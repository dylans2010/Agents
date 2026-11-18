use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

fn next_id() -> u64 {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

struct Session {
    child: Child,
    stdin: ChildStdin,
    reader: BufReader<std::process::ChildStdout>,
}

impl Session {
    fn spawn(workspace: &std::path::Path, assets: Option<&std::path::Path>) -> Self {
        let exe = env!("CARGO_BIN_EXE_coincide-mcp-server");
        let mut command = Command::new(exe);
        command
            .arg("--cwd")
            .arg(workspace)
            .arg("--socket")
            .arg(workspace.join("missing-control.sock"));
        if let Some(dir) = assets {
            command.arg("--assets-dir").arg(dir);
        }
        let mut child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn coincide-mcp-server");
        let stdin = child.stdin.take().expect("server stdin");
        let stdout = child.stdout.take().expect("server stdout");
        Session {
            child,
            stdin,
            reader: BufReader::new(stdout),
        }
    }

    fn request(&mut self, method: &str, params: Value) -> Value {
        let id = next_id();
        let payload = json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params});
        self.stdin
            .write_all(serde_json::to_string(&payload).unwrap().as_bytes())
            .unwrap();
        self.stdin.write_all(b"\n").unwrap();
        self.stdin.flush().unwrap();
        self.read_response()
    }

    fn notify(&mut self, method: &str) {
        let payload = json!({"jsonrpc": "2.0", "method": method});
        self.stdin
            .write_all(serde_json::to_string(&payload).unwrap().as_bytes())
            .unwrap();
        self.stdin.write_all(b"\n").unwrap();
        self.stdin.flush().unwrap();
    }

    fn read_response(&mut self) -> Value {
        let mut line = String::new();
        self.reader.read_line(&mut line).unwrap();
        assert!(!line.is_empty(), "server closed stdout without a response");
        serde_json::from_str(&line).unwrap()
    }

    fn close(mut self) {
        drop(self.stdin);
        let status = self.child.wait().unwrap();
        assert!(status.success(), "server exited with {status}");
    }
}

fn temp_dir(prefix: &str) -> tempfile::TempDir {
    tempfile::Builder::new()
        .prefix(prefix)
        .tempdir()
        .expect("create temp dir")
}

fn asset_fixtures() -> tempfile::TempDir {
    let dir = temp_dir("agents-mcp-assets");
    std::fs::write(dir.path().join("Safeguards.md"), "# Safeguards\n").unwrap();
    std::fs::write(dir.path().join("Identity.md"), "# Identity\n").unwrap();
    std::fs::write(dir.path().join("ToolRoutingPolicy.md"), "# Routing\n").unwrap();
    dir
}

fn initialize(session: &mut Session) -> Value {
    let response = session.request(
        "initialize",
        json!({
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "clientInfo": {"name": "test-client", "version": "0.0.0"},
        }),
    );
    assert_eq!(response["jsonrpc"], "2.0");
    assert!(response.get("error").is_none(), "initialize failed: {response}");
    session.notify("notifications/initialized");
    response["result"].clone()
}

fn call(session: &mut Session, name: &str, arguments: Value) -> Value {
    let response = session.request("tools/call", json!({"name": name, "arguments": arguments}));
    assert!(response.get("error").is_none(), "tools/call failed: {response}");
    response["result"].clone()
}

fn call_text(session: &mut Session, name: &str, arguments: Value) -> String {
    let result = call(session, name, arguments);
    result["content"][0]["text"].as_str().unwrap().to_owned()
}

#[test]
fn initialize_handshake_advertises_tools_resources_and_prompts() {
    let workspace = temp_dir("agents-mcp-workspace");
    let mut session = Session::spawn(workspace.path(), None);
    let result = initialize(&mut session);
    assert_eq!(result["protocolVersion"], "2025-03-26");
    assert!(result["capabilities"]["tools"].is_object());
    assert!(result["capabilities"]["resources"].is_object());
    assert!(result["capabilities"]["prompts"].is_object());
    assert_eq!(result["serverInfo"]["name"], "coincide-mcp-server");
    let ping = session.request("ping", json!({}));
    assert!(ping.get("error").is_none(), "ping failed: {ping}");
    session.close();
}

