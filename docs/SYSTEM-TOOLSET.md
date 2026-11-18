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
- MCP delivery: for MCP-capable providers the launch carries an `McpMount`
  (thread id and data directory) and the provider session is mounted with the
  `coincide-mcp-server` stdio server, which serves the 332 system tools plus
  the SystemAssets as resources and the stored prompt as a `prompts/get`
  prompt. Claude is the exception: it gets the mount AND the stored prompt
  injected via `--append-system-prompt`. For the other MCP-capable providers
  (Cursor, Grok Build, Antigravity, ACP registry agents) the stored prompt
  is NOT injected as instructions — it reaches the model only via
  `prompts/get`. See "The MCP server" below.

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

## The 332-tool registry

Every tool in `Agents/Core/SystemTools/SystemToolRegistry.swift`, verified row by row against the MCP server table in `Rust Backend/crates/coincide-mcp-server/src/tools.rs` (same names, actions, and channels, in the same order). 332 tools, 63 distinct actions: several tools share one action (`workspace.read_file` x59, `terminal.create` x60, `workspace.write_file` x47, `workspace.search_regex` x37, `computer_use.request` x22, `workspace.read_dir` x15, `workspace.files` x7, `workspace.edit_file` x4, `workspace.move_file` x4, `workspace.search` x3, `git.log` x3, `workspace.delete_file` x3, `workspace.copy_file` x3, `memory.store` x3, `web.fetch` x4, `git.diff` x2, `git.diff.range` x2, `workspace.delete_directory` x2, `workspace.create_dir` x2, `git.actions.run` x2, `git.branches.list` x2, `memory.snapshot` x2, `workers.spawn` x2, `git.checkpoints.restore` x2, `system.info` x2, plus 38 single-tool actions).

Production tool execution is the Rust MCP server, not the Swift registry: `tools/call` in `Rust Backend/crates/coincide-mcp-server/src/tools.rs` dispatches the 332 `DEFINITIONS` entries either to `coincide_core::workspace_tools` directly or via `engine_request` over the engine control socket (`<data_dir>/control.sock`). The Swift `SystemToolRegistry` is the canonical schema mirror (definitions, the Rust cross-check test, the UI display filter); its `execute()` is exercised by tests, not by the production turn path. The `Real backend` column below describes each action's backend on either side of that mirror.

