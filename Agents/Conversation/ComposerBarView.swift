import AppKit
import CoincideRemoteKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Local Staged Image Representation

struct ComposerStagedImageItem: Identifiable, Equatable {
    let id: String
    let name: String
    let data: Data
    let thumbnail: NSImage
    let width: Int?
    let height: Int?

    static func == (lhs: ComposerStagedImageItem, rhs: ComposerStagedImageItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Composer Bar View

struct ComposerBarView: View {
    @Bindable var appModel: AppModel

    @State private var draftText: String = ""
    @State private var textViewHeight: CGFloat = ComposerNSTextView.minHeight
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var activeTrigger: ComposerTriggerState? = nil
    @State private var isComposerFocused: Bool = false
    @State private var isDragTargeted: Bool = false
    @State private var pendingEdit: ComposerProgrammaticEdit? = nil

    // Attachments & Completions
    @State private var stagedImages: [ComposerStagedImageItem] = []
    @State private var completions: [RemoteCompletion] = []
    @State private var highlightedCompletionIndex: Int = 0
    @State private var completionTask: Task<Void, Never>? = nil

    // Prompt History
    @State private var sentPromptHistory: [String] = []
    @State private var historyIndex: Int? = nil
    @State private var savedLiveDraftBeforeHistory: String = ""

    // Voice Dictation Insertion Anchor
    @State private var activeDictationInsertion: DictationInsertion? = nil

    // Popovers
    @State private var showAgentModelPopover = false
    @State private var showUsageQuotaPopover = false
    @State private var isSending = false

    private var activeThread: RemoteThreadSummary? {
        appModel.selectedThread
    }

    private var isTurnRunning: Bool {
        if let turn = appModel.activeTranscript?.turn {
            return turn.isRunning || turn.isStarting
        }
        return activeThread?.isRunning == true || activeThread?.isStarting == true
    }

    private var canSteerRunningTurn: Bool {
        appModel.activeTranscript?.turn.canSteer ?? false
    }

    private var queuedMessages: [RemoteQueuedMessage] {
        appModel.activeTranscript?.turn.queued ?? []
    }

    private var hasSendablePayload: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !stagedImages.isEmpty
    }

    /// Extracts `@path/to/file` mentions currently present in `draftText` for visual pill badges.
    private var referencedFilePills: [String] {
        guard draftText.contains("@") else { return [] }
        let tokens = draftText.components(separatedBy: .whitespacesAndNewlines)
        var seen = Set<String>()
        var files: [String] = []
        for token in tokens where token.hasPrefix("@") && token.count > 1 {
            let path = String(token.dropFirst())
            if !seen.contains(path) {
                seen.insert(path)
                files.append(path)
            }
        }
        return files
    }

    private var activeSelection: RemoteSelection {
        activeThread?.selection
            ?? RemoteSelection(provider: "antigravity", modelID: "default", modelName: "Default")
    }

    private var relevantUsageWindows: [(providerName: String, window: RemoteUsage.Window)] {
        let currentProv = AgentBranding.normalizedID(activeSelection.provider)
        let matching = appModel.usageLimits.filter {
            AgentBranding.normalizedID($0.provider) == currentProv
        }
        let source = matching.isEmpty ? appModel.usageLimits : matching
        return source.flatMap { usage in
            usage.windows.map { (providerName: usage.providerName, window: $0) }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // 1. Usage Warning Banner (`RemoteComposerNotice.usageWarning`)
            if let warning = appModel.activeComposerNotice?.usageWarning {
                ComposerUsageWarningBanner(warning: warning, appModel: appModel)
            }

            // 2. Queued Follow-Up Messages Strip when a turn is running
            if !queuedMessages.isEmpty {
                QueuedMessagesStripView(messages: queuedMessages, appModel: appModel)
            }

            // 3. Floating `@` / `/` Autocomplete Popover Card
            if activeTrigger != nil && !completions.isEmpty {
                ComposerCompletionsCard(
                    trigger: activeTrigger?.trigger ?? "@",
                    completions: completions,
                    highlightedIndex: highlightedCompletionIndex,
                    onSelect: { completion in
                        acceptCompletion(completion)
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // 4. Main Composer Card
            VStack(alignment: .leading, spacing: 0) {
                // Staged image thumbnails & `@file` pills strip
                if !stagedImages.isEmpty || !referencedFilePills.isEmpty {
                    composerAttachmentsStrip
                    Divider().opacity(0.6)
                }

                // Voice dictation error banner if any
                if let voiceErr = appModel.voiceDictation.lastError, !voiceErr.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.slash.fill")
                            .foregroundStyle(AppTheme.danger)
                            .font(.system(size: 11))
                        Text(voiceErr)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            appModel.voiceDictation.lastError = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss voice dictation error")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.danger.opacity(0.07))
                }

                // Native AppKit NSTextView
                ComposerNSTextView(
                    text: $draftText,
                    measuredHeight: $textViewHeight,
                    selectedRange: $selectedRange,
                    activeTrigger: $activeTrigger,
                    isFocused: $isComposerFocused,
                    isDragTargeted: $isDragTargeted,
                    placeholder: composerPlaceholder,
                    fontScale: appModel.fontScale,
                    hasActiveCompletions: activeTrigger != nil && !completions.isEmpty,
                    pendingEdit: pendingEdit,
                    onEditConsumed: { consumedID in
                        if pendingEdit?.id == consumedID {
                            pendingEdit = nil
                        }
                    },
                    onSubmit: { alternate in
                        submitMessage(alternateDelivery: alternate)
                    },
                    onCompletionKey: { cmd in
                        handleCompletionCommand(cmd)
                    },
                    onNavigateHistory: { direction in
                        navigateHistory(direction: direction)
                    },
                    onEscape: {
                        if appModel.showFindBar {
                            appModel.showFindBar = false
                        }
                    },
                    onPasteImageData: { data, filename in
                        Task { await stageImageData(data, filename: filename) }
                    },
                    onDropOrPasteURLs: { urls in
                        Task { await handleIncomingURLs(urls) }
                    }
                )
                .frame(height: textViewHeight)

                // Footer Control Bar
                composerFooterControls
            }
            .glassPanel(cornerRadius: AppTheme.cornerRadiusLarge)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                    .strokeBorder(composerBorderColor, lineWidth: isDragTargeted || isComposerFocused ? 1.5 : 1)
            )
        }
        .frame(maxWidth: AppTheme.conversationColumnMaxWidth)
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .onChange(of: activeTrigger) { _, newTrigger in
            refreshCompletions(for: newTrigger)
        }
        .onChange(of: appModel.composerInsertedTextRequest) { _, requestedText in
            guard let requestedText else { return }
            appModel.composerInsertedTextRequest = nil
            pendingEdit = ComposerProgrammaticEdit(.insertAtSelection(requestedText))
        }
        .onReceive(NotificationCenter.default.publisher(for: .coincideFocusComposer)) { _ in
            pendingEdit = ComposerProgrammaticEdit(.focus)
        }
        .task {
            if appModel.usageLimits.isEmpty {
                if let limits = try? await appModel.runtime?.fetchUsageLimits() {
                    appModel.usageLimits = limits
                }
            }
        }
    }

    private var composerPlaceholder: String {
        if isTurnRunning {
            return canSteerRunningTurn
                ? "Steer or queue a follow-up message… (@ files, / commands)"
                : "Queue a follow-up message while \(AgentBranding.displayName(for: activeSelection.provider)) works…"
        }
        let projSuffix = appModel.selectedProject.flatMap { $0.isChats ? nil : " in \($0.name)" } ?? ""
        return "Ask \(AgentBranding.displayName(for: activeSelection.provider))\(projSuffix)… (@ to mention files, / for skills)"
    }

    private var composerBorderColor: Color {
        if isDragTargeted { return AppTheme.accent }
        if appModel.voiceDictation.isRecording { return AppTheme.danger.opacity(0.75) }
        if isComposerFocused { return AppTheme.accent.opacity(0.55) }
        return AppTheme.separator
    }

    // MARK: - Staged Attachments & `@file` Pills Strip

    @ViewBuilder
    private var composerAttachmentsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stagedImages) { img in
                    HStack(spacing: 7) {
                        Image(nsImage: img.thumbnail)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(img.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.primaryLabel)
                                .lineLimit(1)
                                .frame(maxWidth: 120, alignment: .leading)
                            if let w = img.width, let h = img.height {
                                Text("\(w)×\(h)")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(AppTheme.tertiaryLabel)
                            }
                        }

                        Button {
                            stagedImages.removeAll { $0.id == img.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        .buttonStyle(.plain)
                        .help("Remove attached image")
                        .accessibilityLabel("Remove attached image \(img.name)")
                    }
                    .padding(5)
                    .padding(.trailing, 3)
                    .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(AppTheme.separator, lineWidth: 1)
                    )
                }

                ForEach(referencedFilePills, id: \.self) { filePath in
                    HStack(spacing: 5) {
                        Button {
                            appModel.openFileInInspector(path: filePath)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "at")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(AppTheme.accent)
                                Text((filePath as NSString).lastPathComponent)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Inspect \(filePath)")

                        Button {
                            removeFileMention(filePath)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                        }
                        .buttonStyle(.plain)
                        .help("Remove @\(filePath) mention")
                        .accessibilityLabel("Remove file mention \(filePath)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.accent.opacity(0.09), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(AppTheme.accent.opacity(0.35), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Footer Controls

    @ViewBuilder
    private var composerFooterControls: some View {
        HStack(spacing: 8) {
            // 1. Attach Button (`NSOpenPanel`)
            Button {
                presentAttachmentOpenPanel()
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .frame(width: 26, height: 26)
                    .background(AppTheme.subtleHoverFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Attach images or mention workspace files")
            .accessibilityLabel("Attach images or mention workspace files")

            // 2. Voice Dictation Button + Live Level Meter
            voiceDictationControl

            // 3. Agent, Account & Model Popover Button
            Button {
                showAgentModelPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    AgentLogoView(provider: activeSelection.provider, size: 14)

                    Text(resolvedFooterModelLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)

                    if let acctName = activeSelection.accountName, !acctName.isEmpty {
                        Text("· \(acctName)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .lineLimit(1)
                    }

                    if let effort = activeSelection.effort, !effort.isEmpty {
                        Text(effort.uppercased())
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3.5))
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(AppTheme.elevatedCardFill, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(AppTheme.separator.opacity(0.85), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAgentModelPopover, arrowEdge: .top) {
                AgentModelPickerPopover(appModel: appModel)
            }
            .help("Select agent, account, model & reasoning effort")

            // 4. Interaction Mode (`Build` vs `Plan`)
            interactionModeMenu

            // 5. Access Mode (`Approval` vs `Full Access`)
            accessModeMenu

            Spacer(minLength: 4)

            // 6. Usage Quota Indicator Popover (if quota windows exist)
            if !relevantUsageWindows.isEmpty {
                usageQuotaButton
            }

            // 7. Primary Send / Queue / Steer / Stop Button (`⌘.`)
            primaryActionButtons
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .padding(.top, 4)
    }

    private var resolvedFooterModelLabel: String {
        let name = activeSelection.modelName
        if !name.isEmpty && name.lowercased() != "default" {
            return name
        }
        return AgentBranding.displayName(for: activeSelection.provider)
    }

    // MARK: - Voice Dictation Control

    @ViewBuilder
    private var voiceDictationControl: some View {
        let vd = appModel.voiceDictation
        HStack(spacing: 4) {
            Button {
                toggleVoiceDictation()
            } label: {
                HStack(spacing: 5) {
                    if vd.isPreparing {
                        ProgressView()
                            .controlSize(.mini)
                        if let dl = vd.downloadProgress {
                            Text("\(Int(dl * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                    } else if vd.isRecording {
                        Image(systemName: "waveform")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(AppTheme.danger)
                        AudioLevelBarsView(level: vd.audioLevel)
                    } else {
                        Image(systemName: "mic")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
                .padding(.horizontal, vd.isRecording ? 8 : 6)
                .frame(height: 26)
                .background(
                    vd.isRecording ? AppTheme.danger.opacity(0.13) : AppTheme.subtleHoverFill.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .buttonStyle(.plain)
            .help(vd.isRecording ? "Stop voice dictation" : "Start on-device voice dictation")
            .accessibilityLabel(vd.isRecording ? "Stop voice dictation" : "Start voice dictation")
            .contextMenu {
                Section("Microphone Input") {
                    Button {
                        appModel.voiceDictation.selectedMicrophoneUID = nil
                    } label: {
                        HStack {
                            Text("System Default")
                            if appModel.voiceDictation.selectedMicrophoneUID == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    ForEach(appModel.voiceDictation.availableMicrophones) { mic in
                        Button {
                            appModel.voiceDictation.selectedMicrophoneUID = mic.uid
                        } label: {
                            HStack {
                                Text(mic.name)
                                if appModel.voiceDictation.selectedMicrophoneUID == mic.uid {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Refresh Microphones") {
                    appModel.voiceDictation.refreshMicrophones()
                }
            }
        }
    }

    // MARK: - Interaction & Access Mode Menus

    @ViewBuilder
    private var interactionModeMenu: some View {
        let currentMode = activeThread?.interactionMode ?? "build"
        let isPlan = currentMode == "plan"

        Menu {
            Button {
                setInteractionMode("build")
            } label: {
                Label("Build Mode — Edit files & execute tools", systemImage: "hammer")
                if !isPlan { Image(systemName: "checkmark") }
            }

            Button {
                setInteractionMode("plan")
            } label: {
                Label("Plan Mode — Research & design before acting", systemImage: "list.bullet.clipboard")
                if isPlan { Image(systemName: "checkmark") }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isPlan ? "list.bullet.clipboard" : "hammer")
                    .font(.system(size: 11, weight: .medium))
                Text(isPlan ? "Plan" : "Build")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isPlan ? AppTheme.info : AppTheme.secondaryLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                isPlan ? AppTheme.info.opacity(0.11) : AppTheme.elevatedCardFill,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isPlan ? AppTheme.info.opacity(0.45) : AppTheme.separator.opacity(0.8), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch between Build and Plan mode")
    }

    @ViewBuilder
    private var accessModeMenu: some View {
        let currentAccess = activeThread?.accessMode ?? "approval"
        let isFullAccess = currentAccess == "fullAccess" || currentAccess == "full"

        Menu {
            Button {
                setAccessMode("approval")
            } label: {
                Label("Ask for Approval — Prompt before commands & edits", systemImage: "hand.raised")
                if !isFullAccess { Image(systemName: "checkmark") }
            }

            Button {
                setAccessMode("fullAccess")
            } label: {
                Label("Full Access — Run tools autonomously in workspace", systemImage: "bolt.shield")
                if isFullAccess { Image(systemName: "checkmark") }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isFullAccess ? "bolt.shield.fill" : "hand.raised")
                    .font(.system(size: 11, weight: .medium))
                Text(isFullAccess ? "Full Access" : "Approval")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isFullAccess ? AppTheme.warning : AppTheme.secondaryLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                isFullAccess ? AppTheme.warning.opacity(0.10) : AppTheme.elevatedCardFill,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isFullAccess ? AppTheme.warning.opacity(0.45) : AppTheme.separator.opacity(0.8), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Configure tool execution permission mode")
    }

    // MARK: - Usage Quota Indicator & Popover

    @ViewBuilder
    private var usageQuotaButton: some View {
        let peakPercent = relevantUsageWindows.map(\.window.usedPercent).max() ?? 0
        let normalized = min(100, max(0, peakPercent))
        let tint: Color = normalized >= 90 ? AppTheme.danger : (normalized >= 75 ? AppTheme.warning : AppTheme.secondaryLabel)

        Button {
            showUsageQuotaPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.separator, lineWidth: 2)
                        .frame(width: 12, height: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(normalized / 100.0))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 12, height: 12)
                }
                Text("\(Int(normalized.rounded()))%")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppTheme.elevatedCardFill, in: Capsule())
            .overlay(Capsule().strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("View rate-limit quota windows")
        .accessibilityLabel("View rate-limit quota windows")
        .popover(isPresented: $showUsageQuotaPopover, arrowEdge: .top) {
            UsageQuotaPopoverContent(appModel: appModel)
        }
    }

    // MARK: - Primary Send / Queue / Stop Buttons

    @ViewBuilder
    private var primaryActionButtons: some View {
        HStack(spacing: 6) {
            if isTurnRunning {
                Button {
                    Task { await appModel.stopActiveTurn() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Stop")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.onAccent)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(AppTheme.danger, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(".", modifiers: [.command])
                .help("Stop active agent turn (⌘.)")
                .accessibilityLabel("Stop active agent turn")
            }

            if !isTurnRunning || hasSendablePayload {
                Button {
                    let isCommandHeld = NSEvent.modifierFlags.contains(.command)
                    submitMessage(alternateDelivery: isCommandHeld)
                } label: {
                    HStack(spacing: 5) {
                        if isSending {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: isTurnRunning ? (canSteerRunningTurn ? "arrow.turn.down.right" : "clock.badge.plus") : "arrow.up")
                                .font(.system(size: 11.5, weight: .bold))
                        }
                        if isTurnRunning {
                            Text(canSteerRunningTurn ? "Steer" : "Queue")
                                .font(.system(size: 11.5, weight: .semibold))
                        } else if hasSendablePayload {
                            Text("Send")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                    .foregroundStyle(hasSendablePayload ? AppTheme.onAccent : AppTheme.tertiaryLabel)
                    .padding(.horizontal, isTurnRunning ? 11 : 9)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(
                        hasSendablePayload ? AppTheme.accent : AppTheme.elevatedCardFill,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasSendablePayload || isSending)
                .accessibilityLabel(isTurnRunning ? (canSteerRunningTurn ? "Steer running turn" : "Queue follow-up message") : "Send message")
                .help(
                    isTurnRunning
                        ? "Send into running turn or queue (⌘Return or ⌘-Click for alternate delivery)"
                        : "Send message (Return) · ⌘Return for alternate delivery"
                )
            }
        }
    }

    // MARK: - Submit, History, Dictation, Completions & Attachments Logic

    private func submitMessage(alternateDelivery: Bool) {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !stagedImages.isEmpty else { return }
        guard !isSending else { return }

        if appModel.voiceDictation.isRecording {
            Task { _ = await appModel.voiceDictation.stopRecording() }
            activeDictationInsertion = nil
        }

        let outgoingText = trimmed
        let outgoingImages = stagedImages.map { RemoteImage(name: $0.name, data: $0.data) }
        let delivery: RemoteSendRequest.Delivery = alternateDelivery ? .alternate : .automatic

        // Record in prompt history
        if !outgoingText.isEmpty && sentPromptHistory.last != outgoingText {
            sentPromptHistory.append(outgoingText)
            if sentPromptHistory.count > 60 {
                sentPromptHistory.removeFirst()
            }
        }
        historyIndex = nil
        savedLiveDraftBeforeHistory = ""

        draftText = ""
        stagedImages.removeAll()
        activeTrigger = nil
        completions = []
        isSending = true

        Task {
            _ = await appModel.sendMessage(
                text: outgoingText,
                images: outgoingImages,
                delivery: delivery
            )
            isSending = false
        }
    }

    private func navigateHistory(direction: Int) -> Bool {
        guard !sentPromptHistory.isEmpty else { return false }
        if direction < 0 {
            // Up into older prompts
            if let current = historyIndex {
                guard current > 0 else { return true }
                let nextIdx = current - 1
                historyIndex = nextIdx
                pendingEdit = ComposerProgrammaticEdit(.replaceAll(sentPromptHistory[nextIdx]))
                return true
            } else {
                savedLiveDraftBeforeHistory = draftText
                let nextIdx = sentPromptHistory.count - 1
                historyIndex = nextIdx
                pendingEdit = ComposerProgrammaticEdit(.replaceAll(sentPromptHistory[nextIdx]))
                return true
            }
        } else {
            // Down toward newer / live draft
            guard let current = historyIndex else { return false }
            if current + 1 < sentPromptHistory.count {
                let nextIdx = current + 1
                historyIndex = nextIdx
                pendingEdit = ComposerProgrammaticEdit(.replaceAll(sentPromptHistory[nextIdx]))
                return true
            } else {
                historyIndex = nil
                pendingEdit = ComposerProgrammaticEdit(.replaceAll(savedLiveDraftBeforeHistory))
                return true
            }
        }
    }

    private func toggleVoiceDictation() {
        let vd = appModel.voiceDictation
        if vd.isRecording || vd.isPreparing {
            Task {
                _ = await vd.stopRecording()
                activeDictationInsertion = nil
            }
        } else {
            activeDictationInsertion = DictationInsertion(text: draftText, selection: selectedRange)
            Task {
                await vd.startRecording { liveTranscript in
                    applyLiveDictation(liveTranscript)
                }
            }
        }
    }

    private func applyLiveDictation(_ transcript: String) {
        if activeDictationInsertion == nil {
            activeDictationInsertion = DictationInsertion(text: draftText, selection: selectedRange)
        }
        guard var insertion = activeDictationInsertion,
              let edit = insertion.update(transcript)
        else { return }
        activeDictationInsertion = insertion
        pendingEdit = ComposerProgrammaticEdit(
            .replaceRange(edit.range, edit.replacement, moveCaretTo: insertion.caret)
        )
    }

    private func refreshCompletions(for triggerState: ComposerTriggerState?) {
        completionTask?.cancel()
        guard let triggerState else {
            completions = []
            highlightedCompletionIndex = 0
            return
        }

        completionTask = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            var results: [RemoteCompletion] = []

            if let client = appModel.runtime, let tid = appModel.selectedThreadUUID {
                let kind = triggerState.trigger == "@" ? "file" : "command"
                if let fetched = try? await client.fetchCompletions(
                    thread: tid,
                    kind: kind,
                    query: triggerState.query
                ) {
                    results = fetched
                }
            }

            // Fallback for `@` file mentions using `listWorkspaceFiles` (e.g. before a thread exists)
            if results.isEmpty && triggerState.trigger == "@",
               let client = appModel.runtime,
               let cwd = appModel.activeWorkingDirectory
            {
                if let workspaceFiles = try? await client.listWorkspaceFiles(
                    cwd: cwd,
                    query: triggerState.query,
                    limit: 30
                ) {
                    results = workspaceFiles.map { entry in
                        RemoteCompletion(
                            kind: entry.isDirectory ? .folder : .file,
                            insert: "@\(entry.path) ",
                            title: entry.name,
                            detail: entry.path
                        )
                    }
                }
            }

            guard !Task.isCancelled else { return }
            completions = Array(results.prefix(30))
            highlightedCompletionIndex = 0
        }
    }

    private func handleCompletionCommand(_ command: ComposerCompletionKeyCommand) {
        guard !completions.isEmpty else { return }
        switch command {
        case .moveUp:
            highlightedCompletionIndex = (highlightedCompletionIndex - 1 + completions.count) % completions.count
        case .moveDown:
            highlightedCompletionIndex = (highlightedCompletionIndex + 1) % completions.count
        case .accept:
            let idx = min(max(0, highlightedCompletionIndex), completions.count - 1)
            acceptCompletion(completions[idx])
        case .dismiss:
            completions = []
            activeTrigger = nil
        }
    }

    private func acceptCompletion(_ completion: RemoteCompletion) {
        guard let triggerState = activeTrigger else { return }
        let replacement = completion.insert.hasSuffix(" ") ? completion.insert : completion.insert + " "
        pendingEdit = ComposerProgrammaticEdit(
            .replaceRange(triggerState.replacementRange, replacement, moveCaretTo: nil)
        )
        completions = []
        activeTrigger = nil
    }

    private func removeFileMention(_ path: String) {
        let targetWithSpace = "@\(path) "
        let targetBare = "@\(path)"
        if draftText.contains(targetWithSpace) {
            let updated = draftText.replacingOccurrences(of: targetWithSpace, with: "")
            pendingEdit = ComposerProgrammaticEdit(.replaceAll(updated))
        } else if draftText.contains(targetBare) {
            let updated = draftText.replacingOccurrences(of: targetBare, with: "")
            pendingEdit = ComposerProgrammaticEdit(.replaceAll(updated))
        }
    }

    private func presentAttachmentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Attach Images or Mention Workspace Files"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .sourceCode, .plainText, .json, .yaml, .xml, .pdf, .data]

        if let cwd = appModel.activeWorkingDirectory {
            panel.directoryURL = URL(fileURLWithPath: cwd)
        }

        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { await handleIncomingURLs(urls) }
        }
    }

    private func handleIncomingURLs(_ urls: [URL]) async {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "bmp"]
        var mentionsToInsert: [String] = []

        for url in urls {
            let ext = url.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                await stageImageFile(at: url)
            } else {
                let mention = relativePathForWorkspace(url: url)
                mentionsToInsert.append("@\(mention)")
            }
        }

        if !mentionsToInsert.isEmpty {
            let joined = mentionsToInsert.joined(separator: " ") + " "
            let prefix = (!draftText.isEmpty && !draftText.hasSuffix(" ") && !draftText.hasSuffix("\n")) ? " " : ""
            pendingEdit = ComposerProgrammaticEdit(.insertAtSelection(prefix + joined))
        }
    }

    private func relativePathForWorkspace(url: URL) -> String {
        let fullPath = url.path
        if let root = appModel.activeWorkingDirectory {
            let cleanRoot = ExternalEditorService.expandedPath(root)
            let rootPrefix = cleanRoot.hasSuffix("/") ? cleanRoot : cleanRoot + "/"
            if fullPath.hasPrefix(rootPrefix) {
                return String(fullPath.dropFirst(rootPrefix.count))
            }
        }
        return fullPath
    }

    private func stageImageFile(at url: URL) async {
        guard stagedImages.count < 20 else {
            appModel.presentToast("Attachment Limit", detail: "Up to 20 images can be attached per message.", style: .warning)
            return
        }

        do {
            // Stage & validate through `AgentsRuntimeClient.stageAttachment` (passing `threadID: nil` so `RemoteSendRequest.images` sends cleanly without duplicating draft state)
            if let client = appModel.runtime {
                let staged = try await client.stageAttachment(
                    filePath: url.path,
                    filename: url.lastPathComponent,
                    threadID: nil
                )
                let stagedURL = URL(fileURLWithPath: staged.path)
                let bytes: Data
                if let stagedBytes = try? Data(contentsOf: stagedURL) {
                    bytes = stagedBytes
                } else {
                    bytes = try Data(contentsOf: url)
                }
                if let nsImage = NSImage(data: bytes) {
                    stagedImages.append(
                        ComposerStagedImageItem(
                            id: staged.id,
                            name: staged.name,
                            data: bytes,
                            thumbnail: nsImage,
                            width: staged.width,
                            height: staged.height
                        )
                    )
                    return
                }
            }

            let rawBytes = try Data(contentsOf: url)
            if let nsImage = NSImage(data: rawBytes) {
                stagedImages.append(
                    ComposerStagedImageItem(
                        id: UUID().uuidString,
                        name: url.lastPathComponent,
                        data: rawBytes,
                        thumbnail: nsImage,
                        width: Int(nsImage.size.width),
                        height: Int(nsImage.size.height)
                    )
                )
            }
        } catch {
            appModel.presentError(error)
        }
    }

    private func stageImageData(_ data: Data, filename: String) async {
        guard stagedImages.count < 20 else {
            appModel.presentToast("Attachment Limit", detail: "Up to 20 images can be attached per message.", style: .warning)
            return
        }

        do {
            if let client = appModel.runtime {
                let b64 = data.base64EncodedString()
                let staged = try await client.stageAttachment(
                    base64Data: b64,
                    filename: filename,
                    threadID: nil
                )
                let bytes = (try? Data(contentsOf: URL(fileURLWithPath: staged.path))) ?? data
                if let nsImage = NSImage(data: bytes) {
                    stagedImages.append(
                        ComposerStagedImageItem(
                            id: staged.id,
                            name: staged.name,
                            data: bytes,
                            thumbnail: nsImage,
                            width: staged.width,
                            height: staged.height
                        )
                    )
                    return
                }
            }

            if let nsImage = NSImage(data: data) {
                stagedImages.append(
                    ComposerStagedImageItem(
                        id: UUID().uuidString,
                        name: filename,
                        data: data,
                        thumbnail: nsImage,
                        width: Int(nsImage.size.width),
                        height: Int(nsImage.size.height)
                    )
                )
            }
        } catch {
            appModel.presentError(error)
        }
    }

    private func setInteractionMode(_ mode: String) {
        Task {
            let tid: UUID?
            if let existing = appModel.selectedThreadUUID {
                tid = existing
            } else {
                tid = await appModel.createNewThread()
            }
            if let tid {
                await appModel.updateThreadSettings(
                    RemoteThreadSettings(threadID: tid, interactionMode: mode)
                )
            }
        }
    }

    private func setAccessMode(_ mode: String) {
        Task {
            let tid: UUID?
            if let existing = appModel.selectedThreadUUID {
                tid = existing
            } else {
                tid = await appModel.createNewThread()
            }
            if let tid {
                await appModel.updateThreadSettings(
                    RemoteThreadSettings(threadID: tid, accessMode: mode)
                )
            }
        }
    }
}

// MARK: - Live Audio Level Bars

private struct AudioLevelBarsView: View {
    let level: Float

    var body: some View {
        let clamped = CGFloat(max(0.08, min(1.0, level)))
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { idx in
                let scale: CGFloat = switch idx {
                case 0: 0.55
                case 1: 1.0
                case 2: 0.8
                default: 0.45
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppTheme.danger)
                    .frame(width: 2.5, height: max(4, 14 * clamped * scale))
            }
        }
        .frame(height: 14)
        .animation(.linear(duration: 0.08), value: level)
    }
}

// MARK: - Queued Follow-Up Messages Strip

private struct QueuedMessagesStripView: View {
    let messages: [RemoteQueuedMessage]
    let appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.accent)
                Text("QUEUED FOLLOW-UPS (\(messages.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Spacer()
            }

            ForEach(messages) { msg in
                HStack(spacing: 8) {
                    Text(msg.text.isEmpty ? "(Image attachment)" : msg.text)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)

                    if msg.imageCount > 0 {
                        Label("\(msg.imageCount)", systemImage: "photo")
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }

                    Spacer()

                    Button {
                        Task { await appModel.steerQueuedMessage(msg.id) }
                    } label: {
                        Label("Steer Now", systemImage: "arrow.turn.down.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Inject this message immediately into the running turn")

                    Button {
                        Task { await appModel.removeQueuedMessage(msg.id) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .help("Remove queued message")
                    .accessibilityLabel("Remove queued message")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.textBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 1)
                )
            }
        }
        .padding(10)
        .glassPanel()
    }
}

// MARK: - Autocomplete Completions Card (`@` Files & `/` Commands/Skills)

private struct ComposerCompletionsCard: View {
    let trigger: String
    let completions: [RemoteCompletion]
    let highlightedIndex: Int
    let onSelect: (RemoteCompletion) -> Void

    private func icon(for kind: RemoteCompletion.Kind) -> String {
        switch kind {
        case .file: "doc.text"
        case .folder: "folder"
        case .command: "terminal"
        case .skill: "sparkles"
        case .unknown: "circle.dotted"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(trigger == "@" ? "WORKSPACE FILES" : "SLASH COMMANDS & SKILLS")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                Spacer()
                Text("↑↓ Navigate · ↩ Insert · Esc Dismiss")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.025))

            Divider()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(completions.enumerated()), id: \.element.id) { idx, item in
                            let isSelected = idx == highlightedIndex
                            Button {
                                onSelect(item)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: icon(for: item.kind))
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.secondaryLabel)
                                        .frame(width: 16)

                                    Text(item.title)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: trigger == "@" ? .monospaced : .default))
                                        .foregroundStyle(AppTheme.primaryLabel)
                                        .lineLimit(1)

                                    if let detail = item.detail, !detail.isEmpty, detail != item.title {
                                        Text(detail)
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.secondaryLabel)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5.5)
                                .background(
                                    isSelected ? AppTheme.accent.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(idx)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 210)
                .onChange(of: highlightedIndex) { _, target in
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        .glassPanel()
    }
}

// MARK: - Composer Usage Warning Notice Banner

private struct ComposerUsageWarningBanner: View {
    let warning: RemoteUsageWarning
    let appModel: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.warning)

            Text(warning.text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.primaryLabel)
                .lineLimit(2)

            Spacer()

            if warning.resumesAt != nil {
                Button("Cancel Auto-Resume") {
                    sendWarningAction(.cancelResume)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if warning.canResumeAtReset {
                Button("Resume at Reset") {
                    sendWarningAction(.resumeAtReset)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button {
                sendWarningAction(.dismiss)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss usage warning")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.warning.opacity(0.4), lineWidth: 1)
        )
    }

    private func sendWarningAction(_ action: RemoteUsageWarningCommand.Action) {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID else { return }
        Task {
            if let updated = try? await client.performUsageWarningAction(
                RemoteUsageWarningCommand(threadID: tid, key: warning.key, action: action)
            ) {
                appModel.activeComposerNotice = updated
            }
        }
    }
}

// MARK: - Usage Quota Popover

private struct UsageQuotaPopoverContent: View {
    let appModel: AppModel
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Provider Quota Windows", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Spacer()
                Button {
                    isRefreshing = true
                    Task {
                        if let limits = try? await appModel.runtime?.fetchUsageLimits() {
                            appModel.usageLimits = limits
                        }
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh quota windows")
            }

            if appModel.usageLimits.isEmpty {
                Text("No active rate-limit windows reported by connected providers.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
            } else {
                ForEach(appModel.usageLimits) { usage in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            AgentLogoView(provider: usage.provider, size: 14)
                            Text(usage.providerName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.primaryLabel)
                            if let acct = usage.accountName, !acct.isEmpty {
                                Text("· \(acct)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                        }

                        ForEach(usage.windows) { window in
                            let clamped = min(100, max(0, window.usedPercent))
                            let barColor: Color = clamped >= 90 ? AppTheme.danger : (clamped >= 75 ? AppTheme.warning : AppTheme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(window.label)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(AppTheme.primaryLabel)
                                    Spacer()
                                    Text("\(Int(clamped.rounded()))% used")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(barColor)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(AppTheme.elevatedCardFill)
                                        Capsule()
                                            .fill(barColor)
                                            .frame(width: max(4, geo.size.width * CGFloat(clamped / 100.0)))
                                    }
                                }
                                .frame(height: 6)

                                if let resets = window.resetsAt {
                                    Text("Resets \(resets.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(AppTheme.tertiaryLabel)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                }
            }
        }
        .padding(14)
        .frame(minWidth: 340, idealWidth: 360, maxWidth: 400)
    }
}
