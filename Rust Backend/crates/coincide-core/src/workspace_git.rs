//! Local Git primitives. Checkpoints capture the index, never unstaged/untracked data.
//! Slice 10 amendment: reset and clean are now allowed, only inside the named,
//! confirmation-gated functions below (rollback, restore_checkpoint); checkout,
//! worktree removal, network and user hook execution remain excluded everywhere.
use crate::workspace::{GitRequest, external_git_path, git, git_output};
use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};
use std::path::{Component, Path};
use uuid::Uuid;

fn text(directory: &Path, args: &[&str]) -> Result<String> {
    Ok(String::from_utf8(git(directory, args)?)?.trim().to_owned())
}

pub fn validate_oid(oid: &str) -> Result<()> {
    ensure!(
        matches!(oid.len(), 40 | 64) && oid.bytes().all(|b| b.is_ascii_hexdigit()),
        "Expected a full Git object ID"
    );
    Ok(())
}

fn root(directory: &Path) -> Result<()> {
    let top = text(directory, &["rev-parse", "--show-toplevel"])?;
    ensure!(
        Path::new(&top).canonicalize()? == directory.canonicalize()?,
        "Operation requires the repository root"
    );
    Ok(())
}

pub fn validate_branch(directory: &Path, branch: &str) -> Result<()> {
    ensure!(
        !branch.is_empty()
            && branch.len() <= 200
            && !branch.starts_with('-')
            && !branch.contains('@')
            && !branch.chars().any(char::is_control),
        "Invalid branch name"
    );
    git(
        directory,
        &["check-ref-format", &format!("refs/heads/{branch}")],
    )?;
    Ok(())
}

fn checkpoint_ref(id: &str) -> Result<String> {
    let uuid = Uuid::parse_str(id).context("Invalid checkpoint ID")?;
    ensure!(uuid.to_string() == id, "Expected canonical checkpoint ID");
    Ok(format!("refs/coincide/checkpoints/{id}"))
}

/// Creates an immutable staged snapshot, preserving index, branch and working files.
/// expected_head detects a stale UI selection. The snapshot's parent is that head even
/// if an external process subsequently moves the branch. Unmerged indexes fail closed.
pub fn create_checkpoint(directory: &Path, expected_head: &str, label: &str) -> Result<Value> {
    root(directory)?;
    validate_oid(expected_head)?;
    ensure!(
        !label.trim().is_empty() && label.len() <= 500 && !label.contains('\0'),
        "Invalid checkpoint label"
    );
    let head = text(directory, &["rev-parse", "--verify", "HEAD"])?;
    ensure!(
        head == expected_head,
        "HEAD changed; refresh before checkpointing"
    );
    let tree = text(directory, &["write-tree"])?;
    let commit = text(
        directory,
        &[
            "-c",
            "user.name=Coincide",
            "-c",
            "user.email=checkpoint@coincide.invalid",
            "-c",
            "commit.gpgSign=false",
            "commit-tree",
            &tree,
            "-p",
            &head,
            "-m",
            label,
        ],
    )?;
    validate_oid(&commit)?;
    let id = Uuid::new_v4().to_string();
    let reference = checkpoint_ref(&id)?;
    // Empty old value requires an absent reference (compare-and-swap).
    git(directory, &["update-ref", &reference, &commit, ""])?;
    Ok(json!({"id":id,"commit":commit,"parent":head,"tree":tree,"scope":"staged"}))
}

pub fn checkpoints(directory: &Path) -> Result<Value> {
    let data = text(
        directory,
        &[
            "for-each-ref",
            "--sort=-creatordate",
            "--format=%(refname) %(objectname)",
            "refs/coincide/checkpoints/",
        ],
    )?;
    let mut entries = Vec::new();
    for line in data.lines() {
        let (reference, commit) = line.split_once(' ').context("Malformed checkpoint ref")?;
        let id = reference
            .strip_prefix("refs/coincide/checkpoints/")
            .context("Invalid checkpoint namespace")?;
        // Per-turn snapshots (<thread>/<turn>/<phase>, also written by the
        // Swift app) share the namespace; only staged checkpoints are listed.
        if id.contains('/') {
            continue;
        }
        checkpoint_ref(id)?;
        validate_oid(commit)?;
        entries.push(json!({"id":id,"commit":commit}));
    }
    Ok(json!({"checkpoints":entries}))
}

