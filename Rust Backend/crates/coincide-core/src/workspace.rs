//! Bounded project inspection shared by the desktop and CLI.
#[path = "workspace_path.rs"]
mod path;
use anyhow::{Context, Result, bail, ensure};
pub(crate) use path::{external_git_directory, external_git_path};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    io::Read,
    path::{Component, Path},
    process::{Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

const MAX_OUTPUT: usize = 3 * 1024 * 1024;

/// How one Git invocation differs from the bounded default.
pub(crate) struct GitOptions<'a> {
    /// A throwaway index, so Git never reads or writes the user's.
    pub index_file: Option<&'a Path>,
    pub input: Option<&'a [u8]>,
    pub timeout: Duration,
    pub max_output: usize,
    /// Stop reading at `max_output` and report the cut instead of failing.
    pub truncate: bool,
}

impl Default for GitOptions<'_> {
    fn default() -> Self {
        Self {
            index_file: None,
            input: None,
            timeout: Duration::from_secs(15),
            max_output: MAX_OUTPUT,
            truncate: false,
        }
    }
}

pub(crate) fn git(directory: &Path, arguments: &[&str]) -> Result<Vec<u8>> {
    let output = git_output(directory, arguments, &GitRequest::default())?;
    ensure!(
        !output.overflowed,
        "Git output exceeds 3 MiB; narrow the path"
    );
    ensure!(
        output.success,
        "Git failed: {}",
        String::from_utf8_lossy(&output.stderr)
            .chars()
            .take(2000)
            .collect::<String>()
    );
    Ok(output.stdout)
}

/// Per-call additions to the hardened runner. Environment entries are applied
/// after inherited GIT_* variables are removed, so only these reach Git.
pub(crate) struct GitRequest<'a> {
    pub env: &'a [(&'a str, &'a std::ffi::OsStr)],
    pub input: Option<&'a [u8]>,
    pub timeout: Duration,
    pub max_output: usize,
    /// Off only for callers that build explicitly literal pathspec magic.
    pub literal_pathspecs: bool,
    pub truncate: bool,
    pub stderr_limit: Option<usize>,
}
impl Default for GitRequest<'_> {
    fn default() -> Self {
        Self {
            env: &[],
            input: None,
            timeout: Duration::from_secs(15),
            max_output: MAX_OUTPUT,
            literal_pathspecs: true,
            truncate: false,
            stderr_limit: None,
        }
    }
}
pub(crate) struct GitOutput {
    pub success: bool,
    pub code: Option<i32>,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    /// Output passed max_output; stdout holds its first max_output + 1 bytes.
    pub overflowed: bool,
    pub truncated: bool,
}
impl GitOutput {
    pub(crate) fn stderr_text(&self) -> String {
        String::from_utf8_lossy(&self.stderr)
            .chars()
            .take(2000)
            .collect()
    }
}

pub(crate) fn git_with(
    directory: &Path,
    arguments: &[&str],
    options: &GitOptions<'_>,
) -> Result<(Vec<u8>, bool)> {
    let index = options.index_file.map(external_git_path).transpose()?;
    let env = index
        .as_ref()
        .map(|index| [("GIT_INDEX_FILE", index.as_os_str())]);
    let output = git_output(
        directory,
        arguments,
        &GitRequest {
            env: env.as_ref().map_or(&[], |entries| entries.as_slice()),
            input: options.input,
            timeout: options.timeout,
            max_output: options.max_output,
            truncate: options.truncate,
            stderr_limit: Some(MAX_OUTPUT),
            ..Default::default()
        },
    )?;
    ensure!(!output.overflowed, "Git output is too large");
    ensure!(
        output.truncated || output.success,
        "Git failed: {}",
        output.stderr_text()
    );
    Ok((output.stdout, output.truncated))
}

