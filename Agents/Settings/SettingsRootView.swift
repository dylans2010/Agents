import AppKit
import CoincideRemoteKit
import SwiftUI

public struct SettingsRootView: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        NavigationSplitView {
            settingsSidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 218, max: 250)
        } detail: {
            settingsDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.windowBackground)
        }
        .frame(minWidth: 840, idealWidth: 920, minHeight: 580, idealHeight: 660)
        .preferredColorScheme(appModel.appearancePreference.colorScheme)
        .task {
            await refreshAllSettingsContext()
        }
    }

    // MARK: - Sidebar

    private var settingsSidebar: some View {
        List(selection: $appModel.selectedSettingsTab) {
            Section("Workspace") {
                sidebarRow(for: .general, tint: .gray)
                sidebarRow(for: .antigravity, tint: AppTheme.info)
                sidebarRow(for: .providers, tint: .indigo)
                sidebarRow(for: .models, tint: AppTheme.merged)
                sidebarRow(for: .instructions, tint: AppTheme.warning)
                sidebarRow(for: .memory, tint: .teal)
                sidebarRow(for: .computerUse, tint: .brown)
                sidebarRow(for: .assistants, tint: .purple)
            }

            Section("Telemetry & System") {
                sidebarRow(for: .usage, tint: AppTheme.success)
                sidebarRow(for: .voice, tint: AppTheme.favoriteHeart)
                sidebarRow(for: .remote, tint: .cyan)
                sidebarRow(for: .about, tint: .secondary)
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(for tab: SettingsTab, tint: Color) -> some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(tint.opacity(0.16))
                    .frame(width: 22, height: 22)

                if tab == .antigravity {
                    AgentLogoView(provider: "antigravity", size: 14)
                } else {
                    Image(systemName: tab.symbolName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }

            Text(tab.title)
                .font(.system(size: 13))

            Spacer(minLength: 4)

            if tab == .antigravity {
                antigravityStatusDot
            } else if tab == .remote, appModel.remoteServer.enabled {
                Circle()
                    .fill(AppTheme.success)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 1)
        .tag(tab)
    }

    @ViewBuilder
    private var antigravityStatusDot: some View {
        if let agy = appModel.providers.first(where: { $0.id == "antigravity" }) {
            let hasKey = agy.keyAccounts.contains(where: \.hasKey)
            let hasBinary = agy.approvedExecutable != nil || agy.effectiveExecutable != nil
            Circle()
                .fill((hasKey && hasBinary && agy.isApproved) ? AppTheme.success : AppTheme.warning)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Detail Switcher

    @ViewBuilder
    private var settingsDetailPane: some View {
        switch appModel.selectedSettingsTab {
        case .general:
            GeneralSettingsPane(appModel: appModel)
        case .antigravity:
            AntigravitySettingsPane(appModel: appModel)
        case .providers:
            ProvidersSettingsPane(appModel: appModel)
        case .models:
            ModelsSettingsPane(appModel: appModel)
        case .instructions:
            InstructionsSettingsPane(appModel: appModel)
        case .memory:
            MemorySettingsPane(appModel: appModel)
        case .computerUse:
            ComputerUseSettingsPane(appModel: appModel)
        case .assistants:
            AssistantsSettingsPane(appModel: appModel)
        case .usage:
            UsageSettingsPane(appModel: appModel)
        case .voice:
            VoiceSettingsPane(appModel: appModel)
        case .remote:
            RemoteSettingsPane(appModel: appModel)
        case .about:
            AboutSettingsPane(appModel: appModel)
        }
    }

    private func refreshAllSettingsContext() async {
        appModel.voiceDictation.refreshMicrophones()
        await appModel.refreshProviders()
        await appModel.refreshRemoteServer()
        if let runtime = appModel.runtime {
            if let snap = try? await runtime.fetchSettings() {
                appModel.settingsSnapshot = snap
            }
            if let limits = try? await runtime.fetchUsageLimits() {
                appModel.usageLimits = limits
            }
        }
    }
}
