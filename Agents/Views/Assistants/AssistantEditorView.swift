import CoincideRemoteKit
import SwiftUI

public struct AssistantEditorView: View {
    @Bindable public var viewModel: AssistantEditorViewModel
    public var onSave: (RemoteAssistantDraft) async -> UUID?
    public var onCancel: () -> Void
    public var onTestRun: ((RemoteAssistant, String) async -> Void)?
    public var savedAssistant: RemoteAssistant?
    public var onRestoreDefaults: ((RemoteAssistant) async -> Void)?

    @State private var isSaving: Bool = false
    @State private var isRestoring: Bool = false
    @State private var showRestoreConfirmation: Bool = false
    @State var sampleTask: String = ""
    @State var testRunNote: String? = nil
    @State private var showTestPreview: Bool = false
    @State private var newIntendedTask: String = ""
    @State private var newInputRequirement: String = ""

    public init(
        viewModel: AssistantEditorViewModel,
        onSave: @escaping (RemoteAssistantDraft) async -> UUID?,
        onCancel: @escaping () -> Void,
        onTestRun: ((RemoteAssistant, String) async -> Void)? = nil,
        savedAssistant: RemoteAssistant? = nil,
        onRestoreDefaults: ((RemoteAssistant) async -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onSave = onSave
        self.onCancel = onCancel
        self.onTestRun = onTestRun
        self.savedAssistant = savedAssistant
        self.onRestoreDefaults = onRestoreDefaults
    }

    public static func testRunHandler(appModel: AppModel) -> (RemoteAssistant, String) async -> Void {
        { assistant, task in await appModel.launchAssistant(assistant, task: task) }
    }

    private var issues: [AssistantValidationIssue] {
        viewModel.validationIssues
    }

    private var headerTint: Color {
        if let provider = viewModel.modelConfig.provider {
            return AgentBranding.color(for: provider)
        }
        return AppTheme.accent
    }

    private var canRunLiveTest: Bool {
        savedAssistant != nil && onTestRun != nil
            && !sampleTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var liveTestUnavailableReason: String? {
        if savedAssistant == nil {
            return "Save the assistant first. A live test run launches the saved assistant, so there is nothing to run until it exists."
        }
        if onTestRun == nil {
            return "Live test runs are not wired in this context."
        }
        if sampleTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a sample task to run the live test."
        }
        return nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identityCard
                    promptCard
                    capabilitiesCard
                    modelCard
                    permissionsCard
                    outputCard
                    testRunCard
                }
                .padding(20)
            }

            Divider()

