import CoincideRemoteKit
import Foundation
import Observation

public enum AssistantCapability: String, CaseIterable, Sendable {
    case fileRead
    case fileEdit
    case search
    case terminal
    case git
    case repoAnalysis
    case codeExecution

    public var title: String {
        switch self {
        case .fileRead: return "Read files"
        case .fileEdit: return "Edit files"
        case .search: return "Search"
        case .terminal: return "Terminal"
        case .git: return "Git"
        case .repoAnalysis: return "Repository analysis"
        case .codeExecution: return "Run builds and tests"
        }
    }

    public var detail: String {
        switch self {
        case .fileRead: return "Read and list files in the workspace."
        case .fileEdit: return "Create, edit, move, and delete files in the workspace."
        case .search: return "Search file contents with text and regular expressions."
        case .terminal: return "Run commands in an integrated terminal."
        case .git: return "Inspect history and diffs, and commit, push, pull, and manage branches."
        case .repoAnalysis: return "Map the project structure, dependencies, symbols, and recent changes."
        case .codeExecution: return "Run builds and test suites in the workspace."
        }
    }

    public var symbol: String {
        switch self {
        case .fileRead: return "doc.text"
        case .fileEdit: return "square.and.pencil"
        case .search: return "magnifyingglass"
        case .terminal: return "terminal"
        case .git: return "arrow.triangle.branch"
        case .repoAnalysis: return "map"
        case .codeExecution: return "hammer"
        }
    }

    public var tools: [String] {
        switch self {
        case .fileRead:
            return ["read_file", "list_files", "read_directory"]
        case .fileEdit:
            return [
                "write_file", "edit_file", "multi_edit_file", "create_directory",
                "delete_file", "delete_directory", "move_file", "copy_file",
            ]
        case .search:
            return ["search_files", "search_regex"]
        case .terminal:
            return ["create_terminal", "write_terminal", "read_terminal", "use_terminal", "run_command"]
        case .git:
            return [
                "git_status", "git_diff", "git_log", "git_show", "git_diff_range", "git_diff_branch",
                "git_commit", "git_push", "git_pull", "git_branch_list", "git_branch_create",
                "git_branch_checkout",
            ]
        case .repoAnalysis:
            return [
                "repo_overview", "project_structure_map", "dependency_graph", "search_symbol",
                "recent_changes", "file_type_breakdown", "code_summary",
            ]
        case .codeExecution:
            return ["run_build", "run_tests", "project_build", "project_test"]
        }
    }
}

public enum AssistantModelMode: String, CaseIterable, Sendable {
    case appDefault
    case specific
    case providerOnly
    case modelOnly
    case currentAppModel

    public var title: String {
        switch self {
        case .appDefault: return "App default"
        case .specific: return "Specific provider and model"
        case .providerOnly: return "Specific provider, any model"
        case .modelOnly: return "Specific model, any provider"
        case .currentAppModel: return "Current app model"
        }
    }

    public var detail: String {
        switch self {
        case .appDefault:
            return "Uses whatever the app would use with no assistant override."
        case .specific:
            return "Always launches with this provider and model."
        case .providerOnly:
            return "Always launches with this provider and its default model."
        case .modelOnly:
            return "Always launches with this model ID on the app's provider."
        case .currentAppModel:
            return "Uses the provider and model the app currently has selected, resolved when the assistant launches."
        }
    }
}

public struct AssistantTestRunPreview: Hashable, Sendable {
    public var systemPrompt: String
    public var providerDescription: String
    public var modelDescription: String
    public var toolsDescription: String
    public var permissionDescription: String
    public var toolsetNote: String

    public init(
        systemPrompt: String, providerDescription: String, modelDescription: String,
        toolsDescription: String, permissionDescription: String, toolsetNote: String
    ) {
        self.systemPrompt = systemPrompt
        self.providerDescription = providerDescription
        self.modelDescription = modelDescription
        self.toolsDescription = toolsDescription
        self.permissionDescription = permissionDescription
        self.toolsetNote = toolsetNote
    }
}

