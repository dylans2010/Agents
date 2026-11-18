import CoincideRemoteKit
import Foundation

public protocol AssistantTaskRuntime: Sendable {
    func tasksList() async throws -> JSONValue
    func tasksSave(task: JSONValue, baseline: String) async throws -> JSONValue
    func tasksDelete(taskId: String, baseline: String) async throws -> JSONValue
    func tasksRunNow(taskId: String, parentThreadId: String) async throws -> JSONValue
    func tasksDue() async throws -> JSONValue
    func tasksMarkMissed(taskId: String, reason: String) async throws -> JSONValue
    func tasksRecover() async throws -> JSONValue
    func createParentThread(projectID: UUID) async throws -> UUID
    func deleteParentThread(_ threadID: UUID) async throws
    func listAssistants() async throws -> RemoteAssistants
    func fetchWorkspace(includeArchived: Bool) async throws -> RemoteWorkspace
}

extension AgentsRuntimeClient: AssistantTaskRuntime {
    public func createParentThread(projectID: UUID) async throws -> UUID {
        try await newThread(projectID: projectID)
    }

    public func deleteParentThread(_ threadID: UUID) async throws {
        _ = try await deleteThreadPermanently(threadID: threadID.uuidString)
    }
}

private func decodeTaskJSONValue<T: Decodable>(_ value: JSONValue, as type: T.Type) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(type, from: data)
}

private func encodeTaskJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(JSONValue.self, from: data)
}

public enum AssistantTaskError: Error, LocalizedError, Sendable, Equatable {
    case staleBaseline
    case taskNotFound(id: UUID)
    case invalidResult(String)
    case runRejected(String)
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .staleBaseline:
            "Automated task document changed; reload before saving"
        case .taskNotFound(let id):
            "Automated task \(id.uuidString) no longer exists."
        case .invalidResult(let detail):
            detail
        case .runRejected(let reason):
            reason
        case .underlying(let detail):
            detail
        }
    }
}

public struct AssistantTaskExecutionLimits: Codable, Hashable, Sendable {
    public var maxRuns: Int?
    public var maxConcurrent: Int

    public init(maxRuns: Int? = nil, maxConcurrent: Int = 1) {
        self.maxRuns = maxRuns
        self.maxConcurrent = maxConcurrent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxRuns = try container.decodeIfPresent(Int.self, forKey: .maxRuns)
        maxConcurrent = try container.decodeIfPresent(Int.self, forKey: .maxConcurrent) ?? 1
    }
}

public struct AssistantTaskNotificationPrefs: Codable, Hashable, Sendable {
    public var onSuccess: Bool
    public var onFailure: Bool
    public var onMissed: Bool

    public init(onSuccess: Bool = false, onFailure: Bool = true, onMissed: Bool = true) {
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        self.onMissed = onMissed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        onSuccess = try container.decodeIfPresent(Bool.self, forKey: .onSuccess) ?? false
        onFailure = try container.decodeIfPresent(Bool.self, forKey: .onFailure) ?? true
        onMissed = try container.decodeIfPresent(Bool.self, forKey: .onMissed) ?? true
    }
}

public struct AssistantTaskFailurePolicy: Codable, Hashable, Sendable {
    public var behavior: String
    public var maxRetries: Int
    public var backoffSeconds: Int

    public init(behavior: String = "retryWithBackoff", maxRetries: Int = 3, backoffSeconds: Int = 300) {
        self.behavior = behavior
        self.maxRetries = maxRetries
        self.backoffSeconds = backoffSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        behavior = try container.decodeIfPresent(String.self, forKey: .behavior) ?? "retryWithBackoff"
        maxRetries = try container.decodeIfPresent(Int.self, forKey: .maxRetries) ?? 3
        backoffSeconds = try container.decodeIfPresent(Int.self, forKey: .backoffSeconds) ?? 300
    }
}

public struct AssistantTaskApprovalRequirements: Codable, Hashable, Sendable {
    public var required: Bool
    public var actions: [String]

    public init(required: Bool = false, actions: [String] = []) {
        self.required = required
        self.actions = actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        actions = try container.decodeIfPresent([String].self, forKey: .actions) ?? []
    }
}

public struct AssistantTaskSchedule: Hashable, Sendable {
    public var kind: String
    public var timeZoneID: String
    public var date: JSONValue
    public var hour: Int
    public var minute: Int
    public var weekday: Int
    public var weekdays: [Int]?
    public var intervalMinutes: Int?
    public var cron: String?
    public var extra: [String: JSONValue]

