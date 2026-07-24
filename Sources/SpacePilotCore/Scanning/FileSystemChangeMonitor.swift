import CoreServices
import Foundation

private final class FileSystemChangeCallbackBox {
    let root: URL
    let ignoredRoots: [URL]
    let handler: FileSystemChangeMonitor.Handler

    init(
        root: URL,
        ignoredRoots: [URL],
        handler: @escaping FileSystemChangeMonitor.Handler
    ) {
        self.root = root
        self.ignoredRoots = ignoredRoots
        self.handler = handler
    }
}

private func spacePilotFileSystemEventCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIDs: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let box = Unmanaged<FileSystemChangeCallbackBox>
        .fromOpaque(info)
        .takeUnretainedValue()
    let pathArray = unsafeBitCast(eventPaths, to: CFArray.self)
    let paths = pathArray as NSArray

    var changedPaths: [URL] = []
    changedPaths.reserveCapacity(
        min(count, FileSystemChangeMonitor.maximumChangedPathsPerBatch)
    )
    var requiresFullInvalidation = false
    var lastEventID: FSEventStreamEventId = 0
    for index in 0..<count {
        let flags = eventFlags[index]
        lastEventID = max(lastEventID, eventIDs[index])
        if FileSystemChangeMonitor.requiresFullInvalidation(flags) {
            requiresFullInvalidation = true
        }
        if flags & FSEventStreamEventFlags(
            kFSEventStreamEventFlagHistoryDone
        ) == 0, index < paths.count,
           let path = paths[index] as? String {
            if changedPaths.count
                < FileSystemChangeMonitor.maximumChangedPathsPerBatch {
                changedPaths.append(URL(fileURLWithPath: path))
            } else {
                requiresFullInvalidation = true
            }
        }
    }
    let boundedID = lastEventID > FSEventStreamEventId(Int64.max)
        ? Int64.max
        : Int64(lastEventID)
    let relevantPaths = changedPaths.filter { changedPath in
        let path = changedPath.standardizedFileURL.path
        return !box.ignoredRoots.contains { ignoredRoot in
            let ignoredPath = ignoredRoot.standardizedFileURL.path
            return path == ignoredPath || path.hasPrefix(ignoredPath + "/")
        }
    }
    box.handler(FileSystemChangeBatch(
        changedPaths: ChangedPathReducer.reduce(
            relevantPaths,
            within: box.root
        ),
        lastEventID: boundedID,
        requiresFullInvalidation: requiresFullInvalidation
    ))
}

public struct FileSystemChangeBatch: Sendable {
    public let changedPaths: [URL]
    public let lastEventID: Int64
    public let requiresFullInvalidation: Bool

    public init(
        changedPaths: [URL],
        lastEventID: Int64,
        requiresFullInvalidation: Bool
    ) {
        self.changedPaths = changedPaths
        self.lastEventID = max(0, lastEventID)
        self.requiresFullInvalidation = requiresFullInvalidation
    }
}

public enum ChangedPathReducer {
    public static func reduce(_ paths: [URL], within root: URL) -> [URL] {
        let rootPath = root.standardizedFileURL.path
        let candidates = Set(paths.compactMap { url -> String? in
            let path = url.standardizedFileURL.path
            guard path == rootPath || path.hasPrefix(rootPath + "/") else {
                return nil
            }
            return path
        }).sorted {
            let lhsDepth = $0.split(separator: "/").count
            let rhsDepth = $1.split(separator: "/").count
            return lhsDepth == rhsDepth ? $0 < $1 : lhsDepth < rhsDepth
        }

        var retained: [String] = []
        for path in candidates where !retained.contains(where: {
            path == $0 || path.hasPrefix($0 + "/")
        }) {
            retained.append(path)
        }
        return retained.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }
}

public final class FileSystemChangeMonitor: @unchecked Sendable {
    public typealias Handler = @Sendable (FileSystemChangeBatch) -> Void
    public static let maximumChangedPathsPerBatch = 512

    private let root: URL
    private let ignoredRoots: [URL]
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var callbackBoxPointer: UnsafeMutableRawPointer?

    public init(
        root: URL,
        ignoredRoots: [URL] = [],
        queue: DispatchQueue = DispatchQueue(
            label: "com.yurunhao.SpacePilot.fsevents",
            qos: .utility
        )
    ) {
        self.root = root.standardizedFileURL
        self.ignoredRoots = ignoredRoots.map(\.standardizedFileURL)
        self.queue = queue
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
    }

    @discardableResult
    public func start(
        sinceEventID: Int64?,
        latency: TimeInterval = 0.8,
        handler: @escaping Handler
    ) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil else {
            return max(0, sinceEventID ?? 0)
        }

        let startingID: FSEventStreamEventId
        if let sinceEventID {
            startingID = FSEventStreamEventId(max(0, sinceEventID))
        } else {
            startingID = FSEventsGetCurrentEventId()
        }

        let boxPointer = Unmanaged.passRetained(
            FileSystemChangeCallbackBox(
                root: root,
                ignoredRoots: ignoredRoots,
                handler: handler
            )
        ).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: boxPointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard let created = FSEventStreamCreate(
            nil,
            spacePilotFileSystemEventCallback,
            &context,
            [root.path] as CFArray,
            startingID,
            latency,
            flags
        ) else {
            Unmanaged<FileSystemChangeCallbackBox>
                .fromOpaque(boxPointer)
                .release()
            throw FileSystemChangeMonitorError.couldNotCreateStream
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            Unmanaged<FileSystemChangeCallbackBox>
                .fromOpaque(boxPointer)
                .release()
            throw FileSystemChangeMonitorError.couldNotStartStream
        }
        stream = created
        callbackBoxPointer = boxPointer
        return startingID > FSEventStreamEventId(Int64.max)
            ? Int64.max
            : Int64(startingID)
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        if DispatchQueue.getSpecific(key: queueKey) == nil {
            queue.sync {}
        }
        if let callbackBoxPointer {
            Unmanaged<FileSystemChangeCallbackBox>
                .fromOpaque(callbackBoxPointer)
                .release()
            self.callbackBoxPointer = nil
        }
    }

    public static func requiresFullInvalidation(
        _ flags: FSEventStreamEventFlags
    ) -> Bool {
        let invalidatingFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagEventIdsWrapped
                | kFSEventStreamEventFlagRootChanged
        )
        return flags & invalidatingFlags != 0
    }

    public static func volumeID(for url: URL) -> String {
        if let values = try? url.resourceValues(
            forKeys: [.volumeUUIDStringKey]
        ), let uuid = values.volumeUUIDString {
            return uuid
        }
        return url.standardizedFileURL.path
    }
}

public enum FileSystemChangeMonitorError: Error {
    case couldNotCreateStream
    case couldNotStartStream
}
