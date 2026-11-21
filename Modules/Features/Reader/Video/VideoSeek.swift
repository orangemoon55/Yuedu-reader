/// Shared by the player's absolute seek and its relative transport buttons, so every target
/// handed to AVPlayer is finite and inside the current episode's seekable span.
enum VideoSeek {
    static let transportSeconds: Double = 15

    static func target(_ seconds: Double, in range: ClosedRange<Double>?) -> Double? {
        guard seconds.isFinite, let range,
              range.lowerBound.isFinite, range.upperBound.isFinite,
              range.upperBound > range.lowerBound else { return nil }
        return min(max(seconds, range.lowerBound), range.upperBound)
    }

    /// Move from the window's edge if live playback has run past it, as a scrub does. A live
    /// stream without a window, an unknown position, or a non-finite offset is a safe no-op.
    static func target(from currentTime: Double, by seconds: Double,
                       in range: ClosedRange<Double>?) -> Double? {
        guard seconds.isFinite, let range,
              let start = target(currentTime, in: range) else { return nil }
        // The sum may overflow for a finite but extreme offset; clamp it before AVPlayer sees it.
        return min(max(start + seconds, range.lowerBound), range.upperBound)
    }
}
