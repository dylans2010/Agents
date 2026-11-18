import AppKit
import CoincideRemoteKit
import SwiftUI

public struct ConversationRootView: View {
    @Bindable public var appModel: AppModel

    @State private var showRenamePopover = false
    @State private var renameDraft = ""
    @State private var showCheckoutPopover = false
    @State private var activeFindIndex: Int = 0
    @FocusState private var isFindFieldFocused: Bool

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var activeThread: RemoteThreadSummary? {
        appModel.selectedThread
    }

    private var activeTranscript: RemoteTranscript? {
        appModel.activeTranscript
    }

    private var shouldShowWelcome: Bool {
        guard let transcript = activeTranscript, appModel.selectedThreadUUID != nil else {
            return true
        }
        let isRunning = transcript.turn.isRunning || transcript.turn.isStarting
        return transcript.items.isEmpty && !isRunning
    }

    private var uncommittedDiffFileCount: Int {
        guard case .uncommitted = appModel.activeDiffScope else {
            return appModel.activeGitState?.changedFiles ?? 0
        }
        if let files = appModel.activeDiff?.files, !files.isEmpty {
            return files.count
        }
        return appModel.activeGitState?.changedFiles ?? 0
    }

    /// Transcript items matching `appModel.findQuery` when the Find Bar is open.
    private var matchingFindItemIDs: [UUID] {
        guard appModel.showFindBar else { return [] }
        let q = appModel.findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let items = activeTranscript?.items else { return [] }
        return items.compactMap { item in
            let matchesText = item.text.localizedStandardContains(q)
            let matchesTitle = item.title?.localizedStandardContains(q) == true
            let matchesDetail = item.detail?.localizedStandardContains(q) == true
            return (matchesText || matchesTitle || matchesDetail) ? item.id : nil
        }
    }

