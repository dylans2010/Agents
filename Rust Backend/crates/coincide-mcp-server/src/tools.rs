use anyhow::{Context, Result};
use serde_json::{Value, json};
use std::time::{Duration, Instant};

pub struct ToolParam {
    pub name: &'static str,
    pub kind: &'static str,
    pub required: bool,
    pub description: &'static str,
}

pub struct ToolDef {
    pub name: &'static str,
    pub description: &'static str,
    pub action: &'static str,
    pub channel: &'static str,
    pub params: &'static [ToolParam],
}

const P_CWD: ToolParam = ToolParam {
    name: "cwd",
    kind: "string",
    required: true,
    description: "Absolute working directory.",
};
const P_PATH: ToolParam = ToolParam {
    name: "path",
    kind: "string",
    required: true,
    description: "Path relative to the working directory.",
};
const P_THREAD_ID: ToolParam = ToolParam {
    name: "threadId",
    kind: "string",
    required: true,
    description: "Owning thread ID.",
};
const P_LIMIT: ToolParam = ToolParam {
    name: "limit",
    kind: "integer",
    required: false,
    description: "Maximum matches to return.",
};

pub static DEFINITIONS: &[ToolDef] = &[
    ToolDef {
        name: "read_file",
        description: "Read a file in the thread working directory.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "write_file",
        description: "Write a file in the thread working directory.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "content",
                kind: "string",
                required: true,
                description: "Full file content.",
            },
        ],
    },
    ToolDef {
        name: "list_files",
        description: "List files in the thread working directory.",
        action: "workspace.files",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "query",
                kind: "string",
                required: false,
                description: "Substring filter for file paths.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum files to return.",
            },
        ],
    },
    ToolDef {
        name: "search_files",
        description: "Search file contents in the thread working directory.",
        action: "workspace.search",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "query",
                kind: "string",
                required: true,
                description: "Text to search for.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "create_terminal",
        description: "Create an integrated terminal for a thread.",
        action: "terminal.create",
        channel: "engine",
        params: &[ToolParam {
            name: "threadId",
            kind: "string",
            required: false,
            description: "Owning thread ID.",
        }],
    },
    ToolDef {
        name: "write_terminal",
        description: "Send input to an integrated terminal.",
        action: "terminal.write",
        channel: "engine",
        params: &[
            ToolParam {
                name: "terminalId",
                kind: "string",
                required: true,
                description: "Terminal ID from create_terminal.",
            },
            ToolParam {
                name: "text",
                kind: "string",
                required: true,
                description: "Text to send.",
            },
        ],
    },
    ToolDef {
        name: "read_terminal",
        description: "Read an integrated terminal viewport snapshot.",
        action: "terminal.read",
        channel: "engine",
        params: &[ToolParam {
            name: "terminalId",
            kind: "string",
            required: true,
            description: "Terminal ID from create_terminal.",
        }],
    },
    ToolDef {
        name: "git_status",
        description: "Read git working-tree status for a thread.",
        action: "git.status",
        channel: "engine",
        params: &[P_THREAD_ID],
    },
    ToolDef {
        name: "git_diff",
        description: "Read the git diff for a thread.",
        action: "git.diff",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Single file path to diff.",
            },
            ToolParam {
                name: "staged",
                kind: "boolean",
                required: false,
                description: "Diff staged changes instead of the worktree.",
            },
        ],
    },
    ToolDef {
        name: "git_log",
        description: "List git commits for a thread working directory, newest first, with author, date, message, and parents.",
        action: "git.log",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum commits to return, 1–200. Defaults to 50.",
            },
            ToolParam {
                name: "skip",
                kind: "integer",
                required: false,
                description: "Commits to skip for pagination. Defaults to 0.",
            },
        ],
    },
    ToolDef {
        name: "git_show",
        description: "Show one git commit for a thread working directory: its metadata, changed files, and full diff.",
        action: "git.show",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "sha",
                kind: "string",
                required: true,
                description: "Full 40- or 64-character commit SHA.",
            },
        ],
    },
    ToolDef {
        name: "git_diff_range",
        description: "Diff two git references for a thread working directory, comparing the merge base of the first against the second, with changed files and the full patch.",
        action: "git.diff.range",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "from",
                kind: "string",
                required: true,
                description: "Base reference, such as a branch name or commit SHA.",
            },
            ToolParam {
                name: "to",
                kind: "string",
                required: true,
                description: "Reference to compare against the base, such as a branch name or commit SHA.",
            },
        ],
    },
    ToolDef {
        name: "git_diff_branch",
        description: "Diff the thread branch working tree against the base it branched from, with the full patch.",
        action: "git.diff.branch",
        channel: "engine",
        params: &[P_THREAD_ID],
    },
    ToolDef {
        name: "delete_file",
        description: "Delete a file in the thread working directory. Refuses directories and symlinks.",
        action: "workspace.delete_file",
        channel: "desktop",
        params: &[P_CWD, P_PATH],
    },
    ToolDef {
        name: "delete_directory",
        description: "Delete a directory in the thread working directory. Without recursive=true only an empty directory is removed.",
        action: "workspace.delete_directory",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "recursive",
                kind: "boolean",
                required: false,
                description: "Remove the directory and everything inside it.",
            },
        ],
    },
    ToolDef {
        name: "move_file",
        description: "Move or rename a file or directory inside the thread working directory. The destination must not already exist.",
        action: "workspace.move_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "destination",
                kind: "string",
                required: true,
                description: "Destination path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "copy_file",
        description: "Copy a file inside the thread working directory. The destination must not already exist.",
        action: "workspace.copy_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "destination",
                kind: "string",
                required: true,
                description: "Destination path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "create_directory",
        description: "Create a directory, including missing parents, in the thread working directory.",
        action: "workspace.create_dir",
        channel: "desktop",
        params: &[P_CWD, P_PATH],
    },
    ToolDef {
        name: "read_directory",
        description: "List directory entries in the thread working directory with a real directory read, including files git ignores.",
        action: "workspace.read_dir",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Directory relative to the working directory; defaults to the working directory itself.",
            },
            ToolParam {
                name: "recursive",
                kind: "boolean",
                required: false,
                description: "List entries recursively, up to 16 levels deep.",
            },
        ],
    },
    ToolDef {
        name: "edit_file",
        description: "Replace anchored text in a file. The anchor must match exactly once or the edit fails; the file is re-read after writing to verify the result.",
        action: "workspace.edit_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "oldText",
                kind: "string",
                required: true,
                description: "Exact text to match, exactly once.",
            },
            ToolParam {
                name: "newText",
                kind: "string",
                required: true,
                description: "Replacement text.",
            },
            ToolParam {
                name: "mode",
                kind: "string",
                required: false,
                description: "replace, insertAfter, or insertBefore. Defaults to replace.",
            },
        ],
    },
    ToolDef {
        name: "multi_edit_file",
        description: "Apply several anchored edits to one file, in order. Every anchor must match exactly once at the time it is applied or the whole edit fails.",
        action: "workspace.edit_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "edits",
                kind: "array",
                required: true,
                description: "Edits to apply, each with oldText, newText, and an optional mode.",
            },
        ],
    },
    ToolDef {
        name: "search_regex",
        description: "Search file contents with a regular expression. Runs ripgrep in regex mode when installed, otherwise a real regex scan. An invalid pattern is an error.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "pattern",
                kind: "string",
                required: true,
                description: "Regular expression to search for.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "run_build",
        description: "Run a build command in the thread's integrated terminal and return its real output and exit code. The output is the final terminal viewport, not full scrollback.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "command",
                kind: "string",
                required: true,
                description: "Build command to run, for example xcodebuild -scheme MyApp build.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command. Defaults to 600.",
            },
        ],
    },
    ToolDef {
        name: "run_tests",
        description: "Run a test command in the thread's integrated terminal and return its real output and exit code. The output is the final terminal viewport, not full scrollback.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "command",
                kind: "string",
                required: true,
                description: "Test command to run, for example xcodebuild test -scheme MyApp or cargo test.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command. Defaults to 600.",
            },
        ],
    },
    ToolDef {
        name: "git_commit",
        description: "Commit the thread working-tree changes with the given message, using the engine git action runner.",
        action: "git.actions.run",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "message",
                kind: "string",
                required: true,
                description: "Commit message.",
            },
            ToolParam {
                name: "paths",
                kind: "array",
                required: false,
                description: "Paths to commit; defaults to all changes.",
            },
        ],
    },
    ToolDef {
        name: "git_push",
        description: "Push the thread branch to its upstream, using the engine git action runner.",
        action: "git.actions.run",
        channel: "engine",
        params: &[P_THREAD_ID],
    },
    ToolDef {
        name: "git_pull",
        description: "Pull the thread branch from its upstream, using the engine git action runner.",
        action: "git.actions.pull",
        channel: "engine",
        params: &[P_THREAD_ID],
    },
    ToolDef {
        name: "git_branch_list",
        description: "List git branches for the thread working directory.",
        action: "git.branches.list",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "scope",
                kind: "string",
                required: false,
                description: "project lists the project checkout branches instead of the thread worktree.",
            },
        ],
    },
    ToolDef {
        name: "git_branch_create",
        description: "Create and check out a new git branch for the thread working directory.",
        action: "git.branches.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "name",
                kind: "string",
                required: true,
                description: "New branch name.",
            },
        ],
    },
    ToolDef {
        name: "git_branch_checkout",
        description: "Check out an existing git branch for the thread working directory. The thread must have no active turn.",
        action: "git.branches.checkout",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "name",
                kind: "string",
                required: true,
                description: "Branch name to check out.",
            },
        ],
    },
    ToolDef {
        name: "mem_store",
        description: "Store a durable fact in agent memory. Storing an existing key overwrites it and reports overwritten=true.",
        action: "memory.store",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "key",
                kind: "string",
                required: true,
                description: "Memory key, up to 256 characters.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: true,
                description: "Fact to store, up to 64 KiB.",
            },
            ToolParam {
                name: "scope",
                kind: "string",
                required: false,
                description: "global or workspace:<identifier>. Defaults to global.",
            },
        ],
    },
    ToolDef {
        name: "mem_retrieve",
        description: "Read a stored fact from agent memory by key. A missing key is an error.",
        action: "memory.retrieve",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "key",
                kind: "string",
                required: true,
                description: "Memory key to read.",
            },
            ToolParam {
                name: "scope",
                kind: "string",
                required: false,
                description: "global or workspace:<identifier>. Defaults to global.",
            },
        ],
    },
    ToolDef {
        name: "view_memory",
        description: "List stored agent memories in a scope, optionally filtered by a keyword substring over keys and values.",
        action: "memory.list",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "scope",
                kind: "string",
                required: false,
                description: "global or workspace:<identifier>. Defaults to all scopes.",
            },
            ToolParam {
                name: "query",
                kind: "string",
                required: false,
                description: "Keyword substring filter over keys and values.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum entries to return.",
            },
        ],
    },
    ToolDef {
        name: "mem_delete",
        description: "Delete one stored fact from agent memory by key. A missing key is an error.",
        action: "memory.delete",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "key",
                kind: "string",
                required: true,
                description: "Memory key to delete.",
            },
            ToolParam {
                name: "scope",
                kind: "string",
                required: false,
                description: "global or workspace:<identifier>. Defaults to global.",
            },
        ],
    },
    ToolDef {
        name: "mem_clear",
        description: "Delete every memory entry in one scope. Requires scope and confirm=true; without both the clear is refused.",
        action: "memory.clear",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "scope",
                kind: "string",
                required: true,
                description: "Scope to clear: global or workspace:<identifier>.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: true,
                description: "Must be true. Clearing a scope is irreversible.",
            },
        ],
    },
    ToolDef {
        name: "mem_context_snapshot",
        description: "Capture a snapshot of the memories relevant to the current context. Each call mints a new snapshot key and stores it as a memory entry.",
        action: "memory.snapshot",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "scope",
                kind: "string",
                required: false,
                description: "global or workspace:<identifier>. Defaults to global.",
            },
            ToolParam {
                name: "query",
                kind: "string",
                required: false,
                description: "Keyword substring filter over keys and values.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum entries to capture.",
            },
        ],
    },
    ToolDef {
        name: "context_persistence_store",
        description: "Durable key-value context across sessions, backed by the agent memory store. Get of a missing key succeeds with an empty value.",
        action: "memory.context_store",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "key",
                kind: "string",
                required: true,
                description: "Memory key.",
            },
            ToolParam {
                name: "action",
                kind: "string",
                required: true,
                description: "get, set, or delete.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: false,
                description: "Value for set.",
            },
            ToolParam {
                name: "scope",
                kind: "string",
                required: false,
                description: "global or workspace:<identifier>. Defaults to global.",
            },
        ],
    },
    ToolDef {
        name: "use_workers",
        description: "Spawn one or more subagent workers on the parent thread. Each worker runs a real provider turn on its own thread; worker names must be unique and targetFiles must be disjoint across workers.",
        action: "workers.spawn",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "parentThreadId",
                kind: "string",
                required: true,
                description: "Parent thread ID that owns the workers.",
            },
            ToolParam {
                name: "workers",
                kind: "array",
                required: true,
                description: "Workers to spawn, each with name, task of at most 500 characters, and targetFiles.",
            },
        ],
    },
    ToolDef {
        name: "list_workers",
        description: "List workers spawned by a parent thread, with live status and progress.",
        action: "workers.list",
        channel: "desktop",
        params: &[ToolParam {
            name: "parentThreadId",
            kind: "string",
            required: false,
            description: "Parent thread ID; lists every worker when omitted.",
        }],
    },
    ToolDef {
        name: "worker_status",
        description: "Read one worker's live status, progress, and result if finished.",
        action: "workers.status",
        channel: "desktop",
        params: &[ToolParam {
            name: "workerId",
            kind: "string",
            required: true,
            description: "Worker ID from use_workers or list_workers.",
        }],
    },
    ToolDef {
        name: "worker_result",
        description: "Read one worker's result. Returns the worker record; result is null until the worker completes.",
        action: "workers.result",
        channel: "desktop",
        params: &[ToolParam {
            name: "workerId",
            kind: "string",
            required: true,
            description: "Worker ID from use_workers or list_workers.",
        }],
    },
    ToolDef {
        name: "cancel_worker",
        description: "Ask a running worker's provider turn to stop and mark the worker cancelled. Cancellation is a stop request, not a kill: the provider winds down on its own schedule.",
        action: "workers.cancel",
        channel: "desktop",
        params: &[ToolParam {
            name: "workerId",
            kind: "string",
            required: true,
            description: "Worker ID from use_workers or list_workers.",
        }],
    },
    ToolDef {
        name: "intel_plan_task",
        description: "Draft a plan for a complex task as worker steps. Mechanical sentence decomposition, not LLM planning; each step still needs disjoint targetFiles assigned before spawning.",
        action: "workers.plan",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "parentThreadId",
                kind: "string",
                required: true,
                description: "Parent thread ID that owns the plan.",
            },
            ToolParam {
                name: "task",
                kind: "string",
                required: true,
                description: "Task to decompose into worker steps.",
            },
        ],
    },
    ToolDef {
        name: "intel_breakdown_task",
        description: "Expand a stored plan's steps into granular sub-steps by mechanical splitting. Requires a planId from intel_plan_task.",
        action: "workers.breakdown",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "planId",
                kind: "string",
                required: true,
                description: "Plan ID from intel_plan_task.",
            },
            ToolParam {
                name: "parentThreadId",
                kind: "string",
                required: false,
                description: "Parent thread ID the plan must belong to.",
            },
        ],
    },
    ToolDef {
        name: "execution_plan",
        description: "Build an execution plan from the objective and live repository state, and write it to agent_notes.md in the parent working directory. The plan is a fixed mechanical template, not completed work.",
        action: "workers.execution_plan",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "parentThreadId",
                kind: "string",
                required: true,
                description: "Parent thread ID that owns the plan.",
            },
            ToolParam {
                name: "objective",
                kind: "string",
                required: true,
                description: "Objective to plan, at most 500 characters.",
            },
            ToolParam {
                name: "mode",
                kind: "string",
                required: true,
                description: "Plan mode, for example build.",
            },
        ],
    },
    ToolDef {
        name: "list_apps",
        description: "List running apps on this computer.",
        action: "computer_use.request",
        channel: "engine",
        params: &[P_THREAD_ID],
    },
    ToolDef {
        name: "list_windows",
        description: "List on-screen windows, optionally for one app.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "pid",
                kind: "integer",
                required: false,
                description: "Process ID of the running app.",
            },
        ],
    },
    ToolDef {
        name: "get_window_state",
        description: "Observe one window: its accessible elements as fresh element tokens, optionally with a screenshot saved as a private PNG file.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "pid",
                kind: "integer",
                required: true,
                description: "Process ID of the running app.",
            },
            ToolParam {
                name: "window_id",
                kind: "integer",
                required: true,
                description: "Window ID from list_windows or get_desktop_state.",
            },
            ToolParam {
                name: "max_elements",
                kind: "integer",
                required: false,
                description: "Maximum accessible elements to return, at most 128.",
            },
            ToolParam {
                name: "include_screenshot",
                kind: "boolean",
                required: false,
                description: "Save a screenshot as a private PNG file and return its path.",
            },
        ],
    },
    ToolDef {
        name: "get_desktop_state",
        description: "List running apps and on-screen windows, optionally with a screenshot of the main display.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "include_screenshot",
                kind: "boolean",
                required: false,
                description: "Save a screenshot as a private PNG file and return its path.",
            },
        ],
    },
    ToolDef {
        name: "verify_state",
        description: "Fresh read of a window: elements whose title or value contains text. Issues no tokens.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "pid",
                kind: "integer",
                required: true,
                description: "Process ID of the running app.",
            },
            ToolParam {
                name: "window_id",
                kind: "integer",
                required: true,
                description: "Window ID from list_windows or get_desktop_state.",
            },
            ToolParam {
                name: "text",
                kind: "string",
                required: true,
                description: "Text to find in element titles or values.",
            },
        ],
    },
    ToolDef {
        name: "zoom",
        description: "Sharper image of a region of the observed window, in window points.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "observation",
                kind: "string",
                required: true,
                description: "Observation ID from a fresh get_window_state screenshot.",
            },
            ToolParam {
                name: "x",
                kind: "number",
                required: true,
                description: "Region x in window points.",
            },
            ToolParam {
                name: "y",
                kind: "number",
                required: true,
                description: "Region y in window points.",
            },
            ToolParam {
                name: "width",
                kind: "number",
                required: true,
                description: "Region width in window points.",
            },
            ToolParam {
                name: "height",
                kind: "number",
                required: true,
                description: "Region height in window points.",
            },
        ],
    },
    ToolDef {
        name: "click",
        description: "Press an accessible element by its fresh element token.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "element_token",
                kind: "string",
                required: true,
                description: "Element token from a fresh get_window_state observation.",
            },
        ],
    },
    ToolDef {
        name: "double_click",
        description: "Double-click an element token, or a point in a fresh screenshot observation.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "element_token",
                kind: "string",
                required: false,
                description: "Element token from a fresh get_window_state observation.",
            },
            ToolParam {
                name: "observation",
                kind: "string",
                required: false,
                description: "Observation ID from a fresh get_window_state screenshot.",
            },
            ToolParam {
                name: "x",
                kind: "number",
                required: false,
                description: "Point x in window points.",
            },
            ToolParam {
                name: "y",
                kind: "number",
                required: false,
                description: "Point y in window points.",
            },
        ],
    },
    ToolDef {
        name: "right_click",
        description: "Right-click an element token, or a point in a fresh screenshot observation.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "element_token",
                kind: "string",
                required: false,
                description: "Element token from a fresh get_window_state observation.",
            },
            ToolParam {
                name: "observation",
                kind: "string",
                required: false,
                description: "Observation ID from a fresh get_window_state screenshot.",
            },
            ToolParam {
                name: "x",
                kind: "number",
                required: false,
                description: "Point x in window points.",
            },
            ToolParam {
                name: "y",
                kind: "number",
                required: false,
                description: "Point y in window points.",
            },
        ],
    },
    ToolDef {
        name: "set_value",
        description: "Set the text of an accessible element by its fresh element token.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "element_token",
                kind: "string",
                required: true,
                description: "Element token from a fresh get_window_state observation.",
            },
            ToolParam {
                name: "text",
                kind: "string",
                required: true,
                description: "Text to set.",
            },
        ],
    },
    ToolDef {
        name: "type_text",
        description: "Type text into the focused element of the foreground app.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "element_token",
                kind: "string",
                required: true,
                description: "Element token from a fresh get_window_state observation.",
            },
            ToolParam {
                name: "text",
                kind: "string",
                required: true,
                description: "Text to type.",
            },
        ],
    },
    ToolDef {
        name: "press_key",
        description: "Press a key on the focused element of the foreground app.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "element_token",
                kind: "string",
                required: true,
                description: "Element token from a fresh get_window_state observation.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: true,
                description: "Key to press: enter, escape, tab, backspace, left, right, up, or down.",
            },
        ],
    },
    ToolDef {
        name: "hotkey",
        description: "Send a modifier chord to the focused element of the foreground app, for example cmd shift t.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "element_token",
                kind: "string",
                required: true,
                description: "Element token from a fresh get_window_state observation.",
            },
            ToolParam {
                name: "keys",
                kind: "array",
                required: true,
                description: "Modifiers then one key, for example cmd shift t.",
            },
        ],
    },
    ToolDef {
        name: "scroll",
        description: "Scroll at an element token, or a point in a fresh screenshot observation.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "element_token",
                kind: "string",
                required: false,
                description: "Element token from a fresh get_window_state observation.",
            },
            ToolParam {
                name: "observation",
                kind: "string",
                required: false,
                description: "Observation ID from a fresh get_window_state screenshot.",
            },
            ToolParam {
                name: "x",
                kind: "number",
                required: false,
                description: "Point x in window points.",
            },
            ToolParam {
                name: "y",
                kind: "number",
                required: false,
                description: "Point y in window points.",
            },
            ToolParam {
                name: "direction",
                kind: "string",
                required: true,
                description: "Scroll direction: up, down, left, or right.",
            },
            ToolParam {
                name: "amount",
                kind: "integer",
                required: false,
                description: "Scroll amount, 1 to 50. Defaults to 3.",
            },
        ],
    },
    ToolDef {
        name: "drag",
        description: "Drag between two points of a fresh screenshot observation.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "observation",
                kind: "string",
                required: true,
                description: "Observation ID from a fresh get_window_state screenshot.",
            },
            ToolParam {
                name: "from_x",
                kind: "number",
                required: true,
                description: "Start x in window points.",
            },
            ToolParam {
                name: "from_y",
                kind: "number",
                required: true,
                description: "Start y in window points.",
            },
            ToolParam {
                name: "to_x",
                kind: "number",
                required: true,
                description: "End x in window points.",
            },
            ToolParam {
                name: "to_y",
                kind: "number",
                required: true,
                description: "End y in window points.",
            },
        ],
    },
    ToolDef {
        name: "move_cursor",
        description: "Move the cursor to a point in a fresh screenshot observation.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "observation",
                kind: "string",
                required: true,
                description: "Observation ID from a fresh get_window_state screenshot.",
            },
            ToolParam {
                name: "x",
                kind: "number",
                required: true,
                description: "Point x in window points.",
            },
            ToolParam {
                name: "y",
                kind: "number",
                required: true,
                description: "Point y in window points.",
            },
        ],
    },
    ToolDef {
        name: "click_point",
        description: "Click a point in a fresh screenshot observation of the foreground window.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "observation",
                kind: "string",
                required: true,
                description: "Observation ID from a fresh get_window_state screenshot.",
            },
            ToolParam {
                name: "x",
                kind: "number",
                required: true,
                description: "Point x in window points.",
            },
            ToolParam {
                name: "y",
                kind: "number",
                required: true,
                description: "Point y in window points.",
            },
        ],
    },
    ToolDef {
        name: "invoke_menu",
        description: "Run a menu bar path of a running app, for example File New Window.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "pid",
                kind: "integer",
                required: true,
                description: "Process ID of the running app.",
            },
            ToolParam {
                name: "path",
                kind: "array",
                required: true,
                description: "Menu path, for example File New Window.",
            },
        ],
    },
    ToolDef {
        name: "launch_app",
        description: "Launch an app by bundle ID.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "bundle_id",
                kind: "string",
                required: true,
                description: "App bundle ID, for example com.apple.TextEdit.",
            },
        ],
    },
    ToolDef {
        name: "set_window_frame",
        description: "Move and resize a window, in screen points.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            ToolParam {
                name: "pid",
                kind: "integer",
                required: true,
                description: "Process ID of the running app.",
            },
            ToolParam {
                name: "window_id",
                kind: "integer",
                required: true,
                description: "Window ID from list_windows or get_desktop_state.",
            },
            ToolParam {
                name: "x",
                kind: "number",
                required: true,
                description: "Frame x in screen points.",
            },
            ToolParam {
                name: "y",
                kind: "number",
                required: true,
                description: "Frame y in screen points.",
            },
            ToolParam {
                name: "width",
                kind: "number",
                required: true,
                description: "Frame width in screen points.",
            },
            ToolParam {
                name: "height",
                kind: "number",
                required: true,
                description: "Frame height in screen points.",
            },
        ],
    },
    ToolDef {
        name: "file_read",
        description: "Read a file in the thread working directory.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "view_file",
        description: "View a file in the thread working directory.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "file_write",
        description: "Write a file in the thread working directory.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "content",
                kind: "string",
                required: true,
                description: "Full file content.",
            },
        ],
    },
    ToolDef {
        name: "create_file",
        description: "Create a new file in the thread working directory. Refuses to overwrite an existing file unless overwrite is true.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "content",
                kind: "string",
                required: false,
                description: "Initial file content. Defaults to empty.",
            },
            ToolParam {
                name: "overwrite",
                kind: "boolean",
                required: false,
                description: "Allow overwriting an existing file. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "file_create",
        description: "Create a file that must not already exist, in the thread working directory. Refuses to overwrite unless overwrite is true.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "content",
                kind: "string",
                required: false,
                description: "Initial file content. Defaults to empty.",
            },
            ToolParam {
                name: "overwrite",
                kind: "boolean",
                required: false,
                description: "Allow overwriting an existing file. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "file_append",
        description: "Append content to an existing file in the thread working directory. A missing file is an error.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "content",
                kind: "string",
                required: true,
                description: "Content to append.",
            },
        ],
    },
    ToolDef {
        name: "file_delete",
        description: "Delete a file in the thread working directory. Refuses directories and symlinks.",
        action: "workspace.delete_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "dir_delete",
        description: "Delete a directory in the thread working directory. Without recursive=true only an empty directory is removed.",
        action: "workspace.delete_directory",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "recursive",
                kind: "boolean",
                required: false,
                description: "Remove the directory and everything inside it.",
            },
        ],
    },
    ToolDef {
        name: "file_move",
        description: "Move a file or directory inside the thread working directory. The destination must not already exist.",
        action: "workspace.move_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "destination",
                kind: "string",
                required: true,
                description: "Destination path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "file_rename",
        description: "Rename a file within its own directory. The new name is a single file name, not a path.",
        action: "workspace.move_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "newName",
                kind: "string",
                required: true,
                description: "New file name, without any path separator.",
            },
        ],
    },
    ToolDef {
        name: "file_copy",
        description: "Copy a file inside the thread working directory. The destination must not already exist.",
        action: "workspace.copy_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "destination",
                kind: "string",
                required: true,
                description: "Destination path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "dir_create",
        description: "Create a directory, including missing parents, in the thread working directory.",
        action: "workspace.create_dir",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "dir_read",
        description: "List a directory in the thread working directory, non-recursive.",
        action: "workspace.read_dir",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Directory relative to the working directory; defaults to the working directory itself.",
            },
        ],
    },
    ToolDef {
        name: "list_directory",
        description: "List directory entries in the thread working directory.",
        action: "workspace.read_dir",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Directory relative to the working directory; defaults to the working directory itself.",
            },
            ToolParam {
                name: "recursive",
                kind: "boolean",
                required: false,
                description: "List entries recursively, up to 16 levels deep.",
            },
        ],
    },
    ToolDef {
        name: "tree_view",
        description: "List a directory tree in the thread working directory, recursively up to maxDepth levels.",
        action: "workspace.read_dir",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Directory relative to the working directory; defaults to the working directory itself.",
            },
            ToolParam {
                name: "maxDepth",
                kind: "integer",
                required: false,
                description: "Maximum tree depth, 1 to 10. Defaults to 3.",
            },
        ],
    },
    ToolDef {
        name: "search_directory",
        description: "List files in the thread working directory matching a substring filter.",
        action: "workspace.files",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "query",
                kind: "string",
                required: false,
                description: "Substring filter for file paths.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum files to return.",
            },
        ],
    },
    ToolDef {
        name: "search_text",
        description: "Search file contents literally in the thread working directory.",
        action: "workspace.search",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "query",
                kind: "string",
                required: true,
                description: "Text to search for.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum matches to return.",
            },
        ],
    },
    ToolDef {
        name: "code_replace",
        description: "Replace exact target text with replacement text in a file. The target must match exactly once unless allowMultiple is true.",
        action: "workspace.edit_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "target",
                kind: "string",
                required: true,
                description: "Exact text to match.",
            },
            ToolParam {
                name: "replacement",
                kind: "string",
                required: true,
                description: "Replacement text.",
            },
            ToolParam {
                name: "allowMultiple",
                kind: "boolean",
                required: false,
                description: "Replace every occurrence instead of requiring exactly one. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "code_insert",
        description: "Insert code into a file at a 1-based line, or before or after a pattern that must match exactly once.",
        action: "workspace.edit_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "code",
                kind: "string",
                required: true,
                description: "Code to insert.",
            },
            ToolParam {
                name: "line",
                kind: "integer",
                required: false,
                description: "1-based line to insert before, for mode line. Defaults to the end of the file.",
            },
            ToolParam {
                name: "mode",
                kind: "string",
                required: false,
                description: "line, before, or after. Defaults to line.",
            },
            ToolParam {
                name: "pattern",
                kind: "string",
                required: false,
                description: "Pattern to anchor on, required for mode before or after.",
            },
        ],
    },
    ToolDef {
        name: "code_multi_edit",
        description: "Apply several anchored edits to one file, in order. Every anchor must match exactly once at the time it is applied or the whole edit fails.",
        action: "workspace.edit_file",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "Path relative to the working directory.",
            },
            ToolParam {
                name: "edits",
                kind: "array",
                required: true,
                description: "Edits to apply, each with oldText, newText, and an optional mode.",
            },
        ],
    },
    ToolDef {
        name: "use_terminal",
        description: "Run a shell command in the thread integrated terminal and return its real output and exit code.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "command",
                kind: "string",
                required: true,
                description: "Shell command to run.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command. Defaults to 600.",
            },
        ],
    },
    ToolDef {
        name: "run_command",
        description: "Run a shell command in the thread integrated terminal and return its real output and exit code.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "command",
                kind: "string",
                required: true,
                description: "Shell command to run.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command. Defaults to 600.",
            },
        ],
    },
    ToolDef {
        name: "git_log_viewer",
        description: "List git commits for a thread working directory, newest first, with author, date, message, and parents.",
        action: "git.log",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum commits to return, 1–200. Defaults to 50.",
            },
            ToolParam {
                name: "skip",
                kind: "integer",
                required: false,
                description: "Commits to skip for pagination. Defaults to 0.",
            },
        ],
    },
    ToolDef {
        name: "git_branch_compare",
        description: "Diff two git references for a thread working directory, comparing the merge base of the first against the second, with changed files and the full patch.",
        action: "git.diff.range",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "from",
                kind: "string",
                required: true,
                description: "Base reference, such as a branch name or commit SHA.",
            },
            ToolParam {
                name: "to",
                kind: "string",
                required: true,
                description: "Reference to compare against the base, such as a branch name or commit SHA.",
            },
        ],
    },
    ToolDef {
        name: "project_diff",
        description: "Read the git diff for a thread.",
        action: "git.diff",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Single file path to diff.",
            },
            ToolParam {
                name: "staged",
                kind: "boolean",
                required: false,
                description: "Diff staged changes instead of the worktree.",
            },
        ],
    },
    ToolDef {
        name: "git_branch_manager",
        description: "List, create, check out, or safely delete local git branches. Delete requires confirm=true and refuses the checked-out branch.",
        action: "git.branches.list",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "action",
                kind: "string",
                required: false,
                description: "list, create, checkout, or delete. Defaults to list.",
            },
            ToolParam {
                name: "name",
                kind: "string",
                required: false,
                description: "Branch name for create, checkout, or delete.",
            },
            ToolParam {
                name: "force",
                kind: "boolean",
                required: false,
                description: "Delete with -D instead of -d, dropping unmerged work. Defaults to false.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: false,
                description: "Must be true to delete a branch.",
            },
        ],
    },
    ToolDef {
        name: "save_to_memory",
        description: "Store a durable fact in agent memory. Storing an existing key overwrites it and reports overwritten=true.",
        action: "memory.store",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "key",
                kind: "string",
                required: true,
                description: "Memory key, up to 256 characters.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: true,
                description: "Fact to store, up to 64 KiB.",
            },
            ToolParam {
                name: "scope",
                kind: "string",
                required: false,
                description: "global or workspace:<identifier>. Defaults to global.",
            },
        ],
    },
    ToolDef {
        name: "use_mcp",
        description: "Use the coincide MCP server: list its servers, list its tools, or run one of its tools by name.",
        action: "mcp.tools",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "serverName",
                kind: "string",
                required: true,
                description: "MCP server name, or list to list servers.",
            },
            ToolParam {
                name: "toolName",
                kind: "string",
                required: false,
                description: "Tool name to run, or list_tools to list tools.",
            },
            ToolParam {
                name: "arguments",
                kind: "string",
                required: false,
                description: "JSON object string of arguments for the tool.",
            },
        ],
    },
    ToolDef {
        name: "take_screenshot",
        description: "Capture the main display as a private PNG file and return its path.",
        action: "computer_use.request",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "include_screenshot",
                kind: "boolean",
                required: false,
                description: "Save a screenshot as a private PNG file and return its path. Defaults to true.",
            },
        ],
    },
    ToolDef {
        name: "start_subagent",
        description: "Spawn one or more subagent workers on the parent thread. Each worker runs a real provider turn on its own thread; worker names must be unique and targetFiles must be disjoint across workers.",
        action: "workers.spawn",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "parentThreadId",
                kind: "string",
                required: true,
                description: "Parent thread ID that owns the workers.",
            },
            ToolParam {
                name: "workers",
                kind: "array",
                required: true,
                description: "Workers to spawn, each with name, task of at most 500 characters, and targetFiles.",
            },
        ],
    },
    ToolDef {
        name: "git_stash_operator",
        description: "Save, pop, list, show, or drop git stashes. Pop and drop require confirm=true.",
        action: "git.stash",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "action",
                kind: "string",
                required: true,
                description: "push, pop, list, show, or drop.",
            },
            ToolParam {
                name: "message",
                kind: "string",
                required: false,
                description: "Message for stash push.",
            },
            ToolParam {
                name: "includeUntracked",
                kind: "boolean",
                required: false,
                description: "Include untracked files in a stash push. Defaults to false.",
            },
            ToolParam {
                name: "reference",
                kind: "string",
                required: false,
                description: "Stash reference such as stash@{0}, for pop, show, or drop.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: false,
                description: "Must be true to pop or drop a stash.",
            },
            ToolParam {
                name: "paths",
                kind: "array",
                required: false,
                description: "Paths to stash on push; defaults to all changes.",
            },
        ],
    },
    ToolDef {
        name: "git_blame_inspector",
        description: "Show git blame line annotations for a file, with author, commit, and content per line.",
        action: "git.blame",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: true,
                description: "File path relative to the working directory.",
            },
            ToolParam {
                name: "start",
                kind: "integer",
                required: false,
                description: "First line of the range, 1-based. Requires end.",
            },
            ToolParam {
                name: "end",
                kind: "integer",
                required: false,
                description: "Last line of the range, inclusive. Requires start.",
            },
        ],
    },
    ToolDef {
        name: "git_bisect",
        description: "Run git bisect: start, good, bad, skip, reset, or log. Start, good, bad, and skip move HEAD.",
        action: "git.bisect",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "action",
                kind: "string",
                required: true,
                description: "start, good, bad, skip, reset, or log.",
            },
            ToolParam {
                name: "reference",
                kind: "string",
                required: false,
                description: "Reference to mark good, bad, or skip. Defaults to HEAD.",
            },
            ToolParam {
                name: "good",
                kind: "string",
                required: false,
                description: "Known-good reference for start.",
            },
            ToolParam {
                name: "bad",
                kind: "string",
                required: false,
                description: "Known-bad reference for start.",
            },
        ],
    },
    ToolDef {
        name: "git_cherry_pick",
        description: "Cherry-pick a commit by full SHA, optionally without committing. Requires confirm=true. On conflict it reports the conflicted files and never auto-aborts.",
        action: "git.cherry_pick",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "sha",
                kind: "string",
                required: true,
                description: "Full 40- or 64-character commit SHA.",
            },
            ToolParam {
                name: "noCommit",
                kind: "boolean",
                required: false,
                description: "Stage the cherry-pick without committing. Defaults to false.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: true,
                description: "Must be true. Cherry-pick changes the working tree.",
            },
        ],
    },
    ToolDef {
        name: "version_control_operator",
        description: "Run git by action: status, commit, branch, diff, or rollback. Rollback resets hard to HEAD, HEAD~N, HEAD^N, or a full SHA and requires confirm=true.",
        action: ",
            action: ",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "action",
                kind: "string",
                required: true,
                description: "status, commit, branch, diff, or rollback.",
            },
            ToolParam {
                name: "message",
                kind: "string",
                required: false,
                description: "Commit message.",
            },
            ToolParam {
                name: "name",
                kind: "string",
                required: false,
                description: "Branch name for the branch action.",
            },
            ToolParam {
                name: "ref",
                kind: "string",
                required: false,
                description: "Reference to roll back to. Defaults to HEAD~1.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: false,
                description: "Must be true to roll back.",
            },
            ToolParam {
                name: "paths",
                kind: "array",
                required: false,
                description: "Paths to commit; defaults to all changes.",
            },
        ],
    },
    ToolDef {
        name: "git_pr_summary",
        description: "Compose a local-only markdown PR summary from git log and the diff range, with no GitHub API call.",
        action: "git.log",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "from",
                kind: "string",
                required: false,
                description: "Base reference. Defaults to the branch base.",
            },
            ToolParam {
                name: "to",
                kind: "string",
                required: false,
                description: "Reference to compare. Defaults to the branch head.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum commits to list. Defaults to 20.",
            },
        ],
    },
    ToolDef {
        name: "git_conflict_resolver",
        description: "Detect merge conflict markers across the workspace, or resolve them in one file with the ours, theirs, or both strategy.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "action",
                kind: "string",
                required: false,
                description: "detect or resolve. Defaults to detect.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File path relative to the working directory, for resolve.",
            },
            ToolParam {
                name: "strategy",
                kind: "string",
                required: false,
                description: "ours, theirs, or both. Defaults to ours.",
            },
        ],
    },
    ToolDef {
        name: "project_snapshot",
        description: "Capture a staged snapshot of the workspace and return its snapshot id for project_restore.",
        action: "git.checkpoints.create",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "label",
                kind: "string",
                required: false,
                description: "Snapshot label, stored in the checkpoint commit message.",
            },
        ],
    },
    ToolDef {
        name: "project_changelog",
        description: "List workspace snapshot ids and commits, newest first. Labels live in the checkpoint commit message, not in the list entries.",
        action: "git.checkpoints.list",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
        ],
    },
    ToolDef {
        name: "project_restore",
        description: "Restore the workspace to a snapshot id, resetting hard to the snapshot commit and removing untracked and ignored files. Requires confirm=true.",
        action: "git.checkpoints.restore",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "checkpointId",
                kind: "string",
                required: true,
                description: "Snapshot id from project_snapshot or project_changelog.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: true,
                description: "Must be true. Restore discards uncommitted and untracked changes.",
            },
        ],
    },
    ToolDef {
        name: "safe_undo",
        description: "Restore the second-newest snapshot. Requires at least two snapshots and confirm=true.",
        action: "git.checkpoints.restore",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: true,
                description: "Must be true. Undo discards uncommitted and untracked changes.",
            },
        ],
    },
    ToolDef {
        name: "safe_validate_changes",
        description: "Check a file, or the whole workspace, for merge markers and missing trailing newlines. Returns success with issues listed.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Single file path to check; defaults to the whole workspace.",
            },
        ],
    },
];

