import AppKit
import CoincideRemoteKit
import SwiftUI

public struct CommandPaletteSheet: View {
    @Bindable public var appModel: AppModel
    @Environment(\.openSettings) private var openSettings

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var workspaceFiles: [WorkspaceFileEntry] = []
    @State private var isLoadingFiles: Bool = false
    @FocusState private var isSearchFocused: Bool

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    // MARK: - Palette Item Representation

    private nonisolated enum Category: String, CaseIterable, Hashable, Sendable {
        case actions = "Quick Actions"
        case threads = "Threads"
        case projects = "Projects"
        case bots = "Bots"
        case files = "Workspace Files"
    }

    private enum IconSpec {
        case symbol(String, Color?)
        case agent(String)
        case bot(RemoteBotAvatar?)
        case appIcon(NSImage)
    }

    private struct PaletteItem: Identifiable {
        let id: String
        let category: Category
        let title: String
        let subtitle: String?
        let shortcutHint: String?
        let icon: IconSpec
        let score: Int
        let perform: @MainActor () -> Void

        func withScore(_ newScore: Int) -> Self {
            Self(
                id: id,
                category: category,
                title: title,
                subtitle: subtitle,
                shortcutHint: shortcutHint,
                icon: icon,
                score: newScore,
                perform: perform
            )
        }
    }

    private struct IndexedPaletteItem: Identifiable {
        let globalIndex: Int
        let item: PaletteItem
        var id: String { item.id }
    }

    private struct PaletteSection: Identifiable {
        let category: Category
        let entries: [IndexedPaletteItem]
        var id: String { category.rawValue }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var regularProjectsByID: [UUID: RemoteProject] {
        Dictionary(
            uniqueKeysWithValues: appModel.workspace.projects
                .filter { !$0.isChats }
                .map { ($0.id, $0) }
        )
    }

    private var allResults: [PaletteItem] {
        let q = trimmedQuery
        var items: [PaletteItem] = []

        // 1. Quick Actions
        for action in buildQuickActions() {
            if q.isEmpty {
                items.append(action)
            } else if let s = Self.matchScore(query: q, primary: action.title, secondary: action.subtitle) {
                items.append(action.withScore(s + 25))
            }
        }

        // 2. Threads
        let threadsSource = appModel.workspace.threads.sorted { $0.updatedAt > $1.updatedAt }
        let maxEmptyThreads = 6
        var addedEmptyThreads = 0
        for thread in threadsSource {
            let title = thread.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "New Thread"
                : thread.title
            let projectName = regularProjectsByID[thread.projectID]?.name
            let subtitleParts = [
                projectName,
                thread.branch,
                AgentBranding.displayName(for: thread.selection.provider),
            ].compactMap { $0 }.filter { !$0.isEmpty }
            let subtitle = subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · ")

            if q.isEmpty {
                guard !thread.isArchived, addedEmptyThreads < maxEmptyThreads else { continue }
                addedEmptyThreads += 1
                items.append(
                    PaletteItem(
                        id: "thread:\(thread.id.uuidString)",
                        category: .threads,
                        title: title,
                        subtitle: subtitle,
                        shortcutHint: SidebarThreadRow.compactRelativeAge(from: thread.updatedAt),
                        icon: .agent(thread.selection.provider),
                        score: 50 - addedEmptyThreads
                    ) {
                        appModel.selectThread(thread.id)
                    }
                )
            } else if let s = Self.matchScore(query: q, primary: title, secondary: subtitle) {
                items.append(
                    PaletteItem(
                        id: "thread:\(thread.id.uuidString)",
                        category: .threads,
                        title: title,
                        subtitle: subtitle,
                        shortcutHint: SidebarThreadRow.compactRelativeAge(from: thread.updatedAt),
                        icon: .agent(thread.selection.provider),
                        score: s + (thread.isArchived ? -10 : 15)
                    ) {
                        appModel.selectThread(thread.id)
                    }
                )
            }
        }

        // 3. Projects
        for project in appModel.workspace.projects where !project.isChats {
            if q.isEmpty {
                items.append(makeProjectItem(project, score: 30))
            } else if let s = Self.matchScore(query: q, primary: project.name, secondary: project.path) {
                items.append(makeProjectItem(project, score: s + 20))
            }
        }

        // 4. Bots
        for bot in appModel.workspace.bots ?? [] {
            let subtitle = bot.persona?.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                items.append(makeBotItem(bot, subtitle: subtitle, score: 25))
            } else if let s = Self.matchScore(query: q, primary: bot.name, secondary: subtitle) {
                items.append(makeBotItem(bot, subtitle: subtitle, score: s + 20))
            }
        }

