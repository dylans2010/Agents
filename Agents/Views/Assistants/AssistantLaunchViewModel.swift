import CoincideRemoteKit
import Foundation
import Observation

public enum AssistantLaunchFieldKind: Hashable, Sendable {
    case text
    case multiLineText
    case directory
    case files
    case branch
    case pullRequest
    case issue
    case scope
    case constraints

    public var title: String {
        switch self {
        case .text, .multiLineText: return "Input"
        case .directory: return "Directory"
        case .files: return "Files"
        case .branch: return "Branch"
        case .pullRequest: return "Pull request"
        case .issue: return "Issue"
        case .scope: return "Scope"
        case .constraints: return "Constraints"
        }
    }
}

public struct AssistantLaunchField: Identifiable, Hashable, Sendable {
    public let id: Int
    public let requirement: String
    public let kind: AssistantLaunchFieldKind
    public let title: String
    public var text: String
    public var paths: [String]

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && paths.isEmpty
    }

    public var assembledValue: String {
        switch kind {
        case .directory, .files:
            return paths.joined(separator: ", ")
        case .text, .multiLineText, .branch, .pullRequest, .issue, .scope, .constraints:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

public struct AssistantLaunchResult: Hashable, Sendable {
    public let threadID: UUID?
    public let errorMessage: String?

    public init(threadID: UUID? = nil, errorMessage: String? = nil) {
        self.threadID = threadID
        self.errorMessage = errorMessage
    }
}

@Observable
@MainActor
public final class AssistantLaunchViewModel {
    public typealias Launcher = @MainActor (RemoteAssistant, String, UUID?) async -> AssistantLaunchResult

    public let assistant: AssistantDefinition
    public let projectID: UUID?
    public var fields: [AssistantLaunchField]
    public var task: String = ""
    public var extraInstructions: String = ""
    public private(set) var branches: [RemoteBranch]
    public private(set) var isLaunching: Bool = false
    public private(set) var launchError: String?
    public private(set) var launchedThreadID: UUID?

    private let launcher: Launcher

    public init(
        assistant: AssistantDefinition,
        projectID: UUID? = nil,
        branches: [RemoteBranch] = [],
        launcher: @escaping Launcher
    ) {
        self.assistant = assistant
        self.projectID = projectID
        self.branches = branches
        self.launcher = launcher
        var seenKinds: [AssistantLaunchFieldKind: Int] = [:]
        self.fields = (assistant.inputRequirements ?? []).enumerated().map { index, requirement in
            let kind = Self.kind(for: requirement)
            seenKinds[kind, default: 0] += 1
            let occurrence = seenKinds[kind] ?? 1
            let title = occurrence == 1 ? kind.title : "\(kind.title) \(occurrence)"
            return AssistantLaunchField(
                id: index,
                requirement: requirement,
                kind: kind,
                title: title,
                text: "",
                paths: []
            )
        }
    }

    public static func kind(for requirement: String) -> AssistantLaunchFieldKind {
        let text = requirement.lowercased()
        if text.contains("scope") {
            return .scope
        }
        if text.contains("pasted") || text.contains("stack trace") || text.contains("crash report")
            || text.contains("crash log") || text.contains("log text") || text.contains("staged diff")
            || text.contains("failing test output") || text.contains("failure report")
            || text.contains("description of") {
            return .multiLineText
        }
        if text.contains("pull request") {
            return .pullRequest
        }
        if text.contains("diff") {
            return .multiLineText
        }
        if text.contains("issue") {
            return .issue
        }
        if text.contains("branch") {
            return .branch
        }
        if text.contains("directory") {
            return .directory
        }
        if text.contains("file") || text.contains("lockfile") || text.contains("manifest") {
            return .files
        }
        if text.contains("constraint") || text.contains("must be preserved") || text.contains("must respect")
            || text.contains("whether deletion") || text.contains("whether to audit")
            || text.contains("severity threshold") {
            return .constraints
        }
        return .text
    }

    public var remoteAssistant: RemoteAssistant {
        RemoteAssistant(
            id: assistant.persistenceID ?? UUID(),
            name: assistant.name,
            description: assistant.description,
            icon: assistant.icon,
            category: assistant.category.remote,
            systemPrompt: assistant.systemPrompt,
            intendedTasks: assistant.intendedTasks,
            expectedOutputFormat: assistant.expectedOutputFormat,
            allowedTools: assistant.allowedTools,
            provider: assistant.modelConfig.provider,
            model: assistant.modelConfig.model,
            permissionProfile: assistant.permissionProfile.remote,
            inputRequirements: assistant.inputRequirements,
            version: assistant.version,
            source: assistant.isBuiltIn ? .unknown : .custom
        )
    }

    public var validationError: String? {
        if task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Describe the task for \(assistant.name)."
        }
        return nil
    }

    public var canLaunch: Bool {
        validationError == nil && !isLaunching
    }

    public var assembledTask: String {
        var sections: [String] = []
        sections.append(task.trimmingCharacters(in: .whitespacesAndNewlines))
        for field in fields {
            let value = field.assembledValue
            guard !value.isEmpty else { continue }
            sections.append("\(field.title): \(value)")
        }
        let extra = extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            sections.append("Additional instructions: \(extra)")
        }
        return sections.joined(separator: "\n\n")
    }

    public func updateBranches(_ branches: [RemoteBranch]) {
        self.branches = branches
    }

    public func setText(_ text: String, forField id: Int) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        fields[index].text = text
    }

    public func setPaths(_ paths: [String], forField id: Int) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        fields[index].paths = paths
    }

    public func removePath(_ path: String, fromField id: Int) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        fields[index].paths.removeAll { $0 == path }
    }

    public func launch() async {
        if let error = validationError {
            launchError = error
            return
        }
        isLaunching = true
        launchError = nil
        launchedThreadID = nil
        let result = await launcher(remoteAssistant, assembledTask, projectID)
        isLaunching = false
        launchedThreadID = result.threadID
        launchError = result.errorMessage
    }

    public static func appModelLauncher(appModel: AppModel) -> Launcher {
        { assistant, task, projectID in
            let previousThreadID = appModel.selectedThreadID
            let previousError = appModel.lastError
            await appModel.launchAssistant(assistant, task: task, in: projectID)
            if let selected = appModel.selectedThreadID,
               selected != previousThreadID,
               let threadID = UUID(uuidString: selected) {
                return AssistantLaunchResult(threadID: threadID, errorMessage: nil)
            }
            if let error = appModel.lastError, error != previousError {
                return AssistantLaunchResult(threadID: nil, errorMessage: error)
            }
            return AssistantLaunchResult(
                threadID: nil,
                errorMessage: "The assistant did not start a conversation. The runtime may not be connected."
            )
        }
    }
}
