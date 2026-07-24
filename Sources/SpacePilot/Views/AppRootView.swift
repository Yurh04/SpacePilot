import SpacePilotCore
import SwiftUI

struct AppRootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            detail
        }
        .tint(.blue)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: L10n.text(.searchCurrent))
        .toolbar {
            ToolbarItemGroup {
                if model.isScanning {
                    Button(L10n.cancel(), systemImage: "xmark") { model.cancelScan() }
                        .keyboardShortcut(.cancelAction)
                } else if model.canRefreshCurrentView {
                    Button(L10n.scan(), systemImage: "arrow.clockwise") {
                        model.refreshCurrentView()
                    }
                        .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.isScanning || model.errorMessage != nil {
                ScanStatusView(model: model)
            }
        }
        .sheet(isPresented: $model.showingCleanupConfirmation) {
            CleanupConfirmationView(
                items: model.cleanupCandidates,
                isExecuting: model.isCleaning,
                onConfirm: model.executePreparedCleanup,
                onCancel: { model.showingCleanupConfirmation = false }
            )
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection ?? .overview {
        case .overview:
            OverviewView(
                projection: model.projection?.overview,
                hasSnapshot: model.latestSnapshot != nil,
                startScan: { model.startScan(scope: .full) },
                reviewCleanup: model.prepareCleanup
            )
        case .storage:
            StorageView(
                projection: model.projection?.storage,
                hasSnapshot: model.latestSnapshot != nil,
                searchText: model.searchText,
                reviewCleanup: model.prepareCleanup
            )
        case .applications:
            ApplicationsView(
                projection: model.projection?.applications,
                hasSnapshot: model.latestSnapshot != nil,
                searchText: model.searchText,
                uninstall: model.prepareUninstall,
                reset: model.prepareReset
            )
        case .developerAI:
            DeveloperAIView(
                model: model,
                projection: model.projection?.developerAI,
                hasSnapshot: model.latestSnapshot != nil
            )
        case .history:
            CleanupHistoryView(transactions: model.cleanupHistory)
        }
    }
}
