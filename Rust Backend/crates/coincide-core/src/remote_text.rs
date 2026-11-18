//! The wording Settings › General › Remote shows, as `RemoteSettingsView.swift`
//! words it, kept here so it's tested without a window.
use super::protocol::{Device, HostKind};
use super::server::Status;

/// The status dot's color: green running, yellow starting, orange failed, the
/// border color when off.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dot {
    Green,
    Yellow,
    Orange,
    Off,
}

pub fn status_dot(status: &Status) -> Dot {
    match status {
        Status::Running { .. } => Dot::Green,
        Status::Starting => Dot::Yellow,
        Status::Failed(_) => Dot::Orange,
        Status::Off => Dot::Off,
    }
}

pub fn status_title(status: &Status) -> &'static str {
    match status {
        Status::Running { .. } => "Listening for Coincide Remote",
        Status::Starting => "Starting…",
        Status::Failed(_) => "Coincide Remote can’t start",
        Status::Off => "Off",
    }
}

pub fn status_detail(status: &Status, connected: usize) -> String {
    match status {
        Status::Running { port } if connected == 0 => {
            format!("On port {port}. Scan the pairing code with Coincide Remote to add a device.")
        }
        Status::Running { port } => format!("On port {port}. {connected} connected now."),
        Status::Starting => "Preparing the encrypted connection.".into(),
        Status::Failed(message) => message.clone(),
        Status::Off => String::new(),
    }
}

pub fn kind_label(kind: HostKind) -> &'static str {
    match kind {
        HostKind::Lan => "Local network",
        HostKind::LocalName => "Bonjour name",
        HostKind::Tailscale => "Tailscale",
        HostKind::TailscaleName => "MagicDNS",
        HostKind::Manual => "",
    }
}

/// "Connected now", "Last connected 5 minutes ago" or "Paired Jan 2, 2026 at 3:04 PM".
pub fn device_detail(device: &Device, connected: bool, now_ms: f64) -> String {
    if connected {
        return "Connected now".into();
    }
    match device.last_seen_at {
        Some(seen) => format!("Last connected {}", relative(seen, now_ms)),
        None => format!("Paired {}", date_time(device.paired_at)),
    }
}

/// A past moment the way `.relative(presentation: .named)` reads it.
pub fn relative(then_ms: f64, now_ms: f64) -> String {
    let seconds = ((now_ms - then_ms) / 1000.).max(0.) as u64;
    let plural =
        |count: u64, unit: &str| format!("{count} {unit}{} ago", if count == 1 { "" } else { "s" });
    match seconds {
        0..60 => "now".into(),
        60..3_600 => plural(seconds / 60, "minute"),
        3_600..86_400 => plural(seconds / 3_600, "hour"),
        86_400..172_800 => "yesterday".into(),
        172_800..604_800 => plural(seconds / 86_400, "day"),
        604_800..1_209_600 => "last week".into(),
        _ => plural(seconds / 604_800, "week"),
    }
}

fn date_time(ms: f64) -> String {
    chrono::DateTime::from_timestamp_millis(ms as i64)
        .map(|date| {
            date.with_timezone(&chrono::Local)
                .format("%b %-d, %Y at %-I:%M %p")
                .to_string()
        })
        .unwrap_or_default()
}

/// "Works once, for 4:59 more." until the code expires.
pub fn countdown(expires_at_seconds: f64, now_ms: f64) -> (String, bool) {
    let remaining = (expires_at_seconds - now_ms / 1000.).max(0.) as u64;
    if remaining > 0 {
        (
            format!(
                "Works once, for {}:{:02} more.",
                remaining / 60,
                remaining % 60
            ),
            true,
        )
    } else {
        ("This code has expired.".into(), false)
    }
}

pub fn sanitize_display_text(text: &str) -> Option<String> {
    let mut result = collapse_whitespace(text);
    if result.is_empty() {
        return None;
    }
    if let Ok(home) = std::env::var("HOME") {
        if !home.is_empty() && home != "/" {
            result = result.replace(&home, "~");
        }
    }
    for (pattern, replacement) in sanitize_patterns() {
        result = replace(&result, pattern, replacement);
    }
    result = collapse_whitespace(&result);
    if result.is_empty() {
        None
    } else {
        Some(result)
    }
}

fn collapse_whitespace(text: &str) -> String {
    replace(text, r"\s+", " ").trim().to_string()
}

fn replace(text: &str, pattern: &str, replacement: &str) -> String {
    match regex::Regex::new(pattern) {
        Ok(expression) => expression.replace_all(text, replacement).into_owned(),
        Err(_) => text.to_string(),
    }
}