            footerBar
        }
        .frame(minWidth: 580, idealWidth: 640, maxWidth: 720, minHeight: 560, idealHeight: 720, maxHeight: 860)
        .background(AppTheme.windowBackground)
        .confirmationDialog(
            "Restore Defaults?",
            isPresented: $showRestoreConfirmation,
            presenting: viewModel.overrideRecordToDelete
        ) { record in
            Button("Restore Defaults", role: .destructive) {
                Task { await restoreDefaults(record) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { record in
            Text("“\(record.name)” returns to the built-in preset. Your customized version is deleted.")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(headerTint.opacity(0.16))
                    .frame(width: 64, height: 64)
                Circle()
                    .strokeBorder(headerTint.opacity(0.35), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: viewModel.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(headerTint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Assistant" : viewModel.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)

                    Text(viewModel.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.elevatedCardFill, in: Capsule())
                }

                Text(viewModel.category.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)

                if viewModel.preset != nil {
                    Text("Customizing a built-in preset creates your own override. The preset itself is never changed.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(AppTheme.elevatedCardFill)
    }

    private var identityCard: some View {
        editorSectionCard(title: "Identity", symbol: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Name")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                        Text("\(viewModel.name.unicodeScalars.count)/\(AssistantDefinition.nameLimit)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    TextField("Assistant Name", text: $viewModel.name)
                        .textFieldStyle(.roundedBorder)
                    if issues.contains(.emptyName) {
                        inlineError(AssistantValidationIssue.emptyName.userMessage)
                    }
                    if issues.contains(.nameTooLong) {
                        inlineError(AssistantValidationIssue.nameTooLong.userMessage)
                    }
                    if issues.contains(.nameHasControlCharacters) {
                        inlineError(AssistantValidationIssue.nameHasControlCharacters.userMessage)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Description")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                        Text("\(viewModel.description.unicodeScalars.count)/\(AssistantDefinition.descriptionLimit)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    TextField("What this assistant does", text: $viewModel.description)
                        .textFieldStyle(.roundedBorder)
                    if issues.contains(.descriptionTooLong) {
                        inlineError(AssistantValidationIssue.descriptionTooLong.userMessage)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Category")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Picker("Category", selection: $viewModel.category) {
                        ForEach(AssistantCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Icon")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 6)], spacing: 6) {
                        ForEach(AssistantEditorViewModel.iconOptions, id: \.self) { symbol in
                            let isSelected = viewModel.icon == symbol
                            Button {
                                viewModel.icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isSelected ? headerTint : AppTheme.secondaryLabel)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                            .fill(isSelected ? headerTint.opacity(0.16) : AppTheme.controlBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                            .strokeBorder(isSelected ? headerTint : AppTheme.separator, lineWidth: isSelected ? 2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(symbol)
                            .accessibilityLabel("Icon \(symbol)")
                        }
                    }
                    Text("Every icon here is already used by a built-in assistant. The header tint follows the chosen provider's color in the app palette; no color is stored with the assistant.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }
        }
    }

    private var promptCard: some View {
        editorSectionCard(title: "System Prompt", symbol: "doc.text") {
            AssistantPromptEditorView(text: $viewModel.systemPrompt)
            if issues.contains(.emptySystemPrompt) {
                inlineError(AssistantValidationIssue.emptySystemPrompt.userMessage)
            }
            if issues.contains(.systemPromptTooLong) {
                inlineError(AssistantValidationIssue.systemPromptTooLong.userMessage)
            }
        }
    }

    private var capabilitiesCard: some View {
        editorSectionCard(title: "Capabilities", symbol: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.testRunPreview.toolsetNote)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(AssistantCapability.allCases, id: \.self) { capability in
                    Toggle(isOn: Binding(
                        get: { viewModel.isCapabilityEnabled(capability) },
                        set: { viewModel.setCapability(capability, enabled: $0) }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: capability.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(capability.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                Text(capability.detail)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                }

                Text(capabilitySummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                ForEach(issues.filter { issue in
                    if case .unknownTool = issue { return true }
                    if case .duplicateToolName = issue { return true }
                    if case .emptyToolName = issue { return true }
                    return false
                }, id: \.self) { issue in
                    inlineError(issue.userMessage)
                }
            }
        }
    }

    private var capabilitySummary: String {
        if let tools = viewModel.allowedTools {
            if tools.isEmpty {
                return "No tools enabled. The assistant can answer from its instructions only."
            }
            return "\(tools.count) tools enabled."
        }
        return "No tool restriction. The assistant can use all \(SystemToolRegistry.systemTools.count) system tools."
    }

    private var modelCard: some View {
        editorSectionCard(title: "Model", symbol: "cpu") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Model", selection: Binding(
                    get: { viewModel.modelMode },
                    set: { viewModel.setModelMode($0) }
                )) {
                    ForEach(AssistantModelMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()

                Text(viewModel.modelMode.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.modelMode == .specific || viewModel.modelMode == .providerOnly {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Provider")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Picker("Provider", selection: $viewModel.provider) {
                            ForEach(AssistantEditorViewModel.providerOptions, id: \.id) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        .labelsHidden()
                    }
                }

                if viewModel.modelMode == .specific || viewModel.modelMode == .modelOnly {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Model ID")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.secondaryLabel)
                            Spacer()
                            Text("\(viewModel.model.unicodeScalars.count)/\(AssistantDefinition.modelLimit)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                        }
                        TextField("Model ID", text: $viewModel.model)
                            .textFieldStyle(.roundedBorder)
                        if issues.contains(.emptyModel) {
                            inlineError(AssistantValidationIssue.emptyModel.userMessage)
                        }
                        if issues.contains(.modelTooLong) {
                            inlineError(AssistantValidationIssue.modelTooLong.userMessage)
                        }
                    }
                }
            }
        }
    }

    private var permissionsCard: some View {
        editorSectionCard(title: "Permissions", symbol: "lock.shield") {
            VStack(alignment: .leading, spacing: 12) {
                Text("New assistants start read-only. Choose a wider profile only when the assistant needs it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Permissions", selection: $viewModel.permissionProfile) {
                    Text("Read-only").tag(AssistantPermissionProfile.readOnly)
                    Text("Workspace modify").tag(AssistantPermissionProfile.workspaceModify)
                    Text("Terminal").tag(AssistantPermissionProfile.terminal)
                    Text("Approval required").tag(AssistantPermissionProfile.approvalRequired)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)

                if let consequence = viewModel.permissionConsequence {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.warning)
                            .padding(.top, 1)
                        Text(consequence)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .strokeBorder(AppTheme.warning.opacity(0.4), lineWidth: 1)
                    )
                }
            }
        }
    }

    private var outputCard: some View {
        editorSectionCard(title: "Output & Input Requirements", symbol: "list.clipboard") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Expected output format")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                        Text("\(viewModel.expectedOutputFormat.unicodeScalars.count)/\(AssistantDefinition.outputFormatLimit)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    TextEditor(text: $viewModel.expectedOutputFormat)
                        .font(.system(size: 12.5))
                        .frame(minHeight: 56, maxHeight: 96)
                        .padding(6)
                        .background(AppTheme.textBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                .strokeBorder(AppTheme.separator, lineWidth: 1)
                        )
                    if issues.contains(.expectedOutputFormatTooLong) {
                        inlineError(AssistantValidationIssue.expectedOutputFormatTooLong.userMessage)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Intended tasks")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                        Text("\(viewModel.intendedTasks.count)/\(AssistantDefinition.intendedTasksLimit)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    ForEach(viewModel.intendedTasks.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            TextField("Task the assistant should handle", text: $viewModel.intendedTasks[index])
                                .textFieldStyle(.roundedBorder)
                            Button {
                                viewModel.removeIntendedTask(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove intended task \(index + 1)")
                        }
                    }
                    if issues.contains(.tooManyIntendedTasks) {
                        inlineError(AssistantValidationIssue.tooManyIntendedTasks.userMessage)
                    }
                    HStack(spacing: 8) {
                        TextField("Add an intended task", text: $newIntendedTask)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addIntendedTaskFromField() }
                        Button("Add") {
                            addIntendedTaskFromField()
                        }
                        .disabled(
                            newIntendedTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || viewModel.intendedTasks.count >= AssistantDefinition.intendedTasksLimit
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Input requirements")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                        Text("\((viewModel.inputRequirements ?? []).count)/\(AssistantDefinition.inputRequirementsLimit)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    Text("What the user must provide before this assistant can do its job.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    ForEach((viewModel.inputRequirements ?? []).indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            TextField("Required input", text: Binding(
                                get: { viewModel.inputRequirements?[index] ?? "" },
                                set: { viewModel.inputRequirements?[index] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            Button {
                                viewModel.removeInputRequirement(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove input requirement \(index + 1)")
                        }
                    }
                    if issues.contains(.tooManyInputRequirements) {
                        inlineError(AssistantValidationIssue.tooManyInputRequirements.userMessage)
                    }
                    HStack(spacing: 8) {
                        TextField("Add an input requirement", text: $newInputRequirement)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addInputRequirementFromField() }
                        Button("Add") {
                            addInputRequirementFromField()
                        }
                        .disabled(
                            newInputRequirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || (viewModel.inputRequirements ?? []).count >= AssistantDefinition.inputRequirementsLimit
                        )
                    }
                }
            }
        }
    }

    private var testRunCard: some View {
        editorSectionCard(title: "Test Run", symbol: "play.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Run this assistant on a sample task in a real thread, or preview exactly what a run would use.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Sample task")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    TextField("A short task to try the assistant on", text: $sampleTask)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Button(showTestPreview ? "Hide Preview" : "Preview Test Run") {
                        showTestPreview.toggle()
                    }
                    .controlSize(.small)

                    Spacer()

                    Button("Run Live Test") {
                        Task { await runTest() }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRunLiveTest || isSaving)
                }

                if let reason = liveTestUnavailableReason {
                    Text(reason)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                } else if savedAssistant != nil {
                    Text("Runs the last saved version of this assistant. Unsaved edits are not included in the run.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let note = testRunNote {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.top, 1)
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if showTestPreview {
                    testRunPreviewBody
                }
            }
        }
    }

    private var testRunPreviewBody: some View {
        let preview = viewModel.testRunPreview
        return VStack(alignment: .leading, spacing: 8) {
            previewRow(label: "Provider", value: preview.providerDescription)
            previewRow(label: "Model", value: preview.modelDescription)
            previewRow(label: "Permissions", value: preview.permissionDescription)
            previewRow(label: "Tools", value: preview.toolsDescription)
            Text(preview.toolsetNote)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            Text("The runtime composes the final instructions internally.")
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.primaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = viewModel.saveDisabledReason {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                        .padding(.top, 1)
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
            }

            HStack(spacing: 10) {
                if viewModel.isCustomizedBuiltIn, onRestoreDefaults != nil {
                    Button("Restore Defaults…") {
                        showRestoreConfirmation = true
                    }
                    .disabled(isSaving || isRestoring)
                }

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving || isRestoring)

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Saving…")
                        }
                    } else {
                        Text(viewModel.preset != nil ? "Save Customization" : viewModel.editingDefinition != nil ? "Save Assistant" : "Create Assistant")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isValid || isSaving || isRestoring)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func editorSectionCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.primaryLabel)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func inlineError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.danger)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addIntendedTaskFromField() {
        let trimmed = newIntendedTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, viewModel.intendedTasks.count < AssistantDefinition.intendedTasksLimit else { return }
        viewModel.intendedTasks.append(trimmed)
        newIntendedTask = ""
    }

    private func addInputRequirementFromField() {
        let trimmed = newInputRequirement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, (viewModel.inputRequirements ?? []).count < AssistantDefinition.inputRequirementsLimit else { return }
        viewModel.inputRequirements = (viewModel.inputRequirements ?? []) + [trimmed]
        newInputRequirement = ""
    }

    private func save() async {
        guard viewModel.isValid else { return }
        isSaving = true
        defer { isSaving = false }
        let draft = viewModel.makeDraft()
        if await onSave(draft) != nil {
            onCancel()
        }
    }

    func runTest() async {
        guard let assistant = savedAssistant, let onTestRun else { return }
        let task = sampleTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        testRunNote = nil
        await onTestRun(assistant, task)
        testRunNote = "Test run requested using the last saved version of this assistant. A new thread appears when the runtime starts it."
    }

    private func restoreDefaults(_ record: RemoteAssistant) async {
        guard let onRestoreDefaults else { return }
        isRestoring = true
        defer { isRestoring = false }
        await onRestoreDefaults(record)
        onCancel()
    }
}
