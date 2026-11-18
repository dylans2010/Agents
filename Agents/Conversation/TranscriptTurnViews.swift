import AppKit
import CoincideRemoteKit
import Foundation
import SwiftUI

// MARK: - Coalesced Transcript Render Blocks

nonisolated enum TranscriptRenderBlock: Identifiable, Equatable, Sendable {
    case user(RemoteItem)
    case workGroup(id: UUID, items: [RemoteItem])
    case assistant(item: RemoteItem, turnOpeningItemID: UUID?, changedFiles: [RemoteChangedFile])
    case plan(RemoteItem)
    case error(RemoteItem)
    case notice(RemoteItem)
    case approval(RemoteItem)
    case question(RemoteItem)

    var id: String {
        switch self {
        case .user(let item): "user-\(item.id.uuidString)"
        case .workGroup(let id, _): "work-\(id.uuidString)"
        case .assistant(let item, _, _): "assistant-\(item.id.uuidString)"
        case .plan(let item): "plan-\(item.id.uuidString)"
        case .error(let item): "error-\(item.id.uuidString)"
        case .notice(let item): "notice-\(item.id.uuidString)"
        case .approval(let item): "approval-\(item.id.uuidString)"
        case .question(let item): "question-\(item.id.uuidString)"
        }
    }

    func containsItem(id targetID: UUID) -> Bool {
        switch self {
        case .user(let item),
             .assistant(let item, _, _),
             .plan(let item),
             .error(let item),
             .notice(let item),
             .approval(let item),
             .question(let item):
            return item.id == targetID
        case .workGroup(_, let items):
            return items.contains { $0.id == targetID }
        }
    }

    static func build(from transcript: RemoteTranscript) -> [TranscriptRenderBlock] {
        var blocks: [TranscriptRenderBlock] = []
        var workBuffer: [RemoteItem] = []
        var currentTurnUserID: UUID? = nil

        // Precompute the last assistant item ID for each user turn so `turnChanges` attaches cleanly once per turn.
        var lastAssistantForTurn: [UUID: UUID] = [:]
        var scanTurnUserID: UUID? = nil
        for item in transcript.items {
            if item.kind == .user && !item.steered {
                scanTurnUserID = item.id
            } else if item.kind == .assistant, let uid = scanTurnUserID {
                lastAssistantForTurn[uid] = item.id
            }
        }

        func flushWorkBuffer() {
            guard let first = workBuffer.first else { return }
            blocks.append(.workGroup(id: first.id, items: workBuffer))
            workBuffer.removeAll(keepingCapacity: true)
        }

        for item in transcript.items {
            switch item.kind {
            case .reasoning, .tool:
                workBuffer.append(item)

            case .user:
                flushWorkBuffer()
                if !item.steered {
                    currentTurnUserID = item.id
                }
                blocks.append(.user(item))

            case .assistant:
                flushWorkBuffer()
                var turnFiles: [RemoteChangedFile] = []
                var associatedTurnID: UUID? = nil
                if let uid = currentTurnUserID, lastAssistantForTurn[uid] == item.id {
                    associatedTurnID = uid
                    turnFiles = transcript.turnChanges[uid.uuidString]
                        ?? transcript.turnChanges[uid.uuidString.lowercased()]
                        ?? []
                }
                blocks.append(.assistant(item: item, turnOpeningItemID: associatedTurnID, changedFiles: turnFiles))

            case .plan:
                flushWorkBuffer()
                blocks.append(.plan(item))

            case .error:
                flushWorkBuffer()
                blocks.append(.error(item))

            case .notice:
                flushWorkBuffer()
                blocks.append(.notice(item))

            case .approval:
                flushWorkBuffer()
                blocks.append(.approval(item))

            case .question:
                flushWorkBuffer()
                blocks.append(.question(item))

            case .unknown:
                break
            }
        }

        flushWorkBuffer()
        return blocks
    }
}

// MARK: - Block Dispatcher

struct TranscriptBlockRowView: View {
    let block: TranscriptRenderBlock
    let threadID: UUID
    let appModel: AppModel
    @Binding var expandedWorkGroups: Set<UUID>
    var highlightQuery: String = ""
    var isActiveFindMatch: Bool = false

