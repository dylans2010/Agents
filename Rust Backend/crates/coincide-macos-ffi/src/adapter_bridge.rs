//! Full `CoincideRemoteKit` `RemoteRequest` -> `Adapter` + `Engine` bridge for
//! in-process macOS SwiftUI callers.
//!
//! Accepts either `{"type": "...", "body": ...}` or `{"v": 1, "id": "local", "type": "...", "body": ...}`
//! and returns `{"ok": true, "type": "<result_type>", "body": <RemoteResult body JSON>}`
//! or `{"ok": false, "error": {"code": "<camelCase ErrorCode>", "message": "..."}}`.
use crate::{CoincideMacOSRuntime, discovery};
use chrono::Utc;
use coincide_core::{
    api::BotConversationDisposition,
    composer_suggestions,
    git_actions::{self, ActionRequest, StackedAction, ops as git_ops},
    message_queue,
    remote::{
        adapter::{approval_options, stored_date_ms},
        protocol::{
            self, Account as RemoteAccount, ClientMessage, ErrorCode, RemoteError, Request,
            ThreadAction,
        },
    },
    schedule_presentation,
    scheduling,
    usage_limits,
    workspace,
    workspace_diff::{self, Scope as DiffScope},
};
use serde_json::{Value, json};
use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use uuid::Uuid;

pub fn dispatch_adapter_call(runtime: &CoincideMacOSRuntime, raw_json: &str) -> Value {
    match execute_adapter_call(runtime, raw_json) {
        Ok((kind, body)) => json!({
            "ok": true,
            "type": kind,
            "body": body,
        }),
        Err(error) => json!({
            "ok": false,
            "error": error,
        }),
    }
}

fn execute_adapter_call(
    runtime: &CoincideMacOSRuntime,
    raw_json: &str,
) -> Result<(&'static str, Value), RemoteError> {
    let mut envelope: Value =
        serde_json::from_str(raw_json).map_err(|_| RemoteError::bad_request())?;
    let Some(obj) = envelope.as_object_mut() else {
        return Err(RemoteError::bad_request());
    };
    if !obj.contains_key("v") {
        obj.insert("v".into(), json!(protocol::VERSION));
    }
    if !obj.contains_key("id") {
        obj.insert("id".into(), json!("local"));
    }
    let body_snapshot = obj.get("body").cloned();
    let encoded = serde_json::to_vec(&envelope).map_err(|_| RemoteError::bad_request())?;
    let message = ClientMessage::decode(&encoded).map_err(|f| f.error)?;

    let adapter = &runtime.adapter;
    match message.request {
        Request::Hello(_) | Request::Pair(_) => Ok((
            "server",
            serde_json::to_value(adapter.server_info("LOCAL", "Mac"))
                .map_err(|e| RemoteError::failed(e.to_string()))?,
        )),
        Request::Ping | Request::CloseThread { .. } | Request::Presence(_) => {
            Ok(("ok", Value::Null))
        }
        Request::Workspace { include_archived } => {
            let runs = adapter.workspace_runs()?;
            let mut ws = adapter.initial_workspace(include_archived, &runs)?;
            enrich_local_workspace(runtime, &mut ws)?;
            let mut ws_json =
                serde_json::to_value(ws).map_err(|e| RemoteError::failed(e.to_string()))?;
            attach_workspace_extras(runtime, &mut ws_json);
            Ok(("workspace", ws_json))
        }
        Request::OpenThread { thread_id, limit } => {
            let runs = adapter.workspace_runs()?;
            let (transcript, document) = adapter.transcript(thread_id, limit, &runs)?;
            let mut body = serde_json::to_value(&transcript)
                .map_err(|e| RemoteError::failed(e.to_string()))?;
            if let Ok(mut engine) = runtime.engine.lock() {
                if let Ok(Some(resolved)) = engine.store.resolve_thread_id(thread_id) {
                    let _ = engine.dispatch_desktop(json!({
                        "method": "threads.open",
                        "params": { "threadId": resolved },
                    }));
                    if let Ok(cp) = engine.checkpoint_list_for_snapshot(&resolved, &document) {
                        body["turnChanges"] = turn_changes_map(&cp);
                    }
                }
            }
            if let Ok(remote) = runtime.remote.lock() {
                remote.desktop_seen(thread_id);
            }
            Ok(("transcript", body))
        }
        Request::LoadEarlier {
            thread_id,
            before_index,
            limit,
        } => {
            let page = adapter.items_before(thread_id, before_index, limit, &adapter.runs()?)?;
            let body =
                serde_json::to_value(page).map_err(|e| RemoteError::failed(e.to_string()))?;
            Ok(("items", body))
        }
        Request::Media {
            thread_id,
            item_id,
            index,
            full,
        } => {
            let media = adapter.media(thread_id, item_id, index, full)?;
            let body =
                serde_json::to_value(media).map_err(|e| RemoteError::failed(e.to_string()))?;
            Ok(("media", body))
        }
        Request::MarkSeen { thread_id } => {
            adapter.mark_seen(thread_id)?;
            if let Ok(remote) = runtime.remote.lock() {
                remote.desktop_seen(thread_id);
            }
            Ok(("ok", Value::Null))
        }
        Request::Send(send) => {
            ensure_native_account_ready_before_send(runtime, send.thread_id)?;
            let delivery = adapter.send(&send, &adapter.runs()?)?;
            Ok(("delivery", protocol::value_body(delivery)))
        }
        Request::UpdateSettings(settings) => {
            handle_update_settings(runtime, settings)?;
            Ok(("ok", Value::Null))
        }
        Request::SteerQueued {
            thread_id,
            message_id,
        } => {
            handle_steer_queued(runtime, thread_id, message_id)?;
            Ok(("ok", Value::Null))
        }
        Request::RemoveQueued {
            thread_id,
            message_id,
        } => {
            adapter.remove_queued(thread_id, message_id)?;
            Ok(("ok", Value::Null))
        }
        Request::Stop { thread_id } => {
            adapter.stop(thread_id, &adapter.runs()?)?;
            Ok(("ok", Value::Null))
        }
        Request::Respond {
            thread_id,
            item_id,
            option_id,
            text,
        } => {
            handle_respond(runtime, thread_id, item_id, &option_id, text.as_deref())?;
            Ok(("ok", Value::Null))
        }
        Request::Answer {
            thread_id,
            item_id,
            answers,
        } => {
            adapter.answer(thread_id, item_id, &answers, &adapter.runs()?)?;
            Ok(("ok", Value::Null))
        }
        Request::DismissQuestion { thread_id, item_id } => {
            adapter.dismiss_question(thread_id, item_id, &adapter.runs()?)?;
            Ok(("ok", Value::Null))
        }
        Request::NewThread {
            project_id,
            system_prompt,
            toolset,
            allowed_tools,
            assistant_id,
        } => {
            let id = adapter.new_thread(project_id, &adapter.workspace_runs()?, system_prompt, toolset, allowed_tools, assistant_id)?;
            Ok(("thread", protocol::value_body(id)))
        }
        Request::NewBotConversation { bot_id } => {
            let id = adapter.new_bot_conversation(bot_id)?;
            Ok(("thread", protocol::value_body(id)))
        }
        Request::SetProjectExpanded {
            project_id,
            expanded,
        } => {
            adapter.set_project_expanded(project_id, expanded)?;
            Ok(("ok", Value::Null))
        }
        Request::ThreadAction { thread_id, action } => {
            handle_thread_action(runtime, thread_id, &action)?;
            Ok(("ok", Value::Null))
        }
        Request::UpdateStoredPrompt {
            thread_id,
            system_prompt,
            allowed_tools,
        } => {
            adapter.update_stored_prompt(thread_id, &system_prompt, allowed_tools.as_deref())?;
            Ok(("ok", Value::Null))
        }
        Request::UsageLimits => {
            let usage = collect_remote_usage_limits(runtime)?;
            Ok(("usage", protocol::value_body(usage)))
        }
        Request::ShowThread { thread_id } => {
            let id = resolve_thread_id(runtime, thread_id)?;
            engine_call(runtime, "threads.open", json!({ "threadId": id }))?;
            Ok(("ok", Value::Null))
        }
        Request::Unimplemented(kind) => {
            let body_obj = body_snapshot.unwrap_or_else(|| json!({}));
            handle_extended_request(runtime, &kind, &body_obj)
        }
    }
}

// MARK: - Helpers & Extended CoincideRemoteKit Request Handlers

fn engine_call(
    runtime: &CoincideMacOSRuntime,
    method: &str,
    params: Value,
) -> Result<Value, RemoteError> {
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
    let resp = engine.dispatch(json!({ "method": method, "params": params }));
    if let Some(err) = resp.get("error") {
        return Err(RemoteError::failed(
            err["message"].as_str().unwrap_or("Command failed"),
        ));
    }
    Ok(resp["result"].clone())
}

fn resolve_thread_id(runtime: &CoincideMacOSRuntime, uuid: Uuid) -> Result<String, RemoteError> {
    let engine = runtime
        .engine
        .lock()
        .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
    engine
        .store
        .resolve_thread_id(uuid)
        .map_err(|e| RemoteError::failed(e.to_string()))?
        .ok_or_else(RemoteError::thread_not_found)
}

fn parse_uuid_field(body: &Value, key: &str) -> Result<Uuid, RemoteError> {
    body.get(key)
        .and_then(Value::as_str)
        .and_then(|s| Uuid::parse_str(s).ok())
        .ok_or_else(RemoteError::bad_request)
}

fn thread_working_dir(runtime: &CoincideMacOSRuntime, thread_id: &str) -> Result<PathBuf, RemoteError> {
    let engine = runtime
        .engine
        .lock()
        .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
    let thread = engine
        .store
        .thread(thread_id)
        .map_err(|_| RemoteError::thread_not_found())?;
    if let Some(wt) = thread["worktreePath"].as_str().filter(|s| !s.is_empty()) {
        let p = PathBuf::from(wt);
        if p.is_dir() {
            return Ok(p);
        }
    }
    if let Ok(projects) = engine.store.projects()
        && let Some(proj) = projects
            .as_array()
            .into_iter()
            .flatten()
            .find(|p| p["id"] == thread["projectID"])
        && let Some(path) = proj["path"].as_str().filter(|s| !s.is_empty())
    {
        return Ok(PathBuf::from(path));
    }
    discovery::home_dir().ok_or_else(|| RemoteError::failed("Working directory is unavailable."))
}

