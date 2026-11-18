# System Toolset

## The seam

A per-thread system prompt and toolset travel from the Mac UI to the provider
runtime without ever touching user project files (`AGENTS.md`, `CLAUDE.md`)
and without being prepended to user message text (it would leak into the
transcript).

- Swift: `RemoteSendRequest.systemPrompt` and
  `RemoteRequest.newThread(projectID:systemPrompt:toolset:)` in
  `CoincideRemoteKit`. Both fields are optional; older peers omit them and
  decode to `nil`, so the wire format is backward compatible.
- FFI: `AgentsRuntimeClient.newThread(projectID:systemPrompt:toolset:)` and
  the existing `send(_:)` path forward the fields through
  `coincide_macos_adapter_call`.
- Rust: `remote_protocol::SendRequest.system_prompt` and
  `Request::NewThread { project_id, system_prompt, toolset }`.
  `remote_adapter::Adapter::new_thread` stores both on the thread document
  (via `threads.create`, or `threads.patch` when an untouched empty thread is
  reused). `Adapter::send` binds a send-carried prompt onto a thread that has
  none stored yet. `Adapter::summary` surfaces the stored toolset, and
  `RemoteThreadSummary.toolset` carries it back to Swift.
- Delivery: `Engine::system_instructions` in `bot_engine.rs` reads the stored
  prompt at every send and passes it as the session `instructions`, riding the
  same channel bot instructions already use: Codex `thread/start` /
  `thread/resume` `developerInstructions`, Claude `--append-system-prompt`.
  The prompt is resolved from the thread document, so it survives resume,
  steering, and queued turns. Forks copy the whole thread document, so a fork
  keeps the parent's toolset and prompt.
- MCP delivery: for MCP-capable providers the stored prompt is NOT injected
  as instructions. Instead the launch carries an `McpMount` (thread id and
  data directory) and the provider session is mounted with the
  `coincide-mcp-server` stdio server, which serves the 33 system tools plus
  the SystemAssets as resources and the stored prompt as a `prompts/get`
  prompt. See "The MCP server" below.

## The two toolsets

System Tools (default) and Provider Tools. The selection is persisted in
`UserDefaults` under `coincide.agentToolset` and shown in Settings › General ›
Agent Tools. There is no matching core setting (the core `changeSetting`
allowlist has no toolset key), so the setting is intentionally Swift-side.

- New threads are created with the currently selected toolset and, in System
  Tools mode, with the system prompt built for the current selection
  (`AppModel.systemPromptForSelectedThread`).
- Existing threads keep the toolset they were created with: the stored value
  on the thread document wins over the global selection. Threads created
  before toolsets existed have no stored value and behave as Provider Tools.
- In Provider Tools mode no system prompt is created, sent, or stored, and
  `SystemToolRegistry.tools(for: .provider)` is empty.

## The MCP server

`Rust Backend/crates/coincide-mcp-server/` is a standalone stdio binary
(`coincide-mcp-server`) that serves the System Tools to provider CLIs over
the MCP protocol. It is built by the Xcode preBuildScript and bundled inside
`Agents.app/Contents/MacOS/` next to the app binary, which is how
`coincide_core::mcp::server_binary_path()` resolves it (sibling of the
running executable, overridable with `COINCIDE_MCP_SERVER`).

### Protocol surface

JSON-RPC 2.0 over stdio, one JSON object per line, newline-delimited
responses. Protocol version `2025-03-26`.

- `initialize` — returns the protocol version, capabilities
  (`tools`, `resources`, `prompts`), and server info
  `coincide-mcp-server`.
- `ping` — returns `{}`.
- `tools/list` — the real 26-tool registry, with the same names, descriptions,
  input schemas, and parameters as the Swift `SystemToolRegistry`. A
  cross-check test in the server crate parses the Swift registry source and
  asserts the two tables match exactly.
- `tools/call` — executes a real tool and returns its real result as text
  content, or `isError: true` content on a real execution failure. An
  unknown tool name is JSON-RPC error `-32602`; a malformed request is
  `-32700`; an unknown method is `-32601`.
- `resources/list` / `resources/read` — the 33 bundled SystemAssets as
  `agents-asset://<fileName>` resources (`text/markdown`), read from disk.
  The assets directory resolves from `--assets-dir`, then
  `$COINCIDE_SYSTEM_ASSETS_DIR`, then the app bundle
  `../Resources/SystemAssets`, then a walk up to
  `Agents/Resources/SystemAssets`.
- `prompts/list` / `prompts/get` — one prompt, `agents-system-prompt`: the
  composed system prompt stored on the thread document, read back through
  the engine control socket (`threads.read`). If no prompt is stored for the
  thread, `prompts/get` returns an honest `-32602` error, never a canned
  prompt.
