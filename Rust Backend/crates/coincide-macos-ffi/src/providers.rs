//! Provider configuration, Keychain API-key accounts, isolated login accounts,
//! ACP registry integration, and model catalog + preference actions.
use crate::{
    CoincideMacOSRuntime,
    discovery::{
        antigravity_companion_present, candidate_executables, discover_antigravity_binaries,
        provider_id_str,
    },
};
use anyhow::{Context, Result, bail, ensure};
use coincide_core::{
    acp_registry,
    api::Engine,
    composer_selection,
    provider_catalog,
    provider_configuration::{
        self, NativeAccountAuthentication, NativeKeyAccount, NativeLoginAccount,
        NativeProviderAccount, SetupAction,
    },
    provider_preferences,
};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

fn str_param<'a>(params: &'a Value, keys: &[&str]) -> Option<&'a str> {
    keys.iter()
        .find_map(|key| params.get(*key).and_then(Value::as_str))
}

fn req_str<'a>(params: &'a Value, keys: &[&str], label: &str) -> Result<&'a str> {
    str_param(params, keys)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .with_context(|| format!("Missing required parameter '{label}'"))
}

fn key_account_json(account: &NativeKeyAccount) -> Value {
    json!({
        "id": account.id,
        "provider": account.provider,
        "name": account.name,
        "revision": account.revision,
        "envName": account.key_variable,
        "keyVariable": account.key_variable,
        "hasKey": account.has_key,
    })
}

fn login_account_json(
    account: &NativeLoginAccount,
    provider: &str,
    executable: Option<&Path>,
) -> Value {
    let env_var = match provider {
        "codex" => Some("CODEX_HOME"),
        "claude" => Some("CLAUDE_CONFIG_DIR"),
        "grok" => Some("GROK_HOME"),
        "opencode" => Some("XDG_DATA_HOME"),
        _ => None,
    };
    let cli = executable
        .map(|p| format!("'{}'", p.display().to_string().replace('\'', "'\"'\"'")))
        .unwrap_or_else(|| match provider {
            "cursor" => "cursor-agent".into(),
            _ => provider.into(),
        });
    let login_subcmd = match provider {
        "claude" | "opencode" => "auth login",
        _ => "login",
    };
    let login_command = env_var.map(|var| {
        let home_escaped = account.home.display().to_string().replace('\'', "'\"'\"'");
        format!("{var}='{home_escaped}' {cli} {login_subcmd}")
    });
    json!({
        "id": account.id,
        "provider": provider,
        "name": account.name,
        "revision": account.revision,
        "home": account.home,
        "envVar": env_var,
        "loginCommand": login_command,
    })
}

fn provider_account_json(account: &NativeProviderAccount) -> Value {
    let auth = match account.authentication {
        NativeAccountAuthentication::Login => "login",
        NativeAccountAuthentication::ApiKey => "apiKey",
    };
    json!({
        "id": account.id,
        "provider": account.provider,
        "name": account.name,
        "revision": account.revision,
        "authentication": auth,
        "keyVariable": account.key_variable,
        "hasKey": account.has_key,
        "hasAdminKey": account.has_admin_key,
    })
}

