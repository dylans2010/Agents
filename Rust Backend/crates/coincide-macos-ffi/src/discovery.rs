//! macOS login-shell PATH adoption, executable discovery, managed Antigravity
//! binary detection, and non-destructive legacy Swift store import.
use anyhow::{Context, Result, ensure};
use coincide_core::{
    api::SharedEngine,
    provider_catalog::{self, ProviderId},
    store::Store,
};
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    fs,
    io::Read,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant},
};
use uuid::Uuid;

/// Safely queries the user's login shell `PATH` (bounded to 2.5s) and merges
/// standard macOS + user CLI directories before spawning background threads.
pub fn adopt_login_shell_path() {
    const START: &str = "__COINCIDE_PATH_START__";
    const END: &str = "__COINCIDE_PATH_END__";
    let shell = std::env::var("SHELL")
        .ok()
        .filter(|shell| Path::new(shell).is_file())
        .unwrap_or_else(|| "/bin/zsh".into());
    let current_path = std::env::var("PATH").unwrap_or_default();
    let needs_shell = !current_path
        .split(':')
        .any(|entry| entry == "/opt/homebrew/bin")
        && !current_path
            .split(':')
            .any(|entry| entry == "/usr/local/bin");
    let mut from_shell = None;
    if needs_shell
        && let Ok(mut child) = Command::new(&shell)
            .args([
                "-ilc",
                &format!("printf '%s%s%s' '{START}' \"$PATH\" '{END}'"),
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
    {
        let deadline = Instant::now() + Duration::from_millis(2500);
        loop {
            match child.try_wait() {
                Ok(Some(_)) => break,
                Ok(None) if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(25));
                }
                _ => {
                    let _ = child.kill();
                    let _ = child.wait();
                    break;
                }
            }
        }
        if let Some(output) = child.stdout.take() {
            let mut text = String::new();
            let _ = output.take(64 * 1024).read_to_string(&mut text);
            if let Some(start) = text.find(START)
                && let Some(end) = text[start..].find(END)
            {
                let path = &text[start + START.len()..start + end];
                if !path.is_empty() && path.len() <= 32 * 1024 {
                    from_shell = Some(path.to_owned());
                }
            }
        }
    }
    let home = home_dir().map(|p| p.display().to_string()).unwrap_or_default();
    let mut extras = vec![
        "/opt/homebrew/bin".to_owned(),
        "/opt/homebrew/sbin".to_owned(),
        "/usr/local/bin".to_owned(),
    ];
    if !home.is_empty() {
        extras.extend([
            format!("{home}/.local/bin"),
            format!("{home}/.bun/bin"),
            format!("{home}/.npm-global/bin"),
            format!("{home}/.cargo/bin"),
            format!("{home}/.grok/bin"),
            format!("{home}/.opencode/bin"),
            format!("{home}/.cursor/bin"),
        ]);
    }
    extras.extend([
        "/usr/bin".to_owned(),
        "/bin".to_owned(),
        "/usr/sbin".to_owned(),
        "/sbin".to_owned(),
    ]);
    let mut seen = HashSet::new();
    let mut parts = Vec::new();
    for entry in from_shell
        .iter()
        .flat_map(|path| path.split(':'))
        .chain(current_path.split(':'))
        .chain(extras.iter().map(String::as_str))
        .filter(|entry| !entry.is_empty())
    {
        if seen.insert(entry.to_owned()) {
            parts.push(entry.to_owned());
        }
    }
    let merged = parts.join(":");
    if merged != current_path {
        // SAFETY: Called by the host during early startup before spawning threads.
        unsafe { std::env::set_var("PATH", merged) };
    }
}

pub fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
}

pub fn is_executable_file(path: &Path) -> bool {
    fs::metadata(path)
        .is_ok_and(|meta| meta.is_file() && (meta.permissions().mode() & 0o111 != 0))
}

pub fn default_legacy_store_dir() -> Option<PathBuf> {
    Some(home_dir()?.join("Library/Application Support/Coincide"))
}

pub fn legacy_import_available(data_dir: &Path) -> bool {
    let Some(legacy) = default_legacy_store_dir() else {
        return false;
    };
    if legacy == data_dir {
        return false;
    }
    legacy.join("projects.json").is_file() || legacy.join("threads").is_dir()
}

