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
        description: "Run git with an action of status, commit, branch, diff, or rollback. Rollback resets hard to HEAD, HEAD~N, HEAD^N, or a full SHA and requires confirm=true.",
        action: "git.rollback",
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
    ToolDef {
        name: "project_build",
        description: "Build the thread project with xcodebuild and return the real diagnostics, exit code, and output.",
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
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme to build.",
            },
            ToolParam {
                name: "configuration",
                kind: "string",
                required: false,
                description: "Build configuration, such as Debug or Release.",
            },
            ToolParam {
                name: "destination",
                kind: "string",
                required: false,
                description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "project_test",
        description: "Run the thread project tests with xcodebuild test and return the real test summary, diagnostics, exit code, and output.",
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
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme to test.",
            },
            ToolParam {
                name: "configuration",
                kind: "string",
                required: false,
                description: "Build configuration, such as Debug or Release.",
            },
            ToolParam {
                name: "destination",
                kind: "string",
                required: false,
                description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "compiler_diagnostics_engine",
        description: "Run a real build and return only its parsed compiler diagnostics with error and warning counts.",
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
                name: "kind",
                kind: "string",
                required: false,
                description: "xcodebuild or swiftpm. Defaults to xcodebuild.",
            },
            ToolParam {
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme to build.",
            },
            ToolParam {
                name: "destination",
                kind: "string",
                required: false,
                description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "dependency_resolution_engine",
        description: "Resolve the thread project package dependencies with swift package resolve or xcodebuild and return the real result.",
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
                name: "kind",
                kind: "string",
                required: false,
                description: "swiftpm or xcode. Defaults to swiftpm.",
            },
            ToolParam {
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme for xcode dependency resolution.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "generate_xcodeproj",
        description: "Generate the Xcode project from project.yml with the xcodegen CLI; errors honestly when xcodegen is not installed.",
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
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "project_scheme_list",
        description: "List the thread project schemes, targets, and configurations from xcodebuild -list -json.",
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
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "project_target_list",
        description: "List the thread project targets from xcodebuild -list -json.",
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
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "project_build_settings",
        description: "Read the thread project build settings with xcodebuild -showBuildSettings and return them parsed by target. Read only; there is no setter.",
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
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme to read settings for.",
            },
            ToolParam {
                name: "configuration",
                kind: "string",
                required: false,
                description: "Build configuration, such as Debug or Release.",
            },
            ToolParam {
                name: "target",
                kind: "string",
                required: false,
                description: "Target to read settings for.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "project_clean",
        description: "Clean the thread project build products with xcodebuild clean. Requires confirm=true.",
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
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme to clean.",
            },
            ToolParam {
                name: "configuration",
                kind: "string",
                required: false,
                description: "Build configuration, such as Debug or Release.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: true,
                description: "Must be true. Cleaning removes build products.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "project_archive",
        description: "Archive the thread project with xcodebuild archive into the given archive path.",
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
                name: "scheme",
                kind: "string",
                required: true,
                description: "Scheme to archive.",
            },
            ToolParam {
                name: "archivePath",
                kind: "string",
                required: true,
                description: "Archive path relative to the thread working directory.",
            },
            ToolParam {
                name: "configuration",
                kind: "string",
                required: false,
                description: "Build configuration, such as Debug or Release.",
            },
            ToolParam {
                name: "destination",
                kind: "string",
                required: false,
                description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "test_run_single",
        description: "Run one test with xcodebuild test -only-testing and return the real test summary and output.",
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
                name: "testIdentifier",
                kind: "string",
                required: true,
                description: "Test identifier for -only-testing, such as Target/Class/testMethod.",
            },
            ToolParam {
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme to test.",
            },
            ToolParam {
                name: "destination",
                kind: "string",
                required: false,
                description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "test_coverage_report",
        description: "Report line coverage totals from an xcresult bundle with xcrun xccov view --report --json.",
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
                name: "xcresultPath",
                kind: "string",
                required: true,
                description: "Path to the xcresult bundle, relative to the thread working directory.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "test_coverage_reporter",
        description: "Render a full coverage report from an xcresult bundle with xcrun xccov, as JSON or text.",
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
                name: "xcresultPath",
                kind: "string",
                required: true,
                description: "Path to the xcresult bundle, relative to the thread working directory.",
            },
            ToolParam {
                name: "format",
                kind: "string",
                required: false,
                description: "json or text. Defaults to text.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "performance_benchmark",
        description: "Run one allow-listed build or test command and report its real wall time, exit code, and output.",
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
                name: "benchmark",
                kind: "string",
                required: true,
                description: "Allow-listed benchmark: xcodebuild-build, xcodebuild-test, swift-build, swift-test, or xcodebuild-clean-build.",
            },
            ToolParam {
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme for xcodebuild benchmarks.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "docc_build",
        description: "Build the thread project documentation with xcodebuild docbuild and return the real result.",
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
                name: "scheme",
                kind: "string",
                required: true,
                description: "Scheme to document.",
            },
            ToolParam {
                name: "destination",
                kind: "string",
                required: false,
                description: "Destination specifier, such as platform=iOS Simulator,name=iPhone 16.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "xcode_scheme_manager",
        description: "List the thread project schemes, or validate one scheme by reading its build settings.",
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
                name: "action",
                kind: "string",
                required: true,
                description: "list or validate.",
            },
            ToolParam {
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme to validate.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "xcode_build_settings_inspector",
        description: "Read one named build setting across the thread project targets with xcodebuild -showBuildSettings.",
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
                name: "key",
                kind: "string",
                required: true,
                description: "Build setting name, such as PRODUCT_BUNDLE_IDENTIFIER.",
            },
            ToolParam {
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme to read settings for.",
            },
            ToolParam {
                name: "configuration",
                kind: "string",
                required: false,
                description: "Build configuration, such as Debug or Release.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "xcode_device_destination_finder",
        description: "Find the real run destinations for the thread project scheme with xcodebuild -showdestinations.",
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
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme to find destinations for.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "simulator_list",
        description: "List the simulators on the machine from xcrun simctl list -j devices, parsed by runtime.",
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
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "simulator_boot",
        description: "Boot a simulator with xcrun simctl boot and return the real result.",
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
                name: "device",
                kind: "string",
                required: true,
                description: "Simulator UDID or name.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "simulator_controller",
        description: "Control a simulator with xcrun simctl: boot, shutdown, erase, openurl, or status.",
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
                name: "action",
                kind: "string",
                required: true,
                description: "boot, shutdown, erase, openurl, or status.",
            },
            ToolParam {
                name: "device",
                kind: "string",
                required: true,
                description: "Simulator UDID or name.",
            },
            ToolParam {
                name: "url",
                kind: "string",
                required: false,
                description: "URL to open for openurl.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "device_list",
        description: "List the connected devices with xcrun devicectl, falling back to xcrun xctrace list devices when devicectl is unavailable.",
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
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "provisioning_check",
        description: "Check one provisioning profile with security cms -D and return its name, UUID, team, entitlements, and expiry.",
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
                name: "profilePath",
                kind: "string",
                required: true,
                description: "Path to the provisioning profile, relative to the thread working directory.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "swift_package_manager",
        description: "Run a Swift Package Manager command on the thread package: describe, resolve, clean, or reset.",
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
                name: "action",
                kind: "string",
                required: true,
                description: "describe, resolve, clean, or reset.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: false,
                description: "Must be true for reset.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "package_dependency_update",
        description: "Update the thread package dependencies with swift package update, optionally for one package.",
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
                name: "package",
                kind: "string",
                required: false,
                description: "Package name to update; updates all packages when omitted.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "code_signing_diagnose",
        description: "Diagnose the code signature of a file with codesign --verify and codesign -dv and return the parsed result.",
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
                name: "path",
                kind: "string",
                required: true,
                description: "Path to the file to diagnose, relative to the thread working directory.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "xcode_toolchain_info",
        description: "Report the Xcode version, build, and developer directory from xcodebuild -version and xcode-select -p.",
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
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "xcresult_parser",
        description: "Read an xcresult bundle with xcrun xcresulttool get --format json and return the parsed result.",
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
                name: "path",
                kind: "string",
                required: true,
                description: "Path to the xcresult bundle, relative to the thread working directory.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "mach_o_binary_analyzer",
        description: "Analyze a Mach-O binary with file, otool -L, and otool -hv and return its type, libraries, and header.",
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
                name: "path",
                kind: "string",
                required: true,
                description: "Path to the binary, relative to the thread working directory.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "signing_certificate_inspector",
        description: "List the code signing identities on the machine from security find-identity -v -p codesigning.",
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
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "provisioning_profile_reader",
        description: "Read one provisioning profile with security cms -D and return its full parsed property list.",
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
                name: "profilePath",
                kind: "string",
                required: true,
                description: "Path to the provisioning profile, relative to the thread working directory.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "swift_ast_inspector",
        description: "Dump the Swift AST of one file with swiftc -dump-ast and return declaration counts.",
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
                name: "path",
                kind: "string",
                required: true,
                description: "Path to the Swift source file, relative to the thread working directory.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "binary_size_report",
        description: "Report the sizes of files under a build directory from a real directory read plus du, largest first.",
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
                name: "path",
                kind: "string",
                required: false,
                description: "Directory to report, relative to the thread working directory. Defaults to build.",
            },
            ToolParam {
                name: "top",
                kind: "integer",
                required: false,
                description: "Largest files to return, 1-100. Defaults to 20.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Seconds to wait for the command.",
            },
        ],
    },
    ToolDef {
        name: "git_review_diff",
        description: "Read the review diff for the thread working directory: staged, unstaged, and untracked changes against HEAD or the branch base.",
        action: "git.review.diff",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "scope",
                kind: "string",
                required: false,
                description: "uncommitted or branch. Defaults to uncommitted.",
            },
            ToolParam {
                name: "ignoreWhitespace",
                kind: "boolean",
                required: false,
                description: "Ignore whitespace changes in the diff.",
            },
        ],
    },
    ToolDef {
        name: "search_symbol",
        description: "Heuristic declaration search for a symbol across four regex declaration patterns. Regex scan, not semantic analysis.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "symbol",
                kind: "string",
                required: true,
                description: "Symbol name to search for.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "dependency_graph",
        description: "Regex import scan listing which files import which modules. Nodes conflate file paths and module names.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "source_graph_builder",
        description: "Regex symbol and import graph over the workspace. Type edges come from declaration regex, not a semantic index.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "semantic_query_engine",
        description: "Substring concept search over workspace text. Substring matching, not semantic search.",
        action: "workspace.search",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "query",
                kind: "string",
                required: true,
                description: "Substring to search for.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "code_summary",
        description: "Line, non-empty-line and comment counts for one file. Does not extract interface declarations.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "code_lint",
        description: "Line-length over 120 plus TODO and FIXME scan for one file or the workspace. Regex and line rules, not a style analyzer.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "complexity_analysis",
        description: "Substring keyword counting for one file. Counts keywords in comments and strings too; not real cyclomatic complexity.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "autonomous_review_engine",
        description: "Heuristic keyword scan for force-unwraps and concurrency smells. No retain-cycle check; findings are leads, not diagnoses.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "runtime_diagnostics_engine",
        description: "Keyword scan of a crash or diagnostics log file for fatal errors, signals and thread mentions. Leads, not diagnoses.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "logPath",
                kind: "string",
                required: true,
                description: "Crash or diagnostics log file, relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "code_metrics_analyzer",
        description: "Line counts, comment density, function and type counts, plus a keyword-based complexity estimate per Swift file.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "memory_leak_detector",
        description: "Heuristic static scan for unowned self captures, strong self captures, non-weak delegates and timer observers.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "dead_code_eliminator",
        description: "Report-only list of unreferenced private function candidates with file and line evidence. Deletes nothing; deletion is a separate confirmed edit.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "dead_code_scan",
        description: "Heuristic scan for declarations with zero references elsewhere in the workspace. Overloaded names are excluded.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "duplicate_code_scan",
        description: "Normalized six-line sliding-window scan for repeated code blocks, reported as file and line pairs.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "todo_scan",
        description: "Heuristic regex inventory of TODO, FIXME, XXX and HACK markers with file, line and text.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "todo_fixme_scanner",
        description: "Heuristic regex inventory of TODO, FIXME, HACK and NOTE annotations with file, line and text.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "license_header_check",
        description: "Lists Swift files whose first 15 lines lack the required header text. Defaults to Copyright.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            ToolParam {
                name: "requiredText",
                kind: "string",
                required: false,
                description: "Header text that must appear in the first 15 lines. Defaults to Copyright.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "api_surface_extract",
        description: "Public and open declarations grouped by file, with counts. Regex scan, not a compiler API surface.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "access_level_audit",
        description: "Declaration counts by access level: public, open, internal, private, fileprivate. Regex scan.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "concurrency_audit",
        description: "Heuristic scan for main-queue sync, nonisolated unsafe, unstructured tasks, shared mutable statics and sync blocks.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "swift_concurrency_analyzer",
        description: "Heuristic scan for non-Sendable transfers, unsafe mutable state and actor reentrancy hazards. Regex scan, not a compiler check.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "swift_migration_advisor",
        description: "Heuristic audit for Swift 6 strict concurrency, mutable globals and actor isolation issues. Regex scan.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "security_audit_scanner",
        description: "Heuristic scan for hardcoded secrets, plain HTTP URLs and unsafe credentials. Secret matches report file, line and pattern only, never values.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "secrets_scan",
        description: "Heuristic scan for AWS keys, GitHub tokens, sk keys, credential assignments and private-key blocks. Reports file, line and pattern only, never matched values or line contents.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "network_security_auditor",
        description: "Heuristic scan of App Transport Security keys, plaintext HTTP URLs and certificate pinning rules. Regex scan.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "permissions_audit",
        description: "Heuristic scan of Info.plist usage descriptions, entitlements and PrivacyInfo entries, with missing-description checks.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "accessibility_audit",
        description: "Heuristic scan for Buttons, Images and TextFields and their accessibility labels, hints and values. Regex scan.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "accessibility_audit_scanner",
        description: "Heuristic scan of SwiftUI and AppKit views for accessibility labels, hints, traits and identifiers. Regex scan.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "interface_simulator",
        description: "Heuristic audit of SwiftUI view structures, accessibility traits, dynamic type scaling and tap targets. Regex scan, not a running simulator.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "docstring_generator",
        description: "Generates Apple DocC style markdown doc blocks for Swift declarations found by regex in one file.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "symbol",
                kind: "string",
                required: false,
                description: "Declaration name; when given, only that declaration is documented.",
            },
        ],
    },
    ToolDef {
        name: "code_snippet_manager",
        description: "Returns a standardized Swift 6 template by name, and writes it to path when given. Templates are fixed starter text, not generated code.",
        action: "workspace.write_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "template",
                kind: "string",
                required: true,
                description: "Template name: observable, asyncstream, actor, or glasscard.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "unused_imports_detector",
        description: "Heuristic scan for Swift module imports never referenced elsewhere in the same file.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "force_unwrap_scan",
        description: "Heuristic regex scan for force unwraps, try! and as! across Swift sources.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "string_literal_audit",
        description: "Heuristic scan for hardcoded user-facing string literals not routed through localization. Regex scan.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "comment_density_report",
        description: "Comment-to-code ratios per Swift file, least-documented first. Line-based counts, not semantic documentation quality.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "function_size_report",
        description: "Longest functions by brace-counted line span, highlighting decomposition candidates. Heuristic spans, not a compiler AST.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "call_hierarchy",
        description: "Definition site, callers and callees for a function name, from regex. Callers are textual call sites, not a compiler call graph.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "function",
                kind: "string",
                required: true,
                description: "Function name to trace.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "type_hierarchy",
        description: "Class, struct, enum and protocol declarations with inheritance and conformance clauses, from regex.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "protocol_conformance_list",
        description: "Every type declaring conformance to a protocol, from regex over declaration lines.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "protocol",
                kind: "string",
                required: true,
                description: "Protocol name to list conformances for.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "import_graph",
        description: "File-level import graph; which files import a given module. Regex scan over import lines.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "module",
                kind: "string",
                required: false,
                description: "Module name; when given, only files importing it are listed.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "change_impact_estimate",
        description: "Blast-radius estimate: files textually referencing a symbol name. Regex scan, not a dependency graph.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "symbol",
                kind: "string",
                required: true,
                description: "Symbol name to search for.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "conflict_marker_scan",
        description: "Regex scan for unresolved merge-conflict markers in source files.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "build_log_analyze",
        description: "Parses a build log file for errors, warnings and the build result. Text parsing, not a build run.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "crash_log_parse",
        description: "Parses a crash log file for exception type, termination reason, faulting thread and blamed frames. Text parsing.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "deprecation_usage_scan",
        description: "Regex scan for deprecated markers in declarations. Usage sites of a deprecated API need the API name via search_symbol.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "info_plist_audit",
        description: "Audits Info.plist files for required keys, version-format sanity and duplicate bundle identifiers. Text parsing.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "api_endpoint_audit",
        description: "Hardcoded http and https URL literals grouped by host. Regex scan.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "color_usage_audit",
        description: "Heuristic scan for hardcoded colors that should live in the asset catalog. Regex scan.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "strings_file_validate",
        description: "Validates .strings files for syntax, duplicate keys and empty values. Line-based parsing.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "entitlements_diff",
        description: "Diffs two .entitlements plists into added, removed and changed keys. Text parsing.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "otherPath",
                kind: "string",
                required: true,
                description: "Second file to compare against path, relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "pbxproj_lint",
        description: "Read-only regex lint over project.pbxproj text: file references pointing at missing files, duplicate paths and dangling build-file refs. Never writes the pbxproj.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "xctest_discovery",
        description: "Lists XCTestCase subclasses and test methods by regex, without running anything.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "build_settings_diff",
        description: "Diffs two .xcconfig files key by key. Text parsing.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
            ToolParam {
                name: "otherPath",
                kind: "string",
                required: true,
                description: "Second file to compare against path, relative to the working directory.",
            },
        ],
    },
    ToolDef {
        name: "build_phase_scripts_list",
        description: "Lists Run Script build phases from project.pbxproj text with truncated script bodies. Read-only.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "build_configuration_list",
        description: "Lists build configurations per project and target from project.pbxproj text. Read-only.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "target_dependencies_list",
        description: "Lists target-to-target dependencies from project.pbxproj text. Read-only.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "target_source_list",
        description: "Lists source files compiled into each target from Compile Sources phases in project.pbxproj text. Read-only.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "workspace_settings_read",
        description: "Reads Xcode workspace .xcsettings plists as key-value pairs. Text parsing.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "scheme_test_plan_list",
        description: "Lists .xctestplan files and the test targets each covers. JSON parsing, no test run.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "test_log_parse",
        description: "Parses a test log for pass and fail outcomes, suite summaries, error lines and the failed list. Text parsing.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "test_flaky_detect",
        description: "Parses a test log for tests with both pass and fail outcomes. Text parsing.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            P_PATH,
        ],
    },
    ToolDef {
        name: "code_comment_extract",
        description: "Extracts triple-slash and block doc comments per file, optionally limited to files mentioning a symbol. Regex scan.",
        action: "workspace.search_regex",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
            ToolParam {
                name: "symbol",
                kind: "string",
                required: false,
                description: "Symbol name; when given, only files mentioning it are included.",
            },
        ],
    },
    ToolDef {
        name: "api_docs_coverage",
        description: "Share of public declarations carrying doc comments, from regex over Swift files.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "markdown_link_check",
        description: "Validates internal links in Markdown files against the workspace file list. Regex plus file existence, not a link crawler.",
        action: "workspace.read_file",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            P_LIMIT,
        ],
    },
    ToolDef {
        name: "docs_index_build",
        description: "Indexes Markdown files with path, first-heading title and size. Line-based reading.",
        action: "workspace.files",
        channel: "desktop",
        params: &[
            P_CWD,
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "framework_linker_auditor",
        description: "Audits linked frameworks from the pbxproj against target platforms and weak-linking flags. Text parsing of the project file.",
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
                required: false,
                description: "Relative path to project.pbxproj. Defaults to the first project.pbxproj found.",
            },
        ],
    },
    ToolDef {
        name: "string_catalog_migrator",
        description: "Migrates legacy .strings and .stringsdict files into a modern .xcstrings catalog, then verifies the catalog by re-reading it.",
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
                required: false,
                description: "File or directory to migrate, relative to the working directory. Defaults to the whole workspace.",
            },
            ToolParam {
                name: "sourceLanguage",
                kind: "string",
                required: false,
                description: "Source language for the catalog. Defaults to en.",
            },
        ],
    },
    ToolDef {
        name: "symbol_reference_graph",
        description: "Finds definitions and reference sites of one symbol across Swift sources. Regex scan, not semantic analysis.",
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
                name: "symbol",
                kind: "string",
                required: true,
                description: "Symbol name to trace.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum reference sites to return.",
            },
        ],
    },
    ToolDef {
        name: "podfile_inspector",
        description: "Parses and validates CocoaPods Podfile dependencies and target integrations, with versions from Podfile.lock when present.",
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
                required: false,
                description: "Relative path to the Podfile. Defaults to the first Podfile found.",
            },
        ],
    },
    ToolDef {
        name: "carthage_cartfile_inspector",
        description: "Inspects Carthage Cartfile and Cartfile.resolved dependencies with their resolved versions.",
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
                required: false,
                description: "Relative path to the Cartfile. Defaults to the first Cartfile found.",
            },
        ],
    },
    ToolDef {
        name: "spm_dependency_tree",
        description: "Computes the resolved SwiftPM dependency graph from swift package show-dependencies JSON output.",
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
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Package directory relative to the working directory. Defaults to the workspace root.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Command timeout in seconds.",
            },
        ],
    },
    ToolDef {
        name: "package_manifest_read",
        description: "Parses Package.swift: name, platforms, products, targets, and dependencies. Text parsing, no swift invocation.",
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
                required: false,
                description: "Relative path to Package.swift. Defaults to Package.swift in the workspace root.",
            },
        ],
    },
    ToolDef {
        name: "package_manifest_validate",
        description: "Validates Package.swift with swift package dump-package: exit code plus name and target count from the parsed manifest.",
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
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Package directory relative to the working directory. Defaults to the workspace root.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Command timeout in seconds.",
            },
        ],
    },
    ToolDef {
        name: "package_dependency_audit",
        description: "Audits Package.swift against Package.resolved: manifest dependencies missing from resolved, non-exact requirements, and resolved pins missing from the manifest.",
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
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Package directory relative to the working directory. Defaults to the workspace root.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Command timeout in seconds.",
            },
        ],
    },
    ToolDef {
        name: "package_dependency_add",
        description: "Inserts a .package(url:from:) dependency into Package.swift with optional product and target wiring, then verifies on re-read.",
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
                name: "url",
                kind: "string",
                required: true,
                description: "Package repository URL.",
            },
            ToolParam {
                name: "version",
                kind: "string",
                required: true,
                description: "Minimum version for from:.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Relative path to Package.swift. Defaults to Package.swift in the workspace root.",
            },
            ToolParam {
                name: "product",
                kind: "string",
                required: false,
                description: "Product name to wire into a target.",
            },
            ToolParam {
                name: "target",
                kind: "string",
                required: false,
                description: "Target name to wire the product into.",
            },
        ],
    },
    ToolDef {
        name: "asset_catalog_list",
        description: "Enumerates .xcassets catalogs with image, color, icon, dataset, and symbol sets plus counts.",
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
                name: "path",
                kind: "string",
                required: false,
                description: "Directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "asset_image_add",
        description: "Creates an imageName.imageset with a valid Contents.json and copies a workspace image into it, verified on re-read.",
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
                name: "imageName",
                kind: "string",
                required: true,
                description: "Image set name without the .imageset suffix.",
            },
            ToolParam {
                name: "source",
                kind: "string",
                required: true,
                description: "Workspace image file to copy, relative to the working directory.",
            },
            ToolParam {
                name: "catalog",
                kind: "string",
                required: false,
                description: "Relative path to the .xcassets catalog. Defaults to the first catalog found.",
            },
        ],
    },
    ToolDef {
        name: "strings_localization",
        description: "Gets, sets, or deletes one localization key in a .strings or .xcstrings file, per locale.",
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
                description: "Relative path to the .strings or .xcstrings file.",
            },
            ToolParam {
                name: "action",
                kind: "string",
                required: true,
                description: "Action: get, set, or delete.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: true,
                description: "Localization key.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: false,
                description: "Value for set.",
            },
            ToolParam {
                name: "locale",
                kind: "string",
                required: false,
                description: "Locale code for .xcstrings. Defaults to the catalog source language.",
            },
        ],
    },
    ToolDef {
        name: "localization_audit",
        description: "Reports missing keys per locale and keys never referenced in Swift sources.",
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
                required: false,
                description: "File or directory to audit, relative to the working directory. Defaults to the whole workspace.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum findings to return.",
            },
        ],
    },
    ToolDef {
        name: "localize_app",
        description: "Localizes an app: discovers NSLocalizedString keys in Swift, creates or merges Localizable.xcstrings with per-locale state, and sets Info.plist CFBundleLocalizations and CFBundleDevelopmentRegion.",
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
                name: "action",
                kind: "string",
                required: true,
                description: "Action: localize, status, or set_development_region.",
            },
            ToolParam {
                name: "languages",
                kind: "array",
                required: false,
                description: "Target language codes for localize, at most 3.",
            },
            ToolParam {
                name: "translations",
                kind: "array",
                required: false,
                description: "Translations for localize, each with locale, key, and value.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            ToolParam {
                name: "developmentRegion",
                kind: "string",
                required: false,
                description: "Development region code for set_development_region.",
            },
        ],
    },
    ToolDef {
        name: "asset_catalog_manager",
        description: "Inspects, manages, and creates .xcassets catalogs, color sets, and image sets.",
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
                name: "action",
                kind: "string",
                required: true,
                description: "Action: list, inspect, create_imageset, or create_colorset.",
            },
            ToolParam {
                name: "catalog",
                kind: "string",
                required: false,
                description: "Relative path to the .xcassets catalog. Defaults to the first catalog found.",
            },
            ToolParam {
                name: "name",
                kind: "string",
                required: false,
                description: "Set name for inspect and create actions.",
            },
            ToolParam {
                name: "source",
                kind: "string",
                required: false,
                description: "Workspace image file to copy for create_imageset.",
            },
            ToolParam {
                name: "lightHex",
                kind: "string",
                required: false,
                description: "Light-mode hex color for create_colorset.",
            },
            ToolParam {
                name: "darkHex",
                kind: "string",
                required: false,
                description: "Dark-mode hex color for create_colorset.",
            },
        ],
    },
    ToolDef {
        name: "localization_manager",
        description: "Inspects, extracts, adds translations to, and validates .strings and .xcstrings catalogs.",
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
                name: "action",
                kind: "string",
                required: true,
                description: "Action: list, extract, add, or validate.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory to manage, relative to the working directory. Defaults to the whole workspace.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: false,
                description: "Localization key for add.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: false,
                description: "Translation value for add.",
            },
            ToolParam {
                name: "locale",
                kind: "string",
                required: false,
                description: "Locale code for add to .xcstrings.",
            },
        ],
    },
    ToolDef {
        name: "entitlements_manager",
        description: "Inspects, adds, or removes App Sandbox, Network Client and Server, and security entitlements in .entitlements plists.",
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
                name: "action",
                kind: "string",
                required: true,
                description: "Action: list, add, or remove.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Relative path to the .entitlements file. Defaults to the first one found.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: false,
                description: "Entitlement key for add and remove.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: false,
                description: "Value for add: true, false, or a string.",
            },
            ToolParam {
                name: "threadId",
                kind: "string",
                required: false,
                description: "Owning thread ID. Only used by the MCP server path.",
            },
        ],
    },
    ToolDef {
        name: "colorset_builder",
        description: "Generates a .colorset asset catalog JSON with light and dark mode hex definitions.",
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
                name: "name",
                kind: "string",
                required: true,
                description: "Color set name without the .colorset suffix.",
            },
            ToolParam {
                name: "lightHex",
                kind: "string",
                required: true,
                description: "Light-mode hex color, for example #FF8800.",
            },
            ToolParam {
                name: "catalog",
                kind: "string",
                required: false,
                description: "Relative path to the .xcassets catalog. Defaults to the first catalog found.",
            },
            ToolParam {
                name: "darkHex",
                kind: "string",
                required: false,
                description: "Dark-mode hex color. Defaults to the light hex.",
            },
        ],
    },
    ToolDef {
        name: "icon_generator_tool",
        description: "Generates a complete AppIcon set for iOS, macOS, or watchOS from source artwork with real sips resizing.",
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
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "source",
                kind: "string",
                required: true,
                description: "Source artwork file, relative to the working directory.",
            },
            ToolParam {
                name: "output",
                kind: "string",
                required: true,
                description: "Destination .appiconset directory, relative to the working directory.",
            },
            ToolParam {
                name: "platform",
                kind: "string",
                required: false,
                description: "Platform: ios, macos, or watchos. Defaults to ios.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Command timeout in seconds.",
            },
        ],
    },
    ToolDef {
        name: "project_entitlements",
        description: "Parses .entitlements files and returns their keys and values.",
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
                required: false,
                description: "Relative path to the .entitlements file. Defaults to the first one found.",
            },
        ],
    },
    ToolDef {
        name: "project_info_plist",
        description: "Gets, sets, or deletes Info.plist keys with real plist serialization.",
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
                name: "action",
                kind: "string",
                required: true,
                description: "Action: get, set, or delete.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Relative path to the plist. Defaults to the first Info.plist found.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: false,
                description: "Plist key for get, set, and delete.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: false,
                description: "Value for set: true, false, a number, or a string.",
            },
            ToolParam {
                name: "threadId",
                kind: "string",
                required: false,
                description: "Owning thread ID. Only used by the MCP server path.",
            },
        ],
    },
    ToolDef {
        name: "project_capabilities",
        description: "Lists, enables, or disables Xcode capabilities backed by boolean entitlements. Array-valued capabilities are reported, not silently rewritten.",
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
                name: "action",
                kind: "string",
                required: true,
                description: "Action: list, enable, or disable.",
            },
            ToolParam {
                name: "capability",
                kind: "string",
                required: false,
                description: "Capability name for enable and disable, for example app-sandbox or network-client.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Relative path to the .entitlements file. Defaults to the first one found.",
            },
            ToolParam {
                name: "threadId",
                kind: "string",
                required: false,
                description: "Owning thread ID. Only used by the MCP server path.",
            },
        ],
    },
    ToolDef {
        name: "project_signing",
        description: "Reports CODE_SIGN_STYLE, DEVELOPMENT_TEAM, and bundle ID from the pbxproj plus provisioning profile filenames, never profile contents.",
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
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Relative path to project.pbxproj. Defaults to the first project.pbxproj found.",
            },
            ToolParam {
                name: "scheme",
                kind: "string",
                required: false,
                description: "Scheme to query with xcodebuild -showBuildSettings. Defaults to pbxproj text parsing only.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Command timeout in seconds.",
            },
        ],
    },
    ToolDef {
        name: "entry_points_discover",
        description: "Finds application entry points: @main types, main.swift files, and AppDelegate and SceneDelegate classes.",
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
                description: "File or directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum entry points to return.",
            },
        ],
    },
    ToolDef {
        name: "repo_overview",
        description: "Summarizes the repository: file counts by language, README and license presence, and largest files.",
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
                name: "path",
                kind: "string",
                required: false,
                description: "Directory to summarize, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "project_structure_map",
        description: "Builds a machine-readable map of directories with file counts plus Xcode targets from the pbxproj.",
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
                description: "Directory to map, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "recent_changes",
        description: "Lists files modified within the last N hours, newest first, from real file modification times.",
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
                name: "hours",
                kind: "integer",
                required: false,
                description: "Look-back window in hours. Defaults to 24.",
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
        name: "readme_locate",
        description: "Finds README files with their title lines.",
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
                required: false,
                description: "Directory to search, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "dependency_licenses",
        description: "Inventories third-party dependencies from Package.resolved and Podfile.lock for license review, with name, version, and source.",
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
                required: false,
                description: "Directory to inventory, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "stale_files_report",
        description: "Reports source files not modified in a long time, from real file modification times.",
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
                name: "days",
                kind: "integer",
                required: false,
                description: "Staleness threshold in days. Defaults to 180.",
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
        name: "file_type_breakdown",
        description: "Reports file counts and bytes per extension across the workspace.",
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
                name: "path",
                kind: "string",
                required: false,
                description: "Directory to analyze, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "empty_dirs_find",
        description: "Finds empty directories, candidates for cleanup.",
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
                description: "Directory to search, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "symlink_audit",
        description: "Lists symbolic links with their targets, flagging broken links.",
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
                description: "Directory to audit, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "executable_files_scan",
        description: "Lists files with the executable bit set, from real file metadata.",
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
                description: "Directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "dir_size_report",
        description: "Reports recursive disk usage per subdirectory, largest first, from real file sizes.",
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
                description: "Directory to analyze, relative to the working directory. Defaults to the whole workspace.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum directories to return.",
            },
        ],
    },
    ToolDef {
        name: "image_asset_size_report",
        description: "Reports oversized images inside .xcassets catalogs, from real file sizes.",
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
                description: "Directory to scan, relative to the working directory. Defaults to the whole workspace.",
            },
            ToolParam {
                name: "maxKilobytes",
                kind: "integer",
                required: false,
                description: "Size threshold in kilobytes. Defaults to 500.",
            },
        ],
    },
    ToolDef {
        name: "bundle_resource_auditor",
        description: "Scans target app bundles for missing, duplicated, or bloated resources from pbxproj resource phases and real files.",
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
                required: false,
                description: "Relative path to project.pbxproj. Defaults to the first project.pbxproj found.",
            },
        ],
    },
    ToolDef {
        name: "core_data_model_inspector",
        description: "Inspects Core Data .xcdatamodeld models: entities, attributes, and relationships.",
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
                required: false,
                description: "File or directory to inspect, relative to the working directory. Defaults to the whole workspace.",
            },
        ],
    },
    ToolDef {
        name: "swift_data_schema_auditor",
        description: "Audits SwiftData @Model declarations, relationships, and uniqueness constraints in Swift sources.",
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
                required: false,
                description: "File or directory to audit, relative to the working directory. Defaults to the whole workspace.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum findings to return.",
            },
        ],
    },
    ToolDef {
        name: "privacy_manifest_auditor",
        description: "Audits PrivacyInfo.xcprivacy for required reasons APIs and tracking declarations. Audit only; it does not edit the manifest.",
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
                required: false,
                description: "Relative path to PrivacyInfo.xcprivacy. Defaults to the first one found.",
            },
        ],
    },
    ToolDef {
        name: "env_info",
        description: "Reports runtime facts from the live process: macOS version, CPU count, physical memory, hostname, and uptime.",
        action: "system.info",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: false,
                description: "Owning thread ID. Only used by the MCP server path.",
            },
        ],
    },
    ToolDef {
        name: "process_monitor_tool",
        description: "Monitors running processes with CPU and memory consumption from real ps output, with an optional name filter.",
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
                name: "cwd",
                kind: "string",
                required: false,
                description: "Absolute working directory for the terminal. Defaults to the thread working directory.",
            },
            ToolParam {
                name: "filter",
                kind: "string",
                required: false,
                description: "Substring filter for process names.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum processes to return.",
            },
        ],
    },
    ToolDef {
        name: "disk_space_analyzer",
        description: "Checks disk usage with real df and du output for the workspace and a chosen path.",
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
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Path to measure, relative to the working directory. Defaults to the workspace root.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Command timeout in seconds.",
            },
        ],
    },
    ToolDef {
        name: "environment_variable_manager",
        description: "Lists and reads process environment variables from the live process. The process environment cannot be mutated by a tool; set is refused with an honest error.",
        action: "system.env",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "action",
                kind: "string",
                required: true,
                description: "Action: list or get.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: false,
                description: "Variable name for get.",
            },
        ],
    },
    ToolDef {
        name: "clipboard_manager_tool",
        description: "Reads, writes, or clears the macOS system clipboard through NSPasteboard.",
        action: "system.clipboard",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "action",
                kind: "string",
                required: true,
                description: "Action: read, write, or clear.",
            },
            ToolParam {
                name: "text",
                kind: "string",
                required: false,
                description: "Text for write.",
            },
            ToolParam {
                name: "threadId",
                kind: "string",
                required: false,
                description: "Owning thread ID. Only used by the MCP server path.",
            },
        ],
    },
    ToolDef {
        name: "system_notification_tool",
        description: "Posts a macOS user notification for task completions and build events through UNUserNotificationCenter.",
        action: "system.notify",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "title",
                kind: "string",
                required: true,
                description: "Notification title.",
            },
            ToolParam {
                name: "body",
                kind: "string",
                required: false,
                description: "Notification body.",
            },
            ToolParam {
                name: "threadId",
                kind: "string",
                required: false,
                description: "Owning thread ID. Only used by the MCP server path.",
            },
        ],
    },
    ToolDef {
        name: "use_system",
        description: "Native macOS system diagnostics plus one authorized user-level mutation. Diagnostics use fixed commands only; user_defaults_write requires confirm and verifies by read-back.",
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
                name: "operation",
                kind: "string",
                required: true,
                description: "Operation: system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read, or user_defaults_write.",
            },
            ToolParam {
                name: "cwd",
                kind: "string",
                required: false,
                description: "Absolute working directory for disk_info. Defaults to the thread working directory.",
            },
            ToolParam {
                name: "filter",
                kind: "string",
                required: false,
                description: "Name filter for process_list.",
            },
            ToolParam {
                name: "interface",
                kind: "string",
                required: false,
                description: "Interface name for network_interfaces.",
            },
            ToolParam {
                name: "host",
                kind: "string",
                required: false,
                description: "Host for connectivity.",
            },
            ToolParam {
                name: "port",
                kind: "integer",
                required: false,
                description: "Port for connectivity.",
            },
            ToolParam {
                name: "minutes",
                kind: "integer",
                required: false,
                description: "Look-back minutes for system_log.",
            },
            ToolParam {
                name: "predicate",
                kind: "string",
                required: false,
                description: "Log predicate for system_log.",
            },
            ToolParam {
                name: "sysctlName",
                kind: "string",
                required: false,
                description: "Allowlisted sysctl name for config_read.",
            },
            ToolParam {
                name: "domain",
                kind: "string",
                required: false,
                description: "Defaults domain for user_defaults_write.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: false,
                description: "Defaults key for user_defaults_write.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: false,
                description: "Scalar value for user_defaults_write.",
            },
            ToolParam {
                name: "valueType",
                kind: "string",
                required: false,
                description: "Value type for user_defaults_write: string, bool, or int. Defaults to string.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: false,
                description: "Must be true for user_defaults_write.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Command timeout in seconds.",
            },
        ],
    },
    ToolDef {
        name: "search_skills",
        description: "Searches the bundled SystemAssets index of shipped guidance documents by title, filename, section, and text. It searches only that bundled index, never an external skills library.",
        action: "system.skills",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "query",
                kind: "string",
                required: true,
                description: "Search query.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum results. Defaults to 8, at most 20.",
            },
        ],
    },
    ToolDef {
        name: "plan-AskUser",
        description: "Lists pending provider questions for a thread and submits answers to them. It does not present a new question to the user and does not suspend the turn; no 300 second suspension is wired.",
        action: "agent.pending",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "requestId",
                kind: "string",
                required: false,
                description: "Pending request ID to answer. Omit to list pending questions.",
            },
            ToolParam {
                name: "answers",
                kind: "array",
                required: false,
                description: "Answers for requestId, each with questionId and an answers array of strings.",
            },
        ],
    },
    ToolDef {
        name: "tool_capability_lookup",
        description: "Live registry lookup: description, action, channel, and parameters of any registered system tool.",
        action: "system.lookup",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "tool",
                kind: "string",
                required: true,
                description: "Tool name to look up.",
            },
        ],
    },
    ToolDef {
        name: "preflight_checks",
        description: "Runs environment checks before a build: workspace writable, Xcode tools present, disk space, and artifact storage.",
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
                name: "cwd",
                kind: "string",
                required: true,
                description: "Absolute working directory.",
            },
        ],
    },
    ToolDef {
        name: "session_progress_report",
        description: "Reports engineering phases from agent_notes.md with worker status and the last agent-notes save time.",
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
                name: "threadId",
                kind: "string",
                required: false,
                description: "Parent thread ID to include worker status for.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "Relative path to agent_notes.md. Defaults to .assist_temp/artifacts/agent_notes.md.",
            },
        ],
    },
    ToolDef {
        name: "manage_memory",
        description: "Manages entries in the SQLite agent memory store: store, edit, append, delete, clear, or list keys in a scope. There are no sections and no UserMemory.md file.",
        action: "memory.store",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "action",
                kind: "string",
                required: true,
                description: "Action: store, edit, append, delete, clear, or list.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: false,
                description: "Memory key for store, edit, append, and delete.",
            },
            ToolParam {
                name: "value",
                kind: "string",
                required: false,
                description: "Value for store, edit, and append.",
            },
            ToolParam {
                name: "scope",
                kind: "string",
                required: false,
                description: "Memory scope.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: false,
                description: "Must be true for clear.",
            },
        ],
    },
    ToolDef {
        name: "fetch_documentation",
        description: "Retrieves real Apple Developer documentation pages from developer.apple.com by URL, search query, or framework landing page. Returns raw page text; it does not fabricate signatures or availability.",
        action: "web.fetch",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID. Only used by the MCP server path.",
            },
            ToolParam {
                name: "query",
                kind: "string",
                required: false,
                description: "Documentation search query.",
            },
            ToolParam {
                name: "url",
                kind: "string",
                required: false,
                description: "Documentation URL on developer.apple.com.",
            },
            ToolParam {
                name: "framework",
                kind: "string",
                required: false,
                description: "Framework name to open its documentation landing page.",
            },
        ],
    },
    ToolDef {
        name: "external_resource_gateway",
        description: "Performs an HTTPS-only GET of a JSON API and returns the parsed JSON. Non-2xx responses fail; 30 second timeout.",
        action: "web.fetch",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID. Only used by the MCP server path.",
            },
            ToolParam {
                name: "url",
                kind: "string",
                required: true,
                description: "HTTPS JSON API URL.",
            },
        ],
    },
    ToolDef {
        name: "read_url_content",
        description: "Fetches HTTPS URL content as text with status and content type. Non-2xx responses fail; 30 second timeout.",
        action: "web.fetch",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID. Only used by the MCP server path.",
            },
            ToolParam {
                name: "url",
                kind: "string",
                required: true,
                description: "HTTPS URL to fetch.",
            },
            ToolParam {
                name: "maxChars",
                kind: "integer",
                required: false,
                description: "Maximum characters to return. Defaults to 8000.",
            },
        ],
    },
    ToolDef {
        name: "github_repo",
        description: "Reads real GitHub repositories through the gh CLI: repository info, file listings, file contents, trees, code search, and tarball download. Read-only against the remote.",
        action: "github.repo",
        channel: "engine",
        params: &[
            ToolParam {
                name: "threadId",
                kind: "string",
                required: true,
                description: "Owning thread ID.",
            },
            ToolParam {
                name: "operation",
                kind: "string",
                required: true,
                description: "Operation: repository_info, list_files, get_file, get_directory, get_tree, search_code, or fetch_repository.",
            },
            ToolParam {
                name: "owner",
                kind: "string",
                required: false,
                description: "Repository owner.",
            },
            ToolParam {
                name: "repo",
                kind: "string",
                required: false,
                description: "Repository name.",
            },
            ToolParam {
                name: "url",
                kind: "string",
                required: false,
                description: "Repository URL, used when owner and repo are omitted.",
            },
            ToolParam {
                name: "ref",
                kind: "string",
                required: false,
                description: "Branch, tag, or commit. Defaults to the default branch.",
            },
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "File or directory path inside the repository.",
            },
            ToolParam {
                name: "query",
                kind: "string",
                required: false,
                description: "Code search query for search_code.",
            },
            ToolParam {
                name: "timeoutSeconds",
                kind: "integer",
                required: false,
                description: "Command timeout in seconds.",
            },
        ],
    },
    ToolDef {
        name: "use_app",
        description: "Native macOS application interaction through the real computer-use tools. Dispatches only the 20 real actions and errors honestly on activate, close_application, select_window, get_focused_element, select_all, copy, paste, wait_for_element, and wait_for_window, which have no engine tool.",
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
                name: "action",
                kind: "string",
                required: true,
                description: "Action to perform, for example list_applications, launch, click, type_text, or verify.",
            },
            ToolParam {
                name: "app_identifier",
                kind: "string",
                required: false,
                description: "Bundle ID for launch.",
            },
            ToolParam {
                name: "app_name",
                kind: "string",
                required: false,
                description: "Application name for inspect_application.",
            },
            ToolParam {
                name: "pid",
                kind: "integer",
                required: false,
                description: "Process ID of the running app.",
            },
            ToolParam {
                name: "window_id",
                kind: "integer",
                required: false,
                description: "Window ID from list_windows or get_desktop_state.",
            },
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
                name: "from_x",
                kind: "number",
                required: false,
                description: "Drag start x in window points.",
            },
            ToolParam {
                name: "from_y",
                kind: "number",
                required: false,
                description: "Drag start y in window points.",
            },
            ToolParam {
                name: "to_x",
                kind: "number",
                required: false,
                description: "Drag end x in window points.",
            },
            ToolParam {
                name: "to_y",
                kind: "number",
                required: false,
                description: "Drag end y in window points.",
            },
            ToolParam {
                name: "text",
                kind: "string",
                required: false,
                description: "Text to type, set, or find.",
            },
            ToolParam {
                name: "key",
                kind: "string",
                required: false,
                description: "Key to press: enter, escape, tab, backspace, left, right, up, or down.",
            },
            ToolParam {
                name: "keys",
                kind: "array",
                required: false,
                description: "Modifiers then one key for press_shortcut, for example cmd shift t.",
            },
            ToolParam {
                name: "direction",
                kind: "string",
                required: false,
                description: "Scroll direction: up, down, left, or right.",
            },
            ToolParam {
                name: "amount",
                kind: "integer",
                required: false,
                description: "Scroll amount, 1 to 50. Defaults to 3.",
            },
            ToolParam {
                name: "bundle_id",
                kind: "string",
                required: false,
                description: "App bundle ID for launch, for example com.apple.TextEdit.",
            },
            ToolParam {
                name: "path",
                kind: "array",
                required: false,
                description: "Menu path for select_menu, for example File New Window.",
            },
            ToolParam {
                name: "confirm",
                kind: "boolean",
                required: false,
                description: "Confirmation for destructive actions.",
            },
        ],
    },
    ToolDef {
        name: "derived_data_locate",
        description: "Locates Xcode DerivedData directories with sizes and file counts.",
        action: "system.info",
        channel: "desktop",
        params: &[
            ToolParam {
                name: "path",
                kind: "string",
                required: false,
                description: "DerivedData directory to inspect. Defaults to ~/Library/Developer/Xcode/DerivedData.",
            },
            ToolParam {
                name: "limit",
                kind: "integer",
                required: false,
                description: "Maximum directories to return.",
            },
            ToolParam {
                name: "threadId",
                kind: "string",
                required: false,
                description: "Owning thread ID. Only used by the MCP server path.",
            },
        ],
    },
    ToolDef {
        name: "build_system_detect",
        description: "Detects build systems in the workspace: xcworkspace and xcodeproj, SwiftPM, CocoaPods, Carthage, Tuist, xcodegen, Bazel, and CMake.",
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
                name: "path",
                kind: "string",
                required: false,
                description: "Directory to inspect, relative to the working directory. Defaults to the whole workspace.",
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
    let response = state
        .control
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .call(&json!({"method": method, "params": params}))
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

fn g3_command(argv: &[String]) -> String {
    argv.iter()
        .map(|arg| shell_quote(arg))
        .collect::<Vec<_>>()
        .join(" ")
}

fn g3_run(
    state: &crate::ServerState,
    thread_id: &str,
    cwd: &str,
    argv: &[String],
    timeout_seconds: u64,
) -> Result<(i64, String), CallError> {
    run_shell_status(state, thread_id, cwd, &g3_command(argv), timeout_seconds)
}

fn g3_missing_cli(cli: &str, exit_code: i64, output: &str) -> Result<(), CallError> {
    if exit_code == 127
        || output.contains("command not found")
        || output.contains("unable to find utility")
    {
        return Err(failed(format!("{cli} is not installed on this machine.")));
    }
    Ok(())
}

fn g3_token(value: &str, field: &str, tool: &str) -> Result<(), CallError> {
    if value.is_empty()
        || value.contains('\n')
        || value.contains('\r')
        || value.starts_with('-')
    {
        return Err(failed(format!(
            "Tool \"{tool}\" {field} must be a non-empty value without newlines or a leading dash."
        )));
    }
    Ok(())
}

fn g3_identifier(value: &str, field: &str, tool: &str) -> Result<(), CallError> {
    if value.is_empty()
        || !value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.' || c == '-')
    {
        return Err(failed(format!(
            "Tool \"{tool}\" {field} must use only letters, digits, underscore, dot, or dash."
        )));
    }
    Ok(())
}

fn g3_test_identifier(value: &str, tool: &str) -> Result<(), CallError> {
    let ok = !value.is_empty()
        && !value.starts_with('-')
        && !value.contains('\n')
        && !value.contains('\r')
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '/' | '-'))
        && value
            .split('/')
            .all(|part| !part.is_empty() && part != "." && part != "..");
    if !ok {
        return Err(failed(format!(
            "Tool \"{tool}\" testIdentifier must be a slash-separated test path using letters, digits, underscore, dot, dash, or slash."
        )));
    }
    Ok(())
}

fn g3_relative_path(path: &str, tool: &str) -> Result<(), CallError> {
    if path.is_empty()
        || path.starts_with('/')
        || path.split('/').any(|part| part == ".." || part == ".")
    {
        return Err(failed(format!(
            "Tool \"{tool}\" path must be relative without dot or parent components."
        )));
    }
    Ok(())
}

fn g3_json_text(output: &str) -> &str {
    for line in output.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('{') || trimmed.starts_with('[') {
            if let Some(at) = output.find(trimmed) {
                return &output[at..];
            }
        }
    }
    output
}

fn g3_parse_json(output: &str, tool: &str) -> Result<Value, CallError> {
    serde_json::from_str(g3_json_text(output))
        .map_err(|error| failed(format!("Tool \"{tool}\" command output was not valid JSON: {error}")))
}

fn g3_diagnostics(output: &str) -> Vec<Value> {
    let mut diagnostics: Vec<Value> = Vec::new();
    for raw_line in output.lines() {
        let line = raw_line.trim();
        let mut matched = false;
        for severity in ["error", "warning", "note"] {
            let marker = format!(": {severity}: ");
            if let Some(at) = line.find(&marker) {
                let head = &line[..at];
                let message = &line[at + marker.len()..];
                let parts: Vec<&str> = head.split(':').collect();
                let mut path = head.to_owned();
                let mut line_number = 0i64;
                let mut column = 0i64;
                if parts.len() >= 3 {
                    if let (Ok(parsed_line), Ok(parsed_column)) = (
                        parts[parts.len() - 2].parse::<i64>(),
                        parts[parts.len() - 1].parse::<i64>(),
                    ) {
                        line_number = parsed_line;
                        column = parsed_column;
                        path = parts[..parts.len() - 2].join(":");
                    }
                } else if parts.len() >= 2 {
                    if let Ok(parsed_line) = parts[parts.len() - 1].parse::<i64>() {
                        line_number = parsed_line;
                        path = parts[..parts.len() - 1].join(":");
                    }
                }
                diagnostics.push(json!({"path": path, "line": line_number, "column": column, "severity": severity, "message": message}));
                matched = true;
                break;
            }
        }
        if matched {
            continue;
        }
        for severity in ["error", "warning", "note"] {
            let prefix = format!("{severity}: ");
            if let Some(message) = line.strip_prefix(&prefix) {
                diagnostics.push(json!({"path": "", "line": 0, "column": 0, "severity": severity, "message": message}));
                break;
            }
        }
    }
    diagnostics
}

fn g3_test_summary(output: &str) -> (i64, i64, i64, i64) {
    let mut executed = 0i64;
    let mut failed = 0i64;
    let mut suites_passed = 0i64;
    let mut suites_failed = 0i64;
    for raw_line in output.lines() {
        let line = raw_line.trim();
        if let Some(rest) = line.strip_prefix("Executed ") {
            let fields: Vec<&str> = rest.split(' ').collect();
            if fields.len() >= 2 {
                if let Ok(count) = fields[1].parse::<i64>() {
                    executed += count;
                }
            }
            if let Some(with_at) = line.find("with ") {
                if let Some(fail_at) = line.find(" failures") {
                    let count_text = line[with_at + "with ".len()..fail_at].trim();
                    if let Ok(count) = count_text.parse::<i64>() {
                        failed += count;
                    }
                }
            }
        } else if line.starts_with("Test Suite '") {
            if line.contains("' passed at ") {
                suites_passed += 1;
            } else if line.contains("' failed at ") {
                suites_failed += 1;
            }
        }
    }
    (executed, failed, suites_passed, suites_failed)
}

fn g3_build_settings(output: &str) -> Vec<Value> {
    let mut sections: Vec<Value> = Vec::new();
    let mut current_target = String::new();
    let mut current: serde_json::Map<String, Value> = serde_json::Map::new();
    let mut current_key: Option<String> = None;
    for line in output.lines() {
        if line.starts_with("Build settings for action ") {
            if !current.is_empty() {
                sections.push(json!({"target": current_target, "settings": current}));
                current = serde_json::Map::new();
            }
            current_key = None;
            if let Some(start) = line.find("target \"") {
                let rest = &line[start + "target \"".len()..];
                current_target = rest.split('"').next().unwrap_or("").to_owned();
            } else {
                current_target = String::new();
            }
            continue;
        }
        if line.starts_with("    ") && !line.starts_with("     ") {
            let stripped = line.trim();
            if let Some(eq) = stripped.find(" = ") {
                let key = stripped[..eq].to_owned();
                let value = stripped[eq + " = ".len()..].to_owned();
                current.insert(key.clone(), json!(value));
                current_key = Some(key);
                continue;
            }
        }
        if let Some(key) = &current_key {
            if line.starts_with(' ') || line.starts_with('\t') {
                let stripped = line.trim();
                if !stripped.is_empty() {
                    let existing = current
                        .get(key)
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_owned();
                    current.insert(key.clone(), json!(format!("{existing} {stripped}")));
                }
            }
        }
    }
    if !current.is_empty() {
        sections.push(json!({"target": current_target, "settings": current}));
    }
    sections
}

fn g3_xcodebuild_list(value: &Value) -> (Vec<String>, Vec<String>, Vec<String>, String) {
    let project = &value["project"];
    let strings = |key: &str| -> Vec<String> {
        project[key]
            .as_array()
            .map(|items| {
                items
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_owned)
                    .collect()
            })
            .unwrap_or_default()
    };
    (
        strings("schemes"),
        strings("targets"),
        strings("configurations"),
        project["name"].as_str().unwrap_or("").to_owned(),
    )
}

fn g3_coverage(value: &Value) -> Vec<Value> {
    let mut targets: Vec<Value> = Vec::new();
    for target in value["targets"].as_array().cloned().unwrap_or_default() {
        let mut entry = serde_json::Map::new();
        if let Some(name) = target["name"].as_str() {
            entry.insert("name".to_owned(), json!(name));
        }
        if let Some(coverage) = target["lineCoverage"].as_f64() {
            entry.insert("lineCoverage".to_owned(), json!(coverage));
        }
        if let Some(covered) = target["coveredLines"].as_i64() {
            entry.insert("coveredLines".to_owned(), json!(covered));
        }
        if let Some(executable) = target["executableLines"].as_i64() {
            entry.insert("executableLines".to_owned(), json!(executable));
        }
        if !entry.is_empty() {
            targets.push(Value::Object(entry));
        }
    }
    targets
}

fn g3_destinations(output: &str) -> Vec<Value> {
    let mut destinations: Vec<Value> = Vec::new();
    for line in output.lines() {
        let trimmed = line.trim();
        if !trimmed.starts_with('{') || !trimmed.ends_with('}') {
            continue;
        }
        let inner = &trimmed[1..trimmed.len() - 1];
        let mut fields: Vec<String> = Vec::new();
        let mut depth = 0i64;
        let mut current = String::new();
        for ch in inner.chars() {
            if ch == '[' {
                depth += 1;
            }
            if ch == ']' {
                depth -= 1;
            }
            if ch == ',' && depth == 0 {
                fields.push(std::mem::take(&mut current));
            } else {
                current.push(ch);
            }
        }
        if !current.trim().is_empty() {
            fields.push(current);
        }
        let mut record = serde_json::Map::new();
        for field in fields {
            if let Some((key, value)) = field.split_once(':') {
                let key = key.trim();
                let value = value.trim();
                if !key.is_empty() {
                    record.insert(key.to_owned(), json!(value));
                }
            }
        }
        if !record.is_empty() {
            destinations.push(Value::Object(record));
        }
    }
    destinations
}

fn g3_simctl_devices(value: &Value) -> Vec<Value> {
    let mut devices: Vec<Value> = Vec::new();
    let Some(runtimes) = value["devices"].as_object() else {
        return devices;
    };
    let mut keys: Vec<&String> = runtimes.keys().collect();
    keys.sort();
    for runtime in keys {
        for device in runtimes[runtime.as_str()].as_array().cloned().unwrap_or_default() {
            let mut entry = serde_json::Map::new();
            entry.insert("udid".to_owned(), json!(device["udid"].as_str().unwrap_or("")));
            entry.insert("name".to_owned(), json!(device["name"].as_str().unwrap_or("")));
            entry.insert("state".to_owned(), json!(device["state"].as_str().unwrap_or("")));
            entry.insert("runtime".to_owned(), json!(runtime));
            entry.insert(
                "isAvailable".to_owned(),
                json!(device["isAvailable"].as_bool().unwrap_or(false)),
            );
            if let Some(type_id) = device["deviceTypeIdentifier"].as_str() {
                entry.insert("deviceTypeIdentifier".to_owned(), json!(type_id));
            }
            devices.push(Value::Object(entry));
        }
    }
    devices
}

fn g3_xcode_version(output: &str) -> (String, String) {
    let mut version = String::new();
    let mut build = String::new();
    for line in output.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("Xcode ") {
            version = rest.to_owned();
        }
        if let Some(rest) = trimmed.strip_prefix("Build version ") {
            build = rest.to_owned();
        }
    }
    (version, build)
}

fn g3_codesign(output: &str) -> Value {
    let mut details = serde_json::Map::new();
    let mut authorities: Vec<Value> = Vec::new();
    for line in output.lines() {
        if let Some((key, value)) = line.split_once('=') {
            let key = key.trim();
            let value = value.trim();
            if key.is_empty() || value.is_empty() {
                continue;
            }
            if key == "Authority" {
                authorities.push(json!(value));
            } else {
                details.insert(key.to_owned(), json!(value));
            }
        }
    }
    if !authorities.is_empty() {
        details.insert("Authority".to_owned(), json!(authorities));
    }
    Value::Object(details)
}

fn g3_otool_libraries(output: &str) -> Vec<String> {
    let mut libraries: Vec<String> = Vec::new();
    for line in output.lines().skip(1) {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some((path, _)) = trimmed.split_once('(') {
            libraries.push(path.trim().to_owned());
        } else {
            libraries.push(trimmed.to_owned());
        }
    }
    libraries
}

fn g3_mach_headers(output: &str) -> Vec<Value> {
    let mut headers: Vec<Value> = Vec::new();
    let mut saw_header = false;
    for line in output.lines() {
        let trimmed = line.trim();
        if trimmed == "Mach header" || trimmed.starts_with("magic ") {
            saw_header = true;
            continue;
        }
        if saw_header {
            let fields: Vec<&str> = trimmed
                .split(' ')
                .filter(|part| !part.is_empty())
                .collect();
            if fields.len() >= 5 {
                headers.push(json!({"magic": fields[0], "cputype": fields[1], "filetype": fields[4]}));
            }
            saw_header = false;
        }
    }
    headers
}

fn g3_identities(output: &str) -> Vec<Value> {
    let mut identities: Vec<Value> = Vec::new();
    for line in output.lines() {
        let trimmed = line.trim();
        let Some((index_text, rest)) = trimmed.split_once(')') else {
            continue;
        };
        let Ok(index) = index_text.trim().parse::<i64>() else {
            continue;
        };
        let rest = rest.trim();
        let Some((hash, name)) = rest.split_once(' ') else {
            continue;
        };
        let name = name.trim().trim_matches('"');
        identities.push(json!({"index": index, "hash": hash, "name": name}));
    }
    identities
}

fn g3_ast_decl_counts(output: &str) -> (serde_json::Map<String, Value>, i64) {
    let mut counts: serde_json::Map<String, Value> = serde_json::Map::new();
    let mut total = 0i64;
    for line in output.lines() {
        let trimmed = line.trim();
        if !trimmed.starts_with('(') {
            continue;
        }
        let name = trimmed[1..].split(' ').next().unwrap_or("");
        if !name.ends_with("_decl") {
            continue;
        }
        let entry = counts.entry(name.to_owned()).or_insert(json!(0));
        *entry = json!(entry.as_i64().unwrap_or(0) + 1);
        total += 1;
    }
    (counts, total)
}

fn g3_du_sizes(output: &str) -> Vec<(String, i64)> {
    let mut sizes: Vec<(String, i64)> = Vec::new();
    for line in output.lines() {
        if let Some((size_text, path)) = line.split_once('\t') {
            if let Ok(size) = size_text.trim().parse::<i64>() {
                sizes.push((path.to_owned(), size));
            }
        }
    }
    sizes
}

struct G5PatternSpec {
    label: &'static str,
    pattern: &'static str,
    redact: bool,
    capture: usize,
}

struct G5ScanSpec {
    shape: &'static str,
    literal: bool,
    sample_limit: usize,
    patterns: &'static [G5PatternSpec],
}

fn g5_scan_spec(name: &str) -> Option<G5ScanSpec> {
    match name {
        "search_symbol" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "function", pattern: "func\\s+{symbol}\\b", redact: false, capture: 0 }, G5PatternSpec { label: "type", pattern: "(class|struct|enum|protocol)\\s+{symbol}\\b", redact: false, capture: 0 }, G5PatternSpec { label: "variable", pattern: "(let|var)\\s+{symbol}\\b", redact: false, capture: 0 }, G5PatternSpec { label: "typealias", pattern: "typealias\\s+{symbol}\\b", redact: false, capture: 0 }] }),
        "dependency_graph" => Some(G5ScanSpec { shape: "files", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "import", pattern: "^import\\s+([A-Za-z0-9_]+)", redact: false, capture: 1 }] }),
        "source_graph_builder" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "import", pattern: "^import\\s+([A-Za-z0-9_]+)", redact: false, capture: 1 }, G5PatternSpec { label: "type", pattern: "(class|struct|enum|protocol)\\s+([A-Za-z0-9_]+)", redact: false, capture: 2 }] }),
        "semantic_query_engine" => Some(G5ScanSpec { shape: "flat", literal: true, sample_limit: 0, patterns: &[G5PatternSpec { label: "match", pattern: "{query}", redact: false, capture: 0 }] }),
        "autonomous_review_engine" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "forceUnwrap", pattern: "[A-Za-z0-9_\\)\\]]![^=!]", redact: false, capture: 0 }, G5PatternSpec { label: "tryBang", pattern: "try!", redact: false, capture: 0 }, G5PatternSpec { label: "asBang", pattern: "as!", redact: false, capture: 0 }, G5PatternSpec { label: "mainSync", pattern: "DispatchQueue\\.main\\.sync", redact: false, capture: 0 }, G5PatternSpec { label: "fatal", pattern: "fatalError|precondition\\(", redact: false, capture: 0 }] }),
        "memory_leak_detector" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "unownedSelf", pattern: "\\[unowned self\\]", redact: false, capture: 0 }, G5PatternSpec { label: "strongSelf", pattern: "\\[self\\]", redact: false, capture: 0 }, G5PatternSpec { label: "delegateAssign", pattern: "\\.delegate\\s*=", redact: false, capture: 0 }, G5PatternSpec { label: "scheduledTimer", pattern: "Timer\\.scheduledTimer", redact: false, capture: 0 }, G5PatternSpec { label: "observer", pattern: "NotificationCenter\\.default\\.addObserver", redact: false, capture: 0 }] }),
        "todo_scan" => Some(G5ScanSpec { shape: "flat", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "todo", pattern: "\\b(TODO|FIXME|XXX|HACK)\\b", redact: false, capture: 0 }] }),
        "todo_fixme_scanner" => Some(G5ScanSpec { shape: "flat", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "todo", pattern: "\\b(TODO|FIXME|HACK|NOTE)\\b", redact: false, capture: 0 }] }),
        "api_surface_extract" => Some(G5ScanSpec { shape: "files", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "declaration", pattern: "\\b(public|open)\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0 }] }),
        "access_level_audit" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "public", pattern: "\\bpublic\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0 }, G5PatternSpec { label: "open", pattern: "\\bopen\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0 }, G5PatternSpec { label: "internal", pattern: "\\binternal\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0 }, G5PatternSpec { label: "private", pattern: "\\bprivate\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0 }, G5PatternSpec { label: "fileprivate", pattern: "\\bfileprivate\\s+(func|class|struct|enum|protocol|var|let|typealias)\\b", redact: false, capture: 0 }] }),
        "concurrency_audit" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "mainSync", pattern: "DispatchQueue\\.main\\.sync", redact: false, capture: 0 }, G5PatternSpec { label: "nonisolatedUnsafe", pattern: "nonisolated\\(unsafe\\)", redact: false, capture: 0 }, G5PatternSpec { label: "task", pattern: "Task\\s*\\{", redact: false, capture: 0 }, G5PatternSpec { label: "sharedMutableStatic", pattern: "static\\s+(let|var)\\s+[A-Za-z0-9_]+\\s*[:=]", redact: false, capture: 0 }, G5PatternSpec { label: "syncBlock", pattern: "\\.sync\\s*\\{", redact: false, capture: 0 }] }),
        "swift_concurrency_analyzer" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "nonisolated", pattern: "nonisolated", redact: false, capture: 0 }, G5PatternSpec { label: "mainActor", pattern: "@MainActor", redact: false, capture: 0 }, G5PatternSpec { label: "actor", pattern: "\\bactor\\s+[A-Za-z0-9_]+", redact: false, capture: 0 }, G5PatternSpec { label: "sendable", pattern: "Sendable", redact: false, capture: 0 }, G5PatternSpec { label: "detached", pattern: "Task\\.detached", redact: false, capture: 0 }] }),
        "swift_migration_advisor" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "dispatchQueue", pattern: "DispatchQueue", redact: false, capture: 0 }, G5PatternSpec { label: "lock", pattern: "NSLock|os_unfair_lock", redact: false, capture: 0 }, G5PatternSpec { label: "mutableGlobal", pattern: "static\\s+var\\s+[A-Za-z0-9_]+", redact: false, capture: 0 }, G5PatternSpec { label: "uncheckedSendable", pattern: "@unchecked Sendable", redact: false, capture: 0 }, G5PatternSpec { label: "nonisolatedUnsafe", pattern: "nonisolated\\(unsafe\\)", redact: false, capture: 0 }] }),
        "security_audit_scanner" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "plainHttp", pattern: "http://[^ \\t\\\"'\\)]+", redact: false, capture: 0 }, G5PatternSpec { label: "apiKey", pattern: "api_key\\s*[:=]", redact: true, capture: 0 }, G5PatternSpec { label: "password", pattern: "password\\s*[:=]", redact: true, capture: 0 }, G5PatternSpec { label: "awsKey", pattern: "AKIA[0-9A-Z]{16}", redact: true, capture: 0 }, G5PatternSpec { label: "bearer", pattern: "Bearer\\s+[A-Za-z0-9\\-_\\.]+", redact: true, capture: 0 }] }),
        "secrets_scan" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "awsKey", pattern: "AKIA[0-9A-Z]{16}", redact: true, capture: 0 }, G5PatternSpec { label: "githubToken", pattern: "ghp_[A-Za-z0-9]{20,}", redact: true, capture: 0 }, G5PatternSpec { label: "skKey", pattern: "sk-[A-Za-z0-9]{20,}", redact: true, capture: 0 }, G5PatternSpec { label: "apiKey", pattern: "api_key\\s*[:=]", redact: true, capture: 0 }, G5PatternSpec { label: "password", pattern: "password\\s*[:=]", redact: true, capture: 0 }, G5PatternSpec { label: "privateKey", pattern: "BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY", redact: true, capture: 0 }, G5PatternSpec { label: "slackToken", pattern: "xox[baprs]-[A-Za-z0-9\\-]{10,}", redact: true, capture: 0 }] }),
        "network_security_auditor" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "plainHttp", pattern: "http://[^ \\t\\\"'\\)]+", redact: false, capture: 0 }, G5PatternSpec { label: "ats", pattern: "NSAppTransportSecurity", redact: false, capture: 0 }, G5PatternSpec { label: "arbitraryLoads", pattern: "NSAllowsArbitraryLoads", redact: false, capture: 0 }, G5PatternSpec { label: "localNetworking", pattern: "NSAllowsLocalNetworking", redact: false, capture: 0 }, G5PatternSpec { label: "pinning", pattern: "SecTrust|certificatePinning|pinnedCertificate", redact: false, capture: 0 }] }),
        "permissions_audit" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "usageDescription", pattern: "UsageDescription", redact: false, capture: 0 }, G5PatternSpec { label: "privacyInfo", pattern: "NSPrivacy", redact: false, capture: 0 }, G5PatternSpec { label: "entitlement", pattern: "com\\.apple\\.security", redact: false, capture: 0 }, G5PatternSpec { label: "sensitiveEntitlement", pattern: "get-task-allow|application-identifier", redact: false, capture: 0 }] }),
        "accessibility_audit" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "button", pattern: "Button\\(", redact: false, capture: 0 }, G5PatternSpec { label: "image", pattern: "Image\\(", redact: false, capture: 0 }, G5PatternSpec { label: "textField", pattern: "TextField\\(", redact: false, capture: 0 }, G5PatternSpec { label: "label", pattern: "\\.accessibilityLabel\\(", redact: false, capture: 0 }, G5PatternSpec { label: "hint", pattern: "\\.accessibilityHint\\(", redact: false, capture: 0 }, G5PatternSpec { label: "value", pattern: "\\.accessibilityValue\\(", redact: false, capture: 0 }] }),
        "accessibility_audit_scanner" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "label", pattern: "\\.accessibilityLabel\\(", redact: false, capture: 0 }, G5PatternSpec { label: "hint", pattern: "\\.accessibilityHint\\(", redact: false, capture: 0 }, G5PatternSpec { label: "traits", pattern: "\\.accessibilityAddTraits\\(", redact: false, capture: 0 }, G5PatternSpec { label: "hidden", pattern: "\\.accessibilityHidden\\(", redact: false, capture: 0 }, G5PatternSpec { label: "identifier", pattern: "\\.accessibilityIdentifier\\(", redact: false, capture: 0 }] }),
        "interface_simulator" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 5, patterns: &[G5PatternSpec { label: "label", pattern: "\\.accessibilityLabel\\(", redact: false, capture: 0 }, G5PatternSpec { label: "dynamicType", pattern: "\\.dynamicTypeSize\\(", redact: false, capture: 0 }, G5PatternSpec { label: "font", pattern: "\\.font\\(", redact: false, capture: 0 }, G5PatternSpec { label: "button", pattern: "Button\\(", redact: false, capture: 0 }, G5PatternSpec { label: "fixedFrame", pattern: "\\.frame\\(width", redact: false, capture: 0 }, G5PatternSpec { label: "color", pattern: "\\.foregroundColor\\(|Color\\(", redact: false, capture: 0 }] }),
        "force_unwrap_scan" => Some(G5ScanSpec { shape: "flat", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "forceUnwrap", pattern: "[A-Za-z0-9_\\)\\]]![^=!]", redact: false, capture: 0 }, G5PatternSpec { label: "tryBang", pattern: "try!", redact: false, capture: 0 }, G5PatternSpec { label: "asBang", pattern: "as!", redact: false, capture: 0 }] }),
        "string_literal_audit" => Some(G5ScanSpec { shape: "flat", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "stringLiteral", pattern: "\"[^\"]{8,}\"", redact: false, capture: 0 }] }),
        "call_hierarchy" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "definition", pattern: "(func|init)\\s+{function}\\b", redact: false, capture: 0 }, G5PatternSpec { label: "callSite", pattern: "\\b{function}\\s*\\(", redact: false, capture: 0 }] }),
        "type_hierarchy" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "type", pattern: "(class|struct|enum|protocol)\\s+([A-Za-z0-9_]+)(\\s*:\\s*[^{]+)?", redact: false, capture: 2 }] }),
        "protocol_conformance_list" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "conformance", pattern: "(class|struct|enum)\\s+([A-Za-z0-9_]+)\\s*:[^{]*\\b{protocol}\\b", redact: false, capture: 2 }] }),
        "import_graph" => Some(G5ScanSpec { shape: "files", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "import", pattern: "^import\\s+([A-Za-z0-9_]+)", redact: false, capture: 1 }] }),
        "change_impact_estimate" => Some(G5ScanSpec { shape: "flat", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "reference", pattern: "\\b{symbol}\\b", redact: false, capture: 0 }] }),
        "conflict_marker_scan" => Some(G5ScanSpec { shape: "flat", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "marker", pattern: "^(<{7}|={7}|>{7}|\\|{7})", redact: false, capture: 0 }] }),
        "deprecation_usage_scan" => Some(G5ScanSpec { shape: "flat", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "deprecated", pattern: "\\bdeprecated\\b", redact: false, capture: 0 }] }),
        "api_endpoint_audit" => Some(G5ScanSpec { shape: "host", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "url", pattern: "https?://([A-Za-z0-9.\\-]+)", redact: false, capture: 1 }] }),
        "color_usage_audit" => Some(G5ScanSpec { shape: "flat", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "color", pattern: "Color\\(|UIColor\\(|NSColor\\(|#[0-9A-Fa-f]{6}\\b", redact: false, capture: 0 }] }),
        "xctest_discovery" => Some(G5ScanSpec { shape: "patterns", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "testClass", pattern: "class\\s+([A-Za-z0-9_]+)\\s*:\\s*XCTestCase", redact: false, capture: 1 }, G5PatternSpec { label: "testMethod", pattern: "func\\s+(test[A-Za-z0-9_]*)\\s*\\(", redact: false, capture: 1 }] }),
        "code_comment_extract" => Some(G5ScanSpec { shape: "flat", literal: false, sample_limit: 0, patterns: &[G5PatternSpec { label: "comment", pattern: "///|/\\*\\*", redact: false, capture: 0 }] }),
        _ => None,
    }
}

fn g5_regex(pattern: &str) -> Option<regex::Regex> {
    regex::RegexBuilder::new(pattern)
        .multi_line(true)
        .build()
        .ok()
}

fn g5_regex_captures(pattern: &str, text: &str) -> Vec<Vec<Option<String>>> {
    let Some(regex) = g5_regex(pattern) else {
        return Vec::new();
    };
    regex
        .captures_iter(text)
        .map(|caps| {
            (0..caps.len())
                .map(|index| caps.get(index).map(|m| m.as_str().to_owned()))
                .collect()
        })
        .collect()
}

fn g5_first_capture(pattern: &str, text: &str, group: usize) -> Option<String> {
    let matches = g5_regex_captures(pattern, text);
    let first = matches.first()?;
    if group >= first.len() {
        return None;
    }
    first[group].clone()
}

fn g5_escape_regex(value: &str) -> String {
    regex::escape(value)
}

fn g5_lines(content: &str) -> Vec<&str> {
    content.lines().collect()
}

fn g5_count_substring(text: &str, needle: &str) -> usize {
    if needle.is_empty() {
        return 0;
    }
    text.matches(needle).count()
}

fn g5_count_word(text: &str, word: &str) -> usize {
    let pattern = format!(r"\b{}\b", g5_escape_regex(word));
    g5_regex_captures(&pattern, text).len()
}

fn g5_file_counts(content: &str) -> (usize, usize, usize, usize) {
    let lines = g5_lines(content);
    let mut code = 0usize;
    let mut comment = 0usize;
    let mut blank = 0usize;
    let mut in_block = false;
    for line in &lines {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            blank += 1;
            continue;
        }
        if in_block {
            comment += 1;
            if trimmed.contains("*/") {
                in_block = false;
            }
            continue;
        }
        if trimmed.starts_with("//") || trimmed.starts_with('*') {
            comment += 1;
            continue;
        }
        if trimmed.starts_with("/*") {
            comment += 1;
            if !trimmed.contains("*/") {
                in_block = true;
            }
            continue;
        }
        code += 1;
    }
    (lines.len(), code, comment, blank)
}

fn g5_search_regex_hits(cwd: &str, pattern: &str, limit: u64) -> Result<Vec<(String, i64, String)>, CallError> {
    let value = coincide_core::workspace_tools::search_regex(
        &json!({"cwd": cwd, "pattern": pattern, "limit": limit}),
    )
    .map_err(|error| failed(error.to_string()))?;
    Ok(g5_hits_from_value(&value))
}

fn g5_search_hits(cwd: &str, query: &str, limit: u64) -> Result<Vec<(String, i64, String)>, CallError> {
    let value = coincide_core::workspace_tools::search(
        &json!({"cwd": cwd, "query": query, "limit": limit}),
    )
    .map_err(|error| failed(error.to_string()))?;
    Ok(g5_hits_from_value(&value))
}

fn g5_hits_from_value(value: &Value) -> Vec<(String, i64, String)> {
    let mut hits = Vec::new();
    for hit in value["matches"].as_array().cloned().unwrap_or_default() {
        let path = hit["path"].as_str().unwrap_or("").to_owned();
        let line = hit["line"].as_i64().unwrap_or(1);
        let text = hit["text"].as_str().unwrap_or("").to_owned();
        hits.push((path, line, text));
    }
    hits
}

fn g5_scope_hits(
    hits: Vec<(String, i64, String)>,
    scope: Option<&str>,
) -> Vec<(String, i64, String)> {
    let Some(scope) = scope.filter(|s| !s.is_empty()) else {
        return hits;
    };
    hits.into_iter()
        .filter(|(path, _, _)| path == scope || path.starts_with(&format!("{scope}/")))
        .collect()
}

fn g5_hit_json(path: &str, line: i64, text: &str, redact: bool) -> Value {
    if redact {
        json!({"path": path, "lineNumber": line})
    } else {
        json!({"path": path, "lineNumber": line, "lineText": text})
    }
}

fn g5_capture_values(pattern: &G5PatternSpec, hits: &[(String, i64, String)]) -> Vec<String> {
    if pattern.capture == 0 {
        return Vec::new();
    }
    let mut values: Vec<String> = Vec::new();
    for (_, _, text) in hits {
        if let Some(value) = g5_first_capture(pattern.pattern, text, pattern.capture) {
            if !values.contains(&value) {
                values.push(value);
            }
        }
    }
    values
}

fn g5_group_json(
    label: &str,
    hits: &[(String, i64, String)],
    values: &[String],
    redact: bool,
    sample_limit: usize,
) -> Value {
    let mut seen: Vec<(String, i64)> = Vec::new();
    let mut unique: Vec<(String, i64, String)> = Vec::new();
    for hit in hits {
        let key = (hit.0.clone(), hit.1);
        if !seen.contains(&key) {
            seen.push(key);
            unique.push(hit.clone());
        }
    }
    let count = unique.len();
    let shown: Vec<&(String, i64, String)> = if sample_limit > 0 {
        unique.iter().take(sample_limit).collect()
    } else {
        unique.iter().collect()
    };
    json!({
        "label": label,
        "count": count,
        "matches": shown.iter().map(|hit| g5_hit_json(&hit.0, hit.1, &hit.2, redact)).collect::<Vec<_>>(),
        "values": values,
    })
}

fn g5_pattern_group_json(
    spec: &G5ScanSpec,
    pattern: &G5PatternSpec,
    hits: &[(String, i64, String)],
) -> Value {
    match spec.shape {
        "files" => {
            let mut order: Vec<String> = Vec::new();
            let mut by_file: Vec<(String, Vec<(String, i64, String)>)> = Vec::new();
            for hit in hits {
                if let Some(entry) = by_file.iter_mut().find(|(path, _)| path == &hit.0) {
                    entry.1.push(hit.clone());
                } else {
                    order.push(hit.0.clone());
                    by_file.push((hit.0.clone(), vec![hit.clone()]));
                }
            }
            let mut groups: Vec<Value> = Vec::new();
            let mut all_values: Vec<String> = Vec::new();
            for file in &order {
                let file_hits = by_file
                    .iter()
                    .find(|(path, _)| path == file)
                    .map(|(_, hits)| hits.clone())
                    .unwrap_or_default();
                let values = g5_capture_values(pattern, &file_hits);
                for value in &values {
                    if !all_values.contains(value) {
                        all_values.push(value.clone());
                    }
                }
                groups.push(g5_group_json(file, &file_hits, &values, pattern.redact, spec.sample_limit));
            }
            json!({"label": pattern.label, "count": hits.len(), "files": groups, "values": all_values})
        }
        "host" => {
            let mut order: Vec<String> = Vec::new();
            let mut by_host: Vec<(String, Vec<(String, i64, String)>)> = Vec::new();
            for hit in hits {
                let host = g5_capture_values(pattern, std::slice::from_ref(hit))
                    .first()
                    .cloned()
                    .unwrap_or_default();
                if let Some(entry) = by_host.iter_mut().find(|(name, _)| name == &host) {
                    entry.1.push(hit.clone());
                } else {
                    order.push(host.clone());
                    by_host.push((host, vec![hit.clone()]));
                }
            }
            let mut groups: Vec<Value> = Vec::new();
            for host in &order {
                let host_hits = by_host
                    .iter()
                    .find(|(name, _)| name == host)
                    .map(|(_, hits)| hits.clone())
                    .unwrap_or_default();
                groups.push(g5_group_json(host, &host_hits, &[], pattern.redact, spec.sample_limit));
            }
            json!({"label": pattern.label, "count": hits.len(), "hosts": groups})
        }
        _ => {
            let values = g5_capture_values(pattern, hits);
            g5_group_json(pattern.label, hits, &values, pattern.redact, spec.sample_limit)
        }
    }
}

fn g5_run_scan(state: &crate::ServerState, name: &str, args: &Value) -> Result<Value, CallError> {
    let _ = state;
    let Some(spec) = g5_scan_spec(name) else {
        return Err(failed(format!("Unknown G5 scan tool {name}.")));
    };
    let cwd = req_str(args, "cwd", name)?;
    let scope = opt_str(args, "path");
    let limit = opt_u64(args, "limit").unwrap_or(200).clamp(1, 1000);
    let mut groups: Vec<Value> = Vec::new();
    let mut total_matches = 0usize;
    let mut truncated = false;
    if spec.literal {
        let query = req_str(args, "query", name)?;
        let hits = g5_search_hits(&cwd, &query, limit)?;
        let scoped = g5_scope_hits(hits, scope.as_deref());
        total_matches = scoped.len();
        truncated = scoped.len() as u64 >= limit;
        groups.push(g5_group_json("matches", &scoped, &[], false, 0));
    } else {
        for pattern in spec.patterns {
            let mut pattern_text = pattern.pattern.to_owned();
            for key in ["symbol", "function", "protocol"] {
                if let Some(value) = opt_str(args, key) {
                    pattern_text = pattern_text.replace(&format!("{{{key}}}"), &g5_escape_regex(&value));
                }
            }
            if pattern_text.contains("{symbol}") {
                return Err(failed("search_symbol requires symbol.".to_owned()));
            }
            if pattern_text.contains("{function}") {
                return Err(failed("call_hierarchy requires function.".to_owned()));
            }
            if pattern_text.contains("{protocol}") {
                return Err(failed("protocol_conformance_list requires protocol.".to_owned()));
            }
            let hits = g5_search_regex_hits(&cwd, &pattern_text, limit)?;
            let scoped = g5_scope_hits(hits, scope.as_deref());
            if scoped.len() as u64 >= limit {
                truncated = true;
            }
            total_matches += scoped.len();
            groups.push(g5_pattern_group_json(&spec, pattern, &scoped));
        }
    }
    if name == "code_comment_extract" {
        if let Some(symbol) = opt_str(args, "symbol") {
            let symbol_hits = g5_search_hits(&cwd, &symbol, limit)?;
            let symbol_files: Vec<String> = symbol_hits.into_iter().map(|(path, _, _)| path).collect();
            let mut kept_total = 0usize;
            groups = groups
                .into_iter()
                .map(|group| {
                    let mut group = group;
                    if let Some(matches) = group["matches"].as_array().cloned() {
                        let kept: Vec<Value> = matches
                            .into_iter()
                            .filter(|hit| {
                                hit["path"]
                                    .as_str()
                                    .map_or(false, |path| symbol_files.iter().any(|f| f == path))
                            })
                            .collect();
                        kept_total += kept.len();
                        if let Some(object) = group.as_object_mut() {
                            object.insert("matches".to_owned(), json!(kept.clone()));
                            object.insert("count".to_owned(), json!(kept.len()));
                        }
                    }
                    group
                })
                .collect();
            total_matches = kept_total;
        }
    }
    if name == "import_graph" {
        if let Some(module) = opt_str(args, "module") {
            groups = groups
                .into_iter()
                .filter(|group| {
                    group["values"]
                        .as_array()
                        .map_or(false, |values| {
                            values.iter().any(|value| value.as_str() == Some(module.as_str()))
                        })
                })
                .collect();
            total_matches = groups
                .iter()
                .map(|group| group["count"].as_u64().unwrap_or(0) as usize)
                .sum();
        }
    }
    Ok(json!({
        "tool": name,
        "matchCount": total_matches,
        "truncated": truncated,
        "groups": groups,
    }))
}

fn g5_list_workspace_files(cwd: &str, query: &str, limit: u64) -> Result<Vec<Value>, CallError> {
    let value = coincide_core::workspace_tools::files(
        &json!({"cwd": cwd, "query": query, "limit": limit}),
    )
    .map_err(|error| failed(error.to_string()))?;
    Ok(value["files"].as_array().cloned().unwrap_or_default())
}

fn g5_scope_entries(entries: Vec<Value>, path: Option<&str>) -> Vec<Value> {
    let Some(path) = path.filter(|p| !p.is_empty()) else {
        return entries;
    };
    entries
        .into_iter()
        .filter(|entry| {
            let entry_path = entry["path"].as_str().unwrap_or("");
            entry_path == path || entry_path.starts_with(&format!("{path}/"))
        })
        .collect()
}

fn g5_read_text_files(
    cwd: &str,
    path: Option<&str>,
    extensions: &[&str],
    limit: usize,
) -> Result<Vec<(String, String)>, CallError> {
    let entries = g5_list_workspace_files(cwd, "", 500)?;
    let scoped = g5_scope_entries(entries, path);
    let mut files: Vec<(String, String)> = Vec::new();
    for entry in scoped {
        if files.len() >= limit {
            break;
        }
        let entry_path = entry["path"].as_str().unwrap_or("").to_owned();
        if entry["isDirectory"].as_bool() == Some(true) {
            continue;
        }
        if entry_path.starts_with('.') || entry_path.contains("/.") {
            continue;
        }
        if !extensions.iter().any(|ext| entry_path.ends_with(ext)) {
            continue;
        }
        if let Ok(text) = read_text_file_at(cwd, &entry_path) {
            files.push((entry_path, text));
        }
    }
    Ok(files)
}

fn g5_resolve_pbxproj(cwd: &str, path: Option<&str>, tool: &str) -> Result<String, CallError> {
    if let Some(path) = path.filter(|p| !p.is_empty()) {
        return Ok(path.to_owned());
    }
    let entries = g5_list_workspace_files(cwd, "project.pbxproj", 20)?;
    for entry in entries {
        if entry["isDirectory"].as_bool() != Some(true) {
            if let Some(found) = entry["path"].as_str() {
                return Ok(found.to_owned());
            }
        }
    }
    Err(failed(format!("{tool} found no project.pbxproj in the workspace.")))
}


fn g5_file_summary(tool: &str, path: &str, content: &str) -> Value {
    let (lines, code, comment, blank) = g5_file_counts(content);
    json!({
        "tool": tool,
        "path": path,
        "lines": lines,
        "codeLines": code,
        "commentLines": comment,
        "blankLines": blank,
    })
}

fn g5_complexity(tool: &str, path: &str, content: &str) -> Value {
    let (lines, _, _, _) = g5_file_counts(content);
    let mut keywords: Vec<Value> = Vec::new();
    let mut total = 0usize;
    for keyword in ["if", "for", "while", "guard", "switch", "case", "catch"] {
        let count = g5_count_word(content, keyword);
        total += count;
        keywords.push(json!({"keyword": keyword, "count": count}));
    }
    for op in ["&&", "||"] {
        let count = g5_count_substring(content, op);
        total += count;
        keywords.push(json!({"keyword": op, "count": count}));
    }
    json!({
        "tool": tool,
        "path": path,
        "lines": lines,
        "keywords": keywords,
        "complexityEstimate": 1 + total,
    })
}

fn g5_lint(tool: &str, files: &[(String, String)], limit: usize) -> Value {
    let mut issues: Vec<Value> = Vec::new();
    for (path, content) in files {
        for (index, line) in g5_lines(content).iter().enumerate() {
            if line.chars().count() > 120 {
                issues.push(json!({
                    "path": path,
                    "lineNumber": index + 1,
                    "kind": "longLine",
                    "text": format!("Line is {} characters, over the 120 limit.", line.chars().count()),
                }));
            }
            if line.contains("TODO") || line.contains("FIXME") {
                issues.push(json!({
                    "path": path,
                    "lineNumber": index + 1,
                    "kind": "todo",
                    "text": line.trim(),
                }));
            }
            if issues.len() >= limit {
                break;
            }
        }
        if issues.len() >= limit {
            break;
        }
    }
    let count = issues.len();
    json!({
        "tool": tool,
        "filesChecked": files.len(),
        "issues": issues,
        "issueCount": count,
    })
}

fn g5_diagnostics_log(tool: &str, log_path: &str, content: &str) -> Value {
    let lines = g5_lines(content);
    let kinds: [(&str, &str, &str); 5] = [
        ("fatalError", "fatal error", "A fatal error was logged; inspect the frames near the first fatal line."),
        ("exception", "EXC_", "An exception code was logged; match it against the exception type in the header."),
        ("crash", "crash", "A crash mention was logged; check the faulting thread section for blamed frames."),
        ("signal", "SIG", "A signal was logged; check which thread received it and what it was doing."),
        ("thread", "Thread ", "Thread mentions were logged; compare the faulting thread against the others."),
    ];
    let mut findings: Vec<Value> = Vec::new();
    let mut leads: Vec<String> = Vec::new();
    for (kind, needle, lead) in kinds {
        let mut sample: Vec<String> = Vec::new();
        let mut count = 0usize;
        for (index, line) in lines.iter().enumerate() {
            if line.contains(needle) {
                count += 1;
                if sample.len() < 3 {
                    sample.push(format!("{}: {}", index + 1, line.trim()));
                }
            }
        }
        if count > 0 {
            leads.push(lead.to_owned());
            findings.push(json!({"kind": kind, "count": count, "sampleLines": sample}));
        }
    }
    json!({
        "tool": tool,
        "logPath": log_path,
        "lines": lines.len(),
        "findings": findings,
        "leads": leads,
    })
}

fn g5_build_log(tool: &str, path: &str, content: &str) -> Value {
    let lines = g5_lines(content);
    let mut errors: Vec<Value> = Vec::new();
    let mut warnings: Vec<Value> = Vec::new();
    let mut result = "unknown";
    for (index, line) in lines.iter().enumerate() {
        if line.contains("BUILD SUCCEEDED") {
            result = "succeeded";
        }
        if line.contains("BUILD FAILED") {
            result = "failed";
        }
        if line.contains("error:") {
            errors.push(json!({"lineNumber": index + 1, "text": line.trim()}));
        } else if line.contains("warning:") {
            warnings.push(json!({"lineNumber": index + 1, "text": line.trim()}));
        }
    }
    if result == "unknown" && !errors.is_empty() {
        result = "failed";
    }
    let error_count = errors.len();
    let warning_count = warnings.len();
    json!({
        "tool": tool,
        "path": path,
        "result": result,
        "errors": errors,
        "warnings": warnings,
        "errorCount": error_count,
        "warningCount": warning_count,
    })
}

fn g5_crash_log(tool: &str, path: &str, content: &str) -> Value {
    let lines = g5_lines(content);
    let mut exception_type = String::new();
    let mut termination_reason = String::new();
    let mut faulting_thread: i64 = -1;
    let mut crashed_thread: i64 = -1;
    let mut blamed_frames: Vec<String> = Vec::new();
    let mut in_crashed_thread = false;
    for line in &lines {
        let trimmed = line.trim();
        if let Some(value) = g5_first_capture(r"^Exception Type:\s*(.+)$", trimmed, 1) {
            exception_type = value;
        }
        if let Some(value) = g5_first_capture(r"^Termination Reason:\s*(.+)$", trimmed, 1) {
            termination_reason = value;
        }
        if let Some(value) = g5_first_capture(r"^Triggered by Thread:\s*(\d+)", trimmed, 1) {
            if let Ok(number) = value.parse::<i64>() {
                faulting_thread = number;
            }
        }
        if let Some(value) = g5_first_capture(r"^Thread (\d+) Crashed:", trimmed, 1) {
            if let Ok(number) = value.parse::<i64>() {
                crashed_thread = number;
            }
            in_crashed_thread = true;
            continue;
        }
        if in_crashed_thread {
            if trimmed.starts_with("Thread ") {
                in_crashed_thread = false;
                continue;
            }
            if blamed_frames.len() < 5 && !trimmed.is_empty() {
                blamed_frames.push(trimmed.to_owned());
            }
        }
    }
    if faulting_thread < 0 {
        faulting_thread = crashed_thread;
    }
    json!({
        "tool": tool,
        "path": path,
        "exceptionType": exception_type,
        "terminationReason": termination_reason,
        "faultingThread": faulting_thread,
        "blamedFrames": blamed_frames,
    })
}

fn g5_test_log(tool: &str, path: &str, content: &str) -> Value {
    let lines = g5_lines(content);
    let mut passed = 0usize;
    let mut failed = 0usize;
    let mut failed_tests: Vec<String> = Vec::new();
    let mut suites: Vec<(String, usize, usize)> = Vec::new();
    let mut error_lines: Vec<Value> = Vec::new();
    let mut current_suite = String::new();
    for (index, line) in lines.iter().enumerate() {
        let trimmed = line.trim();
        if let Some(suite) = g5_first_capture(r"Test Suite '([^']+)' started", trimmed, 1) {
            current_suite = suite.clone();
            if !suites.iter().any(|(name, _, _)| name == &suite) {
                suites.push((suite, 0, 0));
            }
        } else if g5_first_capture(r"Test Suite '([^']+)' finished", trimmed, 1).is_some() {
            current_suite = String::new();
        } else if let Some(name) = g5_first_capture(r"Test Case '-\[([^\]]+)\]' failed", trimmed, 1) {
            failed += 1;
            failed_tests.push(name);
            if !current_suite.is_empty() {
                if let Some(entry) = suites.iter_mut().find(|(n, _, _)| n == &current_suite) {
                    entry.2 += 1;
                }
            }
        } else if g5_first_capture(r"Test Case '-\[([^\]]+)\]' passed", trimmed, 1).is_some() {
            passed += 1;
            if !current_suite.is_empty() {
                if let Some(entry) = suites.iter_mut().find(|(n, _, _)| n == &current_suite) {
                    entry.1 += 1;
                }
            }
        }
        if trimmed.contains(": error:") {
            error_lines.push(json!({"lineNumber": index + 1, "text": trimmed}));
        }
    }
    json!({
        "tool": tool,
        "path": path,
        "passed": passed,
        "failed": failed,
        "failedTests": failed_tests,
        "suites": suites.iter().map(|(name, p, f)| json!({"name": name, "passed": p, "failed": f})).collect::<Vec<_>>(),
        "errorLines": error_lines,
    })
}

fn g5_flaky_tests(tool: &str, path: &str, content: &str) -> Value {
    let lines = g5_lines(content);
    let mut outcomes: Vec<(String, usize, usize)> = Vec::new();
    for line in &lines {
        let trimmed = line.trim();
        if let Some(name) = g5_first_capture(r"Test Case '-\[([^\]]+)\]' failed", trimmed, 1) {
            if let Some(entry) = outcomes.iter_mut().find(|(n, _, _)| n == &name) {
                entry.2 += 1;
            } else {
                outcomes.push((name, 0, 1));
            }
        } else if let Some(name) = g5_first_capture(r"Test Case '-\[([^\]]+)\]' passed", trimmed, 1) {
            if let Some(entry) = outcomes.iter_mut().find(|(n, _, _)| n == &name) {
                entry.1 += 1;
            } else {
                outcomes.push((name, 1, 0));
            }
        }
    }
    let flaky: Vec<Value> = outcomes
        .iter()
        .filter(|(_, p, f)| *p > 0 && *f > 0)
        .map(|(name, p, f)| json!({"name": name, "passes": p, "failures": f}))
        .collect();
    let count = flaky.len();
    json!({
        "tool": tool,
        "path": path,
        "flaky": flaky,
        "flakyCount": count,
    })
}

fn g5_metrics(tool: &str, files: &[(String, String)]) -> Value {
    let mut file_rows: Vec<Value> = Vec::new();
    let mut total_lines = 0usize;
    let mut total_code = 0usize;
    let mut total_comment = 0usize;
    let mut total_blank = 0usize;
    let mut total_functions = 0usize;
    let mut total_types = 0usize;
    let mut total_complexity = 0usize;
    for (path, content) in files {
        let (lines, code, comment, blank) = g5_file_counts(content);
        let functions = g5_regex_captures(
            r"^\s*(?:(?:public|open|internal|private|fileprivate)\s+)?(?:static\s+)?func\s+[A-Za-z0-9_]+",
            content,
        )
        .len();
        let types = g5_regex_captures(
            r"^\s*(?:(?:public|open|internal|private|fileprivate)\s+)?(?:final\s+)?(class|struct|enum|protocol)\s+[A-Za-z0-9_]+",
            content,
        )
        .len();
        let mut complexity = 1usize;
        for keyword in ["if", "for", "while", "guard", "switch", "case", "catch"] {
            complexity += g5_count_word(content, keyword);
        }
        complexity += g5_count_substring(content, "&&");
        complexity += g5_count_substring(content, "||");
        total_lines += lines;
        total_code += code;
        total_comment += comment;
        total_blank += blank;
        total_functions += functions;
        total_types += types;
        total_complexity += complexity;
        file_rows.push(json!({
            "path": path,
            "lines": lines,
            "codeLines": code,
            "commentLines": comment,
            "blankLines": blank,
            "functions": functions,
            "types": types,
            "complexityEstimate": complexity,
        }));
    }
    file_rows.sort_by(|a, b| {
        b["lines"]
            .as_u64()
            .unwrap_or(0)
            .cmp(&a["lines"].as_u64().unwrap_or(0))
    });
    json!({
        "tool": tool,
        "filesChecked": files.len(),
        "totals": {
            "lines": total_lines,
            "codeLines": total_code,
            "commentLines": total_comment,
            "blankLines": total_blank,
            "functions": total_functions,
            "types": total_types,
            "complexityEstimate": total_complexity,
        },
        "files": file_rows,
    })
}

fn g5_comment_density(tool: &str, files: &[(String, String)], limit: usize) -> Value {
    let mut rows: Vec<(String, usize, usize, usize, f64)> = Vec::new();
    for (path, content) in files {
        let (lines, code, comment, _) = g5_file_counts(content);
        let documented = code + comment;
        let ratio = if documented > 0 {
            comment as f64 / documented as f64
        } else {
            0.0
        };
        rows.push((path.clone(), lines, code, comment, ratio));
    }
    rows.sort_by(|a, b| a.4.partial_cmp(&b.4).unwrap_or(std::cmp::Ordering::Equal));
    let shown: Vec<Value> = rows
        .iter()
        .take(limit)
        .map(|(path, lines, code, comment, ratio)| {
            json!({"path": path, "lines": lines, "codeLines": code, "commentLines": comment, "commentRatio": ratio})
        })
        .collect();
    json!({
        "tool": tool,
        "filesChecked": files.len(),
        "files": shown,
    })
}

fn g5_function_sizes(tool: &str, files: &[(String, String)], limit: usize) -> Value {
    let mut functions: Vec<Value> = Vec::new();
    for (path, content) in files {
        let lines = g5_lines(content);
        let mut index = 0usize;
        while index < lines.len() {
            let Some(name) = g5_first_capture(
                r"^\s*(?:(?:public|open|internal|private|fileprivate)\s+)?(?:static\s+)?func\s+([A-Za-z0-9_]+)",
                lines[index],
                1,
            ) else {
                index += 1;
                continue;
            };
            let mut depth: i64 = 0;
            let mut started = false;
            let mut end = index;
            let mut cursor = index;
            while cursor < lines.len() {
                for ch in lines[cursor].chars() {
                    if ch == '{' {
                        depth += 1;
                        started = true;
                    }
                    if ch == '}' {
                        depth -= 1;
                    }
                }
                if started && depth <= 0 {
                    end = cursor;
                    break;
                }
                cursor += 1;
            }
            if started {
                functions.push(json!({
                    "name": name,
                    "path": path,
                    "startLine": index + 1,
                    "endLine": end + 1,
                    "lines": end - index + 1,
                }));
                index = (end + 1).max(index + 1);
            } else {
                index += 1;
            }
        }
    }
    functions.sort_by(|a, b| {
        b["lines"]
            .as_u64()
            .unwrap_or(0)
            .cmp(&a["lines"].as_u64().unwrap_or(0))
    });
    functions.truncate(limit);
    json!({
        "tool": tool,
        "filesChecked": files.len(),
        "functions": functions,
    })
}


fn g5_dead_code(tool: &str, files: &[(String, String)], private_only: bool, limit: usize) -> Value {
    let mut declarations: Vec<(String, String, String, String, usize)> = Vec::new();
    let mut declaration_counts: Vec<(String, usize)> = Vec::new();
    for (path, content) in files {
        for (index, line) in g5_lines(content).iter().enumerate() {
            let matches = g5_regex_captures(
                r"^\s*(private\s+|fileprivate\s+|internal\s+|public\s+|open\s+)?(func|class|struct|enum|protocol|let|var|typealias)\s+([A-Za-z0-9_]+)",
                line,
            );
            let Some(first) = matches.first() else {
                continue;
            };
            let access = first
                .get(1)
                .cloned()
                .flatten()
                .unwrap_or_default()
                .trim()
                .to_owned();
            let kind = first.get(2).cloned().flatten().unwrap_or_default();
            let name = first.get(3).cloned().flatten().unwrap_or_default();
            if name.is_empty() || kind.is_empty() {
                continue;
            }
            declarations.push((name.clone(), kind, access, path.clone(), index + 1));
            if let Some(entry) = declaration_counts.iter_mut().find(|(n, _)| n == &name) {
                entry.1 += 1;
            } else {
                declaration_counts.push((name, 1));
            }
        }
    }
    let mut candidates: Vec<Value> = Vec::new();
    for (name, kind, access, path, line) in &declarations {
        let declared = declaration_counts
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, c)| *c)
            .unwrap_or(0);
        if declared > 1 {
            continue;
        }
        if private_only && !(access == "private" && kind == "func") {
            continue;
        }
        let mut references = 0usize;
        for (_, content) in files {
            references += g5_count_word(content, name);
        }
        if references <= 1 {
            candidates.push(json!({
                "name": name,
                "kind": kind,
                "path": path,
                "lineNumber": line,
            }));
        }
        if candidates.len() >= limit {
            break;
        }
    }
    let count = candidates.len();
    let mut result = json!({
        "tool": tool,
        "filesChecked": files.len(),
        "declarations": declarations.len(),
        "candidates": candidates,
        "candidateCount": count,
    });
    if private_only {
        if let Some(object) = result.as_object_mut() {
            object.insert("reportOnly".to_owned(), json!(true));
        }
    }
    result
}

fn g5_duplicate_blocks(tool: &str, files: &[(String, String)], limit: usize) -> Value {
    let window = 6usize;
    let mut blocks: Vec<(String, Vec<(String, i64)>)> = Vec::new();
    for (path, content) in files {
        let raw_lines = g5_lines(content);
        let mut normalized: Vec<String> = Vec::new();
        let mut line_numbers: Vec<i64> = Vec::new();
        for (index, line) in raw_lines.iter().enumerate() {
            if line.trim().is_empty() {
                continue;
            }
            let collapsed = line.split_whitespace().collect::<Vec<_>>().join(" ");
            normalized.push(collapsed);
            line_numbers.push(index as i64 + 1);
        }
        if normalized.len() < window {
            continue;
        }
        for start in 0..=(normalized.len() - window) {
            let key = normalized[start..start + window].join("\n");
            if let Some(entry) = blocks.iter_mut().find(|(k, _)| k == &key) {
                entry.1.push((path.clone(), line_numbers[start]));
            } else {
                blocks.push((key, vec![(path.clone(), line_numbers[start])]));
            }
        }
    }
    let mut duplicates: Vec<Value> = Vec::new();
    for (_, occurrences) in &blocks {
        let distinct: Vec<String> = occurrences
            .iter()
            .map(|(path, line)| format!("{path}:{line}"))
            .collect::<std::collections::HashSet<_>>()
            .into_iter()
            .collect();
        if distinct.len() <= 1 {
            continue;
        }
        duplicates.push(json!({
            "lines": 6,
            "occurrences": occurrences.iter().map(|(path, line)| json!({"path": path, "lineNumber": line})).collect::<Vec<_>>(),
        }));
        if duplicates.len() >= limit {
            break;
        }
    }
    let count = duplicates.len();
    json!({
        "tool": tool,
        "filesChecked": files.len(),
        "blocks": duplicates,
        "blockCount": count,
    })
}

fn g5_unused_imports(tool: &str, files: &[(String, String)], limit: usize) -> Value {
    let protected: [&str; 21] = [
        "Foundation", "SwiftUI", "AppKit", "UIKit", "Combine", "CoreData", "CryptoKit",
        "Security", "XCTest", "SwiftData", "Observation", "WebKit",
        "UniformTypeIdentifiers", "Dispatch", "Network", "os", "SystemConfiguration",
        "CoreGraphics", "QuartzCore", "StoreKit", "AuthenticationServices",
    ];
    let mut unused: Vec<Value> = Vec::new();
    for (path, content) in files {
        let lines = g5_lines(content);
        for (index, line) in lines.iter().enumerate() {
            let Some(module) = g5_first_capture(r"^import\s+([A-Za-z0-9_]+)", line, 1) else {
                continue;
            };
            if protected.contains(&module.as_str()) {
                continue;
            }
            let mut body = String::new();
            for (other_index, other) in lines.iter().enumerate() {
                if other_index != index {
                    body.push_str(other);
                    body.push('\n');
                }
            }
            if g5_count_word(&body, &module) == 0 {
                unused.push(json!({
                    "path": path,
                    "module": module,
                    "lineNumber": index + 1,
                }));
            }
            if unused.len() >= limit {
                break;
            }
        }
        if unused.len() >= limit {
            break;
        }
    }
    let count = unused.len();
    json!({
        "tool": tool,
        "filesChecked": files.len(),
        "unused": unused,
        "unusedCount": count,
    })
}

fn g5_license_check(tool: &str, files: &[(String, String)], required_text: &str) -> Value {
    let mut missing: Vec<String> = Vec::new();
    for (path, content) in files {
        let head = g5_lines(content).iter().take(15).cloned().collect::<Vec<_>>().join("\n");
        if !head.contains(required_text) {
            missing.push(path.clone());
        }
    }
    let count = missing.len();
    json!({
        "tool": tool,
        "requiredText": required_text,
        "filesChecked": files.len(),
        "missing": missing,
        "missingCount": count,
    })
}

fn g5_doc_coverage(tool: &str, files: &[(String, String)]) -> Value {
    let mut declarations = 0usize;
    let mut documented = 0usize;
    for (_, content) in files {
        let lines = g5_lines(content);
        for (index, line) in lines.iter().enumerate() {
            if g5_regex_captures(
                r"^\s*(public|open)\s+(func|class|struct|enum|protocol|var|let|typealias)\s+[A-Za-z0-9_]+",
                line,
            )
            .is_empty()
            {
                continue;
            }
            declarations += 1;
            let mut cursor: i64 = index as i64 - 1;
            while cursor >= 0 {
                let previous = lines[cursor as usize].trim();
                if previous.is_empty() {
                    cursor -= 1;
                    continue;
                }
                if previous.starts_with("///") {
                    documented += 1;
                }
                break;
            }
        }
    }
    let coverage = if declarations > 0 {
        documented as f64 / declarations as f64
    } else {
        1.0
    };
    json!({
        "tool": tool,
        "filesChecked": files.len(),
        "declarations": declarations,
        "documented": documented,
        "coverage": coverage,
    })
}

fn g5_docstring(tool: &str, path: &str, content: &str, symbol: Option<&str>) -> Value {
    let mut declarations: Vec<Value> = Vec::new();
    for (index, line) in g5_lines(content).iter().enumerate() {
        let matches = g5_regex_captures(
            r"^\s*(?:(?:public|open|internal|private|fileprivate)\s+)?(func|class|struct|enum|protocol|init|var|let|typealias)\s+([A-Za-z0-9_]+)",
            line,
        );
        let Some(first) = matches.first() else {
            continue;
        };
        let kind = first.get(1).cloned().flatten().unwrap_or_default();
        let name = first.get(2).cloned().flatten().unwrap_or_default();
        if name.is_empty() {
            continue;
        }
        if let Some(symbol) = symbol {
            if symbol != name {
                continue;
            }
        }
        let mut block: Vec<String> = vec![format!("/// {name}")];
        if kind == "func" {
            let parameters = g5_first_capture(r"\(([^)]*)\)", line, 1).unwrap_or_default();
            let names: Vec<String> = parameters
                .split(',')
                .filter_map(|part| {
                    let pieces: Vec<&str> = part.trim().split(' ').collect();
                    let first = pieces.first().copied().unwrap_or("");
                    let cleaned = first.strip_prefix('_').unwrap_or(first);
                    if cleaned.is_empty() {
                        None
                    } else {
                        Some(cleaned.to_owned())
                    }
                })
                .collect();
            if !names.is_empty() {
                block.push("///".to_owned());
                block.push("/// - Parameters:".to_owned());
                for parameter in names {
                    block.push(format!("///   - {parameter}: "));
                }
            }
            if line.contains("->") {
                block.push("///".to_owned());
                block.push("/// - Returns: ".to_owned());
            }
        }
        declarations.push(json!({
            "name": name,
            "kind": kind,
            "lineNumber": index + 1,
            "docBlock": block.join("\n"),
        }));
    }
    json!({
        "tool": tool,
        "path": path,
        "declarations": declarations,
    })
}

fn g5_snippet_template(template: &str) -> Option<&'static str> {
    match template {
        "observable" => Some("@Observable\nfinal class Store {\n    var title = \"\"\n    var items: [String] = []\n}\n"),
        "asyncstream" => Some("func makeStream() -> AsyncStream<String> {\n    AsyncStream { continuation in\n        continuation.yield(\"ready\")\n        continuation.finish()\n    }\n}\n"),
        "actor" => Some("actor Counter {\n    private var value = 0\n    func next() -> Int {\n        value += 1\n        return value\n    }\n}\n"),
        "glasscard" => Some("struct GlassCard: View {\n    var body: some View {\n        Text(\"Card\")\n            .padding()\n            .glassEffect()\n    }\n}\n"),
        _ => None,
    }
}

fn g5_strings_validate(tool: &str, files: &[(String, String)], limit: usize) -> Value {
    let mut issues: Vec<Value> = Vec::new();
    for (path, content) in files {
        let mut seen: Vec<String> = Vec::new();
        for (index, line) in g5_lines(content).iter().enumerate() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with("//") || trimmed.starts_with("/*") || trimmed.starts_with('*') {
                continue;
            }
            let matches = g5_regex_captures(
                r#"^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#,
                trimmed,
            );
            let Some(first) = matches.first() else {
                issues.push(json!({"path": path, "lineNumber": index + 1, "kind": "syntax", "key": ""}));
                continue;
            };
            let key = first.get(1).cloned().flatten().unwrap_or_default();
            let value = first.get(2).cloned().flatten().unwrap_or_default();
            if seen.contains(&key) {
                issues.push(json!({"path": path, "lineNumber": index + 1, "kind": "duplicate", "key": key}));
            } else {
                seen.push(key.clone());
            }
            if value.is_empty() {
                issues.push(json!({"path": path, "lineNumber": index + 1, "kind": "empty", "key": key}));
            }
            if issues.len() >= limit {
                break;
            }
        }
        if issues.len() >= limit {
            break;
        }
    }
    let count = issues.len();
    json!({
        "tool": tool,
        "filesChecked": files.len(),
        "issues": issues,
        "issueCount": count,
    })
}

fn g5_plist_key_values(text: &str) -> Vec<(String, String)> {
    let mut values: Vec<(String, String)> = Vec::new();
    let key_matches = g5_regex_captures(r"<key>([^<]+)</key>", text);
    let mut offsets: Vec<usize> = Vec::new();
    if let Some(regex) = g5_regex(r"<key>([^<]+)</key>") {
        for m in regex.find_iter(text) {
            offsets.push(m.end());
        }
    }
    for (index, key_match) in key_matches.iter().enumerate() {
        let Some(key) = key_match.get(1).cloned().flatten() else {
            continue;
        };
        if key.is_empty() {
            continue;
        }
        let after = offsets.get(index).copied().unwrap_or(text.len());
        let rest = &text[after..];
        if let Some(value_match) = g5_regex_captures(r"^\s*<(string|integer|real|date|data)>([^<]*)</(string|integer|real|date|data)>", rest).first() {
            let open_tag = value_match.get(1).cloned().flatten().unwrap_or_default();
            let close_tag = value_match.get(3).cloned().flatten().unwrap_or_default();
            if open_tag == close_tag {
                let value = value_match.get(2).cloned().flatten().unwrap_or_default();
                values.push((key, value));
            }
        } else if rest.trim_start().starts_with("<true/>") {
            values.push((key, "true".to_owned()));
        } else if rest.trim_start().starts_with("<false/>") {
            values.push((key, "false".to_owned()));
        } else if let Some(tag_match) = g5_regex_captures(r"^\s*<(array|dict)>", rest).first() {
            let tag = tag_match.get(1).cloned().flatten().unwrap_or_default();
            values.push((key, format!("<{tag}>")));
        } else if let Some(step_match) = g5_regex_captures(r"^\s*([A-Za-z0-9_.-]+)\s*=\s*([^;]+);", rest).first() {
            let value = step_match.get(2).cloned().flatten().unwrap_or_default();
            values.push((key, value));
        }
    }
    if values.is_empty() {
        for line in g5_lines(text) {
            let trimmed = line.trim();
            if let Some(m) = g5_regex_captures(r"^([A-Za-z0-9_.-]+)\s*=\s*([^;]+);", trimmed).first() {
                let key = m.get(1).cloned().flatten().unwrap_or_default();
                let value = m.get(2).cloned().flatten().unwrap_or_default();
                if !key.is_empty() {
                    values.push((key, value.trim().to_owned()));
                }
            }
        }
    }
    values
}

fn g5_xcconfig_key_values(text: &str) -> Vec<(String, String)> {
    let mut values: Vec<(String, String)> = Vec::new();
    for line in g5_lines(text) {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with("//") {
            continue;
        }
        if let Some(m) = g5_regex_captures(r"^([A-Za-z0-9_\.\[\]\*]+)\s*=\s*(.+)$", trimmed).first() {
            let key = m.get(1).cloned().flatten().unwrap_or_default();
            let value = m.get(2).cloned().flatten().unwrap_or_default();
            if !key.is_empty() {
                values.push((key, value.trim().to_owned()));
            }
        }
    }
    values
}

fn g5_key_value_diff(tool: &str, path: &str, other_path: &str, first: &[(String, String)], second: &[(String, String)]) -> Value {
    let mut added: Vec<String> = Vec::new();
    let mut removed: Vec<String> = Vec::new();
    let mut changed: Vec<Value> = Vec::new();
    let mut first_keys: Vec<String> = first.iter().map(|(k, _)| k.clone()).collect();
    let mut second_keys: Vec<String> = second.iter().map(|(k, _)| k.clone()).collect();
    first_keys.sort();
    second_keys.sort();
    for key in &second_keys {
        if !first.iter().any(|(k, _)| k == key) {
            added.push(key.clone());
        }
    }
    for key in &first_keys {
        if !second.iter().any(|(k, _)| k == key) {
            removed.push(key.clone());
        }
    }
    for key in &first_keys {
        let old = first.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone());
        let new = second.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone());
        if let (Some(old), Some(new)) = (old, new) {
            if old != new {
                changed.push(json!({"key": key, "from": old, "to": new}));
            }
        }
    }
    json!({
        "tool": tool,
        "path": path,
        "otherPath": other_path,
        "added": added,
        "removed": removed,
        "changed": changed,
    })
}


fn g5_pbxproj_section(content: &str, name: &str) -> String {
    let begin = format!("/* Begin {name} section */");
    let end = format!("/* End {name} section */");
    let Some(start) = content.find(&begin) else {
        return String::new();
    };
    let Some(finish) = content.find(&end) else {
        return String::new();
    };
    let body_start = start + begin.len();
    if body_start > finish {
        return String::new();
    }
    content[body_start..finish].to_owned()
}

fn g5_pbxproj_file_refs(content: &str) -> Vec<(String, String)> {
    let section = g5_pbxproj_section(content, "PBXFileReference");
    let mut refs: Vec<(String, String)> = Vec::new();
    for m in g5_regex_captures(
        r#"([0-9A-F]{24})\s*/\* [^*]+ \*/\s*=\s*\{[^}]*?path\s*=\s*"?([^";\n]+)"?;"#,
        &section,
    ) {
        let id = m.get(1).cloned().flatten().unwrap_or_default();
        let path = m.get(2).cloned().flatten().unwrap_or_default().trim().to_owned();
        if !id.is_empty() && !path.is_empty() {
            refs.push((id, path));
        }
    }
    refs
}

fn g5_pbxproj_build_files(content: &str) -> Vec<(String, String)> {
    let section = g5_pbxproj_section(content, "PBXBuildFile");
    let mut files: Vec<(String, String)> = Vec::new();
    for m in g5_regex_captures(
        r"([0-9A-F]{24})\s*/\* [^*]+ \*/\s*=\s*\{[^}]*?fileRef\s*=\s*([0-9A-F]{24})\s*;",
        &section,
    ) {
        let id = m.get(1).cloned().flatten().unwrap_or_default();
        let reference = m.get(2).cloned().flatten().unwrap_or_default();
        if !id.is_empty() && !reference.is_empty() {
            files.push((id, reference));
        }
    }
    files
}

fn g5_pbxproj_lint(tool: &str, path: &str, content: &str, workspace_paths: &[String]) -> Value {
    let refs = g5_pbxproj_file_refs(content);
    let mut missing: Vec<Value> = Vec::new();
    let mut seen_paths: Vec<String> = Vec::new();
    let mut duplicates: Vec<String> = Vec::new();
    let mut sorted_paths: Vec<String> = refs.iter().map(|(_, p)| p.clone()).collect();
    sorted_paths.sort();
    for ref_path in sorted_paths {
        if seen_paths.contains(&ref_path) {
            if !duplicates.contains(&ref_path) {
                duplicates.push(ref_path.clone());
            }
            continue;
        }
        seen_paths.push(ref_path.clone());
        let exists = workspace_paths.iter().any(|workspace_path| {
            workspace_path == &ref_path || workspace_path.ends_with(&format!("/{ref_path}"))
        });
        if !exists {
            missing.push(json!({"path": ref_path, "reference": ref_path}));
        }
    }
    let build_files = g5_pbxproj_build_files(content);
    let mut dangling: Vec<String> = Vec::new();
    let mut sorted_build_files = build_files.clone();
    sorted_build_files.sort();
    for (id, reference) in sorted_build_files {
        if !refs.iter().any(|(ref_id, _)| ref_id == &reference) {
            dangling.push(id);
        }
    }
    let issue_count = missing.len() + duplicates.len() + dangling.len();
    json!({
        "tool": tool,
        "path": path,
        "fileReferences": refs.len(),
        "missingFiles": missing,
        "duplicatePaths": duplicates,
        "danglingBuildFiles": dangling,
        "issueCount": issue_count,
    })
}

fn g5_pbxproj_scripts(tool: &str, path: &str, content: &str) -> Value {
    let section = g5_pbxproj_section(content, "PBXShellScriptBuildPhase");
    let mut phases: Vec<Value> = Vec::new();
    for m in g5_regex_captures(r"\{[^}]*?isa\s*=\s*PBXShellScriptBuildPhase;[^}]*?\}", &section) {
        let Some(block) = m.first().cloned().flatten() else {
            continue;
        };
        let name = g5_first_capture(r#"name\s*=\s*"?([^";\n]+)"?;"#, &block, 1)
            .unwrap_or_default()
            .trim()
            .to_owned();
        let shell_path = g5_first_capture(r"shellPath\s*=\s*([^;\n]+);", &block, 1)
            .unwrap_or_default()
            .trim()
            .to_owned();
        let mut script = g5_first_capture(
            r#"(?s)shellScript\s*=\s*"((?:[^"\\]|\\.)*)";"#,
            &block,
            1,
        )
        .unwrap_or_default();
        if script.chars().count() > 200 {
            script = script.chars().take(200).collect();
        }
        phases.push(json!({"name": name, "shellPath": shell_path, "script": script}));
    }
    json!({
        "tool": tool,
        "path": path,
        "phases": phases,
    })
}

fn g5_pbxproj_configs(tool: &str, path: &str, content: &str, xcconfig_files: &[String]) -> Value {
    let section = g5_pbxproj_section(content, "XCBuildConfiguration");
    let mut configurations: Vec<String> = Vec::new();
    for m in g5_regex_captures(r"name\s*=\s*([^;\n]+);", &section) {
        let name = m.get(1).cloned().flatten().unwrap_or_default().trim().to_owned();
        if !name.is_empty() && !configurations.contains(&name) {
            configurations.push(name);
        }
    }
    let count = configurations.len();
    json!({
        "tool": tool,
        "path": path,
        "configurations": configurations,
        "configurationCount": count,
        "xcconfigFiles": xcconfig_files,
    })
}

fn g5_pbxproj_deps(tool: &str, path: &str, content: &str) -> Value {
    let mut target_names: Vec<(String, String)> = Vec::new();
    let mut target_deps: Vec<(String, Vec<String>)> = Vec::new();
    let target_section = g5_pbxproj_section(content, "PBXNativeTarget");
    for m in g5_regex_captures(
        r"([0-9A-F]{24})\s*/\* ([^*]+) \*/\s*=\s*\{[^}]*?\}",
        &target_section,
    ) {
        let id = m.get(1).cloned().flatten().unwrap_or_default();
        let Some(block) = m.first().cloned().flatten() else {
            continue;
        };
        if id.is_empty() {
            continue;
        }
        let name = g5_first_capture(r"name\s*=\s*([^;\n]+);", &block, 1)
            .unwrap_or_default()
            .trim()
            .to_owned();
        let dep_list = g5_first_capture(r"(?s)dependencies\s*=\s*\(([^)]*)\)", &block, 1).unwrap_or_default();
        let dep_ids: Vec<String> = g5_regex_captures(r"([0-9A-F]{24})", &dep_list)
            .iter()
            .filter_map(|cap| cap.get(1).cloned().flatten())
            .collect();
        target_names.push((id.clone(), name));
        target_deps.push((id, dep_ids));
    }
    let mut dep_targets: Vec<(String, String)> = Vec::new();
    let dep_section = g5_pbxproj_section(content, "PBXTargetDependency");
    for m in g5_regex_captures(
        r"([0-9A-F]{24})[^\{]*\{[^}]*?target\s*=\s*([0-9A-F]{24})\s*;",
        &dep_section,
    ) {
        let id = m.get(1).cloned().flatten().unwrap_or_default();
        let target = m.get(2).cloned().flatten().unwrap_or_default();
        if !id.is_empty() {
            dep_targets.push((id, target));
        }
    }
    let mut targets: Vec<Value> = Vec::new();
    let mut sorted_deps = target_deps.clone();
    sorted_deps.sort();
    for (id, dep_ids) in sorted_deps {
        let dependencies: Vec<String> = dep_ids
            .iter()
            .filter_map(|dep_id| dep_targets.iter().find(|(d, _)| d == dep_id).map(|(_, t)| t.clone()))
            .filter_map(|target_id| {
                target_names
                    .iter()
                    .find(|(t, _)| t == &target_id)
                    .map(|(_, n)| n.clone())
            })
            .collect();
        let name = target_names
            .iter()
            .find(|(t, _)| t == &id)
            .map(|(_, n)| n.clone())
            .unwrap_or(id);
        targets.push(json!({"name": name, "dependencies": dependencies}));
    }
    json!({
        "tool": tool,
        "path": path,
        "targets": targets,
    })
}

fn g5_pbxproj_sources(tool: &str, path: &str, content: &str) -> Value {
    let refs = g5_pbxproj_file_refs(content);
    let build_files = g5_pbxproj_build_files(content);
    let mut phase_owners: Vec<(String, String)> = Vec::new();
    let target_section = g5_pbxproj_section(content, "PBXNativeTarget");
    for m in g5_regex_captures(
        r"([0-9A-F]{24})\s*/\* ([^*]+) \*/\s*=\s*\{[^}]*?buildPhases\s*=\s*\(([^)]*)\)",
        &target_section,
    ) {
        let name = m.get(2).cloned().flatten().unwrap_or_default().trim().to_owned();
        let phase_list = m.get(3).cloned().flatten().unwrap_or_default();
        for phase_match in g5_regex_captures(r"([0-9A-F]{24})", &phase_list) {
            if let Some(phase_id) = phase_match.get(1).cloned().flatten() {
                phase_owners.push((phase_id, name.clone()));
            }
        }
    }
    let mut by_target: Vec<(String, Vec<String>)> = Vec::new();
    let sources_section = g5_pbxproj_section(content, "PBXSourcesBuildPhase");
    for m in g5_regex_captures(
        r"([0-9A-F]{24})[^\{]*\{[^}]*?files\s*=\s*\(([^)]*)\)",
        &sources_section,
    ) {
        let phase_id = m.get(1).cloned().flatten().unwrap_or_default();
        let file_list = m.get(2).cloned().flatten().unwrap_or_default();
        let owner = phase_owners
            .iter()
            .find(|(p, _)| p == &phase_id)
            .map(|(_, n)| n.clone())
            .unwrap_or_default();
        if !by_target.iter().any(|(n, _)| n == &owner) {
            by_target.push((owner.clone(), Vec::new()));
        }
        for file_match in g5_regex_captures(r"([0-9A-F]{24})", &file_list) {
            let Some(build_id) = file_match.get(1).cloned().flatten() else {
                continue;
            };
            let Some(ref_id) = build_files.iter().find(|(b, _)| b == &build_id).map(|(_, r)| r.clone()) else {
                continue;
            };
            let Some(file_path) = refs.iter().find(|(r, _)| r == &ref_id).map(|(_, p)| p.clone()) else {
                continue;
            };
            if let Some(entry) = by_target.iter_mut().find(|(n, _)| n == &owner) {
                entry.1.push(file_path);
            }
        }
    }
    let targets: Vec<Value> = by_target
        .iter()
        .map(|(name, sources)| json!({"name": name, "sources": sources}))
        .collect();
    json!({
        "tool": tool,
        "path": path,
        "targets": targets,
    })
}

fn g5_workspace_settings(tool: &str, cwd: &str, path: Option<&str>) -> Result<Value, CallError> {
    let resolved: String = if let Some(path) = path.filter(|p| !p.is_empty()) {
        path.to_owned()
    } else {
        let entries = g5_list_workspace_files(cwd, ".xcsettings", 20)?;
        let found = entries.into_iter().find(|entry| entry["isDirectory"].as_bool() != Some(true));
        let Some(found) = found.and_then(|entry| entry["path"].as_str().map(str::to_owned)) else {
            return Ok(json!({"tool": tool, "found": false, "settings": {}}));
        };
        found
    };
    let text = read_text_file_at(cwd, &resolved)?;
    let mut settings = serde_json::Map::new();
    for (key, value) in g5_plist_key_values(&text) {
        settings.insert(key, json!(value));
    }
    Ok(json!({
        "tool": tool,
        "path": resolved,
        "found": true,
        "settings": settings,
    }))
}

fn g5_test_plans(tool: &str, files: &[(String, String)]) -> Value {
    let mut plans: Vec<Value> = Vec::new();
    for (path, content) in files {
        let mut targets: Vec<String> = Vec::new();
        if let Ok(parsed) = serde_json::from_str::<Value>(content) {
            if let Some(test_targets) = parsed["testTargets"].as_array() {
                for entry in test_targets {
                    if let Some(name) = entry["target"]["name"].as_str() {
                        targets.push(name.to_owned());
                    } else if let Some(name) = entry["target"].as_str() {
                        targets.push(name.to_owned());
                    }
                }
            }
        }
        plans.push(json!({"path": path, "testTargets": targets}));
    }
    json!({
        "tool": tool,
        "plans": plans,
    })
}

fn g5_info_plist_audit(tool: &str, files: &[(String, String)]) -> Value {
    let mut plists: Vec<Value> = Vec::new();
    let mut bundle_counts: Vec<(String, usize)> = Vec::new();
    let version_pattern = r"^[0-9]+(\.[0-9]+){0,2}$";
    for (path, content) in files {
        let values = g5_plist_key_values(content);
        let get = |key: &str| {
            values
                .iter()
                .find(|(k, _)| k == key)
                .map(|(_, v)| v.clone())
                .unwrap_or_default()
        };
        let bundle_id = get("CFBundleIdentifier");
        let short_version = get("CFBundleShortVersionString");
        let version = get("CFBundleVersion");
        let mut issues: Vec<String> = Vec::new();
        if bundle_id.is_empty() {
            issues.push("Missing CFBundleIdentifier.".to_owned());
        }
        if get("CFBundleName").is_empty() && get("CFBundleDisplayName").is_empty() {
            issues.push("Missing CFBundleName.".to_owned());
        }
        if short_version.is_empty() {
            issues.push("Missing CFBundleShortVersionString.".to_owned());
        } else if g5_regex_captures(version_pattern, &short_version).is_empty() {
            issues.push("CFBundleShortVersionString is not a dotted version.".to_owned());
        }
        if version.is_empty() {
            issues.push("Missing CFBundleVersion.".to_owned());
        } else if g5_regex_captures(version_pattern, &version).is_empty() {
            issues.push("CFBundleVersion is not a dotted version.".to_owned());
        }
        if !bundle_id.is_empty() {
            if let Some(entry) = bundle_counts.iter_mut().find(|(b, _)| b == &bundle_id) {
                entry.1 += 1;
            } else {
                bundle_counts.push((bundle_id.clone(), 1));
            }
        }
        plists.push(json!({
            "path": path,
            "bundleIdentifier": bundle_id,
            "shortVersion": short_version,
            "version": version,
            "issues": issues,
        }));
    }
    let mut duplicates: Vec<String> = bundle_counts
        .iter()
        .filter(|(_, count)| *count > 1)
        .map(|(bundle, _)| bundle.clone())
        .collect();
    duplicates.sort();
    json!({
        "tool": tool,
        "filesChecked": files.len(),
        "plists": plists,
        "duplicateBundleIdentifiers": duplicates,
    })
}

fn g5_normalize_path(path: &str) -> String {
    let mut parts: Vec<&str> = Vec::new();
    for part in path.split('/') {
        if part == "." || part.is_empty() {
            continue;
        }
        if part == ".." {
            parts.pop();
            continue;
        }
        parts.push(part);
    }
    parts.join("/")
}

fn g5_markdown_links(
    tool: &str,
    cwd: &str,
    path: Option<&str>,
    limit: usize,
) -> Result<Value, CallError> {
    let entries = g5_list_workspace_files(cwd, "", 500)?;
    let workspace_paths: Vec<String> = entries
        .into_iter()
        .filter(|entry| entry["isDirectory"].as_bool() != Some(true))
        .filter_map(|entry| entry["path"].as_str().map(str::to_owned))
        .collect();
    let files = g5_read_text_files(cwd, path, &[".md"], 100)?;
    let mut broken: Vec<Value> = Vec::new();
    let mut link_count = 0usize;
    for (file_path, content) in &files {
        let directory = std::path::Path::new(file_path)
            .parent()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default();
        for (index, line) in g5_lines(content).iter().enumerate() {
            for m in g5_regex_captures(r"\[[^\]]*\]\(([^)\s]+)\)", line) {
                let Some(target) = m.get(1).cloned().flatten() else {
                    continue;
                };
                if target.is_empty() {
                    continue;
                }
                if target.starts_with("http://")
                    || target.starts_with("https://")
                    || target.starts_with("mailto:")
                    || target.starts_with('#')
                {
                    continue;
                }
                link_count += 1;
                let clean_target = target.split('#').next().unwrap_or(target.as_str()).to_owned();
                let resolved = if directory.is_empty() || directory == "." {
                    clean_target.clone()
                } else {
                    format!("{directory}/{clean_target}")
                };
                let normalized = g5_normalize_path(&resolved);
                if !workspace_paths.contains(&normalized) && !workspace_paths.contains(&clean_target) {
                    broken.push(json!({
                        "path": file_path,
                        "lineNumber": index + 1,
                        "target": target,
                    }));
                }
                if broken.len() >= limit {
                    break;
                }
            }
            if broken.len() >= limit {
                break;
            }
        }
        if broken.len() >= limit {
            break;
        }
    }
    let broken_count = broken.len();
    Ok(json!({
        "tool": tool,
        "filesChecked": files.len(),
        "links": link_count,
        "broken": broken,
        "brokenCount": broken_count,
    }))
}

fn g5_docs_index(tool: &str, cwd: &str, path: Option<&str>) -> Result<Value, CallError> {
    let entries = g5_list_workspace_files(cwd, "", 500)?;
    let scoped = g5_scope_entries(entries, path);
    let mut files: Vec<Value> = Vec::new();
    for entry in scoped {
        let entry_path = entry["path"].as_str().unwrap_or("").to_owned();
        if entry["isDirectory"].as_bool() == Some(true) {
            continue;
        }
        if !entry_path.ends_with(".md") || entry_path.starts_with('.') || entry_path.contains("/.") {
            continue;
        }
        let Ok(text) = read_text_file_at(cwd, &entry_path) else {
            continue;
        };
        let mut title = String::new();
        for line in g5_lines(&text) {
            let trimmed = line.trim();
            if let Some(rest) = trimmed.strip_prefix("# ") {
                title = rest.trim().to_owned();
                break;
            }
        }
        let size = entry["sizeBytes"]
            .as_i64()
            .unwrap_or(text.len() as i64);
        files.push(json!({"path": entry_path, "title": title, "sizeBytes": size}));
    }
    Ok(json!({
        "tool": tool,
        "files": files,
    }))
}

fn g5_call(state: &crate::ServerState, name: &str, args: &Value) -> Result<Value, CallError> {
    let cwd = req_str(args, "cwd", name)?;
    let path = opt_str(args, "path");
    let limit = opt_u64(args, "limit").unwrap_or(200).clamp(1, 1000) as usize;
    match name {
        "code_summary" => {
            let file = req_str(args, "path", name)?;
            let text = read_text_file_at(&cwd, &file)?;
            Ok(g5_file_summary(name, &file, &text))
        }
        "complexity_analysis" => {
            let file = req_str(args, "path", name)?;
            let text = read_text_file_at(&cwd, &file)?;
            Ok(g5_complexity(name, &file, &text))
        }
        "code_lint" => {
            let files = if let Some(file) = path.filter(|p| !p.is_empty()) {
                let text = read_text_file_at(&cwd, &file)?;
                vec![(file, text)]
            } else {
                g5_read_text_files(&cwd, None, &[".swift"], 100)?
            };
            Ok(g5_lint(name, &files, limit))
        }
        "runtime_diagnostics_engine" => {
            let log_path = req_str(args, "logPath", name)?;
            let text = read_text_file_at(&cwd, &log_path)?;
            Ok(g5_diagnostics_log(name, &log_path, &text))
        }
        "build_log_analyze" => {
            let file = req_str(args, "path", name)?;
            let text = read_text_file_at(&cwd, &file)?;
            Ok(g5_build_log(name, &file, &text))
        }
        "crash_log_parse" => {
            let file = req_str(args, "path", name)?;
            let text = read_text_file_at(&cwd, &file)?;
            Ok(g5_crash_log(name, &file, &text))
        }
        "test_log_parse" => {
            let file = req_str(args, "path", name)?;
            let text = read_text_file_at(&cwd, &file)?;
            Ok(g5_test_log(name, &file, &text))
        }
        "test_flaky_detect" => {
            let file = req_str(args, "path", name)?;
            let text = read_text_file_at(&cwd, &file)?;
            Ok(g5_flaky_tests(name, &file, &text))
        }
        "code_metrics_analyzer" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 100)?;
            Ok(g5_metrics(name, &files))
        }
        "comment_density_report" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 100)?;
            Ok(g5_comment_density(name, &files, limit))
        }
        "function_size_report" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 100)?;
            Ok(g5_function_sizes(name, &files, limit))
        }
        "dead_code_scan" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 100)?;
            Ok(g5_dead_code(name, &files, false, limit))
        }
        "dead_code_eliminator" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 100)?;
            Ok(g5_dead_code(name, &files, true, limit))
        }
        "duplicate_code_scan" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 100)?;
            Ok(g5_duplicate_blocks(name, &files, limit))
        }
        "unused_imports_detector" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 100)?;
            Ok(g5_unused_imports(name, &files, limit))
        }
        "license_header_check" => {
            let required_text = opt_str(args, "requiredText").unwrap_or_else(|| "Copyright".to_owned());
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 200)?;
            Ok(g5_license_check(name, &files, &required_text))
        }
        "api_docs_coverage" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 100)?;
            Ok(g5_doc_coverage(name, &files))
        }
        "docstring_generator" => {
            let file = req_str(args, "path", name)?;
            let text = read_text_file_at(&cwd, &file)?;
            Ok(g5_docstring(name, &file, &text, opt_str(args, "symbol").as_deref()))
        }
        "code_snippet_manager" => {
            let template = req_str(args, "template", name)?;
            let Some(content) = g5_snippet_template(&template) else {
                return Err(failed(
                    "Unknown template. Use observable, asyncstream, actor, or glasscard.".to_owned(),
                ));
            };
            if let Some(file) = path.filter(|p| !p.is_empty()) {
                write_text_file(&cwd, &file, content)?;
                return Ok(json!({
                    "tool": name,
                    "template": template,
                    "written": true,
                    "path": file,
                    "content": content,
                }));
            }
            Ok(json!({
                "tool": name,
                "template": template,
                "written": false,
                "content": content,
            }))
        }
        "strings_file_validate" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".strings"], 100)?;
            Ok(g5_strings_validate(name, &files, limit))
        }
        "entitlements_diff" | "build_settings_diff" => {
            let first = req_str(args, "path", name)?;
            let second = req_str(args, "otherPath", name)?;
            let first_text = read_text_file_at(&cwd, &first)?;
            let second_text = read_text_file_at(&cwd, &second)?;
            let first_pairs = if name == "entitlements_diff" {
                g5_plist_key_values(&first_text)
            } else {
                g5_xcconfig_key_values(&first_text)
            };
            let second_pairs = if name == "entitlements_diff" {
                g5_plist_key_values(&second_text)
            } else {
                g5_xcconfig_key_values(&second_text)
            };
            Ok(g5_key_value_diff(name, &first, &second, &first_pairs, &second_pairs))
        }
        "pbxproj_lint" => {
            let resolved = g5_resolve_pbxproj(&cwd, path.as_deref(), name)?;
            let text = read_text_file_at(&cwd, &resolved)?;
            let entries = g5_list_workspace_files(&cwd, "", 500)?;
            let workspace_paths: Vec<String> = entries
                .into_iter()
                .filter(|entry| entry["isDirectory"].as_bool() != Some(true))
                .filter_map(|entry| entry["path"].as_str().map(str::to_owned))
                .collect();
            Ok(g5_pbxproj_lint(name, &resolved, &text, &workspace_paths))
        }
        "build_phase_scripts_list" => {
            let resolved = g5_resolve_pbxproj(&cwd, path.as_deref(), name)?;
            let text = read_text_file_at(&cwd, &resolved)?;
            Ok(g5_pbxproj_scripts(name, &resolved, &text))
        }
        "build_configuration_list" => {
            let resolved = g5_resolve_pbxproj(&cwd, path.as_deref(), name)?;
            let text = read_text_file_at(&cwd, &resolved)?;
            let entries = g5_list_workspace_files(&cwd, ".xcconfig", 100)?;
            let xcconfigs: Vec<String> = entries
                .into_iter()
                .filter(|entry| entry["isDirectory"].as_bool() != Some(true))
                .filter_map(|entry| entry["path"].as_str().map(str::to_owned))
                .collect();
            Ok(g5_pbxproj_configs(name, &resolved, &text, &xcconfigs))
        }
        "target_dependencies_list" => {
            let resolved = g5_resolve_pbxproj(&cwd, path.as_deref(), name)?;
            let text = read_text_file_at(&cwd, &resolved)?;
            Ok(g5_pbxproj_deps(name, &resolved, &text))
        }
        "target_source_list" => {
            let resolved = g5_resolve_pbxproj(&cwd, path.as_deref(), name)?;
            let text = read_text_file_at(&cwd, &resolved)?;
            Ok(g5_pbxproj_sources(name, &resolved, &text))
        }
        "workspace_settings_read" => g5_workspace_settings(name, &cwd, path.as_deref()),
        "scheme_test_plan_list" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".xctestplan"], 100)?;
            Ok(g5_test_plans(name, &files))
        }
        "info_plist_audit" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &["Info.plist"], 50)?;
            Ok(g5_info_plist_audit(name, &files))
        }
        "markdown_link_check" => g5_markdown_links(name, &cwd, path.as_deref(), limit),
        "docs_index_build" => g5_docs_index(name, &cwd, path.as_deref()),
        _ => g5_run_scan(state, name, args),
    }
}


fn g6_entries(cwd: &str, path: Option<&str>) -> Result<Vec<Value>, CallError> {
    read_dir_entries(cwd, path.unwrap_or(""), true)
}

fn g6_entry_path(entry: &Value) -> String {
    entry["path"].as_str().unwrap_or("").to_owned()
}

fn g6_entry_name(entry: &Value) -> String {
    entry["name"].as_str().unwrap_or("").to_owned()
}

fn g6_is_dir(entry: &Value) -> bool {
    entry["isDirectory"].as_bool() == Some(true)
}

fn g6_size(entry: &Value) -> i64 {
    entry["sizeBytes"].as_i64().unwrap_or(0)
}

fn g6_mtime(entry: &Value) -> f64 {
    entry["modifiedAt"].as_f64().unwrap_or(0.0)
}

fn g6_ext(path: &str) -> String {
    Path::new(path)
        .extension()
        .map(|ext| ext.to_string_lossy().to_lowercase())
        .unwrap_or_default()
}

fn g6_basename(path: &str) -> String {
    Path::new(path)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn g6_dirname(path: &str) -> String {
    Path::new(path)
        .parent()
        .map(|parent| parent.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn g6_join(cwd: &str, path: Option<&str>) -> String {
    match path.filter(|p| !p.is_empty()) {
        Some(rel) => Path::new(cwd).join(rel).to_string_lossy().into_owned(),
        None => cwd.to_owned(),
    }
}

fn g6_validate_relative(path: &str, tool: &str) -> Result<(), CallError> {
    if path.starts_with('/') || path.split('/').any(|part| part == "..") {
        return Err(failed(format!(
            "{tool} path must be relative and must not contain .. components."
        )));
    }
    Ok(())
}

fn g6_missing_cli(output: &str, exit_code: i64) -> bool {
    exit_code == 127 || output.contains("command not found")
}

fn g6_command_output(argv: &[&str]) -> Option<String> {
    let mut command = std::process::Command::new(argv[0]);
    if argv.len() > 1 {
        command.args(&argv[1..]);
    }
    let output = command.output().ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

fn g6_strings_unescape(text: &str) -> String {
    let mut out = String::new();
    let mut escaped = false;
    for ch in text.chars() {
        if escaped {
            match ch {
                'n' => out.push('\n'),
                't' => out.push('\t'),
                '"' => out.push('"'),
                '\\' => out.push('\\'),
                _ => out.push(ch),
            }
            escaped = false;
        } else if ch == '\\' {
            escaped = true;
        } else {
            out.push(ch);
        }
    }
    out
}

fn g6_strings_escape(text: &str) -> String {
    text.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\t', "\\t")
}

fn g6_strings_pairs(content: &str) -> Vec<(String, String, usize)> {
    let mut pairs: Vec<(String, String, usize)> = Vec::new();
    for (index, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        let matches = g5_regex_captures(
            r#"^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#,
            trimmed,
        );
        let Some(first) = matches.first() else {
            continue;
        };
        let key = first.get(1).cloned().flatten().unwrap_or_default();
        let value = first.get(2).cloned().flatten().unwrap_or_default();
        if !key.is_empty() {
            pairs.push((
                g6_strings_unescape(&key),
                g6_strings_unescape(&value),
                index + 1,
            ));
        }
    }
    pairs
}

fn g6_serialize_strings(pairs: &[(String, String)]) -> String {
    let mut out = String::new();
    for (key, value) in pairs {
        out.push_str(&format!(
            "\"{}\" = \"{}\";\n",
            g6_strings_escape(key),
            g6_strings_escape(value)
        ));
    }
    out
}

fn g6_xcstrings_keys(value: &Value) -> Vec<(String, Vec<(String, String)>)> {
    let mut out: Vec<(String, Vec<(String, String)>)> = Vec::new();
    let Some(strings) = value.get("strings").and_then(Value::as_object) else {
        return out;
    };
    for (key, entry) in strings {
        let mut locales: Vec<(String, String)> = Vec::new();
        if let Some(locs) = entry.get("localizations").and_then(Value::as_object) {
            for (locale, loc) in locs {
                if let Some(text) = loc
                    .get("stringUnit")
                    .and_then(|unit| unit.get("value"))
                    .and_then(Value::as_str)
                {
                    locales.push((locale.clone(), text.to_owned()));
                }
            }
        }
        out.push((key.clone(), locales));
    }
    out
}

fn g6_xcstrings_set(value: &mut Value, key: &str, locale: &str, text: &str, state: &str) {
    if !value.is_object() {
        *value = json!({});
    }
    let object = value.as_object_mut().unwrap();
    if !object.contains_key("strings") {
        object.insert("strings".to_owned(), json!({}));
    }
    let strings = object
        .get_mut("strings")
        .unwrap()
        .as_object_mut()
        .unwrap();
    let entry = strings.entry(key.to_owned()).or_insert_with(|| json!({}));
    if !entry.is_object() {
        *entry = json!({});
    }
    let entry_object = entry.as_object_mut().unwrap();
    if !entry_object.contains_key("localizations") {
        entry_object.insert("localizations".to_owned(), json!({}));
    }
    let localizations = entry_object
        .get_mut("localizations")
        .unwrap()
        .as_object_mut()
        .unwrap();
    localizations.insert(
        locale.to_owned(),
        json!({"stringUnit": {"state": state, "value": text}}),
    );
}

fn g6_xcstrings_encode(value: &Value, tool: &str) -> Result<String, CallError> {
    serde_json::to_string_pretty(value)
        .map(|text| format!("{text}\n"))
        .map_err(|error| failed(format!("{tool} could not serialize the catalog as JSON: {error}")))
}

fn g6_plist_path(cwd: &str, path: &str) -> std::path::PathBuf {
    Path::new(cwd).join(path)
}

fn g6_plist_json(cwd: &str, path: &str, tool: &str) -> Result<Value, CallError> {
    let full = g6_plist_path(cwd, path);
    let output = std::process::Command::new("plutil")
        .args([
            "-convert",
            "json",
            "-o",
            "-",
            full.to_str().unwrap_or(""),
        ])
        .output()
        .map_err(|error| failed(format!("{tool} could not run plutil: {error}")))?;
    if !output.status.success() {
        return Err(failed(format!(
            "{tool} could not read {path} as a property list: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        )));
    }
    serde_json::from_slice(&output.stdout)
        .map_err(|error| failed(format!("{tool} could not parse {path} as a property list: {error}")))
}

fn g6_plist_set(cwd: &str, path: &str, key: &str, value: &Value, tool: &str) -> Result<(), CallError> {
    let full = g6_plist_path(cwd, path);
    let full_str = full.to_str().unwrap_or("");
    let value_json = serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_owned());
    let replaced = std::process::Command::new("plutil")
        .args(["-replace", key, "-json", &value_json, full_str])
        .output()
        .map_err(|error| failed(format!("{tool} could not run plutil: {error}")))?;
    if replaced.status.success() {
        return Ok(());
    }
    let inserted = std::process::Command::new("plutil")
        .args(["-insert", key, "-json", &value_json, full_str])
        .output()
        .map_err(|error| failed(format!("{tool} could not run plutil: {error}")))?;
    if inserted.status.success() {
        return Ok(());
    }
    Err(failed(format!(
        "{tool} could not set {key} in {path}: {}",
        String::from_utf8_lossy(&inserted.stderr).trim()
    )))
}

fn g6_plist_remove(cwd: &str, path: &str, key: &str, tool: &str) -> Result<(), CallError> {
    let full = g6_plist_path(cwd, path);
    let output = std::process::Command::new("plutil")
        .args(["-remove", key, full.to_str().unwrap_or("")])
        .output()
        .map_err(|error| failed(format!("{tool} could not run plutil: {error}")))?;
    if output.status.success() {
        return Ok(());
    }
    Err(failed(format!(
        "{tool} could not remove {key} from {path}: {}",
        String::from_utf8_lossy(&output.stderr).trim()
    )))
}

fn g6_plist_scalar(text: &str) -> Value {
    if text == "true" {
        return json!(true);
    }
    if text == "false" {
        return json!(false);
    }
    if let Ok(value) = text.parse::<i64>() {
        return json!(value);
    }
    if let Ok(value) = text.parse::<f64>() {
        return json!(value);
    }
    json!(text)
}

fn g6_locale_for_path(path: &str) -> String {
    for part in path.split('/') {
        if let Some(locale) = part.strip_suffix(".lproj") {
            return locale.to_owned();
        }
    }
    "base".to_owned()
}

fn g6_language_for_extension(ext: &str) -> &'static str {
    match ext {
        "swift" => "Swift",
        "m" | "mm" | "h" => "Objective-C",
        "c" | "cpp" | "cc" | "hpp" => "C/C++",
        "ts" | "tsx" => "TypeScript",
        "js" | "jsx" => "JavaScript",
        "py" => "Python",
        "rs" => "Rust",
        "kt" | "kts" => "Kotlin",
        "java" => "Java",
        "md" => "Markdown",
        "json" => "JSON",
        "plist" => "Property List",
        "yaml" | "yml" => "YAML",
        "xml" => "XML",
        "png" | "jpg" | "jpeg" | "heic" | "webp" | "gif" => "Image",
        "" => "No extension",
        _ => "Other",
    }
}

fn g6_pbxproj_targets(content: &str) -> Vec<String> {
    let mut targets: Vec<String> = Vec::new();
    for caps in g5_regex_captures(r"isa = PBXNativeTarget;[^}]*?name = ([^;]+);", content) {
        let name = caps
            .get(1)
            .cloned()
            .flatten()
            .unwrap_or_default()
            .trim()
            .to_owned();
        if !name.is_empty() && !targets.contains(&name) {
            targets.push(name);
        }
    }
    targets
}

fn g6_resolve_file(
    cwd: &str,
    path: Option<&str>,
    query: &str,
    suffix: &str,
    tool: &str,
) -> Result<String, CallError> {
    if let Some(path) = path.filter(|p| !p.is_empty()) {
        return Ok(path.to_owned());
    }
    let entries = g5_list_workspace_files(cwd, query, 100)?;
    for entry in entries {
        if g6_is_dir(&entry) {
            continue;
        }
        let entry_path = g6_entry_path(&entry);
        if entry_path.ends_with(suffix) {
            return Ok(entry_path);
        }
    }
    Err(failed(format!(
        "{tool} found no file matching {query} in the workspace."
    )))
}

fn g6_resolve_catalog(cwd: &str, catalog: Option<&str>, tool: &str) -> Result<String, CallError> {
    if let Some(catalog) = catalog.filter(|c| !c.is_empty()) {
        if !catalog.ends_with(".xcassets") {
            return Err(failed(format!(
                "{tool} catalog path must end in .xcassets."
            )));
        }
        return Ok(catalog.to_owned());
    }
    let entries = g6_entries(cwd, None)?;
    for entry in entries {
        if g6_is_dir(&entry) && g6_entry_path(&entry).ends_with(".xcassets") {
            return Ok(g6_entry_path(&entry));
        }
    }
    Err(failed(format!(
        "{tool} found no .xcassets catalog in the workspace."
    )))
}

fn g6_colorset_contents(light_hex: &str, dark_hex: &str) -> Value {
    fn components(hex: &str) -> Value {
        let clean = hex.strip_prefix('#').unwrap_or(hex);
        let red = u32::from_str_radix(clean.get(0..2).unwrap_or("00"), 16).unwrap_or(0);
        let green = u32::from_str_radix(clean.get(2..4).unwrap_or("00"), 16).unwrap_or(0);
        let blue = u32::from_str_radix(clean.get(4..6).unwrap_or("00"), 16).unwrap_or(0);
        json!({
            "red": format!("{:.3}", red as f64 / 255.0),
            "green": format!("{:.3}", green as f64 / 255.0),
            "blue": format!("{:.3}", blue as f64 / 255.0),
            "alpha": "1.000",
        })
    }
    json!({
        "colors": [
            {"color": {"color-space": "srgb", "components": components(light_hex)}, "idiom": "universal"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "color": {"color-space": "srgb", "components": components(dark_hex)}, "idiom": "universal"},
        ],
        "info": {"author": "xcode", "version": 1},
    })
}

fn g6_parse_manifest(content: &str) -> Value {
    let mut name = String::new();
    if let Some(at) = content.find("Package(") {
        let rest = &content[at + "Package(".len()..];
        if let Some(found) = g5_first_capture(r#"name:\s*"([^"]+)""#, rest, 1) {
            name = found;
        }
    }
    let mut platforms: Vec<String> = Vec::new();
    for caps in g5_regex_captures(r"\.([A-Za-z]+)\(\.v([0-9_]+)\)", content) {
        let platform = caps.get(1).cloned().flatten().unwrap_or_default();
        let version = caps
            .get(2)
            .cloned()
            .flatten()
            .unwrap_or_default()
            .replace('_', ".");
        if !platform.is_empty() {
            platforms.push(format!("{platform} {version}"));
        }
    }
    let mut products: Vec<String> = Vec::new();
    for caps in g5_regex_captures(r#"\.(library|executable)\(\s*name:\s*"([^"]+)""#, content) {
        let product = caps.get(2).cloned().flatten().unwrap_or_default();
        if !product.is_empty() {
            products.push(product);
        }
    }
    let mut targets: Vec<String> = Vec::new();
    for caps in g5_regex_captures(
        r#"\.(target|testTarget|executableTarget|binaryTarget|systemLibrary|plugin)\(\s*name:\s*"([^"]+)""#,
        content,
    ) {
        let target = caps.get(2).cloned().flatten().unwrap_or_default();
        if !target.is_empty() {
            targets.push(target);
        }
    }
    let mut dependencies: Vec<Value> = Vec::new();
    for caps in g5_regex_captures(r#"\.package\(\s*url:\s*"([^"]+)"([^)]*)\)"#, content) {
        let url = caps.get(1).cloned().flatten().unwrap_or_default();
        let rest = caps.get(2).cloned().flatten().unwrap_or_default();
        let mut dep = serde_json::Map::new();
        dep.insert("url".to_owned(), json!(url));
        if let Some(req) =
            g5_regex_captures(r#"(from|exact|branch|revision):\s*"([^"]+)""#, &rest).into_iter().next()
        {
            let kind = req.get(1).cloned().flatten().unwrap_or_default();
            let version = req.get(2).cloned().flatten().unwrap_or_default();
            if !kind.is_empty() {
                dep.insert(kind, json!(version));
            }
        }
        if !url.is_empty() {
            dependencies.push(Value::Object(dep));
        }
    }
    for caps in g5_regex_captures(r#"\.package\(\s*path:\s*"([^"]+)""#, content) {
        let path = caps.get(1).cloned().flatten().unwrap_or_default();
        if !path.is_empty() {
            dependencies.push(json!({"path": path}));
        }
    }
    json!({
        "name": name,
        "platforms": platforms,
        "products": products,
        "targets": targets,
        "dependencies": dependencies,
    })
}

fn g6_parse_resolved(content: &str) -> Vec<(String, String, String)> {
    let mut out: Vec<(String, String, String)> = Vec::new();
    let Ok(value) = serde_json::from_str::<Value>(content) else {
        return out;
    };
    let Some(pins) = value.get("pins").and_then(Value::as_array) else {
        return out;
    };
    for pin in pins {
        let identity = pin
            .get("identity")
            .and_then(Value::as_str)
            .or_else(|| pin.get("package").and_then(Value::as_str))
            .unwrap_or("")
            .to_owned();
        let location = pin
            .get("location")
            .and_then(Value::as_str)
            .or_else(|| pin.get("repositoryURL").and_then(Value::as_str))
            .unwrap_or("")
            .to_owned();
        let version = pin
            .get("state")
            .and_then(|state| state.get("version"))
            .and_then(Value::as_str)
            .or_else(|| {
                pin.get("state")
                    .and_then(|state| state.get("revision"))
                    .and_then(Value::as_str)
            })
            .or_else(|| pin.get("version").and_then(Value::as_str))
            .unwrap_or("")
            .to_owned();
        if !identity.is_empty() || !location.is_empty() || !version.is_empty() {
            out.push((identity, location, version));
        }
    }
    out
}

fn g6_show_dependencies_names(value: &Value) -> Vec<String> {
    let mut names: Vec<String> = Vec::new();
    let Some(dependencies) = value.get("dependencies").and_then(Value::as_array) else {
        return names;
    };
    for dep in dependencies {
        if let Some(identity) = dep.get("identity").and_then(Value::as_str) {
            names.push(identity.to_owned());
        }
        names.extend(g6_show_dependencies_names(dep));
    }
    names
}

fn g6_dependency_audit(
    tool: &str,
    manifest: &Value,
    resolved_pins: &[(String, String, String)],
    shown: &[String],
    exit_code: i64,
    output: &str,
) -> Value {
    let mut missing_resolved: Vec<String> = Vec::new();
    let mut non_exact: Vec<Value> = Vec::new();
    let mut missing_from_manifest: Vec<String> = Vec::new();
    let resolved_identities: Vec<String> = resolved_pins
        .iter()
        .map(|(identity, _, _)| identity.clone())
        .collect();
    let manifest_deps: Vec<&Value> = manifest
        .get("dependencies")
        .and_then(Value::as_array)
        .map(|deps| deps.iter().collect())
        .unwrap_or_default();
    for dep in &manifest_deps {
        if let Some(url) = dep.get("url").and_then(Value::as_str) {
            let identity = Path::new(url)
                .file_stem()
                .map(|stem| stem.to_string_lossy().into_owned())
                .unwrap_or_else(|| url.to_owned());
            if !resolved_identities
                .iter()
                .any(|known| known.to_lowercase() == identity.to_lowercase())
            {
                missing_resolved.push(url.to_owned());
            }
            if dep.get("from").is_some() || dep.get("branch").is_some() {
                let requirement = dep
                    .get("from")
                    .and_then(Value::as_str)
                    .or_else(|| dep.get("branch").and_then(Value::as_str))
                    .unwrap_or("");
                non_exact.push(json!({"url": url, "requirement": requirement}));
            }
        }
    }
    for (identity, _, _) in resolved_pins {
        let in_manifest = manifest_deps.iter().any(|dep| {
            let Some(url) = dep.get("url").and_then(Value::as_str) else {
                return false;
            };
            let name = Path::new(url)
                .file_stem()
                .map(|stem| stem.to_string_lossy().into_owned())
                .unwrap_or_else(|| url.to_owned());
            name.to_lowercase() == identity.to_lowercase()
        });
        if !in_manifest {
            missing_from_manifest.push(identity.clone());
        }
    }
    json!({
        "tool": tool,
        "manifestName": manifest.get("name").cloned().unwrap_or(Value::Null),
        "manifestDependencies": manifest_deps.len(),
        "resolvedPins": resolved_pins.len(),
        "missingResolved": missing_resolved,
        "nonExactRequirements": non_exact,
        "resolvedMissingFromManifest": missing_from_manifest,
        "showDependencies": shown,
        "showDependenciesExitCode": exit_code,
        "output": output,
    })
}

fn g6_signing_from_pbxproj(tool: &str, path: &str, content: &str) -> Value {
    let mut values: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    for key in [
        "CODE_SIGN_STYLE",
        "DEVELOPMENT_TEAM",
        "PRODUCT_BUNDLE_IDENTIFIER",
        "CODE_SIGN_IDENTITY",
        "PROVISIONING_PROFILE_SPECIFIER",
    ] {
        let pattern = format!("{key}\\s*=\\s*([^;]+);");
        if let Some(found) = g5_first_capture(&pattern, content, 1) {
            values.insert(
                key.to_owned(),
                found.trim().trim_matches('"').to_owned(),
            );
        }
    }
    let get = |key: &str| -> Value {
        values
            .get(key)
            .map(|value| json!(value))
            .unwrap_or(Value::Null)
    };
    json!({
        "tool": tool,
        "path": path,
        "codeSignStyle": get("CODE_SIGN_STYLE"),
        "developmentTeam": get("DEVELOPMENT_TEAM"),
        "bundleIdentifier": get("PRODUCT_BUNDLE_IDENTIFIER"),
        "codeSignIdentity": get("CODE_SIGN_IDENTITY"),
        "provisioningProfileSpecifier": get("PROVISIONING_PROFILE_SPECIFIER"),
    })
}

fn g6_build_settings_json(output: &str) -> Value {
    let mut object = serde_json::Map::new();
    for line in output.lines() {
        let trimmed = line.trim();
        let matches = g5_regex_captures(r"^([A-Z0-9_]+)\s*=\s*(.+)$", trimmed);
        if let Some(first) = matches.first() {
            let key = first.get(1).cloned().flatten().unwrap_or_default();
            let value = first
                .get(2)
                .cloned()
                .flatten()
                .unwrap_or_default()
                .trim()
                .to_owned();
            if !key.is_empty() {
                object.insert(key, json!(value));
            }
        }
    }
    Value::Object(object)
}

fn g6_icon_sizes(platform: &str) -> Vec<(u32, &'static str, &'static str, &'static str)> {
    match platform {
        "macos" => vec![
            (16, "16x16", "mac", "1x"),
            (32, "16x16", "mac", "2x"),
            (32, "32x32", "mac", "1x"),
            (64, "32x32", "mac", "2x"),
            (128, "128x128", "mac", "1x"),
            (256, "128x128", "mac", "2x"),
            (256, "256x256", "mac", "1x"),
            (512, "256x256", "mac", "2x"),
            (512, "512x512", "mac", "1x"),
            (1024, "512x512", "mac", "2x"),
        ],
        "watchos" => vec![
            (48, "24x24", "watch", "2x"),
            (55, "27.5x27.5", "watch", "2x"),
            (58, "29x29", "watch", "2x"),
            (87, "29x29", "watch", "3x"),
            (80, "40x40", "watch", "2x"),
            (88, "44x44", "watch", "2x"),
            (100, "50x50", "watch", "2x"),
            (172, "86x86", "watch", "2x"),
            (196, "98x98", "watch", "2x"),
            (216, "108x108", "watch", "2x"),
            (1024, "1024x1024", "watch-marketing", "1x"),
        ],
        _ => vec![
            (40, "20x20", "iphone", "2x"),
            (60, "20x20", "iphone", "3x"),
            (58, "29x29", "iphone", "2x"),
            (87, "29x29", "iphone", "3x"),
            (80, "40x40", "iphone", "2x"),
            (120, "40x40", "iphone", "3x"),
            (120, "60x60", "iphone", "2x"),
            (180, "60x60", "iphone", "3x"),
            (76, "76x76", "ipad", "1x"),
            (152, "76x76", "ipad", "2x"),
            (167, "83.5x83.5", "ipad", "2x"),
            (1024, "1024x1024", "ios-marketing", "1x"),
        ],
    }
}

fn g6_app_icon_contents(generated: &[Value]) -> Value {
    let mut images: Vec<Value> = Vec::new();
    for entry in generated {
        let Some(size) = entry.get("size").and_then(Value::as_str) else {
            continue;
        };
        let Some(idiom) = entry.get("idiom").and_then(Value::as_str) else {
            continue;
        };
        let Some(scale) = entry.get("scale").and_then(Value::as_str) else {
            continue;
        };
        let Some(filename) = entry.get("filename").and_then(Value::as_str) else {
            continue;
        };
        images.push(json!({
            "idiom": idiom,
            "filename": filename,
            "scale": scale,
            "size": size,
        }));
    }
    json!({"images": images, "info": {"author": "xcode", "version": 1}})
}

fn g6_parse_ps(output: &str, filter: Option<&str>, limit: usize) -> Vec<Value> {
    let mut rows: Vec<Value> = Vec::new();
    for line in output.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let parts: Vec<&str> = trimmed.split_whitespace().collect();
        if parts.len() < 4 {
            continue;
        }
        let Ok(pid) = parts[0].parse::<i64>() else {
            continue;
        };
        let Ok(cpu) = parts[1].parse::<f64>() else {
            continue;
        };
        let Ok(mem) = parts[2].parse::<f64>() else {
            continue;
        };
        let command = parts[3..].join(" ");
        if let Some(filter) = filter.filter(|f| !f.is_empty()) {
            if !command.to_lowercase().contains(&filter.to_lowercase()) {
                continue;
            }
        }
        rows.push(json!({
            "pid": pid,
            "cpuPercent": cpu,
            "memoryPercent": mem,
            "command": command,
        }));
        if rows.len() >= limit {
            break;
        }
    }
    rows
}

fn g6_disk_space(tool: &str, path: &str, df_output: &str, du_output: &str) -> Value {
    let mut total_kilobytes: Option<i64> = None;
    let mut available_kilobytes: Option<i64> = None;
    let mut used_kilobytes: Option<i64> = None;
    let mut capacity_percent: Option<i64> = None;
    let mut mount_point: Option<String> = None;
    for line in df_output.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 9 {
            continue;
        }
        let Ok(total) = parts[1].parse::<i64>() else {
            continue;
        };
        let Ok(used) = parts[2].parse::<i64>() else {
            continue;
        };
        let Ok(available) = parts[3].parse::<i64>() else {
            continue;
        };
        total_kilobytes = Some(total);
        used_kilobytes = Some(used);
        available_kilobytes = Some(available);
        capacity_percent = parts[4].trim_end_matches('%').parse::<i64>().ok();
        mount_point = Some(parts[8..].join(" "));
    }
    let mut path_kilobytes: Option<i64> = None;
    if let Some(first) = du_output.split_whitespace().next() {
        path_kilobytes = first.parse::<i64>().ok();
    }
    json!({
        "tool": tool,
        "path": path,
        "totalKilobytes": total_kilobytes,
        "availableKilobytes": available_kilobytes,
        "usedKilobytes": used_kilobytes,
        "capacityPercent": capacity_percent,
        "mountPoint": mount_point,
        "pathKilobytes": path_kilobytes,
    })
}

fn g6_framework_audit(tool: &str, path: &str, content: &str) -> Value {
    let mut linked: Vec<Value> = Vec::new();
    let mut seen: Vec<String> = Vec::new();
    for line in content.lines() {
        if !line.contains("PBXBuildFile") || !line.contains(".framework") {
            continue;
        }
        let matches = g5_regex_captures(r"/\*\s*([A-Za-z0-9_.\-]+\.framework)\s*\*/", line);
        if let Some(first) = matches.first() {
            let name = first.get(1).cloned().flatten().unwrap_or_default();
            if !name.is_empty() && !seen.contains(&name) {
                seen.push(name.clone());
                linked.push(json!({"name": name, "weak": line.contains("Weak")}));
            }
        }
    }
    let mut available: Vec<String> = Vec::new();
    for line in content.lines() {
        if !line.contains("PBXFileReference") || !line.contains(".framework") {
            continue;
        }
        let matches = g5_regex_captures(r"/\*\s*([A-Za-z0-9_.\-]+\.framework)\s*\*/", line);
        if let Some(first) = matches.first() {
            let name = first.get(1).cloned().flatten().unwrap_or_default();
            if !name.is_empty() && !available.contains(&name) {
                available.push(name);
            }
        }
    }
    let mut sdkroots: Vec<String> = Vec::new();
    let mut deployment_targets: Vec<String> = Vec::new();
    for key in [
        "SDKROOT",
        "IPHONEOS_DEPLOYMENT_TARGET",
        "MACOSX_DEPLOYMENT_TARGET",
        "TVOS_DEPLOYMENT_TARGET",
        "WATCHOS_DEPLOYMENT_TARGET",
    ] {
        let pattern = format!("{key}\\s*=\\s*([^;]+);");
        for caps in g5_regex_captures(&pattern, content) {
            let value = caps
                .get(1)
                .cloned()
                .flatten()
                .unwrap_or_default()
                .trim()
                .to_owned();
            if value.is_empty() {
                continue;
            }
            if key == "SDKROOT" {
                if !sdkroots.contains(&value) {
                    sdkroots.push(value);
                }
            } else {
                let entry = format!("{key} {value}");
                if !deployment_targets.contains(&entry) {
                    deployment_targets.push(entry);
                }
            }
        }
    }
    json!({
        "tool": tool,
        "path": path,
        "linkedFrameworks": linked,
        "linkedCount": linked.len(),
        "availableFrameworks": available,
        "sdkroots": sdkroots,
        "deploymentTargets": deployment_targets,
    })
}

fn g6_bundle_resources(tool: &str, path: &str, content: &str, entries: &[Value]) -> Value {
    let mut build_files: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    for caps in g5_regex_captures(
        r"([0-9A-F]{24}) = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})",
        content,
    ) {
        let id = caps.get(1).cloned().flatten().unwrap_or_default();
        let reference = caps.get(2).cloned().flatten().unwrap_or_default();
        if !id.is_empty() && !reference.is_empty() {
            build_files.insert(id, reference);
        }
    }
    let mut file_paths: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    for caps in g5_regex_captures(
        r"([0-9A-F]{24}) /\* ([^*]+) \*/ = \{isa = PBXFileReference;[^}]*?path = ([^;]+);",
        content,
    ) {
        let id = caps.get(1).cloned().flatten().unwrap_or_default();
        let name = caps
            .get(2)
            .cloned()
            .flatten()
            .unwrap_or_default()
            .trim()
            .to_owned();
        let mut file_path = caps
            .get(3)
            .cloned()
            .flatten()
            .unwrap_or_default()
            .trim()
            .trim_matches('"')
            .to_owned();
        if file_path.is_empty() {
            file_path = name;
        }
        if !id.is_empty() && !file_path.is_empty() {
            file_paths.insert(id, file_path);
        }
    }
    let mut sizes: std::collections::HashMap<String, i64> = std::collections::HashMap::new();
    for entry in entries {
        if !g6_is_dir(entry) {
            sizes.insert(g6_entry_path(entry), g6_size(entry));
        }
    }
    let Some(section_start) = content.find("Begin PBXResourcesBuildPhase section") else {
        return json!({
            "tool": tool,
            "path": path,
            "resources": [],
            "missing": [],
            "duplicates": [],
            "note": "No PBXResourcesBuildPhase section found.",
        });
    };
    let Some(section_end) = content.find("End PBXResourcesBuildPhase section") else {
        return json!({
            "tool": tool,
            "path": path,
            "resources": [],
            "missing": [],
            "duplicates": [],
            "note": "No PBXResourcesBuildPhase section found.",
        });
    };
    let section = &content[section_start + "Begin PBXResourcesBuildPhase section".len()..section_end];
    let mut resources: Vec<Value> = Vec::new();
    let mut seen_names: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    let mut missing: Vec<String> = Vec::new();
    for caps in g5_regex_captures(r"([0-9A-F]{24}) /\*", section) {
        let id = caps.get(1).cloned().flatten().unwrap_or_default();
        let Some(reference) = build_files.get(&id) else {
            continue;
        };
        let Some(file_path) = file_paths.get(reference) else {
            continue;
        };
        let name = g6_basename(file_path);
        *seen_names.entry(name).or_insert(0) += 1;
        let found = sizes.contains_key(file_path)
            || sizes.keys().any(|key| key.ends_with(&format!("/{file_path}")));
        if !found {
            missing.push(file_path.clone());
        }
        let bytes = sizes
            .get(file_path)
            .copied()
            .or_else(|| {
                sizes
                    .iter()
                    .find(|(key, _)| key.ends_with(&format!("/{file_path}")))
                    .map(|(_, value)| *value)
            })
            .unwrap_or(0);
        resources.push(json!({"path": file_path, "found": found, "bytes": bytes}));
    }
    let mut duplicates: Vec<String> = seen_names
        .iter()
        .filter(|(_, count)| **count > 1)
        .map(|(name, _)| name.clone())
        .collect();
    duplicates.sort();
    json!({
        "tool": tool,
        "path": path,
        "resources": resources,
        "resourceCount": resources.len(),
        "missing": missing,
        "duplicates": duplicates,
    })
}

fn g6_core_data_model(tool: &str, path: &str, content: &str) -> Value {
    let Some(regex) = g5_regex(r#"<entity\s+name="([^"]+)""#) else {
        return json!({"path": path, "entities": [], "entityCount": 0});
    };
    let starts: Vec<(usize, String)> = regex
        .captures_iter(content)
        .filter_map(|caps| {
            let m = caps.get(0)?;
            let name = caps.get(1)?.as_str().to_owned();
            Some((m.start(), name))
        })
        .collect();
    let mut entities: Vec<Value> = Vec::new();
    for (index, (start, name)) in starts.iter().enumerate() {
        let end = starts
            .get(index + 1)
            .map(|(next, _)| *next)
            .unwrap_or(content.len());
        let chunk = &content[*start..end];
        let mut attributes: Vec<Value> = Vec::new();
        for caps in g5_regex_captures(
            r#"<attribute\s+name="([^"]+)"[^>]*attributeType="([^"]+)""#,
            chunk,
        ) {
            attributes.push(json!({
                "name": caps.get(1).cloned().flatten().unwrap_or_default(),
                "type": caps.get(2).cloned().flatten().unwrap_or_default(),
            }));
        }
        let mut relationships: Vec<Value> = Vec::new();
        for caps in g5_regex_captures(
            r#"<relationship\s+name="([^"]+)"[^>]*destinationEntity="([^"]+)""#,
            chunk,
        ) {
            relationships.push(json!({
                "name": caps.get(1).cloned().flatten().unwrap_or_default(),
                "destination": caps.get(2).cloned().flatten().unwrap_or_default(),
            }));
        }
        entities.push(json!({
            "name": name,
            "attributes": attributes,
            "relationships": relationships,
        }));
    }
    json!({
        "path": path,
        "entities": entities,
        "entityCount": entities.len(),
    })
}

fn g6_privacy_audit(tool: &str, path: &str, plist: &Value) -> Value {
    let mut issues: Vec<String> = Vec::new();
    let tracking = plist
        .get("NSPrivacyTracking")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if tracking {
        let domains_ok = plist
            .get("NSPrivacyTrackingDomains")
            .and_then(Value::as_array)
            .map(|domains| !domains.is_empty())
            .unwrap_or(false);
        if !domains_ok {
            issues.push(
                "NSPrivacyTracking is true but NSPrivacyTrackingDomains is missing or empty."
                    .to_owned(),
            );
        }
    }
    if let Some(collected) = plist
        .get("NSPrivacyCollectedDataTypes")
        .and_then(Value::as_array)
    {
        for (index, entry) in collected.iter().enumerate() {
            for key in [
                "NSPrivacyCollectedDataType",
                "NSPrivacyCollectedDataTypeLinked",
                "NSPrivacyCollectedDataTypeTracking",
                "NSPrivacyCollectedDataTypePurposes",
            ] {
                if entry.get(key).is_none() {
                    issues.push(format!(
                        "Collected data type at index {index} is missing {key}."
                    ));
                }
            }
        }
    } else if plist.get("NSPrivacyCollectedDataTypes").is_some() {
        issues.push(
            "NSPrivacyCollectedDataTypes is present but is not an array of dictionaries."
                .to_owned(),
        );
    }
    let categories_requiring_reasons = [
        "NSPrivacyAccessedAPICategoryFileTimestamp",
        "NSPrivacyAccessedAPICategorySystemBootTime",
        "NSPrivacyAccessedAPICategoryDiskSpace",
        "NSPrivacyAccessedAPICategoryActiveKeyboards",
        "NSPrivacyAccessedAPICategoryUserDefaults",
    ];
    if let Some(accessed) = plist.get("NSPrivacyAccessedAPITypes").and_then(Value::as_array) {
        for (index, entry) in accessed.iter().enumerate() {
            let Some(category) = entry
                .get("NSPrivacyAccessedAPICategory")
                .and_then(Value::as_str)
            else {
                issues.push(format!(
                    "Accessed API type at index {index} is missing NSPrivacyAccessedAPICategory."
                ));
                continue;
            };
            if categories_requiring_reasons.contains(&category) {
                let reasons_ok = entry
                    .get("NSPrivacyAccessedAPITypeReasons")
                    .and_then(Value::as_array)
                    .map(|reasons| !reasons.is_empty())
                    .unwrap_or(false);
                if !reasons_ok {
                    issues.push(format!(
                        "{category} requires NSPrivacyAccessedAPITypeReasons."
                    ));
                }
            }
        }
    }
    json!({
        "tool": tool,
        "path": path,
        "tracking": tracking,
        "collectedDataTypes": plist.get("NSPrivacyCollectedDataTypes").and_then(Value::as_array).map(|v| v.len()).unwrap_or(0),
        "accessedApiTypes": plist.get("NSPrivacyAccessedAPITypes").and_then(Value::as_array).map(|v| v.len()).unwrap_or(0),
        "issues": issues,
        "issueCount": issues.len(),
    })
}

fn g6_dir_size_recursive(dir: &Path) -> (i64, usize) {
    let mut bytes: i64 = 0;
    let mut files: usize = 0;
    let Ok(entries) = std::fs::read_dir(dir) else {
        return (0, 0);
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if let Ok(metadata) = entry.metadata() {
            if metadata.is_dir() {
                let (child_bytes, child_files) = g6_dir_size_recursive(&path);
                bytes += child_bytes;
                files += child_files;
            } else {
                bytes += metadata.len() as i64;
                files += 1;
            }
        }
    }
    (bytes, files)
}

fn g6_derived_data(tool: &str, path: Option<&str>, limit: usize) -> Value {
    let home = std::env::var("HOME").unwrap_or_default();
    let default_path = format!("{home}/Library/Developer/Xcode/DerivedData");
    let root = path
        .filter(|p| !p.is_empty())
        .map(|p| {
            if let Some(rest) = p.strip_prefix("~/") {
                format!("{home}/{rest}")
            } else {
                p.to_owned()
            }
        })
        .unwrap_or(default_path);
    let root_path = Path::new(&root);
    let mut directories: Vec<Value> = Vec::new();
    let mut exists = false;
    if let Ok(entries) = std::fs::read_dir(root_path) {
        exists = true;
        let mut names: Vec<String> = entries
            .flatten()
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        for name in names {
            let dir = root_path.join(&name);
            if !dir.is_dir() {
                continue;
            }
            let (bytes, files) = g6_dir_size_recursive(&dir);
            directories.push(json!({
                "path": dir.to_string_lossy(),
                "name": name,
                "bytes": bytes,
                "files": files,
            }));
        }
    }
    directories.sort_by(|a, b| {
        b["bytes"]
            .as_i64()
            .unwrap_or(0)
            .cmp(&a["bytes"].as_i64().unwrap_or(0))
    });
    let total_bytes: i64 = directories
        .iter()
        .map(|dir| dir["bytes"].as_i64().unwrap_or(0))
        .sum();
    let shown: Vec<Value> = directories.into_iter().take(limit).collect();
    json!({
        "tool": tool,
        "path": root,
        "exists": exists,
        "directories": shown,
        "totalBytes": total_bytes,
    })
}

fn g6_env_info(tool: &str) -> Value {
    let arch = g6_command_output(&["uname", "-m"]).unwrap_or_else(|| "unknown".to_owned());
    let os_version =
        g6_command_output(&["sw_vers", "-productVersion"]).unwrap_or_else(|| "unknown".to_owned());
    let os_build =
        g6_command_output(&["sw_vers", "-buildVersion"]).unwrap_or_default();
    let cpu_count = g6_command_output(&["sysctl", "-n", "hw.ncpu"])
        .and_then(|text| text.parse::<i64>().ok())
        .unwrap_or(0);
    let physical_memory = g6_command_output(&["sysctl", "-n", "hw.memsize"])
        .and_then(|text| text.parse::<i64>().ok())
        .unwrap_or(0);
    let host_name = g6_command_output(&["hostname"]).unwrap_or_default();
    let uptime_seconds = g6_command_output(&["sysctl", "-n", "kern.boottime"])
        .and_then(|text| {
            let caps = g5_regex_captures(r"sec = ([0-9]+)", &text);
            caps.first()
                .and_then(|first| first.get(1).cloned().flatten())
                .and_then(|sec| sec.parse::<u64>().ok())
        })
        .map(|boot| {
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|now| now.as_secs().saturating_sub(boot) as f64)
                .unwrap_or(0.0)
        })
        .unwrap_or(0.0);
    json!({
        "tool": tool,
        "osVersion": os_version,
        "osBuild": os_build,
        "arch": arch,
        "cpuCount": cpu_count,
        "physicalMemoryBytes": physical_memory,
        "hostName": host_name,
        "uptimeSeconds": uptime_seconds,
    })
}

fn g6_find_pid(value: &Value, name: &str) -> Option<i64> {
    match value {
        Value::Array(items) => items.iter().find_map(|item| g6_find_pid(item, name)),
        Value::Object(map) => {
            if map.get("name").and_then(Value::as_str) == Some(name)
                || map.get("bundleIdentifier").and_then(Value::as_str) == Some(name)
            {
                return map.get("pid").and_then(Value::as_i64);
            }
            map.values().find_map(|item| g6_find_pid(item, name))
        }
        _ => None,
    }
}

fn g6_scope_hits(
    hits: Vec<(String, i64, String)>,
    path: Option<&str>,
) -> Vec<(String, i64, String)> {
    let Some(path) = path.filter(|p| !p.is_empty()) else {
        return hits;
    };
    hits.into_iter()
        .filter(|(hit_path, _, _)| hit_path == path || hit_path.starts_with(&format!("{path}/")))
        .collect()
}

fn g6_call(state: &crate::ServerState, name: &str, args: &Value) -> Result<Value, CallError> {
    let _ = state;
    let cwd = req_str(args, "cwd", name)?;
    let path = opt_str(args, "path");
    let limit = opt_u64(args, "limit").unwrap_or(200).clamp(1, 1000) as usize;
    match name {
        "framework_linker_auditor" => {
            let pbxproj = g5_resolve_pbxproj(&cwd, path.as_deref(), name)?;
            let content = read_text_file_at(&cwd, &pbxproj)?;
            Ok(g6_framework_audit(name, &pbxproj, &content))
        }
        "string_catalog_migrator" => {
            let source_language = opt_str(args, "sourceLanguage").unwrap_or_else(|| "en".to_owned());
            let mut files: Vec<(String, String)> = Vec::new();
            let single_file = path
                .as_deref()
                .map(|p| p.ends_with(".strings") || p.ends_with(".stringsdict"))
                .unwrap_or(false);
            if let Some(path) = path.as_deref().filter(|p| !p.is_empty()) {
                if single_file {
                    let content = read_text_file_at(&cwd, path)?;
                    files.push((path.to_owned(), content));
                }
            }
            if files.is_empty() {
                files = g5_read_text_files(&cwd, path.as_deref(), &[".strings", ".stringsdict"], 100)?;
            }
            if files.is_empty() {
                return Err(failed(format!(
                    "{name} found no .strings or .stringsdict files."
                )));
            }
            let mut migrated: Vec<Value> = Vec::new();
            let mut skipped: Vec<Value> = Vec::new();
            for (file_path, content) in &files {
                if file_path.ends_with(".stringsdict") {
                    skipped.push(json!({
                        "path": file_path,
                        "reason": "stringsdict plural forms need manual mapping and are not migrated.",
                    }));
                    continue;
                }
                let pairs = g6_strings_pairs(content);
                let mut strings = serde_json::Map::new();
                for (key, value, _) in &pairs {
                    strings.insert(
                        key.clone(),
                        json!({"localizations": {source_language.clone(): {"stringUnit": {"state": "translated", "value": value}}}}),
                    );
                }
                let catalog = json!({
                    "sourceLanguage": source_language,
                    "strings": strings,
                    "version": "1.0",
                });
                let out_path = format!(
                    "{}.xcstrings",
                    file_path.strip_suffix(".strings").unwrap_or(file_path)
                );
                let text = g6_xcstrings_encode(&catalog, name)?;
                write_text_file(&cwd, &out_path, &text)?;
                let verify = read_text_file_at(&cwd, &out_path)?;
                let decoded: Value = serde_json::from_str(&verify)
                    .map_err(|error| failed(format!("{name} verification failed: {error}")))?;
                let decoded_count = decoded
                    .get("strings")
                    .and_then(Value::as_object)
                    .map(|strings| strings.len())
                    .unwrap_or(0);
                migrated.push(json!({
                    "source": file_path,
                    "catalog": out_path,
                    "keys": pairs.len(),
                    "verified": decoded_count == pairs.len(),
                }));
            }
            Ok(json!({
                "tool": name,
                "migrated": migrated,
                "skipped": skipped,
                "count": migrated.len(),
            }))
        }
        "symbol_reference_graph" => {
            let symbol = req_str(args, "symbol", name)?;
            let escaped = g5_escape_regex(&symbol);
            let declaration_hits = g5_search_regex_hits(
                &cwd,
                &format!(r"(func|class|struct|enum|protocol|let|var|typealias|actor)\s+{escaped}\b"),
                limit as u64,
            )?;
            let reference_hits = g5_search_regex_hits(
                &cwd,
                &format!(r"\b{escaped}\b"),
                limit as u64,
            )?;
            let scoped_declarations = g6_scope_hits(declaration_hits, path.as_deref());
            let scoped_references = g6_scope_hits(reference_hits, path.as_deref());
            let definitions: Vec<Value> = scoped_declarations
                .iter()
                .map(|(hit_path, line, text)| {
                    json!({"path": hit_path, "lineNumber": line, "lineText": text})
                })
                .collect();
            let definition_keys: Vec<String> = scoped_declarations
                .iter()
                .map(|(hit_path, line, _)| format!("{hit_path}:{line}"))
                .collect();
            let references: Vec<Value> = scoped_references
                .iter()
                .filter(|(hit_path, line, _)| {
                    !definition_keys.contains(&format!("{hit_path}:{line}"))
                })
                .map(|(hit_path, line, text)| {
                    json!({"path": hit_path, "lineNumber": line, "lineText": text})
                })
                .collect();
            Ok(json!({
                "tool": name,
                "symbol": symbol,
                "definitions": definitions,
                "references": references,
                "definitionCount": definitions.len(),
                "referenceCount": references.len(),
            }))
        }
        "podfile_inspector" => {
            let podfile = g6_resolve_file(&cwd, path.as_deref(), "Podfile", "/Podfile", name)
                .or_else(|_| {
                    g6_resolve_file(&cwd, path.as_deref(), "Podfile", "Podfile", name)
                })?;
            let content = read_text_file_at(&cwd, &podfile)?;
            let mut pods: Vec<Value> = Vec::new();
            let mut targets: Vec<String> = Vec::new();
            let mut current_target = String::new();
            let mut platform = String::new();
            for line in content.lines() {
                let trimmed = line.trim();
                if let Some(first) = g5_regex_captures(
                    r#"^target\s+['"]([^'"]+)['"]\s+do"#,
                    trimmed,
                )
                .into_iter()
                .next()
                {
                    let target = first.get(1).cloned().flatten().unwrap_or_default();
                    targets.push(target.clone());
                    current_target = target;
                    continue;
                }
                if trimmed == "end" {
                    current_target = String::new();
                    continue;
                }
                if let Some(first) = g5_regex_captures(
                    r#"^platform\s+:(\w+),\s*['"]([^'"]+)['"]"#,
                    trimmed,
                )
                .into_iter()
                .next()
                {
                    let platform_name = first.get(1).cloned().flatten().unwrap_or_default();
                    let version = first.get(2).cloned().flatten().unwrap_or_default();
                    platform = format!("{platform_name} {version}");
                    continue;
                }
                if let Some(first) = g5_regex_captures(
                    r#"^pod\s+['"]([^'"]+)['"](?:\s*,\s*['"]([^'"]+)['"])?"#,
                    trimmed,
                )
                .into_iter()
                .next()
                {
                    let pod_name = first.get(1).cloned().flatten().unwrap_or_default();
                    let requirement = first.get(2).cloned().flatten().unwrap_or_default();
                    pods.push(json!({
                        "name": pod_name,
                        "requirement": requirement,
                        "target": current_target,
                    }));
                }
            }
            let mut locked: Vec<Value> = Vec::new();
            let dir = g6_dirname(&podfile);
            let lock_path = if dir.is_empty() {
                "Podfile.lock".to_owned()
            } else {
                format!("{dir}/Podfile.lock")
            };
            if let Ok(lock_content) = read_text_file_at(&cwd, &lock_path) {
                let mut in_pods = false;
                for line in lock_content.lines() {
                    if line.starts_with("PODS:") {
                        in_pods = true;
                        continue;
                    }
                    if in_pods {
                        if line.is_empty()
                            || (!line.starts_with(' ') && !line.starts_with('\t'))
                        {
                            break;
                        }
                        if let Some(first) = g5_regex_captures(
                            r"^\s*-\s*([A-Za-z0-9_./-]+) \(([^)]+)\)",
                            line,
                        )
                        .into_iter()
                        .next()
                        {
                            let pod_name = first.get(1).cloned().flatten().unwrap_or_default();
                            let version = first.get(2).cloned().flatten().unwrap_or_default();
                            if !pod_name.is_empty() {
                                locked.push(json!({"name": pod_name, "version": version}));
                            }
                        }
                    }
                }
            }
            Ok(json!({
                "tool": name,
                "path": podfile,
                "platform": platform,
                "targets": targets,
                "pods": pods,
                "podCount": pods.len(),
                "locked": locked,
                "lockPresent": !locked.is_empty(),
            }))
        }
        "carthage_cartfile_inspector" => {
            let cartfile = g6_resolve_file(&cwd, path.as_deref(), "Cartfile", "/Cartfile", name)
                .or_else(|_| {
                    g6_resolve_file(&cwd, path.as_deref(), "Cartfile", "Cartfile", name)
                })?;
            let content = read_text_file_at(&cwd, &cartfile)?;
            let mut dependencies: Vec<Value> = Vec::new();
            for line in content.lines() {
                let trimmed = line.trim();
                if let Some(first) = g5_regex_captures(
                    r#"^(github|git|binary)\s+"([^"]+)"(?:\s+"([^"]+)")?"#,
                    trimmed,
                )
                .into_iter()
                .next()
                {
                    dependencies.push(json!({
                        "source": first.get(1).cloned().flatten().unwrap_or_default(),
                        "name": first.get(2).cloned().flatten().unwrap_or_default(),
                        "requirement": first.get(3).cloned().flatten().unwrap_or_default(),
                    }));
                }
            }
            let mut resolved: Vec<Value> = Vec::new();
            let dir = g6_dirname(&cartfile);
            let resolved_path = if dir.is_empty() {
                "Cartfile.resolved".to_owned()
            } else {
                format!("{dir}/Cartfile.resolved")
            };
            if let Ok(resolved_content) = read_text_file_at(&cwd, &resolved_path) {
                for line in resolved_content.lines() {
                    let trimmed = line.trim();
                    if let Some(first) = g5_regex_captures(
                        r#"^(github|git|binary)\s+"([^"]+)"\s+"([^"]+)""#,
                        trimmed,
                    )
                    .into_iter()
                    .next()
                    {
                        resolved.push(json!({
                            "source": first.get(1).cloned().flatten().unwrap_or_default(),
                            "name": first.get(2).cloned().flatten().unwrap_or_default(),
                            "version": first.get(3).cloned().flatten().unwrap_or_default(),
                        }));
                    }
                }
            }
            Ok(json!({
                "tool": name,
                "path": cartfile,
                "dependencies": dependencies,
                "dependencyCount": dependencies.len(),
                "resolved": resolved,
                "resolvedPresent": !resolved.is_empty(),
            }))
        }
        "package_manifest_read" => {
            let manifest_path = path.unwrap_or_else(|| "Package.swift".to_owned());
            g6_validate_relative(&manifest_path, name)?;
            let content = read_text_file_at(&cwd, &manifest_path)?;
            let manifest = g6_parse_manifest(&content);
            Ok(json!({
                "tool": name,
                "path": manifest_path,
                "name": manifest.get("name").cloned().unwrap_or(Value::Null),
                "platforms": manifest.get("platforms").cloned().unwrap_or(Value::Null),
                "products": manifest.get("products").cloned().unwrap_or(Value::Null),
                "targets": manifest.get("targets").cloned().unwrap_or(Value::Null),
                "dependencies": manifest.get("dependencies").cloned().unwrap_or(Value::Null),
            }))
        }
        "package_dependency_add" => {
            let url = req_str(args, "url", name)?;
            let version = req_str(args, "version", name)?;
            let manifest_path = path.unwrap_or_else(|| "Package.swift".to_owned());
            g6_validate_relative(&manifest_path, name)?;
            if !url.starts_with("https://") && !url.starts_with("git@") {
                return Err(failed(format!(
                    "{name} url must be an https or git@ URL."
                )));
            }
            let mut content = read_text_file_at(&cwd, &manifest_path)?;
            if content.contains(&url) {
                return Err(failed(format!(
                    "Package.swift already references {url}."
                )));
            }
            let Some(dep_at) = content.find("dependencies: [") else {
                return Err(failed(format!(
                    "{name} found no dependencies array in Package.swift."
                )));
            };
            let insertion = format!("\n        .package(url: \"{url}\", from: \"{version}\"),");
            content.insert_str(dep_at + "dependencies: [".len(), &insertion);
            let mut wired = false;
            let mut wiring_note = String::new();
            if let (Some(product), Some(target)) =
                (opt_str(args, "product"), opt_str(args, "target"))
            {
                let package_name = Path::new(&url)
                    .file_stem()
                    .map(|stem| stem.to_string_lossy().into_owned())
                    .unwrap_or_default();
                let escaped_target = g5_escape_regex(&target);
                let pattern = format!(
                    r#"\.(target|executableTarget|testTarget)\(\s*name:\s*"{escaped_target}"[^)]*?dependencies:\s*\["#
                );
                if let Some(regex) = g5_regex(&pattern) {
                    if let Some(matched) = regex.find(&content) {
                        let wiring = format!(
                            "\n            .product(name: \"{product}\", package: \"{package_name}\"),"
                        );
                        content.insert_str(matched.end(), &wiring);
                        wired = true;
                    } else {
                        wiring_note =
                            format!("Target {target} has no dependencies array to wire into.");
                    }
                } else {
                    wiring_note =
                        format!("Target {target} has no dependencies array to wire into.");
                }
            }
            write_text_file(&cwd, &manifest_path, &content)?;
            let verify = read_text_file_at(&cwd, &manifest_path)?;
            let parsed = g6_parse_manifest(&verify);
            let present = parsed
                .get("dependencies")
                .and_then(Value::as_array)
                .map(|deps| {
                    deps.iter()
                        .any(|dep| dep.get("url").and_then(Value::as_str) == Some(url.as_str()))
                })
                .unwrap_or(false);
            if !present {
                return Err(failed(format!(
                    "{name} verification failed: the dependency is not present after writing."
                )));
            }
            Ok(json!({
                "tool": name,
                "path": manifest_path,
                "url": url,
                "version": version,
                "added": true,
                "wired": wired,
                "wiringNote": wiring_note,
            }))
        }
        "asset_catalog_list" => {
            let entries = g6_entries(&cwd, path.as_deref())?;
            let catalogs: Vec<&Value> = entries
                .iter()
                .filter(|entry| g6_is_dir(entry) && g6_entry_path(entry).ends_with(".xcassets"))
                .collect();
            let mut out: Vec<Value> = Vec::new();
            for catalog in catalogs {
                let catalog_path = g6_entry_path(catalog);
                let prefix = format!("{catalog_path}/");
                let mut counts: std::collections::HashMap<&str, usize> =
                    std::collections::HashMap::new();
                let mut names: Vec<String> = Vec::new();
                for entry in &entries {
                    if !g6_is_dir(entry) {
                        continue;
                    }
                    let entry_path = g6_entry_path(entry);
                    if !entry_path.starts_with(&prefix) {
                        continue;
                    }
                    let suffix = g6_basename(&entry_path);
                    let kind = if suffix.ends_with(".imageset") {
                        Some("image")
                    } else if suffix.ends_with(".colorset") {
                        Some("color")
                    } else if suffix.ends_with(".appiconset") {
                        Some("icon")
                    } else if suffix.ends_with(".dataset") {
                        Some("dataset")
                    } else if suffix.ends_with(".symbolset") {
                        Some("symbol")
                    } else {
                        None
                    };
                    if let Some(kind) = kind {
                        *counts.entry(kind).or_insert(0) += 1;
                        names.push(suffix);
                    }
                }
                out.push(json!({
                    "catalog": catalog_path,
                    "imageSets": counts.get("image").copied().unwrap_or(0),
                    "colorSets": counts.get("color").copied().unwrap_or(0),
                    "iconSets": counts.get("icon").copied().unwrap_or(0),
                    "dataSets": counts.get("dataset").copied().unwrap_or(0),
                    "symbolSets": counts.get("symbol").copied().unwrap_or(0),
                    "sets": names,
                }));
            }
            Ok(json!({
                "tool": name,
                "catalogs": out,
                "catalogCount": out.len(),
            }))
        }
        "asset_image_add" => {
            let image_name = req_str(args, "imageName", name)?;
            let source = req_str(args, "source", name)?;
            g6_validate_relative(&source, name)?;
            if image_name.is_empty()
                || image_name.contains('/')
                || image_name.contains('\\')
            {
                return Err(failed(format!(
                    "{name} imageName must be a single name without a path separator."
                )));
            }
            let catalog = g6_resolve_catalog(&cwd, opt_str(args, "catalog").as_deref(), name)?;
            let set_path = format!("{catalog}/{image_name}.imageset");
            let file_name = g6_basename(&source);
            let set_dir = Path::new(&cwd).join(&set_path);
            std::fs::create_dir_all(&set_dir)
                .map_err(|error| failed(format!("{name} could not create {set_path}: {error}")))?;
            std::fs::copy(Path::new(&cwd).join(&source), set_dir.join(&file_name))
                .map_err(|error| failed(format!("{name} could not copy {source}: {error}")))?;
            let contents = json!({
                "images": [{"filename": file_name, "idiom": "universal", "scale": "1x"}],
                "info": {"author": "xcode", "version": 1},
            });
            let contents_text = serde_json::to_string_pretty(&contents)
                .map_err(|error| failed(format!("{name} could not serialize Contents.json: {error}")))?;
            write_text_file(&cwd, &format!("{set_path}/Contents.json"), &contents_text)?;
            let verify = read_text_file_at(&cwd, &format!("{set_path}/Contents.json"))?;
            Ok(json!({
                "tool": name,
                "catalog": catalog,
                "set": set_path,
                "image": file_name,
                "verified": verify.contains(&file_name),
            }))
        }
        "strings_localization" => {
            let file_path = req_str(args, "path", name)?;
            let action = req_str(args, "action", name)?;
            let key = req_str(args, "key", name)?;
            g6_validate_relative(&file_path, name)?;
            if !["get", "set", "delete"].contains(&action.as_str()) {
                return Err(failed(format!(
                    "{name} action must be get, set, or delete."
                )));
            }
            if file_path.ends_with(".xcstrings") {
                let content = read_text_file_at(&cwd, &file_path)?;
                let mut catalog: Value = serde_json::from_str(&content)
                    .map_err(|error| failed(format!("{name} catalog was not valid JSON: {error}")))?;
                if !catalog.is_object() {
                    return Err(failed(format!("{name} catalog root is not a JSON object.")));
                }
                let locale = opt_str(args, "locale").unwrap_or_else(|| {
                    catalog
                        .get("sourceLanguage")
                        .and_then(Value::as_str)
                        .unwrap_or("en")
                        .to_owned()
                });
                let keys = g6_xcstrings_keys(&catalog);
                match action.as_str() {
                    "get" => {
                        let value = keys
                            .iter()
                            .find(|(found_key, _)| found_key == &key)
                            .and_then(|(_, locales)| {
                                locales
                                    .iter()
                                    .find(|(found_locale, _)| found_locale == &locale)
                                    .map(|(_, value)| value.clone())
                            });
                        return Ok(json!({
                            "tool": name,
                            "path": file_path,
                            "key": key,
                            "locale": locale,
                            "found": value.is_some(),
                            "value": value,
                        }));
                    }
                    "set" => {
                        let value = req_str(args, "value", name)?;
                        g6_xcstrings_set(&mut catalog, &key, &locale, &value, "translated");
                        let text = g6_xcstrings_encode(&catalog, name)?;
                        write_text_file(&cwd, &file_path, &text)?;
                        return Ok(json!({
                            "tool": name,
                            "path": file_path,
                            "key": key,
                            "locale": locale,
                            "value": value,
                            "updated": true,
                        }));
                    }
                    _ => {
                        let mut strings = catalog
                            .get("strings")
                            .and_then(Value::as_object)
                            .cloned()
                            .unwrap_or_default();
                        let Some(entry) = strings.get_mut(&key) else {
                            return Err(failed(format!("Key {key} not found in {file_path}.")));
                        };
                        if let Some(localizations) = entry
                            .get_mut("localizations")
                            .and_then(Value::as_object_mut)
                        {
                            localizations.remove(&locale);
                        }
                        if let Some(object) = catalog.as_object_mut() {
                            object.insert("strings".to_owned(), Value::Object(strings));
                        }
                        let text = g6_xcstrings_encode(&catalog, name)?;
                        write_text_file(&cwd, &file_path, &text)?;
                        return Ok(json!({
                            "tool": name,
                            "path": file_path,
                            "key": key,
                            "locale": locale,
                            "deleted": true,
                        }));
                    }
                }
            }
            if !file_path.ends_with(".strings") {
                return Err(failed(format!(
                    "{name} path must end in .strings or .xcstrings."
                )));
            }
            let content = read_text_file_at(&cwd, &file_path)?;
            let mut pairs = g6_strings_pairs(&content);
            match action.as_str() {
                "get" => {
                    let found = pairs.iter().find(|(found_key, _, _)| found_key == &key);
                    return Ok(json!({
                        "tool": name,
                        "path": file_path,
                        "key": key,
                        "found": found.is_some(),
                        "value": found.map(|(_, value, _)| value.clone()),
                    }));
                }
                "set" => {
                    let value = req_str(args, "value", name)?;
                    if let Some(existing) = pairs.iter_mut().find(|(found_key, _, _)| found_key == &key) {
                        existing.1 = value.clone();
                    } else {
                        pairs.push((key.clone(), value.clone(), pairs.len() + 1));
                    }
                    let serialized = g6_serialize_strings(
                        &pairs
                            .iter()
                            .map(|(pair_key, pair_value, _)| (pair_key.clone(), pair_value.clone()))
                            .collect::<Vec<(String, String)>>(),
                    );
                    write_text_file(&cwd, &file_path, &serialized)?;
                    return Ok(json!({
                        "tool": name,
                        "path": file_path,
                        "key": key,
                        "value": value,
                        "updated": true,
                    }));
                }
                _ => {
                    if !pairs.iter().any(|(found_key, _, _)| found_key == &key) {
                        return Err(failed(format!("Key {key} not found in {file_path}.")));
                    }
                    pairs.retain(|(found_key, _, _)| found_key != &key);
                    let serialized = g6_serialize_strings(
                        &pairs
                            .iter()
                            .map(|(pair_key, pair_value, _)| (pair_key.clone(), pair_value.clone()))
                            .collect::<Vec<(String, String)>>(),
                    );
                    write_text_file(&cwd, &file_path, &serialized)?;
                    return Ok(json!({
                        "tool": name,
                        "path": file_path,
                        "key": key,
                        "deleted": true,
                    }));
                }
            }
        }
        "localization_audit" => {
            let strings_files = g5_read_text_files(&cwd, path.as_deref(), &[".strings"], 200)?;
            let catalog_files = g5_read_text_files(&cwd, path.as_deref(), &[".xcstrings"], 50)?;
            let mut keys_by_locale: std::collections::HashMap<String, std::collections::HashSet<String>> =
                std::collections::HashMap::new();
            let mut all_keys: std::collections::HashSet<String> = std::collections::HashSet::new();
            for (file_path, content) in &strings_files {
                let locale = g6_locale_for_path(file_path);
                let keys: std::collections::HashSet<String> = g6_strings_pairs(content)
                    .into_iter()
                    .map(|(key, _, _)| key)
                    .collect();
                keys_by_locale
                    .entry(locale)
                    .or_default()
                    .extend(keys.iter().cloned());
                all_keys.extend(keys);
            }
            for (_, content) in &catalog_files {
                if let Ok(catalog) = serde_json::from_str::<Value>(content) {
                    for (key, locales) in g6_xcstrings_keys(&catalog) {
                        all_keys.insert(key);
                        for (locale, _) in locales {
                            keys_by_locale.entry(locale).or_default().insert(key.clone());
                        }
                    }
                }
            }
            let mut locales: Vec<String> = keys_by_locale.keys().cloned().collect();
            locales.sort();
            let mut missing: Vec<Value> = Vec::new();
            for locale in &locales {
                let known = keys_by_locale.get(locale);
                let absent: Vec<String> = all_keys
                    .iter()
                    .filter(|key| !known.map(|set| set.contains(*key)).unwrap_or(false))
                    .cloned()
                    .collect();
                let mut absent = absent;
                absent.sort();
                if !absent.is_empty() {
                    missing.push(json!({"locale": locale, "missingKeys": absent}));
                }
            }
            let swift_files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 100)?;
            let total_keys = all_keys.len();
            let mut all_keys_sorted: Vec<String> = all_keys.into_iter().collect();
            all_keys_sorted.sort();
            let mut unreferenced: Vec<String> = Vec::new();
            for key in all_keys_sorted {
                let referenced = swift_files.iter().any(|(_, content)| {
                    content.contains(&format!("\"{key}\""))
                        || content.contains(&format!("NSLocalizedString(\"{key}\""))
                });
                if !referenced {
                    unreferenced.push(key);
                }
                if unreferenced.len() >= limit {
                    break;
                }
            }
            Ok(json!({
                "tool": name,
                "locales": locales,
                "totalKeys": total_keys,
                "missing": missing,
                "unreferencedKeys": unreferenced,
            }))
        }
        "localize_app" => {
            let action = req_str(args, "action", name)?;
            if !["localize", "status", "set_development_region"].contains(&action.as_str()) {
                return Err(failed(format!(
                    "{name} action must be localize, status, or set_development_region."
                )));
            }
            let catalog_path = "Localizable.xcstrings";
            if action == "status" {
                if let Ok(content) = read_text_file_at(&cwd, catalog_path) {
                    if let Ok(catalog) = serde_json::from_str::<Value>(&content) {
                        let keys = g6_xcstrings_keys(&catalog);
                        let mut locales: Vec<String> = keys
                            .iter()
                            .flat_map(|(_, locales)| locales.iter().map(|(locale, _)| locale.clone()))
                            .collect();
                        locales.sort();
                        locales.dedup();
                        return Ok(json!({
                            "tool": name,
                            "action": action,
                            "exists": true,
                            "sourceLanguage": catalog.get("sourceLanguage").cloned().unwrap_or(Value::Null),
                            "keyCount": keys.len(),
                            "locales": locales,
                        }));
                    }
                }
                return Ok(json!({
                    "tool": name,
                    "action": action,
                    "exists": false,
                    "keyCount": 0,
                    "locales": [],
                }));
            }
            if action == "set_development_region" {
                let region = req_str(args, "developmentRegion", name)?;
                let plist_path = g6_resolve_file(&cwd, None, "Info.plist", "Info.plist", name)?;
                g6_plist_set(&cwd, &plist_path, "CFBundleDevelopmentRegion", &json!(region), name)?;
                return Ok(json!({
                    "tool": name,
                    "action": action,
                    "path": plist_path,
                    "developmentRegion": region,
                    "updated": true,
                }));
            }
            let Some(languages) = args
                .get("languages")
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(|item| item.as_str().map(str::to_owned))
                        .collect::<Vec<String>>()
                })
            else {
                return Err(failed(format!(
                    "{name} localize requires languages with 1 to 3 language codes."
                )));
            };
            if languages.is_empty() || languages.len() > 3 {
                return Err(failed(format!(
                    "{name} localize requires languages with 1 to 3 language codes."
                )));
            }
            let mut translations: std::collections::HashMap<String, std::collections::HashMap<String, String>> =
                std::collections::HashMap::new();
            if let Some(raw_translations) = args.get("translations").and_then(Value::as_array) {
                for raw in raw_translations {
                    let Some(locale) = raw.get("locale").and_then(Value::as_str) else {
                        return Err(failed(format!("{name} is missing required argument \"translations\".")));
                    };
                    let Some(key) = raw.get("key").and_then(Value::as_str) else {
                        return Err(failed(format!("{name} is missing required argument \"translations\".")));
                    };
                    let Some(value) = raw.get("value").and_then(Value::as_str) else {
                        return Err(failed(format!("{name} is missing required argument \"translations\".")));
                    };
                    translations
                        .entry(locale.to_owned())
                        .or_default()
                        .insert(key.to_owned(), value.to_owned());
                }
            }
            let swift_files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 200)?;
            let mut keys: std::collections::HashSet<String> = std::collections::HashSet::new();
            for (_, content) in &swift_files {
                for caps in g5_regex_captures(
                    r#"NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)""#,
                    content,
                ) {
                    let key = caps.get(1).cloned().flatten().unwrap_or_default();
                    if !key.is_empty() {
                        keys.insert(g6_strings_unescape(&key));
                    }
                }
                for caps in g5_regex_captures(
                    r#"String\(localized:\s*"((?:[^"\\]|\\.)*)""#,
                    content,
                ) {
                    let key = caps.get(1).cloned().flatten().unwrap_or_default();
                    if !key.is_empty() {
                        keys.insert(g6_strings_unescape(&key));
                    }
                }
            }
            let mut catalog: Value = if let Ok(content) = read_text_file_at(&cwd, catalog_path) {
                serde_json::from_str(&content).unwrap_or_else(|_| {
                    json!({"sourceLanguage": "en", "strings": {}, "version": "1.0"})
                })
            } else {
                json!({"sourceLanguage": "en", "strings": {}, "version": "1.0"})
            };
            let source_language = catalog
                .get("sourceLanguage")
                .and_then(Value::as_str)
                .unwrap_or("en")
                .to_owned();
            let mut keys_sorted: Vec<String> = keys.into_iter().collect();
            keys_sorted.sort();
            let mut keys_added = 0usize;
            let layout_direction = if languages.iter().any(|language| {
                ["ar", "he", "fa", "ur"].contains(&language.to_lowercase().as_str())
            }) {
                "rtl"
            } else {
                "ltr"
            };
            for key in &keys_sorted {
                let existing = g6_xcstrings_keys(&catalog)
                    .into_iter()
                    .find(|(found_key, _)| found_key == key);
                if existing.is_none() {
                    keys_added += 1;
                }
                g6_xcstrings_set(&mut catalog, key, &source_language, key, "translated");
                for language in &languages {
                    if let Some(translated) = translations
                        .get(language)
                        .and_then(|map| map.get(key))
                    {
                        g6_xcstrings_set(&mut catalog, key, language, translated, "translated");
                    } else {
                        let has_language = g6_xcstrings_keys(&catalog)
                            .into_iter()
                            .find(|(found_key, _)| found_key == key)
                            .map(|(_, locales)| {
                                locales.iter().any(|(locale, _)| locale == language)
                            })
                            .unwrap_or(false);
                        if !has_language {
                            g6_xcstrings_set(&mut catalog, key, language, key, "new");
                        }
                    }
                }
            }
            let text = g6_xcstrings_encode(&catalog, name)?;
            write_text_file(&cwd, catalog_path, &text)?;
            if let Ok(plist_path) = g6_resolve_file(&cwd, None, "Info.plist", "Info.plist", name) {
                if let Ok(plist) = g6_plist_json(&cwd, &plist_path, name) {
                    let _ = g6_plist_set(
                        &cwd,
                        &plist_path,
                        "CFBundleLocalizations",
                        &json!(languages),
                        name,
                    );
                    if plist.get("CFBundleDevelopmentRegion").is_none() {
                        let _ = g6_plist_set(
                            &cwd,
                            &plist_path,
                            "CFBundleDevelopmentRegion",
                            &json!(source_language),
                            name,
                        );
                    }
                }
            }
            Ok(json!({
                "tool": name,
                "action": action,
                "languages": languages,
                "layoutDirection": layout_direction,
                "sourceLanguage": source_language,
                "keysAdded": keys_added,
                "catalog": catalog_path,
            }))
        }
        "asset_catalog_manager" => {
            let action = req_str(args, "action", name)?;
            match action.as_str() {
                "list" => {
                    let entries = g6_entries(&cwd, path.as_deref())?;
                    let catalogs: Vec<String> = entries
                        .iter()
                        .filter(|entry| g6_is_dir(entry) && g6_entry_path(entry).ends_with(".xcassets"))
                        .map(|entry| g6_entry_path(entry))
                        .collect();
                    Ok(json!({
                        "tool": name,
                        "action": action,
                        "catalogs": catalogs,
                        "catalogCount": catalogs.len(),
                    }))
                }
                "inspect" => {
                    let set_name = req_str(args, "name", name)?;
                    let entries = g6_entries(&cwd, path.as_deref())?;
                    let Some(set) = entries.iter().find(|entry| {
                        g6_is_dir(entry) && g6_basename(&g6_entry_path(entry)) == set_name
                    }) else {
                        return Err(failed(format!("No asset set named {set_name} found.")));
                    };
                    let set_path = g6_entry_path(set);
                    let contents = read_text_file_at(&cwd, &format!("{set_path}/Contents.json"))?;
                    Ok(json!({
                        "tool": name,
                        "action": action,
                        "set": set_path,
                        "contents": contents,
                    }))
                }
                "create_imageset" => {
                    let image_name = req_str(args, "name", name)?;
                    let source = req_str(args, "source", name)?;
                    g6_validate_relative(&source, name)?;
                    let catalog =
                        g6_resolve_catalog(&cwd, opt_str(args, "catalog").as_deref(), name)?;
                    let set_path = format!("{catalog}/{image_name}.imageset");
                    let file_name = g6_basename(&source);
                    let set_dir = Path::new(&cwd).join(&set_path);
                    std::fs::create_dir_all(&set_dir).map_err(|error| {
                        failed(format!("{name} could not create {set_path}: {error}"))
                    })?;
                    std::fs::copy(Path::new(&cwd).join(&source), set_dir.join(&file_name))
                        .map_err(|error| failed(format!("{name} could not copy {source}: {error}")))?;
                    let contents = json!({
                        "images": [{"filename": file_name, "idiom": "universal", "scale": "1x"}],
                        "info": {"author": "xcode", "version": 1},
                    });
                    let contents_text = serde_json::to_string_pretty(&contents).map_err(|error| {
                        failed(format!("{name} could not serialize Contents.json: {error}"))
                    })?;
                    write_text_file(&cwd, &format!("{set_path}/Contents.json"), &contents_text)?;
                    Ok(json!({
                        "tool": name,
                        "action": action,
                        "set": set_path,
                        "image": file_name,
                        "created": true,
                    }))
                }
                "create_colorset" => {
                    let color_name = req_str(args, "name", name)?;
                    let light_hex = req_str(args, "lightHex", name)?;
                    let dark_hex = opt_str(args, "darkHex").unwrap_or_else(|| light_hex.clone());
                    let catalog =
                        g6_resolve_catalog(&cwd, opt_str(args, "catalog").as_deref(), name)?;
                    let set_path = format!("{catalog}/{color_name}.colorset");
                    let set_dir = Path::new(&cwd).join(&set_path);
                    std::fs::create_dir_all(&set_dir).map_err(|error| {
                        failed(format!("{name} could not create {set_path}: {error}"))
                    })?;
                    let contents = g6_colorset_contents(&light_hex, &dark_hex);
                    let contents_text = serde_json::to_string_pretty(&contents).map_err(|error| {
                        failed(format!("{name} could not serialize Contents.json: {error}"))
                    })?;
                    write_text_file(&cwd, &format!("{set_path}/Contents.json"), &contents_text)?;
                    Ok(json!({
                        "tool": name,
                        "action": action,
                        "set": set_path,
                        "created": true,
                    }))
                }
                _ => Err(failed(format!(
                    "{name} action must be list, inspect, create_imageset, or create_colorset."
                ))),
            }
        }
        "localization_manager" => {
            let action = req_str(args, "action", name)?;
            match action.as_str() {
                "list" => {
                    let strings_files =
                        g5_read_text_files(&cwd, path.as_deref(), &[".strings"], 200)?;
                    let catalog_files =
                        g5_read_text_files(&cwd, path.as_deref(), &[".xcstrings"], 50)?;
                    Ok(json!({
                        "tool": name,
                        "action": action,
                        "stringsFiles": strings_files.iter().map(|(file_path, _)| file_path).collect::<Vec<_>>(),
                        "catalogs": catalog_files.iter().map(|(file_path, _)| file_path).collect::<Vec<_>>(),
                    }))
                }
                "extract" => {
                    let strings_files =
                        g5_read_text_files(&cwd, path.as_deref(), &[".strings"], 200)?;
                    let catalog_files =
                        g5_read_text_files(&cwd, path.as_deref(), &[".xcstrings"], 50)?;
                    let mut keys: std::collections::HashMap<
                        String,
                        std::collections::HashMap<String, String>,
                    > = std::collections::HashMap::new();
                    for (file_path, content) in &strings_files {
                        let locale = g6_locale_for_path(file_path);
                        for (key, value, _) in g6_strings_pairs(content) {
                            keys.entry(key).or_default().insert(locale.clone(), value);
                        }
                    }
                    for (_, content) in &catalog_files {
                        if let Ok(catalog) = serde_json::from_str::<Value>(content) {
                            for (key, locales) in g6_xcstrings_keys(&catalog) {
                                for (locale, value) in locales {
                                    keys.entry(key).or_default().insert(locale, value);
                                }
                            }
                        }
                    }
                    let key_count = keys.len();
                    let mut keys_json = serde_json::Map::new();
                    for (key, locales) in keys {
                        let mut locales_json = serde_json::Map::new();
                        for (locale, value) in locales {
                            locales_json.insert(locale, json!(value));
                        }
                        keys_json.insert(key, Value::Object(locales_json));
                    }
                    Ok(json!({
                        "tool": name,
                        "action": action,
                        "keys": keys_json,
                        "keyCount": key_count,
                    }))
                }
                "add" => {
                    let key = req_str(args, "key", name)?;
                    let value = req_str(args, "value", name)?;
                    let file_path = req_str(args, "path", name)?;
                    g6_validate_relative(&file_path, name)?;
                    if file_path.ends_with(".xcstrings") {
                        let content = read_text_file_at(&cwd, &file_path)?;
                        let mut catalog: Value = serde_json::from_str(&content).map_err(|error| {
                            failed(format!("{name} catalog was not valid JSON: {error}"))
                        })?;
                        let locale = opt_str(args, "locale").unwrap_or_else(|| {
                            catalog
                                .get("sourceLanguage")
                                .and_then(Value::as_str)
                                .unwrap_or("en")
                                .to_owned()
                        });
                        g6_xcstrings_set(&mut catalog, &key, &locale, &value, "translated");
                        let text = g6_xcstrings_encode(&catalog, name)?;
                        write_text_file(&cwd, &file_path, &text)?;
                        return Ok(json!({
                            "tool": name,
                            "action": action,
                            "path": file_path,
                            "key": key,
                            "locale": locale,
                            "updated": true,
                        }));
                    }
                    if !file_path.ends_with(".strings") {
                        return Err(failed(format!(
                            "{name} add path must end in .strings or .xcstrings."
                        )));
                    }
                    let content = read_text_file_at(&cwd, &file_path)?;
                    let mut pairs = g6_strings_pairs(&content);
                    if let Some(existing) =
                        pairs.iter_mut().find(|(found_key, _, _)| found_key == &key)
                    {
                        existing.1 = value.clone();
                    } else {
                        pairs.push((key.clone(), value.clone(), pairs.len() + 1));
                    }
                    let serialized = g6_serialize_strings(
                        &pairs
                            .iter()
                            .map(|(pair_key, pair_value, _)| {
                                (pair_key.clone(), pair_value.clone())
                            })
                            .collect::<Vec<(String, String)>>(),
                    );
                    write_text_file(&cwd, &file_path, &serialized)?;
                    Ok(json!({
                        "tool": name,
                        "action": action,
                        "path": file_path,
                        "key": key,
                        "updated": true,
                    }))
                }
                "validate" => {
                    let files = g5_read_text_files(&cwd, path.as_deref(), &[".strings"], 100)?;
                    Ok(g5_strings_validate(name, &files, limit))
                }
                _ => Err(failed(format!(
                    "{name} action must be list, extract, add, or validate."
                ))),
            }
        }
        "entitlements_manager" => {
            let action = req_str(args, "action", name)?;
            let entitlements_path =
                g6_resolve_file(&cwd, path.as_deref(), ".entitlements", ".entitlements", name)?;
            g6_validate_relative(&entitlements_path, name)?;
            let plist = g6_plist_json(&cwd, &entitlements_path, name)?;
            match action.as_str() {
                "list" => Ok(json!({
                    "tool": name,
                    "action": action,
                    "path": entitlements_path,
                    "entitlements": plist,
                })),
                "add" => {
                    let key = req_str(args, "key", name)?;
                    let value = req_str(args, "value", name)?;
                    let scalar = g6_plist_scalar(&value);
                    g6_plist_set(&cwd, &entitlements_path, &key, &scalar, name)?;
                    Ok(json!({
                        "tool": name,
                        "action": action,
                        "path": entitlements_path,
                        "key": key,
                        "updated": true,
                    }))
                }
                "remove" => {
                    let key = req_str(args, "key", name)?;
                    if plist.get(&key).is_none() {
                        return Err(failed(format!(
                            "Entitlement {key} not present in {entitlements_path}."
                        )));
                    }
                    g6_plist_remove(&cwd, &entitlements_path, &key, name)?;
                    Ok(json!({
                        "tool": name,
                        "action": action,
                        "path": entitlements_path,
                        "key": key,
                        "removed": true,
                    }))
                }
                _ => Err(failed(format!(
                    "{name} action must be list, add, or remove."
                ))),
            }
        }
        "colorset_builder" => {
            let color_name = req_str(args, "name", name)?;
            let light_hex = req_str(args, "lightHex", name)?;
            let dark_hex = opt_str(args, "darkHex").unwrap_or_else(|| light_hex.clone());
            if color_name.is_empty() || color_name.contains('/') {
                return Err(failed(format!(
                    "{name} name must be a single name without a path separator."
                )));
            }
            for hex in [&light_hex, &dark_hex] {
                let valid = hex.len() == 7
                    && hex.starts_with('#')
                    && hex[1..].chars().all(|ch| ch.is_ascii_hexdigit());
                if !valid {
                    return Err(failed(format!(
                        "{name} color hex must be #RRGGBB, for example #FF8800."
                    )));
                }
            }
            let catalog = g6_resolve_catalog(&cwd, opt_str(args, "catalog").as_deref(), name)?;
            let set_path = format!("{catalog}/{color_name}.colorset");
            let set_dir = Path::new(&cwd).join(&set_path);
            std::fs::create_dir_all(&set_dir)
                .map_err(|error| failed(format!("{name} could not create {set_path}: {error}")))?;
            let contents = g6_colorset_contents(&light_hex, &dark_hex);
            let contents_text = serde_json::to_string_pretty(&contents)
                .map_err(|error| failed(format!("{name} could not serialize Contents.json: {error}")))?;
            write_text_file(&cwd, &format!("{set_path}/Contents.json"), &contents_text)?;
            let verify = read_text_file_at(&cwd, &format!("{set_path}/Contents.json"))?;
            let light_red = u32::from_str_radix(light_hex.get(1..3).unwrap_or("00"), 16).unwrap_or(0);
            let expected_red = format!("{:.3}", light_red as f64 / 255.0);
            Ok(json!({
                "tool": name,
                "set": set_path,
                "lightHex": light_hex,
                "darkHex": dark_hex,
                "verified": verify.contains(&expected_red),
            }))
        }
        "project_entitlements" => {
            let entitlements_path =
                g6_resolve_file(&cwd, path.as_deref(), ".entitlements", ".entitlements", name)?;
            g6_validate_relative(&entitlements_path, name)?;
            let plist = g6_plist_json(&cwd, &entitlements_path, name)?;
            Ok(json!({
                "tool": name,
                "path": entitlements_path,
                "entitlements": plist,
            }))
        }
        "project_info_plist" => {
            let action = req_str(args, "action", name)?;
            let plist_path = g6_resolve_file(&cwd, path.as_deref(), "Info.plist", "Info.plist", name)?;
            g6_validate_relative(&plist_path, name)?;
            let plist = g6_plist_json(&cwd, &plist_path, name)?;
            match action.as_str() {
                "get" => {
                    let key = req_str(args, "key", name)?;
                    let found = plist.get(&key);
                    Ok(json!({
                        "tool": name,
                        "path": plist_path,
                        "key": key,
                        "found": found.is_some(),
                        "value": found.cloned().unwrap_or(Value::Null),
                    }))
                }
                "set" => {
                    let key = req_str(args, "key", name)?;
                    let value = req_str(args, "value", name)?;
                    let scalar = g6_plist_scalar(&value);
                    g6_plist_set(&cwd, &plist_path, &key, &scalar, name)?;
                    Ok(json!({
                        "tool": name,
                        "path": plist_path,
                        "key": key,
                        "value": value,
                        "updated": true,
                    }))
                }
                "delete" => {
                    let key = req_str(args, "key", name)?;
                    if plist.get(&key).is_none() {
                        return Err(failed(format!("Key {key} not present in {plist_path}.")));
                    }
                    g6_plist_remove(&cwd, &plist_path, &key, name)?;
                    Ok(json!({
                        "tool": name,
                        "path": plist_path,
                        "key": key,
                        "deleted": true,
                    }))
                }
                _ => Err(failed(format!(
                    "{name} action must be get, set, or delete."
                ))),
            }
        }
        "project_capabilities" => {
            let action = req_str(args, "action", name)?;
            let entitlements_path =
                g6_resolve_file(&cwd, path.as_deref(), ".entitlements", ".entitlements", name)?;
            g6_validate_relative(&entitlements_path, name)?;
            let plist = g6_plist_json(&cwd, &entitlements_path, name)?;
            let supported: Vec<(&str, &str)> = vec![
                ("app-sandbox", "com.apple.security.app-sandbox"),
                ("network-client", "com.apple.security.network.client"),
                ("network-server", "com.apple.security.network.server"),
                (
                    "files-user-selected-read-only",
                    "com.apple.security.files.user-selected.read-only",
                ),
                (
                    "files-user-selected-read-write",
                    "com.apple.security.files.user-selected.read-write",
                ),
                (
                    "files-downloads-read-only",
                    "com.apple.security.files.downloads.read-only",
                ),
                (
                    "files-downloads-read-write",
                    "com.apple.security.files.downloads.read-write",
                ),
                ("audio-input", "com.apple.security.device.audio-input"),
                ("camera", "com.apple.security.device.camera"),
                ("usb", "com.apple.security.device.usb"),
                ("bluetooth", "com.apple.security.device.bluetooth"),
                ("printing", "com.apple.security.print"),
            ];
            if action == "list" {
                let mut enabled: Vec<String> = Vec::new();
                let mut disabled: Vec<String> = Vec::new();
                let mut sorted = supported.clone();
                sorted.sort_by(|a, b| a.0.cmp(b.0));
                for (capability, key) in &sorted {
                    if plist.get(*key).and_then(Value::as_bool) == Some(true) {
                        enabled.push((*capability).to_owned());
                    } else {
                        disabled.push((*capability).to_owned());
                    }
                }
                let mut present: Vec<Value> = Vec::new();
                if let Some(object) = plist.as_object() {
                    let mut keys: Vec<&String> = object.keys().collect();
                    keys.sort();
                    for key in keys {
                        if !supported.iter().any(|(_, known)| known == key) {
                            present.push(json!({
                                "key": key,
                                "value": object.get(key).cloned().unwrap_or(Value::Null),
                            }));
                        }
                    }
                }
                return Ok(json!({
                    "tool": name,
                    "action": action,
                    "path": entitlements_path,
                    "enabled": enabled,
                    "disabled": disabled,
                    "otherEntitlements": present,
                }));
            }
            if !["enable", "disable"].contains(&action.as_str()) {
                return Err(failed(format!(
                    "{name} action must be list, enable, or disable."
                )));
            }
            let capability = req_str(args, "capability", name)?;
            let Some((_, key)) = supported.iter().find(|(known, _)| *known == capability.as_str()) else {
                let names: Vec<&str> = supported.iter().map(|(known, _)| *known).collect();
                return Err(failed(format!(
                    "Capability {capability} is not a boolean entitlement capability. Supported: {}.",
                    names.join(", ")
                )));
            };
            let key = *key;
            let enabled = action == "enable";
            g6_plist_set(&cwd, &entitlements_path, key, &json!(enabled), name)?;
            Ok(json!({
                "tool": name,
                "action": action,
                "path": entitlements_path,
                "capability": capability,
                "key": key,
                "enabled": enabled,
            }))
        }
        "entry_points_discover" => {
            let main_hits = g5_search_regex_hits(&cwd, "@main", limit as u64)?;
            let delegate_hits = g5_search_regex_hits(
                &cwd,
                r"(class|struct)\s+([A-Za-z0-9_]*(AppDelegate|SceneDelegate)[A-Za-z0-9_]*)",
                limit as u64,
            )?;
            let scoped_main = g6_scope_hits(main_hits, path.as_deref());
            let scoped_delegates = g6_scope_hits(delegate_hits, path.as_deref());
            let mut entries: Vec<Value> = Vec::new();
            for (hit_path, line, text) in &scoped_main {
                entries.push(json!({"kind": "main", "path": hit_path, "lineNumber": line, "lineText": text}));
            }
            for (hit_path, line, text) in &scoped_delegates {
                entries.push(json!({"kind": "delegate", "path": hit_path, "lineNumber": line, "lineText": text}));
            }
            let main_files = g6_entries(&cwd, path.as_deref())?;
            for entry in &main_files {
                if !g6_is_dir(entry) && g6_entry_name(entry) == "main.swift" {
                    entries.push(json!({
                        "kind": "mainSwift",
                        "path": g6_entry_path(entry),
                        "lineNumber": 1,
                        "lineText": "main.swift",
                    }));
                }
            }
            Ok(json!({
                "tool": name,
                "entryPoints": entries,
                "count": entries.len(),
            }))
        }
        "repo_overview" => {
            let entries = g6_entries(&cwd, path.as_deref())?;
            let files: Vec<&Value> = entries.iter().filter(|entry| !g6_is_dir(entry)).collect();
            let mut by_language: std::collections::HashMap<String, (usize, i64)> =
                std::collections::HashMap::new();
            for file in &files {
                let ext = g6_ext(&g6_entry_path(file));
                let language = g6_language_for_extension(&ext).to_owned();
                let slot = by_language.entry(language).or_insert((0, 0));
                slot.0 += 1;
                slot.1 += g6_size(file);
            }
            let mut largest: Vec<&Value> = files.clone();
            largest.sort_by(|a, b| g6_size(b).cmp(&g6_size(a)));
            let largest: Vec<Value> = largest
                .into_iter()
                .take(10)
                .map(|file| json!({"path": g6_entry_path(file), "bytes": g6_size(file)}))
                .collect();
            let names: std::collections::HashSet<String> = files
                .iter()
                .map(|file| g6_entry_name(file).to_lowercase())
                .collect();
            let mut languages: Vec<String> = by_language.keys().cloned().collect();
            languages.sort();
            let languages_json: Vec<Value> = languages
                .iter()
                .map(|language| {
                    let (count, bytes) = by_language.get(language).copied().unwrap_or((0, 0));
                    json!({"language": language, "files": count, "bytes": bytes})
                })
                .collect();
            Ok(json!({
                "tool": name,
                "fileCount": files.len(),
                "directoryCount": entries.len() - files.len(),
                "languages": languages_json,
                "hasReadme": names.iter().any(|file_name| file_name.starts_with("readme")),
                "hasLicense": names.iter().any(|file_name| file_name.starts_with("license")),
                "largestFiles": largest,
            }))
        }
        "project_structure_map" => {
            let entries = g6_entries(&cwd, path.as_deref())?;
            let mut directories: std::collections::HashMap<String, usize> =
                std::collections::HashMap::new();
            for entry in &entries {
                if g6_is_dir(entry) {
                    continue;
                }
                let dir = g6_dirname(&g6_entry_path(entry));
                *directories.entry(dir).or_insert(0) += 1;
            }
            let mut targets: Vec<String> = Vec::new();
            if let Ok(pbxproj) = g5_resolve_pbxproj(&cwd, None, name) {
                if let Ok(content) = read_text_file_at(&cwd, &pbxproj) {
                    targets = g6_pbxproj_targets(&content);
                }
            }
            let mut dirs: Vec<String> = directories.keys().cloned().collect();
            dirs.sort();
            let directories_json: Vec<Value> = dirs
                .iter()
                .map(|dir| {
                    json!({"path": dir, "files": directories.get(dir).copied().unwrap_or(0)})
                })
                .collect();
            Ok(json!({
                "tool": name,
                "directories": directories_json,
                "targets": targets,
            }))
        }
        "recent_changes" => {
            let hours = opt_u64(args, "hours").unwrap_or(24).clamp(1, 24 * 365);
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|duration| duration.as_secs_f64())
                .unwrap_or(0.0);
            let cutoff = now - hours as f64 * 3600.0;
            let entries = g6_entries(&cwd, path.as_deref())?;
            let mut changed: Vec<&Value> = entries
                .iter()
                .filter(|entry| !g6_is_dir(entry) && g6_mtime(entry) >= cutoff)
                .collect();
            changed.sort_by(|a, b| {
                g6_mtime(b)
                    .partial_cmp(&g6_mtime(a))
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            let changed: Vec<Value> = changed
                .into_iter()
                .take(limit)
                .map(|entry| {
                    json!({
                        "path": g6_entry_path(entry),
                        "modifiedAt": g6_mtime(entry),
                        "sizeBytes": g6_size(entry),
                    })
                })
                .collect();
            Ok(json!({
                "tool": name,
                "hours": hours,
                "files": changed,
                "count": changed.len(),
            }))
        }
        "readme_locate" => {
            let entries = g6_entries(&cwd, path.as_deref())?;
            let mut readmes: Vec<Value> = Vec::new();
            for entry in &entries {
                if g6_is_dir(entry) || !g6_entry_name(entry).to_lowercase().starts_with("readme") {
                    continue;
                }
                let entry_path = g6_entry_path(entry);
                let mut title = String::new();
                if let Ok(content) = read_text_file_at(&cwd, &entry_path) {
                    for line in content.lines() {
                        let trimmed = line.trim();
                        if let Some(rest) = trimmed.strip_prefix("# ") {
                            title = rest.trim().to_owned();
                            break;
                        }
                    }
                }
                readmes.push(json!({"path": entry_path, "title": title}));
            }
            Ok(json!({
                "tool": name,
                "readmes": readmes,
                "count": readmes.len(),
            }))
        }
        "dependency_licenses" => {
            let mut dependencies: Vec<Value> = Vec::new();
            let entries = g6_entries(&cwd, path.as_deref())?;
            if let Some(resolved_entry) = entries
                .iter()
                .find(|entry| !g6_is_dir(entry) && g6_entry_name(entry) == "Package.resolved")
            {
                let entry_path = g6_entry_path(resolved_entry);
                if let Ok(content) = read_text_file_at(&cwd, &entry_path) {
                    for (identity, location, version) in g6_parse_resolved(&content) {
                        dependencies.push(json!({
                            "name": identity,
                            "version": version,
                            "source": "Package.resolved",
                            "location": location,
                        }));
                    }
                }
            }
            if let Some(lock_entry) = entries
                .iter()
                .find(|entry| !g6_is_dir(entry) && g6_entry_name(entry) == "Podfile.lock")
            {
                let entry_path = g6_entry_path(lock_entry);
                if let Ok(content) = read_text_file_at(&cwd, &entry_path) {
                    let mut in_pods = false;
                    for line in content.lines() {
                        if line.starts_with("PODS:") {
                            in_pods = true;
                            continue;
                        }
                        if in_pods {
                            if line.is_empty()
                                || (!line.starts_with(' ') && !line.starts_with('\t'))
                            {
                                break;
                            }
                            if let Some(first) = g5_regex_captures(
                                r"^\s*-\s*([A-Za-z0-9_./-]+) \(([^)]+)\)",
                                line,
                            )
                            .into_iter()
                            .next()
                            {
                                let pod_name =
                                    first.get(1).cloned().flatten().unwrap_or_default();
                                let version =
                                    first.get(2).cloned().flatten().unwrap_or_default();
                                if !pod_name.is_empty() {
                                    dependencies.push(json!({
                                        "name": pod_name,
                                        "version": version,
                                        "source": "Podfile.lock",
                                        "location": "",
                                    }));
                                }
                            }
                        }
                    }
                }
            }
            let has_license = entries.iter().any(|entry| {
                !g6_is_dir(entry) && g6_entry_name(entry).to_lowercase().starts_with("license")
            });
            Ok(json!({
                "tool": name,
                "dependencies": dependencies,
                "count": dependencies.len(),
                "hasLicenseFile": has_license,
                "note": "License text is not stored in Package.resolved or Podfile.lock; check each package LICENSE file for the license terms.",
            }))
        }
        "stale_files_report" => {
            let days = opt_u64(args, "days").unwrap_or(180).clamp(1, 3650);
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|duration| duration.as_secs_f64())
                .unwrap_or(0.0);
            let cutoff = now - days as f64 * 86400.0;
            let entries = g6_entries(&cwd, path.as_deref())?;
            let source_exts = [
                "swift", "m", "mm", "h", "c", "cpp", "ts", "tsx", "js", "jsx", "py", "rs", "kt",
                "java",
            ];
            let mut stale: Vec<&Value> = entries
                .iter()
                .filter(|entry| {
                    if g6_is_dir(entry) {
                        return false;
                    }
                    let modified = g6_mtime(entry);
                    modified > 0.0
                        && modified < cutoff
                        && source_exts.contains(&g6_ext(&g6_entry_path(entry)).as_str())
                })
                .collect();
            stale.sort_by(|a, b| {
                g6_mtime(a)
                    .partial_cmp(&g6_mtime(b))
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            let stale: Vec<Value> = stale
                .into_iter()
                .take(limit)
                .map(|entry| {
                    json!({
                        "path": g6_entry_path(entry),
                        "modifiedAt": g6_mtime(entry),
                        "sizeBytes": g6_size(entry),
                    })
                })
                .collect();
            Ok(json!({
                "tool": name,
                "days": days,
                "files": stale,
                "count": stale.len(),
            }))
        }
        "file_type_breakdown" => {
            let entries = g6_entries(&cwd, path.as_deref())?;
            let mut by_extension: std::collections::HashMap<String, (usize, i64)> =
                std::collections::HashMap::new();
            for entry in &entries {
                if g6_is_dir(entry) {
                    continue;
                }
                let ext = g6_ext(&g6_entry_path(entry));
                let key = if ext.is_empty() {
                    "(none)".to_owned()
                } else {
                    format!(".{ext}")
                };
                let slot = by_extension.entry(key).or_insert((0, 0));
                slot.0 += 1;
                slot.1 += g6_size(entry);
            }
            let mut exts: Vec<String> = by_extension.keys().cloned().collect();
            exts.sort();
            let types: Vec<Value> = exts
                .iter()
                .map(|ext| {
                    let (count, bytes) = by_extension.get(ext).copied().unwrap_or((0, 0));
                    json!({"extension": ext, "files": count, "bytes": bytes})
                })
                .collect();
            Ok(json!({
                "tool": name,
                "types": types,
            }))
        }
        "empty_dirs_find" => {
            let entries = g6_entries(&cwd, path.as_deref())?;
            let mut children: std::collections::HashMap<String, usize> =
                std::collections::HashMap::new();
            for entry in &entries {
                let dir = g6_dirname(&g6_entry_path(entry));
                if !dir.is_empty() {
                    *children.entry(dir).or_insert(0) += 1;
                }
            }
            let empty: Vec<String> = entries
                .iter()
                .filter(|entry| {
                    g6_is_dir(entry) && children.get(&g6_entry_path(entry)).copied().unwrap_or(0) == 0
                })
                .map(|entry| g6_entry_path(entry))
                .collect();
            Ok(json!({
                "tool": name,
                "emptyDirectories": empty,
                "count": empty.len(),
            }))
        }
        "symlink_audit" => {
            let entries = g6_entries(&cwd, path.as_deref())?;
            let mut links: Vec<Value> = Vec::new();
            for entry in &entries {
                if entry["isSymlink"].as_bool() != Some(true) {
                    continue;
                }
                let entry_path = g6_entry_path(entry);
                let target = entry["symlinkTarget"]
                    .as_str()
                    .unwrap_or("")
                    .to_owned();
                let mut broken = false;
                if !target.is_empty() {
                    let resolved = if target.starts_with('/') {
                        Path::new(&target).to_path_buf()
                    } else {
                        Path::new(&cwd)
                            .join(g6_dirname(&entry_path))
                            .join(&target)
                    };
                    broken = !resolved.exists();
                }
                links.push(json!({
                    "path": entry_path,
                    "target": target,
                    "broken": broken,
                }));
            }
            let broken_count = links
                .iter()
                .filter(|link| link["broken"].as_bool() == Some(true))
                .count();
            Ok(json!({
                "tool": name,
                "links": links,
                "count": links.len(),
                "brokenCount": broken_count,
            }))
        }
        "executable_files_scan" => {
            let entries = g6_entries(&cwd, path.as_deref())?;
            let executables: Vec<Value> = entries
                .iter()
                .filter(|entry| {
                    !g6_is_dir(entry) && entry["isExecutable"].as_bool() == Some(true)
                })
                .map(|entry| {
                    json!({"path": g6_entry_path(entry), "sizeBytes": g6_size(entry)})
                })
                .collect();
            Ok(json!({
                "tool": name,
                "executables": executables,
                "count": executables.len(),
            }))
        }
        "dir_size_report" => {
            let entries = g6_entries(&cwd, path.as_deref())?;
            let root = path.clone().unwrap_or_default();
            let mut totals: std::collections::HashMap<String, i64> = std::collections::HashMap::new();
            let mut file_counts: std::collections::HashMap<String, usize> =
                std::collections::HashMap::new();
            for entry in &entries {
                if g6_is_dir(entry) {
                    continue;
                }
                let entry_path = g6_entry_path(entry);
                let relative = if root.is_empty() {
                    entry_path.clone()
                } else if let Some(rest) = entry_path.strip_prefix(&format!("{root}/")) {
                    rest.to_owned()
                } else {
                    entry_path.clone()
                };
                let top = relative
                    .split('/')
                    .next()
                    .map(str::to_owned)
                    .unwrap_or_else(|| "(root)".to_owned());
                *totals.entry(top.clone()).or_insert(0) += g6_size(entry);
                *file_counts.entry(top).or_insert(0) += 1;
            }
            let mut dirs: Vec<String> = totals.keys().cloned().collect();
            dirs.sort_by(|a, b| {
                totals
                    .get(b)
                    .copied()
                    .unwrap_or(0)
                    .cmp(&totals.get(a).copied().unwrap_or(0))
            });
            let directories: Vec<Value> = dirs
                .into_iter()
                .take(limit)
                .map(|dir| {
                    json!({
                        "directory": dir,
                        "bytes": totals.get(&dir).copied().unwrap_or(0),
                        "files": file_counts.get(&dir).copied().unwrap_or(0),
                    })
                })
                .collect();
            let total_bytes: i64 = entries
                .iter()
                .filter(|entry| !g6_is_dir(entry))
                .map(|entry| g6_size(entry))
                .sum();
            Ok(json!({
                "tool": name,
                "directories": directories,
                "totalBytes": total_bytes,
            }))
        }
        "image_asset_size_report" => {
            let max_bytes = opt_u64(args, "maxKilobytes")
                .unwrap_or(500)
                .clamp(1, 100000)
                * 1024;
            let entries = g6_entries(&cwd, path.as_deref())?;
            let image_exts = ["png", "jpg", "jpeg", "heic", "webp", "gif", "pdf"];
            let mut oversized: Vec<&Value> = entries
                .iter()
                .filter(|entry| {
                    if g6_is_dir(entry) || !g6_entry_path(entry).contains(".xcassets/") {
                        return false;
                    }
                    let ext = g6_ext(&g6_entry_path(entry));
                    image_exts.contains(&ext.as_str()) && g6_size(entry) > max_bytes as i64
                })
                .collect();
            oversized.sort_by(|a, b| g6_size(b).cmp(&g6_size(a)));
            let images: Vec<Value> = oversized
                .into_iter()
                .map(|entry| {
                    json!({"path": g6_entry_path(entry), "sizeBytes": g6_size(entry)})
                })
                .collect();
            Ok(json!({
                "tool": name,
                "maxKilobytes": max_bytes / 1024,
                "images": images,
                "count": images.len(),
            }))
        }
        "bundle_resource_auditor" => {
            let pbxproj = g5_resolve_pbxproj(&cwd, path.as_deref(), name)?;
            let content = read_text_file_at(&cwd, &pbxproj)?;
            let entries = g6_entries(&cwd, None)?;
            Ok(g6_bundle_resources(name, &pbxproj, &content, &entries))
        }
        "core_data_model_inspector" => {
            let mut model_paths: Vec<String> = Vec::new();
            if let Some(path) = path.as_deref().filter(|p| !p.is_empty()) {
                model_paths.push(path.to_owned());
            } else {
                let entries = g6_entries(&cwd, None)?;
                model_paths = entries
                    .iter()
                    .filter(|entry| g6_entry_path(entry).ends_with(".xcdatamodeld"))
                    .map(|entry| g6_entry_path(entry))
                    .collect();
            }
            let mut models: Vec<Value> = Vec::new();
            for model_path in &model_paths {
                let entries = g6_entries(&cwd, Some(model_path))?;
                for entry in &entries {
                    let entry_path = g6_entry_path(entry);
                    if entry_path.ends_with(".xcdatamodel/contents")
                        || entry_path.ends_with("contents")
                    {
                        if let Ok(content) = read_text_file_at(&cwd, &entry_path) {
                            models.push(g6_core_data_model(name, &entry_path, &content));
                        }
                    }
                }
            }
            Ok(json!({
                "tool": name,
                "models": models,
                "modelCount": models.len(),
            }))
        }
        "swift_data_schema_auditor" => {
            let files = g5_read_text_files(&cwd, path.as_deref(), &[".swift"], 100)?;
            let mut models: Vec<Value> = Vec::new();
            let mut issues: Vec<String> = Vec::new();
            for (file_path, content) in &files {
                let mut current_model: Option<String> = None;
                let mut expecting_model = false;
                let mut relationships: Vec<Value> = Vec::new();
                let mut uniques: Vec<String> = Vec::new();
                for line in content.lines() {
                    let trimmed = line.trim();
                    if trimmed.starts_with("@Model") {
                        expecting_model = true;
                        if let Some(first) = g5_regex_captures(
                            r"class\s+([A-Za-z0-9_]+)",
                            trimmed,
                        )
                        .into_iter()
                        .next()
                        {
                            if let Some(found) = first.get(1).cloned().flatten() {
                                current_model = Some(found);
                                expecting_model = false;
                            }
                        }
                        continue;
                    }
                    if expecting_model {
                        if let Some(first) = g5_regex_captures(
                            r"^(final\s+)?class\s+([A-Za-z0-9_]+)",
                            trimmed,
                        )
                        .into_iter()
                        .next()
                        {
                            if let Some(found) = first.get(2).cloned().flatten() {
                                current_model = Some(found);
                                expecting_model = false;
                                continue;
                            }
                        }
                    }
                    if current_model.is_none() {
                        continue;
                    }
                    if let Some(first) = g5_regex_captures(
                        r"@Relationship\(deleteRule:\s*\.([A-Za-z]+)[^)]*\)\s*var\s+([A-Za-z0-9_]+)",
                        trimmed,
                    )
                    .into_iter()
                    .next()
                    {
                        relationships.push(json!({
                            "name": first.get(2).cloned().flatten().unwrap_or_default(),
                            "deleteRule": first.get(1).cloned().flatten().unwrap_or_default(),
                        }));
                    } else if let Some(first) = g5_regex_captures(
                        r"@Relationship[^\n]*?var\s+([A-Za-z0-9_]+)",
                        trimmed,
                    )
                    .into_iter()
                    .next()
                    {
                        relationships.push(json!({
                            "name": first.get(1).cloned().flatten().unwrap_or_default(),
                            "deleteRule": "nullify",
                        }));
                    }
                    if trimmed.contains("@Attribute(.unique)") {
                        if let Some(first) = g5_regex_captures(
                            r"var\s+([A-Za-z0-9_]+)",
                            trimmed,
                        )
                        .into_iter()
                        .next()
                        {
                            if let Some(found) = first.get(1).cloned().flatten() {
                                uniques.push(found);
                            }
                        }
                    }
                }
                if let Some(model) = current_model {
                    if relationships.is_empty() && uniques.is_empty() {
                        issues.push(format!(
                            "{model} in {file_path} declares no relationships or unique constraints."
                        ));
                    }
                    models.push(json!({
                        "model": model,
                        "path": file_path,
                        "relationships": relationships,
                        "uniqueAttributes": uniques,
                    }));
                }
            }
            Ok(json!({
                "tool": name,
                "models": models,
                "modelCount": models.len(),
                "issues": issues,
            }))
        }
        "privacy_manifest_auditor" => {
            let manifest_path =
                g6_resolve_file(&cwd, path.as_deref(), "PrivacyInfo.xcprivacy", "PrivacyInfo.xcprivacy", name)?;
            g6_validate_relative(&manifest_path, name)?;
            let plist = g6_plist_json(&cwd, &manifest_path, name)?;
            Ok(g6_privacy_audit(name, &manifest_path, &plist))
        }
        "build_system_detect" => {
            let entries = g6_entries(&cwd, path.as_deref())?;
            let mut detected: Vec<Value> = Vec::new();
            let has_name = |wanted: &str| {
                entries.iter().any(|entry| {
                    !g6_is_dir(entry) && g6_entry_name(entry) == wanted
                })
            };
            let has_suffix = |suffix: &str| {
                entries
                    .iter()
                    .any(|entry| !g6_is_dir(entry) && g6_entry_path(entry).ends_with(suffix))
            };
            if entries
                .iter()
                .any(|entry| g6_is_dir(entry) && g6_entry_path(entry).ends_with(".xcworkspace"))
            {
                detected.push(json!({"system": "xcworkspace", "evidence": ".xcworkspace"}));
            }
            if entries
                .iter()
                .any(|entry| g6_is_dir(entry) && g6_entry_path(entry).ends_with(".xcodeproj"))
            {
                detected.push(json!({"system": "xcodeproj", "evidence": ".xcodeproj"}));
            }
            if has_name("Package.swift") {
                detected.push(json!({"system": "SwiftPM", "evidence": "Package.swift"}));
            }
            if has_name("Podfile") {
                detected.push(json!({"system": "CocoaPods", "evidence": "Podfile"}));
            }
            if has_name("Cartfile") {
                detected.push(json!({"system": "Carthage", "evidence": "Cartfile"}));
            }
            if has_name("Project.swift") {
                detected.push(json!({"system": "Tuist", "evidence": "Project.swift"}));
            }
            if has_name("project.yml") {
                detected.push(json!({"system": "xcodegen", "evidence": "project.yml"}));
            }
            if has_name("WORKSPACE")
                || has_name("WORKSPACE.bazel")
                || has_suffix("BUILD")
                || has_suffix("BUILD.bazel")
            {
                detected.push(json!({"system": "Bazel", "evidence": "WORKSPACE or BUILD file"}));
            }
            if has_name("CMakeLists.txt") {
                detected.push(json!({"system": "CMake", "evidence": "CMakeLists.txt"}));
            }
            Ok(json!({
                "tool": name,
                "systems": detected,
                "count": detected.len(),
            }))
        }
        _ => Err(failed(format!("Unknown G6 file tool {name}."))),
    }
}

fn g6_curl_fetch(url: &str, timeout_seconds: u64, tool: &str) -> Result<(i64, String, String), CallError> {
    let output = std::process::Command::new("curl")
        .args([
            "-sS",
            "-L",
            "--max-time",
            &timeout_seconds.to_string(),
            "-w",
            "\n__AGENTS_CURL_STATUS__:%{http_code}\n__AGENTS_CURL_TYPE__:%{content_type}",
            url,
        ])
        .output()
        .map_err(|error| failed(format!("{tool} could not run curl: {error}")))?;
    if !output.status.success() {
        return Err(failed(format!(
            "{tool} fetch failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        )));
    }
    let text = String::from_utf8_lossy(&output.stdout).into_owned();
    let mut status = -1i64;
    let mut content_type = String::new();
    let mut body = text.as_str();
    if let Some(marker) = text.rfind("\n__AGENTS_CURL_STATUS__:") {
        body = &text[..marker];
        let tail = &text[marker + 1..];
        for line in tail.lines() {
            if let Some(value) = line.strip_prefix("__AGENTS_CURL_STATUS__:") {
                status = value.trim().parse::<i64>().unwrap_or(-1);
            }
            if let Some(value) = line.strip_prefix("__AGENTS_CURL_TYPE__:") {
                content_type = value.trim().to_owned();
            }
        }
    }
    Ok((status, content_type, body.to_owned()))
}

fn g6_terminal_call(
    state: &crate::ServerState,
    name: &str,
    args: &Value,
) -> Result<Value, CallError> {
    let thread_id = req_str(args, "threadId", name)?;
    let cwd = opt_str(args, "cwd").unwrap_or_else(|| "/".to_owned());
    let timeout = opt_u64(args, "timeoutSeconds").unwrap_or(300);
    match name {
        "spm_dependency_tree" => {
            let package_dir = g6_join(&cwd, opt_str(args, "path").as_deref());
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                &package_dir,
                "swift package show-dependencies --format json",
                timeout,
            )?;
            if g6_missing_cli(&output, exit_code) {
                return Err(failed(format!(
                    "{name} requires the swift command line tools."
                )));
            }
            if exit_code != 0 {
                return Ok(json!({
                    "dependencies": Value::Null,
                    "exitCode": exit_code,
                    "output": output,
                }));
            }
            let dependencies: Value = serde_json::from_str(&output)
                .map_err(|error| failed(format!("{name} could not parse show-dependencies output: {error}")))?;
            Ok(json!({"dependencies": dependencies, "exitCode": exit_code}))
        }
        "package_manifest_validate" => {
            let package_dir = g6_join(&cwd, opt_str(args, "path").as_deref());
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                &package_dir,
                "swift package dump-package",
                timeout,
            )?;
            if g6_missing_cli(&output, exit_code) {
                return Err(failed(format!(
                    "{name} requires the swift command line tools."
                )));
            }
            if exit_code != 0 {
                return Ok(json!({
                    "valid": false,
                    "name": Value::Null,
                    "targetCount": 0,
                    "exitCode": exit_code,
                    "output": output,
                }));
            }
            let dumped: Value = serde_json::from_str(&output)
                .map_err(|error| failed(format!("{name} could not parse dump-package output: {error}")))?;
            let target_count = dumped
                .get("targets")
                .and_then(Value::as_array)
                .map(|targets| targets.len())
                .unwrap_or(0);
            Ok(json!({
                "valid": true,
                "name": dumped.get("name").cloned().unwrap_or(Value::Null),
                "targetCount": target_count,
                "exitCode": exit_code,
            }))
        }
        "package_dependency_audit" => {
            let package_dir = g6_join(&cwd, opt_str(args, "path").as_deref());
            let manifest_content = read_text_file_at(&package_dir, "Package.swift")?;
            let manifest = g6_parse_manifest(&manifest_content);
            let mut resolved_pins: Vec<(String, String, String)> = Vec::new();
            if let Ok(resolved_content) = read_text_file_at(&package_dir, "Package.resolved") {
                resolved_pins = g6_parse_resolved(&resolved_content);
            }
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                &package_dir,
                "swift package show-dependencies --format json",
                timeout,
            )?;
            if g6_missing_cli(&output, exit_code) {
                return Err(failed(format!(
                    "{name} requires the swift command line tools."
                )));
            }
            let mut shown: Vec<String> = Vec::new();
            if exit_code == 0 {
                if let Ok(shown_value) = serde_json::from_str::<Value>(&output) {
                    shown = g6_show_dependencies_names(&shown_value);
                }
            }
            Ok(g6_dependency_audit(
                name,
                &manifest,
                &resolved_pins,
                &shown,
                exit_code,
                &output,
            ))
        }
        "project_signing" => {
            let pbxproj = g5_resolve_pbxproj(&cwd, opt_str(args, "path").as_deref(), name)?;
            let content = read_text_file_at(&cwd, &pbxproj)?;
            let mut object = g6_signing_from_pbxproj(name, &pbxproj, &content);
            let entries = g5_list_workspace_files(&cwd, ".mobileprovision", 100)?;
            let profiles: Vec<String> = entries
                .iter()
                .filter(|entry| {
                    !g6_is_dir(entry)
                        && (g6_entry_path(entry).ends_with(".mobileprovision")
                            || g6_entry_path(entry).ends_with(".provisionprofile"))
                })
                .map(|entry| g6_entry_path(entry))
                .collect();
            if let Some(map) = object.as_object_mut() {
                map.insert("provisioningProfiles".to_owned(), json!(profiles));
            }
            if let Some(scheme) = opt_str(args, "scheme") {
                if scheme.is_empty()
                    || scheme.contains(' ')
                    || scheme.contains('/')
                    || scheme.starts_with('-')
                {
                    return Err(failed(format!("{name} scheme is not a valid identifier.")));
                }
                let (exit_code, output) = run_shell_status(
                    state,
                    &thread_id,
                    &cwd,
                    &format!(
                        "xcodebuild -showBuildSettings -scheme {}",
                        shell_quote(&scheme)
                    ),
                    opt_u64(args, "timeoutSeconds").unwrap_or(120),
                )?;
                if g6_missing_cli(&output, exit_code) {
                    return Err(failed(format!(
                        "{name} requires xcodebuild."
                    )));
                }
                if let Some(map) = object.as_object_mut() {
                    map.insert(
                        "showBuildSettings".to_owned(),
                        g6_build_settings_json(&output),
                    );
                    map.insert("showBuildSettingsExitCode".to_owned(), json!(exit_code));
                }
            }
            Ok(object)
        }
        "icon_generator_tool" => {
            let source = req_str(args, "source", name)?;
            let output = req_str(args, "output", name)?;
            let platform = opt_str(args, "platform").unwrap_or_else(|| "ios".to_owned());
            if !["ios", "macos", "watchos"].contains(&platform.as_str()) {
                return Err(failed(format!(
                    "{name} platform must be ios, macos, or watchos."
                )));
            }
            g6_validate_relative(&source, name)?;
            g6_validate_relative(&output, name)?;
            if !output.ends_with(".appiconset") {
                return Err(failed(format!(
                    "{name} output must end in .appiconset."
                )));
            }
            let set_dir = Path::new(&cwd).join(&output);
            std::fs::create_dir_all(&set_dir)
                .map_err(|error| failed(format!("{name} could not create {output}: {error}")))?;
            let sizes = g6_icon_sizes(&platform);
            let mut generated: Vec<Value> = Vec::new();
            for (pixels, size, idiom, scale) in &sizes {
                let file_name = format!("icon-{pixels}.png");
                let destination = format!("{output}/{file_name}");
                run_shell(
                    state,
                    &thread_id,
                    &cwd,
                    &format!(
                        "sips -Z {pixels} {} --out {}",
                        shell_quote(&source),
                        shell_quote(&destination)
                    ),
                    timeout,
                )?;
                generated.push(json!({
                    "size": size,
                    "idiom": idiom,
                    "scale": scale,
                    "filename": file_name,
                    "pixels": pixels,
                }));
            }
            let contents = g6_app_icon_contents(&generated);
            let contents_text = serde_json::to_string_pretty(&contents)
                .map_err(|error| failed(format!("{name} could not serialize Contents.json: {error}")))?;
            write_text_file(&cwd, &format!("{output}/Contents.json"), &contents_text)?;
            let listed = read_dir_entries(&cwd, &output, false)?;
            Ok(json!({
                "platform": platform,
                "output": output,
                "icons": generated,
                "iconCount": generated.len(),
                "filesPresent": listed.iter().filter(|entry| !g6_is_dir(entry)).count(),
            }))
        }
        "process_monitor_tool" => {
            let filter = opt_str(args, "filter");
            let limit = opt_u64(args, "limit").unwrap_or(50).clamp(1, 500) as usize;
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                &cwd,
                "/bin/ps -ax -o pid=,pcpu=,pmem=,comm=",
                opt_u64(args, "timeoutSeconds").unwrap_or(60),
            )?;
            if g6_missing_cli(&output, exit_code) {
                return Err(failed(format!("{name} requires ps.")));
            }
            let processes = g6_parse_ps(&output, filter.as_deref(), limit);
            Ok(json!({
                "processes": processes,
                "count": processes.len(),
                "exitCode": exit_code,
            }))
        }
        "disk_space_analyzer" => {
            let path = opt_str(args, "path").unwrap_or_else(|| ".".to_owned());
            g6_validate_relative(&path, name)?;
            let timeout = opt_u64(args, "timeoutSeconds").unwrap_or(60);
            let df_output = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!("df -k {}", shell_quote(&path)),
                timeout,
            )?;
            let du_output = run_shell(
                state,
                &thread_id,
                &cwd,
                &format!("du -sk {}", shell_quote(&path)),
                timeout,
            )?;
            Ok(g6_disk_space(name, &path, &df_output, &du_output))
        }
        "use_system" => g6_use_system(state, name, args),
        "preflight_checks" => {
            let probe = format!(
                ".preflight-check-{}",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|duration| duration.as_nanos())
                    .unwrap_or(0)
            );
            let probe_path = Path::new(&cwd).join(&probe);
            let mut writable = false;
            if std::fs::write(&probe_path, b"ok").is_ok() {
                writable = true;
                let _ = std::fs::remove_file(&probe_path);
            }
            let mut checks: Vec<Value> = Vec::new();
            checks.push(json!({"check": "workspaceWritable", "passed": writable}));
            let (xcode_exit, xcode_output) = run_shell_status(
                state,
                &thread_id,
                &cwd,
                "xcodebuild -version",
                60,
            )?;
            let first_line = xcode_output.lines().next().unwrap_or("").to_owned();
            checks.push(json!({
                "check": "xcodebuild",
                "passed": xcode_exit == 0,
                "detail": first_line,
            }));
            let df_output = run_shell(state, &thread_id, &cwd, "df -k .", 60)?;
            let mut free_bytes: i64 = 0;
            for line in df_output.lines() {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 4 {
                    if let Ok(available) = parts[3].parse::<i64>() {
                        free_bytes = available * 1024;
                    }
                }
            }
            checks.push(json!({
                "check": "diskSpace",
                "passed": free_bytes > 1024 * 1024 * 1024,
                "detail": format!("{free_bytes} bytes free"),
            }));
            let artifacts_dir = Path::new(&cwd).join(".assist_temp/artifacts");
            let mut artifacts_writable = false;
            if std::fs::create_dir_all(&artifacts_dir).is_ok() {
                let artifact_probe = artifacts_dir.join(".preflight-check");
                if std::fs::write(&artifact_probe, b"ok").is_ok() {
                    artifacts_writable = true;
                    let _ = std::fs::remove_file(&artifact_probe);
                }
            }
            checks.push(json!({
                "check": "artifactStorage",
                "passed": artifacts_writable,
            }));
            let all_passed = checks
                .iter()
                .all(|check| check["passed"].as_bool() == Some(true));
            Ok(json!({
                "tool": name,
                "checks": checks,
                "allPassed": all_passed,
            }))
        }
        "github_repo" => g6_github_repo(state, name, args),
        _ => Err(failed(format!("Unknown G6 terminal tool {name}."))),
    }
}

fn g6_use_system(
    state: &crate::ServerState,
    name: &str,
    args: &Value,
) -> Result<Value, CallError> {
    let thread_id = req_str(args, "threadId", name)?;
    let operation = req_str(args, "operation", name)?;
    let timeout = opt_u64(args, "timeoutSeconds").unwrap_or(60);
    match operation.as_str() {
        "system_info" => Ok(g6_env_info(name)),
        "dev_environment" => {
            let mut tools: Vec<Value> = Vec::new();
            for (tool_name, command) in [
                ("xcodebuild", "xcodebuild -version"),
                ("swift", "swift --version"),
            ] {
                let (exit_code, output) = run_shell_status(
                    state,
                    &thread_id,
                    "/",
                    command,
                    timeout,
                )?;
                tools.push(json!({
                    "tool": tool_name,
                    "available": exit_code == 0,
                    "output": output,
                }));
            }
            Ok(json!({"operation": operation, "tools": tools}))
        }
        "process_list" => {
            let filter = opt_str(args, "filter");
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                "/",
                "/bin/ps -ax -o pid=,pcpu=,pmem=,comm=",
                timeout,
            )?;
            let processes = g6_parse_ps(&output, filter.as_deref(), 200);
            Ok(json!({
                "operation": operation,
                "processes": processes,
                "count": processes.len(),
                "exitCode": exit_code,
            }))
        }
        "network_interfaces" => {
            let mut command = "/sbin/ifconfig".to_owned();
            if let Some(interface) = opt_str(args, "interface") {
                if interface.is_empty()
                    || interface.contains(' ')
                    || interface.contains('/')
                    || interface.starts_with('-')
                {
                    return Err(failed(format!(
                        "{name} interface is not a valid identifier."
                    )));
                }
                command = format!("/sbin/ifconfig {}", shell_quote(&interface));
            }
            let (exit_code, output) =
                run_shell_status(state, &thread_id, "/", &command, timeout)?;
            Ok(json!({
                "operation": operation,
                "output": output,
                "exitCode": exit_code,
            }))
        }
        "listening_sockets" => {
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                "/",
                "/usr/sbin/lsof -i -P -n -sTCP:LISTEN",
                timeout,
            )?;
            let mut listening: Vec<Value> = Vec::new();
            for line in output.lines() {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() < 9 || parts[0] == "COMMAND" {
                    continue;
                }
                listening.push(json!({
                    "command": parts[0],
                    "pid": parts[1].parse::<i64>().unwrap_or(0),
                    "user": parts[2],
                    "address": parts[8..].join(" "),
                }));
            }
            Ok(json!({
                "operation": operation,
                "listening": listening,
                "exitCode": exit_code,
                "output": output,
                "note": if exit_code == 0 { "" } else { "lsof exited non-zero; output may be incomplete where permission was denied." },
            }))
        }
        "connectivity" => {
            let host = req_str(args, "host", name)?;
            let Some(port) = args.get("port").and_then(Value::as_u64) else {
                return Err(failed(format!(
                    "{name} is missing required argument \"port\"."
                )));
            };
            if !(1..=65535).contains(&port) {
                return Err(failed(format!(
                    "{name} is missing required argument \"port\"."
                )));
            }
            if host.is_empty() || host.contains(' ') || host.starts_with('-') {
                return Err(failed(format!("{name} host is not a valid token.")));
            }
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!("nc -z -w 5 {} {port}", shell_quote(&host)),
                timeout,
            )?;
            if g6_missing_cli(&output, exit_code) {
                return Err(failed(format!("{name} requires nc.")));
            }
            Ok(json!({
                "operation": operation,
                "host": host,
                "port": port,
                "reachable": exit_code == 0,
                "exitCode": exit_code,
            }))
        }
        "disk_info" => {
            let root = opt_str(args, "cwd").unwrap_or_else(|| "/".to_owned());
            let output = run_shell(
                state,
                &thread_id,
                "/",
                &format!("df -k {}", shell_quote(&root)),
                timeout,
            )?;
            let mut total = 0i64;
            let mut available = 0i64;
            for line in output.lines() {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 4 {
                    if let (Ok(parsed_total), Ok(parsed_available)) =
                        (parts[1].parse::<i64>(), parts[3].parse::<i64>())
                    {
                        total = parsed_total * 1024;
                        available = parsed_available * 1024;
                    }
                }
            }
            let used = (total - available).max(0);
            Ok(json!({
                "operation": operation,
                "path": root,
                "totalBytes": total,
                "availableBytes": available,
                "usedBytes": used,
                "usedPercent": if total > 0 { used as f64 / total as f64 * 100.0 } else { 0.0 },
            }))
        }
        "system_log" => {
            let minutes = opt_u64(args, "minutes").unwrap_or(5).clamp(1, 60);
            let mut command = format!("/usr/bin/log show --last {minutes}m");
            if let Some(predicate) = opt_str(args, "predicate") {
                if predicate.is_empty() || predicate.contains('\n') || predicate.starts_with('-') {
                    return Err(failed(format!(
                        "{name} predicate is not a valid token."
                    )));
                }
                command = format!("{command} --predicate {}", shell_quote(&predicate));
            }
            let (exit_code, output) =
                run_shell_status(state, &thread_id, "/", &command, timeout)?;
            let truncated = output.len() > 20000;
            let shown: String = output.chars().take(20000).collect();
            Ok(json!({
                "operation": operation,
                "minutes": minutes,
                "output": shown,
                "truncated": truncated,
                "exitCode": exit_code,
            }))
        }
        "service_status" => {
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                "/",
                "/bin/launchctl list",
                timeout,
            )?;
            let mut services: Vec<Value> = Vec::new();
            for line in output.lines() {
                let parts: Vec<&str> = line.split('\t').collect();
                if parts.len() < 3 {
                    continue;
                }
                let pid = parts[0].trim();
                let status = parts[1].trim();
                let label = parts[2].trim();
                if label.is_empty() || label == "Label" {
                    continue;
                }
                services.push(json!({
                    "pid": pid,
                    "status": status,
                    "label": label,
                }));
            }
            Ok(json!({
                "operation": operation,
                "services": services,
                "exitCode": exit_code,
            }))
        }
        "config_read" => {
            let sysctl_name = req_str(args, "sysctlName", name)?;
            let allowed = [
                "hw.memsize",
                "hw.ncpu",
                "hw.model",
                "hw.machine",
                "kern.osrelease",
                "kern.osversion",
                "kern.version",
                "hw.physicalcpu",
                "hw.logicalcpu",
                "machdep.cpu.brand_string",
            ];
            if !allowed.contains(&sysctl_name.as_str()) {
                return Err(failed(format!(
                    "{name} config_read sysctlName must be one of: {}.",
                    allowed.join(", ")
                )));
            }
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!("/usr/sbin/sysctl -n {}", shell_quote(&sysctl_name)),
                timeout,
            )?;
            Ok(json!({
                "operation": operation,
                "sysctlName": sysctl_name,
                "value": output.trim(),
                "exitCode": exit_code,
            }))
        }
        "user_defaults_write" => {
            let confirmed = args.get("confirm").and_then(Value::as_bool).unwrap_or(false);
            if !confirmed {
                return Err(failed(format!(
                    "{name} user_defaults_write is a mutation; pass confirm=true."
                )));
            }
            let domain = req_str(args, "domain", name)?;
            let key = req_str(args, "key", name)?;
            let value = req_str(args, "value", name)?;
            let value_type = opt_str(args, "valueType").unwrap_or_else(|| "string".to_owned());
            if !["string", "bool", "int"].contains(&value_type.as_str()) {
                return Err(failed(format!(
                    "{name} user_defaults_write valueType must be string, bool, or int."
                )));
            }
            if domain == "NSGlobalDomain"
                || domain.starts_with('/')
                || domain.contains("..")
                || domain.starts_with('-')
            {
                return Err(failed(format!(
                    "{name} user_defaults_write refuses NSGlobalDomain and non-user domains."
                )));
            }
            if key.is_empty() || key.contains(' ') || key.starts_with('-') {
                return Err(failed(format!("{name} key is not a valid token.")));
            }
            let (before_exit, before_output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!(
                    "defaults read {} {}",
                    shell_quote(&domain),
                    shell_quote(&key)
                ),
                timeout,
            )?;
            let previous: Value = if before_exit == 0 {
                json!(before_output.trim())
            } else {
                Value::Null
            };
            let (flag, written): (&str, String) = match value_type.as_str() {
                "bool" => {
                    if value != "true" && value != "false" {
                        return Err(failed(format!(
                            "{name} user_defaults_write bool value must be true or false."
                        )));
                    }
                    ("-bool", if value == "true" { "1".to_owned() } else { "0".to_owned() })
                }
                "int" => {
                    if value.parse::<i64>().is_err() {
                        return Err(failed(format!(
                            "{name} user_defaults_write int value must be an integer."
                        )));
                    }
                    ("-int", value.clone())
                }
                _ => ("-string", value.clone()),
            };
            let (write_exit, write_output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!(
                    "defaults write {} {} {} {}",
                    shell_quote(&domain),
                    shell_quote(&key),
                    flag,
                    shell_quote(&value)
                ),
                timeout,
            )?;
            if write_exit != 0 {
                return Err(failed(format!(
                    "{name} defaults write failed: {write_output}"
                )));
            }
            let (after_exit, after_output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!(
                    "defaults read {} {}",
                    shell_quote(&domain),
                    shell_quote(&key)
                ),
                timeout,
            )?;
            let after = after_output.trim();
            let verified = after_exit == 0
                && (if value_type == "string" {
                    after == value
                } else {
                    after == written
                });
            Ok(json!({
                "operation": operation,
                "domain": domain,
                "key": key,
                "previousValue": previous,
                "newValue": value,
                "verified": verified,
            }))
        }
        _ => Err(failed(format!(
            "{name} operation must be system_info, dev_environment, process_list, network_interfaces, listening_sockets, connectivity, disk_info, system_log, service_status, config_read, or user_defaults_write."
        ))),
    }
}

fn g6_github_default_branch(
    state: &crate::ServerState,
    name: &str,
    thread_id: &str,
    repository: &str,
    timeout: u64,
) -> Result<String, CallError> {
    let (exit_code, output) = run_shell_status(
        state,
        thread_id,
        "/",
        &format!(
            "gh repo view {} --json defaultBranchRef --jq .defaultBranchRef.name",
            shell_quote(repository)
        ),
        timeout,
    )?;
    if g6_missing_cli(&output, exit_code) {
        return Err(failed(format!("{name} requires gh.")));
    }
    if exit_code != 0 {
        return Err(failed(format!("{name} gh repo view failed: {output}")));
    }
    let branch = output.trim().to_owned();
    if branch.is_empty() {
        return Err(failed(format!(
            "{name} gh repo view returned no default branch for {repository}."
        )));
    }
    Ok(branch)
}

fn g6_validate_repo_path(path: &str, tool: &str) -> Result<(), CallError> {
    if path.contains('\n')
        || path.contains('\r')
        || path.starts_with('-')
        || path.split('/').any(|part| part == "..")
    {
        return Err(failed(format!(
            "{tool} repository path must not contain newlines, start with a dash, or contain .. components."
        )));
    }
    Ok(())
}

fn g6_github_repo(
    state: &crate::ServerState,
    name: &str,
    args: &Value,
) -> Result<Value, CallError> {
    let thread_id = req_str(args, "threadId", name)?;
    let operation = req_str(args, "operation", name)?;
    let timeout = opt_u64(args, "timeoutSeconds").unwrap_or(120);
    let repository: String = if let (Some(owner), Some(repo)) =
        (opt_str(args, "owner"), opt_str(args, "repo"))
    {
        if owner.is_empty()
            || owner.contains('/')
            || owner.contains(' ')
            || repo.is_empty()
            || repo.contains('/')
            || repo.contains(' ')
        {
            return Err(failed(format!(
                "{name} owner and repo must be single path components."
            )));
        }
        format!("{owner}/{repo}")
    } else if let Some(url) = opt_str(args, "url").filter(|u| !u.is_empty()) {
        if !url.starts_with("https://github.com/") {
            return Err(failed(format!(
                "{name} url must be a github.com repository URL."
            )));
        }
        let rest = url.strip_prefix("https://github.com/").unwrap_or("");
        let parts: Vec<&str> = rest.split('/').collect();
        if parts.len() < 2 || parts[0].is_empty() || parts[1].is_empty() {
            return Err(failed(format!(
                "{name} url must name an owner and repository."
            )));
        }
        format!(
            "{}/{}",
            parts[0],
            parts[1].trim_end_matches(".git")
        )
    } else {
        return Err(failed(format!(
            "{name} is missing required argument \"owner\"."
        )));
    };
    let reference = opt_str(args, "ref");
    if let Some(reference) = &reference {
        if reference.is_empty() || reference.contains(' ') || reference.starts_with('-') {
            return Err(failed(format!("{name} ref is not a valid token.")));
        }
    }
    match operation.as_str() {
        "repository_info" => {
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!(
                    "gh repo view {} --json name,description,defaultBranchRef,createdAt,updatedAt,licenseInfo,primaryLanguage,stargazerCount,forkCount,isPrivate",
                    shell_quote(&repository)
                ),
                timeout,
            )?;
            if g6_missing_cli(&output, exit_code) {
                return Err(failed(format!("{name} requires gh.")));
            }
            if exit_code != 0 {
                return Err(failed(format!("{name} gh repo view failed: {output}")));
            }
            serde_json::from_str(&output)
                .map_err(|error| failed(format!("{name} could not parse gh output: {error}")))
        }
        "list_files" | "get_directory" => {
            let repo_path = opt_str(args, "path").unwrap_or_default();
            g6_validate_repo_path(&repo_path, name)?;
            let mut api_path = format!("repos/{repository}/contents");
            if !repo_path.is_empty() {
                api_path = format!("{api_path}/{repo_path}");
            }
            if let Some(reference) = &reference {
                api_path = format!("{api_path}?ref={reference}");
            }
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!("gh api {}", shell_quote(&api_path)),
                timeout,
            )?;
            if g6_missing_cli(&output, exit_code) {
                return Err(failed(format!("{name} requires gh.")));
            }
            if exit_code != 0 {
                return Err(failed(format!("{name} gh api failed: {output}")));
            }
            serde_json::from_str(&output)
                .map_err(|error| failed(format!("{name} could not parse gh output: {error}")))
        }
        "get_file" => {
            let repo_path = req_str(args, "path", name)?;
            g6_validate_repo_path(&repo_path, name)?;
            let mut api_path = format!("repos/{repository}/contents/{repo_path}");
            if let Some(reference) = &reference {
                api_path = format!("{api_path}?ref={reference}");
            }
            let (meta_exit, meta_output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!("gh api {}", shell_quote(&api_path)),
                timeout,
            )?;
            if g6_missing_cli(&meta_output, meta_exit) {
                return Err(failed(format!("{name} requires gh.")));
            }
            if meta_exit != 0 {
                return Err(failed(format!("{name} gh api failed: {meta_output}")));
            }
            let metadata: Value = serde_json::from_str(&meta_output)
                .map_err(|error| failed(format!("{name} could not parse gh output: {error}")))?;
            if metadata.get("type").and_then(Value::as_str) != Some("file") {
                return Err(failed(format!(
                    "Path {repo_path} is not a file in {repository}."
                )));
            }
            if metadata.get("size").and_then(Value::as_i64).unwrap_or(0) > 200000 {
                return Err(failed(format!(
                    "File {repo_path} exceeds 200000 bytes; fetch it with fetch_repository instead."
                )));
            }
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!(
                    "gh api {} -H {}",
                    shell_quote(&api_path),
                    shell_quote("Accept: application/vnd.github.raw")
                ),
                timeout,
            )?;
            if exit_code != 0 {
                return Err(failed(format!("{name} gh api failed: {output}")));
            }
            Ok(json!({
                "repository": repository,
                "path": repo_path,
                "size": metadata.get("size").cloned().unwrap_or(Value::Null),
                "content": output,
            }))
        }
        "get_tree" => {
            let tree_ref = match &reference {
                Some(reference) => reference.clone(),
                None => g6_github_default_branch(state, name, &thread_id, &repository, timeout)?,
            };
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!(
                    "gh api {}",
                    shell_quote(&format!(
                        "repos/{repository}/git/trees/{tree_ref}?recursive=1"
                    ))
                ),
                timeout,
            )?;
            if g6_missing_cli(&output, exit_code) {
                return Err(failed(format!("{name} requires gh.")));
            }
            if exit_code != 0 {
                return Err(failed(format!("{name} gh api failed: {output}")));
            }
            let value: Value = serde_json::from_str(&output)
                .map_err(|error| failed(format!("{name} could not parse gh output: {error}")))?;
            let tree = value
                .get("tree")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let count = tree.len();
            Ok(json!({
                "repository": repository,
                "ref": tree_ref,
                "truncated": value.get("truncated").cloned().unwrap_or(Value::Null),
                "entries": tree.into_iter().take(500).collect::<Vec<Value>>(),
                "entryCount": count,
            }))
        }
        "search_code" => {
            let query = req_str(args, "query", name)?;
            if query.is_empty() || query.starts_with('-') || query.contains('\n') {
                return Err(failed(format!("{name} query is not a valid token.")));
            }
            if !query.chars().all(|ch| {
                ch.is_alphanumeric() || "_:.+- ".contains(ch)
            }) {
                return Err(failed(format!(
                    "{name} search_code query must use only letters, digits, space, underscore, dot, colon, plus, or dash."
                )));
            }
            let encoded = query.replace(' ', "+");
            let (exit_code, output) = run_shell_status(
                state,
                &thread_id,
                "/",
                &format!(
                    "gh api {}",
                    shell_quote(&format!("search/code?q=repo:{repository}+{encoded}"))
                ),
                timeout,
            )?;
            if g6_missing_cli(&output, exit_code) {
                return Err(failed(format!("{name} requires gh.")));
            }
            if exit_code != 0 {
                return Err(failed(format!("{name} gh api failed: {output}")));
            }
            let value: Value = serde_json::from_str(&output)
                .map_err(|error| failed(format!("{name} could not parse gh output: {error}")))?;
            let items = value
                .get("items")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            Ok(json!({
                "repository": repository,
                "query": query,
                "totalCount": value.get("total_count").cloned().unwrap_or(Value::Null),
                "items": items.into_iter().take(20).collect::<Vec<Value>>(),
            }))
        }
        "fetch_repository" => {
            let tree_ref = match &reference {
                Some(reference) => reference.clone(),
                None => g6_github_default_branch(state, name, &thread_id, &repository, timeout)?,
            };
            let root = state
                .cwd
                .to_str()
                .map(str::to_owned)
                .or_else(|| opt_str(args, "cwd"))
                .ok_or_else(|| {
                    failed(format!(
                        "{name} fetch_repository needs a workspace directory."
                    ))
                })?;
            let safe_ref = tree_ref.replace('/', "-");
            let repo_name = repository
                .split('/')
                .next_back()
                .unwrap_or("repo")
                .to_owned();
            let file_name = format!("{repo_name}-{safe_ref}.tar.gz");
            run_shell(
                state,
                &thread_id,
                &root,
                &format!(
                    "gh api {} > {}",
                    shell_quote(&format!("repos/{repository}/tarball/{tree_ref}")),
                    shell_quote(&file_name)
                ),
                timeout,
            )?;
            let size = std::fs::metadata(Path::new(&root).join(&file_name))
                .map(|metadata| metadata.len() as i64)
                .unwrap_or(0);
            Ok(json!({
                "repository": repository,
                "ref": tree_ref,
                "path": file_name,
                "bytes": size,
            }))
        }
        _ => Err(failed(format!(
            "{name} operation must be repository_info, list_files, get_file, get_directory, get_tree, search_code, or fetch_repository."
        ))),
    }
}

fn g6_misc_call(
    state: &crate::ServerState,
    name: &str,
    args: &Value,
) -> Result<Value, CallError> {
    match name {
        "env_info" => Ok(g6_env_info(name)),
        "environment_variable_manager" => {
            let action = req_str(args, "action", name)?;
            match action.as_str() {
                "list" => {
                    let mut keys: Vec<String> = std::env::vars_os()
                        .filter_map(|(key, _)| key.to_str().map(str::to_owned))
                        .collect();
                    keys.sort();
                    Ok(json!({
                        "action": action,
                        "keys": keys,
                        "count": keys.len(),
                    }))
                }
                "get" => {
                    let key = req_str(args, "key", name)?;
                    match std::env::var_os(&key) {
                        Some(value) => Ok(json!({
                            "action": action,
                            "key": key,
                            "found": true,
                            "value": value.to_string_lossy(),
                        })),
                        None => Ok(json!({
                            "action": action,
                            "key": key,
                            "found": false,
                            "value": Value::Null,
                        })),
                    }
                }
                _ => Err(failed(format!(
                    "{name} action must be list or get. The process environment cannot be mutated by a tool; use a terminal export instead."
                ))),
            }
        }
        "clipboard_manager_tool" => {
            let action = req_str(args, "action", name)?;
            match action.as_str() {
                "read" => {
                    let output = std::process::Command::new("pbpaste")
                        .output()
                        .map_err(|error| failed(format!("{name} could not run pbpaste: {error}")))?;
                    if !output.status.success() {
                        return Err(failed(format!(
                            "{name} pbpaste failed: {}",
                            String::from_utf8_lossy(&output.stderr).trim()
                        )));
                    }
                    let text = String::from_utf8_lossy(&output.stdout).into_owned();
                    Ok(json!({
                        "action": action,
                        "hasText": !text.is_empty(),
                        "text": if text.is_empty() { Value::Null } else { json!(text) },
                    }))
                }
                "write" => {
                    let text = req_str(args, "text", name)?;
                    let mut child = std::process::Command::new("pbcopy")
                        .stdin(std::process::Stdio::piped())
                        .spawn()
                        .map_err(|error| failed(format!("{name} could not run pbcopy: {error}")))?;
                    if let Some(stdin) = child.stdin.as_mut() {
                        use std::io::Write;
                        stdin
                            .write_all(text.as_bytes())
                            .map_err(|error| failed(format!("{name} could not write to pbcopy: {error}")))?;
                    }
                    let status = child
                        .wait()
                        .map_err(|error| failed(format!("{name} could not wait for pbcopy: {error}")))?;
                    if !status.success() {
                        return Err(failed(format!("{name} pbcopy failed.")));
                    }
                    Ok(json!({
                        "action": action,
                        "written": true,
                        "characters": text.chars().count(),
                    }))
                }
                "clear" => {
                    let status = std::process::Command::new("pbcopy")
                        .stdin(std::process::Stdio::null())
                        .status()
                        .map_err(|error| failed(format!("{name} could not run pbcopy: {error}")))?;
                    if !status.success() {
                        return Err(failed(format!("{name} pbcopy failed.")));
                    }
                    Ok(json!({
                        "action": action,
                        "cleared": true,
                    }))
                }
                _ => Err(failed(format!(
                    "{name} action must be read, write, or clear."
                ))),
            }
        }
        "system_notification_tool" => {
            let title = req_str(args, "title", name)?;
            let body = opt_str(args, "body").unwrap_or_default();
            let escape_applescript = |text: &str| {
                text.replace('\\', "\\\\").replace('"', "\\\"")
            };
            let script = format!(
                "display notification \"{}\" with title \"{}\"",
                escape_applescript(&body),
                escape_applescript(&title)
            );
            let status = std::process::Command::new("osascript")
                .args(["-e", &script])
                .status()
                .map_err(|error| failed(format!("{name} could not run osascript: {error}")))?;
            if !status.success() {
                return Err(failed(format!(
                    "{name} could not post the notification."
                )));
            }
            let identifier = format!(
                "agents-tool-{}",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|duration| duration.as_nanos())
                    .unwrap_or(0)
            );
            Ok(json!({
                "posted": true,
                "identifier": identifier,
                "title": title,
                "note": "Delivery requires notification authorization, granted at app launch.",
            }))
        }
        "tool_capability_lookup" => {
            let tool_name = req_str(args, "tool", name)?;
            let Some(found) = definition(&tool_name) else {
                return Err(CallError::UnknownTool(tool_name));
            };
            Ok(json!({
                "name": found.name,
                "description": found.description,
                "action": found.action,
                "channel": found.channel,
                "parameters": found.params.iter().map(|param| {
                    json!({
                        "name": param.name,
                        "type": param.kind,
                        "required": param.required,
                        "description": param.description,
                    })
                }).collect::<Vec<Value>>(),
            }))
        }
        "search_skills" => {
            let query = req_str(args, "query", name)?;
            let limit = opt_u64(args, "limit").unwrap_or(8).clamp(1, 20) as usize;
            let Some(dir) = crate::assets::resolve_assets_dir(state.assets_dir.as_deref()) else {
                return Err(failed(format!(
                    "{name} could not locate the bundled SystemAssets directory."
                )));
            };
            let names = crate::assets::list_asset_names(&dir)
                .map_err(|error| failed(format!("{name} could not list SystemAssets: {error}")))?;
            let document_count = names.len();
            let query_lower = query.to_lowercase();
            let tokens: Vec<&str> = query_lower.split_whitespace().collect();
            let mut scored: Vec<(i64, Value)> = Vec::new();
            for file_name in &names {
                let path = dir.join(file_name);
                let Ok(content) = std::fs::read_to_string(&path) else {
                    continue;
                };
                let lower = content.to_lowercase();
                let mut title = String::new();
                let mut section_heading = String::new();
                let mut heading_path: Vec<String> = Vec::new();
                for line in content.lines() {
                    let trimmed = line.trim();
                    if let Some(rest) = trimmed.strip_prefix("# ") {
                        if title.is_empty() {
                            title = rest.trim().to_owned();
                        }
                    } else if let Some(rest) = trimmed.strip_prefix("## ") {
                        if section_heading.is_empty() {
                            section_heading = rest.trim().to_owned();
                            heading_path.push(section_heading.clone());
                        }
                    }
                }
                if title.is_empty() {
                    title = file_name
                        .strip_suffix(".md")
                        .unwrap_or(file_name)
                        .to_owned();
                }
                if section_heading.is_empty() {
                    section_heading = title.clone();
                }
                let mut score: i64 = 0;
                for token in &tokens {
                    if file_name.to_lowercase().contains(*token) {
                        score += 5;
                    }
                    if title.to_lowercase().contains(*token) {
                        score += 10;
                    }
                    if section_heading.to_lowercase().contains(*token) {
                        score += 5;
                    }
                    score += lower.matches(*token).count() as i64;
                }
                if score > 0 {
                    let truncated = content.chars().count() > 2000;
                    let text: String = content.chars().take(2000).collect();
                    scored.push((
                        score,
                        json!({
                            "documentID": file_name.strip_suffix(".md").unwrap_or(file_name),
                            "fileName": file_name,
                            "title": title,
                            "sectionHeading": section_heading,
                            "headingPath": heading_path,
                            "text": text,
                            "truncated": truncated,
                            "score": score,
                            "reason": "token match",
                        }),
                    ));
                }
            }
            scored.sort_by(|a, b| b.0.cmp(&a.0));
            let results: Vec<Value> = scored.into_iter().take(limit).map(|(_, value)| value).collect();
            Ok(json!({
                "query": query,
                "searched": "bundled SystemAssets index",
                "documentCount": document_count,
                "results": results,
            }))
        }
        "plan-AskUser" => {
            let thread_id = req_str(args, "threadId", name)?;
            let Some(request_id) = opt_str(args, "requestId") else {
                let pending = engine_request(
                    state,
                    "agent.pending",
                    json!({"threadId": thread_id}),
                )?;
                return Ok(json!({
                    "threadId": thread_id,
                    "pending": pending,
                    "note": "Lists pending provider questions. This tool does not present a new question and does not suspend the turn.",
                }));
            };
            let Some(raw_answers) = args.get("answers").and_then(Value::as_array) else {
                return Err(failed(format!(
                    "{name} is missing required argument \"answers\"."
                )));
            };
            if raw_answers.is_empty() {
                return Err(failed(format!(
                    "{name} is missing required argument \"answers\"."
                )));
            }
            let mut answers_object = serde_json::Map::new();
            for raw in raw_answers {
                let Some(question_id) = raw.get("questionId").and_then(Value::as_str) else {
                    return Err(failed(format!(
                        "{name} is missing required argument \"questionId\"."
                    )));
                };
                if question_id.is_empty() {
                    return Err(failed(format!(
                        "{name} is missing required argument \"questionId\"."
                    )));
                }
                let Some(values) = raw.get("answers").and_then(Value::as_array) else {
                    return Err(failed(format!(
                        "{name} is missing required argument \"answers\"."
                    )));
                };
                if values.is_empty()
                    || values
                        .iter()
                        .any(|value| value.as_str().map(|text| text.is_empty()).unwrap_or(true))
                {
                    return Err(failed(format!(
                        "{name} is missing required argument \"answers\"."
                    )));
                }
                answers_object.insert(
                    question_id.to_owned(),
                    json!({"answers": values}),
                );
            }
            engine_request(
                state,
                "agent.answer",
                json!({
                    "threadId": thread_id,
                    "requestId": request_id,
                    "answers": answers_object,
                }),
            )
        }
        "session_progress_report" => {
            let cwd = req_str(args, "cwd", name)?;
            let path = opt_str(args, "path")
                .unwrap_or_else(|| ".assist_temp/artifacts/agent_notes.md".to_owned());
            g6_validate_relative(&path, name)?;
            let mut phases: Vec<Value> = Vec::new();
            let mut failures: Vec<String> = Vec::new();
            let mut found = false;
            if let Ok(content) = read_text_file_at(&cwd, &path) {
                found = true;
                let mut current: Option<String> = None;
                let mut summary: Vec<String> = Vec::new();
                for line in content.lines() {
                    if let Some(rest) = line.strip_prefix("## ") {
                        if let Some(title) = current.take() {
                            phases.push(json!({
                                "title": title,
                                "summary": summary.join(" "),
                            }));
                        }
                        current = Some(rest.trim().to_owned());
                        summary = Vec::new();
                    } else if current.is_some() {
                        let trimmed = line.trim();
                        if !trimmed.is_empty() && summary.len() < 3 {
                            summary.push(trimmed.to_owned());
                        }
                        if trimmed.to_lowercase().contains("fail") && failures.len() < 20 {
                            failures.push(trimmed.to_owned());
                        }
                    }
                }
                if let Some(title) = current {
                    phases.push(json!({
                        "title": title,
                        "summary": summary.join(" "),
                    }));
                }
            }
            let mut last_save = Value::Null;
            if let Ok(entries) = g5_list_workspace_files(&cwd, "agent_notes.md", 5) {
                if let Some(entry) = entries.iter().find(|entry| g6_entry_path(entry) == path) {
                    if let Some(modified) = entry.get("modifiedAt").and_then(Value::as_f64) {
                        last_save = json!(modified);
                    }
                }
            }
            let mut workers: Vec<Value> = Vec::new();
            if let Some(thread_id) = opt_str(args, "threadId") {
                if let Ok(listed) = engine_request(
                    state,
                    "workers.list",
                    json!({"parentThreadId": thread_id}),
                ) {
                    if let Some(array) = listed.get("workers").and_then(Value::as_array) {
                        workers = array.clone();
                    } else if let Some(array) = listed.as_array() {
                        workers = array.clone();
                    }
                }
            }
            Ok(json!({
                "found": found,
                "path": path,
                "phases": phases,
                "failures": failures,
                "lastAgentNotesSave": last_save,
                "workers": workers,
            }))
        }
        "manage_memory" => {
            let action = req_str(args, "action", name)?;
            match action.as_str() {
                "store" | "edit" => {
                    let key = req_str(args, "key", name)?;
                    let value = req_str(args, "value", name)?;
                    let mut params = json!({"key": key, "value": value});
                    if let Some(scope) = opt_str(args, "scope") {
                        params["scope"] = json!(scope);
                    }
                    let mut stored = engine_request(state, "memory.store", params)?;
                    if let Some(object) = stored.as_object_mut() {
                        object.insert("action".to_owned(), json!(action));
                    }
                    Ok(stored)
                }
                "append" => {
                    let key = req_str(args, "key", name)?;
                    let value = req_str(args, "value", name)?;
                    let scope = opt_str(args, "scope");
                    let mut retrieve_params = json!({"key": key});
                    if let Some(scope) = &scope {
                        retrieve_params["scope"] = json!(scope);
                    }
                    let existing = engine_request(state, "memory.retrieve", retrieve_params)?;
                    let previous = existing
                        .get("value")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_owned();
                    let combined = if previous.is_empty() {
                        value.clone()
                    } else {
                        format!("{previous}\n{value}")
                    };
                    let mut store_params = json!({"key": key, "value": combined});
                    if let Some(scope) = scope {
                        store_params["scope"] = json!(scope);
                    }
                    let mut stored = engine_request(state, "memory.store", store_params)?;
                    if let Some(object) = stored.as_object_mut() {
                        object.insert("action".to_owned(), json!(action));
                    }
                    Ok(stored)
                }
                "delete" => {
                    let key = req_str(args, "key", name)?;
                    let mut params = json!({"key": key});
                    if let Some(scope) = opt_str(args, "scope") {
                        params["scope"] = json!(scope);
                    }
                    engine_request(state, "memory.delete", params)
                }
                "clear" => {
                    let scope = req_str(args, "scope", name)?;
                    let confirmed = args.get("confirm").and_then(Value::as_bool).unwrap_or(false);
                    if !confirmed {
                        return Err(failed(format!(
                            "{name} clear is irreversible; pass confirm=true."
                        )));
                    }
                    engine_request(
                        state,
                        "memory.clear",
                        json!({"scope": scope, "confirm": true}),
                    )
                }
                "list" => {
                    let mut params = json!({});
                    if let Some(scope) = opt_str(args, "scope") {
                        params["scope"] = json!(scope);
                    }
                    if let Some(query) = opt_str(args, "query") {
                        params["query"] = json!(query);
                    }
                    if let Some(limit) = opt_u64(args, "limit") {
                        params["limit"] = json!(limit);
                    }
                    engine_request(state, "memory.list", params)
                }
                _ => Err(failed(format!(
                    "{name} action must be store, edit, append, delete, clear, or list."
                ))),
            }
        }
        "fetch_documentation" => {
            let _ = req_str(args, "threadId", name)?;
            let url: String = if let Some(given) = opt_str(args, "url").filter(|u| !u.is_empty()) {
                if !given.starts_with("https://developer.apple.com") {
                    return Err(failed(format!(
                        "{name} url must be an https URL on developer.apple.com."
                    )));
                }
                given
            } else if let Some(query) = opt_str(args, "query").filter(|q| !q.is_empty()) {
                let encoded: String = query
                    .chars()
                    .map(|ch| {
                        if ch.is_alphanumeric() || "-_.~".contains(ch) {
                            ch.to_string()
                        } else {
                            format!("%{:02X}", ch as u32)
                        }
                    })
                    .collect();
                format!("https://developer.apple.com/search/?q={encoded}")
            } else if let Some(framework) = opt_str(args, "framework").filter(|f| !f.is_empty()) {
                if !framework
                    .chars()
                    .all(|ch| ch.is_alphanumeric() || ch == '_')
                {
                    return Err(failed(format!(
                        "{name} framework must use only letters, digits, or underscore."
                    )));
                }
                format!(
                    "https://developer.apple.com/documentation/{}/",
                    framework.to_lowercase()
                )
            } else {
                return Err(failed(format!(
                    "{name} is missing required argument \"query\"."
                )));
            };
            let (status, content_type, text) = g6_curl_fetch(&url, 30, name)?;
            if !(200..300).contains(&status) {
                return Err(failed(format!("{name} fetch returned HTTP {status}.")));
            }
            let mut title: Option<String> = None;
            if let Ok(regex) = regex::RegexBuilder::new(r"<title>([^<]+)</title>")
                .case_insensitive(true)
                .build()
            {
                if let Some(caps) = regex.captures(&text) {
                    title = caps.get(1).map(|m| m.as_str().trim().to_owned());
                }
            }
            let truncated = text.chars().count() > 8000;
            let shown: String = text.chars().take(8000).collect();
            Ok(json!({
                "url": url,
                "statusCode": status,
                "contentType": content_type,
                "title": title,
                "text": shown,
                "truncated": truncated,
            }))
        }
        "external_resource_gateway" => {
            let _ = req_str(args, "threadId", name)?;
            let url = req_str(args, "url", name)?;
            if !url.starts_with("https://") {
                return Err(failed(format!(
                    "{name} url must be an https URL."
                )));
            }
            let (status, _, text) = g6_curl_fetch(&url, 30, name)?;
            if !(200..300).contains(&status) {
                return Err(failed(format!("{name} fetch returned HTTP {status}.")));
            }
            let value: Value = serde_json::from_str(&text)
                .map_err(|_| failed(format!("{name} response was not JSON.")))?;
            Ok(json!({
                "url": url,
                "statusCode": status,
                "value": value,
            }))
        }
        "read_url_content" => {
            let _ = req_str(args, "threadId", name)?;
            let url = req_str(args, "url", name)?;
            if !url.starts_with("https://") {
                return Err(failed(format!(
                    "{name} url must be an https URL."
                )));
            }
            let max_chars = opt_u64(args, "maxChars").unwrap_or(8000).clamp(1, 100000) as usize;
            let (status, content_type, text) = g6_curl_fetch(&url, 30, name)?;
            if !(200..300).contains(&status) {
                return Err(failed(format!("{name} fetch returned HTTP {status}.")));
            }
            let truncated = text.chars().count() > max_chars;
            let content: String = text.chars().take(max_chars).collect();
            Ok(json!({
                "url": url,
                "statusCode": status,
                "contentType": content_type,
                "content": content,
                "truncated": truncated,
            }))
        }
        "use_app" => g6_use_app(state, name, args),
        "derived_data_locate" => {
            let path = opt_str(args, "path");
            let limit = opt_u64(args, "limit").unwrap_or(50).clamp(1, 500) as usize;
            Ok(g6_derived_data(name, path.as_deref(), limit))
        }
        _ => Err(failed(format!("Unknown G6 misc tool {name}."))),
    }
}

fn g6_use_app(
    state: &crate::ServerState,
    name: &str,
    args: &Value,
) -> Result<Value, CallError> {
    let thread_id = req_str(args, "threadId", name)?;
    let action = req_str(args, "action", name)?;
    let missing = [
        "activate",
        "close_application",
        "select_window",
        "get_focused_element",
        "select_all",
        "copy",
        "paste",
        "wait_for_element",
        "wait_for_window",
    ];
    if missing.contains(&action.as_str()) {
        return Err(failed(format!(
            "{name} action {action} has no engine tool; the capability is not implemented."
        )));
    }
    let mapped: &str = match action.as_str() {
        "list_applications" => "list_apps",
        "inspect_application" => "list_windows",
        "launch" => "launch_app",
        "list_windows" => "list_windows",
        "inspect_ui" | "get_accessibility_tree" => "get_window_state",
        "click" | "activate_element" => "click",
        "double_click" => "double_click",
        "right_click" => "right_click",
        "move_pointer" => "move_cursor",
        "drag" => "drag",
        "scroll" => "scroll",
        "type_text" => "type_text",
        "press_key" => "press_key",
        "press_shortcut" => "hotkey",
        "set_element_value" => "set_value",
        "select_menu" => "invoke_menu",
        "verify" => "verify_state",
        "take_screenshot" => {
            return run_computer_use_named(
                state,
                "get_desktop_state",
                "get_desktop_state",
                &json!({"threadId": thread_id, "include_screenshot": true}),
            );
        }
        _ => {
            return Err(failed(format!(
                "{name} action {action} is not a known action."
            )));
        }
    };
    let mut mapped_args = args.clone();
    if action == "inspect_application" {
        if mapped_args.get("pid").is_none() {
            if let Some(app_name) = opt_str(args, "app_name") {
                let apps = run_computer_use_operation(
                    state,
                    "list_apps",
                    &json!({"threadId": thread_id}),
                )?;
                let Some(pid) = g6_find_pid(&apps, &app_name) else {
                    return Err(failed(format!(
                        "No running app named {app_name} found."
                    )));
                };
                if let Some(object) = mapped_args.as_object_mut() {
                    object.insert("pid".to_owned(), json!(pid));
                }
            }
        }
    }
    if action == "launch" {
        if mapped_args.get("bundle_id").is_none() {
            if let Some(identifier) = opt_str(args, "app_identifier") {
                if let Some(object) = mapped_args.as_object_mut() {
                    object.insert("bundle_id".to_owned(), json!(identifier));
                }
            }
        }
    }
    if let Some(object) = mapped_args.as_object_mut() {
        object.insert("threadId".to_owned(), json!(thread_id));
    }
    let result = run_computer_use_named(state, mapped, mapped, &mapped_args)?;
    Ok(json!({
        "action": action,
        "tool": mapped,
        "result": result,
    }))
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
        "project_build" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let mut argv: Vec<String> = vec!["xcodebuild".to_owned(), "build".to_owned()];
            if let Some(scheme) = opt_str(&args, "scheme") {
                g3_token(&scheme, "scheme", name)?;
                argv.push("-scheme".to_owned());
                argv.push(scheme);
            }
            if let Some(configuration) = opt_str(&args, "configuration") {
                g3_token(&configuration, "configuration", name)?;
                argv.push("-configuration".to_owned());
                argv.push(configuration);
            }
            if let Some(destination) = opt_str(&args, "destination") {
                g3_token(&destination, "destination", name)?;
                argv.push("-destination".to_owned());
                argv.push(destination);
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(600);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("xcodebuild", exit_code, &output)?;
            let diagnostics = g3_diagnostics(&output);
            let errors = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("error"))
                .count();
            let warnings = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("warning"))
                .count();
            Ok(json!({"succeeded": exit_code == 0, "exitCode": exit_code, "errors": errors, "warnings": warnings, "diagnostics": diagnostics, "output": output}))
        }
        "project_test" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let mut argv: Vec<String> = vec!["xcodebuild".to_owned(), "test".to_owned()];
            if let Some(scheme) = opt_str(&args, "scheme") {
                g3_token(&scheme, "scheme", name)?;
                argv.push("-scheme".to_owned());
                argv.push(scheme);
            }
            if let Some(configuration) = opt_str(&args, "configuration") {
                g3_token(&configuration, "configuration", name)?;
                argv.push("-configuration".to_owned());
                argv.push(configuration);
            }
            if let Some(destination) = opt_str(&args, "destination") {
                g3_token(&destination, "destination", name)?;
                argv.push("-destination".to_owned());
                argv.push(destination);
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(600);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("xcodebuild", exit_code, &output)?;
            let diagnostics = g3_diagnostics(&output);
            let errors = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("error"))
                .count();
            let warnings = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("warning"))
                .count();
            let (executed, failed, suites_passed, suites_failed) = g3_test_summary(&output);
            Ok(json!({"succeeded": exit_code == 0, "exitCode": exit_code, "testsExecuted": executed, "testsFailed": failed, "suitesPassed": suites_passed, "suitesFailed": suites_failed, "errors": errors, "warnings": warnings, "diagnostics": diagnostics, "output": output}))
        }
        "compiler_diagnostics_engine" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let kind = opt_str(&args, "kind").unwrap_or_else(|| "xcodebuild".to_owned());
            let mut argv: Vec<String> = Vec::new();
            let mut cli = "xcodebuild";
            match kind.as_str() {
                "xcodebuild" => {
                    argv = vec!["xcodebuild".to_owned(), "build".to_owned()];
                    if let Some(scheme) = opt_str(&args, "scheme") {
                        g3_token(&scheme, "scheme", name)?;
                        argv.push("-scheme".to_owned());
                        argv.push(scheme);
                    }
                    if let Some(destination) = opt_str(&args, "destination") {
                        g3_token(&destination, "destination", name)?;
                        argv.push("-destination".to_owned());
                        argv.push(destination);
                    }
                }
                "swiftpm" => {
                    argv = vec!["swift".to_owned(), "build".to_owned()];
                    cli = "swift";
                }
                _ => {
                    return Err(failed(
                        "compiler_diagnostics_engine kind must be xcodebuild or swiftpm.",
                    ));
                }
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(600);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli(cli, exit_code, &output)?;
            let diagnostics = g3_diagnostics(&output);
            let errors = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("error"))
                .count();
            let warnings = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("warning"))
                .count();
            Ok(json!({"exitCode": exit_code, "errors": errors, "warnings": warnings, "diagnostics": diagnostics, "output": output}))
        }
        "dependency_resolution_engine" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let kind = opt_str(&args, "kind").unwrap_or_else(|| "swiftpm".to_owned());
            let mut argv: Vec<String> = Vec::new();
            let mut cli = "swift";
            match kind.as_str() {
                "swiftpm" => {
                    argv = vec![
                        "swift".to_owned(),
                        "package".to_owned(),
                        "resolve".to_owned(),
                    ];
                }
                "xcode" => {
                    let scheme = match opt_str(&args, "scheme") {
                        Some(scheme) => scheme,
                        None => {
                            return Err(failed(
                                "Tool \"dependency_resolution_engine\" is missing required argument \"scheme\".",
                            ));
                        }
                    };
                    g3_token(&scheme, "scheme", name)?;
                    argv = vec![
                        "xcodebuild".to_owned(),
                        "-resolvePackageDependencies".to_owned(),
                        "-scheme".to_owned(),
                        scheme,
                    ];
                    cli = "xcodebuild";
                }
                _ => {
                    return Err(failed(
                        "dependency_resolution_engine kind must be swiftpm or xcode.",
                    ));
                }
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(300);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli(cli, exit_code, &output)?;
            Ok(json!({"resolved": exit_code == 0, "exitCode": exit_code, "output": output}))
        }
        "generate_xcodeproj" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(120);
            let (exit_code, output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &["xcodegen".to_owned(), "generate".to_owned()],
                timeout,
            )?;
            g3_missing_cli("xcodegen", exit_code, &output)?;
            Ok(json!({"generated": exit_code == 0, "exitCode": exit_code, "output": output}))
        }
        "project_scheme_list" | "project_target_list" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(60);
            let (exit_code, output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &[
                    "xcodebuild".to_owned(),
                    "-list".to_owned(),
                    "-json".to_owned(),
                ],
                timeout,
            )?;
            g3_missing_cli("xcodebuild", exit_code, &output)?;
            if exit_code != 0 {
                if name == "project_target_list" {
                    return Ok(json!({"targets": [], "exitCode": exit_code, "output": output}));
                }
                return Ok(json!({"name": "", "schemes": [], "targets": [], "configurations": [], "exitCode": exit_code, "output": output}));
            }
            let listed = g3_parse_json(&output, name)?;
            let (schemes, targets, configurations, project_name) = g3_xcodebuild_list(&listed);
            if name == "project_target_list" {
                return Ok(json!({"targets": targets, "exitCode": exit_code, "output": output}));
            }
            Ok(json!({"name": project_name, "schemes": schemes, "targets": targets, "configurations": configurations, "exitCode": exit_code, "output": output}))
        }
        "project_build_settings" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let mut argv: Vec<String> =
                vec!["xcodebuild".to_owned(), "-showBuildSettings".to_owned()];
            if let Some(scheme) = opt_str(&args, "scheme") {
                g3_token(&scheme, "scheme", name)?;
                argv.push("-scheme".to_owned());
                argv.push(scheme);
            }
            if let Some(configuration) = opt_str(&args, "configuration") {
                g3_token(&configuration, "configuration", name)?;
                argv.push("-configuration".to_owned());
                argv.push(configuration);
            }
            if let Some(target) = opt_str(&args, "target") {
                g3_token(&target, "target", name)?;
                argv.push("-target".to_owned());
                argv.push(target);
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(120);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("xcodebuild", exit_code, &output)?;
            let settings = g3_build_settings(&output);
            Ok(json!({"settings": settings, "exitCode": exit_code, "output": output}))
        }
        "project_clean" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            if !opt_bool(&args, "confirm").unwrap_or(false) {
                return Err(failed(
                    "project_clean removes build products; pass confirm=true.",
                ));
            }
            let mut argv: Vec<String> = vec!["xcodebuild".to_owned(), "clean".to_owned()];
            if let Some(scheme) = opt_str(&args, "scheme") {
                g3_token(&scheme, "scheme", name)?;
                argv.push("-scheme".to_owned());
                argv.push(scheme);
            }
            if let Some(configuration) = opt_str(&args, "configuration") {
                g3_token(&configuration, "configuration", name)?;
                argv.push("-configuration".to_owned());
                argv.push(configuration);
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(300);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("xcodebuild", exit_code, &output)?;
            Ok(json!({"cleaned": exit_code == 0, "exitCode": exit_code, "output": output}))
        }
        "project_archive" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let scheme = req_str(&args, "scheme", name)?;
            g3_token(&scheme, "scheme", name)?;
            let archive_path = req_str(&args, "archivePath", name)?;
            g3_relative_path(&archive_path, name)?;
            let mut argv: Vec<String> = vec![
                "xcodebuild".to_owned(),
                "archive".to_owned(),
                "-scheme".to_owned(),
                scheme,
                "-archivePath".to_owned(),
                archive_path.clone(),
            ];
            if let Some(configuration) = opt_str(&args, "configuration") {
                g3_token(&configuration, "configuration", name)?;
                argv.push("-configuration".to_owned());
                argv.push(configuration);
            }
            if let Some(destination) = opt_str(&args, "destination") {
                g3_token(&destination, "destination", name)?;
                argv.push("-destination".to_owned());
                argv.push(destination);
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(1800);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("xcodebuild", exit_code, &output)?;
            let diagnostics = g3_diagnostics(&output);
            let errors = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("error"))
                .count();
            let warnings = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("warning"))
                .count();
            Ok(json!({"archived": exit_code == 0, "archivePath": archive_path, "exitCode": exit_code, "errors": errors, "warnings": warnings, "diagnostics": diagnostics, "output": output}))
        }
        "test_run_single" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let test_identifier = req_str(&args, "testIdentifier", name)?;
            g3_test_identifier(&test_identifier, name)?;
            let mut argv: Vec<String> = vec![
                "xcodebuild".to_owned(),
                "test".to_owned(),
                format!("-only-testing:{test_identifier}"),
            ];
            if let Some(scheme) = opt_str(&args, "scheme") {
                g3_token(&scheme, "scheme", name)?;
                argv.push("-scheme".to_owned());
                argv.push(scheme);
            }
            if let Some(destination) = opt_str(&args, "destination") {
                g3_token(&destination, "destination", name)?;
                argv.push("-destination".to_owned());
                argv.push(destination);
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(600);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("xcodebuild", exit_code, &output)?;
            let diagnostics = g3_diagnostics(&output);
            let errors = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("error"))
                .count();
            let warnings = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("warning"))
                .count();
            let (executed, failed, suites_passed, suites_failed) = g3_test_summary(&output);
            Ok(json!({"succeeded": exit_code == 0, "testIdentifier": test_identifier, "exitCode": exit_code, "testsExecuted": executed, "testsFailed": failed, "suitesPassed": suites_passed, "suitesFailed": suites_failed, "errors": errors, "warnings": warnings, "diagnostics": diagnostics, "output": output}))
        }
        "test_coverage_report" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let xcresult_path = req_str(&args, "xcresultPath", name)?;
            g3_relative_path(&xcresult_path, name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(300);
            let (exit_code, output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &[
                    "xcrun".to_owned(),
                    "xccov".to_owned(),
                    "view".to_owned(),
                    "--report".to_owned(),
                    "--json".to_owned(),
                    xcresult_path,
                ],
                timeout,
            )?;
            g3_missing_cli("xcrun", exit_code, &output)?;
            if exit_code != 0 {
                return Ok(json!({"lineCoverage": Value::Null, "targets": [], "exitCode": exit_code, "output": output}));
            }
            let coverage = g3_parse_json(&output, name)?;
            let targets = g3_coverage(&coverage);
            Ok(json!({"lineCoverage": coverage["lineCoverage"], "targets": targets, "exitCode": exit_code, "output": output}))
        }
        "test_coverage_reporter" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let xcresult_path = req_str(&args, "xcresultPath", name)?;
            g3_relative_path(&xcresult_path, name)?;
            let format = opt_str(&args, "format").unwrap_or_else(|| "text".to_owned());
            if format != "json" && format != "text" {
                return Err(failed("test_coverage_reporter format must be json or text."));
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(300);
            let mut argv: Vec<String> = vec![
                "xcrun".to_owned(),
                "xccov".to_owned(),
                "view".to_owned(),
                "--report".to_owned(),
            ];
            if format == "json" {
                argv.push("--json".to_owned());
            }
            argv.push(xcresult_path);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("xcrun", exit_code, &output)?;
            if format == "json" {
                if exit_code != 0 {
                    return Ok(json!({"format": format, "report": Value::Null, "exitCode": exit_code, "output": output}));
                }
                let report = g3_parse_json(&output, name)?;
                return Ok(json!({"format": format, "report": report, "exitCode": exit_code, "output": output}));
            }
            Ok(json!({"format": format, "report": output, "exitCode": exit_code, "output": output}))
        }
        "performance_benchmark" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let benchmark = req_str(&args, "benchmark", name)?;
            let base: &[&str] = match benchmark.as_str() {
                "xcodebuild-build" => &["xcodebuild", "build"],
                "xcodebuild-test" => &["xcodebuild", "test"],
                "swift-build" => &["swift", "build"],
                "swift-test" => &["swift", "test"],
                "xcodebuild-clean-build" => &["xcodebuild", "clean", "build"],
                _ => {
                    return Err(failed(
                        "performance_benchmark benchmark must be xcodebuild-build, xcodebuild-test, swift-build, swift-test, or xcodebuild-clean-build.",
                    ));
                }
            };
            let is_xcodebuild = benchmark.starts_with("xcodebuild");
            let mut argv: Vec<String> = base.iter().map(|part| part.to_string()).collect();
            if let Some(scheme) = opt_str(&args, "scheme") {
                if !is_xcodebuild {
                    return Err(failed(
                        "performance_benchmark scheme applies only to xcodebuild benchmarks.",
                    ));
                }
                g3_token(&scheme, "scheme", name)?;
                argv.push("-scheme".to_owned());
                argv.push(scheme);
            }
            let cli = argv[0].clone();
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(600);
            let started = std::time::Instant::now();
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            let elapsed = started.elapsed().as_secs_f64();
            g3_missing_cli(&cli, exit_code, &output)?;
            Ok(json!({"benchmark": benchmark, "elapsedSeconds": elapsed, "exitCode": exit_code, "output": output}))
        }
        "docc_build" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let scheme = req_str(&args, "scheme", name)?;
            g3_token(&scheme, "scheme", name)?;
            let mut argv: Vec<String> = vec![
                "xcodebuild".to_owned(),
                "docbuild".to_owned(),
                "-scheme".to_owned(),
                scheme,
            ];
            if let Some(destination) = opt_str(&args, "destination") {
                g3_token(&destination, "destination", name)?;
                argv.push("-destination".to_owned());
                argv.push(destination);
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(600);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("xcodebuild", exit_code, &output)?;
            let diagnostics = g3_diagnostics(&output);
            let errors = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("error"))
                .count();
            let warnings = diagnostics
                .iter()
                .filter(|d| d["severity"].as_str() == Some("warning"))
                .count();
            Ok(json!({"succeeded": exit_code == 0, "exitCode": exit_code, "errors": errors, "warnings": warnings, "diagnostics": diagnostics, "output": output}))
        }
        "xcode_scheme_manager" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let action = req_str(&args, "action", name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(120);
            match action.as_str() {
                "list" => {
                    let (exit_code, output) = g3_run(
                        state,
                        &thread_id,
                        &cwd,
                        &[
                            "xcodebuild".to_owned(),
                            "-list".to_owned(),
                            "-json".to_owned(),
                        ],
                        timeout,
                    )?;
                    g3_missing_cli("xcodebuild", exit_code, &output)?;
                    if exit_code != 0 {
                        return Ok(json!({"action": action, "schemes": [], "exitCode": exit_code, "output": output}));
                    }
                    let listed = g3_parse_json(&output, name)?;
                    let (schemes, _, _, _) = g3_xcodebuild_list(&listed);
                    Ok(json!({"action": action, "schemes": schemes, "exitCode": exit_code, "output": output}))
                }
                "validate" => {
                    let scheme = match opt_str(&args, "scheme") {
                        Some(scheme) => scheme,
                        None => {
                            return Err(failed(
                                "Tool \"xcode_scheme_manager\" is missing required argument \"scheme\".",
                            ));
                        }
                    };
                    g3_token(&scheme, "scheme", name)?;
                    let (exit_code, output) = g3_run(
                        state,
                        &thread_id,
                        &cwd,
                        &[
                            "xcodebuild".to_owned(),
                            "-scheme".to_owned(),
                            scheme.clone(),
                            "-showBuildSettings".to_owned(),
                        ],
                        timeout,
                    )?;
                    g3_missing_cli("xcodebuild", exit_code, &output)?;
                    let settings = g3_build_settings(&output);
                    let settings_count: usize = settings
                        .iter()
                        .map(|section| {
                            section["settings"]
                                .as_object()
                                .map(|object| object.len())
                                .unwrap_or(0)
                        })
                        .sum();
                    Ok(json!({"action": action, "scheme": scheme, "valid": exit_code == 0, "settingsCount": settings_count, "exitCode": exit_code, "output": output}))
                }
                _ => Err(failed("xcode_scheme_manager action must be list or validate.")),
            }
        }
        "xcode_build_settings_inspector" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let key = req_str(&args, "key", name)?;
            g3_token(&key, "key", name)?;
            let mut argv: Vec<String> =
                vec!["xcodebuild".to_owned(), "-showBuildSettings".to_owned()];
            if let Some(scheme) = opt_str(&args, "scheme") {
                g3_token(&scheme, "scheme", name)?;
                argv.push("-scheme".to_owned());
                argv.push(scheme);
            }
            if let Some(configuration) = opt_str(&args, "configuration") {
                g3_token(&configuration, "configuration", name)?;
                argv.push("-configuration".to_owned());
                argv.push(configuration);
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(120);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("xcodebuild", exit_code, &output)?;
            let sections = g3_build_settings(&output);
            let mut values: Vec<Value> = Vec::new();
            for section in sections {
                if let Some(value) = section["settings"][key.as_str()].as_str() {
                    values.push(json!({"target": section["target"].as_str().unwrap_or(""), "value": value}));
                }
            }
            let found = !values.is_empty();
            Ok(json!({"key": key, "values": values, "found": found, "exitCode": exit_code, "output": output}))
        }
        "xcode_device_destination_finder" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let mut argv: Vec<String> =
                vec!["xcodebuild".to_owned(), "-showdestinations".to_owned()];
            if let Some(scheme) = opt_str(&args, "scheme") {
                g3_token(&scheme, "scheme", name)?;
                argv.push("-scheme".to_owned());
                argv.push(scheme);
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(120);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("xcodebuild", exit_code, &output)?;
            let destinations = g3_destinations(&output);
            Ok(json!({"destinations": destinations, "exitCode": exit_code, "output": output}))
        }
        "simulator_list" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(60);
            let (exit_code, output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &[
                    "xcrun".to_owned(),
                    "simctl".to_owned(),
                    "list".to_owned(),
                    "-j".to_owned(),
                    "devices".to_owned(),
                ],
                timeout,
            )?;
            g3_missing_cli("simctl", exit_code, &output)?;
            if exit_code != 0 {
                return Ok(json!({"devices": [], "runtimes": [], "exitCode": exit_code, "output": output}));
            }
            let listed = g3_parse_json(&output, name)?;
            let devices = g3_simctl_devices(&listed);
            let mut runtimes: Vec<String> = devices
                .iter()
                .filter_map(|d| d["runtime"].as_str().map(str::to_owned))
                .collect();
            runtimes.sort();
            runtimes.dedup();
            Ok(json!({"devices": devices, "runtimes": runtimes, "exitCode": exit_code, "output": output}))
        }
        "simulator_boot" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let device = req_str(&args, "device", name)?;
            g3_token(&device, "device", name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(120);
            let (exit_code, output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &[
                    "xcrun".to_owned(),
                    "simctl".to_owned(),
                    "boot".to_owned(),
                    device.clone(),
                ],
                timeout,
            )?;
            g3_missing_cli("simctl", exit_code, &output)?;
            Ok(json!({"booted": exit_code == 0, "device": device, "exitCode": exit_code, "output": output}))
        }
        "simulator_controller" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let action = req_str(&args, "action", name)?;
            let device = req_str(&args, "device", name)?;
            g3_token(&device, "device", name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(120);
            match action.as_str() {
                "boot" | "shutdown" | "erase" => {
                    let (exit_code, output) = g3_run(
                        state,
                        &thread_id,
                        &cwd,
                        &[
                            "xcrun".to_owned(),
                            "simctl".to_owned(),
                            action.clone(),
                            device.clone(),
                        ],
                        timeout,
                    )?;
                    g3_missing_cli("simctl", exit_code, &output)?;
                    Ok(json!({"action": action, "device": device, "succeeded": exit_code == 0, "exitCode": exit_code, "output": output}))
                }
                "openurl" => {
                    let url = match opt_str(&args, "url") {
                        Some(url) => url,
                        None => {
                            return Err(failed(
                                "simulator_controller openurl requires a url with a scheme.",
                            ));
                        }
                    };
                    let has_scheme = url.contains("://") || url.contains(':');
                    if !has_scheme {
                        return Err(failed(
                            "simulator_controller openurl requires a url with a scheme.",
                        ));
                    }
                    let (exit_code, output) = g3_run(
                        state,
                        &thread_id,
                        &cwd,
                        &[
                            "xcrun".to_owned(),
                            "simctl".to_owned(),
                            "openurl".to_owned(),
                            device.clone(),
                            url,
                        ],
                        timeout,
                    )?;
                    g3_missing_cli("simctl", exit_code, &output)?;
                    Ok(json!({"action": action, "device": device, "opened": exit_code == 0, "exitCode": exit_code, "output": output}))
                }
                "status" => {
                    let (exit_code, output) = g3_run(
                        state,
                        &thread_id,
                        &cwd,
                        &[
                            "xcrun".to_owned(),
                            "simctl".to_owned(),
                            "list".to_owned(),
                            "-j".to_owned(),
                            "devices".to_owned(),
                        ],
                        timeout,
                    )?;
                    g3_missing_cli("simctl", exit_code, &output)?;
                    if exit_code != 0 {
                        return Ok(json!({"action": action, "device": device, "state": Value::Null, "found": false, "exitCode": exit_code, "output": output}));
                    }
                    let listed = g3_parse_json(&output, name)?;
                    let devices = g3_simctl_devices(&listed);
                    let found = devices.iter().find(|d| {
                        d["udid"].as_str() == Some(device.as_str())
                            || d["name"].as_str() == Some(device.as_str())
                    });
                    Ok(json!({"action": action, "device": device, "state": found.map(|d| d["state"].clone()).unwrap_or(Value::Null), "found": found.is_some(), "exitCode": exit_code, "output": output}))
                }
                _ => Err(failed(
                    "simulator_controller action must be boot, shutdown, erase, openurl, or status.",
                )),
            }
        }
        "device_list" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(60);
            let (devicectl_exit, devicectl_output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &[
                    "xcrun".to_owned(),
                    "devicectl".to_owned(),
                    "list".to_owned(),
                    "devices".to_owned(),
                ],
                timeout,
            )?;
            let mut source = "devicectl";
            let mut exit_code = devicectl_exit;
            let mut output = devicectl_output;
            if devicectl_exit == 127
                || output.contains("command not found")
                || output.contains("unable to find utility")
            {
                source = "xctrace";
                let (xctrace_exit, xctrace_output) = g3_run(
                    state,
                    &thread_id,
                    &cwd,
                    &[
                        "xcrun".to_owned(),
                        "xctrace".to_owned(),
                        "list".to_owned(),
                        "devices".to_owned(),
                    ],
                    timeout,
                )?;
                g3_missing_cli("xctrace", xctrace_exit, &xctrace_output)?;
                exit_code = xctrace_exit;
                output = xctrace_output;
            }
            let line_count = output.lines().filter(|line| !line.trim().is_empty()).count();
            Ok(json!({"source": source, "exitCode": exit_code, "lineCount": line_count, "output": output}))
        }
        "provisioning_check" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let profile_path = req_str(&args, "profilePath", name)?;
            g3_relative_path(&profile_path, name)?;
            if !profile_path.ends_with(".mobileprovision")
                && !profile_path.ends_with(".provisionprofile")
            {
                return Err(failed(
                    "provisioning_check profilePath must end in .mobileprovision or .provisionprofile.",
                ));
            }
            if !workspace_file_exists(&cwd, &profile_path)? {
                return Err(failed(format!("No such file: {profile_path}.")));
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(60);
            let command = format!(
                "security cms -D -i {} | plutil -convert json -o - -",
                shell_quote(&profile_path)
            );
            let (exit_code, output) =
                run_shell_status(state, &thread_id, &cwd, &command, timeout)?;
            g3_missing_cli("security", exit_code, &output)?;
            if exit_code != 0 {
                return Ok(json!({"valid": false, "exitCode": exit_code, "output": output}));
            }
            let profile = g3_parse_json(&output, name)?;
            let (_, now_output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &[
                    "date".to_owned(),
                    "-u".to_owned(),
                    "+%Y-%m-%dT%H:%M:%SZ".to_owned(),
                ],
                30,
            )?;
            let now = now_output.trim().to_owned();
            let expiration = profile["ExpirationDate"].as_str().unwrap_or("").to_owned();
            let expired = !expiration.is_empty() && !now.is_empty() && expiration.as_str() < now.as_str();
            let entitlement_keys: Vec<String> = profile["Entitlements"]
                .as_object()
                .map(|object| {
                    let mut keys: Vec<String> = object.keys().cloned().collect();
                    keys.sort();
                    keys
                })
                .unwrap_or_default();
            Ok(json!({"valid": true, "name": profile["Name"].as_str().unwrap_or(""), "uuid": profile["UUID"].as_str().unwrap_or(""), "teamIdentifier": profile["TeamIdentifier"].as_array().and_then(|items| items.first()).and_then(Value::as_str).unwrap_or(""), "expirationDate": expiration, "expired": expired, "entitlementKeys": entitlement_keys, "exitCode": exit_code}))
        }
        "swift_package_manager" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let action = req_str(&args, "action", name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(300);
            match action.as_str() {
                "describe" => {
                    let (exit_code, output) = g3_run(
                        state,
                        &thread_id,
                        &cwd,
                        &[
                            "swift".to_owned(),
                            "package".to_owned(),
                            "describe".to_owned(),
                            "--type".to_owned(),
                            "json".to_owned(),
                        ],
                        timeout,
                    )?;
                    g3_missing_cli("swift", exit_code, &output)?;
                    if exit_code != 0 {
                        return Ok(json!({"action": action, "description": Value::Null, "exitCode": exit_code, "output": output}));
                    }
                    let described = g3_parse_json(&output, name)?;
                    Ok(json!({"action": action, "description": described, "exitCode": exit_code, "output": output}))
                }
                "resolve" => {
                    let (exit_code, output) = g3_run(
                        state,
                        &thread_id,
                        &cwd,
                        &["swift".to_owned(), "package".to_owned(), "resolve".to_owned()],
                        timeout,
                    )?;
                    g3_missing_cli("swift", exit_code, &output)?;
                    Ok(json!({"action": action, "resolved": exit_code == 0, "exitCode": exit_code, "output": output}))
                }
                "clean" => {
                    let (exit_code, output) = g3_run(
                        state,
                        &thread_id,
                        &cwd,
                        &["swift".to_owned(), "package".to_owned(), "clean".to_owned()],
                        timeout,
                    )?;
                    g3_missing_cli("swift", exit_code, &output)?;
                    Ok(json!({"action": action, "cleaned": exit_code == 0, "exitCode": exit_code, "output": output}))
                }
                "reset" => {
                    if !opt_bool(&args, "confirm").unwrap_or(false) {
                        return Err(failed(
                            "swift_package_manager reset removes the package build state; pass confirm=true.",
                        ));
                    }
                    let (exit_code, output) = g3_run(
                        state,
                        &thread_id,
                        &cwd,
                        &["swift".to_owned(), "package".to_owned(), "reset".to_owned()],
                        timeout,
                    )?;
                    g3_missing_cli("swift", exit_code, &output)?;
                    Ok(json!({"action": action, "reset": exit_code == 0, "exitCode": exit_code, "output": output}))
                }
                _ => Err(failed(
                    "swift_package_manager action must be describe, resolve, clean, or reset.",
                )),
            }
        }
        "package_dependency_update" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let mut argv: Vec<String> =
                vec!["swift".to_owned(), "package".to_owned(), "update".to_owned()];
            if let Some(package) = opt_str(&args, "package") {
                g3_identifier(&package, "package", name)?;
                argv.push(package);
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(300);
            let (exit_code, output) = g3_run(state, &thread_id, &cwd, &argv, timeout)?;
            g3_missing_cli("swift", exit_code, &output)?;
            let package = opt_str(&args, "package")
                .map(Value::String)
                .unwrap_or(Value::Null);
            Ok(json!({"updated": exit_code == 0, "package": package, "exitCode": exit_code, "output": output}))
        }
        "code_signing_diagnose" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            g3_relative_path(&path, name)?;
            if !workspace_file_exists(&cwd, &path)? {
                return Err(failed(format!("No such file: {path}.")));
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(60);
            let (verify_exit, verify_output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &[
                    "codesign".to_owned(),
                    "--verify".to_owned(),
                    "--verbose".to_owned(),
                    path.clone(),
                ],
                timeout,
            )?;
            g3_missing_cli("codesign", verify_exit, &verify_output)?;
            let (dv_exit, dv_output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &[
                    "codesign".to_owned(),
                    "-dv".to_owned(),
                    "--verbose=4".to_owned(),
                    path.clone(),
                ],
                timeout,
            )?;
            let details = g3_codesign(&dv_output);
            Ok(json!({"path": path, "verified": verify_exit == 0, "verifyExitCode": verify_exit, "verifyOutput": verify_output, "details": details, "exitCode": dv_exit}))
        }
        "xcode_toolchain_info" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(60);
            let (version_exit, version_output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &["xcodebuild".to_owned(), "-version".to_owned()],
                timeout,
            )?;
            g3_missing_cli("xcodebuild", version_exit, &version_output)?;
            let (xcode_version, xcode_build) = g3_xcode_version(&version_output);
            let (select_exit, select_output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &["xcode-select".to_owned(), "-p".to_owned()],
                timeout,
            )?;
            Ok(json!({"xcodeVersion": xcode_version, "xcodeBuild": xcode_build, "developerDir": select_output.trim(), "exitCode": version_exit, "selectExitCode": select_exit}))
        }
        "xcresult_parser" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            g3_relative_path(&path, name)?;
            if !path.ends_with(".xcresult") {
                return Err(failed("xcresult_parser path must end in .xcresult."));
            }
            if !workspace_file_exists(&cwd, &path)? {
                return Err(failed(format!("No such file: {path}.")));
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(120);
            let (exit_code, output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &[
                    "xcrun".to_owned(),
                    "xcresulttool".to_owned(),
                    "get".to_owned(),
                    "--format".to_owned(),
                    "json".to_owned(),
                    "--path".to_owned(),
                    path.clone(),
                ],
                timeout,
            )?;
            g3_missing_cli("xcrun", exit_code, &output)?;
            if exit_code != 0 {
                return Ok(json!({"path": path, "result": Value::Null, "topLevelKeys": [], "exitCode": exit_code, "output": output}));
            }
            let result = g3_parse_json(&output, name)?;
            let mut keys: Vec<String> = result
                .as_object()
                .map(|object| object.keys().cloned().collect())
                .unwrap_or_default();
            keys.sort();
            Ok(json!({"path": path, "result": result, "topLevelKeys": keys, "exitCode": exit_code, "output": output}))
        }
        "mach_o_binary_analyzer" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            g3_relative_path(&path, name)?;
            if !workspace_file_exists(&cwd, &path)? {
                return Err(failed(format!("No such file: {path}.")));
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(60);
            let (file_exit, file_output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &["file".to_owned(), path.clone()],
                timeout,
            )?;
            g3_missing_cli("file", file_exit, &file_output)?;
            let (otool_exit, otool_output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &["otool".to_owned(), "-L".to_owned(), path.clone()],
                timeout,
            )?;
            g3_missing_cli("otool", otool_exit, &otool_output)?;
            let (hv_exit, hv_output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &["otool".to_owned(), "-hv".to_owned(), path.clone()],
                timeout,
            )?;
            let libraries = g3_otool_libraries(&otool_output);
            let headers = g3_mach_headers(&hv_output);
            let file_line = file_output.lines().next().unwrap_or("").trim().to_owned();
            Ok(json!({"path": path, "file": file_line, "fileOutput": file_output, "libraries": libraries, "headers": headers, "exitCode": otool_exit, "hvExitCode": hv_exit}))
        }
        "signing_certificate_inspector" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(60);
            let (exit_code, output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &[
                    "security".to_owned(),
                    "find-identity".to_owned(),
                    "-v".to_owned(),
                    "-p".to_owned(),
                    "codesigning".to_owned(),
                ],
                timeout,
            )?;
            g3_missing_cli("security", exit_code, &output)?;
            let identities = g3_identities(&output);
            let count = identities.len();
            Ok(json!({"identities": identities, "count": count, "exitCode": exit_code, "output": output}))
        }
        "provisioning_profile_reader" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let profile_path = req_str(&args, "profilePath", name)?;
            g3_relative_path(&profile_path, name)?;
            if !profile_path.ends_with(".mobileprovision")
                && !profile_path.ends_with(".provisionprofile")
            {
                return Err(failed(
                    "provisioning_profile_reader profilePath must end in .mobileprovision or .provisionprofile.",
                ));
            }
            if !workspace_file_exists(&cwd, &profile_path)? {
                return Err(failed(format!("No such file: {profile_path}.")));
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(60);
            let command = format!(
                "security cms -D -i {} | plutil -convert json -o - -",
                shell_quote(&profile_path)
            );
            let (exit_code, output) =
                run_shell_status(state, &thread_id, &cwd, &command, timeout)?;
            g3_missing_cli("security", exit_code, &output)?;
            if exit_code != 0 {
                return Ok(json!({"profile": Value::Null, "exitCode": exit_code, "output": output}));
            }
            let profile = g3_parse_json(&output, name)?;
            Ok(json!({"profile": profile, "exitCode": exit_code}))
        }
        "swift_ast_inspector" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = req_str(&args, "path", name)?;
            g3_relative_path(&path, name)?;
            if !path.ends_with(".swift") {
                return Err(failed("swift_ast_inspector path must end in .swift."));
            }
            if !workspace_file_exists(&cwd, &path)? {
                return Err(failed(format!("No such file: {path}.")));
            }
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(120);
            let (exit_code, output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &["swiftc".to_owned(), "-dump-ast".to_owned(), path.clone()],
                timeout,
            )?;
            g3_missing_cli("swiftc", exit_code, &output)?;
            let (decl_counts, total) = g3_ast_decl_counts(&output);
            let line_count = output.lines().count();
            Ok(json!({"path": path, "declCounts": decl_counts, "totalDecls": total, "lineCount": line_count, "exitCode": exit_code, "output": output}))
        }
        "binary_size_report" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let cwd = req_str(&args, "cwd", name)?;
            let path = opt_str(&args, "path").unwrap_or_else(|| "build".to_owned());
            g3_relative_path(&path, name)?;
            let top = opt_u64(&args, "top").unwrap_or(20).clamp(1, 100) as usize;
            let entries = read_dir_entries(&cwd, &path, true)?;
            let file_count = entries
                .iter()
                .filter(|entry| entry["isDirectory"].as_bool() != Some(true))
                .count();
            let timeout = opt_u64(&args, "timeoutSeconds").unwrap_or(120);
            let (exit_code, output) = g3_run(
                state,
                &thread_id,
                &cwd,
                &["du".to_owned(), "-ak".to_owned(), path.clone()],
                timeout,
            )?;
            g3_missing_cli("du", exit_code, &output)?;
            let mut files: Vec<(String, i64)> = g3_du_sizes(&output)
                .into_iter()
                .filter(|(file_path, _)| file_path != &path)
                .collect();
            files.sort_by(|a, b| b.1.cmp(&a.1));
            let total: i64 = files.iter().map(|(_, size)| size).sum();
            let largest: Vec<Value> = files
                .iter()
                .take(top)
                .map(|(file_path, size)| json!({"path": file_path, "kilobytes": size}))
                .collect();
            Ok(json!({"path": path, "fileCount": file_count, "totalKilobytes": total, "largest": largest, "exitCode": exit_code}))
        }
        "git_review_diff" => {
            let thread_id = req_str(&args, "threadId", name)?;
            let root = session_expected_root(state)?;
            let scope = opt_str(&args, "scope").unwrap_or_else(|| "uncommitted".to_owned());
            if scope != "uncommitted" && scope != "branch" {
                return Err(failed("git_review_diff scope must be uncommitted or branch."));
            }
            let ignore_whitespace = opt_bool(&args, "ignoreWhitespace").unwrap_or(false);
            run_workspace_api_operation(
                state,
                "git.review.diff",
                &thread_id,
                json!({"expectedRoot": root, "scope": scope, "ignoreWhitespace": ignore_whitespace}),
            )
        }
        "search_symbol" => g5_call(state, name, &args),
        "dependency_graph" => g5_call(state, name, &args),
        "source_graph_builder" => g5_call(state, name, &args),
        "semantic_query_engine" => g5_call(state, name, &args),
        "code_summary" => g5_call(state, name, &args),
        "code_lint" => g5_call(state, name, &args),
        "complexity_analysis" => g5_call(state, name, &args),
        "autonomous_review_engine" => g5_call(state, name, &args),
        "runtime_diagnostics_engine" => g5_call(state, name, &args),
        "code_metrics_analyzer" => g5_call(state, name, &args),
        "memory_leak_detector" => g5_call(state, name, &args),
        "dead_code_eliminator" => g5_call(state, name, &args),
        "dead_code_scan" => g5_call(state, name, &args),
        "duplicate_code_scan" => g5_call(state, name, &args),
        "todo_scan" => g5_call(state, name, &args),
        "todo_fixme_scanner" => g5_call(state, name, &args),
        "license_header_check" => g5_call(state, name, &args),
        "api_surface_extract" => g5_call(state, name, &args),
        "access_level_audit" => g5_call(state, name, &args),
        "concurrency_audit" => g5_call(state, name, &args),
        "swift_concurrency_analyzer" => g5_call(state, name, &args),
        "swift_migration_advisor" => g5_call(state, name, &args),
        "security_audit_scanner" => g5_call(state, name, &args),
        "secrets_scan" => g5_call(state, name, &args),
        "network_security_auditor" => g5_call(state, name, &args),
        "permissions_audit" => g5_call(state, name, &args),
        "accessibility_audit" => g5_call(state, name, &args),
        "accessibility_audit_scanner" => g5_call(state, name, &args),
        "interface_simulator" => g5_call(state, name, &args),
        "docstring_generator" => g5_call(state, name, &args),
        "code_snippet_manager" => g5_call(state, name, &args),
        "unused_imports_detector" => g5_call(state, name, &args),
        "force_unwrap_scan" => g5_call(state, name, &args),
        "string_literal_audit" => g5_call(state, name, &args),
        "comment_density_report" => g5_call(state, name, &args),
        "function_size_report" => g5_call(state, name, &args),
        "call_hierarchy" => g5_call(state, name, &args),
        "type_hierarchy" => g5_call(state, name, &args),
        "protocol_conformance_list" => g5_call(state, name, &args),
        "import_graph" => g5_call(state, name, &args),
        "change_impact_estimate" => g5_call(state, name, &args),
        "conflict_marker_scan" => g5_call(state, name, &args),
        "build_log_analyze" => g5_call(state, name, &args),
        "crash_log_parse" => g5_call(state, name, &args),
        "deprecation_usage_scan" => g5_call(state, name, &args),
        "info_plist_audit" => g5_call(state, name, &args),
        "api_endpoint_audit" => g5_call(state, name, &args),
        "color_usage_audit" => g5_call(state, name, &args),
        "strings_file_validate" => g5_call(state, name, &args),
        "entitlements_diff" => g5_call(state, name, &args),
        "pbxproj_lint" => g5_call(state, name, &args),
        "xctest_discovery" => g5_call(state, name, &args),
        "build_settings_diff" => g5_call(state, name, &args),
        "build_phase_scripts_list" => g5_call(state, name, &args),
        "build_configuration_list" => g5_call(state, name, &args),
        "target_dependencies_list" => g5_call(state, name, &args),
        "target_source_list" => g5_call(state, name, &args),
        "workspace_settings_read" => g5_call(state, name, &args),
        "scheme_test_plan_list" => g5_call(state, name, &args),
        "test_log_parse" => g5_call(state, name, &args),
        "test_flaky_detect" => g5_call(state, name, &args),
        "code_comment_extract" => g5_call(state, name, &args),
        "api_docs_coverage" => g5_call(state, name, &args),
        "markdown_link_check" => g5_call(state, name, &args),
        "docs_index_build" => g5_call(state, name, &args),
        "framework_linker_auditor" => g6_call(state, name, &args),
        "string_catalog_migrator" => g6_call(state, name, &args),
        "symbol_reference_graph" => g6_call(state, name, &args),
        "podfile_inspector" => g6_call(state, name, &args),
        "carthage_cartfile_inspector" => g6_call(state, name, &args),
        "package_manifest_read" => g6_call(state, name, &args),
        "package_dependency_add" => g6_call(state, name, &args),
        "asset_catalog_list" => g6_call(state, name, &args),
        "asset_image_add" => g6_call(state, name, &args),
        "strings_localization" => g6_call(state, name, &args),
        "localization_audit" => g6_call(state, name, &args),
        "localize_app" => g6_call(state, name, &args),
        "asset_catalog_manager" => g6_call(state, name, &args),
        "localization_manager" => g6_call(state, name, &args),
        "entitlements_manager" => g6_call(state, name, &args),
        "colorset_builder" => g6_call(state, name, &args),
        "project_entitlements" => g6_call(state, name, &args),
        "project_info_plist" => g6_call(state, name, &args),
        "project_capabilities" => g6_call(state, name, &args),
        "entry_points_discover" => g6_call(state, name, &args),
        "repo_overview" => g6_call(state, name, &args),
        "project_structure_map" => g6_call(state, name, &args),
        "recent_changes" => g6_call(state, name, &args),
        "readme_locate" => g6_call(state, name, &args),
        "dependency_licenses" => g6_call(state, name, &args),
        "stale_files_report" => g6_call(state, name, &args),
        "file_type_breakdown" => g6_call(state, name, &args),
        "empty_dirs_find" => g6_call(state, name, &args),
        "symlink_audit" => g6_call(state, name, &args),
        "executable_files_scan" => g6_call(state, name, &args),
        "dir_size_report" => g6_call(state, name, &args),
        "image_asset_size_report" => g6_call(state, name, &args),
        "bundle_resource_auditor" => g6_call(state, name, &args),
        "core_data_model_inspector" => g6_call(state, name, &args),
        "swift_data_schema_auditor" => g6_call(state, name, &args),
        "privacy_manifest_auditor" => g6_call(state, name, &args),
        "build_system_detect" => g6_call(state, name, &args),
        "spm_dependency_tree" => g6_terminal_call(state, name, &args),
        "package_manifest_validate" => g6_terminal_call(state, name, &args),
        "package_dependency_audit" => g6_terminal_call(state, name, &args),
        "project_signing" => g6_terminal_call(state, name, &args),
        "icon_generator_tool" => g6_terminal_call(state, name, &args),
        "process_monitor_tool" => g6_terminal_call(state, name, &args),
        "disk_space_analyzer" => g6_terminal_call(state, name, &args),
        "use_system" => g6_terminal_call(state, name, &args),
        "preflight_checks" => g6_terminal_call(state, name, &args),
        "github_repo" => g6_terminal_call(state, name, &args),
        "env_info" => g6_misc_call(state, name, &args),
        "environment_variable_manager" => g6_misc_call(state, name, &args),
        "clipboard_manager_tool" => g6_misc_call(state, name, &args),
        "system_notification_tool" => g6_misc_call(state, name, &args),
        "search_skills" => g6_misc_call(state, name, &args),
        "plan-AskUser" => g6_misc_call(state, name, &args),
        "tool_capability_lookup" => g6_misc_call(state, name, &args),
        "session_progress_report" => g6_misc_call(state, name, &args),
        "manage_memory" => g6_misc_call(state, name, &args),
        "fetch_documentation" => g6_misc_call(state, name, &args),
        "external_resource_gateway" => g6_misc_call(state, name, &args),
        "read_url_content" => g6_misc_call(state, name, &args),
        "use_app" => g6_misc_call(state, name, &args),
        "derived_data_locate" => g6_misc_call(state, name, &args),

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
        assert_eq!(swift.len(), 326, "Swift registry must hold 326 tools");
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