fn enrich_local_workspace(
    runtime: &CoincideMacOSRuntime,
    ws: &mut protocol::Workspace,
) -> Result<(), RemoteError> {
    ws.can_edit_bots = true;
    let Ok(engine) = runtime.engine.lock() else {
        return Ok(());
    };
    for provider in &mut ws.providers {
        let cfg = engine.native_provider_configuration(&provider.id).ok();
        let candidates = discovery::candidate_executables(&provider.id, &runtime.data_dir);
        let has_exec = cfg
            .as_ref()
            .and_then(|c| c.executable.as_ref())
            .is_some()
            || !candidates.is_empty();
        if let Ok(accounts) = engine.native_provider_accounts(&provider.id) {
            provider.accounts = accounts
                .into_iter()
                .map(|acc| {
                    let is_ready = match acc.authentication {
                        coincide_core::provider_configuration::NativeAccountAuthentication::ApiKey => {
                            acc.has_key
                        }
                        coincide_core::provider_configuration::NativeAccountAuthentication::Login => {
                            true
                        }
                    };
                    RemoteAccount {
                        id: acc.id,
                        name: acc.name,
                        is_ready,
                    }
                })
                .collect();
        }
        provider.state = if !has_exec {
            "notInstalled".into()
        } else if provider.id == "antigravity"
            && !provider.accounts.iter().any(|a| a.is_ready)
        {
            "notAuthenticated".into()
        } else {
            "ready".into()
        };
    }
    Ok(())
}

fn attach_workspace_extras(runtime: &CoincideMacOSRuntime, ws_json: &mut Value) {
    let Ok(mut engine) = runtime.engine.lock() else {
        return;
    };
    let settings = engine
        .store
        .document("settings.json")
        .ok()
        .flatten()
        .unwrap_or_else(|| json!({}));
    ws_json["sidebar"] = json!({
        "projectSort": settings["projectSort"].as_str().unwrap_or("manual"),
        "threadSort": settings["threadSort"].as_str().unwrap_or("recentActivity"),
        "chatSort": settings["chatSort"].as_str().unwrap_or("recentActivity"),
        "botSort": settings["botSort"].as_str().unwrap_or("recentActivity"),
        "threadsPerProject": settings.get("threadsPerProject").filter(|v| v.is_i64()),
    });
    ws_json["botPersonalityPresets"] = json!([
        "friendly",
        "pragmatic",
        "direct",
        "mentor",
        "critic",
        "socratic",
    ]);

    // Enrich thread summaries with scheduleCount and nextScheduledRun
    let tasks_resp = engine.dispatch_desktop(json!({
        "method": "schedules.list",
        "params": {},
    }));
    if let Some(tasks) = tasks_resp["result"]["tasks"].as_array()
        && let Some(threads) = ws_json["threads"].as_array_mut()
    {
        for t in threads {
            if let Some(tid) = t["id"].as_str().map(str::to_owned) {
                let count = tasks
                    .iter()
                    .filter(|task| {
                        task["threadID"]
                            .as_str()
                            .is_some_and(|s| s.eq_ignore_ascii_case(&tid))
                    })
                    .count();
                if count > 0 {
                    t["scheduleCount"] = json!(count);
                    if let Some((next_dt, _)) = schedule_presentation::next_run_in_thread(tasks, &tid)
                    {
                        t["nextScheduledRun"] = json!(next_dt.timestamp_millis() as f64);
                    }
                }
            }
        }
    }
}

fn turn_changes_map(cp_value: &Value) -> Value {
    let mut map = serde_json::Map::new();
    for turn in cp_value["turns"].as_array().into_iter().flatten() {
        let Some(item_id) = turn["userItemID"].as_str() else {
            continue;
        };
        let files: Vec<Value> = turn["files"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|f| {
                json!({
                    "path": f["path"],
                    "oldPath": f["oldPath"],
                    "status": f["status"],
                    "additions": f["additions"].as_u64().unwrap_or(0),
                    "deletions": f["deletions"].as_u64().unwrap_or(0),
                })
            })
            .collect();
        if !files.is_empty() {
            map.insert(item_id.to_uppercase(), Value::Array(files));
        }
    }
    Value::Object(map)
}

/// Ensures that if a thread uses Antigravity and a Gemini API key account exists,
/// the native account selection seal is minted if no account was explicitly bound yet.
fn ensure_native_account_ready_before_send(
    runtime: &CoincideMacOSRuntime,
    thread_uuid: Uuid,
) -> Result<(), RemoteError> {
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
    let Some(id) = engine
        .store
        .resolve_thread_id(thread_uuid)
        .ok()
        .flatten()
    else {
        return Ok(());
    };
    let Ok(thread) = engine.store.thread(&id) else {
        return Ok(());
    };
    if thread["selection"]["provider"] == "antigravity" {
        let selected_acc = thread["selection"]["accountID"].as_str().unwrap_or("default");
        if selected_acc == "default" || selected_acc.is_empty() {
            if let Ok(accounts) = engine.native_key_accounts("antigravity")
                && let Some(first_ready) = accounts.iter().find(|a| a.has_key)
            {
                let _ = engine.dispatch_desktop(json!({
                    "method": "threads.open",
                    "params": { "threadId": id },
                }));
                if let Ok(fresh) = engine.store.thread(&id) {
                    let _ =
                        engine.select_native_provider_account(&fresh, Some(&first_ready.id));
                }
            }
        }
    }
    Ok(())
}

fn handle_update_settings(
    runtime: &CoincideMacOSRuntime,
    mut settings: protocol::ThreadSettings,
) -> Result<(), RemoteError> {
    // Check whether the requested accountID is a native provider account.
    // If so, update provider/model/effort/speed/modes first, then apply the
    // HMAC-authenticated `select_native_provider_account` grant!
    let requested_account = settings.account_id.clone();
    let is_native_target = {
        let engine = runtime
            .engine
            .lock()
            .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
        let id = engine
            .store
            .resolve_thread_id(settings.thread_id)
            .map_err(|e| RemoteError::failed(e.to_string()))?
            .ok_or_else(RemoteError::thread_not_found)?;
        let current = engine
            .store
            .thread(&id)
            .map_err(|_| RemoteError::thread_not_found())?;
        let target_provider = settings
            .provider
            .as_deref()
            .or_else(|| current["selection"]["provider"].as_str())
            .unwrap_or("codex");
        let native_list = engine
            .native_provider_accounts(target_provider)
            .unwrap_or_default();
        let current_acc = current["selection"]["accountID"].as_str().unwrap_or("default");
        let current_is_native = native_list.iter().any(|a| a.id == current_acc);
        match requested_account.as_deref() {
            Some(acc) if acc != "default" && !acc.is_empty() => {
                native_list.iter().any(|a| a.id == acc)
            }
            Some(_) => current_is_native,
            None => false,
        }
    };

    if is_native_target {
        // Clear account_id during base settings update if switching to a new native account,
        // then mint the native account selection seal cleanly.
        settings.account_id = Some("default".into());
        runtime.adapter.update_thread_settings(&settings)?;
        let mut engine = runtime
            .engine
            .lock()
            .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
        let id = engine
            .store
            .resolve_thread_id(settings.thread_id)
            .map_err(|e| RemoteError::failed(e.to_string()))?
            .ok_or_else(RemoteError::thread_not_found)?;
        let _ = engine.dispatch_desktop(json!({
            "method": "threads.open",
            "params": { "threadId": id },
        }));
        let current = engine
            .store
            .thread(&id)
            .map_err(|e| RemoteError::failed(e.to_string()))?;
        let target = requested_account
            .as_deref()
            .filter(|a| !a.is_empty() && *a != "default");
        engine
            .select_native_provider_account(&current, target)
            .map_err(|e| RemoteError::failed(e.to_string()))?;
        return Ok(());
    }

    runtime.adapter.update_thread_settings(&settings)
}

fn handle_steer_queued(
    runtime: &CoincideMacOSRuntime,
    thread_id: Uuid,
    message_id: Uuid,
) -> Result<(), RemoteError> {
    let id = resolve_thread_id(runtime, thread_id)?;
    let doc = engine_call(runtime, "threads.read", json!({ "threadId": id }))?;
    let queued = message_queue::read(&doc)
        .unwrap_or_default()
        .into_iter()
        .find(|m| Uuid::parse_str(&m.id).ok() == Some(message_id))
        .ok_or_else(|| RemoteError::new(ErrorCode::NotFound, "Queued message not found."))?;
    runtime.adapter.remove_queued(thread_id, message_id)?;
    engine_call(
        runtime,
        "agent.steer",
        json!({ "threadId": id, "text": queued.text }),
    )?;
    Ok(())
}

fn handle_respond(
    runtime: &CoincideMacOSRuntime,
    thread_id: Uuid,
    item_id: Uuid,
    option_id: &str,
    text: Option<&str>,
) -> Result<(), RemoteError> {
    if let Some(note) = text.filter(|t| !t.trim().is_empty()) {
        let id = resolve_thread_id(runtime, thread_id)?;
        let doc = engine_call(runtime, "threads.read", json!({ "threadId": id }))?;
        let item = doc["items"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|i| {
                i["kind"] == "approval"
                    && i["id"].as_str().and_then(|s| Uuid::parse_str(s).ok()) == Some(item_id)
            })
            .ok_or_else(|| {
                RemoteError::new(ErrorCode::NotFound, "That request no longer exists.")
            })?;
        let req_id = item["externalID"]
            .as_str()
            .ok_or_else(RemoteError::bad_request)?;
        let pending = engine_call(runtime, "agent.pending", json!({ "threadId": id }))?;
        let params = pending
            .as_array()
            .into_iter()
            .flatten()
            .find(|p| p["requestId"].as_str() == Some(req_id))
            .map(|p| p["params"].clone())
            .ok_or_else(|| {
                RemoteError::new(ErrorCode::NotAllowed, "That request was already answered.")
            })?;
        if !approval_options(&params).iter().any(|o| o.id == option_id) {
            return Err(RemoteError::new(
                ErrorCode::BadRequest,
                "That choice isn’t offered.",
            ));
        }
        engine_call(
            runtime,
            "agent.respond",
            json!({
                "threadId": id,
                "requestId": req_id,
                "decision": option_id,
                "text": note,
            }),
        )?;
        return Ok(());
    }
    runtime
        .adapter
        .respond(thread_id, item_id, option_id, &runtime.adapter.runs()?)
}

