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
  and `tool_call_id` values.

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
