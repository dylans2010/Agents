use anyhow::{Context, Result};
use serde_json::{Value, json};
use std::fs;
use std::path::{Component, Path};
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
    ToolDef {
        name: "create_artifact",
        description: "Create or update a Markdown artifact in .assist_temp/artifacts, or append to it. The artifact name stays inside that directory.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "name",
                kind: "string",
                required: true,
                description: "Artifact name, a plain file name without any path separator.",
            },
            ToolParam {
                name: "content",
                kind: "string",
                required: true,
                description: "Markdown content to write.",
            },
            ToolParam {
                name: "kind",
                kind: "string",
                required: false,
                description: "artifact or execution_plan. Defaults to artifact.",
            },
            ToolParam {
                name: "append",
                kind: "boolean",
                required: false,
                description: "Append to the existing artifact instead of replacing it. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "list_artifacts",
        description: "List Markdown artifacts in .assist_temp/artifacts, newest first.",
        action: "workspace.read_dir",
        channel: "desktop",
        params: &[
            P_CWD,
        ],
    },
    ToolDef {
        name: "read_artifact",
        description: "Read one Markdown artifact from .assist_temp/artifacts. Content over 60000 characters is truncated and marked.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "name",
                kind: "string",
                required: true,
                description: "Artifact name, a plain file name without any path separator.",
            },
        ],
    },
    ToolDef {
        name: "delete_artifact",
        description: "Permanently delete one Markdown artifact from .assist_temp/artifacts. Requires confirm=true. agent_notes.md is protected and cannot be deleted.",
        action: "workspace.delete_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "name",
                kind: "string",
                required: true,
                description: "Artifact name, a plain file name without any path separator.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: true,
                description: "Must be true. Deleting an artifact is permanent.",
            },
        ],
    },
    ToolDef {
        name: "format_json_file",
        description: "Validate a JSON file and rewrite it pretty-printed with sorted keys.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "csv_to_json",
        description: "Parse a tabular CSV file and write its records as a JSON array of objects.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "output",
                kind: "string",
                required: false,
                description: "Output path relative to the working directory. Defaults to the input path with a .json extension.",
            },
        ],
    },
    ToolDef {
        name: "json_to_csv",
        description: "Convert a JSON array of objects into RFC 4180 CSV and write it to a file.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "output",
                kind: "string",
                required: false,
                description: "Output path relative to the working directory. Defaults to the input path with a .csv extension.",
            },
        ],
    },
    ToolDef {
        name: "plist_to_json",
        description: "Convert an Apple property list file into a formatted JSON file.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "output",
                kind: "string",
                required: false,
                description: "Output path relative to the working directory. Defaults to the input path with a .json extension.",
            },
        ],
    },
    ToolDef {
        name: "json_to_plist",
        description: "Convert a JSON file into an Apple property list file, XML or binary.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "output",
                kind: "string",
                required: false,
                description: "Output path relative to the working directory. Defaults to the input path with a .plist extension.",
            },
            ToolParam {
                name: "format",
                kind: "string",
                required: false,
                description: "xml or binary. Defaults to xml.",
            },
        ],
    },
    ToolDef {
        name: "json_validate",
        description: "Validate JSON syntax in a file. Writes back pretty-printed with sorted keys only when write is true.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "write",
                kind: "boolean",
                required: false,
                description: "Write the formatted JSON back to the file. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "json_validator_tool",
        description: "Validate JSON syntax and report structural errors without writing anything.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "yaml_validate",
        description: "Heuristically validate YAML: tabs, unbalanced brackets and quotes, duplicate top-level keys. Writes a normalized copy only when write is true and validation passes.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "write",
                kind: "boolean",
                required: false,
                description: "Write the normalized YAML back to the file. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "yaml_parser_tool",
        description: "Validate YAML and convert its mapping, list, and scalar subset into a structured JSON representation. No anchors, aliases, or block scalars.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "plist_edit",
        description: "Get, set, or delete one key in a property list file, with an atomic write and a verify re-read. Keys may use dot paths for nested dictionaries.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "action",
                kind: "string",
                required: true,
                description: "get, set, or delete.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: true,
                description: "Property list key, optionally a dot path.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: false,
                description: "String value for set.",
            },
        ],
    },
    ToolDef {
        name: "plist_editor",
        description: "Inspect, read, set, or delete keys in an Apple property list file, XML or binary.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "action",
                kind: "string",
                required: false,
                description: "read, get, set, or delete. Defaults to read.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: false,
                description: "Property list key, optionally a dot path.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: false,
                description: "String value for set.",
            },
        ],
    },
    ToolDef {
        name: "binary_plist_converter",
        description: "Convert a property list file between binary and XML representations.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "output",
                kind: "string",
                required: false,
                description: "Output path relative to the working directory. Defaults to the input path with a converted extension.",
            },
            ToolParam {
                name: "format",
                kind: "string",
                required: true,
                description: "Target representation: xml or binary.",
            },
        ],
    },
    ToolDef {
        name: "file_metadata",
        description: "Read size, modification time, symlink target, and executable bit for one file or directory, from the real directory read.",
        action: "workspace.read_dir",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "file_hash_verify",
        description: "Hash a file and compare it to an expected hash. A mismatch returns match false, not an error.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "expectedHash",
                kind: "string",
                required: true,
                description: "Expected lowercase hex digest.",
            },
            ToolParam {
                name: "algorithm",
                kind: "string",
                required: false,
                description: "sha256, sha512, sha1, or md5. Defaults to sha256.",
            },
        ],
    },
    ToolDef {
        name: "generate_file_checksum",
        description: "Compute the SHA-256, SHA-512, SHA-1, and MD5 checksums of a file.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "file_checksum_verifier",
        description: "Compute the SHA-256 and MD5 checksums of a file, optionally verifying one expected hash.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "expectedHash",
                kind: "string",
                required: false,
                description: "Expected lowercase hex digest to verify.",
            },
            ToolParam {
                name: "algorithm",
                kind: "string",
                required: false,
                description: "sha256 or md5. Defaults to sha256.",
            },
        ],
    },
    ToolDef {
        name: "file_compare_diff",
        description: "Compare two files line by line and produce a unified diff with added and removed line counts.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "otherPath",
                kind: "string",
                required: true,
                description: "Second file path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "file_head_preview",
        description: "Read the first N lines of a file without dumping the whole file.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "lines",
                kind: "integer",
                required: false,
                description: "Lines to return, 1 to 5000. Defaults to 20.",
            },
        ],
    },
    ToolDef {
        name: "code_generate",
        description: "Scaffold a file from a built-in template: swift_struct, swift_class, swiftui_view, or test. Refuses to overwrite an existing file.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "template",
                kind: "string",
                required: true,
                description: "swift_struct, swift_class, swiftui_view, or test.",
            },
            ToolParam {
                name: "module",
                kind: "string",
                required: false,
                description: "Module name used by the test template. Defaults to the project directory name.",
            },
        ],
    },
    ToolDef {
        name: "code_format",
        description: "Normalize a text file or directory: trailing whitespace, blank-line collapse, tab expansion, trailing newline. This is basic normalization, not a real formatter.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory relative to the working directory. Defaults to the working directory itself.",
            },
        ],
    },
    ToolDef {
        name: "swift_format_lint",
        description: "Check or format Swift files with the swiftformat CLI when it is installed. If swiftformat is absent the tool reports that honestly instead of pretending.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
            ToolParam {
                name: "mode",
                kind: "string",
                required: false,
                description: "lint or format. Defaults to lint.",
            },
        ],
    },
    ToolDef {
        name: "code_mutation_engine",
        description: "Replace the brace-balanced body of a named symbol, or an exact target block, in one file. Matching is textual and the output is never syntax-checked.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "replacement",
                kind: "string",
                required: true,
                description: "Replacement text for the symbol body or target block.",
            },
            ToolParam {
                name: "symbol",
                kind: "string",
                required: false,
                description: "Symbol name whose brace-balanced body is replaced.",
            },
            ToolParam {
                name: "target",
                kind: "string",
                required: false,
                description: "Exact block of text to replace.",
            },
        ],
    },
    ToolDef {
        name: "patch_application_engine",
        description: "Replace a verbatim original block with updated text in a file, replacing every occurrence.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "original",
                kind: "string",
                required: true,
                description: "Verbatim block to replace.",
            },
            ToolParam {
                name: "updated",
                kind: "string",
                required: true,
                description: "Replacement text.",
            },
        ],
    },
    ToolDef {
        name: "automated_repair_engine",
        description: "Annotation only: insert an AssistAutoRepair review-required annotation above the named lines. It does not fix anything and does not rebuild.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "errors",
                kind: "array",
                required: true,
                description: "Line numbers, 1-based, to annotate.",
            },
        ],
    },
    ToolDef {
        name: "regex_replace_in_files",
        description: "Search with a regular expression and replace every match across the matching files.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "pattern",
                kind: "string",
                required: true,
                description: "Regular expression to search for.",
            },
            ToolParam {
                name: "replacement",
                kind: "string",
                required: true,
                description: "Replacement text.",
            },
            ToolParam {
                name: "query",
                kind: "string",
                required: false,
                description: "Optional substring filter over file paths.",
            },
        ],
    },
    ToolDef {
        name: "symbol_rename_project",
        description: "Rename a symbol across Swift files with whole-word matching.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "oldName",
                kind: "string",
                required: true,
                description: "Existing symbol name.",
            },
            ToolParam {
                name: "newName",
                kind: "string",
                required: true,
                description: "New symbol name.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Directory to search, relative to the working directory. Defaults to the working directory itself.",
            },
        ],
    },
    ToolDef {
        name: "symbol_move_file",
        description: "Move a brace-balanced symbol block from a source file to a destination file, verified with a restore on failure.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "sourcePath",
                kind: "string",
                required: true,
                description: "Source file path relative to the working directory.",
            },
            ToolParam {
                name: "destinationPath",
                kind: "string",
                required: true,
                description: "Destination file path relative to the working directory.",
            },
            ToolParam {
                name: "symbol",
                kind: "string",
                required: true,
                description: "Symbol name whose block is moved.",
            },
        ],
    },
    ToolDef {
        name: "import_cleanup",
        description: "Remove unused import lines from a Swift file. Protected modules are never removed.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "batch_rename_files",
        description: "Rename files matching a substring in a directory. With dryRun true it only reports the planned renames.",
        action: "workspace.move_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "directory",
                kind: "string",
                required: false,
                description: "Directory to rename inside. Defaults to the working directory itself.",
            },
            ToolParam {
                name: "pattern",
                kind: "string",
                required: true,
                description: "Substring to match in file names.",
            },
            ToolParam {
                name: "replacement",
                kind: "string",
                required: true,
                description: "Replacement substring.",
            },
            ToolParam {
                name: "dryRun",
                kind: "boolean",
                required: false,
                description: "Report planned renames without moving anything. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "file_backup",
        description: "Copy a file to .assist_temp/backups with a timestamped .bak name and verify the size.",
        action: "workspace.copy_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "session_export",
        description: "Write a Markdown session export with title, timestamp, session id, workspace, and notes. Never reads conversation history.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "title",
                kind: "string",
                required: true,
                description: "Export title.",
            },
            ToolParam {
                name: "sessionId",
                kind: "string",
                required: false,
                description: "Session id to record. Defaults to a new id.",
            },
            ToolParam {
                name: "notes",
                kind: "string",
                required: false,
                description: "Notes to include in the export.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Output path. Defaults to a timestamped file under .assist_temp.",
            },
            ToolParam {
                name: "overwrite",
                kind: "boolean",
                required: false,
                description: "Allow overwriting an existing export file. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "markdown_toc_generate",
        description: "Generate a table of contents from a Markdown file headings and insert or update it between TOC markers.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "readme_generate",
        description: "Generate a README skeleton from a real inspection of the repository contents. Refuses to overwrite without overwrite true.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Output path. Defaults to README.md.",
            },
            ToolParam {
                name: "overwrite",
                kind: "boolean",
                required: false,
                description: "Allow overwriting an existing README. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "docs_generate",
        description: "Generate Markdown API docs from the public declarations in Swift sources. Refuses to overwrite without overwrite true.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Source file or directory. Defaults to the working directory itself.",
            },
            ToolParam {
                name: "output",
                kind: "string",
                required: false,
                description: "Output path. Defaults to API.md.",
            },
            ToolParam {
                name: "overwrite",
                kind: "boolean",
                required: false,
                description: "Allow overwriting an existing docs file. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "test_data_factory",
        description: "Write a JSON or Swift test fixture from a field list such as id:Int,name:String. Refuses to overwrite without overwrite true.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "format",
                kind: "string",
                required: true,
                description: "json or swift.",
            },
            ToolParam {
                name: "fields",
                kind: "string",
                required: true,
                description: "Comma-separated field list, each name:Type.",
            },
            ToolParam {
                name: "overwrite",
                kind: "boolean",
                required: false,
                description: "Allow overwriting an existing fixture. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "ui_test_scaffold",
        description: "Write an XCTest UI test scaffold for an app. Refuses to overwrite without overwrite true.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "appName",
                kind: "string",
                required: false,
                description: "App name under test. Defaults to the project directory name.",
            },
            ToolParam {
                name: "overwrite",
                kind: "boolean",
                required: false,
                description: "Allow overwriting an existing test file. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "test_snapshot_manage",
        description: "List snapshot references under __Snapshots__, or clean unreferenced snapshots with confirm true. Unreferenced detection is heuristic.",
        action: "workspace.read_dir",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "action",
                kind: "string",
                required: false,
                description: "list or clean. Defaults to list.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Snapshots directory. Defaults to __Snapshots__.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: false,
                description: "Must be true to clean snapshots.",
            },
        ],
    },
    ToolDef {
        name: "open_in_finder",
        description: "Open a file or directory in macOS Finder.",
        action: "system.open_in_finder",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "reveal_in_finder",
        description: "Reveal and highlight a file or directory in macOS Finder.",
        action: "system.reveal_in_finder",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "image_encode_base64",
        description: "Read an image file and return its Base64 encoding, optionally as a data URI.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "dataURI",
                kind: "boolean",
                required: false,
                description: "Return a data URI instead of bare Base64. Defaults to false.",
            },
        ],
    },
    ToolDef {
        name: "image_decode_base64",
        description: "Decode a Base64 string into an image file on disk.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "base64",
                kind: "string",
                required: true,
                description: "Base64-encoded image bytes.",
            },
        ],
    },
    ToolDef {
        name: "image_get_dimensions",
        description: "Read image width, height, and format with the sips CLI and return its real output.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "image_convert_format",
        description: "Convert an image between PNG, JPEG, TIFF, BMP, and GIF with the sips CLI and return its real output.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
            ToolParam {
                name: "format",
                kind: "string",
                required: true,
                description: "png, jpg, tiff, bmp, or gif.",
            },
            ToolParam {
                name: "output",
                kind: "string",
                required: false,
                description: "Output path relative to the working directory. Defaults to the input path with the new extension.",
            },
            ToolParam {
                name: "quality",
                kind: "integer",
                required: false,
                description: "JPEG quality, 0 to 100.",
            },
        ],
    },
    ToolDef {
        name: "image_generate_thumbnail",
        description: "Generate a scaled thumbnail preserving aspect ratio with the sips CLI and return its real output.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
            ToolParam {
                name: "output",
                kind: "string",
                required: false,
                description: "Output path relative to the working directory. Defaults to the input path with a -thumb suffix.",
            },
            ToolParam {
                name: "maxPixels",
                kind: "integer",
                required: false,
                description: "Maximum thumbnail pixel size. Defaults to 256.",
            },
        ],
    },
    ToolDef {
        name: "image_extract_metadata",
        description: "Extract embedded EXIF, TIFF, GPS, and camera metadata with the mdls CLI and return its real output.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "zip_file",
        description: "Compress a file or directory into a .zip archive with the system ditto CLI and return its real output and exit code.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
            ToolParam {
                name: "output",
                kind: "string",
                required: true,
                description: "Archive path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "unzip_file",
        description: "Extract a .zip archive into a target directory with the system ditto CLI and return its real output and exit code.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
            ToolParam {
                name: "destination",
                kind: "string",
                required: true,
                description: "Target directory relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "tar_archive_create",
        description: "Create a .tar or .tar.gz archive from a directory or file with the tar CLI and return its real output and exit code.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
            ToolParam {
                name: "output",
                kind: "string",
                required: true,
                description: "Archive path relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "tar_archive_extract",
        description: "Extract a .tar or .tar.gz archive into a destination directory with the tar CLI and return its real output and exit code.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
            ToolParam {
                name: "destination",
                kind: "string",
                required: true,
                description: "Destination directory relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "gzip_compress_file",
        description: "Compress a single file to a .gz file with the system gzip CLI and return its real output and exit code.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
            ToolParam {
                name: "output",
                kind: "string",
                required: false,
                description: "Output path relative to the working directory. Defaults to the input path with a .gz extension.",
            },
        ],
    },
    ToolDef {
        name: "gzip_decompress_file",
        description: "Decompress a .gz file into a destination file with the system gzip CLI and return its real output and exit code.",
        action: "terminal.create",
        channel: "engine",
        params: &[
            P_THREAD_ID,
            P_CWD,
            P_PATH,
            ToolParam {
                name: "output",
                kind: "string",
                required: false,
                description: "Output path relative to the working directory. Defaults to the input path without the .gz extension.",
            },
        ],
    },
    ToolDef {
        name: "count_file_lines",
        description: "Count total, code, comment, and blank lines across workspace files or directories.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory. Defaults to the working directory itself.",
            },
        ],
    },
    ToolDef {
        name: "extract_code_symbols",
        description: "Extract class, struct, enum, protocol, actor, func, and extension declarations from source code.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Source file or directory. Defaults to the working directory itself.",
            },
        ],
    },
    ToolDef {
        name: "find_duplicate_files",
        description: "Find byte-identical duplicate files by SHA-256 content hashing.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Directory to search. Defaults to the working directory itself.",
            },
        ],
    },
    ToolDef {
        name: "env_capture_logs",
        description: "Capture a memory snapshot and return its metadata: timestamp, message, and id. It does not read log contents.",
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

fn validate_relative_path(path: &str) -> Result<(), CallError> {
    if path.is_empty() || path.starts_with('/') {
        return Err(failed("Path must be relative to the working directory."));
    }
    let rel = Path::new(path);
    if rel
        .components()
        .any(|part| !matches!(part, Component::Normal(_)))
    {
        return Err(failed("Path must not contain . or .. components."));
    }
    Ok(())
}

fn resolve_workspace_file(cwd: &str, path: &str) -> Result<std::path::PathBuf, CallError> {
    validate_relative_path(path)?;
    let root = fs::canonicalize(cwd)
        .map_err(|error| failed(format!("Workspace directory is unavailable: {error}")))?;
    let target = root.join(path);
    let canonical = target
        .canonicalize()
        .map_err(|_| failed(format!("File does not exist or cannot be read: {path}")))?;
    if !canonical.starts_with(&root) {
        return Err(failed("Path escapes the working directory."));
    }
    Ok(canonical)
}

fn read_workspace_bytes(cwd: &str, path: &str) -> Result<Vec<u8>, CallError> {
    let target = resolve_workspace_file(cwd, path)?;
    let bytes = fs::read(&target).map_err(|error| failed(error.to_string()))?;
    if bytes.len() > 3 * 1024 * 1024 {
        return Err(failed("File exceeds 3 MiB."));
    }
    Ok(bytes)
}

fn write_workspace_bytes(cwd: &str, path: &str, bytes: &[u8]) -> Result<(), CallError> {
    validate_relative_path(path)?;
    let root = fs::canonicalize(cwd)
        .map_err(|error| failed(format!("Workspace directory is unavailable: {error}")))?;
    let target = root.join(path);
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(|error| failed(error.to_string()))?;
    }
    let canonical_parent = target
        .parent()
        .map(fs::canonicalize)
        .transpose()
        .map_err(|error| failed(error.to_string()))?;
    if let Some(parent) = canonical_parent {
        if !parent.starts_with(&root) {
            return Err(failed("Path escapes the working directory."));
        }
    }
    fs::write(&target, bytes).map_err(|error| failed(error.to_string()))
}

