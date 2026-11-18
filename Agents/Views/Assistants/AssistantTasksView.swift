import SwiftUI

public struct AssistantTasksView: View {
    @Bindable public var viewModel: AssistantTasksViewModel

    @State private var editorDraft: AssistantTaskDraft?
    @State private var editingTaskID: UUID?
    @State private var showingDeleteConfirmation: Bool = false
    @State private var taskPendingDelete: AssistantTaskRecord?

    public init(viewModel: AssistantTasksViewModel, initialDraft: AssistantTaskDraft? = nil) {
        self.viewModel = viewModel
        if let initialDraft {
            _editorDraft = State(initialValue: initialDraft)
            _editingTaskID = State(initialValue: nil)
        }
    }

    public var body: some View {
        NavigationSplitView {
            listPane
        } detail: {
            detailPane
        }
        .navigationTitle("Automated Tasks")
        .sheet(isPresented: Binding(
            get: { editorDraft != nil },
            set: { if !$0 { editorDraft = nil } }
        )) {
            if let editorDraft {
                AssistantTaskEditorView(
                    viewModel: viewModel,
                    draft: editorDraft,
                    editingTaskID: editingTaskID
                ) {
                    self.editorDraft = nil
                    self.editingTaskID = nil
                }
            }
        }
        .alert("Delete this task?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                taskPendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let task = taskPendingDelete {
                    Task { await viewModel.delete(task) }
                    taskPendingDelete = nil
                }
            }
        } message: {
            if let task = taskPendingDelete {
                Text("“\(task.name)” will be deleted. This cannot be undone.")
            }
        }
        .task {
            await viewModel.refresh()
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            if let error = viewModel.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(AppTheme.danger)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.danger)
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    Button {
                        viewModel.lastError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.danger.opacity(0.08))
            }

            Picker("Filter", selection: $viewModel.filter) {
                ForEach(AssistantTasksFilter.allCases, id: \.self) { filter in
                    let count = viewModel.countsByFilter[filter] ?? 0
                    Text("\(filter.title) (\(count))").tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            TextField("Search tasks", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if viewModel.isLoading && viewModel.tasks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredTasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                    Text(emptyStateText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .multilineTextAlignment(.center)
                    Button("New Automated Task") {
                        editorDraft = viewModel.draftForNewTask()
                        editingTaskID = nil
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $viewModel.selectedTaskID) {
                    ForEach(viewModel.filteredTasks) { task in
                        AssistantTaskRow(
                            task: task,
                            assistantName: viewModel.assistantName(for: task),
                            workspaceName: viewModel.workspaceName(for: task)
                        )
                        .tag(task.id)
                        .contextMenu {
                            Button("Run Now") {
                                Task { await viewModel.runNow(task) }
                            }
                            .disabled(!task.enabled || task.paused)
                            Button(task.paused ? "Resume" : "Pause") {
                                Task { await viewModel.setPaused(task, paused: !task.paused) }
                            }
                            Button(task.enabled ? "Disable" : "Enable") {
                                Task { await viewModel.setEnabled(task, enabled: !task.enabled) }
                            }
                            Button("Edit") {
                                editorDraft = viewModel.draftForTask(task)
                                editingTaskID = task.id
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                taskPendingDelete = task
                                showingDeleteConfirmation = true
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await viewModel.recoverMissed() }
                } label: {
                    Label("Recover Missed", systemImage: "arrow.clockwise")
                }
                .help("Record runs missed while Agents was closed")

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Reload automated tasks")

                Button {
                    editorDraft = viewModel.draftForNewTask()
                    editingTaskID = nil
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .help("Create an automated task")
            }
        }
    }

    private var emptyStateText: String {
        if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No tasks match this search."
        }
        switch viewModel.filter {
        case .all:
            return "No automated tasks yet. Create one to run an assistant on a schedule."
        case .active:
            return "No active tasks."
        case .paused:
            return "No paused tasks."
        case .upcoming:
            return "No upcoming runs."
        case .recent:
            return "No tasks have run yet."
        case .failed:
            return "No failed tasks."
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let task = viewModel.selectedTask {
            AssistantTaskDetailView(
                task: task,
                viewModel: viewModel,
                onEdit: { task in
                    editorDraft = viewModel.draftForTask(task)
                    editingTaskID = task.id
                },
                onDelete: { _ in
                    editorDraft = nil
                    editingTaskID = nil
                }
            )
        } else {
            VStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                Text("Select an automated task to see its schedule, runs, and last run.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}
