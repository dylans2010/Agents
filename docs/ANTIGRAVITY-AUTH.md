# Antigravity Authentication

This is the verified auth design for the Antigravity provider in Agents. It
describes what the code actually does — not what the settings UI used to
imply.

## API-key-only, by design

Antigravity authenticates with a Gemini API key and nothing else. There is
no OAuth flow in Agents: Google sign-in was removed in this repo, and
there is no OAuth infrastructure in this repo to reuse or to work
around. Do not build a browser OAuth flow, do not
set `AGY_ACP_ENABLE_OAUTH`, and do not import a legacy `acp_token.json` —
the profile guard refuses to start a thread when one is present.

Keys are stored as named accounts in macOS Keychain, one `GEMINI_API_KEY`
per account. A thread selects exactly one account; the key is handed to the
ACP server process through its environment only, and only for that thread.

## Per-thread private profile

Each thread runs inside its own isolated `GEMINI_HOME` directory
(`providers/antigravity/<account-id>/threads/<thread-id>`), created with
`0700` permissions and a marker file. The profile's `antigravity-acp`
directory is pre-seeded with `settings.json` containing
`{"auth":{"type":"gemini-api-key"}}`, so the server never falls back to
another auth method. No thread can see another thread's profile, and a
session ID from one account cannot be resumed under a different account.

## Environment allowlist / denylist

The child process environment is constructed explicitly, not inherited.
The server gets `GEMINI_HOME`, `AGY_ACP_FORCE_FILE_STORAGE=1`, the
`BROWSER` shim (below), `PYTHONUNBUFFERED=1`,
`ANTIGRAVITY_HARNESS_PATH`, a private `TMPDIR`/`TMP`/`TEMP`, and the
selected account's `GEMINI_API_KEY`. The removed-environment list strips
everything that could change the auth path, including `GOOGLE_API_KEY`,
`GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_PROJECT`,
`GOOGLE_GENAI_USE_VERTEXAI`, `AGY_ACP_ENABLE_OAUTH`, the `AGY_LLM_GATEWAY_*`
variables, and `GEMINI_HOME` itself, so a stray variable in the user's
shell cannot silently switch the server to a different credential.

## Browser suppression, by design

