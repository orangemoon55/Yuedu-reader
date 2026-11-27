// SPDX-License-Identifier: GPL-3.0-only
// From youshen2/MeloX a41ea0e1e1fa69fb543d827b853fe3aff5420951.
import Foundation

enum LyricVocalDurationEstimator {
    /// LRC has no content-end timestamp. Keep its display duration intact for
    /// lyric highlighting while estimating a conservative sung-content tail
    /// for detecting a following instrumental gap.
    static func estimatedDuration(for text: String) -> TimeInterval {
        let visibleCharacterCount = text.filter { !$0.isWhitespace }.count
        return min(max(Double(visibleCharacterCount) * 0.32, 2), 8)
    }
}
