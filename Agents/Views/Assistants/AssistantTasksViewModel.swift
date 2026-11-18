import CoincideRemoteKit
import Foundation
import Observation

public enum AssistantTaskTriggerKind: String, Codable, Hashable, Sendable, CaseIterable {
    case timer
    case gitCommit
    case branchChange
    case pullRequest
    case issue
    case workspaceChange
    case fileChange

    public var displayName: String {
        switch self {
        case .timer: "Timer"
        case .gitCommit: "Git Commit"
        case .branchChange: "Branch Change"
        case .pullRequest: "Pull Request"
        case .issue: "Issue"
        case .workspaceChange: "Workspace Change"
        case .fileChange: "File Change"
        }
    }

    public var isAvailable: Bool {
        self == .timer
    }

    public var unavailableReason: String? {
        switch self {
        case .timer:
            nil
        case .gitCommit:
            "Git commit triggers are not available: Coincide has no git watcher, hooks, webhooks, or GitHub polling"
        case .branchChange:
            "Branch change triggers are not available: Coincide has no git watcher or branch-change events"
        case .pullRequest:
            "Pull request triggers are not available: Coincide has no GitHub polling or webhooks"
        case .issue:
            "Issue triggers are not available: Coincide has no Issues API polling or webhooks"
        case .workspaceChange:
            "Workspace change triggers are not available: Coincide has no workspace file watcher"
        case .fileChange:
            "File change triggers are not available: Coincide has no file watcher"
        }
    }
}

public enum AssistantTaskFailureBehavior: String, Codable, Hashable, Sendable, CaseIterable {
    case retryWithBackoff
    case stop
    case notify

    public var displayName: String {
        switch self {
        case .retryWithBackoff: "Retry with backoff"
        case .stop: "Stop"
        case .notify: "Notify only"
        }
    }
}

public enum AssistantTaskOutcome: Hashable, Sendable {
    case completed
    case failed
    case missed
    case interrupted
    case unknown(String)

    public var displayName: String {
        switch self {
        case .completed: "Completed"
        case .failed: "Failed"
        case .missed: "Missed"
        case .interrupted: "Interrupted"
        case .unknown(let value): value
        }
    }

    public var rawValue: String {
        switch self {
        case .completed: "completed"
        case .failed: "failed"
        case .missed: "missed"
        case .interrupted: "interrupted"
        case .unknown(let value): value
        }
    }
}

extension AssistantTaskOutcome: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "completed": self = .completed
        case "failed": self = .failed
        case "missed": self = .missed
        case "interrupted": self = .interrupted
        case let value: self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AssistantTaskScheduleKind: String, Codable, Hashable, Sendable, CaseIterable {
    case once
    case daily
    case weekly
    case weekdays
    case days
    case interval
    case cron
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = AssistantTaskScheduleKind(rawValue: try container.decode(String.self)) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .once: "Once"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .weekdays: "Weekdays"
        case .days: "Selected days"
        case .interval: "Repeat every"
        case .cron: "Cron"
        case .unknown: "Custom"
        }
    }
}

public struct AssistantTaskSchedule: Codable, Hashable, Sendable {
    public var kind: AssistantTaskScheduleKind
    public var timeZoneID: String
    public var date: Date
    public var hour: Int
    public var minute: Int
    public var weekday: Int
    public var weekdays: [Int]?
    public var intervalMinutes: Int?
    public var cron: String?

