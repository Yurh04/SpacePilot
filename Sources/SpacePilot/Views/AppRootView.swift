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
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search current view")
        .toolbar {
            ToolbarItemGroup {
                if model.isScanning {
                    Button("Cancel", systemImage: "xmark") { model.cancelScan() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Scan", systemImage: "arrow.clockwise") { model.startScan() }
                        .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.isScanning || model.errorMessage != nil {
                ScanStatusView(model: model)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection ?? .overview {
        case .overview:
            OverviewView(snapshot: model.latestSnapshot, startScan: model.startScan)
        case .storage:
            StorageView(snapshot: model.latestSnapshot, searchText: model.searchText)
        case .applications:
            ApplicationsView(snapshot: model.latestSnapshot, searchText: model.searchText)
        case .developerAI:
            DeveloperAIView(model: model)
        case .history:
            CleanupHistoryView()
        }
    }
}
