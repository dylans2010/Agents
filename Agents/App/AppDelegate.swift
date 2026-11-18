import AppKit
import CoincideRemoteKit
import Foundation
@preconcurrency import UserNotifications

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    public let appModel = AppModel()
    private var statusBarController: StatusBarController?
    private var isShuttingDown = false

    public static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else { return }

        // 1. Adopt login shell PATH early before spawning any runtime worker threads.
        AgentsRuntimeClient.adoptLoginShellPath()

        // 2. Single-instance handoff: if another Agents instance is already serving
        //    `control.sock`, activate it and exit cleanly.
        let customDataDir = ProcessInfo.processInfo.environment["COINCIDE_DATA_DIR"]
        if AgentsRuntimeClient.handoffIfRunning(dataDir: customDataDir) {
            NSApp.terminate(nil)
            return
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else { return }

        configureNotifications()
        let bar = StatusBarController(appModel: appModel)
        self.statusBarController = bar

        appModel.onStatusChanged = { [weak self] status in
            guard let self else { return }
            self.updateDockBadge(with: status)
            self.statusBarController?.update(with: status)
        }

        appModel.onAgentTurnFinished = { [weak self] summary in
            self?.postTurnFinishedNotification(for: summary)
        }

        appModel.onUserAttentionNeeded = { [weak self] approvals, questions in
            self?.postAttentionNotification(approvals: approvals, questions: questions)
        }

        let customDataDir = ProcessInfo.processInfo.environment["COINCIDE_DATA_DIR"]
        Task {
            await appModel.bootstrap(dataDir: customDataDir, startPolling: true)
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return true
    }

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Agents")

        let newThreadItem = NSMenuItem(
            title: "New Thread",
            action: #selector(dockNewThread),
            keyEquivalent: ""
        )
        newThreadItem.target = self
        menu.addItem(newThreadItem)

        let recents = appModel.recentThreads
        if !recents.isEmpty {
            menu.addItem(.separator())
            for thread in recents {
                let item = NSMenuItem(
                    title: thread.title.isEmpty ? "Untitled Thread" : thread.title,
                    action: #selector(dockOpenThread(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = thread.id.uuidString
                menu.addItem(item)
            }
        }
        return menu
    }

    @objc private func dockNewThread() {
        NSApp.activate(ignoringOtherApps: true)
        Task { _ = await appModel.createNewThread() }
    }

    @objc private func dockOpenThread(_ sender: NSMenuItem) {
        guard let threadID = sender.representedObject as? String else { return }
        NSApp.activate(ignoringOtherApps: true)
        appModel.selectThread(threadID)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.isRunningUnitTests else { return .terminateNow }
        if isShuttingDown {
            return .terminateLater
        }

        let activeTurns = appModel.status.running + appModel.status.starting
        if activeTurns > 0 {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = activeTurns == 1
                ? "An agent turn is still running."
                : "\(activeTurns) agent turns are still running."
            alert.informativeText = "Quitting Agents will stop active turns and close open terminal sessions."
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn {
                return .terminateCancel
            }
        }

        isShuttingDown = true
        statusBarController?.tearDown()
        NSApp.dockTile.badgeLabel = nil

        Task { @MainActor in
            await appModel.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: - Dock Badge & Notifications

    private func updateDockBadge(with status: RuntimePollStatus) {
        let attention = status.totalAttentionCount
        if attention > 0 {
            NSApp.dockTile.badgeLabel = "\(attention)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    private func configureNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    private func postTurnFinishedNotification(for thread: RemoteThreadSummary) {
        guard !NSApp.isActive, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = AgentBranding.displayName(for: thread.selection.provider)
        content.body = thread.title.isEmpty ? "Finished turn." : "Finished: \(thread.title)"
        content.sound = .default
        content.userInfo = ["threadID": thread.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "turn-\(thread.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func postAttentionNotification(approvals: Int, questions: Int) {
        guard !NSApp.isActive, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Agents Needs Input"
        if approvals > 0 && questions > 0 {
            content.body = "\(approvals) approval(s) and \(questions) question(s) waiting."
        } else if approvals > 0 {
            content.body = "\(approvals) tool approval\(approvals == 1 ? "" : "s") waiting."
        } else {
            content.body = "\(questions) agent question\(questions == 1 ? "" : "s") waiting."
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "attention-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let threadID = response.notification.request.content.userInfo["threadID"] as? String
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            if let threadID {
                self.appModel.selectThread(threadID)
            }
        }
        completionHandler()
    }
}
