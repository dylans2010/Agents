import SwiftUI

public struct ComputerUseSettingsPane: View {
    @Bindable public var appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var controller: ComputerUseController {
        appModel.computerUse
    }

    private var status: ComputerUseStatus? {
        controller.status
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                enableSection
                stateSection
                permissionsSection
                limitsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Computer Use")
        .task {
            await controller.refreshStatus()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Computer Use")
                .font(.title2.bold())
            Text("Lets an agent observe and control apps on this Mac through the real engine: list apps and windows, read accessible elements, click, type, and take screenshots. Actions run only while Computer Use is on and only for threads the engine has granted.")
                .foregroundStyle(.secondary)
        }
    }

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enable")
                .font(.headline)
            Toggle(
                "Computer Use",
                isOn: Binding(
                    get: { status?.enabled ?? false },
                    set: { newValue in
                        Task { await controller.setEnabled(newValue) }
                    }
                )
            )
            .disabled(status == nil || controller.isBusy)
            if let status, !status.nativeCompiled {
                Text("The native computer-use executor is not compiled into this build. Computer Use cannot run here.")
                    .foregroundStyle(.red)
            }
            if let error = status?.error {
                Text(error)
                    .foregroundStyle(.red)
            }
            if let message = controller.lastError {
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }

    private var stateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("State")
                .font(.headline)
            if let status {
                LabeledContent("Enabled", value: status.enabled ? "On" : "Off")
                LabeledContent("Saved setting", value: status.savedEnabled ? "On" : "Off")
                LabeledContent("Native executor", value: status.nativeCompiled ? "Compiled" : "Not compiled")
                LabeledContent("Desktop owner", value: status.desktopOwner ?? "None")
                LabeledContent("Granted threads", value: "\(status.grantedThreads.count)")
                LabeledContent("Active threads", value: "\(status.activeThreads.count)")
                LabeledContent("Stopped", value: status.stopped ? "Yes" : "No")
            } else {
                Text("Status has not loaded yet.")
                    .foregroundStyle(.secondary)
            }
            Button("Refresh Status") {
                Task { await controller.refreshStatus() }
            }
            .disabled(controller.isBusy)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("macOS Permissions")
                .font(.headline)
            Text("Both permissions are granted in System Settings on this Mac. Grant Access opens the system prompt where macOS allows it; if the prompt no longer appears, grant the permission in System Settings › Privacy & Security.")
                .foregroundStyle(.secondary)
            permissionRow(
                title: "Accessibility",
                state: status?.accessibility ?? "unknown",
                granted: status?.accessibilityGranted ?? false,
                kind: "accessibility"
            )
            permissionRow(
                title: "Screen Recording",
                state: status?.screenCapture ?? "unknown",
                granted: status?.screenCaptureGranted ?? false,
                kind: "screen_capture"
            )
            Button("Refresh Permissions") {
                Task { await controller.refreshPermissions() }
            }
            .disabled(controller.isBusy)
        }
    }

    private func permissionRow(title: String, state: String, granted: Bool, kind: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(granted ? "Granted" : state)
                    .foregroundStyle(granted ? .green : .secondary)
            }
            Spacer()
            Button("Grant Access") {
                Task { await controller.requestPermission(kind: kind) }
            }
            .disabled(controller.isBusy || granted)
        }
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Limits")
                .font(.headline)
            Text("Screen recording is not available: the engine has no recording tool and none is offered. Screenshots are saved by the engine as private files, newest 32 per thread. There is no per-action approval dialog: turning Computer Use on and granting a thread is the approval, and every manual action in the app is approved by the button press that starts it.")
                .foregroundStyle(.secondary)
        }
    }
}