pub fn checkpoint_diff(directory: &Path, id: &str) -> Result<Value> {
    let reference = checkpoint_ref(id)?;
    let commit = text(
        directory,
        &["rev-parse", "--verify", &format!("{reference}^{{commit}}")],
    )?;
    validate_oid(&commit)?;
    let diff = String::from_utf8(git(
        directory,
        &[
            "diff",
            "--no-ext-diff",
            "--no-textconv",
            "--no-color",
            &format!("{commit}^"),
            &commit,
            "--",
        ],
    )?)?;
    Ok(json!({"id":id,"commit":commit,"diff":diff}))
}

pub fn worktrees(directory: &Path) -> Result<Value> {
    let bytes = git(directory, &["worktree", "list", "--porcelain", "-z"])?;
    let mut entries = Vec::new();
    let mut entry = serde_json::Map::new();
    for record in bytes.split(|b| *b == 0) {
        if record.is_empty() {
            if !entry.is_empty() {
                entries.push(Value::Object(std::mem::take(&mut entry)));
            }
            continue;
        }
        let record = std::str::from_utf8(record)?;
        let (key, value) = record.split_once(' ').unwrap_or((record, ""));
        entry.insert(
            key.into(),
            if value.is_empty() {
                json!(true)
            } else {
                json!(value)
            },
        );
    }
    if !entry.is_empty() {
        entries.push(Value::Object(entry));
    }
    Ok(json!({"worktrees":entries}))
}

/// Reserve a new branch and empty linked worktree at an exact commit. No checkout
/// means repository smudge filters cannot execute. A separate reviewed checkout
/// flow is required to populate files. Existing destinations are never overwritten.
pub fn create_worktree(
    directory: &Path,
    parent: &Path,
    name: &str,
    branch: &str,
    base: &str,
) -> Result<Value> {
    root(directory)?;
    validate_branch(directory, branch)?;
    validate_oid(base)?;
    ensure!(
        name.len() <= 128
            && name
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_')),
        "Use a portable worktree name containing only letters, digits, hyphens and underscores"
    );
    ensure!(
        !matches!(
            name.to_ascii_uppercase().as_str(),
            "CON"
                | "PRN"
                | "AUX"
                | "NUL"
                | "COM1"
                | "COM2"
                | "COM3"
                | "COM4"
                | "COM5"
                | "COM6"
                | "COM7"
                | "COM8"
                | "COM9"
                | "LPT1"
                | "LPT2"
                | "LPT3"
                | "LPT4"
                | "LPT5"
                | "LPT6"
                | "LPT7"
                | "LPT8"
                | "LPT9"
        ),
        "Reserved worktree name"
    );
    let components = Path::new(name).components().collect::<Vec<_>>();
    ensure!(
        components.len() == 1
            && matches!(components[0], Component::Normal(_))
            && !name.starts_with('-')
            && !name.contains(['/', '\\'])
            && !name.chars().any(char::is_control),
        "Expected a single worktree directory name"
    );
    ensure!(parent.is_absolute(), "Worktree parent must be absolute");
    let parent = parent.canonicalize()?;
    ensure!(
        !parent.starts_with(directory.canonicalize()?),
        "Worktree must be outside the source checkout"
    );
    let destination = parent.join(name);
    ensure!(
        std::fs::symlink_metadata(&destination)
            .is_err_and(|e| e.kind() == std::io::ErrorKind::NotFound),
        "Worktree destination already exists or is inaccessible"
    );
    let external_destination = external_git_path(&destination)?;
    let destination_text = external_destination
        .to_str()
        .context("Worktree path is not UTF-8")?;
    ensure!(
        text(directory, &["cat-file", "-t", base])? == "commit",
        "Base must be a commit object"
    );
    git(
        directory,
        &[
            "worktree",
            "add",
            "--no-checkout",
            "-b",
            branch,
            "--",
            destination_text,
            base,
        ],
    )?;
    Ok(json!({"path":destination_text,"branch":branch,"head":base,"populated":false}))
}

