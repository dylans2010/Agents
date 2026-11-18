import CoincideRemoteKit
import Foundation

public enum AssistantRunStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case queued
    case running
    case awaitingApproval
    case completed
    case failed
    case cancelled

    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }

    public init(workerStatus: String) {
        switch workerStatus {
        case "completed":
            self = .completed
        case "failed":
            self = .failed
        case "cancelled":
            self = .cancelled
        default:
            self = .running
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

public enum AssistantRunMode: String, Codable, Hashable, Sendable {
    case foreground
    case background
}

public struct AssistantToolExecution: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var category: String?
    public var status: String?
    public var startedAt: Date
    public var completedAt: Date?

    public init(id: UUID, title: String, category: String? = nil, status: String? = nil, startedAt: Date, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public init(item: RemoteItem) {
        self.id = item.id
        self.title = item.title ?? item.text
        self.category = item.category
        self.status = item.status
        self.startedAt = item.createdAt
        self.completedAt = item.completedAt
    }

    public var isTerminal: Bool {
        status == "completed" || status == "failed" || status == "declined"
    }
}

public struct AssistantApproval: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String?
    public var detail: String?
    public var options: [RemoteApproval.Option]
    public var resolution: String?
    public var createdAt: Date

    public init(id: UUID, title: String? = nil, detail: String? = nil, options: [RemoteApproval.Option] = [], resolution: String? = nil, createdAt: Date) {
        self.id = id
        self.title = title
        self.detail = detail
        self.options = options
        self.resolution = resolution
        self.createdAt = createdAt
    }

    public init(item: RemoteItem) {
        self.id = item.id
        self.title = item.title
        self.detail = item.detail
        self.options = item.approval?.options ?? []
        self.resolution = item.approval?.resolution
        self.createdAt = item.createdAt
    }

    public var isPending: Bool {
        resolution == nil
    }
}

public struct AssistantGitSnapshot: Codable, Hashable, Sendable {
    public var isRepository: Bool
    public var branch: String?
    public var ahead: Int
    public var behind: Int
    public var changedFiles: Int
    public var diffFiles: [RemoteDiff.File]

    public init(isRepository: Bool, branch: String? = nil, ahead: Int = 0, behind: Int = 0, changedFiles: Int = 0, diffFiles: [RemoteDiff.File] = []) {
        self.isRepository = isRepository
        self.branch = branch
        self.ahead = ahead
        self.behind = behind
        self.changedFiles = changedFiles
        self.diffFiles = diffFiles
    }

    public init(gitState: RemoteGitState, diff: RemoteDiff) {
        self.isRepository = gitState.isRepository
        self.branch = gitState.branch
        self.ahead = gitState.ahead
        self.behind = gitState.behind
        self.changedFiles = gitState.changedFiles
        self.diffFiles = diff.files
    }
}

public struct AssistantRun: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var assistantID: String
    public var assistantName: String
    public var mode: AssistantRunMode
    public var task: String
    public var inputs: [String: String]
    public var projectID: UUID?
    public var threadID: UUID?
    public var workerID: String?
    public var workerThreadID: UUID?
    public var workerName: String?
    public var provider: String?
    public var model: String?
    public var toolset: AgentToolset
    public var allowedTools: [String]?
    public var permissionProfile: AssistantPermissionProfile
    public var systemPromptText: String
    public var systemPromptIncludedDocuments: [String]
    public var systemPromptOmittedDocuments: [String]
    public var systemPromptEstimatedTokens: Int
    public var systemPromptIsBaselineFallback: Bool
    public var startedAt: Date
    public var endedAt: Date?
    public var status: AssistantRunStatus
    public var lastActivity: String?
    public var lastTurnSerial: UInt64
    public var seenItemIndex: Int
    public var toolExecutions: [AssistantToolExecution]
    public var filesModified: [RemoteChangedFile]
    public var gitSnapshot: AssistantGitSnapshot?
    public var output: String?
    public var errors: [String]
    public var approvals: [AssistantApproval]
    public var activityLog: [String]
    public var cancellationReason: String?

    public init(
        id: UUID = UUID(),
        assistantID: String,
        assistantName: String,
        mode: AssistantRunMode,
        task: String,
        inputs: [String: String] = [:],
        projectID: UUID? = nil,
        threadID: UUID? = nil,
        workerID: String? = nil,
        workerThreadID: UUID? = nil,
        workerName: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        toolset: AgentToolset = .system,
        allowedTools: [String]? = nil,
        permissionProfile: AssistantPermissionProfile = .readOnly,
        systemPromptText: String = "",
        systemPromptIncludedDocuments: [String] = [],
        systemPromptOmittedDocuments: [String] = [],
        systemPromptEstimatedTokens: Int = 0,
        systemPromptIsBaselineFallback: Bool = false,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: AssistantRunStatus = .queued,
        lastActivity: String? = nil,
        lastTurnSerial: UInt64 = 0,
        seenItemIndex: Int = -1,
        toolExecutions: [AssistantToolExecution] = [],
        filesModified: [RemoteChangedFile] = [],
        gitSnapshot: AssistantGitSnapshot? = nil,
        output: String? = nil,
        errors: [String] = [],
        approvals: [AssistantApproval] = [],
        activityLog: [String] = [],
        cancellationReason: String? = nil
    ) {
        self.id = id
        self.assistantID = assistantID
        self.assistantName = assistantName
        self.mode = mode
        self.task = task
        self.inputs = inputs
        self.projectID = projectID
        self.threadID = threadID
        self.workerID = workerID
        self.workerThreadID = workerThreadID
        self.workerName = workerName
        self.provider = provider
        self.model = model
        self.toolset = toolset
        self.allowedTools = allowedTools
        self.permissionProfile = permissionProfile
        self.systemPromptText = systemPromptText
        self.systemPromptIncludedDocuments = systemPromptIncludedDocuments
        self.systemPromptOmittedDocuments = systemPromptOmittedDocuments
        self.systemPromptEstimatedTokens = systemPromptEstimatedTokens
        self.systemPromptIsBaselineFallback = systemPromptIsBaselineFallback
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.lastActivity = lastActivity
        self.lastTurnSerial = lastTurnSerial
        self.seenItemIndex = seenItemIndex
        self.toolExecutions = toolExecutions
        self.filesModified = filesModified
        self.gitSnapshot = gitSnapshot
        self.output = output
        self.errors = errors
        self.approvals = approvals
        self.activityLog = activityLog
        self.cancellationReason = cancellationReason
    }

    public init(worker: WorkerRecord, assistant: AssistantDefinition) {
        self.id = UUID(uuidString: worker.id) ?? UUID()
        self.assistantID = assistant.id
        self.assistantName = assistant.name
        self.mode = .background
        self.task = worker.task
        self.inputs = [:]
        self.projectID = nil
        self.threadID = UUID(uuidString: worker.threadId)
        self.workerID = worker.id
        self.workerThreadID = UUID(uuidString: worker.threadId)
        self.workerName = worker.name
        self.provider = worker.provider.isEmpty ? nil : worker.provider
        self.model = nil
        self.toolset = .system
        self.allowedTools = assistant.allowedTools
        self.permissionProfile = assistant.permissionProfile
        self.systemPromptText = ""
        self.systemPromptIncludedDocuments = []
        self.systemPromptOmittedDocuments = []
        self.systemPromptEstimatedTokens = 0
        self.systemPromptIsBaselineFallback = false
        self.startedAt = Date(timeIntervalSince1970: worker.startedAt)
        self.endedAt = worker.completedAt.map { Date(timeIntervalSince1970: $0) }
        self.status = AssistantRunStatus(workerStatus: worker.status)
        self.lastActivity = worker.progress?.stage
        self.lastTurnSerial = 0
        self.seenItemIndex = max(worker.transcriptStart + worker.transcriptItems - 1, -1)
        self.toolExecutions = []
        self.filesModified = []
        self.gitSnapshot = nil
        self.output = worker.result
        self.errors = worker.error.map { [$0] } ?? []
        self.approvals = []
        self.activityLog = []
        self.cancellationReason = worker.status == "cancelled" ? "Cancelled by user or runtime" : nil
    }

    public var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    public var observedThreadID: UUID? {
        workerThreadID ?? threadID
    }

    public var isTerminal: Bool {
        status.isTerminal
    }

    public var pendingApprovals: [AssistantApproval] {
        approvals.filter(\.isPending)
    }

    public mutating func recordActivity(_ line: String) {
        activityLog.append(line)
        lastActivity = line
    }
}

