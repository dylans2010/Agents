import Foundation

public nonisolated struct SystemAssetIndex: Sendable {
    public var directory: URL
    public var documents: [SystemAssetDocument]
    public var chunks: [SystemAssetChunk]
    public var postings: [String: [SystemAssetPosting]]
    public var keywordsByDocumentID: [String: [String]]
    public var dependentsByFileName: [String: [String]]

    private var byID: [String: SystemAssetDocument]
    private var byFileName: [String: SystemAssetDocument]
    private var byRelativePath: [String: SystemAssetDocument]
    private var chunkByID: [String: SystemAssetChunk]

    public init(directory: URL, documents: [SystemAssetDocument], chunks: [SystemAssetChunk]? = nil, postings: [String: [SystemAssetPosting]]? = nil, keywordsByDocumentID: [String: [String]]? = nil, dependentsByFileName: [String: [String]]? = nil) {
        self.directory = directory
        self.documents = documents.sorted { $0.fileName < $1.fileName }
        var idMap: [String: SystemAssetDocument] = [:]
        var nameMap: [String: SystemAssetDocument] = [:]
        var pathMap: [String: SystemAssetDocument] = [:]
        for document in self.documents {
            idMap[document.id] = document
            if nameMap[document.fileName] == nil {
                nameMap[document.fileName] = document
            }
            pathMap[document.relativePath] = document
        }
        self.byID = idMap
        self.byFileName = nameMap
        self.byRelativePath = pathMap
        if let chunks, let postings, let keywordsByDocumentID, let dependentsByFileName {
            self.chunks = chunks
            self.postings = postings
            self.keywordsByDocumentID = keywordsByDocumentID
            self.dependentsByFileName = dependentsByFileName
        } else {
            let derived = SystemAssetIndexStructures.derive(documents: self.documents)
            self.chunks = derived.chunks
            self.postings = derived.postings
            self.keywordsByDocumentID = derived.keywordsByDocumentID
            self.dependentsByFileName = derived.dependentsByFileName
        }
        var chunkMap: [String: SystemAssetChunk] = [:]
        for chunk in self.chunks {
            chunkMap[chunk.id] = chunk
        }
        self.chunkByID = chunkMap
    }

    public var documentCount: Int {
        documents.count
    }

    public var isEmpty: Bool {
        documents.isEmpty
    }

    public var fileNames: [String] {
        documents.map(\.fileName)
    }

    public static func load(directory: URL) throws -> SystemAssetIndex {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SystemAssetError.assetsDirectoryMissing(searched: [directory])
        }
        let markdownURLs = markdownFiles(in: directory)
        guard !markdownURLs.isEmpty else {
            throw SystemAssetError.noDocumentsFound(directory: directory)
        }
        var parsed: [SystemAssetDocument] = []
        for url in markdownURLs {
            let fileName = url.lastPathComponent
            let relativePath = SystemAssetFingerprint.relativePath(of: url, in: directory)
            guard let data = try? Data(contentsOf: url) else {
                throw SystemAssetError.documentUnreadable(fileName: fileName)
            }
            parsed.append(try SystemAssetDocument.parse(fileName: fileName, relativePath: relativePath, data: data))
        }
        return SystemAssetIndex(directory: directory, documents: parsed)
    }

    private static func markdownFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }
        var found: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory != true else {
                continue
            }
            if url.pathExtension.lowercased() == "md" {
                found.append(url)
            }
        }
        return found.sorted { SystemAssetFingerprint.relativePath(of: $0, in: directory) < SystemAssetFingerprint.relativePath(of: $1, in: directory) }
    }

    public static func bundledAssetsURL() throws -> URL {
        var searched: [URL] = []
        let candidates = bundledAssetsCandidates()
        for candidate in candidates {
            searched.append(candidate)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }
        throw SystemAssetError.assetsDirectoryMissing(searched: searched)
    }

    private static func bundledAssetsCandidates() -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("SystemAssets"))
        }
        if let bundleURL = Bundle.main.bundleURL as URL? {
            var ancestor: URL? = bundleURL
            for _ in 0..<6 {
                guard let current = ancestor else {
                    break
                }
                candidates.append(current.appendingPathComponent("Agents/Resources/SystemAssets"))
                ancestor = current.deletingLastPathComponent()
                if ancestor?.path == "/" {
                    break
                }
            }
        }
        var workingDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            candidates.append(workingDir.appendingPathComponent("Agents/Resources/SystemAssets"))
            let parent = workingDir.deletingLastPathComponent()
            if parent == workingDir {
                break
            }
            workingDir = parent
        }
        var unique: [URL] = []
        for candidate in candidates where !unique.contains(candidate) {
            unique.append(candidate)
        }
        return unique
    }

    public func document(id: String) -> SystemAssetDocument? {
        byID[id]
    }

    public func document(fileName: String) -> SystemAssetDocument? {
        byFileName[fileName]
    }

    public func document(relativePath: String) -> SystemAssetDocument? {
        byRelativePath[relativePath]
    }

    public func chunk(id: String) -> SystemAssetChunk? {
        chunkByID[id]
    }

    public func chunks(forDocumentID documentID: String) -> [SystemAssetChunk] {
        chunks.filter { $0.documentID == documentID }
    }

    public func postings(for token: String) -> [SystemAssetPosting] {
        let normalizedToken = Self.normalized(token)
        guard !normalizedToken.isEmpty, !normalizedToken.contains(" ") else {
            return []
        }
        return postings[normalizedToken] ?? []
    }

    public func keywords(forDocumentID documentID: String) -> [String] {
        keywordsByDocumentID[documentID] ?? []
    }

    public func documents(category: String) -> [SystemAssetDocument] {
        let wanted = Self.normalized(category)
        guard !wanted.isEmpty else {
            return []
        }
        return documents.filter { Self.normalized($0.category) == wanted }
    }

    public func documents(tag: String) -> [SystemAssetDocument] {
        let wanted = Self.normalized(tag)
        guard !wanted.isEmpty else {
            return []
        }
        return documents.filter { document in
            document.tags.contains { Self.normalized($0) == wanted }
        }
    }

    public func relatedDocumentIDs(ofFileName fileName: String) -> [String] {
        guard let document = byFileName[fileName] else {
            return []
        }
        var ids = Set<String>()
        for dependency in document.dependencies {
            if let target = byFileName[dependency] {
                ids.insert(target.id)
            }
        }
        for dependent in dependentsByFileName[fileName] ?? [] {
            if let target = byFileName[dependent] {
                ids.insert(target.id)
            }
        }
        ids.remove(document.id)
        return ids.sorted()
    }

    public func section(documentID: String, heading: String) -> SystemAssetSection? {
        let wanted = Self.normalized(heading)
        return byID[documentID]?.sections.first { Self.normalized($0.heading) == wanted }
    }

    public func search(_ query: String, limit: Int = 10) -> [SystemAssetSearchResult] {
        let normalizedQuery = Self.normalized(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }
        let tokens = Self.tokenize(normalizedQuery)
        var bestByKey: [String: SystemAssetSearchResult] = [:]
        for document in documents {
            let normalizedTitle = Self.normalized(document.title)
            let normalizedFileName = Self.normalized(document.fileName)
            let normalizedID = Self.normalized(document.id)
            if normalizedQuery == normalizedFileName || normalizedQuery == normalizedID {
                let first = document.sections.first
                let result = SystemAssetSearchResult(
                    documentID: document.id,
                    fileName: document.fileName,
                    title: document.title,
                    sectionHeading: first?.heading ?? document.title,
                    headingPath: first?.headingPath ?? [document.title],
                    text: first?.displayText ?? document.rawText,
                    score: 100,
                    reason: "exactFilename",
                    contentHash: document.contentHash
                )
                bestByKey[document.id] = result
                continue
            }
            if normalizedQuery == normalizedTitle {
                let first = document.sections.first
                let result = SystemAssetSearchResult(
                    documentID: document.id,
                    fileName: document.fileName,
                    title: document.title,
                    sectionHeading: first?.heading ?? document.title,
                    headingPath: first?.headingPath ?? [document.title],
                    text: first?.displayText ?? document.rawText,
                    score: 90,
                    reason: "exactTitle",
                    contentHash: document.contentHash
                )
                bestByKey[document.id] = result
                continue
            }
            for section in document.sections {
                let normalizedHeading = Self.normalized(section.heading)
                let normalizedBody = Self.normalized(section.body)
                let combined = normalizedHeading + " " + normalizedBody
                var score = 0
                var reason = "keyword"
                if !normalizedHeading.isEmpty && normalizedHeading == normalizedQuery {
                    score = 80
                    reason = "exactHeading"
                } else if combined.contains(normalizedQuery) {
                    let occurrences = combined.components(separatedBy: normalizedQuery).count - 1
                    score = 70 + min(10, occurrences)
                    reason = "phrase"
                } else {
                    var tokenScore = 0
                    for token in tokens {
                        if normalizedTitle.contains(token) {
                            tokenScore += 5
                        }
                        if normalizedHeading.contains(token) {
                            tokenScore += 4
                        }
                        if normalizedBody.contains(token) {
                            tokenScore += 1
                        }
                    }
                    guard tokenScore > 0 else {
                        continue
                    }
                    score = min(69, tokenScore)
                    reason = "keyword"
                }
                let key = document.id + "|" + section.heading
                let result = SystemAssetSearchResult(
                    documentID: document.id,
                    fileName: document.fileName,
                    title: document.title,
                    sectionHeading: section.heading,
                    headingPath: section.headingPath,
                    text: section.displayText,
                    score: score,
                    reason: reason,
                    contentHash: document.contentHash
                )
                if let existing = bestByKey[key] {
                    if result.score > existing.score {
                        bestByKey[key] = result
                    }
                } else {
                    bestByKey[key] = result
                }
            }
        }
        let ranked = bestByKey.values.sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            if $0.fileName != $1.fileName {
                return $0.fileName < $1.fileName
            }
            return $0.sectionHeading < $1.sectionHeading
        }
        return Array(ranked.prefix(max(0, limit)))
    }

    public func resolveDependencies(of fileNames: [String]) -> [String] {
        var resolved: [String] = []
        var visited = Set(fileNames)
        var queue = fileNames
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard let document = byFileName[current] else {
                continue
            }
            for dependency in document.dependencies where !visited.contains(dependency) {
                visited.insert(dependency)
                resolved.append(dependency)
                queue.append(dependency)
            }
        }
        return resolved
    }

    public func changedDocumentIDs(comparedTo other: SystemAssetIndex) -> [String] {
        var changed: [String] = []
        let allIDs = Set(byID.keys).union(other.byID.keys)
        for id in allIDs.sorted() {
            if byID[id]?.contentHash != other.byID[id]?.contentHash {
                changed.append(id)
            }
        }
        return changed
    }

    public static func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func tokenize(_ normalizedText: String) -> [String] {
        normalizedText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
