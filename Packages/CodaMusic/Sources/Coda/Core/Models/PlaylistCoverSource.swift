import Foundation

/// Empty and malformed cover fields must not hide another usable source.
enum PlaylistCoverSource {
    static func firstValid(_ candidates: [String?]) -> String? {
        candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { value in
                guard let url = URL(string: value),
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme) else { return false }
                return url.host?.isEmpty == false
            }
    }
}

extension NeteaseAPI {
    /// List endpoints often omit tracks. Fetch one entry only when artwork is absent.
    static func playlistCover(id: Int, using client: NeteaseClient = .shared) async throws -> String? {
        let data = try await client.eapi("/v6/playlist/detail", ["id": id, "n": 1, "s": 0])
        let detail = try client.decoded(PlaylistDetailResponse.self, from: data).playlist
        if let cover = detail.coverURL { return cover }
        guard let firstID = detail.trackIds.first?.id else { return nil }
        let songData = try await client.eapi("/v3/song/detail", ["c": "[{\"id\":\(firstID)}]"])
        let songs = try client.decoded(SongDetailResponse.self, from: songData).songs
        return PlaylistCoverSource.firstValid([songs.first { $0.id == firstID }?.album.picUrl])
    }
}
