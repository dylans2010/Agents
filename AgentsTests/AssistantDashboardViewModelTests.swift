import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Assistant dashboard: status mapping, filtering, detail assembly, controls")
struct AssistantDashboardViewModelTests {

    private static func makeRecord(
        id: String = UUID().uuidString,
        name: String = "Worker",
        parentThreadId: String = UUID().uuidString,
        threadId: String = UUID().uuidString,
        task: String = "Do the task",
        provider: String = "claude",
        targetFiles: [String] = [],
        status: String = "running",
        cancelRequested: Bool = false,
        transcriptItems: Int = 0,
        elapsedSeconds: Double = 0,
        createdAt: Double = 1000,
        startedAt: Double = 1000,
        completedAt: Double? = nil,
        error: String? = nil,
        result: String? = nil,
        assistantId: String? = nil
    ) -> WorkerRecord {
        WorkerRecord(
            id: id,
            name: name,
            parentThreadId: parentThreadId,
            threadId: threadId,
            task: task,
            provider: provider,
            targetFiles: targetFiles,
            status: status,
            cancelRequested: cancelRequested,
            transcriptStart: 0,
            transcriptItems: transcriptItems,
            elapsedSeconds: elapsedSeconds,
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: completedAt,
            error: error,
            result: result,
            progress: nil,
            assistantId: assistantId
        )
    }

    private static func makeAssistant(id: UUID = UUID(), name: String = "Reviewer") -> RemoteAssistant {
        RemoteAssistant(id: id, name: name, category: .codeReviewSecurity, systemPrompt: "Review code.")
    }

    private static func makeTranscript(
        threadID: UUID,
        projectID: UUID,
        modelName: String = "claude-sonnet-4",
        branch: String? = "main",
        pendingApprovals: Int = 0,
        items: [RemoteItem] = []
    ) -> RemoteTranscript {
        let summary = RemoteThreadSummary(
            id: threadID,
            projectID: projectID,
            title: "Thread",
            selection: RemoteSelection(provider: "claude", modelID: "claude-sonnet-4", modelName: modelName),
            branch: branch,
            pendingApprovals: pendingApprovals
        )
        return RemoteTranscript(thread: summary, items: items)
    }

    private static func makeToolItem(id: UUID = UUID(), title: String = "read file.swift") -> RemoteItem {
        RemoteItem(id: id, index: 1, kind: .tool, text: "", title: title, category: "read", status: "completed")
    }

    private static func makeApprovalItem(id: UUID = UUID()) -> RemoteItem {
        let option = RemoteApproval.Option(id: "allow", label: "Allow once", kind: "allowOnce")
        let approval = RemoteApproval(options: [option])
        return RemoteItem(id: id, index: 2, kind: .approval, text: "Approve shell command", approval: approval)
    }

    final class StubRunDataSource: AssistantRunDataSource, @unchecked Sendable {
        var runs: [WorkerRecord] = []
        var assistants: [RemoteAssistant] = []
        var transcript: RemoteTranscript?
        var diff: RemoteDiff?
        var gitState: RemoteGitState?
        var workspace = RemoteWorkspace()
        var requestedAssistantIds: [String?] = []
        var cancelledIDs: [String] = []
        var spawnedRequests: [(parentThreadId: String, requests: [WorkerSpawnRequest])] = []
        var failSections: Set<String> = []
        var resultByID: [String: WorkerRecord] = [:]

        func listAssistants() async throws -> RemoteAssistants {
            RemoteAssistants(assistants: assistants)
        }

        func listRuns(assistantId: String?) async throws -> [WorkerRecord] {
            requestedAssistantIds.append(assistantId)
            if let assistantId {
                return runs.filter { $0.assistantId == assistantId }
            }
            return runs
        }