fn handle_thread_action(
    runtime: &CoincideMacOSRuntime,
    thread_id: Uuid,
    action: &ThreadAction,
) -> Result<(), RemoteError> {
    match action {
        ThreadAction::Move(project_uuid) => {
            let id = resolve_thread_id(runtime, thread_id)?;
            let mut engine = runtime
                .engine
                .lock()
                .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
            let projects = engine
                .store
                .projects()
                .map_err(|e| RemoteError::failed(e.to_string()))?;
            let target_id = projects
                .as_array()
                .into_iter()
                .flatten()
                .find_map(|p| {
                    let pid = p["id"].as_str()?;
                    (Uuid::parse_str(pid).ok() == Some(*project_uuid)).then(|| pid.to_owned())
                })
                .unwrap_or_else(|| project_uuid.to_string().to_uppercase());
            let prepared = engine
                .prepare_native_thread_move(&id, &target_id)
                .map_err(|e| RemoteError::failed(e.to_string()))?;
            engine
                .apply_native_thread_move(prepared)
                .map_err(|e| RemoteError::failed(e.to_string()))?;
            Ok(())
        }
        ThreadAction::Delete => {
            let id = resolve_thread_id(runtime, thread_id)?;
            let mut engine = runtime
                .engine
                .lock()
                .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
            let ids = vec![id.clone()];
            let prepared = match engine.prepare_native_conversation_deletion(&ids) {
                Ok(plan) => plan,
                Err(_) => engine
                    .prepare_native_thread_deletion(&ids)
                    .map_err(|e| RemoteError::failed(e.to_string()))?,
            };
            let undo = engine
                .apply_native_thread_deletion(prepared)
                .map_err(|e| RemoteError::failed(e.to_string()))?;
            let shared = Arc::new(Mutex::new(Some(undo)));
            if let Ok(mut map) = runtime.thread_delete_undos.lock() {
                map.insert(id.to_uppercase(), shared);
            }
            Ok(())
        }
        other => runtime.adapter.perform(thread_id, other),
    }
}

fn collect_remote_usage_limits(
    runtime: &CoincideMacOSRuntime,
) -> Result<Vec<protocol::RemoteUsage>, RemoteError> {
    let mut rows = Vec::new();
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| RemoteError::failed("Usage is temporarily unavailable."))?;

    for (provider, provider_name, method) in [
        ("codex", "Codex", "usage.codexLimits.status"),
        ("claude", "Claude Code", "usage.claudeLimits.status"),
    ] {
        let status = engine.dispatch_desktop(json!({ "method": method, "params": {} }))["result"]
            .clone();
        if let Some(windows_val) = status.get("windows").and_then(Value::as_array) {
            let windows: Vec<protocol::RemoteUsageWindow> = windows_val
                .iter()
                .filter_map(|w| {
                    Some(protocol::RemoteUsageWindow {
                        id: w["id"].as_str()?.to_owned(),
                        label: w["label"].as_str().unwrap_or("Limit").to_owned(),
                        used_percent: w["usedPercent"].as_f64().unwrap_or(0.0),
                        resets_at: w["resetsAt"]
                            .as_str()
                            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                            .map(|dt| dt.timestamp_millis()),
                    })
                })
                .collect();
            if !windows.is_empty() {
                rows.push(protocol::RemoteUsage {
                    provider: provider.into(),
                    provider_name: provider_name.into(),
                    account_id: "default".into(),
                    account_name: None,
                    windows,
                    checked_at: status["checkedAt"]
                        .as_str()
                        .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                        .map(|dt| dt.timestamp_millis()),
                });
            }
        }
    }
    Ok(rows)
}

fn handle_extended_request(
    runtime: &CoincideMacOSRuntime,
    kind: &str,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    match kind {
        "diff" => handle_diff(runtime, body),
        "runScript" => handle_run_script(runtime, body),
        "saveBot" => handle_save_bot(runtime, body),
        "deleteBot" => handle_delete_bot(runtime, body),
        "assistants" => Ok(("assistants", build_remote_assistants(runtime)?)),
        "saveAssistant" => handle_save_assistant(runtime, body),
        "deleteAssistant" => handle_delete_assistant(runtime, body),
        "settings" => Ok(("settings", build_remote_settings_snapshot(runtime)?)),
        "changeSetting" => handle_change_setting(runtime, body),
        "settingsAction" => handle_settings_action(runtime, body),
        "settingsDocument" => handle_settings_document(runtime, body),
        "saveSettingsDocument" => handle_save_settings_document(runtime, body),
        "completions" => handle_completions(runtime, body),
        "checkout" => {
            let tid = parse_uuid_field(body, "threadID")?;
            Ok(("checkout", build_remote_checkout(runtime, tid)?))
        }
        "changeCheckout" => handle_change_checkout(runtime, body),
        "usageDashboard" => handle_remote_usage_dashboard(runtime, body),
        "forkThread" => handle_fork_thread(runtime, body),
        "rewindOptions" => handle_rewind_options(runtime, body),
        "rewind" => handle_rewind(runtime, body),
        "composerNotice" => handle_composer_notice(runtime, body),
        "usageWarningAction" => handle_composer_notice(runtime, body),
        "setSidebarOptions" => handle_set_sidebar_options(runtime, body),
        "projectDefaults" => handle_project_defaults(runtime, body),
        "saveProjectDefaults" => handle_save_project_defaults(runtime, body),
        "removeProject" => handle_remove_project(runtime, body),
        "scheduledTasks" => Ok(("scheduledTasks", build_remote_scheduled_tasks(runtime)?)),
        "saveScheduledTask" => handle_save_scheduled_task(runtime, body),
        "scheduledTaskAction" => handle_scheduled_task_action(runtime, body),
        "gitState" => handle_git_state(runtime, body),
        "gitAction" => handle_git_action(runtime, body),
        "pullRequests" => handle_pull_requests(runtime, body),
        "pullRequest" => handle_pull_request(runtime, body),
        "pullRequestAction" => handle_pull_request_action(runtime, body),
        other => Err(RemoteError::unsupported(other)),
    }
}

fn handle_diff(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let thread_uuid = parse_uuid_field(body, "threadID")?;
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;

    if let Some(turn_uuid) = body
        .get("turnID")
        .filter(|v| !v.is_null())
        .map(|v| v.as_str().and_then(|s| Uuid::parse_str(s).ok()))
    {
        let turn_uuid = turn_uuid.ok_or_else(RemoteError::bad_request)?;
        let resp = engine_call(
            runtime,
            "checkpoints.diff",
            json!({
                "threadId": thread_id,
                "userItemId": turn_uuid.to_string(),
            }),
        )?;
        let raw_patch = resp["diff"].as_str().unwrap_or("");
        let truncated = resp["truncated"].as_bool().unwrap_or(false);
        let parsed = workspace_diff::parse_patch(raw_patch);
        let files: Vec<Value> = parsed.iter().map(file_diff_to_remote).collect();
        return Ok((
            "diff",
            json!({
                "title": "Turn changes",
                "files": files,
                "isTruncated": truncated,
            }),
        ));
    }

    let cwd = thread_working_dir(runtime, &thread_id)?;
    let review_val = workspace_diff::review(&cwd, DiffScope::Uncommitted, false)
        .map_err(|e| RemoteError::failed(e.to_string()))?;
    let decoded =
        workspace_diff::decode(&review_val).map_err(|e| RemoteError::failed(e.to_string()))?;
    let (files, is_truncated) = match decoded {
        workspace_diff::Review::NotRepository => (Vec::new(), false),
        workspace_diff::Review::Diff { diff, .. } => (
            diff.files.iter().map(file_diff_to_remote).collect(),
            diff.is_truncated,
        ),
    };
    Ok((
        "diff",
        json!({
            "title": "Uncommitted changes",
            "files": files,
            "isTruncated": is_truncated,
        }),
    ))
}

fn file_diff_to_remote(file: &workspace_diff::FileDiff) -> Value {
    let status = match file.status {
        workspace_diff::ChangeStatus::Added => "added",
        workspace_diff::ChangeStatus::Untracked => "untracked",
        workspace_diff::ChangeStatus::Modified => "modified",
        workspace_diff::ChangeStatus::Deleted => "deleted",
        workspace_diff::ChangeStatus::Renamed => "renamed",
    };
    let mut patch_lines = Vec::new();
    for hunk in &file.hunks {
        patch_lines.push(hunk.header());
        for line in &hunk.lines {
            match line.kind {
                workspace_diff::LineKind::Context => patch_lines.push(format!(" {}", line.text)),
                workspace_diff::LineKind::Addition => patch_lines.push(format!("+{}", line.text)),
                workspace_diff::LineKind::Deletion => patch_lines.push(format!("-{}", line.text)),
                workspace_diff::LineKind::NoNewline => {
                    patch_lines.push("\\ No newline at end of file".into())
                }
            }
        }
    }
    json!({
        "path": file.path,
        "oldPath": file.old_path,
        "status": status,
        "additions": file.additions,
        "deletions": file.deletions,
        "isBinary": file.is_binary,
        "patch": patch_lines.join("\n"),
    })
}

fn handle_run_script(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let thread_uuid = parse_uuid_field(body, "threadID")?;
    let script_uuid = parse_uuid_field(body, "scriptID")?;
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;
    engine_call(
        runtime,
        "terminal.create",
        json!({
            "threadId": thread_id,
            "scriptId": script_uuid.to_string(),
        }),
    )?;
    Ok(("ok", Value::Null))
}