    public init(
        kind: String = "daily", timeZoneID: String = "UTC", date: JSONValue = .null,
        hour: Int = 9, minute: Int = 0, weekday: Int = 1, weekdays: [Int]? = nil,
        intervalMinutes: Int? = nil, cron: String? = nil, extra: [String: JSONValue] = [:]
    ) {
        self.kind = kind
        self.timeZoneID = timeZoneID
        self.date = date
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
        self.weekdays = weekdays
        self.intervalMinutes = intervalMinutes
        self.cron = cron
        self.extra = extra
    }
}

extension AssistantTaskSchedule: Codable {
    private static let knownKeys: Set<String> = [
        "kind", "timeZoneID", "date", "hour", "minute", "weekday", "weekdays", "intervalMinutes", "cron",
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        kind = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("kind")) ?? "daily"
        timeZoneID = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("timeZoneID")) ?? "UTC"
        date = try container.decodeIfPresent(JSONValue.self, forKey: AnyCodingKey("date")) ?? .null
        hour = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("hour")) ?? 9
        minute = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("minute")) ?? 0
        weekday = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("weekday")) ?? 1
        weekdays = try container.decodeIfPresent([Int].self, forKey: AnyCodingKey("weekdays"))
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("intervalMinutes"))
        cron = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("cron"))
        var extra: [String: JSONValue] = [:]
        for key in container.allKeys where !Self.knownKeys.contains(key.stringValue) {
            if let value = try? container.decode(JSONValue.self, forKey: key) {
                extra[key.stringValue] = value
            }
        }
        self.extra = extra
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(kind, forKey: AnyCodingKey("kind"))
        try container.encode(timeZoneID, forKey: AnyCodingKey("timeZoneID"))
        try container.encode(date, forKey: AnyCodingKey("date"))
        try container.encode(hour, forKey: AnyCodingKey("hour"))
        try container.encode(minute, forKey: AnyCodingKey("minute"))
        try container.encode(weekday, forKey: AnyCodingKey("weekday"))
        try container.encodeIfPresent(weekdays, forKey: AnyCodingKey("weekdays"))
        try container.encodeIfPresent(intervalMinutes, forKey: AnyCodingKey("intervalMinutes"))
        try container.encodeIfPresent(cron, forKey: AnyCodingKey("cron"))
        for (key, value) in extra {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }
}

public struct AssistantTaskRecord: Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var assistantID: UUID
    public var workspaceID: UUID
    public var inputs: JSONValue
    public var schedule: AssistantTaskSchedule
    public var trigger: String
    public var enabled: Bool
    public var paused: Bool
    public var limits: AssistantTaskExecutionLimits
    public var notifications: AssistantTaskNotificationPrefs
    public var failurePolicy: AssistantTaskFailurePolicy
    public var approval: AssistantTaskApprovalRequirements
    public var runCount: Int
    public var lastRunAt: Int64?
    public var lastOutcome: String?
    public var lastMessage: String?
    public var lastMissedAt: Int64?
    public var missedCount: Int
    public var lastWorkerID: String?
    public var nextRunAt: Int64?
    public var createdAt: Int64
    public var updatedAt: Int64
    public var extra: [String: JSONValue]

    public init(
        id: UUID, name: String, assistantID: UUID, workspaceID: UUID,
        inputs: JSONValue = .object([:]), schedule: AssistantTaskSchedule = AssistantTaskSchedule(),
        trigger: String = "timer", enabled: Bool = true, paused: Bool = false,
        limits: AssistantTaskExecutionLimits = AssistantTaskExecutionLimits(),
        notifications: AssistantTaskNotificationPrefs = AssistantTaskNotificationPrefs(),
        failurePolicy: AssistantTaskFailurePolicy = AssistantTaskFailurePolicy(),
        approval: AssistantTaskApprovalRequirements = AssistantTaskApprovalRequirements(),
        runCount: Int = 0, lastRunAt: Int64? = nil, lastOutcome: String? = nil,
        lastMessage: String? = nil, lastMissedAt: Int64? = nil, missedCount: Int = 0,
        lastWorkerID: String? = nil, nextRunAt: Int64? = nil, createdAt: Int64 = 0,
        updatedAt: Int64 = 0, extra: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.assistantID = assistantID
        self.workspaceID = workspaceID
        self.inputs = inputs
        self.schedule = schedule
        self.trigger = trigger
        self.enabled = enabled
        self.paused = paused
        self.limits = limits
        self.notifications = notifications
        self.failurePolicy = failurePolicy
        self.approval = approval
        self.runCount = runCount
        self.lastRunAt = lastRunAt
        self.lastOutcome = lastOutcome
        self.lastMessage = lastMessage
        self.lastMissedAt = lastMissedAt
        self.missedCount = missedCount
        self.lastWorkerID = lastWorkerID
        self.nextRunAt = nextRunAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.extra = extra
    }

    public var isActive: Bool {
        enabled && !paused
    }

    public init(json: JSONValue) throws {
        self = try decodeTaskJSONValue(json, as: Self.self)
    }

    public func encoded() throws -> JSONValue {
        try encodeTaskJSONValue(self)
    }
}

