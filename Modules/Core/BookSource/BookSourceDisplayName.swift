import Foundation

/// Presentation only: source identity, scripts and exported names stay untouched.
enum BookSourceDisplayName {
    nonisolated static func title(_ original: String) -> String {
        let compact = original.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Strip the explicit metadata suffix used by some imported sources, e.g.
        // “飞卢男生 ▪ 标签”. Preserve channel names, parentheses and other meaningful words.
        let suffix = #"\s*[▪▫■□●○◆◇•·|｜丨⬛◾]+\s*(?:标签|標籤)\s*$"#
        let cleaned = compact.replacingOccurrences(of: suffix, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? compact : cleaned
    }
}

/// Searches source summaries only; never performs requests or changes the active source.
enum DiscoverySourceSearch {
    nonisolated static func matching(
        _ sources: [DiscoverableBookSource], query: String
    ) -> [DiscoverableBookSource] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return sources }
        return sources.filter { source in
            terms.allSatisfy { term in
                source.name.localizedStandardContains(term)
                    || source.displayName.localizedStandardContains(term)
                    || source.url.localizedStandardContains(term)
            }
        }
    }
}
