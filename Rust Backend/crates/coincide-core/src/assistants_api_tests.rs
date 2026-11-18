use super::*;
use crate::assistants::validate_assistant;

const ID: &str = "00000000-0000-4000-8000-000000000001";
const OTHER_ID: &str = "00000000-0000-4000-8000-000000000002";

fn fixture() -> (tempfile::TempDir, Engine) {
    let root = tempfile::tempdir().unwrap();
    let engine = Engine::new(Store::open(&root.path().join("rust.sqlite")).unwrap());
    (root, engine)
}

fn record(id: &str) -> Value {
    json!({
        "id": id,
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
        "permissionProfile": "read-only",
        "inputRequirements": ["A diff"],
        "version": 1,
        "source": "custom",
        "isFavorite": false,
        "lastUsedAt": Value::Null,
        "createdAt": 1_000_000,
        "updatedAt": 1_000_000,
        "futureField": {"keep": true}
    })
}

fn save(engine: &mut Engine, assistant: &Value, baseline: &Value) -> Value {
    engine
        .execute(
            "assistants.save",
            &json!({"assistant": assistant, "baseline": baseline}),
        )
        .unwrap()
}

#[test]
fn save_list_update_and_delete_round_trip() {
    let (_root, mut engine) = fixture();
    let listed = engine.execute("assistants.list", &json!({})).unwrap();
    assert_eq!(listed["origin"], "empty");
    assert_eq!(listed["assistants"], json!([]));
    let created = save(&mut engine, &record(ID), &listed["baseline"]);
    assert_eq!(created["assistant"]["id"], ID);
    assert_eq!(created["assistant"]["futureField"], json!({"keep": true}));
    assert_eq!(created["assistant"]["createdAt"], json!(1_000_000));
    assert!(created["assistant"]["updatedAt"].as_i64().unwrap() > 1_000_000);
    assert_eq!(created["origin"], "local");
    let revision = engine.revision;
    let listed = engine.execute("assistants.list", &json!({})).unwrap();
    assert_eq!(listed["assistants"].as_array().unwrap().len(), 1);
    assert_eq!(listed["assistants"][0]["name"], "Reviewer");
    let mut updated = record(ID);
    updated["name"] = json!("Senior Reviewer");
    updated["createdAt"] = json!(5);
    let saved = save(&mut engine, &updated, &listed["baseline"]);
    assert_eq!(saved["assistant"]["name"], "Senior Reviewer");
    assert_eq!(saved["assistant"]["createdAt"], json!(1_000_000));
    assert_eq!(saved["assistant"]["futureField"], json!({"keep": true}));
    assert_eq!(engine.revision, revision + 1);
    let listed = engine.execute("assistants.list", &json!({})).unwrap();
    let deleted = engine
        .execute(
            "assistants.delete",
            &json!({"assistantId": ID, "baseline": listed["baseline"]}),
        )
        .unwrap();
    assert_eq!(deleted["assistants"], json!([]));
    let listed = engine.execute("assistants.list", &json!({})).unwrap();
    assert_eq!(listed["assistants"], json!([]));
    let error = engine
        .execute(
            "assistants.delete",
            &json!({"assistantId": ID, "baseline": listed["baseline"]}),
        )
        .unwrap_err();
    assert!(error.to_string().contains("Assistant not found"));
}

#[test]
fn unknown_delete_and_unknown_method_fail_without_changing_revision() {
    let (_root, mut engine) = fixture();
    let listed = engine.execute("assistants.list", &json!({})).unwrap();
    let revision = engine.revision;
    let error = engine
        .execute(
            "assistants.delete",
            &json!({"assistantId": OTHER_ID, "baseline": listed["baseline"]}),
        )
        .unwrap_err();
    assert!(error.to_string().contains("Assistant not found"));
    assert_eq!(engine.revision, revision);
    let error = engine
        .execute("assistants.bogus", &json!({}))
        .unwrap_err();
    assert!(error.to_string().contains("Unsupported method: assistants.bogus"));
    assert_eq!(engine.revision, revision);
}

