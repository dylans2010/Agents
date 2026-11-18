import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Assistant tasks: filters, schedule visualization, editor validation, manager call-through")
struct AssistantTasksViewModelTests {

    private struct ScriptedTaskError: Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private final class ScriptedAssistantTaskManager: AssistantTaskManaging, @unchecked Sendable {
        var tasks: [AssistantTask] = []
        var failNext: (any Error)?
        var saved: [AssistantTask] = []
        var deleted: [UUID] = []
        var enabledChanges: [(UUID, Bool)] = []
        var pausedChanges: [(UUID, Bool)] = []
        var runNowIDs: [UUID] = []
        var runNowWorkerID: UUID = UUID()
        var due: [AssistantTaskDue] = []
        var markedMissed: [(UUID, String)] = []
        var recoverResult: [UUID] = []

        private func maybeThrow() throws {
            if let error = failNext {
                failNext = nil
                throw error
            }
        }

        func listTasks() async throws -> [AssistantTask] {
            try maybeThrow()
            return tasks
        }

        func saveTask(_ task: AssistantTask) async throws -> AssistantTask {
            try maybeThrow()
            saved.append(task)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = task
            } else {
                tasks.append(task)
            }
            return task
        }

        func deleteTask(id: UUID) async throws {
            try maybeThrow()
            deleted.append(id)
            tasks.removeAll { $0.id == id }
        }

        func setTaskEnabled(id: UUID, enabled: Bool) async throws -> AssistantTask {
            try maybeThrow()
            enabledChanges.append((id, enabled))
            guard let index = tasks.firstIndex(where: { $0.id == id }) else {
                throw ScriptedTaskError(message: "Task not found")
            }
            tasks[index].enabled = enabled
            return tasks[index]
        }

        func setTaskPaused(id: UUID, paused: Bool) async throws -> AssistantTask {
            try maybeThrow()
            pausedChanges.append((id, paused))
            guard let index = tasks.firstIndex(where: { $0.id == id }) else {
                throw ScriptedTaskError(message: "Task not found")
            }
            tasks[index].paused = paused
            return tasks[index]
        }

        func runTaskNow(id: UUID) async throws -> AssistantTaskRunNowResult {
            try maybeThrow()
            runNowIDs.append(id)
            guard let index = tasks.firstIndex(where: { $0.id == id }) else {
                throw ScriptedTaskError(message: "Task not found")
            }
            tasks[index].runCount += 1
            tasks[index].lastRunAt = Date()
            tasks[index].lastOutcome = nil
            tasks[index].lastWorkerID = runNowWorkerID
            return AssistantTaskRunNowResult(task: tasks[index], workerID: runNowWorkerID)
        }

        func dueTasks(now: Date) async throws -> [AssistantTaskDue] {
            try maybeThrow()
            return due
        }

        func markTaskMissed(id: UUID, reason: String) async throws -> AssistantTask {
            try maybeThrow()
            markedMissed.append((id, reason))
            guard let index = tasks.firstIndex(where: { $0.id == id }) else {
                throw ScriptedTaskError(message: "Task not found")
            }
            tasks[index].lastOutcome = .missed
            tasks[index].lastMessage = reason
            tasks[index].missedCount += 1
            return tasks[index]
        }

