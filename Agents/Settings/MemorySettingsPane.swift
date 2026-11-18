import AppKit
import CoincideRemoteKit
import SwiftUI

public struct MemorySettingsPane: View {
    @Bindable public var appModel: AppModel

    private enum ScopeFilter: String, CaseIterable {
        case all
        case global
        case workspace

        var title: String {
            switch self {
            case .all: "All scopes"
            case .global: "Global"
            case .workspace: "Workspace"
            }
        }
    }

    @State private var entries: [MemoryEntry] = []
    @State private var searchText: String = ""
    @State private var scopeFilter: ScopeFilter = .all
    @State private var workspaceScopeText: String
    @State private var newKey: String = ""
    @State private var newValue: String = ""
    @State private var newScopeIsWorkspace: Bool = false
    @State private var isLoading: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var clearScopeIsWorkspace: Bool = false
    @State private var showClearConfirm: Bool = false
    @State private var isClearing: Bool = false

    public init(appModel: AppModel) {
        self.appModel = appModel
        self._workspaceScopeText = State(initialValue: appModel.activeWorkingDirectory ?? "")
    }

    private var workspaceScope: String {
        "workspace:" + workspaceScopeText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var listScope: String? {
        switch scopeFilter {
        case .all: nil
        case .global: "global"
        case .workspace: workspaceScopeText.isEmpty ? nil : workspaceScope
        }
    }

    private var clearScope: String {
        clearScopeIsWorkspace ? workspaceScope : "global"
    }

    private var canSaveEntry: Bool {
        !newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !newValue.isEmpty
            && (!newScopeIsWorkspace || !workspaceScopeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                addEntrySection
                listSection
                clearSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Memory")
        .alert("Clear \(clearScopeIsWorkspace ? "Workspace" : "Global") Memory?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task { await clearSelectedScope() }
            }
        } message: {
            Text("This deletes every memory entry in the \(clearScopeIsWorkspace ? "workspace" : "global") scope. This cannot be undone.")
        }
        .task {
            await reloadEntries()
        }
        .onChange(of: scopeFilter) { _, _ in
            Task { await reloadEntries() }
        }
        .onChange(of: workspaceScopeText) { _, _ in
            Task { await reloadEntries() }
        }
        .onSubmit {
            Task { await reloadEntries() }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent memory is stored in the local SQLite store and survives restarts. Retrieval is keyword search only; there are no embeddings.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.danger)
            }
        }
    }

    private var addEntrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a memory")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 10) {
                TextField("Key", text: $newKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                TextField("Value", text: $newValue)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $newScopeIsWorkspace) {
                    Text("Global").tag(false)
                    Text("Workspace").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .accessibilityLabel("Scope for new memory")
                Button("Save") {
                    Task { await saveEntry() }
                }
                .disabled(!canSaveEntry || isSaving)
            }
            if newScopeIsWorkspace {
                TextField("Workspace identifier (absolute path)", text: $workspaceScopeText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Stored memories")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                TextField("Search keys and values", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Picker("", selection: $scopeFilter) {
                    ForEach(ScopeFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .accessibilityLabel("Filter memories by scope")
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if scopeFilter == .workspace {
                TextField("Workspace identifier (absolute path)", text: $workspaceScopeText)
                    .textFieldStyle(.roundedBorder)
            }
            if entries.isEmpty && !isLoading {
                Text("No memories in this scope yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        memoryRow(entry)
                        if entry.id != entries.last?.id {
                            Divider()
                        }
                    }
                }
                .background(AppTheme.windowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    private func memoryRow(_ entry: MemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(entry.key)
                        .font(.system(size: 13, weight: .semibold))
                    Text(entry.scope)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }
                Text(entry.value)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(Date(timeIntervalSince1970: entry.updatedAt), format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Delete") {
                Task { await deleteEntry(entry) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
    }

    private var clearSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clear a scope")
                .font(.system(size: 13, weight: .semibold))
            Text("Clearing deletes every entry in the selected scope. This cannot be undone.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Picker("", selection: $clearScopeIsWorkspace) {
                    Text("Global").tag(false)
                    Text("Workspace").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .accessibilityLabel("Scope to clear")
                if clearScopeIsWorkspace {
                    TextField("Workspace identifier (absolute path)", text: $workspaceScopeText)
                        .textFieldStyle(.roundedBorder)
                }
                Spacer()
            }
            Button("Clear scope") {
                showClearConfirm = true
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.danger)
            .disabled(isClearing || (clearScopeIsWorkspace && workspaceScopeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
    }

    private func reloadEntries() async {
        guard let runtime = appModel.runtime else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await runtime.memoryList(scope: listScope, query: searchText.isEmpty ? nil : searchText)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveEntry() async {
        guard let runtime = appModel.runtime else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let scope = newScopeIsWorkspace ? workspaceScope : "global"
            _ = try await runtime.memoryStore(key: newKey.trimmingCharacters(in: .whitespacesAndNewlines), value: newValue, scope: scope)
            newKey = ""
            newValue = ""
            errorMessage = nil
            await reloadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteEntry(_ entry: MemoryEntry) async {
        guard let runtime = appModel.runtime else { return }
        do {
            _ = try await runtime.memoryDelete(key: entry.key, scope: entry.scope)
            errorMessage = nil
            await reloadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearSelectedScope() async {
        guard let runtime = appModel.runtime else { return }
        isClearing = true
        defer { isClearing = false }
        do {
            _ = try await runtime.memoryClear(scope: clearScope, confirm: true)
            errorMessage = nil
            await reloadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
