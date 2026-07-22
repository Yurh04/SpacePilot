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
                    TableColumn("Application") { application in
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
                        .accessibilityLabel("\(application.name), \(ByteCount.string(projection.totalSize(for: application.id)))")
                    }
                    TableColumn("Version", value: \.versionOrDash).width(90)
                    TableColumn("Related") { Text($0.associations.count.formatted()) }.width(70)
                    TableColumn("Total space") {
                        Text(ByteCount.string(projection.totalSize(for: $0.id))).monospacedDigit()
                    }.width(105)
                }
                .frame(minHeight: 280)

                if let application = selectedApplication(in: applications) {
                    Divider()
                    ApplicationDetail(
                        application: application,
                        uninstall: { uninstall(application) },
                        reset: { reset(application) }
                    )
                    .frame(minHeight: 220, idealHeight: 280)
                }
            }
            .navigationTitle("Applications")
            .onAppear {
                if !applications.contains(where: { $0.id == selectedApplicationID }) {
                    selectedApplicationID = applications.first?.id
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

    private func selectedApplication(in applications: [ApplicationRecord]) -> ApplicationRecord? {
        applications.first { $0.id == selectedApplicationID }
    }
}

private struct ApplicationDetail: View {
    let application: ApplicationRecord
    let uninstall: () -> Void
    let reset: () -> Void

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

            List(associations) { association in
                HStack {
                    VStack(alignment: .leading) {
                        Text(association.evidence.displayName)
                        Text("\(association.confidence.displayName) confidence")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(association.risk.displayName).foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
        .padding(.vertical, 10)
    }

    private var associations: [ArtifactAssociation] {
        application.associations.sorted { $0.confidence > $1.confidence }
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