| Tool | Action | Channel | Real backend |
| --- | --- | --- | --- |
| `read_file` | `workspace.read_file` | desktop | FFI `workspace.read_file` arm -> `coincide_core::workspace_tools::read_file` |
| `write_file` | `workspace.write_file` | desktop | FFI `workspace.write_file` arm -> `coincide_core::workspace_tools::write_file` |
| `list_files` | `workspace.files` | desktop | FFI `workspace.files` arm -> `coincide_core::workspace_tools::files` |
| `search_files` | `workspace.search` | desktop | FFI `workspace.search` arm -> `coincide_core::workspace_tools::search` |
| `create_terminal` | `terminal.create` | engine | Engine RPC `terminal.create` on the live engine |
| `write_terminal` | `terminal.write` | engine | Engine RPC `terminal.write` on the live engine; sends the caller's arbitrary text, including newlines and control bytes, straight into the live shell's stdin with no confirmation step, so a provider agent holding a terminal ID can run any shell command in that terminal. Unlike the destructive tools, this is not confirm-gated: the grant is holding the terminal, not a per-write approval. Input is capped at 32 KiB per write by the engine (`Terminal::write`); larger writes are refused, not truncated. |
| `read_terminal` | `terminal.read` | engine | Engine RPC `terminal.read` on the live engine |
| `git_status` | `git.status` | engine | Engine `git.status`, async workspace channel polled via `workspace.result` |
| `git_diff` | `git.diff` | engine | Engine `git.diff`, async workspace channel polled via `workspace.result` |
| `git_log` | `git.log` | engine | Engine `git.log`, async workspace channel polled via `workspace.result` |
| `git_show` | `git.show` | engine | Engine `git.show`, async workspace channel polled via `workspace.result` |
| `git_diff_range` | `git.diff.range` | engine | Engine `git.diff.range`, async workspace channel polled via `workspace.result` |
| `git_diff_branch` | `git.diff.branch` | engine | Engine `git.diff.branch`, async workspace channel polled via `workspace.result` |
| `delete_file` | `workspace.delete_file` | desktop | FFI `workspace.delete_file` arm -> `coincide_core::workspace_tools::delete_file` |
| `delete_directory` | `workspace.delete_directory` | desktop | FFI `workspace.delete_directory` arm -> `coincide_core::workspace_tools::delete_directory` |
| `move_file` | `workspace.move_file` | desktop | FFI `workspace.move_file` arm -> `coincide_core::workspace_tools::move_file` |
| `copy_file` | `workspace.copy_file` | desktop | FFI `workspace.copy_file` arm -> `coincide_core::workspace_tools::copy_file` |
| `create_directory` | `workspace.create_dir` | desktop | FFI `workspace.create_dir` arm -> `coincide_core::workspace_tools::create_dir` |
| `read_directory` | `workspace.read_dir` | desktop | FFI `workspace.read_dir` arm -> `coincide_core::workspace_tools::read_dir` |
| `edit_file` | `workspace.edit_file` | desktop | FFI `workspace.edit_file` arm -> `coincide_core::workspace_tools::edit_file` |
| `multi_edit_file` | `workspace.edit_file` | desktop | FFI `workspace.edit_file` arm -> `coincide_core::workspace_tools::edit_file` |
| `search_regex` | `workspace.search_regex` | desktop | FFI `workspace.search_regex` arm -> `coincide_core::workspace_tools::search_regex` |
| `run_build` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `run_tests` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `git_commit` | `git.actions.run` | engine | Engine `git.actions.run` (`action: commit`), polled via `git.actions.result` |
| `git_push` | `git.actions.run` | engine | Engine `git.actions.run` (`action: push`), polled via `git.actions.result` |
| `git_pull` | `git.actions.pull` | engine | Engine `git.actions.pull` (no extra params), polled via `git.actions.result` |
| `git_branch_list` | `git.branches.list` | engine | Engine `git.branches.list` (optional `scope`), polled via `git.actions.result` |
| `git_branch_create` | `git.branches.create` | engine | Engine `git.branches.create` (`name`), polled via `git.actions.result` |
| `git_branch_checkout` | `git.branches.checkout` | engine | Engine `git.branches.checkout` (`name`), polled via `git.actions.result` |
| `mem_store` | `memory.store` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::store_entry` (SQLite `memory_entries`) |
| `mem_retrieve` | `memory.retrieve` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::retrieve_entry` (SQLite `memory_entries`) |
| `view_memory` | `memory.list` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::list_entries` (SQLite `memory_entries`) |
| `mem_delete` | `memory.delete` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::delete_entry` (SQLite `memory_entries`) |
| `mem_clear` | `memory.clear` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::clear_scope` (SQLite `memory_entries`) |
| `mem_context_snapshot` | `memory.snapshot` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::snapshot_context` (SQLite `memory_entries`) |
| `context_persistence_store` | `memory.context_store` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::context_store` (SQLite `memory_entries`) |
| `use_workers` | `workers.spawn` | desktop | FFI `workers.*` arm -> `Engine::workers_spawn` (record in SQLite `worker_records`) |
| `list_workers` | `workers.list` | desktop | FFI `workers.*` arm -> `Engine::workers_list` (record in SQLite `worker_records`) |
| `worker_status` | `workers.status` | desktop | FFI `workers.*` arm -> `Engine::workers_status` (record in SQLite `worker_records`) |
| `worker_result` | `workers.result` | desktop | FFI `workers.*` arm -> `Engine::workers_result` (record in SQLite `worker_records`) |
| `cancel_worker` | `workers.cancel` | desktop | FFI `workers.*` arm -> `Engine::workers_cancel` (record in SQLite `worker_records`) |
| `intel_plan_task` | `workers.plan` | desktop | FFI `workers.*` arm -> `Engine::workers_plan` (plan in SQLite `worker_plans`) |
| `intel_breakdown_task` | `workers.breakdown` | desktop | FFI `workers.*` arm -> `Engine::workers_breakdown` (plan in SQLite `worker_plans`) |
| `execution_plan` | `workers.execution_plan` | desktop | FFI `workers.*` arm -> `Engine::workers_execution_plan` (plan in SQLite `worker_plans`) |
| `list_apps` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `list_windows` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `get_window_state` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `get_desktop_state` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `verify_state` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `zoom` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `click` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `double_click` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `right_click` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `set_value` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `type_text` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `press_key` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `hotkey` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `scroll` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `drag` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `move_cursor` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `click_point` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `invoke_menu` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `launch_app` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `set_window_frame` | `computer_use.request` | engine | Engine `computer_use.request`, polled via `computer_use.result`; FFI Pump drains it into the native macOS executor (ScreenCaptureKit / Accessibility / CGEvent) |
| `file_read` | `workspace.read_file` | desktop | FFI `workspace.read_file` arm -> `coincide_core::workspace_tools::read_file` (alias of `read_file`) |
| `view_file` | `workspace.read_file` | desktop | Same as `file_read` |
| `file_write` | `workspace.write_file` | desktop | FFI `workspace.write_file` arm -> `coincide_core::workspace_tools::write_file` (alias of `write_file`) |
| `create_file` | `workspace.write_file` | desktop | Refuses when the file exists; otherwise FFI `workspace.write_file` arm |
| `file_create` | `workspace.write_file` | desktop | Same as `create_file` |
| `file_append` | `workspace.write_file` | desktop | Read + write composition through the FFI `workspace.read_file` / `workspace.write_file` arms; a missing file is an error |
| `file_delete` | `workspace.delete_file` | desktop | FFI `workspace.delete_file` arm -> `coincide_core::workspace_tools::delete_file` (alias of `delete_file`) |
| `dir_delete` | `workspace.delete_directory` | desktop | FFI `workspace.delete_directory` arm -> `coincide_core::workspace_tools::delete_directory` (alias of `delete_directory`) |
| `file_move` | `workspace.move_file` | desktop | FFI `workspace.move_file` arm -> `coincide_core::workspace_tools::move_file` (alias of `move_file`) |
| `file_rename` | `workspace.move_file` | desktop | FFI `workspace.move_file` arm with a same-directory destination; `newName` must be a single file name, not a path |
| `file_copy` | `workspace.copy_file` | desktop | FFI `workspace.copy_file` arm -> `coincide_core::workspace_tools::copy_file` (alias of `copy_file`) |
| `dir_create` | `workspace.create_dir` | desktop | FFI `workspace.create_dir` arm -> `coincide_core::workspace_tools::create_dir` (alias of `create_directory`) |
| `dir_read` | `workspace.read_dir` | desktop | FFI `workspace.read_dir` arm -> `coincide_core::workspace_tools::read_dir`, non-recursive (alias of `read_directory`) |
| `list_directory` | `workspace.read_dir` | desktop | FFI `workspace.read_dir` arm -> `coincide_core::workspace_tools::read_dir` (alias of `read_directory`) |
| `tree_view` | `workspace.read_dir` | desktop | FFI `workspace.read_dir` arm -> `coincide_core::workspace_tools::read_dir`, recursive, depth-filtered client-side by `maxDepth` |
| `search_directory` | `workspace.files` | desktop | FFI `workspace.files` arm -> `coincide_core::workspace_tools::files` (alias of `list_files`) |
| `search_text` | `workspace.search` | desktop | FFI `workspace.search` arm -> `coincide_core::workspace_tools::search` (alias of `search_files`) |
| `code_replace` | `workspace.edit_file` | desktop | FFI `workspace.edit_file` arm -> `coincide_core::workspace_tools::edit_file` (exactly-once anchor), or read + write when `allowMultiple` is true |
| `code_insert` | `workspace.write_file` | desktop | Read + write composition through the FFI `workspace.read_file` / `workspace.write_file` arms; `line` / `before` / `after` modes |
| `code_multi_edit` | `workspace.edit_file` | desktop | FFI `workspace.edit_file` arm -> `coincide_core::workspace_tools::edit_file` with `edits` (alias of `multi_edit_file`) |
| `use_terminal` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel. No approval step: the command is typed into a fresh shell as given, and the terminal stays open in the drawer afterwards. |
| `run_command` | `terminal.create` | engine | Same as `use_terminal` |
| `git_log_viewer` | `git.log` | engine | Engine `git.log`, async workspace channel polled via `workspace.result` |
| `git_branch_compare` | `git.diff.range` | engine | Engine `git.diff.range`, async workspace channel polled via `workspace.result` |
| `project_diff` | `git.diff` | engine | Engine `git.diff`, async workspace channel polled via `workspace.result` |
| `git_branch_manager` | `git.branches.list` | engine | Dispatches on `action`: list/create/checkout/delete via Engine `git.branches.*`, polled via `git.actions.result`; delete requires `confirm=true` |
| `save_to_memory` | `memory.store` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::store_entry` (SQLite `memory_entries`) |
| `use_mcp` | `mcp.tools` | desktop | Local meta-tool over the live registry: `list` / `list_tools` / recursive `SystemToolRegistry.execute` (Swift mirror); Rust: recursive `tools::call` (`use_mcp` arm, tools.rs:17299, recursing at :17336); only the `coincide` server exists |
| `take_screenshot` | `computer_use.request` | engine | Engine `computer_use.request` (`get_desktop_state` with `include_screenshot`), polled via `computer_use.result`; FFI Pump drains it into the native macOS executor |
| `start_subagent` | `workers.spawn` | desktop | FFI `workers.*` arm -> `Engine::workers_spawn` (record in SQLite `worker_records`) (alias of `use_workers`) |
| `git_stash_operator` | `git.stash` | engine | Engine `git.stash` (`workspace_git::stash` on the hardened `git()` runner), polled via `workspace.result`; pop/drop require `confirm=true` |
| `git_blame_inspector` | `git.blame` | engine | Engine `git.blame` (`git blame --line-porcelain`), polled via `workspace.result` |
| `git_bisect` | `git.bisect` | engine | Engine `git.bisect` (start/good/bad/skip/reset/log), polled via `workspace.result` |
| `git_cherry_pick` | `git.cherry_pick` | engine | Engine `git.cherry_pick` (SHA-validated), polled via `workspace.result`; requires `confirm=true`; conflicts are reported, never auto-aborted |
| `version_control_operator` | `git.rollback` | engine | Dispatches on `action`: status/diff/commit/branch via the existing engines, rollback via Engine `git.rollback`; rollback requires `confirm=true` and only accepts `HEAD`, `HEAD~N`, `HEAD^N`, or a full OID |
| `git_pr_summary` | `git.log` | engine | Swift composition of Engine `git.log` + `git.diff.range` / `git.diff.branch`, markdown out |
| `git_conflict_resolver` | `workspace.search_regex` | desktop | Swift composition: `workspace.search_regex` for `<<<<<<<` / `=======` / `>>>>>>>`, read + write to resolve |
| `project_snapshot` | `git.checkpoints.create` | engine | Engine `git.checkpoints.create` via the workspace API (`git.workspace.result`); returns the snapshot `id` |
| `project_changelog` | `git.checkpoints.list` | engine | Engine `git.checkpoints.list` via the workspace API; the list returns only `id` + `commit`, the label lives in the commit message |
| `project_restore` | `git.checkpoints.restore` | engine | Engine `git.checkpoints.restore` via the workspace API; `reset --hard` + `clean -fdx`; requires `confirm=true` |
| `safe_undo` | `git.checkpoints.restore` | engine | Swift composition: list snapshots, restore the second-newest; requires `confirm=true` and at least two snapshots |
| `safe_validate_changes` | `workspace.search_regex` | desktop | Swift-only scan: merge markers + missing trailing newline via `workspace.search_regex` / `workspace.read_file` |
| `create_artifact` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `list_artifacts` | `workspace.read_dir` | desktop | FFI `workspace.read_dir` arm -> `coincide_core::workspace_tools::read_dir`, with metadata fields |
| `read_artifact` | `workspace.read_file` | desktop | Swift composition over the FFI `workspace.read_file` arm |
| `delete_artifact` | `workspace.delete_file` | desktop | FFI `workspace.delete_file` arm -> `coincide_core::workspace_tools::delete_file` |
| `format_json_file` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `csv_to_json` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `json_to_csv` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `plist_to_json` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `json_to_plist` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `json_validate` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `json_validator_tool` | `workspace.read_file` | desktop | Swift composition over the FFI `workspace.read_file` arm |
| `yaml_validate` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `yaml_parser_tool` | `workspace.read_file` | desktop | Swift composition over the FFI `workspace.read_file` arm |
| `plist_edit` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `plist_editor` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `binary_plist_converter` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `file_metadata` | `workspace.read_dir` | desktop | FFI `workspace.read_dir` arm -> `coincide_core::workspace_tools::read_dir`, with metadata fields |
| `file_hash_verify` | `workspace.read_file` | desktop | In-process FileManager bytes + CryptoKit (SHA-256/SHA-512/SHA-1/MD5) |
| `generate_file_checksum` | `workspace.read_file` | desktop | In-process FileManager bytes + CryptoKit (SHA-256/SHA-512/SHA-1/MD5) |
| `file_checksum_verifier` | `workspace.read_file` | desktop | In-process FileManager bytes + CryptoKit (SHA-256/SHA-512/SHA-1/MD5) |
| `file_compare_diff` | `workspace.read_file` | desktop | Swift composition over the FFI `workspace.read_file` arm |
| `file_head_preview` | `workspace.read_file` | desktop | Swift composition over the FFI `workspace.read_file` arm |
| `code_generate` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `code_format` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `swift_format_lint` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `code_mutation_engine` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `patch_application_engine` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `automated_repair_engine` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `regex_replace_in_files` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `symbol_rename_project` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `symbol_move_file` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `import_cleanup` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `batch_rename_files` | `workspace.move_file` | desktop | FFI `workspace.move_file` arm -> `coincide_core::workspace_tools::move_file` |
| `file_backup` | `workspace.copy_file` | desktop | Swift FileManager byte copy (read + write), verified by size |
| `session_export` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `markdown_toc_generate` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `readme_generate` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `docs_generate` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `test_data_factory` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `ui_test_scaffold` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `test_snapshot_manage` | `workspace.read_dir` | desktop | FFI `workspace.read_dir` arm for list; clean adds text search + FFI `workspace.delete_file`, keeps snapshots referenced by a `.swift` file |
| `open_in_finder` | `system.open_in_finder` | desktop | In-process `NSWorkspace.shared.open`, same API family as `ExternalEditorService` |
| `reveal_in_finder` | `system.reveal_in_finder` | desktop | In-process `NSWorkspace.shared.activateFileViewerSelecting`, same call as `ExternalEditorService` |
| `image_encode_base64` | `workspace.read_file` | desktop | In-process FileManager bytes + `Data` base64 |
| `image_decode_base64` | `workspace.write_file` | desktop | In-process `Data` base64 + FileManager bytes |
| `image_get_dimensions` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `image_convert_format` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `image_generate_thumbnail` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `image_extract_metadata` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `zip_file` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `unzip_file` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `tar_archive_create` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `tar_archive_extract` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `gzip_compress_file` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `gzip_decompress_file` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `count_file_lines` | `workspace.read_file` | desktop | Swift composition over the FFI `workspace.read_file` arm |
| `extract_code_symbols` | `workspace.read_file` | desktop | Swift composition over the FFI `workspace.read_file` arm |
| `find_duplicate_files` | `workspace.read_file` | desktop | FFI `workspace.read_dir` arm + FileManager bytes + CryptoKit SHA-256, grouped by hash |
| `env_capture_logs` | `memory.snapshot` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::snapshot_context` |
| `project_build` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `project_test` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `compiler_diagnostics_engine` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `dependency_resolution_engine` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `generate_xcodeproj` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `project_scheme_list` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `project_target_list` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `project_build_settings` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `project_clean` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `project_archive` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `test_run_single` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `test_coverage_report` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `test_coverage_reporter` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `performance_benchmark` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `docc_build` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `xcode_scheme_manager` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `xcode_build_settings_inspector` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `xcode_device_destination_finder` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `simulator_list` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `simulator_boot` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `simulator_controller` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `device_list` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `provisioning_check` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `swift_package_manager` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `package_dependency_update` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `code_signing_diagnose` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `xcode_toolchain_info` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `xcresult_parser` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `mach_o_binary_analyzer` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `signing_certificate_inspector` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `provisioning_profile_reader` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `swift_ast_inspector` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `binary_size_report` | `terminal.create` | engine | Terminal RPC: `terminal.create` runs the real CLI in the thread workspace and returns real output + exit code |
| `git_review_diff` | `git.review.diff` | engine | Engine `git.review.diff` -> `coincide_core::workspace_api::workspace_diff::review` |
| `search_symbol` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `dependency_graph` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `source_graph_builder` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `semantic_query_engine` | `workspace.search` | desktop | Swift literal composition over `searchWorkspace` + Rust `search` arm |
| `code_summary` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `code_lint` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `complexity_analysis` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `autonomous_review_engine` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `runtime_diagnostics_engine` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `code_metrics_analyzer` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `memory_leak_detector` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `dead_code_eliminator` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `dead_code_scan` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `duplicate_code_scan` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `todo_scan` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `todo_fixme_scanner` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `license_header_check` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `api_surface_extract` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `access_level_audit` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `concurrency_audit` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `swift_concurrency_analyzer` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `swift_migration_advisor` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `security_audit_scanner` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `secrets_scan` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `network_security_auditor` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `permissions_audit` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `accessibility_audit` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `accessibility_audit_scanner` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `interface_simulator` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `docstring_generator` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `code_snippet_manager` | `workspace.write_file` | desktop | Swift template return, optional `writeWorkspaceFile` + Rust `write_text_file` arm |
| `unused_imports_detector` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `force_unwrap_scan` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `string_literal_audit` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `comment_density_report` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `function_size_report` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `call_hierarchy` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `type_hierarchy` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `protocol_conformance_list` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `import_graph` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `change_impact_estimate` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `conflict_marker_scan` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `build_log_analyze` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `crash_log_parse` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `deprecation_usage_scan` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `info_plist_audit` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `api_endpoint_audit` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `color_usage_audit` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `strings_file_validate` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `entitlements_diff` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `pbxproj_lint` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `xctest_discovery` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `build_settings_diff` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `build_phase_scripts_list` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `build_configuration_list` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `target_dependencies_list` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `target_source_list` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `workspace_settings_read` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `scheme_test_plan_list` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `test_log_parse` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `test_flaky_detect` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `code_comment_extract` | `workspace.search_regex` | desktop | Swift regex composition over `searchWorkspaceRegex` + Rust `search_regex` arm |
| `api_docs_coverage` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `markdown_link_check` | `workspace.read_file` | desktop | Swift read-and-parse composition over `readWorkspaceFile` + Rust `read_text_file_at` arm |
| `docs_index_build` | `workspace.files` | desktop | Swift list-and-read composition over `listWorkspaceFiles` + Rust `read_dir_entries` arm |
| `framework_linker_auditor` | `workspace.read_file` | desktop | Swift pbxproj text parse for linked frameworks (weak flag), SDKROOT, deployment targets |
| `string_catalog_migrator` | `workspace.write_file` | desktop | Swift `.strings` pair parse -> new `.xcstrings` JSON, verified by re-read; `.stringsdict` skipped with reason |
| `symbol_reference_graph` | `workspace.search_regex` | desktop | FFI regex search for declarations + word references, path-scoped |
| `podfile_inspector` | `workspace.read_file` | desktop | Swift Podfile + Podfile.lock PODS parse |
| `carthage_cartfile_inspector` | `workspace.read_file` | desktop | Swift Cartfile + Cartfile.resolved parse |
| `spm_dependency_tree` | `terminal.create` | engine | Engine terminal `swift package show-dependencies --format json` |
| `package_manifest_read` | `workspace.read_file` | desktop | Swift Package.swift regex parse (name/platforms/products/targets/dependencies) |
| `package_manifest_validate` | `terminal.create` | engine | Engine terminal `swift package dump-package` |
| `package_dependency_audit` | `terminal.create` | engine | Engine terminal manifest vs Package.resolved vs `show-dependencies` comparison |
| `package_dependency_add` | `workspace.write_file` | desktop | Swift Package.swift text insert of `.package(url:from:)` + optional `.product` wiring, verified on re-read |
| `asset_catalog_list` | `workspace.files` | desktop | Swift recursive directory listing, counted by `.imageset`/`.colorset`/`.appiconset` suffix |
| `asset_image_add` | `workspace.write_file` | desktop | Swift FFI copy into a new `.imageset` + generated Contents.json, verified by re-read |
| `strings_localization` | `workspace.write_file` | desktop | Swift `.strings` pair rewrite or `.xcstrings` JSON edit via JSONValue |
| `localization_audit` | `workspace.read_file` | desktop | Swift `.strings` + `.xcstrings` key sets vs Swift source references |
| `localize_app` | `workspace.write_file` | desktop | Swift NSLocalizedString/String(localized:) key discovery, merges root Localizable.xcstrings, sets Info.plist CFBundleLocalizations + CFBundleDevelopmentRegion |
| `asset_catalog_manager` | `workspace.write_file` | desktop | Swift list/inspect/create_imageset/create_colorset over the real `.xcassets` tree |
| `localization_manager` | `workspace.write_file` | desktop | Swift list/extract/add over `.strings` + `.xcstrings`; validate delegates to the G5 strings validator |
| `entitlements_manager` | `workspace.write_file` | desktop | Swift plist read/write via PropertyListSerialization |
| `colorset_builder` | `workspace.write_file` | desktop | Swift `.colorset` Contents.json from #RRGGBB components, verified by re-read |
| `icon_generator_tool` | `terminal.create` | engine | Engine terminal real `sips -Z` resize per size + generated Contents.json |
| `project_entitlements` | `workspace.read_file` | desktop | Swift plist read via PropertyListSerialization |
| `project_info_plist` | `workspace.write_file` | desktop | Swift plist read/write via PropertyListSerialization |
| `project_capabilities` | `workspace.write_file` | desktop | Swift plist read/write; only the 11 boolean entitlement capabilities are rewritten |
| `project_signing` | `terminal.create` | engine | Swift pbxproj signing parse; optional `xcodebuild -showBuildSettings -scheme` when a scheme is given |
| `entry_points_discover` | `workspace.search_regex` | desktop | FFI `@main` + AppDelegate/SceneDelegate regex + main.swift discovery |
| `repo_overview` | `workspace.files` | desktop | Swift recursive listing, language counts by extension, README/LICENSE presence, 10 largest files |
| `project_structure_map` | `workspace.read_dir` | desktop | Swift recursive listing, file counts per directory + pbxproj targets |
| `recent_changes` | `workspace.read_dir` | desktop | Swift recursive listing filtered by modifiedAt |
| `readme_locate` | `workspace.read_file` | desktop | Swift recursive listing for README* + first `# ` title |
| `dependency_licenses` | `workspace.read_file` | desktop | Swift Package.resolved + Podfile.lock parse (name/version/source; license text is not in those files) |
| `stale_files_report` | `workspace.read_dir` | desktop | Swift recursive listing, source files older than N days by modifiedAt |
| `file_type_breakdown` | `workspace.files` | desktop | Swift recursive listing, counts + bytes per extension |
| `empty_dirs_find` | `workspace.read_dir` | desktop | Swift recursive listing, directories with no children |
| `symlink_audit` | `workspace.read_dir` | desktop | Swift recursive listing, isSymlink + broken-target check via FileManager |
| `executable_files_scan` | `workspace.read_dir` | desktop | Swift recursive listing filtered by isExecutable |
| `dir_size_report` | `workspace.read_dir` | desktop | Swift recursive listing, summed sizeBytes per top-level directory |
| `image_asset_size_report` | `workspace.read_dir` | desktop | Swift recursive listing, images under `.xcassets/` over the size threshold |
| `bundle_resource_auditor` | `workspace.read_file` | desktop | Swift pbxproj resource phases vs real files |
| `core_data_model_inspector` | `workspace.read_file` | desktop | Swift `.xcdatamodel/contents` XML parse (entities/attributes/relationships) |
| `swift_data_schema_auditor` | `workspace.read_file` | desktop | Swift `@Model`/`@Relationship`/`@Attribute(.unique)` scan |
| `privacy_manifest_auditor` | `workspace.read_file` | desktop | Swift PrivacyInfo.xcprivacy plist audit only (never edits) |
| `env_info` | `system.info` | desktop | Swift ProcessInfo + utsname in-process |
| `process_monitor_tool` | `terminal.create` | engine | Engine terminal `/bin/ps -ax -o pid=,pcpu=,pmem=,comm=` |
| `disk_space_analyzer` | `terminal.create` | engine | Engine terminal `df -k` + `du -sk` |
| `environment_variable_manager` | `system.env` | desktop | Swift ProcessInfo.processInfo.environment in-process (list/get only; set is refused) |
| `clipboard_manager_tool` | `system.clipboard` | desktop | Swift NSPasteboard.general |
| `system_notification_tool` | `system.notify` | desktop | Swift UNUserNotificationCenter fire-and-forget (delivery needs launch-time authorization) |
| `use_system` | `terminal.create` | engine | Engine terminal fixed-argv ps/ifconfig/lsof/log/launchctl/defaults/sysctl; allow-listed only |
| `search_skills` | `system.skills` | desktop | Swift SystemAssetManager.shared.search over the bundled SystemAssets index only |
| `plan-AskUser` | `agent.pending` | engine | Engine RPC `agent.pending` list / `agent.answer` submit; does not present a question or suspend the turn |
| `tool_capability_lookup` | `system.lookup` | desktop | Swift SystemToolRegistry.definition(named:for:) in-process |
| `preflight_checks` | `terminal.create` | engine | Engine terminal writable probe + `xcodebuild -version` + disk space + artifact-storage probe |
| `session_progress_report` | `workspace.read_file` | desktop | Swift read of agent_notes.md (`## ` phases, "fail" lines) + workers.list when a threadId is given |
| `manage_memory` | `memory.store` | desktop | Swift SQLite KV via AgentsRuntimeClient memoryStore/Retrieve/List/Delete/Clear (no sections, no UserMemory.md) |
| `fetch_documentation` | `web.fetch` | desktop | Swift URLSession GET, developer.apple.com only, returns raw page text |
| `external_resource_gateway` | `web.fetch` | desktop | Swift URLSession https-only JSON GET, 30 s, non-2xx fails |
| `read_url_content` | `web.fetch` | desktop | Swift URLSession https-only text GET |
| `github_repo` | `github.repo` | engine | Engine terminal real `gh` CLI (repo view, contents API, code search, tarball fetch) |
| `use_app` | `computer_use.request` | engine | Swift dispatch of the 20 real computer-use tools only; the 9 missing actions error honestly |
| `derived_data_locate` | `system.info` | desktop | Swift FileManager enumeration of ~/Library/Developer/Xcode/DerivedData with recursive sizes |
| `build_system_detect` | `workspace.files` | desktop | Swift recursive listing for xcworkspace/xcodeproj/SwiftPM/CocoaPods/Carthage/Tuist/xcodegen/Bazel/CMake markers |
| `svg_to_png` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `intel_generate_tests` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms |
| `search_web` | `web.fetch` | desktop | Swift URLSession GET of the DuckDuckGo HTML endpoint, result links parsed by regex |
| `reverse_analyze` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `report_to_user` | `workspace.write_file` | desktop | Swift composition over the FFI `workspace.read_file` / `workspace.write_file` arms; appends to agent_notes.md |
| `intel_explain_code` | `workspace.read_file` | desktop | Swift composition of `code_summary` + `api_surface_extract` + `code_comment_extract` over `readWorkspaceFile` / regex search |