- `notifications/initialized` — accepted, no response. Stdin EOF exits
  cleanly with code 0.

### Dispatch

Desktop-channel tools (file read/write/edit/delete/move/copy, search literal
and regex, directory listing/creation) call the same core functions the FFI
uses (`coincide_core::workspace_tools`, moved there from the FFI so both
callers share one implementation). Engine-channel tools (terminal, git,
build/test) go over the control socket
(`<data_dir>/control.sock`) to the LIVE engine — no second Engine, no
shared-store hazard — replicating the Swift registry's polling loops
(`workspace.result` for git status/diff, `git.actions.result` for git
actions, the `__AGENTS_TOOL_DONE__:$?` sentinel for build/test). A tool call
with no engine reachable returns a real error, never a fake success.

The server is spawned with `--cwd <thread workspace>`, `--thread-id <id>`,
`--socket <control socket path>`, and `--assets-dir <dir>`. Calls that omit
`cwd`/`threadId` default to the session values.

### Mount rule

A launch mounts the server only when the thread's toolset is `system` AND
the provider is MCP-capable (`coincide_core::mcp::is_mcp_capable_provider`:
every provider except `codex`, `opencode`, `lithos`). The toolset gate
(`ensure_system_toolset_supported`) now rejects only `opencode` and `lithos`
for System Tools; MCP-capable providers may store the prompt (delivered via
`prompts/get`, never injected as instructions). If the server binary is
missing at launch, the mount is skipped silently and the session runs as it
did before this slice.

## Enforcement boundary (read this before claiming more)

What is enforced for real in this slice:

- The system prompt is delivered as a genuine developer/system instruction
  for Codex and Claude, never as user text.
- `SystemToolRegistry` (Swift) registers exactly thirty-three tools, each mapped to a
  real core action that was verified against the FFI dispatch:
  `workspace.read_file`, `workspace.write_file`, `workspace.files`,
  `workspace.search` (synchronous desktop actions) and `terminal.create`,
  `terminal.write`, `terminal.read`, `git.status`, `git.diff` (engine RPC;
  the git actions run through the async workspace-operation channel and the
  registry polls `workspace.result` for the outcome). Slice 1 added
  seventeen more, all real:
  - File mutation, as new `desktop_call` actions on real filesystem calls
    with the same canonical-root containment as `workspace.write_file`:
    `workspace.delete_file` (`delete_file`), `workspace.delete_directory`
    (`delete_directory`), `workspace.move_file` (`move_file`, also renames),
    `workspace.copy_file` (`copy_file`), `workspace.create_dir`
    (`create_directory`), `workspace.read_dir` (`read_directory`, a real
    `read_dir`, including files git ignores; recursive tree to 16 levels).
    Move and copy refuse an existing destination; delete refuses symlinks;
    non-empty directory delete needs `recursive: true`.
  - Targeted edits, as `workspace.edit_file` (`edit_file`,
    `multi_edit_file`): read, anchored exact-match replacement, write back
    through the same regular-file writer as `workspace.write_file`, then
    re-read to verify byte equality. An anchor matching zero times or two or
    more times is a loud error, never a fuzzy guess. Modes are `replace`,
    `insertAfter`, `insertBefore`.
  - Regex search, as `workspace.search_regex` (`search_regex`): the core's
    real search path, ripgrep in regex mode when installed, otherwise a real
    scan with the `regex` crate over the same walker the literal search uses.
    An invalid pattern is an error, never an empty result.
  - Build and test, as `run_build` / `run_tests`: no canned output. Each
    creates a real integrated terminal for the thread, sends the caller's
    command, polls `terminal.read` until a sentinel echo reports the real
    exit code, and returns the real output with that exit code. The output is
    the final terminal viewport (the tail), not full scrollback, and a
    command that never finishes reports `timedOut: true` instead of a fake
    success.
  - Memory, as engine methods `memory.store` / `memory.retrieve` /
    `memory.list` / `memory.delete` / `memory.clear` / `memory.snapshot` /
    `memory.context_store` (`mem_store`, `mem_retrieve`, `view_memory`,
    `mem_delete`, `mem_clear`, `mem_context_snapshot`,
    `context_persistence_store`). Slice 3 added seven, all real:
    - Store design: one document in the existing SQLite `documents` table,
      `memory.json` (`coincide-core/src/memory_store.rs`), holding
      `{"version": 1, "entries": {<composite key>: {key, scope, value,
      updatedAt}}}` where the composite key is the scope, a unit-separator
      character, and the key. It is the same table and the same
      `Store::save_document` / `Store::document` calls the rest of the
      engine already uses, so entries survive restarts; the Rust and Swift
      round-trip tests reopen the store and read the entry back.
    - Scopes: `global`, or `workspace:<identifier>` where the identifier is
      normally the absolute project path. The same key in two scopes is two
      different entries. A list with no scope returns entries from all
      scopes; the other operations default to `global`.
    - Key semantics: keys are trimmed, non-empty, at most 256 characters, no
      control characters. Values are at most 64 KiB, no NUL bytes. Storing
      an existing key is an explicit upsert and the result reports
      `overwritten: true`; there is no silent-merge or append mode.
    - Retrieval is keyword only: `view_memory` filters by a
      case-insensitive substring over keys and values, and
      `mem_context_snapshot` retrieves the same way. There are no embeddings
      anywhere in the repo, so there is no semantic similarity search.
    - `mem_retrieve` of a missing key is an error, per the catalog.
      `context_persistence_store` keeps the catalog's opposite rule: get
      (or delete) of a missing key succeeds, get returning `value: ""` with
      `found: false`. An unknown `action` is an error here, not a silent
      fall-through to `get` as the catalog describes.
    - `mem_clear` gating: clear takes a scope and requires `confirm: true`.
      Without the scope, or with `confirm` missing or false, the clear is
      refused before anything is deleted, in both the Swift registry and the
      MCP server. It deletes only that scope and reports how many entries
      were removed. There is no bare clear-all.
    - `mem_context_snapshot` mints a new `snapshot:<uuid>` key on every call
      (not idempotent) and stores the snapshot as an ordinary memory entry
      whose value is a JSON summary (snapshot id, scope, query, matched
      keys, timestamp) alongside the matched entries in the result. It does
      NOT capture environment or open files, per the catalog's own
      correction; it captures stored memories relevant to the query.
    - `context_persistence_store` is backed by the same SQLite memory
      store, NOT by `<workspaceRoot>/.assist_context_store.json`: the
      catalog's file would pollute the user's repository, so the file path
      is deliberately not implemented.
    - Settings › Memory lists entries with their scope, searches keys and
      values, deletes per entry, and clears a scope only after an explicit
      confirmation toggle. Everything reads the real store through the FFI
      `memory.*` actions.
  No Qwen tool is imported: `AvailableTools.md` describes Qwen's tools, not this repo's.

