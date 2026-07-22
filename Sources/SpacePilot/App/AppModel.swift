import Observation
import SpacePilotCore

@MainActor
@Observable
final class AppModel {
    var selection: NavigationDestination? = .overview
}
