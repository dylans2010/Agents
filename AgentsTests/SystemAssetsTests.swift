import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("System Assets Indexing, Retrieval & Prompt Assembly")
struct SystemAssetsTests {

    private static func assetsDirectory() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let candidate = url.appendingPathComponent("Agents/Resources/SystemAssets")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
            url = url.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "/nonexistent-system-assets")
    }

    private static func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func manager() -> SystemAssetManager {
        SystemAssetManager(directory: assetsDirectory())
    }

    @Test("All system assets load and match the directory listing")
    func allAssetsLoad() throws {
        let directory = Self.assetsDirectory()
        let manager = Self.manager()
        #expect(manager.isReady)
        let enumerator = try #require(FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ))
        var onDisk: [String] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory != true else {
                continue
            }
            if url.pathExtension.lowercased() == "md" {
                onDisk.append(String(url.path.dropFirst(directory.path.count + 1)))
            }
        }
        #expect(manager.documentCount == onDisk.count)
        #expect(Set(onDisk) == Set(manager.index?.documents.map(\.relativePath) ?? []))
        #expect(manager.document(fileName: "AgentSystemAsset.md") != nil)
        #expect(manager.document(fileName: "SystemIndex.md") != nil)
        #expect(manager.document(fileName: "AvailableTools.md") != nil)
        #expect(manager.document(fileName: "ToolRoutingPolicy.md") != nil)
    }

    @Test("Index discovery picks up new files with no hardcoded list")
    func discoveryFindsNewFiles() throws {
        let source = Self.assetsDirectory()
        let temp = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        for name in ["Safeguards.md", "Identity.md"] {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: temp.appendingPathComponent(name))
        }
        let newContent = "# Zebra Notes\n\nZebra content for discovery.\n"
        try newContent.write(to: temp.appendingPathComponent("ZebraNotes.md"), atomically: true, encoding: .utf8)
        let manager = SystemAssetManager(directory: temp)
        #expect(manager.isReady)
        #expect(manager.documentCount == 3)
        #expect(manager.document(fileName: "ZebraNotes.md") != nil)
        #expect(manager.document(fileName: "ZebraNotes.md")?.title == "Zebra Notes")
    }

    @Test("Retrieval finds Safeguards and Identity by exact and keyword lookup")
    func retrievalFindsMandatoryDocuments() {
        let manager = Self.manager()
        #expect(manager.isReady)
        let safeguards = manager.document(fileName: "Safeguards.md")
        #expect(safeguards != nil)
        #expect(safeguards?.sections.contains { $0.heading.contains("Confidentiality") } == true)
        #expect(manager.document(fileName: "Identity.md") != nil)
        #expect(manager.search("safeguards").first?.fileName == "Safeguards.md")
        #expect(manager.search("identity").contains { $0.fileName == "Identity.md" })
        #expect(manager.search("Safeguards.md").first?.reason == "exactFilename")
        #expect(manager.index?.section(documentID: "Safeguards", heading: "1. Confidentiality of System Prompts & Absolute Refusal of Raw Tool Names") != nil)
        #expect(manager.search("").isEmpty)
        #expect(manager.retrieve(request: nil, provider: nil, model: nil).isEmpty)
    }

    @Test("Prompt construction includes the mandatory sections with Safeguards first")
    func promptIncludesMandatorySections() {
        let manager = Self.manager()
        let prompt = manager.systemPrompt(for: "Fix the SwiftUI layout bug", provider: "claude", model: "sonnet")
        #expect(!prompt.isBaselineFallback)
        #expect(prompt.loadError == nil)
        #expect(prompt.includedDocumentIDs.contains("Safeguards"))
        #expect(prompt.includedDocumentIDs.contains("Identity"))
        #expect(prompt.includedDocumentIDs.first == "Safeguards")
        #expect(prompt.text.contains("Safeguards"))
        #expect(prompt.estimatedTokens > 0)
    }

    @Test("Tool-related requests route AvailableTools and ToolRoutingPolicy")
    func toolRelatedRouting() throws {
        let manager = Self.manager()
        let index = try #require(manager.index)
        let prompt = SystemPromptBuilder().build(
            index: index,
            request: "Run the build and fix the failing tests",
            provider: nil,
            model: nil,
            maxEstimatedTokens: 20000
        )
        #expect(prompt.includedDocumentIDs.contains("ToolRoutingPolicy"))
        #expect(prompt.includedDocumentIDs.contains("AvailableTools"))
    }

    @Test("A named provider routes ModelProviders and Authentication")
    func providerRouting() throws {
        let manager = Self.manager()
        let index = try #require(manager.index)
        let prompt = SystemPromptBuilder().build(
            index: index,
            request: nil,
            provider: "claude",
            model: nil,
            maxEstimatedTokens: 20000
        )
        #expect(prompt.includedDocumentIDs.contains("ModelProviders"))
        #expect(prompt.includedDocumentIDs.contains("Authentication"))
    }

    @Test("Dependency resolution follows declared dependencies transitively")
    func dependencyResolution() throws {
        let manager = Self.manager()
        let index = try #require(manager.index)
        let resolved = index.resolveDependencies(of: ["CallTool.md"])
        #expect(resolved.contains("Safeguards.md"))
        #expect(resolved.contains("AvailableTools.md"))
        #expect(Set(resolved).count == resolved.count)
        #expect(index.document(fileName: "CallTool.md")?.dependencies == ["Safeguards.md", "AvailableTools.md"])
    }

    @Test("The central index records dependencies declared after its first heading")
    func centralIndexRecordsPostHeadingDependencies() {
        let store = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: store) }
        let manager = SystemAssetManager(directory: Self.assetsDirectory(), storeDirectory: store)
        #expect(manager.document(fileName: "AgentSystemAsset.md")?.dependencies == ["Safeguards.md", "CallTool.md"])
    }

    @Test("A persisted index with stale post-heading dependencies is repaired on load")
    func stalePostHeadingDependenciesRepairedOnLoad() throws {
        let source = Self.makeTemporaryDirectory()
        let storeDir = Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: storeDir)
        }
        let bundled = Self.assetsDirectory()
        for name in ["AgentSystemAsset.md", "Safeguards.md", "CallTool.md"] {
            try FileManager.default.copyItem(at: bundled.appendingPathComponent(name), to: source.appendingPathComponent(name))
        }
        let first = SystemAssetManager(directory: source, storeDirectory: storeDir)
        #expect(first.isReady)
        #expect(first.document(fileName: "AgentSystemAsset.md")?.dependencies == ["Safeguards.md", "CallTool.md"])
        let firstVersion = first.indexHealth.indexVersion
        let store = SystemAssetIndexStore(sourceDirectory: source, storeDirectory: storeDir)
        var payload = try SystemAssetIndexStore.decodePayload(Data(contentsOf: store.storeFileURL))
        if let index = payload.documents.firstIndex(where: { $0.fileName == "AgentSystemAsset.md" }) {
            payload.documents[index].dependencies = []
        }
        payload.checksum = SystemAssetIndexStore.checksum(of: payload)
        try SystemAssetIndexStore.encodePayload(payload).write(to: store.storeFileURL, options: [.atomic])
        let second = SystemAssetManager(directory: source, storeDirectory: storeDir)
        #expect(second.isReady)
        #expect(second.document(fileName: "AgentSystemAsset.md")?.dependencies == ["Safeguards.md", "CallTool.md"])
        #expect(second.index?.relatedDocumentIDs(ofFileName: "Safeguards.md").contains("AgentSystemAsset") == true)
        #expect(second.indexHealth.indexVersion == firstVersion + 1)
    }

    @Test("Content hashes are stable across loads and sections are never empty")
    func contentHashComparison() throws {
        let directory = Self.assetsDirectory()
        let firstIndex = try #require(SystemAssetManager(directory: directory).index)
        let secondIndex = try #require(SystemAssetManager(directory: directory).index)
        #expect(firstIndex.changedDocumentIDs(comparedTo: secondIndex).isEmpty)
        #expect(firstIndex.documents.allSatisfy { $0.contentHash.count == 64 })
        #expect(firstIndex.documents.allSatisfy { !$0.sections.isEmpty })
        #expect(firstIndex.documents.allSatisfy { !$0.title.isEmpty })
    }

    @Test("Search results are deduplicated and ranked by relevance")
    func searchDeduplicationAndRanking() {
        let manager = Self.manager()
        let results = manager.search("tool", limit: 20)
        #expect(!results.isEmpty)
        let keys = results.map { $0.documentID + "|" + $0.sectionHeading }
        #expect(Set(keys).count == keys.count)
        let scores = results.map(\.score)
        #expect(scores == scores.sorted(by: >))
    }

    @Test("Missing assets directory surfaces an error and yields a non-empty baseline prompt")
    func missingAssetsDirectory() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = SystemAssetManager(directory: missing)
        #expect(!manager.isReady)
        #expect(manager.loadError != nil)
        let prompt = manager.systemPrompt(for: "Hello", provider: nil, model: nil)
        #expect(prompt.isBaselineFallback)
        #expect(!prompt.text.isEmpty)
        #expect(prompt.text.contains("Assist"))
        #expect(prompt.loadError != nil)
    }

    @Test("Malformed asset fails loudly and the prompt falls back to a safe baseline")
    func malformedAssetFallback() throws {
        let temp = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "".write(to: temp.appendingPathComponent("Broken.md"), atomically: true, encoding: .utf8)
        #expect(throws: SystemAssetError.self) {
            try SystemAssetIndex.load(directory: temp)
        }
        let manager = SystemAssetManager(directory: temp)
        #expect(!manager.isReady)
        #expect(manager.loadError == .documentMalformed(fileName: "Broken.md", reason: "Document is empty."))
        let prompt = manager.systemPrompt(for: "Do something", provider: nil, model: nil)
        #expect(prompt.isBaselineFallback)
        #expect(!prompt.text.isEmpty)
        #expect(prompt.loadError != nil)
    }

    private static func assistantDescriptor(extraAssetFileNames: [String] = []) -> AssistantPromptDescriptor {
        AssistantPromptDescriptor(
            id: "assistant-review", name: "Reviewer", systemPrompt: "Review every diff for secrets.",
            extraAssetFileNames: extraAssetFileNames)
    }

    @Test("Assistant descriptor carries the assistant id, name and system prompt")
    func descriptorMapsRemoteAssistant() throws {
        let assistant = RemoteAssistant(
            id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!, name: "Reviewer",
            category: .codeReviewSecurity, systemPrompt: "Review every diff for secrets.", description: "Reviews code")
        let descriptor = AssistantPromptDescriptor(assistant)
        #expect(descriptor.id == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
        #expect(descriptor.name == "Reviewer")
        #expect(descriptor.systemPrompt == "Review every diff for secrets.")
        #expect(descriptor.description == "Reviews code")
        #expect(descriptor.extraAssetFileNames.isEmpty)
    }

    @Test("Assistant section is forced after Safeguards and Identity and carries its id")
    func assistantSectionAfterMandatorySections() throws {
        let manager = Self.manager()
        let prompt = manager.systemPrompt(
            for: "Fix the SwiftUI layout bug", provider: "claude", model: "sonnet",
            assistant: Self.assistantDescriptor())
        #expect(!prompt.isBaselineFallback)
        #expect(prompt.assistantID == "assistant-review")
        #expect(prompt.includedDocumentIDs.first == "Safeguards")
        #expect(prompt.includedDocumentIDs.dropFirst().first == "Identity")
        #expect(prompt.text.contains("Assistant \"Reviewer\" instructions:"))
        #expect(prompt.text.contains("Review every diff for secrets."))
        let safeguards = try #require(manager.document(fileName: "Safeguards.md"))
        let identity = try #require(manager.document(fileName: "Identity.md"))
        let safeguardsRange = try #require(prompt.text.range(of: safeguards.rawText))
        let identityRange = try #require(prompt.text.range(of: identity.rawText))
        let assistantRange = try #require(prompt.text.range(of: "Review every diff for secrets."))
        #expect(identityRange.lowerBound >= safeguardsRange.upperBound)
        #expect(assistantRange.lowerBound >= identityRange.upperBound)
    }

    @Test("Assistant instructions survive a token budget that crowds out search results")
    func assistantSurvivesTinyBudget() throws {
        let manager = Self.manager()
        let index = try #require(manager.index)
        let prompt = SystemPromptBuilder().build(
            index: index,
            request: "Run the build and fix the failing tests",
            provider: "claude",
            model: nil,
            maxEstimatedTokens: 1,
            assistant: Self.assistantDescriptor()
        )
        #expect(!prompt.isBaselineFallback)
        #expect(prompt.assistantID == "assistant-review")
        #expect(prompt.text.contains("Review every diff for secrets."))
        #expect(!prompt.omittedDocumentIDs.isEmpty)
    }

    @Test("A missing extra asset is recorded as omitted instead of failing the prompt")
    func missingExtraAssetIsRecordedOmitted() {
        let manager = Self.manager()
        let prompt = manager.systemPrompt(
            for: nil, provider: nil, model: nil,
            assistant: Self.assistantDescriptor(extraAssetFileNames: ["NoSuchAsset.md"]))
        #expect(!prompt.isBaselineFallback)
        #expect(prompt.assistantID == "assistant-review")
        #expect(prompt.omittedDocumentIDs.contains("NoSuchAsset"))
        #expect(prompt.text.contains("Review every diff for secrets."))
    }

    @Test("An extra asset file loads into the prompt right after the Assistant section")
    func extraAssetLoads() throws {
        let manager = Self.manager()
        let availableTools = try #require(manager.document(fileName: "AvailableTools.md"))
        let prompt = manager.systemPrompt(
            for: nil, provider: nil, model: nil,
            assistant: Self.assistantDescriptor(extraAssetFileNames: ["AvailableTools.md"]))
        #expect(!prompt.isBaselineFallback)
        #expect(prompt.assistantID == "assistant-review")
        #expect(prompt.includedDocumentIDs.prefix(3) == ["Safeguards", "Identity", "AvailableTools"])
        #expect(prompt.text.contains(availableTools.rawText))
    }

    @Test("Without an Assistant the prompt is unchanged and carries no assistant id")
    func noAssistantPromptUnchanged() throws {
        let manager = Self.manager()
        let index = try #require(manager.index)
        let viaManager = manager.systemPrompt(for: "Fix the SwiftUI layout bug", provider: "claude", model: "sonnet")
        let viaBuilder = SystemPromptBuilder().build(
            index: index, request: "Fix the SwiftUI layout bug", provider: "claude", model: "sonnet")
        #expect(viaManager.assistantID == nil)
        #expect(viaBuilder.assistantID == nil)
        #expect(viaManager.text == viaBuilder.text)
        #expect(viaManager.includedDocumentIDs == viaBuilder.includedDocumentIDs)
        #expect(viaManager.omittedDocumentIDs == viaBuilder.omittedDocumentIDs)
        #expect(viaManager.estimatedTokens == viaBuilder.estimatedTokens)
        #expect(viaManager.includedDocumentIDs.first == "Safeguards")
    }

    private static let retrievalAlpha = "# Alpha Guide\n\n## Getting Started\nAlpha tokens live here for the alpha walkthrough.\n\n## Advanced Alpha\nDeep alpha material.\n"
    private static let retrievalBeta = "# Beta Guide\n\n## Getting Started\nBeta tokens live here for the beta walkthrough.\n\n## Advanced Beta\nDeep beta material.\n"
    private static let retrievalGamma = "# Gamma Notes\n\n## Overview\nShared token appears in this body text.\n"

    private static func makeRetrievalFixture() throws -> URL {
        let temp = Self.makeTemporaryDirectory()
        try Self.retrievalAlpha.write(to: temp.appendingPathComponent("Alpha.md"), atomically: true, encoding: .utf8)
        try Self.retrievalBeta.write(to: temp.appendingPathComponent("Beta.md"), atomically: true, encoding: .utf8)
        try Self.retrievalGamma.write(to: temp.appendingPathComponent("Gamma Notes.md"), atomically: true, encoding: .utf8)
        return temp
    }

    @Test("Canonical ranking pins the same results the Rust port must reproduce")
    func canonicalRankingParityFixture() throws {
        let fixture = try Self.makeRetrievalFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let manager = SystemAssetManager(directory: fixture)
        #expect(manager.isReady)
        #expect(manager.documentCount == 3)
        let alpha = manager.search("alpha", limit: 10)
        #expect(alpha.map(\.documentID) == ["Alpha", "Alpha", "Alpha"])
        #expect(alpha.map(\.fileName) == ["Alpha.md", "Alpha.md", "Alpha.md"])
        #expect(alpha.map(\.sectionHeading) == ["Advanced Alpha", "Getting Started", "Alpha Guide"])
        #expect(alpha.map(\.score) == [72, 72, 71])
        #expect(alpha.map(\.reason) == ["phrase", "phrase", "phrase"])
        #expect(alpha.map(\.text) == [
            "Advanced Alpha\n\nDeep alpha material.",
            "Getting Started\n\nAlpha tokens live here for the alpha walkthrough.",
            "Alpha Guide\n\n",
        ])
        let getting = manager.search("getting started", limit: 10)
        #expect(getting.map(\.fileName) == ["Alpha.md", "Beta.md"])
        #expect(getting.map(\.sectionHeading) == ["Getting Started", "Getting Started"])
        #expect(getting.map(\.score) == [80, 80])
        #expect(getting.map(\.reason) == ["exactHeading", "exactHeading"])
    }

    @Test("Two documents sharing a title token both rank")
    func sharedTitleTokenRanksBothDocuments() throws {
        let fixture = try Self.makeRetrievalFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let manager = SystemAssetManager(directory: fixture)
        let guide = manager.search("guide", limit: 10)
        #expect(guide.map(\.fileName) == ["Alpha.md", "Beta.md", "Alpha.md", "Alpha.md", "Beta.md", "Beta.md"])
        #expect(guide.map(\.sectionHeading) == ["Alpha Guide", "Beta Guide", "Advanced Alpha", "Getting Started", "Advanced Beta", "Getting Started"])
        #expect(guide.map(\.score) == [71, 71, 5, 5, 5, 5])
        #expect(guide.map(\.reason) == ["phrase", "phrase", "keyword", "keyword", "keyword", "keyword"])
        #expect(Set(guide.map(\.fileName)) == ["Alpha.md", "Beta.md"])
        #expect(guide.map(\.documentID) == ["Alpha", "Beta", "Alpha", "Alpha", "Beta", "Beta"])
    }

    @Test("Multi-word queries tokenize before postings lookup")
    func multiWordQueriesTokenizeBeforePostings() throws {
        let fixture = try Self.makeRetrievalFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let manager = SystemAssetManager(directory: fixture)
        let index = try #require(manager.index)
        #expect(SystemAssetIndex.tokenize("getting-started guide") == ["getting", "started", "guide"])
        #expect(SystemAssetIndex.tokenize("getting started") == ["getting", "started"])
        #expect(index.postings(for: "getting started").isEmpty)
        #expect(index.postings(for: "getting-started").isEmpty)
        let results = manager.search("getting started", limit: 10)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.reason == "exactHeading" })
        #expect(results.allSatisfy { $0.sectionHeading == "Getting Started" })
    }

    @Test("A document outside the top results stays fully retrievable")
    func fullDocumentRetrievalOutsideTopResults() throws {
        let fixture = try Self.makeRetrievalFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let manager = SystemAssetManager(directory: fixture)
        let top = manager.search("alpha", limit: 1)
        #expect(top.count == 1)
        #expect(top.first?.fileName == "Alpha.md")
        #expect(top.allSatisfy { $0.fileName != "Beta.md" })
        let beta = try #require(manager.document(fileName: "Beta.md"))
        #expect(beta.rawText == Self.retrievalBeta)
        #expect(beta.sections.count == 3)
        #expect(beta.rawText.contains("Deep beta material."))
        #expect(beta.sections.map(\.heading) == ["Beta Guide", "Getting Started", "Advanced Beta"])
        let gamma = try #require(manager.document(fileName: "Gamma Notes.md"))
        #expect(gamma.rawText == Self.retrievalGamma)
        #expect(gamma.id == "Gamma Notes")
    }
}
