use super::*;
use crate::store::text;
use crate::worker_store;

pub(super) const METHODS: &[&str] = &[
    "workers.spawn",
    "workers.list",
    "workers.status",
    "workers.result",
    "workers.cancel",
    "workers.delete",
    "workers.plan",
    "workers.breakdown",
    "workers.execution_plan",
];

fn present_record(record: &Value) -> Value {
    let mut record = record.clone();
    let status = record
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("running")
        .to_owned();
    let transcript_items = record
        .get("transcriptItems")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let elapsed = record
        .get("elapsedSeconds")
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    record["progress"] = json!({
        "stage": status,
        "transcriptItems": transcript_items,
        "elapsedSeconds": elapsed,
    });
    record
}

fn refresh_progress(record: &mut Value, thread: &Value, started_at: f64) {
    let items = thread
        .get("items")
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let start = record
        .get("transcriptStart")
        .and_then(Value::as_u64)
        .unwrap_or(0) as usize;
    record["transcriptItems"] = json!(items.saturating_sub(start) as u64);
    record["elapsedSeconds"] = json!((worker_store::now_seconds() - started_at).max(0.0));
}

impl Engine {
    pub(super) fn workers_command(&mut self, method: &str, p: &Value) -> Result<Value> {
        match method {
            "workers.spawn" => self.workers_spawn(p),
            "workers.list" => self.workers_list(p),
            "workers.status" => self.workers_status(p),
            "workers.result" => self.workers_result(p),
            "workers.cancel" => self.workers_cancel(p),
            "workers.delete" => self.workers_delete(p),
            "workers.plan" => self.workers_plan(p),
            "workers.breakdown" => self.workers_breakdown(p),
            "workers.execution_plan" => self.workers_execution_plan(p),
            _ => bail!("Unknown workers method '{method}'"),
        }
    }

    pub fn workers_spawn(&mut self, params: &Value) -> Result<Value> {
        let (parent_thread_id, requests) = if params.get("workers").is_some() {
            worker_store::parse_batch_spawn_request(params)?
        } else {
            let request = worker_store::parse_spawn_request(params)?;
            (request.parent_thread_id.clone(), vec![request])
        };
        let parent = self.store.thread(&parent_thread_id)?;
        ensure!(
            self.codex_login_context(&parent)?.is_none(),
            "Worker spawn is not supported on threads using a named Codex profile: a per-thread system prompt cannot ride a named profile session"
        );
        for request in &requests {
            worker_store::check_spawn_allowed(&self.store, request)?;
        }
        let provider = text(&parent["selection"], "provider");
        let mut spawned: Vec<Value> = Vec::new();
        for request in &requests {
            spawned.push(self.spawn_one_worker(&parent, request, &provider)?);
        }
        self.revision += 1;
        Ok(json!({"workers": spawned.iter().map(present_record).collect::<Vec<_>>()}))
    }

