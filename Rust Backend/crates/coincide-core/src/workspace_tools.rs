use anyhow::{Context, Result, bail, ensure};
use crate::{native_file, project_search, workspace};
use serde_json::{Value, json};
use std::{
    collections::VecDeque,
    fs::{self, OpenOptions},
    io::{Read, Seek, SeekFrom, Write},
    path::{Component, Path, PathBuf},
};
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;

const MAX_FILE_WRITE_BYTES: usize = 3 * 1024 * 1024;

pub fn files(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd", "path"], "cwd")?);
    ensure!(cwd.is_dir(), "Workspace directory does not exist");
    let query = str_param(params, &["query"]).unwrap_or("");
    let limit = params
        .get("limit")
        .and_then(Value::as_u64)
        .map(|n| n as usize)
        .unwrap_or(500)
        .clamp(1, 5000);

    match workspace::files(&cwd, query, limit) {
        Ok(res) => Ok(res),
        Err(_) => fallback_walk_files(&cwd, query, limit),
    }
}

fn fallback_walk_files(root: &Path, query: &str, limit: usize) -> Result<Value> {
    const IGNORED: &[&str] = &[
        ".git",
        "node_modules",
        "target",
        "DerivedData",
        ".build",
        "dist",
        "build",
        ".venv",
        "venv",
        "__pycache__",
    ];
    let root = root.canonicalize()?;
    let lower_q = query.to_lowercase();
    let mut queue = VecDeque::from([(root.clone(), 0usize)]);
    let mut visited = 0usize;
    let mut matched = Vec::new();
    while let Some((dir, depth)) = queue.pop_front() {
        if visited >= 10_000 {
            break;
        }
        visited += 1;
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let Ok(ft) = entry.file_type() else { continue };
            if ft.is_symlink() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            let path = entry.path();
            if ft.is_dir() {
                if depth < 16 && !IGNORED.contains(&name.as_str()) {
                    queue.push_back((path, depth + 1));
                }
            } else if ft.is_file()
                && let Ok(rel) = path.strip_prefix(&root)
                && let Some(rel_str) = rel.to_str()
            {
                if lower_q.is_empty() || rel_str.to_lowercase().contains(&lower_q) {
                    matched.push(rel_str.to_owned());
                }
            }
        }
    }
    matched.sort_unstable();
    let total = matched.len();
    matched.truncate(limit);
    Ok(json!({
        "files": matched,
        "total": total,
        "truncated": total > limit,
    }))
}

pub fn search(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let query = req_str(params, &["query"], "query")?;
    let limit = params
        .get("limit")
        .and_then(Value::as_u64)
        .map(|n| n as usize)
        .unwrap_or(project_search::TEXT_LIMIT)
        .clamp(1, 1000);

    let mut matches = project_search::text(&cwd, query)?;
    let total = matches.len();
    matches.truncate(limit);
    let rows: Vec<Value> = matches
        .into_iter()
        .map(|m| {
            json!({
                "path": m.path,
                "line": m.line,
                "text": m.text,
            })
        })
        .collect();
    Ok(json!({
        "matches": rows,
        "total": total,
        "truncated": total > limit,
    }))
}

fn validate_relative_workspace_path(path: &str) -> Result<&Path> {
    let rel = Path::new(path);
    ensure!(
        !rel.as_os_str().is_empty()
            && rel
                .components()
                .all(|part| matches!(part, Component::Normal(_))),
        "Path must be a relative workspace path without '.' or '..' components"
    );
    Ok(rel)
}

fn workspace_target_parts(cwd: &Path, rel_str: &str) -> Result<(PathBuf, PathBuf)> {
    let rel = validate_relative_workspace_path(rel_str)?;
    let canonical_root = cwd.canonicalize().context("Workspace directory is unavailable")?;
    let joined = canonical_root.join(rel);
    Ok((canonical_root, joined))
}