### Slice 10: Git completion, snapshots, and aliases

- `workspace_git.rs` constraint amendment: the module header used to forbid
  checkout, reset, and clean. `reset --hard` and `clean -fdx` are now allowed
  ONLY inside the named, confirmation-gated functions `rollback` and
  `restore_checkpoint`. Checkout, worktree removal, network access, and user
  hooks remain excluded.
- `edit_file` was already registered, so it is not registered twice. The 30th
  new alias is `file_append` (catalog File Operations entry: append, missing
  file is an error), keeping the registry at 107 tools with 51 distinct
  actions.
- Destructive operations require `confirm=true` in both the Swift registry
  (refused before any engine call) and the Rust engine (backstop): rollback,
  cherry-pick, stash pop/drop, branch delete (`-d` and `-D`), checkpoint
  restore, and `safe_undo`. `git_bisect` does not require confirmation: it
  moves HEAD but is recoverable with `bisect reset`.
- `project_restore` resets the branch to the checkpoint commit and removes
  untracked AND ignored files (`clean -fdx`); there is no tracked-only
  restore. `project_changelog` returns only snapshot id and commit; the
  label lives in the checkpoint commit message. `safe_undo` restores the
  second-newest snapshot (the list is newest-first) and needs at least two
  snapshots.
- Manual staged checkpoints now have a Restore button in Inspector › Git,
  next to Diff, behind the same confirmation pattern as turn-checkpoint
  restore.

