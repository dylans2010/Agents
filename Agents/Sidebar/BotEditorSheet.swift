import AppKit
import CoincideRemoteKit
import SwiftUI

public extension RemoteBotAvatar {
    typealias Character = BotArtwork.Character
    typealias Tint = BotArtwork.Tint
}

public struct BotEditorSheet: View {
    @Bindable public var appModel: AppModel

    @State private var look: BotEditorLook = BotEditorLook(character: .alien)
    @State private var personalityState: BotEditorPersonality = BotEditorPersonality(editing: nil)
    @State private var persona: String = ""

    @State private var selectedProvider: String = ""
    @State private var selectedModelID: String = ""
    @State private var selectedEffort: String = ""
    @State private var selectedAccessMode: String = ""
    @State private var selectedInteractionMode: String = ""

    @State private var eyeOpenness: CGFloat = 1.0
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var didInitializeState: Bool = false

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var editingBot: RemoteBot? {
        appModel.editingBot
    }

    private var currentAvatar: RemoteBotAvatar {
        RemoteBotAvatar(look.character, look.tint)
    }

    private var trimmedName: String {
        look.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated struct ProviderOption: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let models: [ModelOption]
    }

    private nonisolated struct ModelOption: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let efforts: [String]
    }

    private var providerOptions: [ProviderOption] {
        if !appModel.providers.isEmpty {
            return appModel.providers
                .filter(\.isEnabled)
                .map { p in
                    ProviderOption(
                        id: p.id,
                        name: p.displayName,
                        models: p.models.filter(\.isVisible).map {
                            ModelOption(id: $0.id, name: $0.name, efforts: $0.efforts)
                        }
                    )
                }
        }
        return appModel.workspace.providers.map { p in
            ProviderOption(
                id: p.id,
                name: p.name,
                models: p.models.map {
                    ModelOption(id: $0.id, name: $0.name, efforts: $0.efforts)
                }
            )
        }
    }

    private var modelsForSelectedProvider: [ModelOption] {
        providerOptions.first(where: { $0.id == selectedProvider })?.models ?? []
    }

    private var effortsForSelectedModel: [String] {
        modelsForSelectedProvider.first(where: { $0.id == selectedModelID })?.efforts ?? []
    }

    public var body: some View {
        VStack(spacing: 0) {
            heroPreviewHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identityAndAppearanceCard
                    personalityCard
                    systemPromptCard
                    defaultModelCard
                }
                .padding(20)
            }

            Divider()

            footerBar
        }
        .frame(minWidth: 580, idealWidth: 640, maxWidth: 720, minHeight: 560, idealHeight: 660, maxHeight: 780)
        .background(AppTheme.windowBackground)
        .onAppear {
            initializeFromEditingBotIfNeeded()
        }
        .task {
            if appModel.providers.isEmpty {
                await appModel.refreshProviders()
            }
        }
        .task {
            await runNaturalBlinkLoop()
        }
        .confirmationDialog(
            "Delete Bot?",
            isPresented: $showDeleteConfirmation,
            presenting: editingBot
        ) { bot in
            Button("Delete Bot (Keep Conversations)", role: .destructive) {
                Task {
                    await appModel.deleteBot(bot.id, deletesConversations: false)
                    closeSheet()
                }
            }
            Button("Delete Bot & Conversations", role: .destructive) {
                Task {
                    await appModel.deleteBot(bot.id, deletesConversations: true)
                    closeSheet()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { bot in
            Text("Delete “\(bot.name)”? Existing conversations can remain as standard chats or be deleted permanently.")
        }
    }

    // MARK: - Live Preview Header

    private var heroPreviewHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(tintSwiftUIColor(look.tint).opacity(0.16))
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(tintSwiftUIColor(look.tint).opacity(0.35), lineWidth: 1)
                    .frame(width: 76, height: 76)
                BotAvatarView(avatar: currentAvatar, size: 60, eyeOpenness: eyeOpenness)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(trimmedName.isEmpty ? look.character.defaultName : trimmedName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)

                    Text(editingBot == nil ? "New Bot" : "Editing Bot")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.elevatedCardFill, in: Capsule())
                }

                if let activePreset = BotPersonalityPreset.preset(id: personalityState.presetID),
                   !activePreset.greeting.isEmpty
                {
                    Text("“\(activePreset.greeting)”")
                        .font(.system(size: 12.5, design: .serif))
                        .italic()
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                } else if personalityState.choice == .custom,
                          !personalityState.custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    Text(personalityState.custom.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                } else {
                    Text("Configure character, personality tone, standing instructions, and default agent.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(AppTheme.elevatedCardFill)
    }

    // MARK: - Name, Character & Tint Card

    private var identityAndAppearanceCard: some View {
        editorSectionCard(title: "Identity & Appearance", symbol: "paintpalette") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    TextField("Bot Name", text: $look.name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Character")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)

                    HStack(spacing: 8) {
                        ForEach(RemoteBotAvatar.Character.allCases, id: \.rawValue) { character in
                            let isSelected = look.character == character
                            let previewTint = look.pickerTint(for: character)
                            Button {
                                selectCharacter(character)
                            } label: {
                                VStack(spacing: 4) {
                                    BotAvatarView(
                                        avatar: RemoteBotAvatar(character, previewTint),
                                        size: 38
                                    )
                                    Text(character.defaultName)
                                        .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? AppTheme.primaryLabel : AppTheme.secondaryLabel)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                        .fill(isSelected ? tintSwiftUIColor(previewTint).opacity(0.16) : AppTheme.controlBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                        .strokeBorder(
                                            isSelected ? Color.accentColor : AppTheme.separator,
                                            lineWidth: isSelected ? 2 : 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Color Tint")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                        Text(look.tint.rawValue.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }

                    HStack(spacing: 10) {
                        ForEach(RemoteBotAvatar.Tint.allCases, id: \.rawValue) { tint in
                            let isSelected = look.tint == tint
                            Button {
                                look.tint = tint
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(tintSwiftUIColor(tint))
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                                        )

                                    if isSelected {
                                        Circle()
                                            .strokeBorder(AppTheme.primaryLabel, lineWidth: 2)
                                            .frame(width: 32, height: 32)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                                    }
                                }
                                .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .help(tint.rawValue.capitalized)
                            .accessibilityLabel("Tint \(tint.rawValue.capitalized)")
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Personality Presets & Custom Tone Card

    private var personalityCard: some View {
        editorSectionCard(title: "Personality & Conversational Style", symbol: "theatermasks") {
            VStack(alignment: .leading, spacing: 12) {
                let columns = [
                    GridItem(.adaptive(minimum: 132), spacing: 8),
                ]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    personalityChip(
                        title: "None",
                        symbol: "circle.slash",
                        isSelected: personalityState.choice == .none
                    ) {
                        personalityState.pick(.none)
                    }

                    ForEach(BotPersonalityPreset.all) { preset in
                        personalityChip(
                            title: preset.name,
                            symbol: preset.symbol,
                            isSelected: personalityState.presetID == preset.id
                        ) {
                            personalityState.pick(.preset(preset.id))
                        }
                    }

                    personalityChip(
                        title: "Custom",
                        symbol: "pencil.and.scribble",
                        isSelected: personalityState.choice == .custom
                    ) {
                        personalityState.pick(.custom)
                    }
                }

                if let activePreset = BotPersonalityPreset.preset(id: personalityState.presetID) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: activePreset.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(activePreset.summary)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.primaryLabel)
                            Text(activePreset.prompt)
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        Button("Customize…") {
                            personalityState.start(from: activePreset.prompt)
                        }
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .strokeBorder(AppTheme.separator, lineWidth: 1)
                    )
                } else if personalityState.choice == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Custom Personality Tone")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(AppTheme.secondaryLabel)
                            Spacer()
                            Text("\(personalityState.custom.count)/\(BotPersonalityPreset.customLimit)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                        }

                        TextEditor(text: $personalityState.custom)
                            .font(.system(size: 12.5))
                            .frame(minHeight: 74, maxHeight: 110)
                            .padding(6)
                            .background(AppTheme.textBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .strokeBorder(AppTheme.separator, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func personalityChip(
        title: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : AppTheme.secondaryLabel)
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.primaryLabel : AppTheme.secondaryLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : AppTheme.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .strokeBorder(isSelected ? Color.accentColor : AppTheme.separator, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Standing System Prompt (`persona`) Card

    private var systemPromptCard: some View {
        editorSectionCard(title: "Standing Instructions (System Prompt)", symbol: "doc.text") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Define this bot's specialized job, domain expertise, tools, and workflow rules.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)

                TextEditor(text: $persona)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(minHeight: 96, maxHeight: 150)
                    .padding(6)
                    .background(AppTheme.textBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .strokeBorder(AppTheme.separator, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Default Provider & Model Card

    private var defaultModelCard: some View {
        editorSectionCard(title: "Default Agent & Execution Defaults", symbol: "cpu") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Provider")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .gridColumnAlignment(.trailing)

                    Picker("Provider", selection: $selectedProvider) {
                        Text("Workspace Default").tag("")
                        ForEach(providerOptions) { provider in
                            HStack(spacing: 6) {
                                AgentLogoView(provider: provider.id, size: 14)
                                Text(provider.name)
                            }
                            .tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedProvider) { _, newValue in
                        if newValue.isEmpty {
                            selectedModelID = ""
                            selectedEffort = ""
                        } else {
                            let validModels = providerOptions.first(where: { $0.id == newValue })?.models ?? []
                            if !validModels.contains(where: { $0.id == selectedModelID }) {
                                selectedModelID = ""
                                selectedEffort = ""
                            }
                        }
                    }
                }

                if !selectedProvider.isEmpty {
                    GridRow {
                        Text("Model")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)

                        if !modelsForSelectedProvider.isEmpty {
                            Picker("Model", selection: $selectedModelID) {
                                Text("Provider Default").tag("")
                                ForEach(modelsForSelectedProvider) { model in
                                    Text(model.name).tag(model.id)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: selectedModelID) { _, _ in
                                if !effortsForSelectedModel.contains(selectedEffort) {
                                    selectedEffort = ""
                                }
                            }
                        } else {
                            TextField("Model ID (optional)", text: $selectedModelID)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if !effortsForSelectedModel.isEmpty {
                    GridRow {
                        Text("Effort")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)

                        Picker("Effort", selection: $selectedEffort) {
                            Text("Model Default").tag("")
                            ForEach(effortsForSelectedModel, id: \.self) { effort in
                                Text(effort.capitalized).tag(effort)
                            }
                        }
                        .labelsHidden()
                    }
                }

                GridRow {
                    Text("Permissions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)

                    Picker("Permissions", selection: $selectedAccessMode) {
                        Text("Workspace Default").tag("")
                        Text("Ask for Approval").tag("approval")
                        Text("Full Access").tag("fullAccess")
                    }
                    .labelsHidden()
                }

                GridRow {
                    Text("Mode")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)

                    Picker("Mode", selection: $selectedInteractionMode) {
                        Text("Workspace Default").tag("")
                        Text("Build").tag("build")
                        Text("Plan").tag("plan")
                    }
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack(spacing: 10) {
            if editingBot != nil {
                Button("Delete Bot…", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(isSaving)
            }

            Spacer()

            Button("Cancel") {
                closeSheet()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isSaving)

            Button {
                Task { await saveBotDraft() }
            } label: {
                if isSaving {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Saving…")
                    }
                } else {
                    Text(editingBot == nil ? "Create Bot" : "Save Bot")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(trimmedName.isEmpty || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func editorSectionCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.primaryLabel)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
    }

    private func tintSwiftUIColor(_ tint: RemoteBotAvatar.Tint) -> Color {
        let art = BotArtwork.color(tint)
        return Color(
            .sRGB,
            red: Double(art.red),
            green: Double(art.green),
            blue: Double(art.blue),
            opacity: Double(art.alpha)
        )
    }

    private func initializeFromEditingBotIfNeeded() {
        guard !didInitializeState else { return }
        didInitializeState = true

        if let bot = editingBot {
            let char = bot.avatar?.artCharacter ?? .alien
            let tint = bot.avatar?.artTint ?? char.defaultTint
            look = BotEditorLook(character: char, tint: tint, name: bot.name)
            personalityState = BotEditorPersonality(editing: bot.personality)
            persona = bot.persona ?? ""
            selectedProvider = bot.selection?.provider ?? ""
            selectedModelID = bot.selection?.modelID ?? ""
            selectedEffort = bot.selection?.effort ?? ""
            selectedAccessMode = bot.accessMode ?? ""
            selectedInteractionMode = bot.interactionMode ?? ""
        } else {
            let usedCharacters = Set(
                (appModel.workspace.bots ?? []).compactMap { $0.avatar?.artCharacter }
            )
            let initialLook = BotEditorLook.newBot(avoiding: usedCharacters)
            look = initialLook
            personalityState = BotEditorPersonality(
                newBotAs: initialLook.character.rawValue,
                defaultID: BotPersonalityPreset.defaultID(forCharacter:)
            )
            persona = ""
            selectedProvider = ""
            selectedModelID = ""
            selectedEffort = ""
            selectedAccessMode = ""
            selectedInteractionMode = ""
        }
    }

    private func selectCharacter(_ character: RemoteBotAvatar.Character) {
        let previous = look.character.rawValue
        look.pick(character)
        personalityState.suggest(
            for: character.rawValue,
            replacing: previous,
            defaultID: BotPersonalityPreset.defaultID(forCharacter:)
        )
    }

    private func saveBotDraft() async {
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let draft = RemoteBotDraft(
            id: editingBot?.id,
            name: trimmedName,
            avatar: currentAvatar,
            persona: persona.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: selectedProvider.isEmpty ? nil : selectedProvider,
            modelID: (selectedProvider.isEmpty || selectedModelID.isEmpty) ? nil : selectedModelID,
            effort: selectedEffort.isEmpty ? nil : selectedEffort,
            accessMode: selectedAccessMode.isEmpty ? nil : selectedAccessMode,
            interactionMode: selectedInteractionMode.isEmpty ? nil : selectedInteractionMode,
            personality: personalityState.draft
        )

        _ = await appModel.saveBot(draft)
    }

    private func closeSheet() {
        appModel.showBotEditor = false
        appModel.editingBot = nil
    }

    private func runNaturalBlinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(3_600))
            guard !Task.isCancelled else { break }
            withAnimation(.easeInOut(duration: 0.09)) {
                eyeOpenness = 0.12
            }
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { break }
            withAnimation(.easeInOut(duration: 0.11)) {
                eyeOpenness = 1.0
            }
        }
    }
}