pub fn definition(name: &str) -> Option<&'static ToolDef> {
    DEFINITIONS.iter().find(|def| def.name == name)
}

pub fn input_schema(def: &ToolDef) -> Value {
    let mut properties = serde_json::Map::new();
    let mut required: Vec<Value> = Vec::new();
    for param in def.params {
        let schema = match param.kind {
            "integer" => json!({"type": "integer"}),
            "number" => json!({"type": "number"}),
            "boolean" => json!({"type": "boolean"}),
            "array" => json!({"type": "array"}),
            _ => json!({"type": "string"}),
        };
        let mut entry = schema.as_object().cloned().unwrap_or_default();
        entry.insert(
            "description".to_owned(),
            Value::String(param.description.to_owned()),
        );
        properties.insert(param.name.to_owned(), Value::Object(entry));
        if param.required {
            required.push(Value::String(param.name.to_owned()));
        }
    }
    json!({
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": false,
    })
}

pub fn list_json() -> Value {
    Value::Array(
        DEFINITIONS
            .iter()
            .map(|def| {
                json!({
                    "name": def.name,
                    "description": def.description,
                    "inputSchema": input_schema(def),
                })
            })
            .collect(),
    )
}

pub enum CallError {
    UnknownTool(String),
    Failed(String),
}

