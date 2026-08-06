import SpacePilotCore
import SwiftUI

struct StorageItemRow: View {
    let item: ScannedItem

    var body: some View {
        HStack {
            FileSystemItemIcon(url: item.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                Text(verbatim: L10n.explanation(item.explanation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(ByteCount.string(item.allocatedSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .onDoubleClickRevealInFinder(item.url)
        .contextMenu { Button(L10n.text(.revealFinder)) { FinderReveal.reveal(item.url) } }
        .accessibilityLabel("\(item.url.lastPathComponent), \(ByteCount.string(item.allocatedSize)), \(L10n.name(for: item.risk))")
    }
}
