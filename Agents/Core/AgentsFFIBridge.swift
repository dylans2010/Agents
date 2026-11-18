internal import AgentsMacOSFFI
import CoincideRemoteKit
import Foundation

// MARK: - Runtime Bridge Errors

public nonisolated enum AgentsRuntimeError: LocalizedError, Sendable {
    case openFailed(String)
    case runtimeClosed
    case invalidJSON(String)
    case remoteFailure(RemoteError)
    case desktopFailure(String)
    case unexpectedResult(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg):
            "Failed to open Agents runtime: \(msg)"
        case .runtimeClosed:
            "Agents runtime is closed."
        case .invalidJSON(let detail):
            "Invalid runtime JSON payload: \(detail)"
        case .remoteFailure(let err):
            err.message
        case .desktopFailure(let msg):
            msg
        case .unexpectedResult(let expected, let actual):
            "Unexpected runtime result (expected \(expected), received \(actual))."
        }
    }
}

// MARK: - Thread-Safe Off-MainActor FFI Runtime Client

public nonisolated final class AgentsRuntimeClient: @unchecked Sendable {
    private let ffiQueue = DispatchQueue(
        label: "com.apoorvdarshan.coincide.runtime.ffi",
        qos: .userInitiated
    )
    private static let ffiQueueKey = DispatchSpecificKey<Void>()
    private let stateLock = NSLock()
    private nonisolated(unsafe) var runtimePtr: OpaquePointer?
    private nonisolated(unsafe) var lastUndoDeleteID: String?

    // MARK: - Early Process Bootstrap Helpers

    public static func adoptLoginShellPath() {
        coincide_macos_adopt_login_path()
    }

    public static func handoffIfRunning(dataDir: String? = nil) -> Bool {
        if let dataDir, !dataDir.isEmpty {
            return dataDir.withCString { cPath in
                coincide_macos_handoff_if_running(cPath)
            }
        }
        return coincide_macos_handoff_if_running(nil)
    }

    // MARK: - Lifecycle

    public init(dataDir: String? = nil, appVersion: String) throws {
        ffiQueue.setSpecific(key: Self.ffiQueueKey, value: ())
        var outError: UnsafeMutablePointer<CChar>? = nil
        let opened: OpaquePointer? = appVersion.withCString { cVersion in
            if let dataDir, !dataDir.isEmpty {
                return dataDir.withCString { cDir in
                    coincide_macos_open(cDir, cVersion, &outError)
                }
            } else {
                return coincide_macos_open(nil, cVersion, &outError)
            }
        }

        if let opened {
            if let outError {
                coincide_macos_string_free(outError)
            }
            self.runtimePtr = opened
        } else {
            let message = Self.consumeCString(outError) ?? "Unknown runtime initialization failure"
            throw AgentsRuntimeError.openFailed(message)
        }
    }

    deinit {
        closeSynchronously()
    }

    public var isOpen: Bool {
        stateLock.withLock { runtimePtr != nil }
    }

    public func close(timeout: Duration = .seconds(15)) async {
        await withCheckedContinuation { continuation in
            let gate = CloseResumeGate(continuation)
            ffiQueue.async { [self] in
                self.performCloseOnQueue()
                gate.resume()
            }
            Task {
                try? await Task.sleep(for: timeout)
                gate.resume()
            }
        }
    }

    private final class CloseResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        private let continuation: CheckedContinuation<Void, Never>

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func resume() {
            let shouldResume = lock.withLock {
                if resumed { return false }
                resumed = true
                return true
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    public func closeSynchronously() {
        let hasPtr = stateLock.withLock { runtimePtr != nil }
        guard hasPtr else { return }
        if DispatchQueue.getSpecific(key: Self.ffiQueueKey) != nil {
            performCloseOnQueue()
        } else {
            ffiQueue.sync {
                performCloseOnQueue()
            }
        }
    }

    private func performCloseOnQueue() {
        let ptr: OpaquePointer? = stateLock.withLock {
            defer { runtimePtr = nil }
            return runtimePtr
        }
        if let ptr {
            coincide_macos_close(ptr)
        }
    }

    // MARK: - Low-Level Off-MainActor Execution

    private static func consumeCString(_ ptr: UnsafeMutablePointer<CChar>?) -> String? {
        guard let ptr else { return nil }
        defer { coincide_macos_string_free(ptr) }
        return String(cString: ptr)
    }

    private func executeOnQueue<T: Sendable>(
        _ work: @escaping @Sendable (OpaquePointer) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            ffiQueue.async { [self] in
                let ptr = self.stateLock.withLock { self.runtimePtr }
                guard let ptr else {
                    continuation.resume(throwing: AgentsRuntimeError.runtimeClosed)
                    return
                }
                do {
                    let value = try work(ptr)
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func makeDesktopDecoder() -> JSONDecoder {
        RemoteProtocol.makeDecoder()
    }

    private static func makeDesktopEncoder() -> JSONEncoder {
        RemoteProtocol.makeEncoder()
    }

    // MARK: - Status Poll

    public func pollStatus() async throws -> RuntimePollStatus {
        try await executeOnQueue { ptr in
            guard let raw = Self.consumeCString(coincide_macos_poll_status(ptr)),
                  let data = raw.data(using: .utf8)
            else {
                throw AgentsRuntimeError.invalidJSON("Empty pollStatus payload")
            }
            let decoder = Self.makeDesktopDecoder()
            if let envelope = try? decoder.decode([String: JSONValue].self, from: data),
               envelope["ok"]?.boolValue == false,
               let errorText = envelope["error"]?.stringValue
            {
                throw AgentsRuntimeError.desktopFailure(errorText)
            }
            return try decoder.decode(RuntimePollStatus.self, from: data)
        }
    }

    // MARK: - Generic Adapter & Desktop Dispatchers

    private struct RawAdapterEnvelope: Decodable {
        var ok: Bool?
        var type: String?
        var body: JSONValue?
        var error: RemoteError?
    }

    private struct SyntheticServerResponse: Encodable {
        var v: Int = RemoteProtocol.version
        var kind: String = "response"
        var re: String = "local"
        var type: String
        var body: JSONValue?
    }

    public func adapterCall(_ request: RemoteRequest) async throws -> RemoteResult {
        try await executeOnQueue { ptr in
            let encoder = RemoteProtocol.makeEncoder()
            let decoder = RemoteProtocol.makeDecoder()
            let requestData = try encoder.encode(RemoteClientMessage(id: "local", request: request))
            guard let requestJSON = String(data: requestData, encoding: .utf8) else {
                throw AgentsRuntimeError.invalidJSON("Failed to UTF-8 encode RemoteClientMessage")
            }

            let rawReply: String? = requestJSON.withCString { cReq in
                Self.consumeCString(coincide_macos_adapter_call(ptr, cReq))
            }
            guard let rawReply, let replyData = rawReply.data(using: .utf8) else {
                throw AgentsRuntimeError.invalidJSON("Empty adapter response")
            }

            // `coincide_macos_adapter_call` returns `{"ok": true, "type": "...", "body": ...}`
            // or `{"ok": false, "error": {"code": "...", "message": "..."}}`.
            if let env = try? decoder.decode(RawAdapterEnvelope.self, from: replyData),
               let ok = env.ok
            {
                if !ok {
                    throw AgentsRuntimeError.remoteFailure(
                        env.error ?? RemoteError(.failed, "Adapter request failed.")
                    )
                }
                let resultType = env.type ?? "ok"
                if resultType == "ok" {
                    return .ok
                }
                let synthetic = SyntheticServerResponse(type: resultType, body: env.body)
                let syntheticData = try encoder.encode(synthetic)
                let message = try decoder.decode(RemoteServerMessage.self, from: syntheticData)
                switch message {
                case .response(_, let result):
                    return result
                case .failure(_, let err):
                    throw AgentsRuntimeError.remoteFailure(err)
                case .unknown(let kind):
                    throw AgentsRuntimeError.unexpectedResult(expected: request.name, actual: kind)
                case .event(let ev):
                    throw AgentsRuntimeError.unexpectedResult(expected: request.name, actual: "event(\(ev))")
                }
            }

            // Fallback if directly formatted as RemoteServerMessage
            let serverMsg = try decoder.decode(RemoteServerMessage.self, from: replyData)
            switch serverMsg {
            case .response(_, let result):
                return result
            case .failure(_, let err):
                throw AgentsRuntimeError.remoteFailure(err)
            case .unknown(let kind):
                throw AgentsRuntimeError.unexpectedResult(expected: request.name, actual: kind)
            case .event(let ev):
                throw AgentsRuntimeError.unexpectedResult(expected: request.name, actual: "event(\(ev))")
            }
        }
    }

    private struct RawDesktopEnvelope<Payload: Decodable>: Decodable {
        var ok: Bool
        var result: Payload?
        var error: JSONValue?
    }

    public func desktopCall<Response: Decodable & Sendable>(
        action: String,
        params: [String: JSONValue] = [:],
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        try await executeOnQueue { ptr in
            var payload = params
            payload["action"] = .string(action)
            let encoder = Self.makeDesktopEncoder()
            let decoder = Self.makeDesktopDecoder()
            let requestData = try encoder.encode(JSONValue.object(payload))
            guard let requestJSON = String(data: requestData, encoding: .utf8) else {
                throw AgentsRuntimeError.invalidJSON("Failed to UTF-8 encode desktop action")
            }

            let rawReply: String? = requestJSON.withCString { cAction in
                Self.consumeCString(coincide_macos_desktop_call(ptr, cAction))
            }
            guard let rawReply, let replyData = rawReply.data(using: .utf8) else {
                throw AgentsRuntimeError.invalidJSON("Empty desktop action response")
            }

            let envelope = try decoder.decode(RawDesktopEnvelope<JSONValue>.self, from: replyData)
            if !envelope.ok {
                let errMsg = envelope.error?.stringValue
                    ?? envelope.error?["message"]?.stringValue
                    ?? "Desktop operation '\(action)' failed."
                throw AgentsRuntimeError.desktopFailure(errMsg)
            }

            let resultJSON = envelope.result ?? .object([:])
            if Response.self == JSONValue.self, let casted = resultJSON as? Response {
                return casted
            }
            let resultBytes = try encoder.encode(resultJSON)
            return try decoder.decode(Response.self, from: resultBytes)
        }
    }

    // MARK: - CoincideRemoteKit Operations

    public func fetchWorkspace(includeArchived: Bool = false) async throws -> RemoteWorkspace {
        let res = try await adapterCall(.workspace(includeArchived: includeArchived))
        guard case .workspace(let ws) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "workspace", actual: "\(res)")
        }
        return ws
    }

    public func openThread(_ threadID: UUID, limit: Int = 200) async throws -> RemoteTranscript {
        let res = try await adapterCall(.openThread(threadID: threadID, limit: limit))
        guard case .transcript(let transcript) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "transcript", actual: "\(res)")
        }
        return transcript
    }

    public func closeThread(_ threadID: UUID) async throws {
        _ = try await adapterCall(.closeThread(threadID: threadID))
    }

    public func loadEarlier(thread: UUID, before: Int, limit: Int = 200) async throws -> RemoteItemPage {
        let res = try await adapterCall(.loadEarlier(threadID: thread, beforeIndex: before, limit: limit))
        guard case .items(let page) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "items", actual: "\(res)")
        }
        return page
    }

    public func markSeen(_ threadID: UUID) async throws {
        _ = try await adapterCall(.markSeen(threadID: threadID))
    }

    @discardableResult
    public func send(_ request: RemoteSendRequest) async throws -> String {
        let res = try await adapterCall(.send(request))
        if case .delivery(let status) = res {
            return status
        }
        return "sent"
    }

    public func steerQueued(thread: UUID, message: UUID) async throws {
        _ = try await adapterCall(.steerQueued(threadID: thread, messageID: message))
    }

    public func removeQueued(thread: UUID, message: UUID) async throws {
        _ = try await adapterCall(.removeQueued(threadID: thread, messageID: message))
    }

    public func stop(thread: UUID) async throws {
        _ = try await adapterCall(.stop(threadID: thread))
    }

    public func respond(
        thread: UUID,
        requestID: UUID,
        optionID: String,
        text: String? = nil
    ) async throws {
        _ = try await adapterCall(
            .respond(threadID: thread, itemID: requestID, optionID: optionID, text: text)
        )
    }

    public func answer(
        thread: UUID,
        requestID: UUID,
        answers: [String: [String]]
    ) async throws {
        _ = try await adapterCall(.answer(threadID: thread, itemID: requestID, answers: answers))
    }

    public func dismissQuestion(thread: UUID, requestID: UUID) async throws {
        _ = try await adapterCall(.dismissQuestion(threadID: thread, itemID: requestID))
    }

    public func updateThreadSettings(_ settings: RemoteThreadSettings) async throws {
        _ = try await adapterCall(.updateSettings(settings))
    }

    public func newThread(projectID: UUID? = nil, systemPrompt: String? = nil, toolset: AgentToolset? = nil, allowedTools: [String]? = nil, assistantId: String? = nil, selection: RemoteSelectionOverride? = nil) async throws -> UUID {
        let unknown = SystemToolRegistry.unknownToolNames(in: allowedTools)
        guard unknown.isEmpty else {
            throw AgentsRuntimeError.desktopFailure(
                "Unknown thread tools: \(unknown.joined(separator: ", ")). Threads can only allow tools from the system toolset."
            )
        }
        let res = try await adapterCall(.newThread(projectID: projectID, systemPrompt: systemPrompt, toolset: toolset?.rawValue, allowedTools: allowedTools, assistantId: assistantId, selection: selection))
        guard case .thread(let id) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "thread", actual: "\(res)")
        }
        return id
    }

    public func updateStoredPrompt(threadID: UUID, prompt: String, allowedTools: [String]? = nil) async throws {
        let unknown = SystemToolRegistry.unknownToolNames(in: allowedTools)
        guard unknown.isEmpty else {
            throw AgentsRuntimeError.desktopFailure(
                "Unknown thread tools: \(unknown.joined(separator: ", ")). Threads can only allow tools from the system toolset."
            )
        }
        let res = try await adapterCall(.updateStoredPrompt(threadID: threadID, systemPrompt: prompt, allowedTools: allowedTools))
        guard case .ok = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "ok", actual: "\(res)")
        }
    }

    public func performThreadAction(thread: UUID, action: RemoteThreadAction) async throws {
        _ = try await adapterCall(.threadAction(threadID: thread, action: action))
    }

    public func fetchDiff(thread: UUID, scope: DiffScope = .uncommitted) async throws -> RemoteDiff {
        let res = try await adapterCall(.diff(threadID: thread, turnID: scope.turnID))
        guard case .diff(let diff) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "diff", actual: "\(res)")
        }
        return diff
    }

    public func runScript(projectID: UUID? = nil, scriptID: UUID, threadID: UUID) async throws {
        _ = projectID
        _ = try await adapterCall(.runScript(threadID: threadID, scriptID: scriptID))
    }

    public func fetchUsageLimits() async throws -> [RemoteUsage] {
        let res = try await adapterCall(.usageLimits)
        guard case .usage(let limits) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "usage", actual: "\(res)")
        }
        return limits
    }

    public func newBotConversation(botID: UUID) async throws -> UUID {
        let res = try await adapterCall(.newBotConversation(botID: botID))
        guard case .thread(let id) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "thread", actual: "\(res)")
        }
        return id
    }

    @discardableResult
    public func saveBot(_ draft: RemoteBotDraft) async throws -> UUID {
        let res = try await adapterCall(.saveBot(draft))
        guard case .bot(let id) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "bot", actual: "\(res)")
        }
        return id
    }

    public func deleteBot(_ botID: UUID, deletesConversations: Bool = false) async throws {
        _ = try await adapterCall(.deleteBot(botID: botID, deletesConversations: deletesConversations))
    }

    public func listAssistants() async throws -> RemoteAssistants {
        let res = try await adapterCall(.assistants)
        guard case .assistants(let assistants) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "assistants", actual: "\(res)")
        }
        return assistants
    }

    @discardableResult
    public func saveAssistant(_ draft: RemoteAssistantDraft) async throws -> UUID {
        let res = try await adapterCall(.saveAssistant(draft))
        guard case .assistant(let id) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "assistant", actual: "\(res)")
        }
        return id
    }

    public func deleteAssistant(_ assistantID: UUID) async throws {
        _ = try await adapterCall(.deleteAssistant(assistantID: assistantID))
    }

    public func fetchSettings() async throws -> RemoteSettingsSnapshot {
        let res = try await adapterCall(.settings)
        guard case .settings(let snapshot) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "settings", actual: "\(res)")
        }
        return snapshot
    }

    @discardableResult
    public func changeSetting(id: String, value: RemoteSettingValue) async throws -> RemoteSettingsSnapshot {
        let res = try await adapterCall(.changeSetting(key: id, value: value))
        guard case .settings(let snapshot) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "settings", actual: "\(res)")
        }
        return snapshot
    }

    public func saveSettingsDocument(_ document: RemoteSettingsDocument) async throws -> RemoteSettingsDocument {
        let res = try await adapterCall(.saveSettingsDocument(document))
        guard case .settingsDocument(let saved) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "settingsDocument", actual: "\(res)")
        }
        return saved
    }

    public func setProjectExpanded(projectID: UUID, expanded: Bool) async throws {
        _ = try await adapterCall(.setProjectExpanded(projectID: projectID, expanded: expanded))
    }

    public func fetchMedia(
        thread: UUID,
        itemID: UUID,
        index: Int,
        full: Bool = false
    ) async throws -> RemoteMediaData {
        let res = try await adapterCall(.media(threadID: thread, itemID: itemID, index: index, full: full))
        guard case .media(let media) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "media", actual: "\(res)")
        }
        return media
    }

    /// Convenience overload accepting composite `"<itemUUID>:<index>"` `mediaID`.
    public func fetchMedia(thread: UUID, mediaID: String, full: Bool = false) async throws -> RemoteMediaData {
        let parts = mediaID.split(separator: ":", maxSplits: 1).map(String.init)
        guard let first = parts.first, let itemUUID = UUID(uuidString: first) else {
            throw AgentsRuntimeError.invalidJSON("mediaID must be formatted as '<itemUUID>:<index>'")
        }
        let idx = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return try await fetchMedia(thread: thread, itemID: itemUUID, index: idx, full: full)
    }

    public func fetchCompletions(
        thread: UUID,
        kind: String,
        query: String
    ) async throws -> [RemoteCompletion] {
        let trigger = kind == "file" ? "@" : (kind == "command" ? "/" : kind)
        let res = try await adapterCall(.completions(threadID: thread, trigger: trigger, query: query))
        guard case .completions(let list) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "completions", actual: "\(res)")
        }
        return list
    }

    public func fetchCheckout(thread: UUID) async throws -> RemoteCheckout {
        let res = try await adapterCall(.checkout(threadID: thread))
        guard case .checkout(let checkout) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "checkout", actual: "\(res)")
        }
        return checkout
    }

    public func changeCheckout(thread: UUID, action: RemoteCheckoutAction) async throws -> RemoteCheckout {
        let res = try await adapterCall(.changeCheckout(threadID: thread, action: action))
        guard case .checkout(let checkout) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "checkout", actual: "\(res)")
        }
        return checkout
    }

    public func forkThread(_ request: RemoteForkRequest) async throws -> UUID {
        let res = try await adapterCall(.forkThread(request))
        guard case .thread(let id) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "thread", actual: "\(res)")
        }
        return id
    }

    public func fetchRewindOptions(thread: UUID, itemID: UUID) async throws -> RemoteRewindOptions {
        let res = try await adapterCall(.rewindOptions(RemoteItemReference(threadID: thread, itemID: itemID)))
        guard case .rewindOptions(let options) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "rewindOptions", actual: "\(res)")
        }
        return options
    }

    public func rewind(_ request: RemoteRewindRequest) async throws -> RemoteRewind {
        let res = try await adapterCall(.rewind(request))
        guard case .rewind(let rw) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "rewind", actual: "\(res)")
        }
        return rw
    }

    public func fetchComposerNotice(thread: UUID) async throws -> RemoteComposerNotice {
        let res = try await adapterCall(.composerNotice(threadID: thread))
        guard case .composerNotice(let notice) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "composerNotice", actual: "\(res)")
        }
        return notice
    }

    public func performUsageWarningAction(_ command: RemoteUsageWarningCommand) async throws -> RemoteComposerNotice {
        let res = try await adapterCall(.usageWarningAction(command))
        guard case .composerNotice(let notice) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "composerNotice", actual: "\(res)")
        }
        return notice
    }

    public func setSidebarOptions(_ options: RemoteSidebarOptions) async throws {
        _ = try await adapterCall(.setSidebarOptions(options))
    }

    public func fetchProjectDefaults(projectID: UUID) async throws -> RemoteProjectDefaults {
        let res = try await adapterCall(.projectDefaults(projectID: projectID))
        guard case .projectDefaults(let defaults) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "projectDefaults", actual: "\(res)")
        }
        return defaults
    }

    @discardableResult
    public func saveProjectDefaults(_ defaults: RemoteProjectDefaults) async throws -> RemoteProjectDefaults {
        let res = try await adapterCall(.saveProjectDefaults(defaults))
        guard case .projectDefaults(let saved) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "projectDefaults", actual: "\(res)")
        }
        return saved
    }

    public func removeProject(projectID: UUID) async throws {
        _ = try await adapterCall(.removeProject(projectID: projectID))
    }

    public func fetchScheduledTasks() async throws -> RemoteScheduledTasks {
        let res = try await adapterCall(.scheduledTasks)
        guard case .scheduledTasks(let tasks) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "scheduledTasks", actual: "\(res)")
        }
        return tasks
    }

    @discardableResult
    public func saveScheduledTask(_ draft: RemoteScheduledTaskDraft) async throws -> RemoteScheduledTasks {
        let res = try await adapterCall(.saveScheduledTask(draft))
        guard case .scheduledTasks(let tasks) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "scheduledTasks", actual: "\(res)")
        }
        return tasks
    }

    @discardableResult
    public func performScheduledTaskAction(_ command: RemoteScheduledTaskCommand) async throws -> RemoteScheduledTasks {
        let res = try await adapterCall(.scheduledTaskAction(command))
        guard case .scheduledTasks(let tasks) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "scheduledTasks", actual: "\(res)")
        }
        return tasks
    }

    public func fetchGitState(thread: UUID) async throws -> RemoteGitState {
        let res = try await adapterCall(.gitState(threadID: thread))
        guard case .gitState(let state) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "gitState", actual: "\(res)")
        }
        return state
    }

    public func performGitAction(_ request: RemoteGitActionRequest) async throws -> RemoteGitActionResult {
        let res = try await adapterCall(.gitAction(request))
        guard case .gitAction(let outcome) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "gitAction", actual: "\(res)")
        }
        return outcome
    }

    public func fetchPullRequests(_ query: RemotePullRequestQuery) async throws -> RemotePullRequestList {
        let res = try await adapterCall(.pullRequests(query))
        guard case .pullRequests(let list) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "pullRequests", actual: "\(res)")
        }
        return list
    }

    public func fetchPullRequestDetail(projectID: UUID, number: Int) async throws -> RemotePullRequestDetail {
        let res = try await adapterCall(.pullRequest(RemotePullRequestReference(projectID: projectID, number: number)))
        guard case .pullRequest(let detail) = res else {
            throw AgentsRuntimeError.unexpectedResult(expected: "pullRequest", actual: "\(res)")
        }
        return detail
    }

    /// Overload resolving `projectID` from a `thread` UUID when the caller holds the thread ID.
    public func fetchPullRequestDetail(thread: UUID, number: Int) async throws -> RemotePullRequestDetail {
        let ws = try await fetchWorkspace(includeArchived: true)
        guard let summary = ws.threads.first(where: { $0.id == thread }) else {
            throw AgentsRuntimeError.remoteFailure(RemoteError(.notFound, "Thread not found for pull request."))
        }
        return try await fetchPullRequestDetail(projectID: summary.projectID, number: number)
    }

    public func performPullRequestAction(_ command: RemotePullRequestCommand) async throws -> RemoteResult {
        try await adapterCall(.pullRequestAction(command))
    }

    // MARK: - Desktop Extended Actions (`coincide_macos_desktop_call`)

    @discardableResult
    public func engineRPC(method: String, params: [String: JSONValue] = [:]) async throws -> JSONValue {
        try await desktopCall(
            action: "engine.rpc",
            params: [
                "method": .string(method),
                "params": .object(params),
            ],
            as: JSONValue.self
        )
    }

    public func runWorkspaceOperation(method: String, params: [String: JSONValue], timeoutSeconds: Int = 30) async throws -> JSONValue {
        guard let threadID = params["threadId"]?.stringValue else {
            throw AgentsRuntimeError.desktopFailure("Workspace operation requires a threadId.")
        }
        let started = try await engineRPC(method: method, params: params)
        guard let operationId = started["operationId"]?.stringValue else {
            return started
        }
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let polled = try await engineRPC(
                method: "workspace.result",
                params: [
                    "threadId": .string(threadID),
                    "operationId": .string(operationId),
                ]
            )
            if polled["ready"]?.boolValue == true {
                let result = polled["result"] ?? .object([:])
                if let errorText = result["error"]?.stringValue, !errorText.isEmpty {
                    throw AgentsRuntimeError.desktopFailure(errorText)
                }
                return result
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw AgentsRuntimeError.desktopFailure("Workspace operation timed out.")
    }

    public func runGitActionsOperation(method: String, params: [String: JSONValue], timeoutSeconds: Int = 60) async throws -> JSONValue {
        guard let threadID = params["threadId"]?.stringValue else {
            throw AgentsRuntimeError.desktopFailure("Git operation requires a threadId.")
        }
        let started = try await engineRPC(method: method, params: params)
        guard let operationId = started["operationId"]?.stringValue else {
            return started
        }
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let polled = try await engineRPC(
                method: "git.actions.result",
                params: [
                    "threadId": .string(threadID),
                    "operationId": .string(operationId),
                ]
            )
            if polled["ready"]?.boolValue == true {
                let result = polled["result"] ?? .object([:])
                if let errorText = result["error"]?.stringValue, !errorText.isEmpty {
                    throw AgentsRuntimeError.desktopFailure(errorText)
                }
                return result
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw AgentsRuntimeError.desktopFailure("Git operation timed out.")
    }

    public func computerUseStatus() async throws -> ComputerUseStatus {
        try await desktopCall(action: "computer_use.status", as: ComputerUseStatus.self)
    }

    public func computerUseSetEnabled(_ enabled: Bool) async throws -> ComputerUseStatus {
        try await desktopCall(
            action: "computer_use.set_enabled",
            params: ["enabled": .bool(enabled)],
            as: ComputerUseStatus.self
        )
    }

    public func computerUseRequestPermission(kind: String? = nil) async throws -> ComputerUseStatus {
        var params: [String: JSONValue] = [:]
        if let kind {
            params["kind"] = .string(kind)
        }
        return try await desktopCall(action: "computer_use.request_permission", params: params, as: ComputerUseStatus.self)
    }

    public func computerUseRefresh() async throws -> ComputerUseStatus {
        try await desktopCall(action: "computer_use.refresh", as: ComputerUseStatus.self)
    }

    public func computerUseRequest(threadId: String, request: JSONValue) async throws -> JSONValue {
        try await desktopCall(
            action: "computer_use.request",
            params: [
                "threadId": .string(threadId),
                "request": request,
            ],
            as: JSONValue.self
        )
    }

    public func computerUseResult(threadId: String, operationId: String) async throws -> JSONValue {
        try await desktopCall(
            action: "computer_use.result",
            params: [
                "threadId": .string(threadId),
                "operationId": .string(operationId),
            ],
            as: JSONValue.self
        )
    }

    public func computerUseScreenshots(threadId: String) async throws -> [ComputerUseScreenshot] {
        struct ScreenshotsResponse: Decodable {
            var screenshots: [ComputerUseScreenshot]
        }
        let response = try await desktopCall(
            action: "computer_use.screenshots",
            params: ["threadId": .string(threadId)],
            as: ScreenshotsResponse.self
        )
        return response.screenshots
    }

    // 1. Providers & Accounts
    private struct ProvidersListResponse: Decodable {
        var providers: [DesktopProviderInfo]
    }

    public func listAllProviders() async throws -> [DesktopProviderInfo] {
        let resp = try await desktopCall(action: "providers.list_all", as: ProvidersListResponse.self)
        return resp.providers
    }

    @discardableResult
    public func saveProviderConfig(
        provider: String,
        executable: String? = nil,
        environment: [String: String]? = nil,
        enabled: Bool? = nil
    ) async throws -> JSONValue {
        var params: [String: JSONValue] = ["provider": .string(provider)]
        if let executable {
            params["executable"] = .string(executable)
        }
        if let environment {
            params["environment"] = .object(environment.mapValues(JSONValue.string))
        }
        if let enabled {
            params["enabled"] = .bool(enabled)
        }
        return try await desktopCall(action: "providers.save_config", params: params, as: JSONValue.self)
    }

    public func checkProvider(provider: String, accountID: String? = nil) async throws -> ProviderProbeResult {
        var params: [String: JSONValue] = ["provider": .string(provider)]
        if let accountID, !accountID.isEmpty {
            params["accountId"] = .string(accountID)
        }
        return try await desktopCall(action: "providers.check", params: params, as: ProviderProbeResult.self)
    }

    private struct KeyAccountEnvelope: Decodable {
        var account: ProviderKeyAccountInfo
    }

    @discardableResult
    public func createProviderKeyAccount(
        provider: String,
        name: String,
        apiKey: String,
        keyVariable: String? = nil
    ) async throws -> ProviderKeyAccountInfo {
        var params: [String: JSONValue] = [
            "provider": .string(provider),
            "name": .string(name),
            "apiKey": .string(apiKey),
        ]
        if let keyVariable, !keyVariable.isEmpty {
            params["envName"] = .string(keyVariable)
        }
        let env = try await desktopCall(
            action: "providers.create_key_account",
            params: params,
            as: KeyAccountEnvelope.self
        )
        return env.account
    }

    @discardableResult
    public func updateProviderAccountKey(
        provider: String,
        accountID: String,
        apiKey: String
    ) async throws -> ProviderKeyAccountInfo {
        let env = try await desktopCall(
            action: "providers.update_account_key",
            params: [
                "provider": .string(provider),
                "accountId": .string(accountID),
                "apiKey": .string(apiKey),
            ],
            as: KeyAccountEnvelope.self
        )
        return env.account
    }

    @discardableResult
    public func renameProviderKeyAccount(
        provider: String,
        accountID: String,
        name: String
    ) async throws -> JSONValue {
        try await desktopCall(
            action: "providers.rename_key_account",
            params: [
                "provider": .string(provider),
                "accountId": .string(accountID),
                "name": .string(name),
            ],
            as: JSONValue.self
        )
    }

    public func deleteProviderAccount(provider: String, accountID: String) async throws {
        _ = try await desktopCall(
            action: "providers.delete_account",
            params: [
                "provider": .string(provider),
                "accountId": .string(accountID),
            ],
            as: JSONValue.self
        )
    }

    private struct LoginAccountEnvelope: Decodable {
        var account: ProviderLoginAccountInfo
    }

    @discardableResult
    public func createProviderLoginAccount(
        provider: String,
        name: String
    ) async throws -> ProviderLoginAccountInfo {
        let env = try await desktopCall(
            action: "providers.create_login_account",
            params: [
                "provider": .string(provider),
                "name": .string(name),
            ],
            as: LoginAccountEnvelope.self
        )
        return env.account
    }

    public func selectThreadAccount(threadID: String, accountID: String?) async throws {
        var params: [String: JSONValue] = ["threadId": .string(threadID)]
        if let accountID, !accountID.isEmpty {
            params["accountId"] = .string(accountID)
        }
        _ = try await desktopCall(action: "providers.select_account", params: params, as: JSONValue.self)
    }

    // 2. ACP Registry & Model Catalog
    private struct ACPRegistryEnvelope: Decodable {
        var agents: [ACPRegistryAgentInfo]?
        var registered: [JSONValue]?
    }

    public func fetchACPRegistry(refresh: Bool = false) async throws -> [ACPRegistryAgentInfo] {
        let env = try await desktopCall(
            action: "providers.acp_registry",
            params: ["refresh": .bool(refresh)],
            as: ACPRegistryEnvelope.self
        )
        let registeredIDs = Set(
            (env.registered ?? []).compactMap { $0["provider"]?.stringValue }
        )
        return (env.agents ?? []).map { agent in
            var copy = agent
            if registeredIDs.contains(copy.providerID) {
                copy.isRegistered = true
            }
            return copy
        }
    }

    @discardableResult
    public func registerACPAgent(agentID: String) async throws -> String {
        let resp = try await desktopCall(
            action: "providers.register_acp",
            params: ["agentId": .string(agentID)],
            as: JSONValue.self
        )
        return resp["provider"]?.stringValue ?? "acp-\(agentID)"
    }

    private struct ModelCatalogEnvelope: Decodable {
        var provider: String?
        var models: [CatalogModelEntry]?
    }

    public func fetchModelCatalog(
        provider: String,
        refresh: Bool = false,
        threadID: String? = nil,
        accountID: String? = nil
    ) async throws -> [CatalogModelEntry] {
        var params: [String: JSONValue] = [
            "provider": .string(provider),
            "refresh": .bool(refresh),
        ]
        if let threadID, !threadID.isEmpty {
            params["threadId"] = .string(threadID)
        }
        if let accountID, !accountID.isEmpty {
            params["accountId"] = .string(accountID)
        }
        let env = try await desktopCall(
            action: "models.catalog",
            params: params,
            as: ModelCatalogEnvelope.self
        )
        return (env.models ?? []).map { item in
            var copy = item
            if copy.provider.isEmpty { copy.provider = provider }
            return copy
        }
    }

    public func setModelPreference(
        provider: String,
        modelID: String,
        favorite: Bool? = nil,
        hidden: Bool? = nil,
        isDefault: Bool? = nil,
        custom: Bool? = nil
    ) async throws {
        var params: [String: JSONValue] = [
            "provider": .string(provider),
            "modelId": .string(modelID),
        ]
        if let favorite { params["favorite"] = .bool(favorite) }
        if let hidden { params["hidden"] = .bool(hidden) }
        if let isDefault { params["isDefault"] = .bool(isDefault) }
        if let custom { params["custom"] = .bool(custom) }
        _ = try await desktopCall(action: "models.set_preference", params: params, as: JSONValue.self)
    }

    // 3. Integrated PTY Terminals
    @discardableResult
    public func createTerminal(threadID: String? = nil) async throws -> String {
        var params: [String: JSONValue] = [:]
        if let threadID, !threadID.isEmpty {
            params["threadId"] = .string(threadID)
        }
        let resp = try await engineRPC(method: "terminal.create", params: params)
        guard let termID = resp["terminalId"]?.stringValue else {
            throw AgentsRuntimeError.desktopFailure("Terminal creation did not return a terminalId.")
        }
        return termID
    }

    public func listTerminals(threadID: String? = nil) async throws -> [TerminalSessionSummary] {
        var params: [String: JSONValue] = [:]
        if let threadID, !threadID.isEmpty {
            params["threadId"] = .string(threadID)
        }
        let raw = try await engineRPC(method: "terminal.status", params: params)
        let data = try Self.makeDesktopEncoder().encode(raw)
        return try Self.makeDesktopDecoder().decode([TerminalSessionSummary].self, from: data)
    }

    public func readTerminalViewport(id: String, dark: Bool = true) async throws -> TerminalViewportSnapshot {
        try await desktopCall(
            action: "terminal.viewport",
            params: [
                "id": .string(id),
                "dark": .bool(dark),
            ],
            as: TerminalViewportSnapshot.self
        )
    }

    public func sendTerminalInput(id: String, data: String) async throws {
        _ = try await engineRPC(
            method: "terminal.write",
            params: [
                "terminalId": .string(id),
                "text": .string(data),
            ]
        )
    }

    public func resizeTerminal(id: String, cols: Int, rows: Int) async throws {
        _ = try await engineRPC(
            method: "terminal.resize",
            params: [
                "terminalId": .string(id),
                "cols": .int(Int64(max(2, cols))),
                "rows": .int(Int64(max(2, rows))),
            ]
        )
    }

    public func scrollTerminal(id: String, delta: Int, revision: UInt64? = nil) async throws {
        let rev: UInt64
        if let revision {
            rev = revision
        } else {
            let snap = try await engineRPC(
                method: "terminal.read",
                params: ["terminalId": .string(id)]
            )
            rev = snap["revision"]?.uint64Value ?? 0
        }
        _ = try await engineRPC(
            method: "terminal.scroll",
            params: [
                "terminalId": .string(id),
                "revision": .int(Int64(rev)),
                "scroll": .object([
                    "kind": .string("lines"),
                    "lines": .int(Int64(delta)),
                ]),
            ]
        )
    }

    public func clearTerminal(id: String) async throws {
        _ = try await engineRPC(
            method: "terminal.clear",
            params: ["terminalId": .string(id)]
        )
    }

    public func restartTerminal(id: String) async throws {
        _ = try await engineRPC(
            method: "terminal.restart",
            params: ["terminalId": .string(id)]
        )
    }

    public func closeTerminal(id: String) async throws {
        _ = try await engineRPC(
            method: "terminal.close",
            params: ["terminalId": .string(id)]
        )
    }

    // 4. Workspace Files, Ripgrep-Speed Search, Read & Write
    public func listWorkspaceFiles(
        cwd: String,
        query: String = "",
        limit: Int = 500
    ) async throws -> [WorkspaceFileEntry] {
        let expanded = ExternalEditorService.expandedPath(cwd)
        let raw = try await desktopCall(
            action: "workspace.files",
            params: [
                "cwd": .string(expanded),
                "query": .string(query),
                "limit": .int(Int64(limit)),
            ],
            as: JSONValue.self
        )
        let encoder = Self.makeDesktopEncoder()
        let decoder = Self.makeDesktopDecoder()
        if let filesVal = raw["files"] {
            let data = try encoder.encode(filesVal)
            return try decoder.decode([WorkspaceFileEntry].self, from: data)
        }
        if case .array = raw {
            let data = try encoder.encode(raw)
            return try decoder.decode([WorkspaceFileEntry].self, from: data)
        }
        return []
    }

    private struct WorkspaceSearchEnvelope: Decodable {
        var matches: [WorkspaceSearchHit]?
    }

    public func searchWorkspace(
        cwd: String,
        query: String,
        limit: Int = 200
    ) async throws -> [WorkspaceSearchHit] {
        let expanded = ExternalEditorService.expandedPath(cwd)
        let env = try await desktopCall(
            action: "workspace.search",
            params: [
                "cwd": .string(expanded),
                "query": .string(query),
                "limit": .int(Int64(limit)),
            ],
            as: WorkspaceSearchEnvelope.self
        )
        return env.matches ?? []
    }

    public func readWorkspaceFile(cwd: String, path: String) async throws -> WorkspaceFileDocument {
        let expanded = ExternalEditorService.expandedPath(cwd)
        return try await desktopCall(
            action: "workspace.read_file",
            params: [
                "cwd": .string(expanded),
                "path": .string(path),
            ],
            as: WorkspaceFileDocument.self
        )
    }

    public func writeWorkspaceFile(cwd: String, path: String, content: String) async throws {
        let expanded = ExternalEditorService.expandedPath(cwd)
        _ = try await desktopCall(
            action: "workspace.write_file",
            params: [
                "cwd": .string(expanded),
                "path": .string(path),
                "content": .string(content),
            ],
            as: JSONValue.self
        )
    }

    public func deleteWorkspaceFile(cwd: String, path: String) async throws {
        let expanded = ExternalEditorService.expandedPath(cwd)
        _ = try await desktopCall(
            action: "workspace.delete_file",
            params: [
                "cwd": .string(expanded),
                "path": .string(path),
            ],
            as: JSONValue.self
        )
    }

    public func deleteWorkspaceDirectory(cwd: String, path: String, recursive: Bool = false) async throws {
        let expanded = ExternalEditorService.expandedPath(cwd)
        _ = try await desktopCall(
            action: "workspace.delete_directory",
            params: [
                "cwd": .string(expanded),
                "path": .string(path),
                "recursive": .bool(recursive),
            ],
            as: JSONValue.self
        )
    }

    public func moveWorkspaceFile(cwd: String, path: String, destination: String) async throws {
        let expanded = ExternalEditorService.expandedPath(cwd)
        _ = try await desktopCall(
            action: "workspace.move_file",
            params: [
                "cwd": .string(expanded),
                "path": .string(path),
                "destination": .string(destination),
            ],
            as: JSONValue.self
        )
    }

    public func copyWorkspaceFile(cwd: String, path: String, destination: String) async throws {
        let expanded = ExternalEditorService.expandedPath(cwd)
        _ = try await desktopCall(
            action: "workspace.copy_file",
            params: [
                "cwd": .string(expanded),
                "path": .string(path),
                "destination": .string(destination),
            ],
            as: JSONValue.self
        )
    }

    public func createWorkspaceDirectory(cwd: String, path: String) async throws {
        let expanded = ExternalEditorService.expandedPath(cwd)
        _ = try await desktopCall(
            action: "workspace.create_dir",
            params: [
                "cwd": .string(expanded),
                "path": .string(path),
            ],
            as: JSONValue.self
        )
    }

    public func readWorkspaceDirectory(
        cwd: String,
        path: String = "",
        recursive: Bool = false
    ) async throws -> [WorkspaceFileEntry] {
        let expanded = ExternalEditorService.expandedPath(cwd)
        let raw = try await desktopCall(
            action: "workspace.read_dir",
            params: [
                "cwd": .string(expanded),
                "path": .string(path),
                "recursive": .bool(recursive),
            ],
            as: JSONValue.self
        )
        let encoder = Self.makeDesktopEncoder()
        let decoder = Self.makeDesktopDecoder()
        if let entriesVal = raw["entries"] {
            let data = try encoder.encode(entriesVal)
            return try decoder.decode([WorkspaceFileEntry].self, from: data)
        }
        return []
    }

    public func editWorkspaceFile(
        cwd: String,
        path: String,
        oldText: String,
        newText: String,
        mode: String = "replace"
    ) async throws -> JSONValue {
        let expanded = ExternalEditorService.expandedPath(cwd)
        return try await desktopCall(
            action: "workspace.edit_file",
            params: [
                "cwd": .string(expanded),
                "path": .string(path),
                "oldText": .string(oldText),
                "newText": .string(newText),
                "mode": .string(mode),
            ],
            as: JSONValue.self
        )
    }

    public func editWorkspaceFile(cwd: String, path: String, edits: [WorkspaceEdit]) async throws -> JSONValue {
        let expanded = ExternalEditorService.expandedPath(cwd)
        return try await desktopCall(
            action: "workspace.edit_file",
            params: [
                "cwd": .string(expanded),
                "path": .string(path),
                "edits": .array(edits.map { edit in
                    .object([
                        "oldText": .string(edit.oldText),
                        "newText": .string(edit.newText),
                        "mode": .string(edit.mode),
                    ])
                }),
            ],
            as: JSONValue.self
        )
    }

    public func searchWorkspaceRegex(
        cwd: String,
        pattern: String,
        limit: Int = 200
    ) async throws -> [WorkspaceSearchHit] {
        let expanded = ExternalEditorService.expandedPath(cwd)
        let env = try await desktopCall(
            action: "workspace.search_regex",
            params: [
                "cwd": .string(expanded),
                "pattern": .string(pattern),
                "limit": .int(Int64(limit)),
            ],
            as: WorkspaceSearchEnvelope.self
        )
        return env.matches ?? []
    }

    public func memoryStore(key: String, value: String, scope: String? = nil) async throws -> JSONValue {
        var params: [String: JSONValue] = [
            "key": .string(key),
            "value": .string(value),
        ]
        if let scope {
            params["scope"] = .string(scope)
        }
        return try await desktopCall(action: "memory.store", params: params, as: JSONValue.self)
    }

    public func memoryRetrieve(key: String, scope: String? = nil) async throws -> JSONValue {
        var params: [String: JSONValue] = ["key": .string(key)]
        if let scope {
            params["scope"] = .string(scope)
        }
        return try await desktopCall(action: "memory.retrieve", params: params, as: JSONValue.self)
    }

    private struct MemoryListEnvelope: Decodable {
        var entries: [MemoryEntry]?
    }

    public func memoryList(scope: String? = nil, query: String? = nil, limit: Int = 200) async throws -> [MemoryEntry] {
        var params: [String: JSONValue] = ["limit": .int(Int64(limit))]
        if let scope {
            params["scope"] = .string(scope)
        }
        if let query {
            params["query"] = .string(query)
        }
        let env = try await desktopCall(action: "memory.list", params: params, as: MemoryListEnvelope.self)
        return env.entries ?? []
    }

    public func memoryDelete(key: String, scope: String? = nil) async throws -> JSONValue {
        var params: [String: JSONValue] = ["key": .string(key)]
        if let scope {
            params["scope"] = .string(scope)
        }
        return try await desktopCall(action: "memory.delete", params: params, as: JSONValue.self)
    }

    public func memoryClear(scope: String, confirm: Bool) async throws -> JSONValue {
        try await desktopCall(
            action: "memory.clear",
            params: [
                "scope": .string(scope),
                "confirm": .bool(confirm),
            ],
            as: JSONValue.self
        )
    }

    public func memorySnapshot(scope: String? = nil, query: String? = nil, limit: Int = 50) async throws -> JSONValue {
        var params: [String: JSONValue] = ["limit": .int(Int64(limit))]
        if let scope {
            params["scope"] = .string(scope)
        }
        if let query {
            params["query"] = .string(query)
        }
        return try await desktopCall(action: "memory.snapshot", params: params, as: JSONValue.self)
    }

    public func memoryContextStore(key: String, action: String, value: String? = nil, scope: String? = nil) async throws -> JSONValue {
        var params: [String: JSONValue] = [
            "key": .string(key),
            "action": .string(action),
        ]
        if let value {
            params["value"] = .string(value)
        }
        if let scope {
            params["scope"] = .string(scope)
        }
        return try await desktopCall(action: "memory.context_store", params: params, as: JSONValue.self)
    }

    public func spawnWorkers(parentThreadId: String, workers: [WorkerSpawnRequest]) async throws -> JSONValue {
        let workerValues: [JSONValue] = try workers.map { worker in
            var object: [String: JSONValue] = [
                "name": .string(worker.name),
                "task": .string(worker.task),
                "targetFiles": .array(worker.targetFiles.map { .string($0) }),
            ]
            if let assistantId = worker.assistantId, !assistantId.isEmpty {
                guard UUID(uuidString: assistantId) != nil else {
                    throw AgentsRuntimeError.desktopFailure("Assistant ID must be a UUID")
                }
                object["assistantId"] = .string(assistantId)
            }
            return .object(object)
        }
        return try await desktopCall(
            action: "workers.spawn",
            params: [
                "parentThreadId": .string(parentThreadId),
                "workers": .array(workerValues),
            ],
            as: JSONValue.self
        )
    }

    private struct WorkerListEnvelope: Decodable {
        var workers: [WorkerRecord]?
    }

    public func listWorkers(parentThreadId: String? = nil) async throws -> [WorkerRecord] {
        var params: [String: JSONValue] = [:]
        if let parentThreadId {
            params["parentThreadId"] = .string(parentThreadId)
        }
        let env = try await desktopCall(action: "workers.list", params: params, as: WorkerListEnvelope.self)
        return env.workers ?? []
    }

    public func listWorkers(assistantId: String) async throws -> [WorkerRecord] {
        let env = try await desktopCall(
            action: "workers.list",
            params: ["assistantId": .string(assistantId)],
            as: WorkerListEnvelope.self
        )
        return env.workers ?? []
    }

    public func workerStatus(workerId: String) async throws -> WorkerRecord {
        try await desktopCall(
            action: "workers.status",
            params: ["workerId": .string(workerId)],
            as: WorkerRecord.self
        )
    }

    public func workerResult(workerId: String) async throws -> WorkerRecord {
        try await desktopCall(
            action: "workers.result",
            params: ["workerId": .string(workerId)],
            as: WorkerRecord.self
        )
    }

    public func cancelWorker(workerId: String) async throws -> WorkerRecord {
        try await desktopCall(
            action: "workers.cancel",
            params: ["workerId": .string(workerId)],
            as: WorkerRecord.self
        )
    }

    public func deleteWorker(workerId: String) async throws -> JSONValue {
        try await desktopCall(
            action: "workers.delete",
            params: ["workerId": .string(workerId)],
            as: JSONValue.self
        )
    }

    public func planTask(parentThreadId: String, task: String) async throws -> WorkerPlan {
        try await desktopCall(
            action: "workers.plan",
            params: [
                "parentThreadId": .string(parentThreadId),
                "task": .string(task),
            ],
            as: WorkerPlan.self
        )
    }

    public func breakdownTask(planId: String, parentThreadId: String? = nil) async throws -> WorkerPlan {
        var params: [String: JSONValue] = ["planId": .string(planId)]
        if let parentThreadId {
            params["parentThreadId"] = .string(parentThreadId)
        }
        return try await desktopCall(action: "workers.breakdown", params: params, as: WorkerPlan.self)
    }

    public func executionPlan(parentThreadId: String, objective: String, mode: String) async throws -> WorkerPlan {
        try await desktopCall(
            action: "workers.execution_plan",
            params: [
                "parentThreadId": .string(parentThreadId),
                "objective": .string(objective),
                "mode": .string(mode),
            ],
            as: WorkerPlan.self
        )
    }

    // 5. Agent Instruction Files
    private struct InstructionsListEnvelope: Decodable {
        var global: [InstructionFileDescriptor]?
        var project: [InstructionFileDescriptor]?
    }

    public func listInstructions(projectRoot: String? = nil) async throws -> [InstructionFileDescriptor] {
        var params: [String: JSONValue] = [:]
        if let projectRoot, !projectRoot.isEmpty {
            params["cwd"] = .string(ExternalEditorService.expandedPath(projectRoot))
        }
        let env = try await desktopCall(
            action: "instructions.list",
            params: params,
            as: InstructionsListEnvelope.self
        )
        return (env.global ?? []) + (env.project ?? [])
    }

    public func readInstruction(path: String, projectRoot: String? = nil) async throws -> String {
        var params: [String: JSONValue] = ["path": .string(path)]
        if let projectRoot, !projectRoot.isEmpty {
            params["cwd"] = .string(ExternalEditorService.expandedPath(projectRoot))
        }
        let raw = try await desktopCall(
            action: "instructions.read",
            params: params,
            as: JSONValue.self
        )
        return raw["content"]?.stringValue ?? raw["text"]?.stringValue ?? ""
    }

    public func saveInstruction(
        path: String,
        content: String,
        projectRoot: String? = nil,
        expectedContent: String? = nil
    ) async throws {
        var params: [String: JSONValue] = [
            "path": .string(path),
            "content": .string(content),
        ]
        if let projectRoot, !projectRoot.isEmpty {
            params["cwd"] = .string(ExternalEditorService.expandedPath(projectRoot))
        }
        if let expectedContent {
            params["expectedContent"] = .string(expectedContent)
        }
        _ = try await desktopCall(action: "instructions.save", params: params, as: JSONValue.self)
    }

    // 6. Attachment Staging, Permanent Thread Deletion, Undo, Schedules & Scripts
    public func stageAttachment(
        filePath: String? = nil,
        base64Data: String? = nil,
        filename: String? = nil,
        threadID: String? = nil
    ) async throws -> StagedAttachment {
        var params: [String: JSONValue] = [:]
        if let filePath, !filePath.isEmpty {
            params["filePath"] = .string(ExternalEditorService.expandedPath(filePath))
        }
        if let base64Data, !base64Data.isEmpty {
            params["base64"] = .string(base64Data)
        }
        if let filename, !filename.isEmpty {
            params["filename"] = .string(filename)
        }
        if let threadID, !threadID.isEmpty {
            params["threadId"] = .string(threadID)
        }
        return try await desktopCall(
            action: "attachments.stage",
            params: params,
            as: StagedAttachment.self
        )
    }

    @discardableResult
    public func deleteThreadPermanently(threadID: String) async throws -> String {
        let resp = try await desktopCall(
            action: "threads.delete_permanent",
            params: ["threadId": .string(threadID)],
            as: JSONValue.self
        )
        let undoID = resp["undoId"]?.stringValue ?? threadID
        stateLock.withLock { self.lastUndoDeleteID = undoID }
        return undoID
    }

    @discardableResult
    public func undoDeleteThread(undoID: String? = nil) async throws -> [String] {
        let resolvedID = undoID ?? stateLock.withLock { self.lastUndoDeleteID }
        guard let resolvedID, !resolvedID.isEmpty else {
            throw AgentsRuntimeError.desktopFailure("No recently deleted thread available to undo.")
        }
        let resp = try await desktopCall(
            action: "threads.undo_delete",
            params: ["undoId": .string(resolvedID)],
            as: JSONValue.self
        )
        return resp["threadIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    public func approveSchedule(id: String) async throws {
        _ = try await desktopCall(
            action: "schedules.approve",
            params: ["id": .string(id)],
            as: JSONValue.self
        )
    }

    public func saveProjectScripts(projectID: String, scripts: [RemoteScript]) async throws {
        let encodedScripts: [JSONValue] = scripts.map { script in
            .object([
                "id": .string(script.id.uuidString),
                "name": .string(script.name),
                "command": .string(script.command),
                "icon": .string(script.icon),
            ])
        }
        _ = try await desktopCall(
            action: "projects.scripts.save",
            params: [
                "projectId": .string(projectID),
                "scripts": .array(encodedScripts),
            ],
            as: JSONValue.self
        )
    }

    // 7. Usage Report, Remote Server & Legacy Import
    public func fetchDesktopUsage(
        days: Int = 30,
        provider: String? = nil,
        accountID: String? = nil,
        refresh: Bool = false
    ) async throws -> DesktopUsageReport {
        var params: [String: JSONValue] = [
            "days": .int(Int64(days)),
            "refresh": .bool(refresh),
        ]
        if let provider, !provider.isEmpty {
            params["provider"] = .string(provider)
        }
        if let accountID, !accountID.isEmpty {
            params["accountId"] = .string(accountID)
        }
        return try await desktopCall(
            action: "usage.dashboard",
            params: params,
            as: DesktopUsageReport.self
        )
    }

    public func fetchRemoteServerStatus() async throws -> RemoteServerSnapshot {
        try await desktopCall(action: "remote.status", as: RemoteServerSnapshot.self)
    }

    @discardableResult
    public func setRemoteServerEnabled(_ enabled: Bool) async throws -> RemoteServerSnapshot {
        try await desktopCall(
            action: "remote.set_enabled",
            params: ["enabled": .bool(enabled)],
            as: RemoteServerSnapshot.self
        )
    }

    @discardableResult
    public func beginRemotePairing() async throws -> RemoteServerSnapshot {
        try await desktopCall(action: "remote.begin_pairing", as: RemoteServerSnapshot.self)
    }

    @discardableResult
    public func cancelRemotePairing() async throws -> RemoteServerSnapshot {
        try await desktopCall(action: "remote.cancel_pairing", as: RemoteServerSnapshot.self)
    }

    @discardableResult
    public func revokeRemoteDevice(deviceID: String) async throws -> RemoteServerSnapshot {
        try await desktopCall(
            action: "remote.revoke_device",
            params: ["deviceId": .string(deviceID)],
            as: RemoteServerSnapshot.self
        )
    }

    @discardableResult
    public func resetRemoteIdentity() async throws -> RemoteServerSnapshot {
        try await desktopCall(action: "remote.reset_identity", as: RemoteServerSnapshot.self)
    }

    @discardableResult
    public func importLegacyWorkspace(sourceDir: String? = nil) async throws -> LegacyImportReport {
        var params: [String: JSONValue] = [:]
        if let sourceDir, !sourceDir.isEmpty {
            params["sourceDir"] = .string(ExternalEditorService.expandedPath(sourceDir))
        }
        return try await desktopCall(
            action: "store.import_legacy",
            params: params,
            as: LegacyImportReport.self
        )
    }

    // 8. Project Creation & CLI Session Discovery/Import Helpers
    @discardableResult
    public func createProject(path: String, name: String? = nil) async throws -> UUID {
        let expanded = ExternalEditorService.expandedPath(path)
        var params: [String: JSONValue] = ["path": .string(expanded)]
        if let name, !name.isEmpty {
            params["name"] = .string(name)
        }
        let resp = try await engineRPC(method: "projects.create", params: params)
        if let idStr = resp["id"]?.stringValue, let uuid = UUID(uuidString: idStr) {
            return uuid
        }
        throw AgentsRuntimeError.desktopFailure("Project creation did not return a valid UUID.")
    }

    public func discoverCLISessions() async -> [CLISessionSummary] {
        await Task.detached(priority: .userInitiated) {
            Self.scanLocalCLISessions()
        }.value
    }

    @discardableResult
    public func importCLISession(
        path: String,
        provider: String = "auto",
        projectID: UUID? = nil
    ) async throws -> UUID {
        let expanded = ExternalEditorService.expandedPath(path)
        let preview = try await engineRPC(
            method: "cli.sessions.preview",
            params: [
                "path": .string(expanded),
                "provider": .string(provider),
            ]
        )
        if let existing = preview["existingThreadId"]?.stringValue,
           let uuid = UUID(uuidString: existing)
        {
            return uuid
        }
        guard let sha256 = preview["sha256"]?.stringValue else {
            throw AgentsRuntimeError.desktopFailure("Session preview missing sha256 guard.")
        }
        let resolvedProvider = preview["provider"]?.stringValue ?? provider
        var importParams: [String: JSONValue] = [
            "path": .string(expanded),
            "provider": .string(resolvedProvider),
            "sha256": .string(sha256),
        ]
        if let projectID {
            importParams["projectId"] = .string(projectID.uuidString)
        }
        let imported = try await engineRPC(method: "cli.sessions.import", params: importParams)
        guard let tid = imported["threadId"]?.stringValue,
              let uuid = UUID(uuidString: tid)
        else {
            throw AgentsRuntimeError.desktopFailure("CLI session import did not return a valid threadId.")
        }
        return uuid
    }

    private static func scanLocalCLISessions() -> [CLISessionSummary] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        let claudeRoot = env["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".claude")
        let codexRoot = env["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")

        let roots: [(String, URL)] = [
            ("claude", claudeRoot.appendingPathComponent("projects")),
            ("codex", codexRoot.appendingPathComponent("sessions")),
            ("codex", codexRoot.appendingPathComponent("archived_sessions")),
        ]

        var results: [CLISessionSummary] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]

        for (provider, rootURL) in roots {
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            var visited = 0
            while let fileURL = enumerator.nextObject() as? URL {
                visited += 1
                if visited > 4_000 || results.count >= 300 { break }
                guard fileURL.pathExtension == "jsonl" else { continue }
                guard let vals = try? fileURL.resourceValues(forKeys: Set(keys)),
                      vals.isRegularFile == true,
                      vals.isSymbolicLink != true
                else {
                    continue
                }
                let head = Self.extractHeadMetadata(from: fileURL)
                results.append(
                    CLISessionSummary(
                        id: fileURL.path,
                        provider: provider,
                        title: head.title ?? fileURL.deletingPathExtension().lastPathComponent,
                        path: fileURL.path,
                        cwd: head.cwd,
                        updatedAt: vals.contentModificationDate,
                        messageCount: head.approxMessages,
                        alreadyImported: false
                    )
                )
            }
        }

        results.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        return results
    }

    private static func extractHeadMetadata(from url: URL) -> (title: String?, cwd: String?, approxMessages: Int) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return (nil, nil, 0)
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024),
              let text = String(data: data, encoding: .utf8)
        else {
            return (nil, nil, 0)
        }
        var foundTitle: String?
        var foundCwd: String?
        var count = 0
        for line in text.split(separator: "\n").prefix(60) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONDecoder().decode([String: JSONValue].self, from: lineData)
            else {
                continue
            }
            if foundCwd == nil {
                foundCwd = obj["cwd"]?.stringValue ?? obj["payload"]?["cwd"]?.stringValue
            }
            if obj["type"]?.stringValue == "user" || obj["payload"]?["role"]?.stringValue == "user" {
                count += 1
                if foundTitle == nil {
                    let msgText = obj["message"]?["content"]?.stringValue
                        ?? obj["payload"]?["content"]?.arrayValue?.first?["text"]?.stringValue
                    if let trimmed = msgText?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                        foundTitle = String(trimmed.prefix(90))
                    }
                }
            }
        }
        return (foundTitle, foundCwd, max(1, count))
    }
}
