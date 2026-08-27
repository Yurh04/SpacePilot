import Foundation

public enum AIUpdateAssetKind: String, Codable, Hashable, Sendable {
    case application
    case cli
    case skill
    case plugin
    case package
}

public struct AIUpdateAssetKey: Codable, Hashable, Sendable, Comparable {
    public let kind: AIUpdateAssetKind
    public let owner: AIAssetOwner
    public let canonicalLocation: String

    public init(kind: AIUpdateAssetKind, owner: AIAssetOwner, canonicalLocation: String) {
        self.kind = kind
        self.owner = owner
        self.canonicalLocation = canonicalLocation
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.owner.sortToken != rhs.owner.sortToken { return lhs.owner.sortToken < rhs.owner.sortToken }
        return lhs.canonicalLocation < rhs.canonicalLocation
    }
}

private extension AIAssetOwner {
    var sortToken: String {
        switch self {
        case .tool(let definitionID): "tool:\(definitionID)"
        case .shared: "shared"
        case .plugin(let pluginID): "plugin:\(pluginID)"
        case .unknown: "unknown"
        }
    }
}

public enum VersionEvidenceSource: String, Codable, Hashable, Sendable {
    case applicationBundle
    case cliProbe
    case packageReceipt
    case pluginManifest
    case skillManifest
}

public enum VersionEvidenceConfidence: Int, Codable, Hashable, Comparable, Sendable {
    case low = 20
    case medium = 60
    case high = 90

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct VersionEvidence: Codable, Hashable, Sendable {
    public let version: String
    public let source: VersionEvidenceSource
    public let confidence: VersionEvidenceConfidence

    public init(version: String, source: VersionEvidenceSource, confidence: VersionEvidenceConfidence) {
        self.version = version
        self.source = source
        self.confidence = confidence
    }
}

public enum LocalVersionState: Codable, Hashable, Sendable {
    case unknown
    case resolved(VersionEvidence)
    case conflict([VersionEvidence])

    public var selectedVersion: String? {
        switch self {
        case .unknown, .conflict:
            return nil
        case .resolved(let evidence):
            return evidence.version
        }
    }
}

public enum UpdateStatus: String, Codable, Hashable, Sendable {
    case unknown
    case unsupported
    case checking
    case upToDate
    case updateAvailable
    case checkFailed
}

public enum UpdateCheckFailure: String, Codable, Hashable, Sendable, Error {
    case unsupported
    case noTrustedLocalVersion
    case unknownProvider
    case invalidRequest
    case timeout
    case offline
    case rateLimited
    case invalidResponse
    case cancelled
}

public struct UpdateCheckResult: Codable, Hashable, Sendable {
    public let assetKey: AIUpdateAssetKey
    public let displayName: String
    public let localVersion: LocalVersionState
    public let latestVersion: String?
    public let status: UpdateStatus
    public let checkedAt: Date?
    public let failure: UpdateCheckFailure?

    public init(
        assetKey: AIUpdateAssetKey,
        displayName: String,
        localVersion: LocalVersionState,
        latestVersion: String?,
        status: UpdateStatus,
        checkedAt: Date?,
        failure: UpdateCheckFailure?
    ) {
        self.assetKey = assetKey
        self.displayName = displayName
        self.localVersion = localVersion
        self.latestVersion = latestVersion
        self.status = status
        self.checkedAt = checkedAt
        self.failure = failure
    }

    public static func unsupported(asset: AIUpdateAsset) -> Self {
        Self(
            assetKey: asset.key,
            displayName: asset.displayName,
            localVersion: asset.localVersion,
            latestVersion: nil,
            status: .unsupported,
            checkedAt: nil,
            failure: .unsupported
        )
    }
}

public struct UpdateCheckSummary: Codable, Hashable, Sendable {
    public let checkedAt: Date?
    public let updateAvailableCount: Int
    public let upToDateCount: Int
    public let unknownCount: Int
    public let failedCount: Int
    public let unsupportedCount: Int

