import AppKit
import CoincideRemoteKit
import SwiftUI

public struct ProvidersSettingsPane: View {
    @Bindable public var appModel: AppModel

    private enum ProvidersSectionMode: String, CaseIterable, Identifiable {
        case configured = "Coding Agents"
        case registry = "ACP Agent Registry"
        var id: String { rawValue }
    }

    @State private var mode: ProvidersSectionMode = .configured
    @State private var selectedProviderID: String = "claude"

    // Provider Config Drafts
    @State private var executableDraft: String = ""
    @State private var envPairs: [EnvPair] = []
    @State private var probeResult: ProviderProbeResult?
    @State private var isProbing: Bool = false
    @State private var isSavingConfig: Bool = false

    // Add Key Account Drafts
    @State private var newKeyAccountName: String = ""
    @State private var newKeyEnvName: String = ""
    @State private var newKeySecret: String = ""
    @State private var isAddingKey: Bool = false
    @State private var updatingKeyAccount: ProviderKeyAccountInfo?
    @State private var updatedSecretText: String = ""

    // Add Login Profile Drafts
    @State private var newLoginProfileName: String = ""
    @State private var isCreatingProfile: Bool = false

    // ACP Registry State
    @State private var registrySearch: String = ""
    @State private var showInstalledOnly: Bool = false
    @State private var isRefreshingRegistry: Bool = false
    @State private var registeringAgentIDs: Set<String> = []

    private struct EnvPair: Identifiable, Equatable {
        let id: UUID
        var key: String
        var value: String

        init(id: UUID = UUID(), key: String = "", value: String = "") {
            self.id = id
            self.key = key
            self.value = value
        }
    }

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var listedProviders: [DesktopProviderInfo] {
        appModel.providers.filter { $0.id != "antigravity" }
    }

    private var selectedProvider: DesktopProviderInfo? {
        listedProviders.first(where: { $0.id == selectedProviderID }) ?? listedProviders.first
    }

    private var filteredRegistryAgents: [ACPRegistryAgentInfo] {
        let q = registrySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appModel.acpRegistry.filter { agent in
            if showInstalledOnly && !agent.isInstalled && !agent.isRegistered {
                return false
            }
            guard !q.isEmpty else { return true }
            return agent.name.lowercased().contains(q)
                || agent.id.lowercased().contains(q)
                || (agent.description?.lowercased().contains(q) ?? false)
                || (agent.executable?.lowercased().contains(q) ?? false)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            topModeHeader
            Divider()

            switch mode {
            case .configured:
                configuredAgentsSplitView
            case .registry:
                acpRegistryView
            }
        }
        .navigationTitle("Providers")
        .task {
            await appModel.refreshProviders()
            if selectedProvider == nil, let first = listedProviders.first {
                selectedProviderID = first.id
            }
            loadDrafts(from: selectedProvider)
            if appModel.acpRegistry.isEmpty {
                await appModel.refreshACPRegistry(force: false)
            }
        }
        .onChange(of: selectedProviderID) { _, _ in
            probeResult = nil
            loadDrafts(from: selectedProvider)
        }
        .sheet(item: $updatingKeyAccount) { account in
            updateKeySheet(account)
        }
    }

    // MARK: - Top Segmented Bar

