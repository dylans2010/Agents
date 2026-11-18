import CoincideRemoteKit
import Foundation
import Observation

public enum AssistantRunStatusFilter: String, CaseIterable, Sendable, Identifiable {
    case all
    case running
    case completed
    case failed
    case cancelled
    case unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unknown"
        }
    }

    public func matches(_ record: WorkerRecord) -> Bool {
        switch self {
        case .all: return true
        case .unknown: return AssistantRunStatus.from(runtimeStatus: record.status) == .unknown
        case .running: return record.status == "running"
        case .completed: return record.status == "completed"
        case .failed: return record.status == "failed"
        case .cancelled: return record.status == "cancelled"
        }
    }
}

public enum AssistantRunControl: String, CaseIterable, Sendable, Hashable {
    case openThread
    case cancel
    case retry
    case viewOutput
    case reviewChanges
    case openWorkspace
}

public protocol AssistantRunDataSource: Sendable {
    func listAssistants() async throws -> RemoteAssistants
    func listRuns(assistantId: String?) async throws -> [WorkerRecord]
    func workerResult(workerId: String) async throws -> WorkerRecord
    func cancelWorker(workerId: String) async throws -> WorkerRecord
    func spawnWorkers(parentThreadId: String, workers: [WorkerSpawnRequest]) async throws -> JSONValue
    func openThread(_ threadID: UUID, limit: Int) async throws -> RemoteTranscript
    func fetchDiff(thread: UUID, scope: DiffScope) async throws -> RemoteDiff
    func fetchGitState(thread: UUID) async throws -> RemoteGitState
    func fetchWorkspace(includeArchived: Bool) async throws -> RemoteWorkspace
}

extension AgentsRuntimeClient: AssistantRunDataSource {
    public func listRuns(assistantId: String?) async throws -> [WorkerRecord] {
        if let assistantId {
            return try await listWorkers(assistantId: assistantId)
        }
        return try await listWorkers()
    }
}

public struct AssistantRunDetail: Sendable, Hashable {
    public var record: WorkerRecord
    public var assistantName: String?
    public var providerName: String?
    public var modelName: String?
    public var projectName: String?
    public var projectPath: String?
    public var branch: String?
    public var startedAt: Date?
    public var endedAt: Date?
    public var durationSeconds: TimeInterval?
    public var targetFiles: [String]
    public var toolExecutions: [RemoteItem]
    public var approvalItems: [RemoteItem]
    public var pendingApprovals: Int
    public var changedFiles: [RemoteChangedFile]
    public var diff: RemoteDiff?
    public var gitState: RemoteGitState?
    public var transcript: RemoteTranscript?
    public var isOrphan: Bool

    public var status: AssistantRunStatus {
        AssistantRunStatus.from(runtimeStatus: record.status)
    }

    public var outputText: String? {
        guard let result = record.result, !result.isEmpty else { return nil }
        return result
    }

    public init(
        record: WorkerRecord,
        assistantName: String? = nil,
        providerName: String? = nil,
        modelName: String? = nil,
        projectName: String? = nil,
        projectPath: String? = nil,
        branch: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        durationSeconds: TimeInterval? = nil,
        targetFiles: [String] = [],
        toolExecutions: [RemoteItem] = [],
        approvalItems: [RemoteItem] = [],
        pendingApprovals: Int = 0,
        changedFiles: [RemoteChangedFile] = [],
        diff: RemoteDiff? = nil,
        gitState: RemoteGitState? = nil,
        transcript: RemoteTranscript? = nil,
        isOrphan: Bool = false
    ) {
        self.record = record
        self.assistantName = assistantName
        self.providerName = providerName
        self.modelName = modelName
        self.projectName = projectName
        self.projectPath = projectPath
        self.branch = branch
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.targetFiles = targetFiles
        self.toolExecutions = toolExecutions
        self.approvalItems = approvalItems
        self.pendingApprovals = pendingApprovals
        self.changedFiles = changedFiles
        self.diff = diff
        self.gitState = gitState
        self.transcript = transcript
        self.isOrphan = isOrphan
    }
}

@MainActor
@Observable
public final class AssistantDashboardViewModel {
    @ObservationIgnored private let sourceProvider: () -> (any AssistantRunDataSource)?
    @ObservationIgnored public var onOpenThread: ((String) -> Void)?

