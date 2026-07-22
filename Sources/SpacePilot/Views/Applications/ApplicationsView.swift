import AppKit
import SpacePilotCore
import SwiftUI

struct ApplicationsView: View {
    let projection: ApplicationListProjection?
    let hasSnapshot: Bool
    let searchText: String
    let uninstall: (ApplicationRecord) -> Void
    let reset: (ApplicationRecord) -> Void
    @State private var selectedApplicationID: UUID?

    var body: some View {
        if let projection {
            let applications = projection.filtered(by: searchText)
            VStack(spacing: 0) {
                Table(applications, selection: $selectedApplicationID) {
                    TableColumn("Application") { projection in
                        let application = projection.application
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                                .resizable()
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading) {
                                Text(application.name)
                                Text(application.bundleIdentifier ?? application.url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Reveal in Finder") { reveal(application.url) }
                            Divider()
                            Button("Review Reset…") { reset(application) }
                            Button("Review Uninstall…") { uninstall(application) }
                        }
                        .accessibilityLabel("\(application.name), \(ByteCount.string(projection.totalSize))")
                    }
                    TableColumn("Version") { Text($0.application.versionOrDash) }.width(90)
                    TableColumn("Related") { Text($0.associations.count.formatted()) }.width(70)
                    TableColumn("Total space") {
                        Text(ByteCount.string($0.totalSize)).monospacedDigit()
                    }.width(105)
                }
                .frame(minHeight: 280)

                if let application = selectedApplication(in: applications) {
                    Divider()
                    ApplicationDetail(
                        projection: application,
                        uninstall: { uninstall(application.application) },
                        reset: { reset(application.application) }
                    )
                    .frame(minHeight: 220, idealHeight: 280)
                }
            }
            .navigationTitle("Applications")
            .onChange(of: applications.map(\.id), initial: true) { _, applicationIDs in
                if !applicationIDs.contains(where: { $0 == selectedApplicationID }) {
                    selectedApplicationID = applicationIDs.first
                }
            }
        } else if hasSnapshot {
            ProgressView("Preparing summary…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Applications")
        } else {
            empty("Applications", image: "square.grid.2x2")
        }
    }

    private func selectedApplication(in applications: [ApplicationProjection]) -> ApplicationProjection? {
        applications.first { $0.id == selectedApplicationID }
    }
}

private struct ApplicationDetail: View {
    let projection: ApplicationProjection
    let uninstall: () -> Void
    let reset: () -> Void

    private var application: ApplicationRecord { projection.application }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(application.name).font(.headline)
                    Text("Only high-confidence related files are preselected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset…", action: reset)
                Button("Uninstall…", action: uninstall).buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)

            List(projection.associations) { pair in
                HStack {
                    VStack(alignment: .leading) {
                        Text(pair.item.url.lastPathComponent)
                        Text(pair.item.url.deletingLastPathComponent().path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("\(pair.association.evidence.displayName) · \(pair.association.confidence.displayName) confidence")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(pair.association.risk.displayName).foregroundStyle(.secondary)
                    Text(ByteCount.string(pair.item.allocatedSize)).monospacedDigit()
                }
                .contextMenu { Button("Reveal in Finder") { reveal(pair.item.url) } }
            }
            .listStyle(.inset)
        }
        .padding(.vertical, 10)
    }

}

private extension ApplicationRecord {
    var versionOrDash: String { version ?? "—" }
}

private extension AssociationEvidence {
    var displayName: String {
        switch self {
        case .exactBundleIdentifier: "Bundle identifier"
        case .exactContainerIdentifier: "Container identifier"
        case .knownRule: "Known application rule"
        case .signedHelperRelationship: "Signed helper"
        case .vendorAndNameMatch: "Application name"
        }
    }
}

private extension AssociationConfidence {
    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}
