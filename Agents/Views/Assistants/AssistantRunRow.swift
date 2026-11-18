import CoincideRemoteKit
import SwiftUI

struct AssistantRunRow: View {
    var record: WorkerRecord
    var assistantName: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)
                    Spacer()
                    AssistantRunStatusBadge(status: AssistantRunStatus.from(runtimeStatus: record.status))
                }
                Text(record.task)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let assistantName, !assistantName.isEmpty {
                        Text(assistantName)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    if !record.provider.isEmpty {
                        Text(record.provider)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    Text("\(record.transcriptItems) updates")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Text(AssistantDashboardFormatting.elapsedLabel(record.elapsedSeconds))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Spacer()
                    if record.isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .fill(isSelected ? AppTheme.accent.opacity(0.12) : AppTheme.elevatedCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .strokeBorder(isSelected ? AppTheme.accent.opacity(0.5) : AppTheme.separator.opacity(0.5), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Run \(record.name), \(record.status)")
    }
}

struct AssistantRunStatusBadge: View {
    var status: AssistantRunStatus

    var body: some View {
        let color: Color
        switch status {
        case .queued: color = AppTheme.secondaryLabel
        case .running: color = AppTheme.accent
        case .awaitingApproval: color = AppTheme.warning
        case .completed: color = AppTheme.success
        case .failed: color = AppTheme.danger
        case .cancelled: color = AppTheme.warning
        case .unknown: color = AppTheme.secondaryLabel
        }
        return Text(status.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .accessibilityLabel("Status \(status.title)")
    }
}

enum AssistantDashboardFormatting {
    static func elapsedLabel(_ seconds: Double) -> String {
        durationLabel(seconds)
    }

    static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 {
            return "\(total)s"
        }
        if total < 3600 {
            return "\(total / 60)m \(total % 60)s"
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    static func dateLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
