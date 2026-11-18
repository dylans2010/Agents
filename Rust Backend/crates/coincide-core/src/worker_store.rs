use crate::store::Store;
use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

pub const MAX_WORKER_NAME_CHARS: usize = 128;
pub const MAX_TASK_CHARS: usize = 500;
pub const MAX_TARGET_FILES: usize = 64;
pub const MAX_PLAN_STEPS: usize = 16;
pub const MAX_WORKERS_PER_PARENT: usize = 32;
pub const MAX_WORKER_RESULT_CHARS: usize = 64 * 1024;
pub const WORKER_RETENTION_SETTING: &str = "workerRetentionCount";
pub const DEFAULT_WORKER_RETENTION_COUNT: usize = 50;

pub fn truncate_worker_text(text: &str) -> String {
    if text.chars().count() <= MAX_WORKER_RESULT_CHARS {
        return text.to_owned();
    }
    let kept: String = text.chars().take(MAX_WORKER_RESULT_CHARS).collect();
    format!("{kept}\n[truncated: worker output exceeded 64 KiB; the full transcript remains on the worker thread]")
}

pub fn now_seconds() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn req_str(params: &Value, name: &str) -> Result<String> {
    params
        .get(name)
        .and_then(Value::as_str)
        .map(str::to_owned)
        .with_context(|| format!("Missing required parameter '{name}'"))
}

fn opt_str(params: &Value, name: &str) -> Option<String> {
    params.get(name).and_then(Value::as_str).map(str::to_owned)
}

