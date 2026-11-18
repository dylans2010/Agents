import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Subagent Prompts: Composed Worker Prompts & Per-Thread Prompt Cache")
struct SubagentPromptTests {

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

    private static func manager() -> SystemAssetManager {
        SystemAssetManager(directory: assetsDirectory())
    }

    private static func reviewerAssistant(allowedTools: [String]? = ["read_file"], profile: RemoteAssistant.PermissionProfile = .readOnly) -> RemoteAssistant {
        RemoteAssistant(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            name: "Reviewer",
            category: .codeReviewSecurity,
            systemPrompt: "Review the diff for security issues.",
            allowedTools: allowedTools,
            provider: "claude",
            model: "sonnet",
            permissionProfile: profile
        )
    }

    private static func storedPrompt(text: String) -> SystemPrompt {
        SystemPrompt(
            text: text,
            includedDocumentIDs: [],
            omittedDocumentIDs: [],
            estimatedTokens: max(1, text.count / 4),
            isBaselineFallback: false,
            loadError: nil
        )
    }

    private static func cacheKey(threadID: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!) -> SystemPromptCacheKey {
        SystemPromptCacheKey(
            threadID: threadID,
            assistantID: "00000000-0000-4000-8000-000000000001",
            assistantName: "Reviewer",
            assistantRoleText: "Review the diff for security issues.",
            assistantExtraAssetFileNames: [],
            provider: "claude",
            model: "sonnet",
            toolset: "system",
            allowedTools: ["read_file"],
            indexVersion: 3
        )
    }

    @Test("Assistant-spawned worker gets the composed budgeted prompt, not the raw role text")
    func assistantWorkerGetsComposedPrompt() throws {
        let manager = Self.manager()
        #expect(manager.isReady)
        let assistant = Self.reviewerAssistant()
        let task = "Review the pull request diff for security issues"
        let composed = WorkerPromptComposer.composedPrompt(
            task: task,
            assistant: assistant,
            parentProvider: "codex",
            parentModel: "default",
            parentToolset: "system",
            manager: manager
        )
        let prompt = try #require(composed)
        let direct = manager.systemPrompt(
            for: task,
            provider: assistant.provider,
            model: assistant.model,
            assistant: AssistantPromptDescriptor(assistant)
        )
        #expect(prompt == direct.text)
        #expect(prompt.hasPrefix(SystemPromptBuilder.conciseBaseline))
        #expect(prompt.contains("Review the diff for security issues."))
        #expect(!direct.isBaselineFallback)
        #expect(direct.estimatedTokens <= SystemPromptBudget.defaultBudgetTokens)
        #expect(direct.assistantID == assistant.id.uuidString)
        let safeguards = try #require(manager.document(fileName: "Safeguards.md"))
        let identity = try #require(manager.document(fileName: "Identity.md"))
        #expect(!prompt.contains(safeguards.rawText))
        #expect(!prompt.contains(identity.rawText))
    }

    @Test("Worker prompt composition refuses a provider-toolset parent unless the assistant forces the system toolset")
    func providerToolsetParentCompositionRule() {
        let manager = Self.manager()
        let withTools = Self.reviewerAssistant(allowedTools: ["read_file"], profile: .workspaceModify)
        #expect(WorkerPromptComposer.composedPrompt(task: "Do the thing.", assistant: withTools, parentProvider: "codex", parentModel: "default", parentToolset: "provider", manager: manager) != nil)
        let readOnlyWithoutTools = Self.reviewerAssistant(allowedTools: nil, profile: .readOnly)
        #expect(WorkerPromptComposer.composedPrompt(task: "Do the thing.", assistant: readOnlyWithoutTools, parentProvider: "codex", parentModel: "default", parentToolset: "provider", manager: manager) != nil)
        let modifyWithoutTools = Self.reviewerAssistant(allowedTools: nil, profile: .workspaceModify)
        #expect(WorkerPromptComposer.composedPrompt(task: "Do the thing.", assistant: modifyWithoutTools, parentProvider: "codex", parentModel: "default", parentToolset: "provider", manager: manager) == nil)
        #expect(WorkerPromptComposer.composedPrompt(task: "Do the thing.", assistant: nil, parentProvider: "codex", parentModel: "default", parentToolset: "provider", manager: manager) == nil)
        #expect(WorkerPromptComposer.composedPrompt(task: "Do the thing.", assistant: nil, parentProvider: "codex", parentModel: "default", parentToolset: "system", manager: manager) != nil)
        #expect(WorkerPromptComposer.composedPrompt(task: "   ", assistant: Self.reviewerAssistant(), parentProvider: "codex", parentModel: "default", parentToolset: "system", manager: manager) == nil)
    }

