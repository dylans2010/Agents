import CoincideRemoteKit
import Foundation
import Testing
import UserNotifications
@testable import Agents

@Suite("Assistant Task Manager: CRUD, CAS, Run-Now, Due Poll, Recover")
struct AssistantTaskManagerTests {

    private struct FakeStaleBaselineError: Error, LocalizedError {
        var errorDescription: String? {
            "Automated task document changed; reload before saving"
        }
    }

    private struct FakeTaskError: Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private final class RecordingPoster: AssistantNotificationPosting, @unchecked Sendable {
        var requests: [UNNotificationRequest] = []

        func add(_ request: UNNotificationRequest) {
            requests.append(request)
        }
    }

    private actor FakeTaskRuntime: AssistantTaskRuntime {
        var tasks: [AssistantTaskRecord] = []
        var workers: [String: WorkerRecord] = [:]
        var baseline: String = String(repeating: "a", count: 64)
        var baselineCounter = 0
        var assistants: [RemoteAssistant] = []
        var workspace = RemoteWorkspace()
        var now: Int64 = 1_790_000_000
        var parentThreadID = UUID()
        var newThreadProjectIDs: [UUID] = []
        var deleteParentThreadCalls: [UUID] = []
        var deleteParentThreadError: Error?
        var listAssistantsCalls = 0
        var fetchWorkspaceCalls = 0
        var extraListValues: [JSONValue] = []
        var extraDueValues: [JSONValue] = []
        var listTasksError: Error?
        var dueError: Error?
        var listAssistantsError: Error?
        var fetchWorkspaceError: Error?
        var saveOmitsTask = false
        var runNowOmitsTask = false
        var runNowCalls: [(taskId: String, parentThreadId: String)] = []
        var markMissedCalls: [(taskId: String, reason: String)] = []
        var recoverCalls = 0
        var runNowError: Error?
        var recordOutcomeCalls: [(taskId: String, workerId: String)] = []
        var recordOutcomeError: Error?
        var workerStatusError: Error?

        func setTasks(_ value: [AssistantTaskRecord]) { tasks = value }
        func setWorker(_ value: WorkerRecord) { workers[value.id] = value }
        func setAssistants(_ value: [RemoteAssistant]) { assistants = value }
        func setWorkspace(_ value: RemoteWorkspace) { workspace = value }
        func setNow(_ value: Int64) { now = value }
        func setRunNowError(_ value: Error?) { runNowError = value }
        func setRecordOutcomeError(_ value: Error?) { recordOutcomeError = value }
        func setWorkerStatusError(_ value: Error?) { workerStatusError = value }
        func setParentThreadID(_ value: UUID) { parentThreadID = value }
        func setDeleteParentThreadError(_ value: Error?) { deleteParentThreadError = value }
        func setExtraListValues(_ value: [JSONValue]) { extraListValues = value }
        func setExtraDueValues(_ value: [JSONValue]) { extraDueValues = value }
        func setListTasksError(_ value: Error?) { listTasksError = value }
        func setDueError(_ value: Error?) { dueError = value }
        func setListAssistantsError(_ value: Error?) { listAssistantsError = value }
        func setFetchWorkspaceError(_ value: Error?) { fetchWorkspaceError = value }
        func setSaveOmitsTask(_ value: Bool) { saveOmitsTask = value }
        func setRunNowOmitsTask(_ value: Bool) { runNowOmitsTask = value }

        static func makeWorker(
            id: String, parentThreadId: String, threadId: String = UUID().uuidString,
            status: String, result: String? = nil, error: String? = nil
        ) -> WorkerRecord {
            WorkerRecord(
                id: id, name: "Nightly review", parentThreadId: parentThreadId,
                threadId: threadId, task: "Review the change.", provider: "claude",
                targetFiles: [], status: status, cancelRequested: false,
                transcriptStart: 0, transcriptItems: 0, elapsedSeconds: 0,
                createdAt: 1000, startedAt: 1000, completedAt: nil, error: error,
                result: result, progress: nil
            )
        }

        private func rotateBaseline() {
            baselineCounter += 1
            baseline = String(format: "%064x", baselineCounter)
        }

        private func taskResult(_ task: AssistantTaskRecord) -> JSONValue {
            .object([
                "task": (try? task.encoded()) ?? .null,
                "baseline": .string(baseline),
                "origin": .string("local"),
                "version": .int(1),
            ])
        }

        private func markMissedLocked(_ task: inout AssistantTaskRecord, reason: String) {
            task.lastOutcome = "missed"
            task.lastMessage = reason
            task.lastMissedAt = now
            task.missedCount += 1
            task.nextRunAt = now + 86_400
            task.updatedAt = now
        }

        func tasksList() async throws -> JSONValue {
            if let listTasksError {
                throw listTasksError
            }
            let values = try tasks.map { try $0.encoded() } + extraListValues
            return .object([
                "tasks": .array(values),
                "baseline": .string(baseline),
                "origin": .string("local"),
                "version": .int(1),
            ])
        }

        func tasksSave(task: JSONValue, baseline: String) async throws -> JSONValue {
            guard baseline == self.baseline else {
                throw FakeStaleBaselineError()
            }
            var incoming = try AssistantTaskRecord(json: task)
            if let reason = AssistantTaskManager.unavailableTriggerReason(incoming.trigger) {
                throw FakeTaskError(message: reason)
            }
            if let index = tasks.firstIndex(where: { $0.id == incoming.id }) {
                let stored = tasks[index]
                incoming.createdAt = stored.createdAt
                incoming.runCount = stored.runCount
                incoming.lastRunAt = stored.lastRunAt
                incoming.lastOutcome = stored.lastOutcome
                incoming.lastMessage = stored.lastMessage
                incoming.lastMissedAt = stored.lastMissedAt
                incoming.missedCount = stored.missedCount
                incoming.lastWorkerID = stored.lastWorkerID
                incoming.activeWorkerIds = stored.activeWorkerIds
                incoming.history = stored.history
                incoming.consecutiveFailures = stored.consecutiveFailures
                incoming.updatedAt = now
                tasks[index] = incoming
            } else {
                incoming.createdAt = now
                incoming.updatedAt = now
                tasks.append(incoming)
            }
            rotateBaseline()
            if saveOmitsTask {
                return .object(["baseline": .string(baseline), "origin": .string("local"), "version": .int(1)])
            }
            return taskResult(incoming)
        }

        func tasksDelete(taskId: String, baseline: String) async throws -> JSONValue {
            guard baseline == self.baseline else {
                throw FakeStaleBaselineError()
            }
            guard let index = tasks.firstIndex(where: { $0.id.uuidString == taskId }) else {
                throw FakeTaskError(message: "Automated task not found")
            }
            tasks.remove(at: index)
            rotateBaseline()
            return .object(["deleted": .bool(true), "taskId": .string(taskId)])
        }

        func tasksRunNow(taskId: String, parentThreadId: String) async throws -> JSONValue {
            if let runNowError {
                throw runNowError
            }
            guard let index = tasks.firstIndex(where: { $0.id.uuidString == taskId }) else {
                throw FakeTaskError(message: "Automated task not found")
            }
            runNowCalls.append((taskId: taskId, parentThreadId: parentThreadId))
            tasks[index].runCount += 1
            tasks[index].lastRunAt = now
            tasks[index].lastWorkerID = "worker-1"
            if !tasks[index].activeWorkerIds.contains("worker-1") {
                tasks[index].activeWorkerIds.append("worker-1")
            }
            workers["worker-1"] = Self.makeWorker(
                id: "worker-1", parentThreadId: parentThreadId, status: "running"
            )
            tasks[index].lastOutcome = nil
            tasks[index].lastMessage = nil
            tasks[index].nextRunAt = now + 86_400
            tasks[index].updatedAt = now
            rotateBaseline()
            var result = taskResult(tasks[index])
            if case .object(var object) = result {
                object["worker"] = .object(["id": .string("worker-1")])
                result = .object(object)
            }
            if runNowOmitsTask, case .object(var object) = result {
                object.removeValue(forKey: "task")
                result = .object(object)
            }
            return result
        }

        func workerStatus(workerId: String) async throws -> WorkerRecord {
            if let workerStatusError {
                self.workerStatusError = nil
                throw workerStatusError
            }
            guard let worker = workers[workerId] else {
                throw FakeTaskError(message: "Unknown worker")
            }
            return worker
        }

        func tasksRecordOutcome(taskId: String, workerId: String) async throws -> JSONValue {
            if let recordOutcomeError {
                throw recordOutcomeError
            }
            guard let index = tasks.firstIndex(where: { $0.id.uuidString == taskId }) else {
                throw FakeTaskError(message: "Automated task not found")
            }
            recordOutcomeCalls.append((taskId: taskId, workerId: workerId))
            guard let worker = workers[workerId] else {
                recordOutcomeLocked(
                    &tasks[index], workerID: workerId, status: "cancelled",
                    summary: "Worker record is gone; its outcome cannot be determined",
                    parentThreadID: nil
                )
                rotateBaseline()
                return recordOutcomeResult(tasks[index], outcome: "interrupted", retryScheduled: false, notifyRequested: false, parentThreadID: nil, workerID: workerId)
            }
            guard worker.isTerminal else {
                throw FakeTaskError(message: "Worker '\(workerId)' has not finished; its status is '\(worker.status)'")
            }
            let outcome = worker.status == "completed" ? "completed" : worker.status == "failed" ? "failed" : "interrupted"
            let summary = outcome == "completed" ? (worker.result ?? "") : (worker.error ?? "")
            recordOutcomeLocked(
                &tasks[index], workerID: workerId, status: worker.status,
                summary: summary, parentThreadID: worker.parentThreadId
            )
            let retryScheduled = outcome == "failed"
                && tasks[index].failurePolicy.behavior == "retryWithBackoff"
                && tasks[index].consecutiveFailures <= tasks[index].failurePolicy.maxRetries
            let notifyRequested = outcome == "failed" && tasks[index].failurePolicy.behavior == "notify"
            rotateBaseline()
            return recordOutcomeResult(
                tasks[index], outcome: outcome, retryScheduled: retryScheduled,
                notifyRequested: notifyRequested, parentThreadID: worker.parentThreadId, workerID: workerId
            )
        }

        private func recordOutcomeLocked(
            _ task: inout AssistantTaskRecord, workerID: String, status: String,
            summary: String, parentThreadID: String?
        ) {
            let outcome = status == "completed" ? "completed" : status == "failed" ? "failed" : "interrupted"
            task.activeWorkerIds.removeAll { $0 == workerID }
            task.lastWorkerID = workerID
            task.lastOutcome = outcome
            task.lastMessage = summary.isEmpty ? "Worker run was interrupted." : summary
            task.lastRunAt = now
            task.updatedAt = now
            task.history.append(AssistantTaskHistoryEntry(at: now, outcome: outcome, workerID: workerID, message: task.lastMessage ?? ""))
            if task.history.count > 50 {
                task.history.removeFirst(task.history.count - 50)
            }
            if outcome == "failed" {
                task.consecutiveFailures += 1
                if task.failurePolicy.behavior == "retryWithBackoff"
                    && task.consecutiveFailures <= task.failurePolicy.maxRetries {
                    task.nextRunAt = now + Int64(task.failurePolicy.backoffSeconds)
                } else {
                    task.nextRunAt = now + 86_400
                }
            } else {
                task.consecutiveFailures = 0
                task.nextRunAt = now + 86_400
            }
        }

        private func recordOutcomeResult(
            _ task: AssistantTaskRecord, outcome: String, retryScheduled: Bool,
            notifyRequested: Bool, parentThreadID: String?, workerID: String
        ) -> JSONValue {
            var result = taskResult(task)
            if case .object(var object) = result {
                object["outcome"] = .string(outcome)
                object["retryScheduled"] = .bool(retryScheduled)
                object["nextRetryAt"] = retryScheduled ? .int(task.nextRunAt ?? now) : .null
                object["notifyRequested"] = .bool(notifyRequested)
                object["parentThreadId"] = parentThreadID.map { .string($0) } ?? .null
                object["workerId"] = .string(workerID)
                result = .object(object)
            }
            return result
        }

        func tasksDue() async throws -> JSONValue {
            if let dueError {
                throw dueError
            }
            let due = tasks.filter { task in
                guard task.isActive else {
                    return false
                }
                if AssistantTaskManager.unavailableTriggerReason(task.trigger) != nil {
                    return false
                }
                if let maxRuns = task.limits.maxRuns, task.runCount >= maxRuns {
                    return false
                }
                return (task.nextRunAt ?? .max) <= now
            }
            let values: [JSONValue] = due.map { task in
                .object([
                    "taskId": .string(task.id.uuidString),
                    "taskName": .string(task.name),
                    "occurrence": .int(task.nextRunAt ?? now),
                    "nextRunAt": .int(task.nextRunAt ?? now),
                    "runCount": .int(Int64(task.runCount)),
                ])
            } + extraDueValues
            return .object(["dueTasks": .array(values), "now": .int(now)])
        }

        func tasksMarkMissed(taskId: String, reason: String) async throws -> JSONValue {
            guard let index = tasks.firstIndex(where: { $0.id.uuidString == taskId }) else {
                throw FakeTaskError(message: "Automated task not found")
            }
            guard let next = tasks[index].nextRunAt, next <= now else {
                throw FakeTaskError(message: "Task has no missed run to record")
            }
            markMissedCalls.append((taskId: taskId, reason: reason))
            markMissedLocked(&tasks[index], reason: reason)
            rotateBaseline()
            return taskResult(tasks[index])
        }

        func tasksRecover() async throws -> JSONValue {
            recoverCalls += 1
            var missed: [String] = []
            for index in tasks.indices {
                let task = tasks[index]
                guard task.enabled, !task.paused, task.trigger == "timer",
                      let next = task.nextRunAt, next <= now
                else {
                    continue
                }
                markMissedLocked(&tasks[index], reason: "A run was skipped while Coincide was closed or asleep.")
                missed.append(task.id.uuidString)
            }
            if !missed.isEmpty {
                rotateBaseline()
            }
            return .object(["missedTaskIds": .array(missed.map { .string($0) })])
        }

        func createParentThread(projectID: UUID) async throws -> UUID {
            newThreadProjectIDs.append(projectID)
            return parentThreadID
        }

        func deleteParentThread(_ threadID: UUID) async throws {
            deleteParentThreadCalls.append(threadID)
            if let deleteParentThreadError {
                throw deleteParentThreadError
            }
        }

        func listAssistants() async throws -> RemoteAssistants {
            if let listAssistantsError {
                throw listAssistantsError
            }
            listAssistantsCalls += 1
            return RemoteAssistants(assistants: assistants, baseline: "", origin: "local")
        }

        func fetchWorkspace(includeArchived: Bool) async throws -> RemoteWorkspace {
            if let fetchWorkspaceError {
                throw fetchWorkspaceError
            }
            fetchWorkspaceCalls += 1
            return workspace
        }
    }

