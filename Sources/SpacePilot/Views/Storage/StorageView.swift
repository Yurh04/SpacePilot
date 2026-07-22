import AppKit
import SpacePilotCore
import SwiftUI

struct StorageView: View {
    let snapshot: ScanSnapshot?
    let searchText: String
    let reviewCleanup: ([ScannedItem]) -> Void

    var body: some View {
        if let snapshot {
            let projection = StorageProjection(snapshot: snapshot)
            VStack(spacing: 0) {
                Table(projection.categories) {
                    TableColumn("Category") { summary in
                        Text(summary.category.displayName)
                    }
                    TableColumn("Items") { summary in
                        Text(summary.itemCount.formatted())
                    }
                    .width(70)
                    TableColumn("Space") { summary in
                        Text(ByteCount.string(summary.allocatedSize))
                            .monospacedDigit()
                    }
                    .width(100)
                }
                .frame(minHeight: 180, idealHeight: 240)

                Divider()

                Table(filtered(projection.largestItems)) {
                    TableColumn("Largest analyzed items") { item in
                        Text(item.url.lastPathComponent)
                            .contextMenu {
                                Button("Reveal in Finder") { reveal(item.url) }
                                if item.risk == .safe {
                                    Button("Review Cleanup") { reviewCleanup([item]) }
                                }
                            }
                    }
                    TableColumn("Location") { item in
                        Text(item.url.deletingLastPathComponent().path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Risk") { item in
                        Text(item.risk.displayName)
                    }
                    .width(120)
                    TableColumn("Space") { item in
                        Text(ByteCount.string(item.allocatedSize)).monospacedDigit()
                    }
                    .width(100)
                }
            }
            .navigationTitle("Storage")
        } else {
            empty("Storage", image: "internaldrive")
        }
    }

    private func filtered(_ items: [ScannedItem]) -> [ScannedItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.url.path.localizedCaseInsensitiveContains(searchText) }
    }
}

func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

@ViewBuilder
func empty(_ title: String, image: String) -> some View {
    ContentUnavailableView(title, systemImage: image, description: Text("Run a scan to see local results."))
        .navigationTitle(title)
}