    public init(
        kind: AssistantTaskScheduleKind,
        timeZoneID: String = TimeZone.current.identifier,
        date: Date = Date(),
        hour: Int = 9,
        minute: Int = 0,
        weekday: Int = 2,
        weekdays: [Int]? = nil,
        intervalMinutes: Int? = nil,
        cron: String? = nil
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
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case timeZoneID
        case date
        case hour
        case minute
        case weekday
        case weekdays
        case intervalMinutes
        case cron
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? container.decode(AssistantTaskScheduleKind.self, forKey: .kind)) ?? .unknown
        timeZoneID = (try? container.decode(String.self, forKey: .timeZoneID)) ?? TimeZone.current.identifier
        if let text = try? container.decode(String.self, forKey: .date),
           let parsed = ISO8601DateFormatter().date(from: text) {
            date = parsed
        } else if let seconds = try? container.decode(Double.self, forKey: .date) {
            date = Date(timeIntervalSinceReferenceDate: seconds)
        } else {
            date = Date()
        }
        hour = (try? container.decode(Int.self, forKey: .hour)) ?? 9
        minute = (try? container.decode(Int.self, forKey: .minute)) ?? 0
        weekday = (try? container.decode(Int.self, forKey: .weekday)) ?? 2
        weekdays = try? container.decode([Int].self, forKey: .weekdays)
        intervalMinutes = try? container.decode(Int.self, forKey: .intervalMinutes)
        cron = try? container.decode(String.self, forKey: .cron)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(timeZoneID, forKey: .timeZoneID)
        try container.encode(ISO8601DateFormatter().string(from: date), forKey: .date)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
        try container.encode(weekday, forKey: .weekday)
        try container.encodeIfPresent(weekdays, forKey: .weekdays)
        try container.encodeIfPresent(intervalMinutes, forKey: .intervalMinutes)
        try container.encodeIfPresent(cron, forKey: .cron)
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .current
    }

    public var summary: String {
        let time = AssistantTaskDateFormatting.time(hour: hour, minute: minute, timeZoneID: timeZoneID)
        switch kind {
        case .once:
            return "Once on \(AssistantTaskDateFormatting.date(date, timeZoneID: timeZoneID)) at \(time)"
        case .daily:
            return "Daily at \(time)"
        case .weekly:
            let symbols = Calendar.current.weekdaySymbols
            let index = max(0, min(symbols.count - 1, weekday - 1))
            return "Weekly on \(symbols[index]) at \(time)"
        case .weekdays:
            return "Weekdays at \(time)"
        case .days:
            let symbols = Calendar.current.weekdaySymbols
            let names = (weekdays ?? []).sorted().map { day in
                symbols[max(0, min(symbols.count - 1, day - 1))]
            }
            if names.isEmpty {
                return "Selected days at \(time)"
            }
            return "On \(names.joined(separator: ", ")) at \(time)"
        case .interval:
            guard let intervalMinutes else { return "Repeat every" }
            if intervalMinutes % 1440 == 0 {
                let days = intervalMinutes / 1440
                return days == 1 ? "Every day" : "Every \(days) days"
            }
            if intervalMinutes % 60 == 0 {
                let hours = intervalMinutes / 60
                return hours == 1 ? "Every hour" : "Every \(hours) hours"
            }
            return intervalMinutes == 1 ? "Every minute" : "Every \(intervalMinutes) minutes"
        case .cron:
            if let cron, !cron.isEmpty {
                return "Cron: \(cron)"
            }
            return "Cron schedule"
        case .unknown:
            return "Custom schedule"
        }
    }

    public func upcomingRuns(after: Date, count: Int) -> [Date] {
        guard count > 0 else { return [] }
        switch kind {
        case .once:
            return date > after ? [date] : []
        case .interval:
            guard let intervalMinutes, intervalMinutes > 0 else { return [] }
            let step = TimeInterval(intervalMinutes * 60)
            var first: Date
            if date > after {
                first = date
            } else {
                let elapsed = after.timeIntervalSince(date)
                let steps = Int(elapsed / step) + 1
                first = date.addingTimeInterval(TimeInterval(steps) * step)
            }
            return (0..<count).map { first.addingTimeInterval(TimeInterval($0) * step) }
        case .daily, .weekly, .weekdays, .days:
            guard kind != .days || !(weekdays ?? []).isEmpty else { return [] }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            var results: [Date] = []
            var cursor = after
            var attempts = 0
            while results.count < count && attempts < 3660 {
                attempts += 1
                var matching = DateComponents()
                matching.hour = hour
                matching.minute = minute
                if kind == .weekly {
                    matching.weekday = weekday
                }
                guard let next = calendar.nextDate(
                    after: cursor,
                    matching: matching,
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .forward
                ) else {
                    break
                }
                cursor = next
                let dayOfWeek = calendar.component(.weekday, from: next)
                if kind == .weekdays, !(2...6).contains(dayOfWeek) {
                    continue
                }
                if kind == .days, !(weekdays ?? []).contains(dayOfWeek) {
                    continue
                }
                results.append(next)
            }
            return results
        case .cron, .unknown:
            return []
        }
    }
}

