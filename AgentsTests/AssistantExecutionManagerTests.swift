import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Assistant Execution Manager: Resolve, Lifecycle, Isolation, Cancel & History")
struct AssistantExecutionManagerTests {

    private actor FakeAssistantRuntime: AssistantRuntime {
        let workerThreadID = UUID()
        var newThreadID = UUID()
        var newThreadCalls: [(projectID: UUID?, systemPrompt: String?, toolset: AgentToolset?, allowedTools: [String]?, assistantId: String?, selection: RemoteSelectionOverride?)] = []
        var sendCalls: [RemoteSendRequest] = []
        var transcript = Self.transcript(threadID: UUID(), items: [])
        var transcriptsByThread: [UUID: RemoteTranscript] = [:]
        var pollStatusValue = RuntimePollStatus()
        var stoppedThreads: [UUID] = []
        var respondCalls: [(thread: UUID, requestID: UUID, optionID: String, text: String?)] = []
        var spawnCalls: [(parentThreadId: String, workers: [WorkerSpawnRequest])] = []
        var spawnResult: JSONValue
        var workerStatusValue: WorkerRecord
        var workerResultValue: WorkerRecord
        var cancelledWorkers: [String] = []
        var workersByAssistant: [WorkerRecord] = []
        var workersByParent: [WorkerRecord] = []
        var diffValue = RemoteDiff(title: "Uncommitted changes", files: [])
        var gitStateValue = RemoteGitState(isRepository: true, branch: "main")
        var newThreadError: Error?
        var sendError: Error?

        init() {
            let threadID = workerThreadID
            spawnResult = .object(["workers": .array([.object(["id": .string("worker-1"), "threadId": .string(threadID.uuidString)])])])
            workerStatusValue = WorkerRecord(id: "worker-1", name: "Tidy Imports", parentThreadId: UUID().uuidString, threadId: threadID.uuidString, task: "Tidy the imports.", provider: "claude", targetFiles: [], status: "running", cancelRequested: false, transcriptStart: 0, transcriptItems: 0, elapsedSeconds: 0, createdAt: 1000, startedAt: 1000, completedAt: nil, error: nil, result: nil, progress: nil)
            workerResultValue = workerStatusValue
        }

        static func transcript(threadID: UUID, items: [RemoteItem], turn: RemoteTurnState = RemoteTurnState(), turnChanges: [String: [RemoteChangedFile]] = [:]) -> RemoteTranscript {
            RemoteTranscript(
                thread: RemoteThreadSummary(id: threadID, projectID: UUID(), title: "Test", selection: RemoteSelection(provider: "claude", modelID: "sonnet", modelName: "Sonnet")),
                items: items,
                turn: turn,
                turnChanges: turnChanges
            )
        }

        func setTranscript(_ value: RemoteTranscript) { transcript = value }
        func setTranscriptsByThread(_ value: [UUID: RemoteTranscript]) { transcriptsByThread = value }
        func setPollStatus(_ value: RuntimePollStatus) { pollStatusValue = value }
        func setWorkerStatus(_ value: WorkerRecord) { workerStatusValue = value }
        func setWorkerResult(_ value: WorkerRecord) { workerResultValue = value }
        func setWorkersByAssistant(_ value: [WorkerRecord]) { workersByAssistant = value }
        func setWorkersByParent(_ value: [WorkerRecord]) { workersByParent = value }
        func setNewThreadError(_ value: Error?) { newThreadError = value }
        func setSendError(_ value: Error?) { sendError = value }
        func setNewThreadID(_ value: UUID) { newThreadID = value }

        func newThread(projectID: UUID?, systemPrompt: String?, toolset: AgentToolset?, allowedTools: [String]?, assistantId: String?, selection: RemoteSelectionOverride?) async throws -> UUID {
            newThreadCalls.append((projectID, systemPrompt, toolset, allowedTools, assistantId, selection))
            if let newThreadError { throw newThreadError }
            return newThreadID
        }

        func send(_ request: RemoteSendRequest) async throws -> String {
            sendCalls.append(request)
            if let sendError { throw sendError }
            return "sent"
        }

        func openThread(_ threadID: UUID, limit: Int) async throws -> RemoteTranscript {
            transcriptsByThread[threadID] ?? transcript
        }

        func pollStatus() async throws -> RuntimePollStatus {
            pollStatusValue
        }

        func stop(thread: UUID) async throws {
            stoppedThreads.append(thread)
        }

        func respond(thread: UUID, requestID: UUID, optionID: String, text: String?) async throws {
            respondCalls.append((thread, requestID, optionID, text))
        }

        func spawnWorkers(parentThreadId: String, workers: [WorkerSpawnRequest]) async throws -> JSONValue {
            spawnCalls.append((parentThreadId, workers))
            return spawnResult
        }

        func listWorkers(parentThreadId: String?) async throws -> [WorkerRecord] {
            workersByParent
        }

        func listWorkers(assistantId: String) async throws -> [WorkerRecord] {
            workersByAssistant
        }

        func workerStatus(workerId: String) async throws -> WorkerRecord {
            workerStatusValue
        }

        func workerResult(workerId: String) async throws -> WorkerRecord {
            workerResultValue
        }

        func cancelWorker(workerId: String) async throws -> WorkerRecord {
            cancelledWorkers.append(workerId)
            var record = workerStatusValue
            record.status = "cancelled"
            return record
        }

        func fetchDiff(thread: UUID, scope: DiffScope) async throws -> RemoteDiff {
            diffValue
        }

        func fetchGitState(thread: UUID) async throws -> RemoteGitState {
            gitStateValue
        }
    }

