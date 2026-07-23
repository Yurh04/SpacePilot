import Charts
import SpacePilotCore
import SwiftUI

struct DiskCapacityChart: View {
    let usedBytes: Int64
    let availableBytes: Int64
    let totalCapacityBytes: Int64

    private struct CapacitySegment: Identifiable {
        enum Kind: String {
            case used
            case available
        }

        var id: Kind { kind }
        let kind: Kind
        let name: String
        let bytes: Int64
    }

    private var segments: [CapacitySegment] {
        [
            CapacitySegment(
                kind: .used,
                name: L10n.text(.overviewDiskUsed),
                bytes: usedBytes
            ),
            CapacitySegment(
                kind: .available,
                name: L10n.text(.overviewDiskAvailable),
                bytes: availableBytes
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: L10n.text(.overviewDiskCapacityChart))
                .font(.headline)

            Chart(segments) { segment in
                SectorMark(
                    angle: .value(L10n.space(), segment.bytes),
                    innerRadius: .ratio(0.64),
                    angularInset: 1
                )
                .foregroundStyle(
                    segment.kind == .used
                        ? Color.accentColor
                        : Color.secondary.opacity(0.28)
                )
            }
            .frame(height: 220)
            .accessibilityRepresentation {
                capacityValues
            }

            capacityValues
        }
    }

    private var capacityValues: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(
                L10n.text(.overviewDiskUsed),
                value: ByteCount.string(usedBytes)
            )
            LabeledContent(
                L10n.text(.overviewDiskAvailable),
                value: ByteCount.string(availableBytes)
            )
            LabeledContent(
                L10n.text(.overviewDiskTotal),
                value: ByteCount.string(totalCapacityBytes)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(.overviewDiskCapacityChart))
    }
}
