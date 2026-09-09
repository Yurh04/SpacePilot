import SpacePilotCore
import SwiftUI

/// The detail pane for one selected AI Agent.
///
/// Content is split across four top tabs rather than one long scroll, because
/// the four things a user asks about an Agent are different questions:
///
/// - **Overview** — identity, version, evidence paths, global instructions,
///   coverage issues.
/// - **Storage** — the Agent's data/config roots with sizes from the snapshot.
/// - **Plugins** — plugins owned by this Agent's definition.
/// - **Skills** — split by an explicit "This Agent" / "Global" switch, since a
///   shared Skill is deletable machine-wide while an owned one is not.
///
/// MCP servers and Hooks appear under Overview: both are small, config-derived
/// lists that describe how the Agent is wired, not things it stores.
///
/// A local Agent always shows all four tabs, keeping an honest empty state when
/// one has zero items. A remote Agent shows "Not applicable" for what it does
/// not manage locally.
struct AIAgentDetailView: View {
    let detail: AIAgentDetailProjection
    let mcpServers: [MCPServerRecord]
    let hooks: [HookRecord]
    let instructionFiles: [AgentInstructionFile]
    let configProfile: AgentConfigProfile?
    let revealURL: URL?
    let formFactorLabels: [String]
    var isDiscovering = false
    var cliUpdateAssets: [AIUpdateAsset] = []
    var updateResults: [AIUpdateAssetKey: UpdateCheckResult] = [:]
    var isCheckingUpdates = false
    var isExecutingUpdates = false
    var updateError: String?
    var onCheckUpdates: (Set<AIUpdateAssetKey>) -> Void = { _ in }
    var onUpdate: (Set<AIUpdateAssetKey>) -> Void = { _ in }
    @State private var tab: Tab = .overview
    @State private var skillsScope: SkillsScope = .agent

    enum Tab: Hashable, CaseIterable {
        case overview
        case storage
        case plugins
        case skills

