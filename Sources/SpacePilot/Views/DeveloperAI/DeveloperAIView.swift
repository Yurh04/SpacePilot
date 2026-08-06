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
                        .onDoubleClickRevealInFinder(
                            FinderReveal.applicationURL(for: application.application)
                        )
                        .contextMenu {
                            if let url = FinderReveal.applicationURL(
                                for: application.application
                            ) {
                                Button(L10n.text(.revealFinder)) {
                                    FinderReveal.reveal(url)
                                }
                            }
                        }
                        .tag(application.id)
                    }
                    .frame(minWidth: 190, idealWidth: 230, maxWidth: 280)

                    if projection.applications.isEmpty {
                        ContentUnavailableView(
                            L10n.developerAI(),
                            systemImage: "sparkles.rectangle.stack",
                            description: Text(verbatim: L10n.noData())
                        )
                    } else if let application = selectedApplication(in: projection.applications) {
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
            .onChange(of: projection.applications.map(\.id), initial: true) {
                _, applicationIDs in
                if !applicationIDs.contains(where: { $0 == model.selectedAIApplicationID }) {
                    model.selectedAIApplicationID = applicationIDs.first
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
