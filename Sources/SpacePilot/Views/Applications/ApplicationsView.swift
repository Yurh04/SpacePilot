import AppKit
import SpacePilotCore
import SwiftUI

struct ApplicationAssociationGroup: Identifiable {
    var id: ItemCategory { category }
    let category: ItemCategory
    let pairs: [ApplicationAssociationProjection]
    let allocatedSize: Int64

    static func grouped(
        _ pairs: [ApplicationAssociationProjection]
    ) -> [ApplicationAssociationGroup] {
        let pairsByCategory = Dictionary(grouping: pairs) { $0.item.category }
        return ItemCategory.allCases.compactMap { category in
            guard let categoryPairs = pairsByCategory[category] else {
                return nil
            }
            let orderedPairs = categoryPairs.sorted {
                if $0.item.allocatedSize != $1.item.allocatedSize {
                    return $0.item.allocatedSize > $1.item.allocatedSize
                }
                return $0.item.url.path.localizedStandardCompare(
                    $1.item.url.path
                ) == .orderedAscending
            }
            return ApplicationAssociationGroup(
                category: category,
                pairs: orderedPairs,
                allocatedSize: orderedPairs.reduce(Int64(0)) {
                    $0 + $1.item.allocatedSize
                }
            )
        }
    }
}

struct ApplicationsView: View {
    let projection: ApplicationListProjection?
    let hasSnapshot: Bool
    let relatedFileSearchText: String
    let analyzingApplicationID: UUID?
    let analyze: (ApplicationProjection) -> Void
    let uninstall: (ApplicationProjection) -> Void
    let reset: (ApplicationProjection) -> Void
    @State private var selectedApplicationID: UUID?
    @State private var applicationSearchText = ""
    @State private var applicationSortOrder = ApplicationSortOrder.totalSpace

    var body: some View {
        if let projection {
            let applications = projection.results(
                matching: applicationSearchText,
                sortedBy: applicationSortOrder
            )

            HSplitView {
                ApplicationListPane(
                    applications: applications,
                    selection: $selectedApplicationID,
                    searchText: $applicationSearchText,
                    sortOrder: $applicationSortOrder,
                    uninstall: uninstall,
                    reset: reset
                )
                .frame(width: 280)

                if let application = selectedApplication(in: applications) {
                    ApplicationDetail(
                        projection: application,
                        isAnalyzing: analyzingApplicationID == application.id,
                        searchText: relatedFileSearchText,
                        uninstall: { uninstall(application) },
                        reset: { reset(application) }
                    )
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        L10n.text(.application),
                        systemImage: "square.grid.2x2",
                        description: Text(L10n.text(.applicationOnlyHighConfidence))
                    )
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(L10n.applications())
            .onChange(of: applications.map(\.id), initial: true) { _, applicationIDs in
                if !applicationIDs.contains(where: { $0 == selectedApplicationID }) {
                    selectedApplicationID = applicationIDs.first
                }
            }
            .onChange(of: selectedApplicationID, initial: true) {
                _, applicationID in
                guard let application = applications.first(where: {
                    $0.id == applicationID
                }) else {
                    return
                }
                analyze(application)
            }
            .onChange(
                of: selectedApplication(in: applications)?.associations.count,
                initial: true
            ) { _, _ in
                guard let application = selectedApplication(in: applications)
                else { return }
                analyze(application)
            }
        } else if hasSnapshot {
            ProgressView(L10n.preparingSummary())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(L10n.applications())
        } else {
            empty(L10n.applications(), image: "square.grid.2x2")
        }
    }

    private func selectedApplication(
        in applications: [ApplicationProjection]
    ) -> ApplicationProjection? {
        applications.first { $0.id == selectedApplicationID }
    }
}

private struct ApplicationListPane: View {
    let applications: [ApplicationProjection]
    @Binding var selection: UUID?
    @Binding var searchText: String
    @Binding var sortOrder: ApplicationSortOrder
    let uninstall: (ApplicationProjection) -> Void
    let reset: (ApplicationProjection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.text(.applicationSearch), text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text(.cleanupClearSelection))
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    .background.secondary,
                    in: RoundedRectangle(cornerRadius: 8)
                )

