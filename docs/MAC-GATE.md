# Mac Gate — Agents

The single ordered checklist for the Mac gate: Xcode build, Swift tests,
Rust tests, live provider runs, and visual/accessibility checks. Run it
top to bottom on Dylan's Mac against one commit and record the result in
the sign-off section at the end.

Status of everything below: statically verified only. Nothing in this
repository was compiled, executed, or tested in the environment where this
document was written — there is no Swift toolchain and no cargo there. Every
command, target, scheme, and count in this document was read out of the
source file named next to it. Where a check the program asked for does not
exist in this checkout, this document says so instead of inventing it.

Base commit at time of writing: remote `main` at `f9d55e0a`. That tip
moves — Dylan pushes from his Mac too — so confirm the tip before starting
and record the exact commit tested in the sign-off section.

## 0. Preparation

### 0.1 Checkout state

Work on `main` in `~/workspace/repos/Agents` (or the equivalent local
checkout). Confirm the branch and the remote tip before starting:

    git status --short --branch
    git log --oneline -3
    git rev-parse HEAD

The checkout used to write this document was local `main` at `013c0057`,
clean, with remote `main` at `f9d55e0a`. If the remote tip has moved since,
re-sync to it first and record the new SHA in the sign-off section. Do not
gate an older commit and report it as the tip.

Push route note: plain `git push` over HTTPS does not work from the agent
environment (no credential helper; the stored token is api.github.com-only).
Dylan pushes from his Mac normally. Nothing in this gate depends on the
agent-side API push route.

### 0.2 Prerequisites (all verified from the files named)

- Xcode 27. CI runs the Agents jobs on the `xcode-27` runner, and the
  CodeQL workflow notes that image ships Xcode 27 on the macOS 27 SDK
  (`.github/workflows/ci.yml`, `.github/workflows/codeql-swift.yml`).
- XcodeGen 2.46.0, SHA-256
  `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`
  (`.github/workflows/ci.yml`, `.github/workflows/ios-tests.yml`).
- Rust stable toolchain. CI installs it with `dtolnay/rust-toolchain`
  (stable) in the `agents-app`, `analyze-agents`, and Rust jobs
  (`.github/workflows/ci.yml`, `.github/workflows/rust.yml`).
- The Agents target's pre-build scripts compile `coincide-macos-ffi` and
  `coincide-mcp-server` with cargo before the Swift build, and the
  post-build script bundles `coincide-mcp-server` into the app
  (`project.yml`). Cargo must be on `PATH` before `xcodebuild` runs, or the
  build fails in the pre-build script, not in Swift code.
- The app targets macOS 26.0, Swift 6.0, arm64 only, marketing version
  0.2.0 (`project.yml`). The iOS Remote app is a separate project
  (`project-remote.yml`, `project-remote-tests.yml`).

## 1. Ordered gate steps

Do these in order. A failure in an early step blocks the later ones that
depend on it; record the failure and stop rather than skipping ahead.

### Step 1 — Generate the Xcode project

From the repo root:

    xcodegen generate

This is the exact command the `agents-app` CI job runs
(`.github/workflows/ci.yml`). It generates `Agents.xcodeproj` from
`project.yml` (scheme `Agents`, targets `Agents` and `AgentsTests`).

### Step 2 — Build the Agents app

    xcodebuild -project Agents.xcodeproj -scheme Agents -destination 'platform=macOS' -skipPackagePluginValidation -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

This is the exact build command from the `agents-app` job
(`.github/workflows/ci.yml`). Expect the pre-build scripts to run
`cargo build --release -p coincide-macos-ffi` and
`cargo build --release -p coincide-mcp-server` first. If the build fails
there, it is a Rust problem, not a Swift one — go to Step 5 and reproduce
it with cargo directly.

### Step 3 — Run the Agents Swift tests

    xcodebuild -project Agents.xcodeproj -scheme Agents -destination 'platform=macOS' -skipPackagePluginValidation -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages test -collect-test-diagnostics never CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

This is the exact test command from the `agents-app` job
(`.github/workflows/ci.yml`). It runs the `AgentsTests` target
(`project.yml`, scheme `Agents`, test config Debug).

Expected count, measured by grep at time of writing: **105 `@Test`
functions** in `AgentsTests` (`grep -rn "@Test" AgentsTests`). The
registry test asserts the tool count directly
(`AgentsTests/ToolsetTests.swift`, `#expect(tools.count == 332)`).

### Step 4 — Run the Coincide Remote iOS tests

