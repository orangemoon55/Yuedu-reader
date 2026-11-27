import SwiftUI

/// Links the current track artists without requiring another navigation stack.
struct NowPlayingTrackDestinationLinks: View {
    let track: Track
    let font: Font
    let color: Color
    let onOpenDestination: (Destination) -> Void

    private var artists: [ArtistRef] {
        track.artists.filter { $0.id != 0 && !$0.name.isEmpty }
    }

    var body: some View {
        HStack(spacing: 0) {
            if artists.isEmpty {
                Text(track.artistNames)
            } else {
                ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                    if index > 0 {
                        Text(" / ")
                    }
                    Button {
                        onOpenDestination(.artist(artist.id))
                    } label: {
                        Text(artist.name)
                            .contentShape(Rectangle())
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开歌手：\(artist.name)")
                }
            }

        }
        .font(font)
        .foregroundStyle(color)
        .lineLimit(1)
        .accessibilityElement(children: .contain)
    }
}
