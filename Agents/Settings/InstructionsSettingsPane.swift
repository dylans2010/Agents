import AppKit
import CoincideRemoteKit
import SwiftUI

public struct InstructionsSettingsPane: View {
    @Bindable public var appModel: AppModel

    @State private var descriptors: [InstructionFileDescriptor] = []
    @State private var selectedPath: String?
    @State private var editorContent: String = ""
    @State private var loadedBaseline: String = ""
    @State private var isLoadingList: Bool = false
    @State private var isLoadingFile: Bool = false
    @State private var isSaving: Bool = false

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private var globalDescriptors: [InstructionFileDescriptor] {
        descriptors.filter { $0.scope.lowercased() == "global" }
    }

    private var projectDescriptors: [InstructionFileDescriptor] {
        descriptors.filter { $0.scope.lowercased() != "global" }
    }

    private var selectedDescriptor: InstructionFileDescriptor? {
        guard let selectedPath else { return nil }
        return descriptors.first { $0.path == selectedPath }
    }

    private var hasUnsavedChanges: Bool {
        selectedDescriptor != nil && editorContent != loadedBaseline
    }

    public var body: some View {
        HSplitView {
            instructionsSidebar
                .frame(minWidth: 230, idealWidth: 260, maxWidth: 320)

            instructionEditorPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Instructions")
        .task {
            await reloadInstructionsList()
        }
        .onChange(of: selectedPath) { _, newPath in
            if let newPath {
                Task { await loadSelectedInstruction(path: newPath) }
            } else {
                editorContent = ""
                loadedBaseline = ""
            }
        }
    }

    // MARK: - Left File List

    private var instructionsSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Instruction Files")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Spacer()
                Button {
                    Task { await reloadInstructionsList() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.borderless)
                .help("Rescan Instruction Files")
                .accessibilityLabel("Rescan instruction files")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.controlBackground)

            Divider()

            List(selection: $selectedPath) {
                if !globalDescriptors.isEmpty {
                    Section("Global Instructions") {
                        ForEach(globalDescriptors) { item in
                            instructionRow(item)
                                .tag(item.path)
                        }
                    }
                }

                Section(projectSectionHeader) {
                    if projectDescriptors.isEmpty {
                        Text("No project folder selected")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                    } else {
                        ForEach(projectDescriptors) { item in
                            instructionRow(item)
                                .tag(item.path)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var projectSectionHeader: String {
        if let proj = appModel.selectedProject, !proj.isChats {
            return "Project · \(proj.name)"
        }
        return "Workspace Instructions"
    }

    private func instructionRow(_ item: InstructionFileDescriptor) -> some View {
        HStack(spacing: 8) {
            if let prov = item.provider, !prov.isEmpty {
                AgentLogoView(provider: prov, size: 14)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                if let rel = item.relativePath, !rel.isEmpty {
                    Text(rel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryLabel)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if item.isSymlink {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                    .help(item.linkTarget ?? "Symbolic link")
            }

            Text(item.exists ? "Exists" : "Create")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.exists ? AppTheme.success : AppTheme.info)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    Capsule()
                        .fill((item.exists ? AppTheme.success : AppTheme.info).opacity(0.14))
                )
        }
        .padding(.vertical, 2)
    }

    // MARK: - Right Monospaced Editor

    @ViewBuilder
    private var instructionEditorPane: some View {
        if let descriptor = selectedDescriptor {
            VStack(spacing: 0) {
                // Header Bar
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(descriptor.title)
                                .font(.system(size: 13, weight: .semibold))

                            if hasUnsavedChanges {
                                Text("Edited")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.warning)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(AppTheme.warning.opacity(0.14)))
                            }
                        }

                        Text(descriptor.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    if descriptor.exists {
                        if let preferredEditor = appModel.externalEditors.preferredEditor {
                            Button {
                                try? appModel.externalEditors.open(path: descriptor.path, in: preferredEditor)
                            } label: {
                                Label(preferredEditor.name, systemImage: "square.and.pencil")
                            }
                            .controlSize(.small)
                        }

                        Button("Reveal in Finder") {
                            appModel.externalEditors.revealInFinder(path: descriptor.path)
                        }
                        .controlSize(.small)
                    }

                    if hasUnsavedChanges {
                        Button("Revert") {
                            editorContent = loadedBaseline
                        }
                        .controlSize(.small)
                    }

                    Button {
                        Task { await saveCurrentInstruction(descriptor) }
                    } label: {
                        HStack(spacing: 5) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(descriptor.exists ? "Save" : "Create & Save")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(isSaving || (!hasUnsavedChanges && descriptor.exists))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(AppTheme.controlBackground)

                Divider()

                if isLoadingFile {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Reading \(descriptor.title)…")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextEditor(text: $editorContent)
                        .font(AppTheme.codeFont(scale: appModel.fontScale, size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(AppTheme.textBackground)
                }
            }
        } else {
            ContentUnavailableView(
                isLoadingList ? "Scanning Instruction Files…" : "Select an Instruction File",
                systemImage: "doc.text",
                description: Text("Edit AGENTS.md, CLAUDE.md, GEMINI.md, or .cursorrules to steer every coding agent in your workspace.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Runtime Operations

    private func reloadInstructionsList() async {
        guard let runtime = appModel.runtime else { return }
        isLoadingList = true
        defer { isLoadingList = false }
        do {
            let list = try await runtime.listInstructions(projectRoot: appModel.activeWorkingDirectory)
            self.descriptors = list
            if selectedPath == nil || !list.contains(where: { $0.path == selectedPath }) {
                let initial = list.first(where: \.exists) ?? list.first
                self.selectedPath = initial?.path
                if let p = initial?.path {
                    await loadSelectedInstruction(path: p)
                }
            }
        } catch {
            appModel.presentError(error)
        }
    }

    private func loadSelectedInstruction(path: String) async {
        guard let runtime = appModel.runtime else { return }
        let descriptor = descriptors.first { $0.path == path }
        guard descriptor?.exists == true else {
            editorContent = defaultTemplate(for: descriptor?.title ?? "AGENTS.md")
            loadedBaseline = ""
            return
        }

        isLoadingFile = true
        defer { isLoadingFile = false }
        do {
            let text = try await runtime.readInstruction(
                path: path,
                projectRoot: appModel.activeWorkingDirectory
            )
            if selectedPath == path {
                self.editorContent = text
                self.loadedBaseline = text
            }
        } catch {
            if selectedPath == path {
                self.editorContent = ""
                self.loadedBaseline = ""
            }
            appModel.presentError(error)
        }
    }

    private func saveCurrentInstruction(_ descriptor: InstructionFileDescriptor) async {
        guard let runtime = appModel.runtime else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await runtime.saveInstruction(
                path: descriptor.path,
                content: editorContent,
                projectRoot: appModel.activeWorkingDirectory,
                expectedContent: descriptor.exists ? loadedBaseline : nil
            )
            self.loadedBaseline = editorContent
            await reloadInstructionsList()
            appModel.presentToast("Saved \(descriptor.title)", style: .success)
        } catch {
            appModel.presentError(error)
        }
    }

    private func defaultTemplate(for filename: String) -> String {
        """
        # \(filename)

        ## Architecture & Conventions
        - Follow project coding style and Swift / Rust concurrency safety guidelines.
        - Prefer minimal, well-tested changes over speculative refactors.
        """
    }
}
