import AppKit
import CoincideRemoteKit
import SwiftUI

struct DiffInspectorView: View {
    @Bindable var appModel: AppModel
    var refreshToken: UUID

    @State private var selectedFilePath: String?
    @State private var collapsedPaths: Set<String> = []
    @State private var fileFilterQuery: String = ""
    @State private var wrapsLines: Bool = false
    @State private var isLoading: Bool = false
    @State private var scrollRequestID: String?
    @State private var showCompareSheet: Bool = false
    @State private var compareFrom: String = ""
    @State private var compareTo: String = ""
    @State private var compareBranches: [String] = []
    @State private var isLoadingCompareBranches: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            diffToolbar
            Divider()

            if appModel.selectedThreadUUID == nil {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "plusminus",
                    description: Text("Select a conversation to inspect uncommitted or per-turn file diffs.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedFiles.isEmpty {
                cleanStateView
            } else {
                VSplitView {
                    changedFilesListPane
                        .frame(minHeight: 110, idealHeight: 175, maxHeight: 420)

                    unifiedDiffViewport
                        .frame(minHeight: 180, maxHeight: .infinity)
                }
            }
        }
        .background(AppTheme.windowBackground)
        .task(id: DiffLoadKey(threadID: appModel.selectedThreadID, scope: appModel.activeDiffScope, token: refreshToken)) {
            await reloadDiff()
        }
        .sheet(isPresented: $showCompareSheet) {
            compareSheet
        }
    }

    // MARK: - Computed Data

    private var availableTurnScopes: [(itemID: UUID, label: String, count: Int)] {
        guard let transcript = appModel.activeTranscript else { return [] }
        var entries: [(UUID, String, Int)] = []
        for item in transcript.items where item.kind == .user {
            let matchingFiles = transcript.turnChanges.first { key, _ in
                key.caseInsensitiveCompare(item.id.uuidString) == .orderedSame
            }?.value
            if let files = matchingFiles, !files.isEmpty {
                let snippet = item.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines)
                    .first ?? "Turn"
                let short = snippet.count > 34 ? String(snippet.prefix(34)) + "…" : snippet
                entries.append((item.id, short.isEmpty ? "Turn" : short, files.count))
            }
        }
        return entries.reversed()
    }

    private var rawDiffFiles: [RemoteDiff.File] {
        if let diff = appModel.activeDiff, !diff.files.isEmpty {
            return diff.files
        }
        // Fallback summary from transcript.turnChanges if a turn scope is active and patch is empty
        if case .turn(let turnUUID) = appModel.activeDiffScope,
           let transcript = appModel.activeTranscript,
           let turnFiles = transcript.turnChanges.first(where: {
               $0.key.caseInsensitiveCompare(turnUUID.uuidString) == .orderedSame
           })?.value
        {
            return turnFiles.map { changed in
                RemoteDiff.File(
                    path: changed.path,
                    oldPath: changed.oldPath,
                    status: changed.status,
                    additions: changed.additions,
                    deletions: changed.deletions,
                    isBinary: false,
                    patch: ""
                )
            }
        }
        return []
    }

    private var displayedFiles: [RemoteDiff.File] {
        let q = fileFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return rawDiffFiles }
        return rawDiffFiles.filter { file in
            file.path.lowercased().contains(q)
                || (file.oldPath?.lowercased().contains(q) ?? false)
                || file.status.lowercased().contains(q)
        }
    }

    private var totalAdditions: Int {
        displayedFiles.reduce(0) { $0 + $1.additions }
    }

    private var totalDeletions: Int {
        displayedFiles.reduce(0) { $0 + $1.deletions }
    }

    // MARK: - Toolbar

    private var diffToolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Menu {
                    Button {
                        Task { await appModel.refreshDiff(scope: .uncommitted) }
                    } label: {
                        HStack {
                            Text("Uncommitted Changes")
                            if appModel.activeDiffScope == .uncommitted {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        Task { await appModel.refreshDiff(scope: .branch) }
                    } label: {
                        HStack {
                            Text("Branch vs Base")
                            if appModel.activeDiffScope == .branch {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        Task { await loadCompareBranches() }
                        showCompareSheet = true
                    } label: {
                        HStack {
                            Text("Compare Branches…")
                            if case .compare = appModel.activeDiffScope {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    let turns = availableTurnScopes
                    if !turns.isEmpty {
                        Divider()
                        Section("Turn Snapshots") {
                            ForEach(turns, id: \.itemID) { turn in
                                Button {
                                    Task { await appModel.refreshDiff(scope: .turn(turn.itemID)) }
                                } label: {
                                    HStack {
                                        Text("\(turn.label) (\(turn.count))")
                                        if appModel.activeDiffScope == .turn(turn.itemID) {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: scopeButtonIcon)
                            .font(.system(size: 11, weight: .medium))
                        Text(scopeButtonTitle)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                if !displayedFiles.isEmpty {
                    HStack(spacing: 5) {
                        Text("+\(totalAdditions)")
                            .foregroundStyle(AppTheme.diffAdditionText)
                        Text("−\(totalDeletions)")
                            .foregroundStyle(AppTheme.diffDeletionText)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))

                    Button {
                        wrapsLines.toggle()
                    } label: {
                        Image(systemName: wrapsLines ? "arrow.turn.down.left" : "arrow.left.and.right.text.vertical")
                            .font(.system(size: 11))
                            .foregroundStyle(wrapsLines ? AppTheme.accent : AppTheme.secondaryLabel)
                    }
                    .buttonStyle(.borderless)
                    .help(wrapsLines ? "Disable Line Wrapping" : "Wrap Long Diff Lines")
                    .accessibilityLabel(wrapsLines ? "Disable line wrapping" : "Wrap long diff lines")

                    Button {
                        copyAllPatchesToPasteboard()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Full Unified Patch")
                    .accessibilityLabel("Copy full unified patch")
                }

                Button {
                    Task { await reloadDiff() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderless)
                .help("Refresh Diff")
                .accessibilityLabel("Refresh diff")
            }

            if rawDiffFiles.count > 3 || !fileFilterQuery.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                    TextField("Filter changed files…", text: $fileFilterQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                    if !fileFilterQuery.isEmpty {
                        Button {
                            fileFilterQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear file filter")
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

            if appModel.activeDiff?.isTruncated == true {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.warning)
                    Text("Large diff truncated for responsiveness. Open individual files in the Inspector Editor to view full contents.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.controlBackground)
    }

    private var scopeButtonTitle: String {
        switch appModel.activeDiffScope {
        case .uncommitted:
            return appModel.activeDiff?.title.isEmpty == false ? (appModel.activeDiff?.title ?? "Uncommitted") : "Uncommitted"
        case .turn(let id):
            if let match = availableTurnScopes.first(where: { $0.itemID == id }) {
                return "Turn: \(match.label)"
            }
            return "Turn Changes"
        case .branch:
            return appModel.activeDiff?.title.isEmpty == false ? (appModel.activeDiff?.title ?? "Branch vs Base") : "Branch vs Base"
        case .compare(let from, let to):
            return "Compare \(from)…\(to)"
        }
    }

    private var scopeButtonIcon: String {
        switch appModel.activeDiffScope {
        case .uncommitted: "square.and.pencil"
        case .turn: "clock.arrow.circlepath"
        case .branch: "arrow.triangle.branch"
        case .compare: "arrow.left.arrow.right"
        }
    }

    // MARK: - Empty / Clean State

    private var cleanStateView: some View {
        ContentUnavailableView {
            Label(
                fileFilterQuery.isEmpty ? "Working Tree Clean" : "No Matching Changed Files",
                systemImage: fileFilterQuery.isEmpty ? "checkmark.circle" : "magnifyingglass"
            )
        } description: {
            Text(
                fileFilterQuery.isEmpty
                    ? "There are no uncommitted changes in the active workspace."
                    : "No changed files match “\(fileFilterQuery)”."
            )
        } actions: {
            HStack(spacing: 8) {
                if !fileFilterQuery.isEmpty {
                    Button("Clear Filter") {
                        fileFilterQuery = ""
                    }
                }
                Button("Refresh") {
                    Task { await reloadDiff() }
                }
                Button("Browse Files") {
                    appModel.inspectorTab = .files
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Changed Files List Pane

    private var changedFilesListPane: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(displayedFiles) { file in
                    DiffFileSummaryRow(
                        file: file,
                        isSelected: selectedFilePath == file.path,
                        onSelect: {
                            selectedFilePath = file.path
                            collapsedPaths.remove(file.path)
                            scrollRequestID = file.path
                        },
                        onOpenInInspector: {
                            appModel.openFileInInspector(
                                path: file.path,
                                line: firstTargetLine(in: file)
                            )
                        },
                        onOpenInExternalEditor: { target in
                            openInExternalEditor(file: file, line: firstTargetLine(in: file), target: target)
                        },
                        onRevealInFinder: {
                            revealFileInFinder(file.path)
                        },
                        onQuoteInComposer: {
                            quoteFileInComposer(file.path)
                        },
                        onCopyPatch: {
                            copyPatch(for: file)
                        }
                    )
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .background(AppTheme.underPageBackground.opacity(0.45))
    }

    // MARK: - Unified Diff Viewport

    private var unifiedDiffViewport: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(displayedFiles) { file in
                        DiffFilePatchCard(
                            file: file,
                            fontScale: appModel.fontScale,
                            wrapsLines: wrapsLines,
                            isFocused: selectedFilePath == file.path,
                            isCollapsed: collapsedPaths.contains(file.path),
                            onToggleCollapse: {
                                if collapsedPaths.contains(file.path) {
                                    collapsedPaths.remove(file.path)
                                } else {
                                    collapsedPaths.insert(file.path)
                                }
                            },
                            onOpenInInspector: { line in
                                appModel.openFileInInspector(
                                    path: file.path,
                                    line: line ?? firstTargetLine(in: file)
                                )
                            },
                            onOpenInExternalEditor: { target, line in
                                openInExternalEditor(
                                    file: file,
                                    line: line ?? firstTargetLine(in: file),
                                    target: target
                                )
                            },
                            onRevealInFinder: {
                                revealFileInFinder(file.path)
                            },
                            onQuoteInComposer: {
                                quoteFileInComposer(file.path)
                            },
                            onCopyPatch: {
                                copyPatch(for: file)
                            }
                        )
                        .id(file.path)
                    }
                }
                .padding(8)
            }
            .onChange(of: scrollRequestID) { _, targetID in
                guard let targetID else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(targetID, anchor: .top)
                }
                scrollRequestID = nil
            }
        }
        .background(AppTheme.windowBackground)
    }

    // MARK: - Actions

    private func reloadDiff() async {
        guard appModel.selectedThreadUUID != nil else { return }
        isLoading = true
        defer { isLoading = false }
        await appModel.refreshDiff()
        if let selected = selectedFilePath, !rawDiffFiles.contains(where: { $0.path == selected }) {
            selectedFilePath = rawDiffFiles.first?.path
        } else if selectedFilePath == nil {
            selectedFilePath = rawDiffFiles.first?.path
        }
    }

    private func loadCompareBranches() async {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID else { return }
        isLoadingCompareBranches = true
        defer { isLoadingCompareBranches = false }
        do {
            let value = try await client.runGitActionsOperation(
                method: "git.branches.list",
                params: ["threadId": .string(tid.uuidString.lowercased())]
            )
            let branches = value["branches"]?.arrayValue ?? []
            let local = branches.compactMap { branch -> (name: String, isCurrent: Bool, isDefault: Bool)? in
                guard let name = branch["name"]?.stringValue, branch["isRemote"]?.boolValue != true else { return nil }
                return (name, branch["isCurrent"]?.boolValue ?? false, branch["isDefault"]?.boolValue ?? false)
            }
            compareBranches = local.map { $0.name }
            if compareFrom.isEmpty {
                compareFrom = local.first(where: { $0.isDefault })?.name ?? local.first?.name ?? "main"
            }
            if compareTo.isEmpty {
                compareTo = local.first(where: { $0.isCurrent })?.name ?? local.first?.name ?? ""
            }
        } catch {
            appModel.presentError(error)
        }
    }

    private var compareSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compare Branches")
                .font(.system(size: 14, weight: .semibold))
            Text("Shows what changed between the merge base of the first branch and the second branch.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
            if isLoadingCompareBranches {
                ProgressView()
                    .controlSize(.small)
            } else if compareBranches.isEmpty {
                Text("No local branches found for this thread.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Picker("From branch", selection: $compareFrom) {
                            ForEach(compareBranches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                        .labelsHidden()
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("To")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Picker("To branch", selection: $compareTo) {
                            ForEach(compareBranches, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    showCompareSheet = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Compare") {
                    showCompareSheet = false
                    Task { await appModel.refreshDiff(scope: .compare(from: compareFrom, to: compareTo)) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(compareFrom.isEmpty || compareTo.isEmpty || compareFrom == compareTo)
            }
        }
        .padding(18)
        .frame(minWidth: 340, idealWidth: 520, maxWidth: 640)
    }

    private func firstTargetLine(in file: RemoteDiff.File) -> Int? {
        guard !file.patch.isEmpty else { return nil }
        let parsed = RemoteDiffParsing.lines(of: file.patch)
        return parsed.first(where: { $0.kind == .addition })?.newLine
            ?? parsed.first(where: { $0.newLine != nil })?.newLine
            ?? parsed.first(where: { $0.oldLine != nil })?.oldLine
    }

    private func resolvedAbsolutePath(for relativeOrAbsolute: String) -> String {
        let expanded = ExternalEditorService.expandedPath(relativeOrAbsolute)
        if (expanded as NSString).isAbsolutePath {
            return expanded
        }
        let base = appModel.activeWorkingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: base).appendingPathComponent(expanded).path
    }

    private func openInExternalEditor(file: RemoteDiff.File, line: Int?, target: ExternalAppTarget?) {
        let resolvedTarget = target ?? ExternalEditorService.shared.preferredEditor
        guard let resolvedTarget else {
            appModel.presentToast(
                "No External Editor Found",
                detail: "Install an editor like Xcode, VS Code, Cursor, or Zed to open files externally.",
                style: .warning
            )
            return
        }
        let absPath = resolvedAbsolutePath(for: file.path)
        do {
            try ExternalEditorService.shared.open(path: absPath, line: line, in: resolvedTarget)
        } catch {
            appModel.presentError(error)
        }
    }

    private func revealFileInFinder(_ path: String) {
        let absPath = resolvedAbsolutePath(for: path)
        ExternalEditorService.shared.revealInFinder(path: absPath)
    }

    private func quoteFileInComposer(_ path: String) {
        appModel.insertTextIntoComposer("@\(path) ")
        appModel.presentToast("Quoted in Composer", detail: "@\(path)", style: .info)
    }

    private func formattedUnifiedPatch(for file: RemoteDiff.File) -> String {
        let oldHeader = file.oldPath ?? file.path
        var header = "diff --git a/\(oldHeader) b/\(file.path)\n"
        header += "--- a/\(oldHeader)\n"
        header += "+++ b/\(file.path)\n"
        return header + file.patch
    }

    private func copyPatch(for file: RemoteDiff.File) {
        let text = file.patch.isEmpty ? file.path : formattedUnifiedPatch(for: file)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appModel.presentToast("Copied File Patch", detail: (file.path as NSString).lastPathComponent, style: .success)
    }

    private func copyAllPatchesToPasteboard() {
        let combined = displayedFiles
            .filter { !$0.patch.isEmpty }
            .map(formattedUnifiedPatch(for:))
            .joined(separator: "\n\n")
        guard !combined.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        appModel.presentToast("Copied Full Patch", detail: "\(displayedFiles.count) files", style: .success)
    }
}

private struct DiffLoadKey: Equatable {
    let threadID: String?
    let scope: DiffScope
    let token: UUID
}

// MARK: - File Status Appearance Helper

enum DiffFileStatusStyle {
    static func iconName(for status: String) -> String {
        switch status.lowercased() {
        case "added", "a":
            return "plus.square.fill"
        case "deleted", "d":
            return "minus.square.fill"
        case "renamed", "r":
            return "arrow.right.square.fill"
        case "untracked", "?", "??":
            return "questionmark.square.fill"
        default:
            return "pencil.square.fill"
        }
    }

    static func tint(for status: String) -> Color {
        switch status.lowercased() {
        case "added", "a":
            return AppTheme.success
        case "deleted", "d":
            return AppTheme.danger
        case "renamed", "r":
            return AppTheme.info
        case "untracked", "?", "??":
            return AppTheme.secondaryLabel
        default:
            return AppTheme.warning
        }
    }

    static func label(for status: String) -> String {
        switch status.lowercased() {
        case "added", "a": return "Added"
        case "deleted", "d": return "Deleted"
        case "renamed", "r": return "Renamed"
        case "untracked", "?", "??": return "Untracked"
        default: return "Modified"
        }
    }
}

// MARK: - Changed File Summary Row

private struct DiffFileSummaryRow: View {
    let file: RemoteDiff.File
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenInInspector: () -> Void
    let onOpenInExternalEditor: (ExternalAppTarget?) -> Void
    let onRevealInFinder: () -> Void
    let onQuoteInComposer: () -> Void
    let onCopyPatch: () -> Void

    @State private var isHovered: Bool = false

    private var fileName: String {
        (file.path as NSString).lastPathComponent
    }

    private var directoryPrefix: String? {
        let dir = (file.path as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: DiffFileStatusStyle.iconName(for: file.status))
                .font(.system(size: 12))
                .foregroundStyle(DiffFileStatusStyle.tint(for: file.status))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(fileName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)

                    if let old = file.oldPath, old != file.path {
                        Text("← \((old as NSString).lastPathComponent)")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .lineLimit(1)
                    }
                }

                if let dir = directoryPrefix {
                    Text(dir)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if isHovered {
                HStack(spacing: 3) {
                    if file.status.lowercased() != "deleted" {
                        Button(action: onOpenInInspector) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("Open in Inspector Editor")
                        .accessibilityLabel("Open in Inspector Editor")

                        Button {
                            onOpenInExternalEditor(nil)
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("Open in External Editor")
                        .accessibilityLabel("Open in external editor")
                    }

                    Button(action: onQuoteInComposer) {
                        Image(systemName: "at")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("Quote File in Composer")
                    .accessibilityLabel("Quote file in composer")
                }
                .foregroundStyle(AppTheme.secondaryLabel)
            }

            if file.isBinary {
                Text("BIN")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(AppTheme.elevatedCardFill))
            } else {
                HStack(spacing: 4) {
                    if file.additions > 0 {
                        Text("+\(file.additions)")
                            .foregroundStyle(AppTheme.diffAdditionText)
                    }
                    if file.deletions > 0 {
                        Text("−\(file.deletions)")
                            .foregroundStyle(AppTheme.diffDeletionText)
                    }
                    if file.additions == 0 && file.deletions == 0 {
                        Text("±0")
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect() }
        .contextMenu {
            if file.status.lowercased() != "deleted" {
                Button("Open in Inspector Editor", systemImage: "doc.text.magnifyingglass", action: onOpenInInspector)

                let editors = ExternalEditorService.shared.installedEditors
                if let preferred = ExternalEditorService.shared.preferredEditor {
                    Button("Open in \(preferred.name)", systemImage: "arrow.up.forward.app") {
                        onOpenInExternalEditor(preferred)
                    }
                }
                if editors.count > 1 {
                    Menu("Open With…") {
                        ForEach(editors) { editor in
                            Button(editor.name) {
                                onOpenInExternalEditor(editor)
                            }
                        }
                    }
                }
                Button("Reveal in Finder", systemImage: "folder", action: onRevealInFinder)
                Divider()
            }
            Button("Quote File in Composer", systemImage: "at", action: onQuoteInComposer)
            if !file.patch.isEmpty {
                Button("Copy Patch", systemImage: "doc.on.doc", action: onCopyPatch)
            }
        }
    }
}

// MARK: - Unified Diff Patch Card

private struct DiffFilePatchCard: View {
    let file: RemoteDiff.File
    let fontScale: Double
    let wrapsLines: Bool
    let isFocused: Bool
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onOpenInInspector: (Int?) -> Void
    let onOpenInExternalEditor: (ExternalAppTarget?, Int?) -> Void
    let onRevealInFinder: () -> Void
    let onQuoteInComposer: () -> Void
    let onCopyPatch: () -> Void

    private var parsedLines: [RemoteDiffParsing.Line] {
        guard !file.patch.isEmpty else { return [] }
        return RemoteDiffParsing.lines(of: file.patch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            if !isCollapsed {
                Divider()
                cardPatchBody
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall + 2)
                .fill(AppTheme.codeBlockBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall + 2)
                .strokeBorder(
                    isFocused ? AppTheme.accent.opacity(0.65) : AppTheme.separator,
                    lineWidth: isFocused ? 1.2 : 0.85
                )
        )
    }

    private var cardHeader: some View {
        HStack(spacing: 6) {
            Button(action: onToggleCollapse) {
                HStack(spacing: 5) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .frame(width: 10)

                    Image(systemName: DiffFileStatusStyle.iconName(for: file.status))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DiffFileStatusStyle.tint(for: file.status))

                    if let old = file.oldPath, old != file.path {
                        Text("\(old) → \(file.path)")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(file.path)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            if !file.isBinary {
                HStack(spacing: 4) {
                    if file.additions > 0 {
                        Text("+\(file.additions)")
                            .foregroundStyle(AppTheme.diffAdditionText)
                    }
                    if file.deletions > 0 {
                        Text("−\(file.deletions)")
                            .foregroundStyle(AppTheme.diffDeletionText)
                    }
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }

            HStack(spacing: 4) {
                Button(action: onQuoteInComposer) {
                    Image(systemName: "at")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Quote File in Composer (@\(file.path))")
                .accessibilityLabel("Quote file in composer")

                if !file.patch.isEmpty {
                    Button(action: onCopyPatch) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Patch")
                    .accessibilityLabel("Copy patch")
                }

                if file.status.lowercased() != "deleted" {
                    Button {
                        onOpenInInspector(nil)
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Open in Inspector Editor")
                    .accessibilityLabel("Open in Inspector Editor")

                    Menu {
                        Button("Open in Inspector Editor") {
                            onOpenInInspector(nil)
                        }
                        Divider()
                        let editors = ExternalEditorService.shared.installedEditors
                        if editors.isEmpty {
                            Button("Reveal in Finder", action: onRevealInFinder)
                        } else {
                            ForEach(editors) { editor in
                                Button("Open in \(editor.name)") {
                                    onOpenInExternalEditor(editor, nil)
                                }
                            }
                            Divider()
                            Button("Reveal in Finder", action: onRevealInFinder)
                        }
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Open in External Editor")
                    .accessibilityLabel("Open in external editor")
                }
            }
            .foregroundStyle(AppTheme.secondaryLabel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppTheme.controlBackground.opacity(0.9))
    }

    @ViewBuilder
    private var cardPatchBody: some View {
        if file.isBinary {
            HStack(spacing: 8) {
                Image(systemName: "doc.zipper")
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text("Binary file changed (\(DiffFileStatusStyle.label(for: file.status))).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Spacer()
            }
            .padding(12)
        } else if parsedLines.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "doc.plaintext")
                    .foregroundStyle(AppTheme.tertiaryLabel)
                Text("No inline patch hunks (\(DiffFileStatusStyle.label(for: file.status))).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Spacer()
                if file.status.lowercased() != "deleted" {
                    Button("Open File") {
                        onOpenInInspector(1)
                    }
                    .controlSize(.mini)
                }
            }
            .padding(10)
        } else if wrapsLines {
            linesStack(parsedLines)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                linesStack(parsedLines)
                    .frame(minWidth: 320, alignment: .leading)
            }
        }
    }

    private func linesStack(_ lines: [RemoteDiffParsing.Line]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                UnifiedDiffLineRow(
                    line: line,
                    fontScale: fontScale,
                    wrapsLines: wrapsLines,
                    canJumpToLine: file.status.lowercased() != "deleted" && (line.newLine != nil || line.oldLine != nil),
                    onJumpToLine: {
                        onOpenInInspector(line.newLine ?? line.oldLine)
                    }
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct UnifiedDiffLineRow: View {
    let line: RemoteDiffParsing.Line
    let fontScale: Double
    let wrapsLines: Bool
    let canJumpToLine: Bool
    let onJumpToLine: () -> Void

    @State private var gutterHovered: Bool = false

    private var marker: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "−"
        case .hunk: "@@"
        case .note: "\\"
        case .context: " "
        }
    }

    private var rowBackground: Color {
        switch line.kind {
        case .addition: AppTheme.diffAdditionBackground
        case .deletion: AppTheme.diffDeletionBackground
        case .hunk: AppTheme.diffHunkHeaderBackground
        case .note: AppTheme.elevatedCardFill
        case .context: Color.clear
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .addition: AppTheme.diffAdditionText
        case .deletion: AppTheme.diffDeletionText
        case .hunk: AppTheme.info
        case .note: AppTheme.tertiaryLabel
        case .context: AppTheme.primaryLabel.opacity(0.9)
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .addition: AppTheme.diffAdditionText
        case .deletion: AppTheme.diffDeletionText
        case .hunk: AppTheme.info
        case .note: AppTheme.tertiaryLabel
        case .context: AppTheme.tertiaryLabel
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if line.kind == .hunk {
                Text("⋯")
                    .font(AppTheme.codeFont(scale: fontScale, size: 10.5))
                    .foregroundStyle(AppTheme.info.opacity(0.85))
                    .frame(width: 72, alignment: .center)
                    .padding(.vertical, 2.5)

                Text(line.text)
                    .font(AppTheme.codeFont(scale: fontScale, size: 11.0))
                    .foregroundStyle(AppTheme.info)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
            } else {
                // Dual monospaced old/new line-number gutters
                HStack(spacing: 2) {
                    Text(line.oldLine.map(String.init) ?? "")
                        .frame(width: 32, alignment: .trailing)
                    Text(line.newLine.map(String.init) ?? "")
                        .frame(width: 32, alignment: .trailing)
                }
                .font(AppTheme.codeFont(scale: fontScale, size: 10.5))
                .foregroundStyle(gutterHovered && canJumpToLine ? AppTheme.accent : AppTheme.tertiaryLabel)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .contentShape(Rectangle())
                .onHover { gutterHovered = $0 }
                .onTapGesture {
                    if canJumpToLine {
                        onJumpToLine()
                    }
                }
                .help(canJumpToLine ? "Open at line \(line.newLine ?? line.oldLine ?? 1) in Inspector Editor" : "")
                .accessibilityElement(children: .combine)
                .accessibilityLabel(canJumpToLine ? "Open at line \(line.newLine ?? line.oldLine ?? 1) in Inspector Editor" : "Line \(line.newLine ?? line.oldLine ?? 1)")
                .accessibilityAddTraits(canJumpToLine ? .isButton : [])
                .accessibilityAction {
                    if canJumpToLine {
                        onJumpToLine()
                    }
                }

                Rectangle()
                    .fill(AppTheme.separator.opacity(0.45))
                    .frame(width: 0.75)

                Text(marker)
                    .font(AppTheme.codeFont(scale: fontScale, size: 11.5))
                    .foregroundStyle(markerColor)
                    .frame(width: 16, alignment: .center)
                    .padding(.vertical, 1.5)

                Text(line.text.isEmpty ? " " : line.text)
                    .font(AppTheme.codeFont(scale: fontScale, size: 11.5))
                    .foregroundStyle(textColor)
                    .lineLimit(wrapsLines ? nil : 1)
                    .fixedSize(horizontal: !wrapsLines, vertical: true)
                    .textSelection(.enabled)
                    .padding(.trailing, 10)
                    .padding(.vertical, 1.5)
            }

            Spacer(minLength: 0)
        }
        .background(rowBackground)
    }
}