fn opt_string_array(params: &Value, name: &str) -> Vec<String> {
    params
        .get(name)
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

pub fn validate_worker_name(raw: &str) -> Result<String> {
    let name = raw.trim();
    ensure!(!name.is_empty(), "Worker name must not be empty");
    ensure!(
        name.chars().count() <= MAX_WORKER_NAME_CHARS,
        "Worker name must be at most 128 characters"
    );
    ensure!(
        !name.chars().any(char::is_control),
        "Worker name must not contain control characters"
    );
    Ok(name.to_owned())
}

pub fn validate_task(raw: &str) -> Result<String> {
    let task = raw.trim();
    ensure!(!task.is_empty(), "Worker task must not be empty");
    ensure!(
        task.chars().count() <= MAX_TASK_CHARS,
        "Worker task must be at most 500 characters"
    );
    ensure!(
        !task.contains('\0'),
        "Worker task must not contain NUL bytes"
    );
    Ok(task.to_owned())
}

pub fn validate_target_files(raw: Vec<String>) -> Result<Vec<String>> {
    ensure!(
        raw.len() <= MAX_TARGET_FILES,
        "A worker may target at most 64 files"
    );
    let mut files: Vec<String> = Vec::new();
    for file in raw {
        let file = file.trim().to_owned();
        ensure!(!file.is_empty(), "Target file paths must not be empty");
        ensure!(
            !file.contains('\0'),
            "Target file paths must not contain NUL bytes"
        );
        ensure!(
            !files.contains(&file),
            "Target files must not contain duplicates"
        );
        files.push(file);
    }
    Ok(files)
}

#[derive(Clone, Debug)]
pub struct SpawnRequest {
    pub name: String,
    pub task: String,
    pub target_files: Vec<String>,
    pub parent_thread_id: String,
    pub assistant_id: Option<String>,
}

pub fn parse_spawn_request(params: &Value) -> Result<SpawnRequest> {
    let parent_thread_id = req_str(params, "parentThreadId")?;
    ensure!(
        !parent_thread_id.trim().is_empty(),
        "Parent thread ID must not be empty"
    );
    let assistant_id = match params.get("assistantId") {
        None | Some(Value::Null) => None,
        Some(value) => {
            let id = value.as_str().context("Assistant ID must be a UUID")?;
            Some(
                Uuid::parse_str(id)
                    .map(|parsed| parsed.to_string())
                    .context("Assistant ID must be a UUID")?,
            )
        }
    };
    Ok(SpawnRequest {
        name: validate_worker_name(&req_str(params, "name")?)?,
        task: validate_task(&req_str(params, "task")?)?,
        target_files: validate_target_files(opt_string_array(params, "targetFiles"))?,
        parent_thread_id,
        assistant_id,
    })
}

pub fn parse_batch_spawn_request(params: &Value) -> Result<(String, Vec<SpawnRequest>)> {
    let parent_thread_id = req_str(params, "parentThreadId")?;
    ensure!(
        !parent_thread_id.trim().is_empty(),
        "Parent thread ID must not be empty"
    );
    let workers = params
        .get("workers")
        .and_then(Value::as_array)
        .context("Missing required parameter 'workers'")?;
    ensure!(!workers.is_empty(), "At least one worker is required");
    ensure!(
        workers.len() <= MAX_WORKERS_PER_PARENT,
        "A single use_workers call may spawn at most 32 workers"
    );
    let mut requests: Vec<SpawnRequest> = Vec::new();
    for worker in workers {
        let mut shaped = worker.clone();
        if let Some(object) = shaped.as_object_mut() {
            object.insert(
                "parentThreadId".to_owned(),
                Value::String(parent_thread_id.clone()),
            );
        }
        requests.push(parse_spawn_request(&shaped)?);
    }
    let mut names: Vec<&str> = requests.iter().map(|r| r.name.as_str()).collect();
    names.sort_unstable();
    names.dedup();
    ensure!(
        names.len() == requests.len(),
        "Worker names must be unique within a batch"
    );
    let mut claimed: Vec<&str> = Vec::new();
    for request in &requests {
        for file in &request.target_files {
            ensure!(
                !claimed.contains(&file.as_str()),
                "Target files must be disjoint across workers in a batch"
            );
            claimed.push(file.as_str());
        }
    }
    Ok((parent_thread_id, requests))
}

pub fn worker_record_json(
    id: &str,
    request: &SpawnRequest,
    thread_id: &str,
    provider: &str,
    transcript_start: usize,
    started_at: f64,
) -> Value {
    json!({
        "id": id,
        "name": request.name,
        "parentThreadId": request.parent_thread_id,
        "threadId": thread_id,
        "task": request.task,
        "provider": provider,
        "targetFiles": request.target_files,
        "assistantId": request
            .assistant_id
            .clone()
            .map(Value::String)
            .unwrap_or(Value::Null),
        "status": "running",
        "cancelRequested": false,
        "transcriptStart": transcript_start,
        "transcriptItems": 0,
        "elapsedSeconds": 0.0,
        "createdAt": started_at,
        "startedAt": started_at,
        "completedAt": Value::Null,
        "error": Value::Null,
        "result": Value::Null,
    })
}

pub fn insert_record(
    store: &mut Store,
    request: &SpawnRequest,
    thread_id: &str,
    provider: &str,
    transcript_start: usize,
) -> Result<Value> {
    let id = uuid::Uuid::new_v4().to_string();
    let started_at = now_seconds();
    let record = worker_record_json(
        &id,
        request,
        thread_id,
        provider,
        transcript_start,
        started_at,
    );
    store.worker_upsert(&id, &record)?;
    prune_terminal_records(store, &request.parent_thread_id)?;
    Ok(record)
}

pub fn retention_limit(store: &Store) -> usize {
    let settings = store
        .document("settings.json")
        .ok()
        .flatten()
        .unwrap_or(json!({}));
    let raw = settings.get(WORKER_RETENTION_SETTING);
    let parsed = raw
        .and_then(Value::as_u64)
        .map(|value| value as usize)
        .or_else(|| raw.and_then(Value::as_f64).map(|value| value.max(0.0) as usize));
    parsed.unwrap_or(DEFAULT_WORKER_RETENTION_COUNT)
}

pub fn prune_terminal_records(store: &mut Store, parent_thread_id: &str) -> Result<()> {
    let keep = retention_limit(store);
    if keep == 0 {
        return Ok(());
    }
    let mut terminal: Vec<Value> = load_workers(store)?
        .into_iter()
        .filter(|record| {
            record.get("parentThreadId").and_then(Value::as_str) == Some(parent_thread_id)
                && record
                    .get("status")
                    .and_then(Value::as_str)
                    .is_some_and(|status| is_terminal(status))
        })
        .collect();
    terminal.sort_by(|a, b| {
        let ca = a.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0);
        let cb = b.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0);
        cb.partial_cmp(&ca)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| {
                let ia = a.get("id").and_then(Value::as_str).unwrap_or("");
                let ib = b.get("id").and_then(Value::as_str).unwrap_or("");
                ib.cmp(ia)
            })
    });
    for record in terminal.iter().skip(keep) {
        if let Some(id) = record.get("id").and_then(Value::as_str) {
            store.worker_delete(id)?;
        }
    }
    Ok(())
}

