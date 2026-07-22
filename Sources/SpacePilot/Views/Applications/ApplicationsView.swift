import SpacePilotCore
import SwiftUI

struct ApplicationsView: View {
    let snapshot: ScanSnapshot?
    let searchText: String
    let uninstall: (ApplicationRecord) -> Void

    var body: some View {
        if let snapshot {
            Table(applications(snapshot)) {
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
                        .contextMenu {
                            Button("Reveal in Finder") { reveal(application.url) }
                            Divider()
                            Button("Review Uninstall…") { uninstall(application) }
                        }
                    }
                    .accessibilityLabel("\(application.name), \(ByteCount.string(totalSize(application, snapshot: snapshot)))")
                }
                TableColumn("Version", value: \.versionOrDash)
                    .width(100)
                TableColumn("Related files") { application in
                    Text(application.associations.count.formatted())
                }
                .width(90)
                TableColumn("Total space") { application in
                    Text(ByteCount.string(totalSize(application, snapshot: snapshot))).monospacedDigit()
                }
                .width(110)
            }
            .navigationTitle("Applications")
        } else {
            empty("Applications", image: "square.grid.2x2")
        }
    }

    private func applications(_ snapshot: ScanSnapshot) -> [ApplicationRecord] {
        snapshot.applications.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }.sorted { totalSize($0, snapshot: snapshot) > totalSize($1, snapshot: snapshot) }
    }

    private func totalSize(_ application: ApplicationRecord, snapshot: ScanSnapshot) -> Int64 {
        application.allocatedSize + snapshot.items
            .filter { $0.ownerID == application.id }
            .reduce(0) { $0 + $1.allocatedSize }
    }
}

private extension ApplicationRecord {
    var versionOrDash: String { version ?? "—" }
}
