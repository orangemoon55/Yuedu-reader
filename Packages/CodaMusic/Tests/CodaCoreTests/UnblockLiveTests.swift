import Foundation
import Testing
@testable import CodaCore

/// Hits the real services anonymously; run with CODA_UNBLOCK_LIVE=1.
@Suite("Unblock live sources")
struct UnblockLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODA_UNBLOCK_LIVE"] == "1"))
    func eachSourceFindsACommonSong() async throws {
        let hits = try await QQMusicAPI(authentication: QQMusicAuth(persistsSession: false))
            .searchSongs(keyword: "后来 刘若英", limit: 5)
        let reference = try #require(hits.first { $0.name == "后来" })
        let query = UnblockQuery(origin: .qishui, title: reference.name,
                                 artists: reference.artists.components(separatedBy: " / "),
                                 album: reference.album, durationMS: Int(reference.duration * 1000))
        let sources: [any UnblockSource] = [MirrorUnblockSource(), ParserUnblockSource(), NeteaseUnblockSource(),
                                            QQUnblockSource(), KugouUnblockSource()]
        var found = 0
        for source in sources {
            do {
                let stream = try await source.resolve(query, quality: .lossless)
                print("live source=\(source.id.rawValue) host=\(stream?.url.host ?? "nil") quality=\(stream?.quality?.rawValue ?? "nil")")
                if stream != nil { found += 1 }
            } catch {
                print("live source=\(source.id.rawValue) error=\(error.localizedDescription)")
            }
        }
        #expect(found > 0)
        let tiers = try await MirrorUnblockSource().qualityOptions(query)
        print("live mirror tiers=\(tiers.map(\.title))")
        #expect(tiers.count > 1)
    }
}
