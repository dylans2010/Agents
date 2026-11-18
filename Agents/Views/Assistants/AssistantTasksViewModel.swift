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

    public init(rawValue: String) {
        switch rawValue {
        case "completed": self = .completed
        case "failed": self = .failed
        case "missed": self = .missed
        case "interrupted": self = .interrupted
        case let value: self = .unknown(value)
        }
    }

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
        self.init(rawValue: try container.decode(String.self))
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

extension AssistantTaskSchedule {
    public var kindEnum: AssistantTaskScheduleKind {
        AssistantTaskScheduleKind(rawValue: kind) ?? .unknown
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .current
    }

    public var onceDate: Date? {
        switch date {
        case .string(let text):
            ISO8601DateFormatter().date(from: text)
        case .int(let seconds):
            Date(timeIntervalSince1970: TimeInterval(seconds))
        case .double(let seconds):
            Date(timeIntervalSince1970: seconds)
        default:
            nil
        }
    }

    public var summary: String {
        let time = AssistantTaskDateFormatting.time(hour: hour, minute: minute, timeZoneID: timeZoneID)
        switch kindEnum {
        case .once:
            if let anchor = onceDate {
                return "Once on \(AssistantTaskDateFormatting.date(anchor, timeZoneID: timeZoneID)) at \(time)"
            }
            return "Once"
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
        switch kindEnum {
        case .once:
            guard let anchor = onceDate, anchor > after else { return [] }
            return [anchor]
        case .interval:
            guard let intervalMinutes, intervalMinutes > 0, let anchor = onceDate else { return [] }
            let step = TimeInterval(intervalMinutes * 60)
            var first: Date
            if anchor > after {
                first = anchor
            } else {
                let elapsed = after.timeIntervalSince(anchor)
                let steps = Int(elapsed / step) + 1
                first = anchor.addingTimeInterval(TimeInterval(steps) * step)
            }
            return (0..<count).map { first.addingTimeInterval(TimeInterval($0) * step) }
        case .daily, .weekly, .weekdays, .days:
            guard kindEnum != .days || !(weekdays ?? []).isEmpty else { return [] }
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
                if kindEnum == .weekly {
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
                if kindEnum == .weekdays, !(2...6).contains(dayOfWeek) {
                    continue
                }
                if kindEnum == .days, !(weekdays ?? []).contains(dayOfWeek) {
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

extension AssistantTaskRecord {
    public var triggerKind: AssistantTaskTriggerKind {
        AssistantTaskTriggerKind(rawValue: trigger) ?? .timer
    }

    public var lastOutcomeEnum: AssistantTaskOutcome? {
        lastOutcome.map(AssistantTaskOutcome.init(rawValue:))
    }

    public var lastRunAtDate: Date? {
        lastRunAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var lastMissedAtDate: Date? {
        lastMissedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var nextRunAtDate: Date? {
        nextRunAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var createdAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    public var updatedAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(updatedAt))
    }

    public var hasFailed: Bool {
        lastOutcome == "failed"
    }

    public var hasUnconfirmedRun: Bool {
        lastWorkerID != nil && lastOutcome == nil && lastRunAt != nil
    }

    public var statusLabel: String {
        if !enabled {
            return "Disabled"
        }
        if paused {
            return "Paused"
        }
        if lastOutcome == "failed" {
            return "Failed"
        }
        if lastOutcome == "missed" {
            return "Missed"
        }
        return "Active"
    }
}

extension AssistantTaskFailurePolicy {
    public var failureBehaviorEnum: AssistantTaskFailureBehavior {
        AssistantTaskFailureBehavior(rawValue: behavior) ?? .retryWithBackoff
    }
}

extension JSONValue {
    public init?(jsonText: String) {
        guard let data = jsonText.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return nil
        }
        self = value
    }

    public var displayText: String {
        if case .string(let text) = self {
            return text
        }
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }

    public var isPlainString: Bool {
        if case .string = self {
            return true
        }
        return false
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
    public var scheduleKind: AssistantTaskScheduleKind
    public var preservedSchedule: AssistantTaskSchedule?
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
        schedule: AssistantTaskSchedule = AssistantTaskSchedule(),
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
        self.scheduleKind = schedule.kindEnum
        self.preservedSchedule = nil
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
            if row.isJSON, JSONValue(jsonText: row.value) == nil {
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

    public func makeTask(id: UUID, existing: AssistantTaskRecord?, now: Date) -> AssistantTaskRecord? {
        guard let assistantID, let workspaceID else { return nil }
        var inputs: [String: JSONValue] = [:]
        for row in inputRows {
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            if row.isJSON {
                guard let value = JSONValue(jsonText: row.value) else { return nil }
                inputs[key] = value
            } else {
                inputs[key] = .string(row.value)
            }
        }
        var schedule = preservedSchedule ?? self.schedule
        if preservedSchedule == nil {
            schedule.kind = scheduleKind.rawValue
        }
        return AssistantTaskRecord(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            assistantID: assistantID,
            workspaceID: workspaceID,
            inputs: .object(inputs),
            schedule: schedule,
            trigger: trigger.rawValue,
            enabled: enabled,
            paused: paused,
            limits: AssistantTaskExecutionLimits(maxRuns: maxRuns, maxConcurrent: maxConcurrent),
            notifications: AssistantTaskNotificationPrefs(
                onSuccess: notifyOnSuccess,
                onFailure: notifyOnFailure,
                onMissed: notifyOnMissed
            ),
            failurePolicy: AssistantTaskFailurePolicy(
                behavior: failureBehavior.rawValue,
                maxRetries: maxRetries,
                backoffSeconds: backoffSeconds
            ),
            approval: AssistantTaskApprovalRequirements(
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
            createdAt: existing?.createdAt ?? Int64(now.timeIntervalSince1970),
            updatedAt: Int64(now.timeIntervalSince1970),
            extra: existing?.extra ?? [:]
        )
    }
}

public protocol AssistantTaskManaging: Sendable {
    func listTasks() async throws -> AssistantTaskList
    func saveTask(_ task: AssistantTaskRecord, baseline: String) async throws -> AssistantTaskRecord
    func deleteTask(id: UUID, baseline: String) async throws
    func setTaskEnabled(_ task: AssistantTaskRecord, enabled: Bool, baseline: String) async throws -> AssistantTaskRecord
    func setTaskPaused(_ task: AssistantTaskRecord, paused: Bool, baseline: String) async throws -> AssistantTaskRecord
    func runTaskNow(_ task: AssistantTaskRecord) async throws -> AssistantTaskRunOutcome
    func recoverMissedTasks() async throws -> [UUID]
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

    public var tasks: [AssistantTaskRecord] = []
    public var baseline: String = ""
    public var filter: AssistantTasksFilter = .all
    public var searchText: String = ""
    public var selectedTaskID: UUID?
    public var isLoading: Bool = false
    public var lastError: String?
    public var lastRunNowWorkerID: String?

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

    public var selectedTask: AssistantTaskRecord? {
        guard let selectedTaskID else { return nil }
        return tasks.first { $0.id == selectedTaskID }
    }

    public var filteredTasks: [AssistantTaskRecord] {
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
                guard task.isActive, let next = task.nextRunAtDate else { return false }
                return next > nowDate
            }
        case .recent:
            result = result.filter { $0.lastRunAtDate != nil }
        case .failed:
            result = result.filter { $0.lastOutcome == "failed" }
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
            return result.sorted { ($0.lastRunAtDate ?? .distantPast) > ($1.lastRunAtDate ?? .distantPast) }
        case .upcoming:
            return result.sorted { ($0.nextRunAtDate ?? .distantFuture) < ($1.nextRunAtDate ?? .distantFuture) }
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
            guard task.isActive, let next = task.nextRunAtDate else { return false }
            return next > nowDate
        }.count
        counts[.recent] = tasks.filter { $0.lastRunAtDate != nil }.count
        counts[.failed] = tasks.filter { $0.lastOutcome == "failed" }.count
        return counts
    }

    public func assistantDefinition(for task: AssistantTaskRecord) -> AssistantDefinition? {
        catalog.definition(forPersistenceID: task.assistantID)
    }

    public func assistantName(for task: AssistantTaskRecord) -> String {
        assistantDefinition(for: task)?.name ?? "Unknown assistant"
    }

    public func workspaceName(for task: AssistantTaskRecord) -> String {
        projects.first { $0.id == task.workspaceID }?.name ?? "Unknown workspace"
    }

    public func upcomingRuns(for task: AssistantTaskRecord, count: Int = 5) -> [Date] {
        let runs = task.schedule.upcomingRuns(after: now(), count: count)
        if !runs.isEmpty {
            return runs
        }
        if let next = task.nextRunAtDate, next > now() {
            return [next]
        }
        return []
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await reload()
    }

    private func reload() async {
        do {
            let listed = try await manager.listTasks()
            tasks = listed.tasks
            baseline = listed.baseline
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func recoverMissed() async -> [UUID] {
        do {
            let missed = try await manager.recoverMissedTasks()
            await reload()
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

    public func draftForTask(_ task: AssistantTaskRecord) -> AssistantTaskDraft {
        let rows = (task.inputs.objectValue ?? [:])
            .sorted { $0.key < $1.key }
            .map { key, value in
                AssistantTaskInputRow(key: key, value: value.displayText, isJSON: !value.isPlainString)
            }
        var draft = AssistantTaskDraft(
            name: task.name,
            assistantID: task.assistantID,
            workspaceID: task.workspaceID,
            inputRows: rows,
            schedule: task.schedule,
            trigger: task.triggerKind,
            enabled: task.enabled,
            paused: task.paused,
            maxRuns: task.limits.maxRuns,
            maxConcurrent: task.limits.maxConcurrent,
            notifyOnSuccess: task.notifications.onSuccess,
            notifyOnFailure: task.notifications.onFailure,
            notifyOnMissed: task.notifications.onMissed,
            failureBehavior: task.failurePolicy.failureBehaviorEnum,
            maxRetries: task.failurePolicy.maxRetries,
            backoffSeconds: task.failurePolicy.backoffSeconds,
            approvalRequired: task.approval.required,
            approvalActions: task.approval.actions
        )
        if task.schedule.kindEnum == .unknown {
            draft.preservedSchedule = task.schedule
        }
        return draft
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
            let saved = try await manager.saveTask(task, baseline: baseline)
            await reload()
            selectedTaskID = saved.id
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func delete(_ task: AssistantTaskRecord) async -> Bool {
        do {
            try await manager.deleteTask(id: task.id, baseline: baseline)
            await reload()
            if selectedTaskID == task.id {
                selectedTaskID = nil
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func setEnabled(_ task: AssistantTaskRecord, enabled: Bool) async -> Bool {
        do {
            _ = try await manager.setTaskEnabled(task, enabled: enabled, baseline: baseline)
            await reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func setPaused(_ task: AssistantTaskRecord, paused: Bool) async -> Bool {
        do {
            _ = try await manager.setTaskPaused(task, paused: paused, baseline: baseline)
            await reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func runNow(_ task: AssistantTaskRecord) async -> Bool {
        do {
            let result = try await manager.runTaskNow(task)
            lastRunNowWorkerID = result.workerID
            await reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