pub fn load_workers(store: &Store) -> Result<Vec<Value>> {
    let mut records: Vec<Value> = store.worker_records()?;
    records.sort_by(|a, b| {
        let ca = a.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0);
        let cb = b.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0);
        cb.partial_cmp(&ca).unwrap_or(std::cmp::Ordering::Equal)
    });
    Ok(records)
}

pub fn load_worker(store: &Store, id: &str) -> Result<Value> {
    store
        .worker_record(id)?
        .with_context(|| format!("Unknown worker '{id}'"))
}

pub fn save_worker(store: &mut Store, record: &Value) -> Result<()> {
    let id = record
        .get("id")
        .and_then(Value::as_str)
        .context("Worker record has no id")?
        .to_owned();
    ensure!(store.worker_upsert(&id, record)?, "Unknown worker '{id}'");
    Ok(())
}

pub fn active_workers_for_parent(store: &Store, parent_thread_id: &str) -> Result<Vec<Value>> {
    Ok(load_workers(store)?
        .into_iter()
        .filter(|record| {
            record.get("parentThreadId").and_then(Value::as_str) == Some(parent_thread_id)
                && record.get("status").and_then(Value::as_str) == Some("running")
        })
        .collect())
}

pub fn check_spawn_allowed(store: &Store, request: &SpawnRequest) -> Result<()> {
    let active = active_workers_for_parent(store, &request.parent_thread_id)?;
    ensure!(
        active.len() < MAX_WORKERS_PER_PARENT,
        "This parent thread already has 32 running workers"
    );
    ensure!(
        !active.iter().any(|record| record.get("name").and_then(Value::as_str)
            == Some(request.name.as_str())),
        "A running worker with this name already exists for this parent thread"
    );
    for record in &active {
        let claimed: Vec<&str> = record
            .get("targetFiles")
            .and_then(Value::as_array)
            .map(|items| items.iter().filter_map(Value::as_str).collect())
            .unwrap_or_default();
        for file in &request.target_files {
            ensure!(
                !claimed.contains(&file.as_str()),
                "Target file '{file}' is already claimed by running worker '{}'",
                record.get("name").and_then(Value::as_str).unwrap_or("")
            );
        }
    }
    Ok(())
}

pub fn is_terminal(status: &str) -> bool {
    matches!(status, "completed" | "failed" | "cancelled")
}

pub fn extract_transcript(thread: &Value, transcript_start: usize) -> (Vec<String>, Option<String>) {
    let mut assistant_texts: Vec<String> = Vec::new();
    let mut error_text: Option<String> = None;
    if let Some(items) = thread.get("items").and_then(Value::as_array) {
        for item in items.iter().skip(transcript_start) {
            match item.get("kind").and_then(Value::as_str) {
                Some("assistant") => {
                    if let Some(text) = item.get("text").and_then(Value::as_str) {
                        if !text.trim().is_empty() {
                            assistant_texts.push(text.to_owned());
                        }
                    }
                }
                Some("error") => {
                    if let Some(text) = item.get("text").and_then(Value::as_str) {
                        if !text.trim().is_empty() {
                            error_text = Some(text.to_owned());
                        }
                    }
                }
                _ => {}
            }
        }
    }
    (assistant_texts, error_text)
}

pub fn latest_turn_outcome(turn_results: &Value, thread_id: &str) -> Option<String> {
    let mut outcome: Option<(u64, String)> = None;
    if let Some(recent) = turn_results.get("recent").and_then(Value::as_array) {
        for entry in recent {
            if entry.get("threadId").and_then(Value::as_str) != Some(thread_id) {
                continue;
            }
            let serial = entry.get("serial").and_then(Value::as_u64).unwrap_or(0);
            let name = entry
                .get("outcome")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_owned();
            if outcome.as_ref().is_none_or(|(old, _)| serial >= *old) {
                outcome = Some((serial, name));
            }
        }
    }
    outcome.map(|(_, name)| name)
}

fn split_sentences(text: &str) -> Vec<String> {
    let mut pieces: Vec<String> = Vec::new();
    let mut current = String::new();
    for ch in text.chars() {
        current.push(ch);
        if matches!(ch, '.' | '!' | '?' | '\n') {
            let piece = current.trim().to_owned();
            if !piece.is_empty() {
                pieces.push(piece);
            }
            current.clear();
        }
    }
    let tail = current.trim().to_owned();
    if !tail.is_empty() {
        pieces.push(tail);
    }
    pieces
}

