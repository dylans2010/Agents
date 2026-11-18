import AppKit
import CoincideRemoteKit
import Foundation
import Observation

@Observable
@MainActor
public final class AppModel {
    // MARK: - Core Workspace & Conversation State

    public var workspace: RemoteWorkspace = RemoteWorkspace()
    public var selectedThreadID: String? {
        didSet {
            UserDefaults.standard.set(selectedThreadID, forKey: Self.selectedThreadDefaultsKey)
            UserDefaults.standard.set("", forKey: AssistantLibrarySidebarSelection.userDefaultsKey)
            if oldValue?.uppercased() != selectedThreadID?.uppercased() {
                Task { await handleSelectedThreadChanged() }
            }
        }
    }
    public var activeTranscript: RemoteTranscript?

    // MARK: - Providers, Models & Runtime Poll Status

    public var providers: [DesktopProviderInfo] = []
    public var acpRegistry: [ACPRegistryAgentInfo] = []
    public var status: RuntimePollStatus = RuntimePollStatus()

    public private(set) var daemonOpenFailure: String?
    public private(set) var consecutivePollFailures: Int = 0
    public private(set) var lastPollError: String?

    public var daemonConnectionStatus: DaemonConnectionStatus {
        DaemonConnectionStatus.status(
            runtimeOpen: runtime?.isOpen == true,
            consecutivePollFailures: consecutivePollFailures,
            lastPollError: lastPollError,
            openFailure: daemonOpenFailure
        )
    }

    // MARK: - Shell Chrome, Inspector & Integrated Terminal State

    public var inspectorVisible: Bool {
        didSet { UserDefaults.standard.set(inspectorVisible, forKey: Self.inspectorVisibleKey) }
    }
    public var inspectorTab: InspectorTab {
        didSet { UserDefaults.standard.set(inspectorTab.rawValue, forKey: Self.inspectorTabKey) }
    }
    public var terminalVisible: Bool {
        didSet { UserDefaults.standard.set(terminalVisible, forKey: Self.terminalVisibleKey) }
    }
    public var activeTerminals: [TerminalSessionSummary] = []
    public var selectedTerminalID: String?

    // MARK: - Sheets, Search, Find & Settings Navigation

    public var showCommandPalette: Bool = false
    public var showBotEditor: Bool = false
    public var editingBot: RemoteBot?
    public var showSessionImport: Bool = false
    public var showFindBar: Bool = false
    public var findQuery: String = ""
    public var sidebarSearchQuery: String = ""
    public var showArchivedThreads: Bool = false {
        didSet {
            if oldValue != showArchivedThreads {
                Task { await refreshWorkspace() }
            }
        }
    }
    public var selectedSettingsTab: SettingsTab = .general

    public var editingAssistantDefinition: AssistantDefinition?
    public var showAssistantEditor: Bool = false
    public var launchingAssistantDefinition: AssistantDefinition?
    public var launchingAssistantPaths: [String] = []
    public var launchingAssistantTask: String = ""
    public var showAssistantLaunch: Bool = false
    public var assistantResultReport: AssistantReport?
    public var showAssistantResult: Bool = false
    public var showAssistantTasks: Bool = false

    public var agentToolset: AgentToolset {
        didSet { AgentToolset.save(agentToolset) }
    }

    // MARK: - Typography & Appearance Preferences

    public var fontScale: Double {
        didSet { UserDefaults.standard.set(fontScale, forKey: Self.fontScaleKey) }
    }
    public var usesSerifReplies: Bool {
        didSet { UserDefaults.standard.set(usesSerifReplies, forKey: Self.usesSerifKey) }
    }
    public var appearancePreference: AppearancePreference {
        didSet {
            UserDefaults.standard.set(appearancePreference.rawValue, forKey: Self.appearanceKey)
            applyAppearanceToNSApp()
        }
    }

    // MARK: - Notifications, Toasts, Errors & Cross-Pane Requests

    public var toastMessage: ToastMessage?
    public var lastError: String?
    public var openFileInInspectorRequest: WorkspaceFileOpenRequest?
    public var composerInsertedTextRequest: String?

    // MARK: - Rich Contextual Caches & Sub-Services

    public private(set) var isBootstrapped: Bool = false
    public private(set) var isLoadingTranscript: Bool = false
    public var activeCheckout: RemoteCheckout?
    public var activeComposerNotice: RemoteComposerNotice?
    public var activeDiff: RemoteDiff?
    public var activeDiffScope: DiffScope = .uncommitted
    public var activeGitState: RemoteGitState?
    public var scheduledTasks: RemoteScheduledTasks = RemoteScheduledTasks()
    public var assistants: [RemoteAssistant] = []
    public private(set) var assistantsLoaded: Bool = false

    public var assistantCatalog: AssistantCatalog {
        AssistantCatalog(stored: assistants)
    }

    public var remoteServer: RemoteServerSnapshot = RemoteServerSnapshot()
    public var settingsSnapshot: RemoteSettingsSnapshot = RemoteSettingsSnapshot()
    public var usageLimits: [RemoteUsage] = []

    public let voiceDictation = VoiceDictationController()
    public let computerUse = ComputerUseController()
    public let systemAssets = SystemAssetManager.shared
    public var externalEditors: ExternalEditorService { ExternalEditorService.shared }

    @ObservationIgnored public private(set) var runtime: AgentsRuntimeClient?
    @ObservationIgnored public private(set) var assistantTaskManager: AssistantTaskManager?
    @ObservationIgnored public private(set) var assistantChangeLedger: AssistantChangeLedger?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var toastDismissTask: Task<Void, Never>?
    @ObservationIgnored private var toastUndoHandler: (@MainActor () -> Void)?
    @ObservationIgnored private var daemonReconnectInFlight = false
    @ObservationIgnored private var bootstrapDataDir: String?
    @ObservationIgnored private var systemPromptCache = SystemPromptCache()
    @ObservationIgnored private var lastObservedRevision: UInt64 = 0
    @ObservationIgnored private var lastObservedRunningIDs: Set<String> = []
    @ObservationIgnored private var lastObservedAttentionCount: Int = 0
    @ObservationIgnored private var lastObservedTurnSerial: UInt64 = 0
    @ObservationIgnored private var lastPollActive: Bool = false
    @ObservationIgnored private var pollFastUntil: Date = .distantPast
    @ObservationIgnored private var lastPollErrorMessage: String?

