import CommonCrypto
import CryptoKit
import Foundation
import Testing
@testable import CodaCore

private func md5Hex(_ text: String) -> String {
    Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func song(hash: String, mix: String? = nil, albumAudio: String? = nil) -> ProviderSong {
    ProviderSong(id: 1, name: "n", artists: "a", album: "", coverURL: nil, duration: 1, source: .kugou,
                 qqMid: nil, qqMediaMid: nil, qqAlbumMID: nil, qqArtistReferences: nil, kugouHash: hash,
                 kugouAlbumAudioId: albumAudio, kugouMixSongID: mix, kugouAlbumId: nil, kugouQualityHashes: nil,
                 kugouCloud: nil, qishui: nil)
}

@Suite struct QishuiGapFillTests {
    @Test func successBodiesMayOmitStatusCode() {
        #expect(QishuiMusicAPI.mutationSucceeded(["status_info": ["log_id": "x"]]))
        #expect(QishuiMusicAPI.mutationSucceeded(["status_code": 0]))
        #expect(!QishuiMusicAPI.mutationSucceeded(["status_code": 1000004]))
        #expect(!QishuiMusicAPI.mutationSucceeded([:]))
    }

    @Test func playlistMediaPayloadUsesTrackMedia() throws {
        let payload = try QishuiMusicAPI.playlistMediaPayload(playlistID: " 77 ", trackIDs: ["1", "2"])
        #expect(payload["playlist_id"] as? String == "77")
        let media = payload["media"] as? [[String: String]]
        #expect(media == [["id": "1", "type": "track"], ["id": "2", "type": "track"]])
        #expect(throws: (any Error).self) { try QishuiMusicAPI.playlistMediaPayload(playlistID: "", trackIDs: ["1"]) }
        #expect(throws: (any Error).self) { try QishuiMusicAPI.playlistMediaPayload(playlistID: "7", trackIDs: ["1", " "]) }
    }

    @Test func keywordTextsReadLiveResponseShapes() {
        // Shapes captured from anonymous GET /luna/pc/sug and /luna/suggest-words/default (2026-11-10).
        let sug: [String: Any] = ["status_info": ["log_id": "x"], "sugs": [
            ["suggestion": "周杰", "content_type": "artist", "entity": ["artist": ["id": "7114648512948537380"]], "group_id": "1"],
            ["suggestion": "周杰伦", "content_type": "artist", "entity": ["artist": ["id": "7629000950985279531"]], "group_id": "2"],
            ["suggestion": "周杰伦所有的歌曲", "content_type": "playlist", "entity": ["playlist": ["id": "7618519056723099657"]], "group_id": "3"]]]
        #expect(QishuiMusicAPI.keywordTexts(sug["sugs"], excluding: "周杰") == ["周杰伦", "周杰伦所有的歌曲"])
        let hot: [String: Any] = ["status_info": ["log_id": "x"], "suggest_words": [
            ["keyword": "莫问归期", "group_id": "7305844060497053706", "type": "track"], ["keyword": "晴天", "group_id": "1", "type": "track"]]]
        #expect(QishuiMusicAPI.keywordTexts(hot, excluding: "") == ["莫问归期", "晴天"])
    }

    @Test func keywordTextsAcceptStringsAndObjects() {
        let body: [String: Any] = ["sugs": [["word": "周杰伦 晴天"], "周杰伦 稻香", ["word": "周杰伦"], ["query": "周杰伦 晴天"]],
                                   "status_info": ["now": "ignored"]]
        #expect(QishuiMusicAPI.keywordTexts(body["sugs"], excluding: "周杰伦") == ["周杰伦 晴天", "周杰伦 稻香"])
        let nested: [String: Any] = ["words": [["show_word": "热搜一"], ["show_word": "热搜二"]], "status_info": ["msg": "x"]]
        #expect(QishuiMusicAPI.keywordTexts(nested, excluding: "") == ["热搜一", "热搜二"])
    }
}

@Suite struct KugouGapFillTests {
    @Test func fileIDsMatchByMixSongIDThenHash() throws {
        let rows: [[String: Any]] = [
            ["fileid": 11, "hash": "AAA", "mixsongid": 900],
            ["fileid": 22, "hash": "BBB", "mixsongid": 0],
        ]
        #expect(try KugouMusicAPI.playlistFileIDs(rows: rows, songs: [song(hash: "zzz", mix: "900")]) == [11])
        #expect(try KugouMusicAPI.playlistFileIDs(rows: rows, songs: [song(hash: "bbb")]) == [22])
        #expect(throws: (any Error).self) { try KugouMusicAPI.playlistFileIDs(rows: rows, songs: [song(hash: "ccc")]) }
    }

    @Test func renameKeepsIntroTagsAndSort() {
        var playlist = ProviderPlaylist(id: 5, name: "旧", coverURL: nil, source: .kugou)
        playlist.kugouIntro = "简介"; playlist.kugouTags = "流行"; playlist.kugouSort = 3
        let body = KugouMusicAPI.renameBody(playlist: playlist, name: "新")
        #expect(body["listid"] as? Int == 5)
        #expect(body["name"] as? String == "新")
        #expect(body["intro"] as? String == "简介")
        #expect(body["tags"] as? String == "流行")
        #expect(body["sort"] as? Int == 3)
    }

    @Test func playlistMetadataKeepsEditableFields() {
        let item = KugouMusicAPI.mapPlaylist(["listid": 8, "name": "x", "intro": "i", "tags": [["tag_name": "a"], ["tag_name": "b"]], "sort": 2],
                                             accountUserID: "1")
        #expect(item?.kugouIntro == "i")
        #expect(item?.kugouTags == "a,b")
        #expect(item?.kugouSort == 2)
    }

    @Test func followEnvelopeIsAES256WithKeyDerivedIV() throws {
        let envelope = try #require(KugouMusicAPI.followEnvelope(["singerid": 3520, "token": "t"], tempKey: "abcdefghijklmnop"))
        #expect(envelope.key == "abcdefghijklmnop")
        let key = md5Hex("abcdefghijklmnop")
        let cipher = Data(stride(from: 0, to: envelope.params.count, by: 2).map {
            let start = envelope.params.index(envelope.params.startIndex, offsetBy: $0)
            return UInt8(envelope.params[start..<envelope.params.index(start, offsetBy: 2)], radix: 16)!
        })
        var out = Data(count: cipher.count + kCCBlockSizeAES128)
        let capacity = out.count
        var length = 0
        let keyData = Data(key.utf8), iv = Data(key.suffix(16).utf8)
        let status = out.withUnsafeMutableBytes { o in cipher.withUnsafeBytes { c in keyData.withUnsafeBytes { k in iv.withUnsafeBytes { v in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), k.baseAddress, kCCKeySizeAES256,
                    v.baseAddress, c.baseAddress, cipher.count, o.baseAddress, capacity, &length)
        } } } }
        #expect(status == kCCSuccess)
        let plain = try JSONSerialization.jsonObject(with: out.prefix(length)) as? [String: Any]
        #expect(plain?["singerid"] as? Int == 3520)
        #expect(plain?["token"] as? String == "t")
    }

    @Test func followListParsesSingers() {
        let json: [String: Any] = ["status": 1, "data": ["lists": [
            ["singerid": 3520, "nickname": "周杰伦", "k_pic": "https://img/{size}/a.jpg"],
            ["singerid": 3520, "nickname": "周杰伦"], ["singerid": 0, "nickname": "无效"]
        ]]]
        let items = KugouMusicAPI.followedSingers(in: json)
        #expect(items.map(\.id) == ["3520"])
        #expect(items.first?.coverURL?.absoluteString == "https://img/240/a.jpg")
    }

    @Test func searchTipsReadHintInfo() {
        let json: [String: Any] = ["status": 1, "data": [["LableName": "", "RecordDatas": [["HintInfo": "周杰伦 晴天"], ["HintInfo": "周杰伦"], ["HintInfo": "周杰伦 晴天"]]]]]
        #expect(KugouMusicAPI.searchTips(in: json, excluding: "周杰伦") == ["周杰伦 晴天"])
    }

}

@Suite struct SearchKeywordTests {
    @Test func uniqueDropsBlankDuplicatesAndKeyword() {
        #expect(SearchKeywords.unique([" 晴天 ", "晴天", "", "周杰伦", "稻香", "七里香"], excluding: "周杰伦", limit: 2) == ["晴天", "稻香"])
    }

    @Test func newlyWiredFeaturesAreInTheCatalog() {
        #expect(MusicProvider.kugou.supports(.favoriteChanges))
        #expect(MusicProvider.kugou.supports(.collectionArtists))
        #expect(MusicProvider.kugou.supports(.searchPlaylists))
        // album_audio/related lists other versions of one song, not similar songs.
        #expect(!MusicProvider.kugou.supports(.personalizedSuggestions))
        #expect(MusicProvider.kugou.supportsPlaylistRename)
        #expect(MusicProvider.qishui.supports(.searchSuggestions))
        #expect(MusicProvider.qishui.supports(.playlistDeletion))
        #expect(MusicProvider.qishui.supports(.playlistTrackAddition))
        #expect(MusicProvider.qishui.supportsPlaylistRename)
        #expect(!MusicProvider.netease.supportsPlaylistRename)
    }
}
