use super::*;
use crate::assistants::{Assistant, AssistantsDocument, empty_document, validate_assistant};
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

pub(super) const METHODS: &[&str] = &["assistants.list", "assistants.save", "assistants.delete"];
const DOCUMENT: &str = "assistants.json";

struct Snapshot {
    source: Option<Value>,
    document: Value,
    baseline: String,
    origin: &'static str,
}

fn load(store: &Store) -> Result<Snapshot> {
    let local = store.local_document(DOCUMENT)?;
    let (source, origin) = if let Some(local) = local {
        (Some(local), "local")
    } else if let Some(bytes) = store.original(DOCUMENT)? {
        ensure!(
            bytes.len() <= crate::organization::DOCUMENT_LIMIT,
            "Assistants document exceeds size limit"
        );
        (
            Some(serde_json::from_slice(&bytes).context("Captured assistants document is invalid")?),
            "imported",
        )
    } else {
        (None, "empty")
    };
    let document = source.clone().unwrap_or_else(empty_document);
    let typed: AssistantsDocument =
        serde_json::from_value(document.clone()).context("Assistants document is invalid")?;
    let baseline = crate::digest_hex::lower_hex(Sha256::digest(typed.validate()?));
    Ok(Snapshot {
        source,
        document,
        baseline,
        origin,
    })
}

pub(crate) fn find_assistant(store: &Store, id: Uuid) -> Result<Assistant> {
    let snapshot = load(store)?;
    let found = snapshot.document["assistants"]
        .as_array()
        .context("Invalid assistants envelope")?
        .iter()
        .find(|assistant| {
            assistant["id"]
                .as_str()
                .and_then(|value| Uuid::parse_str(value).ok())
                == Some(id)
        })
        .with_context(|| format!("Unknown assistant '{id}'"))?;
    validate_assistant(found)
}

fn response(snapshot: &Snapshot, assistant: Option<&Value>) -> Value {
    let mut result = json!({"baseline": snapshot.baseline, "origin": snapshot.origin, "version": 1});
    if let Some(assistant) = assistant {
        result["assistant"] = assistant.clone();
    } else {
        result["assistants"] = snapshot.document["assistants"].clone();
    }
    result
}

fn check_baseline(params: &Value, snapshot: &Snapshot) -> Result<()> {
    let baseline = required(params, "baseline")?;
    ensure!(
        baseline.len() == 64 && baseline.bytes().all(|byte| byte.is_ascii_hexdigit()),
        "Invalid assistant baseline"
    );
    ensure!(
        baseline == snapshot.baseline,
        "Assistant document changed; reload before saving"
    );
    Ok(())
}

fn index(document: &Value, id: Uuid) -> Result<usize> {
    document["assistants"]
        .as_array()
        .context("Invalid assistants envelope")?
        .iter()
        .position(|assistant| {
            assistant["id"]
                .as_str()
                .and_then(|id| Uuid::parse_str(id).ok())
                == Some(id)
        })
        .context("Assistant not found")
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}

fn save_snapshot(engine: &mut Engine, snapshot: &mut Snapshot) -> Result<String> {
    let typed: AssistantsDocument =
        serde_json::from_value(snapshot.document.clone()).context("Assistants document is invalid")?;
    let baseline = crate::digest_hex::lower_hex(Sha256::digest(typed.validate()?));
    engine
        .store
        .save_assistants_document_if_unchanged(snapshot.source.as_ref(), &snapshot.document)?;
    engine.revision += 1;
    snapshot.baseline = baseline.clone();
    snapshot.origin = "local";
    Ok(baseline)
}

impl Engine {
    pub(super) fn assistants_command(&mut self, method: &str, params: &Value) -> Result<Value> {
        ensure!(METHODS.contains(&method), "Unknown assistant method");
        let object = params.as_object().context("Assistant params must be an object")?;
        let allowed: &[&str] = match method {
            "assistants.list" => &[],
            "assistants.save" => &["assistant", "baseline"],
            "assistants.delete" => &["assistantId", "baseline"],
            _ => &[],
        };
        ensure!(
            object.keys().all(|key| allowed.contains(&key.as_str())),
            "Unknown assistant parameter"
        );
        let mut snapshot = load(&self.store)?;
        if method == "assistants.list" {
            return Ok(response(&snapshot, None));
        }
        check_baseline(params, &snapshot)?;
        if method == "assistants.delete" {
            let id = Uuid::parse_str(required(params, "assistantId")?)
                .context("Invalid assistant UUID")?;
            let position = index(&snapshot.document, id)?;
            snapshot.document["assistants"]
                .as_array_mut()
                .context("Invalid assistants envelope")?
                .remove(position);
            save_snapshot(self, &mut snapshot)?;
            return Ok(response(&snapshot, None));
        }
        let mut incoming = validate_assistant(&params["assistant"])?;
        let id = Uuid::parse_str(&incoming.id).context("Invalid assistant UUID")?;
        let now = now_secs();
        let assistants = snapshot.document["assistants"]
            .as_array_mut()
            .context("Invalid assistants envelope")?;
        let position = match assistants.iter().position(|existing| {
            existing["id"]
                .as_str()
                .and_then(|value| Uuid::parse_str(value).ok())
                == Some(id)
        }) {
            Some(position) => {
                let stored: Assistant = serde_json::from_value(assistants[position].clone())
                    .context("Stored assistant is invalid")?;
                incoming.created_at = stored.created_at;
                incoming.last_used_at = stored.last_used_at;
                incoming.updated_at = now;
                assistants[position] = serde_json::to_value(&incoming)?;
                position
            }
            None => {
                ensure!(
                    assistants.len() < crate::organization::RECORD_LIMIT,
                    "Too many assistants"
                );
                if incoming.created_at <= 0 {
                    incoming.created_at = now;
                }
                incoming.updated_at = now;
                assistants.push(serde_json::to_value(&incoming)?);
                assistants.len() - 1
            }
        };
        save_snapshot(self, &mut snapshot)?;
        Ok(response(
            &snapshot,
            Some(&snapshot.document["assistants"][position]),
        ))
    }
}

#[cfg(test)]
#[path = "assistants_api_tests.rs"]
mod tests;