extension AssistantTaskRecord: Codable {
    private static let knownKeys: Set<String> = [
        "id", "name", "assistantId", "workspaceId", "inputs", "schedule", "trigger", "enabled",
        "paused", "limits", "notifications", "failurePolicy", "approval", "runCount", "lastRunAt",
        "lastOutcome", "lastMessage", "lastMissedAt", "missedCount", "lastWorkerId", "nextRunAt",
        "createdAt", "updatedAt",
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        id = try container.decode(UUID.self, forKey: AnyCodingKey("id"))
        name = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("name")) ?? ""
        assistantID = try container.decode(UUID.self, forKey: AnyCodingKey("assistantId"))
        workspaceID = try container.decode(UUID.self, forKey: AnyCodingKey("workspaceId"))
        inputs = try container.decodeIfPresent(JSONValue.self, forKey: AnyCodingKey("inputs")) ?? .object([:])
        schedule = try container.decodeIfPresent(AssistantTaskSchedule.self, forKey: AnyCodingKey("schedule")) ?? AssistantTaskSchedule()
        trigger = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("trigger")) ?? "timer"
        enabled = try container.decodeIfPresent(Bool.self, forKey: AnyCodingKey("enabled")) ?? true
        paused = try container.decodeIfPresent(Bool.self, forKey: AnyCodingKey("paused")) ?? false
        limits = try container.decodeIfPresent(AssistantTaskExecutionLimits.self, forKey: AnyCodingKey("limits")) ?? AssistantTaskExecutionLimits()
        notifications = try container.decodeIfPresent(AssistantTaskNotificationPrefs.self, forKey: AnyCodingKey("notifications")) ?? AssistantTaskNotificationPrefs()
        failurePolicy = try container.decodeIfPresent(AssistantTaskFailurePolicy.self, forKey: AnyCodingKey("failurePolicy")) ?? AssistantTaskFailurePolicy()
        approval = try container.decodeIfPresent(AssistantTaskApprovalRequirements.self, forKey: AnyCodingKey("approval")) ?? AssistantTaskApprovalRequirements()
        runCount = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("runCount")) ?? 0
        lastRunAt = try container.decodeIfPresent(Int64.self, forKey: AnyCodingKey("lastRunAt"))
        lastOutcome = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("lastOutcome"))
        lastMessage = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("lastMessage"))
        lastMissedAt = try container.decodeIfPresent(Int64.self, forKey: AnyCodingKey("lastMissedAt"))
        missedCount = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("missedCount")) ?? 0
        lastWorkerID = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("lastWorkerId"))
        nextRunAt = try container.decodeIfPresent(Int64.self, forKey: AnyCodingKey("nextRunAt"))
        createdAt = try container.decodeIfPresent(Int64.self, forKey: AnyCodingKey("createdAt")) ?? 0
        updatedAt = try container.decodeIfPresent(Int64.self, forKey: AnyCodingKey("updatedAt")) ?? 0
        var extra: [String: JSONValue] = [:]
        for key in container.allKeys where !Self.knownKeys.contains(key.stringValue) {
            if let value = try? container.decode(JSONValue.self, forKey: key) {
                extra[key.stringValue] = value
            }
        }
        self.extra = extra
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(id.uuidString, forKey: AnyCodingKey("id"))
        try container.encode(name, forKey: AnyCodingKey("name"))
        try container.encode(assistantID.uuidString, forKey: AnyCodingKey("assistantId"))
        try container.encode(workspaceID.uuidString, forKey: AnyCodingKey("workspaceId"))
        try container.encode(inputs, forKey: AnyCodingKey("inputs"))
        try container.encode(schedule, forKey: AnyCodingKey("schedule"))
        try container.encode(trigger, forKey: AnyCodingKey("trigger"))
        try container.encode(enabled, forKey: AnyCodingKey("enabled"))
        try container.encode(paused, forKey: AnyCodingKey("paused"))
        try container.encode(limits, forKey: AnyCodingKey("limits"))
        try container.encode(notifications, forKey: AnyCodingKey("notifications"))
        try container.encode(failurePolicy, forKey: AnyCodingKey("failurePolicy"))
        try container.encode(approval, forKey: AnyCodingKey("approval"))
        try container.encode(runCount, forKey: AnyCodingKey("runCount"))
        try container.encodeIfPresent(lastRunAt, forKey: AnyCodingKey("lastRunAt"))
        try container.encodeIfPresent(lastOutcome, forKey: AnyCodingKey("lastOutcome"))
        try container.encodeIfPresent(lastMessage, forKey: AnyCodingKey("lastMessage"))
        try container.encodeIfPresent(lastMissedAt, forKey: AnyCodingKey("lastMissedAt"))
        try container.encode(missedCount, forKey: AnyCodingKey("missedCount"))
        try container.encodeIfPresent(lastWorkerID, forKey: AnyCodingKey("lastWorkerId"))
        try container.encodeIfPresent(nextRunAt, forKey: AnyCodingKey("nextRunAt"))
        try container.encode(createdAt, forKey: AnyCodingKey("createdAt"))
        try container.encode(updatedAt, forKey: AnyCodingKey("updatedAt"))
        for (key, value) in extra {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }
}

