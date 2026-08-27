import SpacePilotCore
import SwiftUI

/// The detail pane for one selected AI Agent. Renders four modules driven purely
/// by `AIAgentDetailProjection` (Core does the filtering/counting; this view does
/// no file-system work):
///
/// - **Overview** — identity, locality, form factors, detected version, evidence
///   paths and any coverage issues.
/// - **Data & Storage** — the Agent's fixed data/config roots with the sizes the
///   snapshot already computed (never recomputed here).
/// - **Plugins** / **Skills** — assets owned by this Agent's definition only
///   (shared assets stay in the Global pages).
///
/// A local Agent always shows all four modules, keeping an honest empty state
/// when a module has zero items. A remote Agent shows "Not applicable" for the
/// modules it does not manage locally. Double-click on a table row reveals the
/// underlying file via the native adapter; there is no per-cell tap gesture.
struct AIAgentDetailView: View {
    let detail: AIAgentDetailProjection
    let revealURL: URL?
    let formFactorLabels: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                overviewModule
                storageModule
                pluginsModule
                skillsModule
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            AgentIcon(descriptor: detail.overview.icon, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.overview.displayName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(localityLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if let revealURL {
                Button(L10n.text(.revealFinder)) { FinderReveal.reveal(revealURL) }
            }
        }
    }

    private var localityLabel: String {
        switch detail.overview.locality {
        case .local: L10n.text(.aiAgentsLocal)
        case .remote: L10n.text(.aiAgentsRemote)
        }
    }

    // MARK: - Overview module

    private var overviewModule: some View {
        moduleCard(title: L10n.overview()) {
            LabeledContent(L10n.version()) {
                Text(detail.overview.detectedVersion ?? "—")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            LabeledContent(L10n.text(.aiAgentFormFactors)) {
                Text(formFactorLabels.isEmpty ? "—" : formFactorLabels.joined(separator: " · "))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let appURL = detail.overview.applicationURL {
                evidenceRow(L10n.text(.application), path: appURL.path)
            }
            if let execURL = detail.overview.executableURL {
                evidenceRow(L10n.text(.aiAgentFormCLI), path: execURL.path)
            }
            ForEach(detail.overview.aliasExecutableURLs, id: \.self) { alias in
                evidenceRow(L10n.text(.aiCLIAliases), path: alias.path)
            }
            ForEach(sortedCoverage, id: \.self) { failure in
                LabeledContent(L10n.text(.aiOverviewDiscoveryIssue)) {
                    Text(verbatim: L10n.name(for: failure))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private var sortedCoverage: [AIToolCoverageFailure] {
        detail.overview.coverageFailures.sorted { $0.rawValue < $1.rawValue }
    }

    private func evidenceRow(_ label: String, path: String) -> some View {
        LabeledContent(label) {
            Text(path)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Storage module

    private var storageModule: some View {
        moduleCard(
            title: "\(L10n.text(.aiAgentStorage)) — \(ByteCount.string(detail.totalStorageSize))"
        ) {
            switch detail.storageAvailability {
            case .notApplicable:
                moduleUnavailable(L10n.text(.aiAgentNotApplicable))
            case .empty:
                moduleEmpty
            case .available:
                ForEach(detail.storageItems) { item in
                    storageRow(item)
                }
            }
        }
    }

    private func storageRow(_ item: AIAgentStorageItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind == .data ? "internaldrive" : "gearshape")
                .foregroundStyle(.secondary)
            Text(item.url.path)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(ByteCount.string(item.allocatedSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.text(.revealFinder)) { FinderReveal.reveal(item.url) }
        }
    }

    // MARK: - Plugins module

    private var pluginsModule: some View {
        moduleCard(title: "\(L10n.plugins()) (\(detail.plugins.count))") {
            switch detail.pluginsAvailability {
            case .notApplicable:
                moduleUnavailable(L10n.text(.aiAgentNotApplicable))
            case .empty:
                moduleEmpty
            case .available:
                ForEach(detail.plugins) { plugin in
                    assetRow(name: plugin.name, url: plugin.url)
                }
            }
        }
    }

    // MARK: - Skills module

    private var skillsModule: some View {
        moduleCard(title: "\(L10n.skills()) (\(detail.skills.count))") {
            switch detail.skillsAvailability {
            case .notApplicable:
                moduleUnavailable(L10n.text(.aiAgentNotApplicable))
            case .empty:
                moduleEmpty
            case .available:
                ForEach(detail.skills) { skill in
                    assetRow(name: skill.name, url: skill.url)
                }
            }
        }
    }

    private func assetRow(name: String, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.text(.revealFinder)) { FinderReveal.reveal(url) }
        }
    }

    // MARK: - Shared module chrome

    private func moduleCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var moduleEmpty: some View {
        Text(L10n.text(.aiAgentModuleEmpty))
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func moduleUnavailable(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
    }
}
