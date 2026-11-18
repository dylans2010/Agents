import Foundation

public nonisolated struct SystemAssetFingerprint: Codable, Hashable, Sendable {
    public var relativePath: String
    public var size: Int64
    public var modificationTime: Int64
    public var contentHash: String

    public init(relativePath: String, size: Int64, modificationTime: Int64, contentHash: String) {
        self.relativePath = relativePath
        self.size = size
        self.modificationTime = modificationTime
        self.contentHash = contentHash
    }

    public func hasSameFileState(as other: SystemAssetFingerprint) -> Bool {
        size == other.size && modificationTime == other.modificationTime
    }

    public static func relativePath(of fileURL: URL, in directory: URL) -> String {
        let base = directory.path
        let path = fileURL.path
        if path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        return fileURL.lastPathComponent
    }
}

public nonisolated struct SystemAssetScannedFile: Sendable, Hashable {
    public var relativePath: String
    public var size: Int64
    public var modificationTime: Int64
    public var fileURL: URL

    public init(relativePath: String, size: Int64, modificationTime: Int64, fileURL: URL) {
        self.relativePath = relativePath
        self.size = size
        self.modificationTime = modificationTime
        self.fileURL = fileURL
    }
}

public nonisolated struct SystemAssetSourceScan {
    private init() {}

    public static func scan(directory: URL) throws -> [SystemAssetScannedFile] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SystemAssetError.assetsDirectoryMissing(searched: [directory])
        }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }
        var found: [SystemAssetScannedFile] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else {
                continue
            }
            if values.isDirectory == true {
                continue
            }
            guard url.pathExtension.lowercased() == "md" else {
                continue
            }
            let milliseconds = Int64((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)
            found.append(SystemAssetScannedFile(
                relativePath: SystemAssetFingerprint.relativePath(of: url, in: directory),
                size: Int64(values.fileSize ?? 0),
                modificationTime: milliseconds,
                fileURL: url
            ))
        }
        return found.sorted { $0.relativePath < $1.relativePath }
    }
}
