import Foundation

/// Keep AVQueuePlayer at .pause boundaries; only the current item may drive a transition.
enum MusicQueuePlaybackPolicy {
    enum EndAction: Equatable { case ignore, repeatCurrent, advance, finish }
    enum PreviousAction: Equatable { case restart, back }

    static func previousAction(elapsed: TimeInterval, hasPrevious: Bool) -> PreviousAction {
        elapsed > YingxiaMusicQueue<MediaHubLibraryItem>.restartThreshold || !hasPrevious ? .restart : .back
    }

    /// Identity alone cannot reject a late seek/notification after reselecting the same item.
    /// Every replacement, seek and stop invalidates the captured generation. A terminal event
    /// (EOF or failure) may be consumed only once, even when notification and status polling race.
    struct ItemEvents {
        private(set) var generation: UInt64 = 0
        private var terminalEventHandled = false

        mutating func invalidate() {
            generation &+= 1
            terminalEventHandled = false
        }

        func accepts(_ generation: UInt64, isCurrentItem: Bool) -> Bool {
            isCurrentItem && generation == self.generation
        }

        mutating func consumeTerminalEvent(_ generation: UInt64, isCurrentItem: Bool) -> Bool {
            guard accepts(generation, isCurrentItem: isCurrentItem), !terminalEventHandled else { return false }
            terminalEventHandled = true
            return true
        }
    }

    static func endAction(isCurrentItem: Bool, repeatsCurrent: Bool, hasNext: Bool) -> EndAction {
        guard isCurrentItem else { return .ignore }
        if repeatsCurrent { return .repeatCurrent }
        return hasNext ? .advance : .finish
    }

    static func nextIndex(after index: Int, itemCount: Int) -> Int? {
        guard index >= 0, itemCount > 0, index < itemCount - 1 else { return nil }
        return index + 1
    }
}