fn existing_workspace_target(cwd: &Path, rel_str: &str) -> Result<PathBuf> {
    let (canonical_root, joined) = workspace_target_parts(cwd, rel_str)?;
    let meta = fs::symlink_metadata(&joined)?;
    ensure!(
        !meta.file_type().is_symlink(),
        "Refusing to operate on a symlink"
    );
    let canonical = joined.canonicalize().context("Path does not exist")?;
    ensure!(
        canonical.starts_with(&canonical_root),
        "Path resolves outside the workspace directory"
    );
    Ok(canonical)
}

fn workspace_parent_for_write(cwd: &Path, rel_str: &str) -> Result<(PathBuf, String)> {
    let rel = validate_relative_workspace_path(rel_str)?;
    let canonical_root = cwd.canonicalize().context("Workspace directory is unavailable")?;
    let mut current = canonical_root.clone();
    if let Some(parent_rel) = rel.parent() {
        for component in parent_rel.components() {
            current.push(component);
            match fs::symlink_metadata(&current) {
                Ok(meta) => {
                    ensure!(
                        meta.is_dir() && !meta.file_type().is_symlink(),
                        "Intermediate workspace path is not a regular directory"
                    );
                }
                Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                    fs::create_dir(&current)?;
                }
                Err(err) => return Err(err.into()),
            }
        }
    }
    let canonical_parent = current.canonicalize()?;
    ensure!(
        canonical_parent.starts_with(&canonical_root),
        "Target parent directory is outside the workspace"
    );
    let name = rel
        .file_name()
        .context("Invalid filename")?
        .to_string_lossy()
        .into_owned();
    Ok((canonical_parent, name))
}

fn read_workspace_text(cwd: &Path, rel_str: &str) -> Result<(String, PathBuf)> {
    let (canonical_root, joined) = workspace_target_parts(cwd, rel_str)?;
    let meta = fs::symlink_metadata(&joined)?;
    ensure!(
        meta.is_file() && !meta.file_type().is_symlink(),
        "Path is not a regular file"
    );
    let canonical = joined.canonicalize().context("File does not exist")?;
    ensure!(
        canonical.starts_with(&canonical_root),
        "File resolves outside the workspace directory"
    );
    let mut file = native_file::open_regular(&canonical, false)?;
    let mut bytes = Vec::new();
    Read::by_ref(&mut file)
        .take((MAX_FILE_WRITE_BYTES + 1) as u64)
        .read_to_end(&mut bytes)?;
    ensure!(bytes.len() <= MAX_FILE_WRITE_BYTES, "File exceeds 3 MiB");
    ensure!(!bytes.contains(&0), "File is binary");
    let content = String::from_utf8(bytes).context("File is not valid UTF-8 text")?;
    Ok((content, canonical))
}

pub fn search_regex(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let pattern = req_str(params, &["pattern"], "pattern")?;
    let limit = params
        .get("limit")
        .and_then(Value::as_u64)
        .map(|n| n as usize)
        .unwrap_or(project_search::TEXT_LIMIT)
        .clamp(1, 1000);
    let mut matches = project_search::text_regex(&cwd, pattern)?;
    let total = matches.len();
    matches.truncate(limit);
    let rows: Vec<Value> = matches
        .into_iter()
        .map(|m| {
            json!({
                "path": m.path,
                "line": m.line,
                "text": m.text,
            })
        })
        .collect();
    Ok(json!({
        "matches": rows,
        "total": total,
        "truncated": total > limit,
    }))
}

pub fn delete_file(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let rel_str = req_str(params, &["path"], "path")?;
    let target = existing_workspace_target(&cwd, rel_str)?;
    ensure!(fs::metadata(&target)?.is_file(), "Path is not a file");
    fs::remove_file(&target)?;
    Ok(json!({
        "path": rel_str,
        "deleted": true,
    }))
}

