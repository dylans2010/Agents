# Auto-updater audit

Date: 2026-11-18 (Slice 65). Static audit only: no build, no test run, no
live network check. The auditor read the Rust updater in `coincide-core`
(`updater.rs`, `updater_install.rs`, `updater_helper.rs`), its only caller
(`coincide-desktop`, the superseded GPUI desktop), the native Swift app, and
the Xcode project. Every finding below cites file and line.

## Verdict

No real defect was found, and no code was changed. All four audited areas
are already handled in the code, with tests covering the security-relevant
branches. The larger finding is scope: **the updater is dead in the shipped
native Swift app**. It can only run inside the superseded GPUI desktop, and
even there only behind a non-default feature flag and four environment
variables. Changing dead code was out of scope, so this audit is recorded
here instead, with recommendations at the end.

## 1. Scope: the updater is not live in the shipped app

- The shipped app is built by `project.yml`, whose only Rust builds are
  `cargo build --release -p coincide-macos-ffi` and
  `cargo build --release -p coincide-mcp-server` (lines 47, 50). It never
  builds `coincide-desktop`, the `CoincideRustUpdater` helper binary, or any
  updater helper target, and it contains no `AgentsUpdater` target.
- No Swift source references the updater: zero matches for `Updater`,
  `check_for_updates`, `CheckForUpdates`, `update_feed`, or
  `install_update` in `Agents/` and `AgentsTests/`, and zero matches for
  `Check for Updates`, `App Updates`, `checksForAppUpdates`, or
  `lastAppUpdateCheck`. The native app has no update UI at all.
- `coincide-macos-ffi` contains zero updater references and exposes no
  updater function over its C API. `coincide-mcp-server` never calls the
  updater either; the only `updater::` references outside the updater
  modules themselves are in `coincide-desktop`, the
  `updater_stage_e2e.rs` example, and the feature-gated helper binary.
- The updater targets a different app: `PREVIEW_ID` is
  `com.apoorvdarshan.coincide.rust` and the channel is `rust-preview`
  (`Rust Backend/crates/coincide-core/src/updater.rs:31-32`), while the
  shipped app is `com.apoorvdarshan.coincide` / `Agents.app`. The desktop
  mount additionally requires the running executable to be exactly
  `Coincide Rust.app/Contents/MacOS/coincide-rust`
  (`Rust Backend/crates/coincide-desktop/src/updater_mount.rs:89-92`).
- Even inside `coincide-desktop`, the channel is off unless all of
  `COINCIDE_RUST_UPDATE_FEED`, `COINCIDE_RUST_UPDATE_ARTIFACT_BASE`, and
  `COINCIDE_RUST_UPDATE_ANCHOR` are set
  (`updater_mount.rs:57-63`), install additionally requires
  `COINCIDE_RUST_UPDATE_ENABLE_INSTALL=1` (`updater_mount.rs:154`), and
  the whole helper path is behind the `preview-updater-helper` feature,
  which is not a default feature of `coincide-core` (its
  `Cargo.toml:9` defines it as empty) or of `coincide-desktop` (whose
  defaults are only `native-notifications`, `native-microphone`, and
  `native-computer-use`).
- One caveat: `updater` and `updater_install` are unconditional modules in
  `coincide-core/src/lib.rs:67,84`, so their code is compiled into
  `libcoincide_macos_ffi.a` and `coincide-mcp-server` as unreachable dead
  code. Only `updater_helper` is feature-gated (`lib.rs:86-87`). There is
  no entry point from the shipped app into any of it.

`docs/app-updates.md` describes the pre-reconstruction Swift desktop's
GitHub Releases flow and is explicitly frozen as a historical record; it is
not the current state and was left untouched.

## 2. Feed validation: handled

- There is no default feed anywhere. The feed URL must be supplied by the
  caller; in the desktop it comes only from the
  `COINCIDE_RUST_UPDATE_FEED` environment variable.