fn sanitize_patterns() -> [(&'static str, &'static str); 36] {
    [
        (r"(?i)(?:ws|wss|http|https|ftp)://\S+", "[address]"),
        (r"(?i)\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b", "[address]"),
        (r"(?i)\blocalhost(?::\d+)?\b", "[local address]"),
        (r"(?i)\btransport\s*[:=]\s*\S+", "transport: [redacted]"),
        (r"(?i)\bport\s+\d+\b", "port [redacted]"),
        (r"(?i)\bunix\s+socket\s+\S+", "unix socket [redacted]"),
        (r"(?i)\bfd\s+\d+\b", "fd [redacted]"),
        (r"/Users/[^/\s]+", "~"),
        (r"~/Library/Application Support[^\s,;:]*", "[application support]"),
        (r"~/Library/Caches[^\s,;:]*", "[cache]"),
        (r"~/Library/Logs[^\s,;:]*", "[logs]"),
        (r"~/\.config[^\s,;:]*", "[config]"),
        (r"~/\.curlrc[^\s,;:]*", "[config]"),
        (r"~/\.ssh[^\s,;:]*", "[config]"),
        (r"file://\S+", "[path]"),
        (r"(?:/private)?/var/folders/\S+", "[temporary directory]"),
        (r"(?:/private)?/tmp/\S+", "[temporary directory]"),
        (r"SystemAssets/\S+", "[asset]"),
        (r"~/\S+", "[path]"),
        (
            r"/(?:Users|var|tmp|private|etc|opt|usr|Library|System|Applications|Volumes)/[^\s,;:\"']*",
            "[path]",
        ),
        (r"(?i)://[^/\s:]+:[^/\s@]+@", "://[redacted]@"),
        (
            r"(?i)Authorization\s*:\s*(?:Bearer\s+)?\S+",
            "Authorization: [redacted]",
        ),
        (
            r"(?i)(api[_-]?key|apikey|access[_-]?token|auth[_-]?token|token|client[_-]?secret|secret|password|passwd)\s*[:=]\s*\S+",
            "$1: [redacted]",
        ),
        (r"sk-[A-Za-z0-9_\-]{8,}", "[redacted key]"),
        (r"(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{8,}", "[redacted token]"),
        (r"github_pat_[A-Za-z0-9_]+", "[redacted token]"),
        (r"sc_dev_(?:live|test)_[A-Za-z0-9_\-]+", "[redacted key]"),
        (r"AKIA[0-9A-Z]{16}", "[redacted key]"),
        (r"xox[baprs]-[A-Za-z0-9\-]+", "[redacted token]"),
        (r"(?i)Bearer\s+\S+", "Bearer [redacted]"),
        (
            r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
            "[id]",
        ),
        (r"\b[0-9a-fA-F]{32,}\b", "[redacted]"),
        (r"\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+){1,}\b", "[code]"),
        (r"(?i)system prompt\s*:\s*[^\n]+", "system prompt: [redacted]"),
        (r"(?i)SystemPrompt[A-Za-z]*", "[prompt]"),
        (r"(?i)\b[A-Za-z][A-Za-z0-9_\-]*\.md\b", "[asset]"),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn statuses_read_as_on_the_mac() {
        let running = Status::Running { port: 47391 };
        assert_eq!(status_title(&running), "Listening for Coincide Remote");
        assert_eq!(
            status_detail(&running, 0),
            "On port 47391. Scan the pairing code with Coincide Remote to add a device."
        );
        assert_eq!(
            status_detail(&running, 2),
            "On port 47391. 2 connected now."
        );
        assert_eq!(
            status_detail(&Status::Starting, 0),
            "Preparing the encrypted connection."
        );
        assert_eq!(
            status_title(&Status::Failed("x".into())),
            "Coincide Remote can’t start"
        );
        assert_eq!(
            status_detail(&Status::Failed("Port busy".into()), 0),
            "Port busy"
        );
        assert_eq!(status_dot(&Status::Off), Dot::Off);
        assert_eq!(kind_label(HostKind::TailscaleName), "MagicDNS");
    }

    #[test]
    fn devices_and_codes_count_down() {
        let now = 1_000_000_000.;
        assert_eq!(relative(now - 10_000., now), "now");
        assert_eq!(relative(now - 60_000., now), "1 minute ago");
        assert_eq!(relative(now - 7_200_000., now), "2 hours ago");
        assert_eq!(relative(now - 90_000_000., now), "yesterday");
        assert_eq!(relative(now - 3. * 86_400_000., now), "3 days ago");
        let device = Device {
            id: "D".into(),
            name: "Phone".into(),
            paired_at: now,
            last_seen_at: Some(now - 120_000.),
        };
        assert_eq!(device_detail(&device, true, now), "Connected now");
        assert_eq!(
            device_detail(&device, false, now),
            "Last connected 2 minutes ago"
        );
        let never = Device {
            last_seen_at: None,
            ..device
        };
        assert!(device_detail(&never, false, now).starts_with("Paired "));
        assert_eq!(
            countdown(now / 1000. + 299.5, now),
            ("Works once, for 4:59 more.".into(), true)
        );
        assert_eq!(
            countdown(now / 1000. + 61., now).0,
            "Works once, for 1:01 more."
        );
        assert_eq!(
            countdown(now / 1000. - 1., now),
            ("This code has expired.".into(), false)
        );
    }

    #[test]
    fn display_text_keeps_plain_reasons_and_drops_empty_ones() {
        assert_eq!(
            sanitize_display_text("GitHub pull requests are unavailable for this project."),
            Some("GitHub pull requests are unavailable for this project.".into())
        );
        assert_eq!(sanitize_display_text(""), None);
        assert_eq!(sanitize_display_text("   \n\t  "), None);
        assert_eq!(sanitize_display_text("a   b\n c"), Some("a b c".into()));
    }

    #[test]
    fn display_text_redacts_paths_tokens_and_addresses() {
        let redacted = sanitize_display_text(
            "open /Users/dylan/work/x failed: token ghp_abcdefghij1234567890 at https://github.com/foo",
        )
        .unwrap();
        assert!(!redacted.contains("/Users/dylan"));
        assert!(!redacted.contains("ghp_abcdefghij1234567890"));
        assert!(!redacted.contains("https://github.com/foo"));
        assert!(redacted.contains("[path]"));
        assert!(redacted.contains("[redacted token]"));
        assert!(redacted.contains("[address]"));
        let identified =
            sanitize_display_text("thread 123e4567-e89b-12d3-a456-426614174000 failed").unwrap();
        assert!(identified.contains("[id]"));
        assert!(!identified.contains("123e4567-e89b-12d3-a456-426614174000"));
    }
}
