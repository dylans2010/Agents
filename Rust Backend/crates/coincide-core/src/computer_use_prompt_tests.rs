use super::*;
use crate::computer_use::Authority;
use crate::computer_use_bridge::{Access, Bridge};
use std::{fs, path::Path};

const FAKE: &str = r#"#!/usr/bin/env python3
import json,sys
def read():
    line=sys.stdin.readline()
    return json.loads(line) if line else None
def write(v):
    print(json.dumps(v),flush=True)
with open('launches.jsonl','a') as f: f.write('launched\n'); f.flush()
while True:
    r=read()
    if r is None:
        break
    if 'request_id' in r:
        write({'type':'control_response','response':{'subtype':'success','request_id':r['request_id']}})
        continue
    if r.get('type')=='user':
        with open('prompts.jsonl','a') as f: f.write(json.dumps(r['message']['content'])+'\n'); f.flush()
        session=sys.argv[sys.argv.index('--resume')+1] if '--resume' in sys.argv else sys.argv[sys.argv.index('--session-id')+1]
        write({'type':'system','subtype':'init','session_id':session})
        write({'type':'result','subtype':'success','is_error':False,'session_id':session,'result':'Synthetic computer-use reply'})
"#;

fn fixture(root: &Path) -> (SharedEngine, Arc<Bridge>, String) {
    fs::create_dir_all(root).unwrap();
    let mut store = Store::open(&root.join("state.sqlite")).unwrap();
    let project = store
        .create_project(root, Some("computer-use prompt fixture"))
        .unwrap();
    let mut thread = store.new_thread(project["id"].as_str().unwrap()).unwrap();
    thread["selection"] = json!({"provider": "claude", "modelID": "default"});
    let id = text(&thread, "id");
    store.save(&thread).unwrap();
    let mut engine = Engine::fixture(store);
    engine.schedule_initialized = true;
    engine.schedule_last_poll = Instant::now();
    engine.set_active_thread(Some(id.clone())).unwrap();
    engine.ui_available = true;
    let authority = Authority::default();
    authority.native_enable(true);
    engine.computer_use_bind_authority(authority);
    let shared: SharedEngine = Arc::new(Mutex::new(engine));
    let bridge = Arc::new(Bridge::new(&shared));
    shared
        .lock()
        .unwrap()
        .computer_use_bind_bridge(bridge.clone());
    (shared, bridge, id)
}

fn transport_secrets(access: &Access) -> (String, String) {
    let config = access.configuration.display().to_string();
    let text = fs::read_to_string(&access.configuration).unwrap();
    let token = text
        .lines()
        .find_map(|line| line.strip_prefix("header = \"Authorization: Bearer "))
        .unwrap()
        .trim_end_matches('"')
        .to_owned();
    (config, token)
}

fn forbidden(config: &str, token: &str, thread: &str) -> Vec<String> {
    vec![
        "<coincide_computer_use>".to_owned(),
        "computer-use.curl".to_owned(),
        "CoincideComputerUse".to_owned(),
        "curl --config".to_owned(),
        "curl.exe --config".to_owned(),
        "Bearer ".to_owned(),
        config.to_owned(),
        token.to_owned(),
        thread.to_owned(),
    ]
}

fn assert_clean(prompt: &str, forbidden: &[String]) {
    for secret in forbidden {
        assert!(
            !prompt.contains(secret.as_str()),
            "outgoing prompt carries transport material"
        );
    }
}

fn prompts(root: &Path) -> Vec<String> {
    fs::read_to_string(root.join("prompts.jsonl"))
        .unwrap_or_default()
        .lines()
        .map(|line| {
            let value: Value = serde_json::from_str(line).unwrap();
            match &value {
                Value::String(text) => text.clone(),
                Value::Array(blocks) => blocks
                    .iter()
                    .filter_map(|block| block.get("text").and_then(Value::as_str))
                    .collect::<Vec<_>>()
                    .join(""),
                _ => value.to_string(),
            }
        })
        .collect()
}