## What is still NOT implemented (honest list)

The 300-ID catalog in `AvailableTools.md` is a specification, not a
registry. After slice 3, 33 tools are real. These catalog tools are NOT
implemented, and why:

- Memory (`save_to_memory`, `manage_memory`, `conversation_context_manager`):
  not registered as separate tools. `save_to_memory` and `manage_memory`
  describe writing to a `UserMemory.md` file, which does not exist in this
  repo; their real function is covered by `mem_store`, `mem_delete`, and
  `mem_clear` against the SQLite memory store. `conversation_context_manager`
  describes a per-conversation context file; no such file backend exists,
  so it is unavailable. `mem_store`, `mem_retrieve`, `mem_clear`,
  `mem_context_snapshot`, `context_persistence_store`, and `view_memory`
  are real — see the Enforcement boundary above.
- Workers (`use_workers`, `start_subagent`) and plans
  (`intel_plan_task`, `intel_breakdown_task`, `execution_plan`): no
  worker-spawn or plan-store API exists. Slice 5 owns this.
- Computer use (`use_app`, `take_screenshot`): the core broker and typed
  tool catalog exist, but no native executor is wired into the Swift app's
  FFI. `take_screenrecord` needs a whole new ScreenCaptureKit recorder.
  Slice 7 owns this.
- Artboards ×8, `use_extension`, `reverse_analyze`, `use_composio`,
  `search_skills`, `report_to_user`: whole subsystems or external services
  that do not exist in this repo. Out of scope for the 10-hour program.
- LLM tools (`intel_autofix`, `intel_generate_tests`, `intel_explain_code`,
  `code_review`, `task_runner`): there is no LLM client in the core. Out of
  scope.
- `project_mutation_controller`, `project_target_add`, `test_target_add`:
  no pbxproj writer exists anywhere; `file_write` does not register files
  in Xcode projects. This is the riskiest missing primitive; it is not
  faked here.
- Git gaps: `git_stash_operator`, rollback/reset-hard, `git_log_viewer`,
  `git_blame_inspector`, `git_branch_compare`, `git_bisect`,
  `git_cherry_pick` have no engine method. Slice 6 owns the git follow-ups.