    private static func definition(
        id: String = "builtin.code-maintenance.tidy-imports",
        name: String = "Tidy Imports",
        modelConfig: AssistantModelConfig = .specific(provider: "claude", model: "claude-sonnet-4"),
        allowedTools: [String]? = ["read_file"],
        permissionProfile: AssistantPermissionProfile = .workspaceModify,
        isBuiltIn: Bool = true
    ) -> AssistantDefinition {
        AssistantDefinition(
            id: id, name: name, description: "Tidies imports", category: .codeMaintenance, icon: "arrow.triangle.2.circlepath",
            systemPrompt: "Tidy the imports.", intendedTasks: ["Sort imports"], expectedOutputFormat: "A diff",
            allowedTools: allowedTools, modelConfig: modelConfig, permissionProfile: permissionProfile, version: 2,
            isBuiltIn: isBuiltIn)
    }

    private static func emptyAssetsManager() throws -> (SystemAssetManager, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-exec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (SystemAssetManager(directory: dir), dir)
    }

    private static func makeManager(
        runtime: FakeAssistantRuntime,
        catalog: AssistantCatalog,
        currentProvider: String? = nil,
        currentModel: String? = nil,
        maxConcurrentRuns: Int = 32,
        pollInterval: Duration = .seconds(60)
    ) throws -> (AssistantExecutionManager, URL) {
        let (assets, dir) = try emptyAssetsManager()
        let manager = AssistantExecutionManager(
            runtime: runtime, catalog: catalog, systemAssets: assets,
            currentProvider: currentProvider, currentModel: currentModel,
            maxConcurrentRuns: maxConcurrentRuns, pollInterval: pollInterval)
        return (manager, dir)
    }

    private static func customRecord(id: UUID) -> RemoteAssistant {
        RemoteAssistant(
            id: id, name: "Custom Tidy", category: .codeMaintenance, systemPrompt: "Tidy the imports.",
            allowedTools: ["read_file"], provider: "claude", model: "claude-sonnet-4",
            permissionProfile: .workspaceModify, source: .custom)
    }

