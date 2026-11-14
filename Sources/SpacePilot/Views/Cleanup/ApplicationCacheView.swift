import SpacePilotCore
import SwiftUI

struct ApplicationCacheView: View {
    let projection: ApplicationCacheProjection?
    let hasSnapshot: Bool
    let searchText: String
    let scan: () -> Void
    let reviewCleanup: ([ScannedItem]) -> Void

    @State private var filter: CacheSafetyFilter = .all
    @State private var sortOrder: CacheSortOrder = .largest
    @State private var selectedItemIDs: Set<UUID> = []

    var body: some View {
        Group {
            if let projection {
                content(projection)
            } else if hasSnapshot {
                ContentUnavailableView(
                    L10n.text(.cacheEmptyTitle),
                    systemImage: "internaldrive",
                    description: Text(verbatim: L10n.text(.cacheEmptyDescription))
                )
            } else {
                ContentUnavailableView {
                    Label(L10n.text(.cacheTitle), systemImage: "internaldrive")
                } description: {
                    Text(verbatim: L10n.noData())
                } actions: {
                    Button(L10n.text(.cacheScan), action: scan)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear { selectSafeItemsIfNeeded() }
        .onChange(of: projectionSignature) { _, _ in
            selectedItemIDs = []
            selectSafeItemsIfNeeded()
        }
    }

    private func content(_ projection: ApplicationCacheProjection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(projection)
            controls(projection)

            if rows.isEmpty {
                ContentUnavailableView(
                    L10n.text(.cacheNoMatching),
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(verbatim: L10n.text(.cacheNoMatchingDescription))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { row in
                    cacheRow(row)
                }
                .listStyle(.inset)
                .nativeTableHoverHighlight { rows.indices.contains($0) }
            }

            actionBar(projection)
        }
        .padding(20)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ projection: ApplicationCacheProjection) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                headerText(projection)
                Spacer()
                coverageLabel(projection)
                Button(L10n.text(.cacheScan), systemImage: "arrow.clockwise", action: scan)
            }
            VStack(alignment: .leading, spacing: 8) {
                headerText(projection)
                HStack {
                    coverageLabel(projection)
                    Spacer()
                    Button(L10n.text(.cacheScan), systemImage: "arrow.clockwise", action: scan)
                }
            }
        }
    }

    private func headerText(_ projection: ApplicationCacheProjection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: L10n.text(.cacheTitle))
                .font(.title2.weight(.semibold))
            Text(verbatim: L10n.cacheSummary(
                projection.groups.count,
                space: ByteCount.string(projection.totalBytes)
            ))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func coverageLabel(_ projection: ApplicationCacheProjection) -> some View {
        if !projection.coverage.isComplete {
            Label(L10n.text(.cacheLimitedCoverage), systemImage: "lock.trianglebadge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func controls(_ projection: ApplicationCacheProjection) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                safetyPicker(projection)
                selectionButtons(projection)
                Spacer()
                sortPicker
            }
            VStack(alignment: .leading, spacing: 10) {
                safetyPicker(projection)
                HStack {
                    selectionButtons(projection)
                    Spacer()
                    sortPicker
                }
            }
        }
    }