    private static func makeTask(
        id: UUID = UUID(), name: String = "Nightly review", assistantID: UUID, workspaceID: UUID,
        nextRunAt: Int64? = nil, enabled: Bool = true, paused: Bool = false,
        trigger: String = "timer", approvalRequired: Bool = false, maxRuns: Int? = nil,
        runCount: Int = 0, lastOutcome: String? = nil, lastMessage: String? = nil,
        lastMissedAt: Int64? = nil, missedCount: Int = 0
    ) -> AssistantTaskRecord {
        AssistantTaskRecord(
            id: id, name: name, assistantID: assistantID, workspaceID: workspaceID,
            trigger: trigger, enabled: enabled, paused: paused,
            limits: AssistantTaskExecutionLimits(maxRuns: maxRuns, maxConcurrent: 1),
            approval: AssistantTaskApprovalRequirements(
                required: approvalRequired, actions: approvalRequired ? ["write_file"] : []
            ),
            runCount: runCount, lastOutcome: lastOutcome, lastMessage: lastMessage,
            lastMissedAt: lastMissedAt, missedCount: missedCount, nextRunAt: nextRunAt
        )
    }

    private static func makeAssistant(
        id: UUID, name: String = "Reviewer",
        permissionProfile: RemoteAssistant.PermissionProfile = .readOnly
    ) -> RemoteAssistant {
        RemoteAssistant(
            id: id, name: name, category: .codeReviewSecurity, systemPrompt: "Review the diff.",
            permissionProfile: permissionProfile
        )
    }

