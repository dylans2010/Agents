import CoincideRemoteKit
import Foundation

public enum AssistantReportStatus: String, Codable, Hashable, Sendable {
    case completed
    case failed
    case cancelled
    case running
    case unknown

    public init(workerStatus: String) {
        switch workerStatus.lowercased() {
        case "completed": self = .completed
        case "failed": self = .failed
        case "cancelled": self = .cancelled
        case "running": self = .running
        default: self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .running: return "Running"
        case .unknown: return "Unknown"
        }
    }
}

public enum AssistantFindingSeverity: String, Codable, Hashable, Sendable, CaseIterable {
    case critical
    case high
    case medium
    case low
    case info

    public init?(label: String) {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "critical": self = .critical
        case "high": self = .high
        case "medium": self = .medium
        case "low": self = .low
        case "info", "note": self = .info
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .info: return "Info"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        case .info: return 4
        }
    }
}

public struct AssistantFinding: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var severity: AssistantFindingSeverity?
    public var title: String
    public var detail: String?
    public var file: String?
    public var line: Int?

    public init(
        id: UUID = UUID(), severity: AssistantFindingSeverity? = nil, title: String,
        detail: String? = nil, file: String? = nil, line: Int? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.file = file
        self.line = line
    }

    public var locationLabel: String? {
        guard let file else { return nil }
        if let line { return "\(file):\(line)" }
        return file
    }
}

public struct AssistantEvidence: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var file: String?
    public var line: Int?
    public var snippet: String
    public var note: String?

    public init(id: UUID = UUID(), file: String? = nil, line: Int? = nil, snippet: String, note: String? = nil) {
        self.id = id
        self.file = file
        self.line = line
        self.snippet = snippet
        self.note = note
    }

    public var locationLabel: String? {
        guard let file else { return nil }
        if let line { return "\(file):\(line)" }
        return file
    }
}

public enum AssistantTestOutcome: String, Codable, Hashable, Sendable {
    case passed
    case failed
    case skipped
    case unknown

    public var displayName: String {
        switch self {
        case .passed: return "Passed"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        case .unknown: return "Unknown"
        }
    }
}

public struct AssistantTestResult: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var outcome: AssistantTestOutcome
    public var detail: String?

    public init(id: UUID = UUID(), name: String, outcome: AssistantTestOutcome = .unknown, detail: String? = nil) {
        self.id = id
        self.name = name
        self.outcome = outcome
        self.detail = detail
    }
}

