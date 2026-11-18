use crate::store::Store;
use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};
use std::time::{SystemTime, UNIX_EPOCH};

pub const MAX_KEY_CHARS: usize = 256;
pub const MAX_VALUE_BYTES: usize = 64 * 1024;
pub const MAX_SCOPE_CHARS: usize = 512;
pub const DEFAULT_LIST_LIMIT: usize = 200;
pub const DEFAULT_SNAPSHOT_LIMIT: usize = 50;

fn now_seconds() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn validate_key(raw: &str) -> Result<String> {
    let key = raw.trim();
    ensure!(!key.is_empty(), "Memory key must not be empty");
    ensure!(
        key.chars().count() <= MAX_KEY_CHARS,
        "Memory key must be at most 256 characters"
    );
    ensure!(
        !key.chars().any(char::is_control),
        "Memory key must not contain control characters"
    );
    Ok(key.to_owned())
}

fn validate_value(raw: &str) -> Result<String> {
    ensure!(
        raw.len() <= MAX_VALUE_BYTES,
        "Memory value must be at most 64 KiB"
    );
    ensure!(
        !raw.contains('\0'),
        "Memory value must not contain NUL bytes"
    );
    Ok(raw.to_owned())
}

pub fn normalize_scope(raw: Option<&str>) -> Result<String> {
    let scope = raw.map(str::trim).filter(|s| !s.is_empty()).unwrap_or("global");
    if scope == "global" {
        return Ok("global".to_owned());
    }
    let Some(id) = scope.strip_prefix("workspace:") else {
        bail!("Memory scope must be \"global\" or \"workspace:<identifier>\"");
    };
    let id = id.trim();
    ensure!(!id.is_empty(), "Workspace scope identifier must not be empty");
    ensure!(
        scope.chars().count() <= MAX_SCOPE_CHARS,
        "Memory scope must be at most 512 characters"
    );
    ensure!(
        !scope.chars().any(char::is_control),
        "Memory scope must not contain control characters"
    );
    Ok(format!("workspace:{id}"))
}

