import SpacePilotCore
import SwiftUI

struct StorageCapacityHeader: View {
    let projection: StorageProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    diskTitle
                    Spacer()
                    usageSummary
                }

                VStack(alignment: .leading, spacing: 3) {
                    diskTitle
                    usageSummary
                }
            }

            StorageSegmentedCapacityBar(segments: barSegments)
                .frame(height: 18)
                .accessibilityLabel(L10n.text(.storageUsed))
                .accessibilityValue(usageSummaryText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 145), spacing: 12)],
                alignment: .leading,
                spacing: 7
            ) {
                ForEach(legendEntries) { entry in
                    StorageLegendEntryView(entry: entry)
                }
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    metric(
                        L10n.text(.overviewAnalyzedLocally),
                        bytes: projection.analyzedBytes,
                        symbol: "checkmark.circle"
                    )
                    metric(
                        L10n.text(.storageUnattributed),
                        bytes: projection.unattributedBytes,
                        symbol: "questionmark.folder"
                    )
                    metric(
                        L10n.text(.storageAvailable),
                        bytes: projection.availableBytes,
                        symbol: "internaldrive"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    metric(
                        L10n.text(.overviewAnalyzedLocally),
                        bytes: projection.analyzedBytes,
                        symbol: "checkmark.circle"
                    )
                    metric(
                        L10n.text(.storageUnattributed),
                        bytes: projection.unattributedBytes,
                        symbol: "questionmark.folder"
                    )
                    metric(
                        L10n.text(.storageAvailable),
                        bytes: projection.availableBytes,
                        symbol: "internaldrive"
                    )
                }
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var diskTitle: some View {
        HStack(spacing: 7) {
            Image(systemName: "internaldrive.fill")
                .foregroundStyle(.secondary)
            Text(verbatim: L10n.text(.storageInternalDisk))
                .font(.headline)
        }
    }

    private var usageSummaryText: String {
        L10n.usedSpace(
            ByteCount.string(projection.usedBytes),
            total: ByteCount.string(projection.totalCapacity)
        )
    }

    private var usageSummary: some View {
        Text(verbatim: usageSummaryText)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private var barSegments: [StorageCapacitySegment] {
        let analyzedForBar = min(projection.analyzedBytes, projection.usedBytes)
        let scale = projection.analyzedBytes > 0
            ? Double(analyzedForBar) / Double(projection.analyzedBytes)
            : 0
        var result: [StorageCapacitySegment] = projection.capacityCategories.compactMap { summary in
            let bytes = Int64((Double(summary.allocatedSize) * scale).rounded(.down))
            guard bytes > 0 else { return nil }
            return StorageCapacitySegment(
                id: "category.\(summary.category.rawValue)",
                bytes: bytes,
                color: StorageCategoryAppearance.color(for: summary.category)
            )
        }
        if projection.unattributedBytes > 0 {
            result.append(StorageCapacitySegment(
                id: "unattributed",
                bytes: projection.unattributedBytes,
                color: .gray.opacity(0.72)
            ))
        }
        if projection.availableBytes > 0 {
            result.append(StorageCapacitySegment(
                id: "available",
                bytes: projection.availableBytes,
                color: .gray.opacity(0.18)
            ))
        }
        return result
    }

    private var legendEntries: [StorageLegendEntry] {
        let visibleCategoryCount = 5
        var entries = projection.capacityCategories.prefix(visibleCategoryCount).map { summary in
            StorageLegendEntry(
                id: "category.\(summary.category.rawValue)",
                title: L10n.name(for: summary.category),
                bytes: summary.allocatedSize,
                color: StorageCategoryAppearance.color(for: summary.category)
            )
        }
        let otherBytes = projection.capacityCategories.dropFirst(visibleCategoryCount)
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        if otherBytes > 0 {
            entries.append(StorageLegendEntry(
                id: "other-analyzed",
                title: L10n.text(.storageOtherAnalyzed),
                bytes: otherBytes,
                color: .blue.opacity(0.55)
            ))
        }
        if projection.unattributedBytes > 0 {
            entries.append(StorageLegendEntry(
                id: "unattributed",
                title: L10n.text(.storageUnattributed),
                bytes: projection.unattributedBytes,
                color: .gray.opacity(0.72)
            ))
        }
        if projection.availableBytes > 0 {
            entries.append(StorageLegendEntry(
                id: "available",
                title: L10n.text(.storageAvailable),
                bytes: projection.availableBytes,
                color: .gray.opacity(0.24)
            ))
        }
        return entries
    }

    private func metric(_ title: String, bytes: Int64, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(ByteCount.string(bytes))
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum StorageCategoryAppearance {
    static func color(for category: ItemCategory) -> Color {
        switch category {
        case .application: .red
        case .personal: .orange
        case .developer: .green
        case .aiData: .purple
        case .cache: .yellow
        case .log: .brown
        case .conversation: .mint
        case .model: .indigo
        case .plugin: .cyan
        case .skill: .teal
        case .system: .gray
        case .unclassified: .blue.opacity(0.55)
        }
    }

    static func symbol(for category: ItemCategory) -> String {
        switch category {
        case .application: "app.fill"
        case .personal: "doc.fill"
        case .developer: "hammer.fill"
        case .aiData: "brain.head.profile.fill"
        case .cache: "shippingbox.fill"
        case .log: "text.alignleft"
        case .conversation: "bubble.left.and.bubble.right.fill"
        case .model: "cube.fill"
        case .plugin: "puzzlepiece.extension.fill"
        case .skill: "wand.and.stars"
        case .system: "gearshape.fill"
        case .unclassified: "questionmark.folder.fill"
        }
    }
}

private struct StorageSegmentedCapacityBar: View {
    let segments: [StorageCapacitySegment]

    var body: some View {
        GeometryReader { geometry in
            let spacing = 2.0
            let total = max(segments.reduce(0.0) { $0 + Double($1.bytes) }, 1)
            let usableWidth = max(
                0,
                geometry.size.width - spacing * Double(max(segments.count - 1, 0))
            )
            HStack(spacing: spacing) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: usableWidth * Double(segment.bytes) / total)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            }
        }
    }
}

private struct StorageLegendEntryView: View {
    let entry: StorageLegendEntry

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(entry.color)
                .frame(width: 8, height: 8)
            Text(entry.title)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(ByteCount.string(entry.bytes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

private struct StorageCapacitySegment: Identifiable {
    let id: String
    let bytes: Int64
    let color: Color
}

private struct StorageLegendEntry: Identifiable {
    let id: String
    let title: String
    let bytes: Int64
    let color: Color
}
