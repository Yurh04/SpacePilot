import AppKit
import SwiftUI

@MainActor
private final class FileIconCache {
    static let shared = FileIconCache()
    private let images: NSCache<NSString, NSImage>

    private init() {
        images = NSCache()
        images.countLimit = 512
    }

    func image(for url: URL) -> NSImage {
        let key = url.standardizedFileURL.path as NSString
        if let image = images.object(forKey: key) {
            return image
        }
        let image = NSWorkspace.shared.icon(forFile: key as String)
        images.setObject(image, forKey: key)
        return image
    }
}

struct FileSystemItemIcon: View {
    let url: URL
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: FileIconCache.shared.image(for: url))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
