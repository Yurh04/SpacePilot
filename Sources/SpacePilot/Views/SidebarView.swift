import SpacePilotCore
import SwiftUI

struct SidebarView: View {
    private static let stableWidth: CGFloat = 220

    @Bindable var model: AppModel

    var body: some View {
        List(NavigationDestination.allCases, selection: $model.selection) { destination in
            Label(L10n.title(for: destination), systemImage: destination.systemImage)
                .tag(destination)
        }
        .listStyle(.sidebar)
        .frame(width: Self.stableWidth)
        .navigationTitle("SpacePilot")
        .navigationSplitViewColumnWidth(
            min: Self.stableWidth,
            ideal: Self.stableWidth,
            max: Self.stableWidth
        )
    }
}
