import AppKit
import CoincideRemoteKit
import SwiftUI

public struct AssistantLaunchView: View {
    public let assistant: AssistantDefinition
    public let appModel: AppModel
    public let onLaunch: (UUID) -> Void

    @StateObject private var viewModel: AssistantLaunchViewModel
    @Environment(\.dismiss) private var dismiss

    public init(
        assistant: AssistantDefinition,
        appModel: AppModel,
        onLaunch: @escaping (UUID) -> Void = { _ in }
    ) {
        self.assistant = assistant
        self.appModel = appModel
        self.onLaunch = onLaunch
        self._viewModel = StateObject(wrappedValue: AssistantLaunchViewModel(
            assistant: assistant,
            projectID: appModel.selectedProject?.id,
            branches: appModel.activeCheckout?.branches ?? [],
            launcher: AssistantLaunchViewModel.appModelLauncher(appModel: appModel)
        ))
    }

    private var modelDescription: String {
        let config = assistant.modelConfig
        switch (config.provider, config.model) {
        case let (provider?, model?):
            return "\(provider) · \(model)"
        case let (provider?, nil):
            return provider
        case let (nil, model?):
            return model
        case (nil, nil):
            return "App default model"
        }
    }

    private var workspaceDescription: String {
        guard let project = appModel.selectedProject else {
            return "No project selected"
        }
        return project.path.isEmpty ? project.name : "\(project.name) — \(project.path)"
    }