fn read_text_file_at(cwd: &str, path: &str) -> Result<String, CallError> {
    read_text_file(&json!({"cwd": cwd, "path": path}))
}

fn write_text_file(cwd: &str, path: &str, content: &str) -> Result<Value, CallError> {
    coincide_core::workspace_tools::write_file(&json!({"cwd": cwd, "path": path, "content": content}))
        .map_err(|error| failed(error.to_string()))
}

fn read_dir_entries(cwd: &str, path: &str, recursive: bool) -> Result<Vec<Value>, CallError> {
    let value = coincide_core::workspace_tools::read_dir(
        &json!({"cwd": cwd, "path": path, "recursive": recursive}),
    )
    .map_err(|error| failed(error.to_string()))?;
    Ok(value["entries"]
        .as_array()
        .cloned()
        .unwrap_or_default())
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn clean_terminal_output(output: &str) -> String {
    output
        .lines()
        .filter(|line| {
            let trimmed = line.trim();
            !trimmed.contains("__AGENTS_TOOL_DONE__:") && !trimmed.starts_with("cd ")
        })
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_owned()
}

fn run_shell_status(
    state: &crate::ServerState,
    thread_id: &str,
    cwd: &str,
    command: &str,
    timeout_seconds: u64,
) -> Result<(i64, String), CallError> {
    let full = format!("cd {} && {}", shell_quote(cwd), command);
    let result = run_terminal_command(state, thread_id, &full, timeout_seconds)?;
    if result["timedOut"] == true {
        return Err(failed("Terminal command did not finish in time."));
    }
    let exit_code = result["exitCode"].as_i64().unwrap_or(-1);
    let output = clean_terminal_output(result["output"].as_str().unwrap_or(""));
    Ok((exit_code, output))
}

fn run_shell(
    state: &crate::ServerState,
    thread_id: &str,
    cwd: &str,
    command: &str,
    timeout_seconds: u64,
) -> Result<String, CallError> {
    let (exit_code, output) = run_shell_status(state, thread_id, cwd, command, timeout_seconds)?;
    if exit_code != 0 {
        return Err(failed(format!(
            "Command failed with exit code {exit_code}: {output}"
        )));
    }
    Ok(output)
}

fn parse_hex_line(output: &str, len: usize) -> Option<String> {
    for line in output.lines() {
        let trimmed = line.trim();
        if trimmed.len() == len && trimmed.chars().all(|c| c.is_ascii_hexdigit()) {
            return Some(trimmed.to_lowercase());
        }
        if trimmed.len() > len + 2 {
            let (head, rest) = trimmed.split_at(len);
            if head.chars().all(|c| c.is_ascii_hexdigit()) && rest.starts_with("  ") {
                return Some(head.to_lowercase());
            }
        }
    }
    None
}

fn shasum_hex(
    state: &crate::ServerState,
    thread_id: &str,
    cwd: &str,
    path: &str,
    algorithm: &str,
) -> Result<String, CallError> {
    let command = match algorithm {
        "sha256" => format!("shasum -a 256 {}", shell_quote(path)),
        "sha512" => format!("shasum -a 512 {}", shell_quote(path)),
        "sha1" => format!("shasum -a 1 {}", shell_quote(path)),
        "md5" => format!("md5 -q {}", shell_quote(path)),
        _ => return Err(failed("Checksum algorithm must be sha256, sha512, sha1, or md5.")),
    };
    let output = run_shell(state, thread_id, cwd, &command, 120)?;
    let len = match algorithm {
        "sha256" => 64,
        "sha512" => 128,
        "sha1" => 40,
        _ => 32,
    };
    parse_hex_line(&output, len)
        .ok_or_else(|| failed(format!("Could not parse {algorithm} output: {output}")))
}

const BASE64_ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn base64_encode(data: &[u8]) -> String {
    let mut out = String::new();
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = *chunk.get(1).unwrap_or(&0) as u32;
        let b2 = *chunk.get(2).unwrap_or(&0) as u32;
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(BASE64_ALPHABET[(triple >> 18 & 63) as usize] as char);
        out.push(BASE64_ALPHABET[(triple >> 12 & 63) as usize] as char);
        out.push(if chunk.len() > 1 {
            BASE64_ALPHABET[(triple >> 6 & 63) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            BASE64_ALPHABET[(triple & 63) as usize] as char
        } else {
            '='
        });
    }
    out
}

fn base64_decode(text: &str) -> Option<Vec<u8>> {
    let clean: Vec<u8> = text.bytes().filter(|b| !b.is_ascii_whitespace()).collect();
    if clean.is_empty() || clean.len() % 4 != 0 {
        return None;
    }
    let value = |b: u8| -> Option<u32> {
        match b {
            b'A'..=b'Z' => Some((b - b'A') as u32),
            b'a'..=b'z' => Some((b - b'a' + 26) as u32),
            b'0'..=b'9' => Some((b - b'0' + 52) as u32),
            b'+' => Some(62),
            b'/' => Some(63),
            b'=' => Some(0),
            _ => None,
        }
    };
    let mut out = Vec::new();
    for chunk in clean.chunks(4) {
        let v0 = value(chunk[0])?;
        let v1 = value(chunk[1])?;
        let v2 = value(chunk[2])?;
        let v3 = value(chunk[3])?;
        let triple = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3;
        out.push((triple >> 16 & 0xff) as u8);
        if chunk[2] != b'=' {
            out.push((triple >> 8 & 0xff) as u8);
        }
        if chunk[3] != b'=' {
            out.push((triple & 0xff) as u8);
        }
    }
    Some(out)
}

fn artifact_path(name: &str, tool: &str) -> Result<String, CallError> {
    if name.is_empty() || name.contains('/') || name.contains('\\') || name == "." || name == ".." {
        return Err(failed(format!(
            "Tool \"{tool}\" artifact name must be a plain file name without any path separator."
        )));
    }
    let file_name = if name.ends_with(".md") {
        name.to_owned()
    } else {
        format!("{name}.md")
    };
    Ok(format!(".assist_temp/artifacts/{file_name}"))
}

fn parse_csv(text: &str) -> Vec<Vec<String>> {
    let mut rows: Vec<Vec<String>> = Vec::new();
    let mut row: Vec<String> = Vec::new();
    let mut field = String::new();
    let mut in_quotes = false;
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if in_quotes {
            if c == '"' {
                if i + 1 < chars.len() && chars[i + 1] == '"' {
                    field.push('"');
                    i += 2;
                    continue;
                }
                in_quotes = false;
            } else {
                field.push(c);
            }
        } else if c == '"' && field.is_empty() {
            in_quotes = true;
        } else if c == ',' {
            row.push(std::mem::take(&mut field));
        } else if c == '\n' || c == '\r' {
            if c == '\r' && i + 1 < chars.len() && chars[i + 1] == '\n' {
                i += 1;
            }
            row.push(std::mem::take(&mut field));
            rows.push(std::mem::take(&mut row));
        } else {
            field.push(c);
        }
        i += 1;
    }
    if !field.is_empty() || !row.is_empty() {
        row.push(field);
        rows.push(row);
    }
    rows
}

