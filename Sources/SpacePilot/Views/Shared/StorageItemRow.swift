import SpacePilotCore
import SwiftUI

struct StorageItemRow: View {
    let item: ScannedItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                Text(item.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(ByteCount.string(item.allocatedSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contextMenu { Button("Reveal in Finder") { reveal(item.url) } }
        .accessibilityLabel("\(item.url.lastPathComponent), \(ByteCount.string(item.allocatedSize)), \(item.risk.displayName)")
    }
}
