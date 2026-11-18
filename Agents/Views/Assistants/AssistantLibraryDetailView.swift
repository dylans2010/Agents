import SwiftUI

public struct AssistantLibraryDetailView: View {
    public let definition: AssistantDefinition
    public let isFavorite: Bool
    public let canDelete: Bool
    public let canRestoreDefaults: Bool
    public let showsAutomationAction: Bool
    public let onToggleFavorite: () -> Void
    public let onDuplicate: () -> Void
    public let onEdit: (AssistantDefinition) -> Void
    public let onDelete: () -> Void
    public let onRestoreDefaults: () -> Void
    public let onAddToAutomation: () -> Void
    public let onLaunch: (String) -> Void

    @State private var taskText: String = ""
    @State private var pendingDelete: Bool = false
    @State private var pendingRestore: Bool = false

    public init(
        definition: AssistantDefinition,
        isFavorite: Bool,
        canDelete: Bool,
        canRestoreDefaults: Bool,
        showsAutomationAction: Bool,
        onToggleFavorite: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onEdit: @escaping (AssistantDefinition) -> Void,
        onDelete: @escaping () -> Void,
        onRestoreDefaults: @escaping () -> Void,
        onAddToAutomation: @escaping () -> Void,
        onLaunch: @escaping (String) -> Void
    ) {
        self.definition = definition
        self.isFavorite = isFavorite
        self.canDelete = canDelete
        self.canRestoreDefaults = canRestoreDefaults
        self.showsAutomationAction = showsAutomationAction
        self.onToggleFavorite = onToggleFavorite
        self.onDuplicate = onDuplicate
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onRestoreDefaults = onRestoreDefaults
        self.onAddToAutomation = onAddToAutomation
        self.onLaunch = onLaunch
    }

    private var modelConfigText: String {
        switch definition.modelConfig {
        case .appDefault:
            "App default"
        case .specific(let provider, let model):
            "\(AgentBranding.displayName(for: provider)) · \(model)"
        case .providerOnly(let provider):
            "\(AgentBranding.displayName(for: provider)) · any model"
        case .modelOnly(let model):
            "Any provider · \(model)"
        case .currentAppModel:
            "Current app model"
        }
    }

    private var permissionProfileText: String {
        switch definition.permissionProfile {
        case .readOnly: "Read-only"
        case .workspaceModify: "Workspace modify"
        case .terminal: "Terminal"
        case .approvalRequired: "Approval required"
        }
    }

    private var capabilityText: String {
        if let tools = definition.allowedTools {
            return "\(tools.count) tools"
        }
        return "\(SystemToolRegistry.systemTools.count) tools"
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                launchSection
                actionsSection
                Divider()
                summarySection
                if !definition.intendedTasks.isEmpty {
                    detailSection(title: "Intended Tasks", systemImage: "checklist") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(definition.intendedTasks, id: \.self) { task in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 5))
                                        .foregroundStyle(AppTheme.tertiaryLabel)
                                        .padding(.top, 5)
                                    Text(task)
                                        .font(AppTheme.bodyFont())
                                        .foregroundStyle(AppTheme.primaryLabel)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                if !definition.expectedOutputFormat.isEmpty {
                    detailSection(title: "Expected Output", systemImage: "doc.text") {
                        Text(definition.expectedOutputFormat)
                            .font(AppTheme.bodyFont())
                            .foregroundStyle(AppTheme.primaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                detailSection(title: "Capabilities", systemImage: "wrench.and.screwdriver") {
                    Text(capabilityText)
                        .font(AppTheme.codeFont())
                        .foregroundStyle(AppTheme.primaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                detailSection(title: "Model", systemImage: "cpu") {
                    Text(modelConfigText)
                        .font(AppTheme.bodyFont())
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                detailSection(title: "Permissions", systemImage: "lock.shield") {
                    Text(permissionProfileText)
                        .font(AppTheme.bodyFont())
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                if let requirements = definition.inputRequirements, !requirements.isEmpty {
                    detailSection(title: "Input Requirements", systemImage: "tray.and.arrow.down") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(requirements, id: \.self) { requirement in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 5))
                                        .foregroundStyle(AppTheme.tertiaryLabel)
                                        .padding(.top, 5)
                                    Text(requirement)
                                        .font(AppTheme.bodyFont())
                                        .foregroundStyle(AppTheme.primaryLabel)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(AppTheme.windowBackground)
        .alert(
            "Delete Assistant?",
            isPresented: $pendingDelete
        ) {
            Button("Delete", role: .destructive) {
                pendingDelete = false
                onDelete()
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = false
            }
        } message: {
            Text("Delete “\(definition.name)”? This removes the custom assistant permanently.")
        }
        .alert(
            "Restore Defaults?",
            isPresented: $pendingRestore
        ) {
            Button("Restore Defaults", role: .destructive) {
                pendingRestore = false
                onRestoreDefaults()
            }
            Button("Cancel", role: .cancel) {
                pendingRestore = false
            }
        } message: {
            Text("Discard your customizations to “\(definition.name)” and restore the built-in assistant?")
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: definition.icon.isEmpty ? "sparkles" : definition.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(width: 48, height: 48)
                .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(definition.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(definition.category.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.elevatedCardFill, in: Capsule())

                    if definition.customized {
                        Text("Customized")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.warning.opacity(0.12), in: Capsule())
                    } else if !definition.isBuiltIn {
                        Text("Custom")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.info)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.info.opacity(0.12), in: Capsule())
                    } else {
                        Text("Built-in")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.elevatedCardFill, in: Capsule())
                    }
                }

                if !definition.description.isEmpty {
                    Text(definition.description)
                        .font(AppTheme.bodyFont())
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Launch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)

            HStack(spacing: 8) {
                TextField("Describe the task for \(definition.name)…", text: $taskText)
                    .textFieldStyle(.roundedBorder)
                    .font(AppTheme.bodyFont())
                    .onSubmit {
                        launchIfPossible()
                    }

                Button {
                    launchIfPossible()
                } label: {
                    Label("Launch Assistant", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
    }

    private var actionsSection: some View {
        HStack(spacing: 8) {
            Button {
                onToggleFavorite()
            } label: {
                Label(
                    isFavorite ? "Favorited" : "Favorite",
                    systemImage: isFavorite ? "star.fill" : "star"
                )
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onEdit(definition)
            } label: {
                Label(definition.isBuiltIn ? "Customize…" : "Edit…", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if showsAutomationAction {
                Button {
                    onAddToAutomation()
                } label: {
                    Label("Add to Automation", systemImage: "bolt")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if canRestoreDefaults {
                Button {
                    pendingRestore = true
                } label: {
                    Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if canDelete {
                Button(role: .destructive) {
                    pendingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var summarySection: some View {
        detailSection(title: "Summary", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 4) {
                summaryRow(label: "Category", value: definition.category.displayName)
                summaryRow(label: "Permissions", value: permissionProfileText)
                summaryRow(label: "Capabilities", value: capabilityText)
                summaryRow(label: "Input requirements", value: inputRequirementsText)
                summaryRow(label: "Version", value: "Version \(definition.version)")
            }
        }
    }

    private var inputRequirementsText: String {
        let count = definition.inputRequirements?.count ?? 0
        if count == 0 {
            return "None"
        }
        return "\(count) requirement\(count == 1 ? "" : "s")"
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(AppTheme.bodyFont())
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(width: 128, alignment: .leading)
            Text(value)
                .font(AppTheme.bodyFont())
                .foregroundStyle(AppTheme.primaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)
            content()
        }
    }

    private func launchIfPossible() {
        let trimmed = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onLaunch(trimmed)
    }
}