                HStack {
                    Text(applications.count.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker(L10n.text(.applicationSort), selection: $sortOrder) {
                        ForEach(ApplicationSortOrder.allCases, id: \.self) { order in
                            Text(order.localizedName).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel(L10n.text(.applicationSort))
                }
                .font(.caption)
            }
            .padding(12)

            Divider()

            List(applications, selection: $selection) { projection in
                let application = projection.application
                ApplicationListRow(projection: projection)
                    .tag(projection.id)
                    .contextMenu {
                        Button(L10n.text(.revealFinder)) { reveal(application.url) }
                        Divider()
                        Button(L10n.text(.applicationReviewReset)) { reset(projection) }
                        Button(L10n.text(.applicationReviewUninstall)) {
                            uninstall(projection)
                        }
                    }
                    .accessibilityLabel(
                        "\(application.name), \(ByteCount.string(projection.totalSize))"
                    )
            }
            .listStyle(.sidebar)
            .overlay {
                if applications.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView(
                            L10n.applications(),
                            systemImage: "square.grid.2x2"
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
    }
}

private struct ApplicationListRow: View {
    let projection: ApplicationProjection

    private var application: ApplicationRecord { projection.application }

    var body: some View {
        HStack(spacing: 10) {
            FileSystemItemIcon(url: application.url, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(application.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(application.bundleIdentifier ?? application.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteCount.string(projection.totalSize))
                    .fontWeight(.medium)
                    .monospacedDigit()
                Text(projection.associations.count.formatted())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ApplicationDetail: View {
    let projection: ApplicationProjection
    let isAnalyzing: Bool
    let searchText: String
    let uninstall: () -> Void
    let reset: () -> Void
    @State private var collapsedCategories: Set<ItemCategory> = []

    private var application: ApplicationRecord { projection.application }
    private var visibleAssociations: [ApplicationAssociationProjection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projection.associations }
        return projection.associations.filter { pair in
            pair.item.url.path.localizedCaseInsensitiveContains(query)
                || pair.item.explanation.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let associationGroups = ApplicationAssociationGroup.grouped(
            visibleAssociations
        )

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    FileSystemItemIcon(url: application.url, size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(application.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(application.bundleIdentifier ?? application.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(verbatim: application.versionOrDash)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button(L10n.text(.applicationReset), action: reset)
                    Button(L10n.text(.applicationUninstall), action: uninstall)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)

            Divider()

            HStack(spacing: 12) {
                ApplicationMetric(
                    title: L10n.text(.applicationTotalSpace),
                    value: ByteCount.string(projection.totalSize),
                    systemImage: "internaldrive"
                )
                ApplicationMetric(
                    title: L10n.text(.application),
                    value: ByteCount.string(application.allocatedSize),
                    systemImage: "app"
                )
                ApplicationMetric(
                    title: L10n.text(.applicationRelated),
                    value: projection.associations.count.formatted(),
                    systemImage: "link"
                )
            }
            .padding(16)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(.items))
                        .font(.headline)
                    Text(verbatim: L10n.text(.applicationOnlyHighConfidence))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !searchText.isEmpty {
                    Text(visibleAssociations.count.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            List {
                ForEach(associationGroups) { group in
                    DisclosureGroup(
                        isExpanded: expansionBinding(for: group.category)
                    ) {
                        ForEach(group.pairs) { pair in
                            ApplicationAssociationRow(pair: pair)
                                .contextMenu {
                                    Button(L10n.text(.revealFinder)) {
                                        reveal(pair.item.url)
                                    }
                                }
                        }
                    } label: {
                        ApplicationAssociationGroupHeader(group: group)
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if isAnalyzing {
                    ProgressView()
                } else if !searchText.isEmpty && visibleAssociations.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if projection.associations.isEmpty {
                    ContentUnavailableView(
                        L10n.text(.applicationOnlyHighConfidence),
                        systemImage: "externaldrive.badge.magnifyingglass"
                    )
                }
            }
        }
    }

    private func expansionBinding(
        for category: ItemCategory
    ) -> Binding<Bool> {
        guard searchText.isEmpty else { return .constant(true) }
        return Binding(
            get: { !collapsedCategories.contains(category) },
            set: { isExpanded in
                if isExpanded {
                    collapsedCategories.remove(category)
                } else {
                    collapsedCategories.insert(category)
                }
            }
        )
    }
}

private struct ApplicationAssociationGroupHeader: View {
    let group: ApplicationAssociationGroup

    var body: some View {
        HStack(spacing: 8) {
            Label(
                L10n.name(for: group.category),
                systemImage: group.category.systemImage
            )
            Spacer(minLength: 12)
            Text(
                "\(group.pairs.count.formatted()) · "
                    + ByteCount.string(group.allocatedSize)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .textCase(nil)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct ApplicationMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .background.secondary,
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}

private struct ApplicationAssociationRow: View {
    let pair: ApplicationAssociationProjection

    private var ownership: AssociationOwnership { pair.association.ownership }
    private var risk: RiskLevel { max(pair.item.risk, pair.association.risk) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            FileSystemItemIcon(url: pair.item.url, size: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(pair.item.url.lastPathComponent)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(pair.item.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if ownership == .shared {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: L10n.name(for: ownership))
                    Text(verbatim: "·")
                    Text(verbatim: L10n.association(
                        pair.association.evidence,
                        confidence: pair.association.confidence
                    ))
                }
                .font(.caption)
                .foregroundStyle(ownership == .shared ? .orange : .secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(ByteCount.string(pair.item.allocatedSize))
                    .fontWeight(.medium)
                    .monospacedDigit()
                Text(verbatim: L10n.name(for: risk))
                    .font(.caption)
                    .foregroundStyle(risk.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(risk.tint.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 3)
    }
}

private extension ApplicationRecord {
    var versionOrDash: String { version ?? "—" }
}

private extension ApplicationSortOrder {
    var localizedName: String {
        switch self {
        case .totalSpace:
            L10n.text(.applicationTotalSpace)
        case .name:
            L10n.text(.name)
        case .relatedFiles:
            L10n.text(.applicationRelated)
        case .lastUsed:
            L10n.text(.applicationLastUsed)
        }
    }
}

private extension RiskLevel {
    var tint: Color {
        switch self {
        case .safe:
            .green
        case .rebuildable:
            .blue
        case .sensitive:
            .orange
        case .managed:
            .secondary
        }
    }
}

private extension ItemCategory {
    var systemImage: String {
        switch self {
        case .application: "app"
        case .personal: "person.crop.circle"
        case .developer: "hammer"
        case .aiData: "sparkles.rectangle.stack"
        case .cache: "internaldrive"
        case .log: "doc.text.magnifyingglass"
        case .conversation: "bubble.left.and.bubble.right"
        case .model: "cpu"
        case .plugin: "puzzlepiece.extension"
        case .skill: "wand.and.stars"
        case .system: "gearshape.2"
        case .unclassified: "questionmark.folder"
        }
    }
}