/// The hardened runner without the status check, for plumbing that inspects
/// stderr or exit codes. Timeouts and spawn failures are still errors.
pub(crate) fn git_output(
    directory: &Path,
    arguments: &[&str],
    request: &GitRequest<'_>,
) -> Result<GitOutput> {
    ensure!(directory.is_dir(), "Project directory does not exist");
    let mut command = Command::new("git");
    #[cfg(windows)]
    command.args(["-c", "core.longpaths=true"]);
    // An inherited Git config/index can redirect operations into another checkout.
    for (name, _) in std::env::vars_os() {
        if name.to_string_lossy().starts_with("GIT_") {
            command.env_remove(name);
        }
    }
    // A regular file cannot contain executable hooks (portable across platforms).
    let hooks = external_git_path(&std::env::current_exe()?)?;
    command
        .arg("-c")
        .arg(format!("core.hooksPath={}", hooks.to_string_lossy()));
    command.arg("--no-pager");
    if request.literal_pathspecs {
        command.arg("--literal-pathspecs");
    }
    command
        .args([
            "-c",
            "core.fsmonitor=false",
            "-c",
            "core.untrackedCache=false",
            "-c",
            "protocol.allow=never",
            "-C",
        ])
        .arg(path::external_git_directory(directory)?)
        .args(arguments)
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("GIT_NO_LAZY_FETCH", "1")
        .env("GIT_OPTIONAL_LOCKS", "0")
        .stdin(if request.input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for name in [
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_COMMON_DIR",
    ] {
        command.env_remove(name);
    }
    for (name, value) in request.env {
        command.env(name, value);
    }
    let mut child = command.spawn().context("Unable to start git")?;
    if let Some(input) = request.input {
        let mut stdin = child.stdin.take().context("Missing git stdin")?;
        let input = input.to_vec();
        // A separate writer keeps a large input from blocking output reads.
        thread::spawn(move || {
            use std::io::Write;
            let _ = stdin.write_all(&input);
        });
    }
    let stdout = child.stdout.take().context("Missing git stdout")?;
    let stderr = child.stderr.take().context("Missing git stderr")?;
    let limit = request.max_output;
    let read_pipe = |mut pipe: Box<dyn Read + Send>, limit: usize| {
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            let mut bytes = Vec::new();
            let result = (&mut pipe)
                .take((limit + 1) as u64)
                .read_to_end(&mut bytes)
                .map(|_| bytes);
            let capped = result.as_ref().is_ok_and(|bytes| bytes.len() > limit);
            // Publish the cap before draining so an authorized truncated read
            // can stop and reap Git without waiting for the rest of its output.
            let _ = tx.send(result);
            if capped {
                let _ = std::io::copy(&mut pipe, &mut std::io::sink());
            }
        });
        rx
    };
    let output = read_pipe(Box::new(stdout), limit);
    let stderr_limit = request.stderr_limit.unwrap_or(limit);
    let errors = read_pipe(Box::new(stderr), stderr_limit);
    let started = Instant::now();
    let mut read = None;
    let status = loop {
        if read.is_none()
            && let Ok(result) = output.try_recv()
        {
            read = Some(result);
        }
        if request.truncate
            && let Some(Ok(bytes)) = &read
            && bytes.len() > limit
        {
            let _ = child.kill();
            break child.wait()?;
        }
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if started.elapsed() < request.timeout => {
                thread::sleep(Duration::from_millis(20))
            }
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                bail!("Git operation timed out");
            }
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(error.into());
            }
        }
    };
    let mut bytes = match read {
        Some(result) => result?,
        None => output
            .recv_timeout(Duration::from_secs(1))
            .context("Git stdout did not close")??,
    };
    let errors = errors
        .recv_timeout(Duration::from_secs(1))
        .context("Git stderr did not close")??;
    let truncated = request.truncate && bytes.len() > limit;
    if truncated {
        bytes.truncate(limit);
    }
    Ok(GitOutput {
        success: status.success(),
        code: status.code(),
        overflowed: bytes.len() > limit || errors.len() > stderr_limit,
        truncated,
        stdout: bytes,
        stderr: errors,
    })
}

fn relative_path(path: &str) -> Result<&Path> {
    let path = Path::new(path);
    ensure!(
        !path.as_os_str().is_empty()
            && path
                .components()
                .all(|part| matches!(part, Component::Normal(_))),
        "Use a relative project path without dot or parent components"
    );
    Ok(path)
}

