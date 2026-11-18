import AppKit
import CoincideRemoteKit
import CryptoKit
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
            ]
        ),
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
            description: "Run git with an action of status, commit, branch, diff, or rollback. Rollback resets hard to HEAD, HEAD~N, HEAD^N, or a full SHA and requires confirm=true.",
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
        SystemToolDefinition(
            name: "create_artifact",
            description: "Create or update a Markdown artifact in .assist_temp/artifacts, or append to it. The artifact name stays inside that directory.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "name", type: "string", required: true, description: "Artifact name, a plain file name without any path separator."),
                SystemToolParameter(name: "content", type: "string", required: true, description: "Markdown content to write."),
                SystemToolParameter(name: "kind", type: "string", required: false, description: "artifact or execution_plan. Defaults to artifact."),
                SystemToolParameter(name: "append", type: "boolean", required: false, description: "Append to the existing artifact instead of replacing it. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "list_artifacts",
            description: "List Markdown artifacts in .assist_temp/artifacts, newest first.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "read_artifact",
            description: "Read one Markdown artifact from .assist_temp/artifacts. Content over 60000 characters is truncated and marked.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "name", type: "string", required: true, description: "Artifact name, a plain file name without any path separator."),
            ]
        ),
        SystemToolDefinition(
            name: "delete_artifact",
            description: "Permanently delete one Markdown artifact from .assist_temp/artifacts. Requires confirm=true. agent_notes.md is protected and cannot be deleted.",
            action: "workspace.delete_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "name", type: "string", required: true, description: "Artifact name, a plain file name without any path separator."),
                SystemToolParameter(name: "confirm", type: "boolean", required: true, description: "Must be true. Deleting an artifact is permanent."),
            ]
        ),
        SystemToolDefinition(
            name: "format_json_file",
            description: "Validate a JSON file and rewrite it pretty-printed with sorted keys.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "csv_to_json",
            description: "Parse a tabular CSV file and write its records as a JSON array of objects.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path relative to the working directory. Defaults to the input path with a .json extension."),
            ]
        ),
        SystemToolDefinition(
            name: "json_to_csv",
            description: "Convert a JSON array of objects into RFC 4180 CSV and write it to a file.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path relative to the working directory. Defaults to the input path with a .csv extension."),
            ]
        ),
        SystemToolDefinition(
            name: "plist_to_json",
            description: "Convert an Apple property list file into a formatted JSON file.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path relative to the working directory. Defaults to the input path with a .json extension."),
            ]
        ),
        SystemToolDefinition(
            name: "json_to_plist",
            description: "Convert a JSON file into an Apple property list file, XML or binary.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path relative to the working directory. Defaults to the input path with a .plist extension."),
                SystemToolParameter(name: "format", type: "string", required: false, description: "xml or binary. Defaults to xml."),
            ]
        ),
        SystemToolDefinition(
            name: "json_validate",
            description: "Validate JSON syntax in a file. Writes back pretty-printed with sorted keys only when write is true.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "write", type: "boolean", required: false, description: "Write the formatted JSON back to the file. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "json_validator_tool",
            description: "Validate JSON syntax and report structural errors without writing anything.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "yaml_validate",
            description: "Heuristically validate YAML: tabs, unbalanced brackets and quotes, duplicate top-level keys. Writes a normalized copy only when write is true and validation passes.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "write", type: "boolean", required: false, description: "Write the normalized YAML back to the file. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "yaml_parser_tool",
            description: "Validate YAML and convert its mapping, list, and scalar subset into a structured JSON representation. No anchors, aliases, or block scalars.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "plist_edit",
            description: "Get, set, or delete one key in a property list file, with an atomic write and a verify re-read. Keys may use dot paths for nested dictionaries.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "get, set, or delete."),
                SystemToolParameter(name: "key", type: "string", required: true, description: "Property list key, optionally a dot path."),
                SystemToolParameter(name: "value", type: "string", required: false, description: "String value for set."),
            ]
        ),
        SystemToolDefinition(
            name: "plist_editor",
            description: "Inspect, read, set, or delete keys in an Apple property list file, XML or binary.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "action", type: "string", required: false, description: "read, get, set, or delete. Defaults to read."),
                SystemToolParameter(name: "key", type: "string", required: false, description: "Property list key, optionally a dot path."),
                SystemToolParameter(name: "value", type: "string", required: false, description: "String value for set."),
            ]
        ),
        SystemToolDefinition(
            name: "binary_plist_converter",
            description: "Convert a property list file between binary and XML representations.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path relative to the working directory. Defaults to the input path with a converted extension."),
                SystemToolParameter(name: "format", type: "string", required: true, description: "Target representation: xml or binary."),
            ]
        ),
        SystemToolDefinition(
            name: "file_metadata",
            description: "Read size, modification time, symlink target, and executable bit for one file or directory, from the real directory read.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "file_hash_verify",
            description: "Hash a file and compare it to an expected hash. A mismatch returns match false, not an error.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "expectedHash", type: "string", required: true, description: "Expected lowercase hex digest."),
                SystemToolParameter(name: "algorithm", type: "string", required: false, description: "sha256, sha512, sha1, or md5. Defaults to sha256."),
            ]
        ),
        SystemToolDefinition(
            name: "generate_file_checksum",
            description: "Compute the SHA-256, SHA-512, SHA-1, and MD5 checksums of a file.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "file_checksum_verifier",
            description: "Compute the SHA-256 and MD5 checksums of a file, optionally verifying one expected hash.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "expectedHash", type: "string", required: false, description: "Expected lowercase hex digest to verify."),
                SystemToolParameter(name: "algorithm", type: "string", required: false, description: "sha256 or md5. Defaults to sha256."),
            ]
        ),
        SystemToolDefinition(
            name: "file_compare_diff",
            description: "Compare two files line by line and produce a unified diff with added and removed line counts.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "otherPath", type: "string", required: true, description: "Second file path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "file_head_preview",
            description: "Read the first N lines of a file without dumping the whole file.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "lines", type: "integer", required: false, description: "Lines to return, 1 to 5000. Defaults to 20."),
            ]
        ),
        SystemToolDefinition(
            name: "code_generate",
            description: "Scaffold a file from a built-in template: swift_struct, swift_class, swiftui_view, or test. Refuses to overwrite an existing file.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "template", type: "string", required: true, description: "swift_struct, swift_class, swiftui_view, or test."),
                SystemToolParameter(name: "module", type: "string", required: false, description: "Module name used by the test template. Defaults to the project directory name."),
            ]
        ),
        SystemToolDefinition(
            name: "code_format",
            description: "Normalize a text file or directory: trailing whitespace, blank-line collapse, tab expansion, trailing newline. This is basic normalization, not a real formatter.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory relative to the working directory. Defaults to the working directory itself."),
            ]
        ),
        SystemToolDefinition(
            name: "swift_format_lint",
            description: "Check or format Swift files with the swiftformat CLI when it is installed. If swiftformat is absent the tool reports that honestly instead of pretending.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "mode", type: "string", required: false, description: "lint or format. Defaults to lint."),
            ]
        ),
        SystemToolDefinition(
            name: "code_mutation_engine",
            description: "Replace the brace-balanced body of a named symbol, or an exact target block, in one file. Matching is textual and the output is never syntax-checked.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "replacement", type: "string", required: true, description: "Replacement text for the symbol body or target block."),
                SystemToolParameter(name: "symbol", type: "string", required: false, description: "Symbol name whose brace-balanced body is replaced."),
                SystemToolParameter(name: "target", type: "string", required: false, description: "Exact block of text to replace."),
            ]
        ),
        SystemToolDefinition(
            name: "patch_application_engine",
            description: "Replace a verbatim original block with updated text in a file, replacing every occurrence.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "original", type: "string", required: true, description: "Verbatim block to replace."),
                SystemToolParameter(name: "updated", type: "string", required: true, description: "Replacement text."),
            ]
        ),
        SystemToolDefinition(
            name: "automated_repair_engine",
            description: "Annotation only: insert an AssistAutoRepair review-required annotation above the named lines. It does not fix anything and does not rebuild.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "errors", type: "array", required: true, description: "Line numbers, 1-based, to annotate."),
            ]
        ),
        SystemToolDefinition(
            name: "regex_replace_in_files",
            description: "Search with a regular expression and replace every match across the matching files.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "pattern", type: "string", required: true, description: "Regular expression to search for."),
                SystemToolParameter(name: "replacement", type: "string", required: true, description: "Replacement text."),
                SystemToolParameter(name: "query", type: "string", required: false, description: "Optional substring filter over file paths."),
            ]
        ),
        SystemToolDefinition(
            name: "symbol_rename_project",
            description: "Rename a symbol across Swift files with whole-word matching.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "oldName", type: "string", required: true, description: "Existing symbol name."),
                SystemToolParameter(name: "newName", type: "string", required: true, description: "New symbol name."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to search, relative to the working directory. Defaults to the working directory itself."),
            ]
        ),
        SystemToolDefinition(
            name: "symbol_move_file",
            description: "Move a brace-balanced symbol block from a source file to a destination file, verified with a restore on failure.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "sourcePath", type: "string", required: true, description: "Source file path relative to the working directory."),
                SystemToolParameter(name: "destinationPath", type: "string", required: true, description: "Destination file path relative to the working directory."),
                SystemToolParameter(name: "symbol", type: "string", required: true, description: "Symbol name whose block is moved."),
            ]
        ),
        SystemToolDefinition(
            name: "import_cleanup",
            description: "Remove unused import lines from a Swift file. Protected modules are never removed.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "batch_rename_files",
            description: "Rename files matching a substring in a directory. With dryRun true it only reports the planned renames.",
            action: "workspace.move_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "directory", type: "string", required: false, description: "Directory to rename inside. Defaults to the working directory itself."),
                SystemToolParameter(name: "pattern", type: "string", required: true, description: "Substring to match in file names."),
                SystemToolParameter(name: "replacement", type: "string", required: true, description: "Replacement substring."),
                SystemToolParameter(name: "dryRun", type: "boolean", required: false, description: "Report planned renames without moving anything. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "file_backup",
            description: "Copy a file to .assist_temp/backups with a timestamped .bak name and verify the size.",
            action: "workspace.copy_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "session_export",
            description: "Write a Markdown session export with title, timestamp, session id, workspace, and notes. Never reads conversation history.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "title", type: "string", required: true, description: "Export title."),
                SystemToolParameter(name: "sessionId", type: "string", required: false, description: "Session id to record. Defaults to a new id."),
                SystemToolParameter(name: "notes", type: "string", required: false, description: "Notes to include in the export."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Output path. Defaults to a timestamped file under .assist_temp."),
                SystemToolParameter(name: "overwrite", type: "boolean", required: false, description: "Allow overwriting an existing export file. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "markdown_toc_generate",
            description: "Generate a table of contents from a Markdown file headings and insert or update it between TOC markers.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "readme_generate",
            description: "Generate a README skeleton from a real inspection of the repository contents. Refuses to overwrite without overwrite true.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Output path. Defaults to README.md."),
                SystemToolParameter(name: "overwrite", type: "boolean", required: false, description: "Allow overwriting an existing README. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "docs_generate",
            description: "Generate Markdown API docs from the public declarations in Swift sources. Refuses to overwrite without overwrite true.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Source file or directory. Defaults to the working directory itself."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path. Defaults to API.md."),
                SystemToolParameter(name: "overwrite", type: "boolean", required: false, description: "Allow overwriting an existing docs file. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "test_data_factory",
            description: "Write a JSON or Swift test fixture from a field list such as id:Int,name:String. Refuses to overwrite without overwrite true.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "format", type: "string", required: true, description: "json or swift."),
                SystemToolParameter(name: "fields", type: "string", required: true, description: "Comma-separated field list, each name:Type."),
                SystemToolParameter(name: "overwrite", type: "boolean", required: false, description: "Allow overwriting an existing fixture. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "ui_test_scaffold",
            description: "Write an XCTest UI test scaffold for an app. Refuses to overwrite without overwrite true.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "appName", type: "string", required: false, description: "App name under test. Defaults to the project directory name."),
                SystemToolParameter(name: "overwrite", type: "boolean", required: false, description: "Allow overwriting an existing test file. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "test_snapshot_manage",
            description: "List snapshot references under __Snapshots__, or clean unreferenced snapshots with confirm true. Unreferenced detection is heuristic.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "action", type: "string", required: false, description: "list or clean. Defaults to list."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Snapshots directory. Defaults to __Snapshots__."),
                SystemToolParameter(name: "confirm", type: "boolean", required: false, description: "Must be true to clean snapshots."),
            ]
        ),
        SystemToolDefinition(
            name: "open_in_finder",
            description: "Open a file or directory in macOS Finder.",
            action: "system.open_in_finder",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "reveal_in_finder",
            description: "Reveal and highlight a file or directory in macOS Finder.",
            action: "system.reveal_in_finder",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "image_encode_base64",
            description: "Read an image file and return its Base64 encoding, optionally as a data URI.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "dataURI", type: "boolean", required: false, description: "Return a data URI instead of bare Base64. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "image_decode_base64",
            description: "Decode a Base64 string into an image file on disk.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "base64", type: "string", required: true, description: "Base64-encoded image bytes."),
            ]
        ),
        SystemToolDefinition(
            name: "image_get_dimensions",
            description: "Read image width, height, and format with the sips CLI and return its real output.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "image_convert_format",
            description: "Convert an image between PNG, JPEG, TIFF, BMP, and GIF with the sips CLI and return its real output.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "format", type: "string", required: true, description: "png, jpg, tiff, bmp, or gif."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path relative to the working directory. Defaults to the input path with the new extension."),
                SystemToolParameter(name: "quality", type: "integer", required: false, description: "JPEG quality, 0 to 100."),
            ]
        ),
        SystemToolDefinition(
            name: "image_generate_thumbnail",
            description: "Generate a scaled thumbnail preserving aspect ratio with the sips CLI and return its real output.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path relative to the working directory. Defaults to the input path with a -thumb suffix."),
                SystemToolParameter(name: "maxPixels", type: "integer", required: false, description: "Maximum thumbnail pixel size. Defaults to 256."),
            ]
        ),
        SystemToolDefinition(
            name: "image_extract_metadata",
            description: "Extract embedded EXIF, TIFF, GPS, and camera metadata with the mdls CLI and return its real output.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "zip_file",
            description: "Compress a file or directory into a .zip archive with the system ditto CLI and return its real output and exit code.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: true, description: "Archive path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "unzip_file",
            description: "Extract a .zip archive into a target directory with the system ditto CLI and return its real output and exit code.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "destination", type: "string", required: true, description: "Target directory relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "tar_archive_create",
            description: "Create a .tar or .tar.gz archive from a directory or file with the tar CLI and return its real output and exit code.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: true, description: "Archive path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "tar_archive_extract",
            description: "Extract a .tar or .tar.gz archive into a destination directory with the tar CLI and return its real output and exit code.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "destination", type: "string", required: true, description: "Destination directory relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "gzip_compress_file",
            description: "Compress a single file to a .gz file with the system gzip CLI and return its real output and exit code.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path relative to the working directory. Defaults to the input path with a .gz extension."),
            ]
        ),
        SystemToolDefinition(
            name: "gzip_decompress_file",
            description: "Decompress a .gz file into a destination file with the system gzip CLI and return its real output and exit code.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path relative to the working directory. Defaults to the input path without the .gz extension."),
            ]
        ),
        SystemToolDefinition(
            name: "count_file_lines",
            description: "Count total, code, comment, and blank lines across workspace files or directories.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory. Defaults to the working directory itself."),
            ]
        ),
        SystemToolDefinition(
            name: "extract_code_symbols",
            description: "Extract class, struct, enum, protocol, actor, func, and extension declarations from source code.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Source file or directory. Defaults to the working directory itself."),
            ]
        ),
        SystemToolDefinition(
            name: "find_duplicate_files",
            description: "Find byte-identical duplicate files by SHA-256 content hashing.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to search. Defaults to the working directory itself."),
            ]
        ),
        SystemToolDefinition(
            name: "env_capture_logs",
            description: "Capture a memory snapshot and return its metadata: timestamp, message, and id. It does not read log contents.",
            action: "memory.snapshot",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "scope", type: "string", required: false, description: "global or workspace:<identifier>. Defaults to global."),
                SystemToolParameter(name: "query", type: "string", required: false, description: "Keyword substring filter over keys and values."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum entries to capture."),
            ]
        ),
        SystemToolDefinition(
            name: "project_build",
            description: "Build the thread project with xcodebuild and return the real diagnostics, exit code, and output.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme to build."),
                SystemToolParameter(name: "configuration", type: "string", required: false, description: "Build configuration, such as Debug or Release."),
                SystemToolParameter(name: "destination", type: "string", required: false, description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "project_test",
            description: "Run the thread project tests with xcodebuild test and return the real test summary, diagnostics, exit code, and output.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme to test."),
                SystemToolParameter(name: "configuration", type: "string", required: false, description: "Build configuration, such as Debug or Release."),
                SystemToolParameter(name: "destination", type: "string", required: false, description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "compiler_diagnostics_engine",
            description: "Run a real build and return only its parsed compiler diagnostics with error and warning counts.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "kind", type: "string", required: false, description: "xcodebuild or swiftpm. Defaults to xcodebuild."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme to build."),
                SystemToolParameter(name: "destination", type: "string", required: false, description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "dependency_resolution_engine",
            description: "Resolve the thread project package dependencies with swift package resolve or xcodebuild and return the real result.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "kind", type: "string", required: false, description: "swiftpm or xcode. Defaults to swiftpm."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme for xcode dependency resolution."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "generate_xcodeproj",
            description: "Generate the Xcode project from project.yml with the xcodegen CLI; errors honestly when xcodegen is not installed.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "project_scheme_list",
            description: "List the thread project schemes, targets, and configurations from xcodebuild -list -json.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "project_target_list",
            description: "List the thread project targets from xcodebuild -list -json.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "project_build_settings",
            description: "Read the thread project build settings with xcodebuild -showBuildSettings and return them parsed by target. Read only; there is no setter.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme to read settings for."),
                SystemToolParameter(name: "configuration", type: "string", required: false, description: "Build configuration, such as Debug or Release."),
                SystemToolParameter(name: "target", type: "string", required: false, description: "Target to read settings for."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "project_clean",
            description: "Clean the thread project build products with xcodebuild clean. Requires confirm=true.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme to clean."),
                SystemToolParameter(name: "configuration", type: "string", required: false, description: "Build configuration, such as Debug or Release."),
                SystemToolParameter(name: "confirm", type: "boolean", required: true, description: "Must be true. Cleaning removes build products."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "project_archive",
            description: "Archive the thread project with xcodebuild archive into the given archive path.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "scheme", type: "string", required: true, description: "Scheme to archive."),
                SystemToolParameter(name: "archivePath", type: "string", required: true, description: "Archive path relative to the thread working directory."),
                SystemToolParameter(name: "configuration", type: "string", required: false, description: "Build configuration, such as Debug or Release."),
                SystemToolParameter(name: "destination", type: "string", required: false, description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "test_run_single",
            description: "Run one test with xcodebuild test -only-testing and return the real test summary and output.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "testIdentifier", type: "string", required: true, description: "Test identifier for -only-testing, such as Target/Class/testMethod."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme to test."),
                SystemToolParameter(name: "destination", type: "string", required: false, description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "test_coverage_report",
            description: "Report line coverage totals from an xcresult bundle with xcrun xccov view --report --json.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "xcresultPath", type: "string", required: true, description: "Path to the xcresult bundle, relative to the thread working directory."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "test_coverage_reporter",
            description: "Render a full coverage report from an xcresult bundle with xcrun xccov, as JSON or text.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "xcresultPath", type: "string", required: true, description: "Path to the xcresult bundle, relative to the thread working directory."),
                SystemToolParameter(name: "format", type: "string", required: false, description: "json or text. Defaults to text."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "performance_benchmark",
            description: "Run one allow-listed build or test command and report its real wall time, exit code, and output.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "benchmark", type: "string", required: true, description: "Allow-listed benchmark: xcodebuild-build, xcodebuild-test, swift-build, swift-test, or xcodebuild-clean-build."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme for xcodebuild benchmarks."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "docc_build",
            description: "Build the thread project documentation with xcodebuild docbuild and return the real result.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "scheme", type: "string", required: true, description: "Scheme to document."),
                SystemToolParameter(name: "destination", type: "string", required: false, description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "xcode_scheme_manager",
            description: "List the thread project schemes, or validate one scheme by reading its build settings.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "list or validate."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme to validate."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "xcode_build_settings_inspector",
            description: "Read one named build setting across the thread project targets with xcodebuild -showBuildSettings.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "key", type: "string", required: true, description: "Build setting name, such as PRODUCT_BUNDLE_IDENTIFIER."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme to read settings for."),
                SystemToolParameter(name: "configuration", type: "string", required: false, description: "Build configuration, such as Debug or Release."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "xcode_device_destination_finder",
            description: "Find the real run destinations for the thread project scheme with xcodebuild -showdestinations.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme to find destinations for."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "simulator_list",
            description: "List the simulators on the machine from xcrun simctl list -j devices, parsed by runtime.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "simulator_boot",
            description: "Boot a simulator with xcrun simctl boot and return the real result.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "device", type: "string", required: true, description: "Simulator UDID or name."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "simulator_controller",
            description: "Control a simulator with xcrun simctl: boot, shutdown, erase, openurl, or status.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "boot, shutdown, erase, openurl, or status."),
                SystemToolParameter(name: "device", type: "string", required: true, description: "Simulator UDID or name."),
                SystemToolParameter(name: "url", type: "string", required: false, description: "URL to open for openurl."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "device_list",
            description: "List the connected devices with xcrun devicectl, falling back to xcrun xctrace list devices when devicectl is unavailable.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "provisioning_check",
            description: "Check one provisioning profile with security cms -D and return its name, UUID, team, entitlements, and expiry.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "profilePath", type: "string", required: true, description: "Path to the provisioning profile, relative to the thread working directory."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "swift_package_manager",
            description: "Run a Swift Package Manager command on the thread package: describe, resolve, clean, or reset.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "describe, resolve, clean, or reset."),
                SystemToolParameter(name: "confirm", type: "boolean", required: false, description: "Must be true for reset."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "package_dependency_update",
            description: "Update the thread package dependencies with swift package update, optionally for one package.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "package", type: "string", required: false, description: "Package name to update; updates all packages when omitted."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "code_signing_diagnose",
            description: "Diagnose the code signature of a file with codesign --verify and codesign -dv and return the parsed result.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path to the file to diagnose, relative to the thread working directory."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "xcode_toolchain_info",
            description: "Report the Xcode version, build, and developer directory from xcodebuild -version and xcode-select -p.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "xcresult_parser",
            description: "Read an xcresult bundle with xcrun xcresulttool get --format json and return the parsed result.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path to the xcresult bundle, relative to the thread working directory."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "mach_o_binary_analyzer",
            description: "Analyze a Mach-O binary with file, otool -L, and otool -hv and return its type, libraries, and header.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path to the binary, relative to the thread working directory."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "signing_certificate_inspector",
            description: "List the code signing identities on the machine from security find-identity -v -p codesigning.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "provisioning_profile_reader",
            description: "Read one provisioning profile with security cms -D and return its full parsed property list.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "profilePath", type: "string", required: true, description: "Path to the provisioning profile, relative to the thread working directory."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "swift_ast_inspector",
            description: "Dump the Swift AST of one file with swiftc -dump-ast and return declaration counts.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path to the Swift source file, relative to the thread working directory."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "binary_size_report",
            description: "Report the sizes of files under a build directory from a real directory read plus du, largest first.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to report, relative to the thread working directory. Defaults to build."),
                SystemToolParameter(name: "top", type: "integer", required: false, description: "Largest files to return, 1-100. Defaults to 20."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Seconds to wait for the command."),
            ]
        ),
        SystemToolDefinition(
            name: "git_review_diff",
            description: "Read the review diff for the thread working directory: staged, unstaged, and untracked changes against HEAD or the branch base.",
            action: "git.review.diff",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "scope", type: "string", required: false, description: "uncommitted or branch. Defaults to uncommitted."),
                SystemToolParameter(name: "ignoreWhitespace", type: "boolean", required: false, description: "Ignore whitespace changes in the diff."),
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
        case "create_artifact":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let artifactName = try requiredString(arguments, "name", tool: name)
            let content = try requiredString(arguments, "content", tool: name)
            let kind = optionalString(arguments, "kind") ?? "artifact"
            guard kind == "artifact" || kind == "execution_plan" else {
                throw SystemToolError.executionFailed(tool: name, message: "Artifact kind must be artifact or execution_plan.")
            }
            let artifactPath = try Self.artifactRelativePath(name: artifactName, tool: name)
            let append = optionalBool(arguments, "append") ?? false
            if append {
                var existing = (try? await runtime.readWorkspaceFile(cwd: cwd, path: artifactPath))?.content ?? ""
                if !existing.isEmpty, !existing.hasSuffix("\n") {
                    existing += "\n"
                }
                try await runtime.writeWorkspaceFile(cwd: cwd, path: artifactPath, content: existing + content)
            } else {
                try await runtime.writeWorkspaceFile(cwd: cwd, path: artifactPath, content: content)
            }
            return .object(["name": .string(artifactName), "path": .string(artifactPath), "kind": .string(kind), "appended": .bool(append)])
        case "list_artifacts":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let entries = (try? await runtime.readWorkspaceDirectory(cwd: cwd, path: ".assist_temp/artifacts", recursive: false)) ?? []
            let artifacts = entries.filter { $0.name.hasSuffix(".md") }.sorted { ($0.modifiedAt ?? 0) > ($1.modifiedAt ?? 0) }
            return .array(artifacts.map { entry in
                .object([
                    "name": .string(entry.name),
                    "path": .string(entry.path),
                    "sizeBytes": entry.sizeBytes.map { .int($0) } ?? .null,
                    "modifiedAt": entry.modifiedAt.map { .double($0) } ?? .null,
                ])
            })
        case "read_artifact":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let artifactName = try requiredString(arguments, "name", tool: name)
            let artifactPath = try Self.artifactRelativePath(name: artifactName, tool: name)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: artifactPath)
            let truncated = document.content.count > 60000
            let content = truncated ? String(document.content.prefix(60000)) + "\n... (truncated)" : document.content
            return .object(["name": .string(artifactName), "path": .string(artifactPath), "content": .string(content), "truncated": .bool(truncated), "totalCharacters": .int(Int64(document.content.count))])
        case "delete_artifact":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let artifactName = try requiredString(arguments, "name", tool: name)
            try Self.requireConfirm(arguments, tool: name, message: "Deleting an artifact is permanent; pass confirm=true.")
            guard artifactName != "agent_notes.md" else {
                throw SystemToolError.executionFailed(tool: name, message: "agent_notes.md is protected and cannot be deleted.")
            }
            let artifactPath = try Self.artifactRelativePath(name: artifactName, tool: name)
            try await runtime.deleteWorkspaceFile(cwd: cwd, path: artifactPath)
            return .object(["name": .string(artifactName), "path": .string(artifactPath), "deleted": .bool(true)])
        case "format_json_file":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let value = try Self.jsonObject(from: document.content, tool: name)
            let formatted = try Self.prettyJSONText(value)
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: formatted + "\n")
            return .object(["path": .string(path), "valid": .bool(true)])
        case "csv_to_json":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let output = optionalString(arguments, "output") ?? Self.replacingExtension(path, with: "json")
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let rows = Self.parseCSV(document.content)
            guard let headers = rows.first, !headers.isEmpty else {
                throw SystemToolError.executionFailed(tool: tool, message: "CSV file has no header row.")
            }
            var records: [[String: Any]] = []
            for row in rows.dropFirst() {
                if row.allSatisfy({ $0.isEmpty }) {
                    continue
                }
                var record: [String: Any] = [:]
                for (index, header) in headers.enumerated() {
                    record[header] = index < row.count ? row[index] : ""
                }
                records.append(record)
            }
            let json = try Self.prettyJSONText(records)
            try await runtime.writeWorkspaceFile(cwd: cwd, path: output, content: json + "\n")
            return .object(["path": .string(path), "output": .string(output), "rows": .int(Int64(records.count))])
        case "json_to_csv":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let output = optionalString(arguments, "output") ?? Self.replacingExtension(path, with: "csv")
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let value = try Self.jsonObject(from: document.content, tool: name)
            guard let records = value as? [[String: Any]] else {
                throw SystemToolError.executionFailed(tool: tool, message: "JSON file must contain an array of objects.")
            }
            var headers: [String] = []
            for record in records {
                for key in record.keys where !headers.contains(key) {
                    headers.append(key)
                }
            }
            headers.sort()
            var lines: [String] = [headers.map { Self.csvField($0) }.joined(separator: ",")]
            for record in records {
                lines.append(headers.map { Self.csvField(Self.jsonScalarText(record[$0] ?? NSNull())) }.joined(separator: ","))
            }
            try await runtime.writeWorkspaceFile(cwd: cwd, path: output, content: lines.joined(separator: "\n") + "\n")
            return .object(["path": .string(path), "output": .string(output), "rows": .int(Int64(records.count))])
        case "plist_to_json":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let output = optionalString(arguments, "output") ?? Self.replacingExtension(path, with: "json")
            let (object, _) = try Self.readPlist(cwd: cwd, path: path, tool: name)
            let json = try Self.prettyJSONText(Self.plistJSONValue(object))
            try await runtime.writeWorkspaceFile(cwd: cwd, path: output, content: json + "\n")
            return .object(["path": .string(path), "output": .string(output)])
        case "json_to_plist":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let output = optionalString(arguments, "output") ?? Self.replacingExtension(path, with: "plist")
            let formatName = optionalString(arguments, "format") ?? "xml"
            guard formatName == "xml" || formatName == "binary" else {
                throw SystemToolError.executionFailed(tool: tool, message: "Plist format must be xml or binary.")
            }
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let object = try Self.jsonObject(from: document.content, tool: name)
            let format: PropertyListSerialization.PropertyListFormat = formatName == "binary" ? .binary : .xml
            try Self.writePlist(cwd: cwd, path: output, object: object, format: format, tool: name)
            return .object(["path": .string(path), "output": .string(output), "format": .string(formatName)])
        case "json_validate":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let value: Any
            do {
                value = try Self.jsonObject(from: document.content, tool: name)
            } catch let error as SystemToolError {
                return .object(["path": .string(path), "valid": .bool(false), "error": .string(error.localizedDescription), "wrote": .bool(false)])
            }
            let write = optionalBool(arguments, "write") ?? false
            if write {
                let formatted = try Self.prettyJSONText(value)
                try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: formatted + "\n")
            }
            return .object(["path": .string(path), "valid": .bool(true), "wrote": .bool(write)])
        case "json_validator_tool":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            do {
                let value = try Self.jsonObject(from: document.content, tool: name)
                let formatted = try Self.prettyJSONText(value)
                return .object(["path": .string(path), "valid": .bool(true), "formatted": .string(formatted)])
            } catch let error as SystemToolError {
                return .object(["path": .string(path), "valid": .bool(false), "error": .string(error.localizedDescription)])
            }
        case "yaml_validate":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let issues = Self.yamlIssues(document.content)
            let write = optionalBool(arguments, "write") ?? false
            var wrote = false
            if write, issues.isEmpty {
                try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: Self.yamlNormalized(document.content))
                wrote = true
            }
            return .object(["path": .string(path), "valid": .bool(issues.isEmpty), "issues": .array(issues.map { .string($0) }), "wrote": .bool(wrote)])
        case "yaml_parser_tool":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let issues = Self.yamlIssues(document.content)
            guard issues.isEmpty else {
                return .object(["path": .string(path), "valid": .bool(false), "issues": .array(issues.map { .string($0) })])
            }
            do {
                let value = try Self.yamlParse(document.content, tool: name)
                return .object(["path": .string(path), "valid": .bool(true), "value": value])
            } catch let error as SystemToolError {
                return .object(["path": .string(path), "valid": .bool(false), "error": .string(error.localizedDescription)])
            }
        case "plist_edit":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let action = try requiredString(arguments, "action", tool: name)
            let key = try requiredString(arguments, "key", tool: name)
            let (object, sourceFormat) = try Self.readPlist(cwd: cwd, path: path, tool: name)
            switch action {
            case "get":
                let found = Self.plistValue(at: key, in: object)
                return .object(["path": .string(path), "key": .string(key), "found": .bool(found != nil), "value": found.map { Self.plistJSONValue($0) } ?? .null])
            case "set":
                guard var root = object as? [String: Any] else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Property list root must be a dictionary for key edits.")
                }
                guard let value = arguments["value"]?.stringValue else {
                    throw SystemToolError.missingArgument(tool: tool, argument: "value")
                }
                Self.plistSet(value, keyPath: key, root: &root)
                try Self.writePlist(cwd: cwd, path: path, object: root, format: sourceFormat, tool: name)
                return .object(["path": .string(path), "key": .string(key), "value": .string(value)])
            case "delete":
                guard var root = object as? [String: Any] else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Property list root must be a dictionary for key edits.")
                }
                guard Self.plistDelete(keyPath: key, root: &root) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Property list key was not found: \(key).")
                }
                try Self.writePlist(cwd: cwd, path: path, object: root, format: sourceFormat, tool: name)
                return .object(["path": .string(path), "key": .string(key), "deleted": .bool(true)])
            default:
                throw SystemToolError.executionFailed(tool: tool, message: "plist_edit action must be get, set, or delete.")
            }
        case "plist_editor":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let action = optionalString(arguments, "action") ?? "read"
            let (object, sourceFormat) = try Self.readPlist(cwd: cwd, path: path, tool: name)
            switch action {
            case "read":
                return .object(["path": .string(path), "value": Self.plistJSONValue(object)])
            case "get":
                let key = try requiredString(arguments, "key", tool: name)
                let found = Self.plistValue(at: key, in: object)
                return .object(["path": .string(path), "key": .string(key), "found": .bool(found != nil), "value": found.map { Self.plistJSONValue($0) } ?? .null])
            case "set":
                let key = try requiredString(arguments, "key", tool: name)
                guard var root = object as? [String: Any] else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Property list root must be a dictionary for key edits.")
                }
                guard let value = arguments["value"]?.stringValue else {
                    throw SystemToolError.missingArgument(tool: tool, argument: "value")
                }
                Self.plistSet(value, keyPath: key, root: &root)
                try Self.writePlist(cwd: cwd, path: path, object: root, format: sourceFormat, tool: name)
                return .object(["path": .string(path), "key": .string(key), "value": .string(value)])
            case "delete":
                let key = try requiredString(arguments, "key", tool: name)
                guard var root = object as? [String: Any] else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Property list root must be a dictionary for key edits.")
                }
                guard Self.plistDelete(keyPath: key, root: &root) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Property list key was not found: \(key).")
                }
                try Self.writePlist(cwd: cwd, path: path, object: root, format: sourceFormat, tool: name)
                return .object(["path": .string(path), "key": .string(key), "deleted": .bool(true)])
            default:
                throw SystemToolError.executionFailed(tool: tool, message: "plist_editor action must be read, get, set, or delete.")
            }
        case "binary_plist_converter":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let formatName = try requiredString(arguments, "format", tool: name)
            guard formatName == "xml" || formatName == "binary" else {
                throw SystemToolError.executionFailed(tool: tool, message: "Plist format must be xml or binary.")
            }
            let output = optionalString(arguments, "output") ?? path
            let (object, _) = try Self.readPlist(cwd: cwd, path: path, tool: name)
            let format: PropertyListSerialization.PropertyListFormat = formatName == "binary" ? .binary : .xml
            try Self.writePlist(cwd: cwd, path: output, object: object, format: format, tool: name)
            let (_, verifiedFormat) = try Self.readPlist(cwd: cwd, path: output, tool: name)
            guard verifiedFormat == format else {
                throw SystemToolError.executionFailed(tool: tool, message: "Property list conversion verification failed: the output is not \(formatName).")
            }
            return .object(["path": .string(path), "output": .string(output), "format": .string(formatName), "converted": .bool(true)])
        case "file_metadata":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let parent = (path as NSString).deletingLastPathComponent
            let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: parent, recursive: false)
            let fileName = (path as NSString).lastPathComponent
            guard let entry = entries.first(where: { $0.name == fileName }) else {
                throw SystemToolError.executionFailed(tool: tool, message: "No such file or directory: \(path).")
            }
            return .object([
                "path": .string(path),
                "name": .string(entry.name),
                "isDirectory": .bool(entry.isDirectory),
                "sizeBytes": entry.sizeBytes.map { .int($0) } ?? .null,
                "modifiedAt": entry.modifiedAt.map { .double($0) } ?? .null,
                "isSymlink": entry.isSymlink.map { .bool($0) } ?? .null,
                "symlinkTarget": entry.symlinkTarget.map { .string($0) } ?? .null,
                "isExecutable": entry.isExecutable.map { .bool($0) } ?? .null,
            ])
        case "file_hash_verify":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let expectedHash = try requiredString(arguments, "expectedHash", tool: name)
            let algorithm = optionalString(arguments, "algorithm") ?? "sha256"
            let data = try Self.readWorkspaceBytes(cwd: cwd, path: path, tool: name)
            let hash = try Self.checksumHex(data: data, algorithm: algorithm, tool: name)
            return .object(["path": .string(path), "algorithm": .string(algorithm), "hash": .string(hash), "expectedHash": .string(expectedHash.lowercased()), "match": .bool(hash == expectedHash.lowercased())])
        case "generate_file_checksum":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let data = try Self.readWorkspaceBytes(cwd: cwd, path: path, tool: name)
            return .object([
                "path": .string(path),
                "sha256": .string(try Self.checksumHex(data: data, algorithm: "sha256", tool: name)),
                "sha512": .string(try Self.checksumHex(data: data, algorithm: "sha512", tool: name)),
                "sha1": .string(try Self.checksumHex(data: data, algorithm: "sha1", tool: name)),
                "md5": .string(try Self.checksumHex(data: data, algorithm: "md5", tool: name)),
            ])
        case "file_checksum_verifier":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let algorithm = optionalString(arguments, "algorithm") ?? "sha256"
            guard algorithm == "sha256" || algorithm == "md5" else {
                throw SystemToolError.executionFailed(tool: tool, message: "file_checksum_verifier algorithm must be sha256 or md5.")
            }
            let data = try Self.readWorkspaceBytes(cwd: cwd, path: path, tool: name)
            let sha256 = try Self.checksumHex(data: data, algorithm: "sha256", tool: name)
            let md5 = try Self.checksumHex(data: data, algorithm: "md5", tool: name)
            let verified: JSONValue
            if let expectedHash = optionalString(arguments, "expectedHash") {
                let actual = algorithm == "md5" ? md5 : sha256
                verified = .bool(actual == expectedHash.lowercased())
            } else {
                verified = .null
            }
            return .object(["path": .string(path), "sha256": .string(sha256), "md5": .string(md5), "algorithm": .string(algorithm), "verified": verified])
        case "file_compare_diff":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let otherPath = try requiredString(arguments, "otherPath", tool: name)
            let first = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let second = try await runtime.readWorkspaceFile(cwd: cwd, path: otherPath)
            let result = Self.unifiedDiff(oldText: first.content, newText: second.content, oldPath: path, newPath: otherPath)
            return .object(["path": .string(path), "otherPath": .string(otherPath), "identical": .bool(first.content == second.content), "added": .int(Int64(result.added)), "removed": .int(Int64(result.removed)), "diff": .string(result.diff)])
        case "file_head_preview":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let lines = min(max(optionalInt(arguments, "lines") ?? 20, 1), 5000)
            let value = try await runtime.desktopCall(action: "workspace.read_file", params: ["cwd": .string(ExternalEditorService.expandedPath(cwd)), "path": .string(path), "lineOffset": .int(0), "lineLimit": .int(Int64(lines))], as: JSONValue.self)
            return .object([
                "path": .string(path),
                "content": value["content"]?.stringValue.map { .string($0) } ?? .null,
                "lineOffset": .int(0),
                "totalLines": value["totalLines"]?.intValue.map { .int(Int64($0)) } ?? .null,
                "truncated": value["truncated"]?.boolValue.map { .bool($0) } ?? .null,
            ])
        case "code_generate":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let template = try requiredString(arguments, "template", tool: name)
            let module = optionalString(arguments, "module") ?? URL(fileURLWithPath: ExternalEditorService.expandedPath(cwd)).lastPathComponent
            try Self.assertFileAbsent(cwd: cwd, path: path, tool: name)
            let fileName = (path as NSString).lastPathComponent
            let content = try Self.codeTemplate(template, module: module, fileName: fileName, tool: name)
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: content)
            return .object(["path": .string(path), "template": .string(template)])
        case "code_format":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? ""
            let extensions: Set<String> = ["swift", "c", "h", "m", "mm", "js", "ts", "tsx", "jsx", "py"]
            var formatted: [String] = []
            var skipped = 0
            var targets: [String] = []
            if path.isEmpty {
                let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: "", recursive: true)
                targets = entries.filter { !$0.isDirectory && extensions.contains((($0.path as NSString).pathExtension).lowercased()) }.map { $0.path }
            } else if let entries = try? await runtime.readWorkspaceDirectory(cwd: cwd, path: path, recursive: true) {
                targets = entries.filter { !$0.isDirectory && extensions.contains((($0.path as NSString).pathExtension).lowercased()) }.map { $0.path }
            } else {
                targets = [path]
            }
            for target in targets {
                guard let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: target) else {
                    skipped += 1
                    continue
                }
                let normalized = Self.normalizedText(document.content)
                if normalized != document.content {
                    try await runtime.writeWorkspaceFile(cwd: cwd, path: target, content: normalized)
                    formatted.append(target)
                }
            }
            return .object(["path": .string(path), "formattedFiles": .array(formatted.map { .string($0) }), "formatted": .int(Int64(formatted.count)), "skipped": .int(Int64(skipped))])
        case "swift_format_lint":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let mode = optionalString(arguments, "mode") ?? "lint"
            guard mode == "lint" || mode == "format" else {
                throw SystemToolError.executionFailed(tool: tool, message: "swift_format_lint mode must be lint or format.")
            }
            try Self.validateRelativePath(path, tool: name)
            let command = mode == "lint" ? "swiftformat --lint " + Self.shellQuoted(path) : "swiftformat " + Self.shellQuoted(path)
            let fullCommand = "cd " + Self.shellQuoted(ExternalEditorService.expandedPath(cwd)) + " && " + command
            let result = try await runTerminalCommand(tool: tool, threadId: threadId, command: fullCommand, timeoutSeconds: 300, runtime: runtime)
            if result["timedOut"]?.boolValue == true {
                throw SystemToolError.operationTimeout(tool: tool)
            }
            let exitCode = result["exitCode"]?.intValue ?? -1
            let cleaned = Self.cleanTerminalOutput(result["output"]?.stringValue ?? "")
            if exitCode == 127 || cleaned.contains("command not found") {
                throw SystemToolError.executionFailed(tool: tool, message: "swiftformat is not installed; install it to use swift_format_lint.")
            }
            if mode == "lint" {
                return .object(["path": .string(path), "mode": .string(mode), "lintPassed": .bool(exitCode == 0), "exitCode": .int(Int64(exitCode)), "output": .string(cleaned)])
            }
            guard exitCode == 0 else {
                throw SystemToolError.executionFailed(tool: tool, message: "swiftformat failed with exit code \(exitCode): \(cleaned)")
            }
            return .object(["path": .string(path), "mode": .string(mode), "formatted": .bool(true), "exitCode": .int(Int64(exitCode)), "output": .string(cleaned)])
        case "code_mutation_engine":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            guard let replacement = arguments["replacement"]?.stringValue else {
                throw SystemToolError.missingArgument(tool: name, argument: "replacement")
            }
            let symbol = optionalString(arguments, "symbol")
            let target = optionalString(arguments, "target")
            guard symbol != nil || target != nil else {
                throw SystemToolError.executionFailed(tool: tool, message: "code_mutation_engine requires symbol or target.")
            }
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            if let target {
                guard document.content.contains(target) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Target block was not found in the file.")
                }
                let updated = document.content.replacingOccurrences(of: target, with: replacement)
                try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: updated)
                return .object(["path": .string(path), "mutated": .bool(true)])
            }
            let lines = document.content.components(separatedBy: "\n")
            guard let start = Self.symbolDeclarationLine(lines, symbol: symbol!) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Symbol was not found in the file: \(symbol!).")
            }
            guard let end = Self.braceBlockEnd(lines, from: start) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Symbol has no brace-balanced body: \(symbol!).")
            }
            var updatedLines = lines
            let replacementLines = replacement.components(separatedBy: "\n")
            var openLine = start
            while openLine <= end, !updatedLines[openLine].contains("{") {
                openLine += 1
            }
            guard openLine <= end else {
                throw SystemToolError.executionFailed(tool: tool, message: "Symbol has no brace-balanced body: \(symbol!).")
            }
            if openLine == end {
                updatedLines.replaceSubrange(openLine...openLine, with: replacementLines)
            } else {
                updatedLines.replaceSubrange((openLine + 1)..<end, with: replacementLines)
            }
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: updatedLines.joined(separator: "\n"))
            return .object(["path": .string(path), "symbol": .string(symbol!), "mutated": .bool(true)])
        case "patch_application_engine":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let original = try requiredString(arguments, "original", tool: name)
            guard let updated = arguments["updated"]?.stringValue else {
                throw SystemToolError.missingArgument(tool: name, argument: "updated")
            }
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let occurrences = document.content.components(separatedBy: original).count - 1
            guard occurrences > 0 else {
                throw SystemToolError.executionFailed(tool: tool, message: "Original block was not found in the file.")
            }
            let patched = document.content.replacingOccurrences(of: original, with: updated)
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: patched)
            return .object(["path": .string(path), "patched": .bool(true), "occurrences": .int(Int64(occurrences))])
        case "automated_repair_engine":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            guard let rawErrors = arguments["errors"]?.arrayValue, !rawErrors.isEmpty else {
                throw SystemToolError.missingArgument(tool: name, argument: "errors")
            }
            let lineNumbers = rawErrors.compactMap(\.intValue)
            guard lineNumbers.count == rawErrors.count else {
                throw SystemToolError.executionFailed(tool: tool, message: "automated_repair_engine errors must be line numbers.")
            }
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            var lines = document.content.components(separatedBy: "\n")
            let sorted = lineNumbers.sorted(by: >)
            for lineNumber in sorted {
                guard lineNumber >= 1, lineNumber <= lines.count else {
                    throw SystemToolError.executionFailed(tool: tool, message: "automated_repair_engine line \(lineNumber) is out of range for the file.")
                }
                lines.insert("// AssistAutoRepair: review required", at: lineNumber - 1)
            }
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: lines.joined(separator: "\n"))
            return .object(["path": .string(path), "annotated": .int(Int64(lineNumbers.count)), "lines": .array(lineNumbers.map { .int(Int64($0)) })])
        case "regex_replace_in_files":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let pattern = try requiredString(arguments, "pattern", tool: name)
            guard let replacement = arguments["replacement"]?.stringValue else {
                throw SystemToolError.missingArgument(tool: name, argument: "replacement")
            }
            let query = optionalString(arguments, "query")
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: pattern)
            } catch {
                throw SystemToolError.executionFailed(tool: tool, message: "Invalid regular expression: \(error.localizedDescription)")
            }
            let hits = try await runtime.searchWorkspaceRegex(cwd: cwd, pattern: pattern, limit: 500)
            var files: [String] = []
            for hit in hits where !files.contains(hit.path) {
                if let query, !hit.path.contains(query) {
                    continue
                }
                files.append(hit.path)
            }
            var changed: [String] = []
            var total = 0
            for file in files {
                let document = try await runtime.readWorkspaceFile(cwd: cwd, path: file)
                let range = NSRange(document.content.startIndex..., in: document.content)
                let count = regex.numberOfMatches(in: document.content, range: range)
                guard count > 0 else {
                    continue
                }
                let updated = regex.stringByReplacingMatches(in: document.content, range: range, withTemplate: replacement)
                try await runtime.writeWorkspaceFile(cwd: cwd, path: file, content: updated)
                changed.append(file)
                total += count
            }
            return .object(["filesChanged": .array(changed.map { .string($0) }), "changed": .int(Int64(changed.count)), "replacements": .int(Int64(total))])
        case "symbol_rename_project":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let oldName = try requiredString(arguments, "oldName", tool: name)
            let newName = try requiredString(arguments, "newName", tool: name)
            let directory = optionalString(arguments, "path") ?? ""
            let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: directory, recursive: true)
            var changed: [String] = []
            var total = 0
            for entry in entries where !entry.isDirectory && (entry.path as NSString).pathExtension == "swift" {
                guard let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: entry.path) else {
                    continue
                }
                let (updated, count) = Self.wholeWordReplace(document.content, old: oldName, new: newName)
                guard count > 0 else {
                    continue
                }
                try await runtime.writeWorkspaceFile(cwd: cwd, path: entry.path, content: updated)
                changed.append(entry.path)
                total += count
            }
            return .object(["oldName": .string(oldName), "newName": .string(newName), "filesChanged": .array(changed.map { .string($0) }), "changed": .int(Int64(changed.count)), "replacements": .int(Int64(total))])
        case "symbol_move_file":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let sourcePath = try requiredString(arguments, "sourcePath", tool: name)
            let destinationPath = try requiredString(arguments, "destinationPath", tool: name)
            let symbol = try requiredString(arguments, "symbol", tool: name)
            let source = try await runtime.readWorkspaceFile(cwd: cwd, path: sourcePath)
            let destination = try await runtime.readWorkspaceFile(cwd: cwd, path: destinationPath)
            let sourceLines = source.content.components(separatedBy: "\n")
            guard let start = Self.symbolDeclarationLine(sourceLines, symbol: symbol) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Symbol was not found in the source file: \(symbol).")
            }
            guard let end = Self.braceBlockEnd(sourceLines, from: start) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Symbol has no brace-balanced body: \(symbol).")
            }
            let block = Array(sourceLines[start...end])
            var remaining = sourceLines
            remaining.removeSubrange(start...end)
            var destinationContent = destination.content
            if !destinationContent.isEmpty, !destinationContent.hasSuffix("\n") {
                destinationContent += "\n"
            }
            destinationContent += block.joined(separator: "\n") + "\n"
            try await runtime.writeWorkspaceFile(cwd: cwd, path: sourcePath, content: remaining.joined(separator: "\n"))
            do {
                try await runtime.writeWorkspaceFile(cwd: cwd, path: destinationPath, content: destinationContent)
            } catch {
                try? await runtime.writeWorkspaceFile(cwd: cwd, path: sourcePath, content: source.content)
                throw error
            }
            let verifiedSource = try await runtime.readWorkspaceFile(cwd: cwd, path: sourcePath)
            let verifiedDestination = try await runtime.readWorkspaceFile(cwd: cwd, path: destinationPath)
            guard Self.symbolDeclarationLine(verifiedSource.content.components(separatedBy: "\n"), symbol: symbol) == nil,
                  Self.symbolDeclarationLine(verifiedDestination.content.components(separatedBy: "\n"), symbol: symbol) != nil else {
                throw SystemToolError.executionFailed(tool: tool, message: "Symbol move verification failed.")
            }
            return .object(["sourcePath": .string(sourcePath), "destinationPath": .string(destinationPath), "symbol": .string(symbol), "moved": .bool(true), "lines": .int(Int64(block.count))])
        case "import_cleanup":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let protected: Set<String> = ["Foundation", "SwiftUI", "AppKit", "UIKit", "Combine", "CoreData", "CryptoKit", "Security", "XCTest", "SwiftData", "Observation", "WebKit", "UniformTypeIdentifiers", "Dispatch", "Network", "os", "SystemConfiguration", "CoreGraphics", "QuartzCore", "StoreKit", "AuthenticationServices"]
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let lines = document.content.components(separatedBy: "\n")
            let importPattern = "^\\s*import\\s+([A-Za-z_][A-Za-z0-9_]*)"
            guard let regex = try? NSRegularExpression(pattern: importPattern, options: [.anchorsMatchLines]) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Import scan failed.")
            }
            var removed: [String] = []
            for (lineIndex, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      let moduleRange = Range(match.range(at: 1), in: line) else {
                    continue
                }
                let module = String(line[moduleRange])
                if protected.contains(module) {
                    continue
                }
                var body = ""
                for (otherIndex, other) in lines.enumerated() where otherIndex != lineIndex {
                    body += other + "\n"
                }
                let wordPattern = "\\b" + NSRegularExpression.escapedPattern(for: module) + "\\b"
                let wordRegex = try? NSRegularExpression(pattern: wordPattern)
                let wordRange = NSRange(body.startIndex..., in: body)
                if wordRegex?.firstMatch(in: body, range: wordRange) == nil {
                    removed.append(module)
                }
            }
            guard !removed.isEmpty else {
                return .object(["path": .string(path), "removed": .array([]), "count": .int(0)])
            }
            let updated = lines.filter { line in
                let range = NSRange(line.startIndex..., in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      let moduleRange = Range(match.range(at: 1), in: line) else {
                    return true
                }
                return !removed.contains(String(line[moduleRange]))
            }
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: updated.joined(separator: "\n"))
            return .object(["path": .string(path), "removed": .array(removed.map { .string($0) }), "count": .int(Int64(removed.count))])
        case "batch_rename_files":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let directory = optionalString(arguments, "directory") ?? ""
            let pattern = try requiredString(arguments, "pattern", tool: name)
            guard let replacement = arguments["replacement"]?.stringValue else {
                throw SystemToolError.missingArgument(tool: name, argument: "replacement")
            }
            let dryRun = optionalBool(arguments, "dryRun") ?? false
            let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: directory, recursive: false)
            var planned: [(from: String, to: String)] = []
            for entry in entries where !entry.isDirectory && entry.name.contains(pattern) {
                let newName = entry.name.replacingOccurrences(of: pattern, with: replacement)
                guard newName != entry.name, !newName.isEmpty, !newName.contains("/") else {
                    continue
                }
                let from = directory.isEmpty ? entry.name : directory + "/" + entry.name
                let to = directory.isEmpty ? newName : directory + "/" + newName
                planned.append((from, to))
            }
            if dryRun {
                return .object(["dryRun": .bool(true), "renames": .array(planned.map { .object(["from": .string($0.from), "to": .string($0.to)]) }), "count": .int(Int64(planned.count))])
            }
            var renamed: [(from: String, to: String)] = []
            for plan in planned {
                try await runtime.moveWorkspaceFile(cwd: cwd, path: plan.from, destination: plan.to)
                renamed.append(plan)
            }
            return .object(["dryRun": .bool(false), "renames": .array(renamed.map { .object(["from": .string($0.from), "to": .string($0.to)]) }), "count": .int(Int64(renamed.count))])
        case "file_backup":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let data = try Self.readWorkspaceBytes(cwd: cwd, path: path, tool: name)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let stamp = formatter.string(from: Date())
            let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let backupPath = ".assist_temp/backups/" + base + "." + stamp + ".bak"
            try Self.writeWorkspaceBytes(cwd: cwd, path: backupPath, data: data, tool: name)
            let verified = try Self.readWorkspaceBytes(cwd: cwd, path: backupPath, tool: name)
            guard verified.count == data.count else {
                throw SystemToolError.executionFailed(tool: tool, message: "Backup verification failed: size mismatch.")
            }
            return .object(["path": .string(path), "backupPath": .string(backupPath), "byteLen": .int(Int64(data.count))])
        case "session_export":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let title = try requiredString(arguments, "title", tool: name)
            let sessionId = optionalString(arguments, "sessionId") ?? UUID().uuidString
            let notes = optionalString(arguments, "notes") ?? ""
            let path = optionalString(arguments, "path") ?? ".assist_temp/session-export-\(sessionId).md"
            let overwrite = optionalBool(arguments, "overwrite") ?? false
            if !overwrite {
                try Self.assertFileAbsent(cwd: cwd, path: path, tool: name)
            }
            let formatter = ISO8601DateFormatter()
            let stamp = formatter.string(from: Date())
            var lines = ["# \(title)", "", "- Session: \(sessionId)", "- Exported: \(stamp)", "- Workspace: \(cwd)", ""]
            if !notes.isEmpty {
                lines.append("## Notes")
                lines.append("")
                lines.append(notes)
                lines.append("")
            }
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: lines.joined(separator: "\n"))
            return .object(["path": .string(path), "sessionId": .string(sessionId)])
        case "markdown_toc_generate":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            let headingPattern = "^(#{1,6})\\s+(.+)$"
            guard let regex = try? NSRegularExpression(pattern: headingPattern, options: [.anchorsMatchLines]) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Heading scan failed.")
            }
            var toc: [String] = []
            let lines = document.content.components(separatedBy: "\n")
            for line in lines {
                let range = NSRange(line.startIndex..., in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      match.numberOfRanges == 3,
                      let hashesRange = Range(match.range(at: 1), in: line),
                      let textRange = Range(match.range(at: 2), in: line) else {
                    continue
                }
                let level = line[hashesRange].count
                let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
                let indent = String(repeating: "  ", count: max(0, level - 1))
                toc.append("\(indent)- [\(text)](#\(Self.tocSlug(text)))")
            }
            guard !toc.isEmpty else {
                throw SystemToolError.executionFailed(tool: tool, message: "No headings found in the file.")
            }
            var updated = lines
            if let open = lines.firstIndex(of: "<!-- TOC -->"), let close = lines.firstIndex(of: "<!-- /TOC -->"), close > open {
                updated.replaceSubrange((open + 1)..<close, with: toc)
            } else if let firstHeading = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
                updated.insert(contentsOf: ["", "<!-- TOC -->"] + toc + ["<!-- /TOC -->"], at: firstHeading + 1)
            } else {
                updated.insert(contentsOf: ["<!-- TOC -->"] + toc + ["<!-- /TOC -->", ""], at: 0)
            }
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: updated.joined(separator: "\n"))
            return .object(["path": .string(path), "entries": .int(Int64(toc.count))])
        case "readme_generate":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? "README.md"
            let overwrite = optionalBool(arguments, "overwrite") ?? false
            if !overwrite {
                try Self.assertFileAbsent(cwd: cwd, path: path, tool: name)
            }
            let project = URL(fileURLWithPath: ExternalEditorService.expandedPath(cwd)).lastPathComponent
            let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: "", recursive: false)
            var lines = ["# \(project)", "", "Generated README skeleton from the repository contents.", "", "## Contents", ""]
            for entry in entries.sorted(by: { $0.path < $1.path }) {
                lines.append("- \(entry.isDirectory ? entry.name + "/" : entry.name)")
            }
            lines.append("")
            lines.append("## Getting Started")
            lines.append("")
            lines.append("Open this project and follow the project build instructions.")
            lines.append("")
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: lines.joined(separator: "\n"))
            return .object(["path": .string(path), "entries": .int(Int64(entries.count))])
        case "docs_generate":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let source = optionalString(arguments, "path") ?? ""
            let output = optionalString(arguments, "output") ?? "API.md"
            let overwrite = optionalBool(arguments, "overwrite") ?? false
            if !overwrite {
                try Self.assertFileAbsent(cwd: cwd, path: output, tool: name)
            }
            var sources: [String] = []
            if source.isEmpty {
                let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: "", recursive: true)
                sources = entries.filter { !$0.isDirectory && ($0.path as NSString).pathExtension == "swift" }.map { $0.path }
            } else if let entries = try? await runtime.readWorkspaceDirectory(cwd: cwd, path: source, recursive: true) {
                sources = entries.filter { !$0.isDirectory && ($0.path as NSString).pathExtension == "swift" }.map { $0.path }
            } else {
                sources = [source]
            }
            var lines = ["# API Documentation", ""]
            var total = 0
            for file in sources.sorted() {
                guard let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: file) else {
                    continue
                }
                let symbols = Self.extractSymbols(document.content, path: file)
                total += symbols.count
                lines.append("## \(file)")
                lines.append("")
                if symbols.isEmpty {
                    lines.append("No public declarations found.")
                } else {
                    for symbol in symbols {
                        let kind = symbol["kind"]?.stringValue ?? ""
                        let symbolName = symbol["name"]?.stringValue ?? ""
                        let lineNumber = symbol["line"]?.intValue ?? 0
                        lines.append("- `\(kind) \(symbolName)` (line \(lineNumber))")
                    }
                }
                lines.append("")
            }
            try await runtime.writeWorkspaceFile(cwd: cwd, path: output, content: lines.joined(separator: "\n"))
            return .object(["output": .string(output), "files": .int(Int64(sources.count)), "symbols": .int(Int64(total))])
        case "test_data_factory":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let format = try requiredString(arguments, "format", tool: name)
            let fieldsText = try requiredString(arguments, "fields", tool: name)
            let overwrite = optionalBool(arguments, "overwrite") ?? false
            guard format == "json" || format == "swift" else {
                throw SystemToolError.executionFailed(tool: tool, message: "test_data_factory format must be json or swift.")
            }
            if !overwrite {
                try Self.assertFileAbsent(cwd: cwd, path: path, tool: name)
            }
            var fields: [(name: String, type: String)] = []
            for part in fieldsText.split(separator: ",") {
                let pieces = part.split(separator: ":", maxSplits: 1)
                guard pieces.count == 2 else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Fields must be name:Type pairs separated by commas.")
                }
                fields.append((String(pieces[0]).trimmingCharacters(in: .whitespaces), String(pieces[1]).trimmingCharacters(in: .whitespaces)))
            }
            guard !fields.isEmpty else {
                throw SystemToolError.executionFailed(tool: tool, message: "Fields must not be empty.")
            }
            let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if format == "swift" {
                let first = base.unicodeScalars.first
                let validStart = first.map { CharacterSet.letters.contains($0) || $0 == "_" } ?? false
                let validRest = base.unicodeScalars.dropFirst().allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
                guard validStart, validRest else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Fixture file name must be a valid Swift identifier for the swift format.")
                }
            }
            if format == "json" {
                var record: [String: Any] = [:]
                for field in fields {
                    switch field.type {
                    case "Int":
                        record[field.name] = 1
                    case "Double", "Float":
                        record[field.name] = 1.5
                    case "Bool":
                        record[field.name] = true
                    default:
                        record[field.name] = "Example"
                    }
                }
                let json = try Self.prettyJSONText(record)
                try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: json + "\n")
            } else {
                let structName = base
                var lines = ["import Foundation", "", "public struct \(structName) {"]
                for field in fields {
                    lines.append("    public var \(field.name): \(field.type)")
                }
                lines.append("")
                var initParams: [String] = []
                var initBody: [String] = []
                for field in fields {
                    let sample: String
                    switch field.type {
                    case "Int":
                        sample = "1"
                    case "Double", "Float":
                        sample = "1.5"
                    case "Bool":
                        sample = "true"
                    default:
                        sample = "\"Example\""
                    }
                    initParams.append("\(field.name): \(field.type) = \(sample)")
                    initBody.append("        self.\(field.name) = \(field.name)")
                }
                lines.append("    public init(\(initParams.joined(separator: ", "))) {")
                lines.append(contentsOf: initBody)
                lines.append("    }")
                lines.append("")
                lines.append("    public static let sample = \(structName)()")
                lines.append("}")
                lines.append("")
                try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: lines.joined(separator: "\n"))
            }
            return .object(["path": .string(path), "format": .string(format), "fields": .int(Int64(fields.count))])
        case "ui_test_scaffold":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let appName = optionalString(arguments, "appName") ?? URL(fileURLWithPath: ExternalEditorService.expandedPath(cwd)).lastPathComponent
            let overwrite = optionalBool(arguments, "overwrite") ?? false
            if !overwrite {
                try Self.assertFileAbsent(cwd: cwd, path: path, tool: name)
            }
            let className = appName.filter { $0.isLetter || $0.isNumber }
            let content = "import XCTest\n\nfinal class \(className)UITests: XCTestCase {\n    func testAppLaunches() {\n        let app = XCUIApplication()\n        app.launch()\n        XCTAssertTrue(app.state == .runningForeground)\n    }\n}\n"
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: content)
            return .object(["path": .string(path), "appName": .string(appName)])
        case "test_snapshot_manage":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let action = optionalString(arguments, "action") ?? "list"
            let directory = optionalString(arguments, "path") ?? "__Snapshots__"
            switch action {
            case "list":
                let entries = (try? await runtime.readWorkspaceDirectory(cwd: cwd, path: directory, recursive: true)) ?? []
                return .object(["action": .string(action), "refs": .array(entries.filter { !$0.isDirectory }.map { .string($0.path) }), "count": .int(Int64(entries.filter { !$0.isDirectory }.count))])
            case "clean":
                try Self.requireConfirm(arguments, tool: name, message: "Cleaning snapshots deletes files; pass confirm=true.")
                let entries = (try? await runtime.readWorkspaceDirectory(cwd: cwd, path: directory, recursive: true)) ?? []
                var deleted: [String] = []
                var kept = 0
                for entry in entries where !entry.isDirectory {
                    let base = (entry.name as NSString).deletingPathExtension
                    let hits = (try? await runtime.searchWorkspace(cwd: cwd, query: base, limit: 5)) ?? []
                    let referenced = hits.contains { ($0.path as NSString).pathExtension == "swift" }
                    if referenced {
                        kept += 1
                    } else {
                        try await runtime.deleteWorkspaceFile(cwd: cwd, path: entry.path)
                        deleted.append(entry.path)
                    }
                }
                return .object(["action": .string(action), "deleted": .array(deleted.map { .string($0) }), "count": .int(Int64(deleted.count)), "kept": .int(Int64(kept))])
            default:
                throw SystemToolError.executionFailed(tool: tool, message: "test_snapshot_manage action must be list or clean.")
            }
        case "open_in_finder":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let url = try Self.resolveWorkspaceFileURL(cwd: cwd, path: path, tool: name)
            let opened = await MainActor.run { NSWorkspace.shared.open(url) }
            guard opened else {
                throw SystemToolError.executionFailed(tool: tool, message: "Finder could not open \(path).")
            }
            return .object(["path": .string(path), "opened": .bool(true)])
        case "reveal_in_finder":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let url = try Self.resolveWorkspaceFileURL(cwd: cwd, path: path, tool: name)
            await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            return .object(["path": .string(path), "revealed": .bool(true)])
        case "image_encode_base64":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let dataURI = optionalBool(arguments, "dataURI") ?? false
            let data = try Self.readWorkspaceBytes(cwd: cwd, path: path, tool: name)
            let encoded = data.base64EncodedString()
            if dataURI {
                let ext = ((path as NSString).pathExtension).lowercased()
                let mime: String
                switch ext {
                case "png":
                    mime = "image/png"
                case "jpg", "jpeg":
                    mime = "image/jpeg"
                case "gif":
                    mime = "image/gif"
                case "tiff", "tif":
                    mime = "image/tiff"
                default:
                    mime = "application/octet-stream"
                }
                return .object(["path": .string(path), "base64": .string("data:\(mime);base64,\(encoded)"), "byteLen": .int(Int64(data.count))])
            }
            return .object(["path": .string(path), "base64": .string(encoded), "byteLen": .int(Int64(data.count))])
        case "image_decode_base64":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let encoded = try requiredString(arguments, "base64", tool: name)
            let cleaned = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: String
            if let comma = cleaned.firstIndex(of: ",") {
                payload = String(cleaned[cleaned.index(after: comma)...])
            } else {
                payload = cleaned
            }
            guard let data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]), !data.isEmpty else {
                throw SystemToolError.executionFailed(tool: tool, message: "Base64 string could not be decoded.")
            }
            try Self.writeWorkspaceBytes(cwd: cwd, path: path, data: data, tool: name)
            return .object(["path": .string(path), "byteLen": .int(Int64(data.count))])
        case "image_get_dimensions":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            try Self.validateRelativePath(path, tool: name)
            let output = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: "sips -g pixelWidth -g pixelHeight -g format " + Self.shellQuoted(path), timeoutSeconds: 60, runtime: runtime)
            var width: Int?
            var height: Int?
            var format: String?
            for line in output.components(separatedBy: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else {
                    continue
                }
                if parts[0] == "pixelWidth" {
                    width = Int(parts[1])
                } else if parts[0] == "pixelHeight" {
                    height = Int(parts[1])
                } else if parts[0] == "format" {
                    format = parts[1]
                }
            }
            return .object([
                "path": .string(path),
                "width": width.map { .int(Int64($0)) } ?? .null,
                "height": height.map { .int(Int64($0)) } ?? .null,
                "format": format.map { .string($0) } ?? .null,
                "output": .string(output),
            ])
        case "image_convert_format":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let format = try requiredString(arguments, "format", tool: name)
            let normalized = format.lowercased() == "jpg" ? "jpeg" : format.lowercased()
            guard ["png", "jpeg", "tiff", "bmp", "gif"].contains(normalized) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Image format must be png, jpg, tiff, bmp, or gif.")
            }
            let output = optionalString(arguments, "output") ?? Self.replacingExtension(path, with: format.lowercased())
            try Self.validateRelativePath(path, tool: name)
            try Self.validateRelativePath(output, tool: name)
            var command = "sips -s format \(normalized) "
            if normalized == "jpeg", let quality = optionalInt(arguments, "quality") {
                guard quality >= 0, quality <= 100 else {
                    throw SystemToolError.executionFailed(tool: tool, message: "JPEG quality must be 0 to 100.")
                }
                command += "-s formatOptions \(quality) "
            }
            command += Self.shellQuoted(path) + " --out " + Self.shellQuoted(output)
            let result = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: command, timeoutSeconds: 120, runtime: runtime)
            return .object(["path": .string(path), "output": .string(output), "format": .string(normalized), "result": .string(result)])
        case "image_generate_thumbnail":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let maxPixels = optionalInt(arguments, "maxPixels") ?? 256
            guard maxPixels >= 1, maxPixels <= 4096 else {
                throw SystemToolError.executionFailed(tool: tool, message: "Thumbnail maxPixels must be 1 to 4096.")
            }
            let output: String
            if let given = optionalString(arguments, "output") {
                output = given
            } else {
                let stem = (path as NSString).deletingPathExtension
                let ext = (path as NSString).pathExtension
                output = ext.isEmpty ? stem + "-thumb" : stem + "-thumb." + ext
            }
            try Self.validateRelativePath(path, tool: name)
            try Self.validateRelativePath(output, tool: name)
            let result = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: "sips -Z \(maxPixels) " + Self.shellQuoted(path) + " --out " + Self.shellQuoted(output), timeoutSeconds: 120, runtime: runtime)
            return .object(["path": .string(path), "output": .string(output), "maxPixels": .int(Int64(maxPixels)), "result": .string(result)])
        case "image_extract_metadata":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            try Self.validateRelativePath(path, tool: name)
            let output = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: "mdls " + Self.shellQuoted(path), timeoutSeconds: 60, runtime: runtime)
            return .object(["path": .string(path), "metadata": .string(output)])
        case "zip_file":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let output = try requiredString(arguments, "output", tool: name)
            guard output.hasSuffix(".zip") else {
                throw SystemToolError.executionFailed(tool: tool, message: "zip_file output must end in .zip.")
            }
            try Self.validateRelativePath(path, tool: name)
            try Self.validateRelativePath(output, tool: name)
            let result = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: "ditto -c -k --sequesterRsrc --keepParent " + Self.shellQuoted(path) + " " + Self.shellQuoted(output), timeoutSeconds: 300, runtime: runtime)
            return .object(["path": .string(path), "output": .string(output), "result": .string(result)])
        case "unzip_file":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let destination = try requiredString(arguments, "destination", tool: name)
            try Self.validateRelativePath(path, tool: name)
            try Self.validateRelativePath(destination, tool: name)
            let result = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: "mkdir -p " + Self.shellQuoted(destination) + " && ditto -x -k " + Self.shellQuoted(path) + " " + Self.shellQuoted(destination), timeoutSeconds: 300, runtime: runtime)
            return .object(["path": .string(path), "destination": .string(destination), "result": .string(result)])
        case "tar_archive_create":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let output = try requiredString(arguments, "output", tool: name)
            let compressed = output.hasSuffix(".tar.gz") || output.hasSuffix(".tgz")
            guard output.hasSuffix(".tar") || compressed else {
                throw SystemToolError.executionFailed(tool: tool, message: "tar_archive_create output must end in .tar, .tar.gz, or .tgz.")
            }
            try Self.validateRelativePath(path, tool: name)
            try Self.validateRelativePath(output, tool: name)
            let flags = compressed ? "-czf" : "-cf"
            let result = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: "tar \(flags) " + Self.shellQuoted(output) + " " + Self.shellQuoted(path), timeoutSeconds: 300, runtime: runtime)
            return .object(["path": .string(path), "output": .string(output), "result": .string(result)])
        case "tar_archive_extract":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let destination = try requiredString(arguments, "destination", tool: name)
            let compressed = path.hasSuffix(".tar.gz") || path.hasSuffix(".tgz")
            guard path.hasSuffix(".tar") || compressed else {
                throw SystemToolError.executionFailed(tool: tool, message: "tar_archive_extract path must end in .tar, .tar.gz, or .tgz.")
            }
            try Self.validateRelativePath(path, tool: name)
            try Self.validateRelativePath(destination, tool: name)
            let flags = compressed ? "-xzf" : "-xf"
            let result = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: "mkdir -p " + Self.shellQuoted(destination) + " && tar \(flags) " + Self.shellQuoted(path) + " -C " + Self.shellQuoted(destination), timeoutSeconds: 300, runtime: runtime)
            return .object(["path": .string(path), "destination": .string(destination), "result": .string(result)])
        case "gzip_compress_file":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let output = optionalString(arguments, "output") ?? path + ".gz"
            try Self.validateRelativePath(path, tool: name)
            try Self.validateRelativePath(output, tool: name)
            let result = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: "gzip -c " + Self.shellQuoted(path) + " > " + Self.shellQuoted(output), timeoutSeconds: 120, runtime: runtime)
            return .object(["path": .string(path), "output": .string(output), "result": .string(result)])
        case "gzip_decompress_file":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let output: String
            if let given = optionalString(arguments, "output") {
                output = given
            } else if path.hasSuffix(".gz") {
                output = String(path.dropLast(3))
            } else {
                output = path + ".decompressed"
            }
            try Self.validateRelativePath(path, tool: name)
            try Self.validateRelativePath(output, tool: name)
            let result = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: "gzip -dc " + Self.shellQuoted(path) + " > " + Self.shellQuoted(output), timeoutSeconds: 120, runtime: runtime)
            return .object(["path": .string(path), "output": .string(output), "result": .string(result)])
        case "count_file_lines":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? ""
            var targets: [String] = []
            if path.isEmpty {
                let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: "", recursive: true)
                targets = entries.filter { !$0.isDirectory }.map { $0.path }
            } else if let entries = try? await runtime.readWorkspaceDirectory(cwd: cwd, path: path, recursive: true) {
                targets = entries.filter { !$0.isDirectory }.map { $0.path }
            } else {
                targets = [path]
            }
            var total = 0
            var code = 0
            var comment = 0
            var blank = 0
            var files = 0
            for target in targets {
                guard let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: target) else {
                    continue
                }
                let counts = Self.lineCounts(document.content)
                total += counts.total
                code += counts.code
                comment += counts.comment
                blank += counts.blank
                files += 1
            }
            return .object(["path": .string(path), "files": .int(Int64(files)), "total": .int(Int64(total)), "code": .int(Int64(code)), "comment": .int(Int64(comment)), "blank": .int(Int64(blank))])
        case "extract_code_symbols":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? ""
            var sources: [String] = []
            if path.isEmpty {
                let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: "", recursive: true)
                sources = entries.filter { !$0.isDirectory && ($0.path as NSString).pathExtension == "swift" }.map { $0.path }
            } else if let entries = try? await runtime.readWorkspaceDirectory(cwd: cwd, path: path, recursive: true) {
                sources = entries.filter { !$0.isDirectory && ($0.path as NSString).pathExtension == "swift" }.map { $0.path }
            } else {
                sources = [path]
            }
            var symbols: [[String: JSONValue]] = []
            var files = 0
            for file in sources.sorted() {
                guard let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: file) else {
                    continue
                }
                symbols.append(contentsOf: Self.extractSymbols(document.content, path: file))
                files += 1
            }
            return .object(["path": .string(path), "files": .int(Int64(files)), "symbols": .array(symbols.map { .object($0) }), "count": .int(Int64(symbols.count))])
        case "find_duplicate_files":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? ""
            let entries = try await runtime.readWorkspaceDirectory(cwd: cwd, path: path, recursive: true)
            var byHash: [String: [String]] = [:]
            var byteLens: [String: Int] = [:]
            var skipped = 0
            for entry in entries where !entry.isDirectory {
                guard let data = try? Self.readWorkspaceBytes(cwd: cwd, path: entry.path, tool: name) else {
                    skipped += 1
                    continue
                }
                guard let hash = try? Self.checksumHex(data: data, algorithm: "sha256", tool: name) else {
                    skipped += 1
                    continue
                }
                byHash[hash, default: []].append(entry.path)
                byteLens[hash] = data.count
            }
            var groups: [[String: JSONValue]] = []
            for hash in byHash.keys.sorted() {
                guard let files = byHash[hash], files.count > 1 else {
                    continue
                }
                groups.append([
                    "hash": .string(hash),
                    "files": .array(files.sorted().map { .string($0) }),
                    "byteLen": .int(Int64(byteLens[hash] ?? 0)),
                ])
            }
            return .object(["path": .string(path), "groups": .array(groups.map { .object($0) }), "count": .int(Int64(groups.count)), "skipped": .int(Int64(skipped))])
        case "env_capture_logs":
            return try await runtime.memorySnapshot(scope: optionalString(arguments, "scope"), query: optionalString(arguments, "query"), limit: optionalInt(arguments, "limit") ?? 50)
        case "project_build":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            var buildArgv = ["xcodebuild", "build"]
            if let scheme = optionalString(arguments, "scheme") {
                try Self.g3Token(scheme, field: "scheme", tool: name)
                buildArgv += ["-scheme", scheme]
            }
            if let configuration = optionalString(arguments, "configuration") {
                try Self.g3Token(configuration, field: "configuration", tool: name)
                buildArgv += ["-configuration", configuration]
            }
            if let destination = optionalString(arguments, "destination") {
                try Self.g3Token(destination, field: "destination", tool: name)
                buildArgv += ["-destination", destination]
            }
            let buildTimeout = optionalInt(arguments, "timeoutSeconds") ?? 600
            let (buildExit, buildOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: buildArgv, timeoutSeconds: buildTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: buildExit, output: buildOutput)
            let buildDiagnostics = Self.parseG3Diagnostics(buildOutput)
            return .object([
                "succeeded": .bool(buildExit == 0),
                "exitCode": .int(Int64(buildExit)),
                "errors": .int(Int64(buildDiagnostics.filter { $0["severity"]?.stringValue == "error" }.count)),
                "warnings": .int(Int64(buildDiagnostics.filter { $0["severity"]?.stringValue == "warning" }.count)),
                "diagnostics": .array(buildDiagnostics.map { .object($0) }),
                "output": .string(buildOutput),
            ])
        case "project_test":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            var testArgv = ["xcodebuild", "test"]
            if let scheme = optionalString(arguments, "scheme") {
                try Self.g3Token(scheme, field: "scheme", tool: name)
                testArgv += ["-scheme", scheme]
            }
            if let configuration = optionalString(arguments, "configuration") {
                try Self.g3Token(configuration, field: "configuration", tool: name)
                testArgv += ["-configuration", configuration]
            }
            if let destination = optionalString(arguments, "destination") {
                try Self.g3Token(destination, field: "destination", tool: name)
                testArgv += ["-destination", destination]
            }
            let testTimeout = optionalInt(arguments, "timeoutSeconds") ?? 600
            let (testExit, testOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: testArgv, timeoutSeconds: testTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: testExit, output: testOutput)
            let testDiagnostics = Self.parseG3Diagnostics(testOutput)
            let testSummary = Self.parseG3TestSummary(testOutput)
            return .object([
                "succeeded": .bool(testExit == 0),
                "exitCode": .int(Int64(testExit)),
                "testsExecuted": .int(Int64(testSummary.executed)),
                "testsFailed": .int(Int64(testSummary.failed)),
                "suitesPassed": .int(Int64(testSummary.suitesPassed)),
                "suitesFailed": .int(Int64(testSummary.suitesFailed)),
                "errors": .int(Int64(testDiagnostics.filter { $0["severity"]?.stringValue == "error" }.count)),
                "warnings": .int(Int64(testDiagnostics.filter { $0["severity"]?.stringValue == "warning" }.count)),
                "diagnostics": .array(testDiagnostics.map { .object($0) }),
                "output": .string(testOutput),
            ])
        case "compiler_diagnostics_engine":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let kind = optionalString(arguments, "kind") ?? "xcodebuild"
            var diagnosticsArgv: [String] = []
            var diagnosticsCLI = "xcodebuild"
            switch kind {
            case "xcodebuild":
                diagnosticsArgv = ["xcodebuild", "build"]
                if let scheme = optionalString(arguments, "scheme") {
                    try Self.g3Token(scheme, field: "scheme", tool: name)
                    diagnosticsArgv += ["-scheme", scheme]
                }
                if let destination = optionalString(arguments, "destination") {
                    try Self.g3Token(destination, field: "destination", tool: name)
                    diagnosticsArgv += ["-destination", destination]
                }
            case "swiftpm":
                diagnosticsArgv = ["swift", "build"]
                diagnosticsCLI = "swift"
            default:
                throw SystemToolError.executionFailed(tool: name, message: "compiler_diagnostics_engine kind must be xcodebuild or swiftpm.")
            }
            let diagnosticsTimeout = optionalInt(arguments, "timeoutSeconds") ?? 600
            let (diagnosticsExit, diagnosticsOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: diagnosticsArgv, timeoutSeconds: diagnosticsTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: diagnosticsCLI, exitCode: diagnosticsExit, output: diagnosticsOutput)
            let diagnostics = Self.parseG3Diagnostics(diagnosticsOutput)
            return .object([
                "exitCode": .int(Int64(diagnosticsExit)),
                "errors": .int(Int64(diagnostics.filter { $0["severity"]?.stringValue == "error" }.count)),
                "warnings": .int(Int64(diagnostics.filter { $0["severity"]?.stringValue == "warning" }.count)),
                "diagnostics": .array(diagnostics.map { .object($0) }),
                "output": .string(diagnosticsOutput),
            ])
        case "dependency_resolution_engine":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let kind = optionalString(arguments, "kind") ?? "swiftpm"
            var resolveArgv: [String] = []
            var resolveCLI = "swift"
            switch kind {
            case "swiftpm":
                resolveArgv = ["swift", "package", "resolve"]
            case "xcode":
                guard let scheme = optionalString(arguments, "scheme") else {
                    throw SystemToolError.missingArgument(tool: name, argument: "scheme")
                }
                try Self.g3Token(scheme, field: "scheme", tool: name)
                resolveArgv = ["xcodebuild", "-resolvePackageDependencies", "-scheme", scheme]
                resolveCLI = "xcodebuild"
            default:
                throw SystemToolError.executionFailed(tool: name, message: "dependency_resolution_engine kind must be swiftpm or xcode.")
            }
            let resolveTimeout = optionalInt(arguments, "timeoutSeconds") ?? 300
            let (resolveExit, resolveOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: resolveArgv, timeoutSeconds: resolveTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: resolveCLI, exitCode: resolveExit, output: resolveOutput)
            return .object([
                "resolved": .bool(resolveExit == 0),
                "exitCode": .int(Int64(resolveExit)),
                "output": .string(resolveOutput),
            ])
        case "generate_xcodeproj":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 120
            let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcodegen", "generate"], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodegen", exitCode: exitCode, output: output)
            return .object([
                "generated": .bool(exitCode == 0),
                "exitCode": .int(Int64(exitCode)),
                "output": .string(output),
            ])
        case "project_scheme_list", "project_target_list":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 60
            let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcodebuild", "-list", "-json"], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: exitCode, output: output)
            if exitCode != 0 {
                if name == "project_target_list" {
                    return .object([
                        "targets": .array([]),
                        "exitCode": .int(Int64(exitCode)),
                        "output": .string(output),
                    ])
                }
                return .object([
                    "name": .string(""),
                    "schemes": .array([]),
                    "targets": .array([]),
                    "configurations": .array([]),
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            }
            let listed = try Self.g3JSONValue(output, tool: name)
            let (schemes, targets, configurations, projectName) = Self.parseG3XcodebuildList(listed)
            if name == "project_target_list" {
                return .object([
                    "targets": .array(targets.map { .string($0) }),
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            }
            return .object([
                "name": .string(projectName),
                "schemes": .array(schemes.map { .string($0) }),
                "targets": .array(targets.map { .string($0) }),
                "configurations": .array(configurations.map { .string($0) }),
                "exitCode": .int(Int64(exitCode)),
                "output": .string(output),
            ])
        case "project_build_settings":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            var settingsArgv = ["xcodebuild", "-showBuildSettings"]
            if let scheme = optionalString(arguments, "scheme") {
                try Self.g3Token(scheme, field: "scheme", tool: name)
                settingsArgv += ["-scheme", scheme]
            }
            if let configuration = optionalString(arguments, "configuration") {
                try Self.g3Token(configuration, field: "configuration", tool: name)
                settingsArgv += ["-configuration", configuration]
            }
            if let target = optionalString(arguments, "target") {
                try Self.g3Token(target, field: "target", tool: name)
                settingsArgv += ["-target", target]
            }
            let settingsTimeout = optionalInt(arguments, "timeoutSeconds") ?? 120
            let (settingsExit, settingsOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: settingsArgv, timeoutSeconds: settingsTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: settingsExit, output: settingsOutput)
            let settings = Self.parseG3BuildSettings(settingsOutput)
            return .object([
                "settings": .array(settings.map { .object($0) }),
                "exitCode": .int(Int64(settingsExit)),
                "output": .string(settingsOutput),
            ])
        case "project_clean":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            try Self.requireConfirm(arguments, tool: name, message: "project_clean removes build products; pass confirm=true.")
            var cleanArgv = ["xcodebuild", "clean"]
            if let scheme = optionalString(arguments, "scheme") {
                try Self.g3Token(scheme, field: "scheme", tool: name)
                cleanArgv += ["-scheme", scheme]
            }
            if let configuration = optionalString(arguments, "configuration") {
                try Self.g3Token(configuration, field: "configuration", tool: name)
                cleanArgv += ["-configuration", configuration]
            }
            let cleanTimeout = optionalInt(arguments, "timeoutSeconds") ?? 300
            let (cleanExit, cleanOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: cleanArgv, timeoutSeconds: cleanTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: cleanExit, output: cleanOutput)
            return .object([
                "cleaned": .bool(cleanExit == 0),
                "exitCode": .int(Int64(cleanExit)),
                "output": .string(cleanOutput),
            ])
        case "project_archive":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let scheme = try requiredString(arguments, "scheme", tool: name)
            try Self.g3Token(scheme, field: "scheme", tool: name)
            let archivePath = try requiredString(arguments, "archivePath", tool: name)
            try Self.validateRelativePath(archivePath, tool: name)
            var archiveArgv = ["xcodebuild", "archive", "-scheme", scheme, "-archivePath", archivePath]
            if let configuration = optionalString(arguments, "configuration") {
                try Self.g3Token(configuration, field: "configuration", tool: name)
                archiveArgv += ["-configuration", configuration]
            }
            if let destination = optionalString(arguments, "destination") {
                try Self.g3Token(destination, field: "destination", tool: name)
                archiveArgv += ["-destination", destination]
            }
            let archiveTimeout = optionalInt(arguments, "timeoutSeconds") ?? 1800
            let (archiveExit, archiveOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: archiveArgv, timeoutSeconds: archiveTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: archiveExit, output: archiveOutput)
            let archiveDiagnostics = Self.parseG3Diagnostics(archiveOutput)
            return .object([
                "archived": .bool(archiveExit == 0),
                "archivePath": .string(archivePath),
                "exitCode": .int(Int64(archiveExit)),
                "errors": .int(Int64(archiveDiagnostics.filter { $0["severity"]?.stringValue == "error" }.count)),
                "warnings": .int(Int64(archiveDiagnostics.filter { $0["severity"]?.stringValue == "warning" }.count)),
                "diagnostics": .array(archiveDiagnostics.map { .object($0) }),
                "output": .string(archiveOutput),
            ])
        case "test_run_single":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let testIdentifier = try requiredString(arguments, "testIdentifier", tool: name)
            try Self.g3TestIdentifier(testIdentifier, tool: name)
            var singleArgv = ["xcodebuild", "test", "-only-testing:" + testIdentifier]
            if let scheme = optionalString(arguments, "scheme") {
                try Self.g3Token(scheme, field: "scheme", tool: name)
                singleArgv += ["-scheme", scheme]
            }
            if let destination = optionalString(arguments, "destination") {
                try Self.g3Token(destination, field: "destination", tool: name)
                singleArgv += ["-destination", destination]
            }
            let singleTimeout = optionalInt(arguments, "timeoutSeconds") ?? 600
            let (singleExit, singleOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: singleArgv, timeoutSeconds: singleTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: singleExit, output: singleOutput)
            let singleDiagnostics = Self.parseG3Diagnostics(singleOutput)
            let singleSummary = Self.parseG3TestSummary(singleOutput)
            return .object([
                "succeeded": .bool(singleExit == 0),
                "testIdentifier": .string(testIdentifier),
                "exitCode": .int(Int64(singleExit)),
                "testsExecuted": .int(Int64(singleSummary.executed)),
                "testsFailed": .int(Int64(singleSummary.failed)),
                "suitesPassed": .int(Int64(singleSummary.suitesPassed)),
                "suitesFailed": .int(Int64(singleSummary.suitesFailed)),
                "errors": .int(Int64(singleDiagnostics.filter { $0["severity"]?.stringValue == "error" }.count)),
                "warnings": .int(Int64(singleDiagnostics.filter { $0["severity"]?.stringValue == "warning" }.count)),
                "diagnostics": .array(singleDiagnostics.map { .object($0) }),
                "output": .string(singleOutput),
            ])
        case "test_coverage_report":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let xcresultPath = try requiredString(arguments, "xcresultPath", tool: name)
            try Self.validateRelativePath(xcresultPath, tool: name)
            let coverageTimeout = optionalInt(arguments, "timeoutSeconds") ?? 300
            let (coverageExit, coverageOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcrun", "xccov", "view", "--report", "--json", xcresultPath], timeoutSeconds: coverageTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcrun", exitCode: coverageExit, output: coverageOutput)
            if coverageExit != 0 {
                return .object([
                    "lineCoverage": .null,
                    "targets": .array([]),
                    "exitCode": .int(Int64(coverageExit)),
                    "output": .string(coverageOutput),
                ])
            }
            let coverage = try Self.g3JSONValue(coverageOutput, tool: name)
            return .object([
                "lineCoverage": coverage["lineCoverage"] ?? .null,
                "targets": .array(Self.parseG3Coverage(coverage).map { .object($0) }),
                "exitCode": .int(Int64(coverageExit)),
                "output": .string(coverageOutput),
            ])
        case "test_coverage_reporter":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let xcresultPath = try requiredString(arguments, "xcresultPath", tool: name)
            try Self.validateRelativePath(xcresultPath, tool: name)
            let format = optionalString(arguments, "format") ?? "text"
            guard format == "json" || format == "text" else {
                throw SystemToolError.executionFailed(tool: name, message: "test_coverage_reporter format must be json or text.")
            }
            let reporterTimeout = optionalInt(arguments, "timeoutSeconds") ?? 300
            var reporterArgv = ["xcrun", "xccov", "view", "--report"]
            if format == "json" {
                reporterArgv += ["--json"]
            }
            reporterArgv += [xcresultPath]
            let (reporterExit, reporterOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: reporterArgv, timeoutSeconds: reporterTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcrun", exitCode: reporterExit, output: reporterOutput)
            if format == "json" {
                if reporterExit != 0 {
                    return .object([
                        "format": .string(format),
                        "report": .null,
                        "exitCode": .int(Int64(reporterExit)),
                        "output": .string(reporterOutput),
                    ])
                }
                let report = try Self.g3JSONValue(reporterOutput, tool: name)
                return .object([
                    "format": .string(format),
                    "report": report,
                    "exitCode": .int(Int64(reporterExit)),
                    "output": .string(reporterOutput),
                ])
            }
            return .object([
                "format": .string(format),
                "report": .string(reporterOutput),
                "exitCode": .int(Int64(reporterExit)),
                "output": .string(reporterOutput),
            ])
        case "performance_benchmark":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let benchmark = try requiredString(arguments, "benchmark", tool: name)
            let benchmarks: [String: [String]] = [
                "xcodebuild-build": ["xcodebuild", "build"],
                "xcodebuild-test": ["xcodebuild", "test"],
                "swift-build": ["swift", "build"],
                "swift-test": ["swift", "test"],
                "xcodebuild-clean-build": ["xcodebuild", "clean", "build"],
            ]
            guard var benchmarkArgv = benchmarks[benchmark] else {
                throw SystemToolError.executionFailed(tool: name, message: "performance_benchmark benchmark must be xcodebuild-build, xcodebuild-test, swift-build, swift-test, or xcodebuild-clean-build.")
            }
            let isXcodebuild = benchmark.hasPrefix("xcodebuild")
            if let scheme = optionalString(arguments, "scheme") {
                guard isXcodebuild else {
                    throw SystemToolError.executionFailed(tool: name, message: "performance_benchmark scheme applies only to xcodebuild benchmarks.")
                }
                try Self.g3Token(scheme, field: "scheme", tool: name)
                benchmarkArgv += ["-scheme", scheme]
            }
            let benchmarkCLI = benchmarkArgv[0]
            let benchmarkTimeout = optionalInt(arguments, "timeoutSeconds") ?? 600
            let benchmarkStarted = Date()
            let (benchmarkExit, benchmarkOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: benchmarkArgv, timeoutSeconds: benchmarkTimeout, runtime: runtime)
            let elapsed = Date().timeIntervalSince(benchmarkStarted)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: benchmarkCLI, exitCode: benchmarkExit, output: benchmarkOutput)
            return .object([
                "benchmark": .string(benchmark),
                "elapsedSeconds": .double(elapsed),
                "exitCode": .int(Int64(benchmarkExit)),
                "output": .string(benchmarkOutput),
            ])
        case "docc_build":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let scheme = try requiredString(arguments, "scheme", tool: name)
            try Self.g3Token(scheme, field: "scheme", tool: name)
            var doccArgv = ["xcodebuild", "docbuild", "-scheme", scheme]
            if let destination = optionalString(arguments, "destination") {
                try Self.g3Token(destination, field: "destination", tool: name)
                doccArgv += ["-destination", destination]
            }
            let doccTimeout = optionalInt(arguments, "timeoutSeconds") ?? 600
            let (doccExit, doccOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: doccArgv, timeoutSeconds: doccTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: doccExit, output: doccOutput)
            let doccDiagnostics = Self.parseG3Diagnostics(doccOutput)
            return .object([
                "succeeded": .bool(doccExit == 0),
                "exitCode": .int(Int64(doccExit)),
                "errors": .int(Int64(doccDiagnostics.filter { $0["severity"]?.stringValue == "error" }.count)),
                "warnings": .int(Int64(doccDiagnostics.filter { $0["severity"]?.stringValue == "warning" }.count)),
                "diagnostics": .array(doccDiagnostics.map { .object($0) }),
                "output": .string(doccOutput),
            ])
        case "xcode_scheme_manager":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let action = try requiredString(arguments, "action", tool: name)
            let managerTimeout = optionalInt(arguments, "timeoutSeconds") ?? 120
            switch action {
            case "list":
                let (listExit, listOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcodebuild", "-list", "-json"], timeoutSeconds: managerTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: listExit, output: listOutput)
                if listExit != 0 {
                    return .object([
                        "action": .string(action),
                        "schemes": .array([]),
                        "exitCode": .int(Int64(listExit)),
                        "output": .string(listOutput),
                    ])
                }
                let listed = try Self.g3JSONValue(listOutput, tool: name)
                let (schemes, _, _, _) = Self.parseG3XcodebuildList(listed)
                return .object([
                    "action": .string(action),
                    "schemes": .array(schemes.map { .string($0) }),
                    "exitCode": .int(Int64(listExit)),
                    "output": .string(listOutput),
                ])
            case "validate":
                guard let scheme = optionalString(arguments, "scheme") else {
                    throw SystemToolError.missingArgument(tool: name, argument: "scheme")
                }
                try Self.g3Token(scheme, field: "scheme", tool: name)
                let (validateExit, validateOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcodebuild", "-scheme", scheme, "-showBuildSettings"], timeoutSeconds: managerTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: validateExit, output: validateOutput)
                let validateSettings = Self.parseG3BuildSettings(validateOutput)
                let settingsCount = validateSettings.reduce(0) { $0 + ($1["settings"]?.objectValue?.count ?? 0) }
                return .object([
                    "action": .string(action),
                    "scheme": .string(scheme),
                    "valid": .bool(validateExit == 0),
                    "settingsCount": .int(Int64(settingsCount)),
                    "exitCode": .int(Int64(validateExit)),
                    "output": .string(validateOutput),
                ])
            default:
                throw SystemToolError.executionFailed(tool: name, message: "xcode_scheme_manager action must be list or validate.")
            }
        case "xcode_build_settings_inspector":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let key = try requiredString(arguments, "key", tool: name)
            try Self.g3Token(key, field: "key", tool: name)
            var inspectorArgv = ["xcodebuild", "-showBuildSettings"]
            if let scheme = optionalString(arguments, "scheme") {
                try Self.g3Token(scheme, field: "scheme", tool: name)
                inspectorArgv += ["-scheme", scheme]
            }
            if let configuration = optionalString(arguments, "configuration") {
                try Self.g3Token(configuration, field: "configuration", tool: name)
                inspectorArgv += ["-configuration", configuration]
            }
            let inspectorTimeout = optionalInt(arguments, "timeoutSeconds") ?? 120
            let (inspectorExit, inspectorOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: inspectorArgv, timeoutSeconds: inspectorTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: inspectorExit, output: inspectorOutput)
            let sections = Self.parseG3BuildSettings(inspectorOutput)
            var values: [[String: JSONValue]] = []
            for section in sections {
                if let value = section["settings"]?.objectValue?[key]?.stringValue {
                    values.append(["target": .string(section["target"]?.stringValue ?? ""), "value": .string(value)])
                }
            }
            return .object([
                "key": .string(key),
                "values": .array(values.map { .object($0) }),
                "found": .bool(!values.isEmpty),
                "exitCode": .int(Int64(inspectorExit)),
                "output": .string(inspectorOutput),
            ])
        case "xcode_device_destination_finder":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            var destinationsArgv = ["xcodebuild", "-showdestinations"]
            if let scheme = optionalString(arguments, "scheme") {
                try Self.g3Token(scheme, field: "scheme", tool: name)
                destinationsArgv += ["-scheme", scheme]
            }
            let destinationsTimeout = optionalInt(arguments, "timeoutSeconds") ?? 120
            let (destinationsExit, destinationsOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: destinationsArgv, timeoutSeconds: destinationsTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: destinationsExit, output: destinationsOutput)
            let destinations = Self.parseG3Destinations(destinationsOutput)
            return .object([
                "destinations": .array(destinations.map { .object($0) }),
                "exitCode": .int(Int64(destinationsExit)),
                "output": .string(destinationsOutput),
            ])
        case "simulator_list":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 60
            let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcrun", "simctl", "list", "-j", "devices"], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "simctl", exitCode: exitCode, output: output)
            if exitCode != 0 {
                return .object([
                    "devices": .array([]),
                    "runtimes": .array([]),
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            }
            let listed = try Self.g3JSONValue(output, tool: name)
            let devices = Self.parseG3SimctlDevices(listed)
            let runtimes = Set(devices.compactMap { $0["runtime"]?.stringValue }).sorted()
            return .object([
                "devices": .array(devices.map { .object($0) }),
                "runtimes": .array(runtimes.map { .string($0) }),
                "exitCode": .int(Int64(exitCode)),
                "output": .string(output),
            ])
        case "simulator_boot":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let device = try requiredString(arguments, "device", tool: name)
            try Self.g3Token(device, field: "device", tool: name)
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 120
            let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcrun", "simctl", "boot", device], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "simctl", exitCode: exitCode, output: output)
            return .object([
                "booted": .bool(exitCode == 0),
                "device": .string(device),
                "exitCode": .int(Int64(exitCode)),
                "output": .string(output),
            ])
        case "simulator_controller":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let action = try requiredString(arguments, "action", tool: name)
            let device = try requiredString(arguments, "device", tool: name)
            try Self.g3Token(device, field: "device", tool: name)
            let controllerTimeout = optionalInt(arguments, "timeoutSeconds") ?? 120
            switch action {
            case "boot", "shutdown", "erase":
                let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcrun", "simctl", action, device], timeoutSeconds: controllerTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "simctl", exitCode: exitCode, output: output)
                return .object([
                    "action": .string(action),
                    "device": .string(device),
                    "succeeded": .bool(exitCode == 0),
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            case "openurl":
                guard let url = optionalString(arguments, "url"), let parsed = URL(string: url), parsed.scheme != nil else {
                    throw SystemToolError.executionFailed(tool: name, message: "simulator_controller openurl requires a url with a scheme.")
                }
                let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcrun", "simctl", "openurl", device, url], timeoutSeconds: controllerTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "simctl", exitCode: exitCode, output: output)
                return .object([
                    "action": .string(action),
                    "device": .string(device),
                    "opened": .bool(exitCode == 0),
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            case "status":
                let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcrun", "simctl", "list", "-j", "devices"], timeoutSeconds: controllerTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "simctl", exitCode: exitCode, output: output)
                if exitCode != 0 {
                    return .object([
                        "action": .string(action),
                        "device": .string(device),
                        "state": .null,
                        "found": .bool(false),
                        "exitCode": .int(Int64(exitCode)),
                        "output": .string(output),
                    ])
                }
                let listed = try Self.g3JSONValue(output, tool: name)
                let devices = Self.parseG3SimctlDevices(listed)
                let match = devices.first { $0["udid"]?.stringValue == device || $0["name"]?.stringValue == device }
                return .object([
                    "action": .string(action),
                    "device": .string(device),
                    "state": match?["state"] ?? .null,
                    "found": .bool(match != nil),
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            default:
                throw SystemToolError.executionFailed(tool: name, message: "simulator_controller action must be boot, shutdown, erase, openurl, or status.")
            }
        case "device_list":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 60
            let (devicectlExit, devicectlOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcrun", "devicectl", "list", "devices"], timeoutSeconds: timeoutSeconds, runtime: runtime)
            var source = "devicectl"
            var exitCode = devicectlExit
            var output = devicectlOutput
            if devicectlExit == 127 || devicectlOutput.contains("command not found") || devicectlOutput.contains("unable to find utility") {
                source = "xctrace"
                let (xctraceExit, xctraceOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcrun", "xctrace", "list", "devices"], timeoutSeconds: timeoutSeconds, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "xctrace", exitCode: xctraceExit, output: xctraceOutput)
                exitCode = xctraceExit
                output = xctraceOutput
            }
            let lineCount = output.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            return .object([
                "source": .string(source),
                "exitCode": .int(Int64(exitCode)),
                "lineCount": .int(Int64(lineCount)),
                "output": .string(output),
            ])
        case "provisioning_check":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let profilePath = try requiredString(arguments, "profilePath", tool: name)
            try Self.validateRelativePath(profilePath, tool: name)
            guard profilePath.hasSuffix(".mobileprovision") || profilePath.hasSuffix(".provisionprofile") else {
                throw SystemToolError.executionFailed(tool: name, message: "provisioning_check profilePath must end in .mobileprovision or .provisionprofile.")
            }
            guard try await Self.g3FileExists(tool: name, threadId: threadId, path: profilePath, runtime: runtime) else {
                throw SystemToolError.executionFailed(tool: tool, message: "No such file: \(profilePath)")
            }
            let checkTimeout = optionalInt(arguments, "timeoutSeconds") ?? 60
            let (checkExit, checkOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["security", "cms", "-D", "-i", profilePath], timeoutSeconds: checkTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "security", exitCode: checkExit, output: checkOutput)
            if checkExit != 0 {
                return .object([
                    "valid": .bool(false),
                    "exitCode": .int(Int64(checkExit)),
                    "output": .string(checkOutput),
                ])
            }
            let profile = try Self.g3PlistObject(checkOutput, tool: name)
            guard let dict = profile as? [String: Any] else {
                throw SystemToolError.executionFailed(tool: name, message: "Provisioning profile did not decode as a property list dictionary.")
            }
            let expiration = dict["ExpirationDate"] as? Date
            let entitlements = (dict["Entitlements"] as? [String: Any])?.keys.sorted() ?? []
            return .object([
                "valid": .bool(true),
                "name": .string(dict["Name"] as? String ?? ""),
                "uuid": .string(dict["UUID"] as? String ?? ""),
                "teamIdentifier": .string((dict["TeamIdentifier"] as? [String])?.first ?? ""),
                "expirationDate": .string(expiration.map { ISO8601DateFormatter().string(from: $0) } ?? ""),
                "expired": .bool(expiration.map { $0 < Date() } ?? false),
                "entitlementKeys": .array(entitlements.map { .string($0) }),
                "exitCode": .int(Int64(checkExit)),
            ])
        case "swift_package_manager":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let action = try requiredString(arguments, "action", tool: name)
            let managerTimeout = optionalInt(arguments, "timeoutSeconds") ?? 300
            switch action {
            case "describe":
                let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["swift", "package", "describe", "--type", "json"], timeoutSeconds: managerTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "swift", exitCode: exitCode, output: output)
                if exitCode != 0 {
                    return .object([
                        "action": .string(action),
                        "description": .null,
                        "exitCode": .int(Int64(exitCode)),
                        "output": .string(output),
                    ])
                }
                let described = try Self.g3JSONValue(output, tool: name)
                return .object([
                    "action": .string(action),
                    "description": described,
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            case "resolve":
                let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["swift", "package", "resolve"], timeoutSeconds: managerTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "swift", exitCode: exitCode, output: output)
                return .object([
                    "action": .string(action),
                    "resolved": .bool(exitCode == 0),
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            case "clean":
                let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["swift", "package", "clean"], timeoutSeconds: managerTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "swift", exitCode: exitCode, output: output)
                return .object([
                    "action": .string(action),
                    "cleaned": .bool(exitCode == 0),
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            case "reset":
                try Self.requireConfirm(arguments, tool: name, message: "swift_package_manager reset removes the package build state; pass confirm=true.")
                let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["swift", "package", "reset"], timeoutSeconds: managerTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "swift", exitCode: exitCode, output: output)
                return .object([
                    "action": .string(action),
                    "reset": .bool(exitCode == 0),
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            default:
                throw SystemToolError.executionFailed(tool: name, message: "swift_package_manager action must be describe, resolve, clean, or reset.")
            }
        case "package_dependency_update":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            var updateArgv = ["swift", "package", "update"]
            if let package = optionalString(arguments, "package") {
                try Self.g3Identifier(package, field: "package", tool: name)
                updateArgv += [package]
            }
            let updateTimeout = optionalInt(arguments, "timeoutSeconds") ?? 300
            let (updateExit, updateOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: updateArgv, timeoutSeconds: updateTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "swift", exitCode: updateExit, output: updateOutput)
            return .object([
                "updated": .bool(updateExit == 0),
                "package": optionalString(arguments, "package").map { .string($0) } ?? .null,
                "exitCode": .int(Int64(updateExit)),
                "output": .string(updateOutput),
            ])
        case "code_signing_diagnose":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            try Self.validateRelativePath(path, tool: name)
            guard try await Self.g3FileExists(tool: name, threadId: threadId, path: path, runtime: runtime) else {
                throw SystemToolError.executionFailed(tool: tool, message: "No such file: \(path)")
            }
            let diagnoseTimeout = optionalInt(arguments, "timeoutSeconds") ?? 60
            let (verifyExit, verifyOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["codesign", "--verify", "--verbose", path], timeoutSeconds: diagnoseTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "codesign", exitCode: verifyExit, output: verifyOutput)
            let (dvExit, dvOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["codesign", "-dv", "--verbose=4", path], timeoutSeconds: diagnoseTimeout, runtime: runtime)
            let details = Self.parseG3Codesign(dvOutput)
            return .object([
                "path": .string(path),
                "verified": .bool(verifyExit == 0),
                "verifyExitCode": .int(Int64(verifyExit)),
                "verifyOutput": .string(verifyOutput),
                "details": .object(details),
                "exitCode": .int(Int64(dvExit)),
            ])
        case "xcode_toolchain_info":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let infoTimeout = optionalInt(arguments, "timeoutSeconds") ?? 60
            let (versionExit, versionOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcodebuild", "-version"], timeoutSeconds: infoTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: versionExit, output: versionOutput)
            let (xcodeVersion, xcodeBuild) = Self.parseG3XcodeVersion(versionOutput)
            let (selectExit, selectOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcode-select", "-p"], timeoutSeconds: infoTimeout, runtime: runtime)
            return .object([
                "xcodeVersion": .string(xcodeVersion),
                "xcodeBuild": .string(xcodeBuild),
                "developerDir": .string(selectOutput.trimmingCharacters(in: .whitespacesAndNewlines)),
                "exitCode": .int(Int64(versionExit)),
                "selectExitCode": .int(Int64(selectExit)),
            ])
        case "xcresult_parser":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            try Self.validateRelativePath(path, tool: name)
            guard path.hasSuffix(".xcresult") else {
                throw SystemToolError.executionFailed(tool: name, message: "xcresult_parser path must end in .xcresult.")
            }
            guard try await Self.g3FileExists(tool: name, threadId: threadId, path: path, runtime: runtime) else {
                throw SystemToolError.executionFailed(tool: tool, message: "No such file: \(path)")
            }
            let parserTimeout = optionalInt(arguments, "timeoutSeconds") ?? 120
            let (parserExit, parserOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcrun", "xcresulttool", "get", "--format", "json", "--path", path], timeoutSeconds: parserTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcrun", exitCode: parserExit, output: parserOutput)
            if parserExit != 0 {
                return .object([
                    "path": .string(path),
                    "result": .null,
                    "topLevelKeys": .array([]),
                    "exitCode": .int(Int64(parserExit)),
                    "output": .string(parserOutput),
                ])
            }
            let result = try Self.g3JSONValue(parserOutput, tool: name)
            let keys = (result.objectValue?.keys.sorted() ?? []).map { .string($0) }
            return .object([
                "path": .string(path),
                "result": result,
                "topLevelKeys": .array(keys),
                "exitCode": .int(Int64(parserExit)),
                "output": .string(parserOutput),
            ])
        case "mach_o_binary_analyzer":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            try Self.validateRelativePath(path, tool: name)
            guard try await Self.g3FileExists(tool: name, threadId: threadId, path: path, runtime: runtime) else {
                throw SystemToolError.executionFailed(tool: tool, message: "No such file: \(path)")
            }
            let analyzerTimeout = optionalInt(arguments, "timeoutSeconds") ?? 60
            let (fileExit, fileOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["file", path], timeoutSeconds: analyzerTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "file", exitCode: fileExit, output: fileOutput)
            let (otoolExit, otoolOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["otool", "-L", path], timeoutSeconds: analyzerTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "otool", exitCode: otoolExit, output: otoolOutput)
            let (hvExit, hvOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["otool", "-hv", path], timeoutSeconds: analyzerTimeout, runtime: runtime)
            let libraries = Self.parseG3OtoolLibraries(otoolOutput)
            let headers = Self.parseG3MachHeader(hvOutput)
            return .object([
                "path": .string(path),
                "file": .string(fileOutput.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""),
                "fileOutput": .string(fileOutput),
                "libraries": .array(libraries.map { .string($0) }),
                "headers": .array(headers.map { .object($0) }),
                "exitCode": .int(Int64(otoolExit)),
                "hvExitCode": .int(Int64(hvExit)),
            ])
        case "signing_certificate_inspector":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 60
            let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["security", "find-identity", "-v", "-p", "codesigning"], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "security", exitCode: exitCode, output: output)
            let identities = Self.parseG3Identities(output)
            return .object([
                "identities": .array(identities.map { .object($0) }),
                "count": .int(Int64(identities.count)),
                "exitCode": .int(Int64(exitCode)),
                "output": .string(output),
            ])
        case "provisioning_profile_reader":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let profilePath = try requiredString(arguments, "profilePath", tool: name)
            try Self.validateRelativePath(profilePath, tool: name)
            guard profilePath.hasSuffix(".mobileprovision") || profilePath.hasSuffix(".provisionprofile") else {
                throw SystemToolError.executionFailed(tool: name, message: "provisioning_profile_reader profilePath must end in .mobileprovision or .provisionprofile.")
            }
            guard try await Self.g3FileExists(tool: name, threadId: threadId, path: profilePath, runtime: runtime) else {
                throw SystemToolError.executionFailed(tool: tool, message: "No such file: \(profilePath)")
            }
            let readerTimeout = optionalInt(arguments, "timeoutSeconds") ?? 60
            let (readerExit, readerOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["security", "cms", "-D", "-i", profilePath], timeoutSeconds: readerTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "security", exitCode: readerExit, output: readerOutput)
            if readerExit != 0 {
                return .object([
                    "profile": .null,
                    "exitCode": .int(Int64(readerExit)),
                    "output": .string(readerOutput),
                ])
            }
            let profile = try Self.g3PlistObject(readerOutput, tool: name)
            return .object([
                "profile": Self.plistJSONValue(profile),
                "exitCode": .int(Int64(readerExit)),
            ])
        case "swift_ast_inspector":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            try Self.validateRelativePath(path, tool: name)
            guard path.hasSuffix(".swift") else {
                throw SystemToolError.executionFailed(tool: name, message: "swift_ast_inspector path must end in .swift.")
            }
            guard try await Self.g3FileExists(tool: name, threadId: threadId, path: path, runtime: runtime) else {
                throw SystemToolError.executionFailed(tool: tool, message: "No such file: \(path)")
            }
            let astTimeout = optionalInt(arguments, "timeoutSeconds") ?? 120
            let (astExit, astOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["swiftc", "-dump-ast", path], timeoutSeconds: astTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "swiftc", exitCode: astExit, output: astOutput)
            let counts = Self.parseG3ASTDeclCounts(astOutput)
            let total = counts["total"] ?? 0
            var declCounts: [String: JSONValue] = [:]
            for key in counts.keys.sorted() where key != "total" {
                declCounts[key] = .int(Int64(counts[key] ?? 0))
            }
            return .object([
                "path": .string(path),
                "declCounts": .object(declCounts),
                "totalDecls": .int(Int64(total)),
                "lineCount": .int(Int64(astOutput.components(separatedBy: "\n").count)),
                "exitCode": .int(Int64(astExit)),
                "output": .string(astOutput),
            ])
        case "binary_size_report":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let path = optionalString(arguments, "path") ?? "build"
            try Self.validateRelativePath(path, tool: name)
            let top = min(max(optionalInt(arguments, "top") ?? 20, 1), 100)
            let root = try await Self.resolveThreadRoot(threadId: threadId, tool: name, runtime: runtime)
            let entries = try await runtime.readWorkspaceDirectory(cwd: root, path: path, recursive: true)
            let reportTimeout = optionalInt(arguments, "timeoutSeconds") ?? 120
            let (reportExit, reportOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["du", "-ak", path], timeoutSeconds: reportTimeout, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "du", exitCode: reportExit, output: reportOutput)
            let sizes = Self.parseG3DuSizes(reportOutput)
            let files = sizes.filter { $0.path != path }
            let sorted = files.sorted { $0.kilobytes > $1.kilobytes }
            let total = files.reduce(0) { $0 + $1.kilobytes }
            return .object([
                "path": .string(path),
                "fileCount": .int(Int64(entries.filter { !$0.isDirectory }.count)),
                "totalKilobytes": .int(Int64(total)),
                "largest": .array(sorted.prefix(top).map { .object(["path": .string($0.path), "kilobytes": .int(Int64($0.kilobytes))]) }),
                "exitCode": .int(Int64(reportExit)),
            ])
        case "git_review_diff":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let scope = optionalString(arguments, "scope") ?? "uncommitted"
            guard scope == "uncommitted" || scope == "branch" else {
                throw SystemToolError.executionFailed(tool: name, message: "git_review_diff scope must be uncommitted or branch.")
            }
            let ignoreWhitespace = optionalBool(arguments, "ignoreWhitespace") ?? false
            let root = try await Self.resolveThreadRoot(threadId: threadId, tool: name, runtime: runtime)
            return try await runWorkspaceApiOperation(method: "git.review.diff", threadId: threadId, params: ["expectedRoot": .string(root), "scope": .string(scope), "ignoreWhitespace": .bool(ignoreWhitespace)], tool: name, timeoutSeconds: 120, runtime: runtime)
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

    private static func validateRelativePath(_ path: String, tool: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            throw SystemToolError.executionFailed(tool: tool, message: "Path must be relative to the working directory.")
        }
        let parts = path.split(separator: "/")
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw SystemToolError.executionFailed(tool: tool, message: "Path must not contain . or .. components.")
        }
    }

    private static func resolveWorkspaceFileURL(cwd: String, path: String, tool: String) throws -> URL {
        try validateRelativePath(path, tool: tool)
        let base = URL(fileURLWithPath: ExternalEditorService.expandedPath(cwd)).resolvingSymlinksInPath()
        let target = base.appendingPathComponent(path).resolvingSymlinksInPath()
        guard target.path == base.path || target.path.hasPrefix(base.path + "/") else {
            throw SystemToolError.executionFailed(tool: tool, message: "Path escapes the working directory.")
        }
        return target
    }

    private static func readWorkspaceBytes(cwd: String, path: String, tool: String) throws -> Data {
        let url = try resolveWorkspaceFileURL(cwd: cwd, path: path, tool: tool)
        guard let data = try? Data(contentsOf: url) else {
            throw SystemToolError.executionFailed(tool: tool, message: "File does not exist or cannot be read.")
        }
        guard data.count <= 3 * 1024 * 1024 else {
            throw SystemToolError.executionFailed(tool: tool, message: "File exceeds 3 MiB.")
        }
        return data
    }

    private static func writeWorkspaceBytes(cwd: String, path: String, data: Data, tool: String) throws {
        let url = try resolveWorkspaceFileURL(cwd: cwd, path: path, tool: tool)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    private static func checksumHex(data: Data, algorithm: String, tool: String) throws -> String {
        switch algorithm {
        case "sha256":
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha512":
            return SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha1":
            return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "md5":
            return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        default:
            throw SystemToolError.executionFailed(tool: tool, message: "Checksum algorithm must be sha256, sha512, sha1, or md5.")
        }
    }

    private static func artifactRelativePath(name: String, tool: String) throws -> String {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else {
            throw SystemToolError.executionFailed(tool: tool, message: "Artifact name must be a plain file name without any path separator.")
        }
        let fileName = name.hasSuffix(".md") ? name : name + ".md"
        return ".assist_temp/artifacts/" + fileName
    }

    private static func jsonObject(from text: String, tool: String) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw SystemToolError.executionFailed(tool: tool, message: "File is not valid UTF-8 text.")
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        } catch {
            throw SystemToolError.executionFailed(tool: tool, message: "Invalid JSON: \(error.localizedDescription)")
        }
    }

    private static func prettyJSONText(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func replacingExtension(_ path: String, with ext: String) -> String {
        (path as NSString).deletingPathExtension + "." + ext
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if inQuotes {
                if char == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(char)
                }
            } else if char == "\"", field.isEmpty {
                inQuotes = true
            } else if char == "," {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r" {
                if char == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                row.append(field)
                field = ""
                rows.append(row)
                row = []
            } else {
                field.append(char)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func jsonScalarText(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case is NSNull:
            return ""
        case let array as [Any]:
            return (try? prettyJSONText(array)) ?? String(describing: array)
        case let dict as [String: Any]:
            return (try? prettyJSONText(dict)) ?? String(describing: dict)
        default:
            return String(describing: value)
        }
    }

    private static func yamlIssues(_ text: String) -> [String] {
        var issues: [String] = []
        var topKeys: [String: Int] = [:]
        let lines = text.components(separatedBy: "\n")
        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            if rawLine.contains("\t") {
                issues.append("Line \(lineNumber): tab character; YAML forbids tabs for indentation.")
            }
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            var inSingle = false
            var inDouble = false
            var squares = 0
            var braces = 0
            var scan = rawLine.startIndex
            while scan < rawLine.endIndex {
                let char = rawLine[scan]
                if char == "'" && !inDouble {
                    inSingle.toggle()
                } else if char == "\"" && !inSingle {
                    inDouble.toggle()
                } else if !inSingle && !inDouble {
                    if char == "[" {
                        squares += 1
                    } else if char == "]" {
                        squares -= 1
                    } else if char == "{" {
                        braces += 1
                    } else if char == "}" {
                        braces -= 1
                    } else if char == "#" {
                        let previous = scan == rawLine.startIndex ? " " : rawLine[rawLine.index(before: scan)]
                        if previous == " " || previous == "\t" {
                            break
                        }
                    }
                }
                scan = rawLine.index(after: scan)
            }
            if inSingle || inDouble {
                issues.append("Line \(lineNumber): unbalanced quote.")
            }
            if squares != 0 {
                issues.append("Line \(lineNumber): unbalanced square bracket.")
            }
            if braces != 0 {
                issues.append("Line \(lineNumber): unbalanced brace.")
            }
            if !rawLine.hasPrefix(" ") && !rawLine.hasPrefix("\t") {
                if let colon = yamlKeyColon(trimmed) {
                    let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty, !key.contains(" ") {
                        if let first = topKeys[key] {
                            issues.append("Line \(lineNumber): duplicate top-level key \(key), first seen on line \(first).")
                        } else {
                            topKeys[key] = lineNumber
                        }
                    }
                }
            }
        }
        return issues
    }

    private static func yamlNormalized(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            var out = line
            while out.hasPrefix("\t") {
                out = "  " + String(out.dropFirst())
            }
            return out.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }

    private static func yamlKeyColon(_ text: String) -> String.Index? {
        var inSingle = false
        var inDouble = false
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "'" && !inDouble {
                inSingle.toggle()
            } else if char == "\"" && !inSingle {
                inDouble.toggle()
            } else if char == ":", !inSingle, !inDouble {
                let next = text.index(after: index)
                if next == text.endIndex || text[next] == " " {
                    return index
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func yamlScalar(_ text: String) -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "~" || trimmed.lowercased() == "null" {
            return .null
        }
        if trimmed.lowercased() == "true" {
            return .bool(true)
        }
        if trimmed.lowercased() == "false" {
            return .bool(false)
        }
        if let int = Int(trimmed) {
            return .int(Int64(int))
        }
        if let double = Double(trimmed) {
            return .double(double)
        }
        var value = trimmed
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return .string(value)
    }

    private static func yamlParse(_ text: String, tool: String) throws -> JSONValue {
        var lines: [(indent: Int, text: String)] = []
        for raw in text.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            var indent = 0
            for char in raw {
                if char == " " {
                    indent += 1
                } else {
                    break
                }
            }
            lines.append((indent, String(raw.dropFirst(indent))))
        }
        var index = 0
        let value = try yamlParseBlock(lines, &index, 0, tool)
        guard index == lines.count else {
            throw SystemToolError.executionFailed(tool: tool, message: "YAML has content outside the parsed structure; only mappings, lists, and scalars are supported.")
        }
        return value
    }

    private static func yamlParseBlock(_ lines: [(indent: Int, text: String)], _ index: inout Int, _ indent: Int, _ tool: String) throws -> JSONValue {
        guard index < lines.count else {
            return .null
        }
        let line = lines[index]
        guard line.indent == indent else {
            return .null
        }
        if line.text == "-" || line.text.hasPrefix("- ") {
            return try yamlParseList(lines, &index, indent, tool)
        }
        if yamlKeyColon(line.text) != nil {
            return try yamlParseMap(lines, &index, indent, tool)
        }
        index += 1
        return yamlScalar(line.text)
    }

    private static func yamlParseMap(_ lines: [(indent: Int, text: String)], _ index: inout Int, _ indent: Int, _ tool: String) throws -> JSONValue {
        var object: [String: JSONValue] = [:]
        while index < lines.count {
            let line = lines[index]
            guard line.indent == indent else {
                break
            }
            if line.text == "-" || line.text.hasPrefix("- ") {
                break
            }
            guard let colon = yamlKeyColon(line.text) else {
                break
            }
            let key = String(line.text[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw SystemToolError.executionFailed(tool: tool, message: "YAML mapping key is empty.")
            }
            let rest = String(line.text[line.text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            index += 1
            if !rest.isEmpty {
                object[key] = yamlScalar(rest)
            } else if index < lines.count, lines[index].indent > indent {
                object[key] = try yamlParseBlock(lines, &index, lines[index].indent, tool)
            } else {
                object[key] = .null
            }
        }
        return .object(object)
    }

    private static func yamlParseList(_ lines: [(indent: Int, text: String)], _ index: inout Int, _ indent: Int, _ tool: String) throws -> JSONValue {
        var items: [JSONValue] = []
        while index < lines.count {
            let line = lines[index]
            guard line.indent == indent else {
                break
            }
            guard line.text == "-" || line.text.hasPrefix("- ") else {
                break
            }
            let rest = line.text == "-" ? "" : String(line.text.dropFirst(2))
            if rest.isEmpty {
                index += 1
                if index < lines.count, lines[index].indent > indent {
                    items.append(try yamlParseBlock(lines, &index, lines[index].indent, tool))
                } else {
                    items.append(.null)
                }
            } else if yamlKeyColon(rest) != nil {
                var object: [String: JSONValue] = [:]
                guard let colon = yamlKeyColon(rest) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "YAML list item has no key.")
                }
                let key = String(rest[..<colon]).trimmingCharacters(in: .whitespaces)
                let valueText = String(rest[rest.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                index += 1
                if !valueText.isEmpty {
                    object[key] = yamlScalar(valueText)
                } else if index < lines.count, lines[index].indent > indent {
                    object[key] = try yamlParseBlock(lines, &index, lines[index].indent, tool)
                } else {
                    object[key] = .null
                }
                while index < lines.count, lines[index].indent == indent + 2, yamlKeyColon(lines[index].text) != nil {
                    let follow = lines[index]
                    guard let followColon = yamlKeyColon(follow.text) else {
                        break
                    }
                    let followKey = String(follow.text[..<followColon]).trimmingCharacters(in: .whitespaces)
                    let followRest = String(follow.text[follow.text.index(after: followColon)...]).trimmingCharacters(in: .whitespaces)
                    index += 1
                    if !followRest.isEmpty {
                        object[followKey] = yamlScalar(followRest)
                    } else if index < lines.count, lines[index].indent > indent + 2 {
                        object[followKey] = try yamlParseBlock(lines, &index, lines[index].indent, tool)
                    } else {
                        object[followKey] = .null
                    }
                }
                items.append(.object(object))
            } else {
                items.append(yamlScalar(rest))
                index += 1
            }
        }
        return .array(items)
    }

    private static func plistJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let dict as [String: Any]:
            return .object(Dictionary(uniqueKeysWithValues: dict.map { ($0.key, plistJSONValue($0.value)) }))
        case let array as [Any]:
            return .array(array.map { plistJSONValue($0) })
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let double = number.doubleValue
            if double == double.rounded(), abs(double) < 9.0e15 {
                return .int(Int64(double))
            }
            return .double(double)
        case let data as Data:
            return .string(data.base64EncodedString())
        case let date as Date:
            return .string(ISO8601DateFormatter().string(from: date))
        default:
            return .string(String(describing: value))
        }
    }

    private static func readPlist(cwd: String, path: String, tool: String) throws -> (Any, PropertyListSerialization.PropertyListFormat) {
        let data = try readWorkspaceBytes(cwd: cwd, path: path, tool: tool)
        var format = PropertyListSerialization.PropertyListFormat.xml
        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            return (object, format)
        } catch {
            throw SystemToolError.executionFailed(tool: tool, message: "Invalid property list: \(error.localizedDescription)")
        }
    }

    private static func writePlist(cwd: String, path: String, object: Any, format: PropertyListSerialization.PropertyListFormat, tool: String) throws {
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0)
        } catch {
            throw SystemToolError.executionFailed(tool: tool, message: "Cannot serialize property list: \(error.localizedDescription)")
        }
        try writeWorkspaceBytes(cwd: cwd, path: path, data: data, tool: tool)
        let (verified, _) = try readPlist(cwd: cwd, path: path, tool: tool)
        let matches: Bool
        if let lhs = object as? NSObject, let rhs = verified as? NSObject {
            matches = lhs.isEqual(rhs)
        } else {
            matches = String(describing: verified) == String(describing: object)
        }
        guard matches else {
            throw SystemToolError.executionFailed(tool: tool, message: "Property list verification failed: the file changed after writing.")
        }
    }

    private static func plistValue(at keyPath: String, in object: Any) -> Any? {
        var current: Any? = object
        for part in keyPath.split(separator: ".") {
            guard let dict = current as? [String: Any] else {
                return nil
            }
            current = dict[String(part)]
        }
        return current
    }

    private static func plistSet(_ value: Any, keyPath: String, root: inout [String: Any]) {
        var parts = keyPath.split(separator: ".").map(String.init)
        guard let first = parts.first else {
            return
        }
        if parts.count == 1 {
            root[first] = value
            return
        }
        var child = (root[first] as? [String: Any]) ?? [:]
        parts.removeFirst()
        plistSet(value, keyPath: parts.joined(separator: "."), root: &child)
        root[first] = child
    }

    private static func plistDelete(keyPath: String, root: inout [String: Any]) -> Bool {
        var parts = keyPath.split(separator: ".").map(String.init)
        guard let first = parts.first else {
            return false
        }
        if parts.count == 1 {
            return root.removeValue(forKey: first) != nil
        }
        guard var child = root[first] as? [String: Any] else {
            return false
        }
        parts.removeFirst()
        let removed = plistDelete(keyPath: parts.joined(separator: "."), root: &child)
        root[first] = child
        return removed
    }

    private static func unifiedDiff(oldText: String, newText: String, oldPath: String, newPath: String) -> (diff: String, added: Int, removed: Int) {
        let oldLines = oldText.components(separatedBy: "\n")
        let newLines = newText.components(separatedBy: "\n")
        let n = oldLines.count
        let m = newLines.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in (0..<n).reversed() {
            for j in (0..<m).reversed() {
                if oldLines[i] == newLines[j] {
                    table[i][j] = table[i + 1][j + 1] + 1
                } else {
                    table[i][j] = max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var ops: [(Character, String)] = []
        var i = 0
        var j = 0
        while i < n, j < m {
            if oldLines[i] == newLines[j] {
                ops.append((" ", oldLines[i]))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                ops.append(("-", oldLines[i]))
                i += 1
            } else {
                ops.append(("+", newLines[j]))
                j += 1
            }
        }
        while i < n {
            ops.append(("-", oldLines[i]))
            i += 1
        }
        while j < m {
            ops.append(("+", newLines[j]))
            j += 1
        }
        var added = 0
        var removed = 0
        for op in ops {
            if op.0 == "+" {
                added += 1
            } else if op.0 == "-" {
                removed += 1
            }
        }
        let changeIndices = ops.indices.filter { ops[$0].0 != " " }
        var groups: [[Int]] = []
        for idx in changeIndices {
            if let last = groups.last, let lastIdx = last.last, idx - lastIdx <= 7 {
                groups[groups.count - 1].append(idx)
            } else {
                groups.append([idx])
            }
        }
        var out: [String] = ["--- \(oldPath)", "+++ \(newPath)"]
        for group in groups {
            let start = max(0, group.first! - 3)
            let end = min(ops.count, group.last! + 4)
            var oldStart = 1
            var newStart = 1
            for k in 0..<start {
                if ops[k].0 != "+" {
                    oldStart += 1
                }
                if ops[k].0 != "-" {
                    newStart += 1
                }
            }
            var oldCount = 0
            var newCount = 0
            for k in start..<end {
                if ops[k].0 != "+" {
                    oldCount += 1
                }
                if ops[k].0 != "-" {
                    newCount += 1
                }
            }
            let oldRange = oldCount == 1 ? "\(oldStart)" : "\(oldStart),\(oldCount)"
            let newRange = newCount == 1 ? "\(newStart)" : "\(newStart),\(newCount)"
            out.append("@@ -\(oldRange) +\(newRange) @@")
            for k in start..<end {
                out.append("\(ops[k].0)\(ops[k].1)")
            }
        }
        return (out.joined(separator: "\n"), added, removed)
    }

    private static func lineCounts(_ content: String) -> (total: Int, code: Int, comment: Int, blank: Int) {
        if content.isEmpty {
            return (0, 0, 0, 0)
        }
        var lines = content.components(separatedBy: "\n")
        if content.hasSuffix("\n") {
            lines.removeLast()
        }
        var total = 0
        var code = 0
        var comment = 0
        var blank = 0
        var inBlock = false
        for rawLine in lines {
            total += 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                blank += 1
                continue
            }
            if inBlock {
                comment += 1
                if line.contains("*/") {
                    inBlock = false
                }
                continue
            }
            if line.hasPrefix("//") || line.hasPrefix("#") || line.hasPrefix("*") {
                comment += 1
                continue
            }
            if line.hasPrefix("/*") {
                comment += 1
                if !line.dropFirst(2).contains("*/") {
                    inBlock = true
                }
                continue
            }
            code += 1
        }
        return (total, code, comment, blank)
    }

    private static func extractSymbols(_ content: String, path: String) -> [[String: JSONValue]] {
        var symbols: [[String: JSONValue]] = []
        let pattern = "^\\s*(?:(?:public|private|fileprivate|internal|open)\\s+)*(?:final\\s+|override\\s+|static\\s+|class\\s+)*(class|struct|enum|protocol|actor|extension|func)\\s+([A-Za-z_][A-Za-z0-9_]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges == 3,
                  let kindRange = Range(match.range(at: 1), in: line),
                  let nameRange = Range(match.range(at: 2), in: line) else {
                continue
            }
            symbols.append([
                "path": .string(path),
                "kind": .string(String(line[kindRange])),
                "name": .string(String(line[nameRange])),
                "line": .int(Int64(index + 1)),
            ])
        }
        return symbols
    }

    private static func wholeWordReplace(_ content: String, old: String, new: String) -> (String, Int) {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: old) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (content, 0)
        }
        let range = NSRange(content.startIndex..., in: content)
        let count = regex.numberOfMatches(in: content, range: range)
        let replaced = regex.stringByReplacingMatches(in: content, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: new))
        return (replaced, count)
    }

    private static func symbolDeclarationLine(_ lines: [String], symbol: String) -> Int? {
        let pattern = "^\\s*(?:(?:public|private|fileprivate|internal|open)\\s+)*(?:final\\s+|override\\s+|static\\s+|class\\s+)*(?:class|struct|enum|protocol|actor|extension|func)\\s+" + NSRegularExpression.escapedPattern(for: symbol) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, range: range) != nil {
                return index
            }
        }
        return nil
    }

    private static func braceBlockEnd(_ lines: [String], from start: Int) -> Int? {
        var depth = 0
        var sawOpen = false
        var index = start
        while index < lines.count {
            for char in lines[index] {
                if char == "{" {
                    depth += 1
                    sawOpen = true
                }
                if char == "}" {
                    depth -= 1
                }
            }
            if sawOpen, depth == 0 {
                return index
            }
            if depth < 0 {
                return nil
            }
            index += 1
        }
        return nil
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func cleanTerminalOutput(_ output: String) -> String {
        output.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.contains("__AGENTS_TOOL_DONE__:") && !trimmed.hasPrefix("cd ")
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runShellCommand(tool: String, threadId: String, cwd: String, command: String, timeoutSeconds: Int, runtime: AgentsRuntimeClient) async throws -> String {
        let fullCommand = "cd " + shellQuoted(ExternalEditorService.expandedPath(cwd)) + " && " + command
        let result = try await runTerminalCommand(tool: tool, threadId: threadId, command: fullCommand, timeoutSeconds: timeoutSeconds, runtime: runtime)
        if result["timedOut"]?.boolValue == true {
            throw SystemToolError.operationTimeout(tool: tool)
        }
        let exitCode = result["exitCode"]?.intValue ?? -1
        let cleaned = cleanTerminalOutput(result["output"]?.stringValue ?? "")
        guard exitCode == 0 else {
            throw SystemToolError.executionFailed(tool: tool, message: "Command failed with exit code \(exitCode): \(cleaned)")
        }
        return cleaned
    }

    private static func normalizedText(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: "\t", with: "    ").replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
        }
        var out: [String] = []
        var blanks = 0
        for line in lines {
            if line.isEmpty {
                blanks += 1
                if blanks <= 2 {
                    out.append(line)
                }
            } else {
                blanks = 0
                out.append(line)
            }
        }
        var text = out.joined(separator: "\n")
        if !text.isEmpty, !text.hasSuffix("\n") {
            text += "\n"
        }
        return text
    }

    private static func codeTemplate(_ template: String, module: String, fileName: String, tool: String) throws -> String {
        let base = (fileName as NSString).deletingPathExtension
        let first = base.unicodeScalars.first
        let validStart = first.map { CharacterSet.letters.contains($0) || $0 == "_" } ?? false
        let validRest = base.unicodeScalars.dropFirst().allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
        guard validStart, validRest else {
            throw SystemToolError.executionFailed(tool: tool, message: "File name must be a valid Swift identifier for code generation.")
        }
        switch template {
        case "swift_struct":
            return "import Foundation\n\npublic struct \(base) {\n    public init() {}\n}\n"
        case "swift_class":
            return "import Foundation\n\npublic final class \(base) {\n    public init() {}\n}\n"
        case "swiftui_view":
            return "import SwiftUI\n\npublic struct \(base): View {\n    public var body: some View {\n        Text(\"\(base)\")\n    }\n}\n"
        case "test":
            return "import Testing\n@testable import \(module)\n\n@Suite(\"\(base)\")\nstruct \(base) {\n    @Test(\"Placeholder\")\n    func placeholder() {\n        #expect(Bool(false), \"Replace this failing scaffold with a real assertion.\")\n    }\n}\n"
        default:
            throw SystemToolError.executionFailed(tool: tool, message: "Unknown code template \(template); use swift_struct, swift_class, swiftui_view, or test.")
        }
    }

    private static func tocSlug(_ text: String) -> String {
        var kept = ""
        for char in text.lowercased() {
            if char.isLetter || char.isNumber || char == " " || char == "-" {
                kept.append(char)
            }
        }
        let spaced = kept.replacingOccurrences(of: " ", with: "-")
        var slug = ""
        var previousDash = false
        for char in spaced {
            if char == "-" {
                if !previousDash {
                    slug.append(char)
                }
                previousDash = true
            } else {
                slug.append(char)
                previousDash = false
            }
        }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
    private static func g3Run(
        tool: String,
        threadId: String,
        argv: [String],
        timeoutSeconds: Int,
        runtime: AgentsRuntimeClient
    ) async throws -> (exitCode: Int, output: String) {
        let command = argv.map { shellQuoted($0) }.joined(separator: " ")
        let result = try await runTerminalCommand(tool: tool, threadId: threadId, command: command, timeoutSeconds: timeoutSeconds, runtime: runtime)
        if result["timedOut"]?.boolValue == true {
            throw SystemToolError.operationTimeout(tool: tool)
        }
        let exitCode = result["exitCode"]?.intValue ?? -1
        return (exitCode, cleanTerminalOutput(result["output"]?.stringValue ?? ""))
    }

    private static func g3ThrowIfMissingCLI(tool: String, cli: String, exitCode: Int, output: String) throws {
        if exitCode == 127 || output.contains("command not found") || output.contains("unable to find utility") {
            throw SystemToolError.executionFailed(tool: tool, message: "\(cli) is not installed on this machine.")
        }
    }

    private static func g3Token(_ value: String, field: String, tool: String) throws {
        guard !value.isEmpty, !value.contains("\n"), !value.contains("\r"), !value.hasPrefix("-") else {
            throw SystemToolError.executionFailed(tool: tool, message: "\(field) must be a non-empty value without newlines or a leading dash.")
        }
    }

    private static func g3Identifier(_ value: String, field: String, tool: String) throws {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "_.-")
        guard !value.isEmpty, value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw SystemToolError.executionFailed(tool: tool, message: "\(field) must use only letters, digits, underscore, dot, or dash.")
        }
    }

    private static func g3TestIdentifier(_ value: String, tool: String) throws {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "_./-")
        let segments = value.split(separator: "/")
        guard !value.isEmpty, !value.hasPrefix("-"), !value.contains("\n"), !value.contains("\r"), value.unicodeScalars.allSatisfy({ allowed.contains($0) }), !segments.isEmpty, segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw SystemToolError.executionFailed(tool: tool, message: "testIdentifier must be a slash-separated test path using letters, digits, underscore, dot, dash, or slash.")
        }
    }

    private static func g3JSONText(_ output: String) -> String {
        let lines = output.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("{") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) else {
            return output
        }
        return lines[start...].joined(separator: "\n")
    }

    private static func g3PlistText(_ output: String) -> String {
        let lines = output.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("<?xml") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("<plist") }) else {
            return output
        }
        return lines[start...].joined(separator: "\n")
    }

    private static func g3JSONValue(_ text: String, tool: String) throws -> JSONValue {
        guard let data = g3JSONText(text).data(using: .utf8) else {
            throw SystemToolError.executionFailed(tool: tool, message: "Command output was not valid UTF-8.")
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw SystemToolError.executionFailed(tool: tool, message: "Command output was not valid JSON: \(error.localizedDescription)")
        }
    }

    private static func g3PlistObject(_ text: String, tool: String) throws -> Any {
        guard let data = g3PlistText(text).data(using: .utf8) else {
            throw SystemToolError.executionFailed(tool: tool, message: "Command output was not valid UTF-8.")
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        do {
            return try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        } catch {
            throw SystemToolError.executionFailed(tool: tool, message: "Command output was not a valid property list: \(error.localizedDescription)")
        }
    }

    private static func g3FileExists(tool: String, threadId: String, path: String, runtime: AgentsRuntimeClient) async throws -> Bool {
        let root = try await Self.resolveThreadRoot(threadId: threadId, tool: tool, runtime: runtime)
        let target = URL(fileURLWithPath: root).appendingPathComponent(path).standardized
        guard target.path == root || target.path.hasPrefix(root + "/") else {
            throw SystemToolError.executionFailed(tool: tool, message: "Path escapes the working directory.")
        }
        return FileManager.default.fileExists(atPath: target.path)
    }

    static func parseG3Diagnostics(_ output: String) -> [[String: JSONValue]] {
        var diagnostics: [[String: JSONValue]] = []
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            var matched = false
            for severity in ["error", "warning", "note"] {
                let marker = ": \(severity): "
                guard let range = line.range(of: marker) else { continue }
                let head = String(line[..<range.lowerBound])
                let message = String(line[range.upperBound...])
                let parts = head.split(separator: ":")
                var path = head
                var lineNumber = 0
                var column = 0
                if parts.count >= 3, let parsedLine = Int(parts[parts.count - 2]), let parsedColumn = Int(parts[parts.count - 1]) {
                    lineNumber = parsedLine
                    column = parsedColumn
                    path = parts.dropLast(2).joined(separator: ":")
                } else if parts.count >= 2, let parsedLine = Int(parts[parts.count - 1]) {
                    lineNumber = parsedLine
                    path = parts.dropLast().joined(separator: ":")
                }
                diagnostics.append([
                    "path": .string(path),
                    "line": .int(Int64(lineNumber)),
                    "column": .int(Int64(column)),
                    "severity": .string(severity),
                    "message": .string(message),
                ])
                matched = true
                break
            }
            if matched { continue }
            for severity in ["error", "warning", "note"] {
                let prefix = "\(severity): "
                if line.hasPrefix(prefix) {
                    diagnostics.append([
                        "path": .string(""),
                        "line": .int(0),
                        "column": .int(0),
                        "severity": .string(severity),
                        "message": .string(String(line.dropFirst(prefix.count))),
                    ])
                    break
                }
            }
        }
        return diagnostics
    }

    static func parseG3TestSummary(_ output: String) -> (executed: Int, failed: Int, suitesPassed: Int, suitesFailed: Int) {
        var executed = 0
        var failed = 0
        var suitesPassed = 0
        var suitesFailed = 0
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Executed ") {
                let fields = line.split(separator: " ")
                if fields.count >= 2, let count = Int(fields[1]) {
                    executed += count
                }
                if let withRange = line.range(of: "with "), let failuresRange = line.range(of: " failures") {
                    let countText = line[withRange.upperBound..<failuresRange.lowerBound].trimmingCharacters(in: .whitespaces)
                    if let count = Int(countText) {
                        failed += count
                    }
                }
            } else if line.hasPrefix("Test Suite '") {
                if line.contains("' passed at ") {
                    suitesPassed += 1
                } else if line.contains("' failed at ") {
                    suitesFailed += 1
                }
            }
        }
        return (executed, failed, suitesPassed, suitesFailed)
    }

    static func parseG3BuildSettings(_ output: String) -> [[String: JSONValue]] {
        var sections: [[String: JSONValue]] = []
        var currentTarget = ""
        var current: [String: String] = [:]
        var currentKey: String?
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("Build settings for action ") {
                if !current.isEmpty {
                    sections.append(["target": .string(currentTarget), "settings": .object(current.mapValues { .string($0) })])
                }
                current = [:]
                currentKey = nil
                if let start = line.range(of: "target \"") {
                    let rest = line[start.upperBound...]
                    currentTarget = rest.split(separator: "\"").first.map(String.init) ?? ""
                } else {
                    currentTarget = ""
                }
                continue
            }
            if line.hasPrefix("    "), !line.hasPrefix("     ") {
                let stripped = line.trimmingCharacters(in: .whitespaces)
                if let eq = stripped.range(of: " = ") {
                    let key = String(stripped[..<eq.lowerBound])
                    let value = String(stripped[eq.upperBound...])
                    current[key] = value
                    currentKey = key
                    continue
                }
            }
            if let key = currentKey, line.hasPrefix(" ") || line.hasPrefix("\t") {
                let stripped = line.trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty {
                    current[key] = (current[key] ?? "") + " " + stripped
                }
            }
        }
        if !current.isEmpty {
            sections.append(["target": .string(currentTarget), "settings": .object(current.mapValues { .string($0) })])
        }
        return sections
    }

    static func parseG3XcodebuildList(_ value: JSONValue) -> (schemes: [String], targets: [String], configurations: [String], name: String) {
        let project = value["project"]
        return (
            schemes: project?["schemes"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            targets: project?["targets"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            configurations: project?["configurations"]?.arrayValue?.compactMap(\.stringValue) ?? [],
            name: project?["name"]?.stringValue ?? ""
        )
    }

    static func parseG3Coverage(_ value: JSONValue) -> [[String: JSONValue]] {
        var targets: [[String: JSONValue]] = []
        for target in value["targets"]?.arrayValue ?? [] {
            var entry: [String: JSONValue] = [:]
            if let name = target["name"]?.stringValue { entry["name"] = .string(name) }
            if let coverage = target["lineCoverage"]?.doubleValue { entry["lineCoverage"] = .double(coverage) }
            if let covered = target["coveredLines"]?.intValue { entry["coveredLines"] = .int(Int64(covered)) }
            if let executable = target["executableLines"]?.intValue { entry["executableLines"] = .int(Int64(executable)) }
            if !entry.isEmpty { targets.append(entry) }
        }
        return targets
    }

    static func parseG3Destinations(_ output: String) -> [[String: JSONValue]] {
        var destinations: [[String: JSONValue]] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { continue }
            let inner = String(trimmed.dropFirst().dropLast())
            var fields: [String] = []
            var depth = 0
            var current = ""
            for char in inner {
                if char == "[" { depth += 1 }
                if char == "]" { depth -= 1 }
                if char == "," && depth == 0 {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(char)
                }
            }
            if !current.trimmingCharacters(in: .whitespaces).isEmpty { fields.append(current) }
            var record: [String: JSONValue] = [:]
            for field in fields {
                let parts = field.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { record[key] = .string(value) }
            }
            if !record.isEmpty { destinations.append(record) }
        }
        return destinations
    }

    static func parseG3SimctlDevices(_ value: JSONValue) -> [[String: JSONValue]] {
        var devices: [[String: JSONValue]] = []
        guard let runtimes = value["devices"]?.objectValue else { return devices }
        for runtime in runtimes.keys.sorted() {
            for device in runtimes[runtime]?.arrayValue ?? [] {
                var entry: [String: JSONValue] = [
                    "udid": .string(device["udid"]?.stringValue ?? ""),
                    "name": .string(device["name"]?.stringValue ?? ""),
                    "state": .string(device["state"]?.stringValue ?? ""),
                    "runtime": .string(runtime),
                    "isAvailable": .bool(device["isAvailable"]?.boolValue ?? false),
                ]
                if let typeId = device["deviceTypeIdentifier"]?.stringValue { entry["deviceTypeIdentifier"] = .string(typeId) }
                devices.append(entry)
            }
        }
        return devices
    }

    static func parseG3XcodeVersion(_ output: String) -> (version: String, build: String) {
        var version = ""
        var build = ""
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Xcode ") { version = String(trimmed.dropFirst("Xcode ".count)) }
            if trimmed.hasPrefix("Build version ") { build = String(trimmed.dropFirst("Build version ".count)) }
        }
        return (version, build)
    }

    static func parseG3Codesign(_ output: String) -> [String: JSONValue] {
        var details: [String: JSONValue] = [:]
        var authorities: [String] = []
        for line in output.components(separatedBy: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            if key == "Authority" {
                authorities.append(value)
            } else {
                details[key] = .string(value)
            }
        }
        if !authorities.isEmpty { details["Authority"] = .array(authorities.map { .string($0) }) }
        return details
    }

    static func parseG3OtoolLibraries(_ output: String) -> [String] {
        var libraries: [String] = []
        for line in output.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let paren = trimmed.firstIndex(of: "(") {
                libraries.append(String(trimmed[..<paren]).trimmingCharacters(in: .whitespaces))
            } else {
                libraries.append(trimmed)
            }
        }
        return libraries
    }

    static func parseG3MachHeader(_ output: String) -> [[String: JSONValue]] {
        var headers: [[String: JSONValue]] = []
        var sawHeader = false
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "Mach header" || trimmed.hasPrefix("magic ") {
                sawHeader = true
                continue
            }
            if sawHeader {
                let fields = trimmed.split(separator: " ").map(String.init)
                if fields.count >= 5 {
                    headers.append([
                        "magic": .string(fields[0]),
                        "cputype": .string(fields[1]),
                        "filetype": .string(fields[4]),
                    ])
                }
                sawHeader = false
            }
        }
        return headers
    }

    static func parseG3Identities(_ output: String) -> [[String: JSONValue]] {
        var identities: [[String: JSONValue]] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: ")", maxSplits: 1)
            guard parts.count == 2, let index = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            let rest = parts[1].trimmingCharacters(in: .whitespaces)
            let fields = rest.split(separator: " ", maxSplits: 1)
            guard fields.count == 2 else { continue }
            let hash = String(fields[0])
            var name = String(fields[1]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
                name = String(name.dropFirst().dropLast())
            }
            identities.append(["index": .int(Int64(index)), "hash": .string(hash), "name": .string(name)])
        }
        return identities
    }

    static func parseG3ASTDeclCounts(_ output: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        var total = 0
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("(") else { continue }
            let name = trimmed.dropFirst().split(separator: " ").first.map(String.init) ?? ""
            guard name.hasSuffix("_decl") else { continue }
            counts[name, default: 0] += 1
            total += 1
        }
        counts["total"] = total
        return counts
    }

    static func parseG3DuSizes(_ output: String) -> [(path: String, kilobytes: Int)] {
        var sizes: [(path: String, kilobytes: Int)] = []
        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let size = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            sizes.append((path: String(parts[1]), kilobytes: size))
        }
        return sizes
    }
}
