use super::*;
use crate::store::text;
use crate::worker_store;

pub(super) const METHODS: &[&str] = &[
    "workers.spawn",
    "workers.list",
    "workers.status",
    "workers.result",
    "workers.cancel",
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
        let mut child_params = json!({
            "projectId": parent["projectID"],
            "cwd": cwd.to_string_lossy(),
            "title": format!("Worker: {}", request.name),
        });
        if parent["selection"].is_object() {
            child_params["selection"] = parent["selection"].clone();
        }
        for key in ["accessMode", "interactionMode"] {
            if parent[key].is_string() {
                child_params[key] = parent[key].clone();
            }
        }
        if !parent["systemPrompt"].is_null() {
            child_params["systemPrompt"] = parent["systemPrompt"].clone();
        }
        if !parent["toolset"].is_null() {
            child_params["toolset"] = parent["toolset"].clone();
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
        let record = worker_store::insert_record(
            &mut self.store,
            request,
            &child_id,
            provider,
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
                record["result"] = json!(assistant_texts.join("\n\n"));
            }
            Some("failed") => {
                record["status"] = json!("failed");
                record["completedAt"] = json!(completed_at);
                record["error"] = json!(error_text.unwrap_or_else(|| "Provider turn failed".to_owned()));
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
                    record["error"] = json!(error);
                } else if !assistant_texts.is_empty() {
                    record["status"] = json!("completed");
                    record["completedAt"] = json!(completed_at);
                    record["result"] = json!(assistant_texts.join("\n\n"));
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
        let mut records = worker_store::load_workers(&self.store)?;
        if let Some(parent) = parent {
            records.retain(|record| {
                record.get("parentThreadId").and_then(Value::as_str) == Some(parent)
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
                    record["status"] = json!("cancelled");
                    record["completedAt"] = json!(worker_store::now_seconds());
                    record["error"] = json!("Cancelled by the parent thread; the provider turn was asked to stop and may still be winding down");
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
    fn cancel_requests_provider_stop_and_marks_cancelled() {
        let mut engine = test_engine();
        let parent = make_thread(&mut engine);
        let child = make_thread(&mut engine);
        let (record, sender) = insert_running_worker(&mut engine, &parent, &child, "alpha");
        let id = text(&record, "id");
        let cancelled = engine.workers_cancel(&json!({"workerId": id})).unwrap();
        assert_eq!(cancelled["status"], "cancelled");
        assert_eq!(cancelled["cancelRequested"], true);
        assert!(engine.runs.contains_key(&child));
        sender.send(Event::Finished).unwrap();
        engine.poll();
        let still = engine.workers_status(&json!({"workerId": id})).unwrap();
        assert_eq!(still["status"], "cancelled");
        let repeat = engine.workers_cancel(&json!({"workerId": id})).unwrap();
        assert_eq!(repeat["status"], "cancelled");
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