pub fn validate_relative_path(path: &str) -> Result<()> {
    ensure!(
        !path.is_empty()
            && path.len() <= 4096
            && !path.starts_with('/')
            && !path.contains('\0')
            && Path::new(path)
                .components()
                .all(|part| matches!(part, Component::Normal(_))),
        "Use a relative path without dot or parent components"
    );
    Ok(())
}

fn resolve_ref(directory: &Path, reference: &str) -> Result<String> {
    ensure!(
        !reference.is_empty()
            && reference.len() <= 255
            && !reference.starts_with('-')
            && !reference.chars().any(char::is_control),
        "Invalid Git reference"
    );
    let oid = text(
        directory,
        &[
            "rev-parse",
            "--verify",
            "--quiet",
            &format!("{reference}^{{commit}}"),
        ],
    )?;
    validate_oid(&oid)?;
    Ok(oid)
}

fn stash_reference(reference: &str) -> Result<String> {
    let rest = reference
        .strip_prefix("stash@{")
        .context("Expected a stash reference such as stash@{0}")?;
    let digits = rest
        .strip_suffix('}')
        .context("Expected a stash reference such as stash@{0}")?;
    ensure!(
        !digits.is_empty()
            && digits.len() <= 6
            && digits.bytes().all(|b| b.is_ascii_digit()),
        "Expected a stash reference such as stash@{0}"
    );
    let index: usize = digits.parse().context("Invalid stash index")?;
    ensure!(index <= 100_000, "Stash index is too large");
    Ok(format!("stash@{{{index}}}"))
}

fn conflicted_files(directory: &Path) -> Result<Vec<String>> {
    let bytes = git(directory, &["diff", "--name-only", "--diff-filter=U", "-z"])?;
    Ok(bytes
        .split(|b| *b == 0)
        .filter(|record| !record.is_empty())
        .map(|record| String::from_utf8_lossy(record).into_owned())
        .collect())
}

pub fn stash(
    directory: &Path,
    action: &str,
    message: Option<&str>,
    include_untracked: bool,
    reference: Option<&str>,
    confirm: bool,
    paths: Option<Vec<String>>,
) -> Result<Value> {
    match action {
        "list" => {
            let out = String::from_utf8_lossy(&git(
                directory,
                &["stash", "list", "--format=%gd%x00%H%x00%s%x1e"],
            )?)
            .into_owned();
            let mut entries = Vec::new();
            for record in out.split('\u{1e}') {
                let record = record.trim();
                if record.is_empty() {
                    continue;
                }
                let fields: Vec<&str> = record.split('\0').collect();
                let [reference, commit, subject] = fields.as_slice() else {
                    continue;
                };
                entries.push(json!({"reference": reference, "commit": commit, "subject": subject}));
            }
            Ok(json!({"stashes": entries}))
        }
        "show" => {
            let reference = stash_reference(
                reference.context("Stash show requires a reference such as stash@{0}")?,
            )?;
            let oid = resolve_ref(directory, &reference)?;
            let diff = String::from_utf8(git(
                directory,
                &[
                    "stash",
                    "show",
                    "--patch",
                    "--no-ext-diff",
                    "--no-textconv",
                    "--no-color",
                    &reference,
                ],
            )?)?;
            Ok(json!({"reference": reference, "commit": oid, "diff": diff}))
        }
        "push" => {
            if let Some(paths) = &paths {
                for path in paths {
                    validate_relative_path(path)?;
                }
            }
            if let Some(message) = message {
                ensure!(
                    !message.is_empty() && message.len() <= 500 && !message.contains('\0'),
                    "Invalid stash message"
                );
            }
            let mut args: Vec<String> = vec!["stash".into(), "push".into()];
            if include_untracked {
                args.push("--include-untracked".into());
            }
            if let Some(message) = message {
                args.push("-m".into());
                args.push(message.to_owned());
            }
            if let Some(paths) = &paths {
                if !paths.is_empty() {
                    args.push("--".into());
                    for path in paths {
                        args.push(path.clone());
                    }
                }
            }
            let arg_refs: Vec<&str> = args.iter().map(String::as_str).collect();
            let output = String::from_utf8(git(directory, &arg_refs)?)?;
            Ok(json!({"pushed": true, "output": output.trim()}))
        }
        "pop" => {
            ensure!(confirm, "Stash pop is destructive; pass confirm=true");
            let reference = stash_reference(
                reference.context("Stash pop requires a reference such as stash@{0}")?,
            )?;
            let output = git_output(directory, &["stash", "pop", &reference], &GitRequest::default())?;
            if output.success {
                Ok(json!({"popped": true, "reference": reference}))
            } else {
                Ok(json!({"popped": false, "reference": reference, "conflicts": conflicted_files(directory)?, "message": output.stderr_text()}))
            }
        }
        "drop" => {
            ensure!(confirm, "Stash drop is destructive; pass confirm=true");
            let reference = stash_reference(
                reference.context("Stash drop requires a reference such as stash@{0}")?,
            )?;
            git(directory, &["stash", "drop", &reference])?;
            Ok(json!({"dropped": true, "reference": reference}))
        }
        _ => bail!("Unknown stash action"),
    }
}

