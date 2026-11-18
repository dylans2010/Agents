import CoincideRemoteKit
import Foundation

public protocol AssistantRuntime: Sendable {
    func newThread(projectID: UUID?, systemPrompt: String?, toolset: AgentToolset?, allowedTools: [String]?, assistantId: String?, selection: RemoteSelectionOverride?) async throws -> UUID
    func send(_ request: RemoteSendRequest) async throws -> String
    func openThread(_ threadID: UUID, limit: Int) async throws -> RemoteTranscript
    func pollStatus() async throws -> RuntimePollStatus
    func stop(thread: UUID) async throws
    func respond(thread: UUID, requestID: UUID, optionID: String, text: String?) async throws
    func spawnWorkers(parentThreadId: String, workers: [WorkerSpawnRequest]) async throws -> JSONValue
    func listWorkers(parentThreadId: String?) async throws -> [WorkerRecord]
    func listWorkers(assistantId: String) async throws -> [WorkerRecord]
    func workerStatus(workerId: String) async throws -> WorkerRecord
    func workerResult(workerId: String) async throws -> WorkerRecord
    func cancelWorker(workerId: String) async throws -> WorkerRecord
    func fetchDiff(thread: UUID, scope: DiffScope) async throws -> RemoteDiff
    func fetchGitState(thread: UUID) async throws -> RemoteGitState
}

extension AgentsRuntimeClient: AssistantRuntime {
}

public struct AssistantRunPlan: Sendable {
    public var definition: AssistantDefinition
    public var task: String
    public var inputs: [String: String]
    public var projectID: UUID?
    public var provider: String?
    public var model: String?
    public var selectionOverride: RemoteSelectionOverride?
    public var allowedTools: [String]?
    public var systemPrompt: SystemPrompt
    public var spawnAssistantID: String?

    public init(definition: AssistantDefinition, task: String, inputs: [String: String], projectID: UUID?, provider: String?, model: String?, selectionOverride: RemoteSelectionOverride?, allowedTools: [String]?, systemPrompt: SystemPrompt, spawnAssistantID: String?) {
        self.definition = definition
        self.task = task
        self.inputs = inputs
        self.projectID = projectID
        self.provider = provider
        self.model = model
        self.selectionOverride = selectionOverride
        self.allowedTools = allowedTools
        self.systemPrompt = systemPrompt
        self.spawnAssistantID = spawnAssistantID
    }
}

public enum AssistantRunCancelOutcome: Sendable, Equatable {
    case cancelled(AssistantRun)
    case alreadyTerminal(AssistantRun)
    case notFound
    case failed(AssistantRunError)
}

