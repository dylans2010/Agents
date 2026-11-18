import AppKit
import CoincideRemoteKit
import SwiftUI

struct AgentModelPickerPopover: View {
    @Bindable var appModel: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    @State private var focusedProviderID: String = ""
    @State private var modelFilter: String = ""
    @State private var fetchedCatalogModels: [String: [CatalogModelEntry]] = [:]
    @State private var isRefreshingCatalog = false

    private struct UnifiedAccountOption: Identifiable, Hashable {
        let id: String
        let name: String
        let subtitle: String?
        let isReady: Bool
    }

    private var activeSelection: RemoteSelection {
        appModel.selectedThread?.selection
            ?? RemoteSelection(provider: "antigravity", modelID: "default", modelName: "Default")
    }

    private var allProvidersOrdered: [DesktopProviderInfo] {
        var byID: [String: DesktopProviderInfo] = [:]
        for p in appModel.providers {
            byID[AgentBranding.normalizedID(p.id)] = p
        }
        for rp in appModel.workspace.providers {
            let key = AgentBranding.normalizedID(rp.id)
            if byID[key] == nil {
                byID[key] = DesktopProviderInfo(
                    id: rp.id,
                    displayName: rp.name,
                    isACP: rp.id.hasPrefix("acp-"),
                    isEnabled: true,
                    isApproved: rp.isReady,
                    isInstalled: rp.state != "notInstalled",
                    state: rp.state,
                    models: rp.models.map { rm in
                        CatalogModelEntry(
                            id: rm.id,
                            provider: rp.id,
                            name: rm.name,
                            efforts: rm.efforts,
                            defaultEffort: rm.defaultEffort,
                            speeds: rm.speeds,
                            supportsImages: rm.supportsImages
                        )
                    }
                )
            }
        }
        // Ensure core built-in agents are always represented in a predictable order
        let preferredOrder = ["antigravity", "claude", "codex", "cursor", "grok", "opencode", "lithos"]
        var result: [DesktopProviderInfo] = []
        for id in preferredOrder {
            if let existing = byID.removeValue(forKey: id) {
                result.append(existing)
            } else if id == "antigravity" || id == "claude" || id == "codex" || id == "cursor" || id == "grok" || id == "opencode" {
                result.append(
                    DesktopProviderInfo(
                        id: id,
                        displayName: AgentBranding.displayName(for: id),
                        isEnabled: true,
                        isApproved: false,
                        isInstalled: false,
                        state: "notInstalled"
                    )
                )
            }
        }
        let remaining = byID.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        result.append(contentsOf: remaining)
        return result
    }

    private var selectedProviderInfo: DesktopProviderInfo? {
        let target = focusedProviderID.isEmpty
            ? AgentBranding.normalizedID(activeSelection.provider)
            : AgentBranding.normalizedID(focusedProviderID)
        return allProvidersOrdered.first { AgentBranding.normalizedID($0.id) == target }
            ?? allProvidersOrdered.first
    }

    private func accounts(for provider: DesktopProviderInfo) -> [UnifiedAccountOption] {
        var seen = Set<String>()
        var output: [UnifiedAccountOption] = []

        for keyAcc in provider.keyAccounts {
            guard !seen.contains(keyAcc.id) else { continue }
            seen.insert(keyAcc.id)
            output.append(
                UnifiedAccountOption(
                    id: keyAcc.id,
                    name: keyAcc.name,
                    subtitle: keyAcc.keyVariable ?? "API Key",
                    isReady: keyAcc.hasKey
                )
            )
        }

        if let agAccounts = provider.antigravityStatus?.accounts {
            for keyAcc in agAccounts where !seen.contains(keyAcc.id) {
                seen.insert(keyAcc.id)
                output.append(
                    UnifiedAccountOption(
                        id: keyAcc.id,
                        name: keyAcc.name,
                        subtitle: keyAcc.keyVariable ?? "GEMINI_API_KEY",
                        isReady: keyAcc.hasKey
                    )
                )
            }
        }

        for loginAcc in provider.loginAccounts where !seen.contains(loginAcc.id) {
            seen.insert(loginAcc.id)
            output.append(
                UnifiedAccountOption(
                    id: loginAcc.id,
                    name: loginAcc.name,
                    subtitle: loginAcc.statusText ?? "CLI Login",
                    isReady: loginAcc.isReady
                )
            )
        }

        if let remoteProv = appModel.workspace.providers.first(where: {
            AgentBranding.normalizedID($0.id) == AgentBranding.normalizedID(provider.id)
        }) {
            for ra in remoteProv.accounts where !seen.contains(ra.id) {
                seen.insert(ra.id)
                output.append(
                    UnifiedAccountOption(
                        id: ra.id,
                        name: ra.name,
                        subtitle: nil,
                        isReady: ra.isReady
                    )
                )
            }
        }
        return output
    }

