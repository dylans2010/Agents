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
    assert_eq!(tools.len(), 41);
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
        "intel_plan_task",
        "intel_breakdown_task",
        "execution_plan",
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
fn stdin_eof_exits_cleanly() {
    let workspace = temp_dir("agents-mcp-workspace");
    let session = Session::spawn(workspace.path(), None);
    session.close();
}
