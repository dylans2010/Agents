import CoincideRemoteKit
import Foundation
import Testing
import UserNotifications
@testable import Agents

@Suite("Assistant Notifications: Manager, Settings & Deep Links")
@MainActor
struct AssistantNotificationManagerTests {

    private final class RecordingPoster: AssistantNotificationPosting {
        var requests: [UNNotificationRequest] = []

        func add(_ request: UNNotificationRequest) {
            requests.append(request)
        }
    }

    private static let assistantID = "AAAAAAAA-1111-4111-8111-111111111111"
    private static let threadID = "BBBBBBBB-2222-4222-8222-222222222222"
    private static let projectID = "CCCCCCCC-3333-4333-8333-333333333333"

    private func makeSettings() -> (AssistantNotificationSettings, String) {
        let suiteName = "com.apoorvdarshan.coincide.tests.assistantNotifications.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let settings = AssistantNotificationSettings(defaults: suite)
        return (settings, suiteName)
    }

    private func makeManager(settings: AssistantNotificationSettings, isAppActive: @escaping () -> Bool = { false }) -> (AssistantNotificationManager, RecordingPoster) {
        let poster = RecordingPoster()
        let manager = AssistantNotificationManager(
            settings: settings,
            poster: poster,
            isAppActive: isAppActive,
            bundleIdentifier: "com.apoorvdarshan.coincide.tests"
        )
        return (manager, poster)
    }

    private func makeThread(
        assistantId: String? = assistantID,
        title: String = "Review pass",
        scheduleCount: Int? = nil,
        pendingApprovals: Int = 0,
        pendingQuestions: Int = 0
    ) -> RemoteThreadSummary {
        RemoteThreadSummary(
            id: UUID(uuidString: Self.threadID)!,
            projectID: UUID(uuidString: Self.projectID)!,
            title: title,
            selection: RemoteSelection(provider: "codex", modelID: "gpt-5", modelName: "GPT-5"),
            pendingApprovals: pendingApprovals,
            pendingQuestions: pendingQuestions,
            scheduleCount: scheduleCount,
            assistantId: assistantId
        )
    }

    private func makeWorker(
        status: String = "completed",
        result: String? = "Found three blockers.",
        assistantId: String? = assistantID
    ) -> WorkerRecord {
        WorkerRecord(
            id: "worker-1",
            name: "Review worker",
            parentThreadId: "DDDDDDDD-4444-4444-8444-444444444444",
            threadId: Self.threadID,
            task: "Review the change",
            provider: "codex",
            targetFiles: [],
            status: status,
            cancelRequested: false,
            transcriptStart: 0,
            transcriptItems: 4,
            elapsedSeconds: 12,
            createdAt: 0,
            startedAt: 0,
            completedAt: status == "completed" ? 12 : nil,
            error: status == "failed" ? "boom" : nil,
            result: result,
            progress: nil,
            assistantId: assistantId
        )
    }

