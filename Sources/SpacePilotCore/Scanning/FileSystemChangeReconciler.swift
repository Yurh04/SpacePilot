import Foundation

public actor FileSystemChangeReconciler {
    public typealias Handler = @Sendable (FileSystemChangeBatch) async -> Void

    private let root: URL
    private let debounceDuration: Duration
    private let handler: Handler
    private var pendingPaths: [URL] = []
    private var pendingEventID: Int64 = 0
    private var pendingFullInvalidation = false
    private var hasPendingBatch = false
    private var scheduledFlush: Task<Void, Never>?

    public init(
        root: URL,
        debounceDuration: Duration = .seconds(4),
        handler: @escaping Handler
    ) {
        self.root = root.standardizedFileURL
        self.debounceDuration = debounceDuration
        self.handler = handler
    }

    public func submit(_ batch: FileSystemChangeBatch) {
        hasPendingBatch = true
        pendingEventID = max(pendingEventID, batch.lastEventID)
        pendingFullInvalidation = pendingFullInvalidation
            || batch.requiresFullInvalidation

        if pendingFullInvalidation {
            pendingPaths = []
        } else {
            pendingPaths = ChangedPathReducer.reduce(
                pendingPaths + batch.changedPaths,
                within: root
            )
            if pendingPaths.count
                > FileSystemChangeMonitor.maximumChangedPathsPerBatch {
                pendingPaths = []
                pendingFullInvalidation = true
            }
        }

        scheduledFlush?.cancel()
        let delay = debounceDuration
        scheduledFlush = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                await self?.flushPending()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    public func flushPending() async {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        guard hasPendingBatch else { return }

        let batch = FileSystemChangeBatch(
            changedPaths: pendingPaths,
            lastEventID: pendingEventID,
            requiresFullInvalidation: pendingFullInvalidation
        )
        pendingPaths = []
        pendingEventID = 0
        pendingFullInvalidation = false
        hasPendingBatch = false
        await handler(batch)
    }

    public func cancel() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        pendingPaths = []
        pendingEventID = 0
        pendingFullInvalidation = false
        hasPendingBatch = false
    }
}

public enum IncrementalRefreshPlanner {
    public static func scope(
        for batch: FileSystemChangeBatch,
        homeDirectory: URL
    ) -> ScanScope? {
        guard !batch.requiresFullInvalidation else { return nil }
        let home = homeDirectory.standardizedFileURL
        let developerAIRoots = [
            ".agents",
            ".codex",
            ".claude",
            ".ollama",
            ".npm/_cacache",
            ".gradle/caches",
            ".cache/pip",
            ".cache/opencode",
            ".config/opencode",
            ".local/share/opencode",
            "Library/Developer",
            "Library/Caches/Homebrew",
            "Library/Caches/pip",
            "Library/Application Support/com.openai.chat",
            "Library/Application Support/ChatGPT",
            "Library/Application Support/Ollama",
            "Library/Caches/com.openai.chat"
        ].map {
            home.appending(path: $0).standardizedFileURL.path
        }
        let applicationRoots = (
            ["Applications"] + ApplicationArtifactRoot.standard.map(\.relativePath)
        ).map {
            home.appending(path: $0).standardizedFileURL.path
        }
        let paths = batch.changedPaths.map {
            $0.standardizedFileURL.path
        }

        if paths.contains(where: { path in
            developerAIRoots.contains {
                isSameOrDescendant(path, of: $0)
            }
        }) {
            return .developerAI
        }
        if paths.contains(where: { path in
            applicationRoots.contains {
                isSameOrDescendant(path, of: $0)
            }
        }) {
            return .applications
        }
        return nil
    }

    private static func isSameOrDescendant(
        _ path: String,
        of root: String
    ) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
