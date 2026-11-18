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

public struct CoincideAppCommands: Commands {
    public let appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some Commands {
        CoincideMenuCommands(appModel: appModel)
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
