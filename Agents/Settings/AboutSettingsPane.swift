import AppKit
import CoincideRemoteKit
import SwiftUI

public struct AboutSettingsPane: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var dataDirectory: String {
        if !appModel.status.dataDir.isEmpty {
            return appModel.status.dataDir
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Coincide")
            .path
    }

    private var readyProvidersCount: Int {
        appModel.providers.filter { $0.isEnabled && ($0.isApproved || $0.state == "ready") }.count
    }

    public var body: some View {
        Form {
            heroSection
            architectureSection
            providersSummarySection
            linksSection
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }

    // MARK: - 1. AppIcon Hero Card

    private var heroSection: some View {
        Section {
            HStack(spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Agents")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppTheme.primaryLabel)

                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }

                    Text("Native macOS Multi-Agent Coding Workspace")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.primaryLabel)

                    Text("Built natively with SwiftUI + AppKit on macOS and powered by the coincide-core Rust runtime.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }

                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - 2. Runtime & Data Store Details

    private var architectureSection: some View {
        Section {
            LabeledContent("UI Stack") {
                Text("100% Native SwiftUI + AppKit (Zero WebViews)")
                    .font(.system(size: 12, weight: .medium))
            }

            LabeledContent("Engine Runtime") {
                Text("coincide-core + coincide-macos-ffi (Rust Static FFI)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            LabeledContent("Remote Protocol") {
                Text("CoincideRemoteKit v\(RemoteProtocol.version) (mTLS 1.3)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            LabeledContent("Data Store") {
                HStack(spacing: 8) {
                    Text(dataDirectory)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Button("Reveal") {
                        appModel.externalEditors.revealInFinder(path: dataDirectory)
                    }
                    .controlSize(.mini)
                }
            }
        } header: {
            Text("Runtime Architecture")
        }
    }

    // MARK: - 3. Active Providers Summary

    private var providersSummarySection: some View {
        Section {
            LabeledContent("Configured Agents") {
                Text("\(readyProvidersCount) ready of \(appModel.providers.count) registered")
                    .font(.system(size: 12, weight: .medium))
            }

            if !appModel.providers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appModel.providers) { provider in
                            HStack(spacing: 6) {
                                AgentLogoView(provider: provider.id, size: 14)
                                Text(provider.displayName)
                                    .font(.system(size: 11.5, weight: .medium))
                                Circle()
                                    .fill(
                                        (provider.isEnabled && (provider.isApproved || provider.state == "ready"))
                                            ? AppTheme.success
                                            : AppTheme.tertiaryLabel
                                    )
                                    .frame(width: 6, height: 6)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(AppTheme.elevatedCardFill)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(AppTheme.separator, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Active Providers")
        }
    }

    // MARK: - 4. Documentation & Project Links

    private var linksSection: some View {
        Section {
            HStack(spacing: 10) {
                externalLinkButton(
                    title: "GitHub Repository",
                    icon: "chevron.left.forwardslash.chevron.right",
                    url: "https://github.com/apoorvdarshan/coincide"
                )
                externalLinkButton(
                    title: "Antigravity ACP Docs",
                    icon: "sparkles",
                    url: "https://antigravity.google/docs/ide/extensions/acp"
                )
                externalLinkButton(
                    title: "Changelog",
                    icon: "clock.arrow.circlepath",
                    url: "https://github.com/apoorvdarshan/coincide/releases"
                )
                externalLinkButton(
                    title: "License",
                    icon: "doc.plaintext",
                    url: "https://github.com/apoorvdarshan/coincide/blob/main/LICENSE"
                )
                Spacer()
            }
            .padding(.vertical, 2)
        } header: {
            Text("Resources & Links")
        }
    }

    private func externalLinkButton(title: String, icon: String, url: String) -> some View {
        Button {
            if let resolved = URL(string: url) {
                NSWorkspace.shared.open(resolved)
            }
        } label: {
            Label(title, systemImage: icon)
        }
        .controlSize(.small)
    }
}