#[test]
fn tools_list_returns_the_real_registry() {
    let workspace = temp_dir("agents-mcp-workspace");
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    let response = session.request("tools/list", json!({}));
    let tools = response["result"]["tools"].as_array().unwrap();
    assert_eq!(tools.len(), 337);
    let names: Vec<&str> = tools
        .iter()
        .map(|tool| tool["name"].as_str().unwrap())
        .collect();
    for expected in [
        "read_file",
        "write_file",
        "list_files",
        "search_files",
        "create_terminal",
        "write_terminal",
        "read_terminal",
        "git_status",
        "git_diff",
        "git_log",
        "git_show",
        "git_diff_range",
        "git_diff_branch",
        "delete_file",
        "delete_directory",
        "move_file",
        "copy_file",
        "create_directory",
        "read_directory",
        "edit_file",
        "multi_edit_file",
        "search_regex",
        "run_build",
        "run_tests",
        "git_commit",
        "git_push",
        "git_pull",
        "git_branch_list",
        "git_branch_create",
        "git_branch_checkout",
        "mem_store",
        "mem_retrieve",
        "view_memory",
        "mem_delete",
        "mem_clear",
        "mem_context_snapshot",
        "context_persistence_store",
        "use_workers",
        "list_workers",
        "worker_status",
        "worker_result",
        "cancel_worker",
        "delete_worker",
        "intel_plan_task",
        "intel_breakdown_task",
        "execution_plan",
        "list_apps",
        "list_windows",
        "get_window_state",
        "get_desktop_state",
        "verify_state",
        "zoom",
        "click",
        "double_click",
        "right_click",
        "set_value",
        "type_text",
        "press_key",
        "hotkey",
        "scroll",
        "drag",
        "move_cursor",
        "click_point",
        "invoke_menu",
        "launch_app",
        "set_window_frame",
        "file_read",
        "view_file",
        "file_write",
        "create_file",
        "file_create",
        "file_append",
        "file_delete",
        "dir_delete",
        "file_move",
        "file_rename",
        "file_copy",
        "dir_create",
        "dir_read",
        "list_directory",
        "tree_view",
        "search_directory",
        "search_text",
        "code_replace",
        "code_insert",
        "code_multi_edit",
        "use_terminal",
        "run_command",
        "git_log_viewer",
        "git_branch_compare",
        "project_diff",
        "git_branch_manager",
        "save_to_memory",
        "use_mcp",
        "take_screenshot",
        "start_subagent",
        "git_stash_operator",
        "git_blame_inspector",
        "git_bisect",
        "git_cherry_pick",
        "version_control_operator",
        "git_pr_summary",
        "git_conflict_resolver",
        "project_snapshot",
        "project_changelog",
        "project_restore",
        "safe_undo",
        "safe_validate_changes",
        "create_artifact",
        "list_artifacts",
        "read_artifact",
        "delete_artifact",
        "format_json_file",
        "csv_to_json",
        "json_to_csv",
        "plist_to_json",
        "json_to_plist",
        "json_validate",
        "json_validator_tool",
        "yaml_validate",
        "yaml_parser_tool",
        "plist_edit",
        "plist_editor",
        "binary_plist_converter",
        "file_metadata",
        "file_hash_verify",
        "generate_file_checksum",
        "file_checksum_verifier",
        "file_compare_diff",
        "file_head_preview",
        "code_generate",
        "code_format",
        "swift_format_lint",
        "code_mutation_engine",
        "patch_application_engine",
        "automated_repair_engine",
        "regex_replace_in_files",
        "symbol_rename_project",
        "symbol_move_file",
        "import_cleanup",
        "batch_rename_files",
        "file_backup",
        "session_export",
        "markdown_toc_generate",
        "readme_generate",
        "docs_generate",
        "test_data_factory",
        "ui_test_scaffold",
        "test_snapshot_manage",
        "open_in_finder",
        "reveal_in_finder",
        "image_encode_base64",
        "image_decode_base64",
        "image_get_dimensions",
        "image_convert_format",
        "image_generate_thumbnail",
        "image_extract_metadata",
        "zip_file",
        "unzip_file",
        "tar_archive_create",
        "tar_archive_extract",
        "gzip_compress_file",
        "gzip_decompress_file",
        "count_file_lines",
        "extract_code_symbols",
        "find_duplicate_files",
        "env_capture_logs",
        "project_build",
        "project_test",
        "compiler_diagnostics_engine",
        "dependency_resolution_engine",
        "generate_xcodeproj",
        "project_scheme_list",
        "project_target_list",
        "project_build_settings",
        "project_clean",
        "project_archive",
        "test_run_single",
        "test_coverage_report",
        "test_coverage_reporter",
        "performance_benchmark",
        "docc_build",
        "xcode_scheme_manager",
        "xcode_build_settings_inspector",
        "xcode_device_destination_finder",
        "simulator_list",
        "simulator_boot",
        "simulator_controller",
        "device_list",
        "provisioning_check",
        "swift_package_manager",
        "package_dependency_update",
        "code_signing_diagnose",
        "xcode_toolchain_info",
        "xcresult_parser",
        "mach_o_binary_analyzer",
        "signing_certificate_inspector",
        "provisioning_profile_reader",
        "swift_ast_inspector",
        "binary_size_report",
        "git_review_diff",
        "search_symbol",
        "dependency_graph",
        "source_graph_builder",
        "semantic_query_engine",
        "code_summary",
        "code_lint",
        "complexity_analysis",
        "autonomous_review_engine",
        "runtime_diagnostics_engine",
        "code_metrics_analyzer",
        "memory_leak_detector",
        "dead_code_eliminator",
        "dead_code_scan",
        "duplicate_code_scan",
        "todo_scan",
        "todo_fixme_scanner",
        "license_header_check",
        "api_surface_extract",
        "access_level_audit",
        "concurrency_audit",
        "swift_concurrency_analyzer",
        "swift_migration_advisor",
        "security_audit_scanner",
        "secrets_scan",
        "network_security_auditor",
        "permissions_audit",
        "accessibility_audit",
        "accessibility_audit_scanner",
        "interface_simulator",
        "docstring_generator",
        "code_snippet_manager",
        "unused_imports_detector",
        "force_unwrap_scan",
        "string_literal_audit",
        "comment_density_report",
        "function_size_report",
        "call_hierarchy",
        "type_hierarchy",
        "protocol_conformance_list",
        "import_graph",
        "change_impact_estimate",
        "conflict_marker_scan",
        "build_log_analyze",
        "crash_log_parse",
        "deprecation_usage_scan",
        "info_plist_audit",
        "api_endpoint_audit",
        "color_usage_audit",
        "strings_file_validate",
        "entitlements_diff",
        "pbxproj_lint",
        "xctest_discovery",
        "build_settings_diff",
        "build_phase_scripts_list",
        "build_configuration_list",
        "target_dependencies_list",
        "target_source_list",
        "workspace_settings_read",
        "scheme_test_plan_list",
        "test_log_parse",
        "test_flaky_detect",
        "code_comment_extract",
        "api_docs_coverage",
        "markdown_link_check",
        "docs_index_build",
        "framework_linker_auditor",
        "string_catalog_migrator",
        "symbol_reference_graph",
        "podfile_inspector",
        "carthage_cartfile_inspector",
        "spm_dependency_tree",
        "package_manifest_read",
        "package_manifest_validate",
        "package_dependency_audit",
        "package_dependency_add",
        "asset_catalog_list",
        "asset_image_add",
        "strings_localization",
        "localization_audit",
        "localize_app",
        "asset_catalog_manager",
        "localization_manager",
        "entitlements_manager",
        "colorset_builder",
        "icon_generator_tool",
        "project_entitlements",
        "project_info_plist",
        "project_capabilities",
        "project_signing",
        "entry_points_discover",
        "repo_overview",
        "project_structure_map",
        "recent_changes",
        "readme_locate",
        "dependency_licenses",
        "stale_files_report",
        "file_type_breakdown",
        "empty_dirs_find",
        "symlink_audit",
        "executable_files_scan",
        "dir_size_report",
        "image_asset_size_report",
        "bundle_resource_auditor",
        "core_data_model_inspector",
        "swift_data_schema_auditor",
        "privacy_manifest_auditor",
        "env_info",
        "process_monitor_tool",
        "disk_space_analyzer",
        "environment_variable_manager",
        "clipboard_manager_tool",
        "system_notification_tool",
        "use_system",
        "search_skills",
        "system_asset_read",
        "system_asset_list",
        "system_asset_get_metadata",
        "system_asset_search_related",
        "plan-AskUser",
        "tool_capability_lookup",
        "preflight_checks",
        "session_progress_report",
        "manage_memory",
        "fetch_documentation",
        "external_resource_gateway",
        "read_url_content",
        "github_repo",
        "use_app",
        "derived_data_locate",
        "build_system_detect",
        "svg_to_png",
        "intel_generate_tests",
        "search_web",
        "reverse_analyze",
        "report_to_user",
        "intel_explain_code",
    ] {
        assert!(names.contains(&expected), "tools/list missing {expected}");
    }
    for tool in tools {
        assert!(tool["inputSchema"]["properties"].is_object());
        assert!(tool["inputSchema"]["required"].is_array());
    }
    session.close();
}

