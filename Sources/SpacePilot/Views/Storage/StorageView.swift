import SpacePilotCore
import SwiftUI

struct StorageView: View {
    private static let categoryColumnWidth: CGFloat = 260
    private static let workspaceActionSlotWidth: CGFloat = 150

    let projection: StorageProjection?
    let changeHistory: StorageChangeHistory
    let hasSnapshot: Bool
    let searchText: String
    @Binding var mode: StorageItemMode
    let reviewCleanup: ([ScannedItem]) -> Void
    @State private var categorySelection: StorageCategorySelection = .all
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var selectedChangeIDs: Set<UUID> = []
    @State private var changeTimeRange: StorageChangeTimeRange = .week
    @State private var changeKindFilter: StorageChangeKindFilter = .all
    @State private var changeSafetyFilter: StorageChangeSafetyFilter = .all
    @State private var itemSortOrder = [
        KeyPathComparator(\ScannedItem.allocatedSize, order: .reverse)
    ]
    @State private var changeSortOrder = [
        KeyPathComparator(\StorageChangeEntry.magnitudeBytes, order: .reverse)
    ]

    var body: some View {
        if let projection {
            VStack(spacing: 0) {
                StorageCapacityHeader(projection: projection)

                Divider()

                HSplitView {
                    categoryBrowser(projection)
                        .frame(width: Self.categoryColumnWidth)

                    itemsWorkspace(projection)
                        .frame(minWidth: 0)
                }
            }
            .onChange(of: categorySelection) {
                selectedItemIDs.removeAll()
            }
            .onChange(of: mode) {
                selectedItemIDs.removeAll()
                selectedChangeIDs.removeAll()
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
            Section(L10n.text(.storageAnalyzedCategories)) {
                StorageCategoryRow(
                    title: L10n.text(.storageAllAnalyzed),
                    itemCount: projection.categories.reduce(0) { $0 + $1.itemCount },
                    allocatedSize: projection.analyzedBytes,
                    symbol: "chart.pie.fill",
                    color: .accentColor
                )
                .tag(StorageCategorySelection.all)

                ForEach(projection.categories) { summary in
                    StorageCategoryRow(
                        title: L10n.name(for: summary.category),
                        itemCount: summary.itemCount,
                        allocatedSize: summary.allocatedSize,
                        symbol: StorageCategoryAppearance.symbol(for: summary.category),
                        color: StorageCategoryAppearance.color(for: summary.category)
                    )
                    .tag(StorageCategorySelection.category(summary.category))
                }
            }

            if projection.unattributedBytes > 0 {
                Section {
                    StorageUnattributedRow(bytes: projection.unattributedBytes)
                }
            }
        }
        .listStyle(.inset)
    }

    private func itemsWorkspace(_ projection: StorageProjection) -> some View {
        let visibleItems = filteredItems(in: projection).sorted(using: itemSortOrder)
        let safeSelectedItems = visibleItems.filter {
            selectedItemIDs.contains($0.id) && $0.risk == .safe
        }
        let changes = StorageChangeProjection(
            history: changeHistory,
            timeRange: changeTimeRange,
            kindFilter: changeKindFilter,
            category: selectedCategory,
            searchText: searchText,
            safeOnly: changeSafetyFilter == .safe
        )
        let visibleChanges = changes.entries.sorted(using: changeSortOrder)
        let visibleItemCount =
            mode == .recent
            ? visibleChanges.count
            : visibleItems.count

        return VStack(spacing: 0) {
            workspaceNavigationToolbar(visibleItemCount: visibleItemCount) {
                HStack {
                    Spacer(minLength: 0)
                    reviewButton(items: safeSelectedItems)
                }
                .opacity(mode == .recent ? 0 : 1)
                .allowsHitTesting(mode != .recent)
                .accessibilityHidden(mode == .recent)
            }
            .padding(12)

            if mode == .recent {
                recentChangesFilters
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            Divider()

            if mode == .recent {
                recentChangesContent(changes, visibleChanges: visibleChanges)
            } else {
                scannedItemsContent(visibleItems)
            }
        }
    }

    @ViewBuilder
    private func scannedItemsContent(_ visibleItems: [ScannedItem]) -> some View {
        if visibleItems.isEmpty {
            ContentUnavailableView(
                L10n.text(.storageNoMatching),
                systemImage: "internaldrive",
                description: Text(verbatim: L10n.text(.storageNoMatchingDescription))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(
                of: ScannedItem.self,
                selection: $selectedItemIDs,
                sortOrder: $itemSortOrder
            ) {
                TableColumn(
                    mode == .largest
                        ? L10n.text(.storageLargestItems)
                        : L10n.text(.storageOldItems),
                    value: \.storageDisplayName
                ) { item in
                    HStack(spacing: 8) {
                        FileSystemItemIcon(url: item.url)
                        Text(item.storageDisplayName)
                            .lineLimit(1)
                    }
                    .contextMenu {
                        Button(L10n.text(.revealFinder)) {
                            FinderReveal.reveal(item.url)
                        }
                        if item.risk == .safe {
                            Button(L10n.text(.cleanupReview)) {
                                reviewCleanup([item])
                            }
                        }
                    }
                }
                .width(min: 120, ideal: 180)
                TableColumn(L10n.location(), value: \.storageParentPath) { item in
                    Text(item.storageParentPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 190)
                TableColumn(L10n.risk(), value: \.risk) { item in
                    Text(verbatim: L10n.name(for: item.risk))
                }
                .width(min: 90, ideal: 105)
                TableColumn(L10n.space(), value: \.allocatedSize) { item in
                    Text(ByteCount.string(item.allocatedSize))
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 95)
            } rows: {
                ForEach(visibleItems)
            }
            .nativeTableDoubleClickReveal { row in
                visibleItems.indices.contains(row) ? visibleItems[row].url : nil
            }
        }

        if selectedItemIDs.count == 1,
            let selectedID = selectedItemIDs.first,
            let selectedItem = visibleItems.first(where: { $0.id == selectedID })
        {
            Divider()
            StorageItemDetail(
                item: selectedItem,
                reviewCleanup: reviewCleanup
            )
        }
    }

    @ViewBuilder
    private func recentChangesContent(
        _ changes: StorageChangeProjection,
        visibleChanges: [StorageChangeEntry]
    ) -> some View {
        StorageChangeSummary(projection: changes)
            .padding(12)

        Divider()

        if visibleChanges.isEmpty {
            ContentUnavailableView(
                changeHistory.baselineEstablishedAt == nil
                    ? L10n.text(.storageChangesWaitingBaseline)
                    : L10n.text(.storageChangesEmpty),
                systemImage: "clock.arrow.circlepath",
                description: Text(verbatim: L10n.text(.storageChangesEmptyDescription))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(
                of: StorageChangeEntry.self,
                selection: $selectedChangeIDs,
                sortOrder: $changeSortOrder
            ) {
                TableColumn(
                    L10n.text(.storageChangesItem),
                    value: \.storageDisplayName
                ) { entry in
                    HStack(spacing: 8) {
                        FileSystemItemIcon(url: entry.url)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.storageDisplayName)
                                .lineLimit(1)
                            if entry.ownerName != nil || entry.isAggregated {
                                Text(entry.url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if entry.isSafeToClean {
                                Label(
                                    L10n.name(for: RiskLevel.safe),
                                    systemImage: "shield.checkered"
                                )
                                .font(.caption)
                                .foregroundStyle(.green)
                                .lineLimit(1)
                            }
                        }
                    }
                    .contextMenu {
                        if entry.kind != .deleted {
                            Button(L10n.text(.revealFinder)) {
                                FinderReveal.reveal(entry.url)
                            }
                        }
                    }
                }
                .width(min: 150, ideal: 220)
                TableColumn(
                    L10n.location(),
                    value: \.storageParentPath
                ) { entry in
                    Text(entry.storageParentPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 190)
                TableColumn(
                    L10n.text(.storageChangesType),
                    value: \.storageKindSortValue
                ) { entry in
                    Label(
                        changeKindName(entry.kind),
                        systemImage: changeKindIcon(entry.kind)
                    )
                    .foregroundStyle(changeKindColor(entry.kind))
                }
                .width(min: 80, ideal: 95)
                TableColumn(
                    L10n.text(.storageChangesTime),
                    value: \.observedAt
                ) { entry in
                    Text(entry.observedAt, style: .relative)
                        .foregroundStyle(.secondary)
                }
                .width(min: 85, ideal: 105)
                TableColumn(
                    L10n.text(.storageChangesSize),
                    value: \.magnitudeBytes
                ) { entry in
                    Text(changeSize(entry))
                        .fontWeight(entry.isHighlighted ? .bold : .regular)
                        .foregroundStyle(entry.isHighlighted ? .orange : .primary)
                        .monospacedDigit()
                }
                .width(min: 90, ideal: 105)
            } rows: {
                ForEach(visibleChanges)
            }
            .nativeTableDoubleClickReveal { row in
                guard visibleChanges.indices.contains(row),
                    visibleChanges[row].kind != .deleted
                else { return nil }
                return visibleChanges[row].url
            }
        }

        if changes.hasCoverageGap {
            Label(
                L10n.text(.storageChangesCoverageGap),
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func workspaceNavigationToolbar<Trailing: View>(
        visibleItemCount: Int,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                workspaceTitle(visibleItemCount: visibleItemCount)
                Spacer()
                modePicker
                trailing()
                    .frame(
                        width: Self.workspaceActionSlotWidth,
                        alignment: .trailing
                    )
            }
            .frame(minWidth: 540)

            VStack(alignment: .leading, spacing: 8) {
                workspaceTitle(visibleItemCount: visibleItemCount)
                HStack(spacing: 10) {
                    modePicker
                        .frame(maxWidth: 200)
                    Spacer(minLength: 8)
                    trailing()
                        .frame(
                            width: Self.workspaceActionSlotWidth,
                            alignment: .trailing
                        )
                }
            }
        }
    }

    private var recentChangesFilters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 10) {
                Spacer(minLength: 0)
                changeFilter(L10n.text(.storageChangesRange)) {
                    changeTimePicker
                }
                changeFilter(L10n.text(.storageChangesType)) {
                    changeKindPicker
                }
                changeFilter(L10n.text(.storageChangesSafety)) {
                    changeSafetyPicker
                }
            }
            .frame(minWidth: 410)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .bottom, spacing: 10) {
                    changeFilter(L10n.text(.storageChangesRange)) {
                        changeTimePicker
                    }
                    changeFilter(L10n.text(.storageChangesType)) {
                        changeKindPicker
                    }
                }
                changeFilter(L10n.text(.storageChangesSafety)) {
                    changeSafetyPicker
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func changeFilter<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func workspaceTitle(visibleItemCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(categoryTitle)
                .font(.headline)
                .lineLimit(1)
            Text(verbatim: L10n.visibleItems(visibleItemCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modePicker: some View {
        Picker(L10n.text(.items), selection: $mode) {
            ForEach(StorageItemMode.allCases) { mode in
                Text(verbatim: modeName(mode))
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(minWidth: 200, idealWidth: 260, maxWidth: 300)
        .accessibilityIdentifier("storage-mode-picker")
    }

    private func modeName(_ mode: StorageItemMode) -> String {
        switch mode {
        case .largest: L10n.text(.storageLargest)
        case .old: L10n.text(.storageOlder180)
        case .recent: L10n.text(.storageChangesRecent)
        }
    }

    private var changeTimePicker: some View {
        Picker(L10n.text(.storageChangesRange), selection: $changeTimeRange) {
            Text(verbatim: L10n.text(.storageChanges24Hours)).tag(StorageChangeTimeRange.day)
            Text(verbatim: L10n.text(.storageChanges7Days)).tag(StorageChangeTimeRange.week)
            Text(verbatim: L10n.text(.storageChanges30Days)).tag(StorageChangeTimeRange.month)
        }
        .labelsHidden()
        .frame(width: 105)
        .accessibilityLabel(L10n.text(.storageChangesRange))
        .accessibilityIdentifier("storage-change-time-range")
    }

    private var changeKindPicker: some View {
        Picker(L10n.text(.storageChangesType), selection: $changeKindFilter) {
            Text(verbatim: L10n.text(.storageChangesAll)).tag(StorageChangeKindFilter.all)
            Text(verbatim: L10n.text(.storageChangesAdded)).tag(StorageChangeKindFilter.added)
            Text(verbatim: L10n.text(.storageChangesGrown)).tag(StorageChangeKindFilter.grown)
            Text(verbatim: L10n.text(.storageChangesDeleted)).tag(StorageChangeKindFilter.deleted)
        }
        .labelsHidden()
        .frame(width: 90)
        .accessibilityLabel(L10n.text(.storageChangesType))
        .accessibilityIdentifier("storage-change-kind")
    }

    private var changeSafetyPicker: some View {
        Picker(L10n.risk(), selection: $changeSafetyFilter) {
            Text(verbatim: L10n.text(.storageChangesAll))
                .tag(StorageChangeSafetyFilter.all)
            Text(verbatim: L10n.text(.storageChangesSafeOnly))
                .tag(StorageChangeSafetyFilter.safe)
        }
        .labelsHidden()
        .frame(width: 105)
        .accessibilityLabel(L10n.text(.storageChangesSafety))
        .accessibilityIdentifier("storage-change-safety")
    }

    private func changeKindName(_ kind: StorageChangeKind) -> String {
        switch kind {
        case .added: L10n.text(.storageChangesAdded)
        case .grown: L10n.text(.storageChangesGrown)
        case .deleted: L10n.text(.storageChangesDeleted)
        }
    }

    private func changeKindIcon(_ kind: StorageChangeKind) -> String {
        switch kind {
        case .added: "plus.circle.fill"
        case .grown: "arrow.up.circle.fill"
        case .deleted: "minus.circle.fill"
        }
    }

    private func changeKindColor(_ kind: StorageChangeKind) -> Color {
        switch kind {
        case .added, .grown: .blue
        case .deleted: .green
        }
    }

    private func changeSize(_ entry: StorageChangeEntry) -> String {
        let prefix = entry.kind == .deleted ? "−" : "+"
        return prefix + ByteCount.string(entry.magnitudeBytes)
    }

    private func reviewButton(items: [ScannedItem]) -> some View {
        Button(L10n.text(.storageReviewSafeCleanup)) {
            reviewCleanup(items)
        }
        .buttonStyle(.borderedProminent)
        .disabled(items.isEmpty)
        .fixedSize()
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

extension ScannedItem {
    fileprivate var storageDisplayName: String { url.lastPathComponent }

    fileprivate var storageParentPath: String {
        url.deletingLastPathComponent().path(percentEncoded: false)
    }
}

extension StorageChangeEntry {
    fileprivate var storageDisplayName: String { ownerName ?? url.lastPathComponent }

    fileprivate var storageParentPath: String {
        url.deletingLastPathComponent().path(percentEncoded: false)
    }

    fileprivate var storageKindSortValue: String { kind.rawValue }
}

private struct StorageCategoryRow: View {
    let title: String
    let itemCount: Int
    let allocatedSize: Int64
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(verbatim: L10n.itemCount(itemCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(ByteCount.string(allocatedSize))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}

private struct StorageUnattributedRow: View {
    let bytes: Int64

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "questionmark.folder")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(verbatim: L10n.text(.storageUnattributed))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(ByteCount.string(bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(verbatim: L10n.text(.storageUnattributedDescription))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                Text(
                    verbatim: "\(L10n.name(for: item.risk)) · \(L10n.explanation(item.explanation))"
                )
                .font(.caption)
                .foregroundStyle(item.risk == .sensitive ? .orange : .secondary)
                if let modificationDate = item.modificationDate {
                    Text(modificationDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDoubleClickRevealInFinder(item.url)

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(ByteCount.string(item.allocatedSize))
                    .font(.headline)
                    .monospacedDigit()
                Button(L10n.text(.revealFinder)) {
                    FinderReveal.reveal(item.url)
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

enum StorageItemMode: String, CaseIterable, Identifiable {
    case largest
    case old
    case recent

    var id: Self { self }
}

private enum StorageChangeSafetyFilter: String, CaseIterable, Identifiable {
    case all
    case safe

    var id: Self { self }
}

private struct StorageChangeSummary: View {
    let projection: StorageChangeProjection

    var body: some View {
        HStack(spacing: 20) {
            metric(L10n.text(.storageChangesAdded), projection.addedBytes)
            metric(L10n.text(.storageChangesGrown), projection.grownBytes)
            metric(L10n.text(.storageChangesReleased), projection.releasedBytes)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: L10n.text(.storageChangesDiskDelta))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(diskDelta)
                    .font(.headline)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diskDelta: String {
        guard let delta = projection.availableCapacityDelta else { return "—" }
        let prefix = delta > 0 ? "+" : (delta < 0 ? "−" : "")
        return prefix + ByteCount.string(abs(delta))
    }

    private func metric(_ title: String, _ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ByteCount.string(bytes))
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
