mod assets;
mod protocol;
mod system_assets_search;
mod tools;

use std::{
    io::{BufRead, BufReader, Write},
    path::PathBuf,
    process::ExitCode,
};

use serde_json::Value;

pub struct ServerState {
    pub cwd: PathBuf,
    pub thread_id: Option<String>,
    pub socket: PathBuf,
    pub assets_dir: Option<PathBuf>,
    pub control: std::sync::Mutex<coincide_core::control::ControlClient>,
}

const USAGE: &str = "coincide-mcp-server --cwd <dir> [--thread-id <id>] [--socket <path>] [--assets-dir <dir>]";
const MAX_FRAME_BYTES: usize = 16 * 1024 * 1024;

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

enum FrameRead {
    Eof,
    Line(Vec<u8>),
    Oversized,
}

fn drain_to_newline(reader: &mut impl BufRead) -> std::io::Result<()> {
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return Ok(());
        }
        match available.iter().position(|byte| *byte == b'\n') {
            Some(end) => {
                reader.consume(end + 1);
                return Ok(());
            }
            None => {
                let len = available.len();
                reader.consume(len);
            }
        }
    }
}

fn read_frame_line(reader: &mut impl BufRead) -> std::io::Result<FrameRead> {
    let mut raw: Vec<u8> = Vec::new();
    loop {
        if raw.len() > MAX_FRAME_BYTES {
            drain_to_newline(reader)?;
            return Ok(FrameRead::Oversized);
        }
        // Copy out of the buffer and drop its borrow before consuming, since
        // `consume` and `drain_to_newline` need `reader` mutably again.
        let (take, end, available_len) = {
            let available = reader.fill_buf()?;
            if available.is_empty() {
                if raw.is_empty() {
                    return Ok(FrameRead::Eof);
                }
                return Ok(FrameRead::Line(raw));
            }
            let end = available.iter().position(|byte| *byte == b'\n');
            let room = MAX_FRAME_BYTES + 1 - raw.len();
            let take = match end {
                Some(end) => (end + 1).min(room),
                None => available.len().min(room),
            };
            raw.extend_from_slice(&available[..take]);
            (take, end, available.len())
        };
        reader.consume(take);
        match end {
            Some(end) => {
                if take < end + 1 {
                    drain_to_newline(reader)?;
                    return Ok(FrameRead::Oversized);
                }
                return Ok(FrameRead::Line(raw));
            }
            None => {
                if take < available_len {
                    drain_to_newline(reader)?;
                    return Ok(FrameRead::Oversized);
                }
            }
        }
    }
}

fn write_response(writer: &mut impl Write, response: &Value) -> Result<(), String> {
    let mut encoded = serde_json::to_string(response)
        .map_err(|error| format!("Failed encoding MCP response: {error}"))?;
    encoded.push('\n');
    writer
        .write_all(encoded.as_bytes())
        .map_err(|error| format!("Failed writing MCP response: {error}"))?;
    writer
        .flush()
        .map_err(|error| format!("Failed flushing MCP response: {error}"))?;
    Ok(())
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let state = parse_args(&args)?;
    let stdin = std::io::stdin();
    let mut reader = BufReader::new(stdin.lock());
    let stdout = std::io::stdout();
    let mut writer = stdout.lock();
    loop {
        let raw = match read_frame_line(&mut reader)
            .map_err(|error| format!("Failed reading MCP input: {error}"))?
        {
            FrameRead::Eof => return Ok(()),
            FrameRead::Oversized => {
                write_response(
                    &mut writer,
                    &protocol::parse_error_response("Request frame exceeds 16 MiB"),
                )?;
                continue;
            }
            FrameRead::Line(raw) => raw,
        };
        let text = match String::from_utf8(raw) {
            Ok(text) => text,
            Err(_) => {
                write_response(
                    &mut writer,
                    &protocol::parse_error_response("Request is not valid UTF-8"),
                )?;
                continue;
            }
        };
        let trimmed = text.trim();
        if trimmed.is_empty() {
            continue;
        }
        let response = match serde_json::from_str::<serde_json::Value>(trimmed) {
            Ok(request) => {
                if !request.is_object() {
                    protocol::invalid_request_response("Request must be a JSON object")
                } else {
                    match protocol::handle(&state, &request) {
                        Some(response) => response,
                        None => continue,
                    }
                }
            }
            Err(error) => protocol::parse_error_response(&format!("Parse error: {error}")),
        };
        write_response(&mut writer, &response)?;
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
