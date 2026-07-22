import CryptoKit
import Foundation

public enum ContentFingerprint {
    public static func skill(manifestData: Data, relativeFileNames: [String]) -> String {
        var payload = manifestData
        for name in relativeFileNames.sorted() {
            payload.append(0)
            payload.append(contentsOf: name.utf8)
        }
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }
}
