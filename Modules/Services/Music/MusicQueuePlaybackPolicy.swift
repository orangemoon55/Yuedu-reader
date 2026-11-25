import Foundation

/// Keep AVQueuePlayer at .pause boundaries; only the current item may drive a transition.
enum MusicQueuePlaybackPolicy {
    enum EndAction: Equatable { case ignore, repeatCurrent, advance, finish }

    static func endAction(isCurrentItem: Bool, repeatsCurrent: Bool, hasNext: Bool) -> EndAction {
        guard isCurrentItem else { return .ignore }
        if repeatsCurrent { return .repeatCurrent }
        return hasNext ? .advance : .finish
    }

    static func nextIndex(after index: Int, itemCount: Int) -> Int? {
        guard index >= 0, index + 1 < itemCount else { return nil }
        return index + 1
    }
}
