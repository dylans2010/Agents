# Assistants

Assistants are reusable, named specialists: a system prompt, a category, an
optional provider/model, a permission profile, and an explicit list of the
system tools the assistant may use. A thread launched from an assistant gets
the assistant's prompt, its tool list, and (since F6b) its provider/model;
a worker spawned by an assistant gets the same. Everything in this document
is grounded in the code at worktree base `b81e42ea` (slices F1a–F6b, C0–C6,
C-fix, C-fix2). Nothing here was compiled, executed, or tested in the
environment where this document was written — there is no Swift toolchain
and no cargo there — so every count below was measured by reading the
source, and the Mac gate (see `docs/MAC-GATE.md`) is Dylan's.

Slice SHAs cited here were verified against the local history:
F1a `791e2226`, F1b `edc35dc2`, F2 `ed517955`, F3 `66603357`,
F3b `e92c5b20`, F4 `1765acb2`, F5 `ac79fb01`, C0 `62ff0304`,
C1 `a5d0bf80`, C2 `fbbaa497`, C3 `67d7d590`, C4 `51a0d044`,
C5 `97751186`, C6 `88e212fb`, C-fix `63054c30`, C-fix2 `8f5a22d3`,
F6b `b81e42ea` (the base commit itself). The program's remote-main SHA
`6024d742` is not present in this worktree's history and was not verified
here; the tree it names is stated to equal this base's tree.

## The model

### `AssistantDefinition` (Swift)

`Agents/Core/Assistants/AssistantDefinition.swift` is the app-side model.
Fields, in order:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `String` | Stable ID: `builtin.<category>.<slug>` or `custom.<uuid>` (see IDs below) |
| `name` | `String` | 1–1024 Unicode scalars, no control characters |
| `description` | `String` | At most 4096 scalars, no NUL |
| `category` | `AssistantCategory` | One of six categories (below) |
| `icon` | `String` | SF Symbol name, at most 128 scalars, no control characters |
| `systemPrompt` | `String` | Non-empty, at most 1 MiB UTF-8, no NUL |
| `intendedTasks` | `[String]` | At most 32, each at most 512 scalars, no NUL |
| `expectedOutputFormat` | `String` | At most 4096 scalars, no NUL |
| `allowedTools` | `[String]?` | `nil` means unrestricted; a list must be unique, non-empty names of at most 256 scalars, and every name must exist in the 333-tool registry |
| `modelConfig` | `AssistantModelConfig` | App default unless the assistant pins a provider and/or model |
| `permissionProfile` | `AssistantPermissionProfile` | Default `.readOnly`; **stored, not enforced** (see Enforcement) |
| `inputRequirements` | `[String]?` | At most 16, each at most 512 scalars, no NUL |
| `version` | `Int` | At least 1; built-ins are all version 1 at this base |
| `isBuiltIn` / `customized` | `Bool` | `customized` is set only when an override record actually differs from its preset |

`validationIssues()` enforces all of the above plus stable-ID shape: a
built-in ID must be exactly `builtin.<category-raw-value>.<valid-slug>`,
a custom ID must be `custom.` plus a parseable UUID. Slugs are lowercase
kebab: `[a-z0-9-]`, no leading/trailing `-`, no `--`
(`AssistantDefinition.isValidSlug`).

### The stored record (Rust)

