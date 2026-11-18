# Performance Notes (Slice 15)

All items below were verified in the code before changing. No tool behavior,
UI layout, or registry count changed (registry stays at 337 tools). No build
or test was run for this slice: there is no Swift or Rust toolchain in this
environment, so everything below is statically validated only. The Xcode
build, `swift test`, and `cargo test` runs on Dylan's Mac remain the gate.

## 1. Memory store: per-entry SQLite rows

Before: `memory_store.rs` loaded the whole `memory.json` document
(`Store::document` reads one `documents` row, parses the full JSON), mutated
one entry in memory, and wrote the whole document back
(`Store::save_document` upserts the full JSON string). Every `mem_store`,
`mem_delete`, `mem_clear`, snapshot, and `context_persistence_store` call
was an O(document) read plus an O(document) write.

After: `Store` owns three tables, created on open
(`memory_entries`, `worker_records`, `worker_plans`, plus a scope index):

- `memory_entries(composite_key TEXT PRIMARY KEY, scope TEXT NOT NULL, entry TEXT NOT NULL)`
- `memory_upsert` is one indexed point upsert and reports whether the key
  already existed; `memory_entry` is one point select; `memory_delete` is
  one point delete; `memory_delete_scope` is one indexed delete by scope.
- `memory_entries` (full scan) is used only by list/snapshot, which
  inherently need every entry to filter, sort, and count.

Migration: `Store::open` imports a legacy `memory.json` document (from the
`documents` row, or from an imported original file) into `memory_entries`
exactly once, inside a transaction, then deletes the legacy `documents` row.
The import is skipped whenever the table is already non-empty, so it is
idempotent across processes. A malformed legacy document is left in place
and skipped rather than failing `open`; the new table then starts empty and
memory calls work instead of erroring, which is strictly better
availability than the old path (which errored on every call).

Tool surface unchanged: `mem_store`, `mem_retrieve`, `view_memory`,
`mem_delete`, `mem_clear`, `mem_context_snapshot`, and
`context_persistence_store` keep the same parameters, results, and error
messages. Swift test added in `AgentsTests/ToolsetTests.swift`
(`memoryStorePerEntryRoundTrip`): store two keys, retrieve one, delete it,
retrieve the survivor, retrieve the deleted key and expect failure.

## 2. Workers store: per-entry SQLite rows

Before: `worker_store.rs` loaded the whole `workers.json` document and
rewrote it on every `insert_record`, `save_worker`, `create_plan`, and
`breakdown_plan`. `workers_list` and `workers_status` call `save_worker`
for every running worker on every call, so the rewrite happened per worker
per poll.

After: `worker_records(id TEXT PRIMARY KEY, record TEXT NOT NULL)` and
`worker_plans(id TEXT PRIMARY KEY, plan TEXT NOT NULL)`. Insert, load-one,
and save are single point statements; `save_worker` still errors on an
unknown id, `load_workers` still returns records sorted by `createdAt`,
and plan create/load/breakdown keep their exact behavior. Legacy
`workers.json` migrates the same way as `memory.json` (see above).
`check_spawn_allowed` and `active_workers_for_parent` still scan records
in Rust; worker counts are small (at most 32 running per parent), and the
fixed cost was the rewrite, not the scan.

## 3. AppModel poll loop: adaptive backoff

Before: `AppModel.startPollLoop` slept a fixed 150 ms between
`pollStatus` calls, unconditionally, forever.

After: the interval is 150 ms while a turn is active and 1 s while idle.
Active means the last poll reported `busy`, `running > 0`,
`starting > 0`, or a non-empty `runningThreadIDs`. The flag is seeded
from the initial poll in `bootstrap`, so a turn already running at
startup polls fast from the first tick. Local turn starts
(`sendMessage`, `respondToApproval`, `answerQuestion`) set a 10 s
fast-poll window so the loop is already fast when the engine reports the
new turn; `stopActiveTurn` clears that window. Turns started outside the
app (remote, CLI, scheduled task) are picked up by the next idle poll
within 1 s, at which point the loop drops back to 150 ms. The poll
compares revision, running set, attention count, and the turn-results
serial on every tick, and
`sendMessage` itself refreshes the workspace and transcript immediately.