public struct AssistantRunReport: Codable, Hashable, Sendable {
    public var runID: UUID
    public var assistantID: String
    public var assistantName: String
    public var mode: AssistantRunMode
    public var status: AssistantRunStatus
    public var task: String
    public var inputs: [String: String]
    public var projectID: UUID?
    public var threadID: UUID?
    public var workerID: String?
    public var workerThreadID: UUID?
    public var provider: String?
    public var model: String?
    public var toolset: AgentToolset
    public var allowedTools: [String]?
    public var permissionProfile: AssistantPermissionProfile
    public var startedAt: Date
    public var endedAt: Date?
    public var durationSeconds: TimeInterval?
    public var systemPromptIncludedDocuments: [String]
    public var systemPromptOmittedDocuments: [String]
    public var systemPromptEstimatedTokens: Int
    public var systemPromptIsBaselineFallback: Bool
    public var toolExecutions: [AssistantToolExecution]
    public var filesModified: [RemoteChangedFile]
    public var gitSnapshot: AssistantGitSnapshot?
    public var output: String?
    public var errors: [String]
    public var approvals: [AssistantApproval]
    public var activityLog: [String]
    public var cancellationReason: String?

    public init(run: AssistantRun) {
        self.runID = run.id
        self.assistantID = run.assistantID
        self.assistantName = run.assistantName
        self.mode = run.mode
        self.status = run.status
        self.task = run.task
        self.inputs = run.inputs
        self.projectID = run.projectID
        self.threadID = run.threadID
        self.workerID = run.workerID
        self.workerThreadID = run.workerThreadID
        self.provider = run.provider
        self.model = run.model
        self.toolset = run.toolset
        self.allowedTools = run.allowedTools
        self.permissionProfile = run.permissionProfile
        self.startedAt = run.startedAt
        self.endedAt = run.endedAt
        self.durationSeconds = run.duration
        self.systemPromptIncludedDocuments = run.systemPromptIncludedDocuments
        self.systemPromptOmittedDocuments = run.systemPromptOmittedDocuments
        self.systemPromptEstimatedTokens = run.systemPromptEstimatedTokens
        self.systemPromptIsBaselineFallback = run.systemPromptIsBaselineFallback
        self.toolExecutions = run.toolExecutions
        self.filesModified = run.filesModified
        self.gitSnapshot = run.gitSnapshot
        self.output = run.output
        self.errors = run.errors
        self.approvals = run.approvals
        self.activityLog = run.activityLog
        self.cancellationReason = run.cancellationReason
    }
}

