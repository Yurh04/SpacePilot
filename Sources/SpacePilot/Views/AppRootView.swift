import SpacePilotCore
import SwiftUI

struct AppRootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(NavigationDestination.allCases, selection: $model.selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .listStyle(.sidebar)
            .navigationTitle("SpacePilot")
        } detail: {
            ContentUnavailableView {
                Label(
                    model.selection?.title ?? "SpacePilot",
                    systemImage: model.selection?.systemImage ?? "internaldrive"
                )
            } description: {
                Text("Local storage analysis will appear here.")
            }
        }
        .tint(.blue)
    }
}
