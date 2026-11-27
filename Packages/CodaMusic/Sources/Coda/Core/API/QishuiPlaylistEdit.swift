// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

// Protocol: libresoda src/soda/playlist_edit.rs and search.rs (HEAD, 2026-11);
// see docs/development/qishui-integration.md. Request bodies follow the
// official PC client IDL that libresoda documents; Coda writes its own Swift.
extension QishuiMusicAPI {
    /// Successful PC writes may omit `status_code` and only return `status_info`.
    nonisolated static func mutationSucceeded(_ body: [String: Any]) -> Bool {
        if let code = body["status_code"] { return (code as? NSNumber)?.intValue == 0 || (code as? String) == "0" }
        return body["status_info"] is [String: Any]
    }

    private func mutate(_ path: String, payload: [String: Any]) async throws {
        let body = try await signedPCPost(path: path, payload: payload)
        guard Self.mutationSucceeded(body) else { throw QishuiError.invalidResponse }
    }

    nonisolated static func playlistMediaPayload(playlistID: String, trackIDs: [String]) throws -> [String: Any] {
        let playlistID = playlistID.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = trackIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !playlistID.isEmpty, !ids.isEmpty, ids.count == trackIDs.count else { throw MusicProviderError.missingTrack }
        return ["playlist_id": playlistID, "media": ids.map { ["id": $0, "type": "track"] }]
    }

    func deletePlaylist(id: String) async throws {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw MusicProviderError.missingTrack }
        try await mutate("/luna/pc/me/playlist/delete", payload: ["playlist_ids": [id]])
    }

    /// Returns the name the client should display. Name rules match creation.
    func renamePlaylist(id: String, name: String) async throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.unicodeScalars.count <= 30 else { throw QishuiError.invalidPlaylistName }
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw MusicProviderError.missingTrack }
        let body = try await signedPCPost(path: "/luna/pc/me/playlist/update", payload: ["playlist_id": id, "name": name])
        guard Self.mutationSucceeded(body) else { throw QishuiError.invalidResponse }
        let returned = Self.string((body["playlist"] as? [String: Any])?["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return returned.isEmpty ? name : returned
    }

    func appendPlaylistTracks(playlistID: String, trackIDs: [String]) async throws {
        try await mutate("/luna/pc/me/playlist/media/append",
                         payload: try Self.playlistMediaPayload(playlistID: playlistID, trackIDs: trackIDs))
    }

    func deletePlaylistTracks(playlistID: String, trackIDs: [String]) async throws {
        try await mutate("/luna/pc/me/playlist/media/delete",
                         payload: try Self.playlistMediaPayload(playlistID: playlistID, trackIDs: trackIDs))
    }

    // MARK: - Search keywords

    private static var keywordQuery: [String: String] {
        ["aid": "386088", "app_name": "luna_pc", "device_platform": "windows", "version_code": "30030000"]
    }

    /// `GET /luna/pc/sug` (official client SearchBox, `sug_scene=main`).
    func searchSuggestions(keyword: String, limit: Int = 8) async throws -> [String] {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        var query = Self.keywordQuery
        query["q"] = keyword
        query["sug_scene"] = "main"
        query["sug_search_id"] = UUID().uuidString.lowercased()
        let body = try await send(host: .pc, path: "/luna/pc/sug", query: query, cookie: nil,
                                  userAgent: "LunaPC/3.3.0(359450208)").0
        return Array(Self.keywordTexts(body["sugs"] ?? body["data"] ?? body, excluding: keyword).prefix(limit))
    }

    /// `GET /luna/suggest-words/default`: hot or recommended search words.
    func hotSearchWords(limit: Int = 8) async throws -> [String] {
        let body = try await send(host: .pc, path: "/luna/suggest-words/default", query: Self.keywordQuery, cookie: nil,
                                  userAgent: "LunaPC/3.3.0(359450208)").0
        return Array(Self.keywordTexts(body, excluding: "").prefix(limit))
    }

    /// Accepts plain strings or objects; the response shape varies by client version.
    nonisolated static func keywordTexts(_ value: Any?, excluding excluded: String) -> [String] {
        let keys = ["suggestion", "word", "query", "sug", "text", "keyword", "content", "display_text", "show_word", "title"]
        var seen = Set<String>(), result: [String] = []
        func add(_ raw: String) {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != excluded, text.count <= 40, seen.insert(text).inserted else { return }
            result.append(text)
        }
        func walk(_ value: Any?, depth: Int) {
            guard depth < 6, let value else { return }
            if let text = value as? String { add(text); return }
            if let list = value as? [Any] { list.forEach { walk($0, depth: depth + 1) }; return }
            guard let object = value as? [String: Any] else { return }
            if let text = keys.lazy.compactMap({ object[$0] as? String }).first(where: { !$0.isEmpty }) {
                add(text); return
            }
            for (key, child) in object.sorted(by: { $0.key < $1.key })
            where child is [Any] || (child is [String: Any] && !["status_info", "log_pb", "extra"].contains(key)) {
                walk(child, depth: depth + 1)
            }
        }
        walk(value, depth: 0)
        return result
    }
}
