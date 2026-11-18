use crate::assistants::Assistant;
use crate::scheduling::Recurrence;
use crate::store::Store;
use anyhow::{Context, Result, bail, ensure};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use uuid::Uuid;

pub const DOCUMENT: &str = "assistant-tasks.json";
pub const METHODS: &[&str] = &[
    "tasks.list",
    "tasks.save",
    "tasks.delete",
    "tasks.run_now",
    "tasks.due",
    "tasks.mark_missed",
    "tasks.recover",
];
pub const NAME_LIMIT: usize = 1024;
pub const INPUTS_LIMIT: usize = 65_536;
pub const INPUT_KEYS_LIMIT: usize = 128;
pub const INPUT_KEY_LIMIT: usize = 256;
pub const ACTIONS_LIMIT: usize = 32;
pub const ACTION_NAME_LIMIT: usize = 256;
pub const MESSAGE_LIMIT: usize = 4096;
pub const MAX_RUNS_LIMIT: u32 = 100_000;
pub const MAX_CONCURRENT_LIMIT: u32 = 32;
pub const MAX_RETRIES_LIMIT: u32 = 10;
pub const BACKOFF_MIN_SECONDS: u32 = 60;
pub const BACKOFF_MAX_SECONDS: u32 = 86_400;
pub const RUN_NOW_PROMPT_LIMIT: usize = 500;

pub const LAST_OUTCOMES: &[&str] = &["completed", "failed", "missed", "interrupted"];

pub const MISSED_WHILE_CLOSED: &str = "A run was skipped while Coincide was closed or asleep.";

fn default_true() -> bool {
    true
}

fn default_trigger() -> TriggerKind {
    TriggerKind::Timer
}

fn default_max_concurrent() -> u32 {
    1
}

fn default_failure_behavior() -> FailureBehavior {
    FailureBehavior::RetryWithBackoff
}

fn default_max_retries() -> u32 {
    3
}

fn default_backoff_seconds() -> u32 {
    300
}

fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    let mut out = String::with_capacity(64);
    for byte in digest {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

fn check_no_nul(value: &Value) -> Result<()> {
    let mut stack = vec![value];
    while let Some(current) = stack.pop() {
        match current {
            Value::String(text) => ensure!(!text.contains('\0'), "Text must not contain NUL"),
            Value::Array(items) => stack.extend(items.iter()),
            Value::Object(map) => {
                for (key, item) in map {
                    ensure!(
                        !key.contains('\0'),
                        "Object keys must not contain NUL"
                    );
                    stack.push(item);
                }
            }
            _ => {}
        }
    }
    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TriggerKind {
    Timer,
    GitCommit,
    BranchChange,
    PullRequest,
    Issue,
    WorkspaceChange,
    FileChange,
}

impl TriggerKind {
    pub fn is_available(self) -> bool {
        matches!(self, TriggerKind::Timer)
    }

    pub fn unavailable_reason(self) -> Option<&'static str> {
        match self {
            TriggerKind::Timer => None,
            TriggerKind::GitCommit => Some(
                "Git commit triggers are not available: Coincide has no git watcher, hooks, webhooks, or GitHub polling",
            ),
            TriggerKind::BranchChange => Some(
                "Branch change triggers are not available: Coincide has no git watcher or branch-change events",
            ),
            TriggerKind::PullRequest => Some(
                "Pull request triggers are not available: Coincide has no GitHub polling or webhooks",
            ),
            TriggerKind::Issue => Some(
                "Issue triggers are not available: Coincide has no Issues API polling or webhooks",
            ),
            TriggerKind::WorkspaceChange => Some(
                "Workspace change triggers are not available: Coincide has no workspace file watcher",
            ),
            TriggerKind::FileChange => Some(
                "File change triggers are not available: Coincide has no file watcher",
            ),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FailureBehavior {
    RetryWithBackoff,
    Stop,
    Notify,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecutionLimits {
    #[serde(default)]
    pub max_runs: Option<u32>,
    #[serde(default = "default_max_concurrent")]
    pub max_concurrent: u32,
}

impl Default for ExecutionLimits {
    fn default() -> Self {
        Self {
            max_runs: None,
            max_concurrent: 1,
        }
    }
}

impl ExecutionLimits {
    pub fn validate(&self) -> Result<()> {
        ensure!(
            (1..=MAX_CONCURRENT_LIMIT).contains(&self.max_concurrent),
            "Maximum concurrent runs must be between 1 and 32"
        );
        if let Some(max_runs) = self.max_runs {
            ensure!(
                (1..=MAX_RUNS_LIMIT).contains(&max_runs),
                "Maximum runs must be between 1 and 100000"
            );
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NotificationPrefs {
    #[serde(default)]
    pub on_success: bool,
    #[serde(default = "default_true")]
    pub on_failure: bool,
    #[serde(default = "default_true")]
    pub on_missed: bool,
}

impl Default for NotificationPrefs {
    fn default() -> Self {
        Self {
            on_success: false,
            on_failure: true,
            on_missed: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FailurePolicy {
    #[serde(default = "default_failure_behavior")]
    pub behavior: FailureBehavior,
    #[serde(default = "default_max_retries")]
    pub max_retries: u32,
    #[serde(default = "default_backoff_seconds")]
    pub backoff_seconds: u32,
}

impl Default for FailurePolicy {
    fn default() -> Self {
        Self {
            behavior: FailureBehavior::RetryWithBackoff,
            max_retries: 3,
            backoff_seconds: 300,
        }
    }
}

impl FailurePolicy {
    pub fn validate(&self) -> Result<()> {
        ensure!(
            self.max_retries <= MAX_RETRIES_LIMIT,
            "Maximum retries must be at most 10"
        );
        ensure!(
            (BACKOFF_MIN_SECONDS..=BACKOFF_MAX_SECONDS).contains(&self.backoff_seconds),
            "Retry backoff must be between 60 and 86400 seconds"
        );
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApprovalRequirements {
    #[serde(default)]
    pub required: bool,
    #[serde(default)]
    pub actions: Vec<String>,
}

impl Default for ApprovalRequirements {
    fn default() -> Self {
        Self {
            required: false,
            actions: Vec::new(),
        }
    }
}

impl ApprovalRequirements {
    pub fn validate(&self) -> Result<()> {
        ensure!(
            self.actions.len() <= ACTIONS_LIMIT,
            "At most 32 actions can require approval"
        );
        ensure!(
            self.required || self.actions.is_empty(),
            "Approval actions must be empty when approval is not required"
        );
        let mut seen = HashSet::new();
        for action in &self.actions {
            ensure!(
                !action.trim().is_empty()
                    && action.chars().count() <= ACTION_NAME_LIMIT
                    && !action.chars().any(char::is_control),
                "Approval action names must contain 1-256 characters without control characters"
            );
            ensure!(seen.insert(action), "Duplicate approval action name");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AssistantTask {
    pub id: String,
    pub name: String,
    pub assistant_id: String,
    pub workspace_id: String,
    pub inputs: Value,
    pub schedule: Recurrence,
    #[serde(default = "default_trigger")]
    pub trigger: TriggerKind,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub paused: bool,
    #[serde(default)]
    pub limits: ExecutionLimits,
    #[serde(default)]
    pub notifications: NotificationPrefs,
    #[serde(default)]
    pub failure_policy: FailurePolicy,
    #[serde(default)]
    pub approval: ApprovalRequirements,
    #[serde(default)]
    pub run_count: u64,
    #[serde(default)]
    pub last_run_at: Option<i64>,
    #[serde(default)]
    pub last_outcome: Option<String>,
    #[serde(default)]
    pub last_message: Option<String>,
    #[serde(default)]
    pub last_missed_at: Option<i64>,
    #[serde(default)]
    pub missed_count: u64,
    #[serde(default)]
    pub last_worker_id: Option<String>,
    #[serde(default)]
    pub next_run_at: Option<i64>,
    #[serde(default)]
    pub created_at: i64,
    #[serde(default)]
    pub updated_at: i64,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl AssistantTask {
    pub fn is_active(&self) -> bool {
        self.enabled && !self.paused
    }

    pub fn validate(&self) -> Result<()> {
        Uuid::parse_str(&self.id).context("Invalid automated task ID")?;
        ensure!(
            !self.name.trim().is_empty()
                && self.name.chars().count() <= NAME_LIMIT
                && !self.name.chars().any(char::is_control),
            "Automated task name must contain 1-1024 characters without control characters"
        );
        Uuid::parse_str(&self.assistant_id).context("Invalid automated task assistant ID")?;
        Uuid::parse_str(&self.workspace_id).context("Invalid automated task workspace ID")?;
        let inputs = self.inputs.as_object().context("Task inputs must be an object")?;
        ensure!(
            inputs.len() <= INPUT_KEYS_LIMIT,
            "Task inputs must contain at most 128 entries"
        );
        for key in inputs.keys() {
            ensure!(
                !key.trim().is_empty()
                    && key.chars().count() <= INPUT_KEY_LIMIT
                    && !key.chars().any(char::is_control),
                "Task input names must contain 1-256 characters without control characters"
            );
        }
        let inputs_bytes = serde_json::to_vec(&self.inputs)?;
        ensure!(
            inputs_bytes.len() <= INPUTS_LIMIT,
            "Task inputs must fit within 64 KiB"
        );
        check_no_nul(&self.inputs)?;
        self.schedule.validate()?;
        if let Some(reason) = self.trigger.unavailable_reason() {
            bail!("{reason}");
        }
        self.limits.validate()?;
        self.failure_policy.validate()?;
        self.approval.validate()?;
        if let Some(outcome) = &self.last_outcome {
            ensure!(
                LAST_OUTCOMES.contains(&outcome.as_str()),
                "Unknown automated task last outcome"
            );
        }
        if let Some(message) = &self.last_message {
            ensure!(
                message.chars().count() <= MESSAGE_LIMIT && !message.contains('\0'),
                "Automated task last message must contain at most 4096 characters and no NUL"
            );
        }
        if let Some(worker_id) = &self.last_worker_id {
            Uuid::parse_str(worker_id).context("Invalid automated task last worker ID")?;
        }
        ensure!(
            self.next_run_at.is_none_or(|at| at >= 0),
            "Automated task next run must be an epoch timestamp"
        );
        ensure!(
            self.last_run_at.is_none_or(|at| at >= 0),
            "Automated task last run must be an epoch timestamp"
        );
        ensure!(
            self.last_missed_at.is_none_or(|at| at >= 0),
            "Automated task last missed run must be an epoch timestamp"
        );
        ensure!(
            self.created_at >= 0 && self.updated_at >= 0,
            "Automated task timestamps must be epoch timestamps"
        );
        Ok(())
    }
}

pub fn validate_task(value: &Value) -> Result<AssistantTask> {
    let task: AssistantTask =
        serde_json::from_value(value.clone()).context("Automated task record is invalid")?;
    task.validate()?;
    Ok(task)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AssistantTaskDocument {
    pub version: u32,
    pub tasks: Vec<AssistantTask>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl AssistantTaskDocument {
    pub fn validate(&self) -> Result<Vec<u8>> {
        ensure!(
            self.version == 1,
            "Unsupported automated tasks document version"
        );
        ensure!(
            self.tasks.len() <= crate::organization::RECORD_LIMIT,
            "Too many automated tasks"
        );
        let mut seen = HashSet::new();
        for task in &self.tasks {
            task.validate()?;
            ensure!(
                seen.insert(Uuid::parse_str(&task.id)?),
                "Duplicate automated task ID"
            );
        }
        let bytes = serde_json::to_vec(self)?;
        ensure!(
            bytes.len() <= crate::organization::DOCUMENT_LIMIT,
            "Automated tasks document exceeds size limit"
        );
        Ok(bytes)
    }
}

pub fn empty_document() -> Value {
    json!({"version": 1, "tasks": []})
}

pub struct TasksSnapshot {
    pub source: Option<Value>,
    pub document: Value,
    pub baseline: String,
    pub origin: &'static str,
}

pub fn load(store: &Store) -> Result<TasksSnapshot> {
    let local = store.local_document(DOCUMENT)?;
    let (source, origin) = if let Some(local) = local {
        (Some(local), "local")
    } else if let Some(bytes) = store.original(DOCUMENT)? {
        ensure!(
            bytes.len() <= crate::organization::DOCUMENT_LIMIT,
            "Automated tasks document exceeds size limit"
        );
        (
            Some(
                serde_json::from_slice(&bytes)
                    .context("Captured automated tasks document is invalid")?,
            ),
            "imported",
        )
    } else {
        (None, "empty")
    };
    let document = source.clone().unwrap_or_else(empty_document);
    let typed: AssistantTaskDocument =
        serde_json::from_value(document.clone()).context("Automated tasks document is invalid")?;
    let baseline = sha256_hex(&typed.validate()?);
    Ok(TasksSnapshot {
        source,
        document,
        baseline,
        origin,
    })
}

pub fn persist(store: &mut Store, snapshot: &mut TasksSnapshot) -> Result<String> {
    let typed: AssistantTaskDocument =
        serde_json::from_value(snapshot.document.clone())
            .context("Automated tasks document is invalid")?;
    let baseline = sha256_hex(&typed.validate()?);
    store.save_document(DOCUMENT, &snapshot.document)?;
    snapshot.baseline = baseline.clone();
    snapshot.origin = "local";
    Ok(baseline)
}

pub fn assistant_exists(store: &Store, id: Uuid) -> Result<bool> {
    let document = match store.local_document("assistants.json")? {
        Some(document) => Some(document),
        None => match store.original("assistants.json")? {
            Some(bytes) => {
                ensure!(
                    bytes.len() <= crate::organization::DOCUMENT_LIMIT,
                    "Assistants document exceeds size limit"
                );
                Some(
                    serde_json::from_slice(&bytes)
                        .context("Captured assistants document is invalid")?,
                )
            }
            None => None,
        },
    };
    let Some(document) = document else {
        return Ok(false);
    };
    let assistants = document["assistants"]
        .as_array()
        .context("Invalid assistants envelope")?;
    Ok(assistants.iter().any(|assistant| {
        assistant["id"]
            .as_str()
            .and_then(|value| Uuid::parse_str(value).ok())
            == Some(id)
    }))
}

pub fn workspace_exists(store: &Store, id: Uuid) -> Result<bool> {
    let projects = store.projects()?;
    let projects = projects.as_array().context("Invalid projects")?;
    Ok(projects.iter().any(|project| {
        project["id"]
            .as_str()
            .and_then(|value| Uuid::parse_str(value).ok())
            == Some(id)
    }))
}

pub fn next_run_at(task: &AssistantTask, now: DateTime<Utc>) -> Result<Option<DateTime<Utc>>> {
    if !task.is_active() {
        return Ok(None);
    }
    if let Some(reason) = task.trigger.unavailable_reason() {
        bail!("{reason}");
    }
    if let Some(max_runs) = task.limits.max_runs
        && task.run_count >= u64::from(max_runs)
    {
        return Ok(None);
    }
    task.schedule.next_after(now)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DueTask {
    pub task_id: String,
    pub task_name: String,
    pub occurrence: i64,
    pub next_run_at: i64,
    pub run_count: u64,
}

pub fn due_tasks(document: &AssistantTaskDocument, now: DateTime<Utc>) -> Result<Vec<DueTask>> {
    let mut due = Vec::new();
    for task in &document.tasks {
        if !task.is_active() {
            continue;
        }
        if task.trigger.unavailable_reason().is_some() {
            continue;
        }
        let stored = task
            .next_run_at
            .map(|epoch| {
                DateTime::from_timestamp(epoch, 0).context("Invalid automated task next run")
            })
            .transpose()?;
        let next = match stored {
            Some(next) => Some(next),
            None => next_run_at(task, now)?,
        };
        if let Some(next) = next.filter(|next| *next <= now) {
            due.push(DueTask {
                task_id: task.id.clone(),
                task_name: task.name.clone(),
                occurrence: next.timestamp(),
                next_run_at: next.timestamp(),
                run_count: task.run_count,
            });
        }
    }
    due.sort_by_key(|job| job.occurrence);
    Ok(due)
}

pub fn mark_missed(
    task: &mut AssistantTask,
    occurrence: DateTime<Utc>,
    now: DateTime<Utc>,
    reason: &str,
) -> Result<()> {
    ensure!(
        reason.chars().count() <= MESSAGE_LIMIT && !reason.contains('\0'),
        "Missed-run reason must contain at most 4096 characters and no NUL"
    );
    task.last_outcome = Some("missed".to_string());
    task.last_message = Some(reason.to_string());
    task.last_missed_at = Some(now.timestamp());
    task.missed_count += 1;
    task.next_run_at = next_run_at(task, now)?.map(|next| next.timestamp());
    let _ = occurrence;
    Ok(())
}

pub fn record_missed_runs(
    document: &mut AssistantTaskDocument,
    now: DateTime<Utc>,
) -> Result<Vec<String>> {
    let mut missed = Vec::new();
    for task in &mut document.tasks {
        let Some(stored_next) = task.next_run_at else {
            continue;
        };
        if !task.is_active() || task.trigger != TriggerKind::Timer {
            continue;
        }
        if stored_next > now.timestamp() {
            continue;
        }
        let occurrence = DateTime::from_timestamp(stored_next, 0)
            .context("Invalid automated task next run")?;
        mark_missed(task, occurrence, now, MISSED_WHILE_CLOSED)?;
        missed.push(task.id.clone());
    }
    Ok(missed)
}

pub fn check_run_now(task: &AssistantTask, assistant: &Assistant, now: DateTime<Utc>) -> Result<()> {
    if !task.enabled {
        bail!(
            "Automated task '{}' is disabled; run-now is rejected",
            task.name
        );
    }
    if task.paused {
        bail!(
            "Automated task '{}' is paused; run-now is rejected",
            task.name
        );
    }
    if let Some(reason) = task.trigger.unavailable_reason() {
        bail!("{reason}");
    }
    if let Some(max_runs) = task.limits.max_runs
        && task.run_count >= u64::from(max_runs)
    {
        bail!(
            "Automated task '{}' has reached its maximum of {} runs",
            task.name,
            max_runs
        );
    }
    if task.schedule.kind == "once" && task.run_count >= 1 {
        bail!(
            "Automated task '{}' is a one-time task that has already run",
            task.name
        );
    }
    if task.approval.required {
        bail!(
            "Automated task '{}' requires approval for its actions; run-now cannot start it without explicit user approval",
            task.name
        );
    }
    ensure!(
        assistant.permission_profile != "approval-required",
        "Assistant '{}' requires approval for every run; automated run-now cannot start it without explicit user approval",
        assistant.name
    );
    let _ = now;
    Ok(())
}

pub fn run_now_prompt(task: &AssistantTask) -> String {
    let inputs = serde_json::to_string(&task.inputs).unwrap_or_else(|_| "{}".to_string());
    let text = format!("Automated task \"{}\". Inputs: {inputs}", task.name);
    text.chars().take(RUN_NOW_PROMPT_LIMIT).collect()
}

pub fn find_task(document: &Value, id: Uuid) -> Result<usize> {
    document["tasks"]
        .as_array()
        .context("Invalid automated tasks envelope")?
        .iter()
        .position(|task| {
            task["id"]
                .as_str()
                .and_then(|value| Uuid::parse_str(value).ok())
                == Some(id)
        })
        .context("Automated task not found")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::Engine;
    use chrono::TimeZone;
    use chrono_tz::Tz;

    const ID: &str = "00000000-0000-4000-8000-000000000001";
    const ASSISTANT_ID: &str = "00000000-0000-4000-8000-000000000002";
    const WORKSPACE_ID: &str = "00000000-0000-4000-8000-000000000003";

    fn schedule_json(kind: &str) -> Value {
        json!({
            "kind": kind,
            "timeZoneID": "America/New_York",
            "date": "2026-11-18T09:00:00Z",
            "hour": 9,
            "minute": 0,
            "weekday": 4,
        })
    }

    fn task_json(id: &str) -> Value {
        json!({
            "id": id,
            "name": "Nightly review",
            "assistantId": ASSISTANT_ID,
            "workspaceId": WORKSPACE_ID,
            "inputs": {"branch": "main"},
            "schedule": schedule_json("daily"),
            "trigger": "timer",
            "enabled": true,
            "paused": false,
            "limits": {"maxRuns": Value::Null, "maxConcurrent": 1},
            "notifications": {"onSuccess": false, "onFailure": true, "onMissed": true},
            "failurePolicy": {"behavior": "retryWithBackoff", "maxRetries": 3, "backoffSeconds": 300},
            "approval": {"required": false, "actions": []},
            "runCount": 0,
            "lastRunAt": Value::Null,
            "lastOutcome": Value::Null,
            "lastMessage": Value::Null,
            "lastMissedAt": Value::Null,
            "missedCount": 0,
            "lastWorkerId": Value::Null,
            "nextRunAt": Value::Null,
            "createdAt": 1_000_000,
            "updatedAt": 1_000_000,
            "futureField": {"keep": true}
        })
    }

    fn assistant_json(profile: &str) -> Value {
        json!({
            "id": ASSISTANT_ID,
            "name": "Reviewer",
            "description": "Reviews diffs",
            "icon": "magnifyingglass",
            "category": "code-review-security",
            "systemPrompt": "Review the diff for security issues.",
            "intendedTasks": ["Review pull requests"],
            "expectedOutputFormat": "A list of findings",
            "allowedTools": Value::Null,
            "provider": "claude",
            "model": "sonnet",
            "permissionProfile": profile,
            "inputRequirements": ["A diff"],
            "version": 1,
            "source": "custom",
            "isFavorite": false,
            "lastUsedAt": Value::Null,
            "createdAt": 1_000_000,
            "updatedAt": 1_000_000
        })
    }

    fn utc(year: i32, month: u32, day: u32, hour: u32, minute: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(year, month, day, hour, minute, 0)
            .single()
            .unwrap()
    }

    fn fixture_engine() -> (tempfile::TempDir, Engine) {
        let root = tempfile::tempdir().unwrap();
        let engine = Engine::fixture(Store::open(&root.path().join("rust.sqlite")).unwrap());
        (root, engine)
    }

    fn call(engine: &mut Engine, method: &str, params: Value) -> Value {
        engine.dispatch(json!({"id": 1, "method": method, "params": params}))
    }

    fn seed_assistant(engine: &mut Engine, profile: &str) {
        let listed = call(engine, "assistants.list", json!({}));
        assert!(listed["error"].is_null(), "{}", listed["error"]);
        let saved = call(
            engine,
            "assistants.save",
            json!({"assistant": assistant_json(profile), "baseline": listed["result"]["baseline"]}),
        );
        assert!(saved["error"].is_null(), "{}", saved["error"]);
    }

    fn seed_workspace(engine: &mut Engine) {
        engine
            .store
            .save_document(
                "projects.json",
                &json!([{"id": WORKSPACE_ID, "path": "/tmp"}]),
            )
            .unwrap();
    }

    fn save_task(engine: &mut Engine, task: &Value) -> Value {
        let listed = call(engine, "tasks.list", json!({}));
        assert!(listed["error"].is_null(), "{}", listed["error"]);
        call(
            engine,
            "tasks.save",
            json!({"task": task, "baseline": listed["result"]["baseline"]}),
        )
    }

    #[test]
    fn validation_accepts_a_well_formed_task_and_keeps_unknown_fields() {
        let task = validate_task(&task_json(ID)).unwrap();
        assert_eq!(task.extra["futureField"], json!({"keep": true}));
        assert!(task.is_active());
        assert_eq!(task.trigger, TriggerKind::Timer);
    }

    #[test]
    fn validation_rejects_bad_ids_non_object_inputs_and_oversized_inputs() {
        let mut bad = task_json(ID);
        bad["assistantId"] = json!("not-a-uuid");
        assert!(validate_task(&bad).is_err());
        let mut bad = task_json(ID);
        bad["workspaceId"] = json!("not-a-uuid");
        assert!(validate_task(&bad).is_err());
        let mut bad = task_json(ID);
        bad["inputs"] = json!(["not", "an", "object"]);
        assert!(validate_task(&bad).unwrap_err().to_string().contains("object"));
        let mut bad = task_json(ID);
        bad["inputs"] = json!({"blob": "x".repeat(70_000)});
        assert!(validate_task(&bad).is_err());
        let mut bad = task_json(ID);
        bad["name"] = json!("");
        assert!(validate_task(&bad).is_err());
    }

    #[test]
    fn validation_rejects_bad_timezone_bad_schedule_kind_and_bad_limits() {
        let mut bad = task_json(ID);
        bad["schedule"]["timeZoneID"] = json!("Not/AZone");
        assert!(validate_task(&bad).is_err());
        let mut bad = task_json(ID);
        bad["schedule"]["kind"] = json!("fortnightly");
        assert!(validate_task(&bad).unwrap_err().to_string().contains("Unknown schedule kind"));
        let mut bad = task_json(ID);
        bad["limits"]["maxConcurrent"] = json!(0);
        assert!(validate_task(&bad).is_err());
        let mut bad = task_json(ID);
        bad["limits"]["maxRuns"] = json!(0);
        assert!(validate_task(&bad).is_err());
        let mut bad = task_json(ID);
        bad["failurePolicy"]["backoffSeconds"] = json!(30);
        assert!(validate_task(&bad).is_err());
        let mut bad = task_json(ID);
        bad["approval"]["required"] = json!(false);
        bad["approval"]["actions"] = json!(["write_file"]);
        assert!(validate_task(&bad).is_err());
        let mut bad = task_json(ID);
        bad["approval"]["actions"] = json!(["write_file", "write_file"]);
        bad["approval"]["required"] = json!(true);
        assert!(validate_task(&bad).is_err());
    }

    #[test]
    fn validation_rejects_every_unavailable_trigger_with_a_clear_reason() {
        for kind in [
            "gitCommit",
            "branchChange",
            "pullRequest",
            "issue",
            "workspaceChange",
            "fileChange",
        ] {
            let mut task = task_json(ID);
            task["trigger"] = json!(kind);
            let error = validate_task(&task).unwrap_err().to_string();
            assert!(
                error.contains("not available"),
                "trigger {kind} must report unavailability, got: {error}"
            );
        }
        let parsed: TriggerKind = serde_json::from_value(json!("gitCommit")).unwrap();
        assert_eq!(parsed, TriggerKind::GitCommit);
        assert!(!parsed.is_available());
    }

    #[test]
    fn next_run_daily_respects_timezone_across_the_spring_forward() {
        let task = validate_task(&task_json(ID)).unwrap();
        let zone: Tz = "America/New_York".parse().unwrap();
        let now = utc(2026, 3, 7, 21, 30);
        let next = next_run_at(&task, now).unwrap().unwrap();
        let expected = zone
            .with_ymd_and_hms(2026, 3, 8, 9, 0, 0)
            .single()
            .unwrap()
            .with_timezone(&Utc);
        assert_eq!(next, expected);
        assert_eq!(next.timestamp(), utc(2026, 3, 8, 13, 0).timestamp());
    }

    #[test]
    fn next_run_daily_moves_a_spring_gap_time_to_the_first_valid_minute() {
        let mut value = task_json(ID);
        value["schedule"]["hour"] = json!(2);
        value["schedule"]["minute"] = json!(30);
        let task = validate_task(&value).unwrap();
        let next = next_run_at(&task, utc(2026, 3, 7, 21, 30))
            .unwrap()
            .unwrap();
        assert_eq!(next.timestamp(), utc(2026, 3, 8, 7, 0).timestamp());
    }

    #[test]
    fn next_run_daily_picks_the_first_occurrence_in_the_fall_back_fold() {
        let mut value = task_json(ID);
        value["schedule"]["hour"] = json!(1);
        value["schedule"]["minute"] = json!(30);
        let task = validate_task(&value).unwrap();
        let next = next_run_at(&task, utc(2026, 11, 1, 4, 30))
            .unwrap()
            .unwrap();
        assert_eq!(next.timestamp(), utc(2026, 11, 1, 5, 30).timestamp());
    }

    #[test]
    fn next_run_weekly_and_interval_follow_the_recurrence() {
        let mut weekly = task_json(ID);
        weekly["schedule"]["kind"] = json!("weekly");
        weekly["schedule"]["weekday"] = json!(2);
        let task = validate_task(&weekly).unwrap();
        let next = next_run_at(&task, utc(2026, 11, 15, 12, 0))
            .unwrap()
            .unwrap();
        assert_eq!(next.timestamp(), utc(2026, 11, 16, 14, 0).timestamp());
        let mut interval = task_json(ID);
        interval["schedule"]["kind"] = json!("interval");
        interval["schedule"]["intervalMinutes"] = json!(60);
        interval["schedule"]["date"] = json!("2026-11-18T00:00:00Z");
        let task = validate_task(&interval).unwrap();
        let next = next_run_at(&task, utc(2026, 11, 18, 1, 30))
            .unwrap()
            .unwrap();
        assert_eq!(next.timestamp(), utc(2026, 11, 18, 2, 0).timestamp());
    }

    #[test]
    fn next_run_returns_none_for_once_past_paused_disabled_and_max_runs() {
        let mut once = task_json(ID);
        once["schedule"]["kind"] = json!("once");
        once["schedule"]["date"] = json!("2026-11-01T09:00:00Z");
        let task = validate_task(&once).unwrap();
        assert!(next_run_at(&task, utc(2026, 11, 18, 12, 0))
            .unwrap()
            .is_none());
        let mut paused = task_json(ID);
        paused["paused"] = json!(true);
        assert!(next_run_at(&validate_task(&paused).unwrap(), utc(2026, 11, 18, 12, 0))
            .unwrap()
            .is_none());
        let mut disabled = task_json(ID);
        disabled["enabled"] = json!(false);
        assert!(next_run_at(&validate_task(&disabled).unwrap(), utc(2026, 11, 18, 12, 0))
            .unwrap()
            .is_none());
        let mut capped = task_json(ID);
        capped["limits"]["maxRuns"] = json!(2);
        capped["runCount"] = json!(2);
        assert!(next_run_at(&validate_task(&capped).unwrap(), utc(2026, 11, 18, 12, 0))
            .unwrap()
            .is_none());
    }

    #[test]
    fn due_tasks_lists_only_due_active_timer_tasks_in_order() {
        let mut document: AssistantTaskDocument =
            serde_json::from_value(json!({"version": 1, "tasks": []})).unwrap();
        let mut due = validate_task(&task_json(ID)).unwrap();
        due.next_run_at = Some(utc(2026, 11, 18, 10, 0).timestamp());
        let mut future = validate_task(&task_json("00000000-0000-4000-8000-000000000004")).unwrap();
        future.next_run_at = Some(utc(2026, 11, 18, 15, 0).timestamp());
        let mut paused = validate_task(&task_json("00000000-0000-4000-8000-000000000005")).unwrap();
        paused.paused = true;
        paused.next_run_at = Some(utc(2026, 11, 18, 10, 0).timestamp());
        document.tasks = vec![future, paused, due];
        let due = due_tasks(&document, utc(2026, 11, 18, 12, 0)).unwrap();
        assert_eq!(due.len(), 1);
        assert_eq!(due[0].task_id, ID);
        assert_eq!(due[0].occurrence, utc(2026, 11, 18, 10, 0).timestamp());
    }

    #[test]
    fn due_tasks_skips_active_unavailable_trigger_and_returns_due_timer_task() {
        let mut document: AssistantTaskDocument =
            serde_json::from_value(json!({"version": 1, "tasks": []})).unwrap();
        let mut unavailable =
            validate_task(&task_json("00000000-0000-4000-8000-000000000006")).unwrap();
        unavailable.trigger = TriggerKind::GitCommit;
        unavailable.next_run_at = Some(utc(2026, 11, 18, 10, 0).timestamp());
        let mut due = validate_task(&task_json(ID)).unwrap();
        due.next_run_at = Some(utc(2026, 11, 18, 10, 0).timestamp());
        document.tasks = vec![unavailable, due];
        let due = due_tasks(&document, utc(2026, 11, 18, 12, 0)).unwrap();
        assert_eq!(due.len(), 1);
        assert_eq!(due[0].task_id, ID);
        assert_eq!(due[0].occurrence, utc(2026, 11, 18, 10, 0).timestamp());
        let missed = record_missed_runs(&mut document, utc(2026, 11, 18, 12, 0)).unwrap();
        assert_eq!(missed, vec![ID.to_string()]);
        assert!(document.tasks[0].last_outcome.is_none());
        assert_eq!(document.tasks[0].missed_count, 0);
    }

    #[test]
    fn mark_missed_records_the_miss_and_advances_without_catching_up() {
        let mut task = validate_task(&task_json(ID)).unwrap();
        task.next_run_at = Some(utc(2026, 11, 18, 9, 0).timestamp());
        let occurrence = utc(2026, 11, 18, 14, 0);
        mark_missed(&mut task, occurrence, utc(2026, 11, 18, 15, 0), "Host was asleep.").unwrap();
        assert_eq!(task.last_outcome.as_deref(), Some("missed"));
        assert_eq!(task.missed_count, 1);
        assert_eq!(task.last_missed_at, Some(utc(2026, 11, 18, 15, 0).timestamp()));
        assert_eq!(task.next_run_at, Some(utc(2026, 11, 19, 14, 0).timestamp()));
    }

    #[test]
    fn record_missed_runs_marks_overdue_and_skips_paused_and_future_tasks() {
        let mut document: AssistantTaskDocument =
            serde_json::from_value(json!({"version": 1, "tasks": []})).unwrap();
        let mut overdue = validate_task(&task_json(ID)).unwrap();
        overdue.next_run_at = Some(utc(2026, 11, 18, 9, 0).timestamp());
        let mut paused = validate_task(&task_json("00000000-0000-4000-8000-000000000004")).unwrap();
        paused.paused = true;
        paused.next_run_at = Some(utc(2026, 11, 18, 9, 0).timestamp());
        document.tasks = vec![overdue, paused];
        let missed = record_missed_runs(&mut document, utc(2026, 11, 18, 12, 0)).unwrap();
        assert_eq!(missed, vec![ID.to_string()]);
        assert_eq!(document.tasks[0].last_outcome.as_deref(), Some("missed"));
        assert_eq!(document.tasks[0].missed_count, 1);
        assert!(document.tasks[1].last_outcome.is_none());
        let again = record_missed_runs(&mut document, utc(2026, 11, 18, 12, 0)).unwrap();
        assert!(again.is_empty());
    }

    #[test]
    fn check_run_now_rejects_paused_disabled_approval_and_max_runs() {
        let assistant: Assistant = serde_json::from_value(assistant_json("read-only")).unwrap();
        let now = utc(2026, 11, 18, 12, 0);
        let mut paused = validate_task(&task_json(ID)).unwrap();
        paused.paused = true;
        assert!(check_run_now(&paused, &assistant, now)
            .unwrap_err()
            .to_string()
            .contains("paused"));
        let mut disabled = validate_task(&task_json(ID)).unwrap();
        disabled.enabled = false;
        assert!(check_run_now(&disabled, &assistant, now)
            .unwrap_err()
            .to_string()
            .contains("disabled"));
        let mut needs_approval = validate_task(&task_json(ID)).unwrap();
        needs_approval.approval.required = true;
        needs_approval.approval.actions = vec!["write_file".to_string()];
        assert!(check_run_now(&needs_approval, &assistant, now)
            .unwrap_err()
            .to_string()
            .contains("requires approval"));
        let approving: Assistant =
            serde_json::from_value(assistant_json("approval-required")).unwrap();
        assert!(check_run_now(&validate_task(&task_json(ID)).unwrap(), &approving, now)
            .unwrap_err()
            .to_string()
            .contains("requires approval"));
        let mut capped = validate_task(&task_json(ID)).unwrap();
        capped.limits.max_runs = Some(1);
        capped.run_count = 1;
        assert!(check_run_now(&capped, &assistant, now)
            .unwrap_err()
            .to_string()
            .contains("maximum"));
        assert!(check_run_now(&validate_task(&task_json(ID)).unwrap(), &assistant, now).is_ok());
    }

    #[test]
    fn run_now_prompt_caps_at_the_worker_spawn_limit() {
        let mut value = task_json(ID);
        value["inputs"] = json!({"blob": "x".repeat(2000)});
        let task = validate_task(&value).unwrap();
        let prompt = run_now_prompt(&task);
        assert!(prompt.chars().count() <= RUN_NOW_PROMPT_LIMIT);
        assert!(prompt.contains("Nightly review"));
    }

    #[test]
    fn dispatch_list_save_delete_round_trip_with_baseline() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let listed = call(&mut engine, "tasks.list", json!({}));
        assert_eq!(listed["result"]["origin"], "empty");
        assert_eq!(listed["result"]["tasks"], json!([]));
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        assert_eq!(created["result"]["task"]["id"], ID);
        assert_eq!(created["result"]["task"]["futureField"], json!({"keep": true}));
        assert_eq!(created["result"]["origin"], "local");
        assert!(created["result"]["task"]["nextRunAt"].as_i64().unwrap() > 0);
        let listed = call(&mut engine, "tasks.list", json!({}));
        assert_eq!(listed["result"]["tasks"].as_array().unwrap().len(), 1);
        let mut updated = task_json(ID);
        updated["name"] = json!("Morning review");
        let saved = save_task(&mut engine, &updated);
        assert!(saved["error"].is_null(), "{}", saved["error"]);
        assert_eq!(saved["result"]["task"]["name"], "Morning review");
        assert_eq!(saved["result"]["task"]["createdAt"], json!(1_000_000));
        let listed = call(&mut engine, "tasks.list", json!({}));
        let deleted = call(
            &mut engine,
            "tasks.delete",
            json!({"taskId": ID, "baseline": listed["result"]["baseline"]}),
        );
        assert!(deleted["error"].is_null(), "{}", deleted["error"]);
        assert_eq!(deleted["result"]["deleted"], true);
        let listed = call(&mut engine, "tasks.list", json!({}));
        assert_eq!(listed["result"]["tasks"], json!([]));
    }

    #[test]
    fn dispatch_save_rejects_unknown_assistant_unknown_workspace_and_stale_baseline() {
        let (_root, mut engine) = fixture_engine();
        seed_workspace(&mut engine);
        let no_assistant = save_task(&mut engine, &task_json(ID));
        assert!(no_assistant["error"]["message"]
            .as_str()
            .unwrap()
            .contains("Unknown assistant"));
        seed_assistant(&mut engine, "read-only");
        let mut bad_workspace = task_json(ID);
        bad_workspace["workspaceId"] = json!("00000000-0000-4000-8000-000000000099");
        let rejected = save_task(&mut engine, &bad_workspace);
        assert!(rejected["error"]["message"]
            .as_str()
            .unwrap()
            .contains("Unknown workspace"));
        let stale = call(
            &mut engine,
            "tasks.save",
            json!({"task": task_json(ID), "baseline": "00".repeat(32)}),
        );
        assert!(stale["error"]["message"]
            .as_str()
            .unwrap()
            .contains("changed; reload before saving"));
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        let stale_delete = call(
            &mut engine,
            "tasks.delete",
            json!({"taskId": ID, "baseline": "00".repeat(32)}),
        );
        assert!(stale_delete["error"].is_object());
    }

    #[test]
    fn dispatch_run_now_rejects_paused_disabled_and_approval_required_tasks() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "approval-required");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        let parent = call(
            &mut engine,
            "threads.create",
            json!({"projectId": WORKSPACE_ID}),
        );
        assert!(parent["error"].is_null(), "{}", parent["error"]);
        let parent_id = parent["result"]["id"].as_str().unwrap().to_string();
        let refused = call(
            &mut engine,
            "tasks.run_now",
            json!({"taskId": ID, "parentThreadId": parent_id}),
        );
        assert!(refused["error"]["message"]
            .as_str()
            .unwrap()
            .contains("requires approval"));
        let mut paused = task_json(ID);
        paused["paused"] = json!(true);
        let saved = save_task(&mut engine, &paused);
        assert!(saved["error"].is_null(), "{}", saved["error"]);
        let refused = call(
            &mut engine,
            "tasks.run_now",
            json!({"taskId": ID, "parentThreadId": parent_id}),
        );
        assert!(refused["error"]["message"]
            .as_str()
            .unwrap()
            .contains("paused"));
        let missing = call(
            &mut engine,
            "tasks.run_now",
            json!({"taskId": "00000000-0000-4000-8000-000000000099", "parentThreadId": parent_id}),
        );
        assert!(missing["error"].is_object());
    }

    fn set_stored_next_run_at(engine: &mut Engine, id: &str, next_run_at: i64) {
        let listed = call(engine, "tasks.list", json!({}));
        assert!(listed["error"].is_null(), "{}", listed["error"]);
        let mut document = json!({"version": 1, "tasks": listed["result"]["tasks"].clone()});
        for task in document["tasks"].as_array_mut().unwrap() {
            if task["id"] == id {
                task["nextRunAt"] = json!(next_run_at);
            }
        }
        engine
            .store
            .save_document("assistant-tasks.json", &document)
            .unwrap();
    }

    fn run_now_parent(engine: &mut Engine) -> String {
        let parent = call(
            engine,
            "threads.create",
            json!({"projectId": WORKSPACE_ID}),
        );
        assert!(parent["error"].is_null(), "{}", parent["error"]);
        parent["result"]["id"].as_str().unwrap().to_string()
    }

    fn run_now(engine: &mut Engine, task_id: &str, parent_id: &str) -> Value {
        call(
            engine,
            "tasks.run_now",
            json!({"taskId": task_id, "parentThreadId": parent_id}),
        )
    }

    #[test]
    fn check_run_now_rejects_a_spent_one_time_task_without_max_runs() {
        let assistant: Assistant = serde_json::from_value(assistant_json("read-only")).unwrap();
        let now = utc(2026, 11, 18, 12, 0);
        let mut spent = validate_task(&task_json(ID)).unwrap();
        spent.schedule.kind = "once".to_string();
        spent.run_count = 1;
        assert!(check_run_now(&spent, &assistant, now)
            .unwrap_err()
            .to_string()
            .contains("already run"));
        let mut fresh = validate_task(&task_json(ID)).unwrap();
        fresh.schedule.kind = "once".to_string();
        assert!(check_run_now(&fresh, &assistant, now).is_ok());
    }

    #[test]
    fn dispatch_save_resets_client_supplied_bookkeeping_on_create() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let mut forged = task_json(ID);
        forged["runCount"] = json!(100);
        forged["limits"]["maxRuns"] = json!(100);
        forged["missedCount"] = json!(5);
        forged["lastRunAt"] = json!(1_500_000);
        forged["lastOutcome"] = json!("completed");
        forged["lastMessage"] = json!("Forged outcome");
        forged["lastMissedAt"] = json!(1_400_000);
        forged["lastWorkerId"] = json!("00000000-0000-4000-8000-000000000009");
        forged["createdAt"] = json!(500);
        let created = save_task(&mut engine, &forged);
        assert!(created["error"].is_null(), "{}", created["error"]);
        let saved = &created["result"]["task"];
        assert_eq!(saved["runCount"], json!(0));
        assert_eq!(saved["missedCount"], json!(0));
        assert!(saved["lastRunAt"].is_null());
        assert!(saved["lastOutcome"].is_null());
        assert!(saved["lastMessage"].is_null());
        assert!(saved["lastMissedAt"].is_null());
        assert!(saved["lastWorkerId"].is_null());
        assert!(saved["nextRunAt"].as_i64().unwrap() > 0);
        assert!(saved["createdAt"].as_i64().unwrap() > 1_000_000);
        assert_eq!(saved["createdAt"], saved["updatedAt"]);
    }

    #[test]
    fn dispatch_save_preserves_overdue_next_run_at_when_schedule_is_unchanged() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        set_stored_next_run_at(&mut engine, ID, 1_000_000);
        let mut renamed = task_json(ID);
        renamed["name"] = json!("Morning review");
        let saved = save_task(&mut engine, &renamed);
        assert!(saved["error"].is_null(), "{}", saved["error"]);
        assert_eq!(saved["result"]["task"]["nextRunAt"], json!(1_000_000));
        let mut rescheduled = task_json(ID);
        rescheduled["name"] = json!("Morning review");
        rescheduled["schedule"]["hour"] = json!(10);
        let saved = save_task(&mut engine, &rescheduled);
        assert!(saved["error"].is_null(), "{}", saved["error"]);
        assert!(saved["result"]["task"]["nextRunAt"].as_i64().unwrap() > 1_000_000);
        let mut capped = task_json(ID);
        capped["name"] = json!("Morning review");
        capped["schedule"]["hour"] = json!(10);
        capped["limits"]["maxRuns"] = json!(5);
        let saved = save_task(&mut engine, &capped);
        assert!(saved["error"].is_null(), "{}", saved["error"]);
        assert!(saved["result"]["task"]["nextRunAt"].as_i64().unwrap() > 1_000_000);
    }

    #[test]
    fn dispatch_run_now_spawns_a_worker_and_records_the_run() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        let parent_id = run_now_parent(&mut engine);
        let ran = run_now(&mut engine, ID, &parent_id);
        assert!(ran["error"].is_null(), "{}", ran["error"]);
        let worker = &ran["result"]["worker"];
        assert!(worker["id"].as_str().is_some_and(|id| !id.is_empty()));
        assert_eq!(worker["status"], "running");
        let thread_id = worker["threadId"].as_str().unwrap();
        assert!(engine.store.thread(thread_id).is_ok());
        let saved = &ran["result"]["task"];
        assert_eq!(saved["runCount"], json!(1));
        assert_eq!(saved["lastWorkerId"], worker["id"]);
        assert!(saved["lastRunAt"].as_i64().unwrap() > 0);
        assert!(saved["lastOutcome"].is_null());
        assert!(saved["nextRunAt"].as_i64().unwrap() > saved["lastRunAt"].as_i64().unwrap());
    }

    #[test]
    fn dispatch_run_now_rejects_a_spent_one_time_task() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let mut once = task_json(ID);
        once["schedule"]["kind"] = json!("once");
        once["schedule"]["date"] = json!("2030-01-01T09:00:00Z");
        let created = save_task(&mut engine, &once);
        assert!(created["error"].is_null(), "{}", created["error"]);
        let parent_id = run_now_parent(&mut engine);
        let first = run_now(&mut engine, ID, &parent_id);
        assert!(first["error"].is_null(), "{}", first["error"]);
        assert_eq!(first["result"]["task"]["runCount"], json!(1));
        let second = run_now(&mut engine, ID, &parent_id);
        assert!(second["error"]["message"]
            .as_str()
            .unwrap()
            .contains("already run"));
        let listed = call(&mut engine, "tasks.list", json!({}));
        assert_eq!(listed["result"]["tasks"][0]["runCount"], json!(1));
    }

    #[test]
    fn dispatch_due_lists_overdue_tasks() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        let future = save_task(
            &mut engine,
            &task_json("00000000-0000-4000-8000-000000000004"),
        );
        assert!(future["error"].is_null(), "{}", future["error"]);
        set_stored_next_run_at(&mut engine, ID, 1_000_000);
        let due = call(&mut engine, "tasks.due", json!({}));
        assert!(due["error"].is_null(), "{}", due["error"]);
        let due_tasks = due["result"]["dueTasks"].as_array().unwrap();
        assert_eq!(due_tasks.len(), 1);
        assert_eq!(due_tasks[0]["taskId"], ID);
        assert_eq!(due_tasks[0]["occurrence"], json!(1_000_000));
    }

    #[test]
    fn dispatch_recover_marks_overdue_tasks_missed() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        set_stored_next_run_at(&mut engine, ID, 1_000_000);
        let recovered = call(&mut engine, "tasks.recover", json!({}));
        assert!(recovered["error"].is_null(), "{}", recovered["error"]);
        assert_eq!(recovered["result"]["missedTaskIds"], json!([ID]));
        let listed = call(&mut engine, "tasks.list", json!({}));
        let task = &listed["result"]["tasks"][0];
        assert_eq!(task["lastOutcome"], "missed");
        assert_eq!(task["missedCount"], json!(1));
        assert!(task["nextRunAt"].as_i64().unwrap() > 1_000_000);
        let again = call(&mut engine, "tasks.recover", json!({}));
        assert_eq!(again["result"]["missedTaskIds"], json!([]));
    }

    #[test]
    fn dispatch_mark_missed_records_a_missed_run() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        set_stored_next_run_at(&mut engine, ID, 1_000_000);
        let missed = call(
            &mut engine,
            "tasks.mark_missed",
            json!({"taskId": ID, "reason": "Host was asleep."}),
        );
        assert!(missed["error"].is_null(), "{}", missed["error"]);
        let saved = &missed["result"]["task"];
        assert_eq!(saved["lastOutcome"], "missed");
        assert_eq!(saved["lastMessage"], "Host was asleep.");
        assert_eq!(saved["missedCount"], json!(1));
        assert!(saved["nextRunAt"].as_i64().unwrap() > 1_000_000);
        let too_soon = call(
            &mut engine,
            "tasks.mark_missed",
            json!({"taskId": ID, "reason": "Too soon."}),
        );
        assert!(too_soon["error"]["message"]
            .as_str()
            .unwrap()
            .contains("no missed run to record"));
    }

    #[test]
    fn dispatch_rejects_unknown_task_parameters() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let listed = call(&mut engine, "tasks.list", json!({"unexpected": 1}));
        assert!(listed["error"]["message"]
            .as_str()
            .unwrap()
            .contains("Unknown automated task parameter"));
        let due = call(&mut engine, "tasks.due", json!({"unexpected": 1}));
        assert!(due["error"]["message"]
            .as_str()
            .unwrap()
            .contains("Unknown automated task parameter"));
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        let parent_id = run_now_parent(&mut engine);
        let run_now = call(
            &mut engine,
            "tasks.run_now",
            json!({"taskId": ID, "parentThreadId": parent_id, "extra": 1}),
        );
        assert!(run_now["error"]["message"]
            .as_str()
            .unwrap()
            .contains("Unknown automated task parameter"));
    }

    #[test]
    fn dispatch_run_now_allows_a_second_run_when_the_previous_worker_is_interrupted() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        let parent_id = run_now_parent(&mut engine);
        let first = run_now(&mut engine, ID, &parent_id);
        assert!(first["error"].is_null(), "{}", first["error"]);
        let worker_id = first["result"]["worker"]["id"]
            .as_str()
            .unwrap()
            .to_string();
        let mut record = crate::worker_store::load_worker(&engine.store, &worker_id).unwrap();
        record["status"] = json!("interrupted");
        assert!(engine.store.worker_upsert(&worker_id, &record).unwrap());
        let second = run_now(&mut engine, ID, &parent_id);
        assert!(second["error"].is_null(), "{}", second["error"]);
        assert_eq!(second["result"]["task"]["runCount"], json!(2));
    }

    #[test]
    fn dispatch_run_now_recovers_a_stale_running_worker_after_restart() {
        let (root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        let parent_id = run_now_parent(&mut engine);
        let first = run_now(&mut engine, ID, &parent_id);
        assert!(first["error"].is_null(), "{}", first["error"]);
        drop(engine);
        let mut engine = Engine::fixture(Store::open(&root.path().join("rust.sqlite")).unwrap());
        let second = run_now(&mut engine, ID, &parent_id);
        assert!(second["error"].is_null(), "{}", second["error"]);
        assert_eq!(second["result"]["task"]["runCount"], json!(2));
    }

    #[test]
    fn dispatch_save_preserves_next_run_at_when_renaming_an_overdue_one_time_task() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let mut once = task_json(ID);
        once["schedule"]["kind"] = json!("once");
        once["schedule"]["date"] = json!("2030-01-01T09:00:00Z");
        let created = save_task(&mut engine, &once);
        assert!(created["error"].is_null(), "{}", created["error"]);
        set_stored_next_run_at(&mut engine, ID, 1_000_000);
        let mut renamed = task_json(ID);
        renamed["schedule"]["kind"] = json!("once");
        renamed["schedule"]["date"] = json!("2030-01-01T09:00:00Z");
        renamed["name"] = json!("One-off review");
        let saved = save_task(&mut engine, &renamed);
        assert!(saved["error"].is_null(), "{}", saved["error"]);
        assert_eq!(saved["result"]["task"]["nextRunAt"], json!(1_000_000));
        let parent_id = run_now_parent(&mut engine);
        let ran = run_now(&mut engine, ID, &parent_id);
        assert!(ran["error"].is_null(), "{}", ran["error"]);
        let next_after_run = ran["result"]["task"]["nextRunAt"].clone();
        let mut renamed_again = task_json(ID);
        renamed_again["schedule"]["kind"] = json!("once");
        renamed_again["schedule"]["date"] = json!("2030-01-01T09:00:00Z");
        renamed_again["name"] = json!("One-off review done");
        let saved = save_task(&mut engine, &renamed_again);
        assert!(saved["error"].is_null(), "{}", saved["error"]);
        assert_eq!(saved["result"]["task"]["runCount"], json!(1));
        assert_eq!(saved["result"]["task"]["nextRunAt"], next_after_run);
    }

    #[test]
    fn dispatch_save_rejects_moving_a_one_time_task_to_the_past() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let mut once = task_json(ID);
        once["schedule"]["kind"] = json!("once");
        once["schedule"]["date"] = json!("2030-01-01T09:00:00Z");
        let created = save_task(&mut engine, &once);
        assert!(created["error"].is_null(), "{}", created["error"]);
        let mut moved = task_json(ID);
        moved["schedule"]["kind"] = json!("once");
        moved["schedule"]["date"] = json!("2026-11-01T09:00:00Z");
        let saved = save_task(&mut engine, &moved);
        assert!(saved["error"]["message"]
            .as_str()
            .unwrap()
            .contains("Choose a future date"));
        let listed = call(&mut engine, "tasks.list", json!({}));
        assert_eq!(
            listed["result"]["tasks"][0]["schedule"]["date"],
            json!("2030-01-01T09:00:00Z")
        );
    }

    #[test]
    fn dispatch_run_now_refreshes_a_previous_worker_from_another_parent() {
        let (root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        let first_parent = run_now_parent(&mut engine);
        let first = run_now(&mut engine, ID, &first_parent);
        assert!(first["error"].is_null(), "{}", first["error"]);
        drop(engine);
        let mut engine = Engine::fixture(Store::open(&root.path().join("rust.sqlite")).unwrap());
        let second_parent = run_now_parent(&mut engine);
        assert_ne!(first_parent, second_parent);
        let second = run_now(&mut engine, ID, &second_parent);
        assert!(second["error"].is_null(), "{}", second["error"]);
        assert_eq!(second["result"]["task"]["runCount"], json!(2));
    }

    #[test]
    fn dispatch_run_now_fails_when_the_previous_worker_refresh_cannot_persist() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        let parent_id = run_now_parent(&mut engine);
        let first = run_now(&mut engine, ID, &parent_id);
        assert!(first["error"].is_null(), "{}", first["error"]);
        let worker_id = first["result"]["worker"]["id"]
            .as_str()
            .unwrap()
            .to_string();
        let mut record = crate::worker_store::load_worker(&engine.store, &worker_id).unwrap();
        record.as_object_mut().unwrap().remove("id");
        assert!(engine.store.worker_upsert(&worker_id, &record).unwrap());
        let second = run_now(&mut engine, ID, &parent_id);
        assert!(second["error"]["message"]
            .as_str()
            .unwrap()
            .contains("Worker record has no id"));
        let listed = call(&mut engine, "tasks.list", json!({}));
        assert_eq!(listed["result"]["tasks"][0]["runCount"], json!(1));
    }

    #[test]
    fn dispatch_save_recomputes_next_run_at_when_only_max_runs_changes() {
        let (_root, mut engine) = fixture_engine();
        seed_assistant(&mut engine, "read-only");
        seed_workspace(&mut engine);
        let created = save_task(&mut engine, &task_json(ID));
        assert!(created["error"].is_null(), "{}", created["error"]);
        set_stored_next_run_at(&mut engine, ID, 1_000_000);
        let mut capped = task_json(ID);
        capped["limits"]["maxRuns"] = json!(5);
        let saved = save_task(&mut engine, &capped);
        assert!(saved["error"].is_null(), "{}", saved["error"]);
        assert!(saved["result"]["task"]["nextRunAt"].as_i64().unwrap() > 1_000_000);
    }
}
