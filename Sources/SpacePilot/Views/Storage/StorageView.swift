import AppKit
import SpacePilotCore
import SwiftUI

struct StorageView: View {
    let projection: StorageProjection?
    let hasSnapshot: Bool
    let searchText: String
    let reviewCleanup: ([ScannedItem]) -> Void
    @State private var mode: StorageItemMode = .largest
    @State private var categorySelection: StorageCategorySelection = .all
    @State private var selectedItemIDs: Set<UUID> = []

    var body: some View {
        if let projection {
            VStack(spacing: 0) {
                StorageCapacityHeader(projection: projection)

                Divider()

                HSplitView {
                    categoryBrowser(projection)
                        .frame(minWidth: 230, idealWidth: 270, maxWidth: 330)

                    itemsWorkspace(projection)
                        .frame(minWidth: 620)
                }
            }
            .onChange(of: categorySelection) {
                selectedItemIDs.removeAll()
            }
            .onChange(of: mode) {
                selectedItemIDs.removeAll()
            }
            .onChange(of: searchText) {
                let visibleIDs = Set(filteredItems(in: projection).map(\.id))
                selectedItemIDs.formIntersection(visibleIDs)
            }
            .navigationTitle(L10n.storage())
        } else if hasSnapshot {
            ProgressView(L10n.preparingSummary())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(L10n.storage())
        } else {
            empty(L10n.storage(), image: "internaldrive")
        }
    }

