import AppKit
import CoincideRemoteKit
import SwiftUI

// MARK: - Appearance Preference

public nonisolated enum AppearancePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Native macOS Semantic Design Tokens

public enum AppTheme {
    // Semantic Surfaces (Automatically adapt to macOS Light & Dark Mode)
    public static var windowBackground: Color { Color(nsColor: .windowBackgroundColor) }
    public static var underPageBackground: Color { Color(nsColor: .underPageBackgroundColor) }
    public static var controlBackground: Color { Color(nsColor: .controlBackgroundColor) }
    public static var textBackground: Color { Color(nsColor: .textBackgroundColor) }
    public static var selectedContentBackground: Color { Color(nsColor: .selectedContentBackgroundColor) }
    public static var unemphasizedSelectedBackground: Color { Color(nsColor: .unemphasizedSelectedContentBackgroundColor) }

    // Semantic Borders & Dividers
    public static var separator: Color { Color(nsColor: .separatorColor) }
    public static var grid: Color { Color(nsColor: .gridColor) }

    // Semantic Ink / Labels
    public static var primaryLabel: Color { Color(nsColor: .labelColor) }
    public static var secondaryLabel: Color { Color(nsColor: .secondaryLabelColor) }
    public static var tertiaryLabel: Color { Color(nsColor: .tertiaryLabelColor) }
    public static var quaternaryLabel: Color { Color(nsColor: .quaternaryLabelColor) }

    // Brand & Semantic Accents
    public static var accent: Color { Color("AccentColor") }
    public static var onAccent: Color { .white }
    public static var success: Color { Color(nsColor: .systemGreen) }
    public static var warning: Color { Color(nsColor: .systemOrange) }
    public static var danger: Color { Color(nsColor: .systemRed) }
    public static var info: Color { Color(nsColor: .systemBlue) }

    // Diff Colors
    public static var diffAdditionText: Color { Color(nsColor: .systemGreen) }
    public static var diffDeletionText: Color { Color(nsColor: .systemRed) }
    public static var diffAdditionBackground: Color { Color(nsColor: .systemGreen).opacity(0.12) }
    public static var diffDeletionBackground: Color { Color(nsColor: .systemRed).opacity(0.12) }
    public static var diffHunkHeaderBackground: Color { Color(nsColor: .systemBlue).opacity(0.10) }

    public static var findHighlightBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.systemYellow.withAlphaComponent(isDark ? 0.20 : 0.14)
        })
    }

    public static var findHighlightBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.systemYellow.withAlphaComponent(isDark ? 0.75 : 0.65)
        })
    }

    public static var searchMatchHighlight: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.systemYellow.withAlphaComponent(isDark ? 0.42 : 0.34)
        })
    }

    public static var favoriteStar: Color { Color(nsColor: .systemYellow) }

    public static var merged: Color { Color(nsColor: .systemPurple) }

    public static var favoriteHeart: Color { Color(nsColor: .systemPink) }

    // Card & Subtle Elevation Tokens
    public static var elevatedCardFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor.white.withAlphaComponent(0.045)
                : NSColor.black.withAlphaComponent(0.03)
        })
    }

    public static var subtleHoverFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor.white.withAlphaComponent(0.065)
                : NSColor.black.withAlphaComponent(0.045)
        })
    }

    public static var codeBlockBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.09, green: 0.095, blue: 0.11, alpha: 1.0)
                : NSColor(srgbRed: 0.955, green: 0.96, blue: 0.97, alpha: 1.0)
        })
    }

    // Typography Helpers
    public nonisolated static func replyFont(scale: Double = 1.0, usesSerif: Bool = true) -> Font {
        let size = CGFloat(14.0 * max(0.8, min(1.5, scale)))
        return .system(size: size, weight: .regular, design: usesSerif ? .serif : .default)
    }

    public nonisolated static func bodyFont(scale: Double = 1.0) -> Font {
        let size = CGFloat(13.0 * max(0.8, min(1.5, scale)))
        return .system(size: size, weight: .regular, design: .default)
    }

    public nonisolated static func codeFont(scale: Double = 1.0, size baseSize: Double = 12.5) -> Font {
        let size = CGFloat(baseSize * max(0.8, min(1.5, scale)))
        return .system(size: size, weight: .regular, design: .monospaced)
    }

    // Layout Metrics
    public nonisolated static let cornerRadiusSmall: CGFloat = 6
    public nonisolated static let cornerRadiusMedium: CGFloat = 10
    public nonisolated static let cornerRadiusLarge: CGFloat = 14
    public nonisolated static let sidebarMinWidth: CGFloat = 232
    public nonisolated static let sidebarIdealWidth: CGFloat = 264
    public nonisolated static let inspectorMinWidth: CGFloat = 300
    public nonisolated static let inspectorIdealWidth: CGFloat = 360
    public nonisolated static let conversationColumnMaxWidth: CGFloat = 800
}

