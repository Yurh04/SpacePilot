import SpacePilotCore
import SwiftUI

struct InspectorDetailView: View {
    let item: ScannedItem

    var body: some View {
        Form {
            LabeledContent(L10n.text(.name), value: item.url.lastPathComponent)
                .onDoubleClickRevealInFinder(item.url)
            LabeledContent(L10n.location(), value: item.url.path(percentEncoded: false))
                .onDoubleClickRevealInFinder(item.url)
            LabeledContent(L10n.space(), value: ByteCount.string(item.allocatedSize))
            LabeledContent(L10n.risk(), value: L10n.name(for: item.risk))
            Text(verbatim: L10n.explanation(item.explanation)).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
