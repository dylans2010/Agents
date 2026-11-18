import AppKit
import CoincideRemoteKit
import SwiftUI

public struct SidebarThreadRow: View {
    @Bindable public var appModel: AppModel
    public let thread: RemoteThreadSummary
    public var projectPath: String?
    public var showsProjectBadge: Bool = false
    public var projectName: String?

    @State private var isHovering: Bool = false
    @State private var isRenaming: Bool = false
    @State private var renameDraft: String = ""
    @FocusState private var isRenameFieldFocused: Bool

    public init(
        appModel: AppModel,
        thread: RemoteThreadSummary,
        projectPath: String? = nil,
        showsProjectBadge: Bool = false,
        projectName: String? = nil
    ) {
        self.appModel = appModel
        self.thread = thread
        self.projectPath = projectPath
        self.showsProjectBadge = showsProjectBadge
        self.projectName = projectName
    }

    private var displayTitle: String {
        let trimmed = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Thread" : trimmed
    }

    private var attentionCount: Int {
        thread.pendingApprovals + thread.pendingQuestions
    }

    private var isActivelyWorking: Bool {
        thread.isRunning || thread.isStarting || (thread.hasBackgroundWork == true)
    }

    private var isSnoozedActive: Bool {
        guard let until = thread.snoozedUntil else { return false }
        return until > Date()
    }

    private var resolvedFolderPath: String {
        if let projectPath, !projectPath.isEmpty {
            return ExternalEditorService.expandedPath(projectPath)
        }
        if let proj = appModel.workspace.projects.first(where: { $0.id == thread.projectID && !$0.isChats }),
           !proj.path.isEmpty
        {
            return ExternalEditorService.expandedPath(proj.path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    public var body: some View {
        HStack(spacing: 8) {
            AgentLogoView(provider: thread.selection.provider, size: 15)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(displayTitle)
                        .font(.system(size: 13, weight: thread.unseen != nil ? .semibold : .regular))
                        .foregroundStyle(thread.isArchived ? AppTheme.secondaryLabel : AppTheme.primaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if thread.hasDraft {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .help("Unsent draft")
                    }
                }

                if hasMetadataRow {
                    metadataSubtitleRow
                }
            }

            Spacer(minLength: 4)

            trailingIndicators
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityLabel("\(displayTitle), \(Self.compactRelativeAge(from: thread.updatedAt)) ago")
        .onHover { hovering in
            isHovering = hovering
        }
        .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
            renamePopoverContent
        }
        .contextMenu {
            contextMenuContent
        }
    }

    // MARK: - Subtitle Metadata

    private var hasMetadataRow: Bool {
        let hasBranch = !(thread.branch ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasProjectLabel = showsProjectBadge && !(projectName ?? "").isEmpty
        return hasBranch || thread.hasWorktree || hasProjectLabel || isSnoozedActive || (thread.scheduleCount ?? 0) > 0
    }

    @ViewBuilder
    private var metadataSubtitleRow: some View {
        HStack(spacing: 5) {
            if showsProjectBadge, let projectName, !projectName.isEmpty {
                Text(projectName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(1)
            }

            if let branch = thread.branch?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: thread.hasWorktree ? "square.split.2x1" : "arrow.triangle.branch")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(branch)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(AppTheme.secondaryLabel)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1)
                .background(AppTheme.elevatedCardFill, in: Capsule())
            } else if thread.hasWorktree {
                HStack(spacing: 3) {
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text("worktree")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(AppTheme.secondaryLabel)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1)
                .background(AppTheme.elevatedCardFill, in: Capsule())
            }

            if let scheduleCount = thread.scheduleCount, scheduleCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 8.5, weight: .semibold))
                    if scheduleCount > 1 {
                        Text("\(scheduleCount)")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                }
                .foregroundStyle(AppTheme.tertiaryLabel)
                .help("\(scheduleCount) active schedule\(scheduleCount == 1 ? "" : "s")")
            }