### Slice 11: G4 file ops, transforms & artifacts

59 new tools, taking the registry from 107 to 166 tools and 51 to 53
distinct actions (the two new actions are `system.open_in_finder` and
`system.reveal_in_finder`). `file_append` was already registered in slice
10, so the G4 family counts 60 distinct names with 59 new registrations.
No G4 tool was left unimplemented.

- `read_dir` metadata extension: `coincide-core` `workspace_tools::read_dir`
  entries now carry `sizeBytes`, `modifiedAt` (seconds since epoch, float),
  `isSymlink`, `symlinkTarget` (null unless a symlink), and `isExecutable`
  (Unix permission bit `0o111`, false elsewhere). Swift
  `WorkspaceFileEntry` gained the same five fields, decoded through the
  existing `AnyCodingKey` helpers. `file_metadata` lists the parent
  directory and picks the entry; `list_artifacts` sorts newest-first by
  `modifiedAt`.
- Artifacts convention: `.assist_temp/artifacts/<name>.md`, over the real
  write/read/list/delete primitives. The name must be a plain file name
  (no `/`, `\`, `.`, or `..`); `.md` is appended when missing.
  `delete_artifact` requires `confirm=true`; `agent_notes.md` is protected
  from deletion. `read_artifact` caps content at 60,000 characters and
  marks truncation. `file_backup` uses the same convention under
  `.assist_temp/backups/<base>.<yyyy-MM-dd-HHmmss>.bak`.
- Binary file IO: the Rust `workspace.read_file` arm refuses binary content
  (NUL check) and requires UTF-8, so checksums, base64, backups, and
  duplicate detection read bytes directly with FileManager under a
  symlink-resolved containment check (mirroring `resolveThreadRoot` /
  `assertFileAbsent`), capped at 3 MiB.
- Checksums: Swift computes SHA-256 / SHA-512 / SHA-1 / MD5 in-process with
  CryptoKit over those bytes. The Rust MCP arms shell out to `shasum` /
  `md5` through the session terminal, matching the catalog's own wording;
  `remote_crypto.rs` exists but is not declared in
  `coincide-core/src/lib.rs`, so `sha256_hex` is unavailable to the server.
- `file_compare_diff` is a real LCS-based unified diff with hunks (3 lines
  of context) in Swift, not `workspace_diff::changed_ranges` (that helper
  returns a single optional character range and gives up on files over
  2000 characters). The Rust arm runs the real `diff -u` CLI, treating
  exit 1 as "different" rather than an error.
- YAML is a heuristic validator plus a subset parser in both Swift and
  Rust: mappings, nested mappings, lists (including `- key: value` items),
  and scalars. It is NOT a full YAML parser — no anchors, aliases, flow
  style, or block scalars — and the tool descriptions say so. The validator
  flags tabs, unbalanced brackets/quotes, and duplicate top-level keys.
- Plists: Swift uses `PropertyListSerialization` in-process (XML and
  binary); edits preserve the source format and verify with a re-read. The
  Rust arms shell out to `plutil` (`-convert`, `-extract`, `-replace` with
  `-insert` fallback, `-remove`, `-lint`) through the session terminal, so
  they need a mounted thread.
- CLI-backed tools (`sips`, `mdls`, `ditto`, `tar`, `gzip`, `plutil`,
  `swiftformat`) run through the real terminal RPC and return real output
  plus exit code. A missing CLI is a real error, never a fake result:
  `swift_format_lint` reports "swiftformat is not installed" on exit 127
  or "command not found", and returns `lintPassed` instead of throwing on a
  nonzero lint exit.
- `code_format` is text normalization only (tabs to 4 spaces, trailing
  whitespace, blank-line collapse to at most 2, trailing newline) — not a
  real formatter. `code_generate` writes template files (`swift_struct`,
  `swift_class`, `swiftui_view`, `test`, the last a failing `#expect`
  scaffold per the catalog) and refuses to overwrite; it does NOT register
  the file in `project.pbxproj`, because no such primitive exists — the
  catalog's pbxproj claim is not implemented.
- `automated_repair_engine` is annotation-only: it inserts
  `// AssistAutoRepair: review required` above the named lines and does not
  fix or rebuild anything. `import_cleanup` and `test_snapshot_manage`
  clean are heuristics: an import is removed only when its module name
  appears nowhere else as a whole word (a protected set of system modules
  is never removed), and a snapshot is deleted only when its base name
  (one extension stripped) is not referenced in any `.swift` file.
- `env_capture_logs` is a thin alias of `mem_context_snapshot`
  (`memory.snapshot`); it returns snapshot metadata only, never log
  contents — the name overstates what it does.
- Swift-vs-Rust mechanism split: Swift runs JSON/plist/YAML/checksum/diff
  in-process (JSONSerialization, PropertyListSerialization, CryptoKit,
  LCS); the Rust MCP arms use the equivalent CLIs (`plutil`, `shasum`,
  `md5`, `diff -u`) or hand-rolled helpers (base64, YAML subset parser)
  through the session terminal, and use the `regex` crate for
  `regex_replace_in_files`. Both sides are covered by the same cross-check
  test, updated to 166.
- Finder tools: Swift uses `NSWorkspace.shared.open` /
  `activateFileViewerSelecting` on the main actor; the Rust arms use the
  macOS `open` / `open -R` CLI through the session terminal.
- Pre-existing repair found by the cross-check: since slice 5,
  `set_window_frame` in the Swift registry was missing its closing `]` and
  `),`, so every definition after it nested inside its `parameters` array
  (a type error) and the array end carried a compensating extra `),` +
  `]` pair. The Rust cross-check test parses the Swift source by
  definition, so it failed on that tool too (9 params parsed vs 7 real).
  This slice restores the two missing lines after the `height` parameter
  and removes the compensating pair at the end of the array; the registry
  now counts 166 definitions, 166 closers, 166 parameter-array closes,
  and the cross-check is written to pass exactly (no build or test run was
  performed in this environment; the tests are written, not executed).

### Slice 12: G3 build/test/Xcode/devices

34 new tools, taking the registry from 166 to 200 tools and 53 to 54
distinct actions (the one new action is `git.review.diff`). All 33 G3
tools landed; none was left unimplemented.

- G3 family: `project_build`, `project_test`, `compiler_diagnostics_engine`
  (parses real xcodebuild/swift build output into diagnostics),
  `dependency_resolution_engine`, `generate_xcodeproj` (runs the real
  `xcodegen` CLI; errors honestly when it is not installed),
  `project_scheme_list` (`xcodebuild -list -json`, parsed),
  `project_target_list`, `project_build_settings` (read half only, see
  below), `project_clean` (requires `confirm=true`), `project_archive`,
  `test_run_single` (`xcodebuild test -only-testing:`),
  `test_coverage_report`, `test_coverage_reporter`, `performance_benchmark`
  (allow-listed only, see below), `docc_build`, `xcode_scheme_manager`,
  `xcode_build_settings_inspector`, `xcode_device_destination_finder`,
  `simulator_list`, `simulator_boot`, `simulator_controller` (real `xcrun
  simctl`), `device_list` (`xcrun devicectl`, with `xcrun xctrace list
  devices` fallback only when devicectl is missing), `provisioning_check`
  (`security cms -D`), `swift_package_manager`, `package_dependency_update`
  (`swift package`), `code_signing_diagnose` (`codesign`),
  `xcode_toolchain_info` (`xcodebuild -version`), `xcresult_parser`
  (`xcrun xcresulttool`), `mach_o_binary_analyzer` (`otool`/`file`),
  `signing_certificate_inspector`, `provisioning_profile_reader`
  (`security`), `swift_ast_inspector` (`swiftc -dump-ast`),
  `binary_size_report` (`read_dir` + `du` under `build/`). Every G3 tool
  runs its CLI through the real terminal RPC with a fixed argv template,
  validated arguments, and a parser that reports the real result (counts,
  diagnostics, lists). A missing CLI is a real error, never a fake result.
