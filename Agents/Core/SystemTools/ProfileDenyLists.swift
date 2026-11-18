import Foundation

nonisolated enum ProfileDenyLists {
    struct Manifest: Decodable {
        let readOnlyDenied: [String]
        let approvalRequiredDenied: [String]
    }

    static let manifest: Manifest? = loadManifest()

    static var readOnlyDenied: Set<String> {
        if let manifest {
            return Set(manifest.readOnlyDenied)
        }
        return Set(SystemToolRegistry.systemTools.map(\.name))
    }

    static var approvalRequiredDenied: Set<String> {
        if let manifest {
            return Set(manifest.approvalRequiredDenied)
        }
        return Set(SystemToolRegistry.systemTools.map(\.name))
    }

    static func manifestURL() -> URL? {
        for candidate in manifestCandidates() {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func manifestCandidates() -> [URL] {
        var candidates: [URL] = []
        if let url = Bundle.main.url(forResource: "ProfileDenyLists", withExtension: "json") {
            candidates.append(url)
        }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "ProfileDenyLists", withExtension: "json") {
                candidates.append(url)
            }
        }
        if let bundleURL = Bundle.main.bundleURL as URL? {
            var ancestor: URL? = bundleURL
            for _ in 0..<6 {
                guard let current = ancestor else {
                    break
                }
                candidates.append(current.appendingPathComponent("Agents/Resources/ProfileDenyLists.json"))
                ancestor = current.deletingLastPathComponent()
                if ancestor?.path == "/" {
                    break
                }
            }
        }
        var workingDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            candidates.append(workingDir.appendingPathComponent("Agents/Resources/ProfileDenyLists.json"))
            let parent = workingDir.deletingLastPathComponent()
            if parent == workingDir {
                break
            }
            workingDir = parent
        }
        var unique: [URL] = []
        for candidate in candidates where !unique.contains(candidate) {
            unique.append(candidate)
        }
        return unique
    }

    private static func loadManifest() -> Manifest? {
        guard let url = manifestURL() else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }
}
