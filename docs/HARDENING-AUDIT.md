# Hardening Audit — Slices 71–109

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
25 regression tests**. The remaining
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
332 tools per side.

**Verification:** sweep re-run after the edit (129/129 params, 0
lacking pinning language, 0 cross-side mismatches); zero occurrences
of the old wording remain in either registry or the test. Statically
verified only — no Swift compile here, as for every slice in this
record. Sweep baseline: local `main` `2a0261d8`, remote `main`
`27dabf958a`, same tree `667422d1`. The local pre-push commit is
`02251181` (same tree as remote `23a73f2d`).
Slice 110 re-verified this slice; see [How to re-verify](#how-to-re-verify).

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
  (re-verified at HEAD: exactly 332; the one further `ToolDef {` match is the
  `pub struct ToolDef {` declaration at `tools.rs:14`, not a registry entry). Cross-check the same
  332 names, actions, and order against
  `Agents/Core/SystemTools/SystemToolRegistry.swift`; the canonical
  description is `docs/SYSTEM-TOOLSET.md:57-61`.
- **MAC-GATE count method.** From `Rust Backend`, excluding `vendor/`:
  count short-form `#[test]` attributes, fully-qualified
  `#[::core::prelude::v1::test]` attributes, and `#[gpui_kit::test]`
  attributes, and sum them. At HEAD the
  expected total is **3,000** (2,219 + 736 + 45). Method and per-crate table:
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
- **Slices with no commit (87, 89, 90).** There is nothing to re-read in
  git for these; re-run the sweep (Rust: per-crate module-tree + def/use
  indexing; Swift: declaration/candidate indexing over the named targets)
  and compare against the 0 CONFIRMED-MISSING result recorded here.