public actor AssistantExecutionManager {
    public static let maxWorkerTaskCharacters = 500
    public static let maxWorkerNameCharacters = 128
    public static let defaultMaxConcurrentRuns = 32

    private let runtime: AssistantRuntime
    private let catalog: AssistantCatalog
    private let systemAssets: SystemAssetManager
    private let currentProvider: String?
    private let currentModel: String?
    private let maxConcurrentRuns: Int
    private let pollInterval: Duration
    private let persistenceURL: URL?

    private var runs: [UUID: AssistantRun] = [:]
    private var pollTasks: [UUID: Task<Void, Never>] = [:]
    private var subscribers: [UUID: [UUID: EventSubscriber]] = [:]

    private final class EventSubscriber: @unchecked Sendable {
        let continuation: AsyncStream<AssistantRunEvent>.Continuation

        init(_ continuation: AsyncStream<AssistantRunEvent>.Continuation) {
            self.continuation = continuation
        }
    }

    public init(
        runtime: AssistantRuntime,
        catalog: AssistantCatalog,
        systemAssets: SystemAssetManager = .shared,
        currentProvider: String? = nil,
        currentModel: String? = nil,
        maxConcurrentRuns: Int = defaultMaxConcurrentRuns,
        pollInterval: Duration = .milliseconds(500),
        persistenceURL: URL? = nil
    ) {
        self.runtime = runtime
        self.catalog = catalog
        self.systemAssets = systemAssets
        self.currentProvider = currentProvider
        self.currentModel = currentModel
        self.maxConcurrentRuns = maxConcurrentRuns
        self.pollInterval = pollInterval
        self.persistenceURL = persistenceURL
        loadPersisted()
    }

    public func resolve(assistantID: String, task: String, inputs: [String: String] = [:], projectID: UUID? = nil) throws -> AssistantRunPlan {
        guard let definition = catalog.definition(forStableID: assistantID) else {
            throw AssistantRunError.unknownAssistant(id: assistantID)
        }
        let issues = definition.validationIssues()
        guard issues.isEmpty else {
            throw AssistantRunError.invalidDefinition(id: assistantID, issues: issues)
        }
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AssistantRunError.emptyTask
        }
        let resolvedConfig = definition.modelConfig.resolvingCurrent(provider: currentProvider, model: currentModel)
        let descriptor = AssistantPromptDescriptor(
            id: definition.persistenceID?.uuidString ?? definition.id,
            name: definition.name,
            systemPrompt: definition.systemPrompt,
            description: definition.description
        )
        let prompt = systemAssets.systemPrompt(for: trimmed, provider: resolvedConfig.provider, model: resolvedConfig.model, assistant: descriptor)
        return AssistantRunPlan(
            definition: definition,
            task: trimmed,
            inputs: inputs,
            projectID: projectID,
            provider: resolvedConfig.provider,
            model: resolvedConfig.model,
            selectionOverride: resolvedConfig.selectionOverride,
            allowedTools: definition.allowedTools,
            systemPrompt: prompt,
            spawnAssistantID: spawnAssistantID(for: definition)
        )
    }

    public func start(assistantID: String, task: String, inputs: [String: String] = [:], projectID: UUID? = nil, mode: AssistantRunMode = .foreground, targetFiles: [String] = []) async throws -> UUID {
        let activeCount = runs.values.filter { !$0.isTerminal }.count
        guard activeCount < maxConcurrentRuns else {
            throw AssistantRunError.runLimitReached(limit: maxConcurrentRuns)
        }
        let plan = try resolve(assistantID: assistantID, task: task, inputs: inputs, projectID: projectID)
        if mode == .background {
            guard plan.task.unicodeScalars.count <= Self.maxWorkerTaskCharacters else {
                throw AssistantRunError.taskTooLong(limit: Self.maxWorkerTaskCharacters)
            }
            guard plan.definition.name.unicodeScalars.count <= Self.maxWorkerNameCharacters else {
                throw AssistantRunError.workerNameTooLong(limit: Self.maxWorkerNameCharacters)
            }
        }
        var run = AssistantRun(
            assistantID: plan.definition.id,
            assistantName: plan.definition.name,
            mode: mode,
            task: plan.task,
            inputs: inputs,
            projectID: plan.projectID,
            provider: plan.provider,
            model: plan.model,
            toolset: .system,
            allowedTools: plan.allowedTools,
            permissionProfile: plan.definition.permissionProfile,
            systemPromptText: plan.systemPrompt.text,
            systemPromptIncludedDocuments: plan.systemPrompt.includedDocumentIDs,
            systemPromptOmittedDocuments: plan.systemPrompt.omittedDocumentIDs,
            systemPromptEstimatedTokens: plan.systemPrompt.estimatedTokens,
            systemPromptIsBaselineFallback: plan.systemPrompt.isBaselineFallback
        )
        runs[run.id] = run
        emit(.started(run), for: run.id)
        do {
            let threadID = try await runtime.newThread(
                projectID: plan.projectID,
                systemPrompt: plan.systemPrompt.text,
                toolset: .system,
                allowedTools: plan.allowedTools,
                assistantId: plan.definition.persistenceID?.uuidString,
                selection: plan.selectionOverride
            )
            run.threadID = threadID
            run.status = .running
            runs[run.id] = run
            switch mode {
            case .foreground:
                _ = try await runtime.send(RemoteSendRequest(threadID: threadID, text: plan.task, systemPrompt: plan.systemPrompt.text, allowedTools: plan.allowedTools))
            case .background:
                let request = WorkerSpawnRequest(name: plan.definition.name, task: plan.task, targetFiles: targetFiles, assistantId: plan.spawnAssistantID)
                let result = try await runtime.spawnWorkers(parentThreadId: threadID.uuidString, workers: [request])
                let spawned = result["workers"]?.arrayValue?.first
                guard let workerID = spawned?["id"]?.stringValue, !workerID.isEmpty else {
                    throw AssistantRunError.workerSpawnFailed(message: "Runtime returned no worker id")
                }
                run.workerID = workerID
                run.workerName = plan.definition.name
                if let workerThread = spawned?["threadId"]?.stringValue {
                    run.workerThreadID = UUID(uuidString: workerThread)
                }
                runs[run.id] = run
            }
            persist()
            let runID = run.id
            pollTasks[runID] = Task { await self.pollLoop(runID: runID) }
            return runID
        } catch {
            run.status = .failed
            run.endedAt = Date()
            run.errors.append(error.localizedDescription)
            runs[run.id] = run
            persist()
            emit(.failed(AssistantRunReport(run: run), .runtimeFailure(message: error.localizedDescription)), for: run.id)
            finishSubscribers(for: run.id)
            throw error
        }
    }

    public func run(id: UUID) -> AssistantRun? {
        runs[id]
    }

    public func allRuns() -> [AssistantRun] {
        runs.values.sorted { $0.startedAt > $1.startedAt }
    }

    public func runs(forAssistantID assistantID: String) -> [AssistantRun] {
        runs.values.filter { $0.assistantID == assistantID }.sorted { $0.startedAt > $1.startedAt }
    }

    public func report(for runID: UUID) -> AssistantRunReport? {
        runs[runID].map(AssistantRunReport.init)
    }

    public func activeRunCount() -> Int {
        runs.values.filter { !$0.isTerminal }.count
    }

    public func workerHistory(forAssistantID assistantID: String) async throws -> [AssistantRun] {
        guard let definition = catalog.definition(forStableID: assistantID),
              let persistenceID = definition.persistenceID else {
            return []
        }
        let records: [WorkerRecord]
        do {
            records = try await runtime.listWorkers(assistantId: persistenceID.uuidString)
        } catch {
            throw AssistantRunError.runtimeFailure(message: error.localizedDescription)
        }
        return records.map { AssistantRun(worker: $0, assistant: definition) }.sorted { $0.startedAt > $1.startedAt }
    }

    public func workerHistory(forThreadID threadID: UUID) async throws -> [WorkerRecord] {
        do {
            return try await runtime.listWorkers(parentThreadId: threadID.uuidString)
        } catch {
            throw AssistantRunError.runtimeFailure(message: error.localizedDescription)
        }
    }

    public func pendingApprovals(runID: UUID) async -> [AssistantApproval] {
        _ = await refresh(runID: runID)
        return runs[runID]?.pendingApprovals ?? []
    }

    public func respondToApproval(runID: UUID, itemID: UUID, optionID: String, text: String? = nil) async throws -> Bool {
        guard let run = runs[runID] else {
            throw AssistantRunError.runNotFound(id: runID)
        }
        guard let threadID = run.observedThreadID else {
            throw AssistantRunError.cancellationUnsupported(reason: "Run has no thread yet")
        }
        do {
            try await runtime.respond(thread: threadID, requestID: itemID, optionID: optionID, text: text)
        } catch {
            throw AssistantRunError.runtimeFailure(message: error.localizedDescription)
        }
        _ = await refresh(runID: runID)
        return true
    }

    public func cancel(runID: UUID, reason: String? = nil) async -> AssistantRunCancelOutcome {
        guard var run = runs[runID] else {
            return .notFound
        }
        if run.isTerminal {
            return .alreadyTerminal(run)
        }
        pollTasks[runID]?.cancel()
        pollTasks[runID] = nil
        guard let threadID = run.threadID else {
            run.status = .cancelled
            run.endedAt = Date()
            run.cancellationReason = reason ?? "Cancelled before launch"
            runs[runID] = run
            persist()
            emit(.cancelled(run), for: runID)
            finishSubscribers(for: runID)
            return .cancelled(run)
        }
        do {
            if run.mode == .background, let workerID = run.workerID {
                _ = try await runtime.cancelWorker(workerId: workerID)
                if let workerThreadID = run.workerThreadID {
                    try await runtime.stop(thread: workerThreadID)
                }
            } else {
                try await runtime.stop(thread: threadID)
            }
        } catch {
            _ = await refresh(runID: runID)
            if let current = runs[runID], !current.isTerminal {
                pollTasks[runID] = Task { await self.pollLoop(runID: runID) }
            }
            return .failed(.runtimeFailure(message: error.localizedDescription))
        }
        run.status = .cancelled
        run.endedAt = Date()
        run.cancellationReason = reason ?? "Cancelled"
        runs[runID] = run
        persist()
        emit(.cancelled(run), for: runID)
        finishSubscribers(for: runID)
        return .cancelled(run)
    }

    public func events(for runID: UUID) -> AsyncStream<AssistantRunEvent> {
        AsyncStream { continuation in
            let subscriberID = UUID()
            Task { await self.addSubscriber(EventSubscriber(continuation), id: subscriberID, for: runID) }
            continuation.onTermination = { _ in
                Task { await self.removeSubscriber(id: subscriberID, for: runID) }
            }
        }
    }

    private func spawnAssistantID(for definition: AssistantDefinition) -> String? {
        guard let persistenceID = definition.persistenceID else {
            return nil
        }
        guard catalog.stored.contains(where: { $0.id == persistenceID }) else {
            return nil
        }
        return persistenceID.uuidString
    }

    private func pollLoop(runID: UUID) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            guard !Task.isCancelled else { return }
            guard runs[runID] != nil else { return }
            if await refresh(runID: runID) { return }
        }
    }

    private func refresh(runID: UUID) async -> Bool {
        guard var run = runs[runID], !run.isTerminal else {
            return runs[runID]?.isTerminal ?? true
        }
        guard let observedThreadID = run.observedThreadID else {
            return false
        }
        do {
            let transcript = try await runtime.openThread(observedThreadID, limit: 200)
            let newItems = transcript.items.filter { $0.index > run.seenItemIndex }.sorted { $0.index < $1.index }
            for item in newItems {
                run.seenItemIndex = max(run.seenItemIndex, item.index)
                switch item.kind {
                case .tool:
                    let execution = AssistantToolExecution(item: item)
                    run.recordActivity(item.title ?? item.text)
                    runs[runID] = run
                    emit(.toolCall(run, execution), for: runID)
                case .approval:
                    let approval = AssistantApproval(item: item)
                    if approval.isPending {
                        run.status = .awaitingApproval
                        run.recordActivity("Approval requested")
                        runs[runID] = run
                        emit(.approvalNeeded(run, approval), for: runID)
                    }
                case .assistant:
                    if !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        run.output = item.text
                        runs[runID] = run
                        emit(.output(run, item.text), for: runID)
                    }
                case .error:
                    run.errors.append(item.text)
                    run.recordActivity(item.text)
                default:
                    if !item.text.isEmpty {
                        run.recordActivity(item.text)
                    }
                }
            }
            var executions: [UUID: AssistantToolExecution] = [:]
            for existing in run.toolExecutions {
                executions[existing.id] = existing
            }
            for item in transcript.items where item.kind == .tool {
                executions[item.id] = AssistantToolExecution(item: item)
            }
            run.toolExecutions = executions.values.sorted { $0.startedAt < $1.startedAt }
            var approvalsByID: [UUID: AssistantApproval] = [:]
            for existing in run.approvals {
                approvalsByID[existing.id] = existing
            }
            for item in transcript.items where item.kind == .approval {
                approvalsByID[item.id] = AssistantApproval(item: item)
            }
            run.approvals = approvalsByID.values.sorted { $0.createdAt < $1.createdAt }
            if run.status == .awaitingApproval && run.pendingApprovals.isEmpty && transcript.thread.pendingApprovals == 0 {
                run.status = .running
            }
            var changed: [String: RemoteChangedFile] = [:]
            for files in transcript.turnChanges.values {
                for file in files {
                    changed[file.path] = file
                }
            }
            run.filesModified = changed.values.sorted { $0.path < $1.path }
            if transcript.turn.isRunning || transcript.turn.isStarting {
                if run.status != .awaitingApproval {
                    run.status = .running
                }
            } else if transcript.thread.pendingApprovals > 0 {
                run.status = .awaitingApproval
            }
            if run.mode == .background, let workerID = run.workerID {
                if let record = try? await runtime.workerStatus(workerId: workerID) {
                    run.lastActivity = record.progress?.stage ?? run.lastActivity
                    if let error = record.error, !run.errors.contains(error) {
                        run.errors.append(error)
                    }
                    if record.isTerminal {
                        if run.output == nil || run.output?.isEmpty == true {
                            if let result = try? await runtime.workerResult(workerId: workerID) {
                                run.output = result.result ?? run.output
                            }
                        }
                        runs[runID] = run
                        await finish(runID: runID, status: AssistantRunStatus(workerStatus: record.status), outcome: record.status)
                        return true
                    }
                }
            } else {
                do {
                    let status = try await runtime.pollStatus()
                    let (entries, watermark) = status.newlyFinishedTurns(since: run.lastTurnSerial)
                    run.lastTurnSerial = watermark
                    if let entry = entries.first(where: { $0.threadID == observedThreadID.uuidString }) {
                        runs[runID] = run
                        await finish(runID: runID, status: AssistantRunStatus(turnOutcome: entry.outcome), outcome: entry.outcome)
                        return true
                    }
                } catch {
                    if run.errors.last != error.localizedDescription {
                        run.errors.append(error.localizedDescription)
                    }
                }
                if let unseen = transcript.thread.unseen, !unseen.isEmpty {
                    runs[runID] = run
                    await finish(runID: runID, status: AssistantRunStatus(unseen: unseen), outcome: unseen)
                    return true
                }
            }
            runs[runID] = run
            return false
        } catch {
            if run.errors.last != error.localizedDescription {
                run.errors.append(error.localizedDescription)
            }
            runs[runID] = run
            return false
        }
    }

    private func finish(runID: UUID, status: AssistantRunStatus, outcome: String? = nil) async {
        guard var run = runs[runID], !run.isTerminal else {
            return
        }
        if status.isTerminal {
            run.status = status
        } else {
            run.status = .failed
            run.errors.append("Unknown run outcome '\(outcome ?? status.rawValue)'")
        }
        run.endedAt = Date()
        if let threadID = run.threadID {
            if let diff = try? await runtime.fetchDiff(thread: threadID, scope: .uncommitted),
               let gitState = try? await runtime.fetchGitState(thread: threadID) {
                run.gitSnapshot = AssistantGitSnapshot(gitState: gitState, diff: diff)
            }
        }
        runs[runID] = run
        pollTasks[runID]?.cancel()
        pollTasks[runID] = nil
        persist()
        let report = AssistantRunReport(run: run)
        switch run.status {
        case .completed:
            emit(.completed(report), for: runID)
        case .failed:
            emit(.failed(report, .runtimeFailure(message: run.errors.last ?? "Turn failed")), for: runID)
        case .cancelled:
            emit(.cancelled(run), for: runID)
        default:
            break
        }
        finishSubscribers(for: runID)
    }

    private func emit(_ event: AssistantRunEvent, for runID: UUID) {
        guard let subs = subscribers[runID] else {
            return
        }
        for sub in subs.values {
            sub.continuation.yield(event)
        }
    }

    private func addSubscriber(_ subscriber: EventSubscriber, id: UUID, for runID: UUID) {
        subscribers[runID, default: [:]][id] = subscriber
        guard let run = runs[runID], run.isTerminal else {
            return
        }
        let report = AssistantRunReport(run: run)
        switch run.status {
        case .completed:
            subscriber.continuation.yield(.completed(report))
        case .failed:
            subscriber.continuation.yield(.failed(report, .runtimeFailure(message: run.errors.last ?? "Turn failed")))
        case .cancelled:
            subscriber.continuation.yield(.cancelled(run))
        default:
            break
        }
        subscriber.continuation.finish()
        subscribers[runID]?.removeValue(forKey: id)
    }

    private func removeSubscriber(id: UUID, for runID: UUID) {
        subscribers[runID]?.removeValue(forKey: id)
        if subscribers[runID]?.isEmpty == true {
            subscribers.removeValue(forKey: runID)
        }
    }

    private func finishSubscribers(for runID: UUID) {
        guard let subs = subscribers.removeValue(forKey: runID) else {
            return
        }
        for sub in subs.values {
            sub.continuation.finish()
        }
    }

    private func persist() {
        guard let persistenceURL else {
            return
        }
        let records = runs.values.sorted { $0.startedAt < $1.startedAt }
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func loadPersisted() {
        guard let persistenceURL,
              let data = try? Data(contentsOf: persistenceURL),
              let records = try? JSONDecoder().decode([AssistantRun].self, from: data) else {
            return
        }
        for record in records {
            runs[record.id] = record
        }
    }
}