#[test]
fn tools_call_executes_real_file_operations() {
    let workspace = temp_dir("agents-mcp-workspace");
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    let path = workspace.path().join("hello.txt");
    let write = call_text(
        &mut session,
        "write_file",
        json!({"path": path, "content": "hello agents"}),
    );
    assert!(write.contains("hello.txt"), "unexpected write result: {write}");
    let read = call_text(&mut session, "read_file", json!({"path": path}));
    assert!(read.contains("hello agents"), "unexpected read result: {read}");
    call_text(
        &mut session,
        "edit_file",
        json!({"path": path, "oldText": "hello", "newText": "goodbye"}),
    );
    let edited = call_text(&mut session, "read_file", json!({"path": path}));
    assert!(edited.contains("goodbye agents"), "unexpected edit result: {edited}");
    let found = call_text(
        &mut session,
        "search_regex",
        json!({"pattern": "goodbye\\s+agents"}),
    );
    assert!(found.contains("hello.txt"), "unexpected search result: {found}");
    let moved = workspace.path().join("moved.txt");
    call_text(
        &mut session,
        "move_file",
        json!({"path": path, "newPath": moved}),
    );
    assert!(!path.exists());
    assert!(moved.exists());
    let listing = call_text(&mut session, "list_files", json!({}));
    assert!(listing.contains("moved.txt"), "unexpected listing: {listing}");
    call_text(&mut session, "delete_file", json!({"path": moved}));
    assert!(!moved.exists());
    session.close();
}

#[test]
fn tools_call_reports_engine_errors_without_a_socket() {
    let workspace = temp_dir("agents-mcp-workspace");
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    let result = call(
        &mut session,
        "git_status",
        json!({"threadId": "missing-thread"}),
    );
    assert_eq!(result["isError"], true);
    let text = result["content"][0]["text"].as_str().unwrap();
    assert!(
        text.contains("control socket") || text.contains("Cannot reach"),
        "unexpected git error text: {text}"
    );
    session.close();
}

#[test]
fn unknown_tool_and_malformed_requests_return_jsonrpc_errors() {
    let workspace = temp_dir("agents-mcp-workspace");
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    let unknown = session.request("tools/call", json!({"name": "no_such_tool", "arguments": {}}));
    assert_eq!(unknown["error"]["code"], -32602);
    let unknown_method = session.request("nope/method", json!({}));
    assert_eq!(unknown_method["error"]["code"], -32601);
    session
        .stdin
        .write_all(b"{not valid json\n")
        .unwrap();
    session.stdin.flush().unwrap();
    let parse_error = session.read_response();
    assert_eq!(parse_error["error"]["code"], -32700);
    session.close();
}

#[test]
fn panicking_tool_call_returns_internal_error_and_the_server_survives() {
    let workspace = temp_dir("agents-mcp-workspace");
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    call(
        &mut session,
        "write_file",
        json!({"path": "Localizable.xcstrings", "content": "{\"strings\": 42}"}),
    );
    let panicked = session.request(
        "tools/call",
        json!({"name": "strings_localization", "arguments": {
            "path": "Localizable.xcstrings",
            "action": "set",
            "key": "greeting",
            "value": "Hello",
        }}),
    );
    assert_eq!(panicked["error"]["code"], -32603);
    assert_eq!(panicked["error"]["message"], "request handler panicked");
    let ping = session.request("ping", json!({}));
    assert!(
        ping.get("error").is_none(),
        "server did not survive the panic: {ping}"
    );
    assert_eq!(ping["result"], json!({}));
    session.close();
}

