import CoincideRemoteKit
import SwiftUI

struct CheckoutPopoverView: View {
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var branchFilter: String = ""
    @State private var newBranchName: String = ""
    @State private var isRefreshing = false
    @State private var isMutating = false

    private var checkout: RemoteCheckout? {
        appModel.activeCheckout
    }

    private var filteredBranches: [RemoteBranch] {
        guard let branches = checkout?.branches else { return [] }
        let q = branchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return branches }
        return branches.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Git Checkout & Worktree", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)

                Spacer()

                if isRefreshing || isMutating || checkout?.isBusy == true {
                    ProgressView()
                        .controlSize(.mini)
                }

                Button {
                    Task { await reloadCheckout() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .help("Refresh Git branches")
                .accessibilityLabel("Refresh Git branches")
            }

            if let checkout {
                // Workspace Mode Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("WORKSPACE ISOLATION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.tertiaryLabel)

                    HStack(spacing: 6) {
                        workspaceOptionButton(
                            title: "Local Checkout",
                            subtitle: "Project folder",
                            icon: "folder",
                            isSelected: checkout.workspace == .local,
                            isEnabled: checkout.canChangeWorkspace && !checkout.isBusy && !isMutating
                        ) {
                            performAction(.useLocal)
                        }

                        workspaceOptionButton(
                            title: "Git Worktree",
                            subtitle: checkout.workspace == .worktree ? "Isolated copy" : "New isolated copy",
                            icon: "square.split.2x1",
                            isSelected: checkout.workspace == .worktree || checkout.workspace == .newWorktree,
                            isEnabled: checkout.canChangeWorkspace && !checkout.isBusy && !isMutating
                        ) {
                            performAction(.useNewWorktree)
                        }
                    }

                    if checkout.hasPreviousWorktree, checkout.canChangeWorkspace {
                        Button {
                            performAction(.usePreviousWorktree)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11))
                                Text("Reuse Previous Worktree\(checkout.previousWorktreeBranch.map { " (\($0))" } ?? "")")
                                    .font(.system(size: 11.5, weight: .medium))
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                        }
                        .buttonStyle(.plain)
                        .disabled(checkout.isBusy || isMutating)
                    }

                    if !checkout.canChangeWorkspace {
                        Text(
                            checkout.workspace == .worktree
                                ? "Running in an isolated git worktree."
                                : "Workspace mode is locked after the first message."
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                }

                Divider()

                // Branch Switcher Section
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(checkout.workspace == .newWorktree ? "BASE BRANCH" : "BRANCH")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                        Spacer()
                        if let activeBranch = checkout.workspace == .newWorktree ? checkout.baseBranch : checkout.branch {
                            Text(activeBranch)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.accent)
                                .lineLimit(1)
                        }
                    }

                    if checkout.branches.count > 5 {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                            TextField("Filter branches…", text: $branchFilter)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                            if !branchFilter.isEmpty {
                                Button {
                                    branchFilter = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.tertiaryLabel)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear branch filter")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                .strokeBorder(AppTheme.separator, lineWidth: 1)
                        )
                    }

                    if filteredBranches.isEmpty {
                        Text(checkout.branches.isEmpty ? "No Git branches detected." : "No matching branches.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .padding(.vertical, 8)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(filteredBranches) { branch in
                                    branchRow(branch, checkout: checkout)
                                }
                            }
                        }
                        .frame(maxHeight: 190)
                    }
                }

                // Create New Branch Section
                if checkout.canCreateBranch {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CREATE NEW BRANCH")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.tertiaryLabel)

                        HStack(spacing: 6) {
                            TextField("feat/my-branch", text: $newBranchName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .onSubmit {
                                    createNewBranchIfValid()
                                }

                            Button("Create") {
                                createNewBranchIfValid()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(
                                newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || checkout.isBusy
                                    || isMutating
                            )
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Not a Git repository")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(AppTheme.primaryLabel)
                    Text("Initialize Git in this project folder or select a repository to manage branches and isolated worktrees.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .frame(minWidth: 300, idealWidth: 330, maxWidth: 380)
        .task {
            await reloadCheckout()
        }
    }

    @ViewBuilder
    private func workspaceOptionButton(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryLabel)
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? AppTheme.accent.opacity(0.11) : AppTheme.elevatedCardFill,
                in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .strokeBorder(isSelected ? AppTheme.accent.opacity(0.6) : AppTheme.separator, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled && !isSelected)
        .opacity((!isEnabled && !isSelected) ? 0.55 : 1.0)
    }

    @ViewBuilder
    private func branchRow(_ branch: RemoteBranch, checkout: RemoteCheckout) -> some View {
        let isSelected = (checkout.workspace == .newWorktree)
            ? (checkout.baseBranch == branch.name)
            : (branch.isCurrent || checkout.branch == branch.name)
        let disabled = !checkout.canPickBranch
            || checkout.isBusy
            || isMutating
            || (branch.isCheckedOutElsewhere && checkout.workspace == .local)

        Button {
            performAction(.pickBranch(branch.name))
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark" : "arrow.triangle.branch")
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.tertiaryLabel)
                    .frame(width: 14)

                Text(branch.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if branch.isRemote {
                    Text("remote")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AppTheme.subtleHoverFill, in: Capsule())
                }

                if branch.isCheckedOutElsewhere {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.warning)
                        .help("Checked out in another worktree")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isSelected ? AppTheme.accent.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled && !isSelected ? 0.5 : 1.0)
    }

    private func reloadCheckout() async {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID else { return }
        isRefreshing = true
        if let updated = try? await client.fetchCheckout(thread: tid) {
            appModel.activeCheckout = updated
        }
        isRefreshing = false
    }

    private func performAction(_ action: RemoteCheckoutAction) {
        isMutating = true
        Task {
            await appModel.changeCheckout(action)
            isMutating = false
        }
    }

    private func createNewBranchIfValid() {
        let trimmed = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isMutating = true
        Task {
            await appModel.changeCheckout(.createBranch(trimmed))
            newBranchName = ""
            isMutating = false
            dismiss()
        }
    }
}