public indirect enum AssistantTaskJSONValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([AssistantTaskJSONValue])
    case object([String: AssistantTaskJSONValue])

    public init?(jsonText: String) {
        guard let data = jsonText.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
              let value = Self(any: parsed) else {
            return nil
        }
        self = value
    }

    public init?(any: Any) {
        switch any {
        case let text as String:
            self = .string(text)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case is NSNull:
            self = .null
        case let items as [Any]:
            let values = items.compactMap(Self.init(any:))
            guard values.count == items.count else { return nil }
            self = .array(values)
        case let object as [String: Any]:
            var values: [String: AssistantTaskJSONValue] = [:]
            for (key, item) in object {
                guard let value = Self(any: item) else { return nil }
                values[key] = value
            }
            self = .object(values)
        default:
            return nil
        }
    }

    public var anyValue: Any {
        switch self {
        case .string(let text): text
        case .number(let number): number
        case .bool(let flag): flag
        case .null: NSNull()
        case .array(let items): items.map(\.anyValue)
        case .object(let object): object.mapValues(\.anyValue)
        }
    }

    public var jsonText: String {
        guard let data = try? JSONSerialization.data(withJSONObject: anyValue, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }
}

extension AssistantTaskJSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .string(text)
            return
        }
        if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
            return
        }
        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        if let items = try? container.decode([AssistantTaskJSONValue].self) {
            self = .array(items)
            return
        }
        if let object = try? container.decode([String: AssistantTaskJSONValue].self) {
            self = .object(object)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text): try container.encode(text)
        case .number(let number): try container.encode(number)
        case .bool(let flag): try container.encode(flag)
        case .null: try container.encodeNil()
        case .array(let items): try container.encode(items)
        case .object(let object): try container.encode(object)
        }
    }
}

public enum AssistantTaskInputValue: Hashable, Sendable {
    case string(String)
    case json(AssistantTaskJSONValue)

    public var displayText: String {
        switch self {
        case .string(let text): text
        case .json(let value): value.jsonText
        }
    }

    public var isJSON: Bool {
        if case .json = self { return true }
        return false
    }
}

extension AssistantTaskInputValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .string(text)
            return
        }
        let value = try container.decode(AssistantTaskJSONValue.self)
        self = .json(value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text): try container.encode(text)
        case .json(let value): try container.encode(value)
        }
    }
}

public struct AssistantTaskLimits: Codable, Hashable, Sendable {
    public var maxRuns: Int?
    public var maxConcurrent: Int

    public init(maxRuns: Int? = nil, maxConcurrent: Int = 1) {
        self.maxRuns = maxRuns
        self.maxConcurrent = maxConcurrent
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
}

public struct AssistantTaskFailurePolicy: Codable, Hashable, Sendable {
    public var behavior: AssistantTaskFailureBehavior
    public var maxRetries: Int
    public var backoffSeconds: Int

    public init(
        behavior: AssistantTaskFailureBehavior = .retryWithBackoff,
        maxRetries: Int = 3,
        backoffSeconds: Int = 300
    ) {
        self.behavior = behavior
        self.maxRetries = maxRetries
        self.backoffSeconds = backoffSeconds
    }
}

public struct AssistantTaskApproval: Codable, Hashable, Sendable {
    public var required: Bool
    public var actions: [String]

    public init(required: Bool = false, actions: [String] = []) {
        self.required = required
        self.actions = actions
    }
}

public struct AssistantTask: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var assistantID: UUID
    public var workspaceID: UUID
    public var inputs: [String: AssistantTaskInputValue]
    public var schedule: AssistantTaskSchedule
    public var trigger: AssistantTaskTriggerKind
    public var enabled: Bool
    public var paused: Bool
    public var limits: AssistantTaskLimits
    public var notifications: AssistantTaskNotificationPrefs
    public var failurePolicy: AssistantTaskFailurePolicy
    public var approval: AssistantTaskApproval
    public var runCount: Int
    public var lastRunAt: Date?
    public var lastOutcome: AssistantTaskOutcome?
    public var lastMessage: String?
    public var lastMissedAt: Date?
    public var missedCount: Int
    public var lastWorkerID: UUID?
    public var nextRunAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var extra: [String: AssistantTaskJSONValue]

