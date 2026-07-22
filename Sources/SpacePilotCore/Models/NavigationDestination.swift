public enum NavigationDestination: String, CaseIterable, Identifiable, Sendable {
    case overview
    case storage
    case applications
    case developerAI
    case history

    public var id: Self { self }

    public var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .storage: "internaldrive"
        case .applications: "square.grid.2x2"
        case .developerAI: "sparkles.rectangle.stack"
        case .history: "clock.arrow.circlepath"
        }
    }
}
