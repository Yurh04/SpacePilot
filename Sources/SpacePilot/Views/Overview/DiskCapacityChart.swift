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
                .accessibilityHidden(true)

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
                .annotation(position: .overlay) {
                    if segment.bytes > 0 {
                        Text(verbatim: segment.name)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
            }
            .frame(height: 220)
            .accessibilityRepresentation {
                accessibleCapacityValues
            }

            visibleCapacityValues
                .accessibilityHidden(true)
        }
    }

    private var visibleCapacityValues: some View {
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
    }

    private var accessibleCapacityValues: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: L10n.text(.overviewDiskCapacityChart))
            visibleCapacityValues
        }
    }
}
