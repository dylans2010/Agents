import CoincideRemoteKit
import Foundation
import Observation

public typealias AssistantAutomationRequestHandler = @MainActor (AssistantDefinition) -> Void
public typealias AssistantLaunchRequestHandler = @MainActor (AssistantDefinition, String) -> Void

public enum AssistantLibraryScope: String, CaseIterable, Sendable {
    case all
    case favorites
    case recent

    public var title: String {
        switch self {
        case .all: "All"
        case .favorites: "Favorites"
        case .recent: "Recent"
        }
    }
}

public enum AssistantLibrarySortOrder: String, CaseIterable, Sendable {
    case name
    case recentlyUsed
    case category

    public var title: String {
        switch self {
        case .name: "Name"
        case .recentlyUsed: "Recently Used"
        case .category: "Category"
        }
    }
}

public enum AssistantLibrarySidebarSelection: Hashable, Sendable {
    case all
    case favorites
    case recent
    case category(AssistantCategory)

    public static let userDefaultsKey = "coincide.assistantLibrarySelection"

    public var storedValue: String {
        switch self {
        case .all: "all"
        case .favorites: "favorites"
        case .recent: "recent"
        case .category(let category): "category.\(category.rawValue)"
        }
    }

    public init?(storedValue: String) {
        switch storedValue {
        case "all":
            self = .all
        case "favorites":
            self = .favorites
        case "recent":
            self = .recent
        case let value where value.hasPrefix("category."):
            guard let category = AssistantCategory(rawValue: String(value.dropFirst("category.".count))) else {
                return nil
            }
            self = .category(category)
        default:
            return nil
        }
    }
}

public struct AssistantLibraryStore {
    public var saveDraft: @MainActor (RemoteAssistantDraft) async -> UUID?
    public var deleteRecord: @MainActor (RemoteAssistant) async -> Void
    public var launchRecord: @MainActor (RemoteAssistant, String) async -> Void

    public init(
        saveDraft: @escaping @MainActor (RemoteAssistantDraft) async -> UUID?,
        deleteRecord: @escaping @MainActor (RemoteAssistant) async -> Void,
        launchRecord: @escaping @MainActor (RemoteAssistant, String) async -> Void
    ) {
        self.saveDraft = saveDraft
        self.deleteRecord = deleteRecord
        self.launchRecord = launchRecord
    }

    public static func live(appModel: AppModel) -> AssistantLibraryStore {
        AssistantLibraryStore(
            saveDraft: { draft in await appModel.saveAssistant(draft) },
            deleteRecord: { record in await appModel.deleteAssistant(record) },
            launchRecord: { record, task in await appModel.launchAssistant(record, task: task) }
        )
    }
}

@Observable
@MainActor
public final class AssistantLibraryViewModel {
    public static let recentIDsDefaultsKey = "coincide.assistantLibraryRecentIDs"
    public static let recentIDsLimit = 10

    public var catalog: AssistantCatalog
    public var searchText: String = ""
    public var scope: AssistantLibraryScope = .all
    public var selectedCategory: AssistantCategory?
    public var sortOrder: AssistantLibrarySortOrder = .name
    public var selectedDefinitionID: String?
    public var onAddToAutomation: AssistantAutomationRequestHandler?
    public var onLaunch: AssistantLaunchRequestHandler?

    private let store: AssistantLibraryStore
    private let defaults: UserDefaults
    private var recentStableIDs: [String]

    public init(
        catalog: AssistantCatalog,
        store: AssistantLibraryStore,
        defaults: UserDefaults = .standard,
        initialSelection: AssistantLibrarySidebarSelection? = nil,
        onAddToAutomation: AssistantAutomationRequestHandler? = nil,
        onLaunch: AssistantLaunchRequestHandler? = nil
    ) {
        self.catalog = catalog
        self.store = store
        self.defaults = defaults
        self.onAddToAutomation = onAddToAutomation
        self.onLaunch = onLaunch
        self.recentStableIDs = Self.prunedRecentIDs(in: defaults, catalog: catalog)
        defaults.set(recentStableIDs, forKey: Self.recentIDsDefaultsKey)
        applySidebarSelection(initialSelection)
    }

    public static func prunedRecentIDs(in defaults: UserDefaults, catalog: AssistantCatalog) -> [String] {
        let storedIDs = defaults.stringArray(forKey: Self.recentIDsDefaultsKey) ?? []
        return storedIDs.filter { id in catalog.definition(forStableID: id) != nil }
    }

    public var allDefinitions: [AssistantDefinition] {
        catalog.allDefinitions
    }