// MARK: - Hex Color Initializer

public extension Color {
    nonisolated init(srgbHex hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

public extension NSColor {
    static func fromSRGBHex(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

// MARK: - Agent Branding

public enum AgentBranding {
    public nonisolated static func normalizedID(_ provider: String?) -> String {
        (provider ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public nonisolated static func displayName(for provider: String?) -> String {
        switch normalizedID(provider) {
        case "antigravity": "Antigravity"
        case "claude": "Claude Code"
        case "codex": "Codex"
        case "cursor": "Cursor"
        case "grok": "Grok Build"
        case "opencode": "OpenCode"
        case let other where other.hasPrefix("acp-"):
            String(other.dropFirst(4)).replacingOccurrences(of: "-", with: " ").capitalized
        case let other where !other.isEmpty:
            other.capitalized
        default:
            "Agent"
        }
    }

    /// Asset name inside `Agents/Resources/Assets.xcassets`, or `nil` for custom ACP providers.
    public nonisolated static func assetName(for provider: String?) -> String? {
        switch normalizedID(provider) {
        case "antigravity": "AgentAntigravity"
        case "claude": "AgentClaude"
        case "codex": "AgentCodex"
        case "cursor": "AgentCursor"
        case "grok": "AgentGrok"
        case "opencode": "AgentOpenCode"
        default: nil
        }
    }

    /// Antigravity and Claude marks carry multi-tone/brand fills and use `.original` rendering;
    /// monochrome vector marks (`Codex`, `Cursor`, `Grok`, `OpenCode`) use `.template`.
    public nonisolated static func keepsOriginalColors(for provider: String?) -> Bool {
        let id = normalizedID(provider)
        return id == "antigravity" || id == "claude"
    }

    /// Adaptive macOS `Color` matching `RemotePalette.agentColor` in Light and Dark mode.
    public static func color(for provider: String?) -> Color {
        let pair = RemotePalette.agentColor(normalizedID(provider))
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.fromSRGBHex(isDark ? pair.dark : pair.light)
        })
    }

    public nonisolated static func color(for provider: String?, colorScheme: ColorScheme) -> Color {
        let pair = RemotePalette.agentColor(normalizedID(provider))
        return Color(srgbHex: colorScheme == .dark ? pair.dark : pair.light)
    }

    @ViewBuilder
    public static func icon(
        for provider: String?,
        size: CGFloat = 16,
        monochromeTint: Color? = nil
    ) -> some View {
        AgentLogoView(provider: provider, size: size, monochromeTint: monochromeTint)
    }
}

/// Renders an agent's crisp asset mark with proper `.original` vs `.template` rendering mode,
/// falling back to a stylized SF Symbol badge for custom ACP registry agents.
public struct AgentLogoView: View {
    public let provider: String?
    public var size: CGFloat = 16
    public var monochromeTint: Color? = nil

    public init(provider: String?, size: CGFloat = 16, monochromeTint: Color? = nil) {
        self.provider = provider
        self.size = size
        self.monochromeTint = monochromeTint
    }

    public var body: some View {
        if let asset = AgentBranding.assetName(for: provider) {
            Image(asset)
                .resizable()
                .renderingMode(AgentBranding.keepsOriginalColors(for: provider) ? .original : .template)
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(monochromeTint ?? AppTheme.primaryLabel)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "terminal.fill")
                .font(.system(size: max(10, size * 0.78), weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(monochromeTint ?? AgentBranding.color(for: provider))
                .accessibilityHidden(true)
        }
    }
}

/// Renders a Agents Bot character (`BotArtwork` from `CoincideRemoteKit`) via SwiftUI `Canvas`.
public struct BotAvatarView: View {
    public let avatar: RemoteBotAvatar?
    public var size: CGFloat = 24
    public var eyeOpenness: CGFloat = 1.0

    public init(avatar: RemoteBotAvatar?, size: CGFloat = 24, eyeOpenness: CGFloat = 1.0) {
        self.avatar = avatar
        self.size = size
        self.eyeOpenness = eyeOpenness
    }

    public var body: some View {
        let character = avatar?.artCharacter ?? .alien
        let tint = avatar?.artTint ?? character.defaultTint
        Canvas { context, canvasSize in
            context.withCGContext { cgContext in
                BotArtwork.draw(
                    character,
                    tint: tint,
                    in: cgContext,
                    rect: CGRect(origin: .zero, size: canvasSize),
                    openness: eyeOpenness
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

public extension View {
    func glassPanel(cornerRadius: CGFloat = AppTheme.cornerRadiusMedium) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    func glassCapsule() -> some View {
        glassEffect(.regular, in: Capsule())
    }

    func glassPanelTinted(_ tint: Color, cornerRadius: CGFloat = AppTheme.cornerRadiusMedium) -> some View {
        glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