public struct AssistantTaskList: Sendable {
    public var tasks: [AssistantTaskRecord]
    public var baseline: String
    public var origin: String
    public var decodeFailures: [AssistantTaskDecodeFailure]

    public init(
        tasks: [AssistantTaskRecord] = [], baseline: String = "", origin: String = "",
        decodeFailures: [AssistantTaskDecodeFailure] = []
    ) {
        self.tasks = tasks
        self.baseline = baseline
        self.origin = origin
        self.decodeFailures = decodeFailures
    }
}

public struct AssistantTaskDueEntry: Codable, Hashable, Sendable {
    public var taskID: UUID
    public var taskName: String
    public var occurrence: Int64
    public var nextRunAt: Int64
    public var runCount: Int64

    private enum CodingKeys: String, CodingKey {
        case taskID = "taskId"
        case taskName
        case occurrence
        case nextRunAt
        case runCount
    }

    public init(taskID: UUID, taskName: String, occurrence: Int64, nextRunAt: Int64, runCount: Int64) {
        self.taskID = taskID
        self.taskName = taskName
        self.occurrence = occurrence
        self.nextRunAt = nextRunAt
        self.runCount = runCount
    }

    public init(json: JSONValue) throws {
        self = try decodeTaskJSONValue(json, as: Self.self)
    }
}

public struct AssistantTaskRunOutcome: Sendable, Hashable {
    public var task: AssistantTaskRecord
    public var workerID: String
    public var parentThreadID: UUID

    public init(task: AssistantTaskRecord, workerID: String, parentThreadID: UUID) {
        self.task = task
        self.workerID = workerID
        self.parentThreadID = parentThreadID
    }
}

public struct AssistantTaskSkippedRun: Sendable, Hashable {
    public var task: AssistantTaskRecord
    public var reason: AssistantTaskSkipReason

    public init(task: AssistantTaskRecord, reason: AssistantTaskSkipReason) {
        self.task = task
        self.reason = reason
    }
}

public struct AssistantTaskFailedRun: Sendable, Hashable {
    public var task: AssistantTaskRecord
    public var message: String

    public init(task: AssistantTaskRecord, message: String) {
        self.task = task
        self.message = message
    }
}

public struct AssistantTaskDecodeFailure: Sendable, Hashable {
    public var taskID: UUID?
    public var message: String

    public init(taskID: UUID?, message: String) {
        self.taskID = taskID
        self.message = message
    }
}

public struct AssistantTaskPollOutcome: Sendable {
    public var ran: [AssistantTaskRunOutcome]
    public var skipped: [AssistantTaskSkippedRun]
    public var failed: [AssistantTaskFailedRun]
    public var decodeFailures: [AssistantTaskDecodeFailure]
    public var cycleError: String?

