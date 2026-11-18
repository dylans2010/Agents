import AppKit
import CoincideRemoteKit
import SwiftUI

public struct ModelsSettingsPane: View {
    @Bindable public var appModel: AppModel

    @State private var selectedProviderID: String = "antigravity"
    @State private var catalogModels: [CatalogModelEntry] = []
    @State private var searchQuery: String = ""
    @State private var showHiddenModels: Bool = true
    @State private var isLoading: Bool = false
    @State private var customModelIDDraft: String = ""

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var availableProviders: [DesktopProviderInfo] {
        appModel.providers
    }

    private var filteredModels: [CatalogModelEntry] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return catalogModels.filter { entry in
            if !showHiddenModels && entry.isHidden {
                return false
            }
            guard !q.isEmpty else { return true }
            return entry.name.lowercased().contains(q)
                || entry.id.lowercased().contains(q)
                || (entry.description?.lowercased().contains(q) ?? false)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            modelsToolbar
            Divider()
            modelsListContent
            Divider()
            customModelFooterBar
        }
        .navigationTitle("Models")
        .task {
            if appModel.providers.isEmpty {
                await appModel.refreshProviders()
            }
            if !appModel.providers.contains(where: { $0.id == selectedProviderID }),
               let first = appModel.providers.first
            {
                selectedProviderID = first.id
            }
            await loadCatalog(refresh: false)
        }
        .onChange(of: selectedProviderID) { _, _ in
            Task { await loadCatalog(refresh: false) }
        }
    }

    // MARK: - Top Filter & Provider Bar

    private var modelsToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                AgentLogoView(provider: selectedProviderID, size: 16)
                Picker("Provider", selection: $selectedProviderID) {
                    ForEach(availableProviders) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryLabel)
                TextField("Filter models by name or ID…", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    .buttonStyle(.plain)
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

            Toggle("Show Hidden", isOn: $showHiddenModels)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Button {
                Task { await loadCatalog(refresh: true) }
            } label: {
                HStack(spacing: 5) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh Catalog")
                }
            }
            .controlSize(.small)
            .disabled(isLoading)
        }
        .padding(12)
        .background(AppTheme.controlBackground)
    }

    // MARK: - Models Table / List

    @ViewBuilder
    private var modelsListContent: some View {
        if isLoading && catalogModels.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Querying model catalog…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredModels.isEmpty {
            ContentUnavailableView(
                searchQuery.isEmpty ? "No Models Reported" : "No Matching Models",
                systemImage: "slider.horizontal.3",
                description: Text(
                    searchQuery.isEmpty
                        ? "Configure and verify this provider or add a custom model ID below."
                        : "Clear your search filter to see all models."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filteredModels) { model in
                modelRow(model)
            }
            .listStyle(.inset)
        }
    }

    private func modelRow(_ model: CatalogModelEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.isHidden ? AppTheme.tertiaryLabel : AppTheme.primaryLabel)

                    Text(model.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .textSelection(.enabled)

                    if model.isDefault {
                        tagPill("Default", icon: "star.fill", tint: AppTheme.warning)
                    }
                    if model.supportsImages {
                        tagPill("Vision", icon: "photo", tint: AppTheme.info)
                    }
                    if model.isCustom {
                        tagPill("Custom", icon: "sparkles", tint: AppTheme.accent)
                    }
                }

                if let desc = model.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                }

                if !model.efforts.isEmpty || !model.speeds.isEmpty {
                    HStack(spacing: 6) {
                        if !model.efforts.isEmpty {
                            Text("Reasoning:")
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                            ForEach(model.efforts, id: \.self) { effort in
                                Text(effort)
                                    .font(.system(size: 10, weight: effort == model.defaultEffort ? .semibold : .regular, design: .monospaced))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(AppTheme.elevatedCardFill)
                                    )
                            }
                        }

                        if !model.speeds.isEmpty {
                            Text("Speeds:")
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                                .padding(.leading, 4)
                            ForEach(model.speeds) { speed in
                                Text(speed.name)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(AppTheme.elevatedCardFill)
                                    )
                            }
                        }
                    }
                }
            }

            Spacer()

            // Preference Toggles: Default Star, Favorite Heart, Hidden Eye-Slash
            HStack(spacing: 8) {
                Button {
                    Task { await toggleDefault(model) }
                } label: {
                    Image(systemName: model.isDefault ? "star.fill" : "star")
                        .foregroundStyle(model.isDefault ? AppTheme.warning : AppTheme.tertiaryLabel)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(model.isDefault ? "Default Model" : "Set as Default Model")

                Button {
                    Task { await toggleFavorite(model) }
                } label: {
                    Image(systemName: model.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(model.isFavorite ? Color(nsColor: .systemPink) : AppTheme.tertiaryLabel)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(model.isFavorite ? "Remove from Favorites" : "Pin to Favorites")

                Button {
                    Task { await toggleHidden(model) }
                } label: {
                    Image(systemName: model.isHidden ? "eye.slash.fill" : "eye")
                        .foregroundStyle(model.isHidden ? AppTheme.danger : AppTheme.tertiaryLabel)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(model.isHidden ? "Show in Composer Picker" : "Hide from Composer Picker")
            }
        }
        .padding(.vertical, 4)
    }

    private func tagPill(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(
            Capsule()
                .fill(tint.opacity(0.14))
        )
    }

    // MARK: - Custom Model Footer Bar

    private var customModelFooterBar: some View {
        HStack(spacing: 8) {
            Text("Custom Model ID:")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.secondaryLabel)

            TextField("e.g. gemini-2.5-pro-exp or claude-opus-4-6", text: $customModelIDDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
                .onSubmit {
                    Task { await addCustomModel() }
                }

            Button("Add Custom Model") {
                Task { await addCustomModel() }
            }
            .controlSize(.small)
            .disabled(customModelIDDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(AppTheme.controlBackground)
    }

    // MARK: - Actions

    private func loadCatalog(refresh: Bool) async {
        guard let runtime = appModel.runtime, !selectedProviderID.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        let targetProvider = selectedProviderID
        do {
            let models = try await runtime.fetchModelCatalog(
                provider: targetProvider,
                refresh: refresh,
                threadID: appModel.selectedThreadID,
                accountID: nil
            )
            if self.selectedProviderID == targetProvider {
                self.catalogModels = models
            }
            if refresh {
                await appModel.refreshWorkspace()
            }
        } catch {
            if let fallback = appModel.providers.first(where: { $0.id == targetProvider })?.models, !fallback.isEmpty {
                self.catalogModels = fallback
            } else {
                appModel.presentError(error)
            }
        }
    }

    private func toggleDefault(_ model: CatalogModelEntry) async {
        guard let runtime = appModel.runtime else { return }
        let newDefault = !model.isDefault
        do {
            try await runtime.setModelPreference(
                provider: selectedProviderID,
                modelID: model.id,
                isDefault: newDefault
            )
            await loadCatalog(refresh: false)
            await appModel.refreshWorkspace()
        } catch {
            appModel.presentError(error)
        }
    }

    private func toggleFavorite(_ model: CatalogModelEntry) async {
        guard let runtime = appModel.runtime else { return }
        do {
            try await runtime.setModelPreference(
                provider: selectedProviderID,
                modelID: model.id,
                favorite: !model.isFavorite
            )
            await loadCatalog(refresh: false)
            await appModel.refreshWorkspace()
        } catch {
            appModel.presentError(error)
        }
    }

    private func toggleHidden(_ model: CatalogModelEntry) async {
        guard let runtime = appModel.runtime else { return }
        do {
            try await runtime.setModelPreference(
                provider: selectedProviderID,
                modelID: model.id,
                hidden: !model.isHidden
            )
            await loadCatalog(refresh: false)
            await appModel.refreshWorkspace()
        } catch {
            appModel.presentError(error)
        }
    }

    private func addCustomModel() async {
        guard let runtime = appModel.runtime else { return }
        let trimmed = customModelIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await runtime.setModelPreference(
                provider: selectedProviderID,
                modelID: trimmed,
                favorite: true,
                hidden: false,
                custom: true
            )
            customModelIDDraft = ""
            await loadCatalog(refresh: false)
            await appModel.refreshWorkspace()
            appModel.presentToast("Added Custom Model", detail: trimmed, style: .success)
        } catch {
            appModel.presentError(error)
        }
    }
}
