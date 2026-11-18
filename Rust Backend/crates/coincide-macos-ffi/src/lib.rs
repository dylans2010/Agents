//! C-ABI staticlib FFI bridge exposing `coincide-core` to the native macOS
//! SwiftUI + AppKit application.
mod adapter_bridge;
mod discovery;
mod providers;
mod workspace_ops;

use anyhow::{Context, Result, ensure};
use coincide_core::{
    api::{Engine, SharedEngine, ThreadDeletionUndo},
    control,
    native_ui_edits::NativeUiEditors,
    remote::{adapter::Adapter, server::RemoteServer},
    store::Store,
};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    ffi::{CStr, CString, c_char},
    fs,
    io::{BufRead, BufReader, Read, Write},
    os::unix::{
        fs::{MetadataExt, PermissionsExt},
        net::UnixStream,
    },
    panic::{AssertUnwindSafe, catch_unwind},
    path::{Path, PathBuf},
    ptr,
    sync::{
        Arc, Mutex, TryLockError,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

pub struct CoincideMacOSRuntime {
    pub(crate) data_dir: PathBuf,
    pub(crate) app_version: String,
    pub(crate) engine: SharedEngine,
    pub(crate) _native_editors: NativeUiEditors,
    pub(crate) control: Mutex<Option<control::Server>>,
    pub(crate) adapter: Adapter,
    pub(crate) remote: Mutex<RemoteServer>,
    pub(crate) thread_delete_undos:
        Mutex<HashMap<String, Arc<Mutex<Option<ThreadDeletionUndo>>>>>,
    pub(crate) instruction_baselines: Mutex<HashMap<PathBuf, Vec<u8>>>,
    pub(crate) closing: AtomicBool,
}

fn cstr_optional(ptr: *const c_char) -> Result<Option<String>> {
    if ptr.is_null() {
        return Ok(None);
    }
    // SAFETY: Caller passes a valid NUL-terminated C string or null.
    let text = unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .context("C string parameter is not valid UTF-8")?
        .trim();
    if text.is_empty() {
        Ok(None)
    } else {
        Ok(Some(text.to_owned()))
    }
}

fn cstr_required(ptr: *const c_char, name: &str) -> Result<String> {
    ensure!(!ptr.is_null(), "Required C string '{name}' is null");
    // SAFETY: Caller passes a valid NUL-terminated C string.
    let text = unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .with_context(|| format!("C string '{name}' is not valid UTF-8"))?;
    Ok(text.to_owned())
}

fn to_c_string_ptr(text: String) -> *mut c_char {
    let sanitized = if text.contains('\0') {
        text.replace('\0', "")
    } else {
        text
    };
    match CString::new(sanitized) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => CString::new("{\"ok\":false,\"error\":\"Invalid CString\"}")
            .expect("static JSON")
            .into_raw(),
    }
}

fn json_c_string_ptr(value: &Value) -> *mut c_char {
    let serialized = serde_json::to_string(value)
        .unwrap_or_else(|e| format!("{{\"ok\":false,\"error\":\"Serialization failed: {e}\"}}"));
    to_c_string_ptr(serialized)
}

fn resolve_data_dir(nullable_data_dir: *const c_char) -> Result<PathBuf> {
    match cstr_optional(nullable_data_dir)? {
        Some(custom) => {
            if let Some(rest) = custom.strip_prefix("~/") {
                let home = discovery::home_dir().context("HOME is missing")?;
                Ok(home.join(rest))
            } else {
                Ok(PathBuf::from(custom))
            }
        }
        None => control::data_directory(),
    }
}

fn ensure_private_data_dir(path: &Path) -> Result<()> {
    ensure!(path.is_absolute(), "Data directory path must be absolute");
    let existed = path.exists();
    if !existed {
        fs::create_dir_all(path)
            .with_context(|| format!("Failed to create data directory {}", path.display()))?;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    } else {
        let meta = fs::symlink_metadata(path)?;
        ensure!(
            meta.is_dir() && !meta.file_type().is_symlink(),
            "Data directory must be a regular directory, not a symlink"
        );
        if meta.uid() == unsafe { libc::geteuid() } && (meta.permissions().mode() & 0o077 != 0) {
            fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
        }
    }
    Ok(())
}

fn panic_message(payload: Box<dyn std::any::Any + Send>) -> String {
    if let Some(s) = payload.downcast_ref::<&str>() {
        format!("FFI panic: {s}")
    } else if let Some(s) = payload.downcast_ref::<String>() {
        format!("FFI panic: {s}")
    } else {
        "FFI panic: unknown payload".to_owned()
    }
}