        var title: String {
            switch self {
            case .overview: L10n.overview()
            case .storage: L10n.text(.aiAgentStorage)
            case .plugins: L10n.plugins()
            case .skills: L10n.skills()
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding([.horizontal, .top])
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .overview:
                        overviewModule
                        if !cliUpdateAssets.isEmpty { cliUpdatesModule }
                        if let configProfile, !configProfile.isEmpty { modelConfigModule(configProfile) }
                        if !mcpServers.isEmpty { mcpModule }
                        if !hooks.isEmpty { hooksModule }
                    case .storage:
                        storageModule
                        if !detail.storageBreakdown.isEmpty { breakdownModule }
                    case .plugins:
                        pluginsModule
                    case .skills:
                        skillsModule
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                Text(AIUpdateStatusPresentation.currentVersion(
                    cliUpdateAssets.first.flatMap { updateResults[$0.key] },
                    fallback: detail.overview.detectedVersion
                ))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            LabeledContent(L10n.text(.aiAgentFormFactors)) {
                Text(formFactorLabels.isEmpty ? "—" : formFactorLabels.joined(separator: " · "))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if detail.storageAvailability != .notApplicable {
                LabeledContent(L10n.text(.aiAgentStorage), value: storageTotalText)
                LabeledContent(L10n.skills(), value: "\(detail.skills.count)")
                LabeledContent(L10n.plugins(), value: "\(detail.plugins.count)")
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
            ForEach(instructionFiles) { file in
                LabeledContent(L10n.text(.aiAgentInstructions)) {
                    VStack(alignment: .trailing, spacing: 2) {
                        // Title if the file declares one, else the file name.
                        Text(file.title ?? file.url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        // Line count is the useful number here: it says how much is
                        // being injected into every session.
                        Text(verbatim: "\(file.url.lastPathComponent) · \(file.lineCount) · \(ByteCount.string(file.allocatedSize))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !file.sections.isEmpty {
                            Text(file.sections.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                    }
                }
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

    private var cliUpdatesModule: some View {
        moduleCard(title: "\(L10n.text(.aiAgentFormCLI)) · \(L10n.text(.aiUpdateSection))") {
            ForEach(cliUpdateAssets, id: \.key) { asset in
                let result = updateResults[asset.key]
                LabeledContent(L10n.version()) {
                    Text(AIUpdateStatusPresentation.currentVersion(result, fallback: asset.localVersion.selectedVersion))
                }
                LabeledContent(L10n.text(.aiUpdateLatest)) {
                    Text(AIUpdateStatusPresentation.latestVersion(result))
                }
                if let result {
                    LabeledContent(L10n.text(.aiUpdateStatus), value: AIUpdateStatusPresentation.statusText(result))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { cliUpdateButtons(asset) }
                    VStack(alignment: .leading, spacing: 8) { cliUpdateButtons(asset) }
                }
            }
            if isCheckingUpdates { ProgressView().controlSize(.small) }
            if let updateError {
                Text(updateError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func cliUpdateButtons(_ asset: AIUpdateAsset) -> some View {
        Button {
            onCheckUpdates([asset.key])
        } label: {
            Label(L10n.text(.aiUpdateCheckNow), systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(isCheckingUpdates || isExecutingUpdates)
        Button {
            onUpdate([asset.key])
        } label: {
            Label(L10n.text(.aiUpdateSelected), systemImage: "square.and.arrow.down")
        }
        .disabled(isCheckingUpdates || isExecutingUpdates)
    }

    // MARK: - Model & config module

    /// Non-secret configuration facts: pinned model, reasoning effort, and whether
    /// a credential is configured. The credential is shown as presence only —
    /// never its value — matching the privacy rule that key material is never read.
    private func modelConfigModule(_ profile: AgentConfigProfile) -> some View {
        moduleCard(title: L10n.text(.aiConfigSection)) {
            if let model = profile.model {
                LabeledContent(L10n.text(.aiConfigModel)) {
                    Text(model).lineLimit(1).truncationMode(.tail)
                }
            }
            if let effort = profile.reasoningEffort {
                LabeledContent(L10n.text(.aiConfigReasoningEffort)) {
                    Text(effort).lineLimit(1).truncationMode(.tail)
                }
            }
            LabeledContent(L10n.text(.aiConfigCredential)) {
                Text(profile.hasCredential
                     ? L10n.text(.aiConfigCredentialConfigured)
                     : L10n.text(.aiConfigCredentialNone))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - MCP / Hooks modules

    private var mcpModule: some View {
        moduleCard(title: "\(L10n.text(.aiAgentMCP)) (\(mcpServers.count))") {
            ForEach(mcpServers) { server in
                HStack(spacing: 8) {
                    Text(server.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if !server.isEnabled {
                        // A disabled server is still installed; say so rather
                        // than hiding it.
                        Text(L10n.text(.aiMCPDisabled))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(server.transport == .unknown ? "—" : server.transport.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button(L10n.text(.revealFinder)) { FinderReveal.reveal(server.sourceURL) }
                }
            }
        }
    }

    private var hooksModule: some View {
        moduleCard(title: "\(L10n.text(.aiAgentHooks)) (\(hooks.count))") {
            ForEach(hooks) { hook in
                HStack(spacing: 8) {
                    Text(hook.event)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if !hook.providers.isEmpty {
                        Text(hook.providers.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(verbatim: "×\(hook.handlerCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button(L10n.text(.revealFinder)) { FinderReveal.reveal(hook.sourceURL) }
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
            title: "\(L10n.text(.aiAgentStorage)) · \(detail.storageItems.count) · \(storageTotalText)"
        ) {
            if isDiscovering {
                ProgressView(L10n.text(.aiOverviewDiscovering)).controlSize(.small)
            }
            if !detail.storageCoverageFailures.isEmpty {
                Text(L10n.text(.overviewLimitedCoverageDescription))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            switch detail.storageAvailability {
            case .notApplicable:
                moduleUnavailable(L10n.text(.aiAgentNotApplicable))
            case .empty:
                moduleEmpty
            case .available:
                HStack {
                    Text(L10n.location()).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.text(.category)).frame(width: 72, alignment: .leading)
                    Text(L10n.space()).frame(width: 90, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(detail.storageItems) { item in
                    storageRow(item)
                    Divider()
                }
            }
        }
    }

    private var storageTotalText: String {
        let size = ByteCount.string(detail.totalStorageSize)
        return detail.storageCoverageFailures.isEmpty ? size : "≥ \(size)"
    }

    private func storageRow(_ item: AIAgentStorageItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                Text(item.url.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                ProgressView(
                    value: Double(item.allocatedSize),
                    total: Double(max(1, detail.storageItems.map(\.allocatedSize).max() ?? 1))
                )
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.name(for: item.category))
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(item.isSizeKnown ? ByteCount.string(item.allocatedSize) : "≥ \(ByteCount.string(item.allocatedSize))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.text(.revealFinder)) { FinderReveal.reveal(item.url) }
        }
    }

    // MARK: - Space breakdown module

    /// A bar chart of the Agent's footprint by semantic category (conversations,
    /// logs, cache, model data, …). Bars are scaled to the largest category so
    /// the visual comparison is meaningful even when one category dominates.
    private var breakdownModule: some View {
        let maxSize = detail.storageBreakdown.map(\.allocatedSize).max() ?? 0
        return moduleCard(title: L10n.text(.aiStorageBreakdown)) {
            ForEach(detail.storageBreakdown) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L10n.name(for: entry.category))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(ByteCount.string(entry.allocatedSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        let fraction = maxSize > 0 ? Double(entry.allocatedSize) / Double(maxSize) : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.18))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(width: max(2, geo.size.width * fraction))
                        }
                    }
                    .frame(height: 5)
                }
            }
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
                    assetRow(name: plugin.name, url: plugin.url, allocatedSize: plugin.allocatedSize)
                }
            }
        }
    }

    // MARK: - Skills module

    /// Which skill list the module is showing. Owned skills are the default
    /// because they are what this Agent uniquely has; global skills are one click
    /// away and clearly labelled as shared.
    private enum SkillsScope: Hashable {
        case agent
        case global
    }

    private var skillsModule: some View {
        moduleCard(title: L10n.skills()) {
            Picker(L10n.text(.aiGroupScope), selection: $skillsScope) {
                Text(verbatim: L10n.aiSkillsScopeAgent(detail.skills.count)).tag(SkillsScope.agent)
                Text(verbatim: L10n.aiSkillsScopeGlobal(detail.globalSkills.count)).tag(SkillsScope.global)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 2)

            switch skillsScope {
            case .agent:
                skillsList(
                    records: detail.skills,
                    availability: detail.skillsAvailability
                )
            case .global:
                skillsList(
                    records: detail.globalSkills,
                    availability: detail.globalSkillsAvailability
                )
                if !detail.globalSkills.isEmpty {
                    Text(L10n.text(.aiSkillsGlobalNote))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func skillsList(
        records: [SkillRecord],
        availability: AIAgentModuleAvailability
    ) -> some View {
        switch availability {
        case .notApplicable:
            moduleUnavailable(L10n.text(.aiAgentNotApplicable))
        case .empty:
            moduleEmpty
        case .available:
            ForEach(records) { skill in
                assetRow(
                    name: skill.name, url: skill.url, allocatedSize: skill.allocatedSize,
                    source: detail.sourcePluginName(for: skill), symlinkTarget: skill.symlinkTarget
                )
            }
        }
    }

    private func assetRow(
        name: String, url: URL, allocatedSize: Int64,
        source: String? = nil, symlinkTarget: URL? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).lineLimit(1).truncationMode(.tail)
                if let source {
                    Label("\(L10n.text(.plugin)): \(source)", systemImage: "puzzlepiece.extension")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).help(source)
                }
                Text(url.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if let symlinkTarget {
                    Label(symlinkTarget.path, systemImage: "arrow.turn.down.right")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(symlinkTarget.path)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(ByteCount.string(allocatedSize))
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 5)
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
        .padding(.vertical, 4)
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
