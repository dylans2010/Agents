import AppKit
import CoincideRemoteKit
import Foundation

@MainActor
public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var appModel: AppModel?

    public init(appModel: AppModel) {
        self.appModel = appModel
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
            let image = NSImage(named: "coincide.bot")
                ?? NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: "Coincide")
            image?.isTemplate = true
            button.image = image?.withSymbolConfiguration(symbolConfig) ?? image
            button.imagePosition = .imageLeading
            button.toolTip = "Coincide"
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
    }

    public func update(with status: RuntimePollStatus) {
        guard let button = statusItem?.button else { return }
        let attention = status.totalAttentionCount
        let active = status.running + status.starting

        if attention > 0 {
            button.title = " \(attention)"
        } else if active > 0 {
            button.title = " \(active)"
        } else {
            button.title = ""
        }
    }

    // MARK: - NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let appModel else { return }

        let status = appModel.status
        let activeCount = status.running + status.starting
        let attentionCount = status.totalAttentionCount

        let headerText: String
        if attentionCount > 0 {
            headerText = "\(attentionCount) waiting for your input"
        } else if activeCount > 0 {
            headerText = "\(activeCount) agent turn\(activeCount == 1 ? "" : "s") running"
        } else {
            headerText = "Coincide · Idle"
        }
        let headerItem = NSMenuItem(title: headerText, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        let bringFront = NSMenuItem(
            title: "Bring Coincide to Front",
            action: #selector(handleBringToFront),
            keyEquivalent: ""
        )
        bringFront.target = self
        menu.addItem(bringFront)

        let newThread = NSMenuItem(
            title: "New Thread",
            action: #selector(handleNewThread),
            keyEquivalent: "n"
        )
        newThread.target = self
        menu.addItem(newThread)

        let recent = appModel.recentThreads
        if !recent.isEmpty {
            menu.addItem(.separator())
            let recentHeader = NSMenuItem(title: "Recent Threads", action: nil, keyEquivalent: "")
            recentHeader.isEnabled = false
            menu.addItem(recentHeader)

            for thread in recent {
                let prefix = thread.needsUser ? "● " : (thread.isRunning ? "↻ " : "")
                let item = NSMenuItem(
                    title: prefix + (thread.title.isEmpty ? "Untitled Thread" : thread.title),
                    action: #selector(handleSelectRecentThread(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = thread.id.uuidString
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit Coincide",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    @objc private func handleBringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func handleNewThread() {
        handleBringToFront()
        guard let appModel else { return }
        Task {
            _ = await appModel.createNewThread()
        }
    }

    @objc private func handleSelectRecentThread(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String else { return }
        handleBringToFront()
        appModel?.selectThread(idString)
    }

    public func tearDown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}
