# Performance Notes (Slice 15)

All items below were verified in the code before changing. No tool behavior,
UI layout, or registry count changed (registry stays at 332 tools). No build
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
compares revision, running set, and attention count on every tick, and
`sendMessage` itself refreshes the workspace and transcript immediately.

Known limitation: a turn that both starts and finishes inside one 1 s
idle window never fires `onAgentTurnFinished`. The completion callback
fires only for threads observed in `previousRunning` that are gone from
the next poll's running set, and no signal the poll can see identifies a
turn that completed unseen: the engine `revision` is a global counter
bumped by unrelated dispatches (memory, schedules, settings), the
attention count only moves on approvals and questions, and neither the
poll status nor the thread summaries carry a last-finished-turn marker
or a turn-history query. A sub-second turn still refreshes the workspace
through the revision change, so its results appear; only the completion
callback (notification/sound) is skipped. Fixing this needs a new
engine-side finished-turn marker; none was invented here.

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