- `project_build_settings` set half is NONE: no pbxproj writer exists in
  this repo, so no setter is registered and none is planned until a writer
  exists. The tool reads only.
- `performance_benchmark` allow-list: exactly `xcodebuild-build`,
  `xcodebuild-test`, `swift-build`, `swift-test`, and
  `xcodebuild-clean-build`. Anything else is refused before any command
  runs. A `scheme` is accepted only for the xcodebuild benchmarks.
- Newly wired engine methods: `git.review.diff` (workspace API, exposed as
  the `git_review_diff` tool; `scope` is `uncommitted` or `branch`) and
  `git.worktrees.useExisting` (the Worktrees card in Inspector > Git now
  has a Switch button on every non-current worktree, gated on
  `canChangeWorkspace`, wired through `RemoteCheckoutAction
  .useExistingWorktree(path:branch:)` and the FFI `handle_change_checkout`
  arm).
- Swift-vs-Rust mechanism split: the Rust MCP arms mirror the Swift
  parsers. Provisioning arms pipe `security cms -D -i <path> | plutil
  -convert json -o - -` (Swift uses PropertyListSerialization in-process);
  `simulator_controller` openurl validation is a scheme check in Swift and
  a `://` check in Rust; `binary_size_report` counts files with
  `read_dir_entries` in Rust and the workspace directory reader in Swift.
- Pre-existing repair found by the cross-check: `version_control_operator`
  in the Swift registry described itself as running git "by action: ...",
  which the naive Rust cross-check parser read as the tool's action field;
  the Rust table carried the same corruption, so the two bugs cancelled
  out and the test passed. This slice rewrites the description on both
  sides and sets the Rust action to the real `git.rollback`. The MCP
  integration test asserted 41 tools (stale since the registry passed 41);
  it now asserts 200 with the full name list.


### Slice 13: G5 part 1 — code scans + project-structure read-only tools

65 new tools, taking the registry from 200 to 265 tools; distinct actions
stay at 54, because all 65 reuse existing actions (`workspace.search_regex`
x32, `workspace.read_file` x30, `workspace.files` x1, `workspace.search`
x1, `workspace.write_file` x1). All 65 G5 part 1 tools landed; none was
left unimplemented and none was already registered.

- Count correction: the slice was scoped as 66 tools (49 code scans + 17
  project-structure tools), but the task's own lists contain 48 code scans
  + 17 project-structure tools = 65. The registry therefore goes 200 ->
  265, not 266.
- Code scans (48): `search_symbol`, `dependency_graph`,
  `source_graph_builder`, `semantic_query_engine`, `code_summary`,
  `code_lint`, `complexity_analysis`, `autonomous_review_engine`,
  `runtime_diagnostics_engine`, `code_metrics_analyzer`,
  `memory_leak_detector`, `dead_code_eliminator`, `dead_code_scan`,
  `duplicate_code_scan`, `todo_scan`, `todo_fixme_scanner`,
  `license_header_check`, `api_surface_extract`, `access_level_audit`,
  `concurrency_audit`, `swift_concurrency_analyzer`,
  `swift_migration_advisor`, `security_audit_scanner`, `secrets_scan`,
  `network_security_auditor`, `permissions_audit`, `accessibility_audit`,
  `accessibility_audit_scanner`, `interface_simulator`,
  `docstring_generator`, `code_snippet_manager`,
  `unused_imports_detector`, `force_unwrap_scan`, `string_literal_audit`,
  `comment_density_report`, `function_size_report`, `call_hierarchy`,
  `type_hierarchy`, `protocol_conformance_list`, `import_graph`,
  `change_impact_estimate`, `conflict_marker_scan`, `build_log_analyze`,
  `crash_log_parse`, `deprecation_usage_scan`, `info_plist_audit`,
  `api_endpoint_audit`, `color_usage_audit`.
- Project-structure read-only tools (17): `strings_file_validate`,
  `entitlements_diff`, `pbxproj_lint`, `xctest_discovery`,
  `build_settings_diff`, `build_phase_scripts_list`,
  `build_configuration_list`, `target_dependencies_list`,
  `target_source_list`, `workspace_settings_read`,
  `scheme_test_plan_list`, `test_log_parse`, `test_flaky_detect`,
  `code_comment_extract`, `api_docs_coverage`, `markdown_link_check`,
  `docs_index_build`.
- Heuristic scans: what these tools really are. Every one of the 65 is a
  regex/substring scan over real workspace content, or a parser over real
  plist / xcconfig / pbxproj / log text. `semantic_query_engine` is a
  literal keyword search, not a semantic index. `complexity_analysis`
  counts branch keywords and returns 1 + that count as an estimate, not a
  cyclomatic-complexity computation. `dead_code_scan` is a regex-based
  unused-symbol heuristic: a declaration whose name appears only once in
  the workspace is a candidate, not a proven dead symbol.
  `autonomous_review_engine` composes the lint, complexity, secrets, and
  force-unwrap scans and reports their findings; it does not review code.
  `runtime_diagnostics_engine` counts crash-log needles (fatal error,
  EXC_, SIG, Thread) and reports the count; it does not diagnose a live
  process. No tool description calls a scan semantic analysis, AI review,
  or deep analysis, and the catalog (`AvailableTools.md`) already
  describes all 65 honestly, so it needs no change.
- One generic table-driven engine covers the 33 pure scan tools in both
  languages (label, pattern, redact, capture; shapes `patterns`, `files`,
  `host`, `flat`; a `literal` flag; a per-tool sample limit). The other 32
  tools have dedicated parsers: file-content parsing, two-file diffs,
  pbxproj parsing, log parsing, and snippet templates. Patterns avoid
  lookahead, lookbehind, and backreferences, which the Rust `regex` crate
  and ripgrep do not support; user input (`symbol`, `function`,
  `protocol`) is regex-escaped before substitution.
- `dead_code_eliminator` is report-only: it lists private-function
  candidates with file:line evidence and `reportOnly: true`. It deletes
  nothing; deletion is a separate, confirmed `edit_file` step.
  `pbxproj_lint` is read-only regex over pbxproj text; no pbxproj writer
  exists in this repo, so nothing writes pbxproj.
- `secrets_scan` and the secret patterns in `security_audit_scanner` are
  redacted: results carry path, line, and pattern name only, never line
  text or a matched value.
- Swift-vs-Rust mechanism split: the Rust MCP arms mirror the Swift
  engine. Swift uses `NSRegularExpression`; Rust uses the `regex` crate
  with multiline mode. The pbxproj file-reference pattern needed a Rust
  raw string with `#` delimiters because the pattern contains literal
  quotes; the Swift analogue is a plain string. Literal search uses the
  `query` parameter on both sides. The markdown-link closer check compares
  captured open/close tag names explicitly instead of a backreference.
- Tests: six new `@Test` functions in `AgentsTests/ToolsetTests.swift`
  (registration of all 65 with actions and channels; regex scans against
  a real temp workspace with known content; file parses against the same
  fixtures; pbxproj tools against a real fixture pbxproj; pure-parser unit
  tests; missing-argument refusals). The MCP integration test now asserts
  265 with the full name list. No build or test run was performed in this
  environment; the tests are written, not executed.

### Slice 14: G5 part 2 — Apple formats + repo intelligence + system/lookup/workflow

61 new tools, taking the registry from 265 to 326 tools; distinct actions
54 -> 63 with 9 new actions (`system.lookup`, `system.skills`,
`system.info`, `system.env`, `system.clipboard`, `system.notify`,
`agent.pending`, `web.fetch`, `github.repo`). All 61 G5 part 2 tools
landed; none was left unimplemented. `file_checksum_verifier` was already
registered in Slice 11, so it is skipped, not double-registered.

- Count correction: the slice was scoped as 61 tools (24 + 17 + 20), but
  the system/lookup/workflow list enumerates 21 names, so the lists name
  62; minus the already-registered `file_checksum_verifier`, the true new
  count is 61. The registry therefore goes 265 -> 326.
- Three prior-decision conflicts, resolved by reading the code (see the
  superseded notes below):
  - `search_skills` IS registered. `SystemAssetIndex.search` indexes the
    bundled SystemAssets and `SystemAssetManager.shared.search` is the real
    primitive; the tool's description says exactly that it searches only
    the bundled SystemAssets index, never an external skills library. This
    supersedes the Slice 10 note that claimed no skills-library backend
    exists.
  - `manage_memory` IS registered as a SQLite KV dispatcher
    (store/edit/append/delete/clear/list via the runtime memory client;
    no sections, no `UserMemory.md` file — that file does not exist
    anywhere in the Swift code). This supersedes the Slice 3 note.
  - `use_app` IS registered in narrowed form: it dispatches only the 20
    real computer-use actions and errors honestly on the 9 missing ones
    (`activate`, `close_application`, `select_window`,
    `get_focused_element`, `select_all`, `copy`, `paste`,
    `wait_for_element`, `wait_for_window`).
  - `plan-AskUser` IS registered in narrowed form: the async-question
    machinery lists and answers pending provider questions
    (`agent.pending` / `agent.answer`); there is no 300 s suspension wired
    through the provider turn, and the tool does not present a new
    question or suspend the turn.
- Swift/Rust shape divergences (deliberate, both sides real): the Rust
  `symbol_reference_graph` / `entry_points_discover` omit the `column`
  field (the Rust regex helper returns path/line/text only); the Rust
  `manage_memory` list returns the engine result as-is while Swift maps
  entries to {key, scope, value, updatedAt} objects; the Rust
  `search_skills` is a token scorer over SystemAssets files while Swift
  uses the real `SystemAssetManager` index.
- Bug fixes in this slice: `g6DiskSpace` took the mount point from the
  `iused` column of `df` output; it now takes columns 8+ like the Rust
  side. `colorset_builder` verified by checking the written Contents.json
  for the hex string, which the file never contains (it holds float
  components); it now verifies against the formatted red component.
  `G6Manifest` and `G6IconSize` are internal (not private) so the parser
  tests can call them via `@testable`.