pub fn delete_directory(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let rel_str = req_str(params, &["path"], "path")?;
    let recursive = params.get("recursive").and_then(Value::as_bool).unwrap_or(false);
    let target = existing_workspace_target(&cwd, rel_str)?;
    ensure!(fs::metadata(&target)?.is_dir(), "Path is not a directory");
    if recursive {
        fs::remove_dir_all(&target)?;
    } else {
        fs::remove_dir(&target)?;
    }
    Ok(json!({
        "path": rel_str,
        "deleted": true,
        "recursive": recursive,
    }))
}

fn require_absent_destination(dest: &Path) -> Result<()> {
    match fs::symlink_metadata(dest) {
        Ok(_) => bail!("Destination already exists"),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err.into()),
    }
}

pub fn move_file(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let rel_str = req_str(params, &["path"], "path")?;
    let dest_str = req_str(params, &["destination"], "destination")?;
    let source = existing_workspace_target(&cwd, rel_str)?;
    let (dest_parent, dest_name) = workspace_parent_for_write(&cwd, dest_str)?;
    let dest = dest_parent.join(&dest_name);
    ensure!(source != dest, "Source and destination are the same path");
    require_absent_destination(&dest)?;
    fs::rename(&source, &dest)?;
    Ok(json!({
        "path": rel_str,
        "destination": dest_str,
        "moved": true,
    }))
}

pub fn copy_file(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let rel_str = req_str(params, &["path"], "path")?;
    let dest_str = req_str(params, &["destination"], "destination")?;
    let source = existing_workspace_target(&cwd, rel_str)?;
    ensure!(fs::metadata(&source)?.is_file(), "Path is not a file");
    let (dest_parent, dest_name) = workspace_parent_for_write(&cwd, dest_str)?;
    let dest = dest_parent.join(&dest_name);
    ensure!(source != dest, "Source and destination are the same path");
    require_absent_destination(&dest)?;
    let bytes = fs::copy(&source, &dest)?;
    Ok(json!({
        "path": rel_str,
        "destination": dest_str,
        "copied": true,
        "byteLen": bytes,
    }))
}

pub fn create_dir(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let rel_str = req_str(params, &["path"], "path")?;
    let (parent, name) = workspace_parent_for_write(&cwd, rel_str)?;
    let target = parent.join(&name);
    match fs::symlink_metadata(&target) {
        Ok(meta) => {
            ensure!(
                meta.is_dir() && !meta.file_type().is_symlink(),
                "Path exists and is not a directory"
            );
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            fs::create_dir(&target)?;
        }
        Err(err) => return Err(err.into()),
    }
    Ok(json!({
        "path": rel_str,
        "created": true,
    }))
}

pub fn read_dir(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let rel_str = str_param(params, &["path"]).unwrap_or("");
    let recursive = params.get("recursive").and_then(Value::as_bool).unwrap_or(false);
    let canonical_root = cwd.canonicalize().context("Workspace directory is unavailable")?;
    let base = if rel_str.is_empty() || rel_str == "." {
        canonical_root.clone()
    } else {
        existing_workspace_target(&cwd, rel_str)?
    };
    ensure!(fs::metadata(&base)?.is_dir(), "Path is not a directory");
    let mut entries: Vec<Value> = Vec::new();
    let mut queue = VecDeque::from([(base, 0usize)]);
    while let Some((dir, depth)) = queue.pop_front() {
        if entries.len() >= 5000 {
            break;
        }
        let Ok(read) = fs::read_dir(&dir) else {
            continue;
        };
        let mut rows: Vec<_> = read.flatten().collect();
        rows.sort_by_key(|entry| entry.file_name());
        for entry in rows {
            if entries.len() >= 5000 {
                break;
            }
            let Ok(kind) = entry.file_type() else {
                continue;
            };
            let name = entry.file_name().to_string_lossy().into_owned();
            let path = entry.path();
            let Ok(rel) = path.strip_prefix(&canonical_root) else {
                continue;
            };
            let Some(rel_str) = rel.to_str() else {
                continue;
            };
            let is_dir = kind.is_dir();
            entries.push(json!({
                "path": rel_str.replace('\\', "/"),
                "name": name,
                "isDirectory": is_dir,
            }));
            if recursive && is_dir && depth < 16 {
                queue.push_back((path, depth + 1));
            }
        }
    }
    entries.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
    let total = entries.len();
    Ok(json!({
        "path": rel_str,
        "entries": entries,
        "total": total,
    }))
}

