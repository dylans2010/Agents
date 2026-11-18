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