pub fn list_all_providers(runtime: &CoincideMacOSRuntime) -> Result<Value> {
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    let settings = engine
        .store
        .document("settings.json")?
        .unwrap_or_else(|| json!({}));

    let mut entries: Vec<(String, String, bool)> = provider_catalog::PROVIDERS
        .iter()
        .map(|d| (provider_id_str(d.id).to_owned(), d.display_name.to_owned(), false))
        .collect();

    for acp in engine.native_acp_agents().unwrap_or_default() {
        if let (Some(id), Some(name)) = (acp["provider"].as_str(), acp["displayName"].as_str()) {
            entries.push((id.to_owned(), name.to_owned(), true));
        }
    }

    let mut out = Vec::with_capacity(entries.len());
    for (id, display_name, is_acp) in entries {
        let enabled = provider_preferences::enabled(&settings, &id).unwrap_or(true);
        let config = engine.native_provider_configuration(&id)?;
        let candidates = candidate_executables(&id, &runtime.data_dir);
        let configured_exec = config.executable.clone();
        let approved_exec = if config.approved {
            config.executable.clone()
        } else {
            None
        };
        let effective_exec = approved_exec
            .clone()
            .or_else(|| configured_exec.clone())
            .or_else(|| candidates.first().cloned());
        let approved_companion = if id == "antigravity" {
            approved_exec
                .as_deref()
                .and_then(antigravity_companion_present)
        } else {
            None
        };

        let key_choices: Vec<Value> = provider_configuration::native_account_key_choices(&id)
            .map(|choices| {
                choices
                    .iter()
                    .map(|(env_name, label)| json!({"envName": env_name, "label": label}))
                    .collect()
            })
            .unwrap_or_default();

        let key_accounts: Vec<Value> = engine
            .native_key_accounts(&id)
            .unwrap_or_default()
            .iter()
            .map(key_account_json)
            .collect();

        let login_accounts: Vec<Value> = engine
            .native_login_accounts(&id)
            .unwrap_or_default()
            .iter()
            .map(|acc| login_account_json(acc, &id, effective_exec.as_deref()))
            .collect();

        let provider_accounts: Vec<Value> = engine
            .native_provider_accounts(&id)
            .unwrap_or_default()
            .iter()
            .map(provider_account_json)
            .collect();

        let setup_cmds: Vec<Value> =
            provider_configuration::setup_commands(&id, effective_exec.as_deref())
                .into_iter()
                .map(|cmd| {
                    let kind = match cmd.action {
                        SetupAction::Install => "install",
                        SetupAction::SignIn => "signIn",
                    };
                    json!({
                        "action": kind,
                        "label": cmd.label,
                        "command": cmd.display,
                    })
                })
                .collect();

        let antigravity_status = if id == "antigravity" {
            let resp = engine.dispatch_desktop(json!({
                "method": "providers.antigravity.status",
                "params": {},
            }));
            resp.get("result").cloned().unwrap_or(Value::Null)
        } else {
            Value::Null
        };

        out.push(json!({
            "id": id,
            "displayName": display_name,
            "isAcp": is_acp,
            "enabled": enabled,
            "approved": config.approved,
            "imported": config.imported,
            "baseline": config.baseline,
            "configuredExecutable": configured_exec,
            "approvedExecutable": approved_exec,
            "effectiveExecutable": effective_exec,
            "approvedCompanion": approved_companion,
            "candidateExecutables": candidates,
            "environment": config.environment,
            "keyChoices": key_choices,
            "keyAccounts": key_accounts,
            "loginAccounts": login_accounts,
            "accounts": provider_accounts,
            "setupCommands": setup_cmds,
            "signInSupported": provider_configuration::native_sign_in_supported(&id),
            "antigravityStatus": antigravity_status,
        }));
    }

    Ok(json!({ "providers": out }))
}

pub fn save_provider_config(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let provider = req_str(params, &["provider", "id"], "provider")?;
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;

    let current = engine.native_provider_configuration(provider)?;
    let executable_specified = params.get("executable").is_some();
    let executable_path: Option<PathBuf> = if executable_specified {
        params["executable"]
            .as_str()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(PathBuf::from)
    } else {
        current.executable.clone()
    };

    let environment: BTreeMap<String, String> = match params.get("environment") {
        None | Some(Value::Null) => current.environment.clone(),
        Some(Value::Object(map)) => {
            let mut env = BTreeMap::new();
            for (k, v) in map {
                let k = k.trim();
                if k.is_empty() {
                    continue;
                }
                let val = match v {
                    Value::String(s) => s.clone(),
                    Value::Null => continue,
                    other => other.to_string(),
                };
                env.insert(k.to_owned(), val);
            }
            env
        }
        Some(_) => bail!("environment must be an object mapping variable names to strings"),
    };

    let has_config_change = executable_specified || params.get("environment").is_some();
    let snapshot = if has_config_change {
        let prepared = engine.prepare_native_provider_configuration(
            provider,
            &current.baseline,
            executable_path.as_deref(),
            environment,
        )?;
        engine.apply_native_provider_configuration(prepared)?
    } else {
        current
    };

    if let Some(enabled) = params.get("enabled").and_then(Value::as_bool) {
        update_provider_enabled(&mut engine, provider, enabled)?;
    }

    let settings = engine
        .store
        .document("settings.json")?
        .unwrap_or_else(|| json!({}));
    let enabled = provider_preferences::enabled(&settings, provider).unwrap_or(true);

    Ok(json!({
        "provider": provider,
        "enabled": enabled,
        "approved": snapshot.approved,
        "baseline": snapshot.baseline,
        "configuredExecutable": snapshot.executable,
        "environment": snapshot.environment,
    }))
}

