import CoincideRemoteKit
import Foundation

public nonisolated struct SystemToolParameter: Codable, Hashable, Sendable {
    public var name: String
    public var type: String
    public var required: Bool
    public var description: String

    public init(name: String, type: String, required: Bool, description: String) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
    }
}

public nonisolated enum SystemToolChannel: String, Codable, Sendable {
    case desktop
    case engine
}

public nonisolated struct SystemToolDefinition: Codable, Hashable, Sendable {
    public var name: String
    public var description: String
    public var action: String
    public var channel: SystemToolChannel
    public var parameters: [SystemToolParameter]

    public init(name: String, description: String, action: String, channel: SystemToolChannel, parameters: [SystemToolParameter]) {
        self.name = name
        self.description = description
        self.action = action
        self.channel = channel
        self.parameters = parameters
    }
}

public nonisolated enum SystemToolError: LocalizedError, Equatable, Sendable {
    case unknownTool(String)
    case toolNotActive(tool: String, toolset: AgentToolset)
    case missingArgument(tool: String, argument: String)
    case executionFailed(tool: String, message: String)
    case operationTimeout(tool: String)

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            "Unknown system tool \"\(name)\"."
        case .toolNotActive(let tool, let toolset):
            "System tool \"\(tool)\" is not active under the \(toolset.title) toolset."
        case .missingArgument(let tool, let argument):
            "System tool \"\(tool)\" is missing required argument \"\(argument)\"."
        case .executionFailed(let tool, let message):
            "System tool \"\(tool)\" failed: \(message)"
        case .operationTimeout(let tool):
            "System tool \"\(tool)\" did not finish in time."
        }
    }
}

