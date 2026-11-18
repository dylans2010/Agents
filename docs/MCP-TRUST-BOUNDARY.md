# MCP trust boundary

Assessment by slice S-MCP1, 2026-11-18, against remote main `1926f3a5`.
Verdict: there is no safe gating for `resources/read` or `prompts/get` that
does not break the runtime, so the server is intentionally unchanged
(option (c) in the slice brief). This note is the record of that finding.
The behavior it pins down is covered by the `trust_boundary_*` tests in
`Rust Backend/crates/coincide-mcp-server/tests/mcp_server.rs`.

## Transport: stdio only, no network

`coincide-mcp-server` reads newline-delimited JSON-RPC 2.0 from stdin and
writes responses to stdout (`Rust Backend/crates/coincide-mcp-server/src/main.rs:151-158`,
`run()` loop). The crate contains no TCP, UDP, HTTP, or socket listener of
any kind, so the server is reachable only by a process that holds its stdin
and stdout pipes. There is no authentication step in the protocol
(`protocol.rs` dispatches on the `method` string only) and no caller
identity is available on a stdio pipe.

## Who spawns it, and who the client is

The app never speaks MCP to this server. No production Swift or Rust code
in the app calls `resources/read` or `prompts/get` (the only callers are
the tests in
`Rust Backend/crates/coincide-mcp-server/tests/mcp_server.rs`); the app
reads the SystemAssets directly from disk and the stored prompt directly
from the thread document.
The only clients are the external provider agent processes:

- A launch mounts the server only when the thread toolset is `system` and
  the provider is MCP-capable (`Rust Backend/crates/coincide-core/src/mcp.rs:45-56`,
  `mount_for`; `mcp.rs:18`, `is_mcp_capable_provider` excludes `codex`,
  `opencode`, `lithos`).
- `mcp.rs:58-76` (`server_command_and_args`) builds the command:
  the server binary plus `--cwd`, `--thread-id`, and `--socket
  <data_dir>/control.sock`. `server_command_and_args` has exactly two
  callers: `session_servers` (`mcp.rs:93-97`) and `claude_config_path`
  (`mcp.rs:99-130`). The file-write code inside `claude_config_path` is
  `mcp.rs:111-130`; what follows it (line 132 onward) is the `#[cfg(test)]`
  test module, not production code.
- The command and args are handed to the provider agent process, which
  spawns the server itself and owns its pipes: ACP `session/new`
  `mcpServers` for Cursor (`provider_cursor.rs:307`), Grok Build and
  Antigravity via the same ACP path (`provider_acp.rs:640`,
  `provider_antigravity.rs:385`), and Claude via a per-thread config file
  `<data_dir>/mcp/claude-<thread_id>.json` written as a private file
  (`mcp.rs:111-130`, `--mcp-config` plus `--strict-mcp-config` in
  `provider_claude.rs:414-419`).

## What is served

- `resources/read` returns the full text of a bundled SystemAsset
  (`protocol.rs:136-142` into `assets.rs:109-133`, `read_asset`).
- `prompts/get` returns the full stored system prompt for the bound thread,
  read back through the engine control socket (`protocol.rs:144-166` into
  `assets.rs:134-159`, `stored_system_prompt`, via `threads.read`).
  `prompts/list` advertises it with the instruction to read it before using
  the system tools (`protocol.rs:56-62`).
- `resources/list` returns only URI, name, and MIME type per asset, and
  `prompts/list` only the prompt name, description, and arguments
  (`assets.rs:70-82`, `list_json`; `protocol.rs:56-62`). Neither list
  carries content, and the asset filenames are already visible to anyone
  who can read the app bundle, so listing is not a leak and is unchanged.

## Why gating to the app's own client is impossible (option (a))

There is no in-process or app-owned MCP client to gate to. The client is
the provider agent process, which spawns the server and holds the pipes.
A stdio pipe carries no peer identity, so the server cannot tell the
provider agent apart from any other local process that spawns the same
binary with its own pipes. Checking the parent process does not fix this,
and the reasons are specific, not general: the provider agent processes
that legitimately spawn the server are themselves arbitrary ACP agent
binaries, so a parent allowlist would have to admit whatever agent binary
the provider runs; agents commonly run under shared interpreters, so the
observable parent is a generic interpreter rather than the agent; the
server's own argv carries no expected-parent identity to check against
(`--cwd`, `--thread-id`, and `--socket` only, `mcp.rs:58-76`); and a
parent check would bound nothing the attacker does not already have, since
any local code can already read the assets from the app bundle and call
`threads.read` on the unauthenticated control socket (see "Residual risk"
below). A shared-secret
token is not an option either: the codebase has no such scheme, the token
would have to travel in the command line the provider uses to spawn the
server (visible to the same user via process listing), and the MCP protocol
has no auth handshake to carry it.