#[test]
fn resources_serve_real_asset_files() {
    let workspace = temp_dir("agents-mcp-workspace");
    let assets = asset_fixtures();
    let mut session = Session::spawn(workspace.path(), Some(assets.path()));
    initialize(&mut session);
    let list = session.request("resources/list", json!({}));
    let resources = list["result"]["resources"].as_array().unwrap();
    assert_eq!(resources.len(), 3);
    assert!(resources
        .iter()
        .any(|r| r["uri"] == "agents-asset://Safeguards.md"));
    let read = session.request(
        "resources/read",
        json!({"uri": "agents-asset://Identity.md"}),
    );
    assert!(read.get("error").is_none(), "resources/read failed: {read}");
    let text = read["result"]["contents"][0]["text"].as_str().unwrap();
    assert_eq!(text, "# Identity\n");
    let missing = session.request(
        "resources/read",
        json!({"uri": "agents-asset://Nope.md"}),
    );
    assert_eq!(missing["error"]["code"], -32602);
    let traversal = session.request(
        "resources/read",
        json!({"uri": "agents-asset://../secrets.md"}),
    );
    assert_eq!(traversal["error"]["code"], -32602);
    session.close();
}

const RETRIEVAL_ALPHA: &str = "# Alpha Guide\n\n## Getting Started\nAlpha tokens live here for the alpha walkthrough.\n\n## Advanced Alpha\nDeep alpha material.\n";
const RETRIEVAL_BETA: &str = "# Beta Guide\n\n## Getting Started\nBeta tokens live here for the beta walkthrough.\n\n## Advanced Beta\nDeep beta material.\n";
const RETRIEVAL_GAMMA: &str = "# Gamma Notes\n\n## Overview\nShared token appears in this body text.\n";

fn retrieval_fixtures() -> tempfile::TempDir {
    let dir = temp_dir("agents-mcp-retrieval");
    std::fs::write(dir.path().join("Safeguards.md"), "# Safeguards\n").unwrap();
    std::fs::write(dir.path().join("Identity.md"), "# Identity\n").unwrap();
    std::fs::write(dir.path().join("AlphaNotes.md"), RETRIEVAL_ALPHA).unwrap();
    std::fs::write(dir.path().join("BetaNotes.md"), RETRIEVAL_BETA).unwrap();
    std::fs::write(dir.path().join("Gamma Notes.md"), RETRIEVAL_GAMMA).unwrap();
    dir
}

fn search_skills(session: &mut Session, query: &str, limit: u64) -> Value {
    let text = call_text(
        session,
        "search_skills",
        json!({"query": query, "limit": limit}),
    );
    serde_json::from_str(&text).expect("search_skills result parses as JSON")
}

fn ranked(result: &Value) -> Vec<(String, String, String, i64, String, String, Vec<String>)> {
    result["results"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| {
            (
                entry["documentID"].as_str().unwrap().to_owned(),
                entry["fileName"].as_str().unwrap().to_owned(),
                entry["sectionHeading"].as_str().unwrap().to_owned(),
                entry["score"].as_i64().unwrap(),
                entry["reason"].as_str().unwrap().to_owned(),
                entry["text"].as_str().unwrap().to_owned(),
                entry["headingPath"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|part| part.as_str().unwrap().to_owned())
                    .collect(),
            )
        })
        .collect()
}

#[test]
fn search_skills_matches_canonical_ranking() {
    let workspace = temp_dir("agents-mcp-workspace");
    let assets = retrieval_fixtures();
    let mut session = Session::spawn(workspace.path(), Some(assets.path()));
    initialize(&mut session);
    let alpha = search_skills(&mut session, "alpha", 10);
    assert_eq!(alpha["documentCount"].as_u64().unwrap(), 5);
    assert_eq!(
        ranked(&alpha),
        vec![
            (
                "AlphaNotes".to_owned(),
                "AlphaNotes.md".to_owned(),
                "Advanced Alpha".to_owned(),
                72,
                "phrase".to_owned(),
                "Advanced Alpha\n\nDeep alpha material.".to_owned(),
                vec!["Alpha Guide".to_owned(), "Advanced Alpha".to_owned()],
            ),
            (
                "AlphaNotes".to_owned(),
                "AlphaNotes.md".to_owned(),
                "Getting Started".to_owned(),
                72,
                "phrase".to_owned(),
                "Getting Started\n\nAlpha tokens live here for the alpha walkthrough.".to_owned(),
                vec!["Alpha Guide".to_owned(), "Getting Started".to_owned()],
            ),
            (
                "AlphaNotes".to_owned(),
                "AlphaNotes.md".to_owned(),
                "Alpha Guide".to_owned(),
                71,
                "phrase".to_owned(),
                "Alpha Guide\n\n".to_owned(),
                vec!["Alpha Guide".to_owned()],
            ),
        ]
    );
    let guide = search_skills(&mut session, "guide", 10);
    assert_eq!(
        ranked(&guide),
        vec![
            (
                "AlphaNotes".to_owned(),
                "AlphaNotes.md".to_owned(),
                "Alpha Guide".to_owned(),
                71,
                "phrase".to_owned(),
                "Alpha Guide\n\n".to_owned(),
                vec!["Alpha Guide".to_owned()],
            ),
            (
                "BetaNotes".to_owned(),
                "BetaNotes.md".to_owned(),
                "Beta Guide".to_owned(),
                71,
                "phrase".to_owned(),
                "Beta Guide\n\n".to_owned(),
                vec!["Beta Guide".to_owned()],
            ),
            (
                "AlphaNotes".to_owned(),
                "AlphaNotes.md".to_owned(),
                "Advanced Alpha".to_owned(),
                5,
                "keyword".to_owned(),
                "Advanced Alpha\n\nDeep alpha material.".to_owned(),
                vec!["Alpha Guide".to_owned(), "Advanced Alpha".to_owned()],
            ),
            (
                "AlphaNotes".to_owned(),
                "AlphaNotes.md".to_owned(),
                "Getting Started".to_owned(),
                5,
                "keyword".to_owned(),
                "Getting Started\n\nAlpha tokens live here for the alpha walkthrough.".to_owned(),
                vec!["Alpha Guide".to_owned(), "Getting Started".to_owned()],
            ),
            (
                "BetaNotes".to_owned(),
                "BetaNotes.md".to_owned(),
                "Advanced Beta".to_owned(),
                5,
                "keyword".to_owned(),
                "Advanced Beta\n\nDeep beta material.".to_owned(),
                vec!["Beta Guide".to_owned(), "Advanced Beta".to_owned()],
            ),
            (
                "BetaNotes".to_owned(),
                "BetaNotes.md".to_owned(),
                "Getting Started".to_owned(),
                5,
                "keyword".to_owned(),
                "Getting Started\n\nBeta tokens live here for the beta walkthrough.".to_owned(),
                vec!["Beta Guide".to_owned(), "Getting Started".to_owned()],
            ),
        ]
    );
    let getting = search_skills(&mut session, "getting started", 10);
    assert_eq!(
        ranked(&getting),
        vec![
            (
                "AlphaNotes".to_owned(),
                "AlphaNotes.md".to_owned(),
                "Getting Started".to_owned(),
                80,
                "exactHeading".to_owned(),
                "Getting Started\n\nAlpha tokens live here for the alpha walkthrough.".to_owned(),
                vec!["Alpha Guide".to_owned(), "Getting Started".to_owned()],
            ),
            (
                "BetaNotes".to_owned(),
                "BetaNotes.md".to_owned(),
                "Getting Started".to_owned(),
                80,
                "exactHeading".to_owned(),
                "Getting Started\n\nBeta tokens live here for the beta walkthrough.".to_owned(),
                vec!["Beta Guide".to_owned(), "Getting Started".to_owned()],
            ),
        ]
    );
    session.close();
}


