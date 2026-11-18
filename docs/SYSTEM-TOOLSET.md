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
  `coincide-mcp-server` stdio server, which serves the 200 system tools plus
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

## The 200-tool registry

Every tool in `Agents/Core/SystemTools/SystemToolRegistry.swift`, verified row by row against the MCP server table in `Rust Backend/crates/coincide-mcp-server/src/tools.rs` (same names, actions, and channels, in the same order). 200 tools, 54 distinct actions: several tools share one action (`workspace.write_file` x32, `computer_use.request` x21, `terminal.create` x49, `workspace.read_file` x15, `workspace.read_dir` x7, `workspace.edit_file` x5, `workspace.move_file` x4, `git.log` x3, `workspace.delete_file` x3, `workspace.copy_file` x3, `workspace.search_regex` x3, `workspace.files` x2, `workspace.search` x2, `git.diff` x2, `git.diff.range` x2, `workspace.delete_directory` x2, `workspace.create_dir` x2, `git.actions.run` x2, `git.branches.list` x2, `memory.store` x2, `memory.snapshot` x2, `workers.spawn` x2, `git.checkpoints.restore` x2, plus 31 single-tool actions).

| Tool | Action | Channel | Real backend |
| --- | --- | --- | --- |
| `read_file` | `workspace.read_file` | desktop | FFI `workspace.read_file` arm -> `coincide_core::workspace_tools::read_file` |
| `write_file` | `workspace.write_file` | desktop | FFI `workspace.write_file` arm -> `coincide_core::workspace_tools::write_file` |
| `list_files` | `workspace.files` | desktop | FFI `workspace.files` arm -> `coincide_core::workspace_tools::files` |
| `search_files` | `workspace.search` | desktop | FFI `workspace.search` arm -> `coincide_core::workspace_tools::search` |
| `create_terminal` | `terminal.create` | engine | Engine RPC `terminal.create` on the live engine |
| `write_terminal` | `terminal.write` | engine | Engine RPC `terminal.write` on the live engine |
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
| `mem_store` | `memory.store` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::store_entry` (SQLite `memory.json`) |
| `mem_retrieve` | `memory.retrieve` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::retrieve_entry` (SQLite `memory.json`) |
| `view_memory` | `memory.list` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::list_entries` (SQLite `memory.json`) |
| `mem_delete` | `memory.delete` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::delete_entry` (SQLite `memory.json`) |
| `mem_clear` | `memory.clear` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::clear_scope` (SQLite `memory.json`) |
| `mem_context_snapshot` | `memory.snapshot` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::snapshot_context` (SQLite `memory.json`) |
| `context_persistence_store` | `memory.context_store` | desktop | FFI `memory.*` arm -> `coincide_core::memory_store::context_store` (SQLite `memory.json`) |
| `use_workers` | `workers.spawn` | desktop | FFI `workers.*` arm -> `Engine::workers_spawn` (record in SQLite `workers.json`) |
| `list_workers` | `workers.list` | desktop | FFI `workers.*` arm -> `Engine::workers_list` (record in SQLite `workers.json`) |
| `worker_status` | `workers.status` | desktop | FFI `workers.*` arm -> `Engine::workers_status` (record in SQLite `workers.json`) |
| `worker_result` | `workers.result` | desktop | FFI `workers.*` arm -> `Engine::workers_result` (record in SQLite `workers.json`) |
| `cancel_worker` | `workers.cancel` | desktop | FFI `workers.*` arm -> `Engine::workers_cancel` (record in SQLite `workers.json`) |
| `intel_plan_task` | `workers.plan` | desktop | FFI `workers.*` arm -> `Engine::workers_plan` (record in SQLite `workers.json`) |
| `intel_breakdown_task` | `workers.breakdown` | desktop | FFI `workers.*` arm -> `Engine::workers_breakdown` (record in SQLite `workers.json`) |
| `execution_plan` | `workers.execution_plan` | desktop | FFI `workers.*` arm -> `Engine::workers_execution_plan` (record in SQLite `workers.json`) |
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
| `use_terminal` | `terminal.create` | engine | Creates a real terminal, runs the command, polls `terminal.read` for the `__AGENTS_TOOL_DONE__:$?` sentinel |
| `run_command` | `terminal.create` | engine | Same as `use_terminal` |
| `git_log_viewer` | `git.log` | engine | Engine `git.log`, async workspace channel polled via `workspace.result` |
| `git_branch_compare` | `git.diff.range` | engine | Engine `git.diff.range`, async workspace channel polled via `workspace.result` |
| `project_diff` | `git.diff` | engine | Engine `git.diff`, async workspace channel polled via `workspace.result` |
| `git_branch_manager` | `git.branches.list` | engine | Dispatches on `action`: list/create/checkout/delete via Engine `git.branches.*`, polled via `git.actions.result`; delete requires `confirm=true` |
| `save_to_memory` | `memory.store` | engine | Engine RPC `memory.store` on the live engine |
| `use_mcp` | `mcp.tools` | engine | Meta-tool over the live registry: `list` / `list_tools` / recursive `SystemToolRegistry.execute`; only the `coincide` server exists |
| `take_screenshot` | `computer_use.request` | engine | Engine `computer_use.request` (`get_desktop_state` with `include_screenshot`), polled via `computer_use.result`; FFI Pump drains it into the native macOS executor |
| `start_subagent` | `workers.spawn` | engine | Engine RPC `workers.spawn` on the live engine (alias of `use_workers`) |
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
  and the cross-check passes exactly.

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
- `tools/list` — the real 200-tool registry, with the same names, descriptions,
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
spawn/plan calls that omit `parentThreadId` default to the session thread id.
A tool call
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
- `SystemToolRegistry` (Swift) registers exactly sixty-five tools, each mapped to a
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
      The worker record lives in the same SQLite `documents` table as
      memory, under `workers.json`
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
      most 16 steps), and stores the plan under `workers.json`.
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
    The catalog IDs are the real ones: there is no `take_screenshot` or
    `use_app` tool. Screenshots are taken by `get_window_state` /
    `get_desktop_state` with `include_screenshot`, and apps are launched by
    `launch_app`.
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