    @Test("Run completed posts with assistant deep link")
    func runCompletedPostsWithDeepLink() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        let handled = manager.notifyTurnFinished(thread: makeThread(), outcome: "completed", assistantName: "Reviewer")
        #expect(handled == true)
        #expect(poster.requests.count == 1)
        let request = poster.requests[0]
        #expect(request.identifier == "assistant-runCompleted-\(Self.threadID)")
        #expect(request.content.title == "Reviewer")
        #expect(request.content.body == "Finished: Review pass")
        #expect(request.content.userInfo["assistantID"] as? String == Self.assistantID)
        #expect(request.content.userInfo["threadID"] as? String == Self.threadID)
        #expect(request.content.userInfo["runID"] as? String == Self.threadID)
        #expect(request.content.userInfo["category"] as? String == "runCompleted")
    }

    @Test("Run failed posts failed category")
    func runFailedPostsFailedCategory() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        let handled = manager.notifyTurnFinished(thread: makeThread(), outcome: "failed", assistantName: "Reviewer")
        #expect(handled == true)
        #expect(poster.requests.count == 1)
        #expect(poster.requests[0].content.userInfo["category"] as? String == "runFailed")
        #expect(poster.requests[0].content.body == "Failed: Review pass")
    }

    @Test("Interrupted outcome posts nothing and is unclassified")
    func interruptedOutcomePostsNothing() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyTurnFinished(thread: makeThread(), outcome: "interrupted", assistantName: "Reviewer") == false)
        #expect(manager.notifyTurnFinished(thread: makeThread(), outcome: "", assistantName: "Reviewer") == false)
        #expect(poster.requests.isEmpty)
    }

    @Test("Non-assistant thread posts nothing")
    func nonAssistantThreadPostsNothing() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyTurnFinished(thread: makeThread(assistantId: nil), outcome: "completed", assistantName: nil) == false)
        #expect(poster.requests.isEmpty)
    }

    @Test("Disabled run-completed category posts nothing but still classifies")
    func disabledCategoryStillClassifies() {
        let (settings, _) = makeSettings()
        settings.runCompletedEnabled = false
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyTurnFinished(thread: makeThread(), outcome: "completed", assistantName: "Reviewer") == true)
        #expect(poster.requests.isEmpty)
    }

    @Test("Master toggle off silences every category")
    func masterToggleSilencesAll() {
        let (settings, _) = makeSettings()
        settings.isEnabled = false
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyTurnFinished(thread: makeThread(), outcome: "completed", assistantName: "Reviewer") == true)
        #expect(manager.notifyTurnFinished(thread: makeThread(), outcome: "failed", assistantName: "Reviewer") == true)
        #expect(manager.notifyApprovalNeeded(threads: [makeThread(pendingApprovals: 1)], assistantName: { _ in "Reviewer" }) == true)
        #expect(manager.notifyWorkerTerminal(makeWorker(), assistantName: "Reviewer") == true)
        #expect(poster.requests.isEmpty)
    }

    @Test("Second terminal event for the same run posts nothing")
    func dedupSecondTerminalEvent() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyTurnFinished(thread: makeThread(), outcome: "completed", assistantName: "Reviewer") == true)
        #expect(manager.notifyTurnFinished(thread: makeThread(), outcome: "completed", assistantName: "Reviewer") == true)
        #expect(poster.requests.count == 1)
    }

    @Test("Scheduled thread completion posts automation category")
    func scheduledCompletionPostsAutomation() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyTurnFinished(thread: makeThread(scheduleCount: 2), outcome: "completed", assistantName: "Reviewer") == true)
        #expect(poster.requests.count == 1)
        #expect(poster.requests[0].content.userInfo["category"] as? String == "automationExecuted")
        #expect(poster.requests[0].content.body == "Scheduled run finished: Review pass")
    }

    @Test("Failed scheduled run still posts failure")
    func failedScheduledRunPostsFailure() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyTurnFinished(thread: makeThread(scheduleCount: 2), outcome: "failed", assistantName: "Reviewer") == true)
        #expect(poster.requests[0].content.userInfo["category"] as? String == "runFailed")
    }

    @Test("Approval posts per assistant thread with deep link")
    func approvalPostsPerAssistantThread() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        let threads = [
            makeThread(pendingApprovals: 2),
            makeThread(assistantId: nil, pendingApprovals: 3),
            makeThread(title: "Quiet thread")
        ]
        #expect(manager.notifyApprovalNeeded(threads: threads, assistantName: { _ in "Reviewer" }) == true)
        #expect(poster.requests.count == 1)
        #expect(poster.requests[0].content.title == "Reviewer Needs Input")
        #expect(poster.requests[0].content.body == "2 tool approvals waiting.")
        #expect(poster.requests[0].content.userInfo["threadID"] as? String == Self.threadID)
        #expect(poster.requests[0].content.userInfo["assistantID"] as? String == Self.assistantID)
        #expect(poster.requests[0].content.userInfo["category"] as? String == "needsApproval")
    }

    @Test("Approval posts nothing when no assistant thread waits")
    func approvalPostsNothingWithoutAssistantThread() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyApprovalNeeded(threads: [makeThread(assistantId: nil, pendingApprovals: 3)], assistantName: { _ in nil }) == false)
        #expect(poster.requests.isEmpty)
    }

    @Test("Approval repeats only when counts change")
    func approvalRepeatsOnlyOnCountChange() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyApprovalNeeded(threads: [makeThread(pendingApprovals: 1)], assistantName: { _ in "Reviewer" }) == true)
        #expect(poster.requests.count == 1)
        #expect(manager.notifyApprovalNeeded(threads: [makeThread(pendingApprovals: 1)], assistantName: { _ in "Reviewer" }) == true)
        #expect(poster.requests.count == 1)
        #expect(manager.notifyApprovalNeeded(threads: [makeThread(pendingApprovals: 2)], assistantName: { _ in "Reviewer" }) == true)
        #expect(poster.requests.count == 2)
    }

    @Test("Worker with findings posts significant findings")
    func workerWithFindingsPosts() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyWorkerTerminal(makeWorker(), assistantName: "Reviewer") == true)
        #expect(poster.requests.count == 1)
        #expect(poster.requests[0].content.userInfo["category"] as? String == "significantFindings")
        #expect(poster.requests[0].content.userInfo["threadID"] as? String == Self.threadID)
        #expect(poster.requests[0].content.userInfo["runID"] as? String == Self.threadID)
        #expect(poster.requests[0].content.body.contains("Review worker") == true)
        #expect(poster.requests[0].content.body.contains("Found three blockers.") == true)
    }

    @Test("Worker without a result posts no findings")
    func workerWithoutResultPostsNothing() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyWorkerTerminal(makeWorker(result: nil), assistantName: "Reviewer") == false)
        #expect(manager.notifyWorkerTerminal(makeWorker(result: "   "), assistantName: "Reviewer") == false)
        #expect(poster.requests.isEmpty)
    }

    @Test("Failed worker posts run failed, deduped against the turn path")
    func failedWorkerDedupedAgainstTurnPath() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyTurnFinished(thread: makeThread(), outcome: "failed", assistantName: "Reviewer") == true)
        #expect(manager.notifyWorkerTerminal(makeWorker(status: "failed", result: nil), assistantName: "Reviewer") == true)
        #expect(poster.requests.count == 1)
    }

    @Test("Running worker posts nothing")
    func runningWorkerPostsNothing() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings)
        #expect(manager.notifyWorkerTerminal(makeWorker(status: "running"), assistantName: "Reviewer") == false)
        #expect(poster.requests.isEmpty)
    }

    @Test("App in foreground posts nothing")
    func foregroundPostsNothing() {
        let (settings, _) = makeSettings()
        let (manager, poster) = makeManager(settings: settings, isAppActive: { true })
        #expect(manager.notifyTurnFinished(thread: makeThread(), outcome: "completed", assistantName: "Reviewer") == true)
        #expect(poster.requests.isEmpty)
    }

    @Test("Settings round-trip through UserDefaults")
    func settingsRoundTrip() {
        let (settings, suiteName) = makeSettings()
        settings.isEnabled = false
        settings.runCompletedEnabled = false
        settings.needsApprovalEnabled = false
        settings.automationExecutedEnabled = false
        let reloaded = AssistantNotificationSettings(defaults: UserDefaults(suiteName: suiteName)!)
        #expect(reloaded.isEnabled == false)
        #expect(reloaded.runCompletedEnabled == false)
        #expect(reloaded.runFailedEnabled == true)
        #expect(reloaded.needsApprovalEnabled == false)
        #expect(reloaded.automationExecutedEnabled == false)
        #expect(reloaded.significantFindingsEnabled == true)
        #expect(reloaded.isCategoryEnabled(.runCompleted) == false)
        #expect(reloaded.isCategoryEnabled(.runFailed) == false)
    }

    @Test("Category toggles round-trip independently")
    func categoryTogglesIndependent() {
        let (settings, suiteName) = makeSettings()
        settings.setCategoryEnabled(false, for: .significantFindings)
        let reloaded = AssistantNotificationSettings(defaults: UserDefaults(suiteName: suiteName)!)
        #expect(reloaded.significantFindingsEnabled == false)
        #expect(reloaded.isCategoryEnabled(.significantFindings) == false)
        #expect(reloaded.isCategoryEnabled(.runCompleted) == true)
    }

    private static func makeTask(
        notifications: AssistantTaskNotificationPrefs = AssistantTaskNotificationPrefs()
    ) -> AssistantTaskRecord {
        AssistantTaskRecord(
            id: UUID(), name: "Nightly review", assistantID: UUID(), workspaceID: UUID(),
            notifications: notifications
        )
    }

    @Test("Task completion honors the task success preference")
    func taskCompletionHonorsSuccessPreference() {
        let (settings, _) = makeSettings()
        let (manager, _) = makeManager(settings: settings)
        let silenced = Self.makeTask(notifications: AssistantTaskNotificationPrefs(onSuccess: false, onFailure: true, onMissed: true))
        #expect(manager.allowsTaskNotification(task: silenced, outcome: "completed", scheduleCount: 0) == false)
        let allowed = Self.makeTask(notifications: AssistantTaskNotificationPrefs(onSuccess: true, onFailure: true, onMissed: true))
        #expect(manager.allowsTaskNotification(task: allowed, outcome: "completed", scheduleCount: 0) == true)
    }

    @Test("Task failure honors the task failure preference")
    func taskFailureHonorsFailurePreference() {
        let (settings, _) = makeSettings()
        let (manager, _) = makeManager(settings: settings)
        let silenced = Self.makeTask(notifications: AssistantTaskNotificationPrefs(onSuccess: true, onFailure: false, onMissed: true))
        #expect(manager.allowsTaskNotification(task: silenced, outcome: "failed", scheduleCount: 0) == false)
        let allowed = Self.makeTask(notifications: AssistantTaskNotificationPrefs(onSuccess: true, onFailure: true, onMissed: true))
        #expect(manager.allowsTaskNotification(task: allowed, outcome: "failed", scheduleCount: 0) == true)
    }

    @Test("Scheduled task completion uses the automation category")
    func scheduledTaskCompletionUsesAutomationCategory() {
        let (settings, _) = makeSettings()
        let (manager, _) = makeManager(settings: settings)
        let task = Self.makeTask(notifications: AssistantTaskNotificationPrefs(onSuccess: true, onFailure: true, onMissed: true))
        #expect(manager.allowsTaskNotification(task: task, outcome: "completed", scheduleCount: 1) == true)
        settings.setCategoryEnabled(false, for: .automationExecuted)
        #expect(manager.allowsTaskNotification(task: task, outcome: "completed", scheduleCount: 1) == false)
        #expect(manager.allowsTaskNotification(task: task, outcome: "completed", scheduleCount: 0) == true)
    }

    @Test("Master toggle off silences task notifications")
    func masterToggleSilencesTaskNotifications() {
        let (settings, _) = makeSettings()
        let (manager, _) = makeManager(settings: settings)
        let task = Self.makeTask(notifications: AssistantTaskNotificationPrefs(onSuccess: true, onFailure: true, onMissed: true))
        settings.isEnabled = false
        #expect(manager.allowsTaskNotification(task: task, outcome: "completed", scheduleCount: 0) == false)
        #expect(manager.allowsTaskNotification(task: task, outcome: "failed", scheduleCount: 0) == false)
    }

    @Test("Interrupted task outcome never notifies")
    func interruptedTaskOutcomeNeverNotifies() {
        let (settings, _) = makeSettings()
        let (manager, _) = makeManager(settings: settings)
        let task = Self.makeTask(notifications: AssistantTaskNotificationPrefs(onSuccess: true, onFailure: true, onMissed: true))
        #expect(manager.allowsTaskNotification(task: task, outcome: "interrupted", scheduleCount: 0) == false)
    }
}