#[test]
fn search_skills_exact_document_id_returns_first_section() {
    let workspace = temp_dir("agents-mcp-workspace");
    let assets = retrieval_fixtures();
    let mut session = Session::spawn(workspace.path(), Some(assets.path()));
    initialize(&mut session);
    let exact = search_skills(&mut session, "alphanotes", 10);
    assert_eq!(
        ranked(&exact),
        vec![(
            "AlphaNotes".to_owned(),
            "AlphaNotes.md".to_owned(),
            "Alpha Guide".to_owned(),
            100,
            "exactFilename".to_owned(),
            "Alpha Guide\n\n".to_owned(),
            vec!["Alpha Guide".to_owned()],
        )]
    );
    session.close();
}

#[test]
fn search_skills_full_document_readable_outside_top_results() {
    let workspace = temp_dir("agents-mcp-workspace");
    let assets = retrieval_fixtures();
    let mut session = Session::spawn(workspace.path(), Some(assets.path()));
    initialize(&mut session);
    let top = search_skills(&mut session, "alpha", 1);
    let results = top["results"].as_array().unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["fileName"].as_str().unwrap(), "AlphaNotes.md");
    assert_eq!(
        results[0]["resourceUri"].as_str().unwrap(),
        "agents-asset://AlphaNotes.md"
    );
    assert!(results.iter().all(|entry| entry["fileName"] != "BetaNotes.md"));
    let read = session.request(
        "resources/read",
        json!({"uri": "agents-asset://BetaNotes.md"}),
    );
    assert!(read.get("error").is_none(), "resources/read failed: {read}");
    let text = read["result"]["contents"][0]["text"].as_str().unwrap();
    assert_eq!(text, RETRIEVAL_BETA);
    session.close();
}

const ASSET_ALPHA: &str = "<!-- system-index-category: Guides -->\n<!-- system-index-tags: alpha, walkthrough -->\n<!-- system-index-depends: Beta.md -->\n# Alpha Guide\n\n## Getting Started\nAlpha tokens live here for the alpha walkthrough.\n\n## Advanced Alpha\nDeep alpha material.\n";
const ASSET_BETA: &str = "# Beta Guide\n\n## Getting Started\nBeta tokens live here for the beta walkthrough.\n";

fn asset_tool_fixtures() -> tempfile::TempDir {
    let dir = temp_dir("agents-mcp-asset-tools");
    std::fs::write(dir.path().join("Safeguards.md"), "# Safeguards\n").unwrap();
    std::fs::write(dir.path().join("Identity.md"), "# Identity\n").unwrap();
    std::fs::write(dir.path().join("Alpha.md"), ASSET_ALPHA).unwrap();
    std::fs::write(dir.path().join("Beta.md"), ASSET_BETA).unwrap();
    std::fs::write(dir.path().join("Hash.md"), "abc").unwrap();
    std::fs::write(dir.path().join("Gamma Notes.md"), RETRIEVAL_GAMMA).unwrap();
    dir
}

fn asset_tool(session: &mut Session, name: &str, arguments: Value) -> Value {
    let text = call_text(session, name, arguments);
    serde_json::from_str(&text).expect("asset tool result parses as JSON")
}

fn sorted_keys(value: &Value) -> Vec<&str> {
    let mut keys: Vec<&str> = value
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect();
    keys.sort_unstable();
    keys
}

