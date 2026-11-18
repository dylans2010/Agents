# Hardening Audit — Slices 71–150

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
totals to 19 defects fixed and 19 regression tests. Slices 99–101,
appended after that, pinned session identity over model-supplied thread
ids on both sides of the registry: 3 further defects fixed, 2 dead
helpers removed, and 6 regression tests added. Slice 102 verified the
Swift registry read-only and found 1 pre-existing HIGH type error (fixed
in Slice 103, no test added), and Slice 104 re-verified Slice 103 with a
pass-with-minors verdict — bringing the totals to **23 defects fixed and
25 regression tests**. Slice 109, appended after that, closed the last
thread-identity description gap (`session_progress_report`, both
registries; no behavior change, no test added). Description-only
corrections are not counted in the defect/test totals, following the
Slice 105 precedent, so the totals stay at **23 defects fixed and
25 regression tests**. Slice 118, appended after that, audited the
OpenCode, Grok, Cursor, and Antigravity provider integrations: 2 further
defects fixed and 2 regression tests added — bringing the totals to
**25 defects fixed and 27 regression tests**. Slice 122, appended after
that, audited the Swift app UI (Liquid Glass consistency, accessibility
close-out, dead UI, hardcoded colors): 4 further defects fixed and 0
regression tests added — bringing the totals to **29 defects fixed and
27 regression tests**. The Slice 122 correction of the Slice 118
`provider_transport.rs` line cite is description-only and not counted,
following the Slice 105/109 precedent. Slice 124, appended after that,
fixed the Slice 123 findings and backfilled the Slice 122 remote SHA —
all description-only, following the Slice 105/109 precedent, so the
totals stay at **29 defects fixed and 27 regression tests**. Slice 126,
appended after that, qualified the Slice 124 diff-row combined-children
claim — all description-only, following the Slice 105/109 precedent, so
the totals stay at **29 defects fixed and 27 regression tests**. Slice 128,
appended after that, audited the GPUI desktop crate
(`coincide-desktop`) — CI-built but not shipped — across the updater,
credentials, download, open-target, terminal-handoff, FFI, import, and
collection-cap surfaces and found 0 defects — all description-only,
following the Slice 105/109 precedent, so the totals stay at
**29 defects fixed and 27 regression tests**. Slice 130,
appended after that, corrected the Slice 128 Rust test-total figures
(3,003 → 3,002 real, desktop 1,149 → 1,148 real — the raw short-form
count had included the one `//` comment line at
`diff_panel_ui_tests.rs:5`), fixed the `rust.yml` job cite, and
backfilled the Slice 128 remote SHA — all description-only, following
the Slice 105/109 precedent, so the totals stay at
**29 defects fixed and 27 regression tests**. Slice 134,
appended after that, isolated MCP server dispatch panics: per-request
dispatch is now wrapped in `catch_unwind`, a panicking handler returns a
fixed-message `-32603` error, and the server keeps serving subsequent
requests — 1 further defect fixed and 1 regression test added, bringing
the totals to **30 defects fixed and 28 regression tests**. Slice 138, appended after that, audited Swift
`SystemToolRegistry.execute()` handler-arm coverage across all 333
registered tools and found 0 missing arms, 0 dead arms, and 0 defects —
every definition is reachable, including through the shared
multi-name arms, and the fallback for an unhandled tool is the honest
`unknownTool` error, not a wrong result — all description-only,
following the Slice 105/109 precedent, so the totals stay at
**30 defects fixed and 28 regression tests**. Slice 144, appended after
that, fixed the two real defects from Slice 141's audit plus the cheap
cwd pin it recommended — a 5 GiB `copy_file` cap with a free-space
reserve and partial-dest cleanup, a final-symlink refusal on both
`read_file` paths, and `with_session_defaults` now overwriting a
model-supplied `cwd` with the session cwd — 3 further defects fixed and
5 regression tests added, bringing the totals to **33 defects fixed and
33 regression tests**. Slice 146, appended after that, fixed the two
MAJOR findings from Slice 145's re-verification of Slice 144 — the
literal `.git/config` read on the paged path and the intermediate-
directory symlink bypass on both read paths — plus the two MINOR doc
corrections it raised, and added 4 regression tests, bringing the
totals to **35 defects fixed and 37 regression tests**. The two MINORs
are description-only and not counted as defects, following the Slice
105/109 precedent. Slice 148, appended after that, added success-path
`execute()` tests for the highest-value registry tools Slice 143 found
untested — 0 defects fixed and 15 regression tests added, bringing the
totals to **35 defects fixed and 52 regression tests**. Slice 150,
appended after that, fixed Slice 149's MAJOR finding from its
re-verification of Slice 148 — the `read_file` success-path test
expected content without the trailing newline the Swift `execute()`
path actually returns verbatim — plus the two MINOR doc corrections
it raised, and backfilled the Slice 148 remote SHA — 1 further
defect fixed and 0 regression tests added, bringing the totals to
**36 defects fixed and 52 regression tests**. The two MINORs are
description-only and not counted as defects, following the Slice
105/109 precedent. The remaining
known gaps are listed under [Documented, not fixed](#documented-not-fixed)
instead of being silently dropped. Every SHA, count, and line number below
was verified against the repo at the time of writing (local `main`
`245f84a4`, remote `main` `8d8deca9`, same tree); where a slice's own report
could not be re-checked from the repo (the no-commit sweeps), this record
says so. The Slices 99–103 sections below were verified against local
`main` `cca948d3`, remote `main` `b45b5690`, same tree `b172259e`.

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

## Slice 99 — Computer-use engine audit (remote `6e0c9dff`)

**Audited:** the computer-use engine path — `with_session_defaults` in
`coincide-mcp-server` (`tools.rs`), `Extended` in `coincide-core`
(`computer_use.rs`), and `Bridge` (`computer_use_bridge.rs`).

**Defects fixed (1) + dead-code removal (2):**

1. `with_session_defaults` only filled `threadId` when the model had not
   supplied one, so a model-supplied `threadId` overrode the session
   thread. It now overwrites unconditionally when the server is bound to
   a session thread — `tools.rs:7819` (function), `:7829-7830`
   (overwrite). A server without a session id keeps the supplied value.
2. Dead code removed: `Extended::tool()` in `computer_use.rs` (18 lines,
   zero call sites) and `Bridge::threads()` in `computer_use_bridge.rs`
   (zero call sites outside its own tests; the two test assertions using
   it were removed with it). Verified: no remaining references at HEAD.

**Tests added (1):**
`session_thread_identity_wins_over_model_supplied_thread_id` in
`tools.rs:21335` (tests module) — a bound session wins over a
model-supplied id and fills an omitted one; an unbound server keeps the
supplied id.

**Verification:** diff read (`git show 7df7cfb3`, remote `6e0c9dff`, same
tree `72029b0c`); fixed lines confirmed present at HEAD. Statically
verified only — no cargo run here, as for every slice in this record. The
local pre-push commit is `7df7cfb3` (same tree as remote `6e0c9dff`).

## Slice 100 — MCP worker identity pin (remote `b98da65c`)

**Audited:** `parentThreadId` handling in the MCP worker tools
(`tools.rs` `call()` plus `default_parent_thread`).

**Defects fixed (1):**

1. `default_parent_thread` only filled `parentThreadId` when absent, so a
   model-supplied `parentThreadId` could steer worker spawn/plan/list/
   breakdown calls to another thread. It now overwrites unconditionally
   when the server is bound — `tools.rs:21202` (function). `list_workers`
   (`:17069`) and `intel_breakdown_task` (`:17081`) are newly routed
   through it; `use_workers` / `intel_plan_task` / `execution_plan`
   (`:17065`) and `start_subagent` (`:17419`) already were, so all six
   `parentThreadId`-bearing tools are now pinned. A server without a
   session id keeps the supplied value.

**Tests added (1):**
`session_parent_identity_wins_over_model_supplied_parent_thread_id` in
`tools.rs:21369` — mirrors the Slice 99 test for `parentThreadId`.

**Docs:** the worker paragraph in `docs/SYSTEM-TOOLSET.md` now states
spawn/plan/list/breakdown calls always run under the session thread id.

**Verification:** diff read (`git show bc11ecd1`, remote `b98da65c`, same
tree `42d67439`); fixed lines confirmed present at HEAD. Statically
verified only. The local pre-push commit is `bc11ecd1` (same tree as
remote `b98da65c`).

## Slice 101 — Swift-side parent identity pin (remote `e256255f`)

**Audited:** `SystemToolRegistry.execute()` in Swift
(`Agents/Core/SystemTools/SystemToolRegistry.swift`).

**Defects fixed (1):**

1. `execute()` passed model-supplied `threadId` / `parentThreadId`
   through untouched, so the Swift mirror did not pin session identity
   the way the Rust server does since Slices 99–100. `execute()` now
   takes an opt-in `sessionThreadId: String? = nil` parameter (`:3826`,
   parameter at `:3831`) and, when non-empty, overwrites both ids in the
   arguments (`:3834-3836`); the `use_mcp` recursion threads it through
   (`:4392` case, `:4422` call). Calls without one keep the supplied
   values.

**Tests added (4):** in `AgentsTests/WorkersTests.swift` —
`sessionThreadWinsOverModelParent` (`:210`),
`sessionThreadWinsForBreakdown` (`:246`),
`sessionThreadWinsThroughUseMcp` (`:275`),
`sessionThreadWinsOverModelThreadId` (`:294`).

**Docs:** the worker paragraph in `docs/SYSTEM-TOOLSET.md` now records
the Swift mirror pin alongside the Rust one.

**Verification:** diff read (`git show 856701b6`, remote `e256255f`, same
tree `4524ec75`); fixed lines confirmed present at HEAD. Statically
verified only. The local pre-push commit is `856701b6` (same tree as
remote `e256255f`).

**Open after this slice:** the registry param descriptions still read
"Parent thread ID that owns the workers." / "Owning thread ID.", wording
from before the pin. They were corrected to match the pinned behavior in
a joint Swift/Rust description pass pushed with this record (Slice 105),
which also updated the pinned expectations in
`AgentsTests/ToolsetTests.swift`.

## Slice 102 — Swift registry read-only verification (no commit)

**Audited:** `SystemToolRegistry.execute()` return types, read-only; no
code changed.

**Result: NOT CLEAN — 1 pre-existing HIGH type error found.** Three plan
cases returned `WorkerPlan` where `execute()` promises `JSONValue`:
`intel_plan_task` (`:4116`), `intel_breakdown_task` (`:4119`), and
`execution_plan` (`:4124`), at the pre-fix commit `856701b6`. Counts
re-measured at the time: Swift `@Test` 128, Rust 2,955 (short-form +
fully-qualified only; the 45 `#[gpui_kit::test]` attributes were not yet
counted — corrected to 3,000 by Slice 104).

**Tests added (0); commit (none):** verification only; the defect was
fixed in Slice 103 (below).

**Verification:** the three bare `WorkerPlan` returns are visible in
`git show 856701b6:Agents/Core/SystemTools/SystemToolRegistry.swift` and
in the Slice 103 diff (minus lines).

## Slice 103 — WorkerPlan-to-JSONValue fix (remote `b45b5690`)

**Audited:** the Slice 102 HIGH type error.

**Defects fixed (1):**

1. The three plan cases now wrap their `WorkerPlan` results in the new
   `workerPlanJSON` helper — `SystemToolRegistry.swift:11582` (helper),
   used at `:4116` (`intel_plan_task`), `:4119` (`intel_breakdown_task`),
   and `:4124` (`execution_plan`). All 275 `return` statements in
   `execute()` were audited (re-counted at HEAD: `execute()` spans
   `:3826-7518` and holds exactly 275 returns); the three plan cases were
   the only `WorkerPlan` leaks.

**Tests added (0):** no test added; 1 file, +50/−3.

**Verification:** diff read (`git show cca948d3`, remote `b45b5690`, same
tree `b172259e`); fixed lines confirmed present at HEAD. Statically
verified only — no Swift compile here, as for every slice in this record.
The local pre-push commit is `cca948d3` (same tree as remote `b45b5690`).
Slice 104 re-verified this slice; see [How to re-verify](#how-to-re-verify).
---

## Slice 105 — Joint threadId description pass (remote `741c8582`)

**Audited:** every `threadId` / `parentThreadId` parameter description
in both registries — `Agents/Core/SystemTools/SystemToolRegistry.swift`
and `Rust Backend/crates/coincide-mcp-server/src/tools.rs` — against
the session pin each value already carries at runtime (Slices 99–101).

**Descriptions corrected (124 Swift lines / 80 Rust lines):** the
pinned phrase ", pinned to the session thread when bound" was added to
124 Swift description lines and 80 Rust description lines, including
the shared Rust `P_THREAD_ID` const (`tools.rs:34-39`, description at
`:38`), which covers 45 `threadId` params. Five descriptions still
lacked pinning language after this pass: the four `parentThreadId`
descriptions (`list_workers`, `intel_plan_task`,
`intel_breakdown_task`, `execution_plan` — pinned in Slice 107) and
`session_progress_report`'s `threadId` (pinned in Slice 109). No
behavior change; the descriptions now match the pin the handlers
already apply.

**Tests added (0):** no test added; 3 pinned expectations updated in
`AgentsTests/ToolsetTests.swift` (`run_build`, `run_tests`,
`search_web`) to match the corrected descriptions. Description-only
corrections are not counted in the defect/test totals, per the
precedent this slice set (see Summary).

**Docs:** this record's Slices 99–103 sections were written in this
slice; `docs/MAC-GATE.md` refreshed to 128 Swift `@Test` and 3,000 Rust
test attributes (2,219 short-form + 736 fully-qualified + 45
`#[gpui_kit::test]`, correcting 2,953); `docs/SYSTEM-TOOLSET.md`
history extended to Slices 99–104.

**Verification:** diff read (`git show 9cadcd38`, remote `741c8582`,
same tree `6325d57d`); corrected lines confirmed present at HEAD.
Statically verified only — no Swift compile here, as for every slice in
this record. The local pre-push commit is `9cadcd38` (same tree as
remote `741c8582`). Slice 106 re-verified this slice; see
[How to re-verify](#how-to-re-verify).
---

## Slice 107 — ParentThreadId description pins (remote `27dabf95`)

**Audited:** the four `parentThreadId` descriptions that still lacked
pinning language after Slice 105, in both registries.

**Descriptions corrected (4 lines per side):** `list_workers`
("Parent thread ID, pinned to the session thread when bound; lists
every worker when omitted and unbound."), `intel_plan_task` and
`execution_plan` ("Parent thread ID that owns the plan, pinned to the
session thread when bound."), and `intel_breakdown_task` ("Parent
thread ID the plan must belong to, pinned to the session thread when
bound.") — byte-identical on both sides. After this pass the only
description still lacking pinning language was
`session_progress_report`'s `threadId`, closed in Slice 109. No
behavior change.

**Tests added (0):** no test change. Description-only corrections are
not counted in the defect/test totals, per the Slice 105 precedent.

**Docs:** two nits in this record fixed — the `use_mcp` line cite in
the Slice 101 section (`:4419` corrected to `:4392`) and the
ToolDef-count wording in [How to re-verify](#how-to-re-verify) (the one
further `ToolDef {` match is the `pub struct ToolDef {` declaration at
`tools.rs:14`, not a registry entry).

**Verification:** diff read (`git show 2a0261d8`, remote `27dabf95`,
same tree `667422d1`); corrected lines confirmed present at HEAD.
Statically verified only — no Swift compile here, as for every slice in
this record. The local pre-push commit is `2a0261d8` (same tree as
remote `27dabf95`). Slice 108 re-verified this slice; see
[How to re-verify](#how-to-re-verify).
---

## Slice 109 — Thread-identity description sweep complete (remote `23a73f2d`)

**Audited:** every `threadId` / `parentThreadId` parameter description
in both registries — `Agents/Core/SystemTools/SystemToolRegistry.swift`
and `Rust Backend/crates/coincide-mcp-server/src/tools.rs` —
re-enumerated from source, not trusted from the Slice 106 inventory.

**Descriptions corrected (1):** `session_progress_report`'s `threadId`
read "Parent thread ID to include worker status for." with no pinning
language, although the value is pinned when bound: Swift `execute()`
overwrites `threadId` for every tool (`:3835`) before the handler reads
it to list workers (`:7104`), and Rust `call()` applies
`with_session_defaults` at entry (`:16896`; function `:7819-7833`)
before the handler reads it for `workers.list` (`:16477`). The
description now reads "Parent thread ID to include worker status for,
pinned to the session thread when bound.", byte-identical on both sides.

**Sweep result:** 129 identity params per side (123 `threadId` + 6
`parentThreadId`). Swift holds all 123 `threadId` params inline; Rust
holds 78 inline plus 45 via the shared `P_THREAD_ID` const
(`tools.rs:34-39`) and 6 inline `parentThreadId` params. All 6
`parentThreadId` descriptions already carried pinning language
(`use_workers`, `list_workers`, `intel_plan_task`,
`intel_breakdown_task`, `execution_plan`, `start_subagent`; the last
four pinned in Slice 107). After this fix all 129 carry it on both
sides, and the effective descriptions are byte-identical cross-side
(const-resolved). No other description lacked pinning language; none
was left unchanged as inapplicable.

**Tests added (0):** `sliceTwentyTwoParamDescriptionsPinned` in
`AgentsTests/ToolsetTests.swift` pins six (tool, param, description)
triples, none of them `session_progress_report`, and the old wording
appeared nowhere in `AgentsTests`. The Rust
`tool_table_matches_swift_registry` test parses the Swift registry
dynamically and compares every param description, so the identical
change on both sides keeps it consistent. Registry counts unchanged at
333 tools per side.

**Verification:** sweep re-run after the edit (129/129 params, 0
lacking pinning language, 0 cross-side mismatches); zero occurrences
of the old wording remain in either registry or the test. Statically
verified only — no Swift compile here, as for every slice in this
record. Sweep baseline: local `main` `2a0261d8`, remote `main`
`27dabf958a`, same tree `667422d1`. The local pre-push commit is
`02251181` (same tree as remote `23a73f2d`).
Slice 110 re-verified this slice; see [How to re-verify](#how-to-re-verify).

## Slice 118 — OpenCode/Grok/Cursor/Antigravity provider audit (remote bf146ce8)

**Audited:** the four provider integrations that had never had a
dedicated defect audit — OpenCode (`provider_opencode.rs`,
`provider_opencode_http.rs`, `provider_opencode_forms.rs`,
`provider_opencode_lithos.rs`, `provider_opencode_metadata.rs`), Grok
(`provider_grok.rs` plus the shared `provider_acp.rs`
`run_grok`/`run_flavored`), Cursor (`provider_cursor.rs`,
`provider_cursor_questions.rs`, `provider_cursor_profile.rs`,
`provider_cursor_auth.rs`), Antigravity (`provider_antigravity.rs`,
`provider_antigravity_files.rs`, `provider_antigravity_profile.rs`,
`provider_antigravity_api.rs`) — each traced session creation → MCP
mount or explicit rejection → prompt injection → turn execution →
stop-reason/result handling → error paths → shutdown/cleanup, plus the
shared `provider_transport.rs` frame bounds and `mcp.rs` mount path,
the `agent.rs` dispatch and failure path, and the Swift-side toolset
gate. Statically verified only — no build or test run here, as for every
slice in this record.

**Defects fixed (2):**

1. **OpenCode turn failure echoed provider error text**
   (`provider_opencode.rs:503-508`). `Mapper::handle` bailed
   `"OpenCode turn failed: {}"` with `data["error"]["message"]`
   verbatim from the `session.execution.failed` SSE event. The error
   becomes `Event::Failed` (`agent.rs:520`), so the provider's own
   words — which may carry secrets, paths, or multi-line content —
   reached the user-visible/persisted turn failure. Same defect class
   Slice 43 fixed in Grok/Cursor stop reasons and Slice 81 fixed in
   Claude result frames. Now a fixed string, `bail!("OpenCode turn
   failed")` (`:503-505`); the full frame is still emitted live as a raw
   `provider/event` frame, as for every provider (`raw()` at
   `provider_opencode.rs:1071` → `provider_transport.rs:455-460`), though
   it is not appended to the persisted transcript — the transcript
   handler's `provider/event` arm only extracts composer commands
   (`api.rs:3345-3376`), and command-less frames are treated as ignorable
   (`api.rs:3779-3781`).
2. **Antigravity resume treated capability presence as capability
   enabled** (`provider_antigravity.rs:385-388`). The stage-2 resume
   branch chose `session/resume` whenever
   `sessionCapabilities.resume` was present
   (`.get("resume").is_some()`), even when the agent advertised
   `"resume": false` — unlike the adjacent `loadSession == true`
   check. A `"resume": false` agent would then be sent
   `session/resume`, reject it, and fail the turn loudly at stage 3
   instead of falling back to `session/load`. Now an `offers_resume`
   helper (`:34-36`) requires the value to be `true`, matching the
   `loadSession` idiom.

**No defects found in Grok or Cursor.** Grok:
`validate_stop_reason` already emits fixed strings only
(`provider_grok.rs:114-120`); `completion` pins session/prompt
identity and validates before completing; questions are capped at 20
with duplicate-text/ID guards; `question_params` carries the raw
provider frame only as `providerFrame`, the established pattern.
Cursor: `error_report` already reduces provider text to fixed
classifications (`provider_cursor.rs:48-85`), so the held-error bail
at `:378` carries only a classification; stop drains pending requests
with cancelled replies; stage-2 resume pins the returned session ID;
the private profile import is size-bounded (64 MiB) and
symlink-checked. Shared paths also checked clean: `session_servers`
bails loudly when the MCP binary is missing (`mcp.rs:93-97`);
`Transport` inbound/outbound frames are capped at 32 MiB with a
64 MiB queue (`provider_transport.rs:6-8`); OpenCode HTTP responses
and SSE frames are capped at 8 MiB (`provider_opencode_http.rs:6`);
the OpenCode rejection of System Tools is loud at thread creation
(`agent.rs:721-727`, via `bot_engine.rs:180`,
`remote_adapter.rs:1670`, `thread_defaults.rs:293`); missing provider
binaries fail loudly at spawn (`transport.rs`, "Unable to launch
provider"); `exit_status_text` is numeric only (`agent.rs:830-851`).

**Tests added (2):**
`execution_failure_never_carries_provider_error_text`
(`provider_opencode.rs:1214`, drives a hostile
`session.execution.failed` frame through `Mapper::handle` and asserts
the exact fixed string) and
`resume_requires_an_enabled_capability_not_mere_presence`
(`provider_antigravity.rs:520`, `true` → resume, `false` / missing /
empty → load). Written-not-executed, as for every slice in this
record.

**Verification:** re-read of both changed hunks; zero new `//`
comments in added lines; registry counts unchanged at 333 tools per
side (Swift `SystemToolDefinition(` 333; Rust `ToolDef {` 334 raw
incl. the struct declaration at `tools.rs:14`); `git diff --stat`
shows only the two provider files plus this record and the
`SYSTEM-TOOLSET.md` hardening entry. Rust `#[test]` total in `Rust
Backend/crates/` is 2,222 after this slice (was 2,220). Audit
baseline: local `main` `d6f55594`, remote `main` `cc09b357`, same tree
`e6d48ac26eda0705c68c361f4368aa1c8fbf7039`. The local pre-push commit is
`50a42e70` (tree `29fbdddc9d4095c7934e518af58956406d84fe6f`, same tree as
remote `bf146ce8`).

## Slice 122 — Swift UI audit: Liquid Glass consistency, accessibility close-out, dead UI (remote `1acbed3c`)

**Audited:** the Swift app UI only (`Agents/`, 66 Swift files; Rust and
the iOS companion untouched) — every `glassEffect` / `glassBackground` /
`material(` use; the 3 unresolved Slice 32 accessibility items; a sweep
for unlabeled controls added since Slice 32; buttons/menu items/views in
the workspace/history/inspector/composer surfaces for empty, no-op, or
TODO actions; hardcoded `Color(` / `.white` / `.black` / hex literals in
UI code added since Slice 7. Statically verified only — no build or test
run here, as for every slice in this record.

**Defects fixed (4):**

1. **Composer `NSTextView` had no accessibility label**
   (`Agents/Conversation/ComposerNSTextView.swift:100,128`). The
   composer is an AppKit `NSTextView` in an `NSScrollView` via
   `NSViewRepresentable`, and its placeholder is drawn by hand in
   `draw(_:)`, so VoiceOver had no prompt text for the field. Now
   `textView.accessibilityLabel = placeholder` in `makeNSView`, re-synced
   in `updateNSView` alongside the existing placeholder sync, so the
   label tracks the dynamic placeholder ("Ask …", "Steer or queue a
   follow-up message…"). Setting the label is AppKit metadata only;
   whether VoiceOver announces it without double-announcing typed text
   is a Mac-gate check (see below).
2. **Diff file row was not VoiceOver-activatable**
   (`Agents/Inspector/DiffInspectorView.swift:798-800`).
   `DiffFileSummaryRow` selects on `.onTapGesture(perform: onSelect)`
   with no accessibility element, so VoiceOver could read the row's text
   but not activate it. Now `.accessibilityElement(children: .combine)`
   + `.accessibilityAddTraits(isSelected ? [.isButton, .isSelected] :
   .isButton)` + `.accessibilityAction { onSelect() }`, following the
   `TerminalDrawerRootView` row's traits pattern — the identical
   `.accessibilityAddTraits(isSelected ? [.isButton, .isSelected] :
   .isButton)` expression at `TerminalDrawerRootView.swift:712` (which
   additionally carries an explicit label at `:711`; this row relies on
   the combined children reading naturally instead). The
   `.accessibilityElement(children: .combine)` +
   `.accessibilityAction` mechanism itself is new here: those two
   modifiers appear nowhere else in `Agents/` — this is their first use
   (`DiffInspectorView.swift:798,800,1122,1125`). No explicit label: the
   combined children (file name, directory, +N/−M counts) already read
   naturally when not hovered — three hover-revealed buttons
   (`DiffInspectorView.swift:727-758`) also sit inside the combined element
   when hovered, but their actions are duplicated in the context menu — and
   a label would duplicate the visible file name (Slice 34
   rule).
3. **Diff line-number gutter was not VoiceOver-activatable**
   (`Agents/Inspector/DiffInspectorView.swift:1122-1128`).
   `UnifiedDiffLineRow`'s gutter jumps to the line in the Inspector
   Editor on tap, with the action described only by a `.help` tooltip.
   Now a combined element + `.accessibilityLabel` reusing the tooltip
   text when `canJumpToLine` ("Open at line N in Inspector Editor", else
   "Line N") + the `.isButton` trait only when jumpable +
   `.accessibilityAction` guarded by the same `canJumpToLine` check as
   the tap handler.
4. **Dead "Mark as Read" menu item in the thread context menu**
   (`Agents/Sidebar/SidebarThreadRow.swift:333-339` after the fix; the
   removed item was at `:334-340` before it). In the already-read branch
   (`thread.unseen == nil`) the menu showed a permanently `.disabled(true)`
   "Mark as Read" item whose action called `.markUnread` — a copy-paste
   of the sibling button, so even enabled it would have done the opposite
   of its label. Removed; the branch now shows only the working "Mark as
   Unread" item. The unread branch (`unseen != nil`) already shows the
   working "Mark as Read" (`markSeen`) item and is unchanged.

**No defects found in Liquid Glass consistency.** The three `AppTheme`
helpers remain the only real `glassEffect` call sites
(`AppTheme.swift:324,328,332`); their 8 use sites are all chrome — toast
(`MainWindowView.swift:120`), composer (`ComposerBarView.swift:211`),
composer cards (`ComposerBarView.swift:1173,1261`), approval/question
cards (`PendingAttentionView.swift:164,346`), Jump to Latest pill
(`TranscriptScrollView.swift:182`), terminal banner
(`TerminalDrawerRootView.swift:444`) — and no glass sits on conversation
content, lists, or editor surfaces. The only other `glassEffect` hit is a
string literal in a code-snippet template
(`SystemToolRegistry.swift:11057`, the "glasscard" snippet the tool emits
for users), not a UI call site; left as-is. The single `material(` use is
`.thinMaterial` on the sidebar footer bar (`SidebarRootView.swift:675`),
introduced by Slice 7 itself; left as-is.

**No defects found in hardcoded colors.** No `.white` / `.black` /
`Color(red:` / hex literal was added to UI code since Slice 7
(`bb71be67`). Every existing instance is a deliberate fixed-contrast use:
white text on accent/warning/danger fills (badge counts in
`ConversationRootView.swift:359`, `SidebarRootView.swift:813`,
`SidebarThreadRow.swift:194`; Stop/Send buttons in
`ComposerBarView.swift:657,685`), white on the media-overlay scrim
(`MediaLightboxSheet.swift:154,167,170`), white behind the pairing QR code
(`RemoteSettingsPane.swift:142`, QR codes must scan on white), and the
white checkmark on user-chosen tint swatches
(`BotEditorSheet.swift:288-289`). The `NSColor.white/black` alpha blends
in `AppTheme.swift:115-116,124-125` and
`NativeCodeEditorNSView.swift:378-379,423-424` are the adaptive theme
definitions themselves, and the terminal's `isDark ? white : black` picks
(`NativeTerminalNSView.swift:576,623,631`) are dark/light branches, not
hardcoded UI colors.

**No further defects found in the accessibility sweep or dead-UI check.**
The only controls added since Slice 32 (`565a293f`) are the
environment-variable Value fields
(`ProvidersSettingsPane.swift:549,553`), which carry placeholder labels
— the KEY field (`:543`) predates Slice 32 — and the remove-row button
beside them is labelled; no new unlabeled
Button/Toggle/Picker/onTapGesture was added in the 15 files changed since
Slice 32. The other pre-existing `onTapGesture` select rows (pull
requests, workspace files, sidebar bot row) predate Slice 32 and are
unchanged since it, so they are out of this slice's "added since Slice 32"
scope and were left untouched. The two `EmptyView()` defaults
(`PendingAttentionView.swift:35`, `GeneralSettingsPane.swift:258`) are
exhaustive-switch arms, not dead UI; the three `Button("Cancel", role:
.cancel) {}` buttons are the standard alert-dismiss idiom; the two
`fatalError("init(coder:) has not been implemented")` stubs
(`NativeCodeEditorNSView.swift:401`, `NativeTerminalNSView.swift:171`)
are the standard programmatic-NSView pattern.

**Tests added (0):** no Swift `@Test` pattern exists for
accessibility-label or menu-item assertions in this codebase, and none was
added. Swift `@Test` total stays 128 (109 in `AgentsTests/`, 19 in
`CoincideRemoteTests/`; the 2 `@Test` hits in `SystemToolRegistry.swift`
are generated-code strings, not tests).

**Docs correction (not counted):** the Slice 118 section cited
`provider_transport.rs:8-10` for the 32 MiB inbound/outbound caps; the
caps are at `:6-7`, `:8` is the 64 MiB queue and `:9` the write deadline —
corrected to `:6-8`. Description-only, so the totals move only by the 4
defects above, following the Slice 105/109 precedent.

**Verification:** re-read of all four changed hunks; zero new `//`
comments in added lines; registry counts unchanged at 333 tools per side
(Swift `SystemToolDefinition(` 333; Rust `ToolDef {` 334 raw incl. the
struct declaration at `tools.rs:14`); `git diff --stat` shows only the
three Swift files plus this record and the `SYSTEM-TOOLSET.md` hardening
entry. Audit baseline: local `main` `ede38793`, remote `main`
`165ef9a81`, same tree
`6e56794a9bc76c3470a945bc650610c991803c93`. Remote SHA
`1acbed3c26bd201f835fea76d77056f857b48cf6`, backfilled by Slice 124, as
Slice 120 backfilled Slice 118's.

**Mac-gate checks owed:** (1) VoiceOver focus on the composer announces
the placeholder label ("Ask …" / "Steer or queue…") and does not
double-announce with typed text; (2) VoiceOver can activate the diff file
row and the diff gutter jump, and the gutter reads as a button only when
the line is jumpable; (3) the thread context menu on an already-read
thread shows only "Mark as Unread" (no disabled "Mark as Read").

## Slice 124 — Fix Slice 123 findings: docs precision, Slice 122 SHA backfill (remote `70ccd083`)

**Audited:** the Slice 123 verification report on Slice 122 — the
three docs findings and the correlated terminal-row note — re-checked
against the code at HEAD. Statically verified only — no build or test
run here, as for every slice in this record.

**Defects fixed (0):** no code change. The correlated Slice 123 note
asked whether the terminal session row
(`Agents/Terminal/TerminalDrawerRootView.swift:711-712`) should get the
same `.accessibilityElement(children: .combine)` +
`.accessibilityAction` treatment as the Slice 122 diff row. It does not
apply cleanly: the tap handler is identifiable
(`.onTapGesture(perform: onSelect)` at `:709`), but the row contains an
interactive child — the close `Button(action: onClose)` at `:686` with
its own `.accessibilityLabel("Close terminal \(displayTitle)")` at
`:695` — and combining the row's children would merge that button into
the single row element, so VoiceOver users could no longer reach "Close
terminal …" as a separate control. When not hovered, the diff row's
combined children are all non-interactive (file name, directory, +N/−M
counts; its action buttons live in the context menu, outside the combined
element), so the pattern applied cleanly there and does not here. When
hovered, three inline buttons (Open in Inspector Editor, Open in
External Editor, Quote File in Composer) do appear inside the combined
element (`DiffInspectorView.swift:727-758`), but each action is duplicated
in the context menu, which stays reachable. Left unchanged;
Mac-gate owed (see below).

**Docs corrections (not counted):** (1) the Slice 122 §2 sentence now
says the diff row follows the `TerminalDrawerRootView` row's *traits
pattern* — the identical `.accessibilityAddTraits(isSelected ?
[.isButton, .isSelected] : .isButton)` expression at
`TerminalDrawerRootView.swift:712` (which additionally carries an
explicit label at `:711`) — and records the
`.accessibilityElement(children: .combine)` +
`.accessibilityAction` mechanism as the first use of those two modifiers
in `Agents/` (`DiffInspectorView.swift:798,800,1122,1125`); (2) the
Slice 122 sweep paragraph now names the environment-variable *Value*
fields (`ProvidersSettingsPane.swift:549,553`) accurately — the KEY
field (`:543`) predates Slice 32; (3) the Slice 122 section heading now
carries the pushed remote SHA `1acbed3c` and the Verification paragraph
the full `1acbed3c26bd201f835fea76d77056f857b48cf6`, replacing the "to be
backfilled" note. Description-only, so the totals stay at 29 defects
fixed and 27 regression tests, following the Slice 105/109 precedent.

**Tests added (0):** docs-only slice. Swift `@Test` total stays 128
(109 in `AgentsTests/`, 19 in `CoincideRemoteTests/`).

**Verification:** re-read of all changed hunks; the cited lines
re-verified in the files (`TerminalDrawerRootView.swift:686,695,709,
711-712`; `DiffInspectorView.swift:798-800,1122-1125`;
`ProvidersSettingsPane.swift:543,549,553`); registry counts unchanged
at 332 tools per side (Swift `SystemToolDefinition(` 332; Rust
`ToolDef {` 333 raw incl. the struct declaration at `tools.rs:14`);
zero new `//` comments in added lines (docs only, no Swift changed);
`git diff --stat` shows only this record, `docs/MAC-GATE.md`, and the
`SYSTEM-TOOLSET.md` hardening entry. Audit baseline: local `main`
`9df38e0b`, remote `main` `1acbed3c26bd201f835fea76d77056f857b48cf6`,
same tree `e3beabbdbe21f7312ec747bc5baa5b2afa40d811`. Remote SHA
`70ccd083957f102dd55dd3cfc190d074e6c38137`, backfilled by Slice 126, as
this slice backfilled Slice 122's.

**Mac-gate checks owed:** (1) decide how VoiceOver activates the
terminal session row without swallowing its close button — the row
(`TerminalDrawerRootView.swift:709-712`) is tap-to-select with only the
`.isButton` trait and no action, so it may itself not be
VoiceOver-activatable, while the close button at `:686` must stay
separately reachable; any fix must keep both.

## Slice 126 — Qualify diff-row combined-children claim; record hovered-state follow-up (remote `7fe85375`)

**Audited:** the Slice 125 verification report on Slice 124 — the one
docs-precision finding (F1) — re-checked against the code at HEAD.
Statically verified only — no build or test run here, as for every slice
in this record.

**Defects fixed (0):** no code change. The Slice 124 "Defects fixed (0)"
paragraph overstated the diff row: it said the row's combined children
are all non-interactive, but `DiffFileSummaryRow.body`'s outer `HStack`
(`Agents/Inspector/DiffInspectorView.swift:696-784`), to which
`.accessibilityElement(children: .combine)` applies at `:798`, contains
an `if isHovered` block (`:727-758`) with three `Button`s — Open in
Inspector Editor (`:730`), Open in External Editor (`:738`), Quote File
in Composer (`:749`). When the row is hovered, those interactive children
are inside the combined element and would be merged into the single row
element by the same mechanism Slice 124 cites for the terminal close
button. The context-menu buttons (`:801-827`) are indeed outside the
combined element. Mitigations, unchanged from Slice 125: the buttons
render only when `isHovered`, a state VoiceOver users effectively never
trigger, and each hover button's action is duplicated in the context menu
(`:803` Open in Inspector, `:807` Open in External Editor, `:823` Quote
File in Composer), which stays reachable. The gutter row (`:1122`)
genuinely has text-only children. The terminal-row decision stands.

**Docs corrections (not counted):** (1) the Slice 124 "Defects fixed (0)"
paragraph now says the diff row's combined children are all
non-interactive *when not hovered*, and notes the three hover-revealed
buttons inside the combined element with their actions duplicated in the
context menu; (2) the Slice 122 §2 sentence now carries the same
qualifier on its "combined children (file name, directory, +N/−M counts)"
list; (3) the Slice 124 section heading now carries the pushed remote SHA
`70ccd083` and the Verification paragraph the full
`70ccd083957f102dd55dd3cfc190d074e6c38137`, replacing the "to be
backfilled" note. Description-only, so the totals stay at 29 defects fixed and 27
regression tests, following the Slice 105/109 precedent.

**Tests added (0):** docs-only slice. Swift `@Test` total stays 128
(109 in `AgentsTests/`, 19 in `CoincideRemoteTests/`).

**Verification:** re-read of all changed hunks; the cited lines
re-verified in the file (`DiffInspectorView.swift:696-798,801-827,
1122`); registry counts unchanged at 332 tools per side (Swift
`SystemToolDefinition(` 332; Rust `ToolDef {` 333 raw incl. the struct
declaration at `tools.rs:14`); zero new `//` comments in added lines
(docs only, no Swift changed); `git diff --stat` shows only this record
and the `SYSTEM-TOOLSET.md` hardening entry. Audit baseline: local `main`
`a15a133e`, remote `main` `70ccd083957f102dd55dd3cfc190d074e6c38137`,
same tree `9dea8822ea538fac1b5a8747e1bc6c8aca828642`. Remote SHA backfilled
by Slice 128 as `7fe853752a988d1f2ab1e40f4945f89a2ca63f1f` (tree
`075ee67ba1cb1cc688314412ede0acc0f04087b1`, same as local `38a34d15`).

**Mac-gate checks owed:** (1) in the hovered state the diff row has the
same swallowing property Slice 124 declined to introduce in the terminal
row — look at whether the hover buttons should be excluded from the
combined element or left as-is, given they are hover-only and their
actions are duplicated in the context menu.

## Slice 128 — coincide-desktop (GPUI) audit: CI-built, 0 defects found (remote `de82d77f`)

**Audited:** `Rust Backend/crates/coincide-desktop/` (296 files under
`src/`), the legacy GPUI desktop app — its first defect audit in this
program. Bounded to the highest-risk surfaces in the defect classes of
Slices 39/43/53/81/118: auth/credentials, update/feed handling,
provider/error text, unbounded collections/caches, network fetches, and
file writes. Statically verified only — no build or test run here, as for
every slice in this record. No cargo, no Swift toolchain.

**Build status — BUILT (not unbuilt legacy code).** The crate is a
workspace member (`Rust Backend/Cargo.toml:2`, `members` includes
`crates/coincide-desktop`) and CI builds and tests it extensively:
`.github/workflows/rust.yml:154` (`cargo build -p coincide-desktop
--locked`), `:187` (`cargo test -p coincide-desktop --locked --features
native-notifications,native-microphone,native-computer-use`), `:190`
(updater-helper transport tests), `:193-273` (six native-SDK example
builds), `:352,611` (`cargo check`, with and without
`preview-updater-helper`), plus the macOS job `desktop` at `:124` (where
the already-cited `:154`/`:187` live), the Windows job
`desktop-windows` at `:296` (native-app build step at `:415`), and the
Linux job `desktop-linux` at `:532` (native-app build step at `:668`).
`.github/workflows/ci.yml:132-133` confirms rust.yml covers coincide-core
and coincide-desktop. It is NOT shipped: `project.yml:47,50` builds only
`coincide-macos-ffi` and `coincide-mcp-server`, and no crate depends on it
(no `coincide-desktop` in the `Cargo.toml` of coincide-core,
coincide-macos-ffi, or coincide-mcp-server). So the audit proceeded as a
live-code audit, and the Slice 65 standing note (updater dead in the
shipped app) still applies to what ships — but the crate itself is
compiled and tested by CI, so a defect here would be a live defect, not
dead code.

**Defects fixed (0):** no code change. Per area, with the evidence that
closed each one:

- **Updater transport** (`updater_helper_transport.rs`): commands bounded
  to `MAX_FRAME / 2` (`:333-358`); proposals bound by nonce/digest/
  session/sequence checks, a 16-frame cap, and 64-hex tree hashes
  (`:552-565,630-720`); worker failures truncated to 1,024 chars (`:460`);
  consent fencing blocks session reuse after clean consent
  (`:360-382,419-520`).
- **Updater lifecycle** (`updater_lifecycle.rs`): install target pinned
  to an absolute `Coincide Rust.app` path with no `..` components, and
  handshake/shutdown deadlines capped at 900 s / 600 s (`:167-200`); poll
  drains at most 8 events per tick (`:263`); failure after consent is
  `ConsentUncertain`, never retried or claimed disarmed (`:226-243`).
- **Update feed** (core-owned, read for the desktop display): feed bytes
  capped by `config.limits.metadata_bytes` (default 2 MiB), artifact URL
  must equal the configured platform-specific URL exactly, archive size
  capped, SHA-256 format-checked
  (`coincide-core/src/updater.rs:79-80,373-376,392,630-690`); the desktop
  only displays the validated `release.version`
  (`updater_settings.rs:226,520-525`).
- **Credentials** (`credentials.rs`, `browser_credentials_macos.rs`,
  `voice_credentials.rs`): approval is native-only with a 300 s expiry
  and a one-use id (`credentials.rs:26-40`); fill permits last 9 s, are
  revocable, and a timed-out job never fills (`:129,192,209-232`);
  `FillJob` carries no Debug/Serialize (`:129`); voice keys go through
  `Zeroizing` and the OS secret store
  (`voice_credentials.rs:68-81,325`); no secret appears in any log line
  (grep for `password|token|secret|api_key|bearer|credential` across
  `println!`/`eprintln!`/`debug!`/`info!`/`warn!`/`error!`/`trace!` is
  empty).
- **Downloads** (desktop callers + core registry, read-only): every
  platform validates the URL/origin and the navigation epoch before
  admitting (`browser_downloads_macos.rs:428-460`,
  `browser_downloads_linux.rs:349-397`,
  `browser_downloads_windows.rs:196-230`, incl. the 128-active cap at
  `:206`); the registry caps 8 active / 50 records, truncates refusal
  reasons to 512 chars, sanitizes the server-suggested name to a leaf of
  at most 180 chars with control/RTL characters stripped, and writes
  into a per-download UUID directory at mode 0o700 with symlink checks
  (`coincide-core/src/browser_protocol.rs:605-650,705-740,895-938`).
- **Open targets** (`open_targets.rs`, `main.rs:4347-4348`): targets come
  from a fixed built-in discovery list (`open_targets.rs:52-240`);
  settings select by `id` only, never by program path (`:451-464`);
  spawned children are reaped every tick (`main.rs:4347-4348`); editor
  URLs are percent-encoded (`:326-336`).
- **Terminal handoff and shell PATH** (`provider_setup_terminal.rs`,
  `main.rs:8098-8147`): fixed terminal/launcher names found on PATH,
  literal path arguments, no shell, 10 s launcher deadline
  (`provider_setup_terminal.rs:26-57,81-135`); the login-shell PATH probe
  runs a fixed `printf` command with output capped at 64 KiB and `$SHELL`
  checked to be a file (`main.rs:8098,8147`).
- **Appshots FFI** (`appshots_platform.rs:86-170`): native pointers
  null-checked before `CStr::from_ptr`, capture bytes capped at 20 MiB
  (`:149`), native errors surfaced as fixed strings.
- **Community links** (`community_links.rs:159-195`): report URLs are
  query-escaped, version fields folded to one line and capped at 120
  chars (`MAX_FIELD`, `:5`).
- **Cookie/session/history import** (`browser_cookie_import.rs`,
  `cookie_import_flow.rs`, `session_import.rs`, `browser_settings.rs`):
  cookie readback comparison short-circuits above 1,000 entries
  (`browser_cookie_import.rs:83,297`); session preview caps visible
  messages and characters (`session_import.rs:94-151`); profile import is
  capped at 1 MiB (`browser_settings.rs:98`, `MAX_DOCUMENT`) and saved
  atomically at mode 0o600 with symlink refusal and rollback
  (`:569-640`).
- **Unbounded collections** (`main.rs` App state): follow-up backlog
  capped at 32 (`composer_follow_up_mount.rs:483`); image previews
  capped at 128 with eviction and decoded assets at 32
  (`main.rs:5568,5664`); sidebar row bounds cleared on every sidebar
  render (`navigation.rs:911-913`); tool-detail scrolls cleared on
  thread change (`main.rs:3151`); queued messages are replaced wholesale
  from the engine read and cleared on selection (`queue.rs:525`,
  `main.rs:3208`); `open_target_children` reaped per tick (above).
- **Keep-awake admin path** (`persistent_awake.rs:73-87,629-652,665-700`):
  the privileged `osascript` script is built only from fixed commands
  and validated integers (`u32` parsed from `pmset`, `u8::from(bool)`);
  stderr is truncated to 512 chars (`:647`); the audio-helper binary is
  symlink-checked with a 10 s deadline and a cleared environment
  (`:665-700`).
- **No network client in the crate:** `Cargo.toml` declares no
  `reqwest`/`ureq`/`hyper`/`curl` dependency and no `std::net` listener
  exists outside tests, so there is no desktop-owned fetch surface to
  bound; fetches live in coincide-core (out of scope) or the WebKit/Wry
  views.

**Tests added (0):** docs-only slice; no defect to regress. Rust test
total re-counted at HEAD: **3,002** real (2,221 real short-form
`#[test]` — 2,222 raw minus the one `//` comment line at
`Rust Backend/crates/coincide-desktop/src/diff_panel_ui_tests.rs:5`,
which mentions the attribute in prose — + 736 fully-qualified
`#[::core::prelude::v1::test]` + 45 `#[gpui_kit::test]`); the desktop
crate holds 1,148 real of them (1,149 raw: 368 short-form, 2 of which
are in `swift_link_options.rs`, + 736 + 45). The brief's 3,002 / 1,148
expectation was correct; Slice 128 counted the raw total without
subtracting the documented comment line, and its sentence claiming the
brief was off by one was backwards.

**Verification:** re-read of every cited file/line above; registry counts
unchanged at 332 tools per side (Swift `SystemToolDefinition(` 332; Rust
`ToolDef {` 333 raw in `coincide-mcp-server/src/tools.rs`, incl. the
struct declaration at `:14`, i.e. 332 in `DEFINITIONS` at `:47`); zero
new `//` comments (docs only, no `.rs` changed); `git diff --stat`
shows only this record and the `SYSTEM-TOOLSET.md` hardening entry.
Audit baseline: local `main` `38a34d15`, remote `main`
`7fe853752a988d1f2ab1e40f4945f89a2ca63f1f`, same tree
`075ee67ba1cb1cc688314412ede0acc0f04087b1`. Remote SHA backfilled by
Slice 130 as `de82d77fd05b995c8312a662d8f88a02bde78576` (tree
`d9bc052544d775c26453086dda9ae56a74056935`, same as local `07da5097`).
(Also backfilled Slice 126's remote SHA `7fe85375` in its
heading above.)

**Mac-gate checks owed:** (1) `cargo test -p coincide-desktop` on
Dylan's Mac — the 1,148 desktop tests (updater transport/lifecycle,
credential approval/fill, download, import suites) have never run here;
(2) the CI `rust.yml` desktop jobs remain the compile gate for this
crate, since it is not built by `project.yml`.

## Slice 130 — Correct Rust test total 3,003 → 3,002; fix rust.yml cite; Slice 128 SHA backfill

**Audited:** the Slice 129 verification report on Slice 128 — its two
findings (F1 counts, F2 `rust.yml` cite) — re-checked against the repo
at HEAD. Statically verified only — no build or test run here, as for
every slice in this record.

**Defects fixed (0):** no code change. Docs corrections only (below).

**Docs corrections (not counted):** (1) the Slice 128 "Tests added (0)"
paragraph now says the Rust test total re-counted at HEAD is **3,002**
real — 2,221 real short-form `#[test]` (2,222 raw minus the one `//`
comment line at
`Rust Backend/crates/coincide-desktop/src/diff_panel_ui_tests.rs:5`,
which mentions the attribute in prose) + 736 fully-qualified
`#[::core::prelude::v1::test]` + 45 `#[gpui_kit::test]` — and the
desktop crate holds 1,148 real of them (1,149 raw), retracting Slice
128's backwards sentence: the brief's 3,002 / 1,148 expectation was
correct; Slice 128 had counted the raw total without subtracting the
documented comment line; (2) the Slice 128 Mac-gate line now says the
1,148 desktop tests have never run here; (3) the `SYSTEM-TOOLSET.md`
Slice 128 bullet now says 3,002 (desktop 1,148); (4) the `rust.yml` cite
in the Slice 128 "Build status" paragraph now maps the jobs precisely —
macOS job `desktop` at `:124` (where the already-cited `:154`/`:187`
live), Windows job `desktop-windows` at `:296` (native-app build step
at `:415`), Linux job `desktop-linux` at `:532` (native-app build step
at `:668`) — replacing the "macOS/Windows/Linux jobs (`:415,668`)"
wording that attached the macOS job to the Windows/Linux step lines;
(5) the Slice 128 section heading now carries the pushed remote SHA
`de82d77f` and the Verification paragraph the full
`de82d77fd05b995c8312a662d8f88a02bde78576`, replacing the "to be
backfilled" note. `docs/MAC-GATE.md`'s 3,002 was already correct and is
untouched. Description-only, so the totals stay at 29 defects fixed and
27 regression tests, following the Slice 105/109 precedent.

**Tests added (0):** docs-only slice. Rust test total stays 3,002 real
(2,221 + 736 + 45); desktop 1,148 real.

**Verification:** re-read of all changed hunks; counts re-measured at
HEAD (2,222 raw short-form, exactly one non-attribute match — the `//`
comment at `diff_panel_ui_tests.rs:5` — 736 fully-qualified, 45
`gpui_kit`, desktop 368 raw short-form); `rust.yml` job lines re-read
(`desktop:` :124, `desktop-windows:` :296, `desktop-linux:` :532, build
steps :415/:668); remote `main` verified via the GitHub API as
`de82d77fd05b995c8312a662d8f88a02bde78576`, tree
`d9bc052544d775c26453086dda9ae56a74056935`, same as local `07da5097`;
zero new `//` comments (docs only, no `.rs` changed); `git diff --stat`
shows only this record and the `SYSTEM-TOOLSET.md` hardening entry.
Audit baseline: local `main` `07da5097`, remote `main`
`de82d77fd05b995c8312a662d8f88a02bde78576`, same tree
`d9bc052544d775c26453086dda9ae56a74056935`. Remote SHA
`3da030fdabe379e6455ef3b5ee153fa1aad3f689` (tree
`380ec9676dcfe90a371b88faad7a5911198a943e`, same as local `d1f46398`),
backfilled by Slice 133.

**Mac-gate checks owed:** none new; the Slice 128 Mac-gate item (the
1,148 desktop tests never run here) stands, now with the corrected
count.

## Slice 134 — MCP server panic isolation (`33cc12f1`)

**Audited:** the `coincide-mcp-server` dispatch path — `main.rs` `run()`
loop, `protocol.rs` `handle()`, `call_tool()`, and `tools.rs` `call()` —
for panic isolation. (File paths in this section are under
`Rust Backend/crates/coincide-mcp-server/` unless noted otherwise.)

**Gap (1, real):** there was no `catch_unwind` anywhere in the crate
(verified: zero matches in `src/`), so a panic anywhere in tool dispatch
unwound through `handle()` into the `run()` loop and killed the process
(exit 101), dropping every provider's System Tools mid-turn with no error
frame. A deterministic provider-reachable trigger exists today:
`strings_localization` with action `set` on a `.xcstrings` catalog whose
`"strings"` value is not an object (for example `{"strings": 42}`) panics
in `g6_xcstrings_set` at `tools.rs:11870`
(`object.get_mut("strings").unwrap().as_object_mut().unwrap()`), reached
via `call()` `tools.rs:21143` → `g6_call` `tools.rs:13451` → the `set`
arm `tools.rs:13498`. Every other `unwrap()` site checked on the dispatch
path is guarded by a preceding check (`use_mcp` `tools.rs:17402-17406`,
`whole_word_replace` `tools.rs:18688`, `code_mutation_engine`
`tools.rs:18462`, `assets.rs` throughout), so the guard is defense in
depth for this and any future handler panic, not a fix for a single
unwrapping site.

**Defects fixed (1):**

1. Per-request dispatch is now wrapped in `std::panic::catch_unwind`
   (`dispatch_guarded`, `src/protocol.rs:96-101`; `AssertUnwindSafe`
   because the closure captures `&ServerState`, whose
   `Mutex<ControlClient>` is not statically `UnwindSafe`). The method
   match was extracted unchanged into `dispatch()`
   (`src/protocol.rs:82-94`) and `handle()` now calls
   `dispatch_guarded()` (`src/protocol.rs:75`), so the wrap covers every
   dispatched method (`tools/call`, `resources/list`, `resources/read`,
   `prompts/get`, `initialize`, `ping`, `tools/list`), not just tool
   calls. A caught panic returns JSON-RPC error `-32603` with the fixed
   message `"request handler panicked"` — the panic payload is discarded
   (`Err(_)`), never echoed into the response — and the `run()` loop
   continues serving subsequent requests.

**Tests added (1):**
`panicking_tool_call_returns_internal_error_and_the_server_survives` in
`tests/mcp_server.rs` — drives the real server binary over stdio through
the real wrap point: writes a `Localizable.xcstrings` catalog containing
`{"strings": 42}`, calls `strings_localization` with action `set`, and
asserts the `-32603` error with exactly the fixed message, then asserts a
following `ping` still answers `{}` and the server exits cleanly on
stdin EOF.

**Known limitation (not fixed, by design):** Mutex poisoning is untouched.
If a panic happens while the engine-control lock is held, the lock
poisons; the MCP server's own `state.control` lock already recovers via
`into_inner()` in `engine_request` (`tools.rs:7842-7844`), but a poisoned
engine-side lock surfaces as the pre-existing `"Engine lock failed"`
error (`coincide-core/src/control.rs:182`). No lock type was changed.

**Verification:** static only (no cargo in this environment, as for every
slice in this record). Brace/paren/bracket balance re-checked on both
changed Rust files; full diff read — only the two intended files, only
the intended hunks; the wrap point traced by hand from the `run()` loop
through `handle()` → `dispatch_guarded()` → `dispatch()` →
`call_tool()` → `tools::call()`; the panic trigger traced by hand from
`tools/call` to `g6_xcstrings_set` `tools.rs:11870`; no panic payload
reaches any error string (the only new error string is the fixed
literal); zero new `//` comments; no secrets. Remote
`33cc12f1cd1161590f84bcb777e3107e742954b2` (tree
`27f2434210f68be99845738b6dd536d313935e40`, parent
`9a0a81c1d64deb4dd3a899343428ef24b2d2cd19`), backfilled by Slice 136,
following the Slice 130 precedent. The local pre-push commit SHA and
tree are in the slice's push report.

**Mac-gate checks owed:** `cargo test -p coincide-mcp-server` on Dylan's
Mac — the new test was written, not executed, here.

## Slice 138 — Swift `execute()` handler-arm coverage audit (remote `d4360146`, 0 defects)

**Audited:** whether every one of the 332 definitions in
`Agents/Core/SystemTools/SystemToolRegistry.swift` (`systemTools`) is
actually reachable in Swift `execute()` — handler-arm coverage, never
audited before. Prior slices verified the definitions
332/332/332 including param descriptions (Slice 132), all 275 returns
in `execute()` are `JSONValue` (Slices 103/104), and thread-identity
pinning on all 129 identity params (Slices 105–110); the Rust side was
used only as a reference (Rust `tools.rs` `call()` verified 332/332
dispatch arms in Slice 72).

**Dispatch structure (as found):** `execute()` (`:3826–7444`) dispatches
on **name**, not action: after the thread-identity pin
(`:3835–3838`), a guard at `:3839–3844` resolves the definition and
throws `SystemToolError.toolNotActive` when the tool is registered but
not active under the caller's toolset, or `unknownTool` when the name
is not registered at all; the body is a single `switch
definition.name` (`:3845`) with a `default:` arm at `:7441–7442`
that throws `SystemToolError.unknownTool(name)` — an honest error, not
a silent wrong result. The fallback is unreachable for a registered
tool: the guard admits only registered names, and every registered
name has an arm (below). A missing arm would therefore degrade to the
honest `unknownTool` error, never to a fabricated success — but no arm
is missing.

**Method:** a Python re-parse of both the definitions array and the
`execute()` switch (a first single-line pass undercounted the arms at
209 and falsely reported 123 missing, because three arms span multiple
lines; the corrected parser accumulates multi-line case labels), plus
hand verification of every shared arm and of the helper dispatchers
they delegate to, to rule out "covered by an arm but unhandled inside
the helper".

**Coverage (measured): 332 definitions → 332 covered / 0 missing /
0 dead arms / 0 duplicate arms.** The switch has 207 top-level arms
carrying 332 name entries: 199 single-name arms plus 8 multi-name
arms — `run_build` / `run_tests` (`:4010`), the 20 computer-use tools
(`:4125`), `file_read` / `view_file` (`:4132`), `create_file` /
`file_create` (`:4143`), `use_terminal` / `run_command` (`:4335`),
`project_scheme_list` / `project_target_list` (`:5956`), the 38 G6
tools (`:6705`), and the 65 G5 tools (`:7187`). All 63 distinct actions
have at least one covered tool; no action is wholly or partly
uncovered.

**Depth check (shared arms do real work, not fall-through):**

- G5 arm (65 names) → `runG5Tool` (`:10083`): 32 inner switch cases
  plus 33 `g5ScanSpecs` entries (`:7460`, reached via `runG5Scan`'s
  `default:` and its guard at `:10197`) partition the 65 exactly — 0
  unhandled inside the helper, 0 inner cases or spec keys outside the
  arm.
- G6 arm (38 names) → `runG6Tool` (`:7995`): 37 inner switch cases
  plus `derived_data_locate`, handled by the pre-switch early return
  at `:7996` (`g6DerivedData`) before the switch's `unknownTool`
  default at `:9370` — 0 unhandled.
- Computer-use arm (20 names) → `runComputerUseTool` (`:11670`):
  no per-name switch, by design — it forwards the tool name
  generically through the `computer_use.request` engine RPC
  (`"name": tool`) and polls `computer_use.result`, so all 20 are
  handled by construction.
- The only other `unknownTool` throws inside `execute()` are the
  pre-switch guard (`:3843`), the `use_mcp` recursion
  (`:4414`, for a delegated MCP tool name that has no registry
  definition), and the `tool_capability_lookup` arm (`:6946–6949`:
  `guard let found = Self.definition(named: toolName, for: .system)
  else { throw SystemToolError.unknownTool(toolName) }`, throw at
  `:6949`) — all three legitimate. (Slice 139 caught the omission of
  the third; corrected in Slice 144.)

**Defects fixed (0):** no code change. No arm was added: with 0
missing arms there is nothing to add, and adding arms for symmetry
would be dead code — the fallback already returns the honest error.
The definitions array, params, and descriptions are untouched.

**Tests added (0):** docs-only slice. No new arm means no new arm to
test; the existing `ToolsetTests.swift` coverage of `execute()` is
unchanged.

**Verification:** static only (no Swift toolchain in this environment,
as for every slice in this record). Coverage script re-run after the
final parse (332/332, 0/0/0); brace balance re-checked on both changed
docs files; full diff read — only the two intended files, only the
intended hunks; the Slice 136 remote SHA verified against the GitHub
API (`92cc6f32698235ca9c24d7b2b967cf84f27dc97a`, tree
`963d7ddd7ebe51dcd6a788835ac0af9dedece72d`, parent
`33cc12f1cd1161590f84bcb777e3107e742954b2`); the Slice 138 remote SHA
was backfilled by Slice 144, verified against the GitHub API
(`d43601463a1aeff025fdc3beebd9b22f6458721e`, tree
`20b4fbfb234ce095303e457b6dd09c19de35dea0`, parent
`92cc6f32698235ca9c24d7b2b967cf84f27dc97a`); the Slice 137 facts below
spot-checked (program diff 224 files +54,296/−3,595; 17 remaining
"3,002" hits in `docs/`, all historical; the Slice 134 test function
closes at `tests/mcp_server.rs:598`; `coincide-mcp-server` holds 19
`#[test]` attributes). Zero new `//` comments (docs only, no Swift
changed); no secrets. The local pre-push commit SHA and tree are in
the slice's push report.

**Mac-gate checks owed:** none new; no code changed, so there is
nothing to build.

## Slice 144 — Slice 141 defects: `copy_file` cap, `read_file` symlink guard, cwd pin (remote `4dc0a144`, 3 defects, 5 tests)

**Fixed (3):** the two real defects from Slice 141's audit, plus the
cheap cwd pin it recommended.

- **Fix 1 — `copy_file` had no size cap.**
  `workspace_tools.rs:326–361`: `copy_file` resolved the source,
  checked `is_file()`, resolved the destination, and called
  `fs::copy` with no size check — the only size constant,
  `MAX_FILE_WRITE_BYTES` (3 MiB), covers reads/writes/edits only.
  Now the source length is read once (`:331–336`) and refused above a
  **5 GiB cap** (`MAX_FILE_COPY_BYTES`, `:14`). The cap covers
  realistic legitimate single-file in-workspace copies (`.ipa` /
  `.dmg` / MLX shards / video, almost all under 5 GiB per file) while
  bounding worst-case damage to ~1% of a 512 GB disk; anything larger
  can already go through the agent's terminal `cp`. Containment is
  unchanged and untouched. Two further guards in the same function: a
  free-space reserve check (`:341–347`) refuses the copy when the
  source would eat into a 5 GiB reserve on the destination volume
  (`source_len > free_space − 5 GiB`, underflow-safe), probed with
  `libc::statvfs` (`available_bytes`, `:363–378`, following the
  existing `updater.rs` pattern); `libc` is already a dependency of
  `coincide-core` (`Cargo.toml:27`: `libc = "0.2"`, also used for
  `O_NOFOLLOW` in this file), so no new dependency and no
  `Cargo.lock` change. The probe is Unix-only and fails open (the
  check is skipped when `statvfs` fails or on non-Unix), so a
  failed probe can never block a legitimate copy. And a mid-copy
  `fs::copy` error now removes the partial destination (`:348–354`)
  instead of leaving a truncated file behind.
- **Fix 2 — `read_file` read through in-workspace symlinks,
  bypassing the `.git` guard.** A planted symlink `leak ->
  .git/config` passed lexical validation, canonicalized inside the
  root, and returned `.git/config` contents. Fixed on both paths.
  Non-paged branch (`workspace_tools.rs:564–595`): the hand-rolled
  canonicalize-and-prefix check is gone; the branch now routes
  through `read_workspace_text` (`:585`), which refuses a final
  symlink via `symlink_metadata` (`:220–224`) before canonicalizing,
  and preserves the existing 3 MiB / non-binary / UTF-8 checks and
  the same returned JSON shape (`path`, `text`, `content`,
  `lineOffset` 0, `totalLines`, `truncated` false). Paged path
  (`workspace.rs:733–743`): the same `symlink_metadata` refusal was
  added (`:737–743`) before canonicalizing; the existing test
  asserting an outside-pointing symlink is rejected
  (`workspace.rs:824–826`) still passes, since every final symlink is
  now refused, not just outside-pointing ones. Zero legitimate cost:
  a genuinely needed symlink read can go through the terminal.
- **Fix 3 — cwd pin.** `with_session_defaults`
  (`tools.rs:7819–7831`) only inserted `state.cwd` when the model
  omitted `cwd`, so a model-supplied `cwd` won verbatim and file
  tools worked against any root (`/`, `~/.ssh`, another project).
  It now always overwrites `args["cwd"]` with `state.cwd`, guarded
  to non-empty (`:7824`: `state.cwd.to_str().filter(|cwd|
  !cwd.is_empty())`). `state.cwd` is always populated: `--cwd` is
  required by `parse_args` (`main.rs:48`) and must be absolute, and
  the only other `ServerState` constructions are the five test sites,
  all with `cwd: "/tmp"` — so the guard never fires in practice; it
  is defense-in-depth for direct construction. The `use_mcp`
  recursion re-enters `call()` (`tools.rs:17405`), which applies
  `with_session_defaults` (`:16894`), so the recursion goes through
  the same choke point and the pin covers it too.

**Accepted risks (not fixed):** the check-then-open TOCTOU stays
open — a racer needs workspace write access, which is the same trust
boundary as the agent itself, and `open_regular` already uses
`O_NOFOLLOW` plus post-open re-verification; closing it needs
openat-style traversal. The cwd pin binds the model, not the
launcher: `--cwd` is chosen by whoever starts the server, so a
compromised launcher is outside this fix's threat model. Slice 140's
audit found 0 real defects — `initialize` protocolVersion benign,
duplicate JSON keys benign, `--help` exit 1 cosmetic — none fixed.
Slice 142's UI sweep found 0 findings. Slice 143's coverage numbers
stand as its audit note: 246/332 direct, 174/332 arm-reached, 57
truly uncovered.

**Tests added (5):** `copy_file_copies_small_files` and
`copy_file_refuses_files_over_the_5_gib_cap`
(`workspace_tools.rs:825,844` — the refusal test uses a sparse file
via `set_len(5 GiB + 1)`, no real 5 GiB file is written);
`read_file_refuses_symlink_to_git_config_on_both_paths`
(`workspace_tools.rs:865`, non-paged plus paged through the public
entry) and `read_file_refuses_symlink_to_git_config`
(`workspace.rs:830`, paged path directly); and
`session_cwd_wins_over_model_supplied_cwd`
(`tools.rs:21367`, a model-supplied `cwd=/etc` is pinned to
`state.cwd`). All written, not executed — `cargo test -p
coincide-core` and `cargo test -p coincide-mcp-server` on Dylan's
Mac are the gate.

**Verification:** static only (no cargo in this environment, as for
every slice in this record). Brace balance re-checked on the three
Rust files (deltas zero vs. the parent on each);
each fix traced by hand (cap check before copy, symlink refusal
before canonicalize on both read paths, cwd overwrite at the choke
point); zero new `//` comments in the Rust diff; no secrets; no
registry definition, param, or description changed. Full diff read —
only the five intended files, only the intended hunks. The local
pre-push commit SHA and tree are in the slice's push report. The
Slice 138 remote SHA was verified against the GitHub API and
backfilled in the Slice 138 section above; the Slice 144 remote SHA
was verified against the GitHub API by Slice 146
(`4dc0a1440ee07f29b574db5490b8a8c9f95a4a3d`, tree
`fbb6d20e6dfc97bf4dc3b1895bc3d000aa8b0ebd`, parent
`d43601463a1aeff025fdc3beebd9b22f6458721e`) and backfilled in the
Slice 144 section header above; the Slice 139 MINOR (the
`:6949` sentence, see the re-verify note below) is fixed in this
slice. Owed as follow-up, not done here: `docs/MAC-GATE.md` still
says 3,003 Rust tests, but this slice adds 5 (3,008 by this slice's
count: 2,227 short-form + 736 fully-qualified + 45 `gpui_kit`) —
same staleness pattern as Slice 134, fixed then in Slice 136.

**Mac-gate checks owed:** the 5 new tests above, plus the Xcode
build as usual; no new Mac-gate surface beyond the tests.

## Slice 146 — Slice 145 findings: literal `.git/config` read and intermediate-symlink bypass on both read paths (remote `81cf2e4c`, 2 defects, 4 tests)

**Correction of the record:** Slice 144's Fix 2 wording — "Fixed on
both paths" and, in `docs/SYSTEM-TOOLSET.md`, "closing the
`.git/config` symlink leak" — was premature. Slice 144's final-symlink
refusal closed only the planted-final-symlink case. The literal
`.git/config` path and the intermediate-directory symlink case both
still returned file contents after Slice 144, as Slice 145 traced.
The leak is closed by this slice, not by Slice 144. Slice 144's
section above is left as written; the correction lives here.

**Fixed (2):** the two MAJOR findings from Slice 145's re-verification
of Slice 144.

- **Fix 1 — paged `read_file` read `.git/config` by literal path.**
  `workspace::read_file` (`workspace.rs:738`) had no `.git` guard:
  its `relative_path` (`:281–296`) only required `Normal` components,
  unlike `validate_relative_workspace_path`
  (`workspace_tools.rs:145–161`), and the paged branch in
  `workspace_tools::read_file` never called the latter, so
  `read_file({cwd, path: ".git/config", lineOffset: 0, lineLimit: 10})`
  returned the file with no symlink at all. Fixed by adding the
  `.git`-component refusal to `relative_path` itself
  (`workspace.rs:290–294`, same byte comparison as
  `validate_relative_workspace_path`). Callers checked first:
  `relative_path` has only two — `read_file` (`:740`) and `diff`
  (`:327`), which passes the path as a git pathspec to the git runner.
  No git tooling reads `.git` file contents through it (the git
  functions use the git runner directly), and a `.git/config`
  pathspec matches nothing in git anyway, so refusing it in `diff`
  only turns a no-op diff into an error. The guard therefore lives in
  `relative_path`, covering both callers with one change. The
  non-paged path was already refused by
  `validate_relative_workspace_path` — now proven by test, since the
  existing `workspace_paths_refuse_git_internals` test covers
  write/delete/move but, as Slice 145 noted, not read.
- **Fix 2 — intermediate directory symlink bypassed both read
  paths.** Both guards checked only the final component with
  `symlink_metadata` (`workspace_tools.rs:236–240`,
  `workspace.rs:744–748`); intermediate components were resolved by
  the kernel, so a planted `link -> .git` plus a read of
  `link/config` stat-ed the resolved regular file `.git/config`,
  canonicalized inside the root, and returned its contents. Fixed
  with one shared read-only helper,
  `refuse_intermediate_symlinks` (`workspace_tools.rs:218–231`,
  `pub(crate)`), which walks the parent components exactly the way
  `workspace_parent_for_write` (`:184–216`) already does for writes —
  same "Intermediate workspace path is not a regular directory"
  refusal — but read-only: a missing intermediate propagates the
  `NotFound` io error instead of creating the directory, so a read
  never creates directories as a side effect. It is called from both
  read paths: `read_workspace_text` (`:235`) and
  `workspace::read_file` (`workspace.rs:742`). The write path's walk
  itself was not reused because it creates missing directories, which
  is wrong for a read; no second mechanism was invented — the walk
  logic is mirrored once in the shared helper. Tradeoff, recorded:
  this refuses intermediate symlinks even when they point inside the
  workspace, stricter than the old canonicalize-stays-inside behavior
  — consistent with the no-symlink policy reads already enforce on
  final components, and a genuinely needed symlink read can go
  through the terminal. Side effect, consistent with that policy:
  `edit_file` gains the same refusal, since its pre-write read and
  post-write verification both route through `read_workspace_text`.

**MINORs fixed (2, description-only, not counted as defects,
following the Slice 105/109 precedent):** (1) the Slice 144 section's
"four test sites" sentence now reads "five test sites" — verified:
`tools.rs:21334, 21351, 21368, 21386, 21403`, every site with
`cwd: "/tmp"`, plus production `main.rs:59`; (2)
`docs/MAC-GATE.md` refreshed to the true Rust total **3,012** (2,231
real short-form — 2,232 raw minus the one `//` comment line at
`diff_panel_ui_tests.rs:5` — + 736 fully-qualified + 45 `gpui_kit`;
core 1,832, `coincide-mcp-server` 20, desktop 1,148). Swift `@Test`
verified at 128 and left alone.

**Tests added (4):** `read_file_refuses_literal_git_config_path`
(`workspace.rs:848`, paged path directly — literal `.git/config`
and `.git` refused, `sub/notes.txt` and `dotted.name.txt` still
read); `read_file_refuses_intermediate_symlink`
(`workspace.rs:868`, paged path directly — `link/config` refused
where `link -> .git`, and `alias/notes.txt` refused where `alias`
points at a real in-workspace directory, proving the stricter
tradeoff; `real/notes.txt` still reads);
`read_file_refuses_literal_git_config_on_both_paths`
(`workspace_tools.rs:914`, non-paged plus paged through the public
entry); `read_file_refuses_intermediate_symlink_on_both_paths`
(`workspace_tools.rs:943`, non-paged plus paged, including the
in-workspace `alias` refusal on both paths). All written, not
executed — `cargo test -p coincide-core` on Dylan's Mac is the gate.

**Verification:** static only (no cargo in this environment, as for
every slice in this record). Each fix traced by hand (literal
`.git/config` refused on both paths; `link/config` refused on both
paths; normal files, files in subdirectories, and files with dots in
names still read on both paths); brace/paren/bracket deltas zero-net
vs. the parent on both Rust files; zero new `//` comments in the Rust
diff; no secrets; no registry definition, param, or description
changed. Full diff read — only the five intended files, only the
intended hunks. The local pre-push commit SHA and tree are in the
slice's push report; the remote SHA was verified against the GitHub
API and backfilled by Slice 148
(`81cf2e4c84f4678c528393b7fc465fd2b23dd157`, tree
`ecda0cbf386883c446f5d4d6693f22ee079f544a`, parent
`4dc0a1440ee07f29b574db5490b8a8c9f95a4a3d`).

**Mac-gate checks owed:** the 4 new tests above, plus the Xcode
build as usual; no new Mac-gate surface beyond the tests.

## Slice 148 — Success-path `execute()` tests for the highest-value untested registry tools (remote `1c1905f7`, 0 defects, 15 tests)

**Audited:** Slice 143's coverage numbers, re-measured first with a
fresh script plus hand-check (`/tmp/slice148_coverage.py` — per-tool
`execute()` / `Self.run()` call sites in `AgentsTests`, success
context = a call not inside a `do` block ending in
`Issue.record("Expected…")`; multi-name arms mapped so a tool
sharing an arm with a tested sibling counts as arm-shared-only, not
uncovered). The script reproduces Slice 143 exactly on the
pre-change tree: 246 direct / 174 arm-reached (52.4%) / 72
validation-only / 29 arm-shared-only / 57 truly uncovered —
including the group splits (git 15 truly uncovered, computer-use 16
not directly covered, memory 1, workers 1). Each target arm was then
hand-traced in `SystemToolRegistry.swift` `execute()` before its test
was written, following the existing `file_create` round trip
(`GitCompletionTests.swift:539,545`), `mem_store` round trip
(`MemoryTests.swift:109,114,119`), `todo_scan`
(`ToolsetTests.swift:1476`), and `project_snapshot`
(`GitCompletionTests.swift:377,387`) patterns. No test fakes success
or asserts on an error path as if it were success.

**Tests added (15):** all written, not executed — Xcode build +
`swift test` on Dylan's Mac is the gate.

- `write_file` — `writeFileWritesRealContent`
  (`ToolsetTests.swift:2965`): writes `notes/hello.txt` through
  `execute()`, asserts the returned path and the on-disk bytes.
- `read_file` — `readFileReadsRealContent`
  (`ToolsetTests.swift:2979`): reads `docs/readme.txt` written by the
  test; asserts path and content `alpha\nbeta\n` — the Swift
  `execute()` path returns the file bytes verbatim: the arm
  (`SystemToolRegistry.swift:3846-3850`) hands
  `runtime.readWorkspaceFile`'s `WorkspaceFileDocument.content`
  straight through, and the Rust side returns
  `read_workspace_text`'s `String::from_utf8(bytes)` verbatim as
  `"content"` (`workspace_tools.rs:580-606`, via
  `workspace_ops.rs:444-445` and `AgentsFFIBridge.swift:1191-1200`),
  with the decoder preferring `"content"`
  (`DesktopModels.swift:1484-1487`). The line-joining
  `workspace::read_file` (`workspace.rs:738`) serves only the engine
  `files.read` API (`api.rs:810`) and is never on the Swift path — it
  is reached from `workspace_tools::read_file` only when
  `lineOffset`/`lineLimit` are passed, which the arm never sends.
  (Corrected in Slice 150: this section originally asserted
  `alpha\nbeta`, citing the line-joining read.)
- `search_files` — `searchFilesFindsRealToken`
  (`ToolsetTests.swift:2994`): one hit, path
  `Sources/Store.swift`, line 2, line text contains the token.
- `create_terminal` — `createTerminalReturnsLiveId`
  (`ToolsetTests.swift:3013`): non-empty terminal id, viewport rows
  and cols above zero.
- `write_terminal` + `read_terminal` —
  `writeAndReadTerminalRoundTrip` (`ToolsetTests.swift:3038`): writes
  `echo hello-terminal-148`, polls `read_terminal` up to 15 s, asserts
  the text appears in the terminal lines; asserts the write result
  echoes the terminal id.
- `list_files` — `listFilesListsFixtureFiles`
  (`GitCompletionTests.swift:632`): the fixture repo's `a.txt`,
  `b.txt`, `c.txt` are all listed (the arm runs `git ls-files`, so
  the test uses the git fixture, not a plain directory).
- `git_status` — `gitStatusReportsBranchAndDirtyEntries`
  (`GitCompletionTests.swift:650`): dirties `a.txt`, asserts a
  non-empty branch and an entry for `a.txt` whose status contains
  `M`.
- `git_diff` — `gitDiffReturnsUnstagedDiff`
  (`GitCompletionTests.swift:672`): staged false, diff contains
  `a.txt` and `+three`.
- `git_log` — `gitLogReturnsFixtureCommits`
  (`GitCompletionTests.swift:692`): 3 commits, subjects
  third/second/first, author `Fixture`.
- `git_push` — `gitPushPublishesToLocalBareRemote`
  (`GitCompletionTests.swift:712`): pushes to a local bare repo as
  `origin` (no network); asserts outcome `pushed`, upstream
  `origin/<branch>`, and the bare remote's ref equals the repo HEAD.
- `git_pull` — `gitPullFetchesFromLocalBareRemote`
  (`GitCompletionTests.swift:737`): pushes, commits a new file via a
  second clone of the bare remote, pulls; asserts `pulled` true and
  the new file lands in the fixture repo.
- `git_branch_list` — `gitBranchListListsLocalBranches`
  (`GitCompletionTests.swift:774`): `spare` listed, `currentBranch`
  non-empty and equal to the `isCurrent` branch's name.
- `git_branch_checkout` — `gitBranchCheckoutSwitchesBranches`
  (`GitCompletionTests.swift:797`): result branch `spare`, confirmed
  by a `git_status` call reading `spare`.
- `save_to_memory` — `saveToMemoryStoresFact`
  (`MemoryTests.swift:222`): `overwritten` false, `mem_retrieve`
  reads `uses tabs` back.
- `take_screenshot` — `takeScreenshotReturnsDesktopState`
  (`ComputerUseTests.swift:98`): enables Computer Use first (turned
  off again at the end, following the existing `enableRoundTrips`
  pattern), calls with `include_screenshot` false, asserts
  `coordinateSpace` `screen_points`, real `apps` / `windows` arrays,
  and a null `screenshot`.

**Coverage after (re-measured with the same script + hand-check):**
direct 246 → 261, arm-reached 168 → 184 (50.6% → 55.4%),
validation-only 78 → 77 (`read_file` moves out), arm-shared-only 29
unchanged, truly uncovered 57 → 42. By group: memory 10/10
arm-reached (`save_to_memory` was the lone uncovered); computer-use
truly uncovered 1 → 0 (`take_screenshot` was the lone one; 15
remain arm-shared-only behind the shared 20-tool arm); git 15 → 8
truly uncovered; terminal arm 1 → 4 (action-`terminal.*` group, 62
tools: `project_signing` plus the three new terminal tools);
workspace 143 → 147. (Restated in Slice 150 under the strict
success-context rule — see the correction note below; this section
originally printed the Slice 143 method's 174 → 190 / 72 → 71 and
terminal arm 3 → 6.)

**Correction of the record (Slice 150):** the arm-reached and
validation-only figures in this section were measured with the Slice
143 method, whose success test is only "not inside a `do` block ending
in `Issue.record("Expected…")`" — it misses call sites inside
`#expect(throws:)` closures and counts those as success. Six tools
were wrongly counted arm-reached in both periods:
`fetch_documentation`, `github_repo`, `reverse_analyze`,
`search_web`, `svg_to_png`, `use_app` — every call site of each is
inside a `#expect(throws:)` closure expecting an argument or
validation error, so none ever executes successfully. (Slice 149's
report names the six `computer_use.*` validation-only tools instead;
that identification is wrong — `click`, `get_window_state`,
`invoke_menu`, `launch_app`, and `scroll` are validation-only under
both methods, and only `use_app` of that set is in the gap.) Under the
strict success-context rule — a call site counts toward arm-reached
only if it is not inside a `#expect(throws:)` closure, not inside a
`do` block whose body after the call contains
`Issue.record("Expected…")`, and not called with `toolset: .provider`;
arm-shared-only still means sharing an `execute()` switch arm with a
directly-called tool — the figures are arm-reached 168 → 184 (50.6% →
55.4%), validation-only 78 → 77, direct / arm-shared-only / truly
uncovered unchanged at 246 → 261 / 29 / 57 → 42. The same blind spot
is behind the terminal figure: under the Slice 143 method the
action-`terminal.*` arm was 3 → 6 (`project_signing` plus
`svg_to_png` and `reverse_analyze`, both called only inside
`#expect(throws:)` in `sliceEighteenInvalidArgumentsRefused`, plus
the three new terminal tools); under the strict rule it is 1 → 4.
The 174/190 and 72/71 figures quoted in the "Audited" paragraph above
are the Slice 143 method's output and are superseded by the strict
figures here.

**Left uncovered (1 of the 16 targets):** `start_subagent` — spawn
starts a live provider turn via `send_turn`
(`workers_api.rs` `spawn_one_worker`); there is no hermetic path,
and a test would launch a real agent process needing a provider CLI
plus credentials plus network. Left uncovered deliberately and
recorded here, not faked.

**Also fixed (1 test assertion, not counted as a defect):** the
pre-existing `useMcpListsAndExecutes` assertion read
`read["text"]`, but the `read_file` arm returns
`{"path", "content"}` — the assertion could never pass. Corrected to
`read["content"]` (`GitCompletionTests.swift:628`). Test-only,
following the Slice 105/109 precedent, not counted in the defect
total.

**Still uncovered after this slice (42):** workspace 19 —
`code_multi_edit`, `code_replace`, `copy_file`, `create_directory`,
`delete_directory`, `dir_create`, `dir_delete`, `dir_read`,
`file_append`, `file_copy`, `file_delete`, `file_move`, `file_read`,
`file_write`, `list_directory`, `read_directory`,
`search_directory`, `search_text`, `view_file` (same-arm siblings
of tools this slice tested — the cheapest next slice, same
patterns); git 8 — `git_bisect`, `git_blame_inspector`,
`git_branch_compare`, `git_diff_branch`, `git_diff_range`,
`git_log_viewer`, `git_show`, `project_diff` (read-only git tools,
same fixture pattern as this slice's git tests); terminal 10 —
`disk_space_analyzer`, `icon_generator_tool`,
`package_dependency_audit`, `package_manifest_validate`,
`preflight_checks`, `process_monitor_tool`, `run_command`,
`spm_dependency_tree`, `use_system`, `use_terminal` (arms that build
a shell command and run it via `runTerminalCommand`, or script-driven
tools on the terminal-create path — same terminal fixture as this
slice); system 2 — `clipboard_manager_tool`,
`system_notification_tool` (live OS surface: clipboard,
notifications); web 2 — `external_resource_gateway`,
`read_url_content` (live network fetch); workers 1 — `start_subagent`
(live provider turn, see above).

**Verification:** static only (no Swift toolchain in this
environment, as for every slice in this record). Each new test
hand-traced: valid arguments, real `execute()` path, assertion on
the real result; test names, tool names, and expected values checked
against the arm code and the Rust shapes behind it (read returns
bytes verbatim, `terminal.read` snapshot `lines`, git log/status/diff JSON,
`git.actions.run` push result, `git.branches.list` /
`git.branches.checkout` JSON, `get_desktop_state` result). Brace
balance re-checked on all four changed test files (deltas zero vs.
the parent; the ToolsetTests paren delta of −1 is pre-existing at
HEAD, from parens inside string literals); zero new `//` comments;
no secrets; no registry definition, param, or description changed.
Full diff read — only the seven intended files, only the intended
hunks. The local pre-push commit SHA and tree are in the slice's
push report; the remote SHA is `1c1905f7d2deea0ad76ad723b0b8e21e0e351cc3`
(tree `1f49c82b7586953dbf88984b77de59fea94ae6e5`, parent
`81cf2e4c84f4678c528393b7fc465fd2b23dd157`, verified against the GitHub
API), backfilled by Slice 150.

**Mac-gate checks owed:** the 15 new tests above, plus the Xcode
build as usual. Two honest limits ride with them:
`take_screenshot` with `include_screenshot` true (the real PNG
capture) is still unverified in tests — it needs Screen Recording
permission for the test host, which a test cannot grant itself; and
`start_subagent` still needs a live provider turn.

## Slice 150 — Slice 149 re-verification fixes: wrong `read_file` expectation + two MINOR doc corrections (1 defect, 0 tests)

**Re-verified:** Slice 149's re-verification of Slice 148 (verdict NOT
CLEAN — see the note in [How to re-verify](#how-to-re-verify)). Its
MAJOR finding re-traced end-to-end here, the other 14 Slice 148 tests
re-checked against their arms, and both MINORs re-derived with fresh
scripts (Slice 148's script on the pre-change tree and at HEAD, Slice
149's strict script at both revs, plus a derivation script combining
the strict classification with the Slice 143 arm-shared rule).

**Fixed (1):** the wrong `read_file` test expectation —
`readFileReadsRealContent` (`ToolsetTests.swift:2980`) expected
`"alpha\nbeta"` for a file written as `"alpha\nbeta\n"`. The Swift
`execute()` path returns the file bytes verbatim: arm
`SystemToolRegistry.swift:3846-3850` → `runtime.readWorkspaceFile` →
`desktopCall(action: "workspace.read_file")`
(`AgentsFFIBridge.swift:1191-1200`) → FFI `workspace_read_file`
(`workspace_ops.rs:444-445`) →
`coincide_core::workspace_tools::read_file`
(`workspace_tools.rs:580-606`), whose `read_workspace_text`
(`workspace_tools.rs:233-254`) returns
`String::from_utf8(bytes)` verbatim and sets `"content"` to that
verbatim string; `WorkspaceFileDocument`'s decoder prefers
`"content"` (`DesktopModels.swift:1484-1487`). The arm sends no
`lineOffset`/`lineLimit`, so the line-joining `workspace::read_file`
(`workspace.rs:738`, engine `files.read` only, `api.rs:810`) is never
on this path. The fixture keeps its trailing newline and the
expectation is now `"alpha\nbeta\n"` — the verbatim-bytes behavior is
the real contract worth asserting. One expectation line changed;
counted as the slice's 1 defect because the wrong expectation would
fail on the Mac gate.

**Description-only corrections (2, not counted as defects, following
the Slice 105/109 precedent):**

- **Terminal arm 3 → 6 does not reproduce under the strict rule.**
  Slice 148's method counted `svg_to_png` and `reverse_analyze` as
  arm-reached because their only call sites are `#expect(throws:)`
  closures in `sliceEighteenInvalidArgumentsRefused`, which its
  do-block-only heuristic misses. Restated with the grouping explicit:
  action-`terminal.*` group (62 tools), arm-reached 1 → 4
  (`project_signing` plus `create_terminal`, `write_terminal`,
  `read_terminal`); the +3 delta is unchanged.
- **Arm-reached / validation-only figures restated.** Slice 143/148's
  method over-counted arm-reached by 6 in both periods (see the
  correction note in the Slice 148 section above). Restated:
  arm-reached 168 → 184 (50.6% → 55.4%), validation-only 78 → 77;
  direct 246 → 261, arm-shared-only 29, truly uncovered 57 → 42
  unchanged. The 42-set equals the docs' listed 42 exactly.

**Classification rule (strict success-context rule, for future
re-measurement):** a call site counts toward arm-reached only if it
is not inside a `#expect(throws:)` closure, not inside a `do` block
whose body after the call contains `Issue.record("Expected…")`, and not
called with `toolset: .provider`. A tool is arm-reached iff it has at
least one success-context call site; validation-only iff it is called
but has none; arm-shared-only iff it is not called but shares an
`execute()` switch arm with a directly-called tool (the Slice 143
rule, unchanged).

**Per-test re-check (the other 14 Slice 148 tests — no further wrong
expectation found):** `write_file` writes bytes verbatim
(`write_regular_utf8`, `workspace_tools.rs:655`); `search_files`
line numbers are 1-based ripgrep lines, decoded `line`→`lineNumber`,
`text`→`lineText`; `create_terminal` returns the id string and the
viewport rows/cols come from the live terminal; `write_terminal`
returns `{"terminalId"}` and `terminal.read`'s `snapshot()`
(`terminal.rs:747`) returns `{"lines": [...]}`; `list_files` runs
`git ls-files --cached --others` and the bare-string entry decoder
takes the path verbatim; `git_status` returns
`{"branch","entries":[{"status","path"}]}` with porcelain `" M"`
containing `M`; `git_diff` returns `{"diff","staged":false}` with
the unstaged `+three` hunk; `git_log` is newest-first with
`{"subject","authorName"}`; `git_push` returns
`result.push.outcome` `"pushed"` (camelCase serde) with upstream
`origin/<branch>`; `git_pull` returns `{"pulled": true}` when HEAD
advances; `git_branch_list` returns camelCase
`branches[{name,isCurrent}]` + `currentBranch`;
`git_branch_checkout` returns `{"branch": "spare"}`;
`save_to_memory` matches the pre-existing `mem_store` round trip
(`overwritten` false on first store); `take_screenshot` with
`include_screenshot` false returns `screenshot` null and
`coordinateSpace` `"screen_points"`.

**Verification:** static only (no Swift toolchain in this
environment, as for every slice in this record). The read_file chain
re-traced end-to-end; both coverage scripts re-run at the pre-change
tree (`77475429`) and HEAD, with a third derivation script
cross-checking the strict classification against the Slice 143
arm-shared rule; the 42-set compared set-equal with the docs' listed
42; Swift `@Test` 143 (124 + 19) and Rust 3,012 re-measured; program
diff 224 files +55,778/−3,596 re-measured against the program base
`04b235e3`. Brace balance re-checked on all three changed files
(deltas zero vs. the parent); zero new `//` comments; no secrets; no
registry definition, param, or description changed. Full diff read —
only the three intended files, only the intended hunks. The local
pre-push commit SHA and tree are in the slice's push report. Remote SHA
backfilled by Slice 152 as
`e9a46e9cae70af8bad914d307673d5332332ed2c` (tree
`66e6d43460f3ba5d05fddd77740992c77306ee40`, parent
`1c1905f7d2deea0ad76ad723b0b8e21e0e351cc3`, same tree as local
`b6caaffb`).

**Mac-gate checks owed:** the corrected `read_file` test, plus the
Xcode build as usual; no new Mac-gate surface beyond the test
correction.

## Slice W5 — Workers/subagents UX + retention default (4 fixes, 3 tests)

**Fixed (4):**

1. **Worker thread is tappable.** The worker detail used to show the
   child thread as a raw UUID string with no action
   (`WorkersInspectorView.swift`, detail line). It is now a button
   labelled with the worker thread's own title, `Worker: <name>`
   (the title `spawn_one_worker` gives the child thread in
   `workers_api.rs`), which selects that thread through the existing
   `appModel.selectThread(_:)` pattern, the same call the sidebar
   uses. The raw UUID is no longer shown.
2. **Newest-first worker order.** `load_workers`
   (`worker_store.rs`) sorted ascending by `createdAt`, so the oldest
   worker sat at the top and `workers.list` (`workers_api.rs`, which
   returns `load_workers` order) and the inspector rendered oldest
   first. The sort is now descending, so the newest worker is at the
   top in the list response and in the inspector, which renders the
   returned order.
3. **N/32 cap indicator.** `MAX_WORKERS_PER_PARENT` is 32
   (`worker_store.rs:11`) and spawn fails at the cap, but nothing
   surfaced the count until then. The inspector header now shows
   `N/32 running` in the Current Thread scope (always, including
   `0/32`), turning warning-coloured at 32; the All Workers scope
   keeps the plain `N running` label, since the cap is per parent
   thread and a cross-parent total against 32 would mislead.
4. **Worker-record retention, default 50.** `worker_records` was
   append-only with no delete or prune path (recorded as open since
   Slice 77 in [Documented, not fixed](#documented-not-fixed)). A new
   `Store::worker_delete(id)` (`store.rs`) deletes one record row,
   and `worker_store::insert_record` now prunes after every spawn:
   per parent thread, only terminal (completed/failed/cancelled)
   records older than the newest N are deleted; all running records
   are kept, records of other parents are untouched, and only record
   rows are deleted — the child thread itself is never touched. The
   limit comes from the new `settings.json` key
   `workerRetentionCount` (Int, default 50, 0 keeps everything),
   read by `worker_store::retention_limit` with a float-tolerant
   parse, since the Settings stepper writes it as a JSON number. The
   key is described in the settings snapshot and accepted by the
   change allowlist (`adapter_bridge.rs`, new Workers section on the
   General page, 0–500 step 1, unit "records"), and the Mac General
   pane now renders `.number` rows as a Stepper
   (`GeneralSettingsPane.swift`), which previously dropped them. The
   phone Settings UI already rendered `.number` rows as a Stepper
   (`MacSettingsViews.swift:95`), so the row surfaces there too.
   **The 50 is a default this slice chose, not Dylan's decision:**
   he can change it in Settings › General › Workers, or set 0 to
   keep everything.

**Tests added (3):** in `worker_store.rs` —
`retention_limit_defaults_to_fifty_and_reads_settings`,
`retention_prunes_oldest_terminal_records_per_parent_and_keeps_running`
(keeps the newest 2 terminal records for the parent, keeps the
running record, leaves another parent's records alone, and confirms
newest-first order), and
`retention_zero_keeps_every_terminal_record`. No manual
`workers.delete`/`clear` route and no retry/respawn were added; both
remain out of scope for this slice.

**Verification:** static only (no Swift toolchain, no cargo in this
environment, as for every slice in this record). Full diff read —
only the intended files, only the intended hunks; brace balance
re-checked on all changed files; zero new `//` comments; no secrets;
no registry definition, param, or description changed; updater,
Privacy URL, and `remote_protocol.rs:655` untouched. The local
pre-push commit SHA and tree are in the slice's push report.

**Mac-gate checks owed:** Xcode build + `swift test` + `cargo test`
as usual; the new worker retention tests; the inspector tap-to-open,
`N/32` header, and retention stepper exercised live, including a
spawn past 50 finished workers for one parent confirming the oldest
terminal record disappears while its child thread remains.

## Slice W8 — workers.delete route + retry/respawn (2 fixes, 1 test)

**Fixed (2):**

1. **Manual `workers.delete` route.** `workers_api.rs` gains a
   `workers.delete` engine route (`METHODS` + `workers_command`
   dispatch + `workers_delete`), wired through the existing FFI
   fallthrough: `workspace_ops.rs` passes unknown desktop actions
   to `dispatch_engine_method`, and `Engine::execute` routes any
   `workers.*` method in `workers_api::METHODS` to
   `workers_command`, so no FFI dispatch file needed a new arm.
   The route refreshes the record first (so a stale `running`
   record that actually finished becomes terminal instead of
   erroring), then deletes only terminal records
   (`completed`/`failed`/`cancelled`) via the existing
   `Store::worker_delete(id)` from Slice W5; deleting a running
   worker returns an explicit error, never silently drops a live
   worker. Only the record row is deleted, never the child thread.
   Swift side mirrors `workers.cancel`: `deleteWorker(workerId:)`
   in `AgentsFFIBridge.swift`, a `delete_worker` definition plus
   dispatch case in `SystemToolRegistry.swift`, and a Delete
   button in the inspector detail view for terminal records only,
   behind the same `.confirmationDialog` pattern Git restore uses.
2. **Retry/respawn for failed/cancelled workers.** A Retry button
   in the inspector detail view re-spawns through the existing
   `workers.spawn` path with the same name, task, target files,
   and parent thread — no new Rust spawn path. A retry creates a
   new worker record; the old failed/cancelled record stays for
   history. No name-policy change was needed: `check_spawn_allowed`
   in `worker_store.rs` only rejects a name already held by a
   *running* worker for the same parent, so a terminal record's
   name (and target files) are free to reuse.

**Tests added (1):** in `workers_api.rs` —
`delete_removes_terminal_records_and_refuses_running_workers`
(running delete errors with the terminal-only message and leaves
the record in place; cancel then delete succeeds, returns
`{"deleted": true, "workerId": ...}`, and the record is gone;
deleting again errors `Unknown worker`; the child thread still
exists).

**Verification:** static only (no Swift toolchain, no cargo in this
environment, as for every slice in this record). Full diff read —
only the intended files, only the intended hunks; brace balance
re-checked on all changed files; zero new `//` comments; no secrets;
no registry definition, param, or description changed except the
new `delete_worker` tool; updater, Privacy URL, and
`remote_protocol.rs:655` untouched. The local pre-push commit SHA
and tree are in the slice's push report.

**Mac-gate checks owed:** Xcode build + `swift test` + `cargo test`
as usual; the new `workers.delete` test; the inspector Delete
(terminal records only, confirmation dialog, record gone, child
thread still listed) and Retry (failed/cancelled worker respawns
with the same name, task, and target files, old record kept)
exercised live, including a delete attempt on a running worker
returning the explicit terminal-only error.

**Left open by this slice:** no bulk `workers.clear` route.
`workers.delete` is also not yet listed in the engine
`methods.list` introspection surface (`api.rs`) or the MCP server
tool catalog (`tools.rs`); both files were outside this slice's
scope, and the Swift inspector calls the route directly through
the FFI fallthrough, so it works without those listings.

## Documented, not fixed

Items the audits found, recorded, and deliberately left open. None of
these is a silent known-bad state: each was an explicit decision, a
limitation of the audited component, or a question owed to Dylan.

- **Worker-record count was unbounded — now bounded by a retention
  default (Slice W5).** One record is created per worker spawn and
  there was no per-record delete or prune path in
  `worker_store.rs` / `workers_api.rs` (verified: no delete/prune
  function there; the only worker-related delete in `store.rs:255,275`
  removes the whole `workers.json` document). Slice W5 added
  `Store::worker_delete(id)` plus pruning in
  `worker_store::insert_record`: per parent thread the newest 50
  terminal records are kept (default; `workerRetentionCount` in
  `settings.json`, 0 keeps everything), running records are always
  kept, and only record rows are deleted, never the child thread. The
  50 is a default this slice chose, not Dylan's decision — he can
  change it in Settings › General › Workers. Slice W8 closed the
  manual-delete and retry parts: a `workers.delete` engine route
  (terminal records only; deleting a running worker is an explicit
  error), a `delete_worker` system tool, an inspector Delete button
  behind the same confirmation-dialog pattern as Git restore, and a
  Retry button for failed/cancelled workers that re-spawns through
  the existing `workers.spawn` path with the same name, task,
  target files, and parent thread — the old record stays for
  history, and no name-policy change was needed because spawn only
  rejects a name already held by a *running* worker. Still open:
  no bulk `workers.clear` route.
- **MCP server is a sequential loop.** `main.rs` reads and dispatches one
  stdio frame at a time, so a slow `tools/call` blocks all other requests;
  there is no tools/call-level timeout (verified: no `timeout` in `main.rs`
  or `protocol.rs`). The frame itself is size-capped at 16 MiB
  (`main.rs:22`, `MAX_FRAME_BYTES`), but that bounds frame size, not call
  duration. Documented limitation (Slices 31/71). Panic isolation for
  per-request dispatch was fixed in Slice 134 (`dispatch_guarded` in
  `protocol.rs`, `-32603` fixed-message error, server keeps serving); the
  sequential loop and the missing tools/call timeout remain open.
- **No overall turn-level timeout; context budget is a fixed 2 MiB cap,
  not per-provider.** A browser-only turn timeout exists
  (`browser_protocol.rs:119,148`) — that is not an overall turn timeout.
  The 2 MiB figure appears as fixed caps such as `handoff_prompt.rs:7`
  (`MAX_TEXT`) and the scope check in `follow_up_api.rs:630`.
  (Slices 33/38.)
- **Check-then-open-by-path TOCTOU in workspace reads.** Paths are
  validated by `existing_workspace_target` (`workspace_tools.rs:169`) and
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
  not introduced by this wave (Slices 64/70). Whether to remove it is the
  parent's call, per the coordinator's standing instruction.
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
- **`.git` guards are exact-byte: `.GIT` passes on a case-insensitive
  filesystem.** The guards in `workspace.rs:290–294`,
  `workspace_tools.rs:154–158`, and `workspace_ops.rs:970–974`
  (coincide-macos-ffi) all compare
  `part.as_os_str().as_encoded_bytes() != b".git"`, so `.GIT` passes the
  guard while resolving to the real `.git` on macOS's case-insensitive
  APFS (`.GIT/config` reads the real `.git/config`). No `.GIT` test
  exists (Slice 147 INFO-3). Documented, not fixed.
## How to re-verify

- **Registry 332 check.** Count the `ToolDef {` entries inside the
  `DEFINITIONS` slice in
  `Rust Backend/crates/coincide-mcp-server/src/tools.rs:47` — expect 332
  (re-verified at HEAD: exactly 332; the one further `ToolDef {` match is the
  `pub struct ToolDef {` declaration at `tools.rs:14`, not a registry entry). Cross-check the same
  332 names, actions, and order against
  `Agents/Core/SystemTools/SystemToolRegistry.swift`; the canonical
  description is `docs/SYSTEM-TOOLSET.md:57-61`.
- **MAC-GATE count method.** From `Rust Backend`, excluding `vendor/`:
  count short-form `#[test]` attributes, fully-qualified
  `#[::core::prelude::v1::test]` attributes, and `#[gpui_kit::test]`
  attributes, and sum them. At HEAD the
  expected total is **3,012** (2,231 + 736 + 45). Method and per-crate table:
  `docs/MAC-GATE.md:139-173`. Known wrinkle documented there: one `//`
  comment line in `crates/coincide-desktop/src/diff_panel_ui_tests.rs:5`
  mentions the glob import and must not be counted as an attribute; and
  the 1,033 `#[gpui::test]` / 25 `#[crate::test]` lines a repo-wide grep
  finds are all inside `vendor/` and must not be counted either.
  **Slice 104 re-verification (no commit):** Slice 104 re-audited Slice
  103 read-only and passed it with minors — the Rust total correction
  from 2,955 to 3,000 (the 45 `#[gpui_kit::test]` attributes, all in
  `coincide-desktop`, had not been counted) and `docs/MAC-GATE.md`
  staleness (105 Swift `@Test`, 2,953 Rust total) came out of that
  re-verification; both were fixed in Slice 105, which also corrected the
  registry param descriptions to the pinned behavior (see the Slice 101
  section above).
  **Slice 106 re-verification (no commit):** Slice 106 re-audited Slice
  105 read-only and passed it with minors — recorded here from the
  verification report, since the slice left no commit to re-derive from.
  It independently re-measured all counts (128 Swift `@Test`, 3,000 Rust
  including 45 `#[gpui_kit::test]`, per-crate table), ran a full
  string-aware parse of both registries (332 tools / 1,087 params each
  side, 0 mismatches), and confirmed the pinned test expectations match.
  Six findings: (1) MINOR — worker-report inaccuracy: the "zero old
  wording remains anywhere" claim overstated, since this record's Slice
  101 section quotes both old wordings as a historical record (`:417`) —
  legitimate, left as-is; (2) MINOR — the `list_workers` description
  misdescribed bound behavior, fixed in Slice 107; (3) MINOR —
  inconsistent treatment of the pinned plan descriptions, fixed in Slice
  107; (4) NOTE — worker misattribution: the "Parent thread ID to
  include worker status for." string belongs to `session_progress_report`,
  not `worker_status`; (5) TRIVIAL — pre-existing ToolDef-struct
  imprecision, fixed in Slice 107; (6) TRIVIAL — loose `:4419` line
  citation, fixed in Slice 107.
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
  **Slice 110 re-verification (no commit):** Slice 110 re-audited Slice
  109 read-only and passed it with minors — all code claims exact
  (129/129 identity params, byte-identical cross-side). The minors were
  the Slice 106 entry in `docs/SYSTEM-TOOLSET.md` overstating the
  pre-107 parentThreadId pin (2 of 6 pinned, not all 6) and two
  off-by-one line cites in the Slice 109 section; both were fixed in
  Slice 111.
  **Slice 112 re-verification (no commit):** Slice 112 re-verified Slice
  111 read-only and passed it with zero findings — the Slice 110 fixes,
  the Slice 109 SHA backfill, and the Slices 105/107 sections all
  confirmed as written.
  **Slice 115 re-verification (no commit):** Slice 115 re-verified Slice
  114 read-only and passed it with one minor — the `:412` line cite in
  this record's Slice 106 note, corrected to `:417` in Slice 116.
  **Slice 117 re-verification (no commit):** Slice 117 re-verified Slice
  116 read-only and passed it with zero findings — the `:412` → `:417`
  cite correction confirmed.
  **Slice 119 re-verification (no commit):** Slice 119 re-verified Slice
  118 read-only and passed it with minors — the `provider/event`
  persistence wording overstated what is persisted, three line cites
  were off by one to three lines, and `docs/MAC-GATE.md` was stale
  (Rust total 3,000, core 1,822); all fixed in Slice 120.
  **Slice 123 re-verification (no commit):** Slice 123 re-verified Slice
  122 read-only and passed it with minors — (1) MINOR — the Slice 122
  §2 "TerminalDrawerRootView row precedent" wording was half-right: the
  terminal row does use the identical traits expression, but it has no
  `.accessibilityElement(children: .combine)` and no
  `.accessibilityAction`, and those two modifiers appear nowhere else in
  `Agents/`; (2) MINOR — `docs/MAC-GATE.md` §2.9 still said Slice 32
  "left 3 controls unresolved"; (3) TRIVIAL — the Slice 122 sweep
  paragraph called `ProvidersSettingsPane.swift:549,553` the "KEY/Value
  fields", but those are the two Value fields and the KEY field is at
  `:543` and predates Slice 32. Correlated note: the terminal session
  row itself may not be VoiceOver-activatable (tap-to-select, `.isButton`
  trait only, no action). All fixed or recorded in Slice 124.
  **Slice 125 re-verification (no commit):** Slice 125 re-verified Slice
  124 read-only and passed it with minors — one MINOR: the Slice 124
  "Defects fixed (0)" paragraph overstated the diff row's combined
  children as all non-interactive, ignoring the three hover-revealed
  buttons inside the combined element
  (`DiffInspectorView.swift:727-758`); mitigated because the buttons
  render only when hovered, a state VoiceOver users effectively never
  trigger, and each action is duplicated in the context menu. Fixed in
  Slice 126.
  **Slice 129 re-verification (no commit):** Slice 129 re-verified Slice
  128 read-only and passed it with minors — (1) MAJOR — the Slice 128
  Rust test total was 3,003 / desktop 1,149, counting the raw short-form
  total without subtracting the one `//` comment line at
  `diff_panel_ui_tests.rs:5`; the true total is 3,002 real (2,221 real
  short-form + 736 fully-qualified + 45 `gpui_kit`), desktop 1,148
  real, and the brief's 3,002 / 1,148 expectation was correct — Slice
  128's sentence claiming the brief was off by one was backwards;
  (2) MINOR — the Slice 128 `rust.yml` cite attached the macOS job to
  the Windows/Linux step lines `:415,668`; the macOS job is `desktop`
  at `:124`. Both fixed in Slice 130.
  **Slice 131 re-verification (no commit):** Slice 131 re-verified Slice
  130 read-only and passed it with zero findings — remote `3da030fd` /
  tree `380ec967` match the live API and the local HEAD `d1f46398`; the
  Slice 130 diff touches only the two docs files; F1 counts re-measured
  at HEAD as 3,002 real / 1,148 desktop (2,221 real short-form + 736
  fully-qualified + 45 `gpui_kit`; desktop 368 raw short-form); F2
  `rust.yml` cites exact (`desktop` :124, `desktop-windows` :296 step
  :415, `desktop-linux` :532 step :668); the Slice 128 backfill is
  present; totals recounted at 29 defects / 27 tests; program diff
  224 files +54,116/−3,595.
  **Slice 132 re-verification (no commit):** Slice 132 was the final
  full-repo re-verification and passed with zero findings — sync
  tree-identical; registry 332/332/332 with 0 mismatches (1,087 params
  each side, 63 distinct actions); catalog 279/300 (278 exact + 1 alias
  + 1 duplicate + 20 NONE); 10-tool realness sample 9 REAL + 1
  real-but-heuristic (`search_symbol`), 0 stubs; Swift `@Test` 128,
  Rust 3,002 real, Swift files 148, Rust files 707 excluding `vendor/`,
  docs 28, program diff 224 files +54,116/−3,595, 90 commits; secrets
  sweep 0 real; comments sweep 0 new code comments (6 `//` lines all
  explained); all 8 open items still accurately documented.
  **Slice 135 re-verification (no commit):** Slice 135 re-verified Slice
  134 read-only and passed it with minors — the one MINOR is a docs
  staleness, fixed in Slice 136 (remote
  `92cc6f32698235ca9c24d7b2b967cf84f27dc97a`, tree
  `963d7ddd7ebe51dcd6a788835ac0af9dedece72d`, parent
  `33cc12f1cd1161590f84bcb777e3107e742954b2`, verified against the GitHub
  API by Slice 138): the Rust test total in
  `docs/MAC-GATE.md` still said 3,002, but Slice 134's new test made it
  3,003. The Slice 134 verdict itself stands: sync tree-identical
  (remote `33cc12f1` / tree `27f24342`); the gap is real (zero
  `catch_unwind` in the crate at the parent; the trigger is
  `g6_xcstrings_set` at `tools.rs:11870` with `{"strings": 42}`); the fix
  is `dispatch_guarded` in `protocol.rs:96-101`, returning `-32603` with
  the fixed message `"request handler panicked"`, covering all 8
  dispatched methods, with the `run()` loop continuing after a caught
  panic; the test
  `panicking_tool_call_returns_internal_error_and_the_server_survives`
  in `tests/mcp_server.rs:570-598` drives the real server binary over
  stdio and was written, not executed — `cargo test -p
  coincide-mcp-server` on Dylan's Mac is the gate. Counts re-measured
  at HEAD as 3,003 real / 1,148 desktop (2,222 real short-form + 736
  fully-qualified + 45 `gpui_kit`; desktop 368 raw short-form;
  `coincide-mcp-server` 19). The Slice 134 diff touches only the four
  intended files (+147/−14); totals recounted at 30 defects / 28 tests;
  program diff 224 files +54,272/−3,595.
  **Slice 137 re-verification (no commit):** Slice 137 re-verified Slice
  136 read-only and passed it with zero findings — sync tree-identical;
  counts re-measured 3,003 real (2,222 + 736 + 45), `coincide-mcp-server`
  19; all 17 remaining "3,002" hits in `docs/` verified historical; the
  Slice 134 test function closes at `tests/mcp_server.rs:598` (Slice 136
  right, Slice 134's `:599` wrong); program diff at current HEAD 224
  files +54,296/−3,595. Spot-checked by Slice 138; every fact above
  confirmed as written.
  **Slice 139 re-verification:** Slice 139 re-verified Slice 138
  read-only and passed it with minors — the one MINOR is a docs
  precision gap: the Slice 138 section's sentence claiming the only
  other `unknownTool` throws inside `execute()` are the pre-switch
  guard (`:3843`) and the `use_mcp` recursion (`:4414`) omits the
  third, the `tool_capability_lookup` arm (`:6946–6949`, throw at
  `:6949`); fixed in Slice 144. Every other Slice 138 fact
  spot-checked as written: 332/332 re-derived with a fresh parser
  (207 arms, 199 single + 8 multi); depth G5 32+33, G6 37+1,
  computer-use 20 generic forward; Slice 139's own diff is docs-only
  (2 files +129/−5); program diff 224 files +54,420/−3,595.
  **Slice 145 re-verification (no commit):** Slice 145 re-verified Slice
  144 read-only and passed it **NOT CLEAN** — two MAJOR findings and
  two MINORs, all fixed in Slice 146. Fix 1 confirmed as written: the
  5 GiB cap (`MAX_FILE_COPY_BYTES`, `workspace_tools.rs:14`;
  length read once and refused above the cap, `:331–336`), the
  free-space reserve (`:341–347`, source refused when it would eat
  into a 5 GiB reserve), the `libc::statvfs` probe using `f_frsize`
  (`:363–378`, `available_bytes`), the partial-destination cleanup
  on mid-copy error (`:348–354`), and `libc` 0.2 already a
  `coincide-core` dependency (`Cargo.toml:27`, no new dependency).
  Fix 2 confirmed for final symlinks only: non-paged routes through
  `read_workspace_text` (`:585`, refusal at `:220–224`) and paged
  refuses before canonicalizing (`workspace.rs:733–743`), with the
  returned JSON shape identical on both branches. Fix 3 confirmed:
  the cwd pin (`tools.rs:7819–7831`, non-empty guard at `:7824`),
  `--cwd` required and absolute (`main.rs:48`), and the `use_mcp`
  recursion re-entering `call()` (`tools.rs:17405`) through
  `with_session_defaults` (`:16894`). The 5 tests confirmed present;
  docs totals 33 defects / 33 tests confirmed; Rust total 3,008
  re-measured (2,227 real short-form + 736 fully-qualified + 45
  `gpui_kit`). Finding 1 (MAJOR): the literal `.git/config` read
  was never closed — `workspace::read_file` had no `.git` guard and
  the paged branch never called `validate_relative_workspace_path`,
  so the file was retrievable with no symlink at all, contradicting
  Slice 144's "Fixed on both paths" claim; fixed in Slice 146 by
  the `.git` refusal in `relative_path`. Finding 2 (MAJOR): an
  intermediate-directory symlink (`link -> .git`, read
  `link/config`) bypassed both read paths, since both guards checked
  only the final component; fixed in Slice 146 by the shared
  intermediate-symlink walk. Finding 3 (MINOR): the Slice 144
  section's "four test sites" sentence miscounts — five test sites
  (`tools.rs:21334, 21351, 21368, 21386, 21403`); fixed in Slice
  146. Finding 4 (MINOR): `docs/MAC-GATE.md` still said 3,003 Rust
  tests after Slice 144's 5 new tests (true total 3,008); refreshed
  in Slice 146 to 3,012 after its own 4 new tests.
  **Slice 147 re-verification (no commit):** Slice 147 re-verified
  Slice 146 read-only and passed it with zero findings — Fix 1
  confirmed as written: the `.git`-component guard in
  `relative_path` (`workspace.rs:290–294`), with only two callers
  (`diff`, `:327`, which passes the path as a git pathspec, and
  `read_file`, `:740`); Fix 2 confirmed as written: the shared
  read-only helper `refuse_intermediate_symlinks`
  (`workspace_tools.rs:218–231`), called from `read_workspace_text`
  (`:235`) and `workspace::read_file` (`workspace.rs:742`), mirroring
  the write path's intermediate check
  (`workspace_parent_for_write`, refusal ensure at `:193–197`) but
  read-only (a missing intermediate propagates `NotFound` instead of
  creating a directory); the 4 tests confirmed present; counts
  re-measured at 3,012 Rust (2,231 real short-form + 736
  fully-qualified + 45 `gpui_kit`; core 1,832, `coincide-mcp-server`
  20) and 128 Swift `@Test`; program diff 224 files +55,019/−3,596.
  **Slice 149 re-verification (no commit):** Slice 149 re-verified Slice
  148 read-only and passed it **NOT CLEAN** — one MAJOR finding and two
  MINORs, all fixed in Slice 150. Spot-checked as written: 14 of the 15
  tests are arm-shape YES (only `read_file` is wrong — see Finding 1);
  the coverage deltas are exact (direct +15, arm-reached +16 under the
  strict rule, validation-only −1, arm-shared-only 0, truly uncovered
  −15; the 42-set equals the docs' listed 42); the totals chain 30/28 →
  33/33 → 35/37 → 35/52 verified; the Slice 146 backfill verified
  (remote `81cf2e4c` in the Slice 146 header); Swift `@Test` 143 (124 in
  `AgentsTests` + 19 bare `@Test func` in `CoincideRemoteTests`), Rust
  3,012 (2,231 real short-form + 736 fully-qualified + 45 `gpui_kit`);
  program diff 224 files +55,570/−3,596 against the program base
  `04b235e3`, measured at Slice 148's HEAD `7c4d94cf`. Finding 1 (MAJOR): `readFileReadsRealContent`
  (`ToolsetTests.swift:2980`) expected `"alpha\nbeta"` for a file
  written as `"alpha\nbeta\n"`, but the Swift `execute()` path returns
  the file bytes verbatim — the line-joining `workspace::read_file`
  serves only the engine `files.read` API and is never on this path;
  fixed in Slice 150 by correcting the expectation to `"alpha\nbeta\n"`.
  Finding 2 (MINOR): the Slice 148 section's "terminal arm 3 → 6" does
  not reproduce under the strict rule — the Slice 143 method counted
  `svg_to_png` and `reverse_analyze` as arm-reached from their
  `#expect(throws:)` call sites; restated in Slice 150 as action-
  `terminal.*` arm 1 → 4. Finding 3 (MINOR): the arm-reached /
  validation-only absolute figures (174/72 pre, 190/71 post) are not
  independently reproducible — the strict rule gives 168/78 pre and
  184/77 post; the 6-tool gap is the `#expect(throws:)`-only tools
  `fetch_documentation`, `github_repo`, `reverse_analyze`,
  `search_web`, `svg_to_png`, `use_app` (Slice 149's report names the
  six `computer_use.*` tools instead; that identification is wrong —
  only `use_app` of that set is in the gap); restated in Slice 150
  with the classification rule documented.
  **Slice 151 re-verification (no commit):** Slice 151 re-verified Slice
  150 read-only and passed it **PASS WITH MINORs** — one MINOR finding,
  fixed in Slice 152. Finding 1 confirmed: the `read_file` expectation is
  now `"alpha\nbeta\n"` (`ToolsetTests.swift:2990`), the fixture unchanged,
  and the chain re-traced end-to-end (arm
  `SystemToolRegistry.swift:3846-3850` → FFI bridge
  `AgentsFFIBridge.swift:1191-1200` → `workspace_ops.rs:444-445` →
  `read_workspace_text` (`workspace_tools.rs:233-254`) verbatim → decoder
  prefers `"content"` (`DesktopModels.swift:1484-1487`); the line-joining
  `workspace::read_file` (`workspace.rs:738`) serves engine `files.read`
  (`api.rs:810`) only; no live "read joins lines" claim remains in this
  record). Finding 2 confirmed: action-`terminal.*` group 62 tools;
  strict 1 → 4, loose 3 → 6; the sentence is coherent. Finding 3
  confirmed: the gap set is exactly `fetch_documentation`,
  `github_repo`, `reverse_analyze`, `search_web`, `svg_to_png`,
  `use_app`; restated figures 168 → 184 / 50.6% → 55.4% /
  validation-only 78 → 77; the 42-set is set-equal to the docs' list;
  the classification rule as documented reproduces the numbers. 5
  spot-checked tests confirmed (`git_push`, `git_branch_list`,
  `write_file`, `search_files`, `take_screenshot`); the Slice 148
  backfill API-verified; Swift `@Test` 143 (124 + 19), Rust 3,012
  (2,231 + 736 + 45); program diff 224 files +55,778/−3,596. MINOR (F1):
  the Slice 150 Verification paragraph's program-diff figure +55,570 is
  stale at HEAD `b6caaffb` — that was the value at Slice 148's HEAD
  `7c4d94cf`; re-measured against the program base `04b235e3` it is
  +55,778; corrected in Slice 152 (remote 12e85d5e), which also qualified the Slice 149
  note's +55,570 with its rev.
  **Slice 153 re-verification (no commit):** Slice 153 re-verified Slice
  152 read-only and passed it **PASS WITH MINORs** — two MINOR findings,
  both fixed in Slice 154. Spot-checked as written: sync tree-identical
  (remote `12e85d5e` / tree `bbcfaac6`); registry 332/332/332 with 0
  mismatches (1,087 params each side, 63 distinct actions); catalog
  279/300 (278 exact + 1 alias + 1 duplicate + 20 NONE); strict coverage
  261 direct / 184 arm-reached (55.4%) / 77 validation-only / 29 shared /
  42 uncovered (loose 190/71); Swift `@Test` 143 (124 in `AgentsTests` +
  19 bare `@Test func` in `CoincideRemoteTests`), Rust 3,012 (2,231 real
  short-form + 736 fully-qualified + 45 `gpui_kit`); Swift files 148, Rust
  files 707 excluding `vendor/`, docs 28; program diff 224 files
  +55,809/−3,596 against the program base `04b235e3`, measured at HEAD
  `ba9ee5b7`; commits in range 99; totals recounted at 36 defects / 52
  tests; secrets sweep clean (69 hits reviewed); comments sweep 6 lines
  all explained; open items all still true/documented except F2 (fixed
  here); Slices 144/146/148/150 fixes all hold at HEAD. The Slice 152
  backfill is API-verified (remote
  `12e85d5e64f945424780dd6cf62338aa82a60df0`, tree
  `bbcfaac60e6a9547e382f836d799292565db9c75`, parent
  `e9a46e9cae70af8bad914d307673d5332332ed2c`). MINOR (F1):
  `docs/MAC-GATE.md:188` still said `coincide-mcp-server` (19 tests),
  but the true count is 20 (4 in `tools.rs:21310,21332,21366,21384` + 16
  in `tests/mcp_server.rs:120–796`); the per-crate table at `:172`
  already said 20 and the 3,012 total depends on 20; corrected in Slice
  154. MINOR (F2): the `.git` guards' exact-byte case-insensitivity
  edge (Slice 147 INFO-3) was missing from the docs; added to
  [Documented, not fixed](#documented-not-fixed) in Slice 154.
- **Slices with no commit (87, 89, 90).** There is nothing to re-read in
  git for these; re-run the sweep (Rust: per-crate module-tree + def/use
  indexing; Swift: declaration/candidate indexing over the named targets)
  and compare against the 0 CONFIRMED-MISSING result recorded here.