pub fn edit_file(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let rel_str = req_str(params, &["path"], "path")?;
    let mut edits: Vec<(String, String, String)> = Vec::new();
    if let Some(list) = params.get("edits").and_then(Value::as_array) {
        ensure!(!list.is_empty(), "Edits must not be empty");
        ensure!(list.len() <= 100, "Too many edits in one call");
        for item in list {
            let old = item
                .get("oldText")
                .and_then(Value::as_str)
                .context("Each edit requires 'oldText'")?;
            let new = item
                .get("newText")
                .and_then(Value::as_str)
                .context("Each edit requires 'newText'")?;
            let mode = item.get("mode").and_then(Value::as_str).unwrap_or("replace");
            edits.push((old.to_owned(), new.to_owned(), mode.to_owned()));
        }
    } else {
        let old = req_str(params, &["oldText"], "oldText")?;
        let new = params
            .get("newText")
            .and_then(Value::as_str)
            .context("Missing required string parameter 'newText'")?;
        let mode = str_param(params, &["mode"]).unwrap_or("replace");
        edits.push((old.to_owned(), new.to_owned(), mode.to_owned()));
    }
    let (content, target) = read_workspace_text(&cwd, rel_str)?;
    let mut updated = content.clone();
    let mut lines: Vec<Value> = Vec::new();
    for (old, new, mode) in &edits {
        ensure!(!old.is_empty(), "Anchor text must not be empty");
        ensure!(!new.contains('\0'), "NUL bytes are not permitted in text files");
        ensure!(
            matches!(mode.as_str(), "replace" | "insertAfter" | "insertBefore"),
            "Edit mode must be 'replace', 'insertAfter' or 'insertBefore'"
        );
        let found: Vec<usize> = updated.match_indices(old).map(|(index, _)| index).collect();
        ensure!(
            !found.is_empty(),
            format!("Anchor text not found in {rel_str}")
        );
        ensure!(
            found.len() == 1,
            format!(
                "Anchor text matches {} times in {rel_str}; refine the anchor to match exactly once",
                found.len()
            )
        );
        let at = found[0];
        let line = updated[..at].matches('\n').count() + 1;
        let replacement = match mode.as_str() {
            "insertAfter" => format!("{old}{new}"),
            "insertBefore" => format!("{new}{old}"),
            _ => new.clone(),
        };
        updated.replace_range(at..at + old.len(), &replacement);
        lines.push(json!(line));
    }
    ensure!(
        updated.len() <= MAX_FILE_WRITE_BYTES,
        "Edited file exceeds 3 MiB limit"
    );
    write_regular_utf8(&target, updated.as_bytes())?;
    let (verified, _) = read_workspace_text(&cwd, rel_str)?;
    ensure!(
        verified == updated,
        "Edit verification failed: file content changed after write"
    );
    Ok(json!({
        "path": rel_str,
        "edited": true,
        "replacements": edits.len(),
        "lines": lines,
        "byteLen": updated.len(),
    }))
}