        // 5. Workspace Files
        let fileEntries = workspaceFiles.filter { !$0.isDirectory }
        let fileSlice = q.isEmpty ? Array(fileEntries.prefix(8)) : Array(fileEntries.prefix(35))
        for (idx, file) in fileSlice.enumerated() {
            let dir = (file.path as NSString).deletingLastPathComponent
            let subtitle = dir.isEmpty ? nil : dir
            let computedScore: Int
            if q.isEmpty {
                computedScore = max(1, 20 - idx)
            } else {
                computedScore = (Self.matchScore(query: q, primary: file.name, secondary: file.path) ?? 40) + 10
            }
            items.append(
                PaletteItem(
                    id: "file:\(file.path)",
                    category: .files,
                    title: file.name,
                    subtitle: subtitle,
                    shortcutHint: file.gitStatus,
                    icon: .symbol(Self.fileSymbolName(for: file.name), AppTheme.secondaryLabel),
                    score: computedScore
                ) {
                    appModel.openFileInInspector(path: file.path)
                }
            )
        }

        if !q.isEmpty {
            return items.sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
        return items
    }

    private var groupedSections: [PaletteSection] {
        let flat = allResults
        if !trimmedQuery.isEmpty {
            var byCat: [Category: [PaletteItem]] = [:]
            var catOrder: [Category] = []
            for item in flat {
                if byCat[item.category] == nil {
                    catOrder.append(item.category)
                }
                byCat[item.category, default: []].append(item)
            }
            var result: [PaletteSection] = []
            var runningIdx = 0
            for cat in catOrder {
                let raw = byCat[cat] ?? []
                let indexed = raw.map { item -> IndexedPaletteItem in
                    defer { runningIdx += 1 }
                    return IndexedPaletteItem(globalIndex: runningIdx, item: item)
                }
                result.append(PaletteSection(category: cat, entries: indexed))
            }
            return result
        } else {
            var result: [PaletteSection] = []
            var runningIdx = 0
            for cat in Category.allCases {
                let matching = flat.filter { $0.category == cat }
                guard !matching.isEmpty else { continue }
                let indexed = matching.map { item -> IndexedPaletteItem in
                    defer { runningIdx += 1 }
                    return IndexedPaletteItem(globalIndex: runningIdx, item: item)
                }
                result.append(PaletteSection(category: cat, entries: indexed))
            }
            return result
        }
    }

    private var orderedVisibleItems: [PaletteItem] {
        groupedSections.flatMap { $0.entries.map(\.item) }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            searchInputHeader

            Divider()

            resultsScrollView

            Divider()

            footerHintBar
        }
        .frame(width: 620, height: 420)
        .background(AppTheme.windowBackground)
        .onAppear {
            selectedIndex = 0
            isSearchFocused = true
        }
        .task(id: trimmedQuery) {
            await loadWorkspaceFiles(matching: trimmedQuery)
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.downArrow) {
            moveSelection(delta: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(delta: -1)
            return .handled
        }
        .onKeyPress(.return) {
            activateHighlightedItem()
            return .handled
        }
        .onKeyPress(.escape) {
            appModel.showCommandPalette = false
            return .handled
        }
    }

    // MARK: - Search Input Header

    private var searchInputHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.secondaryLabel)