fn handle_save_bot(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let name = body["name"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;
    let character = body["avatar"]["character"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;
    let tint = body["avatar"]["tint"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;
    let persona = body["persona"].as_str().unwrap_or("");

    let list = engine_call(runtime, "bots.list", json!({}))?;
    let baseline = list["baseline"]
        .as_str()
        .ok_or_else(|| RemoteError::failed("Bot settings are unavailable."))?;

    let mut patch = json!({
        "name": name,
        "persona": persona,
        "avatar": { "shape": character, "tint": tint },
    });
    if let Some(personality) = body.get("personality") {
        if personality.is_null() {
            patch["personality"] = Value::Null;
        } else {
            patch["personality"] = personality.clone();
        }
    }

    let existing_id = match body.get("id").filter(|v| !v.is_null()) {
        Some(v) => Some(
            v.as_str()
                .and_then(|s| Uuid::parse_str(s).ok())
                .ok_or_else(RemoteError::bad_request)?,
        ),
        None => None,
    };

    let saved = if let Some(bot_uuid) = existing_id {
        engine_call(
            runtime,
            "bots.patch",
            json!({
                "botId": bot_uuid.to_string().to_uppercase(),
                "baseline": baseline,
                "patch": patch,
            }),
        )?
    } else {
        engine_call(
            runtime,
            "bots.save",
            json!({
                "baseline": baseline,
                "patch": patch,
            }),
        )?
    };
    let saved_id = saved["bot"]["id"]
        .as_str()
        .ok_or_else(|| RemoteError::failed("Bot ID missing after save."))?
        .to_uppercase();
    Ok(("bot", protocol::value_body(saved_id)))
}

fn handle_delete_bot(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let bot_uuid = parse_uuid_field(body, "botID")?;
    let deletes_conversations = body["deletesConversations"].as_bool().unwrap_or(false);
    let disposition = if deletes_conversations {
        BotConversationDisposition::Delete
    } else {
        BotConversationDisposition::KeepAsChats
    };
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
    let bot_id = bot_uuid.to_string().to_uppercase();
    let _ = engine.request_native_bot_stop(&bot_id);
    let prepared = engine
        .prepare_native_bot_deletion(&bot_id, disposition)
        .map_err(|e| RemoteError::failed(e.to_string()))?;
    let _undo = engine
        .apply_native_bot_deletion(prepared)
        .map_err(|e| RemoteError::failed(e.to_string()))?;
    Ok(("ok", Value::Null))
}

fn build_remote_assistants(runtime: &CoincideMacOSRuntime) -> Result<Value, RemoteError> {
    let resp = engine_call(runtime, "assistants.list", json!({}))?;
    let mut out = Vec::new();
    for item in resp["assistants"].as_array().into_iter().flatten() {
        let Some(id_uuid) = item["id"]
            .as_str()
            .and_then(|s| Uuid::parse_str(s).ok())
        else {
            continue;
        };
        let mut assistant = item.clone();
        assistant["id"] = json!(id_uuid.to_string().to_uppercase());
        for key in ["lastUsedAt", "createdAt", "updatedAt"] {
            if let Some(secs) = item[key].as_i64() {
                assistant[key] = json!(secs * 1000);
            }
        }
        out.push(assistant);
    }
    Ok(json!({
        "assistants": out,
        "baseline": resp["baseline"].as_str().unwrap_or(""),
        "origin": resp["origin"].as_str().unwrap_or("empty"),
    }))
}

fn handle_save_assistant(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let list = engine_call(runtime, "assistants.list", json!({}))?;
    let baseline = list["baseline"]
        .as_str()
        .ok_or_else(|| RemoteError::failed("Assistant settings are unavailable."))?;
    let mut assistant = body
        .get("assistant")
        .cloned()
        .unwrap_or_else(|| body.clone());
    let object = assistant
        .as_object_mut()
        .ok_or_else(RemoteError::bad_request)?;
    if object
        .get("id")
        .and_then(Value::as_str)
        .is_none_or(str::is_empty)
    {
        object.insert(
            "id".to_string(),
            json!(Uuid::new_v4().to_string().to_uppercase()),
        );
    } else if let Some(id) = object.get("id").and_then(Value::as_str) {
        let id = id.to_uppercase();
        object.insert("id".to_string(), json!(id));
    }
    object.remove("createdAt");
    object.remove("updatedAt");
    object.remove("lastUsedAt");
    let saved = engine_call(
        runtime,
        "assistants.save",
        json!({
            "assistant": assistant,
            "baseline": baseline,
        }),
    )?;
    let saved_id = saved["assistant"]["id"]
        .as_str()
        .ok_or_else(|| RemoteError::failed("Assistant ID missing after save."))?
        .to_uppercase();
    Ok(("assistant", protocol::value_body(saved_id)))
}

fn handle_delete_assistant(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let assistant_uuid = parse_uuid_field(body, "assistantID")?;
    let list = engine_call(runtime, "assistants.list", json!({}))?;
    let baseline = list["baseline"]
        .as_str()
        .ok_or_else(|| RemoteError::failed("Assistant settings are unavailable."))?;
    engine_call(
        runtime,
        "assistants.delete",
        json!({
            "assistantId": assistant_uuid.to_string().to_uppercase(),
            "baseline": baseline,
        }),
    )?;
    Ok(("ok", Value::Null))
}

fn build_remote_settings_snapshot(runtime: &CoincideMacOSRuntime) -> Result<Value, RemoteError> {
    let settings = engine_call(runtime, "settings.read", json!({}))?;
    let appearance = settings["appearance"].as_str().unwrap_or("system");
    let show_reasoning = settings["showReasoning"].as_bool().unwrap_or(true);
    let follow_up = settings["followUpBehavior"].as_str().unwrap_or("steer");
    let confirm_delete = settings["confirmBeforeDeletingThreads"]
        .as_bool()
        .unwrap_or(true);
    let checkpoints = settings["checkpointsEnabled"].as_bool().unwrap_or(true);
    let cli_control = settings["commandLineControl"].as_bool().unwrap_or(true);
    let worker_retention = settings["workerRetentionCount"]
        .as_u64()
        .or_else(|| {
            settings["workerRetentionCount"]
                .as_f64()
                .map(|value| value.max(0.0) as u64)
        })
        .unwrap_or(50);

    let pages = json!([
        {
            "id": "general",
            "title": "General",
            "symbol": "gearshape",
            "color": "gray",
            "group": "app",
            "sections": [
                {
                    "id": "appearance",
                    "title": "Appearance",
                    "rows": [
                        {
                            "id": "appearance",
                            "kind": "choice",
                            "title": "Appearance",
                            "value": appearance,
                            "options": [
                                { "id": "system", "title": "System" },
                                { "id": "light", "title": "Light" },
                                { "id": "dark", "title": "Dark" }
                            ]
                        },
                        {
                            "id": "showReasoning",
                            "kind": "toggle",
                            "title": "Show Reasoning",
                            "value": show_reasoning
                        }
                    ]
                },
                {
                    "id": "composer",
                    "title": "Conversations",
                    "rows": [
                        {
                            "id": "followUpBehavior",
                            "kind": "choice",
                            "title": "While Turn Is Running",
                            "value": follow_up,
                            "options": [
                                { "id": "steer", "title": "Steer" },
                                { "id": "queue", "title": "Queue" }
                            ]
                        },
                        {
                            "id": "checkpointsEnabled",
                            "kind": "toggle",
                            "title": "Turn Checkpoints",
                            "value": checkpoints
                        },
                        {
                            "id": "confirmBeforeDeletingThreads",
                            "kind": "toggle",
                            "title": "Confirm Before Deleting Threads",
                            "value": confirm_delete
                        },
                        {
                            "id": "commandLineControl",
                            "kind": "toggle",
                            "title": "Command-Line Control",
                            "value": cli_control
                        }
                    ]
                },
                {
                    "id": "workers",
                    "title": "Workers",
                    "footer": "Finished workers are kept per parent thread. 0 keeps every finished worker record.",
                    "rows": [
                        {
                            "id": "workerRetentionCount",
                            "kind": "number",
                            "title": "Keep Finished Workers",
                            "detail": "Most recent finished worker records kept per parent thread",
                            "value": worker_retention,
                            "minimum": 0,
                            "maximum": 500,
                            "step": 1,
                            "unit": "records"
                        }
                    ]
                }
            ]
        }
    ]);
    Ok(json!({ "pages": pages }))
}

fn handle_change_setting(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let key = body["key"].as_str().ok_or_else(RemoteError::bad_request)?;
    let value = body
        .get("value")
        .ok_or_else(RemoteError::bad_request)?
        .clone();
    if !matches!(
        key,
        "appearance"
            | "darkTheme"
            | "lightTheme"
            | "showReasoning"
            | "followUpBehavior"
            | "replyTypeface"
            | "userMessageSide"
            | "checkpointsEnabled"
            | "confirmBeforeDeletingThreads"
            | "commandLineControl"
            | "workerRetentionCount"
            | "sendOnReturn"
    ) {
        return Err(RemoteError::new(
            ErrorCode::NotAllowed,
            "This setting cannot be changed through this action.",
        ));
    }
    let mut patch = serde_json::Map::new();
    patch.insert(key.to_owned(), value);
    engine_call(runtime, "settings.patch", json!({ "patch": patch }))?;
    Ok(("settings", build_remote_settings_snapshot(runtime)?))
}

fn handle_settings_action(
    runtime: &CoincideMacOSRuntime,
    _body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    Ok(("settings", build_remote_settings_snapshot(runtime)?))
}

fn document_version_hash(text: &str) -> String {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    text.as_bytes().hash(&mut hasher);
    text.len().hash(&mut hasher);
    format!("{:016x}-{}", hasher.finish(), text.len())
}

fn resolve_settings_doc_path(key: &str) -> Result<(&'static str, PathBuf), RemoteError> {
    let home =
        discovery::home_dir().ok_or_else(|| RemoteError::failed("Home folder unavailable."))?;
    Ok(match key {
        "instructions.claude" => ("CLAUDE.md", home.join(".claude/CLAUDE.md")),
        "instructions.gemini" => ("GEMINI.md", home.join(".gemini/GEMINI.md")),
        _ => ("AGENTS.md", home.join(".codex/AGENTS.md")),
    })
}

fn handle_settings_document(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let key = body["key"].as_str().ok_or_else(RemoteError::bad_request)?;
    let (title, path) = resolve_settings_doc_path(key)?;
    let read_res = crate::workspace_ops::instructions_read(
        runtime,
        &json!({ "path": path }),
    )
    .map_err(|e| RemoteError::failed(e.to_string()))?;
    let text = read_res["content"].as_str().unwrap_or("");
    let version = document_version_hash(text);
    Ok((
        "settingsDocument",
        json!({
            "key": key,
            "title": title,
            "text": text,
            "version": version,
        }),
    ))
}

fn handle_save_settings_document(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let key = body["key"].as_str().ok_or_else(RemoteError::bad_request)?;
    let text = body["text"].as_str().ok_or_else(RemoteError::bad_request)?;
    let expected_version = body["version"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;
    let (title, path) = resolve_settings_doc_path(key)?;

    let current = crate::workspace_ops::instructions_read(runtime, &json!({ "path": path }))
        .map_err(|e| RemoteError::failed(e.to_string()))?;
    let current_text = current["content"].as_str().unwrap_or("");
    if document_version_hash(current_text) != expected_version {
        return Err(RemoteError::new(
            ErrorCode::Conflict,
            "This instruction file changed since it was opened. Reload before saving.",
        ));
    }

    crate::workspace_ops::instructions_save(
        runtime,
        &json!({
            "path": path,
            "content": text,
            "expectedContent": current_text,
        }),
    )
    .map_err(|e| RemoteError::failed(e.to_string()))?;

    let new_version = document_version_hash(text);
    Ok((
        "settingsDocument",
        json!({
            "key": key,
            "title": title,
            "text": text,
            "version": new_version,
        }),
    ))
}

fn handle_completions(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let thread_uuid = parse_uuid_field(body, "threadID")?;
    let trigger = body["trigger"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;
    let query = body["query"].as_str().unwrap_or("");
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;

    let mut items = Vec::new();
    match trigger {
        "@" => {
            let cwd = thread_working_dir(runtime, &thread_id)?;
            if let Ok(res) = workspace::files(&cwd, query, 40) {
                for p in res["files"].as_array().into_iter().flatten() {
                    if let Some(path_str) = p.as_str() {
                        let (parent, file_name) = path_str.rsplit_once('/').unwrap_or(("", path_str));
                        items.push(json!({
                            "kind": "file",
                            "insert": format!("@{path_str} "),
                            "title": file_name,
                            "detail": (!parent.is_empty()).then_some(parent),
                        }));
                    }
                }
            }
        }
        "/" | "$" => {
            let q = query.to_lowercase();
            let builtins = composer_suggestions::BuiltIn::available(&[], false);
            if trigger == "/" {
                for b in builtins {
                    let name = match &b {
                        composer_suggestions::BuiltIn::Model => "model",
                        composer_suggestions::BuiltIn::Plan => "plan",
                        composer_suggestions::BuiltIn::Build => "build",
                        composer_suggestions::BuiltIn::UsageLimits => "usage-limits",
                        composer_suggestions::BuiltIn::Agent { provider, .. } => provider.as_str(),
                    };
                    if q.is_empty() || name.contains(&q) {
                        items.push(json!({
                            "kind": "command",
                            "insert": format!("/{name} "),
                            "title": format!("/{name}"),
                            "detail": Value::Null,
                        }));
                    }
                }
            }
            if let Ok(reported) =
                engine_call(runtime, "composer.commands", json!({ "threadId": thread_id }))
            {
                for cmd in reported["commands"].as_array().into_iter().flatten() {
                    let Some(name) = cmd["name"].as_str() else {
                        continue;
                    };
                    let is_skill = cmd["kind"].as_str() == Some("skill");
                    if trigger == "$" && !is_skill {
                        continue;
                    }
                    if q.is_empty() || name.to_lowercase().contains(&q) {
                        let prefix = if is_skill && trigger == "$" { "$" } else { "/" };
                        items.push(json!({
                            "kind": if is_skill { "skill" } else { "command" },
                            "insert": format!("{prefix}{name} "),
                            "title": format!("{prefix}{name}"),
                            "detail": cmd["description"].as_str(),
                        }));
                    }
                    if items.len() >= 40 {
                        break;
                    }
                }
            }
        }
        _ => {}
    }
    items.truncate(40);
    Ok(("completions", protocol::value_body(items)))
}

fn build_remote_checkout(runtime: &CoincideMacOSRuntime, thread_uuid: Uuid) -> Result<Value, RemoteError> {
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;
    let (doc, toolbar, is_running) = {
        let mut engine = runtime
            .engine
            .lock()
            .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
        let doc = engine
            .store
            .thread(&thread_id)
            .map_err(|_| RemoteError::thread_not_found())?;
        let toolbar = engine.dispatch(json!({
            "method": "git.toolbar.state",
            "params": { "threadId": thread_id },
        }))["result"]
            .clone();
        let status = engine.dispatch_desktop(json!({ "method": "app.status", "params": {} }))["result"]
            .clone();
        let running = status["running"]
            .as_array()
            .into_iter()
            .flatten()
            .any(|r| r.as_str() == Some(thread_id.as_str()));
        (doc, toolbar, running)
    };

    let started = doc["items"]
        .as_array()
        .is_some_and(|items| items.iter().any(|i| i["kind"] == "user"));
    let has_worktree = doc["worktreePath"].as_str().is_some_and(|s| !s.is_empty());
    let base_branch = toolbar["baseBranch"].as_str().map(str::to_owned);
    let preparing = toolbar["preparing"].as_bool().unwrap_or(false);
    let prev_wt = toolbar.get("previousWorktree").filter(|v| v.is_object());

    let workspace_kind = if has_worktree {
        if !started && base_branch.is_some() {
            "newWorktree"
        } else {
            "worktree"
        }
    } else {
        "local"
    };

    let cwd = thread_working_dir(runtime, &thread_id)?;
    let branch_list = git_ops::branches(&cwd).unwrap_or_default();
    let current_branch = branch_list
        .current_branch
        .clone()
        .or_else(|| doc["branch"].as_str().map(str::to_owned));

    let branches: Vec<Value> = branch_list
        .branches
        .iter()
        .take(80)
        .map(|b| {
            let checked_out_elsewhere = b
                .worktree_path
                .as_deref()
                .is_some_and(|wt| Path::new(wt) != cwd);
            json!({
                "name": b.name,
                "isCurrent": b.is_current,
                "isRemote": b.is_remote,
                "isCheckedOutElsewhere": checked_out_elsewhere,
            })
        })
        .collect();

    let is_busy = is_running || preparing;
    let can_change_ws = !started && !is_busy && branch_list.is_repository;
    let can_pick = !is_busy && branch_list.is_repository && (!has_worktree || !started);
    let can_create = !is_busy && branch_list.is_repository && !has_worktree;

    Ok(json!({
        "workspace": workspace_kind,
        "canChangeWorkspace": can_change_ws,
        "hasPreviousWorktree": prev_wt.is_some(),
        "previousWorktreeBranch": prev_wt.and_then(|p| p["branch"].as_str()),
        "branch": current_branch,
        "baseBranch": base_branch.or_else(|| branch_list.default_branch.clone()),
        "canPickBranch": can_pick,
        "canCreateBranch": can_create,
        "branches": branches,
        "isBusy": is_busy,
    }))
}

fn wait_git_operation(
    runtime: &CoincideMacOSRuntime,
    thread_id: &str,
    op_id: &str,
) -> Result<Value, RemoteError> {
    let deadline = Instant::now() + Duration::from_secs(60);
    loop {
        let res = engine_call(
            runtime,
            "git.actions.result",
            json!({ "threadId": thread_id, "operationId": op_id }),
        )?;
        if res["ready"] == true {
            let inner = res["result"].clone();
            if let Some(err) = inner.get("error").and_then(Value::as_str) {
                return Err(RemoteError::failed(err));
            }
            return Ok(inner);
        }
        if Instant::now() >= deadline {
            return Err(RemoteError::failed("Git operation timed out."));
        }
        std::thread::sleep(Duration::from_millis(30));
    }
}

fn handle_change_checkout(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let thread_uuid = parse_uuid_field(body, "threadID")?;
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;
    let action = body
        .get("checkoutAction")
        .or_else(|| body.get("action"))
        .ok_or_else(RemoteError::bad_request)?;
    let action_type = action["type"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;

    let dispatched = match action_type {
        "useLocal" => engine_call(
            runtime,
            "git.worktrees.useCheckout",
            json!({ "threadId": thread_id }),
        )?,
        "useNewWorktree" => engine_call(
            runtime,
            "git.worktrees.useNew",
            json!({ "threadId": thread_id }),
        )?,
        "usePreviousWorktree" => {
            let toolbar = engine_call(
                runtime,
                "git.toolbar.state",
                json!({ "threadId": thread_id }),
            )?;
            let prev = toolbar
                .get("previousWorktree")
                .filter(|v| v.is_object())
                .ok_or_else(|| RemoteError::failed("No previous worktree available."))?;
            engine_call(
                runtime,
                "git.worktrees.useExisting",
                json!({
                    "threadId": thread_id,
                    "path": prev["path"],
                    "branch": prev["branch"],
                }),
            )?
        }
        "useExistingWorktree" => {
            let path = action["path"]
                .as_str()
                .ok_or_else(RemoteError::bad_request)?;
            engine_call(
                runtime,
                "git.worktrees.useExisting",
                json!({
                    "threadId": thread_id,
                    "path": path,
                    "branch": action["branch"],
                }),
            )?
        }
        "pickBranch" => {
            let branch = action["branch"]
                .as_str()
                .ok_or_else(RemoteError::bad_request)?;
            let toolbar = engine_call(
                runtime,
                "git.toolbar.state",
                json!({ "threadId": thread_id }),
            )?;
            if toolbar.get("baseBranch").is_some_and(|v| !v.is_null()) {
                engine_call(
                    runtime,
                    "git.worktrees.useNew",
                    json!({ "threadId": thread_id, "baseBranch": branch }),
                )?
            } else {
                engine_call(
                    runtime,
                    "git.branches.checkout",
                    json!({ "threadId": thread_id, "name": branch }),
                )?
            }
        }
        "createBranch" => {
            let branch = action["branch"]
                .as_str()
                .ok_or_else(RemoteError::bad_request)?;
            engine_call(
                runtime,
                "git.branches.create",
                json!({ "threadId": thread_id, "name": branch }),
            )?
        }
        _ => return Err(RemoteError::bad_request()),
    };

    if let Some(op_id) = dispatched["operationId"].as_str() {
        wait_git_operation(runtime, &thread_id, op_id)?;
    }
    Ok(("checkout", build_remote_checkout(runtime, thread_uuid)?))
}

fn format_compact_tokens(tokens: u64) -> String {
    if tokens >= 1_000_000_000 {
        format!("{:.1}B", tokens as f64 / 1_000_000_000.0)
    } else if tokens >= 1_000_000 {
        format!("{:.1}M", tokens as f64 / 1_000_000.0)
    } else if tokens >= 1_000 {
        format!("{:.1}K", tokens as f64 / 1_000.0)
    } else {
        tokens.to_string()
    }
}

fn format_usd(cost: f64) -> String {
    format!("${cost:.2}")
}

fn handle_remote_usage_dashboard(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let days = body["days"].as_u64().unwrap_or(30).clamp(1, 365) as u32;
    let provider = body["provider"].as_str().filter(|s| !s.is_empty());
    let account_id = body["accountID"].as_str().filter(|s| !s.is_empty());
    let refresh = body["refresh"].as_bool().unwrap_or(false);

    let raw = crate::workspace_ops::usage_dashboard(
        runtime,
        &json!({
            "days": days,
            "provider": provider,
            "accountId": account_id,
            "refresh": refresh,
        }),
    )
    .map_err(|e| RemoteError::failed(e.to_string()))?;

    let tile = |title: &str, current: &Value, trend: Option<f64>| {
        let tokens = current["totalTokens"].as_u64().unwrap_or(0);
        let cost = current["estimatedCostUsd"].as_f64().unwrap_or(0.0);
        json!({
            "title": title,
            "tokens": format_compact_tokens(tokens),
            "cost": format_usd(cost),
            "trend": trend.map(|t| format!("{:+.0}%", t * 100.0)),
            "trendIsUp": trend.is_some_and(|t| t > 0.0),
        })
    };

    let tiles = vec![
        tile("Today", &raw["today"], raw["todayTrend"].as_f64()),
        tile("Last 7 days", &raw["lastWeek"], raw["weekTrend"].as_f64()),
        tile("Last 30 days", &raw["lastMonth"], raw["monthTrend"].as_f64()),
    ];

    let period_tokens = raw["period"]["totalTokens"].as_u64().unwrap_or(0).max(1) as f64;
    let daily: Vec<Value> = raw["daily"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|d| {
            json!({
                "day": d["dayMs"].as_i64().unwrap_or(0) as f64,
                "provider": d["provider"],
                "tokens": d["totals"]["totalTokens"].as_u64().unwrap_or(0) as f64,
                "cost": d["totals"]["estimatedCostUsd"].as_f64().unwrap_or(0.0),
            })
        })
        .collect();

    let top_models: Vec<Value> = raw["models"]
        .as_array()
        .into_iter()
        .flatten()
        .take(8)
        .map(|m| {
            let tok = m["totals"]["totalTokens"].as_u64().unwrap_or(0);
            let cost = m["totals"]["estimatedCostUsd"].as_f64().unwrap_or(0.0);
            json!({
                "title": m["model"],
                "provider": m["provider"],
                "share": (tok as f64 / period_tokens).clamp(0.0, 1.0),
                "tokens": format_compact_tokens(tok),
                "cost": format_usd(cost),
            })
        })
        .collect();

    let top_projects: Vec<Value> = raw["projects"]
        .as_array()
        .into_iter()
        .flatten()
        .take(8)
        .map(|p| {
            let tok = p["totals"]["totalTokens"].as_u64().unwrap_or(0);
            let cost = p["totals"]["estimatedCostUsd"].as_f64().unwrap_or(0.0);
            json!({
                "title": p["projectName"],
                "provider": Value::Null,
                "share": (tok as f64 / period_tokens).clamp(0.0, 1.0),
                "tokens": format_compact_tokens(tok),
                "cost": format_usd(cost),
            })
        })
        .collect();

    let provider_choices: Vec<Value> = coincide_core::provider_catalog::PROVIDERS
        .iter()
        .map(|d| {
            json!({
                "id": discovery::provider_id_str(d.id),
                "title": d.display_name,
            })
        })
        .collect();

    let scope_title = provider
        .and_then(|p| {
            coincide_core::provider_catalog::PROVIDERS
                .iter()
                .find(|d| discovery::provider_id_str(d.id) == p)
                .map(|d| d.display_name)
        })
        .unwrap_or("All Agents");

    Ok((
        "usageDashboard",
        json!({
            "scopeTitle": scope_title,
            "periodName": format!("Last {days} days"),
            "days": days,
            "provider": provider,
            "accountID": account_id,
            "providers": provider_choices,
            "accountChoices": [],
            "tiles": tiles,
            "daily": daily,
            "topModels": top_models,
            "topProjects": top_projects,
            "activity": [
                {
                    "title": "Turns",
                    "value": raw["period"]["requests"].as_u64().unwrap_or(0).to_string()
                }
            ],
            "accounts": [],
            "isScanning": false,
            "updatedAt": Utc::now().timestamp_millis() as f64,
        }),
    ))
}

fn handle_fork_thread(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let thread_uuid = parse_uuid_field(body, "threadID")?;
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;
    let item_id = match body.get("itemID").filter(|v| !v.is_null()) {
        Some(v) => Some(
            v.as_str()
                .and_then(|s| Uuid::parse_str(s).ok())
                .ok_or_else(RemoteError::bad_request)?,
        ),
        None => None,
    };

    let mut params = json!({ "threadId": thread_id });
    if let Some(item) = item_id {
        params["itemId"] = json!(item.to_string());
    }
    let forked = engine_call(runtime, "threads.fork", params)?;
    let new_id = forked["id"]
        .as_str()
        .ok_or_else(|| RemoteError::failed("Forked thread ID missing."))?
        .to_uppercase();
    Ok(("thread", protocol::value_body(new_id)))
}

fn handle_rewind_options(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let thread_uuid = parse_uuid_field(body, "threadID")?;
    let item_uuid = parse_uuid_field(body, "itemID")?;
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;
    let runs = runtime.adapter.runs()?;
    let is_running = runs.running.contains(&thread_id.to_uppercase());
    let can_restore = if is_running {
        false
    } else {
        engine_call(
            runtime,
            "checkpoints.canRestore",
            json!({
                "threadId": thread_id,
                "userItemId": item_uuid.to_string(),
            }),
        )
        .ok()
        .and_then(|v| v["canRestore"].as_bool())
        .unwrap_or(false)
    };
    Ok((
        "rewindOptions",
        json!({
            "canRevertFiles": can_restore,
            "isRunning": is_running,
        }),
    ))
}

fn handle_rewind(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let thread_uuid = parse_uuid_field(body, "threadID")?;
    let item_uuid = parse_uuid_field(body, "itemID")?;
    let reverts_files = body["revertsFiles"].as_bool().unwrap_or(false);
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;

    let res = engine_call(
        runtime,
        "threads.rewind",
        json!({
            "threadId": thread_id,
            "itemId": item_uuid.to_string(),
            "revertFiles": reverts_files,
        }),
    )?;
    let thread = &res["thread"];
    let text = thread["draft"].as_str().unwrap_or("");
    let attachments: Vec<String> = thread["rustDraftImages"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|img| img["originalName"].as_str().map(str::to_owned))
        .collect();
    Ok((
        "rewind",
        json!({
            "text": text,
            "attachments": attachments,
        }),
    ))
}

fn handle_composer_notice(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let thread_uuid = parse_uuid_field(body, "threadID")?;
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;
    let doc = engine_call(runtime, "threads.read", json!({ "threadId": thread_id }))?;
    let provider = doc["selection"]["provider"].as_str().unwrap_or("codex");

    let method = match provider {
        "codex" => Some(("Codex", "usage.codexLimits.status")),
        "claude" => Some(("Claude", "usage.claudeLimits.status")),
        _ => None,
    };
    if let Some((label, rpc)) = method
        && let Ok(status) = engine_call(runtime, rpc, json!({}))
        && let Ok(raw_limits) = serde_json::from_value::<usage_limits::Limits>(status["limits"].clone())
    {
        let now = Utc::now();
        let limits = raw_limits.current(now);
        if let Some(warn) = limits.warning() {
            let text = usage_limits::warning_text(
                warn,
                label,
                usage_limits::DisplayMode::Used,
                now,
            );
            return Ok((
                "composerNotice",
                json!({
                    "usageWarning": {
                        "key": format!("{provider}:{}", warn.id),
                        "text": text,
                        "fraction": warn.bar_fill(usage_limits::DisplayMode::Used),
                        "canResumeAtReset": false,
                    }
                }),
            ));
        }
    }

    Ok(("composerNotice", json!({ "usageWarning": Value::Null })))
}

fn handle_set_sidebar_options(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let mut patch = serde_json::Map::new();
    for key in ["projectSort", "threadSort", "chatSort", "botSort"] {
        if let Some(v) = body.get(key).filter(|v| v.is_string()) {
            patch.insert(key.to_owned(), v.clone());
        }
    }
    if let Some(tpp) = body.get("threadsPerProject") {
        patch.insert("threadsPerProject".into(), tpp.clone());
    }
    if !patch.is_empty() {
        engine_call(runtime, "settings.patch", json!({ "patch": patch }))?;
    }
    Ok(("ok", Value::Null))
}

fn handle_project_defaults(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let project_uuid = parse_uuid_field(body, "projectID")?;
    let engine = runtime
        .engine
        .lock()
        .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
    let target_id = resolve_project_id_str(&engine.store, project_uuid)?;
    let review = engine
        .native_project_defaults(&target_id)
        .map_err(|e| RemoteError::failed(e.to_string()))?;
    let eff = review.effective();
    Ok((
        "projectDefaults",
        json!({
            "projectID": project_uuid.to_string().to_uppercase(),
            "usesGlobalDefaults": review.inherits_global(),
            "provider": eff["selection"]["provider"].as_str().unwrap_or("codex"),
            "modelID": eff["selection"]["modelID"].as_str().unwrap_or("default"),
            "effort": eff["selection"]["effort"].as_str(),
            "accessMode": eff["accessMode"].as_str().unwrap_or("approval"),
            "interactionMode": eff["interactionMode"].as_str().unwrap_or("build"),
        }),
    ))
}

fn handle_save_project_defaults(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let project_uuid = parse_uuid_field(body, "projectID")?;
    let uses_global = body["usesGlobalDefaults"]
        .as_bool()
        .ok_or_else(RemoteError::bad_request)?;
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
    let target_id = resolve_project_id_str(&engine.store, project_uuid)?;
    let review = engine
        .native_project_defaults(&target_id)
        .map_err(|e| RemoteError::failed(e.to_string()))?;

    if uses_global {
        engine
            .native_save_project_defaults(&review, None)
            .map_err(|e| RemoteError::failed(e.to_string()))?;
    } else {
        let provider = body["provider"]
            .as_str()
            .ok_or_else(RemoteError::bad_request)?;
        let model_id = body["modelID"]
            .as_str()
            .ok_or_else(RemoteError::bad_request)?;
        let mut selection = json!({
            "provider": provider,
            "modelID": model_id,
        });
        if let Some(effort) = body["effort"].as_str().filter(|s| !s.is_empty()) {
            selection["effort"] = json!(effort);
        }
        let defaults = json!({
            "selection": selection,
            "accessMode": body["accessMode"].as_str().unwrap_or("approval"),
            "interactionMode": body["interactionMode"].as_str().unwrap_or("build"),
        });
        engine
            .native_save_project_defaults(&review, Some(&defaults))
            .map_err(|e| RemoteError::failed(e.to_string()))?;
    }
    drop(engine);
    handle_project_defaults(runtime, &json!({ "projectID": project_uuid }))
}

fn resolve_project_id_str(
    store: &coincide_core::store::Store,
    project_uuid: Uuid,
) -> Result<String, RemoteError> {
    let projects = store
        .projects()
        .map_err(|e| RemoteError::failed(e.to_string()))?;
    projects
        .as_array()
        .into_iter()
        .flatten()
        .find_map(|p| {
            let pid = p["id"].as_str()?;
            (Uuid::parse_str(pid).ok() == Some(project_uuid)).then(|| pid.to_owned())
        })
        .ok_or_else(|| RemoteError::new(ErrorCode::NotFound, "That project no longer exists."))
}

fn handle_remove_project(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let project_uuid = parse_uuid_field(body, "projectID")?;
    let target_id = {
        let engine = runtime
            .engine
            .lock()
            .map_err(|_| RemoteError::failed("Application state is unavailable."))?;
        resolve_project_id_str(&engine.store, project_uuid)?
    };
    let preview = engine_call(
        runtime,
        "projects.prepare",
        json!({
            "projectId": target_id,
            "action": "remove",
        }),
    )?;
    let ticket = preview["ticket"]
        .as_str()
        .ok_or_else(|| RemoteError::failed("Project removal ticket missing."))?;
    let count = preview["threadCount"].as_u64().unwrap_or(0);
    engine_call(
        runtime,
        "projects.remove",
        json!({
            "projectId": target_id,
            "ticket": ticket,
            "confirmed": true,
            "confirmedThreadCount": count,
        }),
    )?;
    Ok(("ok", Value::Null))
}

fn build_remote_scheduled_tasks(runtime: &CoincideMacOSRuntime) -> Result<Value, RemoteError> {
    let resp = engine_call(runtime, "schedules.list", json!({}))?;
    let error = resp["error"].as_str().map(str::to_owned);
    let mut out_tasks = Vec::new();
    for t in resp["tasks"].as_array().into_iter().flatten() {
        let Some(id_uuid) = t["id"].as_str().and_then(|s| Uuid::parse_str(s).ok()) else {
            continue;
        };
        let proj_uuid = t["projectID"]
            .as_str()
            .and_then(|s| Uuid::parse_str(s).ok())
            .unwrap_or_default();
        let rec = &t["recurrence"];
        let rec_date_ms = stored_date_ms(&rec["date"])
            .or_else(|| {
                scheduling::parse_date(&rec["date"])
                    .ok()
                    .map(|dt| dt.timestamp_millis() as f64)
            })
            .unwrap_or_else(|| Utc::now().timestamp_millis() as f64);
        let is_paused = t["isPaused"].as_bool().unwrap_or(false);
        let needs_approval = t["awaitingApproval"].as_bool().unwrap_or(false);
        let state = if is_paused {
            "paused"
        } else {
            t["lastOutcome"].as_str().unwrap_or("scheduled")
        };
        let state_text = if needs_approval {
            "Needs Approval"
        } else if is_paused {
            "Paused"
        } else {
            "Scheduled"
        };
        let kind = rec["kind"].as_str().unwrap_or("daily");
        let hour = rec["hour"].as_i64().unwrap_or(9);
        let minute = rec["minute"].as_i64().unwrap_or(0);
        let schedule_text = format!("{kind} at {hour:02}:{minute:02}");
        let next_run_ms = scheduling::parse_date(&t["nextRunAt"])
            .ok()
            .map(|dt| dt.timestamp_millis() as f64);
        let last_run_ms = scheduling::parse_date(&t["lastRunAt"])
            .ok()
            .map(|dt| dt.timestamp_millis() as f64);

        out_tasks.push(json!({
            "id": id_uuid.to_string().to_uppercase(),
            "name": t["name"].as_str().unwrap_or("Task"),
            "projectID": proj_uuid.to_string().to_uppercase(),
            "prompt": t["prompt"].as_str().unwrap_or(""),
            "recurrence": {
                "kind": kind,
                "timeZoneID": rec["timeZoneID"].as_str().unwrap_or("UTC"),
                "date": rec_date_ms,
                "hour": hour,
                "minute": minute,
                "weekday": rec["weekday"].as_i64().unwrap_or(2),
            },
            "isPaused": is_paused,
            "state": state,
            "stateText": state_text,
            "scheduleText": schedule_text,
            "nextRunAt": next_run_ms,
            "lastRunAt": last_run_ms,
            "lastMessage": t["lastError"].as_str(),
            "lastThreadID": t["lastThreadID"].as_str().and_then(|s| Uuid::parse_str(s).ok()).map(|u| u.to_string().to_uppercase()),
            "canRunNow": !needs_approval,
            "threadID": t["threadID"].as_str().and_then(|s| Uuid::parse_str(s).ok()).map(|u| u.to_string().to_uppercase()),
            "needsApproval": needs_approval,
            "createdByAgent": t["createdByAgent"].as_bool(),
        }));
    }
    Ok(json!({
        "tasks": out_tasks,
        "error": error,
    }))
}

fn handle_save_scheduled_task(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let name = body["name"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;
    let project_uuid = parse_uuid_field(body, "projectID")?;
    let prompt = body["prompt"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;
    let is_paused = body["isPaused"].as_bool().unwrap_or(false);

    let mut rec_json = body.get("recurrence").cloned().unwrap_or(Value::Null);
    if let Some(ms) = rec_json["date"].as_f64() {
        rec_json["date"] = json!(coincide_core::remote::adapter::swift_seconds(ms));
    }

    if let Some(existing_id) = body
        .get("id")
        .filter(|v| !v.is_null())
        .and_then(Value::as_str)
    {
        let mut patch = json!({
            "name": name,
            "projectID": project_uuid.to_string().to_uppercase(),
            "prompt": prompt,
            "isPaused": is_paused,
        });
        if !rec_json.is_null() {
            patch["recurrence"] = rec_json;
        }
        engine_call(
            runtime,
            "schedules.patch",
            json!({
                "scheduleId": existing_id,
                "patch": patch,
            }),
        )?;
    } else {
        let mut task = json!({
            "name": name,
            "projectID": project_uuid.to_string().to_uppercase(),
            "prompt": prompt,
            "recurrence": rec_json,
            "isPaused": is_paused,
        });
        if let Some(tid) = body["threadID"].as_str().filter(|s| !s.is_empty()) {
            task["threadID"] = json!(tid);
        }
        engine_call(runtime, "schedules.create", json!({ "task": task }))?;
    }
    Ok(("scheduledTasks", build_remote_scheduled_tasks(runtime)?))
}

fn handle_scheduled_task_action(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let task_uuid = parse_uuid_field(body, "taskID")?;
    let action = body["action"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;
    let id_str = task_uuid.to_string();
    let method = match action {
        "pause" => "schedules.pause",
        "resume" => "schedules.resume",
        "runNow" => "schedules.run-now",
        "delete" => "schedules.delete",
        _ => return Err(RemoteError::bad_request()),
    };
    engine_call(runtime, method, json!({ "scheduleId": id_str }))?;
    Ok(("scheduledTasks", build_remote_scheduled_tasks(runtime)?))
}

fn handle_git_state(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let thread_uuid = parse_uuid_field(body, "threadID")?;
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;
    let cwd = thread_working_dir(runtime, &thread_id)?;

    let status = git_ops::status(&cwd).map_err(|e| RemoteError::failed(e.to_string()))?;
    if !status.is_repository {
        return Ok((
            "gitState",
            json!({
                "isRepository": false,
                " ahead": 0,
                "ahead": 0,
                "behind": 0,
                "changedFiles": 0,
                "hasRemote": false,
                "canCommit": false,
                "canPush": false,
                "canCreatePullRequest": false,
                "canPull": false,
                "changeRequestName": "Pull Request",
                "confirmsOnDefaultBranch": [],
                "isDefaultBranch": false,
            }),
        ));
    }

    let host = status
        .has_remote
        .then(|| git_ops::remote_host(&cwd, status.branch.as_deref()))
        .flatten();
    let change_request_name = match host.as_ref().map(|h| h.kind.change_request()) {
        Some(git_actions::host::Term::MergeRequest) => "Merge Request",
        _ => "Pull Request",
    };

    let open_pr = status
        .branch
        .as_deref()
        .filter(|_| status.has_remote && !status.is_default_branch)
        .and_then(|branch| git_ops::open_pull_request(branch, &cwd, false))
        .and_then(|v| serde_json::to_value(v).ok())
        .and_then(|pr| {
            Some(json!({
                "number": pr["number"].as_i64()?,
                "title": pr["title"].as_str().unwrap_or(""),
                "url": pr["url"].as_str().unwrap_or(""),
                "headBranch": status.branch,
                "baseBranch": status.default_branch.clone().unwrap_or_else(|| "main".into()),
                "state": "open",
                "isDraft": pr["isDraft"].as_bool().unwrap_or(false),
            }))
        });

    let has_changes = !status.files.is_empty();
    let on_branch = status.branch.is_some();
    let can_commit = has_changes && status.conflicted_paths.is_empty();
    let can_push = on_branch && status.has_remote && (status.ahead > 0 || !status.has_upstream());
    let can_pr = on_branch
        && status.has_remote
        && !status.is_default_branch
        && open_pr.is_none()
        && (status.ahead_of_default > 0 || has_changes);
    let can_pull = on_branch && status.has_upstream() && !has_changes;
    let confirms = if status.is_default_branch {
        vec!["commitPush", "push"]
    } else {
        vec![]
    };

    Ok((
        "gitState",
        json!({
            "isRepository": true,
            "branch": status.branch,
            "isDefaultBranch": status.is_default_branch,
            "upstream": status.upstream,
            "ahead": status.ahead,
            "behind": status.behind,
            "changedFiles": status.files.len(),
            "hasRemote": status.has_remote,
            "canCommit": can_commit,
            "canPush": can_push,
            "canCreatePullRequest": can_pr,
            "canPull": can_pull,
            "pullRequest": open_pr,
            "changeRequestName": change_request_name,
            "confirmsOnDefaultBranch": confirms,
        }),
    ))
}

fn handle_git_action(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let thread_uuid = parse_uuid_field(body, "threadID")?;
    let thread_id = resolve_thread_id(runtime, thread_uuid)?;
    let action = body["action"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;
    let message = body["message"].as_str().map(str::to_owned);
    let feature_branch = body["featureBranch"].as_bool().unwrap_or(false);
    let cwd = thread_working_dir(runtime, &thread_id)?;

    if action == "pull" {
        let res = git_ops::pull(&cwd).map_err(|e| RemoteError::failed(e.to_string()))?;
        let title = match res {
            git_actions::PullResult::Pulled => "Pulled latest changes",
            git_actions::PullResult::UpToDate => "Already up to date",
        };
        return Ok(("gitAction", json!({ "title": title })));
    }

    let stacked: StackedAction = serde_json::from_value(json!(action))
        .map_err(|_| RemoteError::bad_request())?;
    let req = ActionRequest {
        action: Some(stacked),
        commit_message: message,
        file_paths: None,
        feature_branch,
    };
    let outcome =
        git_actions::run(&req, &cwd, &|_| {}).map_err(|e| RemoteError::failed(e.to_string()))?;
    let outcome_val =
        serde_json::to_value(&outcome).map_err(|e| RemoteError::failed(e.to_string()))?;
    let title = outcome_val["summary"]
        .as_str()
        .or_else(|| outcome_val["title"].as_str())
        .unwrap_or("Completed Git action");
    let url = outcome_val["pullRequestUrl"]
        .as_str()
        .or_else(|| outcome_val["url"].as_str());
    Ok((
        "gitAction",
        json!({
            "title": title,
            "detail": outcome_val["detail"].as_str(),
            "url": url,
        }),
    ))
}

fn wait_github_operation(
    runtime: &CoincideMacOSRuntime,
    thread_id: &str,
    expected_root: Option<&str>,
    initial: Value,
) -> Result<Value, RemoteError> {
    if initial["ready"] == true {
        return Ok(initial["result"].clone());
    }
    let op_id = initial["operationId"]
        .as_str()
        .ok_or_else(|| RemoteError::failed("GitHub operation ID missing."))?
        .to_owned();
    let root = expected_root
        .or_else(|| initial["expectedRoot"].as_str())
        .ok_or_else(|| RemoteError::failed("GitHub expectedRoot missing."))?
        .to_owned();

    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let poll = engine_call(
            runtime,
            "github.result",
            json!({
                "threadId": thread_id,
                "expectedRoot": root,
                "operationId": op_id,
            }),
        )?;
        if poll["ready"] == true {
            return Ok(poll["result"].clone());
        }
        if Instant::now() >= deadline {
            return Err(RemoteError::failed("GitHub request timed out."));
        }
        std::thread::sleep(Duration::from_millis(40));
    }
}

fn ensure_project_helper_thread(
    runtime: &CoincideMacOSRuntime,
    project_uuid: Uuid,
) -> Result<String, RemoteError> {
    let runs = runtime.adapter.workspace_runs()?;
    let ws = runtime.adapter.initial_workspace(true, &runs)?;
    let target = project_uuid.to_string().to_uppercase();
    if let Some(existing) = ws.threads.iter().find(|t| t.project_id == target) {
        return resolve_thread_id(
            runtime,
            Uuid::parse_str(&existing.id).map_err(|_| RemoteError::bad_request())?,
        );
    }
    let created = runtime.adapter.new_thread(Some(project_uuid), &runs, None, None, None)?;
    resolve_thread_id(
        runtime,
        Uuid::parse_str(&created).map_err(|_| RemoteError::bad_request())?,
    )
}

fn map_gh_pr(pr: &Value) -> Option<Value> {
    let number = pr["number"].as_i64()?;
    let state = match pr["state"].as_str().unwrap_or("OPEN") {
        "MERGED" | "merged" => "merged",
        "CLOSED" | "closed" => "closed",
        _ => "open",
    };
    let review = match pr["reviewDecision"].as_str() {
        Some("APPROVED") => Some("approved"),
        Some("CHANGES_REQUESTED") => Some("changesRequested"),
        Some("REVIEW_REQUIRED") => Some("reviewRequired"),
        _ => None,
    };
    let updated_ms = pr["updatedAt"]
        .as_str()
        .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
        .map(|dt| dt.timestamp_millis() as f64);
    Some(json!({
        "number": number,
        "title": pr["title"].as_str().unwrap_or(""),
        "url": pr["url"].as_str().unwrap_or(""),
        "author": pr["author"]["login"].as_str().or_else(|| pr["author"].as_str()),
        "headBranch": pr["headRefName"].as_str().unwrap_or(""),
        "baseBranch": pr["baseRefName"].as_str().unwrap_or(""),
        "state": state,
        "isDraft": pr["isDraft"].as_bool().unwrap_or(false),
        "review": review,
        "updatedAt": updated_ms,
    }))
}

fn handle_pull_requests(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let project_uuid = parse_uuid_field(body, "projectID")?;
    let filter = body["filter"].as_str().unwrap_or("open");
    let thread_id = ensure_project_helper_thread(runtime, project_uuid)?;
    let cwd = thread_working_dir(runtime, &thread_id)?;
    let canon_root = cwd
        .canonicalize()
        .unwrap_or(cwd)
        .to_string_lossy()
        .into_owned();

    let avail_init = engine_call(
        runtime,
        "github.pr.availability",
        json!({ "threadId": thread_id }),
    );
    let avail = match avail_init {
        Ok(init) => wait_github_operation(runtime, &thread_id, Some(&canon_root), init)?,
        Err(err) => {
            return Ok((
                "pullRequests",
                json!({ "items": [], "unavailable": err.message }),
            ));
        }
    };

    if avail["state"] != "ready" {
        let msg = avail["message"]
            .as_str()
            .unwrap_or("GitHub pull requests are unavailable for this project.");
        return Ok((
            "pullRequests",
            json!({ "items": [], "unavailable": msg }),
        ));
    }

    let repo = avail["repository"]
        .as_str()
        .ok_or_else(|| RemoteError::failed("Repository name missing."))?;
    let involvement = match filter {
        "mine" => "authored",
        "reviewRequested" => "reviewRequested",
        _ => "all",
    };
    let list_init = engine_call(
        runtime,
        "github.pr.list",
        json!({
            "threadId": thread_id,
            "expectedRoot": canon_root,
            "repository": repo,
            "state": "open",
            "limit": 50,
            "involvement": involvement,
        }),
    )?;
    let listed = wait_github_operation(runtime, &thread_id, Some(&canon_root), list_init)?;
    let items: Vec<Value> = listed["pullRequests"]
        .as_array()
        .or_else(|| listed["items"].as_array())
        .into_iter()
        .flatten()
        .filter_map(map_gh_pr)
        .collect();
    Ok(("pullRequests", json!({ "items": items })))
}

fn handle_pull_request(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let project_uuid = parse_uuid_field(body, "projectID")?;
    let number = body["number"].as_i64().ok_or_else(RemoteError::bad_request)?;
    let thread_id = ensure_project_helper_thread(runtime, project_uuid)?;
    let cwd = thread_working_dir(runtime, &thread_id)?;
    let canon_root = cwd
        .canonicalize()
        .unwrap_or(cwd)
        .to_string_lossy()
        .into_owned();

    let avail_init = engine_call(
        runtime,
        "github.pr.availability",
        json!({ "threadId": thread_id }),
    )?;
    let avail = wait_github_operation(runtime, &thread_id, Some(&canon_root), avail_init)?;
    let repo = avail["repository"]
        .as_str()
        .ok_or_else(|| RemoteError::failed("GitHub pull requests are unavailable."))?;

    let read_init = engine_call(
        runtime,
        "github.pr.read",
        json!({
            "threadId": thread_id,
            "expectedRoot": canon_root,
            "repository": repo,
            "number": number,
        }),
    )?;
    let detail_raw = wait_github_operation(runtime, &thread_id, Some(&canon_root), read_init)?;
    let pr_raw = detail_raw.get("pullRequest").unwrap_or(&detail_raw);
    let summary = map_gh_pr(pr_raw)
        .ok_or_else(|| RemoteError::new(ErrorCode::NotFound, "Pull request not found."))?;
    let mergeability = match pr_raw["mergeable"].as_str() {
        Some("MERGEABLE") => "mergeable",
        Some("CONFLICTING") => "conflicting",
        _ => "unknown",
    };

    Ok((
        "pullRequest",
        json!({
            "pullRequest": summary,
            "body": pr_raw["body"].as_str().unwrap_or(""),
            "checks": [],
            "mergeability": mergeability,
            "additions": pr_raw["additions"].as_i64(),
            "deletions": pr_raw["deletions"].as_i64(),
            "changedFiles": pr_raw["changedFiles"].as_i64(),
            "reviews": [],
            "canMerge": mergeability == "mergeable",
            "mergeMethods": ["squash", "merge", "rebase"],
        }),
    ))
}

fn handle_pull_request_action(
    runtime: &CoincideMacOSRuntime,
    body: &Value,
) -> Result<(&'static str, Value), RemoteError> {
    let project_uuid = parse_uuid_field(body, "projectID")?;
    let number = body["number"].as_i64().ok_or_else(RemoteError::bad_request)?;
    let action = body["action"]
        .as_str()
        .ok_or_else(RemoteError::bad_request)?;

    if action == "checkOut" {
        let (_, detail) = handle_pull_request(
            runtime,
            &json!({ "projectID": project_uuid, "number": number }),
        )?;
        let head = detail["pullRequest"]["headBranch"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| RemoteError::failed("Pull request head branch is unavailable."))?;
        let new_tid = runtime
            .adapter
            .new_thread(Some(project_uuid), &runtime.adapter.workspace_runs()?, None, None, None)?;
        let resolved = resolve_thread_id(
            runtime,
            Uuid::parse_str(&new_tid).map_err(|_| RemoteError::bad_request())?,
        )?;
        let op = engine_call(
            runtime,
            "git.worktrees.useNew",
            json!({ "threadId": resolved, "baseBranch": head }),
        )?;
        if let Some(op_id) = op["operationId"].as_str() {
            let _ = wait_git_operation(runtime, &resolved, op_id);
        }
        return Ok(("thread", protocol::value_body(new_tid)));
    }

    handle_pull_request(
        runtime,
        &json!({ "projectID": project_uuid, "number": number }),
    )
}
