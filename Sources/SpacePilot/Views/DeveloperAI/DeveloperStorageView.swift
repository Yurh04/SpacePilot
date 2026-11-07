import Foundation
import SpacePilotCore
import SwiftUI

/// Global development caches plus read-only Simulator inventory. Rebuildable
/// cache rows start unselected. Simulator devices and runtimes are intentionally
/// inventory-only because Apple's supported removal route is permanent rather
/// than a move to Trash.
struct DeveloperStorageView: View {
    let projection: DeveloperStorageProjection?
    let searchText: String
    let scan: () -> Void
    let reviewCleanup: ([ScannedItem]) -> Void

    @State private var selectedItemIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            AIWorkspaceHeader(
                title: L10n.text(.developerToolsTitle),
                systemImage: "hammer",
                subtitle: L10n.text(.developerToolsSubtitle),
                count: projection?.items.count ?? 0
            )

            HStack(spacing: 12) {
                Label(L10n.text(.developerToolsCheckFirst), systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Spacer()
                Button(L10n.text(.developerToolsScan), systemImage: "arrow.clockwise", action: scan)
            }
            .padding(.horizontal, AIWorkspaceLayout.pagePadding)
            .padding(.bottom, 10)

            if displayRows.isEmpty {
                ContentUnavailableView(
                    L10n.text(.developerToolsEmpty),
                    systemImage: "hammer",
                    description: Text(verbatim: L10n.text(.developerToolsEmptyDescription))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(displayRows) { row in
                    switch row {
                    case .header(let section, let count, let bytes):
                        sectionHeader(section, count: count, bytes: bytes)
                            .selectionDisabled()
                    case .item(let item):
                        itemRow(item)
                    }
                }
                .listStyle(.inset)
                .nativeTableHoverHighlight { index in
                    displayRows.indices.contains(index) && displayRows[index].isItem
                }
            }

            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: projectionSignature) { _, _ in selectedItemIDs.removeAll() }
    }

