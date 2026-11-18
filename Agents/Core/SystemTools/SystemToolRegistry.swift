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
