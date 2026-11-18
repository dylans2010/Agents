import CoincideRemoteKit
import SwiftUI

struct RewindConversationSheet: View {
    let threadID: UUID
    let item: RemoteItem
    let appModel: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var options: RemoteRewindOptions? = nil
    @State private var isLoadingOptions = true
    @State private var revertsFiles = false
    @State private var isSubmitting = false
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AppTheme.warning)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit / Rewind Conversation")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                    Text("Rewinds this thread to right before the selected message and places it back in the composer.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                Spacer()
            }

            // Selected message preview
            VStack(alignment: .leading, spacing: 6) {
                Text("SELECTED MESSAGE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryLabel)

                Text(item.text.isEmpty ? "(Attachment message)" : item.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .strokeBorder(AppTheme.separator, lineWidth: 1)
                    )
            }

            if isLoadingOptions {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking turn checkpoints…")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .padding(.vertical, 8)
            } else if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.danger)
            } else if let options {
                if options.isRunning {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .foregroundStyle(AppTheme.warning)
                        Text("An agent turn is currently running. Stop the active turn before rewinding.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.primaryLabel)
                        Spacer()
                        Button("Stop Turn") {
                            Task {
                                await appModel.stopActiveTurn(threadID: threadID)
                                await fetchOptions()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.danger)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(AppTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                } else if options.canRevertFiles {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WORKSPACE FILES")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.tertiaryLabel)

                        rewindModeCard(
                            selected: !revertsFiles,
                            title: "Keep File Changes on Disk",
                            subtitle: "Rewinds only the conversation history. Edits made to workspace files stay untouched.",
                            icon: "doc.badge.gearshape",
                            destructive: false
                        ) {
                            revertsFiles = false
                        }

                        rewindModeCard(
                            selected: revertsFiles,
                            title: "Revert Workspace Files Too",
                            subtitle: "Restores tracked workspace files to the checkpoint captured before this message.",
                            icon: "clock.arrow.circlepath",
                            destructive: true
                        ) {
                            revertsFiles = true
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Text("Conversation history after this message will be removed. Workspace files on disk will not be modified.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(role: revertsFiles ? .destructive : nil) {
                    performRewind()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(revertsFiles ? "Rewind & Revert Files" : "Rewind Conversation")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(revertsFiles ? AppTheme.danger : AppTheme.accent)
                .disabled(isLoadingOptions || isSubmitting || options?.isRunning == true || loadError != nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            await fetchOptions()
        }
    }

    @ViewBuilder
    private func rewindModeCard(
        selected: Bool,
        title: String,
        subtitle: String,
        icon: String,
        destructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let highlight = destructive ? AppTheme.danger : AppTheme.accent
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? highlight : AppTheme.secondaryLabel)
                    .padding(.top, 2)

                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? highlight : AppTheme.secondaryLabel)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(destructive && selected ? AppTheme.danger : AppTheme.primaryLabel)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(10)
            .background(
                selected ? highlight.opacity(0.09) : AppTheme.elevatedCardFill,
                in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .strokeBorder(selected ? highlight.opacity(0.6) : AppTheme.separator, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fetchOptions() async {
        guard let client = appModel.runtime else {
            isLoadingOptions = false
            return
        }
        isLoadingOptions = true
        loadError = nil
        do {
            let fetched = try await client.fetchRewindOptions(thread: threadID, itemID: item.id)
            options = fetched
            if !fetched.canRevertFiles {
                revertsFiles = false
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingOptions = false
    }

    private func performRewind() {
        isSubmitting = true
        Task {
            if let _ = await appModel.rewindConversation(to: item.id, revertsFiles: revertsFiles) {
                dismiss()
            }
            isSubmitting = false
        }
    }
}