#[test]
fn system_asset_tools_read_list_metadata_and_related() {
    let workspace = temp_dir("agents-mcp-workspace");
    let assets = asset_tool_fixtures();
    let mut session = Session::spawn(workspace.path(), Some(assets.path()));
    initialize(&mut session);
    let read = asset_tool(
        &mut session,
        "system_asset_read",
        json!({"fileName": "Alpha.md"}),
    );
    assert_eq!(read["documentID"], "Alpha");
    assert_eq!(read["title"], "Alpha Guide");
    assert_eq!(read["category"], "Guides");
    assert_eq!(read["sectionHeading"], "Alpha Guide");
    assert_eq!(read["text"], ASSET_ALPHA);
    assert_eq!(read["truncated"], false);
    assert_eq!(
        read["characterCount"],
        ASSET_ALPHA.chars().count() as u64
    );
    assert_eq!(read["resourceUri"], "agents-asset://Alpha.md");
    assert_eq!(
        sorted_keys(&read),
        vec![
            "category",
            "characterCount",
            "documentID",
            "fileName",
            "headingPath",
            "resourceUri",
            "sectionHeading",
            "text",
            "title",
            "truncated"
        ]
    );
    let section = asset_tool(
        &mut session,
        "system_asset_read",
        json!({"fileName": "Alpha.md", "section": "getting started"}),
    );
    assert_eq!(section["sectionHeading"], "Getting Started");
    assert_eq!(
        section["headingPath"],
        json!(["Alpha Guide", "Getting Started"])
    );
    assert_eq!(
        section["text"],
        "Getting Started\n\nAlpha tokens live here for the alpha walkthrough."
    );
    let clipped = asset_tool(
        &mut session,
        "system_asset_read",
        json!({"fileName": "Alpha.md", "maxChars": 10}),
    );
    assert_eq!(clipped["text"].as_str().unwrap().chars().count(), 10);
    assert_eq!(clipped["truncated"], true);
    let list = asset_tool(&mut session, "system_asset_list", json!({}));
    assert_eq!(list["totalCount"], 6);
    assert_eq!(list["returnedCount"], 6);
    let names: Vec<&str> = list["documents"]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| entry["fileName"].as_str().unwrap())
        .collect();
    assert_eq!(
        names,
        vec![
            "Alpha.md",
            "Beta.md",
            "Gamma Notes.md",
            "Hash.md",
            "Identity.md",
            "Safeguards.md"
        ]
    );
    assert_eq!(
        sorted_keys(&list),
        vec![
            "category",
            "documents",
            "limit",
            "offset",
            "returnedCount",
            "tag",
            "totalCount"
        ]
    );
    assert_eq!(
        sorted_keys(&list["documents"][0]),
        vec![
            "category",
            "documentID",
            "fileName",
            "resourceUri",
            "tags",
            "title"
        ]
    );
    let guides = asset_tool(
        &mut session,
        "system_asset_list",
        json!({"category": "GUIDES"}),
    );
    assert_eq!(guides["totalCount"], 1);
    assert_eq!(guides["documents"][0]["fileName"], "Alpha.md");
    let tagged = asset_tool(
        &mut session,
        "system_asset_list",
        json!({"tag": "walkthrough"}),
    );
    assert_eq!(tagged["totalCount"], 1);
    let page = asset_tool(
        &mut session,
        "system_asset_list",
        json!({"limit": 2, "offset": 2}),
    );
    assert_eq!(page["totalCount"], 6);
    assert_eq!(page["returnedCount"], 2);
    assert_eq!(page["documents"][0]["fileName"], "Gamma Notes.md");
    assert_eq!(page["documents"][1]["fileName"], "Hash.md");
    let metadata = asset_tool(
        &mut session,
        "system_asset_get_metadata",
        json!({"fileName": "Alpha.md"}),
    );
    assert_eq!(metadata["documentID"], "Alpha");
    assert_eq!(metadata["relativePath"], "Alpha.md");
    assert_eq!(metadata["category"], "Guides");
    assert_eq!(metadata["tags"], json!(["alpha", "walkthrough"]));
    assert_eq!(metadata["dependencies"], json!(["Beta.md"]));
    assert_eq!(metadata["dependents"], json!([]));
    assert_eq!(metadata["sectionCount"], 3);
    assert!(metadata["estimatedTokens"].as_i64().unwrap() > 0);
    assert_eq!(
        metadata["characterCount"],
        ASSET_ALPHA.chars().count() as u64
    );
    assert_eq!(metadata["byteCount"], ASSET_ALPHA.len() as u64);
    assert_eq!(metadata["contentHash"].as_str().unwrap().len(), 64);
    assert_eq!(
        sorted_keys(&metadata),
        vec![
            "byteCount",
            "category",
            "characterCount",
            "contentHash",
            "dependencies",
            "dependents",
            "documentID",
            "estimatedTokens",
            "fileName",
            "relativePath",
            "resourceUri",
            "sectionCount",
            "tags",
            "title"
        ]
    );
    let hash = asset_tool(
        &mut session,
        "system_asset_get_metadata",
        json!({"fileName": "Hash.md"}),
    );
    assert_eq!(
        hash["contentHash"],
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
    let related = asset_tool(
        &mut session,
        "system_asset_search_related",
        json!({"fileName": "Alpha.md"}),
    );
    assert_eq!(related["relatedCount"], 1);
    assert_eq!(related["related"][0]["fileName"], "Beta.md");
    assert_eq!(related["related"][0]["relation"], "dependency");
    assert_eq!(
        sorted_keys(&related),
        vec!["documentID", "fileName", "related", "relatedCount", "title"]
    );
    assert_eq!(
        sorted_keys(&related["related"][0]),
        vec![
            "category",
            "documentID",
            "fileName",
            "relation",
            "resourceUri",
            "title"
        ]
    );
    let reverse = asset_tool(
        &mut session,
        "system_asset_search_related",
        json!({"fileName": "Beta.md"}),
    );
    assert_eq!(reverse["relatedCount"], 1);
    assert_eq!(reverse["related"][0]["fileName"], "Alpha.md");
    assert_eq!(reverse["related"][0]["relation"], "dependent");
    let beta_meta = asset_tool(
        &mut session,
        "system_asset_get_metadata",
        json!({"fileName": "Beta.md"}),
    );
    assert_eq!(beta_meta["dependents"], json!(["Alpha.md"]));
    assert_eq!(beta_meta["category"], "General");
    let missing = session.request(
        "tools/call",
        json!({"name": "system_asset_read", "arguments": {"fileName": "Nope.md"}}),
    );
    assert!(
        missing.get("error").is_none(),
        "unknown asset must not be a protocol error: {missing}"
    );
    assert_eq!(missing["result"]["isError"], true);
    assert!(missing["result"]["content"][0]["text"]
        .as_str()
        .unwrap()
        .contains("unknown SystemAsset"));
    session.close();
}

