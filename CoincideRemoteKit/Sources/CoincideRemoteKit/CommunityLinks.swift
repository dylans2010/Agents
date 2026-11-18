import Foundation

public enum CoincideLinks {
    public static let repository = URL(string: "https://github.com/dylans2010/Agents")!
    /// Coincide's page on Product Hunt, to upvote it.
    public static let productHunt = URL(string: "https://www.producthunt.com/products/coincide")!
    /// Coincide Remote's "Write a Review" page on the App Store, opened when the in-app review prompt was asked for
    /// recently (`RemoteReview`). Nil until the app is on the App Store, so Rate always asks for the prompt.
    public static let remoteAppStoreReview: URL? = nil
}

public enum CommunityLink: String, CaseIterable, Sendable, Identifiable {
    case reportIssue
    case requestFeature
    case starOnGitHub
    /// Coincide's Product Hunt page, to upvote it.
    case upvoteOnProductHunt

    /// The app listing the links.
    public enum Platform: Sendable {
        case mac
        /// Coincide Remote on iPhone and iPad.
        case remote
    }

    public enum Group: String, CaseIterable, Sendable {
        case community
    }

    public var id: String { rawValue }

    public var group: Group {
        .community
    }

    public func isOffered(on platform: Platform) -> Bool {
        true
    }

    /// The links the app on `platform` lists, in order.
    public static func offered(on platform: Platform) -> [CommunityLink] { allCases.filter { $0.isOffered(on: platform) } }

    /// The links of `group` the app on `platform` lists, in order.
    public static func links(in group: Group, on platform: Platform) -> [CommunityLink] {
        offered(on: platform).filter { $0.group == group }
    }

    /// The issue form's file in `.github/ISSUE_TEMPLATE`, for the two that open one.
    public var template: String? {
        switch self {
        case .reportIssue: "bug_report.yml"
        case .requestFeature: "feature_request.yml"
        default: nil
        }
    }

    /// Ids of the bug report form's fields that a link fills in.
    public enum Field {
        public static let macOSVersion = "macos-version"
        public static let coincideVersion = "coincide-version"
    }

    /// Longest value a link puts in a field; the forms' version fields are one line.
    public static let maxFieldLength = 120

    /// Where the link goes; for a report, its GitHub form. A bug report fills in its "Coincide version" and "macOS
    /// version" fields with what is given; empty values are left out, and nothing else takes any.
    public func url(coincideVersion: String? = nil, macOSVersion: String? = nil) -> URL {
        switch self {
        case .starOnGitHub: return CoincideLinks.repository
        case .upvoteOnProductHunt: return CoincideLinks.productHunt
        case .reportIssue, .requestFeature: break
        }
        var components = URLComponents(
            url: CoincideLinks.repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "template", value: template)]
        if self == .reportIssue {
            for (field, value) in [(Field.coincideVersion, coincideVersion), (Field.macOSVersion, macOSVersion)] {
                guard let value = Self.fieldValue(value) else { continue }
                items.append(URLQueryItem(name: field, value: value))
            }
        }
        components.queryItems = items
        // URLComponents leaves "+" alone in queries, where GitHub reads it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// A field's value on one line, trimmed and cut to `maxFieldLength`; nil when nothing is left.
    static func fieldValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let line = value.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(maxFieldLength))
    }

    // MARK: Versions

    /// An app's version as the form's placeholder writes it: "0.1.0 (1)", or just "0.1.0" without a build number.
    public static func appVersion(_ version: String?, build: String?) -> String? {
        let version = fieldValue(version)
        let build = fieldValue(build)
        switch (version, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        default: return nil
        }
    }

    /// A system's version as Apple writes it, "26.1" or "26.1.2", followed by its build when known: "26.1 (25B78)".
    public static func systemVersion(_ version: OperatingSystemVersion, build: String? = nil) -> String {
        var number = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion != 0 { number += ".\(version.patchVersion)" }
        guard let build = fieldValue(build) else { return number }
        return "\(number) (\(build))"
    }

    /// The bug report's "Coincide version" from Coincide Remote: the Mac's Coincide when the phone knows it, then the
    /// phone's own app and system, "0.1.0 (12) · Coincide Remote 1.0 (3) on iOS 26.1".
    public static func remoteCoincideVersion(mac: String?, remote: String, system: String, systemName: String = "iOS") -> String {
        let phone = "Coincide Remote \(remote) on \(systemName) \(system)"
        guard let mac = fieldValue(mac) else { return phone }
        return "\(mac) · \(phone)"
    }
}

/// Rate Coincide Remote: iOS's own review prompt, which it shows only a few times a year, so a second tap soon after
/// opens the App Store's review page instead, once the app has one (`CoincideLinks.remoteAppStoreReview`). Only when
/// the user taps Rate; the app never asks on its own.
public enum RemoteReview {
    /// How long after asking for the prompt a tap opens the App Store page instead.
    public static let promptInterval: TimeInterval = 122 * 24 * 60 * 60

    /// The App Store page to open, or nil to ask for the prompt.
    public static func storePage(lastPrompt: Date?, now: Date = Date(), page: URL? = CoincideLinks.remoteAppStoreReview) -> URL? {
        guard let page, let lastPrompt, now.timeIntervalSince(lastPrompt) < promptInterval else { return nil }
        return page
    }
}
