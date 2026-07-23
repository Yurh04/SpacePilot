import Foundation
import SpacePilotCore

struct CleanupSelection {
    let items: [ScannedItem]
    private(set) var selectedIDs: Set<UUID> = []

    var selectedItems: [ScannedItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.allocatedSize }
    }

    var hasSelectedSensitiveItems: Bool {
        selectedItems.contains { $0.risk == .sensitive }
    }

    mutating func toggle(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        if !selectedIDs.insert(id).inserted {
            selectedIDs.remove(id)
        }
    }

    mutating func selectAll() {
        selectedIDs = Set(items.map(\.id))
    }

    mutating func clear() {
        selectedIDs.removeAll()
    }
}