fn failed(message: impl Into<String>) -> CallError {
    CallError::Failed(message.into())
}

fn req_str(args: &Value, name: &str, tool: &str) -> Result<String, CallError> {
    match args.get(name).and_then(Value::as_str) {
        Some(value) if !value.is_empty() => Ok(value.to_owned()),
        _ => Err(failed(format!(
            "Tool \"{tool}\" is missing required argument \"{name}\"."
        ))),
    }
}

fn opt_str(args: &Value, name: &str) -> Option<String> {
    args.get(name).and_then(Value::as_str).map(str::to_owned)
}

fn opt_bool(args: &Value, name: &str) -> Option<bool> {
    args.get(name).and_then(Value::as_bool)
}

fn opt_u64(args: &Value, name: &str) -> Option<u64> {
    args.get(name).and_then(Value::as_u64)
}

fn with_session_defaults(state: &crate::ServerState, mut args: Value) -> Value {
    if !args.is_object() {
        return json!({});
    }
    let object = args.as_object_mut().unwrap();
    if !object.contains_key("cwd")
        && let Some(cwd) = state.cwd.to_str()
    {
        object.insert("cwd".to_owned(), json!(cwd));
    }
    if !object.contains_key("threadId")
        && let Some(thread_id) = &state.thread_id
    {
        object.insert("threadId".to_owned(), json!(thread_id));
    }
    args
}

