import AppKit
import Foundation

public nonisolated enum ExternalAppKind: String, Codable, Sendable, Hashable {
    case editor
    case terminal
    case finder
}

public struct ExternalAppTarget: Identifiable, Hashable {
    public let id: String          // Bundle identifier
    public let name: String
    public let kind: ExternalAppKind
    public let appURL: URL
    public let cliExecutableURL: URL?

    public init(
        id: String,
        name: String,
        kind: ExternalAppKind,
        appURL: URL,
        cliExecutableURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.appURL = appURL
        self.cliExecutableURL = cliExecutableURL
    }

    public var icon: NSImage {
        let img = NSWorkspace.shared.icon(forFile: appURL.path)
        img.size = NSSize(width: 16, height: 16)
        return img
    }
}

@MainActor
public final class ExternalEditorService {
    public static let shared = ExternalEditorService()

    private struct CandidateSpec {
        let bundleID: String
        let name: String
        let fallbackBundleSubpath: String
        let kind: ExternalAppKind
        let cliNames: [String]
        let appRelativeCLIPath: String?
    }

    private static let candidates: [CandidateSpec] = [
        CandidateSpec(
            bundleID: "com.google.antigravity",
            name: "Antigravity",
            fallbackBundleSubpath: "Antigravity.app",
            kind: .editor,
            cliNames: ["agy", "antigravity"],
            appRelativeCLIPath: "Contents/Resources/app/bin/agy"
        ),
        CandidateSpec(
            bundleID: "com.apple.dt.Xcode",
            name: "Xcode",
            fallbackBundleSubpath: "Xcode.app",
            kind: .editor,
            cliNames: ["xed"],
            appRelativeCLIPath: nil
        ),
        CandidateSpec(
            bundleID: "com.todesktop.230313mzl4w4u92",
            name: "Cursor",
            fallbackBundleSubpath: "Cursor.app",
            kind: .editor,
            cliNames: ["cursor"],
            appRelativeCLIPath: "Contents/Resources/app/bin/cursor"
        ),
        CandidateSpec(
            bundleID: "dev.zed.Zed",
            name: "Zed",
            fallbackBundleSubpath: "Zed.app",
            kind: .editor,
            cliNames: ["zed"],
            appRelativeCLIPath: "Contents/MacOS/cli"
        ),
        CandidateSpec(
            bundleID: "com.microsoft.VSCode",
            name: "VS Code",
            fallbackBundleSubpath: "Visual Studio Code.app",
            kind: .editor,
            cliNames: ["code"],
            appRelativeCLIPath: "Contents/Resources/app/bin/code"
        ),
        CandidateSpec(
            bundleID: "com.exafunction.windsurf",
            name: "Windsurf",
            fallbackBundleSubpath: "Windsurf.app",
            kind: .editor,
            cliNames: ["windsurf"],
            appRelativeCLIPath: "Contents/Resources/app/bin/windsurf"
        ),
        CandidateSpec(
            bundleID: "com.sublimetext.4",
            name: "Sublime Text",
            fallbackBundleSubpath: "Sublime Text.app",
            kind: .editor,
            cliNames: ["subl"],
            appRelativeCLIPath: "Contents/SharedSupport/bin/subl"
        ),
        CandidateSpec(
            bundleID: "com.panic.Nova",
            name: "Nova",
            fallbackBundleSubpath: "Nova.app",
            kind: .editor,
            cliNames: ["nova"],
            appRelativeCLIPath: "Contents/SharedSupport/nova"
        ),
        CandidateSpec(
            bundleID: "com.barebones.bbedit",
            name: "BBEdit",
            fallbackBundleSubpath: "BBEdit.app",
            kind: .editor,
            cliNames: ["bbedit"],
            appRelativeCLIPath: "Contents/Helpers/bbedit_tool"
        ),
        CandidateSpec(
            bundleID: "com.google.android.studio",
            name: "Android Studio",
            fallbackBundleSubpath: "Android Studio.app",
            kind: .editor,
            cliNames: ["studio"],
            appRelativeCLIPath: "Contents/MacOS/studio"
        ),
        CandidateSpec(
            bundleID: "com.jetbrains.intellij",
            name: "IntelliJ IDEA",
            fallbackBundleSubpath: "IntelliJ IDEA.app",
            kind: .editor,
            cliNames: ["idea"],
            appRelativeCLIPath: "Contents/MacOS/idea"
        ),
        CandidateSpec(
            bundleID: "com.jetbrains.intellij.ce",
            name: "IntelliJ IDEA CE",
            fallbackBundleSubpath: "IntelliJ IDEA CE.app",
            kind: .editor,
            cliNames: ["idea"],
            appRelativeCLIPath: "Contents/MacOS/idea"
        ),
        CandidateSpec(
            bundleID: "com.mitchellh.ghostty",
            name: "Ghostty",
            fallbackBundleSubpath: "Ghostty.app",
            kind: .terminal,
            cliNames: ["ghostty"],
            appRelativeCLIPath: "Contents/MacOS/ghostty"
        ),
        CandidateSpec(
            bundleID: "com.googlecode.iterm2",
            name: "iTerm2",
            fallbackBundleSubpath: "iTerm.app",
            kind: .terminal,
            cliNames: [],
            appRelativeCLIPath: nil
        ),
        CandidateSpec(
            bundleID: "dev.warp.Warp-Stable",
            name: "Warp",
            fallbackBundleSubpath: "Warp.app",
            kind: .terminal,
            cliNames: [],
            appRelativeCLIPath: nil
        ),
        CandidateSpec(
            bundleID: "com.apple.Terminal",
            name: "Terminal",
            fallbackBundleSubpath: "Utilities/Terminal.app",
            kind: .terminal,
            cliNames: [],
            appRelativeCLIPath: nil
        ),
        CandidateSpec(
            bundleID: "com.apple.finder",
            name: "Finder",
            fallbackBundleSubpath: "CoreServices/Finder.app",
            kind: .finder,
            cliNames: [],
            appRelativeCLIPath: nil
        ),
    ]

