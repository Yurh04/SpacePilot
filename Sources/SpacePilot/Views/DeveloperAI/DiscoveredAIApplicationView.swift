import SpacePilotCore
import SwiftUI

/// Read-only detail for an application discovered by the `AIToolRegistry` that
/// does not yet have a deep-scan projection. It surfaces the evidence and any
/// coverage failures honestly; it performs no writes and triggers no probes.
struct DiscoveredAIApplicationView: View {
    let application: AIApplicationJoin.RegistryOnlyApplication
    let updateResult: UpdateCheckResult?

    var body: some View {
        List {
            Section {
                if let bundleIdentifier = application.bundleIdentifier {
                    LabeledContent(L10n.text(.application), value: bundleIdentifier)
                }
                if let version = application.detectedVersion {
                    LabeledContent(L10n.version(), value: version)
                }
                LabeledContent(
                    L10n.text(.aiUpdateLatest),
                    value: AIUpdateStatusPresentation.latestVersion(updateResult)
                )
                LabeledContent(
                    L10n.text(.aiUpdateStatus),
                    value: AIUpdateStatusPresentation.statusText(updateResult)
                )
                LabeledContent(
                    L10n.text(.source),
                    value: AIUpdateStatusPresentation.evidenceText(updateResult)
                )
                if let url = application.applicationURL {
                    LabeledContent(L10n.location()) {
                        Text(url.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .onDoubleClickRevealInFinder(url)
                    .contextMenu {
                        Button(L10n.text(.revealFinder)) { FinderReveal.reveal(url) }
                    }
                }
            } header: {
                Text(application.displayName)
            }
            if !application.coverageFailures.isEmpty {
                Section(L10n.text(.aiOverviewPartialCoverage)) {
                    ForEach(application.coverageFailures, id: \.self) { failure in
                        Label(
                            L10n.name(for: failure),
                            systemImage: "exclamationmark.circle"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