fn csv_field(value: &str) -> String {
    if value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r') {
        format!("\"{}\"", value.replace('"', "\"\""))
    } else {
        value.to_owned()
    }
}

fn json_scalar_text(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Null => String::new(),
        other => serde_json::to_string(other).unwrap_or_default(),
    }
}

fn line_counts(content: &str) -> (usize, usize, usize, usize) {
    if content.is_empty() {
        return (0, 0, 0, 0);
    }
    let mut lines: Vec<&str> = content.split('\n').collect();
    if content.ends_with('\n') {
        lines.pop();
    }
    let (mut total, mut code, mut comment, mut blank) = (0, 0, 0, 0);
    let mut in_block = false;
    for raw in lines {
        total += 1;
        let line = raw.trim();
        if line.is_empty() {
            blank += 1;
            continue;
        }
        if in_block {
            comment += 1;
            if line.contains("*/") {
                in_block = false;
            }
            continue;
        }
        if line.starts_with("//") || line.starts_with('#') || line.starts_with('*') {
            comment += 1;
            continue;
        }
        if line.starts_with("/*") {
            comment += 1;
            if !line[2..].contains("*/") {
                in_block = true;
            }
            continue;
        }
        code += 1;
    }
    (total, code, comment, blank)
}

fn declaration_name(tokens: &[&str], symbol: Option<&str>) -> Option<(String, String)> {
    let keywords = ["class", "struct", "enum", "protocol", "actor", "extension", "func"];
    let mut found: Option<(String, String)> = None;
    for (i, token) in tokens.iter().enumerate() {
        if !keywords.contains(token) {
            continue;
        }
        let Some(next) = tokens.get(i + 1) else {
            continue;
        };
        let name: String = next
            .chars()
            .take_while(|c| *c != '(' && *c != '<' && *c != ':' && *c != '{' && *c != ' ')
            .collect();
        if name.is_empty() {
            continue;
        }
        if let Some(want) = symbol {
            if name == want {
                return Some((token.to_string(), name));
            }
        } else {
            found = Some((token.to_string(), name));
        }
    }
    found
}

fn extract_symbols(content: &str, path: &str) -> Vec<Value> {
    let mut symbols = Vec::new();
    for (index, line) in content.lines().enumerate() {
        let tokens: Vec<&str> = line.split_whitespace().collect();
        if let Some((kind, name)) = declaration_name(&tokens, None) {
            symbols.push(json!({
                "path": path,
                "kind": kind,
                "name": name,
                "line": index + 1,
            }));
        }
    }
    symbols
}

fn symbol_declaration_line(lines: &[&str], symbol: &str) -> Option<usize> {
    for (index, line) in lines.iter().enumerate() {
        let tokens: Vec<&str> = line.split_whitespace().collect();
        if declaration_name(&tokens, Some(symbol)).is_some() {
            return Some(index);
        }
    }
    None
}

fn brace_block_end(lines: &[&str], start: usize) -> Option<usize> {
    let mut depth: i64 = 0;
    let mut saw_open = false;
    let mut index = start;
    while index < lines.len() {
        for c in lines[index].chars() {
            if c == '{' {
                depth += 1;
                saw_open = true;
            }
            if c == '}' {
                depth -= 1;
            }
        }
        if saw_open && depth == 0 {
            return Some(index);
        }
        if depth < 0 {
            return None;
        }
        index += 1;
    }
    None
}

fn is_word_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

fn whole_word_replace(content: &str, old: &str, new: &str) -> (String, usize) {
    if old.is_empty() {
        return (content.to_owned(), 0);
    }
    let mut out = String::new();
    let mut count = 0;
    let mut rest = content;
    while let Some(at) = rest.find(old) {
        let before_ok = at == 0 || !is_word_char(rest[..at].chars().last().unwrap());
        let after = &rest[at + old.len()..];
        let after_ok = after.chars().next().map_or(true, |c| !is_word_char(c));
        if before_ok && after_ok {
            out.push_str(&rest[..at]);
            out.push_str(new);
            count += 1;
        } else {
            out.push_str(&rest[..at + old.len()]);
        }
        rest = after;
    }
    out.push_str(rest);
    (out, count)
}

fn toc_slug(text: &str) -> String {
    let mut kept = String::new();
    for c in text.to_lowercase().chars() {
        if c.is_alphanumeric() || c == ' ' || c == '-' {
            kept.push(c);
        }
    }
    let spaced = kept.replace(' ', "-");
    let mut slug = String::new();
    let mut previous_dash = false;
    for c in spaced.chars() {
        if c == '-' {
            if !previous_dash {
                slug.push(c);
            }
            previous_dash = true;
        } else {
            slug.push(c);
            previous_dash = false;
        }
    }
    slug.trim_matches('-').to_owned()
}

fn normalized_text(content: &str) -> String {
    let mut out: Vec<String> = Vec::new();
    let mut blanks = 0;
    for line in content.split('\n') {
        let expanded = line.replace('\t', "    ");
        let trimmed = expanded.trim_end().to_owned();
        if trimmed.is_empty() {
            blanks += 1;
            if blanks <= 2 {
                out.push(trimmed);
            }
        } else {
            blanks = 0;
            out.push(trimmed);
        }
    }
    let mut text = out.join("\n");
    if !text.is_empty() && !text.ends_with('\n') {
        text.push('\n');
    }
    text
}

fn valid_swift_identifier(name: &str) -> bool {
    let mut chars = name.chars();
    match chars.next() {
        Some(c) if c.is_ascii_alphabetic() || c == '_' => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn code_template(template: &str, module: &str, file_name: &str, tool: &str) -> Result<String, CallError> {
    let base = file_name.rsplit_once('.').map_or(file_name, |(stem, _)| stem);
    if !valid_swift_identifier(base) {
        return Err(failed(format!(
            "Tool \"{tool}\" file name must be a valid Swift identifier for code generation."
        )));
    }
    match template {
        "swift_struct" => Ok(format!(
            "import Foundation\n\npublic struct {base} {{\n    public init() {{}}\n}}\n"
        )),
        "swift_class" => Ok(format!(
            "import Foundation\n\npublic final class {base} {{\n    public init() {{}}\n}}\n"
        )),
        "swiftui_view" => Ok(format!(
            "import SwiftUI\n\npublic struct {base}: View {{\n    public var body: some View {{\n        Text(\"{base}\")\n    }}\n}}\n"
        )),
        "test" => Ok(format!(
            "import Testing\n@testable import {module}\n\n@Suite(\"{base}\")\nstruct {base} {{\n    @Test(\"Placeholder\")\n    func placeholder() {{\n        #expect(Bool(false), \"Replace this failing scaffold with a real assertion.\")\n    }}\n}}\n"
        )),
        _ => Err(failed(format!(
            "Unknown code template {template}; use swift_struct, swift_class, swiftui_view, or test."
        ))),
    }
}

fn yaml_key_colon(text: &str) -> Option<usize> {
    let bytes = text.as_bytes();
    let mut in_single = false;
    let mut in_double = false;
    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];
        if b == b'\'' && !in_double {
            in_single = !in_single;
        } else if b == b'"' && !in_single {
            in_double = !in_double;
        } else if b == b':' && !in_single && !in_double {
            let next = bytes.get(i + 1);
            if next.is_none() || next == Some(&b' ') {
                return Some(i);
            }
        }
        i += 1;
    }
    None
}

fn yaml_issues(text: &str) -> Vec<String> {
    let mut issues = Vec::new();
    let mut top_keys: Vec<(String, usize)> = Vec::new();
    for (index, raw_line) in text.lines().enumerate() {
        let line_number = index + 1;
        if raw_line.contains('\t') {
            issues.push(format!(
                "Line {line_number}: tab character; YAML forbids tabs for indentation."
            ));
        }
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let bytes = raw_line.as_bytes();
        let mut in_single = false;
        let mut in_double = false;
        let mut squares: i64 = 0;
        let mut braces: i64 = 0;
        let mut i = 0;
        while i < bytes.len() {
            let b = bytes[i];
            if b == b'\'' && !in_double {
                in_single = !in_single;
            } else if b == b'"' && !in_single {
                in_double = !in_double;
            } else if !in_single && !in_double {
                match b {
                    b'[' => squares += 1,
                    b']' => squares -= 1,
                    b'{' => braces += 1,
                    b'}' => braces -= 1,
                    b'#' => {
                        let prev = if i == 0 { b' ' } else { bytes[i - 1] };
                        if prev == b' ' || prev == b'\t' {
                            break;
                        }
                    }
                    _ => {}
                }
            }
            i += 1;
        }
        if in_single || in_double {
            issues.push(format!("Line {line_number}: unbalanced quote."));
        }
        if squares != 0 {
            issues.push(format!("Line {line_number}: unbalanced square bracket."));
        }
        if braces != 0 {
            issues.push(format!("Line {line_number}: unbalanced brace."));
        }
        if !raw_line.starts_with(' ') && !raw_line.starts_with('\t') {
            if let Some(colon) = yaml_key_colon(trimmed) {
                let key = trimmed[..colon].trim();
                if !key.is_empty() && !key.contains(' ') {
                    if let Some((_, first)) = top_keys.iter().find(|(k, _)| k == key) {
                        issues.push(format!(
                            "Line {line_number}: duplicate top-level key {key}, first seen on line {first}."
                        ));
                    } else {
                        top_keys.push((key.to_owned(), line_number));
                    }
                }
            }
        }
    }
    issues
}