- `Updater::configured` rejects the configuration unless the feed and the
  artifact base both satisfy `RequestPolicy::allows`
  (`updater.rs:396`): scheme must be `https`, no username, no password, no
  port, no query, no fragment, and the host must be in the explicitly
  configured allowlist of at most 16 hosts (`updater.rs:163-172`). An
  `http://` feed, a `file://` URL, or any non-allowlisted host fails
  configuration before any request is made; the test
  `missing_anchor_and_insecure_feed_cannot_enable_service` covers the
  `http://` case.
- The desktop mount additionally requires the feed and artifact-base hosts
  to be identical (`updater_mount.rs:96-100`), and `configured` requires
  the artifact base path to end with `/` (`updater.rs:397-398`).
- Every request and every redirect hop is re-checked against the same
  policy, and the service independently verifies the complete redirect
  chain (at most six entries, starting at the requested URL)
  (`updater.rs:589-615`). The concrete transport enforces HTTPS-only, no
  proxy, no automatic redirects, and no content decompression
  (`updater.rs:1291-1293`).

No fix. Nothing to add: a stricter feed rule would duplicate checks that
already exist at configuration, request, and redirect time.

## 3. Download integrity: handled

- The downloaded archive's SHA-256 is verified against the feed's digest
  before any extraction (`updater.rs:959`), and the download is refused
  unless the received byte count equals the feed's declared size and the
  HTTP status and content length agree (`updater.rs:934-940`). The feed
  digest itself must be exactly 64 lowercase hex characters, and the
  declared size must be within the configured archive bound
  (`updater.rs:660-680`). Hash/size mismatches never reach the decoder
  (covered by `hash_and_size_mismatch_never_reach_decoder_and_partial_jobs_are_removed`).
- The feed hash is not signed: its trust rests on TLS to an allowlisted
  host. That is a real limitation of the feed format, but it is not an
  installable defect here, because installation never rests on the feed
  hash alone. The staged candidate must also pass pinned Developer ID
  code-signature verification (section 4) at stage time, at
  authorization, at arming, and repeatedly inside the helper; a forged
  feed hash without a bundle signed by the pinned team cannot install.
  Adding a feed-signature scheme would need a signing key, a feed format
  change, and a verifier, which is not a minimal fix and is not warranted
  for a dead code path. Recorded as a residual, not fixed.
- Size is bounded end to end: metadata 2 MiB, archive 512 MiB, expanded
  1 GiB, per-entry 256 MiB, under 50,000 entries, with a 64 MiB disk
  reserve (`updater.rs:79-88`, enforced by `Limits` validation in
  `configured`). The transport enforces the bound while reading, including
  a one-byte probe for over-limit chunked bodies, and the writer checks
  free disk space before every chunk.
- Staging is private: the cache root must pre-exist, be absolute, be
  owned by the current user with mode 0700, contain no symlinks in any
  ancestor, and not sit inside an `.app` bundle (`updater.rs:689-720`).
  Job directories are fresh UUID names created 0700, archive files are
  created with `create_new` at 0600 so no existing file or symlink is
  followed (`updater.rs:728-737`), and extraction only emits regular
  files through a bounded sink that rejects traversal, case aliases,
  reserved Windows names, symlinks, and children beneath files.

No fix.

## 4. Install safety: handled

- Atomic: the exchange uses `renameatx_np(RENAME_SWAP)` on macOS and
  `renameat2(RENAME_EXCHANGE)` on Linux, after verifying target and
  replacement are on one filesystem
  (`Rust Backend/crates/coincide-core/src/updater_install.rs:1260-1298`).
  The trait documents that it must never be implemented as
  remove-and-rename or copy-over-target.
- Bundle identity and code signature are verified before the running app
  is touched: `MacCodeVerifier` runs `codesign --verify --strict --deep
  --all-architectures` with a designated requirement pinning the Apple
  anchor, the Developer ID team (`subject.OU` equals the configured
  10-character anchor), and the preview bundle identifier, then verifies
  each executable the same way plus `lipo -verify_arch`, then runs
  Gatekeeper assessment with `spctl --assess --type execute`
  (`updater_install.rs:1348-1480`). The installed app's identity and the
  candidate's identity are both verified, the candidate must be strictly
  newer, and both bundle fingerprints must be unchanged after the user
  prompt (`updater_install.rs:459-531`). Verification repeats at arming
  and at every step inside `run_helper`, which re-verifies the installed
  app, the candidate, the copied backup, and the post-exchange result
  (`updater_install.rs:534-560,641-760`).