    public var assistants: [RemoteAssistant] = []
    public var selectedAssistantID: UUID?
    public var statusFilter: AssistantRunStatusFilter = .all
    public var runs: [WorkerRecord] = []
    public var selectedRunID: String?
    public var detail: AssistantRunDetail?
    public var detailNotice: String?
    public var workspace: RemoteWorkspace?
    public var isLoading = false
    public var errorText: String?
    public var cancellingIDs: Set<String> = []
    public var retryingIDs: Set<String> = []

    @ObservationIgnored private var liveRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?

    public init(
        sourceProvider: @escaping () -> (any AssistantRunDataSource)?,
        onOpenThread: ((String) -> Void)? = nil
    ) {
        self.sourceProvider = sourceProvider
        self.onOpenThread = onOpenThread
    }

    public var filteredRuns: [WorkerRecord] {
        Self.sortedRuns(Self.filteredRuns(runs, assistantId: selectedAssistantID?.uuidString, statusFilter: statusFilter))
    }

    public var historyRuns: [WorkerRecord] {
        Self.historyRuns(from: runs, assistantId: selectedAssistantID?.uuidString)
    }

    public var selectedRun: WorkerRecord? {
        runs.first { $0.id == selectedRunID }
    }

    public var runningCount: Int {
        runs.filter(\.isRunning).count
    }

    public var knownThreadIDs: Set<String>? {
        guard let workspace else { return nil }
        return Set(workspace.threads.map { $0.id.uuidString.lowercased() })
    }

    public func assistant(for record: WorkerRecord) -> RemoteAssistant? {
        guard let assistantId = record.assistantId else { return nil }
        return assistants.first { $0.id.uuidString == assistantId }
    }

    public func assistantName(for record: WorkerRecord) -> String? {
        assistant(for: record)?.name
    }

    public func project(for record: WorkerRecord) -> RemoteProject? {
        guard let workspace else { return nil }
        let threadID = record.threadId.lowercased()
        guard let projectID = workspace.threads.first(where: { $0.id.uuidString.lowercased() == threadID })?.projectID else {
            return nil
        }
        return workspace.projects.first { $0.id == projectID }
    }

    public func project(for record: WorkerRecord, transcript: RemoteTranscript?) -> RemoteProject? {
        if let transcript {
            let projectID = transcript.thread.projectID
            if let resolved = workspace?.projects.first(where: { $0.id == projectID }) {
                return resolved
            }
        }
        return project(for: record)
    }

    public func refresh() async {
        await loadAssistants()
        await loadWorkspace()
        await loadRuns()
    }

    public func loadAssistants() async {
        guard let source = sourceProvider() else { return }
        do {
            assistants = try await source.listAssistants().assistants
        } catch {
            errorText = ErrorSanitizer.displayMessage(for: error)
        }
    }

    public func loadWorkspace() async {
        guard let source = sourceProvider() else { return }
        workspace = try? await source.fetchWorkspace(includeArchived: true)
    }

    public func loadRuns(silent: Bool = false) async {
        guard let source = sourceProvider() else { return }
        if !silent {
            isLoading = true
        }
        defer {
            if !silent {
                isLoading = false
            }
        }
        do {
            let loaded = try await source.listRuns(assistantId: selectedAssistantID?.uuidString)
            if !Task.isCancelled {
                runs = loaded
                cancellingIDs.subtract(Set(loaded.filter(\.isTerminal).map(\.id)))
            }
            errorText = nil
        } catch {
            if !Task.isCancelled && !silent {
                errorText = ErrorSanitizer.displayMessage(for: error)
            }
        }
    }

    public func selectRun(_ record: WorkerRecord) {
        selectedRunID = record.id
        detailNotice = nil
        detail = Self.assembleDetail(
            record: record,
            assistant: assistant(for: record),
            transcript: nil,
            diff: nil,
            gitState: nil,
            project: project(for: record),
            knownThreadIDs: knownThreadIDs
        )
        Task { await loadDetail(for: record) }
    }

