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
                if model.showsScanStatus {
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
            if model.showsScanStatus || model.errorMessage != nil {
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
                latestCleanup: model.cleanupHistory.first,
                changeHistory: model.storageChangeHistory,
                startScan: { model.startScan(scope: .full) },
                reviewCleanup: model.prepareCleanup,
                openStorage: {
                    model.storageItemMode = .largest
                    model.selection = .storage
                },
                openRecentChanges: {
                    model.storageItemMode = .recent
                    model.selection = .storage
                },
                openApplications: { model.selection = .applications },
                openHistory: { model.selection = .history },
                openDiskAccessSettings: {
                    PermissionService().openFullDiskAccessSettings()
                }
            )
        case .storage:
            StorageView(
                projection: model.projection?.storage,
                changeHistory: model.storageChangeHistory,
                hasSnapshot: model.latestSnapshot != nil,
                searchText: model.searchText,
                mode: $model.storageItemMode,
                reviewCleanup: model.prepareCleanup
            )
        case .applications:
            ApplicationsView(
                projection: model.projection?.applications,
                hasSnapshot: model.latestSnapshot != nil,
                relatedFileSearchText: model.searchText,
                analyzingApplicationID: model.analyzingApplicationID,
                applicationAnalysisDates: model.applicationAnalysisDates,
                analyze: model.analyzeApplication,
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
