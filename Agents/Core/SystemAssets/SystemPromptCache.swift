import Foundation

public struct SystemPromptCacheKey: Hashable, Sendable {
    public var threadID: UUID
    public var assistantID: String?
    public var assistantName: String
    public var assistantRoleText: String
    public var assistantExtraAssetFileNames: [String]
    public var provider: String?
    public var model: String?
    public var toolset: String?
    public var allowedTools: [String]
    public var indexVersion: Int

    public init(threadID: UUID, assistantID: String? = nil, assistantName: String = "", assistantRoleText: String = "", assistantExtraAssetFileNames: [String] = [], provider: String? = nil, model: String? = nil, toolset: String? = nil, allowedTools: [String] = [], indexVersion: Int = 0) {
        self.threadID = threadID
        self.assistantID = assistantID
        self.assistantName = assistantName
        self.assistantRoleText = assistantRoleText
        self.assistantExtraAssetFileNames = assistantExtraAssetFileNames
        self.provider = provider
        self.model = model
        self.toolset = toolset
        self.allowedTools = allowedTools
        self.indexVersion = indexVersion
    }
}

public final class SystemPromptCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [SystemPromptCacheKey: SystemPrompt] = [:]
    private var insertionOrder: [SystemPromptCacheKey] = []
    public let maxEntries: Int

    public init(maxEntries: Int = 128) {
        self.maxEntries = max(1, maxEntries)
    }

    public func prompt(for key: SystemPromptCacheKey) -> SystemPrompt? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    public func store(_ prompt: SystemPrompt, for key: SystemPromptCacheKey) {
        lock.lock()
        defer { lock.unlock() }
        if entries[key] == nil {
            insertionOrder.append(key)
        }
        entries[key] = prompt
        while entries.count > maxEntries, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    public func invalidate(threadID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        let keys = entries.keys.filter { $0.threadID == threadID }
        for key in keys {
            entries.removeValue(forKey: key)
        }
        insertionOrder.removeAll { $0.threadID == threadID }
    }

    public func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        insertionOrder.removeAll()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
}
