import AppKit
import CoincideRemoteKit
import Foundation
import SwiftUI

// MARK: - Parsed Markdown AST

nonisolated enum NativeMarkdownTableAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

nonisolated struct NativeMarkdownListItem: Equatable, Sendable {
    var marker: String
    var isTask: Bool
    var isChecked: Bool
    var text: String
    var depth: Int
}

nonisolated struct NativeMarkdownTableData: Equatable, Sendable {
    var headers: [String]
    var alignments: [NativeMarkdownTableAlignment]
    var rows: [[String]]

    var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var tsvRepresentation: String {
        var lines: [String] = []
        if !headers.isEmpty {
            lines.append(headers.joined(separator: "\t"))
        }
        for row in rows {
            lines.append(row.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }
}

nonisolated enum NativeMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([NativeMarkdownListItem])
    case blockquote(String)
    case codeBlock(language: String?, code: String)
    case table(NativeMarkdownTableData)
    case thematicBreak

    static func parse(_ source: String) -> [NativeMarkdownBlock] {
        guard !source.isEmpty else { return [] }
        let rawLines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        var blocks: [NativeMarkdownBlock] = []
        var paragraphBuffer: [String] = []
        var listBuffer: [NativeMarkdownListItem] = []
        var quoteBuffer: [String] = []

        var fenceMarker: String? = nil
        var codeLanguage: String? = nil
        var codeBuffer: [String] = []

        func flushPending() {
            if !paragraphBuffer.isEmpty {
                blocks.append(.paragraph(paragraphBuffer.joined(separator: "\n")))
                paragraphBuffer.removeAll(keepingCapacity: true)
            }
            if !listBuffer.isEmpty {
                blocks.append(.list(listBuffer))
                listBuffer.removeAll(keepingCapacity: true)
            }
            if !quoteBuffer.isEmpty {
                blocks.append(.blockquote(quoteBuffer.joined(separator: "\n")))
                quoteBuffer.removeAll(keepingCapacity: true)
            }
        }

        var idx = 0
        while idx < rawLines.count {
            let line = rawLines[idx]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Active fenced code block
            if let activeFence = fenceMarker {
                if trimmed.hasPrefix(activeFence),
                   trimmed.dropFirst(activeFence.count).trimmingCharacters(in: .whitespaces).isEmpty
                {
                    blocks.append(.codeBlock(language: codeLanguage, code: codeBuffer.joined(separator: "\n")))
                    fenceMarker = nil
                    codeLanguage = nil
                    codeBuffer.removeAll(keepingCapacity: true)
                } else {
                    codeBuffer.append(line)
                }
                idx += 1
                continue
            }

            // Start of fenced code block (``` or ~~~)
            if let opened = Self.openingFence(in: trimmed) {
                flushPending()
                fenceMarker = opened.fence
                codeLanguage = opened.language
                codeBuffer.removeAll(keepingCapacity: true)
                idx += 1
                continue
            }

            // Blank line separates blocks
            if trimmed.isEmpty {
                flushPending()
                idx += 1
                continue
            }

            // Markdown table: header line + delimiter row (`| --- | :---: |`)
            if idx + 1 < rawLines.count,
               trimmed.contains("|"),
               let alignments = Self.parseTableDelimiterRow(rawLines[idx + 1])
            {
                let headerCells = Self.splitTableCells(line)
                if !headerCells.isEmpty && headerCells.count == alignments.count {
                    flushPending()
                    var bodyRows: [[String]] = []
                    var scan = idx + 2
                    while scan < rawLines.count {
                        let candidate = rawLines[scan]
                        let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                        if candidateTrimmed.isEmpty || !candidateTrimmed.contains("|") {
                            break
                        }
                        if Self.openingFence(in: candidateTrimmed) != nil {
                            break
                        }
                        let rowCells = Self.splitTableCells(candidate)
                        if rowCells.isEmpty {
                            break
                        }
                        var normalized = rowCells
                        if normalized.count < headerCells.count {
                            normalized.append(contentsOf: Array(repeating: "", count: headerCells.count - normalized.count))
                        } else if normalized.count > headerCells.count {
                            normalized = Array(normalized.prefix(headerCells.count))
                        }
                        bodyRows.append(normalized)
                        scan += 1
                    }
                    blocks.append(
                        .table(
                            NativeMarkdownTableData(
                                headers: headerCells,
                                alignments: alignments,
                                rows: bodyRows
                            )
                        )
                    )
                    idx = scan
                    continue
                }
            }

            // ATX Heading (# through ######)
            if let heading = Self.parseHeading(trimmed) {
                flushPending()
                blocks.append(.heading(level: heading.level, text: heading.text))
                idx += 1
                continue
            }

            // Horizontal rule
            if Self.isThematicBreak(trimmed) {
                flushPending()
                blocks.append(.thematicBreak)
                idx += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                if !paragraphBuffer.isEmpty || !listBuffer.isEmpty {
                    flushPending()
                }
                var stripped = String(trimmed.dropFirst())
                if stripped.hasPrefix(" ") {
                    stripped.removeFirst()
                }
                quoteBuffer.append(stripped)
                idx += 1
                continue
            }

            // List item (bullet, numbered, or task checkbox)
            if let item = Self.parseListItem(line) {
                if !paragraphBuffer.isEmpty || !quoteBuffer.isEmpty {
                    flushPending()
                }
                listBuffer.append(item)
                idx += 1
                continue
            }

            // Indented continuation of an open list item
            if !listBuffer.isEmpty && (line.hasPrefix("  ") || line.hasPrefix("\t")) {
                listBuffer[listBuffer.count - 1].text += " " + trimmed
                idx += 1
                continue
            }

            if !listBuffer.isEmpty || !quoteBuffer.isEmpty {
                flushPending()
            }
            paragraphBuffer.append(line)
            idx += 1
        }

        if fenceMarker != nil {
            blocks.append(.codeBlock(language: codeLanguage, code: codeBuffer.joined(separator: "\n")))
        }
        flushPending()
        return blocks
    }

    private static func openingFence(in trimmed: String) -> (fence: String, language: String?)? {
        for char: Character in ["`", "~"] {
            let count = trimmed.prefix { $0 == char }.count
            if count >= 3 {
                let fence = String(repeating: String(char), count: count)
                let rest = String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
                if char == "`" && rest.contains("`") {
                    return nil
                }
                let lang = rest.split(separator: " ").first.map(String.init)
                return (fence, lang?.isEmpty == true ? nil : lang)
            }
        }
        return nil
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let after = trimmed.dropFirst(hashes)
        guard after.isEmpty || after.first == " " || after.first == "\t" else { return nil }
        let clean = after.trimmingCharacters(in: .whitespaces)
        return (hashes, clean)
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first else { return false }
        guard first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func parseListItem(_ line: String) -> NativeMarkdownListItem? {
        var indentSpaces = 0
        var consumed = 0
        for ch in line {
            if ch == " " {
                indentSpaces += 1
                consumed += 1
            } else if ch == "\t" {
                indentSpaces += 4
                consumed += 1
            } else {
                break
            }
        }
        let rest = line.dropFirst(consumed)
        let depth = min(indentSpaces / 2, 5)

        let taskPrefixes: [(String, Bool)] = [
            ("- [ ] ", false), ("- [x] ", true), ("- [X] ", true),
            ("* [ ] ", false), ("* [x] ", true), ("* [X] ", true),
            ("+ [ ] ", false), ("+ [x] ", true), ("+ [X] ", true),
        ]
        for (prefix, checked) in taskPrefixes where rest.hasPrefix(prefix) {
            return NativeMarkdownListItem(
                marker: checked ? "☑︎" : "☐",
                isTask: true,
                isChecked: checked,
                text: String(rest.dropFirst(prefix.count)),
                depth: depth
            )
        }

        for bullet in ["- ", "* ", "+ "] where rest.hasPrefix(bullet) {
            let markerSymbol: String = switch depth % 3 {
            case 0: "•"
            case 1: "◦"
            default: "▪︎"
            }
            return NativeMarkdownListItem(
                marker: markerSymbol,
                isTask: false,
                isChecked: false,
                text: String(rest.dropFirst(bullet.count)),
                depth: depth
            )
        }

        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty && digits.count <= 4 {
            let afterDigits = rest.dropFirst(digits.count)
            if afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") ") {
                return NativeMarkdownListItem(
                    marker: "\(digits).",
                    isTask: false,
                    isChecked: false,
                    text: String(afterDigits.dropFirst(2)),
                    depth: depth
                )
            }
        }
        return nil
    }

    private static func splitTableCells(_ line: String) -> [String] {
        var working = line.trimmingCharacters(in: .whitespaces)
        if working.hasPrefix("|") {
            working.removeFirst()
        }
        if working.hasSuffix("|") && !working.hasSuffix("\\|") {
            working.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for ch in working {
            if escaped {
                if ch == "|" {
                    current.append("|")
                } else {
                    current.append("\\")
                    current.append(ch)
                }
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if escaped {
            current.append("\\")
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func parseTableDelimiterRow(_ line: String) -> [NativeMarkdownTableAlignment]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") && trimmed.contains("-") else { return nil }
        let cells = splitTableCells(trimmed)
        guard !cells.isEmpty else { return nil }

        var alignments: [NativeMarkdownTableAlignment] = []
        for rawCell in cells {
            let cell = rawCell.trimmingCharacters(in: .whitespaces)
            guard !cell.isEmpty else { return nil }
            let startsColon = cell.hasPrefix(":")
            let endsColon = cell.hasSuffix(":")
            var core = cell
            if startsColon { core.removeFirst() }
            if endsColon && !core.isEmpty { core.removeLast() }
            guard core.count >= 3 && core.allSatisfy({ $0 == "-" }) else {
                return nil
            }
            if startsColon && endsColon {
                alignments.append(.center)
            } else if endsColon {
                alignments.append(.trailing)
            } else {
                alignments.append(.leading)
            }
        }
        return alignments
    }
}

// MARK: - Workspace File Link Resolution Helper

enum WorkspacePathLinkResolver {
    struct ResolvedFileTarget {
        let path: String
        let line: Int?
        let column: Int?
    }

    /// Parses URLs (`file:///path#L12`, `/abs/path:42:8`, `Sources/Foo.swift:10`) and determines if they point
    /// to a local file in or near the active workspace.
    static func resolveLocalTarget(url: URL, workspaceRoot: String?) -> ResolvedFileTarget? {
        if url.isFileURL {
            var filePath = url.path
            var line: Int? = nil
            var col: Int? = nil

            if let fragment = url.fragment, !fragment.isEmpty {
                let parsed = parseFragmentLine(fragment)
                line = parsed.line
                col = parsed.column
            } else {
                let split = splitTrailingLineAndColumn(from: filePath)
                filePath = split.path
                line = split.line
                col = split.column
            }

            if let root = workspaceRoot {
                let cleanRoot = ExternalEditorService.expandedPath(root)
                let rootPrefix = cleanRoot.hasSuffix("/") ? cleanRoot : cleanRoot + "/"
                if filePath.hasPrefix(rootPrefix) {
                    let relative = String(filePath.dropFirst(rootPrefix.count))
                    return ResolvedFileTarget(path: relative, line: line, column: col)
                }
            }
            if FileManager.default.fileExists(atPath: filePath) {
                return ResolvedFileTarget(path: filePath, line: line, column: col)
            }
            return nil
        }

        // Schemes like http/https/mailto are external links
        if let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto", "tel", "ssh"].contains(scheme)
        {
            return nil
        }

        // Bare relative or absolute path inside markdown `[AppModel.swift](Agents/Core/AppModel.swift#L42)`
        let raw = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        let hashParts = raw.split(separator: "#", maxSplits: 1).map(String.init)
        let baseRaw = hashParts.first ?? raw
        let split = splitTrailingLineAndColumn(from: baseRaw)
        var line = split.line
        var column = split.column
        if hashParts.count > 1 {
            let frag = parseFragmentLine(hashParts[1])
            if frag.line != nil {
                line = frag.line
                column = frag.column
            }
        }

        let candidatePath = ExternalEditorService.expandedPath(split.path)
        if candidatePath.hasPrefix("/") {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidatePath, isDirectory: &isDir), !isDir.boolValue {
                if let root = workspaceRoot {
                    let cleanRoot = ExternalEditorService.expandedPath(root)
                    let rootPrefix = cleanRoot.hasSuffix("/") ? cleanRoot : cleanRoot + "/"
                    if candidatePath.hasPrefix(rootPrefix) {
                        return ResolvedFileTarget(
                            path: String(candidatePath.dropFirst(rootPrefix.count)),
                            line: line,
                            column: column
                        )
                    }
                }
                return ResolvedFileTarget(path: candidatePath, line: line, column: column)
            }
        } else if let root = workspaceRoot {
            let cleanRoot = ExternalEditorService.expandedPath(root)
            let joined = (cleanRoot as NSString).appendingPathComponent(candidatePath)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: joined, isDirectory: &isDir), !isDir.boolValue {
                return ResolvedFileTarget(path: candidatePath, line: line, column: column)
            }
        }

        return nil
    }

    static func splitTrailingLineAndColumn(from raw: String) -> (path: String, line: Int?, column: Int?) {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3,
           let last = Int(parts[parts.count - 1]),
           let secondLast = Int(parts[parts.count - 2]),
           secondLast > 0
        {
            let path = parts.dropLast(2).joined(separator: ":")
            if !path.isEmpty {
                return (path, secondLast, max(1, last))
            }
        }
        if parts.count >= 2,
           let last = Int(parts[parts.count - 1]),
           last > 0
        {
            let path = parts.dropLast(1).joined(separator: ":")
            if !path.isEmpty {
                return (path, last, nil)
            }
        }
        return (raw, nil, nil)
    }

    private static func parseFragmentLine(_ fragment: String) -> (line: Int?, column: Int?) {
        let upper = fragment.uppercased()
        guard upper.hasPrefix("L") else { return (nil, nil) }
        let trimmed = String(upper.dropFirst())
        let dashTrimmed = trimmed.split(separator: "-").first.map(String.init) ?? trimmed
        let cParts = dashTrimmed.split(separator: "C").map(String.init)
        if let line = cParts.first.flatMap(Int.init), line > 0 {
            let col = cParts.count > 1 ? Int(cParts[1]) : nil
            return (line, col)
        }
        return (nil, nil)
    }
}

// MARK: - Native Markdown View

public struct NativeMarkdownView: View, Equatable {
    public let text: String
    public var fontScale: Double = 1.0
    public var usesSerif: Bool = true
    public var highlightQuery: String = ""
    public var workspaceRoot: String? = nil
    public var onOpenWorkspaceFile: ((String, Int?, Int?) -> Void)? = nil

    public static func == (lhs: NativeMarkdownView, rhs: NativeMarkdownView) -> Bool {
        lhs.text == rhs.text
            && lhs.fontScale == rhs.fontScale
            && lhs.usesSerif == rhs.usesSerif
            && lhs.highlightQuery == rhs.highlightQuery
            && lhs.workspaceRoot == rhs.workspaceRoot
    }

    public init(
        text: String,
        fontScale: Double = 1.0,
        usesSerif: Bool = true,
        highlightQuery: String = "",
        workspaceRoot: String? = nil,
        onOpenWorkspaceFile: ((String, Int?, Int?) -> Void)? = nil
    ) {
        self.text = text
        self.fontScale = fontScale
        self.usesSerif = usesSerif
        self.highlightQuery = highlightQuery
        self.workspaceRoot = workspaceRoot
        self.onOpenWorkspaceFile = onOpenWorkspaceFile
    }

    private var baseFont: Font {
        AppTheme.replyFont(scale: fontScale, usesSerif: usesSerif)
    }

    public var body: some View {
        let blocks = NativeMarkdownBlock.parse(text)
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if let resolved = WorkspacePathLinkResolver.resolveLocalTarget(url: url, workspaceRoot: workspaceRoot),
               let onOpenWorkspaceFile
            {
                onOpenWorkspaceFile(resolved.path, resolved.line, resolved.column)
                return .handled
            }
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    @ViewBuilder
    private func blockView(for block: NativeMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let headingText):
            Text(inlineAttributed(headingText, codeSize: headingCodeSize(for: level)))
                .font(headingFont(for: level))
                .foregroundStyle(AppTheme.primaryLabel)
                .padding(.top, level <= 2 ? 4 : 2)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let content):
            Text(inlineAttributed(content, codeSize: 12.5 * fontScale))
                .font(baseFont)
                .lineSpacing(3)
                .foregroundStyle(AppTheme.primaryLabel)
                .fixedSize(horizontal: false, vertical: true)

        case .list(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if item.isTask {
                            Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                                .font(.system(size: CGFloat(12.5 * fontScale), weight: .medium))
                                .foregroundStyle(item.isChecked ? AppTheme.accent : AppTheme.secondaryLabel)
                        } else {
                            Text(item.marker)
                                .font(.system(size: CGFloat(13.0 * fontScale), weight: .medium).monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }

                        Text(inlineAttributed(item.text, codeSize: 12.5 * fontScale))
                            .font(baseFont)
                            .lineSpacing(2.5)
                            .foregroundStyle(item.isTask && item.isChecked ? AppTheme.secondaryLabel : AppTheme.primaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 18)
                }
            }

        case .blockquote(let quoteText):
            HStack(alignment: .top, spacing: 11) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppTheme.accent.opacity(0.55))
                    .frame(width: 3)
                Text(inlineAttributed(quoteText, codeSize: 12.0 * fontScale))
                    .font(baseFont)
                    .italic(usesSerif)
                    .lineSpacing(2.5)
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .codeBlock(let language, let code):
            NativeCodeBlockCard(
                language: language,
                code: code,
                fontScale: fontScale,
                highlightQuery: highlightQuery
            )

        case .table(let tableData):
            NativeMarkdownTableView(
                table: tableData,
                fontScale: fontScale,
                highlightQuery: highlightQuery,
                inlineRenderer: { cellText in
                    inlineAttributed(cellText, codeSize: 11.5 * fontScale)
                }
            )

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func headingFont(for level: Int) -> Font {
        let clampedScale = max(0.8, min(1.5, fontScale))
        let baseSize: Double = switch level {
        case 1: 20.0
        case 2: 17.0
        case 3: 15.0
        case 4: 14.0
        default: 13.5
        }
        let weight: Font.Weight = level <= 2 ? .bold : .semibold
        return .system(size: CGFloat(baseSize * clampedScale), weight: weight, design: usesSerif ? .serif : .default)
    }

    private func headingCodeSize(for level: Int) -> Double {
        let base: Double = switch level {
        case 1: 17.0
        case 2: 15.0
        case 3: 13.5
        default: 12.5
        }
        return base * max(0.8, min(1.5, fontScale))
    }

    private func inlineAttributed(_ raw: String, codeSize: Double) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        var attributed = (try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw)

        for run in attributed.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                attributed[run.range].font = .system(size: CGFloat(max(10.5, codeSize)), weight: .medium, design: .monospaced)
                attributed[run.range].backgroundColor = Color.primary.opacity(0.075)
            }
            if run.link != nil {
                attributed[run.range].foregroundColor = AppTheme.info
                attributed[run.range].underlineStyle = .single
            }
        }

        let trimmedQuery = highlightQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            Self.applySearchHighlight(query: trimmedQuery, to: &attributed)
        }
        return attributed
    }

    static func applySearchHighlight(query: String, to attributed: inout AttributedString) {
        let plain = String(attributed.characters)
        guard !plain.isEmpty else { return }
        var searchStart = plain.startIndex
        while let foundRange = plain.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<plain.endIndex
        ) {
            if let lower = AttributedString.Index(foundRange.lowerBound, within: attributed),
               let upper = AttributedString.Index(foundRange.upperBound, within: attributed)
            {
                attributed[lower..<upper].backgroundColor = AppTheme.searchMatchHighlight
            }
            searchStart = foundRange.upperBound
        }
    }
}

