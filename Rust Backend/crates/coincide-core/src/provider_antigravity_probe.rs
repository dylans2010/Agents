use super::Launch;
use super::antigravity::AUTH_FAILURE;
use super::antigravity::profile::{Profile, removed_environment};
use super::transport::Transport;
use crate::api::provider_configuration::{
    AntigravityProbe, AntigravityProbeReport, AntigravityProbeState, antigravity_runtime_copy,
    enter,
};
use serde_json::{Value, json};
use std::{
    fs,
    path::Path,
    time::{Duration, Instant, SystemTime},
};

const PROBE_TIMEOUT: Duration = Duration::from_secs(60);
const PROBE_INVALID_KEY: &str = "coincide-probe-invalid-key";
const MAX_DETAIL: usize = 500;

fn sanitize(text: &str) -> String {
    let cleaned: String = text
        .chars()
        .map(|c| if c.is_control() && c != '\t' { ' ' } else { c })
        .collect();
    if cleaned.len() > MAX_DETAIL {
        let mut truncated = cleaned.chars().take(MAX_DETAIL).collect::<String>();
        truncated.push_str("...");
        truncated
    } else {
        cleaned
    }
}

fn initialize_frame() -> Value {
    json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientInfo":{"name":"Coincide","version":env!("CARGO_PKG_VERSION")},"clientCapabilities":{"fs":{"readTextFile":true,"writeTextFile":true},"terminal":false}}})
}

fn authenticate_frame() -> Value {
    json!({"jsonrpc":"2.0","id":2,"method":"authenticate","params":{"methodId":"gemini-api-key"}})
}

pub(crate) fn run(probe: &AntigravityProbe) -> AntigravityProbeReport {
    let started = Instant::now();
    let checked_at_unix = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0);
    let mode = if probe.invalid_key {
        "invalid-key"
    } else if probe.account_id.is_some() {
        "authenticate"
    } else {
        "handshake"
    };
    let mut report = AntigravityProbeReport {
        state: AntigravityProbeState::Unreachable,
        mode,
        executable: probe.executable.clone(),
        account_id: probe.account_id.clone(),
        key_revision: probe.key_revision.clone(),
        used_key: false,
        protocol_version: None,
        auth_methods: Vec::new(),
        server_name: None,
        server_version: None,
        authenticate_result_keys: Vec::new(),
        error_code: None,
        detail: None,
        checked_at_unix,
        duration_ms: 0,
    };
    execute(probe, &mut report, started);
    report.duration_ms = started.elapsed().as_millis() as u64;
    report
}

fn execute(probe: &AntigravityProbe, report: &mut AntigravityProbeReport, started: Instant) {
    let _scope = enter(probe.configuration.clone());
    let Some(executable) = probe.executable.as_ref() else {
        if probe.unapproved_candidate {
            report.state = AntigravityProbeState::NotApproved;
            report.detail = Some(
                "Antigravity runtime binary was found but is not approved; approve it in Settings before probing"
                    .into(),
            );
        } else {
            report.state = AntigravityProbeState::BinaryMissing;
            report.detail =
                Some("Antigravity runtime binary (agy_acp_server.par) was not found".into());
        }
        return;
    };
    let probe_dir = probe
        .data_dir
        .join("providers/antigravity/probe")
        .join(uuid::Uuid::new_v4().to_string());
    let profile = match Profile::prepare_probe(&probe_dir) {
        Ok(profile) => profile,
        Err(error) => {
            let _ = fs::remove_dir_all(&probe_dir);
            report.state = AntigravityProbeState::Unreachable;
            report.detail = Some(format!(
                "Antigravity probe profile could not be prepared: {}",
                sanitize(&error.to_string())
            ));
            return;
        }
    };
    handshake(probe, &profile, executable, report, started);
    drop(profile);
    let _ = fs::remove_dir_all(&probe_dir);
    let _ = fs::remove_dir(probe.data_dir.join("providers/antigravity/probe"));
}