#[test]
fn stale_baseline_save_is_rejected() {
    let (_root, mut engine) = fixture();
    let listed = engine.execute("assistants.list", &json!({})).unwrap();
    let created = save(&mut engine, &record(ID), &listed["baseline"]);
    let error = engine
        .execute(
            "assistants.save",
            &json!({"assistant": record(OTHER_ID), "baseline": listed["baseline"]}),
        )
        .unwrap_err();
    assert!(error
        .to_string()
        .contains("Assistant document changed; reload before saving"));
    let listed = engine.execute("assistants.list", &json!({})).unwrap();
    assert_eq!(listed["baseline"], created["baseline"]);
    assert_eq!(listed["assistants"].as_array().unwrap().len(), 1);
}

#[test]
fn store_cas_rejects_a_stale_expected_document() {
    let root = tempfile::tempdir().unwrap();
    let mut store = Store::open(&root.path().join("rust.sqlite")).unwrap();
    let empty = json!({"version": 1, "assistants": []});
    store
        .save_assistants_document_if_unchanged(None, &empty)
        .unwrap();
    assert_eq!(store.assistants_document().unwrap(), Some(empty.clone()));
    let changed = json!({"version": 1, "assistants": [record(ID)]});
    let error = store
        .save_assistants_document_if_unchanged(None, &changed)
        .unwrap_err();
    assert!(error
        .to_string()
        .contains("Assistant document changed; reload before saving"));
    assert_eq!(store.assistants_document().unwrap(), Some(empty));
    store
        .save_assistants_document_if_unchanged(Some(&json!({"version": 1, "assistants": []})), &changed)
        .unwrap();
    assert_eq!(store.assistants_document().unwrap(), Some(changed));
}

#[test]
fn secure_defaults_apply_to_a_minimal_record() {
    let minimal = json!({
        "id": ID,
        "name": "Helper",
        "category": "building-fixing",
        "systemPrompt": "Build it.",
        "source": "custom"
    });
    let assistant = validate_assistant(&minimal).unwrap();
    assert_eq!(assistant.permission_profile, "read-only");
    assert!(!assistant.is_favorite);
    assert_eq!(assistant.version, 1);
    assert_eq!(assistant.allowed_tools, None);
    assert_eq!(assistant.provider, None);
    assert_eq!(assistant.model, None);
    assert_eq!(assistant.input_requirements, None);
    assert_eq!(assistant.last_used_at, None);
    assert!(assistant.extra.is_empty());
}