fn open_runtime_inner(
    nullable_data_dir: *const c_char,
    app_version: *const c_char,
) -> Result<Box<CoincideMacOSRuntime>> {
    let data_dir = resolve_data_dir(nullable_data_dir)?;
    ensure_private_data_dir(&data_dir)?;
    let version = cstr_optional(app_version)?.unwrap_or_else(|| env!("CARGO_PKG_VERSION").into());

    let store = Store::open(&data_dir.join("coincide.sqlite"))?;
    let engine = Engine::new(store);
    let native_editors = engine.native_ui_editors();
    let engine = Arc::new(Mutex::new(engine));

    let control_server = control::serve(data_dir.join("control.sock"), engine.clone())?;
    let adapter = Adapter::new(engine.clone(), version.clone());
    let mut remote = RemoteServer::new(data_dir.clone(), engine.clone(), version.clone());
    remote.start_if_enabled();

    Ok(Box::new(CoincideMacOSRuntime {
        data_dir,
        app_version: version,
        engine,
        _native_editors: native_editors,
        control: Mutex::new(Some(control_server)),
        adapter,
        remote: Mutex::new(remote),
        thread_delete_undos: Mutex::new(HashMap::new()),
        instruction_baselines: Mutex::new(HashMap::new()),
        closing: AtomicBool::new(false),
    }))
}

fn poll_status_inner(runtime: &CoincideMacOSRuntime) -> Value {
    if runtime.closing.load(Ordering::Acquire) {
        return json!({ "busy": true, "closing": true });
    }
    let mut engine = match runtime.engine.try_lock() {
        Ok(guard) => guard,
        Err(TryLockError::WouldBlock) => return json!({ "busy": true }),
        Err(TryLockError::Poisoned(_)) => {
            return json!({ "ok": false, "error": "Engine lock poisoned" });
        }
    };

    let status_resp = engine.dispatch_desktop(json!({
        "method": "app.status",
        "params": {},
    }));
    if let Some(err) = status_resp.get("error") {
        return json!({
            "ok": false,
            "error": err["message"].as_str().unwrap_or("Status poll failed"),
        });
    }
    let mut status = status_resp["result"].clone();

    // Count pending approvals & pending questions across running threads
    let mut approvals_count = 0usize;
    let mut questions_count = 0usize;
    let mut pending_questions_by_thread = serde_json::Map::new();

    if let Some(map) = status["pendingApprovals"].as_object() {
        approvals_count = map
            .values()
            .filter_map(Value::as_u64)
            .map(|c| c as usize)
            .sum();
    }

    let running_ids: Vec<String> = status["running"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|v| v.as_str().map(str::to_owned))
        .collect();

    for tid in running_ids {
        let pending_resp = engine.dispatch_desktop(json!({
            "method": "agent.pending",
            "params": { "threadId": tid },
        }));
        if let Some(arr) = pending_resp["result"].as_array() {
            let q_count = arr
                .iter()
                .filter(|req| req["method"].as_str() == Some("item/tool/requestUserInput"))
                .count();
            if q_count > 0 {
                questions_count += q_count;
                pending_questions_by_thread.insert(tid, json!(q_count));
            }
        }
    }

    let activation_requested = std::mem::replace(&mut engine.activation_requested, false);
    let requested_open = engine.requested_open.take();
    let shutdown_requested = engine.shutdown;
    drop(engine);

    let legacy_available = discovery::legacy_import_available(&runtime.data_dir);
    let antigravity_bin = discovery::primary_antigravity_binary(&runtime.data_dir);

    if let Some(obj) = status.as_object_mut() {
        obj.insert("ok".into(), json!(true));
        obj.insert("busy".into(), json!(false));
        obj.insert("appVersion".into(), json!(runtime.app_version));
        obj.insert("pendingApprovalsCount".into(), json!(approvals_count));
        obj.insert("pendingQuestionsCount".into(), json!(questions_count));
        obj.insert(
            "pendingRequestsCount".into(),
            json!(approvals_count + questions_count),
        );
        obj.insert(
            "pendingQuestions".into(),
            Value::Object(pending_questions_by_thread),
        );
        obj.insert("activationRequested".into(), json!(activation_requested));
        obj.insert("requestedOpen".into(), json!(requested_open));
        obj.insert("shutdownRequested".into(), json!(shutdown_requested));
        obj.insert("legacyImportAvailable".into(), json!(legacy_available));
        obj.insert("legacyAntigravityBinary".into(), json!(antigravity_bin));
    }

    status
}

fn close_runtime_inner(runtime: Box<CoincideMacOSRuntime>) {
    runtime.closing.store(true, Ordering::Release);

    // 1. Stop RemoteServer cleanly off the Engine lock.
    if let Ok(mut remote) = runtime.remote.lock() {
        remote.stop();
    }

    // 2. Release retained Undo tokens so SQLite temp tables can be discarded.
    if let Ok(mut undos) = runtime.thread_delete_undos.lock() {
        undos.clear();
    }

    // 3. Request core shutdown (freezes admissions, requests stop on running turns,
    //    terminals, model catalog, background jobs, GitHub readers, and idle sleep).
    if let Ok(mut engine) = runtime.engine.lock() {
        let _ = engine.request_core_owner_shutdown();
    }

    // 4. Poll core owner shutdown off-lock until Rust workers drain (bounded).
    let drain_deadline = Instant::now() + Duration::from_secs(6);
    loop {
        let drained = match runtime.engine.lock() {
            Ok(mut engine) => engine
                .poll_core_owner_shutdown()
                .map(|s| s.rust_owners_drained())
                .unwrap_or(true),
            Err(_) => true,
        };
        if drained || Instant::now() >= drain_deadline {
            break;
        }
        std::thread::sleep(Duration::from_millis(15));
    }

    // 5. Stop and join `control::Server` off the Engine lock so its poll loop exits cleanly.
    if let Ok(mut slot) = runtime.control.lock()
        && let Some(server) = slot.take()
    {
        server.request_stop();
        drop(server);
    }

    // 6. Final poll + close SQLite database cleanly.
    if let Ok(mut engine) = runtime.engine.lock() {
        let _ = engine.poll_core_owner_shutdown();
        let _ = engine.close_store_after_core_shutdown();
    }
}

