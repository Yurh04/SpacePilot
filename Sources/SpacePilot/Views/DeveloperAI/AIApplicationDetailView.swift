import AppKit
import SpacePilotCore
import SwiftUI

struct AIApplicationDetailView: View {
    let projection: AIApplicationProjection
    let queryProjection: AIApplicationQueryProjection?
    let isPreparingQuery: Bool
    let pluginDiagnostics: [String]
    @Binding var selectedTab: AIApplicationTab

    private var application: AIApplicationRecord { projection.application }
    private var applicationRevealURL: URL? {
        FinderReveal.applicationURL(for: application)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(application.name)
                    .font(.title2.weight(.semibold))
                    .onDoubleClickRevealInFinder(applicationRevealURL)
                    .contextMenu {
                        if let applicationRevealURL {
                            Button(L10n.text(.revealFinder)) {
                                FinderReveal.reveal(applicationRevealURL)
                            }
                        }
                    }
                Picker(L10n.text(.aiSection), selection: $selectedTab) {
                    ForEach(AIApplicationTab.allCases) { tab in
                        Text(verbatim: L10n.title(for: tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()
            tabContent
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            List {
                Section(L10n.text(.aiLocalFootprint)) {
                    LabeledContent(L10n.text(.aiTotalIndexedSpace), value: ByteCount.string(projection.totalSize))
                    LabeledContent(L10n.text(.aiDataItems), value: projection.dataItems.count.formatted())
                    LabeledContent(L10n.plugins(), value: projection.plugins.count.formatted())
                    LabeledContent(L10n.skillsVisible(to: application.name), value: projection.skills.count.formatted())
                }
                if !projection.storageComponents.isEmpty {
                    Section(L10n.text(.aiStorageBreakdown)) {
                        ForEach(projection.storageComponents) { component in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Label(
                                        storageName(for: component.category),
                                        systemImage: storageIcon(for: component.category)
                                    )
                                    Spacer()
                                    Text(ByteCount.string(component.allocatedSize))
                                        .monospacedDigit()
                                }
                                ProgressView(
                                    value: Double(component.allocatedSize),
                                    total: Double(max(1, projection.totalSize))
                                )
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                Section(L10n.text(.aiPrivacy)) {
                    Label(L10n.text(.aiNoContentIndexed), systemImage: "hand.raised")
                        .foregroundStyle(.secondary)
                }
            }
        case .dataStorage:
            if isPreparingQuery {
                ProgressView(L10n.text(.aiSearching))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(queryProjection?.dataItems ?? projection.dataItems) {
                    TableColumn(L10n.title(for: .dataStorage)) { item in
                        VStack(alignment: .leading) {
                            Text(item.url.lastPathComponent)
                            Text(verbatim: L10n.name(for: item.category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .onDoubleClickRevealInFinder(item.url)
                        .contextMenu { Button(L10n.text(.revealFinder)) { FinderReveal.reveal(item.url) } }
                        .accessibilityLabel("\(item.url.lastPathComponent), \(ByteCount.string(item.allocatedSize)), \(L10n.name(for: item.risk))")
                    }
                    TableColumn(L10n.risk()) { Text(verbatim: L10n.name(for: $0.risk)) }.width(120)
                    TableColumn(L10n.space()) { Text(ByteCount.string($0.allocatedSize)).monospacedDigit() }.width(100)
                }
            }
        case .plugins:
            VStack(spacing: 0) {
                HStack {
                    Text(verbatim: L10n.text(.aiPluginsManaged))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let applicationURL = application.applicationURL {
                        Button(L10n.manageIn(application.name)) {
                            NSWorkspace.shared.openApplication(
                                at: applicationURL,
                                configuration: .init()
                            )
                        }
                    }
                }
                .padding(12)
                Divider()
                if projection.plugins.isEmpty {
                    if pluginDiagnostics.isEmpty {
                        ContentUnavailableView(
                            L10n.noPluginsInstalled(),
                            systemImage: "puzzlepiece.extension"
                        )
                    } else {
                        VStack(spacing: 12) {
                            ContentUnavailableView(
                                L10n.pluginDiscoveryFailed(),
                                systemImage: "exclamationmark.triangle"
                            )
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(sanitizedDiagnosticSummaries, id: \.self) { summary in
                                    Label(summary, systemImage: "exclamationmark.circle")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                } else {
                    Table(projection.plugins) {
                        TableColumn(L10n.text(.plugin)) { plugin in
                            VStack(alignment: .leading) {
                                Text(plugin.name)
                                Text(plugin.source).font(.caption).foregroundStyle(.secondary)
                            }
                            .onDoubleClickRevealInFinder(plugin.url)
                            .contextMenu { Button(L10n.text(.revealFinder)) { FinderReveal.reveal(plugin.url) } }
                        }
                        TableColumn(L10n.version()) { Text($0.version ?? "—") }.width(90)
                        TableColumn(L10n.skills()) { Text($0.skillCount.formatted()) }.width(70)
                        TableColumn(L10n.management()) { _ in Text(verbatim: L10n.officialHandoff()) }.width(130)
                        TableColumn(L10n.space()) {
                            Text(ByteCount.string($0.allocatedSize)).monospacedDigit()
                        }
                        .width(100)
                    }
                }
            }
        case .skills:
            if isPreparingQuery {
                ProgressView(L10n.text(.aiSearching))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(queryProjection?.skills ?? projection.skills) {
                    TableColumn(L10n.text(.skill)) { skill in
                        VStack(alignment: .leading) {
                            Text(skill.name)
                            Text(skill.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .onDoubleClickRevealInFinder(skill.url)
                        .contextMenu { Button(L10n.text(.revealFinder)) { FinderReveal.reveal(skill.url) } }
                    }
                    TableColumn(L10n.text(.source)) { Text(verbatim: L10n.name(for: $0.scope)) }.width(130)
                    TableColumn(L10n.management()) { Text(verbatim: L10n.name(for: $0.managementStatus)) }.width(120)
                    TableColumn(L10n.space()) { Text(ByteCount.string($0.allocatedSize)).monospacedDigit() }.width(100)
                }
            }
        }
    }

    private var sanitizedDiagnosticSummaries: [String] {
        PluginDiagnosticPresentation.summaries(pluginDiagnostics)
    }

    private func storageIcon(for category: ItemCategory) -> String {
        switch category {
        case .application: "app.dashed"
        case .conversation: "bubble.left.and.bubble.right"
        case .cache: "arrow.trianglehead.2.clockwise.rotate.90"
        case .log: "doc.text.magnifyingglass"
        case .model: "shippingbox"
        case .plugin: "puzzlepiece.extension"
        case .skill: "sparkles"
        case .aiData: "brain"
        default: "folder"
        }
    }

    private func storageName(for category: ItemCategory) -> String {
        category == .application
            ? L10n.text(.application)
            : L10n.name(for: category)
    }
}