- Everything else in the catalog (~240 IDs) stays PARTIAL: reachable in
  principle via the real terminal RPC or read/write/search composition, but
  not tool-shaped, and not claimed as implemented. In particular the
  heuristic "intelligence" tools (`complexity_analysis`,
  `autonomous_review_engine`, `semantic_query_engine`, `code_summary`,
  `code_lint`, `runtime_diagnostics_engine`) are keyword/substring scans
  by the catalog's own admission, not the analysis their names promise.
- In Provider Tools mode the registry is empty and executing any system tool
  throws `SystemToolError.toolNotActive` before any runtime call.

What is NOT enforced yet, and is not claimed:

- Provider-native tools cannot be disabled from this slice. The provider
  processes (Claude CLI, Codex app-server, OpenCode server, ACP servers)
  advertise and execute their own tools; coincide-core maps their tool-call
  frames into the transcript but does not mediate execution, and there is no
  tool allowlist parameter in the `session/new`, Codex `thread/start`, or
  OpenCode session-create calls this adapter makes. The system prompt (or,
  for MCP providers, the MCP tool descriptions and the stored prompt served
  by `prompts/get`) instructs the model to use the system tools, but a model
  that ignores the instruction still runs its native tools.

## Providers

| Provider | System Tools mechanism | SystemAssets mechanism | Channel / limitation |
| --- | --- | --- | --- |
| Codex | System prompt only; Codex's own tools execute | Prompt carries the composed assets (injected as `developerInstructions`) | Verified channel: `thread/start` / `thread/resume` `developerInstructions`. No MCP: the adapter has no verified in-handshake or config channel, and named Codex profiles explicitly forbid `config.toml` overrides. Users may add the server manually to their Codex config: `[mcp_servers.coincide]` with `command = "<path to coincide-mcp-server>"`, `args = ["--cwd", "<workspace>"]`. |
| Claude | System prompt + MCP server mounted via `--mcp-config` | Prompt injected via `--append-system-prompt`; assets also available as MCP resources/prompts | Verified channels. The server is mounted WITHOUT `--strict-mcp-config`, so the user's own MCP servers from `.mcp.json` keep loading. The per-thread config file is `<data_dir>/mcp/claude-<thread_id>.json` (0600). |
| Cursor | MCP server mounted via `mcpServers` on `session/new` | MCP resources (`agents-asset://`) + `prompts/get` | Verified channel. Cursor profile MCP servers come from the per-thread profile file, not the wire, so the mount does not clobber them. No instruction channel: the stored prompt is served by `prompts/get`, never injected. |
| Grok Build | MCP server mounted via `mcpServers` on `session/new` | MCP resources + `prompts/get` | Verified channel (same ACP `session/new` path as Cursor). No instruction channel. |
| Antigravity | MCP server mounted via `mcpServers` on `session/new` | MCP resources + `prompts/get` | Verified channel (ACP `session/new`). No instruction channel. |
| ACP registry agents | MCP server mounted via `mcpServers` on `session/new` | MCP resources + `prompts/get` | Verified channel (`session/new` in `run_flavored`). The model-catalog discovery probe still sends `mcpServers: []` deliberately. No instruction channel. |
| OpenCode | None | None | No channel: the adapter starts `opencode serve` with no config passed and there is no verified in-adapter channel. MCP servers come only from the user's own OpenCode config. System Tools is rejected for OpenCode at thread creation and send. |
| Lithos | None | None | No channel: no verified in-adapter MCP or instruction channel. System Tools is rejected for Lithos at thread creation and send. |

Per-thread system instructions are supported only for Codex and Claude,
because those are the only runtimes with a verified instruction channel
(`developerInstructions`, `--append-system-prompt`). OpenCode, Lithos, Grok,
Cursor, Antigravity, and registered ACP agents have no such channel in this
adapter (ACP `session/new` takes `cwd` and `mcpServers` only; OpenCode
session creation takes location, agent, permissions, and model). For those
providers the MCP server's tools and resources are the mechanism, and the
model must be instructed via the tool descriptions and the server-provided
prompt to use them — injection is never claimed where it did not happen.

A system prompt for an unsupported provider is an explicit error, never a
silent drop:

- At thread creation, when the resolved provider is OpenCode or Lithos and a
  non-empty system prompt was supplied.
- At every send, when the thread stores a system prompt and its provider is
  OpenCode or Lithos, or when the thread uses a named Codex profile (which
  cannot carry extra instructions).
- At send time, when a prompt arrives for a thread stored as Provider Tools.
- A system prompt combined with the Provider Tools toolset, an unknown
  toolset value, a prompt over 64 KiB, or a prompt containing NUL is rejected
  at validation.

Switching a thread's provider after creation (via thread settings) is
checked at the next send, not at the switch.