- Tests: four new `@Test` functions in `AgentsTests/ToolsetTests.swift`
  (registration of all 61 with actions and channels; pure-parser unit
  tests; round-trips against a real temp workspace with known fixtures;
  missing-argument / invalid-value refusals). The MCP integration test
  now asserts 326 with the full name list. No build or test run was
  performed in this environment; the tests are written, not executed.

### Slice 18: final catalog tools — the last 6 implementable IDs

6 new tools, taking the registry from 326 to 332 tools; distinct actions
stay at 63 (no new action: `terminal.create` x58 -> x60,
`workspace.write_file` x44 -> x46, `web.fetch` x3 -> x4,
`workspace.read_file` x58 -> x59). The Slice 17 triage counted 299 true
catalog IDs: 271 registered by exact name, 1 alias-covered
(`conversation_context_manager` via `context_persistence_store`), 1
duplicate (`code_review` of `autonomous_review_engine`), 20 with no real
backend, and these 6 implementable. That triage missed the hyphenated
`plan-AskUser` (line 165 of `AvailableTools.md`), so the true count is
300 catalog entries: 272 registered by exact name before this slice.
This slice registers the 6, so the catalog is now covered 279 of 300
(278 exact + 1 alias-covered); the remaining 21 are 20 NONE plus
1 duplicate.

- `svg_to_png` reuses the exact `sips -s format png` invocation from
  `image_convert_format`, plus `--resampleHeightWidth` when both width
  and height are given and the thumbnail's `-Z` flag when only one is.
  Output is PNG only; the description says complex SVGs can distort at
  small sizes.
- `intel_generate_tests` composes the registered `extract_code_symbols`
  regex extraction with the `code_generate` test template and emits one
  failing test stub per extracted symbol into `testPath`. It refuses to
  overwrite an existing file unless `overwrite: true`, following the
  `ui_test_scaffold` precedent. Template stubs, not LLM-written tests.
- `search_web` fetches `https://html.duckduckgo.com/html/?q=` through
  the existing `g6FetchURL` / `g6_curl_fetch` and extracts result
  titles/URLs with the existing regex helper. Unofficial DuckDuckGo HTML
  scraping, no search API; results may be empty if DDG blocks or changes
  markup; failure is reported, never faked.
- `reverse_analyze` is the narrowed form only: `artifact` composes
  `file` / `otool -L` / `otool -hv` / `codesign --verify` /
  `codesign -dv` (the `mach_o_binary_analyzer` and
  `code_signing_diagnose` primitives, plus top-level plist keys when the
  path ends in `.plist`), `disassembly` is served by `otool -tV`
  (objdump itself is not wired), `demangle` runs
  `xcrun swift-demangle`, and `sqlite_schema` runs the fixed argv
  `sqlite3 <path> .schema`. REA evidence IDs / confidence scores are
  refused honestly (the REA subsystem does not exist), as is Go /
  managed-metadata inspection.
- `report_to_user` is the narrowed form only: it validates a non-empty
  `summary` and appends the completion record to the session-notes
  artifact `.assist_temp/artifacts/agent_notes.md` (the same artifact
  `session_progress_report` reads), returning success as the completion
  signal. The chat reply itself is the actual delivery to the user; the
  tool records the summary and marks the turn complete, it does not
  deliver out-of-band.
- `intel_explain_code` is heuristic-only: it composes the registered
  `code_summary` + `api_surface_extract` + `code_comment_extract` into
  a structural overview (line counts, public declarations, doc
  comments). The catalog's "LLM explanation / Provider hardcoded to
  OpenAI" claim is not reproduced.
- The 20 NONE tools stay unimplemented; see "What is still NOT
  implemented" below for the exact list with reasons.
- Docs corrections in this slice: the stale "~121 PARTIAL" claim is
  replaced with the exact counts above; `AvailableTools.md` corrects the
  `file_write` / `file_create` / `code_generate` pbxproj-registration
  claim (they write the file only; no pbxproj registration exists), the
  Cloud Toolkit section (all 8 of its IDs are now in the local system
  registry — `search_web` was the last, registered here), and the
  `dir_cd` / `use_terminal` `workingDirectory` claim (there is no
  session working-directory state; per-call `cwd` is the mechanism).
- Tests: five new `@Test` functions in `AgentsTests/ToolsetTests.swift`
  (registration of all 6 with actions, channels, parameters, and the
  required honest-description phrases; round-trips for
  `intel_generate_tests`, `report_to_user`, and `intel_explain_code`
  against a real temp workspace; validation refusals for `svg_to_png`,
  `search_web`, `reverse_analyze`, `intel_generate_tests`, and
  `report_to_user`). The MCP integration test now asserts 332 with the
  full name list, and the Rust cross-check test asserts 332. No build or
  test run was performed in this environment; the tests are written, not
  executed.

### Hardening wave (Slices 69–109)

The per-slice log above ends at Slice 18 (the registry build-out). The
hardening slices below did not add registry tools, so they are logged here
instead of as `### Slice N:` entries — one or two lines each: what was
done, how it was verified, verdict. Slices 69–109 only; slices 19–68 have
no entries in this file either and are not backfilled here. Full record:
`docs/HARDENING-AUDIT.md`.

- **Slice 69** — Docs-only: qualified the Slice 11 cross-check claim as
  written-not-executed (commit `53da6d39`). No code change, no test.
- **Slice 71** — MCP server audit: 6 defects fixed (resources/list shape,
  curl redirect/size bounds, symlink-loop sizing, asset symlink/size
  hardening, `use_mcp` arg validation, notification silence); 4 tests
  added in `tests/mcp_server.rs`. Verified by the Slice 73 re-audit, which
  found only 2 follow-up minors.
- **Slice 73** — MCP server follow-ups: 2 defects fixed (additive
  truncation flag for deep dir sizing; asset size bound enforced on the
  read, closing the stat-then-read TOCTOU); 2 tests added. No later slice
  re-opened these paths.
- **Slice 75** — Docs-only: refreshed the MAC-GATE Rust test counts to
  2,940 (commit `e1b148d1`). No code change.
- **Slice 77** — Memory/workers store audit: 5 defects fixed (memory
  entry/byte caps, snapshot self-counting and value-cap bypass, worker
  text cap, WAL file permissions) + 1 dead-code removal; 5 tests added.
  Byte accounting corrected by Slice 79.
- **Slice 79** — Memory byte accounting: 1 defect fixed
  (`memory_total_bytes` counted characters, now bytes); 0 tests, covered
  by the Slice 77 total-byte-cap test.
- **Slice 81** — Claude/Codex provider audit: 2 defects fixed (MCP config
  rewrite failed after the first turn; Claude result-frame error text
  leaked into transcripts); 3 tests added. Symlink-refusal test added in
  Slice 83.
- **Slice 83** — Added the Claude config symlink-refusal test; refreshed
  the MAC-GATE counts to 2,949. No new defect.
- **Slice 85** — Workspace file-ops audit: 2 critical compile breaks
  fixed (restored missing helpers in both crates), `.git` mutation
  refused, atomic new-file writes, honest truncation flags; 3 tests
  added. Corroborated by the Slices 87–90 sweeps (0 confirmed-missing).
- **Slice 87** — Repo-wide Rust undefined-reference sweep, all 6 crates:
  0 CONFIRMED-MISSING in non-test code. No commit.
- **Slice 88** — Docs-only: refreshed the MAC-GATE counts to 2,952
  (commit `8d8deca9`). No code change.
- **Slice 89** — Swift undefined-symbol sweep, Agents target:
  0 CONFIRMED-MISSING. No commit.
- **Slice 90** — Swift undefined-symbol sweep, remaining 5 targets:
  0 CONFIRMED-MISSING. No commit.
- **Slice 91** — Consolidated hardening-audit record for Slices 71–90
  (`docs/HARDENING-AUDIT.md`, commit `11097655`). Docs-only.
- **Slice 92** — No commit in the repo and no record in docs; nothing
  verifiable to log.
- **Slice 93** — Docs-only: fixed the Slice 81 citation line in
  `HARDENING-AUDIT.md` and corrected the MAC-GATE desktop test count
  (commit `1e65a098`).
- **Slice 95** — Thread/document store audit: 1 defect fixed (case-variant
  draft patch resolves the canonical thread id); 2 dead store helpers
  removed (`Store::archived_conversations`, `Store::message_matches`);
  1 regression test added
  (`draft_patch_accepts_a_case_variant_thread_id`). Statically verified
  only; Slice 96 confirmed the remote tree.
- **Slice 99** — Computer-use engine audit: `with_session_defaults` now
  overwrites a model-supplied `threadId` with the session thread id when
  bound (was fill-if-absent); dead `Extended::tool()` and
  `Bridge::threads()` removed; 1 test added
  (`session_thread_identity_wins_over_model_supplied_thread_id`).
- **Slice 100** — MCP worker identity pin: `default_parent_thread` now
  overwrites a model-supplied `parentThreadId` when bound; `list_workers`
  and `intel_breakdown_task` newly routed through it (spawn/plan/
  execution-plan and `start_subagent` already were); 1 test added. The
  worker paragraph in this file now states the pin.
- **Slice 101** — Swift-side parent identity pin:
  `SystemToolRegistry.execute` takes opt-in `sessionThreadId` and
  overwrites model-supplied `threadId` / `parentThreadId` with it,
  threaded through the `use_mcp` recursion; 4 tests added in
  `AgentsTests/WorkersTests.swift`. The worker paragraph in this file now
  records the Swift mirror pin.
- **Slice 102** — Read-only verification of the Swift registry: NOT CLEAN
  — found the pre-existing HIGH type error (three plan cases returned
  `WorkerPlan` where `execute()` promises `JSONValue`). No commit; fixed
  in Slice 103.
- **Slice 103** — Fixed the Slice 102 type error: new `workerPlanJSON`
  helper wraps the `planTask` / `breakdownTask` / `executionPlan`
  results; all 275 returns in `execute()` audited. No test added.
  Re-verified by Slice 104.
- **Slice 104** — Read-only re-verification of Slice 103: PASS WITH
  MINORs — corrected the Rust test-attribute total to 3,000 (2,219
  short-form + 736 fully-qualified + 45 `#[gpui_kit::test]`); noted
  MAC-GATE.md staleness, fixed in Slice 105. No commit.