pub fn status(directory: &Path) -> Result<Value> {
    let bytes = git(
        directory,
        &["status", "--porcelain=v1", "-z", "--untracked-files=normal"],
    )?;
    let mut records = bytes.split(|b| *b == 0).filter(|r| !r.is_empty());
    let mut entries = Vec::new();
    while let Some(record) = records.next() {
        ensure!(record.len() >= 4, "Malformed git status record");
        let state = std::str::from_utf8(&record[..2])?;
        let path = std::str::from_utf8(&record[3..])?;
        let original = if state.contains('R') || state.contains('C') {
            Some(std::str::from_utf8(
                records.next().context("Missing rename source")?,
            )?)
        } else {
            None
        };
        entries.push(json!({"status":state,"path":path,"originalPath":original}));
    }
    let branch = String::from_utf8(
        git(directory, &["symbolic-ref", "--short", "-q", "HEAD"])
            .or_else(|_| git(directory, &["rev-parse", "--short", "HEAD"]))?,
    )?;
    Ok(json!({"branch":branch.trim(),"entries":entries}))
}

pub fn diff(directory: &Path, path: Option<&str>, staged: bool) -> Result<Value> {
    if let Some(path) = path {
        relative_path(path)?;
    }
    let mut args = vec!["diff", "--no-ext-diff", "--no-textconv", "--no-color"];
    if staged {
        args.push("--cached");
    }
    args.push("--");
    if let Some(path) = path {
        args.push(path);
    }
    Ok(json!({"diff":String::from_utf8(git(directory,&args)?)?,"staged":staged}))
}

pub fn log(directory: &Path, limit: usize, skip: usize) -> Result<Value> {
    ensure!((1..=200).contains(&limit), "Limit must be 1–200");
    ensure!(skip <= 100_000, "Skip must be at most 100000");
    let (bytes, truncated) = git_with(
        directory,
        &[
            "log",
            "--format=%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00%b%x1e",
            &format!("--max-count={limit}"),
            &format!("--skip={skip}"),
        ],
        &GitOptions {
            timeout: Duration::from_secs(60),
            truncate: true,
            ..GitOptions::default()
        },
    )?;
    let text = String::from_utf8(bytes)?;
    let mut records: Vec<&str> = text.split('\u{1e}').collect();
    if truncated {
        records.pop();
    }
    let commits: Vec<Value> = records.into_iter().filter_map(parse_log_record).collect();
    Ok(json!({"commits": commits, "truncated": truncated}))
}

fn parse_log_record(record: &str) -> Option<Value> {
    let record = record.strip_prefix('\n').unwrap_or(record);
    if record.is_empty() {
        return None;
    }
    let fields: Vec<&str> = record.split('\0').collect();
    let [sha, parents, author_name, author_email, author_date, subject, body] =
        fields.as_slice()
    else {
        return None;
    };
    Some(json!({
        "sha": sha,
        "parents": parents.split(' ').filter(|parent| !parent.is_empty()).collect::<Vec<_>>(),
        "authorName": author_name,
        "authorEmail": author_email,
        "authorDate": author_date.parse::<i64>().unwrap_or(0),
        "subject": subject,
        "body": body.trim_end_matches('\n'),
    }))
}

fn validate_sha(sha: &str) -> Result<()> {
    ensure!(
        matches!(sha.len(), 40 | 64) && sha.bytes().all(|b| b.is_ascii_hexdigit()),
        "Expected a full commit SHA"
    );
    Ok(())
}

fn resolve_commit(directory: &Path, reference: &str) -> Result<String> {
    ensure!(
        !reference.is_empty()
            && reference.len() <= 255
            && !reference.starts_with('-')
            && !reference.chars().any(char::is_control),
        "Invalid Git reference"
    );
    let oid = git(
        directory,
        &[
            "rev-parse",
            "--verify",
            "--quiet",
            &format!("{reference}^{{commit}}"),
        ],
    )?;
    let oid = String::from_utf8(oid)?.trim().to_owned();
    validate_sha(&oid)?;
    Ok(oid)
}

fn parse_name_status(text: &str) -> Result<Vec<(char, String, Option<String>)>> {
    let mut entries = Vec::new();
    let mut records = text.split('\0').filter(|record| !record.is_empty());
    while let Some(record) = records.next() {
        let (status, path) = record
            .split_once('\t')
            .context("Malformed name-status record")?;
        let kind = status.chars().next().context("Empty name-status record")?;
        let original = if kind == 'R' || kind == 'C' {
            Some(
                records
                    .next()
                    .context("Missing rename source")?
                    .to_owned(),
            )
        } else {
            None
        };
        entries.push((kind, path.to_owned(), original));
    }
    Ok(entries)
}

