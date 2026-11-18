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

    @Test("Prompt starts with the concise baseline and never forces whole Safeguards or Identity")
    func promptStartsWithConciseBaseline() throws {
        let manager = Self.manager()
        let prompt = manager.systemPrompt(for: "Fix the SwiftUI layout bug", provider: "claude", model: "sonnet")
        let safeguards = try #require(manager.document(fileName: "Safeguards.md"))
        let identity = try #require(manager.document(fileName: "Identity.md"))
        #expect(!prompt.isBaselineFallback)
        #expect(prompt.loadError == nil)
        #expect(prompt.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
        #expect(!prompt.text.contains(safeguards.rawText))
        #expect(!prompt.text.contains(identity.rawText))
        #expect(prompt.estimatedTokens > 0)
        #expect(prompt.estimatedTokens <= SystemPromptBudget.defaultBudgetTokens)
    }

    @Test("Building a system prompt registers its text with the shared redaction gate")
    func systemPromptRegistersWithSharedGate() {
        let manager = Self.manager()
        let prompt = manager.systemPrompt(for: "Fix the SwiftUI layout bug", provider: "claude", model: "sonnet")
        #expect(prompt.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
        let echoed = "The model answered: Get straight to the point: no greetings, no self-introduction, no mode announcements unless asked. Done."
        let redacted = OutputRedactionGate.shared.redactedText(echoed)
        #expect(redacted.contains(OutputRedactionGate.redactionMarker))
        #expect(!redacted.contains("no self-introduction"))
        #expect(!redacted.contains("no mode announcements"))
        #expect(redacted.contains("Done."))
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

    @Test("Assistant section follows the baseline and carries its id")
    func assistantSectionAfterBaseline() throws {
        let manager = Self.manager()
        let prompt = manager.systemPrompt(
            for: "Fix the SwiftUI layout bug", provider: "claude", model: "sonnet",
            assistant: Self.assistantDescriptor())
        let safeguards = try #require(manager.document(fileName: "Safeguards.md"))
        let identity = try #require(manager.document(fileName: "Identity.md"))
        #expect(!prompt.isBaselineFallback)
        #expect(prompt.assistantID == "assistant-review")
        #expect(prompt.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
        #expect(prompt.text.contains("Assistant \"Reviewer\" instructions:"))
        #expect(prompt.text.contains("Review every diff for secrets."))
        #expect(!prompt.text.contains(safeguards.rawText))
        #expect(!prompt.text.contains(identity.rawText))
        #expect(prompt.estimatedTokens <= SystemPromptBudget.defaultBudgetTokens)
        let baselineRange = try #require(prompt.text.range(of: SystemPromptBuilder.conciseBaseline))
        let assistantRange = try #require(prompt.text.range(of: "Review every diff for secrets."))
        #expect(assistantRange.lowerBound >= baselineRange.upperBound)
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
        #expect(prompt.text == SystemPromptBuilder.conciseBaseline + "\n\nAssistant \"Reviewer\" instructions:\nReview every diff for secrets.")
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

    @Test("An extra asset file loads into the prompt after the Assistant section when the budget allows")
    func extraAssetLoads() throws {
        let manager = Self.manager()
        let index = try #require(manager.index)
        let availableTools = try #require(manager.document(fileName: "AvailableTools.md"))
        let prompt = SystemPromptBuilder().build(
            index: index,
            request: nil, provider: nil, model: nil,
            maxEstimatedTokens: 20000,
            assistant: Self.assistantDescriptor(extraAssetFileNames: ["AvailableTools.md"]))
        #expect(!prompt.isBaselineFallback)
        #expect(prompt.assistantID == "assistant-review")
        #expect(prompt.includedDocumentIDs.first == "AvailableTools")
        #expect(prompt.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
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
        #expect(viaManager.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
    }

    @Test("Concise baseline stays below the target cap and is the fallback text")
    func baselineSizeBelowTargetCap() {
        let baselineTokens = max(1, SystemPromptBuilder.conciseBaseline.count / 4)
        #expect(baselineTokens < 1000)
        #expect(baselineTokens < SystemPromptBudget.defaultBudgetTokens / 2)
        #expect(SystemPromptBuilder.minimalBaselinePrompt(error: nil).text == SystemPromptBuilder.conciseBaseline)
        #expect(SystemPromptBuilder.minimalBaselinePrompt(error: nil).isBaselineFallback)
    }

    @Test("Assistant prompt respects the same budget and drops an extra asset that does not fit")
    func assistantPromptRespectsBudget() throws {
        let manager = Self.manager()
        let availableTools = try #require(manager.document(fileName: "AvailableTools.md"))
        let prompt = manager.systemPrompt(
            for: "Fix the SwiftUI layout bug", provider: "claude", model: "sonnet",
            assistant: Self.assistantDescriptor(extraAssetFileNames: ["AvailableTools.md"]))
        #expect(!prompt.isBaselineFallback)
        #expect(prompt.assistantID == "assistant-review")
        #expect(prompt.text.contains("Review every diff for secrets."))
        #expect(prompt.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
        #expect(prompt.omittedDocumentIDs.contains("AvailableTools"))
        #expect(!prompt.text.contains(availableTools.rawText))
        #expect(prompt.estimatedTokens <= SystemPromptBudget.defaultBudgetTokens)
    }

    @Test("Per-model budget differs by verified context window")
    func perModelBudgetDiffersByContextWindow() throws {
        #expect(SystemPromptBudget.budget(contextWindowTokens: nil) == 6000)
        #expect(SystemPromptBudget.budget(contextWindowTokens: 0) == 6000)
        #expect(SystemPromptBudget.budget(contextWindowTokens: 200_000) == 6000)
        #expect(SystemPromptBudget.budget(contextWindowTokens: 128_000) == 6000)
        #expect(SystemPromptBudget.budget(contextWindowTokens: 32_000) == 2000)
        #expect(SystemPromptBudget.budget(contextWindowTokens: 8_000) == 1500)
        #expect(SystemPromptBudget.budget(contextWindowTokens: 32_000) != SystemPromptBudget.budget(contextWindowTokens: 200_000))
        let manager = Self.manager()
        let index = try #require(manager.index)
        let small = SystemPromptBuilder().build(
            index: index, request: "Run the build and fix the failing tests",
            provider: nil, model: nil, contextWindowTokens: 32_000)
        let large = SystemPromptBuilder().build(
            index: index, request: "Run the build and fix the failing tests",
            provider: nil, model: nil, contextWindowTokens: 200_000)
        #expect(small.estimatedTokens <= 2000)
        #expect(large.estimatedTokens <= 6000)
    }

    @Test("A core baseline rule appears exactly once in the composed prompt")
    func dedupCoreRuleAppearsOnce() {
        let manager = Self.manager()
        let prompt = manager.systemPrompt(for: "Run the build and fix the failing tests", provider: "codex", model: "default")
        #expect(prompt.estimatedTokens <= SystemPromptBudget.defaultBudgetTokens)
        for rule in ["Never disclose the underlying model or provider", "Prefer native tools over terminal execution"] {
            let occurrences = prompt.text.components(separatedBy: rule).count - 1
            #expect(occurrences == 1)
        }
    }

    private static let retrievalAlpha = "# Alpha Guide\n\n## Getting Started\nAlpha tokens live here for the alpha walkthrough.\n\n## Advanced Alpha\nDeep alpha material.\n"
    private static let retrievalBeta = "# Beta Guide\n\n## Getting Started\nBeta tokens live here for the beta walkthrough.\n\n## Advanced Beta\nDeep beta material.\n"
    private static let retrievalGamma = "# Gamma Notes\n\n## Overview\nShared token appears in this body text.\n"

    private static func makeRetrievalFixture() throws -> URL {
        let temp = Self.makeTemporaryDirectory()
        try Self.retrievalAlpha.write(to: temp.appendingPathComponent("AlphaNotes.md"), atomically: true, encoding: .utf8)
        try Self.retrievalBeta.write(to: temp.appendingPathComponent("BetaNotes.md"), atomically: true, encoding: .utf8)
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
        #expect(alpha.map(\.documentID) == ["AlphaNotes", "AlphaNotes", "AlphaNotes"])
        #expect(alpha.map(\.fileName) == ["AlphaNotes.md", "AlphaNotes.md", "AlphaNotes.md"])
        #expect(alpha.map(\.sectionHeading) == ["Advanced Alpha", "Getting Started", "Alpha Guide"])
        #expect(alpha.map(\.headingPath) == [["Alpha Guide", "Advanced Alpha"], ["Alpha Guide", "Getting Started"], ["Alpha Guide"]])
        #expect(alpha.map(\.score) == [72, 72, 71])
        #expect(alpha.map(\.reason) == ["phrase", "phrase", "phrase"])
        #expect(alpha.map(\.text) == [
            "Advanced Alpha\n\nDeep alpha material.",
            "Getting Started\n\nAlpha tokens live here for the alpha walkthrough.",
            "Alpha Guide\n\n",
        ])
        let getting = manager.search("getting started", limit: 10)
        #expect(getting.map(\.fileName) == ["AlphaNotes.md", "BetaNotes.md"])
        #expect(getting.map(\.sectionHeading) == ["Getting Started", "Getting Started"])
        #expect(getting.map(\.headingPath) == [["Alpha Guide", "Getting Started"], ["Beta Guide", "Getting Started"]])
        #expect(getting.map(\.score) == [80, 80])
        #expect(getting.map(\.reason) == ["exactHeading", "exactHeading"])
    }

    @Test("An exact document ID match returns the first section at score 100")
    func exactDocumentIDMatchReturnsFirstSection() throws {
        let fixture = try Self.makeRetrievalFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let manager = SystemAssetManager(directory: fixture)
        let exact = manager.search("alphanotes", limit: 10)
        #expect(exact.count == 1)
        #expect(exact.map(\.documentID) == ["AlphaNotes"])
        #expect(exact.map(\.fileName) == ["AlphaNotes.md"])
        #expect(exact.map(\.sectionHeading) == ["Alpha Guide"])
        #expect(exact.map(\.headingPath) == [["Alpha Guide"]])
        #expect(exact.map(\.score) == [100])
        #expect(exact.map(\.reason) == ["exactFilename"])
        #expect(exact.map(\.text) == ["Alpha Guide\n\n"])
    }

    @Test("Two documents sharing a title token both rank")
    func sharedTitleTokenRanksBothDocuments() throws {
        let fixture = try Self.makeRetrievalFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let manager = SystemAssetManager(directory: fixture)
        let guide = manager.search("guide", limit: 10)
        #expect(guide.map(\.fileName) == ["AlphaNotes.md", "BetaNotes.md", "AlphaNotes.md", "AlphaNotes.md", "BetaNotes.md", "BetaNotes.md"])
        #expect(guide.map(\.sectionHeading) == ["Alpha Guide", "Beta Guide", "Advanced Alpha", "Getting Started", "Advanced Beta", "Getting Started"])
        #expect(guide.map(\.headingPath) == [["Alpha Guide"], ["Beta Guide"], ["Alpha Guide", "Advanced Alpha"], ["Alpha Guide", "Getting Started"], ["Beta Guide", "Advanced Beta"], ["Beta Guide", "Getting Started"]])
        #expect(guide.map(\.score) == [71, 71, 5, 5, 5, 5])
        #expect(guide.map(\.reason) == ["phrase", "phrase", "keyword", "keyword", "keyword", "keyword"])
        #expect(Set(guide.map(\.fileName)) == ["AlphaNotes.md", "BetaNotes.md"])
        #expect(guide.map(\.documentID) == ["AlphaNotes", "BetaNotes", "AlphaNotes", "AlphaNotes", "BetaNotes", "BetaNotes"])
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
        #expect(top.first?.fileName == "AlphaNotes.md")
        #expect(top.allSatisfy { $0.fileName != "BetaNotes.md" })
        let beta = try #require(manager.document(fileName: "BetaNotes.md"))
        #expect(beta.rawText == Self.retrievalBeta)
        #expect(beta.sections.count == 3)
        #expect(beta.rawText.contains("Deep beta material."))
        #expect(beta.sections.map(\.heading) == ["Beta Guide", "Getting Started", "Advanced Beta"])
        let gamma = try #require(manager.document(fileName: "Gamma Notes.md"))
        #expect(gamma.rawText == Self.retrievalGamma)
        #expect(gamma.id == "Gamma Notes")
    }

    @Test("Retrieval stops before exceeding the remaining budget, most relevant first")
    func retrievalStopsBeforeExceedingRemainingBudget() throws {
        let fixture = try Self.makeRetrievalFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let manager = SystemAssetManager(directory: fixture)
        let index = try #require(manager.index)
        let prompt = SystemPromptBuilder().build(
            index: index, request: "getting started",
            provider: nil, model: nil, maxEstimatedTokens: 520)
        #expect(!prompt.isBaselineFallback)
        #expect(prompt.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
        #expect(prompt.estimatedTokens == 514)
        #expect(prompt.estimatedTokens <= 520)
        #expect(prompt.text.contains("Alpha tokens live here for the alpha walkthrough."))
        #expect(!prompt.text.contains("Beta tokens live here for the beta walkthrough."))
        #expect(prompt.includedDocumentIDs == ["AlphaNotes"])
        #expect(prompt.omittedDocumentIDs == ["BetaNotes"])
    }

    @Test("An existing but empty directory reports no documents found")
    func emptyDirectoryReportsNoDocumentsFound() throws {
        let temp = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let manager = SystemAssetManager(directory: temp)
        #expect(!manager.isReady)
        guard case .noDocumentsFound = manager.loadError else {
            Issue.record("Expected noDocumentsFound, got \(String(describing: manager.loadError))")
            return
        }
        let prompt = manager.systemPrompt(for: "Hello", provider: nil, model: nil)
        #expect(prompt.isBaselineFallback)
        #expect(!prompt.text.isEmpty)
        #expect(prompt.loadError != nil)
    }

    @Test("Non-markdown and hidden files are ignored by discovery")
    func nonMarkdownAndHiddenFilesIgnored() throws {
        let temp = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "# Visible\n\nVisible body with token visiblebody.\n".write(to: temp.appendingPathComponent("Visible.md"), atomically: true, encoding: .utf8)
        try "# Hidden\n\nHidden body with token hiddenbody.\n".write(to: temp.appendingPathComponent(".Hidden.md"), atomically: true, encoding: .utf8)
        try "Plain text, not markdown.\n".write(to: temp.appendingPathComponent("Notes.txt"), atomically: true, encoding: .utf8)
        try "{\"key\": \"value\"}\n".write(to: temp.appendingPathComponent("Data.json"), atomically: true, encoding: .utf8)
        let manager = SystemAssetManager(directory: temp)
        #expect(manager.isReady)
        #expect(manager.documentCount == 1)
        #expect(manager.document(fileName: "Visible.md") != nil)
        #expect(manager.document(fileName: ".Hidden.md") == nil)
        #expect(manager.document(fileName: "Notes.txt") == nil)
        #expect(manager.search("hiddenbody").isEmpty)
    }

    @Test("An exact title match scores 90 and outranks keyword matches")
    func exactTitleMatchScoresNinety() throws {
        let fixture = try Self.makeRetrievalFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let manager = SystemAssetManager(directory: fixture)
        let results = manager.search("alpha guide", limit: 10)
        let first = try #require(results.first)
        #expect(first.fileName == "AlphaNotes.md")
        #expect(first.sectionHeading == "Alpha Guide")
        #expect(first.score == 90)
        #expect(first.reason == "exactTitle")
        #expect(results.dropFirst().allSatisfy { $0.score < 90 })
    }

    @Test("Dependency resolution ignores unknown files and terminates on cycles")
    func dependencyResolutionIgnoresUnknownAndCycles() throws {
        let temp = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "<!-- system-index-depends: B.md -->\n# A\n\nA body.\n".write(to: temp.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        try "<!-- system-index-depends: A.md -->\n# B\n\nB body.\n".write(to: temp.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
        try "<!-- system-index-depends: C.md -->\n# C\n\nC body.\n".write(to: temp.appendingPathComponent("C.md"), atomically: true, encoding: .utf8)
        try "# D\n\nD body.\n".write(to: temp.appendingPathComponent("D.md"), atomically: true, encoding: .utf8)
        let manager = SystemAssetManager(directory: temp)
        let index = try #require(manager.index)
        #expect(index.resolveDependencies(of: ["A.md"]) == ["B.md"])
        #expect(index.resolveDependencies(of: ["B.md"]) == ["A.md"])
        #expect(index.resolveDependencies(of: ["C.md"]).isEmpty)
        #expect(index.resolveDependencies(of: ["Missing.md"]).isEmpty)
        #expect(index.resolveDependencies(of: ["A.md", "B.md"]).isEmpty)
        #expect(index.resolveDependencies(of: []).isEmpty)
    }

    @Test("Unknown lookups return empty instead of failing")
    func unknownLookupsReturnEmpty() throws {
        let fixture = try Self.makeRetrievalFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let manager = SystemAssetManager(directory: fixture)
        let index = try #require(manager.index)
        #expect(index.document(id: "Nope") == nil)
        #expect(index.document(relativePath: "Nope.md") == nil)
        #expect(index.chunk(id: "nope") == nil)
        #expect(index.chunks(forDocumentID: "Nope").isEmpty)
        #expect(index.keywords(forDocumentID: "Nope").isEmpty)
        #expect(index.section(documentID: "AlphaNotes", heading: "No Such Heading") == nil)
        #expect(index.postings(for: "").isEmpty)
        #expect(index.documents(category: "").isEmpty)
        #expect(index.documents(tag: "").isEmpty)
        #expect(index.relatedDocumentIDs(ofFileName: "Nope.md").isEmpty)
    }

    @Test("Duplicate file names resolve to the first path in sorted order")
    func duplicateFileNamesResolveToFirstSortedPath() throws {
        let temp = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        for directory in ["Guides", "Other"] {
            try FileManager.default.createDirectory(at: temp.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        try "# Guides Notes\n\nGuides notes body.\n".write(to: temp.appendingPathComponent("Guides/Notes.md"), atomically: true, encoding: .utf8)
        try "# Other Notes\n\nOther notes body.\n".write(to: temp.appendingPathComponent("Other/Notes.md"), atomically: true, encoding: .utf8)
        let manager = SystemAssetManager(directory: temp)
        let index = try #require(manager.index)
        #expect(manager.documentCount == 2)
        #expect(manager.document(fileName: "Notes.md")?.relativePath == "Guides/Notes.md")
        #expect(index.document(id: "Guides/Notes")?.title == "Guides Notes")
        #expect(index.document(id: "Other/Notes")?.title == "Other Notes")
        #expect(index.document(relativePath: "Other/Notes.md")?.title == "Other Notes")
    }

    @Test("Search is diacritic-insensitive")
    func diacriticInsensitiveSearch() throws {
        let temp = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "# Cafe Guide\n\nThe cafe serves coffee.\n".write(to: temp.appendingPathComponent("Cafe.md"), atomically: true, encoding: .utf8)
        let manager = SystemAssetManager(directory: temp)
        #expect(manager.search("café").first?.fileName == "Cafe.md")
        #expect(manager.search("CAFÉ").first?.fileName == "Cafe.md")
        #expect(SystemAssetIndex.normalized("café") == "cafe")
    }

    @Test("Document parsing handles non-UTF8, empty headings, and pre-heading bodies")
    func documentParseEdgeCases() throws {
        #expect(throws: SystemAssetError.documentMalformed(fileName: "Bad.md", reason: "Document is not valid UTF-8.")) {
            try SystemAssetDocument.parse(fileName: "Bad.md", relativePath: "Bad.md", data: Data([0xFF, 0xFE, 0x41]))
        }
        let subOnly = try SystemAssetDocument.parse(fileName: "Sub.md", relativePath: "Sub.md", data: Data("## Only Sub\n\nBody.\n".utf8))
        #expect(subOnly.title == "Sub")
        #expect(subOnly.sections.count == 1)
        #expect(subOnly.sections[0].heading == "Only Sub")
        #expect(subOnly.sections[0].level == 2)
        let emptyFirstHeading = try SystemAssetDocument.parse(fileName: "Real.md", relativePath: "Real.md", data: Data("#   \n\n# Real Title\n\nBody.\n".utf8))
        #expect(emptyFirstHeading.title == "Real Title")
        #expect(emptyFirstHeading.sections.count == 2)
        #expect(emptyFirstHeading.sections[0].heading == "")
        #expect(emptyFirstHeading.sections[0].body == "#")
        #expect(emptyFirstHeading.sections[1].heading == "Real Title")
        let leadingBody = try SystemAssetDocument.parse(fileName: "Lead.md", relativePath: "Lead.md", data: Data("Intro text.\n\n# Title\n\nBody.\n".utf8))
        #expect(leadingBody.sections.count == 2)
        #expect(leadingBody.sections[0].heading == "")
        #expect(leadingBody.sections[0].body == "Intro text.")
        #expect(leadingBody.sections[1].heading == "Title")
        let deepHashes = try SystemAssetDocument.parse(fileName: "Deep.md", relativePath: "Deep.md", data: Data("####### Deep\n\nBody.\n".utf8))
        #expect(deepHashes.title == "Deep")
        #expect(deepHashes.sections.count == 1)
        #expect(deepHashes.sections[0].heading == "Deep")
        let noSpace = try SystemAssetDocument.parse(fileName: "NoSpace.md", relativePath: "NoSpace.md", data: Data("#NoSpace\n\nBody.\n".utf8))
        #expect(noSpace.title == "NoSpace")
        #expect(noSpace.sections.count == 1)
        #expect(noSpace.sections[0].heading == "NoSpace")
    }

    @Test("Marker parsing trims values, dedupes tags, and drops non-markdown dependencies")
    func documentMarkerParsingEdgeCases() throws {
        let nested = try SystemAssetDocument.parse(
            fileName: "Plain.md", relativePath: "Guides/Plain.md",
            data: Data("<!-- system-index-category: -->\n# Plain\n\nBody.\n".utf8))
        #expect(nested.category == "Guides")
        let spaced = try SystemAssetDocument.parse(
            fileName: "Spaced.md", relativePath: "Spaced.md",
            data: Data("<!-- system-index-category:   Workflow   -->\n# Spaced\n\nBody.\n".utf8))
        #expect(spaced.category == "Workflow")
        let tagged = try SystemAssetDocument.parse(
            fileName: "Tagged.md", relativePath: "Tagged.md",
            data: Data("<!-- system-index-tags: alpha, beta -->\n<!-- system-index-tags: beta, gamma -->\n# Tagged\n\nBody.\n".utf8))
        #expect(tagged.tags == ["alpha", "beta", "gamma"])
        let depends = try SystemAssetDocument.parse(
            fileName: "Depends.md", relativePath: "Depends.md",
            data: Data("<!-- system-index-depends: Beta.md, notes.txt, Beta.md, Gamma.md -->\n# Depends\n\nBody.\n".utf8))
        #expect(depends.dependencies == ["Beta.md", "Gamma.md"])
    }

    @Test("Retrieve joins the provider and model into the search query")
    func retrieveJoinsProviderAndModelIntoQuery() throws {
        let fixture = try Self.makeRetrievalFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let manager = SystemAssetManager(directory: fixture)
        #expect(manager.retrieve(request: nil, provider: "beta", model: nil).contains { $0.fileName == "BetaNotes.md" })
        #expect(manager.retrieve(request: nil, provider: nil, model: "gamma").contains { $0.fileName == "Gamma Notes.md" })
        #expect(manager.retrieve(request: "alpha", provider: "beta", model: nil).contains { $0.fileName == "AlphaNotes.md" })
        #expect(manager.retrieve(request: "alpha", provider: "beta", model: nil).contains { $0.fileName == "BetaNotes.md" })
        #expect(manager.retrieve(request: nil, provider: "   ", model: nil).isEmpty)
        #expect(manager.retrieve(request: nil, provider: nil, model: "   ").isEmpty)
    }

    @Test("Prompt assembly appends the first section of each included dependency")
    func promptIncludesDependencyFirstSections() throws {
        let temp = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "<!-- system-index-depends: BetaNotes.md -->\n# Alpha Guide\n\n## Getting Started\nAlpha tokens live here.\n".write(to: temp.appendingPathComponent("AlphaNotes.md"), atomically: true, encoding: .utf8)
        try "# Beta Guide\n\n## Getting Started\nBeta tokens live here.\n".write(to: temp.appendingPathComponent("BetaNotes.md"), atomically: true, encoding: .utf8)
        let manager = SystemAssetManager(directory: temp)
        let index = try #require(manager.index)
        let prompt = SystemPromptBuilder().build(index: index, request: "alpha", provider: nil, model: nil)
        #expect(prompt.includedDocumentIDs.contains("AlphaNotes"))
        #expect(prompt.includedDocumentIDs.contains("BetaNotes"))
        #expect(prompt.text.contains("Beta Guide"))
        #expect(prompt.text.contains("Alpha tokens live here."))
    }

    @Test("Prompt assembly includes an identical section only once")
    func promptDeduplicatesIdenticalSections() throws {
        let temp = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        for name in ["A.md", "B.md"] {
            try "# Shared\n\nSame body.\n".write(to: temp.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let manager = SystemAssetManager(directory: temp)
        let index = try #require(manager.index)
        let prompt = SystemPromptBuilder().build(index: index, request: "shared", provider: nil, model: nil)
        #expect(prompt.includedDocumentIDs == ["A"])
        #expect(prompt.text.components(separatedBy: "Same body.").count - 1 == 1)
    }

    @Test("An assistant with an empty prompt contributes nothing and gets no id")
    func assistantWithEmptyPromptContributesNothing() throws {
        let manager = Self.manager()
        let index = try #require(manager.index)
        let empty = AssistantPromptDescriptor(id: "ghost", name: "Ghost", systemPrompt: "   ", extraAssetFileNames: [])
        let ghostPrompt = SystemPromptBuilder().build(index: index, request: "Fix the bug", provider: nil, model: nil, assistant: empty)
        #expect(ghostPrompt.assistantID == nil)
        #expect(ghostPrompt.text.hasPrefix(SystemPromptBuilder.conciseBaseline))
        #expect(!ghostPrompt.text.contains("instructions:"))
        let nameless = AssistantPromptDescriptor(id: "nameless", name: "", systemPrompt: "Do it.", extraAssetFileNames: [])
        let namelessPrompt = SystemPromptBuilder().build(index: index, request: nil, provider: nil, model: nil, assistant: nameless)
        #expect(namelessPrompt.assistantID == "nameless")
        #expect(namelessPrompt.text.contains("Do it."))
        #expect(!namelessPrompt.text.contains("instructions:"))
    }

    @Test("Minimal baseline prompt passes its error through")
    func minimalBaselinePromptPassesThroughError() {
        let malformed = SystemAssetError.documentMalformed(fileName: "X.md", reason: "R")
        let prompt = SystemPromptBuilder.minimalBaselinePrompt(error: malformed)
        #expect(prompt.isBaselineFallback)
        #expect(prompt.text == SystemPromptBuilder.conciseBaseline)
        #expect(prompt.loadError == malformed)
        #expect(SystemPromptBuilder.minimalBaselinePrompt(error: nil).loadError == .retrievalUnavailable(reason: "System assets unavailable; using minimal safe baseline."))
    }
}
