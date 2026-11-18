import Foundation

public nonisolated struct SystemAssetSection: Sendable, Hashable {
    public var documentID: String
    public var fileName: String
    public var heading: String
    public var level: Int
    public var headingPath: [String]
    public var body: String
    public var estimatedTokens: Int

    public init(documentID: String, fileName: String, heading: String, level: Int, headingPath: [String], body: String) {
        self.documentID = documentID
        self.fileName = fileName
        self.heading = heading
        self.level = level
        self.headingPath = headingPath
        self.body = body
        self.estimatedTokens = max(1, (heading.count + body.count + 3) / 4)
    }

    public var displayText: String {
        if heading.isEmpty {
            return body
        }
        return heading + "\n\n" + body
    }
}
