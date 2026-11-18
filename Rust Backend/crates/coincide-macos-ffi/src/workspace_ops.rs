//! Desktop operations: terminal viewport, workspace files/search/read/write,
//! agent instructions, attachment staging, permanent thread deletion + undo,
//! schedule approval, project scripts, usage dashboard, remote server control,
//! and legacy store migration.
use crate::{CoincideMacOSRuntime, discovery, providers};
use anyhow::{Context, Result, bail, ensure};
use base64::Engine as _;
use chrono::{TimeZone, Utc};
use coincide_core::{
    attachments,
    native_file,
    project_scripts::{self, ScriptDraft, ScriptIcon},
    remote::{
        crypto::display_fingerprint,
        qr,
        server::{RemoteServer, Snapshot as RemoteSnapshot, Status as RemoteStatus},
    },
    store::ScriptEdit,
    terminal::Palette,
    usage_report::{self, Totals},
};
use serde_json::{Value, json};
use std::{
    collections::{HashSet, VecDeque},
    fs::{self, OpenOptions},
    io::{Read, Seek, SeekFrom, Write},
    os::unix::fs::OpenOptionsExt,
    path::{Component, Path, PathBuf},
    sync::{Arc, Mutex},
};
use uuid::Uuid;

const MAX_INSTRUCTION_BYTES: usize = 1024 * 1024;

pub fn dispatch_desktop_action(runtime: &CoincideMacOSRuntime, raw_json: &str) -> Result<Value> {
    let parsed: Value =
        serde_json::from_str(raw_json).context("Desktop action request must be valid JSON")?;
    ensure!(
        parsed.is_object(),
        "Desktop action request must be a JSON object"
    );

    let action = parsed
        .get("action")
        .and_then(Value::as_str)
        .or_else(|| parsed.get("type").and_then(Value::as_str))
        .or_else(|| parsed.get("method").and_then(Value::as_str))
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .context("Desktop action JSON requires an 'action' (or 'type'/'method') string")?
        .to_owned();

    if action == "engine.rpc" {
        return engine_rpc(runtime, &parsed);
    }

    let params = extract_params(&parsed);

    match action.as_str() {
        "providers.list_all" => providers::list_all_providers(runtime),
        "providers.save_config" => providers::save_provider_config(runtime, &params),
        "providers.check" => providers::check_provider(runtime, &params),
        "providers.create_key_account" => providers::create_key_account(runtime, &params),
        "providers.update_account_key" => providers::update_account_key(runtime, &params),
        "providers.rename_key_account" => providers::rename_key_account(runtime, &params),
        "providers.delete_account" => providers::delete_account(runtime, &params),
        "providers.create_login_account" => providers::create_login_account(runtime, &params),
        "providers.select_account" => providers::select_thread_account(runtime, &params),
        "providers.acp_registry" => providers::acp_registry_view(runtime, &params),
        "providers.register_acp" => providers::register_acp_agent(runtime, &params),
        "models.catalog" => providers::models_catalog(runtime, &params),
        "models.set_preference" => providers::set_model_preference(runtime, &params),
        "terminal.viewport" => terminal_viewport(runtime, &params),
        "workspace.files" => workspace_files(&params),
        "workspace.search" => workspace_search(&params),
        "workspace.search_regex" => workspace_search_regex(&params),
        "workspace.read_file" => workspace_read_file(&params),
        "workspace.write_file" => workspace_write_file(&params),
        "workspace.delete_file" => workspace_delete_file(&params),
        "workspace.delete_directory" => workspace_delete_directory(&params),
        "workspace.move_file" => workspace_move_file(&params),
        "workspace.copy_file" => workspace_copy_file(&params),
        "workspace.create_dir" => workspace_create_dir(&params),
        "workspace.read_dir" => workspace_read_dir(&params),
        "workspace.edit_file" => workspace_edit_file(&params),
        "instructions.list" => instructions_list(runtime, &params),
        "instructions.read" => instructions_read(runtime, &params),
        "instructions.save" => instructions_save(runtime, &params),
        "attachments.stage" => attachments_stage(runtime, &params),
        "threads.delete_permanent" => threads_delete_permanent(runtime, &params),
        "threads.undo_delete" => threads_undo_delete(runtime, &params),
        "schedules.approve" => schedules_approve(runtime, &params),
        "projects.scripts.save" => projects_scripts_save(runtime, &params),
        "usage.dashboard" => usage_dashboard(runtime, &params),
        "remote.status" => remote_status(runtime),
        "remote.set_enabled" => remote_set_enabled(runtime, &params),
        "remote.begin_pairing" => remote_begin_pairing(runtime),
        "remote.cancel_pairing" => remote_cancel_pairing(runtime),
        "remote.revoke_device" => remote_revoke_device(runtime, &params),
        "remote.reset_identity" => remote_reset_identity(runtime),
        "store.import_legacy" => {
            let source_dir = str_param(&params, &["sourceDir", "source"]);
            discovery::import_legacy_store(&runtime.engine, &runtime.data_dir, source_dir)
        }
        // Direct pass-through for any Engine RPC method (e.g. `terminal.create`, `terminal.write`,
        // `projects.create`, `threads.create`, `settings.read`, etc.)
        other => dispatch_engine_method(runtime, other, params),
    }
}

