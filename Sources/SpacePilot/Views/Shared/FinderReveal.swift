import AppKit
import SpacePilotCore
import SwiftUI

enum FinderReveal {
    static func reveal(_ url: URL, workspace: NSWorkspace = .shared) {
        workspace.activateFileViewerSelecting([url])
    }

    static func applicationURL(for application: AIApplicationRecord) -> URL? {
        application.applicationURL ?? application.rootURLs.first
    }

    static func cleanupHistoryURL(
        resultingURL: URL?,
        sourceURL: URL?,
        fileExists: (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) -> URL? {
        if let resultingURL, fileExists(resultingURL.path) {
            return resultingURL
        }
        if let sourceURL, fileExists(sourceURL.path) {
            return sourceURL
        }
        return nil
    }
}

private struct DoubleClickRevealInFinderModifier: ViewModifier {
    let url: URL?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let url {
            content
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    FinderReveal.reveal(url)
                }
        } else {
            content
        }
    }
}

extension View {
    func onDoubleClickRevealInFinder(_ url: URL?) -> some View {
        modifier(DoubleClickRevealInFinderModifier(url: url))
    }
}
