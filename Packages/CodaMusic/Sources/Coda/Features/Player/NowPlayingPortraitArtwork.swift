// SPDX-License-Identifier: GPL-3.0-only
// Adapted from youshen2/MeloX NowPlayingPortraitArtwork.swift at
// 09713edb847a0f0a3515a34f779cc630d4fe5985. See ThirdPartyNotices/MeloX.md.
import SwiftUI

#if os(iOS)
/// Independently implemented, steady circular artwork for the mist poster.
/// The compact lyric header keeps its rounded-square shape. No fabricated
/// rotation or playback-driven bounce is used; pausing never hides the cover.
struct NowPlayingPortraitArtwork: View {
    let image: PlatformImage?
    let isArtworkPage: Bool
    let isPlaying: Bool

    var body: some View {
        ZStack {
            Color(white: 0.15)
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: isArtworkPage ? 48 : 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: isArtworkPage ? 1000 : 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isArtworkPage ? 1000 : 12, style: .continuous)
                .strokeBorder(.white.opacity(isArtworkPage ? 0.14 : 0), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isArtworkPage ? 0.24 : 0),
                radius: isArtworkPage ? 24 : 0, y: isArtworkPage ? 12 : 0)
    }
}

struct PortraitLyricsEntranceID: Equatable {
    let expanded: Bool
    let trackID: Int?
    let prepared: Bool
}
#endif
