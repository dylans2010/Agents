import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Assistant Library: ViewModel Search, Filter, Favorites, Recents & Actions")
struct AssistantLibraryViewModelTests {

    @MainActor
    private final class RecordingStore {
        var savedDrafts: [RemoteAssistantDraft] = []
        var deletedRecords: [RemoteAssistant] = []
        var launched: [(RemoteAssistant, String)] = []

        func store() -> AssistantLibraryStore {
            AssistantLibraryStore(
                saveDraft: { draft in
                    self.savedDrafts.append(draft)
                    return draft.id ?? UUID()
                },
                deleteRecord: { record in
                    self.deletedRecords.append(record)
                },
                launchRecord: { record, task in
                    self.launched.append((record, task))
                }
            )
        }
    }

    private struct Harness {
        let viewModel: AssistantLibraryViewModel
        let store: RecordingStore
        let defaults: UserDefaults
        let suiteName: String
    }

    @MainActor
    private func makeHarness(
        builtIns: [AssistantDefinition],
        stored: [RemoteAssistant] = [],
        seededRecentIDs: [String] = [],
        initialSelection: AssistantLibrarySidebarSelection? = nil,
        onAddToAutomation: AssistantAutomationRequestHandler? = nil
    ) -> Harness {
        let suiteName = "com.apoorvdarshan.coincide.tests.assistantLibrary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(seededRecentIDs, forKey: AssistantLibraryViewModel.recentIDsDefaultsKey)
        let store = RecordingStore()
        let viewModel = AssistantLibraryViewModel(
            catalog: AssistantCatalog(builtIns: builtIns, stored: stored),
            store: store.store(),
            defaults: defaults,
            initialSelection: initialSelection,
            onAddToAutomation: onAddToAutomation
        )
        return Harness(viewModel: viewModel, store: store, defaults: defaults, suiteName: suiteName)
    }

    private static func preset(
        slug: String = "tidy-imports",
        name: String = "Tidy Imports",
        description: String = "Tidies imports",
        category: AssistantCategory = .codeMaintenance,
        icon: String = "arrow.triangle.2.circlepath",
        systemPrompt: String = "Tidy the imports.",
        intendedTasks: [String] = ["Sort imports", "Remove unused imports"],
        allowedTools: [String]? = ["read_file"]
    ) -> AssistantDefinition {
        AssistantDefinition(
            id: AssistantDefinition.builtInID(category: category, slug: slug),
            name: name,
            description: description,
            category: category,
            icon: icon,
            systemPrompt: systemPrompt,
            intendedTasks: intendedTasks,
            allowedTools: allowedTools
        )
    }

    private static func customRecord(
        id: UUID = UUID(),
        name: String = "My Helper",
        isFavorite: Bool = false,
        category: RemoteAssistant.Category = .codeMaintenance
    ) -> RemoteAssistant {
        RemoteAssistant(
            id: id,
            name: name,
            category: category,
            systemPrompt: "Help.",
            source: .custom,
            isFavorite: isFavorite
        )
    }

    private static func overrideRecord(
        for preset: AssistantDefinition,
        name: String? = nil,
        isFavorite: Bool = false
    ) -> RemoteAssistant {
        RemoteAssistant(
            id: preset.persistenceID ?? UUID(),
            name: name ?? preset.name,
            description: preset.description,
            icon: preset.icon,
            category: preset.category.remote,
            systemPrompt: preset.systemPrompt,
            intendedTasks: preset.intendedTasks,
            expectedOutputFormat: preset.expectedOutputFormat,
            allowedTools: preset.allowedTools,
            provider: preset.modelConfig.provider,
            model: preset.modelConfig.model,
            permissionProfile: preset.permissionProfile.remote,
            inputRequirements: preset.inputRequirements,
            version: preset.version,
            source: .override,
            isFavorite: isFavorite
        )
    }