    private static func makeWorkspace(projectID: UUID) -> RemoteWorkspace {
        RemoteWorkspace(projects: [RemoteProject(id: projectID, name: "App", path: "/tmp/App")])
    }

    private func makeManager(
        fake: FakeTaskRuntime, assistantID: UUID, workspaceID: UUID,
        permissionProfile: RemoteAssistant.PermissionProfile = .readOnly
    ) async -> AssistantTaskManager {
        await fake.setAssistants([Self.makeAssistant(id: assistantID, permissionProfile: permissionProfile)])
        await fake.setWorkspace(Self.makeWorkspace(projectID: workspaceID))
        return AssistantTaskManager(runtime: fake)
    }

    private func makeNotifications() async -> (AssistantNotificationManager, RecordingPoster) {
        let suiteName = "com.apoorvdarshan.coincide.tests.taskReconcile.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let settings = await AssistantNotificationSettings(defaults: suite)
        let poster = RecordingPoster()
        let manager = await AssistantNotificationManager(
            settings: settings, poster: poster, isAppActive: { false },
            bundleIdentifier: "com.apoorvdarshan.coincide.tests"
        )
        return (manager, poster)
    }

    private func makeManagerWithNotifications(
        fake: FakeTaskRuntime, assistantID: UUID, workspaceID: UUID,
        notifications: AssistantNotificationManager
    ) async -> AssistantTaskManager {
        await fake.setAssistants([Self.makeAssistant(id: assistantID)])
        await fake.setWorkspace(Self.makeWorkspace(projectID: workspaceID))
        return AssistantTaskManager(runtime: fake, notifications: notifications)
    }

    private static func makeTaskWithWorker(
        assistantID: UUID, workspaceID: UUID, workerID: String = "worker-1",
        behavior: String = "retryWithBackoff", maxRetries: Int = 3, backoffSeconds: Int = 300,
        notifyOnSuccess: Bool = false, notifyOnFailure: Bool = true
    ) -> AssistantTaskRecord {
        var task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        task.failurePolicy = AssistantTaskFailurePolicy(behavior: behavior, maxRetries: maxRetries, backoffSeconds: backoffSeconds)
        task.notifications = AssistantTaskNotificationPrefs(onSuccess: notifyOnSuccess, onFailure: notifyOnFailure, onMissed: true)
        task.activeWorkerIds = [workerID]
        task.lastWorkerID = workerID
        return task
    }

