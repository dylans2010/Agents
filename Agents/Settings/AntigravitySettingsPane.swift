import AppKit
import CoincideRemoteKit
import SwiftUI
import UniformTypeIdentifiers

public struct AntigravitySettingsPane: View {
    @Bindable public var appModel: AppModel

    @State private var executablePathDraft: String = ""
    @State private var isSavingRuntime: Bool = false
    @State private var isVerifying: Bool = false
    @State private var probeResult: ProviderProbeResult?

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var provider: DesktopProviderInfo? {
        appModel.providers.first { $0.id == "antigravity" }
    }

    private var discoveredCandidates: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let rawList: [String?] = (provider?.candidateExecutables ?? []).map { Optional($0) } + [
            provider?.antigravityStatus?.binaryPath,
            provider?.antigravityStatus?.legacyBinaryPath,
            appModel.status.legacyAntigravityBinary,
        ]
        for item in rawList {
            guard let trimmed = item?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  !seen.contains(trimmed)
            else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private enum ReadinessState {
        case ready
        case needsAPIKey
        case needsServerBinary

        var label: String {
            switch self {
            case .ready: "Ready"
            case .needsAPIKey: "Needs API Key"
            case .needsServerBinary: "Needs Server Binary"
            }
        }

        var tint: Color {
            switch self {
            case .ready: AppTheme.success
            case .needsAPIKey: AppTheme.warning
            case .needsServerBinary: AppTheme.danger
            }
        }

        var icon: String {
            switch self {
            case .ready: "checkmark.seal.fill"
            case .needsAPIKey: "key.fill"
            case .needsServerBinary: "exclamationmark.triangle.fill"
            }
        }
    }

    private var readiness: ReadinessState {
        let hasBinary = (provider?.approvedExecutable != nil)
            || (provider?.effectiveExecutable != nil)
            || !discoveredCandidates.isEmpty
        guard hasBinary, provider?.isApproved == true else {
            if !hasBinary {
                return .needsServerBinary
            }
            let hasKey = provider?.keyAccounts.contains(where: \.hasKey) ?? false
            return hasKey ? .needsServerBinary : .needsAPIKey
        }
        let hasKey = provider?.keyAccounts.contains(where: \.hasKey) ?? false
        return hasKey ? .ready : .needsAPIKey
    }

    private var docsURL: URL {
        if let raw = provider?.antigravityStatus?.termsURL, let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://antigravity.google/docs/ide/extensions/acp")!
    }

    public var body: some View {
        Form {
            headerSection
            acpRuntimeSection
            geminiKeyAccountsSection
            securitySafetySection
        }
        .formStyle(.grouped)
        .navigationTitle("Google Antigravity")
        .task {
            await appModel.refreshProviders()
            syncDraftFromProvider()
        }
        .onChange(of: appModel.providers) { _, _ in
            if executablePathDraft.isEmpty {
                syncDraftFromProvider()
            }
        }
    }

    // MARK: - 1. Flagship Header Card

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AgentBranding.color(for: "antigravity").opacity(0.12))
                            .frame(width: 46, height: 46)
                        AgentLogoView(provider: "antigravity", size: 32)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Google Antigravity")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppTheme.primaryLabel)