fn handshake(
    probe: &AntigravityProbe,
    profile: &Profile,
    executable: &Path,
    report: &mut AntigravityProbeReport,
    started: Instant,
) {
    let copied = match profile.runtime(executable) {
        Ok(path) => path,
        Err(error) => {
            report.state = AntigravityProbeState::Unreachable;
            report.detail = Some(format!(
                "Antigravity runtime failed its integrity check: {}",
                sanitize(&error.to_string())
            ));
            return;
        }
    };
    let _runtime_scope = match antigravity_runtime_copy(executable, &copied) {
        Ok(scope) => scope,
        Err(error) => {
            report.state = AntigravityProbeState::Unreachable;
            report.detail = Some(format!(
                "Antigravity private runtime copy was rejected: {}",
                sanitize(&error.to_string())
            ));
            return;
        }
    };
    let mut launch = Launch {
        executable: copied.clone(),
        cwd: profile.directory.clone(),
        session: None,
        prompt: String::new(),
        model: None,
        variant: None,
        full_access: false,
        mcp: None,
    };
    launch.cwd = match launch.cwd.canonicalize() {
        Ok(path) => path,
        Err(error) => {
            report.state = AntigravityProbeState::Unreachable;
            report.detail = Some(format!(
                "Antigravity probe profile directory is unavailable: {}",
                sanitize(&error.to_string())
            ));
            return;
        }
    };
    let mut environment = profile.environment(&copied);
    if probe.invalid_key {
        environment.retain(|(key, _)| key.to_string_lossy() != "GEMINI_API_KEY");
        environment.push(("GEMINI_API_KEY".into(), PROBE_INVALID_KEY.into()));
        report.used_key = true;
    } else if probe.account_id.is_some() {
        report.used_key = true;
    }
    let removed = removed_environment();
    let removed: Vec<&str> = removed.iter().map(String::as_str).collect();
    let mut transport = match Transport::spawn_antigravity(&launch, &removed, &environment) {
        Ok(transport) => transport,
        Err(error) => {
            report.state = AntigravityProbeState::Unreachable;
            report.detail = Some(format!(
                "Antigravity runtime could not be launched: {}",
                sanitize(&error.to_string())
            ));
            return;
        }
    };
    if let Err(error) = transport.write(&initialize_frame()) {
        report.state = AntigravityProbeState::Unreachable;
        report.detail = Some(format!(
            "Antigravity initialize request could not be sent: {}",
            sanitize(&error.to_string())
        ));
        return;
    }
    let deadline = started + PROBE_TIMEOUT;
    let mut stage = 1u64;
    loop {
        if Instant::now() >= deadline {
            report.state = AntigravityProbeState::Unreachable;
            report.detail = Some(format!(
                "Antigravity probe timed out after 60 seconds waiting for {}",
                if stage == 1 {
                    "initialize"
                } else {
                    "authenticate"
                }
            ));
            return;
        }
        let frame = match transport.next() {
            Ok(Some(frame)) => frame,
            Ok(None) => continue,
            Err(error) => {
                let message = error.to_string();
                if message == AUTH_FAILURE {
                    report.state = AntigravityProbeState::AuthRejected;
                    report.detail = Some(
                        "Antigravity server requested interactive sign-in; API-key authentication was not accepted"
                            .into(),
                    );
                } else {
                    report.state = AntigravityProbeState::Unreachable;
                    report.detail = Some(format!(
                        "Antigravity server connection failed: {}",
                        sanitize(&message)
                    ));
                }
                return;
            }
        };
        if frame.get("id").and_then(Value::as_u64) != Some(stage) {
            continue;
        }
        if let Some(error) = frame.get("error") {
            report.error_code = error.get("code").and_then(Value::as_i64);
            let message = error.get("message").and_then(Value::as_str).unwrap_or("");
            if stage == 1 {
                report.state = AntigravityProbeState::Unreachable;
                report.detail = Some(format!(
                    "Antigravity server rejected initialize: {}",
                    sanitize(message)
                ));
            } else if message.contains("SUBSCRIPTION_REQUIRED") {
                report.state = AntigravityProbeState::AuthRejected;
                report.detail = Some(
                    "Antigravity server reports SUBSCRIPTION_REQUIRED for this account".into(),
                );
            } else {
                report.state = AntigravityProbeState::AuthRejected;
                report.detail = Some(format!(
                    "Antigravity server rejected API-key authentication: {}",
                    sanitize(message)
                ));
            }
            return;
        }
        let Some(result) = frame.get("result") else {
            report.state = AntigravityProbeState::Unreachable;
            report.detail = Some("Antigravity response has no result".into());
            return;
        };
        if stage == 1 {
            if result.get("protocolVersion").and_then(Value::as_u64) != Some(1) {
                report.state = AntigravityProbeState::Unreachable;
                report.detail =
                    Some("Antigravity server did not answer ACP protocol version 1".into());
                return;
            }
            report.protocol_version = Some(1);
            report.auth_methods = result
                .get("authMethods")
                .and_then(Value::as_array)
                .map(|methods| {
                    methods
                        .iter()
                        .filter_map(|method| {
                            method
                                .get("id")
                                .and_then(Value::as_str)
                                .map(str::to_owned)
                        })
                        .collect()
                })
                .unwrap_or_default();
            if let Some(info) = result.get("agentInfo") {
                report.server_name = info
                    .get("name")
                    .and_then(Value::as_str)
                    .map(|name| sanitize(name));
                report.server_version = info
                    .get("version")
                    .and_then(Value::as_str)
                    .map(|version| sanitize(version));
            }
            if !report
                .auth_methods
                .iter()
                .any(|method| method == "gemini-api-key")
            {
                report.state = AntigravityProbeState::AuthRejected;
                report.detail = Some(
                    "Antigravity server did not offer gemini-api-key authentication".into(),
                );
                return;
            }
            if report.mode == "handshake" {
                report.state = AntigravityProbeState::HandshakeOk;
                return;
            }
            if let Err(error) = transport.write(&authenticate_frame()) {
                report.state = AntigravityProbeState::Unreachable;
                report.detail = Some(format!(
                    "Antigravity authenticate request could not be sent: {}",
                    sanitize(&error.to_string())
                ));
                return;
            }
            stage = 2;
        } else {
            report.authenticate_result_keys = result
                .as_object()
                .map(|object| object.keys().cloned().collect())
                .unwrap_or_default();
            report.state = AntigravityProbeState::Authenticated;
            return;
        }
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use crate::provider_configuration::tests::with_native_key_executable;

    const HANDSHAKE_SCRIPT: &[u8] = br##"#!/usr/bin/env python3
import json, os, sys
assert "GEMINI_API_KEY" not in os.environ
assert "AGY_ACP_ENABLE_OAUTH" not in os.environ
from pathlib import Path
assert not (Path(os.environ["GEMINI_HOME"]) / "antigravity-acp/acp_token.json").exists()
def read():
    return json.loads(sys.stdin.readline())
def reply(request, result):
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
request = read()
assert request["method"] == "initialize"
assert request["params"]["protocolVersion"] == 1
reply(request, {"protocolVersion": 1, "authMethods": [{"id": "gemini-api-key"}], "agentInfo": {"name": "antigravity-acp", "version": "9.9-test"}, "agentCapabilities": {}})
sys.stdin.readline()
"##;

    const AUTH_SCRIPT: &[u8] = br##"#!/usr/bin/env python3
import json, os, sys
assert os.environ["GEMINI_API_KEY"] == "synthetic-owned-account-key"
def read():
    return json.loads(sys.stdin.readline())
def reply(request, result):
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
request = read()
assert request["method"] == "initialize"
reply(request, {"protocolVersion": 1, "authMethods": [{"id": "gemini-api-key"}], "agentCapabilities": {}})
request = read()
assert request["method"] == "authenticate"
assert request["params"] == {"methodId": "gemini-api-key"}
reply(request, {"account": "probe-account"})
sys.stdin.readline()
"##;

    const REJECT_SCRIPT: &[u8] = br##"#!/usr/bin/env python3
import json, os, sys
assert os.environ["GEMINI_API_KEY"] == "coincide-probe-invalid-key"
def read():
    return json.loads(sys.stdin.readline())
request = read()
assert request["method"] == "initialize"
print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": {"protocolVersion": 1, "authMethods": [{"id": "gemini-api-key"}]}}), flush=True)
request = read()
assert request["method"] == "authenticate"
print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "error": {"code": -32001, "message": "API key not valid. Please pass a valid API key."}}), flush=True)
sys.stdin.readline()
"##;

    const NO_API_KEY_SCRIPT: &[u8] = br##"#!/usr/bin/env python3
