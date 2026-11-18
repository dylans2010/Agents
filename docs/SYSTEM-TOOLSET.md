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

## Enforcement boundary (read this before claiming more)

What is enforced for real in this slice:

- The system prompt is delivered as a genuine developer/system instruction
  for Codex and Claude, never as user text.
- `SystemToolRegistry` (Swift) registers exactly twenty-six tools, each mapped to a
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
  - Git, as engine methods that already existed and were verified in
    `git_actions_api.rs`: `git.actions.run` with `commit` (`git_commit`,
    message required) and `push` (`git_push`), `git.actions.pull`
    (`git_pull`), `git.branches.list` (`git_branch_list`),
    `git.branches.create` (`git_branch_create`), `git.branches.checkout`
    (`git_branch_checkout`). They run on the engine's git background workers
    and the registry polls `git.actions.result` for the outcome.
  No Qwen tool is imported: `AvailableTools.md` describes Qwen's tools, not this repo's.

## What is still NOT implemented (honest list)

The 300-ID catalog in `AvailableTools.md` is a specification, not a
registry. After slice 1, 26 tools are real. These catalog tools are NOT
implemented, and why:

- `use_mcp`: no MCP server exists anywhere in the repo. Providers send
  `mcpServers: []` (Claude is deliberately locked down). Slice 3 owns this.
- Memory (`mem_store`, `mem_retrieve`, `mem_clear`, `mem_context_snapshot`,
  `context_persistence_store`, `save_to_memory`, `view_memory`,
  `manage_memory`, `conversation_context_manager`): no memory API exists.
  The `documents`-table KV in the core store is the primitive a real one
  needs. Slice 4 owns this.
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
  OpenCode session-create calls this adapter makes. The system prompt
  instructs the model to use the system tools, but a model that ignores the
  instruction still runs its native tools.
- There is no MCP server yet. Fully routing model-initiated tool calls
  through `SystemToolRegistry` requires a coincide-owned MCP server mounted
  via ACP `mcpServers` / Claude `--mcp-config` (plus a per-provider tool
  allowlist), which is a core feature, not a slice change. The registry is
  the execution backend that mount will call.

## Providers

Per-thread system instructions are supported only for Codex and Claude,
because those are the only runtimes with a verified instruction channel
(`developerInstructions`, `--append-system-prompt`). OpenCode, Lithos, Grok,
Cursor, Antigravity, and registered ACP agents have no such channel in this
adapter (ACP `session/new` takes `cwd` and `mcpServers` only; OpenCode
session creation takes location, agent, permissions, and model).

A system prompt for an unsupported provider is an explicit error, never a
silent drop:

- At thread creation, when the resolved provider is unsupported and a
  non-empty system prompt was supplied.
- At every send, when the thread stores a system prompt and its provider is
  unsupported, or when the thread uses a named Codex profile (which cannot
  carry extra instructions).
- At send time, when a prompt arrives for a thread stored as Provider Tools.
- A system prompt combined with the Provider Tools toolset, an unknown
  toolset value, a prompt over 64 KiB, or a prompt containing NUL is rejected
  at validation.

Switching a thread's provider after creation (via thread settings) is
checked at the next send, not at the switch.