    @Test("Prompt cache returns the cached prompt on a repeat turn with nothing changed")
    func cacheHitOnRepeatTurn() {
        let cache = SystemPromptCache()
        let key = Self.cacheKey()
        let prompt = Self.storedPrompt(text: "Composed prompt.")
        cache.store(prompt, for: key)
        #expect(cache.prompt(for: key)?.text == "Composed prompt.")
        #expect(cache.count == 1)
    }

    @Test("Prompt cache misses when the assistant, toolset, model, or index changes")
    func cacheMissesOnChangedInputs() {
        let cache = SystemPromptCache()
        let key = Self.cacheKey()
        cache.store(Self.storedPrompt(text: "Composed prompt."), for: key)
        var changed = key
        changed.assistantRoleText = "A different role text."
        #expect(cache.prompt(for: changed) == nil)
        changed = key
        changed.assistantID = "00000000-0000-4000-8000-000000000099"
        #expect(cache.prompt(for: changed) == nil)
        changed = key
        changed.assistantName = "Renamed Reviewer"
        #expect(cache.prompt(for: changed) == nil)
        changed = key
        changed.toolset = "provider"
        #expect(cache.prompt(for: changed) == nil)
        changed = key
        changed.allowedTools = ["read_file", "write_file"]
        #expect(cache.prompt(for: changed) == nil)
        changed = key
        changed.model = "opus"
        #expect(cache.prompt(for: changed) == nil)
        changed = key
        changed.provider = "codex"
        #expect(cache.prompt(for: changed) == nil)
        changed = key
        changed.indexVersion = 4
        #expect(cache.prompt(for: changed) == nil)
        changed = key
        changed.assistantExtraAssetFileNames = ["Extra.md"]
        #expect(cache.prompt(for: changed) == nil)
        #expect(cache.prompt(for: key)?.text == "Composed prompt.")
    }

    @Test("Prompt cache invalidation drops only the affected thread, or everything")
    func cacheInvalidationScopes() {
        let cache = SystemPromptCache()
        let firstThread = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let secondThread = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        cache.store(Self.storedPrompt(text: "First."), for: Self.cacheKey(threadID: firstThread))
        cache.store(Self.storedPrompt(text: "Second."), for: Self.cacheKey(threadID: secondThread))
        cache.invalidate(threadID: firstThread)
        #expect(cache.prompt(for: Self.cacheKey(threadID: firstThread)) == nil)
        #expect(cache.prompt(for: Self.cacheKey(threadID: secondThread))?.text == "Second.")
        cache.invalidateAll()
        #expect(cache.prompt(for: Self.cacheKey(threadID: secondThread)) == nil)
        #expect(cache.count == 0)
    }

    @Test("Prompt cache evicts the oldest entry past its cap")
    func cacheEvictsOldestPastCap() {
        let cache = SystemPromptCache(maxEntries: 2)
        let first = Self.cacheKey(threadID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!)
        let second = Self.cacheKey(threadID: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!)
        let third = Self.cacheKey(threadID: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!)
        cache.store(Self.storedPrompt(text: "First."), for: first)
        cache.store(Self.storedPrompt(text: "Second."), for: second)
        cache.store(Self.storedPrompt(text: "Third."), for: third)
        #expect(cache.count == 2)
        #expect(cache.prompt(for: first) == nil)
        #expect(cache.prompt(for: second)?.text == "Second.")
        #expect(cache.prompt(for: third)?.text == "Third.")
    }

    @Test("Worker spawn request carries a composed system prompt and decodes legacy requests without it")
    func workerSpawnRequestSystemPromptRoundTrips() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let request = WorkerSpawnRequest(
            name: "alpha",
            task: "Do it.",
            targetFiles: [],
            assistantId: UUID().uuidString,
            systemPrompt: "Composed baseline plus role text."
        )
        let data = try encoder.encode(request)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["systemPrompt"] as? String == "Composed baseline plus role text.")
        #expect(try decoder.decode(WorkerSpawnRequest.self, from: data) == request)
        let legacy = "{\"name\":\"alpha\",\"task\":\"Do it.\",\"targetFiles\":[]}"
        #expect(try decoder.decode(WorkerSpawnRequest.self, from: Data(legacy.utf8)).systemPrompt == nil)
    }
}
