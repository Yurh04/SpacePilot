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
            Text("Review Cleanup")
                .font(.title2.weight(.semibold))
            Text("These exact items will be moved to the Trash. You can restore them from the Trash until it is emptied.")
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
                    Text("\(item.risk.displayName) · \(item.explanation)")
                        .font(.caption)
                        .foregroundStyle(item.risk == .sensitive ? .orange : .secondary)
                }
            }
            .frame(minHeight: 220)

            Toggle("I understand these items will be moved to the Trash", isOn: $understandsTrash)
            if hasSensitiveItems {
                Toggle("Also move the sensitive conversation, project, or settings data listed above", isOn: $confirmsSensitive)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isExecuting ? "Moving…" : "Move to Trash") {
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
