public enum NavigationDestination: String, CaseIterable, Identifiable, Sendable {
    case overview
    case applicationCaches
    case developerTools
    case storage
    case applications
    case developerAI
    case history

    public var id: Self { self }

    public var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .applicationCaches: "internaldrive.fill"
        case .developerTools: "hammer"
        case .storage: "internaldrive"
        case .applications: "square.grid.2x2"
        case .developerAI: "sparkles.rectangle.stack"
        case .history: "clock.arrow.circlepath"
        }
    }
}
