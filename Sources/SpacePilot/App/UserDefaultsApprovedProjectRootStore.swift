import Foundation
import SpacePilotCore

struct UserDefaultsApprovedProjectRootStore: ApprovedProjectRootStoring {
    private final class DefaultsBox: @unchecked Sendable {
        let defaults: UserDefaults

        init(_ defaults: UserDefaults) {
            self.defaults = defaults
        }
    }

    private struct Payload: Codable {
        let version: Int
        let roots: [ApprovedProjectRoot]
    }

    private let defaultsBox: DefaultsBox
    private let key: String
    private let validator = ApprovedProjectRootValidator()

    init(
        defaults: UserDefaults = .standard,
        key: String = "SpacePilot.ApprovedProjectRoots.v1"
    ) {
        self.defaultsBox = DefaultsBox(defaults)
        self.key = key
    }

    func load() throws -> ApprovedProjectRootValidationResult {
        guard let data = defaultsBox.defaults.data(forKey: key) else {
            return ApprovedProjectRootValidationResult(roots: [], issues: [])
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.version == 1 else {
                return ApprovedProjectRootValidationResult(roots: [], issues: [.invalidPayload])
            }
            return validator.validateStored(payload.roots)
        } catch {
            return ApprovedProjectRootValidationResult(roots: [], issues: [.invalidPayload])
        }
    }

    func replace(_ roots: [ApprovedProjectRoot]) throws {
        let payload = Payload(version: 1, roots: roots)
        let data = try JSONEncoder().encode(payload)
        defaultsBox.defaults.set(data, forKey: key)
    }
}
