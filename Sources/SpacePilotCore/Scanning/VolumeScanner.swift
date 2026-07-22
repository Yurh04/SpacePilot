import Foundation

public struct VolumeScanner: Sendable {
    public let root: URL

    public init(root: URL = URL(fileURLWithPath: "/", isDirectory: true)) {
        self.root = root
    }

    public func scan() throws -> VolumeRecord {
        let values = try root.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeRecord(
            url: root,
            name: values.volumeName ?? "Macintosh HD",
            totalCapacity: total,
            availableCapacity: max(0, min(total, available))
        )
    }
}