    fn spawn_one_worker(
        &mut self,
        parent: &Value,
        request: &worker_store::SpawnRequest,
        provider: &str,
    ) -> Result<Value> {
        let cwd = self.working_directory(parent)?;
        let assistant = match &request.assistant_id {
            Some(id) => Some(crate::api::assistants_api::find_assistant(
                &self.store,
                uuid::Uuid::parse_str(id).context("Invalid assistant ID")?,
            )?),
            None => None,
        };
        let mut child_params = json!({
            "projectId": parent["projectID"],
            "cwd": cwd.to_string_lossy(),
            "title": format!("Worker: {}", request.name),
        });
        if let Some(assistant) = &assistant {
            if let Some(assistant_provider) = &assistant.provider {
                child_params["selection"] = json!({
                    "provider": assistant_provider,
                    "modelID": assistant.model.clone().unwrap_or_else(|| "default".to_owned()),
                });
            } else if parent["selection"].is_object() {
                child_params["selection"] = parent["selection"].clone();
            }
            child_params["assistantId"] = json!(request.assistant_id);
        } else {
            if parent["selection"].is_object() {
                child_params["selection"] = parent["selection"].clone();
            }
            if let Some(assistant_id) = parent["assistantId"]
                .as_str()
                .filter(|id| uuid::Uuid::parse_str(id).is_ok())
            {
                child_params["assistantId"] = json!(assistant_id);
            }
        }
        for key in ["accessMode", "interactionMode"] {
            if parent[key].is_string() {
                child_params[key] = parent[key].clone();
            }
        }
        if let Some(assistant) = &assistant {
            child_params["systemPrompt"] = json!(assistant.system_prompt);
            let assistant_tools = assistant
                .allowed_tools
                .as_ref()
                .filter(|tools| !tools.is_empty());
            if let Some(allowed_tools) = assistant_tools {
                let narrowed = crate::agent::profile_gate::effective_allowed_tools(
                    &assistant.permission_profile,
                    Some(allowed_tools),
                )
                .unwrap_or_default();
                if narrowed.is_empty() {
                    bail!("This assistant has no tools available for this conversation.");
                }
                child_params["toolset"] = json!("system");
                child_params["allowedTools"] = json!(narrowed);
            } else {
                let parent_toolset = parent["toolset"].as_str();
                let parent_tools_non_empty = parent["allowedTools"]
                    .as_array()
                    .is_some_and(|list| !list.is_empty());
                let effective_system = parent_toolset == Some("system")
                    || (parent_toolset.is_none() && parent_tools_non_empty);
                let provider_key_present = child_params["selection"]
                    .as_object()
                    .is_some_and(|selection| selection.contains_key("provider"));
                let child_provider = child_params["selection"]["provider"]
                    .as_str()
                    .unwrap_or("codex");
                let system_supported = provider_key_present
                    && crate::agent::ensure_system_toolset_supported(child_provider).is_ok();
                let fallback_valid = parent_toolset != Some("provider")
                    && (!effective_system || system_supported);
                if fallback_valid {
                    if !parent["toolset"].is_null() {
                        child_params["toolset"] = parent["toolset"].clone();
                    }
                    if let Some(parent_tools) = parent["allowedTools"]
                        .as_array()
                        .filter(|list| !list.is_empty())
                    {
                        let parent_tools = parent_tools
                            .iter()
                            .filter_map(|name| name.as_str().map(str::to_owned))
                            .collect::<Vec<_>>();
                        let narrowed = crate::agent::profile_gate::effective_allowed_tools(
                            &assistant.permission_profile,
                            Some(&parent_tools),
                        )
                        .unwrap_or_default();
                        if narrowed.is_empty() {
                            bail!("This assistant has no tools available for this conversation.");
                        }
                        child_params["allowedTools"] = json!(narrowed);
                    } else if matches!(
                        assistant.permission_profile.as_str(),
                        "read-only" | "approval-required"
                    ) {
                        let materialized = crate::agent::profile_gate::materialized_allowed_tools(
                            &assistant.permission_profile,
                            None,
                        )
                        .unwrap_or_default();
                        if !materialized.is_empty() {
                            child_params["toolset"] = json!("system");
                            child_params["allowedTools"] = json!(materialized);
                        }
                    }
                }
            }
        } else {
            if !parent["systemPrompt"].is_null() {
                child_params["systemPrompt"] = parent["systemPrompt"].clone();
            }
            if !parent["toolset"].is_null() {
                child_params["toolset"] = parent["toolset"].clone();
            }
            if !parent["allowedTools"].is_null() {
                child_params["allowedTools"] = parent["allowedTools"].clone();
            }
            if let Some(inherited_id) = parent["assistantId"]
                .as_str()
                .filter(|id| uuid::Uuid::parse_str(id).is_ok())
                .and_then(|id| uuid::Uuid::parse_str(id).ok())
            {
                if let Ok(inherited) =
                    crate::api::assistants_api::find_assistant(&self.store, inherited_id)
                {
                    if let Some(child_tools) = child_params["allowedTools"]
                        .as_array()
                        .filter(|list| !list.is_empty())
                    {
                        let child_tools = child_tools
                            .iter()
                            .filter_map(|name| name.as_str().map(str::to_owned))
                            .collect::<Vec<_>>();
                        if let Some(narrowed) = crate::agent::profile_gate::effective_allowed_tools(
                            &inherited.permission_profile,
                            Some(&child_tools),
                        ) {
                            child_params["allowedTools"] = json!(narrowed);
                        }
                    } else if parent["toolset"].as_str() != Some("provider")
                        && matches!(
                            inherited.permission_profile.as_str(),
                            "read-only" | "approval-required"
                        )
                    {
                        let materialized = crate::agent::profile_gate::materialized_allowed_tools(
                            &inherited.permission_profile,
                            None,
                        )
                        .unwrap_or_default();
                        if !materialized.is_empty() {
                            child_params["toolset"] = json!("system");
                            child_params["allowedTools"] = json!(materialized);
                        }
                    }
                }
            }
        }
        let child = self.create_ordinary_thread(&child_params)?;
        let child_id = text(&child, "id");
        let transcript_start = child
            .get("items")
            .and_then(Value::as_array)
            .map(|items| items.len())
            .unwrap_or(0);
        let scope = if request.target_files.is_empty() {
            "No specific files were assigned; stay inside the task scope and do not touch unrelated files.".to_owned()
        } else {
            format!(
                "Work only on these files: {}. Do not touch other files.",
                request.target_files.join(", ")
            )
        };
        let prompt = format!(
            "You are worker \"{}\" spawned by the parent thread. Task: {}. {}. When finished, reply with a concise summary of what you changed and the outcome, so the parent can collect it as your result.",
            request.name, request.task, scope
        );
        if let Err(error) = self.send_turn(
            &json!({"threadId": child_id, "text": prompt}),
            SendOrigin::Ordinary,
        ) {
            bail!(
                "Worker turn could not start ({error}); the empty worker thread {child_id} remains as an ordinary thread"
            );
        }
        let effective_provider = assistant
            .as_ref()
            .and_then(|assistant| assistant.provider.clone())
            .unwrap_or_else(|| provider.to_owned());
        let record = worker_store::insert_record(
            &mut self.store,
            request,
            &child_id,
            &effective_provider,
            transcript_start,
        )?;
        Ok(record)
    }

    fn refresh_worker(&mut self, record: &mut Value) -> Result<()> {
        let status = record
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("running")
            .to_owned();
        if worker_store::is_terminal(&status) {
            return Ok(());
        }
        let _ = self.provider_workers_status();
        let thread_id = record
            .get("threadId")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned();
        let started_at = record
            .get("startedAt")
            .and_then(Value::as_f64)
            .unwrap_or(0.0);
        let thread = match self.store.thread(&thread_id) {
            Ok(thread) => thread,
            Err(_) => {
                record["status"] = json!("failed");
                record["completedAt"] = json!(worker_store::now_seconds());
                record["error"] =
                    json!("Worker thread was deleted; its provider turn cannot be observed");
                return Ok(());
            }
        };
        if self.runs.contains_key(&thread_id) {
            refresh_progress(record, &thread, started_at);
            return Ok(());
        }
        let outcome =
            worker_store::latest_turn_outcome(&self.turn_results.status(), &thread_id);
        let transcript_start = record
            .get("transcriptStart")
            .and_then(Value::as_u64)
            .unwrap_or(0) as usize;
        let (assistant_texts, error_text) = worker_store::extract_transcript(&thread, transcript_start);
        refresh_progress(record, &thread, started_at);
        let completed_at = worker_store::now_seconds();
        match outcome.as_deref() {
            Some("completed") => {
                record["status"] = json!("completed");
                record["completedAt"] = json!(completed_at);
                record["result"] =
                    json!(worker_store::truncate_worker_text(&assistant_texts.join("\n\n")));
            }
            Some("failed") => {
                record["status"] = json!("failed");
                record["completedAt"] = json!(completed_at);
                record["error"] = json!(error_text
                    .map(|text| worker_store::truncate_worker_text(&text))
                    .unwrap_or_else(|| "Provider turn failed".to_owned()));
            }
            Some("interrupted") => {
                record["status"] = json!("cancelled");
                record["completedAt"] = json!(completed_at);
                record["error"] = json!("Turn was interrupted");
            }
            _ => {
                if let Some(error) = error_text {
                    record["status"] = json!("failed");
                    record["completedAt"] = json!(completed_at);
                    record["error"] = json!(worker_store::truncate_worker_text(&error));
                } else if !assistant_texts.is_empty() {
                    record["status"] = json!("completed");
                    record["completedAt"] = json!(completed_at);
                    record["result"] =
                        json!(worker_store::truncate_worker_text(&assistant_texts.join("\n\n")));
                } else {
                    record["status"] = json!("failed");
                    record["completedAt"] = json!(completed_at);
                    record["error"] = json!("Engine restarted while the worker was running; the provider turn did not survive the restart and no result was recorded");
                }
            }
        }
        Ok(())
    }

