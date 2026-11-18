import CoincideRemoteKit
import SwiftUI

/// Prominent interactive banner docked right above the composer whenever any `.approval` or `.question`
/// item in the active transcript is waiting for user input.
struct PendingAttentionView: View {
    let transcript: RemoteTranscript
    let appModel: AppModel

    private var pendingItems: [RemoteItem] {
        transcript.items.filter { item in
            item.isWaiting && (item.kind == .approval || item.kind == .question)
        }
    }

    var body: some View {
        let waiting = pendingItems
        if !waiting.isEmpty {
            VStack(spacing: 10) {
                ForEach(waiting) { item in
                    switch item.kind {
                    case .approval:
                        ApprovalAttentionCard(
                            item: item,
                            threadID: transcript.thread.id,
                            appModel: appModel
                        )
                    case .question:
                        QuestionAttentionCard(
                            item: item,
                            threadID: transcript.thread.id,
                            appModel: appModel
                        )
                    default:
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: AppTheme.conversationColumnMaxWidth)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Approval Attention Card

private struct ApprovalAttentionCard: View {
    let item: RemoteItem
    let threadID: UUID
    let appModel: AppModel

    @State private var noteText: String = ""
    @State private var submittingOptionID: String? = nil

    private var targetFilePath: String? {
        guard let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty,
              !detail.contains("\n")
        else { return nil }
        let expanded = ExternalEditorService.expandedPath(detail)
        if FileManager.default.fileExists(atPath: expanded) {
            return detail
        }
        if let root = appModel.activeWorkingDirectory {
            let candidate = (ExternalEditorService.expandedPath(root) as NSString).appendingPathComponent(detail)
            if FileManager.default.fileExists(atPath: candidate) {
                return detail
            }
        }
        return nil
    }

    var body: some View {
        let approval = item.approval ?? RemoteApproval(
            options: [
                RemoteApproval.Option(id: "allowOnce", label: "Allow Once", kind: "allowOnce"),
                RemoteApproval.Option(id: "allowAlways", label: "Allow Always", kind: "allowAlways"),
                RemoteApproval.Option(id: "deny", label: "Deny", kind: "deny"),
            ]
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.warning.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title ?? "Tool Permission Required")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                    if let category = item.category, !category.isEmpty {
                        Text(category == "fileChange" ? "File Modification" : category.capitalized)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }

                Spacer()

                if let path = targetFilePath {
                    Button {
                        appModel.openFileInInspector(path: path)
                    } label: {
                        Label("Inspect File", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let detail = item.detail, !detail.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(detail)
                        .font(AppTheme.codeFont(scale: appModel.fontScale, size: 11.75))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .frame(maxHeight: 110)
                .background(AppTheme.codeBlockBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 1)
                )
            } else if !item.text.isEmpty {
                Text(item.text)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            if approval.acceptsText {
                TextField(
                    approval.textPlaceholder ?? "Optional instructions or reason…",
                    text: $noteText
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            }

            HStack(spacing: 8) {
                ForEach(approval.options) { option in
                    approvalOptionButton(option)
                }
                Spacer()
            }
        }
        .padding(14)
        .glassPanelTinted(AppTheme.warning.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.warning.opacity(0.55), lineWidth: 1.25)
        )
    }

    @ViewBuilder
    private func approvalOptionButton(_ option: RemoteApproval.Option) -> some View {
        let isBusy = submittingOptionID != nil
        let isPrimary = option.kind == "allowOnce"
        let isDestructive = option.kind == "deny" || option.kind == "cancel"

        if isPrimary {
            Button {
                submitOption(option)
            } label: {
                HStack(spacing: 5) {
                    if submittingOptionID == option.id {
                        ProgressView().controlSize(.mini)
                    }
                    Text(option.label)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isBusy)
        } else {
            Button(role: isDestructive ? .destructive : nil) {
                submitOption(option)
            } label: {
                HStack(spacing: 5) {
                    if submittingOptionID == option.id {
                        ProgressView().controlSize(.mini)
                    }
                    Text(option.label)
                }
            }
            .buttonStyle(.bordered)
            .tint(isDestructive ? AppTheme.danger : nil)
            .controlSize(.regular)
            .disabled(isBusy)
        }
    }

    private func submitOption(_ option: RemoteApproval.Option) {
        submittingOptionID = option.id
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await appModel.respondToApproval(
                itemID: item.id,
                optionID: option.id,
                text: trimmedNote.isEmpty ? nil : trimmedNote,
                threadID: threadID
            )
            submittingOptionID = nil
        }
    }
}

// MARK: - Question Set Attention Card

private struct QuestionAttentionCard: View {
    let item: RemoteItem
    let threadID: UUID
    let appModel: AppModel

    @State private var selectedOptions: [String: Set<String>] = [:]
    @State private var customAnswers: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var isDismissing = false

    private var questionsList: [RemoteQuestionSet.Question] {
        item.questions?.questions ?? []
    }

    private var compiledAnswers: [String: [String]] {
        var output: [String: [String]] = [:]
        for question in questionsList {
            var values: [String] = []
            let picked = selectedOptions[question.id] ?? []
            // Preserve question option order
            for opt in question.options where picked.contains(opt.label) {
                values.append(opt.label)
            }
            if let custom = customAnswers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !custom.isEmpty
            {
                values.append(custom)
            }
            output[question.id] = values
        }
        return output
    }

    private var canSubmit: Bool {
        guard !questionsList.isEmpty else { return false }
        let compiled = compiledAnswers
        return questionsList.allSatisfy { q in
            !(compiled[q.id] ?? []).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                Text(item.questions?.title ?? "Agent Needs Clarification")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)

                Spacer()

                Button {
                    isDismissing = true
                    Task {
                        await appModel.dismissQuestion(itemID: item.id, threadID: threadID)
                        isDismissing = false
                    }
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSubmitting || isDismissing)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(questionsList) { question in
                        questionBlock(question)
                    }
                }
            }
            .frame(maxHeight: 280)

            HStack {
                Text("Select an option or type a custom response.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryLabel)

                Spacer()

                Button {
                    isSubmitting = true
                    let payload = compiledAnswers
                    Task {
                        await appModel.answerQuestion(
                            itemID: item.id,
                            answers: payload,
                            threadID: threadID
                        )
                        isSubmitting = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isSubmitting {
                            ProgressView().controlSize(.mini)
                        }
                        Text("Submit Answer")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!canSubmit || isSubmitting || isDismissing)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(14)
        .glassPanelTinted(AppTheme.accent.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.accent.opacity(0.55), lineWidth: 1.25)
        )
    }

    @ViewBuilder
    private func questionBlock(_ question: RemoteQuestionSet.Question) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let header = question.header, !header.isEmpty {
                    Text(header.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
                if question.allowsMultipleSelection {
                    Text("Select all that apply")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
            }

            Text(question.prompt)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AppTheme.primaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            if !question.options.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(question.options, id: \.label) { option in
                        let isSelected = selectedOptions[question.id]?.contains(option.label) == true
                        Button {
                            toggleOption(option.label, for: question)
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(
                                    systemName: question.allowsMultipleSelection
                                        ? (isSelected ? "checkmark.square.fill" : "square")
                                        : (isSelected ? "largecircle.fill.circle" : "circle")
                                )
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryLabel)
                                .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(AppTheme.primaryLabel)
                                    if let detail = option.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.secondaryLabel)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? AppTheme.accent.opacity(0.10) : AppTheme.elevatedCardFill,
                                in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .strokeBorder(
                                        isSelected ? AppTheme.accent.opacity(0.55) : AppTheme.separator.opacity(0.75),
                                        lineWidth: 1
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.label)\(option.detail.map { ", \($0)" } ?? "")")
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }

            if question.allowsFreeText || question.options.isEmpty {
                let textBinding = Binding<String>(
                    get: { customAnswers[question.id] ?? "" },
                    set: { newVal in
                        customAnswers[question.id] = newVal
                        if !newVal.isEmpty && !question.allowsMultipleSelection {
                            selectedOptions[question.id] = []
                        }
                    }
                )
                if question.isSecret {
                    SecureField("Enter secret value…", text: textBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                } else {
                    TextField(
                        question.options.isEmpty ? "Type your answer…" : "Or enter a custom answer…",
                        text: textBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                }
            }
        }
    }

    private func toggleOption(_ label: String, for question: RemoteQuestionSet.Question) {
        var current = selectedOptions[question.id] ?? []
        if current.contains(label) {
            current.remove(label)
        } else {
            if !question.allowsMultipleSelection {
                current.removeAll()
                customAnswers[question.id] = ""
            }
            current.insert(label)
        }
        selectedOptions[question.id] = current
    }
}