public enum AssistantRunEvent: Sendable {
    case started(AssistantRun)
    case activity(AssistantRun, String)
    case toolCall(AssistantRun, AssistantToolExecution)
    case approvalNeeded(AssistantRun, AssistantApproval)
    case output(AssistantRun, String)
    case completed(AssistantRunReport)
    case failed(AssistantRunReport, AssistantRunError)
    case cancelled(AssistantRun)

    public var runID: UUID {
        switch self {
        case .started(let run), .activity(let run, _), .toolCall(let run, _), .approvalNeeded(let run, _), .output(let run, _):
            return run.id
        case .completed(let report):
            return report.runID
        case .failed(let report, _):
            return report.runID
        case .cancelled(let run):
            return run.id
        }
    }
}

public enum AssistantRunError: Error, Equatable, Sendable, LocalizedError {
    case unknownAssistant(id: String)
    case invalidDefinition(id: String, issues: [AssistantValidationIssue])
    case emptyTask
    case taskTooLong(limit: Int)
    case workerNameTooLong(limit: Int)
    case unknownTools(names: [String])
    case runNotFound(id: UUID)
    case runLimitReached(limit: Int)
    case runtimeFailure(message: String)
    case cancellationUnsupported(reason: String)
    case workerSpawnFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .unknownAssistant(let id):
            return "Unknown assistant '\(id)'"
        case .invalidDefinition(let id, let issues):
            return "Assistant '\(id)' is invalid: \(issues.map { String(describing: $0) }.joined(separator: ", "))"
        case .emptyTask:
            return "Task text is empty"
        case .taskTooLong(let limit):
            return "Task exceeds the \(limit)-character worker task limit"
        case .workerNameTooLong(let limit):
            return "Worker name exceeds the \(limit)-character limit"
        case .unknownTools(let names):
            return "Unknown tools: \(names.joined(separator: ", "))"
        case .runNotFound(let id):
            return "No run with id \(id.uuidString)"
        case .runLimitReached(let limit):
            return "Concurrent run limit of \(limit) reached"
        case .runtimeFailure(let message):
            return message
        case .cancellationUnsupported(let reason):
            return "Cancellation unsupported: \(reason)"
        case .workerSpawnFailed(let message):
            return "Worker spawn failed: \(message)"
        }
    }
}
