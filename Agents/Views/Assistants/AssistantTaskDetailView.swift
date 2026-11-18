import SwiftUI

public struct AssistantTaskDetailView: View {
    public let task: AssistantTaskRecord
    public let viewModel: AssistantTasksViewModel
    public let onEdit: (AssistantTaskRecord) -> Void
    public let onDelete: (AssistantTaskRecord) -> Void

    @State private var isBusy: Bool = false
    @State private var showingDeleteConfirmation: Bool = false

    public init(
        task: AssistantTaskRecord,
        viewModel: AssistantTasksViewModel,
        onEdit: @escaping (AssistantTaskRecord) -> Void,
        onDelete: @escaping (AssistantTaskRecord) -> Void
    ) {
        self.task = task
        self.viewModel = viewModel
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    private var statusLabel: String {
        task.statusLabel
    }

    private var upcomingRuns: [Date] {
        viewModel.upcomingRuns(for: task)
    }

    public var body: some View {
        Form {
            Section("Task") {
                LabeledContent("Name") {
                    Text(task.name.isEmpty ? "Untitled Task" : task.name)
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                LabeledContent("Status") {
                    Text(statusLabel)
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                LabeledContent("Assistant") {
                    Text(viewModel.assistantName(for: task))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                LabeledContent("Workspace") {
                    Text(viewModel.workspaceName(for: task))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                if let inputs = task.inputs.objectValue, !inputs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Inputs")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        ForEach(inputs.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack(spacing: 6) {
                                Text(key)
                                    .font(AppTheme.codeFont(size: 12))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                Text(value.displayText)
                                    .font(AppTheme.codeFont(size: 12))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Scheduled") {
                LabeledContent("Schedule") {
                    Text(task.schedule.summary)
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                LabeledContent("Time Zone") {
                    Text(task.schedule.timeZoneID)
                        .font(AppTheme.codeFont(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                if let nextRun = task.nextRunAtDate, task.isActive {
                    LabeledContent("Next Run") {
                        Text(AssistantTaskDateFormatting.dateTime(nextRun, timeZoneID: task.schedule.timeZoneID))
                            .foregroundStyle(AppTheme.primaryLabel)
                    }
                }
                if upcomingRuns.isEmpty {
                    if task.schedule.kindEnum == .cron {
                        Text("Cron runs are listed from the stored next run; the next occurrences are computed by the task manager.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    } else if !task.isActive {
                        Text("No upcoming runs while the task is \(statusLabel.lowercased()).")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    } else {
                        Text("No upcoming runs.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upcoming Runs")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        ForEach(upcomingRuns, id: \.self) { run in
                            Text(AssistantTaskDateFormatting.dateTime(run, timeZoneID: task.schedule.timeZoneID))
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.primaryLabel)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if task.hasUnconfirmedRun {
                Section("Unconfirmed Run") {
                    if let workerID = task.lastWorkerID {
                        LabeledContent("Worker") {
                            Text(workerID)
                                .font(AppTheme.codeFont(size: 12))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                    }
                    if let started = task.lastRunAtDate {
                        LabeledContent("Started") {
                            Text(AssistantTaskDateFormatting.dateTime(started, timeZoneID: task.schedule.timeZoneID))
                                .foregroundStyle(AppTheme.primaryLabel)
                        }
                    }
                    Text("This run has not reported an outcome yet, so it is not known whether it is still running.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }

            Section("Last Run") {
                LabeledContent("Runs") {
                    Text("\(task.runCount)")
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                if let lastRun = task.lastRunAtDate {
                    LabeledContent("Last Run") {
                        Text(AssistantTaskDateFormatting.dateTime(lastRun, timeZoneID: task.schedule.timeZoneID))
                            .foregroundStyle(AppTheme.primaryLabel)
                    }
                }
                if let outcome = task.lastOutcomeEnum {
                    LabeledContent("Last Outcome") {
                        Text(outcome.displayName)
                            .foregroundStyle(outcome == .failed ? AppTheme.danger : AppTheme.primaryLabel)
                    }
                }
                if let message = task.lastMessage, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(task.lastOutcome == "failed" ? AppTheme.danger : AppTheme.secondaryLabel)
                }
                LabeledContent("Missed Runs") {
                    Text("\(task.missedCount)")
                        .foregroundStyle(task.missedCount > 0 ? AppTheme.warning : AppTheme.primaryLabel)
                }
                if let lastMissed = task.lastMissedAtDate {
                    LabeledContent("Last Missed") {
                        Text(AssistantTaskDateFormatting.dateTime(lastMissed, timeZoneID: task.schedule.timeZoneID))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
            }

            Section("Trigger") {
                LabeledContent("Kind") {
                    Text(task.triggerKind.displayName)
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                if let reason = task.triggerKind.unavailableReason {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.warning)
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                } else {
                    Text("Runs on the schedule above.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }

            Section("Limits") {
                LabeledContent("Maximum Runs") {
                    if let maxRuns = task.limits.maxRuns {
                        Text("\(maxRuns)")
                            .foregroundStyle(AppTheme.primaryLabel)
                    } else {
                        Text("Unlimited")
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
                LabeledContent("Maximum Concurrent") {
                    Text("\(task.limits.maxConcurrent)")
                        .foregroundStyle(AppTheme.primaryLabel)
                }
            }

            Section("Notifications") {
                LabeledContent("On Success") {
                    Text(task.notifications.onSuccess ? "On" : "Off")
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                LabeledContent("On Failure") {
                    Text(task.notifications.onFailure ? "On" : "Off")
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                LabeledContent("On Missed") {
                    Text(task.notifications.onMissed ? "On" : "Off")
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }

            Section("Failure Behavior") {
                LabeledContent("Behavior") {
                    Text(task.failurePolicy.failureBehaviorEnum.displayName)
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                LabeledContent("Maximum Retries") {
                    Text("\(task.failurePolicy.maxRetries)")
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                LabeledContent("Retry Backoff") {
                    Text("\(task.failurePolicy.backoffSeconds) seconds")
                        .foregroundStyle(AppTheme.primaryLabel)
                }
            }

            Section("Approval") {
                LabeledContent("Required") {
                    Text(task.approval.required ? "Yes" : "No")
                        .foregroundStyle(AppTheme.primaryLabel)
                }
                if !task.approval.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actions Requiring Approval")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        ForEach(task.approval.actions, id: \.self) { action in
                            Text(action)
                                .font(AppTheme.codeFont(size: 12))
                                .foregroundStyle(AppTheme.primaryLabel)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Controls") {
                HStack(spacing: 8) {
                    Button(task.enabled ? "Disable" : "Enable") {
                        isBusy = true
                        Task {
                            await viewModel.setEnabled(task, enabled: !task.enabled)
                            isBusy = false
                        }
                    }
                    .disabled(isBusy)

                    Button(task.paused ? "Resume" : "Pause") {
                        isBusy = true
                        Task {
                            await viewModel.setPaused(task, paused: !task.paused)
                            isBusy = false
                        }
                    }
                    .disabled(isBusy)

                    Button("Run Now") {
                        isBusy = true
                        Task {
                            await viewModel.runNow(task)
                            isBusy = false
                        }
                    }
                    .disabled(isBusy || !task.enabled || task.paused)

                    Button("Edit") {
                        onEdit(task)
                    }
                    .disabled(isBusy)

                    Spacer(minLength: 8)

                    Button("Delete", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .disabled(isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Delete this task?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                isBusy = true
                Task {
                    await viewModel.delete(task)
                    isBusy = false
                    onDelete(task)
                }
            }
        } message: {
            Text("“\(task.name)” will be deleted. This cannot be undone.")
        }
    }
}

public struct AssistantTaskEditorView: View {
    public let viewModel: AssistantTasksViewModel
    public let editingTaskID: UUID?
    public let onDone: () -> Void

    @State private var draft: AssistantTaskDraft
    @State private var isSaving: Bool = false

    public init(
        viewModel: AssistantTasksViewModel,
        draft: AssistantTaskDraft,
        editingTaskID: UUID? = nil,
        onDone: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.editingTaskID = editingTaskID
        self.onDone = onDone
        self._draft = State(initialValue: draft)
    }

    private var scheduleKindBinding: Binding<AssistantTaskScheduleKind> {
        Binding(
            get: { draft.scheduleKind },
            set: { kind in
                draft.scheduleKind = kind
                draft.preservedSchedule = nil
            }
        )
    }

    private var onceDateBinding: Binding<Date> {
        Binding(
            get: { draft.schedule.onceDate ?? Date() },
            set: { date in
                draft.schedule.date = .string(ISO8601DateFormatter().string(from: date))
            }
        )
    }

    private var scheduledTime: Binding<Date> {
        Binding(
            get: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = draft.schedule.timeZone
                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = draft.schedule.hour
                components.minute = draft.schedule.minute
                return calendar.date(from: components) ?? Date()
            },
            set: { date in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = draft.schedule.timeZone
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                draft.schedule.hour = parts.hour ?? 9
                draft.schedule.minute = parts.minute ?? 0
            }
        )
    }

    private func weekdayBinding(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { (draft.schedule.weekdays ?? []).contains(day) },
            set: { on in
                var days = Set(draft.schedule.weekdays ?? [])
                if on {
                    days.insert(day)
                } else {
                    days.remove(day)
                }
                draft.schedule.weekdays = days.sorted()
            }
        )
    }

    private var canSave: Bool {
        !isSaving && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(editingTaskID == nil ? "New Automated Task" : "Edit Automated Task")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Runs an assistant on a schedule while Agents is active on your Mac.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(AppTheme.controlBackground)

            Divider()

            Form {
                if let error = viewModel.lastError {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(AppTheme.danger)
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.danger)
                        }
                    }
                }

                Section("Details") {
                    TextField("Name", text: $draft.name)
                    Picker("Assistant", selection: $draft.assistantID) {
                        Text("Choose an assistant").tag(nil as UUID?)
                        ForEach(viewModel.catalog.allDefinitions) { definition in
                            Text(definition.name).tag(definition.persistenceID as UUID?)
                        }
                    }
                    Picker("Workspace", selection: $draft.workspaceID) {
                        Text("Choose a workspace").tag(nil as UUID?)
                        ForEach(viewModel.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    Toggle("Enabled", isOn: $draft.enabled)
                    Toggle("Paused", isOn: $draft.paused)
                }

                Section("Inputs") {
                    if draft.inputRows.isEmpty {
                        Text("No inputs. The assistant runs with no extra values.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    ForEach($draft.inputRows) { $row in
                        HStack(spacing: 8) {
                            TextField("Name", text: $row.key)
                                .font(AppTheme.codeFont(size: 12))
                                .frame(minWidth: 80, maxWidth: 160)
                            TextField("Value", text: $row.value)
                                .font(AppTheme.codeFont(size: 12))
                            Toggle("JSON", isOn: $row.isJSON)
                                .toggleStyle(.checkbox)
                                .controlSize(.small)
                            Button {
                                draft.inputRows.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(AppTheme.danger)
                            }
                            .buttonStyle(.plain)
                            .help("Remove input")
                        }
                    }
                    Button("Add Input") {
                        draft.inputRows.append(AssistantTaskInputRow(key: "", value: ""))
                    }
                }

                Section("Schedule") {
                    if draft.preservedSchedule != nil {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.warning)
                            Text("The existing custom schedule is kept unchanged. Choose a replacement below to edit the schedule.")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                    }
                    Picker("Frequency", selection: scheduleKindBinding) {
                        ForEach(AssistantTaskScheduleKind.allCases.filter { $0 != .unknown }, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if draft.preservedSchedule == nil {
                        if draft.scheduleKind == .once {
                            DatePicker("Run Date", selection: onceDateBinding, displayedComponents: [.date])
                        }
                        if draft.scheduleKind == .weekly {
                            Picker("Day of Week", selection: $draft.schedule.weekday) {
                                let symbols = Calendar.current.weekdaySymbols
                                ForEach(1...7, id: \.self) { day in
                                    Text(symbols[day - 1]).tag(day)
                                }
                            }
                        }
                        if draft.scheduleKind == .days {
                            VStack(alignment: .leading, spacing: 4) {
                                let symbols = Calendar.current.weekdaySymbols
                                ForEach(1...7, id: \.self) { day in
                                    Toggle(symbols[day - 1], isOn: weekdayBinding(day))
                                }
                            }
                        }
                        if draft.scheduleKind == .interval {
                            Stepper("Every \(draft.schedule.intervalMinutes ?? 60) minutes", value: Binding(
                                get: { draft.schedule.intervalMinutes ?? 60 },
                                set: { draft.schedule.intervalMinutes = $0 }
                            ), in: 5...44640, step: 5)
                        }
                        if draft.scheduleKind == .cron {
                            TextField("Cron expression", text: Binding(
                                get: { draft.schedule.cron ?? "" },
                                set: { draft.schedule.cron = $0 }
                            ))
                            .font(AppTheme.codeFont(size: 12))
                        }

                        DatePicker("Run Time", selection: scheduledTime, displayedComponents: [.hourAndMinute])

                        TextField("Time Zone (IANA)", text: $draft.schedule.timeZoneID)
                            .font(AppTheme.codeFont(size: 12))
                        Text(draft.schedule.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }

                Section("Trigger") {
                    Picker("Trigger", selection: $draft.trigger) {
                        ForEach(AssistantTaskTriggerKind.allCases, id: \.self) { kind in
                            Text(kind.displayName)
                                .tag(kind)
                                .disabled(!kind.isAvailable)
                        }
                    }
                    ForEach(AssistantTaskTriggerKind.allCases.filter { !$0.isAvailable }, id: \.self) { kind in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.warning)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.primaryLabel)
                                Text(kind.unavailableReason ?? "")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                        }
                    }
                }

                Section("Limits") {
                    Toggle("Limit total runs", isOn: Binding(
                        get: { draft.maxRuns != nil },
                        set: { on in draft.maxRuns = on ? (draft.maxRuns ?? 10) : nil }
                    ))
                    if draft.maxRuns != nil {
                        Stepper("Maximum runs: \(draft.maxRuns ?? 10)", value: Binding(
                            get: { draft.maxRuns ?? 10 },
                            set: { draft.maxRuns = $0 }
                        ), in: 1...100000)
                    }
                    Stepper("Maximum concurrent runs: \(draft.maxConcurrent)", value: $draft.maxConcurrent, in: 1...32)
                }

                Section("Notifications") {
                    Toggle("On success", isOn: $draft.notifyOnSuccess)
                    Toggle("On failure", isOn: $draft.notifyOnFailure)
                    Toggle("On missed", isOn: $draft.notifyOnMissed)
                }

                Section("Failure Behavior") {
                    Picker("Behavior", selection: $draft.failureBehavior) {
                        ForEach(AssistantTaskFailureBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    Stepper("Maximum retries: \(draft.maxRetries)", value: $draft.maxRetries, in: 0...10)
                    Stepper("Retry backoff: \(draft.backoffSeconds) seconds", value: $draft.backoffSeconds, in: 60...86400, step: 60)
                }

                Section("Approval") {
                    Toggle("Approval required", isOn: $draft.approvalRequired)
                    if draft.approvalRequired {
                        ForEach(draft.approvalActions.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                TextField("Action name", text: $draft.approvalActions[index])
                                    .font(AppTheme.codeFont(size: 12))
                                Button {
                                    draft.approvalActions.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(AppTheme.danger)
                                }
                                .buttonStyle(.plain)
                                .help("Remove action")
                            }
                        }
                        Button("Add Action") {
                            draft.approvalActions.append("")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") {
                    onDone()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 60)
                    } else {
                        Text(editingTaskID == nil ? "Create Task" : "Save Changes")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(AppTheme.controlBackground)
        }
        .frame(minWidth: 460, idealWidth: 520, maxWidth: 620, minHeight: 520, idealHeight: 620, maxHeight: 760)
        .background(AppTheme.windowBackground)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        if draft.scheduleKind == .once, let day = draft.schedule.onceDate {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = draft.schedule.timeZone
            let dayStart = calendar.startOfDay(for: day)
            var matching = DateComponents()
            matching.hour = draft.schedule.hour
            matching.minute = draft.schedule.minute
            if let merged = calendar.nextDate(
                after: dayStart.addingTimeInterval(-1),
                matching: matching,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ), calendar.isDate(merged, inSameDayAs: day) {
                draft.schedule.date = .string(ISO8601DateFormatter().string(from: merged))
            }
        }
        if await viewModel.saveDraft(draft, editingTaskID: editingTaskID) {
            onDone()
        }
    }
}
