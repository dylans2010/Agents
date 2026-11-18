import CoincideRemoteKit
import StoreKit
import SwiftUI
import UIKit

extension CommunityLink {
    var title: String {
        switch self {
        case .reportIssue: String(localized: "Report an Issue")
        case .requestFeature: String(localized: "Request a Feature")
        case .starOnGitHub: String(localized: "Star on GitHub")
        case .upvoteOnProductHunt: String(localized: "Upvote on Product Hunt")
        }
    }

    /// The account or address shown at the row's end.
    var detail: String? {
        nil
    }

    var symbol: String {
        switch self {
        case .reportIssue: "ladybug.fill"
        case .requestFeature: "lightbulb.fill"
        case .starOnGitHub: "star.fill"
        case .upvoteOnProductHunt: "arrowtriangle.up.fill"
        }
    }

    /// The tile's color, by `MacSettingsLabel.color` name.
    var color: String {
        switch self {
        case .reportIssue: "red"
        case .requestFeature: "orange"
        case .starOnGitHub: "gray"
        case .upvoteOnProductHunt: "orange"
        }
    }

    /// Words Settings search also finds the link by.
    var keywords: [String] {
        switch self {
        case .reportIssue: [String(localized: "Bug"), String(localized: "Feedback"), "GitHub", "bug", "issue"]
        case .requestFeature: [String(localized: "Idea"), String(localized: "Feedback"), "GitHub", "feature"]
        case .starOnGitHub: ["GitHub", "source", "open source", "MIT"]
        case .upvoteOnProductHunt: ["Product Hunt", "upvote", "vote", "launch"]
        }
    }

    /// The heading the links of `group` are under.
    static func title(of group: Group) -> String {
        switch group {
        case .community: String(localized: "Help & Community")
        }
    }

    /// Where the link goes from the phone. A bug report's form names the Mac's Coincide and macOS from its About pane
    /// when the phone has read it, and this app's and this device's own versions.
    func remoteURL(_ client: RemoteClient) -> URL {
        guard self == .reportIssue else { return url() }
        let about = client.macSettings?.page("about")?.sections.flatMap(\.rows) ?? []
        let mac = about.first { $0.id == "about.version" }?.detail ?? client.server?.appVersion
        let macOS = about.first { $0.id == "about.macos" }?.detail.map { "macOS \($0)" }
        let info = Bundle.main.infoDictionary ?? [:]
        let remote = Self.appVersion(info["CFBundleShortVersionString"] as? String, build: info["CFBundleVersion"] as? String)
            ?? RemoteClient.appVersion
        let system = Self.systemVersion(ProcessInfo.processInfo.operatingSystemVersion)
        let systemName = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        return url(
            coincideVersion: Self.remoteCoincideVersion(mac: mac, remote: remote, system: system, systemName: systemName),
            macOSVersion: macOS)
    }
}

struct HelpCommunityRows: View {
    var body: some View {
        ForEach(CommunityLink.Group.allCases, id: \.self) { group in
            SidebarHeader(Text(CommunityLink.title(of: group))).sidebarRow()
            ForEach(CommunityLink.links(in: group, on: .remote)) { link in CommunityLinkRow(link: link) }
            if group == .community { RateRemoteRow() }
        }
    }
}

struct CommunityLinkRow: View {
    let link: CommunityLink
    @Environment(RemoteClient.self) private var client
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(link.remoteURL(client))
        } label: {
            SettingsTileLabel(title: link.title, symbol: link.symbol, color: link.color, detail: link.detail, opensLink: true)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .accessibilityHint(hint)
        .sidebarRow()
    }

    private var hint: Text {
        switch link {
        case .reportIssue, .requestFeature: Text("Opens the GitHub issue form")
        default: Text("Opens in your browser")
        }
    }
}

/// Rate Coincide Remote: iOS's review prompt, or the App Store's review page when the prompt was asked for recently
/// and the app has one (`RemoteReview`). Only on a tap; the app never asks by itself.
struct RateRemoteRow: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @AppStorage("review.lastPrompt") private var lastPrompt: Double = 0

    var body: some View {
        Button {
            let last = lastPrompt > 0 ? Date(timeIntervalSince1970: lastPrompt) : nil
            if let page = RemoteReview.storePage(lastPrompt: last) {
                openURL(page)
            } else {
                lastPrompt = Date().timeIntervalSince1970
                requestReview()
            }
        } label: {
            SettingsTileLabel(title: String(localized: "Rate Coincide"), symbol: "star.bubble.fill", color: "yellow")
        }
        .buttonStyle(SidebarRowButtonStyle())
        .accessibilityHint(Text("Asks iOS to show its review prompt"))
        .sidebarRow()
    }
}