public extension AssistantValidationIssue {
    var userMessage: String {
        switch self {
        case .emptyName:
            return "Enter a name for the assistant."
        case .nameTooLong:
            return "The name is longer than \(AssistantDefinition.nameLimit) characters."
        case .nameHasControlCharacters:
            return "The name contains control characters."
        case .descriptionTooLong:
            return "The description is longer than \(AssistantDefinition.descriptionLimit) characters."
        case .descriptionHasNUL:
            return "The description contains a NUL character."
        case .iconTooLong:
            return "The icon name is longer than \(AssistantDefinition.iconLimit) characters."
        case .iconHasControlCharacters:
            return "The icon name contains control characters."
        case .emptySystemPrompt:
            return "Enter the system prompt: the instructions the assistant will follow."
        case .systemPromptTooLong:
            return "The system prompt is longer than \(AssistantDefinition.systemPromptLimit) characters."
        case .systemPromptHasNUL:
            return "The system prompt contains a NUL character."
        case .emptyModel:
            return "Enter a model ID."
        case .modelTooLong:
            return "The model ID is longer than \(AssistantDefinition.modelLimit) characters."
        case .tooManyIntendedTasks:
            return "There are more than \(AssistantDefinition.intendedTasksLimit) intended tasks."
        case .intendedTaskTooLong(let index):
            return "Intended task \(index + 1) is longer than \(AssistantDefinition.intendedTaskLimit) characters."
        case .intendedTaskHasNUL(let index):
            return "Intended task \(index + 1) contains a NUL character."
        case .expectedOutputFormatTooLong:
            return "The expected output format is longer than \(AssistantDefinition.outputFormatLimit) characters."
        case .expectedOutputFormatHasNUL:
            return "The expected output format contains a NUL character."
        case .emptyToolName:
            return "A tool name is empty."
        case .toolNameTooLong(let name):
            return "The tool name “\(name)” is longer than \(AssistantDefinition.toolNameLimit) characters."
        case .toolNameHasControlCharacters(let name):
            return "The tool name “\(name)” contains control characters."
        case .duplicateToolName(let name):
            return "The tool “\(name)” is listed more than once."
        case .unknownTool(let name):
            return "“\(name)” is not a tool in the system tool registry."
        case .tooManyInputRequirements:
            return "There are more than \(AssistantDefinition.inputRequirementsLimit) input requirements."
        case .inputRequirementTooLong(let index):
            return "Input requirement \(index + 1) is longer than \(AssistantDefinition.inputRequirementLimit) characters."
        case .inputRequirementHasNUL(let index):
            return "Input requirement \(index + 1) contains a NUL character."
        case .versionTooLow:
            return "The assistant version is below 1."
        case .invalidStableID:
            return "The assistant ID is not a valid stable ID."
        }
    }
}

@Observable
@MainActor
public final class AssistantEditorViewModel {
    public static let providerOptions: [(id: String, name: String)] = [
        (id: "codex", name: "Codex"),
        (id: "claude", name: "Claude"),
        (id: "grok", name: "Grok"),
        (id: "opencode", name: "OpenCode"),
        (id: "lithos", name: "Lithos"),
        (id: "cursor", name: "Cursor"),
        (id: "antigravity", name: "Antigravity"),
    ]

    public static let providerIDs: [String] = providerOptions.map(\.id)

    public static let iconOptions: [String] = [
        "accessibility", "arrow.triangle.2.circlepath", "arrow.triangle.branch", "arrow.triangle.merge",
        "book.pages", "bubble.left.and.bubble.right", "bug.fill", "building.columns", "chart.bar",
        "checkmark.circle", "checkmark.seal.fill", "clock.arrow.circlepath", "curlybraces",
        "cylinder.fill", "cylinder.split.1x2", "doc.on.doc", "doc.richtext", "doc.text",
        "doc.text.magnifyingglass", "exclamationmark.octagon", "exclamationmark.triangle",
        "gauge.with.needle", "globe", "hammer", "heart.text.square", "ladybug", "link",
        "list.clipboard", "lock.shield", "macwindow", "magnifyingglass", "map", "memorychip",
        "network", "paintbrush", "pencil.line", "point.3.connected.trianglepath",
        "questionmark.circle", "rectangle.3.group", "scissors", "shield", "shippingbox",
        "square.stack.3d.up", "swift", "tag", "text.bubble", "textformat", "trash", "tray",
        "wrench.and.screwdriver", "xmark.circle",
    ]

    public static let defaultCapabilities: [AssistantCapability] = [.fileRead, .search, .repoAnalysis]