pub fn update_provider_enabled(engine: &mut Engine, provider: &str, enabled: bool) -> Result<()> {
    let mut settings = engine
        .store
        .document("settings.json")?
        .unwrap_or_else(|| json!({}));
    ensure!(settings.is_object(), "Saved settings.json is malformed");
    match settings.get_mut("providers") {
        None | Some(Value::Null) => {
            settings["providers"] = json!({ provider: { "isEnabled": enabled } });
        }
        Some(Value::Object(map)) => {
            let entry = map.entry(provider.to_owned()).or_insert_with(|| json!({}));
            ensure!(entry.is_object(), "Saved provider entry is malformed");
            entry["isEnabled"] = json!(enabled);
        }
        Some(Value::Array(arr)) => {
            let mut found = false;
            for pair in arr.chunks_exact_mut(2) {
                if pair[0].as_str() == Some(provider) {
                    ensure!(pair[1].is_object(), "Saved provider entry is malformed");
                    pair[1]["isEnabled"] = json!(enabled);
                    found = true;
                    break;
                }
            }
            if !found {
                arr.push(json!(provider));
                arr.push(json!({ "isEnabled": enabled }));
            }
        }
        Some(_) => bail!("Saved provider preferences are malformed"),
    }
    engine.store.save_document("settings.json", &settings)?;
    engine.revision += 1;
    Ok(())
}

pub fn check_provider(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let provider = req_str(params, &["provider", "id"], "provider")?.to_owned();
    let account_id = str_param(params, &["accountId", "accountID"])
        .map(str::trim)
        .filter(|s| !s.is_empty() && *s != "default")
        .map(str::to_owned);

    if provider == "antigravity" {
        if params.get("probe").and_then(Value::as_bool) == Some(true) {
            return probe_antigravity(runtime, params);
        }
        let mut engine = runtime
            .engine
            .lock()
            .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
        let snap = engine.native_provider_configuration("antigravity")?;
        let candidates = discover_antigravity_binaries(&runtime.data_dir);
        let exec = snap
            .executable
            .clone()
            .or_else(|| candidates.first().cloned());
        let companion = exec.as_deref().and_then(antigravity_companion_present);
        let key_accounts = engine.native_key_accounts("antigravity")?;
        let has_key = key_accounts.iter().any(|a| a.has_key);
        let note = match (&exec, &companion, snap.approved, has_key) {
            (None, _, _, _) => "Antigravity runtime binary (agy_acp_server.par) was not found.",
            (Some(_), None, _, _) => "Antigravity helper (localharness_external) is missing.",
            (Some(_), Some(_), false, _) => {
                "Antigravity binary found; save configuration or add a Gemini API key account to approve it."
            }
            (Some(_), Some(_), true, false) => {
                "Antigravity runtime is approved. Add a Gemini API key account to start chatting."
            }
            (Some(_), Some(_), true, true) => {
                "Antigravity runtime and Gemini API key account are configured."
            }
        };
        let status = engine.dispatch_desktop(json!({
            "method": "providers.antigravity.status",
            "params": {},
        }))["result"]
            .clone();
        return Ok(json!({
            "provider": "antigravity",
            "executable": exec,
            "companion": companion,
            "approved": snap.approved,
            "authenticated": (snap.approved && companion.is_some() && has_key).then_some(true),
            "statusNote": note,
            "antigravityStatus": status,
        }));
    }

    // Prepare probe under brief Engine lock, then run subprocess probe completely off-lock.
    let probe = {
        let engine = runtime
            .engine
            .lock()
            .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
        if let Some(acc_id) = &account_id {
            let acc = engine
                .native_login_accounts(&provider)?
                .into_iter()
                .find(|a| a.id == *acc_id)
                .context("Login account not found")?;
            engine.prepare_native_login_account_check(&provider, acc_id, &acc.revision)?
        } else {
            engine.prepare_native_provider_check(&provider)?
        }
    };

    let deadline = Instant::now() + Duration::from_secs(30);
    let report = probe.run(&|| Instant::now() < deadline)?;
    Ok(json!({
        "provider": provider,
        "accountId": account_id,
        "executable": report.executable,
        "version": report.version,
        "authenticated": report.authenticated,
        "account": report.account,
        "integrations": report.integrations,
        "models": report.models,
        "statusNote": report.status_note,
    }))
}

