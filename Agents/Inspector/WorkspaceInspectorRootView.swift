import AppKit
import CoincideRemoteKit
import SwiftUI

public struct WorkspaceInspectorRootView: View {
    @Bindable public var appModel: AppModel

    @State private var isRefreshing: Bool = false
    @State private var manualRefreshToken: UUID = UUID()

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
            Divider()
            inspectorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.windowBackground)
        .onAppear {
            routePendingFileOpenIfNeeded()
        }
        .onChange(of: appModel.openFileInInspectorRequest) { _, newValue in
            if newValue != nil {
                routePendingFileOpenIfNeeded()
            }
        }
        .task(id: InspectorReloadKey(tab: appModel.inspectorTab, threadID: appModel.selectedThreadID)) {
            await performRefresh(triggerSubViews: false)
        }
    }

    // MARK: - Header

    private var inspectorHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(appModel.inspectorTab.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)

                    if let subtitle = headerSubtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 4)

                Button {
                    Task { await performRefresh(triggerSubViews: true) }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(width: 16, height: 16)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help("Refresh \(appModel.inspectorTab.title)")
                .accessibilityLabel("Refresh \(appModel.inspectorTab.title)")

                Button {
                    appModel.inspectorVisible = false
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Hide Inspector (⌥⌘I)")
                .accessibilityLabel("Hide inspector")
            }

            HStack(spacing: 4) {
                ForEach(InspectorTab.allCases) { tab in
                    InspectorTabPillButton(
                        tab: tab,
                        isSelected: appModel.inspectorTab == tab,
                        badgeText: badgeText(for: tab)
                    ) {
                        appModel.inspectorTab = tab
                    }
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall + 1)
                    .fill(AppTheme.elevatedCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall + 1)
                    .strokeBorder(AppTheme.separator.opacity(0.65), lineWidth: 0.75)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.controlBackground)
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch appModel.inspectorTab {
        case .changes:
            DiffInspectorView(appModel: appModel, refreshToken: manualRefreshToken)
        case .git:
            GitInspectorView(appModel: appModel, refreshToken: manualRefreshToken)
        case .pullRequests:
            PullRequestsInspectorView(appModel: appModel, refreshToken: manualRefreshToken)
        case .files:
            WorkspaceFilesInspectorView(appModel: appModel, refreshToken: manualRefreshToken)
        case .schedules:
            SchedulesInspectorView(appModel: appModel, refreshToken: manualRefreshToken)
        }
    }

    // MARK: - Helpers

    private var headerSubtitle: String? {
        if let project = appModel.selectedProject, !project.isChats {
            if let branch = appModel.activeGitState?.branch ?? appModel.activeCheckout?.branch ?? appModel.selectedThread?.branch,
               !branch.isEmpty
            {
                return "\(project.name) · \(branch)"
            }
            return project.name
        }
        if let cwd = appModel.activeWorkingDirectory, !cwd.isEmpty {
            return (cwd as NSString).abbreviatingWithTildeInPath
        }
        return nil
    }

    private func badgeText(for tab: InspectorTab) -> String? {
        switch tab {
        case .changes:
            if let count = appModel.activeDiff?.files.count, count > 0 {
                return "\(count)"
            }
            if let gitCount = appModel.activeGitState?.changedFiles, gitCount > 0 {
                return "\(gitCount)"
            }
            return nil
        case .git:
            guard let git = appModel.activeGitState, git.isRepository else { return nil }
            let syncTotal = git.ahead + git.behind
            return syncTotal > 0 ? "\(syncTotal)" : nil
        case .pullRequests:
            if appModel.activeGitState?.pullRequest != nil {
                return "1"
            }
            return nil
        case .files:
            return nil
        case .schedules:
            let pendingCount = appModel.scheduledTasks.tasks.filter { $0.needsApproval == true }.count
            if pendingCount > 0 {
                return "\(pendingCount)"
            }
            let activeCount = appModel.scheduledTasks.tasks.filter { !$0.isPaused }.count
            return activeCount > 0 ? "\(activeCount)" : nil
        }
    }

    private func routePendingFileOpenIfNeeded() {
        guard appModel.openFileInInspectorRequest != nil else { return }
        if appModel.inspectorTab != .files {
            appModel.inspectorTab = .files
        }
        if !appModel.inspectorVisible {
            appModel.inspectorVisible = true
        }
    }

    private func performRefresh(triggerSubViews: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }
        await appModel.refreshActiveInspectorData()
        if appModel.inspectorTab == .git, let client = appModel.runtime, let tid = appModel.selectedThreadUUID {
            if let checkout = try? await client.fetchCheckout(thread: tid), appModel.selectedThreadUUID == tid {
                appModel.activeCheckout = checkout
            }
        }
        if triggerSubViews {
            manualRefreshToken = UUID()
        }
    }
}

private struct InspectorReloadKey: Equatable {
    let tab: InspectorTab
    let threadID: String?
}

private struct InspectorTabPillButton: View {
    let tab: InspectorTab
    let isSelected: Bool
    let badgeText: String?
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? AppTheme.accent.opacity(0.22) : AppTheme.separator.opacity(0.45))
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .foregroundStyle(isSelected ? AppTheme.primaryLabel : AppTheme.secondaryLabel)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall - 1)
                    .fill(
                        isSelected
                            ? AppTheme.controlBackground
                            : (isHovered ? AppTheme.subtleHoverFill : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall - 1)
                    .strokeBorder(isSelected ? AppTheme.separator : Color.clear, lineWidth: 0.75)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tab.title)
        .accessibilityLabel(badgeText.map { "\(tab.title), \($0)" } ?? tab.title)
    }
}