            if isSnoozedActive, let until = thread.snoozedUntil {
                HStack(spacing: 3) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 8.5))
                    Text(Self.shortSnoozeLabel(until: until))
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .foregroundStyle(AppTheme.tertiaryLabel)
            }
        }
    }

    // MARK: - Trailing Status Indicators

    @ViewBuilder
    private var trailingIndicators: some View {
        HStack(spacing: 6) {
            if isSnoozedActive && isHovering {
                Button {
                    Task { await appModel.performThreadAction(.snooze(nil), on: thread.id) }
                } label: {
                    Image(systemName: "sun.max")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .help("Unsnooze Thread")
                .accessibilityLabel("Unsnooze thread")
            }

            if attentionCount > 0 {
                Text("\(attentionCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1.5)
                    .background(AppTheme.warning, in: Capsule())
                    .help(attentionTooltip)
            }

            if isActivelyWorking {
                ProgressView()
                    .controlSize(.mini)
                    .help(thread.isStarting ? "Starting agent…" : "Agent is running")
            }

            if thread.unseen != nil {
                Circle()
                    .fill(AppTheme.info)
                    .frame(width: 7, height: 7)
                    .help(thread.unseen == "failed" ? "Unread failed turn" : "Unread reply")
            }

            Text(Self.compactRelativeAge(from: thread.updatedAt))
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(AppTheme.tertiaryLabel)
                .monospacedDigit()
        }
    }

    private var attentionTooltip: String {
        if thread.pendingApprovals > 0 && thread.pendingQuestions > 0 {
            return "\(thread.pendingApprovals) approval(s) and \(thread.pendingQuestions) question(s) waiting"
        } else if thread.pendingApprovals > 0 {
            return "\(thread.pendingApprovals) approval\(thread.pendingApprovals == 1 ? "" : "s") waiting"
        } else {
            return "\(thread.pendingQuestions) question\(thread.pendingQuestions == 1 ? "" : "s") waiting"
        }
    }

    // MARK: - Inline Rename Popover

    private var renamePopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename Thread")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)

            TextField("Thread Title", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                .focused($isRenameFieldFocused)
                .onSubmit {
                    commitRename()
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    isRenaming = false
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.small)

                Button("Save") {
                    commitRename()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .onAppear {
            renameDraft = thread.title
            isRenameFieldFocused = true
        }
    }

    private func beginRename() {
        renameDraft = thread.title
        isRenaming = true
    }

    private func commitRename() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenaming = false
        guard !trimmed.isEmpty, trimmed != thread.title else { return }
        Task {
            await appModel.performThreadAction(.rename(trimmed), on: thread.id)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            beginRename()
        } label: {
            Label("Rename…", systemImage: "pencil")
        }

        Button {
            Task { await appModel.performThreadAction(.pin(!thread.isPinned), on: thread.id) }
        } label: {
            Label(thread.isPinned ? "Unpin" : "Pin", systemImage: thread.isPinned ? "pin.slash" : "pin")
        }

        Menu {
            ForEach(SnoozePreset.allCases) { preset in
                Button(preset.title) {
                    let targetDate = preset.resolveDate()
                    Task { await appModel.performThreadAction(.snooze(targetDate), on: thread.id) }
                }
            }
            if thread.snoozedUntil != nil {
                Divider()
                Button("Unsnooze") {
                    Task { await appModel.performThreadAction(.snooze(nil), on: thread.id) }
                }
            }
        } label: {
            Label("Snooze", systemImage: "moon.zzz")
        }

        Button {
            Task { _ = await appModel.forkThread(thread.id) }
        } label: {
            Label("Fork Thread", systemImage: "arrow.triangle.branch")
        }

        if thread.unseen != nil {
            Button {
                Task {
                    try? await appModel.runtime?.markSeen(thread.id)
                    await appModel.refreshWorkspace()
                }
            } label: {
                Label("Mark as Read", systemImage: "envelope.open")
            }
        } else {
            Button {
                Task { await appModel.performThreadAction(.markUnread, on: thread.id) }
            } label: {
                Label("Mark as Unread", systemImage: "circle.fill")
            }
        }

        let targetProjects = appModel.workspace.projects.filter { !$0.isChats && $0.id != thread.projectID }
        if !targetProjects.isEmpty {
            Menu {
                ForEach(targetProjects) { proj in
                    Button(proj.name) {
                        Task { await appModel.performThreadAction(.move(projectID: proj.id), on: thread.id) }
                    }
                }
            } label: {
                Label("Move to Project", systemImage: "folder")
            }
        }

        Divider()

        let folder = resolvedFolderPath
        if let preferredEditor = appModel.externalEditors.preferredEditor {
            Button {
                do {
                    try appModel.externalEditors.open(path: folder, in: preferredEditor)
                } catch {
                    appModel.presentError(error)
                }
            } label: {
                Label {
                    Text("Open Folder in \(preferredEditor.name)")
                } icon: {
                    Image(nsImage: preferredEditor.icon)
                }
            }
        }

        Button {
            appModel.externalEditors.revealInFinder(path: folder)
        } label: {
            Label("Open Folder in Finder", systemImage: "folder")
        }

        Divider()

        Button {
            Task { await appModel.performThreadAction(.archive(!thread.isArchived), on: thread.id) }
        } label: {
            Label(
                thread.isArchived ? "Restore" : "Archive",
                systemImage: thread.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }

        Button(role: .destructive) {
            Task { await appModel.deleteThreadPermanently(thread.id.uuidString) }
        } label: {
            Label("Delete Permanently", systemImage: "trash")
        }
    }

    // MARK: - Formatting & Snooze Presets

    public nonisolated static func compactRelativeAge(from date: Date, relativeTo now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 45 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }
        let months = max(1, days / 30)
        if months < 12 { return "\(months)mo" }
        let years = max(1, days / 365)
        return "\(years)y"
    }

    private nonisolated static func shortSnoozeLabel(until date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInTomorrow(date) {
            return "Tomorrow \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

public nonisolated enum SnoozePreset: String, CaseIterable, Identifiable, Sendable {
    case oneHour
    case threeHours
    case tonight
    case tomorrowMorning
    case nextWeek

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneHour: "In 1 Hour"
        case .threeHours: "In 3 Hours"
        case .tonight: "Tonight"
        case .tomorrowMorning: "Tomorrow Morning"
        case .nextWeek: "Next Week"
        }
    }

    public func resolveDate(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .oneHour:
            return now.addingTimeInterval(3_600)
        case .threeHours:
            return now.addingTimeInterval(3 * 3_600)
        case .tonight:
            if let todayEvening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now),
               todayEvening.timeIntervalSince(now) > 1_800
            {
                return todayEvening
            }
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        case .nextWeek:
            if let nextMonday = calendar.nextDate(
                after: now,
                matching: DateComponents(hour: 9, minute: 0, second: 0, weekday: 2),
                matchingPolicy: .nextTime
            ) {
                return nextMonday
            }
            return now.addingTimeInterval(7 * 86_400)
        }
    }
}
