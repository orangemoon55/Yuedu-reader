import Foundation
import CoreFoundation

// Foundation-only value types shared by the Readcc50 UI and data layer.
struct CatVodCategory: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
}

struct CatVodFilterOption: Sendable, Hashable {
    let name: String
    let value: String
}

struct CatVodFilter: Identifiable, Sendable, Hashable {
    let key: String
    let name: String
    let initial: String
    let options: [CatVodFilterOption]
    var id: String { key }
}

struct CatVodVideo: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let poster: String
    let remarks: String
    let summary: String
    let actor: String
    let director: String
    let year: String
    let area: String
    let routes: [CatVodRoute]
    var ratings: [MovieRating] = []
    var metadataIdentity: MovieMetadataIdentity = .init()
}

struct CatVodRoute: Identifiable, Sendable, Hashable {
    let id: String
    let flag: String
    let name: String
    let episodes: [CatVodEpisode]
}

struct CatVodEpisode: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let playID: String
}

struct CatVodHome: Sendable, Hashable {
    let categories: [CatVodCategory]
    let filters: [String: [CatVodFilter]]
    let videos: [CatVodVideo]
}

struct CatVodPage: Sendable, Hashable {
    let videos: [CatVodVideo]
    let page: Int
    let pageCount: Int?
    let hasMore: Bool
}

struct CatVodPlaybackChoice: Identifiable, Sendable, Hashable {
    let id: Int
    let name: String
    let address: String
    let headers: [String: String]
    let requiresWebParsing: Bool
}

struct CatVodPlayback: Sendable, Hashable {
    let url: String
    let headers: [String: String]
    let requiresWebParsing: Bool
    /// Ordered alternatives for this episode; the first is the legacy `url`.
    let choices: [CatVodPlaybackChoice]

    init(url: String, headers: [String: String], requiresWebParsing: Bool, choices: [CatVodPlaybackChoice] = []) {
        self.url = url
        self.headers = headers
        self.requiresWebParsing = requiresWebParsing
        self.choices = choices.isEmpty
            ? [CatVodPlaybackChoice(id: 0, name: "默认", address: url, headers: headers, requiresWebParsing: requiresWebParsing)]
            : choices
    }
}

enum CatVodContentError: Error, LocalizedError, Sendable, Equatable {
    case invalidJSON
    case invalidResponse(String)
    case businessFailure(String)
    case invalidPlaybackURL

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "猫源响应不是有效的 JSON。"
        case .invalidResponse(let detail):
            return "猫源响应格式无效：\(detail)"
        case .businessFailure(let detail):
            return "猫源请求失败：\(detail)"
        case .invalidPlaybackURL:
            return "播放响应中没有有效的 HTTP(S) 媒体 URL。"
        }
    }
}

enum CatVodContentParser {
    private enum DetailLookup {
        case video([String: Any])
        case empty
        case malformed
    }

    static func home(_ data: Data) throws -> CatVodHome {
        let root = try normalizedRoot(data)
        try checkBusinessStatus(root)
        guard let object = root as? [String: Any] else {
            throw CatVodContentError.invalidResponse("首页应为对象")
        }

        let categoryValues = (object["class"] as? [Any]) ?? (object["type"] as? [Any]) ?? []
        var seenCategories = Set<String>()
        let categories = categoryValues.compactMap { value -> CatVodCategory? in
            guard let item = value as? [String: Any] else { return nil }
            let id = string(item["type_id"] ?? item["id"])
            let name = string(item["type_name"] ?? item["name"])
            guard !id.isEmpty, !name.isEmpty, seenCategories.insert(id).inserted else { return nil }
            return CatVodCategory(id: id, name: name)
        }

        let filters = parseFilters(object["filters"])
        let videos = parseVideos(videoList(in: object))
        return CatVodHome(categories: categories, filters: filters, videos: videos)
    }

    static func page(_ data: Data, requestedPage: Int) throws -> CatVodPage {
        let root = try normalizedRoot(data)
        try checkBusinessStatus(root)
        guard let object = root as? [String: Any] else {
            throw CatVodContentError.invalidResponse("分页响应应为对象")
        }
        let pageNumber = max(1, positiveInt(object["page"] ?? object["page_num"] ?? object["current"]) ?? requestedPage)
        let videos = parseVideos(videoList(in: object))
        let pageCount = nonnegativeInt(object["pagecount"] ?? object["page_count"] ?? object["pages"])
        let hasMore = !videos.isEmpty && paginationHasMore(object, page: pageNumber, pageCount: pageCount)
        return CatVodPage(videos: videos, page: pageNumber, pageCount: pageCount, hasMore: hasMore)
    }