fn probe_antigravity(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let account_id = str_param(params, &["accountId", "accountID"])
        .map(str::trim)
        .filter(|s| !s.is_empty() && *s != "default")
        .map(str::to_owned);
    let invalid_key = params.get("probeKey").and_then(Value::as_str) == Some("invalid");
    let probe = {
        let engine = runtime
            .engine
            .lock()
            .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
        let snap = engine.native_provider_configuration("antigravity")?;
        let candidates = discover_antigravity_binaries(&runtime.data_dir);
        let executable = if snap.approved {
            snap.executable.clone()
        } else {
            None
        };
        let unapproved_candidate = snap.executable.is_some() || !candidates.is_empty();
        let account = if invalid_key {
            None
        } else {
            account_id.as_deref()
        };
        engine.prepare_antigravity_probe(executable, unapproved_candidate, account, invalid_key)?
    };
    let report = probe.run().to_json();
    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    let status = engine.record_antigravity_probe(&report)?;
    Ok(json!({
        "provider": "antigravity",
        "probe": report,
        "antigravityStatus": status,
    }))
}

pub fn create_key_account(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let provider = req_str(params, &["provider"], "provider")?;
    let name = req_str(params, &["name"], "name")?;
    let api_key = req_str(params, &["apiKey", "key"], "apiKey")?;

    let choices = provider_configuration::native_account_key_choices(provider)?;
    let default_env = if provider == "antigravity" {
        "GEMINI_API_KEY"
    } else {
        choices
            .first()
            .map(|(env, _)| *env)
            .context("Provider does not support API key accounts")?
    };
    let env_name = str_param(params, &["envName", "keyVariable"])
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(default_env);

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;

    // If Antigravity has no approved executable yet, auto-discover `agy_acp_server.par`
    // and approve it immediately so Antigravity works out of the box!
    let mut auto_approved_executable: Option<PathBuf> = None;
    if provider == "antigravity" {
        let current = engine.native_provider_configuration("antigravity")?;
        if !current.approved || current.executable.is_none() {
            if let Some(candidate) = discover_antigravity_binaries(&runtime.data_dir)
                .into_iter()
                .next()
            {
                if let Ok(plan) = engine.prepare_native_provider_configuration(
                    "antigravity",
                    &current.baseline,
                    Some(&candidate),
                    current.environment,
                ) && engine.apply_native_provider_configuration(plan).is_ok()
                {
                    auto_approved_executable = Some(candidate);
                }
            }
        }
    }

    let created = engine.create_native_key_account(provider, name, env_name)?;
    let saved =
        engine.save_native_account_key(provider, &created.id, &created.revision, api_key)?;
    if saved.cleanup_pending {
        let _ = engine.retry_native_account_secret_cleanup(provider);
    }

    Ok(json!({
        "account": key_account_json(&saved.account),
        "cleanupPending": saved.cleanup_pending,
        "autoApprovedExecutable": auto_approved_executable,
    }))
}

