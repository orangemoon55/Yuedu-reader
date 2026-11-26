import Foundation
import Security
import CoreFoundation

/// The enabled preference is deliberately non-secret; the credential itself never enters defaults.
enum TMDBSettings {
    static let enabledKey = "media.tmdb.enabled"
    static let revisionKey = "media.tmdb.revision"
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    static var credential: String? { TMDBCredentialStore.load() }

    static func saveCredential(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TMDBSettingsError.invalidCredential }
        guard TMDBCredentialStore.save(trimmed) else { throw TMDBSettingsError.storageUnavailable }
        incrementRevision()
    }

    static func deleteCredential() throws {
        guard TMDBCredentialStore.delete() else { throw TMDBSettingsError.storageUnavailable }
        incrementRevision()
    }

    private static func incrementRevision() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: revisionKey) &+ 1, forKey: revisionKey)
    }
}

enum TMDBSettingsError: Error {
    case invalidCredential
    case storageUnavailable
}

private enum TMDBCredentialStore {
    private static let service = "app.yuedu.media.tmdb"
    private static let account = "userCredential"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanFalse!]
    }

    static func load() -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    static func save(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess
    }

    static func delete() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}


struct TMDBRecord: Sendable, Hashable {
    let id: Int
    let kind: MovieMetadataKind
    let title: String
    let originalTitle: String
    let year: Int?
    let voteAverage: Double
    let voteCount: Int
    let hasValidRating: Bool
}

/// Internal request construction and pure response matching are kept independently testable.
enum TMDBRequestBuilder {
    static func isBearerToken(_ credential: String) -> Bool {
        let parts = credential.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty }
    }

    static func request(path: String, query: [URLQueryItem], credential: String) -> URLRequest? {
        guard path.hasPrefix("/"), !path.contains(".."),
              var components = URLComponents(string: "https://api.themoviedb.org/3" + path),
              components.scheme == "https", components.host == "api.themoviedb.org" else { return nil }
        var items = query
        if isBearerToken(credential) {
            components.queryItems = items.isEmpty ? nil : items
        } else {
            items.append(URLQueryItem(name: "api_key", value: credential))
            components.queryItems = items
        }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if isBearerToken(credential) {
            request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

enum TMDBClientError: LocalizedError {
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: localized("TMDB 评分服务暂时无法使用。")
        case .invalidResponse: localized("无法识别 TMDB 响应。")
        }
    }
}

enum TMDBMatching {
    struct Page: Sendable {
        let records: [TMDBRecord]
        let totalPages: Int
    }

