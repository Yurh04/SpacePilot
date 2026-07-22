import SpacePilotCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(NavigationDestination.allCases, selection: $model.selection) { destination in
            Label(L10n.title(for: destination), systemImage: destination.systemImage)
                .tag(destination)
        }
        .listStyle(.sidebar)
        .navigationTitle("SpacePilot")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
    }
}