    public init(results: [UpdateCheckResult]) {
        checkedAt = results.compactMap(\.checkedAt).max()
        updateAvailableCount = results.filter { $0.status == .updateAvailable }.count
        upToDateCount = results.filter { $0.status == .upToDate }.count
        unknownCount = results.filter { $0.status == .unknown }.count
        failedCount = results.filter { $0.status == .checkFailed }.count
        unsupportedCount = results.filter { $0.status == .unsupported }.count
    }

    public static let empty = UpdateCheckSummary(results: [])
}

public enum UpdateProviderKind: String, Codable, Hashable, Sendable {
    case npmRegistry
    case pypi
}

public enum VersionComparatorKind: String, Codable, Hashable, Sendable {
    case semver
}

public struct UpdateCapability: Hashable, Sendable {
    public let providerID: String
    public let providerKind: UpdateProviderKind
    public let packageIdentifier: String
    public let comparator: VersionComparatorKind
    public let allowsPrerelease: Bool

    public init(
        providerID: String,
        providerKind: UpdateProviderKind,
        packageIdentifier: String,
        comparator: VersionComparatorKind = .semver,
        allowsPrerelease: Bool = false
    ) {
        self.providerID = providerID
        self.providerKind = providerKind
        self.packageIdentifier = packageIdentifier
        self.comparator = comparator
        self.allowsPrerelease = allowsPrerelease
    }
}

public struct AIUpdateAsset: Hashable, Sendable {
    public let key: AIUpdateAssetKey
    public let displayName: String
    public let definitionID: String?
    public let localVersion: LocalVersionState
    public let capability: UpdateCapability?

    public init(
        key: AIUpdateAssetKey,
        displayName: String,
        definitionID: String?,
        localVersion: LocalVersionState,
        capability: UpdateCapability?
    ) {
        self.key = key
        self.displayName = displayName
        self.definitionID = definitionID
        self.localVersion = localVersion
        self.capability = capability
    }
}

public enum UpdateMetadataRequest: Hashable, Sendable {
    case npm(package: String)
    case pypi(package: String)

    public var providerKey: String {
        switch self {
        case .npm(let package): "npm:\(package)"
        case .pypi(let package): "pypi:\(package)"
        }
    }

    public var url: URL? {
        switch self {
        case .npm(let package):
            let encoded = package.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
            return URL(string: "https://registry.npmjs.org/\(encoded)")
        case .pypi(let package):
            let encoded = package.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? package
            return URL(string: "https://pypi.org/pypi/\(encoded)/json")
        }
    }
}

public struct UpdateMetadataResponse: Hashable, Sendable {
    public let latestVersion: String

    public init(latestVersion: String) {
        self.latestVersion = latestVersion
    }
}

public protocol UpdateMetadataFetching: Sendable {
    func fetch(_ request: UpdateMetadataRequest) async throws -> UpdateMetadataResponse
}

public struct LocalUpdateMetadataFetcher: UpdateMetadataFetching {
    private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let original = task.originalRequest?.url,
                  let target = request.url,
                  UpdateRequestValidator.isAllowedRedirect(from: original, to: target) else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    private let maximumBodyBytes: Int
    private let session: URLSession

    public init(maximumBodyBytes: Int = 256 * 1_024, timeout: TimeInterval = 5) {
        self.maximumBodyBytes = maximumBodyBytes
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["User-Agent": "SpacePilot/1 UpdateCheck"]
        self.session = URLSession(configuration: configuration, delegate: RedirectDelegate(), delegateQueue: nil)
    }