pub fn blame(directory: &Path, path: &str, start: Option<usize>, end: Option<usize>) -> Result<Value> {
    validate_relative_path(path)?;
    let mut args: Vec<String> = vec!["blame".into(), "--line-porcelain".into()];
    if let (Some(start), Some(end)) = (start, end) {
        ensure!(
            start >= 1 && end >= start && end <= 1_000_000,
            "Invalid blame line range"
        );
        args.push("-L".into());
        args.push(format!("{start},{end}"));
    }
    args.push("--".into());
    args.push(path.to_owned());
    let arg_refs: Vec<&str> = args.iter().map(String::as_str).collect();
    let out = String::from_utf8(git(directory, &arg_refs)?)?;
    let mut entries = Vec::new();
    let mut lines = out.lines();
    while let Some(header) = lines.next() {
        let mut fields = header.split(' ');
        let sha = fields.next().unwrap_or("");
        ensure!(
            matches!(sha.len(), 40 | 64) && sha.bytes().all(|b| b.is_ascii_hexdigit()),
            "Malformed blame output"
        );
        let _original = fields.next().context("Malformed blame output")?;
        let final_line: usize = fields
            .next()
            .and_then(|value| value.parse().ok())
            .context("Malformed blame output")?;
        let mut author = String::new();
        let mut author_email = String::new();
        let mut author_time: i64 = 0;
        let mut summary = String::new();
        let mut content = String::new();
        loop {
            let line = lines.next().context("Malformed blame output")?;
            if let Some(text) = line.strip_prefix('\t') {
                content = text.to_owned();
                break;
            }
            if let Some(value) = line.strip_prefix("author ") {
                author = value.to_owned();
            } else if let Some(value) = line.strip_prefix("author-mail ") {
                author_email = value.trim_matches(['<', '>']).to_owned();
            } else if let Some(value) = line.strip_prefix("author-time ") {
                author_time = value.parse().unwrap_or(0);
            } else if let Some(value) = line.strip_prefix("summary ") {
                summary = value.to_owned();
            }
        }
        entries.push(json!({"line": final_line, "sha": sha, "author": author, "authorEmail": author_email, "authorTime": author_time, "summary": summary, "content": content}));
    }
    Ok(json!({"path": path, "lines": entries}))
}

pub fn bisect(
    directory: &Path,
    action: &str,
    reference: Option<&str>,
    good: Option<&str>,
    bad: Option<&str>,
) -> Result<Value> {
    match action {
        "start" => {
            let good = resolve_ref(
                directory,
                good.context("Bisect start requires a known-good reference")?,
            )?;
            let bad = resolve_ref(
                directory,
                bad.context("Bisect start requires a known-bad reference")?,
            )?;
            let output = String::from_utf8(git(directory, &["bisect", "start", &bad, &good])?)?;
            let head = text(directory, &["rev-parse", "--verify", "HEAD"])?;
            Ok(json!({"started": true, "good": good, "bad": bad, "head": head, "output": output.trim()}))
        }
        "good" | "bad" | "skip" => {
            let mut args: Vec<String> = vec!["bisect".into(), action.into()];
            if let Some(reference) = reference {
                args.push(resolve_ref(directory, reference)?);
            }
            let arg_refs: Vec<&str> = args.iter().map(String::as_str).collect();
            let output = String::from_utf8(git(directory, &arg_refs)?)?;
            let head = text(directory, &["rev-parse", "--verify", "HEAD"])?;
            Ok(json!({"action": action, "head": head, "output": output.trim()}))
        }
        "reset" => {
            git(directory, &["bisect", "reset"])?;
            let head = text(directory, &["rev-parse", "--verify", "HEAD"])?;
            Ok(json!({"reset": true, "head": head}))
        }
        "log" => {
            let output = String::from_utf8(git(directory, &["bisect", "log"])?)?;
            Ok(json!({"log": output}))
        }
        _ => bail!("Unknown bisect action"),
    }
}

