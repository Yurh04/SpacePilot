import SpacePilotCore
import SwiftUI

struct DeveloperAIView: View {
    @Bindable var model: AppModel
    let projection: DeveloperAIProjection?
    let hasSnapshot: Bool

    var body: some View {
        if let projection {
            VStack(spacing: 0) {
                HStack {
                    Label("Developer storage", systemImage: "hammer")
                    Spacer()
                    Text(ByteCount.string(projection.developerBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .frame(height: 44)
                Divider()
                HSplitView {
                    List(projection.applications, selection: $model.selectedAIApplicationID) { application in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(application.application.name)
                                .fontWeight(.medium)
                            Text("\(application.application.supportLevel == .deep ? "Deep analysis" : "Basic footprint") · \(ByteCount.string(application.totalSize))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(application.id)
                    }
                    .frame(minWidth: 190, idealWidth: 230, maxWidth: 280)

                    if let application = selectedApplication(in: projection.applications) {
                        AIApplicationDetailView(
                            projection: application,
                            queryProjection: model.aiQueryProjection,
                            isPreparingQuery: model.isPreparingAIQuery,
                            selectedTab: $model.selectedAIApplicationTab
                        )
                    } else {
                        ContentUnavailableView("Select an AI application", systemImage: "sparkles.rectangle.stack")
                    }
                }
            }
            .navigationTitle("Developer & AI")
            .onAppear {
                if !projection.applications.contains(where: { $0.id == model.selectedAIApplicationID }) {
                    model.selectedAIApplicationID = projection.applications.first?.id
                }
            }
        } else if hasSnapshot {
            ProgressView("Preparing summary…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Developer & AI")
        } else {
            empty("Developer & AI", image: "sparkles.rectangle.stack")
        }
    }

    private func selectedApplication(in applications: [AIApplicationProjection]) -> AIApplicationProjection? {
        applications.first { $0.id == model.selectedAIApplicationID }
    }
}
