import CoincideRemoteKit
import SwiftUI

public struct MainWindowView: View {
    @Bindable public var appModel: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage(AssistantLibrarySidebarSelection.userDefaultsKey) private var librarySelectionRaw: String = ""

    private var librarySelection: AssistantLibrarySidebarSelection? {
        AssistantLibrarySidebarSelection(storedValue: librarySelectionRaw)
    }

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarContainerView(appModel: appModel)
                .navigationSplitViewColumnWidth(
                    min: AppTheme.sidebarMinWidth,
                    ideal: AppTheme.sidebarIdealWidth,
                    max: 420
                )
        } detail: {
            detailContent
                .inspector(isPresented: $appModel.inspectorVisible) {
                    InspectorContainerView(appModel: appModel)
                        .inspectorColumnWidth(
                            min: AppTheme.inspectorMinWidth,
                            ideal: AppTheme.inspectorIdealWidth,
                            max: 560
                        )
                }
        }
        .preferredColorScheme(appModel.appearancePreference.colorScheme)
        .overlay(alignment: .bottom) {
            if let toast = appModel.toastMessage {
                ToastBannerOverlay(toast: toast, appModel: appModel)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: appModel.toastMessage)
        .sheet(isPresented: $appModel.showCommandPalette) {
            CommandPaletteContainerSheet(appModel: appModel)
        }
        .sheet(isPresented: $appModel.showBotEditor) {
            BotEditorContainerSheet(appModel: appModel)
        }
        .sheet(isPresented: $appModel.showSessionImport) {
            SessionImportContainerSheet(appModel: appModel)
        }
        .sheet(isPresented: $appModel.showAssistantEditor) {
            AssistantEditorContainerSheet(appModel: appModel)
        }
        .sheet(isPresented: $appModel.showAssistantLaunch) {
            AssistantLaunchContainerSheet(appModel: appModel)
        }
        .sheet(isPresented: $appModel.showAssistantResult) {
            AssistantResultContainerSheet(appModel: appModel)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selection = librarySelection {
            AssistantLibraryView(
                appModel: appModel,
                onEdit: { definition in appModel.openAssistantEditor(for: definition) },
                initialSelection: selection
            )
        } else {
            VSplitView {
                ConversationContainerView(appModel: appModel)
                    .frame(minWidth: 520, minHeight: 320, maxHeight: .infinity)

                if appModel.terminalVisible {
                    TerminalContainerView(appModel: appModel)
                        .frame(minHeight: 160, idealHeight: 250, maxHeight: 520)
                }
            }
        }
    }
}

private struct ToastBannerOverlay: View {
    let toast: ToastMessage
    let appModel: AppModel

    private var iconName: String {
        switch toast.style {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var iconTint: Color {
        switch toast.style {
        case .info: AppTheme.info
        case .success: AppTheme.success
        case .warning: AppTheme.warning
        case .error: AppTheme.danger
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconTint)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryLabel)
                if let detail = toast.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                }
            }

            if let undoTitle = toast.undoActionTitle {
                Button(undoTitle) {
                    appModel.performToastUndo()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button {
                appModel.dismissToast()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPanel()
    }
}
