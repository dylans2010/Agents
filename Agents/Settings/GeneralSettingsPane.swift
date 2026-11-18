import AppKit
import CoincideRemoteKit
import SwiftUI

public struct GeneralSettingsPane: View {
    @Bindable public var appModel: AppModel

    @State private var installedEditors: [ExternalAppTarget] = []
    @State private var installedTerminals: [ExternalAppTarget] = []
    @State private var selectedEditorBundleID: String = ""
    @State private var selectedTerminalBundleID: String = ""
    @State private var isImportingLegacy: Bool = false

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var resolvedDataDirectory: String {
        if !appModel.status.dataDir.isEmpty {
            return appModel.status.dataDir
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Coincide")
            .path
    }

    private var generalRemoteSections: [RemoteSettingsSection] {
        guard let page = appModel.settingsSnapshot.page("general") else { return [] }
        return page.sections.compactMap { section in
            let filtered = section.rows.filter { row in
                switch row.kind {
                case .toggle, .choice:
                    // Exclude appearance/serif if already natively bound at top
                    let lower = row.id.lowercased()
                    if lower.contains("appearance") || lower.contains("typeface") || lower.contains("serif") {
                        return false
                    }
                    return true
                case .number:
                    return true
                default:
                    return false
                }
            }
            guard !filtered.isEmpty else { return nil }
            return RemoteSettingsSection(
                id: section.id,
                title: section.title,
                footer: section.footer,
                rows: filtered
            )
        }
    }

    public var body: some View {
        Form {
            appearanceSection
            agentToolsSection
            externalToolsSection
            dynamicEnginePreferencesSections
            storageAndMigrationSection
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear {
            reloadExternalTargets()
        }
        .task {
            if let runtime = appModel.runtime, appModel.settingsSnapshot.pages.isEmpty {
                if let snap = try? await runtime.fetchSettings() {
                    appModel.settingsSnapshot = snap
                }
            }
        }
    }

    // MARK: - 1. Appearance & Reading

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appModel.appearancePreference) {
                ForEach(AppearancePreference.allCases) { pref in
                    Label(pref.title, systemImage: pref.symbolName)
                        .tag(pref)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Font Scale") {
                HStack(spacing: 10) {
                    Slider(value: $appModel.fontScale, in: 0.8...1.5, step: 0.05)
                        .frame(minWidth: 140, idealWidth: 200, maxWidth: 260)

                    Text("\(Int((appModel.fontScale * 100).rounded()))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .frame(width: 44, alignment: .trailing)

                    Button("Reset") {
                        appModel.resetFontScale()
                    }
                    .controlSize(.small)
                    .disabled(abs(appModel.fontScale - 1.0) < 0.01)
                }
            }

            Toggle("Use New York Serif for Assistant Replies", isOn: $appModel.usesSerifReplies)
        } header: {
            Text("Appearance & Reading")
        } footer: {
            Text("Scales conversation typography, diffs, and the integrated PTY terminal across all Agents windows.")
        }
    }

    // MARK: - 2. External Tools

    private var agentToolsSection: some View {
        Section {
            Picker("Agent Tools", selection: $appModel.agentToolset) {
                ForEach(AgentToolset.allCases, id: \.self) { toolset in
                    Text(toolset.title).tag(toolset)
                }
            }
            .pickerStyle(.segmented)

            Text(appModel.agentToolset.detail)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryLabel)
        } header: {
            Text("Agent Tools")
        } footer: {
            Text("Applies to new conversations. Existing conversations keep the toolset they were created with. System Tools delivers the Agents system prompt to Codex and Claude. For Codex the prompt is the whole mechanism: the MCP server is not mounted for Codex sessions. OpenCode and Lithos report an error instead of silently dropping it, and switching an existing System Tools conversation to either of them is refused at the switch. In Provider Tools mode, Assistant permission profiles are not enforced. Cursor, Grok Build, Antigravity, and registered ACP agents get no injected prompt; they run only if their CLI fetches the MCP prompt, which this app cannot verify.")
        }
    }

