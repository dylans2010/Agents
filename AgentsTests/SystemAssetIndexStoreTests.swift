import Foundation
import Testing
@testable import Agents

@Suite("Persistent Versioned System Assets Index")
struct SystemAssetIndexStoreTests {

    private static func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeSource(names: [String]) throws -> URL {
        let source = Self.makeTemporaryDirectory()
        for (offset, name) in names.enumerated() {
            let content = "# " + name + "\n\nBody text for " + name + " with token doc" + String(offset) + ".\n"
            try content.write(to: source.appendingPathComponent(name + ".md"), atomically: true, encoding: .utf8)
        }
        return source
    }

    private static func makeManager(source: URL, store: URL) -> SystemAssetManager {
        SystemAssetManager(directory: source, storeDirectory: store)
    }

    private static func cleanup(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test("Persisted index round-trips and the second launch reuses it without changes")
    func persistedIndexRoundTrip() throws {
        let source = try Self.makeSource(names: ["Alpha", "Beta", "Gamma"])
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let first = Self.makeManager(source: source, store: store)
        #expect(first.isReady)
        #expect(first.documentCount == 3)
        #expect(first.indexHealth.schemaVersion == SystemAssetIndexStore.currentSchemaVersion)
        #expect(first.indexHealth.indexVersion == 1)
        #expect(first.indexHealth.persistenceAvailable)
        let firstVersion = first.indexHealth.indexVersion
        let second = Self.makeManager(source: source, store: store)
        #expect(second.isReady)
        #expect(second.documentCount == 3)
        #expect(second.indexHealth.indexVersion == firstVersion)
        let firstIndex = try #require(first.index)
        let secondIndex = try #require(second.index)
        #expect(firstIndex.documents.map(\.contentHash) == secondIndex.documents.map(\.contentHash))
        #expect(firstIndex.documents.map(\.title) == secondIndex.documents.map(\.title))
        #expect(firstIndex.chunks.map(\.id) == secondIndex.chunks.map(\.id))
        #expect(firstIndex.postings.keys.sorted() == secondIndex.postings.keys.sorted())
        let refresh = second.refresh()
        #expect(refresh.succeeded)
        #expect(refresh.addedDocumentIDs.isEmpty)
        #expect(refresh.removedDocumentIDs.isEmpty)
        #expect(refresh.changedDocumentIDs.isEmpty)
        #expect(refresh.renamedDocumentIDs.isEmpty)
        #expect(refresh.indexVersion == firstVersion)
    }

    @Test("Modifying one document reindexes only that document and never serves stale text")
    func incrementalModify() throws {
        let source = try Self.makeSource(names: ["Alpha", "Beta", "Gamma"])
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let manager = Self.makeManager(source: source, store: store)
        #expect(manager.isReady)
        #expect(manager.search("doc0").first?.fileName == "Alpha.md")
        let before = try #require(manager.index)
        let alphaBefore = try #require(manager.document(fileName: "Alpha.md"))
        try "# Alpha\n\nRewritten alpha body with token rewrittenalpha.\n".write(to: source.appendingPathComponent("Alpha.md"), atomically: true, encoding: .utf8)
        let result = manager.refresh()
        #expect(result.succeeded)
        #expect(result.changedDocumentIDs == ["Alpha"])
        #expect(result.addedDocumentIDs.isEmpty)
        #expect(result.removedDocumentIDs.isEmpty)
        #expect(result.renamedDocumentIDs.isEmpty)
        let after = try #require(manager.index)
        #expect(after.changedDocumentIDs(comparedTo: before) == result.changedDocumentIDs)
        let alphaAfter = try #require(manager.document(fileName: "Alpha.md"))
        #expect(alphaAfter.contentHash != alphaBefore.contentHash)
        #expect(alphaAfter.rawText.contains("rewrittenalpha"))
        #expect(!alphaAfter.rawText.contains("doc0"))
        #expect(manager.search("doc0").isEmpty)
        #expect(manager.search("rewrittenalpha").first?.fileName == "Alpha.md")
        #expect(manager.document(fileName: "Beta.md")?.contentHash == before.document(fileName: "Beta.md")?.contentHash)
        #expect(manager.document(fileName: "Gamma.md")?.contentHash == before.document(fileName: "Gamma.md")?.contentHash)
    }

    @Test("Added and removed documents are detected by refresh")
    func incrementalAddAndRemove() throws {
        let source = try Self.makeSource(names: ["Alpha", "Beta"])
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let manager = Self.makeManager(source: source, store: store)
        #expect(manager.documentCount == 2)
        try "# Delta\n\nDelta body with token deltadoc.\n".write(to: source.appendingPathComponent("Delta.md"), atomically: true, encoding: .utf8)
        let added = manager.refresh()
        #expect(added.succeeded)
        #expect(added.addedDocumentIDs == ["Delta"])
        #expect(manager.documentCount == 3)
        #expect(manager.document(fileName: "Delta.md") != nil)
        try FileManager.default.removeItem(at: source.appendingPathComponent("Beta.md"))
        let removed = manager.refresh()
        #expect(removed.succeeded)
        #expect(removed.removedDocumentIDs == ["Beta"])
        #expect(manager.documentCount == 2)
        #expect(manager.document(fileName: "Beta.md") == nil)
        #expect(manager.search("doc1").isEmpty)
    }

    @Test("Renaming a file is detected by content hash without reindexing its content")
    func incrementalRename() throws {
        let source = try Self.makeSource(names: ["Alpha", "Beta"])
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let manager = Self.makeManager(source: source, store: store)
        let alphaHash = try #require(manager.document(fileName: "Alpha.md")).contentHash
        try FileManager.default.moveItem(at: source.appendingPathComponent("Alpha.md"), to: source.appendingPathComponent("Renamed.md"))
        let result = manager.refresh()
        #expect(result.succeeded)
        #expect(result.renamedDocumentIDs.count == 1)
        #expect(result.renamedDocumentIDs.first?.from == "Alpha")
        #expect(result.renamedDocumentIDs.first?.to == "Renamed")
        #expect(result.addedDocumentIDs.isEmpty)
        #expect(result.removedDocumentIDs.isEmpty)
        #expect(result.changedDocumentIDs.isEmpty)
        #expect(manager.documentCount == 2)
        #expect(manager.document(fileName: "Alpha.md") == nil)
        let renamed = try #require(manager.document(fileName: "Renamed.md"))
        #expect(renamed.contentHash == alphaHash)
        #expect(renamed.id == "Renamed")
        #expect(renamed.title == "Alpha")
    }

    @Test("Renaming across directories re-derives category and a heading-less title")
    func renameRederivesCategoryAndFallbackTitle() throws {
        let source = Self.makeTemporaryDirectory()
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let guides = source.appendingPathComponent("Guides")
        try FileManager.default.createDirectory(at: guides, withIntermediateDirectories: true)
        try "Body without a heading and token guidebody.\n".write(to: guides.appendingPathComponent("Old.md"), atomically: true, encoding: .utf8)
        try "# Kept Title\n\nHeaded body with token headedbody.\n".write(to: guides.appendingPathComponent("Headed.md"), atomically: true, encoding: .utf8)
        let manager = Self.makeManager(source: source, store: store)
        let before = try #require(manager.document(fileName: "Old.md"))
        #expect(before.category == "Guides")
        #expect(before.title == "Guides/Old")
        let other = source.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: guides.appendingPathComponent("Old.md"), to: other.appendingPathComponent("New.md"))
        try FileManager.default.moveItem(at: guides.appendingPathComponent("Headed.md"), to: other.appendingPathComponent("Headed.md"))
        let result = manager.refresh()
        #expect(result.succeeded)
        #expect(result.renamedDocumentIDs.count == 2)
        let renamed = try #require(manager.document(fileName: "New.md"))
        #expect(renamed.category == "Other")
        #expect(renamed.title == "Other/New")
        #expect(renamed.id == "Other/New")
        let headed = try #require(manager.document(fileName: "Headed.md"))
        #expect(headed.category == "Other")
        #expect(headed.title == "Kept Title")
    }