fn yaml_normalized(text: &str) -> String {
    text.lines()
        .map(|line| {
            let mut out = line.to_owned();
            while out.starts_with('\t') {
                out = format!("  {}", &out[1..]);
            }
            out.trim_end().to_owned()
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn yaml_scalar(text: &str) -> Value {
    let trimmed = text.trim();
    if trimmed.is_empty() || trimmed == "~" || trimmed.eq_ignore_ascii_case("null") {
        return Value::Null;
    }
    if trimmed.eq_ignore_ascii_case("true") {
        return json!(true);
    }
    if trimmed.eq_ignore_ascii_case("false") {
        return json!(false);
    }
    if let Ok(v) = trimmed.parse::<i64>() {
        return json!(v);
    }
    if let Ok(v) = trimmed.parse::<f64>() {
        return json!(v);
    }
    let mut value = trimmed.to_owned();
    if value.len() >= 2
        && ((value.starts_with('"') && value.ends_with('"'))
            || (value.starts_with('\'') && value.ends_with('\'')))
    {
        value = value[1..value.len() - 1].to_owned();
    }
    json!(value)
}

struct YamlLine {
    indent: usize,
    text: String,
}

fn yaml_parse(text: &str) -> Result<Value, String> {
    let mut lines: Vec<YamlLine> = Vec::new();
    for raw in text.lines() {
        let trimmed = raw.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let indent = raw.len() - raw.trim_start_matches(' ').len();
        lines.push(YamlLine {
            indent,
            text: raw[indent..].to_owned(),
        });
    }
    let mut index = 0;
    let value = yaml_parse_block(&lines, &mut index, 0)?;
    if index != lines.len() {
        return Err(
            "YAML has content outside the parsed structure; only mappings, lists, and scalars are supported."
                .to_owned(),
        );
    }
    Ok(value)
}

fn yaml_parse_block(lines: &[YamlLine], index: &mut usize, indent: usize) -> Result<Value, String> {
    if *index >= lines.len() {
        return Ok(Value::Null);
    }
    let line = &lines[*index];
    if line.indent != indent {
        return Ok(Value::Null);
    }
    if line.text == "-" || line.text.starts_with("- ") {
        return yaml_parse_list(lines, index, indent);
    }
    if yaml_key_colon(&line.text).is_some() {
        return yaml_parse_map(lines, index, indent);
    }
    *index += 1;
    Ok(yaml_scalar(&line.text))
}

fn yaml_parse_map(lines: &[YamlLine], index: &mut usize, indent: usize) -> Result<Value, String> {
    let mut object = serde_json::Map::new();
    while *index < lines.len() {
        let line = &lines[*index];
        if line.indent != indent {
            break;
        }
        if line.text == "-" || line.text.starts_with("- ") {
            break;
        }
        let Some(colon) = yaml_key_colon(&line.text) else {
            break;
        };
        let key = line.text[..colon].trim().to_owned();
        if key.is_empty() {
            return Err("YAML mapping key is empty.".to_owned());
        }
        let rest = line.text[colon + 1..].trim().to_owned();
        *index += 1;
        if !rest.is_empty() {
            object.insert(key, yaml_scalar(&rest));
        } else if *index < lines.len() && lines[*index].indent > indent {
            let child_indent = lines[*index].indent;
            let value = yaml_parse_block(lines, index, child_indent)?;
            object.insert(key, value);
        } else {
            object.insert(key, Value::Null);
        }
    }
    Ok(Value::Object(object))
}

fn yaml_parse_list(lines: &[YamlLine], index: &mut usize, indent: usize) -> Result<Value, String> {
    let mut items = Vec::new();
    while *index < lines.len() {
        let line = &lines[*index];
        if line.indent != indent {
            break;
        }
        if !(line.text == "-" || line.text.starts_with("- ")) {
            break;
        }
        let rest = if line.text == "-" {
            String::new()
        } else {
            line.text[2..].to_owned()
        };
        if rest.is_empty() {
            *index += 1;
            if *index < lines.len() && lines[*index].indent > indent {
                let child_indent = lines[*index].indent;
                items.push(yaml_parse_block(lines, index, child_indent)?);
            } else {
                items.push(Value::Null);
            }
        } else if yaml_key_colon(&rest).is_some() {
            let colon = yaml_key_colon(&rest).unwrap();
            let key = rest[..colon].trim().to_owned();
            let value_text = rest[colon + 1..].trim().to_owned();
            *index += 1;
            let mut object = serde_json::Map::new();
            if !value_text.is_empty() {
                object.insert(key, yaml_scalar(&value_text));
            } else if *index < lines.len() && lines[*index].indent > indent {
                let child_indent = lines[*index].indent;
                let value = yaml_parse_block(lines, index, child_indent)?;
                object.insert(key, value);
            } else {
                object.insert(key, Value::Null);
            }
            while *index < lines.len()
                && lines[*index].indent == indent + 2
                && yaml_key_colon(&lines[*index].text).is_some()
            {
                let follow = &lines[*index];
                let follow_colon = yaml_key_colon(&follow.text).unwrap();
                let follow_key = follow.text[..follow_colon].trim().to_owned();
                let follow_rest = follow.text[follow_colon + 1..].trim().to_owned();
                *index += 1;
                if !follow_rest.is_empty() {
                    object.insert(follow_key, yaml_scalar(&follow_rest));
                } else if *index < lines.len() && lines[*index].indent > indent + 2 {
                    let child_indent = lines[*index].indent;
                    let value = yaml_parse_block(lines, index, child_indent)?;
                    object.insert(follow_key, value);
                } else {
                    object.insert(follow_key, Value::Null);
                }
            }
            items.push(Value::Object(object));
        } else {
            items.push(yaml_scalar(&rest));
            *index += 1;
        }
    }
    Ok(Value::Array(items))
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
        "create_artifact" => {
            let cwd = req_str(&args, "cwd", name)?;
            let artifact_name = req_str(&args, "name", name)?;
            let content = req_str(&args, "content", name)?;
            let kind = opt_str(&args, "kind").unwrap_or_else(|| "artifact".to_owned());
            if kind != "artifact" && kind != "execution_plan" {
                return Err(failed("Artifact kind must be artifact or execution_plan."));
            }
            let artifact_path = artifact_path(&artifact_name, name)?;
            let append = opt_bool(&args, "append").unwrap_or(false);
            if append {
                let mut existing = read_text_file_at(&cwd, &artifact_path).unwrap_or_default();
                if !existing.is_empty() && !existing.ends_with('\n') {
                    existing.push('\n');
                }
                existing.push_str(&content);
                write_text_file(&cwd, &artifact_path, &existing)?;
            } else {
                write_text_file(&cwd, &artifact_path, &content)?;
            }
            Ok(json!({"name": artifact_name, "path": artifact_path, "kind": kind, "appended": append}))
        }
        "list_artifacts" => {
            let cwd = req_str(&args, "cwd", name)?;
            let mut entries = read_dir_entries(&cwd, ".assist_temp/artifacts", false).unwrap_or_default();
            entries.retain(|e| e["name"].as_str().map_or(false, |n| n.ends_with(".md")));
            entries.sort_by(|a, b| {
                let ma = a["modifiedAt"].as_f64().unwrap_or(0.0);
                let mb = b["modifiedAt"].as_f64().unwrap_or(0.0);
                mb.partial_cmp(&ma).unwrap_or(std::cmp::Ordering::Equal)
            });
            Ok(json!(entries
                .iter()
                .map(|e| json!({
                    "name": e["name"],
                    "path": e["path"],
                    "sizeBytes": e["sizeBytes"],
                    "modifiedAt": e["modifiedAt"],
                }))
                .collect::<Vec<_>>()))
        }
        "read_artifact" => {
            let cwd = req_str(&args, "cwd", name)?;
            let artifact_name = req_str(&args, "name", name)?;
            let artifact_path = artifact_path(&artifact_name, name)?;
            let content = read_text_file_at(&cwd, &artifact_path)?;
            let total = content.chars().count();
            let truncated = total > 60000;
            let shown = if truncated {
                let mut text: String = content.chars().take(60000).collect();
                text.push_str("\n... (truncated)");
                text
            } else {
                content
            };
            Ok(json!({"name": artifact_name, "path": artifact_path, "content": shown, "truncated": truncated, "totalCharacters": total}))
        }
        "delete_artifact" => {
            let cwd = req_str(&args, "cwd", name)?;
            let artifact_name = req_str(&args, "name", name)?;
            if !opt_bool(&args, "confirm").unwrap_or(false) {
                return Err(failed("Deleting an artifact is permanent; pass confirm=true."));
            }
            if artifact_name == "agent_notes.md" {
                return Err(failed("agent_notes.md is protected and cannot be deleted."));
            }
            let artifact_path = artifact_path(&artifact_name, name)?;
            coincide_core::workspace_tools::delete_file(&json!({"cwd": cwd, "path": artifact_path}))
                .map_err(|error| failed(error.to_string()))?;
            Ok(json!({"name": artifact_name, "path": artifact_path, "deleted": true}))
        }
        "format_json_file" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let text = read_text_file_at(&cwd, &path)?;
            let value: Value = serde_json::from_str(&text)
                .map_err(|error| failed(format!("Invalid JSON: {error}")))?;
            let formatted = serde_json::to_string_pretty(&value)
                .map_err(|error| failed(error.to_string()))?;
            write_text_file(&cwd, &path, &format!("{formatted}\n"))?;
            Ok(json!({"path": path, "valid": true}))
        }
        "csv_to_json" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let output = opt_str(&args, "output").unwrap_or_else(|| {
                Path::new(&path)
                    .with_extension("json")
                    .to_string_lossy()
                    .into_owned()
            });
            let text = read_text_file_at(&cwd, &path)?;
            let rows = parse_csv(&text);
            let Some(headers) = rows.first() else {
                return Err(failed("CSV file has no header row."));
            };
            if headers.is_empty() {
                return Err(failed("CSV file has no header row."));
            }
            let mut records: Vec<Value> = Vec::new();
            for row in rows.iter().skip(1) {
                if row.iter().all(|v| v.is_empty()) {
                    continue;
                }
                let mut record = serde_json::Map::new();
                for (index, header) in headers.iter().enumerate() {
                    let value = row.get(index).cloned().unwrap_or_default();
                    record.insert(header.clone(), json!(value));
                }
                records.push(Value::Object(record));
            }
            let count = records.len();
            let formatted = serde_json::to_string_pretty(&json!(records))
                .map_err(|error| failed(error.to_string()))?;
            write_text_file(&cwd, &output, &format!("{formatted}\n"))?;
            Ok(json!({"path": path, "output": output, "rows": count}))
        }
        "json_to_csv" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let output = opt_str(&args, "output").unwrap_or_else(|| {
                Path::new(&path)
                    .with_extension("csv")
                    .to_string_lossy()
                    .into_owned()
            });
            let text = read_text_file_at(&cwd, &path)?;
            let value: Value = serde_json::from_str(&text)
                .map_err(|error| failed(format!("Invalid JSON: {error}")))?;
            let Some(records) = value.as_array() else {
                return Err(failed("JSON file must contain an array of objects."));
            };
            let mut headers: Vec<String> = Vec::new();
            for record in records {
                if let Some(object) = record.as_object() {
                    for key in object.keys() {
                        if !headers.contains(key) {
                            headers.push(key.clone());
                        }
                    }
                } else {
                    return Err(failed("JSON file must contain an array of objects."));
                }
            }
            headers.sort();
            let mut lines: Vec<String> = vec![headers
                .iter()
                .map(|h| csv_field(h))
                .collect::<Vec<_>>()
                .join(",")];
            for record in records {
                let object = record.as_object().unwrap();
                lines.push(
                    headers
                        .iter()
                        .map(|h| csv_field(&json_scalar_text(object.get(h).unwrap_or(&Value::Null))))
                        .collect::<Vec<_>>()
                        .join(","),
                );
            }
            let count = records.len();
            write_text_file(&cwd, &output, &format!("{}\n", lines.join("\n")))?;
            Ok(json!({"path": path, "output": output, "rows": count}))
        }
        "plist_to_json" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let output = opt_str(&args, "output").unwrap_or_else(|| {
                Path::new(&path)
                    .with_extension("json")
                    .to_string_lossy()
                    .into_owned()
            });
            run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "plutil -convert json -o {} {}",
                    shell_quote(&output),
                    shell_quote(&path)
                ),
                60,
            )?;
            Ok(json!({"path": path, "output": output}))
        }
        "json_to_plist" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let output = opt_str(&args, "output").unwrap_or_else(|| {
                Path::new(&path)
                    .with_extension("plist")
                    .to_string_lossy()
                    .into_owned()
            });
            let format = opt_str(&args, "format").unwrap_or_else(|| "xml".to_owned());
            if format != "xml" && format != "binary" {
                return Err(failed("Plist format must be xml or binary."));
            }
            let target = if format == "binary" { "binary1" } else { "xml1" };
            run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "plutil -convert {target} -o {} {}",
                    shell_quote(&output),
                    shell_quote(&path)
                ),
                60,
            )?;
            Ok(json!({"path": path, "output": output, "format": format}))
        }
        "json_validate" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let text = read_text_file_at(&cwd, &path)?;
            let value: Value = match serde_json::from_str(&text) {
                Ok(value) => value,
                Err(error) => {
                    return Ok(json!({"path": path, "valid": false, "error": format!("Invalid JSON: {error}"), "wrote": false}));
                }
            };
            let write = opt_bool(&args, "write").unwrap_or(false);
            if write {
                let formatted = serde_json::to_string_pretty(&value)
                    .map_err(|error| failed(error.to_string()))?;
                write_text_file(&cwd, &path, &format!("{formatted}\n"))?;
            }
            Ok(json!({"path": path, "valid": true, "wrote": write}))
        }
        "json_validator_tool" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let text = read_text_file_at(&cwd, &path)?;
            match serde_json::from_str::<Value>(&text) {
                Ok(value) => {
                    let formatted = serde_json::to_string_pretty(&value)
                        .map_err(|error| failed(error.to_string()))?;
                    Ok(json!({"path": path, "valid": true, "formatted": formatted}))
                }
                Err(error) => Ok(json!({"path": path, "valid": false, "error": format!("Invalid JSON: {error}"),})),
            }
        }
        "yaml_validate" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let text = read_text_file_at(&cwd, &path)?;
            let issues = yaml_issues(&text);
            let write = opt_bool(&args, "write").unwrap_or(false);
            let mut wrote = false;
            if write && issues.is_empty() {
                write_text_file(&cwd, &path, &yaml_normalized(&text))?;
                wrote = true;
            }
            Ok(json!({"path": path, "valid": issues.is_empty(), "issues": issues, "wrote": wrote}))
        }
        "yaml_parser_tool" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let text = read_text_file_at(&cwd, &path)?;
            let issues = yaml_issues(&text);
            if !issues.is_empty() {
                return Ok(json!({"path": path, "valid": false, "issues": issues}));
            }
            match yaml_parse(&text) {
                Ok(value) => Ok(json!({"path": path, "valid": true, "value": value})),
                Err(error) => Ok(json!({"path": path, "valid": false, "error": error})),
            }
        }
        "plist_edit" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let action = req_str(&args, "action", name)?;
            let key = req_str(&args, "key", name)?;
            match action.as_str() {
                "get" => {
                    let (exit_code, output) = run_shell_status(
                        state,
                        &thread_id,
                        &cwd,
                        &format!(
                            "plutil -extract {} json -o - {}",
                            shell_quote(&key),
                            shell_quote(&path)
                        ),
                        60,
                    )?;
                    if exit_code != 0 {
                        return Ok(json!({"path": path, "key": key, "found": false, "value": Value::Null}));
                    }
                    let value: Value = serde_json::from_str(&output)
                        .map_err(|error| failed(format!("Invalid plist value JSON: {error}")))?;
                    Ok(json!({"path": path, "key": key, "found": true, "value": value}))
                }
                "set" => {
                    let value = req_str(&args, "value", name)?;
                    run_shell(
                        state,
                        &thread_id,
                        &cwd,
                        &format!(
                            "plutil -replace {} -string {} {} || plutil -insert {} -string {} {}",
                            shell_quote(&key),
                            shell_quote(&value),
                            shell_quote(&path),
                            shell_quote(&key),
                            shell_quote(&value),
                            shell_quote(&path)
                        ),
                        60,
                    )?;
                    run_shell(
                        state,
                        &thread_id,
                        &cwd,
                        &format!("plutil -lint {}", shell_quote(&path)),
                        60,
                    )?;
                    Ok(json!({"path": path, "key": key, "value": value}))
                }
                "delete" => {
                    run_shell(
                        state,
                        &thread_id,
                        &cwd,
                        &format!(
                            "plutil -remove {} {}",
                            shell_quote(&key),
                            shell_quote(&path)
                        ),
                        60,
                    )?;
                    run_shell(
                        state,
                        &thread_id,
                        &cwd,
                        &format!("plutil -lint {}", shell_quote(&path)),
                        60,
                    )?;
                    Ok(json!({"path": path, "key": key, "deleted": true}))
                }
                _ => Err(failed("plist_edit action must be get, set, or delete.")),
            }
        }
        "plist_editor" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let action = opt_str(&args, "action").unwrap_or_else(|| "read".to_owned());
            match action.as_str() {
                "read" => {
                    let output = run_shell(
                        state,
                        &thread_id,
                        &cwd,
                        &format!("plutil -convert json -o - {}", shell_quote(&path)),
                        60,
                    )?;
                    let value: Value = serde_json::from_str(&output)
                        .map_err(|error| failed(format!("Invalid plist JSON: {error}")))?;
                    Ok(json!({"path": path, "value": value}))
                }
                "get" => {
                    let key = req_str(&args, "key", name)?;
                    let (exit_code, output) = run_shell_status(
                        state,
                        &thread_id,
                        &cwd,
                        &format!(
                            "plutil -extract {} json -o - {}",
                            shell_quote(&key),
                            shell_quote(&path)
                        ),
                        60,
                    )?;
                    if exit_code != 0 {
                        return Ok(json!({"path": path, "key": key, "found": false, "value": Value::Null}));
                    }
                    let value: Value = serde_json::from_str(&output)
                        .map_err(|error| failed(format!("Invalid plist value JSON: {error}")))?;
                    Ok(json!({"path": path, "key": key, "found": true, "value": value}))
                }
                "set" => {
                    let key = req_str(&args, "key", name)?;
                    let value = req_str(&args, "value", name)?;
                    run_shell(
                        state,
                        &thread_id,
                        &cwd,
                        &format!(
                            "plutil -replace {} -string {} {} || plutil -insert {} -string {} {}",
                            shell_quote(&key),
                            shell_quote(&value),
                            shell_quote(&path),
                            shell_quote(&key),
                            shell_quote(&value),
                            shell_quote(&path)
                        ),
                        60,
                    )?;
                    run_shell(
                        state,
                        &thread_id,
                        &cwd,
                        &format!("plutil -lint {}", shell_quote(&path)),
                        60,
                    )?;
                    Ok(json!({"path": path, "key": key, "value": value}))
                }
                "delete" => {
                    let key = req_str(&args, "key", name)?;
                    run_shell(
                        state,
                        &thread_id,
                        &cwd,
                        &format!(
                            "plutil -remove {} {}",
                            shell_quote(&key),
                            shell_quote(&path)
                        ),
                        60,
                    )?;
                    run_shell(
                        state,
                        &thread_id,
                        &cwd,
                        &format!("plutil -lint {}", shell_quote(&path)),
                        60,
                    )?;
                    Ok(json!({"path": path, "key": key, "deleted": true}))
                }
                _ => Err(failed("plist_editor action must be read, get, set, or delete.")),
            }
        }
        "binary_plist_converter" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let format = req_str(&args, "format", name)?;
            if format != "xml" && format != "binary" {
                return Err(failed("Plist format must be xml or binary."));
            }
            let output = opt_str(&args, "output").unwrap_or_else(|| path.clone());
            let target = if format == "binary" { "binary1" } else { "xml1" };
            run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "plutil -convert {target} -o {} {}",
                    shell_quote(&output),
                    shell_quote(&path)
                ),
                60,
            )?;
            let bytes = read_workspace_bytes(&cwd, &output)?;
            let is_binary = bytes.starts_with(b"bplist00");
            let is_xml = bytes.starts_with(b"<?xml");
            if (format == "binary" && !is_binary) || (format == "xml" && !is_xml) {
                return Err(failed(format!(
                    "Property list conversion verification failed: the output is not {format}."
                )));
            }
            Ok(json!({"path": path, "output": output, "format": format, "converted": true}))
        }
        "file_metadata" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let parent = Path::new(&path)
                .parent()
                .map(|p| p.to_string_lossy().into_owned())
                .unwrap_or_default();
            let file_name = Path::new(&path)
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            let entries = read_dir_entries(&cwd, &parent, false)?;
            let Some(entry) = entries
                .iter()
                .find(|e| e["name"].as_str() == Some(file_name.as_str()))
            else {
                return Err(failed(format!("No such file or directory: {path}.")));
            };
            Ok(json!({
                "path": path,
                "name": entry["name"],
                "isDirectory": entry["isDirectory"],
                "sizeBytes": entry["sizeBytes"],
                "modifiedAt": entry["modifiedAt"],
                "isSymlink": entry["isSymlink"],
                "symlinkTarget": entry["symlinkTarget"],
                "isExecutable": entry["isExecutable"],
            }))
        }
        "file_hash_verify" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let expected = req_str(&args, "expectedHash", name)?;
            let algorithm = opt_str(&args, "algorithm").unwrap_or_else(|| "sha256".to_owned());
            let hash = shasum_hex(state, &thread_id, &cwd, &path, &algorithm)?;
            Ok(json!({"path": path, "algorithm": algorithm, "hash": hash, "expectedHash": expected.to_lowercase(), "match": hash == expected.to_lowercase()}))
        }
        "generate_file_checksum" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let output = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "shasum -a 256 {}; shasum -a 512 {}; shasum -a 1 {}; md5 -q {}",
                    shell_quote(&path),
                    shell_quote(&path),
                    shell_quote(&path),
                    shell_quote(&path)
                ),
                120,
            )?;
            let sha256 = parse_hex_line(&output, 64)
                .ok_or_else(|| failed(format!("Could not parse sha256 output: {output}")))?;
            let sha512 = parse_hex_line(&output, 128)
                .ok_or_else(|| failed(format!("Could not parse sha512 output: {output}")))?;
            let sha1 = parse_hex_line(&output, 40)
                .ok_or_else(|| failed(format!("Could not parse sha1 output: {output}")))?;
            let md5 = parse_hex_line(&output, 32)
                .ok_or_else(|| failed(format!("Could not parse md5 output: {output}")))?;
            Ok(json!({"path": path, "sha256": sha256, "sha512": sha512, "sha1": sha1, "md5": md5}))
        }
        "file_checksum_verifier" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let algorithm = opt_str(&args, "algorithm").unwrap_or_else(|| "sha256".to_owned());
            if algorithm != "sha256" && algorithm != "md5" {
                return Err(failed("file_checksum_verifier algorithm must be sha256 or md5."));
            }
            let output = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "shasum -a 256 {}; md5 -q {}",
                    shell_quote(&path),
                    shell_quote(&path)
                ),
                120,
            )?;
            let sha256 = parse_hex_line(&output, 64)
                .ok_or_else(|| failed(format!("Could not parse sha256 output: {output}")))?;
            let md5 = parse_hex_line(&output, 32)
                .ok_or_else(|| failed(format!("Could not parse md5 output: {output}")))?;
            let verified = match opt_str(&args, "expectedHash") {
                Some(expected) => {
                    let actual = if algorithm == "md5" { &md5 } else { &sha256 };
                    json!(actual == &expected.to_lowercase())
                }
                None => Value::Null,
            };
            Ok(json!({"path": path, "sha256": sha256, "md5": md5, "algorithm": algorithm, "verified": verified}))
        }
        "file_compare_diff" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let other = req_str(&args, "otherPath", name)?;
            let output = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "diff -u {} {} || test $? -eq 1",
                    shell_quote(&path),
                    shell_quote(&other)
                ),
                60,
            )?;
            let mut added = 0;
            let mut removed = 0;
            for line in output.lines() {
                if line.starts_with('+') && !line.starts_with("+++") {
                    added += 1;
                } else if line.starts_with('-') && !line.starts_with("---") {
                    removed += 1;
                }
            }
            Ok(json!({"path": path, "otherPath": other, "identical": added == 0 && removed == 0, "added": added, "removed": removed, "diff": output}))
        }
        "file_head_preview" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let lines = opt_u64(&args, "lines").unwrap_or(20).clamp(1, 5000);
            let value = coincide_core::workspace_tools::read_file(&json!({
                "cwd": cwd,
                "path": path,
                "lineOffset": 0,
                "lineLimit": lines,
            }))
            .map_err(|error| failed(error.to_string()))?;
            Ok(json!({
                "path": path,
                "content": value["content"],
                "lineOffset": 0,
                "totalLines": value["totalLines"],
                "truncated": value["truncated"],
            }))
        }
        "code_generate" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let template = req_str(&args, "template", name)?;
            let module = opt_str(&args, "module").unwrap_or_else(|| {
                Path::new(&cwd)
                    .file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .unwrap_or_default()
            });
            if workspace_file_exists(&cwd, &path)? {
                return Err(failed("A file already exists at that path; use write_file to overwrite it."));
            }
            let file_name = Path::new(&path)
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            let content = code_template(&template, &module, &file_name, name)?;
            write_text_file(&cwd, &path, &content)?;
            Ok(json!({"path": path, "template": template}))
        }
        "code_format" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = opt_str(&args, "path").unwrap_or_default();
            let extensions = ["swift", "c", "h", "m", "mm", "js", "ts", "tsx", "jsx", "py"];
            let mut targets: Vec<String> = Vec::new();
            if path.is_empty() {
                let entries = read_dir_entries(&cwd, "", true)?;
                targets = entries
                    .iter()
                    .filter(|e| {
                        e["isDirectory"] != true
                            && e["path"]
                                .as_str()
                                .map(|p| {
                                    Path::new(p)
                                        .extension()
                                        .map(|x| extensions.contains(&x.to_string_lossy().to_lowercase().as_str()))
                                        .unwrap_or(false)
                                })
                                .unwrap_or(false)
                    })
                    .filter_map(|e| e["path"].as_str().map(str::to_owned))
                    .collect();
            } else if let Ok(entries) = read_dir_entries(&cwd, &path, true) {
                if entries.is_empty() {
                    targets = vec![path.clone()];
                } else {
                    targets = entries
                        .iter()
                        .filter(|e| {
                            e["isDirectory"] != true
                                && e["path"]
                                    .as_str()
                                    .map(|p| {
                                        Path::new(p)
                                            .extension()
                                            .map(|x| extensions.contains(&x.to_string_lossy().to_lowercase().as_str()))
                                            .unwrap_or(false)
                                    })
                                    .unwrap_or(false)
                        })
                        .filter_map(|e| e["path"].as_str().map(str::to_owned))
                        .collect();
                }
            } else {
                targets = vec![path.clone()];
            }
            let mut formatted: Vec<String> = Vec::new();
            let mut skipped = 0;
            for target in targets {
                let Ok(document) = read_text_file_at(&cwd, &target) else {
                    skipped += 1;
                    continue;
                };
                let normalized = normalized_text(&document);
                if normalized != document {
                    write_text_file(&cwd, &target, &normalized)?;
                    formatted.push(target);
                }
            }
            let count = formatted.len();
            Ok(json!({"path": path, "formattedFiles": formatted, "formatted": count, "skipped": skipped}))
        }
        "swift_format_lint" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let mode = opt_str(&args, "mode").unwrap_or_else(|| "lint".to_owned());
            if mode != "lint" && mode != "format" {
                return Err(failed("swift_format_lint mode must be lint or format."));
            }
            validate_relative_path(&path)?;
            let command = if mode == "lint" {
                format!("swiftformat --lint {}", shell_quote(&path))
            } else {
                format!("swiftformat {}", shell_quote(&path))
            };
            let (exit_code, output) = run_shell_status(state, &thread_id, &cwd, &command, 300)?;
            if exit_code == 127 || output.contains("command not found") {
                return Err(failed("swiftformat is not installed; install it to use swift_format_lint."));
            }
            if mode == "lint" {
                return Ok(json!({"path": path, "mode": mode, "lintPassed": exit_code == 0, "exitCode": exit_code, "output": output}));
            }
            if exit_code != 0 {
                return Err(failed(format!(
                    "swiftformat failed with exit code {exit_code}: {output}"
                )));
            }
            Ok(json!({"path": path, "mode": mode, "formatted": true, "exitCode": exit_code, "output": output}))
        }
        "code_mutation_engine" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let replacement = req_str(&args, "replacement", name)?;
            let symbol = opt_str(&args, "symbol");
            let target = opt_str(&args, "target");
            if symbol.is_none() && target.is_none() {
                return Err(failed("code_mutation_engine requires symbol or target."));
            }
            let content = read_text_file_at(&cwd, &path)?;
            if let Some(target) = target {
                if !content.contains(&target) {
                    return Err(failed("Target block was not found in the file."));
                }
                let updated = content.replace(&target, &replacement);
                write_text_file(&cwd, &path, &updated)?;
                return Ok(json!({"path": path, "mutated": true}));
            }
            let symbol = symbol.unwrap();
            let lines: Vec<&str> = content.lines().collect();
            let Some(start) = symbol_declaration_line(&lines, &symbol) else {
                return Err(failed(format!("Symbol was not found in the file: {symbol}.")));
            };
            let Some(end) = brace_block_end(&lines, start) else {
                return Err(failed(format!("Symbol has no brace-balanced body: {symbol}.")));
            };
            let mut updated_lines: Vec<String> = lines.iter().map(|l| l.to_string()).collect();
            let replacement_lines: Vec<String> =
                replacement.lines().map(str::to_owned).collect();
            let mut open_line = start;
            while open_line <= end && !updated_lines[open_line].contains('{') {
                open_line += 1;
            }
            if open_line > end {
                return Err(failed(format!("Symbol has no brace-balanced body: {symbol}.")));
            }
            if open_line == end {
                updated_lines.splice(open_line..=open_line, replacement_lines);
            } else {
                updated_lines.splice(open_line + 1..end, replacement_lines);
            }
            write_text_file(&cwd, &path, &updated_lines.join("\n"))?;
            Ok(json!({"path": path, "symbol": symbol, "mutated": true}))
        }
        "patch_application_engine" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let original = req_str(&args, "original", name)?;
            let updated = req_str(&args, "updated", name)?;
            let content = read_text_file_at(&cwd, &path)?;
            let occurrences = content.matches(&original).count();
            if occurrences == 0 {
                return Err(failed("Original block was not found in the file."));
            }
            let patched = content.replace(&original, &updated);
            write_text_file(&cwd, &path, &patched)?;
            Ok(json!({"path": path, "patched": true, "occurrences": occurrences}))
        }
        "automated_repair_engine" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let Some(raw_errors) = args.get("errors").and_then(Value::as_array) else {
                return Err(failed(format!(
                    "Tool \"{name}\" is missing required argument \"errors\"."
                )));
            };
            if raw_errors.is_empty() {
                return Err(failed(format!(
                    "Tool \"{name}\" is missing required argument \"errors\"."
                )));
            }
            let mut line_numbers: Vec<usize> = Vec::new();
            for raw in raw_errors {
                let Some(n) = raw.as_u64() else {
                    return Err(failed("automated_repair_engine errors must be line numbers."));
                };
                line_numbers.push(n as usize);
            }
            let content = read_text_file_at(&cwd, &path)?;
            let mut lines: Vec<String> = content.lines().map(str::to_owned).collect();
            let mut sorted = line_numbers.clone();
            sorted.sort_by(|a, b| b.cmp(a));
            for line_number in &sorted {
                if *line_number < 1 || *line_number > lines.len() {
                    return Err(failed(format!(
                        "automated_repair_engine line {line_number} is out of range for the file."
                    )));
                }
                lines.insert(*line_number - 1, "// AssistAutoRepair: review required".to_owned());
            }
            write_text_file(&cwd, &path, &lines.join("\n"))?;
            Ok(json!({"path": path, "annotated": line_numbers.len(), "lines": line_numbers}))
        }
        "regex_replace_in_files" => {
            let cwd = req_str(&args, "cwd", name)?;
            let pattern = req_str(&args, "pattern", name)?;
            let replacement = req_str(&args, "replacement", name)?;
            let query = opt_str(&args, "query");
            let regex = regex::Regex::new(&pattern)
                .map_err(|error| failed(format!("Invalid regular expression: {error}")))?;
            let mut params = args.clone();
            if let Some(object) = params.as_object_mut() {
                object.insert("pattern".to_owned(), json!(pattern));
                object.insert("limit".to_owned(), json!(500));
            }
            let value = coincide_core::workspace_tools::search_regex(&params)
                .map_err(|error| failed(error.to_string()))?;
            let mut files: Vec<String> = Vec::new();
            for hit in value["matches"].as_array().cloned().unwrap_or_default() {
                let Some(path) = hit["path"].as_str() else {
                    continue;
                };
                if let Some(query) = &query {
                    if !path.contains(query.as_str()) {
                        continue;
                    }
                }
                if !files.iter().any(|f| f == path) {
                    files.push(path.to_owned());
                }
            }
            let mut changed: Vec<String> = Vec::new();
            let mut total = 0;
            for file in files {
                let content = read_text_file_at(&cwd, &file)?;
                let count = regex.find_iter(&content).count();
                if count == 0 {
                    continue;
                }
                let updated = regex.replace_all(&content, replacement.as_str()).into_owned();
                write_text_file(&cwd, &file, &updated)?;
                changed.push(file);
                total += count;
            }
            let count = changed.len();
            Ok(json!({"filesChanged": changed, "changed": count, "replacements": total}))
        }
        "symbol_rename_project" => {
            let cwd = req_str(&args, "cwd", name)?;
            let old_name = req_str(&args, "oldName", name)?;
            let new_name = req_str(&args, "newName", name)?;
            let directory = opt_str(&args, "path").unwrap_or_default();
            let entries = read_dir_entries(&cwd, &directory, true)?;
            let mut changed: Vec<String> = Vec::new();
            let mut total = 0;
            for entry in entries {
                if entry["isDirectory"] == true {
                    continue;
                }
                let Some(path) = entry["path"].as_str() else {
                    continue;
                };
                if Path::new(path).extension().map_or(false, |x| x != "swift") {
                    continue;
                }
                let Ok(content) = read_text_file_at(&cwd, path) else {
                    continue;
                };
                let (updated, count) = whole_word_replace(&content, &old_name, &new_name);
                if count == 0 {
                    continue;
                }
                write_text_file(&cwd, path, &updated)?;
                changed.push(path.to_owned());
                total += count;
            }
            let count = changed.len();
            Ok(json!({"oldName": old_name, "newName": new_name, "filesChanged": changed, "changed": count, "replacements": total}))
        }
        "symbol_move_file" => {
            let cwd = req_str(&args, "cwd", name)?;
            let source_path = req_str(&args, "sourcePath", name)?;
            let destination_path = req_str(&args, "destinationPath", name)?;
            let symbol = req_str(&args, "symbol", name)?;
            let source = read_text_file_at(&cwd, &source_path)?;
            let destination = read_text_file_at(&cwd, &destination_path)?;
            let source_lines: Vec<&str> = source.lines().collect();
            let Some(start) = symbol_declaration_line(&source_lines, &symbol) else {
                return Err(failed(format!("Symbol was not found in the source file: {symbol}.")));
            };
            let Some(end) = brace_block_end(&source_lines, start) else {
                return Err(failed(format!("Symbol has no brace-balanced body: {symbol}.")));
            };
            let block: Vec<&str> = source_lines[start..=end].to_vec();
            let block_len = block.len();
            let mut remaining: Vec<&str> = source_lines.clone();
            remaining.drain(start..=end);
            let mut destination_content = destination;
            if !destination_content.is_empty() && !destination_content.ends_with('\n') {
                destination_content.push('\n');
            }
            destination_content.push_str(&block.join("\n"));
            destination_content.push('\n');
            write_text_file(&cwd, &source_path, &remaining.join("\n"))?;
            if let Err(error) = write_text_file(&cwd, &destination_path, &destination_content) {
                let _ = write_text_file(&cwd, &source_path, &source);
                return Err(error);
            }
            let verified_source = read_text_file_at(&cwd, &source_path)?;
            let verified_destination = read_text_file_at(&cwd, &destination_path)?;
            let source_lines: Vec<&str> = verified_source.lines().collect();
            let destination_lines: Vec<&str> = verified_destination.lines().collect();
            if symbol_declaration_line(&source_lines, &symbol).is_some()
                || symbol_declaration_line(&destination_lines, &symbol).is_none()
            {
                return Err(failed("Symbol move verification failed."));
            }
            Ok(json!({"sourcePath": source_path, "destinationPath": destination_path, "symbol": symbol, "moved": true, "lines": block_len}))
        }
        "import_cleanup" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let protected = [
                "Foundation", "SwiftUI", "AppKit", "UIKit", "Combine", "CoreData", "CryptoKit",
                "Security", "XCTest", "SwiftData", "Observation", "WebKit",
                "UniformTypeIdentifiers", "Dispatch", "Network", "os", "SystemConfiguration",
                "CoreGraphics", "QuartzCore", "StoreKit", "AuthenticationServices",
            ];
            let content = read_text_file_at(&cwd, &path)?;
            let lines: Vec<&str> = content.lines().collect();
            let mut removed: Vec<String> = Vec::new();
            for (line_index, line) in lines.iter().enumerate() {
                let trimmed = line.trim_start();
                let Some(rest) = trimmed.strip_prefix("import ") else {
                    continue;
                };
                let module: String = rest
                    .chars()
                    .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                    .collect();
                if module.is_empty() || protected.contains(&module.as_str()) {
                    continue;
                }
                let mut body = String::new();
                for (other_index, other) in lines.iter().enumerate() {
                    if other_index != line_index {
                        body.push_str(other);
                        body.push('\n');
                    }
                }
                let mut used = false;
                let mut rest = body.as_str();
                while let Some(at) = rest.find(&module) {
                    let before_ok = at == 0
                        || !is_word_char(rest[..at].chars().last().unwrap());
                    let after = &rest[at + module.len()..];
                    let after_ok = after.chars().next().map_or(true, |c| !is_word_char(c));
                    if before_ok && after_ok {
                        used = true;
                        break;
                    }
                    rest = after;
                }
                if !used {
                    removed.push(module);
                }
            }
            if removed.is_empty() {
                return Ok(json!({"path": path, "removed": [], "count": 0}));
            }
            let updated: Vec<&str> = lines
                .iter()
                .filter(|line| {
                    let trimmed = line.trim_start();
                    let Some(rest) = trimmed.strip_prefix("import ") else {
                        return true;
                    };
                    let module: String = rest
                        .chars()
                        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                        .collect();
                    !removed.contains(&module)
                })
                .copied()
                .collect();
            let count = removed.len();
            write_text_file(&cwd, &path, &updated.join("\n"))?;
            Ok(json!({"path": path, "removed": removed, "count": count}))
        }
        "batch_rename_files" => {
            let cwd = req_str(&args, "cwd", name)?;
            let directory = opt_str(&args, "directory").unwrap_or_default();
            let pattern = req_str(&args, "pattern", name)?;
            let replacement = req_str(&args, "replacement", name)?;
            let dry_run = opt_bool(&args, "dryRun").unwrap_or(false);
            let entries = read_dir_entries(&cwd, &directory, false)?;
            let mut planned: Vec<(String, String)> = Vec::new();
            for entry in entries {
                if entry["isDirectory"] == true {
                    continue;
                }
                let Some(entry_name) = entry["name"].as_str() else {
                    continue;
                };
                if !entry_name.contains(&pattern) {
                    continue;
                }
                let new_name = entry_name.replace(&pattern, &replacement);
                if new_name == entry_name || new_name.is_empty() || new_name.contains('/') {
                    continue;
                }
                let from = if directory.is_empty() {
                    entry_name.to_owned()
                } else {
                    format!("{directory}/{entry_name}")
                };
                let to = if directory.is_empty() {
                    new_name
                } else {
                    format!("{directory}/{new_name}")
                };
                planned.push((from, to));
            }
            if dry_run {
                let renames: Vec<Value> = planned
                    .iter()
                    .map(|(from, to)| json!({"from": from, "to": to}))
                    .collect();
                let count = renames.len();
                return Ok(json!({"dryRun": true, "renames": renames, "count": count}));
            }
            let mut renamed: Vec<Value> = Vec::new();
            for (from, to) in &planned {
                coincide_core::workspace_tools::move_file(
                    &json!({"cwd": cwd, "path": from, "destination": to}),
                )
                .map_err(|error| failed(error.to_string()))?;
                renamed.push(json!({"from": from, "to": to}));
            }
            let count = renamed.len();
            Ok(json!({"dryRun": false, "renames": renamed, "count": count}))
        }
        "file_backup" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let data = read_workspace_bytes(&cwd, &path)?;
            let stamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let base = Path::new(&path)
                .file_stem()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| "file".to_owned());
            let backup_path = format!(".assist_temp/backups/{base}.{stamp}.bak");
            write_workspace_bytes(&cwd, &backup_path, &data)?;
            let verified = read_workspace_bytes(&cwd, &backup_path)?;
            if verified.len() != data.len() {
                return Err(failed("Backup verification failed: size mismatch."));
            }
            Ok(json!({"path": path, "backupPath": backup_path, "byteLen": data.len()}))
        }
        "session_export" => {
            let cwd = req_str(&args, "cwd", name)?;
            let title = req_str(&args, "title", name)?;
            let session_id = opt_str(&args, "sessionId").unwrap_or_else(|| {
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| format!("session-{}", d.as_secs()))
                    .unwrap_or_else(|_| "session".to_owned())
            });
            let notes = opt_str(&args, "notes").unwrap_or_default();
            let path = opt_str(&args, "path")
                .unwrap_or_else(|| format!(".assist_temp/session-export-{session_id}.md"));
            let overwrite = opt_bool(&args, "overwrite").unwrap_or(false);
            if !overwrite && workspace_file_exists(&cwd, &path)? {
                return Err(failed("A file already exists at that path; use write_file to overwrite it."));
            }
            let stamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let mut lines = vec![
                format!("# {title}"),
                String::new(),
                format!("- Session: {session_id}"),
                format!("- Exported: {stamp}"),
                format!("- Workspace: {cwd}"),
                String::new(),
            ];
            if !notes.is_empty() {
                lines.push("## Notes".to_owned());
                lines.push(String::new());
                lines.push(notes);
                lines.push(String::new());
            }
            write_text_file(&cwd, &path, &lines.join("\n"))?;
            Ok(json!({"path": path, "sessionId": session_id}))
        }
        "markdown_toc_generate" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let content = read_text_file_at(&cwd, &path)?;
            let mut toc: Vec<String> = Vec::new();
            for line in content.lines() {
                let mut hashes = 0;
                for c in line.chars() {
                    if c == '#' {
                        hashes += 1;
                    } else {
                        break;
                    }
                }
                if hashes == 0 || hashes > 6 {
                    continue;
                }
                let Some(rest) = line[hashes..].strip_prefix(' ') else {
                    continue;
                };
                let text = rest.trim();
                if text.is_empty() {
                    continue;
                }
                let indent = "  ".repeat(hashes - 1);
                toc.push(format!("{indent}- [{}](#{})", text, toc_slug(text)));
            }
            if toc.is_empty() {
                return Err(failed("No headings found in the file."));
            }
            let mut updated: Vec<String> = content.lines().map(str::to_owned).collect();
            let open = updated.iter().position(|l| l == "<!-- TOC -->");
            let close = updated.iter().position(|l| l == "<!-- /TOC -->");
            if let (Some(open), Some(close)) = (open, close) {
                if close > open {
                    updated.splice(open + 1..close, toc.clone());
                }
            } else if let Some(first) = updated.iter().position(|l| l.starts_with("# ")) {
                let mut insert: Vec<String> =
                    vec![String::new(), "<!-- TOC -->".to_owned()];
                insert.extend(toc.iter().cloned());
                insert.push("<!-- /TOC -->".to_owned());
                updated.splice(first + 1..first + 1, insert);
            } else {
                let mut insert: Vec<String> = vec!["<!-- TOC -->".to_owned()];
                insert.extend(toc.iter().cloned());
                insert.push("<!-- /TOC -->".to_owned());
                insert.push(String::new());
                updated.splice(0..0, insert);
            }
            let count = toc.len();
            write_text_file(&cwd, &path, &updated.join("\n"))?;
            Ok(json!({"path": path, "entries": count}))
        }
        "readme_generate" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = opt_str(&args, "path").unwrap_or_else(|| "README.md".to_owned());
            let overwrite = opt_bool(&args, "overwrite").unwrap_or(false);
            if !overwrite && workspace_file_exists(&cwd, &path)? {
                return Err(failed("A file already exists at that path; use write_file to overwrite it."));
            }
            let project = Path::new(&cwd)
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            let mut entries = read_dir_entries(&cwd, "", false)?;
            entries.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
            let mut lines = vec![
                format!("# {project}"),
                String::new(),
                "Generated README skeleton from the repository contents.".to_owned(),
                String::new(),
                "## Contents".to_owned(),
                String::new(),
            ];
            for entry in &entries {
                let Some(entry_name) = entry["name"].as_str() else {
                    continue;
                };
                if entry["isDirectory"] == true {
                    lines.push(format!("- {entry_name}/"));
                } else {
                    lines.push(format!("- {entry_name}"));
                }
            }
            lines.push(String::new());
            lines.push("## Getting Started".to_owned());
            lines.push(String::new());
            lines.push("Open this project and follow the project build instructions.".to_owned());
            lines.push(String::new());
            let count = entries.len();
            write_text_file(&cwd, &path, &lines.join("\n"))?;
            Ok(json!({"path": path, "entries": count}))
        }
        "docs_generate" => {
            let cwd = req_str(&args, "cwd", name)?;
            let source = opt_str(&args, "path").unwrap_or_default();
            let output = opt_str(&args, "output").unwrap_or_else(|| "API.md".to_owned());
            let overwrite = opt_bool(&args, "overwrite").unwrap_or(false);
            if !overwrite && workspace_file_exists(&cwd, &output)? {
                return Err(failed("A file already exists at that path; use write_file to overwrite it."));
            }
            let mut sources: Vec<String> = Vec::new();
            if source.is_empty() {
                let entries = read_dir_entries(&cwd, "", true)?;
                sources = entries
                    .iter()
                    .filter(|e| {
                        e["isDirectory"] != true
                            && e["path"]
                                .as_str()
                                .map(|p| Path::new(p).extension().map_or(false, |x| x == "swift"))
                                .unwrap_or(false)
                    })
                    .filter_map(|e| e["path"].as_str().map(str::to_owned))
                    .collect();
            } else if let Ok(entries) = read_dir_entries(&cwd, &source, true) {
                if entries.is_empty() {
                    sources = vec![source.clone()];
                } else {
                    sources = entries
                        .iter()
                        .filter(|e| {
                            e["isDirectory"] != true
                                && e["path"]
                                    .as_str()
                                    .map(|p| Path::new(p).extension().map_or(false, |x| x == "swift"))
                                    .unwrap_or(false)
                        })
                        .filter_map(|e| e["path"].as_str().map(str::to_owned))
                        .collect();
                }
            } else {
                sources = vec![source.clone()];
            }
            sources.sort();
            let mut lines = vec!["# API Documentation".to_owned(), String::new()];
            let mut total = 0;
            for file in &sources {
                let Ok(document) = read_text_file_at(&cwd, file) else {
                    continue;
                };
                let symbols = extract_symbols(&document, file);
                total += symbols.len();
                lines.push(format!("## {file}"));
                lines.push(String::new());
                if symbols.is_empty() {
                    lines.push("No public declarations found.".to_owned());
                } else {
                    for symbol in &symbols {
                        let kind = symbol["kind"].as_str().unwrap_or("");
                        let symbol_name = symbol["name"].as_str().unwrap_or("");
                        let line_number = symbol["line"].as_u64().unwrap_or(0);
                        lines.push(format!("- `{kind} {symbol_name}` (line {line_number})"));
                    }
                }
                lines.push(String::new());
            }
            let file_count = sources.len();
            write_text_file(&cwd, &output, &lines.join("\n"))?;
            Ok(json!({"output": output, "files": file_count, "symbols": total}))
        }
        "test_data_factory" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let format = req_str(&args, "format", name)?;
            let fields_text = req_str(&args, "fields", name)?;
            let overwrite = opt_bool(&args, "overwrite").unwrap_or(false);
            if format != "json" && format != "swift" {
                return Err(failed("test_data_factory format must be json or swift."));
            }
            if !overwrite && workspace_file_exists(&cwd, &path)? {
                return Err(failed("A file already exists at that path; use write_file to overwrite it."));
            }
            let mut fields: Vec<(String, String)> = Vec::new();
            for part in fields_text.split(',') {
                let mut pieces = part.splitn(2, ':');
                let Some(field_name) = pieces.next() else {
                    return Err(failed("Fields must be name:Type pairs separated by commas."));
                };
                let Some(field_type) = pieces.next() else {
                    return Err(failed("Fields must be name:Type pairs separated by commas."));
                };
                fields.push((
                    field_name.trim().to_owned(),
                    field_type.trim().to_owned(),
                ));
            }
            if fields.is_empty() {
                return Err(failed("Fields must not be empty."));
            }
            let base = Path::new(&path)
                .file_stem()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            if format == "json" {
                let mut record = serde_json::Map::new();
                for (field_name, field_type) in &fields {
                    let value = match field_type.as_str() {
                        "Int" => json!(1),
                        "Double" | "Float" => json!(1.5),
                        "Bool" => json!(true),
                        _ => json!("Example"),
                    };
                    record.insert(field_name.clone(), value);
                }
                let formatted = serde_json::to_string_pretty(&Value::Object(record))
                    .map_err(|error| failed(error.to_string()))?;
                write_text_file(&cwd, &path, &format!("{formatted}\n"))?;
            } else {
                if !valid_swift_identifier(&base) {
                    return Err(failed(
                        "Fixture file name must be a valid Swift identifier for the swift format.",
                    ));
                }
                let mut lines = vec![
                    "import Foundation".to_owned(),
                    String::new(),
                    format!("public struct {base} {{"),
                ];
                for (field_name, field_type) in &fields {
                    lines.push(format!("    public var {field_name}: {field_type}"));
                }
                lines.push(String::new());
                let mut init_params: Vec<String> = Vec::new();
                let mut init_body: Vec<String> = Vec::new();
                for (field_name, field_type) in &fields {
                    let sample = match field_type.as_str() {
                        "Int" => "1",
                        "Double" | "Float" => "1.5",
                        "Bool" => "true",
                        _ => "\"Example\"",
                    };
                    init_params.push(format!("{field_name}: {field_type} = {sample}"));
                    init_body.push(format!("        self.{field_name} = {field_name}"));
                }
                lines.push(format!("    public init({}) {{", init_params.join(", ")));
                lines.extend(init_body);
                lines.push("    }".to_owned());
                lines.push(String::new());
                lines.push(format!("    public static let sample = {base}()"));
                lines.push("}".to_owned());
                lines.push(String::new());
                write_text_file(&cwd, &path, &lines.join("\n"))?;
            }
            Ok(json!({"path": path, "format": format, "fields": fields.len()}))
        }
        "ui_test_scaffold" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let app_name = opt_str(&args, "appName").unwrap_or_else(|| {
                Path::new(&cwd)
                    .file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .unwrap_or_default()
            });
            let overwrite = opt_bool(&args, "overwrite").unwrap_or(false);
            if !overwrite && workspace_file_exists(&cwd, &path)? {
                return Err(failed("A file already exists at that path; use write_file to overwrite it."));
            }
            let class_name: String = app_name
                .chars()
                .filter(|c| c.is_ascii_alphanumeric())
                .collect();
            let content = format!(
                "import XCTest\n\nfinal class {class_name}UITests: XCTestCase {{\n    func testAppLaunches() {{\n        let app = XCUIApplication()\n        app.launch()\n        XCTAssertTrue(app.state == .runningForeground)\n    }}\n}}\n"
            );
            write_text_file(&cwd, &path, &content)?;
            Ok(json!({"path": path, "appName": app_name}))
        }
        "test_snapshot_manage" => {
            let cwd = req_str(&args, "cwd", name)?;
            let action = opt_str(&args, "action").unwrap_or_else(|| "list".to_owned());
            let directory = opt_str(&args, "path").unwrap_or_else(|| "__Snapshots__".to_owned());
            match action.as_str() {
                "list" => {
                    let entries = read_dir_entries(&cwd, &directory, true).unwrap_or_default();
                    let refs: Vec<Value> = entries
                        .iter()
                        .filter(|e| e["isDirectory"] != true)
                        .filter_map(|e| e["path"].as_str().map(|p| json!(p)))
                        .collect();
                    let count = refs.len();
                    Ok(json!({"action": action, "refs": refs, "count": count}))
                }
                "clean" => {
                    if !opt_bool(&args, "confirm").unwrap_or(false) {
                        return Err(failed("Cleaning snapshots deletes files; pass confirm=true."));
                    }
                    let entries = read_dir_entries(&cwd, &directory, true).unwrap_or_default();
                    let mut deleted: Vec<String> = Vec::new();
                    let mut kept = 0;
                    for entry in entries {
                        if entry["isDirectory"] == true {
                            continue;
                        }
                        let Some(entry_path) = entry["path"].as_str() else {
                            continue;
                        };
                        let Some(entry_name) = entry["name"].as_str() else {
                            continue;
                        };
                        let base = Path::new(entry_name)
                            .file_stem()
                            .map(|n| n.to_string_lossy().into_owned())
                            .unwrap_or_default();
                        let mut params = args.clone();
                        if let Some(object) = params.as_object_mut() {
                            object.insert("query".to_owned(), json!(base));
                            object.insert("limit".to_owned(), json!(5));
                        }
                        let value = coincide_core::workspace_tools::search(&params)
                            .map_err(|error| failed(error.to_string()))?;
                        let referenced = value["matches"]
                            .as_array()
                            .cloned()
                            .unwrap_or_default()
                            .iter()
                            .any(|hit| {
                                hit["path"]
                                    .as_str()
                                    .map(|p| Path::new(p).extension().map_or(false, |x| x == "swift"))
                                    .unwrap_or(false)
                            });
                        if referenced {
                            kept += 1;
                        } else {
                            coincide_core::workspace_tools::delete_file(
                                &json!({"cwd": cwd, "path": entry_path}),
                            )
                            .map_err(|error| failed(error.to_string()))?;
                            deleted.push(entry_path.to_owned());
                        }
                    }
                    let count = deleted.len();
                    Ok(json!({"action": action, "deleted": deleted, "count": count, "kept": kept}))
                }
                _ => Err(failed("test_snapshot_manage action must be list or clean.")),
            }
        }
        "open_in_finder" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            validate_relative_path(&path)?;
            let result = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!("open {}", shell_quote(&path)),
                60,
            )?;
            Ok(json!({"path": path, "opened": true, "result": result}))
        }
        "reveal_in_finder" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            validate_relative_path(&path)?;
            let result = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!("open -R {}", shell_quote(&path)),
                60,
            )?;
            Ok(json!({"path": path, "revealed": true, "result": result}))
        }
        "image_encode_base64" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let data_uri = opt_bool(&args, "dataURI").unwrap_or(false);
            let data = read_workspace_bytes(&cwd, &path)?;
            let encoded = base64_encode(&data);
            let byte_len = data.len();
            if data_uri {
                let ext = Path::new(&path)
                    .extension()
                    .map(|x| x.to_string_lossy().to_lowercase())
                    .unwrap_or_default();
                let mime = match ext.as_str() {
                    "png" => "image/png",
                    "jpg" | "jpeg" => "image/jpeg",
                    "gif" => "image/gif",
                    "tiff" | "tif" => "image/tiff",
                    _ => "application/octet-stream",
                };
                return Ok(json!({"path": path, "base64": format!("data:{mime};base64,{encoded}"), "byteLen": byte_len}));
            }
            Ok(json!({"path": path, "base64": encoded, "byteLen": byte_len}))
        }
        "image_decode_base64" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let encoded = req_str(&args, "base64", name)?;
            let cleaned = encoded.trim();
            let payload = match cleaned.find(',') {
                Some(at) => &cleaned[at + 1..],
                None => cleaned,
            };
            let Some(data) = base64_decode(payload) else {
                return Err(failed("Base64 string could not be decoded."));
            };
            if data.is_empty() {
                return Err(failed("Base64 string could not be decoded."));
            }
            write_workspace_bytes(&cwd, &path, &data)?;
            Ok(json!({"path": path, "byteLen": data.len()}))
        }
        "image_get_dimensions" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            validate_relative_path(&path)?;
            let output = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "sips -g pixelWidth -g pixelHeight -g format {}",
                    shell_quote(&path)
                ),
                60,
            )?;
            let mut width: Option<i64> = None;
            let mut height: Option<i64> = None;
            let mut format: Option<String> = None;
            for line in output.lines() {
                let mut parts = line.splitn(2, ':');
                let Some(key) = parts.next() else {
                    continue;
                };
                let Some(value) = parts.next() else {
                    continue;
                };
                match key.trim() {
                    "pixelWidth" => width = value.trim().parse::<i64>().ok(),
                    "pixelHeight" => height = value.trim().parse::<i64>().ok(),
                    "format" => format = Some(value.trim().to_owned()),
                    _ => {}
                }
            }
            Ok(json!({"path": path, "width": width, "height": height, "format": format, "output": output}))
        }
        "image_convert_format" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let format = req_str(&args, "format", name)?;
            let normalized = if format.to_lowercase() == "jpg" {
                "jpeg".to_owned()
            } else {
                format.to_lowercase()
            };
            if !["png", "jpeg", "tiff", "bmp", "gif"].contains(&normalized.as_str()) {
                return Err(failed("Image format must be png, jpg, tiff, bmp, or gif."));
            }
            let output = opt_str(&args, "output").unwrap_or_else(|| {
                Path::new(&path)
                    .with_extension(format.to_lowercase())
                    .to_string_lossy()
                    .into_owned()
            });
            validate_relative_path(&path)?;
            validate_relative_path(&output)?;
            let mut command = format!("sips -s format {normalized} ");
            if normalized == "jpeg" {
                if let Some(quality) = opt_u64(&args, "quality") {
                    if quality > 100 {
                        return Err(failed("JPEG quality must be 0 to 100."));
                    }
                    command.push_str(&format!("-s formatOptions {quality} "));
                }
            }
            command.push_str(&format!(
                "{} --out {}",
                shell_quote(&path),
                shell_quote(&output)
            ));
            let result = run_shell(state, &thread_id, &cwd, &command, 120)?;
            Ok(json!({"path": path, "output": output, "format": normalized, "result": result}))
        }
        "image_generate_thumbnail" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let max_pixels = opt_u64(&args, "maxPixels").unwrap_or(256);
            if max_pixels < 1 || max_pixels > 4096 {
                return Err(failed("Thumbnail maxPixels must be 1 to 4096."));
            }
            let output = opt_str(&args, "output").unwrap_or_else(|| {
                let stem = Path::new(&path)
                    .with_extension("")
                    .to_string_lossy()
                    .into_owned();
                let ext = Path::new(&path)
                    .extension()
                    .map(|x| x.to_string_lossy().into_owned())
                    .unwrap_or_default();
                if ext.is_empty() {
                    format!("{stem}-thumb")
                } else {
                    format!("{stem}-thumb.{ext}")
                }
            });
            validate_relative_path(&path)?;
            validate_relative_path(&output)?;
            let result = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "sips -Z {max_pixels} {} --out {}",
                    shell_quote(&path),
                    shell_quote(&output)
                ),
                120,
            )?;
            Ok(json!({"path": path, "output": output, "maxPixels": max_pixels, "result": result}))
        }
        "image_extract_metadata" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            validate_relative_path(&path)?;
            let output = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!("mdls {}", shell_quote(&path)),
                60,
            )?;
            Ok(json!({"path": path, "metadata": output}))
        }
        "zip_file" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let output = req_str(&args, "output", name)?;
            if !output.ends_with(".zip") {
                return Err(failed("zip_file output must end in .zip."));
            }
            validate_relative_path(&path)?;
            validate_relative_path(&output)?;
            let result = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "ditto -c -k --sequesterRsrc --keepParent {} {}",
                    shell_quote(&path),
                    shell_quote(&output)
                ),
                300,
            )?;
            Ok(json!({"path": path, "output": output, "result": result}))
        }
        "unzip_file" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let destination = req_str(&args, "destination", name)?;
            validate_relative_path(&path)?;
            validate_relative_path(&destination)?;
            let result = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "mkdir -p {} && ditto -x -k {} {}",
                    shell_quote(&destination),
                    shell_quote(&path),
                    shell_quote(&destination)
                ),
                300,
            )?;
            Ok(json!({"path": path, "destination": destination, "result": result}))
        }
        "tar_archive_create" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let output = req_str(&args, "output", name)?;
            let compressed = output.ends_with(".tar.gz") || output.ends_with(".tgz");
            if !output.ends_with(".tar") && !compressed {
                return Err(failed("tar_archive_create output must end in .tar, .tar.gz, or .tgz."));
            }
            validate_relative_path(&path)?;
            validate_relative_path(&output)?;
            let flags = if compressed { "-czf" } else { "-cf" };
            let result = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "tar {flags} {} {}",
                    shell_quote(&output),
                    shell_quote(&path)
                ),
                300,
            )?;
            Ok(json!({"path": path, "output": output, "result": result}))
        }
        "tar_archive_extract" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let destination = req_str(&args, "destination", name)?;
            let compressed = path.ends_with(".tar.gz") || path.ends_with(".tgz");
            if !path.ends_with(".tar") && !compressed {
                return Err(failed("tar_archive_extract path must end in .tar, .tar.gz, or .tgz."));
            }
            validate_relative_path(&path)?;
            validate_relative_path(&destination)?;
            let flags = if compressed { "-xzf" } else { "-xf" };
            let result = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "mkdir -p {} && tar {flags} {} -C {}",
                    shell_quote(&destination),
                    shell_quote(&path),
                    shell_quote(&destination)
                ),
                300,
            )?;
            Ok(json!({"path": path, "destination": destination, "result": result}))
        }
        "gzip_compress_file" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let output = opt_str(&args, "output").unwrap_or_else(|| format!("{path}.gz"));
            validate_relative_path(&path)?;
            validate_relative_path(&output)?;
            let result = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "gzip -c {} > {}",
                    shell_quote(&path),
                    shell_quote(&output)
                ),
                120,
            )?;
            Ok(json!({"path": path, "output": output, "result": result}))
        }
        "gzip_decompress_file" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            let output = opt_str(&args, "output").unwrap_or_else(|| {
                if path.ends_with(".gz") {
                    path[..path.len() - 3].to_owned()
                } else {
                    format!("{path}.decompressed")
                }
            });
            validate_relative_path(&path)?;
            validate_relative_path(&output)?;
            let result = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!(
                    "gzip -dc {} > {}",
                    shell_quote(&path),
                    shell_quote(&output)
                ),
                120,
            )?;
            Ok(json!({"path": path, "output": output, "result": result}))
        }
        "count_file_lines" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = opt_str(&args, "path").unwrap_or_default();
            let mut targets: Vec<String> = Vec::new();
            if path.is_empty() {
                let entries = read_dir_entries(&cwd, "", true)?;
                targets = entries
                    .iter()
                    .filter(|e| e["isDirectory"] != true)
                    .filter_map(|e| e["path"].as_str().map(str::to_owned))
                    .collect();
            } else if let Ok(entries) = read_dir_entries(&cwd, &path, true) {
                if entries.is_empty() {
                    targets = vec![path.clone()];
                } else {
                    targets = entries
                        .iter()
                        .filter(|e| e["isDirectory"] != true)
                        .filter_map(|e| e["path"].as_str().map(str::to_owned))
                        .collect();
                }
            } else {
                targets = vec![path.clone()];
            }
            let (mut total, mut code, mut comment, mut blank, mut files) = (0, 0, 0, 0, 0);
            for target in targets {
                let Ok(document) = read_text_file_at(&cwd, &target) else {
                    continue;
                };
                let counts = line_counts(&document);
                total += counts.0;
                code += counts.1;
                comment += counts.2;
                blank += counts.3;
                files += 1;
            }
            Ok(json!({"path": path, "files": files, "total": total, "code": code, "comment": comment, "blank": blank}))
        }
        "extract_code_symbols" => {
            let cwd = req_str(&args, "cwd", name)?;
            let path = opt_str(&args, "path").unwrap_or_default();
            let mut sources: Vec<String> = Vec::new();
            if path.is_empty() {
                let entries = read_dir_entries(&cwd, "", true)?;
                sources = entries
                    .iter()
                    .filter(|e| {
                        e["isDirectory"] != true
                            && e["path"]
                                .as_str()
                                .map(|p| Path::new(p).extension().map_or(false, |x| x == "swift"))
                                .unwrap_or(false)
                    })
                    .filter_map(|e| e["path"].as_str().map(str::to_owned))
                    .collect();
            } else if let Ok(entries) = read_dir_entries(&cwd, &path, true) {
                if entries.is_empty() {
                    sources = vec![path.clone()];
                } else {
                    sources = entries
                        .iter()
                        .filter(|e| {
                            e["isDirectory"] != true
                                && e["path"]
                                    .as_str()
                                    .map(|p| Path::new(p).extension().map_or(false, |x| x == "swift"))
                                    .unwrap_or(false)
                        })
                        .filter_map(|e| e["path"].as_str().map(str::to_owned))
                        .collect();
                }
            } else {
                sources = vec![path.clone()];
            }
            sources.sort();
            let mut symbols: Vec<Value> = Vec::new();
            let mut files = 0;
            for file in sources {
                let Ok(document) = read_text_file_at(&cwd, &file) else {
                    continue;
                };
                symbols.extend(extract_symbols(&document, &file));
                files += 1;
            }
            let count = symbols.len();
            Ok(json!({"path": path, "files": files, "symbols": symbols, "count": count}))
        }
        "find_duplicate_files" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = opt_str(&args, "path").unwrap_or_default();
            let entries = read_dir_entries(&cwd, &path, true)?;
            let mut files: Vec<String> = entries
                .iter()
                .filter(|e| e["isDirectory"] != true)
                .filter_map(|e| e["path"].as_str().map(str::to_owned))
                .collect();
            files.sort();
            let mut by_hash: std::collections::BTreeMap<String, Vec<String>> =
                std::collections::BTreeMap::new();
            let mut skipped = 0;
            for chunk in files.chunks(100) {
                let mut command = String::from("shasum -a 256");
                for file in chunk {
                    command.push(' ');
                    command.push_str(&shell_quote(file));
                }
                let output = run_shell(state, &thread_id, &cwd, &command, 300)?;
                for line in output.lines() {
                    let Some((hash, rest)) = line.split_once("  ") else {
                        skipped += 1;
                        continue;
                    };
                    if hash.len() != 64 || !hash.chars().all(|c| c.is_ascii_hexdigit()) {
                        skipped += 1;
                        continue;
                    }
                    by_hash
                        .entry(hash.to_lowercase())
                        .or_default()
                        .push(rest.to_owned());
                }
            }
            let mut groups: Vec<Value> = Vec::new();
            for (hash, mut group_files) in by_hash {
                if group_files.len() < 2 {
                    continue;
                }
                group_files.sort();
                let byte_len = read_workspace_bytes(&cwd, &group_files[0])
                    .map(|b| b.len())
                    .unwrap_or(0);
                groups.push(json!({"hash": hash, "files": group_files, "byteLen": byte_len}));
            }
            let count = groups.len();
            Ok(json!({"path": path, "groups": groups, "count": count, "skipped": skipped}))
        }
        "env_capture_logs" => {
            let mut params = args.clone();
            if let Some(object) = params.as_object_mut() {
                object.remove("cwd");
                object.remove("threadId");
            }
            engine_request(state, "memory.snapshot", params)
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
        assert_eq!(swift.len(), 166, "Swift registry must hold 166 tools");
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