    public var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    workspaceCard
                    taskCard(viewModel: viewModel)
                    ForEach($viewModel.fields) { $field in
                        fieldCard(field: $field)
                    }
                    extraInstructionsCard(viewModel: viewModel)
                    if let error = viewModel.wrappedValue.launchError {
                        statusCard(text: error, systemImage: "xmark.octagon.fill", isError: true)
                    }
                    if let threadID = viewModel.wrappedValue.launchedThreadID {
                        statusCard(
                            text: "Launched conversation \(threadID.uuidString)",
                            systemImage: "checkmark.circle.fill",
                            isError: false
                        )
                    }
                }
                .padding(16)
            }
            .disabled(viewModel.wrappedValue.isLaunching)
            footerBar(viewModel: viewModel)
        }
        .frame(minWidth: 560, idealWidth: 620, maxWidth: 700, minHeight: 520, idealHeight: 640, maxHeight: 760)
        .onChange(of: appModel.activeCheckout?.branches ?? []) { _, newValue in
            viewModel.wrappedValue.updateBranches(newValue)
        }
        .onChange(of: viewModel.wrappedValue.launchedThreadID) { _, newValue in
            if let newValue {
                onLaunch(newValue)
            }
        }
    }

    private var headerCard: some View {
        sectionCard(title: assistant.name, symbol: assistant.icon.isEmpty ? "sparkles" : assistant.icon) {
            VStack(alignment: .leading, spacing: 4) {
                if !assistant.description.isEmpty {
                    Text(assistant.description)
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                HStack(spacing: 8) {
                    Text(assistant.category.displayName)
                    Text("·")
                    Text(modelDescription)
                    Text("·")
                    Text(assistant.permissionProfile.rawValue)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.tertiaryLabel)
                if !assistant.intendedTasks.isEmpty {
                    Text(assistant.intendedTasks.joined(separator: " · "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                }
            }
        }
    }

    private var workspaceCard: some View {
        sectionCard(title: "Workspace", symbol: "folder") {
            Text(workspaceDescription)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.secondaryLabel)
                .textSelection(.enabled)
        }
    }

    private func taskCard(viewModel: Bindable<AssistantLaunchViewModel>) -> some View {
        sectionCard(title: "Task", symbol: "text.cursor") {
            VStack(alignment: .leading, spacing: 6) {
                Text("What should \(assistant.name) do? The assistant's own instructions are applied automatically.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                TextEditor(text: viewModel.task)
                    .font(.system(size: 12.5))
                    .frame(minHeight: 74, maxHeight: 130)
                    .padding(6)
                    .background(AppTheme.textBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .strokeBorder(AppTheme.separator, lineWidth: 1)
                    )
                if let error = viewModel.wrappedValue.validationError {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func fieldCard(field: Binding<AssistantLaunchField>) -> some View {
        sectionCard(title: field.wrappedValue.title, symbol: symbol(for: field.wrappedValue.kind)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(field.wrappedValue.requirement)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                fieldControl(field: field)
            }
        }
    }

    private func symbol(for kind: AssistantLaunchFieldKind) -> String {
        switch kind {
        case .text, .multiLineText: return "text.alignleft"
        case .directory: return "folder"
        case .files: return "doc.on.doc"
        case .branch: return "arrow.triangle.branch"
        case .pullRequest: return "arrow.triangle.pull"
        case .issue: return "exclamationmark.circle"
        case .scope: return "scope"
        case .constraints: return "exclamationmark.shield"
        }
    }

    @ViewBuilder
    private func fieldControl(field: Binding<AssistantLaunchField>) -> some View {
        switch field.wrappedValue.kind {
        case .text, .pullRequest, .issue, .scope:
            TextField(field.wrappedValue.title, text: field.text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
        case .multiLineText, .constraints:
            TextEditor(text: field.text)
                .font(.system(size: 12.5))
                .frame(minHeight: 74, maxHeight: 130)
                .padding(6)
                .background(AppTheme.textBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .strokeBorder(AppTheme.separator, lineWidth: 1)
                )
        case .directory:
            pathPickerRow(
                paths: field.wrappedValue.paths,
                emptyLabel: "No directory chosen",
                buttonLabel: "Choose…",
                action: { presentDirectoryPicker(forField: field.wrappedValue.id) }
            )
        case .files:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(field.wrappedValue.paths, id: \.self) { path in
                    HStack {
                        Text(path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            viewModel.removePath(path, fromField: field.wrappedValue.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.tertiaryLabel)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(path)")
                    }
                }
                pathPickerRow(
                    paths: field.wrappedValue.paths,
                    emptyLabel: "No files chosen",
                    buttonLabel: "Choose files…",
                    action: { presentFilePicker(forField: field.wrappedValue.id) }
                )
            }
        case .branch:
            if viewModel.branches.isEmpty {
                TextField("Branch name", text: field.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
            } else {
                Picker(field.wrappedValue.title, selection: field.text) {
                    Text("None").tag("")
                    ForEach(viewModel.branches) { branch in
                        Text(branch.name).tag(branch.name)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12.5))
            }
        }
    }

    private func pathPickerRow(paths: [String], emptyLabel: String, buttonLabel: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(paths.first ?? emptyLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(buttonLabel, action: action)
        }
    }

    private func extraInstructionsCard(viewModel: Bindable<AssistantLaunchViewModel>) -> some View {
        sectionCard(title: "Additional instructions", symbol: "plus.bubble") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Optional notes for this run, such as things to avoid or prefer.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                TextEditor(text: viewModel.extraInstructions)
                    .font(.system(size: 12.5))
                    .frame(minHeight: 56, maxHeight: 110)
                    .padding(6)
                    .background(AppTheme.textBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .strokeBorder(AppTheme.separator, lineWidth: 1)
                    )
            }
        }
    }

    private func statusCard(text: String, systemImage: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isError ? .red : .green)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.secondaryLabel)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
    }

    private func sectionCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func footerBar(viewModel: Bindable<AssistantLaunchViewModel>) -> some View {
        HStack {
            if viewModel.wrappedValue.isLaunching {
                ProgressView()
                    .controlSize(.small)
                Text("Launching \(assistant.name)…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Launch") {
                Task { await viewModel.wrappedValue.launch() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.wrappedValue.canLaunch)
        }
        .padding(16)
        .background(AppTheme.elevatedCardFill)
        .overlay(Divider(), alignment: .top)
    }

    private func presentDirectoryPicker(forField id: Int) {
        let panel = NSOpenPanel()
        panel.title = "Choose Directory"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let cwd = appModel.activeWorkingDirectory {
            panel.directoryURL = URL(fileURLWithPath: cwd)
        }
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setPaths([url.path], forField: id)
        }
    }

    private func presentFilePicker(forField id: Int) {
        let panel = NSOpenPanel()
        panel.title = "Choose Files"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if let cwd = appModel.activeWorkingDirectory {
            panel.directoryURL = URL(fileURLWithPath: cwd)
        }
        if panel.runModal() == .OK {
            viewModel.setPaths(panel.urls.map(\.path), forField: id)
        }
    }
}