    @Test("CRUD round trip preserves the task and rotates the baseline")
    func crudRoundTripPreservesTaskAndBaseline() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let listed = try await manager.listTasks()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        let saved = try await manager.saveTask(task, baseline: listed.baseline)
        #expect(saved.id == task.id)
        #expect(saved.name == "Nightly review")
        let listedAfterSave = try await manager.listTasks()
        #expect(listedAfterSave.tasks.count == 1)
        #expect(listedAfterSave.baseline != listed.baseline)
        #expect(listedAfterSave.baseline.count == 64)
        var renamed = saved
        renamed.name = "Morning review"
        let resaved = try await manager.saveTask(renamed, baseline: listedAfterSave.baseline)
        #expect(resaved.name == "Morning review")
        #expect(resaved.createdAt == saved.createdAt)
        let listedAfterRename = try await manager.listTasks()
        try await manager.deleteTask(id: task.id, baseline: listedAfterRename.baseline)
        let listedAfterDelete = try await manager.listTasks()
        #expect(listedAfterDelete.tasks.isEmpty)
        #expect(await manager.currentBaseline == listedAfterDelete.baseline)
    }

    @Test("Stale baseline save and delete throw the stale-baseline error")
    func staleBaselineSaveAndDeleteThrowStaleBaseline() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let listed = try await manager.listTasks()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        let stale = String(repeating: "0", count: 64)
        #expect(throws: AssistantTaskError.staleBaseline) {
            try await manager.saveTask(task, baseline: stale)
        }
        let saved = try await manager.saveTask(task, baseline: listed.baseline)
        #expect(saved.id == task.id)
        #expect(throws: AssistantTaskError.staleBaseline) {
            try await manager.deleteTask(id: task.id, baseline: stale)
        }
        let listedAfter = try await manager.listTasks()
        #expect(listedAfter.tasks.count == 1)
    }

    @Test("Enable, disable and pause round trip through save with the flags")
    func enableDisableAndPauseRoundTripThroughSave() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let listed = try await manager.listTasks()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        let saved = try await manager.saveTask(task, baseline: listed.baseline)
        let listedAfterSave = try await manager.listTasks()
        let disabled = try await manager.setEnabled(saved, enabled: false, baseline: listedAfterSave.baseline)
        #expect(disabled.enabled == false)
        #expect(disabled.isActive == false)
        let listedAfterDisable = try await manager.listTasks()
        let paused = try await manager.setPaused(disabled, paused: true, baseline: listedAfterDisable.baseline)
        #expect(paused.paused == true)
        let listedAfterPause = try await manager.listTasks()
        let resumed = try await manager.setPaused(paused, paused: false, baseline: listedAfterPause.baseline)
        #expect(resumed.paused == false)
        let listedAfterResume = try await manager.listTasks()
        let reenabled = try await manager.setEnabled(resumed, enabled: true, baseline: listedAfterResume.baseline)
        #expect(reenabled.enabled == true)
        #expect(reenabled.isActive == true)
    }

    @Test("Run-now creates the parent thread in the task workspace and returns the worker")
    func runNowCreatesParentThreadInTaskWorkspace() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let parentThreadID = UUID()
        await fake.setParentThreadID(parentThreadID)
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let listed = try await manager.listTasks()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_790_000_000)
        let saved = try await manager.saveTask(task, baseline: listed.baseline)
        let outcome = try await manager.runNow(saved)
        #expect(outcome.workerID == "worker-1")
        #expect(outcome.parentThreadID == parentThreadID)
        #expect(outcome.task.runCount == 1)
        #expect(outcome.task.lastWorkerID == "worker-1")
        let threadProjects = await fake.newThreadProjectIDs
        #expect(threadProjects == [workspaceID])
        let runCalls = await fake.runNowCalls
        #expect(runCalls.count == 1)
        #expect(runCalls[0].parentThreadId == parentThreadID.uuidString)
        #expect(await fake.deleteParentThreadCalls.isEmpty)
    }

    @Test("Run-now rejects an approval-required task without creating a thread")
    func runNowRejectsApprovalRequiredTask() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let listed = try await manager.listTasks()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, approvalRequired: true)
        let saved = try await manager.saveTask(task, baseline: listed.baseline)
        do {
            _ = try await manager.runNow(saved)
            Issue.record("runNow should have rejected the approval-required task")
        } catch let error as AssistantTaskError {
            guard case .runRejected(let reason) = error else {
                Issue.record("Expected a runRejected error, got \(error)")
                return
            }
            #expect(reason.contains("requires approval"))
        }
        #expect(await fake.newThreadProjectIDs.isEmpty)
        #expect(await fake.runNowCalls.isEmpty)
    }

    @Test("Reconcile writes back a completed worker and deletes its parent thread")
    func reconcileWritesBackCompletedOutcome() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let parentThreadID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let task = Self.makeTaskWithWorker(assistantID: assistantID, workspaceID: workspaceID)
        await fake.setTasks([task])
        await fake.setWorker(Self.makeWorker(
            id: "worker-1", parentThreadId: parentThreadID.uuidString,
            status: "completed", result: "Reviewed three files."
        ))
        let outcome = await manager.pollNow()
        #expect(outcome.outcomes.count == 1)
        #expect(outcome.outcomes[0].outcome == "completed")
        #expect(outcome.outcomes[0].task.lastOutcome == "completed")
        #expect(outcome.outcomes[0].task.lastMessage == "Reviewed three files.")
        #expect(outcome.outcomes[0].task.history.count == 1)
        #expect(outcome.outcomes[0].task.history[0].workerID == "worker-1")
        #expect(outcome.outcomes[0].parentThreadID == parentThreadID)
        #expect(outcome.reconcileFailures.isEmpty)
        #expect(await fake.deleteParentThreadCalls == [parentThreadID])
        let listed = try await manager.listTasks()
        #expect(listed.tasks[0].activeWorkerIds.isEmpty)
    }

    @Test("Reconcile schedules a retry after a failed run and deletes its parent thread")
    func reconcileSchedulesRetryOnFailure() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let parentThreadID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let task = Self.makeTaskWithWorker(assistantID: assistantID, workspaceID: workspaceID)
        await fake.setTasks([task])
        await fake.setWorker(Self.makeWorker(
            id: "worker-1", parentThreadId: parentThreadID.uuidString,
            status: "failed", error: "Provider blew up"
        ))
        let outcome = await manager.pollNow()
        #expect(outcome.outcomes.count == 1)
        #expect(outcome.outcomes[0].outcome == "failed")
        #expect(outcome.outcomes[0].retryScheduled == true)
        #expect(outcome.outcomes[0].nextRetryAt == 1_790_000_000 + 300)
        #expect(outcome.outcomes[0].task.nextRunAt == 1_790_000_000 + 300)
        #expect(outcome.outcomes[0].task.consecutiveFailures == 1)
        #expect(await fake.deleteParentThreadCalls == [parentThreadID])
    }

    @Test("Reconcile posts a failure notification only when the policy asks and prefs allow it")
    func reconcileNotifiesForNotifyPolicy() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let threadID = UUID().uuidString
        let (notifications, poster) = await makeNotifications()
        let manager = await makeManagerWithNotifications(
            fake: fake, assistantID: assistantID, workspaceID: workspaceID, notifications: notifications
        )
        let task = Self.makeTaskWithWorker(assistantID: assistantID, workspaceID: workspaceID, behavior: "notify")
        await fake.setTasks([task])
        await fake.setWorker(Self.makeWorker(
            id: "worker-1", parentThreadId: UUID().uuidString, threadId: threadID,
            status: "failed", error: "Provider blew up"
        ))
        let outcome = await manager.pollNow()
        #expect(outcome.outcomes.count == 1)
        #expect(outcome.outcomes[0].notifyRequested == true)
        #expect(poster.requests.count == 1)
        #expect(poster.requests[0].identifier == "assistant-runFailed-\(threadID)")
    }

    @Test("Reconcile skips the failure notification when the task disables it")
    func reconcileSkipsNotificationWhenTaskDisablesFailureNotifications() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let (notifications, poster) = await makeNotifications()
        let manager = await makeManagerWithNotifications(
            fake: fake, assistantID: assistantID, workspaceID: workspaceID, notifications: notifications
        )
        let task = Self.makeTaskWithWorker(
            assistantID: assistantID, workspaceID: workspaceID, behavior: "notify", notifyOnFailure: false
        )
        await fake.setTasks([task])
        await fake.setWorker(Self.makeWorker(
            id: "worker-1", parentThreadId: UUID().uuidString,
            status: "failed", error: "Provider blew up"
        ))
        let outcome = await manager.pollNow()
        #expect(outcome.outcomes.count == 1)
        #expect(outcome.outcomes[0].notifyRequested == true)
        #expect(poster.requests.isEmpty)
    }

    @Test("Reconcile leaves running workers alone")
    func reconcileSkipsRunningWorkers() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let task = Self.makeTaskWithWorker(assistantID: assistantID, workspaceID: workspaceID)
        await fake.setTasks([task])
        await fake.setWorker(Self.makeWorker(
            id: "worker-1", parentThreadId: UUID().uuidString, status: "running"
        ))
        let outcome = await manager.pollNow()
        #expect(outcome.outcomes.isEmpty)
        #expect(outcome.reconcileFailures.isEmpty)
        #expect(await fake.deleteParentThreadCalls.isEmpty)
        #expect(await fake.recordOutcomeCalls.isEmpty)
        let listed = try await manager.listTasks()
        #expect(listed.tasks[0].activeWorkerIds == ["worker-1"])
    }

    @Test("Reconcile records a missing worker record as interrupted")
    func reconcileRecordsMissingWorkerAsInterrupted() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let task = Self.makeTaskWithWorker(assistantID: assistantID, workspaceID: workspaceID)
        await fake.setTasks([task])
        let outcome = await manager.pollNow()
        #expect(outcome.outcomes.count == 1)
        #expect(outcome.outcomes[0].outcome == "interrupted")
        #expect(outcome.outcomes[0].parentThreadID == nil)
        #expect(await fake.deleteParentThreadCalls.isEmpty)
    }

    @Test("Reconcile deletes the parent thread when worker status throws transiently")
    func reconcileDeletesParentThreadWhenWorkerStatusThrowsTransiently() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let parentThreadID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let task = Self.makeTaskWithWorker(assistantID: assistantID, workspaceID: workspaceID)
        await fake.setTasks([task])
        await fake.setWorker(Self.makeWorker(
            id: "worker-1", parentThreadId: parentThreadID.uuidString,
            status: "failed", error: "Provider blew up"
        ))
        await fake.setWorkerStatusError(FakeTaskError(message: "Worker status unavailable"))
        let outcome = await manager.pollNow()
        #expect(outcome.outcomes.count == 1)
        #expect(outcome.outcomes[0].outcome == "failed")
        #expect(outcome.outcomes[0].retryScheduled == true)
        #expect(outcome.outcomes[0].notifyRequested == false)
        #expect(outcome.outcomes[0].parentThreadID == parentThreadID)
        #expect(outcome.reconcileFailures.isEmpty)
        #expect(await fake.deleteParentThreadCalls == [parentThreadID])
    }

    @Test("Reconcile notifies and deletes the parent thread when worker status throws transiently")
    func reconcileNotifiesAndDeletesParentThreadWhenWorkerStatusThrowsTransiently() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let parentThreadID = UUID()
        let (notifications, poster) = await makeNotifications()
        let manager = await makeManagerWithNotifications(
            fake: fake, assistantID: assistantID, workspaceID: workspaceID, notifications: notifications
        )
        let task = Self.makeTaskWithWorker(assistantID: assistantID, workspaceID: workspaceID, behavior: "notify")
        await fake.setTasks([task])
        await fake.setWorker(Self.makeWorker(
            id: "worker-1", parentThreadId: parentThreadID.uuidString,
            status: "failed", error: "Provider blew up"
        ))
        await fake.setWorkerStatusError(FakeTaskError(message: "Worker status unavailable"))
        let outcome = await manager.pollNow()
        #expect(outcome.outcomes.count == 1)
        #expect(outcome.outcomes[0].outcome == "failed")
        #expect(outcome.outcomes[0].notifyRequested == true)
        #expect(outcome.outcomes[0].parentThreadID == parentThreadID)
        #expect(outcome.reconcileFailures.isEmpty)
        #expect(await fake.deleteParentThreadCalls == [parentThreadID])
        #expect(poster.requests.count == 1)
        #expect(poster.requests[0].identifier == "assistant-runFailed-worker-1")
        #expect(poster.requests[0].content.title == "Reviewer")
        #expect(poster.requests[0].content.body == "Failed: Nightly review")
    }

    @Test("Run-now tracks the spawned worker as active")
    func runNowTracksActiveWorker() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        await fake.setParentThreadID(UUID())
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let listed = try await manager.listTasks()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        let saved = try await manager.saveTask(task, baseline: listed.baseline)
        let outcome = try await manager.runNow(saved)
        #expect(outcome.workerID == "worker-1")
        let listedAfter = try await manager.listTasks()
        #expect(listedAfter.tasks[0].activeWorkerIds == ["worker-1"])
    }

    @Test("Due poll runs due tasks and marks invalid ones missed with reasons")
    func duePollRunsDueTasksAndSkipsInvalidOnes() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let good = Self.makeTask(name: "Good", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        let gated = Self.makeTask(name: "Gated", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000, approvalRequired: true)
        let orphaned = Self.makeTask(name: "Orphaned", assistantID: UUID(), workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        let future = Self.makeTask(name: "Future", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_799_999_999)
        await fake.setTasks([good, gated, orphaned, future])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.count == 1)
        #expect(outcome.ran[0].task.name == "Good")
        #expect(outcome.skipped.count == 2)
        #expect(outcome.failed.isEmpty)
        #expect(outcome.cycleError == nil)
        let skippedReasons = outcome.skipped.map { $0.reason }
        #expect(skippedReasons.contains(.approvalRequired))
        #expect(skippedReasons.contains(.assistantMissing))
        let missed = await fake.markMissedCalls
        #expect(missed.count == 2)
        #expect(missed.contains { $0.reason.contains("requires approval") })
        #expect(missed.contains { $0.reason.contains("no longer exists") })
        #expect(await fake.runNowCalls.count == 1)
        let listed = try await manager.listTasks()
        #expect(listed.tasks.first { $0.name == "Future" }?.lastOutcome == nil)
    }

    @Test("Poll never surfaces paused or disabled tasks: they never reach the run loop")
    func pollNeverRunsPausedOrDisabledTasks() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let paused = Self.makeTask(name: "Paused", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000, paused: true)
        let disabled = Self.makeTask(name: "Disabled", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000, enabled: false)
        await fake.setTasks([paused, disabled])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.isEmpty)
        #expect(outcome.skipped.isEmpty)
        #expect(outcome.failed.isEmpty)
        #expect(outcome.decodeFailures.isEmpty)
        #expect(outcome.cycleError == nil)
        #expect(await fake.runNowCalls.isEmpty)
        #expect(await fake.newThreadProjectIDs.isEmpty)
        #expect(await fake.markMissedCalls.isEmpty)
        #expect(await fake.listAssistantsCalls == 0)
        #expect(await fake.fetchWorkspaceCalls == 0)
        let listed = try await manager.listTasks()
        #expect(listed.tasks.count == 2)
    }

    @Test("Poll never surfaces max-runs tasks: they never reach the run loop")
    func pollNeverSurfacesMaxRunsTasks() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let capped = Self.makeTask(name: "Capped", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000, maxRuns: 2, runCount: 2)
        await fake.setTasks([capped])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.isEmpty)
        #expect(outcome.skipped.isEmpty)
        #expect(outcome.failed.isEmpty)
        #expect(outcome.cycleError == nil)
        #expect(await fake.runNowCalls.isEmpty)
        #expect(await fake.markMissedCalls.isEmpty)
    }

    @Test("Save rejects tasks with unavailable triggers, like the real engine")
    func saveRejectsUnavailableTriggerTasks() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let listed = try await manager.listTasks()
        let gitTriggered = Self.makeTask(name: "GitTriggered", assistantID: assistantID, workspaceID: workspaceID, trigger: "gitCommit")
        do {
            _ = try await manager.saveTask(gitTriggered, baseline: listed.baseline)
            Issue.record("saveTask should have rejected the gitCommit trigger")
        } catch let error as FakeTaskError {
            #expect(error.message.contains("not available"))
        }
        let listedAfter = try await manager.listTasks()
        #expect(listedAfter.tasks.isEmpty)
    }

    @Test("Poll skips an active task with an unavailable trigger and still runs the due timer task")
    func pollSkipsActiveUnavailableTriggerAndRunsDueTimerTask() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let gitTriggered = Self.makeTask(name: "GitTriggered", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000, trigger: "gitCommit")
        let due = Self.makeTask(name: "Due", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        await fake.setTasks([gitTriggered, due])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.count == 1)
        #expect(outcome.ran[0].task.name == "Due")
        #expect(outcome.skipped.isEmpty)
        #expect(outcome.failed.isEmpty)
        #expect(outcome.cycleError == nil)
        #expect(await fake.runNowCalls.count == 1)
        #expect(await fake.markMissedCalls.isEmpty)
        let listed = try await manager.listTasks()
        let skipped = listed.tasks.first { $0.name == "GitTriggered" }
        #expect(skipped?.lastOutcome == nil)
        #expect(skipped?.missedCount == 0)
    }

    @Test("Static skip reason flags max-runs and unavailable triggers without a runtime")
    func staticSkipReasonFlagsMaxRunsAndUnavailableTriggers() {
        let assistantID = UUID()
        let workspaceID = UUID()
        let assistants = [Self.makeAssistant(id: assistantID)]
        let workspace = Self.makeWorkspace(projectID: workspaceID)
        let capped = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, maxRuns: 2, runCount: 2)
        #expect(AssistantTaskManager.skipReason(for: capped, assistants: assistants, workspace: workspace) == .maxRunsReached(2))
        let gitTriggered = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, trigger: "gitCommit")
        #expect(AssistantTaskManager.skipReason(for: gitTriggered, assistants: assistants, workspace: workspace) == .triggerUnavailable("gitCommit"))
    }

    @Test("Poll fetches assistants and workspace once per cycle, not once per due task")
    func pollFetchesAssistantsAndWorkspaceOncePerCycle() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let first = Self.makeTask(name: "First", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        let second = Self.makeTask(name: "Second", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        let third = Self.makeTask(name: "Third", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        await fake.setTasks([first, second, third])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.count == 3)
        #expect(outcome.skipped.isEmpty)
        #expect(outcome.failed.isEmpty)
        #expect(await fake.listAssistantsCalls == 1)
        #expect(await fake.fetchWorkspaceCalls == 1)
    }

    @Test("Destructive tasks are never auto-run: approval-required assistants stay missed")
    func destructiveTaskNeverAutoRuns() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(
            fake: fake, assistantID: assistantID, workspaceID: workspaceID,
            permissionProfile: .approvalRequired
        )
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        await fake.setTasks([task])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.isEmpty)
        #expect(outcome.skipped.count == 1)
        #expect(outcome.skipped[0].reason == .assistantRequiresApproval)
        #expect(await fake.runNowCalls.isEmpty)
        #expect(await fake.newThreadProjectIDs.isEmpty)
        let missed = await fake.markMissedCalls
        #expect(missed.count == 1)
        #expect(missed[0].reason.contains("requires approval"))
        do {
            _ = try await manager.runNow(task)
            Issue.record("runNow should have rejected the approval-required assistant")
        } catch let error as AssistantTaskError {
            guard case .runRejected = error else {
                Issue.record("Expected a runRejected error, got \(error)")
                return
            }
        }
    }

    @Test("Poll skips a task whose workspace no longer exists")
    func pollSkipsTaskWithMissingWorkspace() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let task = Self.makeTask(assistantID: assistantID, workspaceID: UUID(), nextRunAt: 1_789_999_000)
        await fake.setTasks([task])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.isEmpty)
        #expect(outcome.skipped.count == 1)
        #expect(outcome.skipped[0].reason == .workspaceMissing)
        #expect(await fake.runNowCalls.isEmpty)
    }

    @Test("Recover marks overdue tasks missed once and is idempotent")
    func recoverMarksOverdueTasksOnce() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let overdue = Self.makeTask(name: "Overdue", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        let paused = Self.makeTask(name: "Paused", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000, paused: true)
        await fake.setTasks([overdue, paused])
        let missed = try await manager.recover()
        #expect(missed == [overdue.id])
        #expect(await fake.recoverCalls == 1)
        let second = try await manager.recover()
        #expect(second.isEmpty)
        #expect(await fake.recoverCalls == 2)
        let listed = try await manager.listTasks()
        let recovered = listed.tasks.first { $0.id == overdue.id }
        #expect(recovered?.lastOutcome == "missed")
        #expect(recovered?.missedCount == 1)
        #expect(listed.tasks.first { $0.id == paused.id }?.lastOutcome == nil)
    }

    @Test("Missed runs surface with reasons and counts for the UI")
    func missedRunsSurfacedWithReasons() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let missed = Self.makeTask(
            name: "Missed", assistantID: assistantID, workspaceID: workspaceID,
            nextRunAt: 1_790_086_400, lastOutcome: "missed", lastMessage: "Assistant was deleted.",
            lastMissedAt: 1_790_000_000, missedCount: 3
        )
        let healthy = Self.makeTask(name: "Healthy", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_790_086_400)
        await fake.setTasks([healthy, missed])
        let runs = try await manager.missedRuns()
        #expect(runs.count == 1)
        #expect(runs[0].task.name == "Missed")
        #expect(runs[0].reason == "Assistant was deleted.")
        #expect(runs[0].missedCount == 3)
        #expect(runs[0].missedAt == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test("Polling start and stop toggle state and the loop runs due tasks")
    func pollingStartStopTogglesStateAndLoopRunsDueTasks() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        await fake.setAssistants([Self.makeAssistant(id: assistantID)])
        await fake.setWorkspace(Self.makeWorkspace(projectID: workspaceID))
        let manager = AssistantTaskManager(runtime: fake, pollInterval: .milliseconds(50))
        let due = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        await fake.setTasks([due])
        #expect(await manager.isPolling == false)
        await manager.startPolling()
        #expect(await manager.isPolling == true)
        try await Task.sleep(for: .milliseconds(200))
        await manager.stopPolling()
        #expect(await manager.isPolling == false)
        #expect(await fake.runNowCalls.count == 1)
    }

    @Test("A failed run-now is recorded as failed and its occurrence is marked missed")
    func failedRunNowIsRecordedAsFailedAndMarkedMissed() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        await fake.setRunNowError(FakeTaskError(message: "Automated task 'Nightly review' already has a running worker"))
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        await fake.setTasks([task])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.isEmpty)
        #expect(outcome.failed.count == 1)
        #expect(outcome.failed[0].message.contains("already has a running worker"))
        #expect(await fake.markMissedCalls.count == 1)
        #expect(await fake.markMissedCalls[0].reason.contains("Run failed"))
        #expect(await fake.newThreadProjectIDs == [workspaceID])
        #expect(await fake.deleteParentThreadCalls == [await fake.parentThreadID])
    }

    @Test("A failed run-now still reports the run error when thread cleanup fails")
    func failedRunNowStillReportsOriginalErrorWhenThreadCleanupFails() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        await fake.setRunNowError(FakeTaskError(message: "Automated task 'Nightly review' already has a running worker"))
        await fake.setDeleteParentThreadError(FakeTaskError(message: "Thread delete failed"))
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        await fake.setTasks([task])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.isEmpty)
        #expect(outcome.failed.count == 1)
        #expect(outcome.failed[0].message.contains("already has a running worker"))
        #expect(await fake.deleteParentThreadCalls.count == 1)
    }

    @Test("List surfaces undecodable task records instead of dropping them")
    func listTasksSurfacesUndecodableRecords() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let good = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        let brokenID = UUID()
        let brokenWithID: JSONValue = .object([
            "id": .string(brokenID.uuidString),
            "name": .string("Broken"),
        ])
        let brokenWithoutID: JSONValue = .object([
            "name": .string("Nameless"),
        ])
        await fake.setTasks([good])
        await fake.setExtraListValues([brokenWithID, brokenWithoutID])
        let listed = try await manager.listTasks()
        #expect(listed.tasks.count == 1)
        #expect(listed.tasks[0].id == good.id)
        #expect(listed.decodeFailures.count == 2)
        #expect(listed.decodeFailures.contains { $0.taskID == brokenID })
        #expect(listed.decodeFailures.contains { $0.taskID == nil })
    }

    @Test("Poll surfaces undecodable due entries instead of dropping them")
    func pollNowSurfacesUndecodableDueEntries() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let good = Self.makeTask(name: "Good", assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 1_789_999_000)
        let brokenDue: JSONValue = .object([
            "taskName": .string("Broken"),
        ])
        await fake.setTasks([good])
        await fake.setExtraDueValues([brokenDue])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.count == 1)
        #expect(outcome.ran[0].task.name == "Good")
        #expect(outcome.decodeFailures.count == 1)
        #expect(outcome.decodeFailures[0].taskID == nil)
    }

    @Test("Poll surfaces a due entry whose task is no longer listed")
    func pollNowSurfacesDueEntryForMissingTask() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let missingID = UUID()
        let dangling: JSONValue = .object([
            "taskId": .string(missingID.uuidString),
            "taskName": .string("Gone"),
            "occurrence": .int(1_789_999_000),
            "nextRunAt": .int(1_789_999_000),
            "runCount": .int(0),
        ])
        await fake.setTasks([])
        await fake.setExtraDueValues([dangling])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.isEmpty)
        #expect(outcome.skipped.isEmpty)
        #expect(outcome.failed.isEmpty)
        #expect(outcome.decodeFailures.count == 1)
        #expect(outcome.decodeFailures[0].taskID == missingID)
    }

    @Test("Poll surfaces an undecodable task record behind its due entry")
    func pollNowSurfacesUndecodableTaskRecordBehindDueEntry() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let brokenID = UUID()
        let brokenRecord: JSONValue = .object([
            "id": .string(brokenID.uuidString),
            "name": .string("Broken"),
        ])
        let dueForBroken: JSONValue = .object([
            "taskId": .string(brokenID.uuidString),
            "taskName": .string("Broken"),
            "occurrence": .int(1_789_999_000),
            "nextRunAt": .int(1_789_999_000),
            "runCount": .int(0),
        ])
        await fake.setTasks([])
        await fake.setExtraListValues([brokenRecord])
        await fake.setExtraDueValues([dueForBroken])
        let outcome = await manager.pollNow()
        #expect(outcome.ran.isEmpty)
        #expect(outcome.decodeFailures.count == 2)
        #expect(outcome.decodeFailures.filter { $0.taskID == brokenID }.count == 2)
    }

    @Test("Delete refreshes the baseline so the next save succeeds")
    func deleteRefreshesBaselineForNextSave() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let listed = try await manager.listTasks()
        let first = Self.makeTask(name: "First", assistantID: assistantID, workspaceID: workspaceID)
        let second = Self.makeTask(name: "Second", assistantID: assistantID, workspaceID: workspaceID)
        let savedFirst = try await manager.saveTask(first, baseline: listed.baseline)
        let listedAfterFirst = try await manager.listTasks()
        let savedSecond = try await manager.saveTask(second, baseline: listedAfterFirst.baseline)
        let baselineBeforeDelete = await manager.currentBaseline
        try await manager.deleteTask(id: savedFirst.id, baseline: baselineBeforeDelete ?? "")
        #expect(await manager.currentBaseline != baselineBeforeDelete)
        let listedAfterDelete = try await manager.listTasks()
        #expect(listedAfterDelete.tasks.count == 1)
        #expect(await manager.currentBaseline == listedAfterDelete.baseline)
        var renamed = savedSecond
        renamed.name = "Second renamed"
        let resaved = try await manager.saveTask(renamed, baseline: await manager.currentBaseline ?? "")
        #expect(resaved.name == "Second renamed")
    }

    @Test("Delete leaves the baseline unknown when the refresh list fails")
    func deleteLeavesBaselineUnknownWhenRefreshFails() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        let listed = try await manager.listTasks()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        let saved = try await manager.saveTask(task, baseline: listed.baseline)
        await fake.setListTasksError(FakeTaskError(message: "List failed"))
        try await manager.deleteTask(id: saved.id, baseline: await manager.currentBaseline ?? "")
        #expect(await manager.currentBaseline == nil)
        await fake.setListTasksError(nil)
        let listedAfter = try await manager.listTasks()
        #expect(listedAfter.tasks.isEmpty)
    }

    @Test("Task records round trip through JSON without losing unknown fields")
    func taskRecordRoundTripPreservesUnknownFields() async throws {
        let assistantID = UUID()
        let workspaceID = UUID()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        var withFuture = task
        withFuture.extra = ["futureField": .object(["keep": .bool(true)])]
        let encoded = try withFuture.encoded()
        let decoded = try AssistantTaskRecord(json: encoded)
        #expect(decoded == withFuture)
        #expect(decoded.extra["futureField"]?["keep"]?.boolValue == true)
    }

    @Test("Poll reports a cycle error when the due list cannot be fetched")
    func pollReportsCycleErrorWhenDueListFails() async {
        let fake = FakeTaskRuntime()
        await fake.setDueError(FakeTaskError(message: "Due failed"))
        let manager = AssistantTaskManager(runtime: fake)
        let outcome = await manager.pollNow()
        #expect(outcome.cycleError == "Due failed")
        #expect(outcome.ran.isEmpty)
        #expect(outcome.skipped.isEmpty)
        #expect(outcome.failed.isEmpty)
    }

    @Test("Poll reports a cycle error when the task list cannot be fetched")
    func pollReportsCycleErrorWhenTaskListFails() async {
        let fake = FakeTaskRuntime()
        await fake.setListTasksError(FakeTaskError(message: "List failed"))
        let manager = AssistantTaskManager(runtime: fake)
        let outcome = await manager.pollNow()
        #expect(outcome.cycleError == "List failed")
        #expect(outcome.ran.isEmpty)
    }

    @Test("Poll reports a cycle error when assistants cannot be listed")
    func pollReportsCycleErrorWhenAssistantsFail() async {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        await fake.setTasks([Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 0)])
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        await fake.setListAssistantsError(FakeTaskError(message: "Assistants failed"))
        let outcome = await manager.pollNow()
        #expect(outcome.cycleError == "Assistants failed")
        #expect(outcome.ran.isEmpty)
    }

    @Test("Poll reports a cycle error when the workspace cannot be fetched")
    func pollReportsCycleErrorWhenWorkspaceFails() async {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        await fake.setTasks([Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, nextRunAt: 0)])
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        await fake.setFetchWorkspaceError(FakeTaskError(message: "Workspace failed"))
        let outcome = await manager.pollNow()
        #expect(outcome.cycleError == "Workspace failed")
        #expect(outcome.ran.isEmpty)
    }

    @Test("Poll records a failure when a skipped run cannot be marked missed")
    func pollRecordsFailureWhenMissedMarkingFails() async {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let task = Self.makeTask(
            assistantID: assistantID, workspaceID: workspaceID,
            nextRunAt: 1_790_000_000 + 86_400, approvalRequired: true)
        await fake.setTasks([task])
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        await fake.setExtraDueValues([.object([
            "taskId": .string(task.id.uuidString),
            "taskName": .string(task.name),
            "occurrence": .int(1_790_000_000),
            "nextRunAt": .int(1_790_000_000),
            "runCount": .int(0),
        ])])
        let outcome = await manager.pollNow()
        #expect(outcome.cycleError == nil)
        #expect(outcome.failed.count == 1)
        #expect(outcome.failed.first?.task.id == task.id)
        #expect(outcome.failed.first?.message == "Could not record the missed run: Task has no missed run to record")
        #expect(outcome.skipped.isEmpty)
        #expect(outcome.ran.isEmpty)
    }

    @Test("Save rejects a result that omits the saved task")
    func saveRejectsResultWithoutTask() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        let manager = AssistantTaskManager(runtime: fake)
        let listed = try await manager.listTasks()
        await fake.setSaveOmitsTask(true)
        do {
            _ = try await manager.saveTask(task, baseline: listed.baseline)
            Issue.record("Expected saveTask to reject a result without a task")
        } catch let error as AssistantTaskError {
            #expect(error == .invalidResult("Save did not return the saved task."))
        }
    }

    @Test("Run-now rejects a result that omits the updated task")
    func runNowRejectsResultWithoutTask() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        await fake.setTasks([task])
        let manager = await makeManager(fake: fake, assistantID: assistantID, workspaceID: workspaceID)
        await fake.setRunNowOmitsTask(true)
        do {
            _ = try await manager.runNow(task)
            Issue.record("Expected runNow to reject a result without a task")
        } catch let error as AssistantTaskError {
            #expect(error == .invalidResult("Run-now did not return the updated task."))
        }
        #expect(await fake.runNowCalls.count == 1)
        #expect(await fake.deleteParentThreadCalls.isEmpty)
    }

    @Test("Reconcile reports failures when recording an outcome throws")
    func reconcileReportsRecordOutcomeFailures() async {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let task = Self.makeTaskWithWorker(assistantID: assistantID, workspaceID: workspaceID)
        await fake.setTasks([task])
        await fake.setWorker(Self.makeWorker(id: "worker-1", parentThreadId: UUID().uuidString, status: "completed", result: "done"))
        let manager = AssistantTaskManager(runtime: fake)
        await fake.setRecordOutcomeError(FakeTaskError(message: "Outcome failed"))
        let outcome = await manager.reconcileTaskOutcomes([task])
        #expect(outcome.outcomes.isEmpty)
        #expect(outcome.reconcileFailures.count == 1)
        #expect(outcome.reconcileFailures.first?.taskID == task.id)
        #expect(outcome.reconcileFailures.first?.message == "Could not record the outcome of worker worker-1: Outcome failed")
    }

    @Test("Reconcile with no active workers records nothing")
    func reconcileWithNoActiveWorkersRecordsNothing() async {
        let manager = AssistantTaskManager(runtime: FakeTaskRuntime())
        let outcome = await manager.reconcileTaskOutcomes([Self.makeTask(assistantID: UUID(), workspaceID: UUID())])
        #expect(outcome.outcomes.isEmpty)
        #expect(outcome.reconcileFailures.isEmpty)
        #expect(outcome.ran.isEmpty)
        #expect(outcome.skipped.isEmpty)
        #expect(outcome.failed.isEmpty)
        #expect(outcome.cycleError == nil)
    }

    @Test("Skip reasons follow the documented precedence")
    func skipReasonPrecedence() {
        let assistantID = UUID()
        let workspaceID = UUID()
        let assistant = Self.makeAssistant(id: assistantID)
        let workspace = Self.makeWorkspace(projectID: workspaceID)
        let emptyWorkspace = RemoteWorkspace()
        #expect(AssistantTaskManager.skipReason(for: Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, enabled: false, paused: true), assistants: [], workspace: emptyWorkspace) == .disabled)
        #expect(AssistantTaskManager.skipReason(for: Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, paused: true), assistants: [], workspace: emptyWorkspace) == .paused)
        #expect(AssistantTaskManager.skipReason(for: Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, trigger: "gitCommit"), assistants: [], workspace: emptyWorkspace) == .triggerUnavailable("gitCommit"))
        #expect(AssistantTaskManager.skipReason(for: Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, trigger: "webhook"), assistants: [], workspace: emptyWorkspace) == .triggerUnavailable("webhook"))
        #expect(AssistantTaskManager.skipReason(for: Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, maxRuns: 2, runCount: 2, approvalRequired: true), assistants: [assistant], workspace: workspace) == .maxRunsReached(2))
        #expect(AssistantTaskManager.skipReason(for: Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, approvalRequired: true), assistants: [], workspace: workspace) == .approvalRequired)
        #expect(AssistantTaskManager.skipReason(for: Self.makeTask(assistantID: assistantID, workspaceID: workspaceID), assistants: [], workspace: workspace) == .assistantMissing)
        #expect(AssistantTaskManager.skipReason(for: Self.makeTask(assistantID: assistantID, workspaceID: workspaceID), assistants: [Self.makeAssistant(id: assistantID, permissionProfile: .approvalRequired)], workspace: workspace) == .assistantRequiresApproval)
        #expect(AssistantTaskManager.skipReason(for: Self.makeTask(assistantID: assistantID, workspaceID: workspaceID), assistants: [assistant], workspace: emptyWorkspace) == .workspaceMissing)
        #expect(AssistantTaskManager.skipReason(for: Self.makeTask(assistantID: assistantID, workspaceID: workspaceID), assistants: [assistant], workspace: workspace) == nil)
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        #expect(AssistantTaskSkipReason.triggerUnavailable("webhook").message(task: task) == "Trigger 'webhook' is not available: only timer triggers can run automatically.")
        #expect(AssistantTaskSkipReason.maxRunsReached(2).message(task: task) == "Automated task 'Nightly review' has reached its maximum of 2 runs")
        #expect(AssistantTaskSkipReason.assistantMissing.message(task: task) == "Assistant '\(assistantID.uuidString)' no longer exists; automated runs are skipped until the task points at an existing assistant.")
    }

    @Test("Unavailable trigger reasons name the missing capability")
    func unavailableTriggerReasons() {
        #expect(AssistantTaskManager.unavailableTriggerReason("timer") == nil)
        #expect(AssistantTaskManager.unavailableTriggerReason("gitCommit") == "Git commit triggers are not available: Coincide has no git watcher, hooks, webhooks, or GitHub polling")
        #expect(AssistantTaskManager.unavailableTriggerReason("branchChange") == "Branch change triggers are not available: Coincide has no git watcher or branch-change events")
        #expect(AssistantTaskManager.unavailableTriggerReason("pullRequest") == "Pull request triggers are not available: Coincide has no GitHub polling or webhooks")
        #expect(AssistantTaskManager.unavailableTriggerReason("issue") == "Issue triggers are not available: Coincide has no Issues API polling or webhooks")
        #expect(AssistantTaskManager.unavailableTriggerReason("workspaceChange") == "Workspace change triggers are not available: Coincide has no workspace file watcher")
        #expect(AssistantTaskManager.unavailableTriggerReason("fileChange") == "File change triggers are not available: Coincide has no file watcher")
        #expect(AssistantTaskManager.unavailableTriggerReason("webhook") == nil)
    }

    @Test("Minimal task records decode with documented defaults and keep unknown schedule keys")
    func minimalTaskRecordDecodeDefaults() throws {
        let json: JSONValue = .object([
            "id": .string(UUID().uuidString),
            "assistantId": .string(UUID().uuidString),
            "workspaceId": .string(UUID().uuidString),
            "schedule": .object(["kind": .string("daily"), "cronExpression": .string("0 9 * * *")]),
        ])
        let record = try AssistantTaskRecord(json: json)
        #expect(record.name == "")
        #expect(record.trigger == "timer")
        #expect(record.enabled == true)
        #expect(record.paused == false)
        #expect(record.limits.maxRuns == nil)
        #expect(record.limits.maxConcurrent == 1)
        #expect(record.notifications.onSuccess == false)
        #expect(record.notifications.onFailure == true)
        #expect(record.notifications.onMissed == true)
        #expect(record.failurePolicy.behavior == "retryWithBackoff")
        #expect(record.failurePolicy.maxRetries == 3)
        #expect(record.failurePolicy.backoffSeconds == 300)
        #expect(record.approval.required == false)
        #expect(record.approval.actions.isEmpty)
        #expect(record.runCount == 0)
        #expect(record.missedCount == 0)
        #expect(record.isActive == true)
        #expect(record.schedule.kind == "daily")
        #expect(record.schedule.extra["cronExpression"]?.stringValue == "0 9 * * *")
        let reencoded = try record.encoded()
        #expect(reencoded["schedule"]?["cronExpression"]?.stringValue == "0 9 * * *")
        #expect(reencoded["schedule"]?["kind"]?.stringValue == "daily")
    }

    @Test("Missed runs sort newest first and default their reason")
    func missedRunsSortNewestFirst() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let older = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, lastOutcome: "missed", lastMessage: "Old reason", lastMissedAt: 1000)
        let newer = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, lastOutcome: "missed", lastMessage: nil, lastMissedAt: 2000)
        let never = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, lastOutcome: "missed", lastMessage: nil, lastMissedAt: nil)
        let completed = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID, lastOutcome: "completed", lastMissedAt: 3000)
        await fake.setTasks([older, newer, never, completed])
        let manager = AssistantTaskManager(runtime: fake)
        let missed = try await manager.missedRuns()
        #expect(missed.count == 3)
        #expect(missed[0].task.id == newer.id)
        #expect(missed[0].reason == "Run missed.")
        #expect(missed[0].missedAt == Date(timeIntervalSince1970: 2000))
        #expect(missed[0].missedCount == 0)
        #expect(missed[1].task.id == older.id)
        #expect(missed[1].reason == "Old reason")
        #expect(missed[2].task.id == never.id)
        #expect(missed[2].missedAt == nil)
    }

    @Test("Run-now rejects a task whose assistant no longer exists")
    func runNowRejectsMissingAssistant() async throws {
        let fake = FakeTaskRuntime()
        let assistantID = UUID()
        let workspaceID = UUID()
        let task = Self.makeTask(assistantID: assistantID, workspaceID: workspaceID)
        let manager = AssistantTaskManager(runtime: fake)
        do {
            _ = try await manager.runNow(task)
            Issue.record("Expected runNow to reject a task whose assistant is gone")
        } catch let error as AssistantTaskError {
            guard case .runRejected(let reason) = error else {
                Issue.record("Expected runRejected, got \(error)")
                return
            }
            #expect(reason.contains("no longer exists"))
        }
        #expect(await fake.newThreadProjectIDs.isEmpty)
        #expect(await fake.runNowCalls.isEmpty)
    }

    @Test("Task error descriptions are exact")
    func taskErrorDescriptions() {
        let id = UUID()
        #expect(AssistantTaskError.staleBaseline.errorDescription == "Automated task document changed; reload before saving")
        #expect(AssistantTaskError.taskNotFound(id: id).errorDescription == "Automated task \(id.uuidString) no longer exists.")
        #expect(AssistantTaskError.invalidResult("bad result").errorDescription == "bad result")
        #expect(AssistantTaskError.runRejected("nope").errorDescription == "nope")
        #expect(AssistantTaskError.underlying("deep").errorDescription == "deep")
    }
}
