import AppKit
import CoincideRemoteKit
import SwiftUI

public struct AgentsMenuCommands: Commands {
    public let appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var selectedThread: RemoteThreadSummary? {
        appModel.selectedThread
    }

    private var hasActiveTurn: Bool {
        if let thread = selectedThread, thread.isRunning || thread.isStarting {
            return true
        }
        if let turn = appModel.activeTranscript?.turn, turn.isRunning || turn.isStarting {
            return true
        }
        return false
    }

    public var body: some Commands {
        // MARK: - File Menu (New & Open)
        CommandGroup(replacing: .newItem) {
            Button("New Thread") {
                Task { _ = await appModel.createNewThread() }
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("New Chat") {
                Task { _ = await appModel.createNewChat() }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Bot…") {
                appModel.openBotEditor(for: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("Add Project Folder…") {
                appModel.promptAddProjectFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Import CLI Sessions…") {
                appModel.showSessionImport = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button(openInEditorTitle) {
                openWorkingDirectoryInPreferredEditor()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(appModel.activeWorkingDirectory == nil || appModel.externalEditors.preferredEditor == nil)

            Button("Reveal Working Directory in Finder") {
                if let cwd = appModel.activeWorkingDirectory {
                    appModel.externalEditors.revealInFinder(path: cwd)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(appModel.activeWorkingDirectory == nil)
        }

        // MARK: - Edit Menu (Find & Search)
        CommandGroup(after: .textEditing) {
            Divider()

            Button("Find in Conversation") {
                appModel.showFindBar = true
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Search Sidebar") {
                NotificationCenter.default.post(name: .coincideFocusSidebarSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }

        // MARK: - View Menu (Inspector, Terminal, Palette & Zoom)
        CommandGroup(after: .sidebar) {
            Button(appModel.inspectorVisible ? "Hide Inspector" : "Toggle Inspector") {
                appModel.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Button("Show Changes") {
                appModel.openInspector(tab: .changes)
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button("Show Source Control") {
                appModel.openInspector(tab: .git)
            }
            .keyboardShortcut("g", modifiers: [.command, .control])

            Button("Show Pull Requests") {
                appModel.openInspector(tab: .pullRequests)
            }
            .keyboardShortcut("p", modifiers: [.command, .control])

            Button("Show Workspace Files") {
                appModel.openInspector(tab: .files)
            }
            .keyboardShortcut("e", modifiers: [.command, .control])

            Button("Show Scheduled Tasks") {
                appModel.openInspector(tab: .schedules)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(appModel.terminalVisible ? "Hide Terminal" : "Toggle Terminal") {
                appModel.toggleTerminal()
            }
            .keyboardShortcut("j", modifiers: [.command])

            Toggle(
                "Show Archived Threads",
                isOn: Binding(
                    get: { appModel.showArchivedThreads },
                    set: { appModel.showArchivedThreads = $0 }
                )
            )
            .keyboardShortcut("a", modifiers: [.command, .option])

            Button("Command Palette…") {
                appModel.showCommandPalette.toggle()
            }
            .keyboardShortcut("k", modifiers: [.command])

            Divider()

            Button("Zoom In") {
                appModel.increaseFontScale()
            }
            .keyboardShortcut("+", modifiers: [.command])

            Button("Zoom Out") {
                appModel.decreaseFontScale()
            }
            .keyboardShortcut("-", modifiers: [.command])

            Button("Actual Size") {
                appModel.resetFontScale()
            }
            .keyboardShortcut("0", modifiers: [.command])
        }

        // MARK: - Thread Menu
        CommandMenu("Thread") {
            Button("Stop Active Turn") {
                Task { await appModel.stopActiveTurn() }
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!hasActiveTurn)

            Button("Previous Thread") {
                appModel.selectPreviousThread()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(appModel.filteredThreads.isEmpty)

            Button("Next Thread") {
                appModel.selectNextThread()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(appModel.filteredThreads.isEmpty)

            Divider()

            Button(selectedThread?.isPinned == true ? "Unpin Thread" : "Pin Thread") {
                guard let thread = selectedThread else { return }
                Task {
                    await appModel.performThreadAction(.pin(!thread.isPinned), on: thread.id)
                }
            }
            .disabled(selectedThread == nil)

            Button("Fork Thread") {
                guard let threadID = appModel.selectedThreadUUID else { return }
                Task { _ = await appModel.forkThread(threadID) }
            }
            .disabled(selectedThread == nil)

            Button("Mark Seen") {
                guard let threadID = appModel.selectedThreadUUID else { return }
                Task {
                    try? await appModel.runtime?.markSeen(threadID)
                    await appModel.refreshWorkspace()
                }
            }
            .disabled(selectedThread == nil)

            Button(selectedThread?.isArchived == true ? "Unarchive Thread" : "Archive Thread") {
                guard let thread = selectedThread else { return }
                Task {
                    await appModel.performThreadAction(.archive(!thread.isArchived), on: thread.id)
                }
            }
            .disabled(selectedThread == nil)

            Divider()

            Button("Delete Thread", role: .destructive) {
                guard let threadID = appModel.selectedThreadID else { return }
                Task { await appModel.deleteThreadPermanently(threadID) }
            }
            .disabled(selectedThread == nil)
        }

        // MARK: - Help Menu
        CommandGroup(replacing: .help) {
            Button("Antigravity ACP Documentation") {
                if let url = URL(string: "https://antigravity.google/docs/ide/extensions/acp") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Agents GitHub Repository") {
                NSWorkspace.shared.open(AgentsLinks.repository)
            }

            Button("Report an Issue") {
                let appVer = CommunityLink.appVersion(
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                )
                let macVer = CommunityLink.systemVersion(ProcessInfo.processInfo.operatingSystemVersion)
                let issueURL = CommunityLink.reportIssue.url(coincideVersion: appVer, macOSVersion: macVer)
                NSWorkspace.shared.open(issueURL)
            }
        }
    }

    // MARK: - Helpers

    private var openInEditorTitle: String {
        if let editor = appModel.externalEditors.preferredEditor {
            return "Open in \(editor.name)"
        }
        return "Open in Preferred Editor"
    }

    private func openWorkingDirectoryInPreferredEditor() {
        guard let cwd = appModel.activeWorkingDirectory,
              let editor = appModel.externalEditors.preferredEditor
        else { return }
        do {
            try appModel.externalEditors.open(path: cwd, in: editor)
        } catch {
            appModel.presentError(error)
        }
    }
}
