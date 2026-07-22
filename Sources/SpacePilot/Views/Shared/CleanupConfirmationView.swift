import SpacePilotCore
import SwiftUI

struct CleanupConfirmationView: View {
    let items: [ScannedItem]
    let isExecuting: Bool
    let onConfirm: (Bool) -> Void
    let onCancel: () -> Void
    @State private var understandsTrash = false
    @State private var confirmsSensitive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: L10n.text(.cleanupReview))
                .font(.title2.weight(.semibold))
            Text(verbatim: L10n.text(.cleanupReviewDescription))
                .foregroundStyle(.secondary)

            List(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.url.lastPathComponent).fontWeight(.medium)
                        Spacer()
                        Text(ByteCount.string(item.allocatedSize)).monospacedDigit()
                    }
                    Text(item.url.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(verbatim: "\(L10n.name(for: item.risk)) · \(L10n.explanation(item.explanation))")
                        .font(.caption)
                        .foregroundStyle(item.risk == .sensitive ? .orange : .secondary)
                }
            }
            .frame(minHeight: 220)

            Toggle(L10n.text(.cleanupConfirmTrash), isOn: $understandsTrash)
            if hasSensitiveItems {
                Toggle(L10n.text(.cleanupConfirmSensitive), isOn: $confirmsSensitive)
            }

            HStack {
                Spacer()
                Button(L10n.cancel(), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isExecuting ? L10n.text(.cleanupMoving) : L10n.text(.cleanupMoveTrash)) {
                    onConfirm(confirmsSensitive)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!understandsTrash || (hasSensitiveItems && !confirmsSensitive) || isExecuting)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 480)
    }

    private var hasSensitiveItems: Bool {
        items.contains { $0.risk == .sensitive }
    }
}
