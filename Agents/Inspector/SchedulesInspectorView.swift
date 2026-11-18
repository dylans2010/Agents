import AppKit
import CoincideRemoteKit
import SwiftUI

struct SchedulesInspectorView: View {
    @Bindable var appModel: AppModel
    var refreshToken: UUID

    enum ScopeFilter: String, CaseIterable, Identifiable {
        case currentThread
        case allSchedules

        var id: String { rawValue }

        var title: String {
            switch self {
            case .currentThread: "Current Thread"
            case .allSchedules: "All Schedules"
            }
        }
    }

    @State private var scopeFilter: ScopeFilter = .allSchedules
    @State private var showEditorSheet: Bool = false
    @State private var editingTask: RemoteScheduledTask?
    @State private var pendingDeleteTask: RemoteScheduledTask?
    @State private var busyTaskIDs: Set<UUID> = []
    @State private var isRefreshing: Bool = false

    private var filteredTasks: [RemoteScheduledTask] {
        let all = appModel.scheduledTasks.tasks
        switch scopeFilter {
        case .allSchedules:
            return all
        case .currentThread:
            guard let tid = appModel.selectedThreadUUID else { return [] }
            return all.filter { task in
                if let taskThread = task.threadID {
                    return taskThread == tid
                }
                return task.lastThreadID == tid
            }
        }
    }

    private var groupedSchedules: [(owner: RemoteScheduleOwner, tasks: [RemoteScheduledTask])] {
        RemoteScheduleOwner.groups(filteredTasks)
    }

