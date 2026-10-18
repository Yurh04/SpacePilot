import SpacePilotCore
import SwiftUI

/// Rebuildable global caches owned by development toolchains. Nothing is
/// selected automatically because removing these may trigger large downloads
/// or long rebuilds on the next use.
struct DeveloperStorageView: View {
    let projection: DeveloperStorageProjection?
    let searchText: String
    let scan: () -> Void
    let reviewCleanup: ([ScannedItem]) -> Void

    @State private var selectedItemIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            AIWorkspaceHeader(
                title: L10n.text(.developerToolsTitle),
                systemImage: "hammer",
                subtitle: L10n.text(.developerToolsSubtitle),
                count: projection?.items.count ?? 0
            )

            HStack(spacing: 12) {
                Label(L10n.text(.developerToolsCheckFirst), systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Spacer()
                Button(L10n.text(.developerToolsScan), systemImage: "arrow.clockwise", action: scan)
            }
            .padding(.horizontal, AIWorkspaceLayout.pagePadding)
            .padding(.bottom, 10)

            if rows.isEmpty {
                ContentUnavailableView(
                    L10n.text(.developerToolsEmpty),
                    systemImage: "hammer",
                    description: Text(verbatim: L10n.text(.developerToolsEmptyDescription))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { item in
                    HStack(spacing: 10) {
                        Toggle("", isOn: selectionBinding(for: item.id))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        AIAssetIdentity(
                            name: L10n.developerToolName(
                                relativePath: item.cleanupPolicyRelativePath,
                                fallback: item.explanation
                            ),
                            subtitle: item.url.path,
                            url: item.url
                        )
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(ByteCount.string(item.allocatedSize))
                                .fontWeight(.medium)
                                .monospacedDigit()
                            Text(verbatim: L10n.name(for: item.risk))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onDoubleClickRevealInFinder(item.url)
                    .contextMenu {
                        Button(L10n.text(.revealFinder)) { FinderReveal.reveal(item.url) }
                    }
                }
                .listStyle(.inset)
                .nativeTableHoverHighlight { rows.indices.contains($0) }
            }

            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: projectionSignature) { _, _ in selectedItemIDs.removeAll() }
    }

    private var rows: [ScannedItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projection?.items ?? [] }
        return (projection?.items ?? []).filter {
            $0.explanation.localizedCaseInsensitiveContains(query)
                || $0.url.path.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedItems: [ScannedItem] {
        (projection?.items ?? []).filter { selectedItemIDs.contains($0.id) }
    }

    private var actionBar: some View {
        let selected = selectedItems
        let bytes = selected.reduce(Int64(0)) { $0 + $1.allocatedSize }
        return HStack {
            Text(verbatim: L10n.selectedItems(
                selected.count,
                space: bytes == 0 ? "0 KB" : ByteCount.string(bytes)
            ))
            .font(.headline)
            .monospacedDigit()
            Spacer()
            Button(L10n.text(.cleanupClearSelection)) { selectedItemIDs.removeAll() }
                .disabled(selected.isEmpty)
            Button(L10n.text(.developerToolsReview), systemImage: "trash") {
                reviewCleanup(selected)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
        .padding(AIWorkspaceLayout.pagePadding)
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedItemIDs.contains(id) },
            set: { selected in
                if selected { selectedItemIDs.insert(id) }
                else { selectedItemIDs.remove(id) }
            }
        )
    }

    private var projectionSignature: String {
        (projection?.items ?? []).map { "\($0.id.uuidString):\($0.allocatedSize)" }
            .joined(separator: "|")
    }
}
