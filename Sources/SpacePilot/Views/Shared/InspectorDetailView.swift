import SpacePilotCore
import SwiftUI

struct InspectorDetailView: View {
    let item: ScannedItem

    var body: some View {
        Form {
            LabeledContent("Name", value: item.url.lastPathComponent)
            LabeledContent("Location", value: item.url.path(percentEncoded: false))
            LabeledContent("Space", value: ByteCount.string(item.allocatedSize))
            LabeledContent("Risk", value: item.risk.displayName)
            Text(item.explanation).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
