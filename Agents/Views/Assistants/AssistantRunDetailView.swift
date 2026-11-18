import AppKit
import CoincideRemoteKit
import SwiftUI

struct AssistantRunDetailView: View {
    @Bindable var viewModel: AssistantDashboardViewModel
    var detail: AssistantRunDetail

    @State private var outputExpanded = false
    @State private var changesExpanded = false
    @State private var collapsedDiffPaths: Set<String> = []

    private var record: WorkerRecord { detail.record }
    private var controls: Set<AssistantRunControl> {
        AssistantDashboardViewModel.availableControls(for: record, projectPath: detail.projectPath, isOrphan: detail.isOrphan)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerSection
                    controlsSection(proxy: proxy)
                    if let notice = viewModel.detailNotice {
                        Text(notice)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    metaSection
                    if record.isRunning {
                        progressSection
                    }
                    if detail.outputText != nil || record.isRunning {
                        outputSection(detail.outputText)
                            .id("output")
                    }
                    if !detail.toolExecutions.isEmpty {
                        toolExecutionsSection
                    }
                    if !detail.targetFiles.isEmpty || !detail.changedFiles.isEmpty {
                        filesSection
                    }
                    if let gitState = detail.gitState, gitState.isRepository {
                        gitSection(gitState)
                    }
                    if let diff = detail.diff, !diff.files.isEmpty {
                        diffSection(diff)
                            .id("changes")
                    }
                    if detail.pendingApprovals > 0 || !detail.approvalItems.isEmpty {
                        approvalsSection
                    }
                    if let transcript = detail.transcript, !transcript.items.isEmpty {
                        activitySection(transcript)
                    }
                    if let error = record.error, !error.isEmpty {
                        errorSection(error)
                    }
                }
                .padding(12)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(record.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Spacer()
                AssistantRunStatusBadge(status: detail.status)
            }
            Text(record.task)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.primaryLabel)
            if detail.isOrphan {
                Text("Parent thread no longer exists.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.warning)
            }
        }
    }

    private func controlsSection(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            if controls.contains(.openThread) {
                Button("Open Thread") {
                    viewModel.openRunThread(record)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if controls.contains(.cancel) {
                Button("Cancel Run") {
                    Task { await viewModel.cancelRun(record) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.cancellingIDs.contains(record.id))
            }
            if controls.contains(.retry) {
                Button("Retry Run") {
                    Task { await viewModel.retryRun(record) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.retryingIDs.contains(record.id))
            }
            if controls.contains(.viewOutput) && (detail.outputText != nil || detail.transcript != nil) {
                Button("View Output") {
                    outputExpanded = true
                    proxy.scrollTo("output", anchor: .top)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if controls.contains(.reviewChanges) && detail.diff.map({ !$0.files.isEmpty }) == true {
                Button("Review Changes") {
                    changesExpanded = true
                    proxy.scrollTo("changes", anchor: .top)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if controls.contains(.openWorkspace) {
                Button("Open Workspace") {
                    openWorkspace()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func openWorkspace() {
        guard let path = detail.projectPath, !path.isEmpty else { return }
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let assistantName = detail.assistantName {
                metaRow(label: "Assistant", value: assistantName)
            }
            if let providerName = detail.providerName {
                metaRow(label: "Provider", value: providerName)
            }
            if let modelName = detail.modelName {
                metaRow(label: "Model", value: modelName)
            }
            if let projectName = detail.projectName {
                metaRow(label: "Workspace", value: projectName)
            }
            if let projectPath = detail.projectPath {
                metaRow(label: "Path", value: projectPath)
            }
            if let branch = detail.branch, !branch.isEmpty {
                metaRow(label: "Branch", value: branch)
            }
            if let startedAt = detail.startedAt {
                metaRow(label: "Started", value: AssistantDashboardFormatting.dateLabel(startedAt))
            }
            if let endedAt = detail.endedAt {
                metaRow(label: "Ended", value: AssistantDashboardFormatting.dateLabel(endedAt))
            }
            if let duration = detail.durationSeconds {
                metaRow(label: "Duration", value: AssistantDashboardFormatting.durationLabel(duration))
            }
            metaRow(label: "Updates", value: "\(record.transcriptItems)")
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.primaryLabel)
                .textSelection(.enabled)
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Progress")
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 12, height: 12)
                if let stage = record.progress?.stage, !stage.isEmpty {
                    Text(stage.capitalized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                Text("\(record.transcriptItems) updates")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(AssistantDashboardFormatting.elapsedLabel(record.elapsedSeconds))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
        }
    }

    private func outputSection(_ output: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Output")
            if record.isRunning && output == nil {
                Text("No result yet — the run is still working.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            } else if output == nil {
                Text("Completed with no text reply.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            } else if let output {
                Text(outputExpanded ? output : Self.truncatedOutput(output))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.primaryLabel)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if Self.isOutputTruncated(output) {
                    Button(outputExpanded ? "Show less" : "Show full output") {
                        outputExpanded.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                }
            }
        }
    }

    private var toolExecutionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Tool Executions")
            ForEach(detail.toolExecutions) { item in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activityText(for: item))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .lineLimit(2)
                        if let category = item.category, !category.isEmpty {
                            Text(category)
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        if let detailText = item.detail, !detailText.isEmpty {
                            Text(detailText)
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if let status = item.status, !status.isEmpty {
                        Text(status.capitalized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(toolStatusColor(status))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func toolStatusColor(_ status: String) -> Color {
        switch status {
        case "running", "waiting": return AppTheme.accent
        case "completed": return AppTheme.success
        case "failed": return AppTheme.danger
        case "declined": return AppTheme.warning
        default: return AppTheme.secondaryLabel
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Files Modified")
            if !detail.targetFiles.isEmpty {
                Text(detail.targetFiles.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            ForEach(detail.changedFiles) { file in
                HStack(spacing: 8) {
                    Text(file.path)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.primaryLabel)
                    Text(file.status)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Spacer()
                    if file.additions > 0 || file.deletions > 0 {
                        Text("+\(file.additions) −\(file.deletions)")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
            }
        }
    }

    private func gitSection(_ gitState: RemoteGitState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Git Changes")
            if let branch = gitState.branch, !branch.isEmpty {
                metaRow(label: "Branch", value: branch)
            }
            metaRow(label: "Ahead / Behind", value: "\(gitState.ahead) / \(gitState.behind)")
            metaRow(label: "Changed Files", value: "\(gitState.changedFiles)")
            if let upstream = gitState.upstream, !upstream.isEmpty {
                metaRow(label: "Upstream", value: upstream)
            }
        }
    }

    private func diffSection(_ diff: RemoteDiff) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                sectionTitle("Changes")
                Spacer()
                Button(changesExpanded ? "Hide Patches" : "Show Patches") {
                    changesExpanded.toggle()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
            }
            if diff.isTruncated {
                Text("Some files were left out to keep the message small.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            ForEach(diff.files) { file in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(file.path)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.primaryLabel)
                        Text(file.status)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer()
                        Text("+\(file.additions) −\(file.deletions)")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    if changesExpanded && !file.patch.isEmpty {
                        Text(file.patch)
                            .font(AppTheme.codeFont(size: 11))
                            .foregroundStyle(AppTheme.primaryLabel)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .fill(AppTheme.codeBlockBackground)
                            )
                    }
                }
            }
        }
    }

    private var approvalsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Approvals")
            if detail.pendingApprovals > 0 {
                Text("\(detail.pendingApprovals) approval\(detail.pendingApprovals == 1 ? "" : "s") waiting in the conversation.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.warning)
            }
            ForEach(detail.approvalItems) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? item.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(2)
                    if let approval = item.approval {
                        if let resolution = approval.resolution, !resolution.isEmpty {
                            Text("Resolved: \(resolution)")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        } else {
                            Text("Options: \(approval.options.map(\.label).joined(separator: ", "))")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                    }
                }
            }
            Text("Approvals are answered in the conversation thread.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
    }

    private func activitySection(_ transcript: RemoteTranscript) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Activity")
            ForEach(transcript.items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.kind.rawValue.capitalized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .frame(width: 72, alignment: .leading)
                    Text(activityText(for: item))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(3)
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func activityText(for item: RemoteItem) -> String {
        AssistantToolActivity.displayTitle(for: item)
    }

    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Error")
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.warning)
                .textSelection(.enabled)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.primaryLabel)
    }

    private static let outputMaxLines = 6
    private static let outputMaxCharacters = 1200

    static func truncatedOutput(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lines = trimmed.components(separatedBy: .newlines)
        let keptLines = Array(lines.prefix(outputMaxLines))
        let droppedLines = lines.count - keptLines.count
        var peek = keptLines.joined(separator: "\n")
        if peek.count > outputMaxCharacters {
            peek = String(peek.prefix(outputMaxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            return peek
        }
        if droppedLines > 0 {
            peek += "\n… (\(droppedLines) more \(droppedLines == 1 ? "line" : "lines") — open the thread for the full result)"
        }
        return peek
    }

    static func isOutputTruncated(_ output: String) -> Bool {
        truncatedOutput(output) != output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
