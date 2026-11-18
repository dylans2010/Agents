//! Antigravity uses only an explicitly selected native Gemini API-key account.
//! Old subscription configuration remains on disk, but cannot authorize a run.
use super::*;

const API_KEY_REQUIRED: &str = "Antigravity Google-account login is no longer supported. Add and select a Gemini API key account in Settings › Antigravity.";

fn account_id(value: &Value) -> Result<String> {
    let id = value.as_str().unwrap_or("default");
    ensure!(
        value.is_null() || value.is_string(),
        "Antigravity accountId must be text"
    );
    ensure!(
        id == "default" || Uuid::parse_str(id).is_ok_and(|uuid| uuid.to_string() == id),
        "Antigravity accountId must be default or a canonical UUID"
    );
    Ok(id.into())
}

fn probe_verification(
    probe: &Value,
    accounts: &[provider_configuration::NativeKeyAccount],
    approved_executable: Option<&str>,
) -> (bool, bool) {
    let state = probe["state"].as_str().unwrap_or("");
    let executable_matches = probe["executable"]
        .as_str()
        .is_some_and(|path| approved_executable == Some(path));
    let handshake_verified = matches!(state, "handshakeOk" | "authenticated") && executable_matches;
    let authentication_verified = state == "authenticated"
        && probe["usedKey"] == true
        && executable_matches
        && probe["accountId"].as_str().is_some_and(|id| {
            accounts.iter().any(|account| {
                account.id == id
                    && account.has_key
                    && probe["keyRevision"].as_str() == Some(account.revision.as_str())
            })
        });
    (handshake_verified, authentication_verified)
}

impl Engine {
    pub fn record_antigravity_probe(&mut self, report: &Value) -> Result<Value> {
        let state = report["state"].as_str().unwrap_or("");
        ensure!(
            matches!(
                state,
                "binaryMissing"
                    | "notApproved"
                    | "handshakeOk"
                    | "authenticated"
                    | "authRejected"
                    | "unreachable"
            ),
            "Antigravity probe state is invalid"
        );
        self.store
            .save_document("rust-antigravity-probe.json", report)?;
        self.revision += 1;
        self.antigravity_command("providers.antigravity.status", &json!({}))
    }

    pub(super) fn antigravity_command(&mut self, method: &str, _p: &Value) -> Result<Value> {
        match method {
            "providers.antigravity.status" => {
                let key_accounts = self.native_key_accounts("antigravity")?;
                let accounts = key_accounts
                    .iter()
                    .map(|account| {
                        (
                            account.id.clone(),
                            json!({"name":account.name,"auth":"apiKey","hasKey":account.has_key}),
                        )
                    })
                    .collect::<serde_json::Map<String, Value>>();
                let probe = self
                    .store
                    .local_document("rust-antigravity-probe.json")?
                    .unwrap_or(Value::Null);
                let approved_executable = self
                    .native_provider_configuration("antigravity")
                    .ok()
                    .and_then(|snapshot| {
                        if snapshot.approved {
                            snapshot
                                .executable
                                .map(|path| path.to_string_lossy().into_owned())
                        } else {
                            None
                        }
                    });
                let (handshake_verified, authentication_verified) =
                    probe_verification(&probe, &key_accounts, approved_executable.as_deref());
                Ok(json!({
                    "authentication":"gemini_api_key_only",
                    "authenticationVerified":authentication_verified,
                    "handshakeVerified":handshake_verified,
                    "probe":probe,
                    "accounts":accounts,
                    "termsURL":"https://antigravity.google/docs/ide/extensions/acp",
                    "remaining":["quota_display","windows_runtime"]
                }))
            }
            "providers.antigravity.configure" | "providers.antigravity.acknowledge" => {
                bail!("{API_KEY_REQUIRED}")
            }
            _ => bail!("Unknown Antigravity configuration command"),
        }
    }

    pub(super) fn antigravity_selection(&self, selection: &Value) -> Result<(String, Value)> {
        let id = account_id(&selection["accountID"])?;
        if provider_configuration::native_key_profile("antigravity")
            && provider_configuration::native_account_matches(selection)
        {
            return Ok((id, json!({"auth":"apiKey","native":true})));
        }
        // Permit choosing the provider before choosing a key account, and keep
        // old named selections readable. Neither placeholder authorizes a run.
        let legacy = if id == "default" {
            false
        } else {
            self.store
                .local_document("rust-antigravity.json")?
                .is_some_and(|config| config["accounts"].get(&id).is_some())
        };
        ensure!(id == "default" || legacy, "{API_KEY_REQUIRED}");
        Ok((id, json!({"auth":"apiKeyRequired"})))
    }