fn engine_request(
    state: &crate::ServerState,
    method: &str,
    params: Value,
) -> Result<Value, CallError> {
    let response = coincide_core::control::request(
        &state.socket,
        &json!({"method": method, "params": params}),
    )
    .map_err(|error| {
        failed(format!(
            "Cannot reach the Agents engine control socket at {}: {error}",
            state.socket.display()
        ))
    })?;
    if let Some(error) = response.get("error") {
        return Err(failed(format!(
            "{}",
            error["message"].as_str().unwrap_or("Engine request failed")
        )));
    }
    Ok(response.get("result").cloned().unwrap_or(Value::Null))
}

fn poll_workspace_result(
    state: &crate::ServerState,
    operation_id: &str,
    thread_id: &str,
) -> Result<Value, CallError> {
    for _ in 0..100 {
        let polled = engine_request(
            state,
            "workspace.result",
            json!({"operationId": operation_id, "threadId": thread_id}),
        )?;
        if polled["ready"] == true {
            return Ok(polled["result"].clone());
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    Err(failed("Git operation did not finish in time."))
}

fn poll_git_actions_result(
    state: &crate::ServerState,
    operation_id: &str,
    thread_id: &str,
    timeout_seconds: u64,
) -> Result<Value, CallError> {
    let attempts = timeout_seconds.saturating_mul(4).max(1);
    for _ in 0..attempts {
        let polled = engine_request(
            state,
            "git.actions.result",
            json!({"operationId": operation_id, "threadId": thread_id}),
        )?;
        if polled["ready"] == true {
            return Ok(polled["result"].clone());
        }
        std::thread::sleep(Duration::from_millis(250));
    }
    Err(failed("Git operation did not finish in time."))
}

fn start_git_operation(
    state: &crate::ServerState,
    method: &str,
    params: Value,
) -> Result<String, CallError> {
    let started = engine_request(state, method, params)?;
    let operation_id = started["operationId"]
        .as_str()
        .context("Git operation did not return an operationId")
        .map_err(|error| failed(error.to_string()))?;
    Ok(operation_id.to_owned())
}

fn run_git_operation(
    state: &crate::ServerState,
    method: &str,
    thread_id: &str,
    params: Value,
) -> Result<Value, CallError> {
    let mut start_params = params;
    if let Some(object) = start_params.as_object_mut() {
        object.insert("threadId".to_owned(), json!(thread_id));
    }
    let operation_id = start_git_operation(state, method, start_params)?;
    poll_workspace_result(state, &operation_id, thread_id)
}

fn run_git_actions_operation(
    state: &crate::ServerState,
    method: &str,
    thread_id: &str,
    params: Value,
    timeout_seconds: u64,
) -> Result<Value, CallError> {
    let mut start_params = params;
    if let Some(object) = start_params.as_object_mut() {
        object.insert("threadId".to_owned(), json!(thread_id));
    }
    let operation_id = start_git_operation(state, method, start_params)?;
    poll_git_actions_result(state, &operation_id, thread_id, timeout_seconds)
}

fn poll_computer_use_result(
    state: &crate::ServerState,
    operation_id: &str,
    thread_id: &str,
) -> Result<Value, CallError> {
    for _ in 0..60 {
        let polled = engine_request(
            state,
            "computer_use.result",
            json!({"operationId": operation_id, "threadId": thread_id}),
        )?;
        if polled["ready"] == true {
            if let Some(error) = polled["error"].as_str() {
                return Err(failed(format!("Computer Use failed: {error}")));
            }
            return Ok(polled["result"].clone());
        }
        std::thread::sleep(Duration::from_millis(250));
    }
    Err(failed("Computer Use operation did not finish in time."))
}

fn run_computer_use_operation(
    state: &crate::ServerState,
    name: &str,
    args: &Value,
) -> Result<Value, CallError> {
    run_computer_use_named(state, name, name, args)
}

fn run_computer_use_named(
    state: &crate::ServerState,
    def_name: &str,
    engine_name: &str,
    args: &Value,
) -> Result<Value, CallError> {
    let def = definition(def_name)
        .context("Unknown Computer Use tool")
        .map_err(|error| failed(error.to_string()))?;
    let thread_id = req_str(args, "threadId", def_name)?;
    let mut arguments = serde_json::Map::new();
    for param in def.params {
        if param.name == "threadId" {
            continue;
        }
        match args.get(param.name) {
            Some(value) => {
                arguments.insert(param.name.to_owned(), value.clone());
            }
            None if param.required => {
                return Err(failed(format!(
                    "Computer Use tool {def_name} is missing required argument {}",
                    param.name
                )));
            }
            None => {}
        }
    }
    let started = engine_request(
        state,
        "computer_use.request",
        json!({"threadId": thread_id, "request": {"action": "call", "name": engine_name, "arguments": arguments}}),
    )?;
    let operation_id = started["operationId"]
        .as_str()
        .context("Computer Use request did not return an operationId")
        .map_err(|error| failed(error.to_string()))?;
    poll_computer_use_result(state, operation_id, &thread_id)
}

fn run_terminal_command(
    state: &crate::ServerState,
    thread_id: &str,
    command: &str,
    timeout_seconds: u64,
) -> Result<Value, CallError> {
    let created = engine_request(state, "terminal.create", json!({"threadId": thread_id}))?;
    let terminal_id = created["terminalId"]
        .as_str()
        .context("Terminal creation did not return a terminalId")
        .map_err(|error| failed(error.to_string()))?
        .to_owned();
    engine_request(
        state,
        "terminal.write",
        json!({"terminalId": terminal_id, "text": format!("{command}\n")}),
    )?;
    engine_request(
        state,
        "terminal.write",
        json!({"terminalId": terminal_id, "text": "echo __AGENTS_TOOL_DONE__:$?\n"}),
    )?;
    let clamped_timeout = timeout_seconds.clamp(5, 3600);
    let deadline = Instant::now() + Duration::from_secs(clamped_timeout);
    let mut last_lines: Vec<String> = Vec::new();
    while Instant::now() < deadline {
        let snapshot = engine_request(
            state,
            "terminal.read",
            json!({"terminalId": terminal_id}),
        )?;
        if let Some(exit_code) = snapshot["exitCode"].as_i64() {
            return Err(failed(format!(
                "Terminal closed with exit code {exit_code} before the command finished."
            )));
        }
        let lines: Vec<String> = snapshot["lines"]
            .as_array()
            .map(|rows| {
                rows.iter()
                    .filter_map(Value::as_str)
                    .map(str::to_owned)
                    .collect()
            })
            .unwrap_or_default();
        last_lines.clone_from(&lines);
        for line in &lines {
            if let Some(marker) = line.find("__AGENTS_TOOL_DONE__:") {
                let code_text = line[marker + "__AGENTS_TOOL_DONE__:".len()..].trim();
                let exit_code = code_text.parse::<i64>().unwrap_or(-1);
                let output = lines.join("\n").trim().to_owned();
                return Ok(json!({
                    "terminalId": terminal_id,
                    "exitCode": exit_code,
                    "timedOut": false,
                    "output": output,
                }));
            }
        }
        std::thread::sleep(Duration::from_millis(500));
    }
    Ok(json!({
        "terminalId": terminal_id,
        "exitCode": Value::Null,
        "timedOut": true,
        "output": last_lines.join("\n").trim().to_owned(),
    }))
}

fn session_expected_root(state: &crate::ServerState) -> Result<String, CallError> {
    let canonical = std::fs::canonicalize(&state.cwd)
        .map_err(|error| failed(format!("Session working directory is unavailable: {error}")))?;
    canonical
        .to_str()
        .map(str::to_owned)
        .context("Session working directory is not UTF-8")
        .map_err(|error| failed(error.to_string()))
}

fn poll_git_workspace_result(
    state: &crate::ServerState,
    operation_id: &str,
    thread_id: &str,
) -> Result<Value, CallError> {
    for _ in 0..1200 {
        let polled = engine_request(
            state,
            "git.workspace.result",
            json!({"operationId": operation_id, "threadId": thread_id}),
        )?;
        if polled["ready"] == true {
            return Ok(polled["result"].clone());
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    Err(failed("Workspace operation did not finish in time."))
}

fn run_workspace_api_operation(
    state: &crate::ServerState,
    method: &str,
    thread_id: &str,
    params: Value,
) -> Result<Value, CallError> {
    let mut start_params = params;
    if let Some(object) = start_params.as_object_mut() {
        object.insert("threadId".to_owned(), json!(thread_id));
    }
    let operation_id = start_git_operation(state, method, start_params)?;
    poll_git_workspace_result(state, &operation_id, thread_id)
}

fn read_text_file(args: &Value) -> Result<String, CallError> {
    let value =
        coincide_core::workspace_tools::read_file(args).map_err(|error| failed(error.to_string()))?;
    value["text"]
        .as_str()
        .or_else(|| value["content"].as_str())
        .map(str::to_owned)
        .context("File read did not return text")
        .map_err(|error| failed(error.to_string()))
}

fn workspace_file_exists(cwd: &str, path: &str) -> Result<bool, CallError> {
    if path.is_empty()
        || path.starts_with('/')
        || path
            .split('/')
            .any(|part| part == ".." || part == ".")
    {
        return Err(failed("Path must be relative without dot or parent components."));
    }
    let root = std::path::Path::new(cwd);
    Ok(std::fs::symlink_metadata(root.join(path)).is_ok())
}

fn conflict_files(value: &Value) -> Vec<String> {
    let mut files: Vec<String> = Vec::new();
    for hit in value["matches"].as_array().cloned().unwrap_or_default() {
        if let Some(path) = hit["path"].as_str() {
            if !files.iter().any(|file| file == path) {
                files.push(path.to_owned());
            }
        }
    }
    files
}

fn resolve_conflicts(content: &str, strategy: &str) -> Result<(String, usize), CallError> {
    if !matches!(strategy, "ours" | "theirs" | "both") {
        return Err(failed("git_conflict_resolver strategy must be ours, theirs, or both."));
    }
    let mut output: Vec<&str> = Vec::new();
    let mut ours: Vec<&str> = Vec::new();
    let mut theirs: Vec<&str> = Vec::new();
    let mut state = 0;
    let mut hunks = 0;
    for line in content.lines() {
        if line.starts_with("<<<<<<<") {
            if state != 0 {
                return Err(failed("Nested conflict marker in file."));
            }
            state = 1;
            ours.clear();
            theirs.clear();
            hunks += 1;
            continue;
        }
        if line == "=======" {
            if state != 1 {
                return Err(failed("Conflict separator without an opening marker."));
            }
            state = 2;
            continue;
        }
        if line.starts_with(">>>>>>>") {
            if state != 2 {
                return Err(failed("Conflict end marker without an opening marker."));
            }
            state = 0;
            if strategy == "ours" || strategy == "both" {
                output.extend(ours.iter().copied());
            }
            if strategy == "theirs" || strategy == "both" {
                output.extend(theirs.iter().copied());
            }
            continue;
        }
        if state == 1 {
            ours.push(line);
        } else if state == 2 {
            theirs.push(line);
        } else {
            output.push(line);
        }
    }
    if state != 0 {
        return Err(failed("Unclosed conflict marker in file."));
    }
    if hunks == 0 {
        return Err(failed("No conflict markers found in file."));
    }
    let mut resolved = output.join("\n");
    if content.ends_with('\n') {
        resolved.push('\n');
    }
    Ok((resolved, hunks))
}

fn validate_content(path: &str, content: &str) -> Vec<Value> {
    let mut issues = Vec::new();
    for (index, line) in content.lines().enumerate() {
        if line.starts_with("<<<<<<<") || line.starts_with(">>>>>>>") || line == "=======" {
            issues.push(json!({
                "path": path,
                "line": index + 1,
                "issue": format!("Merge conflict marker: {line}"),
            }));
        }
    }
    if !content.is_empty() && !content.ends_with('\n') {
        issues.push(json!({
            "path": path,
            "line": content.lines().count(),
            "issue": "File does not end with a trailing newline.",
        }));
    }
    issues
}

fn pr_markdown(log: &Value, diff: &Value, from: Option<&str>, to: Option<&str>) -> String {
    let mut lines: Vec<String> = vec!["# PR Summary".to_owned(), String::new()];
    match (from, to) {
        (Some(from), Some(to)) => lines.push(format!("Range: {from} ... {to}")),
        _ => lines.push("Range: branch against its base".to_owned()),
    }
    lines.push(String::new());
    lines.push("## Commits".to_owned());
    let commits = log["commits"].as_array().cloned().unwrap_or_default();
    if commits.is_empty() {
        lines.push("No commits.".to_owned());
    } else {
        for commit in &commits {
            let sha = commit["sha"].as_str().unwrap_or("");
            let subject = commit["subject"].as_str().unwrap_or("");
            let author = commit["authorName"].as_str().unwrap_or("");
            lines.push(format!(
                "- {} {subject} ({author})",
                &sha[..sha.len().min(8)]
            ));
        }
    }
    lines.push(String::new());
    lines.push("## Files Changed".to_owned());
    let files = diff["files"]
        .as_array()
        .or_else(|| diff["numstat"].as_array())
        .cloned()
        .unwrap_or_default();
    if files.is_empty() {
        lines.push("No files changed.".to_owned());
    } else {
        for file in &files {
            let path = file["path"].as_str().unwrap_or("");
            let additions = file["additions"].as_u64().unwrap_or(0);
            let deletions = file["deletions"].as_u64().unwrap_or(0);
            lines.push(format!("- {path} (+{additions}/-{deletions})"));
        }
    }
    let patch = diff["diff"]
        .as_str()
        .or_else(|| diff["patch"].as_str())
        .unwrap_or("");
    if !patch.is_empty() {
        lines.push(String::new());
        lines.push("## Diff".to_owned());
        lines.push("```diff".to_owned());
        if patch.chars().count() > 50000 {
            lines.push(patch.chars().take(50000).collect());
            lines.push("... (diff truncated)".to_owned());
        } else {
            lines.push(patch.to_owned());
        }
        lines.push("```".to_owned());
    }
    lines.join("\n")
}

pub fn call(
    state: &crate::ServerState,
    name: &str,
    arguments: Value,
) -> Result<Value, CallError> {
    if definition(name).is_none() {
        return Err(CallError::UnknownTool(name.to_owned()));
    }
    let args = with_session_defaults(state, arguments);
    match name {
        "read_file" => coincide_core::workspace_tools::read_file(&args).map_err(|e| failed(e.to_string())),
        "write_file" => coincide_core::workspace_tools::write_file(&args).map_err(|e| failed(e.to_string())),
        "list_files" => coincide_core::workspace_tools::files(&args).map_err(|e| failed(e.to_string())),
        "search_files" => coincide_core::workspace_tools::search(&args).map_err(|e| failed(e.to_string())),
        "delete_file" => coincide_core::workspace_tools::delete_file(&args).map_err(|e| failed(e.to_string())),
        "delete_directory" => coincide_core::workspace_tools::delete_directory(&args).map_err(|e| failed(e.to_string())),
        "move_file" => coincide_core::workspace_tools::move_file(&args).map_err(|e| failed(e.to_string())),
        "copy_file" => coincide_core::workspace_tools::copy_file(&args).map_err(|e| failed(e.to_string())),
        "create_directory" => coincide_core::workspace_tools::create_dir(&args).map_err(|e| failed(e.to_string())),
        "read_directory" => coincide_core::workspace_tools::read_dir(&args).map_err(|e| failed(e.to_string())),
        "edit_file" | "multi_edit_file" => {
            coincide_core::workspace_tools::edit_file(&args).map_err(|e| failed(e.to_string()))
        }
        "search_regex" => coincide_core::workspace_tools::search_regex(&args).map_err(|e| failed(e.to_string())),
        "create_terminal" => {
            let mut params = json!({});
            if let Some(thread_id) = opt_str(&args, "threadId") {
                params["threadId"] = json!(thread_id);
            }
            engine_request(state, "terminal.create", params)
        }
        "write_terminal" => {
            let terminal_id = req_str(&args, "terminalId", name)?;
            let text = req_str(&args, "text", name)?;
            engine_request(
                state,
                "terminal.write",
                json!({"terminalId": terminal_id, "text": text}),
            )
        }
        "read_terminal" => {
            let terminal_id = req_str(&args, "terminalId", name)?;
            engine_request(state, "terminal.read", json!({"terminalId": terminal_id}))
        }
        "git_status" => {
            let thread_id = req_str(&args, "threadId", name)?;
            run_git_operation(state, "git.status", &thread_id, json!({}))
        }
        "git_diff" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let mut params = json!({});
            if let Some(path) = opt_str(&args, "path") {
                params["path"] = json!(path);
            }
            if let Some(staged) = opt_bool(&args, "staged") {
                params["staged"] = json!(staged);
            }
            run_git_operation(state, "git.diff", &thread_id, params)
        }
        "git_log" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let mut params = json!({});
            if let Some(limit) = opt_u64(&args, "limit") {
                params["limit"] = json!(limit);
            }
            if let Some(skip) = opt_u64(&args, "skip") {
                params["skip"] = json!(skip);
            }
            run_git_operation(state, "git.log", &thread_id, params)
        }
        "git_show" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let sha = req_str(&args, "sha", name)?;
            run_git_operation(state, "git.show", &thread_id, json!({"sha": sha}))
        }
        "git_diff_range" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let from = req_str(&args, "from", name)?;
            let to = req_str(&args, "to", name)?;
            run_git_operation(
                state,
                "git.diff.range",
                &thread_id,
                json!({"from": from, "to": to}),
            )
        }
        "git_diff_branch" => {
            let thread_id = req_str(&args, "threadId", name)?;
            run_git_operation(state, "git.diff.branch", &thread_id, json!({}))
        }
        "run_build" | "run_tests" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let command = req_str(&args, "command", name)?;
            let timeout_seconds = opt_u64(&args, "timeoutSeconds").unwrap_or(600);
            run_terminal_command(state, &thread_id, &command, timeout_seconds)
        }
        "git_commit" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let message = req_str(&args, "message", name)?;
            let mut params = json!({"action": "commit", "message": message});
            if let Some(paths) = args.get("paths").filter(|v| v.is_array()) {
                params["paths"] = paths.clone();
            }
            run_git_actions_operation(state, "git.actions.run", &thread_id, params, 120)
        }
        "git_push" => {
            let thread_id = req_str(&args, "threadId", name)?;
            run_git_actions_operation(
                state,
                "git.actions.run",
                &thread_id,
                json!({"action": "push"}),
                600,
            )
        }
        "git_pull" => {
            let thread_id = req_str(&args, "threadId", name)?;
            run_git_actions_operation(state, "git.actions.pull", &thread_id, json!({}), 600)
        }
        "git_branch_list" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let mut params = json!({});
            if let Some(scope) = opt_str(&args, "scope") {
                params["scope"] = json!(scope);
            }
            run_git_actions_operation(state, "git.branches.list", &thread_id, params, 60)
        }
        "git_branch_create" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let branch = req_str(&args, "name", name)?;
            run_git_actions_operation(
                state,
                "git.branches.create",
                &thread_id,
                json!({"name": branch}),
                60,
            )
        }
        "git_branch_checkout" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let branch = req_str(&args, "name", name)?;
            run_git_actions_operation(
                state,
                "git.branches.checkout",
                &thread_id,
                json!({"name": branch}),
                60,
            )
        }
        "mem_store" | "mem_retrieve" | "view_memory" | "mem_delete" | "mem_context_snapshot"
        | "context_persistence_store" => {
            let method = match name {
                "mem_store" => "memory.store",
                "mem_retrieve" => "memory.retrieve",
                "view_memory" => "memory.list",
                "mem_delete" => "memory.delete",
                "mem_context_snapshot" => "memory.snapshot",
                _ => "memory.context_store",
            };
            engine_request(state, method, args)
        }
        "mem_clear" => {
            req_str(&args, "scope", name)?;
            let confirmed = args.get("confirm").and_then(Value::as_bool).unwrap_or(false);
            if !confirmed {
                return Err(failed(
                    "mem_clear requires confirm=true; clearing a scope is irreversible.",
                ));
            }
            engine_request(state, "memory.clear", args)
        }
        "use_workers" | "intel_plan_task" | "execution_plan" => {
            let method = match name {
                "use_workers" => "workers.spawn",
                "intel_plan_task" => "workers.plan",
                _ => "workers.execution_plan",
            };
            let args = default_parent_thread(state, args);
            engine_request(state, method, args)
        }
        "list_workers" | "worker_status" | "worker_result" | "cancel_worker" => {
            let method = match name {
                "list_workers" => "workers.list",
                "worker_status" => "workers.status",
                "worker_result" => "workers.result",
                _ => "workers.cancel",
            };
            engine_request(state, method, args)
        }
        "intel_breakdown_task" => engine_request(state, "workers.breakdown", args),
        "list_apps" | "list_windows" | "get_window_state" | "get_desktop_state"
        | "verify_state" | "zoom" | "click" | "double_click" | "right_click" | "set_value"
        | "type_text" | "press_key" | "hotkey" | "scroll" | "drag" | "move_cursor"
        | "click_point" | "invoke_menu" | "launch_app" | "set_window_frame" => {
            run_computer_use_operation(state, name, &args)
        }
        "file_read" | "view_file" => {
            coincide_core::workspace_tools::read_file(&args).map_err(|error| failed(error.to_string()))
        }
        "file_write" => {
            coincide_core::workspace_tools::write_file(&args).map_err(|error| failed(error.to_string()))
        }
        "create_file" | "file_create" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let overwrite = opt_bool(&args, "overwrite").unwrap_or(false);
            if !overwrite && workspace_file_exists(&cwd, &path)? {
                return Err(failed(
                    "A file already exists at that path; use write_file to overwrite it.",
                ));
            }
            coincide_core::workspace_tools::write_file(&args).map_err(|error| failed(error.to_string()))
        }
        "file_append" => {
            let text = read_text_file(&args)?;
            let content = req_str(&args, "content", name)?;
            let mut params = args.clone();
            if let Some(object) = params.as_object_mut() {
                object.insert("content".to_owned(), json!(format!("{text}{content}")));
            }
            coincide_core::workspace_tools::write_file(&params)
                .map_err(|error| failed(error.to_string()))
        }
        "file_delete" => {
            coincide_core::workspace_tools::delete_file(&args).map_err(|error| failed(error.to_string()))
        }
        "dir_delete" => {
            coincide_core::workspace_tools::delete_directory(&args)
                .map_err(|error| failed(error.to_string()))
        }
        "file_move" => {
            coincide_core::workspace_tools::move_file(&args).map_err(|error| failed(error.to_string()))
        }
        "file_rename" => {
            let path = req_str(&args, "path", name)?;
            let new_name = req_str(&args, "newName", name)?;
            if new_name.is_empty()
                || new_name.contains('/')
                || new_name.contains('\\')
                || new_name == "."
                || new_name == ".."
            {
                return Err(failed("newName must be a single file name, not a path."));
            }
            let destination = match path.rfind('/') {
                Some(at) => format!("{}/{}", &path[..at], new_name),
                None => new_name,
            };
            let mut params = args.clone();
            if let Some(object) = params.as_object_mut() {
                object.insert("destination".to_owned(), json!(destination));
            }
            coincide_core::workspace_tools::move_file(&params)
                .map_err(|error| failed(error.to_string()))
        }
        "file_copy" => {
            coincide_core::workspace_tools::copy_file(&args).map_err(|error| failed(error.to_string()))
        }
        "dir_create" => {
            coincide_core::workspace_tools::create_dir(&args).map_err(|error| failed(error.to_string()))
        }
        "dir_read" => {
            let mut params = args.clone();
            if let Some(object) = params.as_object_mut() {
                object.insert("recursive".to_owned(), json!(false));
            }
            coincide_core::workspace_tools::read_dir(&params).map_err(|error| failed(error.to_string()))
        }
        "list_directory" => {
            coincide_core::workspace_tools::read_dir(&args).map_err(|error| failed(error.to_string()))
        }
        "tree_view" => {
            let max_depth = opt_u64(&args, "maxDepth").unwrap_or(3).clamp(1, 10) as usize;
            let path = opt_str(&args, "path").unwrap_or_default();
            let base_depth = if path.is_empty() || path == "." {
                0
            } else {
                path.split('/').count()
            };
            let mut params = args.clone();
            if let Some(object) = params.as_object_mut() {
                object.insert("recursive".to_owned(), json!(true));
            }
            let value = coincide_core::workspace_tools::read_dir(&params)
                .map_err(|error| failed(error.to_string()))?;
            let entries = value["entries"].as_array().cloned().unwrap_or_default();
            let filtered: Vec<Value> = entries
                .into_iter()
                .filter(|entry| {
                    entry["path"]
                        .as_str()
                        .map(|entry_path| {
                            entry_path.split('/').count().saturating_sub(base_depth) <= max_depth
                        })
                        .unwrap_or(false)
                })
                .collect();
            Ok(json!(filtered))
        }
        "search_directory" => {
            coincide_core::workspace_tools::files(&args).map_err(|error| failed(error.to_string()))
        }
        "search_text" => {
            coincide_core::workspace_tools::search(&args).map_err(|error| failed(error.to_string()))
        }
        "code_replace" => {
            let target = req_str(&args, "target", name)?;
            let replacement = match args.get("replacement").and_then(Value::as_str) {
                Some(value) => value.to_owned(),
                None => {
                    return Err(failed(
                        "Tool \"code_replace\" is missing required argument \"replacement\".",
                    ));
                }
            };
            if opt_bool(&args, "allowMultiple").unwrap_or(false) {
                let text = read_text_file(&args)?;
                if !text.contains(&target) {
                    return Err(failed("Target text was not found in the file."));
                }
                let mut params = args.clone();
                if let Some(object) = params.as_object_mut() {
                    object.insert("content".to_owned(), json!(text.replace(&target, &replacement)));
                }
                coincide_core::workspace_tools::write_file(&params)
                    .map_err(|error| failed(error.to_string()))
            } else {
                let mut params = args.clone();
                if let Some(object) = params.as_object_mut() {
                    object.insert("oldText".to_owned(), json!(target));
                    object.insert("newText".to_owned(), json!(replacement));
                    object.remove("target");
                    object.remove("replacement");
                    object.remove("allowMultiple");
                }
                coincide_core::workspace_tools::edit_file(&params)
                    .map_err(|error| failed(error.to_string()))
            }
        }
        "code_insert" => {
            let code = req_str(&args, "code", name)?;
            let mode = opt_str(&args, "mode").unwrap_or_else(|| "line".to_owned());
            let text = read_text_file(&args)?;
            let trailing = text.ends_with('\n');
            let mut lines: Vec<&str> = text.lines().collect();
            match mode.as_str() {
                "line" => {
                    let line = opt_u64(&args, "line").unwrap_or((lines.len() + 1) as u64) as usize;
                    if line < 1 || line > lines.len() + 1 {
                        return Err(failed("code_insert line is out of range for the file."));
                    }
                    lines.insert(line - 1, &code);
                }
                "before" | "after" => {
                    let pattern = req_str(&args, "pattern", name)?;
                    let matches: Vec<usize> = lines
                        .iter()
                        .enumerate()
                        .filter(|(_, line)| line.contains(pattern.as_str()))
                        .map(|(index, _)| index)
                        .collect();
                    if matches.len() != 1 {
                        return Err(failed("code_insert pattern must match exactly one line."));
                    }
                    let at = if mode == "before" {
                        matches[0]
                    } else {
                        matches[0] + 1
                    };
                    lines.insert(at, &code);
                }
                _ => return Err(failed("code_insert mode must be line, before, or after.")),
            }
            let mut updated = lines.join("\n");
            if trailing {
                updated.push('\n');
            }
            let mut params = args.clone();
            if let Some(object) = params.as_object_mut() {
                object.insert("content".to_owned(), json!(updated));
            }
            coincide_core::workspace_tools::write_file(&params)
                .map_err(|error| failed(error.to_string()))
        }
        "code_multi_edit" => {
            coincide_core::workspace_tools::edit_file(&args).map_err(|error| failed(error.to_string()))
        }
        "use_terminal" | "run_command" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let command = req_str(&args, "command", name)?;
            let timeout_seconds = opt_u64(&args, "timeoutSeconds").unwrap_or(600);
            run_terminal_command(state, &thread_id, &command, timeout_seconds)
        }
        "git_log_viewer" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let mut params = json!({});
            if let Some(limit) = opt_u64(&args, "limit") {
                params["limit"] = json!(limit);
            }
            if let Some(skip) = opt_u64(&args, "skip") {
                params["skip"] = json!(skip);
            }
            run_git_operation(state, "git.log", &thread_id, params)
        }
        "git_branch_compare" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let from = req_str(&args, "from", name)?;
            let to = req_str(&args, "to", name)?;
            run_git_operation(
                state,
                "git.diff.range",
                &thread_id,
                json!({"from": from, "to": to}),
            )
        }
        "project_diff" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let mut params = json!({});
            if let Some(path) = opt_str(&args, "path") {
                params["path"] = json!(path);
            }
            if let Some(staged) = opt_bool(&args, "staged") {
                params["staged"] = json!(staged);
            }
            run_git_operation(state, "git.diff", &thread_id, params)
        }
        "git_branch_manager" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let action = opt_str(&args, "action").unwrap_or_else(|| "list".to_owned());
            match action.as_str() {
                "list" => run_git_actions_operation(state, "git.branches.list", &thread_id, json!({}), 60),
                "create" => {
                    let branch = req_str(&args, "name", name)?;
                    run_git_actions_operation(
                        state,
                        "git.branches.create",
                        &thread_id,
                        json!({"name": branch}),
                        60,
                    )
                }
                "checkout" => {
                    let branch = req_str(&args, "name", name)?;
                    run_git_actions_operation(
                        state,
                        "git.branches.checkout",
                        &thread_id,
                        json!({"name": branch}),
                        60,
                    )
                }
                "delete" => {
                    let branch = req_str(&args, "name", name)?;
                    if !opt_bool(&args, "confirm").unwrap_or(false) {
                        return Err(failed("Deleting a branch is irreversible; pass confirm=true."));
                    }
                    let mut params = json!({"name": branch, "confirm": true});
                    if let Some(force) = opt_bool(&args, "force") {
                        params["force"] = json!(force);
                    }
                    run_git_actions_operation(state, "git.branches.delete", &thread_id, params, 60)
                }
                _ => Err(failed(
                    "git_branch_manager action must be list, create, checkout, or delete.",
                )),
            }
        }
        "save_to_memory" => engine_request(state, "memory.store", args),
        "use_mcp" => {
            let server_name = req_str(&args, "serverName", name)?;
            if server_name == "list" {
                return Ok(json!([{
                    "serverName": "coincide",
                    "description": "The coincide MCP server: this app system tools, served over stdio.",
                    "tools": DEFINITIONS.len(),
                }]));
            }
            if server_name != "coincide" {
                return Err(failed(format!(
                    "No MCP server named {server_name} is configured; this app serves only the coincide system-tools server."
                )));
            }
            let tool_name = match opt_str(&args, "toolName") {
                Some(tool) => tool,
                None => {
                    return Err(failed(
                        "Tool \"use_mcp\" is missing required argument \"toolName\".",
                    ));
                }
            };
            if tool_name == "list_tools" {
                return Ok(json!(DEFINITIONS.iter().map(|def| def.name).collect::<Vec<_>>()));
            }
            if tool_name == "use_mcp" {
                return Err(failed("use_mcp cannot call itself."));
            }
            if definition(&tool_name).is_none() {
                return Err(CallError::UnknownTool(tool_name));
            }
            let raw = opt_str(&args, "arguments").unwrap_or_else(|| "{}".to_owned());
            let parsed: Value = serde_json::from_str(&raw)
                .map_err(|_| failed("arguments must be a JSON object string."))?;
            if !parsed.is_object() {
                return Err(failed("arguments must be a JSON object string."));
            }
            call(state, &tool_name, parsed)
        }
        "take_screenshot" => {
            let mut params = args.clone();
            if let Some(object) = params.as_object_mut() {
                if !object.contains_key("include_screenshot") {
                    object.insert("include_screenshot".to_owned(), json!(true));
                }
            }
            run_computer_use_named(state, "take_screenshot", "get_desktop_state", &params)
        }
        "start_subagent" => {
            let args = default_parent_thread(state, args);
            engine_request(state, "workers.spawn", args)
        }
        "git_stash_operator" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let action = req_str(&args, "action", name)?;
            if (action == "pop" || action == "drop") && !opt_bool(&args, "confirm").unwrap_or(false) {
                return Err(failed("Stash pop and drop are destructive; pass confirm=true."));
            }
            let mut params = json!({"action": action});
            if let Some(message) = opt_str(&args, "message") {
                params["message"] = json!(message);
            }
            if let Some(include_untracked) = opt_bool(&args, "includeUntracked") {
                params["includeUntracked"] = json!(include_untracked);
            }
            if let Some(reference) = opt_str(&args, "reference") {
                params["reference"] = json!(reference);
            }
            if let Some(confirm) = opt_bool(&args, "confirm") {
                params["confirm"] = json!(confirm);
            }
            if let Some(paths) = args.get("paths").filter(|value| value.is_array()) {
                params["paths"] = paths.clone();
            }
            run_git_operation(state, "git.stash", &thread_id, params)
        }
        "git_blame_inspector" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let path = req_str(&args, "path", name)?;
            let mut params = json!({"path": path});
            if let Some(start) = opt_u64(&args, "start") {
                params["start"] = json!(start);
            }
            if let Some(end) = opt_u64(&args, "end") {
                params["end"] = json!(end);
            }
            run_git_operation(state, "git.blame", &thread_id, params)
        }
        "git_bisect" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let action = req_str(&args, "action", name)?;
            let mut params = json!({"action": action});
            if let Some(reference) = opt_str(&args, "reference") {
                params["reference"] = json!(reference);
            }
            if let Some(good) = opt_str(&args, "good") {
                params["good"] = json!(good);
            }
            if let Some(bad) = opt_str(&args, "bad") {
                params["bad"] = json!(bad);
            }
            run_git_operation(state, "git.bisect", &thread_id, params)
        }
        "git_cherry_pick" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let sha = req_str(&args, "sha", name)?;
            if !opt_bool(&args, "confirm").unwrap_or(false) {
                return Err(failed("Cherry-pick changes the working tree; pass confirm=true."));
            }
            let mut params = json!({"sha": sha, "confirm": true});
            if let Some(no_commit) = opt_bool(&args, "noCommit") {
                params["noCommit"] = json!(no_commit);
            }
            run_git_operation(state, "git.cherry_pick", &thread_id, params)
        }
        "version_control_operator" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let action = req_str(&args, "action", name)?;
            match action.as_str() {
                "status" => run_git_operation(state, "git.status", &thread_id, json!({})),
                "diff" => {
                    let mut params = json!({});
                    if let Some(path) = opt_str(&args, "path") {
                        params["path"] = json!(path);
                    }
                    if let Some(staged) = opt_bool(&args, "staged") {
                        params["staged"] = json!(staged);
                    }
                    run_git_operation(state, "git.diff", &thread_id, params)
                }
                "commit" => {
                    let message = req_str(&args, "message", name)?;
                    let mut params = json!({"action": "commit", "message": message});
                    if let Some(paths) = args.get("paths").filter(|value| value.is_array()) {
                        params["paths"] = paths.clone();
                    }
                    run_git_actions_operation(state, "git.actions.run", &thread_id, params, 120)
                }
                "branch" => {
                    if let Some(branch) = opt_str(&args, "name") {
                        run_git_actions_operation(
                            state,
                            "git.branches.create",
                            &thread_id,
                            json!({"name": branch}),
                            60,
                        )
                    } else {
                        run_git_actions_operation(state, "git.branches.list", &thread_id, json!({}), 60)
                    }
                }
                "rollback" => {
                    if !opt_bool(&args, "confirm").unwrap_or(false) {
                        return Err(failed(
                            "Rollback discards uncommitted changes; pass confirm=true.",
                        ));
                    }
                    let reference = opt_str(&args, "ref").unwrap_or_else(|| "HEAD~1".to_owned());
                    run_git_operation(
                        state,
                        "git.rollback",
                        &thread_id,
                        json!({"ref": reference, "confirm": true}),
                    )
                }
                _ => Err(failed(
                    "version_control_operator action must be status, commit, branch, diff, or rollback.",
                )),
            }
        }
        "git_pr_summary" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let limit = opt_u64(&args, "limit").unwrap_or(20);
            let from = opt_str(&args, "from");
            let to = opt_str(&args, "to");
            let log = run_git_operation(state, "git.log", &thread_id, json!({"limit": limit}))?;
            if let Some(error) = log["error"].as_str() {
                if !error.is_empty() {
                    return Err(failed(error.to_owned()));
                }
            }
            let diff = match (&from, &to) {
                (Some(from), Some(to)) => run_git_operation(
                    state,
                    "git.diff.range",
                    &thread_id,
                    json!({"from": from, "to": to}),
                )?,
                _ => run_git_operation(state, "git.diff.branch", &thread_id, json!({}))?,
            };
            if let Some(error) = diff["error"].as_str() {
                if !error.is_empty() {
                    return Err(failed(error.to_owned()));
                }
            }
            let markdown = pr_markdown(&log, &diff, from.as_deref(), to.as_deref());
            let files = diff["files"]
                .as_array()
                .or_else(|| diff["numstat"].as_array())
                .map(|entries| entries.len())
                .unwrap_or(0);
            Ok(json!({
                "markdown": markdown,
                "from": from.unwrap_or_default(),
                "to": to.unwrap_or_default(),
                "commits": log["commits"].as_array().map(|entries| entries.len()).unwrap_or(0),
                "files": files,
            }))
        }
        "git_conflict_resolver" => {
            let action = opt_str(&args, "action").unwrap_or_else(|| "detect".to_owned());
            match action.as_str() {
                "detect" => {
                    let mut params = args.clone();
                    if let Some(object) = params.as_object_mut() {
                        object.insert("pattern".to_owned(), json!("^(<{7}|={7}|>{7})"));
                        object.insert("limit".to_owned(), json!(200));
                    }
                    let value = coincide_core::workspace_tools::search_regex(&params)
                        .map_err(|error| failed(error.to_string()))?;
                    let files = conflict_files(&value);
                    let count = files.len();
                    Ok(json!({"conflictedFiles": files, "count": count}))
                }
                "resolve" => {
                    let path = req_str(&args, "path", name)?;
                    let strategy = opt_str(&args, "strategy").unwrap_or_else(|| "ours".to_owned());
                    let text = read_text_file(&args)?;
                    let (resolved, hunks) = resolve_conflicts(&text, &strategy)?;
                    let mut params = args.clone();
                    if let Some(object) = params.as_object_mut() {
                        object.insert("content".to_owned(), json!(resolved));
                    }
                    coincide_core::workspace_tools::write_file(&params)
                        .map_err(|error| failed(error.to_string()))?;
                    Ok(json!({"path": path, "resolved": true, "hunks": hunks, "strategy": strategy}))
                }
                _ => Err(failed("git_conflict_resolver action must be detect or resolve.")),
            }
        }
        "project_snapshot" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let root = session_expected_root(state)?;
            let log = run_git_operation(state, "git.log", &thread_id, json!({"limit": 1}))?;
            let head = log["commits"]
                .as_array()
                .and_then(|commits| commits.first())
                .and_then(|commit| commit["sha"].as_str())
                .map(str::to_owned)
                .context("Could not read the thread HEAD commit")
                .map_err(|error| failed(error.to_string()))?;
            let label = opt_str(&args, "label").unwrap_or_else(|| "Manual snapshot".to_owned());
            run_workspace_api_operation(
                state,
                "git.checkpoints.create",
                &thread_id,
                json!({"expectedRoot": root, "expectedHead": head, "label": label}),
            )
        }
        "project_changelog" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let root = session_expected_root(state)?;
            run_workspace_api_operation(
                state,
                "git.checkpoints.list",
                &thread_id,
                json!({"expectedRoot": root}),
            )
        }
        "project_restore" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let checkpoint_id = req_str(&args, "checkpointId", name)?;
            if !opt_bool(&args, "confirm").unwrap_or(false) {
                return Err(failed(
                    "Restoring a checkpoint discards uncommitted and untracked changes; pass confirm=true.",
                ));
            }
            let root = session_expected_root(state)?;
            run_workspace_api_operation(
                state,
                "git.checkpoints.restore",
                &thread_id,
                json!({"expectedRoot": root, "checkpointId": checkpoint_id, "confirm": true}),
            )
        }
        "safe_undo" => {
            let thread_id = req_str(&args, "threadId", name)?;
            if !opt_bool(&args, "confirm").unwrap_or(false) {
                return Err(failed(
                    "safe_undo restores the second-newest snapshot and discards uncommitted and untracked changes; pass confirm=true.",
                ));
            }
            let root = session_expected_root(state)?;
            let listed = run_workspace_api_operation(
                state,
                "git.checkpoints.list",
                &thread_id,
                json!({"expectedRoot": root.clone()}),
            )?;
            if let Some(error) = listed["error"].as_str() {
                if !error.is_empty() {
                    return Err(failed(error.to_owned()));
                }
            }
            let checkpoints = listed["checkpoints"].as_array().cloned().unwrap_or_default();
            if checkpoints.len() < 2 {
                return Err(failed("safe_undo requires at least two snapshots."));
            }
            let target = checkpoints[1]["id"]
                .as_str()
                .map(str::to_owned)
                .context("Snapshot list is missing checkpoint ids")
                .map_err(|error| failed(error.to_string()))?;
            let restored = run_workspace_api_operation(
                state,
                "git.checkpoints.restore",
                &thread_id,
                json!({"expectedRoot": root, "checkpointId": target, "confirm": true}),
            )?;
            Ok(json!({"restoredId": target, "restore": restored}))
        }
        "safe_validate_changes" => {
            if let Some(path) = opt_str(&args, "path") {
                let text = read_text_file(&args)?;
                let issues = validate_content(&path, &text);
                let count = issues.len();
                return Ok(json!({"issues": issues, "count": count}));
            }
            let mut params = args.clone();
            if let Some(object) = params.as_object_mut() {
                object.insert("pattern".to_owned(), json!("^(<{7}|={7}|>{7})"));
                object.insert("limit".to_owned(), json!(200));
            }
            let value = coincide_core::workspace_tools::search_regex(&params)
                .map_err(|error| failed(error.to_string()))?;
            let files = conflict_files(&value);
            let mut issues: Vec<Value> = Vec::new();
            for path in files {
                let mut file_args = args.clone();
                if let Some(object) = file_args.as_object_mut() {
                    object.insert("path".to_owned(), json!(path.clone()));
                }
                let text = read_text_file(&file_args)?;
                issues.extend(validate_content(&path, &text));
            }
            let count = issues.len();
            Ok(json!({"issues": issues, "count": count}))
        }
        _ => Err(CallError::UnknownTool(name.to_owned())),
    }
}