`BROWSER` points at a generated `browser-suppressed.sh` shim inside the
private profile. If the server ever tries to open a sign-in page, the shim
prints the marker `__COINCIDE_ANTIGRAVITY_SIGN_IN_REQUIRED__` to stderr
and exits 0 — the OAuth URL is never printed and no browser ever opens,
so no sign-in page is ever opened or followed.
Google sign-in is unavailable in this repo because there is no OAuth
infrastructure here, and because
third-party access to Antigravity has led Google to suspend accounts; see
the [Antigravity Terms of Service](https://antigravity.google/terms).
Agents protects the account by never attempting it.

## Runtime acquisition

There is no downloader. The user installs Google Antigravity, or supplies
the `agy_acp_server.par` binary plus its sibling `localharness_external`
helper, and pins them in Settings. Agents records the SHA-256 baseline of
the approved binary and re-checks it before launching turns. The helper
is resolved next to the binary at approval time.

## Disconnect and reconnect

Disconnect is deleting the key account in Settings (the Keychain item is
removed). Reconnect is picking another key account for the thread. There
is no sign-out flow because there is no session to sign out of.

## What "Verify Runtime" actually checks

The "Verify Runtime" button in Settings runs a local file check only:
the server binary is present, the companion helper is present, the
runtime is approved, and a key account with a stored key exists. It does
not contact Gemini, and its result must never be presented as verified
authentication. Authentication is verified only when a turn's
`authenticate` RPC succeeds against Gemini, or when the verification
probe below reports `authenticated` for the same approved runtime and
the same key account.

Settings › Antigravity shows the probe in a separate "Connection
Verification" section: the "Verify Connection" button runs the probe
(handshake only by default, or `authenticate` with the selected Gemini
API key account), and the section shows the last recorded probe —
handshake verified / authentication verified as two distinct rows, the
probe state and when it ran, which account's key the probe used, what
the server advertised, and the probe detail where it is meaningful.
Before any probe has run the section says "Not checked yet" and shows
neither flag as verified.

## Verification probe

`providers.check` with `{"provider": "antigravity", "probe": true}`
runs a real handshake against the approved runtime and records the
result in `rust-antigravity-probe.json`. The probe spawns the approved
`agy_acp_server.par` inside a fresh single-use private profile
(`providers/antigravity/probe/<uuid>`, `0700`, seeded
`settings.json` with `{"auth":{"type":"gemini-api-key"}}` and the
browser-suppression shim, exactly like a turn), sends ACP
`initialize`, and, depending on the mode, `authenticate` with
`methodId` `gemini-api-key`. The probe profile directory is deleted
when the probe finishes, whether it succeeds or fails. The probe
never writes a key anywhere: the key reaches the child process only
through its environment, and the recorded result contains no key
material, no raw frames, and no server output beyond a truncated
error message.

### Modes

- `handshake` (no `accountId`): `initialize` only, no key is
  presented to the server at all. Proves the runtime binary speaks
  ACP 1.x and offers `gemini-api-key` authentication. Proves
  nothing about any key.
- `authenticate` (`accountId` set): `initialize` +
  `authenticate` with the selected account's stored Gemini API key,
  read from Keychain through the same launch configuration a turn
  uses. Proves that key is accepted by Gemini through this runtime.
- `invalid-key` (`probeKey: "invalid"`): `initialize` +
  `authenticate` with the fixed placeholder key
  `coincide-probe-invalid-key`. The server is expected to reject it;
  this mode proves the probe can tell rejection apart from success,
  without risking a real key.

The probe refuses to execute a binary that is not approved, and
refuses to run with an unknown account or an account that has no
stored key. It has a 60-second deadline on the server handshake.

### States

The probe reports exactly one state, recorded with the mode, the
approved executable path, the account id and key revision (when a
key was used), the protocol version and auth methods the server
advertised, the server name/version when the server reports them,
the top-level keys of the `authenticate` result when one came back,
and a truncated detail string:

- `binaryMissing`: no approved runtime and no candidate binary was
  found. Nothing was spawned.
- `notApproved`: a candidate binary was found but is not approved.
  Nothing was spawned.
- `handshakeOk`: `initialize` succeeded (ACP protocol version 1,
  `gemini-api-key` offered). The runtime is real and reachable. No
  key was presented, so this never means the account is
  authenticated.
- `authenticated`: `authenticate` returned a result for the
  presented key. The key is accepted by Gemini through this runtime.
- `authRejected`: the server rejected `authenticate`, did not offer
  `gemini-api-key`, or asked for interactive sign-in (the browser
  shim was triggered). The error code is recorded in the separate
  `errorCode` field; `detail` carries only the server's error
  message, truncated to 500 characters, and is fixed text with no
  code when the server did not offer `gemini-api-key` or asked for
  interactive sign-in.
- `unreachable`: the runtime could not be launched, exited before
  answering, answered with invalid frames, or did not answer within
  60 seconds. The detail says which.

### What the status endpoint reports

`providers.antigravity.status` includes the last recorded probe and
two derived flags:

- `handshakeVerified` is true only when the last probe reported
  `handshakeOk` or `authenticated` for the executable that is
  currently approved. Approving a different binary clears it.
- `authenticationVerified` is true only when the last probe
  reported `authenticated` with a key, for the currently approved
  executable, and the probe's account id and key revision still
  match a key account that has a stored key. Deleting the account
  or saving a new key for it clears it. A successful turn does not
  set either flag; only a probe does.

The UI must keep the two states visually distinct: "Runtime
Handshake Verified" means the binary answered `initialize`; it is
not authentication. "Authenticated" means a probe with a key
succeeded. Before any probe has run, both flags are false.

### What the probe cannot prove

- It does not prove a turn will succeed: model availability,
  quota, and subscription eligibility are learned at session setup
  and during turns, not by the probe.
- It does not prove the key will stay valid: a key can be revoked
  after the probe runs, which is why the status flags go stale when
  the account or its key revision changes.
- It does not list models: real models are learned from the server
  at session setup, so the UI must not promise a model list before
  a turn exists.
- It does not contact Google sign-in in any form. OAuth stays
  disabled; the browser shim still suppresses any sign-in attempt.

### Probe status in this environment

The probe was implemented in this slice but **not executed here**:
no `agy_acp_server.par` binary exists anywhere on this machine
(a full filesystem search found none), and the slice does not
download runtimes, so every probe run here would report
`binaryMissing`. The probe code paths are covered by tests written
in this slice (fake ACP servers answering `initialize` and
`authenticate` over stdio), but those tests were not executed here
either. The Mac gate below is the first real execution.

### Mac gate: running the probe for real

1. On the Mac, install Google Antigravity (or pin a supplied
   `agy_acp_server.par` plus its sibling `localharness_external`
   helper) and approve the runtime in Settings › Antigravity.
2. Add a Gemini API key account in Settings › Antigravity.
3. Handshake first, with no key: call `checkProvider(provider:
   "antigravity", probe: true)` and confirm the result reports
   `handshakeOk`, `protocolVersion` 1, and `authMethods`
   containing `gemini-api-key`. Confirm Settings shows "Runtime
   Handshake Verified" and does NOT show "Authenticated".
4. Authenticate with the real key: call `checkProvider(provider:
   "antigravity", probe: true, accountID: <the account id>)` and
   confirm the result reports `authenticated` with `usedKey` true
   and the account id in the result. Confirm Settings shows
   "Authenticated".
5. Negative control: call `checkProvider(provider:
   "antigravity", probe: true, probeKey: "invalid")` and confirm
   the result reports `authRejected` with the server's rejection
   message. Confirm Settings no longer shows "Authenticated" if a
   previous `authenticated` result was recorded for a different
   probe (the invalid-key probe records its own result).
6. Run the Rust tests (`cargo test -p coincide-core
   antigravity`) and the Swift tests
   (`AntigravityProbeStatusTests`) and confirm they pass.
7. Start a real Antigravity turn and confirm it still works
   end to end; the probe must not change turn behavior.

## Models

Model discovery returns a single placeholder, `antigravity-default`.
Real models are learned from the server at session setup, so the UI must
not promise a model list before a turn exists.

## Not implemented

- Token refresh / expiry handling: there are no tokens, so there is
  nothing to refresh or expire.
- Quota display: the status endpoint lists `quota_display` under
  `remaining` work; no quota is shown anywhere.
- Model list before a turn: see "Models" above.
