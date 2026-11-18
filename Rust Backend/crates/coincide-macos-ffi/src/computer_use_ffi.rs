use coincide_core::{
    api::{Engine, SharedEngine, computer_use_engine::Pending},
    computer_use::{Failure, Permission, PermissionKind},
    computer_use_bridge::Bridge,
};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, VecDeque},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};
use uuid::Uuid;

#[path = "../../coincide-desktop/src/computer_use.rs"]
mod runtime;

use runtime::{Handle, Reply, Runtime};

const LIMIT: usize = 8;
const TICK: Duration = Duration::from_millis(25);

struct Identity {
    engine: Uuid,
    thread: Uuid,
    grant: Uuid,
    deadline: Instant,
}

struct Completion {
    identity: Identity,
    result: std::result::Result<Value, Failure>,
}

struct Pump {
    runtime: Runtime,
    handle: Handle,
    engine: SharedEngine,
    bridge: Arc<Bridge>,
    stop: Arc<AtomicBool>,
    exited: Arc<AtomicBool>,
    flights: BTreeMap<Uuid, Identity>,
    completions: VecDeque<Completion>,
    bound: bool,
    bridge_bound: bool,
}

impl Pump {
    fn new(
        runtime: Runtime,
        handle: Handle,
        engine: SharedEngine,
        bridge: Arc<Bridge>,
        stop: Arc<AtomicBool>,
        exited: Arc<AtomicBool>,
    ) -> Self {
        Self {
            runtime,
            handle,
            engine,
            bridge,
            stop,
            exited,
            flights: BTreeMap::new(),
            completions: VecDeque::new(),
            bound: false,
            bridge_bound: false,
        }
    }

    fn run(mut self) {
        loop {
            if self.stop.load(Ordering::Acquire) {
                break;
            }
            self.harvest();
            if let Ok(mut engine) = self.engine.try_lock() {
                let plan = self.prepare(&mut engine);
                drop(engine);
                self.submit(plan);
                if let Ok(mut engine) = self.engine.try_lock() {
                    self.flush(&mut engine);
                }
            }
            thread::sleep(TICK);
        }
        self.finish();
        self.exited.store(true, Ordering::Release);
    }

    fn prepare(&mut self, engine: &mut Engine) -> Vec<Pending> {
        if self.stop.load(Ordering::Acquire) || engine.shutdown {
            engine.computer_use_shutdown();
            engine.computer_use_unbind_authority();
            self.bridge.stop();
            self.flights.clear();
            self.completions.clear();
            return Vec::new();
        }
        if !self.bound {
            engine.computer_use_bind_authority(self.handle.authority_for_engine());
            self.bound = true;
            if engine.computer_use_saved_enabled().unwrap_or(false) {
                let _ = self.handle.native_enable(true);
            }
        }
        if !self.bridge_bound {
            engine.computer_use_bind_bridge(self.bridge.clone());
            self.bridge_bound = true;
        }
        if let Some(enabled) = self.handle.take_unsaved() {
            let _ = engine.computer_use_save_enabled(enabled);
        }
        let master = self.handle.authority_for_engine().enabled();
        let stopped = self
            .handle
            .try_status()
            .map(|status| status.stopped)
            .unwrap_or(true);
        let enabled = master && !stopped;
        if !enabled {
            engine.computer_use_revoke_all();
            self.bridge.stop();
        }
        self.flush(engine);
        if !enabled {
            return Vec::new();
        }
        let room = LIMIT.saturating_sub(self.flights.len() + self.completions.len());
        if room == 0 {
            return Vec::new();
        }
        engine.computer_use_drain()
    }

    fn submit(&mut self, requests: Vec<Pending>) {
        for pending in requests {
            let identity = Identity {
                engine: pending.id,
                thread: pending.thread,
                grant: pending.grant,
                deadline: pending.deadline,
            };
            let result = if self.stop.load(Ordering::Acquire) {
                Err(Failure::Revoked)
            } else if self.flights.len() >= LIMIT {
                Err(Failure::Busy)
            } else {
                self.handle.try_request_bound(
                    pending.thread,
                    pending.request,
                    pending.deadline,
                    pending.grant,
                )
            };
            match result {
                Ok(native) => {
                    self.flights.insert(native, identity);
                }
                Err(error) => {
                    self.completions.push_back(Completion {
                        identity,
                        result: Err(error),
                    });
                }
            }
        }
    }

    fn harvest(&mut self) {
        while self.completions.len() < LIMIT {
            let Ok(reply) = self.runtime.try_reply() else {
                break;
            };
            self.accept(reply);
        }
        let expired: Vec<Uuid> = self
            .flights
            .iter()
            .filter(|(_, identity)| Instant::now() >= identity.deadline)
            .map(|(id, _)| *id)
            .take(LIMIT - self.completions.len())
            .collect();
        for native in expired {
            if let Some(identity) = self.flights.remove(&native) {
                self.completions.push_back(Completion {
                    identity,
                    result: Err(Failure::TimedOut),
                });
            }
        }
    }

    fn accept(&mut self, reply: Reply) {
        let Some(identity) = self.flights.remove(&reply.id) else {
            return;
        };
        let result = if reply.thread != identity.thread {
            Err(Failure::Revoked)
        } else {
            reply.result
        };
        self.completions.push_back(Completion { identity, result });
    }