This is the separate iOS Remote app, not the macOS Agents scheme. Generate
its test project, then build-for-testing and test on a booted simulator
(commands from `.github/workflows/ios-tests.yml`; the simulator ID comes
from that workflow's simulator setup — use a booted iPhone simulator on
the gate Mac):

    xcodegen generate --spec project-remote-tests.yml --quiet

    xcodebuild -project CoincideRemoteTests.xcodeproj -scheme CoincideRemote -destination "platform=iOS Simulator,id=$SIMULATOR" -skipPackagePluginValidation -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages build-for-testing

    xcodebuild -project CoincideRemoteTests.xcodeproj -scheme CoincideRemote -destination "platform=iOS Simulator,id=$SIMULATOR" -skipPackagePluginValidation -skipPackageUpdates -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages test-without-building -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -collect-test-diagnostics never -resultBundlePath build/iOSTests.xcresult

The scheme is `CoincideRemote` and its test targets are
`CoincideRemoteTests` and `CoincideRemoteUITests`
(`project-remote-tests.yml`). Expected counts, measured by grep at time of
writing: **19 `@Test` functions** in `CoincideRemoteTests` and **0 `@Test`
in `CoincideRemoteUITests`** — the UI tests are XCTest-style
(`@MainActor`, no `@Test`), so a zero there is expected, not a missing
suite. CI additionally checks that both bundles actually ran tests from
the result bundle; a passing `xcodebuild` with an empty bundle is a
failure, not a pass.

### Step 5 — Run the Rust tests

Workspace members, read from `Rust Backend/Cargo.toml`:

- `crates/coincide-core`
- `crates/coincide-desktop`
- `crates/coincide-native-host-tests`
- `crates/coincide-awake-helper`
- `crates/coincide-macos-ffi`
- `crates/coincide-mcp-server`

Measured test-attribute counts, excluding `vendor/`, counted by grep at
time of writing. Two spellings count: the short form `#[test]` and the
fully-qualified `#[::core::prelude::v1::test]` (used by the UI-test
modules in `coincide-desktop`, which import it with
`use ::core::prelude::v1::test;`). Raw short-form grep finds 2,217
matching lines, but one is prose inside a comment —
`crates/coincide-desktop/src/diff_panel_ui_tests.rs:5`, a `//` comment
reading "The glob brings GPUI's test attribute, which expands to
#[test] again." — not a real attribute, so the short-form total is
2,216. Fully-qualified grep finds 736 real attributes, all in
`coincide-desktop`; the 7 other lines matching that string are the
`use ::core::prelude::v1::test;` imports, not attributes. The true
total is **2,952** test attributes. Reproduce from `Rust Backend` with
`find crates -name '*.rs' -not -path '*/vendor/*' -exec grep -H
'#\[test\]' {} + | wc -l` for the raw short-form count, then subtract
matching lines whose `#[test]` sits inside a `//` comment (exactly one,
the line above), and add `find crates -name '*.rs' -not -path
'*/vendor/*' -exec grep -H '#\[::core::prelude::v1::test\]' {} + |
wc -l` for the fully-qualified count:

| Crate | `#[test]` | `#[::core::prelude::v1::test]` | Total |
| --- | --- | --- | --- |
| coincide-core | 1,821 | 0 | 1,821 |
| coincide-desktop | 367 | 736 | 1,103 |
| coincide-awake-helper | 9 | 0 | 9 |
| coincide-macos-ffi | 3 | 0 | 3 |
| coincide-mcp-server | 16 | 0 | 16 |
| coincide-native-host-tests | 0 | 0 | 0 |
| **Total** | **2,216** | **736** | **2,952** |

Run the workspace suite from `Rust Backend`:

    cargo test --locked

Then run the exact per-package commands CI uses, because the workspace run
and CI do not cover the same surface (`.github/workflows/rust.yml`,
`.github/workflows/ci.yml`):

    cargo test -p coincide-core --locked
    cargo test -p coincide-awake-helper --locked
    cargo test -p coincide-desktop --locked --features native-notifications,native-microphone,native-computer-use

Coverage gap to know about before interpreting results:
`coincide-mcp-server` (16 tests) and `coincide-macos-ffi` (3 tests) have
no `cargo test` coverage in any CI job. Their first CI coverage is the
`agents-app` job building them via the Xcode pre-build scripts. On the
gate Mac, also run:

    cargo test -p coincide-mcp-server --locked
    cargo test -p coincide-macos-ffi --locked

CI also runs `cargo fmt --all --check` and
`cargo clippy -p coincide-core --all-targets --locked -- -D warnings`
(`.github/workflows/rust.yml`). Run both from `Rust Backend` and treat
failures as gate failures, not style nits — CI enforces them.