`Rust Backend/crates/coincide-core/src/assistants.rs` is the same shape
in serde form (`Assistant`, camelCase JSON): `id` (a UUID string, not the
stable ID), `name`, `description`, `icon`, `category`, `systemPrompt`
(called "instructions" in one error string), `intendedTasks`,
`expectedOutputFormat`, `allowedTools`, `provider`, `model`,
`permissionProfile` (default `"read-only"`), `inputRequirements`,
`version` (default 1), `source` (`"custom"` or `"override"` only),
`isFavorite`, `lastUsedAt`, `createdAt`, `updatedAt`, plus an `extra`
map that preserves unknown fields a newer client adds instead of
dropping them. `Assistant::validate()` mirrors the Swift limits
character-for-character, and adds two rules the Swift side does not
need: the provider name must be a known provider
(`Provider::from_name`), and an assistant with a provider of
`opencode` or `lithos` may not carry a non-empty `allowedTools` list
("Allowed tools are not supported for provider …: OpenCode and Lithos
cannot use System Tools").

The Swift side and the Rust side are two views of one record. The
bridge type is `RemoteAssistant` in
`CoincideRemoteKit/Sources/CoincideRemoteKit/RemoteModels.swift`, which
decodes leniently: unknown enum values become `.unknown`, missing
fields fall back to the Rust serde defaults, and a record that does not
decode at all is skipped by `RemoteAssistants` instead of losing the
whole list.

### Categories

Six, in `AssistantCategory`
(`Agents/Core/Assistants/AssistantCategory.swift`):

| Raw value | Display name |
| --- | --- |
| `code-maintenance` | Code Maintenance |
| `code-review-security` | Code Review & Security |
| `building-fixing` | Building & Fixing |
| `repository-intelligence` | Repository Intelligence |
| `git-workflow-automation` | Git & Workflow Automation |
| `specialized-productivity` | Specialized Engineering & Productivity |

### Model config

`AssistantModelConfig`
(`Agents/Core/Assistants/AssistantModelConfig.swift`) has five cases:

- `.appDefault` — use whatever the app/thread already has; sends no
  selection override.
- `.specific(provider:model)` — pins both.
- `.providerOnly(provider)` — pins the provider, model becomes
  `"default"` at the Rust end.
- `.modelOnly(model)` — pins the model, keeps the current provider.
- `.currentAppModel` — resolved at launch against the selected thread's
  provider/model (`resolvingCurrent`), then behaves like `.specific`.

`selectionOverride` maps the first four cases to a
`RemoteSelectionOverride` (`{provider, modelID}`); `.appDefault` and
`.currentAppModel` (before resolution) map to `nil`. Every built-in
preset at this base uses `.appDefault`.

### Permission profiles

`AssistantPermissionProfile`
(`Agents/Core/Assistants/AssistantPermissionProfile.swift`) has four
raw values: `read-only`, `workspace-modify`, `terminal`,
`approval-required`. The profile is a **stored declaration of intent,
not an enforcement mechanism**. Nothing in the engine reads it: the
only thing enforced at runtime is `allowedTools` (see Enforcement).
Profile enforcement (program label E1) is not built; see "Not built
yet". The profile still matters because the catalog tests assert it
matches the preset's actual tool list (see the read-only guarantee).

## Stable IDs and persistence IDs

Two ID schemes coexist, and confusing them is the easiest way to break
an assistant:

- **Stable ID** — the human-meaningful identity, used by the Swift
  catalog and the UI: `builtin.<category>.<slug>` for built-ins
  (e.g. `builtin.code-maintenance.dead-code-remover`) and
  `custom.<uuid>` for customs. Built with
  `AssistantDefinition.builtInID(category:slug:)` /
  `customID(_:)`, which preconditions on a valid slug.
- **Persistence ID** — the UUID key under which the record is stored
  in `assistants.json`. For a custom assistant it is the UUID embedded
  in its stable ID. For a built-in it is a **deterministic UUIDv5**
  derived from the stable ID:
  `deterministicID(namespace:persistenceNamespace, name: stableID)`
  — SHA-1 over the namespace bytes plus the stable-ID UTF-8 bytes,
  with the version nibble forced to `5` and the variant bits to
  `10`, i.e. a UUIDv5 in the RFC 4122 sense (implemented with
  `Insecure.SHA1`, which is fine here: it is an identifier hash, not
  a security hash). The namespace UUID is
  `a0c85a04-06f7-468f-8f4d-187c87ee3fbc`
  (`AssistantDefinition.persistenceNamespace`).

Consequences, all verified in `AssistantCatalogTests.swift`:

- The same built-in always maps to the same persistence UUID, so a
  user's override of a built-in survives app updates and preset edits.
- `definition(forPersistenceID:)` finds a built-in by its derived
  UUID; `definition(forStableID:)` finds it by the readable ID.
- An override record whose persistence ID matches no built-in is
  reported by `unmatchedOverrideIDs` rather than silently applied.
- If a preset's version rises above the version the override was
  customized against, `versionGap(for:)` reports `(preset:customizedAgainst:)`;
  the customization is kept, not overwritten.

### `AssistantCatalog` merge semantics

`AssistantCatalog` (`Agents/Core/Assistants/AssistantCatalog.swift`)
holds `builtIns` (the 60 presets, in code) plus `stored`
(`RemoteAssistant` records from `assistants.json`):

- `builtInDefinitions` — each preset, with its matching `source ==
  .override` record applied field-by-field
  (`applyingOverride`), only for fields that differ; `customized`
  is set exactly when at least one field differs. An override
  identical to its preset is not a customization.
- `customDefinitions` — `source == .custom` records, sorted by
  `(name, id)`; a custom record with an unknown category is skipped.
- `allDefinitions` — built-ins (with overrides) followed by customs.
- Duplicate built-in IDs: the first wins, the rest are reported by
  `duplicateBuiltinIDs`.
- `restoreDefaults(builtinID:)` deletes the override record and
  returns the pristine preset; unknown IDs return `nil` and change
  nothing.
- `invalidDefinitions()` runs `validationIssues()` over everything
  and returns the definitions that fail, with their issues.

The app holds the catalog in `AppModel` (`assistants: [RemoteAssistant]`,
`assistantsLoaded`, `assistantCatalog` computed from `stored:`), loaded
by `refreshAssistants()` through `assistants.list`; `assistantsLoaded`
stays `false` until a refresh attempt resolves, so the UI can tell
"not loaded yet" from "loaded and empty".

## The 60-preset catalog

`Agents/Core/Assistants/Catalog/BuiltInPresets.swift` concatenates six
groups of ten. Ten per category, sixty total, all version 1, all
`.appDefault` model config, all with non-empty descriptions, intended
tasks, expected output formats, and input requirements. Per-category
counts of permission profiles:

| Category | Presets | read-only | workspace-modify | approval-required | terminal |
| --- | --- | --- | --- | --- | --- |
| Code Maintenance | 10 | 4 | 4 | 2 | 0 |
| Code Review & Security | 10 | 10 | 0 | 0 | 0 |
| Building & Fixing | 10 | 1 | 7 | 2 | 0 |
| Repository Intelligence | 10 | 10 | 0 | 0 | 0 |
| Git & Workflow Automation | 10 | 7 | 0 | 3 | 0 |
| Specialized Engineering & Productivity | 10 | 8 | 1 | 1 | 0 |
| **Total** | **60** | **40** | **12** | **8** | **0** |

No preset uses the `terminal` profile at this base.

### Preset table

Stable ID is `builtin.<category>.<slug>`; profile is the stored
permission profile (not enforced — see Enforcement).

**Code Maintenance** (`code-maintenance`)

| Slug | Name | Profile | Tools |
| --- | --- | --- | --- |
| `dead-code-remover` | Dead Code Remover | approval-required | 17 |
| `code-cleanup-assistant` | Code Cleanup Assistant | workspace-modify | 14 |
| `refactoring-specialist` | Refactoring Specialist | approval-required | 13 |
| `duplicate-code-finder` | Duplicate Code Finder | read-only | 9 |
| `dependency-auditor` | Dependency Auditor | read-only | 11 |
| `performance-optimizer` | Performance Optimizer | workspace-modify | 13 |
| `memory-leak-investigator` | Memory Leak Investigator | read-only | 8 |
| `architecture-analyst` | Architecture Analyst | read-only | 12 |
| `documentation-generator` | Documentation Generator | workspace-modify | 15 |
| `naming-readability-specialist` | Naming & Readability Specialist | workspace-modify | 12 |

**Code Review & Security** (`code-review-security`) — all read-only

| Slug | Name | Tools |
| --- | --- | --- |
| `pr-reviewer` | PR Reviewer | 14 |
| `security-auditor` | Security Auditor | 15 |
| `bug-risk-reviewer` | Bug Risk Reviewer | 12 |
| `api-compatibility-reviewer` | API Compatibility Reviewer | 10 |
| `swift-code-reviewer` | Swift Code Reviewer | 12 |
| `typescript-reviewer` | TypeScript Reviewer | 12 |
| `accessibility-reviewer` | Accessibility Reviewer | 8 |
| `error-handling-reviewer` | Error Handling Reviewer | 9 |
| `database-schema-reviewer` | Database Schema Reviewer | 9 |
| `release-readiness-reviewer` | Release Readiness Reviewer | 11 |

**Building & Fixing** (`building-fixing`)

| Slug | Name | Profile | Tools |
| --- | --- | --- | --- |
| `feature-builder` | Feature Builder | approval-required | 12 |
| `bug-fixer` | Bug Fixer | workspace-modify | 11 |
| `crash-investigator` | Crash Investigator | read-only | 10 |
| `ui-modernizer` | UI Modernizer | workspace-modify | 11 |
| `swiftui-specialist` | SwiftUI Specialist | workspace-modify | 10 |
| `appkit-specialist` | AppKit Specialist | workspace-modify | 10 |
| `api-integration-builder` | API Integration Builder | workspace-modify | 11 |
| `test-generator` | Test Generator | workspace-modify | 9 |
| `test-failure-fixer` | Test Failure Fixer | workspace-modify | 9 |
| `migration-assistant` | Migration Assistant | approval-required | 13 |

**Repository Intelligence** (`repository-intelligence`) — all read-only

| Slug | Name | Tools |
| --- | --- | --- |
| `codebase-explainer` | Codebase Explainer | 14 |
| `repository-qa` | Repository Q&A | 14 |
| `commit-summarizer` | Commit Summarizer | 9 |
| `change-impact-analyst` | Change Impact Analyst | 13 |
| `dependency-map-analyst` | Dependency Map Analyst | 12 |
| `technical-debt-reporter` | Technical Debt Reporter | 15 |
| `project-documentation-analyst` | Project Documentation Analyst | 10 |
| `api-documentation-assistant` | API Documentation Assistant | 10 |
| `onboarding-guide-generator` | Onboarding Guide Generator | 11 |
| `changelog-generator` | Changelog Generator | 9 |

**Git & Workflow Automation** (`git-workflow-automation`)

| Slug | Name | Profile | Tools |
| --- | --- | --- | --- |
| `commit-message-writer` | Commit Message Writer | read-only | 5 |
| `branch-cleanup-assistant` | Branch Cleanup Assistant | approval-required | 5 |
| `pr-description-writer` | PR Description Writer | read-only | 7 |
| `pr-review-responder` | PR Review Responder | approval-required | 9 |
| `merge-conflict-resolver` | Merge Conflict Resolver | approval-required | 9 |
| `git-history-analyst` | Git History Analyst | read-only | 8 |
| `release-notes-writer` | Release Notes Writer | read-only | 7 |
| `issue-triage-assistant` | Issue Triage Assistant | read-only | 6 |
| `ci-failure-investigator` | CI Failure Investigator | read-only | 10 |
| `repository-health-monitor` | Repository Health Monitor | read-only | 11 |

**Specialized Engineering & Productivity** (`specialized-productivity`)

| Slug | Name | Profile | Tools |
| --- | --- | --- | --- |
| `ui-consistency-auditor` | UI Consistency Auditor | read-only | 12 |
| `localization-assistant` | Localization Assistant | read-only | 8 |
| `accessibility-fixer` | Accessibility Fixer | workspace-modify | 12 |
| `security-patch-assistant` | Security Patch Assistant | approval-required | 13 |
| `build-configuration-auditor` | Build Configuration Auditor | read-only | 16 |
| `database-migration-planner` | Database Migration Planner | read-only | 11 |
| `product-requirements-analyst` | Product Requirements Analyst | read-only | 11 |
| `implementation-planner` | Implementation Planner | read-only | 13 |
| `technical-researcher` | Technical Researcher | read-only | 11 |
| `project-progress-reporter` | Project Progress Reporter | read-only | 13 |

Across the 60 presets, 154 distinct registry tool names are used.
Every preset's `allowedTools` is non-empty and every name exists in
the 333-tool registry — asserted per category by
`allowedToolsExistInRegistry`-style tests that call
`SystemToolRegistry.unknownToolNames(in:)` and expect an empty result.

### Prompt-quality bar

Every preset's system prompt is a detailed, specialized prompt, not a
one-liner. Measured at this base (characters, including the Swift
multi-line literal content): shortest 1,549
(`bug-risk-reviewer`), longest 2,920 (`accessibility-fixer`), mean
~2,038. The bar is asserted in code, per category, by two tests in
each `*PresetsTests.swift` file:

- **Length**: `systemPrompt.count >= 600` for every preset, plus
  non-empty description, expected output format, and intended tasks.
- **Domain keywords**: each preset's prompt must contain at least two
  keywords of its own specialty (the keyword table is hand-written
  per category in the test file, e.g. `dead-code-remover` must contain
  its dead-code terms, `security-patch-assistant` must contain OWASP /
  Keychain / certificate pinning / SQL injection terms). The assertion
  is a substring check on the prompt text.

### The read-only guarantee — and exactly how it is checked

40 of the 60 presets declare `.readOnly`. The guarantee "a read-only
preset grants no mutating tool" is **not** enforced by a single
registry-wide sweep: there is no classification of the 333 registry
tools as mutating vs read-only anywhere in the code, and no test
iterates all 333 tools for this purpose. What exists, and what the
"0 violations" claim rests on, is per-category disjointness tests in
the six `*PresetsTests.swift` files, each against its own
hand-written set of mutating tool names:

- `CodeMaintenancePresetsTests` — 24-name set
  (`write_file`, `edit_file`, `delete_file`, `run_build`,
  `git_commit`, `dead_code_eliminator`, `manage_memory`,
  `swift_package_manager`, …); asserts every read-only preset's
  `allowedTools` is disjoint from it.
- `CodeReviewSecurityPresetsTests` — its own `mutatingToolNames` set
  (84 names);
  asserts every preset (all ten are read-only) lists no mutating tool.
- `RepositoryIntelligencePresetsTests` — its own
  `writeEditTerminalTools` set (62 names); asserts no preset exposes
  a write, edit, or terminal tool.
- `SpecializedProductivityPresetsTests` — the largest set (93
  names, including computer-use actions `click`/`type_text`/…,
  `run_command`, `git_*` mutations, `mem_*` writes,
  `use_workers`/`start_subagent`); asserts the 8 read-only presets
  are disjoint from it.
- `BuildingFixingPresetsTests` — checks only the one read-only
  preset (`crash-investigator`) against a 4-name write set; the
  other nine are not read-only.
- `GitWorkflowAutomationPresetsTests` — asserts the profile of each
  preset matches its mutating surface by explicit per-preset
  expectation, rather than a disjointness sweep.

The sets differ between files: they were written per category, and a
tool classified as mutating in one file may be absent from another
file's list. That is the honest limit of the guarantee. What the
history shows is that the tests do catch real violations: C-fix
(`63054c30`) removed nine mutating tools from read-only presets
(`docs_generate`, `readme_generate`, `markdown_toc_generate` from
the documentation presets; `strings_localization`, `localize_app`,
`string_catalog_migrator` from Localization Assistant;
`execution_plan` from Implementation Planner; `manage_memory` from
Memory Leak Investigator; `swift_package_manager` from Dependency
Auditor), and C-fix2 (`8f5a22d3`, plus a duplicate commit `bc4998b7`
with the same message) removed further ones. At this base the
per-category tests assert 0 violations — but that assertion was
measured by reading the tests, not by running them; see Honest
limits.

## Persistence and recovery

### `assistants.json` and the CAS baseline

F1a (`791e2226`) stores assistants as one document,
`assistants.json`, in the engine's `documents` table (the same
`documents`/`original_files` mechanism as bots and other documents),
with a compare-and-swap baseline:

- `assistants.list` returns `{assistants, baseline, origin, version: 1}`.
  `origin` is `"local"` (a locally saved document),
  `"imported"` (loaded from a captured `original_files` entry), or
  `"empty"` (no document yet; the response is the empty document).
- The baseline is the lowercase hex SHA-256 of the canonical,
  validated serialization of the document
  (`AssistantsDocument::validate()` re-serializes and hashes).
- `assistants.save` and `assistants.delete` both require the caller
  to pass the baseline it listed from; a mismatch is rejected with
  "Assistant document changed; reload before saving". The write
  itself goes through
  `Store::save_assistants_document_if_unchanged`, which re-checks
  the stored document inside an immediate transaction, so two
  writers cannot silently overwrite each other.
- On save, `createdAt` and `lastUsedAt` are preserved from the
  stored record; `updatedAt` is set to now. A new record gets
  `createdAt = updatedAt = now` (unless the client already set a
  positive `createdAt`).
- The document is capped at 16,000,000 bytes (~15.3 MiB) and 10,000 records
  (`organization.rs`: `DOCUMENT_LIMIT`, `RECORD_LIMIT`); the
  document must be version 1 and every record must validate, with
  duplicate IDs rejected.

The engine surface is three methods, dispatched in
`assistants_api.rs` (`assistants.list`, `assistants.save`,
`assistants.delete`); unknown parameters are rejected per method,
and `find_assistant(store, id)` is the shared lookup used by worker
spawn. The Swift side reaches it through `AgentsFFIBridge`
(`listAssistants`, `saveAssistant`, `deleteAssistant`) and the
`RemoteProtocol` request/response shapes (`.assistants`,
`.saveAssistant`, `.deleteAssistant`); `AppModel.saveAssistant`
pre-validates `allowedTools` against the registry client-side and
refuses unknown tools with an explicit error before sending.