    public var name: String
    public var description: String
    public var icon: String
    public var category: AssistantCategory
    public var systemPrompt: String
    public var intendedTasks: [String]
    public var expectedOutputFormat: String
    public var allowedTools: [String]?
    public var modelMode: AssistantModelMode
    public var provider: String
    public var model: String
    public var permissionProfile: AssistantPermissionProfile
    public var inputRequirements: [String]?
    public let currentToolset: AgentToolset

    public let editingDefinition: AssistantDefinition?
    public let storedRecord: RemoteAssistant?
    public let preset: AssistantDefinition?

    private let newCustomID: UUID

    public init() {
        self.name = ""
        self.description = ""
        self.icon = "sparkles"
        self.category = .codeMaintenance
        self.systemPrompt = ""
        self.intendedTasks = []
        self.expectedOutputFormat = ""
        self.allowedTools = Self.defaultCapabilities.flatMap(\.tools).sorted()
        self.modelMode = .appDefault
        self.provider = ""
        self.model = ""
        self.permissionProfile = .readOnly
        self.inputRequirements = nil
        self.currentToolset = AgentToolset.load()
        self.editingDefinition = nil
        self.storedRecord = nil
        self.preset = nil
        self.newCustomID = UUID()
    }

    public init(editing definition: AssistantDefinition, stored: RemoteAssistant? = nil) {
        self.name = definition.name
        self.description = definition.description
        self.icon = definition.icon.isEmpty ? "sparkles" : definition.icon
        self.category = definition.category
        self.systemPrompt = definition.systemPrompt
        self.intendedTasks = definition.intendedTasks
        self.expectedOutputFormat = definition.expectedOutputFormat
        self.allowedTools = definition.allowedTools
        self.provider = definition.modelConfig.provider ?? ""
        self.model = definition.modelConfig.model ?? ""
        self.permissionProfile = definition.permissionProfile
        self.inputRequirements = definition.inputRequirements
        self.currentToolset = AgentToolset.load()
        self.editingDefinition = definition
        self.storedRecord = stored
        self.preset = definition.isBuiltIn ? definition : nil
        self.newCustomID = definition.persistenceID ?? UUID()
        switch definition.modelConfig {
        case .appDefault:
            self.modelMode = .appDefault
        case .specific:
            self.modelMode = .specific
        case .providerOnly:
            self.modelMode = .providerOnly
        case .modelOnly:
            self.modelMode = .modelOnly
        case .currentAppModel:
            self.modelMode = .currentAppModel
        }
    }

    public var title: String {
        if preset != nil {
            return "Customize Assistant"
        }
        if editingDefinition != nil {
            return "Edit Assistant"
        }
        return "New Assistant"
    }

    public var isCustomizedBuiltIn: Bool {
        preset != nil && storedRecord?.source == .override
    }

    public var overrideRecordToDelete: RemoteAssistant? {
        isCustomizedBuiltIn ? storedRecord : nil
    }

    public var version: Int {
        storedRecord?.version ?? preset?.version ?? 1
    }

    public var stableID: String {
        if let preset {
            return preset.id
        }
        if let editingDefinition {
            return editingDefinition.id
        }
        return AssistantDefinition.customID(newCustomID)
    }

    public var draftPersistenceID: UUID {
        preset?.persistenceID ?? storedRecord?.id ?? newCustomID
    }

    public var modelConfig: AssistantModelConfig {
        switch modelMode {
        case .appDefault:
            return .appDefault
        case .specific:
            return .specific(provider: provider, model: model)
        case .providerOnly:
            return .providerOnly(provider)
        case .modelOnly:
            return .modelOnly(model)
        case .currentAppModel:
            return .currentAppModel
        }
    }

    public var currentDefinition: AssistantDefinition {
        AssistantDefinition(
            id: stableID,
            name: name,
            description: description,
            category: category,
            icon: icon,
            systemPrompt: systemPrompt,
            intendedTasks: intendedTasks,
            expectedOutputFormat: expectedOutputFormat,
            allowedTools: allowedTools,
            modelConfig: modelConfig,
            permissionProfile: permissionProfile,
            inputRequirements: inputRequirements,
            version: version,
            isBuiltIn: preset != nil,
            customized: isCustomizedBuiltIn
        )
    }

    public var validationIssues: [AssistantValidationIssue] {
        currentDefinition.validationIssues()
    }

    public var isValid: Bool {
        validationIssues.isEmpty
    }

    public var saveDisabledReason: String? {
        validationIssues.first?.userMessage
    }

