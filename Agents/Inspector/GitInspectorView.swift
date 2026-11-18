import AppKit
import CoincideRemoteKit
import SwiftUI

struct GitInspectorView: View {
    @Bindable var appModel: AppModel
    var refreshToken: UUID

    // Commit Composer State
    @State private var commitMessage: String = ""
    @State private var featureBranch: Bool = false
    @State private var runningAction: RemoteGitActionRequest.Action?
    @State private var lastActionResult: RemoteGitActionResult?
    @State private var pendingConfirmedAction: RemoteGitActionRequest.Action?

    // Branch Creation State
    @State private var showNewBranchSheet: Bool = false
    @State private var newBranchName: String = ""
    @State private var isChangingCheckout: Bool = false

    // Detailed Porcelain Counts & Checkpoints State
    @State private var statusBreakdown: GitPorcelainBreakdown?
    @State private var canonicalRepoRoot: String?
    @State private var currentHeadOID: String?
    @State private var manualCheckpoints: [ManualGitCheckpoint] = []
    @State private var turnCheckpoints: [TurnGitCheckpoint] = []
    @State private var checkpointStatusMessage: String?
    @State private var newCheckpointLabel: String = ""
    @State private var isCreatingCheckpoint: Bool = false
    @State private var isLoadingCheckpoints: Bool = false
    @State private var inspectedCheckpointDiff: InspectedCheckpointPatch?
    @State private var inspectedHistoryCommit: InspectedCheckpointPatch?
    @State private var isLoadingHistoryDetail: Bool = false

    @State private var historyCommits: [GitHistoryCommit] = []
    @State private var isLoadingHistory: Bool = false
    @State private var historyErrorMessage: String?
    @State private var historyHasMore: Bool = false

    @State private var worktreesList: [GitWorktreeEntry] = []

    @State private var pendingRestoreTurn: TurnGitCheckpoint?
    @State private var pendingManualRestore: ManualGitCheckpoint?

    var body: some View {
        Group {
            if appModel.selectedThreadUUID == nil {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Select a conversation to view Git branch status, commits, and checkpoints.")
                )
            } else if let gitState = appModel.activeGitState, !gitState.isRepository {
                nonRepositoryView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let progress = appModel.activeGitState?.progress, !progress.isEmpty {
                            gitProgressBanner(progress)
                        }

                        branchAndCheckoutCard
                        changedFilesSummaryCard
                        commitComposerCard
                        historyCard
                        worktreesCard
                        checkpointsSectionCard
                    }
                    .padding(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.windowBackground)
        .task(id: GitInspectorReloadKey(threadID: appModel.selectedThreadID, token: refreshToken)) {
            await reloadAllGitInspectorState()
        }
        .sheet(isPresented: $showNewBranchSheet) {
            newBranchPopoverSheet
        }
        .sheet(item: $inspectedCheckpointDiff) { patch in
            CheckpointDiffPreviewSheet(patch: patch, fontScale: appModel.fontScale)
        }
        .sheet(item: $inspectedHistoryCommit) { patch in
            CheckpointDiffPreviewSheet(patch: patch, fontScale: appModel.fontScale)
        }
        .confirmationDialog(
            "Restore Files to This Checkpoint?",
            isPresented: Binding(
                get: { pendingRestoreTurn != nil },
                set: { if !$0 { pendingRestoreTurn = nil } }
            ),
            presenting: pendingRestoreTurn
        ) { turn in
            Button("Rewind & Restore Files", role: .destructive) {
                pendingRestoreTurn = nil
                Task {
                    if let uuid = UUID(uuidString: turn.userItemID) {
                        _ = await appModel.rewindConversation(to: uuid, revertsFiles: true)
                        await loadCheckpointsAndPorcelain()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingRestoreTurn = nil
            }
        } message: { turn in
            Text("This rewinds the conversation to before “\(turnTitle(for: turn.userItemID))” and restores workspace files to that checkpoint. Messages after it are removed.")
        }
        .confirmationDialog(
            "Restore Files to This Checkpoint?",
            isPresented: Binding(
                get: { pendingManualRestore != nil },
                set: { if !$0 { pendingManualRestore = nil } }
            ),
            presenting: pendingManualRestore
        ) { cp in
            Button("Rewind & Restore Files", role: .destructive) {
                pendingManualRestore = nil
                Task { await restoreManualCheckpoint(cp) }
            }
            Button("Cancel", role: .cancel) {
                pendingManualRestore = nil
            }
        } message: { cp in
            Text("This resets the working tree to checkpoint \(String(cp.id.prefix(8))) and removes untracked and ignored files. Uncommitted changes are discarded.")
        }
        .confirmationDialog(
            "Push Directly to Default Branch?",
            isPresented: Binding(
                get: { pendingConfirmedAction != nil },
                set: { if !$0 { pendingConfirmedAction = nil } }
            ),
            presenting: pendingConfirmedAction
        ) { action in
            Button("Continue on \(appModel.activeGitState?.branch ?? "Default Branch")", role: .destructive) {
                pendingConfirmedAction = nil
                Task { await executeGitAction(action) }
            }
            Button("Create Feature Branch Instead") {
                pendingConfirmedAction = nil
                featureBranch = true
                Task { await executeGitAction(action) }
            }
            Button("Cancel", role: .cancel) {
                pendingConfirmedAction = nil
            }
        } message: { _ in
            let branch = appModel.activeGitState?.branch ?? "the default branch"
            Text("You are currently on ‘\(branch)’. Enable “Create feature branch” to commit onto a new branch, or confirm pushing directly.")
        }
    }

    // MARK: - Non-Git Empty State

    private var nonRepositoryView: some View {
        ContentUnavailableView {
            Label("Not a Git Repository", systemImage: "folder.badge.questionmark")
        } description: {
            let pathText = appModel.activeWorkingDirectory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "This folder"
            Text("\(pathText) is not initialized as a Git repository.")
        } actions: {
            HStack(spacing: 8) {
                Button("Refresh") {
                    Task { await reloadAllGitInspectorState() }
                }
                Button("Browse Files") {
                    appModel.inspectorTab = .files
                }
            }
            .controlSize(.small)
        }
    }

    private func gitProgressBanner(_ progress: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(progress)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.primaryLabel)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(AppTheme.info.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.info.opacity(0.35), lineWidth: 0.85)
        )
    }

