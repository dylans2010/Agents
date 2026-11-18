use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};
use std::io::Read;
use std::path::{Path, PathBuf};

pub const PROMPT_NAME: &str = "agents-system-prompt";

const MAX_ASSET_BYTES: u64 = 16 * 1024 * 1024;

pub fn resolve_assets_dir(explicit: Option<&Path>) -> Option<PathBuf> {
    if let Some(dir) = explicit.filter(|d| is_assets_dir(d)) {
        return Some(dir.to_path_buf());
    }
    if let Some(value) = std::env::var_os(coincide_core::mcp::SYSTEM_ASSETS_ENV_OVERRIDE)
        .filter(|v| !v.is_empty())
    {
        let dir = PathBuf::from(value);
        if is_assets_dir(&dir) {
            return Some(dir);
        }
    }
    let exe = std::env::current_exe().ok()?;
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(macos) = exe.parent() {
        candidates.push(macos.join("../Resources/SystemAssets"));
    }
    let mut ancestor = exe.parent().map(Path::to_path_buf);
    for _ in 0..6 {
        let Some(current) = ancestor else { break };
        candidates.push(current.join("Agents/Resources/SystemAssets"));
        ancestor = current.parent().map(Path::to_path_buf);
    }
    candidates
        .into_iter()
        .find(|dir| is_assets_dir(dir))
        .map(|dir| dir.canonicalize().unwrap_or(dir))
}

fn is_assets_dir(dir: &Path) -> bool {
    dir.is_dir() && dir.join("Safeguards.md").is_file() && dir.join("Identity.md").is_file()
}

pub fn list_asset_names(dir: &Path) -> Result<Vec<String>> {
    let mut names: Vec<String> = Vec::new();
    let entries = std::fs::read_dir(dir)
        .with_context(|| format!("Cannot list SystemAssets directory {}", dir.display()))?;
    for entry in entries {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if entry
            .file_type()
            .map(|kind| kind.is_file())
            .unwrap_or(false)
            && entry
                .path()
                .extension()
                .is_some_and(|ext| ext.eq_ignore_ascii_case("md"))
        {
            names.push(name);
        }
    }
    names.sort();
    Ok(names)
}

pub fn asset_uri(name: &str) -> String {
    format!("agents-asset://{name}")
}

pub fn list_json(dir: &Path) -> Result<Value> {
    let names = list_asset_names(dir)?;
    Ok(json!({"resources": names
        .iter()
        .map(|name| {
            json!({
                "uri": asset_uri(name),
                "name": name,
                "mimeType": "text/markdown",
            })
        })
        .collect::<Vec<Value>>()}))
}

pub fn read_asset_text(dir: &Path, name: &str) -> Result<String> {
    let canonical_dir = dir
        .canonicalize()
        .with_context(|| format!("Cannot resolve SystemAssets directory {}", dir.display()))?;
    let canonical_file = dir
        .join(name)
        .canonicalize()
        .with_context(|| format!("Cannot resolve SystemAsset \"{name}\""))?;
    ensure!(
        canonical_file.starts_with(&canonical_dir),
        "SystemAsset \"{name}\" resolves outside the SystemAssets directory"
    );
    let file = std::fs::File::open(&canonical_file)
        .with_context(|| format!("Cannot read SystemAsset \"{name}\""))?;
    let mut text = String::new();
    file.take(MAX_ASSET_BYTES + 1)
        .read_to_string(&mut text)
        .with_context(|| format!("Cannot read SystemAsset \"{name}\""))?;
    ensure!(
        (text.len() as u64) <= MAX_ASSET_BYTES,
        "SystemAsset \"{name}\" exceeds the 16 MiB limit"
    );
    Ok(text)
}

pub fn read_asset(dir: &Path, uri: &str) -> Result<Value> {
    let name = uri
        .strip_prefix("agents-asset://")
        .context("Resource URI must start with agents-asset://")?;
    ensure!(
        !name.is_empty()
            && name.ends_with(".md")
            && !name.contains('/')
            && !name.contains('\\')
            && !name.contains('\0'),
        "Invalid SystemAsset resource name"
    );
    let names = list_asset_names(dir)?;
    ensure!(
        names.iter().any(|candidate| candidate == name),
        "Unknown SystemAsset resource \"{name}\""
    );
    let text = read_asset_text(dir, name)?;
    Ok(json!({"contents": [{
        "uri": uri,
        "mimeType": "text/markdown",
        "text": text,
    }]}))
}

