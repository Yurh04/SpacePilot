import AppKit
import SpacePilotCore
import SwiftUI

struct StorageView: View {
    let projection: StorageProjection?
    let hasSnapshot: Bool
    let searchText: String
    let reviewCleanup: ([ScannedItem]) -> Void
    @State private var mode: StorageItemMode = .largest

    var body: some View {
        if let projection {
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

                Picker("Items", selection: $mode) {
                    ForEach(StorageItemMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                .padding(10)

                Table(filtered(mode == .largest ? projection.largestItems : projection.oldItems)) {
                    TableColumn(mode == .largest ? "Largest analyzed items" : "Not modified in 180+ days") { item in
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
        } else if hasSnapshot {
            ProgressView("Preparing summary…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private enum StorageItemMode: String, CaseIterable, Identifiable {
    case largest
    case old

    var id: Self { self }
    var title: String { self == .largest ? "Largest" : "Older than 180 days" }
}

func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

@ViewBuilder
func empty(_ title: String, image: String) -> some View {
    ContentUnavailableView(title, systemImage: image, description: Text("Run a scan to see local results."))
        .navigationTitle(title)
}
