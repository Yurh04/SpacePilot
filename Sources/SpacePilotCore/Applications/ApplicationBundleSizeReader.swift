import CoreServices
import Foundation

/// Keep Finder's logical size separate from disk allocation. Spotlight supplies
/// both without walking large bundles; unindexed bundles use the complete walker.
enum ApplicationBundleSizeReader {
    static func sizes(of url: URL) throws -> ApplicationArtifactSize {
        try Task.checkCancellation()
        if let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
           let logical = MDItemCopyAttribute(item, "kMDItemLogicalSize" as CFString) as? NSNumber,
           let allocated = MDItemCopyAttribute(item, "kMDItemPhysicalSize" as CFString) as? NSNumber,
           logical.int64Value > 0, allocated.int64Value > 0 {
            return ApplicationArtifactSize(logical: logical.int64Value, allocated: allocated.int64Value)
        }
        return try FileSystemApplicationArtifactSizeResolver.calculateSizes(of: url)
    }
}
