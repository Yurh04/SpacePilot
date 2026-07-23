import Charts
import SpacePilotCore
import SwiftUI

struct AnalyzedCategoryChart: View {
    let categories: [StorageCategorySummary]

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
                Text(verbatim: L10n.text(.overviewAnalyzedCategoriesDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Chart(categories) { summary in
                    BarMark(
                        x: .value(L10n.space(), summary.allocatedSize),
                        y: .value(L10n.text(.category), L10n.name(for: summary.category))
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(height: 220)
                .accessibilityRepresentation {
                    categoryValues
                }
            }
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