pub fn stored_system_prompt(state: &crate::ServerState) -> Result<Option<String>> {
    let Some(thread_id) = &state.thread_id else {
        return Ok(None);
    };
    let response = coincide_core::control::request(
        &state.socket,
        &json!({"method": "threads.read", "params": {"threadId": thread_id}}),
    )
    .with_context(|| {
        format!(
            "Cannot reach the Agents engine control socket at {}",
            state.socket.display()
        )
    })?;
    if let Some(error) = response.get("error") {
        bail!(
            "{}",
            error["message"].as_str().unwrap_or("Thread read failed")
        );
    }
    let result = response.get("result").cloned().unwrap_or(Value::Null);
    Ok(result["systemPrompt"]
        .as_str()
        .filter(|prompt| !prompt.trim().is_empty())
        .map(str::to_owned))
}

pub fn stored_allowed_tools(state: &crate::ServerState) -> Result<Option<Vec<String>>> {
    let Some(thread_id) = &state.thread_id else {
        return Ok(None);
    };
    let response = coincide_core::control::request(
        &state.socket,
        &json!({"method": "threads.read", "params": {"threadId": thread_id}}),
    )
    .with_context(|| {
        format!(
            "Cannot reach the Agents engine control socket at {}",
            state.socket.display()
        )
    })?;
    if let Some(error) = response.get("error") {
        bail!(
            "{}",
            error["message"].as_str().unwrap_or("Thread read failed")
        );
    }
    let result = response.get("result").cloned().unwrap_or(Value::Null);
    Ok(result["allowedTools"]
        .as_array()
        .map(|names| {
            names
                .iter()
                .filter_map(|name| name.as_str().map(str::to_owned))
                .collect::<Vec<_>>()
        })
        .filter(|names| !names.is_empty()))
}
pub static READ_ONLY_DENIED_TOOLS: &[&str] = &[
        "asset_catalog_manager", "asset_image_add", "automated_repair_engine", "batch_rename_files",
        "binary_plist_converter", "cancel_worker", "click", "click_point",
        "clipboard_manager_tool", "code_format", "code_generate", "code_insert",
        "code_multi_edit", "code_mutation_engine", "code_replace", "code_snippet_manager",
        "colorset_builder", "compiler_diagnostics_engine", "context_persistence_store", "copy_file",
        "create_artifact", "create_directory", "create_file", "create_terminal",
        "csv_to_json", "dead_code_eliminator", "delete_artifact", "delete_directory",
        "delete_file", "delete_worker", "dependency_resolution_engine", "dir_create",
        "dir_delete", "docc_build", "docs_generate", "double_click",
        "drag", "edit_file", "entitlements_manager", "env_capture_logs",
        "execution_plan", "file_append", "file_backup", "file_copy",
        "file_create", "file_delete", "file_move", "file_rename",
        "file_write", "format_json_file", "generate_xcodeproj", "git_bisect",
        "git_branch_checkout", "git_branch_create", "git_branch_manager", "git_cherry_pick",
        "git_commit", "git_conflict_resolver", "git_pull", "git_push",
        "git_stash_operator", "gzip_compress_file", "gzip_decompress_file", "hotkey",
        "image_convert_format", "image_decode_base64", "image_generate_thumbnail", "import_cleanup",
        "intel_breakdown_task", "intel_generate_tests", "intel_plan_task", "invoke_menu",
        "json_to_csv", "json_to_plist", "json_validate", "launch_app",
        "localization_manager", "localize_app", "manage_memory", "markdown_toc_generate",
        "mem_clear", "mem_context_snapshot", "mem_delete", "mem_store",
        "move_cursor", "move_file", "multi_edit_file", "package_dependency_add",
        "package_dependency_update", "patch_application_engine", "performance_benchmark", "plist_edit",
        "plist_editor", "plist_to_json", "preflight_checks", "press_key",
        "project_archive", "project_build", "project_clean", "project_restore",
        "project_snapshot", "project_test", "read_terminal", "readme_generate",
        "regex_replace_in_files", "report_to_user", "right_click", "run_build",
        "run_command", "run_tests", "safe_undo", "save_to_memory",
        "scroll", "session_export", "set_value", "set_window_frame",
        "simulator_boot", "simulator_controller", "start_subagent", "string_catalog_migrator",
        "strings_localization", "svg_to_png", "swift_format_lint", "swift_package_manager",
        "symbol_move_file", "symbol_rename_project", "system_notification_tool", "tar_archive_create",
        "tar_archive_extract", "test_data_factory", "test_run_single", "test_snapshot_manage",
        "type_text", "ui_test_scaffold", "unzip_file", "use_app",
        "use_terminal", "use_workers", "version_control_operator", "write_file",
        "write_terminal", "yaml_validate", "zip_file",
];

