import Foundation

public nonisolated struct SystemAssetChunk: Codable, Hashable, Sendable {
    public static let maxChunkCharacters = 4000

    public var id: String
    public var documentID: String
    public var fileName: String
    public var heading: String
    public var level: Int
    public var headingPath: [String]
    public var body: String
    public var estimatedTokens: Int
    public var sectionIndex: Int
    public var ordinal: Int

    public init(id: String, documentID: String, fileName: String, heading: String, level: Int, headingPath: [String], body: String, sectionIndex: Int, ordinal: Int) {
        self.id = id
        self.documentID = documentID
        self.fileName = fileName
        self.heading = heading
        self.level = level
        self.headingPath = headingPath
        self.body = body
        self.estimatedTokens = max(1, ((heading.isEmpty ? body.count : heading.count + 2 + body.count) + 3) / 4)
        self.sectionIndex = sectionIndex
        self.ordinal = ordinal
    }

    public var text: String {
        if heading.isEmpty {
            return body
        }
        if body.isEmpty {
            return heading
        }
        return heading + "\n\n" + body
    }

    public static func chunk(document: SystemAssetDocument) -> [SystemAssetChunk] {
        var chunks: [SystemAssetChunk] = []
        for (sectionIndex, section) in document.sections.enumerated() {
            let heading = section.heading.isEmpty ? document.title : section.heading
            let headingPath = section.headingPath.isEmpty ? [document.title] : section.headingPath
            let singleText = heading + "\n\n" + section.body
            if singleText.count <= maxChunkCharacters {
                chunks.append(SystemAssetChunk(
                    id: chunkID(documentID: document.id, sectionIndex: sectionIndex, ordinal: 0),
                    documentID: document.id,
                    fileName: document.fileName,
                    heading: heading,
                    level: section.level,
                    headingPath: headingPath,
                    body: section.body,
                    sectionIndex: sectionIndex,
                    ordinal: 0
                ))
                continue
            }
            let available = max(500, maxChunkCharacters - heading.count - 2)
            var pieces: [String] = []
            for paragraph in splitParagraphs(section.body) {
                pieces.append(contentsOf: splitLongText(paragraph, limit: available))
            }
            var groups: [[String]] = []
            var current: [String] = []
            var currentLength = heading.count + 2
            for piece in pieces {
                let added = current.isEmpty ? piece.count : 2 + piece.count
                if !current.isEmpty && currentLength + added > maxChunkCharacters {
                    groups.append(current)
                    current = []
                    currentLength = heading.count + 2
                }
                current.append(piece)
                currentLength += current.count == 1 ? piece.count : added
            }
            if !current.isEmpty {
                groups.append(current)
            }
            if groups.isEmpty {
                groups.append([])
            }
            for (ordinal, group) in groups.enumerated() {
                chunks.append(SystemAssetChunk(
                    id: chunkID(documentID: document.id, sectionIndex: sectionIndex, ordinal: ordinal),
                    documentID: document.id,
                    fileName: document.fileName,
                    heading: heading,
                    level: section.level,
                    headingPath: headingPath,
                    body: group.joined(separator: "\n\n"),
                    sectionIndex: sectionIndex,
                    ordinal: ordinal
                ))
            }
        }
        return chunks
    }

    public static func chunkID(documentID: String, sectionIndex: Int, ordinal: Int) -> String {
        documentID + "#s" + String(sectionIndex) + "c" + String(ordinal)
    }

    private static func splitParagraphs(_ body: String) -> [String] {
        body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitLongText(_ text: String, limit: Int) -> [String] {
        guard text.count > limit else {
            return [text]
        }
        var pieces: [String] = []
        var remainder = text
        while !remainder.isEmpty {
            if remainder.count <= limit {
                pieces.append(remainder)
                break
            }
            let cutIndex = remainder.index(remainder.startIndex, offsetBy: limit)
            let window = remainder[remainder.startIndex..<cutIndex]
            if let lastSpace = window.lastIndex(of: " ") {
                let piece = String(remainder[remainder.startIndex..<lastSpace]).trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty {
                    pieces.append(piece)
                }
                remainder = String(remainder[remainder.index(after: lastSpace)...]).trimmingCharacters(in: .whitespaces)
            } else {
                pieces.append(String(window))
                remainder = String(remainder[cutIndex...])
            }
        }
        return pieces.filter { !$0.isEmpty }
    }
}

public nonisolated enum SystemAssetPostingField: String, Codable, Sendable {
    case title
    case heading
    case body
    case fileName
    case identifier
}

public nonisolated struct SystemAssetPosting: Codable, Hashable, Sendable {
    public var chunkID: String?
    public var documentID: String
    public var field: SystemAssetPostingField
    public var weight: Int
    public var occurrences: Int

    public init(chunkID: String?, documentID: String, field: SystemAssetPostingField, weight: Int, occurrences: Int) {
        self.chunkID = chunkID
        self.documentID = documentID
        self.field = field
        self.weight = weight
        self.occurrences = occurrences
    }
}

public nonisolated struct SystemAssetIndexStructures {
    public nonisolated struct Derived: Sendable {
        public var chunks: [SystemAssetChunk]
        public var postings: [String: [SystemAssetPosting]]
        public var keywordsByDocumentID: [String: [String]]
        public var dependentsByFileName: [String: [String]]

        public init(chunks: [SystemAssetChunk], postings: [String: [SystemAssetPosting]], keywordsByDocumentID: [String: [String]], dependentsByFileName: [String: [String]]) {
            self.chunks = chunks
            self.postings = postings
            self.keywordsByDocumentID = keywordsByDocumentID
            self.dependentsByFileName = dependentsByFileName
        }
    }

    private init() {}

    public static func derive(documents: [SystemAssetDocument]) -> Derived {
        var chunks: [SystemAssetChunk] = []
        var accumulator: [String: [String: SystemAssetPosting]] = [:]
        var keywordsByDocumentID: [String: [String]] = [:]
        var dependentsByFileName: [String: [String]] = [:]
        for document in documents {
            let documentChunks = SystemAssetChunk.chunk(document: document)
            chunks.append(contentsOf: documentChunks)
            var keywordSet = Set<String>()
            accumulateFieldTokens(into: &accumulator, keywordSet: &keywordSet, text: document.title, chunkID: nil, documentID: document.id, field: .title, weight: 5, includeInKeywords: true)
            accumulateFieldTokens(into: &accumulator, keywordSet: &keywordSet, text: document.fileName, chunkID: nil, documentID: document.id, field: .fileName, weight: 5, includeInKeywords: true)
            accumulateFieldTokens(into: &accumulator, keywordSet: &keywordSet, text: document.id, chunkID: nil, documentID: document.id, field: .identifier, weight: 5, includeInKeywords: true)
            for token in tokenizeField(document.category) {
                keywordSet.insert(token)
            }
            for tag in document.tags {
                for token in tokenizeField(tag) {
                    keywordSet.insert(token)
                }
            }
            for chunk in documentChunks {
                accumulateFieldTokens(into: &accumulator, keywordSet: &keywordSet, text: chunk.heading, chunkID: chunk.id, documentID: document.id, field: .heading, weight: 4, includeInKeywords: true)
                accumulateFieldTokens(into: &accumulator, keywordSet: &keywordSet, text: chunk.body, chunkID: chunk.id, documentID: document.id, field: .body, weight: 1, includeInKeywords: false)
            }
            keywordsByDocumentID[document.id] = keywordSet.sorted()
            for dependency in document.dependencies {
                var dependents = dependentsByFileName[dependency] ?? []
                if !dependents.contains(document.fileName) {
                    dependents.append(document.fileName)
                }
                dependentsByFileName[dependency] = dependents.sorted()
            }
        }
        var postings: [String: [SystemAssetPosting]] = [:]
        for (token, byKey) in accumulator {
            postings[token] = byKey.values.sorted {
                if $0.documentID != $1.documentID {
                    return $0.documentID < $1.documentID
                }
                if ($0.chunkID ?? "") != ($1.chunkID ?? "") {
                    return ($0.chunkID ?? "") < ($1.chunkID ?? "")
                }
                return $0.field.rawValue < $1.field.rawValue
            }
        }
        return Derived(chunks: chunks, postings: postings, keywordsByDocumentID: keywordsByDocumentID, dependentsByFileName: dependentsByFileName)
    }

    private static func tokenizeField(_ text: String) -> [String] {
        SystemAssetIndex.tokenize(SystemAssetIndex.normalized(text))
    }

    private static func accumulateFieldTokens(into accumulator: inout [String: [String: SystemAssetPosting]], keywordSet: inout Set<String>, text: String, chunkID: String?, documentID: String, field: SystemAssetPostingField, weight: Int, includeInKeywords: Bool) {
        let tokens = tokenizeField(text)
        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
            if includeInKeywords {
                keywordSet.insert(token)
            }
        }
        for (token, occurrences) in counts {
            let key = documentID + "|" + (chunkID ?? "") + "|" + field.rawValue
            var byKey = accumulator[token] ?? [:]
            byKey[key] = SystemAssetPosting(chunkID: chunkID, documentID: documentID, field: field, weight: weight, occurrences: occurrences)
            accumulator[token] = byKey
        }
    }
}
