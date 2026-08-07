import SpacePilotCore
import SwiftUI

/// Read-only global Plugins page. Shows every `PluginRecord` in the snapshot,
/// not just registry plugin roots. Uses an explicit regular/compact layout
/// branch and reuses the native double-click Finder reveal so single-click
/// selection stays native.
struct GlobalPluginsView: View {
    let plugins: [PluginRecord]
    let searchText: String
    @Binding var selection: UUID?

    private var filteredPlugins: [PluginRecord] {
        AISectionFilter.filterPlugins(plugins, query: searchText)
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = PluginTableLayoutMode(availableWidth: geometry.size.width)
            if plugins.isEmpty {
                // No plugins indexed at all — genuinely empty source.
                ContentUnavailableView(
                    L10n.noPluginsInstalled(),
                    systemImage: "puzzlepiece.extension"
                )
            } else if filteredPlugins.isEmpty {
                // Source has plugins, but the current query matched none.
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
        Table(filteredPlugins, selection: $selection) {
            TableColumn(L10n.text(.plugin)) { plugin in
                pluginNameCell(plugin)
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
        Table(filteredPlugins, selection: $selection) {
            TableColumn(L10n.text(.plugin)) { plugin in
                pluginNameCell(plugin)
            }
            TableColumn(L10n.version()) {
                Text($0.version ?? "—")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 64, ideal: 76, max: 88)
            TableColumn(L10n.skills()) {
                Text($0.skillCount.formatted())
                    .lineLimit(1)
            }
            .width(min: 52, ideal: 64, max: 76)
            TableColumn(L10n.space()) {
                Text(ByteCount.string($0.allocatedSize))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 76, ideal: 92, max: 104)
        }
        .nativeTableDoubleClickReveal(urlAtRow: urlForRow)
    }

    private func pluginNameCell(_ plugin: PluginRecord) -> some View {
        VStack(alignment: .leading) {
            Text(plugin.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(plugin.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contextMenu {
            Button(L10n.text(.revealFinder)) { FinderReveal.reveal(plugin.url) }
        }
    }

    private func urlForRow(_ row: Int) -> URL? {
        filteredPlugins.indices.contains(row) ? filteredPlugins[row].url : nil
    }
}