## Why serving metadata only breaks the runtime (option (b))

For Cursor, Grok Build, Antigravity, and ACP registry agents, `prompts/get`
is the only channel by which the stored system prompt reaches the model:
it is not injected as instructions on those paths
(`docs/SYSTEM-TOOLSET.md:31-40`, provider table rows for Cursor, Grok
Build, Antigravity, and ACP registry agents). `resources/read` is how those
same models read the full text of the Safeguards, Identity, and
tool-routing guidance on demand. That guidance is not carried in full by
the stored prompt: the stored prompt inlines only the condensed baseline
covering identity and safeguards (the baseline text is appended into the
composed prompt parts in `SystemPromptBuilder.swift:87`), and no asset
or prompt text instructs the model to use `resources/read` — the
read-before-using instruction lives in the server's `prompts/list`
description (`protocol.rs:56-62`). `resources/read` therefore serves full
on-demand text beyond what the token-budgeted prompt can carry. Serving
metadata or summaries instead of
full text would leave the model without the instructions the System Tools
design depends on: sessions would run tools unguided, or fail the
read-before-using contract the prompt states. The stored prompt is
user- and assistant-composed instruction text, not a field with a
redactable secret in it, so there is also no content filter that could
separate something sensitive from something the model must read.

## Already enforced (defense in depth that exists today)

- `resources/read` serves only `.md` files that `resources/list` reports
  from the resolved assets directory: traversal (`..`, `/`, `\`, NUL) is
  rejected, the resolved file must stay under the canonical assets
  directory, symlinked asset files are excluded from listing and unreadable,
  and assets over 16 MiB are refused
  (`assets.rs:84-107`, `read_asset_text`; `assets.rs:109-133`, `read_asset`;
  tests `resources_serve_real_asset_files`,
  `resources_ignore_symlinked_asset_files`,
  `resources_read_rejects_an_asset_over_the_size_limit`).
- The server is bound to one thread (`--thread-id`) and one control socket
  (`--socket`), and a session cannot start without the server binary
  (`mcp.rs:93-97` errors instead of starting tool-less).
- The Claude per-thread config file is created private (0600)
  (`mcp.rs:125`).
- Tool execution (`tools/call`) is a separate path with its own deny
  enforcement and is untouched by this assessment.

## Residual risk and the trust boundary

Any code executing as the same local user can spawn the binary with any
`--thread-id` and `--socket` and read the full text of every bundled
SystemAsset plus any thread's stored system prompt. That is the whole
residual risk, and it is bounded by the user account: the same local code
can already read the assets directly from the app bundle
(`Agents.app/Contents/Resources/SystemAssets/`) and can already call
`threads.read` on the engine control socket, which is an unauthenticated
Unix socket (`Rust Backend/crates/coincide-core/src/control.rs:311-320`,
`connect_stream` / `request` use a plain `UnixStream::connect` with no
credential check). The MCP server therefore widens no boundary beyond what
local code running as the user already has; the trust boundary is the local
user account and the process boundary around the provider agent processes,
which already receive the workspace and run tools. Gating further would
require either breaking the provider delivery channel above or inventing
an authentication scheme for a local stdio pipe, neither of which is
available without breaking the runtime.

## What would break if gated further

- Refusing `resources/read` / `prompts/get` to anyone but a privileged
  caller: impossible to distinguish callers on stdio, so this refuses the
  provider agents too and System Tools sessions lose their instructions.
- Serving summaries instead of full text: the model loses the safeguards,
  identity, and tool-routing guidance, and the stored prompt never arrives
  on the Cursor / Grok Build / Antigravity / ACP paths.
- Removing the `resources` / `prompts` capabilities from `initialize`:
  compliant MCP clients would stop offering the read calls the design
  relies on, with the same effect as refusing them.
