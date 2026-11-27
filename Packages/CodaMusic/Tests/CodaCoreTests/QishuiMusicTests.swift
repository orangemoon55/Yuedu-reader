import Foundation
import Testing
@testable import CodaCore

private final class QishuiFixture: URLProtocol, @unchecked Sendable {
    private static let playbackRequestLock = NSLock()
    private static var signedPlaybackRequests = 0

    static var signedPlaybackRequestCount: Int {
        playbackRequestLock.withLock { signedPlaybackRequests }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let mode = request.value(forHTTPHeaderField: "X-Qishui-Fixture") ?? ""
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let cursor = query.first { $0.name == "cursor" }?.value ?? ""
        var headers = ["Content-Type": "application/json"]
        var result: [String: Any] = [:]
        if mode == "reject" { result = ["status_code": 1000004] }
        else {
            switch request.url!.path {
            case "/passport/web/get_qrcode/", "/passport/web/get_qrcode":
                #expect(query.first { $0.name == "device_id" }?.value?.count == 16)
                #expect(query.first { $0.name == "iid" }?.value?.count == 15)
                #expect(request.value(forHTTPHeaderField: "X-Tt-Passport-Verify-Portrait")?.hasSuffix(".login") == true)
                headers["Set-Cookie"] = "passport_csrf_token=qr-flow; Path=/; Secure"
                result = ["message": "success", "data": ["token": "qr-token", "qrcode": "data:image/png;base64,YQ==", "qrcode_index_url": "https://bff-pc.qishui.com/ucenter_web/app/sdk-next?token=separate-scan-token&uc_sdk=scan-auth", "expire_time": 1_900_000_000]]
            case "/passport/web/check_qrconnect/", "/passport/web/check_qrconnect":
                #expect(request.httpMethod == "POST")
                let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
                let csrf = cookie.contains("retry-csrf") ? "retry-csrf" : cookie.contains("scanned-csrf") ? "scanned-csrf" : "qr-flow"
                #expect(request.value(forHTTPHeaderField: "X-Tt-Passport-Csrf-Token") == csrf)
                #expect(request.value(forHTTPHeaderField: "X-Ss-Stub")?.count == 32)
                #expect(query.first { $0.name == "iid" }?.value?.count == 15)
                if ["transient1049", "persistent1049"].contains(mode) {
                    if csrf == "qr-flow" {
                        headers["Set-Cookie"] = "passport_csrf_token=scanned-csrf; Path=/; Secure"
                        result = ["message": "success", "data": ["status": "1", "error_code": 0]]
                    } else if csrf == "scanned-csrf" || mode == "persistent1049" {
                        headers["Set-Cookie"] = "passport_csrf_token=retry-csrf; Path=/; Secure"
                        result = ["message": "error", "data": ["error_code": 1049, "description": "登录校验未通过 token=qr-token Cookie=retry-csrf"]]
                    } else {
                        result = ["message": "success", "data": ["status": "3", "error_code": 0, "session_cookie": "sessionid_ss=confirmed-session; sid_guard=guard-value"]]
                    }
                } else if mode == "unscanned1049" {
                    result = ["message": "error", "data": ["error_code": 1049, "description": "平台拒绝当前登录"]]
                } else if mode == "rateLimited" {
                    result = ["message": "error", "data": ["error_code": 7]]
                } else if mode.hasPrefix("mfa") {
                    let resent = query.contains { $0.name == "isResend" && $0.value == "true" }
                    if !resent {
                        headers["Set-Cookie"] = "passport_mfa_token=mfa-flow; Path=/; Secure"
                        result = ["message": "error", "data": ["error_code": 2046, "url": "https://verify.zijieapi.com/verification.js",
                            "verify_from": mode == "mfa-center" ? "verify_center" : "verify", "biz_params": "{\"verify_ticket\":\"verified-ticket\",\"token\":\"must-not-replace-qr\"}"]]
                    } else {
                        #expect(cookie.contains("passport_mfa_token=mfa-flow"))
                        let fields = URLComponents(string: "https://api.qishui.com/?" + String(decoding: Self.rawBody(request), as: UTF8.self))?.queryItems ?? []
                        #expect(fields.contains { $0.name == "token" && $0.value == "qr-token" })
                        #expect(fields.contains { $0.name == "verify_ticket" && $0.value == "verified-ticket" })
                        headers["Set-Cookie"] = "sessionid=confirmed-session; Path=/; Secure"
                        result = ["message": "success", "data": ["status": "confirmed", "error_code": 0]]
                    }
                } else {
                    if mode != "missingSession" { headers["Set-Cookie"] = "sessionid=confirmed-session; Path=/; Secure" }
                    result = ["message": "success", "data": ["status": "confirmed"]]
                }
            case "/luna/pc/me/playlist":
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=confirmed-session") == true)
                #expect(request.value(forHTTPHeaderField: "X-Helios") == "test-helios")
                #expect(request.value(forHTTPHeaderField: "X-Medusa") == "test-medusa")
                let payload = Self.body(request)
                #expect(payload["name"] as? String == "夜间歌单")
                #expect(payload["is_private"] as? Bool == (mode == "createPlaylistNested"))
                switch mode {
                case "createPlaylistNested":
                    result = ["data": ["playlist_id": "7096700219496368135"], "status_code": 0]
                case "createPlaylistRejected":
                    result = ["status_code": 1000014]
                case "createPlaylistMissingID":
                    result = ["status_info": ["now": 1_800_000_000]]
                default:
                    result = ["playlist": ["id": Int64(7096700219496368135), "title": "夜间歌单", "type": 3],
                              "status_info": ["now": 1_800_000_000]]
                }
            case "/luna/pc/me":
                if mode == "transient1049" {
                    #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionid_ss=confirmed-session") == true)
                    #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sid_guard=guard-value") == true)
                } else { #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=confirmed-session") == true) }
                result = ["my_info": ["id": "7096700219496368135", "nickname": "Fixture", "is_vip": "0"]]
            case "/luna/pc/me/recently-played-media":
                #expect(request.url?.host == "api.qishui.com")
                #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=confirmed-session") == true)
                if request.httpMethod == "POST" {
                    let bytes = Self.rawBody(request)
                    let payload = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
                    #expect(payload?["media"] as? [[String: String]] == [["id": "7079108541549643812", "type": "track"]])
                    #expect(request.value(forHTTPHeaderField: "X-SS-STUB") == bytes.md5Hex().uppercased())
                    result = mode == "expiredHistory" ? ["status_code": 1000016] : ["status_info": ["now": 1_800_000_000]]
                } else if mode == "emptyHistory" {
                    result = ["status_info": ["now": 1_800_000_000]]
                } else {
                    #expect(query.contains { $0.name == "media_type" && $0.value == "track" })
                    let first = Self.resource("7079108541549643812").merging(["play_start_timestamp": 1_800_000_000]) { _, new in new }
                    let second = Self.resource("7079108541549643813").merging(["play_start_timestamp": "1799999999000"]) { _, new in new }
                    if cursor.isEmpty {
                        result = ["media": [first], "next_cursor": "opaque-history", "has_more": true]
                    } else {
                        #expect(cursor == "opaque-history")
                        result = ["media": [first, second]]
                    }
                }
            case "/luna/pc/playlist/detail":
                #expect(request.url?.host == "api.qishui.com")
                #expect(request.httpMethod == "GET")
                #expect(query.contains { $0.name == "playlist_id" && $0.value == "7096700219496368135" })
                #expect(query.contains { $0.name == "count" && $0.value == "50" })
                if mode == "accountPlaylist" {
                    #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=confirmed-session") == true)
                    result = ["playlist": ["count_tracks": 1], "media_resources": [Self.resource("7079108541549643812")]]
                } else if ["emptyPlaylist", "missingPlaylistTracks", "playlistFallback"].contains(mode) {
                    result = ["playlist": ["count_tracks": mode == "emptyPlaylist" ? 0 : 1]]
                } else {
                    let second = cursor == "opaque-page-2"
                    #expect(cursor.isEmpty || second)
                    result = ["has_more": !second, "next_cursor": second ? "" : "opaque-page-2", "media_resources": second ? [Self.resource("7079108541549643812"), Self.resource("7079108541549643813")] : [Self.resource("7079108541549643812"), ["entity": ["video": ["id": "video"]]]]]
                }
            case "/luna/playlist/detail":
                #expect(request.url?.host == "beta-luna.douyin.com")
                #expect(request.httpMethod == "POST")
                let payload = Self.body(request)
                #expect(payload["playlist_id"] as? String == "7096700219496368135")
                #expect(payload["cursor"] as? String == "")
                if mode == "playlistFallback" {
                    #expect(payload["playlist_type"] as? Int == 3)
                    result = ["data": ["playlist": ["id": "7096700219496368135", "title": "Recovered playlist",
                                                    "public_title": "", "count_tracks": 1],
                                       "media_resources": [Self.resource("7079108541549643812")]]]
                } else {
                    #expect(mode == "missingPlaylistTracks")
                    result = ["playlist": ["count_tracks": 1]]
                }
            case "/luna/pc/search/track":
                #expect(request.httpMethod == "GET")
                #expect(query.contains { $0.name == "device_id" && !($0.value ?? "").isEmpty })
                let second = cursor == "37"
                #expect(cursor == "0" || second)
                #expect(query.contains { $0.name == "q" && $0.value == "Fixture" })
                #expect(query.contains { $0.name == "device_platform" && $0.value == "windows" })
                #expect(request.value(forHTTPHeaderField: "X-Helios") == "test-helios")
                #expect(request.value(forHTTPHeaderField: "X-Medusa") == "test-medusa")
                result = ["result_groups": [["has_more": !second, "next_cursor": second ? 51 : 37,
                    "data": second ? [Self.resource("7079108541549643813")] : [Self.resource("7079108541549643812"), ["entity": ["video": ["id": "v"]]]]]]]
            case "/luna/pc/artists/789":
                result = ["artist_info": ["id": "789", "name": "Artist"], "hot_tracks": [["id": "22"]]]
            case "/luna/pc/artists/789/albums":
                switch cursor {
                case "":
                    result = ["albums": [["id": "11", "name": "Album", "release_date": 1_782_000_000]], "next_cursor": "albums-2"]
                case "albums-2":
                    result = ["albums": [["id": "11"], ["id": "12"]], "next_cursor": "albums-end"]
                default:
                    result = ["next_cursor": "albums-end"]
                }
            case "/luna/pc/artists/789/tracks":
                result = cursor.isEmpty
                    ? ["tracks": [["id": "21"], ["id": "22"]], "has_more": true, "next_cursor": "tracks-2"]
                    : ["tracks": [["id": "23"]], "has_more": false]
            case "/luna/pc/track_v2":
                if mode == "wordLyrics" {
                    result = ["lyric": ["content": ""]]
                } else if mode == "pcOriginalLyrics" {
                    result = ["lyric": ["content": "[1010,1000]<0,400,0>Hel<400,600,0>lo"]]
                } else if mode == "androidLyrics" {
                    result = ["track": ["lyric": [
                        "content": "[1010,1000]<0,400,0>Hel<400,600,0>lo",
                        "lang_translations": ["CHINESE": ["content": "[00:01.01]你好"]]
                    ]]]
                } else if mode == "signedStream" {
                    let signed = request.httpMethod == "POST"
                    if signed {
                        Self.playbackRequestLock.withLock { Self.signedPlaybackRequests += 1 }
                        #expect(request.value(forHTTPHeaderField: "X-Helios") == "test-helios")
                        #expect(request.value(forHTTPHeaderField: "X-Medusa") == "test-medusa")
                        #expect(request.value(forHTTPHeaderField: "X-SS-STUB") == Self.rawBody(request).md5Hex().uppercased())
                        #expect(Self.body(request)["track_id"] as? String == "track")
                    }
                    result = ["track": ["duration": 297240], "track_player": ["video_model": [
                        "video_duration": signed ? 297.24 : 30,
                        "video_list": [
                            ["main_url": "https://audio.douyinvod.com/track.m4a", "quality": "medium"],
                            ["main_url": "https://audio.douyinvod.com/higher.m4a", "quality": "higher"]
                        ]
                    ]]]
                } else {
                    result = ["status_code": 1]
                }
            case "/luna/pc/me/collection/media", "/luna/pc/me/collection/media/delete":
                let payload = Self.body(request)
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "X-Helios") == "test-helios")
                #expect(request.value(forHTTPHeaderField: "X-Medusa") == "test-medusa")
                #expect(payload["media"] as? [[String: String]] == [["type": "track", "id": "7079108541549643812"]])
                if request.url!.path.hasSuffix("/delete") {
                    #expect(payload["scene"] == nil)
                    result = ["status_code": 1000004]
                } else {
                    #expect(payload["scene"] as? String == "")
                    result = ["status_info": ["now": 1_800_000_000]]
                }
            case "/luna/pc/me/collection/playlist", "/luna/pc/me/collection/playlist/delete",
                 "/luna/pc/me/collection/album", "/luna/pc/me/collection/album/delete",
                 "/luna/pc/me/collection/artist", "/luna/pc/me/collection/artist/delete":
                let kind = request.url!.pathComponents[5]
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "X-Helios") == "test-helios")
                #expect(Self.body(request) as? [String: [String]] == ["\(kind)_ids": ["7096700219496368135"]])
                result = ["status_code": 0]
            case "/luna/me/collection/mixed", "/luna/me/collection/artist":
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=confirmed-session") == true)
                let kind = query.first { $0.name == "item_types" }?.value
                if request.url!.path.hasSuffix("/artist") {
                    #expect(kind == nil)
                    result = ["artists": [["id": "789", "name": "Fixture artist"]]]
                } else if kind == "playlist" {
                    let item = ["playlist": ["id": "7096700219496368135", "title": "Fixture playlist"]]
                    if cursor.isEmpty {
                        result = ["mixed_collections": [item], "next_cursor": "playlist-next", "has_more": true]
                    } else {
                        #expect(cursor == "playlist-next")
                        result = ["mixed_collections": [item, ["playlist": ["id": "7096700219496368136"]]]]
                    }
                } else {
                    #expect(kind == "album")
                    result = ["status_info": ["now": 1_800_000_000]]
                }
            case "/luna/pc/discover/mix":
                let payload = Self.body(request)
                let exposed = payload["exposure_radio_list"] as? [UInt64]
                let firstID: UInt64 = 7096700219496368135
                let radio: [String: Any] = ["resource_id": "radio-1", "type": "radio",
                    "style": ["title": "Fixture radio", "link": "luna://luna.com/play_source?flow_type=3&trigger_info=fixture"]]
                let second = exposed == [firstID]
                let id = second ? "7096700219496368136" : String(firstID)
                let playlist = ["entity": ["playlist": ["id": id, "public_title": second ? "Next playlist" : "Fixture playlist"]]]
                #expect(request.url?.host == "api.qishui.com")
                #expect(request.httpMethod == "POST")
                #expect((request.value(forHTTPHeaderField: "Cookie") ?? "").isEmpty)
                #expect(payload["block_type"] as? String == "discover_playlist_mix")
                #expect(exposed == [] || second)
                let channel = payload["sub_channel_id"] as? Int
                #expect(channel == -2 || channel == 0)
                result = ["has_more": !second, "inner_block": [
                    ["inner_block_id": id, "resources": channel == -2 ? [playlist, radio] : [radio, playlist, playlist]]
                ]]
            case "/luna/pc/feed/mode", "/luna/pc/feed/song-tab", "/luna/pc/feed/radio/tracks":
                guard request.value(forHTTPHeaderField: "X-Helios") == "test-helios",
                      request.value(forHTTPHeaderField: "X-Medusa") == "test-medusa",
                      request.value(forHTTPHeaderField: "X-SS-STUB") == Self.rawBody(request).md5Hex().uppercased(),
                      query.contains(where: { $0.name == "aid" && $0.value == "386088" }) else {
                    result = ["status_code": 1000006]
                    break
                }
                switch request.url!.path {
                case "/luna/pc/feed/mode":
                    result = ["feed_mode_block": [["feed_mode": [["text": "夜间",
                        "entity": ["feed_scene_mode": ["scene_mode_id": 4, "sub_queue_type": "scene_mode_emo"]]]]]]]
                case "/luna/pc/feed/song-tab":
                    let payload = Self.body(request)
                    let count = (payload["feed_counts"] as? [String: Int])?["mix_session_count"]
                    #expect(payload["is_first_request"] as? Bool == (count == 1))
                    #expect(payload["is_did_first_request"] as? Bool == (count == 1))
                    #expect(payload["did_first_use_time"] as? Int == 1_800_000_000)
                    if let preference = payload["feed_preference"] {
                        #expect(preference as? [String: String] == ["preference_mode": "familiar"])
                        if count == 1 {
                            result = ["items": [Self.resource("7079108541549643812")]]
                        } else {
                            let played = (payload["played_media"] as? [[String: Any]])?.first
                            #expect(played?["media_id"] as? String == "7079108541549643812")
                            #expect(played?["played_mills"] as? Int == 15_000)
                            // A duplicate-only batch must not strand the listener at the queue tail.
                            result = ["items": [Self.resource(count == 2 ? "7079108541549643812" : "7079108541549643815")]]
                        }
                    } else {
                        #expect(count == 1)
                        result = ["items": [Self.resource("7079108541549643814")]]
                    }
                case "/luna/pc/feed/radio/tracks":
                    let payload = Self.body(request)
                    #expect(payload["radio_id"] as? String == "radio-1")
                    #expect(payload["flow_type"] as? Int == 3)
                    #expect(payload["trigger_info"] as? String == "fixture")
                    if payload["cursor"] as? String == "" {
                        result = ["items": [Self.resource("7079108541549643813")], "cursor": "radio-next"]
                    } else {
                        #expect(payload["cursor"] as? String == "radio-next")
                        result = ["items": [Self.resource("7079108541549643816")], "has_more": false]
                    }
                default: break
                }
            case "/sign":
                let json = Self.body(request)
                let headers = json["headers"] as? [String: String]
                #expect(request.url?.absoluteString == "http://103.236.75.83:8899/sign")
                #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
                let target = (json["url"] as? String).flatMap(URL.init(string:))
                #expect(target?.host == "api.qishui.com")
                if target?.path == "/luna/pc/search/track" {
                    // Search is anonymous: signed GET, no body, no stub.
                    #expect(json["method"] as? String == "GET" && json["body"] as? String == "")
                    #expect(headers?["X-SS-STUB"] == nil)
                    result = ["ok": true, "headers": ["x-helios": "test-helios", "x-medusa": "test-medusa"]]
                    break
                }
                #expect(headers?["Cookie"]?.contains("sessionid=confirmed-session") == true)
                let paths: [String]
                switch mode {
                case "signedFeed": paths = ["/luna/pc/feed/mode", "/luna/pc/feed/song-tab", "/luna/pc/feed/radio/tracks"]
                case "signedFavorites": paths = ["/luna/pc/me/collection/media", "/luna/pc/me/collection/media/delete"]
                case let value where value.hasPrefix("createPlaylist"): paths = ["/luna/pc/me/playlist"]
                case "signedCollections":
                    paths = ["playlist", "album", "artist"].flatMap { kind in
                        ["/luna/pc/me/collection/\(kind)", "/luna/pc/me/collection/\(kind)/delete"]
                    }
                default: paths = ["/luna/pc/track_v2"]
                }
                #expect(paths.contains(target?.path ?? ""))
                #expect(headers?["X-SS-STUB"] == Data((json["body"] as? String ?? "").utf8).md5Hex().uppercased())
                result = ["ok": true, "headers": ["x-helios": "test-helios", "x-medusa": "test-medusa"]]
            case "/luna/h5/seo_track":
                if mode == "wordLyrics" {
                    result = ["seo_track": ["lyric": [
                        "content": "[1010,1000]<0,400,0>Hel<400,600,0>lo",
                        "translations": ["cn": "[00:01.01]你好"]
                    ]]]
                } else if mode == "pcOriginalLyrics" {
                    result = ["lyric": ["translations": ["cn": "[00:01.01]你好"]]]
                } else {
                    #expect(mode != "androidLyrics")
                    result = ["lyric": ["content": "[00:01.000]小半\n[00:02.000]想你"]]
                }
            case "/passport/safe/pack_verify_ways_data", "/passport/safe/pack_verify_ways_data/":
                #expect(mode == "mfa-center")
                result = ["data": ["url": "https://verify.zijieapi.com/expanded.js"]]
            default: Issue.record("Unexpected Qishui endpoint \(request.url!.path)")
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: result))
        client?.urlProtocolDidFinishLoading(self)
    }
    private static func resource(_ id: String) -> [String: Any] { ["entity": ["track_wrapper": ["track": ["id": id, "name": "Song", "duration": 218133]]]] }
    private static func rawBody(_ request: URLRequest) -> Data {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
        }
        return data
    }
    private static func body(_ request: URLRequest) -> [String: Any] { (try? JSONSerialization.jsonObject(with: rawBody(request))) as? [String: Any] ?? [:] }
}

