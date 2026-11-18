import CoincideRemoteKit
import Foundation
import Testing
@testable import Agents

@Suite("Assistant Editor: ViewModel, Capabilities, Model Config, Overrides")
@MainActor
struct AssistantEditorViewModelTests {

    private static func makePreset() -> AssistantDefinition {
        AssistantDefinition(
            id: AssistantDefinition.builtInID(category: .codeMaintenance, slug: "test-preset"),
            name: "Test Preset",
            description: "A preset used only by these tests.",
            category: .codeMaintenance,
            icon: "hammer",
            systemPrompt: "Preset prompt.",
            intendedTasks: ["Preset task"],
            expectedOutputFormat: "Preset output.",
            allowedTools: ["read_file", "dead_code_scan"],
            modelConfig: .appDefault,
            permissionProfile: .readOnly,
            inputRequirements: ["Preset input"],
            version: 2,
            isBuiltIn: true,
            customized: false
        )
    }

    private static func makeCustomDefinition() -> AssistantDefinition {
        AssistantDefinition(
            id: AssistantDefinition.customID(UUID(uuidString: "AAAAAAAA-1111-4111-8111-111111111111")!),
            name: "Custom Helper",
            description: "A custom assistant used only by these tests.",
            category: .buildingFixing,
            icon: "wrench.and.screwdriver",
            systemPrompt: "Custom prompt.",
            allowedTools: ["read_file", "mem_store", "create_terminal"],
            modelConfig: .specific(provider: "claude", model: "claude-sonnet-4"),
            permissionProfile: .readOnly,
            version: 1,
            isBuiltIn: false,
            customized: false
        )
    }

    private static func makeOverrideRecord(for preset: AssistantDefinition) -> RemoteAssistant {
        RemoteAssistant(
            id: preset.persistenceID!,
            name: "Customized Preset",
            description: "Customized by these tests.",
            icon: "paintbrush",
            category: .codeMaintenance,
            systemPrompt: "Customized prompt.",
            version: 2,
            source: .override
        )
    }

    @Test("A new assistant defaults to the read-only permission profile")
    func newAssistantDefaultsToReadOnly() {
        let viewModel = AssistantEditorViewModel()
        #expect(viewModel.permissionProfile == .readOnly)
        #expect(viewModel.permissionConsequence == nil)
    }

    @Test("A new assistant starts with read, search, and repo-analysis capabilities only")
    func newAssistantDefaultCapabilities() {
        let viewModel = AssistantEditorViewModel()
        #expect(viewModel.isCapabilityEnabled(.fileRead))
        #expect(viewModel.isCapabilityEnabled(.search))
        #expect(viewModel.isCapabilityEnabled(.repoAnalysis))
        #expect(!viewModel.isCapabilityEnabled(.fileEdit))
        #expect(!viewModel.isCapabilityEnabled(.terminal))
        #expect(!viewModel.isCapabilityEnabled(.git))
        #expect(!viewModel.isCapabilityEnabled(.codeExecution))
    }

    @Test("An empty name and an empty prompt are validation issues and block saving")
    func emptyNameAndPromptBlockSaving() {
        let viewModel = AssistantEditorViewModel()
        #expect(viewModel.validationIssues.contains(.emptyName))
        #expect(viewModel.validationIssues.contains(.emptySystemPrompt))
        #expect(!viewModel.isValid)
        #expect(viewModel.saveDisabledReason != nil)
        viewModel.name = "Helper"
        viewModel.systemPrompt = "Do the job."
        #expect(viewModel.isValid)
        #expect(viewModel.saveDisabledReason == nil)
    }

    @Test("Over-limit text surfaces the matching validation issues")
    func overLimitTextSurfacesIssues() {
        let viewModel = AssistantEditorViewModel()
        viewModel.name = String(repeating: "n", count: AssistantDefinition.nameLimit + 1)
        viewModel.systemPrompt = String(repeating: "p", count: AssistantDefinition.systemPromptLimit + 1)
        #expect(viewModel.validationIssues.contains(.nameTooLong))
        #expect(viewModel.validationIssues.contains(.systemPromptTooLong))
        #expect(!viewModel.isValid)
    }

    @Test("Every capability maps only to real registry tool names")
    func capabilityToolsAreAllRealRegistryNames() {
        for capability in AssistantCapability.allCases {
            #expect(SystemToolRegistry.unknownToolNames(in: capability.tools).isEmpty)
        }
    }