    public init(
        id: UUID,
        name: String,
        assistantID: UUID,
        workspaceID: UUID,
        inputs: [String: AssistantTaskInputValue] = [:],
        schedule: AssistantTaskSchedule,
        trigger: AssistantTaskTriggerKind = .timer,
        enabled: Bool = true,
        paused: Bool = false,
        limits: AssistantTaskLimits = AssistantTaskLimits(),
        notifications: AssistantTaskNotificationPrefs = AssistantTaskNotificationPrefs(),
        failurePolicy: AssistantTaskFailurePolicy = AssistantTaskFailurePolicy(),
        approval: AssistantTaskApproval = AssistantTaskApproval(),
        runCount: Int = 0,
        lastRunAt: Date? = nil,
        lastOutcome: AssistantTaskOutcome? = nil,
        lastMessage: String? = nil,
        lastMissedAt: Date? = nil,
        missedCount: Int = 0,
        lastWorkerID: UUID? = nil,
        nextRunAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        extra: [String: AssistantTaskJSONValue] = [:]
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

    public var hasFailed: Bool {
        lastOutcome == .failed
    }

    public var hasRunningWorker: Bool {
        lastWorkerID != nil && lastOutcome == nil && lastRunAt != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case assistantID
        case workspaceID
        case inputs
        case schedule
        case trigger
        case enabled
        case paused
        case limits
        case notifications
        case failurePolicy
        case approval
        case runCount
        case lastRunAt
        case lastOutcome
        case lastMessage
        case lastMissedAt
        case missedCount
        case lastWorkerID
        case nextRunAt
        case createdAt
        case updatedAt
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    private static func epochDate(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Date? {
        guard let seconds = try? container.decode(Int64.self, forKey: key) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        assistantID = try container.decode(UUID.self, forKey: .assistantID)
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        inputs = (try? container.decode([String: AssistantTaskInputValue].self, forKey: .inputs)) ?? [:]
        schedule = try container.decode(AssistantTaskSchedule.self, forKey: .schedule)
        trigger = (try? container.decode(AssistantTaskTriggerKind.self, forKey: .trigger)) ?? .timer
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? true
        paused = (try? container.decode(Bool.self, forKey: .paused)) ?? false
        limits = (try? container.decode(AssistantTaskLimits.self, forKey: .limits)) ?? AssistantTaskLimits()
        notifications = (try? container.decode(AssistantTaskNotificationPrefs.self, forKey: .notifications)) ?? AssistantTaskNotificationPrefs()
        failurePolicy = (try? container.decode(AssistantTaskFailurePolicy.self, forKey: .failurePolicy)) ?? AssistantTaskFailurePolicy()
        approval = (try? container.decode(AssistantTaskApproval.self, forKey: .approval)) ?? AssistantTaskApproval()
        runCount = (try? container.decode(Int.self, forKey: .runCount)) ?? 0
        lastRunAt = Self.epochDate(from: container, key: .lastRunAt)
        lastOutcome = try? container.decode(AssistantTaskOutcome.self, forKey: .lastOutcome)
        lastMessage = try? container.decode(String.self, forKey: .lastMessage)
        lastMissedAt = Self.epochDate(from: container, key: .lastMissedAt)
        missedCount = (try? container.decode(Int.self, forKey: .missedCount)) ?? 0
        lastWorkerID = try? container.decode(UUID.self, forKey: .lastWorkerID)
        nextRunAt = Self.epochDate(from: container, key: .nextRunAt)
        createdAt = Self.epochDate(from: container, key: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = Self.epochDate(from: container, key: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        let extraContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var extra: [String: AssistantTaskJSONValue] = [:]
        for key in extraContainer.allKeys where CodingKeys(rawValue: key.stringValue) == nil {
            if let value = try? extraContainer.decode(AssistantTaskJSONValue.self, forKey: key) {
                extra[key.stringValue] = value
            }
        }
        self.extra = extra
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(assistantID, forKey: .assistantID)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(paused, forKey: .paused)
        try container.encode(limits, forKey: .limits)
        try container.encode(notifications, forKey: .notifications)
        try container.encode(failurePolicy, forKey: .failurePolicy)
        try container.encode(approval, forKey: .approval)
        try container.encode(runCount, forKey: .runCount)
        if let lastRunAt {
            try container.encode(Int64(lastRunAt.timeIntervalSince1970), forKey: .lastRunAt)
        } else {
            try container.encodeNil(forKey: .lastRunAt)
        }
        if let lastOutcome {
            try container.encode(lastOutcome, forKey: .lastOutcome)
        } else {
            try container.encodeNil(forKey: .lastOutcome)
        }
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        if let lastMissedAt {
            try container.encode(Int64(lastMissedAt.timeIntervalSince1970), forKey: .lastMissedAt)
        } else {
            try container.encodeNil(forKey: .lastMissedAt)
        }
        try container.encode(missedCount, forKey: .missedCount)
        try container.encodeIfPresent(lastWorkerID, forKey: .lastWorkerID)
        if let nextRunAt {
            try container.encode(Int64(nextRunAt.timeIntervalSince1970), forKey: .nextRunAt)
        } else {
            try container.encodeNil(forKey: .nextRunAt)
        }
        try container.encode(Int64(createdAt.timeIntervalSince1970), forKey: .createdAt)
        try container.encode(Int64(updatedAt.timeIntervalSince1970), forKey: .updatedAt)
        var extraContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in extra {
            if let codingKey = DynamicCodingKey(stringValue: key) {
                try extraContainer.encode(value, forKey: codingKey)
            }
        }
    }
}

public struct AssistantTaskDue: Codable, Hashable, Sendable, Identifiable {
    public var taskID: UUID
    public var taskName: String
    public var occurrence: Date
    public var nextRunAt: Date
    public var runCount: Int

    public var id: UUID { taskID }

    public init(taskID: UUID, taskName: String, occurrence: Date, nextRunAt: Date, runCount: Int) {
        self.taskID = taskID
        self.taskName = taskName
        self.occurrence = occurrence
        self.nextRunAt = nextRunAt
        self.runCount = runCount
    }

    private enum CodingKeys: String, CodingKey {
        case taskID
        case taskName
        case occurrence
        case nextRunAt
        case runCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try container.decode(UUID.self, forKey: .taskID)
        taskName = (try? container.decode(String.self, forKey: .taskName)) ?? ""
        let occurrenceSeconds = try container.decode(Int64.self, forKey: .occurrence)
        occurrence = Date(timeIntervalSince1970: TimeInterval(occurrenceSeconds))
        let nextSeconds = try container.decode(Int64.self, forKey: .nextRunAt)
        nextRunAt = Date(timeIntervalSince1970: TimeInterval(nextSeconds))
        runCount = (try? container.decode(Int.self, forKey: .runCount)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskID, forKey: .taskID)
        try container.encode(taskName, forKey: .taskName)
        try container.encode(Int64(occurrence.timeIntervalSince1970), forKey: .occurrence)
        try container.encode(Int64(nextRunAt.timeIntervalSince1970), forKey: .nextRunAt)
        try container.encode(runCount, forKey: .runCount)
    }
}

public struct AssistantTaskRunNowResult: Hashable, Sendable {
    public var task: AssistantTask
    public var workerID: UUID

    public init(task: AssistantTask, workerID: UUID) {
        self.task = task
        self.workerID = workerID
    }
}

public struct AssistantTaskInputRow: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var key: String
    public var value: String
    public var isJSON: Bool

    public init(id: UUID = UUID(), key: String, value: String, isJSON: Bool = false) {
        self.id = id
        self.key = key
        self.value = value
        self.isJSON = isJSON
    }
}

public enum AssistantTaskDraftIssue: Hashable, Sendable {
    case emptyName
    case missingAssistant
    case missingWorkspace
    case emptyInputKey(index: Int)
    case duplicateInputKey(key: String)
    case invalidJSONInput(key: String)
    case approvalActionsWithoutRequirement
    case emptyApprovalAction(index: Int)
    case duplicateApprovalAction(name: String)

    public var message: String {
        switch self {
        case .emptyName:
            "Enter a name for the task."
        case .missingAssistant:
            "Choose an assistant to run."
        case .missingWorkspace:
            "Choose a workspace to run in."
        case .emptyInputKey(let index):
            "Input \(index + 1) needs a name."
        case .duplicateInputKey(let key):
            "Input \"\(key)\" is listed more than once."
        case .invalidJSONInput(let key):
            "Input \"\(key)\" is not valid JSON."
        case .approvalActionsWithoutRequirement:
            "Approval actions need approval to be required."
        case .emptyApprovalAction(let index):
            "Approval action \(index + 1) is empty."
        case .duplicateApprovalAction(let name):
            "Approval action \"\(name)\" is listed more than once."
        }
    }
}

public struct AssistantTaskDraft: Hashable, Sendable {
    public var name: String
    public var assistantID: UUID?
    public var workspaceID: UUID?
    public var inputRows: [AssistantTaskInputRow]
    public var schedule: AssistantTaskSchedule
    public var trigger: AssistantTaskTriggerKind
    public var enabled: Bool
    public var paused: Bool
    public var maxRuns: Int?
    public var maxConcurrent: Int
    public var notifyOnSuccess: Bool
    public var notifyOnFailure: Bool
    public var notifyOnMissed: Bool
    public var failureBehavior: AssistantTaskFailureBehavior
    public var maxRetries: Int
    public var backoffSeconds: Int
    public var approvalRequired: Bool
    public var approvalActions: [String]

    public init(
        name: String = "",
        assistantID: UUID? = nil,
        workspaceID: UUID? = nil,
        inputRows: [AssistantTaskInputRow] = [],
        schedule: AssistantTaskSchedule = AssistantTaskSchedule(kind: .daily),
        trigger: AssistantTaskTriggerKind = .timer,
        enabled: Bool = true,
        paused: Bool = false,
        maxRuns: Int? = nil,
        maxConcurrent: Int = 1,
        notifyOnSuccess: Bool = false,
        notifyOnFailure: Bool = true,
        notifyOnMissed: Bool = true,
        failureBehavior: AssistantTaskFailureBehavior = .retryWithBackoff,
        maxRetries: Int = 3,
        backoffSeconds: Int = 300,
        approvalRequired: Bool = false,
        approvalActions: [String] = []
    ) {
        self.name = name
        self.assistantID = assistantID
        self.workspaceID = workspaceID
        self.inputRows = inputRows
        self.schedule = schedule
        self.trigger = trigger
        self.enabled = enabled
        self.paused = paused
        self.maxRuns = maxRuns
        self.maxConcurrent = maxConcurrent
        self.notifyOnSuccess = notifyOnSuccess
        self.notifyOnFailure = notifyOnFailure
        self.notifyOnMissed = notifyOnMissed
        self.failureBehavior = failureBehavior
        self.maxRetries = maxRetries
        self.backoffSeconds = backoffSeconds
        self.approvalRequired = approvalRequired
        self.approvalActions = approvalActions
    }

    public func validationIssues() -> [AssistantTaskDraftIssue] {
        var issues: [AssistantTaskDraftIssue] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyName)
        }
        if assistantID == nil {
            issues.append(.missingAssistant)
        }
        if workspaceID == nil {
            issues.append(.missingWorkspace)
        }
        var seenKeys: Set<String> = []
        for (index, row) in inputRows.enumerated() {
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                issues.append(.emptyInputKey(index: index))
                continue
            }
            if !seenKeys.insert(key).inserted {
                issues.append(.duplicateInputKey(key: key))
            }
            if row.isJSON, AssistantTaskJSONValue(jsonText: row.value) == nil {
                issues.append(.invalidJSONInput(key: key))
            }
        }
        if !approvalRequired, !approvalActions.isEmpty {
            issues.append(.approvalActionsWithoutRequirement)
        }
        var seenActions: Set<String> = []
        for (index, action) in approvalActions.enumerated() {
            let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                issues.append(.emptyApprovalAction(index: index))
                continue
            }
            if !seenActions.insert(trimmed).inserted {
                issues.append(.duplicateApprovalAction(name: trimmed))
            }
        }
        return issues
    }