- Backup and rollback: the candidate is copied beside the target as
  `.Coincide-Rust-backup-<UUID>.app`, verified there, and only then
  swapped in. A failed post-exchange verification swaps the backup back;
  if rollback also fails, both bundles are retained for recovery and the
  outcome reports it (`updater_install.rs:662-770`). Backups are retained
  for manual recovery, never silently deleted.
- User confirmation: installation requires an explicit native approval
  of the exact proposal (`NativeApproval::present`, via
  `request_native_authorization`), then a consent marker bound to the
  transaction, the proposal hash, and a nonce, written only after the
  app's clean-quit barrier (shutdown, flush) succeeds, and then proof
  that the exact parent process exited normally before the helper writes
  anything beside the target (`updater_install.rs:220-233,641-660`).
  There is no silent auto-install: staging alone never authorizes
  installation (`Stage.install_authorized` is always false,
  `updater.rs:1037`), and `fresh_install_candidate` rehashes the staged
  archive and re-extracts it from scratch rather than trusting any
  previously extracted bytes (`updater.rs:1149-1250`).

No fix.

## 5. Update-check behavior: handled

- Cadence is bounded: the desktop looks once an hour and checks at most
  once a day, only when the daily preference is on
  (`Rust Backend/crates/coincide-desktop/src/updater_settings.rs:26-33,379`).
  There is no startup check and no automatic retry loop. The check
  timeout is 30 seconds and the stage timeout 10 minutes
  (`updater.rs:86-87`); only one operation runs at a time
  (`updater.rs:435-445`).
- A failed check is not silent: failures land in `State::Failed(reason)`
  and the settings status text shows the reason verbatim
  (`updater_settings.rs:218-238`). A 404 is a distinct `Unpublished`
  state and an equal version is a distinct `Current` state.
- The last-check timestamp is recorded before a check starts, so a
  failing check does not cause hammering
  (`updater_settings.rs:324-339,369`).
- Malformed feeds cannot crash the app: feed parsing errors, unknown
  fields (`#[serde(deny_unknown_fields)]`, `updater.rs:116-117`),
  non-numeric or ambiguous versions, a missing or duplicate
  platform/architecture artifact, and an artifact URL that is not
  exactly the configured base plus version plus platform asset name all
  produce `State::Failed`, covered by
  `refuses_swift_channel_artifact_wrong_architecture_and_duplicate_target`
  and `equal_version_unpublished_and_http_error_have_distinct_states`.

No fix.

## Recommendations (not done here)

1. Consider removing `updater` and `updater_install` from the
   unconditional module list in `coincide-core/src/lib.rs`, or gating
   them behind `preview-updater-helper` like `updater_helper`, so dead
   update code stops shipping inside `libcoincide_macos_ffi.a` and
   `coincide-mcp-server`. Not done in this slice: it touches the crate
   surface used by `coincide-desktop` and its tests, and cannot be
   verified without a build.
2. If the Rust preview channel is ever revived as a live path, sign the
   feed (or ship the digest out of band) so the archive hash does not
   rest on TLS alone, and write a current user-facing document for the
   live channel; `docs/app-updates.md` stays frozen history.
3. The six blocked collaboration features and the updater share one
   property worth remembering: code that is present but unreachable
   should be labeled as such wherever it is referenced, so a future
   reader does not mistake compilation for availability.

## Validation performed (static only)

- Python replication of the Rust cross-check test
  (`tool_table_matches_swift_registry` in
  `Rust Backend/crates/coincide-mcp-server/src/tools.rs:21283-21320`),
  including per-parameter descriptions: 333 Swift tools = 333 Rust
  tools, 1,088 parameters each side, 0 mismatches. Registry count
  now at 333 (delete_worker added by Slice W9).
- Brace/paren/bracket balance checked on the changed file (this
  document); `git diff --check` clean; secrets sweep clean; no `//`
  comments in new code (this file is prose, no code added).
- No build or test was run. No Swift, Rust, Xcode, or cargo invocation
  was made. The Rust tests cited above were read, not executed.
