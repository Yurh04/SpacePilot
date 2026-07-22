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
                    TableColumn(L10n.text(.category)) { summary in
                        Text(verbatim: L10n.name(for: summary.category))
                    }
                    TableColumn(L10n.text(.items)) { summary in
                        Text(summary.itemCount.formatted())
                    }
                    .width(70)
                    TableColumn(L10n.space()) { summary in
                        Text(ByteCount.string(summary.allocatedSize))
                            .monospacedDigit()
                    }
                    .width(100)
                }
                .frame(minHeight: 180, idealHeight: 240)

                Divider()

                Picker(L10n.text(.items), selection: $mode) {
                    ForEach(StorageItemMode.allCases) { mode in
                        Text(verbatim: mode == .largest ? L10n.text(.storageLargest) : L10n.text(.storageOlder180)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                .padding(10)

                Table(filtered(mode == .largest ? projection.largestItems : projection.oldItems)) {
                    TableColumn(mode == .largest ? L10n.text(.storageLargestItems) : L10n.text(.storageOldItems)) { item in
                        Text(item.url.lastPathComponent)
                            .contextMenu {
                                Button(L10n.text(.revealFinder)) { reveal(item.url) }
                                if item.risk == .safe {
                                    Button(L10n.text(.cleanupReview)) { reviewCleanup([item]) }
                                }
                            }
                    }
                    TableColumn(L10n.location()) { item in
                        Text(item.url.deletingLastPathComponent().path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn(L10n.risk()) { item in
                        Text(verbatim: L10n.name(for: item.risk))
                    }
                    .width(120)
                    TableColumn(L10n.space()) { item in
                        Text(ByteCount.string(item.allocatedSize)).monospacedDigit()
                    }
                    .width(100)
                }
            }
            .navigationTitle(L10n.storage())
        } else if hasSnapshot {
            ProgressView(L10n.preparingSummary())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(L10n.storage())
        } else {
            empty(L10n.storage(), image: "internaldrive")
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
}

func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

@ViewBuilder
func empty(_ title: String, image: String) -> some View {
    ContentUnavailableView(title, systemImage: image, description: Text(verbatim: L10n.noData()))
        .navigationTitle(title)
}
