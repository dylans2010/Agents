import AppKit
import CoincideRemoteKit
import SwiftUI

public extension Notification.Name {
    static let coincideFocusSidebarSearch = Notification.Name("com.apoorvdarshan.coincide.focusSidebarSearch")
}

public extension AppModel {
    /// Creates a new projectless chat conversation (`RemoteRequest.newThread` with the selected toolset),
    /// bypassing `selectedProject` fallback.
    @discardableResult
    func createNewChat() async -> UUID? {
        guard let client = runtime else { return nil }
        do {
            let prompt = agentToolset == .system ? systemPromptForSelectedThread.text : nil
            let newID = try await client.newThread(projectID: nil, systemPrompt: prompt, toolset: agentToolset)
            await refreshWorkspace()
            selectThread(newID)
            return newID
        } catch {
            presentError(error)
            return nil
        }
    }
}

public struct SidebarRootView: View {
    @Bindable public var appModel: AppModel

    @AppStorage("coincide.dismissedLegacyImportBanner") private var dismissedLegacyImportBanner: Bool = false
    @AppStorage(AssistantLibrarySidebarSelection.userDefaultsKey) private var librarySelectionRaw: String = ""
    @State private var isImportingLegacy: Bool = false
    @State private var isSearchPresented: Bool = false

    @State private var expandedProjectOverrides: [UUID: Bool] = [:]
    @State private var expandedFullThreadListProjects: Set<UUID> = []
    @State private var configuringProject: RemoteProject?
    @State private var pendingRemoveProject: RemoteProject?
    @State private var pendingDeleteBot: RemoteBot?

    private static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    // MARK: - Partitioned Sidebar Data