### Step 6 — Confirm CI is green on the tested commit

Watch the GitHub Actions runs for the pushed commit. The jobs that must
be green:

- `agents-app` ("Agents macOS app build and test") in
  `.github/workflows/ci.yml` — xcodegen, the Step 2 build, and the Step 3
  tests on the `xcode-27` runner.
- `rust-core` in `.github/workflows/ci.yml` — `cargo test -p
  coincide-core --locked`.
- `build-and-test` in `.github/workflows/ci.yml` — the gate job that
  requires the relevant checks above.
- `analyze-agents` ("Analyze (swift, Agents app)") in
  `.github/workflows/codeql-swift.yml` — CodeQL static analysis of the
  Agents target. Note: this job runs weekly, on release tags, and on
  demand only — never on pushes to main — and the workflow says it is not
  a required check. Do not wait on it for a push, but do trigger it on
  demand after a large landing and read its findings. Its build is a
  clean unsigned build with no cache:
  `xcodebuild -project Agents.xcodeproj -scheme Agents -destination
  'platform=macOS' -skipPackagePluginValidation -derivedDataPath
  build/CodeQL-Agents build CODE_SIGNING_ALLOWED=NO
  COMPILER_INDEX_STORE_ENABLE=NO`.

The `Rust` workflow (`.github/workflows/rust.yml`) covers core, desktop,
awake-helper, and native-host-tests across macOS, Linux, and Windows;
on the gate Mac the macOS leg is the one that matters.

## 2. Live behavior checks

No commands are invented here: each check names the feature and the file
it exercises, in words. If a check cannot be performed, record it as
not-checked rather than as passed.

### 2.1 Live provider sessions

The provider split is documented in `README.md` and
`docs/SYSTEM-TOOLSET.md` and is the behavior to verify per provider.
Start one real session with each provider against a real account and a
real workspace, and confirm the toolset behavior matches the documented
split:

- **Claude**: system prompt (`--append-system-prompt`) plus the MCP
  mount. Confirm the 332 system tools are offered through the mount and a
  tool call round-trips through `coincide-mcp-server`.
- **Codex**: system prompt only, no MCP mount. Confirm the prompt is
  delivered and no MCP mount is attempted.
- **Cursor, Grok, Antigravity, ACP**: MCP mount (no Codex/Claude-style
  prompt split). Confirm the mount is offered and a tool call works.
- **OpenCode, Lithos**: reject System Tools. Confirm the rejection is
  clean and the session still works with the provider's own tools.

The mount plumbing is `mcp::mount_for` / `session_servers_for` /
`claude_config_path` in `Rust Backend/crates/coincide-core/src`
(`api.rs`, `provider_acp.rs`, `provider_antigravity.rs`,
`provider_claude.rs`). The 332-tool registry is
`Agents/Core/SystemTools/SystemToolRegistry.swift` (Swift mirror) and
`Rust Backend/crates/coincide-mcp-server/src/tools.rs` (the 332
`DEFINITIONS` entries the server actually serves). Both sides were
measured at 332 with 63 distinct actions at time of writing, and tests
assert 332 on both sides (`AgentsTests/ToolsetTests.swift`,
`tools.rs` cross-check test).

### 2.2 Turn-completion watermark

Run a turn and confirm the sidebar/activity UI marks it finished once,
and only once, with the right outcome (completed / failed /
interrupted). Then run more than 64 turns in one session and confirm the
oldest finished-turn entries drop out of the recent window without
replaying or sticking (the engine keeps a 64-entry window:
`RECENT_LIMIT` in
`Rust Backend/crates/coincide-core/src/thread_activity_api.rs`; the
Swift side polls `newlyFinishedTurns(since:)` in
`Agents/Core/DesktopModels.swift` and `Agents/Core/AppModel.swift`).
Relaunch the app and confirm no earlier session's turns replay — turn
results are session-only and never persisted (same file, header comment).

### 2.3 Computer-use permission prompts

Trigger a computer-use action from a session and confirm the permission
prompt appears before anything happens, and that declining blocks the
action cleanly. The prompt path is
`ComputerUseController.requestPermission` in
`Agents/Core/ComputerUse/ComputerUseController.swift`, and the inbound
`session/request_permission` method on the provider side. Confirm the
prompt names the action it is asking about.

### 2.4 Memory persistence across restart

Store a memory from a session (the `memory.store` system tool), quit the
app completely, relaunch, and confirm the memory is still listed. Memory
lives in the `memory_entries` table with a one-time transactional
migration from the legacy `memory.json`
(`Rust Backend/crates/coincide-core/src/store.rs`,
`memory_store.rs`). Also confirm a stored memory survives a second
restart — one restart proves the write path, two prove the read path is
not serving a stale in-memory copy.

