import SwiftUI

@main
public struct CoincideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        WindowGroup("Coincide") {
            MainWindowView(appModel: appDelegate.appModel)
        }
        .defaultSize(width: 1440, height: 880)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CoincideAppCommands(appModel: appDelegate.appModel)
        }

        Settings {
            SettingsRootContainerView(appModel: appDelegate.appModel)
        }
    }
}