pub fn cherry_pick(directory: &Path, sha: &str, no_commit: bool, confirm: bool) -> Result<Value> {
    ensure!(
        confirm,
        "Cherry-pick changes the working tree; pass confirm=true"
    );
    validate_oid(sha)?;
    let oid = resolve_ref(directory, sha)?;
    let mut args: Vec<&str> = vec!["cherry-pick"];
    if no_commit {
        args.push("--no-commit");
    }
    args.push(&oid);
    let output = git_output(directory, &args, &GitRequest::default())?;
    if output.success {
        let head = text(directory, &["rev-parse", "--verify", "HEAD"])?;
        Ok(json!({"applied": true, "sha": oid, "head": head, "noCommit": no_commit}))
    } else {
        Ok(json!({"applied": false, "sha": oid, "conflicts": conflicted_files(directory)?, "message": output.stderr_text()}))
    }
}

pub fn validate_rollback_ref(reference: &str) -> Result<()> {
    if reference == "HEAD" {
        return Ok(());
    }
    for prefix in ["HEAD~", "HEAD^"] {
        if let Some(rest) = reference.strip_prefix(prefix) {
            ensure!(
                !rest.is_empty()
                    && rest.len() <= 4
                    && rest.bytes().all(|b| b.is_ascii_digit()),
                "Rollback ref must be HEAD, HEAD~N, HEAD^N, or a full commit SHA"
            );
            let steps: usize = rest.parse().context("Invalid rollback ref")?;
            ensure!(
                (1..=1000).contains(&steps),
                "Rollback ref must be HEAD, HEAD~N, HEAD^N, or a full commit SHA"
            );
            return Ok(());
        }
    }
    validate_oid(reference)
}

pub fn rollback(directory: &Path, reference: &str, confirm: bool) -> Result<Value> {
    ensure!(
        confirm,
        "Rollback discards uncommitted changes; pass confirm=true"
    );
    validate_rollback_ref(reference)?;
    let oid = resolve_ref(directory, reference)?;
    git(directory, &["reset", "--hard", &oid])?;
    let head = text(directory, &["rev-parse", "--verify", "HEAD"])?;
    Ok(json!({"rolledBack": true, "ref": reference, "head": head}))
}

