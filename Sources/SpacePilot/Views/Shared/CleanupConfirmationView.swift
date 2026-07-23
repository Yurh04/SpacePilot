import SpacePilotCore
import SwiftUI

struct CleanupConfirmationView: View {
    let items: [CleanupReviewItem]
    let isExecuting: Bool
    let onConfirm: (Set<UUID>, Bool) -> Void
    let onCancel: () -> Void
    @State private var selection: CleanupSelection
    @State private var understandsTrash = false
    @State private var confirmsSensitive = false

    init(
        items: [CleanupReviewItem],
        isExecuting: Bool,
        onConfirm: @escaping (Set<UUID>, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.items = items
        self.isExecuting = isExecuting
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selection = State(initialValue: CleanupSelection(items: items))
    }

    var body: some View {
        let selectedSpace = selection.selectedBytes == 0 ? "0 KB" : ByteCount.string(selection.selectedBytes)

        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: L10n.text(.cleanupReview))
                .font(.title2.weight(.semibold))
            Text(verbatim: L10n.text(.cleanupReviewDescription))
                .foregroundStyle(.secondary)

            HStack {
                Text(verbatim: L10n.itemCount(items.count))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text(.cleanupSelectAll)) {
                    selection.selectAll()
                }
                .disabled(isExecuting || !selection.hasUnselectedSelectAllItems)
                Button(L10n.text(.cleanupClearSelection)) {
                    selection.clear()
                }
                .disabled(isExecuting || selection.selectedIDs.isEmpty)
            }

            List(items) { reviewItem in
                let item = reviewItem.item
                let risk = reviewItem.effectiveRisk
                Toggle(isOn: binding(for: reviewItem)) {
                    HStack(alignment: .top, spacing: 8) {
                        FileSystemItemIcon(url: item.url)
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
                            Text(verbatim: "\(L10n.name(for: risk)) · \(L10n.explanation(item.explanation))")
                                .font(.caption)
                                .foregroundStyle(risk == .sensitive ? .orange : .secondary)
                            HStack(spacing: 4) {
                                if reviewItem.ownership == .shared {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .accessibilityHidden(true)
                                }
                                Text(verbatim: L10n.name(for: reviewItem.ownership))
                                if let evidence = reviewItem.evidence {
                                    Text(verbatim: "·")
                                    Text(verbatim: L10n.name(for: evidence))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(
                                reviewItem.ownership == .shared ? .orange : .secondary
                            )
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(isExecuting)
            }
            .frame(minHeight: 220)

            Text(verbatim: L10n.selectedItems(
                selection.selectedIDs.count,
                space: selectedSpace
            ))
            .font(.headline)
            .monospacedDigit()

            Toggle(L10n.text(.cleanupConfirmTrash), isOn: $understandsTrash)
            if hasSensitiveItems {
                Toggle(L10n.text(.cleanupConfirmSensitive), isOn: $confirmsSensitive)
            }

            HStack {
                Spacer()
                Button(L10n.cancel(), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isExecuting
                    ? L10n.text(.cleanupMoving)
                    : L10n.text(.cleanupMoveSelectedTrash)
                ) {
                    onConfirm(selection.selectedIDs, confirmsSensitive)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    selection.selectedIDs.isEmpty
                        || !understandsTrash
                        || (hasSensitiveItems && !confirmsSensitive)
                        || isExecuting
                )
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 480)
    }

    private var hasSensitiveItems: Bool {
        selection.hasSelectedSensitiveItems
    }

    private func binding(for item: CleanupReviewItem) -> Binding<Bool> {
        Binding(
            get: { selection.selectedIDs.contains(item.id) },
            set: { isSelected in
                guard isSelected != selection.selectedIDs.contains(item.id) else { return }
                selection.toggle(item.id)
            }
        )
    }
}
