import AppKit
import CoincideRemoteKit
import SwiftUI
import UniformTypeIdentifiers

public struct SessionImportSheet: View {
    @Bindable public var appModel: AppModel

    @State private var sessions: [CLISessionSummary] = []
    @State private var isScanning: Bool = true
    @State private var isImporting: Bool = false

    @State private var providerFilter: String = "all"
    @State private var projectFilterID: String = "all"
    @State private var searchQuery: String = ""

    @State private var selectedSessionID: String?
    @State private var destinationProjectSelection: String = "auto"

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var regularProjects: [RemoteProject] {
        appModel.workspace.projects.filter { !$0.isChats }
    }

    private var discoveredProviders: [String] {
        let base = ["claude", "codex"]
        let extra = Set(sessions.map { $0.provider.lowercased() }).subtracting(base).sorted()
        return base + extra
    }

    private var filteredSessions: [CLISessionSummary] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filterProjectPath: String? = {
            guard projectFilterID != "all",
                  let uuid = UUID(uuidString: projectFilterID),
                  let proj = regularProjects.first(where: { $0.id == uuid })
            else {
                return nil
            }
            return ExternalEditorService.expandedPath(proj.path)
        }()

        return sessions.filter { session in
            if providerFilter != "all" && session.provider.lowercased() != providerFilter {
                return false
            }
            if let filterProjectPath {
                guard let cwd = session.cwd else { return false }
                let expandedCwd = ExternalEditorService.expandedPath(cwd)
                if !Self.pathIsInside(child: expandedCwd, parent: filterProjectPath) {
                    return false
                }
            }
            guard !q.isEmpty else { return true }
            return session.title.lowercased().contains(q)
                || (session.cwd?.lowercased().contains(q) ?? false)
                || session.path.lowercased().contains(q)
                || session.provider.lowercased().contains(q)
        }
    }

    private var selectedSession: CLISessionSummary? {
        guard let selectedSessionID else { return nil }
        return filteredSessions.first(where: { $0.id == selectedSessionID })
            ?? sessions.first(where: { $0.id == selectedSessionID })
    }

    private func autoMatchedProject(for session: CLISessionSummary?) -> RemoteProject? {
        guard let rawCwd = session?.cwd, !rawCwd.isEmpty else { return nil }
        let expandedCwd = ExternalEditorService.expandedPath(rawCwd)
        return regularProjects
            .filter { proj in
                guard !proj.path.isEmpty else { return false }
                let projExpanded = ExternalEditorService.expandedPath(proj.path)
                return Self.pathIsInside(child: expandedCwd, parent: projExpanded)
            }
            .max(by: { $0.path.count < $1.path.count })
    }

    private var resolvedTargetProjectID: UUID? {
        if destinationProjectSelection == "chats" {
            return nil
        }
        if destinationProjectSelection == "auto" {
            return autoMatchedProject(for: selectedSession)?.id
        }
        return UUID(uuidString: destinationProjectSelection)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            filterToolbar

            Divider()

            HSplitView {
                sessionListPane
                    .frame(minWidth: 340, idealWidth: 390, maxWidth: .infinity, maxHeight: .infinity)

                sessionInspectorPane
                    .frame(minWidth: 260, idealWidth: 290, maxWidth: 340, maxHeight: .infinity)
            }

            Divider()

            footerBar
        }
        .frame(width: 720, height: 520)
        .background(AppTheme.windowBackground)
        .task {
            await reloadSessions()
        }
        .onChange(of: filteredSessions) { _, newList in
            if selectedSessionID == nil || !newList.contains(where: { $0.id == selectedSessionID }) {
                selectedSessionID = newList.first?.id
            }
        }
    }

    // MARK: - Header & Filter Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Import CLI Session")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Text("Discover and import local Claude Code and Codex JSONL transcripts into Agents.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            Spacer()

            Button {
                promptBrowseCustomSessionFile()
            } label: {
                Label("Choose File…", systemImage: "doc.badge.plus")
            }
            .controlSize(.small)

            Button {
                Task { await reloadSessions() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(isScanning)
            .help("Rescan Local CLI Sessions")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var filterToolbar: some View {
        HStack(spacing: 10) {
            Picker("Provider", selection: $providerFilter) {
                Text("All Providers").tag("all")
                ForEach(discoveredProviders, id: \.self) { provider in
                    Text(AgentBranding.displayName(for: provider)).tag(provider)
                }
            }
            .labelsHidden()
            .frame(width: 145)

            if !regularProjects.isEmpty {
                Picker("Project", selection: $projectFilterID) {
                    Text("All Projects").tag("all")
                    ForEach(regularProjects) { project in
                        Text(project.name).tag(project.id.uuidString)
                    }
                }
                .labelsHidden()
                .frame(width: 155)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.tertiaryLabel)

                TextField("Filter by prompt, folder, or file…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.textBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .strokeBorder(AppTheme.separator, lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(AppTheme.elevatedCardFill)
    }

    // MARK: - Session List Pane

    @ViewBuilder
    private var sessionListPane: some View {
        if isScanning {
            VStack(spacing: 10) {
                ProgressView()
                Text("Scanning ~/.claude and ~/.codex sessions…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredSessions.isEmpty {
            ContentUnavailableView {
                Label(
                    sessions.isEmpty ? "No CLI Sessions Found" : "No Matching Sessions",
                    systemImage: "terminal"
                )
            } description: {
                Text(
                    sessions.isEmpty
                        ? "No local .jsonl sessions were found in ~/.claude or ~/.codex. You can also choose a session file manually."
                        : "Try clearing the provider, project, or search filter."
                )
            } actions: {
                if sessions.isEmpty {
                    Button("Choose .jsonl File…") {
                        promptBrowseCustomSessionFile()
                    }
                } else {
                    Button("Reset Filters") {
                        providerFilter = "all"
                        projectFilterID = "all"
                        searchQuery = ""
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filteredSessions, selection: $selectedSessionID) { session in
                sessionRow(session)
                    .tag(session.id)
                    .onTapGesture(count: 2) {
                        selectedSessionID = session.id
                        Task { await importSelectedSession() }
                    }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: CLISessionSummary) -> some View {
        HStack(alignment: .top, spacing: 9) {
            AgentLogoView(provider: session.provider, size: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)

                    if session.alreadyImported {
                        Text("Imported")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(AppTheme.info)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppTheme.info.opacity(0.14), in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    if let cwd = session.cwd, !cwd.isEmpty {
                        Text(Self.abbreviateHome(cwd))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text((session.path as NSString).lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if session.messageCount > 0 {
                        Text("\(session.messageCount) msg\(session.messageCount == 1 ? "" : "s")")
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }

                    if let updated = session.updatedAt {
                        Text(SidebarThreadRow.compactRelativeAge(from: updated))
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Inspector Detail Pane

    @ViewBuilder
    private var sessionInspectorPane: some View {
        if let session = selectedSession {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        AgentLogoView(provider: session.provider, size: 18)
                        Text(AgentBranding.displayName(for: session.provider))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                    }

                    Text(session.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    inspectorField(label: "Last Updated") {
                        Text(
                            session.updatedAt?.formatted(date: .abbreviated, time: .shortened)
                                ?? "Unknown"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.primaryLabel)
                    }

                    inspectorField(label: "Estimated User Prompts") {
                        Text("\(max(1, session.messageCount))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.primaryLabel)
                    }

                    if let cwd = session.cwd, !cwd.isEmpty {
                        inspectorField(label: "Working Directory") {
                            HStack(spacing: 6) {
                                Text(Self.abbreviateHome(cwd))
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                Spacer(minLength: 2)
                                Button {
                                    appModel.externalEditors.revealInFinder(path: cwd)
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)
                                .help("Reveal Working Directory in Finder")
                            }
                        }
                    }

                    inspectorField(label: "Session File") {
                        HStack(spacing: 6) {
                            Text(Self.abbreviateHome(session.path))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Spacer(minLength: 2)
                            Button {
                                appModel.externalEditors.revealInFinder(path: session.path)
                            } label: {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.borderless)
                            .help("Reveal Transcript File in Finder")
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Import Into")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryLabel)

                        Picker("Import Into", selection: $destinationProjectSelection) {
                            if let matched = autoMatchedProject(for: session) {
                                Text("Auto (\(matched.name))").tag("auto")
                            } else {
                                Text("Auto (Chats)").tag("auto")
                            }
                            Text("Chats (No Project)").tag("chats")
                            if !regularProjects.isEmpty {
                                Divider()
                                ForEach(regularProjects) { project in
                                    Text(project.name).tag(project.id.uuidString)
                                }
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding(16)
            }
            .background(AppTheme.controlBackground)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                Text("Select a session to inspect")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.controlBackground)
        }
    }

    @ViewBuilder
    private func inspectorField<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.tertiaryLabel)
            content()
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack(spacing: 10) {
            Text("\(filteredSessions.count) session\(filteredSessions.count == 1 ? "" : "s")")
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.tertiaryLabel)

            Spacer()

            Button("Cancel") {
                appModel.showSessionImport = false
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isImporting)

            Button {
                Task { await importSelectedSession() }
            } label: {
                if isImporting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Importing…")
                    }
                } else {
                    Text("Import Session")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selectedSession == nil || isImporting)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func reloadSessions() async {
        isScanning = true
        defer { isScanning = false }
        guard let client = appModel.runtime else {
            sessions = []
            return
        }
        let discovered = await client.discoverCLISessions()
        sessions = discovered
        if selectedSessionID == nil || !discovered.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = filteredSessions.first?.id ?? discovered.first?.id
        }
    }

    private func promptBrowseCustomSessionFile() {
        let panel = NSOpenPanel()
        panel.title = "Select CLI Session Transcript (.jsonl)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let jsonlType = UTType(filenameExtension: "jsonl") {
            panel.allowedContentTypes = [jsonlType, .json, .plainText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let customSummary = CLISessionSummary(
            id: url.path,
            provider: inferProvider(fromPath: url.path),
            title: url.deletingPathExtension().lastPathComponent,
            path: url.path,
            cwd: url.deletingLastPathComponent().path,
            updatedAt: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date(),
            messageCount: 1,
            alreadyImported: false
        )
        if !sessions.contains(where: { $0.path == url.path }) {
            sessions.insert(customSummary, at: 0)
        }
        providerFilter = "all"
        projectFilterID = "all"
        searchQuery = ""
        selectedSessionID = customSummary.id
    }

    private func inferProvider(fromPath path: String) -> String {
        let lower = path.lowercased()
        if lower.contains(".claude") || lower.contains("claude") {
            return "claude"
        }
        if lower.contains(".codex") || lower.contains("codex") {
            return "codex"
        }
        return "auto"
    }

    private func importSelectedSession() async {
        guard let session = selectedSession,
              let client = appModel.runtime
        else { return }

        isImporting = true
        defer { isImporting = false }

        do {
            let importedThreadID = try await client.importCLISession(
                path: session.path,
                provider: session.provider,
                projectID: resolvedTargetProjectID
            )
            await appModel.refreshWorkspace()
            appModel.selectThread(importedThreadID)
            appModel.showSessionImport = false
            appModel.presentToast(
                "Session Imported",
                detail: session.title,
                style: .success
            )
        } catch {
            appModel.presentError(error)
        }
    }

    // MARK: - Path Utilities

    private nonisolated static func abbreviateHome(_ rawPath: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if rawPath == home {
            return "~"
        }
        if rawPath.hasPrefix(home + "/") {
            return "~" + String(rawPath.dropFirst(home.count))
        }
        return rawPath
    }

    private nonisolated static func pathIsInside(child: String, parent: String) -> Bool {
        let cleanChild = (child as NSString).standardizingPath
        let cleanParent = (parent as NSString).standardizingPath
        if cleanChild == cleanParent { return true }
        let prefix = cleanParent.hasSuffix("/") ? cleanParent : cleanParent + "/"
        return cleanChild.hasPrefix(prefix)
    }
}