        func workerResult(workerId: String) async throws -> WorkerRecord {
            if failSections.contains("result") {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "result failed"])
            }
            if let updated = resultByID[workerId] {
                return updated
            }
            guard let record = runs.first(where: { $0.id == workerId }) else {
                throw NSError(domain: "test", code: 404, userInfo: [NSLocalizedDescriptionKey: "missing worker"])
            }
            return record
        }

        func cancelWorker(workerId: String) async throws -> WorkerRecord {
            cancelledIDs.append(workerId)
            var record = runs.first(where: { $0.id == workerId }) ?? Self.missingRecord(id: workerId)
            record.status = "cancelled"
            record.cancelRequested = true
            record.completedAt = 2000
            return record
        }

        func spawnWorkers(parentThreadId: String, workers: [WorkerSpawnRequest]) async throws -> JSONValue {
            spawnedRequests.append((parentThreadId: parentThreadId, requests: workers))
            let request = workers[0]
            var spawned = Self.missingRecord(id: UUID().uuidString)
            spawned.name = request.name
            spawned.task = request.task
            spawned.targetFiles = request.targetFiles
            spawned.parentThreadId = parentThreadId
            spawned.assistantId = request.assistantId
            runs.append(spawned)
            return .object(["workers": .array([.object(["id": .string(spawned.id)])])])
        }

        func openThread(_ threadID: UUID, limit: Int) async throws -> RemoteTranscript {
            if failSections.contains("transcript") {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "transcript failed"])
            }
            guard let transcript else {
                throw NSError(domain: "test", code: 404, userInfo: [NSLocalizedDescriptionKey: "no transcript"])
            }
            return transcript
        }

        func fetchDiff(thread: UUID, scope: DiffScope) async throws -> RemoteDiff {
            if failSections.contains("diff") {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "diff failed"])
            }
            guard let diff else {
                throw NSError(domain: "test", code: 404, userInfo: [NSLocalizedDescriptionKey: "no diff"])
            }
            return diff
        }

        func fetchGitState(thread: UUID) async throws -> RemoteGitState {
            if failSections.contains("git") {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "git failed"])
            }
            guard let gitState else {
                throw NSError(domain: "test", code: 404, userInfo: [NSLocalizedDescriptionKey: "no git state"])
            }
            return gitState
        }

        func fetchWorkspace(includeArchived: Bool) async throws -> RemoteWorkspace {
            workspace
        }

        static func missingRecord(id: String) -> WorkerRecord {
            WorkerRecord(
                id: id,
                name: "Missing",
                parentThreadId: UUID().uuidString,
                threadId: UUID().uuidString,
                task: "",
                provider: "",
                targetFiles: [],
                status: "running",
                cancelRequested: false,
                transcriptStart: 0,
                transcriptItems: 0,
                elapsedSeconds: 0,
                createdAt: 0,
                startedAt: 0,
                completedAt: nil,
                error: nil,
                result: nil,
                progress: nil
            )
        }
    }

    @Test("Runtime worker statuses map to dashboard statuses")
    func statusMapping() {
        #expect(AssistantRunStatus.from(runtimeStatus: "running") == .running)
        #expect(AssistantRunStatus.from(runtimeStatus: "completed") == .completed)
        #expect(AssistantRunStatus.from(runtimeStatus: "failed") == .failed)
        #expect(AssistantRunStatus.from(runtimeStatus: "cancelled") == .cancelled)
    }

    @Test("Statuses the runtime never produces map to unknown")
    func unknownStatusMapping() {
        #expect(AssistantRunStatus.from(runtimeStatus: "queued") == .unknown)
        #expect(AssistantRunStatus.from(runtimeStatus: "paused") == .unknown)
        #expect(AssistantRunStatus.from(runtimeStatus: "awaiting-approval") == .unknown)
        #expect(AssistantRunStatus.from(runtimeStatus: "") == .unknown)
        #expect(AssistantRunStatus.from(runtimeStatus: "cancelling") == .unknown)
    }

    @Test("Unknown status is not terminal")
    func unknownStatusIsNotTerminal() {
        #expect(AssistantRunStatus.unknown.isTerminal == false)
        #expect(AssistantRunStatus.running.isTerminal == false)
        #expect(AssistantRunStatus.completed.isTerminal == true)
        #expect(AssistantRunStatus.failed.isTerminal == true)
        #expect(AssistantRunStatus.cancelled.isTerminal == true)
    }

    @Test("Assistant filter excludes runs without an assistant id")
    func assistantFilterExcludesUnattributedRuns() {
        let assistantID = UUID().uuidString
        let runs = [
            Self.makeRecord(assistantId: assistantID),
            Self.makeRecord(assistantId: nil),
            Self.makeRecord(assistantId: UUID().uuidString),
        ]
        let filtered = AssistantDashboardViewModel.filteredRuns(runs, assistantId: assistantID, statusFilter: .all)
        #expect(filtered.count == 1)
        #expect(filtered[0].assistantId == assistantID)
        let all = AssistantDashboardViewModel.filteredRuns(runs, assistantId: nil, statusFilter: .all)
        #expect(all.count == 3)
    }

    @Test("Status filter matches only the mapped status, including unknown")
    func statusFilterMatchesMappedStatus() {
        let runs = [
            Self.makeRecord(status: "running"),
            Self.makeRecord(status: "completed"),
            Self.makeRecord(status: "failed"),
            Self.makeRecord(status: "cancelled"),
            Self.makeRecord(status: "queued"),
        ]
        #expect(AssistantDashboardViewModel.filteredRuns(runs, assistantId: nil, statusFilter: .running).count == 1)
        #expect(AssistantDashboardViewModel.filteredRuns(runs, assistantId: nil, statusFilter: .completed).count == 1)
        #expect(AssistantDashboardViewModel.filteredRuns(runs, assistantId: nil, statusFilter: .failed).count == 1)
        #expect(AssistantDashboardViewModel.filteredRuns(runs, assistantId: nil, statusFilter: .cancelled).count == 1)
        let unknown = AssistantDashboardViewModel.filteredRuns(runs, assistantId: nil, statusFilter: .unknown)
        #expect(unknown.count == 1)
        #expect(unknown[0].status == "queued")
        #expect(AssistantDashboardViewModel.filteredRuns(runs, assistantId: nil, statusFilter: .all).count == 5)
    }

    @Test("Assistant and status filters combine")
    func combinedFilters() {
        let assistantID = UUID().uuidString
        let runs = [
            Self.makeRecord(status: "running", assistantId: assistantID),
            Self.makeRecord(status: "completed", assistantId: assistantID),
            Self.makeRecord(status: "running", assistantId: UUID().uuidString),
        ]
        let filtered = AssistantDashboardViewModel.filteredRuns(runs, assistantId: assistantID, statusFilter: .running)
        #expect(filtered.count == 1)
        #expect(filtered[0].status == "running")
    }

    @Test("Runs sort running first, then newest first")
    func runsSortRunningFirst() {
        let runs = [
            Self.makeRecord(id: "old-completed", status: "completed", startedAt: 1000),
            Self.makeRecord(id: "running", status: "running", startedAt: 500),
            Self.makeRecord(id: "new-completed", status: "completed", startedAt: 2000),
        ]
        let sorted = AssistantDashboardViewModel.sortedRuns(runs)
        #expect(sorted.map(\.id) == ["running", "new-completed", "old-completed"])
    }

    @Test("History holds only terminal runs, newest end first")
    func historyRuns() {
        let runs = [
            Self.makeRecord(id: "running", status: "running"),
            Self.makeRecord(id: "old", status: "completed", startedAt: 1000, completedAt: 1100),
            Self.makeRecord(id: "new", status: "failed", startedAt: 1500, completedAt: 1900),
            Self.makeRecord(id: "cancelled", status: "cancelled", startedAt: 1200, completedAt: 1300),
        ]
        let history = AssistantDashboardViewModel.historyRuns(from: runs, assistantId: nil)
        #expect(history.map(\.id) == ["new", "cancelled", "old"])
    }

    @Test("Detail assembly keeps every field that has a real source")
    func detailAssemblyWithFullSources() {
        let assistant = Self.makeAssistant(name: "Reviewer")
        let threadID = UUID()
        let projectID = UUID()
        let transcript = Self.makeTranscript(
            threadID: threadID,
            projectID: projectID,
            modelName: "claude-sonnet-4",
            branch: "feature/x",
            pendingApprovals: 2,
            items: [Self.makeToolItem(), Self.makeApprovalItem()]
        )
        let changed = RemoteChangedFile(path: "Sources/Foo.swift", status: "modified", additions: 10, deletions: 2)
        var transcriptWithChanges = transcript
        transcriptWithChanges.turnChanges = ["item-1": [changed]]
        let diff = RemoteDiff(
            title: "Uncommitted changes",
            files: [RemoteDiff.File(path: "Sources/Foo.swift", status: "modified", additions: 10, deletions: 2, patch: "@@ -1 +1 @@")]
        )
        let gitState = RemoteGitState(isRepository: true, branch: "feature/x", ahead: 1, behind: 0, changedFiles: 1)
        let project = RemoteProject(id: projectID, name: "MyApp", path: "/Users/dylan/MyApp")
        let record = Self.makeRecord(
            threadId: threadID.uuidString,
            status: "completed",
            startedAt: 1000,
            completedAt: 1600,
            result: "Done."
        )
        let detail = AssistantDashboardViewModel.assembleDetail(
            record: record,
            assistant: assistant,
            transcript: transcriptWithChanges,
            diff: diff,
            gitState: gitState,
            project: project,
            knownThreadIDs: [threadID.uuidString.lowercased()]
        )
        #expect(detail.assistantName == "Reviewer")
        #expect(detail.providerName == "claude")
        #expect(detail.modelName == "claude-sonnet-4")
        #expect(detail.projectName == "MyApp")
        #expect(detail.projectPath == "/Users/dylan/MyApp")
        #expect(detail.branch == "feature/x")
        #expect(detail.startedAt == Date(timeIntervalSince1970: 1000))
        #expect(detail.endedAt == Date(timeIntervalSince1970: 1600))
        #expect(detail.durationSeconds == 600)
        #expect(detail.toolExecutions.count == 1)
        #expect(detail.approvalItems.count == 1)
        #expect(detail.pendingApprovals == 2)
        #expect(detail.changedFiles.count == 1)
        #expect(detail.diff?.files.count == 1)
        #expect(detail.gitState?.ahead == 1)
        #expect(detail.outputText == "Done.")
        #expect(detail.isOrphan == false)
    }

    @Test("Detail assembly omits model, branch, tools, and approvals when there is no transcript")
    func detailAssemblyWithoutTranscript() {
        let record = Self.makeRecord(status: "failed", error: "Provider turn failed")
        let detail = AssistantDashboardViewModel.assembleDetail(
            record: record,
            assistant: nil,
            transcript: nil,
            diff: nil,
            gitState: nil,
            project: nil,
            knownThreadIDs: nil
        )
        #expect(detail.modelName == nil)
        #expect(detail.branch == nil)
        #expect(detail.toolExecutions.isEmpty)
        #expect(detail.approvalItems.isEmpty)
        #expect(detail.pendingApprovals == 0)
        #expect(detail.changedFiles.isEmpty)
        #expect(detail.diff == nil)
        #expect(detail.gitState == nil)
        #expect(detail.projectName == nil)
        #expect(detail.projectPath == nil)
        #expect(detail.assistantName == nil)
        #expect(detail.outputText == nil)
        #expect(detail.record.error == "Provider turn failed")
    }

    @Test("Detail assembly omits the start date when the runtime reports zero")
    func detailAssemblyOmitsZeroStart() {
        let record = Self.makeRecord(status: "failed", startedAt: 0, createdAt: 0)
        let detail = AssistantDashboardViewModel.assembleDetail(
            record: record,
            assistant: nil,
            transcript: nil,
            diff: nil,
            gitState: nil,
            project: nil,
            knownThreadIDs: nil
        )
        #expect(detail.startedAt == nil)
        #expect(detail.durationSeconds == nil)
    }

    @Test("Detail duration falls back to live elapsed seconds while running")
    func detailDurationWhileRunning() {
        let record = Self.makeRecord(status: "running", elapsedSeconds: 42, startedAt: 1000)
        let detail = AssistantDashboardViewModel.assembleDetail(
            record: record,
            assistant: nil,
            transcript: nil,
            diff: nil,
            gitState: nil,
            project: nil,
            knownThreadIDs: nil
        )
        #expect(detail.durationSeconds == 42)
        #expect(detail.endedAt == nil)
    }

    @Test("Detail marks a run orphaned when its parent thread is gone")
    func detailOrphanDetection() {
        let record = Self.makeRecord(parentThreadId: UUID().uuidString)
        let detail = AssistantDashboardViewModel.assembleDetail(
            record: record,
            assistant: nil,
            transcript: nil,
            diff: nil,
            gitState: nil,
            project: nil,
            knownThreadIDs: [UUID().uuidString.lowercased()]
        )
        #expect(detail.isOrphan == true)
    }

    @Test("Running run offers cancel but not retry")
    func controlsForRunningRun() {
        let controls = AssistantDashboardViewModel.availableControls(for: Self.makeRecord(status: "running"), projectPath: "/tmp/App")
        #expect(controls.contains(.cancel))
        #expect(!controls.contains(.retry))
        #expect(controls.contains(.openThread))
        #expect(controls.contains(.viewOutput))
        #expect(controls.contains(.reviewChanges))
        #expect(controls.contains(.openWorkspace))
    }

    @Test("Failed and cancelled runs offer retry but not cancel")
    func controlsForTerminalFailedRuns() {
        for status in ["failed", "cancelled"] {
            let controls = AssistantDashboardViewModel.availableControls(for: Self.makeRecord(status: status), projectPath: nil)
            #expect(controls.contains(.retry))
            #expect(!controls.contains(.cancel))
            #expect(!controls.contains(.openWorkspace))
        }
    }

    @Test("Orphaned failed run offers no retry control")
    func controlsForOrphanedFailedRunOfferNoRetry() {
        let controls = AssistantDashboardViewModel.availableControls(for: Self.makeRecord(status: "failed"), projectPath: nil, isOrphan: true)
        #expect(!controls.contains(.retry))
        #expect(controls.contains(.openThread))
        let nonOrphaned = AssistantDashboardViewModel.availableControls(for: Self.makeRecord(status: "failed"), projectPath: nil, isOrphan: false)
        #expect(nonOrphaned.contains(.retry))
    }

    @Test("Completed run offers neither cancel nor retry")
    func controlsForCompletedRun() {
        let controls = AssistantDashboardViewModel.availableControls(for: Self.makeRecord(status: "completed"), projectPath: nil)
        #expect(!controls.contains(.cancel))
        #expect(!controls.contains(.retry))
        #expect(controls.contains(.openThread))
    }

    @Test("Run without a thread id offers no thread-backed controls")
    func controlsWithoutThreadId() {
        let record = Self.makeRecord(threadId: "")
        let controls = AssistantDashboardViewModel.availableControls(for: record, projectPath: "/tmp/App")
        #expect(!controls.contains(.openThread))
        #expect(!controls.contains(.viewOutput))
        #expect(!controls.contains(.reviewChanges))
        #expect(controls.contains(.openWorkspace))
    }

    @Test("Run with a non-UUID thread id offers open thread but not output or changes")
    func controlsWithNonUUIDThreadId() {
        let record = Self.makeRecord(threadId: "not-a-uuid")
        let controls = AssistantDashboardViewModel.availableControls(for: record, projectPath: nil)
        #expect(controls.contains(.openThread))
        #expect(!controls.contains(.viewOutput))
        #expect(!controls.contains(.reviewChanges))
    }

    @Test("Retry request preserves name, task, target files, and assistant id")
    func retryRequestPreservesInputs() {
        let assistantID = UUID().uuidString
        let record = Self.makeRecord(
            name: "Fix build",
            task: "Fix the failing build",
            targetFiles: ["Sources/Foo.swift"],
            status: "failed",
            assistantId: assistantID
        )
        let request = AssistantDashboardViewModel.retryRequest(for: record)
        #expect(request.name == "Fix build")
        #expect(request.task == "Fix the failing build")
        #expect(request.targetFiles == ["Sources/Foo.swift"])
        #expect(request.assistantId == assistantID)
    }

    @Test("Duration label never invents a percentage")
    func durationLabelFormatting() {
        #expect(AssistantDashboardFormatting.durationLabel(0) == "0s")
        #expect(AssistantDashboardFormatting.durationLabel(45) == "45s")
        #expect(AssistantDashboardFormatting.durationLabel(125) == "2m 5s")
        #expect(AssistantDashboardFormatting.durationLabel(3720) == "1h 2m")
    }

    @Test("Output truncation keeps the first lines and notes the rest")
    func outputTruncation() {
        let long = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let truncated = AssistantRunDetailView.truncatedOutput(long)
        #expect(AssistantRunDetailView.isOutputTruncated(long))
        #expect(truncated.hasPrefix("line 1"))
        #expect(truncated.contains("more lines"))
        #expect(!AssistantRunDetailView.isOutputTruncated("short output"))
    }

    @Test("View model loads runs through the assistant filter")
    @MainActor
    func viewModelLoadsRunsWithAssistantFilter() async {
        let stub = StubRunDataSource()
        let assistantID = UUID().uuidString
        stub.runs = [
            Self.makeRecord(assistantId: assistantID),
            Self.makeRecord(assistantId: UUID().uuidString),
        ]
        let viewModel = AssistantDashboardViewModel(sourceProvider: { stub })
        viewModel.selectedAssistantID = UUID(uuidString: assistantID)
        await viewModel.loadRuns()
        #expect(viewModel.runs.count == 1)
        #expect(stub.requestedAssistantIds.last == assistantID)
    }

    @Test("View model cancel updates the run in place")
    @MainActor
    func viewModelCancelUpdatesRun() async {
        let stub = StubRunDataSource()
        let record = Self.makeRecord(status: "running")
        stub.runs = [record]
        let viewModel = AssistantDashboardViewModel(sourceProvider: { stub })
        await viewModel.loadRuns()
        await viewModel.cancelRun(record)
        #expect(stub.cancelledIDs == [record.id])
        #expect(viewModel.runs.first?.status == "cancelled")
        #expect(viewModel.runs.first?.cancelRequested == true)
    }

    @Test("View model retry spawns the same inputs on the same parent thread")
    @MainActor
    func viewModelRetryRespawnsRun() async {
        let stub = StubRunDataSource()
        let assistantID = UUID().uuidString
        let parentID = UUID().uuidString
        let record = Self.makeRecord(
            parentThreadId: parentID,
            task: "Fix the build",
            targetFiles: ["Sources/Foo.swift"],
            status: "failed",
            assistantId: assistantID
        )
        stub.runs = [record]
        let viewModel = AssistantDashboardViewModel(sourceProvider: { stub })
        await viewModel.loadRuns()
        await viewModel.retryRun(record)
        #expect(stub.spawnedRequests.count == 1)
        #expect(stub.spawnedRequests[0].parentThreadId == parentID)
        #expect(stub.spawnedRequests[0].requests[0].task == "Fix the build")
        #expect(stub.spawnedRequests[0].requests[0].targetFiles == ["Sources/Foo.swift"])
        #expect(stub.spawnedRequests[0].requests[0].assistantId == assistantID)
        #expect(viewModel.runs.count == 2)
        #expect(viewModel.selectedRunID == stub.runs.last?.id)
    }

    @Test("View model retry of a running run does nothing")
    @MainActor
    func viewModelRetryOfRunningRunDoesNothing() async {
        let stub = StubRunDataSource()
        let record = Self.makeRecord(status: "running")
        stub.runs = [record]
        let viewModel = AssistantDashboardViewModel(sourceProvider: { stub })
        await viewModel.loadRuns()
        await viewModel.retryRun(record)
        #expect(stub.spawnedRequests.isEmpty)
        #expect(viewModel.runs.count == 1)
        #expect(viewModel.selectedRunID == nil)
    }

    @Test("View model cancel of a terminal run does nothing")
    @MainActor
    func viewModelCancelOfTerminalRunDoesNothing() async {
        let stub = StubRunDataSource()
        let record = Self.makeRecord(status: "completed")
        stub.runs = [record]
        let viewModel = AssistantDashboardViewModel(sourceProvider: { stub })
        await viewModel.loadRuns()
        await viewModel.cancelRun(record)
        #expect(stub.cancelledIDs.isEmpty)
        #expect(viewModel.runs.first?.status == "completed")
    }

    @Test("View model detail load reports sections that failed to load")
    @MainActor
    func viewModelDetailLoadReportsFailedSections() async {
        let stub = StubRunDataSource()
        let threadID = UUID()
        let record = Self.makeRecord(threadId: threadID.uuidString, status: "completed", result: "Done.")
        stub.runs = [record]
        stub.transcript = Self.makeTranscript(threadID: threadID, projectID: UUID())
        stub.failSections = ["diff", "git"]
        let viewModel = AssistantDashboardViewModel(sourceProvider: { stub })
        viewModel.runs = [record]
        await viewModel.loadDetail(for: record)
        #expect(viewModel.detail?.outputText == "Done.")
        #expect(viewModel.detail?.diff == nil)
        #expect(viewModel.detail?.gitState == nil)
        #expect(viewModel.detailNotice?.contains("Changes") == true)
        #expect(viewModel.detailNotice?.contains("Git state") == true)
    }

    @Test("View model open thread routes through the provided handler")
    @MainActor
    func viewModelOpenThreadHandler() async {
        let stub = StubRunDataSource()
        var opened: [String] = []
        let viewModel = AssistantDashboardViewModel(sourceProvider: { stub }) { threadId in
            opened.append(threadId)
        }
        let record = Self.makeRecord(threadId: "thread-123")
        viewModel.openRunThread(record)
        #expect(opened == ["thread-123"])
        viewModel.openRunThread(Self.makeRecord(threadId: ""))
        #expect(opened == ["thread-123"])
    }
}
