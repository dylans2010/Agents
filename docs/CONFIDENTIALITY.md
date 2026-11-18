# Confidentiality: Output Validation and Redaction

## The gate

Most model output passes through one render-time gate before it reaches the
screen: `OutputRedactionGate` in `Agents/Core/OutputRedactionGate.swift`.
Transcript rows (including collapsed reasoning step titles), plan cards,
tool payload boxes, result views, file diff cards and inline patch hunks,
worker result peeks, run detail output (including approval items, approval
resolutions, and option labels), worker error banners, computer-use results,
and worker-result notifications all call the same `redact` / `redactedText`
entry points; there is no per-view copy of the logic. The gate replaces each
detected span with the neutral marker `[redacted]` and renders the rest of
the response. It never drops a whole response.

The one deliberate exclusion is `PendingAttentionView`, which renders
pending attention items (titles, details, option labels, and question
prompts) without redaction. The run-detail notice is not an exclusion: it is
composed only of the fixed section labels "Transcript", "Changes", and
"Git state", so it carries no model or engine content.

## Approval history cards

A resolved approval in the transcript shows a one-line human summary
instead of the raw request-params JSON: the provider's display title, the
approved command, or a human tool name, in that order. Raw identifiers
(`toolCallId`, `rawInput`, session and call IDs) are never selected for the
summary, so they cannot reach the card even though the full JSON stays in
the item for the live attention card, and the summary itself is run through
the gate. The resolution badge on a resolved card reads the outcome from
the stored approval object. While a request is still waiting, the history
card keeps the raw JSON block: the same pending request is shown by
`PendingAttentionView`, which is the operative surface until it is answered.

## What it detects

- Verbatim or near-verbatim fragments (case and whitespace differences
  tolerated) of System Asset documents, the composed system prompt, and the
  tool documentation carried in those assets. The shared gate is a lazy
  singleton, so bundled asset fragments load at first use, not at startup,
  and `SystemAssetManager` registers each composed system prompt with the
  gate when it is built.
- Fragment registration has a 48-character floor: a fragment shorter than
  48 characters is never registered, so a verbatim asset sentence shorter
  than 48 characters is not detected even when it appears word for word.
- Temporary credential and config paths: `CoincideComputerUse-*` paths,
  `computer-use.curl`, per-thread `GEMINI_HOME` sandboxes, and
  `agy_acp_server` / `localharness_external` runtime paths.
- Credential values: `GEMINI_API_KEY` assignments, Google `AIza` key
  shapes, and the Keychain service names used for provider accounts, remote
  tokens, and voice transcription, including their stored suffixes
  (namespace or scope): a stored name such as
  `com.apoorvdarshan.coincide.rust.provider-account.v1.codex` is redacted
  in full, suffix included.
- Internal identifiers in transport contexts: thread, run, worker, client,
  session, and assistant UUIDs that appear next to their transport label,
  and `tool_call_id` values. The camelCase `toolCallId` used in ACP
  permission params is not covered by these patterns, so the approval
  history card protects that field by never selecting it (see above)
  rather than by redaction.

## Over-redaction

The whole-token path and name patterns match wherever the token appears:
they do not require a value or path context. A bare prose mention such as
"Set GEMINI_HOME in Settings" or a `computer-use.curl`,
`agy_acp_server`, or `localharness_external` mention in plain text is
redacted to `[redacted]`, and any 24-or-more-character `AIza` token shape
is redacted even outside a credential assignment. This is deliberate
over-redaction in favor of never leaking the token; prose that names these
internal markers will read as redacted.

## Notifications

Worker-result notification text goes through the same gate via
`notificationExcerpt(for:)` before it reaches the lock screen. The task name
and outcome status survive; the excerpt is redacted, and when a result
contains nothing but internal content the notification carries no excerpt at
all. Notification scheduling (whether a notification fires) is unchanged.

## Render-time, not storage-time

Redaction happens only at render and notification time. Stored transcripts
and worker records keep the original text so the gate's behavior can be
audited and so a future, more accurate gate can re-evaluate the same
history. Copy actions copy the redacted text, not the original.

There is no diff or patch exemption: file diff cards, inline hunks, the
full-patch view, and Copy Patch are all gated. A copied patch is therefore
the redacted text, and if a redacted span fell inside added or removed
lines the copied patch may no longer apply cleanly.

## Limits

The gate is conservative and pattern-based. It cannot catch paraphrase: a
model that restates internal content in its own words will not be redacted.
It cannot catch internal content it has never seen: fragments are only
detected when they match registered asset or prompt text, and patterns only
cover the credential, path, and identifier shapes listed above. It is a
defense-in-depth layer, not perfect prevention. Anything the gate misses
still needs the model-side refusal behavior and the approval flow to hold.

Display-title genericization is heuristic, not exact:
`AssistantToolActivity.isRawToolIdentifier` treats any single
whitespace-free token with any lowercase letter anywhere and any uppercase
letter after the first character (among other raw-identifier shapes) as a
raw identifier, so a genuine human single-token title with that shape — a
brand-style token such as `iOS`, `macOS`, `GitHub`, `OpenAI`, or `McDonald`
— would be replaced by the generic "Tool activity" label. No current title
source (provider display title, approved command, human tool name)
produces such a token, so this is a known limitation, not an observed
leak; revisit only if a real human title of that shape is observed.

A residual raw channel sits outside the gate: the remote error envelope
serializes the whole `RemoteError`, code and message together
(`remote_protocol.rs:676-678`, `failure()`), and `dispatch_adapter_call`
returns the same whole-`RemoteError` payload in its own
`{"ok":false,"error":…}` envelope for every adapter handler
(`adapter_bridge.rs:35-46`), so a handler failure carries its message to
the phone unredacted. In `handle_pull_requests` an availability failure is
mapped to an unavailable list, but a failure of the list call itself
propagates with `?` instead of becoming unavailable, and
`PullRequestViews:72` renders `RemoteError.message` raw. This channel is
pre-existing; a future slice could sanitize at `dispatch_adapter_call`.
No fix is made here.

The Swift and Rust error sanitizers are not byte-identical. Rust
(`remote_text.rs`, `sanitize_display_text`) collapses whitespace before
applying its patterns (and again after), while Swift
(`ErrorSanitizer.sanitizeText`) applies its redactions first and collapses
whitespace last — the safe direction, since collapsing first can only make
patterns match more, not less. Rust also omits Swift's
`appendActionableHint`, so Rust-sanitized messages carry no "Check your
connection…" style hint.
