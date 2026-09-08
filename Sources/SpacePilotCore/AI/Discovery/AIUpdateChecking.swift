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
    case pep440
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
        comparator: VersionComparatorKind? = nil,
        allowsPrerelease: Bool = false
    ) {
        self.providerID = providerID
        self.providerKind = providerKind
        self.packageIdentifier = packageIdentifier
        // A pypi provider publishes PEP 440 versions (`1.2`, `2024.1`,
        // `1.0.0rc1`, `1.2.post1`), which strict SemVer cannot parse. Default the
        // comparator from the provider kind so a caller cannot forget to pair a
        // pypi provider with the right comparator, while still allowing an
        // explicit override.
        self.comparator = comparator ?? Self.defaultComparator(for: providerKind)
        self.allowsPrerelease = allowsPrerelease
    }

    private static func defaultComparator(for providerKind: UpdateProviderKind) -> VersionComparatorKind {
        switch providerKind {
        case .npmRegistry: return .semver
        case .pypi: return .pep440
        }
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
        switch VersionComparator.compare(
            current, latest,
            kind: capability.comparator,
            allowsPrerelease: capability.allowsPrerelease
        ) {
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

/// Compares two version strings under a named version scheme. This is the single
/// entry point the update pipeline uses so that a pypi package is never compared
/// with strict SemVer (which rejects `1.2`, `2024.1`, `1.0.0rc1`, ...). Returns
/// `nil` when either side is unparseable under the chosen scheme.
public enum VersionComparator {
    public static func compare(
        _ lhs: String,
        _ rhs: String,
        kind: VersionComparatorKind,
        allowsPrerelease: Bool = false
    ) -> ComparisonResult? {
        switch kind {
        case .semver:
            return SemVerComparator.compare(lhs, rhs, allowsPrerelease: allowsPrerelease)
        case .pep440:
            return PEP440Comparator.compare(lhs, rhs, allowsPrerelease: allowsPrerelease)
        }
    }

    /// Whether a single version string parses under the chosen scheme. Used to
    /// validate a probed/latest version before it is trusted as a target.
    public static func isValid(_ version: String, kind: VersionComparatorKind) -> Bool {
        compare(version, version, kind: kind) != nil
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

/// A pragmatic PEP 440 comparator covering the release forms real PyPI packages
/// publish: an arbitrary-length release segment (`1`, `1.2`, `2024.1.0`), an
/// optional epoch (`1!2.0`), and the pre/post/dev suffixes (`1.0rc1`,
/// `1.2.post1`, `1.0.dev3`), with or without separators. It intentionally does
/// not implement local versions (`+local`) for ordering — the build metadata is
/// ignored, matching SemVer's behaviour here — but such versions still parse.
public enum PEP440Comparator {
    public static func compare(
        _ lhs: String,
        _ rhs: String,
        allowsPrerelease: Bool = false
    ) -> ComparisonResult? {
        guard let left = PEP440(lhs), let right = PEP440(rhs) else { return nil }
        // A pre-release (`rcN`/`aN`/`bN`) or dev release is "less than" the
        // corresponding final release. Mirror SemVer's policy: unless the caller
        // opts in, treat "newer only as a pre-release" as not an upgrade.
        if right.isPreOrDev, !left.isPreOrDev, !allowsPrerelease {
            return .orderedDescending
        }
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }

    struct PEP440: Comparable, Equatable {
        let epoch: Int
        let release: [Int]
        /// Ordering rank of the pre-release phase: dev(-3) < alpha(-2) <
        /// beta(-1) < rc(0) < final(1) < post(2). Combined with `phaseNumber`.
        let phase: Int
        let phaseNumber: Int
        let devNumber: Int?

        var isPreOrDev: Bool { phase < 1 || devNumber != nil }

        init?(_ raw: String) {
            guard raw.count <= 128 else { return nil }
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !text.isEmpty else { return nil }
            if text.hasPrefix("v") { text.removeFirst() }

            // Epoch: "N!rest".
            var epoch = 0
            if let bang = text.firstIndex(of: "!") {
                guard let value = Int(text[text.startIndex..<bang]), value >= 0 else { return nil }
                epoch = value
                text = String(text[text.index(after: bang)...])
            }

            // Local version segment ("+local") is ignored for ordering.
            if let plus = text.firstIndex(of: "+") {
                text = String(text[text.startIndex..<plus])
            }

            // Split the release from any pre/post/dev suffix. The release is the
            // leading run of dot-separated integers; the remainder is the suffix.
            var releasePart = text
            var suffix = ""
            if let boundary = text.firstIndex(where: { !($0.isNumber || $0 == ".") }) {
                releasePart = String(text[text.startIndex..<boundary])
                suffix = String(text[boundary...])
            }
            releasePart = releasePart.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let releaseTokens = releasePart.split(separator: ".", omittingEmptySubsequences: false)
            guard !releaseTokens.isEmpty else { return nil }
            var release: [Int] = []
            for token in releaseTokens {
                guard let value = Int(token), value >= 0 else { return nil }
                release.append(value)
            }

            self.epoch = epoch
            self.release = release

            guard let parsed = Self.parseSuffix(suffix) else { return nil }
            self.phase = parsed.phase
            self.phaseNumber = parsed.phaseNumber
            self.devNumber = parsed.devNumber
        }

        /// Parses the pre/post/dev suffix. Accepts optional separators
        /// (`.`, `-`, `_`) and the usual spellings: a/alpha, b/beta, c/rc/pre/preview,
        /// post/rev/r, dev. Returns `nil` on anything unrecognised so a malformed
        /// version does not masquerade as a valid one.
        private static func parseSuffix(_ raw: String) -> (phase: Int, phaseNumber: Int, devNumber: Int?)? {
            var remainder = raw
            var devNumber: Int?

            // Extract a trailing ".devN" (or "devN") first; it can follow any phase.
            if let devRange = remainder.range(of: "dev") {
                let before = String(remainder[remainder.startIndex..<devRange.lowerBound])
                let after = String(remainder[devRange.upperBound...])
                let trimmedNumber = after.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
                if trimmedNumber.isEmpty {
                    devNumber = 0
                } else if let value = Int(trimmedNumber), value >= 0 {
                    devNumber = value
                } else {
                    return nil
                }
                remainder = before.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
            }

            if remainder.isEmpty {
                // Pure release, optionally with a dev segment. A ".devN" with no
                // pre/post phase ranks below the final release.
                return (devNumber == nil ? 1 : -3, 0, devNumber)
            }

            let normalized = remainder.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
            for (tokens, phase) in Self.phaseSpellings {
                for token in tokens where normalized.hasPrefix(token) {
                    let numberText = String(normalized.dropFirst(token.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
                    let number = numberText.isEmpty ? 0 : Int(numberText)
                    guard numberText.isEmpty || number != nil, (number ?? 0) >= 0 else { return nil }
                    return (phase, number ?? 0, devNumber)
                }
            }
            return nil
        }

        /// Longest spellings first so `alpha` is matched before `a`, etc.
        private static let phaseSpellings: [(tokens: [String], phase: Int)] = [
            (["alpha", "a"], -2),
            (["beta", "b"], -1),
            (["preview", "pre", "rc", "c"], 0),
            (["post", "rev", "r"], 2)
        ]

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.epoch != rhs.epoch { return lhs.epoch < rhs.epoch }
            // Compare release components, treating a missing component as 0 so
            // `1.2` == `1.2.0`.
            let count = max(lhs.release.count, rhs.release.count)
            for index in 0..<count {
                let left = index < lhs.release.count ? lhs.release[index] : 0
                let right = index < rhs.release.count ? rhs.release[index] : 0
                if left != right { return left < right }
            }
            if lhs.phase != rhs.phase { return lhs.phase < rhs.phase }
            if lhs.phaseNumber != rhs.phaseNumber { return lhs.phaseNumber < rhs.phaseNumber }
            // A dev release precedes the same phase without one.
            switch (lhs.devNumber, rhs.devNumber) {
            case (nil, nil): return false
            case (_?, nil): return true
            case (nil, _?): return false
            case let (l?, r?): return l < r
            }
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            guard lhs.epoch == rhs.epoch, lhs.phase == rhs.phase,
                  lhs.phaseNumber == rhs.phaseNumber, lhs.devNumber == rhs.devNumber else {
                return false
            }
            let count = max(lhs.release.count, rhs.release.count)
            for index in 0..<count {
                let left = index < lhs.release.count ? lhs.release[index] : 0
                let right = index < rhs.release.count ? rhs.release[index] : 0
                if left != right { return false }
            }
            return true
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