    private var externalToolsSection: some View {
        Section {
            if installedEditors.isEmpty {
                LabeledContent("Preferred External Editor") {
                    Text("No supported editors found in /Applications")
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            } else {
                Picker("Preferred External Editor", selection: $selectedEditorBundleID) {
                    ForEach(installedEditors) { editor in
                        Label {
                            Text(editor.name)
                        } icon: {
                            Image(nsImage: editor.icon)
                        }
                        .tag(editor.id)
                    }
                }
                .onChange(of: selectedEditorBundleID) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    appModel.externalEditors.setPreferredEditor(newValue)
                }
            }

            if installedTerminals.isEmpty {
                LabeledContent("Preferred External Terminal") {
                    Text("Terminal.app")
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            } else {
                Picker("Preferred External Terminal", selection: $selectedTerminalBundleID) {
                    ForEach(installedTerminals) { terminal in
                        Label {
                            Text(terminal.name)
                        } icon: {
                            Image(nsImage: terminal.icon)
                        }
                        .tag(terminal.id)
                    }
                }
                .onChange(of: selectedTerminalBundleID) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    appModel.externalEditors.setPreferredTerminal(newValue)
                }
            }

            HStack {
                Spacer()
                Button {
                    reloadExternalTargets()
                } label: {
                    Label("Rescan Applications", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        } header: {
            Text("External Tools")
        } footer: {
            Text("Used when opening workspace files at exact line numbers or launching an external shell.")
        }
    }

    // MARK: - 3. Dynamic Engine Preferences (if surfaced by RemoteSettingsSnapshot)

    @ViewBuilder
    private var dynamicEnginePreferencesSections: some View {
        ForEach(generalRemoteSections) { section in
            Section {
                ForEach(section.rows) { row in
                    remoteSettingRowView(row)
                }
            } header: {
                Text(section.title ?? "Conversation & Engine")
            } footer: {
                if let footer = section.footer, !footer.isEmpty {
                    Text(footer)
                }
            }
        }
    }

    @ViewBuilder
    private func remoteSettingRowView(_ row: RemoteSettingsRow) -> some View {
        switch row.kind {
        case .toggle:
            let current = row.value?.bool ?? false
            Toggle(
                isOn: Binding(
                    get: { current },
                    set: { newValue in
                        Task { await updateEngineSetting(id: row.id, value: .bool(newValue)) }
                    }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                    if let detail = row.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
            }
            .disabled(row.isEnabled == false)

        case .choice:
            let options = row.options ?? []
            let current = row.value?.string ?? options.first?.id ?? ""
            Picker(
                row.title,
                selection: Binding(
                    get: { current },
                    set: { newValue in
                        Task { await updateEngineSetting(id: row.id, value: .string(newValue)) }
                    }
                )
            ) {
                ForEach(options) { opt in
                    Text(opt.title).tag(opt.id)
                }
            }
            .disabled(row.isEnabled == false)

        case .number:
            let current = Int(row.value?.number ?? row.minimum ?? 0)
            let minimum = Int(row.minimum ?? 0)
            let maximum = Int(row.maximum ?? 500)
            let step = max(1, Int(row.step ?? 1))
            Stepper(
                value: Binding(
                    get: { current },
                    set: { newValue in
                        Task { await updateEngineSetting(id: row.id, value: .number(Double(newValue))) }
                    }
                ),
                in: minimum...maximum,
                step: step
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(row.title): \(current)")
                    if let detail = row.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
            }
            .disabled(row.isEnabled == false)

        default:
            EmptyView()
        }
    }

    // MARK: - 4. Engine & Workspace Storage

    private var storageAndMigrationSection: some View {
        Section {
            LabeledContent("Data Store") {
                HStack(spacing: 8) {
                    Text(resolvedDataDirectory)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Button("Reveal in Finder") {
                        appModel.externalEditors.revealInFinder(path: resolvedDataDirectory)
                    }
                    .controlSize(.small)
                }
            }

            LabeledContent("Migrate Workspace") {
                HStack(spacing: 8) {
                    if appModel.status.legacyImportAvailable {
                        Text("Legacy store detected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.info)
                    }

                    Button {
                        Task {
                            isImportingLegacy = true
                            defer { isImportingLegacy = false }
                            await appModel.importLegacyWorkspace()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isImportingLegacy {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Import Existing Agents Workspace")
                        }
                    }
                    .controlSize(.small)
                    .disabled(isImportingLegacy)

                    Button("Choose Folder…") {
                        chooseCustomLegacyDirectory()
                    }
                    .controlSize(.small)
                    .disabled(isImportingLegacy)
                }
            }
        } header: {
            Text("Engine & Workspace Storage")
        } footer: {
            Text("All threads, transcripts, project defaults, and schedules are stored locally on your Mac inside coincide-core.")
        }
    }

    // MARK: - Helpers

    private func reloadExternalTargets() {
        let editors = appModel.externalEditors.installedEditors
        let terminals = appModel.externalEditors.installedTerminals
        self.installedEditors = editors
        self.installedTerminals = terminals
        self.selectedEditorBundleID = appModel.externalEditors.preferredEditor?.id ?? editors.first?.id ?? ""
        self.selectedTerminalBundleID = appModel.externalEditors.preferredTerminal?.id ?? terminals.first?.id ?? ""
    }

    private func updateEngineSetting(id: String, value: RemoteSettingValue) async {
        guard let runtime = appModel.runtime else { return }
        do {
            appModel.settingsSnapshot = try await runtime.changeSetting(id: id, value: value)
            await appModel.refreshWorkspace()
        } catch {
            appModel.presentError(error)
        }
    }

    private func chooseCustomLegacyDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Select Existing Agents Data Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let runtime = appModel.runtime else { return }
        Task {
            isImportingLegacy = true
            defer { isImportingLegacy = false }
            do {
                let report = try await runtime.importLegacyWorkspace(sourceDir: url.path)
                await appModel.refreshWorkspace()
                appModel.presentToast(
                    "Workspace Imported",
                    detail: "\(report.importedProjects) projects, \(report.importedThreads) threads, \(report.importedBots) bots",
                    style: .success
                )
            } catch {
                appModel.presentError(error)
            }
        }
    }
}