    private func categoryBrowser(_ projection: StorageProjection) -> some View {
        List(selection: $categorySelection) {
            StorageCategoryRow(
                title: L10n.text(.storageAllAnalyzed),
                itemCount: projection.categories.reduce(0) { $0 + $1.itemCount },
                allocatedSize: projection.analyzedBytes,
                comparisonSize: projection.usedBytes
            )
            .tag(StorageCategorySelection.all)

            ForEach(projection.categories) { summary in
                StorageCategoryRow(
                    title: L10n.name(for: summary.category),
                    itemCount: summary.itemCount,
                    allocatedSize: summary.allocatedSize,
                    comparisonSize: projection.usedBytes
                )
                .tag(StorageCategorySelection.category(summary.category))
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack {
                Text(verbatim: L10n.text(.storageCategories))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func itemsWorkspace(_ projection: StorageProjection) -> some View {
        let visibleItems = filteredItems(in: projection)
        let safeSelectedItems = visibleItems.filter {
            selectedItemIDs.contains($0.id) && $0.risk == .safe
        }

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(categoryTitle)
                        .font(.headline)
                    Text(verbatim: L10n.visibleItems(visibleItems.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker(L10n.text(.items), selection: $mode) {
                    ForEach(StorageItemMode.allCases) { mode in
                        Text(verbatim: mode == .largest
                            ? L10n.text(.storageLargest)
                            : L10n.text(.storageOlder180)
                        )
                        .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)

                Button(L10n.text(.storageReviewSafeCleanup)) {
                    reviewCleanup(safeSelectedItems)
                }
                .buttonStyle(.borderedProminent)
                .disabled(safeSelectedItems.isEmpty)
            }
            .padding(12)

            Divider()

            if visibleItems.isEmpty {
                ContentUnavailableView(
                    L10n.text(.storageNoMatching),
                    systemImage: "internaldrive",
                    description: Text(verbatim: L10n.text(.storageNoMatchingDescription))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(of: ScannedItem.self, selection: $selectedItemIDs) {
                    TableColumn(mode == .largest
                        ? L10n.text(.storageLargestItems)
                        : L10n.text(.storageOldItems)
                    ) { item in
                        Text(item.url.lastPathComponent)
                            .lineLimit(1)
                            .contextMenu {
                                Button(L10n.text(.revealFinder)) {
                                    reveal(item.url)
                                }
                                if item.risk == .safe {
                                    Button(L10n.text(.cleanupReview)) {
                                        reviewCleanup([item])
                                    }
                                }
                            }
                    }
                    TableColumn(L10n.location()) { item in
                        Text(item.url.deletingLastPathComponent().path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    TableColumn(L10n.risk()) { item in
                        Text(verbatim: L10n.name(for: item.risk))
                    }
                    .width(120)
                    TableColumn(L10n.space()) { item in
                        Text(ByteCount.string(item.allocatedSize))
                            .monospacedDigit()
                    }
                    .width(100)
                } rows: {
                    ForEach(visibleItems)
                }
            }

            if selectedItemIDs.count == 1,
               let selectedID = selectedItemIDs.first,
               let selectedItem = visibleItems.first(where: { $0.id == selectedID }) {
                Divider()
                StorageItemDetail(
                    item: selectedItem,
                    reviewCleanup: reviewCleanup
                )
            }
        }
    }

    private var selectedCategory: ItemCategory? {
        categorySelection.category
    }

    private var categoryTitle: String {
        selectedCategory.map { L10n.name(for: $0) }
            ?? L10n.text(.storageAllAnalyzed)
    }

    private func filteredItems(in projection: StorageProjection) -> [ScannedItem] {
        let items = projection.items(
            category: selectedCategory,
            oldOnly: mode == .old
        )
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.url.path.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct StorageCapacityHeader: View {
    let projection: StorageProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: L10n.text(.storageInternalDisk))
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(verbatim: L10n.usedSpace(
                    ByteCount.string(projection.usedBytes),
                    total: ByteCount.string(projection.totalCapacity)
                ))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            ProgressView(
                value: Double(projection.usedBytes),
                total: Double(max(projection.totalCapacity, 1))
            )

            HStack(spacing: 28) {
                metric(L10n.text(.storageTotalCapacity), bytes: projection.totalCapacity)
                metric(L10n.text(.storageUsed), bytes: projection.usedBytes)
                metric(L10n.text(.storageAvailable), bytes: projection.availableBytes)
                metric(L10n.text(.overviewAnalyzedLocally), bytes: projection.analyzedBytes)
            }
        }
        .padding(16)
    }

    private func metric(_ title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteCount.string(bytes))
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StorageCategoryRow: View {
    let title: String
    let itemCount: Int
    let allocatedSize: Int64
    let comparisonSize: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .lineLimit(1)
                Spacer()
                Text(ByteCount.string(allocatedSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(
                value: Double(allocatedSize),
                total: Double(max(comparisonSize, 1))
            )
            Text(verbatim: L10n.itemCount(itemCount))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct StorageItemDetail: View {
    let item: ScannedItem
    let reviewCleanup: ([ScannedItem]) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.url.lastPathComponent)
                    .font(.headline)
                Text(item.url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Text(verbatim: "\(L10n.name(for: item.risk)) · \(L10n.explanation(item.explanation))")
                    .font(.caption)
                    .foregroundStyle(item.risk == .sensitive ? .orange : .secondary)
                if let modificationDate = item.modificationDate {
                    Text(modificationDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(ByteCount.string(item.allocatedSize))
                    .font(.headline)
                    .monospacedDigit()
                Button(L10n.text(.revealFinder)) {
                    reveal(item.url)
                }
                if item.risk == .safe {
                    Button(L10n.text(.cleanupReview)) {
                        reviewCleanup([item])
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .frame(minHeight: 112)
    }
}

private enum StorageCategorySelection: Hashable {
    case all
    case category(ItemCategory)

    var category: ItemCategory? {
        guard case .category(let category) = self else { return nil }
        return category
    }
}

private enum StorageItemMode: String, CaseIterable, Identifiable {
    case largest
    case old

    var id: Self { self }
}

func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

@ViewBuilder
func empty(_ title: String, image: String) -> some View {
    ContentUnavailableView(
        title,
        systemImage: image,
        description: Text(verbatim: L10n.noData())
    )
    .navigationTitle(title)
}
