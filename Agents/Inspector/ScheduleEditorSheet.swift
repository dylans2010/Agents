import CoincideRemoteKit
import SwiftUI

struct ScheduleEditorSheet: View {
    @Bindable var appModel: AppModel
    var existingTask: RemoteScheduledTask?
    var preferCurrentThread: Bool = false

    @Environment(\.dismiss) private var dismiss

    enum TargetMode: Hashable {
        case newThreadEachRun
        case specificThread(UUID)
    }

    @State private var name: String = ""
    @State private var prompt: String = ""
    @State private var selectedProjectID: UUID = UUID()
    @State private var targetMode: TargetMode = .newThreadEachRun

    @State private var recurrenceKind: RemoteTaskRecurrence.Kind = .daily
    @State private var keepsUnknownRecurrence: Bool = false
    @State private var onceDate: Date = Date().addingTimeInterval(3600)
    @State private var scheduledTime: Date = {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 9
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()
    @State private var weekday: Int = 2 // Monday (1 = Sunday)
    @State private var timeZoneID: String = TimeZone.current.identifier
    @State private var isPaused: Bool = false
    @State private var isSaving: Bool = false

    private var availableProjects: [RemoteProject] {
        let nonChats = appModel.workspace.projects.filter { !$0.isChats }
        return nonChats.isEmpty ? appModel.workspace.projects : nonChats
    }

    private var threadsInSelectedProject: [RemoteThreadSummary] {
        appModel.workspace.threads.filter { !$0.isArchived && $0.projectID == selectedProjectID }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()

            Form {
                Section("Schedule Details") {
                    TextField("Title (e.g., Morning CI Triage)", text: $name)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Agent Prompt")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)

                        TextEditor(text: $prompt)
                            .font(.system(size: 12.5))
                            .frame(minHeight: 90, maxHeight: 150)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .fill(AppTheme.textBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .strokeBorder(AppTheme.separator, lineWidth: 0.75)
                            )
                    }
                }

                Section("Destination") {
                    Picker("Project", selection: $selectedProjectID) {
                        ForEach(availableProjects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                    .disabled(existingTask?.isThreadSchedule == true)
                    .onChange(of: selectedProjectID) { _, _ in
                        if case .specificThread(let tid) = targetMode,
                           !threadsInSelectedProject.contains(where: { $0.id == tid })
                        {
                            targetMode = .newThreadEachRun
                        }
                    }

                    if let existing = existingTask {
                        if let tid = existing.threadID {
                            let threadTitle = appModel.workspace.threads.first(where: { $0.id == tid })?.title ?? "Bound Conversation"
                            LabeledContent("Target Thread") {
                                Text(threadTitle.isEmpty ? "Current Thread" : threadTitle)
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                        } else {
                            LabeledContent("Execution Mode") {
                                Text("Opens a new conversation on each run")
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                        }
                    } else {
                        Picker("Send Prompt To", selection: $targetMode) {
                            Text("New Conversation on Each Run").tag(TargetMode.newThreadEachRun)
                            if !threadsInSelectedProject.isEmpty {
                                Divider()
                                ForEach(threadsInSelectedProject) { thread in
                                    let label = thread.title.isEmpty ? "Untitled Thread" : thread.title
                                    Text("Thread: \(label)").tag(TargetMode.specificThread(thread.id))
                                }
                            }
                        }
                    }
                }

                Section("Cadence") {
                    if existingTask?.recurrence.kind == .unknown {
                        Toggle("Keep existing custom cadence (\(existingTask?.scheduleText ?? "Custom"))", isOn: $keepsUnknownRecurrence)
                    }

                    if !keepsUnknownRecurrence {
                        Picker("Frequency", selection: $recurrenceKind) {
                            Text("Once").tag(RemoteTaskRecurrence.Kind.once)
                            Text("Daily").tag(RemoteTaskRecurrence.Kind.daily)
                            Text("Weekly").tag(RemoteTaskRecurrence.Kind.weekly)
                        }
                        .pickerStyle(.segmented)

                        if recurrenceKind == .once {
                            DatePicker(
                                "Run Date",
                                selection: $onceDate,
                                displayedComponents: [.date]
                            )
                        }

                        if recurrenceKind == .weekly {
                            Picker("Day of Week", selection: $weekday) {
                                let symbols = Calendar.current.weekdaySymbols
                                ForEach(1...7, id: \.self) { dayIndex in
                                    Text(symbols[dayIndex - 1]).tag(dayIndex)
                                }
                            }
                        }

                        DatePicker(
                            "Run Time",
                            selection: $scheduledTime,
                            displayedComponents: [.hourAndMinute]
                        )

                        LabeledContent("Time Zone") {
                            Text(timeZoneID)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                    }

                    Toggle("Paused", isOn: $isPaused)
                }
            }
            .formStyle(.grouped)

            Divider()
            sheetFooter
        }
        .frame(width: 480, height: 540)
        .background(AppTheme.windowBackground)
        .onAppear(perform: populateInitialValues)
    }

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(existingTask == nil ? "New Scheduled Task" : "Edit Scheduled Task")
                    .font(.system(size: 14, weight: .semibold))
                Text("Schedules run automatically while Agents is active on your Mac.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(AppTheme.controlBackground)
    }

    private var sheetFooter: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                Task { await saveAndApprove() }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 60)
                } else {
                    Text(existingTask == nil ? "Create Schedule" : "Save Changes")
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

    // MARK: - State Population & Saving

    private func populateInitialValues() {
        if let task = existingTask {
            name = task.name
            prompt = task.prompt
            selectedProjectID = task.projectID
            if let tid = task.threadID {
                targetMode = .specificThread(tid)
            } else {
                targetMode = .newThreadEachRun
            }
            isPaused = task.isPaused
            timeZoneID = task.recurrence.timeZoneID

            if task.recurrence.kind == .unknown {
                keepsUnknownRecurrence = true
                recurrenceKind = .daily
            } else {
                keepsUnknownRecurrence = false
                recurrenceKind = task.recurrence.kind
            }
            onceDate = task.recurrence.date
            weekday = max(1, min(7, task.recurrence.weekday))

            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = task.recurrence.hour
            comps.minute = task.recurrence.minute
            if let built = Calendar.current.date(from: comps) {
                scheduledTime = built
            }
        } else {
            let defaultProject = appModel.selectedProject.flatMap { !$0.isChats ? $0 : nil }
                ?? availableProjects.first
            if let defaultProject {
                selectedProjectID = defaultProject.id
            }
            if preferCurrentThread,
               let currentThread = appModel.selectedThread,
               currentThread.projectID == selectedProjectID
            {
                targetMode = .specificThread(currentThread.id)
            } else {
                targetMode = .newThreadEachRun
            }
        }
    }

    private func saveAndApprove() async {
        isSaving = true
        defer { isSaving = false }

        let existingIDsBefore = Set(appModel.scheduledTasks.tasks.map(\.id))

        let recurrencePayload: RemoteTaskRecurrence?
        if keepsUnknownRecurrence {
            recurrencePayload = nil
        } else {
            let timeComps = Calendar.current.dateComponents([.hour, .minute], from: scheduledTime)
            let hour = timeComps.hour ?? 9
            let minute = timeComps.minute ?? 0

            var combinedOnceDate = onceDate
            var dayComps = Calendar.current.dateComponents([.year, .month, .day], from: onceDate)
            dayComps.hour = hour
            dayComps.minute = minute
            if let merged = Calendar.current.date(from: dayComps) {
                combinedOnceDate = merged
            }

            recurrencePayload = RemoteTaskRecurrence(
                kind: recurrenceKind,
                timeZoneID: timeZoneID,
                date: combinedOnceDate,
                hour: hour,
                minute: minute,
                weekday: weekday
            )
        }

        let threadTarget: UUID? = {
            if let existingTask {
                return existingTask.threadID
            }
            if case .specificThread(let tid) = targetMode {
                return tid
            }
            return nil
        }()

        let draft = RemoteScheduledTaskDraft(
            id: existingTask?.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            projectID: selectedProjectID,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            recurrence: recurrencePayload,
            isPaused: isPaused,
            threadID: threadTarget
        )

        await appModel.saveScheduledTask(draft)

        // Auto-approve user-saved schedules if marked awaiting approval
        if let editedID = existingTask?.id {
            if let updated = appModel.scheduledTasks.tasks.first(where: { $0.id == editedID }),
               updated.needsApproval == true
            {
                await appModel.approveSchedule(editedID.uuidString)
            }
        } else {
            let createdTasks = appModel.scheduledTasks.tasks.filter { !existingIDsBefore.contains($0.id) }
            for created in createdTasks where created.needsApproval == true {
                await appModel.approveSchedule(created.id.uuidString)
            }
        }

        dismiss()
    }
}
