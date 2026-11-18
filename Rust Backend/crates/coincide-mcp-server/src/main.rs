mod assets;
mod protocol;
mod tools;

use std::{
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    process::ExitCode,
};

pub struct ServerState {
    pub cwd: PathBuf,
    pub thread_id: Option<String>,
    pub socket: PathBuf,
    pub assets_dir: Option<PathBuf>,
    pub control: std::sync::Mutex<coincide_core::control::ControlClient>,
}

const USAGE: &str = "coincide-mcp-server --cwd <dir> [--thread-id <id>] [--socket <path>] [--assets-dir <dir>]";

fn parse_args(args: &[String]) -> Result<ServerState, String> {
    let mut cwd: Option<PathBuf> = None;
    let mut thread_id: Option<String> = None;
    let mut socket: Option<PathBuf> = None;
    let mut assets_dir: Option<PathBuf> = None;
    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];
        let value = |i: usize| -> Result<String, String> {
            args.get(i + 1)
                .filter(|v| !v.is_empty())
                .cloned()
                .ok_or_else(|| format!("Missing value for {arg}"))
        };
        match arg.as_str() {
            "--cwd" => cwd = Some(PathBuf::from(value(i)?)),
            "--thread-id" => thread_id = Some(value(i)?),
            "--socket" => socket = Some(PathBuf::from(value(i)?)),
            "--assets-dir" => assets_dir = Some(PathBuf::from(value(i)?)),
            "--help" | "-h" => return Err(USAGE.to_owned()),
            _ => return Err(format!("Unknown argument {arg}; usage: {USAGE}")),
        }
        i += 2;
    }
    let cwd = cwd.ok_or_else(|| format!("Missing --cwd; usage: {USAGE}"))?;
    if !cwd.is_absolute() {
        return Err("--cwd must be an absolute path".to_owned());
    }
    let socket = match socket {
        Some(path) => path,
        None => coincide_core::control::data_directory()
            .map_err(|error| error.to_string())?
            .join("control.sock"),
    };
    let control = std::sync::Mutex::new(coincide_core::control::ControlClient::new(socket.clone()));
    Ok(ServerState {
        cwd,
        thread_id,
        socket,
        assets_dir,
        control,
    })
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let state = parse_args(&args)?;
    let stdin = std::io::stdin();
    let mut reader = BufReader::new(stdin.lock());
    let stdout = std::io::stdout();
    let mut writer = stdout.lock();
    let mut line = String::new();
    loop {
        line.clear();
        let read = reader
            .read_line(&mut line)
            .map_err(|error| format!("Failed reading MCP input: {error}"))?;
        if read == 0 {
            return Ok(());
        }
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let response = match serde_json::from_str::<serde_json::Value>(trimmed) {
            Ok(request) => {
                if !request.is_object() {
                    protocol::parse_error_response("Request must be a JSON object")
                } else {
                    match protocol::handle(&state, &request) {
                        Some(response) => response,
                        None => continue,
                    }
                }
            }
            Err(error) => protocol::parse_error_response(&format!("Parse error: {error}")),
        };
        let mut encoded = serde_json::to_string(&response)
            .map_err(|error| format!("Failed encoding MCP response: {error}"))?;
        encoded.push('\n');
        writer
            .write_all(encoded.as_bytes())
            .map_err(|error| format!("Failed writing MCP response: {error}"))?;
        writer
            .flush()
            .map_err(|error| format!("Failed flushing MCP response: {error}"))?;
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("coincide-mcp-server: {message}");
            ExitCode::FAILURE
        }
    }
}
