import AppKit
import SpacePilotCore
import SwiftUI

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

    var body: some View {
        if let projection {
            let applications = projection.filtered(by: applicationSearchText)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        L10n.text(.applicationSearch),
                        text: $applicationSearchText
                    )
                    .textFieldStyle(.plain)
                    if !applicationSearchText.isEmpty {
                        Button {
                            applicationSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text(.cleanupClearSelection))
                    }
                    Divider()
                        .frame(height: 18)
                    Text(applications.count.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: 360)
                .frame(height: 32)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)

                Divider()

                Table(applications, selection: $selectedApplicationID) {
                    TableColumn(L10n.text(.application)) { projection in
                        let application = projection.application
                        HStack {
                            FileSystemItemIcon(url: application.url, size: 24)
                            VStack(alignment: .leading) {
                                Text(application.name)
                                Text(application.bundleIdentifier ?? application.url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button(L10n.text(.revealFinder)) { reveal(application.url) }
                            Divider()
                            Button(L10n.text(.applicationReviewReset)) { reset(projection) }
                            Button(L10n.text(.applicationReviewUninstall)) { uninstall(projection) }
                        }
                        .accessibilityLabel("\(application.name), \(ByteCount.string(projection.totalSize))")
                    }
                    TableColumn(L10n.version()) { Text($0.application.versionOrDash) }.width(90)
                    TableColumn(L10n.text(.applicationRelated)) { Text($0.associations.count.formatted()) }.width(70)
                    TableColumn(L10n.text(.applicationTotalSpace)) {
                        Text(ByteCount.string($0.totalSize)).monospacedDigit()
                    }.width(105)
                }
                .frame(minHeight: 280)

                if let application = selectedApplication(in: applications) {
                    Divider()
                    ApplicationDetail(
                        projection: application,
                        isAnalyzing: analyzingApplicationID == application.id,
                        searchText: relatedFileSearchText,
                        uninstall: { uninstall(application) },
                        reset: { reset(application) }
                    )
                    .frame(minHeight: 220, idealHeight: 280)
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

    private func selectedApplication(in applications: [ApplicationProjection]) -> ApplicationProjection? {
        applications.first { $0.id == selectedApplicationID }
    }
}

private struct ApplicationDetail: View {
    let projection: ApplicationProjection
    let isAnalyzing: Bool
    let searchText: String
    let uninstall: () -> Void
    let reset: () -> Void

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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(application.name).font(.headline)
                    Text(verbatim: L10n.text(.applicationOnlyHighConfidence))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text(.applicationReset), action: reset)
                Button(L10n.text(.applicationUninstall), action: uninstall).buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)

            List(visibleAssociations) { pair in
                let ownership = pair.association.ownership
                let risk = max(pair.item.risk, pair.association.risk)
                HStack(alignment: .top) {
                    FileSystemItemIcon(url: pair.item.url)
                    HStack {
                        VStack(alignment: .leading) {
                            Text(pair.item.url.lastPathComponent)
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
                        Spacer()
                        Text(verbatim: L10n.name(for: risk)).foregroundStyle(.secondary)
                        Text(ByteCount.string(pair.item.allocatedSize)).monospacedDigit()
                    }
                }
                .contextMenu { Button(L10n.text(.revealFinder)) { reveal(pair.item.url) } }
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
        .padding(.vertical, 10)
    }

}

private extension ApplicationRecord {
    var versionOrDash: String { version ?? "—" }
}