pub static APPROVAL_REQUIRED_DENIED_TOOLS: &[&str] = &[
        "compiler_diagnostics_engine", "create_terminal", "delete_artifact", "delete_directory",
        "delete_file", "delete_worker", "dependency_resolution_engine", "dir_delete",
        "docc_build", "file_delete", "generate_xcodeproj", "git_bisect",
        "git_branch_checkout", "git_branch_create", "git_branch_manager", "git_cherry_pick",
        "git_commit", "git_conflict_resolver", "git_pull", "git_push",
        "git_stash_operator", "manage_memory", "mem_clear", "mem_delete",
        "package_dependency_update", "performance_benchmark", "project_archive", "project_build",
        "project_clean", "project_restore", "project_snapshot", "project_test",
        "read_terminal", "run_build", "run_command", "run_tests",
        "safe_undo", "simulator_boot", "simulator_controller", "swift_package_manager",
        "test_run_single", "test_snapshot_manage", "use_terminal", "version_control_operator",
        "write_terminal",
];

pub enum ThreadProfile {
    Unbound,
    NoAssistant,
    Known(String),
    UnknownAssistant,
}

pub fn tool_denied_by_profile(profile: &str, tool: &str) -> bool {
    match profile {
        "read-only" => READ_ONLY_DENIED_TOOLS.contains(&tool),
        "approval-required" => APPROVAL_REQUIRED_DENIED_TOOLS.contains(&tool),
        "workspace-modify" | "terminal" => false,
        _ => true,
    }
}

pub fn thread_profile_allows(profile: &ThreadProfile, tool: &str) -> bool {
    match profile {
        ThreadProfile::Unbound | ThreadProfile::UnknownAssistant => false,
        ThreadProfile::NoAssistant => true,
        ThreadProfile::Known(profile) => !tool_denied_by_profile(profile, tool),
    }
}

pub fn stored_thread_profile(state: &crate::ServerState) -> Result<ThreadProfile> {
    let Some(thread_id) = &state.thread_id else {
        return Ok(ThreadProfile::Unbound);
    };
    let response = coincide_core::control::request(
        &state.socket,
        &json!({"method": "threads.read", "params": {"threadId": thread_id}}),
    )
    .with_context(|| {
        format!(
            "Cannot reach the Agents engine control socket at {}",
            state.socket.display()
        )
    })?;
    if let Some(error) = response.get("error") {
        bail!(
            "{}",
            error["message"].as_str().unwrap_or("Thread read failed")
        );
    }
    let result = response.get("result").cloned().unwrap_or(Value::Null);
    let Some(assistant_id) = result["assistantId"]
        .as_str()
        .filter(|id| !id.is_empty())
    else {
        return Ok(ThreadProfile::NoAssistant);
    };
    let response = coincide_core::control::request(
        &state.socket,
        &json!({"method": "assistants.list", "params": {}}),
    )
    .with_context(|| {
        format!(
            "Cannot reach the Agents engine control socket at {}",
            state.socket.display()
        )
    })?;
    if let Some(error) = response.get("error") {
        bail!(
            "{}",
            error["message"].as_str().unwrap_or("Assistant list failed")
        );
    }
    let result = response.get("result").cloned().unwrap_or(Value::Null);
    let found = result["assistants"].as_array().and_then(|assistants| {
        assistants
            .iter()
            .find(|assistant| assistant["id"].as_str() == Some(assistant_id))
    });
    let Some(assistant) = found else {
        return Ok(ThreadProfile::UnknownAssistant);
    };
    Ok(ThreadProfile::Known(
        assistant["permissionProfile"]
            .as_str()
            .filter(|profile| !profile.is_empty())
            .unwrap_or("read-only")
            .to_owned(),
    ))
}