fn split_long_piece(piece: &str) -> Vec<String> {
    if piece.chars().count() <= MAX_TASK_CHARS {
        return vec![piece.to_owned()];
    }
    let mut out: Vec<String> = Vec::new();
    for part in piece.split(';') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        if part.chars().count() <= MAX_TASK_CHARS {
            out.push(part.to_owned());
            continue;
        }
        let mut current = String::new();
        for word in part.split_whitespace() {
            if !current.is_empty()
                && current.chars().count() + 1 + word.chars().count() > MAX_TASK_CHARS
            {
                out.push(current.trim().to_owned());
                current.clear();
            }
            if !current.is_empty() {
                current.push(' ');
            }
            current.push_str(word);
        }
        if !current.trim().is_empty() {
            out.push(current.trim().to_owned());
        }
    }
    out
}

pub fn decompose_task(task: &str) -> Result<Vec<String>> {
    let mut steps: Vec<String> = Vec::new();
    for sentence in split_sentences(task) {
        for piece in split_long_piece(&sentence) {
            if steps.len() < MAX_PLAN_STEPS {
                steps.push(piece);
            } else {
                let last = steps.len() - 1;
                if steps[last].chars().count() + 2 + piece.chars().count() <= MAX_TASK_CHARS {
                    steps[last].push_str("; ");
                    steps[last].push_str(&piece);
                } else {
                    bail!("Task decomposes into more than 16 steps; narrow the task and try again");
                }
            }
        }
    }
    ensure!(!steps.is_empty(), "Task produced no plan steps");
    Ok(steps)
}

pub fn expand_step(step: &str) -> Vec<String> {
    let mut parts: Vec<String> = Vec::new();
    for piece in step.split(';') {
        let piece = piece.trim();
        if piece.is_empty() {
            continue;
        }
        if piece.contains(", ") {
            for sub in piece.split(", ") {
                let sub = sub.trim().to_owned();
                if !sub.is_empty() && !parts.contains(&sub) {
                    parts.push(sub);
                }
            }
        } else if !parts.contains(&piece.to_owned()) {
            parts.push(piece.to_owned());
        }
    }
    if parts.len() > 3 {
        parts.truncate(3);
    }
    if parts.is_empty() {
        vec![step.to_owned()]
    } else {
        parts
    }
}

fn plan_json(
    plan_id: &str,
    parent_thread_id: &str,
    task: &str,
    steps: &[String],
    created_at: f64,
) -> Value {
    json!({
        "planId": plan_id,
        "parentThreadId": parent_thread_id,
        "task": task,
        "steps": steps.iter().enumerate().map(|(index, step)| json!({
            "name": format!("Step {}", index + 1),
            "task": step,
            "targetFiles": [],
        })).collect::<Vec<_>>(),
        "createdAt": created_at,
    })
}

pub fn create_plan(store: &mut Store, params: &Value) -> Result<Value> {
    let parent_thread_id = req_str(params, "parentThreadId")?;
    let task = validate_task(&req_str(params, "task")?)?;
    let steps = decompose_task(&task)?;
    let plan_id = uuid::Uuid::new_v4().to_string();
    let created_at = now_seconds();
    let plan = plan_json(&plan_id, &parent_thread_id, &task, &steps, created_at);
    store.worker_plan_upsert(&plan_id, &plan)?;
    Ok(plan)
}

pub fn load_plan(store: &Store, plan_id: &str) -> Result<Value> {
    store
        .worker_plan(plan_id)?
        .with_context(|| format!("Unknown plan '{plan_id}'"))
}