Turn completion is observed through the engine `turnResults` field in
the `app.status` payload (`thread_activity_api.rs`): a session-global
monotonically increasing `serial` plus the last 64 finished turns as
`recent` entries (`serial`, `threadId`, `outcome` of `completed`,
`failed`, or `interrupted`). The engine records exactly one entry per
finished run when its provider session drains, for every finish path
including cancellation, and the control-server loop drains the engine
every 20 ms, so a turn that both starts and finishes inside one 1 s
idle window is still present in `recent` on the next poll. `AppModel`
keeps a `lastObservedTurnSerial` watermark seeded from the bootstrap
poll and fires `onAgentTurnFinished` exactly once per entry with a
newer serial, in serial order; entries whose thread is gone from the
refreshed workspace still advance the watermark. If the engine
restarts and the serial resets below the watermark, the watermark
adopts the new serial and nothing fires from that poll, so a restarted
session never replays its history as notifications. The old
running-set transition no longer fires the callback: a thread leaves
`running` only when its run is drained, and the drain always records
the turn result first, so the two signals agree on every finish. The
engine `revision` alone would not suffice: it is a global counter
bumped by unrelated dispatches (memory, schedules, settings), and the
attention count only moves on approvals and questions.

## 4. Transcript markdown memoization

Before: `TranscriptScrollView.renderBlocks` rebuilt
`TranscriptRenderBlock.build(from:)` on every body evaluation, and every
`NativeMarkdownView` body re-ran `NativeMarkdownBlock.parse(text)` plus
per-block `AttributedString(markdown:)` inline parsing, for every item in
the transcript, on every streaming tick.

After: two layers, both rendering-identical.

- `TranscriptScrollView` keeps a `@State` `RenderBlockCache` keyed by a
  content hash of the transcript (`Hasher` over `items` and
  `turnChanges`, the exact inputs to `build`). Unchanged transcripts
  reuse the built blocks; only a changed transcript rebuilds.
- `NativeMarkdownView` conforms to `Equatable`, comparing `text`,
  `fontScale`, `usesSerif`, `highlightQuery`, and `workspaceRoot`, so
  SwiftUI skips re-rendering unchanged markdown rows entirely. The
  `onOpenWorkspaceFile` closure is excluded from the comparison: all
  three call sites forward to the same `appModel.openFileInInspector`,
  so it carries no varying render input. The streaming (changing) item
  still re-parses every tick, as it must; completed items parse once.

## 5. MCP control-socket connection reuse

Before: every MCP tool call ran `coincide_core::control::request`, which
opened a fresh Unix socket connection, sent one frame, read one reply,
and closed. The engine side (`control::serve`) accepted one connection,
handled one frame, and dropped it. The `workspace.result` poll loop
alone could open up to 100 connections per git operation.

After: the engine accepts one connection and serves sequential frames on
it until the client disconnects or idles. `ControlClient` (new in
`control.rs`) holds one persistent `UnixStream` per server process and
reconnects once when the request frame itself fails to write, then retries
the request on the fresh connection. A retry happens only on a write
failure, so no complete request frame reached the server and the retried
request cannot be a duplicate execution. If the write succeeds but the
reply read fails or times out, the client does not retry: it drops the
connection and returns the error, because the server may already have
executed the request and a retry could run a mutation twice. The MCP server keeps one `ControlClient` in
`ServerState` (behind a `Mutex`); `engine_request` now calls it instead
of opening a connection per call. One-shot `control::request` (CLI,
desktop, tests) keeps working unchanged on top of the same client.

Protocol constraints, kept deliberately narrow:

- Frames are strictly request-then-response; clients must not pipeline
  frames on one connection. The server reads frames sequentially with a
  single buffered reader, so a pipelined second frame could be lost.
- After the first frame, the server sets a 500 ms read timeout on the
  accepted stream (the first frame keeps the 2 s budget). An idle client
  is reaped after 500 ms and its next call reconnects transparently;
  this also bounds engine-shutdown latency to one dispatch plus 500 ms.
  The engine still polls between frames.
- A retry happens only when the request frame failed to write, so the
  server never received a complete request and the retry cannot duplicate
  an execution. A lost reply is reported to the caller as an error, never
  silently re-executed; the caller sees the read failure and can check
  engine state before deciding whether to issue the request again. The
  one-shot `control::request` path shares the same client, so the same
  guarantee holds there.
- Windows is unchanged: `ControlClient::call` delegates to the existing
  one-shot named-pipe `request` there, since the Windows transport is
  one frame plus an acknowledgement byte per connection.

## 6. MCP server robustness (Slice 31)

No build or test was run for this slice: there is no Swift or Rust
toolchain in this environment, so everything below is statically
validated only. The `cargo test` run on Dylan's Mac remains the gate,
including the new
`oversized_invalid_utf8_and_non_object_frames_get_errors_and_the_server_survives`
test in `coincide-mcp-server/tests/mcp_server.rs`, which is
written-not-executed here. Registry unchanged: 332 Swift = 332 Rust,
0 mismatches (Python replication of
`tool_table_matches_swift_registry`, including param descriptions).

### Fixed: unbounded stdio frame (main.rs)

