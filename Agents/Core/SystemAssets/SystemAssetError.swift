import Foundation

public nonisolated enum SystemAssetError: Error, LocalizedError, Sendable, Equatable {
    case assetsDirectoryMissing(searched: [URL])
    case noDocumentsFound(directory: URL)
    case documentUnreadable(fileName: String)
    case documentMalformed(fileName: String, reason: String)
    case mandatoryDocumentMissing(fileName: String)
    case retrievalUnavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .assetsDirectoryMissing:
            return "System Assets unavailable."
        case .noDocumentsFound:
            return "System Assets unavailable."
        case .documentUnreadable:
            return "A system asset could not be read."
        case .documentMalformed(_, let reason):
            return "A system asset is malformed: \(reason)"
        case .mandatoryDocumentMissing:
            return "A mandatory system asset is missing; the request cannot proceed with full instructions."
        case .retrievalUnavailable:
            return "System asset retrieval is unavailable."
        }
    }
}