### 2.5 Worker spawn and report-back

Spawn a worker from a session (the `workers.spawn` system tool), confirm
it starts, confirm its report comes back into the parent session, and
confirm the worker record survives an app restart (`worker_records` /
`worker_plans` in `store.rs`). Check the worker UI in
`Agents/Inspector/WorkersInspectorView.swift` shows the worker's state
while it runs.

### 2.6 Git tools live

Exercise the git system tools against a real repository from inside a
session: list branches, show a log, show a diff, and run a git action
(`git.branches.list`, `git.log`, `git.diff`, `git.actions.run` in the
registry). Confirm each returns real repository output and that a
failed git command reports the failure instead of inventing output.

### 2.7 Spaces and Device Hub — not present in this checkout

This section is a negative finding, recorded so it is not mistaken for a
passed check. At time of writing:

- `docs/SPACES-COMPLETION-REPORT.md` does not exist in this repository.
- No Spaces source-control system was found anywhere in the checkout
  (no Spaces code, no `.spaces` format, no Spaces CLI, nothing in
  `CHANGELOG.md`). There is no 30-step Spaces end-to-end scenario to run
  and no Spaces SSH/HTTP/Git round-trips to perform from this repo.
- No Device Hub was found anywhere in the checkout (no Device Hub code,
  no `simctl`/`devicectl` device management). There are no Device Hub
  live device checks to run from this repo.

The closest verifiable surfaces are the git system tools in section 2.6
and the simulator device tools in the registry (`device_list` and
related, taking a simulator UDID or name). Do not mark this section
passed. Either the features live in another repository, or they were
never landed here — that is a question for the program, not something
the gate can answer by running this checkout.

### 2.8 Liquid Glass visual check

The glass styling lives in `Agents/Core/AppTheme.swift`
(`glassEffect(.regular, ...)` variants, including tinted). Check the app
in both dark and light mode: glass cards, toolbar elements, and tinted
variants should read as glass, not as flat grey or as unreadable
low-contrast text. Check a tinted glass element over both a light and a
dark background, and check the composer and inspector surfaces where
glass is used most.

### 2.9 Accessibility spot-check

Slice 32 added 16 accessibility labels and left 3 controls unresolved
because a label alone cannot fix them. Verify those 3 with VoiceOver on:

- The composer `NSTextView` — `Agents/Conversation/ComposerNSTextView.swift`
  (AppKit text view, no AppKit-side label; SwiftUI-side label
  unverifiable statically).
- The two `onTapGesture` click targets in
  `Agents/Inspector/DiffInspectorView.swift` — file-row select and
  diff-line gutter jump — which need `accessibilityElement` / action
  work, not just a label.

Also check the two Slice 32 labels that restate adjacent hint text, and
decide whether they help or double-announce with VoiceOver:

- `Agents/Inspector/ComputerUseInspectorView.swift` — the arguments
  `TextEditor` label repeats the visible heading directly above it.
- `Agents/Inspector/GitInspectorView.swift` — the commit-message
  `TextEditor` label repeats the hint text shown when the field is empty.

## 3. Known unverified / honest limits

Every item below was verified against the code or docs named. Nothing
here is a guess about the implementation, and nothing here was observed
running — these are the limits as the code stands.

- **Hand-made `Cargo.lock` entry.** The `coincide-mcp-server` package
  entry in `Rust Backend/Cargo.lock` was hand-added and only statically
  verified; cargo was not run (commit `a8368f40`, message item F-3). No
  CI job runs `cargo test -p coincide-mcp-server --locked`, so a
  `--locked` build against that entry is unverified until CI runs. If
  Step 5's `cargo test -p coincide-mcp-server --locked` fails on lock
  resolution, this entry is the first suspect.
- **MCP server is a sequential loop.** `coincide-mcp-server` reads one
  stdio line, handles it synchronously, writes the response, and loops
  (`Rust Backend/crates/coincide-mcp-server/src/main.rs`, `run()`).
  There is no per-call timeout on `handle()` and no concurrency: one
  slow `tools/call` blocks every other caller until it returns. Request
  frames over 16 MiB are rejected with a parse error.
- **No overall turn-level timeout.** Individual tools carry their own
  `timeoutSeconds` parameters, but no turn-level timeout was found in
  `Agents/Core/AppModel.swift` or `Agents/Core/AgentToolset.swift`. A
  turn that keeps making progress (or keeps stalling inside per-tool
  timeouts) has no outer bound.