    public func makeTask(id: UUID, existing: AssistantTask?, now: Date) -> AssistantTask? {
        guard let assistantID, let workspaceID else { return nil }
        var inputs: [String: AssistantTaskInputValue] = [:]
        for row in inputRows {
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            if row.isJSON {
                guard let value = AssistantTaskJSONValue(jsonText: row.value) else { return nil }
                inputs[key] = .json(value)
            } else {
                inputs[key] = .string(row.value)
            }
        }
        return AssistantTask(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            assistantID: assistantID,
            workspaceID: workspaceID,
            inputs: inputs,
            schedule: schedule,
            trigger: trigger,
            enabled: enabled,
            paused: paused,
            limits: AssistantTaskLimits(maxRuns: maxRuns, maxConcurrent: maxConcurrent),
            notifications: AssistantTaskNotificationPrefs(
                onSuccess: notifyOnSuccess,
                onFailure: notifyOnFailure,
                onMissed: notifyOnMissed
            ),
            failurePolicy: AssistantTaskFailurePolicy(
                behavior: failureBehavior,
                maxRetries: maxRetries,
                backoffSeconds: backoffSeconds
            ),
            approval: AssistantTaskApproval(
                required: approvalRequired,
                actions: approvalActions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ),
            runCount: existing?.runCount ?? 0,
            lastRunAt: existing?.lastRunAt,
            lastOutcome: existing?.lastOutcome,
            lastMessage: existing?.lastMessage,
            lastMissedAt: existing?.lastMissedAt,
            missedCount: existing?.missedCount ?? 0,
            lastWorkerID: existing?.lastWorkerID,
            nextRunAt: existing?.nextRunAt,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            extra: existing?.extra ?? [:]
        )
    }
}