pub fn update_account_key(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let provider = req_str(params, &["provider"], "provider")?;
    let account_id = req_str(params, &["accountId", "accountID", "id"], "accountId")?;
    let api_key = req_str(params, &["apiKey", "key"], "apiKey")?;

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    let current = engine
        .native_key_accounts(provider)?
        .into_iter()
        .find(|a| a.id == account_id)
        .context("API key account not found")?;
    let saved =
        engine.save_native_account_key(provider, account_id, &current.revision, api_key)?;
    if saved.cleanup_pending {
        let _ = engine.retry_native_account_secret_cleanup(provider);
    }
    Ok(json!({
        "account": key_account_json(&saved.account),
        "cleanupPending": saved.cleanup_pending,
    }))
}

pub fn rename_key_account(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let provider = req_str(params, &["provider"], "provider")?;
    let account_id = req_str(params, &["accountId", "accountID", "id"], "accountId")?;
    let name = req_str(params, &["name"], "name")?;

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    let existing = engine
        .native_provider_accounts(provider)?
        .into_iter()
        .find(|a| a.id == account_id)
        .context("Account not found")?;

    match existing.authentication {
        NativeAccountAuthentication::ApiKey => {
            let updated =
                engine.rename_native_key_account(provider, account_id, &existing.revision, name)?;
            Ok(json!({ "account": key_account_json(&updated) }))
        }
        NativeAccountAuthentication::Login => {
            let updated = engine.rename_native_login_account(
                provider,
                account_id,
                &existing.revision,
                name,
            )?;
            let candidates = candidate_executables(provider, &runtime.data_dir);
            Ok(json!({
                "account": login_account_json(&updated, provider, candidates.first().map(PathBuf::as_path))
            }))
        }
    }
}

pub fn delete_account(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let provider = req_str(params, &["provider"], "provider")?;
    let account_id = req_str(params, &["accountId", "accountID", "id"], "accountId")?;

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    let existing = engine
        .native_provider_accounts(provider)?
        .into_iter()
        .find(|a| a.id == account_id)
        .context("Account not found")?;

    let mut revision = existing.revision;
    if existing.authentication == NativeAccountAuthentication::ApiKey && existing.has_key {
        let key_removed = engine.remove_native_account_key(provider, account_id, &revision)?;
        revision = key_removed.account.revision;
        let _ = engine.retry_native_account_secret_cleanup(provider);
    }

    let plan = engine.prepare_native_provider_account_removal(provider, account_id, &revision)?;
    let outcome = engine.apply_native_provider_account_removal(plan)?;
    let _ = engine.retry_native_removed_account_cleanup(provider);
    let _ = engine.retry_native_account_secret_cleanup(provider);
    let cleanup_remaining = engine
        .native_provider_account_cleanup_pending(provider)
        .unwrap_or(0);

    Ok(json!({
        "deleted": true,
        "provider": provider,
        "accountId": account_id,
        "conversationsUpdated": outcome.conversations,
        "cleanupPending": cleanup_remaining > 0,
    }))
}

pub fn create_login_account(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let provider = req_str(params, &["provider"], "provider")?;
    let name = req_str(params, &["name"], "name")?;

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    let created = engine.create_native_login_account(provider, name)?;
    let config = engine.native_provider_configuration(provider)?;
    let candidates = candidate_executables(provider, &runtime.data_dir);
    let exec = config
        .executable
        .as_deref()
        .or_else(|| candidates.first().map(PathBuf::as_path));

    let setup_cmds: Vec<Value> = provider_configuration::setup_commands(provider, exec)
        .into_iter()
        .map(|cmd| {
            let kind = match cmd.action {
                SetupAction::Install => "install",
                SetupAction::SignIn => "signIn",
            };
            json!({
                "action": kind,
                "label": cmd.label,
                "command": cmd.display,
            })
        })
        .collect();

    Ok(json!({
        "account": login_account_json(&created, provider, exec),
        "setupCommands": setup_cmds,
    }))
}