    /// Lifecycle hooks consumed by `AppDelegate` & `StatusBarController`.
    @ObservationIgnored public var onStatusChanged: (@MainActor (RuntimePollStatus) -> Void)?
    @ObservationIgnored public var onAgentTurnFinished: (@MainActor (RemoteThreadSummary) -> Void)?
    @ObservationIgnored public var onUserAttentionNeeded: (@MainActor (Int, Int) -> Void)?

    // MARK: - UserDefaults Keys

    private static let selectedThreadDefaultsKey = "coincide.selectedThreadID"
    private static let inspectorVisibleKey = "coincide.inspectorVisible"
    private static let inspectorTabKey = "coincide.inspectorTab"
    private static let terminalVisibleKey = "coincide.terminalVisible"
    private static let fontScaleKey = "coincide.fontScale"
    private static let usesSerifKey = "coincide.usesSerifReplies"
    private static let appearanceKey = "coincide.appearancePreference"

    // MARK: - Init

    public init() {
        let defaults = UserDefaults.standard
        self.inspectorVisible = defaults.object(forKey: Self.inspectorVisibleKey) as? Bool ?? false
        self.inspectorTab = InspectorTab(rawValue: defaults.string(forKey: Self.inspectorTabKey) ?? "") ?? .changes
        self.terminalVisible = defaults.object(forKey: Self.terminalVisibleKey) as? Bool ?? false
        let savedScale = defaults.double(forKey: Self.fontScaleKey)
        self.fontScale = savedScale > 0 ? min(1.5, max(0.8, savedScale)) : 1.0
        self.usesSerifReplies = defaults.object(forKey: Self.usesSerifKey) as? Bool ?? false
        self.appearancePreference = AppearancePreference(
            rawValue: defaults.string(forKey: Self.appearanceKey) ?? ""
        ) ?? .system
        self.agentToolset = AgentToolset.load(from: defaults)
        self.selectedThreadID = defaults.string(forKey: Self.selectedThreadDefaultsKey)
        self.computerUse.runtimeProvider = { [weak self] in self?.runtime }
    }

    // MARK: - Computed Workspace Helpers

    public var selectedThreadUUID: UUID? {
        guard let selectedThreadID else { return nil }
        return UUID(uuidString: selectedThreadID)
    }

    public var selectedThread: RemoteThreadSummary? {
        guard let uuid = selectedThreadUUID else { return nil }
        return workspace.threads.first { $0.id == uuid } ?? activeTranscript?.thread
    }

    public var selectedProject: RemoteProject? {
        guard let projectID = selectedThread?.projectID else {
            return workspace.projects.first { !$0.isChats }
        }
        return workspace.projects.first { $0.id == projectID }
    }