pub fn restore_checkpoint(directory: &Path, id: &str, confirm: bool) -> Result<Value> {
    ensure!(
        confirm,
        "Restoring a checkpoint discards uncommitted and untracked changes; pass confirm=true"
    );
    root(directory)?;
    let reference = checkpoint_ref(id)?;
    let commit = text(
        directory,
        &["rev-parse", "--verify", &format!("{reference}^{{commit}}")],
    )?;
    validate_oid(&commit)?;
    git(directory, &["reset", "--hard", &commit])?;
    git(directory, &["clean", "-fdx"])?;
    let head = text(directory, &["rev-parse", "--verify", "HEAD"])?;
    Ok(json!({"restored": true, "id": id, "commit": commit, "head": head}))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture_repo() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        git(root, &["init", "-q", "-b", "main"]).unwrap();
        for (key, value) in [
            ("user.name", "Fixture"),
            ("user.email", "fixture@example.invalid"),
            ("commit.gpgSign", "false"),
            ("core.autocrlf", "false"),
        ] {
            git(root, &["config", key, value]).unwrap();
        }
        dir
    }

    fn commit(root: &Path, message: &str) {
        git(root, &["add", "-A"]).unwrap();
        let identity = [
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "-c",
            "commit.gpgSign=false",
        ];
        let mut args = identity.to_vec();
        args.extend(["commit", "-qm", message]);
        git(root, &args).unwrap();
    }

    fn head(root: &Path) -> String {
        String::from_utf8(git(root, &["rev-parse", "--verify", "HEAD"]).unwrap())
            .unwrap()
            .trim()
            .to_owned()
    }

    fn read(root: &Path, name: &str) -> String {
        std::fs::read_to_string(root.join(name)).unwrap()
    }

    #[test]
    fn stash_push_list_show_pop_and_drop_round_trip() {
        let dir = fixture_repo();
        let root = dir.path();
        std::fs::write(root.join("a.txt"), "one\n").unwrap();
        commit(root, "first");
        std::fs::write(root.join("a.txt"), "one\ntwo\n").unwrap();
        let pushed = stash(root, "push", Some("work in progress"), false, None, false, None).unwrap();
        assert_eq!(pushed["pushed"], true);
        assert_eq!(read(root, "a.txt"), "one\n");
        let listed = stash(root, "list", None, false, None, false, None).unwrap();
        let stashes = listed["stashes"].as_array().unwrap();
        assert_eq!(stashes.len(), 1);
        assert_eq!(stashes[0]["reference"], "stash@{0}");
        assert_eq!(stashes[0]["subject"], "On main: work in progress");
        let shown = stash(root, "show", None, false, Some("stash@{0}"), false, None).unwrap();
        assert!(shown["diff"].as_str().unwrap().contains("+two"));
        assert!(stash(root, "pop", None, false, Some("stash@{0}"), false, None).is_err());
        let popped = stash(root, "pop", None, false, Some("stash@{0}"), true, None).unwrap();
        assert_eq!(popped["popped"], true);
        assert_eq!(read(root, "a.txt"), "one\ntwo\n");
        assert_eq!(
            stash(root, "list", None, false, None, false, None).unwrap()["stashes"]
                .as_array()
                .unwrap()
                .len(),
            0
        );
        stash(root, "push", None, false, None, false, None).unwrap();
        assert!(stash(root, "drop", None, false, Some("stash@{0}"), false, None).is_err());
        let dropped = stash(root, "drop", None, false, Some("stash@{0}"), true, None).unwrap();
        assert_eq!(dropped["dropped"], true);
        assert!(stash(root, "show", None, false, Some("stash@{9}"), false, None).is_err());
        assert!(stash(root, "show", None, false, Some("not-a-stash"), false, None).is_err());
        assert!(stash(root, "explode", None, false, None, false, None).is_err());
    }

    #[test]
    fn blame_reports_authors_and_line_numbers() {
        let dir = fixture_repo();
        let root = dir.path();
        std::fs::write(root.join("a.txt"), "alpha\nbeta\n").unwrap();
        commit(root, "first");
        let blamed = blame(root, "a.txt", None, None).unwrap();
        let lines = blamed["lines"].as_array().unwrap();
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0]["line"], 1);
        assert_eq!(lines[0]["author"], "Fixture");
        assert_eq!(lines[0]["authorEmail"], "fixture@example.invalid");
        assert_eq!(lines[0]["content"], "alpha");
        assert_eq!(lines[1]["line"], 2);
        assert_eq!(lines[1]["content"], "beta");
        assert!(lines[0]["authorTime"].as_i64().unwrap() > 0);
        let ranged = blame(root, "a.txt", Some(2), Some(2)).unwrap();
        assert_eq!(ranged["lines"].as_array().unwrap().len(), 1);
        assert_eq!(ranged["lines"][0]["line"], 2);
        assert!(blame(root, "../escape.txt", None, None).is_err());
        assert!(blame(root, "missing.txt", None, None).is_err());
    }

    #[test]
    fn bisect_walks_to_the_midpoint_and_resets() {
        let dir = fixture_repo();
        let root = dir.path();
        std::fs::write(root.join("a.txt"), "one\n").unwrap();
        commit(root, "first");
        let first = head(root);
        std::fs::write(root.join("a.txt"), "one\ntwo\n").unwrap();
        commit(root, "second");
        let second = head(root);
        std::fs::write(root.join("a.txt"), "one\ntwo\nthree\n").unwrap();
        commit(root, "third");
        let third = head(root);
        let started = bisect(root, "start", None, Some(&first), Some(&third)).unwrap();
        assert_eq!(started["started"], true);
        assert_eq!(started["head"], second);
        let log = bisect(root, "log", None, None, None).unwrap();
        assert!(log["log"].as_str().unwrap().contains("git bisect start"));
        let marked = bisect(root, "good", None, None, None).unwrap();
        assert_eq!(marked["action"], "good");
        let reset = bisect(root, "reset", None, None, None).unwrap();
        assert_eq!(reset["reset"], true);
        assert_eq!(reset["head"], third);
        assert_eq!(head(root), third);
        assert!(bisect(root, "start", None, Some("nope"), Some(&third)).is_err());
    }

    #[test]
    fn cherry_pick_applies_and_reports_conflicts_without_aborting() {
        let dir = fixture_repo();
        let root = dir.path();
        std::fs::write(root.join("a.txt"), "base\n").unwrap();
        commit(root, "base");
        git(root, &["checkout", "-qb", "side"]).unwrap();
        std::fs::write(root.join("b.txt"), "side work\n").unwrap();
        commit(root, "side");
        let side = head(root);
        git(root, &["checkout", "-q", "main"]).unwrap();
        assert!(cherry_pick(root, &side, false, false).is_err());
        let applied = cherry_pick(root, &side, false, true).unwrap();
        assert_eq!(applied["applied"], true);
        assert_eq!(applied["sha"], side);
        assert_eq!(read(root, "b.txt"), "side work\n");
        assert!(cherry_pick(root, "not-a-sha", false, true).is_err());
        git(root, &["checkout", "-qb", "clash"]).unwrap();
        std::fs::write(root.join("a.txt"), "clash\n").unwrap();
        commit(root, "clash");
        let clash = head(root);
        git(root, &["checkout", "-q", "main"]).unwrap();
        std::fs::write(root.join("a.txt"), "main edit\n").unwrap();
        commit(root, "main edit");
        let conflicted = cherry_pick(root, &clash, false, true).unwrap();
        assert_eq!(conflicted["applied"], false);
        assert_eq!(conflicted["conflicts"][0], "a.txt");
        git(root, &["cherry-pick", "--abort"]).unwrap();
        assert_eq!(read(root, "a.txt"), "main edit\n");
    }

    #[test]
    fn rollback_only_accepts_the_strict_allow_list() {
        let dir = fixture_repo();
        let root = dir.path();
        std::fs::write(root.join("a.txt"), "one\n").unwrap();
        commit(root, "first");
        std::fs::write(root.join("a.txt"), "one\ntwo\n").unwrap();
        commit(root, "second");
        let second = head(root);
        std::fs::write(root.join("a.txt"), "dirty\n").unwrap();
        assert!(rollback(root, "HEAD", false).is_err());
        assert!(rollback(root, "main", true).is_err());
        assert!(rollback(root, "HEAD~99", true).is_err());
        let rolled = rollback(root, "HEAD", true).unwrap();
        assert_eq!(rolled["rolledBack"], true);
        assert_eq!(rolled["head"], second);
        assert_eq!(read(root, "a.txt"), "one\ntwo\n");
        let back = rollback(root, "HEAD~1", true).unwrap();
        assert_eq!(back["ref"], "HEAD~1");
        assert_eq!(read(root, "a.txt"), "one\n");
    }

    #[test]
    fn restore_checkpoint_resets_and_cleans_untracked_files() {
        let dir = fixture_repo();
        let root = dir.path();
        std::fs::write(root.join("a.txt"), "one\n").unwrap();
        commit(root, "first");
        std::fs::write(root.join("a.txt"), "one\ntwo\n").unwrap();
        git(root, &["add", "--", "a.txt"]).unwrap();
        let current = head(root);
        let created = create_checkpoint(root, &current, "before edit").unwrap();
        let id = created["id"].as_str().unwrap().to_owned();
        std::fs::write(root.join("a.txt"), "destroyed\n").unwrap();
        std::fs::write(root.join("scratch.txt"), "untracked\n").unwrap();
        assert!(restore_checkpoint(root, &id, false).is_err());
        assert!(restore_checkpoint(root, "not-a-uuid", true).is_err());
        let restored = restore_checkpoint(root, &id, true).unwrap();
        assert_eq!(restored["restored"], true);
        assert_eq!(restored["id"], id);
        assert_eq!(read(root, "a.txt"), "one\ntwo\n");
        assert!(!root.join("scratch.txt").exists());
        let listed = checkpoints(root).unwrap();
        assert_eq!(listed["checkpoints"].as_array().unwrap().len(), 1);
    }
}