        func recoverMissedTasks(now: Date) async throws -> [UUID] {
            try maybeThrow()
            return recoverResult
        }
    }

    private static let assistantID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private static let workspaceID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    private static let otherWorkspaceID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!

    private static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private static func makeDefinition() -> AssistantDefinition {
        AssistantDefinition(
            id: "builtin.code-review-security.reviewer",
            name: "Reviewer",
            category: .codeReviewSecurity,
            systemPrompt: "Review the diff."
        )
    }

    private static func makeSchedule(
        kind: AssistantTaskScheduleKind = .daily,
        timeZoneID: String = "America/New_York",
        date: Date = utcDate(2026, 11, 18),
        hour: Int = 9,
        minute: Int = 0,
        weekday: Int = 2,
        weekdays: [Int]? = nil,
        intervalMinutes: Int? = nil,
        cron: String? = nil
    ) -> AssistantTaskSchedule {
        AssistantTaskSchedule(
            kind: kind,
            timeZoneID: timeZoneID,
            date: date,
            hour: hour,
            minute: minute,
            weekday: weekday,
            weekdays: weekdays,
            intervalMinutes: intervalMinutes,
            cron: cron
        )
    }

    private static func makeTask(
        id: UUID = UUID(),
        name: String = "Nightly review",
        assistantID: UUID = assistantID,
        workspaceID: UUID = workspaceID,
        enabled: Bool = true,
        paused: Bool = false,
        schedule: AssistantTaskSchedule = makeSchedule(),
        trigger: AssistantTaskTriggerKind = .timer,
        runCount: Int = 0,
        lastRunAt: Date? = nil,
        lastOutcome: AssistantTaskOutcome? = nil,
        lastMessage: String? = nil,
        missedCount: Int = 0,
        nextRunAt: Date? = nil,
        inputs: [String: AssistantTaskInputValue] = [:]
    ) -> AssistantTask {
        AssistantTask(
            id: id,
            name: name,
            assistantID: assistantID,
            workspaceID: workspaceID,
            inputs: inputs,
            schedule: schedule,
            trigger: trigger,
            enabled: enabled,
            paused: paused,
            runCount: runCount,
            lastRunAt: lastRunAt,
            lastOutcome: lastOutcome,
            lastMessage: lastMessage,
            missedCount: missedCount,
            nextRunAt: nextRunAt
        )
    }

    @MainActor
    private static func makeViewModel(
        manager: ScriptedAssistantTaskManager,
        now: Date = utcDate(2026, 11, 18, 12)
    ) -> AssistantTasksViewModel {
        let definition = makeDefinition()
        let catalog = AssistantCatalog(builtIns: [definition])
        let projects = [
            RemoteProject(id: workspaceID, name: "SwiftCode", path: "/tmp/SwiftCode"),
            RemoteProject(id: otherWorkspaceID, name: "Notes", path: "/tmp/Notes"),
        ]
        return AssistantTasksViewModel(manager: manager, catalog: catalog, projects: projects, now: { now })
    }

    private static func makeDraft(
        name: String = "Nightly review",
        assistantID: UUID? = assistantID,
        workspaceID: UUID? = workspaceID
    ) -> AssistantTaskDraft {
        AssistantTaskDraft(
            name: name,
            assistantID: assistantID,
            workspaceID: workspaceID,
            inputRows: [AssistantTaskInputRow(key: "branch", value: "main")],
            schedule: makeSchedule()
        )
    }

    @Test("All filter returns every task")
    @MainActor
    func filterAllReturnsEveryTask() async {
        let manager = ScriptedAssistantTaskManager()
        manager.tasks = [
            makeTask(name: "A"),
            makeTask(name: "B", paused: true),
            makeTask(name: "C", enabled: false),
        ]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        viewModel.filter = .all
        #expect(viewModel.filteredTasks.map(\.name) == ["A", "B", "C"])
        #expect(viewModel.countsByFilter[.all] == 3)
    }

    @Test("Active filter excludes paused and disabled tasks")
    @MainActor
    func filterActiveExcludesPausedAndDisabled() async {
        let manager = ScriptedAssistantTaskManager()
        manager.tasks = [
            makeTask(name: "Active"),
            makeTask(name: "Paused", paused: true),
            makeTask(name: "Disabled", enabled: false),
        ]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        viewModel.filter = .active
        #expect(viewModel.filteredTasks.map(\.name) == ["Active"])
        #expect(viewModel.countsByFilter[.active] == 1)
        #expect(viewModel.countsByFilter[.paused] == 1)
    }

    @Test("Paused filter returns only paused tasks")
    @MainActor
    func filterPausedReturnsOnlyPaused() async {
        let manager = ScriptedAssistantTaskManager()
        manager.tasks = [
            makeTask(name: "Active"),
            makeTask(name: "Paused", paused: true),
        ]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        viewModel.filter = .paused
        #expect(viewModel.filteredTasks.map(\.name) == ["Paused"])
    }

    @Test("Upcoming filter needs an active task with a future stored next run")
    @MainActor
    func filterUpcomingRequiresFutureNextRun() async {
        let now = utcDate(2026, 11, 18, 12)
        let manager = ScriptedAssistantTaskManager()
        manager.tasks = [
            makeTask(name: "Soon", nextRunAt: utcDate(2026, 11, 18, 14)),
            makeTask(name: "Past", nextRunAt: utcDate(2026, 11, 18, 10)),
            makeTask(name: "PausedSoon", paused: true, nextRunAt: utcDate(2026, 11, 18, 14)),
            makeTask(name: "NoNextRun"),
        ]
        let viewModel = makeViewModel(manager: manager, now: now)
        await viewModel.refresh()
        viewModel.filter = .upcoming
        #expect(viewModel.filteredTasks.map(\.name) == ["Soon"])
        #expect(viewModel.countsByFilter[.upcoming] == 1)
    }

    @Test("Recent filter orders by last run, newest first")
    @MainActor
    func filterRecentOrdersByLastRun() async {
        let manager = ScriptedAssistantTaskManager()
        manager.tasks = [
            makeTask(name: "Older", lastRunAt: utcDate(2026, 11, 17, 9)),
            makeTask(name: "Newer", lastRunAt: utcDate(2026, 11, 18, 9)),
            makeTask(name: "Never"),
        ]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        viewModel.filter = .recent
        #expect(viewModel.filteredTasks.map(\.name) == ["Newer", "Older"])
        #expect(viewModel.countsByFilter[.recent] == 2)
    }

    @Test("Failed filter returns only tasks whose last outcome failed")
    @MainActor
    func filterFailedReturnsOnlyFailedOutcome() async {
        let manager = ScriptedAssistantTaskManager()
        manager.tasks = [
            makeTask(name: "Failed", lastOutcome: .failed),
            makeTask(name: "Missed", lastOutcome: .missed),
            makeTask(name: "Completed", lastOutcome: .completed),
        ]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        viewModel.filter = .failed
        #expect(viewModel.filteredTasks.map(\.name) == ["Failed"])
        #expect(viewModel.countsByFilter[.failed] == 1)
    }

    @Test("Search matches task name, assistant name, and workspace name")
    @MainActor
    func searchMatchesNameAssistantAndWorkspace() async {
        let manager = ScriptedAssistantTaskManager()
        manager.tasks = [
            makeTask(name: "Nightly review"),
            makeTask(name: "Other", workspaceID: otherWorkspaceID),
        ]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        viewModel.searchText = "review"
        #expect(viewModel.filteredTasks.map(\.name) == ["Nightly review", "Other"])
        viewModel.searchText = "notes"
        #expect(viewModel.filteredTasks.map(\.name) == ["Other"])
        viewModel.searchText = "nope"
        #expect(viewModel.filteredTasks.isEmpty)
    }

    @Test("Schedule summaries describe each recurrence kind")
    @MainActor
    func scheduleSummariesDescribeKinds() {
        #expect(makeSchedule(kind: .daily).summary.contains("Daily"))
        #expect(makeSchedule(kind: .daily).summary.contains("9:00"))
        #expect(makeSchedule(kind: .weekly, weekday: 2).summary.contains("Weekly"))
        #expect(makeSchedule(kind: .weekly, weekday: 2).summary.contains("Monday"))
        #expect(makeSchedule(kind: .weekdays).summary.contains("Weekdays"))
        #expect(makeSchedule(kind: .days, weekdays: [2, 4]).summary.contains("Monday"))
        #expect(makeSchedule(kind: .interval, intervalMinutes: 60).summary == "Every hour")
        #expect(makeSchedule(kind: .interval, intervalMinutes: 90).summary == "Every 90 minutes")
        #expect(makeSchedule(kind: .cron, cron: "0 9 * * *").summary == "Cron: 0 9 * * *")
        #expect(makeSchedule(kind: .unknown).summary == "Custom schedule")
    }

    @Test("Daily upcoming runs follow the schedule time zone")
    @MainActor
    func upcomingRunsDailyFollowScheduleTimeZone() {
        let now = utcDate(2026, 11, 18, 12)
        let runs = makeSchedule(kind: .daily).upcomingRuns(after: now, count: 3)
        #expect(runs == [utcDate(2026, 11, 18, 14), utcDate(2026, 11, 19, 14), utcDate(2026, 11, 20, 14)])
    }

    @Test("Weekly upcoming runs skip other weekdays")
    @MainActor
    func upcomingRunsWeeklySkipOtherDays() {
        let now = utcDate(2026, 11, 18, 12)
        let runs = makeSchedule(kind: .weekly, weekday: 2).upcomingRuns(after: now, count: 2)
        #expect(runs == [utcDate(2026, 11, 23, 14), utcDate(2026, 11, 30, 14)])
    }

    @Test("Weekday upcoming runs skip Saturday and Sunday")
    @MainActor
    func upcomingRunsWeekdaysSkipWeekend() {
        let now = utcDate(2026, 11, 20, 12)
        let runs = makeSchedule(kind: .weekdays).upcomingRuns(after: now, count: 2)
        #expect(runs == [utcDate(2026, 11, 20, 14), utcDate(2026, 11, 23, 14)])
    }

    @Test("Interval upcoming runs step from the anchor")
    @MainActor
    func upcomingRunsIntervalStepFromAnchor() {
        let now = utcDate(2026, 11, 18, 12, 30)
        let schedule = makeSchedule(
            kind: .interval,
            date: utcDate(2026, 11, 18, 0),
            intervalMinutes: 60
        )
        #expect(schedule.upcomingRuns(after: now, count: 3) == [
            utcDate(2026, 11, 18, 13), utcDate(2026, 11, 18, 14), utcDate(2026, 11, 18, 15),
        ])
    }

    @Test("Once upcoming runs return the date only while it is in the future")
    @MainActor
    func upcomingRunsOnceOnlyWhileFuture() {
        let now = utcDate(2026, 11, 18, 12)
        let future = makeSchedule(kind: .once, date: utcDate(2026, 11, 20, 14))
        #expect(future.upcomingRuns(after: now, count: 3) == [utcDate(2026, 11, 20, 14)])
        let past = makeSchedule(kind: .once, date: utcDate(2026, 11, 17, 14))
        #expect(past.upcomingRuns(after: now, count: 3).isEmpty)
    }

    @Test("Cron and unknown schedules provide no computed runs")
    @MainActor
    func upcomingRunsCronAndUnknownAreEmpty() {
        let now = utcDate(2026, 11, 18, 12)
        #expect(makeSchedule(kind: .cron, cron: "0 9 * * *").upcomingRuns(after: now, count: 3).isEmpty)
        #expect(makeSchedule(kind: .unknown).upcomingRuns(after: now, count: 3).isEmpty)
    }

    @Test("ViewModel falls back to the stored next run when the schedule cannot compute runs")
    @MainActor
    func viewModelFallsBackToStoredNextRun() async {
        let manager = ScriptedAssistantTaskManager()
        let task = makeTask(
            schedule: makeSchedule(kind: .cron, cron: "0 9 * * *"),
            nextRunAt: utcDate(2026, 11, 19, 14)
        )
        manager.tasks = [task]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        #expect(viewModel.upcomingRuns(for: task) == [utcDate(2026, 11, 19, 14)])
    }

    @Test("Every non-timer trigger is unavailable with a reason")
    @MainActor
    func unavailableTriggersCarryReasons() {
        #expect(AssistantTaskTriggerKind.timer.isAvailable)
        #expect(AssistantTaskTriggerKind.timer.unavailableReason == nil)
        for kind in AssistantTaskTriggerKind.allCases where kind != .timer {
            #expect(!kind.isAvailable)
            let reason = kind.unavailableReason
            #expect(reason != nil)
            #expect(reason?.contains("not available") == true)
        }
        #expect(AssistantTaskTriggerKind.gitCommit.unavailableReason?.contains("git watcher") == true)
        #expect(AssistantTaskTriggerKind.fileChange.unavailableReason?.contains("file watcher") == true)
    }

    @Test("Draft validation rejects an empty name and missing assistant or workspace")
    @MainActor
    func draftValidationRejectsMissingRequiredFields() {
        #expect(makeDraft(name: "  ").validationIssues().contains(.emptyName))
        #expect(makeDraft(assistantID: nil).validationIssues().contains(.missingAssistant))
        #expect(makeDraft(workspaceID: nil).validationIssues().contains(.missingWorkspace))
        #expect(makeDraft().validationIssues().isEmpty)
    }

    @Test("Draft validation rejects duplicate and empty input keys and invalid JSON values")
    @MainActor
    func draftValidationRejectsBadInputs() {
        var draft = makeDraft()
        draft.inputRows = [
            AssistantTaskInputRow(key: "branch", value: "main"),
            AssistantTaskInputRow(key: "branch", value: "dev"),
        ]
        #expect(draft.validationIssues().contains(.duplicateInputKey(key: "branch")))
        draft.inputRows = [AssistantTaskInputRow(key: " ", value: "main")]
        #expect(draft.validationIssues().contains(.emptyInputKey(index: 0)))
        draft.inputRows = [AssistantTaskInputRow(key: "config", value: "{broken", isJSON: true)]
        #expect(draft.validationIssues().contains(.invalidJSONInput(key: "config")))
        draft.inputRows = [AssistantTaskInputRow(key: "config", value: "{\"a\": 1}", isJSON: true)]
        #expect(draft.validationIssues().isEmpty)
    }

    @Test("Draft validation rejects approval actions without approval required")
    @MainActor
    func draftValidationRejectsApprovalActionsWithoutRequirement() {
        var draft = makeDraft()
        draft.approvalActions = ["write_file"]
        #expect(draft.validationIssues().contains(.approvalActionsWithoutRequirement))
        draft.approvalRequired = true
        #expect(draft.validationIssues().isEmpty)
        draft.approvalActions = ["write_file", "write_file"]
        #expect(draft.validationIssues().contains(.duplicateApprovalAction(name: "write_file")))
    }

    @Test("Saving a valid draft calls the manager and adds the task")
    @MainActor
    func saveDraftCallsManagerAndAddsTask() async {
        let manager = ScriptedAssistantTaskManager()
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        let saved = await viewModel.saveDraft(makeDraft(), editingTaskID: nil)
        #expect(saved)
        #expect(manager.saved.count == 1)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks[0].name == "Nightly review")
        #expect(viewModel.tasks[0].inputs["branch"] == .string("main"))
        #expect(viewModel.lastError == nil)
    }

    @Test("Saving an invalid draft never reaches the manager")
    @MainActor
    func saveInvalidDraftNeverReachesManager() async {
        let manager = ScriptedAssistantTaskManager()
        let viewModel = makeViewModel(manager: manager)
        let saved = await viewModel.saveDraft(makeDraft(name: ""), editingTaskID: nil)
        #expect(!saved)
        #expect(manager.saved.isEmpty)
        #expect(viewModel.lastError?.contains("name") == true)
    }

    @Test("Saving surfaces the manager error and keeps the old list")
    @MainActor
    func saveDraftSurfacesManagerError() async {
        let manager = ScriptedAssistantTaskManager()
        manager.tasks = [makeTask(name: "Existing")]
        manager.failNext = ScriptedTaskError(message: "Automated task name must contain 1-1024 characters")
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        let saved = await viewModel.saveDraft(makeDraft(), editingTaskID: nil)
        #expect(!saved)
        #expect(viewModel.lastError == "Automated task name must contain 1-1024 characters")
        #expect(viewModel.tasks.map(\.name) == ["Existing"])
    }

    @Test("Enable and disable call through to the manager")
    @MainActor
    func setEnabledCallsManager() async {
        let manager = ScriptedAssistantTaskManager()
        let task = makeTask()
        manager.tasks = [task]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        #expect(await viewModel.setEnabled(task, enabled: false))
        #expect(manager.enabledChanges.map { $0.1 } == [false])
        #expect(viewModel.tasks[0].enabled == false)
        #expect(await viewModel.setEnabled(task, enabled: true))
        #expect(viewModel.tasks[0].enabled == true)
    }

    @Test("Pause and resume call through to the manager")
    @MainActor
    func setPausedCallsManager() async {
        let manager = ScriptedAssistantTaskManager()
        let task = makeTask()
        manager.tasks = [task]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        #expect(await viewModel.setPaused(task, paused: true))
        #expect(manager.pausedChanges.map { $0.1 } == [true])
        #expect(viewModel.tasks[0].paused == true)
    }

    @Test("Delete calls the manager, removes the task, and clears the selection")
    @MainActor
    func deleteCallsManagerAndClearsSelection() async {
        let manager = ScriptedAssistantTaskManager()
        let task = makeTask()
        manager.tasks = [task]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        viewModel.selectedTaskID = task.id
        #expect(await viewModel.delete(task))
        #expect(manager.deleted == [task.id])
        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.selectedTaskID == nil)
    }

    @Test("Delete surfaces the manager error and keeps the task")
    @MainActor
    func deleteSurfacesManagerError() async {
        let manager = ScriptedAssistantTaskManager()
        let task = makeTask()
        manager.tasks = [task]
        manager.failNext = ScriptedTaskError(message: "Automated task not found")
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        #expect(await viewModel.delete(task) == false)
        #expect(viewModel.lastError == "Automated task not found")
        #expect(viewModel.tasks.count == 1)
    }

    @Test("Run now calls the manager and records the spawned worker")
    @MainActor
    func runNowCallsManagerAndRecordsWorker() async {
        let manager = ScriptedAssistantTaskManager()
        let task = makeTask(runCount: 2)
        manager.tasks = [task]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        #expect(await viewModel.runNow(task))
        #expect(manager.runNowIDs == [task.id])
        #expect(viewModel.lastRunNowWorkerID == manager.runNowWorkerID)
        #expect(viewModel.tasks[0].runCount == 3)
        #expect(viewModel.tasks[0].hasRunningWorker)
    }

    @Test("Run now surfaces the manager error")
    @MainActor
    func runNowSurfacesManagerError() async {
        let manager = ScriptedAssistantTaskManager()
        let task = makeTask(paused: true)
        manager.tasks = [task]
        manager.failNext = ScriptedTaskError(message: "Automated task 'Nightly review' is paused; run-now is rejected")
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        #expect(await viewModel.runNow(task) == false)
        #expect(viewModel.lastError?.contains("paused") == true)
        #expect(manager.runNowIDs.isEmpty)
    }

    @Test("Recover returns the missed ids and reloads the list")
    @MainActor
    func recoverMissedReturnsIDsAndReloads() async {
        let manager = ScriptedAssistantTaskManager()
        let missedID = UUID()
        manager.tasks = [makeTask(name: "Overdue")]
        manager.recoverResult = [missedID]
        let viewModel = makeViewModel(manager: manager)
        let missed = await viewModel.recoverMissed()
        #expect(missed == [missedID])
        #expect(viewModel.tasks.map(\.name) == ["Overdue"])
    }

    @Test("Due tasks come from the manager")
    @MainActor
    func dueTasksComeFromManager() async {
        let manager = ScriptedAssistantTaskManager()
        let task = makeTask()
        manager.due = [
            AssistantTaskDue(
                taskID: task.id,
                taskName: task.name,
                occurrence: utcDate(2026, 11, 18, 9),
                nextRunAt: utcDate(2026, 11, 18, 9),
                runCount: 0
            )
        ]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refreshDue()
        #expect(viewModel.dueTasksList.map(\.taskID) == [task.id])
        #expect(viewModel.dueTasksList[0].taskName == "Nightly review")
    }

    @Test("Marking a run missed records the outcome through the manager")
    @MainActor
    func markMissedCallsManager() async {
        let manager = ScriptedAssistantTaskManager()
        let task = makeTask()
        manager.tasks = [task]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        #expect(await viewModel.markMissed(task, reason: "Host was asleep."))
        #expect(manager.markedMissed.map { $0.1 } == ["Host was asleep."])
        #expect(viewModel.tasks[0].lastOutcome == .missed)
        #expect(viewModel.tasks[0].missedCount == 1)
    }

    @Test("Refresh surfaces a list failure")
    @MainActor
    func refreshSurfacesListFailure() async {
        let manager = ScriptedAssistantTaskManager()
        manager.failNext = ScriptedTaskError(message: "Automated tasks document is invalid")
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        #expect(viewModel.lastError == "Automated tasks document is invalid")
        #expect(viewModel.tasks.isEmpty)
    }

    @Test("Task JSON round-trips string inputs, JSON inputs, and unknown fields")
    @MainActor
    func taskJSONRoundTrip() throws {
        let task = makeTask(
            inputs: [
                "branch": .string("main"),
                "count": .json(.number(3)),
                "flags": .json(.object(["strict": .bool(true)])),
            ]
        )
        var withExtra = task
        withExtra.extra = ["futureField": .object(["keep": .bool(true)])]
        let data = try JSONEncoder().encode(withExtra)
        let decoded = try JSONDecoder().decode(AssistantTask.self, from: data)
        #expect(decoded.inputs == withExtra.inputs)
        #expect(decoded.extra == withExtra.extra)
        #expect(decoded.schedule.kind == .daily)
        #expect(decoded.trigger == .timer)
    }

    @Test("Task JSON decodes the Rust envelope with epoch timestamps and an ISO schedule date")
    @MainActor
    func taskJSONDecodesRustEnvelope() throws {
        let json = """
        {
            "id": "00000000-0000-4000-8000-000000000001",
            "name": "Nightly review",
            "assistantId": "00000000-0000-4000-8000-000000000002",
            "workspaceId": "00000000-0000-4000-8000-000000000003",
            "inputs": {"branch": "main"},
            "schedule": {
                "kind": "daily",
                "timeZoneID": "America/New_York",
                "date": "2026-11-18T09:00:00Z",
                "hour": 9,
                "minute": 0,
                "weekday": 4
            },
            "trigger": "timer",
            "enabled": true,
            "paused": false,
            "limits": {"maxRuns": null, "maxConcurrent": 1},
            "notifications": {"onSuccess": false, "onFailure": true, "onMissed": true},
            "failurePolicy": {"behavior": "retryWithBackoff", "maxRetries": 3, "backoffSeconds": 300},
            "approval": {"required": false, "actions": []},
            "runCount": 2,
            "lastRunAt": 1794513600,
            "lastOutcome": "completed",
            "lastMessage": null,
            "lastMissedAt": null,
            "missedCount": 1,
            "lastWorkerId": null,
            "nextRunAt": 1794600000,
            "createdAt": 1000000,
            "updatedAt": 1000000
        }
        """
        let decoded = try JSONDecoder().decode(AssistantTask.self, from: Data(json.utf8))
        #expect(decoded.name == "Nightly review")
        #expect(decoded.inputs["branch"] == .string("main"))
        #expect(decoded.schedule.kind == .daily)
        #expect(decoded.schedule.timeZoneID == "America/New_York")
        #expect(decoded.runCount == 2)
        #expect(decoded.lastOutcome == .completed)
        #expect(decoded.missedCount == 1)
        #expect(decoded.nextRunAt == Date(timeIntervalSince1970: 1794600000))
    }

    @Test("Editing a draft preserves run bookkeeping")
    @MainActor
    func editingDraftPreservesBookkeeping() {
        let task = makeTask(runCount: 5, lastOutcome: .failed, lastMessage: "Worker crashed", missedCount: 2)
        let viewModel = makeViewModel(manager: ScriptedAssistantTaskManager())
        let draft = viewModel.draftForTask(task)
        let rebuilt = draft.makeTask(id: task.id, existing: task, now: utcDate(2026, 11, 18, 12))
        #expect(rebuilt?.runCount == 5)
        #expect(rebuilt?.lastOutcome == .failed)
        #expect(rebuilt?.lastMessage == "Worker crashed")
        #expect(rebuilt?.missedCount == 2)
        #expect(rebuilt?.createdAt == task.createdAt)
    }

    @Test("A new-task draft defaults to the first non-chats project")
    @MainActor
    func newTaskDraftDefaultsWorkspace() {
        let viewModel = makeViewModel(manager: ScriptedAssistantTaskManager())
        let definition = Self.makeDefinition()
        let draft = viewModel.draftForNewTask(assistant: definition)
        #expect(draft.assistantID == definition.persistenceID)
        #expect(draft.workspaceID == Self.workspaceID)
        #expect(draft.trigger == .timer)
        #expect(draft.enabled)
        #expect(!draft.paused)
    }

    @Test("Assistant and workspace names resolve from the catalog and projects")
    @MainActor
    func namesResolveFromCatalogAndProjects() async {
        let manager = ScriptedAssistantTaskManager()
        let task = makeTask()
        manager.tasks = [task]
        let viewModel = makeViewModel(manager: manager)
        await viewModel.refresh()
        #expect(viewModel.assistantName(for: task) == "Reviewer")
        #expect(viewModel.workspaceName(for: task) == "SwiftCode")
        let unknown = makeTask(assistantID: UUID(), workspaceID: UUID())
        #expect(viewModel.assistantName(for: unknown) == "Unknown assistant")
        #expect(viewModel.workspaceName(for: unknown) == "Unknown workspace")
    }
}