The 300-ID catalog in `AvailableTools.md` is a specification, not a
registry. After slice 12, 200 tools are real. These catalog tools are NOT
implemented, and why:

- Memory (`manage_memory`, `conversation_context_manager`):
  not registered as separate tools. `save_to_memory` is now real as
  `memory.store`. `manage_memory` describes writing to a `UserMemory.md`
  file, which does not exist in this repo; its real function is covered by
  `mem_store`, `mem_delete`, and `mem_clear` against the SQLite memory
  store. `conversation_context_manager` describes a per-conversation
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
  `include_screenshot`). `use_app` has no engine tool. The real 21
  computer-use tools are wired — see the Enforcement boundary above.
  `take_screenrecord` needs a whole new ScreenCaptureKit recorder and is
  unavailable.
- Artboards ×8, `use_extension`, `reverse_analyze`, `use_composio`,
  `report_to_user`: whole subsystems or external services that do not
  exist in this repo. Out of scope for the 10-hour program.
  `search_skills` is not a registered tool either: the catalog's indexed
  skills library does not exist in this repo. What exists is the composer
  `$` skills picker (`composer_suggestions.rs`, skills reported by agent
  sessions) and the SystemAssets `Skills.md` discovery discipline; the
  catalog function is reachable by `search_text` / `file_read` composition
  over workspace `SKILL.md` files, but there is no skills-library backend,
  so it is not claimed as implemented.
- LLM tools (`intel_autofix`, `intel_generate_tests`, `intel_explain_code`,
  `code_review`, `task_runner`): there is no LLM client in the core. Out of
  scope.
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
- Everything else in the catalog (~247 IDs) stays PARTIAL: reachable in
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