- **Slice 105** — Joint Swift/Rust threadId description pass: registry
  param descriptions corrected to the pinned behavior ("…, pinned to
  the session thread when bound."); the pinned expectations in
  `AgentsTests/ToolsetTests.swift` updated to match. Docs refresh:
  MAC-GATE 128/3,000, hardening log 99–103.
- **Slice 106** — Read-only inventory of thread-identity descriptions:
  123 threadId + 6 parentThreadId params; only 2 of 6 parentThreadId
  pinned (`use_workers`, `start_subagent`) — the other four lacked
  pinning language until Slice 107 — and 122 of 123 threadId pinned,
  `session_progress_report` the one threadId gap. No commit; closed in
  Slice 109.
- **Slice 107** — Pinned the four remaining parentThreadId descriptions
  without pinning language (`list_workers`, `intel_plan_task`,
  `intel_breakdown_task`, `execution_plan`); fixed two hardening-audit
  nits (the `use_mcp` line cite, the ToolDef-count wording). No test
  change.
- **Slice 108** — Read-only re-verification of Slice 107: PASS, zero
  findings; one informational observation — `session_progress_report`
  threadId still unpinned. No commit; closed in Slice 109.
- **Slice 109** — Full re-enumeration of all 129 thread-identity params
  per side (123 threadId + 6 parentThreadId): only
  `session_progress_report` lacked pinning language; its description now
  reads "Parent thread ID to include worker status for, pinned to the
  session thread when bound." on both sides. No behavior change, no test
  change; registry counts unchanged at 332.

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
- `tools/list` — the real 332-tool registry, with the same names, descriptions,
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
callers share one implementation). Desktop-channel tools that are engine
methods (memory, workers) and engine-channel tools (terminal, git,
build/test) go over the control socket
(`<data_dir>/control.sock`) to the LIVE engine — no second Engine, no
shared-store hazard — replicating the Swift registry's polling loops
(`workspace.result` for git status/diff, `git.actions.result` for git
actions, the `__AGENTS_TOOL_DONE__:$?` sentinel for build/test). Worker
spawn/plan/list/breakdown calls always run under the session thread id: a
model-supplied `parentThreadId` is overwritten with it, and standalone servers
without a session id keep the supplied value. The Swift
`SystemToolRegistry.execute` mirror pins the same way when a caller supplies
`sessionThreadId`: model-supplied `threadId` and `parentThreadId` are
overwritten with it, and calls without one keep the supplied values. A tool call
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
- `SystemToolRegistry` (Swift) registers exactly 332 tools in 63 distinct
  actions, each mapped to a real core action; the Rust MCP server table in
  `Rust Backend/crates/coincide-mcp-server/src/tools.rs` carries the same 332
  names, actions, and channels, and the Rust cross-check test asserts the two
  tables match exactly (see "The 332-tool registry" above). Production
  execution is the MCP server's `tools/call`, not the Swift registry's
  `execute()`. Slice 1 added seventeen more tools to the original set, all
  real:
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
    - Store design: one row per entry in the SQLite `memory_entries` table
      (`coincide-core/src/memory_store.rs`), with a composite key
      (`composite_key` primary key), a `scope`, and the entry JSON holding
      `{key, scope, value, updatedAt}`; the composite key is the scope, a
      unit-separator character, and the key. Entries survive restarts; the
      Rust and Swift round-trip tests reopen the store and read the entry
      back. A pre-Slice-15 `memory.json` document in the `documents` table
      is migrated once, transactionally, into `memory_entries` on open
      (`coincide-core/src/store.rs`); a document that cannot be parsed is
      quarantined under a `memory.json.corrupt` name so the migration does
      not re-attempt on every open, and its bytes are preserved.
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
  - Workers, as engine methods `workers.spawn` / `workers.list` /
    `workers.status` / `workers.result` / `workers.cancel` / `workers.plan` /
    `workers.breakdown` / `workers.execution_plan` (`use_workers`,
    `list_workers`, `worker_status`, `worker_result`, `cancel_worker`,
    `intel_plan_task`, `intel_breakdown_task`, `execution_plan`). Slice 4
    added eight, all real:
    - Worker design: a worker is a real provider turn on its own thread, not
      a second worker system. `workers.spawn` creates a child thread with
      `threads.create`, copying the parent's project, working directory,
      provider selection, access mode, interaction mode, system prompt, and
      toolset, then starts the turn with `agent.send` carrying the worker's
      task (at most 500 characters, per the catalog) plus its target files.
      The worker record lives in the SQLite `worker_records` table
      (`coincide-core/src/worker_store.rs`): id, name, parent thread id,
      child thread id, task, provider, target files, status, cancel flag,
      transcript start index, transcript item count, elapsed seconds,
      created/completed timestamps, error, and the cached result. Records
      survive restarts; the Rust and Swift round-trip tests reopen the
      store and read plans back.
    - Validation, per the catalog: worker names are unique among a parent's
      running workers, tasks are at most 500 characters, and `targetFiles`
      must be disjoint across a parent's running workers and within one
      `use_workers` batch. A batch may spawn at most 32 workers, and a
      parent may have at most 32 running workers. A spawn on a thread using
      a named Codex profile is refused: a per-thread system prompt cannot
      ride a named profile session. If the turn fails to start after the
      child thread is created, the spawn fails and the empty child thread
      remains as an ordinary thread; no worker record is written.
    - Lifecycle and progress: status is refreshed on every list/status/
      result call from the real engine state, never from a timer. A worker
      is `running` while its child thread is in the engine's run table.
      When the run is gone, the outcome comes from the engine's turn
      results (`completed` / `failed` / `interrupted`), falling back to
      the child transcript: assistant items after the spawn point mean
      completed, an `error` item means failed. The result is the joined
      text of the worker's assistant transcript items after the spawn
      point, read from the real thread document — the parent collects it
      with `worker_result`. `progress` is a stage marker, not a completion
      percentage: stage (`running` / `completed` / `failed` / `cancelled`),
      transcript item count since spawn, and elapsed seconds. There is no
      per-turn percent anywhere in the engine, so none is reported.
    - Cancellation, honestly: `cancel_worker` sends the same
      `Control::Stop` the Stop button sends (`agent.stop` /
      `request_provider_stop`) to the worker's provider turn, then marks
      the record `cancelled` and stops polling it. That is a stop request,
      not a kill: the provider winds down on its own schedule, and the
      record stays cancelled even if the transcript gains a late item.
      There is no safe cancellation protocol for background jobs
      (`background_workers.rs` says so explicitly), and no worker cancel
      claims one. Grok is the one provider whose stop kills the process
      tree; the others interrupt the turn. Cancelling a worker that already
      finished is a no-op returning the terminal record.
    - Restart edge: turn results are session-only. A worker whose turn
      finished in an earlier engine session is recovered from its
      transcript (assistant items mean completed, an error item means
      failed). A worker with no outcome and no transcript growth after a
      restart is reported `failed` with the restart stated as the reason.
    - Plans are a mechanical decomposition, not LLM planning, per the
      catalog's own Known Limitations. `intel_plan_task` splits the task
      into sentences, packs them into steps of at most 500 characters (at
      most 16 steps), and stores the plan in the `worker_plans` table. A
      pre-Slice-15 `workers.json` document in the `documents` table is
      migrated once, transactionally, into `worker_records` / `worker_plans`
      on open; a document that cannot be parsed is quarantined under a
      `workers.json.corrupt` name so the migration does not re-attempt on
      every open, and its bytes are preserved.
      `intel_breakdown_task` expands each step by splitting on `;`, then
      `, `, capped at 3 sub-steps per step; a step with no separators stays
      one step. A plan is a list of worker tasks the parent can spawn: each
      step carries an empty `targetFiles` until the parent assigns disjoint
      files. `execution_plan` builds the same mechanical plan, counts
      listed files in the parent working directory (git-tracked plus
      untracked, via `git ls-files`) and how many match objective keywords,
      and writes the plan markdown to `agent_notes.md` in that directory.
      The counts are listed files, not inspected files.
    - UI: Inspector › Workers lists workers for the current thread or all
      workers, with live status, provider, elapsed time, and update count;
      a spawn form (name, task with a 500-character counter, comma-separated
      target files); per-worker detail with the real result or error and a
      cancel button; and a plan form (draft plan, expand steps, execution
      plan). Everything reads the real store through the FFI `workers.*`
      actions; there is no mock data anywhere in the view.
  No Qwen tool is imported: `AvailableTools.md` describes Qwen's tools, not this repo's.

- Computer Use (slice 5): the 20-tool typed catalog in
  `coincide-core/src/computer_use.rs` is wired into the Swift app for real.
  The engine owns the broker: `computer_use.request` admits one pending
  request per thread (queue capacity 8, 10-second deadline, 30-second
  result retention) and `computer_use.result` collects it; the FFI mounts
  a `Pump` thread (`coincide-macos-ffi/src/computer_use_ffi.rs`) that
  `#[path]`-includes the Rust desktop's `computer_use.rs` as its runtime
  (one source of truth, no duplicate executor) and drains the engine queue
  into the native macOS executor (`coincide-desktop/src/computer_use_macos.m`:
  ScreenCaptureKit screenshots, Accessibility element control, CGEvent
  input). The FFI runtime marks the engine `ui_available` at open, because
  the FFI runtime exists only for the Swift desktop app; without that flag
  every request failed with "Computer Use requires the desktop window".
  - Wired tools (all 20, action `computer_use.request`, channel `engine`,
    registered in both the Swift `SystemToolRegistry` and the MCP server,
    which cross-check each other): observation `list_apps`, `list_windows`,
    `get_window_state`, `get_desktop_state`, `verify_state`, `zoom`;
    input `click`, `double_click`, `right_click`, `set_value`, `type_text`,
    `press_key`, `hotkey`, `scroll`, `drag`, `move_cursor`, `click_point`;
    app and window control `invoke_menu`, `launch_app`, `set_window_frame`.
    Each executes through the real engine dispatch: submit
    `computer_use.request` with `{"action":"call","name":<tool>,
    "arguments":{...}}`, poll `computer_use.result` until ready (up to 15
    seconds; the engine deadline is 10 seconds). Required arguments are
    validated against the tool's own definition before any runtime call.
    The catalog IDs are the real ones. Two more registered tools share the
    `computer_use.request` action without being catalog entries:
    `take_screenshot` delegates to `get_desktop_state` with
    `include_screenshot`, and `use_app` dispatches action names onto the
    catalog tools, erroring honestly on the nine actions with no engine tool
    (`activate`, `close_application`, `select_window`,
    `get_focused_element`, `select_all`, `copy`, `paste`,
    `wait_for_element`, `wait_for_window`).
  - Screenshots are filed by the engine as 0600 PNG files, newest 32 per
    thread, and listed by the new `computer_use.screenshots` engine method.
    The Inspector › Computer Use tab lists them and shows the real files;
    there are no placeholder images.
  - Approvals: a master enable switch (Settings › Computer Use only;
    `settings.patch` refuses the `computerUseEnabled` key), per-thread
    grant epochs with revocation, and the macOS TCC prompts for
    Accessibility and Screen Recording. There is no per-action approval
    dialog: turning Computer Use on and granting a thread is the approval,
    and every manual action in the app is approved by the button press
    that starts it. No new entitlement was needed: screen capture and
    Accessibility are TCC permissions, not entitlements. The Mac gate must
    grant both permissions on Dylan's Mac; nothing here can grant them.
  - UI: Settings › Computer Use (enable toggle, live state, per-permission
    Grant Access buttons, honest limits) and Inspector › Computer Use
    (thread-scoped status banner, run-a-tool form with the 20-tool picker
    and JSON arguments editor, latest result, screenshots list/viewer, and
    in-memory action history for the session).
  - NOT wired: screen recording. `take_screenrecord` does not exist
    anywhere in the engine and is not registered; it would need a whole
    new ScreenCaptureKit recorder.