    private func safetyPicker(_ projection: ApplicationCacheProjection) -> some View {
        Picker(L10n.text(.cacheSafetyFilter), selection: $filter) {
            Text(verbatim: L10n.cacheFilterAll(projection.safeItemCount + projection.checkFirstItemCount))
                .tag(CacheSafetyFilter.all)
            Text(verbatim: L10n.cacheFilterSafe(projection.safeItemCount))
                .tag(CacheSafetyFilter.safe)
            Text(verbatim: L10n.cacheFilterCheck(projection.checkFirstItemCount))
                .tag(CacheSafetyFilter.checkFirst)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityLabel(L10n.text(.cacheSafetyFilter))
    }

    private func selectionButtons(_ projection: ApplicationCacheProjection) -> some View {
        HStack(spacing: 8) {
            Button(L10n.text(.cacheSelectSafe)) {
                selectedItemIDs = Set(projection.groups
                    .flatMap(\.items)
                    .filter { $0.risk == .safe }
                    .map(\.id))
            }
            Button(L10n.text(.cleanupClearSelection)) {
                selectedItemIDs.removeAll()
            }
            .disabled(selectedItemIDs.isEmpty)
        }
    }

    private var sortPicker: some View {
        Picker(L10n.text(.cacheSort), selection: $sortOrder) {
            Text(verbatim: L10n.text(.cacheSortLargest)).tag(CacheSortOrder.largest)
            Text(verbatim: L10n.text(.cacheSortName)).tag(CacheSortOrder.name)
        }
        .labelsHidden()
        .frame(width: 130)
        .accessibilityLabel(L10n.text(.cacheSort))
    }

    private func cacheRow(_ row: CacheRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: selectionBinding(for: row.items))
                .labelsHidden()
                .toggleStyle(.checkbox)

            FileSystemItemIcon(
                url: row.group.applicationURL ?? row.items[0].url,
                size: 30
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(row.group.name)
                    .fontWeight(.semibold)
                Text(verbatim: L10n.cacheRowDescription(row.items.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteCount.string(row.allocatedSize))
                    .monospacedDigit()
                    .fontWeight(.medium)
                Text(verbatim: L10n.name(for: row.risk))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(row.risk == .safe ? .green : .orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        (row.risk == .safe ? Color.green : Color.orange)
                            .opacity(0.10),
                        in: Capsule()
                    )
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onDoubleClickRevealInFinder(row.items[0].url)
        .contextMenu {
            Button(L10n.text(.revealFinder)) {
                FinderReveal.reveal(row.items[0].url)
            }
        }
        .accessibilityLabel(
            "\(row.group.name), \(ByteCount.string(row.allocatedSize)), \(L10n.name(for: row.risk))"
        )
    }

    private func actionBar(_ projection: ApplicationCacheProjection) -> some View {
        let selected = selectedItems(in: projection)
        let selectedBytes = selected.reduce(Int64(0)) { $0 + $1.allocatedSize }
        return HStack {
            Text(verbatim: L10n.selectedItems(
                selected.count,
                space: selectedBytes == 0 ? "0 KB" : ByteCount.string(selectedBytes)
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

    private var rows: [CacheRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let built = (projection?.groups ?? []).compactMap { group -> CacheRow? in
            let filteredItems = group.items.filter { item in
                switch filter {
                case .all: true
                case .safe: item.risk == .safe
                case .checkFirst: item.risk == .rebuildable
                }
            }
            guard !filteredItems.isEmpty else { return nil }
            guard query.isEmpty
                || group.name.localizedCaseInsensitiveContains(query)
                || group.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true
                || filteredItems.contains(where: {
                    $0.url.path.localizedCaseInsensitiveContains(query)
                }) else {
                return nil
            }
            return CacheRow(group: group, items: filteredItems)
        }
        return built.sorted { lhs, rhs in
            switch sortOrder {
            case .largest:
                if lhs.allocatedSize != rhs.allocatedSize {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
            case .name:
                let comparison = lhs.group.name.localizedStandardCompare(rhs.group.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return lhs.id < rhs.id
        }
    }

    private var projectionSignature: String {
        (projection?.groups.flatMap(\.items).map(\.id.uuidString).sorted() ?? [])
            .joined(separator: ":")
    }

    private func selectSafeItemsIfNeeded() {
        guard selectedItemIDs.isEmpty, let projection else { return }
        selectedItemIDs = Set(projection.groups
            .flatMap(\.items)
            .filter { $0.risk == .safe }
            .map(\.id))
    }

    private func selectedItems(in projection: ApplicationCacheProjection) -> [ScannedItem] {
        projection.groups
            .flatMap(\.items)
            .filter { selectedItemIDs.contains($0.id) }
    }

    private func selectionBinding(for items: [ScannedItem]) -> Binding<Bool> {
        let ids = Set(items.map(\.id))
        return Binding(
            get: { !ids.isEmpty && ids.isSubset(of: selectedItemIDs) },
            set: { selected in
                if selected {
                    selectedItemIDs.formUnion(ids)
                } else {
                    selectedItemIDs.subtract(ids)
                }
            }
        )
    }
}

private struct CacheRow: Identifiable {
    let group: ApplicationCacheGroup
    let items: [ScannedItem]

    var id: String { group.id }
    var allocatedSize: Int64 { items.reduce(Int64(0)) { $0 + $1.allocatedSize } }
    var risk: RiskLevel { items.map(\.risk).max() ?? .safe }
}

private enum CacheSafetyFilter: String, CaseIterable {
    case all
    case safe
    case checkFirst
}

private enum CacheSortOrder: String, CaseIterable {
    case largest
    case name
}
