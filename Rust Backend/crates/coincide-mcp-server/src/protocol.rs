use anyhow::Result;
use serde_json::{Value, json};

use crate::assets;
use crate::tools;

pub const PROTOCOL_VERSION: &str = "2025-03-26";

fn error_response(id: &Value, code: i64, message: &str) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": {"code": code, "message": message},
    })
}

fn result_response(id: &Value, result: Value) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "result": result,
    })
}

fn text_content(text: String) -> Value {
    json!([{"type": "text", "text": text}])
}

fn tool_result(value: Value) -> Value {
    let text = match &value {
        Value::String(text) => text.clone(),
        _ => serde_json::to_string_pretty(&value).unwrap_or_else(|_| value.to_string()),
    };
    json!({"content": text_content(text), "isError": false})
}

fn tool_error(message: String) -> Value {
    json!({"content": text_content(message), "isError": true})
}

fn initialize_result() -> Value {
    json!({
        "protocolVersion": PROTOCOL_VERSION,
        "capabilities": {
            "tools": {},
            "resources": {},
            "prompts": {},
        },
        "serverInfo": {
            "name": "coincide-mcp-server",
            "version": env!("CARGO_PKG_VERSION"),
        },
    })
}

fn prompts_list() -> Value {
    json!({"prompts": [{
        "name": assets::PROMPT_NAME,
        "description": "The composed Agents system prompt stored for this thread: safeguards, identity, tool routing, and the system tool registry guidance. Read it before using the system tools.",
        "arguments": [],
    }]})
}

pub fn handle(state: &crate::ServerState, request: &Value) -> Option<Value> {
    let Some(method) = request.get("method").and_then(Value::as_str) else {
        let id = request.get("id").cloned().unwrap_or(Value::Null);
        return Some(error_response(&id, -32600, "Request must carry a method string"));
    };
    let is_notification = request.get("id").is_none();
    if is_notification {
        return None;
    }
    let id = request.get("id").cloned().unwrap_or(Value::Null);
    let params = request.get("params").cloned().unwrap_or(Value::Null);
    let result = match method {
        "initialize" => Ok(initialize_result()),
        "ping" => Ok(json!({})),
        "tools/list" => Ok(json!({"tools": tools::list_json()})),
        "tools/call" => call_tool(state, &params),
        "resources/list" => list_resources(state),
        "resources/read" => read_resource(state, &params),
        "prompts/list" => Ok(prompts_list()),
        "prompts/get" => get_prompt(state, &params),
        _ => Err((-32601, format!("Method not found: {method}"))),
    };
    Some(match result {
        Ok(value) => result_response(&id, value),
        Err((code, message)) => error_response(&id, code, &message),
    })
}

fn call_tool(state: &crate::ServerState, params: &Value) -> Result<Value, (i64, String)> {
    let Some(name) = params.get("name").and_then(Value::as_str) else {
        return Err((-32602, "tools/call requires a tool name".to_owned()));
    };
    let arguments = params.get("arguments").cloned().unwrap_or(json!({}));
    if !arguments.is_object() {
        return Err((-32602, "tools/call arguments must be an object".to_owned()));
    }
    match tools::call(state, name, arguments) {
        Ok(value) => Ok(tool_result(value)),
        Err(tools::CallError::UnknownTool(name)) => {
            Err((-32602, format!("Unknown tool \"{name}\"")))
        }
        Err(tools::CallError::Failed(message)) => Ok(tool_error(message)),
    }
}

fn assets_dir(state: &crate::ServerState) -> Result<std::path::PathBuf, (i64, String)> {
    assets::resolve_assets_dir(state.assets_dir.as_deref()).ok_or_else(|| {
        (
            -32602,
            "SystemAssets directory is unavailable; the server cannot list resources".to_owned(),
        )
    })
}

fn list_resources(state: &crate::ServerState) -> Result<Value, (i64, String)> {
    let dir = assets_dir(state)?;
    assets::list_json(&dir).map_err(|error| (-32602, error.to_string()))
}

fn read_resource(state: &crate::ServerState, params: &Value) -> Result<Value, (i64, String)> {
    let Some(uri) = params.get("uri").and_then(Value::as_str) else {
        return Err((-32602, "resources/read requires a uri".to_owned()));
    };
    let dir = assets_dir(state)?;
    assets::read_asset(&dir, uri).map_err(|error| (-32602, error.to_string()))
}

fn get_prompt(state: &crate::ServerState, params: &Value) -> Result<Value, (i64, String)> {
    let Some(name) = params.get("name").and_then(Value::as_str) else {
        return Err((-32602, "prompts/get requires a name".to_owned()));
    };
    if name != assets::PROMPT_NAME {
        return Err((-32602, format!("Unknown prompt \"{name}\"")));
    }
    match assets::stored_system_prompt(state) {
        Ok(Some(prompt)) => Ok(json!({
            "description": "The composed Agents system prompt stored for this thread.",
            "messages": [{
                "role": "user",
                "content": {"type": "text", "text": prompt},
            }],
        })),
        Ok(None) => Err((
            -32602,
            "No system prompt is stored for this thread; read the SystemAssets resources instead"
                .to_owned(),
        )),
        Err(error) => Err((-32602, error.to_string())),
    }
}

pub fn parse_error_response(message: &str) -> Value {
    error_response(&Value::Null, -32700, message)
}

pub fn invalid_request_response(message: &str) -> Value {
    error_response(&Value::Null, -32600, message)
}
