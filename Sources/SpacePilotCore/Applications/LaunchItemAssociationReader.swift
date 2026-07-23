import Foundation

public struct LaunchItemAssociationReader: Sendable {
    public init() {}

    public func targetURLs(in plistURL: URL) -> [URL] {
        guard let data = try? Data(contentsOf: plistURL),
              let value = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ),
              let dictionary = value as? [String: Any]
        else {
            return []
        }
        let program = dictionary["Program"] as? String
        let firstArgument = (
            dictionary["ProgramArguments"] as? [String]
        )?.first
        return [program, firstArgument]
            .compactMap { $0 }
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
    }
}