public struct AssistantToolActivity: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var category: String?
    public var status: String?
    public var detail: String?

    public init(id: UUID = UUID(), title: String, category: String? = nil, status: String? = nil, detail: String? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.status = status
        self.detail = detail
    }

    public init(item: RemoteItem) {
        let firstLine = item.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        self.init(
            id: item.id,
            title: item.kind == .tool
                ? Self.displayTitle(for: item)
                : (item.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? firstLine),
            category: item.category,
            status: item.status,
            detail: item.detail
        )
    }

    public static func displayTitle(for item: RemoteItem) -> String {
        if item.kind == .tool {
            if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty, !isRawToolIdentifier(title) {
                return title
            }
            return "Tool activity"
        }
        return item.title ?? item.text
    }

    public static func isRawToolIdentifier(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else { return false }
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "_-.:"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

public struct AssistantReportMetadataEntry: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var value: String

    public var id: String { key }

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public enum AssistantDiffAvailability: Codable, Hashable, Sendable {
    case attached
    case confirmedNoChanges
    case unavailable(reason: String)

    public var unavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

public struct AssistantReportHeader: Codable, Hashable, Sendable {
    public var assistantID: String
    public var assistantName: String
    public var category: AssistantCategory
    public var runID: String
    public var runName: String
    public var task: String
    public var parentThreadID: String
    public var workerThreadID: String
    public var provider: String
    public var model: String?
    public var startedAt: Date
    public var durationSeconds: Double?
    public var status: AssistantReportStatus
    public var error: String?
    public var targetFiles: [String]
    public var transcriptItems: Int
    public var toolActivity: [AssistantToolActivity]
    public var metadata: [AssistantReportMetadataEntry]

    public init(
        assistantID: String, assistantName: String, category: AssistantCategory, runID: String, runName: String,
        task: String, parentThreadID: String, workerThreadID: String, provider: String, model: String?,
        startedAt: Date, durationSeconds: Double?, status: AssistantReportStatus, error: String?,
        targetFiles: [String], transcriptItems: Int, toolActivity: [AssistantToolActivity],
        metadata: [AssistantReportMetadataEntry]
    ) {
        self.assistantID = assistantID
        self.assistantName = assistantName
        self.category = category
        self.runID = runID
        self.runName = runName
        self.task = task
        self.parentThreadID = parentThreadID
        self.workerThreadID = workerThreadID
        self.provider = provider
        self.model = model
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.status = status
        self.error = error
        self.targetFiles = targetFiles
        self.transcriptItems = transcriptItems
        self.toolActivity = toolActivity
        self.metadata = metadata
    }

    public var durationLabel: String? {
        guard let durationSeconds else { return nil }
        return AssistantReportFormatting.durationLabel(durationSeconds)
    }
}

public struct AssistantReviewReport: Codable, Hashable, Sendable {
    public var header: AssistantReportHeader
    public var summary: String?
    public var findings: [AssistantFinding]
    public var recommendations: [String]
    public var warnings: [String]
    public var errors: [String]
    public var nextSteps: [String]
    public var noModificationsConfirmed: Bool

    public init(
        header: AssistantReportHeader, summary: String? = nil, findings: [AssistantFinding] = [],
        recommendations: [String] = [], warnings: [String] = [], errors: [String] = [],
        nextSteps: [String] = [], noModificationsConfirmed: Bool = false
    ) {
        self.header = header
        self.summary = summary
        self.findings = findings
        self.recommendations = recommendations
        self.warnings = warnings
        self.errors = errors
        self.nextSteps = nextSteps
        self.noModificationsConfirmed = noModificationsConfirmed
    }
}

public struct AssistantBuildReport: Codable, Hashable, Sendable {
    public var header: AssistantReportHeader
    public var summary: String?
    public var actionsTaken: [String]
    public var filesChanged: [RemoteDiff.File]
    public var diffAvailability: AssistantDiffAvailability
    public var testsRun: [AssistantTestResult]
    public var warnings: [String]
    public var errors: [String]
    public var nextSteps: [String]

    public init(
        header: AssistantReportHeader, summary: String? = nil, actionsTaken: [String] = [],
        filesChanged: [RemoteDiff.File] = [], diffAvailability: AssistantDiffAvailability,
        testsRun: [AssistantTestResult] = [], warnings: [String] = [], errors: [String] = [],
        nextSteps: [String] = []
    ) {
        self.header = header
        self.summary = summary
        self.actionsTaken = actionsTaken
        self.filesChanged = filesChanged
        self.diffAvailability = diffAvailability
        self.testsRun = testsRun
        self.warnings = warnings
        self.errors = errors
        self.nextSteps = nextSteps
    }

    public var totalAdditions: Int { filesChanged.reduce(0) { $0 + $1.additions } }
    public var totalDeletions: Int { filesChanged.reduce(0) { $0 + $1.deletions } }
}

public struct AssistantAnalysisReport: Codable, Hashable, Sendable {
    public var header: AssistantReportHeader
    public var summary: String?
    public var findings: [AssistantFinding]
    public var evidence: [AssistantEvidence]
    public var recommendations: [String]
    public var warnings: [String]
    public var errors: [String]
    public var nextSteps: [String]
    public var noModificationsConfirmed: Bool

    public init(
        header: AssistantReportHeader, summary: String? = nil, findings: [AssistantFinding] = [],
        evidence: [AssistantEvidence] = [], recommendations: [String] = [], warnings: [String] = [],
        errors: [String] = [], nextSteps: [String] = [], noModificationsConfirmed: Bool = false
    ) {
        self.header = header
        self.summary = summary
        self.findings = findings
        self.evidence = evidence
        self.recommendations = recommendations
        self.warnings = warnings
        self.errors = errors
        self.nextSteps = nextSteps
        self.noModificationsConfirmed = noModificationsConfirmed
    }
}

public enum AssistantReport: Codable, Hashable, Sendable, Identifiable {
    case review(AssistantReviewReport)
    case build(AssistantBuildReport)
    case analysis(AssistantAnalysisReport)

    public var id: String { header.runID }

    public var header: AssistantReportHeader {
        switch self {
        case .review(let report): return report.header
        case .build(let report): return report.header
        case .analysis(let report): return report.header
        }
    }

    public var kindLabel: String {
        switch self {
        case .review: return "Review"
        case .build: return "Build"
        case .analysis: return "Analysis"
        }
    }
}

public enum AssistantReportFormatting {
    public static func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    public static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

extension AssistantReport {
    public var markdownRepresentation: String {
        var lines: [String] = []
        let header = self.header
        lines.append("# \(header.assistantName) — \(kindLabel) Report")
        lines.append("")
        lines.append("- Run: \(header.runName) (\(header.runID))")
        lines.append("- Status: \(header.status.displayName)")
        lines.append("- Provider: \(header.provider)\(header.model.map { " · \($0)" } ?? "")")
        lines.append("- Started: \(AssistantReportFormatting.dateLabel(header.startedAt))")
        if let duration = header.durationLabel {
            lines.append("- Duration: \(duration)")
        }
        lines.append("- Task: \(header.task)")
        switch self {
        case .review(let report):
            appendSummary(report.summary, to: &lines)
            appendFindings(report.findings, to: &lines)
            appendList("Recommendations", report.recommendations, to: &lines)
            appendList("Warnings", report.warnings, to: &lines)
            appendList("Errors", report.errors, to: &lines)
            appendList("Next Steps", report.nextSteps, to: &lines)
            if report.noModificationsConfirmed {
                lines.append("")
                lines.append("No workspace modifications were made by this run.")
            }
        case .build(let report):
            appendSummary(report.summary, to: &lines)
            appendList("Actions Taken", report.actionsTaken, to: &lines)
            if !report.filesChanged.isEmpty {
                lines.append("")
                lines.append("## Files Changed")
                for file in report.filesChanged {
                    lines.append("- \(file.path) (+\(file.additions) −\(file.deletions), \(file.status))")
                }
            }
            if let reason = report.diffAvailability.unavailableReason {
                lines.append("")
                lines.append("Changed files unavailable: \(reason)")
            }
            if report.diffAvailability == .confirmedNoChanges {
                lines.append("")
                lines.append("No files were changed by this run.")
            }
            if !report.testsRun.isEmpty {
                lines.append("")
                lines.append("## Tests Run")
                for test in report.testsRun {
                    lines.append("- \(test.outcome.displayName): \(test.name)")
                }
            }
            appendList("Warnings", report.warnings, to: &lines)
            appendList("Errors", report.errors, to: &lines)
            appendList("Next Steps", report.nextSteps, to: &lines)
        case .analysis(let report):
            appendSummary(report.summary, to: &lines)
            appendFindings(report.findings, to: &lines)
            if !report.evidence.isEmpty {
                lines.append("")
                lines.append("## Evidence")
                for item in report.evidence {
                    if let location = item.locationLabel {
                        lines.append("- \(location): \(item.snippet)")
                    } else {
                        lines.append("- \(item.snippet)")
                    }
                }
            }
            appendList("Recommendations", report.recommendations, to: &lines)
            appendList("Warnings", report.warnings, to: &lines)
            appendList("Errors", report.errors, to: &lines)
            appendList("Next Steps", report.nextSteps, to: &lines)
            if report.noModificationsConfirmed {
                lines.append("")
                lines.append("No workspace modifications were made by this run.")
            }
        }
        if !header.toolActivity.isEmpty {
            lines.append("")
            lines.append("## Tool Activity")
            for activity in header.toolActivity {
                let status = activity.status.map { " (\($0))" } ?? ""
                lines.append("- \(activity.title)\(status)")
            }
        }
        lines.append("")
        lines.append("## Metadata")
        for entry in header.metadata {
            lines.append("- \(entry.key): \(entry.value)")
        }
        return lines.joined(separator: "\n")
    }

    private func appendSummary(_ summary: String?, to lines: inout [String]) {
        guard let summary, !summary.isEmpty else { return }
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append(summary)
    }

    private func appendFindings(_ findings: [AssistantFinding], to lines: inout [String]) {
        guard !findings.isEmpty else { return }
        lines.append("")
        lines.append("## Findings")
        for finding in findings {
            var prefix = "- "
            if let severity = finding.severity {
                prefix += "\(severity.displayName): "
            }
            if let location = finding.locationLabel {
                prefix += "\(location) — "
            }
            lines.append(prefix + finding.title)
        }
    }

    private func appendList(_ title: String, _ items: [String], to lines: inout [String]) {
        guard !items.isEmpty else { return }
        lines.append("")
        lines.append("## \(title)")
        for item in items {
            lines.append("- \(item)")
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
