import CoincideRemoteKit
import SwiftUI

struct AssistantDashboardView: View {
    @Bindable var appModel: AppModel
    @State private var viewModel: AssistantDashboardViewModel

    init(appModel: AppModel) {
        self.appModel = appModel
        let model = AssistantDashboardViewModel(sourceProvider: { [weak appModel] in appModel?.runtime })
        model.onOpenThread = { [weak appModel] threadId in appModel?.selectThread(threadId) }
        self._viewModel = State(initialValue: model)
    }

    var body: some View {
        HSplitView {
            runListPane
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
            detailPane
                .frame(minWidth: 340)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Assistant", selection: $viewModel.selectedAssistantID) {
                    Text("All Assistants").tag(nil as UUID?)
                    ForEach(viewModel.assistants) { assistant in
                        Text(assistant.name).tag(assistant.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                Picker("Status", selection: $viewModel.statusFilter) {
                    ForEach(AssistantRunStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            await viewModel.refresh()
            viewModel.startLiveRefresh()
        }
        .onDisappear {
            viewModel.stopLiveRefresh()
        }
        .onChange(of: viewModel.selectedAssistantID) { _, _ in
            Task { await viewModel.loadRuns() }
        }
    }

    private var runListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Runs")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                Text("\(viewModel.runningCount) running")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            if let errorText = viewModel.errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.warning)
                    .padding(10)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if viewModel.filteredRuns.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView(
                            "No Runs",
                            systemImage: "bolt",
                            description: Text("No assistant runs match the current filters.")
                        )
                        .frame(maxWidth: .infinity)
                    }
                    ForEach(viewModel.filteredRuns) { record in
                        AssistantRunRow(
                            record: record,
                            assistantName: viewModel.assistantName(for: record),
                            isSelected: viewModel.selectedRunID == record.id
                        ) {
                            viewModel.selectRun(record)
                        }
                    }
                    let extraHistory = viewModel.historyRuns.filter { history in
                        !viewModel.filteredRuns.contains { $0.id == history.id }
                    }
                    if !extraHistory.isEmpty {
                        DisclosureGroup("History") {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(extraHistory) { record in
                                    AssistantRunRow(
                                        record: record,
                                        assistantName: viewModel.assistantName(for: record),
                                        isSelected: viewModel.selectedRunID == record.id
                                    ) {
                                        viewModel.selectRun(record)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .padding(.top, 6)
                    }
                }
                .padding(10)
            }
        }
    }

    private var detailPane: some View {
        Group {
            if let detail = viewModel.detail {
                AssistantRunDetailView(viewModel: viewModel, detail: detail)
            } else {
                ContentUnavailableView(
                    "No Run Selected",
                    systemImage: "list.bullet",
                    description: Text("Select a run to see its detail, output, and changes.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
