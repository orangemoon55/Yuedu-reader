import AVFoundation
import CoreVideo
import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

/// Offline only. Synthetic CatVod JSON exercises the production factory; the only bytes
/// AVPlayer opens are the repository's existing ten-second landscape MP4. No source is activated.
@Suite("CatVod native detail and offline playback flow", .serialized)
@MainActor
struct CatVodPlaybackFlowTests {
    private let sourceID = "fixture-source"
    private let siteKey = "fixture-site"
    private let videoID = "fixture-video"
    private let detailJSON = #"""
    {"list":[{"vod_id":"fixture-video","vod_name":"Fixture Series","vod_pic":"",
      "vod_year":"2026","vod_area":"Fixture Area","vod_remarks":"Fixture Facts",
      "vod_actor":"Fixture Cast","vod_content":"A short offline fixture summary.",
      "vod_play_from":"primary$$$backup",
      "vod_play_url":"Primary episode$primary-id$$$Backup episode$backup-id#Backup finale$backup-finale"}]}
    """#

    private func video() throws -> CatVodVideo {
        try CatVodContentParser.detail(Data(detailJSON.utf8))
    }

    private func makeStream(_ json: String, route: CatVodRoute, episode: CatVodEpisode,
                        source: String? = nil, site: String? = nil,
                        resolve: (String) throws -> URL) throws -> VideoStream {
        try CatVodPlaybackFactory.stream(data: Data(json.utf8), sourceID: source ?? sourceID,
                                         siteKey: site ?? siteKey, videoID: videoID,
                                         flag: route.flag, episode: episode, resolveURL: resolve)
    }

    @Test("selected CatVod route reaches the real factory with safe headers and a stable private resume key")
    func selectedRoutePipeline() throws {
        let detail = try video()
        let selected = try #require(detail.routes.first { $0.flag == "backup" })
        let episode = try #require(selected.episodes.first)
        #expect(episode.playID == "backup-id")
        #expect(episode.id == "route-2-episode-1")
        let json = #"""
        {"parse":0,"url":"https://media.example.invalid/backup.mp4?token=one",
         "header":{"User-Agent":"Fixture Player","Referer":"https://source.example.invalid/",
                   "Origin":"https://source.example.invalid","Accept":"video/*","Accept-Language":"en",
                   "Cookie":"not-a-real-cookie","Authorization":"not-a-real-token","Host":"wrong.invalid",
                   "X-Private":"discard","referer":"bad\r\nX-Injected: true"}}
        """#
        var resolved: [String] = []
        let first = try makeStream(json, route: selected, episode: episode) {
            resolved.append($0)
            return try #require(URL(string: $0))
        }
        #expect(resolved == ["https://media.example.invalid/backup.mp4?token=one"])
        #expect(first.headers == ["User-Agent": "Fixture Player", "Referer": "https://source.example.invalid/",
                                  "Origin": "https://source.example.invalid", "Accept": "video/*", "Accept-Language": "en",
                                  "Cookie": "not-a-real-cookie", "Authorization": "not-a-real-token"])
        let key = try #require(first.resumeKey)
        #expect(key.scheme == "readcc-catvod")
        #expect(key.host == "episode")
        #expect(key.lastPathComponent.count == 64)
        #expect(key.query == nil)
        #expect(!key.absoluteString.contains("token"))
        #expect(!key.absoluteString.contains(sourceID))
        let refreshed = try makeStream(json.replacingOccurrences(of: "token=one", with: "token=two"),
                                   route: selected, episode: episode) { try #require(URL(string: $0)) }
        #expect(first.url != refreshed.url)
        #expect(first.resumeKey == refreshed.resumeKey)
        let otherRoute = try #require(detail.routes.first)
        let otherEpisode = try #require(otherRoute.episodes.first)
        #expect(try makeStream(json, route: otherRoute, episode: otherEpisode) { try #require(URL(string: $0)) }.resumeKey != key)
        #expect(try makeStream(json, route: selected, episode: selected.episodes[1]) { try #require(URL(string: $0)) }.resumeKey != key)
        #expect(try makeStream(json, route: selected, episode: episode, source: "different-source") { try #require(URL(string: $0)) }.resumeKey != key)
        #expect(try makeStream(json, route: selected, episode: episode, site: "different-site") { try #require(URL(string: $0)) }.resumeKey != key)
    }

    @Test("alias detail routes reach the production stream factory without losing playback headers")
    func aliasDetailPlaybackHeaders() throws {
        let detailJSON = #"{"data":{"videos":[{"title":"两京十五日","play_from":"quark$$$uc","play_url":"Share$quark://pan.example/s/A%2FB?pwd=x%23y%24z$tail$$$4K$https://media.example.invalid/4k.m3u8"}]}}"#
        let detail = try CatVodContentParser.detail(Data(detailJSON.utf8))
        #expect(detail.id == "route:两京十五日")
        let route = try #require(detail.routes.first { $0.flag == "quark" })
        let episode = try #require(route.episodes.first)
        #expect(episode.playID == "quark://pan.example/s/A%2FB?pwd=x%23y%24z$tail")

        var resolved: [String] = []
        let stream = try CatVodPlaybackFactory.stream(
            data: Data(#"{"url":"https://media.example.invalid/4k.m3u8","headers":{"Referer":"https://source.example.invalid/","User-Agent":"Fixture Player"}}"#.utf8),
            sourceID: sourceID, siteKey: siteKey, videoID: detail.id, flag: route.flag, episode: episode
        ) {
            resolved.append($0)
            return try #require(URL(string: $0))
        }
        #expect(resolved == ["https://media.example.invalid/4k.m3u8"])
        #expect(stream.headers == ["Referer": "https://source.example.invalid/", "User-Agent": "Fixture Player"])
    }

    @Test("CatVod web-parser flags are refused before resolving or opening any URL")
    func refusesWebParsing() throws {
        let route = try #require(try video().routes.first)
        let episode = try #require(route.episodes.first)
        for json in [#"{"parse":1,"url":"https://parse.example.invalid/player"}"#,
                     #"{"jx":true,"url":"https://parse.example.invalid/player"}"#,
                     #"{"jx":1,"url":"https://parse.example.invalid/player"}"#] {
            var resolutionCount = 0
            do {
                _ = try makeStream(json, route: route, episode: episode) {
                    resolutionCount += 1
                    return try #require(URL(string: $0))
                }
                Issue.record("A CatVod web-parser response was accepted")
            } catch {
                #expect((error as? CatVodUseError) == .parsePage)
                #expect(CatVodCatalog.message(error) == CatVodUseError.parsePage.localizedDescription)
            }
            #expect(resolutionCount == 0)
        }
    }

    @Test("DASH and runtime URL refusal retain their existing errors")
    func refusesDASHAndResolutionFailure() throws {
        let route = try #require(try video().routes.first)
        let episode = try #require(route.episodes.first)
        #expect(throws: VideoChapterLinkError.dashManifest) {
            try makeStream(#"{"url":"https://media.example.invalid/video.MPD?token=synthetic"}"#,
                       route: route, episode: episode) { try #require(URL(string: $0)) }
        }
        // The factory cannot swallow or replace the production runtime's ownership failure.
        let refusal = CatVodRuntimeError.badResponse("unowned loopback port")
        do {
            _ = try makeStream(#"{"url":"/proxy/episode.m3u8"}"#, route: route, episode: episode) { _ in throw refusal }
            Issue.record("Runtime URL refusal was swallowed")
        } catch {
            #expect(CatVodCatalog.message(error) == CatVodCatalog.message(refusal))
        }
        #expect(throws: CatVodContentError.self) {
            try makeStream(#"{"error":"fixture network failure"}"#, route: route, episode: episode) { try #require(URL(string: $0)) }
        }
    }

    private func identifier(_ object: NSObject) -> String {
        // SwiftUI elements can implement this getter without declaring the protocol.
        let getter = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
        return object.responds(to: getter) ? (object.value(forKey: "accessibilityIdentifier") as? String ?? "") : ""
    }

    private func element(_ id: String, in host: UIView) -> NSObject? {
        accessibilityElements(in: host).first { identifier($0) == id }
    }

    @Test("native detail exposes title, facts, summary, selected-route cards, play and bookmark actions")
    func nativeDetailAccessibility() async throws {
        let detail = try video()
        let route = try #require(detail.routes.last)
        let episode = try #require(route.episodes.first)
        var plays: [(String, String)] = []
        var bookmarks = 0
        let view = CatVodMovieDetailPresentation(
            detail: detail, poster: nil, selectedRoute: .constant(route.id),
            isResolving: false, isBookmarked: false, playFailure: nil, saveFailure: nil,
            onPlay: { plays.append(($0.playID, $1)) }, onBookmark: { bookmarks += 1 }
        )
        try await withAccessibilityHost(in: view, height: 2400) { host in
            let found = await eventually(host) {
                element("catvod.detail.episode.\(episode.id)", in: host) != nil
            }
            try #require(found)
            let elements = accessibilityElements(in: host)
            #expect(elements.contains { $0.accessibilityLabel == detail.title && $0.accessibilityTraits.contains(.header) })
            #expect(elements.contains { $0.accessibilityLabel?.contains(detail.year) == true
                && $0.accessibilityLabel?.contains(detail.area) == true })
            #expect(elements.contains { $0.accessibilityLabel == detail.actor })
            #expect(elements.contains { $0.accessibilityLabel == detail.summary })
            let routeControl = try #require(element("catvod.detail.route", in: host))
            #expect(routeControl.accessibilityLabel == localized("播放線路"))
            #expect(routeControl.accessibilityValue == route.name)
            #expect(routeControl.accessibilityFrame.height >= 44)
            let play = try #require(element("catvod.detail.play", in: host))
            #expect(play.accessibilityLabel == localized("開始播放"))
            #expect(play.accessibilityValue == episode.title)
            #expect(play.accessibilityFrame.width >= 44 && play.accessibilityFrame.height >= 44)
            #expect(play.accessibilityActivate())
            let card = try #require(element("catvod.detail.episode.\(episode.id)", in: host))
            #expect(card.accessibilityLabel == episode.title)
            #expect(card.accessibilityTraits.contains(.button))
            #expect(card.accessibilityFrame.width >= 44 && card.accessibilityFrame.height >= 44)
            #expect(card.accessibilityActivate())
            let bookmark = try #require(element("catvod.detail.bookmark", in: host))
            #expect(bookmark.accessibilityLabel == localized("加入媒體庫"))
            #expect(bookmark.accessibilityFrame.width >= 44 && bookmark.accessibilityFrame.height >= 44)
            #expect(bookmark.accessibilityActivate())
            #expect(plays.map(\.0) == ["backup-id", "backup-id"])
            #expect(plays.map(\.1) == ["backup", "backup"])
            #expect(bookmarks == 1)
            #expect(element("catvod.detail.episode.route-1-episode-1", in: host) == nil)
        }
    }

    @Test("resolving a stream disables duplicate play/card/route actions but keeps bookmark accessible")
    func pendingVisibility() async throws {
        let detail = try video()
        let route = try #require(detail.routes.first)
        let episode = try #require(route.episodes.first)
        var plays = 0
        let view = CatVodMovieDetailPresentation(
            detail: detail, poster: nil, selectedRoute: .constant(route.id),
            isResolving: true, isBookmarked: true, playFailure: nil, saveFailure: nil,
            onPlay: { _, _ in plays += 1 }, onBookmark: {}
        )
        try await withAccessibilityHost(in: view, height: 2400) { host in
            let found = await eventually(host) { element("catvod.detail.resolving", in: host) != nil }
            try #require(found)
            for id in ["catvod.detail.play", "catvod.detail.route", "catvod.detail.episode.\(episode.id)"] {
                let control = try #require(element(id, in: host))
                #expect(control.accessibilityTraits.contains(.notEnabled))
                if id != "catvod.detail.route" { _ = control.accessibilityActivate() }
            }
            #expect(plays == 0)
            let bookmark = try #require(element("catvod.detail.bookmark", in: host))
            #expect(bookmark.accessibilityLabel == localized("移除收藏"))
            #expect(!bookmark.accessibilityTraits.contains(.notEnabled))
        }
    }

    @Test("existing playback and bookmark failures remain visible verbatim in native detail")
    func detailErrorsRemainVisible() async throws {
        let detail = try video()
        let playError = CatVodCatalog.message(URLError(.notConnectedToInternet))
        let saveError = CocoaError(.fileWriteNoPermission).localizedDescription
        let view = CatVodMovieDetailPresentation(
            detail: detail, poster: nil, selectedRoute: .constant(""),
            isResolving: false, isBookmarked: false, playFailure: playError, saveFailure: saveError,
            onPlay: { _, _ in }, onBookmark: {}
        )
        try await withAccessibilityHost(in: view, height: 2400) { host in
            let found = await eventually(host) { element("catvod.detail.playError", in: host) != nil }
            try #require(found)
            #expect(element("catvod.detail.playError", in: host)?.accessibilityLabel == playError)
            #expect(element("catvod.detail.saveError", in: host)?.accessibilityLabel == saveError)
        }
    }

    @Test("empty episodes disable play; detail network failure retains a working retry and loading state")
    func emptyAndLoadStates() async throws {
        let empty = try CatVodContentParser.detail(Data(#"{"vod_id":"empty","vod_name":"Empty fixture"}"#.utf8))
        let view = CatVodMovieDetailPresentation(
            detail: empty, poster: nil, selectedRoute: .constant(""),
            isResolving: false, isBookmarked: false, playFailure: nil, saveFailure: nil,
            onPlay: { _, _ in Issue.record("Empty detail tried to play") }, onBookmark: {}
        )
        try await withAccessibilityHost(in: view, height: 2400) { host in
            let found = await eventually(host) { element("catvod.detail.emptyEpisodes", in: host) != nil }
            try #require(found)
            #expect(element("catvod.detail.emptyEpisodes", in: host)?.accessibilityLabel == localized("這部影片沒有可播放的集數"))
            let play = try #require(element("catvod.detail.play", in: host))
            #expect(play.accessibilityTraits.contains(.notEnabled))
        }
        var retries = 0
        let failure = CatVodCatalog.message(CatVodRuntimeError.sourceFailed("offline fixture"))
        try await withAccessibilityHost(in: CatVodMovieLoadState(title: "Fixture", failure: failure) { retries += 1 }) { host in
            let found = await eventually(host) { element("catvod.detail.retry", in: host) != nil }
            try #require(found)
            #expect(element("catvod.detail.loadError", in: host)?.accessibilityLabel == failure)
            let retry = try #require(element("catvod.detail.retry", in: host))
            #expect(retry.accessibilityLabel == localized("重試"))
            #expect(retry.accessibilityActivate())
            #expect(retries == 1)
        }
        try await withAccessibilityHost(in: CatVodMovieLoadState(title: "Fixture", failure: nil, onRetry: {})) { host in
            let found = await eventually(host) { element("catvod.detail.loading", in: host) != nil }
            #expect(found)
            #expect(element("catvod.detail.retry", in: host) == nil)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(8)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func withVideoPreferences(rate: Float, resume: Bool,
                                      _ body: () async throws -> Void) async rethrows {
        let defaults = UserDefaults.standard
        let oldRate = defaults.object(forKey: MediaPreferences.videoDefaultRateKey)
        let oldResume = defaults.object(forKey: MediaPreferences.videoResumeEnabledKey)
        defer {
            defaults.set(oldRate, forKey: MediaPreferences.videoDefaultRateKey)
            defaults.set(oldResume, forKey: MediaPreferences.videoResumeEnabledKey)
        }
        MediaPreferences.videoDefaultRate = rate
        MediaPreferences.videoResumeEnabled = resume
        try await body()
    }

    @Test("real AVPlayer decodes and advances the 10s CatVod fixture, pauses, seeks, resumes and releases its item")
    func localFixtureActuallyPlays() async throws {
        try await withVideoPreferences(rate: 1, resume: true) {
            let detail = try video()
            let route = try #require(detail.routes.last)
            let episode = try #require(route.episodes.first)
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/VideoStill/video-still-landscape.mp4")
            try #require(FileManager.default.fileExists(atPath: fixture.path))
            // Only this test resolver may substitute a file. Production still uses the runtime's
            // HTTP(S)/owned-loopback validation, unchanged; no .invalid URL is ever requested.
            let stream = try makeStream(
                #"{"parse":0,"url":"https://fixture.example.invalid/backup.mp4","header":{"User-Agent":"CatVod Fixture","X-Untrusted":"discard"}}"#,
                route: route, episode: episode
            ) { address in
                #expect(address == "https://fixture.example.invalid/backup.mp4")
                return fixture
            }
            #expect(route.flag == "backup" && episode.playID == "backup-id")
            #expect(stream.headers == ["User-Agent": "CatVod Fixture"])
            let key = try #require(stream.resumeKey)
            #expect(key.scheme == "readcc-catvod" && key.host == "episode")
            let saved = VideoLinkPositions.time(for: key)
            VideoLinkPositions.save(0, for: key)
            let controller = VideoPlaybackController(link: stream, title: "Fixture Series · Backup episode", prefersKSPlayer: false)
            defer {
                controller.close()
                VideoLinkPositions.save(saved ?? 0, for: key)
            }
            controller.start()
            let item = try #require(controller.player.currentItem)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            item.add(output)
            let started = try await waitUntil {
                controller.phase == .playing && item.status == .readyToPlay
                    && controller.player.currentTime().seconds > 0.2 && controller.currentTime > 0
            }
            try #require(started, "The real AVPlayer did not advance the local CatVod fixture")
            #expect(abs(controller.duration - 10) < 0.5)
            #expect(controller.player.rate == 1)
            #expect(controller.chapterIndex == 0)
            var decoded = false
            let drewFrame = try await waitUntil {
                if let frame = output.copyPixelBuffer(forItemTime: controller.player.currentTime(), itemTimeForDisplay: nil) {
                    decoded = CVPixelBufferGetWidth(frame) > CVPixelBufferGetHeight(frame)
                }
                return decoded
            }
            #expect(drewFrame, "The local fixture did not deliver a decoded landscape frame")
            controller.pause()
            #expect(controller.phase == .paused)
            #expect(controller.player.rate == 0)
            controller.seek(to: 4)
            let sought = try await waitUntil { abs(controller.player.currentTime().seconds - 4) < 0.15 }
            try #require(sought)
            #expect(controller.currentTime == 4)
            #expect(controller.player.currentItem === item)
            controller.resume()
            let resumed = try await waitUntil {
                controller.phase == .playing && controller.player.currentTime().seconds > 4.2
            }
            #expect(resumed)
            controller.pause()
            controller.seek(to: 4)
            controller.close()
            #expect(controller.player.currentItem == nil)
            #expect(controller.player.rate == 0)
            #expect(VideoLinkPositions.time(for: key) == 4)
            let reopened = VideoPlaybackController(link: stream, title: "Fixture resumed", prefersKSPlayer: false)
            defer { reopened.close() }
            #expect(reopened.book.audioTimeSeconds == 4)
            reopened.start()
            let reopenedAtSavedTime = try await waitUntil {
                reopened.phase == .playing && reopened.player.currentTime().seconds >= 4
            }
            #expect(reopenedAtSavedTime)
        }
    }

    @Test("existing shared default-rate and resume-off preferences are respected without opening media")
    func sharedPreferences() async throws {
        try await withVideoPreferences(rate: 1.5, resume: false) {
            let route = try #require(try video().routes.first)
            let episode = try #require(route.episodes.first)
            let stream = try makeStream(#"{"url":"https://fixture.example.invalid/not-opened.mp4"}"#,
                                    route: route, episode: episode) { try #require(URL(string: $0)) }
            let key = try #require(stream.resumeKey)
            let saved = VideoLinkPositions.time(for: key)
            VideoLinkPositions.save(3, for: key)
            defer { VideoLinkPositions.save(saved ?? 0, for: key) }
            let controller = VideoPlaybackController(link: stream, title: "Never opened")
            #expect(controller.rate == 1.5)
            #expect(controller.player.defaultRate == 1.5)
            #expect(controller.book.audioTimeSeconds == 0)
            #expect(controller.player.currentItem == nil)
            controller.close()
            // Turning resume off does not overwrite or delete a user's previous saved position.
            #expect(VideoLinkPositions.time(for: key) == 3)
        }
    }
}