// MARK: - Fenced Code Block Card

struct NativeCodeBlockCard: View {
    let language: String?
    let code: String
    var fontScale: Double = 1.0
    var highlightQuery: String = ""

    @State private var didCopy = false

    private var displayLanguage: String {
        guard let language, !language.isEmpty else { return "code" }
        return language.lowercased()
    }

    private var lineCount: Int {
        guard !code.isEmpty else { return 0 }
        return code.components(separatedBy: "\n").count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                    Text(displayLanguage)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }

                if lineCount > 1 {
                    Text("· \(lineCount) lines")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        didCopy = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(didCopy ? AppTheme.success : AppTheme.secondaryLabel)
                        Text(didCopy ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(didCopy ? AppTheme.success : AppTheme.secondaryLabel)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.subtleHoverFill, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Copy code to clipboard")
                .accessibilityLabel("Copy code to clipboard")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.03))

            Divider()

            ScrollView(.horizontal, showsIndicators: true) {
                Text(highlightedCode)
                    .font(AppTheme.codeFont(scale: fontScale, size: 12.25))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
            }
        }
        .background(AppTheme.codeBlockBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 1)
        )
    }

    private var highlightedCode: AttributedString {
        var attr = AttributedString(code)
        let q = highlightQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            NativeMarkdownView.applySearchHighlight(query: q, to: &attr)
        }
        return attr
    }
}

