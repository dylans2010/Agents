import AppKit
import SwiftUI

struct ComputerUseInspectorView: View {
    @Bindable var appModel: AppModel
    var refreshToken: UUID

    @State private var selectedToolName: String = "list_apps"
    @State private var argumentsText: String = "{}"
    @State private var screenshots: [ComputerUseScreenshot] = []
    @State private var selectedScreenshot: ComputerUseScreenshot?
    @State private var isLoadingScreenshots: Bool = false
    @State private var errorText: String?

    private var controller: ComputerUseController {
        appModel.computerUse
    }

    private var computerUseTools: [SystemToolDefinition] {
        SystemToolRegistry.systemTools.filter { $0.action == "computer_use.request" }
    }

    private var selectedTool: SystemToolDefinition? {
        computerUseTools.first { $0.name == selectedToolName }
    }

    private var threadId: String? {
        appModel.selectedThreadID
    }

    private var status: ComputerUseStatus? {
        controller.status
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusBanner
                runToolSection
                resultSection
                screenshotsSection
                historySection
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await controller.refreshStatus()
            await reloadScreenshots()
        }
        .onChange(of: refreshToken) { _, _ in
            Task {
                await controller.refreshStatus()
                await reloadScreenshots()
            }
        }
        .onChange(of: appModel.selectedThreadID) { _, _ in
            Task { await reloadScreenshots() }
        }
    }

    private var statusBanner: some View {
        Group {
            if let status {
                if !status.enabled {
                    banner(text: "Computer Use is off. Turn it on in Settings › Computer Use before running a tool.", tone: .orange)
                } else if !status.accessibilityGranted || !status.screenCaptureGranted {
                    let missing = [
                        status.accessibilityGranted ? nil : "Accessibility",
                        status.screenCaptureGranted ? nil : "Screen Recording",
                    ].compactMap { $0 }.joined(separator: " and ")
                    banner(text: "Computer Use is on, but \(missing) permission is not granted. Grant it in Settings › Computer Use.", tone: .orange)
                } else if !status.nativeCompiled {
                    banner(text: "The native computer-use executor is not compiled into this build.", tone: .red)
                } else {
                    banner(text: "Computer Use is on. Granted threads: \(status.grantedThreads.count). Active threads: \(status.activeThreads.count).", tone: .green)
                }
            } else {
                banner(text: "Computer Use status has not loaded yet.", tone: .secondary)
            }
        }
    }

    private func banner(text: String, tone: Color) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(tone)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var runToolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run a Tool")
                .font(.headline)
            if threadId == nil {
                Text("Select a thread first. Computer Use actions belong to the selected thread.")
                    .foregroundStyle(.secondary)
            }
            Picker("Tool", selection: $selectedToolName) {
                ForEach(computerUseTools, id: \.name) { tool in
                    Text(tool.name).tag(tool.name)
                }
            }
            if let tool = selectedTool {
                Text(tool.description)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                let required = tool.parameters.filter { $0.required && $0.name != "threadId" }
                if !required.isEmpty {
                    Text("Required: " + required.map { "\($0.name) (\($0.type))" }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            Text("Arguments (JSON object, without threadId)")
                .font(.callout)
            TextEditor(text: $argumentsText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            Button("Run") {
                Task { await runSelectedTool() }
            }
            .disabled(threadId == nil || controller.isBusy || status?.enabled != true)
        }
    }

    private func runSelectedTool() async {
        guard let threadId else { return }
        guard let data = argumentsText.data(using: .utf8),
              let arguments = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            errorText = "Arguments are not valid JSON."
            return
        }
        errorText = nil
        await controller.runTool(tool: selectedToolName, threadId: threadId, arguments: arguments)
        await reloadScreenshots()
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest Result")
                .font(.headline)
            if let record = controller.history.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(record.tool) · \(record.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.callout.bold())
                    if let error = record.error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    } else if let result = record.result {
                        Text(ComputerUseController.prettyJSON(result))
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    } else if record.timedOut {
                        Text("Timed out waiting for the engine.")
                            .foregroundStyle(.red)
                            .font(.callout)
                    } else {
                        Text("No result yet.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
            } else {
                Text("No computer-use actions have run in this session yet.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    private var screenshotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Screenshots")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task { await reloadScreenshots() }
                }
                .disabled(isLoadingScreenshots || threadId == nil)
            }
            if let selectedScreenshot,
               let image = controller.loadScreenshot(selectedScreenshot) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
                Text(selectedScreenshot.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if screenshots.isEmpty {
                Text(threadId == nil ? "Select a thread to list its screenshots." : "No screenshots filed for this thread yet. Run get_window_state or get_desktop_state with include_screenshot to take one.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(screenshots) { screenshot in
                    Button {
                        selectedScreenshot = screenshot
                    } label: {
                        HStack(spacing: 8) {
                            if let image = controller.loadScreenshot(screenshot) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 72, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(screenshot.name)
                                    .font(.callout)
                                Text(screenshot.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func reloadScreenshots() async {
        guard let threadId else {
            screenshots = []
            return
        }
        isLoadingScreenshots = true
        defer { isLoadingScreenshots = false }
        screenshots = await controller.listScreenshots(threadId: threadId)
        if let selectedScreenshot, !screenshots.contains(where: { $0.path == selectedScreenshot.path }) {
            self.selectedScreenshot = nil
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action History")
                .font(.headline)
            if controller.history.isEmpty {
                Text("No computer-use actions have run in this session yet.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(controller.history) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(record.tool) · \(record.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.callout.bold())
                        if let error = record.error {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.callout)
                        } else if record.result != nil {
                            Text("Completed.")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
            }
        }
    }
}