fn composite_key(scope: &str, key: &str) -> String {
    format!("{scope}\u{1f}{key}")
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

fn opt_limit(params: &Value, name: &str, default: usize) -> usize {
    params
        .get(name)
        .and_then(Value::as_u64)
        .map(|n| n as usize)
        .unwrap_or(default)
        .clamp(1, 1000)
}

fn entry_json(key: &str, scope: &str, value: &str, updated_at: f64) -> Value {
    json!({
        "key": key,
        "scope": scope,
        "value": value,
        "updatedAt": updated_at,
    })
}

fn entry_matches(entry: &Value, query: &str) -> bool {
    if query.is_empty() {
        return true;
    }
    let needle = query.to_lowercase();
    let key = entry
        .get("key")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_lowercase();
    let value = entry
        .get("value")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_lowercase();
    key.contains(&needle) || value.contains(&needle)
}

fn sorted_entries(entries: &[Value], scope: Option<&str>, query: &str) -> Vec<Value> {
    let mut rows: Vec<Value> = entries
        .iter()
        .filter(|entry| {
            scope.is_none_or(|wanted| entry.get("scope").and_then(Value::as_str) == Some(wanted))
                && entry_matches(entry, query)
        })
        .cloned()
        .collect();
    rows.sort_by(|a, b| {
        let ka = a.get("key").and_then(Value::as_str).unwrap_or("");
        let kb = b.get("key").and_then(Value::as_str).unwrap_or("");
        let sa = a.get("scope").and_then(Value::as_str).unwrap_or("");
        let sb = b.get("scope").and_then(Value::as_str).unwrap_or("");
        (sa, ka).cmp(&(sb, kb))
    });
    rows
}

pub fn store_entry(store: &mut Store, params: &Value) -> Result<Value> {
    let key = validate_key(&req_str(params, "key")?)?;
    let value = validate_value(&req_str(params, "value")?)?;
    let scope = normalize_scope(opt_str(params, "scope").as_deref())?;
    let composite = composite_key(&scope, &key);
    let updated_at = now_seconds();
    let overwritten = store.memory_upsert(&composite, &scope, &entry_json(&key, &scope, &value, updated_at))?;
    Ok(json!({
        "key": key,
        "scope": scope,
        "value": value,
        "overwritten": overwritten,
        "updatedAt": updated_at,
    }))
}

pub fn retrieve_entry(store: &Store, params: &Value) -> Result<Value> {
    let key = validate_key(&req_str(params, "key")?)?;
    let scope = normalize_scope(opt_str(params, "scope").as_deref())?;
    let composite = composite_key(&scope, &key);
    store
        .memory_entry(&composite)?
        .with_context(|| format!("No memory entry for key \"{key}\" in scope \"{scope}\""))
}

pub fn list_entries(store: &Store, params: &Value) -> Result<Value> {
    let scope = match opt_str(params, "scope") {
        Some(raw) if !raw.trim().is_empty() => Some(normalize_scope(Some(&raw))?),
        _ => None,
    };
    let query = opt_str(params, "query").unwrap_or_default();
    let limit = opt_limit(params, "limit", DEFAULT_LIST_LIMIT);
    let entries = store.memory_entries()?;
    let rows = sorted_entries(&entries, scope.as_deref(), &query);
    let total = rows.len();
    let truncated = total > limit;
    let page: Vec<Value> = rows.into_iter().take(limit).collect();
    Ok(json!({
        "entries": page,
        "total": total,
        "truncated": truncated,
    }))
}

pub fn delete_entry(store: &mut Store, params: &Value) -> Result<Value> {
    let key = validate_key(&req_str(params, "key")?)?;
    let scope = normalize_scope(opt_str(params, "scope").as_deref())?;
    let composite = composite_key(&scope, &key);
    ensure!(
        store.memory_delete(&composite)?,
        "No memory entry for key \"{key}\" in scope \"{scope}\""
    );
    Ok(json!({"key": key, "scope": scope, "deleted": true}))
}

pub fn clear_scope(store: &mut Store, params: &Value) -> Result<Value> {
    let scope = normalize_scope(Some(&req_str(params, "scope")?))?;
    let confirmed = params.get("confirm").and_then(Value::as_bool).unwrap_or(false);
    ensure!(
        confirmed,
        "mem_clear refuses without confirm=true: clearing a scope is irreversible"
    );
    let deleted = store.memory_delete_scope(&scope)?;
    Ok(json!({"scope": scope, "deleted": deleted}))
}

pub fn snapshot_context(store: &mut Store, params: &Value) -> Result<Value> {
    let scope = normalize_scope(opt_str(params, "scope").as_deref())?;
    let query = opt_str(params, "query").unwrap_or_default();
    let limit = opt_limit(params, "limit", DEFAULT_SNAPSHOT_LIMIT);
    let entries = store.memory_entries()?;
    let rows = sorted_entries(&entries, Some(&scope), &query);
    let total = rows.len();
    let page: Vec<Value> = rows.into_iter().take(limit).collect();
    let snapshot_id = uuid::Uuid::new_v4().to_string();
    let key = format!("snapshot:{snapshot_id}");
    let stored_at = now_seconds();
    let summary = json!({
        "snapshotId": snapshot_id,
        "scope": scope,
        "query": query,
        "entryKeys": page.iter().filter_map(|e| e.get("key").and_then(Value::as_str)).collect::<Vec<_>>(),
        "totalMatched": total,
        "storedAt": stored_at,
    });
    let value = serde_json::to_string(&summary)?;
    let composite = composite_key(&scope, &key);
    store.memory_upsert(&composite, &scope, &entry_json(&key, &scope, &value, stored_at))?;
    Ok(json!({
        "snapshotId": snapshot_id,
        "key": key,
        "scope": scope,
        "query": query,
        "entries": page,
        "totalMatched": total,
        "storedAt": stored_at,
    }))
}

pub fn context_store(store: &mut Store, params: &Value) -> Result<Value> {
    let key = validate_key(&req_str(params, "key")?)?;
    let scope = normalize_scope(opt_str(params, "scope").as_deref())?;
    let action = req_str(params, "action")?;
    match action.as_str() {
        "get" => {
            let composite = composite_key(&scope, &key);
            match store.memory_entry(&composite)? {
                Some(entry) => Ok(json!({
                    "key": key,
                    "scope": scope,
                    "value": entry.get("value").and_then(Value::as_str).unwrap_or(""),
                    "found": true,
                })),
                None => Ok(json!({
                    "key": key,
                    "scope": scope,
                    "value": "",
                    "found": false,
                })),
            }
        }
        "set" => {
            let value = validate_value(&req_str(params, "value")?)?;
            let composite = composite_key(&scope, &key);
            let updated_at = now_seconds();
            let overwritten = store.memory_upsert(&composite, &scope, &entry_json(&key, &scope, &value, updated_at))?;
            Ok(json!({
                "key": key,
                "scope": scope,
                "value": value,
                "overwritten": overwritten,
                "updatedAt": updated_at,
            }))
        }
        "delete" => {
            let composite = composite_key(&scope, &key);
            let deleted = store.memory_delete(&composite)?;
            Ok(json!({"key": key, "scope": scope, "deleted": deleted}))
        }
        other => bail!("Unknown context_persistence_store action \"{other}\": expected get, set, or delete"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::Store;

    fn fixture_store() -> (tempfile::TempDir, Store) {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::open(&dir.path().join("state.sqlite")).unwrap();
        (dir, store)
    }

    fn params(pairs: &[(&str, Value)]) -> Value {
        let mut map = serde_json::Map::new();
        for (key, value) in pairs {
            map.insert((*key).to_owned(), value.clone());
        }
        Value::Object(map)
    }

    #[test]
    fn store_retrieve_round_trip_upserts_explicitly() {
        let (_dir, mut store) = fixture_store();
        let first = store_entry(
            &mut store,
            &params(&[
                ("key", json!("editor")),
                ("value", json!("uses tabs")),
                ("scope", json!("global")),
            ]),
        )
        .unwrap();
        assert_eq!(first["overwritten"], false);
        let second = store_entry(
            &mut store,
            &params(&[
                ("key", json!("editor")),
                ("value", json!("uses spaces")),
                ("scope", json!("global")),
            ]),
        )
        .unwrap();
        assert_eq!(second["overwritten"], true);
        let got = retrieve_entry(
            &store,
            &params(&[("key", json!("editor")), ("scope", json!("global"))]),
        )
        .unwrap();
        assert_eq!(got["value"], "uses spaces");
    }

    #[test]
    fn scopes_isolate_the_same_key() {
        let (_dir, mut store) = fixture_store();
        store_entry(
            &mut store,
            &params(&[
                ("key", json!("theme")),
                ("value", json!("dark")),
                ("scope", json!("global")),
            ]),
        )
        .unwrap();
        store_entry(
            &mut store,
            &params(&[
                ("key", json!("theme")),
                ("value", json!("light")),
                ("scope", json!("workspace:/tmp/demo")),
            ]),
        )
        .unwrap();
        let global = retrieve_entry(
            &store,
            &params(&[("key", json!("theme")), ("scope", json!("global"))]),
        )
        .unwrap();
        assert_eq!(global["value"], "dark");
        let workspace = retrieve_entry(
            &store,
            &params(&[
                ("key", json!("theme")),
                ("scope", json!("workspace:/tmp/demo")),
            ]),
        )
        .unwrap();
        assert_eq!(workspace["value"], "light");
    }

    #[test]
    fn missing_key_retrieval_fails() {
        let (_dir, store) = fixture_store();
        assert!(retrieve_entry(&store, &params(&[("key", json!("nope"))])).is_err());
    }

    #[test]
    fn list_searches_keywords_and_reports_totals() {
        let (_dir, mut store) = fixture_store();
        for (key, value) in [
            ("alpha", "the quick fox"),
            ("beta", "slow turtle"),
            ("gamma", "quick hare"),
        ] {
            store_entry(
                &mut store,
                &params(&[("key", json!(key)), ("value", json!(value))]),
            )
            .unwrap();
        }
        let all = list_entries(&store, &params(&[])).unwrap();
        assert_eq!(all["total"], 3);
        let quick = list_entries(&store, &params(&[("query", json!("QUICK"))])).unwrap();
        assert_eq!(quick["total"], 2);
        let none = list_entries(&store, &params(&[("query", json!("zebra"))])).unwrap();
        assert_eq!(none["total"], 0);
    }

    #[test]
    fn delete_removes_one_entry_only() {
        let (_dir, mut store) = fixture_store();
        store_entry(
            &mut store,
            &params(&[("key", json!("a")), ("value", json!("1"))]),
        )
        .unwrap();
        store_entry(
            &mut store,
            &params(&[("key", json!("b")), ("value", json!("2"))]),
        )
        .unwrap();
        let removed = delete_entry(&mut store, &params(&[("key", json!("a"))])).unwrap();
        assert_eq!(removed["deleted"], true);
        assert!(retrieve_entry(&store, &params(&[("key", json!("a"))])).is_err());
        assert!(retrieve_entry(&store, &params(&[("key", json!("b"))])).is_ok());
        assert!(delete_entry(&mut store, &params(&[("key", json!("a"))])).is_err());
    }

    #[test]
    fn clear_requires_explicit_confirmation_and_only_clears_its_scope() {
        let (_dir, mut store) = fixture_store();
        store_entry(
            &mut store,
            &params(&[("key", json!("g")), ("value", json!("1"))]),
        )
        .unwrap();
        store_entry(
            &mut store,
            &params(&[
                ("key", json!("w")),
                ("value", json!("2")),
                ("scope", json!("workspace:/tmp/demo")),
            ]),
        )
        .unwrap();
        assert!(clear_scope(&mut store, &params(&[("scope", json!("workspace:/tmp/demo"))])).is_err());
        assert!(clear_scope(
            &mut store,
            &params(&[
                ("scope", json!("workspace:/tmp/demo")),
                ("confirm", json!(false)),
            ]),
        )
        .is_err());
        assert!(retrieve_entry(
            &store,
            &params(&[
                ("key", json!("w")),
                ("scope", json!("workspace:/tmp/demo")),
            ]),
        )
        .is_ok());
        let cleared = clear_scope(
            &mut store,
            &params(&[
                ("scope", json!("workspace:/tmp/demo")),
                ("confirm", json!(true)),
            ]),
        )
        .unwrap();
        assert_eq!(cleared["deleted"], 1);
        assert!(retrieve_entry(&store, &params(&[("key", json!("g"))])).is_ok());
    }

    #[test]
    fn snapshot_stores_a_new_entry_each_call() {
        let (_dir, mut store) = fixture_store();
        store_entry(
            &mut store,
            &params(&[("key", json!("fact")), ("value", json!("ships sail"))]),
        )
        .unwrap();
        let first = snapshot_context(&mut store, &params(&[("query", json!("ships"))])).unwrap();
        let second = snapshot_context(&mut store, &params(&[("query", json!("ships"))])).unwrap();
        assert_ne!(first["snapshotId"], second["snapshotId"]);
        assert_ne!(first["key"], second["key"]);
        assert_eq!(first["totalMatched"], 1);
        let stored = retrieve_entry(
            &store,
            &params(&[("key", json!(first["key"].as_str().unwrap()))]),
        )
        .unwrap();
        assert!(stored["value"].as_str().unwrap().contains("snapshotId"));
    }

    #[test]
    fn context_store_get_missing_succeeds_with_empty_value() {
        let (_dir, mut store) = fixture_store();
        let missing = context_store(
            &mut store,
            &params(&[("key", json!("ghost")), ("action", json!("get"))]),
        )
        .unwrap();
        assert_eq!(missing["value"], "");
        assert_eq!(missing["found"], false);
        context_store(
            &mut store,
            &params(&[
                ("key", json!("ghost")),
                ("action", json!("set")),
                ("value", json!("boo")),
            ]),
        )
        .unwrap();
        let found = context_store(
            &mut store,
            &params(&[("key", json!("ghost")), ("action", json!("get"))]),
        )
        .unwrap();
        assert_eq!(found["value"], "boo");
        assert_eq!(found["found"], true);
        let deleted = context_store(
            &mut store,
            &params(&[("key", json!("ghost")), ("action", json!("delete"))]),
        )
        .unwrap();
        assert_eq!(deleted["deleted"], true);
        let deleted_again = context_store(
            &mut store,
            &params(&[("key", json!("ghost")), ("action", json!("delete"))]),
        )
        .unwrap();
        assert_eq!(deleted_again["deleted"], false);
        assert!(context_store(
            &mut store,
            &params(&[("key", json!("ghost")), ("action", json!("bogus"))]),
        )
        .is_err());
    }

    #[test]
    fn entries_survive_a_store_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("state.sqlite");
        {
            let mut store = Store::open(&path).unwrap();
            store_entry(
                &mut store,
                &params(&[("key", json!("durable")), ("value", json!("yes"))]),
            )
            .unwrap();
        }
        let store = Store::open(&path).unwrap();
        let got = retrieve_entry(&store, &params(&[("key", json!("durable"))])).unwrap();
        assert_eq!(got["value"], "yes");
    }

    #[test]
    fn invalid_keys_values_and_scopes_are_rejected() {
        let (_dir, mut store) = fixture_store();
        assert!(store_entry(
            &mut store,
            &params(&[("key", json!("  ")), ("value", json!("x"))]),
        )
        .is_err());
        assert!(store_entry(
            &mut store,
            &params(&[("key", json!("k")), ("value", json!("x")), ("scope", json!("project"))]),
        )
        .is_err());
        assert!(store_entry(
            &mut store,
            &params(&[
                ("key", json!("k")),
                ("value", json!("x")),
                ("scope", json!("workspace:")),
            ]),
        )
        .is_err());
        let oversized = "v".repeat(MAX_VALUE_BYTES + 1);
        assert!(store_entry(
            &mut store,
            &params(&[("key", json!("k")), ("value", json!(oversized))]),
        )
        .is_err());
    }
}
