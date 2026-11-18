import AppKit
import CoincideRemoteKit
import SwiftUI

struct WorkersInspectorView: View {
    @Bindable var appModel: AppModel
    var refreshToken: UUID

    enum ScopeFilter: String, CaseIterable, Identifiable {
        case currentThread
        case allWorkers

        var id: String { rawValue }

        var title: String {
            switch self {
            case .currentThread: "Current Thread"
            case .allWorkers: "All Workers"
            }
        }
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all
        case running
        case completed
        case failed
        case cancelled
        case orphaned

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .running: "Running"
            case .completed: "Completed"
            case .failed: "Failed"
            case .cancelled: "Cancelled"
            case .orphaned: "Orphaned"
            }
        }
    }

    private static let pausedUpdatesNote = "Worker updates paused — will retry"

    @State private var scopeFilter: ScopeFilter = .currentThread
    @State private var statusFilter: StatusFilter = .all
    @State private var consecutiveFailures = 0
    @State private var workers: [WorkerRecord] = []
    @State private var knownThreadIDs: Set<String>?
    @State private var selectedWorkerID: String?
    @State private var isLoading: Bool = false
    @State private var errorText: String?
    @State private var showSpawnForm: Bool = false
    @State private var showPlanForm: Bool = false
    @State private var spawnName: String = ""
    @State private var spawnTask: String = ""
    @State private var spawnTargetFiles: String = ""
    @State private var planTaskText: String = ""
    @State private var plan: WorkerPlan?
    @State private var planObjective: String = ""
    @State private var planMode: String = "build"
    @State private var cancellingIDs: Set<String> = []
    @State private var isCancellingAll: Bool = false
    @State private var showCancelAllConfirmation: Bool = false
    @State private var pendingDeleteWorker: WorkerRecord?
    @State private var deletingIDs: Set<String> = []
    @State private var isClearingFinished: Bool = false
    @State private var showClearFinishedConfirmation: Bool = false
    @State private var retryingIDs: Set<String> = []

    private var scopedWorkers: [WorkerRecord] {
        switch scopeFilter {
        case .allWorkers:
            return workers
        case .currentThread:
            guard let tid = appModel.selectedThreadUUID else { return [] }
            return workers.filter { $0.parentThreadId.lowercased() == tid.uuidString.lowercased() }
        }
    }

    private var filteredWorkers: [WorkerRecord] {
        switch statusFilter {
        case .all:
            return scopedWorkers
        case .running:
            return scopedWorkers.filter(\.isRunning)
        case .completed:
            return scopedWorkers.filter { $0.status == "completed" }
        case .failed:
            return scopedWorkers.filter { $0.status == "failed" }
        case .cancelled:
            return scopedWorkers.filter { $0.status == "cancelled" }
        case .orphaned:
            return scopedWorkers.filter { $0.isOrphan(knownParentThreadIDs: knownThreadIDs) }
        }
    }

    private var selectedWorker: WorkerRecord? {
        filteredWorkers.first { $0.id == selectedWorkerID }
    }

    private var runningCount: Int {
        WorkerRecord.runningWorkers(from: scopedWorkers).count
    }

    private var terminalCount: Int {
        WorkerRecord.terminalWorkers(from: scopedWorkers).count
    }

    private var scopeLabel: String {
        scopeFilter == .currentThread ? "in the current thread" : "across all workers"
    }

    private var runningCapLabel: String {
        scopeFilter == .currentThread ? "\(runningCount)/32 running" : "\(runningCount) running"
    }

    private var runningCapAccessibilityLabel: String {
        scopeFilter == .currentThread
            ? "\(runningCount) of 32 worker slots running"
            : "\(runningCount) workers running"
    }

    var body: some View {
        VStack(spacing: 0) {
            workersToolbar
            Divider()
            if let errorText, !errorText.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.warning)
                    Text(errorText)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") {
                        self.errorText = nil
                        consecutiveFailures = 0
                    }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.warning.opacity(0.10))
                Divider()
            }
            if showSpawnForm {
                spawnForm
                Divider()
            }
            if showPlanForm {
                planForm
                Divider()
            }
            if filteredWorkers.isEmpty {
                emptyWorkersState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredWorkers) { worker in
                            workerRow(worker)
                        }
                    }
                    .padding(10)
                }
            }
            if let worker = selectedWorker {
                Divider()
                workerDetail(worker)
            }
        }
        .task(id: refreshToken) {
            await loadWorkers()
            while !Task.isCancelled {
                let baseSeconds: Int = filteredWorkers.contains(where: \.isRunning) ? 3 : 10
                let multiplier = 1 << min(consecutiveFailures, 3)
                try? await Task.sleep(for: .seconds(baseSeconds * multiplier))
                if Task.isCancelled { break }
                if await loadWorkers(silent: true) {
                    consecutiveFailures = 0
                    if errorText == Self.pausedUpdatesNote {
                        errorText = nil
                    }
                } else {
                    consecutiveFailures += 1
                    if consecutiveFailures >= 3, errorText == nil || errorText == Self.pausedUpdatesNote {
                        errorText = Self.pausedUpdatesNote
                    }
                }
            }
        }
        .onChange(of: scopeFilter) { _, _ in
            consecutiveFailures = 0
            if errorText == Self.pausedUpdatesNote {
                errorText = nil
            }
            Task { await loadWorkers() }
        }
        .confirmationDialog(
            "Delete Worker Record?",
            isPresented: Binding(
                get: { pendingDeleteWorker != nil },
                set: { if !$0 { pendingDeleteWorker = nil } }
            ),
            presenting: pendingDeleteWorker
        ) { worker in
            Button("Delete Record", role: .destructive) {
                pendingDeleteWorker = nil
                Task { await deleteSelectedWorker(worker) }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteWorker = nil
            }
        } message: { worker in
            Text("This deletes the record for “\(worker.name)”. The worker thread itself is not deleted.")
        }
        .confirmationDialog(
            "Cancel All Running Workers?",
            isPresented: $showCancelAllConfirmation
        ) {
            Button(runningCount == 1 ? "Cancel 1 Worker" : "Cancel \(runningCount) Workers", role: .destructive) {
                Task { await cancelAllRunningWorkers() }
            }
            Button("Keep Running", role: .cancel) {}
        } message: {
            Text("This asks \(runningCount) running \(runningCount == 1 ? "worker" : "workers") \(scopeLabel) to stop. Cancellation is a stop request, not a kill: each provider winds down on its own schedule and the records stay cancelled.")
        }
        .confirmationDialog(
            "Clear Finished Workers?",
            isPresented: $showClearFinishedConfirmation
        ) {
            Button(terminalCount == 1 ? "Delete 1 Record" : "Delete \(terminalCount) Records", role: .destructive) {
                Task { await clearFinishedWorkers() }
            }
            Button("Keep Records", role: .cancel) {}
        } message: {
            Text("This deletes \(terminalCount) finished \(terminalCount == 1 ? "worker record" : "worker records") \(scopeLabel). Running workers are never deleted. The worker threads themselves are not deleted.")
        }
    }

    private var workersToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Scope", selection: $scopeFilter) {
                    ForEach(ScopeFilter.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                Spacer(minLength: 4)
                if scopeFilter == .currentThread || runningCount > 0 {
                    Text(runningCapLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(scopeFilter == .currentThread && runningCount >= 32 ? AppTheme.warning : AppTheme.accent)
                        .accessibilityLabel(runningCapAccessibilityLabel)
                }
                Button {
                    Task {
                        consecutiveFailures = 0
                        if await loadWorkers(), errorText == Self.pausedUpdatesNote {
                            errorText = nil
                        }
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(width: 16, height: 16)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .help("Refresh workers")
                .accessibilityLabel("Refresh workers")
            }
            HStack(spacing: 8) {
                Picker("Status", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
                Spacer(minLength: 4)
            }
            HStack(spacing: 8) {
                Button {
                    showSpawnForm.toggle()
                    if showSpawnForm { showPlanForm = false }
                } label: {
                    Label(showSpawnForm ? "Hide Spawn" : "Spawn Worker", systemImage: "person.badge.plus")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    showPlanForm.toggle()
                    if showPlanForm { showSpawnForm = false }
                } label: {
                    Label(showPlanForm ? "Hide Plan" : "Plan", systemImage: "list.bullet.rectangle")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
            HStack(spacing: 8) {
                Button {
                    showCancelAllConfirmation = true
                } label: {
                    Label("Cancel All", systemImage: "stop.circle")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(runningCount == 0 || isCancellingAll)
                .help("Cancel every running worker \(scopeLabel)")
                .accessibilityLabel("Cancel all running workers")
                Button(role: .destructive) {
                    showClearFinishedConfirmation = true
                } label: {
                    Label("Clear Finished", systemImage: "trash")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(terminalCount == 0 || isClearingFinished)
                .help("Delete every finished worker record \(scopeLabel)")
                .accessibilityLabel("Clear finished workers")
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var spawnForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spawn Worker")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.primaryLabel)
            TextField("Name", text: $spawnName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
            TextField("Task (at most 500 characters)", text: $spawnTask, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .lineLimit(3...6)
            HStack(spacing: 6) {
                Text("\(spawnTask.count)/500")
                    .font(.system(size: 11))
                    .foregroundStyle(spawnTask.count > 500 ? AppTheme.warning : AppTheme.secondaryLabel)
                Spacer()
            }
            TextField("Target files, comma separated (optional)", text: $spawnTargetFiles)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
            Text("The worker runs a real provider turn on its own thread, inheriting this thread's provider and toolset. Target files must not overlap another running worker's files.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
            HStack(spacing: 8) {
                Button("Spawn") {
                    Task { await spawnWorker() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(spawnName.trimmingCharacters(in: .whitespaces).isEmpty || spawnTask.trimmingCharacters(in: .whitespaces).isEmpty || spawnTask.count > 500 || appModel.selectedThreadUUID == nil)
                Button("Clear") {
                    spawnName = ""
                    spawnTask = ""
                    spawnTargetFiles = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
    }

    private var planForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.primaryLabel)
            TextField("Task to decompose", text: $planTaskText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .lineLimit(2...4)
            HStack(spacing: 8) {
                Button("Draft Plan") {
                    Task { await draftPlan() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(planTaskText.trimmingCharacters(in: .whitespaces).isEmpty || appModel.selectedThreadUUID == nil)
                if plan != nil {
                    Button("Expand Steps") {
                        Task { await expandPlan() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                TextField("Objective", text: $planObjective)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                TextField("Mode", text: $planMode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .frame(maxWidth: 90)
                Button("Execution Plan") {
                    Task { await buildExecutionPlan() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(planObjective.trimmingCharacters(in: .whitespaces).isEmpty || planMode.trimmingCharacters(in: .whitespaces).isEmpty || appModel.selectedThreadUUID == nil)
            }
            Text("Plans are mechanical sentence decomposition, not LLM planning. An execution plan also writes agent_notes.md in the parent working directory.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
            if let plan {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(index + 1).")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.secondaryLabel)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                Text(step.task)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                        }
                    }
                    if let markdown = plan.markdown {
                        Text(markdown)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    } else if let agentNotesPath = plan.agentNotesPath {
                        Text("Written to \(agentNotesPath).")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
            }
        }
        .padding(10)
    }

    private var emptyWorkersState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(AppTheme.secondaryLabel)
            Text(statusFilter == .orphaned ? "No orphaned workers." : appModel.selectedThreadUUID == nil ? "Select a thread to see its workers." : "No workers yet.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.primaryLabel)
            Text(statusFilter == .orphaned ? "Workers whose parent thread was deleted will appear here." : "Spawn a worker to run a subagent on its own thread, or draft a plan to break work into worker tasks.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func workerRow(_ worker: WorkerRecord) -> some View {
        let isSelected = selectedWorkerID == worker.id
        let orphaned = worker.isOrphan(knownParentThreadIDs: knownThreadIDs)
        return Button {
            selectedWorkerID = isSelected ? nil : worker.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(worker.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .lineLimit(1)
                    Spacer()
                    if orphaned {
                        orphanBadge
                    }
                    statusBadge(worker.status)
                }
                Text(worker.task)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(worker.provider)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Text("\(worker.transcriptItems) updates")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Text(elapsedLabel(worker.elapsedSeconds))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Spacer()
                    if worker.isRunning {
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
        .accessibilityLabel("Worker \(worker.name), \(worker.status)\(orphaned ? ", orphaned" : "")")
    }

    private func workerDetail(_ worker: WorkerRecord) -> some View {
        let orphaned = worker.isOrphan(knownParentThreadIDs: knownThreadIDs)
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(worker.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                    Spacer()
                    if orphaned {
                        orphanBadge
                    }
                    statusBadge(worker.status)
                }
                Text(worker.task)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.primaryLabel)
                if orphaned {
                    Text("Parent thread no longer exists.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.warning)
                }
                if !worker.targetFiles.isEmpty {
                    Text("Files: \(worker.targetFiles.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                Text("Provider: \(worker.provider) · Elapsed: \(elapsedLabel(worker.elapsedSeconds)) · Updates: \(worker.transcriptItems)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Button {
                    appModel.selectThread(worker.threadId)
                } label: {
                    Label("Worker: \(worker.name)", systemImage: "arrow.turn.down.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("Open the worker thread")
                .accessibilityLabel("Open worker thread \(worker.name)")
                if let result = worker.result, !result.isEmpty {
                    Text("Result")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryLabel)
                    Text(result)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.primaryLabel)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if worker.status == "completed" {
                    Text("Completed with no text reply.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                if let error = worker.error, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.warning)
                }
                if worker.isRunning {
                    Button("Cancel Worker") {
                        Task { await cancelSelectedWorker(worker) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(cancellingIDs.contains(worker.id))
                    Text("Cancel asks the provider turn to stop. It is a stop request, not a kill: the provider winds down on its own schedule and the record stays cancelled.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                if worker.status == "failed" || worker.status == "cancelled" {
                    Button("Retry Worker") {
                        Task { await retrySelectedWorker(worker) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(orphaned || retryingIDs.contains(worker.id))
                    Text(orphaned ? "Retry needs the parent thread, which no longer exists. Cancel or delete this worker instead." : "Retry spawns a new worker with the same name, task, and target files on the same parent thread. The old record stays for history.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                if worker.isTerminal {
                    Button("Delete Worker", role: .destructive) {
                        pendingDeleteWorker = worker
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(deletingIDs.contains(worker.id))
                    Text("Delete removes the worker record only. The worker thread stays in the thread list.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 320)
    }

    private var orphanBadge: some View {
        Text("Orphaned")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppTheme.warning)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppTheme.warning.opacity(0.14)))
            .accessibilityLabel("Orphaned worker")
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color
        switch status {
        case "running": color = AppTheme.accent
        case "completed": color = AppTheme.success
        case "failed": color = AppTheme.danger
        case "cancelled": color = AppTheme.warning
        default: color = AppTheme.secondaryLabel
        }
        return Text(status.capitalized)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .accessibilityLabel("Status \(status)")
    }

    private func elapsedLabel(_ seconds: Double) -> String {
        let total = Int(seconds)
        if total < 60 {
            return "\(total)s"
        }
        return "\(total / 60)m \(total % 60)s"
    }

    @discardableResult
    private func loadWorkers(silent: Bool = false) async -> Bool {
        guard let client = appModel.runtime else { return true }
        if !silent {
            isLoading = true
        }
        defer {
            if !silent {
                isLoading = false
            }
        }
        do {
            let parentId: String? = scopeFilter == .currentThread ? appModel.selectedThreadUUID?.uuidString : nil
            let loaded = try await client.listWorkers(parentThreadId: parentId)
            if !Task.isCancelled {
                workers = loaded
            }
            if scopeFilter == .allWorkers, !Task.isCancelled {
                if let workspace = try? await client.fetchWorkspace(includeArchived: true) {
                    knownThreadIDs = Set(workspace.threads.map { $0.id.uuidString.lowercased() })
                }
            }
            return true
        } catch {
            if !Task.isCancelled && !silent {
                errorText = error.localizedDescription
            }
            return false
        }
    }

    private func spawnWorker() async {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID else { return }
        let files = spawnTargetFiles
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        do {
            let result = try await client.spawnWorkers(
                parentThreadId: tid.uuidString,
                workers: [WorkerSpawnRequest(name: spawnName.trimmingCharacters(in: .whitespaces), task: spawnTask.trimmingCharacters(in: .whitespaces), targetFiles: files)]
            )
            let spawned = result["workers"]?.arrayValue ?? []
            if let first = spawned.first, let id = first["id"]?.stringValue {
                selectedWorkerID = id
            }
            spawnName = ""
            spawnTask = ""
            spawnTargetFiles = ""
            showSpawnForm = false
            errorText = nil
            await loadWorkers()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func draftPlan() async {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID else { return }
        do {
            plan = try await client.planTask(parentThreadId: tid.uuidString, task: planTaskText)
            planObjective = planTaskText
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func expandPlan() async {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID, let plan else { return }
        do {
            self.plan = try await client.breakdownTask(planId: plan.planId, parentThreadId: tid.uuidString)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func buildExecutionPlan() async {
        guard let client = appModel.runtime, let tid = appModel.selectedThreadUUID else { return }
        do {
            plan = try await client.executionPlan(parentThreadId: tid.uuidString, objective: planObjective, mode: planMode)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func cancelSelectedWorker(_ worker: WorkerRecord) async {
        guard let client = appModel.runtime else { return }
        cancellingIDs.insert(worker.id)
        defer { cancellingIDs.remove(worker.id) }
        do {
            let updated = try await client.cancelWorker(workerId: worker.id)
            if let index = workers.firstIndex(where: { $0.id == updated.id }) {
                workers[index] = updated
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func cancelAllRunningWorkers() async {
        guard let client = appModel.runtime else { return }
        let targets = WorkerRecord.runningWorkers(from: scopedWorkers)
        guard !targets.isEmpty else { return }
        isCancellingAll = true
        defer { isCancellingAll = false }
        var failures: [String] = []
        for worker in targets {
            cancellingIDs.insert(worker.id)
            do {
                let updated = try await client.cancelWorker(workerId: worker.id)
                if let index = workers.firstIndex(where: { $0.id == updated.id }) {
                    workers[index] = updated
                }
            } catch {
                failures.append("\(worker.name): \(error.localizedDescription)")
            }
            cancellingIDs.remove(worker.id)
        }
        let reloaded = await loadWorkers(silent: true)
        if let message = WorkerRecord.bulkFailureMessage(action: "cancel", attempted: targets.count, failures: failures) {
            errorText = message
        } else if reloaded {
            errorText = nil
        }
    }

    private func clearFinishedWorkers() async {
        guard let client = appModel.runtime else { return }
        let targets = WorkerRecord.terminalWorkers(from: scopedWorkers)
        guard !targets.isEmpty else { return }
        isClearingFinished = true
        defer { isClearingFinished = false }
        var failures: [String] = []
        for worker in targets {
            deletingIDs.insert(worker.id)
            do {
                _ = try await client.deleteWorker(workerId: worker.id)
                workers.removeAll { $0.id == worker.id }
                if selectedWorkerID == worker.id {
                    selectedWorkerID = nil
                }
            } catch {
                failures.append("\(worker.name): \(error.localizedDescription)")
            }
            deletingIDs.remove(worker.id)
        }
        let reloaded = await loadWorkers(silent: true)
        if let message = WorkerRecord.bulkFailureMessage(action: "delete", attempted: targets.count, failures: failures) {
            errorText = message
        } else if reloaded {
            errorText = nil
        }
    }

    private func deleteSelectedWorker(_ worker: WorkerRecord) async {
        guard let client = appModel.runtime else { return }
        deletingIDs.insert(worker.id)
        defer { deletingIDs.remove(worker.id) }
        do {
            _ = try await client.deleteWorker(workerId: worker.id)
            workers.removeAll { $0.id == worker.id }
            if selectedWorkerID == worker.id {
                selectedWorkerID = nil
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func retrySelectedWorker(_ worker: WorkerRecord) async {
        guard let client = appModel.runtime else { return }
        retryingIDs.insert(worker.id)
        defer { retryingIDs.remove(worker.id) }
        do {
            let result = try await client.spawnWorkers(
                parentThreadId: worker.parentThreadId,
                workers: [WorkerSpawnRequest(name: worker.name, task: worker.task, targetFiles: worker.targetFiles)]
            )
            let spawned = result["workers"]?.arrayValue ?? []
            if let first = spawned.first, let id = first["id"]?.stringValue {
                selectedWorkerID = id
            }
            errorText = nil
            await loadWorkers()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
