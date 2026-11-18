import AppKit
import CoincideRemoteKit
import SwiftUI

struct WelcomeWorkspaceView: View {
    @Bindable var appModel: AppModel
    @Environment(\.openSettings) private var openSettings

    private struct PromptSuggestion: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let prompt: String
    }

    private static let starterSuggestions: [PromptSuggestion] = [
        PromptSuggestion(
            id: "architecture",
            title: "Map Architecture",
            subtitle: "Summarize modules, entry points & data flow",
            icon: "square.3.layers.3d",
            prompt: "Walk me through the architecture of this repository: key targets/crates, entry points, state flow, and how components communicate."
        ),
        PromptSuggestion(
            id: "review-changes",
            title: "Review Uncommitted Diff",
            subtitle: "Spot regressions, edge cases & concurrency bugs",
            icon: "magnifyingglass.circle",
            prompt: "Review all uncommitted git changes in this workspace for correctness, concurrency safety, edge cases, and missing test coverage."
        ),
        PromptSuggestion(
            id: "fix-tests",
            title: "Run & Fix Failing Tests",
            subtitle: "Execute test suite and repair any failures",
            icon: "checkmark.seal",
            prompt: "Run the project's test suite, diagnose any failing or flaky tests, and fix the underlying root causes."
        ),
        PromptSuggestion(
            id: "plan-feature",
            title: "Plan a New Feature",
            subtitle: "Draft a step-by-step implementation blueprint",
            icon: "list.bullet.clipboard",
            prompt: "Help me design and plan a clean, incremental implementation for: "
        ),
    ]

    private var nonChatProjects: [RemoteProject] {
        appModel.workspace.projects.filter { !$0.isChats }
    }

    private var antigravityProvider: DesktopProviderInfo? {
        appModel.providers.first { AgentBranding.normalizedID($0.id) == "antigravity" }
    }

    private var antigravityConfiguredAccounts: [ProviderKeyAccountInfo] {
        guard let ag = antigravityProvider else { return [] }
        var map: [String: ProviderKeyAccountInfo] = [:]
        for acc in ag.keyAccounts where acc.hasKey {
            map[acc.id] = acc
        }
        for acc in (ag.antigravityStatus?.accounts ?? []) where acc.hasKey {
            if map[acc.id] == nil {
                map[acc.id] = acc
            }
        }
        return map.values.sorted { $0.name < $1.name }
    }

    private var isAntigravityConfigured: Bool {
        if !antigravityConfiguredAccounts.isEmpty { return true }
        if let ag = antigravityProvider, ag.state == "ready" { return true }
        if let remoteAG = appModel.workspace.providers.first(where: { $0.id == "antigravity" }), remoteAG.isReady {
            return true
        }
        return false
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 26) {
                Spacer(minLength: 12)

                // Brand Hero & Active Project Selector
                VStack(spacing: 12) {
                    Image("BrandMark")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(AppTheme.primaryLabel)
                        .padding(10)
                        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 1)
                        )

                    VStack(spacing: 4) {
                        Text("Agents")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryLabel)

                        Text("Native multi-agent workspace for macOS")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }

                    // Active Project Selector Pill
                    HStack(spacing: 8) {
                        if nonChatProjects.isEmpty {
                            Button {
                                appModel.promptAddProjectFolder()
                            } label: {
                                Label("Add Project Folder…", systemImage: "folder.badge.plus")
                                    .font(.system(size: 12.5, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        } else {
                            Menu {
                                Section("Switch Active Project") {
                                    ForEach(nonChatProjects) { project in
                                        Button {
                                            Task {
                                                if let existing = appModel.workspace.threads.first(where: {
                                                    $0.projectID == project.id && !$0.isArchived && $0.itemCount == 0
                                                }) {
                                                    appModel.selectThread(existing.id)
                                                } else {
                                                    _ = await appModel.createNewThread(in: project.id)
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Text(project.name)
                                                if appModel.selectedProject?.id == project.id {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Button {
                                    appModel.promptAddProjectFolder()
                                } label: {
                                    Label("Add Project Folder…", systemImage: "folder.badge.plus")
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(AppTheme.accent)
                                    Text(appModel.selectedProject?.name ?? "Select Project")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(AppTheme.primaryLabel)
                                    if let path = appModel.selectedProject?.path, !path.isEmpty {
                                        Text(path)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(AppTheme.tertiaryLabel)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(maxWidth: 220)
                                    }
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(AppTheme.tertiaryLabel)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppTheme.elevatedCardFill, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(AppTheme.separator, lineWidth: 1)
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()

                            Button {
                                appModel.promptAddProjectFolder()
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .padding(6)
                                    .background(AppTheme.elevatedCardFill, in: Circle())
                                    .overlay(Circle().strokeBorder(AppTheme.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help("Add Project Folder…")
                            .accessibilityLabel("Add project folder")
                        }
                    }
                    .padding(.top, 2)
                }

                daemonStatusCard

                // Google Antigravity Status Card
                antigravityStatusCard

                // Starter Bots Row
                starterBotsSection

                // Clickable Prompt Suggestions Grid
                VStack(alignment: .leading, spacing: 10) {
                    Text("QUICK START PROMPTS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.tertiaryLabel)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                        ],
                        spacing: 10
                    ) {
                        ForEach(Self.starterSuggestions) { item in
                            Button {
                                appModel.insertTextIntoComposer(item.prompt)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.accent)
                                        .frame(width: 28, height: 28)
                                        .background(AppTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(AppTheme.primaryLabel)
                                        Text(item.subtitle)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(AppTheme.secondaryLabel)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                        .strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var daemonStatusCard: some View {
        switch appModel.daemonConnectionStatus {
        case .connected, .checking:
            HStack(spacing: 8) {
                if appModel.daemonConnectionStatus == .checking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Circle()
                        .fill(AppTheme.success)
                        .frame(width: 7, height: 7)
                }
                Text(appModel.daemonConnectionStatus.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppTheme.elevatedCardFill, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 1)
            )
        case .unreachable(let detail), .misconfigured(let detail):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                    Text(appModel.daemonConnectionStatus.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button {
                        Task { await appModel.retryDaemonConnection() }
                    } label: {
                        Label("Retry Connection", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    Button {
                        openGeneralSettings()
                    } label: {
                        Text("Open Settings")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .padding(15)
            .frame(maxWidth: 680, alignment: .leading)
            .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                    .strokeBorder(AppTheme.separator.opacity(0.85), lineWidth: 1)
            )
        }
    }

    // MARK: - Google Antigravity Status Card

    @ViewBuilder
    private var antigravityStatusCard: some View {
        let accounts = antigravityConfiguredAccounts

        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(AgentBranding.color(for: "antigravity").opacity(0.12))
                    .frame(width: 42, height: 42)
                AgentLogoView(provider: "antigravity", size: 24)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Google Antigravity")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)

                    if isAntigravityConfigured {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppTheme.success)
                                .frame(width: 6.5, height: 6.5)
                            Text("Ready")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.success)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.success.opacity(0.12), in: Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppTheme.warning)
                                .frame(width: 6.5, height: 6.5)
                            Text("API Key Needed")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.warning)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.warning.opacity(0.12), in: Capsule())
                    }
                }

                if isAntigravityConfigured {
                    let acctSummary = accounts.first.map { "Authenticated with Gemini API key (\($0.name))" }
                        ?? "Configured and ready for Gemini-powered agentic workflows."
                    Text(acctSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                } else {
                    Text("Connect a Google AI Studio or Gemini Enterprise API key (GEMINI_API_KEY) to run Antigravity safely.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if isAntigravityConfigured {
                Button {
                    openAntigravitySettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Open Antigravity Settings")
                .accessibilityLabel("Open Antigravity settings")
            } else {
                Button {
                    openAntigravitySettings()
                } label: {
                    Label("Configure Antigravity…", systemImage: "key.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(15)
        .frame(maxWidth: 680, alignment: .leading)
        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                .strokeBorder(AppTheme.separator.opacity(0.85), lineWidth: 1)
        )
    }

    // MARK: - Starter Bots Section

    @ViewBuilder
    private var starterBotsSection: some View {
        let bots = appModel.workspace.bots ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SPECIALIST BOTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                Spacer()
                Button {
                    appModel.openBotEditor(for: nil)
                } label: {
                    Label("New Bot", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }

            if bots.isEmpty {
                Button {
                    appModel.openBotEditor(for: nil)
                } label: {
                    HStack(spacing: 10) {
                        BotAvatarView(avatar: RemoteBotAvatar(.alien, .mint), size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create a Reusable Specialist Bot")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(AppTheme.primaryLabel)
                            Text("Pin standing instructions, preferred model, and folder permissions for one-click workflows.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    .padding(11)
                    .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                            .strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(bots) { bot in
                            Button {
                                Task { await appModel.startBotConversation(bot.id) }
                            } label: {
                                HStack(spacing: 9) {
                                    BotAvatarView(avatar: bot.avatar, size: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bot.name)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(AppTheme.primaryLabel)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                        .strokeBorder(AppTheme.separator.opacity(0.8), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    // MARK: - Actions

    private func openAntigravitySettings() {
        appModel.selectedSettingsTab = .antigravity
        openSettings()
    }

    private func openGeneralSettings() {
        appModel.selectedSettingsTab = .general
        openSettings()
    }
}