    public var permissionConsequence: String? {
        switch permissionProfile {
        case .readOnly:
            return nil
        case .workspaceModify:
            return "The assistant can create, edit, and delete files in the workspace."
        case .terminal:
            return "The assistant can run terminal commands. A command can change files, install software, and reach the network."
        case .approvalRequired:
            return "The assistant asks for approval before acting."
        }
    }

    public var effectiveAllowedTools: [String] {
        allowedTools ?? SystemToolRegistry.systemTools.map(\.name)
    }

    public func isCapabilityEnabled(_ capability: AssistantCapability) -> Bool {
        guard let tools = allowedTools else {
            return true
        }
        let enabled = Set(tools)
        return capability.tools.allSatisfy(enabled.contains)
    }

    public func setCapability(_ capability: AssistantCapability, enabled: Bool) {
        var tools = Set(effectiveAllowedTools)
        if enabled {
            tools.formUnion(capability.tools)
        } else {
            tools.subtract(capability.tools)
        }
        allowedTools = tools.sorted()
    }

    public func setModelMode(_ mode: AssistantModelMode) {
        modelMode = mode
        if (mode == .specific || mode == .providerOnly) && provider.isEmpty {
            provider = Self.providerIDs[0]
        }
    }

    public func addIntendedTask() {
        guard intendedTasks.count < AssistantDefinition.intendedTasksLimit else { return }
        intendedTasks.append("")
    }

    public func removeIntendedTask(at index: Int) {
        guard intendedTasks.indices.contains(index) else { return }
        intendedTasks.remove(at: index)
    }

    public func addInputRequirement() {
        let current = inputRequirements ?? []
        guard current.count < AssistantDefinition.inputRequirementsLimit else { return }
        inputRequirements = current + [""]
    }

    public func removeInputRequirement(at index: Int) {
        guard var current = inputRequirements, current.indices.contains(index) else { return }
        current.remove(at: index)
        inputRequirements = current.isEmpty ? nil : current
    }

    public func makeDraft() -> RemoteAssistantDraft {
        RemoteAssistantDraft(
            id: draftPersistenceID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description,
            icon: icon,
            category: category.remote,
            systemPrompt: systemPrompt,
            intendedTasks: intendedTasks,
            expectedOutputFormat: expectedOutputFormat,
            allowedTools: allowedTools,
            provider: modelConfig.provider,
            model: modelConfig.model,
            permissionProfile: permissionProfile.remote,
            inputRequirements: inputRequirements,
            version: version,
            source: preset == nil ? .custom : .override,
            isFavorite: storedRecord?.isFavorite ?? false
        )
    }

    public var testRunPreview: AssistantTestRunPreview {
        let providerDescription: String
        let modelDescription: String
        switch modelConfig {
        case .appDefault:
            providerDescription = "App default"
            modelDescription = "App default"
        case .specific(let provider, let model):
            providerDescription = Self.providerOptions.first(where: { $0.id == provider })?.name ?? provider
            modelDescription = model
        case .providerOnly(let provider):
            providerDescription = Self.providerOptions.first(where: { $0.id == provider })?.name ?? provider
            modelDescription = "Provider default"
        case .modelOnly(let model):
            providerDescription = "App default"
            modelDescription = model
        case .currentAppModel:
            providerDescription = "Current app selection, resolved at launch"
            modelDescription = "Current app selection, resolved at launch"
        }
        let toolsDescription: String
        if let tools = allowedTools {
            toolsDescription = "\(tools.count) tools: \(tools.joined(separator: ", "))"
        } else {
            toolsDescription = "All \(SystemToolRegistry.systemTools.count) system tools, no restriction"
        }
        let permissionDescription: String
        switch permissionProfile {
        case .readOnly: permissionDescription = "Read-only"
        case .workspaceModify: permissionDescription = "Workspace modify"
        case .terminal: permissionDescription = "Terminal"
        case .approvalRequired: permissionDescription = "Approval required"
        }
        return AssistantTestRunPreview(
            systemPrompt: systemPrompt,
            providerDescription: providerDescription,
            modelDescription: modelDescription,
            toolsDescription: toolsDescription,
            permissionDescription: permissionDescription,
            toolsetNote: "Assistant launches always run under the System Tools toolset. The Assist toolset setting is currently \(currentToolset.title); a test run uses System Tools regardless, so these capability toggles apply."
        )
    }
}
