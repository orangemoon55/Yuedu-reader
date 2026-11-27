import SwiftUI

/// The iPad queue shares the player's backdrop and replaces its lyric column.
/// There is no navigation container, sheet chrome, or separate background.
struct IOSInlinePlaybackQueueView: View {
    @EnvironmentObject private var player: PlayerService
    @Environment(\.nowPlayingFlushPanelEdges) private var flushPanelEdges
    @State private var rows: [InlineQueueItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.component) {
            HStack(alignment: .center, spacing: Theme.Spacing.small) {
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text("待播清单")
                        .font(Theme.Typography.sectionTitle.weight(.bold))
                    Text("\(player.upcomingTracks.count) 首歌曲")
                        .font(Theme.Typography.secondary.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, flushPanelEdges ? 0 : Theme.Spacing.small)

            List {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    inlineRow(item.track, upcomingIndex: index)
                        .listRowInsets(EdgeInsets(top: 7, leading: flushPanelEdges ? 0 : 8, bottom: 7, trailing: flushPanelEdges ? 0 : 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove { offsets, destination in
                    if player.moveUpcoming(from: offsets, to: destination, matching: rows.map { $0.track.id }) {
                        rows.move(fromOffsets: offsets, toOffset: destination)
                    } else {
                        reconcile(player.upcomingTracks)
                    }
                }
                if rows.isEmpty {
                    Text(player.currentTrack == nil ? "播放队列是空的" : "没有待播歌曲")
                        .font(Theme.Typography.body)
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, minHeight: 140)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                PlaybackHandoffList()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.025),
                    .init(color: .black, location: 0.91),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, flushPanelEdges ? 0 : Theme.Layout.trackListInset)
        .padding(.top, flushPanelEdges ? 0 : Theme.Spacing.component)
        .accessibilityIdentifier("inlinePlaybackQueue")
        .onAppear { reconcile(player.upcomingTracks) }
        .onChange(of: player.upcomingTracks) { reconcile($0) }
    }

    /// Keep a distinct identity per occurrence, including duplicate songs,
    /// so native drag reordering moves the same row throughout the gesture.
    private func reconcile(_ tracks: [Track]) {
        var available = Dictionary(grouping: rows, by: { $0.track.id })
        rows = tracks.map { track in
            if var matches = available[track.id], !matches.isEmpty {
                var item = matches.removeFirst()
                available[track.id] = matches
                item.track = track
                return item
            }
            return InlineQueueItem(track: track)
        }
    }

    private func inlineRow(_ track: Track, upcomingIndex: Int) -> some View {
        Button {
            player.jumpToUpcoming(at: upcomingIndex, matching: track.id)
        } label: {
            HStack(spacing: Theme.Spacing.control) {
                CachedAsyncImage(url: track.album.picUrl?.resizedImageURL(144), animated: false)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(track.name)
                        .font(Theme.Typography.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(track.artistNames)
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                player.removeUpcoming(at: upcomingIndex, matching: track.id)
            } label: {
                Label("从待播清单移除", systemImage: "minus.circle")
            }
        }
        .accessibilityAction(named: Text("上移")) {
            if upcomingIndex > 0 {
                moveRow(at: upcomingIndex, to: upcomingIndex - 1)
            }
        }
        .accessibilityAction(named: Text("下移")) {
            if upcomingIndex + 1 < rows.count {
                moveRow(at: upcomingIndex, to: upcomingIndex + 2)
            }
        }
    }

    private func moveRow(at index: Int, to destination: Int) {
        let offsets = IndexSet(integer: index)
        if player.moveUpcoming(from: offsets, to: destination, matching: rows.map { $0.track.id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                rows.move(fromOffsets: offsets, toOffset: destination)
            }
        }
    }
}

private struct InlineQueueItem: Identifiable {
    let id = UUID()
    var track: Track
}