pub fn select_thread_account(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let thread_id = req_str(params, &["threadId", "threadID"], "threadId")?;
    let account_id = str_param(params, &["accountId", "accountID"])
        .map(str::trim)
        .filter(|s| !s.is_empty() && *s != "default");

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    let open = engine.dispatch_desktop(json!({
        "method": "threads.open",
        "params": { "threadId": thread_id },
    }));
    if let Some(err) = open.get("error") {
        bail!(
            "{}",
            err["message"]
                .as_str()
                .unwrap_or("Unable to activate thread")
        );
    }
    let current = engine.store.thread(thread_id)?;
    let updated = engine.select_native_provider_account(&current, account_id)?;
    Ok(json!({ "thread": updated }))
}

pub fn acp_registry_view(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let refresh = params
        .get("refresh")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    if refresh {
        {
            let mut engine = runtime
                .engine
                .lock()
                .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
            engine.refresh_native_acp_registry()?;
        }
        // Poll briefly off-lock if a refresh was explicitly requested so local/live results settle.
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            let still_loading = {
                let mut engine = runtime
                    .engine
                    .lock()
                    .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
                let view = engine.native_acp_registry_view();
                if view["loading"] != true {
                    return Ok(view);
                }
                true
            };
            if !still_loading {
                break;
            }
            std::thread::sleep(Duration::from_millis(30));
        }
    }

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    Ok(engine.native_acp_registry_view())
}

pub fn register_acp_agent(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let raw_id = req_str(params, &["agentId", "agentID", "id"], "agentId")?;
    let agent_id = acp_registry::registry_id(raw_id).unwrap_or(raw_id);

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;

    // Try registering directly from the engine's registry view first; if not loaded yet,
    // check `acp_registry::local_agents()`.
    let provider = match engine.add_native_registry_agent(agent_id) {
        Ok(provider) => provider,
        Err(_) => {
            let local = acp_registry::local_agents()
                .into_iter()
                .find(|a| a.id == agent_id)
                .context("ACP agent not found in registry or local discovery")?;
            let provider =
                acp_registry::provider_id(&local.id).context("Invalid ACP agent identifier")?;
            engine.register_native_acp_agent(&local)?;
            provider
        }
    };

    Ok(json!({
        "registered": true,
        "agentId": agent_id,
        "provider": provider,
        "acpAgents": engine.native_acp_agents()?,
    }))
}

