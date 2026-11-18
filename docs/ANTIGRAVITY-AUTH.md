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
authentication. The status endpoint reports `authenticationVerified:
false` for exactly this reason. Authentication is verified only when a
turn's `authenticate` RPC succeeds against Gemini.

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
- A real verification probe that contacts Gemini: a later slice adds it.
  Until then, the settings banner states exactly what was checked.