    @Test("Resolve maps appDefault to no selection override")
    func resolveAppDefault() async throws {
        let runtime = FakeAssistantRuntime()
        let (assets, dir) = try Self.emptyAssetsManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = AssistantExecutionManager(
            runtime: runtime,
            catalog: AssistantCatalog(builtIns: [Self.definition(modelConfig: .appDefault)]),
            systemAssets: assets)
        let plan = try await manager.resolve(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        #expect(plan.selectionOverride == nil)
        #expect(plan.provider == nil)
        #expect(plan.model == nil)
    }

    @Test("Resolve maps specific provider and model to a full override")
    func resolveSpecific() async throws {
        let runtime = FakeAssistantRuntime()
        let (assets, dir) = try Self.emptyAssetsManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = AssistantExecutionManager(
            runtime: runtime,
            catalog: AssistantCatalog(builtIns: [Self.definition(modelConfig: .specific(provider: "claude", model: "claude-sonnet-4"))]),
            systemAssets: assets)
        let plan = try await manager.resolve(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        #expect(plan.selectionOverride == RemoteSelectionOverride(provider: "claude", modelID: "claude-sonnet-4"))
        #expect(plan.provider == "claude")
        #expect(plan.model == "claude-sonnet-4")
    }

    @Test("Resolve maps providerOnly to a provider-only override")
    func resolveProviderOnly() async throws {
        let runtime = FakeAssistantRuntime()
        let (assets, dir) = try Self.emptyAssetsManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = AssistantExecutionManager(
            runtime: runtime,
            catalog: AssistantCatalog(builtIns: [Self.definition(modelConfig: .providerOnly("codex"))]),
            systemAssets: assets)
        let plan = try await manager.resolve(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        #expect(plan.selectionOverride == RemoteSelectionOverride(provider: "codex", modelID: nil))
        #expect(plan.provider == "codex")
        #expect(plan.model == nil)
    }

    @Test("Resolve maps modelOnly to a model-only override")
    func resolveModelOnly() async throws {
        let runtime = FakeAssistantRuntime()
        let (assets, dir) = try Self.emptyAssetsManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = AssistantExecutionManager(
            runtime: runtime,
            catalog: AssistantCatalog(builtIns: [Self.definition(modelConfig: .modelOnly("gpt-5"))]),
            systemAssets: assets)
        let plan = try await manager.resolve(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        #expect(plan.selectionOverride == RemoteSelectionOverride(provider: nil, modelID: "gpt-5"))
        #expect(plan.provider == nil)
        #expect(plan.model == "gpt-5")
    }

    @Test("Resolve maps currentAppModel to the app selection, and to no override without one")
    func resolveCurrentAppModel() async throws {
        let runtime = FakeAssistantRuntime()
        let (assets, dir) = try Self.emptyAssetsManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let withApp = AssistantExecutionManager(
            runtime: runtime,
            catalog: AssistantCatalog(builtIns: [Self.definition(modelConfig: .currentAppModel)]),
            systemAssets: assets, currentProvider: "claude", currentModel: "claude-opus-4")
        let plan = try withApp.resolve(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        #expect(plan.selectionOverride == RemoteSelectionOverride(provider: "claude", modelID: "claude-opus-4"))
        let withoutApp = AssistantExecutionManager(
            runtime: runtime,
            catalog: AssistantCatalog(builtIns: [Self.definition(modelConfig: .currentAppModel)]),
            systemAssets: assets)
        let fallback = try await withoutApp.resolve(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        #expect(fallback.selectionOverride == nil)
    }

    @Test("Resolve always uses the system toolset and composes a prompt")
    func resolveToolsetAndPrompt() async throws {
        let runtime = FakeAssistantRuntime()
        let (assets, dir) = try Self.emptyAssetsManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = AssistantExecutionManager(
            runtime: runtime,
            catalog: AssistantCatalog(builtIns: [Self.definition()]),
            systemAssets: assets)
        let plan = try await manager.resolve(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        #expect(plan.allowedTools == ["read_file"])
        #expect(!plan.systemPrompt.text.isEmpty)
        #expect(plan.systemPrompt.isBaselineFallback)
    }

    @Test("Resolve rejects an unknown assistant")
    func resolveUnknownAssistant() async throws {
        let runtime = FakeAssistantRuntime()
        let (assets, dir) = try Self.emptyAssetsManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = AssistantExecutionManager(
            runtime: runtime,
            catalog: AssistantCatalog(builtIns: [Self.definition()]),
            systemAssets: assets)
        #expect(throws: AssistantRunError.unknownAssistant(id: "builtin.code-maintenance.nope")) {
            try await manager.resolve(assistantID: "builtin.code-maintenance.nope", task: "Do it.")
        }
    }

    @Test("Resolve rejects an empty task and an invalid definition")
    func resolveInvalidInputs() async throws {
        let runtime = FakeAssistantRuntime()
        let (assets, dir) = try Self.emptyAssetsManager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = AssistantExecutionManager(
            runtime: runtime,
            catalog: AssistantCatalog(builtIns: [Self.definition()]),
            systemAssets: assets)
        #expect(throws: AssistantRunError.emptyTask) {
            try await manager.resolve(assistantID: "builtin.code-maintenance.tidy-imports", task: "   ")
        }
        let badCatalog = AssistantCatalog(builtIns: [Self.definition(allowedTools: ["not_a_tool"])])
        let badManager = AssistantExecutionManager(runtime: runtime, catalog: badCatalog, systemAssets: assets)
        do {
            _ = try await badManager.resolve(assistantID: "builtin.code-maintenance.tidy-imports", task: "Do it.")
            Issue.record("Expected invalidDefinition for an unknown tool")
        } catch let error as AssistantRunError {
            if case .invalidDefinition(let id, let issues) = error {
                #expect(id == "builtin.code-maintenance.tidy-imports")
                #expect(issues.contains(.unknownTool(name: "not_a_tool")))
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("Foreground start creates a thread with the resolved config and sends the task")
    func foregroundStart() async throws {
        let runtime = FakeAssistantRuntime()
        let (manager, dir) = try Self.makeManager(runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]))
        defer { try? FileManager.default.removeItem(at: dir) }
        let runID = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        let run = await manager.run(id: runID)
        #expect(run?.status == .running)
        #expect(run?.toolset == .system)
        #expect(run?.allowedTools == ["read_file"])
        #expect(run?.provider == "claude")
        #expect(run?.model == "claude-sonnet-4")
        #expect(run?.permissionProfile == .workspaceModify)
        let calls = await runtime.newThreadCalls
        #expect(calls.count == 1)
        #expect(calls[0].toolset == .system)
        #expect(calls[0].allowedTools == ["read_file"])
        #expect(calls[0].selection == RemoteSelectionOverride(provider: "claude", modelID: "claude-sonnet-4"))
        #expect(calls[0].assistantId == Self.definition().persistenceID?.uuidString)
        #expect(calls[0].systemPrompt == run?.systemPromptText)
        let sends = await runtime.sendCalls
        #expect(sends.count == 1)
        #expect(sends[0].text == "Tidy the imports.")
        #expect(sends[0].allowedTools == ["read_file"])
        _ = await manager.cancel(runID: runID)
    }

    @Test("Background start spawns a worker with the assistant id only when the assistant is stored")
    func backgroundStartStoredAssistant() async throws {
        let runtime = FakeAssistantRuntime()
        let customID = UUID()
        let record = Self.customRecord(id: customID)
        let catalog = AssistantCatalog(builtIns: [], stored: [record])
        let definition = catalog.definition(forStableID: "custom.\(customID.uuidString.lowercased())")
        #expect(definition != nil)
        let (manager, dir) = try Self.makeManager(runtime: runtime, catalog: catalog)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runID = try await manager.start(
            assistantID: "custom.\(customID.uuidString.lowercased())",
            task: "Tidy the imports.", mode: .background)
        let run = await manager.run(id: runID)
        #expect(run?.mode == .background)
        #expect(run?.workerID == "worker-1")
        let workerThreadID = await runtime.workerThreadID
        #expect(run?.workerThreadID == workerThreadID)
        let spawns = await runtime.spawnCalls
        #expect(spawns.count == 1)
        #expect(spawns[0].workers.count == 1)
        #expect(spawns[0].workers[0].name == "Custom Tidy")
        #expect(spawns[0].workers[0].task == "Tidy the imports.")
        #expect(spawns[0].workers[0].assistantId == customID.uuidString)
        _ = await manager.cancel(runID: runID)
    }

    @Test("Background start omits the assistant id for a built-in with no stored record")
    func backgroundStartBuiltinOmitsAssistantID() async throws {
        let runtime = FakeAssistantRuntime()
        let (manager, dir) = try Self.makeManager(runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]))
        defer { try? FileManager.default.removeItem(at: dir) }
        let runID = try await manager.start(
            assistantID: "builtin.code-maintenance.tidy-imports",
            task: "Tidy the imports.", mode: .background)
        let spawns = await runtime.spawnCalls
        #expect(spawns.count == 1)
        #expect(spawns[0].workers[0].assistantId == nil)
        _ = await manager.cancel(runID: runID)
    }

    @Test("Background start rejects a task over the worker task limit and creates no run")
    func backgroundTaskLimit() async throws {
        let runtime = FakeAssistantRuntime()
        let (manager, dir) = try Self.makeManager(runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]))
        defer { try? FileManager.default.removeItem(at: dir) }
        let longTask = String(repeating: "x", count: 501)
        do {
            _ = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: longTask, mode: .background)
            Issue.record("Expected taskTooLong")
        } catch let error as AssistantRunError {
            #expect(error == .taskTooLong(limit: 500))
        }
        #expect(await manager.allRuns().isEmpty)
        #expect(await runtime.spawnCalls.isEmpty)
    }

    @Test("Foreground run completes from the turn outcome and the report carries real state")
    func foregroundCompletion() async throws {
        let runtime = FakeAssistantRuntime()
        let threadID = UUID()
        await runtime.setNewThreadID(threadID)
        let toolItem = RemoteItem(id: UUID(), index: 0, kind: .tool, text: "read_file", title: "Read imports.swift", category: "read", status: "completed")
        let assistantItem = RemoteItem(id: UUID(), index: 1, kind: .assistant, text: "Imports tidied.")
        let changed = RemoteChangedFile(path: "Sources/Imports.swift", status: "modified", additions: 3, deletions: 5)
        await runtime.setTranscript(FakeAssistantRuntime.transcript(
            threadID: threadID, items: [toolItem, assistantItem],
            turn: RemoteTurnState(isRunning: false),
            turnChanges: ["turn": [changed]]))
        await runtime.setPollStatus(RuntimePollStatus(turnResultsSerial: 1, turnResultsRecent: [TurnResultEntry(serial: 1, threadID: threadID.uuidString, outcome: "completed")]))
        let (manager, dir) = try Self.makeManager(
            runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]), pollInterval: .milliseconds(50))
        defer { try? FileManager.default.removeItem(at: dir) }
        let runID = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        try await Task.sleep(for: .milliseconds(400))
        let run = await manager.run(id: runID)
        #expect(run?.status == .completed)
        #expect(run?.output == "Imports tidied.")
        #expect(run?.toolExecutions.count == 1)
        #expect(run?.toolExecutions.first?.title == "Read imports.swift")
        #expect(run?.toolExecutions.first?.category == "read")
        #expect(run?.filesModified.map(\.path) == ["Sources/Imports.swift"])
        #expect(run?.gitSnapshot?.branch == "main")
        #expect(run?.duration != nil)
        let report = await manager.report(for: runID)
        #expect(report?.status == .completed)
        #expect(report?.durationSeconds != nil)
        #expect(report?.toolExecutions.count == 1)
        #expect(report?.filesModified.count == 1)
    }

    @Test("Turn outcomes map to failed and interrupted to cancelled")
    func turnOutcomeMapping() async throws {
        for (outcome, expected) in [("failed", AssistantRunStatus.failed), ("interrupted", AssistantRunStatus.cancelled)] {
            let runtime = FakeAssistantRuntime()
            let threadID = UUID()
            await runtime.setNewThreadID(threadID)
            await runtime.setTranscript(FakeAssistantRuntime.transcript(threadID: threadID, items: [], turn: RemoteTurnState(isRunning: false)))
            await runtime.setPollStatus(RuntimePollStatus(turnResultsSerial: 1, turnResultsRecent: [TurnResultEntry(serial: 1, threadID: threadID.uuidString, outcome: outcome)]))
            let (manager, dir) = try Self.makeManager(
                runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]), pollInterval: .milliseconds(50))
            defer { try? FileManager.default.removeItem(at: dir) }
            let runID = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
            try await Task.sleep(for: .milliseconds(400))
            #expect(await manager.run(id: runID)?.status == expected)
        }
    }

    @Test("Transcript error items land in the run errors")
    func transcriptErrorsRecorded() async throws {
        let runtime = FakeAssistantRuntime()
        let threadID = UUID()
        await runtime.setNewThreadID(threadID)
        let errorItem = RemoteItem(id: UUID(), index: 0, kind: .error, text: "Build failed")
        await runtime.setTranscript(FakeAssistantRuntime.transcript(threadID: threadID, items: [errorItem], turn: RemoteTurnState(isRunning: true)))
        let (manager, dir) = try Self.makeManager(
            runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]), pollInterval: .milliseconds(50))
        defer { try? FileManager.default.removeItem(at: dir) }
        let runID = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        try await Task.sleep(for: .milliseconds(300))
        #expect(await manager.run(id: runID)?.errors == ["Build failed"])
        _ = await manager.cancel(runID: runID)
    }

    @Test("Approval items surface as awaiting approval and respond passes the option through")
    func approvalPassthrough() async throws {
        let runtime = FakeAssistantRuntime()
        let threadID = UUID()
        await runtime.setNewThreadID(threadID)
        let approvalID = UUID()
        let approvalItem = RemoteItem(
            id: approvalID, index: 0, kind: .approval, text: "Allow write?",
            approval: RemoteApproval(options: [RemoteApproval.Option(id: "allow-once", label: "Allow once", kind: "allowOnce")]))
        await runtime.setTranscript(FakeAssistantRuntime.transcript(threadID: threadID, items: [approvalItem], turn: RemoteTurnState(isRunning: false)))
        let (manager, dir) = try Self.makeManager(runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]))
        defer { try? FileManager.default.removeItem(at: dir) }
        let runID = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        let pending = await manager.pendingApprovals(runID: runID)
        #expect(pending.count == 1)
        #expect(pending[0].id == approvalID)
        #expect(pending[0].options.map(\.id) == ["allow-once"])
        #expect(await manager.run(id: runID)?.status == .awaitingApproval)
        let answered = try await manager.respondToApproval(runID: runID, itemID: approvalID, optionID: "allow-once")
        #expect(answered)
        let calls = await runtime.respondCalls
        #expect(calls.count == 1)
        #expect(calls[0].thread == threadID)
        #expect(calls[0].requestID == approvalID)
        #expect(calls[0].optionID == "allow-once")
        _ = await manager.cancel(runID: runID)
    }

    @Test("Two runs share no state and cancelling one leaves the other running")
    func runIsolation() async throws {
        let runtime = FakeAssistantRuntime()
        let threadA = UUID()
        let threadB = UUID()
        let toolItem = RemoteItem(id: UUID(), index: 0, kind: .tool, text: "read_file", title: "Read A", status: "completed")
        await runtime.setTranscriptsByThread([
            threadA: FakeAssistantRuntime.transcript(threadID: threadA, items: [toolItem], turn: RemoteTurnState(isRunning: true)),
            threadB: FakeAssistantRuntime.transcript(threadID: threadB, items: [], turn: RemoteTurnState(isRunning: true)),
        ])
        let (manager, dir) = try Self.makeManager(
            runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]), pollInterval: .milliseconds(50))
        defer { try? FileManager.default.removeItem(at: dir) }
        await runtime.setNewThreadID(threadA)
        let runA = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Task A.")
        await runtime.setNewThreadID(threadB)
        let runB = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Task B.")
        try await Task.sleep(for: .milliseconds(300))
        #expect(await manager.run(id: runA)?.toolExecutions.count == 1)
        #expect(await manager.run(id: runB)?.toolExecutions.isEmpty == true)
        #expect(await manager.run(id: runA)?.task == "Task A.")
        #expect(await manager.run(id: runB)?.task == "Task B.")
        let outcome = await manager.cancel(runID: runA)
        if case .cancelled(let cancelled) = outcome {
            #expect(cancelled.id == runA)
        } else {
            Issue.record("Expected cancelled outcome, got \(outcome)")
        }
        #expect(await manager.run(id: runA)?.status == .cancelled)
        #expect(await manager.run(id: runB)?.status == .running)
        _ = await manager.cancel(runID: runB)
    }

    @Test("Foreground cancel stops the thread and marks the run cancelled")
    func foregroundCancel() async throws {
        let runtime = FakeAssistantRuntime()
        let threadID = UUID()
        await runtime.setNewThreadID(threadID)
        let (manager, dir) = try Self.makeManager(runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]))
        defer { try? FileManager.default.removeItem(at: dir) }
        let runID = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        let outcome = await manager.cancel(runID: runID, reason: "User stopped it")
        if case .cancelled(let run) = outcome {
            #expect(run.cancellationReason == "User stopped it")
            #expect(run.endedAt != nil)
        } else {
            Issue.record("Expected cancelled outcome, got \(outcome)")
        }
        #expect(await runtime.stoppedThreads == [threadID])
        #expect(await manager.run(id: runID)?.status == .cancelled)
        let again = await manager.cancel(runID: runID)
        if case .alreadyTerminal = again {
        } else {
            Issue.record("Expected alreadyTerminal on second cancel, got \(again)")
        }
        #expect(await manager.cancel(runID: UUID()) == .notFound)
    }

    @Test("Background cancel cancels the worker and stops its thread")
    func backgroundCancel() async throws {
        let runtime = FakeAssistantRuntime()
        let (manager, dir) = try Self.makeManager(runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]))
        defer { try? FileManager.default.removeItem(at: dir) }
        let runID = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.", mode: .background)
        let outcome = await manager.cancel(runID: runID)
        if case .cancelled = outcome {
        } else {
            Issue.record("Expected cancelled outcome, got \(outcome)")
        }
        #expect(await runtime.cancelledWorkers == ["worker-1"])
        let workerThreadID = await runtime.workerThreadID
        #expect(await runtime.stoppedThreads == [workerThreadID])
        #expect(await manager.run(id: runID)?.status == .cancelled)
    }

    @Test("Background run completes from the worker status and picks up the worker result")
    func backgroundCompletion() async throws {
        let runtime = FakeAssistantRuntime()
        var done = await runtime.workerStatusValue
        done.status = "completed"
        done.completedAt = 1010
        done.result = "Imports tidied by worker."
        await runtime.setWorkerStatus(done)
        await runtime.setWorkerResult(done)
        let workerThreadID = await runtime.workerThreadID
        await runtime.setTranscript(FakeAssistantRuntime.transcript(threadID: workerThreadID, items: [], turn: RemoteTurnState(isRunning: false)))
        let (manager, dir) = try Self.makeManager(
            runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]), pollInterval: .milliseconds(50))
        defer { try? FileManager.default.removeItem(at: dir) }
        let runID = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.", mode: .background)
        try await Task.sleep(for: .milliseconds(400))
        let run = await manager.run(id: runID)
        #expect(run?.status == .completed)
        #expect(run?.output == "Imports tidied by worker.")
        #expect(run?.duration != nil)
    }

    @Test("Concurrent run limit is enforced")
    func runLimit() async throws {
        let runtime = FakeAssistantRuntime()
        let (manager, dir) = try Self.makeManager(
            runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]), maxConcurrentRuns: 1)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Task one.")
        do {
            _ = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Task two.")
            Issue.record("Expected runLimitReached")
        } catch let error as AssistantRunError {
            #expect(error == .runLimitReached(limit: 1))
        }
        _ = await manager.cancel(runID: first)
        let second = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Task two.")
        #expect(await manager.run(id: second)?.status == .running)
        _ = await manager.cancel(runID: second)
    }

    @Test("Runtime failure during launch fails the run and rethrows")
    func launchFailure() async throws {
        struct LaunchFailure: Error {}
        let runtime = FakeAssistantRuntime()
        await runtime.setNewThreadError(LaunchFailure())
        let (manager, dir) = try Self.makeManager(runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]))
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
            Issue.record("Expected launch failure to throw")
        } catch is LaunchFailure {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let runs = await manager.allRuns()
        #expect(runs.count == 1)
        #expect(runs[0].status == .failed)
        #expect(runs[0].errors.count == 1)
    }

    @Test("Worker history maps runtime worker statuses and sorts newest first")
    func workerHistoryMapping() async throws {
        let runtime = FakeAssistantRuntime()
        let customID = UUID()
        let record = Self.customRecord(id: customID)
        let catalog = AssistantCatalog(builtIns: [], stored: [record])
        let assistantID = "custom.\(customID.uuidString.lowercased())"
        let parent = UUID().uuidString
        func worker(id: String, status: String, startedAt: Double, completedAt: Double? = nil, error: String? = nil, result: String? = nil) -> WorkerRecord {
            WorkerRecord(id: id, name: "W", parentThreadId: parent, threadId: UUID().uuidString, task: "Task \(id)", provider: "claude", targetFiles: [], status: status, cancelRequested: false, transcriptStart: 0, transcriptItems: 0, elapsedSeconds: 0, createdAt: startedAt, startedAt: startedAt, completedAt: completedAt, error: error, result: result, progress: nil, assistantId: customID.uuidString)
        }
        await runtime.setWorkersByAssistant([
            worker(id: "w-old", status: "completed", startedAt: 1000, completedAt: 1010, result: "Done."),
            worker(id: "w-mid", status: "failed", startedAt: 2000, completedAt: 2010, error: "Boom."),
            worker(id: "w-new", status: "running", startedAt: 3000),
        ])
        let (manager, dir) = try Self.makeManager(runtime: runtime, catalog: catalog)
        defer { try? FileManager.default.removeItem(at: dir) }
        let history = try await manager.workerHistory(forAssistantID: assistantID)
        #expect(history.map(\.workerID) == ["w-new", "w-mid", "w-old"])
        #expect(history.map(\.status) == [.running, .failed, .completed])
        #expect(history[1].errors == ["Boom."])
        #expect(history[2].output == "Done.")
        #expect(history[0].assistantID == assistantID)
        let unknown = try await manager.workerHistory(forAssistantID: "builtin.code-maintenance.nope")
        #expect(unknown.isEmpty)
        let builtinHistory = try await manager.workerHistory(forAssistantID: "builtin.code-maintenance.tidy-imports")
        #expect(builtinHistory.isEmpty)
    }

    @Test("Worker history by parent thread returns the runtime records")
    func workerHistoryByThread() async throws {
        let runtime = FakeAssistantRuntime()
        let parent = UUID()
        await runtime.setWorkersByParent([
            WorkerRecord(id: "w-1", name: "W", parentThreadId: parent.uuidString, threadId: UUID().uuidString, task: "T", provider: "claude", targetFiles: [], status: "completed", cancelRequested: false, transcriptStart: 0, transcriptItems: 0, elapsedSeconds: 0, createdAt: 1000, startedAt: 1000, completedAt: 1010, error: nil, result: "Done.", progress: nil),
        ])
        let (manager, dir) = try Self.makeManager(runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]))
        defer { try? FileManager.default.removeItem(at: dir) }
        let history = try await manager.workerHistory(forThreadID: parent)
        #expect(history.map(\.id) == ["w-1"])
        #expect(history[0].isTerminal)
    }

    @Test("Run status maps only from statuses the runtime produces")
    func runStatusMapping() {
        #expect(AssistantRunStatus(workerStatus: "running") == .running)
        #expect(AssistantRunStatus(workerStatus: "completed") == .completed)
        #expect(AssistantRunStatus(workerStatus: "failed") == .failed)
        #expect(AssistantRunStatus(workerStatus: "cancelled") == .cancelled)
        #expect(AssistantRunStatus(turnOutcome: "completed") == .completed)
        #expect(AssistantRunStatus(turnOutcome: "failed") == .failed)
        #expect(AssistantRunStatus(turnOutcome: "interrupted") == .cancelled)
        #expect(AssistantRunStatus(unseen: "completed") == .completed)
        #expect(AssistantRunStatus(unseen: "failed") == .failed)
    }

    @Test("Runs persist to disk and reload on a new manager")
    func persistenceRoundTrip() async throws {
        let runtime = FakeAssistantRuntime()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-exec-persist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("runs.json")
        let (assets, assetsDir) = try Self.emptyAssetsManager()
        defer { try? FileManager.default.removeItem(at: assetsDir) }
        let first = AssistantExecutionManager(runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]), systemAssets: assets, persistenceURL: url)
        let runID = try await first.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        _ = await first.cancel(runID: runID)
        let second = AssistantExecutionManager(runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]), systemAssets: assets, persistenceURL: url)
        let reloaded = await second.run(id: runID)
        #expect(reloaded?.status == .cancelled)
        #expect(reloaded?.task == "Tidy the imports.")
    }

    @Test("Event stream delivers start and completion for a foreground run")
    func eventStream() async throws {
        let runtime = FakeAssistantRuntime()
        let threadID = UUID()
        await runtime.setNewThreadID(threadID)
        await runtime.setTranscript(FakeAssistantRuntime.transcript(threadID: threadID, items: [], turn: RemoteTurnState(isRunning: false)))
        await runtime.setPollStatus(RuntimePollStatus(turnResultsSerial: 1, turnResultsRecent: [TurnResultEntry(serial: 1, threadID: threadID.uuidString, outcome: "completed")]))
        let (manager, dir) = try Self.makeManager(
            runtime: runtime, catalog: AssistantCatalog(builtIns: [Self.definition()]), pollInterval: .milliseconds(50))
        defer { try? FileManager.default.removeItem(at: dir) }
        let runID = try await manager.start(assistantID: "builtin.code-maintenance.tidy-imports", task: "Tidy the imports.")
        var sawCompleted = false
        for await event in await manager.events(for: runID) {
            if case .completed(let report) = event {
                #expect(report.runID == runID)
                #expect(report.status == .completed)
                sawCompleted = true
            }
        }
        #expect(sawCompleted)
    }
}