    public func fetch(_ request: UpdateMetadataRequest) async throws -> UpdateMetadataResponse {
        guard let url = request.url,
              UpdateRequestValidator.validate(url, for: request) else {
            throw UpdateCheckFailure.invalidRequest
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: urlRequest)
        } catch is CancellationError {
            throw UpdateCheckFailure.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw UpdateCheckFailure.timeout
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw UpdateCheckFailure.offline
        } catch {
            throw UpdateCheckFailure.invalidResponse
        }
        guard let http = response as? HTTPURLResponse else { throw UpdateCheckFailure.invalidResponse }
        if http.statusCode == 429 { throw UpdateCheckFailure.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw UpdateCheckFailure.invalidResponse }
        if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           !contentType.contains("json") {
            throw UpdateCheckFailure.invalidResponse
        }
        var data = Data()
        data.reserveCapacity(min(maximumBodyBytes, 16 * 1_024))
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > maximumBodyBytes {
                    throw UpdateCheckFailure.invalidResponse
                }
            }
        } catch let failure as UpdateCheckFailure {
            throw failure
        } catch is CancellationError {
            throw UpdateCheckFailure.cancelled
        } catch {
            throw UpdateCheckFailure.invalidResponse
        }
        return try Self.parse(data, request: request)
    }

    public static func parse(_ data: Data, request: UpdateMetadataRequest) throws -> UpdateMetadataResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateCheckFailure.invalidResponse
        }
        let latest: String?
        switch request {
        case .npm:
            latest = (object["dist-tags"] as? [String: Any])?["latest"] as? String
        case .pypi:
            latest = (object["info"] as? [String: Any])?["version"] as? String
        }
        guard let latest, !latest.isEmpty else { throw UpdateCheckFailure.invalidResponse }
        return UpdateMetadataResponse(latestVersion: latest)
    }
}

public enum UpdateRequestValidator {
    public static func validate(_ url: URL, for request: UpdateMetadataRequest) -> Bool {
        guard url.scheme == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              let host = url.host(percentEncoded: false),
              !isIPLiteral(host),
              !url.path(percentEncoded: false).contains("..") else {
            return false
        }
        switch request {
        case .npm(let package):
            return host == "registry.npmjs.org" && url.path(percentEncoded: false) == "/\(package)"
        case .pypi(let package):
            return host == "pypi.org" && url.path(percentEncoded: false) == "/pypi/\(package)/json"
        }
    }

    public static func isAllowedRedirect(from original: URL, to target: URL) -> Bool {
        guard original.scheme == "https",
              target.scheme == "https",
              original.host(percentEncoded: false) == target.host(percentEncoded: false),
              target.user == nil,
              target.password == nil,
              target.port == nil else {
            return false
        }
        return true
    }

    private static func isIPLiteral(_ host: String) -> Bool {
        host.contains(":") || host.allSatisfy { $0.isNumber || $0 == "." }
    }
}

public struct AIUpdateChecker: Sendable {
    private let fetcher: any UpdateMetadataFetching

    public init(fetcher: any UpdateMetadataFetching = LocalUpdateMetadataFetcher()) {
        self.fetcher = fetcher
    }

    public func check(_ assets: [AIUpdateAsset]) async -> [UpdateCheckResult] {
        var cache: [String: Result<UpdateMetadataResponse, UpdateCheckFailure>] = [:]
        var results: [UpdateCheckResult] = []
        for asset in assets.sorted(by: { $0.key < $1.key }) {
            if Task.isCancelled { break }
            guard let capability = asset.capability else {
                results.append(.unsupported(asset: asset))
                continue
            }
            guard let current = asset.localVersion.selectedVersion else {
                results.append(UpdateCheckResult(
                    assetKey: asset.key,
                    displayName: asset.displayName,
                    localVersion: asset.localVersion,
                    latestVersion: nil,
                    status: .unknown,
                    checkedAt: nil,
                    failure: .noTrustedLocalVersion
                ))
                continue
            }
            guard let request = Self.request(for: capability) else {
                results.append(failed(asset: asset, failure: .unknownProvider))
                continue
            }
            let responseResult: Result<UpdateMetadataResponse, UpdateCheckFailure>
            if let cached = cache[request.providerKey] {
                responseResult = cached
            } else {
                do {
                    let response = try await fetcher.fetch(request)
                    responseResult = .success(response)
                } catch is CancellationError {
                    responseResult = .failure(.cancelled)
                } catch let failure as UpdateCheckFailure {
                    responseResult = .failure(failure)
                } catch {
                    responseResult = .failure(.invalidResponse)
                }
                cache[request.providerKey] = responseResult
            }
            switch responseResult {
            case .success(let response):
                results.append(result(asset: asset, current: current, latest: response.latestVersion, capability: capability))
            case .failure(let failure):
                results.append(failed(asset: asset, failure: failure))
            }
        }
        return results
    }

    private static func request(for capability: UpdateCapability) -> UpdateMetadataRequest? {
        switch capability.providerKind {
        case .npmRegistry:
            guard capability.providerID == "npm" else { return nil }
            return .npm(package: capability.packageIdentifier)
        case .pypi:
            guard capability.providerID == "pypi" else { return nil }
            return .pypi(package: capability.packageIdentifier)
        }
    }