    private func models(for provider: DesktopProviderInfo) -> [CatalogModelEntry] {
        let norm = AgentBranding.normalizedID(provider.id)
        var rawModels = fetchedCatalogModels[norm] ?? provider.models

        if rawModels.isEmpty,
           let remoteProv = appModel.workspace.providers.first(where: { AgentBranding.normalizedID($0.id) == norm })
        {
            rawModels = remoteProv.models.map { rm in
                CatalogModelEntry(
                    id: rm.id,
                    provider: provider.id,
                    name: rm.name,
                    efforts: rm.efforts,
                    defaultEffort: rm.defaultEffort,
                    speeds: rm.speeds,
                    supportsImages: rm.supportsImages
                )
            }
        }

        let visible = rawModels.filter { !$0.isHidden || $0.id == activeSelection.modelID }
        let sorted = visible.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault && !rhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let q = modelFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    private var activeModelEntry: CatalogModelEntry? {
        guard let provider = selectedProviderInfo else { return nil }
        let list = models(for: provider)
        return list.first(where: { $0.id == activeSelection.modelID }) ?? list.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column: Provider Rail
            VStack(alignment: .leading, spacing: 6) {
                Text("AGENT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(allProvidersOrdered) { provider in
                            providerSidebarRow(provider)
                        }
                    }
                }
            }
            .padding(10)
            .frame(minWidth: 180, idealWidth: 195, maxWidth: 220)
            .background(Color.primary.opacity(0.025))

            Divider()

