import Foundation

/// Semantic operations used by the shared music UI. An unavailable operation
/// is hidden or rejected, never silently sent to a different platform.
enum MusicServiceFeature: String, CaseIterable {
    case login, profile, profileStatistics, playRanking, accountSync
    case recommendedPlaylists, recommendedSongs, personalizedSuggestions, regionalSongs, radarPlaylists
    case dailySongs, recommendationFeedback, personalFM, fmFeedback, intelligenceList, newAlbums, topArtists
    case toplists, toplistSongs, highQualityPlaylists, playlistDetail, songDetails
    case userPlaylists, likedSongs, favoriteChanges, collectionAlbums, collectionArtists
    case searchSongs, searchArtists, searchAlbums, searchPlaylists, searchSuggestions
    case albumDetail, artistDetail, artistAlbums, similarArtists
    case playback, playbackReporting, audioQualities, lyrics, comments, commentChanges
    case playlistCreation, playlistDeletion, playlistTrackAddition, playlistChanges, playlistSubscriptions, recentPlays, cloud, cloudChanges, downloads
}

struct MusicServiceMapping {
    let netease: String
    let qq: String?
    let kugou: String?
    var qishui: String? = nil
    /// Describes a semantic limitation, rather than presenting an approximation
    /// as the platform's original personalized/realtime/full-library endpoint.
    var qqNote = ""
    var kugouNote = ""

    func endpoint(for provider: MusicProvider) -> String? {
        switch provider { case .netease: return netease; case .qq: return qq; case .kugou: return kugou; case .qishui: return qishui }
    }
}

