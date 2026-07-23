import Foundation
import SpacePilotCore

struct CleanupSelection {
    let items: [CleanupReviewItem]
    private(set) var selectedIDs: Set<UUID> = []

    var selectedItems: [CleanupReviewItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.item.allocatedSize }
    }

    var hasSelectedSensitiveItems: Bool {
        selectedItems.contains { $0.item.risk == .sensitive }
    }

    var hasUnselectedSelectAllItems: Bool {
        items.contains {
            $0.isIncludedBySelectAll && !selectedIDs.contains($0.id)
        }
    }

    mutating func toggle(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        if !selectedIDs.insert(id).inserted {
            selectedIDs.remove(id)
        }
    }

    mutating func selectAll() {
        selectedIDs.formUnion(items.filter(\.isIncludedBySelectAll).map(\.id))
    }

    mutating func clear() {
        selectedIDs.removeAll()
    }
}
