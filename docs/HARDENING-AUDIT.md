# Hardening Audit — Slices 71–95

## Summary

Slices 71–90 of the Agents hardening program audited the MCP server, the
memory/workers stores, the Claude/Codex providers, and the workspace file
operations, then swept the whole Rust workspace and the Swift app for
undefined references. The audits fixed 18 defects (2 of them compile breaks
that made both Rust crates unbuildable), made 3 further hardening
improvements in Slice 85, added 18 regression tests, and closed with three
symbol sweeps that found 0 confirmed-missing references. Slice 95, appended
after the wave, audited the thread/document store: 1 further defect fixed, 2
dead store helpers removed, and 1 regression test added — bringing the
totals to 19 defects fixed and 19 regression tests. The remaining
known gaps are listed under [Documented, not fixed](#documented-not-fixed)
instead of being silently dropped. Every SHA, count, and line number below
was verified against the repo at the time of writing (local `main`
`245f84a4`, remote `main` `8d8deca9`, same tree); where a slice's own report
could not be re-checked from the repo (the no-commit sweeps), this record
says so.

**Standing disclosure — read first.** Nothing in this wave was compiled,
executed, or tested in the environment where it was written: there is no
Swift toolchain and no cargo there. Every fix below is statically verified
only (diff read, fixed code lines confirmed present at HEAD, test counts
re-counted from the commits). The Xcode build, `swift test`, `cargo test`,
and live checks on Dylan's Mac are the gate for **all** slices in this
record, exactly as for every earlier slice. Do not report any of this work
as build-verified.

Conventions: SHAs below are the **remote** `main` SHAs (verified against
the GitHub API commit list); local pre-push SHAs differ for API-pushed
slices because the push re-parents the commit, with an identical tree.
Test counts were re-counted from `git show <commit>` (`#[test]` attributes
added, excluding context lines). File:line references are at HEAD
(`245f84a4`) unless noted otherwise.
---

## Slice 71 — MCP server audit (remote `5e5200ab`)

**Audited:** the `coincide-mcp-server` crate — protocol handling, tool
dispatch, asset reads, and the `g6_*` tool implementations. (File paths
in this section are under `Rust Backend/crates/coincide-mcp-server/src/`.)

**Defects fixed (6):**

1. `resources/list` returned a bare JSON array, violating the MCP shape.
   `list_json` now returns `{"resources": [...]}` —
   `Rust Backend/crates/coincide-mcp-server/src/assets.rs:72`.
2. `g6_curl_fetch` followed redirects to any protocol with no size bound.
   curl is now pinned to HTTPS for the initial request and redirects, with
   a 16 MiB cap — `tools.rs:15012-15017` (`--proto =https`,
   `--proto-redir =https`, `--max-filesize 16777216`).
3. `g6_dir_size_recursive` followed symlinks (via `entry.metadata()`)
   with unbounded recursion, so a symlink cycle could loop forever. It now
   uses `entry.file_type()` (symlinks skipped) with a depth cap of 32 —
   `tools.rs:12823-12824`.
4. Asset reads were unbounded and could escape the assets directory via
   symlink. `read_asset_text` now canonicalizes directory and file,
   enforces containment, and caps at 16 MiB (`MAX_ASSET_BYTES`) —
   `assets.rs:8`; all asset reads route through it.
5. `use_mcp` silently dropped object-form `arguments` (only a JSON string
   was accepted; a non-string fell back to `{}`). A non-string `arguments`
   value is now an honest error — `tools.rs:17393`.
6. Notifications (requests with no `id`) fell through to the method check
   and received error responses. They now return no response before any
   method handling — `protocol.rs:65-68`.

**Tests added (4):** `notifications_produce_no_response`,
`use_mcp_rejects_non_string_arguments`,
`derived_data_locate_survives_a_symlink_cycle`,
`resources_ignore_symlinked_asset_files` — all in
`tests/mcp_server.rs`.

**Verification:** Slice 73 re-audited the same crate and found only two
follow-up minors, both fixed there; no Slice 71 fix was found regressed.
The local pre-push commit is `71b0e506` (same tree `d993393b` as remote
`5e5200ab`).

## Slice 73 — MCP server follow-ups (remote `8ab6207d`)

**Audited:** Slice 72's minors against the Slice 71 fixes.

**Defects fixed (2):**

1. Deep directory sizing silently dropped subtrees past the depth cap.
   `g6_dir_size_recursive` now returns an additive `truncated` flag,
   surfaced on the derived-data response — `tools.rs:12823` (signature
   now returns `(i64, usize, bool)`).
2. The asset size bound was enforced by a stat-then-read (TOCTOU — the
   file could grow between check and read). The read is now `Take`-limited
   to `MAX_ASSET_BYTES + 1` bytes, so the bound is enforced on the read
   itself — `assets.rs:99-103`.

**Tests added (2):** `derived_data_locate_flags_deep_tree_truncation`,
`resources_read_rejects_an_asset_over_the_size_limit`.

**Verification:** no later slice re-opened the MCP server asset/sizing
paths. Both fixes confirmed present at HEAD.

## Slice 77 — Memory/workers store audit (remote `6b3b0469`)

**Audited:** the agent memory store and worker store in `coincide-core`
(`memory_store.rs`, `store.rs`, `worker_store.rs`, `workers_api.rs`).
**Defects fixed (5) + 1 dead-code removal:**

1. Memory growth was unbounded. Entries are now capped at 1,000 and total
   stored bytes at 16 MiB, enforced on every store path —
   `memory_store.rs:9-10` (`MAX_MEMORY_ENTRIES`, `MAX_MEMORY_TOTAL_BYTES`).
2. Snapshot self-counting: repeated snapshots counted prior snapshots
   toward the caps. Snapshots no longer count prior snapshots.
3. Snapshot stored-value cap bypass: a snapshot could store a value over
   the per-value cap. The cap is now enforced on snapshot values.
4. Worker results/errors were stored uncapped. Worker text is now capped
   at 64 KiB characters, with a truncation marker noting the full
   transcript remains on the worker thread — `worker_store.rs:11`
   (`MAX_WORKER_RESULT_CHARS`).
5. WAL/`-shm` sidecar files were created with default permissions. They
   are now `chmod 0600` at open — `store.rs:430,569,576`.
6. Dead code removed: `WORKERS_DOCUMENT` had zero references anywhere in
   the workspace (verified: no matches at HEAD) and was deleted.

**Tests added (5):** `store_rejects_new_entry_when_entry_count_cap_reached`,
`store_rejects_new_entry_when_total_byte_cap_reached`,
`repeated_snapshots_do_not_count_prior_snapshots`,
`snapshot_stored_value_stays_within_value_cap`,
`truncate_worker_text_keeps_short_text_and_caps_long_text`.

**Verification:** Slice 79 (below) corrected the byte accounting the caps
depend on; no later slice found a cap bypass.

## Slice 79 — Memory byte accounting (remote `f5e117ab`)

**Audited:** the total-bytes query behind the Slice 77 caps.
**Defect fixed (1):** `memory_total_bytes` counted characters
(`length(entry)`), so multi-byte text under-counted real storage and the
16 MiB cap could be overshot. It now counts bytes via
`length(CAST(entry AS BLOB))` — `store.rs:1817-1819`.

**Tests added (0):** one-line query change; covered by the Slice 77
total-byte-cap test.

**Verification:** no later slice re-opened this query. The byte-counting
form is confirmed present at HEAD.

## Slice 81 — Claude/Codex provider audit (remote `41693867`)

**Audited:** the Claude and Codex provider integrations in `coincide-core`
(`mcp.rs`, `provider_claude.rs`).
**Defects fixed (2):**

1. The Claude MCP config rewrite failed on every turn after the first:
   the config file was created with `create_new`, so the second turn hit
   `AlreadyExists`. The previous turn's file is now replaced when it is a
   regular file; a symlink or directory at that path is refused instead of
   followed or deleted — `mcp.rs:99-119` (refusal message at `:117`).
2. Claude result-frame error text was echoed into persisted transcripts,
   leaking provider error wording into the thread record. Failed-turn
   messages now use fixed strings that never include the raw result frame
   — `failed_turn_message` in `provider_claude.rs:648`.

**Tests added (3):** `claude_config_rewrite_replaces_the_previous_turn`,
`claude_result_error_text_never_reaches_the_transcript`,
`claude_terminal_reason_never_reaches_the_transcript`.

**Verification:** Slice 83 added the symlink-refusal test for fix (1)
(see below). Both fixes confirmed present at HEAD.

## Slice 83 — MAC-GATE count refresh + symlink test (remote `dc36cc22`)

**Audited:** follow-up to Slice 81 plus the Rust test-attribute counts in
`docs/MAC-GATE.md`.
**Defects fixed (0 — count refresh + 1 test):** no new defect; the slice
added the missing symlink-refusal test for the Slice 81 config fix and
refreshed the MAC-GATE counts to **2,949** (2,213 short-form `#[test]` +
736 fully-qualified `#[::core::prelude::v1::test]`).

**Tests added (1):** `claude_config_symlink_is_refused_and_target_untouched`
in `coincide-core/src/mcp.rs` (tests module).

**Verification:** Slice 88 refreshed the counts again to 2,952 (see
below); the 2,949 figure is superseded, kept here for the audit trail.

## Slice 85 — Workspace file-ops audit (remote `07218e04`)

**Audited:** workspace file operations in `coincide-core`
(`workspace_tools.rs`) and `coincide-macos-ffi` (`workspace_ops.rs`).
**Defects fixed (2 CRITICAL compile breaks) + hardening:**

1. `req_str` / `str_param` were never defined in `workspace_tools.rs`
   despite 28 call sites — the crate could not compile. Both helpers were
   restored — `workspace_tools.rs:26,31`.
2. `write_regular_utf8` / `validate_relative_workspace_path` had been
   deleted in Slice 2 with call sites left behind in `workspace_ops.rs` —
   the FFI crate could not compile. Both were restored —
   `workspace_tools.rs:143,626`.
3. `.git` mutation refused: workspace paths containing a `.git` component
   are now rejected by the path validator — `workspace_ops.rs:972`.
4. New-file writes are now atomic (write to a temp file, then rename) —
   `write_regular_utf8` in `workspace_tools.rs:626`.
5. `read_dir` / search responses now carry honest `truncated` flags when
   output is cut at the limit, instead of silently returning partial
   results.

**Tests added (3):** `workspace_paths_refuse_git_internals`,
`write_file_creates_new_files_atomically_without_leftovers`,
`relative_workspace_paths_reject_dot_components_git_and_absolute_paths`.

**Verification:** Slices 87–90 swept the whole workspace for undefined
references (see below) and found 0 confirmed-missing in non-test code,
which corroborates that the restored helpers now resolve. Both restored
helpers and the `.git` refusal are confirmed present at HEAD. The "28 call
sites" figure is as reported by the slice; it was not independently
re-counted.

## Slice 87 — Repo-wide Rust undefined-reference sweep (no commit)

**Audited:** all 6 Rust crates (`coincide-awake-helper`, `coincide-core`,
`coincide-desktop`, `coincide-macos-ffi`, `coincide-mcp-server`,
`coincide-native-host-tests`) for undefined references. Method (as
reported): per-crate module-tree construction plus definition/use
indexing; name-resolution only.

**Result: 0 CONFIRMED-MISSING in non-test code.** Large UNRESOLVED counts
in the raw output are glob imports to external crates (e.g. `gpui`),
generic parameters, and `Self` paths — sampled and judged genuine.

**Limits (as reported):** name-resolution only; arity and types
unverified; no compile. Not a substitute for `cargo test`.

**Tests added (0); commit (none):** nothing to fix, so no commit was
made; no commit object for this slice exists in the repo.

## Slice 88 — MAC-GATE count refresh (remote `8d8deca9`)

**Audited:** the Rust test-attribute counts in `docs/MAC-GATE.md` only.
**Result:** counts refreshed to **2,952** test attributes — 2,216
short-form `#[test]` + 736 fully-qualified
`#[::core::prelude::v1::test]` (`docs/MAC-GATE.md:146,162`; per-crate table
at `:157-162`). No code changed; no defects found.

**Tests added (0); commit:** `245f84a4` locally, remote `8d8deca9`
(local HEAD at the time this record was written).

## Slice 89 — Swift undefined-symbol sweep, Agents app target (no commit)

**Audited:** the `Agents` app target for undefined Swift symbols. Method
(as reported): declaration/candidate indexing across the target's sources.
**Result: 0 CONFIRMED-MISSING** — 66 Swift files (re-verified: `find
Agents -name '*.swift'` returns 66), 258 declarations, 646 candidates
(the file count was re-checked; the declaration/candidate counts were not
independently reproduced).

**Limits:** static name check only; no Swift compile. Not a substitute
for the Xcode build.

**Tests added (0); commit (none):** nothing to fix, so no commit was
made; no commit object exists for this slice.

## Slice 90 — Swift undefined-symbol sweep, remaining targets (no commit)

**Audited:** the remaining 5 Swift targets — `CoincideRemoteKit`,
`AgentsTests`, `CoincideRemoteTests`, `CoincideRemoteUITests`,
`CoincideRemote` (all five directories confirmed present at HEAD).
**Result: 0 CONFIRMED-MISSING.** Same method and limits as Slice 89:
static name check only, no Swift compile.

**Tests added (0); commit (none):** nothing to fix, so no commit was
made; no commit object exists for this slice.

## Slice 95 — Thread/document store audit (remote `5f9644e9`)

**Audited:** the thread/document store in `coincide-core` (`store.rs`,
`store_message_search.rs`, `store_thread_delete.rs`) — draft patching,
thread identity handling, message search, archived-conversation listing,
and delete/Undo.

**Defects fixed (1) + dead-code removal (2):**

1. `patch_draft` used the caller-supplied thread id with `COLLATE NOCASE`
   in every statement and returned that id, so a case-variant id patched
   the stored row but reported the caller's casing — and `patch_thread`
   then re-read the thread through the caller id. `patch_draft` now
   resolves the canonical id first (`SELECT id FROM threads WHERE id=?1
   COLLATE NOCASE`), uses it for the draft revision, navigation, UPDATE,
   and write-marker statements, and returns it; `patch_thread` re-reads
   through the returned id — `store.rs` (`patch_draft`, `patch_thread`).
2. Dead code removed: `Store::archived_conversations` (a thin wrapper over
   `archived_conversations_for_project`) and `Store::message_matches` (a
   wrapper over `message_matches_cancellable` via the message search
   source) had zero production references (verified: no remaining call
   sites at HEAD outside a desktop test name); their test call sites were
   moved to the underlying functions.

**Verified sound (spot-checked):** FTS phrase escaping (quotes doubled
inside the quoted trigram phrase, `store.rs` `summaries_from`);
parameterized CRUD (`?`-bound params throughout); real `DELETE` + Undo
receipt (`thread_delete_undo` temp table, `store_thread_delete.rs:171-187`);
UUID validation (`Uuid::parse_str`, `store.rs:2606`); deferred index
rebuilds; schedule/queue claims revision-checked under the Engine lock;
single-writer connection with `Immediate` transactions; legacy migration
rollback + quarantine (`quarantine_document`, `store.rs:126`); honest
errors on missing threads.

**Tests added (1):** `draft_patch_accepts_a_case_variant_thread_id` in
`store.rs` (tests module) — patches by a lowercased id through both
`patch_draft` and `patch_thread` and asserts the canonical id is returned
and stored.

**Verification:** diff read (`git show 771e645a`, remote `5f9644e9`, same
tree `7dab3229`); fixed lines confirmed present at HEAD. Statically
verified only — no cargo run here, as for every slice in this record. The
local pre-push commit is `771e645a` (same tree as remote `5f9644e9`).
---

## Documented, not fixed

Items the audits found, recorded, and deliberately left open. None of
these is a silent known-bad state: each was an explicit decision, a
limitation of the audited component, or a question owed to Dylan.

- **Worker-record count is unbounded.** One record is created per worker
  spawn and there is no per-record delete or prune path in
  `worker_store.rs` / `workers_api.rs` (verified: no delete/prune function
  there; the only worker-related delete in `store.rs:255,275` removes the
  whole `workers.json` document). Needs Dylan's retention-policy decision
  (Slice 77).
- **MCP server is a sequential loop.** `main.rs` reads and dispatches one
  stdio frame at a time, so a slow `tools/call` blocks all other requests;
  there is no tools/call-level timeout (verified: no `timeout` in `main.rs`
  or `protocol.rs`). The frame itself is size-capped at 16 MiB
  (`main.rs:22`, `MAX_FRAME_BYTES`), but that bounds frame size, not call
  duration. Documented limitation (Slices 31/71).
- **No overall turn-level timeout; context budget is a fixed 2 MiB cap,
  not per-provider.** A browser-only turn timeout exists
  (`browser_protocol.rs:119,148`) — that is not an overall turn timeout.
  The 2 MiB figure appears as fixed caps such as `handoff_prompt.rs:7`
  (`MAX_TEXT`) and the scope check in `follow_up_api.rs:630`.
  (Slices 33/38.)
- **`copy_file` has no size cap.** `fs::copy` copies the whole file
  unbounded — `workspace_tools.rs:324-334`. Contract note from Slice 85,
  not a defect fix.
- **Check-then-open-by-path TOCTOU in workspace reads.** Paths are
  validated by `existing_workspace_target` (`workspace_tools.rs:167`) and
  then opened by path, so the filesystem can change between check and
  open. Closing it needs openat-style traversal (Slice 85).
- **Claude MCP config file is not deleted at end of session.** The only
  `remove_file` on the config path is the per-turn replace in `mcp.rs:119`;
  no session-end cleanup exists. Bounded to one small file per thread
  (Slice 81).
- **Updater is dead in the shipped app; feed hash is unsigned.** The
  updater only runs inside the superseded GPUI desktop behind a
  non-default feature flag, and the native Swift app has no update UI at
  all. The feed hash is not signed (trust rests on TLS plus pinned
  Developer ID code-signature verification at stage time). Full record in
  `docs/updater-audit.md` (Slice 65).
- **Store Privacy URL is the repo URL as a placeholder.**
  `store/APPSTORE.md:66-69` lists `https://github.com/dylans2010/Agents`
  as the Privacy URL (and the Support URL). (Slice 58.)
- **One pre-existing `///` doc comment** at
  `Rust Backend/crates/coincide-core/src/remote_protocol.rs:655`
  ("A phone allowed to connect, as Settings lists it."). Pre-existing,
  not introduced by this wave (Slices 64/70).
- **No Swift compiled in this environment** — restated here because it
  bounds everything above: Xcode build + `swift test` + `cargo test` +
  live checks on Dylan's Mac are the gate for all slices in this record.
- **Thread-document save has no size cap.** `save()` persists the whole
  document value; only the draft field (1 MiB, enforced in `patch_draft`)
  and the title (1,024, import validation) carry caps, so a large document
  is stored unbounded (Slice 95).
- **Unbounded result-set loads in the thread store.**
  `summaries()` has no `LIMIT` in its SQL;
  `archived_conversations_for_project` loads every archived row into a
  `Vec` before paging; `message_matches_cancellable` has no `LIMIT`
  either (Slice 95).
- **`import_legacy` has no per-file/total byte cap.** Files are read whole
  with `fs::read` (`store.rs`), so a large legacy export is imported
  unbounded (Slice 95).
- **Schedule claim atomicity rests on the Engine lock.** The claim is
  revision-checked, but it is atomic only while a single writer holds the
  Engine lock; there is no second-writer lock (Slice 95).
## How to re-verify

- **Registry 332 check.** Count the `ToolDef {` entries inside the
  `DEFINITIONS` slice in
  `Rust Backend/crates/coincide-mcp-server/src/tools.rs:47` — expect 332
  (re-verified at HEAD: exactly 332; one further `ToolDef {` literal
  exists outside `DEFINITIONS`, in test/helper code). Cross-check the same
  332 names, actions, and order against
  `Agents/Core/SystemTools/SystemToolRegistry.swift`; the canonical
  description is `docs/SYSTEM-TOOLSET.md:57-61`.
- **MAC-GATE count method.** From `Rust Backend`, excluding `vendor/`:
  count short-form `#[test]` attributes and fully-qualified
  `#[::core::prelude::v1::test]` attributes, and sum them. At HEAD the
  expected total is **2,953** (2,217 + 736). Method and per-crate table:
  `docs/MAC-GATE.md:143-162`. Known wrinkle documented there: one `//`
  comment line in `crates/coincide-desktop/src/diff_panel_ui_tests.rs:5`
  mentions the glob import and must not be counted as an attribute.
- **Mac-gate checklist.** `docs/MAC-GATE.md` is the single ordered
  checklist for the Mac gate (Xcode build, Swift tests, Rust tests, live
  provider runs, visual/accessibility checks). Run it top to bottom on
  Dylan's Mac against one recorded commit; nothing in this audit record
  counts as passing it.
- **Re-running a slice audit.** Each section above names the files
  audited and the exact fixed lines at HEAD. Re-read the diff of the cited
  remote commit (`git show <sha>`) and confirm the fixed lines are still
  present; if a later commit moved a line, the fix is the code shape
  described, not the line number.
- **Slices with no commit (87, 89, 90).** There is nothing to re-read in
  git for these; re-run the sweep (Rust: per-crate module-tree + def/use
  indexing; Swift: declaration/candidate indexing over the named targets)
  and compare against the 0 CONFIRMED-MISSING result recorded here.
