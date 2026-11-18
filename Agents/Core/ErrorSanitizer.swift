import CoincideRemoteKit
import Foundation

public enum ErrorSanitizer {

    public struct SanitizedError: Sendable {
        public let kind: String
        public let displayMessage: String
        public let diagnosticMessage: String
    }

    public static func sanitize(_ error: Error) -> SanitizedError {
        let kind = errorKind(for: error)
        let display = displayMessage(for: error)
        return SanitizedError(kind: kind, displayMessage: display, diagnosticMessage: "[\(kind)] \(display)")
    }

    public static func errorKind(for error: Error) -> String {
        if let runtimeError = error as? AgentsRuntimeError {
            switch runtimeError {
            case .openFailed:
                return "openFailed"
            case .runtimeClosed:
                return "runtimeClosed"
            case .invalidJSON:
                return "invalidJSON"
            case .remoteFailure(let remoteError):
                return remoteError.code.rawValue
            case .desktopFailure:
                return "desktopFailure"
            case .unexpectedResult:
                return "unexpectedResult"
            }
        }
        if let remoteError = error as? RemoteError {
            return remoteError.code.rawValue
        }
        return String(describing: type(of: error))
    }

    public static func displayMessage(for error: Error) -> String {
        sanitizeText(error.localizedDescription)
    }

    public static func diagnosticMessage(for error: Error) -> String {
        "[\(errorKind(for: error))] \(sanitizeText(error.localizedDescription))"
    }

    public static func sanitizeText(_ text: String) -> String {
        var result = text
        result = redactPaths(in: result)
        result = redactCredentials(in: result)
        result = redactIdentifiers(in: result)
        result = redactTransport(in: result)
        result = redactPromptFragments(in: result)
        result = collapseWhitespace(in: result)
        guard !result.isEmpty else {
            return "Something went wrong. Try again."
        }
        return appendActionableHint(to: result)
    }