    pub(super) fn antigravity_launch(
        &self,
        thread_id: &str,
        selection: &Value,
    ) -> Result<(Provider, PathBuf)> {
        let (id, account) = self.antigravity_selection(selection)?;
        ensure!(account["native"] == true, "{API_KEY_REQUIRED}");
        let executable = provider_configuration::current()
            .and_then(|configuration| configuration.approved_executable())
            .context("Approve the Antigravity executable and helper in Settings first")?;
        let data = self.store.data_directory()?;
        Ok((
            Provider::Antigravity {
                profile: Some(
                    data.join("providers/antigravity")
                        .join(id)
                        .join("threads")
                        .join(thread_id),
                ),
                source_profile: None,
                risk_acknowledged: true,
            },
            executable,
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selected_native_gemini_key_authorizes_only_its_own_account() {
        crate::provider_configuration::tests::with_native_key_configuration(
            "antigravity",
            |engine, _home| {
                let accounts = engine.native_provider_accounts("antigravity").unwrap();
                let id = &accounts[0].id;
                let selection =
                    json!({"provider":"antigravity","modelID":"default","accountID":id});
                let status = engine
                    .antigravity_command("providers.antigravity.status", &json!({}))
                    .unwrap();
                assert_eq!(status["accounts"][id]["auth"], "apiKey");
                assert_eq!(status["accounts"][id]["hasKey"], true);
                assert_eq!(
                    engine.antigravity_selection(&selection).unwrap().1["auth"],
                    "apiKey"
                );
                let (adapter, _) = engine.antigravity_launch("thread", &selection).unwrap();
                assert!(matches!(
                    adapter,
                    Provider::Antigravity {
                        source_profile: None,
                        ..
                    }
                ));
                let other = json!({"provider":"antigravity","modelID":"default","accountID":Uuid::new_v4().to_string()});
                assert!(engine.antigravity_launch("thread", &other).is_err());
            },
        );
    }

    #[test]
    fn legacy_oauth_configuration_never_authorizes_or_changes_a_launch() {
        let root = tempfile::tempdir().unwrap();
        let mut engine = Engine::new(Store::open(&root.path().join("state.sqlite")).unwrap());
        let legacy = json!({"version":1,"accounts":{"default":{"auth":"login","sourceProfile":"/old"}},"riskAcknowledgement":{"key":"provider:antigravity-account-risk","accepted":true}});
        engine
            .store
            .save_document("rust-antigravity.json", &legacy)
            .unwrap();
        let selection = json!({"provider":"antigravity","modelID":"default"});
        assert_eq!(
            engine.antigravity_selection(&selection).unwrap().1["auth"],
            "apiKeyRequired"
        );
        assert!(engine.antigravity_launch("thread", &selection).is_err());
        for method in [
            "providers.antigravity.configure",
            "providers.antigravity.acknowledge",
        ] {
            assert!(
                engine
                    .antigravity_command(method, &json!({"auth":"login","accepted":true}))
                    .is_err()
            );
        }
        assert_eq!(
            engine
                .store
                .local_document("rust-antigravity.json")
                .unwrap(),
            Some(legacy)
        );
        assert!(engine.runs.is_empty());
    }

    #[test]
    fn recorded_probe_verifies_only_matching_runtime_and_account() {
        crate::provider_configuration::tests::with_native_key_configuration(
            "antigravity",
            |engine, _home| {
                let snapshot = engine.native_provider_configuration("antigravity").unwrap();
                let executable = snapshot.executable.unwrap().to_string_lossy().into_owned();
                let account = engine.native_key_accounts("antigravity").unwrap().remove(0);
                let report = |state: &str,
                              account_id: Option<&str>,
                              key_revision: Option<&str>,
                              used_key: bool| {
                    json!({"state": state, "mode": "authenticate", "executable": executable.clone(), "accountId": account_id, "keyRevision": key_revision, "usedKey": used_key, "protocolVersion": 1, "authMethods": ["gemini-api-key"], "serverName": null, "serverVersion": null, "authenticateResultKeys": [], "errorCode": null, "detail": null, "checkedAtUnix": 1, "durationMs": 1})
                };
                let status = engine
                    .record_antigravity_probe(&report("handshakeOk", None, None, false))
                    .unwrap();
                assert_eq!(status["handshakeVerified"], true);
                assert_eq!(status["authenticationVerified"], false);
                assert_eq!(status["probe"]["state"], "handshakeOk");
                let status = engine
                    .record_antigravity_probe(&report(
                        "authenticated",
                        Some(&account.id),
                        Some(&account.revision),
                        true,
                    ))
                    .unwrap();
                assert_eq!(status["handshakeVerified"], true);
                assert_eq!(status["authenticationVerified"], true);
                let status = engine
                    .record_antigravity_probe(&report(
                        "authenticated",
                        Some("3f2b8c1e-9d4a-4b6f-8e2d-1c0a9b8f7e6d"),
                        Some(&account.revision),
                        true,
                    ))
                    .unwrap();
                assert_eq!(status["handshakeVerified"], true);
                assert_eq!(status["authenticationVerified"], false);
                let status = engine
                    .record_antigravity_probe(&report(
                        "authenticated",
                        Some(&account.id),
                        Some("stale-revision"),
                        true,
                    ))
                    .unwrap();
                assert_eq!(status["authenticationVerified"], false);
                let mut mismatched =
                    report("authenticated", Some(&account.id), Some(&account.revision), true);
                mismatched["executable"] = json!("/elsewhere/agy_acp_server.par");
                let status = engine.record_antigravity_probe(&mismatched).unwrap();
                assert_eq!(status["handshakeVerified"], false);
                assert_eq!(status["authenticationVerified"], false);
                assert!(engine
                    .record_antigravity_probe(&json!({"state": "claimed"}))
                    .is_err());
            },
        );
    }
}
