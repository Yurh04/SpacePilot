import SpacePilotCore
import SwiftUI

struct DeveloperAIView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let snapshot = model.latestSnapshot {
            VStack(spacing: 0) {
                HStack {
                    Label("Developer storage", systemImage: "hammer")
                    Spacer()
                    Text(ByteCount.string(developerBytes(in: snapshot)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .frame(height: 44)
                Divider()
                HSplitView {
                List(snapshot.aiApplications, selection: $model.selectedAIApplicationID) { application in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(application.name)
                            .fontWeight(.medium)
                        Text("\(application.supportLevel == .deep ? "Deep analysis" : "Basic footprint") · \(ByteCount.string(applicationSize(application, in: snapshot)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(application.id)
                }
                .frame(minWidth: 190, idealWidth: 230, maxWidth: 280)

                if let application = selectedApplication(in: snapshot) {
                    AIApplicationDetailView(
                        application: application,
                        snapshot: snapshot,
                        selectedTab: $model.selectedAIApplicationTab,
                        searchText: model.searchText
                    )
                } else {
                    ContentUnavailableView("Select an AI application", systemImage: "sparkles.rectangle.stack")
                }
                }
            }
            .navigationTitle("Developer & AI")
            .onAppear {
                if model.selectedAIApplicationID == nil {
                    model.selectedAIApplicationID = snapshot.aiApplications.first?.id
                }
            }
        } else {
            empty("Developer & AI", image: "sparkles.rectangle.stack")
        }
    }

    private func selectedApplication(in snapshot: ScanSnapshot) -> AIApplicationRecord? {
        snapshot.aiApplications.first { $0.id == model.selectedAIApplicationID }
    }

    private func developerBytes(in snapshot: ScanSnapshot) -> Int64 {
        snapshot.items.filter { $0.category == .developer }.reduce(0) { $0 + $1.allocatedSize }
    }

    private func applicationSize(_ application: AIApplicationRecord, in snapshot: ScanSnapshot) -> Int64 {
        let pluginSize = snapshot.plugins
            .filter { application.pluginIDs.contains($0.id) }
            .reduce(0) { $0 + $1.allocatedSize }
        let skillSize = snapshot.skills
            .filter {
                guard application.skillIDs.contains($0.id) else { return false }
                guard let parentPluginID = $0.parentPluginID else { return true }
                return !application.pluginIDs.contains(parentPluginID)
            }
            .reduce(0) { $0 + $1.allocatedSize }
        let itemSize = snapshot.items
            .filter { application.itemIDs.contains($0.id) }
            .reduce(0) { $0 + $1.allocatedSize }
        return application.applicationAllocatedSize + pluginSize + skillSize + itemSize
    }
}