    @ViewBuilder
    private func itemRow(_ item: ScannedItem) -> some View {
        HStack(spacing: 10) {
            if item.cleanupPolicyScope == .developerStorage {
                Toggle("", isOn: selectionBinding(for: item.id))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            } else {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityLabel(L10n.text(.developerToolsManagedInXcode))
            }
            AIAssetIdentity(
                name: title(for: item),
                subtitle: subtitle(for: item),
                url: item.url
            )
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteCount.string(item.allocatedSize))
                    .fontWeight(.medium)
                    .monospacedDigit()
                Text(verbatim: trailingStatus(for: item))
                    .font(.caption)
                    .foregroundStyle(item.cleanupPolicyScope == .developerStorage ? .orange : .secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDoubleClickRevealInFinder(item.url)
        .contextMenu {
            Button(L10n.text(.revealFinder)) { FinderReveal.reveal(item.url) }
        }
    }

    private func sectionHeader(
        _ section: DeveloperStorageItemKind,
        count: Int,
        bytes: Int64
    ) -> some View {
        HStack(spacing: 8) {
            Label(sectionTitle(section), systemImage: sectionImage(section))
                .font(.headline)
            Text(verbatim: "\(count)")
                .foregroundStyle(.secondary)
            Spacer()
            Text(ByteCount.string(bytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if section != .toolCache {
                Text(verbatim: L10n.text(.developerToolsManagedInXcode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    private var filteredItems: [ScannedItem] {
        let items = projection?.items ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            title(for: $0).localizedCaseInsensitiveContains(query)
                || subtitle(for: $0).localizedCaseInsensitiveContains(query)
                || $0.url.path.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayRows: [DeveloperStorageDisplayRow] {
        DeveloperStorageItemKind.allDisplayCases.flatMap {
            kind -> [DeveloperStorageDisplayRow] in
            let items = filteredItems.filter {
                $0.developerStorageMetadata?.kind == kind
            }
            guard !items.isEmpty else { return [] }
            let bytes = items.reduce(Int64(0)) { $0 + $1.allocatedSize }
            return [.header(kind, items.count, bytes)] + items.map {
                .item($0)
            }
        }
    }

    private var selectedItems: [ScannedItem] {
        (projection?.items ?? []).filter {
            $0.cleanupPolicyScope == .developerStorage
                && selectedItemIDs.contains($0.id)
        }
    }

    private var actionBar: some View {
        let selected = selectedItems
        let bytes = selected.reduce(Int64(0)) { $0 + $1.allocatedSize }
        return HStack {
            Text(verbatim: L10n.selectedItems(
                selected.count,
                space: bytes == 0 ? "0 KB" : ByteCount.string(bytes)
            ))
            .font(.headline)
            .monospacedDigit()
            Spacer()
            Button(L10n.text(.cleanupClearSelection)) { selectedItemIDs.removeAll() }
                .disabled(selected.isEmpty)
            Button(L10n.text(.developerToolsReview), systemImage: "trash") {
                reviewCleanup(selected)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
        .padding(AIWorkspaceLayout.pagePadding)
    }

    private func title(for item: ScannedItem) -> String {
        guard let metadata = item.developerStorageMetadata else {
            return L10n.explanation(item.explanation)
        }
        switch metadata.kind {
        case .toolCache:
            return L10n.developerToolName(
                relativePath: item.cleanupPolicyRelativePath,
                fallback: item.explanation
            )
        case .simulatorDevice:
            guard let version = metadata.runtimeVersion else { return metadata.name }
            return "\(metadata.name) · \(runtimePlatform(metadata.runtimeIdentifier)) \(version)"
        case .simulatorRuntime:
            return L10n.developerSimulatorRuntimeName(
                platform: metadata.name,
                version: metadata.runtimeVersion ?? ""
            )
        }
    }

    private func subtitle(for item: ScannedItem) -> String {
        guard let metadata = item.developerStorageMetadata,
              metadata.kind != .toolCache else { return item.url.path }
        var components: [String] = []
        if let state = metadata.state {
            components.append(L10n.developerSimulatorState(state))
        }
        if metadata.kind == .simulatorRuntime,
           let build = metadata.buildVersion {
            components.append(L10n.developerSimulatorBuild(build))
        }
        if let date = metadata.lastUsedDate {
            let relative = RelativeDateTimeFormatter().localizedString(
                for: date,
                relativeTo: .now
            )
            components.append(L10n.developerSimulatorLastUsed(relative))
        }
        if metadata.isInUse == true {
            components.append(L10n.text(.developerSimulatorInUse))
        }
        return components.isEmpty ? item.url.path : components.joined(separator: " · ")
    }

    private func trailingStatus(for item: ScannedItem) -> String {
        item.cleanupPolicyScope == .developerStorage
            ? L10n.name(for: item.risk)
            : L10n.text(.developerToolsManagedInXcode)
    }

    private func runtimePlatform(_ identifier: String?) -> String {
        guard let identifier,
              let marker = identifier.range(of: ".SimRuntime.") else {
            return L10n.text(.developerSimulatorGeneric)
        }
        return String(identifier[marker.upperBound...].split(separator: "-").first ?? "Simulator")
    }

    private func sectionTitle(_ section: DeveloperStorageItemKind) -> String {
        switch section {
        case .toolCache: L10n.text(.developerToolsSectionCaches)
        case .simulatorDevice: L10n.text(.developerToolsSectionDevices)
        case .simulatorRuntime: L10n.text(.developerToolsSectionRuntimes)
        }
    }

    private func sectionImage(_ section: DeveloperStorageItemKind) -> String {
        switch section {
        case .toolCache: "hammer"
        case .simulatorDevice: "iphone.gen3"
        case .simulatorRuntime: "internaldrive"
        }
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedItemIDs.contains(id) },
            set: { selected in
                if selected { selectedItemIDs.insert(id) }
                else { selectedItemIDs.remove(id) }
            }
        )
    }

    private var projectionSignature: String {
        (projection?.items ?? []).map { "\($0.id.uuidString):\($0.allocatedSize)" }
            .joined(separator: "|")
    }
}

private enum DeveloperStorageDisplayRow: Identifiable {
    case header(DeveloperStorageItemKind, Int, Int64)
    case item(ScannedItem)

    var id: String {
        switch self {
        case .header(let kind, _, _): "header:\(kind.rawValue)"
        case .item(let item): "item:\(item.id.uuidString)"
        }
    }

    var isItem: Bool {
        if case .item = self { return true }
        return false
    }
}

private extension DeveloperStorageItemKind {
    static let allDisplayCases: [Self] = [
        .toolCache, .simulatorDevice, .simulatorRuntime
    ]
}