#[test]
fn validation_rejects_each_bad_record() {
    let mut empty_name = record(ID);
    empty_name["name"] = json!("   ");
    assert!(validate_assistant(&empty_name).is_err());
    let mut long_name = record(ID);
    long_name["name"] = json!("n".repeat(1025));
    assert!(validate_assistant(&long_name).is_err());
    let mut empty_prompt = record(ID);
    empty_prompt["systemPrompt"] = json!("");
    assert!(validate_assistant(&empty_prompt).is_err());
    let mut long_prompt = record(ID);
    long_prompt["systemPrompt"] = json!("p".repeat(1_048_577));
    assert!(validate_assistant(&long_prompt).is_err());
    let mut nul_prompt = record(ID);
    nul_prompt["systemPrompt"] = json!("has\0nul");
    assert!(validate_assistant(&nul_prompt).is_err());
    let mut bad_category = record(ID);
    bad_category["category"] = json!("brainstorming");
    assert!(validate_assistant(&bad_category).is_err());
    let mut bad_profile = record(ID);
    bad_profile["permissionProfile"] = json!("root");
    assert!(validate_assistant(&bad_profile).is_err());
    let mut bad_source = record(ID);
    bad_source["source"] = json!("builtin");
    assert!(validate_assistant(&bad_source).is_err());
    let mut unknown_tool = record(ID);
    unknown_tool["allowedTools"] = json!([""]);
    assert!(validate_assistant(&unknown_tool).is_err());
    let mut duplicate_tools = record(ID);
    duplicate_tools["allowedTools"] = json!(["read_file", "read_file"]);
    assert!(validate_assistant(&duplicate_tools).is_err());
    let mut too_many_tasks = record(ID);
    too_many_tasks["intendedTasks"] = json!((0..33).map(|n| format!("task {n}")).collect::<Vec<_>>());
    assert!(validate_assistant(&too_many_tasks).is_err());
    let mut long_task = record(ID);
    long_task["intendedTasks"] = json!(["t".repeat(513)]);
    assert!(validate_assistant(&long_task).is_err());
    let mut too_many_requirements = record(ID);
    too_many_requirements["inputRequirements"] = json!((0..17).map(|n| format!("need {n}")).collect::<Vec<_>>());
    assert!(validate_assistant(&too_many_requirements).is_err());
    let mut bad_version = record(ID);
    bad_version["version"] = json!(0);
    assert!(validate_assistant(&bad_version).is_err());
    let mut bad_provider = record(ID);
    bad_provider["provider"] = json!("not-a-provider");
    assert!(validate_assistant(&bad_provider).is_err());
    let mut bad_id = record(ID);
    bad_id["id"] = json!("not-a-uuid");
    assert!(validate_assistant(&bad_id).is_err());
    let mut long_model = record(ID);
    long_model["model"] = json!("m".repeat(257));
    assert!(validate_assistant(&long_model).is_err());
    let document = json!({
        "version": 1,
        "assistants": [record(ID), record(ID)]
    });
    let typed: AssistantsDocument = serde_json::from_value(document).unwrap();
    assert!(typed.validate().is_err());
    let bad_document = json!({"version": 2, "assistants": []});
    let typed: AssistantsDocument = serde_json::from_value(bad_document).unwrap();
    assert!(typed.validate().is_err());
}

#[test]
fn validation_rejects_allowed_tools_for_opencode_and_lithos() {
    for provider in ["opencode", "lithos"] {
        let mut with_tools = record(ID);
        with_tools["provider"] = json!(provider);
        with_tools["allowedTools"] = json!(["read_file"]);
        let error = validate_assistant(&with_tools).unwrap_err();
        assert!(error.to_string().contains(&format!(
            "Allowed tools are not supported for provider \"{provider}\": OpenCode and Lithos cannot use System Tools"
        )));
        let mut empty_tools = record(ID);
        empty_tools["provider"] = json!(provider);
        empty_tools["allowedTools"] = json!([]);
        assert!(validate_assistant(&empty_tools).is_ok());
        let mut null_tools = record(ID);
        null_tools["provider"] = json!(provider);
        null_tools["allowedTools"] = Value::Null;
        assert!(validate_assistant(&null_tools).is_ok());
        let mut absent_tools = record(ID);
        absent_tools["provider"] = json!(provider);
        absent_tools
            .as_object_mut()
            .unwrap()
            .remove("allowedTools");
        assert!(validate_assistant(&absent_tools).is_ok());
    }
    let mut claude_tools = record(ID);
    claude_tools["provider"] = json!("claude");
    claude_tools["allowedTools"] = json!(["read_file"]);
    assert!(validate_assistant(&claude_tools).is_ok());
}

#[test]
fn document_and_record_unknown_fields_survive_restart() {
    let (root, mut engine) = fixture();
    let listed = engine.execute("assistants.list", &json!({})).unwrap();
    save(&mut engine, &record(ID), &listed["baseline"]);
    engine
        .store
        .save_document(
            "assistants.json",
            &json!({"version": 1, "assistants": [record(ID)], "futureEnvelope": {"keep": [1]}}),
        )
        .unwrap();
    drop(engine);
    let mut restarted = Engine::new(Store::open(&root.path().join("rust.sqlite")).unwrap());
    let listed = restarted.execute("assistants.list", &json!({})).unwrap();
    assert_eq!(listed["assistants"][0]["futureField"], json!({"keep": true}));
    assert_eq!(
        restarted.store.document("assistants.json").unwrap().unwrap()["futureEnvelope"],
        json!({"keep": [1]})
    );
}
