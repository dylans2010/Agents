import SwiftUI

public struct AssistantLibraryView: View {
    @Bindable public var appModel: AppModel
    public let onEdit: @MainActor (AssistantDefinition?) -> Void
    public let initialSelection: AssistantLibrarySidebarSelection?

    @State private var viewModel: AssistantLibraryViewModel

    public init(
        appModel: AppModel,
        onEdit: @escaping @MainActor (AssistantDefinition?) -> Void,
        onAddToAutomation: AssistantAutomationRequestHandler? = nil,
        initialSelection: AssistantLibrarySidebarSelection? = nil
    ) {
        self.appModel = appModel
        self.onEdit = onEdit
        self.initialSelection = initialSelection
        _viewModel = State(initialValue: AssistantLibraryViewModel(
            catalog: appModel.assistantCatalog,
            store: .live(appModel: appModel),
            initialSelection: initialSelection,
            onAddToAutomation: onAddToAutomation
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            libraryToolbar
            Divider()
            libraryContent
        }
        .background(AppTheme.windowBackground)
        .onAppear {
            viewModel.catalog = appModel.assistantCatalog
        }
        .onChange(of: appModel.assistants) { _, _ in
            viewModel.catalog = appModel.assistantCatalog
        }
        .onChange(of: initialSelection) { _, newValue in
            viewModel.applySidebarSelection(newValue)
        }
    }

    private var libraryToolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.tertiaryLabel)
                TextField("Search assistants…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(AppTheme.bodyFont())
                    .accessibilityLabel("Search assistants")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.controlBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            .frame(maxWidth: 280)

            Picker("Scope", selection: $viewModel.scope) {
                ForEach(AssistantLibraryScope.allCases, id: \.self) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)

            Menu {
                Picker("Category", selection: $viewModel.selectedCategory) {
                    Text("All Categories").tag(nil as AssistantCategory?)
                    ForEach(AssistantCategory.allCases, id: \.self) { category in
                        Text(category.displayName).tag(category as AssistantCategory?)
                    }
                }
            } label: {
                Label(viewModel.selectedCategory?.displayName ?? "All Categories", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Menu {
                Picker("Sort", selection: $viewModel.sortOrder) {
                    ForEach(AssistantLibrarySortOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
            } label: {
                Label("Sort: \(viewModel.sortOrder.title)", systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Spacer()

            Button {
                onEdit(nil)
            } label: {
                Label("New Assistant", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var libraryListColumn: some View {
        if viewModel.visibleDefinitions.isEmpty {
            ContentUnavailableView {
                Label("No Matching Assistants", systemImage: "magnifyingglass")
            } description: {
                if viewModel.catalog.allDefinitions.isEmpty {
                    Text("No assistants are available yet.")
                } else {
                    Text("Try a different search or filter.")
                }
            } actions: {
                if !viewModel.searchText.isEmpty || viewModel.selectedCategory != nil || viewModel.scope != .all {
                    Button("Clear Search & Filters") {
                        viewModel.searchText = ""
                        viewModel.selectedCategory = nil
                        viewModel.scope = .all
                    }
                }
            }
        } else {
            List(selection: $viewModel.selectedDefinitionID) {
                ForEach(viewModel.visibleDefinitions) { definition in
                    AssistantLibraryRow(
                        definition: definition,
                        isFavorite: viewModel.isFavorite(definition)
                    ) {
                        Task { await viewModel.toggleFavorite(definition) }
                    }
                    .tag(definition.id)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if !appModel.assistantsLoaded {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading assistants…")
                    .font(AppTheme.bodyFont())
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            NavigationSplitView {
                libraryListColumn
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
            } detail: {
                if let definition = viewModel.selectedDefinition {
                    AssistantLibraryDetailView(
                        definition: definition,
                        isFavorite: viewModel.isFavorite(definition),
                        canDelete: viewModel.canDelete(definition),
                        canRestoreDefaults: viewModel.canRestoreDefaults(definition),
                        showsAutomationAction: viewModel.onAddToAutomation != nil,
                        onToggleFavorite: {
                            Task { await viewModel.toggleFavorite(definition) }
                        },
                        onDuplicate: {
                            Task {
                                if let copy = await viewModel.duplicate(definition) {
                                    viewModel.selectedDefinitionID = copy.id
                                }
                            }
                        },
                        onEdit: { selected in
                            onEdit(selected)
                        },
                        onDelete: {
                            Task { await viewModel.deleteCustom(definition) }
                        },
                        onRestoreDefaults: {
                            Task { await viewModel.restoreDefaults(definition) }
                        },
                        onAddToAutomation: {
                            viewModel.requestAddToAutomation(definition)
                        },
                        onLaunch: { task in
                            Task { await viewModel.launch(definition, task: task) }
                        }
                    )
                } else {
                    ContentUnavailableView {
                        Label("Select an Assistant", systemImage: "square.stack.3d.up")
                    } description: {
                        Text("Choose an assistant to preview its instructions, capabilities, and model.")
                    }
                }
            }
        }
    }
}
