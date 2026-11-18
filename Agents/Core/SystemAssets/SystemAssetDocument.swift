import CryptoKit
import Foundation

public nonisolated struct SystemAssetDocument: Sendable, Hashable, Codable {
    public var id: String
    public var fileName: String
    public var relativePath: String
    public var title: String
    public var category: String
    public var tags: [String]
    public var dependencies: [String]
    public var contentHash: String
    public var sections: [SystemAssetSection]
    public var rawText: String
    public var estimatedTokens: Int

    public init(id: String, fileName: String, relativePath: String, title: String, category: String = "General", tags: [String] = [], dependencies: [String], contentHash: String, sections: [SystemAssetSection], rawText: String) {
        self.id = id
        self.fileName = fileName
        self.relativePath = relativePath
        self.title = title
        self.category = category
        self.tags = tags
        self.dependencies = dependencies
        self.contentHash = contentHash
        self.sections = sections
        self.rawText = rawText
        self.estimatedTokens = sections.reduce(0) { $0 + $1.estimatedTokens }
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func parse(fileName: String, relativePath: String, data: Data) throws -> SystemAssetDocument {
        guard let rawText = String(data: data, encoding: .utf8) else {
            throw SystemAssetError.documentMalformed(fileName: fileName, reason: "Document is not valid UTF-8.")
        }
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SystemAssetError.documentMalformed(fileName: fileName, reason: "Document is empty.")
        }
        let id = (relativePath as NSString).deletingPathExtension
        let lines = rawText.components(separatedBy: "\n")
        let title = parseTitle(lines: lines, fallback: id)
        let category = parseCategory(lines: lines, relativePath: relativePath)
        let tags = parseTags(lines: lines)
        let dependencies = parseDependencies(lines: lines)
        let sections = parseSections(lines: lines, documentID: id, fileName: fileName, title: title)
        return SystemAssetDocument(
            id: id,
            fileName: fileName,
            relativePath: relativePath,
            title: title,
            category: category,
            tags: tags,
            dependencies: dependencies,
            contentHash: sha256Hex(of: data),
            sections: sections,
            rawText: rawText
        )
    }

    private static func parseTitle(lines: [String], fallback: String) -> String {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    return title
                }
            }
        }
        return fallback
    }

    private static func parseCategory(lines: [String], relativePath: String) -> String {
        let marker = "<!-- system-index-category:"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                break
            }
            guard let range = trimmed.range(of: marker) else {
                continue
            }
            let value = String(trimmed[range.upperBound...])
                .replacingOccurrences(of: "-->", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        let directory = (relativePath as NSString).deletingLastPathComponent
        if !directory.isEmpty && directory != "." {
            return (directory as NSString).lastPathComponent
        }
        return "General"
    }

    private static func parseTags(lines: [String]) -> [String] {
        let marker = "<!-- system-index-tags:"
        var found: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                break
            }
            guard let range = trimmed.range(of: marker) else {
                continue
            }
            let remainder = String(trimmed[range.upperBound...])
            let names = remainder.replacingOccurrences(of: "-->", with: "")
            for part in names.components(separatedBy: ",") {
                let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty && !found.contains(name) {
                    found.append(name)
                }
            }
        }
        return found
    }

    private static func parseDependencies(lines: [String]) -> [String] {
        let marker = "<!-- system-index-depends:"
        var found: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                break
            }
            guard let range = trimmed.range(of: marker) else {
                continue
            }
            let remainder = String(trimmed[range.upperBound...])
            let names = remainder.replacingOccurrences(of: "-->", with: "")
            for part in names.components(separatedBy: ",") {
                let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.hasSuffix(".md") && !found.contains(name) {
                    found.append(name)
                }
            }
        }
        return found
    }

    private static func parseSections(lines: [String], documentID: String, fileName: String, title: String) -> [SystemAssetSection] {
        var sections: [SystemAssetSection] = []
        var headingStack: [(level: Int, text: String)] = []
        var currentHeading = ""
        var currentLevel = 0
        var currentBody: [String] = []
        var sawHeading = false

        func flush() {
            let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = currentHeading
            let headingPath = headingStack.map(\.text)
            if !heading.isEmpty || !body.isEmpty {
                sections.append(SystemAssetSection(
                    documentID: documentID,
                    fileName: fileName,
                    heading: heading,
                    level: currentLevel,
                    headingPath: headingPath,
                    body: body
                ))
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = parseHeading(line: trimmed) {
                if sawHeading {
                    flush()
                } else if !currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    flush()
                }
                sawHeading = true
                while let last = headingStack.last, last.level >= heading.level {
                    headingStack.removeLast()
                }
                headingStack.append((level: heading.level, text: heading.text))
                currentHeading = heading.text
                currentLevel = heading.level
                currentBody = []
            } else {
                if trimmed.hasPrefix("<!-- system-index-") {
                    continue
                }
                currentBody.append(line)
            }
        }
        if sawHeading {
            flush()
        } else {
            let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                sections.append(SystemAssetSection(
                    documentID: documentID,
                    fileName: fileName,
                    heading: title,
                    level: 1,
                    headingPath: [title],
                    body: body
                ))
            }
        }
        return sections
    }

    private static func parseHeading(line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex && line[index] == "#" {
            level += 1
            index = line.index(after: index)
        }
        guard level >= 1 && level <= 6 else {
            return nil
        }
        guard index < line.endIndex && line[index] == " " else {
            return nil
        }
        let text = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            return nil
        }
        return (level: level, text: text)
    }
}