enum MusicServiceCatalog {
    static let mappings: [MusicServiceFeature: MusicServiceMapping] = [
        .login: .init(netease: "qrKey / qrCheck / loginCellphone", qq: "QQMusicAuth.fetchQRCode / poll → QQConnectLogin.LoginServer.QQLogin", kugou: "qrKey / pollQR", qishui: "passport/web/get_qrcode / check_qrconnect"),
        .profile: .init(netease: "userAccount", qq: "QQMusicAuth session profile", kugou: "KugouMusicAuth session profile", qishui: "luna/pc/me"),
        .profileStatistics: .init(netease: "userDetail / playRecords", qq: nil, kugou: nil),
        .playRanking: .init(netease: "playRecords", qq: "ListenReportSvr.GetRank", kugou: "listeningRanking / v2/get_list"),
        .accountSync: .init(netease: "SyncService", qq: nil, kugou: nil),
        .recommendedPlaylists: .init(netease: "personalizedPlaylists / recommendResource", qq: "PlaylistSquare.GetRecommendFeed", kugou: "recommendPlaylists", qishui: "luna/discover/mix"),
        .recommendedSongs: .init(netease: "homeDiscovery / homeTopSongs", qq: "GetRadarSong / get_radio_track", kugou: "everydayRecommend"),
        .personalizedSuggestions: .init(netease: "similarSongs", qq: "GetSimilarSongs", kugou: nil),
        .regionalSongs: .init(netease: "homeTopSongs(areaID:)", qq: nil, kugou: nil),
        .radarPlaylists: .init(netease: "radarPlaylists", qq: nil, kugou: nil),
        .dailySongs: .init(netease: "dailyRecommendSongs", qq: "uniform_get_Dissinfo (202)", kugou: "everydayRecommend"),
        .recommendationFeedback: .init(netease: "dislikeRecommendedSong", qq: nil, kugou: nil),
        .fmFeedback: .init(netease: "fmTrash", qq: nil, kugou: nil),
        .highQualityPlaylists: .init(netease: "highQualityPlaylists", qq: nil, kugou: nil),
        .similarArtists: .init(netease: "similarArtists", qq: "GetSimilarSingerList", kugou: nil),
        .personalFM: .init(netease: "personalFM", qq: "GetRadarSong", kugou: "personalFM"),
        .intelligenceList: .init(netease: "intelligenceList", qq: nil, kugou: nil),
        .newAlbums: .init(netease: "newAlbums", qq: "get_new_album_info", kugou: "newAlbums / mobile_newalbum_sp", kugouNote: "每个地区仅返回少量新碟，不支持翻页"),
        .topArtists: .init(netease: "topArtists", qq: "SingerList.GetSingerListIndex", kugou: "hotSingers / ocean/v6/singer/list"),
        .toplists: .init(netease: "toplists", qq: "topLists", kugou: "topLists", qishui: "luna/pc/discover"),
        .toplistSongs: .init(netease: "toplistPreviewTracks / playlistDetail", qq: "topListSongs", kugou: "rankSongs", qishui: "luna/pc/charts/{id}"),
        .playlistDetail: .init(netease: "playlistDetail", qq: "playlistSongs", kugou: "playlistSongs", qishui: "luna/playlist/detail"),
        .songDetails: .init(netease: "songDetails", qq: "catalog / embedded platformSong", kugou: "catalog / embedded platformSong", qishui: "embedded qishui track", qqNote: "从已返回的歌曲元数据恢复", kugouNote: "从已返回的歌曲元数据恢复"),
        .userPlaylists: .init(netease: "userPlaylists", qq: "userPlaylists", kugou: "userPlaylists", qishui: "luna/pc/me/playlist", qqNote: "按来源区分创建与收藏", kugouNote: "区分创建与收藏的账号歌单"),
        .likedSongs: .init(netease: "likedTrackIDs / likedSongsPlaylist", qq: "favoriteSongs / qqLikedPlaylistID", kugou: "userPlaylists → playlistSongs", qishui: "luna/pc/me/playlist (type 1) → playlist/detail"),
        .favoriteChanges: .init(netease: "likeTrack", qq: "PlaylistDetailWrite / SongFavRead", kugou: "我喜欢 list: v6/add_song / v4/delete_songs", qishui: "luna/pc/me/collection/media[/delete]"),
        .collectionAlbums: .init(netease: "likedAlbums / subscribeAlbum", qq: "favoriteAlbums / AlbumFavWrite", kugou: nil, qishui: "luna/me/collection/mixed / luna/pc/me/collection/album"),
        .collectionArtists: .init(netease: "likedArtists / subscribeArtist", qq: "followedArtists / followArtist", kugou: "v4/follow_list / followservice/v3/(un)follow_singer", qishui: "luna/me/collection/artist / luna/pc/me/collection/artist"),
        .searchSongs: .init(netease: "search(type: .songs)", qq: "searchSongs", kugou: "searchSongs", qishui: "luna/search/track"),
        .searchArtists: .init(netease: "search(type: .artists)", qq: "searchArtists", kugou: "searchArtists", qishui: "luna/search/artist"),
        .searchAlbums: .init(netease: "search(type: .albums)", qq: "searchAlbums", kugou: "searchAlbums", qishui: "luna/search/album"),
        .searchPlaylists: .init(netease: "search(type: .playlists)", qq: "DoSearchForQQMusicLite", kugou: "searchPlaylists / v1/search/special", qishui: "luna/search/playlist"),
        .searchSuggestions: .init(netease: "searchSuggest / searchDefaultKeyword", qq: "GetSmartBoxResult / GetHotkeyForQQMusicMobile", kugou: "hotWords / v2/getSearchTip", qishui: "luna/suggest-words / luna/pc/sug"),
        .albumDetail: .init(netease: "album", qq: "albumSongs / GetAlbumSongList", kugou: "albumSongs / v1/album_audio/lite", qishui: "luna/pc/albums/{id}", kugouNote: "缺少 album_id 时才按名称匹配唯一专辑"),
        .artistDetail: .init(netease: "artist", qq: "artistHotSongs / GetSingerSongList", kugou: "artistSongs", qishui: "luna/pc/artists/{id}"),
        .artistAlbums: .init(netease: "artistAlbums", qq: "artistAlbums / GetAlbumList", kugou: "searchAlbums → artist-name match", qishui: "luna/pc/artists/{id}/albums", kugouNote: "搜索匹配，非完整唱片目录"),
        .playback: .init(netease: "songURL / preferredSongURL", qq: "songURLResult (songmid / media_mid)", kugou: "songURL (hash / album_audio_id)", qishui: "luna/pc/track_v2 / luna/h5/seo_track"),
        .playbackReporting: .init(netease: "PlaybackHistoryReporter / NCBL", qq: nil, kugou: "KugouPlaybackReporter / CSCC / upload_songs", qishui: "POST luna/pc/me/recently-played-media", kugouNote: "按真实引擎进度上报；历史回读与排行入账分别确认"),
        .audioQualities: .init(netease: "songAudioQualities", qq: nil, kugou: "songAudioQualities / songURL(quality:)", qishui: "luna/pc/track_v2 full streams", kugouNote: "提供标准、极高、无损与 Hi-Res 请求，实际可用音质由歌曲及账号决定"),
        .lyrics: .init(netease: "lyric", qq: "lyric(songmid:)", kugou: "lyric(hash:duration:)", qishui: "luna/h5/seo_track"),
        .comments: .init(netease: "songComments", qq: "comments(songID:)", kugou: "comments(mixSongID:hash:)", qishui: "luna/pc/comments"),
        .commentChanges: .init(netease: "likeSongComment / sendSongComment / deleteSongComment", qq: nil, kugou: nil),
        .playlistCreation: .init(netease: "createPlaylist", qq: "AddPlaylist / GetPlaylistByUin", kugou: "createPlaylist / v5/add_list", qishui: "POST luna/pc/me/playlist"),
        .playlistDeletion: .init(netease: "deletePlaylist", qq: "DelPlaylist", kugou: "deleteKugouPlaylist / v2/delete_list", qishui: "POST luna/pc/me/playlist/delete"),
        .playlistTrackAddition: .init(netease: "playlistTracks(add)", qq: "AddSonglist", kugou: "addSongs / v6/add_song", qishui: "POST luna/pc/me/playlist/media/append"),
        .playlistChanges: .init(netease: "createPlaylist / deletePlaylist / playlistTracks", qq: "AddPlaylist / EditPlaylist / DelPlaylist / PlaylistDetailWrite", kugou: "v4/delete_songs / v1/modify_list", qishui: "luna/pc/me/playlist/media/delete / playlist/update"),
        .playlistSubscriptions: .init(netease: "subscribePlaylist", qq: "PlaylistFavWrite", kugou: "createPlaylist(type: 1) / unsubscribePlaylist", qishui: "luna/me/collection/mixed / luna/pc/me/collection/playlist"),
        .recentPlays: .init(netease: "recentSongs / playRecords", qq: nil, kugou: "recentSongPlays / playhistory/v1/get_songs", qishui: "GET luna/pc/me/recently-played-media"),
        .cloud: .init(netease: "cloudSongs", qq: "WeiyunMusicRead.GetMatchAudio", kugou: "cloudLibrary / userCloudURL", kugouNote: "列表、容量与播放"),
        .cloudChanges: .init(netease: "cloudUpload / cloudDelete", qq: nil, kugou: "uploadCloudFile / deleteCloudSongs (add_files / del_files)"),
        .downloads: .init(netease: "songDownloadResource", qq: nil, kugou: "downloadResource / v5/url", kugouNote: "仅完整且可校验的曲库音频；不提供云盘下载"),
    ]
}

extension MusicProvider {
    func supports(_ feature: MusicServiceFeature) -> Bool {
        MusicServiceCatalog.mappings[feature]?.endpoint(for: self) != nil
    }
    var homeDiscoverySlots: [HomeDiscoverySlot] {
        if self == .qishui { return [.radios] }
        if self == .qq { return [.playlists, .trending, .newSongs, .radios] }
        if self == .kugou { return [.playlists, .trending, .forYou, .newSongs, .hiddenGems] }
        return supports(.regionalSongs) ? [.playlists, .trending, .regional] : [.playlists, .trending]
    }
    var dailySongsTitle: String { self == .qq ? String(localized: "每日 30 首") : String(localized: "每日推荐") }
    var playlistSectionTitle: String { self == .netease ? String(localized: "创建的歌单") : String(localized: "我的歌单") }
}
