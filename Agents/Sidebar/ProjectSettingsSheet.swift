import AppKit
import CoincideRemoteKit
import SwiftUI

public struct ProjectSettingsSheet: View {
    @Bindable public var appModel: AppModel
    public let project: RemoteProject
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false

    // Project Defaults State
    @State private var usesGlobalDefaults: Bool = true
    @State private var selectedProvider: String = "antigravity"
    @State private var selectedModelID: String = ""
    @State private var selectedEffort: String = ""
    @State private var accessMode: String = "approval"
    @State private var interactionMode: String = "build"

    // Project Scripts State
    @State private var scripts: [RemoteScript] = []

    public init(appModel: AppModel, project: RemoteProject) {
        self.appModel = appModel
        self.project = project
    }

    public nonisolated static func symbolName(forScriptIcon icon: String) -> String {
        switch icon.lowercased() {
        case "play": "play.fill"
        case "test": "checkmark.diamond.fill"
        case "lint": "wand.and.stars"
        case "configure": "gearshape.2.fill"
        case "build": "hammer.fill"
        case "debug": "ladybug.fill"
        default: "terminal.fill"
        }
    }

    private static let scriptIconChoices: [(id: String, label: String)] = [
        ("play", "Run"),
        ("build", "Build"),
        ("test", "Test"),
        ("lint", "Lint"),
        ("debug", "Debug"),
        ("configure", "Configure"),
    ]