pub fn models_catalog(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let provider = req_str(params, &["provider"], "provider")?.to_owned();
    let refresh = params
        .get("refresh")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let thread_id = str_param(params, &["threadId", "threadID"])
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned);
    let account_id = str_param(params, &["accountId", "accountID"])
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned);

    let mut refresh_op: Option<String> = None;
    let mut refresh_error: Option<String> = None;

    if refresh {
        let mut req_params = json!({ "provider": provider });
        if let Some(tid) = &thread_id {
            req_params["threadId"] = json!(tid);
        }
        if let Some(aid) = &account_id {
            req_params["accountId"] = json!(aid);
        }
        let resp = {
            let mut engine = runtime
                .engine
                .lock()
                .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
            engine.dispatch_desktop(json!({
                "method": "agent.models.refresh",
                "params": req_params,
            }))
        };
        if let Some(err) = resp.get("error") {
            refresh_error = err["message"].as_str().map(str::to_owned);
        } else if let Some(op_id) = resp["result"]["operationId"].as_str() {
            refresh_op = Some(op_id.to_owned());
        }
    }

    // If a refresh started, wait boundedly off-lock for completion so callers receive fresh models.
    let mut live_status = Value::Null;
    if let Some(op_id) = &refresh_op {
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            let status_resp = {
                let mut engine = runtime
                    .engine
                    .lock()
                    .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
                engine.dispatch_desktop(json!({
                    "method": "agent.models.status",
                    "params": { "operationId": op_id },
                }))
            };
            live_status = status_resp["result"].clone();
            let state = live_status["state"].as_str().unwrap_or("");
            if matches!(state, "ready" | "failed" | "unsupported") || Instant::now() >= deadline {
                break;
            }
            std::thread::sleep(Duration::from_millis(35));
        }
    }

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    let settings = engine
        .store
        .document("settings.json")?
        .unwrap_or_else(|| json!({}));
    let saved_catalog = engine
        .store
        .document("model-catalog.json")?
        .unwrap_or_else(|| json!({}));

    let mut capability_params = json!({});
    if let Some(tid) = &thread_id {
        capability_params["threadId"] = json!(tid);
    }
    let capabilities = engine.dispatch_desktop(json!({
        "method": "agent.selection.capabilities",
        "params": capability_params,
    }))["result"]
        .clone();

    let favorites: Vec<String> = settings["favoriteModels"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|r| r["provider"].as_str() == Some(provider.as_str()))
        .filter_map(|r| r["modelID"].as_str().map(str::to_owned))
        .collect();
    let hidden: Vec<String> = settings["hiddenModels"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|r| r["provider"].as_str() == Some(provider.as_str()))
        .filter_map(|r| r["modelID"].as_str().map(str::to_owned))
        .collect();
    let custom_models: Vec<String> = provider_settings_entry(&settings, &provider)["customModels"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|v| v.as_str().map(str::to_owned))
        .collect();
    let default_selection = settings.get("defaultSelection").cloned().unwrap_or(Value::Null);
    let default_model_id = if default_selection["provider"].as_str() == Some(provider.as_str()) {
        default_selection["modelID"].as_str().map(str::to_owned)
    } else {
        None
    };

    let discovered = if live_status["models"].is_array() {
        live_status["models"].as_array().cloned().unwrap_or_default()
    } else {
        saved_catalog["providers"][&provider]["models"]
            .as_array()
            .cloned()
            .unwrap_or_default()
    };

    let mut seen = std::collections::HashSet::new();
    let mut models = Vec::new();
    for mut m in discovered {
        if let Some(id) = m["id"].as_str().map(str::to_owned)
            && seen.insert(id.clone())
        {
            if let Some(obj) = m.as_object_mut() {
                obj.insert("favorite".into(), json!(favorites.contains(&id)));
                obj.insert("hidden".into(), json!(hidden.contains(&id)));
                obj.insert(
                    "isDefault".into(),
                    json!(default_model_id.as_deref() == Some(id.as_str())),
                );
                obj.insert("custom".into(), json!(false));
            }
            models.push(m);
        }
    }
    for custom in &custom_models {
        if seen.insert(custom.clone()) {
            models.push(json!({
                "id": custom,
                "displayName": custom,
                "favorite": favorites.contains(custom),
                "hidden": hidden.contains(custom),
                "isDefault": default_model_id.as_deref() == Some(custom.as_str()),
                "custom": true,
            }));
        }
    }

    Ok(json!({
        "provider": provider,
        "enabled": provider_preferences::enabled(&settings, &provider).unwrap_or(true),
        "models": models,
        "favoriteModels": favorites,
        "hiddenModels": hidden,
        "customModels": custom_models,
        "defaultModelId": default_model_id,
        "capabilities": capabilities,
        "liveStatus": live_status,
        "refreshError": refresh_error,
    }))
}