public nonisolated enum SystemToolRegistry {
    public static let systemTools: [SystemToolDefinition] = [
        SystemToolDefinition(
            name: "read_file",
            description: "Read a file in the thread working directory.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "write_file",
            description: "Write a file in the thread working directory.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "content", type: "string", required: true, description: "Full file content."),
            ]
        ),
        SystemToolDefinition(
            name: "list_files",
            description: "List files in the thread working directory.",
            action: "workspace.files",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "query", type: "string", required: false, description: "Substring filter for file paths."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum files to return."),
            ]
        ),
        SystemToolDefinition(
            name: "search_files",
            description: "Search file contents in the thread working directory.",
            action: "workspace.search",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "query", type: "string", required: true, description: "Text to search for."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "create_terminal",
            description: "Create an integrated terminal for a thread.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: false, description: "Owning thread ID."),
            ]
        ),
        SystemToolDefinition(
            name: "write_terminal",
            description: "Send input to an integrated terminal.",
            action: "terminal.write",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "terminalId", type: "string", required: true, description: "Terminal ID from create_terminal."),
                SystemToolParameter(name: "text", type: "string", required: true, description: "Text to send."),
            ]
        ),
        SystemToolDefinition(
            name: "read_terminal",
            description: "Read an integrated terminal viewport snapshot.",
            action: "terminal.read",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "terminalId", type: "string", required: true, description: "Terminal ID from create_terminal."),
            ]
        ),
        SystemToolDefinition(
            name: "git_status",
            description: "Read git working-tree status for a thread.",
            action: "git.status",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
            ]
        ),
        SystemToolDefinition(
            name: "git_diff",
            description: "Read the git diff for a thread.",
            action: "git.diff",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Single file path to diff."),
                SystemToolParameter(name: "staged", type: "boolean", required: false, description: "Diff staged changes instead of the worktree."),
            ]
        ),
        SystemToolDefinition(
            name: "git_log",
            description: "List git commits for a thread working directory, newest first, with author, date, message, and parents.",
            action: "git.log",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum commits to return, 1–200. Defaults to 50."),
                SystemToolParameter(name: "skip", type: "integer", required: false, description: "Commits to skip for pagination. Defaults to 0."),
            ]
        ),
        SystemToolDefinition(
            name: "git_show",
            description: "Show one git commit for a thread working directory: its metadata, changed files, and full diff.",
            action: "git.show",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "sha", type: "string", required: true, description: "Full 40- or 64-character commit SHA."),
            ]
        ),
        SystemToolDefinition(
            name: "git_diff_range",
            description: "Diff two git references for a thread working directory, comparing the merge base of the first against the second, with changed files and the full patch.",
            action: "git.diff.range",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "from", type: "string", required: true, description: "Base reference, such as a branch name or commit SHA."),
                SystemToolParameter(name: "to", type: "string", required: true, description: "Reference to compare against the base, such as a branch name or commit SHA."),
            ]
        ),
        SystemToolDefinition(
            name: "git_diff_branch",
            description: "Diff the thread branch working tree against the base it branched from, with the full patch.",
            action: "git.diff.branch",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
            ]
        ),
        SystemToolDefinition(
            name: "delete_file",
            description: "Delete a file in the thread working directory. Refuses directories and symlinks.",
            action: "workspace.delete_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "delete_directory",
            description: "Delete a directory in the thread working directory. Without recursive=true only an empty directory is removed.",
            action: "workspace.delete_directory",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "recursive", type: "boolean", required: false, description: "Remove the directory and everything inside it."),
            ]
        ),
        SystemToolDefinition(
            name: "move_file",
            description: "Move or rename a file or directory inside the thread working directory. The destination must not already exist.",
            action: "workspace.move_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "destination", type: "string", required: true, description: "Destination path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "copy_file",
            description: "Copy a file inside the thread working directory. The destination must not already exist.",
            action: "workspace.copy_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "destination", type: "string", required: true, description: "Destination path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "create_directory",
            description: "Create a directory, including missing parents, in the thread working directory.",
            action: "workspace.create_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "read_directory",
            description: "List directory entries in the thread working directory with a real directory read, including files git ignores.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory relative to the working directory; defaults to the working directory itself."),
                SystemToolParameter(name: "recursive", type: "boolean", required: false, description: "List entries recursively, up to 16 levels deep."),
            ]
        ),
        SystemToolDefinition(
            name: "edit_file",
            description: "Replace anchored text in a file. The anchor must match exactly once or the edit fails; the file is re-read after writing to verify the result.",
            action: "workspace.edit_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "oldText", type: "string", required: true, description: "Exact text to match, exactly once."),
                SystemToolParameter(name: "newText", type: "string", required: true, description: "Replacement text."),
                SystemToolParameter(name: "mode", type: "string", required: false, description: "replace, insertAfter, or insertBefore. Defaults to replace."),
            ]
        ),
        SystemToolDefinition(
            name: "multi_edit_file",
            description: "Apply several anchored edits to one file, in order. Every anchor must match exactly once at the time it is applied or the whole edit fails.",
            action: "workspace.edit_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "edits", type: "array", required: true, description: "Edits to apply, each with oldText, newText, and an optional mode."),
            ]
        ),
        SystemToolDefinition(
            name: "search_regex",
            description: "Search file contents with a regular expression. Runs ripgrep in regex mode when installed, otherwise a real regex scan. An invalid pattern is an error.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "pattern", type: "string", required: true, description: "Regular expression to search for."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "run_build",
            description: "Run a build command in the thread's integrated terminal and return its real output and exit code. The output is the final terminal viewport, not full scrollback.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID; the terminal starts in the thread working directory."),
                SystemToolParameter(name: "command", type: "string", required: true, description: "Build command to run, for example xcodebuild -scheme MyApp build."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command. Defaults to 600."),
            ]
        ),
        SystemToolDefinition(
            name: "run_tests",
            description: "Run a test command in the thread's integrated terminal and return its real output and exit code. The output is the final terminal viewport, not full scrollback.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID; the terminal starts in the thread working directory."),
                SystemToolParameter(name: "command", type: "string", required: true, description: "Test command to run, for example xcodebuild test -scheme MyApp or cargo test."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command. Defaults to 600."),
            ]
        ),
        SystemToolDefinition(
            name: "git_commit",
            description: "Commit the thread working-tree changes with the given message, using the engine git action runner.",
            action: "git.actions.run",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "message", type: "string", required: true, description: "Commit message."),
                SystemToolParameter(name: "paths", type: "array", required: false, description: "Paths to commit; defaults to all changes."),
            ]
        ),
        SystemToolDefinition(
            name: "git_push",
            description: "Push the thread branch to its upstream, using the engine git action runner.",
            action: "git.actions.run",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
            ]
        ),
        SystemToolDefinition(
            name: "git_pull",
            description: "Pull the thread branch from its upstream, using the engine git action runner.",
            action: "git.actions.pull",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
            ]
        ),
        SystemToolDefinition(
            name: "git_branch_list",
            description: "List git branches for the thread working directory.",
            action: "git.branches.list",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "scope", type: "string", required: false, description: "project lists the project checkout branches instead of the thread worktree."),
            ]
        ),
        SystemToolDefinition(
            name: "git_branch_create",
            description: "Create and check out a new git branch for the thread working directory.",
            action: "git.branches.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "name", type: "string", required: true, description: "New branch name."),
            ]
        ),
        SystemToolDefinition(
            name: "git_branch_checkout",
            description: "Check out an existing git branch for the thread working directory. The thread must have no active turn.",
            action: "git.branches.checkout",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "name", type: "string", required: true, description: "Branch name to check out."),
            ]
        ),
        SystemToolDefinition(
            name: "mem_store",
            description: "Store a durable fact in agent memory. Storing an existing key overwrites it and reports overwritten=true.",
            action: "memory.store",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "key", type: "string", required: true, description: "Memory key, up to 256 characters."),
                SystemToolParameter(name: "value", type: "string", required: true, description: "Fact to store, up to 64 KiB."),
                SystemToolParameter(name: "scope", type: "string", required: false, description: "global or workspace:<identifier>. Defaults to global."),
            ]
        ),
        SystemToolDefinition(
            name: "mem_retrieve",
            description: "Read a stored fact from agent memory by key. A missing key is an error.",
            action: "memory.retrieve",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "key", type: "string", required: true, description: "Memory key to read."),
                SystemToolParameter(name: "scope", type: "string", required: false, description: "global or workspace:<identifier>. Defaults to global."),
            ]
        ),
        SystemToolDefinition(
            name: "view_memory",
            description: "List stored agent memories in a scope, optionally filtered by a keyword substring over keys and values.",
            action: "memory.list",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "scope", type: "string", required: false, description: "global or workspace:<identifier>. Defaults to all scopes."),
                SystemToolParameter(name: "query", type: "string", required: false, description: "Keyword substring filter over keys and values."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum entries to return."),
            ]
        ),
        SystemToolDefinition(
            name: "mem_delete",
            description: "Delete one stored fact from agent memory by key. A missing key is an error.",
            action: "memory.delete",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "key", type: "string", required: true, description: "Memory key to delete."),
                SystemToolParameter(name: "scope", type: "string", required: false, description: "global or workspace:<identifier>. Defaults to global."),
            ]
        ),
        SystemToolDefinition(
            name: "mem_clear",
            description: "Delete every memory entry in one scope. Requires scope and confirm=true; without both the clear is refused.",
            action: "memory.clear",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "scope", type: "string", required: true, description: "Scope to clear: global or workspace:<identifier>."),
                SystemToolParameter(name: "confirm", type: "boolean", required: true, description: "Must be true. Clearing a scope is irreversible."),
            ]
        ),
        SystemToolDefinition(
            name: "mem_context_snapshot",
            description: "Capture a snapshot of the memories relevant to the current context. Each call mints a new snapshot key and stores it as a memory entry.",
            action: "memory.snapshot",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "scope", type: "string", required: false, description: "global or workspace:<identifier>. Defaults to global."),
                SystemToolParameter(name: "query", type: "string", required: false, description: "Keyword substring filter over keys and values."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum entries to capture."),
            ]
        ),
        SystemToolDefinition(
            name: "context_persistence_store",
            description: "Durable key-value context across sessions, backed by the agent memory store. Get of a missing key succeeds with an empty value.",
            action: "memory.context_store",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "key", type: "string", required: true, description: "Memory key."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "get, set, or delete."),
                SystemToolParameter(name: "value", type: "string", required: false, description: "Value for set."),
                SystemToolParameter(name: "scope", type: "string", required: false, description: "global or workspace:<identifier>. Defaults to global."),
            ]
        ),
        SystemToolDefinition(
            name: "use_workers",
            description: "Spawn one or more subagent workers on the parent thread. Each worker runs a real provider turn on its own thread; worker names must be unique and targetFiles must be disjoint across workers.",
            action: "workers.spawn",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "parentThreadId", type: "string", required: true, description: "Parent thread ID that owns the workers."),
                SystemToolParameter(name: "workers", type: "array", required: true, description: "Workers to spawn, each with name, task of at most 500 characters, and targetFiles."),
            ]
        ),
        SystemToolDefinition(
            name: "list_workers",
            description: "List workers spawned by a parent thread, with live status and progress.",
            action: "workers.list",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "parentThreadId", type: "string", required: false, description: "Parent thread ID; lists every worker when omitted."),
            ]
        ),
        SystemToolDefinition(
            name: "worker_status",
            description: "Read one worker's live status, progress, and result if finished.",
            action: "workers.status",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "workerId", type: "string", required: true, description: "Worker ID from use_workers or list_workers."),
            ]
        ),
        SystemToolDefinition(
            name: "worker_result",
            description: "Read one worker's result. Returns the worker record; result is null until the worker completes.",
            action: "workers.result",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "workerId", type: "string", required: true, description: "Worker ID from use_workers or list_workers."),
            ]
        ),
        SystemToolDefinition(
            name: "cancel_worker",
            description: "Ask a running worker's provider turn to stop and mark the worker cancelled. Cancellation is a stop request, not a kill: the provider winds down on its own schedule.",
            action: "workers.cancel",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "workerId", type: "string", required: true, description: "Worker ID from use_workers or list_workers."),
            ]
        ),
        SystemToolDefinition(
            name: "intel_plan_task",
            description: "Draft a plan for a complex task as worker steps. Mechanical sentence decomposition, not LLM planning; each step still needs disjoint targetFiles assigned before spawning.",
            action: "workers.plan",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "parentThreadId", type: "string", required: true, description: "Parent thread ID that owns the plan."),
                SystemToolParameter(name: "task", type: "string", required: true, description: "Task to decompose into worker steps."),
            ]
        ),
        SystemToolDefinition(
            name: "intel_breakdown_task",
            description: "Expand a stored plan's steps into granular sub-steps by mechanical splitting. Requires a planId from intel_plan_task.",
            action: "workers.breakdown",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "planId", type: "string", required: true, description: "Plan ID from intel_plan_task."),
                SystemToolParameter(name: "parentThreadId", type: "string", required: false, description: "Parent thread ID the plan must belong to."),
            ]
        ),
        SystemToolDefinition(
            name: "execution_plan",
            description: "Build an execution plan from the objective and live repository state, and write it to agent_notes.md in the parent working directory. The plan is a fixed mechanical template, not completed work.",
            action: "workers.execution_plan",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "parentThreadId", type: "string", required: true, description: "Parent thread ID that owns the plan."),
                SystemToolParameter(name: "objective", type: "string", required: true, description: "Objective to plan, at most 500 characters."),
                SystemToolParameter(name: "mode", type: "string", required: true, description: "Plan mode, for example build."),
            ]
        ),
        SystemToolDefinition(
            name: "list_apps",
            description: "List running apps on this computer.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
            ]
        ),
        SystemToolDefinition(
            name: "list_windows",
            description: "List on-screen windows, optionally for one app.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "pid", type: "integer", required: false, description: "Process ID of the running app."),
            ]
        ),
        SystemToolDefinition(
            name: "get_window_state",
            description: "Observe one window: its accessible elements as fresh element tokens, optionally with a screenshot saved as a private PNG file.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "pid", type: "integer", required: true, description: "Process ID of the running app."),
                SystemToolParameter(name: "window_id", type: "integer", required: true, description: "Window ID from list_windows or get_desktop_state."),
                SystemToolParameter(name: "max_elements", type: "integer", required: false, description: "Maximum accessible elements to return, at most 128."),
                SystemToolParameter(name: "include_screenshot", type: "boolean", required: false, description: "Save a screenshot as a private PNG file and return its path."),
            ]
        ),
        SystemToolDefinition(
            name: "get_desktop_state",
            description: "List running apps and on-screen windows, optionally with a screenshot of the main display.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "include_screenshot", type: "boolean", required: false, description: "Save a screenshot as a private PNG file and return its path."),
            ]
        ),
        SystemToolDefinition(
            name: "verify_state",
            description: "Fresh read of a window: elements whose title or value contains text. Issues no tokens.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "pid", type: "integer", required: true, description: "Process ID of the running app."),
                SystemToolParameter(name: "window_id", type: "integer", required: true, description: "Window ID from list_windows or get_desktop_state."),
                SystemToolParameter(name: "text", type: "string", required: true, description: "Text to find in element titles or values."),
            ]
        ),
        SystemToolDefinition(
            name: "zoom",
            description: "Sharper image of a region of the observed window, in window points.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "observation", type: "string", required: true, description: "Observation ID from a fresh get_window_state screenshot."),
                SystemToolParameter(name: "x", type: "number", required: true, description: "Region x in window points."),
                SystemToolParameter(name: "y", type: "number", required: true, description: "Region y in window points."),
                SystemToolParameter(name: "width", type: "number", required: true, description: "Region width in window points."),
                SystemToolParameter(name: "height", type: "number", required: true, description: "Region height in window points."),
            ]
        ),
        SystemToolDefinition(
            name: "click",
            description: "Press an accessible element by its fresh element token.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "element_token", type: "string", required: true, description: "Element token from a fresh get_window_state observation."),
            ]
        ),
        SystemToolDefinition(
            name: "double_click",
            description: "Double-click an element token, or a point in a fresh screenshot observation.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "element_token", type: "string", required: false, description: "Element token from a fresh get_window_state observation."),
                SystemToolParameter(name: "observation", type: "string", required: false, description: "Observation ID from a fresh get_window_state screenshot."),
                SystemToolParameter(name: "x", type: "number", required: false, description: "Point x in window points."),
                SystemToolParameter(name: "y", type: "number", required: false, description: "Point y in window points."),
            ]
        ),
        SystemToolDefinition(
            name: "right_click",
            description: "Right-click an element token, or a point in a fresh screenshot observation.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "element_token", type: "string", required: false, description: "Element token from a fresh get_window_state observation."),
                SystemToolParameter(name: "observation", type: "string", required: false, description: "Observation ID from a fresh get_window_state screenshot."),
                SystemToolParameter(name: "x", type: "number", required: false, description: "Point x in window points."),
                SystemToolParameter(name: "y", type: "number", required: false, description: "Point y in window points."),
            ]
        ),
        SystemToolDefinition(
            name: "set_value",
            description: "Set the text of an accessible element by its fresh element token.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "element_token", type: "string", required: true, description: "Element token from a fresh get_window_state observation."),
                SystemToolParameter(name: "text", type: "string", required: true, description: "Text to set."),
            ]
        ),
        SystemToolDefinition(
            name: "type_text",
            description: "Type text into the focused element of the foreground app.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "element_token", type: "string", required: true, description: "Element token from a fresh get_window_state observation."),
                SystemToolParameter(name: "text", type: "string", required: true, description: "Text to type."),
            ]
        ),
        SystemToolDefinition(
            name: "press_key",
            description: "Press a key on the focused element of the foreground app.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "element_token", type: "string", required: true, description: "Element token from a fresh get_window_state observation."),
                SystemToolParameter(name: "key", type: "string", required: true, description: "Key to press: enter, escape, tab, backspace, left, right, up, or down."),
            ]
        ),
        SystemToolDefinition(
            name: "hotkey",
            description: "Send a modifier chord to the focused element of the foreground app, for example cmd shift t.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "element_token", type: "string", required: true, description: "Element token from a fresh get_window_state observation."),
                SystemToolParameter(name: "keys", type: "array", required: true, description: "Modifiers then one key, for example cmd shift t."),
            ]
        ),
        SystemToolDefinition(
            name: "scroll",
            description: "Scroll at an element token, or a point in a fresh screenshot observation.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "element_token", type: "string", required: false, description: "Element token from a fresh get_window_state observation."),
                SystemToolParameter(name: "observation", type: "string", required: false, description: "Observation ID from a fresh get_window_state screenshot."),
                SystemToolParameter(name: "x", type: "number", required: false, description: "Point x in window points."),
                SystemToolParameter(name: "y", type: "number", required: false, description: "Point y in window points."),
                SystemToolParameter(name: "direction", type: "string", required: true, description: "Scroll direction: up, down, left, or right."),
                SystemToolParameter(name: "amount", type: "integer", required: false, description: "Scroll amount, 1 to 50. Defaults to 3."),
            ]
        ),
        SystemToolDefinition(
            name: "drag",
            description: "Drag between two points of a fresh screenshot observation.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "observation", type: "string", required: true, description: "Observation ID from a fresh get_window_state screenshot."),
                SystemToolParameter(name: "from_x", type: "number", required: true, description: "Start x in window points."),
                SystemToolParameter(name: "from_y", type: "number", required: true, description: "Start y in window points."),
                SystemToolParameter(name: "to_x", type: "number", required: true, description: "End x in window points."),
                SystemToolParameter(name: "to_y", type: "number", required: true, description: "End y in window points."),
            ]
        ),
        SystemToolDefinition(
            name: "move_cursor",
            description: "Move the cursor to a point in a fresh screenshot observation.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "observation", type: "string", required: true, description: "Observation ID from a fresh get_window_state screenshot."),
                SystemToolParameter(name: "x", type: "number", required: true, description: "Point x in window points."),
                SystemToolParameter(name: "y", type: "number", required: true, description: "Point y in window points."),
            ]
        ),
        SystemToolDefinition(
            name: "click_point",
            description: "Click a point in a fresh screenshot observation of the foreground window.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "observation", type: "string", required: true, description: "Observation ID from a fresh get_window_state screenshot."),
                SystemToolParameter(name: "x", type: "number", required: true, description: "Point x in window points."),
                SystemToolParameter(name: "y", type: "number", required: true, description: "Point y in window points."),
            ]
        ),
        SystemToolDefinition(
            name: "invoke_menu",
            description: "Run a menu bar path of a running app, for example File New Window.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "pid", type: "integer", required: true, description: "Process ID of the running app."),
                SystemToolParameter(name: "path", type: "array", required: true, description: "Menu path, for example File New Window."),
            ]
        ),
        SystemToolDefinition(
            name: "launch_app",
            description: "Launch an app by bundle ID.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "bundle_id", type: "string", required: true, description: "App bundle ID, for example com.apple.TextEdit."),
            ]
        ),
        SystemToolDefinition(
            name: "set_window_frame",
            description: "Move and resize a window, in screen points.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "pid", type: "integer", required: true, description: "Process ID of the running app."),
                SystemToolParameter(name: "window_id", type: "integer", required: true, description: "Window ID from list_windows or get_desktop_state."),
                SystemToolParameter(name: "x", type: "number", required: true, description: "Frame x in screen points."),
                SystemToolParameter(name: "y", type: "number", required: true, description: "Frame y in screen points."),
                SystemToolParameter(name: "width", type: "number", required: true, description: "Frame width in screen points."),
                SystemToolParameter(name: "height", type: "number", required: true, description: "Frame height in screen points."),
                SystemToolDefinition(
            name: "file_read",
            description: "Read a file in the thread working directory.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "view_file",
            description: "View a file in the thread working directory.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "file_write",
            description: "Write a file in the thread working directory.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "content", type: "string", required: true, description: "Full file content."),
            ]
        ),
        SystemToolDefinition(
            name: "create_file",
            description: "Create a new file in the thread working directory. Refuses to overwrite an existing file unless overwrite is true.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "content", type: "string", required: false, description: "Initial file content. Defaults to empty."),
                SystemToolParameter(name: "overwrite", type: "boolean", required: false, description: "Allow overwriting an existing file. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "file_create",
            description: "Create a file that must not already exist, in the thread working directory. Refuses to overwrite unless overwrite is true.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "content", type: "string", required: false, description: "Initial file content. Defaults to empty."),
                SystemToolParameter(name: "overwrite", type: "boolean", required: false, description: "Allow overwriting an existing file. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "file_append",
            description: "Append content to an existing file in the thread working directory. A missing file is an error.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "content", type: "string", required: true, description: "Content to append."),
            ]
        ),
        SystemToolDefinition(
            name: "file_delete",
            description: "Delete a file in the thread working directory. Refuses directories and symlinks.",
            action: "workspace.delete_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "dir_delete",
            description: "Delete a directory in the thread working directory. Without recursive=true only an empty directory is removed.",
            action: "workspace.delete_directory",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "recursive", type: "boolean", required: false, description: "Remove the directory and everything inside it."),
            ]
        ),
        SystemToolDefinition(
            name: "file_move",
            description: "Move a file or directory inside the thread working directory. The destination must not already exist.",
            action: "workspace.move_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "destination", type: "string", required: true, description: "Destination path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "file_rename",
            description: "Rename a file within its own directory. The new name is a single file name, not a path.",
            action: "workspace.move_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "newName", type: "string", required: true, description: "New file name, without any path separator."),
            ]
        ),
        SystemToolDefinition(
            name: "file_copy",
            description: "Copy a file inside the thread working directory. The destination must not already exist.",
            action: "workspace.copy_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "destination", type: "string", required: true, description: "Destination path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "dir_create",
            description: "Create a directory, including missing parents, in the thread working directory.",
            action: "workspace.create_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "dir_read",
            description: "List a directory in the thread working directory, non-recursive.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory relative to the working directory; defaults to the working directory itself."),
            ]
        ),
        SystemToolDefinition(
            name: "list_directory",
            description: "List directory entries in the thread working directory.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory relative to the working directory; defaults to the working directory itself."),
                SystemToolParameter(name: "recursive", type: "boolean", required: false, description: "List entries recursively, up to 16 levels deep."),
            ]
        ),
        SystemToolDefinition(
            name: "tree_view",
            description: "List a directory tree in the thread working directory, recursively up to maxDepth levels.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory relative to the working directory; defaults to the working directory itself."),
                SystemToolParameter(name: "maxDepth", type: "integer", required: false, description: "Maximum tree depth, 1 to 10. Defaults to 3."),
            ]
        ),
        SystemToolDefinition(
            name: "search_directory",
            description: "List files in the thread working directory matching a substring filter.",
            action: "workspace.files",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "query", type: "string", required: false, description: "Substring filter for file paths."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum files to return."),
            ]
        ),
        SystemToolDefinition(
            name: "search_text",
            description: "Search file contents literally in the thread working directory.",
            action: "workspace.search",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "query", type: "string", required: true, description: "Text to search for."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "code_replace",
            description: "Replace exact target text with replacement text in a file. The target must match exactly once unless allowMultiple is true.",
            action: "workspace.edit_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "target", type: "string", required: true, description: "Exact text to match."),
                SystemToolParameter(name: "replacement", type: "string", required: true, description: "Replacement text."),
                SystemToolParameter(name: "allowMultiple", type: "boolean", required: false, description: "Replace every occurrence instead of requiring exactly one. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "code_insert",
            description: "Insert code into a file at a 1-based line, or before or after a pattern that must match exactly once.",
            action: "workspace.edit_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "code", type: "string", required: true, description: "Code to insert."),
                SystemToolParameter(name: "line", type: "integer", required: false, description: "1-based line to insert before, for mode line. Defaults to the end of the file."),
                SystemToolParameter(name: "mode", type: "string", required: false, description: "line, before, or after. Defaults to line."),
                SystemToolParameter(name: "pattern", type: "string", required: false, description: "Pattern to anchor on, required for mode before or after."),
            ]
        ),
        SystemToolDefinition(
            name: "code_multi_edit",
            description: "Apply several anchored edits to one file, in order. Every anchor must match exactly once at the time it is applied or the whole edit fails.",
            action: "workspace.edit_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "edits", type: "array", required: true, description: "Edits to apply, each with oldText, newText, and an optional mode."),
            ]
        ),
        SystemToolDefinition(
            name: "use_terminal",
            description: "Run a shell command in the thread integrated terminal and return its real output and exit code.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "command", type: "string", required: true, description: "Shell command to run."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command. Defaults to 600."),
            ]
        ),
        SystemToolDefinition(
            name: "run_command",
            description: "Run a shell command in the thread integrated terminal and return its real output and exit code.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "command", type: "string", required: true, description: "Shell command to run."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command. Defaults to 600."),
            ]
        ),
        SystemToolDefinition(
            name: "git_log_viewer",
            description: "List git commits for a thread working directory, newest first, with author, date, message, and parents.",
            action: "git.log",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum commits to return, 1–200. Defaults to 50."),
                SystemToolParameter(name: "skip", type: "integer", required: false, description: "Commits to skip for pagination. Defaults to 0."),
            ]
        ),
        SystemToolDefinition(
            name: "git_branch_compare",
            description: "Diff two git references for a thread working directory, comparing the merge base of the first against the second, with changed files and the full patch.",
            action: "git.diff.range",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "from", type: "string", required: true, description: "Base reference, such as a branch name or commit SHA."),
                SystemToolParameter(name: "to", type: "string", required: true, description: "Reference to compare against the base, such as a branch name or commit SHA."),
            ]
        ),
        SystemToolDefinition(
            name: "project_diff",
            description: "Read the git diff for a thread.",
            action: "git.diff",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Single file path to diff."),
                SystemToolParameter(name: "staged", type: "boolean", required: false, description: "Diff staged changes instead of the worktree."),
            ]
        ),
        SystemToolDefinition(
            name: "git_branch_manager",
            description: "List, create, check out, or safely delete local git branches. Delete requires confirm=true and refuses the checked-out branch.",
            action: "git.branches.list",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "action", type: "string", required: false, description: "list, create, checkout, or delete. Defaults to list."),
                SystemToolParameter(name: "name", type: "string", required: false, description: "Branch name for create, checkout, or delete."),
                SystemToolParameter(name: "force", type: "boolean", required: false, description: "Delete with -D instead of -d, dropping unmerged work. Defaults to false."),
                SystemToolParameter(name: "confirm", type: "boolean", required: false, description: "Must be true to delete a branch."),
            ]
        ),
        SystemToolDefinition(
            name: "save_to_memory",
            description: "Store a durable fact in agent memory. Storing an existing key overwrites it and reports overwritten=true.",
            action: "memory.store",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "key", type: "string", required: true, description: "Memory key, up to 256 characters."),
                SystemToolParameter(name: "value", type: "string", required: true, description: "Fact to store, up to 64 KiB."),
                SystemToolParameter(name: "scope", type: "string", required: false, description: "global or workspace:<identifier>. Defaults to global."),
            ]
        ),
        SystemToolDefinition(
            name: "use_mcp",
            description: "Use the coincide MCP server: list its servers, list its tools, or run one of its tools by name.",
            action: "mcp.tools",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "serverName", type: "string", required: true, description: "MCP server name, or list to list servers."),
                SystemToolParameter(name: "toolName", type: "string", required: false, description: "Tool name to run, or list_tools to list tools."),
                SystemToolParameter(name: "arguments", type: "string", required: false, description: "JSON object string of arguments for the tool."),
            ]
        ),
        SystemToolDefinition(
            name: "take_screenshot",
            description: "Capture the main display as a private PNG file and return its path.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "include_screenshot", type: "boolean", required: false, description: "Save a screenshot as a private PNG file and return its path. Defaults to true."),
            ]
        ),
        SystemToolDefinition(
            name: "start_subagent",
            description: "Spawn one or more subagent workers on the parent thread. Each worker runs a real provider turn on its own thread; worker names must be unique and targetFiles must be disjoint across workers.",
            action: "workers.spawn",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "parentThreadId", type: "string", required: true, description: "Parent thread ID that owns the workers."),
                SystemToolParameter(name: "workers", type: "array", required: true, description: "Workers to spawn, each with name, task of at most 500 characters, and targetFiles."),
            ]
        ),
        SystemToolDefinition(
            name: "git_stash_operator",
            description: "Save, pop, list, show, or drop git stashes. Pop and drop require confirm=true.",
            action: "git.stash",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "push, pop, list, show, or drop."),
                SystemToolParameter(name: "message", type: "string", required: false, description: "Message for stash push."),
                SystemToolParameter(name: "includeUntracked", type: "boolean", required: false, description: "Include untracked files in a stash push. Defaults to false."),
                SystemToolParameter(name: "reference", type: "string", required: false, description: "Stash reference such as stash@{0}, for pop, show, or drop."),
                SystemToolParameter(name: "confirm", type: "boolean", required: false, description: "Must be true to pop or drop a stash."),
                SystemToolParameter(name: "paths", type: "array", required: false, description: "Paths to stash on push; defaults to all changes."),
            ]
        ),
        SystemToolDefinition(
            name: "git_blame_inspector",
            description: "Show git blame line annotations for a file, with author, commit, and content per line.",
            action: "git.blame",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "File path relative to the working directory."),
                SystemToolParameter(name: "start", type: "integer", required: false, description: "First line of the range, 1-based. Requires end."),
                SystemToolParameter(name: "end", type: "integer", required: false, description: "Last line of the range, inclusive. Requires start."),
            ]
        ),
        SystemToolDefinition(
            name: "git_bisect",
            description: "Run git bisect: start, good, bad, skip, reset, or log. Start, good, bad, and skip move HEAD.",
            action: "git.bisect",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "start, good, bad, skip, reset, or log."),
                SystemToolParameter(name: "reference", type: "string", required: false, description: "Reference to mark good, bad, or skip. Defaults to HEAD."),
                SystemToolParameter(name: "good", type: "string", required: false, description: "Known-good reference for start."),
                SystemToolParameter(name: "bad", type: "string", required: false, description: "Known-bad reference for start."),
            ]
        ),
        SystemToolDefinition(
            name: "git_cherry_pick",
            description: "Cherry-pick a commit by full SHA, optionally without committing. Requires confirm=true. On conflict it reports the conflicted files and never auto-aborts.",
            action: "git.cherry_pick",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "sha", type: "string", required: true, description: "Full 40- or 64-character commit SHA."),
                SystemToolParameter(name: "noCommit", type: "boolean", required: false, description: "Stage the cherry-pick without committing. Defaults to false."),
                SystemToolParameter(name: "confirm", type: "boolean", required: true, description: "Must be true. Cherry-pick changes the working tree."),
            ]
        ),
        SystemToolDefinition(
            name: "version_control_operator",
            description: "Run git by action: status, commit, branch, diff, or rollback. Rollback resets hard to HEAD, HEAD~N, HEAD^N, or a full SHA and requires confirm=true.",
            action: "git.rollback",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "status, commit, branch, diff, or rollback."),
                SystemToolParameter(name: "message", type: "string", required: false, description: "Commit message."),
                SystemToolParameter(name: "name", type: "string", required: false, description: "Branch name for the branch action."),
                SystemToolParameter(name: "ref", type: "string", required: false, description: "Reference to roll back to. Defaults to HEAD~1."),
                SystemToolParameter(name: "confirm", type: "boolean", required: false, description: "Must be true to roll back."),
                SystemToolParameter(name: "paths", type: "array", required: false, description: "Paths to commit; defaults to all changes."),
            ]
        ),
        SystemToolDefinition(
            name: "git_pr_summary",
            description: "Compose a local-only markdown PR summary from git log and the diff range, with no GitHub API call.",
            action: "git.log",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "from", type: "string", required: false, description: "Base reference. Defaults to the branch base."),
                SystemToolParameter(name: "to", type: "string", required: false, description: "Reference to compare. Defaults to the branch head."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum commits to list. Defaults to 20."),
            ]
        ),
        SystemToolDefinition(
            name: "git_conflict_resolver",
            description: "Detect merge conflict markers across the workspace, or resolve them in one file with the ours, theirs, or both strategy.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "action", type: "string", required: false, description: "detect or resolve. Defaults to detect."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File path relative to the working directory, for resolve."),
                SystemToolParameter(name: "strategy", type: "string", required: false, description: "ours, theirs, or both. Defaults to ours."),
            ]
        ),
        SystemToolDefinition(
            name: "project_snapshot",
            description: "Capture a staged snapshot of the workspace and return its snapshot id for project_restore.",
            action: "git.checkpoints.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "label", type: "string", required: false, description: "Snapshot label, stored in the checkpoint commit message."),
            ]
        ),
        SystemToolDefinition(
            name: "project_changelog",
            description: "List workspace snapshot ids and commits, newest first. Labels live in the checkpoint commit message, not in the list entries.",
            action: "git.checkpoints.list",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
            ]
        ),
        SystemToolDefinition(
            name: "project_restore",
            description: "Restore the workspace to a snapshot id, resetting hard to the snapshot commit and removing untracked and ignored files. Requires confirm=true.",
            action: "git.checkpoints.restore",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "checkpointId", type: "string", required: true, description: "Snapshot id from project_snapshot or project_changelog."),
                SystemToolParameter(name: "confirm", type: "boolean", required: true, description: "Must be true. Restore discards uncommitted and untracked changes."),
            ]
        ),
        SystemToolDefinition(
            name: "safe_undo",
            description: "Restore the second-newest snapshot. Requires at least two snapshots and confirm=true.",
            action: "git.checkpoints.restore",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "confirm", type: "boolean", required: true, description: "Must be true. Undo discards uncommitted and untracked changes."),
            ]
        ),
        SystemToolDefinition(
            name: "safe_validate_changes",
            description: "Check a file, or the whole workspace, for merge markers and missing trailing newlines. Returns success with issues listed.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Single file path to check; defaults to the whole workspace."),
            ]
        ),
    ]
        ),
    ]

    public static func tools(for toolset: AgentToolset) -> [SystemToolDefinition] {
        switch toolset {
        case .system:
            systemTools
        case .provider:
            []
        }
    }

    public static func definition(named name: String, for toolset: AgentToolset) -> SystemToolDefinition? {
        tools(for: toolset).first { $0.name == name }
    }

    public static func execute(
        _ name: String,
        arguments: [String: JSONValue],
        toolset: AgentToolset,
        runtime: AgentsRuntimeClient
    ) async throws -> JSONValue {
        guard let definition = definition(named: name, for: toolset) else {
            if systemTools.contains(where: { $0.name == name }) {
                throw SystemToolError.toolNotActive(tool: name, toolset: toolset)
            }
            throw SystemToolError.unknownTool(name)
        }
        switch definition.name {
        case "read_file":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            return .object(["path": .string(document.path), "content": .string(document.content)])
        case "write_file":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let content = try requiredString(arguments, "content", tool: name)
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: content)
            return .object(["path": .string(path)])
        case "list_files":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let query = optionalString(arguments, "query") ?? ""
            let limit = optionalInt(arguments, "limit") ?? 500
            let files = try await runtime.listWorkspaceFiles(cwd: cwd, query: query, limit: limit)
            return .array(files.map { file in
                .object([
                    "path": .string(file.path),
                    "name": .string(file.name),
                    "isDirectory": .bool(file.isDirectory),
                ])
            })
        case "search_files":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let query = try requiredString(arguments, "query", tool: name)
            let limit = optionalInt(arguments, "limit") ?? 200
            let hits = try await runtime.searchWorkspace(cwd: cwd, query: query, limit: limit)
            return .array(hits.map { hit in
                .object([
                    "path": .string(hit.path),
                    "lineNumber": .int(Int64(hit.lineNumber)),
                    "column": .int(Int64(hit.column)),
                    "lineText": .string(hit.lineText),
                ])
            })
        case "create_terminal":
            let id = try await runtime.createTerminal(threadID: optionalString(arguments, "threadId"))
            return .string(id)
        case "write_terminal":
            let terminalId = try requiredString(arguments, "terminalId", tool: name)
            let text = try requiredString(arguments, "text", tool: name)
            try await runtime.sendTerminalInput(id: terminalId, data: text)
            return .object(["terminalId": .string(terminalId)])
        case "read_terminal":
            let terminalId = try requiredString(arguments, "terminalId", tool: name)
            return try await runtime.engineRPC(method: "terminal.read", params: ["terminalId": .string(terminalId)])
        case "git_status":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            return try await runGitOperation(method: "git.status", threadId: threadId, params: [:], tool: name, runtime: runtime)
        case "git_diff":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            var params: [String: JSONValue] = [:]
            if let path = optionalString(arguments, "path") {
                params["path"] = .string(path)
            }
            if let staged = optionalBool(arguments, "staged") {
                params["staged"] = .bool(staged)
            }
            return try await runGitOperation(method: "git.diff", threadId: threadId, params: params, tool: name, runtime: runtime)
        case "git_log":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            var params: [String: JSONValue] = [:]
            if let limit = optionalInt(arguments, "limit") {
                params["limit"] = .int(Int64(limit))
            }
            if let skip = optionalInt(arguments, "skip") {
                params["skip"] = .int(Int64(skip))
            }
            return try await runGitOperation(method: "git.log", threadId: threadId, params: params, tool: name, runtime: runtime)
        case "git_show":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let sha = try requiredString(arguments, "sha", tool: name)
            return try await runGitOperation(method: "git.show", threadId: threadId, params: ["sha": .string(sha)], tool: name, runtime: runtime)
        case "git_diff_range":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let from = try requiredString(arguments, "from", tool: name)
            let to = try requiredString(arguments, "to", tool: name)
            return try await runGitOperation(method: "git.diff.range", threadId: threadId, params: ["from": .string(from), "to": .string(to)], tool: name, runtime: runtime)
        case "git_diff_branch":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            return try await runGitOperation(method: "git.diff.branch", threadId: threadId, params: [:], tool: name, runtime: runtime)
        case "delete_file":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            try await runtime.deleteWorkspaceFile(cwd: cwd, path: path)
            return .object(["path": .string(path), "deleted": .bool(true)])
        case "delete_directory":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let recursive = optionalBool(arguments, "recursive") ?? false
            try await runtime.deleteWorkspaceDirectory(cwd: cwd, path: path, recursive: recursive)
            return .object(["path": .string(path), "deleted": .bool(true), "recursive": .bool(recursive)])
        case "move_file":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let destination = try requiredString(arguments, "destination", tool: name)
            try await runtime.moveWorkspaceFile(cwd: cwd, path: path, destination: destination)
            return .object(["path": .string(path), "destination": .string(destination), "moved": .bool(true)])
        case "copy_file":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let destination = try requiredString(arguments, "destination", tool: name)
            try await runtime.copyWorkspaceFile(cwd: cwd, path: path, destination: destination)
            return .object(["path": .string(path), "destination": .string(destination), "copied": .bool(true)])
        case "create_directory":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            try await runtime.createWorkspaceDirectory(cwd: cwd, path: path)
            return .object(["path": .string(path), "created": .bool(true)])
        case "read_directory":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? ""
            let recursive = optionalBool(arguments, "recursive") ?? false
            let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: path, recursive: recursive)
            return .array(entries.map { entry in
                .object([
                    "path": .string(entry.path),
                    "name": .string(entry.name),
                    "isDirectory": .bool(entry.isDirectory),
                ])
            })
        case "edit_file":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let oldText = try requiredString(arguments, "oldText", tool: name)
            guard let newText = arguments["newText"]?.stringValue else {
                throw SystemToolError.missingArgument(tool: name, argument: "newText")
            }
            let mode = optionalString(arguments, "mode") ?? "replace"
            return try await runtime.editWorkspaceFile(cwd: cwd, path: path, oldText: oldText, newText: newText, mode: mode)
        case "multi_edit_file":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            guard let rawEdits = arguments["edits"]?.arrayValue, !rawEdits.isEmpty else {
                throw SystemToolError.missingArgument(tool: name, argument: "edits")
            }
            let edits = try rawEdits.map { raw -> WorkspaceEdit in
                guard let oldText = raw["oldText"]?.stringValue, !oldText.isEmpty else {
                    throw SystemToolError.missingArgument(tool: name, argument: "oldText")
                }
                guard let newText = raw["newText"]?.stringValue else {
                    throw SystemToolError.missingArgument(tool: name, argument: "newText")
                }
                return WorkspaceEdit(
                    oldText: oldText,
                    newText: newText,
                    mode: raw["mode"]?.stringValue ?? "replace"
                )
            }
            return try await runtime.editWorkspaceFile(cwd: cwd, path: path, edits: edits)
        case "search_regex":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let pattern = try requiredString(arguments, "pattern", tool: name)
            let limit = optionalInt(arguments, "limit") ?? 200
            let hits = try await runtime.searchWorkspaceRegex(cwd: cwd, pattern: pattern, limit: limit)
            return .array(hits.map { hit in
                .object([
                    "path": .string(hit.path),
                    "lineNumber": .int(Int64(hit.lineNumber)),
                    "column": .int(Int64(hit.column)),
                    "lineText": .string(hit.lineText),
                ])
            })
        case "run_build", "run_tests":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let command = try requiredString(arguments, "command", tool: name)
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 600
            return try await runTerminalCommand(tool: name, threadId: threadId, command: command, timeoutSeconds: timeoutSeconds, runtime: runtime)
        case "git_commit":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let message = try requiredString(arguments, "message", tool: name)
            var params: [String: JSONValue] = [
                "action": .string("commit"),
                "message": .string(message),
            ]
            if let paths = optionalStringArray(arguments, "paths") {
                params["paths"] = .array(paths.map { .string($0) })
            }
            return try await runGitActionsOperation(method: "git.actions.run", threadId: threadId, params: params, tool: name, timeoutSeconds: 120, runtime: runtime)
        case "git_push":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            return try await runGitActionsOperation(method: "git.actions.run", threadId: threadId, params: ["action": .string("push")], tool: name, timeoutSeconds: 600, runtime: runtime)
        case "git_pull":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            return try await runGitActionsOperation(method: "git.actions.pull", threadId: threadId, params: [:], tool: name, timeoutSeconds: 600, runtime: runtime)
        case "git_branch_list":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            var params: [String: JSONValue] = [:]
            if let scope = optionalString(arguments, "scope") {
                params["scope"] = .string(scope)
            }
            return try await runGitActionsOperation(method: "git.branches.list", threadId: threadId, params: params, tool: name, timeoutSeconds: 60, runtime: runtime)
        case "git_branch_create":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let branch = try requiredString(arguments, "name", tool: name)
            return try await runGitActionsOperation(method: "git.branches.create", threadId: threadId, params: ["name": .string(branch)], tool: name, timeoutSeconds: 60, runtime: runtime)
        case "git_branch_checkout":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let branch = try requiredString(arguments, "name", tool: name)
            return try await runGitActionsOperation(method: "git.branches.checkout", threadId: threadId, params: ["name": .string(branch)], tool: name, timeoutSeconds: 60, runtime: runtime)
        case "mem_store":
            let key = try requiredString(arguments, "key", tool: name)
            let value = try requiredString(arguments, "value", tool: name)
            return try await runtime.memoryStore(key: key, value: value, scope: optionalString(arguments, "scope"))
        case "mem_retrieve":
            let key = try requiredString(arguments, "key", tool: name)
            return try await runtime.memoryRetrieve(key: key, scope: optionalString(arguments, "scope"))
        case "view_memory":
            let entries = try await runtime.memoryList(scope: optionalString(arguments, "scope"), query: optionalString(arguments, "query"), limit: optionalInt(arguments, "limit") ?? 200)
            return .array(entries.map { entry in
                .object([
                    "key": .string(entry.key),
                    "scope": .string(entry.scope),
                    "value": .string(entry.value),
                    "updatedAt": .double(entry.updatedAt),
                ])
            })
        case "mem_delete":
            let key = try requiredString(arguments, "key", tool: name)
            return try await runtime.memoryDelete(key: key, scope: optionalString(arguments, "scope"))
        case "mem_clear":
            let scope = try requiredString(arguments, "scope", tool: name)
            guard let confirm = optionalBool(arguments, "confirm") else {
                throw SystemToolError.missingArgument(tool: name, argument: "confirm")
            }
            guard confirm else {
                throw SystemToolError.executionFailed(tool: name, message: "mem_clear requires confirm=true; clearing a scope is irreversible.")
            }
            return try await runtime.memoryClear(scope: scope, confirm: true)
        case "mem_context_snapshot":
            return try await runtime.memorySnapshot(scope: optionalString(arguments, "scope"), query: optionalString(arguments, "query"), limit: optionalInt(arguments, "limit") ?? 50)
        case "context_persistence_store":
            let key = try requiredString(arguments, "key", tool: name)
            let action = try requiredString(arguments, "action", tool: name)
            return try await runtime.memoryContextStore(key: key, action: action, value: optionalString(arguments, "value"), scope: optionalString(arguments, "scope"))
        case "use_workers":
            let parentThreadId = try requiredString(arguments, "parentThreadId", tool: name)
            guard let rawWorkers = arguments["workers"]?.arrayValue, !rawWorkers.isEmpty else {
                throw SystemToolError.missingArgument(tool: name, argument: "workers")
            }
            let workers = try rawWorkers.map { raw -> WorkerSpawnRequest in
                guard let workerName = raw["name"]?.stringValue, !workerName.isEmpty else {
                    throw SystemToolError.missingArgument(tool: name, argument: "name")
                }
                guard let task = raw["task"]?.stringValue, !task.isEmpty else {
                    throw SystemToolError.missingArgument(tool: name, argument: "task")
                }
                return WorkerSpawnRequest(
                    name: workerName,
                    task: task,
                    targetFiles: raw["targetFiles"]?.arrayValue?.compactMap(\.stringValue) ?? []
                )
            }
            return try await runtime.spawnWorkers(parentThreadId: parentThreadId, workers: workers)
        case "list_workers":
            let workers = try await runtime.listWorkers(parentThreadId: optionalString(arguments, "parentThreadId"))
            return .array(workers.map { workerJSON($0) })
        case "worker_status":
            let workerId = try requiredString(arguments, "workerId", tool: name)
            return workerJSON(try await runtime.workerStatus(workerId: workerId))
        case "worker_result":
            let workerId = try requiredString(arguments, "workerId", tool: name)
            return workerJSON(try await runtime.workerResult(workerId: workerId))
        case "cancel_worker":
            let workerId = try requiredString(arguments, "workerId", tool: name)
            return workerJSON(try await runtime.cancelWorker(workerId: workerId))
        case "intel_plan_task":
            let parentThreadId = try requiredString(arguments, "parentThreadId", tool: name)
            let task = try requiredString(arguments, "task", tool: name)
            return try await runtime.planTask(parentThreadId: parentThreadId, task: task)
        case "intel_breakdown_task":
            let planId = try requiredString(arguments, "planId", tool: name)
            return try await runtime.breakdownTask(planId: planId, parentThreadId: optionalString(arguments, "parentThreadId"))
        case "execution_plan":
            let parentThreadId = try requiredString(arguments, "parentThreadId", tool: name)
            let objective = try requiredString(arguments, "objective", tool: name)
            let mode = try requiredString(arguments, "mode", tool: name)
            return try await runtime.executionPlan(parentThreadId: parentThreadId, objective: objective, mode: mode)
        case "list_apps", "list_windows", "get_window_state", "get_desktop_state",
             "verify_state", "zoom", "click", "double_click", "right_click", "set_value",
             "type_text", "press_key", "hotkey", "scroll", "drag", "move_cursor",
             "click_point", "invoke_menu", "launch_app", "set_window_frame":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let toolArguments = try Self.computerUseArguments(arguments, definition: definition, tool: name)
            return try await runComputerUseTool(tool: name, threadId: threadId, arguments: toolArguments, runtime: runtime)
        case "file_read", "view_file":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            return .object(["path": .string(document.path), "content": .string(document.content)])
        case "file_write":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let content = try requiredString(arguments, "content", tool: name)
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: content)
            return .object(["path": .string(path)])
        case "create_file", "file_create":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let content = optionalString(arguments, "content") ?? ""
            let overwrite = optionalBool(arguments, "overwrite") ?? false
            if !overwrite {
                try Self.assertFileAbsent(cwd: cwd, path: path, tool: name)
            }
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: content)
            return .object(["path": .string(path)])
        case "file_append":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let content = try requiredString(arguments, "content", tool: name)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: document.content + content)
            return .object(["path": .string(path)])
        case "file_delete":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            try await runtime.deleteWorkspaceFile(cwd: cwd, path: path)
            return .object(["path": .string(path), "deleted": .bool(true)])
        case "dir_delete":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let recursive = optionalBool(arguments, "recursive") ?? false
            try await runtime.deleteWorkspaceDirectory(cwd: cwd, path: path, recursive: recursive)
            return .object(["path": .string(path), "deleted": .bool(true), "recursive": .bool(recursive)])
        case "file_move":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let destination = try requiredString(arguments, "destination", tool: name)
            try await runtime.moveWorkspaceFile(cwd: cwd, path: path, destination: destination)
            return .object(["path": .string(path), "destination": .string(destination), "moved": .bool(true)])
        case "file_rename":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let newName = try requiredString(arguments, "newName", tool: name)
            guard !newName.isEmpty, !newName.contains("/"), !newName.contains("\\"), newName != ".", newName != ".." else {
                throw SystemToolError.executionFailed(tool: name, message: "newName must be a single file name, not a path.")
            }
            let parent = (path as NSString).deletingLastPathComponent
            let destination = parent.isEmpty ? newName : parent + "/" + newName
            try await runtime.moveWorkspaceFile(cwd: cwd, path: path, destination: destination)
            return .object(["path": .string(path), "destination": .string(destination), "moved": .bool(true)])
        case "file_copy":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let destination = try requiredString(arguments, "destination", tool: name)
            try await runtime.copyWorkspaceFile(cwd: cwd, path: path, destination: destination)
            return .object(["path": .string(path), "destination": .string(destination), "copied": .bool(true)])
        case "dir_create":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            try await runtime.createWorkspaceDirectory(cwd: cwd, path: path)
            return .object(["path": .string(path), "created": .bool(true)])
        case "dir_read":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? ""
            let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: path, recursive: false)
            return .array(entries.map { entry in
                .object([
                    "path": .string(entry.path),
                    "name": .string(entry.name),
                    "isDirectory": .bool(entry.isDirectory),
                ])
            })
        case "list_directory":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? ""
            let recursive = optionalBool(arguments, "recursive") ?? false
            let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: path, recursive: recursive)
            return .array(entries.map { entry in
                .object([
                    "path": .string(entry.path),
                    "name": .string(entry.name),
                    "isDirectory": .bool(entry.isDirectory),
                ])
            })
        case "tree_view":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? ""
            let maxDepth = min(max(optionalInt(arguments, "maxDepth") ?? 3, 1), 10)
            let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: path, recursive: true)
            let baseDepth = path.isEmpty || path == "." ? 0 : path.split(separator: "/").count
            let filtered = entries.filter { entry in
                entry.path.split(separator: "/").count - baseDepth <= maxDepth
            }
            return .array(filtered.map { entry in
                .object([
                    "path": .string(entry.path),
                    "name": .string(entry.name),
                    "isDirectory": .bool(entry.isDirectory),
                ])
            })
        case "search_directory":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let query = optionalString(arguments, "query") ?? ""
            let limit = optionalInt(arguments, "limit") ?? 500
            let files = try await runtime.listWorkspaceFiles(cwd: cwd, query: query, limit: limit)
            return .array(files.map { file in
                .object([
                    "path": .string(file.path),
                    "name": .string(file.name),
                    "isDirectory": .bool(file.isDirectory),
                ])
            })
        case "search_text":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let query = try requiredString(arguments, "query", tool: name)
            let limit = optionalInt(arguments, "limit") ?? 200
            let hits = try await runtime.searchWorkspace(cwd: cwd, query: query, limit: limit)
            return .array(hits.map { hit in
                .object([
                    "path": .string(hit.path),
                    "lineNumber": .int(Int64(hit.lineNumber)),
                    "column": .int(Int64(hit.column)),
                    "lineText": .string(hit.lineText),
                ])
            })
        case "code_replace":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let target = try requiredString(arguments, "target", tool: name)
            guard let replacement = arguments["replacement"]?.stringValue else {
                throw SystemToolError.missingArgument(tool: name, argument: "replacement")
            }
            let allowMultiple = optionalBool(arguments, "allowMultiple") ?? false
            if allowMultiple {
                let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
                guard document.content.contains(target) else {
                    throw SystemToolError.executionFailed(tool: name, message: "Target text was not found in the file.")
                }
                let updated = document.content.replacingOccurrences(of: target, with: replacement)
                try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: updated)
                return .object(["path": .string(path), "replaced": .bool(true)])
            }
            return try await runtime.editWorkspaceFile(cwd: cwd, path: path, oldText: target, newText: replacement, mode: "replace")
        case "code_insert":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let code = try requiredString(arguments, "code", tool: name)
            let mode = optionalString(arguments, "mode") ?? "line"
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let hadTrailingNewline = document.content.hasSuffix("\n")
            var lines = document.content.components(separatedBy: "\n")
            if hadTrailingNewline {
                lines.removeLast()
            }
            switch mode {
            case "line":
                let line = optionalInt(arguments, "line") ?? (lines.count + 1)
                guard line >= 1, line <= lines.count + 1 else {
                    throw SystemToolError.executionFailed(tool: name, message: "code_insert line is out of range for the file.")
                }
                lines.insert(code, at: line - 1)
            case "before", "after":
                let pattern = try requiredString(arguments, "pattern", tool: name)
                let matches = lines.indices.filter { lines[$0].contains(pattern) }
                guard matches.count == 1 else {
                    throw SystemToolError.executionFailed(tool: name, message: "code_insert pattern must match exactly one line.")
                }
                lines.insert(code, at: mode == "before" ? matches[0] : matches[0] + 1)
            default:
                throw SystemToolError.executionFailed(tool: name, message: "code_insert mode must be line, before, or after.")
            }
            var updated = lines.joined(separator: "\n")
            if hadTrailingNewline {
                updated += "\n"
            }
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: updated)
            return .object(["path": .string(path)])
        case "code_multi_edit":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            guard let rawEdits = arguments["edits"]?.arrayValue, !rawEdits.isEmpty else {
                throw SystemToolError.missingArgument(tool: name, argument: "edits")
            }
            let edits = try rawEdits.map { raw -> WorkspaceEdit in
                guard let oldText = raw["oldText"]?.stringValue, !oldText.isEmpty else {
                    throw SystemToolError.missingArgument(tool: name, argument: "oldText")
                }
                guard let newText = raw["newText"]?.stringValue else {
                    throw SystemToolError.missingArgument(tool: name, argument: "newText")
                }
                return WorkspaceEdit(
                    oldText: oldText,
                    newText: newText,
                    mode: raw["mode"]?.stringValue ?? "replace"
                )
            }
            return try await runtime.editWorkspaceFile(cwd: cwd, path: path, edits: edits)
        case "use_terminal", "run_command":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let command = try requiredString(arguments, "command", tool: name)
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 600
            return try await runTerminalCommand(tool: name, threadId: threadId, command: command, timeoutSeconds: timeoutSeconds, runtime: runtime)
        case "git_log_viewer":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            var params: [String: JSONValue] = [:]
            if let limit = optionalInt(arguments, "limit") {
                params["limit"] = .int(Int64(limit))
            }
            if let skip = optionalInt(arguments, "skip") {
                params["skip"] = .int(Int64(skip))
            }
            return try await runGitOperation(method: "git.log", threadId: threadId, params: params, tool: name, runtime: runtime)
        case "git_branch_compare":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let from = try requiredString(arguments, "from", tool: name)
            let to = try requiredString(arguments, "to", tool: name)
            return try await runGitOperation(method: "git.diff.range", threadId: threadId, params: ["from": .string(from), "to": .string(to)], tool: name, runtime: runtime)
        case "project_diff":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            var params: [String: JSONValue] = [:]
            if let path = optionalString(arguments, "path") {
                params["path"] = .string(path)
            }
            if let staged = optionalBool(arguments, "staged") {
                params["staged"] = .bool(staged)
            }
            return try await runGitOperation(method: "git.diff", threadId: threadId, params: params, tool: name, runtime: runtime)
        case "git_branch_manager":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let action = optionalString(arguments, "action") ?? "list"
            switch action {
            case "list":
                return try await runGitActionsOperation(method: "git.branches.list", threadId: threadId, params: [:], tool: name, timeoutSeconds: 60, runtime: runtime)
            case "create":
                let branch = try requiredString(arguments, "name", tool: name)
                return try await runGitActionsOperation(method: "git.branches.create", threadId: threadId, params: ["name": .string(branch)], tool: name, timeoutSeconds: 60, runtime: runtime)
            case "checkout":
                let branch = try requiredString(arguments, "name", tool: name)
                return try await runGitActionsOperation(method: "git.branches.checkout", threadId: threadId, params: ["name": .string(branch)], tool: name, timeoutSeconds: 60, runtime: runtime)
            case "delete":
                let branch = try requiredString(arguments, "name", tool: name)
                try Self.requireConfirm(arguments, tool: name, message: "Deleting a branch is irreversible; pass confirm=true.")
                var params: [String: JSONValue] = ["name": .string(branch), "confirm": .bool(true)]
                if let force = optionalBool(arguments, "force") {
                    params["force"] = .bool(force)
                }
                return try await runGitActionsOperation(method: "git.branches.delete", threadId: threadId, params: params, tool: name, timeoutSeconds: 60, runtime: runtime)
            default:
                throw SystemToolError.executionFailed(tool: name, message: "git_branch_manager action must be list, create, checkout, or delete.")
            }
        case "save_to_memory":
            let key = try requiredString(arguments, "key", tool: name)
            let value = try requiredString(arguments, "value", tool: name)
            return try await runtime.memoryStore(key: key, value: value, scope: optionalString(arguments, "scope"))
        case "use_mcp":
            let serverName = try requiredString(arguments, "serverName", tool: name)
            if serverName == "list" {
                return .array([.object([
                    "serverName": .string("coincide"),
                    "description": .string("The coincide MCP server: this app system tools, served over stdio."),
                    "tools": .int(Int64(SystemToolRegistry.systemTools.count)),
                ])])
            }
            guard serverName == "coincide" else {
                throw SystemToolError.executionFailed(tool: name, message: "No MCP server named \(serverName) is configured; this app serves only the coincide system-tools server.")
            }
            guard let toolName = optionalString(arguments, "toolName") else {
                throw SystemToolError.missingArgument(tool: name, argument: "toolName")
            }
            if toolName == "list_tools" {
                return .array(SystemToolRegistry.systemTools.map { .string($0.name) })
            }
            guard toolName != "use_mcp" else {
                throw SystemToolError.executionFailed(tool: name, message: "use_mcp cannot call itself.")
            }
            guard definition(named: toolName, for: toolset) != nil else {
                throw SystemToolError.unknownTool(toolName)
            }
            let rawArguments = optionalString(arguments, "arguments") ?? "{}"
            guard let data = rawArguments.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(JSONValue.self, from: data),
                  case .object(let toolArguments) = parsed else {
                throw SystemToolError.executionFailed(tool: name, message: "arguments must be a JSON object string.")
            }
            return try await execute(toolName, arguments: toolArguments, toolset: toolset, runtime: runtime)
        case "take_screenshot":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let includeScreenshot = optionalBool(arguments, "include_screenshot") ?? true
            return try await runComputerUseTool(tool: "get_desktop_state", threadId: threadId, arguments: ["include_screenshot": .bool(includeScreenshot)], runtime: runtime)
        case "start_subagent":
            let parentThreadId = try requiredString(arguments, "parentThreadId", tool: name)
            guard let rawWorkers = arguments["workers"]?.arrayValue, !rawWorkers.isEmpty else {
                throw SystemToolError.missingArgument(tool: name, argument: "workers")
            }
            let workers = try rawWorkers.map { raw -> WorkerSpawnRequest in
                guard let workerName = raw["name"]?.stringValue, !workerName.isEmpty else {
                    throw SystemToolError.missingArgument(tool: name, argument: "name")
                }
                guard let task = raw["task"]?.stringValue, !task.isEmpty else {
                    throw SystemToolError.missingArgument(tool: name, argument: "task")
                }
                return WorkerSpawnRequest(
                    name: workerName,
                    task: task,
                    targetFiles: raw["targetFiles"]?.arrayValue?.compactMap(\.stringValue) ?? []
                )
            }
            return try await runtime.spawnWorkers(parentThreadId: parentThreadId, workers: workers)
        case "git_stash_operator":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let action = try requiredString(arguments, "action", tool: name)
            if action == "pop" || action == "drop" {
                try Self.requireConfirm(arguments, tool: name, message: "Stash pop and drop are destructive; pass confirm=true.")
            }
            var params: [String: JSONValue] = ["action": .string(action)]
            if let message = optionalString(arguments, "message") {
                params["message"] = .string(message)
            }
            if let includeUntracked = optionalBool(arguments, "includeUntracked") {
                params["includeUntracked"] = .bool(includeUntracked)
            }
            if let reference = optionalString(arguments, "reference") {
                params["reference"] = .string(reference)
            }
            if let confirm = optionalBool(arguments, "confirm") {
                params["confirm"] = .bool(confirm)
            }
            if let paths = optionalStringArray(arguments, "paths") {
                params["paths"] = .array(paths.map { .string($0) })
            }
            return try await runGitOperation(method: "git.stash", threadId: threadId, params: params, tool: name, runtime: runtime)
        case "git_blame_inspector":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            var params: [String: JSONValue] = ["path": .string(path)]
            if let start = optionalInt(arguments, "start") {
                params["start"] = .int(Int64(start))
            }
            if let end = optionalInt(arguments, "end") {
                params["end"] = .int(Int64(end))
            }
            return try await runGitOperation(method: "git.blame", threadId: threadId, params: params, tool: name, runtime: runtime)
        case "git_bisect":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let action = try requiredString(arguments, "action", tool: name)
            var params: [String: JSONValue] = ["action": .string(action)]
            if let reference = optionalString(arguments, "reference") {
                params["reference"] = .string(reference)
            }
            if let good = optionalString(arguments, "good") {
                params["good"] = .string(good)
            }
            if let bad = optionalString(arguments, "bad") {
                params["bad"] = .string(bad)
            }
            return try await runGitOperation(method: "git.bisect", threadId: threadId, params: params, tool: name, runtime: runtime)
        case "git_cherry_pick":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let sha = try requiredString(arguments, "sha", tool: name)
            try Self.requireConfirm(arguments, tool: name, message: "Cherry-pick changes the working tree; pass confirm=true.")
            var params: [String: JSONValue] = ["sha": .string(sha), "confirm": .bool(true)]
            if let noCommit = optionalBool(arguments, "noCommit") {
                params["noCommit"] = .bool(noCommit)
            }
            return try await runGitOperation(method: "git.cherry_pick", threadId: threadId, params: params, tool: name, runtime: runtime)
        case "version_control_operator":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let action = try requiredString(arguments, "action", tool: name)
            switch action {
            case "status":
                return try await runGitOperation(method: "git.status", threadId: threadId, params: [:], tool: name, runtime: runtime)
            case "diff":
                var params: [String: JSONValue] = [:]
                if let path = optionalString(arguments, "path") {
                    params["path"] = .string(path)
                }
                if let staged = optionalBool(arguments, "staged") {
                    params["staged"] = .bool(staged)
                }
                return try await runGitOperation(method: "git.diff", threadId: threadId, params: params, tool: name, runtime: runtime)
            case "commit":
                let message = try requiredString(arguments, "message", tool: name)
                var params: [String: JSONValue] = ["action": .string("commit"), "message": .string(message)]
                if let paths = optionalStringArray(arguments, "paths") {
                    params["paths"] = .array(paths.map { .string($0) })
                }
                return try await runGitActionsOperation(method: "git.actions.run", threadId: threadId, params: params, tool: name, timeoutSeconds: 120, runtime: runtime)
            case "branch":
                if let branch = optionalString(arguments, "name") {
                    return try await runGitActionsOperation(method: "git.branches.create", threadId: threadId, params: ["name": .string(branch)], tool: name, timeoutSeconds: 60, runtime: runtime)
                }
                return try await runGitActionsOperation(method: "git.branches.list", threadId: threadId, params: [:], tool: name, timeoutSeconds: 60, runtime: runtime)
            case "rollback":
                try Self.requireConfirm(arguments, tool: name, message: "Rollback discards uncommitted changes; pass confirm=true.")
                let ref = optionalString(arguments, "ref") ?? "HEAD~1"
                return try await runGitOperation(method: "git.rollback", threadId: threadId, params: ["ref": .string(ref), "confirm": .bool(true)], tool: name, runtime: runtime)
            default:
                throw SystemToolError.executionFailed(tool: name, message: "version_control_operator action must be status, commit, branch, diff, or rollback.")
            }
        case "git_pr_summary":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let limit = optionalInt(arguments, "limit") ?? 20
            let from = optionalString(arguments, "from")
            let to = optionalString(arguments, "to")
            let log = try await runGitOperation(method: "git.log", threadId: threadId, params: ["limit": .int(Int64(limit))], tool: name, runtime: runtime)
            if let error = log["error"]?.stringValue, !error.isEmpty {
                throw SystemToolError.executionFailed(tool: name, message: error)
            }
            let diff: JSONValue
            if let from, let to {
                diff = try await runGitOperation(method: "git.diff.range", threadId: threadId, params: ["from": .string(from), "to": .string(to)], tool: name, runtime: runtime)
            } else {
                diff = try await runGitOperation(method: "git.diff.branch", threadId: threadId, params: [:], tool: name, runtime: runtime)
            }
            if let error = diff["error"]?.stringValue, !error.isEmpty {
                throw SystemToolError.executionFailed(tool: name, message: error)
            }
            let markdown = Self.prMarkdown(log: log, diff: diff, from: from, to: to)
            let files = diff["files"]?.arrayValue ?? diff["numstat"]?.arrayValue ?? []
            return .object([
                "markdown": .string(markdown),
                "from": .string(from ?? ""),
                "to": .string(to ?? ""),
                "commits": .int(Int64(log["commits"]?.arrayValue?.count ?? 0)),
                "files": .int(Int64(files.count)),
            ])
        case "git_conflict_resolver":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let action = optionalString(arguments, "action") ?? "detect"
            switch action {
            case "detect":
                let hits = try await runtime.searchWorkspaceRegex(cwd: cwd, pattern: "^(<{7}|={7}|>{7})", limit: 200)
                var files: [String] = []
                for hit in hits where !files.contains(hit.path) {
                    files.append(hit.path)
                }
                return .object(["conflictedFiles": .array(files.map { .string($0) }), "count": .int(Int64(files.count))])
            case "resolve":
                let path = try requiredString(arguments, "path", tool: name)
                let strategy = optionalString(arguments, "strategy") ?? "ours"
                let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
                let (resolved, hunks) = try Self.resolveConflicts(content: document.content, strategy: strategy, tool: name)
                try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: resolved)
                return .object(["path": .string(path), "resolved": .bool(true), "hunks": .int(Int64(hunks)), "strategy": .string(strategy)])
            default:
                throw SystemToolError.executionFailed(tool: name, message: "git_conflict_resolver action must be detect or resolve.")
            }
        case "project_snapshot":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let root = try await Self.resolveThreadRoot(threadId: threadId, tool: name, runtime: runtime)
            let head = try await Self.threadHead(threadId: threadId, tool: name, runtime: runtime)
            let label = optionalString(arguments, "label") ?? "Manual snapshot"
            return try await runWorkspaceApiOperation(method: "git.checkpoints.create", threadId: threadId, params: ["expectedRoot": .string(root), "expectedHead": .string(head), "label": .string(label)], tool: name, timeoutSeconds: 120, runtime: runtime)
        case "project_changelog":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let root = try await Self.resolveThreadRoot(threadId: threadId, tool: name, runtime: runtime)
            return try await runWorkspaceApiOperation(method: "git.checkpoints.list", threadId: threadId, params: ["expectedRoot": .string(root)], tool: name, timeoutSeconds: 30, runtime: runtime)
        case "project_restore":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let checkpointId = try requiredString(arguments, "checkpointId", tool: name)
            try Self.requireConfirm(arguments, tool: name, message: "Restoring a checkpoint discards uncommitted and untracked changes; pass confirm=true.")
            let root = try await Self.resolveThreadRoot(threadId: threadId, tool: name, runtime: runtime)
            return try await runWorkspaceApiOperation(method: "git.checkpoints.restore", threadId: threadId, params: ["expectedRoot": .string(root), "checkpointId": .string(checkpointId), "confirm": .bool(true)], tool: name, timeoutSeconds: 120, runtime: runtime)
        case "safe_undo":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            try Self.requireConfirm(arguments, tool: name, message: "safe_undo restores the second-newest snapshot and discards uncommitted and untracked changes; pass confirm=true.")
            let root = try await Self.resolveThreadRoot(threadId: threadId, tool: name, runtime: runtime)
            let listed = try await runWorkspaceApiOperation(method: "git.checkpoints.list", threadId: threadId, params: ["expectedRoot": .string(root)], tool: name, timeoutSeconds: 30, runtime: runtime)
            let checkpoints = listed["checkpoints"]?.arrayValue ?? []
            guard checkpoints.count >= 2 else {
                throw SystemToolError.executionFailed(tool: name, message: "safe_undo requires at least two snapshots.")
            }
            guard let target = checkpoints[1]["id"]?.stringValue else {
                throw SystemToolError.executionFailed(tool: name, message: "Snapshot list is missing checkpoint ids.")
            }
            let restored = try await runWorkspaceApiOperation(method: "git.checkpoints.restore", threadId: threadId, params: ["expectedRoot": .string(root), "checkpointId": .string(target), "confirm": .bool(true)], tool: name, timeoutSeconds: 120, runtime: runtime)
            return .object(["restoredId": .string(target), "restore": restored])
        case "safe_validate_changes":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            var issues: [[String: JSONValue]] = []
            if let path = optionalString(arguments, "path") {
                let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
                issues.append(contentsOf: Self.validateContent(path: path, content: document.content))
            } else {
                let hits = try await runtime.searchWorkspaceRegex(cwd: cwd, pattern: "^(<{7}|={7}|>{7})", limit: 200)
                var files: [String] = []
                for hit in hits where !files.contains(hit.path) {
                    files.append(hit.path)
                }
                for path in files {
                    let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
                    issues.append(contentsOf: Self.validateContent(path: path, content: document.content))
                }
            }
            return .object(["issues": .array(issues.map { .object($0) }), "count": .int(Int64(issues.count))])
        default:
            throw SystemToolError.unknownTool(name)
        }
    }

    private static func workerJSON(_ record: WorkerRecord) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(record.id),
            "name": .string(record.name),
            "parentThreadId": .string(record.parentThreadId),
            "threadId": .string(record.threadId),
            "task": .string(record.task),
            "provider": .string(record.provider),
            "targetFiles": .array(record.targetFiles.map { .string($0) }),
            "status": .string(record.status),
            "cancelRequested": .bool(record.cancelRequested),
            "transcriptItems": .int(Int64(record.transcriptItems)),
            "elapsedSeconds": .double(record.elapsedSeconds),
            "createdAt": .double(record.createdAt),
            "startedAt": .double(record.startedAt),
        ]
        if let completedAt = record.completedAt {
            object["completedAt"] = .double(completedAt)
        } else {
            object["completedAt"] = .null
        }
        if let error = record.error {
            object["error"] = .string(error)
        } else {
            object["error"] = .null
        }
        if let result = record.result {
            object["result"] = .string(result)
        } else {
            object["result"] = .null
        }
        if let progress = record.progress {
            object["progress"] = .object([
                "stage": .string(progress.stage),
                "transcriptItems": .int(Int64(progress.transcriptItems)),
                "elapsedSeconds": .double(progress.elapsedSeconds),
            ])
        }
        return .object(object)
    }

    private static func computerUseArguments(
        _ arguments: [String: JSONValue],
        definition: SystemToolDefinition,
        tool: String
    ) throws -> [String: JSONValue] {
        var toolArguments: [String: JSONValue] = [:]
        for parameter in definition.parameters {
            if parameter.name == "threadId" {
                continue
            }
            guard let value = arguments[parameter.name] else {
                if parameter.required {
                    throw SystemToolError.missingArgument(tool: tool, argument: parameter.name)
                }
                continue
            }
            let present: Bool
            switch parameter.type {
            case "string":
                present = value.stringValue.map { !$0.isEmpty } ?? false
            case "integer":
                present = value.intValue != nil
            case "number":
                present = value.doubleValue != nil
            case "boolean":
                present = value.boolValue != nil
            case "array":
                present = value.arrayValue != nil
            default:
                present = true
            }
            guard present || !parameter.required else {
                throw SystemToolError.missingArgument(tool: tool, argument: parameter.name)
            }
            if present {
                toolArguments[parameter.name] = value
            }
        }
        return toolArguments
    }

    private static func runComputerUseTool(
        tool: String,
        threadId: String,
        arguments: [String: JSONValue],
        runtime: AgentsRuntimeClient
    ) async throws -> JSONValue {
        let started = try await runtime.engineRPC(
            method: "computer_use.request",
            params: [
                "threadId": .string(threadId),
                "request": .object([
                    "action": .string("call"),
                    "name": .string(tool),
                    "arguments": .object(arguments),
                ]),
            ]
        )
        guard let operationId = started["operationId"]?.stringValue else {
            throw SystemToolError.executionFailed(tool: tool, message: "Computer Use request did not return an operationId.")
        }
        for _ in 0..<60 {
            let polled = try await runtime.engineRPC(
                method: "computer_use.result",
                params: [
                    "threadId": .string(threadId),
                    "operationId": .string(operationId),
                ]
            )
            if polled["ready"]?.boolValue == true {
                if let error = polled["error"]?.stringValue {
                    throw SystemToolError.executionFailed(tool: tool, message: "Computer Use failed: \(error)")
                }
                return polled["result"] ?? .null
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw SystemToolError.operationTimeout(tool: tool)
    }

    private static func runGitOperation(
        method: String,
        threadId: String,
        params: [String: JSONValue],
        tool: String,
        runtime: AgentsRuntimeClient
    ) async throws -> JSONValue {
        var startParams = params
        startParams["threadId"] = .string(threadId)
        let started = try await runtime.engineRPC(method: method, params: startParams)
        guard let operationId = started["operationId"]?.stringValue else {
            throw SystemToolError.executionFailed(tool: tool, message: "Git operation did not return an operationId.")
        }
        for _ in 0..<100 {
            let polled = try await runtime.engineRPC(
                method: "workspace.result",
                params: ["operationId": .string(operationId), "threadId": .string(threadId)]
            )
            if polled["ready"]?.boolValue == true {
                return polled["result"] ?? .null
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SystemToolError.operationTimeout(tool: tool)
    }

    private static func runGitActionsOperation(
        method: String,
        threadId: String,
        params: [String: JSONValue],
        tool: String,
        timeoutSeconds: Int,
        runtime: AgentsRuntimeClient
    ) async throws -> JSONValue {
        var startParams = params
        startParams["threadId"] = .string(threadId)
        let started = try await runtime.engineRPC(method: method, params: startParams)
        guard let operationId = started["operationId"]?.stringValue else {
            throw SystemToolError.executionFailed(tool: tool, message: "Git operation did not return an operationId.")
        }
        let attempts = max(1, timeoutSeconds * 4)
        for _ in 0..<attempts {
            let polled = try await runtime.engineRPC(
                method: "git.actions.result",
                params: ["operationId": .string(operationId), "threadId": .string(threadId)]
            )
            if polled["ready"]?.boolValue == true {
                return polled["result"] ?? .null
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw SystemToolError.operationTimeout(tool: tool)
    }

    private static func runTerminalCommand(
        tool: String,
        threadId: String,
        command: String,
        timeoutSeconds: Int,
        runtime: AgentsRuntimeClient
    ) async throws -> JSONValue {
        let terminalId = try await runtime.createTerminal(threadID: threadId)
        try await runtime.sendTerminalInput(id: terminalId, data: command + "\n")
        try await runtime.sendTerminalInput(id: terminalId, data: "echo __AGENTS_TOOL_DONE__:$?\n")
        let clampedTimeout = min(max(timeoutSeconds, 5), 3600)
        let deadline = Date().addingTimeInterval(TimeInterval(clampedTimeout))
        var lastLines: [String] = []
        while Date() < deadline {
            let snapshot = try await runtime.engineRPC(method: "terminal.read", params: ["terminalId": .string(terminalId)])
            if let exitCode = snapshot["exitCode"]?.intValue {
                throw SystemToolError.executionFailed(tool: tool, message: "Terminal closed with exit code \(exitCode) before the command finished.")
            }
            let lines = snapshot["lines"]?.arrayValue?.compactMap(\.stringValue) ?? []
            lastLines = lines
            for line in lines {
                guard let marker = line.range(of: "__AGENTS_TOOL_DONE__:") else { continue }
                let codeText = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
                let exitCode = Int(codeText) ?? -1
                let output = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return .object([
                    "terminalId": .string(terminalId),
                    "exitCode": .int(Int64(exitCode)),
                    "timedOut": .bool(false),
                    "output": .string(output),
                ])
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        return .object([
            "terminalId": .string(terminalId),
            "exitCode": .null,
            "timedOut": .bool(true),
            "output": .string(lastLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)),
        ])
    }

    private static func requireConfirm(_ arguments: [String: JSONValue], tool: String, message: String) throws {
        guard let confirm = arguments["confirm"]?.boolValue else {
            throw SystemToolError.missingArgument(tool: tool, argument: "confirm")
        }
        guard confirm else {
            throw SystemToolError.executionFailed(tool: tool, message: message)
        }
    }

    private static func assertFileAbsent(cwd: String, path: String, tool: String) throws {
        let base = URL(fileURLWithPath: ExternalEditorService.expandedPath(cwd)).standardized
        let target = base.appendingPathComponent(path).standardized
        guard target.path.hasPrefix(base.path + "/") else {
            throw SystemToolError.executionFailed(tool: tool, message: "Path escapes the working directory.")
        }
        if FileManager.default.fileExists(atPath: target.path) {
            throw SystemToolError.executionFailed(tool: tool, message: "A file already exists at that path; use write_file to overwrite it.")
        }
    }

    private static func resolveThreadRoot(threadId: String, tool: String, runtime: AgentsRuntimeClient) async throws -> String {
        if let doc = try? await runtime.engineRPC(method: "threads.read", params: ["threadId": .string(threadId), "itemLimit": .int(0)]),
           let worktree = doc["worktreePath"]?.stringValue, !worktree.isEmpty {
            return URL(fileURLWithPath: ExternalEditorService.expandedPath(worktree)).resolvingSymlinksInPath().path
        }
        let workspace = try await runtime.fetchWorkspace()
        guard let thread = workspace.threads.first(where: { $0.id.uuidString.lowercased() == threadId.lowercased() }),
              let project = workspace.projects.first(where: { $0.id == thread.projectID }) else {
            throw SystemToolError.executionFailed(tool: tool, message: "Could not resolve the thread working directory.")
        }
        return URL(fileURLWithPath: ExternalEditorService.expandedPath(project.path)).resolvingSymlinksInPath().path
    }

    private static func threadHead(threadId: String, tool: String, runtime: AgentsRuntimeClient) async throws -> String {
        let log = try await runGitOperation(method: "git.log", threadId: threadId, params: ["limit": .int(1)], tool: tool, runtime: runtime)
        guard let sha = log["commits"]?.arrayValue?.first?["sha"]?.stringValue, !sha.isEmpty else {
            throw SystemToolError.executionFailed(tool: tool, message: "Could not read the thread HEAD commit.")
        }
        return sha
    }

    private static func runWorkspaceApiOperation(
        method: String,
        threadId: String,
        params: [String: JSONValue],
        tool: String,
        timeoutSeconds: Int,
        runtime: AgentsRuntimeClient
    ) async throws -> JSONValue {
        var startParams = params
        startParams["threadId"] = .string(threadId)
        let started = try await runtime.engineRPC(method: method, params: startParams)
        guard let operationId = started["operationId"]?.stringValue else {
            throw SystemToolError.executionFailed(tool: tool, message: "Workspace operation did not return an operationId.")
        }
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let polled = try await runtime.engineRPC(
                method: "git.workspace.result",
                params: ["operationId": .string(operationId), "threadId": .string(threadId)]
            )
            if polled["ready"]?.boolValue == true {
                let result = polled["result"] ?? .null
                if let error = result["error"]?.stringValue, !error.isEmpty {
                    throw SystemToolError.executionFailed(tool: tool, message: error)
                }
                return result
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw SystemToolError.operationTimeout(tool: tool)
    }

    private static func prMarkdown(log: JSONValue, diff: JSONValue, from: String?, to: String?) -> String {
        var lines: [String] = ["# PR Summary", ""]
        if let from, let to {
            lines.append("Range: \(from) ... \(to)")
        } else {
            lines.append("Range: branch against its base")
        }
        lines.append("")
        lines.append("## Commits")
        let commits = log["commits"]?.arrayValue ?? []
        if commits.isEmpty {
            lines.append("No commits.")
        } else {
            for commit in commits {
                let sha = commit["sha"]?.stringValue ?? ""
                let subject = commit["subject"]?.stringValue ?? ""
                let author = commit["authorName"]?.stringValue ?? ""
                lines.append("- \(String(sha.prefix(8))) \(subject) (\(author))")
            }
        }
        lines.append("")
        lines.append("## Files Changed")
        let files = diff["files"]?.arrayValue ?? diff["numstat"]?.arrayValue ?? []
        if files.isEmpty {
            lines.append("No files changed.")
        } else {
            for file in files {
                let path = file["path"]?.stringValue ?? ""
                let additions = file["additions"]?.intValue ?? 0
                let deletions = file["deletions"]?.intValue ?? 0
                lines.append("- \(path) (+\(additions)/-\(deletions))")
            }
        }
        let patch = diff["diff"]?.stringValue ?? diff["patch"]?.stringValue ?? ""
        if !patch.isEmpty {
            lines.append("")
            lines.append("## Diff")
            lines.append("```diff")
            if patch.count > 50000 {
                lines.append(String(patch.prefix(50000)))
                lines.append("... (diff truncated)")
            } else {
                lines.append(patch)
            }
            lines.append("```")
        }
        return lines.joined(separator: "\n")
    }

    private static func resolveConflicts(content: String, strategy: String, tool: String) throws -> (String, Int) {
        guard strategy == "ours" || strategy == "theirs" || strategy == "both" else {
            throw SystemToolError.executionFailed(tool: tool, message: "git_conflict_resolver strategy must be ours, theirs, or both.")
        }
        var output: [String] = []
        var ours: [String] = []
        var theirs: [String] = []
        var state = 0
        var hunks = 0
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("<<<<<<<") {
                guard state == 0 else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Nested conflict marker in file.")
                }
                state = 1
                ours = []
                theirs = []
                hunks += 1
                continue
            }
            if line == "=======" {
                guard state == 1 else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Conflict separator without an opening marker.")
                }
                state = 2
                continue
            }
            if line.hasPrefix(">>>>>>>") {
                guard state == 2 else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Conflict end marker without an opening marker.")
                }
                state = 0
                if strategy == "ours" || strategy == "both" {
                    output.append(contentsOf: ours)
                }
                if strategy == "theirs" || strategy == "both" {
                    output.append(contentsOf: theirs)
                }
                continue
            }
            if state == 1 {
                ours.append(line)
            } else if state == 2 {
                theirs.append(line)
            } else {
                output.append(line)
            }
        }
        guard state == 0 else {
            throw SystemToolError.executionFailed(tool: tool, message: "Unclosed conflict marker in file.")
        }
        guard hunks > 0 else {
            throw SystemToolError.executionFailed(tool: tool, message: "No conflict markers found in file.")
        }
        return (output.joined(separator: "\n"), hunks)
    }

    private static func validateContent(path: String, content: String) -> [[String: JSONValue]] {
        var issues: [[String: JSONValue]] = []
        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("<<<<<<<") || line.hasPrefix(">>>>>>>") || line == "=======" {
                issues.append(["path": .string(path), "line": .int(Int64(index + 1)), "issue": .string("Merge conflict marker: \(line)")])
            }
        }
        if !content.isEmpty && !content.hasSuffix("\n") {
            issues.append(["path": .string(path), "line": .int(Int64(lines.count)), "issue": .string("File does not end with a trailing newline.")])
        }
        return issues
    }

    private static func requiredString(_ arguments: [String: JSONValue], _ name: String, tool: String) throws -> String {
        guard let value = arguments[name]?.stringValue, !value.isEmpty else {
            throw SystemToolError.missingArgument(tool: tool, argument: name)
        }
        return value
    }

    private static func optionalString(_ arguments: [String: JSONValue], _ name: String) -> String? {
        arguments[name]?.stringValue
    }

    private static func optionalInt(_ arguments: [String: JSONValue], _ name: String) -> Int? {
        arguments[name]?.intValue
    }

    private static func optionalBool(_ arguments: [String: JSONValue], _ name: String) -> Bool? {
        arguments[name]?.boolValue
    }

    private static func optionalStringArray(_ arguments: [String: JSONValue], _ name: String) -> [String]? {
        arguments[name]?.arrayValue?.compactMap(\.stringValue)
    }
}