    public init(
        ran: [AssistantTaskRunOutcome] = [], skipped: [AssistantTaskSkippedRun] = [],
        failed: [AssistantTaskFailedRun] = [], decodeFailures: [AssistantTaskDecodeFailure] = [],
        cycleError: String? = nil
    ) {
        self.ran = ran
        self.skipped = skipped
        self.failed = failed
        self.decodeFailures = decodeFailures
        self.cycleError = cycleError
    }
}

public struct AssistantTaskMissedRun: Sendable, Hashable {
    public var task: AssistantTaskRecord
    public var reason: String
    public var missedAt: Date?
    public var missedCount: Int

    public init(task: AssistantTaskRecord, reason: String, missedAt: Date? = nil, missedCount: Int = 0) {
        self.task = task
        self.reason = reason
        self.missedAt = missedAt
        self.missedCount = missedCount
    }
}

public enum AssistantTaskSkipReason: Sendable, Equatable {
    case disabled
    case paused
    case assistantMissing
    case workspaceMissing
    case approvalRequired
    case assistantRequiresApproval
    case triggerUnavailable(String)
    case maxRunsReached(Int)

    public func message(task: AssistantTaskRecord) -> String {
        switch self {
        case .disabled:
            "Automated task '\(task.name)' is disabled; run-now is rejected"
        case .paused:
            "Automated task '\(task.name)' is paused; run-now is rejected"
        case .assistantMissing:
            "Assistant '\(task.assistantID.uuidString)' no longer exists; automated runs are skipped until the task points at an existing assistant."
        case .workspaceMissing:
            "Workspace '\(task.workspaceID.uuidString)' no longer exists; automated runs are skipped until the task points at an existing workspace."
        case .approvalRequired:
            "Automated task '\(task.name)' requires approval for its actions; run-now cannot start it without explicit user approval"
        case .assistantRequiresApproval:
            "Assistant '\(task.assistantID.uuidString)' requires approval for every run; automated run-now cannot start it without explicit user approval"
        case .triggerUnavailable(let kind):
            AssistantTaskManager.unavailableTriggerReason(kind)
                ?? "Trigger '\(kind)' is not available: only timer triggers can run automatically."
        case .maxRunsReached(let max):
            "Automated task '\(task.name)' has reached its maximum of \(max) runs"
        }
    }
}