    private nonisolated struct ProviderOption: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let models: [ModelOption]
    }

    private nonisolated struct ModelOption: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let efforts: [String]
        let defaultEffort: String?
    }

    private var availableProviders: [ProviderOption] {
        if !appModel.providers.isEmpty {
            return appModel.providers
                .filter { $0.isEnabled }
                .map { p in
                    let visibleModels = p.models.filter(\.isVisible).map { m in
                        ModelOption(
                            id: m.id,
                            name: m.name,
                            efforts: m.efforts,
                            defaultEffort: m.defaultEffort
                        )
                    }
                    return ProviderOption(
                        id: p.id,
                        name: p.displayName,
                        models: visibleModels
                    )
                }
        }
        if !appModel.workspace.providers.isEmpty {
            return appModel.workspace.providers.map { p in
                ProviderOption(
                    id: p.id,
                    name: p.name,
                    models: p.models.map { m in
                        ModelOption(
                            id: m.id,
                            name: m.name,
                            efforts: m.efforts,
                            defaultEffort: m.defaultEffort
                        )
                    }
                )
            }
        }
        return [
            ProviderOption(id: "antigravity", name: "Antigravity", models: []),
            ProviderOption(id: "claude", name: "Claude Code", models: []),
            ProviderOption(id: "codex", name: "Codex", models: []),
        ]
    }

    private var modelsForSelectedProvider: [ModelOption] {
        availableProviders.first(where: { $0.id == selectedProvider })?.models ?? []
    }

    private var effortsForSelectedModel: [String] {
        modelsForSelectedProvider.first(where: { $0.id == selectedModelID })?.efforts ?? []
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading project configuration…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    newThreadDefaultsSection
                    projectScriptsSection
                }
                .formStyle(.grouped)
            }

            Divider()

            footerBar
        }
        .frame(minWidth: 540, idealWidth: 600, maxWidth: 680, minHeight: 480, idealHeight: 560, maxHeight: 680)
        .background(AppTheme.windowBackground)
        .task {
            await loadProjectConfiguration()
        }
    }

    // MARK: - Header & Footer

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill.badge.gearshape")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(project.name) — Defaults & Scripts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Text(project.path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                appModel.externalEditors.revealInFinder(path: project.path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Reveal Project Folder in Finder")
            .accessibilityLabel("Reveal project folder in Finder")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Text("\(scripts.count) script\(scripts.count == 1 ? "" : "s") configured")
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.tertiaryLabel)

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                Task { await saveConfiguration() }
            } label: {
                if isSaving {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Saving…")
                    }
                } else {
                    Text("Save Changes")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Sections

    @ViewBuilder
    private var newThreadDefaultsSection: some View {
        Section {
            Toggle("Use Global Defaults from Settings", isOn: $usesGlobalDefaults)

            if !usesGlobalDefaults {
                Picker("Default Agent", selection: $selectedProvider) {
                    ForEach(availableProviders) { provider in
                        HStack(spacing: 6) {
                            AgentLogoView(provider: provider.id, size: 14)
                            Text(provider.name)
                        }
                        .tag(provider.id)
                    }
                }
                .onChange(of: selectedProvider) { _, newProvider in
                    let providerModels = availableProviders.first(where: { $0.id == newProvider })?.models ?? []
                    if !providerModels.contains(where: { $0.id == selectedModelID }) {
                        selectedModelID = providerModels.first?.id ?? ""
                        selectedEffort = providerModels.first?.defaultEffort ?? ""
                    }
                }

                if !modelsForSelectedProvider.isEmpty {
                    Picker("Default Model", selection: $selectedModelID) {
                        Text("Provider Default").tag("")
                        ForEach(modelsForSelectedProvider) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .onChange(of: selectedModelID) { _, newModelID in
                        if let model = modelsForSelectedProvider.first(where: { $0.id == newModelID }) {
                            if !model.efforts.contains(selectedEffort) {
                                selectedEffort = model.defaultEffort ?? ""
                            }
                        } else {
                            selectedEffort = ""
                        }
                    }
                } else {
                    TextField("Custom Model ID (optional)", text: $selectedModelID)
                }

                if !effortsForSelectedModel.isEmpty {
                    Picker("Reasoning Effort", selection: $selectedEffort) {
                        Text("Default").tag("")
                        ForEach(effortsForSelectedModel, id: \.self) { effort in
                            Text(effort.capitalized).tag(effort)
                        }
                    }
                }

                Picker("Permissions", selection: $accessMode) {
                    Text("Ask for Approval").tag("approval")
                    Text("Full Access").tag("fullAccess")
                }

                Picker("Interaction Mode", selection: $interactionMode) {
                    Text("Build").tag("build")
                    Text("Plan").tag("plan")
                }
            }
        } header: {
            Text("New Thread Defaults")
        } footer: {
            Text("Controls which agent, model, and permission level new threads in \(project.name) start with.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
    }

    @ViewBuilder
    private var projectScriptsSection: some View {
        Section {
            if scripts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No scripts configured for this project.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.secondaryLabel)

                    HStack(spacing: 8) {
                        Button {
                            appendNewScript(name: "Build", command: "", icon: "build")
                        } label: {
                            Label("Add Build Script", systemImage: "hammer")
                        }
                        .controlSize(.small)

                        Button {
                            appendNewScript(name: "Test", command: "", icon: "test")
                        } label: {
                            Label("Add Test Script", systemImage: "checkmark.diamond")
                        }
                        .controlSize(.small)

                        Button {
                            appendNewScript(name: "Run", command: "", icon: "play")
                        } label: {
                            Label("Add Run Script", systemImage: "play")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ForEach($scripts) { $script in
                    scriptEditorRow(script: $script)
                }
            }

            HStack {
                Button {
                    appendNewScript(name: "Run", command: "", icon: "play")
                } label: {
                    Label("Add Script", systemImage: "plus")
                }
                .controlSize(.small)
                Spacer()
            }
        } header: {
            Text("Project Scripts")
        } footer: {
            Text("Scripts run directly in the integrated PTY terminal inside the active thread's working directory.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
    }

    @ViewBuilder
    private func scriptEditorRow(script: Binding<RemoteScript>) -> some View {
        let currentID = script.wrappedValue.id
        let index = scripts.firstIndex(where: { $0.id == currentID }) ?? 0

        HStack(spacing: 8) {
            Menu {
                ForEach(Self.scriptIconChoices, id: \.id) { item in
                    Button {
                        script.wrappedValue.icon = item.id
                    } label: {
                        Label(item.label, systemImage: Self.symbolName(forScriptIcon: item.id))
                    }
                }
            } label: {
                Image(systemName: Self.symbolName(forScriptIcon: script.wrappedValue.icon))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .help("Script Icon")
            .accessibilityLabel("Script icon, currently \(script.wrappedValue.icon)")

            TextField("Name", text: script.name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 100, idealWidth: 130, maxWidth: 180)

            TextField("Shell command (e.g. swift test)", text: script.command)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            HStack(spacing: 2) {
                Button {
                    guard index > 0 else { return }
                    scripts.swapAt(index, index - 1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help("Move Up")
                .accessibilityLabel("Move script up")

                Button {
                    guard index + 1 < scripts.count else { return }
                    scripts.swapAt(index, index + 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(index + 1 >= scripts.count)
                .help("Move Down")
                .accessibilityLabel("Move script down")

                Button(role: .destructive) {
                    scripts.removeAll { $0.id == currentID }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.danger)
                }
                .buttonStyle(.borderless)
                .help("Remove Script")
                .accessibilityLabel("Remove script \(script.wrappedValue.name.isEmpty ? "unnamed" : script.wrappedValue.name)")
            }
        }
        .padding(.vertical, 2)
    }

    private func appendNewScript(name: String, command: String, icon: String) {
        scripts.append(RemoteScript(id: UUID(), name: name, command: command, icon: icon))
    }

    // MARK: - Data Loading & Saving

    private func loadProjectConfiguration() async {
        isLoading = true
        defer { isLoading = false }

        scripts = project.scripts
        if appModel.providers.isEmpty {
            await appModel.refreshProviders()
        }

        if let client = appModel.runtime,
           let defaults = try? await client.fetchProjectDefaults(projectID: project.id)
        {
            usesGlobalDefaults = defaults.usesGlobalDefaults
            selectedProvider = defaults.provider.isEmpty
                ? (availableProviders.first?.id ?? "antigravity")
                : defaults.provider
            selectedModelID = defaults.modelID
            selectedEffort = defaults.effort ?? ""
            accessMode = defaults.accessMode.isEmpty ? "approval" : defaults.accessMode
            interactionMode = defaults.interactionMode.isEmpty ? "build" : defaults.interactionMode
        } else if let firstProvider = availableProviders.first {
            selectedProvider = firstProvider.id
            selectedModelID = firstProvider.models.first?.id ?? ""
            selectedEffort = firstProvider.models.first?.defaultEffort ?? ""
        }
    }

    private func saveConfiguration() async {
        guard let client = appModel.runtime else {
            dismiss()
            return
        }
        isSaving = true
        defer { isSaving = false }

        let cleanedScripts = scripts.compactMap { script -> RemoteScript? in
            let cmd = script.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmd.isEmpty else { return nil }
            let trimmedName = script.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return RemoteScript(
                id: script.id,
                name: trimmedName.isEmpty ? cmd : trimmedName,
                command: cmd,
                icon: script.icon.isEmpty ? "play" : script.icon
            )
        }

        let defaultsPayload = RemoteProjectDefaults(
            projectID: project.id,
            usesGlobalDefaults: usesGlobalDefaults,
            provider: selectedProvider,
            modelID: selectedModelID,
            effort: selectedEffort.isEmpty ? nil : selectedEffort,
            accessMode: accessMode,
            interactionMode: interactionMode
        )

        do {
            _ = try await client.saveProjectDefaults(defaultsPayload)
            try await client.saveProjectScripts(projectID: project.id.uuidString, scripts: cleanedScripts)
            await appModel.refreshWorkspace()
            appModel.presentToast("Saved Project Settings", detail: project.name, style: .success)
            dismiss()
        } catch {
            appModel.presentError(error)
        }
    }
}