pub fn breakdown_plan(store: &mut Store, params: &Value) -> Result<Value> {
    let plan_id = req_str(params, "planId")?;
    let parent_thread_id = opt_str(params, "parentThreadId");
    let mut plan = load_plan(store, &plan_id)?;
    if let Some(parent) = &parent_thread_id {
        ensure!(
            plan.get("parentThreadId").and_then(Value::as_str) == Some(parent.as_str()),
            "Plan does not belong to this parent thread"
        );
    }
    let steps = plan
        .get("steps")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let mut expanded: Vec<Value> = Vec::new();
    for step in steps {
        let task = step.get("task").and_then(Value::as_str).unwrap_or("");
        let name = step.get("name").and_then(Value::as_str).unwrap_or("");
        let target_files = step.get("targetFiles").cloned().unwrap_or(json!([]));
        let subs = expand_step(task);
        if subs.len() == 1 {
            expanded.push(json!({"name": name, "task": subs[0], "targetFiles": target_files}));
        } else {
            for (index, sub) in subs.iter().enumerate() {
                expanded.push(json!({
                    "name": format!("{name}.{}", index + 1),
                    "task": sub,
                    "targetFiles": target_files,
                }));
            }
        }
    }
    ensure!(
        expanded.len() <= MAX_PLAN_STEPS * 3,
        "Breakdown produced too many steps"
    );
    plan["steps"] = Value::Array(expanded);
    store.worker_plan_upsert(&plan_id, &plan)?;
    Ok(plan)
}

pub fn plan_markdown(
    plan: &Value,
    objective: &str,
    mode: &str,
    total_files: usize,
    relevant_files: usize,
    file_note: &str,
) -> String {
    let mut lines: Vec<String> = Vec::new();
    lines.push(format!("# Execution plan: {objective}"));
    lines.push(String::new());
    lines.push(format!("Mode: {mode}"));
    lines.push(format!(
        "Plan: {}",
        plan.get("planId").and_then(Value::as_str).unwrap_or("")
    ));
    lines.push(String::new());
    lines.push("This plan is a mechanical decomposition of the objective into worker tasks. It is not LLM planning: no model chose these steps, and each step still needs disjoint target files assigned before it can be spawned.".to_owned());
    lines.push(String::new());
    lines.push("## Steps".to_owned());
    if let Some(steps) = plan.get("steps").and_then(Value::as_array) {
        for (index, step) in steps.iter().enumerate() {
            let name = step.get("name").and_then(Value::as_str).unwrap_or("");
            let task = step.get("task").and_then(Value::as_str).unwrap_or("");
            lines.push(format!("{}. {}: {}", index + 1, name, task));
        }
    }
    lines.push(String::new());
    lines.push("## Repository state".to_owned());
    lines.push(format!("Files listed: {total_files}"));
    lines.push(format!("Files matching objective keywords: {relevant_files}"));
    lines.push("Counts are listed files, not inspected files.".to_owned());
    if !file_note.is_empty() {
        lines.push(file_note.to_owned());
    }
    lines.push(String::new());
    lines.push("## Worker spawn calls".to_owned());
    lines.push("Spawn one worker per step with use_workers, assigning disjoint targetFiles to each worker first. A step with no target files assigned must stay inside the task scope it names.".to_owned());
    lines.join("\n")
}

