import Foundation

enum AppPresentationMode: String, CaseIterable, Identifiable {
    case window
    case dynamicIsland

    static let defaultsKey = "appPresentationMode"

    var id: String { rawValue }

    static var current: Self {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let mode = Self(rawValue: rawValue) else {
            return .window
        }
        return mode
    }

    static func select(_ mode: Self) {
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
        NotificationCenter.default.post(
            name: .spacePilotPresentationModeDidChange,
            object: mode.rawValue
        )
    }
}

extension Notification.Name {
    static let spacePilotPresentationModeDidChange = Notification.Name(
        "SpacePilot.presentationModeDidChange"
    )
}