    @Test("Search matches the assistant name")
    @MainActor
    func searchMatchesName() {
        let harness = makeHarness(builtIns: [Self.preset(), Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"])])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.searchText = "review"
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Review PR"])
    }

    @Test("Search matches the description")
    @MainActor
    func searchMatchesDescription() {
        let harness = makeHarness(builtIns: [Self.preset(), Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"])])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.searchText = "pull requests"
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Review PR"])
    }

    @Test("Search matches capabilities: intended tasks and allowed tools")
    @MainActor
    func searchMatchesCapability() {
        let harness = makeHarness(builtIns: [Self.preset(), Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"])])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.searchText = "unused imports"
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Tidy Imports"])
        harness.viewModel.searchText = "read_file"
        #expect(harness.viewModel.visibleDefinitions.count == 2)
    }

    @Test("Search is case-insensitive and every token must match somewhere")
    @MainActor
    func searchIsCaseInsensitiveAndRequiresAllTokens() {
        let harness = makeHarness(builtIns: [Self.preset(), Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"])])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.searchText = "TIDY imports"
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Tidy Imports"])
        harness.viewModel.searchText = "tidy pull"
        #expect(harness.viewModel.visibleDefinitions.isEmpty)
    }

    @Test("Category filter narrows to that category")
    @MainActor
    func categoryFilterNarrowsToCategory() {
        let harness = makeHarness(builtIns: [Self.preset(), Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"])])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.selectedCategory = .codeReviewSecurity
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Review PR"])
        harness.viewModel.selectedCategory = .codeMaintenance
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Tidy Imports"])
    }

    @Test("Favorites scope shows only favorited assistants")
    @MainActor
    func favoritesScopeShowsOnlyFavorites() {
        let tidy = Self.preset()
        let review = Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"])
        let harness = makeHarness(builtIns: [tidy, review], stored: [Self.overrideRecord(for: review, isFavorite: true)])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        #expect(harness.viewModel.favoriteDefinitions.map(\.name) == ["Review PR"])
        harness.viewModel.scope = .favorites
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Review PR"])
    }

    @Test("Recents scope shows most-recent-first")
    @MainActor
    func recentsScopeShowsMostRecentFirst() {
        let tidy = Self.preset()
        let review = Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"])
        let harness = makeHarness(builtIns: [tidy, review])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.recordRecentUse(of: tidy)
        harness.viewModel.recordRecentUse(of: review)
        harness.viewModel.recordRecentUse(of: tidy)
        #expect(harness.viewModel.recentDefinitions.map(\.name) == ["Tidy Imports", "Review PR"])
        harness.viewModel.scope = .recent
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Tidy Imports", "Review PR"])
    }

    @Test("Sort by name orders alphabetically")
    @MainActor
    func sortByNameOrdersAlphabetically() {
        let harness = makeHarness(builtIns: [
            Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"]),
            Self.preset(),
        ])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.sortOrder = .name
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Review PR", "Tidy Imports"])
    }

    @Test("Sort by category groups by category display name")
    @MainActor
    func sortByCategoryGroupsByCategory() {
        let harness = makeHarness(builtIns: [
            Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"]),
            Self.preset(),
        ])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.sortOrder = .category
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Tidy Imports", "Review PR"])
    }

    @Test("Sort by recently used puts recents first, then name order")
    @MainActor
    func sortByRecentlyUsedOrdersByRecency() {
        let tidy = Self.preset()
        let review = Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"])
        let plan = Self.preset(slug: "plan-release", name: "Plan Release", description: "Plans a release", category: .specializedProductivity, intendedTasks: ["Draft plan"], allowedTools: nil)
        let harness = makeHarness(builtIns: [tidy, review, plan])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.recordRecentUse(of: review)
        harness.viewModel.sortOrder = .recentlyUsed
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Review PR", "Plan Release", "Tidy Imports"])
    }

    @Test("Toggling a custom favorite saves a custom draft with the flipped flag")
    @MainActor
    func toggleFavoriteCustomSavesDraftWithFlippedFlag() async {
        let record = Self.customRecord(name: "My Helper", isFavorite: false)
        let harness = makeHarness(builtIns: [Self.preset()], stored: [record])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let definition = harness.viewModel.catalog.customDefinitions.first!
        #expect(harness.viewModel.isFavorite(definition) == false)
        let saved = await harness.viewModel.toggleFavorite(definition)
        #expect(saved == true)
        #expect(harness.store.savedDrafts.count == 1)
        let draft = harness.store.savedDrafts[0]
        #expect(draft.id == record.id)
        #expect(draft.source == .custom)
        #expect(draft.isFavorite == true)
        #expect(draft.name == "My Helper")
    }

    @Test("Toggling a built-in favorite saves an override draft copying the preset")
    @MainActor
    func toggleFavoriteBuiltinSavesOverrideDraft() async {
        let tidy = Self.preset()
        let harness = makeHarness(builtIns: [tidy])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let saved = await harness.viewModel.toggleFavorite(tidy)
        #expect(saved == true)
        #expect(harness.store.savedDrafts.count == 1)
        let draft = harness.store.savedDrafts[0]
        #expect(draft.id == tidy.persistenceID)
        #expect(draft.source == .override)
        #expect(draft.isFavorite == true)
        #expect(draft.name == tidy.name)
        #expect(draft.systemPrompt == tidy.systemPrompt)
        #expect(draft.category == tidy.category.remote)
    }

    @Test("Toggling a favorited assistant saves a draft with the flag off")
    @MainActor
    func toggleFavoriteFromFavoriteSavesDraftWithFlagOff() async {
        let record = Self.customRecord(name: "My Helper", isFavorite: true)
        let harness = makeHarness(builtIns: [Self.preset()], stored: [record])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let definition = harness.viewModel.catalog.customDefinitions.first!
        #expect(harness.viewModel.isFavorite(definition) == true)
        _ = await harness.viewModel.toggleFavorite(definition)
        #expect(harness.store.savedDrafts[0].isFavorite == false)
    }

    @Test("Duplicate creates a real custom copy draft with a fresh ID")
    @MainActor
    func duplicateCreatesCustomCopyDraft() async {
        let tidy = Self.preset()
        let harness = makeHarness(builtIns: [tidy])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let copy = await harness.viewModel.duplicate(tidy)
        #expect(copy != nil)
        #expect(copy?.name == "Tidy Imports Copy")
        #expect(copy?.isBuiltIn == false)
        #expect(copy?.version == 1)
        #expect(harness.store.savedDrafts.count == 1)
        let draft = harness.store.savedDrafts[0]
        #expect(draft.id == copy?.persistenceID)
        #expect(draft.source == .custom)
        #expect(draft.name == "Tidy Imports Copy")
        #expect(draft.systemPrompt == tidy.systemPrompt)
        #expect(draft.isFavorite == false)
    }

    @Test("Duplicate name increments when a copy already exists")
    @MainActor
    func duplicateNameIncrementsWhenCopyExists() async {
        let tidy = Self.preset()
        let existingCopy = Self.customRecord(name: "Tidy Imports Copy")
        let harness = makeHarness(builtIns: [tidy], stored: [existingCopy])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        #expect(harness.viewModel.duplicateName(for: tidy) == "Tidy Imports Copy 2")
        let secondCopy = Self.customRecord(name: "Tidy Imports Copy 2")
        let harness2 = makeHarness(builtIns: [tidy], stored: [existingCopy, secondCopy])
        defer { harness2.defaults.removePersistentDomain(forName: harness2.suiteName) }
        #expect(harness2.viewModel.duplicateName(for: tidy) == "Tidy Imports Copy 3")
    }

    @Test("Delete custom deletes the stored record and clears selection")
    @MainActor
    func deleteCustomDeletesStoredRecord() async {
        let record = Self.customRecord(name: "My Helper")
        let harness = makeHarness(builtIns: [Self.preset()], stored: [record])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let definition = harness.viewModel.catalog.customDefinitions.first!
        harness.viewModel.selectedDefinitionID = definition.id
        let deleted = await harness.viewModel.deleteCustom(definition)
        #expect(deleted == true)
        #expect(harness.store.deletedRecords.map(\.id) == [record.id])
        #expect(harness.viewModel.selectedDefinitionID == nil)
    }

    @Test("Delete refuses built-in assistants and touches no record")
    @MainActor
    func deleteBuiltinIsRefused() async {
        let tidy = Self.preset()
        let harness = makeHarness(builtIns: [tidy])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let deleted = await harness.viewModel.deleteCustom(tidy)
        #expect(deleted == false)
        #expect(harness.store.deletedRecords.isEmpty)
    }

    @Test("Restore defaults deletes the override record and returns the preset")
    @MainActor
    func restoreDefaultsDeletesOverrideRecord() async {
        let tidy = Self.preset()
        let override = Self.overrideRecord(for: tidy, name: "My Tidy Imports")
        let harness = makeHarness(builtIns: [tidy], stored: [override])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let resolved = harness.viewModel.catalog.builtInDefinitions.first!
        #expect(resolved.customized == true)
        #expect(harness.viewModel.canRestoreDefaults(resolved) == true)
        let preset = await harness.viewModel.restoreDefaults(resolved)
        #expect(preset?.name == "Tidy Imports")
        #expect(harness.store.deletedRecords.map(\.id) == [override.id])
    }

    @Test("Restore defaults is refused when the built-in is not customized")
    @MainActor
    func restoreDefaultsRefusedWhenNotCustomized() async {
        let tidy = Self.preset()
        let harness = makeHarness(builtIns: [tidy])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        #expect(harness.viewModel.canRestoreDefaults(tidy) == false)
        let preset = await harness.viewModel.restoreDefaults(tidy)
        #expect(preset == nil)
        #expect(harness.store.deletedRecords.isEmpty)
    }

    @Test("Restore defaults updates the local catalog immediately")
    @MainActor
    func restoreDefaultsUpdatesLocalCatalogImmediately() async {
        let tidy = Self.preset()
        let override = Self.overrideRecord(for: tidy, name: "My Tidy Imports")
        let harness = makeHarness(builtIns: [tidy], stored: [override])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let resolved = harness.viewModel.catalog.builtInDefinitions.first!
        #expect(resolved.customized == true)
        let preset = await harness.viewModel.restoreDefaults(resolved)
        #expect(preset?.name == "Tidy Imports")
        #expect(harness.viewModel.catalog.builtInDefinitions.first?.customized == false)
        #expect(harness.viewModel.catalog.builtInDefinitions.first?.name == "Tidy Imports")
        #expect(harness.viewModel.catalog.overrideRecord(forBuiltinID: tidy.id) == nil)
        #expect(harness.viewModel.canRestoreDefaults(tidy) == false)
    }

    @Test("Sidebar category counts match the ViewModel counts")
    @MainActor
    func sidebarCategoryCountsMatchViewModelCounts() {
        let harness = makeHarness(builtIns: [
            Self.preset(),
            Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"]),
            Self.preset(slug: "fix-build", name: "Fix Build", description: "Fixes broken builds", category: .buildingFixing, intendedTasks: ["Find the failure"], allowedTools: ["read_file"]),
        ])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let sidebarCounts = AssistantLibraryViewModel.countsByCategory(in: harness.viewModel.catalog)
        #expect(sidebarCounts == harness.viewModel.countsByCategory)
        #expect(sidebarCounts[.codeMaintenance] == 1)
        #expect(sidebarCounts[.codeReviewSecurity] == 1)
        #expect(sidebarCounts[.buildingFixing] == 1)
        #expect(sidebarCounts[.gitWorkflowAutomation] == nil)
    }

    @Test("Recents badge excludes stale IDs and init writes the pruned list back")
    @MainActor
    func recentsBadgeExcludesStaleIDs() {
        let tidy = Self.preset()
        let staleID = "assistant.custom.deleted-assistant"
        let harness = makeHarness(builtIns: [tidy], seededRecentIDs: [staleID, tidy.id])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        #expect(harness.viewModel.recentDefinitions.map(\.id) == [tidy.id])
        #expect(AssistantLibraryViewModel.prunedRecentIDs(in: harness.defaults, catalog: harness.viewModel.catalog) == [tidy.id])
        #expect(harness.defaults.stringArray(forKey: AssistantLibraryViewModel.recentIDsDefaultsKey) == [tidy.id])
    }

    @Test("Recent use caps at ten entries and moves repeats to the front")
    @MainActor
    func recordRecentUseCapsAtTenAndMovesToFront() {
        let presets = (1...12).map { index in
            Self.preset(slug: "task-\(index)", name: "Task \(index)", description: "Task \(index)", intendedTasks: [], allowedTools: nil)
        }
        let harness = makeHarness(builtIns: presets)
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        for preset in presets {
            harness.viewModel.recordRecentUse(of: preset)
        }
        #expect(harness.viewModel.recentDefinitions.count == 10)
        #expect(harness.viewModel.recentDefinitions.first?.name == "Task 12")
        #expect(harness.viewModel.recentDefinitions.map(\.name).contains("Task 1") == false)
        #expect(harness.viewModel.recentDefinitions.map(\.name).contains("Task 2") == false)
        harness.viewModel.recordRecentUse(of: presets[4])
        #expect(harness.viewModel.recentDefinitions.first?.name == "Task 5")
        #expect(harness.viewModel.recentDefinitions.count == 10)
    }

    @Test("Sidebar selection maps to scope and category filter")
    @MainActor
    func applySidebarSelectionMapsCategoryAndScope() {
        let harness = makeHarness(builtIns: [Self.preset()])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.applySidebarSelection(.favorites)
        #expect(harness.viewModel.scope == .favorites)
        #expect(harness.viewModel.selectedCategory == nil)
        harness.viewModel.applySidebarSelection(.recent)
        #expect(harness.viewModel.scope == .recent)
        harness.viewModel.applySidebarSelection(.category(.codeReviewSecurity))
        #expect(harness.viewModel.scope == .all)
        #expect(harness.viewModel.selectedCategory == .codeReviewSecurity)
        harness.viewModel.applySidebarSelection(.all)
        #expect(harness.viewModel.scope == .all)
        #expect(harness.viewModel.selectedCategory == nil)
    }

    @Test("Sidebar selection stored value round-trips through UserDefaults strings")
    @MainActor
    func sidebarSelectionStoredValueRoundTrips() {
        let selections: [AssistantLibrarySidebarSelection] = [
            .all, .favorites, .recent, .category(.gitWorkflowAutomation),
        ]
        for selection in selections {
            let restored = AssistantLibrarySidebarSelection(storedValue: selection.storedValue)
            #expect(restored == selection)
        }
        #expect(AssistantLibrarySidebarSelection(storedValue: "") == nil)
        #expect(AssistantLibrarySidebarSelection(storedValue: "category.nope") == nil)
    }

    @Test("Launch record for a built-in synthesizes the deterministic persistence ID")
    @MainActor
    func remoteRecordForBuiltinSynthesizesDeterministicID() {
        let tidy = Self.preset()
        let harness = makeHarness(builtIns: [tidy])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let record = harness.viewModel.remoteRecord(for: tidy)
        #expect(record?.id == tidy.persistenceID)
        #expect(record?.name == tidy.name)
        #expect(record?.systemPrompt == tidy.systemPrompt)
        #expect(record?.source == .override)
    }

    @Test("Launch record for a customized built-in returns the stored override record")
    @MainActor
    func remoteRecordForCustomizedBuiltinReturnsOverride() {
        let tidy = Self.preset()
        let override = Self.overrideRecord(for: tidy, name: "My Tidy Imports")
        let harness = makeHarness(builtIns: [tidy], stored: [override])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        let resolved = harness.viewModel.catalog.builtInDefinitions.first!
        let record = harness.viewModel.remoteRecord(for: resolved)
        #expect(record?.id == override.id)
        #expect(record?.name == "My Tidy Imports")
    }

    @Test("Launch records recency and calls the store with the trimmed task")
    @MainActor
    func launchRecordsRecencyAndCallsStore() async {
        let tidy = Self.preset()
        let harness = makeHarness(builtIns: [tidy])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        await harness.viewModel.launch(tidy, task: "   ")
        #expect(harness.store.launched.isEmpty)
        #expect(harness.viewModel.recentDefinitions.isEmpty)
        await harness.viewModel.launch(tidy, task: "  Tidy the imports in Sources  ")
        #expect(harness.store.launched.count == 1)
        #expect(harness.store.launched[0].1 == "Tidy the imports in Sources")
        #expect(harness.store.launched[0].0.id == tidy.persistenceID)
        #expect(harness.viewModel.recentDefinitions.map(\.name) == ["Tidy Imports"])
    }

    @Test("Add to automation invokes the callback with the definition")
    @MainActor
    func addToAutomationInvokesCallback() {
        let tidy = Self.preset()
        var received: [AssistantDefinition] = []
        let harness = makeHarness(builtIns: [tidy], onAddToAutomation: { definition in
            received.append(definition)
        })
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.requestAddToAutomation(tidy)
        #expect(received.map(\.id) == [tidy.id])
        let harnessWithoutCallback = makeHarness(builtIns: [tidy])
        defer { harnessWithoutCallback.defaults.removePersistentDomain(forName: harnessWithoutCallback.suiteName) }
        harnessWithoutCallback.viewModel.requestAddToAutomation(tidy)
    }

    @Test("Search and category filter compose")
    @MainActor
    func searchAndCategoryFilterCompose() {
        let harness = makeHarness(builtIns: [
            Self.preset(),
            Self.preset(slug: "review-pr", name: "Review PR", description: "Reviews pull requests", category: .codeReviewSecurity, intendedTasks: ["Find bugs"], allowedTools: ["read_file"]),
            Self.preset(slug: "fix-build", name: "Fix Build", description: "Fixes broken builds", category: .buildingFixing, intendedTasks: ["Find the failure"], allowedTools: ["read_file"]),
        ])
        defer { harness.defaults.removePersistentDomain(forName: harness.suiteName) }
        harness.viewModel.searchText = "read_file"
        harness.viewModel.selectedCategory = .buildingFixing
        #expect(harness.viewModel.visibleDefinitions.map(\.name) == ["Fix Build"])
    }
}