    var body: some View {
        Group {
            switch block {
            case .user(let item):
                UserTurnRow(
                    item: item,
                    threadID: threadID,
                    appModel: appModel,
                    highlightQuery: highlightQuery
                )

            case .workGroup(let groupID, let items):
                WorkGroupRow(
                    groupID: groupID,
                    items: items,
                    appModel: appModel,
                    isExpanded: Binding(
                        get: { expandedWorkGroups.contains(groupID) || items.contains(where: \.isWaiting) },
                        set: { newValue in
                            if newValue {
                                expandedWorkGroups.insert(groupID)
                            } else {
                                expandedWorkGroups.remove(groupID)
                            }
                        }
                    ),
                    highlightQuery: highlightQuery
                )

            case .assistant(let item, let turnID, let changedFiles):
                AssistantTurnRow(
                    item: item,
                    threadID: threadID,
                    turnOpeningItemID: turnID,
                    changedFiles: changedFiles,
                    appModel: appModel,
                    highlightQuery: highlightQuery
                )

            case .plan(let item):
                PlanTurnCard(item: item, appModel: appModel, highlightQuery: highlightQuery)

            case .error(let item):
                ErrorTurnCard(item: item)

            case .notice(let item):
                NoticeTurnRow(item: item)

            case .approval(let item):
                InlineApprovalHistoryCard(item: item, appModel: appModel)

            case .question(let item):
                InlineQuestionHistoryCard(item: item)
            }
        }
        .padding(isActiveFindMatch ? 6 : 0)
        .background(
            isActiveFindMatch ? Color.yellow.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
        )
        .overlay {
            if isActiveFindMatch {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .strokeBorder(Color.yellow.opacity(0.65), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - User Message Row

struct UserTurnRow: View {
    let item: RemoteItem
    let threadID: UUID
    let appModel: AppModel
    var highlightQuery: String = ""

    @State private var isHovering = false
    @State private var showRewindSheet = false
    @State private var copied = false

    private var legacyAttachmentNames: [String] {
        guard item.media == nil || item.media?.isEmpty == true else { return [] }
        return item.attachments ?? []
    }

    private var contextChips: [String] {
        item.context ?? []
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 64)

            VStack(alignment: .trailing, spacing: 5) {
                VStack(alignment: .leading, spacing: 8) {
                    // Scheduled task badge or Steered badge
                    if item.scheduleName != nil || item.steered {
                        HStack(spacing: 8) {
                            if let scheduleName = item.scheduleName, !scheduleName.isEmpty {
                                Label("Scheduled · \(scheduleName)", systemImage: "clock.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.info)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(AppTheme.info.opacity(0.12), in: Capsule())
                            }
                            if item.steered {
                                Label("Steered into running turn", systemImage: "arrow.turn.down.right")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(AppTheme.subtleHoverFill, in: Capsule())
                            }
                        }
                    }

                    // Attached image thumbnails
                    if item.media?.isEmpty == false {
                        InlineMediaStripView(
                            item: item,
                            threadID: threadID,
                            appModel: appModel,
                            alignment: .trailing
                        )
                    }

                    // Message body
                    if !item.text.isEmpty {
                        Text(highlightedUserText)
                            .font(AppTheme.bodyFont(scale: appModel.fontScale))
                            .lineSpacing(2.5)
                            .foregroundStyle(AppTheme.primaryLabel)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Legacy attachment & context chips
                    if !legacyAttachmentNames.isEmpty || !contextChips.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(legacyAttachmentNames, id: \.self) { name in
                                Label(name, systemImage: "photo")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .lineLimit(1)
                            }
                            ForEach(Array(contextChips.enumerated()), id: \.offset) { _, snippet in
                                Label(snippet, systemImage: "text.quote")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                        .strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 1)
                )
                .contextMenu {
                    userContextMenuItems
                }

                // Subtle hover action strip
                HStack(spacing: 10) {
                    Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.tertiaryLabel)

                    if isHovering {
                        if !item.text.isEmpty {
                            Button {
                                copyText()
                            } label: {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(copied ? AppTheme.success : AppTheme.secondaryLabel)
                            }
                            .buttonStyle(.plain)
                            .help("Copy message")

                            Button {
                                quoteInComposer()
                            } label: {
                                Image(systemName: "text.quote")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            .buttonStyle(.plain)
                            .help("Quote in composer")
                        }

                        if !item.steered {
                            Button {
                                showRewindSheet = true
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            .buttonStyle(.plain)
                            .help("Edit / Rewind Conversation…")
                        }
                    }
                }
                .frame(height: 14)
                .padding(.trailing, 4)
            }
        }
        .onHover { isHovering = $0 }
        .sheet(isPresented: $showRewindSheet) {
            RewindConversationSheet(threadID: threadID, item: item, appModel: appModel)
        }
    }

    @ViewBuilder
    private var userContextMenuItems: some View {
        if !item.text.isEmpty {
            Button {
                copyText()
            } label: {
                Label("Copy Message", systemImage: "doc.on.doc")
            }

            Button {
                quoteInComposer()
            } label: {
                Label("Quote in Composer", systemImage: "text.quote")
            }
        }

        Divider()

        Button {
            Task { _ = await appModel.forkThread(threadID, itemID: item.id) }
        } label: {
            Label("Fork from Here", systemImage: "arrow.triangle.branch")
        }

        if !item.steered {
            Button {
                showRewindSheet = true
            } label: {
                Label("Edit / Rewind Conversation…", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var highlightedUserText: AttributedString {
        var attr = AttributedString(item.text)
        let q = highlightQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            NativeMarkdownView.applySearchHighlight(query: q, to: &attr)
        }
        return attr
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            copied = false
        }
    }

    private func quoteInComposer() {
        let quoted = item.text
            .components(separatedBy: "\n")
            .map { "> \($0)" }
            .joined(separator: "\n") + "\n\n"
        appModel.insertTextIntoComposer(quoted)
    }
}

// MARK: - Collapsible Work Group Row (Reasoning + Tool Steps)

struct WorkGroupRow: View {
    let groupID: UUID
    let items: [RemoteItem]
    let appModel: AppModel
    @Binding var isExpanded: Bool
    var highlightQuery: String = ""

    private var isRunning: Bool {
        items.contains { $0.status == "running" || $0.status == "waiting" }
    }

    private var hasFailed: Bool {
        items.contains { $0.status == "failed" }
    }

    private var toolItems: [RemoteItem] {
        items.filter { $0.kind == .tool }
    }

    private var reasoningCount: Int {
        items.filter { $0.kind == .reasoning }.count
    }

    private var headerTitle: String {
        if isRunning {
            if let runningTool = items.last(where: { $0.kind == .tool && $0.status == "running" }),
               let title = runningTool.title, !title.isEmpty
            {
                return "Thinking & running tools · \(title)"
            }
            return "Thinking & running tools…"
        }

        let totalSteps = items.count
        if toolItems.isEmpty && reasoningCount > 0 {
            return reasoningCount == 1 ? "Reasoned" : "Completed \(reasoningCount) reasoning steps"
        }
        if totalSteps == 1, let single = toolItems.first, let title = single.title, !title.isEmpty {
            return "Completed 1 step · \(title)"
        }
        if let lastTitle = toolItems.last?.title, !lastTitle.isEmpty {
            return "Completed \(totalSteps) steps · \(lastTitle)"
        }
        return "Completed \(totalSteps) \(totalSteps == 1 ? "step" : "steps")"
    }

    private var elapsedText: String? {
        guard !isRunning,
              let firstStart = items.map(\.createdAt).min(),
              let lastEnd = items.compactMap(\.completedAt).max()
        else { return nil }
        let seconds = lastEnd.timeIntervalSince(firstStart)
        guard seconds >= 0.4 else { return nil }
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 15, height: 15)
                    } else if hasFailed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.danger)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.secondaryLabel.opacity(0.85))
                    }

                    Text(headerTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(isRunning ? AppTheme.primaryLabel : AppTheme.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let elapsedText {
                        Text(elapsedText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    isExpanded ? AppTheme.elevatedCardFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(items) { step in
                        ToolOrReasoningStepRow(
                            item: step,
                            appModel: appModel,
                            highlightQuery: highlightQuery
                        )
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(AppTheme.separator.opacity(0.75))
                        .frame(width: 1.5)
                        .padding(.leading, 6)
                        .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Individual Reasoning or Tool Step Row

struct ToolOrReasoningStepRow: View {
    let item: RemoteItem
    let appModel: AppModel
    var highlightQuery: String = ""

    @State private var isDetailOpen: Bool = false
    @State private var copiedOutput: Bool = false

    private var symbolName: String {
        if item.kind == .reasoning { return "brain" }
        switch item.category {
        case "command": return "terminal"
        case "fileChange": return "pencil.line"
        case "read": return "doc.text"
        case "search": return "magnifyingglass"
        case "web": return "globe"
        case "mcp": return "puzzlepiece.extension"
        case "task": return "person.2"
        case "todo": return "checklist"
        default: return "wrench.and.screwdriver"
        }
    }

    private var stepTitle: String {
        if item.kind == .reasoning {
            let firstLine = item.text
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if let firstLine {
                let stripped = firstLine.replacingOccurrences(of: "**", with: "")
                return stripped.count > 88 ? String(stripped.prefix(88)) + "…" : stripped
            }
            return "Thinking"
        }
        if let title = item.title, !title.isEmpty {
            return title
        }
        if let detail = item.detail, !detail.isEmpty {
            return detail.components(separatedBy: "\n").first ?? "Tool Call"
        }
        return item.category?.capitalized ?? "Tool Call"
    }

    private var statusBadge: (label: String, tint: Color)? {
        guard let status = item.status, !status.isEmpty else { return nil }
        switch status {
        case "running":
            return ("running", AppTheme.info)
        case "completed":
            return ("completed", AppTheme.success)
        case "failed":
            return ("failed", AppTheme.danger)
        case "declined":
            return ("declined", AppTheme.warning)
        case "waiting":
            return ("waiting", AppTheme.warning)
        default:
            return (status, AppTheme.secondaryLabel)
        }
    }

    /// Extracts workspace file path references from read / edit / search tool calls so the user can click to open in Inspector.
    private var detectedWorkspaceFiles: [(display: String, path: String, line: Int?)] {
        guard item.kind == .tool else { return [] }
        let workspaceRoot = appModel.activeWorkingDirectory
        var candidates: [String] = []
        if let title = item.title {
            candidates.append(contentsOf: Self.extractCandidatePaths(from: title))
        }
        if let detail = item.detail {
            candidates.append(contentsOf: Self.extractCandidatePaths(from: detail))
        }

        var seen = Set<String>()
        var results: [(display: String, path: String, line: Int?)] = []
        for raw in candidates {
            let split = WorkspacePathLinkResolver.splitTrailingLineAndColumn(from: raw)
            let candidate = split.path
            guard !candidate.isEmpty, !seen.contains(candidate) else { continue }

            if let resolved = Self.verifyWorkspacePath(candidate, workspaceRoot: workspaceRoot) {
                seen.insert(candidate)
                let shortName = (resolved as NSString).lastPathComponent
                let label = split.line.map { "\(shortName):\($0)" } ?? shortName
                results.append((display: label, path: resolved, line: split.line))
                if results.count >= 4 { break }
            }
        }
        return results
    }

    private var hasExpandableBody: Bool {
        if item.kind == .reasoning {
            return !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !(item.detail ?? "").isEmpty || !item.text.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    guard hasExpandableBody else { return }
                    withAnimation(.snappy(duration: 0.18)) {
                        isDetailOpen.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: symbolName)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(statusBadge?.tint ?? AppTheme.secondaryLabel)
                            .frame(width: 16)

                        Text(stepTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let badge = statusBadge {
                            HStack(spacing: 4) {
                                if item.status == "running" {
                                    ProgressView().controlSize(.mini)
                                }
                                Text(badge.label)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .foregroundStyle(badge.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(badge.tint.opacity(0.12), in: Capsule())
                        }

                        if hasExpandableBody {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                                .rotationEffect(.degrees(isDetailOpen ? 90 : 0))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Clickable workspace file pills
                ForEach(Array(detectedWorkspaceFiles.enumerated()), id: \.offset) { _, target in
                    Button {
                        appModel.openFileInInspector(path: target.path, line: target.line)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 9.5))
                            Text(target.display)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                        }
                        .foregroundStyle(AppTheme.info)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.info.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Open \(target.path) in Workspace Inspector")
                }

                Spacer(minLength: 0)
            }

            if isDetailOpen && hasExpandableBody {
                if item.kind == .reasoning {
                    NativeMarkdownView(
                        text: item.text,
                        fontScale: max(0.85, appModel.fontScale * 0.94),
                        usesSerif: false,
                        highlightQuery: highlightQuery,
                        workspaceRoot: appModel.activeWorkingDirectory,
                        onOpenWorkspaceFile: { path, line, col in
                            appModel.openFileInInspector(path: path, line: line, column: col)
                        }
                    )
                    .opacity(0.88)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if let detail = item.detail, !detail.isEmpty {
                            ToolPayloadBox(
                                label: item.category == "command" ? "COMMAND" : "INPUT",
                                text: detail,
                                isPatch: false,
                                fontScale: appModel.fontScale
                            )
                        }

                        if !item.text.isEmpty {
                            let looksLikePatch = item.category == "fileChange"
                                || item.text.contains("\n@@ ")
                                || item.text.hasPrefix("@@ ")
                            ToolPayloadBox(
                                label: looksLikePatch ? "PATCH" : "OUTPUT",
                                text: item.text,
                                isPatch: looksLikePatch,
                                fontScale: appModel.fontScale
                            )
                        }

                        if item.isClipped {
                            Text("Output truncated for display performance.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private static func extractCandidatePaths(from raw: String) -> [String] {
        let tokens = raw
            .components(separatedBy: CharacterSet(charactersIn: " \t\n\"'`(),[]{}<>"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;")) }
            .filter { token in
                guard token.count >= 3, !token.hasPrefix("http://"), !token.hasPrefix("https://") else { return false }
                return token.contains("/") || token.contains(".")
            }
        return Array(tokens.prefix(10))
    }

    private static func verifyWorkspacePath(_ raw: String, workspaceRoot: String?) -> String? {
        let expanded = ExternalEditorService.expandedPath(raw)
        var isDir: ObjCBool = false
        if expanded.hasPrefix("/") {
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue else {
                return nil
            }
            if let root = workspaceRoot {
                let cleanRoot = ExternalEditorService.expandedPath(root)
                let prefix = cleanRoot.hasSuffix("/") ? cleanRoot : cleanRoot + "/"
                if expanded.hasPrefix(prefix) {
                    return String(expanded.dropFirst(prefix.count))
                }
            }
            return expanded
        }

        guard let root = workspaceRoot else { return nil }
        let cleanRoot = ExternalEditorService.expandedPath(root)
        let candidate = (cleanRoot as NSString).appendingPathComponent(raw)
        if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue {
            return raw
        }
        return nil
    }
}

private struct ToolPayloadBox: View {
    let label: String
    let text: String
    let isPatch: Bool
    let fontScale: Double

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(copied ? AppTheme.success : AppTheme.secondaryLabel)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.03))

            Divider()

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                if isPatch {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(AppTheme.codeFont(scale: fontScale, size: 11.5))
                                .foregroundStyle(patchForeground(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 1)
                                .background(patchBackground(for: line))
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                } else {
                    Text(text)
                        .font(AppTheme.codeFont(scale: fontScale, size: 11.5))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .fixedSize(horizontal: true, vertical: false)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 280)
        }
        .background(AppTheme.codeBlockBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 1)
        )
    }

    private func patchForeground(for line: String) -> Color {
        if line.hasPrefix("@@") { return AppTheme.info }
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return AppTheme.diffAdditionText }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return AppTheme.diffDeletionText }
        return AppTheme.primaryLabel
    }

    private func patchBackground(for line: String) -> Color {
        if line.hasPrefix("@@") { return AppTheme.diffHunkHeaderBackground }
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return AppTheme.diffAdditionBackground }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return AppTheme.diffDeletionBackground }
        return .clear
    }
}

// MARK: - Assistant Reply Row

struct AssistantTurnRow: View {
    let item: RemoteItem
    let threadID: UUID
    let turnOpeningItemID: UUID?
    let changedFiles: [RemoteChangedFile]
    let appModel: AppModel
    var highlightQuery: String = ""

    @State private var isHovering = false
    @State private var copiedMarkdown = false
    @State private var isForking = false

    private var resolvedModelLabel: String? {
        guard let modelID = item.modelID, !modelID.isEmpty else { return nil }
        if let desktopMatch = appModel.providers
            .first(where: { AgentBranding.normalizedID($0.id) == AgentBranding.normalizedID(item.provider) })?
            .models.first(where: { $0.id == modelID })
        {
            return desktopMatch.name
        }
        if let remoteMatch = appModel.workspace.providers
            .first(where: { AgentBranding.normalizedID($0.id) == AgentBranding.normalizedID(item.provider) })?
            .models.first(where: { $0.id == modelID })
        {
            return remoteMatch.name
        }
        return modelID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Left 3pt vertical accent rail colored by AgentBranding
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AgentBranding.color(for: item.provider).opacity(0.82))
                    .frame(width: 3)
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    // Agent header badge
                    HStack(spacing: 6) {
                        AgentLogoView(provider: item.provider, size: 15)
                        Text(AgentBranding.displayName(for: item.provider))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AgentBranding.color(for: item.provider))

                        if let model = resolvedModelLabel {
                            Text(model)
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }

                        if item.status == "running" {
                            ProgressView()
                                .controlSize(.mini)
                                .padding(.leading, 2)
                        }
                    }

                    // Rich Markdown body
                    if !item.text.isEmpty {
                        NativeMarkdownView(
                            text: item.text,
                            fontScale: appModel.fontScale,
                            usesSerif: appModel.usesSerifReplies,
                            highlightQuery: highlightQuery,
                            workspaceRoot: appModel.activeWorkingDirectory,
                            onOpenWorkspaceFile: { path, line, col in
                                appModel.openFileInInspector(path: path, line: line, column: col)
                            }
                        )
                    }

                    // Inline media strip
                    if item.media?.isEmpty == false {
                        InlineMediaStripView(
                            item: item,
                            threadID: threadID,
                            appModel: appModel,
                            alignment: .leading
                        )
                    }

                    // Turn changed files summary card
                    if !changedFiles.isEmpty {
                        TurnChangesCardView(
                            turnOpeningItemID: turnOpeningItemID,
                            files: changedFiles,
                            appModel: appModel
                        )
                    }

                    // Footer / Hover Action Bar
                    HStack(spacing: 12) {
                        Text((item.completedAt ?? item.createdAt).formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiaryLabel)

                        HStack(spacing: 10) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.text, forType: .string)
                                copiedMarkdown = true
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    copiedMarkdown = false
                                }
                            } label: {
                                Label(copiedMarkdown ? "Copied" : "Copy", systemImage: copiedMarkdown ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(copiedMarkdown ? AppTheme.success : AppTheme.secondaryLabel)
                            }
                            .buttonStyle(.plain)
                            .help("Copy Markdown reply")

                            Button {
                                let snippet = item.text
                                    .components(separatedBy: "\n")
                                    .prefix(14)
                                    .map { "> \($0)" }
                                    .joined(separator: "\n") + "\n\n"
                                appModel.insertTextIntoComposer(snippet)
                            } label: {
                                Label("Quote", systemImage: "text.quote")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            .buttonStyle(.plain)
                            .help("Quote reply in composer")

                            Button {
                                isForking = true
                                Task {
                                    _ = await appModel.forkThread(threadID, itemID: item.id)
                                    isForking = false
                                }
                            } label: {
                                Label("Fork from Here", systemImage: "arrow.triangle.branch")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            .buttonStyle(.plain)
                            .disabled(isForking)
                            .help("Create a forked thread up to this response")
                        }
                        .opacity(isHovering || copiedMarkdown ? 1.0 : 0.45)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Turn Changes Summary Card

struct TurnChangesCardView: View {
    let turnOpeningItemID: UUID?
    let files: [RemoteChangedFile]
    let appModel: AppModel

    private var totalAdditions: Int { files.reduce(0) { $0 + $1.additions } }
    private var totalDeletions: Int { files.reduce(0) { $0 + $1.deletions } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plusminus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.accent)

                Text("\(files.count) \(files.count == 1 ? "file" : "files") modified")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)

                HStack(spacing: 5) {
                    Text("+\(totalAdditions)")
                        .foregroundStyle(AppTheme.diffAdditionText)
                    Text("−\(totalDeletions)")
                        .foregroundStyle(AppTheme.diffDeletionText)
                }
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))

                Spacer()

                Button {
                    Task {
                        if let turnID = turnOpeningItemID {
                            await appModel.refreshDiff(scope: .turn(turnID))
                        } else {
                            await appModel.refreshDiff(scope: .uncommitted)
                        }
                        appModel.openInspector(tab: .changes)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Inspect Diff")
                        Image(systemName: "sidebar.right")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(files.prefix(6)) { file in
                    Button {
                        appModel.openFileInInspector(path: file.path)
                    } label: {
                        HStack(spacing: 8) {
                            Text(statusBadgeLetter(for: file.status))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(statusColor(for: file.status))
                                .frame(width: 14)

                            Text(file.path)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(AppTheme.primaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            HStack(spacing: 4) {
                                Text("+\(file.additions)")
                                    .foregroundStyle(AppTheme.diffAdditionText)
                                Text("−\(file.deletions)")
                                    .foregroundStyle(AppTheme.diffDeletionText)
                            }
                            .font(.system(size: 10.5, design: .monospaced))
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open \(file.path) in Workspace Inspector")
                }

                if files.count > 6 {
                    Text("+ \(files.count - 6) more files")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .padding(.top, 2)
                }
            }
        }
        .padding(11)
        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 1)
        )
    }

    private func statusBadgeLetter(for status: String) -> String {
        switch status {
        case "added": "A"
        case "deleted": "D"
        case "renamed": "R"
        case "untracked": "U"
        default: "M"
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "added", "untracked": AppTheme.diffAdditionText
        case "deleted": AppTheme.diffDeletionText
        case "renamed": AppTheme.info
        default: AppTheme.warning
        }
    }
}

// MARK: - Plan, Error, Notice & Inline History Cards

struct PlanTurnCard: View {
    let item: RemoteItem
    let appModel: AppModel
    var highlightQuery: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .foregroundStyle(AppTheme.accent)
                Text(item.title ?? "Execution Plan")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Spacer()
            }

            NativeMarkdownView(
                text: item.text,
                fontScale: appModel.fontScale,
                usesSerif: false,
                highlightQuery: highlightQuery,
                workspaceRoot: appModel.activeWorkingDirectory,
                onOpenWorkspaceFile: { path, line, col in
                    appModel.openFileInInspector(path: path, line: line, column: col)
                }
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.accent.opacity(0.32), lineWidth: 1)
        )
    }
}

struct ErrorTurnCard: View {
    let item: RemoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.danger)
                Text(item.title ?? "Agent Error")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.danger)
                Spacer()
            }
            if !item.text.isEmpty {
                Text(item.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.danger.opacity(0.35), lineWidth: 1)
        )
    }
}

