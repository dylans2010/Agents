import CoincideRemoteKit
import Foundation

public struct AssistantCatalog: Sendable {
    public private(set) var builtIns: [AssistantDefinition]
    public private(set) var stored: [RemoteAssistant]

    public init(builtIns: [AssistantDefinition] = BuiltInPresets.all, stored: [RemoteAssistant] = []) {
        self.builtIns = builtIns
        self.stored = stored
    }

    public var duplicateBuiltinIDs: [String] {
        var counts: [String: Int] = [:]
        for preset in builtIns {
            counts[preset.id, default: 0] += 1
        }
        return counts.filter { $0.value > 1 }.map(\.key).sorted()
    }

    public var builtInDefinitions: [AssistantDefinition] {
        var seen: Set<String> = []
        var resolved: [AssistantDefinition] = []
        for preset in builtIns {
            guard seen.insert(preset.id).inserted else { continue }
            if let record = overrideRecord(matching: preset) {
                resolved.append(preset.applyingOverride(record))
            } else {
                resolved.append(preset)
            }
        }
        return resolved
    }

    public var customDefinitions: [AssistantDefinition] {
        stored.compactMap { record in
            guard record.source == .custom else { return nil }
            return AssistantDefinition(stored: record)
        }
        .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    public var allDefinitions: [AssistantDefinition] {
        builtInDefinitions + customDefinitions
    }

    public var customizedBuiltIns: [AssistantDefinition] {
        builtInDefinitions.filter(\.customized)
    }

    public var unmatchedOverrideIDs: [UUID] {
        let builtinIDs = Set(builtIns.compactMap(\.persistenceID))
        return stored
            .filter { $0.source == .override && !builtinIDs.contains($0.id) }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    public func builtinPreset(for stableID: String) -> AssistantDefinition? {
        builtIns.first { $0.id == stableID }
    }

    public func definition(forStableID stableID: String) -> AssistantDefinition? {
        allDefinitions.first { $0.id == stableID }
    }

    public func definition(forPersistenceID id: UUID) -> AssistantDefinition? {
        allDefinitions.first { $0.persistenceID == id }
    }

    public func presetVersion(for stableID: String) -> Int? {
        builtinPreset(for: stableID)?.version
    }

    public func versionGap(for stableID: String) -> (preset: Int, customizedAgainst: Int)? {
        guard let preset = builtinPreset(for: stableID) else { return nil }
        guard let record = overrideRecord(matching: preset) else { return nil }
        guard preset.version > record.version else { return nil }
        return (preset: preset.version, customizedAgainst: record.version)
    }

    public func overrideRecord(forBuiltinID stableID: String) -> RemoteAssistant? {
        guard let preset = builtinPreset(for: stableID) else { return nil }
        return overrideRecord(matching: preset)
    }

    public mutating func restoreDefaults(builtinID: String) -> AssistantDefinition? {
        guard let preset = builtinPreset(for: builtinID), let persistenceID = preset.persistenceID else {
            return nil
        }
        stored.removeAll { $0.id == persistenceID && $0.source == .override }
        return preset
    }

    public func invalidDefinitions() -> [(definition: AssistantDefinition, issues: [AssistantValidationIssue])] {
        allDefinitions.compactMap { definition in
            let issues = definition.validationIssues()
            return issues.isEmpty ? nil : (definition: definition, issues: issues)
        }
    }

    private func overrideRecord(matching preset: AssistantDefinition) -> RemoteAssistant? {
        guard let persistenceID = preset.persistenceID else { return nil }
        return stored.first { $0.source == .override && $0.id == persistenceID }
    }
}
