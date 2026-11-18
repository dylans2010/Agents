import Foundation

public nonisolated struct SystemAssetSearchResult: Sendable, Hashable {
    public var documentID: String
    public var fileName: String
    public var title: String
    public var sectionHeading: String
    public var headingPath: [String]
    public var text: String
    public var score: Int
    public var reason: String
    public var contentHash: String

    public init(documentID: String, fileName: String, title: String, sectionHeading: String, headingPath: [String], text: String, score: Int, reason: String, contentHash: String) {
        self.documentID = documentID
        self.fileName = fileName
        self.title = title
        self.sectionHeading = sectionHeading
        self.headingPath = headingPath
        self.text = text
        self.score = score
        self.reason = reason
        self.contentHash = contentHash
    }
}
