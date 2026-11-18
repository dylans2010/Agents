use crate::store::Store;
use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};
use std::time::{SystemTime, UNIX_EPOCH};

pub const WORKERS_DOCUMENT: &str = "workers.json";
pub const MAX_WORKER_NAME_CHARS: usize = 128;
pub const MAX_TASK_CHARS: usize = 500;
pub const MAX_TARGET_FILES: usize = 64;
pub const MAX_PLAN_STEPS: usize = 16;
pub const MAX_WORKERS_PER_PARENT: usize = 32;

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
}

pub fn parse_spawn_request(params: &Value) -> Result<SpawnRequest> {
    let parent_thread_id = req_str(params, "parentThreadId")?;
    ensure!(
        !parent_thread_id.trim().is_empty(),
        "Parent thread ID must not be empty"
    );
    Ok(SpawnRequest {
        name: validate_worker_name(&req_str(params, "name")?)?,
        task: validate_task(&req_str(params, "task")?)?,
        target_files: validate_target_files(opt_string_array(params, "targetFiles"))?,
        parent_thread_id,
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

fn load_state(store: &Store) -> Result<(serde_json::Map<String, Value>, serde_json::Map<String, Value>)> {
    let document = store.document(WORKERS_DOCUMENT)?.unwrap_or(json!({}));
    let object = document.as_object().cloned().unwrap_or_default();
    let workers = object
        .get("workers")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let plans = object
        .get("plans")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    Ok((workers, plans))
}

fn save_state(
    store: &mut Store,
    workers: &serde_json::Map<String, Value>,
    plans: &serde_json::Map<String, Value>,
) -> Result<()> {
    store.save_document(
        WORKERS_DOCUMENT,
        &json!({"version": 1, "workers": workers, "plans": plans}),
    )?;
    Ok(())
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
    let (mut workers, plans) = load_state(store)?;
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
    workers.insert(id, record.clone());
    save_state(store, &workers, &plans)?;
    Ok(record)
}

pub fn load_workers(store: &Store) -> Result<Vec<Value>> {
    let (workers, _) = load_state(store)?;
    let mut records: Vec<Value> = workers.values().cloned().collect();
    records.sort_by(|a, b| {
        let ca = a.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0);
        let cb = b.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0);
        ca.partial_cmp(&cb).unwrap_or(std::cmp::Ordering::Equal)
    });
    Ok(records)
}

pub fn load_worker(store: &Store, id: &str) -> Result<Value> {
    let (workers, _) = load_state(store)?;
    workers
        .get(id)
        .cloned()
        .with_context(|| format!("Unknown worker '{id}'"))
}

pub fn save_worker(store: &mut Store, record: &Value) -> Result<()> {
    let id = record
        .get("id")
        .and_then(Value::as_str)
        .context("Worker record has no id")?
        .to_owned();
    let (mut workers, plans) = load_state(store)?;
    ensure!(workers.contains_key(&id), "Unknown worker '{id}'");
    workers.insert(id, record.clone());
    save_state(store, &workers, &plans)?;
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
    let (workers, mut plans) = load_state(store)?;
    plans.insert(plan_id, plan.clone());
    save_state(store, &workers, &plans)?;
    Ok(plan)
}

pub fn load_plan(store: &Store, plan_id: &str) -> Result<Value> {
    let (_, plans) = load_state(store)?;
    plans
        .get(plan_id)
        .cloned()
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
    let (workers, mut plans) = load_state(store)?;
    plans.insert(plan_id, plan.clone());
    save_state(store, &workers, &plans)?;
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
