import SpacePilotCore
import SwiftUI

struct DeveloperAIView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let snapshot = model.latestSnapshot {
            HSplitView {
                List(snapshot.aiApplications, selection: $model.selectedAIApplicationID) { application in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(application.name)
                            .fontWeight(.medium)
                        Text(application.supportLevel == .deep ? "Deep analysis" : "Basic footprint")
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
}