fn parse_numstat(text: &str) -> Vec<(String, u64, u64)> {
    let fields: Vec<&str> = text.split('\0').collect();
    let mut result = Vec::new();
    let mut index = 0;
    while index < fields.len() {
        let parts: Vec<&str> = fields[index].splitn(3, '\t').collect();
        index += 1;
        let [additions, deletions, path] = parts.as_slice() else {
            continue;
        };
        let mut path = (*path).to_owned();
        if path.is_empty() {
            if index + 1 >= fields.len() {
                break;
            }
            path = fields[index + 1].into();
            index += 2;
        }
        if path.is_empty() {
            continue;
        }
        result.push((
            path,
            additions.parse().unwrap_or(0),
            deletions.parse().unwrap_or(0),
        ));
    }
    result
}

fn status_letter(kind: char) -> &'static str {
    match kind {
        'A' | 'C' => "added",
        'D' => "deleted",
        'R' => "renamed",
        _ => "modified",
    }
}

fn files_from_status(
    entries: Vec<(char, String, Option<String>)>,
    counts: &HashMap<String, (u64, u64)>,
) -> Vec<Value> {
    entries
        .into_iter()
        .map(|(kind, path, original)| {
            let (additions, deletions) = counts.get(&path).copied().unwrap_or_default();
            json!({
                "path": path,
                "oldPath": original,
                "status": status_letter(kind),
                "additions": additions,
                "deletions": deletions,
            })
        })
        .collect()
}

fn range_patch(directory: &Path, args: &[&str]) -> Result<(String, bool)> {
    let (bytes, truncated) = git_with(
        directory,
        args,
        &GitOptions {
            timeout: Duration::from_secs(60),
            max_output: 2 * 1024 * 1024,
            truncate: true,
            ..GitOptions::default()
        },
    )?;
    Ok((String::from_utf8_lossy(&bytes).into_owned(), truncated))
}

pub fn commit_detail(directory: &Path, sha: &str) -> Result<Value> {
    validate_sha(sha)?;
    let oid = resolve_commit(directory, sha)?;
    let (meta, _) = git_with(
        directory,
        &[
            "log",
            "-1",
            "--format=%H%x00%P%x00%an%x00%ae%x00%at%x00%s%x00%b%x1e",
            &oid,
        ],
        &GitOptions {
            timeout: Duration::from_secs(60),
            ..GitOptions::default()
        },
    )?;
    let meta = String::from_utf8(meta)?;
    let commit = parse_log_record(&meta).context("Commit not found")?;
    let status_bytes = git(
        directory,
        &["show", "--format=", "--name-status", "-z", "--root", &oid],
    )?;
    let entries = parse_name_status(&String::from_utf8_lossy(&status_bytes))?;
    let numstat_bytes = git(
        directory,
        &["show", "--format=", "--numstat", "-z", "--root", &oid],
    )?;
    let counts: HashMap<String, (u64, u64)> = parse_numstat(&String::from_utf8_lossy(&numstat_bytes))
        .into_iter()
        .map(|(path, additions, deletions)| (path, (additions, deletions)))
        .collect();
    let files = files_from_status(entries, &counts);
    let (patch, truncated) = range_patch(
        directory,
        &[
            "show",
            "--format=",
            "--patch",
            "--no-ext-diff",
            "--no-textconv",
            "--no-color",
            &oid,
        ],
    )?;
    Ok(json!({"commit": commit, "files": files, "diff": patch, "truncated": truncated}))
}

pub fn diff_range(directory: &Path, from: &str, to: &str) -> Result<Value> {
    let from = resolve_commit(directory, from)?;
    let to = resolve_commit(directory, to)?;
    let range = format!("{from}...{to}");
    let status_bytes = git(
        directory,
        &["diff", "--name-status", "-z", "--no-color", &range],
    )?;
    let entries = parse_name_status(&String::from_utf8_lossy(&status_bytes))?;
    let numstat_bytes = git(
        directory,
        &["diff", "--numstat", "-z", "--no-color", &range],
    )?;
    let counts: HashMap<String, (u64, u64)> = parse_numstat(&String::from_utf8_lossy(&numstat_bytes))
        .into_iter()
        .map(|(path, additions, deletions)| (path, (additions, deletions)))
        .collect();
    let files = files_from_status(entries, &counts);
    let (patch, truncated) = range_patch(
        directory,
        &[
            "diff",
            "--patch",
            "--no-ext-diff",
            "--no-textconv",
            "--no-color",
            &range,
        ],
    )?;
    Ok(json!({"from": from, "to": to, "files": files, "diff": patch, "truncated": truncated}))
}

