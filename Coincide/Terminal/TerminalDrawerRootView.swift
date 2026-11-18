import AppKit
import CoincideRemoteKit
import SwiftUI

public struct TerminalDrawerRootView: View {
    @Bindable public var appModel: AppModel

    @State private var isSplitView: Bool = false
    @State private var secondaryTerminalID: String?
    @State private var focusedPane: TerminalPaneSlot = .primary
    @State private var snapshotsByID: [String: TerminalViewportSnapshot] = [:]
    @State private var isCreatingSession: Bool = false

    private enum TerminalPaneSlot: Equatable {
        case primary
        case secondary
    }

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var primaryTerminalID: String? {
        appModel.selectedTerminalID ?? appModel.activeTerminals.first?.id
    }

    private var activeFocusedTerminalID: String? {
        if isSplitView, focusedPane == .secondary, let sec = resolvedSecondaryTerminalID {
            return sec
        }
        return primaryTerminalID
    }

    private var resolvedSecondaryTerminalID: String? {
        guard isSplitView else { return nil }
        if let sec = secondaryTerminalID,
           sec != primaryTerminalID,
           appModel.activeTerminals.contains(where: { $0.id == sec })
        {
            return sec
        }
        return appModel.activeTerminals.first(where: { $0.id != primaryTerminalID })?.id
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()

            terminalHeaderBar
                .frame(height: 32)
                .background(AppTheme.controlBackground)

            Divider()

            terminalWorkspaceBody
        }
        .background(AppTheme.underPageBackground)
        .task {
            await ensureInitialTerminalSession()
        }
        .onChange(of: appModel.selectedThreadID) { _, _ in
            Task {
                await appModel.refreshTerminals()
                if appModel.activeTerminals.isEmpty && appModel.terminalVisible {
                    _ = await appModel.createTerminalForSelectedThread()
                }
            }
        }
        .onChange(of: appModel.activeTerminals) { _, updated in
            if updated.count < 2, isSplitView {
                secondaryTerminalID = nil
            } else if isSplitView, resolvedSecondaryTerminalID == nil {
                secondaryTerminalID = updated.first(where: { $0.id != primaryTerminalID })?.id
            }
        }
    }

    // MARK: - Top Chrome Bar (Height: 32)

    private var terminalHeaderBar: some View {
        HStack(spacing: 6) {
            // Scrollable PTY Session Tab Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(appModel.activeTerminals) { session in
                        TerminalTabChip(
                            session: session,
                            isPrimarySelected: session.id == primaryTerminalID,
                            isSecondarySelected: isSplitView && session.id == resolvedSecondaryTerminalID,
                            isFocused: session.id == activeFocusedTerminalID,
                            onSelect: {
                                selectTab(session.id)
                            },
                            onClose: {
                                Task { await closeSession(session.id) }
                            }
                        )
                    }
                }
                .padding(.leading, 8)
                .padding(.vertical, 3)
            }

            // + New Terminal
            Button {
                Task { await createNewSession() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(isCreatingSession)
            .help("New Terminal Session")

            Divider()
                .frame(height: 16)

            // Split View Toggle
            Button {
                Task { await toggleSplitTerminal() }
            } label: {
                Image(systemName: isSplitView ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSplitView ? AppTheme.accent : AppTheme.secondaryLabel)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.borderless)
            .help(isSplitView ? "Close Split Terminal View" : "Split Terminal Side-by-Side")

            // Project Scripts Quick-Run Menu
            if let project = appModel.selectedProject, !project.scripts.isEmpty {
                Menu {
                    Section("Run in \(project.name)") {
                        ForEach(project.scripts) { script in
                            Button {
                                Task { await runScript(script, in: project) }
                            } label: {
                                Label(script.name, systemImage: symbolForScriptIcon(script.icon))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("Scripts")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Run Project Script")
            }

            Spacer(minLength: 4)

            // Active Directory Breadcrumb Hint
            if let cwd = activeDirectoryLabel {
                Text(cwd)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200, alignment: .trailing)
            }

            Divider()
                .frame(height: 16)

            // Clear
            Button {
                Task { await clearActiveTerminal() }
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 11.5))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(activeFocusedTerminalID == nil)
            .help("Clear Terminal (⌘K)")

            // Restart
            Button {
                Task { await restartActiveTerminal() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11.5))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(activeFocusedTerminalID == nil)
            .help("Restart Shell Process")

            // Send Output to Composer
            Button {
                Task { await sendActiveOutputToComposer() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 11))
                    Text("To Composer")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(activeFocusedTerminalID == nil)
            .help("Send Terminal Output to Composer")

            // Open External Terminal
            externalTerminalButton

            Divider()
                .frame(height: 16)

            // Hide Terminal Drawer
            Button {
                appModel.terminalVisible = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 6)
            .help("Hide Terminal (⌘J)")
        }
    }

    @ViewBuilder
    private var externalTerminalButton: some View {
        let installed = appModel.externalEditors.installedTerminals
        if installed.count > 1 {
            Menu {
                ForEach(installed) { target in
                    Button {
                        openExternalTerminal(target)
                    } label: {
                        Label {
                            Text(target.name)
                        } icon: {
                            Image(nsImage: target.icon)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11.5))
                    .frame(width: 24, height: 22)
            } primaryAction: {
                if let preferred = appModel.externalEditors.preferredTerminal {
                    openExternalTerminal(preferred)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Open Working Directory in External Terminal")
        } else {
            Button {
                if let preferred = appModel.externalEditors.preferredTerminal {
                    openExternalTerminal(preferred)
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11.5))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(installed.isEmpty)
            .help("Open Working Directory in External Terminal")
        }
    }

    // MARK: - PTY Split / Single Content Area

    @ViewBuilder
    private var terminalWorkspaceBody: some View {
        if let primaryID = primaryTerminalID {
            if isSplitView, let secID = resolvedSecondaryTerminalID, secID != primaryID {
                HSplitView {
                    terminalPaneContainer(terminalID: primaryID, slot: .primary, showSplitHeader: true)
                        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)

                    terminalPaneContainer(terminalID: secID, slot: .secondary, showSplitHeader: true)
                        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                terminalPaneContainer(terminalID: primaryID, slot: .primary, showSplitHeader: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Launching interactive shell…")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Button("New Terminal") {
                    Task { await createNewSession() }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func terminalPaneContainer(
        terminalID: String,
        slot: TerminalPaneSlot,
        showSplitHeader: Bool
    ) -> some View {
        let summary = appModel.activeTerminals.first(where: { $0.id == terminalID })
        let isFocusedSlot = !showSplitHeader || focusedPane == slot

        return VStack(spacing: 0) {
            if showSplitHeader {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isFocusedSlot ? AppTheme.accent : AppTheme.quaternaryLabel)
                        .frame(width: 6, height: 6)

                    Menu {
                        ForEach(appModel.activeTerminals) { candidate in
                            Button {
                                assignSession(candidate.id, to: slot)
                            } label: {
                                HStack {
                                    Text(sessionDisplayTitle(candidate))
                                    if candidate.id == terminalID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(summary.map(sessionDisplayTitle) ?? "Terminal")
                            .font(.system(size: 11, weight: isFocusedSlot ? .semibold : .regular))
                            .foregroundStyle(isFocusedSlot ? AppTheme.primaryLabel : AppTheme.secondaryLabel)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    if let code = summary?.exitCode, summary?.exited == true {
                        ExitCodeBadge(exitCode: code)
                    }

                    Spacer()

                    if slot == .secondary {
                        Button {
                            isSplitView = false
                            focusedPane = .primary
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(AppTheme.tertiaryLabel)
                        }
                        .buttonStyle(.plain)
                        .help("Unsplit Pane")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(AppTheme.elevatedCardFill)
                Divider()
            }

            NativeTerminalNSView(
                terminalID: terminalID,
                runtime: appModel.runtime,
                fontScale: appModel.fontScale,
                isBusy: summary?.busy ?? false,
                isPrimaryFocus: isFocusedSlot,
                onFocusRequested: {
                    focusedPane = slot
                    if slot == .primary {
                        appModel.selectedTerminalID = terminalID
                    }
                },
                onSendToComposer: { snippet in
                    appModel.sendTerminalContextToComposer(snippet)
                    appModel.presentToast("Sent to Composer", detail: "Terminal snippet inserted", style: .success)
                },
                onSnapshotChanged: { snap in
                    snapshotsByID[terminalID] = snap
                }
            )
            .overlay(alignment: .bottom) {
                if let summary, summary.exited {
                    exitedBanner(for: summary)
                }
            }
        }
    }

    private func exitedBanner(for session: TerminalSessionSummary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: (session.exitCode ?? 0) == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle((session.exitCode ?? 0) == 0 ? AppTheme.success : AppTheme.warning)
                .font(.system(size: 12))

            Text(
                session.exitMessage
                    ?? "Process exited with status \(session.exitCode ?? 0)"
            )
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(AppTheme.primaryLabel)

            Spacer()

            Button("Restart Shell") {
                Task {
                    try? await appModel.runtime?.restartTerminal(id: session.id)
                    await appModel.refreshTerminals()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("Close") {
                Task { await closeSession(session.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Actions & Helpers

    private var activeDirectoryLabel: String? {
        guard let focusedID = activeFocusedTerminalID else { return nil }
        let dir = snapshotsByID[focusedID]?.directory
            ?? appModel.activeTerminals.first(where: { $0.id == focusedID })?.directory
        guard let dir, !dir.isEmpty else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir == home { return "~" }
        if dir.hasPrefix(home + "/") {
            return "~" + String(dir.dropFirst(home.count))
        }
        return dir
    }

    private func sessionDisplayTitle(_ session: TerminalSessionSummary) -> String {
        if let fg = session.foreground?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fg.isEmpty
        {
            return fg
        }
        let trimmedTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return session.name
    }

    private func ensureInitialTerminalSession() async {
        await appModel.refreshTerminals()
        if appModel.activeTerminals.isEmpty {
            isCreatingSession = true
            defer { isCreatingSession = false }
            _ = await appModel.createTerminalForSelectedThread()
        }
    }

    private func createNewSession() async {
        isCreatingSession = true
        defer { isCreatingSession = false }
        if let newID = await appModel.createTerminalForSelectedThread() {
            if isSplitView && focusedPane == .secondary {
                secondaryTerminalID = newID
            } else {
                appModel.selectedTerminalID = newID
                focusedPane = .primary
            }
        }
    }

    private func selectTab(_ id: String) {
        if isSplitView {
            if id == primaryTerminalID {
                focusedPane = .primary
            } else if id == resolvedSecondaryTerminalID {
                focusedPane = .secondary
            } else if focusedPane == .secondary {
                secondaryTerminalID = id
            } else {
                appModel.selectedTerminalID = id
            }
        } else {
            appModel.selectedTerminalID = id
            focusedPane = .primary
        }
    }

    private func assignSession(_ id: String, to slot: TerminalPaneSlot) {
        switch slot {
        case .primary:
            if id == secondaryTerminalID {
                secondaryTerminalID = primaryTerminalID
            }
            appModel.selectedTerminalID = id
            focusedPane = .primary
        case .secondary:
            if id == primaryTerminalID,
               let alt = appModel.activeTerminals.first(where: { $0.id != id })?.id
            {
                appModel.selectedTerminalID = alt
            }
            secondaryTerminalID = id
            focusedPane = .secondary
        }
    }

    private func toggleSplitTerminal() async {
        if isSplitView {
            isSplitView = false
            focusedPane = .primary
            return
        }

        if appModel.activeTerminals.count < 2 {
            let previousPrimary = primaryTerminalID
            isCreatingSession = true
            let created = await appModel.createTerminalForSelectedThread()
            isCreatingSession = false
            if let previousPrimary {
                appModel.selectedTerminalID = previousPrimary
            }
            secondaryTerminalID = created
        } else {
            secondaryTerminalID = appModel.activeTerminals.first(where: { $0.id != primaryTerminalID })?.id
        }
        isSplitView = secondaryTerminalID != nil
        focusedPane = .secondary
    }

    private func closeSession(_ id: String) async {
        snapshotsByID.removeValue(forKey: id)
        if secondaryTerminalID == id {
            secondaryTerminalID = nil
        }
        await appModel.closeTerminal(id)
        if appModel.activeTerminals.count < 2 {
            isSplitView = false
            focusedPane = .primary
        }
        if appModel.activeTerminals.isEmpty {
            appModel.terminalVisible = false
        }
    }

    private func clearActiveTerminal() async {
        guard let id = activeFocusedTerminalID, let runtime = appModel.runtime else { return }
        do {
            try await runtime.clearTerminal(id: id)
        } catch {
            appModel.presentError(error)
        }
    }

    private func restartActiveTerminal() async {
        guard let id = activeFocusedTerminalID, let runtime = appModel.runtime else { return }
        do {
            try await runtime.restartTerminal(id: id)
            await appModel.refreshTerminals()
        } catch {
            appModel.presentError(error)
        }
    }

    private func sendActiveOutputToComposer() async {
        guard let id = activeFocusedTerminalID else { return }
        var snap = snapshotsByID[id]
        if snap == nil, let runtime = appModel.runtime {
            snap = try? await runtime.readTerminalViewport(id: id, dark: true)
        }
        guard let snap else { return }
        var lines = snap.lines.map {
            $0.text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        let joined = lines.suffix(80).joined(separator: "\n")
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appModel.presentToast("Terminal Output Empty", style: .info)
            return
        }
        appModel.sendTerminalContextToComposer(joined)
        appModel.presentToast("Sent Output to Composer", style: .success)
    }

    private func runScript(_ script: RemoteScript, in project: RemoteProject) async {
        if appModel.selectedThreadUUID != nil {
            await appModel.runProjectScript(script, projectID: project.id)
        } else if let id = activeFocusedTerminalID, let runtime = appModel.runtime {
            try? await runtime.sendTerminalInput(id: id, data: script.command + "\r")
        }
    }

    private func openExternalTerminal(_ target: ExternalAppTarget) {
        let dir = appModel.activeWorkingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        do {
            try appModel.externalEditors.open(path: dir, in: target)
        } catch {
            appModel.presentError(error)
        }
    }

    private func symbolForScriptIcon(_ icon: String) -> String {
        switch icon.lowercased() {
        case "test": "checkmark.seal"
        case "lint": "wand.and.stars"
        case "configure": "slider.horizontal.3"
        case "build": "hammer"
        case "debug": "ladybug"
        default: "play.fill"
        }
    }
}

// MARK: - Session Tab Chip & Badges

private struct TerminalTabChip: View {
    let session: TerminalSessionSummary
    let isPrimarySelected: Bool
    let isSecondarySelected: Bool
    let isFocused: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering: Bool = false

    private var isSelected: Bool {
        isPrimarySelected || isSecondarySelected
    }

    private var displayTitle: String {
        if let fg = session.foreground?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fg.isEmpty
        {
            return fg
        }
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? session.name : title
    }

    var body: some View {
        HStack(spacing: 6) {
            statusIndicator

            Text(displayTitle)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.primaryLabel : AppTheme.secondaryLabel)
                .lineLimit(1)
                .frame(maxWidth: 150)

            if session.exited, let code = session.exitCode {
                ExitCodeBadge(exitCode: code)
            } else if session.bells > 0 {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.warning)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(isHovering || isSelected ? AppTheme.secondaryLabel : AppTheme.tertiaryLabel)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Terminal")
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if session.exited {
            Circle()
                .fill((session.exitCode ?? 0) == 0 ? AppTheme.tertiaryLabel : AppTheme.danger)
                .frame(width: 6, height: 6)
        } else if session.busy {
            Circle()
                .fill(AppTheme.success)
                .frame(width: 6, height: 6)
        } else {
            Image(systemName: "terminal")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.tertiaryLabel)
        }
    }

    private var backgroundFill: Color {
        if isFocused {
            return AppTheme.elevatedCardFill
        }
        if isSelected || isHovering {
            return AppTheme.subtleHoverFill
        }
        return .clear
    }

    private var borderColor: Color {
        if isFocused {
            return AppTheme.accent.opacity(0.45)
        }
        if isSelected {
            return AppTheme.separator
        }
        return .clear
    }
}

private struct ExitCodeBadge: View {
    let exitCode: Int

    var body: some View {
        Text("exit \(exitCode)")
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(exitCode == 0 ? AppTheme.secondaryLabel : AppTheme.danger)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill((exitCode == 0 ? AppTheme.secondaryLabel : AppTheme.danger).opacity(0.14))
            )
    }
}
