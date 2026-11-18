import CoincideRemoteKit
import SwiftUI

public struct SidebarContainerView: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        SidebarRootView(appModel: appModel)
    }
}

public struct ConversationContainerView: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        ConversationRootView(appModel: appModel)
    }
}

public struct InspectorContainerView: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        WorkspaceInspectorRootView(appModel: appModel)
    }
}

public struct TerminalContainerView: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        TerminalDrawerRootView(appModel: appModel)
    }
}

public struct SettingsRootContainerView: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        SettingsRootView(appModel: appModel)
    }
}

public struct AgentsAppCommands: Commands {
    public let appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some Commands {
        AgentsMenuCommands(appModel: appModel)
    }
}

public struct CommandPaletteContainerSheet: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        CommandPaletteSheet(appModel: appModel)
    }
}

public struct BotEditorContainerSheet: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        BotEditorSheet(appModel: appModel)
    }
}

public struct SessionImportContainerSheet: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        SessionImportSheet(appModel: appModel)
    }
}

public struct AssistantEditorContainerSheet: View {
    @Bindable public var appModel: AppModel

    @State private var viewModel: AssistantEditorViewModel
    @State private var savedAssistant: RemoteAssistant?

    public init(appModel: AppModel) {
        self.appModel = appModel
        if let definition = appModel.editingAssistantDefinition {
            _viewModel = State(initialValue: AssistantEditorViewModel(
                editing: definition,
                stored: AssistantLibraryViewModel.storedRecord(for: definition, in: appModel.assistantCatalog)
            ))
        } else {
            _viewModel = State(initialValue: AssistantEditorViewModel())
        }
        _savedAssistant = State(initialValue: nil)
    }

    public var body: some View {
        AssistantEditorView(
            viewModel: viewModel,
            onSave: { draft in
                let id = await appModel.saveAssistant(draft)
                if let id {
                    savedAssistant = appModel.assistants.first { $0.id == id }
                }
                return id
            },
            onCancel: { appModel.closeAssistantEditor() },
            onTestRun: AssistantEditorView.testRunHandler(appModel: appModel),
            savedAssistant: savedAssistant,
            onRestoreDefaults: { record in await appModel.deleteAssistant(record) }
        )
    }
}

public struct AssistantLaunchContainerSheet: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        if let definition = appModel.launchingAssistantDefinition {
            AssistantLaunchView(
                assistant: definition,
                appModel: appModel,
                prefillPaths: appModel.launchingAssistantPaths,
                prefillTask: appModel.launchingAssistantTask,
                onLaunch: { _ in appModel.closeAssistantLaunch() }
            )
        }
    }
}

public struct AssistantResultContainerSheet: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        if let report = appModel.assistantResultReport {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") {
                        appModel.dismissAssistantResult()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                AssistantResultView(report: report)
            }
            .frame(minWidth: 560, idealWidth: 680, maxWidth: 820, minHeight: 480, idealHeight: 640, maxHeight: 860)
        }
    }
}