    fn refresh_and_save(&mut self, record: &mut Value) -> Result<()> {
        let before = record
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned();
        self.refresh_worker(record)?;
        let after = record
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned();
        if before != after || after == "running" {
            worker_store::save_worker(&mut self.store, record)?;
            self.revision += 1;
        }
        Ok(())
    }

    pub fn workers_list(&mut self, params: &Value) -> Result<Value> {
        let parent = params.get("parentThreadId").and_then(Value::as_str);
        let assistant = params.get("assistantId").and_then(Value::as_str);
        let mut records = worker_store::load_workers(&self.store)?;
        if let Some(parent) = parent {
            records.retain(|record| {
                record.get("parentThreadId").and_then(Value::as_str) == Some(parent)
            });
        }
        if let Some(assistant) = assistant {
            records.retain(|record| {
                record.get("assistantId").and_then(Value::as_str) == Some(assistant)
            });
        }
        let mut changed = false;
        for record in records.iter_mut() {
            let before = record
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_owned();
            self.refresh_worker(record)?;
            let after = record
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_owned();
            if before != after || after == "running" {
                worker_store::save_worker(&mut self.store, record)?;
                changed = true;
            }
        }
        if changed {
            self.revision += 1;
        }
        Ok(json!({"workers": records.iter().map(present_record).collect::<Vec<_>>()}))
    }

    pub fn workers_status(&mut self, params: &Value) -> Result<Value> {
        let id = params
            .get("workerId")
            .and_then(Value::as_str)
            .context("Missing required parameter 'workerId'")?;
        let mut record = worker_store::load_worker(&self.store, id)?;
        self.refresh_and_save(&mut record)?;
        Ok(present_record(&record))
    }

    pub fn workers_result(&mut self, params: &Value) -> Result<Value> {
        let id = params
            .get("workerId")
            .and_then(Value::as_str)
            .context("Missing required parameter 'workerId'")?;
        let mut record = worker_store::load_worker(&self.store, id)?;
        self.refresh_and_save(&mut record)?;
        Ok(present_record(&record))
    }

    pub fn workers_cancel(&mut self, params: &Value) -> Result<Value> {
        let id = params
            .get("workerId")
            .and_then(Value::as_str)
            .context("Missing required parameter 'workerId'")?;
        let mut record = worker_store::load_worker(&self.store, id)?;
        self.refresh_and_save(&mut record)?;
        let status = record
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned();
        if worker_store::is_terminal(&status) {
            return Ok(present_record(&record));
        }
        let thread_id = record
            .get("threadId")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned();
        if self.runs.contains_key(&thread_id) {
            match self.request_provider_stop(&thread_id) {
                Ok(()) => {
                    record["cancelRequested"] = json!(true);
                    worker_store::save_worker(&mut self.store, &record)?;
                    self.revision += 1;
                }
                Err(_) => {
                    self.refresh_and_save(&mut record)?;
                }
            }
            return Ok(present_record(&record));
        }
        record["cancelRequested"] = json!(true);
        record["status"] = json!("cancelled");
        record["completedAt"] = json!(worker_store::now_seconds());
        record["error"] =
            json!("Worker turn was not running when cancel was requested; marked cancelled and polling stopped");
        worker_store::save_worker(&mut self.store, &record)?;
        self.revision += 1;
        Ok(present_record(&record))
    }

    pub fn workers_delete(&mut self, params: &Value) -> Result<Value> {
        let id = params
            .get("workerId")
            .and_then(Value::as_str)
            .context("Missing required parameter 'workerId'")?;
        let mut record = worker_store::load_worker(&self.store, id)?;
        self.refresh_and_save(&mut record)?;
        let status = record
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned();
        if !worker_store::is_terminal(&status) {
            bail!("Cannot delete worker '{id}': only completed, failed, or cancelled workers can be deleted; this worker is '{status}'");
        }
        if !self.store.worker_delete(id)? {
            bail!("Unknown worker '{id}'");
        }
        self.revision += 1;
        Ok(json!({"deleted": true, "workerId": id}))
    }

    pub fn workers_plan(&mut self, params: &Value) -> Result<Value> {
        let parent_thread_id = params
            .get("parentThreadId")
            .and_then(Value::as_str)
            .context("Missing required parameter 'parentThreadId'")?;
        let _ = self.store.thread(parent_thread_id)?;
        let plan = worker_store::create_plan(&mut self.store, params)?;
        self.revision += 1;
        Ok(plan)
    }

    pub fn workers_breakdown(&mut self, params: &Value) -> Result<Value> {
        let plan = worker_store::breakdown_plan(&mut self.store, params)?;
        self.revision += 1;
        Ok(plan)
    }