// MARK: - Native SwiftUI Markdown Table View

struct NativeMarkdownTableView: View {
    let table: NativeMarkdownTableData
    let fontScale: Double
    let highlightQuery: String
    let inlineRenderer: (String) -> AttributedString

    @State private var copiedTSV = false

    private func alignment(for column: Int) -> Alignment {
        guard column < table.alignments.count else { return .leading }
        switch table.alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(for column: Int) -> TextAlignment {
        guard column < table.alignments.count else { return .leading }
        switch table.alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    // Header row
                    GridRow {
                        ForEach(0..<table.columnCount, id: \.self) { colIdx in
                            let headerText = colIdx < table.headers.count ? table.headers[colIdx] : ""
                            Text(inlineRenderer(headerText))
                                .font(.system(size: CGFloat(12.25 * fontScale), weight: .semibold))
                                .foregroundStyle(AppTheme.primaryLabel)
                                .multilineTextAlignment(textAlignment(for: colIdx))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .frame(minWidth: 72, maxWidth: .infinity, alignment: alignment(for: colIdx))
                                .overlay(alignment: .trailing) {
                                    if colIdx < table.columnCount - 1 {
                                        Rectangle()
                                            .fill(AppTheme.separator.opacity(0.55))
                                            .frame(width: 1)
                                    }
                                }
                        }
                    }
                    .background(Color.primary.opacity(0.05))

                    Divider()

                    // Body rows
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIdx, row in
                        GridRow {
                            ForEach(0..<table.columnCount, id: \.self) { colIdx in
                                let cellText = colIdx < row.count ? row[colIdx] : ""
                                Text(inlineRenderer(cellText))
                                    .font(.system(size: CGFloat(12.25 * fontScale)))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                    .multilineTextAlignment(textAlignment(for: colIdx))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6.5)
                                    .frame(minWidth: 72, maxWidth: .infinity, alignment: alignment(for: colIdx))
                                    .overlay(alignment: .trailing) {
                                        if colIdx < table.columnCount - 1 {
                                            Rectangle()
                                                .fill(AppTheme.separator.opacity(0.4))
                                                .frame(width: 1)
                                        }
                                    }
                            }
                        }
                        .background(rowIdx.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.02))

                        if rowIdx < table.rows.count - 1 {
                            Divider().opacity(0.6)
                        }
                    }
                }
            }

            Divider().opacity(0.6)

            HStack {
                Text("\(table.rows.count) \(table.rows.count == 1 ? "row" : "rows")")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(table.tsvRepresentation, forType: .string)
                    copiedTSV = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedTSV = false
                    }
                } label: {
                    Label(copiedTSV ? "Copied TSV" : "Copy Table", systemImage: copiedTSV ? "checkmark" : "tablecells")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copiedTSV ? AppTheme.success : AppTheme.secondaryLabel)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.02))
        }
        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.separator.opacity(0.75), lineWidth: 1)
        )
    }
}