    static func page(from data: Data, kind: MovieMetadataKind?, findResponse: Bool = false) -> Page? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let rawRecords: [(Any, MovieMetadataKind)]
        if findResponse {
            rawRecords = ((root["movie_results"] as? [Any]) ?? []).map { ($0, .movie) }
                + ((root["tv_results"] as? [Any]) ?? []).map { ($0, .tv) }
        } else {
            guard let kind, let results = root["results"] as? [Any] else { return nil }
            rawRecords = results.map { ($0, kind) }
        }
        let records = rawRecords.compactMap { value, resultKind in record(value, kind: resultKind) }
        let pages = findResponse ? 1 : integer(root["total_pages"]) ?? -1
        guard pages >= 0 else { return nil}
        return Page(records: records, totalPages: pages)
    }

    static func detail(from data: Data, kind: MovieMetadataKind) -> TMDBRecord? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let value = record(object, kind: kind), value.hasValidRating else { return nil }
        return value
    }

    static func sourceYear(_ value: String) -> Int? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[0-9]{4}(?:-[0-9]{2}(?:-[0-9]{2})?)?$"#, options: .regularExpression) != nil else { return nil }
        return year(text)
    }

    static func match(records: [TMDBRecord], title: String, sourceYear: Int?, kind: MovieMetadataKind?) -> TMDBRecord? {
        let wanted = normalized(title)
        guard !wanted.isEmpty else { return nil }
        let named = records.filter {
            (kind == nil || kind == $0.kind)
                && (normalized($0.title) == wanted || normalized($0.originalTitle) == wanted)
        }
        let dated = sourceYear.map { year in named.filter { $0.year == year } } ?? named
        var unique: [String: TMDBRecord] = [:]
        for record in dated { unique["\(record.kind.rawValue):\(record.id)"] = record }
        guard unique.count == 1 else { return nil }
        return unique.values.first
    }

    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func record(_ value: Any, kind: MovieMetadataKind) -> TMDBRecord? {
        guard let item = value as? [String: Any],
              let id = integer(item["id"]), id > 0,
              let adult = item["adult"] as? NSNumber, CFGetTypeID(adult) == CFBooleanGetTypeID(), !adult.boolValue else { return nil }
        let title = (kind == .movie ? item["title"] : item["name"]) as? String ?? ""
        let original = (kind == .movie ? item["original_title"] : item["original_name"]) as? String ?? ""
        guard !title.isEmpty || !original.isEmpty else { return nil }
        let averageNumber = item["vote_average"] as? NSNumber
        let averageIsBoolean = averageNumber.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? true
        let rawAverage = averageNumber?.doubleValue ?? 0
        let average = rawAverage.isFinite ? rawAverage : 0
        let count = integer(item["vote_count"]) ?? -1
        let hasValidRating = !averageIsBoolean && rawAverage.isFinite && rawAverage > 0 && rawAverage <= 10 && count > 0
        let dateKey = kind == .movie ? "release_date" : "first_air_date"
        return TMDBRecord(id: id, kind: kind, title: title, originalTitle: original,
                          year: year(item[dateKey] as? String), voteAverage: average, voteCount: count,
                          hasValidRating: hasValidRating)
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= Double(Int.min), number.doubleValue < Double(Int.max) else { return nil }
        return Int(number.doubleValue)
    }

    private static func year(_ date: String?) -> Int? {
        guard let date, date.count >= 4, let value = Int(date.prefix(4)), value > 0 else { return nil }
        return value
    }
}