    pub fn workers_execution_plan(&mut self, params: &Value) -> Result<Value> {
        let parent_thread_id = params
            .get("parentThreadId")
            .and_then(Value::as_str)
            .context("Missing required parameter 'parentThreadId'")?;
        let objective = params
            .get("objective")
            .and_then(Value::as_str)
            .context("Missing required parameter 'objective'")?;
        let mode = params
            .get("mode")
            .and_then(Value::as_str)
            .context("Missing required parameter 'mode'")?;
        ensure!(!objective.trim().is_empty(), "Objective must not be empty");
        ensure!(
            objective.chars().count() <= worker_store::MAX_TASK_CHARS,
            "Objective must be at most 500 characters"
        );
        ensure!(!mode.trim().is_empty(), "Mode must not be empty");
        ensure!(
            mode.chars().count() <= 64,
            "Mode must be at most 64 characters"
        );
        let parent = self.store.thread(parent_thread_id)?;
        let cwd = self.working_directory(&parent)?;
        let plan = worker_store::create_plan(
            &mut self.store,
            &json!({"parentThreadId": parent_thread_id, "task": objective}),
        )?;
        let keywords = worker_store::objective_keywords(objective);
        let (total_files, relevant_files, file_note) =
            match crate::workspace::files(&cwd, "", 1000) {
                Ok(listed) => {
                    let paths: Vec<String> = listed
                        .get("files")
                        .and_then(Value::as_array)
                        .map(|items| {
                            items
                                .iter()
                                .filter_map(Value::as_str)
                                .map(str::to_owned)
                                .collect()
                        })
                        .unwrap_or_default();
                    let total = listed
                        .get("total")
                        .and_then(Value::as_u64)
                        .unwrap_or(paths.len() as u64) as usize;
                    let relevant = paths
                        .iter()
                        .filter(|path| {
                            let lower = path.to_lowercase();
                            keywords.iter().any(|keyword| lower.contains(keyword))
                        })
                        .count();
                    (total, relevant, String::new())
                }
                Err(_) => (
                    0,
                    0,
                    "File listing failed; the working directory is not a git checkout or is unavailable.".to_owned(),
                ),
            };
        let markdown = worker_store::plan_markdown(
            &plan,
            objective,
            mode,
            total_files,
            relevant_files,
            &file_note,
        );
        crate::workspace_tools::write_file(&json!({
            "cwd": cwd.to_string_lossy(),
            "path": "agent_notes.md",
            "content": markdown,
        }))?;
        self.revision += 1;
        let mut out = plan.clone();
        out["objective"] = json!(objective);
        out["mode"] = json!(mode);
        out["markdown"] = json!(markdown);
        out["filesListed"] = json!(total_files as u64);
        out["relevantFiles"] = json!(relevant_files as u64);
        out["agentNotesPath"] = json!("agent_notes.md");
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agent::{Event, Launch, Session};
    use std::path::PathBuf;
    use std::sync::mpsc;

    fn test_engine() -> Engine {
        let directory = tempfile::tempdir().unwrap();
        Engine::fixture(Store::open(&directory.path().join("data.sqlite")).unwrap())
    }

    fn make_thread(engine: &mut Engine) -> String {
        text(
            &engine
                .execute("threads.create", &json!({}))
                .unwrap(),
            "id",
        )
    }

    fn spawn_request(parent: &str, name: &str, task: &str) -> Value {
        json!({
            "parentThreadId": parent,
            "name": name,
            "task": task,
            "targetFiles": [],
        })
    }

    fn insert_running_worker(
        engine: &mut Engine,
        parent: &str,
        child: &str,
        name: &str,
    ) -> (Value, mpsc::Sender<Event>) {
        let request = worker_store::parse_spawn_request(
            &spawn_request(parent, name, "Do the thing."),
        )
        .unwrap();
        let record =
            worker_store::insert_record(&mut engine.store, &request, child, "codex", 0).unwrap();
        let mut session = Session::start(Launch {
            executable: PathBuf::from("/nonexistent-coincide-worker-fixture"),
            cwd: std::env::temp_dir(),
            session: None,
            prompt: String::new(),
            model: None,
            variant: None,
            full_access: false,
            mcp: None,
        });
        let (sender, receiver) = mpsc::channel();
        session.events = receiver;
        let transcript_start = engine.store.thread(child).unwrap()["items"]
            .as_array()
            .unwrap()
            .len();
        engine.insert_running(
            child.into(),
            Running {
                configuration: None,
                resume_safe: Arc::new(std::sync::atomic::AtomicBool::new(true)),
                usage_context: None,
                session,
                provider: "codex".into(),
                transcript_start,
                pending: HashMap::new(),
                schedule_claim: None,
                queue_claim: None,
                cancelled: false,
                events: VecDeque::new(),
                persistence_error: None,
            },
        );
        (record, sender)
    }

    #[test]
    fn spawn_rejects_unknown_parent_and_long_tasks() {
        let mut engine = test_engine();
        let missing = engine
            .workers_spawn(&spawn_request("no-such-thread", "w", "Do the thing."))
            .unwrap_err();
        assert!(missing.to_string().contains("no rows"));
        let parent = make_thread(&mut engine);
        let long_task = "x".repeat(501);
        let error = engine
            .workers_spawn(&spawn_request(&parent, "w", &long_task))
            .unwrap_err();
        assert!(error.to_string().contains("500"));
        assert!(worker_store::load_workers(&engine.store).unwrap().is_empty());
    }

    #[test]
    fn spawn_rejects_duplicate_names_and_overlapping_files() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let first = json!({
            "parentThreadId": parent,
            "workers": [
                {"name": "alpha", "task": "First task.", "targetFiles": ["a.swift"]},
                {"name": "alpha", "task": "Second task.", "targetFiles": ["b.swift"]},
            ],
        });
        assert!(engine.workers_spawn(&first).is_err());
        let overlap = json!({
            "parentThreadId": parent,
            "workers": [
                {"name": "alpha", "task": "First task.", "targetFiles": ["a.swift"]},
                {"name": "beta", "task": "Second task.", "targetFiles": ["a.swift"]},
            ],
        });
        assert!(engine.workers_spawn(&overlap).is_err());
        assert!(worker_store::load_workers(&engine.store).unwrap().is_empty());
    }