    private static func replacing(_ text: String, pattern: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func redactPaths(in text: String) -> String {
        var result = text
        let home = NSHomeDirectory()
        if !home.isEmpty && home != "/" {
            result = result.replacingOccurrences(of: home, with: "~")
        }
        result = replacing(result, pattern: #"/Users/[^/\s]+"#, with: "~")
        result = replacing(result, pattern: #"~/Library/Application Support[^\s,;:]*"#, with: "[application support]")
        result = replacing(result, pattern: #"~/Library/Caches[^\s,;:]*"#, with: "[cache]")
        result = replacing(result, pattern: #"~/Library/Logs[^\s,;:]*"#, with: "[logs]")
        result = replacing(result, pattern: #"~/.config[^\s,;:]*"#, with: "[config]")
        result = replacing(result, pattern: #"~/.curlrc[^\s,;:]*"#, with: "[config]")
        result = replacing(result, pattern: #"~/.ssh[^\s,;:]*"#, with: "[config]")
        result = replacing(result, pattern: #"file://\S+"#, with: "[path]")
        result = replacing(result, pattern: #"(?:/private)?/var/folders/\S+"#, with: "[temporary directory]")
        result = replacing(result, pattern: #"(?:/private)?/tmp/\S+"#, with: "[temporary directory]")
        result = replacing(result, pattern: #"SystemAssets/\S+"#, with: "[asset]")
        result = replacing(result, pattern: #"~/\S+"#, with: "[path]")
        result = replacing(result, pattern: #"/(?:Users|var|tmp|private|etc|opt|usr|Library|System|Applications|Volumes)/[^\s,;:\"']*"#, with: "[path]")
        return result
    }

    private static func redactCredentials(in text: String) -> String {
        var result = text
        result = replacing(result, pattern: #"(?i)://[^/\s:]+:[^/\s@]+@"#, with: "://[redacted]@")
        result = replacing(result, pattern: #"(?i)Authorization\s*:\s*(?:Bearer\s+)?\S+"#, with: "Authorization: [redacted]")
        result = replacing(result, pattern: #"(?i)(api[_-]?key|apikey|access[_-]?token|auth[_-]?token|token|client[_-]?secret|secret|password|passwd)\s*[:=]\s*\S+"#, with: "$1: [redacted]")
        result = replacing(result, pattern: #"sk-[A-Za-z0-9_\-]{8,}"#, with: "[redacted key]")
        result = replacing(result, pattern: #"(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{8,}"#, with: "[redacted token]")
        result = replacing(result, pattern: #"github_pat_[A-Za-z0-9_]+"#, with: "[redacted token]")
        result = replacing(result, pattern: #"sc_dev_(?:live|test)_[A-Za-z0-9_\-]+"#, with: "[redacted key]")
        result = replacing(result, pattern: #"AKIA[0-9A-Z]{16}"#, with: "[redacted key]")
        result = replacing(result, pattern: #"xox[baprs]-[A-Za-z0-9\-]+"#, with: "[redacted token]")
        result = replacing(result, pattern: #"(?i)Bearer\s+\S+"#, with: "Bearer [redacted]")
        return result
    }

    private static func redactIdentifiers(in text: String) -> String {
        var result = text
        result = replacing(result, pattern: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#, with: "[id]")
        result = replacing(result, pattern: #"\b[0-9a-f]{32,}\b"#, with: "[redacted]")
        result = replacing(result, pattern: #"\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+){1,}\b"#, with: "[code]")
        return result
    }

    private static func redactTransport(in text: String) -> String {
        var result = text
        result = replacing(result, pattern: #"(?i)(?:ws|wss|http|https|ftp)://[^\s]+"#, with: "[address]")
        result = replacing(result, pattern: #"(?i)\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"#, with: "[address]")
        result = replacing(result, pattern: #"(?i)\blocalhost(?::\d+)?\b"#, with: "[local address]")
        result = replacing(result, pattern: #"(?i)\btransport\s*[:=]\s*\S+"#, with: "transport: [redacted]")
        result = replacing(result, pattern: #"(?i)\bport\s+\d+\b"#, with: "port [redacted]")
        result = replacing(result, pattern: #"(?i)\bunix\s+socket\s+\S+"#, with: "unix socket [redacted]")
        result = replacing(result, pattern: #"(?i)\bfd\s+\d+\b"#, with: "fd [redacted]")
        return result
    }

    private static func redactPromptFragments(in text: String) -> String {
        var result = text
        result = replacing(result, pattern: #"(?i)system prompt\s*:\s*[^\n]+"#, with: "system prompt: [redacted]")
        result = replacing(result, pattern: #"(?i)SystemPrompt[A-Za-z]*"#, with: "[prompt]")
        result = replacing(result, pattern: #"(?i)\b[A-Za-z][A-Za-z0-9_\-]*\.md\b"#, with: "[asset]")
        return result
    }

    private static func collapseWhitespace(in text: String) -> String {
        let collapsed = replacing(text, pattern: #"\s+"#, with: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendActionableHint(to text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("try again") {
            return text
        }
        if lower.contains("connection") || lower.contains("network") || lower.contains("unreachable")
            || lower.contains("timed out") || lower.contains("timeout") || lower.contains("offline")
            || lower.contains("refused") || lower.contains("reset by peer") || lower.contains("dns")
            || lower.contains("internet") || lower.contains("couldn't reach") || lower.contains("could not reach") {
            return text + " Check your connection and try again."
        }
        if lower.contains("permission") || lower.contains("denied") || lower.contains("not authorized")
            || lower.contains("unauthorized") || lower.contains("forbidden") || lower.contains("not allowed") {
            return text + " Check permissions and try again."
        }
        if lower.contains("not found") {
            return text + " Check that the item still exists and try again."
        }
        if lower.contains("rate limit") {
            return text + " Wait a moment and try again."
        }
        return text
    }
}