pub fn branch_diff(directory: &Path) -> Result<Value> {
    crate::workspace_diff::review(directory, crate::workspace_diff::Scope::Branch, false)
}

pub fn files(directory: &Path, query: &str, limit: usize) -> Result<Value> {
    ensure!((1..=5000).contains(&limit), "Limit must be 1–5000");
    let bytes = git(
        directory,
        &[
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        ],
    )?;
    let query = query.to_lowercase();
    let mut paths = bytes
        .split(|b| *b == 0)
        .filter(|path| !path.is_empty())
        .map(std::str::from_utf8)
        .collect::<std::result::Result<Vec<_>, _>>()?;
    paths.sort_unstable();
    paths.dedup();
    paths.retain(|path| path.to_lowercase().contains(&query));
    let total = paths.len();
    paths.truncate(limit);
    Ok(json!({"files":paths,"total":total,"truncated":total>limit}))
}

/// Composer completion includes folders derived from Git's literal paths. This
/// stays distinct from the public file-list API, and never reads file bodies.
pub(crate) fn composer_paths(directory: &Path, query: &str, limit: usize) -> Result<Value> {
    let bytes = git(
        directory,
        &[
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        ],
    )?;
    composer_path_results(&bytes, query, limit)
}
pub(crate) fn composer_path_results(bytes: &[u8], query: &str, limit: usize) -> Result<Value> {
    ensure!(
        (1..=80).contains(&limit),
        "Composer result limit must be 1–80"
    );
    let mut entries = std::collections::BTreeMap::<String, bool>::new();
    let mut limited = false;
    for raw in bytes.split(|b| *b == 0).filter(|p| !p.is_empty()) {
        let path = std::str::from_utf8(raw).context("Project path is not UTF-8")?;
        if entries.len() >= 25_000 {
            limited = true;
            break;
        }
        entries.entry(path.to_owned()).or_insert(false);
        let mut parent = Path::new(path).parent();
        while let Some(folder) = parent.filter(|p| !p.as_os_str().is_empty()) {
            if entries.len() >= 25_000 {
                limited = true;
                break;
            }
            if let Some(folder) = folder.to_str() {
                entries.entry(folder.to_owned()).or_insert(true);
            }
            parent = folder.parent();
        }
    }
    let query = query.to_lowercase();
    let mut matches: Vec<_> = entries
        .into_iter()
        .filter_map(|(path, directory)| {
            let lower = path.to_lowercase();
            let name = lower.rsplit('/').next().unwrap_or(&lower);
            let depth = lower.bytes().filter(|b| *b == b'/').count();
            let rank = if query.is_empty() {
                if depth == 0 {
                    0
                } else {
                    return None;
                }
            } else if name == query {
                0
            } else if name.starts_with(&query) {
                1
            } else if lower.starts_with(&query) {
                2
            } else if name.contains(&query) {
                3
            } else if lower.contains(&query) {
                4
            } else if let Some(cost) = composer_subsequence_cost(query.as_bytes(), name.as_bytes())
            {
                1_000 + cost
            } else {
                let cost = composer_subsequence_cost(query.as_bytes(), lower.as_bytes())?;
                100_000 + cost
            };
            let directory_order = query.is_empty() && !directory;
            Some((
                rank,
                depth,
                directory_order,
                lower.chars().count(),
                lower,
                path,
            ))
        })
        .collect();
    matches.sort_unstable();
    let total = matches.len();
    let paths: Vec<_> = matches
        .into_iter()
        .take(limit)
        .map(|(_, _, _, _, _, path)| path)
        .collect();
    Ok(json!({"files":paths,"total":total,"truncated":limited || total>limit}))
}

