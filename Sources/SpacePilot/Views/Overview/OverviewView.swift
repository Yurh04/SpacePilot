import SpacePilotCore
import SwiftUI

struct OverviewView: View {
    let snapshot: ScanSnapshot?
    let startScan: () -> Void

    var body: some View {
        Group {
            if let snapshot {
                let projection = OverviewProjection(snapshot: snapshot)
                List {
                    Section {
                        LabeledContent("Internal disk used", value: ByteCount.string(projection.totalUsedBytes))
                        LabeledContent("Analyzed locally", value: ByteCount.string(projection.analyzedBytes))
                        LabeledContent("Safe recommendations", value: ByteCount.string(projection.reclaimableBytes))
                    } header: {
                        Text("Storage at a glance")
                    }

                    Section("Safe recommendations") {
                        if projection.preselectedRecommendations.isEmpty {
                            Text("No safe cleanup recommendations yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(projection.preselectedRecommendations.prefix(8)) { item in
                                StorageItemRow(item: item)
                            }
                        }
                    }

                    if !snapshot.coverage.isComplete {
                        Section("Limited coverage") {
                            Label("Some folders could not be read. Results show only verified data.", systemImage: "lock.trianglebadge.exclamationmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Overview")
            } else {
                ContentUnavailableView {
                    Label("Analyze this Mac", systemImage: "internaldrive")
                } description: {
                    Text("SpacePilot works locally and indexes metadata only.")
                } actions: {
                    Button("Start Scan", action: startScan)
                        .buttonStyle(.borderedProminent)
                }
                .navigationTitle("Overview")
            }
        }
    }
}