- Git history and branch compare (slice 6): four engine methods on the same
  async workspace channel as `git.status` / `git.diff`, polled through
  `workspace.result`, all reading the repository through the core's hardened
  git runner (the `git` binary, hooks disabled, no network) — never shelled
  out from Swift:
  - `git.log` — commit list for the current branch, newest first, with
    pagination (`limit` 1–200, `skip`). Each commit carries its SHA, parents,
    author name and email, author date as a unix timestamp, subject, and
    body. Implemented in `coincide-core/src/workspace.rs` as `log`, parsing
    `git log --format=` output split on record/field separators.
  - `git.show` — one commit by full SHA: metadata, changed files with
    additions/deletions (from `--name-status` plus `--numstat`), and the full
    patch (capped at 2 MiB, reported as `truncated`). Merge commits list no
    files, because `git show` reports no name-status for a merge; the patch
    is git's combined diff.
  - `git.diff.range` — three-dot compare of two references (`from...to`,
    merge base of `from` against `to`). Both references are resolved to
    commit OIDs first, so only real commits are compared, and the response
    reports the resolved OIDs. Returns changed files and the full patch.
  - `git.diff.branch` — the working tree against the base the branch left,
    reusing the `workspace_diff::review` `Branch` scope the core already had
    but the UI never wired.
  - Registered as `git_log`, `git_show`, `git_diff_range`, and
    `git_diff_branch` in both the Swift registry and the MCP server.
  - UI: Inspector › Git has a History card (50 commits per page, tap a
    commit for its files and diff) and a Worktrees card (read-only list from
    the existing `git.worktrees.list`); Inspector › Changes gains a Branch
    vs Base scope and a Compare Branches scope with branch pickers. The
    branch card's existing switch/create/worktree controls are unchanged.
  - Checkpoint restore: a turn checkpoint's Restore button rewinds the
    conversation to before that turn's user message and restores workspace
    files to the checkpoint, through the real `rewind` call with
    `revertFiles: true`, behind an explicit confirmation that later
    messages are removed. Manual staged checkpoints have a Restore button
    too (Slice 10): it calls `git.checkpoints.restore` through the
    workspace API behind the same confirmation pattern, and it resets the
    working tree with `reset --hard` plus `clean -fdx`, so untracked and
    ignored files are removed as well.
  - File delete/rename in the Files inspector uses Slice 1's real FFI
    actions (`workspace.delete_file`, `workspace.delete_directory`,
    `workspace.move_file`) with a confirmation dialog for delete; a
    directory delete offers empty-only or recursive, and renaming the open
    file with unsaved edits is refused until the edits are saved or
    reverted.

## What is still NOT implemented (honest list)

The 300-entry catalog in `AvailableTools.md` is a specification, not a
registry. After slice 18, 332 tools are real. These catalog tools are NOT
implemented, and why:

- Memory (`manage_memory`, `conversation_context_manager`):
  `manage_memory` is now real (Slice 14) as a SQLite KV dispatcher —
  store/edit/append/delete/clear/list via the runtime memory client. It
  has no sections and no `UserMemory.md` file; the Slice 3 note saying it
  was unimplemented because that file does not exist is superseded — the
  file still does not exist, and the tool does not pretend it does.
  `save_to_memory` is now real as `memory.store`.
  `conversation_context_manager` describes a per-conversation
  context file; no such file backend exists, so it is unavailable.
  `mem_store`, `mem_retrieve`, `mem_clear`, `mem_context_snapshot`,
  `context_persistence_store`, and `view_memory` are real — see the
  Enforcement boundary above.
- Workers: `start_subagent` is now real as `workers.spawn` (alias of
  `use_workers`). There is no separate cloud runtime; `use_workers` is
  real — see the Enforcement boundary above — as are `intel_plan_task`,
  `intel_breakdown_task`, and `execution_plan` in their honest mechanical
  form. `list_workers`, `worker_status`, `worker_result`, and
  `cancel_worker` have no catalog IDs; they are the lifecycle tools this
  slice added so the parent can observe and collect workers through tool
  calls.
- Computer use (`use_app`, `take_screenrecord`): `take_screenshot` is now
  real as `computer_use.request` (`get_desktop_state` with
  `include_screenshot`). `use_app` is now real (Slice 14) in narrowed
  form: it dispatches only the 20 real computer-use actions and errors
  honestly on the 9 missing ones (`activate`, `close_application`,
  `select_window`, `get_focused_element`, `select_all`, `copy`, `paste`,
  `wait_for_element`, `wait_for_window`) — see the Enforcement boundary
  above. `take_screenrecord` needs a whole new ScreenCaptureKit recorder
  and is unavailable.
- Artboards ×8, `use_extension`, `use_composio`: whole subsystems or
  external services that do not exist in this repo. Out of scope for the
  10-hour program. `reverse_analyze` and `report_to_user` are now real
  (Slice 18) in narrowed form — CLI-composition inspection and
  session-notes completion recording, respectively — and no longer belong
  in this list.
  `search_skills` is now real (Slice 14): it searches only the bundled
  SystemAssets index via `SystemAssetManager.shared.search` — the
  catalog's indexed skills library does not exist in this repo, and the
  tool never claims otherwise. This supersedes the Slice 10 note that
  said no skills-library backend exists. What also exists is the composer
  `$` skills picker (`composer_suggestions.rs`, skills reported by agent
  sessions) and the SystemAssets `Skills.md` discovery discipline.
- LLM tools (`intel_autofix`, `code_review`, `task_runner`): there is no
  LLM client in the core. `intel_autofix` would need one;
  `code_review` is a duplicate of the registered
  `autonomous_review_engine`; `task_runner` has no task registry to
  execute against. `intel_generate_tests` and `intel_explain_code` are
  now real (Slice 18) in narrowed honest form — template stubs from
  regex-extracted symbols, and a structural overview from regex scans —
  neither uses an LLM client. Out of scope.
- `project_mutation_controller`, `project_target_add`, `test_target_add`:
  no pbxproj writer exists anywhere; `file_write` does not register files
  in Xcode projects. This is the riskiest missing primitive; it is not
  faked here.
- Git gaps: `git_stash_operator`, `git_blame_inspector`, `git_bisect`,
  `git_cherry_pick`, and rollback (through `version_control_operator`) are
  now real engine methods, and `git_log_viewer` is real as `git.log` /
  `git.show`, `git_branch_compare` as `git.diff.range` plus the branch
  scope, and `git_branch_manager` delete as `git.branches.delete` — see
  the registry table above. Still missing, with no engine method and
  nothing faked: switching to another existing worktree. The engine has
  `git.worktrees.useExisting`, but the Swift checkout action enum exposes
  only local/new/previous worktrees, so the Worktrees card is a read-only
  list until that action is wired.
- Everything else in the catalog: exact counts after Slice 18. The
  catalog has 300 entries. 279 are covered: 278 registered by exact
  name (272 before this slice, plus the 6 registered by this slice:
  `svg_to_png`, `intel_generate_tests`, `search_web`,
  `reverse_analyze`, `report_to_user`, `intel_explain_code`), and 1
  alias-covered (`conversation_context_manager` via the registered
  `context_persistence_store`). The remaining 21 are 20 with no real
  backend (NONE) plus 1 duplicate (`code_review`, a duplicate of the
  registered `autonomous_review_engine`). Entries are counted by
  bullet: one entry per ``- `id` `` line in `AvailableTools.md`,
  excluding the prose bullet at line 176 (the `safe_undo` note under
  Known Limitations); the line-487 bullet carries a second ID,
  `read_url_content`, so counting IDs instead of bullets gives 301 IDs
  with 280 covered. The 20 NONE tools, with reasons:
  - Artboards ×8 (`artboard_list`, `artboard_get`, `artboard_create`,
    `artboard_update`, `artboard_delete`, `artboard_compile`,
    `artboard_run_app`, `fix_artboards`): no Visual UI Builder
    subsystem exists.
  - `code_refactor`, `intel_autofix`: no LLM client in the core.
  - `task_runner`: no task registry to execute against.
  - `project_mutation_controller`, `project_target_add`,
    `test_target_add`: no pbxproj writer exists anywhere.
  - `use_composio`, `use_extension`: no Composio integration and no
    Extensions v2 platform exist.
  - `take_screenrecord`: no ScreenCaptureKit recorder exists.
  - `dir_cd`, `dir_pwd`: no session working-directory state exists;
    per-call `cwd` is the mechanism.
  - `create_new_app`: no app scaffold, no out-of-workspace write, and
    no session switch exist.
  The heuristic "intelligence" tools (`complexity_analysis`,
  `autonomous_review_engine`, `semantic_query_engine`, `code_summary`,
  `code_lint`, `runtime_diagnostics_engine`) are implemented — as
  keyword/regex scans, exactly as the catalog describes them; see
  "Heuristic scans" below. They are not semantic analysis, and their
  names still overpromise relative to what they do.
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