fn default_parent_thread(state: &crate::ServerState, mut args: Value) -> Value {
    if let Some(object) = args.as_object_mut() {
        if !object.contains_key("parentThreadId") {
            if let Some(thread_id) = &state.thread_id {
                object.insert("parentThreadId".to_owned(), json!(thread_id));
            }
        }
    }
    args
}

#[cfg(test)]
mod tests {
    use super::*;

    fn swift_string_at(text: &str, start: usize) -> Option<(String, usize)> {
        let bytes = text.as_bytes();
        let mut i = start;
        if bytes.get(i) != Some(&b'"') {
            return None;
        }
        i += 1;
        let mut out = String::new();
        while i < bytes.len() {
            match bytes[i] {
                b'\\' if i + 1 < bytes.len() => {
                    let next = bytes[i + 1];
                    match next {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'n' => out.push('\n'),
                        b't' => out.push('\t'),
                        other => {
                            out.push('\\');
                            out.push(other as char);
                        }
                    }
                    i += 2;
                }
                b'"' => return Some((out, i + 1)),
                _ => {
                    let ch_len = text[i..].chars().next()?.len_utf8();
                    out.push_str(&text[i..i + ch_len]);
                    i += ch_len;
                }
            }
        }
        None
    }

    fn swift_field(segment: &str, field: &str) -> Option<String> {
        let needle = format!("{field}: ");
        let at = segment.find(&needle)?;
        let quote = segment[at + needle.len()..].find('"')? + at + needle.len();
        swift_string_at(segment, quote).map(|(value, _)| value)
    }