fn extract_params(envelope: &Value) -> Value {
    let mut merged = serde_json::Map::new();
    if let Some(obj) = envelope.as_object() {
        for (k, v) in obj {
            if !matches!(k.as_str(), "action" | "type" | "params" | "body") {
                merged.insert(k.clone(), v.clone());
            }
        }
    }
    for nested_key in ["body", "params"] {
        if let Some(obj) = envelope.get(nested_key).and_then(Value::as_object) {
            for (k, v) in obj {
                merged.insert(k.clone(), v.clone());
            }
        }
    }
    Value::Object(merged)
}

fn str_param<'a>(params: &'a Value, keys: &[&str]) -> Option<&'a str> {
    keys.iter()
        .find_map(|key| params.get(*key).and_then(Value::as_str))
}

fn req_str<'a>(params: &'a Value, keys: &[&str], label: &str) -> Result<&'a str> {
    str_param(params, keys)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .with_context(|| format!("Missing required parameter '{label}'"))
}

fn engine_rpc(runtime: &CoincideMacOSRuntime, envelope: &Value) -> Result<Value> {
    // Support both `{"action": "engine.rpc", "method": "...", "params": {...}}`
    // and `{"action": "engine.rpc", "params": {"method": "...", "params": {...}}}`
    let inner = envelope
        .get("params")
        .filter(|p| p.is_object() && p.get("method").is_some())
        .or_else(|| {
            envelope
                .get("body")
                .filter(|b| b.is_object() && b.get("method").is_some())
        });
    let (method, rpc_params) = if let Some(inner) = inner {
        let m = inner["method"]
            .as_str()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .context("engine.rpc requires a 'method' string")?;
        let p = inner
            .get("params")
            .cloned()
            .unwrap_or_else(|| json!({}));
        (m, p)
    } else {
        let m = envelope["method"]
            .as_str()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .context("engine.rpc requires a 'method' string")?;
        let p = envelope
            .get("params")
            .or_else(|| envelope.get("body"))
            .cloned()
            .unwrap_or_else(|| json!({}));
        (m, p)
    };
    dispatch_engine_method(runtime, method, rpc_params)
}

fn dispatch_engine_method(
    runtime: &CoincideMacOSRuntime,
    method: &str,
    params: Value,
) -> Result<Value> {
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    let response = engine.dispatch_desktop(json!({
        "method": method,
        "params": params,
    }));
    if let Some(err) = response.get("error") {
        bail!(
            "{}",
            err["message"]
                .as_str()
                .unwrap_or("Engine RPC command failed")
        );
    }
    Ok(response.get("result").cloned().unwrap_or(Value::Null))
}

fn terminal_viewport(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let id = req_str(params, &["id", "terminalId", "terminalID"], "id")?;
    let dark = params.get("dark").and_then(Value::as_bool).unwrap_or(true);
    let palette = if let Some(custom) = params.get("palette").filter(|p| p.is_object()) {
        Palette::from_value(custom)?
    } else if dark {
        Palette::default()
    } else {
        Palette {
            dark: false,
            foreground: [0x1C, 0x1C, 0x1E],
            background: [0xFF, 0xFF, 0xFF],
        }
    };

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    let mut viewport = engine.read_terminal_viewport(id, &palette)?;

    // Also attach tab metadata (cwd, process, number, exited, exitCode, progress) from `terminal.status`
    let status_resp = engine.dispatch_desktop(json!({
        "method": "terminal.status",
        "params": {},
    }));
    if let Some(entry) = status_resp["result"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|row| row["terminalId"].as_str() == Some(id))
        && let Some(obj) = viewport.as_object_mut()
    {
        obj.insert("terminalId".into(), json!(id));
        obj.insert("dark".into(), json!(palette.dark));
        obj.insert("cursorColor".into(), json!(palette.cursor()));
        for field in [
            "threadId",
            "number",
            "name",
            "cwd",
            "directory",
            "process",
            "running",
            "exited",
            "exitCode",
            "message",
            "progress",
        ] {
            if let Some(v) = entry.get(field)
                && !obj.contains_key(field)
            {
                obj.insert(field.to_owned(), v.clone());
            }
        }
        // Build coalesced styled runs per row for fast CoreText/AttributedString rendering on macOS
        if let Some(grid) = obj.get("grid").and_then(Value::as_array).cloned() {
            let runs = coalesce_styled_runs(&grid);
            obj.insert("runs".into(), Value::Array(runs));
        }
    }

    Ok(viewport)
}

fn coalesce_styled_runs(grid: &[Value]) -> Vec<Value> {
    let mut all_rows = Vec::with_capacity(grid.len());
    for row in grid {
        let Some(cells) = row.as_array() else {
            all_rows.push(json!([]));
            continue;
        };
        let mut row_runs: Vec<Value> = Vec::new();
        let mut current_text = String::new();
        let mut current_style: Option<Value> = None;
        let mut start_col = 0usize;

        for (col, cell) in cells.iter().enumerate() {
            if cell["continuation"] == true {
                continue;
            }
            let style = json!({
                "fg": cell["foreground"],
                "bg": cell["background"],
                "bold": cell["bold"],
                "italic": cell["italic"],
                "underline": cell["underline"],
                "strikethrough": cell["strikethrough"],
                "link": cell["link"],
            });
            let ch = cell["text"].as_str().unwrap_or(" ");
            if current_style.as_ref() == Some(&style) {
                current_text.push_str(ch);
            } else {
                if let Some(prev_style) = current_style.take() {
                    row_runs.push(json!({
                        "col": start_col,
                        "text": std::mem::take(&mut current_text),
                        "fg": prev_style["fg"],
                        "bg": prev_style["bg"],
                        "bold": prev_style["bold"],
                        "italic": prev_style["italic"],
                        "underline": prev_style["underline"],
                        "strikethrough": prev_style["strikethrough"],
                        "link": prev_style["link"],
                    }));
                }
                start_col = col;
                current_text.push_str(ch);
                current_style = Some(style);
            }
        }
        if let Some(prev_style) = current_style {
            row_runs.push(json!({
                "col": start_col,
                "text": current_text,
                "fg": prev_style["fg"],
                "bg": prev_style["bg"],
                "bold": prev_style["bold"],
                "italic": prev_style["italic"],
                "underline": prev_style["underline"],
                "strikethrough": prev_style["strikethrough"],
                "link": prev_style["link"],
            }));
        }
        all_rows.push(Value::Array(row_runs));
    }
    all_rows
}

