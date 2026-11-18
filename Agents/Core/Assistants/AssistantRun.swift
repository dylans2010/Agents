import Foundation

public enum AssistantRunStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case queued
    case running
    case awaitingApproval
    case completed
    case failed
    case cancelled
    case unknown

    public var title: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .awaitingApproval: return "Awaiting Approval"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unknown"
        }
    }

    public static func from(runtimeStatus: String) -> AssistantRunStatus {
        switch runtimeStatus {
        case "running": return .running
        case "completed": return .completed
        case "failed": return .failed
        case "cancelled": return .cancelled
        default: return .unknown
        }
    }

    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }

    public init(workerStatus: String) {
        switch workerStatus {
        case "queued":
            self = .queued
        case "running":
            self = .running
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "cancelled":
            self = .cancelled
        default:
            self = .unknown
        }
    }

    public init(turnOutcome: String) {
        switch turnOutcome {
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "interrupted":
            self = .cancelled
        default:
            self = .running
        }
    }

    public init(unseen: String) {
        switch unseen {
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        default:
            self = .running
        }
    }
}