    /// Best-effort absolute working directory for the selected thread or project.
    public var activeWorkingDirectory: String? {
        if let term = activeTerminals.first(where: { $0.id == selectedTerminalID }), !term.directory.isEmpty {
            return ExternalEditorService.expandedPath(term.directory)
        }
        if let proj = selectedProject, !proj.path.isEmpty {
            return ExternalEditorService.expandedPath(proj.path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    public var filteredThreads: [RemoteThreadSummary] {
        let q = sidebarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return workspace.threads.filter { thread in
            if !showArchivedThreads && thread.isArchived { return false }
            guard !q.isEmpty else { return true }
            return thread.title.lowercased().contains(q)
                || (thread.branch?.lowercased().contains(q) ?? false)
                || thread.selection.provider.lowercased().contains(q)
        }
    }

    public var recentThreads: [RemoteThreadSummary] {
        Array(
            workspace.threads
                .filter { !$0.isArchived }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(5)
        )
    }

    // MARK: - Runtime Bootstrap, 150ms Poll Loop & Shutdown

    public func bootstrap(dataDir: String? = nil, startPolling: Bool = true) async {
        guard !isBootstrapped else { return }
        self.bootstrapDataDir = dataDir
        applyAppearanceToNSApp()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"

        do {
            let client = try AgentsRuntimeClient(dataDir: dataDir, appVersion: version)
            self.runtime = client
            self.daemonOpenFailure = nil
            self.consecutivePollFailures = 0
            self.lastPollError = nil
            self.isBootstrapped = true

            if let initialStatus = try? await client.pollStatus() {
                self.status = initialStatus
                self.lastObservedRevision = initialStatus.revision
                self.lastObservedRunningIDs = Set(initialStatus.runningThreadIDs)
                self.lastObservedAttentionCount = initialStatus.totalAttentionCount
                self.lastObservedTurnSerial = initialStatus.turnResultsSerial
                self.lastPollActive = initialStatus.busy || initialStatus.running > 0 || initialStatus.starting > 0 || !initialStatus.runningThreadIDs.isEmpty
                onStatusChanged?(initialStatus)
            } else {
                recordPollFailure("Initial status poll failed")
            }

            await refreshWorkspace()
            await refreshProviders()
            if selectedThreadUUID == nil || selectedThread == nil {
                selectedThreadID = workspace.threads.first(where: { !$0.isArchived })?.id.uuidString
            } else {
                await handleSelectedThreadChanged()
            }

            await refreshAssistants()
            await setupAssistantManagers()
            await recoverAssistantTasks()
            Task {
                await refreshScheduledTasks()
                await refreshRemoteServer()
            }

            if startPolling {
                startPollLoop()
            }
        } catch {
            let message = ErrorSanitizer.displayMessage(for: error)
            self.lastError = message
            if runtime == nil {
                daemonOpenFailure = message
            }
            presentToast("Runtime Startup Failed", detail: message, style: .error)
        }
    }

    private var pollInterval: Duration {
        if lastPollActive || Date.now < pollFastUntil {
            return .milliseconds(150)
        }
        return .milliseconds(1000)
    }

    private func boostPollForNewActivity() {
        pollFastUntil = Date.now.addingTimeInterval(10)
    }

    private func startPollLoop() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .milliseconds(150))
                guard !Task.isCancelled, let self else { break }
                await self.performSinglePollTick()
            }
        }
    }

    private func performSinglePollTick() async {
        guard let client = runtime else { return }
        let polled: RuntimePollStatus
        do {
            polled = try await client.pollStatus()
            notePollSuccess()
        } catch {
            let message = ErrorSanitizer.displayMessage(for: error)
            if lastPollErrorMessage != message {
                lastPollErrorMessage = message
                lastError = message
            }
            recordPollFailure(message)
            return
        }
        if let previousPollError = lastPollErrorMessage {
            lastPollErrorMessage = nil
            if lastError == previousPollError {
                lastError = nil
            }
        }
        lastPollActive = polled.busy || polled.running > 0 || polled.starting > 0 || !polled.runningThreadIDs.isEmpty
        if polled.busy {
            return
        }

        let previousRunning = lastObservedRunningIDs
        let currentRunning = Set(polled.runningThreadIDs)
        let revisionChanged = polled.revision != lastObservedRevision
        let runningChanged = currentRunning != previousRunning || polled.running != status.running || polled.starting != status.starting
        let attentionChanged = polled.totalAttentionCount != lastObservedAttentionCount
        let (finishedTurns, finishedTurnWatermark) = polled.newlyFinishedTurns(since: lastObservedTurnSerial)
        let turnFinishedChanged = !finishedTurns.isEmpty

        self.status = polled
        onStatusChanged?(polled)

        if polled.activationRequested {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }

        if let openID = polled.requestedOpenThreadID,
           let uuid = UUID(uuidString: openID)
        {
            selectThread(uuid)
        }

        if attentionChanged && polled.totalAttentionCount > lastObservedAttentionCount {
            onUserAttentionNeeded?(polled.pendingApprovals, polled.pendingQuestions)
        }

        lastObservedRevision = polled.revision
        lastObservedRunningIDs = currentRunning
        lastObservedAttentionCount = polled.totalAttentionCount
        lastObservedTurnSerial = finishedTurnWatermark

        if revisionChanged || runningChanged || attentionChanged || turnFinishedChanged {
            await refreshWorkspace()
            if let activeUUID = selectedThreadUUID {
                if let transcript = try? await client.openThread(activeUUID),
                   selectedThreadUUID == activeUUID {
                    self.activeTranscript = transcript
                }
            }
            if terminalVisible {
                await refreshTerminals()
            }

            for entry in finishedTurns {
                if let uuid = UUID(uuidString: entry.threadID),
                   let summary = workspace.threads.first(where: { $0.id == uuid })
                {
                    onAgentTurnFinished?(summary)
                }
            }
        }
    }

    private func notePollSuccess() {
        consecutivePollFailures = 0
        lastPollError = nil
    }

    private func recordPollFailure(_ message: String) {
        guard runtime != nil else { return }
        consecutivePollFailures += 1
        lastPollError = message
    }

    public func retryDaemonConnection() async {
        guard !daemonReconnectInFlight else { return }
        daemonReconnectInFlight = true
        defer { daemonReconnectInFlight = false }
        daemonOpenFailure = nil
        consecutivePollFailures = 0
        lastPollError = nil
        if runtime == nil {
            await bootstrap(dataDir: bootstrapDataDir)
        } else if let client = runtime {
            do {
                status = try await client.pollStatus()
                notePollSuccess()
            } catch {
                recordPollFailure(ErrorSanitizer.displayMessage(for: error))
            }
        }
    }

    public func shutdown() async {
        pollTask?.cancel()
        pollTask = nil
        if let taskManager = assistantTaskManager {
            await taskManager.stopPolling()
        }
        assistantTaskManager = nil
        assistantChangeLedger = nil
        toastDismissTask?.cancel()
        await voiceDictation.cancelRecording()
        if let client = runtime {
            runtime = nil
            isBootstrapped = false
            await client.close()
        }
    }

    public func applyAppearanceToNSApp() {
        guard NSApp != nil else { return }
        NSApp.appearance = appearancePreference.nsAppearance
    }

    // MARK: - Workspace, Projects, Threads & Bots

    public func refreshWorkspace() async {
        guard let client = runtime else { return }
        do {
            let ws = try await client.fetchWorkspace(includeArchived: showArchivedThreads)
            self.workspace = ws
        } catch {
            self.lastError = ErrorSanitizer.displayMessage(for: error)
        }
    }

    public func selectThread(_ threadUUID: UUID?) {
        selectedThreadID = threadUUID?.uuidString
    }

    public func selectThread(_ threadID: String?) {
        selectedThreadID = threadID
    }

    public func selectNextThread() {
        let list = filteredThreads
        guard !list.isEmpty else { return }
        guard let current = selectedThreadUUID,
              let idx = list.firstIndex(where: { $0.id == current })
        else {
            selectThread(list.first?.id)
            return
        }
        let nextIdx = (idx + 1) % list.count
        selectThread(list[nextIdx].id)
    }

    public func selectPreviousThread() {
        let list = filteredThreads
        guard !list.isEmpty else { return }
        guard let current = selectedThreadUUID,
              let idx = list.firstIndex(where: { $0.id == current })
        else {
            selectThread(list.last?.id)
            return
        }
        let prevIdx = (idx - 1 + list.count) % list.count
        selectThread(list[prevIdx].id)
    }

    private func handleSelectedThreadChanged() async {
        await voiceDictation.cancelRecording()
        guard let client = runtime else { return }
        guard let uuid = selectedThreadUUID else {
            activeTranscript = nil
            activeCheckout = nil
            activeComposerNotice = nil
            activeDiff = nil
            activeGitState = nil
            return
        }

        isLoadingTranscript = true
        defer { isLoadingTranscript = false }

        do {
            let transcript = try await client.openThread(uuid)
            guard self.selectedThreadUUID == uuid else { return }
            self.activeTranscript = transcript
            _ = try? await client.markSeen(uuid)
            async let checkoutTask = try? client.fetchCheckout(thread: uuid)
            async let noticeTask = try? client.fetchComposerNotice(thread: uuid)
            let (checkout, notice) = await (checkoutTask, noticeTask)
            if self.selectedThreadUUID == uuid {
                self.activeCheckout = checkout
                self.activeComposerNotice = notice
            }
            if inspectorVisible {
                await refreshActiveInspectorData()
            }
            if terminalVisible {
                await refreshTerminals()
            }
        } catch {
            self.lastError = ErrorSanitizer.displayMessage(for: error)
        }
    }

    @discardableResult
    public func createNewThread(in projectID: UUID? = nil, allowedTools: [String]? = nil, assistantId: String? = nil) async -> UUID? {
        guard let client = runtime else { return nil }
        let resolvedProject: UUID? = projectID ?? {
            if let proj = selectedProject, !proj.isChats { return proj.id }
            return nil
        }()
        do {
            let prompt = agentToolset == .system ? systemPromptForSelectedThread.text : nil
            let newID = try await client.newThread(projectID: resolvedProject, systemPrompt: prompt, toolset: agentToolset, allowedTools: allowedTools, assistantId: assistantId)
            await refreshWorkspace()
            selectThread(newID)
            return newID
        } catch {
            presentError(error)
            return nil
        }
    }

    public func systemPrompt(for request: String?, provider: String?, model: String?, assistant: AssistantPromptDescriptor? = nil) -> SystemPrompt {
        let effectiveRequest = [assistant?.systemPrompt, request]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return systemAssets.systemPrompt(for: effectiveRequest.isEmpty ? nil : effectiveRequest, provider: provider, model: model, assistant: assistant)
    }

    public var systemPromptForSelectedThread: SystemPrompt {
        systemPrompt(for: selectedThread)
    }

    public func invalidateSystemPromptCache(for threadID: UUID? = nil) {
        if let threadID {
            systemPromptCache.invalidate(threadID: threadID)
        } else {
            systemPromptCache.invalidateAll()
        }
    }

    private func assistantDescriptor(for thread: RemoteThreadSummary) -> AssistantPromptDescriptor? {
        guard let assistantId = thread.assistantId, let id = UUID(uuidString: assistantId) else {
            return nil
        }
        return assistants.first { $0.id == id }.map { AssistantPromptDescriptor($0) }
    }

    private func systemPromptCacheKey(for thread: RemoteThreadSummary) -> SystemPromptCacheKey? {
        let descriptor: AssistantPromptDescriptor?
        if thread.assistantId != nil {
            guard let resolved = assistantDescriptor(for: thread) else {
                return nil
            }
            descriptor = resolved
        } else {
            descriptor = nil
        }
        return SystemPromptCacheKey(
            threadID: thread.id,
            assistantID: thread.assistantId,
            assistantName: descriptor?.name ?? "",
            assistantRoleText: descriptor?.systemPrompt ?? "",
            assistantExtraAssetFileNames: descriptor?.extraAssetFileNames ?? [],
            provider: thread.selection.provider,
            model: thread.selection.modelID,
            toolset: thread.toolset,
            allowedTools: (thread.allowedTools ?? []).sorted(),
            indexVersion: systemAssets.indexHealth.indexVersion
        )
    }

    public func toolset(for thread: RemoteThreadSummary?) -> AgentToolset {
        AgentToolset.effective(stored: thread?.toolset)
    }

    public func systemPrompt(for thread: RemoteThreadSummary?) -> SystemPrompt {
        guard let thread, let key = systemPromptCacheKey(for: thread) else {
            return systemAssets.systemPrompt(for: nil, provider: thread?.selection.provider, model: thread?.selection.modelID)
        }
        if let cached = systemPromptCache.prompt(for: key) {
            return cached
        }
        let prompt = systemPrompt(for: nil, provider: thread.selection.provider, model: thread.selection.modelID, assistant: assistantDescriptor(for: thread))
        systemPromptCache.store(prompt, for: key)
        return prompt
    }

    public func promptAddProjectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add Project Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task { await addProject(at: url.path) }
        }
    }

    @discardableResult
    public func addProject(at path: String, name: String? = nil) async -> UUID? {
        guard let client = runtime else { return nil }
        do {
            let id = try await client.createProject(path: path, name: name)
            await refreshWorkspace()
            let prompt = agentToolset == .system ? systemPromptForSelectedThread.text : nil
            let allowedTools = agentToolset == .system ? selectedThread?.allowedTools : nil
            let newThread = try? await client.newThread(projectID: id, systemPrompt: prompt, toolset: agentToolset, allowedTools: allowedTools)
            await refreshWorkspace()
            if let newThread {
                selectThread(newThread)
            }
            presentToast("Project Added", detail: (path as NSString).lastPathComponent, style: .success)
            return id
        } catch {
            presentError(error)
            return nil
        }
    }

    public func removeProject(_ projectID: UUID) async {
        guard let client = runtime else { return }
        do {
            try await client.removeProject(projectID: projectID)
            await refreshWorkspace()
            if selectedThread == nil {
                selectThread(workspace.threads.first?.id)
            }
        } catch {
            presentError(error)
        }
    }

    public func setProjectExpanded(_ projectID: UUID, expanded: Bool) async {
        guard let client = runtime else { return }
        do {
            try await client.setProjectExpanded(projectID: projectID, expanded: expanded)
            await refreshWorkspace()
        } catch {
            presentError(error)
        }
    }

    public func performThreadAction(_ action: RemoteThreadAction, on threadID: UUID) async {
        guard let client = runtime else { return }
        if case .delete = action {
            await deleteThreadPermanently(threadID.uuidString)
            return
        }
        do {
            try await client.performThreadAction(thread: threadID, action: action)
            await refreshWorkspace()
            if selectedThreadUUID == threadID {
                await handleSelectedThreadChanged()
            }
        } catch {
            presentError(error)
        }
    }

    public func updateStoredPrompt(threadID: UUID, prompt: String, allowedTools: [String]? = nil) async {
        guard let client = runtime else { return }
        do {
            try await client.updateStoredPrompt(threadID: threadID, prompt: prompt, allowedTools: allowedTools)
            systemPromptCache.invalidate(threadID: threadID)
            await refreshWorkspace()
            if selectedThreadUUID == threadID {
                await handleSelectedThreadChanged()
            }
        } catch {
            presentError(error)
        }
    }

    public func deleteThreadPermanently(_ threadID: String) async {
        guard let client = runtime else { return }
        do {
            let wasSelected = selectedThreadID?.caseInsensitiveCompare(threadID) == .orderedSame
            let undoID = try await client.deleteThreadPermanently(threadID: threadID)
            if let uuid = UUID(uuidString: threadID) {
                systemPromptCache.invalidate(threadID: uuid)
            }
            await refreshWorkspace()
            if wasSelected {
                selectThread(workspace.threads.first(where: { !$0.isArchived })?.id)
            }
            presentToast(
                "Conversation Deleted",
                style: .info,
                undoActionTitle: "Undo"
            ) { [weak self] in
                Task { await self?.undoDeleteThread(undoID: undoID) }
            }
        } catch {
            presentError(error)
        }
    }

    public func undoDeleteThread(undoID: String? = nil) async {
        guard let client = runtime else { return }
        do {
            let restored = try await client.undoDeleteThread(undoID: undoID)
            await refreshWorkspace()
            if let first = restored.first {
                selectThread(first)
            }
            presentToast("Conversation Restored", style: .success)
        } catch {
            presentError(error)
        }
    }

    @discardableResult
    public func forkThread(_ threadID: UUID, itemID: UUID? = nil) async -> UUID? {
        guard let client = runtime else { return nil }
        do {
            let forked = try await client.forkThread(RemoteForkRequest(threadID: threadID, itemID: itemID))
            await refreshWorkspace()
            selectThread(forked)
            presentToast("Forked Conversation", style: .success)
            return forked
        } catch {
            presentError(error)
            return nil
        }
    }

    public func openBotEditor(for bot: RemoteBot? = nil) {
        editingBot = bot
        showBotEditor = true
    }

    public func startBotConversation(_ botID: UUID) async {
        guard let client = runtime else { return }
        do {
            let tid = try await client.newBotConversation(botID: botID)
            await refreshWorkspace()
            selectThread(tid)
        } catch {
            presentError(error)
        }
    }

    public func launchAssistant(_ assistant: RemoteAssistant, modelConfig: AssistantModelConfig? = nil, task: String, in projectID: UUID? = nil) async {
        guard let client = runtime else { return }
        guard !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentError(AgentsRuntimeError.desktopFailure("Task text is empty"))
            return
        }
        do {
            let resolvedConfig = (modelConfig ?? AssistantModelConfig(provider: assistant.provider, model: assistant.model))
                .resolvingCurrent(provider: selectedThread?.selection.provider, model: selectedThread?.selection.modelID)
            let selection = resolvedConfig.selectionOverride
            let composed = systemPrompt(
                for: nil,
                provider: resolvedConfig.provider,
                model: resolvedConfig.model,
                assistant: AssistantPromptDescriptor(assistant)
            )
            let prompt = composed.text
            let threadID = try await client.newThread(
                projectID: projectID,
                systemPrompt: prompt,
                toolset: .system,
                allowedTools: assistant.allowedTools,
                assistantId: assistant.id.uuidString,
                selection: selection
            )
            await refreshWorkspace()
            selectThread(threadID)
            if let summary = workspace.threads.first(where: { $0.id == threadID }) {
                _ = systemPrompt(for: summary)
            }
            if let ledger = assistantChangeLedger {
                try? await ledger.beginRun(runId: threadID.uuidString, assistantId: assistant.id.uuidString, permissionProfile: assistant.permissionProfile)
            }
            _ = await sendMessage(text: task, to: threadID)
            if let ledger = assistantChangeLedger {
                _ = await ledger.finishRun(runId: threadID.uuidString)
            }
        } catch {
            presentError(error)
        }
    }

    @discardableResult
    public func saveBot(_ draft: RemoteBotDraft) async -> UUID? {
        guard let client = runtime else { return nil }
        do {
            let id = try await client.saveBot(draft)
            await refreshWorkspace()
            showBotEditor = false
            editingBot = nil
            presentToast("Saved Bot", detail: draft.name, style: .success)
            return id
        } catch {
            presentError(error)
            return nil
        }
    }

    public func deleteBot(_ botID: UUID, deletesConversations: Bool = false) async {
        guard let client = runtime else { return }
        do {
            try await client.deleteBot(botID, deletesConversations: deletesConversations)
            await refreshWorkspace()
            presentToast("Bot Deleted", style: .info)
        } catch {
            presentError(error)
        }
    }

    // MARK: - Conversation, Composer, Approvals, Questions & Rewind

    @discardableResult
    public func sendMessage(
        text: String,
        images: [RemoteImage] = [],
        delivery: RemoteSendRequest.Delivery = .automatic,
        to threadID: UUID? = nil
    ) async -> String? {
        guard let client = runtime else {
            presentDaemonUnavailable()
            return nil
        }
        let targetThread: UUID?
        if let threadID {
            targetThread = threadID
        } else if let current = selectedThreadUUID {
            targetThread = current
        } else {
            targetThread = await createNewThread()
        }
        guard let targetThread else { return nil }

        let targetSummary = workspace.threads.first { $0.id == targetThread }
        let effectiveToolset = toolset(for: targetSummary)
        let systemPromptText: String? = effectiveToolset == .system ? systemPrompt(for: targetSummary).text : nil
        let allowedTools: [String]? = effectiveToolset == .system ? targetSummary?.allowedTools : nil

        do {
            let outcome = try await client.send(
                RemoteSendRequest(threadID: targetThread, text: text, images: images, delivery: delivery, systemPrompt: systemPromptText, allowedTools: allowedTools)
            )
            boostPollForNewActivity()
            await refreshWorkspace()
            if selectedThreadUUID == targetThread,
               let transcript = try? await client.openThread(targetThread) {
                activeTranscript = transcript
            }
            return outcome
        } catch {
            presentError(error)
            return nil
        }
    }

    public func stopActiveTurn(threadID: UUID? = nil) async {
        guard let client = runtime, let tid = threadID ?? selectedThreadUUID else { return }
        do {
            try await client.stop(thread: tid)
            pollFastUntil = .distantPast
            if selectedThreadUUID == tid,
               let transcript = try? await client.openThread(tid) {
                activeTranscript = transcript
            }
            await refreshWorkspace()
        } catch {
            presentError(error)
        }
    }

    public func steerQueuedMessage(_ messageID: UUID, threadID: UUID? = nil) async {
        guard let client = runtime, let tid = threadID ?? selectedThreadUUID else { return }
        do {
            try await client.steerQueued(thread: tid, message: messageID)
            if let transcript = try? await client.openThread(tid), selectedThreadUUID == tid {
                activeTranscript = transcript
            }
        } catch {
            presentError(error)
        }
    }

    public func removeQueuedMessage(_ messageID: UUID, threadID: UUID? = nil) async {
        guard let client = runtime, let tid = threadID ?? selectedThreadUUID else { return }
        do {
            try await client.removeQueued(thread: tid, message: messageID)
            if let transcript = try? await client.openThread(tid), selectedThreadUUID == tid {
                activeTranscript = transcript
            }
        } catch {
            presentError(error)
        }
    }

    @discardableResult
    public func respondToApproval(
        itemID: UUID,
        optionID: String,
        text: String? = nil,
        threadID: UUID? = nil
    ) async -> Bool {
        guard let client = runtime, let tid = threadID ?? selectedThreadUUID else { return false }
        do {
            try await client.respond(thread: tid, requestID: itemID, optionID: optionID, text: text)
            boostPollForNewActivity()
            if let transcript = try? await client.openThread(tid), selectedThreadUUID == tid {
                activeTranscript = transcript
            }
            await refreshWorkspace()
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    @discardableResult
    public func answerQuestion(
        itemID: UUID,
        answers: [String: [String]],
        threadID: UUID? = nil
    ) async -> Bool {
        guard let client = runtime, let tid = threadID ?? selectedThreadUUID else { return false }
        do {
            try await client.answer(thread: tid, requestID: itemID, answers: answers)
            boostPollForNewActivity()
            if let transcript = try? await client.openThread(tid), selectedThreadUUID == tid {
                activeTranscript = transcript
            }
            await refreshWorkspace()
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    @discardableResult
    public func dismissQuestion(itemID: UUID, threadID: UUID? = nil) async -> Bool {
        guard let client = runtime, let tid = threadID ?? selectedThreadUUID else { return false }
        do {
            try await client.dismissQuestion(thread: tid, requestID: itemID)
            if let transcript = try? await client.openThread(tid), selectedThreadUUID == tid {
                activeTranscript = transcript
            }
            await refreshWorkspace()
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    public func updateThreadSettings(_ settings: RemoteThreadSettings) async {
        guard let client = runtime else { return }
        do {
            try await client.updateThreadSettings(settings)
            await refreshWorkspace()
            if selectedThreadUUID == settings.threadID,
               let transcript = try? await client.openThread(settings.threadID) {
                activeTranscript = transcript
            }
        } catch {
            presentError(error)
        }
    }

    public func loadEarlierMessages(limit: Int = 200) async {
        guard let client = runtime,
              let tid = selectedThreadUUID,
              let transcript = activeTranscript,
              transcript.hasEarlier,
              let firstIndex = transcript.items.first?.index
        else { return }

        do {
            let page = try await client.loadEarlier(thread: tid, before: firstIndex, limit: limit)
            guard selectedThreadUUID == tid, var current = activeTranscript, current.thread.id == tid else { return }
            var merged = page.items
            let existingIDs = Set(merged.map(\.id))
            merged.append(contentsOf: current.items.filter { !existingIDs.contains($0.id) })
            merged.sort { $0.index < $1.index }
            current.items = merged
            current.hasEarlier = page.hasEarlier
            self.activeTranscript = current
        } catch {
            presentError(error)
        }
    }

    public func changeCheckout(_ action: RemoteCheckoutAction) async {
        guard let client = runtime, let tid = selectedThreadUUID else { return }
        do {
            let updated = try await client.changeCheckout(thread: tid, action: action)
            self.activeCheckout = updated
            await refreshWorkspace()
        } catch {
            presentError(error)
        }
    }

    public func rewindConversation(to itemID: UUID, revertsFiles: Bool) async -> RemoteRewind? {
        guard let client = runtime, let tid = selectedThreadUUID else { return nil }
        do {
            let rw = try await client.rewind(
                RemoteRewindRequest(threadID: tid, itemID: itemID, revertsFiles: revertsFiles)
            )
            if let transcript = try? await client.openThread(tid), selectedThreadUUID == tid {
                activeTranscript = transcript
            }
            await refreshWorkspace()
            if !rw.text.isEmpty {
                insertTextIntoComposer(rw.text)
            }
            return rw
        } catch {
            presentError(error)
            return nil
        }
    }

    public func insertTextIntoComposer(_ text: String) {
        composerInsertedTextRequest = text
    }

    // MARK: - Inspector, Diff, Git, Pull Requests, Files & Schedules

    public func toggleInspector() {
        inspectorVisible.toggle()
        if inspectorVisible {
            Task { await refreshActiveInspectorData() }
        }
    }

    public func openInspector(tab: InspectorTab) {
        inspectorTab = tab
        inspectorVisible = true
        Task { await refreshActiveInspectorData() }
    }

    public func openFileInInspector(path: String, line: Int? = nil, column: Int? = nil) {
        openFileInInspectorRequest = WorkspaceFileOpenRequest(path: path, line: line, column: column)
        inspectorTab = .files
        inspectorVisible = true
    }

    public func refreshActiveInspectorData() async {
        switch inspectorTab {
        case .changes:
            await refreshDiff()
        case .git:
            await refreshGitState()
        case .schedules:
            await refreshScheduledTasks()
        case .pullRequests, .files, .workers, .computerUse, .assistants:
            break
        }
    }

    public func refreshDiff(scope: DiffScope? = nil) async {
        guard let client = runtime, let tid = selectedThreadUUID else { return }
        if let scope { activeDiffScope = scope }
        let requestedScope = activeDiffScope
        do {
            let resolved: RemoteDiff
            switch requestedScope {
            case .branch:
                let value = try await client.runWorkspaceOperation(
                    method: "git.diff.branch",
                    params: ["threadId": .string(tid.uuidString.lowercased())]
                )
                let patch = value["patch"]?.stringValue ?? ""
                let base = value["baseLabel"]?.stringValue ?? "base"
                resolved = RemoteDiffParsing.split(patch, title: "Branch vs \(base)")
            case .compare(let from, let to):
                let value = try await client.runWorkspaceOperation(
                    method: "git.diff.range",
                    params: [
                        "threadId": .string(tid.uuidString.lowercased()),
                        "from": .string(from),
                        "to": .string(to),
                    ]
                )
                let patch = value["diff"]?.stringValue ?? ""
                resolved = RemoteDiffParsing.split(patch, title: "Compare \(from)…\(to)")
            default:
                resolved = try await client.fetchDiff(thread: tid, scope: requestedScope)
            }
            if selectedThreadUUID == tid && activeDiffScope == requestedScope {
                activeDiff = resolved
            }
        } catch {
            self.lastError = ErrorSanitizer.displayMessage(for: error)
        }
    }

    public func refreshGitState() async {
        guard let client = runtime, let tid = selectedThreadUUID else { return }
        do {
            let state = try await client.fetchGitState(thread: tid)
            if selectedThreadUUID == tid {
                activeGitState = state
            }
        } catch {
            self.lastError = ErrorSanitizer.displayMessage(for: error)
        }
    }

    @discardableResult
    public func performGitAction(
        _ action: RemoteGitActionRequest.Action,
        message: String? = nil,
        featureBranch: Bool = false
    ) async -> RemoteGitActionResult? {
        guard let client = runtime, let tid = selectedThreadUUID else { return nil }
        do {
            let outcome = try await client.performGitAction(
                RemoteGitActionRequest(
                    threadID: tid,
                    action: action,
                    message: message,
                    featureBranch: featureBranch
                )
            )
            await refreshGitState()
            await refreshDiff()
            await refreshWorkspace()
            presentToast(outcome.title, detail: outcome.detail, style: .success)
            return outcome
        } catch {
            presentError(error)
            return nil
        }
    }

    public func refreshScheduledTasks() async {
        guard let client = runtime else { return }
        if let tasks = try? await client.fetchScheduledTasks() {
            self.scheduledTasks = tasks
        }
    }

    public func refreshAssistants() async {
        defer { assistantsLoaded = true }
        guard let client = runtime else { return }
        if let assistants = try? await client.listAssistants() {
            self.assistants = assistants.assistants
        }
    }

    private func setupAssistantManagers() async {
        guard let client = runtime else { return }
        if assistantChangeLedger == nil {
            assistantChangeLedger = AssistantChangeLedger(runtime: client)
        }
        if assistantTaskManager == nil {
            assistantTaskManager = AssistantTaskManager(
                runtime: client, notifications: AssistantNotificationManager()
            )
            await assistantTaskManager?.startPolling()
        }
    }

    private func recoverAssistantTasks() async {
        guard let manager = assistantTaskManager else { return }
        _ = try? await manager.recover()
    }

    public func openAssistantEditor(for definition: AssistantDefinition?) {
        editingAssistantDefinition = definition
        showAssistantEditor = true
    }

    public func closeAssistantEditor() {
        showAssistantEditor = false
        editingAssistantDefinition = nil
    }

    public func openAssistantTasks() {
        guard assistantTaskManager != nil else { return }
        showAssistantTasks = true
    }

    public func closeAssistantTasks() {
        showAssistantTasks = false
    }

    public func openAssistantLaunch(for definition: AssistantDefinition, paths: [String] = [], task: String = "") {
        launchingAssistantDefinition = definition
        launchingAssistantPaths = paths
        launchingAssistantTask = task
        showAssistantLaunch = true
    }

    public func closeAssistantLaunch() {
        showAssistantLaunch = false
        launchingAssistantDefinition = nil
        launchingAssistantPaths = []
        launchingAssistantTask = ""
    }

    public func dismissAssistantResult() {
        showAssistantResult = false
        assistantResultReport = nil
    }

    public func presentAssistantResult(for record: WorkerRecord) async {
        guard let assistantID = record.assistantId else { return }
        let definition: AssistantDefinition?
        if let persistenceID = UUID(uuidString: assistantID) {
            definition = assistantCatalog.definition(forPersistenceID: persistenceID)
                ?? assistantCatalog.definition(forStableID: assistantID)
        } else {
            definition = assistantCatalog.definition(forStableID: assistantID)
        }
        guard let definition, let client = runtime else { return }
        var transcriptItems: [RemoteItem]? = nil
        var diff: RemoteDiff? = nil
        if let workerThreadID = UUID(uuidString: record.threadId) {
            if let transcript = try? await client.openThread(workerThreadID) {
                transcriptItems = transcript.items
            }
            diff = try? await client.fetchDiff(thread: workerThreadID, scope: .uncommitted)
        }
        assistantResultReport = AssistantReportBuilder.build(AssistantReportBuilder.Input(
            record: record,
            definition: definition,
            transcriptItems: transcriptItems,
            diff: diff
        ))
        showAssistantResult = true
    }

    public static func unknownAllowedTools(in draft: RemoteAssistantDraft) -> [String] {
        unknownAllowedTools(in: draft.allowedTools)
    }

    public static func unknownAllowedTools(in tools: [String]?) -> [String] {
        SystemToolRegistry.unknownToolNames(in: tools)
    }

    @discardableResult
    public func saveAssistant(_ draft: RemoteAssistantDraft) async -> UUID? {
        guard let client = runtime else { return nil }
        let unknown = Self.unknownAllowedTools(in: draft)
        guard unknown.isEmpty else {
            presentError(AgentsRuntimeError.desktopFailure(
                "Unknown assistant tools: \(unknown.joined(separator: ", ")). Assistants can only use tools from the system toolset."
            ))
            return nil
        }
        do {
            let id = try await client.saveAssistant(draft)
            await refreshAssistants()
            presentToast("Saved Assistant", detail: draft.name, style: .success)
            return id
        } catch {
            presentError(error)
            return nil
        }
    }

    public func deleteAssistant(_ assistant: RemoteAssistant) async {
        guard let client = runtime else { return }
        do {
            try await client.deleteAssistant(assistant.id)
            await refreshAssistants()
            presentToast("Assistant Deleted", style: .info)
        } catch {
            presentError(error)
        }
    }

    public func saveScheduledTask(_ draft: RemoteScheduledTaskDraft) async {
        guard let client = runtime else { return }
        do {
            self.scheduledTasks = try await client.saveScheduledTask(draft)
            await refreshWorkspace()
            presentToast("Saved Schedule", detail: draft.name, style: .success)
        } catch {
            presentError(error)
        }
    }

    public func performScheduledTaskAction(_ command: RemoteScheduledTaskCommand) async {
        guard let client = runtime else { return }
        do {
            self.scheduledTasks = try await client.performScheduledTaskAction(command)
            await refreshWorkspace()
        } catch {
            presentError(error)
        }
    }

    public func approveSchedule(_ id: String) async {
        guard let client = runtime else { return }
        do {
            try await client.approveSchedule(id: id)
            await refreshScheduledTasks()
            presentToast("Schedule Approved", style: .success)
        } catch {
            presentError(error)
        }
    }

    // MARK: - Integrated PTY Terminal Operations

    public func toggleTerminal() {
        terminalVisible.toggle()
        if terminalVisible {
            Task {
                await refreshTerminals()
                if activeTerminals.isEmpty {
                    await createTerminalForSelectedThread()
                }
            }
        }
    }

    @discardableResult
    public func createTerminalForSelectedThread() async -> String? {
        guard let client = runtime else { return nil }
        do {
            let id = try await client.createTerminal(threadID: selectedThreadID)
            await refreshTerminals()
            selectedTerminalID = id
            terminalVisible = true
            return id
        } catch {
            presentError(error)
            return nil
        }
    }

    public func refreshTerminals() async {
        guard let client = runtime else { return }
        if let list = try? await client.listTerminals(threadID: selectedThreadID) {
            self.activeTerminals = list
            if selectedTerminalID == nil || !list.contains(where: { $0.id == selectedTerminalID }) {
                selectedTerminalID = list.first?.id
            }
        }
    }

    public func closeTerminal(_ id: String) async {
        guard let client = runtime else { return }
        do {
            try await client.closeTerminal(id: id)
            await refreshTerminals()
        } catch {
            presentError(error)
        }
    }

    public func sendTerminalContextToComposer(_ output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insertTextIntoComposer("\n```sh\n\(trimmed)\n```\n")
    }

    public func runProjectScript(_ script: RemoteScript, projectID: UUID) async {
        guard let client = runtime, let tid = selectedThreadUUID else { return }
        do {
            try await client.runScript(projectID: projectID, scriptID: script.id, threadID: tid)
            terminalVisible = true
            await refreshTerminals()
        } catch {
            presentError(error)
        }
    }

    // MARK: - Providers, ACP Registry, Models, Remote & Legacy Import

    public func refreshProviders() async {
        guard let client = runtime else { return }
        do {
            self.providers = try await client.listAllProviders()
        } catch {
            presentError(error)
        }
    }

    public func refreshACPRegistry(force: Bool = false) async {
        guard let client = runtime else { return }
        do {
            self.acpRegistry = try await client.fetchACPRegistry(refresh: force)
        } catch {
            presentError(error)
        }
    }

    public func registerACPAgent(_ agentID: String) async {
        guard let client = runtime else { return }
        do {
            _ = try await client.registerACPAgent(agentID: agentID)
            await refreshACPRegistry(force: false)
            await refreshProviders()
            await refreshWorkspace()
            presentToast("Registered ACP Agent", detail: agentID, style: .success)
        } catch {
            presentError(error)
        }
    }

    public func refreshRemoteServer() async {
        guard let client = runtime else { return }
        if let snap = try? await client.fetchRemoteServerStatus() {
            self.remoteServer = snap
        }
    }

    public func setRemoteServerEnabled(_ enabled: Bool) async {
        guard let client = runtime else { return }
        do {
            self.remoteServer = try await client.setRemoteServerEnabled(enabled)
        } catch {
            presentError(error)
        }
    }

    public func beginRemotePairing() async {
        guard let client = runtime else { return }
        do {
            self.remoteServer = try await client.beginRemotePairing()
        } catch {
            presentError(error)
        }
    }

    public func cancelRemotePairing() async {
        guard let client = runtime else { return }
        do {
            self.remoteServer = try await client.cancelRemotePairing()
        } catch {
            presentError(error)
        }
    }

    public func revokeRemoteDevice(_ deviceID: String) async {
        guard let client = runtime else { return }
        do {
            self.remoteServer = try await client.revokeRemoteDevice(deviceID: deviceID)
            presentToast("Device Revoked", style: .info)
        } catch {
            presentError(error)
        }
    }

    public func importLegacyWorkspace() async {
        guard let client = runtime else { return }
        do {
            let report = try await client.importLegacyWorkspace()
            await refreshWorkspace()
            presentToast(
                "Legacy Workspace Imported",
                detail: "\(report.importedProjects) projects, \(report.importedThreads) threads, \(report.importedBots) bots",
                style: .success
            )
        } catch {
            presentError(error)
        }
    }

    // MARK: - Zoom & Toast Helpers

    public func increaseFontScale() {
        fontScale = min(1.5, (fontScale * 10 + 1).rounded() / 10)
    }

    public func decreaseFontScale() {
        fontScale = max(0.8, (fontScale * 10 - 1).rounded() / 10)
    }

    public func resetFontScale() {
        fontScale = 1.0
    }

    public func presentError(_ error: Error) {
        let message = ErrorSanitizer.displayMessage(for: error)
        self.lastError = message
        presentToast("Action Failed", detail: message, style: .error)
    }

    private func presentDaemonUnavailable() {
        let connectionStatus = daemonConnectionStatus
        presentToast(
            connectionStatus.title,
            detail: connectionStatus.detail ?? "The Agents runtime has not started yet. Try again in a moment.",
            style: .error
        )
    }

    public func presentToast(
        _ title: String,
        detail: String? = nil,
        style: ToastMessage.Style = .info,
        undoActionTitle: String? = nil,
        onUndo: (@MainActor () -> Void)? = nil
    ) {
        toastDismissTask?.cancel()
        toastUndoHandler = onUndo
        let toast = ToastMessage(
            title: title,
            detail: detail,
            style: style,
            undoActionTitle: undoActionTitle
        )
        toastMessage = toast
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undoActionTitle != nil ? 6 : 4))
            guard !Task.isCancelled else { return }
            if self?.toastMessage?.id == toast.id {
                self?.toastMessage = nil
                self?.toastUndoHandler = nil
            }
        }
    }

    public func performToastUndo() {
        let handler = toastUndoHandler
        dismissToast()
        handler?()
    }

    public func dismissToast() {
        toastDismissTask?.cancel()
        toastMessage = nil
        toastUndoHandler = nil
    }
}