actor TMDBClient {
    static let shared = TMDBClient()
    private static let responseLimit = 1_048_576
    private static let cacheLifetime: TimeInterval = 300
    private static let maxSearchPages = 5

    private struct CacheKey: Hashable {
        let tmdbID: Int?
        let imdbID: String?
        let kind: MovieMetadataKind?
        let identityYear: Int?
        let title: String
        let videoYear: String
        let revision: Int
    }
    private struct CacheEntry {
        let rating: MovieRating?
        let expiresAt: Date
    }
    private var cache: [CacheKey: CacheEntry] = [:]

    func rating(for video: CatVodVideo) async throws -> MovieRating? {
        guard TMDBSettings.enabled else { cache.removeAll(); return nil }
        guard let credential = TMDBSettings.credential, !credential.isEmpty else { return nil }
        let identity = video.metadataIdentity
        let revision = UserDefaults.standard.integer(forKey: TMDBSettings.revisionKey)
        let key = CacheKey(tmdbID: identity.tmdbID, imdbID: identity.imdbID, kind: identity.kind,
                           identityYear: identity.year, title: video.title, videoYear: video.year, revision: revision)
        if let entry = cache[key] {
            if entry.expiresAt > Date() { return entry.rating }
            cache.removeValue(forKey: key)
        }
        do {
            let result = try await lookup(video: video, credential: credential)
            guard !Task.isCancelled else { throw CancellationError() }
            guard TMDBSettings.enabled,
                  UserDefaults.standard.integer(forKey: TMDBSettings.revisionKey) == revision else { return nil }
            if cache.count >= 100 {
                cache = cache.filter { $0.value.expiresAt > Date() }
                if cache.count >= 100, let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                    cache.removeValue(forKey: oldest)
                }
            }
            cache[key] = CacheEntry(rating: result, expiresAt: Date().addingTimeInterval(Self.cacheLifetime))
            return result
        } catch let error as TMDBClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw TMDBClientError.unavailable
        }
    }

    private func lookup(video: CatVodVideo, credential: String) async throws -> MovieRating? {
        let identity = video.metadataIdentity
        if let id = identity.tmdbID {
            guard id > 0, let kind = identity.kind else { return nil }
            let data = try await send(path: "/\(kind.rawValue)/\(id)", query: [], credential: credential)
            guard let record = TMDBMatching.detail(from: data, kind: kind), record.id == id else {
                throw TMDBClientError.invalidResponse
            }
            return rating(from: record)
        }

        let year = identity.year ?? TMDBMatching.sourceYear(video.year)
        if let imdbID = identity.imdbID, Self.validIMDbID(imdbID) {
            let query = [URLQueryItem(name: "external_source", value: "imdb_id"),
                         URLQueryItem(name: "language", value: "zh-TW")]
            let data = try await send(path: "/find/\(imdbID)", query: query, credential: credential)
            guard let page = TMDBMatching.page(from: data, kind: nil, findResponse: true) else {
                throw TMDBClientError.invalidResponse
            }
            guard let result = TMDBMatching.match(records: page.records, title: video.title, sourceYear: year, kind: identity.kind) else { return nil }
            return rating(from: result)
        }

        guard !video.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let kinds = identity.kind.map { [$0] } ?? [.movie, .tv]
        var candidates: [TMDBRecord] = []
        for kind in kinds {
            guard let found = try await search(kind: kind, title: video.title, credential: credential) else { return nil }
            candidates.append(contentsOf: found)
        }
        guard let result = TMDBMatching.match(records: candidates, title: video.title, sourceYear: year, kind: identity.kind) else { return nil }
        return rating(from: result)
    }

    private func rating(from record: TMDBRecord) -> MovieRating? {
        guard record.hasValidRating, record.voteAverage.isFinite, record.voteAverage > 0,
              record.voteAverage <= 10, record.voteCount > 0 else { return nil }
        return MovieRating(provider: .tmdb, value: record.voteAverage, voteCount: record.voteCount,
                           origin: .tmdbAPI, sourceField: "TMDB vote_average")
    }

    private static func validIMDbID(_ value: String) -> Bool {
        value.hasPrefix("tt") && value.count > 2 && value.dropFirst(2).allSatisfy(\.isNumber)
    }

    private func search(kind: MovieMetadataKind, title: String, credential: String) async throws -> [TMDBRecord]? {
        let baseQuery = [URLQueryItem(name: "query", value: title),
                         URLQueryItem(name: "include_adult", value: "false"),
                         URLQueryItem(name: "language", value: "zh-TW")]
        func page(_ number: Int) async throws -> TMDBMatching.Page {
            var query = baseQuery
            query.append(URLQueryItem(name: "page", value: String(number)))
            let data = try await send(path: "/search/\(kind.rawValue)", query: query, credential: credential)
            guard let parsed = TMDBMatching.page(from: data, kind: kind) else { throw TMDBClientError.invalidResponse }
            return parsed
        }
        try Task.checkCancellation()
        let first = try await page(1)
        guard first.totalPages <= Self.maxSearchPages else { return nil }
        var records = first.records
        if first.totalPages > 1 {
            for number in 2...first.totalPages {
                try Task.checkCancellation()
                let next = try await page(number)
                guard next.totalPages == first.totalPages else { return nil }
                records.append(contentsOf: next.records)
            }
        }
        return records
    }

    private func send(path: String, query: [URLQueryItem], credential: String) async throws -> Data {
        try Task.checkCancellation()
        guard var request = TMDBRequestBuilder.request(path: path, query: query, credential: credential) else {
            throw TMDBClientError.invalidResponse
        }
        request.httpShouldHandleCookies = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let redirectBlocker = TMDBRedirectBlocker()
        let session = URLSession(configuration: configuration, delegate: redirectBlocker, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, finalURL.scheme == "https", finalURL.host == "api.themoviedb.org" else {
            throw TMDBClientError.unavailable
        }
        guard http.expectedContentLength < 0 || http.expectedContentLength <= Int64(Self.responseLimit) else {
            throw TMDBClientError.invalidResponse
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.responseLimit else { throw TMDBClientError.invalidResponse }
            data.append(byte)
        }
        return data
    }
}

private final class TMDBRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
