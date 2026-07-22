import SwiftUI

struct CleanupHistoryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No cleanup history", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Verified cleanup operations will appear here.")
        }
        .navigationTitle("Cleanup History")
    }
}