pub fn antigravity_companion_present(binary: &Path) -> Option<PathBuf> {
    let canonical = binary.canonicalize().ok()?;
    let companion = canonical.with_file_name("localharness_external");
    is_executable_file(&companion).then_some(companion)
}

/// Discovers managed Antigravity binaries under Application Support and data_dir.
pub fn discover_antigravity_binaries(data_dir: &Path) -> Vec<PathBuf> {
    let arches = if cfg!(target_arch = "aarch64") {
        ["darwin-arm64", "darwin-x64"]
    } else {
        ["darwin-x64", "darwin-arm64"]
    };
    let mut roots = Vec::new();
    if let Some(home) = home_dir() {
        let app_support = home.join("Library/Application Support");
        roots.push(app_support.join("Coincide"));
        roots.push(app_support.join("Coincide Rust"));
    }
    if !roots.iter().any(|r| r == data_dir) {
        roots.push(data_dir.to_path_buf());
    }
    let mut seen = HashSet::new();
    let mut found = Vec::new();
    for root in roots {
        for arch in arches {
            let candidate = root
                .join("tools/antigravity-acp")
                .join(arch)
                .join("current/agy_acp_server.par");
            if is_executable_file(&candidate)
                && antigravity_companion_present(&candidate).is_some()
                && seen.insert(candidate.clone())
            {
                found.push(candidate);
            }
        }
    }
    found
}

pub fn primary_antigravity_binary(data_dir: &Path) -> Option<PathBuf> {
    discover_antigravity_binaries(data_dir).into_iter().next()
}

/// Discovers all candidate executables on PATH + standard directories + managed tools.
pub fn candidate_executables(provider: &str, data_dir: &Path) -> Vec<PathBuf> {
    let mut seen = HashSet::new();
    let mut results = Vec::new();
    let mut push = |path: PathBuf| {
        if is_executable_file(&path) && seen.insert(path.clone()) {
            results.push(path);
        }
    };

    let env_var = format!("COINCIDE_{}_EXECUTABLE", provider.to_ascii_uppercase());
    if let Some(val) = std::env::var_os(&env_var) {
        push(PathBuf::from(val));
    }

    if provider == "antigravity" {
        for managed in discover_antigravity_binaries(data_dir) {
            push(managed);
        }
    }

    let names: Vec<&str> = if let Some(descriptor) = provider_catalog::PROVIDERS.iter().find(|d| {
        provider_id_str(d.id) == provider
    }) {
        descriptor.executable_candidates.to_vec()
    } else if let Some(acp_id) = coincide_core::acp_registry::registry_id(provider) {
        if let Some(resolved) = coincide_core::acp_registry::resolve_executable(acp_id) {
            push(resolved);
        }
        Vec::new()
    } else {
        Vec::new()
    };

    if !names.is_empty() {
        let mut dirs = Vec::new();
        if let Some(path_os) = std::env::var_os("PATH") {
            for dir in std::env::split_paths(&path_os) {
                if dir.is_absolute() && !dirs.contains(&dir) {
                    dirs.push(dir);
                }
            }
        }
        if let Some(home) = home_dir() {
            for extra in [
                PathBuf::from("/opt/homebrew/bin"),
                PathBuf::from("/usr/local/bin"),
                home.join(".local/bin"),
                home.join(".bun/bin"),
                home.join(".npm-global/bin"),
                home.join(".cargo/bin"),
                home.join(".grok/bin"),
                home.join(".opencode/bin"),
                home.join(".cursor/bin"),
                PathBuf::from("/usr/bin"),
            ] {
                if !dirs.contains(&extra) {
                    dirs.push(extra);
                }
            }
        }
        for name in names {
            for dir in &dirs {
                let candidate = dir.join(name);
                if provider == "antigravity" && antigravity_companion_present(&candidate).is_none() {
                    continue;
                }
                push(candidate);
            }
        }
    }

    results
}

pub fn provider_id_str(id: ProviderId) -> &'static str {
    match id {
        ProviderId::Claude => "claude",
        ProviderId::Codex => "codex",
        ProviderId::Cursor => "cursor",
        ProviderId::Grok => "grok",
        ProviderId::Opencode => "opencode",
        ProviderId::Lithos => "lithos",
        ProviderId::Antigravity => "antigravity",
    }
}

