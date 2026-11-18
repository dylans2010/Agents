# Confidentiality: Output Validation and Redaction

## The gate

All model output passes through one render-time gate before it reaches the
screen: `OutputRedactionGate` in `Agents/Core/OutputRedactionGate.swift`.
Transcript rows, plan cards, tool payload boxes, result views, worker result
peeks, run detail output, computer-use results, and worker-result
notifications all call the same `redact` / `redactedText` entry points; there
is no per-view copy of the logic. The gate replaces each detected span with
the neutral marker `[redacted]` and renders the rest of the response. It
never drops a whole response.

## What it detects

- Verbatim or near-verbatim fragments (case and whitespace differences
  tolerated) of System Asset documents, the composed system prompt, and the
  tool documentation carried in those assets. The shared gate loads bundled
  asset fragments at startup, and `SystemAssetManager` registers each
  composed system prompt with the gate when it is built.
- Temporary credential and config paths: `CoincideComputerUse-*` paths,
  `computer-use.curl`, per-thread `GEMINI_HOME` sandboxes, and
  `agy_acp_server` / `localharness_external` runtime paths.
- Credential values: `GEMINI_API_KEY` assignments, Google `AIza` key
  shapes, and the Keychain service names used for provider accounts, remote
  tokens, and voice transcription.
- Internal identifiers in transport contexts: thread, run, worker, client,
  session, and assistant UUIDs that appear next to their transport label,
  and `tool_call_id` values.

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

## Limits

The gate is conservative and pattern-based. It cannot catch paraphrase: a
model that restates internal content in its own words will not be redacted.
It cannot catch internal content it has never seen: fragments are only
detected when they match registered asset or prompt text, and patterns only
cover the credential, path, and identifier shapes listed above. It is a
defense-in-depth layer, not perfect prevention. Anything the gate misses
still needs the model-side refusal behavior and the approval flow to hold.