fn workspace_files(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::files(params)
}

fn workspace_search(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::search(params)
}

fn workspace_search_regex(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::search_regex(params)
}

fn workspace_read_file(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::read_file(params)
}

fn workspace_write_file(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::write_file(params)
}

fn workspace_delete_file(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::delete_file(params)
}

fn workspace_delete_directory(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::delete_directory(params)
}

fn workspace_move_file(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::move_file(params)
}

fn workspace_copy_file(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::copy_file(params)
}

fn workspace_create_dir(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::create_dir(params)
}

fn workspace_read_dir(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::read_dir(params)
}

fn workspace_edit_file(params: &Value) -> Result<Value> {
    coincide_core::workspace_tools::edit_file(params)
}

// MARK: - Instructions Discovery, Read & Save

fn global_instruction_candidates(runtime: &CoincideMacOSRuntime) -> Vec<(String, PathBuf)> {
    let mut list = Vec::new();
    if let Some(home) = discovery::home_dir() {
        list.push(("Codex Global (AGENTS.md)".into(), home.join(".codex/AGENTS.md")));
        list.push(("Claude Global (CLAUDE.md)".into(), home.join(".claude/CLAUDE.md")));
        list.push(("Gemini Global (GEMINI.md)".into(), home.join(".gemini/GEMINI.md")));
        list.push((
            "OpenCode Global (AGENTS.md)".into(),
            home.join(".config/opencode/AGENTS.md"),
        ));
        list.push(("Home AGENTS.md".into(), home.join("AGENTS.md")));
    }
    if let Ok(engine) = runtime.engine.lock() {
        if let Ok(Some(doc)) = engine.store.document("instructions.json")
            && let Some(master) = doc["global"]["masterPath"].as_str()
        {
            let path = PathBuf::from(master);
            if path.is_absolute() && !list.iter().any(|(_, p)| p == &path) {
                list.insert(0, ("Configured Global Master".into(), path));
            }
        }
        if let Ok(homes) = engine.store.native_codex_instruction_homes() {
            for target in homes {
                if let Ok(path) = target.instruction_path(&engine.store)
                    && !list.iter().any(|(_, p)| p == &path)
                {
                    list.push(("Managed Codex Profile (AGENTS.md)".into(), path));
                }
            }
        }
    }
    list
}

fn discover_project_instruction_paths(root: &Path) -> Vec<PathBuf> {
    const ROOT_DEFAULTS: &[&str] = &[
        "AGENTS.md",
        "CLAUDE.md",
        "GEMINI.md",
        ".cursorrules",
        ".github/copilot-instructions.md",
    ];
    const SKIPPED: &[&str] = &[
        "node_modules",
        "build",
        "DerivedData",
        "Pods",
        "Carthage",
        "vendor",
        "dist",
        "venv",
        "target",
        "__pycache__",
        ".build",
        ".venv",
        ".next",
        ".nuxt",
        ".gradle",
    ];

    let mut result: Vec<PathBuf> = ROOT_DEFAULTS.iter().map(|rel| root.join(rel)).collect();
    let mut queue = VecDeque::from([(root.to_path_buf(), 0usize, false)]);
    let mut visited = 0usize;

    while let Some((directory, depth, in_cursor_rules)) = queue.pop_front() {
        if visited >= 4000 || result.len() >= 512 {
            break;
        }
        visited += 1;
        let Ok(entries) = fs::read_dir(&directory) else {
            continue;
        };
        let mut entries = entries.flatten().take(4096).collect::<Vec<_>>();
        entries.sort_by_key(|e| e.file_name());
        for entry in entries {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            let Ok(kind) = entry.file_type() else {
                continue;
            };
            if in_cursor_rules {
                if !kind.is_dir() && path.extension().is_some_and(|e| e == "mdc") {
                    if !result.contains(&path) {
                        result.push(path);
                    }
                } else if depth < 6 && kind.is_dir() && !kind.is_symlink() {
                    queue.push_back((path, depth + 1, true));
                }
                continue;
            }
            if matches!(
                name.as_str(),
                "AGENTS.md"
                    | "CLAUDE.md"
                    | "GEMINI.md"
                    | "AGENTS.override.md"
                    | "CLAUDE.local.md"
                    | ".cursorrules"
            ) && !kind.is_dir()
            {
                if !result.contains(&path) {
                    result.push(path);
                }
                continue;
            }
            if name == ".claude" && kind.is_dir() && !kind.is_symlink() {
                let f = path.join("CLAUDE.md");
                if fs::symlink_metadata(&f).is_ok() && !result.contains(&f) {
                    result.push(f);
                }
                continue;
            }
            if name == ".github" && kind.is_dir() && !kind.is_symlink() {
                let f = path.join("copilot-instructions.md");
                if fs::symlink_metadata(&f).is_ok() && !result.contains(&f) {
                    result.push(f);
                }
                continue;
            }
            if name == ".cursor" && kind.is_dir() && !kind.is_symlink() {
                let rules = path.join("rules");
                if fs::symlink_metadata(&rules)
                    .is_ok_and(|m| m.is_dir() && !m.file_type().is_symlink())
                {
                    queue.push_back((rules, 0, true));
                }
                continue;
            }
            if depth < 5
                && !name.starts_with('.')
                && !SKIPPED.contains(&name.as_str())
                && kind.is_dir()
                && !kind.is_symlink()
            {
                queue.push_back((path, depth + 1, false));
            }
        }
    }
    result
}

