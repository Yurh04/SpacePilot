import SpacePilotCore
import SwiftUI

/// Developer & AI page shell. Presents a stable left-side section list
/// (Overview / AI Apps / Skills / Plugins / CLI Tools) and routes to the
/// matching read-only section view. This persistent shell owns the section
/// routing and each page's selection state (passed down as bindings) so that
/// switching sections never resets a page's selection and never pollutes
/// `selectedAIApplicationID` / `selectedAIApplicationTab`.
///
/// The internal layout uses `HSplitView` + a section `List` rather than a
/// nested split container to avoid a second sidebar-collapse/toolbar behavior
/// and to keep the narrowest-window width small (section ~140 + AI apps ~180 +
/// detail ~420).
struct DeveloperAIView: View {
    @Bindable var model: AppModel
    let projection: DeveloperAIProjection?
    let hasSnapshot: Bool
    @State private var section: AIManagementSection = .overview
    // Per-page selection is owned by this persistent shell (not the switched-in
    // subviews) so switching sections never resets a page's selection when
    // SwiftUI destroys/recreates the conditional child subtree.
    @State private var selectedAIEntryID: String?
    @State private var selectedSkillID: UUID?
    @State private var selectedPluginID: UUID?
    @State private var selectedCLIID: String?

    private var registryOnlyApplications: [AIApplicationJoin.RegistryOnlyApplication] {
        guard let projection else { return [] }
        return AIApplicationJoin.registryOnlyApplications(
            deepApplications: projection.applications.map(\.application),
            registryApplications: model.aiManagementProjection.applications
        )
    }

    var body: some View {
        if let projection {
            HSplitView {
                List(AIManagementSection.allCases, selection: $section) { entry in
                    Label(
                        L10n.aiSectionTitle(for: entry),
                        systemImage: entry.systemImage
                    )
                    .tag(entry)
                }
                .frame(minWidth: 140, idealWidth: 160, maxWidth: 190)
                sectionContent(projection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(L10n.developerAI())
        } else if hasSnapshot {
            ProgressView(L10n.preparingSummary())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(L10n.developerAI())
        } else {
            ContentUnavailableView(
                L10n.developerAI(),
                systemImage: "sparkles.rectangle.stack",
                description: Text(L10n.text(.aiStateNotScanned))
            )
            .navigationTitle(L10n.developerAI())
        }
    }

    @ViewBuilder
    private func sectionContent(_ projection: DeveloperAIProjection) -> some View {
        switch section {
        case .overview:
            AIManagementOverviewView(
                managementProjection: model.aiManagementProjection,
                appCount: AIApplicationJoin.applicationCount(
                    deepApplications: projection.applications.map(\.application),
                    registryApplications: model.aiManagementProjection.applications
                ),
                globalSkillCount: projection.allSkills.count,
                globalPluginCount: projection.allPlugins.count,
                isDiscovering: model.isDiscoveringAITools,
                discoveryError: model.aiDiscoveryError
            )
        case .apps:
            AIAppsSectionView(
                model: model,
                projection: projection,
                registryOnlyApplications: registryOnlyApplications,
                selectedEntryID: $selectedAIEntryID,
                isDiscovering: model.isDiscoveringAITools,
                discoveryError: model.aiDiscoveryError
            )
        case .skills:
            GlobalSkillsView(
                skills: projection.allSkills,
                searchText: model.searchText,
                selection: $selectedSkillID
            )
        case .plugins:
            GlobalPluginsView(
                plugins: projection.allPlugins,
                searchText: model.searchText,
                selection: $selectedPluginID
            )
        case .cli:
            CLIToolsView(
                clis: model.aiManagementProjection.clis,
                searchText: model.searchText,
                isDiscovering: model.isDiscoveringAITools,
                discoveryError: model.aiDiscoveryError,
                selection: $selectedCLIID
            )
        }
    }
}