    public func loadDetail(for record: WorkerRecord) async {
        detailTask?.cancel()
        detailTask = Task { [weak self] in
            guard let self else { return }
            guard let source = self.sourceProvider() else { return }
            var failedSections: [String] = []
            var refreshed = record
            if let updated = try? await source.workerResult(workerId: record.id) {
                refreshed = updated
                self.replaceRun(updated)
            }
            let threadID = UUID(uuidString: refreshed.threadId)
            var transcript: RemoteTranscript?
            if let threadID {
                do {
                    transcript = try await source.openThread(threadID, limit: 200)
                } catch {
                    failedSections.append("Transcript")
                }
            }
            var diff: RemoteDiff?
            if let threadID {
                do {
                    diff = try await source.fetchDiff(thread: threadID, scope: .uncommitted)
                } catch {
                    failedSections.append("Changes")
                }
            }
            var gitState: RemoteGitState?
            if let threadID {
                do {
                    gitState = try await source.fetchGitState(thread: threadID)
                } catch {
                    failedSections.append("Git state")
                }
            }
            guard !Task.isCancelled else { return }
            guard self.selectedRunID == record.id else { return }
            self.detailNotice = failedSections.isEmpty ? nil : "Could not load: \(failedSections.joined(separator: ", "))."
            self.detail = Self.assembleDetail(
                record: refreshed,
                assistant: self.assistant(for: refreshed),
                transcript: transcript,
                diff: diff,
                gitState: gitState,
                project: self.project(for: refreshed, transcript: transcript),
                knownThreadIDs: self.knownThreadIDs
            )
        }
        await detailTask?.value
    }

    public func cancelRun(_ record: WorkerRecord) async {
        guard AssistantRunStatus.from(runtimeStatus: record.status) == .running else { return }
        guard let source = sourceProvider() else { return }
        guard !cancellingIDs.contains(record.id) else { return }
        cancellingIDs.insert(record.id)
        do {
            let updated = try await source.cancelWorker(workerId: record.id)
            replaceRun(updated)
            if updated.isTerminal {
                cancellingIDs.remove(record.id)
            }
            if selectedRunID == record.id {
                detail = Self.assembleDetail(
                    record: updated,
                    assistant: assistant(for: updated),
                    transcript: detail?.transcript,
                    diff: detail?.diff,
                    gitState: detail?.gitState,
                    project: project(for: updated),
                    knownThreadIDs: knownThreadIDs
                )
            }
            errorText = nil
        } catch {
            cancellingIDs.remove(record.id)
            errorText = ErrorSanitizer.displayMessage(for: error)
        }
    }

    public func retryRun(_ record: WorkerRecord) async {
        let status = AssistantRunStatus.from(runtimeStatus: record.status)
        guard status == .failed || status == .cancelled else { return }
        guard let source = sourceProvider() else { return }
        guard !retryingIDs.contains(record.id) else { return }
        retryingIDs.insert(record.id)
        defer { retryingIDs.remove(record.id) }
        do {
            let result = try await source.spawnWorkers(
                parentThreadId: record.parentThreadId,
                workers: [Self.retryRequest(for: record)]
            )
            await loadRuns()
            if let spawned = result["workers"]?.arrayValue,
               let first = spawned.first,
               let id = first["id"]?.stringValue,
               let newRecord = runs.first(where: { $0.id == id }) {
                selectRun(newRecord)
            }
            errorText = nil
        } catch {
            errorText = ErrorSanitizer.displayMessage(for: error)
        }
    }

    public func openRunThread(_ record: WorkerRecord) {
        guard !record.threadId.isEmpty else { return }
        onOpenThread?(record.threadId)
    }