public protocol AssistantTaskManaging: Sendable {
    func listTasks() async throws -> [AssistantTask]
    func saveTask(_ task: AssistantTask) async throws -> AssistantTask
    func deleteTask(id: UUID) async throws
    func setTaskEnabled(id: UUID, enabled: Bool) async throws -> AssistantTask
    func setTaskPaused(id: UUID, paused: Bool) async throws -> AssistantTask
    func runTaskNow(id: UUID) async throws -> AssistantTaskRunNowResult
    func dueTasks(now: Date) async throws -> [AssistantTaskDue]
    func markTaskMissed(id: UUID, reason: String) async throws -> AssistantTask
    func recoverMissedTasks(now: Date) async throws -> [UUID]
}

public enum AssistantTasksFilter: String, CaseIterable, Sendable {
    case all
    case active
    case paused
    case upcoming
    case recent
    case failed

    public var title: String {
        switch self {
        case .all: "All"
        case .active: "Active"
        case .paused: "Paused"
        case .upcoming: "Upcoming"
        case .recent: "Recent"
        case .failed: "Failed"
        }
    }
}

public enum AssistantTaskDateFormatting {
    private static func formatter(dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style, timeZoneID: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter
    }

    public static func dateTime(_ date: Date, timeZoneID: String) -> String {
        formatter(dateStyle: .medium, timeStyle: .short, timeZoneID: timeZoneID).string(from: date)
    }

