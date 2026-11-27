import Foundation
import Testing
@testable import CodaCore

@Suite("Shared music interface contract")
@MainActor
struct MusicServiceCatalogTests {
    @Test func everyOperationHasAnExplicitMapping() {
        #expect(Set(MusicServiceCatalog.mappings.keys) == Set(MusicServiceFeature.allCases))
        for feature in MusicServiceFeature.allCases {
            #expect(MusicProvider.netease.supports(feature))
        }
    }

    @Test func qqDoesNotAdvertiseNetEaseOnlyFeatures() {
        #expect(MusicProvider.qq.supports(.recommendedPlaylists))
        #expect(MusicProvider.qq.supports(.dailySongs))
        #expect(MusicProvider.qq.supports(.toplists))
        for feature: MusicServiceFeature in [.personalizedSuggestions, .personalFM, .cloud, .playlistChanges] {
            #expect(MusicProvider.qq.supports(feature))
        }
        for feature: MusicServiceFeature in [.radarPlaylists, .regionalSongs, .highQualityPlaylists,
                                             .intelligenceList, .profileStatistics, .cloudChanges, .downloads, .accountSync] {
            #expect(!MusicProvider.qq.supports(feature))
        }
        #expect(MusicProvider.qq.dailySongsTitle == "每日 30 首")
        #expect(MusicProvider.qq.exploreCategories == ["全部", "推荐歌单", "排行榜"])
        #expect(MusicProvider.kugou.exploreCategories == ["推荐", "最热", "最新", "热藏", "飙升", "排行榜"])
    }

    @Test func externalHomeShelvesDoNotRequestUnavailableRegionalAPIs() async throws {
        var requestedAreas: [Int] = []
        let track = try PlatformMusicAPI.decode(Track.self, ["id": -123, "name": "External fixture"])
        let model = HomeDiscoveryModel(fetchHome: { _ in [.playlists: .playlists([])] },
                                       fetchPlaylists: { _ in Issue.record("Existing playlist shelf should be reused"); return [] },
                                       fetchSongs: { area in requestedAreas.append(area); return [track] },
                                       availableSlots: { [.playlists, .trending] })
        await model.load(loggedIn: false, force: true)
        #expect(requestedAreas == [0])
        #expect(model.failedSlots.isEmpty)
        #expect(model.contents[.regional] == nil)
        guard case .songs(let tracks) = model.contents[.trending] else {
            Issue.record("External songs did not populate the existing song shelf"); return
        }
        #expect(tracks.map(\.id) == [-123])
    }

    @Test func kugouRetainsItsSupportedRadioAndWritableFavorites() {
        #expect(MusicProvider.kugou.supports(.personalFM))
        #expect(MusicProvider.kugou.supports(.likedSongs))
        #expect(MusicProvider.kugou.supports(.favoriteChanges))
        #expect(MusicProvider.kugou.homeDiscoverySlots == [.playlists, .trending, .forYou, .newSongs, .hiddenGems])
    }
}