public actor AssistantTaskManager {
    public static let defaultPollInterval: Duration = .seconds(60)
    public static let staleBaselineMarker = "changed; reload before saving"

    private let runtime: AssistantTaskRuntime
    public let pollInterval: Duration
    private var pollTask: Task<Void, Never>?
    private var baseline: String?

    public init(runtime: AssistantTaskRuntime, pollInterval: Duration = defaultPollInterval) {
        self.runtime = runtime
        self.pollInterval = pollInterval
    }

    public var isPolling: Bool {
        pollTask != nil
    }

    public var currentBaseline: String? {
        baseline
    }

    public static func unavailableTriggerReason(_ trigger: String) -> String? {
        switch trigger {
        case "timer":
            nil
        case "gitCommit":
            "Git commit triggers are not available: Coincide has no git watcher, hooks, webhooks, or GitHub polling"
        case "branchChange":
            "Branch change triggers are not available: Coincide has no git watcher or branch-change events"
        case "pullRequest":
            "Pull request triggers are not available: Coincide has no GitHub polling or webhooks"
        case "issue":
            "Issue triggers are not available: Coincide has no Issues API polling or webhooks"
        case "workspaceChange":
            "Workspace change triggers are not available: Coincide has no workspace file watcher"
        case "fileChange":
            "File change triggers are not available: Coincide has no file watcher"
        default:
            nil
        }
    }

    public static func skipReason(
        for task: AssistantTaskRecord, assistants: [RemoteAssistant], workspace: RemoteWorkspace
    ) -> AssistantTaskSkipReason? {
        if !task.enabled {
            return .disabled
        }
        if task.paused {
            return .paused
        }
        if unavailableTriggerReason(task.trigger) != nil || task.trigger != "timer" {
            return .triggerUnavailable(task.trigger)
        }
        if let maxRuns = task.limits.maxRuns, task.runCount >= maxRuns {
            return .maxRunsReached(maxRuns)
        }
        if task.approval.required {
            return .approvalRequired
        }
        guard let assistant = assistants.first(where: { $0.id == task.assistantID }) else {
            return .assistantMissing
        }
        if assistant.permissionProfile == .approvalRequired {
            return .assistantRequiresApproval
        }
        if !workspace.projects.contains(where: { $0.id == task.workspaceID }) {
            return .workspaceMissing
        }
        return nil
    }

    public func skipReason(for task: AssistantTaskRecord) async throws -> AssistantTaskSkipReason? {
        async let assistants = runtime.listAssistants()
        async let workspace = runtime.fetchWorkspace(includeArchived: false)
        let (listed, fetched) = try await (assistants, workspace)
        return Self.skipReason(for: task, assistants: listed.assistants, workspace: fetched)
    }

    public func listTasks() async throws -> AssistantTaskList {
        let result = try await runtime.tasksList()
        var tasks: [AssistantTaskRecord] = []
        var decodeFailures: [AssistantTaskDecodeFailure] = []
        for value in result["tasks"]?.arrayValue ?? [] {
            do {
                tasks.append(try AssistantTaskRecord(json: value))
            } catch {
                decodeFailures.append(AssistantTaskDecodeFailure(
                    taskID: Self.taskID(from: value, key: "id"),
                    message: "Could not decode an automated task record: \(error.localizedDescription)"
                ))
            }
        }
        let baselineValue = result["baseline"]?.stringValue ?? ""
        let origin = result["origin"]?.stringValue ?? ""
        if !baselineValue.isEmpty {
            baseline = baselineValue
        }
        return AssistantTaskList(
            tasks: tasks, baseline: baselineValue, origin: origin, decodeFailures: decodeFailures
        )
    }

    public func saveTask(_ task: AssistantTaskRecord, baseline: String) async throws -> AssistantTaskRecord {
        let encoded = try task.encoded()
        let result: JSONValue
        do {
            result = try await runtime.tasksSave(task: encoded, baseline: baseline)
        } catch {
            throw Self.staleChecked(error)
        }
        guard let saved = try? AssistantTaskRecord(json: result["task"] ?? .null) else {
            throw AssistantTaskError.invalidResult("Save did not return the saved task.")
        }
        updateBaseline(from: result)
        return saved
    }

    public func deleteTask(id: UUID, baseline: String) async throws {
        do {
            _ = try await runtime.tasksDelete(taskId: id.uuidString, baseline: baseline)
        } catch {
            throw Self.staleChecked(error)
        }
        self.baseline = nil
        _ = try? await listTasks()
    }

    public func setEnabled(_ task: AssistantTaskRecord, enabled: Bool, baseline: String) async throws -> AssistantTaskRecord {
        var updated = task
        updated.enabled = enabled
        return try await saveTask(updated, baseline: baseline)
    }

    public func setPaused(_ task: AssistantTaskRecord, paused: Bool, baseline: String) async throws -> AssistantTaskRecord {
        var updated = task
        updated.paused = paused
        return try await saveTask(updated, baseline: baseline)
    }

    public func runNow(_ task: AssistantTaskRecord) async throws -> AssistantTaskRunOutcome {
        if let reason = try await skipReason(for: task) {
            throw AssistantTaskError.runRejected(reason.message(task: task))
        }
        return try await runNowUnchecked(task)
    }

    public func recover() async throws -> [UUID] {
        let result = try await runtime.tasksRecover()
        return (result["missedTaskIds"]?.arrayValue ?? [])
            .compactMap { $0.stringValue }
            .compactMap { UUID(uuidString: $0) }
    }

    public func missedRuns() async throws -> [AssistantTaskMissedRun] {
        let listed = try await listTasks()
        return listed.tasks
            .filter { $0.lastOutcome == "missed" }
            .sorted { ($0.lastMissedAt ?? 0) > ($1.lastMissedAt ?? 0) }
            .map { task in
                AssistantTaskMissedRun(
                    task: task,
                    reason: task.lastMessage ?? "Run missed.",
                    missedAt: task.lastMissedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    missedCount: task.missedCount
                )
            }
    }

    public func pollNow() async -> AssistantTaskPollOutcome {
        var outcome = AssistantTaskPollOutcome()
        let due: [AssistantTaskDueEntry]
        do {
            let (entries, failures) = try await dueEntries()
            due = entries
            outcome.decodeFailures.append(contentsOf: failures)
        } catch {
            outcome.cycleError = error.localizedDescription
            return outcome
        }
        let listed: AssistantTaskList
        do {
            listed = try await listTasks()
        } catch {
            outcome.cycleError = error.localizedDescription
            return outcome
        }
        outcome.decodeFailures.append(contentsOf: listed.decodeFailures)
        guard !due.isEmpty else {
            return outcome
        }
        let assistants: RemoteAssistants
        let workspace: RemoteWorkspace
        do {
            async let listedAssistants = runtime.listAssistants()
            async let fetchedWorkspace = runtime.fetchWorkspace(includeArchived: false)
            (assistants, workspace) = try await (listedAssistants, fetchedWorkspace)
        } catch {
            outcome.cycleError = error.localizedDescription
            return outcome
        }
        let byID = Dictionary(uniqueKeysWithValues: listed.tasks.map { ($0.id, $0) })
        for entry in due {
            guard let task = byID[entry.taskID] else {
                outcome.decodeFailures.append(AssistantTaskDecodeFailure(
                    taskID: entry.taskID,
                    message: "Due run references an automated task that is no longer listed."
                ))
                continue
            }
            if let reason = Self.skipReason(for: task, assistants: assistants.assistants, workspace: workspace) {
                do {
                    _ = try await runtime.tasksMarkMissed(taskId: task.id.uuidString, reason: reason.message(task: task))
                } catch {
                    outcome.failed.append(AssistantTaskFailedRun(
                        task: task,
                        message: "Could not record the missed run: \(error.localizedDescription)"
                    ))
                    continue
                }
                outcome.skipped.append(AssistantTaskSkippedRun(task: task, reason: reason))
                continue
            }
            do {
                outcome.ran.append(try await runNowUnchecked(task))
            } catch {
                let reason = "Run failed: \(error.localizedDescription)"
                do {
                    _ = try await runtime.tasksMarkMissed(taskId: task.id.uuidString, reason: reason)
                } catch {
                }
                outcome.failed.append(AssistantTaskFailedRun(task: task, message: error.localizedDescription))
            }
        }
        return outcome
    }

    public func startPolling() {
        guard pollTask == nil else {
            return
        }
        let interval = pollInterval
        pollTask = Task {
            while !Task.isCancelled {
                _ = await self.pollNow()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func runNowUnchecked(_ task: AssistantTaskRecord) async throws -> AssistantTaskRunOutcome {
        let parentThreadID = try await runtime.createParentThread(projectID: task.workspaceID)
        let result: JSONValue
        do {
            result = try await runtime.tasksRunNow(taskId: task.id.uuidString, parentThreadId: parentThreadID.uuidString)
        } catch {
            try? await runtime.deleteParentThread(parentThreadID)
            throw error
        }
        guard let updated = try? AssistantTaskRecord(json: result["task"] ?? .null) else {
            throw AssistantTaskError.invalidResult("Run-now did not return the updated task.")
        }
        let workerID = result["worker"]?["id"]?.stringValue ?? ""
        updateBaseline(from: result)
        return AssistantTaskRunOutcome(task: updated, workerID: workerID, parentThreadID: parentThreadID)
    }

    private func dueEntries() async throws -> ([AssistantTaskDueEntry], [AssistantTaskDecodeFailure]) {
        let result = try await runtime.tasksDue()
        var entries: [AssistantTaskDueEntry] = []
        var failures: [AssistantTaskDecodeFailure] = []
        for value in result["dueTasks"]?.arrayValue ?? [] {
            do {
                entries.append(try AssistantTaskDueEntry(json: value))
            } catch {
                failures.append(AssistantTaskDecodeFailure(
                    taskID: Self.taskID(from: value, key: "taskId"),
                    message: "Could not decode a due automated task entry: \(error.localizedDescription)"
                ))
            }
        }
        return (entries, failures)
    }

    private static func taskID(from value: JSONValue, key: String) -> UUID? {
        value[key]?.stringValue.flatMap { UUID(uuidString: $0) }
    }

    private func updateBaseline(from result: JSONValue) {
        if let value = result["baseline"]?.stringValue, !value.isEmpty {
            baseline = value
        }
    }

    private static func isStaleBaselineError(_ error: Error) -> Bool {
        error.localizedDescription.contains(staleBaselineMarker)
    }

    private static func staleChecked(_ error: Error) -> Error {
        isStaleBaselineError(error) ? AssistantTaskError.staleBaseline : error
    }
}
