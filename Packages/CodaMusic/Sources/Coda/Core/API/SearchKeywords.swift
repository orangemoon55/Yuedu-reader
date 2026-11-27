import Foundation

/// Search-page keyword chips: hot or default words for an empty field,
/// input suggestions otherwise. Each platform uses its own endpoint.
enum SearchKeywords {
    static func load(provider: MusicProvider, keyword: String, limit: Int = 8) async throws -> [String] {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .qq:
            let api = QQMusicAPI.shared
            return try await keyword.isEmpty ? api.hotKeys(limit: limit) : api.searchSuggestions(keyword: keyword)
        case .kugou:
            let api = KugouMusicAPI.shared
            return try await keyword.isEmpty ? api.hotWords(limit: limit) : api.searchSuggestions(keyword: keyword, limit: limit)
        case .qishui:
            let api = QishuiMusicAPI.shared
            return try await keyword.isEmpty ? api.hotSearchWords(limit: limit) : api.searchSuggestions(keyword: keyword, limit: limit)
        case .netease:
            if keyword.isEmpty { return try await NeteaseAPI.searchDefaultKeyword().map { [$0] } ?? [] }
            guard let body = try await NeteaseAPI.searchSuggest(keyword) else { return [] }
            return unique(neteaseNames(body), excluding: keyword, limit: limit)
        }
    }

    static func neteaseNames(_ body: NeteaseAPI.SearchSuggestResponse.Body) -> [String] {
        var names: [String] = (body.songs ?? []).map(\.name)
        names.append(contentsOf: (body.artists ?? []).map(\.name))
        names.append(contentsOf: (body.albums ?? []).map(\.name))
        names.append(contentsOf: (body.playlists ?? []).map(\.name))
        return names
    }

    static func unique(_ values: [String], excluding keyword: String, limit: Int) -> [String] {
        var seen = Set<String>()
        return Array(values.compactMap { value -> String? in
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty || text == keyword || !seen.insert(text).inserted ? nil : text
        }.prefix(limit))
    }
}
