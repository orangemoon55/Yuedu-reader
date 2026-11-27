import Foundation

/// Search metadata may span providers, but native player/write/detail actions
/// belong to the single active provider account. Fixtures are never playable.
enum CodaSearchInteractionPolicy {
    static func canUseNativePanel(source: MusicProvider, active: MusicProvider,
                                  context: MusicProvider, fixture: Bool,
                                  switching: Bool) -> Bool {
        !fixture && !switching && source == active && source == context
    }
}