    private var currentActiveFindItemID: UUID? {
        let matches = matchingFindItemIDs
        guard !matches.isEmpty else { return nil }
        let clamped = min(max(0, activeFindIndex), matches.count - 1)
        return matches[clamped]
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Inline Find in Thread Bar
            if appModel.showFindBar {
                conversationFindBar
                Divider()
            }

            // Main Upper Canvas: Welcome Workspace vs Virtualized Transcript
            Group {
                if appModel.isLoadingTranscript && activeTranscript == nil {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Opening conversation…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if shouldShowWelcome {
                    WelcomeWorkspaceView(appModel: appModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let transcript = activeTranscript {
                    TranscriptScrollView(
                        transcript: transcript,
                        appModel: appModel,
                        highlightQuery: appModel.showFindBar ? appModel.findQuery : "",
                        activeFindItemID: currentActiveFindItemID
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Interactive Approvals & Questions Banner above Composer
            if let transcript = activeTranscript {
                PendingAttentionView(transcript: transcript, appModel: appModel)
            }

            // AppKit-Backed Composer
            ComposerBarView(appModel: appModel)
                .frame(maxWidth: .infinity)
        }
        .background(AppTheme.windowBackground)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                navigationHeaderItems
            }

            ToolbarItemGroup(placement: .primaryAction) {
                trailingToolbarItems
            }
        }
        .onChange(of: appModel.showFindBar) { _, isVisible in
            if isVisible {
                activeFindIndex = max(0, matchingFindItemIDs.count - 1)
                DispatchQueue.main.async {
                    isFindFieldFocused = true
                }
            }
        }
        .onChange(of: appModel.findQuery) { _, _ in
            let matches = matchingFindItemIDs
            activeFindIndex = matches.isEmpty ? 0 : matches.count - 1
        }
        .task(id: "\(appModel.selectedThreadID ?? "none"):\(appModel.status.revision)") {
            await refreshLightweightDiffBadge()
        }
    }

    // MARK: - Navigation / Principal Toolbar Items

    @ViewBuilder
    private var navigationHeaderItems: some View {
        HStack(spacing: 8) {
            // 1. Thread Title (Click to Rename)
            if let thread = activeThread {
                Button {
                    renameDraft = thread.title
                    showRenamePopover = true
                } label: {
                    HStack(spacing: 6) {
                        if thread.isRunning || thread.isStarting {
                            ProgressView()
                                .controlSize(.mini)
                        } else if thread.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.accent)
                        }

                        Text(thread.title.isEmpty ? "New Conversation" : thread.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .lineLimit(1)
                            .frame(maxWidth: 240, alignment: .leading)

                        if let schedules = thread.scheduleCount, schedules > 0 {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.info)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Click to rename conversation")
                .popover(isPresented: $showRenamePopover, arrowEdge: .bottom) {
                    renameThreadPopover(for: thread)
                }
            } else {
                Text("Agents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .padding(.horizontal, 6)
            }

            // 2. Project Folder Pill
            if let project = appModel.selectedProject {
                Menu {
                    if let cwd = appModel.activeWorkingDirectory {
                        Button {
                            appModel.externalEditors.revealInFinder(path: cwd)
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cwd, forType: .string)
                        } label: {
                            Label("Copy Folder Path", systemImage: "doc.on.doc")
                        }

                        Button {
                            appModel.openInspector(tab: .files)
                        } label: {
                            Label("Browse Project Files", systemImage: "sidebar.right")
                        }

                        Divider()
                    }

                    Button {
                        appModel.promptAddProjectFolder()
                    } label: {
                        Label("Add Project Folder…", systemImage: "folder.badge.plus")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: project.isChats ? "bubble.left.and.bubble.right" : "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Text(project.name)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(AppTheme.elevatedCardFill, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(project.path.isEmpty ? project.name : project.path)
            }

            // 3. Git Branch / Worktree Checkout Popover Pill
            if activeThread != nil,
               let branchLabel = displayedCheckoutBranchLabel
            {
                let isWorktree = appModel.activeCheckout?.workspace == .worktree
                    || appModel.activeCheckout?.workspace == .newWorktree
                    || activeThread?.hasWorktree == true

                Button {
                    showCheckoutPopover.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isWorktree ? "square.split.2x1" : "arrow.triangle.branch")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(isWorktree ? AppTheme.accent : AppTheme.secondaryLabel)

                        Text(branchLabel)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .lineLimit(1)
                            .frame(maxWidth: 150)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(AppTheme.elevatedCardFill, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCheckoutPopover, arrowEdge: .bottom) {
                    CheckoutPopoverView(appModel: appModel)
                }
                .help("Switch Git branch or worktree mode")
            }
        }
    }

    private var displayedCheckoutBranchLabel: String? {
        if let checkout = appModel.activeCheckout {
            if checkout.workspace == .newWorktree {
                return checkout.baseBranch.map { "worktree:\($0)" } ?? "new-worktree"
            }
            if let branch = checkout.branch, !branch.isEmpty {
                return branch
            }
        }
        if let branch = activeThread?.branch, !branch.isEmpty {
            return branch
        }
        if appModel.selectedProject?.isChats == false {
            return "git"
        }
        return nil
    }

    // MARK: - Trailing Toolbar Items

    @ViewBuilder
    private var trailingToolbarItems: some View {
        // 1. Project Scripts Menu (`play.fill`) when project has scripts
        if let project = appModel.selectedProject, !project.scripts.isEmpty {
            Menu {
                Section("Run Project Script") {
                    ForEach(project.scripts) { script in
                        Button {
                            Task {
                                if appModel.selectedThreadUUID == nil {
                                    _ = await appModel.createNewThread(in: project.id)
                                }
                                await appModel.runProjectScript(script, projectID: project.id)
                            }
                        } label: {
                            Label(script.name, systemImage: scriptSymbol(for: script.icon))
                        }
                    }
                }
            } label: {
                Label("Run Script", systemImage: "play.fill")
            }
            .help("Run a configured project script in the integrated terminal")
        }

        // 2. Open In External Editor Split / Menu Button with real NSImage App Icons
        openInExternalAppToolbarItem

        // 3. Find in Thread (`magnifyingglass`)
        Button {
            withAnimation(.snappy(duration: 0.18)) {
                appModel.showFindBar.toggle()
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(appModel.showFindBar ? AppTheme.accent : AppTheme.primaryLabel)
        }
        .help("Find in Conversation (⌘F)")

        // 4. Integrated Terminal (`terminal`)
        Button {
            appModel.toggleTerminal()
        } label: {
            Image(systemName: appModel.terminalVisible ? "terminal.fill" : "terminal")
                .foregroundStyle(appModel.terminalVisible ? AppTheme.accent : AppTheme.primaryLabel)
        }
        .help("Toggle Integrated Terminal (⌘J)")

        // 5. Workspace Inspector (`sidebar.right`) with Uncommitted Diff File Count Badge
        Button {
            appModel.toggleInspector()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(appModel.inspectorVisible ? AppTheme.accent : AppTheme.primaryLabel)

                if uncommittedDiffFileCount > 0 {
                    Text("\(uncommittedDiffFileCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AppTheme.accent, in: Capsule())
                }
            }
        }
        .help(
            uncommittedDiffFileCount > 0
                ? "Toggle Workspace Inspector (\(uncommittedDiffFileCount) uncommitted \(uncommittedDiffFileCount == 1 ? "file" : "files"))"
                : "Toggle Workspace Inspector (⌥⌘I)"
        )
    }

    @ViewBuilder
    private var openInExternalAppToolbarItem: some View {
        let editors = appModel.externalEditors.installedEditors
        let terminals = appModel.externalEditors.installedTerminals
        let finder = appModel.externalEditors.finderTarget
        let preferred = appModel.externalEditors.preferredEditor ?? editors.first ?? terminals.first ?? finder

        if let preferred {
            Menu {
                if !editors.isEmpty {
                    Section("Open Workspace in Editor") {
                        ForEach(editors) { target in
                            Button {
                                appModel.externalEditors.setPreferredEditor(target.id)
                                openWorkspace(in: target)
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
                    Section("Open in External Terminal") {
                        ForEach(terminals) { target in
                            Button {
                                appModel.externalEditors.setPreferredTerminal(target.id)
                                openWorkspace(in: target)
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

                if let finder {
                    Divider()
                    Button {
                        openWorkspace(in: finder)
                    } label: {
                        Label {
                            Text("Reveal in Finder")
                        } icon: {
                            Image(nsImage: finder.icon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(nsImage: preferred.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 15, height: 15)
                    Text(preferred.name)
                        .font(.system(size: 12, weight: .medium))
                }
            } primaryAction: {
                openWorkspace(in: preferred)
            }
            .help("Open workspace in \(preferred.name) (or choose another app)")
        }
    }

    // MARK: - Inline Find Bar

    @ViewBuilder
    private var conversationFindBar: some View {
        let matches = matchingFindItemIDs
        let hasQuery = !appModel.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)

                TextField("Find in conversation…", text: $appModel.findQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($isFindFieldFocused)
                    .onSubmit {
                        stepFindMatch(delta: 1)
                    }

                if !appModel.findQuery.isEmpty {
                    Button {
                        appModel.findQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: 280)
            .background(AppTheme.textBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .strokeBorder(AppTheme.separator, lineWidth: 1)
            )

            if hasQuery {
                Text(
                    matches.isEmpty
                        ? "No matches"
                        : "\(min(activeFindIndex + 1, matches.count)) of \(matches.count)"
                )
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(matches.isEmpty ? AppTheme.danger : AppTheme.secondaryLabel)
            }

            HStack(spacing: 2) {
                Button {
                    stepFindMatch(delta: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(matches.isEmpty)
                .help("Previous match")

                Button {
                    stepFindMatch(delta: 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(matches.isEmpty)
                .help("Next match")
            }

            Spacer()

            Button("Done") {
                appModel.showFindBar = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.controlBackground)
    }

    // MARK: - Rename Thread Popover

    @ViewBuilder
    private func renameThreadPopover(for thread: RemoteThreadSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename Conversation")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppTheme.primaryLabel)

            TextField("Conversation title", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
                .frame(width: 260)
                .onSubmit {
                    commitThreadRename(for: thread)
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    showRenamePopover = false
                }
                .controlSize(.small)

                Button("Save") {
                    commitThreadRename(for: thread)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func commitThreadRename(for thread: RemoteThreadSummary) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showRenamePopover = false
        Task {
            await appModel.performThreadAction(.rename(trimmed), on: thread.id)
        }
    }

    private func stepFindMatch(delta: Int) {
        let matches = matchingFindItemIDs
        guard !matches.isEmpty else { return }
        activeFindIndex = (activeFindIndex + delta + matches.count) % matches.count
    }

    private func openWorkspace(in target: ExternalAppTarget) {
        guard let cwd = appModel.activeWorkingDirectory else { return }
        do {
            try appModel.externalEditors.open(path: cwd, in: target)
        } catch {
            appModel.presentError(error)
        }
    }

    private func scriptSymbol(for icon: String) -> String {
        switch icon.lowercased() {
        case "test": "checkmark.diamond"
        case "lint": "sparkles"
        case "configure": "wrench.and.screwdriver"
        case "build": "hammer"
        case "debug": "ladybug"
        default: "play.fill"
        }
    }

    private func refreshLightweightDiffBadge() async {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID else { return }
        if !appModel.inspectorVisible {
            if let diff = try? await client.fetchDiff(thread: tid, scope: .uncommitted) {
                appModel.activeDiffScope = .uncommitted
                appModel.activeDiff = diff
            }
        }
    }
}
