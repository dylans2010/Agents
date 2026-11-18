import Foundation

public nonisolated final class SystemAssetManager: Sendable {
    public static let assetsDirectoryName = "SystemAssets"

    public static let shared = SystemAssetManager()

    private let store: SystemAssetIndexStore?
    private let resolutionError: SystemAssetError?

    public init() {
        do {
            let directory = try SystemAssetIndex.bundledAssetsURL()
            let created = SystemAssetIndexStore(sourceDirectory: directory)
            self.store = created
            self.resolutionError = nil
            try? created.loadOrRebuild()
        } catch let error as SystemAssetError {
            self.store = nil
            self.resolutionError = error
        } catch {
            self.store = nil
            self.resolutionError = .retrievalUnavailable(reason: error.localizedDescription)
        }
    }

    public init(directory: URL) {
        self.init(directory: directory, storeDirectory: nil)
    }

    public init(directory: URL, storeDirectory: URL?) {
        let created = SystemAssetIndexStore(sourceDirectory: directory, storeDirectory: storeDirectory)
        self.store = created
        self.resolutionError = nil
        try? created.loadOrRebuild()
    }

    public var index: SystemAssetIndex? {
        store?.snapshot()
    }

    public var loadError: SystemAssetError? {
        resolutionError ?? store?.loadError()
    }

    public var indexHealth: SystemAssetIndexHealth {
        store?.health() ?? SystemAssetIndexHealth(
            isReady: false,
            totalDocuments: 0,
            schemaVersion: SystemAssetIndexStore.currentSchemaVersion,
            indexVersion: 0,
            lastRefreshAt: nil,
            lastRefreshChangedCount: 0,
            lastRefreshError: resolutionError?.localizedDescription,
            persistenceAvailable: false
        )
    }

    public func refresh(progress: ((SystemAssetIndexProgress) -> Void)? = nil) -> SystemAssetIndexRefreshResult {
        guard let store else {
            return SystemAssetIndexRefreshResult(
                succeeded: false,
                error: resolutionError?.localizedDescription ?? "System asset index is not ready.",
                addedDocumentIDs: [],
                removedDocumentIDs: [],
                changedDocumentIDs: [],
                renamedDocumentIDs: [],
                totalDocuments: 0,
                indexVersion: 0,
                fullRebuild: false,
                persisted: false
            )
        }
        return store.refresh(progress: progress)
    }

    public var isReady: Bool {
        index != nil
    }

    public var documentCount: Int {
        index?.documentCount ?? 0
    }

    public func document(fileName: String) -> SystemAssetDocument? {
        index?.document(fileName: fileName)
    }

    public func search(_ query: String, limit: Int = 10) -> [SystemAssetSearchResult] {
        index?.search(query, limit: limit) ?? []
    }

    public func retrieve(request: String?, provider: String?, model: String?) -> [SystemAssetSearchResult] {
        let query = [request, provider, model]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else {
            return []
        }
        return search(query, limit: 10)
    }

    public func systemPrompt(for request: String?, provider: String?, model: String?, assistant: AssistantPromptDescriptor? = nil) -> SystemPrompt {
        guard let index else {
            let baseline = SystemPromptBuilder.minimalBaselinePrompt(error: loadError)
            OutputRedactionGate.shared.registerSensitiveText(baseline.text)
            return baseline
        }
        let prompt = SystemPromptBuilder().build(index: index, request: request, provider: provider, model: model, assistant: assistant)
        OutputRedactionGate.shared.registerSensitiveText(prompt.text)
        return prompt
    }
}
