import Foundation

enum MusicLyricsImportOwnership {
    /// A picker result may be attached only to the same displayed track and uninterrupted
    /// playback selection that owned the picker when it was opened.
    static func accepts(targetTrackID: String?, targetGeneration: UUID?,
                        currentTrackID: String, currentGeneration: UUID) -> Bool {
        targetTrackID == currentTrackID && targetGeneration == currentGeneration
    }
}
