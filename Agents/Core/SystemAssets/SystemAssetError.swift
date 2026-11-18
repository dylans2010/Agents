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
        case .assetsDirectoryMissing(let searched):
            let paths = searched.map(\.path).joined(separator: ", ")
            return "System Assets directory was not found. Searched: \(paths)"
        case .noDocumentsFound(let directory):
            return "No Markdown system assets were found in \(directory.path)."
        case .documentUnreadable(let fileName):
            return "System asset \(fileName) could not be read."
        case .documentMalformed(let fileName, let reason):
            return "System asset \(fileName) is malformed: \(reason)"
        case .mandatoryDocumentMissing(let fileName):
            return "Mandatory system asset \(fileName) is missing; the request cannot proceed with full instructions."
        case .retrievalUnavailable(let reason):
            return "System asset retrieval is unavailable: \(reason)"
        }
    }
}