// MARK: - Extern "C" Entry Points

#[unsafe(no_mangle)]
pub unsafe extern "C" fn coincide_macos_adopt_login_path() {
    let _ = catch_unwind(|| {
        discovery::adopt_login_shell_path();
    });
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn coincide_macos_handoff_if_running(
    nullable_data_dir: *const c_char,
) -> bool {
    catch_unwind(AssertUnwindSafe(|| -> bool {
        let Ok(data_dir) = resolve_data_dir(nullable_data_dir) else {
            return false;
        };
        let socket = data_dir.join("control.sock");
        if !socket.exists() {
            return false;
        }
        let Ok(mut stream) = UnixStream::connect(&socket) else {
            return false;
        };
        let _ = stream.set_read_timeout(Some(Duration::from_millis(1500)));
        let _ = stream.set_write_timeout(Some(Duration::from_millis(1500)));
        if stream
            .write_all(b"{\"id\":1,\"method\":\"app.activate\",\"params\":{}}\n")
            .is_err()
        {
            return false;
        }
        let _ = stream.flush();
        let mut reply = Vec::new();
        let n = BufReader::new(stream.take(64 * 1024))
            .read_until(b'\n', &mut reply)
            .unwrap_or(0);
        n > 0 && serde_json::from_slice::<Value>(&reply).is_ok()
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn coincide_macos_open(
    nullable_data_dir: *const c_char,
    app_version: *const c_char,
    out_error: *mut *mut c_char,
) -> *mut CoincideMacOSRuntime {
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        if !out_error.is_null() {
            unsafe { *out_error = ptr::null_mut() };
        }
        match open_runtime_inner(nullable_data_dir, app_version) {
            Ok(runtime) => Box::into_raw(runtime),
            Err(error) => {
                if !out_error.is_null() {
                    unsafe { *out_error = to_c_string_ptr(format!("{error:#}")) };
                }
                ptr::null_mut()
            }
        }
    }));

    match outcome {
        Ok(ptr) => ptr,
        Err(panic_payload) => {
            if !out_error.is_null() {
                unsafe { *out_error = to_c_string_ptr(panic_message(panic_payload)) };
            }
            ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn coincide_macos_poll_status(
    runtime: *mut CoincideMacOSRuntime,
) -> *mut c_char {
    match catch_unwind(AssertUnwindSafe(|| {
        if runtime.is_null() {
            return json_c_string_ptr(&json!({ "ok": false, "error": "Runtime pointer is null" }));
        }
        let runtime_ref = unsafe { &*runtime };
        json_c_string_ptr(&poll_status_inner(runtime_ref))
    })) {
        Ok(ptr) => ptr,
        Err(payload) => json_c_string_ptr(&json!({
            "ok": false,
            "error": panic_message(payload),
        })),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn coincide_macos_adapter_call(
    runtime: *mut CoincideMacOSRuntime,
    request_json: *const c_char,
) -> *mut c_char {
    match catch_unwind(AssertUnwindSafe(|| {
        if runtime.is_null() {
            return json_c_string_ptr(&json!({
                "ok": false,
                "error": { "code": "failed", "message": "Runtime pointer is null." }
            }));
        }
        let raw = match cstr_required(request_json, "request_json") {
            Ok(s) => s,
            Err(err) => {
                return json_c_string_ptr(&json!({
                    "ok": false,
                    "error": { "code": "badRequest", "message": err.to_string() }
                }));
            }
        };
        let runtime_ref = unsafe { &*runtime };
        let result = adapter_bridge::dispatch_adapter_call(runtime_ref, &raw);
        json_c_string_ptr(&result)
    })) {
        Ok(ptr) => ptr,
        Err(payload) => json_c_string_ptr(&json!({
            "ok": false,
            "error": { "code": "failed", "message": panic_message(payload) }
        })),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn coincide_macos_desktop_call(
    runtime: *mut CoincideMacOSRuntime,
    action_json: *const c_char,
) -> *mut c_char {
    match catch_unwind(AssertUnwindSafe(|| {
        if runtime.is_null() {
            return json_c_string_ptr(&json!({
                "ok": false,
                "error": "Runtime pointer is null",
            }));
        }
        let raw = match cstr_required(action_json, "action_json") {
            Ok(s) => s,
            Err(err) => {
                return json_c_string_ptr(&json!({
                    "ok": false,
                    "error": err.to_string(),
                }));
            }
        };
        let runtime_ref = unsafe { &*runtime };
        match workspace_ops::dispatch_desktop_action(runtime_ref, &raw) {
            Ok(result) => json_c_string_ptr(&json!({
                "ok": true,
                "result": result,
            })),
            Err(error) => json_c_string_ptr(&json!({
                "ok": false,
                "error": format!("{error:#}"),
            })),
        }
    })) {
        Ok(ptr) => ptr,
        Err(payload) => json_c_string_ptr(&json!({
            "ok": false,
            "error": panic_message(payload),
        })),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn coincide_macos_close(runtime: *mut CoincideMacOSRuntime) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if runtime.is_null() {
            return;
        }
        let boxed = unsafe { Box::from_raw(runtime) };
        close_runtime_inner(boxed);
    }));
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn coincide_macos_string_free(ptr: *mut c_char) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !ptr.is_null() {
            unsafe { drop(CString::from_raw(ptr)) };
        }
    }));
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    unsafe fn take_json(ptr: *mut c_char) -> Value {
        assert!(!ptr.is_null(), "Expected non-null JSON string pointer");
        let text = unsafe { CStr::from_ptr(ptr) }
            .to_str()
            .expect("valid UTF-8 JSON")
            .to_owned();
        unsafe { coincide_macos_string_free(ptr) };
        serde_json::from_str(&text).unwrap_or_else(|e| panic!("Invalid JSON ({e}): {text}"))
    }

    #[test]
    fn full_ffi_lifecycle_open_poll_adapter_desktop_terminal_remote_and_close() {
        let dir = tempfile::tempdir().unwrap();
        let data_dir = dir.path().join("coincide-data");
        let data_cstr = CString::new(data_dir.to_str().unwrap()).unwrap();
        let ver_cstr = CString::new("0.9.0-test").unwrap();

        // 1. Before opening, handoff returns false.
        assert!(!unsafe { coincide_macos_handoff_if_running(data_cstr.as_ptr()) });

        // 2. Open runtime.
        let mut out_err: *mut c_char = ptr::null_mut();
        let runtime =
            unsafe { coincide_macos_open(data_cstr.as_ptr(), ver_cstr.as_ptr(), &mut out_err) };
        if !runtime.is_null() {
            assert!(out_err.is_null());
        } else {
            let msg = unsafe { CStr::from_ptr(out_err) }.to_string_lossy().into_owned();
            unsafe { coincide_macos_string_free(out_err) };
            panic!("coincide_macos_open failed: {msg}");
        }

        // 3. Second instance handoff succeeds while running and flags activationRequested!
        assert!(unsafe { coincide_macos_handoff_if_running(data_cstr.as_ptr()) });

        // 4. Poll status (retry briefly if control poll holds try_lock for an instant).
        let status = loop {
            let s = unsafe { take_json(coincide_macos_poll_status(runtime)) };
            if s["busy"] != true {
                break s;
            }
            std::thread::sleep(Duration::from_millis(10));
        };
        assert_eq!(status["ok"], true);
        assert_eq!(status["appVersion"], "0.9.0-test");
        assert_eq!(status["activationRequested"], true);
        assert!(status["revision"].as_u64().is_some());
        assert_eq!(status["pendingApprovalsCount"], 0);
        assert_eq!(status["pendingQuestionsCount"], 0);

        // 5. Adapter call: `workspace` (shorthand without `v`/`id`) & `newThread` (full wire format)
        let ws_req = CString::new(r#"{"type":"workspace","body":{"includeArchived":false}}"#).unwrap();
        let ws_resp = unsafe { take_json(coincide_macos_adapter_call(runtime, ws_req.as_ptr())) };
        assert_eq!(ws_resp["ok"], true, "workspace error: {ws_resp}");
        assert_eq!(ws_resp["type"], "workspace");
        assert!(ws_resp["body"]["projects"].is_array());
        assert_eq!(ws_resp["body"]["canEditBots"], true);

        let nt_req =
            CString::new(r#"{"v":1,"id":"req-2","type":"newThread","body":{}}"#).unwrap();
        let nt_resp = unsafe { take_json(coincide_macos_adapter_call(runtime, nt_req.as_ptr())) };
        assert_eq!(nt_resp["ok"], true, "newThread error: {nt_resp}");
        assert_eq!(nt_resp["type"], "thread");
        let thread_id = nt_resp["body"]["value"]
            .as_str()
            .expect("UUID string")
            .to_owned();
        assert!(Uuid::parse_str(&thread_id).is_ok());

        // Open the newly created thread via Adapter
        let open_req = CString::new(
            json!({
                "type": "openThread",
                "body": { "threadID": thread_id, "limit": 50 }
            })
            .to_string(),
        )
        .unwrap();
        let open_resp =
            unsafe { take_json(coincide_macos_adapter_call(runtime, open_req.as_ptr())) };
        assert_eq!(open_resp["ok"], true, "openThread error: {open_resp}");
        assert_eq!(open_resp["type"], "transcript");
        assert_eq!(open_resp["body"]["thread"]["id"], thread_id);

        // 6. Desktop call: `providers.list_all`
        let prov_req = CString::new(r#"{"action":"providers.list_all"}"#).unwrap();
        let prov_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, prov_req.as_ptr())) };
        assert_eq!(prov_resp["ok"], true, "providers.list_all: {prov_resp}");
        let providers = prov_resp["result"]["providers"].as_array().unwrap();
        assert!(providers.len() >= 7);
        assert!(providers.iter().any(|p| p["id"] == "antigravity"));
        assert!(providers.iter().any(|p| p["id"] == "codex"));
        assert!(providers.iter().any(|p| p["id"] == "claude"));

        // 7. Desktop call: `workspace.write_file`, `workspace.files`, `workspace.read_file`, `workspace.search`
        let proj_dir = dir.path().join("sample-project");
        fs::create_dir_all(&proj_dir).unwrap();
        std::process::Command::new("git")
            .args(["init", "-q"])
            .current_dir(&proj_dir)
            .status()
            .unwrap();

        let write_req = CString::new(
            json!({
                "action": "workspace.write_file",
                "cwd": proj_dir,
                "path": "src/hello.swift",
                "content": "struct CoincideMacApp {\n    let greeting = \"Hello Native SwiftUI\"\n}\n",
            })
            .to_string(),
        )
        .unwrap();
        let write_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, write_req.as_ptr())) };
        assert_eq!(write_resp["ok"], true, "workspace.write_file: {write_resp}");

        let files_req = CString::new(
            json!({
                "action": "workspace.files",
                "cwd": proj_dir,
                "query": "hello",
            })
            .to_string(),
        )
        .unwrap();
        let files_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, files_req.as_ptr())) };
        assert_eq!(files_resp["ok"], true, "workspace.files: {files_resp}");
        assert_eq!(
            files_resp["result"]["files"],
            json!(["src/hello.swift"])
        );

        let read_req = CString::new(
            json!({
                "action": "workspace.read_file",
                "cwd": proj_dir,
                "path": "src/hello.swift",
            })
            .to_string(),
        )
        .unwrap();
        let read_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, read_req.as_ptr())) };
        assert_eq!(read_resp["ok"], true, "workspace.read_file: {read_resp}");
        assert!(
            read_resp["result"]["content"]
                .as_str()
                .unwrap()
                .contains("Hello Native SwiftUI")
        );

        let search_req = CString::new(
            json!({
                "action": "workspace.search",
                "cwd": proj_dir,
                "query": "Hello Native SwiftUI",
            })
            .to_string(),
        )
        .unwrap();
        let search_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, search_req.as_ptr())) };
        assert_eq!(search_resp["ok"], true, "workspace.search: {search_resp}");
        assert_eq!(search_resp["result"]["matches"][0]["path"], "src/hello.swift");

        let edit_req = CString::new(
            json!({
                "action": "workspace.edit_file",
                "cwd": proj_dir,
                "path": "src/hello.swift",
                "oldText": "Hello Native SwiftUI",
                "newText": "Hello Agents",
            })
            .to_string(),
        )
        .unwrap();
        let edit_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, edit_req.as_ptr())) };
        assert_eq!(edit_resp["ok"], true, "workspace.edit_file: {edit_resp}");
        assert_eq!(edit_resp["result"]["replacements"], 1);
        assert_eq!(edit_resp["result"]["lines"], json!([2]));

        let ambiguous_req = CString::new(
            json!({
                "action": "workspace.edit_file",
                "cwd": proj_dir,
                "path": "src/hello.swift",
                "oldText": "e",
                "newText": "E",
            })
            .to_string(),
        )
        .unwrap();
        let ambiguous_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, ambiguous_req.as_ptr())) };
        assert_eq!(ambiguous_resp["ok"], false, "ambiguous edit must fail");

        let missing_req = CString::new(
            json!({
                "action": "workspace.edit_file",
                "cwd": proj_dir,
                "path": "src/hello.swift",
                "oldText": "no such anchor",
                "newText": "x",
            })
            .to_string(),
        )
        .unwrap();
        let missing_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, missing_req.as_ptr())) };
        assert_eq!(missing_resp["ok"], false, "missing anchor edit must fail");

        let regex_req = CString::new(
            json!({
                "action": "workspace.search_regex",
                "cwd": proj_dir,
                "pattern": "Hello (Agents|Swift)",
            })
            .to_string(),
        )
        .unwrap();
        let regex_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, regex_req.as_ptr())) };
        assert_eq!(regex_resp["ok"], true, "workspace.search_regex: {regex_resp}");
        assert_eq!(regex_resp["result"]["matches"][0]["path"], "src/hello.swift");

        let bad_regex_req = CString::new(
            json!({
                "action": "workspace.search_regex",
                "cwd": proj_dir,
                "pattern": "([unclosed",
            })
            .to_string(),
        )
        .unwrap();
        let bad_regex_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, bad_regex_req.as_ptr())) };
        assert_eq!(bad_regex_resp["ok"], false, "invalid regex must fail");

        let copy_req = CString::new(
            json!({
                "action": "workspace.copy_file",
                "cwd": proj_dir,
                "path": "src/hello.swift",
                "destination": "src/hello_copy.swift",
            })
            .to_string(),
        )
        .unwrap();
        let copy_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, copy_req.as_ptr())) };
        assert_eq!(copy_resp["ok"], true, "workspace.copy_file: {copy_resp}");

        let move_req = CString::new(
            json!({
                "action": "workspace.move_file",
                "cwd": proj_dir,
                "path": "src/hello_copy.swift",
                "destination": "src/moved.swift",
            })
            .to_string(),
        )
        .unwrap();
        let move_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, move_req.as_ptr())) };
        assert_eq!(move_resp["ok"], true, "workspace.move_file: {move_resp}");

        let mkdir_req = CString::new(
            json!({
                "action": "workspace.create_dir",
                "cwd": proj_dir,
                "path": "src/nested/deep",
            })
            .to_string(),
        )
        .unwrap();
        let mkdir_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, mkdir_req.as_ptr())) };
        assert_eq!(mkdir_resp["ok"], true, "workspace.create_dir: {mkdir_resp}");

        let readdir_req = CString::new(
            json!({
                "action": "workspace.read_dir",
                "cwd": proj_dir,
                "path": "src",
                "recursive": true,
            })
            .to_string(),
        )
        .unwrap();
        let readdir_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, readdir_req.as_ptr())) };
        assert_eq!(readdir_resp["ok"], true, "workspace.read_dir: {readdir_resp}");
        let entries = readdir_resp["result"]["entries"].as_array().unwrap();
        assert!(entries.iter().any(|e| e["path"] == "src/hello.swift"));
        assert!(entries.iter().any(|e| e["path"] == "src/moved.swift"));
        assert!(
            entries
                .iter()
                .any(|e| e["path"] == "src/nested/deep" && e["isDirectory"] == true)
        );

        let del_file_req = CString::new(
            json!({
                "action": "workspace.delete_file",
                "cwd": proj_dir,
                "path": "src/moved.swift",
            })
            .to_string(),
        )
        .unwrap();
        let del_file_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, del_file_req.as_ptr())) };
        assert_eq!(del_file_resp["ok"], true, "workspace.delete_file: {del_file_resp}");
        assert!(!proj_dir.join("src/moved.swift").exists());

        let del_dir_req = CString::new(
            json!({
                "action": "workspace.delete_directory",
                "cwd": proj_dir,
                "path": "src/nested",
                "recursive": true,
            })
            .to_string(),
        )
        .unwrap();
        let del_dir_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, del_dir_req.as_ptr())) };
        assert_eq!(
            del_dir_resp["ok"], true,
            "workspace.delete_directory: {del_dir_resp}"
        );
        assert!(!proj_dir.join("src/nested").exists());

        let escape_req = CString::new(
            json!({
                "action": "workspace.delete_file",
                "cwd": proj_dir,
                "path": "../escape.txt",
            })
            .to_string(),
        )
        .unwrap();
        let escape_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, escape_req.as_ptr())) };
        assert_eq!(escape_resp["ok"], false, "path escape must fail");

        // 8. Desktop call: `terminal.create` + `terminal.viewport` + `terminal.close`
        let term_create_req = CString::new(
            json!({
                "action": "terminal.create",
                "params": { "threadId": thread_id }
            })
            .to_string(),
        )
        .unwrap();
        let term_create_resp = unsafe {
            take_json(coincide_macos_desktop_call(
                runtime,
                term_create_req.as_ptr(),
            ))
        };
        assert_eq!(
            term_create_resp["ok"], true,
            "terminal.create: {term_create_resp}"
        );
        let terminal_id = term_create_resp["result"]["terminalId"]
            .as_str()
            .unwrap()
            .to_owned();

        let term_vp_req = CString::new(
            json!({
                "action": "terminal.viewport",
                "id": terminal_id,
                "dark": true,
            })
            .to_string(),
        )
        .unwrap();
        let term_vp_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, term_vp_req.as_ptr())) };
        assert_eq!(term_vp_resp["ok"], true, "terminal.viewport: {term_vp_resp}");
        assert!(term_vp_resp["result"]["lines"].is_array());
        assert!(term_vp_resp["result"]["grid"].is_array());
        assert!(term_vp_resp["result"]["runs"].is_array());
        assert_eq!(term_vp_resp["result"]["terminalId"], terminal_id);

        let term_close_req = CString::new(
            json!({
                "action": "engine.rpc",
                "method": "terminal.close",
                "params": { "terminalId": terminal_id },
            })
            .to_string(),
        )
        .unwrap();
        let term_close_resp = unsafe {
            take_json(coincide_macos_desktop_call(
                runtime,
                term_close_req.as_ptr(),
            ))
        };
        assert_eq!(term_close_resp["ok"], true, "terminal.close: {term_close_resp}");

        // 9. Desktop call: `threads.delete_permanent` + `threads.undo_delete`
        let del_req = CString::new(
            json!({
                "action": "threads.delete_permanent",
                "threadId": thread_id,
            })
            .to_string(),
        )
        .unwrap();
        let del_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, del_req.as_ptr())) };
        assert_eq!(del_resp["ok"], true, "threads.delete_permanent: {del_resp}");
        assert_eq!(del_resp["result"]["deleted"], true);

        let undo_req = CString::new(
            json!({
                "action": "threads.undo_delete",
                "threadId": thread_id,
            })
            .to_string(),
        )
        .unwrap();
        let undo_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, undo_req.as_ptr())) };
        assert_eq!(undo_resp["ok"], true, "threads.undo_delete: {undo_resp}");
        assert_eq!(undo_resp["result"]["restored"], true);

        // 10. Desktop call: `remote.status` & `usage.dashboard`
        let remote_req = CString::new(r#"{"action":"remote.status"}"#).unwrap();
        let remote_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, remote_req.as_ptr())) };
        assert_eq!(remote_resp["ok"], true, "remote.status: {remote_resp}");
        assert_eq!(remote_resp["result"]["enabled"], false);
        assert_eq!(remote_resp["result"]["status"], "off");

        let usage_req = CString::new(r#"{"action":"usage.dashboard","days":30}"#).unwrap();
        let usage_resp =
            unsafe { take_json(coincide_macos_desktop_call(runtime, usage_req.as_ptr())) };
        assert_eq!(usage_resp["ok"], true, "usage.dashboard: {usage_resp}");
        assert_eq!(usage_resp["result"]["days"], 30);

        // 11. Close runtime cleanly and verify socket is cleaned up.
        unsafe { coincide_macos_close(runtime) };
        assert!(!data_dir.join("control.sock").exists());
        assert!(!unsafe { coincide_macos_handoff_if_running(data_cstr.as_ptr()) });
    }

    #[test]
    fn legacy_import_instructions_attachments_scripts_and_extended_adapter_requests() {
        let dir = tempfile::tempdir().unwrap();
        let data_dir = dir.path().join("coincide-data");
        let proj_dir = dir.path().join("legacy-repo");
        fs::create_dir_all(&proj_dir).unwrap();
        std::process::Command::new("git")
            .args(["init", "-q"])
            .current_dir(&proj_dir)
            .status()
            .unwrap();
        fs::write(proj_dir.join("README.md"), "# Coincide Native\n").unwrap();

        // Prepare a mock legacy Swift Application Support directory
        let legacy_dir = dir.path().join("LegacyCoincide");
        fs::create_dir_all(legacy_dir.join("threads")).unwrap();
        let legacy_proj_id = Uuid::new_v4().to_string().to_uppercase();
        let legacy_bot_id = Uuid::new_v4().to_string().to_uppercase();
        let legacy_thread_id = Uuid::new_v4().to_string().to_uppercase();
        fs::write(
            legacy_dir.join("projects.json"),
            serde_json::to_vec(&json!([
                {
                    "id": legacy_proj_id,
                    "name": "Legacy Repo",
                    "path": proj_dir,
                    "scripts": []
                }
            ]))
            .unwrap(),
        )
        .unwrap();
        fs::write(
            legacy_dir.join("bots.json"),
            serde_json::to_vec(&json!({
                "addedStarters": false,
                "starterLineup": 1,
                "bots": [
                    {
                        "id": legacy_bot_id,
                        "name": "Reviewer Bot",
                        "persona": "Review SwiftUI code carefully.",
                        "selection": { "provider": "codex", "modelID": "default" },
                        "accessMode": "approval",
                        "interactionMode": "build",
                        "createdAt": 780_000_000.0
                    }
                ]
            }))
            .unwrap(),
        )
        .unwrap();
        fs::write(
            legacy_dir
                .join("threads")
                .join(format!("{legacy_thread_id}.json")),
            serde_json::to_vec(&json!({
                "id": legacy_thread_id,
                "projectID": legacy_proj_id,
                "projectPath": proj_dir,
                "title": "Legacy Swift Thread",
                "selection": { "provider": "codex", "modelID": "default" },
                "items": [
                    {
                        "id": Uuid::new_v4().to_string().to_uppercase(),
                        "timestamp": 780_000_005.0,
                        "content": { "userMessage": { "text": "Hello from legacy Coincide!", "images": [] } }
                    }
                ],
                "createdAt": 780_000_000.0,
                "updatedAt": 780_000_010.0
            }))
            .unwrap(),
        )
        .unwrap();

        let data_cstr = CString::new(data_dir.to_str().unwrap()).unwrap();
        let ver_cstr = CString::new("0.9.0-test").unwrap();
        let mut out_err: *mut c_char = ptr::null_mut();
        let runtime =
            unsafe { coincide_macos_open(data_cstr.as_ptr(), ver_cstr.as_ptr(), &mut out_err) };
        assert!(!runtime.is_null());

        let call_desktop = |payload: Value| -> Value {
            let s = CString::new(payload.to_string()).unwrap();
            unsafe { take_json(coincide_macos_desktop_call(runtime, s.as_ptr())) }
        };
        let call_adapter = |payload: Value| -> Value {
            let s = CString::new(payload.to_string()).unwrap();
            unsafe { take_json(coincide_macos_adapter_call(runtime, s.as_ptr())) }
        };

        // 1. Legacy import (non-destructive + idempotent)
        let imp1 = call_desktop(json!({
            "action": "store.import_legacy",
            "sourceDir": legacy_dir,
        }));
        assert_eq!(imp1["ok"], true, "store.import_legacy: {imp1}");
        assert_eq!(imp1["result"]["importedProjects"], 1);
        assert_eq!(imp1["result"]["importedBots"], 1);
        assert_eq!(imp1["result"]["importedThreads"], 1);
        assert!(legacy_dir.join("projects.json").exists());

        let imp2 = call_desktop(json!({
            "action": "store.import_legacy",
            "sourceDir": legacy_dir,
        }));
        assert_eq!(imp2["ok"], true);
        assert_eq!(imp2["result"]["importedThreads"], 0);
        assert_eq!(imp2["result"]["skippedThreads"], 1);

        // 2. Project scripts save on the imported project
        let scripts_resp = call_desktop(json!({
            "action": "projects.scripts.save",
            "projectId": legacy_proj_id,
            "scripts": [
                {
                    "name": "Build App",
                    "command": "swift build",
                    "icon": "hammer"
                }
            ]
        }));
        assert_eq!(scripts_resp["ok"], true, "projects.scripts.save: {scripts_resp}");
        assert_eq!(scripts_resp["result"]["scripts"][0]["name"], "Build App");

        // 3. Instructions list / save / read inside project scope
        let inst_save = call_desktop(json!({
            "action": "instructions.save",
            "cwd": proj_dir,
            "scope": "project",
            "relativePath": "AGENTS.md",
            "content": "# Agent Rules\nAlways test FFI boundaries.\n",
        }));
        assert_eq!(inst_save["ok"], true, "instructions.save: {inst_save}");

        let inst_list = call_desktop(json!({
            "action": "instructions.list",
            "cwd": proj_dir,
        }));
        assert_eq!(inst_list["ok"], true, "instructions.list: {inst_list}");
        assert!(
            inst_list["result"]["project"]
                .as_array()
                .unwrap()
                .iter()
                .any(|f| f["relativePath"] == "AGENTS.md" && f["exists"] == true)
        );

        let inst_read = call_desktop(json!({
            "action": "instructions.read",
            "cwd": proj_dir,
            "path": proj_dir.join("AGENTS.md"),
        }));
        assert_eq!(inst_read["ok"], true, "instructions.read: {inst_read}");
        assert!(
            inst_read["result"]["content"]
                .as_str()
                .unwrap()
                .contains("Always test FFI boundaries.")
        );

        // 4. Attachments staging (1x1 transparent PNG via base64)
        let png_1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==";
        let stage_resp = call_desktop(json!({
            "action": "attachments.stage",
            "base64": png_1x1,
            "filename": "pixel.png",
            "mimeType": "image/png",
        }));
        assert_eq!(stage_resp["ok"], true, "attachments.stage: {stage_resp}");
        assert_eq!(stage_resp["result"]["mimeType"], "image/png");

        // 5. Extended CoincideRemoteKit Adapter requests (`settings`, `usageDashboard`, `scheduledTasks`, `diff`, `gitState`, `forkThread`)
        let settings_resp = call_adapter(json!({ "type": "settings", "body": {} }));
        assert_eq!(settings_resp["ok"], true, "adapter settings: {settings_resp}");
        assert_eq!(settings_resp["type"], "settings");

        let ud_resp = call_adapter(json!({
            "type": "usageDashboard",
            "body": { "days": 7 }
        }));
        assert_eq!(ud_resp["ok"], true, "adapter usageDashboard: {ud_resp}");
        assert_eq!(ud_resp["type"], "usageDashboard");

        let st_resp = call_adapter(json!({ "type": "scheduledTasks", "body": {} }));
        assert_eq!(st_resp["ok"], true, "adapter scheduledTasks: {st_resp}");
        assert_eq!(st_resp["type"], "scheduledTasks");

        let imported_fork_id = imp1["result"]["forked"][0]["fork"]
            .as_str()
            .unwrap()
            .to_owned();

        let diff_resp = call_adapter(json!({
            "type": "diff",
            "body": { "threadID": imported_fork_id }
        }));
        assert_eq!(diff_resp["ok"], true, "adapter diff: {diff_resp}");
        assert_eq!(diff_resp["type"], "diff");

        let gs_resp = call_adapter(json!({
            "type": "gitState",
            "body": { "threadID": imported_fork_id }
        }));
        assert_eq!(gs_resp["ok"], true, "adapter gitState: {gs_resp}");
        assert_eq!(gs_resp["type"], "gitState");

        let fork_resp = call_adapter(json!({
            "type": "forkThread",
            "body": { "threadID": imported_fork_id }
        }));
        assert_eq!(fork_resp["ok"], true, "adapter forkThread: {fork_resp}");
        assert_eq!(fork_resp["type"], "thread");

        unsafe { coincide_macos_close(runtime) };
    }
}
