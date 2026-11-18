import Foundation

public nonisolated final class SystemAssetManager: Sendable {
    public static let assetsDirectoryName = "SystemAssets"

    public static let shared = SystemAssetManager()

    public let index: SystemAssetIndex?
    public let loadError: SystemAssetError?

    public init() {
        do {
            let directory = try SystemAssetIndex.bundledAssetsURL()
            self.index = try SystemAssetIndex.load(directory: directory)
            self.loadError = nil
        } catch let error as SystemAssetError {
            self.index = nil
            self.loadError = error
        } catch {
            self.index = nil
            self.loadError = .retrievalUnavailable(reason: error.localizedDescription)
        }
    }

    public init(directory: URL) {
        do {
            self.index = try SystemAssetIndex.load(directory: directory)
            self.loadError = nil
        } catch let error as SystemAssetError {
            self.index = nil
            self.loadError = error
        } catch {
            self.index = nil
            self.loadError = .retrievalUnavailable(reason: error.localizedDescription)
        }
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
            return SystemPromptBuilder.minimalBaselinePrompt(error: loadError)
        }
        return SystemPromptBuilder().build(index: index, request: request, provider: provider, model: model, assistant: assistant)
    }
}