fn instruction_entry_meta(path: &Path, scope: &str, label: &str, root: Option<&Path>) -> Value {
    let meta = fs::symlink_metadata(path).ok();
    let exists = meta.is_some();
    let is_symlink = native_file::link_target(path)
        .ok()
        .flatten()
        .is_some();
    let link_target = native_file::link_target(path)
        .ok()
        .flatten()
        .map(|p| p.display().to_string());
    let byte_len = path.metadata().ok().map(|m| m.len()).unwrap_or(0);
    let relative = root
        .and_then(|r| path.strip_prefix(r).ok())
        .and_then(Path::to_str)
        .map(str::to_owned);
    json!({
        "scope": scope,
        "label": label,
        "path": path,
        "relativePath": relative,
        "exists": exists,
        "isSymlink": is_symlink,
        "linkTarget": link_target,
        "byteLen": byte_len,
    })
}

fn is_allowed_instruction_path(
    runtime: &CoincideMacOSRuntime,
    target: &Path,
    cwd: Option<&Path>,
) -> bool {
    if !target.is_absolute() {
        return false;
    }
    if global_instruction_candidates(runtime)
        .iter()
        .any(|(_, candidate)| candidate == target)
    {
        return true;
    }
    let allowed_name = target
        .file_name()
        .and_then(|n| n.to_str())
        .is_some_and(|name| {
            matches!(
                name,
                "AGENTS.md"
                    | "CLAUDE.md"
                    | "GEMINI.md"
                    | "AGENTS.override.md"
                    | "CLAUDE.local.md"
                    | ".cursorrules"
                    | "copilot-instructions.md"
            ) || name.ends_with(".mdc")
        });
    if !allowed_name {
        return false;
    }
    if let Some(cwd) = cwd
        && let Ok(canon_cwd) = cwd.canonicalize()
    {
        if let Ok(canon_parent) = target
            .parent()
            .unwrap_or(Path::new("/"))
            .canonicalize()
            && canon_parent.starts_with(&canon_cwd)
        {
            return true;
        }
        if target.starts_with(cwd) || target.starts_with(&canon_cwd) {
            return true;
        }
    }
    // Also permit files inside any registered project directory in the Store
    if let Ok(engine) = runtime.engine.lock()
        && let Ok(projects) = engine.store.projects()
    {
        for proj in projects.as_array().into_iter().flatten() {
            if let Some(proj_path) = proj["path"].as_str().filter(|s| !s.is_empty()) {
                let p = Path::new(proj_path);
                if target.starts_with(p) {
                    return true;
                }
                if let Ok(canon_p) = p.canonicalize()
                    && let Some(parent) = target.parent()
                    && let Ok(canon_parent) = parent.canonicalize()
                    && canon_parent.starts_with(&canon_p)
                {
                    return true;
                }
            }
        }
    }
    false
}

pub fn instructions_list(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let mut global_rows = Vec::new();
    for (label, path) in global_instruction_candidates(runtime) {
        global_rows.push(instruction_entry_meta(&path, "global", &label, None));
    }

    let mut project_rows = Vec::new();
    if let Some(cwd_raw) = str_param(params, &["cwd", "projectPath"]).filter(|s| !s.is_empty()) {
        let root = PathBuf::from(cwd_raw);
        if root.is_dir() {
            for path in discover_project_instruction_paths(&root) {
                let rel = path
                    .strip_prefix(&root)
                    .ok()
                    .and_then(Path::to_str)
                    .unwrap_or("Instruction");
                project_rows.push(instruction_entry_meta(&path, "project", rel, Some(&root)));
            }
        }
    }

    Ok(json!({
        "global": global_rows,
        "project": project_rows,
    }))
}

pub fn instructions_read(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let cwd = str_param(params, &["cwd", "projectPath"])
        .filter(|s| !s.is_empty())
        .map(PathBuf::from);
    let raw_path = req_str(params, &["path", "relativePath", "filePath"], "path")?;
    let target = resolve_instruction_path(raw_path, cwd.as_deref())?;
    ensure!(
        is_allowed_instruction_path(runtime, &target, cwd.as_deref()),
        "Path is not a recognized global or project instruction file"
    );

    if fs::symlink_metadata(&target)
        .err()
        .is_some_and(|e| e.kind() == std::io::ErrorKind::NotFound)
    {
        if let Ok(mut baselines) = runtime.instruction_baselines.lock() {
            baselines.insert(target.clone(), Vec::new());
        }
        return Ok(json!({
            "path": target,
            "exists": false,
            "content": "",
            "text": "",
            "isSymlink": false,
        }));
    }

    let is_symlink = native_file::link_target(&target)?.is_some();
    let resolved = target
        .canonicalize()
        .context("Instruction target cannot be resolved")?;
    let mut file = native_file::open_regular(&resolved, false)?;
    ensure!(
        file.metadata()?.len() <= MAX_INSTRUCTION_BYTES as u64,
        "Instruction file exceeds 1 MiB"
    );
    let mut bytes = Vec::new();
    Read::by_ref(&mut file)
        .take((MAX_INSTRUCTION_BYTES + 1) as u64)
        .read_to_end(&mut bytes)?;
    ensure!(
        bytes.len() <= MAX_INSTRUCTION_BYTES,
        "Instruction file exceeds 1 MiB"
    );
    let content = String::from_utf8(bytes.clone()).context("Instruction file must be UTF-8")?;
    if let Ok(mut baselines) = runtime.instruction_baselines.lock() {
        baselines.insert(target.clone(), bytes);
    }

    Ok(json!({
        "path": target,
        "resolvedPath": resolved,
        "exists": true,
        "isSymlink": is_symlink,
        "content": content,
        "text": content,
    }))
}

