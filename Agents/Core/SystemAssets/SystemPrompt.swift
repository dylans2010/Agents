import Foundation

public nonisolated struct SystemPrompt: Sendable {
    public var text: String
    public var includedDocumentIDs: [String]
    public var omittedDocumentIDs: [String]
    public var estimatedTokens: Int
    public var isBaselineFallback: Bool
    public var loadError: SystemAssetError?
    public var assistantID: String?

    public init(text: String, includedDocumentIDs: [String], omittedDocumentIDs: [String], estimatedTokens: Int, isBaselineFallback: Bool, loadError: SystemAssetError?, assistantID: String? = nil) {
        self.text = text
        self.includedDocumentIDs = includedDocumentIDs
        self.omittedDocumentIDs = omittedDocumentIDs
        self.estimatedTokens = estimatedTokens
        self.isBaselineFallback = isBaselineFallback
        self.loadError = loadError
        self.assistantID = assistantID
    }
}
