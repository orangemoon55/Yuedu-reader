import Foundation
import Testing
@testable import CodaCore

/// 实际请求酷狗首页接口。设置 CODA_KUGOU_LIVE_HOME_AUDIT=1 时运行。
@Suite("Kugou live home shelves", .enabled(if: ProcessInfo.processInfo.environment["CODA_KUGOU_LIVE_HOME_AUDIT"] == "1"))
struct KugouLiveHomeTests {
    @Test func newAlbumsInterleaveRegionsWithNumericIDs() async throws {
        let albums = try await KugouMusicAPI.shared.newAlbums(limit: 20)
        #expect(albums.count >= 4)
        #expect(albums.allSatisfy { Int64($0.id) ?? 0 > 0 && $0.coverURL != nil && !$0.artistName.isEmpty })
        print("albums", albums.prefix(6).map { "\($0.name) - \($0.artistName)" })
    }

    @Test func hotSingersHaveIDsAndCovers() async throws {
        let singers = try await KugouMusicAPI.shared.hotSingers(limit: 30)
        #expect(singers.count >= 10)
        #expect(singers.allSatisfy { Int($0.id) != nil && $0.coverURL?.absoluteString.contains("{size}") == false })
        print("singers", singers.prefix(6).map(\.name))
    }

    @Test func shelfItemsOpenTheirDetailPages() async throws {
        let album = try #require(try await KugouMusicAPI.shared.newAlbums(limit: 1).first)
        #expect(!(try await KugouMusicAPI.shared.albumSongs(album: album)).isEmpty)
        let singer = try #require(try await KugouMusicAPI.shared.hotSingers(limit: 1).first)
        // 歌手详情按 ID 取歌；与搜索结果的 ID 一致即可走同一条详情路径。
        let searched = try await KugouMusicAPI.shared.searchArtists(keyword: singer.name, limit: 3)
        #expect(searched.contains { $0.id == singer.id })
    }

    @Test func hotWordsComeFromTheLiveChart() async throws {
        let words = try await KugouMusicAPI.shared.hotWords(limit: 8)
        #expect(words.count == 8)
        print("hot", words)
    }

    @Test func everyExploreSortReturnsOpenablePlaylists() async throws {
        var firsts = Set<Int>()
        for sort in KugouMusicAPI.PlaylistSort.allCases {
            let lists = try await KugouMusicAPI.shared.sortedPlaylists(sort)
            #expect(lists.count >= 20, "\(sort.title)")
            #expect(lists.allSatisfy { $0.kugouGlobalCollectionID != nil && $0.coverURL != nil })
            if let first = lists.first { firsts.insert(first.id) }
        }
        // 不同排序应给出不同内容，而不是同一页。
        #expect(firsts.count >= 3)
        let sample = try #require(try await KugouMusicAPI.shared.sortedPlaylists(.newest).first)
        #expect(!(try await KugouMusicAPI.shared.playlistSongs(playlist: sample)).isEmpty)
    }

    @Test func songCardsAndNewSongsArePlayable() async throws {
        let api = KugouMusicAPI.shared
        for card in KugouMusicAPI.SongCard.allCases {
            let songs = try await api.cardSongs(card)
            #expect(songs.count >= 10, "card \(card.rawValue)")
            #expect(songs.allSatisfy { $0.kugouHash?.isEmpty == false && !$0.artists.isEmpty })
        }
        let fresh = try await api.newSongs()
        #expect(fresh.count >= 20)
        let second = try await api.newSongs(page: 2)
        #expect(Set(second.map(\.identityKey)).isDisjoint(with: fresh.map(\.identityKey)))
        // 免费歌曲在未登录时也应能解析出播放地址。
        var playable = 0
        for song in (try await api.cardSongs(.hot)).prefix(6) + fresh.prefix(6) {
            if (try? await api.songURL(song: song))??.isEmpty == false { playable += 1 }
        }
        print("playable", playable, "of 12")
        #expect(playable > 0)
    }
}
