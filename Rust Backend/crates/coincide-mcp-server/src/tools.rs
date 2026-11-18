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
        _ => Err(CallError::UnknownTool(name.to_owned())),
    }
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
        assert_eq!(swift.len(), 26, "Swift registry must hold 26 tools");
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