    @Test("Capability toggles add and remove exactly their mapped tools")
    func capabilityTogglesMapTools() {
        let viewModel = AssistantEditorViewModel()
        viewModel.setCapability(.fileEdit, enabled: true)
        #expect(viewModel.allowedTools?.contains("write_file") == true)
        #expect(viewModel.allowedTools?.contains("edit_file") == true)
        #expect(viewModel.allowedTools?.contains("multi_edit_file") == true)
        viewModel.setCapability(.fileEdit, enabled: false)
        #expect(viewModel.allowedTools?.contains("write_file") == false)
        #expect(viewModel.allowedTools?.contains("edit_file") == false)
        #expect(viewModel.allowedTools?.contains("multi_edit_file") == false)
        #expect(viewModel.isCapabilityEnabled(.fileRead))
    }

    @Test("An unknown tool in an edited assistant is rejected by validation")
    func unknownToolIsRejected() {
        var definition = Self.makeCustomDefinition()
        definition.allowedTools = ["read_file", "not_a_real_tool"]
        let viewModel = AssistantEditorViewModel(editing: definition)
        #expect(viewModel.validationIssues.contains(.unknownTool(name: "not_a_real_tool")))
        #expect(!viewModel.isValid)
        #expect(viewModel.saveDisabledReason?.contains("not_a_real_tool") == true)
    }

    @Test("Toggling a capability off keeps tools outside every capability")
    func capabilityTogglePreservesUnrelatedTools() {
        let definition = Self.makeCustomDefinition()
        let viewModel = AssistantEditorViewModel(editing: definition)
        viewModel.setCapability(.terminal, enabled: false)
        #expect(viewModel.allowedTools?.contains("mem_store") == true)
        #expect(viewModel.allowedTools?.contains("create_terminal") == false)
        #expect(viewModel.allowedTools?.contains("read_file") == true)
    }

    @Test("Model modes map to the draft provider and model fields")
    func modelConfigMapping() {
        let viewModel = AssistantEditorViewModel()
        viewModel.setModelMode(.specific)
        viewModel.provider = "claude"
        viewModel.model = "claude-sonnet-4"
        var draft = viewModel.makeDraft()
        #expect(draft.provider == "claude")
        #expect(draft.model == "claude-sonnet-4")
        viewModel.setModelMode(.providerOnly)
        draft = viewModel.makeDraft()
        #expect(draft.provider == "claude")
        #expect(draft.model == nil)
        viewModel.setModelMode(.modelOnly)
        draft = viewModel.makeDraft()
        #expect(draft.provider == nil)
        #expect(draft.model == "claude-sonnet-4")
        viewModel.setModelMode(.appDefault)
        draft = viewModel.makeDraft()
        #expect(draft.provider == nil)
        #expect(draft.model == nil)
        viewModel.setModelMode(.currentAppModel)
        draft = viewModel.makeDraft()
        #expect(draft.provider == nil)
        #expect(draft.model == nil)
        #expect(viewModel.modelConfig == .currentAppModel)
    }

    @Test("An empty model ID in specific mode is a validation issue")
    func emptyModelInSpecificModeIsInvalid() {
        let viewModel = AssistantEditorViewModel()
        viewModel.setModelMode(.specific)
        viewModel.provider = "codex"
        viewModel.model = ""
        #expect(viewModel.validationIssues.contains(.emptyModel))
        #expect(!viewModel.isValid)
    }

