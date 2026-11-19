import Foundation

public nonisolated struct RedactedOutput: Sendable {
    public let text: String
    public let redactionCount: Int

    public var didRedact: Bool {
        redactionCount > 0
    }

    public init(text: String, redactionCount: Int) {
        self.text = text
        self.redactionCount = redactionCount
    }
}

public nonisolated final class OutputRedactionGate: @unchecked Sendable {
    public static let redactionMarker = "[redacted]"
    public static let notificationExcerptLimit = 140
    public static let shared = OutputRedactionGate()

    private static let minimumFragmentLength = 48
    private static let maximumFragmentLength = 400
    private static let fragmentPrefixLength = 24
    private static let longFragmentChunkLength = 200

    private struct PatternRule {
        let expression: NSRegularExpression
        let redactedGroup: Int
    }

    private struct PreparedText {
        let string: String
        let owners: [Int]
        let wordStarts: [Int]
        let wordEnds: [Int]
    }

    private static let patternRules: [PatternRule] = {
        let wholeMatchPatterns = [
            "[^\\s\"']*CoincideComputerUse-[A-Za-z0-9_\\-]+[^\\s\"']*",
            "[^\\s\"']*computer-use\\.curl[^\\s\"']*",
            "[^\\s\"']*agy_acp_server[^\\s\"']*",
            "[^\\s\"']*localharness_external[^\\s\"']*",
            "[^\\s\"']*GEMINI_HOME[^\\s\"']*",
            "AIza[0-9A-Za-z\\-_]{20,}",
            "com\\.apoorvdarshan\\.coincide\\.remote\\.token[^\\s\"']*",
            "com\\.apoorvdarshan\\.coincide\\.rust\\.(?:provider-account|remote|voice-transcription)\\.v1[^\\s\"']*",
        ]
        let groupedPatterns: [(pattern: String, group: Int)] = [
            ("GEMINI_API_KEY\\s*[\"':=]+\\s*\"?([A-Za-z0-9_\\-]{8,})", 1),
            ("(threadId|threadID|thread_id|runId|runID|run_id|workerId|workerID|clientId|clientID|sessionId|sessionID|assistantId|assistantID)\\s*[\"':=]+\\s*\"?([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})", 2),
            ("(tool_call_id)\\s*[\"':=]+\\s*\"?([A-Za-z0-9_\\-]+)", 2),
        ]
        var rules: [PatternRule] = []
        for pattern in wholeMatchPatterns {
            if let expression = try? NSRegularExpression(pattern: pattern) {
                rules.append(PatternRule(expression: expression, redactedGroup: 0))
            }
        }
        for entry in groupedPatterns {
            if let expression = try? NSRegularExpression(pattern: entry.pattern) {
                rules.append(PatternRule(expression: expression, redactedGroup: entry.group))
            }
        }
        return rules
    }()

    private let lock = NSLock()
    private var fragments: Set<String>
    private var orderedFragments: [String]

    public init() {
        let collected = Self.bundledAssetFragments()
        fragments = collected
        orderedFragments = collected.sorted { $0.count > $1.count }
    }

    public init(sensitiveTexts: [String]) {
        var collected: Set<String> = []
        for text in sensitiveTexts {
            collected.formUnion(Self.extractFragments(from: text))
        }
        fragments = collected
        orderedFragments = collected.sorted { $0.count > $1.count }
    }

    public func registerSensitiveText(_ text: String) {
        let extracted = Self.extractFragments(from: text)
        guard !extracted.isEmpty else { return }
        lock.lock()
        fragments.formUnion(extracted)
        orderedFragments = fragments.sorted { $0.count > $1.count }
        lock.unlock()
    }

    public func redact(_ text: String) -> RedactedOutput {
        guard !text.isEmpty else { return RedactedOutput(text: text, redactionCount: 0) }
        var spans: [(start: Int, end: Int)] = []
        spans.append(contentsOf: fragmentSpans(in: text))
        spans.append(contentsOf: Self.patternSpans(in: text))
        let merged = Self.merge(spans)
        guard !merged.isEmpty else { return RedactedOutput(text: text, redactionCount: 0) }
        let chars = Array(text)
        var output = ""
        output.reserveCapacity(text.count)
        var cursor = 0
        for span in merged {
            if span.start > cursor {
                output += String(chars[cursor..<span.start])
            }
            output += Self.redactionMarker
            cursor = max(cursor, span.end)
        }
        if cursor < chars.count {
            output += String(chars[cursor...])
        }
        return RedactedOutput(text: output, redactionCount: merged.count)
    }

    public func redactedText(_ text: String) -> String {
        redact(text).text
    }

    public func notificationExcerpt(for result: String) -> String {
        let flattened = result
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return "" }
        let redacted = redact(flattened).text
        let surviving = redacted
            .replacingOccurrences(of: Self.redactionMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !surviving.isEmpty else { return "" }
        guard redacted.count > Self.notificationExcerptLimit else { return redacted }
        var excerpt = String(redacted.prefix(Self.notificationExcerptLimit))
        if let lastSpace = excerpt.lastIndex(of: " ") {
            let tail = excerpt[excerpt.index(after: lastSpace)...]
            if tail != Self.redactionMarker && tail.hasPrefix("[") && Self.redactionMarker.hasPrefix(tail) {
                excerpt = String(excerpt[..<lastSpace])
            }
        }
        return excerpt.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func fragmentSpans(in text: String) -> [(start: Int, end: Int)] {
        lock.lock()
        let snapshot = orderedFragments
        lock.unlock()
        guard !snapshot.isEmpty else { return [] }
        let prepared = Self.prepareNormalized(text)
        guard !prepared.owners.isEmpty else { return [] }
        var spans: [(start: Int, end: Int)] = []
        for fragment in snapshot {
            guard fragment.count >= Self.minimumFragmentLength else { continue }
            guard prepared.string.contains(String(fragment.prefix(Self.fragmentPrefixLength))) else { continue }
            var searchFrom = prepared.string.startIndex
            while let found = prepared.string.range(of: fragment, range: searchFrom..<prepared.string.endIndex) {
                let lower = prepared.string.distance(from: prepared.string.startIndex, to: found.lowerBound)
                let upper = prepared.string.distance(from: prepared.string.startIndex, to: found.upperBound)
                if lower < upper && lower < prepared.owners.count && upper - 1 < prepared.owners.count {
                    let startWord = prepared.owners[lower]
                    let endWord = prepared.owners[upper - 1]
                    spans.append((start: prepared.wordStarts[startWord], end: prepared.wordEnds[endWord]))
                }
                searchFrom = found.upperBound
            }
        }
        return spans
    }

    private static func patternSpans(in text: String) -> [(start: Int, end: Int)] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var spans: [(start: Int, end: Int)] = []
        for rule in patternRules {
            for match in rule.expression.matches(in: text, range: range) {
                let groupRange = match.range(at: rule.redactedGroup)
                guard groupRange.location != NSNotFound,
                      let swiftRange = Range(groupRange, in: text) else { continue }
                let start = text.distance(from: text.startIndex, to: swiftRange.lowerBound)
                let end = text.distance(from: text.startIndex, to: swiftRange.upperBound)
                guard start < end else { continue }
                spans.append((start: start, end: end))
            }
        }
        return spans
    }

    private static func merge(_ spans: [(start: Int, end: Int)]) -> [(start: Int, end: Int)] {
        let sorted = spans.sorted {
            $0.start < $1.start || ($0.start == $1.start && $0.end < $1.end)
        }
        var merged: [(start: Int, end: Int)] = []
        for span in sorted {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1].end = max(last.end, span.end)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    private static func prepareNormalized(_ text: String) -> PreparedText {
        let chars = Array(text)
        var normChars: [Character] = []
        var owners: [Int] = []
        var wordStarts: [Int] = []
        var wordEnds: [Int] = []
        var index = 0
        var wordIndex = 0
        var firstWord = true
        while index < chars.count {
            while index < chars.count && chars[index].isWhitespace {
                index += 1
            }
            guard index < chars.count else { break }
            let start = index
            while index < chars.count && !chars[index].isWhitespace {
                index += 1
            }
            let end = index
            let normalizedWord = SystemAssetIndex.normalized(String(chars[start..<end]))
            if !firstWord {
                normChars.append(" ")
                owners.append(wordIndex - 1)
            }
            firstWord = false
            for character in normalizedWord {
                normChars.append(character)
                owners.append(wordIndex)
            }
            wordStarts.append(start)
            wordEnds.append(end)
            wordIndex += 1
        }
        return PreparedText(string: String(normChars), owners: owners, wordStarts: wordStarts, wordEnds: wordEnds)
    }

    private static func extractFragments(from text: String) -> Set<String> {
        var found: Set<String> = []
        let normalized = SystemAssetIndex.normalized(text)
        let pieces = normalized.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.count <= maximumFragmentLength {
                if trimmed.count >= minimumFragmentLength {
                    found.insert(trimmed)
                }
            } else {
                found.formUnion(wordChunks(of: trimmed, chunkLength: longFragmentChunkLength))
            }
        }
        return found
    }

    private static func wordChunks(of text: String, chunkLength: Int) -> Set<String> {
        var found: Set<String> = []
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if candidate.count > chunkLength {
                if current.count >= minimumFragmentLength {
                    found.insert(current)
                }
                current = word
            } else {
                current = candidate
            }
        }
        if current.count >= minimumFragmentLength {
            found.insert(current)
        }
        return found
    }

    private static func bundledAssetFragments() -> Set<String> {
        guard let directory = try? SystemAssetIndex.bundledAssetsURL() else { return [] }
        guard let index = try? SystemAssetIndex.load(directory: directory) else { return [] }
        var collected: Set<String> = []
        for document in index.documents {
            collected.formUnion(extractFragments(from: document.rawText))
        }
        return collected
    }
}