pub fn objective_keywords(objective: &str) -> Vec<String> {
    let mut keywords: Vec<String> = Vec::new();
    for word in objective
        .to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| w.chars().count() >= 3)
    {
        if !keywords.contains(&word.to_owned()) {
            keywords.push(word.to_owned());
        }
    }
    keywords
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truncate_worker_text_keeps_short_text_and_caps_long_text() {
        assert_eq!(truncate_worker_text("done"), "done");
        let exact = "x".repeat(MAX_WORKER_RESULT_CHARS);
        assert_eq!(truncate_worker_text(&exact), exact);
        let long = "x".repeat(MAX_WORKER_RESULT_CHARS + 1);
        let truncated = truncate_worker_text(&long);
        assert!(truncated.starts_with(&exact));
        assert!(truncated.contains("truncated"));
        assert!(truncated.contains("full transcript remains on the worker thread"));
        assert!(truncated.chars().count() < MAX_WORKER_RESULT_CHARS + 128);
        let wide = "é".repeat(MAX_WORKER_RESULT_CHARS + 1);
        let truncated_wide = truncate_worker_text(&wide);
        assert!(truncated_wide.starts_with(&"é".repeat(MAX_WORKER_RESULT_CHARS)));
        assert!(truncated_wide.contains("truncated"));
    }

    #[test]
    fn retention_limit_defaults_to_fifty_and_reads_settings() {
        use crate::store::Store;
        let directory = tempfile::tempdir().unwrap();
        let mut store = Store::open(&directory.path().join("data.sqlite")).unwrap();
        assert_eq!(retention_limit(&store), 50);
        store
            .save_document("settings.json", &json!({"workerRetentionCount": 7}))
            .unwrap();
        assert_eq!(retention_limit(&store), 7);
        store
            .save_document("settings.json", &json!({"workerRetentionCount": 0}))
            .unwrap();
        assert_eq!(retention_limit(&store), 0);
    }

    #[test]
    fn retention_prunes_oldest_terminal_records_per_parent_and_keeps_running() {
        use crate::store::Store;
        let directory = tempfile::tempdir().unwrap();
        let mut store = Store::open(&directory.path().join("data.sqlite")).unwrap();
        store
            .save_document("settings.json", &json!({"workerRetentionCount": 2}))
            .unwrap();
        let parent = "parent-thread";
        let seed = |store: &mut Store, id: &str, parent: &str, status: &str, created_at: f64| {
            let request = SpawnRequest {
                name: format!("worker-{id}"),
                task: "Do the thing.".to_owned(),
                target_files: Vec::new(),
                parent_thread_id: parent.to_owned(),
                assistant_id: None,
            };
            let mut record =
                worker_record_json(id, &request, "child-thread", "codex", 0, created_at);
            record["status"] = json!(status);
            store.worker_upsert(id, &record).unwrap();
        };
        seed(&mut store, "old-terminal", parent, "completed", 1.0);
        seed(&mut store, "older-terminal", parent, "failed", 2.0);
        seed(&mut store, "new-terminal", parent, "cancelled", 3.0);
        seed(&mut store, "newest-terminal", parent, "completed", 4.0);
        seed(&mut store, "running", parent, "running", 0.5);
        seed(&mut store, "other-parent-terminal", "other-parent", "completed", 5.0);
        let request = SpawnRequest {
            name: "fresh".to_owned(),
            task: "Do the thing.".to_owned(),
            target_files: Vec::new(),
            parent_thread_id: parent.to_owned(),
            assistant_id: None,
        };
        insert_record(&mut store, &request, "child-thread", "codex", 0).unwrap();
        let ids: Vec<String> = load_workers(&store)
            .unwrap()
            .into_iter()
            .filter_map(|record| {
                record
                    .get("id")
                    .and_then(Value::as_str)
                    .map(str::to_owned)
            })
            .collect();
        assert_eq!(ids.len(), 5);
        assert!(!ids.contains(&"old-terminal".to_owned()));
        assert!(!ids.contains(&"older-terminal".to_owned()));
        assert!(ids.contains(&"new-terminal".to_owned()));
        assert!(ids.contains(&"newest-terminal".to_owned()));
        assert!(ids.contains(&"running".to_owned()));
        assert!(ids.contains(&"other-parent-terminal".to_owned()));
        let newest_pos = ids.iter().position(|id| id == "newest-terminal").unwrap();
        let new_pos = ids.iter().position(|id| id == "new-terminal").unwrap();
        assert!(newest_pos < new_pos);
    }

    #[test]
    fn retention_zero_keeps_every_terminal_record() {
        use crate::store::Store;
        let directory = tempfile::tempdir().unwrap();
        let mut store = Store::open(&directory.path().join("data.sqlite")).unwrap();
        store
            .save_document("settings.json", &json!({"workerRetentionCount": 0}))
            .unwrap();
        let parent = "parent-thread";
        for (index, id) in ["first", "second", "third"].iter().enumerate() {
            let request = SpawnRequest {
                name: format!("worker-{id}"),
                task: "Do the thing.".to_owned(),
                target_files: Vec::new(),
                parent_thread_id: parent.to_owned(),
                assistant_id: None,
            };
            let mut record = worker_record_json(
                id,
                &request,
                "child-thread",
                "codex",
                0,
                index as f64 + 1.0,
            );
            record["status"] = json!("completed");
            store.worker_upsert(id, &record).unwrap();
        }
        let request = SpawnRequest {
            name: "fresh".to_owned(),
            task: "Do the thing.".to_owned(),
            target_files: Vec::new(),
            parent_thread_id: parent.to_owned(),
            assistant_id: None,
        };
        insert_record(&mut store, &request, "child-thread", "codex", 0).unwrap();
        let ids: Vec<String> = load_workers(&store)
            .unwrap()
            .into_iter()
            .filter_map(|record| {
                record
                    .get("id")
                    .and_then(Value::as_str)
                    .map(str::to_owned)
            })
            .collect();
        assert_eq!(ids.len(), 4);
        assert!(ids.contains(&"first".to_owned()));
        assert!(ids.contains(&"second".to_owned()));
        assert!(ids.contains(&"third".to_owned()));
    }
}