    static func detail(_ data: Data) throws -> CatVodVideo {
        try parseDetail(data, requestedID: nil, fallbackTitle: nil)
    }

    /// Opt-in request-context recovery; the strict overload and list validation stay unchanged.
    /// Yingxia Catalog.swift:154-156 uses an id as the missing name; :495-506 fills a
    /// missing vod_id from the detail request. Here only matching explicit vod_id-only
    /// records, or named movie records with real metadata/routes, qualify (never {}).
    /// The caller must supply the actual requested ID, not an ID invented from this response.
    static func detail(_ data: Data, fallbackID: String, fallbackTitle: String? = nil) throws -> CatVodVideo {
        let identifier = fallbackID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            throw CatVodContentError.invalidResponse("详情请求缺少影片标识")
        }
        return try parseDetail(data, requestedID: identifier, fallbackTitle: fallbackTitle)
    }

    private static func parseDetail(_ data: Data, requestedID: String?, fallbackTitle: String?) throws -> CatVodVideo {
        // Do not normalize away detail envelopes: all known wrappers, including JSON
        // strings nested inside result/detail/list, must be validated along this path.
        let root = try jsonObject(data)
        switch try detailLookup(in: root, depth: 0, stringDepth: 0, requestedID: requestedID, fallbackTitle: fallbackTitle) {
        case .video(let item):
            return parseVideo(item, includeRoutes: true)
        case .empty:
            throw CatVodContentError.invalidResponse("详情未找到影片")
        case .malformed:
            throw CatVodContentError.invalidResponse("详情缺少影片字段")
        }
    }

    static func playback(_ data: Data) throws -> CatVodPlayback {
        // Preserve outer headers/parse flags while descending through a data envelope.
        let root = try jsonObject(data)
        guard let selected = try selectPlayback(root, headers: [:], requiresParsing: false, depth: 0, stringDepth: 0) else {
            throw CatVodContentError.invalidPlaybackURL
        }
        return selected
    }

    // Unwrap at most one `data` envelope and one stringified JSON value.
    // Check status before discarding each envelope so errors cannot be hidden.
    private static func normalizedRoot(_ data: Data) throws -> Any {
        var value = try jsonObject(data)
        var usedEnvelope = false
        var usedString = false
        for _ in 0..<3 {
            try checkBusinessStatus(value)
            if let text = value as? String, isJSONContainer(text) {
                guard !usedString else {
                    throw CatVodContentError.invalidResponse("字符串化 JSON 超过一层")
                }
                value = try jsonObject(Data(text.utf8))
                usedString = true
            } else if let object = value as? [String: Any], let wrapped = object["data"] {
                guard !usedEnvelope else {
                    throw CatVodContentError.invalidResponse("data 包裹超过一层")
                }
                value = wrapped
                usedEnvelope = true
            } else {
                return value
            }
        }
        try checkBusinessStatus(value)
        throw CatVodContentError.invalidResponse("响应包裹超过允许层数")
    }

    private static func detailLookup(
        in value: Any, depth: Int, stringDepth: Int, requestedID: String?, fallbackTitle: String?
    ) throws -> DetailLookup {
        // Every inspected wrapper is status-checked before we descend into it. Only these
        // explicitly recognized CatVod response keys are traversed; arbitrary objects are
        // never treated as videos just because they contain unrelated fields.
        try checkBusinessStatus(value)
        guard depth <= 4 else {
            throw CatVodContentError.invalidResponse("详情包裹超过允许层数")
        }
        if let text = value as? String, isJSONContainer(text) {
            guard stringDepth < 1 else {
                throw CatVodContentError.invalidResponse("字符串化 JSON 超过一层")
            }
            return try detailLookup(in: jsonObject(Data(text.utf8)), depth: depth, stringDepth: stringDepth + 1,
                                    requestedID: requestedID, fallbackTitle: fallbackTitle)
        }

        if let item = value as? [String: Any] {
            if let requestedID, let video = contextualDetail(item, requestedID: requestedID, fallbackTitle: fallbackTitle) {
                return .video(video)
            }
            if isRecognizedVideoObject(item) { return .video(item) }

            var sawEmpty = false
            var sawMalformed = false
            for key in ["list", "videos", "video", "detail", "result", "data"] {
                guard let nested = item[key] else { continue }
                if nested is NSNull {
                    if key == "list" || key == "videos" { sawEmpty = true }
                    else { sawMalformed = true }
                    continue
                }
                switch try detailLookup(in: nested, depth: depth + 1, stringDepth: stringDepth,
                                        requestedID: requestedID, fallbackTitle: fallbackTitle) {
                case .video(let video): return .video(video)
                case .empty: sawEmpty = true
                case .malformed: sawMalformed = true
                }
            }
            if sawMalformed { return .malformed }
            if sawEmpty { return .empty }
            return .malformed
        }

        if let values = value as? [Any] {
            guard !values.isEmpty else { return .empty }
            var sawEmpty = false
            var sawMalformed = false
            for nested in values {
                switch try detailLookup(in: nested, depth: depth + 1, stringDepth: stringDepth,
                                        requestedID: requestedID, fallbackTitle: fallbackTitle) {
                case .video(let video): return .video(video)
                case .empty: sawEmpty = true
                case .malformed: sawMalformed = true
                }
            }
            if sawMalformed { return .malformed }
            return sawEmpty ? .empty : .malformed
        }
        return .malformed
    }

    // Detail-only adaptation of Yingxia Catalog.swift:154-156, 495-506 at
    // a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c (GPL-3.0-only).
    // Copyright (C) 2026 jo32 and Yingxia contributors.
    // Unlike upstream's unconditional missing-id fill, require movie evidence and
    // never turn a wrapper, an error message, or an arbitrary generic id into a film.
    private static func contextualDetail(
        _ item: [String: Any], requestedID: String, fallbackTitle: String?
    ) -> [String: Any]? {
        guard !["list", "videos", "video", "detail", "result", "data"].contains(where: { item[$0] != nil }),
              !["msg", "message", "errMsg", "error_msg", "errorMessage", "action"].contains(where: {
                  item[$0].map(isMeaningfulError) ?? false
              }) else { return nil }
        let title = string(item["vod_name"] ?? item["title"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = string(item["vod_id"] ?? item["id"]).trimmingCharacters(in: .whitespacesAndNewlines)
        var video = item
        if title.isEmpty {
            // Explicit vod_id is the upstream Video.init contract. A generic {id:...}
            // is not movie evidence; a mismatched ID must not inherit the selected title.
            guard let rawID = item["vod_id"], !(rawID is NSNull),
                  rawID is String || rawID is NSNumber,
                  !identifier.isEmpty, identifier == requestedID else { return nil }
            if let number = rawID as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            if let rawName = item["vod_name"] ?? item["title"], !(rawName is NSNull), !(rawName is String) {
                return nil
            }
            let name = fallbackTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            video["vod_name"] = name.isEmpty ? identifier : name
            return video
        }
        guard identifier.isEmpty else { return nil }
        let metadataKeys = ["vod_pic", "vod_content", "vod_actor", "vod_director", "vod_year", "vod_area"]
        guard !parseRoutes(item).isEmpty || metadataKeys.contains(where: {
            !string(item[$0]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return nil }
        // Only genuinely omitted/null/blank IDs qualify, not malformed containers.
        if let rawID = item["vod_id"] ?? item["id"], !(rawID is NSNull), !(rawID is String) { return nil }
        video["vod_id"] = requestedID
        return video
    }

    private static func isRecognizedVideoObject(_ item: [String: Any]) -> Bool {
        let title = string(item["vod_name"] ?? item["title"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let identifier = string(item["vod_id"] ?? item["id"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Normal details require their identifier; some PanAdapter cloud-search
        // sites intentionally omit it but return explicit playable share routes.
        return !identifier.isEmpty || !parseRoutes(item).isEmpty
    }

    private static func jsonObject(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw CatVodContentError.invalidJSON
        }
    }

    private static func isJSONContainer(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    private static func checkBusinessStatus(_ value: Any) throws {
        guard let object = value as? [String: Any] else { return }
        if let error = object["error"], isMeaningfulError(error) {
            let detail = string(error).isEmpty ? "服务器返回 error" : string(error)
            throw CatVodContentError.businessFailure(detail)
        }
        // CatVod /spider routes commonly encode PanAdapter login/share failures as
        // {list:[], msg:"..."}; preserve that actionable cause instead of showing
        // the misleading generic missing-detail-field error.
        if let message = object["msg"], isMeaningfulError(message),
           (object["list"] as? [Any])?.isEmpty == true {
            throw CatVodContentError.businessFailure(string(message))
        }
        if let status = object["status"], let failure = failureStatus(status) {
            throw CatVodContentError.businessFailure(message(in: object, fallback: failure))
        }
        for key in ["code", "status_code", "error_code", "errno"] {
            guard let raw = object[key], failureStatus(raw) != nil else { continue }
            throw CatVodContentError.businessFailure(message(in: object, fallback: "\(key)=\(string(raw))"))
        }
        if let success = object["success"], booleanFlag(success) == false {
            throw CatVodContentError.businessFailure(message(in: object, fallback: "success=false"))
        }
    }

    private static func isMeaningfulError(_ value: Any) -> Bool {
        if value is NSNull { return false }
        if let number = value as? NSNumber { return number.doubleValue != 0 }
        if let object = value as? [String: Any] { return !object.isEmpty }
        if let array = value as? [Any] { return !array.isEmpty }
        let text = string(value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !text.isEmpty && text != "false" && text != "null" && text != "0"
    }

    // 0, the conventional HTTP success status 200, and textual success markers
    // are accepted; other explicit status/code values are treated as failures.
    private static func failureStatus(_ value: Any) -> String? {
        if value is NSNull { return nil }
        if let number = value as? NSNumber {
            let n = number.doubleValue
            return (n == 0 || n == 200) ? nil : "状态码 \(number.stringValue)"
        }
        let text = string(value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty || ["0", "200", "ok", "success", "true"].contains(text) { return nil }
        if let number = Double(text), number == 0 || number == 200 { return nil }
        return "状态码 \(text)"
    }

    private static func message(in object: [String: Any], fallback: String) -> String {
        let text = string(object["message"] ?? object["msg"])
        return text.isEmpty ? fallback : text
    }

    private static func string(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        let text = string(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(text), number > 0 else { return nil }
        return number
    }

    private static func videoList(in object: [String: Any]) -> [Any] {
        if let list = object["list"] as? [Any] { return list }
        if let videos = object["videos"] as? [Any] { return videos }
        // An explicit null/missing list is a successful empty result unless a
        // business error/status was returned above.
        return []
    }

    private static func parseVideos(_ values: [Any]) -> [CatVodVideo] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let item = value as? [String: Any] else { return nil }
            let video = parseVideo(item, includeRoutes: false)
            guard !video.id.isEmpty, !video.title.isEmpty, seen.insert(video.id).inserted else { return nil }; return video
        }
    }

    private static func parseVideo(_ item: [String: Any], includeRoutes: Bool) -> CatVodVideo {
        let title = string(item["vod_name"] ?? item["title"])
        let identifier = string(item["vod_id"] ?? item["id"])
        // Use a deterministic presentation identity only for explicitly route-backed
        // adapter details that omit IDs; play IDs remain the untouched route payload.
        let stableID = identifier.isEmpty && includeRoutes && !parseRoutes(item).isEmpty
            ? "route:" + title : identifier
        return CatVodVideo(
            id: stableID,
            title: title,
            poster: string(item["vod_pic"] ?? item["poster"]),
            remarks: string(item["vod_remarks"] ?? item["remarks"]),
            summary: string(item["vod_content"] ?? item["summary"]),
            actor: string(item["actor"] ?? item["vod_actor"]),
            director: string(item["director"] ?? item["vod_director"]),
            year: MovieRatingParser.yearText(in: item),
            area: string(item["area"] ?? item["vod_area"]),
            routes: includeRoutes ? parseRoutes(item) : [],
            ratings: MovieRatingParser.ratings(in: item),
            metadataIdentity: MovieRatingParser.identity(in: item)
        )
    }

    private static func parseFilters(_ value: Any?) -> [String: [CatVodFilter]] {
        guard let value else { return [:] }
        var result: [String: [CatVodFilter]] = [:]
        if let groups = value as? [String: Any] {
            for (categoryID, rawFilters) in groups {
                let items = rawFilters as? [Any] ?? (rawFilters as? [String: Any]).map { [$0] } ?? []
                result[categoryID] = items.compactMap(parseFilter)
            }
        } else if let items = value as? [Any] {
            for raw in items {
                guard let item = raw as? [String: Any] else { continue }
                let categoryID = string(item["type_id"] ?? item["category_id"])
                if let filter = parseFilter(item) {
                    result[categoryID, default: []].append(filter)
                }
            }
        }
        return result.filter { !$0.value.isEmpty }
    }

    private static func parseFilter(_ value: Any) -> CatVodFilter? {
        guard let item = value as? [String: Any] else { return nil }
        let key = string(item["key"])
        guard !key.isEmpty else { return nil }
        let optionValues = item["value"] as? [Any] ?? item["options"] as? [Any] ?? []
        let options = optionValues.compactMap { raw -> CatVodFilterOption? in
            guard let option = raw as? [String: Any] else { return nil }
            let name = string(option["n"] ?? option["name"])
            let value = string(option["v"] ?? option["value"])
            guard !name.isEmpty || !value.isEmpty else { return nil }
            return CatVodFilterOption(name: name, value: value)
        }
        let explicitInitial = string(item["initial"] ?? item["init"] ?? item["default"])
        return CatVodFilter(
            key: key,
            name: string(item["name"] ?? item["label"]),
            initial: explicitInitial.isEmpty ? (options.first?.value ?? "") : explicitInitial,
            options: options
        )
    }

    private static func parseRoutes(_ item: [String: Any]) -> [CatVodRoute] {
        let flags = string(item["vod_play_from"] ?? item["play_from"]).components(separatedBy: "$$$")
        let groupValues = string(item["vod_play_url"] ?? item["play_url"]).components(separatedBy: "$$$")
        let groupCount = max(flags.count, groupValues.count)
        guard groupCount > 0 else { return [] }
        return (0..<groupCount).compactMap { groupIndex -> CatVodRoute? in
            let flag = groupIndex < flags.count ? flags[groupIndex].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let routeName = flag.isEmpty ? "线路 \(groupIndex + 1)" : flag
            let rawGroup = groupIndex < groupValues.count ? groupValues[groupIndex] : ""
            let episodes = rawGroup.components(separatedBy: "#").enumerated().compactMap { offset, raw -> CatVodEpisode? in
                let segment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !segment.isEmpty else { return nil }
                if let separator = segment.firstIndex(of: "$") {
                    let title = String(segment[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let playID = String(segment[segment.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !playID.isEmpty else { return nil }
                    return CatVodEpisode(id: "route-\(groupIndex + 1)-episode-\(offset + 1)", title: title.isEmpty ? "第\(offset + 1)集" : title, playID: playID)
                }
                return CatVodEpisode(id: "route-\(groupIndex + 1)-episode-\(offset + 1)", title: "第\(offset + 1)集", playID: segment)
            }
            guard !episodes.isEmpty else { return nil }
            return CatVodRoute(id: "route-\(groupIndex + 1)", flag: flag, name: routeName, episodes: episodes)
        }
    }

    private static func paginationHasMore(_ object: [String: Any], page: Int, pageCount: Int?) -> Bool {
        if let pageCount { return page < pageCount }
        for key in ["has_more", "hasMore"] {
            if let value = object[key], let explicit = booleanFlag(value) { return explicit }
        }
        if let next = object["next"] ?? object["next_page"] {
            if let number = positiveInt(next) { return number > page }
            if let flag = booleanFlag(next) { return flag }
            return false
        }
        if let total = nonnegativeInt(object["total"]),
           let size = positiveInt(object["limit"] ?? object["pagesize"] ?? object["page_size"] ?? object["pageSize"]) {
            return page <= Int.max / size && page * size < total
        }
        return false
    }

    private static func nonnegativeInt(_ value: Any?) -> Int? {
        let text = string(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(text), number >= 0 else { return nil }
        return number
    }

    private static func booleanFlag(_ value: Any) -> Bool? {
        if let number = value as? NSNumber { return number.doubleValue != 0 }
        let text = string(value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "yes", "on"].contains(text) { return true }
        if ["false", "no", "off", "", "0"].contains(text) { return false }
        if let number = Double(text) { return number != 0 }
        return nil
    }

    private static func selectPlayback(
        _ value: Any, headers: [String: String], requiresParsing: Bool, depth: Int, stringDepth: Int
    ) throws -> CatVodPlayback? {
        guard depth < 8 else {
            throw CatVodContentError.invalidResponse("播放 URL 嵌套超过允许层数")
        }
        try checkBusinessStatus(value)
        if let text = value as? String, isJSONContainer(text) {
            guard stringDepth < 1 else {
                throw CatVodContentError.invalidResponse("字符串化 JSON 超过一层")
            }
            return try selectPlayback(jsonObject(Data(text.utf8)), headers: headers, requiresParsing: requiresParsing,
                                      depth: depth, stringDepth: stringDepth + 1)
        }
        if value is String {
            return playbackChoices(value, headers: headers, requiresParsing: requiresParsing)
        }
        if let array = value as? [Any] {
            // Retain the legacy all-URL array form; otherwise upstream's alternating
            // name/address parser must not mistake an HTTP-looking label for an address.
            let directURLs = array.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !directURLs.isEmpty, directURLs.count == array.count, directURLs.allSatisfy(isHTTPMediaURL) {
                let choices = directURLs.enumerated().map {
                    CatVodPlaybackChoice(id: $0.offset, name: "默认", address: $0.element,
                                         headers: headers, requiresWebParsing: requiresParsing)
                }
                return CatVodPlayback(url: choices[0].address, headers: headers, requiresWebParsing: requiresParsing, choices: choices)
            }
            if let result = playbackChoices(array, headers: headers, requiresParsing: requiresParsing) { return result }
            // Older structured responses may contain URL objects rather than scalar pairs.
            for candidate in array where candidate is [String: Any] || candidate is [Any] {
                if let result = try selectPlayback(candidate, headers: headers, requiresParsing: requiresParsing,
                                                   depth: depth + 1, stringDepth: stringDepth) {
                    return result
                }
            }
        }
        if let object = value as? [String: Any] {
            var mergedHeaders = headers
            for (key, value) in parseHeaders(object["header"]) { mergedHeaders[key] = value }
            for (key, value) in parseHeaders(object["headers"]) { mergedHeaders[key] = value }
            let parsing = requiresParsing || parseFlag(object["parse"]) || parseFlag(object["jx"])
            // Status-check FongMi entries before filtering invalid URLs so a failed
            // response is not silently converted to a different quality's success.
            if let values = object["values"] as? [Any] {
                for entry in values { try checkBusinessStatus(entry) }
                if let result = playbackChoices(object, headers: mergedHeaders, requiresParsing: parsing) { return result }
            }
            for key in ["url", "play", "play_url", "data", "result"] {
                if let payload = object[key],
                   let result = try selectPlayback(payload, headers: mergedHeaders, requiresParsing: parsing,
                                                   depth: depth + 1, stringDepth: stringDepth) {
                    return result
                }
            }
        }
        return nil
    }

    private static func playbackChoices(
        _ value: Any, headers: [String: String], requiresParsing: Bool
    ) -> CatVodPlayback? {
        // This is the production call to the adapted upstream parser, not a parallel
        // fixture-only implementation. Safety filtering preserves its position/order/IDs.
        let choices = YingxiaPlaybackChoice.parse(value, fallbackName: "默认").compactMap { choice -> CatVodPlaybackChoice? in
            let address = choice.address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isHTTPMediaURL(address) else { return nil }
            return CatVodPlaybackChoice(id: choice.id, name: choice.name, address: address,
                                        headers: headers, requiresWebParsing: requiresParsing)
        }
        guard let first = choices.first else { return nil }
        return CatVodPlayback(url: first.address, headers: headers, requiresWebParsing: requiresParsing, choices: choices)
    }

    private static func isHTTPMediaURL(_ text: String) -> Bool {
        if text.hasPrefix("/"), !text.hasPrefix("//"), !text.contains("\\") { return true } // resolve only against the activated bundle
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else { return false }
        return true
    }

    private static func parseHeaders(_ value: Any?) -> [String: String] {
        guard let value else { return [:] }
        var raw: [String: Any]?
        if let dictionary = value as? [String: Any] {
            raw = dictionary
        } else if let text = value as? String, let data = text.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            raw = parsed as? [String: Any]
        }
        guard let raw else { return [:] }
        var headers: [String: String] = [:]
        for (key, item) in raw {
            let headerValue = string(item)
            if !key.isEmpty && !headerValue.isEmpty { headers[key] = headerValue }
        }
        return headers
    }

    private static func parseFlag(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let number = value as? NSNumber { return number.doubleValue != 0 }
        let text = string(value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["1", "true", "yes", "on", "parse", "jx"].contains(text) { return true }
        if ["", "0", "false", "no", "off", "null", "none"].contains(text) { return false }
        if let number = Double(text) { return number != 0 }
        return false
    }
}
