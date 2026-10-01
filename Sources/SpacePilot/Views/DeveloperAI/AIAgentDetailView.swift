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
    var additionalConfigProfiles: [AgentConfigProfile] = []
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

        var systemImage: String {
            switch self {
            case .overview: "square.grid.2x2"
            case .storage: "folder"
            case .plugins: "puzzlepiece.extension"
            case .skills: "sparkles"
            }
        }

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
                .padding(AIWorkspaceLayout.pagePadding)
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, AIWorkspaceLayout.pagePadding)
            .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AIWorkspaceLayout.sectionSpacing) {
                    switch tab {
                    case .overview:
                        overviewModule
                        if !cliUpdateAssets.isEmpty { cliUpdatesModule }
                        if let configProfile, !configProfile.isEmpty { modelConfigModule(configProfile) }
                        ForEach(additionalConfigProfiles.filter { !$0.isEmpty }) { modelConfigModule($0) }
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
                .padding(AIWorkspaceLayout.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.background.secondary)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            AgentIcon(descriptor: detail.overview.icon, size: 40)
                .onDoubleClickRevealInFinder(revealURL)
                .interactiveHover(isEnabled: revealURL != nil, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.overview.displayName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(localityLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let revealURL {
                Button { FinderReveal.reveal(revealURL) } label: {
                    Label(L10n.text(.revealFinder), systemImage: "folder")
                }
            }
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
        VStack(alignment: .leading, spacing: AIWorkspaceLayout.sectionSpacing) {
            if detail.storageAvailability != .notApplicable {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                    AIMetricTile(title: L10n.text(.aiAgentStorage), value: storageTotalText, systemImage: "internaldrive")
                    AIMetricTile(title: L10n.skills(), value: detail.skills.count.formatted(), systemImage: "sparkles", tint: .purple)
                    AIMetricTile(title: L10n.plugins(), value: detail.plugins.count.formatted(), systemImage: "puzzlepiece.extension", tint: .orange)
                }
            }
            moduleCard(title: L10n.overview(), systemImage: "info.circle") {
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
                    HStack(spacing: 8) {
                        FileSystemItemIcon(url: file.url, size: AIWorkspaceLayout.fileIconSize)
                        instructionRow(file)
                    }
                    .contentShape(Rectangle())
                    .onDoubleClickRevealInFinder(file.url)
                    .interactiveHover(cornerRadius: 6)
                    .contextMenu {
                        Button(L10n.text(.revealFinder)) { FinderReveal.reveal(file.url) }
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
    }

    private func instructionRow(_ file: AgentInstructionFile) -> some View {
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

    private var cliUpdatesModule: some View {
        moduleCard(title: L10n.text(.aiUpdateSection), systemImage: "arrow.triangle.2.circlepath") {
            ForEach(cliUpdateAssets, id: \.key) { asset in
                Label(asset.displayName, systemImage: asset.key.kind == .application ? "app" : "terminal")
                    .font(.subheadline.weight(.medium))
                let result = updateResults[asset.key]
                LabeledContent(L10n.version()) {
                    Text(AIUpdateStatusPresentation.currentVersion(result, fallback: asset.localVersion.selectedVersion))
                }
                LabeledContent(L10n.text(.aiUpdateLatest)) {
                    Text(AIUpdateStatusPresentation.latestVersion(result))
                }
                if let result {
                    LabeledContent(L10n.text(.aiUpdateStatus), value: AIUpdateStatusPresentation.statusText(result))
                } else if asset.capability == nil {
                    Text(L10n.text(.aiUpdateSkipUnsupported)).font(.caption).foregroundStyle(.secondary)
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
        if asset.key.kind == .application {
            Button {
                let url = URL(fileURLWithPath: asset.key.canonicalLocation)
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            } label: {
                Label(L10n.text(.aiUpdateOpenApp), systemImage: "arrow.up.forward.app")
            }
        } else {
            Button {
                onUpdate([asset.key])
            } label: {
                Label(L10n.text(.aiUpdateSelected), systemImage: "square.and.arrow.down")
            }
            .disabled(isCheckingUpdates || isExecutingUpdates)
        }
    }

    // MARK: - Model & config module

    /// Non-secret configuration facts: pinned model, reasoning effort, and whether
    /// a credential is configured. The credential is shown as presence only —
    /// never its value — matching the privacy rule that key material is never read.
    private func modelConfigModule(_ profile: AgentConfigProfile) -> some View {
        moduleCard(title: L10n.text(.aiConfigSection), systemImage: "slider.horizontal.3") {
            evidenceRow(L10n.location(), path: profile.sourceURL.path)
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
        moduleCard(title: "\(L10n.text(.aiAgentMCP)) (\(mcpServers.count))", systemImage: "network") {
            ForEach(mcpServers) { server in
                HStack(spacing: 8) {
                    AIWorkspaceIcon(systemImage: "network", tint: .teal, size: 20)
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
                .onDoubleClickRevealInFinder(server.sourceURL)
                .interactiveHover(cornerRadius: 6)
                .contextMenu {
                    Button(L10n.text(.revealFinder)) { FinderReveal.reveal(server.sourceURL) }
                }
            }
        }
    }

    private var hooksModule: some View {
        moduleCard(title: "\(L10n.text(.aiAgentHooks)) (\(hooks.count))", systemImage: "point.3.connected.trianglepath.dotted") {
            ForEach(hooks) { hook in
                HStack(spacing: 8) {
                    AIWorkspaceIcon(systemImage: "bolt", tint: .orange, size: 20)
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
                .onDoubleClickRevealInFinder(hook.sourceURL)
                .interactiveHover(cornerRadius: 6)
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
        let url = URL(fileURLWithPath: path)
        return HStack(spacing: 8) {
            AIAssetIdentity(name: label, subtitle: path, url: url)
                .contentShape(Rectangle())
                .onDoubleClickRevealInFinder(url)
                .interactiveHover(cornerRadius: 6)
                .contextMenu {
                    Button(L10n.text(.revealFinder)) { FinderReveal.reveal(url) }
                }
            Button { FinderReveal.reveal(url) } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.text(.revealFinder))
            .help(L10n.text(.revealFinder))
        }
    }

    // MARK: - Storage module

    private var storageModule: some View {
        moduleCard(
            title: "\(L10n.text(.aiAgentStorage)) · \(detail.storageItems.count) · \(storageTotalText)",
            systemImage: "folder"
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
            FileSystemItemIcon(url: item.url, size: AIWorkspaceLayout.fileIconSize)
            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, AIWorkspaceLayout.rowPadding)
        .contentShape(Rectangle())
        .onDoubleClickRevealInFinder(item.url)
        .interactiveHover(cornerRadius: 6)
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
        return moduleCard(title: L10n.text(.aiStorageBreakdown), systemImage: "chart.bar.xaxis") {
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
        moduleCard(title: "\(L10n.plugins()) (\(detail.plugins.count))", systemImage: "puzzlepiece.extension") {
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
        moduleCard(title: L10n.skills(), systemImage: "sparkles") {
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
        HStack(alignment: .center, spacing: 8) {
            FileSystemItemIcon(url: url, size: AIWorkspaceLayout.fileIconSize)
            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, AIWorkspaceLayout.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDoubleClickRevealInFinder(url)
        .interactiveHover(cornerRadius: 6)
        .contextMenu {
            Button(L10n.text(.revealFinder)) { FinderReveal.reveal(url) }
        }
    }

    // MARK: - Shared module chrome

    private func moduleCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AIWorkspaceCard(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
    }

    private var moduleEmpty: some View {
        Label(L10n.text(.aiAgentModuleEmpty), systemImage: "tray")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 20)
    }

    private func moduleUnavailable(_ text: String) -> some View {
        Label(text, systemImage: "cloud")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 20)
    }
}
