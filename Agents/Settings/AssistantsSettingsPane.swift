import AppKit
import CoincideRemoteKit
import SwiftUI

public struct AssistantsSettingsPane: View {
    @Bindable public var appModel: AppModel
    @State private var notificationSettings = AssistantNotificationSettings.shared

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var activeScheduledTasks: [RemoteScheduledTask] {
        appModel.scheduledTasks.tasks.filter { !$0.isPaused }
    }

    private var nextScheduledRun: Date? {
        activeScheduledTasks.compactMap(\.nextRunAt).min()
    }

    public var body: some View {
        Form {
            notificationSection
            automationSection
        }
        .formStyle(.grouped)
        .navigationTitle("Assistants")
        .task {
            await appModel.refreshScheduledTasks()
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("Notify me about assistant runs", isOn: $notificationSettings.isEnabled)

            ForEach(AssistantNotificationCategory.allCases, id: \.self) { category in
                Toggle(
                    isOn: Binding(
                        get: { notificationSettings.isCategoryEnabled(category) && notificationSettings.isEnabled },
                        set: { notificationSettings.setCategoryEnabled($0, for: category) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                        Text(category.detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
                .disabled(!notificationSettings.isEnabled)
            }
        } header: {
            Text("Assistant Notifications")
        } footer: {
            Text("Notifications appear only while Agents is in the background. Activating one opens the run it refers to. Each run posts at most one notification per event.")
        }
    }

    private var automationSection: some View {
        Section {
            LabeledContent("Scheduled Tasks") {
                Text("\(activeScheduledTasks.count) active of \(appModel.scheduledTasks.tasks.count)")
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            if let nextRun = nextScheduledRun {
                LabeledContent("Next Scheduled Run") {
                    Text(nextRun, style: .relative)
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }

            Button("Open Schedules") {
                appModel.openInspector(tab: .schedules)
            }
            .controlSize(.small)
        } header: {
            Text("Automation")
        } footer: {
            Text("A finished turn on a thread with active schedules posts an automation notification. Pause or edit individual schedules in the Schedules inspector; there is no global automation switch because the scheduler reads each schedule's own paused state.")
        }
    }
}