struct NoticeTurnRow: View {
    let item: RemoteItem

    var body: some View {
        let message = item.text.isEmpty ? (item.title ?? "") : item.text
        if !message.isEmpty {
            HStack {
                Spacer()
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(AppTheme.elevatedCardFill, in: Capsule())
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }
}

struct InlineApprovalHistoryCard: View {
    let item: RemoteItem
    let appModel: AppModel

    var body: some View {
        let tint: Color = item.isWaiting ? AppTheme.warning : AppTheme.secondaryLabel
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isWaiting ? "hand.raised.fill" : "checkmark.shield")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title ?? "Permission Request")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)

                    if item.isWaiting {
                        Text("Action required below")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(AppTheme.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(AppTheme.warning.opacity(0.14), in: Capsule())
                    } else if let resolution = item.approval?.resolution, !resolution.isEmpty {
                        Text(resolution)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }

                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(11)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
    }
}

struct InlineQuestionHistoryCard: View {
    let item: RemoteItem

    var body: some View {
        let tint: Color = item.isWaiting ? AppTheme.warning : AppTheme.secondaryLabel
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
                Text(item.questions?.title ?? "Clarification Question")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Spacer()
                if item.isWaiting {
                    Text("Waiting below")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppTheme.warning)
                } else if item.status == "declined" {
                    Text("Dismissed")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
            }

            ForEach(item.questions?.questions ?? []) { q in
                VStack(alignment: .leading, spacing: 2) {
                    Text(q.prompt)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    if let ans = item.answers?[q.id], !ans.isEmpty {
                        Text(ans.joined(separator: ", "))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
        }
        .padding(11)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - Active Background Tasks Strip

struct ActiveBackgroundTasksStrip: View {
    let tasks: [RemoteBackgroundTask]

    var body: some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("BACKGROUND TASKS (\(tasks.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }

                ForEach(tasks) { task in
                    HStack(spacing: 8) {
                        Image(systemName: task.kind == .agent ? "person.2.fill" : "terminal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AgentBranding.color(for: task.provider))
                        Text(task.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .lineLimit(1)
                        if let progress = task.progress, !progress.isEmpty {
                            Text("· \(progress)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }
            .padding(10)
            .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 1)
            )
        }
    }
}
