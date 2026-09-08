import SpacePilotCore
import SwiftUI

struct AnalyzedCategoryChart: View {
    let categories: [StorageCategorySummary]
    private static let maxVisibleCategories = 5

    static func sizeLabel(for bytes: Int64) -> String {
        ByteCount.string(max(0, bytes))
    }

    private var visibleCategories: [StorageCategorySummary] {
        Array(categories.prefix(Self.maxVisibleCategories))
    }

    private var remainingBytes: Int64 {
        categories.dropFirst(Self.maxVisibleCategories)
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
    }

    private var largestVisibleSize: Int64 {
        max(visibleCategories.map(\.allocatedSize).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: L10n.text(.overviewAnalyzedCategoriesChart))
                .font(.headline)
                .accessibilityHidden(true)

            if categories.isEmpty {
                Label(
                    L10n.text(.overviewAnalyzedCategoriesEmpty),
                    systemImage: "chart.bar.xaxis"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(visibleCategories) { summary in
                        categoryRow(
                            title: L10n.name(for: summary.category),
                            bytes: summary.allocatedSize,
                            color: StorageCategoryAppearance.color(for: summary.category),
                            symbol: StorageCategoryAppearance.symbol(for: summary.category)
                        )
                    }

                    if remainingBytes > 0 {
                        categoryRow(
                            title: L10n.text(.storageOtherAnalyzed),
                            bytes: remainingBytes,
                            color: .secondary.opacity(0.55),
                            symbol: "ellipsis"
                        )
                    }
                }
                .accessibilityHidden(true)
                .accessibilityRepresentation {
                    categoryValues
                }
            }
        }
    }

    private func categoryRow(
        title: String,
        bytes: Int64,
        color: Color,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 19)
                Text(verbatim: title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: Self.sizeLabel(for: bytes))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quinary)
                    Capsule()
                        .fill(color)
                        .frame(
                            width: geometry.size.width
                                * min(max(Double(bytes) / Double(largestVisibleSize), 0), 1)
                        )
                }
            }
            .frame(height: 7)
            .animation(.snappy(duration: 0.25), value: bytes)
        }
    }

    private var categoryValues: some View {
        VStack(alignment: .leading) {
            Text(verbatim: L10n.text(.overviewAnalyzedCategoriesDescription))
            ForEach(categories) { summary in
                LabeledContent(
                    L10n.name(for: summary.category),
                    value: ByteCount.string(summary.allocatedSize)
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(.overviewAnalyzedCategoriesChart))
    }
}