#[test]
fn prompts_get_errors_honestly_without_a_stored_prompt() {
    let workspace = temp_dir("agents-mcp-workspace");
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    let list = session.request("prompts/list", json!({}));
    let prompts = list["result"]["prompts"].as_array().unwrap();
    assert_eq!(prompts.len(), 1);
    assert_eq!(prompts[0]["name"], "agents-system-prompt");
    let get = session.request(
        "prompts/get",
        json!({"name": "agents-system-prompt"}),
    );
    assert_eq!(get["error"]["code"], -32602);
    session.close();
}

#[test]
fn oversized_invalid_utf8_and_non_object_frames_get_errors_and_the_server_survives() {
    let workspace = temp_dir("agents-mcp-workspace");
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    let oversized = "x".repeat(17 * 1024 * 1024);
    session.stdin.write_all(oversized.as_bytes()).unwrap();
    session.stdin.write_all(b"\n").unwrap();
    session.stdin.flush().unwrap();
    let rejected = session.read_response();
    assert_eq!(rejected["error"]["code"], -32700);
    session.stdin.write_all(b"[1, 2, 3]\n").unwrap();
    session.stdin.flush().unwrap();
    let invalid = session.read_response();
    assert_eq!(invalid["error"]["code"], -32600);
    session.stdin.write_all(b"\xff\xfe\n").unwrap();
    session.stdin.flush().unwrap();
    let bad_utf8 = session.read_response();
    assert_eq!(bad_utf8["error"]["code"], -32700);
    let ping = session.request("ping", json!({}));
    assert!(ping.get("error").is_none(), "ping failed after bad frames: {ping}");
    session.close();
}

#[test]
fn stdin_eof_exits_cleanly() {
    let workspace = temp_dir("agents-mcp-workspace");
    let session = Session::spawn(workspace.path(), None);
    session.close();
}

#[test]
fn notifications_produce_no_response() {
    let workspace = temp_dir("agents-mcp-workspace");
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    session
        .stdin
        .write_all(b"{\"jsonrpc\": \"2.0\"}\n")
        .unwrap();
    session.stdin.flush().unwrap();
    session.notify("nope/method");
    let ping = session.request("ping", json!({}));
    assert!(ping.get("error").is_none(), "ping failed: {ping}");
    session.close();
}

#[test]
fn use_mcp_rejects_non_string_arguments() {
    let workspace = temp_dir("agents-mcp-workspace");
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    let result = call(
        &mut session,
        "use_mcp",
        json!({"serverName": "coincide", "toolName": "read_file", "arguments": {"path": "x"}}),
    );
    assert_eq!(result["isError"], true);
    let text = result["content"][0]["text"].as_str().unwrap();
    assert!(text.contains("JSON object string"), "unexpected use_mcp error: {text}");
    session.close();
}

#[test]
fn derived_data_locate_survives_a_symlink_cycle() {
    let workspace = temp_dir("agents-mcp-workspace");
    let root = workspace.path().join("derived");
    std::fs::create_dir_all(root.join("child")).unwrap();
    std::os::unix::fs::symlink(root.clone(), root.join("child").join("loop")).unwrap();
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    let result = call(
        &mut session,
        "derived_data_locate",
        json!({"path": root.to_string_lossy()}),
    );
    assert_eq!(result["isError"], false, "symlink cycle broke derived_data_locate: {result}");
    session.close();
}

#[test]
fn resources_ignore_symlinked_asset_files() {
    let workspace = temp_dir("agents-mcp-workspace");
    let assets = asset_fixtures();
    let outside = workspace.path().join("outside.md");
    std::fs::write(&outside, "# Outside\n").unwrap();
    std::os::unix::fs::symlink(&outside, assets.path().join("Evil.md")).unwrap();
    let mut session = Session::spawn(workspace.path(), Some(assets.path()));
    initialize(&mut session);
    let list = session.request("resources/list", json!({}));
    let resources = list["result"]["resources"].as_array().unwrap();
    assert_eq!(resources.len(), 3);
    assert!(resources
        .iter()
        .all(|r| r["uri"] != "agents-asset://Evil.md"));
    let read = session.request(
        "resources/read",
        json!({"uri": "agents-asset://Evil.md"}),
    );
    assert_eq!(read["error"]["code"], -32602);
    session.close();
}

#[test]
fn derived_data_locate_flags_deep_tree_truncation() {
    let workspace = temp_dir("agents-mcp-workspace");
    let root = workspace.path().join("derived");
    let mut deep = root.join("Deep");
    std::fs::create_dir_all(&deep).unwrap();
    for level in 0..40 {
        deep = deep.join(format!("d{level}"));
        std::fs::create_dir(&deep).unwrap();
    }
    std::fs::write(deep.join("leaf.txt"), "leaf").unwrap();
    let shallow = root.join("Shallow");
    std::fs::create_dir_all(&shallow).unwrap();
    std::fs::write(shallow.join("top.txt"), "top").unwrap();
    let mut session = Session::spawn(workspace.path(), None);
    initialize(&mut session);
    let result = call(
        &mut session,
        "derived_data_locate",
        json!({"path": root.to_string_lossy()}),
    );
    assert_eq!(result["isError"], false, "derived_data_locate failed: {result}");
    let text = result["content"][0]["text"].as_str().unwrap();
    let parsed: Value = serde_json::from_str(text).unwrap();
    assert_eq!(parsed["truncated"], true, "deep tree not flagged: {text}");
    let directories = parsed["directories"].as_array().unwrap();
    let deep_entry = directories
        .iter()
        .find(|entry| entry["name"] == "Deep")
        .expect("Deep directory missing");
    assert_eq!(deep_entry["truncated"], true, "Deep entry not flagged: {text}");
    let shallow_entry = directories
        .iter()
        .find(|entry| entry["name"] == "Shallow")
        .expect("Shallow directory missing");
    assert_eq!(
        shallow_entry["truncated"], false,
        "Shallow entry wrongly flagged: {text}"
    );
    assert_eq!(shallow_entry["bytes"], 3);
    assert_eq!(shallow_entry["files"], 1);
    session.close();
}