Before: the stdio loop used `BufRead::read_line` into a reused `String`
with no length limit, so one provider sending a 100 MB line (or a line
that never ends) grew the server's memory without bound, and an
invalid-UTF-8 line made `read_line` return `Err`, which ended `run()`
and killed the server for every provider. A valid-JSON non-object
frame (for example `[1, 2, 3]`) was answered with -32700 (Parse error),
which the JSON-RPC spec reserves for invalid JSON.

After: `read_frame_line` reads through `fill_buf`/`consume` with a
16 MiB cap on frame content (plus the newline). A frame over the cap
is drained through its newline (so the next frame still parses) and
answered with -32700, and the loop continues. A frame that is not
valid UTF-8 is answered with -32700 and the loop continues, because
the bytes are read first and validated with `String::from_utf8`
afterwards instead of letting `read_line` fail the whole process.
A valid-JSON non-object frame is now answered with -32600 (Invalid
Request) via the new `protocol::invalid_request_response`. The 16 MiB
bound is sized from the largest legitimate inbound frame: local file
tools cap content at 3 MiB (`MAX_FILE_WRITE_BYTES` in
`workspace_tools.rs`, enforced by both `write_file` and the
`read_workspace_text` read path), and engine-routed calls are capped
by the 4 MiB control-socket frame (`MAX_FRAME` in `control.rs`), so
16 MiB is more than 5x the largest legitimate argument payload and
4x the control frame. Outbound tool results are unaffected: they are
written with no cap, and engine results are already bounded by the
4 MiB control frame on the reply side.

### Verified already correct, left untouched

- One malformed frame never killed the loop: a `serde_json` parse
  failure already produced a -32700 response and continued, and
  deeply nested JSON fails inside `serde_json::from_str::<Value>`
  under the default 128-deep recursion limit (no `unbounded_depth`
  feature in `Cargo.toml`), so it is a -32700, not a stack overflow.
- `tools/call` argument validation returns -32602 for a missing name
  and for non-object arguments (`protocol.rs` `call_tool`), unknown
  tools return -32602 (`tools.rs` `call`, both the upfront
  `definition` check and the catch-all arm), engine-unreachable
  returns a result with `isError: true` so a request with an id
  always gets a response, and `prompts/get` with no stored prompt
  returns -32602. An object with no method returns -32600 with its
  id. Notifications (no id) get no response, as specified.
- stdin EOF exits 0 (`FrameRead::Eof` returns `Ok(())`, covered by the
  existing `stdin_eof_exits_cleanly` test). SIGPIPE is ignored by the
  Rust runtime, so a dead provider turns the response write into an
  EPIPE error and the process exits 1 instead of dying on the signal
  or wedging in a write loop; every response is flushed explicitly,
  so SIGTERM cannot lose a buffered response. A broken stdout ends
  the process on the first failed write.
- No `unwrap`/`expect` reachable from hostile tool input can panic
  the server: the yaml colon unwraps are guarded by `is_some()`
  checks on the same value, `whole_word_replace` returns early on an
  empty search string, `g6_xcstrings_set` forces objects before
  unwrapping, the JSON-to-CSV unwrap runs only after a loop that
  rejects every non-object record, and `code_mutation_engine`
  unwraps the symbol only after proving it is `Some`. The remaining
  `expect` calls are in the `#[cfg(test)]` Swift-registry parser.
- `ServerState` accumulates no per-call state, and the `ControlClient`
  `Mutex` is held only across one `engine_request` at a time.

### Known limitation, documented not fixed: sequential loop blocking

The server loop handles one request at a time, so a slow `tools/call`
stalls every other provider's calls until it finishes. Every path is
already bounded, so this is a latency problem, not a hang: the poll
loops cap at 100 x 100 ms (`workspace.result`), 1200 x 100 ms
(`git.workspace.result`, about 120 s), 60 x 250 ms
(`computer_use.result`), and `timeoutSeconds * 4` polls at 250 ms
for `git.actions.result` (up to 600 s for `git_push`/`git_pull`),
and `run_terminal_command` clamps its caller timeout to 5..3600 s;
each control-socket round-trip carries the
10 s read timeout from `connect_stream`. No `tools/call`-level
timeout was added, because the legitimate ceiling is a long build:
`run_build`/`run_tests` default to 600 s and allow up to 3600 s, so
any timeout short enough to matter would break real builds, and any
timeout long enough to allow them would not bound the stall
meaningfully. Fixing this properly needs a concurrent loop or
per-call worker threads, which is a protocol-transport change, not a
minimal robustness fix. The `ControlClient` mutex is the same issue,
not a separate one: the loop is sequential, so the mutex never
contends with a second call while one is in flight.
