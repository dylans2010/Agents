import AppKit
import CoincideRemoteKit
import SwiftUI

struct WorkspaceFilesInspectorView: View {
    @Bindable var appModel: AppModel
    var refreshToken: UUID

    enum Mode: String, CaseIterable, Identifiable {
        case browse
        case search

        var id: String { rawValue }

        var title: String {
            switch self {
            case .browse: "Browse Files"
            case .search: "Search in Files"
            }
        }

        var symbolName: String {
            switch self {
            case .browse: "doc.text"
            case .search: "text.magnifyingglass"
            }
        }
    }

    @State private var mode: Mode = .browse
    @State private var queryText: String = ""
    @State private var fileEntries: [WorkspaceFileEntry] = []
    @State private var searchHits: [WorkspaceSearchHit] = []
    @State private var isLoadingResults: Bool = false

    // Editor Document State
    @State private var selectedFilePath: String?
    @State private var loadedDocument: WorkspaceFileDocument?
    @State private var editorContent: String = ""
    @State private var isLoadingDocument: Bool = false
    @State private var isSavingDocument: Bool = false
    @State private var wrapsLines: Bool = false
    @State private var cursorLine: Int = 1
    @State private var cursorColumn: Int = 1
    @State private var jumpTarget: CodeEditorJumpTarget?

    // Unsaved-buffer confirmation state
    @State private var pendingOpenAction: PendingFileSelection?
    @State private var showUnsavedDiscardAlert: Bool = false

    @State private var pendingDeleteEntry: WorkspaceFileEntry?
    @State private var renameEntry: WorkspaceFileEntry?
    @State private var renameText: String = ""

