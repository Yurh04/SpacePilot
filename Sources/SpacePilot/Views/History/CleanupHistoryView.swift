import SpacePilotCore
import SwiftUI

struct CleanupHistoryView: View {
    let transactions: [CleanupTransaction]

    var body: some View {
        if transactions.isEmpty {
            ContentUnavailableView {
                Label("No cleanup history", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Verified cleanup operations will appear here.")
            }
            .navigationTitle("Cleanup History")
        } else {
            List(transactions) { transaction in
                DisclosureGroup {
                    ForEach(transaction.outcomes) { outcome in
                        LabeledContent(outcome.message, value: outcome.status.displayName)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(transaction.summary.displayName)
                                .fontWeight(.medium)
                            Text(transaction.completedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(transaction.outcomes.filter { $0.status == .movedToTrash }.count) moved")
                            if let bytes = transaction.verifiedFreedBytes {
                                Text("\(ByteCount.string(bytes)) verified")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Cleanup History")
        }
    }
}

private extension CleanupSummary {
    var displayName: String {
        switch self {
        case .success: "Completed"
        case .partialFailure: "Partially completed"
        case .failed: "Not completed"
        }
    }
}

private extension CleanupOutcomeStatus {
    var displayName: String {
        switch self {
        case .movedToTrash: "Moved to Trash"
        case .skippedChanged: "Skipped: changed"
        case .skippedProtected: "Skipped: protected"
        case .failed: "Failed"
        }
    }
}