pub fn instructions_save(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let cwd = str_param(params, &["cwd", "projectPath"])
        .filter(|s| !s.is_empty())
        .map(PathBuf::from);
    let raw_path = req_str(params, &["path", "relativePath", "filePath"], "path")?;
    let content = params
        .get("content")
        .or_else(|| params.get("text"))
        .and_then(Value::as_str)
        .context("Missing required string parameter 'content'")?;
    ensure!(
        content.len() <= MAX_INSTRUCTION_BYTES && !content.contains('\0'),
        "Instruction content must be valid UTF-8 up to 1 MiB without NUL bytes"
    );

    let target = resolve_instruction_path(raw_path, cwd.as_deref())?;
    ensure!(
        is_allowed_instruction_path(runtime, &target, cwd.as_deref()),
        "Path is not a recognized global or project instruction file"
    );

    let recovery_dir = runtime.data_dir.join("instruction-recovery");
    native_file::private_directory(&recovery_dir)?;

    if fs::symlink_metadata(&target).is_ok() {
        let resolved = target
            .canonicalize()
            .context("Instruction symlink target could not be resolved")?;
        let mut file = native_file::open_regular(&resolved, true)?;
        let mut current_bytes = Vec::new();
        Read::by_ref(&mut file)
            .take((MAX_INSTRUCTION_BYTES + 1) as u64)
            .read_to_end(&mut current_bytes)?;

        if let Some(expected) = params.get("expectedContent").and_then(Value::as_str) {
            ensure!(
                current_bytes == expected.as_bytes(),
                "Instruction file changed on disk since it was loaded; reload before saving"
            );
        }

        if current_bytes != content.as_bytes() {
            let backup = recovery_dir.join(format!("backup-{}.md", Uuid::new_v4()));
            let mut rec = native_file::create_private_file(&backup)?;
            rec.write_all(&current_bytes)?;
            rec.sync_all()?;

            file.seek(SeekFrom::Start(0))?;
            file.write_all(content.as_bytes())?;
            file.set_len(content.len() as u64)?;
            file.sync_all()?;
        }
    } else {
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)?;
        }
        write_regular_utf8(&target, content.as_bytes())?;
    }

    if let Ok(mut baselines) = runtime.instruction_baselines.lock() {
        baselines.insert(target.clone(), content.as_bytes().to_vec());
    }

    Ok(json!({
        "path": target,
        "saved": true,
        "byteLen": content.len(),
    }))
}

fn resolve_instruction_path(raw: &str, cwd: Option<&Path>) -> Result<PathBuf> {
    if let Some(rest) = raw.strip_prefix("~/") {
        let home = discovery::home_dir().context("HOME is unavailable")?;
        return Ok(home.join(rest));
    }
    let p = Path::new(raw);
    if p.is_absolute() {
        Ok(p.to_path_buf())
    } else if let Some(cwd) = cwd {
        validate_relative_workspace_path(raw)?;
        Ok(cwd.join(p))
    } else {
        bail!("Instruction path must be absolute or supply 'cwd'")
    }
}

// MARK: - Attachments Staging