    public static func date(_ date: Date, timeZoneID: String) -> String {
        formatter(dateStyle: .medium, timeStyle: .none, timeZoneID: timeZoneID).string(from: date)
    }

    public static func time(_ date: Date, timeZoneID: String) -> String {
        formatter(dateStyle: .none, timeStyle: .short, timeZoneID: timeZoneID).string(from: date)
    }

    public static func time(hour: Int, minute: Int, timeZoneID: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else {
            return String(format: "%d:%02d", hour, minute)
        }
        return time(date, timeZoneID: timeZoneID)
    }
}

@Observable
@MainActor
public final class AssistantTasksViewModel {
    public let manager: any AssistantTaskManaging
    public var catalog: AssistantCatalog
    public var projects: [RemoteProject]
    public var now: () -> Date

    public var tasks: [AssistantTask] = []
    public var filter: AssistantTasksFilter = .all
    public var searchText: String = ""
    public var selectedTaskID: UUID?
    public var isLoading: Bool = false
    public var lastError: String?
    public var lastRunNowWorkerID: UUID?
    public var dueTasksList: [AssistantTaskDue] = []

    public init(
        manager: any AssistantTaskManaging,
        catalog: AssistantCatalog,
        projects: [RemoteProject] = [],
        now: @escaping () -> Date = { Date() }
    ) {
        self.manager = manager
        self.catalog = catalog
        self.projects = projects
        self.now = now
    }

    public var selectedTask: AssistantTask? {
        guard let selectedTaskID else { return nil }
        return tasks.first { $0.id == selectedTaskID }
    }

    public var filteredTasks: [AssistantTask] {
        let nowDate = now()
        var result = tasks
        switch filter {
        case .all:
            break
        case .active:
            result = result.filter(\.isActive)
        case .paused:
            result = result.filter(\.paused)
        case .upcoming:
            result = result.filter { task in
                guard task.isActive, let next = task.nextRunAt else { return false }
                return next > nowDate
            }
        case .recent:
            result = result.filter { $0.lastRunAt != nil }
        case .failed:
            result = result.filter { $0.lastOutcome == .failed }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { task in
                task.name.lowercased().contains(query)
                    || assistantName(for: task).lowercased().contains(query)
                    || workspaceName(for: task).lowercased().contains(query)
            }
        }
        switch filter {
        case .recent:
            return result.sorted { ($0.lastRunAt ?? .distantPast) > ($1.lastRunAt ?? .distantPast) }
        case .upcoming:
            return result.sorted { ($0.nextRunAt ?? .distantFuture) < ($1.nextRunAt ?? .distantFuture) }
        default:
            return result.sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
        }
    }

    public var countsByFilter: [AssistantTasksFilter: Int] {
        let nowDate = now()
        var counts: [AssistantTasksFilter: Int] = [:]
        counts[.all] = tasks.count
        counts[.active] = tasks.filter(\.isActive).count
        counts[.paused] = tasks.filter(\.paused).count
        counts[.upcoming] = tasks.filter { task in
            guard task.isActive, let next = task.nextRunAt else { return false }
            return next > nowDate
        }.count
        counts[.recent] = tasks.filter { $0.lastRunAt != nil }.count
        counts[.failed] = tasks.filter { $0.lastOutcome == .failed }.count
        return counts
    }