    private func result(
        asset: AIUpdateAsset,
        current: String,
        latest: String,
        capability: UpdateCapability
    ) -> UpdateCheckResult {
        let status: UpdateStatus
        switch SemVerComparator.compare(current, latest, allowsPrerelease: capability.allowsPrerelease) {
        case .orderedAscending:
            status = .updateAvailable
        case .orderedSame, .orderedDescending:
            status = .upToDate
        case nil:
            status = .unknown
        }
        return UpdateCheckResult(
            assetKey: asset.key,
            displayName: asset.displayName,
            localVersion: asset.localVersion,
            latestVersion: latest,
            status: status,
            checkedAt: .now,
            failure: nil
        )
    }

    private func failed(asset: AIUpdateAsset, failure: UpdateCheckFailure) -> UpdateCheckResult {
        UpdateCheckResult(
            assetKey: asset.key,
            displayName: asset.displayName,
            localVersion: asset.localVersion,
            latestVersion: nil,
            status: .checkFailed,
            checkedAt: .now,
            failure: failure
        )
    }
}

public enum SemVerComparator {
    public static func compare(
        _ lhs: String,
        _ rhs: String,
        allowsPrerelease: Bool = false
    ) -> ComparisonResult? {
        guard let left = SemVer(lhs), let right = SemVer(rhs) else { return nil }
        if right.prerelease != nil, left.prerelease == nil, !allowsPrerelease {
            return .orderedDescending
        }
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }

    private struct SemVer: Comparable, Equatable {
        let major: Int
        let minor: Int
        let patch: Int
        let prerelease: [String]?

        init?(_ raw: String) {
            guard raw.count <= 128 else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let withoutV = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
            let withoutBuild = withoutV.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let versionAndPrerelease = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let parts = versionAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let major = Int(parts[0]),
                  let minor = Int(parts[1]),
                  let patch = Int(parts[2]),
                  major >= 0, minor >= 0, patch >= 0 else {
                return nil
            }
            self.major = major
            self.minor = minor
            self.patch = patch
            if versionAndPrerelease.count == 2 {
                let identifiers = versionAndPrerelease[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
                guard !identifiers.isEmpty,
                      identifiers.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else {
                    return nil
                }
                prerelease = identifiers
            } else {
                prerelease = nil
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
            switch (lhs.prerelease, rhs.prerelease) {
            case (nil, nil): return false
            case (nil, _?): return false
            case (_?, nil): return true
            case let (left?, right?): return comparePrerelease(left, right) == .orderedAscending
            }
        }

        private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
            for index in 0..<max(lhs.count, rhs.count) {
                guard lhs.indices.contains(index) else { return .orderedAscending }
                guard rhs.indices.contains(index) else { return .orderedDescending }
                let left = lhs[index]
                let right = rhs[index]
                if left == right { continue }
                let leftNumber = Int(left)
                let rightNumber = Int(right)
                switch (leftNumber, rightNumber) {
                case let (l?, r?): return l < r ? .orderedAscending : .orderedDescending
                case (_?, nil): return .orderedAscending
                case (nil, _?): return .orderedDescending
                case (nil, nil): return left < right ? .orderedAscending : .orderedDescending
                }
            }
            return .orderedSame
        }
    }
}

public enum VersionEvidenceResolver {
    public static func resolve(_ evidences: [VersionEvidence]) -> LocalVersionState {
        let trusted = evidences.filter { !$0.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !trusted.isEmpty else { return .unknown }
        let highest = trusted.map(\.confidence).max() ?? .low
        let strongest = trusted.filter { $0.confidence == highest }
        let versions = Set(strongest.map(\.version))
        guard versions.count == 1, let evidence = strongest.sorted(by: { $0.source.rawValue < $1.source.rawValue }).first else {
            return .conflict(strongest.sorted { lhs, rhs in
                if lhs.version != rhs.version { return lhs.version < rhs.version }
                return lhs.source.rawValue < rhs.source.rawValue
            })
        }
        return .resolved(evidence)
    }
}
