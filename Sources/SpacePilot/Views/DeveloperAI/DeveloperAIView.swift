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
                    Label(L10n.text(.aiDeveloperStorage), systemImage: "hammer")
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
                            Text(verbatim: "\(application.application.supportLevel == .deep ? L10n.text(.aiDeepAnalysis) : L10n.text(.aiBasicFootprint)) · \(ByteCount.string(application.totalSize))")
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
                            pluginDiagnostics: pluginDiagnostics(
                                for: application,
                                from: projection.pluginDiagnostics
                            ),
                            selectedTab: $model.selectedAIApplicationTab
                        )
                    } else {
                        ContentUnavailableView(L10n.text(.aiSelectApplication), systemImage: "sparkles.rectangle.stack")
                    }
                }
            }
            .navigationTitle(L10n.developerAI())
            .onAppear {
                if !projection.applications.contains(where: { $0.id == model.selectedAIApplicationID }) {
                    model.selectedAIApplicationID = projection.applications.first?.id
                }
            }
        } else if hasSnapshot {
            ProgressView(L10n.preparingSummary())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(L10n.developerAI())
        } else {
            empty(L10n.developerAI(), image: "sparkles.rectangle.stack")
        }
    }

    private func selectedApplication(in applications: [AIApplicationProjection]) -> AIApplicationProjection? {
        applications.first { $0.id == model.selectedAIApplicationID }
    }

    private func pluginDiagnostics(
        for application: AIApplicationProjection,
        from diagnostics: [String]
    ) -> [String] {
        application.application.bundleIdentifier == "com.openai.codex" ? diagnostics : []
    }
}
