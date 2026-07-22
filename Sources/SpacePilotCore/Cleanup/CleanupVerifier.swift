import Foundation

public struct CleanupVerification: Sendable {
    public let transaction: CleanupTransaction
    public let verifiedFreedBytes: Int64
}

public struct CleanupVerifier: Sendable {
    public init() {}

    public func verify(
        transaction: CleanupTransaction,
        beforeAvailableCapacity: Int64,
        volumeRoot: URL = URL(fileURLWithPath: "/", isDirectory: true)
    ) throws -> CleanupVerification {
        let after = try VolumeScanner(root: volumeRoot).scan().availableCapacity
        return CleanupVerification(
            transaction: transaction,
            verifiedFreedBytes: max(0, after - beforeAvailableCapacity)
        )
    }
}