    var body: some View {
        VStack(spacing: 0) {
            schedulesToolbar
            Divider()

            if let errorText = appModel.scheduledTasks.error, !errorText.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.warning)
                    Text(errorText)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.warning.opacity(0.10))
                Divider()
            }

            if filteredTasks.isEmpty {
                emptySchedulesState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(groupedSchedules.enumerated()), id: \.offset) { _, group in
                            VStack(alignment: .leading, spacing: 6) {
                                ownerSectionHeader(group.owner)

                                ForEach(group.tasks) { task in
                                    ScheduledTaskCard(
                                        task: task,
                                        targetSummary: targetDescription(for: task),
                                        isBusy: busyTaskIDs.contains(task.id),
                                        onApprove: {
                                            Task { await approve(task) }
                                        },
                                        onRunNow: {
                                            Task { await runCommand(.runNow, for: task) }
                                        },
                                        onTogglePause: {
                                            Task {
                                                await runCommand(task.isPaused ? .resume : .pause, for: task)
                                            }
                                        },
                                        onEdit: {
                                            editingTask = task
                                            showEditorSheet = true
                                        },
                                        onDelete: {
                                            pendingDeleteTask = task
                                        },
                                        onOpenThread: { threadUUID in
                                            appModel.selectThread(threadUUID)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(AppTheme.windowBackground)
        .task(id: refreshToken) {
            isRefreshing = true
            defer { isRefreshing = false }
            await appModel.refreshScheduledTasks()
        }
        .sheet(isPresented: $showEditorSheet) {
            ScheduleEditorSheet(
                appModel: appModel,
                existingTask: editingTask,
                preferCurrentThread: scopeFilter == .currentThread
            )
        }
        .alert(
            "Delete Schedule?",
            isPresented: Binding(
                get: { pendingDeleteTask != nil },
                set: { if !$0 { pendingDeleteTask = nil } }
            ),
            presenting: pendingDeleteTask
        ) { task in
            Button("Delete", role: .destructive) {
                pendingDeleteTask = nil
                Task { await runCommand(.delete, for: task) }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteTask = nil
            }
        } message: { task in
            let title = task.name.isEmpty ? "Untitled Schedule" : task.name
            Text("Are you sure you want to permanently delete “\(title)”? Existing conversation transcripts will be preserved.")
        }
    }

    // MARK: - Top Bar

    private var schedulesToolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Picker("Scope", selection: $scopeFilter) {
                    ForEach(ScopeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Schedule scope filter")
                .controlSize(.small)

                Button {
                    editingTask = nil
                    showEditorSheet = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appModel.workspace.projects.isEmpty)
                .help("Create a New Scheduled Task")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.controlBackground)
    }

    // MARK: - Empty State

    private var emptySchedulesState: some View {
        ContentUnavailableView {
            Label(
                scopeFilter == .currentThread ? "No Schedules for This Thread" : "No Scheduled Tasks",
                systemImage: "calendar.badge.clock"
            )
        } description: {
            Text(
                scopeFilter == .currentThread
                    ? "Automate recurring or one-time agent prompts directly inside this conversation, or switch to All Schedules."
                    : "Create a scheduled prompt to run once, daily, or weekly in any project or thread."
            )
        } actions: {
            HStack(spacing: 8) {
                if scopeFilter == .currentThread && !appModel.scheduledTasks.tasks.isEmpty {
                    Button("Show All Schedules") {
                        scopeFilter = .allSchedules
                    }
                }
                Button {
                    editingTask = nil
                    showEditorSheet = true
                } label: {
                    Label("New Schedule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.workspace.projects.isEmpty)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Group Owner Header

    @ViewBuilder
    private func ownerSectionHeader(_ owner: RemoteScheduleOwner) -> some View {
        HStack(spacing: 6) {
            switch owner {
            case .bot(let botID):
                let bot = appModel.workspace.bots?.first(where: { $0.id == botID })
                BotAvatarView(avatar: bot?.avatar, size: 15)
                Text(bot?.name ?? "Bot")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)

            case .thread(let threadID):
                let thread = appModel.workspace.threads.first(where: { $0.id == threadID })
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(thread?.title.isEmpty == false ? (thread?.title ?? "Thread") : "Thread Schedule")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(1)

            case .project(let projectID):
                let project = appModel.workspace.projects.first(where: { $0.id == projectID })
                Image(systemName: project?.isChats == true ? "tray" : "folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(project?.name ?? "Project")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func targetDescription(for task: RemoteScheduledTask) -> String {
        let projectName = appModel.workspace.projects.first(where: { $0.id == task.projectID })?.name ?? "Workspace"
        if let tid = task.threadID {
            let threadTitle = appModel.workspace.threads.first(where: { $0.id == tid })?.title
            let cleanTitle = (threadTitle?.isEmpty == false) ? threadTitle! : "Thread"
            return "\(projectName) · \(cleanTitle)"
        }
        return "\(projectName) · New thread each run"
    }

    // MARK: - Actions

    private func approve(_ task: RemoteScheduledTask) async {
        busyTaskIDs.insert(task.id)
        defer { busyTaskIDs.remove(task.id) }
        await appModel.approveSchedule(task.id.uuidString)
    }

    private func runCommand(_ action: RemoteScheduledTaskCommand.Action, for task: RemoteScheduledTask) async {
        busyTaskIDs.insert(task.id)
        defer { busyTaskIDs.remove(task.id) }
        await appModel.performScheduledTaskAction(
            RemoteScheduledTaskCommand(taskID: task.id, action: action)
        )
        if action == .runNow {
            appModel.presentToast(
                "Triggered Schedule",
                detail: task.name.isEmpty ? "Scheduled Task" : task.name,
                style: .info
            )
        }
    }
}

// MARK: - Schedule Card

private struct ScheduledTaskCard: View {
    let task: RemoteScheduledTask
    let targetSummary: String
    let isBusy: Bool
    let onApprove: () -> Void
    let onRunNow: () -> Void
    let onTogglePause: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onOpenThread: (UUID) -> Void

    private var awaitingApproval: Bool {
        task.needsApproval == true
    }

    private var stateTint: Color {
        if awaitingApproval { return AppTheme.warning }
        if task.isPaused { return AppTheme.secondaryLabel }
        return switch task.state {
        case .scheduled: AppTheme.success
        case .running: AppTheme.info
        case .paused: AppTheme.secondaryLabel
        case .failed, .interrupted: AppTheme.danger
        case .missed: AppTheme.warning
        case .completed: AppTheme.secondaryLabel
        case .unknown: AppTheme.secondaryLabel
        }
    }

    private var stateLabel: String {
        if awaitingApproval { return "Awaiting Approval" }
        if !task.stateText.isEmpty { return task.stateText }
        if task.isPaused { return "Paused" }
        return task.state.rawValue.capitalized
    }

    private var formattedRecurrenceSummary: String {
        if !task.scheduleText.isEmpty {
            return task.scheduleText
        }
        let rec = task.recurrence
        let timeString = String(format: "%d:%02d", rec.hour, rec.minute)
        switch rec.kind {
        case .once:
            return "Once on \(rec.date.formatted(date: .abbreviated, time: .omitted)) at \(timeString)"
        case .daily:
            return "Daily at \(timeString)"
        case .weekly:
            let symbols = Calendar.current.weekdaySymbols
            let idx = max(0, min(symbols.count - 1, rec.weekday - 1))
            return "Weekly on \(symbols[idx]) at \(timeString)"
        case .unknown:
            return "Custom Schedule"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Approval Banner when created by an agent and awaiting user approval
            if awaitingApproval {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.warning)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Approval Required")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryLabel)
                        Text("Created by an agent. Approve to allow scheduled execution.")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }

                    Spacer(minLength: 4)

                    Button("Approve", action: onApprove)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.warning)
                        .controlSize(.mini)
                        .disabled(isBusy)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .fill(AppTheme.warning.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .strokeBorder(AppTheme.warning.opacity(0.45), lineWidth: 0.75)
                )
            }

            // Title + State Pill
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(task.name.isEmpty ? "Untitled Schedule" : task.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .lineLimit(1)

                if task.createdByAgent == true {
                    Text("Agent")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.info)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(AppTheme.info.opacity(0.12)))
                }

                Spacer(minLength: 4)

                Text(stateLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(stateTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(stateTint.opacity(0.12)))
            }

            // Prompt Preview
            if !task.prompt.isEmpty {
                Text(task.prompt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(2)
            }

            // Recurrence, Next Run & Target Metadata
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "repeat")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .frame(width: 12)
                    Text(formattedRecurrenceSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }

                if let nextRun = task.nextRunAt, !task.isPaused {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 12)
                        Text("Next: \(nextRun.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.primaryLabel)
                    }
                }

                HStack(spacing: 5) {
                    Image(systemName: task.isThreadSchedule ? "arrow.turn.down.right" : "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .frame(width: 12)
                    Text(targetSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .lineLimit(1)
                }

                if let lastMessage = task.lastMessage, !lastMessage.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: task.state == .failed ? "exclamationmark.circle" : "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(task.state == .failed ? AppTheme.danger : AppTheme.tertiaryLabel)
                            .frame(width: 12)
                        Text(lastMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(task.state == .failed ? AppTheme.danger : AppTheme.tertiaryLabel)
                            .lineLimit(2)
                    }
                }
            }

            Divider()

            // Action Bar
            HStack(spacing: 6) {
                Button(action: onRunNow) {
                    Label("Run Now", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isBusy || !task.canRunNow || awaitingApproval)

                Button(action: onTogglePause) {
                    Label(
                        task.isPaused ? "Resume" : "Pause",
                        systemImage: task.isPaused ? "play" : "pause"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isBusy)

                Button("Edit…", action: onEdit)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isBusy)

                if let threadUUID = task.lastThreadID ?? task.threadID {
                    Button {
                        onOpenThread(threadUUID)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Open Target / Last Run Conversation")
                    .accessibilityLabel("Open target or last run conversation")
                }

                Spacer(minLength: 0)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.danger)
                }
                .buttonStyle(.borderless)
                .disabled(isBusy)
                .help("Delete Schedule")
                .accessibilityLabel("Delete schedule \(task.name.isEmpty ? "Untitled Schedule" : task.name)")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(AppTheme.elevatedCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(
                    awaitingApproval ? AppTheme.warning.opacity(0.6) : AppTheme.separator.opacity(0.8),
                    lineWidth: 0.85
                )
        )
    }
}