### Definitions, customizations, favorites, run history

- **Definitions** live in the presets (code) for built-ins and in
  `assistants.json` for customs and overrides; the catalog merge in
  "Stable IDs" above is the recovery path: a deleted or corrupted
  override simply stops applying, and the pristine preset returns.
- **Customizations** are override records (`source == "override"`,
  keyed by the built-in's persistence UUID). They survive preset
  updates; a version gap is reported, not auto-merged.
- **Favorites** (`isFavorite`) and **last-used** (`lastUsedAt`) are
  stored fields on the record and round-trip through save — but
  nothing at this base writes them: no launch path sets
  `lastUsedAt`, and no UI or API toggles `isFavorite`. They are
  schema for a future surface, not a working feature. (Verified by
  grep: the only `last_used_at` writes in the engine are the
  preserve-on-save in `assistants_api.rs`; the only `is_favorite`
  mention is the field declaration and the test seed.)
- **Run history** is not stored on the assistant record. What exists
  is per-worker: a worker record carries the `assistantId` it was
  spawned from (`worker_store.rs` `SpawnRequest.assistant_id`,
  stored on the record), and `workers.list` accepts an
  `assistantId` filter (`workers_api.rs`), with a Swift
  `listWorkers(assistantId:)` to match
  (`AgentsFFIBridge.swift`). Listing workers by assistant is the
  only assistant-scoped history query at this base.

## Enforcement as built

### What is enforced, and where

The enforcement unit is the **thread**, not the assistant. The
assistant's `allowedTools` is copied onto the thread document at
creation; from then on the MCP server enforces the thread's stored
list and never consults the assistant record again. Editing an
assistant's `allowedTools` does not change threads already created
from it.

1. **Thread field** (F2, `ed517955`). `threads.create` /
   `prepare_ordinary_thread` accept `systemPrompt`, `toolset`,
   `allowedTools`, `assistantId`. Validation
   (`agent.rs`: `validate_system_prompt_and_toolset`,
   `validate_allowed_tools`): toolset must be `"system"` or
   `"provider"`; a system prompt cannot combine with the provider
   toolset; a non-empty `allowedTools` cannot combine with the
   provider toolset; at most 333 tools, names non-empty, at most
   256 characters, no control characters, no duplicates; a system
   prompt is at most 64 KiB and contains no NUL. If `toolset` is
   `"system"` or `allowedTools` is present, the thread's provider
   must support System Tools (`ensure_system_toolset_supported` —
   rejects `opencode` and `lithos`). `assistantId` must be a UUID
   or the request is rejected. `threads.patch` accepts the same
   fields with the same validation, and `update_stored_prompt`
   (F4, `1765acb2`) is the explicit path for replacing a thread's
   stored prompt and tools: it refuses provider-toolset threads,
   re-validates, and treats an empty `allowedTools` list as
   not-supplied rather than as "allow nothing" (F4-fix,
   `30c0a506`).
2. **MCP `tools/list` filtering** (F3, `66603357`).
   `tools.rs`: `list_json` reads the session thread's stored
   `allowedTools` over the control socket (`threads.read`, via
   `assets.rs`: `stored_allowed_tools`) on every call, with no
   caching, and `list_json_filtered` returns only the allowed
   definitions. A null or absent list means all 333. Unknown names
   in the list are ignored, never surfaced.
3. **MCP `tools/call` rejection** (F3). `tools::call` reads the
   same stored list and `ensure_allowed` rejects a disallowed name
   with `CallError::UnknownTool` before any dispatch. At the
   protocol level (`protocol.rs`) that becomes JSON-RPC `-32602`
   `Unknown tool "<name>"` — deliberately identical to the error
   for a name that does not exist, so a disallowed tool and an
   unknown tool are indistinguishable to the caller. A real
   execution failure is different: it returns `isError: true`
   content, not a JSON-RPC error. A thread read that fails is a
   hard failure (list returns `-32602`, call reports the failure),
   never a silent lift of the restriction.
4. **`use_app` inner-action gate** (F3b, `e92c5b20`). `use_app`
   dispatches action names onto inner computer-use tools, so the
   gate checks the *mapped inner tool*, not just `use_app` itself:
   `click` for the `click` action, `get_desktop_state` for
   `take_screenshot`, `launch_app` for `launch`, and so on
   (`g6_use_app_inner_tool` in `tools.rs`). Allowing `use_app`
   while denying `click` does not let the model click through
   `use_app`. The nine actions with no engine tool (`activate`,
   `close_application`, `select_window`, `get_focused_element`,
   `select_all`, `copy`, `paste`, `wait_for_element`,
   `wait_for_window`) keep their honest "not implemented" error,
   and an unknown action keeps its "not a known action" error —
   neither becomes an `UnknownTool` rejection. One asymmetry to
   know: the Rust server rejects a disallowed inner tool as
   `UnknownTool` (`-32602`), while the Swift `execute()` mirror
   (`SystemToolRegistry.runG6UseApp`) rejects it as
   `SystemToolError.toolNotActive` ("…is not active under the …
   toolset"). Same gate, different error shape.
5. **Swift `execute()` mirror** (F3). `SystemToolRegistry.execute`
   enforces the same list through
   `definition(named:for:allowedTools:)`, throwing
   `SystemToolError.unknownTool` for a disallowed name. It has no
   production caller by design (its only callers are tests); it is
   the schema/test mirror, not an enforcement point. Production
   execution is the MCP server's `tools/call`.
6. **Validation rejections at the assistant layer.** Saving an
   assistant with an unknown tool name is rejected (Rust
   `Assistant::validate` has no registry check — the registry
   check lives in Swift: `AssistantDefinition.validationIssues`
   via `SystemToolRegistry.unknownToolNames`, and
   `AppModel.saveAssistant` refuses before sending). Saving an
   assistant with `provider: opencode|lithos` and a non-empty
   `allowedTools` is rejected by the Rust validator (F5-fix4,
   `e11ac076`). A malformed `assistantId` (non-UUID) is rejected
   at thread creation and at worker spawn.

### Spawn-by-Assistant (F5, `ac79fb01`, plus fixes)

`workers.spawn` accepts `assistantId` per spawn request
(`worker_store.rs`: `parse_spawn_request` — a non-UUID value is
rejected, an absent/null value means no assistant). `spawn_one_worker`
(`workers_api.rs`) resolves it with `find_assistant` and builds the
child thread from the assistant:

- **Provider/model**: if the assistant pins a provider, the child
  selection is `{provider, modelID: model ?? "default"}`; otherwise
  the child inherits the parent's selection.
- **Prompt**: the child's `systemPrompt` is the assistant's stored
  system prompt, verbatim (see Gap 2 below).
- **Tools**: if the assistant's `allowedTools` is non-empty, the
  child gets `toolset: "system"` and that list. If the assistant
  has no tool list, the parent's toolset is inherited — but only
  when the fallback is valid: the parent toolset must not be
  `"provider"`, and if the parent is effectively on System Tools
  the child's provider must support them (F5-fix,
  `87a84a65`; F5-fix3, `883901d8`). An invalid fallback writes
  neither toolset nor tools, so the child cannot silently gain a
  prompt/toolset combination the engine would reject.
- **Link**: the child's `assistantId` is set to the requested
  assistant (F5-fix, `87a84a65` — canonical assistant ID on the
  child), or, with no assistant requested, inherited from the
  parent when the parent's value parses as a UUID. The worker
  record stores the same ID, which is what makes
  `workers.list?assistantId=` work.
- **Scope**: a spawn on a thread using a named Codex profile is
  refused before any of this (a per-thread system prompt cannot
  ride a named profile session).

### Selection parameter end-to-end (F6b, `b81e42ea`)

`AppModel.launchAssistant` maps the assistant's `AssistantModelConfig`
to a `RemoteSelectionOverride` and passes it, with the composed
prompt, `toolset: .system`, the assistant's `allowedTools`, and the
assistant's UUID, to `newThread`. The override travels Swift
(`RemoteProtocol.RemoteSelectionOverride`, `RemoteRequest.newThread`)
→ Rust (`remote_protocol.rs`: `NewThreadSelection`) →
`remote_adapter.rs`: `new_thread`, which validates the provider with
`Provider::from_name` and the model with
`composer_selection::validate_model`, then hands it to
`threads.create` as a selection override (provider-only fills
`modelID: "default"`, matching the worker-spawn precedent). Empty
thread reuse respects it: an untouched empty thread is reused only
when its stored selection already matches the request
(`thread_matches_selection`); otherwise a fresh thread is created,
so a requested selection is never silently dropped. A malformed
`assistantId` in `newThread` is a `bad_request`.

### Prompt composition, and Gap 2

Swift launch composes the prompt. `AppModel.launchAssistant` calls
`systemPrompt(for:provider:model:assistant:)`, which prepends the
assistant's system prompt to the request text and hands both, plus an
`AssistantPromptDescriptor` (id, name, system prompt, description),
to `SystemPromptBuilder.build`. The builder assembles the composed
prompt from the SystemAssets (mandatory `Safeguards.md` and
`Identity.md`, plus keyword/asset selection) under a 6,000-estimated-token
budget (`defaultMaxEstimatedTokens`), and the composed text is what
is stored on the thread as its system prompt.

Rust worker spawn does **not** compose. `spawn_one_worker` writes
the assistant's raw stored `systemPrompt` onto the child thread,
with no Safeguards/Identity/assets assembly. That is Gap 2, still
open at this base (named in the F6b commit message: "Gap 2 (Rust-side
prompt composer) remains open"). A worker spawned from an assistant
therefore runs on the bare assistant prompt, while a thread launched
from the same assistant in the app runs on the composed prompt.
Do not describe the two as equivalent.

## Automation execution: two schedulers, split ownership

There are two schedulers, and they schedule different things, so
neither double-fires nor drops the other's jobs. The legacy
`ScheduleService` (`scheduled-tasks.json`, `coincide-core/src/
schedule_service.rs`) owns thread-bound schedules: a schedule names
a project and a thread, the engine's poll claims due occurrences
at-most-once and sends the prompt into that thread as a foreground
turn, and completion is recorded back on the schedule claim. The
assistant task system (`assistant-tasks.json`, `coincide-core/src/
assistant_tasks.rs`) owns assistant automations: a task names an
assistant and a workspace, the Swift `AssistantTaskManager` polls
`tasks.due` every 60 seconds and starts each due occurrence with
`tasks.run_now`, which spawns a background worker under a fresh
parent thread. The two stores share no IDs and no code path creates
both a schedule and a task for one user action, so one job cannot be
claimed twice. Execution of a task run is owned by the same pair:
`tasks.run_now` enforces `maxConcurrent` by counting the task's
still-running workers and records the spawn in `activeWorkerIds`;
`tasks.record_outcome` writes a finished worker back to the task
(`lastOutcome`, `lastMessage`, a capped 50-entry `history`), applies
`failurePolicy` (retry with backoff while retries remain, stop with
no retry, notify requesting a failure notification), and the Swift
poll then deletes the run-now parent thread, which never receives a
turn and holds no user content. A task worker's completion or
failure notifies only when the task's own notification prefs allow
that outcome and the Assistants settings master and per-category
toggles allow it; a run-now prompt longer than 500 characters is
capped with an explicit `… [truncated]` marker. Worker cancel is a
request, not a result: `workers.cancel` leaves the status alone
until the provider turn ends, and the app keeps the run in a
`cancelling` state until a status poll confirms it terminal.

## What is NOT built yet

Everything below is absent at base `b81e42ea`. Do not describe any
of it as done; the file pointers are where the work would land, not
where it lives.

- **Execution manager.** There is one launch path:
  `AppModel.launchAssistant` (create a thread, send the task);
  background work goes through `workers.spawn` with `assistantId`.
  A second launch stack, `AssistantExecutionManager`, was removed:
  it had no production callers, and `refreshAssistants` rebuilt it
  whenever the catalog changed, dropping its in-memory runs. Run
  state lives only in the runtime workspace. No queue, no run
  record, no progress surface beyond those two paths.
- **Permission-profile enforcement (E1).** The four profiles are
  stored and tested for honesty against the tool lists, but nothing
  in the engine reads `permissionProfile`. A `workspace-modify`
  assistant is not granted write access by its profile, and a
  `read-only` assistant is not blocked from writing by its profile
  — the only runtime restriction is `allowedTools`. E1 would land
  in `assistants.rs` / `assistants_api.rs` (record the profile's
  meaning), `tools.rs` (enforce it at `tools/call`), and the
  catalog tests (assert profile and tools agree).
- **Change ledger.** No record of who changed an assistant, when,
  or from what to what. The document carries only `createdAt` /
  `updatedAt` per record and a single CAS baseline for the whole
  document. A ledger would be a new document/table beside
  `assistants.json`.
- **Triggers.** No scheduled, event-driven, or webhook trigger can
  invoke an assistant. `assistants.*` has no trigger field, and no
  scheduler references assistants.
- **UI surfaces.** There is no Assistants Library view, no assistant
  editor, no assistant picker in the composer, and no favorites or
  last-used surfacing. `AppModel.launchAssistant` exists and is
  wired to the engine, but it has **no caller** in any view at this
  base (verified by grep); the only assistant-adjacent UI is the
  unrelated "Use New York Serif for Assistant Replies" toggle in
  General Settings. The catalog, `refreshAssistants`, and
  `saveAssistant`/`deleteAssistant` are the app-side API surface
  waiting for a UI.
- **Automation.** No assistant can be invoked from a scheduled task,
  a worker plan, or any automation path except a direct
  `workers.spawn` with `assistantId` from a session that already
  knows the ID.

## Honest limits

- **No build or test was run in this environment.** All counts in
  this document are by reading source and by grep. The Swift
  assistant suites total **116 `@Test` functions** across eight
  files (`AssistantCatalogTests` 27, `AssistantTests` 18,
  `BuildingFixingPresetsTests` 14, `GitWorkflowAutomationPresetsTests`
  13, `SpecializedProductivityPresetsTests` 12,
  `RepositoryIntelligencePresetsTests` 11,
  `CodeMaintenancePresetsTests` 11,
  `CodeReviewSecurityPresetsTests` 10), plus **8 `#[test]`
  functions** in `assistants_api_tests.rs`. None were executed
  here; the Mac gate is Dylan's.
- **The read-only guarantee is only as strong as six hand-written
  lists.** See "The read-only guarantee" above: the mutating-tool
  sets differ per category file, and there is no registry-wide
  mutating classification. A tool added to the registry is
  mutating-by-default nowhere; it is only caught if a test file's
  list names it. The C-fix history proves the tests catch real
  violations — and proves violations reached the presets before
  the tests caught them.
- **Gap 2 is open**: Rust worker spawn uses the raw stored prompt;
  Swift launch uses the composed prompt.
- **Provider-None + tools + OpenCode still fails at spawn.** If an
  assistant pins no provider, carries a non-empty `allowedTools`,
  and is spawned from a parent on OpenCode (or Lithos), the child
  is built with `toolset: "system"` and the parent's OpenCode
  selection — and thread creation rejects it
  (`thread_defaults.rs`: System Tools are not supported for that
  provider). The spawn fails; the failure is loud, not silent,
  but the combination has no graceful fallback. The same
  combination is rejected earlier at assistant-save time when the
  assistant itself pins `opencode`/`lithos` (F5-fix4); the gap is
  specifically the provider-None case inheriting an unsupported
  provider from the parent.
- **Swift/Rust rejection shapes differ for `use_app`.** Rust
  reports a disallowed inner tool as `UnknownTool` (`-32602`);
  Swift reports it as `toolNotActive`. Callers that match on the
  error must handle both.
- **`lastUsedAt` and `isFavorite` are stored but never written.**
  Any UI that sorts by "recently used" or shows favorites would
  read empty data until a launch path starts writing them.
- **Change-ledger `.empty` is unreachable while pre-existing
  untracked files exist.** `AssistantChangeLedger.finishRun`
  judges the post-run diff against the pre-run snapshot, not the
  post-run state: if the snapshot contains any untracked (`??`)
  file, an otherwise-empty diff reports `.unavailable`
  ("Untracked files were present before the run and the post-run
  diff came back empty, so an empty result cannot be trusted")
  instead of `.empty` — even when the run itself changed nothing
  and the untracked file is gone by the end of the run. This is
  deliberate conservative design, not a bug: an empty diff cannot
  prove the run changed nothing when untracked files were present
  at the start. Treat `.unavailable` with that reason as "no
  change observed", not as a failure.
- **The assistant record is not validated against the registry in
  Rust.** `Assistant::validate` checks shape, limits, provider,
  and the opencode/lithos rule, but an unknown tool name in
  `allowedTools` passes Rust validation; the registry check lives
  in Swift (`AssistantDefinition.validationIssues`,
  `AppModel.saveAssistant`). A client that writes
  `assistants.json` through the engine directly can store unknown
  tool names; the MCP server ignores them at enforcement time.