    #[test]
    fn spawned_worker_inherits_parent_allowed_tools() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["allowedTools"] = json!(["read_file", "use_workers"]);
        engine.store.save(&parent_doc).unwrap();
        let _ = engine.workers_spawn(&spawn_request(&parent, "alpha", "Do the thing."));
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(child_doc["allowedTools"], json!(["read_file", "use_workers"]));
    }

    fn seed_assistant(engine: &mut Engine) -> String {
        seed_assistant_with_allowed_tools(
            engine,
            Some(json!(["read_file", "write_file"])),
        )
    }

    fn seed_assistant_with_allowed_tools(
        engine: &mut Engine,
        allowed_tools: Option<Value>,
    ) -> String {
        seed_assistant_with_provider_and_tools(engine, "claude", allowed_tools)
    }

    fn seed_assistant_with_provider_and_tools(
        engine: &mut Engine,
        provider: &str,
        allowed_tools: Option<Value>,
    ) -> String {
        seed_assistant_with_optional_provider_and_tools(engine, Some(provider), allowed_tools)
    }

    fn seed_assistant_with_optional_provider_and_tools(
        engine: &mut Engine,
        provider: Option<&str>,
        allowed_tools: Option<Value>,
    ) -> String {
        let id = "00000000-0000-4000-8000-000000000001";
        let listed = engine.execute("assistants.list", &json!({})).unwrap();
        let mut assistant = json!({
            "id": id,
            "name": "Reviewer",
            "description": "Reviews diffs",
            "icon": "magnifyingglass",
            "category": "code-review-security",
            "systemPrompt": "Review the diff for security issues.",
            "intendedTasks": ["Review pull requests"],
            "expectedOutputFormat": "A list of findings",
            "model": "sonnet",
            "permissionProfile": "read-only",
            "inputRequirements": ["A diff"],
            "version": 1,
            "source": "custom",
            "isFavorite": false,
            "lastUsedAt": Value::Null,
            "createdAt": 1_000_000,
            "updatedAt": 1_000_000
        });
        if let Some(provider) = provider {
            assistant["provider"] = json!(provider);
        }
        if let Some(tools) = allowed_tools {
            assistant["allowedTools"] = tools;
        }
        engine
            .execute(
                "assistants.save",
                &json!({
                    "assistant": assistant,
                    "baseline": listed["baseline"],
                }),
            )
            .unwrap();
        id.to_owned()
    }

    #[test]
    fn spawn_with_assistant_id_builds_child_from_assistant_config() {
        let mut engine = test_engine();
        let assistant_id = seed_assistant(&mut engine);
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["selection"] = json!({"provider": "codex", "modelID": "default"});
        parent_doc["systemPrompt"] = json!("Parent prompt.");
        parent_doc["toolset"] = json!("system");
        parent_doc["allowedTools"] = json!(["read_file"]);
        engine.store.save(&parent_doc).unwrap();
        let request = json!({
            "parentThreadId": parent,
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": assistant_id,
        });
        let _ = engine.workers_spawn(&request);
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(child_doc["selection"]["provider"], "claude");
        assert_eq!(child_doc["selection"]["modelID"], "sonnet");
        assert_eq!(
            child_doc["systemPrompt"],
            "Review the diff for security issues."
        );
        assert_eq!(child_doc["toolset"], "system");
        assert_eq!(child_doc["allowedTools"], json!(["read_file"]));
        assert_eq!(child_doc["assistantId"], assistant_id);
    }

    #[test]
    fn spawn_with_read_only_assistant_without_any_allowed_tool_fails_closed() {
        let mut engine = test_engine();
        let assistant_id =
            seed_assistant_with_allowed_tools(&mut engine, Some(json!(["write_file"])));
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["selection"] = json!({"provider": "codex", "modelID": "default"});
        engine.store.save(&parent_doc).unwrap();
        let request = json!({
            "parentThreadId": parent,
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": assistant_id,
        });
        let error = engine.workers_spawn(&request).unwrap_err();
        assert!(error
            .to_string()
            .contains("This assistant has no tools available for this conversation."));
        let children = engine.store.summaries("", true).unwrap();
        assert!(children
            .iter()
            .all(|summary| summary.title != "Worker: alpha"));
    }

    #[test]
    fn spawn_with_assistant_without_lists_materializes_restricted_tools() {
        let mut engine = test_engine();
        let assistant_id = seed_assistant_with_allowed_tools(&mut engine, None);
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["selection"] = json!({"provider": "codex", "modelID": "default"});
        engine.store.save(&parent_doc).unwrap();
        let request = json!({
            "parentThreadId": parent,
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": assistant_id,
        });
        let _ = engine.workers_spawn(&request);
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(child_doc["toolset"], "system");
        let tools = child_doc["allowedTools"]
            .as_array()
            .expect("spawn materializes a restricted list");
        assert_eq!(tools.len(), 183);
        assert!(tools.iter().all(|tool| tool != "write_file"));
    }

    #[test]
    fn spawn_without_assistant_narrows_inherited_parent_tools() {
        let mut engine = test_engine();
        let assistant_id = seed_assistant(&mut engine);
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["selection"] = json!({"provider": "codex", "modelID": "default"});
        parent_doc["assistantId"] = json!(assistant_id);
        parent_doc["toolset"] = json!("system");
        parent_doc["allowedTools"] = json!(["read_file", "write_file"]);
        engine.store.save(&parent_doc).unwrap();
        let _ = engine.workers_spawn(&spawn_request(&parent, "alpha", "Do the thing."));
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(child_doc["assistantId"], assistant_id);
        assert_eq!(child_doc["allowedTools"], json!(["read_file"]));
    }

    #[test]
    fn spawn_with_assistant_without_allowed_tools_inherits_parent_toolset() {
        let mut engine = test_engine();
        let assistant_id = seed_assistant_with_allowed_tools(&mut engine, None);
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["selection"] = json!({"provider": "codex", "modelID": "default"});
        parent_doc["systemPrompt"] = json!("Parent prompt.");
        parent_doc["toolset"] = json!("system");
        parent_doc["allowedTools"] = json!(["read_file"]);
        engine.store.save(&parent_doc).unwrap();
        let request = json!({
            "parentThreadId": parent,
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": assistant_id,
        });
        let _ = engine.workers_spawn(&request);
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(
            child_doc["systemPrompt"],
            "Review the diff for security issues."
        );
        assert_eq!(child_doc["toolset"], "system");
        assert_eq!(child_doc["allowedTools"], json!(["read_file"]));
        assert_eq!(child_doc["assistantId"], assistant_id);
    }

    #[test]
    fn spawn_with_assistant_with_empty_allowed_tools_inherits_parent_toolset() {
        let mut engine = test_engine();
        let assistant_id =
            seed_assistant_with_allowed_tools(&mut engine, Some(json!([])));
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["selection"] = json!({"provider": "codex", "modelID": "default"});
        parent_doc["systemPrompt"] = json!("Parent prompt.");
        parent_doc["toolset"] = json!("system");
        parent_doc["allowedTools"] = json!(["read_file"]);
        engine.store.save(&parent_doc).unwrap();
        let request = json!({
            "parentThreadId": parent,
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": assistant_id,
        });
        let _ = engine.workers_spawn(&request);
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(
            child_doc["systemPrompt"],
            "Review the diff for security issues."
        );
        assert_eq!(child_doc["toolset"], "system");
        assert_eq!(child_doc["allowedTools"], json!(["read_file"]));
        assert_eq!(child_doc["assistantId"], assistant_id);
    }

    #[test]
    fn spawn_with_assistant_without_allowed_tools_skips_provider_toolset_parent() {
        let mut engine = test_engine();
        let assistant_id = seed_assistant_with_allowed_tools(&mut engine, None);
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["selection"] = json!({"provider": "codex", "modelID": "default"});
        parent_doc["systemPrompt"] = json!("Parent prompt.");
        parent_doc["toolset"] = json!("provider");
        parent_doc["allowedTools"] = json!(["read_file"]);
        engine.store.save(&parent_doc).unwrap();
        let request = json!({
            "parentThreadId": parent,
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": assistant_id,
        });
        let _ = engine.workers_spawn(&request);
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(
            child_doc["systemPrompt"],
            "Review the diff for security issues."
        );
        assert!(child_doc["toolset"].is_null());
        assert!(child_doc["allowedTools"].is_null());
        assert_eq!(child_doc["assistantId"], assistant_id);
    }

    #[test]
    fn spawn_with_opencode_assistant_without_allowed_tools_skips_system_toolset_parent() {
        let mut engine = test_engine();
        let assistant_id = seed_assistant_with_provider_and_tools(
            &mut engine,
            "opencode",
            None,
        );
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["selection"] = json!({"provider": "codex", "modelID": "default"});
        parent_doc["systemPrompt"] = json!("Parent prompt.");
        parent_doc["toolset"] = json!("system");
        parent_doc["allowedTools"] = json!(["read_file"]);
        engine.store.save(&parent_doc).unwrap();
        let request = json!({
            "parentThreadId": parent,
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": assistant_id,
        });
        let _ = engine.workers_spawn(&request);
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(child_doc["selection"]["provider"], "opencode");
        assert_eq!(
            child_doc["systemPrompt"],
            "Review the diff for security issues."
        );
        assert!(child_doc["toolset"].is_null());
        assert!(child_doc["allowedTools"].is_null());
        assert_eq!(child_doc["assistantId"], assistant_id);
    }

    #[test]
    fn spawn_with_opencode_assistant_without_allowed_tools_skips_derived_system_toolset_parent() {
        let mut engine = test_engine();
        let assistant_id = seed_assistant_with_provider_and_tools(
            &mut engine,
            "opencode",
            None,
        );
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["selection"] = json!({"provider": "codex", "modelID": "default"});
        parent_doc["systemPrompt"] = json!("Parent prompt.");
        parent_doc["allowedTools"] = json!(["read_file"]);
        engine.store.save(&parent_doc).unwrap();
        let request = json!({
            "parentThreadId": parent,
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": assistant_id,
        });
        let _ = engine.workers_spawn(&request);
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(child_doc["selection"]["provider"], "opencode");
        assert_eq!(
            child_doc["systemPrompt"],
            "Review the diff for security issues."
        );
        assert!(child_doc["toolset"].is_null());
        assert!(child_doc["allowedTools"].is_null());
        assert_eq!(child_doc["assistantId"], assistant_id);
    }

    #[test]
    fn spawn_with_selectionless_parent_and_opencode_discovery_skips_system_toolset_parent() {
        let mut engine = test_engine();
        engine.provider_discovery = Some(json!({"providers":[
            {"provider":"codex","state":"not_found"},
            {"provider":"claude","state":"not_found"},
            {"provider":"opencode","state":"found"}
        ]}));
        let assistant_id =
            seed_assistant_with_optional_provider_and_tools(&mut engine, None, None);
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc
            .as_object_mut()
            .unwrap()
            .remove("selection");
        parent_doc["systemPrompt"] = json!("Parent prompt.");
        parent_doc["toolset"] = json!("system");
        parent_doc["allowedTools"] = json!(["read_file"]);
        engine.store.save(&parent_doc).unwrap();
        let request = json!({
            "parentThreadId": parent,
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": assistant_id,
        });
        let _ = engine.workers_spawn(&request);
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(child_doc["selection"]["provider"], "opencode");
        assert_eq!(
            child_doc["systemPrompt"],
            "Review the diff for security issues."
        );
        assert!(child_doc["toolset"].is_null());
        assert!(child_doc["allowedTools"].is_null());
        assert_eq!(child_doc["assistantId"], assistant_id);
    }

    #[test]
    fn spawn_without_assistant_id_inherits_parent_assistant_id() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let assistant_id = "00000000-0000-4000-8000-000000000001";
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        parent_doc["assistantId"] = json!(assistant_id);
        parent_doc["allowedTools"] = json!(["read_file", "use_workers"]);
        engine.store.save(&parent_doc).unwrap();
        let _ = engine.workers_spawn(&spawn_request(&parent, "alpha", "Do the thing."));
        let children = engine.store.summaries("", true).unwrap();
        let child = children
            .iter()
            .find(|summary| summary.title == "Worker: alpha")
            .expect("worker thread remains after its turn fails to start");
        let child_doc = engine.store.thread(&child.id).unwrap();
        assert_eq!(child_doc["assistantId"], assistant_id);
        assert_eq!(
            child_doc["allowedTools"],
            json!(["read_file", "use_workers"])
        );
    }

    #[test]
    fn spawn_with_unknown_assistant_id_errors_without_creating_a_child() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let mut parent_doc = engine.store.thread(&parent).unwrap();
        parent_doc["worktreePath"] = json!(std::env::temp_dir().to_string_lossy());
        engine.store.save(&parent_doc).unwrap();
        let unknown = "00000000-0000-4000-8000-000000000099";
        let error = engine
            .workers_spawn(&json!({
                "parentThreadId": parent,
                "name": "alpha",
                "task": "Do the thing.",
                "targetFiles": [],
                "assistantId": unknown,
            }))
            .unwrap_err();
        assert!(error.to_string().contains("Unknown assistant"));
        assert!(engine
            .store
            .summaries("", true)
            .unwrap()
            .iter()
            .all(|summary| summary.title != "Worker: alpha"));
    }

    #[test]
    fn spawn_request_rejects_malformed_assistant_id() {
        let error = worker_store::parse_spawn_request(&json!({
            "parentThreadId": "parent",
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": "not-a-uuid",
        }))
        .unwrap_err();
        assert!(error.to_string().contains("Assistant ID must be a UUID"));
        let non_string = worker_store::parse_spawn_request(&json!({
            "parentThreadId": "parent",
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": 123,
        }))
        .unwrap_err();
        assert!(non_string
            .to_string()
            .contains("Assistant ID must be a UUID"));
        let null_id = worker_store::parse_spawn_request(&json!({
            "parentThreadId": "parent",
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": Value::Null,
        }))
        .unwrap();
        assert!(null_id.assistant_id.is_none());
        let parsed = worker_store::parse_spawn_request(&json!({
            "parentThreadId": "parent",
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": "00000000-0000-4000-8000-000000000001",
        }))
        .unwrap();
        assert_eq!(
            parsed.assistant_id.as_deref(),
            Some("00000000-0000-4000-8000-000000000001")
        );
        let plain =
            worker_store::parse_spawn_request(&spawn_request("parent", "beta", "Do the thing."))
                .unwrap();
        assert!(plain.assistant_id.is_none());
    }

    #[test]
    fn worker_record_carries_assistant_id() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let request = worker_store::parse_spawn_request(&json!({
            "parentThreadId": parent,
            "name": "alpha",
            "task": "Do the thing.",
            "targetFiles": [],
            "assistantId": "00000000-0000-4000-8000-000000000001",
        }))
        .unwrap();
        let record =
            worker_store::insert_record(&mut engine.store, &request, "child-thread", "claude", 0)
                .unwrap();
        assert_eq!(record["assistantId"], "00000000-0000-4000-8000-000000000001");
        let plain =
            worker_store::parse_spawn_request(&spawn_request(&parent, "beta", "Do the thing."))
                .unwrap();
        let plain_record =
            worker_store::insert_record(&mut engine.store, &plain, "child-thread", "codex", 0)
                .unwrap();
        assert!(plain_record["assistantId"].is_null());
    }

    #[test]
    fn workers_list_filters_by_assistant_id() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let assistant_a = "00000000-0000-4000-8000-000000000001";
        let assistant_b = "00000000-0000-4000-8000-000000000002";
        let seed = |engine: &mut Engine, name: &str, assistant: Option<&str>| {
            let mut params = spawn_request(&parent, name, "Do the thing.");
            if let Some(assistant) = assistant {
                params["assistantId"] = json!(assistant);
            }
            let request = worker_store::parse_spawn_request(&params).unwrap();
            worker_store::insert_record(&mut engine.store, &request, "child-thread", "codex", 0)
                .unwrap()
        };
        let first = seed(&mut engine, "alpha", Some(assistant_a));
        let _second = seed(&mut engine, "beta", Some(assistant_b));
        let _third = seed(&mut engine, "gamma", None);
        let listed = engine
            .workers_list(&json!({"assistantId": assistant_a}))
            .unwrap();
        let ids: Vec<&str> = listed["workers"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|record| record["id"].as_str())
            .collect();
        assert_eq!(ids, vec![first["id"].as_str().unwrap()]);
        let combined = engine
            .workers_list(&json!({"parentThreadId": parent, "assistantId": assistant_b}))
            .unwrap();
        assert_eq!(combined["workers"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn running_worker_reports_progress_and_completes_with_real_result() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let child = make_thread(&mut engine);
        let (record, sender) = insert_running_worker(&mut engine, &parent, &child, "alpha");
        let id = text(&record, "id");
        let status = engine
            .workers_status(&json!({"workerId": id}))
            .unwrap();
        assert_eq!(status["status"], "running");
        assert_eq!(status["progress"]["stage"], "running");
        sender.send(Event::Finished).unwrap();
        engine.poll();
        let mut child_doc = engine.store.thread(&child).unwrap();
        child_doc["items"] = json!([
            {"id": "u1", "kind": "user", "text": "Do the thing."},
            {"id": "a1", "kind": "assistant", "text": "Done: fixed the leak."},
        ]);
        engine.store.save(&child_doc).unwrap();
        let done = engine.workers_status(&json!({"workerId": id})).unwrap();
        assert_eq!(done["status"], "completed");
        assert_eq!(done["result"], "Done: fixed the leak.");
        assert_eq!(done["progress"]["stage"], "completed");
        let again = engine.workers_result(&json!({"workerId": id})).unwrap();
        assert_eq!(again["result"], "Done: fixed the leak.");
    }

    #[test]
    fn failed_turn_reports_the_recorded_error_item() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let child = make_thread(&mut engine);
        let (record, sender) = insert_running_worker(&mut engine, &parent, &child, "alpha");
        let id = text(&record, "id");
        sender
            .send(Event::Failed("Provider blew up".into()))
            .unwrap();
        engine.poll();
        let done = engine.workers_status(&json!({"workerId": id})).unwrap();
        assert_eq!(done["status"], "failed");
        assert_eq!(done["error"], "Provider blew up");
        assert!(done["result"].is_null());
    }

    #[test]
    fn cancel_requests_provider_stop_and_stays_running_until_the_provider_finishes() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let child = make_thread(&mut engine);
        let (record, sender) = insert_running_worker(&mut engine, &parent, &child, "alpha");
        let id = text(&record, "id");
        let requested = engine.workers_cancel(&json!({"workerId": id})).unwrap();
        assert_eq!(requested["status"], "running");
        assert_eq!(requested["cancelRequested"], true);
        assert!(requested["completedAt"].is_null());
        assert!(engine.runs.contains_key(&child));
        sender.send(Event::Finished).unwrap();
        engine.poll();
        let done = engine.workers_status(&json!({"workerId": id})).unwrap();
        assert_eq!(done["status"], "cancelled");
        assert_eq!(done["cancelRequested"], true);
        let repeat = engine.workers_cancel(&json!({"workerId": id})).unwrap();
        assert_eq!(repeat["status"], "cancelled");
    }

    #[test]
    fn delete_removes_terminal_records_and_refuses_running_workers() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let child = make_thread(&mut engine);
        let (record, sender) = insert_running_worker(&mut engine, &parent, &child, "alpha");
        let id = text(&record, "id");
        let running_error = engine
            .workers_delete(&json!({"workerId": id}))
            .unwrap_err();
        assert!(running_error
            .to_string()
            .contains("only completed, failed, or cancelled"));
        assert!(worker_store::load_worker(&engine.store, &id).is_ok());
        let requested = engine.workers_cancel(&json!({"workerId": id})).unwrap();
        assert_eq!(requested["status"], "running");
        let still_running_error = engine
            .workers_delete(&json!({"workerId": id}))
            .unwrap_err();
        assert!(still_running_error
            .to_string()
            .contains("only completed, failed, or cancelled"));
        sender.send(Event::Finished).unwrap();
        engine.poll();
        let done = engine.workers_status(&json!({"workerId": id})).unwrap();
        assert_eq!(done["status"], "cancelled");
        let deleted = engine.workers_delete(&json!({"workerId": id})).unwrap();
        assert_eq!(deleted["deleted"], true);
        assert_eq!(deleted["workerId"], id);
        assert!(worker_store::load_worker(&engine.store, &id).is_err());
        let unknown = engine
            .workers_delete(&json!({"workerId": id}))
            .unwrap_err();
        assert!(unknown.to_string().contains("Unknown worker"));
        assert!(engine.store.thread(&child).is_ok());
    }

    #[test]
    fn orphaned_running_worker_after_restart_reports_failed() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let child = make_thread(&mut engine);
        let request = worker_store::parse_spawn_request(
            &spawn_request(&parent, "alpha", "Do the thing."),
        )
        .unwrap();
        let record =
            worker_store::insert_record(&mut engine.store, &request, &child, "codex", 0).unwrap();
        let id = text(&record, "id");
        let done = engine.workers_status(&json!({"workerId": id})).unwrap();
        assert_eq!(done["status"], "failed");
        assert!(done["error"]
            .as_str()
            .unwrap()
            .contains("did not survive the restart"));
    }

    #[test]
    fn plan_decomposes_mechanically_and_breakdown_expands_steps() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let plan = engine
            .workers_plan(&json!({
                "parentThreadId": parent,
                "task": "Fix the leak. Add a regression test. Update the docs.",
            }))
            .unwrap();
        assert_eq!(plan["steps"].as_array().unwrap().len(), 3);
        assert_eq!(plan["steps"][0]["name"], "Step 1");
        assert_eq!(plan["steps"][0]["task"], "Fix the leak.");
        let plan_id = text(&plan, "planId");
        let broken = engine
            .workers_breakdown(&json!({"planId": plan_id}))
            .unwrap();
        assert_eq!(broken["steps"].as_array().unwrap().len(), 3);
        let split = engine
            .workers_plan(&json!({
                "parentThreadId": parent,
                "task": "Fix the leak in the cache; flush stale entries, rebuild the index.",
            }))
            .unwrap();
        let split_id = text(&split, "planId");
        let expanded = engine
            .workers_breakdown(&json!({"planId": split_id}))
            .unwrap();
        assert!(expanded["steps"].as_array().unwrap().len() > 1);
    }

    #[test]
    fn execution_plan_requires_objective_and_mode_and_writes_notes() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        assert!(engine
            .workers_execution_plan(&json!({"parentThreadId": parent, "objective": "Fix it."}))
            .is_err());
        let directory = tempfile::tempdir().unwrap();
        let cwd_parent = text(
            &engine
                .execute(
                    "threads.create",
                    &json!({"cwd": directory.path().to_string_lossy()}),
                )
                .unwrap(),
            "id",
        );
        let plan = engine
            .workers_execution_plan(&json!({
                "parentThreadId": cwd_parent,
                "objective": "Fix the leak. Add a regression test.",
                "mode": "build",
            }))
            .unwrap();
        assert_eq!(plan["steps"].as_array().unwrap().len(), 2);
        assert_eq!(plan["agentNotesPath"], "agent_notes.md");
        assert_eq!(plan["filesListed"], 0);
        let notes = std::fs::read_to_string(directory.path().join("agent_notes.md")).unwrap();
        assert!(notes.contains("Execution plan: Fix the leak."));
        assert!(notes.contains("mechanical decomposition"));
        assert_eq!(notes, plan["markdown"].as_str().unwrap());
    }
}
