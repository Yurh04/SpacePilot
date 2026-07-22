public enum AIApplicationTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case dataStorage
    case plugins
    case skills

    public var id: Self { self }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .dataStorage: "Data & Storage"
        case .plugins: "Plugins"
        case .skills: "Skills"
        }
    }
}