// Same ranking rule as Swift's ComposerFileIndex: scattered byte runs first,
// then their span. Only matching is byte-based; emitted paths stay exact UTF-8.
fn composer_subsequence_cost(query: &[u8], text: &[u8]) -> Option<usize> {
    let mut position = 0;
    let mut previous = None;
    let mut first = None;
    let mut runs = 0;
    for byte in query {
        while position < text.len() && text[position] != *byte {
            position += 1;
        }
        if position == text.len() {
            return None;
        }
        if previous.is_none_or(|last| last + 1 != position) {
            runs += 1;
        }
        first.get_or_insert(position);
        previous = Some(position);
        position += 1;
    }
    Some(runs * 100 + previous?.saturating_sub(first?).min(99))
}

pub fn read_file(directory: &Path, path: &str, offset: usize, limit: usize) -> Result<Value> {
    ensure!((1..=5000).contains(&limit), "Line limit must be 1–5000");
    let relative = relative_path(path)?;
    let root = directory.canonicalize()?;
    let joined = root.join(relative);
    let meta = std::fs::symlink_metadata(&joined)?;
    ensure!(
        !meta.file_type().is_symlink(),
        "Refusing to operate on a symlink"
    );
    let file = joined.canonicalize()?;
    ensure!(
        file.starts_with(&root),
        "File is outside the project directory"
    );
    ensure!(file.is_file(), "Path is not a regular file");
    let mut bytes = Vec::new();
    std::fs::File::open(file)?
        .take((MAX_OUTPUT + 1) as u64)
        .read_to_end(&mut bytes)?;
    ensure!(bytes.len() <= MAX_OUTPUT, "File exceeds 3 MiB");
    ensure!(!bytes.contains(&0), "File is binary");
    let body = std::str::from_utf8(&bytes).context("File is not UTF-8 text")?;
    let lines = body.lines().collect::<Vec<_>>();
    let total = lines.len();
    let end = offset.saturating_add(limit).min(total);
    let selected = lines.get(offset..end).unwrap_or_default().join("\n");
    Ok(
        json!({"path":path,"text":selected,"lineOffset":offset,"totalLines":total,"truncated":end<total}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn composer_folder_results_narrow_paths_and_preserve_public_file_list_contract() {
        let paths =
            "src/café.rs\0src/deep/main.rs\0src/deep/main.rs\0top.rs\0white space/child.rs\0";
        let top = composer_path_results(paths.as_bytes(), "", 80).unwrap();
        assert_eq!(top["files"], json!(["src", "white space", "top.rs"]));
        let nested = composer_path_results(paths.as_bytes(), "src/", 80).unwrap();
        assert_eq!(
            nested["files"],
            json!(["src/deep", "src/café.rs", "src/deep/main.rs"])
        );
        let limited = composer_path_results(paths.as_bytes(), "src", 1).unwrap();
        assert_eq!(limited["files"], json!(["src"]));
        assert_eq!(limited["total"], 4);
        assert_eq!(limited["truncated"], true);
        assert_eq!(
            composer_path_results(paths.as_bytes(), "CAFÉ", 80).unwrap()["files"],
            json!(["src/café.rs"])
        );
        assert_eq!(
            composer_path_results(paths.as_bytes(), "cf", 80).unwrap()["files"],
            json!(["src/café.rs"])
        );
        assert_eq!(
            composer_path_results(paths.as_bytes(), "sdp", 80).unwrap()["files"],
            json!(["src/deep", "src/deep/main.rs"])
        );
        assert_eq!(composer_subsequence_cost(b"ab", b"xxab"), Some(101));
        assert_eq!(composer_subsequence_cost(b"ab", b"axxb"), Some(203));
        assert!(composer_path_results(&[255, 0], "", 80).is_err());
        assert!(composer_path_results(paths.as_bytes(), "", 81).is_err());
    }
    #[test]
    fn repository_status_diff_and_literal_file_paths() {
        let dir = tempfile::tempdir().unwrap();
        git(dir.path(), &["init", "-q"]).unwrap();
        std::fs::write(dir.path().join("[fixture].txt"), "line one\nline two\n").unwrap();
        let state = status(dir.path()).unwrap();
        assert_eq!(state["entries"][0]["path"], "[fixture].txt");
        git(dir.path(), &["add", "--", "[fixture].txt"]).unwrap();
        assert!(
            diff(dir.path(), Some("[fixture].txt"), true).unwrap()["diff"]
                .as_str()
                .unwrap()
                .contains("+line one")
        );
        assert_eq!(files(dir.path(), "FIXTURE", 10).unwrap()["total"], 1);
        assert_eq!(
            read_file(dir.path(), "[fixture].txt", 1, 1).unwrap()["text"],
            "line two"
        );
        assert!(read_file(dir.path(), "../outside", 0, 10).is_err());
        std::fs::write(dir.path().join("binary"), [0, 1]).unwrap();
        assert!(read_file(dir.path(), "binary", 0, 10).is_err());
        #[cfg(unix)]
        {
            let outside = tempfile::NamedTempFile::new().unwrap();
            std::os::unix::fs::symlink(outside.path(), dir.path().join("escape")).unwrap();
            assert!(read_file(dir.path(), "escape", 0, 10).is_err());
        }
    }
    #[test]
    fn read_file_refuses_symlink_to_git_config() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir(root.join(".git")).unwrap();
        std::fs::write(root.join(".git").join("config"), "[core]\n").unwrap();
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(".git/config", root.join("leak")).unwrap();
            assert!(read_file(root, "leak", 0, 10).is_err());
        }
    }
    #[test]
    fn git_history_lists_commits_and_shows_files_and_range_diffs() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        git(root, &["init", "-q"]).unwrap();
        let identity = [
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "-c",
            "commit.gpgSign=false",
        ];
        let commit = |message: &str| {
            let mut args = identity.to_vec();
            args.extend(["commit", "-qm", message]);
            git(root, &args).unwrap();
        };
        std::fs::write(root.join("a.txt"), "one\n").unwrap();
        git(root, &["add", "--", "a.txt"]).unwrap();
        commit("first");
        std::fs::write(root.join("a.txt"), "one\ntwo\n").unwrap();
        std::fs::write(root.join("b.txt"), "bee\n").unwrap();
        git(root, &["add", "--", "a.txt", "b.txt"]).unwrap();
        commit("second");
        let head = String::from_utf8(git(root, &["rev-parse", "HEAD"]).unwrap())
            .unwrap()
            .trim()
            .to_owned();
        let history = log(root, 10, 0).unwrap();
        let commits = history["commits"].as_array().unwrap();
        assert_eq!(commits.len(), 2);
        assert_eq!(commits[0]["subject"], "second");
        assert_eq!(commits[1]["subject"], "first");
        assert_eq!(commits[0]["parents"].as_array().unwrap().len(), 1);
        assert_eq!(commits[1]["parents"].as_array().unwrap().len(), 0);
        assert!(commits[0]["authorDate"].as_i64().unwrap() > 0);
        assert_eq!(log(root, 1, 1).unwrap()["commits"][0]["subject"], "first");
        assert!(log(root, 0, 0).is_err());
        assert!(log(root, 201, 0).is_err());
        let detail = commit_detail(root, &head).unwrap();
        assert_eq!(detail["commit"]["subject"], "second");
        assert_eq!(detail["files"].as_array().unwrap().len(), 2);
        assert!(detail["diff"].as_str().unwrap().contains("+two"));
        assert!(detail["diff"].as_str().unwrap().contains("b.txt"));
        assert!(commit_detail(root, &"0".repeat(40)).is_err());
        assert!(commit_detail(root, "not-a-sha").is_err());
        assert!(commit_detail(root, "--output=/tmp/pwned").is_err());
        assert!(commit_detail(root, "--upload-pack=x").is_err());
        let first = commits[1]["sha"].as_str().unwrap().to_owned();
        let range = diff_range(root, &first, &head).unwrap();
        assert_eq!(range["from"], first);
        assert_eq!(range["to"], head);
        assert_eq!(range["files"].as_array().unwrap().len(), 2);
        assert!(range["diff"].as_str().unwrap().contains("+two"));
        assert!(diff_range(root, "nope", &head).is_err());
        assert!(diff_range(root, &first, "--bad").is_err());
        assert!(diff_range(root, "--output=/tmp/pwned", &head).is_err());
        assert!(diff_range(root, &first, "--upload-pack=touch${IFS}/tmp/pwned").is_err());
        assert!(diff_range(root, "--ext-diff", &head).is_err());
        let branch = branch_diff(root).unwrap();
        assert_eq!(branch["patch"], "");
    }
}
