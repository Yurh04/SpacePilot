import SpacePilotCore
import SwiftUI

struct StorageItemRow: View {
    let item: ScannedItem

    var body: some View {
        HStack {
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
        .contextMenu { Button(L10n.text(.revealFinder)) { reveal(item.url) } }
        .accessibilityLabel("\(item.url.lastPathComponent), \(ByteCount.string(item.allocatedSize)), \(L10n.name(for: item.risk))")
    }
}