fn attachments_stage(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let file_path = str_param(params, &["filePath", "path"])
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let base64_raw = str_param(params, &["base64", "data"])
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let custom_name = str_param(params, &["filename", "name"])
        .map(str::trim)
        .filter(|s| !s.is_empty() && !s.chars().any(char::is_control));

    let mut stored = if let Some(fp) = file_path {
        let source = Path::new(fp);
        ensure!(source.is_absolute(), "Attachment filePath must be absolute");
        attachments::ingest_image(&runtime.data_dir, source)?
    } else if let Some(b64) = base64_raw {
        let payload = b64
            .split_once(";base64,")
            .map(|(_, rest)| rest)
            .unwrap_or(b64);
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(payload.trim())
            .context("Invalid base64 image data")?;
        let staged = attachments::stage_clipboard_image(&runtime.data_dir, &bytes)?;
        attachments::ingest_image(&runtime.data_dir, staged.path())?
    } else {
        bail!("Provide either 'filePath' or 'base64' to stage an attachment");
    };

    if let Some(name) = custom_name {
        stored.original_name = name.chars().take(255).collect();
    }

    if let Some(thread_id) = str_param(params, &["threadId", "threadID"]).filter(|s| !s.is_empty())
    {
        let mut engine = runtime
            .engine
            .lock()
            .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
        ensure!(!engine.admissions_frozen(), "Application is closing");
        ensure!(
            !engine.store.is_imported(thread_id)?,
            "Fork an imported thread before adding attachments"
        );
        let mut thread = engine.store.thread(thread_id)?;
        let mut draft_images = thread["rustDraftImages"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        ensure!(
            draft_images.len() < 20,
            "A draft can contain at most 20 images"
        );
        draft_images.push(serde_json::to_value(&stored)?);
        thread["rustDraftImages"] = Value::Array(draft_images);
        engine.store.save(&thread)?;
        engine.revision += 1;
    }

    let mut out = serde_json::to_value(&stored)?;
    if let Some(obj) = out.as_object_mut() {
        obj.insert("attachment".into(), serde_json::to_value(&stored)?);
    }
    Ok(out)
}

// MARK: - Permanent Thread Deletion & Undo

fn threads_delete_permanent(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let mut ids: Vec<String> = if let Some(arr) = params.get("threadIds").and_then(Value::as_array)
    {
        arr.iter()
            .filter_map(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_owned)
            .collect()
    } else {
        vec![req_str(params, &["threadId", "threadID", "id"], "threadId")?.to_owned()]
    };
    ensure!(!ids.is_empty(), "Provide at least one threadId");

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;

    // Resolve canonical stored IDs first
    for slot in &mut ids {
        if let Ok(uuid) = Uuid::parse_str(slot)
            && let Ok(Some(resolved)) = engine.store.resolve_thread_id(uuid)
        {
            *slot = resolved;
        }
    }

    let prepared = match engine.prepare_native_conversation_deletion(&ids) {
        Ok(plan) => plan,
        Err(_) => engine.prepare_native_thread_deletion(&ids)?,
    };
    let undo = engine.apply_native_thread_deletion(prepared)?;
    let deleted_ids = undo.thread_ids();
    let count = undo.count();
    let byte_len = undo.byte_len();
    let undo_id = Uuid::new_v4().to_string().to_uppercase();

    let shared_undo = Arc::new(Mutex::new(Some(undo)));
    if let Ok(mut map) = runtime.thread_delete_undos.lock() {
        if map.len() > 256 {
            map.clear();
        }
        map.insert(undo_id.clone(), shared_undo.clone());
        for tid in &deleted_ids {
            map.insert(tid.to_uppercase(), shared_undo.clone());
        }
    }

    Ok(json!({
        "deleted": true,
        "count": count,
        "byteLen": byte_len,
        "threadIds": deleted_ids,
        "undoId": undo_id,
    }))
}

fn threads_undo_delete(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let key = req_str(
        params,
        &["threadId", "threadID", "undoId", "id"],
        "threadId",
    )?
    .to_uppercase();

    let holder = runtime
        .thread_delete_undos
        .lock()
        .map_err(|_| anyhow::anyhow!("Undo registry lock poisoned"))?
        .remove(&key)
        .context("No undoable deletion found for this conversation")?;

    let undo = holder
        .lock()
        .map_err(|_| anyhow::anyhow!("Undo entry lock poisoned"))?
        .take()
        .context("This deletion was already undone")?;

    let restored_ids = undo.thread_ids();
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    engine.undo_native_thread_deletion(&undo)?;

    if let Ok(mut map) = runtime.thread_delete_undos.lock() {
        for tid in &restored_ids {
            map.remove(&tid.to_uppercase());
        }
    }

    Ok(json!({
        "restored": true,
        "threadIds": restored_ids,
    }))
}

// MARK: - Schedules & Project Scripts

fn schedules_approve(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let id = req_str(params, &["id", "scheduleId", "taskId"], "id")?;
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    engine.approve_schedule(id)
}

fn projects_scripts_save(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let project_id = req_str(params, &["projectId", "projectID"], "projectId")?;
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;

    let target_uuid = Uuid::parse_str(project_id).context("Project identity must be a UUID")?;
    let projects_doc = engine.store.projects()?;
    let mut project = projects_doc
        .as_array()
        .context("Projects must be an array")?
        .iter()
        .find(|p| {
            p["id"]
                .as_str()
                .and_then(|id| Uuid::parse_str(id).ok())
                == Some(target_uuid)
        })
        .cloned()
        .context("Project not found")?;

    if params.get("importT3").and_then(Value::as_bool) == Some(true) {
        let updated = engine.native_edit_project_scripts(&project, &ScriptEdit::ImportT3)?;
        return Ok(json!({ "project": updated, "scripts": updated["scripts"] }));
    }

    if let Some(del_id) = str_param(params, &["deleteId", "deleteScriptId"])
        .filter(|s| !s.is_empty())
    {
        let uuid = Uuid::parse_str(del_id).context("Invalid script UUID")?;
        let updated = engine.native_edit_project_scripts(&project, &ScriptEdit::Delete(uuid))?;
        return Ok(json!({ "project": updated, "scripts": updated["scripts"] }));
    }

    let incoming = params
        .get("scripts")
        .and_then(Value::as_array)
        .context("Missing 'scripts' array parameter")?;

    // Sync the full scripts list through `Engine::native_edit_project_scripts`:
    // 1) Delete any existing scripts omitted from `incoming`
    let existing = project_scripts::scripts(&project);
    let incoming_uuids: HashSet<Uuid> = incoming
        .iter()
        .filter_map(|row| row["id"].as_str())
        .filter_map(|id| Uuid::parse_str(id).ok())
        .filter(|u| !u.is_nil())
        .collect();

    for old in &existing {
        let old_uuid = old.uuid();
        if !incoming_uuids.contains(&old_uuid) {
            project =
                engine.native_edit_project_scripts(&project, &ScriptEdit::Delete(old_uuid))?;
        }
    }

    // 2) Save (update existing or insert new) each script in `incoming`
    let current_uuids: HashSet<Uuid> = project_scripts::scripts(&project)
        .into_iter()
        .map(|s| s.uuid())
        .collect();

    for item in incoming {
        let name = item["name"].as_str().unwrap_or("").to_owned();
        let command = item["command"].as_str().unwrap_or("").to_owned();
        let icon = ScriptIcon::parse(&item["icon"]).unwrap_or_default();
        let run_on_worktree_create = item["runOnWorktreeCreate"].as_bool().unwrap_or(false);
        let id = item["id"]
            .as_str()
            .and_then(|s| Uuid::parse_str(s).ok())
            .filter(|u| current_uuids.contains(u));
        let edit = ScriptEdit::Save {
            id,
            draft: ScriptDraft {
                name,
                command,
                icon,
                run_on_worktree_create,
            },
        };
        project = engine.native_edit_project_scripts(&project, &edit)?;
    }

    Ok(json!({
        "project": project,
        "scripts": project["scripts"],
    }))
}

// MARK: - Usage Dashboard

pub fn usage_dashboard(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let days = params
        .get("days")
        .and_then(Value::as_u64)
        .map(|d| d as u32)
        .unwrap_or(30)
        .clamp(1, 365);
    let provider_filter = str_param(params, &["provider"])
        .map(str::trim)
        .filter(|s| !s.is_empty() && *s != "all")
        .map(str::to_owned);
    let account_filter = str_param(params, &["accountId", "accountID"])
        .map(str::trim)
        .filter(|s| !s.is_empty() && *s != "all")
        .map(str::to_owned);
    let refresh = params
        .get("refresh")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let (history_doc, projects_doc, rate_limits) = {
        let mut engine = runtime
            .engine
            .lock()
            .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
        if refresh {
            let _ = engine.dispatch_desktop(json!({
                "method": "usage.codexLimits.refresh",
                "params": {},
            }));
            let _ = engine.dispatch_desktop(json!({
                "method": "usage.claudeLimits.refresh",
                "params": {},
            }));
        }
        let codex_limits = engine.dispatch_desktop(json!({
            "method": "usage.codexLimits.status",
            "params": {},
        }))["result"]
            .clone();
        let claude_limits = engine.dispatch_desktop(json!({
            "method": "usage.claudeLimits.status",
            "params": {},
        }))["result"]
            .clone();
        let history = engine.store.document("usage-history.json")?;
        let projects = engine.store.projects().unwrap_or_else(|_| json!([]));
        (
            history,
            projects,
            json!({
                "codex": codex_limits,
                "claude": claude_limits,
            }),
        )
    };

    let (turns, skipped) = match history_doc {
        Some(doc) => {
            let raw = serde_json::to_vec(&doc)?;
            usage_report::turn_records(&raw).unwrap_or_else(|_| (Vec::new(), 0))
        }
        None => (Vec::new(), 0),
    };

    let mut events = usage_report::events(&turns, &[]);
    if let Some(prov) = &provider_filter {
        events.retain(|e| &e.provider == prov);
    }
    if let Some(acc) = &account_filter {
        events.retain(|e| &e.account_id == acc);
    }

    let now = Utc::now();
    let report = usage_report::Report::make(&events, days, now, &chrono::Local);

    let totals_json = |t: &Totals| {
        json!({
            "inputTokens": t.tokens.input,
            "cacheReadTokens": t.tokens.cache_read,
            "cacheWriteTokens": t.tokens.cache_write,
            "outputTokens": t.tokens.output,
            "reasoningTokens": t.tokens.reasoning,
            "totalTokens": t.tokens.total(),
            "estimatedCostUsd": t.cost,
            "unpricedTokens": t.unpriced_tokens,
            "requests": t.requests,
            "fullyPriced": t.is_fully_priced(),
        })
    };

    let project_names: std::collections::HashMap<String, String> = projects_doc
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|p| {
            Some((
                p["id"].as_str()?.to_uppercase(),
                p["name"].as_str().unwrap_or("Project").to_owned(),
            ))
        })
        .collect();

    let daily: Vec<Value> = report
        .days
        .iter()
        .map(|row| {
            let ts_ms = chrono::Local
                .from_local_datetime(&row.day.and_hms_opt(0, 0, 0).unwrap())
                .earliest()
                .map(|dt| dt.timestamp_millis())
                .unwrap_or(0);
            json!({
                "date": row.day.to_string(),
                "dayMs": ts_ms,
                "provider": row.provider,
                "totals": totals_json(&row.totals),
            })
        })
        .collect();

    let models: Vec<Value> = report
        .models
        .iter()
        .map(|m| {
            json!({
                "provider": m.provider,
                "model": if m.model.is_empty() { "default" } else { &m.model },
                "totals": totals_json(&m.totals),
            })
        })
        .collect();

    let projects: Vec<Value> = report
        .projects
        .iter()
        .map(|p| {
            json!({
                "projectId": p.project_id,
                "projectName": project_names.get(&p.project_id).cloned().unwrap_or_else(|| "Chats".into()),
                "totals": totals_json(&p.totals),
            })
        })
        .collect();

    let accounts: Vec<Value> = report
        .accounts
        .iter()
        .map(|(key, t)| {
            json!({
                "accountKey": key,
                "totals": totals_json(t),
            })
        })
        .collect();

    Ok(json!({
        "days": days,
        "provider": provider_filter,
        "accountId": account_filter,
        "skippedRecords": skipped,
        "today": totals_json(&report.today),
        "yesterday": totals_json(&report.yesterday),
        "todayTrend": usage_report::trend(&report.today, &report.yesterday),
        "lastWeek": totals_json(&report.last_week),
        "previousWeek": totals_json(&report.previous_week),
        "weekTrend": usage_report::trend(&report.last_week, &report.previous_week),
        "lastMonth": totals_json(&report.last_month),
        "previousMonth": totals_json(&report.previous_month),
        "monthTrend": usage_report::trend(&report.last_month, &report.previous_month),
        "period": totals_json(&report.period),
        "daily": daily,
        "models": models,
        "projects": projects,
        "accounts": accounts,
        "rateLimits": rate_limits,
    }))
}

