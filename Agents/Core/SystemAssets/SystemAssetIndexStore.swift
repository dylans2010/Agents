import CryptoKit
import Foundation

public nonisolated struct SystemAssetIndexHealth: Sendable {
    public var isReady: Bool
    public var totalDocuments: Int
    public var schemaVersion: Int
    public var indexVersion: Int
    public var lastRefreshAt: Date?
    public var lastRefreshChangedCount: Int
    public var lastRefreshError: String?
    public var persistenceAvailable: Bool

    public init(isReady: Bool, totalDocuments: Int, schemaVersion: Int, indexVersion: Int, lastRefreshAt: Date?, lastRefreshChangedCount: Int, lastRefreshError: String?, persistenceAvailable: Bool) {
        self.isReady = isReady
        self.totalDocuments = totalDocuments
        self.schemaVersion = schemaVersion
        self.indexVersion = indexVersion
        self.lastRefreshAt = lastRefreshAt
        self.lastRefreshChangedCount = lastRefreshChangedCount
        self.lastRefreshError = lastRefreshError
        self.persistenceAvailable = persistenceAvailable
    }
}

public nonisolated struct SystemAssetIndexProgress: Sendable {
    public nonisolated enum Phase: String, Sendable {
        case loading
        case validating
        case scanning
        case indexing
        case persisting
        case done
    }

    public var phase: Phase
    public var totalFiles: Int
    public var processedFiles: Int
    public var changedDocuments: Int

    public init(phase: Phase, totalFiles: Int, processedFiles: Int, changedDocuments: Int) {
        self.phase = phase
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.changedDocuments = changedDocuments
    }
}

public nonisolated struct SystemAssetIndexRefreshResult: Sendable {
    public var succeeded: Bool
    public var error: String?
    public var addedDocumentIDs: [String]
    public var removedDocumentIDs: [String]
    public var changedDocumentIDs: [String]
    public var renamedDocumentIDs: [(from: String, to: String)]
    public var totalDocuments: Int
    public var indexVersion: Int
    public var fullRebuild: Bool
    public var persisted: Bool

    public init(succeeded: Bool, error: String?, addedDocumentIDs: [String], removedDocumentIDs: [String], changedDocumentIDs: [String], renamedDocumentIDs: [(from: String, to: String)], totalDocuments: Int, indexVersion: Int, fullRebuild: Bool, persisted: Bool) {
        self.succeeded = succeeded
        self.error = error
        self.addedDocumentIDs = addedDocumentIDs
        self.removedDocumentIDs = removedDocumentIDs
        self.changedDocumentIDs = changedDocumentIDs
        self.renamedDocumentIDs = renamedDocumentIDs
        self.totalDocuments = totalDocuments
        self.indexVersion = indexVersion
        self.fullRebuild = fullRebuild
        self.persisted = persisted
    }
}

public nonisolated struct SystemAssetPersistedIndex: Codable, Sendable {
    public var schemaVersion: Int
    public var indexVersion: Int
    public var sourceDirectory: String
    public var documents: [SystemAssetDocument]
    public var chunks: [SystemAssetChunk]
    public var postings: [String: [SystemAssetPosting]]
    public var keywordsByDocumentID: [String: [String]]
    public var dependentsByFileName: [String: [String]]
    public var fingerprints: [String: SystemAssetFingerprint]
    public var checksum: String

    public init(schemaVersion: Int, indexVersion: Int, sourceDirectory: String, documents: [SystemAssetDocument], chunks: [SystemAssetChunk], postings: [String: [SystemAssetPosting]], keywordsByDocumentID: [String: [String]], dependentsByFileName: [String: [String]], fingerprints: [String: SystemAssetFingerprint], checksum: String) {
        self.schemaVersion = schemaVersion
        self.indexVersion = indexVersion
        self.sourceDirectory = sourceDirectory
        self.documents = documents
        self.chunks = chunks
        self.postings = postings
        self.keywordsByDocumentID = keywordsByDocumentID
        self.dependentsByFileName = dependentsByFileName
        self.fingerprints = fingerprints
        self.checksum = checksum
    }
}