    private var activeCwd: String {
        appModel.activeWorkingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    private var isDirty: Bool {
        guard let doc = loadedDocument, !doc.isBinary else { return false }
        return editorContent != doc.content
    }

    var body: some View {
        VStack(spacing: 0) {
            modeAndSearchHeader
            Divider()

            VSplitView {
                resultsPane
                    .frame(minHeight: 130, idealHeight: 200, maxHeight: 320)

                editorPane
                    .frame(minHeight: 220, maxHeight: .infinity)
            }
        }
        .background(AppTheme.windowBackground)
        .onAppear {
            consumePendingInspectorFileRequest()
        }
        .onChange(of: appModel.openFileInInspectorRequest) { _, _ in
            consumePendingInspectorFileRequest()
        }
        .task(id: FilesQueryReloadKey(cwd: activeCwd, mode: mode, query: queryText, token: refreshToken)) {
            if !queryText.isEmpty {
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
            }
            await executeQuery()
        }
        .confirmationDialog(
            "Unsaved Changes in \((loadedDocument?.path as NSString?)?.lastPathComponent ?? "File")",
            isPresented: $showUnsavedDiscardAlert,
            presenting: pendingOpenAction
        ) { pending in
            Button("Save & Open") {
                pendingOpenAction = nil
                Task {
                    await saveCurrentDocument()
                    await openFile(path: pending.path, line: pending.line, column: pending.column)
                }
            }
            Button("Discard Changes", role: .destructive) {
                pendingOpenAction = nil
                Task {
                    await openFile(path: pending.path, line: pending.line, column: pending.column)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingOpenAction = nil
            }
        } message: { _ in
            Text("You have unsaved edits in the Inspector Editor. Save before switching files?")
        }
        .confirmationDialog(
            "Delete \((pendingDeleteEntry?.name ?? "File"))?",
            isPresented: Binding(
                get: { pendingDeleteEntry != nil },
                set: { if !$0 { pendingDeleteEntry = nil } }
            ),
            presenting: pendingDeleteEntry
        ) { entry in
            if entry.isDirectory {
                Button("Delete Contents Too", role: .destructive) {
                    pendingDeleteEntry = nil
                    Task { await deleteEntry(entry, recursive: true) }
                }
                Button("Delete Empty Folder", role: .destructive) {
                    pendingDeleteEntry = nil
                    Task { await deleteEntry(entry, recursive: false) }
                }
            } else {
                Button("Delete", role: .destructive) {
                    pendingDeleteEntry = nil
                    Task { await deleteEntry(entry, recursive: false) }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteEntry = nil
            }
        } message: { entry in
            Text("“\(entry.path)” is permanently removed from the workspace. This cannot be undone.")
        }
        .sheet(item: $renameEntry) { entry in
            VStack(alignment: .leading, spacing: 14) {
                Text("Rename \(entry.isDirectory ? "Folder" : "File")")
                    .font(.system(size: 14, weight: .semibold))
                Text(entry.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryLabel)
                TextField("New name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
                    .onSubmit {
                        submitRename(entry)
                    }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        renameEntry = nil
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Rename") {
                        submitRename(entry)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(sanitizedRenameText.isEmpty || sanitizedRenameText == entry.name)
                }
            }
            .padding(18)
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
            .onAppear {
                renameText = entry.name
            }
        }
    }

    // MARK: - Top Mode & Search Bar

    private var modeAndSearchHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Label(item.title, systemImage: item.symbolName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("File browser mode")
                .controlSize(.small)

                Button {
                    ExternalEditorService.shared.revealInFinder(path: activeCwd)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.borderless)
                .help("Reveal \((activeCwd as NSString).abbreviatingWithTildeInPath) in Finder")
                .accessibilityLabel("Reveal workspace folder in Finder")
            }

            HStack(spacing: 6) {
                Image(systemName: mode == .browse ? "magnifyingglass" : "text.magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryLabel)

                TextField(
                    mode == .browse ? "Filter files by path or name…" : "Search text across workspace files…",
                    text: $queryText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .onSubmit {
                    Task { await executeQuery() }
                }

                if isLoadingResults {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                } else if !queryText.isEmpty {
                    Button {
                        queryText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear file search")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .fill(AppTheme.textBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .strokeBorder(AppTheme.separator, lineWidth: 0.75)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.controlBackground)
    }

    // MARK: - Top Results Pane

    @ViewBuilder
    private var resultsPane: some View {
        switch mode {
        case .browse:
            if fileEntries.isEmpty && !isLoadingResults {
                ContentUnavailableView(
                    queryText.isEmpty ? "No Workspace Files" : "No Matching Files",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(
                        queryText.isEmpty
                            ? "No files found in \((activeCwd as NSString).abbreviatingWithTildeInPath)."
                            : "No files matched “\(queryText)”."
                    )
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(fileEntries) { entry in
                            WorkspaceFileRow(
                                entry: entry,
                                isSelected: selectedFilePath == entry.path,
                                onSelect: {
                                    guard !entry.isDirectory else {
                                        queryText = entry.path + "/"
                                        return
                                    }
                                    requestOpenFile(path: entry.path, line: nil, column: nil)
                                },
                                onMentionInComposer: {
                                    mentionInComposer(path: entry.path, line: nil)
                                },
                                onRevealInFinder: {
                                    ExternalEditorService.shared.revealInFinder(path: resolvedAbsolutePath(for: entry.path))
                                },
                                onOpenExternal: { editor in
                                    openInExternalEditor(path: entry.path, line: nil, column: nil, target: editor)
                                },
                                onRename: {
                                    renameEntry = entry
                                },
                                onDelete: {
                                    pendingDeleteEntry = entry
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .background(AppTheme.underPageBackground.opacity(0.45))
            }

        case .search:
            if queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Search Workspace Contents",
                    systemImage: "text.magnifyingglass",
                    description: Text("Type a symbol, string, or pattern above to search across \((activeCwd as NSString).abbreviatingWithTildeInPath).")
                )
            } else if searchHits.isEmpty && !isLoadingResults {
                ContentUnavailableView(
                    "No Matches Found",
                    systemImage: "magnifyingglass",
                    description: Text("No lines matched “\(queryText)”.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(searchHits) { hit in
                            WorkspaceSearchHitRow(
                                hit: hit,
                                isSelected: selectedFilePath == hit.path && cursorLine == hit.lineNumber
                            ) {
                                requestOpenFile(path: hit.path, line: hit.lineNumber, column: hit.column)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .background(AppTheme.underPageBackground.opacity(0.45))
            }
        }
    }

    // MARK: - Bottom Native Code Editor Pane

    @ViewBuilder
    private var editorPane: some View {
        if isLoadingDocument && loadedDocument == nil {
            VStack(spacing: 8) {
                ProgressView()
                Text("Opening file…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let doc = loadedDocument {
            VStack(spacing: 0) {
                editorHeaderToolbar(doc)
                Divider()

                if doc.isBinary {
                    ContentUnavailableView {
                        Label("Binary File", systemImage: "doc.zipper")
                    } description: {
                        Text("\(doc.path) (\(ByteCountFormatter.string(fromByteCount: doc.sizeBytes, countStyle: .file))) cannot be edited as plain text.")
                    } actions: {
                        HStack(spacing: 8) {
                            Button("Reveal in Finder") {
                                ExternalEditorService.shared.revealInFinder(path: resolvedAbsolutePath(for: doc.path))
                            }
                            if let preferred = ExternalEditorService.shared.preferredEditor {
                                Button("Open in \(preferred.name)") {
                                    openInExternalEditor(path: doc.path, line: nil, column: nil, target: preferred)
                                }
                            }
                        }
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if doc.isTruncated {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.warning)
                            Text("Large file preview truncated at \(ByteCountFormatter.string(fromByteCount: doc.sizeBytes, countStyle: .file)). Read-only in Inspector — open externally to edit full file.")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.warning.opacity(0.10))
                        Divider()
                    }

                    NativeCodeEditorNSView(
                        text: $editorContent,
                        cursorLine: $cursorLine,
                        cursorColumn: $cursorColumn,
                        isEditable: !doc.isTruncated,
                        wrapsLines: wrapsLines,
                        fontScale: appModel.fontScale,
                        jumpTarget: jumpTarget,
                        onSaveShortcut: {
                            if isDirty && !doc.isTruncated {
                                Task { await saveCurrentDocument() }
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                    editorStatusBar(doc)
                }
            }
        } else {
            ContentUnavailableView(
                "Select a File to View or Edit",
                systemImage: "curlybraces",
                description: Text("Choose a file or search result above, or click any file path in a diff or conversation.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editorHeaderToolbar(_ doc: WorkspaceFileDocument) -> some View {
        let fileName = (doc.path as NSString).lastPathComponent
        return HStack(spacing: 6) {
            Image(systemName: fileIcon(for: doc.path, isDirectory: false))
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.accent)

            Text(fileName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.primaryLabel)
                .lineLimit(1)

            if isDirty {
                HStack(spacing: 3) {
                    Circle()
                        .fill(AppTheme.warning)
                        .frame(width: 6, height: 6)
                    Text("Modified")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(AppTheme.warning.opacity(0.12)))
            }

            Spacer(minLength: 4)

            if !doc.isBinary && !doc.isTruncated {
                if isDirty {
                    Button("Revert") {
                        editorContent = doc.content
                    }
                    .controlSize(.mini)
                    .help("Discard unsaved edits")
                }

                Button {
                    Task { await saveCurrentDocument() }
                } label: {
                    if isSavingDocument {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 34)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(!isDirty || isSavingDocument)
                .keyboardShortcut("s", modifiers: [.command])
                .help("Save File (⌘S)")
            }

            // Mention @file in Composer
            Menu {
                Button("Mention @\(doc.path) in Composer") {
                    mentionInComposer(path: doc.path, line: nil)
                }
                Button("Mention @\(doc.path):\(cursorLine) in Composer") {
                    mentionInComposer(path: doc.path, line: cursorLine)
                }
            } label: {
                Image(systemName: "at")
                    .font(.system(size: 11, weight: .semibold))
            } primaryAction: {
                mentionInComposer(path: doc.path, line: cursorLine > 1 ? cursorLine : nil)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Mention @\(doc.path) in Composer")
            .accessibilityLabel("Mention file in composer")

            // Reveal in Finder
            Button {
                ExternalEditorService.shared.revealInFinder(path: resolvedAbsolutePath(for: doc.path))
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal file in Finder")

            // Open at Line in External Editor
            Menu {
                let editors = ExternalEditorService.shared.installedEditors
                if editors.isEmpty {
                    Button("Reveal in Finder") {
                        ExternalEditorService.shared.revealInFinder(path: resolvedAbsolutePath(for: doc.path))
                    }
                } else {
                    ForEach(editors) { editor in
                        Button("Open at Line \(cursorLine) in \(editor.name)") {
                            openInExternalEditor(
                                path: doc.path,
                                line: cursorLine,
                                column: cursorColumn,
                                target: editor
                            )
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
            } primaryAction: {
                openInExternalEditor(
                    path: doc.path,
                    line: cursorLine,
                    column: cursorColumn,
                    target: ExternalEditorService.shared.preferredEditor
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Open at Line \(cursorLine) in External Editor")
            .accessibilityLabel("Open file in external editor")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppTheme.controlBackground)
    }

    private func editorStatusBar(_ doc: WorkspaceFileDocument) -> some View {
        HStack(spacing: 8) {
            Text("Ln \(cursorLine), Col \(cursorColumn)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryLabel)

            Text("·")
                .foregroundStyle(AppTheme.quaternaryLabel)

            Text(doc.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.tertiaryLabel)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 4)

            if let lang = doc.language, !lang.isEmpty {
                Text(lang.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.tertiaryLabel)
            }

            Button {
                wrapsLines.toggle()
            } label: {
                Text(wrapsLines ? "Wrap: On" : "Wrap: Off")
                    .font(.system(size: 11))
                    .foregroundStyle(wrapsLines ? AppTheme.accent : AppTheme.tertiaryLabel)
            }
            .buttonStyle(.plain)
            .help("Toggle Soft Line Wrap")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.controlBackground)
    }

    // MARK: - Operations

    private func consumePendingInspectorFileRequest() {
        guard let req = appModel.openFileInInspectorRequest else { return }
        appModel.openFileInInspectorRequest = nil
        requestOpenFile(path: req.path, line: req.line, column: req.column)
    }

    private func executeQuery() async {
        guard let client = appModel.runtime else { return }
        let cwd = activeCwd
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoadingResults = true
        defer { isLoadingResults = false }

        do {
            switch mode {
            case .browse:
                let files = try await client.listWorkspaceFiles(cwd: cwd, query: trimmed, limit: 400)
                self.fileEntries = files
            case .search:
                guard !trimmed.isEmpty else {
                    self.searchHits = []
                    return
                }
                let hits = try await client.searchWorkspace(cwd: cwd, query: trimmed, limit: 200)
                self.searchHits = hits
            }
        } catch {
            // Keep UI responsive without spamming modal toasts while typing
            if mode == .browse {
                self.fileEntries = []
            } else {
                self.searchHits = []
            }
        }
    }

    private func requestOpenFile(path rawPath: String, line: Int?, column: Int?) {
        let normalizedPath = normalizedWorkspaceRelativeOrAbsolutePath(rawPath)

        // Same file already open -> just jump directly to line/column!
        if let current = loadedDocument, current.path == normalizedPath {
            selectedFilePath = normalizedPath
            if let line {
                jumpTarget = CodeEditorJumpTarget(line: line, column: column)
            }
            return
        }

        if isDirty {
            pendingOpenAction = PendingFileSelection(path: normalizedPath, line: line, column: column)
            showUnsavedDiscardAlert = true
            return
        }

        Task {
            await openFile(path: normalizedPath, line: line, column: column)
        }
    }

    private func openFile(path: String, line: Int?, column: Int?) async {
        guard let client = appModel.runtime else { return }
        isLoadingDocument = true
        defer { isLoadingDocument = false }

        do {
            let doc = try await client.readWorkspaceFile(cwd: activeCwd, path: path)
            self.selectedFilePath = doc.path
            self.loadedDocument = doc
            self.editorContent = doc.content
            self.cursorLine = line ?? 1
            self.cursorColumn = column ?? 1
            if let line {
                self.jumpTarget = CodeEditorJumpTarget(line: line, column: column)
            } else {
                self.jumpTarget = CodeEditorJumpTarget(line: 1, column: 1)
            }
        } catch {
            appModel.presentError(error)
        }
    }

    private var sanitizedRenameText: String {
        renameText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "")
    }

    private func submitRename(_ entry: WorkspaceFileEntry) {
        let name = sanitizedRenameText
        guard !name.isEmpty, name != entry.name else { return }
        renameEntry = nil
        Task { await performRename(entry, to: name) }
    }

    private func deleteEntry(_ entry: WorkspaceFileEntry, recursive: Bool) async {
        guard let client = appModel.runtime else { return }
        do {
            if entry.isDirectory {
                try await client.deleteWorkspaceDirectory(cwd: activeCwd, path: entry.path, recursive: recursive)
            } else {
                try await client.deleteWorkspaceFile(cwd: activeCwd, path: entry.path)
            }
            if let docPath = loadedDocument?.path, docPath == entry.path || docPath.hasPrefix(entry.path + "/") {
                loadedDocument = nil
                editorContent = ""
                selectedFilePath = nil
            }
            appModel.presentToast("Deleted", detail: entry.name, style: .success)
            await executeQuery()
            await appModel.refreshDiff()
            await appModel.refreshGitState()
        } catch {
            appModel.presentError(error)
        }
    }

    private func performRename(_ entry: WorkspaceFileEntry, to newName: String) async {
        guard let client = appModel.runtime else { return }
        if loadedDocument?.path == entry.path && isDirty {
            appModel.presentToast(
                "Save or Revert First",
                detail: "You have unsaved edits in \(entry.name). Save or revert before renaming it.",
                style: .warning
            )
            return
        }
        let parent = (entry.path as NSString).deletingLastPathComponent
        let destination = parent.isEmpty ? newName : parent + "/" + newName
        do {
            try await client.moveWorkspaceFile(cwd: activeCwd, path: entry.path, destination: destination)
            if loadedDocument?.path == entry.path {
                loadedDocument = nil
                editorContent = ""
                selectedFilePath = nil
            }
            appModel.presentToast("Renamed", detail: "\(entry.name) → \(newName)", style: .success)
            await executeQuery()
            await appModel.refreshDiff()
            await appModel.refreshGitState()
        } catch {
            appModel.presentError(error)
        }
    }

    private func saveCurrentDocument() async {
        guard let client = appModel.runtime,
              var doc = loadedDocument,
              !doc.isBinary,
              !doc.isTruncated
        else { return }

        isSavingDocument = true
        defer { isSavingDocument = false }

        do {
            let contentToSave = editorContent
            try await client.writeWorkspaceFile(cwd: activeCwd, path: doc.path, content: contentToSave)
            doc.content = contentToSave
            doc.sizeBytes = Int64(contentToSave.utf8.count)
            doc.lineCount = max(1, contentToSave.components(separatedBy: "\n").count)
            self.loadedDocument = doc
            appModel.presentToast(
                "Saved File",
                detail: (doc.path as NSString).lastPathComponent,
                style: .success
            )
            // Keep Diff & Git state synchronized after saving
            await appModel.refreshDiff()
            await appModel.refreshGitState()
        } catch {
            appModel.presentError(error)
        }
    }

    private func normalizedWorkspaceRelativeOrAbsolutePath(_ rawPath: String) -> String {
        let expanded = ExternalEditorService.expandedPath(rawPath)
        let cwdPrefix = activeCwd.hasSuffix("/") ? activeCwd : activeCwd + "/"
        if expanded.hasPrefix(cwdPrefix) {
            return String(expanded.dropFirst(cwdPrefix.count))
        }
        return rawPath
    }

    private func resolvedAbsolutePath(for path: String) -> String {
        if let doc = loadedDocument, doc.path == path, let abs = doc.absolutePath, !abs.isEmpty {
            return abs
        }
        let expanded = ExternalEditorService.expandedPath(path)
        if (expanded as NSString).isAbsolutePath {
            return expanded
        }
        return URL(fileURLWithPath: activeCwd).appendingPathComponent(expanded).path
    }

    private func mentionInComposer(path: String, line: Int?) {
        let token = if let line, line > 0 {
            "@\(path):\(line) "
        } else {
            "@\(path) "
        }
        appModel.insertTextIntoComposer(token)
        appModel.presentToast("Added to Composer", detail: token.trimmingCharacters(in: .whitespaces), style: .info)
    }

    private func openInExternalEditor(path: String, line: Int?, column: Int?, target: ExternalAppTarget?) {
        let resolvedTarget = target ?? ExternalEditorService.shared.preferredEditor
        guard let resolvedTarget else {
            appModel.presentToast(
                "No External Editor Found",
                detail: "Install an editor like Xcode, VS Code, Cursor, or Zed.",
                style: .warning
            )
            return
        }
        do {
            try ExternalEditorService.shared.open(
                path: resolvedAbsolutePath(for: path),
                line: line,
                column: column,
                in: resolvedTarget
            )
        } catch {
            appModel.presentError(error)
        }
    }
}

private struct FilesQueryReloadKey: Equatable {
    let cwd: String
    let mode: WorkspaceFilesInspectorView.Mode
    let query: String
    let token: UUID
}

private struct PendingFileSelection: Identifiable {
    let id = UUID()
    let path: String
    let line: Int?
    let column: Int?
}

// MARK: - File Icon Helper

private func fileIcon(for path: String, isDirectory: Bool) -> String {
    if isDirectory { return "folder.fill" }
    let ext = (path as NSString).pathExtension.lowercased()
    return switch ext {
    case "swift": "swift"
    case "rs", "go", "c", "cpp", "h", "hpp", "py", "js", "ts", "tsx", "jsx", "java", "kt", "rb":
        "curlybraces"
    case "json", "toml", "yaml", "yml", "xml", "plist":
        "gearshape.2"
    case "md", "txt", "rst":
        "doc.richtext"
    case "sh", "zsh", "bash":
        "terminal"
    case "png", "jpg", "jpeg", "gif", "webp", "svg", "icns":
        "photo"
    default:
        "doc.text"
    }
}

// MARK: - Browse File Row

private struct WorkspaceFileRow: View {
    let entry: WorkspaceFileEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onMentionInComposer: () -> Void
    let onRevealInFinder: () -> Void
    let onOpenExternal: (ExternalAppTarget?) -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    private var directoryPrefix: String? {
        let dir = (entry.path as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: fileIcon(for: entry.path, isDirectory: entry.isDirectory))
                .font(.system(size: 11.5))
                .foregroundStyle(entry.isDirectory ? AppTheme.info : AppTheme.secondaryLabel)
                .frame(width: 14)

            Text(entry.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(AppTheme.primaryLabel)
                .lineLimit(1)

            if let dir = directoryPrefix {
                Text(dir)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if let status = entry.gitStatus, !status.isEmpty {
                Text(status.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DiffFileStatusStyle.tint(for: status))
            }

            if isHovered && !entry.isDirectory {
                Button(action: onMentionInComposer) {
                    Image(systemName: "at")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .buttonStyle(.borderless)
                .help("Mention @\(entry.path) in Composer")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(
                    isSelected
                        ? AppTheme.unemphasizedSelectedBackground
                        : (isHovered ? AppTheme.subtleHoverFill : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .contextMenu {
            if !entry.isDirectory {
                Button("Open in Inspector Editor", systemImage: "doc.text", action: onSelect)
                Button("Mention @\(entry.name) in Composer", systemImage: "at", action: onMentionInComposer)
                if let preferred = ExternalEditorService.shared.preferredEditor {
                    Button("Open in \(preferred.name)", systemImage: "arrow.up.forward.app") {
                        onOpenExternal(preferred)
                    }
                }
                Divider()
            }
            Button("Reveal in Finder", systemImage: "folder", action: onRevealInFinder)
            Divider()
            Button("Rename…", systemImage: "pencil", action: onRename)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Search Hit Row

private struct WorkspaceSearchHitRow: View {
    let hit: WorkspaceSearchHit
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: fileIcon(for: hit.path, isDirectory: false))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(hit.path)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 4)
                Text(":\(hit.lineNumber)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.accent)
            }

            Text(hit.lineText.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryLabel)
                .lineLimit(1)
                .padding(.leading, 16)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(
                    isSelected
                        ? AppTheme.unemphasizedSelectedBackground
                        : (isHovered ? AppTheme.subtleHoverFill : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }
}