- **Fixed 2 MiB caps, no configurable context budget.** Several payloads
  are hard-capped at 2 MiB with no user-facing control: handoff prompt
  text (`MAX_TEXT` in
  `Rust Backend/crates/coincide-core/src/handoff_prompt.rs`), message
  queue bytes (`QUEUE_BYTES` in `message_queue.rs`), and model-catalog
  output (`MAX_OUTPUT` in `model_catalog.rs`). No single configurable
  context budget was found.
- **Turn-completion watermark is a 64-entry window.** The engine keeps
  only the 64 most recent finished-turn entries and drops older ones
  (`RECENT_LIMIT` in `thread_activity_api.rs`). Anything that polls
  `app.status` less often than every 64 finished turns can miss
  completions; that is by design, not a bug, but it is a limit.
- **Bare-name PATH fallback for provider binaries.** A bare provider
  binary name is resolved through an augmented search path, because
  macOS GUI launches often omit Homebrew and user-local executables
  (`search_path()` / `resolve_executable()` in
  `Rust Backend/crates/coincide-core/src/acp_registry.rs`, which adds
  `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `~/.local/bin`,
  `~/.cargo/bin`, `~/.bun/bin`). A provider installed outside those
  paths and outside the GUI `PATH` will not be found.
- **`search_web` is unofficial scraping.** It fetches
  `https://html.duckduckgo.com/html/` and parses the HTML — no search
  API (`SystemToolRegistry.swift`, `tools.rs`). Results may be empty if
  DuckDuckGo blocks the request or changes its markup; the tool reports
  failure rather than faking results, so an empty result on the gate Mac
  means the scrape failed, not that the web has no results.
- **`sips` SVG conversion is host-dependent.** `svg_to_png` shells out
  to `sips -s format png` (`tools.rs`). The tool description warns
  complex SVGs can distort at small sizes, and the result is whatever
  the gate Mac's `sips` does with the file. Verify with a real SVG on
  the gate Mac rather than assuming any particular macOS version's
  behavior.
- **Two Slice 32 labels restate adjacent hint text.** See section 2.9:
  the ComputerUse arguments editor and the Git commit-message editor.
  Cosmetic, but a VoiceOver double-announce if the label and the hint
  are both read.
- **The Swift registry `execute()` has no production caller, by
  design.** Its only callers are tests
  (`AgentsTests/ToolsetTests.swift`). Production execution is the Rust
  MCP server's `tools/call`
  (`Rust Backend/crates/coincide-mcp-server/src/tools.rs`), with the
  Swift `SystemToolRegistry` as the canonical schema mirror
  (`docs/SYSTEM-TOOLSET.md`). Do not "fix" this by wiring the Swift
  `execute()` into the turn path — that would create two execution
  paths.

## 4. Sign-off checklist

Check each box as its step passes, and record failures inline with the
reason. A step that was not run is unchecked, not passed.

- [ ] Step 1 — `xcodegen generate` clean
- [ ] Step 2 — Agents app builds (Agents scheme)
- [ ] Step 3 — Agents Swift tests pass (AgentsTests, 105 `@Test`)
- [ ] Step 4 — Coincide Remote tests pass (CoincideRemoteTests, 19
  `@Test`; UI tests ran, not skipped)
- [ ] Step 5 — Rust tests pass (2,952 test attributes excl. vendor:
  2,216 `#[test]` + 736 `#[::core::prelude::v1::test]`; incl.
  `coincide-mcp-server` and `coincide-macos-ffi`); `cargo fmt --check`
  and clippy clean
- [ ] Step 6 — CI green on the tested commit (`agents-app`,
  `rust-core`, `build-and-test`; `analyze-agents` triggered/read if run)
- [ ] 2.1 — Live provider sessions verified (Claude, Codex, Cursor,
  Grok, Antigravity, OpenCode)
- [ ] 2.2 — Turn-completion watermark behaves (incl. >64-turn window)
- [ ] 2.3 — Computer-use permission prompts appear and decline blocks
- [ ] 2.4 — Memory persists across two restarts
- [ ] 2.5 — Worker spawn and report-back verified
- [ ] 2.6 — Git tools return real repository output
- [ ] 2.7 — Spaces / Device Hub: NOT PRESENT in this checkout (see
  section 2.7; do not check this box as passed)
- [ ] 2.8 — Liquid Glass visual check, dark and light
- [ ] 2.9 — Accessibility spot-check of the 3 unresolved controls

Mac-gate result: _pass / fail_ — commit tested: ______________ — date:
______________ — notes: ________________________________________