public nonisolated final class SystemAssetIndexStore: @unchecked Sendable {
    public static let currentSchemaVersion = 1
    public static let applicationName = "Coincide"
    public static let storeDirectoryName = "SystemAssets"

    public let sourceDirectory: URL
    public let storeDirectory: URL
    public let storeFileURL: URL

    private let lock = NSLock()
    private var _snapshot: SystemAssetIndex?
    private var _payload: SystemAssetPersistedIndex?
    private var _loadError: SystemAssetError?
    private var _health: SystemAssetIndexHealth
    private var _persistedOnDisk = false

    public init(sourceDirectory: URL, storeDirectory: URL? = nil) {
        let canonical = Self.canonicalPath(of: sourceDirectory)
        self.sourceDirectory = URL(fileURLWithPath: canonical)
        let directory = storeDirectory ?? Self.defaultStoreDirectory()
        self.storeDirectory = directory
        self.storeFileURL = directory.appendingPathComponent(Self.storeFileName(sourceDirectory: sourceDirectory))
        self._health = SystemAssetIndexHealth(
            isReady: false,
            totalDocuments: 0,
            schemaVersion: Self.currentSchemaVersion,
            indexVersion: 0,
            lastRefreshAt: nil,
            lastRefreshChangedCount: 0,
            lastRefreshError: nil,
            persistenceAvailable: true
        )
    }

    public static func canonicalPath(of directory: URL) -> String {
        directory.standardizedFileURL.resolvingSymlinksInPath().path
    }

    public static func defaultStoreDirectory() -> URL {
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return base.appendingPathComponent(applicationName).appendingPathComponent(storeDirectoryName)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(applicationName)
            .appendingPathComponent(storeDirectoryName)
    }

    public static func storeFileName(sourceDirectory: URL) -> String {
        let digest = SystemAssetDocument.sha256Hex(of: Data(canonicalPath(of: sourceDirectory).utf8))
        return "system-assets-index-v" + String(currentSchemaVersion) + "-" + String(digest.prefix(16)) + ".json"
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static func encodePayload(_ payload: SystemAssetPersistedIndex) throws -> Data {
        try makeEncoder().encode(payload)
    }

    static func decodePayload(_ data: Data) throws -> SystemAssetPersistedIndex {
        try makeDecoder().decode(SystemAssetPersistedIndex.self, from: data)
    }

    static func checksum(of payload: SystemAssetPersistedIndex) -> String {
        var copy = payload
        copy.checksum = ""
        guard let data = try? encodePayload(copy) else {
            return ""
        }
        return SystemAssetDocument.sha256Hex(of: data)
    }

    public func snapshot() -> SystemAssetIndex? {
        lock.lock()
        defer { lock.unlock() }
        return _snapshot
    }

    public func health() -> SystemAssetIndexHealth {
        lock.lock()
        defer { lock.unlock() }
        return _health
    }

    public func loadError() -> SystemAssetError? {
        lock.lock()
        defer { lock.unlock() }
        return _loadError
    }

    public func loadOrRebuild(progress: ((SystemAssetIndexProgress) -> Void)? = nil) throws -> SystemAssetIndex {
        lock.lock()
        var pending: [SystemAssetIndexProgress] = []
        defer {
            lock.unlock()
            for event in pending {
                progress?(event)
            }
        }
        pending.append(SystemAssetIndexProgress(phase: .loading, totalFiles: 0, processedFiles: 0, changedDocuments: 0))
        if let loaded = readPersisted() {
            pending.append(SystemAssetIndexProgress(phase: .validating, totalFiles: loaded.documents.count, processedFiles: 0, changedDocuments: 0))
            do {
                let repaired = try validateAndRepair(loaded)
                let baseIndex = SystemAssetIndex(
                    directory: sourceDirectory,
                    documents: repaired.documents,
                    chunks: repaired.chunks,
                    postings: repaired.postings,
                    keywordsByDocumentID: repaired.keywordsByDocumentID,
                    dependentsByFileName: repaired.dependentsByFileName
                )
                _snapshot = baseIndex
                _payload = repaired
                _loadError = nil
                _health = SystemAssetIndexHealth(
                    isReady: true,
                    totalDocuments: baseIndex.documentCount,
                    schemaVersion: Self.currentSchemaVersion,
                    indexVersion: repaired.indexVersion,
                    lastRefreshAt: _health.lastRefreshAt,
                    lastRefreshChangedCount: _health.lastRefreshChangedCount,
                    lastRefreshError: nil,
                    persistenceAvailable: _health.persistenceAvailable
                )
                do {
                    let outcome = try refreshFromPayload(repaired, progress: { pending.append($0) })
                    return outcome.index
                } catch {
                    _health.lastRefreshError = Self.describe(error)
                    _health.lastRefreshAt = Date()
                    return baseIndex
                }
            } catch {
                _health.lastRefreshError = Self.describe(error)
            }
        }
        do {
            return try fullRebuild(progress: { pending.append($0) })
        } catch let error as SystemAssetError {
            _loadError = error
            throw error
        } catch {
            let wrapped = SystemAssetError.retrievalUnavailable(reason: error.localizedDescription)
            _loadError = wrapped
            throw wrapped
        }
    }

    public func refresh(progress: ((SystemAssetIndexProgress) -> Void)? = nil) -> SystemAssetIndexRefreshResult {
        lock.lock()
        var pending: [SystemAssetIndexProgress] = []
        defer {
            lock.unlock()
            for event in pending {
                progress?(event)
            }
        }
        guard _snapshot != nil else {
            return SystemAssetIndexRefreshResult(
                succeeded: false,
                error: "System asset index is not ready.",
                addedDocumentIDs: [],
                removedDocumentIDs: [],
                changedDocumentIDs: [],
                renamedDocumentIDs: [],
                totalDocuments: 0,
                indexVersion: _health.indexVersion,
                fullRebuild: false,
                persisted: false
            )
        }
        if let current = _payload {
            do {
                let outcome = try refreshFromPayload(current, progress: { pending.append($0) })
                return outcome.result
            } catch {
                _health.lastRefreshError = Self.describe(error)
                _health.lastRefreshAt = Date()
                return SystemAssetIndexRefreshResult(
                    succeeded: false,
                    error: Self.describe(error),
                    addedDocumentIDs: [],
                    removedDocumentIDs: [],
                    changedDocumentIDs: [],
                    renamedDocumentIDs: [],
                    totalDocuments: _snapshot?.documentCount ?? 0,
                    indexVersion: _health.indexVersion,
                    fullRebuild: false,
                    persisted: false
                )
            }
        }
        do {
            let index = try SystemAssetIndex.load(directory: sourceDirectory)
            let derived = SystemAssetIndexStructures.derive(documents: index.documents)
            let rebuilt = SystemAssetIndex(
                directory: sourceDirectory,
                documents: index.documents,
                chunks: derived.chunks,
                postings: derived.postings,
                keywordsByDocumentID: derived.keywordsByDocumentID,
                dependentsByFileName: derived.dependentsByFileName
            )
            let changed = _snapshot.map { rebuilt.changedDocumentIDs(comparedTo: $0) } ?? []
            _snapshot = rebuilt
            _loadError = nil
            _health = SystemAssetIndexHealth(
                isReady: true,
                totalDocuments: rebuilt.documentCount,
                schemaVersion: Self.currentSchemaVersion,
                indexVersion: _health.indexVersion,
                lastRefreshAt: Date(),
                lastRefreshChangedCount: changed.count,
                lastRefreshError: nil,
                persistenceAvailable: false
            )
            pending.append(SystemAssetIndexProgress(phase: .done, totalFiles: rebuilt.documentCount, processedFiles: rebuilt.documentCount, changedDocuments: changed.count))
            return SystemAssetIndexRefreshResult(
                succeeded: true,
                error: nil,
                addedDocumentIDs: [],
                removedDocumentIDs: [],
                changedDocumentIDs: changed,
                renamedDocumentIDs: [],
                totalDocuments: rebuilt.documentCount,
                indexVersion: _health.indexVersion,
                fullRebuild: true,
                persisted: false
            )
        } catch {
            _health.lastRefreshError = Self.describe(error)
            _health.lastRefreshAt = Date()
            return SystemAssetIndexRefreshResult(
                succeeded: false,
                error: Self.describe(error),
                addedDocumentIDs: [],
                removedDocumentIDs: [],
                changedDocumentIDs: [],
                renamedDocumentIDs: [],
                totalDocuments: _snapshot?.documentCount ?? 0,
                indexVersion: _health.indexVersion,
                fullRebuild: false,
                persisted: false
            )
        }
    }

    private func readPersisted() -> SystemAssetPersistedIndex? {
        guard FileManager.default.fileExists(atPath: storeFileURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: storeFileURL) else {
            moveCorruptAside()
            return nil
        }
        guard let decoded = try? Self.decodePayload(data) else {
            moveCorruptAside()
            return nil
        }
        guard decoded.schemaVersion == Self.currentSchemaVersion else {
            moveCorruptAside()
            return nil
        }
        guard decoded.sourceDirectory == Self.canonicalPath(of: sourceDirectory) else {
            moveCorruptAside()
            return nil
        }
        guard Self.checksum(of: decoded) == decoded.checksum else {
            moveCorruptAside()
            return nil
        }
        _persistedOnDisk = true
        return decoded
    }

    private func moveCorruptAside() {
        let aside = storeDirectory.appendingPathComponent(storeFileURL.lastPathComponent + ".corrupt")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: storeFileURL, to: aside)
    }

    private func validateAndRepair(_ payload: SystemAssetPersistedIndex) throws -> SystemAssetPersistedIndex {
        var documents = payload.documents
        var fingerprints = payload.fingerprints
        var repaired = false
        var structuresDirty = false
        let paths = Set(documents.map(\.relativePath))
        let orphanPaths = fingerprints.keys.filter { !paths.contains($0) }
        for path in orphanPaths {
            fingerprints.removeValue(forKey: path)
            repaired = true
        }
        let documentIDs = Set(documents.map(\.id))
        var reparsePaths: [String] = []
        for document in documents {
            let textHash = SystemAssetDocument.sha256Hex(of: Data(document.rawText.utf8))
            let fingerprint = fingerprints[document.relativePath]
            if textHash != document.contentHash || fingerprint == nil || fingerprint?.contentHash != document.contentHash {
                reparsePaths.append(document.relativePath)
            }
        }
        let chunkIDs = Set(payload.chunks.map(\.id))
        if payload.chunks.contains(where: { !documentIDs.contains($0.documentID) }) {
            structuresDirty = true
        }
        let allPostings = payload.postings.values.flatMap { $0 }
        if allPostings.contains(where: { ($0.chunkID != nil && !chunkIDs.contains($0.chunkID!)) || !documentIDs.contains($0.documentID) }) {
            structuresDirty = true
        }
        if !structuresDirty {
            let docLevelMissing = documents.contains { document in
                let fields = [(document.title, SystemAssetPostingField.title), (document.fileName, .fileName), (document.id, .identifier)]
                return fields.contains { field in
                    SystemAssetIndex.tokenize(SystemAssetIndex.normalized(field.0)).contains { token in
                        !(payload.postings[token] ?? []).contains { $0.chunkID == nil && $0.documentID == document.id && $0.field == field.1 }
                    }
                }
            }
            if docLevelMissing {
                structuresDirty = true
            }
        }
        if !reparsePaths.isEmpty {
            var byPath: [String: SystemAssetDocument] = [:]
            for document in documents {
                byPath[document.relativePath] = document
            }
            for path in reparsePaths {
                let fileURL = sourceDirectory.appendingPathComponent(path)
                if let data = try? Data(contentsOf: fileURL) {
                    byPath[path] = try SystemAssetDocument.parse(fileName: fileURL.lastPathComponent, relativePath: path, data: data)
                } else {
                    byPath.removeValue(forKey: path)
                    fingerprints.removeValue(forKey: path)
                }
                repaired = true
            }
            documents = byPath.values.sorted { $0.relativePath < $1.relativePath }
            structuresDirty = true
        }
        var result = payload
        result.documents = documents
        result.fingerprints = fingerprints
        if structuresDirty {
            let derived = SystemAssetIndexStructures.derive(documents: documents)
            result.chunks = derived.chunks
            result.postings = derived.postings
            result.keywordsByDocumentID = derived.keywordsByDocumentID
            result.dependentsByFileName = derived.dependentsByFileName
            repaired = true
        }
        if repaired {
            result.indexVersion = payload.indexVersion + 1
            let (stored, ok) = persist(result)
            if !ok {
                _health.persistenceAvailable = false
            }
            return stored
        }
        return result
    }

    private func fullRebuild(progress: ((SystemAssetIndexProgress) -> Void)?) throws -> SystemAssetIndex {
        progress?(SystemAssetIndexProgress(phase: .scanning, totalFiles: 0, processedFiles: 0, changedDocuments: 0))
        let loaded = try SystemAssetIndex.load(directory: sourceDirectory)
        let scan = try SystemAssetSourceScan.scan(directory: sourceDirectory)
        progress?(SystemAssetIndexProgress(phase: .indexing, totalFiles: scan.count, processedFiles: 0, changedDocuments: 0))
        let derived = SystemAssetIndexStructures.derive(documents: loaded.documents)
        let index = SystemAssetIndex(
            directory: sourceDirectory,
            documents: loaded.documents,
            chunks: derived.chunks,
            postings: derived.postings,
            keywordsByDocumentID: derived.keywordsByDocumentID,
            dependentsByFileName: derived.dependentsByFileName
        )
        let fingerprints = Self.fingerprints(for: index, scan: scan)
        progress?(SystemAssetIndexProgress(phase: .persisting, totalFiles: scan.count, processedFiles: scan.count, changedDocuments: index.documentCount))
        let payload = SystemAssetPersistedIndex(
            schemaVersion: Self.currentSchemaVersion,
            indexVersion: 1,
            sourceDirectory: Self.canonicalPath(of: sourceDirectory),
            documents: index.documents,
            chunks: derived.chunks,
            postings: derived.postings,
            keywordsByDocumentID: derived.keywordsByDocumentID,
            dependentsByFileName: derived.dependentsByFileName,
            fingerprints: fingerprints,
            checksum: ""
        )
        let (stored, ok) = persist(payload)
        _snapshot = index
        _payload = stored
        _loadError = nil
        _health = SystemAssetIndexHealth(
            isReady: true,
            totalDocuments: index.documentCount,
            schemaVersion: Self.currentSchemaVersion,
            indexVersion: stored.indexVersion,
            lastRefreshAt: Date(),
            lastRefreshChangedCount: index.documentCount,
            lastRefreshError: nil,
            persistenceAvailable: ok
        )
        progress?(SystemAssetIndexProgress(phase: .done, totalFiles: scan.count, processedFiles: scan.count, changedDocuments: index.documentCount))
        return index
    }

    private func refreshFromPayload(_ payload: SystemAssetPersistedIndex, progress: ((SystemAssetIndexProgress) -> Void)?) throws -> (index: SystemAssetIndex, result: SystemAssetIndexRefreshResult) {
        progress?(SystemAssetIndexProgress(phase: .scanning, totalFiles: 0, processedFiles: 0, changedDocuments: 0))
        let scan = try SystemAssetSourceScan.scan(directory: sourceDirectory)
        guard !scan.isEmpty else {
            throw SystemAssetError.noDocumentsFound(directory: sourceDirectory)
        }
        let scannedPaths = Set(scan.map(\.relativePath))
        let storedPaths = Set(payload.fingerprints.keys)
        let removedPaths = storedPaths.subtracting(scannedPaths).sorted()
        let addedFiles = scan.filter { !storedPaths.contains($0.relativePath) }
        var documentsByPath: [String: SystemAssetDocument] = [:]
        for document in payload.documents {
            documentsByPath[document.relativePath] = document
        }
        var fingerprints = payload.fingerprints
        var addedIDs: [String] = []
        var removedIDs: [String] = []
        var changedIDs: [String] = []
        var renamedPairs: [(from: String, to: String)] = []
        var touchedFingerprints = false
        var processed = 0
        progress?(SystemAssetIndexProgress(phase: .indexing, totalFiles: scan.count, processedFiles: 0, changedDocuments: 0))
        var removedRecords: [String: SystemAssetDocument] = [:]
        for path in removedPaths {
            if let document = documentsByPath[path] {
                removedRecords[path] = document
            }
        }
        for file in addedFiles {
            let data = try Data(contentsOf: file.fileURL)
            let hash = SystemAssetDocument.sha256Hex(of: data)
            if let matchPath = removedPaths.first(where: { removedRecords[$0]?.contentHash == hash }) {
                let oldDocument = removedRecords[matchPath]!
                removedRecords.removeValue(forKey: matchPath)
                var moved = oldDocument
                moved.id = (file.relativePath as NSString).deletingPathExtension
                moved.fileName = file.fileURL.lastPathComponent
                moved.relativePath = file.relativePath
                if !oldDocument.rawText.contains("<!-- system-index-category:") {
                    let directory = (file.relativePath as NSString).deletingLastPathComponent
                    if !directory.isEmpty && directory != "." {
                        moved.category = (directory as NSString).lastPathComponent
                    } else {
                        moved.category = "General"
                    }
                }
                let hasHeading = oldDocument.rawText.components(separatedBy: "\n").contains { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return trimmed.hasPrefix("# ") && !String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces).isEmpty
                }
                if !hasHeading {
                    moved.title = moved.id
                }
                documentsByPath.removeValue(forKey: matchPath)
                documentsByPath[file.relativePath] = moved
                fingerprints.removeValue(forKey: matchPath)
                fingerprints[file.relativePath] = SystemAssetFingerprint(relativePath: file.relativePath, size: file.size, modificationTime: file.modificationTime, contentHash: hash)
                renamedPairs.append((from: oldDocument.id, to: moved.id))
            } else {
                let parsed = try SystemAssetDocument.parse(fileName: file.fileURL.lastPathComponent, relativePath: file.relativePath, data: data)
                documentsByPath[file.relativePath] = parsed
                fingerprints[file.relativePath] = SystemAssetFingerprint(relativePath: file.relativePath, size: file.size, modificationTime: file.modificationTime, contentHash: parsed.contentHash)
                addedIDs.append(parsed.id)
            }
            processed += 1
            progress?(SystemAssetIndexProgress(phase: .indexing, totalFiles: scan.count, processedFiles: processed, changedDocuments: addedIDs.count + changedIDs.count))
        }
        for file in scan where storedPaths.contains(file.relativePath) {
            guard let stored = fingerprints[file.relativePath] else {
                processed += 1
                continue
            }
            if stored.size == file.size && stored.modificationTime == file.modificationTime {
                processed += 1
                continue
            }
            let data = try Data(contentsOf: file.fileURL)
            let hash = SystemAssetDocument.sha256Hex(of: data)
            if hash == stored.contentHash {
                fingerprints[file.relativePath] = SystemAssetFingerprint(relativePath: file.relativePath, size: file.size, modificationTime: file.modificationTime, contentHash: hash)
                touchedFingerprints = true
            } else {
                let parsed = try SystemAssetDocument.parse(fileName: file.fileURL.lastPathComponent, relativePath: file.relativePath, data: data)
                documentsByPath[file.relativePath] = parsed
                fingerprints[file.relativePath] = SystemAssetFingerprint(relativePath: file.relativePath, size: file.size, modificationTime: file.modificationTime, contentHash: parsed.contentHash)
                changedIDs.append(parsed.id)
            }
            processed += 1
            progress?(SystemAssetIndexProgress(phase: .indexing, totalFiles: scan.count, processedFiles: processed, changedDocuments: addedIDs.count + changedIDs.count))
        }
        for (_, document) in removedRecords {
            documentsByPath.removeValue(forKey: document.relativePath)
            fingerprints.removeValue(forKey: document.relativePath)
            removedIDs.append(document.id)
        }
        let anythingChanged = !addedIDs.isEmpty || !removedIDs.isEmpty || !changedIDs.isEmpty || !renamedPairs.isEmpty || touchedFingerprints
        let finalDocuments = documentsByPath.values.sorted { $0.relativePath < $1.relativePath }
        let derived = SystemAssetIndexStructures.derive(documents: finalDocuments)
        let newIndex = SystemAssetIndex(
            directory: sourceDirectory,
            documents: finalDocuments,
            chunks: derived.chunks,
            postings: derived.postings,
            keywordsByDocumentID: derived.keywordsByDocumentID,
            dependentsByFileName: derived.dependentsByFileName
        )
        let changedByComparison: [String]
        if let oldIndex = _snapshot {
            let compared = newIndex.changedDocumentIDs(comparedTo: oldIndex)
            let renameIDs = Set(renamedPairs.flatMap { [$0.from, $0.to] })
            let excluded = Set(addedIDs).union(removedIDs).union(renameIDs)
            changedByComparison = compared.filter { !excluded.contains($0) }.sorted()
        } else {
            changedByComparison = changedIDs.sorted()
        }
        var newPayload = payload
        newPayload.documents = finalDocuments
        newPayload.chunks = derived.chunks
        newPayload.postings = derived.postings
        newPayload.keywordsByDocumentID = derived.keywordsByDocumentID
        newPayload.dependentsByFileName = derived.dependentsByFileName
        newPayload.fingerprints = fingerprints
        newPayload.indexVersion = payload.indexVersion
        var persisted = false
        if anythingChanged {
            newPayload.indexVersion = payload.indexVersion + 1
            progress?(SystemAssetIndexProgress(phase: .persisting, totalFiles: scan.count, processedFiles: processed, changedDocuments: addedIDs.count + changedByComparison.count))
            let (stored, ok) = persist(newPayload)
            newPayload = stored
            persisted = ok
        }
        let affectedCount = addedIDs.count + removedIDs.count + changedByComparison.count + renamedPairs.count
        _snapshot = newIndex
        _payload = newPayload
        _loadError = nil
        _health = SystemAssetIndexHealth(
            isReady: true,
            totalDocuments: newIndex.documentCount,
            schemaVersion: Self.currentSchemaVersion,
            indexVersion: newPayload.indexVersion,
            lastRefreshAt: Date(),
            lastRefreshChangedCount: affectedCount,
            lastRefreshError: nil,
            persistenceAvailable: anythingChanged ? persisted : _health.persistenceAvailable
        )
        progress?(SystemAssetIndexProgress(phase: .done, totalFiles: scan.count, processedFiles: processed, changedDocuments: affectedCount))
        let result = SystemAssetIndexRefreshResult(
            succeeded: true,
            error: nil,
            addedDocumentIDs: addedIDs.sorted(),
            removedDocumentIDs: removedIDs.sorted(),
            changedDocumentIDs: changedByComparison,
            renamedDocumentIDs: renamedPairs.sorted { $0.from < $1.from },
            totalDocuments: newIndex.documentCount,
            indexVersion: newPayload.indexVersion,
            fullRebuild: false,
            persisted: persisted || (!anythingChanged && _persistedOnDisk)
        )
        return (newIndex, result)
    }

    private func persist(_ payload: SystemAssetPersistedIndex) -> (SystemAssetPersistedIndex, Bool) {
        var stored = payload
        stored.checksum = Self.checksum(of: stored)
        do {
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            let data = try Self.encodePayload(stored)
            try data.write(to: storeFileURL, options: [.atomic])
            _persistedOnDisk = true
            return (stored, true)
        } catch {
            _persistedOnDisk = false
            return (stored, false)
        }
    }

    private static func fingerprints(for index: SystemAssetIndex, scan: [SystemAssetScannedFile]) -> [String: SystemAssetFingerprint] {
        var result: [String: SystemAssetFingerprint] = [:]
        for file in scan {
            let contentHash: String
            if let document = index.document(relativePath: file.relativePath) {
                contentHash = document.contentHash
            } else if let data = try? Data(contentsOf: file.fileURL) {
                contentHash = SystemAssetDocument.sha256Hex(of: data)
            } else {
                continue
            }
            result[file.relativePath] = SystemAssetFingerprint(
                relativePath: file.relativePath,
                size: file.size,
                modificationTime: file.modificationTime,
                contentHash: contentHash
            )
        }
        return result
    }

    private static func describe(_ error: Error) -> String {
        if let assetError = error as? SystemAssetError {
            return assetError.localizedDescription
        }
        return "System asset index refresh failed."
    }
}
