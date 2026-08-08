import Foundation

/// The five read-only sections shown inside the Developer & AI page. Rendered as
/// a stable left-side section list (never a horizontal segmented picker, which
/// breaks under long Chinese labels / narrow windows).
enum AIManagementSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case apps
    case skills
    case plugins
    case cli

    var id: String { rawValue }

    /// SF Symbol used for the section row.
    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .apps: "sparkles.rectangle.stack"
        case .skills: "sparkles"
        case .plugins: "puzzlepiece.extension"
        case .cli: "terminal"
        }
    }
}
