import Foundation
import Observation

@MainActor @Observable
final class HomePageSettingsNavigation {
    struct Request: Identifiable { let id = UUID() }
    var request: Request?
}
