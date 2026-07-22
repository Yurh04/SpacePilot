import AppKit
import SpacePilotCore
import SwiftUI

struct AIApplicationDetailView: View {
    let projection: AIApplicationProjection
    @Binding var selectedTab: AIApplicationTab

    private var application: AIApplicationRecord { projection.application }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(application.name)
                    .font(.title2.weight(.semibold))
                Picker("Section", selection: $selectedTab) {
                    ForEach(AIApplicationTab.allCases) { tab in
                        Text(tab.title).tag(tab)
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
                Section("Local footprint") {
                    LabeledContent("Total indexed space", value: ByteCount.string(projection.totalSize))
                    LabeledContent("Data items", value: projection.dataItems.count.formatted())
                    LabeledContent("Plugins", value: projection.plugins.count.formatted())
                    LabeledContent("Skills visible to \(application.name)", value: projection.skills.count.formatted())
                }
                Section("Privacy") {
                    Label("Conversation and log contents are not indexed.", systemImage: "hand.raised")
                        .foregroundStyle(.secondary)
                }
            }
        case .dataStorage:
            Table(projection.dataItems) {
                TableColumn("Data") { item in
                    VStack(alignment: .leading) {
                        Text(item.url.lastPathComponent)
                        Text(item.category.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu { Button("Reveal in Finder") { reveal(item.url) } }
                    .accessibilityLabel("\(item.url.lastPathComponent), \(ByteCount.string(item.allocatedSize)), \(item.risk.displayName)")
                }
                TableColumn("Risk") { Text($0.risk.displayName) }.width(120)
                TableColumn("Space") { Text(ByteCount.string($0.allocatedSize)).monospacedDigit() }.width(100)
            }
        case .plugins:
            VStack(spacing: 0) {
                HStack {
                    Text("Plugin packages are managed by their owning application.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let applicationURL = application.applicationURL {
                        Button("Manage in \(application.name)") {
                            NSWorkspace.shared.openApplication(
                                at: applicationURL,
                                configuration: .init()
                            )
                        }
                    }
                }
                .padding(12)
                Divider()
                Table(projection.plugins) {
                    TableColumn("Plugin") { plugin in
                        VStack(alignment: .leading) {
                            Text(plugin.name)
                            Text(plugin.source).font(.caption).foregroundStyle(.secondary)
                        }
                        .contextMenu { Button("Reveal in Finder") { reveal(plugin.url) } }
                    }
                    TableColumn("Version") { Text($0.version ?? "—") }.width(90)
                    TableColumn("Management") { _ in Text("Official handoff") }.width(130)
                    TableColumn("Space") { Text(ByteCount.string($0.allocatedSize)).monospacedDigit() }.width(100)
                }
            }
        case .skills:
            Table(projection.skills) {
                TableColumn("Skill") { skill in
                    VStack(alignment: .leading) {
                        Text(skill.name)
                        Text(skill.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .contextMenu { Button("Reveal in Finder") { reveal(skill.url) } }
                }
                TableColumn("Source") { Text(scopeName($0.scope)) }.width(130)
                TableColumn("Management") { Text(managementName($0.managementStatus)) }.width(120)
                TableColumn("Space") { Text(ByteCount.string($0.allocatedSize)).monospacedDigit() }.width(100)
            }
        }
    }

    private func scopeName(_ scope: SkillScope) -> String {
        switch scope {
        case .sharedAgents: "Shared"
        case .agentSpecific(let agent): agent
        case .pluginProvided: "Plugin"
        case .systemManaged: "System"
        }
    }

    private func managementName(_ status: SkillManagementStatus) -> String {
        switch status {
        case .standalone: "Standalone"
        case .parentManaged: "Plugin managed"
        case .systemReadOnly: "Read only"
        }
    }
}
