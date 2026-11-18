import SwiftUI

@main
public struct AgentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        WindowGroup("Agents") {
            MainWindowView(appModel: appDelegate.appModel)
        }
        .defaultSize(width: 1440, height: 880)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AgentsAppCommands(appModel: appDelegate.appModel)
        }

        Settings {
            SettingsRootContainerView(appModel: appDelegate.appModel)
        }
    }
}