    @Test("Touching a file without changing its bytes reports no content changes")
    func fingerprintTouchWithoutChange() throws {
        let source = try Self.makeSource(names: ["Alpha", "Beta"])
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let manager = Self.makeManager(source: source, store: store)
        let path = source.appendingPathComponent("Alpha.md").path
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: path)
        let result = manager.refresh()
        #expect(result.succeeded)
        #expect(result.addedDocumentIDs.isEmpty)
        #expect(result.removedDocumentIDs.isEmpty)
        #expect(result.changedDocumentIDs.isEmpty)
        #expect(result.renamedDocumentIDs.isEmpty)
        #expect(manager.documentCount == 2)
    }

    @Test("A corrupt persisted index is rebuilt from source and the manager stays ready")
    func corruptIndexRebuilds() throws {
        let source = try Self.makeSource(names: ["Alpha", "Beta"])
        let storeDir = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, storeDir]) }
        let first = Self.makeManager(source: source, store: storeDir)
        #expect(first.isReady)
        let store = SystemAssetIndexStore(sourceDirectory: source, storeDirectory: storeDir)
        try Data("this is not a persisted index".utf8).write(to: store.storeFileURL, options: [.atomic])
        let second = Self.makeManager(source: source, store: storeDir)
        #expect(second.isReady)
        #expect(second.documentCount == 2)
        #expect(second.indexHealth.schemaVersion == SystemAssetIndexStore.currentSchemaVersion)
        let payload = try SystemAssetIndexStore.decodePayload(Data(contentsOf: store.storeFileURL))
        #expect(payload.schemaVersion == SystemAssetIndexStore.currentSchemaVersion)
        #expect(payload.documents.count == 2)
    }

    @Test("A persisted index with a newer schema version is rebuilt at the current version")
    func schemaVersionMismatchRebuilds() throws {
        let source = try Self.makeSource(names: ["Alpha", "Beta"])
        let storeDir = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, storeDir]) }
        let first = Self.makeManager(source: source, store: storeDir)
        #expect(first.isReady)
        let store = SystemAssetIndexStore(sourceDirectory: source, storeDirectory: storeDir)
        var payload = try SystemAssetIndexStore.decodePayload(Data(contentsOf: store.storeFileURL))
        payload.schemaVersion = 99
        payload.checksum = SystemAssetIndexStore.checksum(of: payload)
        try SystemAssetIndexStore.encodePayload(payload).write(to: store.storeFileURL, options: [.atomic])
        let second = Self.makeManager(source: source, store: storeDir)
        #expect(second.isReady)
        #expect(second.documentCount == 2)
        #expect(second.indexHealth.schemaVersion == SystemAssetIndexStore.currentSchemaVersion)
        let rewritten = try SystemAssetIndexStore.decodePayload(Data(contentsOf: store.storeFileURL))
        #expect(rewritten.schemaVersion == SystemAssetIndexStore.currentSchemaVersion)
    }

    @Test("Recursive discovery finds nested documents with relative paths and directory categories")
    func recursiveDiscovery() throws {
        let source = Self.makeTemporaryDirectory()
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let nested = source.appendingPathComponent("Guides")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "# Nested Guide\n\nNested body with token nestedguide.\n".write(to: nested.appendingPathComponent("Nested.md"), atomically: true, encoding: .utf8)
        try "# Top Level\n\nTop body with token toplevel.\n".write(to: source.appendingPathComponent("Top.md"), atomically: true, encoding: .utf8)
        let manager = Self.makeManager(source: source, store: store)
        #expect(manager.isReady)
        #expect(manager.documentCount == 2)
        let nestedDoc = try #require(manager.document(fileName: "Nested.md"))
        #expect(nestedDoc.relativePath == "Guides/Nested.md")
        #expect(nestedDoc.id == "Guides/Nested")
        #expect(nestedDoc.category == "Guides")
        #expect(manager.index?.document(relativePath: "Guides/Nested.md") != nil)
        #expect(manager.search("nestedguide").first?.fileName == "Nested.md")
    }

    @Test("Category and tag markers are parsed, kept out of section bodies, and queryable")
    func categoryAndTagMarkers() throws {
        let source = Self.makeTemporaryDirectory()
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let content = "<!-- system-index-category: Workflow -->\n<!-- system-index-tags: planning, review -->\n# Planner Notes\n\nPlanning body with token plannerdoc.\n"
        try content.write(to: source.appendingPathComponent("Planner.md"), atomically: true, encoding: .utf8)
        let manager = Self.makeManager(source: source, store: store)
        let document = try #require(manager.document(fileName: "Planner.md"))
        #expect(document.category == "Workflow")
        #expect(document.tags == ["planning", "review"])
        #expect(document.sections.allSatisfy { !$0.body.contains("system-index-") })
        let index = try #require(manager.index)
        #expect(index.documents(category: "Workflow").map(\.fileName) == ["Planner.md"])
        #expect(index.documents(tag: "planning").map(\.fileName) == ["Planner.md"])
        #expect(index.documents(tag: "review").map(\.fileName) == ["Planner.md"])
        #expect(index.documents(tag: "missing").isEmpty)
    }

    @Test("Long sections split into heading-carrying chunks that preserve the body in order")
    func chunkingSplitsLongSections() throws {
        let source = Self.makeTemporaryDirectory()
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let paragraph = (0..<40).map { _ in "Chunkable sentence with token chunkbody." }.joined(separator: " ")
        var body = "# Long Section\n\n"
        for _ in 0..<12 {
            body += paragraph + "\n\n"
        }
        try body.write(to: source.appendingPathComponent("Long.md"), atomically: true, encoding: .utf8)
        let manager = Self.makeManager(source: source, store: store)
        let index = try #require(manager.index)
        let chunks = index.chunks(forDocumentID: "Long")
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.heading == "Long Section" })
        #expect(chunks.allSatisfy { $0.text.count <= SystemAssetChunk.maxChunkCharacters })
        #expect(chunks.allSatisfy { $0.headingPath == ["Long Section"] })
        let originalBody = try #require(manager.document(fileName: "Long.md")).sections.first?.body
        #expect(chunks.map(\.body).joined(separator: "\n\n") == originalBody)
        let firstChunk = try #require(index.chunk(id: chunks[0].id))
        #expect(firstChunk.documentID == "Long")
        #expect(firstChunk.ordinal == 0)
    }

    @Test("Postings resolve a distinctive token to its chunks and keywords cover the document")
    func postingsAndKeywords() throws {
        let source = try Self.makeSource(names: ["Alpha"])
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        try "# Quokka Notes\n\nQuokka body with a very distinctive quokka token.\n".write(to: source.appendingPathComponent("Quokka.md"), atomically: true, encoding: .utf8)
        let manager = Self.makeManager(source: source, store: store)
        let index = try #require(manager.index)
        let postings = index.postings(for: "quokka")
        #expect(!postings.isEmpty)
        #expect(postings.allSatisfy { $0.documentID == "Quokka" })
        #expect(postings.contains { $0.field == .title })
        #expect(postings.contains { $0.field == .body })
        #expect(index.postings(for: "zzzznothing").isEmpty)
        #expect(index.keywords(forDocumentID: "Quokka").contains("quokka"))
        #expect(index.keywords(forDocumentID: "Quokka").contains("notes"))
    }

    @Test("Doc-level postings keep every document sharing a title or file-name token")
    func docLevelPostingsKeepEveryDocument() throws {
        let source = Self.makeTemporaryDirectory()
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        try "# Swift Guide\n\nFirst swift body.\n".write(to: source.appendingPathComponent("SwiftOne.md"), atomically: true, encoding: .utf8)
        try "# Swift Notes\n\nSecond swift body.\n".write(to: source.appendingPathComponent("SwiftTwo.md"), atomically: true, encoding: .utf8)
        let manager = Self.makeManager(source: source, store: store)
        let index = try #require(manager.index)
        let titleDocumentIDs = Set(index.postings(for: "swift").filter { $0.field == .title }.map(\.documentID))
        #expect(titleDocumentIDs == ["SwiftOne", "SwiftTwo"])
        let fileNameDocumentIDs = Set(index.postings(for: "md").filter { $0.field == .fileName }.map(\.documentID))
        #expect(fileNameDocumentIDs == ["SwiftOne", "SwiftTwo"])
    }

    @Test("A persisted index with lossy doc-level postings is re-derived on load")
    func lossyPersistedPostingsRederivedOnLoad() throws {
        let source = Self.makeTemporaryDirectory()
        let storeDir = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, storeDir]) }
        try "# Swift Guide\n\nFirst swift body.\n".write(to: source.appendingPathComponent("SwiftOne.md"), atomically: true, encoding: .utf8)
        try "# Swift Notes\n\nSecond swift body.\n".write(to: source.appendingPathComponent("SwiftTwo.md"), atomically: true, encoding: .utf8)
        let first = Self.makeManager(source: source, store: storeDir)
        #expect(first.isReady)
        let firstVersion = first.indexHealth.indexVersion
        let store = SystemAssetIndexStore(sourceDirectory: source, storeDirectory: storeDir)
        var payload = try SystemAssetIndexStore.decodePayload(Data(contentsOf: store.storeFileURL))
        var swiftPostings = payload.postings["swift"] ?? []
        swiftPostings.removeAll { $0.field == .title && $0.documentID == "SwiftOne" }
        payload.postings["swift"] = swiftPostings
        payload.checksum = SystemAssetIndexStore.checksum(of: payload)
        try SystemAssetIndexStore.encodePayload(payload).write(to: store.storeFileURL, options: [.atomic])
        let second = Self.makeManager(source: source, store: storeDir)
        #expect(second.isReady)
        let index = try #require(second.index)
        let titleDocumentIDs = Set(index.postings(for: "swift").filter { $0.field == .title }.map(\.documentID))
        #expect(titleDocumentIDs == ["SwiftOne", "SwiftTwo"])
        #expect(second.indexHealth.indexVersion == firstVersion + 1)
    }

    @Test("Relationships honor declared dependencies in both directions")
    func relationshipsFollowDependencies() throws {
        let source = Self.makeTemporaryDirectory()
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        try "<!-- system-index-depends: Beta.md -->\n# Alpha\n\nAlpha body.\n".write(to: source.appendingPathComponent("Alpha.md"), atomically: true, encoding: .utf8)
        try "# Beta\n\nBeta body.\n".write(to: source.appendingPathComponent("Beta.md"), atomically: true, encoding: .utf8)
        let manager = Self.makeManager(source: source, store: store)
        let index = try #require(manager.index)
        #expect(index.resolveDependencies(of: ["Alpha.md"]) == ["Beta.md"])
        #expect(index.relatedDocumentIDs(ofFileName: "Alpha.md") == ["Beta"])
        #expect(index.relatedDocumentIDs(ofFileName: "Beta.md") == ["Alpha"])
        #expect(index.relatedDocumentIDs(ofFileName: "Missing.md").isEmpty)
    }

    @Test("Refresh reports progress phases with file counts and ends done")
    func refreshReportsProgress() throws {
        let source = try Self.makeSource(names: ["Alpha", "Beta", "Gamma"])
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let manager = Self.makeManager(source: source, store: store)
        try "# Alpha\n\nChanged alpha body with token changedalpha.\n".write(to: source.appendingPathComponent("Alpha.md"), atomically: true, encoding: .utf8)
        var phases: [SystemAssetIndexProgress.Phase] = []
        var last: SystemAssetIndexProgress?
        let result = manager.refresh { progress in
            phases.append(progress.phase)
            last = progress
        }
        #expect(result.succeeded)
        #expect(phases.contains(.scanning))
        #expect(phases.contains(.indexing))
        #expect(phases.contains(.done))
        #expect(last?.phase == .done)
        #expect(last?.totalFiles == 3)
        #expect(last?.processedFiles == 3)
        #expect(manager.indexHealth.lastRefreshChangedCount == 1)
        #expect(manager.indexHealth.lastRefreshAt != nil)
        #expect(manager.indexHealth.lastRefreshError == nil)
    }

    @Test("Progress callbacks may read the store without deadlocking")
    func progressCallbacksMayReadStore() throws {
        let source = try Self.makeSource(names: ["Alpha", "Beta"])
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let manager = Self.makeManager(source: source, store: store)
        var readCounts: [Int] = []
        let result = manager.refresh { _ in
            readCounts.append(manager.indexHealth.totalDocuments)
        }
        #expect(result.succeeded)
        #expect(!readCounts.isEmpty)
        #expect(readCounts.allSatisfy { $0 == 2 })
    }

    @Test("An unusable store directory degrades gracefully without disabling retrieval")
    func unusableStoreDirectoryDegradesGracefully() throws {
        let source = try Self.makeSource(names: ["Alpha", "Beta"])
        let blocker = Self.makeTemporaryDirectory().appendingPathComponent("blocker")
        defer { Self.cleanup([source, blocker]) }
        try "not a directory".write(to: blocker, atomically: true, encoding: .utf8)
        let manager = SystemAssetManager(directory: source, storeDirectory: blocker)
        #expect(manager.isReady)
        #expect(manager.documentCount == 2)
        #expect(!manager.indexHealth.persistenceAvailable)
        #expect(manager.search("doc0").first?.fileName == "Alpha.md")
        let result = manager.refresh()
        #expect(result.succeeded)
        #expect(!result.fullRebuild)
        #expect(!result.persisted)
    }

    @Test("Retrieve works through the persistent index and empty queries stay empty")
    func retrieveThroughPersistentIndex() throws {
        let source = try Self.makeSource(names: ["Alpha"])
        let store = Self.makeTemporaryDirectory()
        defer { Self.cleanup([source, store]) }
        let manager = Self.makeManager(source: source, store: store)
        #expect(manager.isReady)
        let results = manager.retrieve(request: "alpha", provider: nil, model: nil)
        #expect(results.first?.fileName == "Alpha.md")
        #expect(manager.retrieve(request: nil, provider: nil, model: nil).isEmpty)
        #expect(manager.retrieve(request: "   ", provider: nil, model: nil).isEmpty)
    }
}