    // MARK: - 1. Current Branch & Checkout Card

    private var branchAndCheckoutCard: some View {
        let gitState = appModel.activeGitState
        let checkout = appModel.activeCheckout
        let currentBranch = gitState?.branch ?? checkout?.branch ?? appModel.selectedThread?.branch

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(currentBranch ?? "Detached HEAD")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .lineLimit(1)

                        if gitState?.isDefaultBranch == true {
                            badgePill("default", tint: AppTheme.secondaryLabel)
                        }

                        workspaceModeBadge(checkout: checkout)
                    }

                    if let upstream = gitState?.upstream, !upstream.isEmpty {
                        Text("Tracking \(upstream)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .lineLimit(1)
                    } else if let head = currentHeadOID {
                        Text("HEAD \(String(head.prefix(8)))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                }

                Spacer(minLength: 4)

                // Ahead / Behind Badges
                if let gitState {
                    HStack(spacing: 4) {
                        if gitState.ahead > 0 {
                            badgePill("↑\(gitState.ahead)", tint: AppTheme.success)
                        }
                        if gitState.behind > 0 {
                            badgePill("↓\(gitState.behind)", tint: AppTheme.warning)
                        }
                        if gitState.ahead == 0 && gitState.behind == 0 && gitState.hasRemote {
                            badgePill("Synced", tint: AppTheme.secondaryLabel)
                        }
                    }
                }
            }

            // Active Branch PR Banner if open
            if let pr = gitState?.pullRequest {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.pull")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.success)
                    Text("#\(pr.number)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.primaryLabel)
                    Text(pr.title)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Inspect") {
                        appModel.inspectorTab = .pullRequests
                    }
                    .controlSize(.mini)
                    if let url = URL(string: pr.url) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("Open on GitHub")
                        .accessibilityLabel("Open pull request on GitHub")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .fill(AppTheme.controlBackground)
                )
            }

            Divider()

            // Quick Branch Switcher / New Branch / Worktree Controls
            HStack(spacing: 6) {
                Menu {
                    if let checkout, !checkout.branches.isEmpty {
                        let localBranches = checkout.branches.filter { !$0.isRemote }
                        let remoteBranches = checkout.branches.filter { $0.isRemote }

                        if !localBranches.isEmpty {
                            Section("Local Branches") {
                                ForEach(localBranches) { branch in
                                    Button {
                                        Task { await performCheckoutChange(.pickBranch(branch.name)) }
                                    } label: {
                                        HStack {
                                            Text(branch.isCheckedOutElsewhere ? "\(branch.name) (in worktree)" : branch.name)
                                            if branch.isCurrent || branch.name == currentBranch {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                    .disabled(!checkout.canPickBranch || checkout.isBusy || branch.isCheckedOutElsewhere)
                                }
                            }
                        }

                        if !remoteBranches.isEmpty {
                            Section("Remote Branches") {
                                ForEach(remoteBranches) { branch in
                                    Button {
                                        Task { await performCheckoutChange(.pickBranch(branch.name)) }
                                    } label: {
                                        Text(branch.name)
                                    }
                                    .disabled(!checkout.canPickBranch || checkout.isBusy)
                                }
                            }
                        }
                    } else {
                        Text("No switchable branches available")
                    }
                } label: {
                    Label(
                        checkout?.workspace == .newWorktree
                            ? "Base: \(checkout?.baseBranch ?? currentBranch ?? "main")"
                            : "Switch Branch",
                        systemImage: "arrow.left.arrow.right"
                    )
                    .font(.system(size: 11.5))
                }
                .controlSize(.small)
                .disabled(isChangingCheckout || checkout?.isBusy == true || (checkout?.canPickBranch == false))

                Button {
                    newBranchName = ""
                    showNewBranchSheet = true
                } label: {
                    Label("New Branch…", systemImage: "plus")
                        .font(.system(size: 11.5))
                }
                .controlSize(.small)
                .disabled(isChangingCheckout || checkout?.isBusy == true || (checkout != nil && checkout?.canCreateBranch == false))
                .help(
                    checkout?.canCreateBranch == false
                        ? "New branches can be created when working in the local repository checkout."
                        : "Create and switch to a new Git branch"
                )

                Spacer(minLength: 0)

                if isChangingCheckout {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Worktree Isolation Switcher (available before first message or when supported)
            if let checkout, checkout.canChangeWorkspace {
                HStack(spacing: 6) {
                    if checkout.workspace != .newWorktree && checkout.workspace != .worktree {
                        Button {
                            Task { await performCheckoutChange(.useNewWorktree) }
                        } label: {
                            Label("Switch to Isolated Worktree", systemImage: "square.split.2x1")
                                .font(.system(size: 11))
                        }
                        .controlSize(.small)
                        .disabled(isChangingCheckout || checkout.isBusy)
                    } else {
                        Button {
                            Task { await performCheckoutChange(.useLocal) }
                        } label: {
                            Label("Use Local Project Folder", systemImage: "folder")
                                .font(.system(size: 11))
                        }
                        .controlSize(.small)
                        .disabled(isChangingCheckout || checkout.isBusy)
                    }

                    if checkout.hasPreviousWorktree {
                        Button {
                            Task { await performCheckoutChange(.usePreviousWorktree) }
                        } label: {
                            let prev = checkout.previousWorktreeBranch ?? "Previous"
                            Label("Resume Worktree (\(prev))", systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 11))
                        }
                        .controlSize(.small)
                        .disabled(isChangingCheckout || checkout.isBusy)
                    }
                }
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    @ViewBuilder
    private func workspaceModeBadge(checkout: RemoteCheckout?) -> some View {
        let mode = checkout?.workspace
        if mode == .worktree || appModel.selectedThread?.hasWorktree == true {
            badgePill("Worktree", tint: AppTheme.info)
        } else if mode == .newWorktree {
            badgePill("New Worktree", tint: AppTheme.accent)
        } else {
            badgePill("Local", tint: AppTheme.secondaryLabel)
        }
    }

    // MARK: - 2. Changed Files Summary Card

    private var changedFilesSummaryCard: some View {
        let totalChanged = appModel.activeGitState?.changedFiles ?? appModel.activeDiff?.files.count ?? 0
        let staged = statusBreakdown?.staged ?? 0
        let unstaged = statusBreakdown?.unstaged ?? 0
        let untracked = statusBreakdown?.untracked ?? 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Working Tree Status", systemImage: "doc.badge.gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Spacer()
                Button {
                    appModel.inspectorTab = .changes
                } label: {
                    HStack(spacing: 3) {
                        Text("View Diff")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.accent)
            }

            HStack(spacing: 6) {
                gitStatTile(title: "Total", count: totalChanged, tint: totalChanged > 0 ? AppTheme.primaryLabel : AppTheme.tertiaryLabel)
                gitStatTile(title: "Staged", count: staged, tint: staged > 0 ? AppTheme.success : AppTheme.tertiaryLabel)
                gitStatTile(title: "Unstaged", count: unstaged, tint: unstaged > 0 ? AppTheme.warning : AppTheme.tertiaryLabel)
                gitStatTile(title: "Untracked", count: untracked, tint: untracked > 0 ? AppTheme.info : AppTheme.tertiaryLabel)
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private func gitStatTile(title: String, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.secondaryLabel)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(AppTheme.controlBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .strokeBorder(AppTheme.separator.opacity(0.6), lineWidth: 0.75)
        )
    }

    // MARK: - 3. Commit Composer & Remote Actions Card

    private var commitComposerCard: some View {
        let gitState = appModel.activeGitState
        let prTerm = gitState?.changeRequestName ?? "Pull Request"
        let isBusy = runningAction != nil || gitState?.progress != nil

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Commit & Sync", systemImage: "checkmark.seal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Spacer()
                if runningAction != nil {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $commitMessage)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 66, maxHeight: 110)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .fill(AppTheme.textBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .strokeBorder(AppTheme.separator, lineWidth: 0.85)
                    )

                if commitMessage.isEmpty {
                    Text("Commit message (leave empty to let Agents draft one)…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }

            Toggle(isOn: $featureBranch) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Create feature branch")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppTheme.primaryLabel)
                    Text("Commits onto a new branch named for this change")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
            }
            .toggleStyle(.checkbox)

            // Primary Commit Buttons
            HStack(spacing: 6) {
                Button {
                    triggerGitAction(.commit)
                } label: {
                    Text("Commit")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isBusy || gitState?.canCommit != true)

                Button {
                    triggerGitAction(.commitPush)
                } label: {
                    Text("Commit & Push")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || gitState?.canCommit != true || gitState?.hasRemote != true)
            }

            Button {
                triggerGitAction(.commitPushPR)
            } label: {
                Label("Commit, Push & \(prTerm)", systemImage: "arrow.triangle.pull")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBusy || gitState?.canCommit != true || gitState?.hasRemote != true)

            Divider()

            // Standalone Sync & PR Buttons
            HStack(spacing: 6) {
                Button {
                    triggerGitAction(.pull)
                } label: {
                    Label("Pull", systemImage: "arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || gitState?.canPull != true)

                Button {
                    triggerGitAction(.push)
                } label: {
                    Label("Push", systemImage: "arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || gitState?.canPush != true)

                Button {
                    triggerGitAction(.createPR)
                } label: {
                    Label("Create PR", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || gitState?.canCreatePullRequest != true)
                .help("Create \(prTerm)")
            }

            if let outcome = lastActionResult {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.success)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(outcome.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.primaryLabel)
                        if let detail = outcome.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if let urlString = outcome.url, let url = URL(string: urlString) {
                        Button("Open") {
                            NSWorkspace.shared.open(url)
                        }
                        .controlSize(.mini)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .fill(AppTheme.success.opacity(0.08))
                )
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Spacer()
                if isLoadingHistory {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await loadHistory(reset: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh History")
                    .accessibilityLabel("Refresh history")
                }
            }

            if let error = historyErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.warning)
            }

            if historyCommits.isEmpty && !isLoadingHistory {
                Text("No commits on this branch yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(historyCommits) { commit in
                        Button {
                            Task { await previewHistoryCommit(commit) }
                        } label: {
                            HStack(spacing: 6) {
                                Text(String(commit.sha.prefix(8)))
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppTheme.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(commit.subject)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(AppTheme.primaryLabel)
                                        .lineLimit(1)
                                    Text("\(commit.authorName) · \(commit.authorDate.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppTheme.secondaryLabel)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if isLoadingHistoryDetail {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(AppTheme.tertiaryLabel)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .fill(AppTheme.controlBackground)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if historyHasMore {
                    Button("Load More Commits") {
                        Task { await loadHistory(reset: false) }
                    }
                    .controlSize(.small)
                    .disabled(isLoadingHistory)
                }
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    private var worktreesCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Worktrees", systemImage: "square.split.2x1")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Spacer()
                Text("\(worktreesList.count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            if worktreesList.isEmpty {
                Text("No worktrees recorded for this repository.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(worktreesList) { worktree in
                        HStack(spacing: 6) {
                            Image(systemName: worktree.isMain ? "house.fill" : "square.split.2x1")
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((worktree.path as NSString).abbreviatingWithTildeInPath)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                    .lineLimit(1)
                                Text("\(worktree.branch ?? "Detached HEAD")\(worktree.head.map { " · \($0.prefix(8))" } ?? "")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if worktree.path == canonicalRepoRoot {
                                badgePill("Current", tint: AppTheme.success)
                            } else if worktree.isMain {
                                badgePill("Main", tint: AppTheme.secondaryLabel)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                .fill(AppTheme.controlBackground)
                        )
                    }
                }
                Text("Start a new isolated worktree, or return to the local folder, from the branch card above. Switching to another existing worktree is not available yet.")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryLabel)
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    // MARK: - 4. Turn & Manual Git Checkpoints Card

    private var checkpointsSectionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Git Checkpoints", systemImage: "clock.badge.checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Spacer()
                if isLoadingCheckpoints {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await loadCheckpointsAndPorcelain() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Checkpoints")
                    .accessibilityLabel("Refresh checkpoints")
                }
            }

            // Create Manual Staged Checkpoint
            HStack(spacing: 6) {
                TextField("Manual checkpoint label (staged index)…", text: $newCheckpointLabel)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.system(size: 11.5))
                    .onSubmit {
                        Task { await createManualCheckpoint() }
                    }

                Button {
                    Task { await createManualCheckpoint() }
                } label: {
                    if isCreatingCheckpoint {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 48)
                    } else {
                        Text("Create")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    isCreatingCheckpoint
                        || newCheckpointLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || canonicalRepoRoot == nil
                        || currentHeadOID == nil
                )
            }

            if let msg = checkpointStatusMessage, !msg.isEmpty {
                Text(msg)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.tertiaryLabel)
            }

            // Manual Checkpoints List
            if !manualCheckpoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MANUAL STAGED CHECKPOINTS (\(manualCheckpoints.count))")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppTheme.tertiaryLabel)

                    ForEach(manualCheckpoints) { cp in
                        HStack(spacing: 6) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppTheme.accent)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(cp.id.prefix(8)))
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                Text("Commit \(String(cp.commit.prefix(10)))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(AppTheme.tertiaryLabel)
                            }

                            Spacer()

                            Button("Diff") {
                                Task { await previewManualCheckpointDiff(cp) }
                            }
                            .controlSize(.mini)

                            Button("Restore") {
                                pendingManualRestore = cp
                            }
                            .controlSize(.mini)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cp.commit, forType: .string)
                                appModel.presentToast("Copied Checkpoint OID", detail: String(cp.commit.prefix(12)), style: .info)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10.5))
                            }
                            .buttonStyle(.borderless)
                            .help("Copy Commit OID")
                            .accessibilityLabel("Copy checkpoint commit identifier")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                .fill(AppTheme.controlBackground)
                        )
                    }
                }
            }

            // Turn Checkpoints List
            if !turnCheckpoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TURN CHECKPOINTS (\(turnCheckpoints.count))")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppTheme.tertiaryLabel)

                    ForEach(turnCheckpoints) { turn in
                        HStack(spacing: 6) {
                            Image(systemName: turn.running ? "record.circle" : "clock.arrow.circlepath")
                                .font(.system(size: 11))
                                .foregroundStyle(turn.running ? AppTheme.warning : AppTheme.info)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(turnTitle(for: turn.userItemID))
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                    .lineLimit(1)
                                Text("\(turn.fileCount) changed file\(turn.fileCount == 1 ? "" : "s")\(turn.complete ? "" : " · In progress")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }

                            Spacer()

                            if let uuid = UUID(uuidString: turn.userItemID), turn.fileCount > 0 {
                                Button("Inspect") {
                                    Task {
                                        await appModel.refreshDiff(scope: .turn(uuid))
                                        appModel.inspectorTab = .changes
                                    }
                                }
                                .controlSize(.mini)
                            }

                            if turn.complete && !turn.running && turn.fileCount > 0 {
                                Button("Restore") {
                                    pendingRestoreTurn = turn
                                }
                                .controlSize(.mini)
                                .help("Rewind the conversation and restore workspace files to this checkpoint")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                .fill(AppTheme.controlBackground)
                        )
                    }
                }
            }

            if manualCheckpoints.isEmpty && turnCheckpoints.isEmpty && !isLoadingCheckpoints {
                Text("No turn or staged checkpoints recorded yet for this conversation.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(cardBackground)
    }

    // MARK: - New Branch Sheet

    private var newBranchPopoverSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create & Switch Branch")
                .font(.system(size: 14, weight: .semibold))

            Text("Creates a new local branch from \(appModel.activeGitState?.branch ?? "HEAD") and checks it out immediately.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)

            TextField("feature/my-branch", text: $newBranchName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5, design: .monospaced))
                .onSubmit {
                    submitNewBranch()
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    showNewBranchSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Branch") {
                    submitNewBranch()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(sanitizedBranchName.isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
    }

    private var sanitizedBranchName: String {
        newBranchName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
    }

    // MARK: - Styling Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
            .fill(AppTheme.elevatedCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 0.85)
            )
    }

    private func badgePill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }

    private func turnTitle(for itemID: String) -> String {
        if let item = appModel.activeTranscript?.items.first(where: {
            $0.id.uuidString.caseInsensitiveCompare(itemID) == .orderedSame
        }) {
            let line = item.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .first ?? ""
            if !line.isEmpty {
                return line.count > 42 ? String(line.prefix(42)) + "…" : line
            }
        }
        return "Turn \(String(itemID.prefix(8)))"
    }

    // MARK: - Async Operations

    private func reloadAllGitInspectorState() async {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID else {
            statusBreakdown = nil
            manualCheckpoints = []
            turnCheckpoints = []
            historyCommits = []
            worktreesList = []
            return
        }

        await appModel.refreshGitState()
        if let checkout = try? await client.fetchCheckout(thread: tid), appModel.selectedThreadUUID == tid {
            appModel.activeCheckout = checkout
        }
        await loadCheckpointsAndPorcelain()
        await loadHistory(reset: true)
    }

    private func performCheckoutChange(_ action: RemoteCheckoutAction) async {
        isChangingCheckout = true
        defer { isChangingCheckout = false }
        await appModel.changeCheckout(action)
        await appModel.refreshGitState()
        await appModel.refreshDiff()
        await loadCheckpointsAndPorcelain()
    }

    private func submitNewBranch() {
        let name = sanitizedBranchName
        guard !name.isEmpty else { return }
        showNewBranchSheet = false
        Task {
            await performCheckoutChange(.createBranch(name))
        }
    }

    private func triggerGitAction(_ action: RemoteGitActionRequest.Action) {
        if !featureBranch,
           let confirms = appModel.activeGitState?.confirmsOnDefaultBranch,
           confirms.contains(action.rawValue)
        {
            pendingConfirmedAction = action
            return
        }
        Task { await executeGitAction(action) }
    }

    private func executeGitAction(_ action: RemoteGitActionRequest.Action) async {
        runningAction = action
        defer { runningAction = nil }

        let trimmedMsg = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageArg: String? = trimmedMsg.isEmpty ? nil : trimmedMsg

        if let outcome = await appModel.performGitAction(
            action,
            message: messageArg,
            featureBranch: featureBranch
        ) {
            lastActionResult = outcome
            if action == .commit || action == .commitPush || action == .commitPushPR {
                commitMessage = ""
            }
            await loadCheckpointsAndPorcelain()
        }
    }

    private func loadCheckpointsAndPorcelain() async {
        guard let client = appModel.runtime,
              let tid = appModel.selectedThreadUUID
        else { return }

        if appModel.activeGitState?.isRepository == false {
            statusBreakdown = nil
            manualCheckpoints = []
            turnCheckpoints = []
            historyCommits = []
            worktreesList = []
            canonicalRepoRoot = nil
            currentHeadOID = nil
            checkpointStatusMessage = nil
            return
        }

        isLoadingCheckpoints = true
        defer { isLoadingCheckpoints = false }

        let threadString = tid.uuidString.lowercased()

        // 1. Load Turn Checkpoints (`checkpoints.list`)
        if let turnsResp = try? await client.engineRPC(
            method: "checkpoints.list",
            params: ["threadId": .string(threadString)]
        ), let turnsArray = turnsResp["turns"]?.arrayValue {
            self.turnCheckpoints = turnsArray.compactMap { entry in
                guard let itemID = entry["userItemID"]?.stringValue ?? entry["userItemId"]?.stringValue else {
                    return nil
                }
                let complete = entry["complete"]?.boolValue ?? true
                let running = entry["running"]?.boolValue ?? false
                let filesCount = entry["files"]?.arrayValue?.count ?? 0
                return TurnGitCheckpoint(
                    userItemID: itemID,
                    complete: complete,
                    running: running,
                    fileCount: filesCount
                )
            }.reversed()
        } else if let transcript = appModel.activeTranscript {
            // Fallback from transcript.turnChanges
            self.turnCheckpoints = transcript.turnChanges.map { key, files in
                TurnGitCheckpoint(userItemID: key, complete: true, running: false, fileCount: files.count)
            }
        }

        // 2. Load Porcelain Status Breakdown (`git.status`)
        if let statusVal = try? await runEngineWorkspaceOperation(
            client: client,
            method: "git.status",
            params: ["threadId": .string(threadString)],
            resultMethod: "workspace.result"
        ), let entries = statusVal["entries"]?.arrayValue {
            var staged = 0
            var unstaged = 0
            var untracked = 0
            for entry in entries {
                guard let code = entry["status"]?.stringValue, code.count >= 2 else { continue }
                if code == "??" {
                    untracked += 1
                } else {
                    let chars = Array(code)
                    if chars[0] != " " && chars[0] != "?" { staged += 1 }
                    if chars[1] != " " && chars[1] != "?" { unstaged += 1 }
                }
            }
            self.statusBreakdown = GitPorcelainBreakdown(staged: staged, unstaged: unstaged, untracked: untracked)
        } else if let files = appModel.activeDiff?.files {
            let untracked = files.filter { $0.status == "untracked" }.count
            let tracked = max(0, files.count - untracked)
            self.statusBreakdown = GitPorcelainBreakdown(staged: 0, unstaged: tracked, untracked: untracked)
        }

        // 3. Resolve Canonical Working Directory & HEAD OID for `git.checkpoints.*`
        let resolvedRoot = await resolveThreadCanonicalRoot(client: client, threadID: threadString)
        guard let resolvedRoot else {
            canonicalRepoRoot = nil
            currentHeadOID = nil
            manualCheckpoints = []
            return
        }

        do {
            let worktreesVal = try await runEngineWorkspaceOperation(
                client: client,
                method: "git.worktrees.list",
                params: [
                    "threadId": .string(threadString),
                    "expectedRoot": .string(resolvedRoot),
                ],
                resultMethod: "git.workspace.result"
            )
            let worktrees = worktreesVal["worktrees"]?.arrayValue ?? []
            self.worktreesList = worktrees.enumerated().compactMap { index, wt in
                guard let path = wt["worktree"]?.stringValue, !path.isEmpty else { return nil }
                return GitWorktreeEntry(
                    path: path,
                    branch: wt["branch"]?.stringValue,
                    head: wt["HEAD"]?.stringValue,
                    isMain: index == 0
                )
            }
            let matchingTree = worktrees.first { wt in
                guard let wtPath = wt["worktree"]?.stringValue else { return false }
                let canonWT = URL(fileURLWithPath: wtPath).resolvingSymlinksInPath().path
                return canonWT == resolvedRoot
            } ?? worktrees.first

            self.canonicalRepoRoot = resolvedRoot
            self.currentHeadOID = matchingTree?["HEAD"]?.stringValue
            self.checkpointStatusMessage = matchingTree == nil
                ? "Open the repository root folder to create manual staged checkpoints."
                : nil

            let listedVal = try await runEngineWorkspaceOperation(
                client: client,
                method: "git.checkpoints.list",
                params: [
                    "threadId": .string(threadString),
                    "expectedRoot": .string(resolvedRoot),
                ],
                resultMethod: "git.workspace.result"
            )
            let cpItems = listedVal["checkpoints"]?.arrayValue ?? []
            self.manualCheckpoints = cpItems.compactMap { item in
                guard let id = item["id"]?.stringValue else { return nil }
                let commit = item["commit"]?.stringValue ?? ""
                return ManualGitCheckpoint(id: id, commit: commit)
            }
        } catch {
            // Gracefully handle subdirectories or non-git folders without intrusive error dialogs
            self.manualCheckpoints = []
            self.worktreesList = []
            self.checkpointStatusMessage = nil
        }
    }

    private func loadHistory(reset: Bool = true) async {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID else { return }
        if reset {
            historyCommits = []
            historyErrorMessage = nil
        }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let value = try await client.runWorkspaceOperation(
                method: "git.log",
                params: [
                    "threadId": .string(tid.uuidString.lowercased()),
                    "limit": .int(50),
                    "skip": .int(Int64(reset ? 0 : historyCommits.count)),
                ]
            )
            let commits = (value["commits"]?.arrayValue ?? []).compactMap { entry -> GitHistoryCommit? in
                guard let sha = entry["sha"]?.stringValue, !sha.isEmpty,
                      let subject = entry["subject"]?.stringValue
                else { return nil }
                return GitHistoryCommit(
                    sha: sha,
                    parents: entry["parents"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                    authorName: entry["authorName"]?.stringValue ?? "",
                    authorEmail: entry["authorEmail"]?.stringValue ?? "",
                    authorDate: Date(timeIntervalSince1970: entry["authorDate"]?.doubleValue ?? 0),
                    subject: subject,
                    body: entry["body"]?.stringValue ?? ""
                )
            }
            if reset {
                historyCommits = commits
            } else {
                historyCommits.append(contentsOf: commits)
            }
            historyHasMore = commits.count == 50
        } catch {
            historyErrorMessage = error.localizedDescription
        }
    }

    private func previewHistoryCommit(_ commit: GitHistoryCommit) async {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID else { return }
        isLoadingHistoryDetail = true
        defer { isLoadingHistoryDetail = false }
        do {
            let value = try await client.runWorkspaceOperation(
                method: "git.show",
                params: [
                    "threadId": .string(tid.uuidString.lowercased()),
                    "sha": .string(commit.sha),
                ]
            )
            let rawPatch = value["diff"]?.stringValue ?? ""
            let parsed = RemoteDiffParsing.split(rawPatch, title: "Commit \(String(commit.sha.prefix(8)))")
            inspectedHistoryCommit = InspectedCheckpointPatch(
                id: commit.sha,
                commit: commit.sha,
                rawPatch: rawPatch,
                parsedDiff: parsed,
                title: "Commit"
            )
        } catch {
            appModel.presentError(error)
        }
    }

    private func createManualCheckpoint() async {
        let label = newCheckpointLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty,
              let client = appModel.runtime,
              let tid = appModel.selectedThreadUUID,
              let root = canonicalRepoRoot,
              let head = currentHeadOID
        else { return }

        isCreatingCheckpoint = true
        defer { isCreatingCheckpoint = false }

        do {
            let created = try await runEngineWorkspaceOperation(
                client: client,
                method: "git.checkpoints.create",
                params: [
                    "threadId": .string(tid.uuidString.lowercased()),
                    "expectedRoot": .string(root),
                    "expectedHead": .string(head),
                    "label": .string(label),
                ],
                resultMethod: "git.workspace.result"
            )
            let createdID = created["id"]?.stringValue ?? "snapshot"
            newCheckpointLabel = ""
            appModel.presentToast(
                "Checkpoint Created",
                detail: "Saved staged snapshot \(String(createdID.prefix(8)))",
                style: .success
            )
            await loadCheckpointsAndPorcelain()
        } catch {
            appModel.presentError(error)
        }
    }

    private func previewManualCheckpointDiff(_ cp: ManualGitCheckpoint) async {
        guard let client = appModel.runtime,
              let tid = appModel.selectedThreadUUID,
              let root = canonicalRepoRoot
        else { return }

        do {
            let diffVal = try await runEngineWorkspaceOperation(
                client: client,
                method: "git.checkpoints.diff",
                params: [
                    "threadId": .string(tid.uuidString.lowercased()),
                    "expectedRoot": .string(root),
                    "checkpointId": .string(cp.id),
                ],
                resultMethod: "git.workspace.result"
            )
            let rawPatch = diffVal["diff"]?.stringValue ?? ""
            let parsed = RemoteDiffParsing.split(rawPatch, title: "Checkpoint \(String(cp.id.prefix(8)))")
            inspectedCheckpointDiff = InspectedCheckpointPatch(
                id: cp.id,
                commit: cp.commit,
                rawPatch: rawPatch,
                parsedDiff: parsed
            )
        } catch {
            appModel.presentError(error)
        }
    }

    private func restoreManualCheckpoint(_ cp: ManualGitCheckpoint) async {
        guard let client = appModel.runtime,
              let tid = appModel.selectedThreadUUID,
              let root = canonicalRepoRoot
        else { return }

        do {
            _ = try await runEngineWorkspaceOperation(
                client: client,
                method: "git.checkpoints.restore",
                params: [
                    "threadId": .string(tid.uuidString.lowercased()),
                    "expectedRoot": .string(root),
                    "checkpointId": .string(cp.id),
                    "confirm": .bool(true),
                ],
                resultMethod: "git.workspace.result"
            )
            appModel.presentToast("Restored Checkpoint", detail: String(cp.id.prefix(8)), style: .info)
            await loadCheckpointsAndPorcelain()
            await appModel.refreshDiff()
        } catch {
            appModel.presentError(error)
        }
    }

    private func resolveThreadCanonicalRoot(client: AgentsRuntimeClient, threadID: String) async -> String? {
        if let threadDoc = try? await client.engineRPC(
            method: "threads.read",
            params: ["threadId": .string(threadID), "itemLimit": .int(0)]
        ) {
            if let wt = threadDoc["worktreePath"]?.stringValue, !wt.isEmpty {
                let expanded = ExternalEditorService.expandedPath(wt)
                return URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
            }
        }
        if let proj = appModel.selectedProject, !proj.path.isEmpty {
            let expanded = ExternalEditorService.expandedPath(proj.path)
            return URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
        }
        if let cwd = appModel.activeWorkingDirectory, !cwd.isEmpty {
            let expanded = ExternalEditorService.expandedPath(cwd)
            return URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
        }
        return nil
    }

    /// Invokes an `engine.rpc` method and transparently polls `git.workspace.result` or `workspace.result`
    /// when the Rust engine schedules the Git command asynchronously via `operationId`.
    private func runEngineWorkspaceOperation(
        client: AgentsRuntimeClient,
        method: String,
        params: [String: JSONValue],
        resultMethod: String
    ) async throws -> JSONValue {
        let initial = try await client.engineRPC(method: method, params: params)
        guard let opID = initial["operationId"]?.stringValue,
              let threadID = params["threadId"]?.stringValue
        else {
            return initial
        }

        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let poll = try await client.engineRPC(
                method: resultMethod,
                params: [
                    "threadId": .string(threadID),
                    "operationId": .string(opID),
                ]
            )
            if poll["ready"]?.boolValue == true {
                let result = poll["result"] ?? .object([:])
                if let errText = result["error"]?.stringValue, !errText.isEmpty {
                    throw AgentsRuntimeError.desktopFailure(errText)
                }
                return result
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AgentsRuntimeError.desktopFailure("Git workspace operation timed out.")
    }
}

// MARK: - Supporting Types

private struct GitInspectorReloadKey: Equatable {
    let threadID: String?
    let token: UUID
}

private struct GitPorcelainBreakdown: Equatable {
    let staged: Int
    let unstaged: Int
    let untracked: Int
}

private struct GitHistoryCommit: Identifiable, Hashable {
    let sha: String
    let parents: [String]
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let subject: String
    let body: String
    var id: String { sha }
}

private struct GitWorktreeEntry: Identifiable, Hashable {
    let path: String
    let branch: String?
    let head: String?
    let isMain: Bool
    var id: String { path }
}

private struct ManualGitCheckpoint: Identifiable, Hashable {
    let id: String
    let commit: String
}

private struct TurnGitCheckpoint: Identifiable, Hashable {
    let userItemID: String
    let complete: Bool
    let running: Bool
    let fileCount: Int
    var id: String { userItemID }
}

private struct InspectedCheckpointPatch: Identifiable {
    let id: String
    let commit: String
    let rawPatch: String
    let parsedDiff: RemoteDiff
    let title: String

    init(id: String, commit: String, rawPatch: String, parsedDiff: RemoteDiff, title: String = "Checkpoint") {
        self.id = id
        self.commit = commit
        self.rawPatch = rawPatch
        self.parsedDiff = parsedDiff
        self.title = title
    }
}

private struct CheckpointDiffPreviewSheet: View {
    let patch: InspectedCheckpointPatch
    let fontScale: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(patch.title) \(String(patch.id.prefix(8)))")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("Commit \(patch.commit)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                Spacer()
                if !patch.rawPatch.isEmpty {
                    Button("Copy Patch") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(patch.rawPatch, forType: .string)
                    }
                    .controlSize(.small)
                }
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            .background(AppTheme.controlBackground)

            Divider()

            if patch.parsedDiff.files.isEmpty {
                ContentUnavailableView(
                    "Empty Checkpoint Diff",
                    systemImage: "doc.plaintext",
                    description: Text("This checkpoint matches its parent commit tree.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(patch.parsedDiff.files) { file in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Image(systemName: DiffFileStatusStyle.iconName(for: file.status))
                                        .foregroundStyle(DiffFileStatusStyle.tint(for: file.status))
                                    Text(file.path)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    Spacer()
                                    Text("+\(file.additions) −\(file.deletions)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(AppTheme.secondaryLabel)
                                }
                                .padding(8)
                                .background(AppTheme.controlBackground)

                                Divider()

                                ScrollView(.horizontal) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(RemoteDiffParsing.lines(of: file.patch)) { line in
                                            Text(line.text.isEmpty ? " " : line.text)
                                                .font(AppTheme.codeFont(scale: fontScale, size: 11.5))
                                                .foregroundStyle(
                                                    line.kind == .addition
                                                        ? AppTheme.diffAdditionText
                                                        : (line.kind == .deletion ? AppTheme.diffDeletionText : AppTheme.primaryLabel)
                                                )
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 1.5)
                                                .background(
                                                    line.kind == .addition
                                                        ? AppTheme.diffAdditionBackground
                                                        : (line.kind == .deletion ? AppTheme.diffDeletionBackground : Color.clear)
                                                )
                                        }
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .fill(AppTheme.codeBlockBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .strokeBorder(AppTheme.separator, lineWidth: 0.85)
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(AppTheme.windowBackground)
    }
}
