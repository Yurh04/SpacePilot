import SpacePilotCore
import SwiftUI

/// Read-only global Skills page grouped by explicit owner/location scope. The
/// grouping comes from Core records only; this view never infers ownership from
/// path, display name, or source strings.
struct GlobalSkillsView: View {
    let skills: [SkillRecord]
    let plugins: [PluginRecord]
    let searchText: String
    @Binding var selectedGroupID: String?
    @Binding var selection: UUID?

    private var projection: GroupedSkillsProjection {
        GroupedSkillsProjection(skills: skills, plugins: plugins)
    }

    private var selectedGroup: AIAssetGroup? {
        guard let selectedGroupID else { return nil }
        return projection.groups.first { $0.id == selectedGroupID }
    }

    private var filteredSkills: [SkillRecord] {
        guard let selectedGroupID else { return [] }
        return projection.skills(in: selectedGroupID, matching: searchText)
    }

    var body: some View {
        Group {
            if skills.isEmpty {
                ContentUnavailableView(
                    L10n.text(.aiSkillsEmpty),
                    systemImage: "sparkles"
                )
            } else if projection.groups.isEmpty {
                ContentUnavailableView(
                    L10n.text(.aiGroupEmpty),
                    systemImage: "folder.badge.questionmark"
                )
            } else {
                HSplitView {
                    groupList
                        .frame(minWidth: 150, idealWidth: 190, maxWidth: 240)
                    tableContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear(perform: resolveSelection)
        .onChange(of: projection.groups.map(\.id)) { _, _ in resolveSelection() }
        .onChange(of: selectedGroupID) { _, _ in resolveRowSelection() }
        .onChange(of: searchText) { _, _ in resolveRowSelection() }
    }

    private var groupList: some View {
        List(projection.groups, selection: $selectedGroupID) { group in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(group.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(group.itemCount.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(groupDetail(group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .tag(group.id)
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        GeometryReader { geometry in
            let layout = PluginTableLayoutMode(availableWidth: geometry.size.width)
            if selectedGroupID == nil {
                ContentUnavailableView(L10n.text(.aiGroupSelect), systemImage: "sidebar.left")
            } else if filteredSkills.isEmpty, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(L10n.text(.aiStateNoResults), systemImage: "magnifyingglass")
            } else if filteredSkills.isEmpty {
                ContentUnavailableView(L10n.text(.aiGroupNoItems), systemImage: "tray")
            } else if layout == .compact {
                compactTable
            } else {
                regularTable
            }
        }
    }

    private var compactTable: some View {
        Table(filteredSkills, selection: $selection) {
            TableColumn(L10n.text(.skill)) { skill in
                skillNameCell(skill)
            }
            TableColumn(L10n.space()) {
                Text(ByteCount.string($0.allocatedSize))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 76, ideal: 92, max: 104)
        }
        .nativeTableDoubleClickReveal(urlAtRow: urlForRow)
    }

    private var regularTable: some View {
        Table(filteredSkills, selection: $selection) {
            TableColumn(L10n.text(.skill)) { skill in
                skillNameCell(skill)
            }
            TableColumn(L10n.text(.source)) {
                Text(verbatim: L10n.name(for: $0.scope))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 96, ideal: 120, max: 140)
            TableColumn(L10n.management()) {
                Text(verbatim: L10n.name(for: $0.managementStatus))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 96, ideal: 110, max: 130)
            TableColumn(L10n.space()) {
                Text(ByteCount.string($0.allocatedSize))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 76, ideal: 92, max: 104)
        }
        .nativeTableDoubleClickReveal(urlAtRow: urlForRow)
    }

    private func skillNameCell(_ skill: SkillRecord) -> some View {
        VStack(alignment: .leading) {
            Text(skill.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(skill.url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contextMenu {
            Button(L10n.text(.revealFinder)) { FinderReveal.reveal(skill.url) }
        }
    }

    private func urlForRow(_ row: Int) -> URL? {
        filteredSkills.indices.contains(row) ? filteredSkills[row].url : nil
    }

    private func groupDetail(_ group: AIAssetGroup) -> String {
        "\(localizedDetail(group.detail)) · \(ByteCount.string(group.allocatedSize))"
    }

    private func localizedDetail(_ detail: String) -> String {
        switch detail {
        case "Global": L10n.text(.aiGroupGlobal)
        case "Project": L10n.text(.aiGroupProject)
        case "Bundled": L10n.text(.aiGroupBundled)
        case "System": L10n.text(.aiGroupSystem)
        default: L10n.text(.aiGroupUnknown)
        }
    }

    private func resolveSelection() {
        let oldSelection = selectedGroupID
        selectedGroupID = GroupedSkillsProjection.resolvedSelection(
            current: selectedGroupID,
            preferredOwnerFrom: oldSelection,
            groups: projection.groups
        )
        resolveRowSelection()
    }

    private func resolveRowSelection() {
        if let selection, filteredSkills.contains(where: { $0.id == selection }) { return }
        selection = filteredSkills.first?.id
    }
}