// MARK: - Remote Server Control

fn serialize_remote_snapshot(snapshot: &RemoteSnapshot) -> Value {
    let (status_name, port, status_error) = match &snapshot.status {
        RemoteStatus::Off => ("off", None, None),
        RemoteStatus::Starting => ("starting", None, None),
        RemoteStatus::Running { port } => ("running", Some(*port), None),
        RemoteStatus::Failed(err) => ("failed", None, Some(err.clone())),
    };

    let devices: Vec<Value> = snapshot
        .devices
        .iter()
        .map(|d| {
            json!({
                "id": d.id,
                "name": d.name,
                "pairedAt": d.paired_at,
                "lastSeenAt": d.last_seen_at,
                "isConnected": snapshot.connected.contains(&d.id),
            })
        })
        .collect();

    let pairing_json = snapshot.pairing.as_ref().map(|payload| {
        let uri = payload.encoded();
        let matrix_rows: Option<Vec<String>> = qr::encode(&uri).map(|matrix| {
            (0..matrix.size)
                .map(|y| {
                    (0..matrix.size)
                        .map(|x| if matrix.dark(x, y) { '#' } else { '.' })
                        .collect::<String>()
                })
                .collect()
        });
        json!({
            "uri": uri,
            "expiresAt": payload.expires_at,
            "fingerprint": payload.fingerprint,
            "displayFingerprint": display_fingerprint(&payload.fingerprint, 8),
            "hosts": payload.hosts,
            "serverId": payload.server_id,
            "name": payload.name,
            "port": payload.port,
            "version": payload.version,
            "qrMatrix": matrix_rows,
        })
    });

    let addresses: Vec<String> = snapshot.candidates.iter().map(|c| c.host.clone()).collect();

    json!({
        "enabled": snapshot.enabled,
        "status": status_name,
        "port": port,
        "error": status_error,
        "fingerprint": snapshot.fingerprint,
        "displayFingerprint": snapshot.fingerprint.as_deref().map(|f| display_fingerprint(f, 8)),
        "addresses": addresses,
        "candidates": snapshot.candidates,
        "devices": devices,
        "connectedDeviceIds": snapshot.connected.iter().cloned().collect::<Vec<_>>(),
        "pairing": pairing_json,
        "pairingUri": pairing_json.as_ref().and_then(|p| p["uri"].as_str()),
        "lastPaired": snapshot.last_paired,
        "storageError": snapshot.storage_error,
    })
}