pub fn read_file(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let rel_str = req_str(params, &["path"], "path")?;

    if params.get("lineOffset").is_some() || params.get("lineLimit").is_some() {
        let offset = params
            .get("lineOffset")
            .and_then(Value::as_u64)
            .unwrap_or(0) as usize;
        let limit = params
            .get("lineLimit")
            .and_then(Value::as_u64)
            .unwrap_or(2000)
            .clamp(1, 5000) as usize;
        let mut value = workspace::read_file(&cwd, rel_str, offset, limit)?;
        if let Some(text) = value["text"].as_str().map(str::to_owned) {
            value["content"] = json!(text);
        }
        return Ok(value);
    }

    let rel = validate_relative_workspace_path(rel_str)?;
    let canonical_root = cwd.canonicalize().context("Workspace directory is unavailable")?;
    let target = canonical_root.join(rel);
    let canonical_file = target.canonicalize().context("File does not exist")?;
    ensure!(
        canonical_file.starts_with(&canonical_root),
        "File resolves outside the workspace directory"
    );
    let mut file = native_file::open_regular(&canonical_file, false)?;
    let mut bytes = Vec::new();
    Read::by_ref(&mut file)
        .take((MAX_FILE_WRITE_BYTES + 1) as u64)
        .read_to_end(&mut bytes)?;
    ensure!(bytes.len() <= MAX_FILE_WRITE_BYTES, "File exceeds 3 MiB");
    ensure!(!bytes.contains(&0), "File is binary");
    let content = String::from_utf8(bytes).context("File is not valid UTF-8 text")?;
    let total_lines = content.lines().count();
    Ok(json!({
        "path": rel_str,
        "text": content,
        "content": content,
        "lineOffset": 0,
        "totalLines": total_lines,
        "truncated": false,
    }))
}

pub fn write_file(params: &Value) -> Result<Value> {
    let cwd = PathBuf::from(req_str(params, &["cwd"], "cwd")?);
    let rel_str = req_str(params, &["path"], "path")?;
    let content = params
        .get("content")
        .or_else(|| params.get("text"))
        .and_then(Value::as_str)
        .context("Missing required string parameter 'content'")?;
    ensure!(
        content.len() <= MAX_FILE_WRITE_BYTES,
        "File content exceeds 3 MiB limit"
    );
    ensure!(!content.contains('\0'), "NUL bytes are not permitted in text files");

    let rel = validate_relative_workspace_path(rel_str)?;
    let canonical_root = cwd.canonicalize().context("Workspace directory is unavailable")?;

    let mut current = canonical_root.clone();
    if let Some(parent_rel) = rel.parent() {
        for component in parent_rel.components() {
            current.push(component);
            match fs::symlink_metadata(&current) {
                Ok(meta) => {
                    ensure!(
                        meta.is_dir() && !meta.file_type().is_symlink(),
                        "Intermediate workspace path is not a regular directory"
                    );
                }
                Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                    fs::create_dir(&current)?;
                }
                Err(err) => return Err(err.into()),
            }
        }
    }
    let canonical_parent = current.canonicalize()?;
    ensure!(
        canonical_parent.starts_with(&canonical_root),
        "Target parent directory is outside the workspace"
    );
    let target = canonical_parent.join(rel.file_name().context("Invalid filename")?);

    write_regular_utf8(&target, content.as_bytes())?;

    Ok(json!({
        "path": rel_str,
        "saved": true,
        "byteLen": content.len(),
    }))
}

fn write_regular_utf8(target: &Path, bytes: &[u8]) -> Result<()> {
    match fs::symlink_metadata(target) {
        Ok(meta) => {
            ensure!(
                meta.is_file() && !meta.file_type().is_symlink(),
                "Refusing to overwrite symlink or non-regular file"
            );
            let mut file = native_file::open_regular(target, true)?;
            file.seek(SeekFrom::Start(0))?;
            file.write_all(bytes)?;
            file.set_len(bytes.len() as u64)?;
            file.sync_all()?;
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            let mut options = OpenOptions::new();
            options.write(true).create_new(true);
            #[cfg(unix)]
            options.custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC);
            let mut file = options.open(target)?;
            file.write_all(bytes)?;
            file.sync_all()?;
        }
        Err(err) => return Err(err.into()),
    }
    Ok(())
}
