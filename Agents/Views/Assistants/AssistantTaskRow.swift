import SwiftUI

public struct AssistantTaskRow: View {
    public let task: AssistantTask
    public let assistantName: String
    public let workspaceName: String

    public init(task: AssistantTask, assistantName: String, workspaceName: String) {
        self.task = task
        self.assistantName = assistantName
        self.workspaceName = workspaceName
    }

    private var statusLabel: String {
        if !task.enabled {
            return "Disabled"
        }
        if task.paused {
            return "Paused"
        }
        if task.lastOutcome == .failed {
            return "Failed"
        }
        if task.lastOutcome == .missed {
            return "Missed"
        }
        return "Active"
    }

    private var statusTint: Color {
        if !task.enabled || task.paused {
            return AppTheme.secondaryLabel
        }
        if task.lastOutcome == .failed {
            return AppTheme.danger
        }
        if task.lastOutcome == .missed {
            return AppTheme.warning
        }
        return AppTheme.success
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.trigger == .timer ? "timer" : "clock.badge.exclamationmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(width: 30, height: 30)
                .background(AppTheme.elevatedCardFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.name.isEmpty ? "Untitled Task" : task.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)

                    Text(statusLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusTint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(statusTint.opacity(0.12), in: Capsule())
                }

                Text(task.schedule.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let nextRun = task.nextRunAt, task.isActive {
                        Text("Next \(AssistantTaskDateFormatting.dateTime(nextRun, timeZoneID: task.schedule.timeZoneID))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.primaryLabel)
                    } else if let lastRun = task.lastRunAt {
                        Text("Last run \(AssistantTaskDateFormatting.dateTime(lastRun, timeZoneID: task.schedule.timeZoneID))")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }

                    if task.runCount > 0 {
                        Text("· \(task.runCount) run\(task.runCount == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                }
                .lineLimit(1)

                Text("\(assistantName) · \(workspaceName)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
    }
}