    private var trimmedQuery: String {
        appModel.sidebarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var librarySelection: AssistantLibrarySidebarSelection? {
        get { AssistantLibrarySidebarSelection(storedValue: librarySelectionRaw) }
        set { librarySelectionRaw = newValue?.storedValue ?? "" }
    }

    private var libraryRecentCount: Int {
        UserDefaults.standard.stringArray(forKey: AssistantLibraryViewModel.recentIDsDefaultsKey)?.count ?? 0
    }

    private var searchDisplayQuery: String {
        appModel.sidebarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearchResults: Bool {
        !filteredBots.isEmpty
            || !pinnedThreads.isEmpty
            || !chatThreads.isEmpty
            || !snoozedThreads.isEmpty
            || !archivedThreads.isEmpty
            || regularProjects.contains { project in
                !threads(for: project).isEmpty
                    || project.name.lowercased().contains(trimmedQuery)
                    || project.path.lowercased().contains(trimmedQuery)
            }
    }

    private var regularProjects: [RemoteProject] {
        appModel.workspace.projects.filter { !$0.isChats }
    }

    private var regularProjectMap: [UUID: RemoteProject] {
        Dictionary(uniqueKeysWithValues: regularProjects.map { ($0.id, $0) })
    }

    private var filteredBots: [RemoteBot] {
        let bots = appModel.workspace.bots ?? []
        guard !trimmedQuery.isEmpty else { return bots }
        return bots.filter { bot in
            bot.name.lowercased().contains(trimmedQuery)
                || (bot.persona?.lowercased().contains(trimmedQuery) ?? false)
        }
    }

    private var archivedThreads: [RemoteThreadSummary] {
        guard appModel.showArchivedThreads else { return [] }
        return appModel.filteredThreads
            .filter(\.isArchived)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var snoozedThreads: [RemoteThreadSummary] {
        let now = Date()
        return appModel.filteredThreads
            .filter { !$0.isArchived && (($0.snoozedUntil ?? .distantPast) > now) }
            .sorted { ($0.snoozedUntil ?? .distantFuture) < ($1.snoozedUntil ?? .distantFuture) }
    }

    private var activeNonSnoozedThreads: [RemoteThreadSummary] {
        let now = Date()
        return appModel.filteredThreads.filter { thread in
            !thread.isArchived && ((thread.snoozedUntil ?? .distantPast) <= now)
        }
    }

    private var pinnedThreads: [RemoteThreadSummary] {
        let pinned = activeNonSnoozedThreads.filter(\.isPinned)
        let orderIndex = Dictionary(
            uniqueKeysWithValues: appModel.workspace.pinnedOrder.enumerated().map { ($1, $0) }
        )
        return pinned.sorted { lhs, rhs in
            switch (orderIndex[lhs.id], orderIndex[rhs.id]) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    private var unpinnedActiveThreads: [RemoteThreadSummary] {
        activeNonSnoozedThreads.filter { !$0.isPinned }
    }

    private func threads(for project: RemoteProject) -> [RemoteThreadSummary] {
        unpinnedActiveThreads.filter { $0.projectID == project.id && $0.projectID != Self.zeroUUID }
    }

    private var chatThreads: [RemoteThreadSummary] {
        let validProjectIDs = Set(regularProjects.map(\.id))
        return unpinnedActiveThreads.filter { thread in
            thread.projectID == Self.zeroUUID || !validProjectIDs.contains(thread.projectID)
        }
    }

    private var shouldShowLegacyImportCard: Bool {
        appModel.status.legacyImportAvailable
            && appModel.workspace.threads.isEmpty
            && !dismissedLegacyImportBanner
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            if shouldShowLegacyImportCard {
                legacyImportCalloutCard
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            List(selection: $appModel.selectedThreadID) {
                if !trimmedQuery.isEmpty && !hasSearchResults {
                    ContentUnavailableView {
                        Label("No results for '\(searchDisplayQuery)'", systemImage: "magnifyingglass")
                    } actions: {
                        Button("Clear Search") {
                            appModel.sidebarSearchQuery = ""
                        }
                    }
                } else {
                    botsSection

                    if trimmedQuery.isEmpty {
                        librarySection
                    }

                    if !pinnedThreads.isEmpty {
                        pinnedSection
                    }

                    projectsSection

                    chatsSection

                    if !snoozedThreads.isEmpty {
                        snoozedSection
                    }

                    if appModel.showArchivedThreads {
                        archivedSection
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(
                text: $appModel.sidebarSearchQuery,
                isPresented: $isSearchPresented,
                placement: .sidebar,
                prompt: "Filter threads…"
            )

            Divider()

            bottomActionBar
        }
        .onReceive(NotificationCenter.default.publisher(for: .coincideFocusSidebarSearch)) { _ in
            isSearchPresented = true
        }
        .sheet(item: $configuringProject) { project in
            ProjectSettingsSheet(appModel: appModel, project: project)
        }
        .confirmationDialog(
            "Remove Project from Agents?",
            isPresented: Binding(
                get: { pendingRemoveProject != nil },
                set: { if !$0 { pendingRemoveProject = nil } }
            ),
            presenting: pendingRemoveProject
        ) { project in
            Button("Remove Project", role: .destructive) {
                pendingRemoveProject = nil
                Task { await appModel.removeProject(project.id) }
            }
            Button("Cancel", role: .cancel) {
                pendingRemoveProject = nil
            }
        } message: { project in
            Text("Removes “\(project.name)” and its conversation history from Agents. Your files at \(project.path) on disk will not be touched.")
        }
        .confirmationDialog(
            "Delete Bot?",
            isPresented: Binding(
                get: { pendingDeleteBot != nil },
                set: { if !$0 { pendingDeleteBot = nil } }
            ),
            presenting: pendingDeleteBot
        ) { bot in
            Button("Delete Bot (Keep Conversations)", role: .destructive) {
                pendingDeleteBot = nil
                Task { await appModel.deleteBot(bot.id, deletesConversations: false) }
            }
            Button("Delete Bot & Conversations", role: .destructive) {
                pendingDeleteBot = nil
                Task { await appModel.deleteBot(bot.id, deletesConversations: true) }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteBot = nil
            }
        } message: { bot in
            Text("Delete “\(bot.name)”? Existing conversations can remain under Chats or be removed permanently.")
        }
    }

    // MARK: - Legacy Workspace Import Callout

    private var legacyImportCalloutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Existing Workspace Found")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)

                    Text("Import your projects, threads, and bots from your previous Agents workspace.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 2)

                Button {
                    dismissedLegacyImportBanner = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }

            Button {
                Task {
                    isImportingLegacy = true
                    defer { isImportingLegacy = false }
                    await appModel.importLegacyWorkspace()
                }
            } label: {
                HStack(spacing: 6) {
                    if isImportingLegacy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 11))
                    }
                    Text(isImportingLegacy ? "Importing…" : "Import Existing Agents Workspace")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isImportingLegacy)
        }
        .padding(10)
        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
    }

    // MARK: - Bots Section

    @ViewBuilder
    private var botsSection: some View {
        let shouldDisplay = !filteredBots.isEmpty || (trimmedQuery.isEmpty && (appModel.workspace.canEditBots ?? true))
        if shouldDisplay {
            Section {
                if filteredBots.isEmpty {
                    Button {
                        appModel.openBotEditor(for: nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .frame(width: 20, height: 20)
                            Text("Create a Bot…")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AppTheme.secondaryLabel)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(filteredBots) { bot in
                        SidebarBotRow(
                            appModel: appModel,
                            bot: bot,
                            onRequestDelete: { pendingDeleteBot = bot }
                        )
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Bots")
                    Spacer()
                    Button {
                        appModel.openBotEditor(for: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .help("New Bot… (⌥⌘N)")
                    .accessibilityLabel("New bot")
                }
            }
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        let catalog = appModel.assistantCatalog
        let favoriteCount = catalog.allDefinitions.filter {
            AssistantLibraryViewModel.isFavorite($0, in: catalog)
        }.count
        let counts = catalog.allDefinitions.reduce(into: [AssistantCategory: Int]()) { partial, definition in
            partial[definition.category, default: 0] += 1
        }
        Section {
            SidebarLibraryRow(
                title: "All Assistants",
                systemImage: "square.stack.3d.up",
                count: catalog.allDefinitions.count,
                isSelected: librarySelection == .all
            ) {
                librarySelection = .all
            }

            SidebarLibraryRow(
                title: "Favorites",
                systemImage: "star.fill",
                count: favoriteCount,
                isSelected: librarySelection == .favorites
            ) {
                librarySelection = .favorites
            }

            SidebarLibraryRow(
                title: "Recently Used",
                systemImage: "clock",
                count: libraryRecentCount,
                isSelected: librarySelection == .recent
            ) {
                librarySelection = .recent
            }

            ForEach(AssistantCategory.allCases, id: \.self) { category in
                SidebarLibraryRow(
                    title: category.displayName,
                    systemImage: Self.symbolName(for: category),
                    count: counts[category] ?? 0,
                    isSelected: librarySelection == .category(category)
                ) {
                    librarySelection = .category(category)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text("Library")
                Text("\(catalog.allDefinitions.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                Spacer()
            }
        }
    }

    private nonisolated static func symbolName(for category: AssistantCategory) -> String {
        switch category {
        case .codeMaintenance: "wrench.and.screwdriver"
        case .codeReviewSecurity: "shield.checkered"
        case .buildingFixing: "hammer"
        case .repositoryIntelligence: "magnifyingglass"
        case .gitWorkflowAutomation: "arrow.triangle.2.circlepath"
        case .specializedProductivity: "sparkles"
        }
    }

    // MARK: - Pinned Section

    private var pinnedSection: some View {
        Section("Pinned") {
            ForEach(pinnedThreads) { thread in
                let proj = regularProjectMap[thread.projectID]
                SidebarThreadRow(
                    appModel: appModel,
                    thread: thread,
                    projectPath: proj?.path,
                    showsProjectBadge: proj != nil,
                    projectName: proj?.name
                )
                .tag(thread.id.uuidString)
            }
        }
    }

    // MARK: - Projects Section

    @ViewBuilder
    private var projectsSection: some View {
        Section {
            if regularProjects.isEmpty && trimmedQuery.isEmpty {
                Button {
                    appModel.promptAddProjectFolder()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Text("Add Project Folder…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ForEach(regularProjects) { project in
                    let projectThreads = threads(for: project)
                    let matchesProjectQuery = trimmedQuery.isEmpty
                        || project.name.lowercased().contains(trimmedQuery)
                        || project.path.lowercased().contains(trimmedQuery)
                        || !projectThreads.isEmpty

                    if matchesProjectQuery {
                        projectDisclosureGroup(for: project, threads: projectThreads)
                    }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text("Projects")
                Spacer()
                Button {
                    appModel.promptAddProjectFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .help("Add Project Folder… (⇧⌘O)")
                .accessibilityLabel("Add project folder")
            }
        }
    }

    @ViewBuilder
    private func projectDisclosureGroup(
        for project: RemoteProject,
        threads projectThreads: [RemoteThreadSummary]
    ) -> some View {
        let expansionBinding = Binding<Bool>(
            get: {
                if !trimmedQuery.isEmpty && !projectThreads.isEmpty {
                    return true
                }
                return expandedProjectOverrides[project.id] ?? project.isExpanded ?? true
            },
            set: { newValue in
                expandedProjectOverrides[project.id] = newValue
                Task { await appModel.setProjectExpanded(project.id, expanded: newValue) }
            }
        )

        let rawLimit = appModel.workspace.sidebar?.threadsPerProject
        let effectiveLimit: Int? = {
            guard trimmedQuery.isEmpty,
                  !expandedFullThreadListProjects.contains(project.id),
                  let limit = rawLimit,
                  limit > 0
            else {
                return nil
            }
            return limit
        }()

        let visibleThreads: [RemoteThreadSummary] = {
            guard let limit = effectiveLimit, projectThreads.count > limit else {
                return projectThreads
            }
            var slice = Array(projectThreads.prefix(limit))
            if let selectedUUID = appModel.selectedThreadUUID,
               !slice.contains(where: { $0.id == selectedUUID }),
               let selectedMatch = projectThreads.first(where: { $0.id == selectedUUID })
            {
                slice.append(selectedMatch)
            }
            return slice
        }()

        let hiddenCount = max(0, projectThreads.count - visibleThreads.count)

        DisclosureGroup(isExpanded: expansionBinding) {
            if visibleThreads.isEmpty {
                Button {
                    Task { _ = await appModel.createNewThread(in: project.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                        Text("Start thread in \(project.name)")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(AppTheme.tertiaryLabel)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(visibleThreads) { thread in
                    SidebarThreadRow(
                        appModel: appModel,
                        thread: thread,
                        projectPath: project.path
                    )
                    .tag(thread.id.uuidString)
                }

                if hiddenCount > 0 {
                    Button {
                        expandedFullThreadListProjects.insert(project.id)
                    } label: {
                        Text("Show \(hiddenCount) More…")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        } label: {
            SidebarProjectHeaderLabel(
                appModel: appModel,
                project: project,
                threadCount: projectThreads.count,
                isExpanded: expansionBinding.wrappedValue,
                onConfigureProject: { configuringProject = project },
                onRemoveProject: { pendingRemoveProject = project }
            )
        }
    }

    // MARK: - Chats Section

    @ViewBuilder
    private var chatsSection: some View {
        if !chatThreads.isEmpty || trimmedQuery.isEmpty {
            Section {
                if chatThreads.isEmpty {
                    Button {
                        Task { _ = await appModel.createNewChat() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                            Text("New quick chat…")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(chatThreads) { thread in
                        SidebarThreadRow(appModel: appModel, thread: thread)
                            .tag(thread.id.uuidString)
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Chats")
                    Spacer()
                    Button {
                        Task { _ = await appModel.createNewChat() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .help("New Chat (⇧⌘N)")
                    .accessibilityLabel("New chat")
                }
            }
        }
    }

    // MARK: - Snoozed Section

    private var snoozedSection: some View {
        Section {
            ForEach(snoozedThreads) { thread in
                let proj = regularProjectMap[thread.projectID]
                SidebarThreadRow(
                    appModel: appModel,
                    thread: thread,
                    projectPath: proj?.path,
                    showsProjectBadge: proj != nil,
                    projectName: proj?.name
                )
                .tag(thread.id.uuidString)
            }
        } header: {
            HStack(spacing: 6) {
                Text("Snoozed")
                Text("\(snoozedThreads.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                Spacer()
                Button("Unsnooze All") {
                    let ids = snoozedThreads.map(\.id)
                    Task {
                        for id in ids {
                            await appModel.performThreadAction(.snooze(nil), on: id)
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondaryLabel)
                .help("Wake all snoozed threads")
            }
        }
    }

    // MARK: - Archived Section

    private var archivedSection: some View {
        Section {
            if archivedThreads.isEmpty {
                Text("No archived threads")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.tertiaryLabel)
            } else {
                ForEach(archivedThreads) { thread in
                    let proj = regularProjectMap[thread.projectID]
                    SidebarThreadRow(
                        appModel: appModel,
                        thread: thread,
                        projectPath: proj?.path,
                        showsProjectBadge: proj != nil,
                        projectName: proj?.name
                    )
                    .tag(thread.id.uuidString)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text("Archived")
                if !archivedThreads.isEmpty {
                    Text("\(archivedThreads.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
                Spacer()
                Button("Hide") {
                    appModel.showArchivedThreads = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondaryLabel)
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 6) {
            Button {
                Task { _ = await appModel.createNewThread() }
            } label: {
                Label("New Thread", systemImage: "square.and.pencil")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("New Thread (⌘N)")
            .accessibilityLabel("New thread")

            Spacer()

            Button {
                appModel.promptAddProjectFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Add Project… (⇧⌘O)")
            .accessibilityLabel("Add project")

            Button {
                appModel.showSessionImport = true
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Import CLI Session… (⇧⌘I)")
            .accessibilityLabel("Import CLI session")

            Button {
                appModel.showArchivedThreads.toggle()
            } label: {
                Image(systemName: appModel.showArchivedThreads ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 13))
                    .foregroundStyle(appModel.showArchivedThreads ? AppTheme.accent : AppTheme.secondaryLabel)
            }
            .buttonStyle(.borderless)
            .help(appModel.showArchivedThreads ? "Hide Archived Threads (⌥⌘A)" : "Show Archived Threads (⌥⌘A)")
            .accessibilityLabel(appModel.showArchivedThreads ? "Hide archived threads" : "Show archived threads")

            sidebarSortMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var sidebarSortMenu: some View {
        let currentOptions = appModel.workspace.sidebar ?? RemoteSidebarOptions()
        Menu {
            Section("Sort Threads By") {
                ForEach(RemoteSidebarOptions.threadSorts, id: \.self) { sort in
                    Button {
                        var updated = currentOptions
                        updated.threadSort = sort
                        updated.chatSort = sort
                        Task {
                            try? await appModel.runtime?.setSidebarOptions(updated)
                            await appModel.refreshWorkspace()
                        }
                    } label: {
                        HStack {
                            Text(Self.sortDisplayName(sort))
                            if currentOptions.threadSort == sort {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section("Sort Projects By") {
                ForEach(RemoteSidebarOptions.projectSorts, id: \.self) { sort in
                    Button {
                        var updated = currentOptions
                        updated.projectSort = sort
                        Task {
                            try? await appModel.runtime?.setSidebarOptions(updated)
                            await appModel.refreshWorkspace()
                        }
                    } label: {
                        HStack {
                            Text(Self.sortDisplayName(sort))
                            if currentOptions.projectSort == sort {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .help("Sidebar Sort Options")
        .accessibilityLabel("Sidebar sort options")
    }

    private nonisolated static func sortDisplayName(_ raw: String) -> String {
        switch raw {
        case "manual": "Manual"
        case "recentActivity": "Recent Activity"
        case "created": "Date Created"
        case "name": "Name"
        default: raw.capitalized
        }
    }
}

private struct SidebarLibraryRow: View {
    let title: String
    let systemImage: String
    let count: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryLabel)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(AppTheme.primaryLabel)
                .lineLimit(1)

            Spacer(minLength: 4)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(isSelected ? AppTheme.unemphasizedSelectedBackground.opacity(0.65) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityLabel(title)
    }
}

// MARK: - Sidebar Bot Row

private struct SidebarBotRow: View {
    @Bindable var appModel: AppModel
    let bot: RemoteBot
    let onRequestDelete: () -> Void

    @State private var isHovering: Bool = false

    private var botThreads: [RemoteThreadSummary] {
        let idSet = Set(bot.threadIDs)
        return appModel.workspace.threads
            .filter { idSet.contains($0.id) && !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var isSelectedBot: Bool {
        guard let selectedUUID = appModel.selectedThreadUUID else { return false }
        return bot.threadIDs.contains(selectedUUID)
    }

    private var isRunning: Bool {
        botThreads.contains { $0.isRunning || $0.isStarting || ($0.hasBackgroundWork == true) }
    }

    private var attentionCount: Int {
        botThreads.reduce(0) { $0 + $1.pendingApprovals + $1.pendingQuestions }
    }

    private var hasUnread: Bool {
        botThreads.contains { $0.unseen != nil }
    }

    var body: some View {
        HStack(spacing: 8) {
            BotAvatarView(avatar: bot.avatar, size: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(bot.name)
                    .font(.system(size: 13, weight: (hasUnread || isSelectedBot) ? .semibold : .medium))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .lineLimit(1)

                if let selection = bot.selection {
                    Text(AgentBranding.displayName(for: selection.provider))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if isHovering {
                Button {
                    Task { await appModel.startBotConversation(bot.id) }
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .help("Start New Conversation with \(bot.name)")
            }

            if attentionCount > 0 {
                Text("\(attentionCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.onAccent)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1.5)
                    .background(AppTheme.warning, in: Capsule())
            }

            if isRunning {
                ProgressView()
                    .controlSize(.mini)
            }

            if hasUnread {
                Circle()
                    .fill(AppTheme.info)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(isSelectedBot ? AppTheme.unemphasizedSelectedBackground.opacity(0.65) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if let existing = botThreads.first {
                appModel.selectThread(existing.id)
            } else {
                Task { await appModel.startBotConversation(bot.id) }
            }
        }
        .contextMenu {
            Button {
                Task { await appModel.startBotConversation(bot.id) }
            } label: {
                Label("Start Conversation", systemImage: "plus.bubble")
            }

            if !botThreads.isEmpty {
                Menu("Recent Conversations") {
                    ForEach(botThreads.prefix(8)) { thread in
                        Button(thread.title.isEmpty ? "Conversation" : thread.title) {
                            appModel.selectThread(thread.id)
                        }
                    }
                }
            }

            Button {
                appModel.openBotEditor(for: bot)
            } label: {
                Label("Edit Bot…", systemImage: "slider.horizontal.3")
            }

            Divider()

            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Label("Delete Bot", systemImage: "trash")
            }
        }
    }
}

// MARK: - Sidebar Project Header Label & Context Menu

private struct SidebarProjectHeaderLabel: View {
    @Bindable var appModel: AppModel
    let project: RemoteProject
    let threadCount: Int
    let isExpanded: Bool
    let onConfigureProject: () -> Void
    let onRemoveProject: () -> Void

    @State private var isHovering: Bool = false

    private var expandedPath: String {
        ExternalEditorService.expandedPath(project.path)
    }

    private var pathExistsOnDisk: Bool {
        guard !project.path.isEmpty else { return true }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir) && isDir.boolValue
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: pathExistsOnDisk ? "folder.fill" : "folder.badge.questionmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pathExistsOnDisk ? AppTheme.secondaryLabel : AppTheme.warning)
                    .frame(width: 16, height: 16)

                if !pathExistsOnDisk {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.warning)
                        .offset(x: 3, y: 2)
                }
            }
            .help(pathExistsOnDisk ? project.path : "Folder missing on disk: \(project.path)")

            Text(project.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.primaryLabel)
                .lineLimit(1)

            Spacer(minLength: 4)

            if isHovering {
                Button {
                    Task { _ = await appModel.createNewThread(in: project.id) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .frame(width: 18, height: 18)
                        .background(AppTheme.subtleHoverFill, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("New Thread in \(project.name)")
            } else if !isExpanded && threadCount > 0 {
                Text("\(threadCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 1.5)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            projectContextMenu
        }
    }

    @ViewBuilder
    private var projectContextMenu: some View {
        Button {
            Task { _ = await appModel.createNewThread(in: project.id) }
        } label: {
            Label("New Thread", systemImage: "square.and.pencil")
        }

        Divider()

        if let preferred = appModel.externalEditors.preferredEditor {
            Button {
                openInTarget(preferred)
            } label: {
                Label {
                    Text("Open in \(preferred.name)")
                } icon: {
                    Image(nsImage: preferred.icon)
                }
            }
        }

        let editors = appModel.externalEditors.installedEditors
        let terminals = appModel.externalEditors.installedTerminals
        if !editors.isEmpty || !terminals.isEmpty {
            Menu {
                if !editors.isEmpty {
                    Section("Editors") {
                        ForEach(editors) { target in
                            Button {
                                openInTarget(target)
                            } label: {
                                Label {
                                    Text(target.name)
                                } icon: {
                                    Image(nsImage: target.icon)
                                }
                            }
                        }
                    }
                }
                if !terminals.isEmpty {
                    Section("Terminals") {
                        ForEach(terminals) { target in
                            Button {
                                openInTarget(target)
                            } label: {
                                Label {
                                    Text(target.name)
                                } icon: {
                                    Image(nsImage: target.icon)
                                }
                            }
                        }
                    }
                }
            } label: {
                Label("Open In", systemImage: "arrow.up.forward.app")
            }
        }

        Button {
            appModel.externalEditors.revealInFinder(path: project.path)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(expandedPath, forType: .string)
            appModel.presentToast("Copied Path", detail: project.path, style: .info)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        if !project.scripts.isEmpty {
            Divider()

            Menu {
                ForEach(project.scripts) { script in
                    Button {
                        Task { await runScriptEnsuringProjectThread(script) }
                    } label: {
                        Label(
                            script.name,
                            systemImage: ProjectSettingsSheet.symbolName(forScriptIcon: script.icon)
                        )
                    }
                }
            } label: {
                Label("Run Script", systemImage: "play.circle")
            }
        }

        Divider()

        Button {
            onConfigureProject()
        } label: {
            Label("Project Defaults & Scripts…", systemImage: "slider.horizontal.3")
        }

        Divider()

        Button(role: .destructive) {
            onRemoveProject()
        } label: {
            Label("Remove Project", systemImage: "trash")
        }
    }

    private func openInTarget(_ target: ExternalAppTarget) {
        do {
            try appModel.externalEditors.open(path: project.path, in: target)
        } catch {
            appModel.presentError(error)
        }
    }

    private func runScriptEnsuringProjectThread(_ script: RemoteScript) async {
        if appModel.selectedThread?.projectID != project.id {
            if let existing = appModel.workspace.threads.first(where: { $0.projectID == project.id && !$0.isArchived }) {
                appModel.selectThread(existing.id)
            } else {
                _ = await appModel.createNewThread(in: project.id)
            }
        }
        await appModel.runProjectScript(script, projectID: project.id)
    }
}