import json, sys
def read():
    return json.loads(sys.stdin.readline())
request = read()
assert request["method"] == "initialize"
print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": {"protocolVersion": 1, "authMethods": [{"id": "oauth-personal"}]}}), flush=True)
sys.stdin.readline()
"##;

    const EXIT_SCRIPT: &[u8] = b"#!/usr/bin/env python3\nimport sys\nsys.exit(3)\n";

    fn probe_dir(engine: &crate::api::Engine) -> std::path::PathBuf {
        engine
            .store
            .data_directory()
            .unwrap()
            .join("providers/antigravity/probe")
    }

    #[test]
    fn handshake_probe_verifies_runtime_without_presenting_a_key() {
        with_native_key_executable("antigravity", HANDSHAKE_SCRIPT, |engine, _home, binary| {
            let probe = engine
                .prepare_antigravity_probe(Some(binary.to_path_buf()), false, None, false)
                .unwrap();
            let report = probe.run();
            assert_eq!(report.state, AntigravityProbeState::HandshakeOk);
            assert_eq!(report.mode, "handshake");
            assert!(!report.used_key);
            assert_eq!(report.protocol_version, Some(1));
            assert_eq!(report.auth_methods, vec!["gemini-api-key".to_string()]);
            assert_eq!(report.server_name.as_deref(), Some("antigravity-acp"));
            assert_eq!(report.server_version.as_deref(), Some("9.9-test"));
            assert!(report.detail.is_none());
            assert!(!probe_dir(engine).exists());
            assert!(!report.to_json().to_string().contains("synthetic-owned-account-key"));
        });
    }

    #[test]
    fn authenticate_probe_verifies_the_selected_account_key() {
        with_native_key_executable("antigravity", AUTH_SCRIPT, |engine, _home, binary| {
            let account = engine.native_key_accounts("antigravity").unwrap().remove(0);
            let probe = engine
                .prepare_antigravity_probe(
                    Some(binary.to_path_buf()),
                    false,
                    Some(&account.id),
                    false,
                )
                .unwrap();
            let report = probe.run();
            assert_eq!(report.state, AntigravityProbeState::Authenticated);
            assert_eq!(report.mode, "authenticate");
            assert!(report.used_key);
            assert_eq!(report.account_id.as_deref(), Some(account.id.as_str()));
            assert_eq!(report.authenticate_result_keys, vec!["account".to_string()]);
            assert!(!probe_dir(engine).exists());
            assert!(!report.to_json().to_string().contains("synthetic-owned-account-key"));
        });
    }

    #[test]
    fn invalid_key_probe_reports_the_server_rejection() {
        with_native_key_executable("antigravity", REJECT_SCRIPT, |engine, _home, binary| {
            let probe = engine
                .prepare_antigravity_probe(Some(binary.to_path_buf()), false, None, true)
                .unwrap();
            let report = probe.run();
            assert_eq!(report.state, AntigravityProbeState::AuthRejected);
            assert_eq!(report.mode, "invalid-key");
            assert!(report.used_key);
            assert_eq!(report.error_code, Some(-32001));
            assert!(report
                .detail
                .as_deref()
                .unwrap()
                .contains("API key not valid"));
            assert!(!probe_dir(engine).exists());
            assert!(!report.to_json().to_string().contains("coincide-probe-invalid-key"));
        });
    }

    #[test]
    fn authenticate_probe_rejects_a_server_without_api_key_auth() {
        with_native_key_executable("antigravity", NO_API_KEY_SCRIPT, |engine, _home, binary| {
            let account = engine.native_key_accounts("antigravity").unwrap().remove(0);
            let probe = engine
                .prepare_antigravity_probe(
                    Some(binary.to_path_buf()),
                    false,
                    Some(&account.id),
                    false,
                )
                .unwrap();
            let report = probe.run();
            assert_eq!(report.state, AntigravityProbeState::AuthRejected);
            assert!(report
                .detail
                .as_deref()
                .unwrap()
                .contains("did not offer gemini-api-key"));
            assert!(!probe_dir(engine).exists());
            assert!(!report.to_json().to_string().contains("synthetic-owned-account-key"));
        });
    }

    #[test]
    fn exiting_server_is_unreachable_not_authenticated() {
        with_native_key_executable("antigravity", EXIT_SCRIPT, |engine, _home, binary| {
            let probe = engine
                .prepare_antigravity_probe(Some(binary.to_path_buf()), false, None, false)
                .unwrap();
            let report = probe.run();
            assert_eq!(report.state, AntigravityProbeState::Unreachable);
            assert!(!probe_dir(engine).exists());
            assert!(!report.to_json().to_string().contains("synthetic-owned-account-key"));
        });
    }
}