                            statusPill
                        }

                        Text("Official Agent Client Protocol (ACP) integration powered by Gemini API keys in macOS Keychain.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }

                    Spacer()

                    Button {
                        Task { await verifyAntigravityRuntime() }
                    } label: {
                        HStack(spacing: 6) {
                            if isVerifying {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "stethoscope")
                            }
                            Text("Verify Runtime")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isVerifying)
                }

                if let probe = probeResult {
                    Divider()
                    probeSummaryBanner(probe)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statusPill: some View {
        let current = readiness
        return HStack(spacing: 5) {
            Image(systemName: current.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(current.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(current.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(current.tint.opacity(0.14))
        )
    }

    private func probeSummaryBanner(_ probe: ProviderProbeResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: probe.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(probe.ok ? AppTheme.success : AppTheme.warning)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(probe.ok ? "Runtime Files Present" : "Verification Needs Attention")
                        .font(.system(size: 12.5, weight: .semibold))
                    if let version = probe.version, !version.isEmpty {
                        Text("v\(version)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    if let count = probe.modelsCount, count > 0 {
                        Text("· \(count) models")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }

                if let msg = probe.message, !msg.isEmpty {
                    Text(msg)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }

                Text("This check confirms only that the server binary, the companion helper, runtime approval, and a stored Gemini API key account are present. It does not contact Gemini, so authentication is verified only when a turn's authenticate call succeeds.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if let exec = probe.executablePath, !exec.isEmpty {
                    Text(exec)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(AppTheme.elevatedCardFill)
        )
    }

    // MARK: - 2. ACP Server Runtime (`agy_acp_server.par` + `localharness_external`)

    private var acpRuntimeSection: some View {
        Section {
            LabeledContent("Approved ACP Server") {
                if let approved = provider?.approvedExecutable, !approved.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(AppTheme.success)
                        Text(approved)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button {
                            appModel.externalEditors.revealInFinder(path: approved)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                        .accessibilityLabel("Reveal approved server binary in Finder")
                    }
                } else {
                    Text("Not pinned yet")
                        .foregroundStyle(AppTheme.warning)
                }
            }

            LabeledContent("Companion Helper") {
                let helper = provider?.approvedCompanion ?? provider?.antigravityStatus?.helperPath
                if let helper, !helper.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                        Text((helper as NSString).lastPathComponent)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        Text("(\(helper))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text("localharness_external resolved next to agy_acp_server.par upon approval")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }

            if !discoveredCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto-Discovered ACP Server Candidates")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)

                    ForEach(discoveredCandidates, id: \.self) { candidate in
                        HStack(spacing: 8) {
                            Image(systemName: "terminal")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryLabel)

                            Text(candidate)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)

                            Spacer()

                            if provider?.approvedExecutable == candidate && provider?.isApproved == true {
                                Label("Approved", systemImage: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.success)
                            } else {
                                Button("Use & Approve Discovered Server") {
                                    executablePathDraft = candidate
                                    Task { await saveAndPinRuntime(path: candidate) }
                                }
                                .controlSize(.small)
                                .disabled(isSavingRuntime)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Binary Path")
                    .font(.system(size: 12, weight: .medium))

                HStack(spacing: 8) {
                    TextField(
                        "~/Library/Application Support/Coincide/tools/antigravity-acp/darwin-arm64/current/agy_acp_server.par",
                        text: $executablePathDraft
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))

                    Button("Choose Binary…") {
                        chooseAntigravityBinary()
                    }
                    .controlSize(.regular)

                    Button("Save & Pin Runtime") {
                        Task { await saveAndPinRuntime(path: executablePathDraft) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(executablePathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingRuntime)
                }
            }
        } header: {
            Text("ACP Server Runtime (agy_acp_server.par + localharness_external)")
        } footer: {
            Text("Agents pins the SHA-256 baseline of your approved agy_acp_server.par binary and sibling localharness_external helper before launching turns.")
        }
    }

    // MARK: - 3. Gemini API Key Accounts (macOS Keychain)

    private var geminiKeyAccountsSection: some View {
        ProviderKeyAccountsSection(
            appModel: appModel,
            provider: provider ?? DesktopProviderInfo(id: "antigravity", displayName: "Google Antigravity"),
            title: "Gemini API Key Accounts (macOS Keychain)",
            addTitle: "Add Gemini API Key Account",
            addButtonTitle: "Add Account & Save to Keychain",
            emptyText: "No Gemini API key accounts configured yet. Add a GEMINI_API_KEY below to start coding with Antigravity.",
            footer: "Adding a Gemini API key securely stores it in your macOS Keychain and automatically approves your discovered agy_acp_server.par runtime.",
            defaultAccountName: "Default Gemini Key",
            fixedKeyVariable: "GEMINI_API_KEY",
            addAccount: addGeminiKeyAccount
        )
    }

    // MARK: - 4. Security & Account Safety Card

    private var securitySafetySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(AppTheme.info)
                        .font(.system(size: 15))
                    Text("Isolated Per-Thread GEMINI_HOME & Google Account Protection")
                        .font(.system(size: 13, weight: .semibold))
                }

                Text("Agents runs Google Antigravity's official ACP server exclusively with Gemini API-key accounts stored in your macOS Keychain inside isolated per-thread GEMINI_HOME sandboxes. Personal Google OAuth token scraping is intentionally disabled to protect your Google account under Antigravity Terms of Service.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button {
                        NSWorkspace.shared.open(docsURL)
                    } label: {
                        Label("Open Antigravity ACP Documentation", systemImage: "safari")
                    }
                    .controlSize(.small)

                    Spacer()
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Security & Account Safety")
        }
    }

    private func addGeminiKeyAccount(name: String, key: String, keyVariable: String) async -> String? {
        guard let runtime = appModel.runtime else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedKey.isEmpty else { return nil }

        do {
            _ = try await runtime.createProviderKeyAccount(
                provider: "antigravity",
                name: trimmedName,
                apiKey: trimmedKey,
                keyVariable: keyVariable
            )
            var autoApproveError: Error?
            if provider?.approvedExecutable == nil, let discovered = discoveredCandidates.first {
                do {
                    _ = try await runtime.saveProviderConfig(
                        provider: "antigravity",
                        executable: ExternalEditorService.expandedPath(discovered),
                        environment: provider?.environment,
                        enabled: true
                    )
                } catch {
                    autoApproveError = error
                }
            }
            let nextName: String? = trimmedName == "Default Gemini Key"
                ? "Gemini Key \((provider?.keyAccounts.count ?? 0) + 2)"
                : nil
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
            syncDraftFromProvider()
            if let autoApproveError {
                appModel.presentToast(
                    "Saved Gemini API Key",
                    detail: "Stored in macOS Keychain. Runtime approval failed: \(autoApproveError.localizedDescription)",
                    style: .warning
                )
            } else {
                appModel.presentToast("Saved Gemini API Key", detail: "Stored in macOS Keychain", style: .success)
            }
            return nextName
        } catch {
            appModel.presentError(error)
            return nil
        }
    }

    private func syncDraftFromProvider() {
        if let p = provider {
            executablePathDraft = p.approvedExecutable
                ?? p.configuredExecutable
                ?? p.effectiveExecutable
                ?? discoveredCandidates.first
                ?? ""
        } else if let first = discoveredCandidates.first {
            executablePathDraft = first
        }
    }

    private func chooseAntigravityBinary() {
        let panel = NSOpenPanel()
        panel.title = "Choose agy_acp_server.par Binary"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            executablePathDraft = url.path
        }
    }

    private func saveAndPinRuntime(path rawPath: String) async {
        guard let runtime = appModel.runtime else { return }
        let expanded = ExternalEditorService.expandedPath(rawPath.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !expanded.isEmpty else { return }

        isSavingRuntime = true
        defer { isSavingRuntime = false }

        do {
            _ = try await runtime.saveProviderConfig(
                provider: "antigravity",
                executable: expanded,
                environment: provider?.environment,
                enabled: true
            )
            await appModel.refreshProviders()
            await appModel.refreshWorkspace()
            syncDraftFromProvider()
            appModel.presentToast("Antigravity Runtime Pinned", detail: (expanded as NSString).lastPathComponent, style: .success)
            await verifyAntigravityRuntime()
        } catch {
            appModel.presentError(error)
        }
    }

    private func verifyAntigravityRuntime() async {
        guard let runtime = appModel.runtime else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            let res = try await runtime.checkProvider(provider: "antigravity")
            self.probeResult = res
            await appModel.refreshProviders()
        } catch {
            appModel.presentError(error)
        }
    }

}