    public var selectedDefinition: AssistantDefinition? {
        guard let selectedDefinitionID else { return nil }
        return catalog.definition(forStableID: selectedDefinitionID)
    }

    public var favoriteDefinitions: [AssistantDefinition] {
        allDefinitions.filter { Self.isFavorite($0, in: catalog) }
    }

    public var recentDefinitions: [AssistantDefinition] {
        let order = Dictionary(uniqueKeysWithValues: recentStableIDs.enumerated().map { ($1, $0) })
        return allDefinitions
            .filter { order[$0.id] != nil }
            .sorted { order[$0.id]! < order[$1.id]! }
    }

    public var visibleDefinitions: [AssistantDefinition] {
        var definitions = allDefinitions
        switch scope {
        case .all:
            break
        case .favorites:
            definitions = definitions.filter { Self.isFavorite($0, in: catalog) }
        case .recent:
            let recentIDs = Set(recentStableIDs)
            definitions = definitions.filter { recentIDs.contains($0.id) }
        }
        if let selectedCategory {
            definitions = definitions.filter { $0.category == selectedCategory }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            definitions = definitions.filter { matchesSearch($0, query: query) }
        }
        if scope == .recent {
            let order = Dictionary(uniqueKeysWithValues: recentStableIDs.enumerated().map { ($1, $0) })
            return definitions.sorted { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
        }
        return sorted(definitions)
    }

    public var countsByCategory: [AssistantCategory: Int] {
        Self.countsByCategory(in: catalog)
    }

    public static func countsByCategory(in catalog: AssistantCatalog) -> [AssistantCategory: Int] {
        var counts: [AssistantCategory: Int] = [:]
        for definition in catalog.allDefinitions {
            counts[definition.category, default: 0] += 1
        }
        return counts
    }

    public func isFavorite(_ definition: AssistantDefinition) -> Bool {
        Self.isFavorite(definition, in: catalog)
    }

    public static func isFavorite(_ definition: AssistantDefinition, in catalog: AssistantCatalog) -> Bool {
        guard let record = storedRecord(for: definition, in: catalog) else { return false }
        return record.isFavorite
    }

    public static func storedRecord(
        for definition: AssistantDefinition,
        in catalog: AssistantCatalog
    ) -> RemoteAssistant? {
        guard let persistenceID = definition.persistenceID else { return nil }
        if definition.isBuiltIn {
            return catalog.overrideRecord(forBuiltinID: definition.id)
        }
        return catalog.stored.first { $0.id == persistenceID && $0.source == .custom }
    }

    public func storedRecord(for definition: AssistantDefinition) -> RemoteAssistant? {
        Self.storedRecord(for: definition, in: catalog)
    }

    public func canDelete(_ definition: AssistantDefinition) -> Bool {
        !definition.isBuiltIn && storedRecord(for: definition) != nil
    }

    public func canRestoreDefaults(_ definition: AssistantDefinition) -> Bool {
        definition.isBuiltIn && catalog.overrideRecord(forBuiltinID: definition.id) != nil
    }

    public func applySidebarSelection(_ selection: AssistantLibrarySidebarSelection?) {
        guard let selection else { return }
        switch selection {
        case .all:
            scope = .all
            selectedCategory = nil
        case .favorites:
            scope = .favorites
            selectedCategory = nil
        case .recent:
            scope = .recent
            selectedCategory = nil
        case .category(let category):
            scope = .all
            selectedCategory = category
        }
    }

    public func recordRecentUse(of definition: AssistantDefinition) {
        var ids = recentStableIDs.filter { $0 != definition.id }
        ids.insert(definition.id, at: 0)
        ids = Array(ids.prefix(Self.recentIDsLimit))
        recentStableIDs = ids
        defaults.set(ids, forKey: Self.recentIDsDefaultsKey)
    }

    @discardableResult
    public func toggleFavorite(_ definition: AssistantDefinition) async -> Bool {
        guard let persistenceID = definition.persistenceID else { return false }
        let source: RemoteAssistant.Source = definition.isBuiltIn ? .override : .custom
        let draft = Self.draft(
            for: definition,
            id: persistenceID,
            source: source,
            isFavorite: !isFavorite(definition)
        )
        guard await store.saveDraft(draft) != nil else { return false }
        return true
    }

    @discardableResult
    public func duplicate(_ definition: AssistantDefinition) async -> AssistantDefinition? {
        let newID = UUID()
        var copy = definition
        copy.id = AssistantDefinition.customID(newID)
        copy.name = duplicateName(for: definition)
        copy.isBuiltIn = false
        copy.customized = false
        copy.version = 1
        let draft = Self.draft(for: copy, id: newID, source: .custom, isFavorite: false)
        guard await store.saveDraft(draft) != nil else { return nil }
        return copy
    }

    public func duplicateName(for definition: AssistantDefinition) -> String {
        let base = "\(definition.name) Copy"
        let existingNames = Set(catalog.customDefinitions.map(\.name))
        guard existingNames.contains(base) else { return base }
        var index = 2
        while existingNames.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }

    @discardableResult
    public func deleteCustom(_ definition: AssistantDefinition) async -> Bool {
        guard !definition.isBuiltIn,
              let record = storedRecord(for: definition),
              record.source == .custom
        else { return false }
        await store.deleteRecord(record)
        if selectedDefinitionID == definition.id {
            selectedDefinitionID = nil
        }
        return true
    }

    @discardableResult
    public func restoreDefaults(_ definition: AssistantDefinition) async -> AssistantDefinition? {
        guard definition.isBuiltIn,
              let record = catalog.overrideRecord(forBuiltinID: definition.id)
        else { return nil }
        guard let preset = catalog.restoreDefaults(builtinID: definition.id) else { return nil }
        await store.deleteRecord(record)
        return preset
    }

    public func launch(_ definition: AssistantDefinition, task: String) async {
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTask.isEmpty, let record = remoteRecord(for: definition) else { return }
        recordRecentUse(of: definition)
        await store.launchRecord(record, trimmedTask)
    }

    public func remoteRecord(for definition: AssistantDefinition) -> RemoteAssistant? {
        if let stored = storedRecord(for: definition) {
            return stored
        }
        guard let persistenceID = definition.persistenceID else { return nil }
        return RemoteAssistant(
            id: persistenceID,
            name: definition.name,
            description: definition.description,
            icon: definition.icon,
            category: definition.category.remote,
            systemPrompt: definition.systemPrompt,
            intendedTasks: definition.intendedTasks,
            expectedOutputFormat: definition.expectedOutputFormat,
            allowedTools: definition.allowedTools,
            provider: definition.modelConfig.provider,
            model: definition.modelConfig.model,
            permissionProfile: definition.permissionProfile.remote,
            inputRequirements: definition.inputRequirements,
            version: definition.version,
            source: .override,
            isFavorite: isFavorite(definition),
            lastUsedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    public func requestAddToAutomation(_ definition: AssistantDefinition) {
        onAddToAutomation?(definition)
    }

    public func requestLaunch(_ definition: AssistantDefinition, task: String = "") {
        onLaunch?(definition, task.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func draft(
        for definition: AssistantDefinition,
        id: UUID,
        source: RemoteAssistant.Source,
        isFavorite: Bool
    ) -> RemoteAssistantDraft {
        RemoteAssistantDraft(
            id: id,
            name: definition.name,
            description: definition.description,
            icon: definition.icon,
            category: definition.category.remote,
            systemPrompt: definition.systemPrompt,
            intendedTasks: definition.intendedTasks,
            expectedOutputFormat: definition.expectedOutputFormat,
            allowedTools: definition.allowedTools,
            provider: definition.modelConfig.provider,
            model: definition.modelConfig.model,
            permissionProfile: definition.permissionProfile.remote,
            inputRequirements: definition.inputRequirements,
            version: definition.version,
            source: source,
            isFavorite: isFavorite
        )
    }

    private func matchesSearch(_ definition: AssistantDefinition, query: String) -> Bool {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystacks = [
            definition.name.lowercased(),
            definition.description.lowercased(),
            definition.category.displayName.lowercased(),
            definition.intendedTasks.joined(separator: " ").lowercased(),
            (definition.allowedTools ?? []).joined(separator: " ").lowercased(),
        ]
        return tokens.allSatisfy { token in haystacks.contains { $0.contains(token) } }
    }

    private func sorted(_ definitions: [AssistantDefinition]) -> [AssistantDefinition] {
        switch sortOrder {
        case .name:
            return definitions.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        case .category:
            return definitions.sorted {
                ($0.category.displayName, $0.name, $0.id) < ($1.category.displayName, $1.name, $1.id)
            }
        case .recentlyUsed:
            let order = Dictionary(uniqueKeysWithValues: recentStableIDs.enumerated().map { ($1, $0) })
            return definitions.sorted { lhs, rhs in
                switch (order[lhs.id], order[rhs.id]) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return (lhs.name, lhs.id) < (rhs.name, rhs.id)
                }
            }
        }
    }
}
