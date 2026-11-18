import CoincideRemoteKit
import Foundation

public enum AssistantCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case codeMaintenance = "code-maintenance"
    case codeReviewSecurity = "code-review-security"
    case buildingFixing = "building-fixing"
    case repositoryIntelligence = "repository-intelligence"
    case gitWorkflowAutomation = "git-workflow-automation"
    case specializedProductivity = "specialized-productivity"

    public var displayName: String {
        switch self {
        case .codeMaintenance: return "Code Maintenance"
        case .codeReviewSecurity: return "Code Review & Security"
        case .buildingFixing: return "Building & Fixing"
        case .repositoryIntelligence: return "Repository Intelligence"
        case .gitWorkflowAutomation: return "Git & Workflow Automation"
        case .specializedProductivity: return "Specialized Engineering & Productivity"
        }
    }

    public var remote: RemoteAssistant.Category {
        switch self {
        case .codeMaintenance: return .codeMaintenance
        case .codeReviewSecurity: return .codeReviewSecurity
        case .buildingFixing: return .buildingFixing
        case .repositoryIntelligence: return .repositoryIntelligence
        case .gitWorkflowAutomation: return .gitWorkflowAutomation
        case .specializedProductivity: return .specializedProductivity
        }
    }

    public init?(remote: RemoteAssistant.Category) {
        switch remote {
        case .codeMaintenance: self = .codeMaintenance
        case .codeReviewSecurity: self = .codeReviewSecurity
        case .buildingFixing: self = .buildingFixing
        case .repositoryIntelligence: self = .repositoryIntelligence
        case .gitWorkflowAutomation: self = .gitWorkflowAutomation
        case .specializedProductivity: self = .specializedProductivity
        case .unknown: return nil
        }
    }
}