    public func assistantDefinition(for task: AssistantTask) -> AssistantDefinition? {
        catalog.definition(forPersistenceID: task.assistantID)
    }

    public func assistantName(for task: AssistantTask) -> String {
        assistantDefinition(for: task)?.name ?? "Unknown assistant"
    }

    public func workspaceName(for task: AssistantTask) -> String {
        projects.first { $0.id == task.workspaceID }?.name ?? "Unknown workspace"
    }

    public func upcomingRuns(for task: AssistantTask, count: Int = 5) -> [Date] {
        let runs = task.schedule.upcomingRuns(after: now(), count: count)
        if !runs.isEmpty {
            return runs
        }
        if let next = task.nextRunAt, next > now() {
            return [next]
        }
        return []
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await manager.listTasks()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func refreshDue() async {
        do {
            dueTasksList = try await manager.dueTasks(now: now())
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func recoverMissed() async -> [UUID] {
        do {
            let missed = try await manager.recoverMissedTasks(now: now())
            await refresh()
            lastError = nil
            return missed
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    public func draftForNewTask(
        assistant: AssistantDefinition? = nil,
        workspaceID: UUID? = nil
    ) -> AssistantTaskDraft {
        AssistantTaskDraft(
            assistantID: assistant?.persistenceID,
            workspaceID: workspaceID ?? projects.first { !$0.isChats }?.id ?? projects.first?.id
        )
    }

    public func draftForTask(_ task: AssistantTask) -> AssistantTaskDraft {
        let rows = task.inputs
            .sorted { $0.key < $1.key }
            .map { key, value in
                AssistantTaskInputRow(key: key, value: value.displayText, isJSON: value.isJSON)
            }
        return AssistantTaskDraft(
            name: task.name,
            assistantID: task.assistantID,
            workspaceID: task.workspaceID,
            inputRows: rows,
            schedule: task.schedule,
            trigger: task.trigger,
            enabled: task.enabled,
            paused: task.paused,
            maxRuns: task.limits.maxRuns,
            maxConcurrent: task.limits.maxConcurrent,
            notifyOnSuccess: task.notifications.onSuccess,
            notifyOnFailure: task.notifications.onFailure,
            notifyOnMissed: task.notifications.onMissed,
            failureBehavior: task.failurePolicy.behavior,
            maxRetries: task.failurePolicy.maxRetries,
            backoffSeconds: task.failurePolicy.backoffSeconds,
            approvalRequired: task.approval.required,
            approvalActions: task.approval.actions
        )
    }

    @discardableResult
    public func saveDraft(_ draft: AssistantTaskDraft, editingTaskID: UUID?) async -> Bool {
        let issues = draft.validationIssues()
        guard issues.isEmpty else {
            lastError = issues.map(\.message).joined(separator: "\n")
            return false
        }
        let id = editingTaskID ?? UUID()
        let existing = editingTaskID.flatMap { editingID in tasks.first { $0.id == editingID } }
        guard let task = draft.makeTask(id: id, existing: existing, now: now()) else {
            lastError = "The task could not be built from the editor values."
            return false
        }
        do {
            let saved = try await manager.saveTask(task)
            if let index = tasks.firstIndex(where: { $0.id == saved.id }) {
                tasks[index] = saved
            } else {
                tasks.append(saved)
            }
            selectedTaskID = saved.id
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func delete(_ task: AssistantTask) async -> Bool {
        do {
            try await manager.deleteTask(id: task.id)
            tasks.removeAll { $0.id == task.id }
            if selectedTaskID == task.id {
                selectedTaskID = nil
            }
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func setEnabled(_ task: AssistantTask, enabled: Bool) async -> Bool {
        do {
            let updated = try await manager.setTaskEnabled(id: task.id, enabled: enabled)
            replace(updated)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func setPaused(_ task: AssistantTask, paused: Bool) async -> Bool {
        do {
            let updated = try await manager.setTaskPaused(id: task.id, paused: paused)
            replace(updated)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func runNow(_ task: AssistantTask) async -> Bool {
        do {
            let result = try await manager.runTaskNow(id: task.id)
            lastRunNowWorkerID = result.workerID
            replace(result.task)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func markMissed(_ task: AssistantTask, reason: String) async -> Bool {
        do {
            let updated = try await manager.markTaskMissed(id: task.id, reason: reason)
            replace(updated)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func replace(_ task: AssistantTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        }
    }
}
