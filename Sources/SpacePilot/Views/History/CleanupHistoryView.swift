import SpacePilotCore
import SwiftUI

struct CleanupHistoryView: View {
    let transactions: [CleanupTransaction]

    var body: some View {
        if transactions.isEmpty {
            ContentUnavailableView {
                Label(L10n.text(.cleanupHistoryEmpty), systemImage: "clock.arrow.circlepath")
            } description: {
                Text(verbatim: L10n.text(.cleanupHistoryEmptyDescription))
            }
            .navigationTitle(L10n.cleanupHistory())
        } else {
            List(transactions) { transaction in
                DisclosureGroup {
                    ForEach(transaction.outcomes) { outcome in
                        let revealURL = FinderReveal.cleanupHistoryURL(
                            resultingURL: outcome.resultingURL,
                            sourceURL: outcome.sourceURL
                        )
                        let displayURL = revealURL
                            ?? outcome.sourceURL
                            ?? outcome.resultingURL
                        if let displayURL {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayURL.lastPathComponent)
                                    let parentPath = displayURL.deletingLastPathComponent()
                                        .path(percentEncoded: false)
                                    Text(parentPath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel(
                                            "\(L10n.cleanupSourcePath()): \(parentPath)"
                                        )
                                    Text(verbatim: L10n.cleanupOutcomeMessage(outcome))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    if let bytes = outcome.sourceAllocatedSize {
                                        Text(ByteCount.string(bytes))
                                            .monospacedDigit()
                                    }
                                    Text(verbatim: L10n.name(for: outcome.status))
                                }
                            }
                            .onDoubleClickRevealInFinder(revealURL)
                        } else {
                            LabeledContent(
                                L10n.cleanupOutcomeMessage(outcome.message, status: outcome.status),
                                value: L10n.name(for: outcome.status)
                            )
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(verbatim: L10n.name(for: transaction.summary))
                                .fontWeight(.medium)
                            Text(transaction.completedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(verbatim: L10n.movedCount(transaction.outcomes.filter { $0.status == .movedToTrash }.count))
                            if let bytes = transaction.verifiedFreedBytes {
                                Text(verbatim: L10n.verifiedSpace(ByteCount.string(bytes)))
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.cleanupHistory())
        }
    }
}