    private let preferredEditorKey = "coincide.preferredExternalEditorBundleID"
    private let preferredTerminalKey = "coincide.preferredExternalTerminalBundleID"

    private init() {}

    public func discoverTargets() -> [ExternalAppTarget] {
        var found: [ExternalAppTarget] = []
        let homeApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let searchRoots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library"),
            homeApps,
        ]

        for spec in Self.candidates {
            let resolvedURL: URL? = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spec.bundleID) ?? {
                for root in searchRoots {
                    let candidate = root.appendingPathComponent(spec.fallbackBundleSubpath)
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                        return candidate
                    }
                }
                return nil
            }()

            guard let appURL = resolvedURL else { continue }
            let cliURL = resolveCLI(for: spec, appURL: appURL)
            found.append(
                ExternalAppTarget(
                    id: spec.bundleID,
                    name: spec.name,
                    kind: spec.kind,
                    appURL: appURL,
                    cliExecutableURL: cliURL
                )
            )
        }
        return found
    }

    public var installedEditors: [ExternalAppTarget] {
        discoverTargets().filter { $0.kind == .editor }
    }

    public var installedTerminals: [ExternalAppTarget] {
        discoverTargets().filter { $0.kind == .terminal }
    }

    public var finderTarget: ExternalAppTarget? {
        discoverTargets().first { $0.kind == .finder }
    }

    public var preferredEditor: ExternalAppTarget? {
        let editors = installedEditors
        if let saved = UserDefaults.standard.string(forKey: preferredEditorKey),
           let match = editors.first(where: { $0.id == saved }) {
            return match
        }
        return editors.first
    }

    public func setPreferredEditor(_ bundleID: String) {
        UserDefaults.standard.set(bundleID, forKey: preferredEditorKey)
    }

    public var preferredTerminal: ExternalAppTarget? {
        let terminals = installedTerminals
        if let saved = UserDefaults.standard.string(forKey: preferredTerminalKey),
           let match = terminals.first(where: { $0.id == saved }) {
            return match
        }
        return terminals.first
    }

    public func setPreferredTerminal(_ bundleID: String) {
        UserDefaults.standard.set(bundleID, forKey: preferredTerminalKey)
    }

    /// Expands `~` prefix to the current user's home directory if needed.
    public nonisolated static func expandedPath(_ rawPath: String) -> String {
        if rawPath == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if rawPath.hasPrefix("~/") {
            let suffix = String(rawPath.dropFirst(2))
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(suffix).path
        }
        return rawPath
    }

    /// Opens a file or folder in the specified `ExternalAppTarget`, jumping directly to `line` (and optional `column`)
    /// when supported by the target editor's CLI launcher.
    public func open(
        path rawPath: String,
        line: Int? = nil,
        column: Int? = nil,
        in target: ExternalAppTarget
    ) throws {
        let resolvedPath = Self.expandedPath(rawPath)
        let fileURL = URL(fileURLWithPath: resolvedPath)

        if target.kind == .finder {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDir), !isDir.boolValue {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } else {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: resolvedPath)
            }
            return
        }

        if let line, line > 0, target.kind == .editor,
           try launchWithLineNumber(target: target, path: resolvedPath, line: line, column: column) {
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([fileURL], withApplicationAt: target.appURL, configuration: config)
    }

    public func revealInFinder(path rawPath: String) {
        let resolvedPath = Self.expandedPath(rawPath)
        let url = URL(fileURLWithPath: resolvedPath)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDir), !isDir.boolValue {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: resolvedPath)
        }
    }

    // MARK: - Private CLI Resolution & Line Jump

    private func resolveCLI(for spec: CandidateSpec, appURL: URL) -> URL? {
        if let rel = spec.appRelativeCLIPath {
            let bundled = appURL.appendingPathComponent(rel)
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init) + ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]

        for cli in spec.cliNames {
            for dir in pathDirs {
                let candidate = URL(fileURLWithPath: dir).appendingPathComponent(cli)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func launchWithLineNumber(
        target: ExternalAppTarget,
        path: String,
        line: Int,
        column: Int?
    ) throws -> Bool {
        let colSuffix = column.map { ":\(max(1, $0))" } ?? ""
        switch target.id {
        case "com.apple.dt.Xcode":
            let xed = target.cliExecutableURL ?? URL(fileURLWithPath: "/usr/bin/xed")
            guard FileManager.default.isExecutableFile(atPath: xed.path) else { return false }
            try runDetachedProcess(executable: xed, arguments: ["--line", "\(line)", path])
            return true

        case "com.google.antigravity",
             "com.todesktop.230313mzl4w4u92",
             "com.microsoft.VSCode",
             "com.exafunction.windsurf":
            guard let cli = target.cliExecutableURL else { return false }
            try runDetachedProcess(executable: cli, arguments: ["--goto", "\(path):\(line)\(colSuffix)"])
            return true

        case "dev.zed.Zed":
            guard let cli = target.cliExecutableURL else { return false }
            try runDetachedProcess(executable: cli, arguments: ["\(path):\(line)\(colSuffix)"])
            return true

        case "com.sublimetext.4", "com.panic.Nova":
            guard let cli = target.cliExecutableURL else { return false }
            try runDetachedProcess(executable: cli, arguments: ["\(path):\(line)\(colSuffix)"])
            return true

        case "com.barebones.bbedit":
            guard let cli = target.cliExecutableURL else { return false }
            try runDetachedProcess(executable: cli, arguments: ["+\(line)", path])
            return true

        case "com.google.android.studio", "com.jetbrains.intellij", "com.jetbrains.intellij.ce":
            guard let cli = target.cliExecutableURL else { return false }
            try runDetachedProcess(executable: cli, arguments: ["--line", "\(line)", path])
            return true

        default:
            return false
        }
    }

    private func runDetachedProcess(executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