@Suite("Qishui native integration", .serialized)
@MainActor
struct QishuiMusicTests {
    private func api(_ mode: String = "", now: @escaping () -> Date = Date.init, verification: QishuiMusicAPI.VerificationHandler? = nil) -> QishuiMusicAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QishuiFixture.self]
        configuration.httpAdditionalHeaders = ["X-Qishui-Fixture": mode]
        return QishuiMusicAPI(configuration: configuration, now: now, usesSignedPassport: false, verificationHandler: verification)
    }
    @Test func readsAccountHistoryAcrossPagesAndDeduplicatesTracks() async throws {
        let client = api()
        try client.restore(["sessionid": "confirmed-session", "userid": "42"])
        let entries = try await client.recentSongPlays(limit: 20)
        #expect(entries.compactMap { $0.song.qishui?.trackID } == ["7079108541549643812", "7079108541549643813"])
        #expect(entries.map { $0.playedAt.timeIntervalSince1970 } == [1_800_000_000, 1_799_999_999])
        let empty = api("emptyHistory")
        try empty.restore(["sessionid": "confirmed-session", "userid": "42"])
        #expect(try await empty.recentSongPlays(limit: 20).isEmpty)
    }

    @Test func writesHistoryWithOriginalTrackIDAndDetectsExpiredSession() async throws {
        let client = api(), expired = api("expiredHistory")
        for api in [client, expired] { try api.restore(["sessionid": "confirmed-session", "userid": "42"]) }
        try await client.appendRecentPlay(trackID: "7079108541549643812")
        do {
            try await expired.appendRecentPlay(trackID: "7079108541549643812")
            Issue.record("An expired session must not acknowledge history")
        } catch QishuiError.expiredLogin {}
    }

    @Test func qrFlowKeepsCookiesAndVerifiesConfirmedProfile() async throws {
        let client = api(), qr = try await client.qrCode()
        #expect(qr.token == "qr-token")
        #expect(qr.scanURL.path == "/light/invoke/scan_login")
        #expect(URLComponents(url: qr.scanURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "token" }?.value == "separate-scan-token")
        guard case .confirmed(let credentials) = try await client.pollQRCode(token: qr.token) else { Issue.record("QR did not complete"); return }
        #expect(credentials["userid"] == "7096700219496368135")
        #expect(credentials["sessionid"] == "confirmed-session")
        #expect(!client.isLoggedIn) // A candidate QR never activates itself.
    }
    @Test func confirmedWithoutSessionDoesNotLogIn() async throws {
        let client = api("missingSession"), qr = try await client.qrCode()
        guard case .processing = try await client.pollQRCode(token: qr.token) else { Issue.record("Confirmation must wait for a session"); return }
        #expect(!client.isLoggedIn)
    }
    @Test func transient1049PreservesScannedFlowAndRotatedCookiesUntilVerified() async throws {
        var clock = Date()
        let client = api("transient1049", now: { clock }), qr = try await client.qrCode()
        guard case .scanned = try await client.pollQRCode(token: qr.token) else { Issue.record("Must retain the observed scan"); return }
        guard case .processing = try await client.pollQRCode(token: qr.token) else { Issue.record("Temporary 1049 must wait"); return }
        // A premature poll must respect the server cooldown, not hit the endpoint.
        guard case .processing = try await client.pollQRCode(token: qr.token) else { Issue.record("Cooldown missing"); return }
        clock = clock.addingTimeInterval(6)
        guard case .confirmed(let credentials) = try await client.pollQRCode(token: qr.token) else { Issue.record("Verified result missing"); return }
        #expect(credentials["userid"] == "7096700219496368135")
        #expect(credentials["cookie"]?.contains("sessionid_ss=confirmed-session") == true)
        #expect(credentials["cookie"]?.contains("sid_guard=guard-value") == true)
        #expect(!client.isLoggedIn)
    }
    @Test func persistent1049StopsWithRedactedPlatformReason() async throws {
        var clock = Date()
        let client = api("persistent1049", now: { clock }), qr = try await client.qrCode()
        _ = try await client.pollQRCode(token: qr.token)
        for _ in 0..<3 {
            guard case .processing = try await client.pollQRCode(token: qr.token) else { Issue.record("Bounded retry missing"); return }
            clock = clock.addingTimeInterval(6)
        }
        do {
            _ = try await client.pollQRCode(token: qr.token)
            Issue.record("Persistent rejection must terminate")
        } catch {
            #expect(error.localizedDescription.contains("1049"))
            #expect(error.localizedDescription.contains("登录校验未通过"))
            #expect(!error.localizedDescription.contains("qr-token"))
            #expect(!error.localizedDescription.contains("retry-csrf"))
        }
        #expect(!client.isLoggedIn)
        guard case .expired = try await client.pollQRCode(token: qr.token) else { Issue.record("Rejected flow must be discarded"); return }
    }
    @Test func unscannedRejectionIsNotMisrepresentedAsScanned() async throws {
        let client = api("unscanned1049"), qr = try await client.qrCode()
        await #expect(throws: Error.self) { try await client.pollQRCode(token: qr.token) }
        #expect(!client.isLoggedIn)
    }
    @Test func rateLimitWaitsWithoutLoggingIn() async throws {
        let client = api("rateLimited"), qr = try await client.qrCode()
        guard case .processing = try await client.pollQRCode(token: qr.token) else { Issue.record("Rate limit must cool down"); return }
        #expect(!client.isLoggedIn)
    }
    @Test func cancellingLoginInvalidatesItsQRCode() async throws {
        let client = api(), qr = try await client.qrCode()
        client.cancelLogin()
        guard case .expired = try await client.pollQRCode(token: qr.token) else { Issue.record("Cancelled QR must not continue polling"); return }
    }
    @Test func signedTransportRejectsOtherOriginsAndClosedSessions() async {
        let transport = QishuiPassportSession()
        await #expect(throws: Error.self) { try await transport.send(URLRequest(url: URL(string: "https://example.com/passport/web/get_qrcode/")!)) }
        transport.close()
        await #expect(throws: Error.self) { try await transport.send(URLRequest(url: URL(string: "https://api.qishui.com/passport/web/get_qrcode/")!)) }
    }
    @Test(arguments: ["mfa", "mfa-center"])
    func secondVerificationResendsInTheSameFlowWithoutOverwritingItsToken(mode: String) async throws {
        var verified = false
        let client = api(mode, verification: { decision in
            #expect(QishuiMusicAPI.string(decision["url"]).contains(mode == "mfa-center" ? "expanded.js" : "verification.js"))
            verified = true
        })
        let qr = try await client.qrCode()
        guard case .confirmed(let credentials) = try await client.pollQRCode(token: qr.token) else { Issue.record("MFA did not finish"); return }
        #expect(verified)
        #expect(credentials["userid"] == "7096700219496368135")
        #expect(client.verificationWebView == nil && !client.isLoggedIn)
    }
    @Test func cancelledSecondVerificationCannotCompleteLogin() async throws {
        let client = api("mfa", verification: { _ in throw QishuiPassportError.verificationCancelled })
        let qr = try await client.qrCode()
        await #expect(throws: Error.self) { try await client.pollQRCode(token: qr.token) }
        #expect(!client.isLoggedIn && client.verificationWebView == nil)
    }
    @Test func cancelledQRWhileVerifyingCannotSaveALateSession() async throws {
        var candidate: QishuiMusicAPI?
        candidate = api("mfa", verification: { _ in candidate?.cancelLogin() })
        let client = try #require(candidate), qr = try await client.qrCode()
        await #expect(throws: CancellationError.self) { try await client.pollQRCode(token: qr.token) }
        #expect(!client.isLoggedIn)
    }
    @Test func verificationParametersAndOriginsAreRestricted() throws {
        #expect(try QishuiMusicAPI.verificationParameters("verify_ticket=a%2Bb&token=bad") == ["verify_ticket": "a+b"])
        #expect(try QishuiMusicAPI.verificationParameters("").isEmpty)
        #expect(throws: Error.self) { try QishuiMusicAPI.verificationParameters("not a parameter object") }
        #expect(QishuiPassportSession.isOfficialVerificationURL(URL(string: "https://verify.zijieapi.com/component.js")!))
        #expect(!QishuiPassportSession.isOfficialVerificationURL(URL(string: "https://verify.zijieapi.com.example.com/component.js")!))
        #expect(!QishuiPassportSession.isOfficialVerificationURL(URL(string: "http://verify.zijieapi.com/component.js")!))
    }
    @Test func verificationURLAcceptsStringAndHostPathDecisions() {
        #expect(QishuiPassportSession.verificationURL("https://lf3-cdn.bytegoofy.com/verify.js")?.absoluteString == "https://lf3-cdn.bytegoofy.com/verify.js")
        #expect(QishuiPassportSession.verificationURL("/passport/verify.js")?.absoluteString == "https://api.qishui.com/passport/verify.js")
        #expect(QishuiPassportSession.verificationURL(["host": "lf3-cdn.bytegoofy.com", "path": "obj/verify.js"])?.absoluteString == "https://lf3-cdn.bytegoofy.com/obj/verify.js")
        #expect(QishuiPassportSession.verificationURL(["host": "https://sf.zijieapi.com", "path": "/v.js"])?.absoluteString == "https://sf.zijieapi.com/v.js")
        #expect(QishuiPassportSession.verificationURL(["host": "evil.example", "path": "/v.js"]) == nil)
        #expect(QishuiPassportSession.verificationURL(["host": "api.qishui.com@evil.example", "path": "/v.js"]) == nil)
        #expect(QishuiPassportSession.verificationURL(["host": "evil.example/x.zijieapi.com", "path": "/v.js"]) == nil)
        #expect(QishuiPassportSession.verificationURL("https://api.qishui.com:443@evil.example/v.js") == nil)
        #expect(QishuiPassportSession.verificationURL(nil) == nil)
        #expect(QishuiPassportSession.verificationURL(42) == nil)
    }
    @Test func verificationBridgeOnlyForwardsAllowlistedRequests() throws {
        #expect(QishuiPassportSession.isBridgeableVerificationURL(URL(string: "https://auth.zijieapi.com/a")!))
        #expect(QishuiPassportSession.isBridgeableVerificationURL(URL(string: "https://bff-pc.qishui.com/b")!))
        #expect(!QishuiPassportSession.isBridgeableVerificationURL(URL(string: "https://api.qishui.com/passport/web/x")!))
        #expect(!QishuiPassportSession.isBridgeableVerificationURL(URL(string: "http://auth.zijieapi.com/a")!))
        #expect(!QishuiPassportSession.isBridgeableVerificationURL(URL(string: "https://auth.zijieapi.com:8443/a")!))
        #expect(!QishuiPassportSession.isBridgeableVerificationURL(URL(string: "https://x@auth.zijieapi.com/a")!))
        #expect(QishuiVerificationBridge.request(from: ["url": "https://evil.example/a"]) == nil)
        #expect(QishuiVerificationBridge.request(from: ["url": "https://auth.zijieapi.com/a", "method": "DELETE"]) == nil)
        let request = try #require(QishuiVerificationBridge.request(from: [
            "url": "https://auth.zijieapi.com/a", "method": "post", "body": "x=1",
            "headers": ["Cookie": "stolen=1", "X-Tt-Passport-Csrf-Token": "c", "Origin": "https://evil.example"]]))
        #expect(request.httpMethod == "POST" && request.httpBody == Data("x=1".utf8))
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Tt-Passport-Csrf-Token") == "c")
        #expect(request.value(forHTTPHeaderField: "Origin") == "https://api.qishui.com")
        let cookie = { (domain: String) in HTTPCookie(properties: [.domain: domain, .path: "/", .name: "n", .value: "v"])! }
        let matched = QishuiVerificationBridge.cookies([cookie(".zijieapi.com"), cookie("api.qishui.com"), cookie(".evilzijieapi.com")], matching: URL(string: "https://auth.zijieapi.com/a")!)
        #expect(matched.map(\.domain) == [".zijieapi.com"])
    }
    @Test func verificationDiagnosticOmitsQueryValues() throws {
        let detail = QishuiPassportSession.decisionDiagnostic(["url": "https://sf.zijieapi.com/v.js?ticket=SECRET", "verify_ticket": "SECRET", "verify_from": "verify"])
        #expect(detail["urlHost"] as? String == "sf.zijieapi.com" && detail["urlPath"] as? String == "/v.js")
        #expect(detail["urlAccepted"] as? Bool == true && detail["keys"] as? [String] == ["url", "verify_from", "verify_ticket"])
        let object = QishuiPassportSession.decisionDiagnostic(["url": ["host": "a.bytegoofy.com", "path": "/x.js?t=SECRET"]])
        #expect(object["urlType"] as? String == "object" && object["urlPath"] as? String == "/x.js")
        #expect(QishuiPassportSession.decisionDiagnostic([:])["urlType"] as? String == "missing")
        let text = String(describing: [detail, object])
        #expect(!text.contains("SECRET"))
        let error = NSError(domain: "WKErrorDomain", code: 4, userInfo: ["WKJavaScriptExceptionMessage": "Error: load https://a.com/x.js?token=SECRET failed"])
        #expect(QishuiPassportSession.diagnosticText(error) == "Error: load https://a.com/x.js failed")
    }
    @Test func bundledReactMatchesItsPinnedHashes() throws {
        for asset in QishuiPassportSession.reactAssets {
            #expect(try QishuiPassportSession.bundledScript(asset.name, sha256: asset.sha256).contains("React v17.0.2"))
        }
        #expect(throws: Error.self) { try QishuiPassportSession.bundledScript("react.production.min", sha256: "wrong") }
    }
    @Test func securitySeedAndQRExpiryFollowTheProtocol() throws {
        let seed = try QishuiPassportSession.securitySeed()
        #expect(seed.count == 120 && seed.hasSuffix("=="))
        #expect(seed != (try QishuiPassportSession.securitySeed()))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(QishuiMusicAPI.qrExpiration(180, now: now) == now.addingTimeInterval(180))
        #expect(QishuiMusicAPI.qrExpiration(1_900_000_000, now: now).timeIntervalSince1970 == 1_900_000_000)
    }
    @Test func passportDiagnosticsCannotEchoResponseOrCredentialSecrets() throws {
        let entry = QishuiMusicAPI.passportDiagnostic(path: "/passport/web/check_qrconnect/?token=path-secret", body: ["data": ["status": "sessionid=status-secret", "error_code": 7, "description": "token=body-secret"]], cookie: "sessionid=cookie-secret; passport_csrf_token=csrf-secret")
        let text = String(decoding: try JSONSerialization.data(withJSONObject: entry), as: UTF8.self)
        #expect(entry["status"] as? String == "unrecognized")
        #expect(entry["code"] as? Int == 7)
        #expect(entry["hasSession"] as? Bool == true)
        for secret in ["path-secret", "status-secret", "body-secret", "cookie-secret", "csrf-secret"] { #expect(!text.contains(secret)) }
    }
    @Test func scanURLReplacesDeadWebpageAndPreservesEncodedScanToken() throws {
        let url = try QishuiMusicAPI.scanLoginURL(indexURL: "https://bff-pc.qishui.com/ucenter_web/app/sdk-next?token=a%2Bb%2Fc%3D&next_url=https%3A%2F%2Fexample.com")
        #expect(url.host == "bff-pc.qishui.com")
        #expect(url.path == "/light/invoke/scan_login")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "token" }?.value == "a+b/c=")
        #expect(url.absoluteString.contains("%2B"))
        #expect(!items.contains { $0.name == "next_url" })
        #expect(throws: Error.self) { try QishuiMusicAPI.scanLoginURL(indexURL: "https://example.com/?token=scan") }
        #expect(throws: Error.self) { try QishuiMusicAPI.scanLoginURL(indexURL: "https://bff-pc.qishui.com/?token=") }
    }
    @Test func httpSuccessWithBusinessRejectionIsAnError() async {
        await #expect(throws: Error.self) { try await api("reject").recommendedPlaylists(limit: 5) }
    }
    @Test func playlistUsesOpaqueCursorAndDeduplicatesSongs() async throws {
        let songs = try await api().playlistSongs(.init(playlistID: "7096700219496368135", type: 3))
        #expect(songs.map { $0.qishui?.trackID } == ["7079108541549643812", "7079108541549643813"])
        #expect(songs.first?.duration == 218.133)
    }
    @Test func accountPlaylistUsesSessionAndDistinguishesMissingTracksFromEmptyPlaylist() async throws {
        let reference = QishuiPlaylistReference(playlistID: "7096700219496368135", type: 0)
        let client = api("accountPlaylist")
        try client.restore(["userid": "fixture-user", "sessionid": "confirmed-session"])
        #expect(try await client.playlistSongs(reference).map { $0.qishui?.trackID } == ["7079108541549643812"])
        #expect(try await api("emptyPlaylist").playlistSongs(reference).isEmpty)
        await #expect(throws: QishuiError.self) { try await api("missingPlaylistTracks").playlistSongs(reference) }
    }
    @Test func searchDoesNotInferCursorFromFilteredSongCount() async throws {
        let client = api()
        let first = try await client.search(keyword: "Fixture", playlists: false, limit: 1, offset: 0)
        let second = try await client.search(keyword: "Fixture", playlists: false, limit: 1, offset: 1)
        #expect(first.songs.first?.qishui?.trackID == "7079108541549643812")
        #expect(second.songs.first?.qishui?.trackID == "7079108541549643813")
        #expect(second.total == 2)
    }
    @Test func metadataSurvivesCheckpointWithoutRawResourceSecrets() throws {
        let song = try #require(QishuiMusicAPI.song(["id": "7079108541549643812", "name": "Fixture", "duration": 297240]))
        let bytes = try JSONEncoder().encode(song)
        let restored = try JSONDecoder().decode(ProviderSong.self, from: bytes)
        #expect(restored.source == .qishui && restored.qishui?.trackID == "7079108541549643812")
        #expect(restored.id < 0 && restored.duration == 297.24)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("audio_url"))
        #expect(QishuiMusicAPI.playlist(["id": "7096700219496368135", "type": 3])?.qishui?.playlistID == "7096700219496368135")
    }
    @Test func missingMembershipIsUnknownAndStringZeroIsNotVIP() {
        #expect(QishuiMusicAPI.membership([:]) == .unknown)
        #expect(QishuiMusicAPI.membership(["is_vip": "0"]) == .none)
        #expect(QishuiMusicAPI.membership(["is_vip": true]) == .qishuiVIP)
    }
    @Test func shortLyricsArePreserved() async throws {
        #expect(try await api().lyric(trackID: "id").lrc?.lyric?.contains("想你") == true)
    }
    private func player(duration: Double, spade: String = "", url: String = "https://audio.douyinvod.com/track.m4a") throws -> [String: Any] {
        let model: [String: Any] = ["video_duration": duration, "video_list": [["main_url": url, "spade_a": spade, "video_meta": ["bitrate": 128000]]]]
        return ["video_model": String(decoding: try JSONSerialization.data(withJSONObject: model), as: UTF8.self)]
    }
    @Test(arguments: ["wordLyrics", "pcOriginalLyrics", "androidLyrics"])
    func translatedLyricsPreserveWordTiming(mode: String) async throws {
        let response = try await api(mode).lyric(trackID: "7079108541549643812")
        #expect(response.lrc?.lyric == "[00:01.010]Hello")
        #expect(response.tlyric?.lyric == "[00:01.01]你好")
        let line = try #require(LyricsParser.parse(response).lines.first)
        #expect(line.translation == "你好")
        #expect(line.words?.map(\.start) == [1.01, 1.41])
        #expect(line.words?.map(\.text) == ["Hel", "lo"])
    }

    @Test func previewAndUntrustedURLAreRejectedWhileEncryptionIsPreserved() throws {
        let track: [String: Any] = ["duration": 297240]
        #expect(throws: Error.self) { try QishuiMusicAPI.playbackResource(track: track, player: player(duration: 30)) }
        #expect(try QishuiMusicAPI.playbackResource(track: track, player: player(duration: 297.24, spade: "encrypted")).playAuth == "encrypted")
        #expect(throws: Error.self) { try QishuiMusicAPI.playbackResource(track: track, player: player(duration: 297.24, url: "https://example.com/a.m4a")) }
        #expect(try QishuiMusicAPI.playbackResource(track: track, player: player(duration: 297.24)).durationMS == 297240)
    }
    @Test func aacWithHiResLabelIsRankedAsLossy() throws {
        let track: [String: Any] = ["duration": 297240]
        let aac: [String: Any] = ["main_url": "https://audio.douyinvod.com/aac.m4a", "quality": "hi_res",
                                   "format": "m4a", "video_meta": ["codec_type": "aac", "real_bitrate": 320]]
        let flac: [String: Any] = ["main_url": "https://audio.douyinvod.com/lossless.m4a", "quality": "lossless",
                                    "format": "flac", "sample_rate": 44_100, "bit_depth": 16, "bitrate": 900_000]
        let aacOnly: [String: Any] = ["video_model": ["video_duration": 297.24, "video_list": [aac]]]
        let aacStream = try QishuiMusicAPI.playbackResource(track: track, player: aacOnly)
        #expect(aacStream.level == .exhigh)
        #expect(aacStream.bitrate == 320_000)
        let both: [String: Any] = ["video_model": ["video_duration": 297.24, "video_list": [aac, flac]]]
        #expect(try QishuiMusicAPI.playbackResource(track: track, player: both).level == .lossless)
    }

    @Test(arguments: [2_400_000, 0])
    func verifiedHiResOptionIncludesBitrate(br: Int) throws {
        let payload = Data(#"{"id":42,"level":"hires","br":\#(br),"size":45000000,"time":180000}"#.utf8)
        let option = try JSONDecoder().decode(SongURLData.self, from: payload).qishuiQualityOption
        #expect(option?.quality == .hires)
        #expect(option?.title == (br > 0 ? "Hi-Res · 2400 kbps" : "Hi-Res · 约2000 kbps"))
    }

    @Test func localHiResOptionUsesFileBitrate() throws {
        let url = try #require(Bundle.module.url(forResource: "offline", withExtension: "flac", subdirectory: "Fixtures"))
        let level = AudioQualityCheck.localLevel(url: url, reported: AudioQuality.lossless.rawValue)
        let option = AudioQualityOption.qishuiLocal(url: url, level: level, duration: 3)
        #expect(option?.quality == .hires)
        #expect(option?.title == "Hi-Res · 811.2 kbps")
    }

    @Test func previewTriggersSignedPCPlaybackForLoggedInAccount() async throws {
        let client = api("signedStream")
        try client.restore(["userid": "fixture-user", "sessionid": "confirmed-session"])
        let count = QishuiFixture.signedPlaybackRequestCount
        async let preload = client.playback(trackID: "track", quality: .standard)
        async let playback = client.playback(trackID: "track", quality: .standard)
        let (result, reused) = try await (preload, playback)
        #expect(reused.url == result.url)
        #expect(QishuiFixture.signedPlaybackRequestCount == count + 1)
        #expect(result.durationMS == 297240)
        #expect(result.url == "https://audio.douyinvod.com/track.m4a")
        #expect(result.level == .standard)
        let highest = try await client.playback(trackID: "track")
        #expect(highest.url == "https://audio.douyinvod.com/higher.m4a")
        #expect(highest.level == .higher)
    }
    @Test func artistOverviewKeepsHotSongsFirstAndFillsFromTrackPages() async throws {
        let (artist, tracks) = try await api().artistDetail("789")
        #expect(artist?.name == "Artist")
        #expect(tracks.compactMap { $0.qishui?.trackID } == ["22", "21", "23"])
    }

    @Test func artistContentUsesServerCursorsAndKeepsUnconsumedItems() async throws {
        let client = api()
        let albums = try await client.artistContent("789", kind: .albums, limit: 60, offset: 0)
        #expect(albums.items.map { QishuiMusicAPI.string($0["id"]) } == ["11", "12"])
        #expect(albums.items.first.flatMap(QishuiMusicAPI.albumMetadata)?.releaseDateMS == 1_782_000_000_000)
        #expect(!albums.hasMore)
        let first = try await client.artistContent("789", kind: .tracks, limit: 1, offset: 0)
        #expect(first.items.map { QishuiMusicAPI.string($0["id"]) } == ["21"])
        #expect(first.hasMore)
        let second = try await client.artistContent("789", kind: .tracks, limit: 2, offset: 1)
        #expect(second.items.map { QishuiMusicAPI.string($0["id"]) } == ["22", "23"])
        #expect(!second.hasMore)
    }
    @Test func loginAvatarAcceptsAlternateProfileFields() {
        let signed = "https://p3-passport.byteacctimg.com/img/user-avatar/fixture~300x300.image?x-expires=1&x-signature=abc%3D"
        #expect(QishuiMusicAPI.profileAvatar(["avatar_thumb": ["url_list": [], "urls": [signed], "uri": "fixture"]]) == signed)
        #expect(QishuiMusicAPI.profileAvatar(["medium_avatar_url": ["uri": "only-uri"], "avatar_url": signed]) == signed)
        #expect(QishuiMusicAPI.profileAvatar(["id": "1"]).isEmpty)
        let credentials = QishuiMusicAPI.loginCredentials(sessionID: "s", profile: ["id": "1", "avatar_url": signed])
        #expect(credentials["avatar"] == signed)
    }
    @Test func signedByteDanceAvatarKeepsQueryWhenResized() {
        let signed = "https://p3-passport.byteacctimg.com/img/user-avatar/fixture~300x300.image?x-expires=1&x-signature=abc%3D"
        let resized = signed.resizedImageURL(80)
        #expect(resized?.query(percentEncoded: true) == "x-expires=1&x-signature=abc%3D")
        #expect(resized?.imageSourceURL.absoluteString == signed)
    }
    @Test func artworkUsesCDNTemplateAndKeepsArtistAndAlbumReferences() throws {
        let cover = ["uri": "tos-cn-v-2774c002/fixture-cover", "template_prefix": "tplv-example"]
        let avatar: [String: Any] = ["urls": ["https://p3-luna.douyinpic.com/img/fixture-avatar"], "uri": "fixture-avatar"]
        let song = try #require(QishuiMusicAPI.song(["id": "123", "name": "Track",
            "album": ["id": "456", "name": "Album", "url_cover": cover],
            "artists": [["id": "789", "name": "Artist", "url_avatar": avatar]]]))
        #expect(song.coverURL?.absoluteString == "https://p3-luna.douyinpic.com/img/tos-cn-v-2774c002/fixture-cover~tplv-example-resize:960:960.png")
        #expect(song.qishui?.albumID == "456")
        #expect(song.qishui?.artists?.first?.coverURL?.absoluteString == "https://p3-luna.douyinpic.com/img/fixture-avatar")
    }
    @MainActor @Test func listeningModeAndRadioQueuesUseSignedPCRequestsAndContinue() async throws {
        let client = api("signedFeed", now: { Date(timeIntervalSince1970: 1_800_000_000) })
        try client.restore(["userid": "fixture-user", "sessionid": "confirmed-session"])
        let scenes = try await client.listeningScenes()
        #expect(scenes.map(\.mode) == ["default", "familiar", "fresh", "scene_mode_emo"])
        let defaults = try await client.feedPage(client.feedState(.scene(scenes[0])))
        #expect(defaults.songs.first?.qishui?.trackID == "7079108541549643814")
        let first = try await client.feedPage(client.feedState(.scene(scenes[1])))
        let song = try #require(first.songs.first)
        #expect(song.qishui?.trackID == "7079108541549643812")
        let track = try PlatformMusicAPI.decode(Track.self, [
            "id": -1, "name": song.name, "dt": Int(song.duration * 1000),
            "platformSong": JSONSerialization.jsonObject(with: JSONEncoder().encode(song))
        ])
        let played = try #require(QishuiPlayedMedia(track: track, position: 15))
        let continued = try await client.continueFeed(first.state, excluding: [played.id], played: [played])
        #expect(continued.songs.map { $0.qishui?.trackID } == ["7079108541549643815"])
        #expect(continued.state.requestCount == 3)
        let switched = try await client.continueFeed(client.feedState(.scene(scenes[1])),
                                                     excluding: [played.id], played: [played])
        #expect(switched.songs.map { $0.qishui?.trackID } == ["7079108541549643815"])
        #expect(switched.state.requestCount == 3)
        let radios = try await client.discoveryRadios()
        #expect(radios.map(\.name) == ["Fixture radio"])
        let radio = try #require(radios.first?.qishui)
        let reference = try #require(radio.radio)
        let radioPage = try await client.feedPage(client.feedState(.radio(id: radio.playlistID, reference)))
        #expect(radioPage.songs.first?.qishui?.trackID == "7079108541549643813")
        let radioNext = try await client.continueFeed(radioPage.state, excluding: [], played: [])
        #expect(radioNext.songs.first?.qishui?.trackID == "7079108541549643816")
        #expect(!radioNext.state.hasMore)
    }

    @Test func playlistDiscoveryPaginatesWithFullPrecisionExposureIDs() async throws {
        let client = api()
        let first = try await client.discoveryPlaylists(excluding: [])
        #expect(first.items.map(\.name) == ["Fixture playlist"])
        #expect(first.exposureIDs == [7096700219496368135])
        #expect(first.hasMore)
        let second = try await client.discoveryPlaylists(excluding: first.exposureIDs)
        #expect(second.items.map(\.name) == ["Next playlist"])
        #expect(!second.hasMore)
    }
    @Test func spadeAndCENCDecryptIntoLocalAudio() throws {
        func hex(_ text: String) -> Data {
            let digits = Array(text)
            return Data(stride(from: 0, to: digits.count, by: 2).map { UInt8(String(digits[$0...$0 + 1]), radix: 16)! })
        }
        func box(_ type: String, _ payload: Data) -> Data {
            let size = UInt32(payload.count + 8).bigEndian
            return withUnsafeBytes(of: size) { Data($0) } + Data(type.utf8) + payload
        }

        let auth = "kL0dxVO+G/JSvhvxYo0ex2SLHPJivCvxer4y706RA+5Ol1mA"
        let key = try QishuiAudio.key(from: auth)
        #expect(key == hex("2b7e151628aed2a6abf7158809cf4f3c"))
        #expect(throws: QishuiError.self) { try QishuiAudio.key(from: "AAAA") }

        let iv = hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
        let encrypted = hex("874d6191b620e3261bef6864990db6ce")
        let plaintext = hex("6bc1bee22e409f96e93d7e117393172a")
        let size = box("stsz", hex("000000000000001000000001"))
        let sample = box("senc", hex("0000000000000001") + iv)
        let trackEncryption = box("tenc", hex("0000000000000110"))
        let protection = box("sinf", box("frma", Data("fLaC".utf8)) + box("schi", trackEncryption))
        let entry = box("enca", Data(count: 28) + protection)
        let description = box("stsd", hex("0000000000000001") + entry)
        let movie = box("moov", box("trak", box("mdia", box("minf", box("stbl", description + size + sample)))))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("input")
        let output = temporary.appendingPathComponent("output")
        try (box("mdat", encrypted) + movie).write(to: source)
        try QishuiAudio.decryptFile(source, to: output, key: key)
        let actual = try Data(contentsOf: output)
        #expect(actual.prefix(24) == box("mdat", plaintext))
        #expect(actual.range(of: Data("enca".utf8)) == nil)
        #expect(actual.range(of: Data("fLaC".utf8)) != nil)
    }
    @Test func capabilitiesHideUnsupportedNavigationAndMutations() {
        #expect(MusicProvider.qishui.homeDiscoverySlots == [.radios])
        #expect(MusicProvider.qishui.exploreCategories == ["全部", "推荐歌单"])
        #expect(SearchViewModel.supports(.playlists, provider: .qishui))
        #expect(SearchViewModel.supports(.artists, provider: .qishui))
        #expect(SearchViewModel.supports(.albums, provider: .qishui))
        #expect(MusicProvider.qishui.supportsFavoriteChanges)
        #expect(MusicProvider.qishui.supports(.likedSongs))
        for feature: MusicServiceFeature in [.playlistCreation, .playlistDeletion, .playlistTrackAddition, .playlistChanges, .searchSuggestions, .playlistSubscriptions, .collectionAlbums, .collectionArtists, .recentPlays, .playbackReporting] {
            #expect(MusicProvider.qishui.supports(feature))
        }
        for feature: MusicServiceFeature in [.downloads, .dailySongs, .personalFM, .cloud] {
            #expect(!MusicProvider.qishui.supports(feature))
        }
    }

    @Test func playlistFallsBackToTypedAppRouteAndUsesReturnedMetadata() async throws {
        let response = try await api("playlistFallback").playlistDetail(.init(playlistID: "7096700219496368135", type: 3))
        #expect(response.playlist?.name == "Recovered playlist")
        #expect(response.songs.map { $0.qishui?.trackID } == ["7079108541549643812"])
    }

    @Test(arguments: ["createPlaylist", "createPlaylistNested"])
    func playlistCreationAcceptsServerIDsAndKeepsOwnership(mode: String) async throws {
        let client = api(mode)
        try client.restore(["userid": "fixture", "sessionid": "confirmed-session"])
        let playlist = try await client.createPlaylist(name: " 夜间歌单\n", isPrivate: mode == "createPlaylistNested")
        #expect(playlist.qishui?.playlistID == "7096700219496368135")
        #expect(playlist.name == "夜间歌单")
        #expect(playlist.ownerID == "fixture" && playlist.isOwned == true)
    }

    @Test func playlistCreationRejectsInvalidNamesAndFailedResponses() async throws {
        let client = api("createPlaylistRejected")
        let missingID = api("createPlaylistMissingID")
        for api in [client, missingID] { try api.restore(["userid": "fixture", "sessionid": "confirmed-session"]) }
        do {
            _ = try await client.createPlaylist(name: String(repeating: "歌", count: 31), isPrivate: false)
            Issue.record("Names beyond the service limit must be rejected locally")
        } catch QishuiError.invalidPlaylistName { }
        do {
            _ = try await client.createPlaylist(name: "夜间歌单", isPrivate: false)
            Issue.record("A rejected creation must not report success")
        } catch QishuiError.business(1000014) { }
        do {
            _ = try await missingID.createPlaylist(name: "夜间歌单", isPrivate: false)
            Issue.record("A creation without a playlist ID must not report success")
        } catch QishuiError.invalidResponse { }
    }

    @Test func collectionRequestsUseOriginalIDsAndReadPaginatedResults() async throws {
        let client = api("signedCollections")
        try client.restore(["userid": "fixture", "sessionid": "confirmed-session"])
        for kind: QishuiMusicAPI.CollectionKind in [.playlist, .album, .artist] {
            try await client.setCollection(kind, id: "7096700219496368135", saved: true)
            try await client.setCollection(kind, id: "7096700219496368135", saved: false)
        }
        let playlists = try await client.collectionItems(.playlist)
        #expect(playlists.compactMap { $0["id"] as? String } == ["7096700219496368135", "7096700219496368136"])
        #expect(try await client.collectionItems(.album).isEmpty)
        let artists = try await client.collectionItems(.artist)
        #expect(artists.first?["name"] as? String == "Fixture artist")
    }

    @Test func favoriteWritesUseSignedRequestsAndPropagateRejection() async throws {
        let client = api("signedFavorites")
        try client.restore(["userid": "fixture", "sessionid": "confirmed-session"])
        try await client.setLiked(trackID: "7079108541549643812", liked: true)
        do {
            try await client.setLiked(trackID: "7079108541549643812", liked: false)
            Issue.record("A rejected removal must not report success")
        } catch QishuiError.business(1000004) { }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODA_QISHUI_COMMENTS_LIVE"] == "1"))
    func anonymousLiveComments() async throws {
        let client = QishuiMusicAPI()
        let id = "7501674235158431760"
        let hot = try await client.comments(trackID: id, sort: .hot, offset: 0, limit: 20)
        let more = try await client.comments(trackID: id, sort: .hot, offset: 20, limit: 20)
        let latest = try await client.comments(trackID: id, sort: .latest, offset: 0, limit: 20)
        let first = try #require(hot.hotComments.first)
        #expect(hot.more == true && (hot.total ?? 0) > 20)
        #expect(!first.content.isEmpty && first.likedCount > 0 && first.time > 1_700_000_000_000)
        #expect(more.hotComments.count == 20)
        #expect(Set(hot.hotComments.map(\.id)).isDisjoint(with: more.hotComments.map(\.id)))
        let newest = try #require(latest.comments.first)
        #expect(newest.time > first.time)
        let empty = try await client.comments(trackID: "1", sort: .hot, offset: 0, limit: 20)
        #expect(empty.comments.isEmpty && empty.total == 0 && empty.more == false)
    }
    @Test func qishuiTracksLookElsewhereButNeverOnQishui() async throws {
        let song = try #require(QishuiMusicAPI.song(["id": "7079108541549643812", "name": "Fixture"]))
        let bytes = try JSONEncoder().encode(song)
        let object = try JSONSerialization.jsonObject(with: bytes)
        let track = try PlatformMusicAPI.decode(Track.self, ["id": song.id, "name": song.name, "platformSong": object])
        let query = UnblockQuery(track: track)
        #expect(query.origin == .qishui)
        #expect(query.neteaseID == nil)
        // Every other source is excluded, so nothing may be tried — Qishui least of all.
        let result = await UnblockResolver.resolve(track, quality: .exhigh,
                                                   excluding: [.mirror, .parser, .netease, .qq, .kugou])
        #expect(result.source == nil && result.attemptedSources.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODA_QISHUI_LIVE"] == "1"))
    func anonymousLiveRead() async throws {
        let client = QishuiMusicAPI()
        let lists = try await client.recommendedPlaylists(limit: 5)
        #expect(!lists.isEmpty)
        let songs = try await client.playlistSongs(.init(playlistID: "7096700219496368135", type: 3))
        #expect(songs.count >= 22)
        let response = try await client.lyric(trackID: "7079108541549643812")
        #expect(!LyricsParser.parse(response).lines.isEmpty)
        let qr = try await client.qrCode()
        #expect(qr.image.hasPrefix("data:image/"))
        #expect(client.passportSignatureLength == 44)
        #expect(client.passportMSLength == 120)
        #expect(client.passportTokenMatches == true)
        #expect((client.passportBrowserInfoLength ?? 0) > 0)
        guard case .waiting = try await client.pollQRCode(token: qr.token) else { Issue.record("Fresh QR should be waiting"); return }
        #expect(client.passportSignatureLength == 44)
        #expect(client.passportMSLength == 120 && client.passportTokenMatches == true)
        client.cancelLogin()
        do {
            _ = try await client.playback(trackID: "7079108541549643812")
            Issue.record("The known anonymous preview must not be accepted as a full track")
        } catch QishuiError.previewOnly { }
        do {
            let page = try await client.search(keyword: "周杰伦", playlists: false, limit: 5, offset: 0)
            #expect(page.songs.count == 5)
            let next = try await client.search(keyword: "周杰伦", playlists: false, limit: 5, offset: 20)
            #expect(!next.songs.isEmpty)
            #expect(Set(page.songs.map(\.id)).isDisjoint(with: next.songs.map(\.id)))
            print("Qishui native anonymous search: \(page.songs.count) songs, next page \(next.songs.count)")
        } catch QishuiError.business(let code) {
            print("Qishui native anonymous search rejected by upstream: \(code)")
        }
        print("Qishui native live read: \(lists.count) playlists, \(songs.count) playlist tracks; lyrics, QR image and preview rejection verified")
    }
}
