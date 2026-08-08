import SpacePilotCore
import SwiftUI

/// Read-only global Skills page. Shows every `SkillRecord` in the snapshot,
/// including shared and unowned records — not just registry skill roots. Uses an
/// explicit regular/compact layout branch and reuses the native double-click
/// Finder reveal so single-click selection stays native.
struct GlobalSkillsView: View {
    let skills: [SkillRecord]
    let searchText: String
    @Binding var selection: UUID?

    private var filteredSkills: [SkillRecord] {
        AISectionFilter.filterSkills(skills, query: searchText)
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = PluginTableLayoutMode(availableWidth: geometry.size.width)
            if skills.isEmpty {
                // No skills indexed at all — genuinely empty source.
                ContentUnavailableView(
                    L10n.text(.aiSkillsEmpty),
                    systemImage: "sparkles"
                )
            } else if filteredSkills.isEmpty {
                // Source has skills, but the current query matched none.
                ContentUnavailableView(
                    L10n.text(.aiStateNoResults),
                    systemImage: "magnifyingglass"
                )
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
}
