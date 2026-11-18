import Foundation

public enum DaemonConnectionStatus: Equatable, Sendable {
    case connected
    case checking
    case unreachable(detail: String)
    case misconfigured(detail: String)

    public static let pollFailuresBeforeUnreachable = 2

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var title: String {
        switch self {
        case .connected:
            "Agents runtime connected"
        case .checking:
            "Connecting to the Agents runtime…"
        case .unreachable:
            "Agents runtime unreachable"
        case .misconfigured:
            "Agents runtime misconfigured"
        }
    }

    public var detail: String? {
        switch self {
        case .connected, .checking:
            nil
        case .unreachable(let detail), .misconfigured(let detail):
            detail
        }
    }

    public static func status(
        runtimeOpen: Bool,
        consecutivePollFailures: Int,
        lastPollError: String?,
        openFailure: String?
    ) -> DaemonConnectionStatus {
        if runtimeOpen {
            if consecutivePollFailures >= pollFailuresBeforeUnreachable, let lastPollError {
                return .unreachable(detail: lastPollError)
            }
            return .connected
        }
        if let openFailure {
            return classifyOpenFailure(openFailure)
        }
        return .checking
    }

    public static func classifyOpenFailure(_ message: String) -> DaemonConnectionStatus {
        if misconfiguredOpenFailureMarkers.contains(where: message.contains) {
            return .misconfigured(detail: message)
        }
        return .unreachable(detail: message)
    }

    private static let misconfiguredOpenFailureMarkers = [
        "Data directory",
        "HOME is missing",
        "must be absolute",
        "not a symlink",
        "Failed to create data directory",
    ]
}