    private var topModeHeader: some View {
        HStack(spacing: 12) {
            Picker("", selection: $mode) {
                ForEach(ProvidersSectionMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Providers section")
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)

            Spacer()

            Button {
                appModel.selectedSettingsTab = .antigravity
            } label: {
                HStack(spacing: 5) {
                    AgentLogoView(provider: "antigravity", size: 13)
                    Text("Configure Antigravity…")
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.controlBackground)
    }

    // MARK: - Tab 1: Built-in & Registered Coding Agents

    private var configuredAgentsSplitView: some View {
        HSplitView {
            // Left Provider Roster
            List(selection: $selectedProviderID) {
                Section("Built-in Agents") {
                    ForEach(listedProviders.filter { !$0.isACP }) { provider in
                        providerSidebarRow(provider)
                            .tag(provider.id)
                    }
                }

                let acpProviders = listedProviders.filter(\.isACP)
                if !acpProviders.isEmpty {
                    Section("Registered ACP Agents") {
                        ForEach(acpProviders) { provider in
                            providerSidebarRow(provider)
                                .tag(provider.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 215, maxWidth: 260)

            // Right Provider Detail Form
            if let provider = selectedProvider {
                Form {
                    providerHeaderSection(provider)
                    executableSection(provider)
                    if provider.supportsAPIKeyAccounts || !provider.keyChoices.isEmpty || !provider.keyAccounts.isEmpty {
                        apiKeyAccountsSection(provider)
                    }
                    if provider.supportsLoginAccounts || !provider.loginAccounts.isEmpty {
                        loginProfilesSection(provider)
                    }
                    environmentVariablesSection(provider)
                }
                .formStyle(.grouped)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Providers Available",
                    systemImage: "cpu",
                    description: Text("Wait for the Agents runtime to finish loading providers.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func providerSidebarRow(_ provider: DesktopProviderInfo) -> some View {
        HStack(spacing: 8) {
            AgentLogoView(provider: provider.id, size: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(providerStatusText(provider))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryLabel)
            }

            Spacer(minLength: 4)

            Circle()
                .fill(providerStatusTint(provider))
                .frame(width: 7, height: 7)
        }
        .padding(.vertical, 2)
    }

    private func providerHeaderSection(_ provider: DesktopProviderInfo) -> some View {
        Section {
            HStack(spacing: 12) {
                AgentLogoView(provider: provider.id, size: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(provider.displayName)
                            .font(.system(size: 15, weight: .semibold))

                        Text(providerStatusText(provider))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(providerStatusTint(provider))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(providerStatusTint(provider).opacity(0.14))
                            )
                    }

                    Text(provider.isACP ? "ACP Protocol Agent (\(provider.id))" : "Native CLI Coding Agent (\(provider.id))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }

                Spacer()

                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { provider.isEnabled },
                        set: { newEnabled in
                            Task { await setProviderEnabled(provider, enabled: newEnabled) }
                        }
                    )
                )
                .toggleStyle(.switch)

                Button {
                    Task { await verifyProvider(provider) }
                } label: {
                    HStack(spacing: 5) {
                        if isProbing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text("Verify CLI")
                    }
                }
                .controlSize(.small)
                .disabled(isProbing)
            }

            if let probe = probeResult, probe.provider.isEmpty || probe.provider == provider.id {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: probe.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(probe.ok ? AppTheme.success : AppTheme.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(probe.ok ? "CLI Ready" : "CLI Check Reported an Issue")
                            .font(.system(size: 12, weight: .semibold))
                        if let version = probe.version, !version.isEmpty {
                            Text("Version: \(version)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        if let msg = probe.message, !msg.isEmpty {
                            Text(msg)
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    private func executableSection(_ provider: DesktopProviderInfo) -> some View {
        Section {
            if !provider.candidateExecutables.isEmpty {
                Picker("Discovered CLI", selection: $executableDraft) {
                    ForEach(provider.candidateExecutables, id: \.self) { path in
                        Text(path).tag(path)
                    }
                    if !executableDraft.isEmpty && !provider.candidateExecutables.contains(executableDraft) {
                        Text(executableDraft).tag(executableDraft)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Executable path (e.g. /opt/homebrew/bin/\(provider.id))", text: $executableDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))

                Button("Browse…") {
                    browseForExecutable(for: provider)
                }
                .controlSize(.small)

                Button("Save & Approve") {
                    Task { await saveExecutableAndEnvironment(for: provider) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(executableDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingConfig)
            }

            if !provider.setupCommands.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Setup & Installation Commands")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)

                    ForEach(provider.setupCommands) { cmd in
                        HStack(spacing: 8) {
                            Text(cmd.label)
                                .font(.system(size: 11.5, weight: .medium))
                            Text(cmd.command)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer()
                            Button("Run in Terminal") {
                                runShellInExternalOrIntegratedTerminal(cmd.command)
                            }
                            .controlSize(.mini)
                        }
                    }
                }
            }
        } header: {
            Text("Executable Path")
        } footer: {
            if let approved = provider.approvedExecutable {
                Text("Approved binary: \(approved)")
            } else {
                Text("Save & Approve pins the binary SHA-256 baseline so Agents never runs tampered binaries silently.")
            }
        }
    }

    private func apiKeyAccountsSection(_ provider: DesktopProviderInfo) -> some View {
        Section {
            if provider.keyAccounts.isEmpty {
                Text("No API key accounts stored in Keychain for \(provider.displayName).")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
            } else {
                ForEach(provider.keyAccounts) { account in
                    HStack(spacing: 10) {
                        Image(systemName: account.hasKey ? "key.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(account.hasKey ? AppTheme.success : AppTheme.warning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.system(size: 12.5, weight: .medium))
                            if let envVar = account.keyVariable {
                                Text(envVar)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(AppTheme.tertiaryLabel)
                            }
                        }

                        Spacer()

                        Button("Update Key…") {
                            updatedSecretText = ""
                            updatingKeyAccount = account
                        }
                        .controlSize(.small)

                        Button(role: .destructive) {
                            Task { await deleteAccount(provider: provider.id, accountID: account.id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Delete API key account \(account.name)")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Add Keychain API Key")
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 8) {
                    TextField("Account Name", text: $newKeyAccountName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 120, idealWidth: 150, maxWidth: 190)

                    if provider.keyChoices.count > 1 {
                        Picker("", selection: $newKeyEnvName) {
                            ForEach(provider.keyChoices) { choice in
                                Text(choice.envName).tag(choice.envName)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("API key environment variable")
                        .frame(minWidth: 140, idealWidth: 170, maxWidth: 210)
                    }

                    SecureField("Paste \(resolvedKeyEnvName(for: provider))…", text: $newKeySecret)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))

                    Button("Add Key") {
                        Task { await addKeyAccount(for: provider) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        newKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isAddingKey
                    )
                }
            }
            .padding(.top, 4)
        } header: {
            Text("API Key Accounts (macOS Keychain)")
        }
    }

    private func loginProfilesSection(_ provider: DesktopProviderInfo) -> some View {
        Section {
            if provider.loginAccounts.isEmpty {
                Text("No isolated CLI login profiles yet. Create one to sign into \(provider.displayName) with a dedicated home directory.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
            } else {
                ForEach(provider.loginAccounts) { profile in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: profile.isReady ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                                .foregroundStyle(profile.isReady ? AppTheme.success : AppTheme.secondaryLabel)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                if let home = profile.homePath {
                                    Text(home)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(AppTheme.tertiaryLabel)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            Spacer()

                            if let loginCmd = profile.loginCommand, !loginCmd.isEmpty {
                                Button("Sign In in External Terminal") {
                                    launchLoginInExternalTerminal(command: loginCmd)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Button(role: .destructive) {
                                Task { await deleteAccount(provider: provider.id, accountID: profile.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .controlSize(.small)
                            .accessibilityLabel("Delete login profile \(profile.name)")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 8) {
                TextField("Profile Name (e.g. Work, Personal)", text: $newLoginProfileName)
                    .textFieldStyle(.roundedBorder)

                Button("Create Login Profile") {
                    Task { await createLoginProfile(for: provider) }
                }
                .controlSize(.small)
                .disabled(
                    newLoginProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isCreatingProfile
                )
            }
            .padding(.top, 4)
        } header: {
            Text("Isolated Login Profiles")
        } footer: {
            Text("Each profile isolates credentials in its own directory (e.g. CLAUDE_CONFIG_DIR or CODEX_HOME) so you can switch accounts per conversation.")
        }
    }

    private func environmentVariablesSection(_ provider: DesktopProviderInfo) -> some View {
        Section {
            if envPairs.isEmpty {
                Text("No custom environment variables configured.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
            } else {
                ForEach($envPairs) { $pair in
                    HStack(spacing: 8) {
                        TextField("KEY", text: $pair.key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(minWidth: 140, idealWidth: 180, maxWidth: 240)

                        TextField("Value", text: $pair.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))

                        Button(role: .destructive) {
                            envPairs.removeAll { $0.id == pair.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(AppTheme.danger)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove environment variable \(pair.key.isEmpty ? "row" : pair.key)")
                    }
                }
            }

            HStack {
                Button {
                    envPairs.append(EnvPair())
                } label: {
                    Label("Add Variable", systemImage: "plus")
                }
                .controlSize(.small)

                Spacer()

                Button("Save Environment") {
                    Task { await saveExecutableAndEnvironment(for: provider) }
                }
                .controlSize(.small)
                .disabled(isSavingConfig)
            }
        } header: {
            Text("Environment Variables")
        }
    }

    // MARK: - Tab 2: ACP Agent Registry (46+ Agents)

    private var acpRegistryView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.secondaryLabel)
                    TextField("Search 46+ ACP agents (Gemini CLI, Devin, Copilot, Kiro, Cline, Goose, Qwen…)", text: $registrySearch)
                        .textFieldStyle(.plain)
                    if !registrySearch.isEmpty {
                        Button {
                            registrySearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.tertiaryLabel)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear agent search")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .fill(AppTheme.textBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .strokeBorder(AppTheme.separator, lineWidth: 1)
                )

                Toggle("Installed Only", isOn: $showInstalledOnly)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Button {
                    Task {
                        isRefreshingRegistry = true
                        defer { isRefreshingRegistry = false }
                        await appModel.refreshACPRegistry(force: true)
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isRefreshingRegistry {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh Registry")
                    }
                }
                .controlSize(.small)
                .disabled(isRefreshingRegistry)
            }
            .padding(12)
            .background(AppTheme.controlBackground)

            Divider()

            if filteredRegistryAgents.isEmpty {
                ContentUnavailableView(
                    registrySearch.isEmpty ? "ACP Registry Loading" : "No Matching ACP Agents",
                    systemImage: "puzzlepiece.extension",
                    description: Text(
                        registrySearch.isEmpty
                            ? "Click Refresh Registry to fetch the latest Agent Client Protocol catalog."
                            : "Try searching by agent name or binary executable."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredRegistryAgents) { agent in
                    acpRegistryRow(agent)
                }
                .listStyle(.inset)
            }
        }
    }

    private func acpRegistryRow(_ agent: ACPRegistryAgentInfo) -> some View {
        let isBusy = registeringAgentIDs.contains(agent.id)
        return HStack(alignment: .center, spacing: 12) {
            AgentLogoView(provider: agent.providerID, size: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .semibold))

                    if agent.isInstalled {
                        badge("Installed", tint: AppTheme.success)
                    } else {
                        badge("Not Found on PATH", tint: AppTheme.secondaryLabel)
                    }

                    if agent.isRegistered {
                        badge("Enabled in Agents", tint: AppTheme.info)
                    }
                }

                if let desc = agent.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    if let exec = agent.executable, !exec.isEmpty {
                        let cmdPreview = ([exec] + agent.arguments).joined(separator: " ")
                        Text(cmdPreview)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .lineLimit(1)
                    }
                    if let site = agent.website, let url = URL(string: site) {
                        Link("Website ↗", destination: url)
                            .font(.system(size: 10.5))
                    }
                }
            }

            Spacer()

            if agent.isRegistered {
                Button("Configure") {
                    selectedProviderID = agent.providerID
                    mode = .configured
                }
                .controlSize(.small)
            } else {
                Button {
                    Task {
                        registeringAgentIDs.insert(agent.id)
                        defer { registeringAgentIDs.remove(agent.id) }
                        await appModel.registerACPAgent(agent.id)
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Enable in Agents")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isBusy)
            }
        }
        .padding(.vertical, 4)
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                Capsule()
                    .fill(tint.opacity(0.14))
            )
    }

    // MARK: - Sheet

    private func updateKeySheet(_ account: ProviderKeyAccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Update API Key — \(account.name)")
                .font(.headline)

            SecureField("Paste new API key…", text: $updatedSecretText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            HStack {
                Spacer()
                Button("Cancel") {
                    updatingKeyAccount = nil
                }
                Button("Update Key") {
                    let providerID = account.provider.isEmpty ? (selectedProvider?.id ?? "") : account.provider
                    let accountID = account.id
                    let secret = updatedSecretText.trimmingCharacters(in: .whitespacesAndNewlines)
                    updatingKeyAccount = nil
                    Task { await updateAccountSecret(provider: providerID, accountID: accountID, secret: secret) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(updatedSecretText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 460)
    }

    // MARK: - Helpers & Runtime Calls

    private func loadDrafts(from provider: DesktopProviderInfo?) {
        guard let provider else {
            executableDraft = ""
            envPairs = []
            return
        }
        executableDraft = provider.approvedExecutable
            ?? provider.configuredExecutable
            ?? provider.effectiveExecutable
            ?? provider.candidateExecutables.first
            ?? ""
        envPairs = provider.environment
            .keys
            .sorted()
            .map { EnvPair(key: $0, value: provider.environment[$0] ?? "") }
        newKeyEnvName = provider.keyChoices.first?.envName
            ?? provider.defaultKeyVariable
            ?? DesktopProviderInfo.inferredKeyVariable(for: provider.id)
            ?? "API_KEY"
        if newKeyAccountName.isEmpty {
            newKeyAccountName = "Default Key"
        }
    }

    private func resolvedKeyEnvName(for provider: DesktopProviderInfo) -> String {
        if !newKeyEnvName.isEmpty { return newKeyEnvName }
        return provider.keyChoices.first?.envName
            ?? provider.defaultKeyVariable
            ?? DesktopProviderInfo.inferredKeyVariable(for: provider.id)
            ?? "API_KEY"
    }

    private func providerStatusText(_ provider: DesktopProviderInfo) -> String {
        if !provider.isEnabled { return "Disabled" }
        switch provider.state.lowercased() {
        case "ready": return "Ready"
        case "notinstalled": return "Not Installed"
        case "attention": return provider.isApproved ? "Needs Auth" : "Needs Approval"
        default:
            return provider.isApproved ? "Ready" : (provider.isInstalled ? "Needs Approval" : "Not Installed")
        }
    }

    private func providerStatusTint(_ provider: DesktopProviderInfo) -> Color {
        if !provider.isEnabled { return AppTheme.tertiaryLabel }
        switch provider.state.lowercased() {
        case "ready": return AppTheme.success
        case "notinstalled": return AppTheme.danger
        default: return AppTheme.warning
        }
    }

    private func browseForExecutable(for provider: DesktopProviderInfo) {
        let panel = NSOpenPanel()
        panel.title = "Select \(provider.displayName) Executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            executableDraft = url.path
        }
    }

    private func setProviderEnabled(_ provider: DesktopProviderInfo, enabled: Bool) async {
        guard let runtime = appModel.runtime else { return }
        do {
            _ = try await runtime.saveProviderConfig(provider: provider.id, enabled: enabled)
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
        } catch {
            appModel.presentError(error)
        }
    }

    private func saveExecutableAndEnvironment(for provider: DesktopProviderInfo) async {
        guard let runtime = appModel.runtime else { return }
        isSavingConfig = true
        defer { isSavingConfig = false }

        var envMap: [String: String] = [:]
        for pair in envPairs {
            let k = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty {
                envMap[k] = pair.value
            }
        }
        let exec = executableDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedExec: String? = exec.isEmpty ? nil : ExternalEditorService.expandedPath(exec)

        do {
            _ = try await runtime.saveProviderConfig(
                provider: provider.id,
                executable: resolvedExec,
                environment: envMap,
                enabled: provider.isEnabled
            )
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
            loadDrafts(from: selectedProvider)
            appModel.presentToast("Saved \(provider.displayName)", style: .success)
        } catch {
            appModel.presentError(error)
        }
    }

    private func verifyProvider(_ provider: DesktopProviderInfo) async {
        guard let runtime = appModel.runtime else { return }
        isProbing = true
        defer { isProbing = false }
        do {
            probeResult = try await runtime.checkProvider(provider: provider.id)
            await appModel.refreshProviders()
        } catch {
            appModel.presentError(error)
        }
    }

    private func addKeyAccount(for provider: DesktopProviderInfo) async {
        guard let runtime = appModel.runtime else { return }
        let name = newKeyAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Default Key"
            : newKeyAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = newKeySecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { return }

        isAddingKey = true
        defer { isAddingKey = false }

        do {
            _ = try await runtime.createProviderKeyAccount(
                provider: provider.id,
                name: name,
                apiKey: secret,
                keyVariable: resolvedKeyEnvName(for: provider)
            )
            newKeySecret = ""
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
            appModel.presentToast("API Key Saved to Keychain", detail: name, style: .success)
        } catch {
            appModel.presentError(error)
        }
    }

    private func updateAccountSecret(provider: String, accountID: String, secret: String) async {
        guard let runtime = appModel.runtime, !provider.isEmpty, !secret.isEmpty else { return }
        do {
            _ = try await runtime.updateProviderAccountKey(
                provider: provider,
                accountID: accountID,
                apiKey: secret
            )
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
            appModel.presentToast("Keychain Secret Updated", style: .success)
        } catch {
            appModel.presentError(error)
        }
    }

    private func createLoginProfile(for provider: DesktopProviderInfo) async {
        guard let runtime = appModel.runtime else { return }
        let name = newLoginProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isCreatingProfile = true
        defer { isCreatingProfile = false }

        do {
            let created = try await runtime.createProviderLoginAccount(provider: provider.id, name: name)
            newLoginProfileName = ""
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
            if let cmd = created.loginCommand, !cmd.isEmpty {
                launchLoginInExternalTerminal(command: cmd)
            } else {
                appModel.presentToast("Created Profile", detail: created.name, style: .success)
            }
        } catch {
            appModel.presentError(error)
        }
    }

    private func deleteAccount(provider: String, accountID: String) async {
        guard let runtime = appModel.runtime else { return }
        do {
            try await runtime.deleteProviderAccount(provider: provider, accountID: accountID)
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
            appModel.presentToast("Removed Account", style: .info)
        } catch {
            appModel.presentError(error)
        }
    }

    private func launchLoginInExternalTerminal(command: String) {
        // Copy login command to clipboard for instant convenience and launch external terminal script
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(command, forType: .string)

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("coincide-signin-\(UUID().uuidString.prefix(8)).command")
        let scriptContents = """
        #!/bin/zsh
        clear
        echo "Signing in for Agents isolated profile..."
        echo "$ \(command.replacingOccurrences(of: "\"", with: "\\\""))"
        echo ""
        \(command)
        echo ""
        echo "Authentication finished. You can close this window and return to Agents."
        rm -f "\(scriptURL.path)"
        """

        do {
            try scriptContents.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            if let terminalTarget = appModel.externalEditors.preferredTerminal,
               terminalTarget.id == "com.apple.Terminal" || terminalTarget.id == "com.googlecode.iterm2"
            {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.open([scriptURL], withApplicationAt: terminalTarget.appURL, configuration: config)
            } else if let terminalApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.open([scriptURL], withApplicationAt: terminalApp, configuration: config)
            } else if let preferred = appModel.externalEditors.preferredTerminal {
                try appModel.externalEditors.open(
                    path: appModel.activeWorkingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path,
                    in: preferred
                )
            }
            appModel.presentToast("Launched Sign-In Terminal", detail: "Command also copied to clipboard", style: .info)
        } catch {
            appModel.presentError(error)
        }
    }

    private func runShellInExternalOrIntegratedTerminal(_ command: String) {
        Task {
            if let termID = await appModel.createTerminalForSelectedThread() {
                try? await appModel.runtime?.sendTerminalInput(id: termID, data: command + "\r")
                appModel.presentToast("Running Command in Terminal", detail: command, style: .info)
            } else {
                launchLoginInExternalTerminal(command: command)
            }
        }
    }
}