    fn flush(&mut self, engine: &mut Engine) {
        while let Some(mut completion) = self.completions.pop_front() {
            let identity = completion.identity;
            if self.handle.authority_for_engine().grant(identity.thread) != Ok(identity.grant) {
                completion.result = Err(Failure::Revoked);
            } else if Instant::now() >= identity.deadline {
                completion.result = Err(Failure::TimedOut);
            }
            engine.computer_use_reply(identity.engine, identity.thread, completion.result);
        }
    }

    fn finish(&mut self) {
        self.runtime.request_shutdown();
        if let Ok(mut engine) = self.engine.try_lock() {
            engine.computer_use_shutdown();
            engine.computer_use_unbind_authority();
        }
        self.bridge.stop();
    }
}

pub(crate) struct ComputerUseMount {
    handle: Option<Handle>,
    stop: Arc<AtomicBool>,
    exited: Arc<AtomicBool>,
    spawn_error: Option<String>,
}

impl ComputerUseMount {
    pub(crate) fn start(engine: &SharedEngine) -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let exited = Arc::new(AtomicBool::new(false));
        let bridge = Arc::new(Bridge::new(engine));
        let (handle, spawn_error) = match Runtime::spawn_native() {
            Ok(runtime) => {
                let handle = runtime.handle();
                let pump = Pump::new(
                    runtime,
                    handle.clone(),
                    engine.clone(),
                    bridge,
                    stop.clone(),
                    exited.clone(),
                );
                match thread::Builder::new()
                    .name("coincide-computer-use-ffi-pump".into())
                    .spawn(move || pump.run())
                {
                    Ok(_) => (Some(handle), None),
                    Err(error) => {
                        exited.store(true, Ordering::Release);
                        (
                            Some(handle),
                            Some(format!(
                                "Computer Use pump thread failed to start: {error}"
                            )),
                        )
                    }
                }
            }
            Err(error) => {
                exited.store(true, Ordering::Release);
                (
                    None,
                    Some(format!("Computer Use runtime failed to start: {error}")),
                )
            }
        };
        Self {
            handle,
            stop,
            exited,
            spawn_error,
        }
    }

    pub(crate) fn shutdown(&self) {
        self.stop.store(true, Ordering::Release);
        let deadline = Instant::now() + Duration::from_secs(2);
        while !self.exited.load(Ordering::Acquire) {
            if Instant::now() >= deadline {
                break;
            }
            thread::sleep(Duration::from_millis(5));
        }
    }

    pub(crate) fn status(&self, engine: &SharedEngine) -> Value {
        let saved = engine
            .try_lock()
            .map(|guard| guard.computer_use_saved_enabled().unwrap_or(false))
            .unwrap_or(false);
        let Some(handle) = &self.handle else {
            return json!({
                "enabled": false,
                "nativeCompiled": false,
                "savedEnabled": saved,
                "accessibility": "unsupported",
                "screenCapture": "unsupported",
                "desktopOwner": Value::Null,
                "stopped": false,
                "grantedThreads": [],
                "activeThreads": [],
                "error": self.spawn_error,
            });
        };
        let runtime_status = handle.try_status();
        let (granted, active) = handle.activity();
        let permission = |permission: Permission| {
            serde_json::to_value(permission)
                .ok()
                .and_then(|value| value.as_str().map(str::to_owned))
                .unwrap_or_else(|| "unknown".to_owned())
        };
        let mut error = Value::Null;
        if let Some(message) = &self.spawn_error {
            error = Value::String(message.clone());
        } else if let Some(failure) = runtime_status.as_ref().and_then(|status| status.error) {
            error = serde_json::to_value(failure)
                .unwrap_or_else(|_| Value::String("native".into()));
        }
        json!({
            "enabled": runtime_status.as_ref().map(|status| status.enabled).unwrap_or(false),
            "nativeCompiled": runtime_status.as_ref().map(|status| status.native_compiled).unwrap_or(false),
            "savedEnabled": saved,
            "accessibility": runtime_status.as_ref().map(|status| permission(status.permissions.accessibility)).unwrap_or_else(|| "unknown".to_owned()),
            "screenCapture": runtime_status.as_ref().map(|status| permission(status.permissions.screen_capture)).unwrap_or_else(|| "unknown".to_owned()),
            "desktopOwner": runtime_status.as_ref().and_then(|status| status.desktop_owner).map(|owner| owner.to_string()),
            "stopped": runtime_status.as_ref().map(|status| status.stopped).unwrap_or(false),
            "grantedThreads": granted.iter().map(|thread| thread.to_string()).collect::<Vec<_>>(),
            "activeThreads": active.iter().map(|thread| thread.to_string()).collect::<Vec<_>>(),
            "error": error,
        })
    }

    pub(crate) fn set_enabled(&self, enabled: bool) -> Result<(), Failure> {
        let Some(handle) = &self.handle else {
            return Err(Failure::Unsupported);
        };
        handle.native_set_saved(enabled)
    }

    pub(crate) fn request_permission(
        &self,
        kind: Option<PermissionKind>,
    ) -> Result<(), Failure> {
        let Some(handle) = &self.handle else {
            return Err(Failure::Unsupported);
        };
        match kind {
            Some(kind) => handle.native_request_permission(kind),
            None => handle.native_refresh(),
        }
    }
}
