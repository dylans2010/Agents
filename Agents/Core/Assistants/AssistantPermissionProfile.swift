import CoincideRemoteKit
import Foundation

public enum AssistantPermissionProfile: String, Codable, Hashable, Sendable, CaseIterable {
    case readOnly = "read-only"
    case workspaceModify = "workspace-modify"
    case terminal
    case approvalRequired = "approval-required"

    public var remote: RemoteAssistant.PermissionProfile {
        switch self {
        case .readOnly: return .readOnly
        case .workspaceModify: return .workspaceModify
        case .terminal: return .terminal
        case .approvalRequired: return .approvalRequired
        }
    }

    public init?(remote: RemoteAssistant.PermissionProfile) {
        switch remote {
        case .readOnly: self = .readOnly
        case .workspaceModify: self = .workspaceModify
        case .terminal: self = .terminal
        case .approvalRequired: self = .approvalRequired
        case .unknown: return nil
        }
    }
}