#[test]
fn resources_read_rejects_an_asset_over_the_size_limit() {
    let workspace = temp_dir("agents-mcp-workspace");
    let assets = asset_fixtures();
    let huge = vec![b'a'; 16 * 1024 * 1024 + 1];
    std::fs::write(assets.path().join("Huge.md"), &huge).unwrap();
    let mut session = Session::spawn(workspace.path(), Some(assets.path()));
    initialize(&mut session);
    let read = session.request(
        "resources/read",
        json!({"uri": "agents-asset://Huge.md"}),
    );
    assert_eq!(read["error"]["code"], -32602);
    let message = read["error"]["message"].as_str().unwrap();
    assert!(
        message.contains("exceeds the 16 MiB limit"),
        "unexpected oversize error: {message}"
    );
    session.close();
}

fn spawn_with_thread(
    workspace: &std::path::Path,
    assets: Option<&std::path::Path>,
    thread_id: &str,
    socket: &std::path::Path,
) -> Session {
    let exe = env!("CARGO_BIN_EXE_coincide-mcp-server");
    let mut command = Command::new(exe);
    command
        .arg("--cwd")
        .arg(workspace)
        .arg("--thread-id")
        .arg(thread_id)
        .arg("--socket")
        .arg(socket);
    if let Some(dir) = assets {
        command.arg("--assets-dir").arg(dir);
    }
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn coincide-mcp-server");
    let stdin = child.stdin.take().expect("server stdin");
    let stdout = child.stdout.take().expect("server stdout");
    Session {
        child,
        stdin,
        reader: BufReader::new(stdout),
    }
}

#[test]
fn trust_boundary_any_local_stdio_client_reads_full_asset_text() {
    let workspace = temp_dir("agents-mcp-workspace");
    let assets = asset_fixtures();
    let mut session = Session::spawn(workspace.path(), Some(assets.path()));
    initialize(&mut session);
    let read = session.request(
        "resources/read",
        json!({"uri": "agents-asset://Safeguards.md"}),
    );
    assert!(read.get("error").is_none(), "resources/read failed: {read}");
    let text = read["result"]["contents"][0]["text"].as_str().unwrap();
    assert_eq!(text, "# Safeguards\n");
    session.close();
}

#[test]
fn trust_boundary_listing_exposes_names_only() {
    let workspace = temp_dir("agents-mcp-workspace");
    let assets = asset_fixtures();
    let mut session = Session::spawn(workspace.path(), Some(assets.path()));
    initialize(&mut session);
    let list = session.request("resources/list", json!({}));
    let resources = list["result"]["resources"].as_array().unwrap();
    assert_eq!(resources.len(), 3);
    for resource in resources {
        let mut keys: Vec<&str> = resource
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect();
        keys.sort();
        assert_eq!(keys, ["mimeType", "name", "uri"]);
        assert!(resource.get("text").is_none());
    }
    let prompts = session.request("prompts/list", json!({}));
    let entries = prompts["result"]["prompts"].as_array().unwrap();
    assert_eq!(entries.len(), 1);
    let mut keys: Vec<&str> = entries[0]
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect();
    keys.sort();
    assert_eq!(keys, ["arguments", "description", "name"]);
    assert!(entries[0].get("messages").is_none());
    assert!(entries[0].get("text").is_none());
    session.close();
}

#[test]
fn trust_boundary_prompts_get_returns_full_stored_prompt_to_any_stdio_client() {
    use std::os::unix::net::UnixListener;
    let workspace = temp_dir("agents-mcp-workspace");
    let socket_path = workspace.path().join("control.sock");
    let listener = UnixListener::bind(&socket_path).unwrap();
    let stored = "You are the test agent. Follow the test safeguards.";
    let reply = serde_json::to_string(&json!({
        "result": {"systemPrompt": stored},
    }))
    .unwrap();
    let served = std::thread::spawn(move || {
        listener.set_nonblocking(true).unwrap();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
        loop {
            match listener.accept() {
                Ok((mut stream, _)) => {
                    stream.set_nonblocking(false).unwrap();
                    let mut request = String::new();
                    let mut reader = BufReader::new(stream.try_clone().unwrap());
                    reader.read_line(&mut request).unwrap();
                    assert!(request.contains("threads.read"));
                    stream.write_all(reply.as_bytes()).unwrap();
                    stream.write_all(b"\n").unwrap();
                    stream.flush().unwrap();
                    return;
                }
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    if std::time::Instant::now() > deadline {
                        panic!("control socket was never contacted");
                    }
                    std::thread::sleep(std::time::Duration::from_millis(10));
                }
                Err(error) => panic!("control accept failed: {error}"),
            }
        }
    });
    let mut session = spawn_with_thread(workspace.path(), None, "thread-1", &socket_path);
    initialize(&mut session);
    let get = session.request(
        "prompts/get",
        json!({"name": "agents-system-prompt"}),
    );
    assert!(get.get("error").is_none(), "prompts/get failed: {get}");
    let text = get["result"]["messages"][0]["content"]["text"]
        .as_str()
        .unwrap();
    assert_eq!(text, stored);
    session.close();
    served.join().unwrap();
}
