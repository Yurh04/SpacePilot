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
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: L10n.text(.overviewDiskCapacityChart))
                .font(.headline)
                .accessibilityHidden(true)

            HStack(spacing: 16) {
                ZStack {
                    Chart(segments) { segment in
                        SectorMark(
                            angle: .value(L10n.space(), segment.bytes),
                            innerRadius: .ratio(0.72),
                            angularInset: 1.5
                        )
                        .foregroundStyle(
                            segment.kind == .used
                                ? Color.accentColor
                                : Color.secondary.opacity(0.22)
                        )
                    }
                    .chartLegend(.hidden)

                    VStack(spacing: 1) {
                        Text(ByteCount.string(availableBytes))
                            .font(.headline)
                            .monospacedDigit()
                            .minimumScaleFactor(0.75)
                        Text(verbatim: L10n.text(.overviewDiskAvailable))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
                .frame(width: 132, height: 132)

                visibleCapacityValues
            }
            .accessibilityHidden(true)
            .accessibilityRepresentation {
                accessibleCapacityValues
            }
        }
    }

    private var visibleCapacityValues: some View {
        VStack(alignment: .leading, spacing: 10) {
            capacityValue(
                L10n.text(.overviewDiskUsed),
                bytes: usedBytes,
                color: .accentColor
            )
            capacityValue(
                L10n.text(.overviewDiskAvailable),
                bytes: availableBytes,
                color: .secondary.opacity(0.45)
            )
            Divider()
            capacityValue(
                L10n.text(.overviewDiskTotal),
                bytes: totalCapacityBytes,
                color: .clear
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func capacityValue(_ title: String, bytes: Int64, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ByteCount.string(bytes))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    private var accessibleCapacityValues: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: L10n.text(.overviewDiskCapacityChart))
            visibleCapacityValues
        }
    }
}