    struct SwiftTool {
        name: String,
        description: String,
        action: String,
        channel: String,
        params: Vec<(String, String, bool)>,
    }

    fn parse_swift_registry() -> Vec<SwiftTool> {
        let source = include_str!("../../../../Agents/Core/SystemTools/SystemToolRegistry.swift");
        let mut tools = Vec::new();
        let mut rest = source;
        while let Some(at) = rest.find("SystemToolDefinition(") {
            rest = &rest[at + "SystemToolDefinition(".len()..];
            let end = rest.find("\n        SystemToolDefinition(").unwrap_or(rest.len());
            let segment = &rest[..end];
            let name = swift_field(segment, "name").expect("tool name");
            let description = swift_field(segment, "description").expect("tool description");
            let action = swift_field(segment, "action").expect("tool action");
            let channel = segment
                .find("channel: .")
                .and_then(|at| {
                    let after = &segment[at + "channel: .".len()..];
                    let end = after
                        .find(|c: char| !c.is_ascii_alphabetic())
                        .unwrap_or(after.len());
                    Some(after[..end].to_owned())
                })
                .expect("tool channel");
            let mut params = Vec::new();
            let mut param_rest = segment;
            while let Some(at) = param_rest.find("SystemToolParameter(name: ") {
                let after = &param_rest[at + "SystemToolParameter(name: ".len()..];
                let (param_name, next) = swift_string_at(after, 0).expect("param name");
                let after = &after[next..];
                let kind = swift_field(after, "type").expect("param type");
                let required = after
                    .find("required: ")
                    .map(|at| after[at + "required: ".len()..].starts_with("true"))
                    .expect("param required");
                params.push((param_name, kind, required));
                param_rest = after;
            }
            tools.push(SwiftTool {
                name,
                description,
                action,
                channel,
                params,
            });
        }
        tools
    }

    #[test]
    fn tool_table_matches_swift_registry() {
        let swift = parse_swift_registry();
        assert_eq!(swift.len(), 107, "Swift registry must hold 107 tools");
        assert_eq!(DEFINITIONS.len(), swift.len(), "MCP tool count must match Swift");
        for (def, expected) in DEFINITIONS.iter().zip(swift.iter()) {
            assert_eq!(def.name, expected.name, "tool name");
            assert_eq!(def.description, expected.description, "tool description");
            assert_eq!(def.action, expected.action, "tool action");
            assert_eq!(def.channel, expected.channel, "tool channel");
            assert_eq!(def.params.len(), expected.params.len(), "param count");
            for (param, (name, kind, required)) in
                def.params.iter().zip(expected.params.iter())
            {
                assert_eq!(param.name, *name, "param name");
                assert_eq!(param.kind, *kind, "param type");
                assert_eq!(param.required, *required, "param required");
            }
        }
    }
}