    public func startLiveRefresh() {
        stopLiveRefresh()
        liveRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if Task.isCancelled { return }
                await self.refreshRunningRuns()
            }
        }
    }

    public func stopLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
    }

    private func refreshRunningRuns() async {
        guard runs.contains(where: \.isRunning) else { return }
        await loadRuns(silent: true)
        if let selected = selectedRun, selected.isRunning {
            await loadDetail(for: selected)
        }
    }

    private func replaceRun(_ updated: WorkerRecord) {
        guard let index = runs.firstIndex(where: { $0.id == updated.id }) else { return }
        runs[index] = updated
    }

    public static func filteredRuns(
        _ runs: [WorkerRecord],
        assistantId: String?,
        statusFilter: AssistantRunStatusFilter
    ) -> [WorkerRecord] {
        runs.filter { record in
            if let assistantId, record.assistantId != assistantId {
                return false
            }
            return statusFilter.matches(record)
        }
    }

    public static func sortedRuns(_ runs: [WorkerRecord]) -> [WorkerRecord] {
        runs.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning
            }
            return runSortKey(lhs) > runSortKey(rhs)
        }
    }

    public static func historyRuns(from runs: [WorkerRecord], assistantId: String?) -> [WorkerRecord] {
        let scoped: [WorkerRecord]
        if let assistantId {
            scoped = runs.filter { $0.assistantId == assistantId }
        } else {
            scoped = runs
        }
        return scoped
            .filter(\.isTerminal)
            .sorted { runEndKey($0) > runEndKey($1) }
    }

    public static func availableControls(for record: WorkerRecord, projectPath: String?, isOrphan: Bool = false) -> Set<AssistantRunControl> {
        var controls: Set<AssistantRunControl> = []
        let status = AssistantRunStatus.from(runtimeStatus: record.status)
        if !record.threadId.isEmpty {
            controls.insert(.openThread)
        }
        if status == .running {
            controls.insert(.cancel)
        }
        if (status == .failed || status == .cancelled) && !isOrphan {
            controls.insert(.retry)
        }
        if UUID(uuidString: record.threadId) != nil {
            controls.insert(.viewOutput)
            controls.insert(.reviewChanges)
        }
        if projectPath != nil {
            controls.insert(.openWorkspace)
        }
        return controls
    }

    public static func retryRequest(for record: WorkerRecord) -> WorkerSpawnRequest {
        WorkerSpawnRequest(
            name: record.name,
            task: record.task,
            targetFiles: record.targetFiles,
            assistantId: record.assistantId
        )
    }

    public static func assembleDetail(
        record: WorkerRecord,
        assistant: RemoteAssistant?,
        transcript: RemoteTranscript?,
        diff: RemoteDiff?,
        gitState: RemoteGitState?,
        project: RemoteProject?,
        knownThreadIDs: Set<String>?
    ) -> AssistantRunDetail {
        let startedAt = record.startedAt > 0 ? Date(timeIntervalSince1970: record.startedAt) : nil
        let endedAt = record.completedAt.map { Date(timeIntervalSince1970: $0) }
        let duration: TimeInterval?
        if let startedAt, let endedAt {
            duration = max(0, endedAt.timeIntervalSince(startedAt))
        } else if AssistantRunStatus.from(runtimeStatus: record.status) == .running {
            duration = record.elapsedSeconds
        } else {
            duration = nil
        }
        let items = transcript?.items ?? []
        var changedFiles: [RemoteChangedFile] = []
        if let turnChanges = transcript?.turnChanges {
            for files in turnChanges.values {
                for file in files where !changedFiles.contains(where: { $0.path == file.path }) {
                    changedFiles.append(file)
                }
            }
        }
        let modelName = transcript?.thread.selection.modelName
        return AssistantRunDetail(
            record: record,
            assistantName: assistant?.name,
            providerName: record.provider.isEmpty ? nil : record.provider,
            modelName: modelName.flatMap { $0.isEmpty ? nil : $0 },
            projectName: project?.name,
            projectPath: project?.path,
            branch: transcript?.thread.branch,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: duration,
            targetFiles: record.targetFiles,
            toolExecutions: items.filter { $0.kind == .tool },
            approvalItems: items.filter { $0.kind == .approval },
            pendingApprovals: transcript?.thread.pendingApprovals ?? 0,
            changedFiles: changedFiles,
            diff: diff,
            gitState: gitState,
            transcript: transcript,
            isOrphan: record.isOrphan(knownParentThreadIDs: knownThreadIDs)
        )
    }

    private static func runSortKey(_ record: WorkerRecord) -> Double {
        record.startedAt > 0 ? record.startedAt : record.createdAt
    }

    private static func runEndKey(_ record: WorkerRecord) -> Double {
        if let completedAt = record.completedAt {
            return completedAt
        }
        return runSortKey(record)
    }
}
