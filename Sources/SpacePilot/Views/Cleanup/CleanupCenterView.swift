import SpacePilotCore
import SwiftUI

enum CleanupCenterSection: String, CaseIterable, Identifiable {
    case recommended
    case applicationCaches
    case developerTools

    var id: Self { self }
}

/// The single action surface for cleanup. Specialized scanners and safety
/// policies stay separate; this view only unifies discovery and selection.
struct CleanupCenterView: View {
    @Binding var section: CleanupCenterSection
    let safeCleanup: SafeCleanupProjection?
    let applicationCaches: ApplicationCacheProjection?
    let developerStorage: DeveloperStorageProjection?
    let hasSnapshot: Bool
    let searchText: String
    let scanApplicationCaches: () -> Void
    let scanDeveloperTools: () -> Void
    let reviewSafeCleanup: ([ScannedItem]) -> Void
    let reviewApplicationCaches: ([ScannedItem]) -> Void
    let reviewDeveloperStorage: ([ScannedItem]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.applicationCaches(), selection: $section) {
                Text(verbatim: L10n.text(.overviewSafeRecommendations))
                    .tag(CleanupCenterSection.recommended)
                Text(verbatim: L10n.text(.cacheTitle))
                    .tag(CleanupCenterSection.applicationCaches)
                Text(verbatim: L10n.text(.developerToolsTitle))
                    .tag(CleanupCenterSection.developerTools)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            sectionContent
                .frame(minHeight: 0, maxHeight: .infinity)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .navigationTitle(L10n.applicationCaches())
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .recommended:
            RecommendedCleanupView(
                projection: safeCleanup,
                hasSnapshot: hasSnapshot,
                searchText: searchText,
                reviewCleanup: reviewSafeCleanup
            )
        case .applicationCaches:
            ApplicationCacheView(
                projection: applicationCaches,
                hasSnapshot: hasSnapshot,
                searchText: searchText,
                scan: scanApplicationCaches,
                reviewCleanup: reviewApplicationCaches
            )
        case .developerTools:
            DeveloperStorageView(
                projection: developerStorage,
                searchText: searchText,
                scan: scanDeveloperTools,
                reviewCleanup: reviewDeveloperStorage
            )
        }
    }
}

private struct RecommendedCleanupView: View {
    let projection: SafeCleanupProjection?
    let hasSnapshot: Bool
    let searchText: String
    let reviewCleanup: ([ScannedItem]) -> Void

    @State private var selectedItemIDs: Set<UUID> = []

    var body: some View {
        Group {
            if let projection {
                content(projection)
            } else if hasSnapshot {
                ProgressView(L10n.preparingSummary())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    L10n.text(.overviewNoRecommendations),
                    systemImage: "sparkles"
                )
            }
        }
        .onAppear { selectAllSafeItemsIfNeeded() }
        .onChange(of: projectionSignature) { _, _ in
            selectedItemIDs.removeAll()
            selectAllSafeItemsIfNeeded()
        }
    }

    private func content(_ projection: SafeCleanupProjection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: L10n.text(.overviewReviewSafeCleanup))
                        .font(.title2.weight(.semibold))
                    Text(ByteCount.string(projection.totalBytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button(L10n.text(.cacheSelectSafe)) {
                    selectedItemIDs = Set(projection.items.map(\.id))
                }
                Button(L10n.text(.cleanupClearSelection)) {
                    selectedItemIDs.removeAll()
                }
                .disabled(selectedItemIDs.isEmpty)
            }

            if filteredItems.isEmpty {
                ContentUnavailableView(
                    L10n.text(.overviewNoRecommendations),
                    systemImage: "checkmark.circle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredItems) { item in
                    HStack(spacing: 12) {
                        Toggle("", isOn: selectionBinding(for: item.id))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        StorageItemRow(item: item)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
                .frame(minHeight: 0, maxHeight: .infinity)
                .layoutPriority(1)
                .nativeTableHoverHighlight { filteredItems.indices.contains($0) }
            }

            actionBar(projection)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredItems: [ScannedItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projection?.items ?? [] }
        return (projection?.items ?? []).filter {
            $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
                || $0.url.path.localizedCaseInsensitiveContains(query)
                || L10n.explanation($0.explanation)
                    .localizedCaseInsensitiveContains(query)
        }
    }

    private func actionBar(_ projection: SafeCleanupProjection) -> some View {
        let selected = projection.items.filter { selectedItemIDs.contains($0.id) }
        let bytes = selected.reduce(Int64(0)) { $0 + $1.allocatedSize }
        return HStack {
            Text(verbatim: L10n.selectedItems(
                selected.count,
                space: bytes == 0 ? "0 KB" : ByteCount.string(bytes)
            ))
            .font(.headline)
            .monospacedDigit()
            Spacer()
            Button(L10n.text(.cacheReviewSelected), systemImage: "trash") {
                reviewCleanup(selected)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
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

    private func selectAllSafeItemsIfNeeded() {
        guard selectedItemIDs.isEmpty, let projection else { return }
        selectedItemIDs = Set(projection.items.map(\.id))
    }

    private var projectionSignature: String {
        (projection?.items ?? []).map {
            "\($0.id.uuidString):\($0.allocatedSize)"
        }.joined(separator: "|")
    }
}
