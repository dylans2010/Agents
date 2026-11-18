import AppKit
import CoincideRemoteKit
import CryptoKit
import Foundation
@preconcurrency import UserNotifications

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
            action: "workspace.write_file",
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
        SystemToolDefinition(
            name: "search_symbol",
            description: "Heuristic declaration search for a symbol across four regex declaration patterns. Regex scan, not semantic analysis.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "symbol", type: "string", required: true, description: "Symbol name to search for."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "dependency_graph",
            description: "Regex import scan listing which files import which modules. Nodes conflate file paths and module names.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "source_graph_builder",
            description: "Regex symbol and import graph over the workspace. Type edges come from declaration regex, not a semantic index.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "semantic_query_engine",
            description: "Substring concept search over workspace text. Substring matching, not semantic search.",
            action: "workspace.search",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "query", type: "string", required: true, description: "Substring to search for."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "code_summary",
            description: "Line, non-empty-line and comment counts for one file. Does not extract interface declarations.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "code_lint",
            description: "Line-length over 120 plus TODO and FIXME scan for one file or the workspace. Regex and line rules, not a style analyzer.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "complexity_analysis",
            description: "Substring keyword counting for one file. Counts keywords in comments and strings too; not real cyclomatic complexity.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "autonomous_review_engine",
            description: "Heuristic keyword scan for force-unwraps and concurrency smells. No retain-cycle check; findings are leads, not diagnoses.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "runtime_diagnostics_engine",
            description: "Keyword scan of a crash or diagnostics log file for fatal errors, signals and thread mentions. Leads, not diagnoses.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "logPath", type: "string", required: true, description: "Crash or diagnostics log file, relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "code_metrics_analyzer",
            description: "Line counts, comment density, function and type counts, plus a keyword-based complexity estimate per Swift file.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "memory_leak_detector",
            description: "Heuristic static scan for unowned self captures, strong self captures, non-weak delegates and timer observers.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "dead_code_eliminator",
            description: "Report-only list of unreferenced private function candidates with file and line evidence. Deletes nothing; deletion is a separate confirmed edit.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "dead_code_scan",
            description: "Heuristic scan for declarations with zero references elsewhere in the workspace. Overloaded names are excluded.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "duplicate_code_scan",
            description: "Normalized six-line sliding-window scan for repeated code blocks, reported as file and line pairs.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "todo_scan",
            description: "Heuristic regex inventory of TODO, FIXME, XXX and HACK markers with file, line and text.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "todo_fixme_scanner",
            description: "Heuristic regex inventory of TODO, FIXME, HACK and NOTE annotations with file, line and text.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "license_header_check",
            description: "Lists Swift files whose first 15 lines lack the required header text. Defaults to Copyright.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "requiredText", type: "string", required: false, description: "Header text that must appear in the first 15 lines. Defaults to Copyright."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "api_surface_extract",
            description: "Public and open declarations grouped by file, with counts. Regex scan, not a compiler API surface.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "access_level_audit",
            description: "Declaration counts by access level: public, open, internal, private, fileprivate. Regex scan.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "concurrency_audit",
            description: "Heuristic scan for main-queue sync, nonisolated unsafe, unstructured tasks, shared mutable statics and sync blocks.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "swift_concurrency_analyzer",
            description: "Heuristic scan for non-Sendable transfers, unsafe mutable state and actor reentrancy hazards. Regex scan, not a compiler check.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "swift_migration_advisor",
            description: "Heuristic audit for Swift 6 strict concurrency, mutable globals and actor isolation issues. Regex scan.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "security_audit_scanner",
            description: "Heuristic scan for hardcoded secrets, plain HTTP URLs and unsafe credentials. Secret matches report file, line and pattern only, never values.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "secrets_scan",
            description: "Heuristic scan for AWS keys, GitHub tokens, sk keys, credential assignments and private-key blocks. Reports file, line and pattern only, never matched values or line contents.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "network_security_auditor",
            description: "Heuristic scan of App Transport Security keys, plaintext HTTP URLs and certificate pinning rules. Regex scan.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "permissions_audit",
            description: "Heuristic scan of Info.plist usage descriptions, entitlements and PrivacyInfo entries, with missing-description checks.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "accessibility_audit",
            description: "Heuristic scan for Buttons, Images and TextFields and their accessibility labels, hints and values. Regex scan.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "accessibility_audit_scanner",
            description: "Heuristic scan of SwiftUI and AppKit views for accessibility labels, hints, traits and identifiers. Regex scan.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "interface_simulator",
            description: "Heuristic audit of SwiftUI view structures, accessibility traits, dynamic type scaling and tap targets. Regex scan, not a running simulator.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "docstring_generator",
            description: "Generates Apple DocC style markdown doc blocks for Swift declarations found by regex in one file.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "symbol", type: "string", required: false, description: "Declaration name; when given, only that declaration is documented."),
            ]
        ),
        SystemToolDefinition(
            name: "code_snippet_manager",
            description: "Returns a standardized Swift 6 template by name, and writes it to path when given. Templates are fixed starter text, not generated code.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "template", type: "string", required: true, description: "Template name: observable, asyncstream, actor, or glasscard."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "unused_imports_detector",
            description: "Heuristic scan for Swift module imports never referenced elsewhere in the same file.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "force_unwrap_scan",
            description: "Heuristic regex scan for force unwraps, try! and as! across Swift sources.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "string_literal_audit",
            description: "Heuristic scan for hardcoded user-facing string literals not routed through localization. Regex scan.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "comment_density_report",
            description: "Comment-to-code ratios per Swift file, least-documented first. Line-based counts, not semantic documentation quality.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "function_size_report",
            description: "Longest functions by brace-counted line span, highlighting decomposition candidates. Heuristic spans, not a compiler AST.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "call_hierarchy",
            description: "Definition site, callers and callees for a function name, from regex. Callers are textual call sites, not a compiler call graph.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "function", type: "string", required: true, description: "Function name to trace."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "type_hierarchy",
            description: "Class, struct, enum and protocol declarations with inheritance and conformance clauses, from regex.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "protocol_conformance_list",
            description: "Every type declaring conformance to a protocol, from regex over declaration lines.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "protocol", type: "string", required: true, description: "Protocol name to list conformances for."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "import_graph",
            description: "File-level import graph; which files import a given module. Regex scan over import lines.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "module", type: "string", required: false, description: "Module name; when given, only files importing it are listed."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "change_impact_estimate",
            description: "Blast-radius estimate: files textually referencing a symbol name. Regex scan, not a dependency graph.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "symbol", type: "string", required: true, description: "Symbol name to search for."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "conflict_marker_scan",
            description: "Regex scan for unresolved merge-conflict markers in source files.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "build_log_analyze",
            description: "Parses a build log file for errors, warnings and the build result. Text parsing, not a build run.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "crash_log_parse",
            description: "Parses a crash log file for exception type, termination reason, faulting thread and blamed frames. Text parsing.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "deprecation_usage_scan",
            description: "Regex scan for deprecated markers in declarations. Usage sites of a deprecated API need the API name via search_symbol.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "info_plist_audit",
            description: "Audits Info.plist files for required keys, version-format sanity and duplicate bundle identifiers. Text parsing.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "api_endpoint_audit",
            description: "Hardcoded http and https URL literals grouped by host. Regex scan.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "color_usage_audit",
            description: "Heuristic scan for hardcoded colors that should live in the asset catalog. Regex scan.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "strings_file_validate",
            description: "Validates .strings files for syntax, duplicate keys and empty values. Line-based parsing.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "entitlements_diff",
            description: "Diffs two .entitlements plists into added, removed and changed keys. Text parsing.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "otherPath", type: "string", required: true, description: "Second file to compare against path, relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "pbxproj_lint",
            description: "Read-only regex lint over project.pbxproj text: file references pointing at missing files, duplicate paths and dangling build-file refs. Never writes the pbxproj.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "xctest_discovery",
            description: "Lists XCTestCase subclasses and test methods by regex, without running anything.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "build_settings_diff",
            description: "Diffs two .xcconfig files key by key. Text parsing.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
                SystemToolParameter(name: "otherPath", type: "string", required: true, description: "Second file to compare against path, relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "build_phase_scripts_list",
            description: "Lists Run Script build phases from project.pbxproj text with truncated script bodies. Read-only.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "build_configuration_list",
            description: "Lists build configurations per project and target from project.pbxproj text. Read-only.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "target_dependencies_list",
            description: "Lists target-to-target dependencies from project.pbxproj text. Read-only.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "target_source_list",
            description: "Lists source files compiled into each target from Compile Sources phases in project.pbxproj text. Read-only.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "workspace_settings_read",
            description: "Reads Xcode workspace .xcsettings plists as key-value pairs. Text parsing.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "scheme_test_plan_list",
            description: "Lists .xctestplan files and the test targets each covers. JSON parsing, no test run.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "test_log_parse",
            description: "Parses a test log for pass and fail outcomes, suite summaries, error lines and the failed list. Text parsing.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "test_flaky_detect",
            description: "Parses a test log for tests with both pass and fail outcomes. Text parsing.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Path relative to the working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "code_comment_extract",
            description: "Extracts triple-slash and block doc comments per file, optionally limited to files mentioning a symbol. Regex scan.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
                SystemToolParameter(name: "symbol", type: "string", required: false, description: "Symbol name; when given, only files mentioning it are included."),
            ]
        ),
        SystemToolDefinition(
            name: "api_docs_coverage",
            description: "Share of public declarations carrying doc comments, from regex over Swift files.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "markdown_link_check",
            description: "Validates internal links in Markdown files against the workspace file list. Regex plus file existence, not a link crawler.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum matches to return."),
            ]
        ),
        SystemToolDefinition(
            name: "docs_index_build",
            description: "Indexes Markdown files with path, first-heading title and size. Line-based reading.",
            action: "workspace.files",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "framework_linker_auditor",
            description: "Audits linked frameworks from the pbxproj against target platforms and weak-linking flags. Text parsing of the project file.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to project.pbxproj. Defaults to the first project.pbxproj found."),
            ]
        ),
        SystemToolDefinition(
            name: "string_catalog_migrator",
            description: "Migrates legacy .strings and .stringsdict files into a modern .xcstrings catalog, then verifies the catalog by re-reading it.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to migrate, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "sourceLanguage", type: "string", required: false, description: "Source language for the catalog. Defaults to en."),
            ]
        ),
        SystemToolDefinition(
            name: "symbol_reference_graph",
            description: "Finds definitions and reference sites of one symbol across Swift sources. Regex scan, not semantic analysis.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "symbol", type: "string", required: true, description: "Symbol name to trace."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum reference sites to return."),
            ]
        ),
        SystemToolDefinition(
            name: "podfile_inspector",
            description: "Parses and validates CocoaPods Podfile dependencies and target integrations, with versions from Podfile.lock when present.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to the Podfile. Defaults to the first Podfile found."),
            ]
        ),
        SystemToolDefinition(
            name: "carthage_cartfile_inspector",
            description: "Inspects Carthage Cartfile and Cartfile.resolved dependencies with their resolved versions.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to the Cartfile. Defaults to the first Cartfile found."),
            ]
        ),
        SystemToolDefinition(
            name: "spm_dependency_tree",
            description: "Computes the resolved SwiftPM dependency graph from swift package show-dependencies JSON output.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Package directory relative to the working directory. Defaults to the workspace root."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Command timeout in seconds."),
            ]
        ),
        SystemToolDefinition(
            name: "package_manifest_read",
            description: "Parses Package.swift: name, platforms, products, targets, and dependencies. Text parsing, no swift invocation.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to Package.swift. Defaults to Package.swift in the workspace root."),
            ]
        ),
        SystemToolDefinition(
            name: "package_manifest_validate",
            description: "Validates Package.swift with swift package dump-package: exit code plus name and target count from the parsed manifest.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Package directory relative to the working directory. Defaults to the workspace root."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Command timeout in seconds."),
            ]
        ),
        SystemToolDefinition(
            name: "package_dependency_audit",
            description: "Audits Package.swift against Package.resolved: manifest dependencies missing from resolved, non-exact requirements, and resolved pins missing from the manifest.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Package directory relative to the working directory. Defaults to the workspace root."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Command timeout in seconds."),
            ]
        ),
        SystemToolDefinition(
            name: "package_dependency_add",
            description: "Inserts a .package(url:from:) dependency into Package.swift with optional product and target wiring, then verifies on re-read.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "url", type: "string", required: true, description: "Package repository URL."),
                SystemToolParameter(name: "version", type: "string", required: true, description: "Minimum version for from:."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to Package.swift. Defaults to Package.swift in the workspace root."),
                SystemToolParameter(name: "product", type: "string", required: false, description: "Product name to wire into a target."),
                SystemToolParameter(name: "target", type: "string", required: false, description: "Target name to wire the product into."),
            ]
        ),
        SystemToolDefinition(
            name: "asset_catalog_list",
            description: "Enumerates .xcassets catalogs with image, color, icon, dataset, and symbol sets plus counts.",
            action: "workspace.files",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "asset_image_add",
            description: "Creates an imageName.imageset with a valid Contents.json and copies a workspace image into it, verified on re-read.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "imageName", type: "string", required: true, description: "Image set name without the .imageset suffix."),
                SystemToolParameter(name: "source", type: "string", required: true, description: "Workspace image file to copy, relative to the working directory."),
                SystemToolParameter(name: "catalog", type: "string", required: false, description: "Relative path to the .xcassets catalog. Defaults to the first catalog found."),
            ]
        ),
        SystemToolDefinition(
            name: "strings_localization",
            description: "Gets, sets, or deletes one localization key in a .strings or .xcstrings file, per locale.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Relative path to the .strings or .xcstrings file."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action: get, set, or delete."),
                SystemToolParameter(name: "key", type: "string", required: true, description: "Localization key."),
                SystemToolParameter(name: "value", type: "string", required: false, description: "Value for set."),
                SystemToolParameter(name: "locale", type: "string", required: false, description: "Locale code for .xcstrings. Defaults to the catalog source language."),
            ]
        ),
        SystemToolDefinition(
            name: "localization_audit",
            description: "Reports missing keys per locale and keys never referenced in Swift sources.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to audit, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum findings to return."),
            ]
        ),
        SystemToolDefinition(
            name: "localize_app",
            description: "Localizes an app: discovers NSLocalizedString keys in Swift, creates or merges Localizable.xcstrings with per-locale state, and sets Info.plist CFBundleLocalizations and CFBundleDevelopmentRegion.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action: localize, status, or set_development_region."),
                SystemToolParameter(name: "languages", type: "array", required: false, description: "Target language codes for localize, at most 3."),
                SystemToolParameter(name: "translations", type: "array", required: false, description: "Translations for localize, each with locale, key, and value."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "developmentRegion", type: "string", required: false, description: "Development region code for set_development_region."),
            ]
        ),
        SystemToolDefinition(
            name: "asset_catalog_manager",
            description: "Inspects, manages, and creates .xcassets catalogs, color sets, and image sets.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action: list, inspect, create_imageset, or create_colorset."),
                SystemToolParameter(name: "catalog", type: "string", required: false, description: "Relative path to the .xcassets catalog. Defaults to the first catalog found."),
                SystemToolParameter(name: "name", type: "string", required: false, description: "Set name for inspect and create actions."),
                SystemToolParameter(name: "source", type: "string", required: false, description: "Workspace image file to copy for create_imageset."),
                SystemToolParameter(name: "lightHex", type: "string", required: false, description: "Light-mode hex color for create_colorset."),
                SystemToolParameter(name: "darkHex", type: "string", required: false, description: "Dark-mode hex color for create_colorset."),
            ]
        ),
        SystemToolDefinition(
            name: "localization_manager",
            description: "Inspects, extracts, adds translations to, and validates .strings and .xcstrings catalogs.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action: list, extract, add, or validate."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to manage, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "key", type: "string", required: false, description: "Localization key for add."),
                SystemToolParameter(name: "value", type: "string", required: false, description: "Translation value for add."),
                SystemToolParameter(name: "locale", type: "string", required: false, description: "Locale code for add to .xcstrings."),
            ]
        ),
        SystemToolDefinition(
            name: "entitlements_manager",
            description: "Inspects, adds, or removes App Sandbox, Network Client and Server, and security entitlements in .entitlements plists.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action: list, add, or remove."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to the .entitlements file. Defaults to the first one found."),
                SystemToolParameter(name: "key", type: "string", required: false, description: "Entitlement key for add and remove."),
                SystemToolParameter(name: "value", type: "string", required: false, description: "Value for add: true, false, or a string."),
                SystemToolParameter(name: "threadId", type: "string", required: false, description: "Owning thread ID. Only used by the MCP server path."),
            ]
        ),
        SystemToolDefinition(
            name: "colorset_builder",
            description: "Generates a .colorset asset catalog JSON with light and dark mode hex definitions.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "name", type: "string", required: true, description: "Color set name without the .colorset suffix."),
                SystemToolParameter(name: "lightHex", type: "string", required: true, description: "Light-mode hex color, for example #FF8800."),
                SystemToolParameter(name: "catalog", type: "string", required: false, description: "Relative path to the .xcassets catalog. Defaults to the first catalog found."),
                SystemToolParameter(name: "darkHex", type: "string", required: false, description: "Dark-mode hex color. Defaults to the light hex."),
            ]
        ),
        SystemToolDefinition(
            name: "icon_generator_tool",
            description: "Generates a complete AppIcon set for iOS, macOS, or watchOS from source artwork with real sips resizing.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "source", type: "string", required: true, description: "Source artwork file, relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: true, description: "Destination .appiconset directory, relative to the working directory."),
                SystemToolParameter(name: "platform", type: "string", required: false, description: "Platform: ios, macos, or watchos. Defaults to ios."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Command timeout in seconds."),
            ]
        ),
        SystemToolDefinition(
            name: "project_entitlements",
            description: "Parses .entitlements files and returns their keys and values.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to the .entitlements file. Defaults to the first one found."),
            ]
        ),
        SystemToolDefinition(
            name: "project_info_plist",
            description: "Gets, sets, or deletes Info.plist keys with real plist serialization.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action: get, set, or delete."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to the plist. Defaults to the first Info.plist found."),
                SystemToolParameter(name: "key", type: "string", required: false, description: "Plist key for get, set, and delete."),
                SystemToolParameter(name: "value", type: "string", required: false, description: "Value for set: true, false, a number, or a string."),
                SystemToolParameter(name: "threadId", type: "string", required: false, description: "Owning thread ID. Only used by the MCP server path."),
            ]
        ),
        SystemToolDefinition(
            name: "project_capabilities",
            description: "Lists, enables, or disables Xcode capabilities backed by boolean entitlements. Array-valued capabilities are reported, not silently rewritten.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action: list, enable, or disable."),
                SystemToolParameter(name: "capability", type: "string", required: false, description: "Capability name for enable and disable, for example app-sandbox or network-client."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to the .entitlements file. Defaults to the first one found."),
                SystemToolParameter(name: "threadId", type: "string", required: false, description: "Owning thread ID. Only used by the MCP server path."),
            ]
        ),
        SystemToolDefinition(
            name: "project_signing",
            description: "Reports CODE_SIGN_STYLE, DEVELOPMENT_TEAM, and bundle ID from the pbxproj plus provisioning profile filenames, never profile contents.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to project.pbxproj. Defaults to the first project.pbxproj found."),
                SystemToolParameter(name: "scheme", type: "string", required: false, description: "Scheme to query with xcodebuild -showBuildSettings. Defaults to pbxproj text parsing only."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Command timeout in seconds."),
            ]
        ),
        SystemToolDefinition(
            name: "entry_points_discover",
            description: "Finds application entry points: @main types, main.swift files, and AppDelegate and SceneDelegate classes.",
            action: "workspace.search_regex",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum entry points to return."),
            ]
        ),
        SystemToolDefinition(
            name: "repo_overview",
            description: "Summarizes the repository: file counts by language, README and license presence, and largest files.",
            action: "workspace.files",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to summarize, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "project_structure_map",
            description: "Builds a machine-readable map of directories with file counts plus Xcode targets from the pbxproj.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to map, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "recent_changes",
            description: "Lists files modified within the last N hours, newest first, from real file modification times.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "hours", type: "integer", required: false, description: "Look-back window in hours. Defaults to 24."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum files to return."),
            ]
        ),
        SystemToolDefinition(
            name: "readme_locate",
            description: "Finds README files with their title lines.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to search, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "dependency_licenses",
            description: "Inventories third-party dependencies from Package.resolved and Podfile.lock for license review, with name, version, and source.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to inventory, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "stale_files_report",
            description: "Reports source files not modified in a long time, from real file modification times.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "days", type: "integer", required: false, description: "Staleness threshold in days. Defaults to 180."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum files to return."),
            ]
        ),
        SystemToolDefinition(
            name: "file_type_breakdown",
            description: "Reports file counts and bytes per extension across the workspace.",
            action: "workspace.files",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to analyze, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "empty_dirs_find",
            description: "Finds empty directories, candidates for cleanup.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to search, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "symlink_audit",
            description: "Lists symbolic links with their targets, flagging broken links.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to audit, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "executable_files_scan",
            description: "Lists files with the executable bit set, from real file metadata.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to scan, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "dir_size_report",
            description: "Reports recursive disk usage per subdirectory, largest first, from real file sizes.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to analyze, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum directories to return."),
            ]
        ),
        SystemToolDefinition(
            name: "image_asset_size_report",
            description: "Reports oversized images inside .xcassets catalogs, from real file sizes.",
            action: "workspace.read_dir",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to scan, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "maxKilobytes", type: "integer", required: false, description: "Size threshold in kilobytes. Defaults to 500."),
            ]
        ),
        SystemToolDefinition(
            name: "bundle_resource_auditor",
            description: "Scans target app bundles for missing, duplicated, or bloated resources from pbxproj resource phases and real files.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to project.pbxproj. Defaults to the first project.pbxproj found."),
            ]
        ),
        SystemToolDefinition(
            name: "core_data_model_inspector",
            description: "Inspects Core Data .xcdatamodeld models: entities, attributes, and relationships.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to inspect, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "swift_data_schema_auditor",
            description: "Audits SwiftData @Model declarations, relationships, and uniqueness constraints in Swift sources.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory to audit, relative to the working directory. Defaults to the whole workspace."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum findings to return."),
            ]
        ),
        SystemToolDefinition(
            name: "privacy_manifest_auditor",
            description: "Audits PrivacyInfo.xcprivacy for required reasons APIs and tracking declarations. Audit only; it does not edit the manifest.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to PrivacyInfo.xcprivacy. Defaults to the first one found."),
            ]
        ),
        SystemToolDefinition(
            name: "env_info",
            description: "Reports runtime facts from the live process: macOS version, CPU count, physical memory, hostname, and uptime.",
            action: "system.info",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: false, description: "Owning thread ID. Only used by the MCP server path."),
            ]
        ),
        SystemToolDefinition(
            name: "process_monitor_tool",
            description: "Monitors running processes with CPU and memory consumption from real ps output, with an optional name filter.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: false, description: "Absolute working directory for the terminal. Defaults to the thread working directory."),
                SystemToolParameter(name: "filter", type: "string", required: false, description: "Substring filter for process names."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum processes to return."),
            ]
        ),
        SystemToolDefinition(
            name: "disk_space_analyzer",
            description: "Checks disk usage with real df and du output for the workspace and a chosen path.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Path to measure, relative to the working directory. Defaults to the workspace root."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Command timeout in seconds."),
            ]
        ),
        SystemToolDefinition(
            name: "environment_variable_manager",
            description: "Lists and reads process environment variables from the live process. The process environment cannot be mutated by a tool; set is refused with an honest error.",
            action: "system.env",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action: list or get."),
                SystemToolParameter(name: "key", type: "string", required: false, description: "Variable name for get."),
            ]
        ),
        SystemToolDefinition(
            name: "clipboard_manager_tool",
            description: "Reads, writes, or clears the macOS system clipboard through NSPasteboard.",
            action: "system.clipboard",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action: read, write, or clear."),
                SystemToolParameter(name: "text", type: "string", required: false, description: "Text for write."),
                SystemToolParameter(name: "threadId", type: "string", required: false, description: "Owning thread ID. Only used by the MCP server path."),
            ]
        ),
        SystemToolDefinition(
            name: "system_notification_tool",
            description: "Posts a macOS user notification for task completions and build events through UNUserNotificationCenter.",
            action: "system.notify",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "title", type: "string", required: true, description: "Notification title."),
                SystemToolParameter(name: "body", type: "string", required: false, description: "Notification body."),
                SystemToolParameter(name: "threadId", type: "string", required: false, description: "Owning thread ID. Only used by the MCP server path."),
            ]
        ),
        SystemToolDefinition(
            name: "use_system",
            description: "Native macOS system diagnostics plus one authorized user-level mutation. Diagnostics use fixed commands only; user_defaults_write requires confirm and verifies by read-back.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "operation", type: "string", required: true, description: "Operation: system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read, or user_defaults_write."),
                SystemToolParameter(name: "cwd", type: "string", required: false, description: "Absolute working directory for disk_info. Defaults to the thread working directory."),
                SystemToolParameter(name: "filter", type: "string", required: false, description: "Name filter for process_list."),
                SystemToolParameter(name: "interface", type: "string", required: false, description: "Interface name for network_interfaces."),
                SystemToolParameter(name: "host", type: "string", required: false, description: "Host for connectivity."),
                SystemToolParameter(name: "port", type: "integer", required: false, description: "Port for connectivity."),
                SystemToolParameter(name: "minutes", type: "integer", required: false, description: "Look-back minutes for system_log."),
                SystemToolParameter(name: "predicate", type: "string", required: false, description: "Log predicate for system_log."),
                SystemToolParameter(name: "sysctlName", type: "string", required: false, description: "Allowlisted sysctl name for config_read."),
                SystemToolParameter(name: "domain", type: "string", required: false, description: "Defaults domain for user_defaults_write."),
                SystemToolParameter(name: "key", type: "string", required: false, description: "Defaults key for user_defaults_write."),
                SystemToolParameter(name: "value", type: "string", required: false, description: "Scalar value for user_defaults_write."),
                SystemToolParameter(name: "valueType", type: "string", required: false, description: "Value type for user_defaults_write: string, bool, or int. Defaults to string."),
                SystemToolParameter(name: "confirm", type: "boolean", required: false, description: "Must be true for user_defaults_write."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Command timeout in seconds."),
            ]
        ),
        SystemToolDefinition(
            name: "search_skills",
            description: "Searches the bundled SystemAssets index of shipped guidance documents by title, filename, section, and text. It searches only that bundled index, never an external skills library.",
            action: "system.skills",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "query", type: "string", required: true, description: "Search query."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum results. Defaults to 8, at most 20."),
            ]
        ),
        SystemToolDefinition(
            name: "plan-AskUser",
            description: "Lists pending provider questions for a thread and submits answers to them. It does not present a new question to the user and does not suspend the turn; no 300 second suspension is wired.",
            action: "agent.pending",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "requestId", type: "string", required: false, description: "Pending request ID to answer. Omit to list pending questions."),
                SystemToolParameter(name: "answers", type: "array", required: false, description: "Answers for requestId, each with questionId and an answers array of strings."),
            ]
        ),
        SystemToolDefinition(
            name: "tool_capability_lookup",
            description: "Live registry lookup: description, action, channel, and parameters of any registered system tool.",
            action: "system.lookup",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "tool", type: "string", required: true, description: "Tool name to look up."),
            ]
        ),
        SystemToolDefinition(
            name: "preflight_checks",
            description: "Runs environment checks before a build: workspace writable, Xcode tools present, disk space, and artifact storage.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
            ]
        ),
        SystemToolDefinition(
            name: "session_progress_report",
            description: "Reports engineering phases from agent_notes.md with worker status and the last agent-notes save time.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "threadId", type: "string", required: false, description: "Parent thread ID to include worker status for."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to agent_notes.md. Defaults to .assist_temp/artifacts/agent_notes.md."),
            ]
        ),
        SystemToolDefinition(
            name: "manage_memory",
            description: "Manages entries in the SQLite agent memory store: store, edit, append, delete, clear, or list keys in a scope. There are no sections and no UserMemory.md file.",
            action: "memory.store",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action: store, edit, append, delete, clear, or list."),
                SystemToolParameter(name: "key", type: "string", required: false, description: "Memory key for store, edit, append, and delete."),
                SystemToolParameter(name: "value", type: "string", required: false, description: "Value for store, edit, and append."),
                SystemToolParameter(name: "scope", type: "string", required: false, description: "Memory scope."),
                SystemToolParameter(name: "confirm", type: "boolean", required: false, description: "Must be true for clear."),
            ]
        ),
        SystemToolDefinition(
            name: "fetch_documentation",
            description: "Retrieves real Apple Developer documentation pages from developer.apple.com by URL, search query, or framework landing page. Returns raw page text; it does not fabricate signatures or availability.",
            action: "web.fetch",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID. Only used by the MCP server path."),
                SystemToolParameter(name: "query", type: "string", required: false, description: "Documentation search query."),
                SystemToolParameter(name: "url", type: "string", required: false, description: "Documentation URL on developer.apple.com."),
                SystemToolParameter(name: "framework", type: "string", required: false, description: "Framework name to open its documentation landing page."),
            ]
        ),
        SystemToolDefinition(
            name: "external_resource_gateway",
            description: "Performs an HTTPS-only GET of a JSON API and returns the parsed JSON. Non-2xx responses fail; 30 second timeout.",
            action: "web.fetch",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID. Only used by the MCP server path."),
                SystemToolParameter(name: "url", type: "string", required: true, description: "HTTPS JSON API URL."),
            ]
        ),
        SystemToolDefinition(
            name: "read_url_content",
            description: "Fetches HTTPS URL content as text with status and content type. Non-2xx responses fail; 30 second timeout.",
            action: "web.fetch",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID. Only used by the MCP server path."),
                SystemToolParameter(name: "url", type: "string", required: true, description: "HTTPS URL to fetch."),
                SystemToolParameter(name: "maxChars", type: "integer", required: false, description: "Maximum characters to return. Defaults to 8000."),
            ]
        ),
        SystemToolDefinition(
            name: "github_repo",
            description: "Reads real GitHub repositories through the gh CLI: repository info, file listings, file contents, trees, code search, and tarball download. Read-only against the remote.",
            action: "github.repo",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "operation", type: "string", required: true, description: "Operation: repository_info, list_files, get_file, get_directory, get_tree, search_code, or fetch_repository."),
                SystemToolParameter(name: "owner", type: "string", required: false, description: "Repository owner."),
                SystemToolParameter(name: "repo", type: "string", required: false, description: "Repository name."),
                SystemToolParameter(name: "url", type: "string", required: false, description: "Repository URL, used when owner and repo are omitted."),
                SystemToolParameter(name: "ref", type: "string", required: false, description: "Branch, tag, or commit. Defaults to the default branch."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File or directory path inside the repository."),
                SystemToolParameter(name: "query", type: "string", required: false, description: "Code search query for search_code."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Command timeout in seconds."),
            ]
        ),
        SystemToolDefinition(
            name: "use_app",
            description: "Native macOS application interaction through the real computer-use tools. Dispatches only the 20 real actions and errors honestly on activate, close_application, select_window, get_focused_element, select_all, copy, paste, wait_for_element, and wait_for_window, which have no engine tool.",
            action: "computer_use.request",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "action", type: "string", required: true, description: "Action to perform, for example list_applications, launch, click, type_text, or verify."),
                SystemToolParameter(name: "app_identifier", type: "string", required: false, description: "Bundle ID for launch."),
                SystemToolParameter(name: "app_name", type: "string", required: false, description: "Application name for inspect_application."),
                SystemToolParameter(name: "pid", type: "integer", required: false, description: "Process ID of the running app."),
                SystemToolParameter(name: "window_id", type: "integer", required: false, description: "Window ID from list_windows or get_desktop_state."),
                SystemToolParameter(name: "element_token", type: "string", required: false, description: "Element token from a fresh get_window_state observation."),
                SystemToolParameter(name: "observation", type: "string", required: false, description: "Observation ID from a fresh get_window_state screenshot."),
                SystemToolParameter(name: "x", type: "number", required: false, description: "Point x in window points."),
                SystemToolParameter(name: "y", type: "number", required: false, description: "Point y in window points."),
                SystemToolParameter(name: "from_x", type: "number", required: false, description: "Drag start x in window points."),
                SystemToolParameter(name: "from_y", type: "number", required: false, description: "Drag start y in window points."),
                SystemToolParameter(name: "to_x", type: "number", required: false, description: "Drag end x in window points."),
                SystemToolParameter(name: "to_y", type: "number", required: false, description: "Drag end y in window points."),
                SystemToolParameter(name: "text", type: "string", required: false, description: "Text to type, set, or find."),
                SystemToolParameter(name: "key", type: "string", required: false, description: "Key to press: enter, escape, tab, backspace, left, right, up, or down."),
                SystemToolParameter(name: "keys", type: "array", required: false, description: "Modifiers then one key for press_shortcut, for example cmd shift t."),
                SystemToolParameter(name: "direction", type: "string", required: false, description: "Scroll direction: up, down, left, or right."),
                SystemToolParameter(name: "amount", type: "integer", required: false, description: "Scroll amount, 1 to 50. Defaults to 3."),
                SystemToolParameter(name: "bundle_id", type: "string", required: false, description: "App bundle ID for launch, for example com.apple.TextEdit."),
                SystemToolParameter(name: "path", type: "array", required: false, description: "Menu path for select_menu, for example File New Window."),
                SystemToolParameter(name: "confirm", type: "boolean", required: false, description: "Confirmation for destructive actions."),
            ]
        ),
        SystemToolDefinition(
            name: "derived_data_locate",
            description: "Locates Xcode DerivedData directories with sizes and file counts.",
            action: "system.info",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "path", type: "string", required: false, description: "DerivedData directory to inspect. Defaults to ~/Library/Developer/Xcode/DerivedData."),
                SystemToolParameter(name: "limit", type: "integer", required: false, description: "Maximum directories to return."),
                SystemToolParameter(name: "threadId", type: "string", required: false, description: "Owning thread ID. Only used by the MCP server path."),
            ]
        ),
        SystemToolDefinition(
            name: "build_system_detect",
            description: "Detects build systems in the workspace: xcworkspace and xcodeproj, SwiftPM, CocoaPods, Carthage, Tuist, xcodegen, Bazel, and CMake.",
            action: "workspace.files",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Directory to inspect, relative to the working directory. Defaults to the whole workspace."),
            ]
        ),
        SystemToolDefinition(
            name: "svg_to_png",
            description: "Convert an SVG file to PNG with the sips CLI and return its real output. Output is PNG only; complex SVGs can distort at small sizes.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "SVG file path relative to the working directory."),
                SystemToolParameter(name: "output", type: "string", required: false, description: "Output path relative to the working directory. Defaults to the input path with a .png extension."),
                SystemToolParameter(name: "width", type: "integer", required: false, description: "Target width in pixels, 1 to 4096. With height, resamples to both dimensions; alone, scales to a maximum pixel size."),
                SystemToolParameter(name: "height", type: "integer", required: false, description: "Target height in pixels, 1 to 4096. With width, resamples to both dimensions; alone, scales to a maximum pixel size."),
            ]
        ),
        SystemToolDefinition(
            name: "intel_generate_tests",
            description: "Emit one test stub per regex-extracted symbol from a Swift source file or directory into a test file; template stubs from regex-extracted symbols, not LLM-written tests. Refuses to overwrite an existing file unless overwrite is true.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Swift source file or directory relative to the working directory."),
                SystemToolParameter(name: "testPath", type: "string", required: true, description: "Test file path relative to the working directory."),
                SystemToolParameter(name: "module", type: "string", required: false, description: "Module name for the @testable import. Defaults to the project directory name."),
                SystemToolParameter(name: "overwrite", type: "boolean", required: false, description: "Allow overwriting an existing test file. Defaults to false."),
            ]
        ),
        SystemToolDefinition(
            name: "search_web",
            description: "Search the web with unofficial DuckDuckGo HTML scraping, no search API; results may be empty if DDG blocks or changes markup; failure is reported, never faked.",
            action: "web.fetch",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID. Only used by the MCP server path."),
                SystemToolParameter(name: "query", type: "string", required: true, description: "Search query."),
                SystemToolParameter(name: "maxResults", type: "integer", required: false, description: "Maximum results to return, 1 to 25. Defaults to 10."),
            ]
        ),
        SystemToolDefinition(
            name: "reverse_analyze",
            description: "Inspect a binary or database as a composition of named CLI inspections: file, otool, and codesign artifact facts, otool -tV disassembly, xcrun swift-demangle, or sqlite3 .schema; it is a composition of the named CLI inspections, not the REA subsystem. REA evidence IDs and confidence scores are unavailable.",
            action: "terminal.create",
            channel: .engine,
            parameters: [
                SystemToolParameter(name: "threadId", type: "string", required: true, description: "Owning thread ID."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "File to inspect, relative to the working directory. Required for artifact, disassembly, and sqlite_schema."),
                SystemToolParameter(name: "inspection", type: "string", required: true, description: "Inspection: artifact, disassembly, demangle, or sqlite_schema."),
                SystemToolParameter(name: "symbol", type: "string", required: false, description: "Mangled Swift symbol name for the demangle inspection."),
                SystemToolParameter(name: "cwd", type: "string", required: false, description: "Absolute working directory. Only used to read plist facts when path ends in .plist."),
                SystemToolParameter(name: "timeoutSeconds", type: "integer", required: false, description: "Command timeout in seconds. Defaults to 60."),
            ]
        ),
        SystemToolDefinition(
            name: "report_to_user",
            description: "Record a completion summary in the session-notes artifact and mark the turn complete; the chat reply itself is the actual delivery to the user; the tool records the summary and marks the turn complete, it does not deliver out-of-band.",
            action: "workspace.write_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "summary", type: "string", required: true, description: "Completion summary to record."),
                SystemToolParameter(name: "path", type: "string", required: false, description: "Relative path to agent_notes.md. Defaults to .assist_temp/artifacts/agent_notes.md."),
                SystemToolParameter(name: "title", type: "string", required: false, description: "Section title for the record. Defaults to Completion."),
            ]
        ),
        SystemToolDefinition(
            name: "intel_explain_code",
            description: "Overview of one source file from regex scans: line counts, public declarations, and doc comments; structural overview from regex scans, not an LLM explanation.",
            action: "workspace.read_file",
            channel: .desktop,
            parameters: [
                SystemToolParameter(name: "cwd", type: "string", required: true, description: "Absolute working directory."),
                SystemToolParameter(name: "path", type: "string", required: true, description: "Source file relative to the working directory."),
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
        case "framework_linker_auditor", "string_catalog_migrator", "symbol_reference_graph",
            "podfile_inspector", "carthage_cartfile_inspector", "package_manifest_read",
            "package_dependency_add", "asset_catalog_list", "asset_image_add",
            "strings_localization", "localization_audit", "localize_app",
            "asset_catalog_manager", "localization_manager", "entitlements_manager",
            "colorset_builder", "project_entitlements", "project_info_plist",
            "project_capabilities", "entry_points_discover", "repo_overview",
            "project_structure_map", "recent_changes", "readme_locate",
            "dependency_licenses", "stale_files_report", "file_type_breakdown",
            "empty_dirs_find", "symlink_audit", "executable_files_scan",
            "dir_size_report", "image_asset_size_report", "bundle_resource_auditor",
            "core_data_model_inspector", "swift_data_schema_auditor",
            "privacy_manifest_auditor", "derived_data_locate", "build_system_detect":
            return try await Self.runG6Tool(tool: name, arguments: arguments, runtime: runtime)
        case "spm_dependency_tree":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let packageDir = Self.g6JoinPath(cwd: cwd, path: optionalString(arguments, "path"))
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 300
            let (exitCode, output) = try await Self.g6TerminalJSON(tool: name, threadId: threadId, cwd: packageDir, command: "swift package show-dependencies --format json", timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "swift", exitCode: exitCode, output: output)
            if exitCode != 0 {
                return .object([
                    "dependencies": .null,
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            }
            return .object([
                "dependencies": try Self.g3JSONValue(output, tool: name),
                "exitCode": .int(Int64(exitCode)),
            ])
        case "package_manifest_validate":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let packageDir = Self.g6JoinPath(cwd: cwd, path: optionalString(arguments, "path"))
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 300
            let (exitCode, output) = try await Self.g6TerminalJSON(tool: name, threadId: threadId, cwd: packageDir, command: "swift package dump-package", timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "swift", exitCode: exitCode, output: output)
            if exitCode != 0 {
                return .object([
                    "valid": .bool(false),
                    "name": .null,
                    "targetCount": .int(0),
                    "exitCode": .int(Int64(exitCode)),
                    "output": .string(output),
                ])
            }
            let dumped = try Self.g3JSONValue(output, tool: name)
            let targetCount = dumped["targets"]?.arrayValue?.count ?? 0
            return .object([
                "valid": .bool(true),
                "name": dumped["name"] ?? .null,
                "targetCount": .int(Int64(targetCount)),
                "exitCode": .int(Int64(exitCode)),
            ])
        case "package_dependency_audit":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let packageDir = Self.g6JoinPath(cwd: cwd, path: optionalString(arguments, "path"))
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 300
            let manifestDoc = try await runtime.readWorkspaceFile(cwd: packageDir, path: "Package.swift")
            let manifest = Self.g6ParseManifest(manifestDoc.content)
            var resolvedPins: [[String: String]] = []
            if let resolvedDoc = try? await runtime.readWorkspaceFile(cwd: packageDir, path: "Package.resolved") {
                resolvedPins = Self.g6ParseResolved(resolvedDoc.content)
            }
            let (exitCode, output) = try await Self.g6TerminalJSON(tool: name, threadId: threadId, cwd: packageDir, command: "swift package show-dependencies --format json", timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "swift", exitCode: exitCode, output: output)
            var shown: [String] = []
            if exitCode == 0, let shownValue = try? Self.g3JSONValue(output, tool: name) {
                shown = Self.g6ShowDependenciesNames(shownValue)
            }
            return Self.g6DependencyAudit(tool: name, manifest: manifest, resolvedPins: resolvedPins, shown: shown, exitCode: exitCode, output: output)
        case "project_signing":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let pbxproj = try await Self.g5ResolvePbxproj(tool: name, cwd: cwd, path: optionalString(arguments, "path"), runtime: runtime)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: pbxproj)
            var object = Self.g6SigningFromPbxproj(tool: name, path: pbxproj, content: document.content)
            let entries = try await runtime.listWorkspaceFiles(cwd: cwd, query: ".mobileprovision", limit: 100)
            let profiles = entries.filter { !$0.isDirectory && ($0.path.hasSuffix(".mobileprovision") || $0.path.hasSuffix(".provisionprofile")) }.map { $0.path }
            if case .object(var dict) = object {
                dict["provisioningProfiles"] = .array(profiles.map { .string($0) })
                object = .object(dict)
            }
            if let scheme = optionalString(arguments, "scheme") {
                try Self.g3Identifier(scheme, field: "scheme", tool: name)
                let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 120
                let (exitCode, output) = try await Self.g6TerminalJSON(tool: name, threadId: threadId, cwd: cwd, command: "xcodebuild -showBuildSettings -scheme " + Self.shellQuoted(scheme), timeoutSeconds: timeoutSeconds, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcodebuild", exitCode: exitCode, output: output)
                if case .object(var dict) = object {
                    dict["showBuildSettings"] = Self.g6BuildSettingsJSON(output)
                    dict["showBuildSettingsExitCode"] = .int(Int64(exitCode))
                    object = .object(dict)
                }
            }
            return object
        case "icon_generator_tool":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let source = try requiredString(arguments, "source", tool: name)
            let output = try requiredString(arguments, "output", tool: name)
            let platform = optionalString(arguments, "platform") ?? "ios"
            guard ["ios", "macos", "watchos"].contains(platform) else {
                throw SystemToolError.executionFailed(tool: name, message: "icon_generator_tool platform must be ios, macos, or watchos.")
            }
            try Self.validateRelativePath(source, tool: name)
            try Self.validateRelativePath(output, tool: name)
            guard output.hasSuffix(".appiconset") else {
                throw SystemToolError.executionFailed(tool: name, message: "icon_generator_tool output must end in .appiconset.")
            }
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 300
            try await runtime.createWorkspaceDirectory(cwd: cwd, path: output)
            let sizes = Self.g6IconSizes(platform: platform)
            var generated: [[String: JSONValue]] = []
            for size in sizes {
                let fileName = "icon-\(size.pixels).png"
                let destination = output + "/" + fileName
                _ = try await Self.runShellCommand(tool: name, threadId: threadId, cwd: cwd, command: "sips -Z \(size.pixels) " + Self.shellQuoted(source) + " --out " + Self.shellQuoted(destination), timeoutSeconds: timeoutSeconds, runtime: runtime)
                generated.append([
                    "size": .string(size.label),
                    "idiom": .string(size.idiom),
                    "scale": .string(size.scale),
                    "filename": .string(fileName),
                    "pixels": .int(Int64(size.pixels)),
                ])
            }
            let contents = Self.g6AppIconContents(platform: platform, generated: generated)
            guard let contentsData = try? JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]) else {
                throw SystemToolError.executionFailed(tool: name, message: "Could not serialize AppIcon Contents.json.")
            }
            try Self.writeWorkspaceBytes(cwd: cwd, path: output + "/Contents.json", data: contentsData, tool: name)
            let listed = try await runtime.readWorkspaceDirectory(cwd: cwd, path: output, recursive: false)
            return .object([
                "platform": .string(platform),
                "output": .string(output),
                "icons": .array(generated),
                "iconCount": .int(Int64(generated.count)),
                "filesPresent": .int(Int64(listed.filter { !$0.isDirectory }.count)),
            ])
        case "process_monitor_tool":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 60
            let (exitCode, output) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["/bin/ps", "-ax", "-o", "pid=,pcpu=,pmem=,comm="], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: name, cli: "ps", exitCode: exitCode, output: output)
            let filter = optionalString(arguments, "filter")
            let limit = min(max(optionalInt(arguments, "limit") ?? 50, 1), 500)
            let processes = Self.g6ParsePs(output, filter: filter, limit: limit)
            return .object([
                "processes": .array(processes),
                "count": .int(Int64(processes.count)),
                "exitCode": .int(Int64(exitCode)),
            ])
        case "disk_space_analyzer":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? "."
            try Self.validateRelativePath(path, tool: name)
            let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 60
            let dfOutput = try await Self.runShellCommand(tool: name, threadId: threadId, cwd: cwd, command: "df -k " + Self.shellQuoted(path), timeoutSeconds: timeoutSeconds, runtime: runtime)
            let duOutput = try await Self.runShellCommand(tool: name, threadId: threadId, cwd: cwd, command: "du -sk " + Self.shellQuoted(path), timeoutSeconds: timeoutSeconds, runtime: runtime)
            return Self.g6DiskSpace(tool: name, path: path, dfOutput: dfOutput, duOutput: duOutput)
        case "use_system":
            return try await Self.runG6UseSystem(tool: name, arguments: arguments, runtime: runtime)
        case "env_info":
            return Self.g6EnvInfo(tool: name)
        case "environment_variable_manager":
            let action = try requiredString(arguments, "action", tool: name)
            switch action {
            case "list":
                let keys = ProcessInfo.processInfo.environment.keys.sorted()
                return .object([
                    "action": .string(action),
                    "keys": .array(keys.map { .string($0) }),
                    "count": .int(Int64(keys.count)),
                ])
            case "get":
                let key = try requiredString(arguments, "key", tool: name)
                if let value = ProcessInfo.processInfo.environment[key] {
                    return .object([
                        "action": .string(action),
                        "key": .string(key),
                        "found": .bool(true),
                        "value": .string(value),
                    ])
                }
                return .object([
                    "action": .string(action),
                    "key": .string(key),
                    "found": .bool(false),
                    "value": .null,
                ])
            default:
                throw SystemToolError.executionFailed(tool: name, message: "environment_variable_manager action must be list or get. The process environment cannot be mutated by a tool; use a terminal export instead.")
            }
        case "clipboard_manager_tool":
            let action = try requiredString(arguments, "action", tool: name)
            let pasteboard = NSPasteboard.general
            switch action {
            case "read":
                let text = pasteboard.string(forType: .string)
                return .object([
                    "action": .string(action),
                    "hasText": .bool(text != nil),
                    "text": text.map { .string($0) } ?? .null,
                ])
            case "write":
                let text = try requiredString(arguments, "text", tool: name)
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                return .object([
                    "action": .string(action),
                    "written": .bool(true),
                    "characters": .int(Int64(text.count)),
                ])
            case "clear":
                pasteboard.clearContents()
                return .object([
                    "action": .string(action),
                    "cleared": .bool(true),
                ])
            default:
                throw SystemToolError.executionFailed(tool: name, message: "clipboard_manager_tool action must be read, write, or clear.")
            }
        case "system_notification_tool":
            let title = try requiredString(arguments, "title", tool: name)
            let body = optionalString(arguments, "body") ?? ""
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let identifier = "agents-tool-\(UUID().uuidString)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            return .object([
                "posted": .bool(true),
                "identifier": .string(identifier),
                "title": .string(title),
                "note": .string("Delivery requires notification authorization, granted at app launch."),
            ])
        case "tool_capability_lookup":
            let toolName = try requiredString(arguments, "tool", tool: name)
            guard let found = Self.definition(named: toolName, for: .system) else {
                throw SystemToolError.unknownTool(toolName)
            }
            return .object([
                "name": .string(found.name),
                "description": .string(found.description),
                "action": .string(found.action),
                "channel": .string(found.channel.rawValue),
                "parameters": .array(found.parameters.map { parameter in
                    .object([
                        "name": .string(parameter.name),
                        "type": .string(parameter.type),
                        "required": .bool(parameter.required),
                        "description": .string(parameter.description),
                    ])
                }),
            ])
        case "search_skills":
            let query = try requiredString(arguments, "query", tool: name)
            let limit = min(max(optionalInt(arguments, "limit") ?? 8, 1), 20)
            let results = SystemAssetManager.shared.search(query, limit: limit)
            return .object([
                "query": .string(query),
                "searched": .string("bundled SystemAssets index"),
                "documentCount": .int(Int64(SystemAssetManager.shared.documentCount)),
                "results": .array(results.map { result in
                    .object([
                        "documentID": .string(result.documentID),
                        "fileName": .string(result.fileName),
                        "title": .string(result.title),
                        "sectionHeading": .string(result.sectionHeading),
                        "headingPath": .array(result.headingPath.map { .string($0) }),
                        "text": .string(String(result.text.prefix(2000))),
                        "truncated": .bool(result.text.count > 2000),
                        "score": .int(Int64(result.score)),
                        "reason": .string(result.reason),
                    ])
                }),
            ])
        case "manage_memory":
            let action = try requiredString(arguments, "action", tool: name)
            switch action {
            case "store", "edit":
                let key = try requiredString(arguments, "key", tool: name)
                let value = try requiredString(arguments, "value", tool: name)
                let stored = try await runtime.memoryStore(key: key, value: value, scope: optionalString(arguments, "scope"))
                if case .object(var dict) = stored {
                    dict["action"] = .string(action)
                    return .object(dict)
                }
                return stored
            case "append":
                let key = try requiredString(arguments, "key", tool: name)
                let value = try requiredString(arguments, "value", tool: name)
                let scope = optionalString(arguments, "scope")
                let existing = try await runtime.memoryRetrieve(key: key, scope: scope)
                let previous = existing["value"]?.stringValue ?? ""
                let combined = previous.isEmpty ? value : previous + "\n" + value
                let stored = try await runtime.memoryStore(key: key, value: combined, scope: scope)
                if case .object(var dict) = stored {
                    dict["action"] = .string(action)
                    return .object(dict)
                }
                return stored
            case "delete":
                let key = try requiredString(arguments, "key", tool: name)
                return try await runtime.memoryDelete(key: key, scope: optionalString(arguments, "scope"))
            case "clear":
                let scope = try requiredString(arguments, "scope", tool: name)
                try Self.requireConfirm(arguments, tool: name, message: "manage_memory clear is irreversible; pass confirm=true.")
                return try await runtime.memoryClear(scope: scope, confirm: true)
            case "list":
                let entries = try await runtime.memoryList(scope: optionalString(arguments, "scope"), query: optionalString(arguments, "query"), limit: optionalInt(arguments, "limit") ?? 200)
                return .array(entries.map { entry in
                    .object([
                        "key": .string(entry.key),
                        "scope": .string(entry.scope),
                        "value": .string(entry.value),
                        "updatedAt": .double(entry.updatedAt),
                    ])
                })
            default:
                throw SystemToolError.executionFailed(tool: name, message: "manage_memory action must be store, edit, append, delete, clear, or list.")
            }
        case "plan-AskUser":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            guard let requestId = optionalString(arguments, "requestId") else {
                let pending = try await runtime.engineRPC(method: "agent.pending", params: ["threadId": .string(threadId)])
                return .object([
                    "threadId": .string(threadId),
                    "pending": pending,
                    "note": .string("Lists pending provider questions. This tool does not present a new question and does not suspend the turn."),
                ])
            }
            guard let rawAnswers = arguments["answers"]?.arrayValue, !rawAnswers.isEmpty else {
                throw SystemToolError.missingArgument(tool: name, argument: "answers")
            }
            var answersObject: [String: JSONValue] = [:]
            for raw in rawAnswers {
                guard let questionId = raw["questionId"]?.stringValue, !questionId.isEmpty else {
                    throw SystemToolError.missingArgument(tool: name, argument: "questionId")
                }
                guard let values = raw["answers"]?.arrayValue, !values.isEmpty, values.allSatisfy({ $0.stringValue?.isEmpty == false }) else {
                    throw SystemToolError.missingArgument(tool: name, argument: "answers")
                }
                answersObject[questionId] = .object(["answers": .array(values)])
            }
            return try await runtime.engineRPC(method: "agent.answer", params: [
                "threadId": .string(threadId),
                "requestId": .string(requestId),
                "answers": .object(answersObject),
            ])
        case "use_app":
            return try await Self.runG6UseApp(tool: name, arguments: arguments, runtime: runtime)
        case "preflight_checks":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            return try await Self.runG6Preflight(tool: name, threadId: threadId, cwd: cwd, runtime: runtime)
        case "session_progress_report":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = optionalString(arguments, "path") ?? ".assist_temp/artifacts/agent_notes.md"
            try Self.validateRelativePath(path, tool: name)
            var phases: [[String: JSONValue]] = []
            var failures: [String] = []
            var lastSave: JSONValue = .null
            var found = false
            if let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: path) {
                found = true
                var current: String?
                var summary: [String] = []
                for line in Self.g5Lines(document.content) {
                    if line.hasPrefix("## ") {
                        if let title = current {
                            phases.append(["title": .string(title), "summary": .string(summary.joined(separator: " "))])
                        }
                        current = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                        summary = []
                    } else if current != nil {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty, summary.count < 3 {
                            summary.append(trimmed)
                        }
                        if trimmed.localizedCaseInsensitiveContains("fail") && failures.count < 20 {
                            failures.append(trimmed)
                        }
                    }
                }
                if let title = current {
                    phases.append(["title": .string(title), "summary": .string(summary.joined(separator: " "))])
                }
            }
            if let entries = try? await runtime.listWorkspaceFiles(cwd: cwd, query: "agent_notes.md", limit: 5),
               let entry = entries.first(where: { $0.path == path }), let modified = entry.modifiedAt {
                lastSave = .double(modified)
            }
            var workers: [JSONValue] = []
            if let threadId = optionalString(arguments, "threadId") {
                if let listed = try? await runtime.listWorkers(parentThreadId: threadId) {
                    workers = listed.map { workerJSON($0) }
                }
            }
            return .object([
                "found": .bool(found),
                "path": .string(path),
                "phases": .array(phases),
                "failures": .array(failures.map { .string($0) }),
                "lastAgentNotesSave": lastSave,
                "workers": .array(workers),
            ])
        case "fetch_documentation":
            _ = try requiredString(arguments, "threadId", tool: name)
            let url: URL
            if let given = optionalString(arguments, "url"), !given.isEmpty {
                guard let parsed = URL(string: given), parsed.scheme == "https", parsed.host == "developer.apple.com" else {
                    throw SystemToolError.executionFailed(tool: name, message: "fetch_documentation url must be an https URL on developer.apple.com.")
                }
                url = parsed
            } else if let query = optionalString(arguments, "query"), !query.isEmpty {
                guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let built = URL(string: "https://developer.apple.com/search/?q=" + encoded) else {
                    throw SystemToolError.executionFailed(tool: name, message: "Could not build a documentation search URL.")
                }
                url = built
            } else if let framework = optionalString(arguments, "framework"), !framework.isEmpty {
                guard framework.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" }),
                      let built = URL(string: "https://developer.apple.com/documentation/" + framework.lowercased() + "/") else {
                    throw SystemToolError.executionFailed(tool: name, message: "fetch_documentation framework must use only letters, digits, or underscore.")
                }
                url = built
            } else {
                throw SystemToolError.missingArgument(tool: name, argument: "query")
            }
            let fetched = try await Self.g6FetchURL(url, timeoutSeconds: 30, tool: name)
            return .object([
                "url": .string(url.absoluteString),
                "statusCode": .int(Int64(fetched.statusCode)),
                "contentType": .string(fetched.contentType),
                "title": fetched.title.map { .string($0) } ?? .null,
                "text": .string(String(fetched.text.prefix(8000))),
                "truncated": .bool(fetched.text.count > 8000),
            ])
        case "external_resource_gateway":
            _ = try requiredString(arguments, "threadId", tool: name)
            let urlString = try requiredString(arguments, "url", tool: name)
            guard let url = URL(string: urlString), url.scheme == "https", url.host != nil else {
                throw SystemToolError.executionFailed(tool: name, message: "external_resource_gateway url must be an https URL.")
            }
            let fetched = try await Self.g6FetchURL(url, timeoutSeconds: 30, tool: name)
            guard let data = fetched.text.data(using: .utf8) else {
                throw SystemToolError.executionFailed(tool: name, message: "Response was not valid UTF-8.")
            }
            let value: JSONValue
            do {
                value = try JSONDecoder().decode(JSONValue.self, from: data)
            } catch {
                throw SystemToolError.executionFailed(tool: name, message: "Response was not JSON: \(error.localizedDescription)")
            }
            return .object([
                "url": .string(url.absoluteString),
                "statusCode": .int(Int64(fetched.statusCode)),
                "value": value,
            ])
        case "read_url_content":
            _ = try requiredString(arguments, "threadId", tool: name)
            let urlString = try requiredString(arguments, "url", tool: name)
            guard let url = URL(string: urlString), url.scheme == "https", url.host != nil else {
                throw SystemToolError.executionFailed(tool: name, message: "read_url_content url must be an https URL.")
            }
            let maxChars = min(max(optionalInt(arguments, "maxChars") ?? 8000, 1), 100000)
            let fetched = try await Self.g6FetchURL(url, timeoutSeconds: 30, tool: name)
            return .object([
                "url": .string(url.absoluteString),
                "statusCode": .int(Int64(fetched.statusCode)),
                "contentType": .string(fetched.contentType),
                "content": .string(String(fetched.text.prefix(maxChars))),
                "truncated": .bool(fetched.text.count > maxChars),
            ])
        case "github_repo":
            return try await Self.runG6GitHubRepo(tool: name, arguments: arguments, runtime: runtime)
        case "search_symbol", "dependency_graph", "source_graph_builder", "semantic_query_engine", "code_summary",
            "code_lint", "complexity_analysis", "autonomous_review_engine", "runtime_diagnostics_engine",
            "code_metrics_analyzer", "memory_leak_detector", "dead_code_eliminator", "dead_code_scan",
            "duplicate_code_scan", "todo_scan", "todo_fixme_scanner", "license_header_check", "api_surface_extract",
            "access_level_audit", "concurrency_audit", "swift_concurrency_analyzer", "swift_migration_advisor",
            "security_audit_scanner", "secrets_scan", "network_security_auditor", "permissions_audit",
            "accessibility_audit", "accessibility_audit_scanner", "interface_simulator", "docstring_generator",
            "code_snippet_manager", "unused_imports_detector", "force_unwrap_scan", "string_literal_audit",
            "comment_density_report", "function_size_report", "call_hierarchy", "type_hierarchy",
            "protocol_conformance_list", "import_graph", "change_impact_estimate", "conflict_marker_scan",
            "build_log_analyze", "crash_log_parse", "deprecation_usage_scan", "info_plist_audit",
            "api_endpoint_audit", "color_usage_audit", "strings_file_validate", "entitlements_diff", "pbxproj_lint",
            "xctest_discovery", "build_settings_diff", "build_phase_scripts_list", "build_configuration_list",
            "target_dependencies_list", "target_source_list", "workspace_settings_read", "scheme_test_plan_list",
            "test_log_parse", "test_flaky_detect", "code_comment_extract", "api_docs_coverage",
            "markdown_link_check", "docs_index_build":

            return try await Self.runG5Tool(tool: name, arguments: arguments, runtime: runtime)
        case "svg_to_png":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            guard (path as NSString).pathExtension.lowercased() == "svg" else {
                throw SystemToolError.executionFailed(tool: tool, message: "svg_to_png path must end in .svg.")
            }
            let output = optionalString(arguments, "output") ?? Self.replacingExtension(path, with: "png")
            let width = optionalInt(arguments, "width")
            let height = optionalInt(arguments, "height")
            if let width {
                guard width >= 1, width <= 4096 else {
                    throw SystemToolError.executionFailed(tool: tool, message: "svg_to_png width must be 1 to 4096.")
                }
            }
            if let height {
                guard height >= 1, height <= 4096 else {
                    throw SystemToolError.executionFailed(tool: tool, message: "svg_to_png height must be 1 to 4096.")
                }
            }
            try Self.validateRelativePath(path, tool: name)
            try Self.validateRelativePath(output, tool: name)
            var svgCommand = "sips -s format png "
            if let width, let height {
                svgCommand += "--resampleHeightWidth \(height) \(width) "
            } else if let width {
                svgCommand += "-Z \(width) "
            } else if let height {
                svgCommand += "-Z \(height) "
            }
            svgCommand += Self.shellQuoted(path) + " --out " + Self.shellQuoted(output)
            let svgResult = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: cwd, command: svgCommand, timeoutSeconds: 120, runtime: runtime)
            return .object(["path": .string(path), "output": .string(output), "format": .string("png"), "width": width.map { .int(Int64($0)) } ?? .null, "height": height.map { .int(Int64($0)) } ?? .null, "result": .string(svgResult)])
        case "intel_generate_tests":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let testPath = try requiredString(arguments, "testPath", tool: name)
            let module = optionalString(arguments, "module") ?? URL(fileURLWithPath: ExternalEditorService.expandedPath(cwd)).lastPathComponent
            let overwrite = optionalBool(arguments, "overwrite") ?? false
            if !overwrite {
                try Self.assertFileAbsent(cwd: cwd, path: testPath, tool: name)
            }
            let testFileName = (testPath as NSString).lastPathComponent
            let suiteName = (testFileName as NSString).deletingPathExtension
            let suiteFirst = suiteName.unicodeScalars.first
            let suiteValidStart = suiteFirst.map { CharacterSet.letters.contains($0) || $0 == "_" } ?? false
            let suiteValidRest = suiteName.unicodeScalars.dropFirst().allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
            guard suiteValidStart, suiteValidRest else {
                throw SystemToolError.executionFailed(tool: tool, message: "Test file name must be a valid Swift identifier for test generation.")
            }
            var testSources: [String] = []
            if let entries = try? await runtime.readWorkspaceDirectory(cwd: cwd, path: path, recursive: true) {
                testSources = entries.filter { !$0.isDirectory && ($0.path as NSString).pathExtension == "swift" }.map { $0.path }
            } else {
                testSources = [path]
            }
            var testSymbols: [[String: JSONValue]] = []
            for file in testSources.sorted() {
                guard let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: file) else {
                    continue
                }
                testSymbols.append(contentsOf: Self.extractSymbols(document.content, path: file))
            }
            guard !testSymbols.isEmpty else {
                throw SystemToolError.executionFailed(tool: tool, message: "No symbols found in \(path); no test stubs were written.")
            }
            var stubLines: [String] = []
            stubLines.append("import Testing")
            stubLines.append("@testable import \(module)")
            stubLines.append("")
            stubLines.append("@Suite(\"\(suiteName)\")")
            stubLines.append("struct \(suiteName) {")
            var usedTestNames: Set<String> = []
            for symbol in testSymbols {
                let kind = symbol["kind"]?.stringValue ?? ""
                let symbolName = symbol["name"]?.stringValue ?? ""
                let symbolLine = symbol["line"]?.intValue ?? 0
                var testName = "test" + symbolName.prefix(1).uppercased() + String(symbolName.dropFirst())
                if usedTestNames.contains(testName) {
                    testName += "_\(symbolLine)"
                }
                usedTestNames.insert(testName)
                stubLines.append("    @Test(\"Stub for \(kind) \(symbolName)\")")
                stubLines.append("    func \(testName)() {")
                stubLines.append("        #expect(Bool(false), \"Replace this stub for \(kind) \(symbolName) with a real assertion.\")")
                stubLines.append("    }")
            }
            stubLines.append("}")
            stubLines.append("")
            try await runtime.writeWorkspaceFile(cwd: cwd, path: testPath, content: stubLines.joined(separator: "\n"))
            return .object(["path": .string(path), "testPath": .string(testPath), "symbols": .int(Int64(testSymbols.count)), "tests": .int(Int64(usedTestNames.count))])
        case "search_web":
            _ = try requiredString(arguments, "threadId", tool: name)
            let query = try requiredString(arguments, "query", tool: name)
            let maxResults = min(max(optionalInt(arguments, "maxResults") ?? 10, 1), 25)
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let searchURL = URL(string: "https://html.duckduckgo.com/html/?q=" + encoded) else {
                throw SystemToolError.executionFailed(tool: name, message: "Could not build a DuckDuckGo search URL.")
            }
            let fetched = try await Self.g6FetchURL(searchURL, timeoutSeconds: 30, tool: name)
            var results: [[String: JSONValue]] = []
            for match in Self.g5RegexMatches(pattern: "class=\"result__a\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>", text: fetched.text, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                guard match.1.count > 2, let href = match.1[1], let rawTitle = match.1[2] else {
                    continue
                }
                var link = href
                if let uddgStart = link.range(of: "uddg=") {
                    var encodedTarget = String(link[uddgStart.upperBound...])
                    if let amp = encodedTarget.firstIndex(of: "&") {
                        encodedTarget = String(encodedTarget[..<amp])
                    }
                    if let decoded = encodedTarget.removingPercentEncoding, !decoded.isEmpty {
                        link = decoded
                    }
                }
                if link.hasPrefix("//") {
                    link = "https:" + link
                }
                let plainTitle = rawTitle.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                results.append(["title": .string(plainTitle), "url": .string(link)])
                if results.count >= maxResults {
                    break
                }
            }
            return .object(["query": .string(query), "url": .string(searchURL.absoluteString), "statusCode": .int(Int64(fetched.statusCode)), "contentType": .string(fetched.contentType), "results": .array(results.map { .object($0) }), "count": .int(Int64(results.count))])
        case "reverse_analyze":
            let threadId = try requiredString(arguments, "threadId", tool: name)
            let inspection = try requiredString(arguments, "inspection", tool: name)
            let analyzeTimeout = optionalInt(arguments, "timeoutSeconds") ?? 60
            switch inspection {
            case "artifact":
                let path = try requiredString(arguments, "path", tool: name)
                try Self.validateRelativePath(path, tool: name)
                guard try await Self.g3FileExists(tool: name, threadId: threadId, path: path, runtime: runtime) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "No such file: \(path)")
                }
                let (fileExit, fileOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["file", path], timeoutSeconds: analyzeTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "file", exitCode: fileExit, output: fileOutput)
                let (otoolExit, otoolOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["otool", "-L", path], timeoutSeconds: analyzeTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "otool", exitCode: otoolExit, output: otoolOutput)
                let (hvExit, hvOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["otool", "-hv", path], timeoutSeconds: analyzeTimeout, runtime: runtime)
                let (verifyExit, verifyOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["codesign", "--verify", "--verbose", path], timeoutSeconds: analyzeTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "codesign", exitCode: verifyExit, output: verifyOutput)
                let (dvExit, dvOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["codesign", "-dv", "--verbose=4", path], timeoutSeconds: analyzeTimeout, runtime: runtime)
                let libraries = Self.parseG3OtoolLibraries(otoolOutput)
                let headers = Self.parseG3MachHeader(hvOutput)
                let details = Self.parseG3Codesign(dvOutput)
                var artifact: [String: JSONValue] = [
                    "path": .string(path),
                    "inspection": .string(inspection),
                    "file": .string(fileOutput.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""),
                    "fileOutput": .string(fileOutput),
                    "libraries": .array(libraries.map { .string($0) }),
                    "headers": .array(headers.map { .object($0) }),
                    "verified": .bool(verifyExit == 0),
                    "verifyExitCode": .int(Int64(verifyExit)),
                    "verifyOutput": .string(verifyOutput),
                    "signature": .object(details),
                    "exitCode": .int(Int64(otoolExit)),
                    "hvExitCode": .int(Int64(hvExit)),
                    "signatureExitCode": .int(Int64(dvExit)),
                ]
                if (path as NSString).pathExtension.lowercased() == "plist", let plistCwd = optionalString(arguments, "cwd"),
                   let plist = try? Self.g6ReadPlist(cwd: plistCwd, path: path, tool: name, runtime: runtime) {
                    artifact["plistKeys"] = .array(plist.keys.sorted().map { .string($0) })
                }
                return .object(artifact)
            case "disassembly":
                let path = try requiredString(arguments, "path", tool: name)
                try Self.validateRelativePath(path, tool: name)
                guard try await Self.g3FileExists(tool: name, threadId: threadId, path: path, runtime: runtime) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "No such file: \(path)")
                }
                let (disassemblyExit, disassemblyOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["otool", "-tV", path], timeoutSeconds: analyzeTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "otool", exitCode: disassemblyExit, output: disassemblyOutput)
                return .object(["path": .string(path), "inspection": .string(inspection), "disassembly": .string(disassemblyOutput), "exitCode": .int(Int64(disassemblyExit))])
            case "demangle":
                let symbol = try requiredString(arguments, "symbol", tool: name)
                try Self.g3Token(symbol, field: "symbol", tool: name)
                let (demangleExit, demangleOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["xcrun", "swift-demangle", symbol], timeoutSeconds: analyzeTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "xcrun", exitCode: demangleExit, output: demangleOutput)
                return .object(["symbol": .string(symbol), "inspection": .string(inspection), "demangled": .string(demangleOutput.trimmingCharacters(in: .whitespacesAndNewlines)), "exitCode": .int(Int64(demangleExit)), "output": .string(demangleOutput)])
            case "sqlite_schema":
                let path = try requiredString(arguments, "path", tool: name)
                try Self.validateRelativePath(path, tool: name)
                guard try await Self.g3FileExists(tool: name, threadId: threadId, path: path, runtime: runtime) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "No such file: \(path)")
                }
                let (schemaExit, schemaOutput) = try await Self.g3Run(tool: name, threadId: threadId, argv: ["sqlite3", path, ".schema"], timeoutSeconds: analyzeTimeout, runtime: runtime)
                try Self.g3ThrowIfMissingCLI(tool: name, cli: "sqlite3", exitCode: schemaExit, output: schemaOutput)
                return .object(["path": .string(path), "inspection": .string(inspection), "schema": .string(schemaOutput), "exitCode": .int(Int64(schemaExit))])
            default:
                throw SystemToolError.executionFailed(tool: name, message: "reverse_analyze inspection must be artifact, disassembly, demangle, or sqlite_schema. REA evidence IDs and confidence scores are unavailable because the REA subsystem does not exist, and Go or managed-metadata inspection is not supported.")
            }
        case "report_to_user":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let summary = try requiredString(arguments, "summary", tool: name)
            guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SystemToolError.executionFailed(tool: name, message: "report_to_user summary must not be empty.")
            }
            let path = optionalString(arguments, "path") ?? ".assist_temp/artifacts/agent_notes.md"
            try Self.validateRelativePath(path, tool: name)
            let title = (optionalString(arguments, "title") ?? "Completion").replacingOccurrences(of: "\n", with: " ")
            let stamp = ISO8601DateFormatter().string(from: Date())
            let record = "## \(title)\n\(summary)\n\nRecorded \(stamp). The chat reply itself is the delivery to the user; this record marks the turn complete.\n"
            var existing = (try? await runtime.readWorkspaceFile(cwd: cwd, path: path))?.content ?? ""
            if !existing.isEmpty, !existing.hasSuffix("\n") {
                existing += "\n"
            }
            let notesContent = existing.isEmpty ? "# Agent Notes\n\n" + record : existing + "\n" + record
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: notesContent)
            return .object(["path": .string(path), "completed": .bool(true), "summary": .string(summary)])
        case "intel_explain_code":
            let cwd = try requiredString(arguments, "cwd", tool: name)
            let path = try requiredString(arguments, "path", tool: name)
            let summary = try await Self.runG5Tool(tool: "code_summary", arguments: ["cwd": .string(cwd), "path": .string(path)], runtime: runtime)
            let apiSurface = try await Self.runG5Tool(tool: "api_surface_extract", arguments: ["cwd": .string(cwd), "path": .string(path)], runtime: runtime)
            let docComments = try await Self.runG5Tool(tool: "code_comment_extract", arguments: ["cwd": .string(cwd), "path": .string(path)], runtime: runtime)
            return .object([
                "path": .string(path),
                "lines": summary["lines"] ?? .null,
                "codeLines": summary["codeLines"] ?? .null,
                "commentLines": summary["commentLines"] ?? .null,
                "blankLines": summary["blankLines"] ?? .null,
                "publicDeclarationCount": apiSurface["matchCount"] ?? .null,
                "docCommentCount": docComments["matchCount"] ?? .null,
                "summary": summary,
                "apiSurface": apiSurface,
                "docComments": docComments,
            ])
        default:
            throw SystemToolError.unknownTool(name)
        }
    }

    private struct G5PatternSpec {
        var label: String
        var pattern: String
        var redact: Bool
        var capture: Int
    }

    private struct G5ScanSpec {
        var shape: String
        var literal: Bool
        var sampleLimit: Int
        var patterns: [G5PatternSpec]
    }

    private static let g5ScanSpecs: [String: G5ScanSpec] = [
        "search_symbol": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "function", pattern: "func\\s+{symbol}\\b", redact: false, capture: 0), G5PatternSpec(label: "type", pattern: "(class|struct|enum|protocol)\\s+{symbol}\\b", redact: false, capture: 0), G5PatternSpec(label: "variable", pattern: "(let|var)\\s+{symbol}\\b", redact: false, capture: 0), G5PatternSpec(label: "typealias", pattern: "typealias\\s+{symbol}\\b", redact: false, capture: 0)]),
        "dependency_graph": G5ScanSpec(shape: "files", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "import", pattern: "^import\\s+([A-Za-z0-9_]+)", redact: false, capture: 1)]),
        "source_graph_builder": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "import", pattern: "^import\\s+([A-Za-z0-9_]+)", redact: false, capture: 1), G5PatternSpec(label: "type", pattern: "(class|struct|enum|protocol)\\s+([A-Za-z0-9_]+)", redact: false, capture: 2)]),
        "semantic_query_engine": G5ScanSpec(shape: "flat", literal: true, sampleLimit: 0, patterns: [G5PatternSpec(label: "match", pattern: "{query}", redact: false, capture: 0)]),
        "autonomous_review_engine": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "forceUnwrap", pattern: "[A-Za-z0-9_\\)\\]]![^=!]", redact: false, capture: 0), G5PatternSpec(label: "tryBang", pattern: "try!", redact: false, capture: 0), G5PatternSpec(label: "asBang", pattern: "as!", redact: false, capture: 0), G5PatternSpec(label: "mainSync", pattern: "DispatchQueue\\.main\\.sync", redact: false, capture: 0), G5PatternSpec(label: "fatal", pattern: "fatalError|precondition\\(", redact: false, capture: 0)]),
        "memory_leak_detector": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "unownedSelf", pattern: "\\[unowned self\\]", redact: false, capture: 0), G5PatternSpec(label: "strongSelf", pattern: "\\[self\\]", redact: false, capture: 0), G5PatternSpec(label: "delegateAssign", pattern: "\\.delegate\\s*=", redact: false, capture: 0), G5PatternSpec(label: "scheduledTimer", pattern: "Timer\\.scheduledTimer", redact: false, capture: 0), G5PatternSpec(label: "observer", pattern: "NotificationCenter\\.default\\.addObserver", redact: false, capture: 0)]),
        "todo_scan": G5ScanSpec(shape: "flat", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "todo", pattern: "\\b(TODO|FIXME|XXX|HACK)\\b", redact: false, capture: 0)]),
        "todo_fixme_scanner": G5ScanSpec(shape: "flat", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "todo", pattern: "\\b(TODO|FIXME|HACK|NOTE)\\b", redact: false, capture: 0)]),
        "api_surface_extract": G5ScanSpec(shape: "files", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "declaration", pattern: "\\b(public|open)\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0)]),
        "access_level_audit": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "public", pattern: "\\bpublic\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0), G5PatternSpec(label: "open", pattern: "\\bopen\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0), G5PatternSpec(label: "internal", pattern: "\\binternal\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0), G5PatternSpec(label: "private", pattern: "\\bprivate\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0), G5PatternSpec(label: "fileprivate", pattern: "\\bfileprivate\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0)]),
        "concurrency_audit": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "mainSync", pattern: "DispatchQueue\\.main\\.sync", redact: false, capture: 0), G5PatternSpec(label: "nonisolatedUnsafe", pattern: "nonisolated\\(unsafe\\)", redact: false, capture: 0), G5PatternSpec(label: "task", pattern: "Task\\s*\\{", redact: false, capture: 0), G5PatternSpec(label: "sharedMutableStatic", pattern: "static\\s+(let|var)\\s+[A-Za-z0-9_]+\\s*[:=]", redact: false, capture: 0), G5PatternSpec(label: "syncBlock", pattern: "\\.sync\\s*\\{", redact: false, capture: 0)]),
        "swift_concurrency_analyzer": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "nonisolated", pattern: "nonisolated", redact: false, capture: 0), G5PatternSpec(label: "mainActor", pattern: "@MainActor", redact: false, capture: 0), G5PatternSpec(label: "actor", pattern: "\\bactor\\s+[A-Za-z0-9_]+", redact: false, capture: 0), G5PatternSpec(label: "sendable", pattern: "Sendable", redact: false, capture: 0), G5PatternSpec(label: "detached", pattern: "Task\\.detached", redact: false, capture: 0)]),
        "swift_migration_advisor": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "dispatchQueue", pattern: "DispatchQueue", redact: false, capture: 0), G5PatternSpec(label: "lock", pattern: "NSLock|os_unfair_lock", redact: false, capture: 0), G5PatternSpec(label: "mutableGlobal", pattern: "static\\s+var\\s+[A-Za-z0-9_]+", redact: false, capture: 0), G5PatternSpec(label: "uncheckedSendable", pattern: "@unchecked Sendable", redact: false, capture: 0), G5PatternSpec(label: "nonisolatedUnsafe", pattern: "nonisolated\\(unsafe\\)", redact: false, capture: 0)]),
        "security_audit_scanner": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "plainHttp", pattern: "http://[^ \\t\\\"'\\)]+", redact: false, capture: 0), G5PatternSpec(label: "apiKey", pattern: "api_key\\s*[:=]", redact: true, capture: 0), G5PatternSpec(label: "password", pattern: "password\\s*[:=]", redact: true, capture: 0), G5PatternSpec(label: "awsKey", pattern: "AKIA[0-9A-Z]{16}", redact: true, capture: 0), G5PatternSpec(label: "bearer", pattern: "Bearer\\s+[A-Za-z0-9\\-_\\.]+", redact: true, capture: 0)]),
        "secrets_scan": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "awsKey", pattern: "AKIA[0-9A-Z]{16}", redact: true, capture: 0), G5PatternSpec(label: "githubToken", pattern: "ghp_[A-Za-z0-9]{20,}", redact: true, capture: 0), G5PatternSpec(label: "skKey", pattern: "sk-[A-Za-z0-9]{20,}", redact: true, capture: 0), G5PatternSpec(label: "apiKey", pattern: "api_key\\s*[:=]", redact: true, capture: 0), G5PatternSpec(label: "password", pattern: "password\\s*[:=]", redact: true, capture: 0), G5PatternSpec(label: "privateKey", pattern: "BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY", redact: true, capture: 0), G5PatternSpec(label: "slackToken", pattern: "xox[baprs]-[A-Za-z0-9\\-]{10,}", redact: true, capture: 0)]),
        "network_security_auditor": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "plainHttp", pattern: "http://[^ \\t\\\"'\\)]+", redact: false, capture: 0), G5PatternSpec(label: "ats", pattern: "NSAppTransportSecurity", redact: false, capture: 0), G5PatternSpec(label: "arbitraryLoads", pattern: "NSAllowsArbitraryLoads", redact: false, capture: 0), G5PatternSpec(label: "localNetworking", pattern: "NSAllowsLocalNetworking", redact: false, capture: 0), G5PatternSpec(label: "pinning", pattern: "SecTrust|certificatePinning|pinnedCertificate", redact: false, capture: 0)]),
        "permissions_audit": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "usageDescription", pattern: "UsageDescription", redact: false, capture: 0), G5PatternSpec(label: "privacyInfo", pattern: "NSPrivacy", redact: false, capture: 0), G5PatternSpec(label: "entitlement", pattern: "com\\.apple\\.security", redact: false, capture: 0), G5PatternSpec(label: "sensitiveEntitlement", pattern: "get-task-allow|application-identifier", redact: false, capture: 0)]),
        "accessibility_audit": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "button", pattern: "Button\\(", redact: false, capture: 0), G5PatternSpec(label: "image", pattern: "Image\\(", redact: false, capture: 0), G5PatternSpec(label: "textField", pattern: "TextField\\(", redact: false, capture: 0), G5PatternSpec(label: "label", pattern: "\\.accessibilityLabel\\(", redact: false, capture: 0), G5PatternSpec(label: "hint", pattern: "\\.accessibilityHint\\(", redact: false, capture: 0), G5PatternSpec(label: "value", pattern: "\\.accessibilityValue\\(", redact: false, capture: 0)]),
        "accessibility_audit_scanner": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "label", pattern: "\\.accessibilityLabel\\(", redact: false, capture: 0), G5PatternSpec(label: "hint", pattern: "\\.accessibilityHint\\(", redact: false, capture: 0), G5PatternSpec(label: "traits", pattern: "\\.accessibilityAddTraits\\(", redact: false, capture: 0), G5PatternSpec(label: "hidden", pattern: "\\.accessibilityHidden\\(", redact: false, capture: 0), G5PatternSpec(label: "identifier", pattern: "\\.accessibilityIdentifier\\(", redact: false, capture: 0)]),
        "interface_simulator": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 5, patterns: [G5PatternSpec(label: "label", pattern: "\\.accessibilityLabel\\(", redact: false, capture: 0), G5PatternSpec(label: "dynamicType", pattern: "\\.dynamicTypeSize\\(", redact: false, capture: 0), G5PatternSpec(label: "font", pattern: "\\.font\\(", redact: false, capture: 0), G5PatternSpec(label: "button", pattern: "Button\\(", redact: false, capture: 0), G5PatternSpec(label: "fixedFrame", pattern: "\\.frame\\(width", redact: false, capture: 0), G5PatternSpec(label: "color", pattern: "\\.foregroundColor\\(|Color\\(", redact: false, capture: 0)]),
        "force_unwrap_scan": G5ScanSpec(shape: "flat", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "forceUnwrap", pattern: "[A-Za-z0-9_\\)\\]]![^=!]", redact: false, capture: 0), G5PatternSpec(label: "tryBang", pattern: "try!", redact: false, capture: 0), G5PatternSpec(label: "asBang", pattern: "as!", redact: false, capture: 0)]),
        "string_literal_audit": G5ScanSpec(shape: "flat", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "stringLiteral", pattern: "\"[^\"]{8,}\"", redact: false, capture: 0)]),
        "call_hierarchy": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "definition", pattern: "(func|init)\\s+{function}\\b", redact: false, capture: 0), G5PatternSpec(label: "callSite", pattern: "\\b{function}\\s*\\(", redact: false, capture: 0)]),
        "type_hierarchy": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "type", pattern: "(class|struct|enum|protocol)\\s+([A-Za-z0-9_]+)(\\s*:\\s*[^{]+)?", redact: false, capture: 2)]),
        "protocol_conformance_list": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "conformance", pattern: "(class|struct|enum)\\s+([A-Za-z0-9_]+)\\s*:[^{]*\\b{protocol}\\b", redact: false, capture: 2)]),
        "import_graph": G5ScanSpec(shape: "files", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "import", pattern: "^import\\s+([A-Za-z0-9_]+)", redact: false, capture: 1)]),
        "change_impact_estimate": G5ScanSpec(shape: "flat", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "reference", pattern: "\\b{symbol}\\b", redact: false, capture: 0)]),
        "conflict_marker_scan": G5ScanSpec(shape: "flat", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "marker", pattern: "^(<{7}|={7}|>{7}|\\|{7})", redact: false, capture: 0)]),
        "deprecation_usage_scan": G5ScanSpec(shape: "flat", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "deprecated", pattern: "\\bdeprecated\\b", redact: false, capture: 0)]),
        "api_endpoint_audit": G5ScanSpec(shape: "host", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "url", pattern: "https?://([A-Za-z0-9.\\-]+)", redact: false, capture: 1)]),
        "color_usage_audit": G5ScanSpec(shape: "flat", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "color", pattern: "Color\\(|UIColor\\(|NSColor\\(|#[0-9A-Fa-f]{6}\\b", redact: false, capture: 0)]),
        "xctest_discovery": G5ScanSpec(shape: "patterns", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "testClass", pattern: "class\\s+([A-Za-z0-9_]+)\\s*:\\s*XCTestCase", redact: false, capture: 1), G5PatternSpec(label: "testMethod", pattern: "func\\s+(test[A-Za-z0-9_]*)\\s*\\(", redact: false, capture: 1)]),
        "code_comment_extract": G5ScanSpec(shape: "flat", literal: false, sampleLimit: 0, patterns: [G5PatternSpec(label: "comment", pattern: "///|/\\*\\*", redact: false, capture: 0)]),
    ]

    private static let g5ProtectedModules: Set<String> = [
        "Foundation", "SwiftUI", "AppKit", "UIKit", "Combine", "CoreData", "CryptoKit",
        "Security", "XCTest", "SwiftData", "Observation", "WebKit",
        "UniformTypeIdentifiers", "Dispatch", "Network", "os", "SystemConfiguration",
        "CoreGraphics", "QuartzCore", "StoreKit", "AuthenticationServices",
    ]

    struct G6Manifest {
        var name: String
        var platforms: [String]
        var products: [String]
        var targets: [String]
        var dependencies: [[String: String]]
    }

    struct G6IconSize {
        var pixels: Int
        var label: String
        var idiom: String
        var scale: String
    }

    private static func g6JoinPath(cwd: String, path: String?) -> String {
        guard let path, !path.isEmpty else { return cwd }
        return (cwd as NSString).appendingPathComponent(path)
    }

    private static func g6TerminalJSON(tool: String, threadId: String, cwd: String, command: String, timeoutSeconds: Int, runtime: AgentsRuntimeClient) async throws -> (exitCode: Int, output: String) {
        let fullCommand = "cd " + shellQuoted(ExternalEditorService.expandedPath(cwd)) + " && " + command
        let result = try await runTerminalCommand(tool: tool, threadId: threadId, command: fullCommand, timeoutSeconds: timeoutSeconds, runtime: runtime)
        if result["timedOut"]?.boolValue == true {
            throw SystemToolError.operationTimeout(tool: tool)
        }
        let exitCode = result["exitCode"]?.intValue ?? -1
        return (exitCode, cleanTerminalOutput(result["output"]?.stringValue ?? ""))
    }

    private static func g6FetchURL(_ url: URL, timeoutSeconds: Int, tool: String) async throws -> (statusCode: Int, contentType: String, title: String?, text: String) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = TimeInterval(timeoutSeconds)
        configuration.timeoutIntervalForResource = TimeInterval(timeoutSeconds)
        let session = URLSession(configuration: configuration)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw SystemToolError.executionFailed(tool: tool, message: "Fetch failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw SystemToolError.executionFailed(tool: tool, message: "Fetch did not return an HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SystemToolError.executionFailed(tool: tool, message: "Fetch returned HTTP \(http.statusCode).")
        }
        let text = String(decoding: data, as: UTF8.self)
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        var title: String?
        if let match = Self.g5RegexMatches(pattern: "<title>([^<]+)</title>", text: text, options: [.caseInsensitive]).first {
            title = match.1.count > 1 ? match.1[1] : nil
        }
        return (http.statusCode, contentType, title, text)
    }

    private static func g6ResolveFile(cwd: String, path: String?, query: String, match: (WorkspaceFileEntry) -> Bool, tool: String, runtime: AgentsRuntimeClient) async throws -> String {
        if let path, !path.isEmpty { return path }
        let entries = try await runtime.listWorkspaceFiles(cwd: cwd, query: query, limit: 100)
        guard let found = entries.first(where: { !$0.isDirectory && match($0) }) else {
            throw SystemToolError.executionFailed(tool: tool, message: "No file matching \(query) found in the workspace.")
        }
        return found.path
    }

    private static func g6Entries(cwd: String, path: String?, runtime: AgentsRuntimeClient) async throws -> [WorkspaceFileEntry] {
        try await runtime.readWorkspaceDirectory(cwd: cwd, path: path ?? "", recursive: true)
    }

    static func g6PlistObject(data: Data, tool: String) throws -> Any {
        var format = PropertyListSerialization.PropertyListFormat.xml
        do {
            return try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        } catch {
            throw SystemToolError.executionFailed(tool: tool, message: "File was not a valid property list: \(error.localizedDescription)")
        }
    }

    private static func g6ReadPlist(cwd: String, path: String, tool: String, runtime: AgentsRuntimeClient) async throws -> [String: Any] {
        let data = try readWorkspaceBytes(cwd: cwd, path: path, tool: tool)
        let object = try g6PlistObject(data: data, tool: tool)
        guard let dict = object as? [String: Any] else {
            throw SystemToolError.executionFailed(tool: tool, message: "Property list root is not a dictionary.")
        }
        return dict
    }

    private static func g6WritePlist(cwd: String, path: String, dict: [String: Any], tool: String) throws {
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        } catch {
            throw SystemToolError.executionFailed(tool: tool, message: "Could not serialize property list: \(error.localizedDescription)")
        }
        try writeWorkspaceBytes(cwd: cwd, path: path, data: data, tool: tool)
    }

    static func g6PlistScalar(_ text: String) -> Any {
        if text == "true" { return true }
        if text == "false" { return false }
        if let int = Int(text) { return int }
        if let double = Double(text) { return double }
        return text
    }

    static func g6StringsUnescape(_ text: String) -> String {
        var out = ""
        var escaped = false
        for char in text {
            if escaped {
                switch char {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                default: out.append(char)
                }
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else {
                out.append(char)
            }
        }
        return out
    }

    static func g6StringsEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
    }

    static func g6StringsPairs(_ content: String) -> [(key: String, value: String, line: Int)] {
        var pairs: [(key: String, value: String, line: Int)] = []
        for (index, line) in Self.g5Lines(content).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let match = Self.g5RegexMatches(pattern: "^\"((?:[^\"\\\\]|\\\\.)*)\"\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*;", text: trimmed).first else { continue }
            let key = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let value = match.1.count > 2 ? (match.1[2] ?? "") : ""
            if !key.isEmpty {
                pairs.append((key: Self.g6StringsUnescape(key), value: Self.g6StringsUnescape(value), line: index + 1))
            }
        }
        return pairs
    }

    static func g6SerializeStrings(_ pairs: [(key: String, value: String)]) -> String {
        pairs.map { "\"\(g6StringsEscape($0.key))\" = \"\(g6StringsEscape($0.value))\";" }.joined(separator: "\n") + "\n"
    }

    static func g6XcstringsDecode(_ content: String, tool: String) throws -> [String: JSONValue] {
        guard let data = content.data(using: .utf8) else {
            throw SystemToolError.executionFailed(tool: tool, message: "Catalog was not valid UTF-8.")
        }
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw SystemToolError.executionFailed(tool: tool, message: "Catalog was not valid JSON: \(error.localizedDescription)")
        }
        guard case .object(let dict) = value else {
            throw SystemToolError.executionFailed(tool: tool, message: "Catalog root is not a JSON object.")
        }
        return dict
    }

    static func g6XcstringsEncode(_ dict: [String: JSONValue], tool: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(JSONValue.object(dict)), let text = String(data: data, encoding: .utf8) else {
            throw SystemToolError.executionFailed(tool: tool, message: "Could not serialize the catalog as JSON.")
        }
        return text + "\n"
    }

    static func g6XcstringsKeys(_ dict: [String: JSONValue]) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        guard let strings = dict["strings"]?.objectValue else { return out }
        for (key, entry) in strings {
            var locales: [String: String] = [:]
            if let localizations = entry["localizations"]?.objectValue {
                for (locale, loc) in localizations {
                    if let value = loc["stringUnit"]?["value"]?.stringValue {
                        locales[locale] = value
                    }
                }
            }
            out[key] = locales
        }
        return out
    }

    static func g6XcstringsSet(_ dict: [String: JSONValue], key: String, locale: String, value: String, state: String) -> [String: JSONValue] {
        var dict = dict
        var strings = dict["strings"]?.objectValue ?? [:]
        var entry = strings[key]?.objectValue ?? [:]
        var localizations = entry["localizations"]?.objectValue ?? [:]
        localizations[locale] = .object(["stringUnit": .object(["state": .string(state), "value": .string(value)])])
        entry["localizations"] = .object(localizations)
        strings[key] = .object(entry)
        dict["strings"] = .object(strings)
        return dict
    }

    static func g6ParseManifest(_ content: String) -> G6Manifest {
        var name = ""
        if let range = content.range(of: "Package(") {
            let rest = String(content[range.upperBound...])
            if let match = Self.g5RegexMatches(pattern: "name:\\s*\"([^\"]+)\"", text: rest).first {
                name = match.1.count > 1 ? (match.1[1] ?? "") : ""
            }
        }
        var platforms: [String] = []
        for match in Self.g5RegexMatches(pattern: "\\.([A-Za-z]+)\\(\\.v([0-9_]+)\\)", text: content) {
            let platform = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let version = match.1.count > 2 ? (match.1[2] ?? "") : ""
            if !platform.isEmpty {
                platforms.append(platform + " " + version.replacingOccurrences(of: "_", with: "."))
            }
        }
        var products: [String] = []
        for match in Self.g5RegexMatches(pattern: "\\.(library|executable)\\(\\s*name:\\s*\"([^\"]+)\"", text: content) {
            let product = match.1.count > 2 ? (match.1[2] ?? "") : ""
            if !product.isEmpty { products.append(product) }
        }
        var targets: [String] = []
        for match in Self.g5RegexMatches(pattern: "\\.(target|testTarget|executableTarget|binaryTarget|systemLibrary|plugin)\\(\\s*name:\\s*\"([^\"]+)\"", text: content) {
            let target = match.1.count > 2 ? (match.1[2] ?? "") : ""
            if !target.isEmpty { targets.append(target) }
        }
        var dependencies: [[String: String]] = []
        for match in Self.g5RegexMatches(pattern: "\\.package\\(\\s*url:\\s*\"([^\"]+)\"([^)]*)\\)", text: content) {
            let url = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let rest = match.1.count > 2 ? (match.1[2] ?? "") : ""
            var dep: [String: String] = ["url": url]
            if let req = Self.g5RegexMatches(pattern: "(from|exact|branch|revision):\\s*\"([^\"]+)\"", text: rest).first {
                let kind = req.1.count > 1 ? (req.1[1] ?? "") : ""
                let version = req.1.count > 2 ? (req.1[2] ?? "") : ""
                if !kind.isEmpty { dep[kind] = version }
            }
            if !url.isEmpty { dependencies.append(dep) }
        }
        for match in Self.g5RegexMatches(pattern: "\\.package\\(\\s*path:\\s*\"([^\"]+)\"", text: content) {
            let path = match.1.count > 1 ? (match.1[1] ?? "") : ""
            if !path.isEmpty { dependencies.append(["path": path]) }
        }
        return G6Manifest(name: name, platforms: platforms, products: products, targets: targets, dependencies: dependencies)
    }

    static func g6ParseResolved(_ content: String) -> [[String: String]] {
        guard let data = content.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let pins = value["pins"]?.arrayValue else { return [] }
        var out: [[String: String]] = []
        for pin in pins {
            var entry: [String: String] = [:]
            if let identity = pin["identity"]?.stringValue ?? pin["package"]?.stringValue {
                entry["identity"] = identity
            }
            if let location = pin["location"]?.stringValue ?? pin["repositoryURL"]?.stringValue {
                entry["location"] = location
            }
            if let version = pin["state"]?["version"]?.stringValue ?? pin["state"]?["revision"]?.stringValue ?? pin["version"]?.stringValue {
                entry["version"] = version
            }
            if !entry.isEmpty { out.append(entry) }
        }
        return out
    }

    static func g6ShowDependenciesNames(_ value: JSONValue) -> [String] {
        var names: [String] = []
        guard let dependencies = value["dependencies"]?.arrayValue else { return names }
        for dep in dependencies {
            if let identity = dep["identity"]?.stringValue {
                names.append(identity)
            }
            names.append(contentsOf: g6ShowDependenciesNames(dep))
        }
        return names
    }

    static func g6DependencyAudit(tool: String, manifest: G6Manifest, resolvedPins: [[String: String]], shown: [String], exitCode: Int, output: String) -> JSONValue {
        var missingResolved: [String] = []
        var nonExact: [[String: JSONValue]] = []
        var missingFromManifest: [String] = []
        let resolvedIdentities = resolvedPins.compactMap { $0["identity"] }
        for dep in manifest.dependencies {
            if let url = dep["url"] {
                let identity = (url as NSString).deletingPathExtension.components(separatedBy: "/").last ?? url
                if !resolvedIdentities.contains(where: { $0.lowercased() == identity.lowercased() }) {
                    missingResolved.append(url)
                }
                if dep["from"] != nil || dep["branch"] != nil {
                    nonExact.append(["url": .string(url), "requirement": .string(dep["from"] ?? dep["branch"] ?? "")])
                }
            }
        }
        for pin in resolvedPins {
            guard let identity = pin["identity"] else { continue }
            let inManifest = manifest.dependencies.contains { dep in
                guard let url = dep["url"] else { return false }
                let name = (url as NSString).deletingPathExtension.components(separatedBy: "/").last ?? url
                return name.lowercased() == identity.lowercased()
            }
            if !inManifest {
                missingFromManifest.append(identity)
            }
        }
        return .object([
            "tool": .string(tool),
            "manifestName": .string(manifest.name),
            "manifestDependencies": .int(Int64(manifest.dependencies.count)),
            "resolvedPins": .int(Int64(resolvedPins.count)),
            "missingResolved": .array(missingResolved.map { .string($0) }),
            "nonExactRequirements": .array(nonExact),
            "resolvedMissingFromManifest": .array(missingFromManifest.map { .string($0) }),
            "showDependencies": .array(shown.map { .string($0) }),
            "showDependenciesExitCode": .int(Int64(exitCode)),
            "output": .string(output),
        ])
    }

    static func g6SigningFromPbxproj(tool: String, path: String, content: String) -> JSONValue {
        var values: [String: String] = [:]
        for key in ["CODE_SIGN_STYLE", "DEVELOPMENT_TEAM", "PRODUCT_BUNDLE_IDENTIFIER", "CODE_SIGN_IDENTITY", "PROVISIONING_PROFILE_SPECIFIER"] {
            if let found = Self.g5RegexMatches(pattern: key + "\\s*=\\s*([^;]+);", text: content).first,
               let value = found.1.count > 1 ? found.1[1] : nil {
                values[key] = value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "codeSignStyle": values["CODE_SIGN_STYLE"].map { .string($0) } ?? .null,
            "developmentTeam": values["DEVELOPMENT_TEAM"].map { .string($0) } ?? .null,
            "bundleIdentifier": values["PRODUCT_BUNDLE_IDENTIFIER"].map { .string($0) } ?? .null,
            "codeSignIdentity": values["CODE_SIGN_IDENTITY"].map { .string($0) } ?? .null,
            "provisioningProfileSpecifier": values["PROVISIONING_PROFILE_SPECIFIER"].map { .string($0) } ?? .null,
        ])
    }

    static func g6BuildSettingsJSON(_ output: String) -> JSONValue {
        var dict: [String: JSONValue] = [:]
        for line in Self.g5Lines(output) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let match = Self.g5RegexMatches(pattern: "^([A-Z0-9_]+)\\s*=\\s*(.+)$", text: trimmed).first else { continue }
            let key = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let value = match.1.count > 2 ? (match.1[2] ?? "") : ""
            if !key.isEmpty { dict[key] = .string(value.trimmingCharacters(in: .whitespaces)) }
        }
        return .object(dict)
    }

    static func g6IconSizes(platform: String) -> [G6IconSize] {
        switch platform {
        case "macos":
            return [
                G6IconSize(pixels: 16, label: "16x16", idiom: "mac", scale: "1x"),
                G6IconSize(pixels: 32, label: "16x16", idiom: "mac", scale: "2x"),
                G6IconSize(pixels: 32, label: "32x32", idiom: "mac", scale: "1x"),
                G6IconSize(pixels: 64, label: "32x32", idiom: "mac", scale: "2x"),
                G6IconSize(pixels: 128, label: "128x128", idiom: "mac", scale: "1x"),
                G6IconSize(pixels: 256, label: "128x128", idiom: "mac", scale: "2x"),
                G6IconSize(pixels: 256, label: "256x256", idiom: "mac", scale: "1x"),
                G6IconSize(pixels: 512, label: "256x256", idiom: "mac", scale: "2x"),
                G6IconSize(pixels: 512, label: "512x512", idiom: "mac", scale: "1x"),
                G6IconSize(pixels: 1024, label: "512x512", idiom: "mac", scale: "2x"),
            ]
        case "watchos":
            return [
                G6IconSize(pixels: 48, label: "24x24", idiom: "watch", scale: "2x"),
                G6IconSize(pixels: 55, label: "27.5x27.5", idiom: "watch", scale: "2x"),
                G6IconSize(pixels: 58, label: "29x29", idiom: "watch", scale: "2x"),
                G6IconSize(pixels: 87, label: "29x29", idiom: "watch", scale: "3x"),
                G6IconSize(pixels: 80, label: "40x40", idiom: "watch", scale: "2x"),
                G6IconSize(pixels: 88, label: "44x44", idiom: "watch", scale: "2x"),
                G6IconSize(pixels: 100, label: "50x50", idiom: "watch", scale: "2x"),
                G6IconSize(pixels: 172, label: "86x86", idiom: "watch", scale: "2x"),
                G6IconSize(pixels: 196, label: "98x98", idiom: "watch", scale: "2x"),
                G6IconSize(pixels: 216, label: "108x108", idiom: "watch", scale: "2x"),
                G6IconSize(pixels: 1024, label: "1024x1024", idiom: "watch-marketing", scale: "1x"),
            ]
        default:
            return [
                G6IconSize(pixels: 40, label: "20x20", idiom: "iphone", scale: "2x"),
                G6IconSize(pixels: 60, label: "20x20", idiom: "iphone", scale: "3x"),
                G6IconSize(pixels: 58, label: "29x29", idiom: "iphone", scale: "2x"),
                G6IconSize(pixels: 87, label: "29x29", idiom: "iphone", scale: "3x"),
                G6IconSize(pixels: 80, label: "40x40", idiom: "iphone", scale: "2x"),
                G6IconSize(pixels: 120, label: "40x40", idiom: "iphone", scale: "3x"),
                G6IconSize(pixels: 120, label: "60x60", idiom: "iphone", scale: "2x"),
                G6IconSize(pixels: 180, label: "60x60", idiom: "iphone", scale: "3x"),
                G6IconSize(pixels: 76, label: "76x76", idiom: "ipad", scale: "1x"),
                G6IconSize(pixels: 152, label: "76x76", idiom: "ipad", scale: "2x"),
                G6IconSize(pixels: 167, label: "83.5x83.5", idiom: "ipad", scale: "2x"),
                G6IconSize(pixels: 1024, label: "1024x1024", idiom: "ios-marketing", scale: "1x"),
            ]
        }
    }

    static func g6AppIconContents(platform: String, generated: [[String: JSONValue]]) -> [String: Any] {
        var images: [[String: Any]] = []
        for entry in generated {
            guard let size = entry["size"]?.stringValue,
                  let idiom = entry["idiom"]?.stringValue,
                  let scale = entry["scale"]?.stringValue,
                  let filename = entry["filename"]?.stringValue else { continue }
            images.append(["idiom": idiom, "filename": filename, "scale": scale, "size": size])
        }
        return ["images": images, "info": ["author": "xcode", "version": 1]]
    }

    private static func g6EnvInfo(tool: String) -> JSONValue {
        let process = ProcessInfo.processInfo
        var machine = "unknown"
        var sysinfo = utsname()
        if uname(&sysinfo) == 0 {
            machine = withUnsafeBytes(of: sysinfo.machine) { raw in
                let bytes = raw.prefix(while: { $0 != 0 })
                return String(bytes: bytes, encoding: .utf8) ?? "unknown"
            }
        }
        let versionString = process.operatingSystemVersionString
        var build = ""
        if let start = versionString.firstIndex(of: "("), let end = versionString.firstIndex(of: ")"), start < end {
            build = String(versionString[versionString.index(after: start)..<end])
        }
        return .object([
            "tool": .string(tool),
            "osVersion": .string(versionString),
            "osBuild": .string(build),
            "arch": .string(machine),
            "cpuCount": .int(Int64(process.processorCount)),
            "physicalMemoryBytes": .int(Int64(process.physicalMemory)),
            "hostName": .string(process.hostName),
            "uptimeSeconds": .double(process.systemUptime),
        ])
    }

    static func g6ParsePs(_ output: String, filter: String?, limit: Int) -> [[String: JSONValue]] {
        var rows: [[String: JSONValue]] = []
        for line in Self.g5Lines(output) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4, let pid = Int(parts[0]), let cpu = Double(parts[1]), let mem = Double(parts[2]) else { continue }
            let command = parts[3...].joined(separator: " ")
            if let filter, !filter.isEmpty, !command.localizedCaseInsensitiveContains(filter) { continue }
            rows.append([
                "pid": .int(Int64(pid)),
                "cpuPercent": .double(cpu),
                "memoryPercent": .double(mem),
                "command": .string(command),
            ])
            if rows.count >= limit { break }
        }
        return rows
    }

    static func g6DiskSpace(tool: String, path: String, dfOutput: String, duOutput: String) -> JSONValue {
        var totalKilobytes: Int64?
        var availableKilobytes: Int64?
        var usedKilobytes: Int64?
        var capacityPercent: Int64?
        var mountPoint: String?
        for line in Self.g5Lines(dfOutput) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9, let total = Int64(parts[1]), let used = Int64(parts[2]), let available = Int64(parts[3]) else { continue }
            totalKilobytes = total
            usedKilobytes = used
            availableKilobytes = available
            capacityPercent = Int64(parts[4].replacingOccurrences(of: "%", with: "")) ?? nil
            mountPoint = parts[8...].joined(separator: " ")
        }
        var pathKilobytes: Int64?
        let duParts = duOutput.split(separator: " ", omittingEmptySubsequences: true)
        if let first = duParts.first, let size = Int64(first) {
            pathKilobytes = size
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "totalKilobytes": totalKilobytes.map { .int($0) } ?? .null,
            "usedKilobytes": usedKilobytes.map { .int($0) } ?? .null,
            "availableKilobytes": availableKilobytes.map { .int($0) } ?? .null,
            "capacityPercent": capacityPercent.map { .int($0) } ?? .null,
            "mountPoint": mountPoint.map { .string($0) } ?? .null,
            "pathKilobytes": pathKilobytes.map { .int($0) } ?? .null,
        ])
    }

    private static func runG6Tool(tool: String, arguments: [String: JSONValue], runtime: AgentsRuntimeClient) async throws -> JSONValue {
        if tool == "derived_data_locate" {
            return Self.g6DerivedData(tool: tool, path: optionalString(arguments, "path"), limit: min(max(optionalInt(arguments, "limit") ?? 20, 1), 100))
        }
        let cwd = try requiredString(arguments, "cwd", tool: tool)
        let path = optionalString(arguments, "path")
        let limit = max(1, min(1000, optionalInt(arguments, "limit") ?? 200))
        switch tool {
        case "framework_linker_auditor":
            let pbxproj = try await Self.g5ResolvePbxproj(tool: tool, cwd: cwd, path: path, runtime: runtime)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: pbxproj)
            return Self.g6FrameworkAudit(tool: tool, path: pbxproj, content: document.content)
        case "string_catalog_migrator":
            let sourceLanguage = optionalString(arguments, "sourceLanguage") ?? "en"
            var files: [(path: String, content: String)] = []
            let singleFile = path.map { $0.hasSuffix(".strings") || $0.hasSuffix(".stringsdict") } ?? false
            if let path, !path.isEmpty, singleFile {
                let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
                files = [(path: path, content: document.content)]
            } else {
                files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".strings", ".stringsdict"], limit: 100, runtime: runtime)
            }
            guard !files.isEmpty else {
                throw SystemToolError.executionFailed(tool: tool, message: "No .strings or .stringsdict files found.")
            }
            var migrated: [[String: JSONValue]] = []
            var skipped: [[String: JSONValue]] = []
            for file in files {
                if file.path.hasSuffix(".stringsdict") {
                    skipped.append(["path": .string(file.path), "reason": .string("stringsdict plural forms need manual mapping and are not migrated.")])
                    continue
                }
                let pairs = Self.g6StringsPairs(file.content)
                var strings: [String: JSONValue] = [:]
                for pair in pairs {
                    strings[pair.key] = .object(["localizations": .object([sourceLanguage: .object(["stringUnit": .object(["state": .string("translated"), "value": .string(pair.value)])])])])
                }
                let catalog: [String: JSONValue] = [
                    "sourceLanguage": .string(sourceLanguage),
                    "strings": .object(strings),
                    "version": .string("1.0"),
                ]
                let outPath = (file.path as NSString).deletingPathExtension + ".xcstrings"
                let text = try Self.g6XcstringsEncode(catalog, tool: tool)
                try await runtime.writeWorkspaceFile(cwd: cwd, path: outPath, content: text)
                let verify = try await runtime.readWorkspaceFile(cwd: cwd, path: outPath)
                let decoded = try Self.g6XcstringsDecode(verify.content, tool: tool)
                migrated.append([
                    "source": .string(file.path),
                    "catalog": .string(outPath),
                    "keys": .int(Int64(pairs.count)),
                    "verified": .bool(decoded["strings"]?.objectValue?.count == pairs.count),
                ])
            }
            return .object([
                "tool": .string(tool),
                "migrated": .array(migrated),
                "skipped": .array(skipped),
                "count": .int(Int64(migrated.count)),
            ])
        case "symbol_reference_graph":
            let symbol = try requiredString(arguments, "symbol", tool: name)
            let escaped = NSRegularExpression.escapedPattern(for: symbol)
            let declarationHits = try await runtime.searchWorkspaceRegex(cwd: cwd, pattern: "(func|class|struct|enum|protocol|let|var|typealias|actor)\\s+" + escaped + "\\b", limit: limit)
            let referenceHits = try await runtime.searchWorkspaceRegex(cwd: cwd, pattern: "\\b" + escaped + "\\b", limit: limit)
            let scoped = { (hits: [WorkspaceSearchHit]) in
                hits.filter { hit in
                    guard let path, !path.isEmpty else { return true }
                    return hit.path == path || hit.path.hasPrefix(path + "/")
                }
            }
            let definitions = scoped(declarationHits).map { hit in
                .object([
                    "path": .string(hit.path),
                    "lineNumber": .int(Int64(hit.lineNumber)),
                    "column": .int(Int64(hit.column)),
                    "lineText": .string(hit.lineText),
                ])
            }
            let definitionKeys = Set(definitions.compactMap { def -> String? in
                guard let p = def["path"]?.stringValue, let l = def["lineNumber"]?.intValue else { return nil }
                return p + ":\(l)"
            })
            let references = scoped(referenceHits).filter { hit in
                !definitionKeys.contains(hit.path + ":\(hit.lineNumber)")
            }.map { hit in
                .object([
                    "path": .string(hit.path),
                    "lineNumber": .int(Int64(hit.lineNumber)),
                    "column": .int(Int64(hit.column)),
                    "lineText": .string(hit.lineText),
                ])
            }
            return .object([
                "tool": .string(tool),
                "symbol": .string(symbol),
                "definitions": .array(definitions),
                "references": .array(references),
                "definitionCount": .int(Int64(definitions.count)),
                "referenceCount": .int(Int64(references.count)),
            ])
        case "podfile_inspector":
            let podfile = try await Self.g6ResolveFile(cwd: cwd, path: path, query: "Podfile", match: { $0.name == "Podfile" || $0.path.hasSuffix("/Podfile") }, tool: tool, runtime: runtime)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: podfile)
            var pods: [[String: JSONValue]] = []
            var targets: [String] = []
            var currentTarget = ""
            var platform = ""
            for line in Self.g5Lines(document.content) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let match = Self.g5RegexMatches(pattern: "^target\\s+['\"]([^'\"]+)['\"]\\s+do", text: trimmed).first,
                   let target = match.1.count > 1 ? match.1[1] : nil {
                    targets.append(target)
                    currentTarget = target
                    continue
                }
                if trimmed == "end" {
                    currentTarget = ""
                    continue
                }
                if let match = Self.g5RegexMatches(pattern: "^platform\\s+:(\\w+),\\s*['\"]([^'\"]+)['\"]", text: trimmed).first {
                    let name = match.1.count > 1 ? (match.1[1] ?? "") : ""
                    let version = match.1.count > 2 ? (match.1[2] ?? "") : ""
                    platform = name + " " + version
                    continue
                }
                if let match = Self.g5RegexMatches(pattern: "^pod\\s+['\"]([^'\"]+)['\"](?:\\s*,\\s*['\"]([^'\"]+)['\"])?", text: trimmed).first {
                    let name = match.1.count > 1 ? (match.1[1] ?? "") : ""
                    let requirement = match.1.count > 2 ? (match.1[2] ?? "") : ""
                    pods.append([
                        "name": .string(name),
                        "requirement": .string(requirement),
                        "target": .string(currentTarget),
                    ])
                }
            }
            var locked: [[String: JSONValue]] = []
            let dir = (podfile as NSString).deletingLastPathComponent
            let lockPath = dir.isEmpty ? "Podfile.lock" : dir + "/Podfile.lock"
            if let lockDoc = try? await runtime.readWorkspaceFile(cwd: cwd, path: lockPath) {
                var inPods = false
                for line in Self.g5Lines(lockDoc.content) {
                    if line.hasPrefix("PODS:") { inPods = true; continue }
                    if inPods {
                        if line.isEmpty || (!line.hasPrefix(" ") && !line.hasPrefix("\t")) { break }
                        if let match = Self.g5RegexMatches(pattern: "^\\s*-\\s*([A-Za-z0-9_./-]+) \\(([^)]+)\\)", text: line).first {
                            let name = match.1.count > 1 ? (match.1[1] ?? "") : ""
                            let version = match.1.count > 2 ? (match.1[2] ?? "") : ""
                            if !name.isEmpty {
                                locked.append(["name": .string(name), "version": .string(version)])
                            }
                        }
                    }
                }
            }
            return .object([
                "tool": .string(tool),
                "path": .string(podfile),
                "platform": .string(platform),
                "targets": .array(targets.map { .string($0) }),
                "pods": .array(pods),
                "podCount": .int(Int64(pods.count)),
                "locked": .array(locked),
                "lockPresent": .bool(!locked.isEmpty),
            ])
        case "carthage_cartfile_inspector":
            let cartfile = try await Self.g6ResolveFile(cwd: cwd, path: path, query: "Cartfile", match: { $0.name == "Cartfile" || $0.path.hasSuffix("/Cartfile") }, tool: tool, runtime: runtime)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: cartfile)
            var dependencies: [[String: JSONValue]] = []
            for line in Self.g5Lines(document.content) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let match = Self.g5RegexMatches(pattern: "^(github|git|binary)\\s+\"([^\"]+)\"(?:\\s+\"([^\"]+)\")?", text: trimmed).first {
                    let source = match.1.count > 1 ? (match.1[1] ?? "") : ""
                    let name = match.1.count > 2 ? (match.1[2] ?? "") : ""
                    let requirement = match.1.count > 3 ? (match.1[3] ?? "") : ""
                    dependencies.append([
                        "source": .string(source),
                        "name": .string(name),
                        "requirement": .string(requirement),
                    ])
                }
            }
            var resolved: [[String: JSONValue]] = []
            let dir = (cartfile as NSString).deletingLastPathComponent
            let resolvedPath = dir.isEmpty ? "Cartfile.resolved" : dir + "/Cartfile.resolved"
            if let resolvedDoc = try? await runtime.readWorkspaceFile(cwd: cwd, path: resolvedPath) {
                for line in Self.g5Lines(resolvedDoc.content) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let match = Self.g5RegexMatches(pattern: "^(github|git|binary)\\s+\"([^\"]+)\"\\s+\"([^\"]+)\"", text: trimmed).first {
                        let source = match.1.count > 1 ? (match.1[1] ?? "") : ""
                        let name = match.1.count > 2 ? (match.1[2] ?? "") : ""
                        let version = match.1.count > 3 ? (match.1[3] ?? "") : ""
                        resolved.append([
                            "source": .string(source),
                            "name": .string(name),
                            "version": .string(version),
                        ])
                    }
                }
            }
            return .object([
                "tool": .string(tool),
                "path": .string(cartfile),
                "dependencies": .array(dependencies),
                "dependencyCount": .int(Int64(dependencies.count)),
                "resolved": .array(resolved),
                "resolvedPresent": .bool(!resolved.isEmpty),
            ])
        case "package_manifest_read":
            let manifestPath = path ?? "Package.swift"
            try Self.validateRelativePath(manifestPath, tool: tool)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: manifestPath)
            let manifest = Self.g6ParseManifest(document.content)
            return .object([
                "tool": .string(tool),
                "path": .string(manifestPath),
                "name": .string(manifest.name),
                "platforms": .array(manifest.platforms.map { .string($0) }),
                "products": .array(manifest.products.map { .string($0) }),
                "targets": .array(manifest.targets.map { .string($0) }),
                "dependencies": .array(manifest.dependencies.map { dep in
                    .object(dep.mapValues { .string($0) })
                }),
            ])
        case "package_dependency_add":
            let url = try requiredString(arguments, "url", tool: tool)
            let version = try requiredString(arguments, "version", tool: tool)
            let manifestPath = path ?? "Package.swift"
            try Self.validateRelativePath(manifestPath, tool: tool)
            guard url.hasPrefix("https://") || url.hasPrefix("git@") else {
                throw SystemToolError.executionFailed(tool: tool, message: "package_dependency_add url must be an https or git@ URL.")
            }
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: manifestPath)
            var content = document.content
            guard !content.contains(url) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Package.swift already references \(url).")
            }
            guard let depRange = content.range(of: "dependencies: [") else {
                throw SystemToolError.executionFailed(tool: tool, message: "Package.swift has no dependencies array.")
            }
            let insertion = "\n        .package(url: \"\(url)\", from: \"\(version)\"),"
            content.insert(contentsOf: insertion, at: depRange.upperBound)
            var wired = false
            var wiringNote = ""
            if let product = optionalString(arguments, "product"), let target = optionalString(arguments, "target") {
                let packageName = ((url as NSString).lastPathComponent as NSString).deletingPathExtension
                let escapedTarget = NSRegularExpression.escapedPattern(for: target)
                if let targetMatch = Self.g5RegexMatches(pattern: "\\.(target|executableTarget|testTarget)\\(\\s*name:\\s*\"\(escapedTarget)\"[^)]*?dependencies:\\s*\\[", text: content, options: [.dotMatchesLineSeparators]).first {
                    let afterStart = targetMatch.0.location + targetMatch.0.length
                    if let swiftRange = Range(NSRange(location: afterStart, length: (content as NSString).length - afterStart), in: content) {
                        let wiring = "\n            .product(name: \"\(product)\", package: \"\(packageName)\"),"
                        content.insert(contentsOf: wiring, at: swiftRange.lowerBound)
                        wired = true
                    } else {
                        wiringNote = "Target \(target) found but its dependencies array could not be located."
                    }
                } else {
                    wiringNote = "Target \(target) has no dependencies array to wire into."
                }
            }
            try await runtime.writeWorkspaceFile(cwd: cwd, path: manifestPath, content: content)
            let verify = try await runtime.readWorkspaceFile(cwd: cwd, path: manifestPath)
            let parsed = Self.g6ParseManifest(verify.content)
            guard parsed.dependencies.contains(where: { $0["url"] == url }) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Verification failed: the dependency is not present after writing.")
            }
            return .object([
                "tool": .string(tool),
                "path": .string(manifestPath),
                "url": .string(url),
                "version": .string(version),
                "added": .bool(true),
                "wired": .bool(wired),
                "wiringNote": .string(wiringNote),
            ])
        case "asset_catalog_list":
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            let catalogs = entries.filter { $0.isDirectory && $0.path.hasSuffix(".xcassets") }
            var out: [[String: JSONValue]] = []
            for catalog in catalogs {
                let prefix = catalog.path + "/"
                var counts: [String: Int] = ["image": 0, "color": 0, "icon": 0, "dataset": 0, "symbol": 0]
                var names: [String] = []
                for entry in entries where entry.isDirectory && entry.path.hasPrefix(prefix) {
                    let suffix = (entry.path as NSString).lastPathComponent
                    let kind: String?
                    if suffix.hasSuffix(".imageset") { kind = "image" }
                    else if suffix.hasSuffix(".colorset") { kind = "color" }
                    else if suffix.hasSuffix(".appiconset") { kind = "icon" }
                    else if suffix.hasSuffix(".dataset") { kind = "dataset" }
                    else if suffix.hasSuffix(".symbolset") { kind = "symbol" }
                    else { kind = nil }
                    if let kind {
                        counts[kind, default: 0] += 1
                        names.append(suffix)
                    }
                }
                out.append([
                    "catalog": .string(catalog.path),
                    "imageSets": .int(Int64(counts["image"] ?? 0)),
                    "colorSets": .int(Int64(counts["color"] ?? 0)),
                    "iconSets": .int(Int64(counts["icon"] ?? 0)),
                    "dataSets": .int(Int64(counts["dataset"] ?? 0)),
                    "symbolSets": .int(Int64(counts["symbol"] ?? 0)),
                    "sets": .array(names.map { .string($0) }),
                ])
            }
            return .object([
                "tool": .string(tool),
                "catalogs": .array(out),
                "catalogCount": .int(Int64(out.count)),
            ])
        case "asset_image_add":
            let imageName = try requiredString(arguments, "imageName", tool: name)
            let source = try requiredString(arguments, "source", tool: name)
            try Self.validateRelativePath(source, tool: name)
            guard !imageName.isEmpty, !imageName.contains("/"), !imageName.contains("\\") else {
                throw SystemToolError.executionFailed(tool: tool, message: "asset_image_add imageName must be a single name without a path separator.")
            }
            let catalog = try await Self.g6ResolveCatalog(cwd: cwd, catalog: optionalString(arguments, "catalog"), tool: tool, runtime: runtime)
            let setPath = catalog + "/" + imageName + ".imageset"
            try await runtime.createWorkspaceDirectory(cwd: cwd, path: setPath)
            let fileName = (source as NSString).lastPathComponent
            try await runtime.copyWorkspaceFile(cwd: cwd, path: source, destination: setPath + "/" + fileName)
            let contents: [String: Any] = [
                "images": [["filename": fileName, "idiom": "universal", "scale": "1x"]],
                "info": ["author": "xcode", "version": 1],
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Could not serialize the image set Contents.json.")
            }
            try Self.writeWorkspaceBytes(cwd: cwd, path: setPath + "/Contents.json", data: data, tool: name)
            let verify = try await runtime.readWorkspaceFile(cwd: cwd, path: setPath + "/Contents.json")
            return .object([
                "tool": .string(tool),
                "catalog": .string(catalog),
                "set": .string(setPath),
                "image": .string(fileName),
                "verified": .bool(verify.content.contains(fileName)),
            ])
        case "strings_localization":
            let filePath = try requiredString(arguments, "path", tool: tool)
            let action = try requiredString(arguments, "action", tool: tool)
            let key = try requiredString(arguments, "key", tool: tool)
            try Self.validateRelativePath(filePath, tool: tool)
            guard ["get", "set", "delete"].contains(action) else {
                throw SystemToolError.executionFailed(tool: tool, message: "strings_localization action must be get, set, or delete.")
            }
            if filePath.hasSuffix(".xcstrings") {
                let document = try await runtime.readWorkspaceFile(cwd: cwd, path: filePath)
                var catalog = try Self.g6XcstringsDecode(document.content, tool: tool)
                let locale = optionalString(arguments, "locale") ?? catalog["sourceLanguage"]?.stringValue ?? "en"
                let keys = Self.g6XcstringsKeys(catalog)
                switch action {
                case "get":
                    let value = keys[key]?[locale]
                    return .object([
                        "tool": .string(tool),
                        "path": .string(filePath),
                        "key": .string(key),
                        "locale": .string(locale),
                        "found": .bool(value != nil),
                        "value": value.map { .string($0) } ?? .null,
                    ])
                case "set":
                    let value = try requiredString(arguments, "value", tool: tool)
                    catalog = Self.g6XcstringsSet(catalog, key: key, locale: locale, value: value, state: "translated")
                    let text = try Self.g6XcstringsEncode(catalog, tool: tool)
                    try await runtime.writeWorkspaceFile(cwd: cwd, path: filePath, content: text)
                    return .object([
                        "tool": .string(tool),
                        "path": .string(filePath),
                        "key": .string(key),
                        "locale": .string(locale),
                        "value": .string(value),
                        "updated": .bool(true),
                    ])
                default:
                    var strings = catalog["strings"]?.objectValue ?? [:]
                    guard strings[key] != nil else {
                        throw SystemToolError.executionFailed(tool: tool, message: "Key \(key) not found in \(filePath).")
                    }
                    var entry = strings[key]?.objectValue ?? [:]
                    var localizations = entry["localizations"]?.objectValue ?? [:]
                    localizations.removeValue(forKey: locale)
                    entry["localizations"] = .object(localizations)
                    strings[key] = .object(entry)
                    catalog["strings"] = .object(strings)
                    let text = try Self.g6XcstringsEncode(catalog, tool: tool)
                    try await runtime.writeWorkspaceFile(cwd: cwd, path: filePath, content: text)
                    return .object([
                        "tool": .string(tool),
                        "path": .string(filePath),
                        "key": .string(key),
                        "locale": .string(locale),
                        "deleted": .bool(true),
                    ])
                }
            }
            guard filePath.hasSuffix(".strings") else {
                throw SystemToolError.executionFailed(tool: tool, message: "strings_localization path must end in .strings or .xcstrings.")
            }
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: filePath)
            var pairs = Self.g6StringsPairs(document.content)
            switch action {
            case "get":
                let found = pairs.first { $0.key == key }
                return .object([
                    "tool": .string(tool),
                    "path": .string(filePath),
                    "key": .string(key),
                    "found": .bool(found != nil),
                    "value": found.map { .string($0.value) } ?? .null,
                ])
            case "set":
                let value = try requiredString(arguments, "value", tool: tool)
                if let index = pairs.firstIndex(where: { $0.key == key }) {
                    pairs[index] = (key: key, value: value, line: pairs[index].line)
                } else {
                    pairs.append((key: key, value: value, line: pairs.count + 1))
                }
                try await runtime.writeWorkspaceFile(cwd: cwd, path: filePath, content: Self.g6SerializeStrings(pairs.map { (key: $0.key, value: $0.value) }))
                return .object([
                    "tool": .string(tool),
                    "path": .string(filePath),
                    "key": .string(key),
                    "value": .string(value),
                    "updated": .bool(true),
                ])
            default:
                guard pairs.contains(where: { $0.key == key }) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Key \(key) not found in \(filePath).")
                }
                pairs.removeAll { $0.key == key }
                try await runtime.writeWorkspaceFile(cwd: cwd, path: filePath, content: Self.g6SerializeStrings(pairs.map { (key: $0.key, value: $0.value) }))
                return .object([
                    "tool": .string(tool),
                    "path": .string(filePath),
                    "key": .string(key),
                    "deleted": .bool(true),
                ])
            }
        case "localization_audit":
            let stringsFiles = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".strings"], limit: 200, runtime: runtime)
            let catalogFiles = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".xcstrings"], limit: 50, runtime: runtime)
            var keysByLocale: [String: Set<String>] = [:]
            var allKeys: Set<String> = []
            for file in stringsFiles {
                let locale = Self.g6LocaleForStringsPath(file.path)
                let keys = Set(Self.g6StringsPairs(file.content).map { $0.key })
                keysByLocale[locale, default: []].formUnion(keys)
                allKeys.formUnion(keys)
            }
            for file in catalogFiles {
                if let catalog = try? Self.g6XcstringsDecode(file.content, tool: tool) {
                    for (key, locales) in Self.g6XcstringsKeys(catalog) {
                        allKeys.insert(key)
                        for locale in locales.keys {
                            keysByLocale[locale, default: []].insert(key)
                        }
                    }
                }
            }
            var missing: [[String: JSONValue]] = []
            for locale in keysByLocale.keys.sorted() {
                let absent = allKeys.subtracting(keysByLocale[locale] ?? []).sorted()
                if !absent.isEmpty {
                    missing.append(["locale": .string(locale), "missingKeys": .array(absent.map { .string($0) })])
                }
            }
            let swiftFiles = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 100, runtime: runtime)
            var unreferenced: [String] = []
            for key in allKeys.sorted() {
                let referenced = swiftFiles.contains { $0.content.contains("\"\(key)\"") || $0.content.contains("NSLocalizedString(\"\(key)\"") }
                if !referenced {
                    unreferenced.append(key)
                }
                if unreferenced.count >= limit { break }
            }
            return .object([
                "tool": .string(tool),
                "locales": .array(keysByLocale.keys.sorted().map { .string($0) }),
                "totalKeys": .int(Int64(allKeys.count)),
                "missing": .array(missing),
                "unreferencedKeys": .array(unreferenced.map { .string($0) }),
            ])
        case "localize_app":
            let action = try requiredString(arguments, "action", tool: tool)
            guard ["localize", "status", "set_development_region"].contains(action) else {
                throw SystemToolError.executionFailed(tool: tool, message: "localize_app action must be localize, status, or set_development_region.")
            }
            let catalogPath = "Localizable.xcstrings"
            if action == "status" {
                if let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: catalogPath),
                   let catalog = try? Self.g6XcstringsDecode(document.content, tool: tool) {
                    let keys = Self.g6XcstringsKeys(catalog)
                    return .object([
                        "tool": .string(tool),
                        "action": .string(action),
                        "exists": .bool(true),
                        "sourceLanguage": catalog["sourceLanguage"]?.stringValue.map { .string($0) } ?? .null,
                        "keyCount": .int(Int64(keys.count)),
                        "locales": .array(Array(Set(keys.values.flatMap { $0.keys })).sorted().map { .string($0) }),
                    ])
                }
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "exists": .bool(false),
                    "keyCount": .int(0),
                    "locales": .array([]),
                ])
            }
            if action == "set_development_region" {
                let region = try requiredString(arguments, "developmentRegion", tool: tool)
                let plistPath = try await Self.g6ResolveFile(cwd: cwd, path: nil, query: "Info.plist", match: { $0.name == "Info.plist" }, tool: tool, runtime: runtime)
                var plist = try await Self.g6ReadPlist(cwd: cwd, path: plistPath, tool: tool, runtime: runtime)
                plist["CFBundleDevelopmentRegion"] = region
                try Self.g6WritePlist(cwd: cwd, path: plistPath, dict: plist, tool: tool)
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "path": .string(plistPath),
                    "developmentRegion": .string(region),
                    "updated": .bool(true),
                ])
            }
            guard let languages = optionalStringArray(arguments, "languages"), !languages.isEmpty, languages.count <= 3 else {
                throw SystemToolError.executionFailed(tool: tool, message: "localize_app localize requires languages with 1 to 3 language codes.")
            }
            var translations: [String: [String: String]] = [:]
            if let rawTranslations = arguments["translations"]?.arrayValue {
                for raw in rawTranslations {
                    guard let locale = raw["locale"]?.stringValue, let key = raw["key"]?.stringValue, let value = raw["value"]?.stringValue else {
                        throw SystemToolError.missingArgument(tool: tool, argument: "translations")
                    }
                    translations[locale, default: [:]][key] = value
                }
            }
            let swiftFiles = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 200, runtime: runtime)
            var keys: Set<String> = []
            for file in swiftFiles {
                for match in Self.g5RegexMatches(pattern: "NSLocalizedString\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"", text: file.content) {
                    if let key = match.1.count > 1 ? match.1[1] : nil, !key.isEmpty {
                        keys.insert(Self.g6StringsUnescape(key))
                    }
                }
                for match in Self.g5RegexMatches(pattern: "String\\(localized:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"", text: file.content) {
                    if let key = match.1.count > 1 ? match.1[1] : nil, !key.isEmpty {
                        keys.insert(Self.g6StringsUnescape(key))
                    }
                }
            }
            var catalog: [String: JSONValue] = ["sourceLanguage": .string("en"), "strings": .object([:]), "version": .string("1.0")]
            if let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: catalogPath),
               let existing = try? Self.g6XcstringsDecode(document.content, tool: tool) {
                catalog = existing
            }
            let sourceLanguage = catalog["sourceLanguage"]?.stringValue ?? "en"
            var keysAdded = 0
            var layoutDirection = "ltr"
            if languages.contains(where: { ["ar", "he", "fa", "ur"].contains($0.lowercased()) }) {
                layoutDirection = "rtl"
            }
            for key in keys.sorted() {
                let existing = Self.g6XcstringsKeys(catalog)[key]
                if existing == nil {
                    keysAdded += 1
                }
                catalog = Self.g6XcstringsSet(catalog, key: key, locale: sourceLanguage, value: key, state: "translated")
                for language in languages {
                    if let translated = translations[language]?[key] {
                        catalog = Self.g6XcstringsSet(catalog, key: key, locale: language, value: translated, state: "translated")
                    } else if Self.g6XcstringsKeys(catalog)[key]?[language] == nil {
                        catalog = Self.g6XcstringsSet(catalog, key: key, locale: language, value: key, state: "new")
                    }
                }
            }
            let text = try Self.g6XcstringsEncode(catalog, tool: tool)
            try await runtime.writeWorkspaceFile(cwd: cwd, path: catalogPath, content: text)
            if let plistPath = try? await Self.g6ResolveFile(cwd: cwd, path: nil, query: "Info.plist", match: { $0.name == "Info.plist" }, tool: tool, runtime: runtime),
               var plist = try? await Self.g6ReadPlist(cwd: cwd, path: plistPath, tool: tool, runtime: runtime) {
                plist["CFBundleLocalizations"] = languages
                if plist["CFBundleDevelopmentRegion"] == nil {
                    plist["CFBundleDevelopmentRegion"] = sourceLanguage
                }
                try? Self.g6WritePlist(cwd: cwd, path: plistPath, dict: plist, tool: tool)
            }
            return .object([
                "tool": .string(tool),
                "action": .string(action),
                "languages": .array(languages.map { .string($0) }),
                "layoutDirection": .string(layoutDirection),
                "sourceLanguage": .string(sourceLanguage),
                "keysAdded": .int(Int64(keysAdded)),
                "catalog": .string(catalogPath),
            ])
        case "asset_catalog_manager":
            let action = try requiredString(arguments, "action", tool: tool)
            switch action {
            case "list":
                let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
                let catalogs = entries.filter { $0.isDirectory && $0.path.hasSuffix(".xcassets") }.map { $0.path }
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "catalogs": .array(catalogs.map { .string($0) }),
                    "catalogCount": .int(Int64(catalogs.count)),
                ])
            case "inspect":
                let setName = try requiredString(arguments, "name", tool: tool)
                let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
                guard let set = entries.first(where: { $0.isDirectory && ($0.path as NSString).lastPathComponent == setName }) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "No asset set named \(setName) found.")
                }
                let contentsPath = set.path + "/Contents.json"
                let document = try await runtime.readWorkspaceFile(cwd: cwd, path: contentsPath)
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "set": .string(set.path),
                    "contents": .string(document.content),
                ])
            case "create_imageset":
                let imageName = try requiredString(arguments, "name", tool: tool)
                let source = try requiredString(arguments, "source", tool: tool)
                try Self.validateRelativePath(source, tool: tool)
                let catalog = try await Self.g6ResolveCatalog(cwd: cwd, catalog: optionalString(arguments, "catalog"), tool: tool, runtime: runtime)
                let setPath = catalog + "/" + imageName + ".imageset"
                try await runtime.createWorkspaceDirectory(cwd: cwd, path: setPath)
                let fileName = (source as NSString).lastPathComponent
                try await runtime.copyWorkspaceFile(cwd: cwd, path: source, destination: setPath + "/" + fileName)
                let contents: [String: Any] = [
                    "images": [["filename": fileName, "idiom": "universal", "scale": "1x"]],
                    "info": ["author": "xcode", "version": 1],
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Could not serialize the image set Contents.json.")
                }
                try Self.writeWorkspaceBytes(cwd: cwd, path: setPath + "/Contents.json", data: data, tool: name)
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "set": .string(setPath),
                    "image": .string(fileName),
                    "created": .bool(true),
                ])
            case "create_colorset":
                let colorName = try requiredString(arguments, "name", tool: tool)
                let lightHex = try requiredString(arguments, "lightHex", tool: tool)
                let darkHex = optionalString(arguments, "darkHex") ?? lightHex
                let catalog = try await Self.g6ResolveCatalog(cwd: cwd, catalog: optionalString(arguments, "catalog"), tool: tool, runtime: runtime)
                let setPath = catalog + "/" + colorName + ".colorset"
                try await runtime.createWorkspaceDirectory(cwd: cwd, path: setPath)
                let contents = Self.g6ColorsetContents(lightHex: lightHex, darkHex: darkHex)
                guard let data = try? JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Could not serialize the color set Contents.json.")
                }
                try Self.writeWorkspaceBytes(cwd: cwd, path: setPath + "/Contents.json", data: data, tool: name)
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "set": .string(setPath),
                    "created": .bool(true),
                ])
            default:
                throw SystemToolError.executionFailed(tool: tool, message: "asset_catalog_manager action must be list, inspect, create_imageset, or create_colorset.")
            }
        case "localization_manager":
            let action = try requiredString(arguments, "action", tool: tool)
            switch action {
            case "list":
                let stringsFiles = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".strings"], limit: 200, runtime: runtime)
                let catalogFiles = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".xcstrings"], limit: 50, runtime: runtime)
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "stringsFiles": .array(stringsFiles.map { .string($0.path) }),
                    "catalogs": .array(catalogFiles.map { .string($0.path) }),
                ])
            case "extract":
                let stringsFiles = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".strings"], limit: 200, runtime: runtime)
                let catalogFiles = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".xcstrings"], limit: 50, runtime: runtime)
                var keys: [String: [String: String]] = [:]
                for file in stringsFiles {
                    for pair in Self.g6StringsPairs(file.content) {
                        keys[pair.key, default: [:]][Self.g6LocaleForStringsPath(file.path)] = pair.value
                    }
                }
                for file in catalogFiles {
                    if let catalog = try? Self.g6XcstringsDecode(file.content, tool: tool) {
                        for (key, locales) in Self.g6XcstringsKeys(catalog) {
                            for (locale, value) in locales {
                                keys[key, default: [:]][locale] = value
                            }
                        }
                    }
                }
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "keys": .object(keys.mapValues { locales in
                        .object(locales.mapValues { .string($0) })
                    }),
                    "keyCount": .int(Int64(keys.count)),
                ])
            case "add":
                let key = try requiredString(arguments, "key", tool: tool)
                let value = try requiredString(arguments, "value", tool: tool)
                let filePath = try requiredString(arguments, "path", tool: tool)
                try Self.validateRelativePath(filePath, tool: tool)
                if filePath.hasSuffix(".xcstrings") {
                    let document = try await runtime.readWorkspaceFile(cwd: cwd, path: filePath)
                    var catalog = try Self.g6XcstringsDecode(document.content, tool: tool)
                    let locale = optionalString(arguments, "locale") ?? catalog["sourceLanguage"]?.stringValue ?? "en"
                    catalog = Self.g6XcstringsSet(catalog, key: key, locale: locale, value: value, state: "translated")
                    let text = try Self.g6XcstringsEncode(catalog, tool: tool)
                    try await runtime.writeWorkspaceFile(cwd: cwd, path: filePath, content: text)
                    return .object([
                        "tool": .string(tool),
                        "action": .string(action),
                        "path": .string(filePath),
                        "key": .string(key),
                        "locale": .string(locale),
                        "updated": .bool(true),
                    ])
                }
                guard filePath.hasSuffix(".strings") else {
                    throw SystemToolError.executionFailed(tool: tool, message: "localization_manager add path must end in .strings or .xcstrings.")
                }
                let document = try await runtime.readWorkspaceFile(cwd: cwd, path: filePath)
                var pairs = Self.g6StringsPairs(document.content)
                if let index = pairs.firstIndex(where: { $0.key == key }) {
                    pairs[index] = (key: key, value: value, line: pairs[index].line)
                } else {
                    pairs.append((key: key, value: value, line: pairs.count + 1))
                }
                try await runtime.writeWorkspaceFile(cwd: cwd, path: filePath, content: Self.g6SerializeStrings(pairs.map { (key: $0.key, value: $0.value) }))
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "path": .string(filePath),
                    "key": .string(key),
                    "updated": .bool(true),
                ])
            case "validate":
                return try await Self.runG5StringsValidate(tool: tool, cwd: cwd, path: path, limit: limit, runtime: runtime)
            default:
                throw SystemToolError.executionFailed(tool: tool, message: "localization_manager action must be list, extract, add, or validate.")
            }
        case "entitlements_manager":
            let action = try requiredString(arguments, "action", tool: tool)
            let entitlementsPath = try await Self.g6ResolveFile(cwd: cwd, path: path, query: ".entitlements", match: { $0.path.hasSuffix(".entitlements") }, tool: tool, runtime: runtime)
            try Self.validateRelativePath(entitlementsPath, tool: tool)
            var plist = try await Self.g6ReadPlist(cwd: cwd, path: entitlementsPath, tool: tool, runtime: runtime)
            switch action {
            case "list":
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "path": .string(entitlementsPath),
                    "entitlements": Self.plistJSONValue(plist),
                ])
            case "add":
                let key = try requiredString(arguments, "key", tool: tool)
                let value = try requiredString(arguments, "value", tool: tool)
                plist[key] = Self.g6PlistScalar(value)
                try Self.g6WritePlist(cwd: cwd, path: entitlementsPath, dict: plist, tool: tool)
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "path": .string(entitlementsPath),
                    "key": .string(key),
                    "updated": .bool(true),
                ])
            case "remove":
                let key = try requiredString(arguments, "key", tool: tool)
                guard plist[key] != nil else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Entitlement \(key) not present in \(entitlementsPath).")
                }
                plist.removeValue(forKey: key)
                try Self.g6WritePlist(cwd: cwd, path: entitlementsPath, dict: plist, tool: tool)
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "path": .string(entitlementsPath),
                    "key": .string(key),
                    "removed": .bool(true),
                ])
            default:
                throw SystemToolError.executionFailed(tool: tool, message: "entitlements_manager action must be list, add, or remove.")
            }
        case "colorset_builder":
            let colorName = try requiredString(arguments, "name", tool: name)
            let lightHex = try requiredString(arguments, "lightHex", tool: tool)
            let darkHex = optionalString(arguments, "darkHex") ?? lightHex
            guard !colorName.contains("/"), !colorName.isEmpty else {
                throw SystemToolError.executionFailed(tool: tool, message: "colorset_builder name must be a single name without a path separator.")
            }
            for hex in [lightHex, darkHex] {
                guard hex.hasPrefix("#"), hex.count == 7, hex.dropFirst().allSatisfy({ $0.isHexDigit }) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Color hex must be #RRGGBB, for example #FF8800.")
                }
            }
            let catalog = try await Self.g6ResolveCatalog(cwd: cwd, catalog: optionalString(arguments, "catalog"), tool: tool, runtime: runtime)
            let setPath = catalog + "/" + colorName + ".colorset"
            try await runtime.createWorkspaceDirectory(cwd: cwd, path: setPath)
            let contents = Self.g6ColorsetContents(lightHex: lightHex, darkHex: darkHex)
            guard let data = try? JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]) else {
                throw SystemToolError.executionFailed(tool: tool, message: "Could not serialize the color set Contents.json.")
            }
            try Self.writeWorkspaceBytes(cwd: cwd, path: setPath + "/Contents.json", data: data, tool: name)
            let verify = try await runtime.readWorkspaceFile(cwd: cwd, path: setPath + "/Contents.json")
            let lightRed = Int(lightHex.dropFirst().prefix(2), radix: 16) ?? 0
            let expectedRed = String(format: "%.3f", Double(lightRed) / 255.0)
            return .object([
                "tool": .string(tool),
                "set": .string(setPath),
                "lightHex": .string(lightHex),
                "darkHex": .string(darkHex),
                "verified": .bool(verify.content.contains(expectedRed)),
            ])
        case "project_entitlements":
            let entitlementsPath = try await Self.g6ResolveFile(cwd: cwd, path: path, query: ".entitlements", match: { $0.path.hasSuffix(".entitlements") }, tool: tool, runtime: runtime)
            try Self.validateRelativePath(entitlementsPath, tool: tool)
            let plist = try await Self.g6ReadPlist(cwd: cwd, path: entitlementsPath, tool: tool, runtime: runtime)
            return .object([
                "tool": .string(tool),
                "path": .string(entitlementsPath),
                "entitlements": Self.plistJSONValue(plist),
            ])
        case "project_info_plist":
            let action = try requiredString(arguments, "action", tool: tool)
            let plistPath = try await Self.g6ResolveFile(cwd: cwd, path: path, query: "Info.plist", match: { $0.name == "Info.plist" }, tool: tool, runtime: runtime)
            try Self.validateRelativePath(plistPath, tool: tool)
            var plist = try await Self.g6ReadPlist(cwd: cwd, path: plistPath, tool: tool, runtime: runtime)
            switch action {
            case "get":
                let key = try requiredString(arguments, "key", tool: tool)
                if let value = plist[key] {
                    return .object([
                        "tool": .string(tool),
                        "path": .string(plistPath),
                        "key": .string(key),
                        "found": .bool(true),
                        "value": Self.plistJSONValue(value),
                    ])
                }
                return .object([
                    "tool": .string(tool),
                    "path": .string(plistPath),
                    "key": .string(key),
                    "found": .bool(false),
                    "value": .null,
                ])
            case "set":
                let key = try requiredString(arguments, "key", tool: tool)
                let value = try requiredString(arguments, "value", tool: tool)
                plist[key] = Self.g6PlistScalar(value)
                try Self.g6WritePlist(cwd: cwd, path: plistPath, dict: plist, tool: tool)
                return .object([
                    "tool": .string(tool),
                    "path": .string(plistPath),
                    "key": .string(key),
                    "value": .string(value),
                    "updated": .bool(true),
                ])
            case "delete":
                let key = try requiredString(arguments, "key", tool: tool)
                guard plist[key] != nil else {
                    throw SystemToolError.executionFailed(tool: tool, message: "Key \(key) not present in \(plistPath).")
                }
                plist.removeValue(forKey: key)
                try Self.g6WritePlist(cwd: cwd, path: plistPath, dict: plist, tool: tool)
                return .object([
                    "tool": .string(tool),
                    "path": .string(plistPath),
                    "key": .string(key),
                    "deleted": .bool(true),
                ])
            default:
                throw SystemToolError.executionFailed(tool: tool, message: "project_info_plist action must be get, set, or delete.")
            }
        case "project_capabilities":
            let action = try requiredString(arguments, "action", tool: tool)
            let entitlementsPath = try await Self.g6ResolveFile(cwd: cwd, path: path, query: ".entitlements", match: { $0.path.hasSuffix(".entitlements") }, tool: tool, runtime: runtime)
            try Self.validateRelativePath(entitlementsPath, tool: tool)
            var plist = try await Self.g6ReadPlist(cwd: cwd, path: entitlementsPath, tool: tool, runtime: runtime)
            let supported: [String: String] = [
                "app-sandbox": "com.apple.security.app-sandbox",
                "network-client": "com.apple.security.network.client",
                "network-server": "com.apple.security.network.server",
                "files-user-selected-read-only": "com.apple.security.files.user-selected.read-only",
                "files-user-selected-read-write": "com.apple.security.files.user-selected.read-write",
                "files-downloads-read-only": "com.apple.security.files.downloads.read-only",
                "files-downloads-read-write": "com.apple.security.files.downloads.read-write",
                "audio-input": "com.apple.security.device.audio-input",
                "camera": "com.apple.security.device.camera",
                "usb": "com.apple.security.device.usb",
                "bluetooth": "com.apple.security.device.bluetooth",
                "printing": "com.apple.security.print",
            ]
            if action == "list" {
                var enabled: [String] = []
                var disabled: [String] = []
                var present: [[String: JSONValue]] = []
                for (capability, key) in supported.sorted(by: { $0.key < $1.key }) {
                    if let value = plist[key] as? Bool, value {
                        enabled.append(capability)
                    } else {
                        disabled.append(capability)
                    }
                }
                for key in plist.keys.sorted() where supported.values.contains(key) == false {
                    present.append(["key": .string(key), "value": plist[key].map { Self.plistJSONValue($0) } ?? .null])
                }
                return .object([
                    "tool": .string(tool),
                    "action": .string(action),
                    "path": .string(entitlementsPath),
                    "enabled": .array(enabled.map { .string($0) }),
                    "disabled": .array(disabled.map { .string($0) }),
                    "otherEntitlements": .array(present),
                ])
            }
            guard ["enable", "disable"].contains(action) else {
                throw SystemToolError.executionFailed(tool: tool, message: "project_capabilities action must be list, enable, or disable.")
            }
            let capability = try requiredString(arguments, "capability", tool: tool)
            guard let key = supported[capability] else {
                throw SystemToolError.executionFailed(tool: tool, message: "Capability \(capability) is not a boolean entitlement capability. Supported: \(supported.keys.sorted().joined(separator: ", ")).")
            }
            plist[key] = (action == "enable")
            try Self.g6WritePlist(cwd: cwd, path: entitlementsPath, dict: plist, tool: tool)
            return .object([
                "tool": .string(tool),
                "action": .string(action),
                "path": .string(entitlementsPath),
                "capability": .string(capability),
                "key": .string(key),
                "enabled": .bool(action == "enable"),
            ])
        case "entry_points_discover":
            let mainHits = try await runtime.searchWorkspaceRegex(cwd: cwd, pattern: "@main", limit: limit)
            let delegateHits = try await runtime.searchWorkspaceRegex(cwd: cwd, pattern: "(class|struct)\\s+([A-Za-z0-9_]*(AppDelegate|SceneDelegate)[A-Za-z0-9_]*)", limit: limit)
            let scoped = { (hits: [WorkspaceSearchHit]) in
                hits.filter { hit in
                    guard let path, !path.isEmpty else { return true }
                    return hit.path == path || hit.path.hasPrefix(path + "/")
                }
            }
            var entries: [[String: JSONValue]] = []
            for hit in scoped(mainHits) {
                entries.append(["kind": .string("main"), "path": .string(hit.path), "lineNumber": .int(Int64(hit.lineNumber)), "lineText": .string(hit.lineText)])
            }
            for hit in scoped(delegateHits) {
                entries.append(["kind": .string("delegate"), "path": .string(hit.path), "lineNumber": .int(Int64(hit.lineNumber)), "lineText": .string(hit.lineText)])
            }
            let mainFiles = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            for entry in mainFiles where !entry.isDirectory && entry.name == "main.swift" {
                entries.append(["kind": .string("mainSwift"), "path": .string(entry.path), "lineNumber": .int(1), "lineText": .string("main.swift")])
            }
            return .object([
                "tool": .string(tool),
                "entryPoints": .array(entries),
                "count": .int(Int64(entries.count)),
            ])
        case "repo_overview":
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            let files = entries.filter { !$0.isDirectory }
            var byLanguage: [String: (count: Int, bytes: Int64)] = [:]
            for file in files {
                let ext = (file.path as NSString).pathExtension.lowercased()
                let language = Self.g6LanguageForExtension(ext)
                var slot = byLanguage[language] ?? (count: 0, bytes: 0)
                slot.count += 1
                slot.bytes += file.sizeBytes ?? 0
                byLanguage[language] = slot
            }
            let largest = files.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }.prefix(10).map { file in
                .object(["path": .string(file.path), "bytes": .int(file.sizeBytes ?? 0)])
            }
            let names = Set(files.map { $0.name.lowercased() })
            return .object([
                "tool": .string(tool),
                "fileCount": .int(Int64(files.count)),
                "directoryCount": .int(Int64(entries.count - files.count)),
                "languages": .array(byLanguage.keys.sorted().map { language in
                    .object([
                        "language": .string(language),
                        "files": .int(Int64(byLanguage[language]?.count ?? 0)),
                        "bytes": .int(byLanguage[language]?.bytes ?? 0),
                    ])
                }),
                "hasReadme": .bool(names.contains { $0.hasPrefix("readme") }),
                "hasLicense": .bool(names.contains { $0.hasPrefix("license") }),
                "largestFiles": .array(largest),
            ])
        case "project_structure_map":
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            var directories: [String: Int] = [:]
            for entry in entries where !entry.isDirectory {
                let dir = (entry.path as NSString).deletingLastPathComponent
                directories[dir, default: 0] += 1
            }
            var targets: [String] = []
            if let pbxproj = try? await Self.g5ResolvePbxproj(tool: tool, cwd: cwd, path: nil, runtime: runtime),
               let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: pbxproj) {
                targets = Self.g6PbxprojTargets(document.content)
            }
            return .object([
                "tool": .string(tool),
                "directories": .array(directories.keys.sorted().map { dir in
                    .object(["path": .string(dir), "files": .int(Int64(directories[dir] ?? 0))])
                }),
                "targets": .array(targets.map { .string($0) }),
            ])
        case "recent_changes":
            let hours = min(max(optionalInt(arguments, "hours") ?? 24, 1), 24 * 365)
            let cutoff = Date().timeIntervalSince1970 - Double(hours) * 3600
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            let changed = entries.filter { !$0.isDirectory && ($0.modifiedAt ?? 0) >= cutoff }
                .sorted { ($0.modifiedAt ?? 0) > ($1.modifiedAt ?? 0) }
                .prefix(limit)
                .map { entry in
                    .object([
                        "path": .string(entry.path),
                        "modifiedAt": .double(entry.modifiedAt ?? 0),
                        "sizeBytes": .int(entry.sizeBytes ?? 0),
                    ])
                }
            return .object([
                "tool": .string(tool),
                "hours": .int(Int64(hours)),
                "files": .array(changed),
                "count": .int(Int64(changed.count)),
            ])
        case "readme_locate":
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            var readmes: [[String: JSONValue]] = []
            for entry in entries where !entry.isDirectory && entry.name.lowercased().hasPrefix("readme") {
                var title = ""
                if let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: entry.path) {
                    for line in Self.g5Lines(document.content) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("# ") {
                            title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                            break
                        }
                    }
                }
                readmes.append(["path": .string(entry.path), "title": .string(title)])
            }
            return .object([
                "tool": .string(tool),
                "readmes": .array(readmes),
                "count": .int(Int64(readmes.count)),
            ])
        case "dependency_licenses":
            var dependencies: [[String: JSONValue]] = []
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            if let resolvedEntry = entries.first(where: { !$0.isDirectory && $0.name == "Package.resolved" }),
               let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: resolvedEntry.path) {
                for pin in Self.g6ParseResolved(document.content) {
                    dependencies.append([
                        "name": .string(pin["identity"] ?? ""),
                        "version": .string(pin["version"] ?? ""),
                        "source": .string("Package.resolved"),
                        "location": .string(pin["location"] ?? ""),
                    ])
                }
            }
            if let lockEntry = entries.first(where: { !$0.isDirectory && $0.name == "Podfile.lock" }),
               let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: lockEntry.path) {
                var inPods = false
                for line in Self.g5Lines(document.content) {
                    if line.hasPrefix("PODS:") { inPods = true; continue }
                    if inPods {
                        if line.isEmpty || (!line.hasPrefix(" ") && !line.hasPrefix("\t")) { break }
                        if let match = Self.g5RegexMatches(pattern: "^\\s*-\\s*([A-Za-z0-9_./-]+) \\(([^)]+)\\)", text: line).first {
                            let name = match.1.count > 1 ? (match.1[1] ?? "") : ""
                            let version = match.1.count > 2 ? (match.1[2] ?? "") : ""
                            if !name.isEmpty {
                                dependencies.append([
                                    "name": .string(name),
                                    "version": .string(version),
                                    "source": .string("Podfile.lock"),
                                    "location": .string(""),
                                ])
                            }
                        }
                    }
                }
            }
            let hasLicense = entries.contains { !$0.isDirectory && $0.name.lowercased().hasPrefix("license") }
            return .object([
                "tool": .string(tool),
                "dependencies": .array(dependencies),
                "count": .int(Int64(dependencies.count)),
                "hasLicenseFile": .bool(hasLicense),
                "note": .string("License text is not stored in Package.resolved or Podfile.lock; check each package LICENSE file for the license terms."),
            ])
        case "stale_files_report":
            let days = min(max(optionalInt(arguments, "days") ?? 180, 1), 3650)
            let cutoff = Date().timeIntervalSince1970 - Double(days) * 86400
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            let stale = entries.filter { entry in
                guard !entry.isDirectory, let modified = entry.modifiedAt else { return false }
                let ext = (entry.path as NSString).pathExtension.lowercased()
                return modified < cutoff && ["swift", "m", "mm", "h", "c", "cpp", "ts", "tsx", "js", "jsx", "py", "rs", "kt", "java"].contains(ext)
            }
            .sorted { ($0.modifiedAt ?? 0) < ($1.modifiedAt ?? 0) }
            .prefix(limit)
            .map { entry in
                .object([
                    "path": .string(entry.path),
                    "modifiedAt": .double(entry.modifiedAt ?? 0),
                    "sizeBytes": .int(entry.sizeBytes ?? 0),
                ])
            }
            return .object([
                "tool": .string(tool),
                "days": .int(Int64(days)),
                "files": .array(stale),
                "count": .int(Int64(stale.count)),
            ])
        case "file_type_breakdown":
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            var byExtension: [String: (count: Int, bytes: Int64)] = [:]
            for entry in entries where !entry.isDirectory {
                let ext = (entry.path as NSString).pathExtension.lowercased()
                let key = ext.isEmpty ? "(none)" : "." + ext
                var slot = byExtension[key] ?? (count: 0, bytes: 0)
                slot.count += 1
                slot.bytes += entry.sizeBytes ?? 0
                byExtension[key] = slot
            }
            return .object([
                "tool": .string(tool),
                "types": .array(byExtension.keys.sorted().map { ext in
                    .object([
                        "extension": .string(ext),
                        "files": .int(Int64(byExtension[ext]?.count ?? 0)),
                        "bytes": .int(byExtension[ext]?.bytes ?? 0),
                    ])
                }),
            ])
        case "empty_dirs_find":
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            var children: [String: Int] = [:]
            for entry in entries {
                let dir = (entry.path as NSString).deletingLastPathComponent
                if !dir.isEmpty {
                    children[dir, default: 0] += 1
                }
            }
            let empty = entries.filter { entry in
                entry.isDirectory && (children[entry.path] ?? 0) == 0
            }.map { $0.path }
            return .object([
                "tool": .string(tool),
                "emptyDirectories": .array(empty.map { .string($0) }),
                "count": .int(Int64(empty.count)),
            ])
        case "symlink_audit":
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            var links: [[String: JSONValue]] = []
            for entry in entries where entry.isSymlink == true {
                let target = entry.symlinkTarget ?? ""
                var broken = false
                if !target.isEmpty {
                    let base = URL(fileURLWithPath: ExternalEditorService.expandedPath(cwd))
                    let resolved: URL
                    if target.hasPrefix("/") {
                        resolved = URL(fileURLWithPath: target)
                    } else {
                        resolved = base.appendingPathComponent((entry.path as NSString).deletingLastPathComponent).appendingPathComponent(target)
                    }
                    broken = !FileManager.default.fileExists(atPath: resolved.standardized.path)
                }
                links.append([
                    "path": .string(entry.path),
                    "target": .string(target),
                    "broken": .bool(broken),
                ])
            }
            return .object([
                "tool": .string(tool),
                "links": .array(links),
                "count": .int(Int64(links.count)),
                "brokenCount": .int(Int64(links.filter { $0["broken"]?.boolValue == true }.count)),
            ])
        case "executable_files_scan":
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            let executables = entries.filter { !$0.isDirectory && $0.isExecutable == true }.map { entry in
                .object([
                    "path": .string(entry.path),
                    "sizeBytes": .int(entry.sizeBytes ?? 0),
                ])
            }
            return .object([
                "tool": .string(tool),
                "executables": .array(executables),
                "count": .int(Int64(executables.count)),
            ])
        case "dir_size_report":
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            let root = path ?? ""
            var totals: [String: Int64] = [:]
            var fileCounts: [String: Int] = [:]
            for entry in entries where !entry.isDirectory {
                let relative = root.isEmpty ? entry.path : String(entry.path.dropFirst(root.count + 1))
                let top = relative.split(separator: "/").first.map(String.init) ?? "(root)"
                totals[top, default: 0] += entry.sizeBytes ?? 0
                fileCounts[top, default: 0] += 1
            }
            let sorted = totals.keys.sorted { (totals[$0] ?? 0) > (totals[$1] ?? 0) }.prefix(limit).map { dir in
                .object([
                    "directory": .string(dir),
                    "bytes": .int(totals[dir] ?? 0),
                    "files": .int(Int64(fileCounts[dir] ?? 0)),
                ])
            }
            return .object([
                "tool": .string(tool),
                "directories": .array(sorted),
                "totalBytes": .int(entries.filter { !$0.isDirectory }.reduce(0) { $0 + ($1.sizeBytes ?? 0) }),
            ])
        case "image_asset_size_report":
            let maxBytes = Int64(min(max(optionalInt(arguments, "maxKilobytes") ?? 500, 1), 100000)) * 1024
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            let oversized = entries.filter { entry in
                guard !entry.isDirectory, entry.path.contains(".xcassets/") else { return false }
                let ext = (entry.path as NSString).pathExtension.lowercased()
                return ["png", "jpg", "jpeg", "heic", "webp", "gif", "pdf"].contains(ext) && (entry.sizeBytes ?? 0) > maxBytes
            }
            .sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
            .map { entry in
                .object([
                    "path": .string(entry.path),
                    "sizeBytes": .int(entry.sizeBytes ?? 0),
                ])
            }
            return .object([
                "tool": .string(tool),
                "maxKilobytes": .int(maxBytes / 1024),
                "images": .array(oversized),
                "count": .int(Int64(oversized.count)),
            ])
        case "bundle_resource_auditor":
            let pbxproj = try await Self.g5ResolvePbxproj(tool: tool, cwd: cwd, path: path, runtime: runtime)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: pbxproj)
            let entries = try await Self.g6Entries(cwd: cwd, path: nil, runtime: runtime)
            return Self.g6BundleResources(tool: tool, path: pbxproj, content: document.content, entries: entries)
        case "core_data_model_inspector":
            var modelPaths: [String] = []
            if let path, !path.isEmpty {
                modelPaths = [path]
            } else {
                let entries = try await Self.g6Entries(cwd: cwd, path: nil, runtime: runtime)
                modelPaths = entries.filter { $0.path.hasSuffix(".xcdatamodeld") }.map { $0.path }
            }
            var models: [[String: JSONValue]] = []
            for modelPath in modelPaths {
                let entries = try await Self.g6Entries(cwd: cwd, path: modelPath, runtime: runtime)
                for entry in entries where entry.path.hasSuffix(".xcdatamodel/contents") || entry.path.hasSuffix("contents") {
                    guard let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: entry.path) else { continue }
                    models.append(Self.g6CoreDataModel(tool: tool, path: entry.path, content: document.content))
                }
            }
            return .object([
                "tool": .string(tool),
                "models": .array(models),
                "modelCount": .int(Int64(models.count)),
            ])
        case "swift_data_schema_auditor":
            let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 100, runtime: runtime)
            var models: [[String: JSONValue]] = []
            var issues: [String] = []
            for file in files {
                var currentModel: String?
                var expectingModel = false
                var relationships: [[String: JSONValue]] = []
                var uniques: [String] = []
                for line in Self.g5Lines(file.content) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("@Model") {
                        expectingModel = true
                        if let match = Self.g5RegexMatches(pattern: "class\\s+([A-Za-z0-9_]+)", text: trimmed).first,
                           let name = match.1.count > 1 ? match.1[1] : nil {
                            currentModel = name
                            expectingModel = false
                        }
                        continue
                    }
                    if expectingModel, let match = Self.g5RegexMatches(pattern: "^(final\\s+)?class\\s+([A-Za-z0-9_]+)", text: trimmed).first,
                       let name = match.1.count > 2 ? match.1[2] : nil {
                        currentModel = name
                        expectingModel = false
                        continue
                    }
                    guard currentModel != nil else { continue }
                    if let match = Self.g5RegexMatches(pattern: "@Relationship\\(deleteRule:\\s*\\.([A-Za-z]+)[^)]*\\)\\s*var\\s+([A-Za-z0-9_]+)", text: trimmed).first {
                        let rule = match.1.count > 1 ? (match.1[1] ?? "") : ""
                        let name = match.1.count > 2 ? (match.1[2] ?? "") : ""
                        relationships.append(["name": .string(name), "deleteRule": .string(rule)])
                    } else if let match = Self.g5RegexMatches(pattern: "@Relationship[^\\n]*?var\\s+([A-Za-z0-9_]+)", text: trimmed).first {
                        let name = match.1.count > 1 ? (match.1[1] ?? "") : ""
                        relationships.append(["name": .string(name), "deleteRule": .string("nullify")])
                    }
                    if trimmed.contains("@Attribute(.unique)"), let match = Self.g5RegexMatches(pattern: "var\\s+([A-Za-z0-9_]+)", text: trimmed).first,
                       let name = match.1.count > 1 ? match.1[1] : nil {
                        uniques.append(name)
                    }
                }
                if let model = currentModel {
                    models.append([
                        "model": .string(model),
                        "path": .string(file.path),
                        "relationships": .array(relationships),
                        "uniqueAttributes": .array(uniques.map { .string($0) }),
                    ])
                    if relationships.isEmpty && uniques.isEmpty {
                        issues.append("\(model) in \(file.path) declares no relationships or unique constraints.")
                    }
                }
            }
            return .object([
                "tool": .string(tool),
                "models": .array(models),
                "modelCount": .int(Int64(models.count)),
                "issues": .array(issues.map { .string($0) }),
            ])
        case "privacy_manifest_auditor":
            let manifestPath = try await Self.g6ResolveFile(cwd: cwd, path: path, query: "PrivacyInfo.xcprivacy", match: { $0.name == "PrivacyInfo.xcprivacy" }, tool: tool, runtime: runtime)
            try Self.validateRelativePath(manifestPath, tool: tool)
            let plist = try await Self.g6ReadPlist(cwd: cwd, path: manifestPath, tool: tool, runtime: runtime)
            return Self.g6PrivacyAudit(tool: tool, path: manifestPath, plist: plist)
        case "build_system_detect":
            let entries = try await Self.g6Entries(cwd: cwd, path: path, runtime: runtime)
            var detected: [[String: JSONValue]] = []
            let hasSuffix = { (suffix: String) in entries.contains { !$0.isDirectory && $0.path.hasSuffix(suffix) } }
            let hasName = { (name: String) in entries.contains { !$0.isDirectory && $0.name == name } }
            if entries.contains(where: { $0.isDirectory && $0.path.hasSuffix(".xcworkspace") }) {
                detected.append(["system": .string("xcworkspace"), "evidence": .string(".xcworkspace")])
            }
            if entries.contains(where: { $0.isDirectory && $0.path.hasSuffix(".xcodeproj") }) {
                detected.append(["system": .string("xcodeproj"), "evidence": .string(".xcodeproj")])
            }
            if hasName("Package.swift") {
                detected.append(["system": .string("SwiftPM"), "evidence": .string("Package.swift")])
            }
            if hasName("Podfile") {
                detected.append(["system": .string("CocoaPods"), "evidence": .string("Podfile")])
            }
            if hasName("Cartfile") {
                detected.append(["system": .string("Carthage"), "evidence": .string("Cartfile")])
            }
            if hasName("Project.swift") {
                detected.append(["system": .string("Tuist"), "evidence": .string("Project.swift")])
            }
            if hasName("project.yml") {
                detected.append(["system": .string("xcodegen"), "evidence": .string("project.yml")])
            }
            if hasName("WORKSPACE") || hasName("WORKSPACE.bazel") || hasSuffix("BUILD") || hasSuffix("BUILD.bazel") {
                detected.append(["system": .string("Bazel"), "evidence": .string("WORKSPACE or BUILD file")])
            }
            if hasName("CMakeLists.txt") {
                detected.append(["system": .string("CMake"), "evidence": .string("CMakeLists.txt")])
            }
            return .object([
                "tool": .string(tool),
                "systems": .array(detected),
                "count": .int(Int64(detected.count)),
            ])
        default:
            throw SystemToolError.unknownTool(tool)
        }
    }

    static func g6FrameworkAudit(tool: String, path: String, content: String) -> JSONValue {
        var linked: [[String: JSONValue]] = []
        var seen: Set<String> = []
        for line in Self.g5Lines(content) {
            guard line.contains("PBXBuildFile"), line.contains(".framework") else { continue }
            if let match = Self.g5RegexMatches(pattern: "/\\*\\s*([A-Za-z0-9_.\\-]+\\.framework)\\s*\\*/", text: line).first,
               let name = match.1.count > 1 ? match.1[1] : nil, !name.isEmpty, !seen.contains(name) {
                seen.insert(name)
                linked.append(["name": .string(name), "weak": .bool(line.contains("Weak"))])
            }
        }
        var available: [String] = []
        for line in Self.g5Lines(content) {
            guard line.contains("PBXFileReference"), line.contains(".framework") else { continue }
            if let match = Self.g5RegexMatches(pattern: "/\\*\\s*([A-Za-z0-9_.\\-]+\\.framework)\\s*\\*/", text: line).first,
               let name = match.1.count > 1 ? match.1[1] : nil, !name.isEmpty, !available.contains(name) {
                available.append(name)
            }
        }
        var sdkroots: [String] = []
        var deploymentTargets: [String] = []
        for key in ["SDKROOT", "IPHONEOS_DEPLOYMENT_TARGET", "MACOSX_DEPLOYMENT_TARGET", "TVOS_DEPLOYMENT_TARGET", "WATCHOS_DEPLOYMENT_TARGET"] {
            for match in Self.g5RegexMatches(pattern: key + "\\s*=\\s*([^;]+);", text: content) {
                let value = (match.1.count > 1 ? (match.1[1] ?? "") : "").trimmingCharacters(in: .whitespaces)
                if key == "SDKROOT" {
                    if !value.isEmpty, !sdkroots.contains(value) { sdkroots.append(value) }
                } else if !value.isEmpty, !deploymentTargets.contains(key + " " + value) {
                    deploymentTargets.append(key + " " + value)
                }
            }
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "linkedFrameworks": .array(linked),
            "linkedCount": .int(Int64(linked.count)),
            "availableFrameworks": .array(available.map { .string($0) }),
            "sdkroots": .array(sdkroots.map { .string($0) }),
            "deploymentTargets": .array(deploymentTargets.map { .string($0) }),
        ])
    }

    private static func g6ResolveCatalog(cwd: String, catalog: String?, tool: String, runtime: AgentsRuntimeClient) async throws -> String {
        if let catalog, !catalog.isEmpty {
            guard catalog.hasSuffix(".xcassets") else {
                throw SystemToolError.executionFailed(tool: tool, message: "Catalog path must end in .xcassets.")
            }
            return catalog
        }
        let entries = try await Self.g6Entries(cwd: cwd, path: nil, runtime: runtime)
        guard let found = entries.first(where: { $0.isDirectory && $0.path.hasSuffix(".xcassets") }) else {
            throw SystemToolError.executionFailed(tool: tool, message: "No .xcassets catalog found in the workspace.")
        }
        return found.path
    }

    static func g6ColorsetContents(lightHex: String, darkHex: String) -> [String: Any] {
        func components(_ hex: String) -> [String: Any] {
            let clean = hex.dropFirst()
            let red = Int(clean.prefix(2), radix: 16) ?? 0
            let green = Int(clean.dropFirst(2).prefix(2), radix: 16) ?? 0
            let blue = Int(clean.dropFirst(4).prefix(2), radix: 16) ?? 0
            return [
                "red": String(format: "%.3f", Double(red) / 255.0),
                "green": String(format: "%.3f", Double(green) / 255.0),
                "blue": String(format: "%.3f", Double(blue) / 255.0),
                "alpha": "1.000",
            ]
        }
        return [
            "colors": [
                ["color": ["color-space": "srgb", "components": components(lightHex)], "idiom": "universal"],
                ["appearances": [["appearance": "luminosity", "value": "dark"]], "color": ["color-space": "srgb", "components": components(darkHex)], "idiom": "universal"],
            ],
            "info": ["author": "xcode", "version": 1],
        ]
    }

    static func g6LocaleForStringsPath(_ path: String) -> String {
        for part in path.split(separator: "/") where part.hasSuffix(".lproj") {
            return String(part.dropLast(6))
        }
        return "base"
    }

    static func g6LanguageForExtension(_ ext: String) -> String {
        switch ext {
        case "swift": return "Swift"
        case "m", "mm", "h": return "Objective-C"
        case "c", "cpp", "cc", "hpp": return "C/C++"
        case "ts", "tsx": return "TypeScript"
        case "js", "jsx": return "JavaScript"
        case "py": return "Python"
        case "rs": return "Rust"
        case "kt", "kts": return "Kotlin"
        case "java": return "Java"
        case "md": return "Markdown"
        case "json": return "JSON"
        case "plist": return "Property List"
        case "yaml", "yml": return "YAML"
        case "xml": return "XML"
        case "png", "jpg", "jpeg", "heic", "webp", "gif": return "Image"
        case "": return "No extension"
        default: return "." + ext
        }
    }

    static func g6PbxprojTargets(_ content: String) -> [String] {
        var targets: [String] = []
        for match in Self.g5RegexMatches(pattern: "isa = PBXNativeTarget;[^}]*?name = ([^;]+);", text: content, options: [.dotMatchesLineSeparators]) {
            let name = (match.1.count > 1 ? (match.1[1] ?? "") : "").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !targets.contains(name) { targets.append(name) }
        }
        return targets
    }

    static func g6BundleResources(tool: String, path: String, content: String, entries: [WorkspaceFileEntry]) -> JSONValue {
        var buildFiles: [String: String] = [:]
        for match in Self.g5RegexMatches(pattern: "([0-9A-F]{24}) = \\{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})", text: content) {
            let id = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let ref = match.1.count > 2 ? (match.1[2] ?? "") : ""
            if !id.isEmpty, !ref.isEmpty { buildFiles[id] = ref }
        }
        var filePaths: [String: String] = [:]
        for match in Self.g5RegexMatches(pattern: "([0-9A-F]{24}) /\\* ([^*]+) \\*/ = \\{isa = PBXFileReference;[^}]*?path = ([^;]+);", text: content, options: [.dotMatchesLineSeparators]) {
            let id = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let name = (match.1.count > 2 ? (match.1[2] ?? "") : "").trimmingCharacters(in: .whitespaces)
            var filePath = (match.1.count > 3 ? (match.1[3] ?? "") : "").trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if filePath.isEmpty { filePath = name }
            if !id.isEmpty, !filePath.isEmpty { filePaths[id] = filePath }
        }
        let sizes: [String: Int64] = Dictionary(uniqueKeysWithValues: entries.filter { !$0.isDirectory }.map { ($0.path, $0.sizeBytes ?? 0) })
        let existing = Set(sizes.keys)
        guard let sectionStart = content.range(of: "Begin PBXResourcesBuildPhase section"),
              let sectionEnd = content.range(of: "End PBXResourcesBuildPhase section") else {
            return .object([
                "tool": .string(tool),
                "path": .string(path),
                "resources": .array([]),
                "missing": .array([]),
                "duplicates": .array([]),
                "note": .string("No PBXResourcesBuildPhase section found."),
            ])
        }
        let section = String(content[sectionStart.upperBound..<sectionEnd.lowerBound])
        var resources: [[String: JSONValue]] = []
        var seenNames: [String: Int] = [:]
        var missing: [String] = []
        for match in Self.g5RegexMatches(pattern: "([0-9A-F]{24}) /\\*", text: section) {
            let id = match.1.count > 1 ? (match.1[1] ?? "") : ""
            guard let ref = buildFiles[id], let filePath = filePaths[ref] else { continue }
            let name = (filePath as NSString).lastPathComponent
            seenNames[name, default: 0] += 1
            let found = existing.contains(filePath) || existing.contains { $0.hasSuffix("/" + filePath) }
            if !found { missing.append(filePath) }
            let bytes = sizes[filePath] ?? sizes.first { $0.key.hasSuffix("/" + filePath) }?.value ?? 0
            resources.append([
                "path": .string(filePath),
                "found": .bool(found),
                "bytes": .int(bytes),
            ])
        }
        let duplicates = seenNames.filter { $0.value > 1 }.map { $0.key }.sorted()
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "resources": .array(resources),
            "resourceCount": .int(Int64(resources.count)),
            "missing": .array(missing.map { .string($0) }),
            "duplicates": .array(duplicates.map { .string($0) }),
        ])
    }

    static func g6CoreDataModel(tool: String, path: String, content: String) -> JSONValue {
        let entityMatches = Self.g5RegexMatches(pattern: "<entity\\s+name=\"([^\"]+)\"", text: content)
        var entities: [[String: JSONValue]] = []
        for (index, match) in entityMatches.enumerated() {
            let name = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let start = match.0.location
            let end = index + 1 < entityMatches.count ? entityMatches[index + 1].0.location : (content as NSString).length
            guard let range = Range(NSRange(location: start, length: end - start), in: content) else { continue }
            let chunk = String(content[range])
            var attributes: [[String: JSONValue]] = []
            for attr in Self.g5RegexMatches(pattern: "<attribute\\s+name=\"([^\"]+)\"[^>]*attributeType=\"([^\"]+)\"", text: chunk) {
                attributes.append([
                    "name": .string(attr.1.count > 1 ? (attr.1[1] ?? "") : ""),
                    "type": .string(attr.1.count > 2 ? (attr.1[2] ?? "") : ""),
                ])
            }
            var relationships: [[String: JSONValue]] = []
            for rel in Self.g5RegexMatches(pattern: "<relationship\\s+name=\"([^\"]+)\"[^>]*destinationEntity=\"([^\"]+)\"", text: chunk) {
                relationships.append([
                    "name": .string(rel.1.count > 1 ? (rel.1[1] ?? "") : ""),
                    "destination": .string(rel.1.count > 2 ? (rel.1[2] ?? "") : ""),
                ])
            }
            entities.append([
                "name": .string(name),
                "attributes": .array(attributes),
                "relationships": .array(relationships),
            ])
        }
        return .object([
            "path": .string(path),
            "entities": .array(entities),
            "entityCount": .int(Int64(entities.count)),
        ])
    }

    static func g6PrivacyAudit(tool: String, path: String, plist: [String: Any]) -> JSONValue {
        var issues: [String] = []
        let tracking = plist["NSPrivacyTracking"] as? Bool ?? false
        if tracking {
            if let domains = plist["NSPrivacyTrackingDomains"] as? [String], !domains.isEmpty {
            } else {
                issues.append("NSPrivacyTracking is true but NSPrivacyTrackingDomains is missing or empty.")
            }
        }
        if let collected = plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] {
            for (index, entry) in collected.enumerated() {
                for key in ["NSPrivacyCollectedDataType", "NSPrivacyCollectedDataTypeLinked", "NSPrivacyCollectedDataTypeTracking", "NSPrivacyCollectedDataTypePurposes"] {
                    if entry[key] == nil {
                        issues.append("Collected data type at index \(index) is missing \(key).")
                    }
                }
            }
        } else if plist["NSPrivacyCollectedDataTypes"] != nil {
            issues.append("NSPrivacyCollectedDataTypes is present but is not an array of dictionaries.")
        }
        let categoriesRequiringReasons: Set<String> = [
            "NSPrivacyAccessedAPICategoryFileTimestamp",
            "NSPrivacyAccessedAPICategorySystemBootTime",
            "NSPrivacyAccessedAPICategoryDiskSpace",
            "NSPrivacyAccessedAPICategoryActiveKeyboards",
            "NSPrivacyAccessedAPICategoryUserDefaults",
        ]
        if let accessed = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] {
            for (index, entry) in accessed.enumerated() {
                guard let category = entry["NSPrivacyAccessedAPICategory"] as? String else {
                    issues.append("Accessed API type at index \(index) is missing NSPrivacyAccessedAPICategory.")
                    continue
                }
                if categoriesRequiringReasons.contains(category) {
                    if let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String], !reasons.isEmpty {
                    } else {
                        issues.append("\(category) requires NSPrivacyAccessedAPITypeReasons.")
                    }
                }
            }
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "tracking": .bool(tracking),
            "collectedDataTypes": .int(Int64((plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])?.count ?? 0)),
            "accessedApiTypes": .int(Int64((plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])?.count ?? 0)),
            "issues": .array(issues.map { .string($0) }),
            "issueCount": .int(Int64(issues.count)),
        ])
    }

    static func g6DerivedData(tool: String, path: String?, limit: Int) -> JSONValue {
        let expanded = ExternalEditorService.expandedPath(path ?? "~/Library/Developer/Xcode/DerivedData")
        let root = URL(fileURLWithPath: expanded).standardized
        var directories: [[String: JSONValue]] = []
        var exists = false
        if let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) {
            exists = true
            for name in names.sorted() {
                let dir = root.appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                var bytes: Int64 = 0
                var files = 0
                if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
                    for case let fileURL as URL in enumerator {
                        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]), values.isDirectory != true {
                            bytes += Int64(values.fileSize ?? 0)
                            files += 1
                        }
                    }
                }
                directories.append([
                    "path": .string(dir.path),
                    "name": .string(name),
                    "bytes": .int(bytes),
                    "files": .int(Int64(files)),
                ])
            }
        }
        directories.sort { ($0["bytes"]?.intValue ?? 0) > ($1["bytes"]?.intValue ?? 0) }
        let totalBytes = directories.reduce(0) { $0 + ($1["bytes"]?.intValue ?? 0) }
        return .object([
            "tool": .string(tool),
            "path": .string(root.path),
            "exists": .bool(exists),
            "directories": .array(Array(directories.prefix(limit))),
            "totalBytes": .int(Int64(totalBytes)),
        ])
    }

    static func g6ParseLsof(_ output: String) -> [[String: JSONValue]] {
        var rows: [[String: JSONValue]] = []
        for line in Self.g5Lines(output) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9, parts[0] != "COMMAND" else { continue }
            let address = parts[8...].joined(separator: " ")
            rows.append([
                "command": .string(String(parts[0])),
                "pid": .int(Int64(parts[1]) ?? 0),
                "user": .string(String(parts[2])),
                "address": .string(address),
            ])
        }
        return rows
    }

    static func g6ParseLaunchctl(_ output: String) -> [[String: JSONValue]] {
        var rows: [[String: JSONValue]] = []
        for line in Self.g5Lines(output) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let pid = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let status = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let label = String(parts[2]).trimmingCharacters(in: .whitespaces)
            if label.isEmpty || label == "Label" { continue }
            rows.append([
                "pid": .string(pid),
                "status": .string(status),
                "label": .string(label),
            ])
        }
        return rows
    }

    private static func g6FindPid(_ value: JSONValue, name: String) -> Int? {
        switch value {
        case .array(let items):
            for item in items {
                if let pid = Self.g6FindPid(item, name: name) { return pid }
            }
            return nil
        case .object(let dict):
            if dict["name"]?.stringValue == name || dict["bundleIdentifier"]?.stringValue == name {
                return dict["pid"]?.intValue
            }
            for item in dict.values {
                if let pid = Self.g6FindPid(item, name: name) { return pid }
            }
            return nil
        default:
            return nil
        }
    }

    private static func runG6UseSystem(tool: String, arguments: [String: JSONValue], runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let threadId = try requiredString(arguments, "threadId", tool: tool)
        let operation = try requiredString(arguments, "operation", tool: tool)
        let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 60
        switch operation {
        case "system_info":
            return Self.g6EnvInfo(tool: tool)
        case "dev_environment":
            var tools: [[String: JSONValue]] = []
            for (name, argv) in [("xcodebuild", ["xcodebuild", "-version"]), ("swift", ["swift", "--version"])] {
                let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: argv, timeoutSeconds: timeoutSeconds, runtime: runtime)
                tools.append(["tool": .string(name), "available": .bool(exitCode == 0), "output": .string(output)])
            }
            return .object(["operation": .string(operation), "tools": .array(tools)])
        case "process_list":
            let filter = optionalString(arguments, "filter")
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["/bin/ps", "-ax", "-o", "pid=,pcpu=,pmem=,comm="], timeoutSeconds: timeoutSeconds, runtime: runtime)
            let processes = Self.g6ParsePs(output, filter: filter, limit: 200)
            return .object(["operation": .string(operation), "processes": .array(processes), "count": .int(Int64(processes.count)), "exitCode": .int(Int64(exitCode))])
        case "network_interfaces":
            var argv = ["/sbin/ifconfig"]
            if let interface = optionalString(arguments, "interface") {
                try Self.g3Identifier(interface, field: "interface", tool: tool)
                argv.append(interface)
            }
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: argv, timeoutSeconds: timeoutSeconds, runtime: runtime)
            return .object(["operation": .string(operation), "output": .string(output), "exitCode": .int(Int64(exitCode))])
        case "listening_sockets":
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["/usr/sbin/lsof", "-i", "-P", "-n", "-sTCP:LISTEN"], timeoutSeconds: timeoutSeconds, runtime: runtime)
            return .object([
                "operation": .string(operation),
                "listening": .array(Self.g6ParseLsof(output)),
                "exitCode": .int(Int64(exitCode)),
                "output": .string(output),
                "note": exitCode == 0 ? .string("") : .string("lsof exited non-zero; output may be incomplete where permission was denied."),
            ])
        case "connectivity":
            let host = try requiredString(arguments, "host", tool: tool)
            guard let port = optionalInt(arguments, "port"), (1...65535).contains(port) else {
                throw SystemToolError.missingArgument(tool: tool, argument: "port")
            }
            try Self.g3Token(host, field: "host", tool: tool)
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["nc", "-z", "-w", "5", host, String(port)], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: tool, cli: "nc", exitCode: exitCode, output: output)
            return .object(["operation": .string(operation), "host": .string(host), "port": .int(Int64(port)), "reachable": .bool(exitCode == 0), "exitCode": .int(Int64(exitCode))])
        case "disk_info":
            let root = optionalString(arguments, "cwd") ?? "/"
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: ExternalEditorService.expandedPath(root))
            let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
            let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let used = max(0, total - free)
            return .object(["operation": .string(operation), "path": .string(root), "totalBytes": .int(total), "availableBytes": .int(free), "usedBytes": .int(used), "usedPercent": .double(total > 0 ? Double(used) / Double(total) * 100 : 0)])
        case "system_log":
            let minutes = min(max(optionalInt(arguments, "minutes") ?? 5, 1), 60)
            var argv = ["/usr/bin/log", "show", "--last", "\(minutes)m"]
            if let predicate = optionalString(arguments, "predicate") {
                try Self.g3Token(predicate, field: "predicate", tool: tool)
                argv += ["--predicate", predicate]
            }
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: argv, timeoutSeconds: timeoutSeconds, runtime: runtime)
            return .object(["operation": .string(operation), "minutes": .int(Int64(minutes)), "output": .string(String(output.prefix(20000))), "truncated": .bool(output.count > 20000), "exitCode": .int(Int64(exitCode))])
        case "service_status":
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["/bin/launchctl", "list"], timeoutSeconds: timeoutSeconds, runtime: runtime)
            return .object(["operation": .string(operation), "services": .array(Self.g6ParseLaunchctl(output)), "exitCode": .int(Int64(exitCode))])
        case "config_read":
            let name = try requiredString(arguments, "sysctlName", tool: tool)
            let allowed: Set<String> = ["hw.memsize", "hw.ncpu", "hw.model", "hw.machine", "kern.osrelease", "kern.osversion", "kern.version", "hw.physicalcpu", "hw.logicalcpu", "machdep.cpu.brand_string"]
            guard allowed.contains(name) else {
                throw SystemToolError.executionFailed(tool: tool, message: "config_read sysctlName must be one of: \(allowed.sorted().joined(separator: ", ")).")
            }
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["/usr/sbin/sysctl", "-n", name], timeoutSeconds: timeoutSeconds, runtime: runtime)
            return .object(["operation": .string(operation), "sysctlName": .string(name), "value": .string(output.trimmingCharacters(in: .whitespacesAndNewlines)), "exitCode": .int(Int64(exitCode))])
        case "user_defaults_write":
            try Self.requireConfirm(arguments, tool: tool, message: "user_defaults_write is a mutation; pass confirm=true.")
            let domain = try requiredString(arguments, "domain", tool: tool)
            let key = try requiredString(arguments, "key", tool: tool)
            let value = try requiredString(arguments, "value", tool: tool)
            let valueType = optionalString(arguments, "valueType") ?? "string"
            guard ["string", "bool", "int"].contains(valueType) else {
                throw SystemToolError.executionFailed(tool: tool, message: "user_defaults_write valueType must be string, bool, or int.")
            }
            guard domain != "NSGlobalDomain", !domain.hasPrefix("/"), !domain.contains(".."), !domain.hasPrefix("-") else {
                throw SystemToolError.executionFailed(tool: tool, message: "user_defaults_write refuses NSGlobalDomain and non-user domains.")
            }
            try Self.g3Token(key, field: "key", tool: tool)
            let (beforeExit, beforeOutput) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["defaults", "read", domain, key], timeoutSeconds: timeoutSeconds, runtime: runtime)
            let previous: JSONValue = beforeExit == 0 ? .string(beforeOutput.trimmingCharacters(in: .whitespacesAndNewlines)) : .null
            let flag: String
            let written: String
            switch valueType {
            case "bool":
                guard value == "true" || value == "false" else {
                    throw SystemToolError.executionFailed(tool: tool, message: "user_defaults_write bool value must be true or false.")
                }
                flag = "-bool"
                written = value == "true" ? "1" : "0"
            case "int":
                guard Int(value) != nil else {
                    throw SystemToolError.executionFailed(tool: tool, message: "user_defaults_write int value must be an integer.")
                }
                flag = "-int"
                written = value
            default:
                flag = "-string"
                written = value
            }
            let (writeExit, writeOutput) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["defaults", "write", domain, key, flag, value], timeoutSeconds: timeoutSeconds, runtime: runtime)
            guard writeExit == 0 else {
                throw SystemToolError.executionFailed(tool: tool, message: "defaults write failed: \(writeOutput)")
            }
            let (afterExit, afterOutput) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["defaults", "read", domain, key], timeoutSeconds: timeoutSeconds, runtime: runtime)
            let after = afterOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let verified = afterExit == 0 && (valueType == "string" ? after == value : after == written)
            return .object(["operation": .string(operation), "domain": .string(domain), "key": .string(key), "previousValue": previous, "newValue": .string(value), "verified": .bool(verified)])
        default:
            throw SystemToolError.executionFailed(tool: tool, message: "use_system operation must be system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read, or user_defaults_write.")
        }
    }

    private static func runG6UseApp(tool: String, arguments: [String: JSONValue], runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let threadId = try requiredString(arguments, "threadId", tool: tool)
        let action = try requiredString(arguments, "action", tool: tool)
        let missing: Set<String> = ["activate", "close_application", "select_window", "get_focused_element", "select_all", "copy", "paste", "wait_for_element", "wait_for_window"]
        if missing.contains(action) {
            throw SystemToolError.executionFailed(tool: tool, message: "use_app action \(action) has no engine tool; the capability is not implemented.")
        }
        let mapped: String
        var mappedArguments = arguments
        switch action {
        case "list_applications": mapped = "list_apps"
        case "inspect_application":
            mapped = "list_windows"
            if mappedArguments["pid"] == nil, let appName = optionalString(arguments, "app_name") {
                let apps = try await runComputerUseTool(tool: "list_apps", threadId: threadId, arguments: [:], runtime: runtime)
                guard let pid = Self.g6FindPid(apps, name: appName) else {
                    throw SystemToolError.executionFailed(tool: tool, message: "No running app named \(appName) found.")
                }
                mappedArguments["pid"] = .int(Int64(pid))
            }
        case "launch":
            mapped = "launch_app"
            if mappedArguments["bundle_id"] == nil, let identifier = optionalString(arguments, "app_identifier") {
                mappedArguments["bundle_id"] = .string(identifier)
            }
        case "list_windows": mapped = "list_windows"
        case "inspect_ui", "get_accessibility_tree": mapped = "get_window_state"
        case "take_screenshot":
            return try await runComputerUseTool(tool: "get_desktop_state", threadId: threadId, arguments: ["include_screenshot": .bool(true)], runtime: runtime)
        case "click", "activate_element": mapped = "click"
        case "double_click": mapped = "double_click"
        case "right_click": mapped = "right_click"
        case "move_pointer": mapped = "move_cursor"
        case "drag": mapped = "drag"
        case "scroll": mapped = "scroll"
        case "type_text": mapped = "type_text"
        case "press_key": mapped = "press_key"
        case "press_shortcut": mapped = "hotkey"
        case "set_element_value": mapped = "set_value"
        case "select_menu": mapped = "invoke_menu"
        case "verify": mapped = "verify_state"
        default:
            throw SystemToolError.executionFailed(tool: tool, message: "use_app action \(action) is not a known action.")
        }
        guard let target = Self.definition(named: mapped, for: .system) else {
            throw SystemToolError.unknownTool(mapped)
        }
        let toolArguments = try Self.computerUseArguments(mappedArguments, definition: target, tool: tool)
        let result = try await runComputerUseTool(tool: mapped, threadId: threadId, arguments: toolArguments, runtime: runtime)
        return .object(["action": .string(action), "tool": .string(mapped), "result": result])
    }

    private static func runG6Preflight(tool: String, threadId: String, cwd: String, runtime: AgentsRuntimeClient) async throws -> JSONValue {
        var checks: [[String: JSONValue]] = []
        let probe = ".preflight-check-\(UUID().uuidString)"
        var writable = false
        do {
            try Self.writeWorkspaceBytes(cwd: cwd, path: probe, data: Data("ok".utf8), tool: tool)
            let url = try resolveWorkspaceFileURL(cwd: cwd, path: probe, tool: tool)
            try FileManager.default.removeItem(at: url)
            writable = true
        } catch {
            writable = false
        }
        checks.append(["check": .string("workspaceWritable"), "passed": .bool(writable)])
        let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["xcodebuild", "-version"], timeoutSeconds: 60, runtime: runtime)
        checks.append(["check": .string("xcodebuild"), "passed": .bool(exitCode == 0), "detail": .string(Self.g5Lines(output).first ?? "")])
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: ExternalEditorService.expandedPath(cwd))
        let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        checks.append(["check": .string("diskSpace"), "passed": .bool(free > 1024 * 1024 * 1024), "detail": .string("\(free) bytes free")])
        var artifactsWritable = false
        do {
            let dir = try resolveWorkspaceFileURL(cwd: cwd, path: ".assist_temp/artifacts", tool: tool)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            artifactsWritable = FileManager.default.isWritableFile(atPath: dir.path)
        } catch {
            artifactsWritable = false
        }
        checks.append(["check": .string("artifactStorage"), "passed": .bool(artifactsWritable)])
        return .object([
            "tool": .string(tool),
            "checks": .array(checks),
            "allPassed": .bool(checks.allSatisfy { $0["passed"]?.boolValue == true }),
        ])
    }

    private static func g6GitHubDefaultBranch(tool: String, threadId: String, repository: String, timeoutSeconds: Int, runtime: AgentsRuntimeClient) async throws -> String {
        let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["gh", "repo", "view", repository, "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"], timeoutSeconds: timeoutSeconds, runtime: runtime)
        try Self.g3ThrowIfMissingCLI(tool: tool, cli: "gh", exitCode: exitCode, output: output)
        guard exitCode == 0 else {
            throw SystemToolError.executionFailed(tool: tool, message: "gh repo view failed: \(output)")
        }
        let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw SystemToolError.executionFailed(tool: tool, message: "gh repo view returned no default branch for \(repository).")
        }
        return branch
    }

    private static func g6ValidateRepoPath(_ path: String, tool: String) throws {
        guard !path.contains("\n"), !path.contains("\r"), !path.hasPrefix("-") else {
            throw SystemToolError.executionFailed(tool: tool, message: "Repository path must not contain newlines or start with a dash.")
        }
        guard path.split(separator: "/").allSatisfy({ $0 != ".." }) else {
            throw SystemToolError.executionFailed(tool: tool, message: "Repository path must not contain .. components.")
        }
    }

    private static func runG6GitHubRepo(tool: String, arguments: [String: JSONValue], runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let threadId = try requiredString(arguments, "threadId", tool: tool)
        let operation = try requiredString(arguments, "operation", tool: tool)
        let timeoutSeconds = optionalInt(arguments, "timeoutSeconds") ?? 120
        let repository: String
        if let owner = optionalString(arguments, "owner"), let repo = optionalString(arguments, "repo") {
            try Self.g3Identifier(owner, field: "owner", tool: tool)
            try Self.g3Identifier(repo, field: "repo", tool: tool)
            repository = owner + "/" + repo
        } else if let url = optionalString(arguments, "url"), !url.isEmpty {
            guard let parsed = URL(string: url), parsed.host == "github.com" else {
                throw SystemToolError.executionFailed(tool: tool, message: "github_repo url must be a github.com repository URL.")
            }
            let parts = parsed.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else {
                throw SystemToolError.executionFailed(tool: tool, message: "github_repo url must name an owner and repository.")
            }
            repository = parts[0] + "/" + parts[1].replacingOccurrences(of: ".git", with: "")
        } else {
            throw SystemToolError.missingArgument(tool: tool, argument: "owner")
        }
        let ref = optionalString(arguments, "ref")
        if let ref { try Self.g3Token(ref, field: "ref", tool: tool) }
        switch operation {
        case "repository_info":
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["gh", "repo", "view", repository, "--json", "name,description,defaultBranchRef,createdAt,updatedAt,licenseInfo,primaryLanguage,stargazerCount,forkCount,isPrivate"], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: tool, cli: "gh", exitCode: exitCode, output: output)
            guard exitCode == 0 else {
                throw SystemToolError.executionFailed(tool: tool, message: "gh repo view failed: \(output)")
            }
            return try Self.g3JSONValue(output, tool: tool)
        case "list_files", "get_directory":
            let repoPath = optionalString(arguments, "path") ?? ""
            try Self.g6ValidateRepoPath(repoPath, tool: tool)
            var apiPath = "repos/" + repository + "/contents"
            if !repoPath.isEmpty { apiPath += "/" + repoPath }
            if let ref { apiPath += "?ref=" + ref }
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["gh", "api", apiPath], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: tool, cli: "gh", exitCode: exitCode, output: output)
            guard exitCode == 0 else {
                throw SystemToolError.executionFailed(tool: tool, message: "gh api failed: \(output)")
            }
            return try Self.g3JSONValue(output, tool: tool)
        case "get_file":
            let repoPath = try requiredString(arguments, "path", tool: tool)
            try Self.g6ValidateRepoPath(repoPath, tool: tool)
            var apiPath = "repos/" + repository + "/contents/" + repoPath
            if let ref { apiPath += "?ref=" + ref }
            let (metaExit, metaOutput) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["gh", "api", apiPath], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: tool, cli: "gh", exitCode: metaExit, output: metaOutput)
            guard metaExit == 0 else {
                throw SystemToolError.executionFailed(tool: tool, message: "gh api failed: \(metaOutput)")
            }
            let metadata = try Self.g3JSONValue(metaOutput, tool: tool)
            guard metadata["type"]?.stringValue == "file" else {
                throw SystemToolError.executionFailed(tool: tool, message: "Path \(repoPath) is not a file in \(repository).")
            }
            guard (metadata["size"]?.intValue ?? 0) <= 200000 else {
                throw SystemToolError.executionFailed(tool: tool, message: "File \(repoPath) exceeds 200000 bytes; fetch it with fetch_repository instead.")
            }
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["gh", "api", apiPath, "-H", "Accept: application/vnd.github.raw"], timeoutSeconds: timeoutSeconds, runtime: runtime)
            guard exitCode == 0 else {
                throw SystemToolError.executionFailed(tool: tool, message: "gh api failed: \(output)")
            }
            return .object([
                "repository": .string(repository),
                "path": .string(repoPath),
                "size": metadata["size"] ?? .null,
                "content": .string(output),
            ])
        case "get_tree":
            let treeRef = ref ?? (try await Self.g6GitHubDefaultBranch(tool: tool, threadId: threadId, repository: repository, timeoutSeconds: timeoutSeconds, runtime: runtime))
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["gh", "api", "repos/" + repository + "/git/trees/" + treeRef + "?recursive=1"], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: tool, cli: "gh", exitCode: exitCode, output: output)
            guard exitCode == 0 else {
                throw SystemToolError.executionFailed(tool: tool, message: "gh api failed: \(output)")
            }
            let value = try Self.g3JSONValue(output, tool: tool)
            let tree = value["tree"]?.arrayValue ?? []
            return .object([
                "repository": .string(repository),
                "ref": .string(treeRef),
                "truncated": value["truncated"] ?? .null,
                "entries": .array(Array(tree.prefix(500))),
                "entryCount": .int(Int64(tree.count)),
            ])
        case "search_code":
            let query = try requiredString(arguments, "query", tool: tool)
            try Self.g3Token(query, field: "query", tool: tool)
            guard query.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_.:+- ".contains($0) }) else {
                throw SystemToolError.executionFailed(tool: tool, message: "search_code query must use only letters, digits, space, underscore, dot, colon, plus, or dash.")
            }
            let encoded = query.replacingOccurrences(of: " ", with: "+")
            let (exitCode, output) = try await Self.g3Run(tool: tool, threadId: threadId, argv: ["gh", "api", "search/code?q=repo:" + repository + "+" + encoded], timeoutSeconds: timeoutSeconds, runtime: runtime)
            try Self.g3ThrowIfMissingCLI(tool: tool, cli: "gh", exitCode: exitCode, output: output)
            guard exitCode == 0 else {
                throw SystemToolError.executionFailed(tool: tool, message: "gh api failed: \(output)")
            }
            let value = try Self.g3JSONValue(output, tool: tool)
            let items = value["items"]?.arrayValue ?? []
            return .object([
                "repository": .string(repository),
                "query": .string(query),
                "totalCount": value["total_count"] ?? .null,
                "items": .array(Array(items.prefix(20))),
            ])
        case "fetch_repository":
            let treeRef = ref ?? (try await Self.g6GitHubDefaultBranch(tool: tool, threadId: threadId, repository: repository, timeoutSeconds: timeoutSeconds, runtime: runtime))
            let root = try await Self.resolveThreadRoot(threadId: threadId, tool: tool, runtime: runtime)
            let safeRef = treeRef.replacingOccurrences(of: "/", with: "-")
            let fileName = (repository.split(separator: "/").last.map(String.init) ?? "repo") + "-" + safeRef + ".tar.gz"
            let command = "gh api repos/" + repository + "/tarball/" + treeRef + " > " + Self.shellQuoted(fileName)
            _ = try await Self.runShellCommand(tool: tool, threadId: threadId, cwd: root, command: command, timeoutSeconds: timeoutSeconds, runtime: runtime)
            let url = URL(fileURLWithPath: root).appendingPathComponent(fileName)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return .object([
                "repository": .string(repository),
                "ref": .string(treeRef),
                "path": .string(fileName),
                "bytes": .int(size),
            ])
        default:
            throw SystemToolError.executionFailed(tool: tool, message: "github_repo operation must be repository_info, list_files, get_file, get_directory, get_tree, search_code, or fetch_repository.")
        }
    }

    private static func runG5Tool(tool: String, arguments: [String: JSONValue], runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let cwd = try requiredString(arguments, "cwd", tool: tool)
        let path = optionalString(arguments, "path")
        let limit = max(1, min(1000, optionalInt(arguments, "limit") ?? 200))
        switch tool {
        case "code_summary":
            let file = try requiredString(arguments, "path", tool: tool)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: file)
            return Self.parseG5FileSummary(tool: tool, path: file, content: document.content)
        case "complexity_analysis":
            let file = try requiredString(arguments, "path", tool: tool)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: file)
            return Self.parseG5Complexity(tool: tool, path: file, content: document.content)
        case "code_lint":
            return try await Self.runG5Lint(tool: tool, cwd: cwd, path: path, limit: limit, runtime: runtime)
        case "runtime_diagnostics_engine":
            let logPath = try requiredString(arguments, "logPath", tool: tool)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: logPath)
            return Self.parseG5DiagnosticsLog(tool: tool, logPath: logPath, content: document.content)
        case "build_log_analyze":
            let file = try requiredString(arguments, "path", tool: tool)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: file)
            return Self.parseG5BuildLog(tool: tool, path: file, content: document.content)
        case "crash_log_parse":
            let file = try requiredString(arguments, "path", tool: tool)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: file)
            return Self.parseG5CrashLog(tool: tool, path: file, content: document.content)
        case "test_log_parse":
            let file = try requiredString(arguments, "path", tool: tool)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: file)
            return Self.parseG5TestLog(tool: tool, path: file, content: document.content)
        case "test_flaky_detect":
            let file = try requiredString(arguments, "path", tool: tool)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: file)
            return Self.parseG5FlakyTests(tool: tool, path: file, content: document.content)
        case "code_metrics_analyzer":
            let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 100, runtime: runtime)
            return Self.parseG5Metrics(tool: tool, files: files)
        case "comment_density_report":
            let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 100, runtime: runtime)
            return Self.parseG5CommentDensity(tool: tool, files: files, limit: limit)
        case "function_size_report":
            let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 100, runtime: runtime)
            return Self.parseG5FunctionSizes(tool: tool, files: files, limit: limit)
        case "dead_code_scan":
            let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 100, runtime: runtime)
            return Self.parseG5DeadCode(tool: tool, files: files, privateOnly: false, limit: limit)
        case "dead_code_eliminator":
            let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 100, runtime: runtime)
            return Self.parseG5DeadCode(tool: tool, files: files, privateOnly: true, limit: limit)
        case "duplicate_code_scan":
            let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 100, runtime: runtime)
            return Self.parseG5DuplicateBlocks(tool: tool, files: files, limit: limit)
        case "unused_imports_detector":
            let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 100, runtime: runtime)
            return Self.parseG5UnusedImports(tool: tool, files: files, limit: limit)
        case "license_header_check":
            let requiredText = optionalString(arguments, "requiredText") ?? "Copyright"
            let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 200, runtime: runtime)
            return Self.parseG5LicenseCheck(tool: tool, files: files, requiredText: requiredText)
        case "api_docs_coverage":
            let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".swift"], limit: 100, runtime: runtime)
            return Self.parseG5DocCoverage(tool: tool, files: files)
        case "docstring_generator":
            let file = try requiredString(arguments, "path", tool: tool)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: file)
            return Self.parseG5Docstring(tool: tool, path: file, content: document.content, symbol: optionalString(arguments, "symbol"))
        case "code_snippet_manager":
            return try await Self.runG5Snippet(tool: tool, arguments: arguments, runtime: runtime)
        case "strings_file_validate":
            return try await Self.runG5StringsValidate(tool: tool, cwd: cwd, path: path, limit: limit, runtime: runtime)
        case "entitlements_diff", "build_settings_diff":
            let first = try requiredString(arguments, "path", tool: tool)
            let second = try requiredString(arguments, "otherPath", tool: tool)
            let firstDoc = try await runtime.readWorkspaceFile(cwd: cwd, path: first)
            let secondDoc = try await runtime.readWorkspaceFile(cwd: cwd, path: second)
            let firstPairs = tool == "entitlements_diff" ? Self.parseG5PlistKeyValues(firstDoc.content) : Self.parseG5XcconfigKeyValues(firstDoc.content)
            let secondPairs = tool == "entitlements_diff" ? Self.parseG5PlistKeyValues(secondDoc.content) : Self.parseG5XcconfigKeyValues(secondDoc.content)
            return Self.parseG5KeyValueDiff(tool: tool, path: first, otherPath: second, first: firstPairs, second: secondPairs)
        case "pbxproj_lint", "build_phase_scripts_list", "build_configuration_list", "target_dependencies_list", "target_source_list":
            let resolved = try await Self.g5ResolvePbxproj(tool: tool, cwd: cwd, path: path, runtime: runtime)
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: resolved)
            switch tool {
            case "pbxproj_lint":
                let entries = try await runtime.listWorkspaceFiles(cwd: cwd, query: "", limit: 500)
                let workspacePaths = entries.filter { !$0.isDirectory }.map { $0.path }
                return Self.parseG5PbxprojLint(tool: tool, path: resolved, content: document.content, workspacePaths: workspacePaths)
            case "build_phase_scripts_list":
                return Self.parseG5PbxprojScripts(tool: tool, path: resolved, content: document.content)
            case "build_configuration_list":
                let entries = try await runtime.listWorkspaceFiles(cwd: cwd, query: ".xcconfig", limit: 100)
                let xcconfigs = entries.filter { !$0.isDirectory }.map { $0.path }
                return Self.parseG5PbxprojConfigs(tool: tool, path: resolved, content: document.content, xcconfigFiles: xcconfigs)
            case "target_dependencies_list":
                return Self.parseG5PbxprojDeps(tool: tool, path: resolved, content: document.content)
            default:
                return Self.parseG5PbxprojSources(tool: tool, path: resolved, content: document.content)
            }
        case "workspace_settings_read":
            return try await Self.runG5WorkspaceSettings(tool: tool, cwd: cwd, path: path, runtime: runtime)
        case "scheme_test_plan_list":
            return try await Self.runG5TestPlans(tool: tool, cwd: cwd, path: path, runtime: runtime)
        case "info_plist_audit":
            return try await Self.runG5InfoPlistAudit(tool: tool, cwd: cwd, path: path, runtime: runtime)
        case "markdown_link_check":
            return try await Self.runG5MarkdownLinks(tool: tool, cwd: cwd, path: path, limit: limit, runtime: runtime)
        case "docs_index_build":
            return try await Self.runG5DocsIndex(tool: tool, cwd: cwd, path: path, runtime: runtime)
        default:
            return try await Self.runG5Scan(tool: tool, arguments: arguments, runtime: runtime)
        }
    }

    private static func runG5Scan(tool: String, arguments: [String: JSONValue], runtime: AgentsRuntimeClient) async throws -> JSONValue {
        guard let spec = g5ScanSpecs[tool] else {
            throw SystemToolError.unknownTool(tool)
        }
        let cwd = try requiredString(arguments, "cwd", tool: tool)
        let scope = optionalString(arguments, "path")
        let limit = max(1, min(1000, optionalInt(arguments, "limit") ?? 200))
        var substitutions: [String: String] = [:]
        for key in ["symbol", "function", "protocol"] {
            if let value = optionalString(arguments, key) {
                substitutions[key] = NSRegularExpression.escapedPattern(for: value)
            }
        }
        var groups: [[String: JSONValue]] = []
        var totalMatches = 0
        var truncated = false
        if spec.literal {
            let query = try requiredString(arguments, "query", tool: tool)
            let hits = try await runtime.searchWorkspace(cwd: cwd, query: query, limit: limit)
            let scoped = Self.g5ScopeHits(hits, scope: scope)
            totalMatches = scoped.count
            truncated = scoped.count >= limit
            groups.append(Self.g5GroupJSON(label: "matches", hits: scoped, values: [], redact: false, sampleLimit: 0))
        } else {
            for patternSpec in spec.patterns {
                var pattern = patternSpec.pattern
                for (key, value) in substitutions {
                    pattern = pattern.replacingOccurrences(of: "{\(key)}", with: value)
                }
                if pattern.contains("{symbol}") {
                    throw SystemToolError.missingArgument(tool: tool, argument: "symbol")
                }
                if pattern.contains("{function}") {
                    throw SystemToolError.missingArgument(tool: tool, argument: "function")
                }
                if pattern.contains("{protocol}") {
                    throw SystemToolError.missingArgument(tool: tool, argument: "protocol")
                }
                let hits = try await runtime.searchWorkspaceRegex(cwd: cwd, pattern: pattern, limit: limit)
                let scoped = Self.g5ScopeHits(hits, scope: scope)
                if scoped.count >= limit { truncated = true }
                totalMatches += scoped.count
                groups.append(Self.g5PatternGroupJSON(spec: spec, patternSpec: patternSpec, hits: scoped))
            }
        }
        if tool == "code_comment_extract", let symbol = optionalString(arguments, "symbol") {
            let symbolHits = try await runtime.searchWorkspace(cwd: cwd, query: symbol, limit: limit)
            let symbolFiles = Set(symbolHits.map { $0.path })
            groups = groups.map { group in
                var copy = group
                let kept = (group["matches"]?.arrayValue ?? []).filter { hit in
                    guard let hitPath = hit["path"]?.stringValue else { return false }
                    return symbolFiles.contains(hitPath)
                }
                copy["matches"] = .array(kept)
                copy["count"] = .int(Int64(kept.count))
                return copy
            }
            totalMatches = groups.reduce(0) { $0 + ($1["count"]?.intValue ?? 0) }
        }
        if tool == "import_graph", let module = optionalString(arguments, "module") {
            groups = groups.filter { group in
                (group["values"]?.arrayValue ?? []).contains { $0.stringValue == module }
            }
            totalMatches = groups.reduce(0) { $0 + ($1["count"]?.intValue ?? 0) }
        }
        return .object([
            "tool": .string(tool),
            "matchCount": .int(Int64(totalMatches)),
            "truncated": .bool(truncated),
            "groups": .array(groups),
        ])
    }

    private static func g5ScopeHits(_ hits: [WorkspaceSearchHit], scope: String?) -> [WorkspaceSearchHit] {
        guard let scope, !scope.isEmpty else { return hits }
        return hits.filter { $0.path == scope || $0.path.hasPrefix(scope + "/") }
    }

    private static func g5PatternGroupJSON(spec: G5ScanSpec, patternSpec: G5PatternSpec, hits: [WorkspaceSearchHit]) -> [String: JSONValue] {
        switch spec.shape {
        case "files":
            var byFile: [String: [WorkspaceSearchHit]] = [:]
            var order: [String] = []
            for hit in hits {
                if byFile[hit.path] == nil { order.append(hit.path) }
                byFile[hit.path, default: []].append(hit)
            }
            var groups: [[String: JSONValue]] = []
            var allValues: [String] = []
            for file in order {
                let fileHits = byFile[file] ?? []
                let values = Self.g5CaptureValues(patternSpec: patternSpec, hits: fileHits)
                for value in values where !allValues.contains(value) { allValues.append(value) }
                groups.append(Self.g5GroupJSON(label: file, hits: fileHits, values: values, redact: patternSpec.redact, sampleLimit: spec.sampleLimit))
            }
            return ["label": .string(patternSpec.label), "count": .int(Int64(hits.count)), "files": .array(groups), "values": .array(allValues.map { .string($0) })]
        case "host":
            var byHost: [String: [WorkspaceSearchHit]] = [:]
            var order: [String] = []
            for hit in hits {
                let host = Self.g5CaptureValues(patternSpec: patternSpec, hits: [hit]).first ?? ""
                if byHost[host] == nil { order.append(host) }
                byHost[host, default: []].append(hit)
            }
            var groups: [[String: JSONValue]] = []
            for host in order {
                let hostHits = byHost[host] ?? []
                groups.append(Self.g5GroupJSON(label: host, hits: hostHits, values: [], redact: patternSpec.redact, sampleLimit: spec.sampleLimit))
            }
            return ["label": .string(patternSpec.label), "count": .int(Int64(hits.count)), "hosts": .array(groups)]
        default:
            let values = Self.g5CaptureValues(patternSpec: patternSpec, hits: hits)
            return Self.g5GroupJSON(label: patternSpec.label, hits: hits, values: values, redact: patternSpec.redact, sampleLimit: spec.sampleLimit)
        }
    }

    private static func g5GroupJSON(label: String, hits: [WorkspaceSearchHit], values: [String], redact: Bool, sampleLimit: Int) -> [String: JSONValue] {
        var seen: Set<String> = []
        var unique: [WorkspaceSearchHit] = []
        for hit in hits {
            let key = "\(hit.path):\(hit.lineNumber)"
            if seen.insert(key).inserted { unique.append(hit) }
        }
        let shown = sampleLimit > 0 ? Array(unique.prefix(sampleLimit)) : unique
        return [
            "label": .string(label),
            "count": .int(Int64(unique.count)),
            "matches": .array(shown.map { Self.g5HitJSON($0, redact: redact) }),
            "values": .array(values.map { .string($0) }),
        ]
    }

    private static func g5HitJSON(_ hit: WorkspaceSearchHit, redact: Bool) -> JSONValue {
        if redact {
            return .object(["path": .string(hit.path), "lineNumber": .int(Int64(hit.lineNumber))])
        }
        return .object([
            "path": .string(hit.path),
            "lineNumber": .int(Int64(hit.lineNumber)),
            "lineText": .string(hit.lineText),
        ])
    }

    private static func g5CaptureValues(patternSpec: G5PatternSpec, hits: [WorkspaceSearchHit]) -> [String] {
        guard patternSpec.capture > 0 else { return [] }
        guard let regex = try? NSRegularExpression(pattern: patternSpec.pattern, options: []) else { return [] }
        var values: [String] = []
        for hit in hits {
            let range = NSRange(hit.lineText.startIndex..., in: hit.lineText)
            guard let match = regex.firstMatch(in: hit.lineText, options: [], range: range) else { continue }
            let captureRange = match.range(at: patternSpec.capture)
            guard captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: hit.lineText) else { continue }
            let value = String(hit.lineText[swiftRange])
            if !values.contains(value) { values.append(value) }
        }
        return values
    }

    private static func g5RegexMatches(pattern: String, text: String, options: NSRegularExpression.Options = []) -> [(NSRange, [String?])] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).map { match in
            var groups: [String?] = []
            for index in 0..<match.numberOfRanges {
                let groupRange = match.range(at: index)
                if groupRange.location == NSNotFound {
                    groups.append(nil)
                } else if let swiftRange = Range(groupRange, in: text) {
                    groups.append(String(text[swiftRange]))
                } else {
                    groups.append(nil)
                }
            }
            return (match.range, groups)
        }
    }

    private static func g5FirstCapture(pattern: String, text: String, group: Int, options: NSRegularExpression.Options = []) -> String? {
        let matches = Self.g5RegexMatches(pattern: pattern, text: text, options: options)
        guard let first = matches.first, group < first.1.count else { return nil }
        return first.1[group]
    }

    private static func g5CountSubstring(_ text: String, needle: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var rest = text[...]
        while let found = rest.range(of: needle) {
            count += 1
            rest = rest[found.upperBound...]
        }
        return count
    }

    private static func g5CountWord(_ text: String, word: String) -> Int {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
        return Self.g5RegexMatches(pattern: pattern, text: text).count
    }

    private static func g5Lines(_ content: String) -> [String] {
        content.components(separatedBy: "\n")
    }

    private static func g5FileCounts(_ content: String) -> (lines: Int, code: Int, comment: Int, blank: Int) {
        let lines = Self.g5Lines(content)
        var code = 0
        var comment = 0
        var blank = 0
        var inBlock = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blank += 1
                continue
            }
            if inBlock {
                comment += 1
                if trimmed.contains("*/") { inBlock = false }
                continue
            }
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") {
                comment += 1
                continue
            }
            if trimmed.hasPrefix("/*") {
                comment += 1
                if !trimmed.contains("*/") { inBlock = true }
                continue
            }
            code += 1
        }
        return (lines.count, code, comment, blank)
    }

    private static func g5ScopeEntries(_ entries: [WorkspaceFileEntry], path: String?) -> [WorkspaceFileEntry] {
        guard let path, !path.isEmpty else { return entries }
        return entries.filter { $0.path == path || $0.path.hasPrefix(path + "/") }
    }

    private static func g5ReadTextFiles(cwd: String, path: String?, extensions: [String], limit: Int, runtime: AgentsRuntimeClient) async throws -> [(path: String, content: String)] {
        let entries = try await runtime.listWorkspaceFiles(cwd: cwd, query: "", limit: 500)
        var scoped = Self.g5ScopeEntries(entries, path: path)
        scoped = scoped.filter { entry in
            !entry.isDirectory
            && !entry.path.hasPrefix(".")
            && !entry.path.contains("/.")
            && extensions.contains { entry.path.hasSuffix($0) }
        }
        var files: [(path: String, content: String)] = []
        for entry in scoped.prefix(limit) {
            guard let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: entry.path) else { continue }
            files.append((path: entry.path, content: document.content))
        }
        return files
    }

    private static func g5ResolvePbxproj(tool: String, cwd: String, path: String?, runtime: AgentsRuntimeClient) async throws -> String {
        if let path, !path.isEmpty { return path }
        let entries = try await runtime.listWorkspaceFiles(cwd: cwd, query: "project.pbxproj", limit: 20)
        guard let found = entries.first(where: { !$0.isDirectory }) else {
            throw SystemToolError.executionFailed(tool: tool, message: "No project.pbxproj found in the workspace.")
        }
        return found.path
    }


    static func parseG5FileSummary(tool: String, path: String, content: String) -> JSONValue {
        let counts = Self.g5FileCounts(content)
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "lines": .int(Int64(counts.lines)),
            "codeLines": .int(Int64(counts.code)),
            "commentLines": .int(Int64(counts.comment)),
            "blankLines": .int(Int64(counts.blank)),
        ])
    }

    static func parseG5Complexity(tool: String, path: String, content: String) -> JSONValue {
        let counts = Self.g5FileCounts(content)
        let keywords = ["if", "for", "while", "guard", "switch", "case", "catch"]
        let operators = ["&&", "||"]
        var keywordCounts: [[String: JSONValue]] = []
        var total = 0
        for keyword in keywords {
            let count = Self.g5CountWord(content, word: keyword)
            total += count
            keywordCounts.append(["keyword": .string(keyword), "count": .int(Int64(count))])
        }
        for op in operators {
            let count = Self.g5CountSubstring(content, needle: op)
            total += count
            keywordCounts.append(["keyword": .string(op), "count": .int(Int64(count))])
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "lines": .int(Int64(counts.lines)),
            "keywords": .array(keywordCounts),
            "complexityEstimate": .int(Int64(1 + total)),
        ])
    }

    private static func runG5Lint(tool: String, cwd: String, path: String?, limit: Int, runtime: AgentsRuntimeClient) async throws -> JSONValue {
        var files: [(path: String, content: String)] = []
        if let path, !path.isEmpty {
            let document = try await runtime.readWorkspaceFile(cwd: cwd, path: path)
            files = [(path: path, content: document.content)]
        } else {
            files = try await Self.g5ReadTextFiles(cwd: cwd, path: nil, extensions: [".swift"], limit: 100, runtime: runtime)
        }
        var issues: [[String: JSONValue]] = []
        for file in files {
            for (index, line) in Self.g5Lines(file.content).enumerated() {
                if line.count > 120 {
                    issues.append(["path": .string(file.path), "lineNumber": .int(Int64(index + 1)), "kind": .string("longLine"), "text": .string("Line is \(line.count) characters, over the 120 limit.")])
                }
                if line.contains("TODO") || line.contains("FIXME") {
                    issues.append(["path": .string(file.path), "lineNumber": .int(Int64(index + 1)), "kind": .string("todo"), "text": .string(line.trimmingCharacters(in: .whitespaces))])
                }
                if issues.count >= limit { break }
            }
            if issues.count >= limit { break }
        }
        return .object([
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "issues": .array(issues),
            "issueCount": .int(Int64(issues.count)),
        ])
    }

    static func parseG5DiagnosticsLog(tool: String, logPath: String, content: String) -> JSONValue {
        let lines = Self.g5Lines(content)
        let kinds: [(String, String, String)] = [
            ("fatalError", "fatal error", "A fatal error was logged; inspect the frames near the first fatal line."),
            ("exception", "EXC_", "An exception code was logged; match it against the exception type in the header."),
            ("crash", "crash", "A crash mention was logged; check the faulting thread section for blamed frames."),
            ("signal", "SIG", "A signal was logged; check which thread received it and what it was doing."),
            ("thread", "Thread ", "Thread mentions were logged; compare the faulting thread against the others."),
        ]
        var findings: [[String: JSONValue]] = []
        var leads: [String] = []
        for (kind, needle, lead) in kinds {
            var sample: [String] = []
            var count = 0
            for (index, line) in lines.enumerated() where line.contains(needle) {
                count += 1
                if sample.count < 3 {
                    sample.append("\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
            if count > 0 {
                leads.append(lead)
                findings.append(["kind": .string(kind), "count": .int(Int64(count)), "sampleLines": .array(sample.map { .string($0) })])
            }
        }
        return .object([
            "tool": .string(tool),
            "logPath": .string(logPath),
            "lines": .int(Int64(lines.count)),
            "findings": .array(findings),
            "leads": .array(leads.map { .string($0) }),
        ])
    }

    static func parseG5BuildLog(tool: String, path: String, content: String) -> JSONValue {
        let lines = Self.g5Lines(content)
        var errors: [[String: JSONValue]] = []
        var warnings: [[String: JSONValue]] = []
        var result = "unknown"
        for (index, line) in lines.enumerated() {
            if line.contains("BUILD SUCCEEDED") { result = "succeeded" }
            if line.contains("BUILD FAILED") { result = "failed" }
            if line.contains("error:") {
                errors.append(["lineNumber": .int(Int64(index + 1)), "text": .string(line.trimmingCharacters(in: .whitespaces))])
            } else if line.contains("warning:") {
                warnings.append(["lineNumber": .int(Int64(index + 1)), "text": .string(line.trimmingCharacters(in: .whitespaces))])
            }
        }
        if result == "unknown" && !errors.isEmpty { result = "failed" }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "result": .string(result),
            "errors": .array(errors),
            "warnings": .array(warnings),
            "errorCount": .int(Int64(errors.count)),
            "warningCount": .int(Int64(warnings.count)),
        ])
    }

    static func parseG5CrashLog(tool: String, path: String, content: String) -> JSONValue {
        let lines = Self.g5Lines(content)
        var exceptionType = ""
        var terminationReason = ""
        var faultingThread = -1
        var crashedThread = -1
        var blamedFrames: [String] = []
        var inCrashedThread = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let value = Self.g5FirstCapture(pattern: "^Exception Type:\\s*(.+)$", text: trimmed, group: 1) {
                exceptionType = value
            }
            if let value = Self.g5FirstCapture(pattern: "^Termination Reason:\\s*(.+)$", text: trimmed, group: 1) {
                terminationReason = value
            }
            if let value = Self.g5FirstCapture(pattern: "^Triggered by Thread:\\s*(\\d+)", text: trimmed, group: 1), let number = Int(value) {
                faultingThread = number
            }
            if let value = Self.g5FirstCapture(pattern: "^Thread (\\d+) Crashed:", text: trimmed, group: 1), let number = Int(value) {
                crashedThread = number
                inCrashedThread = true
                continue
            }
            if inCrashedThread {
                if trimmed.hasPrefix("Thread ") {
                    inCrashedThread = false
                    continue
                }
                if blamedFrames.count < 5, !trimmed.isEmpty {
                    blamedFrames.append(trimmed)
                }
            }
        }
        if faultingThread < 0 { faultingThread = crashedThread }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "exceptionType": .string(exceptionType),
            "terminationReason": .string(terminationReason),
            "faultingThread": .int(Int64(faultingThread)),
            "blamedFrames": .array(blamedFrames.map { .string($0) }),
        ])
    }

    static func parseG5TestLog(tool: String, path: String, content: String) -> JSONValue {
        let lines = Self.g5Lines(content)
        var passed = 0
        var failed = 0
        var failedTests: [String] = []
        var suites: [String: (passed: Int, failed: Int)] = [:]
        var suiteOrder: [String] = []
        var errorLines: [[String: JSONValue]] = []
        var currentSuite = ""
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let suite = Self.g5FirstCapture(pattern: "Test Suite '([^']+)' started", text: trimmed, group: 1) {
                currentSuite = suite
                if suites[suite] == nil {
                    suites[suite] = (passed: 0, failed: 0)
                    suiteOrder.append(suite)
                }
            } else if Self.g5FirstCapture(pattern: "Test Suite '([^']+)' finished", text: trimmed, group: 1) != nil {
                currentSuite = ""
            } else if let name = Self.g5FirstCapture(pattern: "Test Case '-\\[([^\\]]+)\\]' failed", text: trimmed, group: 1) {
                failed += 1
                failedTests.append(name)
                if !currentSuite.isEmpty { suites[currentSuite]?.failed += 1 }
            } else if Self.g5FirstCapture(pattern: "Test Case '-\\[([^\\]]+)\\]' passed", text: trimmed, group: 1) != nil {
                passed += 1
                if !currentSuite.isEmpty { suites[currentSuite]?.passed += 1 }
            }
            if trimmed.contains(": error:") {
                errorLines.append(["lineNumber": .int(Int64(index + 1)), "text": .string(trimmed)])
            }
        }
        var suiteJSON: [[String: JSONValue]] = []
        for suite in suiteOrder {
            let counts = suites[suite] ?? (passed: 0, failed: 0)
            suiteJSON.append(["name": .string(suite), "passed": .int(Int64(counts.passed)), "failed": .int(Int64(counts.failed))])
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "passed": .int(Int64(passed)),
            "failed": .int(Int64(failed)),
            "failedTests": .array(failedTests.map { .string($0) }),
            "suites": .array(suiteJSON),
            "errorLines": .array(errorLines),
        ])
    }

    static func parseG5FlakyTests(tool: String, path: String, content: String) -> JSONValue {
        let lines = Self.g5Lines(content)
        var outcomes: [String: (passes: Int, failures: Int)] = [:]
        var order: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let name = Self.g5FirstCapture(pattern: "Test Case '-\\[([^\\]]+)\\]' failed", text: trimmed, group: 1) {
                if outcomes[name] == nil { order.append(name); outcomes[name] = (passes: 0, failures: 0) }
                outcomes[name]?.failures += 1
            } else if let name = Self.g5FirstCapture(pattern: "Test Case '-\\[([^\\]]+)\\]' passed", text: trimmed, group: 1) {
                if outcomes[name] == nil { order.append(name); outcomes[name] = (passes: 0, failures: 0) }
                outcomes[name]?.passes += 1
            }
        }
        var flaky: [[String: JSONValue]] = []
        for name in order {
            let outcome = outcomes[name] ?? (passes: 0, failures: 0)
            if outcome.passes > 0 && outcome.failures > 0 {
                flaky.append(["name": .string(name), "passes": .int(Int64(outcome.passes)), "failures": .int(Int64(outcome.failures))])
            }
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "flaky": .array(flaky),
            "flakyCount": .int(Int64(flaky.count)),
        ])
    }

    static func parseG5Metrics(tool: String, files: [(path: String, content: String)]) -> JSONValue {
        var fileJSON: [[String: JSONValue]] = []
        var totalLines = 0
        var totalCode = 0
        var totalComment = 0
        var totalBlank = 0
        var totalFunctions = 0
        var totalTypes = 0
        var totalComplexity = 0
        for file in files {
            let counts = Self.g5FileCounts(file.content)
            let functions = Self.g5RegexMatches(pattern: "^\\s*(?:(?:public|open|internal|private|fileprivate)\\s+)?(?:static\\s+)?func\\s+[A-Za-z0-9_]+", text: file.content, options: [.anchorsMatchLines]).count
            let types = Self.g5RegexMatches(pattern: "^\\s*(?:(?:public|open|internal|private|fileprivate)\\s+)?(?:final\\s+)?(class|struct|enum|protocol)\\s+[A-Za-z0-9_]+", text: file.content, options: [.anchorsMatchLines]).count
            var complexity = 1
            for keyword in ["if", "for", "while", "guard", "switch", "case", "catch"] {
                complexity += Self.g5CountWord(file.content, word: keyword)
            }
            complexity += Self.g5CountSubstring(file.content, needle: "&&")
            complexity += Self.g5CountSubstring(file.content, needle: "||")
            totalLines += counts.lines
            totalCode += counts.code
            totalComment += counts.comment
            totalBlank += counts.blank
            totalFunctions += functions
            totalTypes += types
            totalComplexity += complexity
            fileJSON.append([
                "path": .string(file.path),
                "lines": .int(Int64(counts.lines)),
                "codeLines": .int(Int64(counts.code)),
                "commentLines": .int(Int64(counts.comment)),
                "blankLines": .int(Int64(counts.blank)),
                "functions": .int(Int64(functions)),
                "types": .int(Int64(types)),
                "complexityEstimate": .int(Int64(complexity)),
            ])
        }
        fileJSON.sort { ($0["lines"]?.intValue ?? 0) > ($1["lines"]?.intValue ?? 0) }
        return .object([
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "totals": .object([
                "lines": .int(Int64(totalLines)),
                "codeLines": .int(Int64(totalCode)),
                "commentLines": .int(Int64(totalComment)),
                "blankLines": .int(Int64(totalBlank)),
                "functions": .int(Int64(totalFunctions)),
                "types": .int(Int64(totalTypes)),
                "complexityEstimate": .int(Int64(totalComplexity)),
            ]),
            "files": .array(fileJSON),
        ])
    }

    static func parseG5CommentDensity(tool: String, files: [(path: String, content: String)], limit: Int) -> JSONValue {
        var fileJSON: [[String: JSONValue]] = []
        for file in files {
            let counts = Self.g5FileCounts(file.content)
            let documented = counts.code + counts.comment
            let ratio = documented > 0 ? Double(counts.comment) / Double(documented) : 0
            fileJSON.append([
                "path": .string(file.path),
                "lines": .int(Int64(counts.lines)),
                "codeLines": .int(Int64(counts.code)),
                "commentLines": .int(Int64(counts.comment)),
                "commentRatio": .double(ratio),
            ])
        }
        fileJSON.sort { ($0["commentRatio"]?.doubleValue ?? 0) < ($1["commentRatio"]?.doubleValue ?? 0) }
        return .object([
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "files": .array(Array(fileJSON.prefix(limit))),
        ])
    }

    static func parseG5FunctionSizes(tool: String, files: [(path: String, content: String)], limit: Int) -> JSONValue {
        var functions: [[String: JSONValue]] = []
        for file in files {
            let lines = Self.g5Lines(file.content)
            var index = 0
            while index < lines.count {
                let line = lines[index]
                guard let name = Self.g5FirstCapture(pattern: "^\\s*(?:(?:public|open|internal|private|fileprivate)\\s+)?(?:static\\s+)?func\\s+([A-Za-z0-9_]+)", text: line, group: 1) else {
                    index += 1
                    continue
                }
                var depth = 0
                var started = false
                var end = index
                var cursor = index
                while cursor < lines.count {
                    for character in lines[cursor] {
                        if character == "{" { depth += 1; started = true }
                        if character == "}" { depth -= 1 }
                    }
                    if started && depth <= 0 {
                        end = cursor
                        break
                    }
                    cursor += 1
                }
                if started {
                    functions.append([
                        "name": .string(name),
                        "path": .string(file.path),
                        "startLine": .int(Int64(index + 1)),
                        "endLine": .int(Int64(end + 1)),
                        "lines": .int(Int64(end - index + 1)),
                    ])
                    index = max(end + 1, index + 1)
                } else {
                    index += 1
                }
            }
        }
        functions.sort { ($0["lines"]?.intValue ?? 0) > ($1["lines"]?.intValue ?? 0) }
        return .object([
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "functions": .array(Array(functions.prefix(limit))),
        ])
    }


    static func parseG5DeadCode(tool: String, files: [(path: String, content: String)], privateOnly: Bool, limit: Int) -> JSONValue {
        struct G5Declaration {
            var name: String
            var kind: String
            var access: String
            var path: String
            var line: Int
        }
        var declarations: [G5Declaration] = []
        var declarationCounts: [String: Int] = [:]
        for file in files {
            for (index, line) in Self.g5Lines(file.content).enumerated() {
                guard let match = Self.g5RegexMatches(pattern: "^\\s*(private\\s+|fileprivate\\s+|internal\\s+|public\\s+|open\\s+)?(func|class|struct|enum|protocol|let|var|typealias)\\s+([A-Za-z0-9_]+)", text: line, options: [.anchorsMatchLines]).first else { continue }
                let access = (match.1.count > 1 ? match.1[1] : nil)?.trimmingCharacters(in: .whitespaces) ?? ""
                let kind = match.1.count > 2 ? (match.1[2] ?? "") : ""
                let name = match.1.count > 3 ? (match.1[3] ?? "") : ""
                guard !name.isEmpty, !kind.isEmpty else { continue }
                declarations.append(G5Declaration(name: name, kind: kind, access: access, path: file.path, line: index + 1))
                declarationCounts[name, default: 0] += 1
            }
        }
        var candidates: [[String: JSONValue]] = []
        for declaration in declarations {
            if declarationCounts[declaration.name, default: 0] > 1 { continue }
            if privateOnly && !(declaration.access == "private" && declaration.kind == "func") { continue }
            var references = 0
            for file in files {
                references += Self.g5CountWord(file.content, word: declaration.name)
            }
            if references <= 1 {
                candidates.append([
                    "name": .string(declaration.name),
                    "kind": .string(declaration.kind),
                    "path": .string(declaration.path),
                    "lineNumber": .int(Int64(declaration.line)),
                ])
            }
            if candidates.count >= limit { break }
        }
        var result: [String: JSONValue] = [
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "declarations": .int(Int64(declarations.count)),
            "candidates": .array(candidates),
            "candidateCount": .int(Int64(candidates.count)),
        ]
        if privateOnly {
            result["reportOnly"] = .bool(true)
        }
        return .object(result)
    }

    static func parseG5DuplicateBlocks(tool: String, files: [(path: String, content: String)], limit: Int) -> JSONValue {
        let window = 6
        var blocks: [String: [(path: String, line: Int)]] = [:]
        var order: [String] = []
        for file in files {
            let normalized = Self.g5Lines(file.content).map { line in
                line.split(separator: " ").map(String.init).joined(separator: " ")
            }.filter { !$0.isEmpty }
            var lineNumbers: [Int] = []
            for (index, line) in Self.g5Lines(file.content).enumerated() {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { lineNumbers.append(index + 1) }
            }
            guard normalized.count >= window else { continue }
            for start in 0...(normalized.count - window) {
                let key = normalized[start..<(start + window)].joined(separator: "\n")
                if blocks[key] == nil { order.append(key) }
                blocks[key, default: []].append((path: file.path, line: lineNumbers[start]))
            }
        }
        var duplicates: [[String: JSONValue]] = []
        for key in order {
            let occurrences = blocks[key] ?? []
            let distinct = Set(occurrences.map { "\($0.path):\($0.line)" })
            guard distinct.count > 1 else { continue }
            duplicates.append([
                "lines": .int(6),
                "occurrences": .array(occurrences.map { occurrence in
                    .object(["path": .string(occurrence.path), "lineNumber": .int(Int64(occurrence.line))])
                }),
            ])
            if duplicates.count >= limit { break }
        }
        return .object([
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "blocks": .array(duplicates),
            "blockCount": .int(Int64(duplicates.count)),
        ])
    }

    static func parseG5UnusedImports(tool: String, files: [(path: String, content: String)], limit: Int) -> JSONValue {
        var unused: [[String: JSONValue]] = []
        for file in files {
            let lines = Self.g5Lines(file.content)
            for (index, line) in lines.enumerated() {
                guard let module = Self.g5FirstCapture(pattern: "^import\\s+([A-Za-z0-9_]+)", text: line, group: 1) else { continue }
                if Self.g5ProtectedModules.contains(module) { continue }
                var body = ""
                for (otherIndex, other) in lines.enumerated() where otherIndex != index {
                    body += other
                    body += "\n"
                }
                if Self.g5CountWord(body, word: module) == 0 {
                    unused.append([
                        "path": .string(file.path),
                        "module": .string(module),
                        "lineNumber": .int(Int64(index + 1)),
                    ])
                }
                if unused.count >= limit { break }
            }
            if unused.count >= limit { break }
        }
        return .object([
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "unused": .array(unused),
            "unusedCount": .int(Int64(unused.count)),
        ])
    }

    static func parseG5LicenseCheck(tool: String, files: [(path: String, content: String)], requiredText: String) -> JSONValue {
        var missing: [String] = []
        for file in files {
            let head = Self.g5Lines(file.content).prefix(15).joined(separator: "\n")
            if !head.contains(requiredText) {
                missing.append(file.path)
            }
        }
        return .object([
            "tool": .string(tool),
            "requiredText": .string(requiredText),
            "filesChecked": .int(Int64(files.count)),
            "missing": .array(missing.map { .string($0) }),
            "missingCount": .int(Int64(missing.count)),
        ])
    }

    static func parseG5DocCoverage(tool: String, files: [(path: String, content: String)]) -> JSONValue {
        var declarations = 0
        var documented = 0
        for file in files {
            let lines = Self.g5Lines(file.content)
            for (index, line) in lines.enumerated() {
                guard Self.g5RegexMatches(pattern: "^\\s*(public|open)\\s+(func|class|struct|enum|protocol|var|let|typealias)\\s+[A-Za-z0-9_]+", text: line, options: [.anchorsMatchLines]).first != nil else { continue }
                declarations += 1
                var cursor = index - 1
                while cursor >= 0 {
                    let previous = lines[cursor].trimmingCharacters(in: .whitespaces)
                    if previous.isEmpty {
                        cursor -= 1
                        continue
                    }
                    if previous.hasPrefix("///") { documented += 1 }
                    break
                }
            }
        }
        let coverage = declarations > 0 ? Double(documented) / Double(declarations) : 1
        return .object([
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "declarations": .int(Int64(declarations)),
            "documented": .int(Int64(documented)),
            "coverage": .double(coverage),
        ])
    }

    static func parseG5Docstring(tool: String, path: String, content: String, symbol: String?) -> JSONValue {
        var declarations: [[String: JSONValue]] = []
        for (index, line) in Self.g5Lines(content).enumerated() {
            guard let match = Self.g5RegexMatches(pattern: "^\\s*(?:(?:public|open|internal|private|fileprivate)\\s+)?(func|class|struct|enum|protocol|init|var|let|typealias)\\s+([A-Za-z0-9_]+)", text: line, options: [.anchorsMatchLines]).first else { continue }
            let kind = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let name = match.1.count > 2 ? (match.1[2] ?? "") : ""
            guard !name.isEmpty else { continue }
            if let symbol, symbol != name { continue }
            var block: [String] = ["/// \(name)"]
            if kind == "func" {
                let parameters = Self.g5FirstCapture(pattern: "\\(([^)]*)\\)", text: line, group: 1) ?? ""
                let names = parameters.split(separator: ",").compactMap { part -> String? in
                    let pieces = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
                    guard let first = pieces.first else { return nil }
                    let cleaned = first.hasPrefix("_") ? String(first.dropFirst()) : String(first)
                    return cleaned.isEmpty ? nil : cleaned
                }
                if !names.isEmpty {
                    block.append("///")
                    block.append("/// - Parameters:")
                    for parameter in names {
                        block.append("///   - \(parameter): ")
                    }
                }
                if line.contains("->") {
                    block.append("///")
                    block.append("/// - Returns: ")
                }
            }
            declarations.append([
                "name": .string(name),
                "kind": .string(kind),
                "lineNumber": .int(Int64(index + 1)),
                "docBlock": .string(block.joined(separator: "\n")),
            ])
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "declarations": .array(declarations),
        ])
    }

    static func g5SnippetTemplate(_ template: String) -> String? {
        switch template {
        case "observable":
            return "@Observable\nfinal class Store {\n    var title = \"\"\n    var items: [String] = []\n}\n"
        case "asyncstream":
            return "func makeStream() -> AsyncStream<String> {\n    AsyncStream { continuation in\n        continuation.yield(\"ready\")\n        continuation.finish()\n    }\n}\n"
        case "actor":
            return "actor Counter {\n    private var value = 0\n    func next() -> Int {\n        value += 1\n        return value\n    }\n}\n"
        case "glasscard":
            return "struct GlassCard: View {\n    var body: some View {\n        Text(\"Card\")\n            .padding()\n            .glassEffect()\n    }\n}\n"
        default:
            return nil
        }
    }

    private static func runG5Snippet(tool: String, arguments: [String: JSONValue], runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let cwd = try requiredString(arguments, "cwd", tool: tool)
        let template = try requiredString(arguments, "template", tool: tool)
        guard let content = Self.g5SnippetTemplate(template) else {
            throw SystemToolError.executionFailed(tool: tool, message: "Unknown template. Use observable, asyncstream, actor, or glasscard.")
        }
        if let path = optionalString(arguments, "path"), !path.isEmpty {
            try await runtime.writeWorkspaceFile(cwd: cwd, path: path, content: content)
            return .object([
                "tool": .string(tool),
                "template": .string(template),
                "written": .bool(true),
                "path": .string(path),
                "content": .string(content),
            ])
        }
        return .object([
            "tool": .string(tool),
            "template": .string(template),
            "written": .bool(false),
            "content": .string(content),
        ])
    }

    private static func runG5StringsValidate(tool: String, cwd: String, path: String?, limit: Int, runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".strings"], limit: 100, runtime: runtime)
        var issues: [[String: JSONValue]] = []
        for file in files {
            var seen: Set<String> = []
            for (index, line) in Self.g5Lines(file.content).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") { continue }
                guard let match = Self.g5RegexMatches(pattern: "^\"((?:[^\"\\\\]|\\\\.)*)\"\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*;", text: trimmed).first else {
                    issues.append(["path": .string(file.path), "lineNumber": .int(Int64(index + 1)), "kind": .string("syntax"), "key": .string("")])
                    continue
                }
                let key = match.1.count > 1 ? (match.1[1] ?? "") : ""
                let value = match.1.count > 2 ? (match.1[2] ?? "") : ""
                if seen.contains(key) {
                    issues.append(["path": .string(file.path), "lineNumber": .int(Int64(index + 1)), "kind": .string("duplicate"), "key": .string(key)])
                } else {
                    seen.insert(key)
                }
                if value.isEmpty {
                    issues.append(["path": .string(file.path), "lineNumber": .int(Int64(index + 1)), "kind": .string("empty"), "key": .string(key)])
                }
                if issues.count >= limit { break }
            }
            if issues.count >= limit { break }
        }
        return .object([
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "issues": .array(issues),
            "issueCount": .int(Int64(issues.count)),
        ])
    }

    static func parseG5PlistKeyValues(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        let keyMatches = Self.g5RegexMatches(pattern: "<key>([^<]+)</key>", text: text)
        for keyMatch in keyMatches {
            guard let key = keyMatch.1.count > 1 ? keyMatch.1[1] : nil, !key.isEmpty else { continue }
            let afterStart = keyMatch.0.location + keyMatch.0.length
            guard let textRange = Range(NSRange(location: afterStart, length: (text as NSString).length - afterStart), in: text) else { continue }
            let rest = String(text[textRange])
            if let tagMatch = Self.g5RegexMatches(pattern: "^\\s*<(string|integer|real|date|data)>([^<]*)</\\1>", text: rest).first {
                values[key] = tagMatch.1.count > 2 ? (tagMatch.1[2] ?? "") : ""
            } else if rest.trimmingCharacters(in: .whitespaces).hasPrefix("<true/>") {
                values[key] = "true"
            } else if rest.trimmingCharacters(in: .whitespaces).hasPrefix("<false/>") {
                values[key] = "false"
            } else if let tagMatch = Self.g5RegexMatches(pattern: "^\\s*<(array|dict)>", text: rest).first {
                values[key] = "<" + (tagMatch.1.count > 1 ? (tagMatch.1[1] ?? "") : "") + ">"
            } else if let stepMatch = Self.g5RegexMatches(pattern: "^\\s*([A-Za-z0-9_.-]+)\\s*=\\s*([^;]+);", text: rest).first {
                values[key] = stepMatch.1.count > 2 ? (stepMatch.1[2] ?? "") : ""
            }
        }
        if values.isEmpty {
            for line in Self.g5Lines(text) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let match = Self.g5RegexMatches(pattern: "^([A-Za-z0-9_.-]+)\\s*=\\s*([^;]+);", text: trimmed).first {
                    let key = match.1.count > 1 ? (match.1[1] ?? "") : ""
                    let value = match.1.count > 2 ? (match.1[2] ?? "") : ""
                    if !key.isEmpty { values[key] = value.trimmingCharacters(in: .whitespaces) }
                }
            }
        }
        return values
    }

    static func parseG5XcconfigKeyValues(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in Self.g5Lines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") { continue }
            guard let match = Self.g5RegexMatches(pattern: "^([A-Za-z0-9_\\.\\[\\]\\*]+)\\s*=\\s*(.+)$", text: trimmed).first else { continue }
            let key = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let value = match.1.count > 2 ? (match.1[2] ?? "") : ""
            if !key.isEmpty { values[key] = value.trimmingCharacters(in: .whitespaces) }
        }
        return values
    }

    static func parseG5KeyValueDiff(tool: String, path: String, otherPath: String, first: [String: String], second: [String: String]) -> JSONValue {
        var added: [String] = []
        var removed: [String] = []
        var changed: [[String: JSONValue]] = []
        for key in second.keys.sorted() where first[key] == nil {
            added.append(key)
        }
        for key in first.keys.sorted() where second[key] == nil {
            removed.append(key)
        }
        for key in first.keys.sorted() {
            if let old = first[key], let new = second[key], old != new {
                changed.append(["key": .string(key), "from": .string(old), "to": .string(new)])
            }
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "otherPath": .string(otherPath),
            "added": .array(added.map { .string($0) }),
            "removed": .array(removed.map { .string($0) }),
            "changed": .array(changed),
        ])
    }


    static func g5PbxprojSection(_ content: String, name: String) -> String {
        guard let start = content.range(of: "/* Begin \(name) section */"),
              let end = content.range(of: "/* End \(name) section */"),
              start.upperBound <= end.lowerBound else { return "" }
        return String(content[start.upperBound..<end.lowerBound])
    }

    static func g5PbxprojFileRefs(_ content: String) -> [String: String] {
        var refs: [String: String] = [:]
        let section = Self.g5PbxprojSection(content, name: "PBXFileReference")
        for match in Self.g5RegexMatches(pattern: "([0-9A-F]{24})\\s*/\\* [^*]+ \\*/\\s*=\\s*\\{[^}]*?path\\s*=\\s*\"?([^\";\\n]+)\"?;", text: section, options: [.dotMatchesLineSeparators]) {
            let id = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let path = match.1.count > 2 ? (match.1[2] ?? "").trimmingCharacters(in: .whitespaces) : ""
            if !id.isEmpty && !path.isEmpty { refs[id] = path }
        }
        return refs
    }

    static func g5PbxprojBuildFiles(_ content: String) -> [String: String] {
        var files: [String: String] = [:]
        let section = Self.g5PbxprojSection(content, name: "PBXBuildFile")
        for match in Self.g5RegexMatches(pattern: "([0-9A-F]{24})\\s*/\\* [^*]+ \\*/\\s*=\\s*\\{[^}]*?fileRef\\s*=\\s*([0-9A-F]{24})\\s*;", text: section, options: [.dotMatchesLineSeparators]) {
            let id = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let ref = match.1.count > 2 ? (match.1[2] ?? "") : ""
            if !id.isEmpty && !ref.isEmpty { files[id] = ref }
        }
        return files
    }

    static func parseG5PbxprojLint(tool: String, path: String, content: String, workspacePaths: [String]) -> JSONValue {
        let refs = Self.g5PbxprojFileRefs(content)
        var missing: [[String: JSONValue]] = []
        var seenPaths: [String: String] = [:]
        var duplicates: [String] = []
        for refPath in refs.values.sorted() {
            if seenPaths[refPath] != nil {
                if !duplicates.contains(refPath) { duplicates.append(refPath) }
                continue
            }
            seenPaths[refPath] = refPath
            let exists = workspacePaths.contains { workspacePath in
                workspacePath == refPath || workspacePath.hasSuffix("/" + refPath)
            }
            if !exists {
                missing.append(["path": .string(refPath), "reference": .string(refPath)])
            }
        }
        let buildFiles = Self.g5PbxprojBuildFiles(content)
        var dangling: [String] = []
        for (id, ref) in buildFiles.sorted(by: { $0.key < $1.key }) where refs[ref] == nil {
            dangling.append(id)
        }
        let issueCount = missing.count + duplicates.count + dangling.count
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "fileReferences": .int(Int64(refs.count)),
            "missingFiles": .array(missing),
            "duplicatePaths": .array(duplicates.map { .string($0) }),
            "danglingBuildFiles": .array(dangling.map { .string($0) }),
            "issueCount": .int(Int64(issueCount)),
        ])
    }

    static func parseG5PbxprojScripts(tool: String, path: String, content: String) -> JSONValue {
        var phases: [[String: JSONValue]] = []
        let section = Self.g5PbxprojSection(content, name: "PBXShellScriptBuildPhase")
        for match in Self.g5RegexMatches(pattern: "\\{[^}]*?isa\\s*=\\s*PBXShellScriptBuildPhase;[^}]*?\\}", text: section, options: [.dotMatchesLineSeparators]) {
            guard let block = match.1.count > 0 ? match.1[0] : nil else { continue }
            let name = Self.g5FirstCapture(pattern: "name\\s*=\\s*\"?([^\";\\n]+)\"?;", text: block, group: 1) ?? ""
            let shellPath = Self.g5FirstCapture(pattern: "shellPath\\s*=\\s*([^;\\n]+);", text: block, group: 1) ?? ""
            var script = Self.g5FirstCapture(pattern: "shellScript\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\";", text: block, group: 1, options: [.dotMatchesLineSeparators]) ?? ""
            if script.count > 200 {
                script = String(script.prefix(200))
            }
            phases.append([
                "name": .string(name.trimmingCharacters(in: .whitespaces)),
                "shellPath": .string(shellPath.trimmingCharacters(in: .whitespaces)),
                "script": .string(script),
            ])
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "phases": .array(phases),
        ])
    }

    static func parseG5PbxprojConfigs(tool: String, path: String, content: String, xcconfigFiles: [String]) -> JSONValue {
        var configurations: [String] = []
        let section = Self.g5PbxprojSection(content, name: "XCBuildConfiguration")
        for match in Self.g5RegexMatches(pattern: "name\\s*=\\s*([^;\\n]+);", text: section) {
            let name = (match.1.count > 1 ? (match.1[1] ?? "") : "").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !configurations.contains(name) { configurations.append(name) }
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "configurations": .array(configurations.map { .string($0) }),
            "configurationCount": .int(Int64(configurations.count)),
            "xcconfigFiles": .array(xcconfigFiles.map { .string($0) }),
        ])
    }

    static func parseG5PbxprojDeps(tool: String, path: String, content: String) -> JSONValue {
        var targetNames: [String: String] = [:]
        var targetDeps: [String: [String]] = [:]
        let targetSection = Self.g5PbxprojSection(content, name: "PBXNativeTarget")
        for match in Self.g5RegexMatches(pattern: "([0-9A-F]{24})\\s*/\\* ([^*]+) \\*/\\s*=\\s*\\{[^}]*?\\}", text: targetSection, options: [.dotMatchesLineSeparators]) {
            let id = match.1.count > 1 ? (match.1[1] ?? "") : ""
            guard !id.isEmpty, let block = match.1.count > 0 ? match.1[0] : nil else { continue }
            let name = Self.g5FirstCapture(pattern: "name\\s*=\\s*([^;\\n]+);", text: block, group: 1)?.trimmingCharacters(in: .whitespaces) ?? ""
            let depList = Self.g5FirstCapture(pattern: "dependencies\\s*=\\s*\\(([^)]*)\\)", text: block, group: 1, options: [.dotMatchesLineSeparators]) ?? ""
            targetNames[id] = name
            targetDeps[id] = Self.g5RegexMatches(pattern: "([0-9A-F]{24})", text: depList).compactMap { $0.1.count > 1 ? $0.1[1] : nil }
        }
        var depTargets: [String: String] = [:]
        let depSection = Self.g5PbxprojSection(content, name: "PBXTargetDependency")
        for match in Self.g5RegexMatches(pattern: "([0-9A-F]{24})[^\\{]*\\{[^}]*?target\\s*=\\s*([0-9A-F]{24})\\s*;", text: depSection, options: [.dotMatchesLineSeparators]) {
            let id = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let target = match.1.count > 2 ? (match.1[2] ?? "") : ""
            if !id.isEmpty { depTargets[id] = target }
        }
        var targets: [[String: JSONValue]] = []
        for id in targetDeps.keys.sorted() {
            let dependencies = (targetDeps[id] ?? []).compactMap { depTargets[$0] }.compactMap { targetNames[$0] }
            targets.append([
                "name": .string(targetNames[id] ?? id),
                "dependencies": .array(dependencies.map { .string($0) }),
            ])
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "targets": .array(targets),
        ])
    }

    static func parseG5PbxprojSources(tool: String, path: String, content: String) -> JSONValue {
        let refs = Self.g5PbxprojFileRefs(content)
        let buildFiles = Self.g5PbxprojBuildFiles(content)
        var phaseOwners: [String: String] = [:]
        let targetSection = Self.g5PbxprojSection(content, name: "PBXNativeTarget")
        for match in Self.g5RegexMatches(pattern: "([0-9A-F]{24})\\s*/\\* ([^*]+) \\*/\\s*=\\s*\\{[^}]*?buildPhases\\s*=\\s*\\(([^)]*)\\)", text: targetSection, options: [.dotMatchesLineSeparators]) {
            let name = match.1.count > 2 ? (match.1[2] ?? "").trimmingCharacters(in: .whitespaces) : ""
            let phaseList = match.1.count > 3 ? (match.1[3] ?? "") : ""
            for phaseMatch in Self.g5RegexMatches(pattern: "([0-9A-F]{24})", text: phaseList) {
                if let phaseId = phaseMatch.1.count > 1 ? phaseMatch.1[1] : nil {
                    phaseOwners[phaseId] = name
                }
            }
        }
        var byTarget: [String: [String]] = [:]
        var targetOrder: [String] = []
        let sourcesSection = Self.g5PbxprojSection(content, name: "PBXSourcesBuildPhase")
        for match in Self.g5RegexMatches(pattern: "([0-9A-F]{24})[^\\{]*\\{[^}]*?files\\s*=\\s*\\(([^)]*)\\)", text: sourcesSection, options: [.dotMatchesLineSeparators]) {
            let phaseId = match.1.count > 1 ? (match.1[1] ?? "") : ""
            let fileList = match.1.count > 2 ? (match.1[2] ?? "") : ""
            let owner = phaseOwners[phaseId] ?? ""
            if byTarget[owner] == nil { targetOrder.append(owner) }
            for fileMatch in Self.g5RegexMatches(pattern: "([0-9A-F]{24})", text: fileList) {
                guard let buildId = fileMatch.1.count > 1 ? fileMatch.1[1] : nil,
                      let refId = buildFiles[buildId],
                      let filePath = refs[refId] else { continue }
                byTarget[owner, default: []].append(filePath)
            }
        }
        var targets: [[String: JSONValue]] = []
        for owner in targetOrder {
            targets.append([
                "name": .string(owner),
                "sources": .array((byTarget[owner] ?? []).map { .string($0) }),
            ])
        }
        return .object([
            "tool": .string(tool),
            "path": .string(path),
            "targets": .array(targets),
        ])
    }

    private static func runG5WorkspaceSettings(tool: String, cwd: String, path: String?, runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let resolved: String
        if let path, !path.isEmpty {
            resolved = path
        } else {
            let entries = try await runtime.listWorkspaceFiles(cwd: cwd, query: ".xcsettings", limit: 20)
            guard let found = entries.first(where: { !$0.isDirectory }) else {
                return .object(["tool": .string(tool), "found": .bool(false), "settings": .object([:])])
            }
            resolved = found.path
        }
        let document = try await runtime.readWorkspaceFile(cwd: cwd, path: resolved)
        let settings = Self.parseG5PlistKeyValues(document.content)
        return .object([
            "tool": .string(tool),
            "path": .string(resolved),
            "found": .bool(true),
            "settings": .object(settings.mapValues { .string($0) }),
        ])
    }

    private static func runG5TestPlans(tool: String, cwd: String, path: String?, runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".xctestplan"], limit: 100, runtime: runtime)
        var plans: [[String: JSONValue]] = []
        for file in files {
            var targets: [String] = []
            if let data = file.content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let testTargets = json["testTargets"] as? [[String: Any]] {
                for entry in testTargets {
                    if let target = entry["target"] as? [String: Any], let name = target["name"] as? String {
                        targets.append(name)
                    } else if let target = entry["target"] as? String {
                        targets.append(target)
                    }
                }
            }
            plans.append([
                "path": .string(file.path),
                "testTargets": .array(targets.map { .string($0) }),
            ])
        }
        return .object([
            "tool": .string(tool),
            "plans": .array(plans),
        ])
    }

    private static func runG5InfoPlistAudit(tool: String, cwd: String, path: String?, runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: ["Info.plist"], limit: 50, runtime: runtime)
        var plists: [[String: JSONValue]] = []
        var bundleIds: [String: Int] = [:]
        for file in files {
            let values = Self.parseG5PlistKeyValues(file.content)
            var issues: [String] = []
            let bundleId = values["CFBundleIdentifier"] ?? ""
            let shortVersion = values["CFBundleShortVersionString"] ?? ""
            let version = values["CFBundleVersion"] ?? ""
            if bundleId.isEmpty { issues.append("Missing CFBundleIdentifier.") }
            if values["CFBundleName"] == nil && values["CFBundleDisplayName"] == nil { issues.append("Missing CFBundleName.") }
            if shortVersion.isEmpty {
                issues.append("Missing CFBundleShortVersionString.")
            } else if Self.g5RegexMatches(pattern: "^[0-9]+(\\.[0-9]+){0,2}$", text: shortVersion).isEmpty {
                issues.append("CFBundleShortVersionString is not a dotted version.")
            }
            if version.isEmpty {
                issues.append("Missing CFBundleVersion.")
            } else if Self.g5RegexMatches(pattern: "^[0-9]+(\\.[0-9]+){0,2}$", text: version).isEmpty {
                issues.append("CFBundleVersion is not a dotted version.")
            }
            if !bundleId.isEmpty { bundleIds[bundleId, default: 0] += 1 }
            plists.append([
                "path": .string(file.path),
                "bundleIdentifier": .string(bundleId),
                "shortVersion": .string(shortVersion),
                "version": .string(version),
                "issues": .array(issues.map { .string($0) }),
            ])
        }
        let duplicates = bundleIds.filter { $0.value > 1 }.map { $0.key }.sorted()
        return .object([
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "plists": .array(plists),
            "duplicateBundleIdentifiers": .array(duplicates.map { .string($0) }),
        ])
    }

    private static func runG5MarkdownLinks(tool: String, cwd: String, path: String?, limit: Int, runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let entries = try await runtime.listWorkspaceFiles(cwd: cwd, query: "", limit: 500)
        let workspacePaths = Set(entries.filter { !$0.isDirectory }.map { $0.path })
        let files = try await Self.g5ReadTextFiles(cwd: cwd, path: path, extensions: [".md"], limit: 100, runtime: runtime)
        var broken: [[String: JSONValue]] = []
        var linkCount = 0
        for file in files {
            let directory = (file.path as NSString).deletingLastPathComponent
            for (index, line) in Self.g5Lines(file.content).enumerated() {
                for match in Self.g5RegexMatches(pattern: "\\[[^\\]]*\\]\\(([^)\\s]+)\\)", text: line) {
                    guard let target = match.1.count > 1 ? match.1[1] : nil, !target.isEmpty else { continue }
                    if target.hasPrefix("http://") || target.hasPrefix("https://") || target.hasPrefix("mailto:") || target.hasPrefix("#") { continue }
                    linkCount += 1
                    let cleanTarget = target.split(separator: "#").first.map(String.init) ?? target
                    let resolved = directory.isEmpty || directory == "." ? cleanTarget : directory + "/" + cleanTarget
                    let normalized = Self.g5NormalizePath(resolved)
                    if !workspacePaths.contains(normalized) && !workspacePaths.contains(cleanTarget) {
                        broken.append([
                            "path": .string(file.path),
                            "lineNumber": .int(Int64(index + 1)),
                            "target": .string(target),
                        ])
                    }
                    if broken.count >= limit { break }
                }
                if broken.count >= limit { break }
            }
            if broken.count >= limit { break }
        }
        return .object([
            "tool": .string(tool),
            "filesChecked": .int(Int64(files.count)),
            "links": .int(Int64(linkCount)),
            "broken": .array(broken),
            "brokenCount": .int(Int64(broken.count)),
        ])
    }

    private static func g5NormalizePath(_ path: String) -> String {
        var parts: [String] = []
        for part in path.split(separator: "/").map(String.init) {
            if part == "." || part.isEmpty { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(part)
        }
        return parts.joined(separator: "/")
    }

    private static func runG5DocsIndex(tool: String, cwd: String, path: String?, runtime: AgentsRuntimeClient) async throws -> JSONValue {
        let entries = try await runtime.listWorkspaceFiles(cwd: cwd, query: "", limit: 500)
        var scoped = Self.g5ScopeEntries(entries, path: path)
        scoped = scoped.filter { !$0.isDirectory && $0.path.hasSuffix(".md") && !$0.path.hasPrefix(".") && !$0.path.contains("/.") }
        var files: [[String: JSONValue]] = []
        for entry in scoped {
            guard let document = try? await runtime.readWorkspaceFile(cwd: cwd, path: entry.path) else { continue }
            var title = ""
            for line in Self.g5Lines(document.content) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") {
                    title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            files.append([
                "path": .string(entry.path),
                "title": .string(title),
                "sizeBytes": .int(entry.sizeBytes ?? Int64(document.content.utf8.count)),
            ])
        }
        return .object([
            "tool": .string(tool),
            "files": .array(files),
        ])
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