/// Non-destructively imports projects, bots, and forked conversations from a legacy
/// Swift Coincide directory (`~/Library/Application Support/Coincide` by default)
/// without modifying the source directory and without clobbering existing data.
pub fn import_legacy_store(
    engine_shared: &SharedEngine,
    data_dir: &Path,
    source_override: Option<&str>,
) -> Result<Value> {
    let source = match source_override.map(str::trim).filter(|s| !s.is_empty()) {
        Some(raw) => PathBuf::from(raw),
        None => default_legacy_store_dir()
            .context("Could not determine ~/Library/Application Support/Coincide")?,
    };
    ensure!(source.is_absolute(), "Legacy source directory must be absolute");
    ensure!(
        source != data_dir,
        "Legacy source directory must differ from active runtime data directory"
    );
    let meta = fs::symlink_metadata(&source)
        .with_context(|| format!("Legacy directory does not exist: {}", source.display()))?;
    ensure!(
        meta.is_dir() && !meta.file_type().is_symlink(),
        "Legacy source must be a regular directory"
    );

    // Stage into a private temporary directory off-lock first so we never touch `source`
    // and can cleanly extract projects, bots, and read-only threads even if the active
    // Store already has conversations.
    let stage_dir = data_dir.join(format!(".legacy-import-stage-{}", Uuid::new_v4()));
    coincide_core::native_file::private_directory(&stage_dir)?;
    struct StageCleanup(PathBuf);
    impl Drop for StageCleanup {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    let _cleanup = StageCleanup(stage_dir.clone());

    let mut staged_projects: Vec<Value> = Vec::new();
    let mut staged_bots: Vec<Value> = Vec::new();
    let mut staged_threads: Vec<(String, String, Value)> = Vec::new();

    if source.join("threads").is_dir() {
        let mut stage_store = Store::open(&stage_dir.join("stage.sqlite"))?;
        let _report = stage_store.import_legacy(&source)?;
        if let Ok(projects) = stage_store.projects()
            && let Some(arr) = projects.as_array()
        {
            staged_projects = arr.clone();
        }
        if let Ok(Some(bots_doc)) = stage_store.document("bots.json")
            && let Some(arr) = bots_doc["bots"].as_array()
        {
            staged_bots = arr.clone();
        } else if let Ok(Some(bytes)) = stage_store.original("bots.json")
            && let Ok(doc) = serde_json::from_slice::<Value>(&bytes)
            && let Some(arr) = doc["bots"].as_array()
        {
            staged_bots = arr.clone();
        }
        for summary in stage_store.summaries("", true)? {
            if let Ok(original) = stage_store.thread(&summary.id) {
                staged_threads.push((summary.id, summary.title, original));
            }
        }
    } else {
        // Fallback when legacy folder only has projects.json / bots.json and no threads/ folder yet.
        let projects_file = source.join("projects.json");
        if projects_file.is_file()
            && !fs::symlink_metadata(&projects_file)?.file_type().is_symlink()
        {
            let raw = fs::read(&projects_file)?;
            let parsed: Value = serde_json::from_slice(&raw).context("Invalid projects.json")?;
            if let Some(arr) = parsed.as_array() {
                staged_projects = arr.clone();
            } else if let Some(arr) = parsed["projects"].as_array() {
                staged_projects = arr.clone();
            }
        }
        let bots_file = source.join("bots.json");
        if bots_file.is_file() && !fs::symlink_metadata(&bots_file)?.file_type().is_symlink() {
            let raw = fs::read(&bots_file)?;
            let parsed: Value = serde_json::from_slice(&raw).context("Invalid bots.json")?;
            if let Some(arr) = parsed["bots"].as_array() {
                staged_bots = arr.clone();
            }
        }
    }

    let mut engine = engine_shared
        .lock()
        .map_err(|_| anyhow::anyhow!("Engine lock poisoned"))?;
    ensure!(!engine.admissions_frozen(), "Application is closing");

    const LEDGER_DOC: &str = "macos-legacy-import-ledger.json";
    let mut ledger = engine
        .store
        .local_document(LEDGER_DOC)?
        .unwrap_or_else(|| json!({"threads": {}}));
    if !ledger["threads"].is_object() {
        ledger["threads"] = json!({});
    }

    // 1. Merge projects (by ID or canonical path)
    let mut current_projects = engine
        .store
        .projects()?
        .as_array()
        .cloned()
        .unwrap_or_default();
    let mut project_id_remap: HashMap<String, String> = HashMap::new();
    let mut imported_projects = 0usize;
    for legacy_proj in staged_projects {
        if legacy_proj["isChats"] == true || legacy_proj["isBots"] == true {
            continue;
        }
        let Some(legacy_id) = legacy_proj["id"].as_str() else {
            continue;
        };
        if legacy_id.eq_ignore_ascii_case(coincide_core::bot_runtime::BOTS_PROJECT_ID)
            || legacy_id == "00000000-0000-0000-0000-000000000000"
        {
            continue;
        }
        let legacy_path = legacy_proj["path"].as_str().unwrap_or("");
        if let Some(existing) = current_projects.iter().find(|p| {
            p["id"]
                .as_str()
                .is_some_and(|id| id.eq_ignore_ascii_case(legacy_id))
                || (!legacy_path.is_empty() && p["path"].as_str() == Some(legacy_path))
        }) {
            if let Some(existing_id) = existing["id"].as_str() {
                project_id_remap.insert(legacy_id.to_uppercase(), existing_id.to_owned());
            }
            continue;
        }
        current_projects.push(legacy_proj);
        imported_projects += 1;
    }
    if imported_projects > 0 {
        engine
            .store
            .save_document("projects.json", &Value::Array(current_projects))?;
    }

    // 2. Merge bots (by UUID)
    let mut imported_bots = 0usize;
    if !staged_bots.is_empty() {
        let mut bots_doc = engine
            .store
            .document("bots.json")?
            .unwrap_or_else(|| json!({"addedStarters": false, "bots": [], "starterLineup": 1}));
        if !bots_doc["bots"].is_array() {
            bots_doc["bots"] = json!([]);
        }
        let existing_bots = bots_doc["bots"].as_array_mut().unwrap();
        for bot in staged_bots {
            let Some(bot_id) = bot["id"].as_str().and_then(|s| Uuid::parse_str(s).ok()) else {
                continue;
            };
            let already = existing_bots.iter().any(|b| {
                b["id"]
                    .as_str()
                    .and_then(|s| Uuid::parse_str(s).ok())
                    == Some(bot_id)
            });
            if !already {
                existing_bots.push(bot);
                imported_bots += 1;
            }
        }
        if imported_bots > 0 {
            engine.store.save_document("bots.json", &bots_doc)?;
        }
    }

    // 3. Fork and save legacy threads (idempotent via ledger)
    let mut forks = Vec::new();
    let mut skipped_threads = 0usize;
    for (legacy_id, title, original) in staged_threads {
        let key = legacy_id.to_uppercase();
        if let Some(existing_fork) = ledger["threads"][&key].as_str()
            && engine.store.thread(existing_fork).is_ok()
        {
            skipped_threads += 1;
            continue;
        }
        let mut fork = original;
        let fork_id = Uuid::new_v4().to_string().to_uppercase();
        fork["id"] = json!(fork_id);
        if let Some(proj_id) = fork["projectID"].as_str()
            && let Some(mapped) = project_id_remap.get(&proj_id.to_uppercase())
        {
            fork["projectID"] = json!(mapped);
        }
        if let Some(fields) = fork.as_object_mut() {
            fields.remove("sessions");
            fields.remove("accountSessions");
            fields.remove("isImported");
            fields.remove("rustBotContext");
            fields.insert("accessMode".into(), json!("approval"));
            fields.insert("interactionMode".into(), json!("build"));
        }
        let provider = fork["selection"]["provider"]
            .as_str()
            .filter(|name| coincide_core::agent::Provider::from_name(name).is_ok())
            .unwrap_or("codex")
            .to_owned();
        let model_id = fork["selection"]["modelID"]
            .as_str()
            .filter(|m| !m.is_empty())
            .unwrap_or("default")
            .to_owned();
        fork["selection"] = json!({
            "provider": provider,
            "modelID": model_id,
        });
        engine.store.save(&fork)?;
        ledger["threads"][key] = json!(fork_id);
        forks.push(json!({
            "source": legacy_id,
            "fork": fork_id,
            "title": title,
        }));
    }

    engine.store.save_document(LEDGER_DOC, &ledger)?;
    if imported_projects > 0 || imported_bots > 0 || !forks.is_empty() {
        engine.revision += 1;
    }

    Ok(json!({
        "sourceDir": source,
        "importedProjects": imported_projects,
        "importedBots": imported_bots,
        "importedThreads": forks.len(),
        "skippedThreads": skipped_threads,
        "forked": forks,
    }))
}