            // Right column: Account, Model, Effort, Speed & Notices
            if let provider = selectedProviderInfo {
                VStack(alignment: .leading, spacing: 12) {
                    providerDetailHeader(provider)

                    if AgentBranding.normalizedID(provider.id) == "antigravity" {
                        antigravityCompactNoticeCard(provider)
                    }

                    let providerAccounts = accounts(for: provider)
                    if !providerAccounts.isEmpty {
                        accountPickerSection(provider: provider, accounts: providerAccounts)
                    }

                    Divider()

                    modelPickerSection(provider: provider)

                    if let model = activeModelEntry,
                       AgentBranding.normalizedID(provider.id) == AgentBranding.normalizedID(activeSelection.provider)
                    {
                        if !model.efforts.isEmpty {
                            Divider()
                            effortPickerSection(provider: provider, model: model)
                        }
                        if !model.speeds.isEmpty {
                            Divider()
                            speedPickerSection(provider: provider, model: model)
                        }
                    }
                }
                .padding(14)
                .frame(minWidth: 320, idealWidth: 345, maxWidth: 380)
            }
        }
        .frame(minHeight: 380, idealHeight: 430, maxHeight: 520)
        .onAppear {
            focusedProviderID = activeSelection.provider
        }
        .task(id: focusedProviderID) {
            await loadCatalogIfNeeded()
        }
    }

    // MARK: - Left Provider Row

    @ViewBuilder
    private func providerSidebarRow(_ provider: DesktopProviderInfo) -> some View {
        let normID = AgentBranding.normalizedID(provider.id)
        let isFocused = AgentBranding.normalizedID(selectedProviderInfo?.id) == normID
        let isThreadActive = AgentBranding.normalizedID(activeSelection.provider) == normID
        let isReady = provider.state == "ready"
            || (normID == "antigravity" && !(provider.keyAccounts.filter(\.hasKey).isEmpty && (provider.antigravityStatus?.accounts.filter(\.hasKey).isEmpty ?? true)))

        Button {
            focusedProviderID = provider.id
            if isReady || provider.isInstalled {
                applyThreadSelection(provider: provider.id, modelID: nil, accountID: nil)
            }
        } label: {
            HStack(spacing: 8) {
                AgentLogoView(provider: provider.id, size: 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(provider.displayName)
                            .font(.system(size: 12, weight: isFocused ? .semibold : .regular))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .lineLimit(1)
                        if normID == "antigravity" {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(AgentBranding.color(for: "antigravity"))
                        }
                    }
                    if provider.isACP {
                        Text("ACP Agent")
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                }

                Spacer(minLength: 4)

                if isThreadActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.accent)
                } else {
                    Circle()
                        .fill(isReady ? AppTheme.success : (provider.isInstalled ? AppTheme.warning : AppTheme.quaternaryLabel))
                        .frame(width: 6.5, height: 6.5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6.5)
            .background(
                isFocused ? AppTheme.selectedContentBackground.opacity(0.22) : Color.clear,
                in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Detail Sections

    @ViewBuilder
    private func providerDetailHeader(_ provider: DesktopProviderInfo) -> some View {
        let normID = AgentBranding.normalizedID(provider.id)
        HStack(spacing: 8) {
            AgentLogoView(provider: provider.id, size: 18)
            Text(provider.displayName)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppTheme.primaryLabel)

            Spacer()

            Button {
                appModel.selectedSettingsTab = normID == "antigravity" ? .antigravity : .providers
                openSettings()
                dismiss()
            } label: {
                Label("Configure…", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func antigravityCompactNoticeCard(_ provider: DesktopProviderInfo) -> some View {
        let termsURLString = provider.antigravityStatus?.termsURL ?? "https://antigravity.google/terms"
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "key.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Gemini API keys (Google AI Studio / Enterprise) are safe to use. Third-party OAuth access may violate Google’s Antigravity terms.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    if let url = URL(string: termsURLString) {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text("Read Google’s Antigravity Terms")
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(AppTheme.info)
                        }
                    }
                }
            }
        }
        .padding(9)
        .background(AppTheme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .strokeBorder(AppTheme.warning.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func accountPickerSection(provider: DesktopProviderInfo, accounts: [UnifiedAccountOption]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AgentBranding.normalizedID(provider.id) == "antigravity" ? "GEMINI API KEY ACCOUNT" : "ACCOUNT")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.tertiaryLabel)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(accounts) { account in
                        let isSelected = activeSelection.accountID == account.id
                            || (activeSelection.accountID == nil && account.id == accounts.first?.id && AgentBranding.normalizedID(activeSelection.provider) == AgentBranding.normalizedID(provider.id))
                        Button {
                            selectAccount(providerID: provider.id, accountID: account.id)
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(account.isReady ? AppTheme.success : AppTheme.warning)
                                    .frame(width: 6, height: 6)
                                Text(account.name)
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(AppTheme.primaryLabel)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(
                                isSelected ? AppTheme.accent.opacity(0.14) : AppTheme.elevatedCardFill,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? AppTheme.accent.opacity(0.65) : AppTheme.separator, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelPickerSection(provider: DesktopProviderInfo) -> some View {
        let modelList = models(for: provider)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MODEL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.tertiaryLabel)

                Spacer()

                Button {
                    Task { await refreshCatalog(for: provider.id) }
                } label: {
                    if isRefreshingCatalog {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
                .buttonStyle(.plain)
                .help("Refresh model catalog")
                .accessibilityLabel("Refresh model catalog")
            }

            if modelList.count > 5 || !modelFilter.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                    TextField("Search models…", text: $modelFilter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .strokeBorder(AppTheme.separator, lineWidth: 1)
                )
            }

            if modelList.isEmpty {
                Text("Default provider model will be used automatically.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(modelList) { model in
                            let isSelected = AgentBranding.normalizedID(activeSelection.provider) == AgentBranding.normalizedID(provider.id)
                                && activeSelection.modelID == model.id
                            HStack(spacing: 6) {
                                Button {
                                    applyThreadSelection(provider: provider.id, modelID: model.id, accountID: nil)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: isSelected ? "checkmark" : "cpu")
                                            .font(.system(size: 10.5, weight: isSelected ? .bold : .regular))
                                            .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.tertiaryLabel)
                                            .frame(width: 14)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(model.name)
                                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                                .foregroundStyle(AppTheme.primaryLabel)
                                                .lineLimit(1)
                                            if model.name != model.id {
                                                Text(model.id)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(AppTheme.tertiaryLabel)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        if model.supportsImages {
                                            Image(systemName: "photo")
                                                .font(.system(size: 10))
                                                .foregroundStyle(AppTheme.tertiaryLabel)
                                                .help("Supports image inputs")
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    toggleFavorite(provider: provider.id, model: model)
                                } label: {
                                    Image(systemName: model.isFavorite ? "star.fill" : "star")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(model.isFavorite ? AppTheme.favoriteStar : AppTheme.quaternaryLabel)
                                }
                                .buttonStyle(.plain)
                                .help(model.isFavorite ? "Remove favorite" : "Pin favorite model")
                                .accessibilityLabel(model.isFavorite ? "Remove \(model.name) from favorites" : "Pin \(model.name) as favorite")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                isSelected ? AppTheme.accent.opacity(0.11) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                        }
                    }
                }
                .frame(maxHeight: 165)
            }
        }
    }

    @ViewBuilder
    private func effortPickerSection(provider: DesktopProviderInfo, model: CatalogModelEntry) -> some View {
        let currentEffort = activeSelection.effort ?? model.defaultEffort ?? ""
        VStack(alignment: .leading, spacing: 5) {
            Text("REASONING EFFORT")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.tertiaryLabel)

            HStack(spacing: 5) {
                ForEach(model.efforts, id: \.self) { effort in
                    let selected = currentEffort == effort
                    Button {
                        updateEffort(effort)
                    } label: {
                        Text(effort.capitalized)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? AppTheme.accent : AppTheme.primaryLabel)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                selected ? AppTheme.accent.opacity(0.13) : AppTheme.elevatedCardFill,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(selected ? AppTheme.accent.opacity(0.6) : AppTheme.separator, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func speedPickerSection(provider: DesktopProviderInfo, model: CatalogModelEntry) -> some View {
        let currentSpeed = activeSelection.speed ?? RemoteThreadSettings.standardSpeed
        let allSpeeds = [RemoteSpeed(id: RemoteThreadSettings.standardSpeed, name: "Standard")] + model.speeds

        VStack(alignment: .leading, spacing: 5) {
            Text("SPEED")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.tertiaryLabel)

            HStack(spacing: 5) {
                ForEach(allSpeeds) { speed in
                    let selected = currentSpeed == speed.id
                    Button {
                        updateSpeed(speed.id)
                    } label: {
                        HStack(spacing: 4) {
                            if speed.id != RemoteThreadSettings.standardSpeed {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9.5))
                            }
                            Text(speed.name)
                                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        }
                        .foregroundStyle(selected ? AppTheme.accent : AppTheme.primaryLabel)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            selected ? AppTheme.accent.opacity(0.13) : AppTheme.elevatedCardFill,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(selected ? AppTheme.accent.opacity(0.6) : AppTheme.separator, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Runtime Mutations

    private func loadCatalogIfNeeded() async {
        guard let provider = selectedProviderInfo else { return }
        let norm = AgentBranding.normalizedID(provider.id)
        guard fetchedCatalogModels[norm] == nil else { return }
        guard let client = appModel.runtime else { return }
        if let list = try? await client.fetchModelCatalog(
            provider: provider.id,
            refresh: false,
            threadID: appModel.selectedThreadID,
            accountID: activeSelection.accountID
        ), !list.isEmpty {
            fetchedCatalogModels[norm] = list
        }
    }

    private func refreshCatalog(for providerID: String) async {
        guard let client = appModel.runtime else { return }
        isRefreshingCatalog = true
        if let list = try? await client.fetchModelCatalog(
            provider: providerID,
            refresh: true,
            threadID: appModel.selectedThreadID,
            accountID: activeSelection.accountID
        ) {
            fetchedCatalogModels[AgentBranding.normalizedID(providerID)] = list
        }
        await appModel.refreshProviders()
        isRefreshingCatalog = false
    }

    private func toggleFavorite(provider: String, model: CatalogModelEntry) {
        let newFavorite = !model.isFavorite
        Task {
            try? await appModel.runtime?.setModelPreference(
                provider: provider,
                modelID: model.id,
                favorite: newFavorite
            )
            await refreshCatalog(for: provider)
        }
    }

    private func ensureTargetThread() async -> UUID? {
        if let existing = appModel.selectedThreadUUID {
            return existing
        }
        return await appModel.createNewThread()
    }

    private func selectAccount(providerID: String, accountID: String) {
        Task {
            guard let tid = await ensureTargetThread() else { return }
            try? await appModel.runtime?.selectThreadAccount(threadID: tid.uuidString, accountID: accountID)
            await appModel.updateThreadSettings(
                RemoteThreadSettings(
                    threadID: tid,
                    provider: providerID,
                    accountID: accountID
                )
            )
        }
    }

    private func applyThreadSelection(provider: String, modelID: String?, accountID: String?) {
        Task {
            guard let tid = await ensureTargetThread() else { return }
            if let accountID {
                try? await appModel.runtime?.selectThreadAccount(threadID: tid.uuidString, accountID: accountID)
            }
            await appModel.updateThreadSettings(
                RemoteThreadSettings(
                    threadID: tid,
                    provider: provider,
                    modelID: modelID,
                    accountID: accountID
                )
            )
        }
    }

    private func updateEffort(_ effort: String) {
        Task {
            guard let tid = await ensureTargetThread() else { return }
            await appModel.updateThreadSettings(
                RemoteThreadSettings(threadID: tid, effort: effort)
            )
        }
    }

    private func updateSpeed(_ speed: String) {
        Task {
            guard let tid = await ensureTargetThread() else { return }
            await appModel.updateThreadSettings(
                RemoteThreadSettings(threadID: tid, speed: speed)
            )
        }
    }
}
