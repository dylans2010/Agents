import AppKit
import CoincideRemoteKit
import SwiftUI

public struct AssistantResultView: View {
    public var report: AssistantReport

    @State private var collapsedFiles: Set<String> = []
    @State private var copyConfirmation: String?

    public init(report: AssistantReport) {
        self.report = report
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                headerCard
                switch report {
                case .review(let review):
                    summarySection(review.summary)
                    findingsSection(review.findings)
                    textListSection("Recommendations", items: review.recommendations, icon: "lightbulb")
                    textListSection("Warnings", items: review.warnings, icon: "exclamationmark.triangle")
                    textListSection("Errors", items: review.errors, icon: "xmark.octagon")
                    textListSection("Next Steps", items: review.nextSteps, icon: "arrow.right.circle")
                    if review.noModificationsConfirmed {
                        noModificationsNote
                    }
                case .build(let build):
                    summarySection(build.summary)
                    textListSection("Actions Taken", items: build.actionsTaken, icon: "hammer")
                    filesChangedSection(build)
                    testsSection(build.testsRun)
                    textListSection("Warnings", items: build.warnings, icon: "exclamationmark.triangle")
                    textListSection("Errors", items: build.errors, icon: "xmark.octagon")
                    textListSection("Next Steps", items: build.nextSteps, icon: "arrow.right.circle")
                case .analysis(let analysis):
                    summarySection(analysis.summary)
                    findingsSection(analysis.findings)
                    evidenceSection(analysis.evidence)
                    textListSection("Recommendations", items: analysis.recommendations, icon: "lightbulb")
                    textListSection("Warnings", items: analysis.warnings, icon: "exclamationmark.triangle")
                    textListSection("Errors", items: analysis.errors, icon: "xmark.octagon")
                    textListSection("Next Steps", items: analysis.nextSteps, icon: "arrow.right.circle")
                    if analysis.noModificationsConfirmed {
                        noModificationsNote
                    }
                }
                toolActivitySection(report.header.toolActivity)
                metadataSection(report.header.metadata)
                if let copyConfirmation {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                        Text(copyConfirmation)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
            }
            .padding(16)
        }
        .background(AppTheme.windowBackground)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copyReport()
                } label: {
                    Label("Copy Report", systemImage: "doc.on.doc")
                }
                .help("Copy the full report as Markdown")
            }
        }
    }

    private var headerCard: some View {
        let header = report.header
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(header.assistantName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                statusBadge(header.status)
                Spacer()
                Text(report.kindLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.elevatedCardFill))
            }
            Text(header.task)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.secondaryLabel)
            HStack(spacing: 12) {
                headerDetail("Category", header.category.displayName)
                headerDetail("Provider", header.provider)
                if let model = header.model {
                    headerDetail("Model", model)
                }
                headerDetail("Started", AssistantReportFormatting.dateLabel(header.startedAt))
                if let duration = header.durationLabel {
                    headerDetail("Duration", duration)
                }
            }
            .font(.system(size: 11.5))
            if let error = header.error, !error.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(AppTheme.danger)
                    Text(error)
                        .foregroundStyle(AppTheme.danger)
                }
                .font(.system(size: 12))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(AppTheme.controlBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .strokeBorder(AppTheme.separator, lineWidth: 0.75)
        )
    }

    private func headerDetail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.tertiaryLabel)
            Text(value)
                .foregroundStyle(AppTheme.primaryLabel)
                .lineLimit(1)
        }
    }

    private func statusBadge(_ status: AssistantReportStatus) -> some View {
        let color: Color
        switch status {
        case .completed: color = AppTheme.success
        case .failed: color = AppTheme.danger
        case .cancelled: color = AppTheme.warning
        case .running: color = AppTheme.accent
        case .unknown: color = AppTheme.secondaryLabel
        }
        return Text(status.displayName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.primaryLabel)
        }
    }

    @ViewBuilder
    private func summarySection(_ summary: String?) -> some View {
        if let summary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Summary", icon: "text.alignleft")
                Text(summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func findingsSection(_ findings: [AssistantFinding]) -> some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Findings", icon: "magnifyingglass")
                ForEach(findings) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        if let severity = finding.severity {
                            Text(severity.displayName)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(severityColor(severity))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(severityColor(severity).opacity(0.14)))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title)
                                .font(.system(size: 12.5))
                                .foregroundStyle(AppTheme.primaryLabel)
                                .textSelection(.enabled)
                            if let detail = finding.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            if let location = finding.locationLabel {
                                Text(location)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }
            }
        }
    }

    func severityColor(_ severity: AssistantFindingSeverity) -> Color {
        switch severity {
        case .critical: return AppTheme.danger
        case .high: return AppTheme.warning
        case .medium: return AppTheme.warning
        case .low: return AppTheme.info
        case .info: return AppTheme.secondaryLabel
        }
    }

    @ViewBuilder
    private func evidenceSection(_ evidence: [AssistantEvidence]) -> some View {
        if !evidence.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Evidence", icon: "doc.text.magnifyingglass")
                ForEach(evidence) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        if let location = item.locationLabel {
                            Text(location)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.accent)
                        }
                        Text(item.snippet)
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .textSelection(.enabled)
                        if let note = item.note, !note.isEmpty {
                            Text(note)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func textListSection(_ title: String, items: [String], icon: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle(title, icon: icon)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundStyle(AppTheme.tertiaryLabel)
                        Text(item)
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var noModificationsNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(AppTheme.success)
            Text("No workspace modifications were made by this run.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
    }

    @ViewBuilder
    private func filesChangedSection(_ build: AssistantBuildReport) -> some View {
        switch build.diffAvailability {
        case .attached:
            if !build.filesChanged.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        sectionTitle("Files Changed", icon: "arrow.triangle.branch")
                        Spacer()
                        Text("+\(build.totalAdditions) −\(build.totalDeletions)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    ForEach(build.filesChanged) { file in
                        AssistantDiffFileCard(
                            file: file,
                            isCollapsed: collapsedFiles.contains(file.path),
                            onToggleCollapse: {
                                if collapsedFiles.contains(file.path) {
                                    collapsedFiles.remove(file.path)
                                } else {
                                    collapsedFiles.insert(file.path)
                                }
                            },
                            onCopyPatch: { copyPatch(for: file) }
                        )
                    }
                }
            }
        case .confirmedNoChanges:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(AppTheme.success)
                Text("No files were changed by this run.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
        case .unavailable(let reason):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Changed files unavailable")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    if !build.header.targetFiles.isEmpty {
                        Text("Files this run was asked to touch: \(build.header.targetFiles.joined(separator: ", "))")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func testsSection(_ tests: [AssistantTestResult]) -> some View {
        if !tests.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Tests Run", icon: "checkmark.seal")
                ForEach(tests) { test in
                    HStack(spacing: 6) {
                        Image(systemName: testIcon(test.outcome))
                            .foregroundStyle(testColor(test.outcome))
                        Text(test.name)
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppTheme.primaryLabel)
                        Text(test.outcome.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(testColor(test.outcome))
                        if let detail = test.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                    }
                }
            }
        }
    }

    private func testIcon(_ outcome: AssistantTestOutcome) -> String {
        switch outcome {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private func testColor(_ outcome: AssistantTestOutcome) -> Color {
        switch outcome {
        case .passed: return AppTheme.success
        case .failed: return AppTheme.danger
        case .skipped: return AppTheme.warning
        case .unknown: return AppTheme.secondaryLabel
        }
    }

    @ViewBuilder
    private func toolActivitySection(_ activities: [AssistantToolActivity]) -> some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Tool Activity", icon: "wrench.and.screwdriver")
                ForEach(activities) { activity in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: toolCategoryIcon(activity.category))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(activity.title)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                    .lineLimit(2)
                                if let status = activity.status {
                                    Text(status)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(toolStatusColor(status))
                                }
                            }
                            if let detail = activity.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
        }
    }

    private func toolCategoryIcon(_ category: String?) -> String {
        switch category?.lowercased() {
        case "command": return "terminal"
        case "filechange": return "pencil.and.scribble"
        case "read": return "doc.text"
        case "search": return "magnifyingglass"
        case "web": return "globe"
        case "mcp": return "server.rack"
        case "task": return "list.bullet"
        case "todo": return "checklist"
        default: return "wrench"
        }
    }

    private func toolStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed": return AppTheme.success
        case "failed": return AppTheme.danger
        case "running": return AppTheme.accent
        case "declined", "waiting": return AppTheme.warning
        default: return AppTheme.secondaryLabel
        }
    }

    @ViewBuilder
    private func metadataSection(_ metadata: [AssistantReportMetadataEntry]) -> some View {
        if !metadata.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                ForEach(metadata) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.key)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .frame(width: 110, alignment: .leading)
                        Text(entry.value)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.markdownRepresentation, forType: .string)
        copyConfirmation = "Report copied"
    }

    private func copyPatch(for file: RemoteDiff.File) {
        let oldHeader = file.oldPath ?? file.path
        let text = file.patch.isEmpty
            ? file.path
            : "diff --git a/\(oldHeader) b/\(file.path)\n--- a/\(oldHeader)\n+++ b/\(file.path)\n" + file.patch
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyConfirmation = "Patch copied"
    }
}

