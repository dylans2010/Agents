use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};
use std::{
    io::Write,
    path::{Path, PathBuf},
};

pub const SERVER_NAME: &str = "coincide";
pub const SERVER_BINARY_NAME: &str = "coincide-mcp-server";
pub const SERVER_ENV_OVERRIDE: &str = "COINCIDE_MCP_SERVER";
pub const SYSTEM_ASSETS_ENV_OVERRIDE: &str = "COINCIDE_SYSTEM_ASSETS_DIR";

pub struct McpMount {
    pub thread_id: String,
    pub data_dir: PathBuf,
}

pub fn is_mcp_capable_provider(provider: &str) -> bool {
    !matches!(provider, "codex" | "opencode" | "lithos")
}

pub fn is_executable_file(path: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::metadata(path)
            .is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
    }
    #[cfg(not(unix))]
    {
        std::fs::metadata(path).is_ok_and(|meta| meta.is_file())
    }
}

pub fn server_binary_path() -> Option<PathBuf> {
    if let Some(value) = std::env::var_os(SERVER_ENV_OVERRIDE).filter(|v| !v.is_empty()) {
        let path = PathBuf::from(value);
        return is_executable_file(&path).then_some(path);
    }
    let exe = std::env::current_exe().ok()?;
    let candidate = exe.parent()?.join(SERVER_BINARY_NAME);
    is_executable_file(&candidate).then_some(candidate)
}

pub fn mount_for(provider: &str, toolset: &Value, thread_id: &str, data_dir: &Path) -> Option<McpMount> {
    if toolset.as_str() != Some("system") {
        return None;
    }
    if !is_mcp_capable_provider(provider) {
        return None;
    }
    Some(McpMount {
        thread_id: thread_id.to_owned(),
        data_dir: data_dir.to_path_buf(),
    })
}

pub fn server_command_and_args(
    cwd: &Path,
    thread_id: &str,
    data_dir: &Path,
) -> Option<(PathBuf, Vec<String>)> {
    let binary = server_binary_path()?;
    let socket = data_dir.join("control.sock");
    Some((
        binary,
        vec![
            "--cwd".to_owned(),
            cwd.display().to_string(),
            "--thread-id".to_owned(),
            thread_id.to_owned(),
            "--socket".to_owned(),
            socket.display().to_string(),
        ],
    ))
}

pub fn session_entry(binary: &Path, args: &[String]) -> Value {
    json!({
        "name": SERVER_NAME,
        "command": binary.display().to_string(),
        "args": args,
    })
}

pub fn session_servers_for(mount: Option<&McpMount>, cwd: &Path) -> Value {
    match mount {
        Some(mount) => session_servers(mount, cwd),
        None => json!([]),
    }
}

pub fn session_servers(mount: &McpMount, cwd: &Path) -> Value {
    match server_command_and_args(cwd, &mount.thread_id, &mount.data_dir) {
        Some((binary, args)) => json!([session_entry(&binary, &args)]),
        None => json!([]),
    }
}

pub fn claude_config_path(mount: &McpMount, cwd: &Path) -> Result<Option<PathBuf>> {
    let Some((binary, args)) = server_command_and_args(cwd, &mount.thread_id, &mount.data_dir)
    else {
        return Ok(None);
    };
    ensure!(
        !mount.thread_id.is_empty()
            && !mount
                .thread_id
                .chars()
                .any(|c| c == '/' || c == '\\' || c == '\0'),
        "Invalid thread ID for MCP config file"
    );
    let dir = mount.data_dir.join("mcp");
    crate::native_file::private_directory(&dir)?;
    let path = dir.join(format!("claude-{}.json", mount.thread_id));
    let config = json!({"mcpServers": {SERVER_NAME: {"command": binary.display().to_string(), "args": args}}});
    let mut file = crate::native_file::create_private_file(&path)?;
    file.write_all(serde_json::to_string(&config)?.as_bytes())
        .context("Writing Claude MCP config")?;
    file.sync_all().context("Syncing Claude MCP config")?;
    Ok(Some(path))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mount_rule_requires_system_toolset_and_mcp_capable_provider() {
        let dir = PathBuf::from("/tmp");
        assert!(mount_for("cursor", &json!("system"), "t1", &dir).is_some());
        assert!(mount_for("grok", &json!("system"), "t1", &dir).is_some());
        assert!(mount_for("antigravity", &json!("system"), "t1", &dir).is_some());
        assert!(mount_for("claude", &json!("system"), "t1", &dir).is_some());
        assert!(mount_for("acp-fx", &json!("system"), "t1", &dir).is_some());
        assert!(mount_for("acp", &json!("system"), "t1", &dir).is_some());
        assert!(mount_for("codex", &json!("system"), "t1", &dir).is_none());
        assert!(mount_for("opencode", &json!("system"), "t1", &dir).is_none());
        assert!(mount_for("lithos", &json!("system"), "t1", &dir).is_none());
        assert!(mount_for("cursor", &json!("provider"), "t1", &dir).is_none());
        assert!(mount_for("cursor", &Value::Null, "t1", &dir).is_none());
    }

    #[test]
    fn session_entry_shape_is_acp_stdio_entry() {
        let entry = session_entry(
            Path::new("/Applications/Agents.app/Contents/MacOS/coincide-mcp-server"),
            &[
                "--cwd".to_owned(),
                "/work".to_owned(),
                "--thread-id".to_owned(),
                "thread-1".to_owned(),
                "--socket".to_owned(),
                "/data/control.sock".to_owned(),
            ],
        );
        assert_eq!(entry["name"], SERVER_NAME);
        assert_eq!(
            entry["command"],
            "/Applications/Agents.app/Contents/MacOS/coincide-mcp-server"
        );
        assert_eq!(
            entry["args"],
            json!([
                "--cwd",
                "/work",
                "--thread-id",
                "thread-1",
                "--socket",
                "/data/control.sock"
            ])
        );
    }
}