fn wait_done(engine: &mut Engine) {
    let deadline = Instant::now() + Duration::from_secs(12);
    loop {
        engine.poll();
        let workers = engine.provider_workers_status();
        if engine.runs.is_empty() && workers.running == 0 {
            assert_eq!(workers.panicked, 0);
            assert_eq!(workers.unclassified, 0);
            return;
        }
        assert!(
            Instant::now() < deadline,
            "fake provider did not finish/join"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn seed_assistant(engine: &mut Engine) -> String {
    let id = "00000000-0000-4000-8000-000000000001";
    let listed = engine.execute("assistants.list", &json!({})).unwrap();
    let assistant = json!({
        "id": id,
        "name": "Reviewer",
        "description": "Reviews diffs",
        "icon": "magnifyingglass",
        "category": "code-review-security",
        "systemPrompt": "Review the diff for security issues.",
        "intendedTasks": ["Review pull requests"],
        "expectedOutputFormat": "A list of findings",
        "allowedTools": ["read_file", "write_file"],
        "provider": "claude",
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
    engine
        .execute(
            "assistants.save",
            &json!({"assistant": assistant, "baseline": listed["baseline"]}),
        )
        .unwrap();
    id.to_owned()
}

#[cfg(unix)]
fn standard_chat_turn_carries_no_transport(root: &Path) {
    let (shared, bridge, id) = fixture(root);
    let thread = Uuid::parse_str(&id).unwrap();
    let access = bridge.access(thread).unwrap();
    let (config, token) = transport_secrets(&access);
    let forbidden = forbidden(&config, &token, &id);
    shared
        .lock()
        .unwrap()
        .send_turn(
            &json!({"threadId": id, "text": "What windows are open?"}),
            SendOrigin::Ordinary,
        )
        .unwrap();
    wait_done(&mut shared.lock().unwrap());
    let wire = prompts(root);
    assert!(!wire.is_empty());
    for prompt in &wire {
        assert!(prompt.contains("What windows are open?"));
        assert_clean(prompt, &forbidden);
    }
    let stored = String::from_utf8_lossy(&fs::read(root.join("state.sqlite")).unwrap());
    assert!(
        !stored.contains(token.as_str()),
        "durable thread state carries the transport token"
    );
    assert!(
        !stored.contains(config.as_str()),
        "durable thread state carries the curl config path"
    );
}

#[cfg(unix)]
fn assistant_spawn_carries_no_transport(root: &Path) {
    let (shared, bridge, id) = fixture(root);
    let assistant_id = seed_assistant(&mut shared.lock().unwrap());
    let spawned = shared
        .lock()
        .unwrap()
        .workers_spawn(&json!({
            "parentThreadId": id,
            "name": "reviewer",
            "task": "Review the diff for security issues.",
            "targetFiles": [],
            "assistantId": assistant_id,
        }))
        .unwrap();
    let child = spawned["workers"][0]["threadId"]
        .as_str()
        .unwrap()
        .to_owned();
    let access = bridge.access(Uuid::parse_str(&child).unwrap()).unwrap();
    let (config, token) = transport_secrets(&access);
    let mut forbidden = forbidden(&config, &token, &child);
    forbidden.push(id.clone());
    wait_done(&mut shared.lock().unwrap());
    let wire = prompts(root);
    assert!(!wire.is_empty());
    for prompt in &wire {
        assert!(prompt.contains("Review the diff for security issues."));
        assert_clean(prompt, &forbidden);
    }
}

#[cfg(unix)]
fn worker_turn_carries_no_transport(root: &Path) {
    let (shared, bridge, id) = fixture(root);
    let spawned = shared
        .lock()
        .unwrap()
        .workers_spawn(&json!({
            "parentThreadId": id,
            "name": "worker",
            "task": "Summarize the workspace layout.",
            "targetFiles": [],
        }))
        .unwrap();
    let child = spawned["workers"][0]["threadId"]
        .as_str()
        .unwrap()
        .to_owned();
    let access = bridge.access(Uuid::parse_str(&child).unwrap()).unwrap();
    let (config, token) = transport_secrets(&access);
    let mut forbidden = forbidden(&config, &token, &child);
    forbidden.push(id.clone());
    wait_done(&mut shared.lock().unwrap());
    let wire = prompts(root);
    assert!(!wire.is_empty());
    for prompt in &wire {
        assert!(prompt.contains("Summarize the workspace layout."));
        assert_clean(prompt, &forbidden);
    }
}

#[cfg(unix)]
#[test]
fn outgoing_prompts_carry_no_computer_use_transport_in_isolated_child() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::tempdir().unwrap();
    let executable = dir.path().join("computer-use-fixture-claude");
    fs::write(&executable, FAKE).unwrap();
    fs::set_permissions(&executable, fs::Permissions::from_mode(0o700)).unwrap();
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--ignored",
            "--exact",
            "api::computer_use_prompt_tests::computer_use_prompt_child",
            "--nocapture",
        ])
        .env("COINCIDE_CLAUDE_EXECUTABLE", &executable)
        .env("COMPUTER_USE_PROMPT_FIXTURE_DIRECTORY", dir.path())
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "computer-use prompt child failed:\n{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[cfg(unix)]
#[test]
#[ignore = "only re-executed with isolated fake provider environment"]
fn computer_use_prompt_child() {
    let Some(root) = std::env::var_os("COMPUTER_USE_PROMPT_FIXTURE_DIRECTORY") else {
        return;
    };
    let root = PathBuf::from(root);
    assert!(std::env::var_os("COINCIDE_CLAUDE_EXECUTABLE").is_some());
    standard_chat_turn_carries_no_transport(&root.join("chat"));
    assistant_spawn_carries_no_transport(&root.join("assistant"));
    worker_turn_carries_no_transport(&root.join("worker"));
}