pub fn set_model_preference(runtime: &CoincideMacOSRuntime, params: &Value) -> Result<Value> {
    let provider = req_str(params, &["provider"], "provider")?;
    let model_id = req_str(params, &["modelId", "modelID"], "modelId")?;
    composer_selection::validate_model(model_id)?;

    let mut engine = runtime
        .engine
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    ensure!(!engine.admissions_frozen(), "Application is closing");

    let mut settings = engine
        .store
        .document("settings.json")?
        .unwrap_or_else(|| json!({}));
    ensure!(settings.is_object(), "Saved settings.json is malformed");
    // Validate provider identity via provider_preferences::enabled
    let _ = provider_preferences::enabled(&settings, provider)?;

    let matches_ref = |row: &Value| {
        row["provider"].as_str() == Some(provider) && row["modelID"].as_str() == Some(model_id)
    };

    if let Some(fav) = params.get("favorite").and_then(Value::as_bool) {
        let mut favs = settings["favoriteModels"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        favs.retain(|r| !matches_ref(r));
        if fav {
            favs.push(json!({ "provider": provider, "modelID": model_id }));
            let mut hid = settings["hiddenModels"]
                .as_array()
                .cloned()
                .unwrap_or_default();
            hid.retain(|r| !matches_ref(r));
            settings["hiddenModels"] = json!(hid);
        }
        settings["favoriteModels"] = json!(favs);
    }

    if let Some(hide) = params.get("hidden").and_then(Value::as_bool) {
        let mut hid = settings["hiddenModels"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        hid.retain(|r| !matches_ref(r));
        if hide {
            hid.push(json!({ "provider": provider, "modelID": model_id }));
            let mut favs = settings["favoriteModels"]
                .as_array()
                .cloned()
                .unwrap_or_default();
            favs.retain(|r| !matches_ref(r));
            settings["favoriteModels"] = json!(favs);
        }
        settings["hiddenModels"] = json!(hid);
    }

    if let Some(is_default) = params.get("isDefault").and_then(Value::as_bool) {
        if is_default {
            settings["defaultSelection"] = json!({
                "provider": provider,
                "modelID": model_id,
            });
        } else if settings["defaultSelection"]["provider"].as_str() == Some(provider)
            && settings["defaultSelection"]["modelID"].as_str() == Some(model_id)
        {
            settings["defaultSelection"] = Value::Null;
        }
    }

    if let Some(custom) = params.get("custom").and_then(Value::as_bool) {
        ensure!(model_id != "default", "Provider default is built in");
        set_custom_model(&mut settings, provider, model_id, custom)?;
    }

    engine.store.save_document("settings.json", &settings)?;
    engine.revision += 1;

    Ok(json!({
        "provider": provider,
        "modelId": model_id,
        "favoriteModels": settings["favoriteModels"],
        "hiddenModels": settings["hiddenModels"],
        "defaultSelection": settings["defaultSelection"],
    }))
}

fn provider_settings_entry<'a>(settings: &'a Value, provider: &str) -> &'a Value {
    if let Some(map) = settings["providers"].as_object() {
        return map.get(provider).unwrap_or(&Value::Null);
    }
    if let Some(arr) = settings["providers"].as_array() {
        for pair in arr.chunks_exact(2) {
            if pair[0].as_str() == Some(provider) {
                return &pair[1];
            }
        }
    }
    &Value::Null
}

fn set_custom_model(
    settings: &mut Value,
    provider: &str,
    model_id: &str,
    add: bool,
) -> Result<()> {
    let mut entry = provider_settings_entry(settings, provider).clone();
    if entry.is_null() {
        entry = json!({});
    }
    ensure!(entry.is_object(), "Saved provider entry is malformed");
    let mut rows = entry["customModels"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    rows.retain(|r| r.as_str() != Some(model_id));
    if add {
        ensure!(rows.len() < 1000, "Custom model limit reached");
        rows.push(json!(model_id));
    }
    entry["customModels"] = json!(rows);
    match settings.get_mut("providers") {
        None | Some(Value::Null) => {
            settings["providers"] = json!({ provider: entry });
        }
        Some(Value::Object(map)) => {
            map.insert(provider.to_owned(), entry);
        }
        Some(Value::Array(arr)) => {
            let mut found = false;
            for pair in arr.chunks_exact_mut(2) {
                if pair[0].as_str() == Some(provider) {
                    pair[1] = entry.clone();
                    found = true;
                    break;
                }
            }
            if !found {
                arr.push(json!(provider));
                arr.push(entry);
            }
        }
        Some(_) => bail!("Saved provider settings are malformed"),
    }
    Ok(())
}