    @Test("Provider options match the pinned snapshot of the engine's supported provider names")
    func providerOptionsMatchPinnedSupportedNamesSnapshot() {
        #expect(
            AssistantEditorViewModel.providerIDs == ["codex", "claude", "grok", "opencode", "lithos", "cursor", "antigravity"],
            "Provider list drifted from the pinned snapshot of the engine's supported provider names. There is no Swift-side shared source for supported_names, so update providerOptions here and re-check the engine's supported_names."
        )
        #expect(Set(AssistantEditorViewModel.providerIDs).count == AssistantEditorViewModel.providerIDs.count, "Duplicate provider id in providerOptions")
        #expect(Set(AssistantEditorViewModel.providerOptions.map(\.name)).count == AssistantEditorViewModel.providerOptions.count, "Duplicate provider display name in providerOptions")
        for option in AssistantEditorViewModel.providerOptions {
            #expect(!option.id.isEmpty, "Empty provider id in providerOptions")
            #expect(AgentBranding.normalizedID(option.id) == option.id, "Provider id \(option.id) is not normalized")
            #expect(!option.name.isEmpty, "Provider \(option.id) has no display name")
        }
        #expect(
            Set(AssistantEditorViewModel.providerIDs) == ["codex", "claude", "grok", "opencode", "lithos", "cursor", "antigravity"],
            "Provider list drifted from the pinned snapshot of the engine's supported provider names. There is no Swift-side shared source for supported_names, so update providerOptions here and re-check the engine's supported_names."
        )
    }

    @Test("Editing a definition without a stored record keeps the definition version in the draft")
    func editingDefinitionVersionPreservedWithoutStoredRecord() {
        var definition = Self.makeCustomDefinition()
        definition.version = 3
        let viewModel = AssistantEditorViewModel(editing: definition)
        #expect(viewModel.version == 3)
        #expect(viewModel.makeDraft().version == 3)
    }

    @Test("The editor's test-run handler accepts an AppModel directly and runs without a runtime")
    func testRunHandlerAcceptsAppModel() async {
        let model = AppModel()
        let handler = AssistantEditorView.testRunHandler(appModel: model)
        let view = AssistantEditorView(
            viewModel: AssistantEditorViewModel(),
            onSave: { _ in nil },
            onCancel: {},
            onTestRun: handler
        )
        #expect(view.onTestRun != nil)
        let assistant = RemoteAssistant(
            id: UUID(),
            name: "Wiring Check",
            category: .codeMaintenance,
            systemPrompt: "Check."
        )
        await handler(assistant, "Hello")
    }

    private final actor TestRunRecorder {
        private(set) var runs: [(assistantID: UUID, task: String)] = []

        func record(assistantID: UUID, task: String) {
            runs.append((assistantID: assistantID, task: task))
        }
    }

    @Test("An empty sample task explains that a task is needed before a live test run")
    func emptySampleTaskExplainsLiveTestNeedsTask() {
        let saved = RemoteAssistant(
            id: UUID(),
            name: "Saved Helper",
            category: .codeMaintenance,
            systemPrompt: "Do the job."
        )
        var view = AssistantEditorView(
            viewModel: AssistantEditorViewModel(),
            onSave: { _ in nil },
            onCancel: {},
            onTestRun: { _, _ in },
            savedAssistant: saved
        )
        #expect(view.liveTestUnavailableReason == "Enter a sample task to run the live test.")
        view.sampleTask = "   "
        #expect(view.liveTestUnavailableReason == "Enter a sample task to run the live test.")
        view.sampleTask = "Summarize the changes."
        #expect(view.liveTestUnavailableReason == nil)
    }

    @Test("Requesting a live test run notes that the last saved version runs and a new thread appears when the runtime starts it")
    func runTestNotesLastSavedVersionAndNewThread() async {
        let saved = RemoteAssistant(
            id: UUID(),
            name: "Saved Helper",
            category: .codeMaintenance,
            systemPrompt: "Do the job."
        )
        let recorder = TestRunRecorder()
        var view = AssistantEditorView(
            viewModel: AssistantEditorViewModel(),
            onSave: { _ in nil },
            onCancel: {},
            onTestRun: { assistant, task in await recorder.record(assistantID: assistant.id, task: task) },
            savedAssistant: saved
        )
        view.sampleTask = "Summarize the changes."
        await view.runTest()
        let runs = await recorder.runs
        #expect(runs.map(\.assistantID) == [saved.id])
        #expect(runs.map(\.task) == ["Summarize the changes."])
        #expect(view.testRunNote == "Test run requested using the last saved version of this assistant. A new thread appears when the runtime starts it.")
    }

    @Test("A new assistant defaults to an icon that is selectable in the icon grid")
    func newAssistantDefaultIconIsInGrid() {
        let viewModel = AssistantEditorViewModel()
        #expect(viewModel.icon == AssistantEditorViewModel.defaultIcon)
        #expect(AssistantEditorViewModel.iconOptions.contains(viewModel.icon))
    }

    @Test("Editing a definition with an empty icon falls back to a grid icon")
    func emptyIconFallsBackToGridIcon() {
        var definition = Self.makeCustomDefinition()
        definition.icon = ""
        let viewModel = AssistantEditorViewModel(editing: definition)
        #expect(viewModel.icon == AssistantEditorViewModel.defaultIcon)
        #expect(AssistantEditorViewModel.iconOptions.contains(viewModel.icon))
    }

    @Test("Customizing a built-in builds an override draft keyed by the preset persistence ID")
    func overrideDraftCreation() {
        let preset = Self.makePreset()
        let viewModel = AssistantEditorViewModel(editing: preset)
        viewModel.name = "My Customized Preset"
        let draft = viewModel.makeDraft()
        #expect(draft.source == .override)
        #expect(draft.id == preset.persistenceID)
        #expect(draft.name == "My Customized Preset")
        #expect(draft.version == preset.version)
        #expect(viewModel.isCustomizedBuiltIn == false)
        #expect(viewModel.overrideRecordToDelete == nil)
    }

    @Test("A customized built-in exposes its override record for restore-to-defaults")
    func restoreExposesOverrideRecord() {
        let preset = Self.makePreset()
        let override = Self.makeOverrideRecord(for: preset)
        let viewModel = AssistantEditorViewModel(editing: preset, stored: override)
        #expect(viewModel.isCustomizedBuiltIn)
        #expect(viewModel.overrideRecordToDelete == override)
        var catalog = AssistantCatalog(builtIns: [preset], stored: [override])
        #expect(catalog.customizedBuiltIns.map(\.id) == [preset.id])
        let restored = catalog.restoreDefaults(builtinID: preset.id)
        #expect(restored == preset)
        #expect(catalog.stored.isEmpty)
        #expect(catalog.customizedBuiltIns.isEmpty)
    }

    @Test("Editing a custom assistant keeps its stable ID, source, and version in the draft")
    func customDraftKeepsIdentity() {
        let definition = Self.makeCustomDefinition()
        let stored = RemoteAssistant(
            id: definition.persistenceID!,
            name: definition.name,
            category: .buildingFixing,
            systemPrompt: definition.systemPrompt,
            version: 3,
            source: .custom,
            isFavorite: true
        )
        let viewModel = AssistantEditorViewModel(editing: definition, stored: stored)
        let draft = viewModel.makeDraft()
        #expect(draft.source == .custom)
        #expect(draft.id == definition.persistenceID)
        #expect(draft.version == 3)
        #expect(draft.isFavorite)
        #expect(draft.provider == "claude")
        #expect(draft.model == "claude-sonnet-4")
    }

    @Test("The system prompt is stored verbatim, with whitespace and newlines untouched")
    func promptStoredVerbatim() {
        let viewModel = AssistantEditorViewModel()
        let prompt = "  Line one.\n\nLine two with trailing spaces.   \n\tTabbed line."
        viewModel.systemPrompt = prompt
        #expect(viewModel.makeDraft().systemPrompt == prompt)
        #expect(viewModel.testRunPreview.systemPrompt == prompt)
    }

    @Test("Input requirements can be added and removed up to the limit")
    func inputRequirementsAddRemove() {
        let viewModel = AssistantEditorViewModel()
        for index in 0..<AssistantDefinition.inputRequirementsLimit {
            viewModel.inputRequirements = (viewModel.inputRequirements ?? []) + ["Requirement \(index)"]
        }
        #expect(viewModel.inputRequirements?.count == AssistantDefinition.inputRequirementsLimit)
        viewModel.addInputRequirement()
        #expect(viewModel.inputRequirements?.count == AssistantDefinition.inputRequirementsLimit)
        viewModel.removeInputRequirement(at: 0)
        #expect(viewModel.inputRequirements?.count == AssistantDefinition.inputRequirementsLimit - 1)
        viewModel.addInputRequirement()
        #expect(viewModel.inputRequirements?.count == AssistantDefinition.inputRequirementsLimit)
    }

    @Test("Intended tasks can be added and removed up to the limit")
    func intendedTasksAddRemove() {
        let viewModel = AssistantEditorViewModel()
        viewModel.addIntendedTask()
        #expect(viewModel.intendedTasks.count == 1)
        viewModel.removeIntendedTask(at: 0)
        #expect(viewModel.intendedTasks.isEmpty)
    }

    @Test("Widening the permission profile states its consequence; read-only states none")
    func permissionConsequences() {
        let viewModel = AssistantEditorViewModel()
        #expect(viewModel.permissionConsequence == nil)
        viewModel.permissionProfile = .workspaceModify
        #expect(viewModel.permissionConsequence?.contains("create, edit, and delete files") == true)
        viewModel.permissionProfile = .terminal
        #expect(viewModel.permissionConsequence?.contains("terminal commands") == true)
        viewModel.permissionProfile = .approvalRequired
        #expect(viewModel.permissionConsequence?.contains("approval") == true)
    }

    @Test("The test-run preview resolves provider, model, tools, and the verbatim prompt")
    func testRunPreviewResolvesConfig() {
        let viewModel = AssistantEditorViewModel()
        viewModel.name = "Preview Helper"
        viewModel.systemPrompt = "Do the job."
        viewModel.setModelMode(.specific)
        viewModel.provider = "claude"
        viewModel.model = "claude-sonnet-4"
        viewModel.setCapability(.terminal, enabled: true)
        let preview = viewModel.testRunPreview
        #expect(preview.providerDescription == "Claude")
        #expect(preview.modelDescription == "claude-sonnet-4")
        #expect(preview.systemPrompt == "Do the job.")
        #expect(preview.toolsDescription.contains("create_terminal"))
        #expect(preview.permissionDescription == "Read-only")
        #expect(preview.toolsetNote.contains("System Tools"))
    }

    @Test("Every icon option is an icon already used by a built-in assistant")
    func iconOptionsAreRealPresetIcons() {
        let presetIcons = Set(BuiltInPresets.all.map(\.icon))
        #expect(!AssistantEditorViewModel.iconOptions.isEmpty)
        for icon in AssistantEditorViewModel.iconOptions {
            #expect(presetIcons.contains(icon), "Icon option \(icon) is not used by any built-in assistant")
        }
    }
}