            TextField("Type a command, thread, project, bot, or file…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .onSubmit {
                    activateHighlightedItem()
                }

            if isLoadingFiles {
                ProgressView()
                    .controlSize(.mini)
            }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsScrollView: some View {
        let sections = groupedSections
        if sections.isEmpty {
            ContentUnavailableView(
                "No Matching Commands or Files",
                systemImage: "sparkle.magnifyingglass",
                description: Text("Try searching for an action, thread title, project, bot, or workspace filename.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                        ForEach(sections) { section in
                            Text(section.category.rawValue)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                                .textCase(.uppercase)
                                .padding(.horizontal, 14)
                                .padding(.top, 8)
                                .padding(.bottom, 3)

                            ForEach(section.entries) { entry in
                                paletteRow(item: entry.item, index: entry.globalIndex)
                                    .id(entry.globalIndex)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: selectedIndex) { _, newIdx in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newIdx, anchor: nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paletteRow(item: PaletteItem, index: Int) -> some View {
        let isHighlighted = index == selectedIndex
        Button {
            selectedIndex = index
            executeItem(item)
        } label: {
            HStack(spacing: 10) {
                paletteIconView(item.icon)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(item.title)
                        .font(.system(size: 13, weight: isHighlighted ? .medium : .regular))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)

                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)

                if let hint = item.shortcutHint, !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func paletteIconView(_ spec: IconSpec) -> some View {
        switch spec {
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(color ?? AppTheme.secondaryLabel)
        case .agent(let provider):
            AgentLogoView(provider: provider, size: 16)
        case .bot(let avatar):
            BotAvatarView(avatar: avatar, size: 20)
        case .appIcon(let nsImage):
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
    }

    // MARK: - Footer Hint Bar

    private var footerHintBar: some View {
        HStack(spacing: 14) {
            keyHintLabel(keys: "↑↓", action: "Navigate")
            keyHintLabel(keys: "↵", action: "Select")
            keyHintLabel(keys: "⎋", action: "Close")

            Spacer()

            if let proj = appModel.selectedProject, !proj.isChats {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(proj.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(AppTheme.tertiaryLabel)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(AppTheme.elevatedCardFill)
    }

    @ViewBuilder
    private func keyHintLabel(keys: String, action: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryLabel)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1)
                .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: 3.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5)
                        .strokeBorder(AppTheme.separator, lineWidth: 0.5)
                )
            Text(action)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiaryLabel)
        }
    }

    // MARK: - Navigation & Execution

    private func moveSelection(delta: Int) {
        let count = orderedVisibleItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func activateHighlightedItem() {
        let items = orderedVisibleItems
        guard !items.isEmpty else { return }
        let clamped = min(max(0, selectedIndex), items.count - 1)
        executeItem(items[clamped])
    }

    private func executeItem(_ item: PaletteItem) {
        appModel.showCommandPalette = false
        item.perform()
    }

    private func navigateToSettingsTab(_ tab: SettingsTab) {
        let openAction = openSettings
        appModel.selectedSettingsTab = tab
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(35))
            openAction()
        }
    }

    // MARK: - Quick Actions Builder

    private func buildQuickActions() -> [PaletteItem] {
        var actions: [PaletteItem] = [
            PaletteItem(
                id: "action:new-thread",
                category: .actions,
                title: "New Thread",
                subtitle: appModel.selectedProject.flatMap { $0.isChats ? nil : "In \($0.name)" },
                shortcutHint: "⌘N",
                icon: .symbol("square.and.pencil", Color.accentColor),
                score: 100
            ) {
                Task { _ = await appModel.createNewThread() }
            },
            PaletteItem(
                id: "action:new-chat",
                category: .actions,
                title: "New Chat",
                subtitle: "Start a standalone projectless conversation",
                shortcutHint: "⇧⌘N",
                icon: .symbol("bubble.left.and.bubble.right", AppTheme.info),
                score: 96
            ) {
                Task { _ = await appModel.createNewChat() }
            },
            PaletteItem(
                id: "action:configure-antigravity",
                category: .actions,
                title: "Configure Antigravity",
                subtitle: "Manage Gemini API keys and Antigravity ACP agent settings",
                shortcutHint: nil,
                icon: .agent("antigravity"),
                score: 94
            ) {
                navigateToSettingsTab(.antigravity)
            },
            PaletteItem(
                id: "action:toggle-terminal",
                category: .actions,
                title: appModel.terminalVisible ? "Hide Terminal" : "Toggle Terminal",
                subtitle: "Open or hide the integrated PTY terminal drawer",
                shortcutHint: "⌘J",
                icon: .symbol("terminal", AppTheme.secondaryLabel),
                score: 92
            ) {
                appModel.toggleTerminal()
            },
            PaletteItem(
                id: "action:toggle-diff",
                category: .actions,
                title: "Toggle Diff — Show Uncommitted Changes",
                subtitle: "Inspect live file diffs in the workspace inspector",
                shortcutHint: "⌘D",
                icon: .symbol("plusminus", AppTheme.success),
                score: 90
            ) {
                if appModel.inspectorVisible && appModel.inspectorTab == .changes {
                    appModel.inspectorVisible = false
                } else {
                    appModel.openInspector(tab: .changes)
                }
            },
            PaletteItem(
                id: "action:import-cli-session",
                category: .actions,
                title: "Import CLI Session…",
                subtitle: "Import local Claude Code or Codex .jsonl transcripts",
                shortcutHint: "⇧⌘I",
                icon: .symbol("square.and.arrow.down", AppTheme.secondaryLabel),
                score: 88
            ) {
                appModel.showSessionImport = true
            },
            PaletteItem(
                id: "action:add-project",
                category: .actions,
                title: "Add Project Folder…",
                subtitle: "Attach a local repository or folder to Coincide",
                shortcutHint: "⇧⌘O",
                icon: .symbol("folder.badge.plus", AppTheme.secondaryLabel),
                score: 86
            ) {
                appModel.promptAddProjectFolder()
            },
            PaletteItem(
                id: "action:new-bot",
                category: .actions,
                title: "New Bot…",
                subtitle: "Create a custom persona bot with character artwork",
                shortcutHint: "⌥⌘N",
                icon: .symbol("sparkles", AppTheme.warning),
                score: 84
            ) {
                appModel.openBotEditor(for: nil)
            },
            PaletteItem(
                id: "action:source-control",
                category: .actions,
                title: "Show Source Control",
                subtitle: "Commit, push, pull, or switch branches",
                shortcutHint: "⌃⌘G",
                icon: .symbol("point.3.connected.trianglepath.dotted", AppTheme.secondaryLabel),
                score: 80
            ) {
                appModel.openInspector(tab: .git)
            },
            PaletteItem(
                id: "action:pull-requests",
                category: .actions,
                title: "Show Pull Requests",
                subtitle: "Review, check out, or merge GitHub pull requests",
                shortcutHint: "⌃⌘P",
                icon: .symbol("arrow.triangle.pull", AppTheme.secondaryLabel),
                score: 78
            ) {
                appModel.openInspector(tab: .pullRequests)
            },
            PaletteItem(
                id: "action:workspace-files",
                category: .actions,
                title: "Show Workspace Files",
                subtitle: "Browse and search files in the active repository",
                shortcutHint: "⌃⌘E",
                icon: .symbol("folder", AppTheme.secondaryLabel),
                score: 76
            ) {
                appModel.openInspector(tab: .files)
            },
            PaletteItem(
                id: "action:schedules",
                category: .actions,
                title: "Show Scheduled Tasks",
                subtitle: "Manage recurring automated agent schedules",
                shortcutHint: "⌥⌘S",
                icon: .symbol("calendar.badge.clock", AppTheme.secondaryLabel),
                score: 74
            ) {
                appModel.openInspector(tab: .schedules)
            },
            PaletteItem(
                id: "action:toggle-inspector",
                category: .actions,
                title: appModel.inspectorVisible ? "Hide Inspector" : "Toggle Inspector",
                subtitle: nil,
                shortcutHint: "⌥⌘I",
                icon: .symbol("sidebar.trailing", AppTheme.secondaryLabel),
                score: 72
            ) {
                appModel.toggleInspector()
            },
            PaletteItem(
                id: "action:find-conversation",
                category: .actions,
                title: "Find in Conversation",
                subtitle: nil,
                shortcutHint: "⌘F",
                icon: .symbol("text.magnifyingglass", AppTheme.secondaryLabel),
                score: 70
            ) {
                appModel.showFindBar = true
            },
            PaletteItem(
                id: "action:toggle-archived",
                category: .actions,
                title: appModel.showArchivedThreads ? "Hide Archived Threads" : "Show Archived Threads",
                subtitle: nil,
                shortcutHint: "⌥⌘A",
                icon: .symbol("archivebox", AppTheme.secondaryLabel),
                score: 68
            ) {
                appModel.showArchivedThreads.toggle()
            },
            PaletteItem(
                id: "action:settings-providers",
                category: .actions,
                title: "Configure Agent Providers & ACP Registry…",
                subtitle: "Manage Claude Code, Codex, Cursor, Grok, OpenCode, and ACP agents",
                shortcutHint: nil,
                icon: .symbol("cpu", AppTheme.secondaryLabel),
                score: 66
            ) {
                navigateToSettingsTab(.providers)
            },
            PaletteItem(
                id: "action:settings-remote",
                category: .actions,
                title: "Pair Coincide Remote (iOS)…",
                subtitle: "Connect your iPhone over local encrypted Wi-Fi",
                shortcutHint: nil,
                icon: .symbol("iphone.radiowaves.left.and.right", AppTheme.info),
                score: 64
            ) {
                navigateToSettingsTab(.remote)
            },
        ]

        if let cwd = appModel.activeWorkingDirectory {
            if let preferred = appModel.externalEditors.preferredEditor {
                actions.append(
                    PaletteItem(
                        id: "action:open-editor",
                        category: .actions,
                        title: "Open Working Directory in \(preferred.name)",
                        subtitle: cwd,
                        shortcutHint: "⌘O",
                        icon: .appIcon(preferred.icon),
                        score: 82
                    ) {
                        try? appModel.externalEditors.open(path: cwd, in: preferred)
                    }
                )
            }

            actions.append(
                PaletteItem(
                    id: "action:reveal-finder",
                    category: .actions,
                    title: "Reveal Working Directory in Finder",
                    subtitle: cwd,
                    shortcutHint: "⇧⌘R",
                    icon: .symbol("folder", AppTheme.secondaryLabel),
                    score: 62
                ) {
                    appModel.externalEditors.revealInFinder(path: cwd)
                }
            )
        }

        if let thread = appModel.selectedThread {
            if thread.isRunning || thread.isStarting {
                actions.insert(
                    PaletteItem(
                        id: "action:stop-turn",
                        category: .actions,
                        title: "Stop Active Agent Turn",
                        subtitle: thread.title,
                        shortcutHint: "⌘.",
                        icon: .symbol("stop.circle.fill", AppTheme.danger),
                        score: 105
                    ) {
                        Task { await appModel.stopActiveTurn() }
                    },
                    at: 0
                )
            }

            actions.append(
                PaletteItem(
                    id: "action:fork-thread",
                    category: .actions,
                    title: "Fork Current Thread",
                    subtitle: thread.title.isEmpty ? "Current conversation" : thread.title,
                    shortcutHint: nil,
                    icon: .symbol("arrow.triangle.branch", AppTheme.secondaryLabel),
                    score: 60
                ) {
                    Task { _ = await appModel.forkThread(thread.id) }
                }
            )
        }

        return actions
    }

    private func makeProjectItem(_ project: RemoteProject, score: Int) -> PaletteItem {
        PaletteItem(
            id: "project:\(project.id.uuidString)",
            category: .projects,
            title: project.name,
            subtitle: project.path,
            shortcutHint: nil,
            icon: .symbol("folder.fill", AppTheme.secondaryLabel),
            score: score
        ) {
            if let latest = appModel.workspace.threads
                .filter({ $0.projectID == project.id && !$0.isArchived })
                .sorted(by: { $0.updatedAt > $1.updatedAt })
                .first
            {
                appModel.selectThread(latest.id)
            } else {
                Task { _ = await appModel.createNewThread(in: project.id) }
            }
        }
    }

    private func makeBotItem(_ bot: RemoteBot, subtitle: String?, score: Int) -> PaletteItem {
        PaletteItem(
            id: "bot:\(bot.id.uuidString)",
            category: .bots,
            title: bot.name,
            subtitle: subtitle,
            shortcutHint: nil,
            icon: .bot(bot.avatar),
            score: score
        ) {
            let idSet = Set(bot.threadIDs)
            if let existing = appModel.workspace.threads
                .filter({ idSet.contains($0.id) && !$0.isArchived })
                .sorted(by: { $0.updatedAt > $1.updatedAt })
                .first
            {
                appModel.selectThread(existing.id)
            } else {
                Task { await appModel.startBotConversation(bot.id) }
            }
        }
    }

    // MARK: - Workspace File Search

    private func loadWorkspaceFiles(matching searchQuery: String) async {
        guard let client = appModel.runtime,
              let cwd = appModel.activeWorkingDirectory,
              !cwd.isEmpty
        else {
            workspaceFiles = []
            return
        }

        if !searchQuery.isEmpty {
            try? await Task.sleep(for: .milliseconds(75))
            guard !Task.isCancelled else { return }
        }

        isLoadingFiles = true
        defer { isLoadingFiles = false }

        if let files = try? await client.listWorkspaceFiles(
            cwd: cwd,
            query: searchQuery,
            limit: searchQuery.isEmpty ? 30 : 80
        ), !Task.isCancelled {
            workspaceFiles = files
        }
    }

    // MARK: - Fuzzy / Substring Ranking & Icons

    private nonisolated static func matchScore(query: String, primary: String, secondary: String?) -> Int? {
        let q = query.lowercased()
        guard !q.isEmpty else { return 0 }

        let p = primary.lowercased()
        if p == q { return 200 }
        if p.hasPrefix(q) { return 160 }
        if p.contains(q) { return 120 }

        if let fuzzyP = subsequenceScore(needle: q, haystack: p) {
            return 75 + fuzzyP
        }

        if let s = secondary?.lowercased(), !s.isEmpty {
            if s.contains(q) { return 85 }
            if let fuzzyS = subsequenceScore(needle: q, haystack: s) {
                return 45 + fuzzyS
            }
        }
        return nil
    }

    private nonisolated static func subsequenceScore(needle: String, haystack: String) -> Int? {
        var needleIdx = needle.startIndex
        var consecutiveBonus = 0
        var lastMatched = false

        for ch in haystack {
            if needleIdx < needle.endIndex && ch == needle[needleIdx] {
                needleIdx = needle.index(after: needleIdx)
                if lastMatched {
                    consecutiveBonus += 3
                }
                lastMatched = true
                if needleIdx == needle.endIndex {
                    return min(40, consecutiveBonus)
                }
            } else {
                lastMatched = false
            }
        }
        return nil
    }

    private nonisolated static func fileSymbolName(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "rs", "ts", "tsx", "js", "jsx", "py", "go", "c", "h", "cpp", "hpp", "rb", "java", "kt":
            return "curlybraces"
        case "json", "toml", "yaml", "yml", "plist", "xml":
            return "doc.badge.gearshape"
        case "md", "markdown", "txt", "rst":
            return "doc.richtext"
        case "sh", "zsh", "bash", "fish":
            return "terminal"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "icns":
            return "photo"
        default:
            return "doc.text"
        }
    }
}
