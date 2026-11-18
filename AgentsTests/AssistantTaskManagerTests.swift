import CoincideRemoteKit
import Foundation
import Testing
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

    private actor FakeTaskRuntime: AssistantTaskRuntime {
        var tasks: [AssistantTaskRecord] = []
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
        var runNowCalls: [(taskId: String, parentThreadId: String)] = []
        var markMissedCalls: [(taskId: String, reason: String)] = []
        var recoverCalls = 0
        var runNowError: Error?

        func setTasks(_ value: [AssistantTaskRecord]) { tasks = value }
        func setAssistants(_ value: [RemoteAssistant]) { assistants = value }
        func setWorkspace(_ value: RemoteWorkspace) { workspace = value }
        func setNow(_ value: Int64) { now = value }
        func setRunNowError(_ value: Error?) { runNowError = value }
        func setParentThreadID(_ value: UUID) { parentThreadID = value }
        func setDeleteParentThreadError(_ value: Error?) { deleteParentThreadError = value }
        func setExtraListValues(_ value: [JSONValue]) { extraListValues = value }
        func setExtraDueValues(_ value: [JSONValue]) { extraDueValues = value }
        func setListTasksError(_ value: Error?) { listTasksError = value }

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
                incoming.updatedAt = now
                tasks[index] = incoming
            } else {
                incoming.createdAt = now
                incoming.updatedAt = now
                tasks.append(incoming)
            }
            rotateBaseline()
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
            return result
        }

        func tasksDue() async throws -> JSONValue {
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
            listAssistantsCalls += 1
            return RemoteAssistants(assistants: assistants, baseline: "", origin: "local")
        }

        func fetchWorkspace(includeArchived: Bool) async throws -> RemoteWorkspace {
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
}