fn remote_status(runtime: &CoincideMacOSRuntime) -> Result<Value> {
    let remote = runtime
        .remote
        .lock()
        .map_err(|_| anyhow::anyhow!("RemoteServer lock poisoned"))?;
    Ok(serialize_remote_snapshot(&remote.snapshot()))
}

fn remote_set_enabled(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let enabled = params
        .get("enabled")
        .and_then(Value::as_bool)
        .context("Missing boolean parameter 'enabled'")?;
    let mut remote = runtime
        .remote
        .lock()
        .map_err(|_| anyhow::anyhow!("RemoteServer lock poisoned"))?;
    remote.set_enabled(enabled);
    Ok(serialize_remote_snapshot(&remote.snapshot()))
}

fn remote_begin_pairing(runtime: &CoincideMacOSRuntime) -> Result<Value> {
    let mut remote = runtime
        .remote
        .lock()
        .map_err(|_| anyhow::anyhow!("RemoteServer lock poisoned"))?;
    if !remote.is_enabled() {
        remote.set_enabled(true);
    }
    let payload = remote
        .begin_pairing()
        .context("Remote server is not running; check status or storage error")?;
    let mut out = serialize_remote_snapshot(&remote.snapshot());
    out["pairingUri"] = json!(payload.encoded());
    Ok(out)
}

fn remote_cancel_pairing(runtime: &CoincideMacOSRuntime) -> Result<Value> {
    let mut remote = runtime
        .remote
        .lock()
        .map_err(|_| anyhow::anyhow!("RemoteServer lock poisoned"))?;
    remote.cancel_pairing();
    Ok(serialize_remote_snapshot(&remote.snapshot()))
}

fn remote_revoke_device(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let device_id = req_str(params, &["deviceId", "deviceID", "id"], "deviceId")?;
    let mut remote = runtime
        .remote
        .lock()
        .map_err(|_| anyhow::anyhow!("RemoteServer lock poisoned"))?;
    RemoteServer::revoke(&mut remote, device_id);
    Ok(serialize_remote_snapshot(&remote.snapshot()))
}

fn remote_reset_identity(runtime: &CoincideMacOSRuntime) -> Result<Value> {
    let mut remote = runtime
        .remote
        .lock()
        .map_err(|_| anyhow::anyhow!("RemoteServer lock poisoned"))?;
    remote.reset_identity()?;
    Ok(serialize_remote_snapshot(&remote.snapshot()))
}
