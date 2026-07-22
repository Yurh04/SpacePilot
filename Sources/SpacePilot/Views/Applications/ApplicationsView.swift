import AppKit
import SpacePilotCore
import SwiftUI

struct ApplicationsView: View {
    let snapshot: ScanSnapshot?
    let searchText: String
    let uninstall: (ApplicationRecord) -> Void
    let reset: (ApplicationRecord) -> Void
    @State private var selectedApplicationID: UUID?

    var body: some View {
        if let snapshot {
            VStack(spacing: 0) {
                Table(applications(snapshot), selection: $selectedApplicationID) {
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
                        .accessibilityLabel("\(application.name), \(ByteCount.string(totalSize(application, snapshot: snapshot)))")
                    }
                    TableColumn("Version", value: \.versionOrDash).width(90)
                    TableColumn("Related") { Text($0.associations.count.formatted()) }.width(70)
                    TableColumn("Total space") {
                        Text(ByteCount.string(totalSize($0, snapshot: snapshot))).monospacedDigit()
                    }.width(105)
                }
                .frame(minHeight: 280)

                if let application = selectedApplication(in: snapshot) {
                    Divider()
                    ApplicationDetail(
                        application: application,
                        snapshot: snapshot,
                        uninstall: { uninstall(application) },
                        reset: { reset(application) }
                    )
                    .frame(minHeight: 220, idealHeight: 280)
                }
            }
            .navigationTitle("Applications")
            .onAppear {
                if selectedApplicationID == nil {
                    selectedApplicationID = applications(snapshot).first?.id
                }
            }
        } else {
            empty("Applications", image: "square.grid.2x2")
        }
    }

    private func applications(_ snapshot: ScanSnapshot) -> [ApplicationRecord] {
        snapshot.applications.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }.sorted { totalSize($0, snapshot: snapshot) > totalSize($1, snapshot: snapshot) }
    }

    private func selectedApplication(in snapshot: ScanSnapshot) -> ApplicationRecord? {
        snapshot.applications.first { $0.id == selectedApplicationID }
    }

    private func totalSize(_ application: ApplicationRecord, snapshot: ScanSnapshot) -> Int64 {
        application.allocatedSize + snapshot.items
            .filter { $0.ownerID == application.id }
            .reduce(0) { $0 + $1.allocatedSize }
    }
}

private struct ApplicationDetail: View {
    let application: ApplicationRecord
    let snapshot: ScanSnapshot
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

            List(associations) { pair in
                HStack {
                    VStack(alignment: .leading) {
                        Text(pair.item.url.lastPathComponent)
                        Text("\(pair.association.evidence.displayName) · \(pair.association.confidence.displayName) confidence")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(pair.item.risk.displayName).foregroundStyle(.secondary)
                    Text(ByteCount.string(pair.item.allocatedSize)).monospacedDigit()
                }
                .contextMenu { Button("Reveal in Finder") { reveal(pair.item.url) } }
            }
            .listStyle(.inset)
        }
        .padding(.vertical, 10)
    }

    private var associations: [AssociationPair] {
        application.associations.compactMap { association in
            snapshot.items.first { $0.id == association.itemID }.map {
                AssociationPair(association: association, item: $0)
            }
        }.sorted { $0.association.confidence > $1.association.confidence }
    }
}

private struct AssociationPair: Identifiable {
    var id: UUID { association.id }
    let association: ArtifactAssociation
    let item: ScannedItem
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