private struct AssistantDiffFileCard: View {
    let file: RemoteDiff.File
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onCopyPatch: () -> Void

    private var parsedLines: [RemoteDiffParsing.Line] {
        guard !file.patch.isEmpty else { return [] }
        return RemoteDiffParsing.lines(of: file.patch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onToggleCollapse) {
                    HStack(spacing: 5) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .frame(width: 10)
                        Image(systemName: statusIcon)
                            .font(.system(size: 11.5))
                            .foregroundStyle(statusTint)
                        if let old = file.oldPath, old != file.path {
                            Text("\(old) → \(file.path)")
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.primaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(file.path)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.primaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                if !file.isBinary {
                    HStack(spacing: 4) {
                        if file.additions > 0 {
                            Text("+\(file.additions)")
                                .foregroundStyle(AppTheme.diffAdditionText)
                        }
                        if file.deletions > 0 {
                            Text("−\(file.deletions)")
                                .foregroundStyle(AppTheme.diffDeletionText)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                if !file.patch.isEmpty {
                    Button(action: onCopyPatch) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Patch")
                    .accessibilityLabel("Copy patch")
                    .foregroundStyle(AppTheme.secondaryLabel)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppTheme.controlBackground.opacity(0.9))

            if !isCollapsed {
                Divider()
                if file.isBinary {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.zipper")
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Text("Binary file changed.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                    }
                    .padding(12)
                } else if parsedLines.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.plaintext")
                            .foregroundStyle(AppTheme.tertiaryLabel)
                        Text("No inline patch hunks.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                    }
                    .padding(10)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(parsedLines) { line in
                                AssistantDiffLineRow(line: line)
                            }
                        }
                        .padding(.vertical, 2)
                        .frame(minWidth: 320, alignment: .leading)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall + 2)
                .fill(AppTheme.codeBlockBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall + 2)
                .strokeBorder(AppTheme.separator, lineWidth: 0.85)
        )
    }

    private var statusIcon: String {
        switch file.status.lowercased() {
        case "added", "a": return "plus.square.fill"
        case "deleted", "d": return "minus.square.fill"
        case "renamed", "r": return "arrow.right.square.fill"
        case "untracked", "?", "??": return "questionmark.square.fill"
        default: return "pencil.square.fill"
        }
    }

    private var statusTint: Color {
        switch file.status.lowercased() {
        case "added", "a": return AppTheme.success
        case "deleted", "d": return AppTheme.danger
        case "renamed", "r": return AppTheme.info
        case "untracked", "?", "??": return AppTheme.secondaryLabel
        default: return AppTheme.warning
        }
    }
}

private struct AssistantDiffLineRow: View {
    let line: RemoteDiffParsing.Line

    private var marker: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "−"
        case .hunk: "@@"
        case .note: "\\"
        case .context: " "
        }
    }

    private var rowBackground: Color {
        switch line.kind {
        case .addition: AppTheme.diffAdditionBackground
        case .deletion: AppTheme.diffDeletionBackground
        case .hunk: AppTheme.diffHunkHeaderBackground
        case .note: AppTheme.elevatedCardFill
        case .context: Color.clear
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .addition: AppTheme.diffAdditionText
        case .deletion: AppTheme.diffDeletionText
        case .hunk: AppTheme.info
        case .note: AppTheme.tertiaryLabel
        case .context: AppTheme.primaryLabel.opacity(0.9)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if line.kind == .hunk {
                Text("⋯")
                    .font(AppTheme.codeFont(size: 10.5))
                    .foregroundStyle(AppTheme.info.opacity(0.85))
                    .frame(width: 72, alignment: .center)
                    .padding(.vertical, 2.5)
                Text(line.text)
                    .font(AppTheme.codeFont(size: 11.0))
                    .foregroundStyle(AppTheme.info)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
            } else {
                HStack(spacing: 2) {
                    Text(line.oldLine.map(String.init) ?? "")
                        .frame(width: 32, alignment: .trailing)
                    Text(line.newLine.map(String.init) ?? "")
                        .frame(width: 32, alignment: .trailing)
                }
                .font(AppTheme.codeFont(size: 10.5))
                .foregroundStyle(AppTheme.tertiaryLabel)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)

                Rectangle()
                    .fill(AppTheme.separator.opacity(0.45))
                    .frame(width: 0.75)

                Text(marker)
                    .font(AppTheme.codeFont(size: 11.5))
                    .foregroundStyle(textColor)
                    .frame(width: 16, alignment: .center)
                    .padding(.vertical, 1.5)

                Text(line.text.isEmpty ? " " : line.text)
                    .font(AppTheme.codeFont(size: 11.5))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(.trailing, 10)
                    .padding(.vertical, 1.5)
            }
            Spacer(minLength: 0)
        }
        .background(rowBackground)
    }
}
