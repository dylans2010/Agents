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

pub fn session_servers_for(mount: Option<&McpMount>, cwd: &Path) -> Result<Value> {
    match mount {
        Some(mount) => session_servers(mount, cwd),
        None => Ok(json!([])),
    }
}

pub fn session_servers(mount: &McpMount, cwd: &Path) -> Result<Value> {
    let (binary, args) = server_command_and_args(cwd, &mount.thread_id, &mount.data_dir)
        .context("System Tools are enabled but the MCP server binary is missing; the session cannot start without it")?;
    Ok(json!([session_entry(&binary, &args)]))
}

pub fn claude_config_path(mount: &McpMount, cwd: &Path) -> Result<Option<PathBuf>> {
    let (binary, args) = server_command_and_args(cwd, &mount.thread_id, &mount.data_dir)
        .context("System Tools are enabled but the MCP server binary is missing; the session cannot start without it")?;
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
    match std::fs::symlink_metadata(&path) {
        Ok(metadata) => {
            ensure!(
                metadata.is_file(),
                "Claude MCP config is not a regular file"
            );
            std::fs::remove_file(&path).context("Replacing Claude MCP config")?;
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
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
    fn session_servers_without_a_mount_is_empty() {
        let dir = PathBuf::from("/tmp");
        assert_eq!(session_servers_for(None, &dir).unwrap(), json!([]));
    }

    #[test]
    fn claude_config_rewrite_replaces_the_previous_turn() {
        struct RestoreEnv(Option<std::ffi::OsString>);
        impl Drop for RestoreEnv {
            fn drop(&mut self) {
                match &self.0 {
                    Some(value) => std::env::set_var(SERVER_ENV_OVERRIDE, value),
                    None => std::env::remove_var(SERVER_ENV_OVERRIDE),
                }
            }
        }
        let dir = tempfile::tempdir().unwrap();
        let binary = dir.path().join("coincide-mcp-server");
        std::fs::write(&binary, "#!/bin/sh\nexit 0\n").unwrap();
        #[cfg(unix)]
        std::fs::set_permissions(
            &binary,
            {
                use std::os::unix::fs::PermissionsExt;
                std::fs::Permissions::from_mode(0o700)
            },
        )
        .unwrap();
        let _restore = RestoreEnv(std::env::var_os(SERVER_ENV_OVERRIDE));
        std::env::set_var(SERVER_ENV_OVERRIDE, &binary);
        let mount = McpMount {
            thread_id: "thread-1".to_owned(),
            data_dir: dir.path().to_path_buf(),
        };
        let first = claude_config_path(&mount, dir.path()).unwrap().unwrap();
        assert!(first.is_file());
        std::fs::write(&first, "stale").unwrap();
        let second = claude_config_path(&mount, dir.path()).unwrap().unwrap();
        assert_eq!(first, second);
        let contents = std::fs::read_to_string(&second).unwrap();
        assert!(contents.contains("mcpServers"));
        assert!(!contents.contains("stale"));
    }

    #[test]
    #[cfg(unix)]
    fn claude_config_symlink_is_refused_and_target_untouched() {
        struct RestoreEnv(Option<std::ffi::OsString>);
        impl Drop for RestoreEnv {
            fn drop(&mut self) {
                match &self.0 {
                    Some(value) => std::env::set_var(SERVER_ENV_OVERRIDE, value),
                    None => std::env::remove_var(SERVER_ENV_OVERRIDE),
                }
            }
        }
        let dir = tempfile::tempdir().unwrap();
        let binary = dir.path().join("coincide-mcp-server");
        std::fs::write(&binary, "#!/bin/sh\nexit 0\n").unwrap();
        std::fs::set_permissions(
            &binary,
            {
                use std::os::unix::fs::PermissionsExt;
                std::fs::Permissions::from_mode(0o700)
            },
        )
        .unwrap();
        let _restore = RestoreEnv(std::env::var_os(SERVER_ENV_OVERRIDE));
        std::env::set_var(SERVER_ENV_OVERRIDE, &binary);
        let mount = McpMount {
            thread_id: "thread-1".to_owned(),
            data_dir: dir.path().to_path_buf(),
        };
        let target = dir.path().join("sentinel.txt");
        std::fs::write(&target, "sentinel").unwrap();
        let config_dir = dir.path().join("mcp");
        std::fs::create_dir_all(&config_dir).unwrap();
        let link = config_dir.join("claude-thread-1.json");
        std::os::unix::fs::symlink(&target, &link).unwrap();
        assert!(claude_config_path(&mount, dir.path()).is_err());
        assert_eq!(std::fs::read_to_string(&target).unwrap(), "sentinel");
        assert!(std::fs::symlink_metadata(&link)
            .unwrap()
            .file_type()
            .is_symlink());
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
