import CryptoKit
import Foundation

/// One book-source category's first page. Context is a digest, never raw credentials.
struct ForYouCandidates: Codable, Sendable {
    static let limit = 40
    let sourceURL: String
    let categoryURL: String
    let fetchedAt: Date
    var books: [OnlineBook]
    var contextID: String?

    init(sourceURL: String, categoryURL: String, fetchedAt: Date, books: [OnlineBook], contextID: String? = nil) {
        self.sourceURL = sourceURL
        self.categoryURL = categoryURL
        self.fetchedAt = fetchedAt
        self.books = Array(books.prefix(Self.limit))
        self.contextID = contextID
    }
}

/// Reuses Caches/ForYou. The small memory window avoids decoding the same disk entry for
/// every home/form use; disk is the regenerable cross-launch cache, never a new user database.
actor ForYouCandidateStore {
    static let shared = ForYouCandidateStore(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ForYou", isDirectory: true))
    nonisolated let directory: URL
    private let memoryLimit = 32
    private var memory: [URL: ForYouCandidates] = [:]
    private var recent: [URL] = []

    init(directory: URL) { self.directory = directory }

    nonisolated func fileURL(sourceURL: String, categoryURL: String, contextID: String? = nil) -> URL {
        let name: String
        if let contextID {
            let raw = [sourceURL, categoryURL, contextID].map { "\($0.utf8.count):\($0)" }.joined()
            name = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        } else {
            // Preserve already shipped files used by other discover consumers.
            name = Insecure.MD5.hash(data: Data((sourceURL + "|" + categoryURL).utf8))
                .map { String(format: "%02x", $0) }.joined()
        }
        return directory.appendingPathComponent(name + ".json")
    }

    private func remember(_ value: ForYouCandidates, file: URL) {
        memory[file] = value
        recent.removeAll { $0 == file }
        recent.append(file)
        while recent.count > memoryLimit { memory[recent.removeFirst()] = nil }
    }

    func write(_ incoming: ForYouCandidates) {
        let file = fileURL(sourceURL: incoming.sourceURL, categoryURL: incoming.categoryURL, contextID: incoming.contextID)
        var candidates = incoming
        do {
            let previous = read(sourceURL: candidates.sourceURL, categoryURL: candidates.categoryURL,
                                sourceID: candidates.books.first?.sourceId ?? UUID(), contextID: candidates.contextID)
            if let previous {
                // Parsed books acquire a UUID on each request. Keep stable identities for
                // unchanged editions so cache refresh cannot reset the carousel selection.
                let identities = Dictionary(previous.books.map { (OnlineBookURLKey.normalize($0.bookUrl), $0.id) },
                                            uniquingKeysWith: { first, _ in first })
                for index in candidates.books.indices {
                    if let id = identities[OnlineBookURLKey.normalize(candidates.books[index].bookUrl)] {
                        candidates.books[index].id = id
                    }
                }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                if try encoder.encode(previous.books) == encoder.encode(candidates.books) {
                    remember(candidates, file: file)
                    return // Same response: no disk rewrite for a generated UUID or timestamp.
                }
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(candidates)
            try data.write(to: file, options: .atomic)
            remember(candidates, file: file)
            CacheAutoCleaner.shared.noteWrite(bytes: data.count)
        } catch {
            AppLogger.cache("⟐ for-you candidates could not be saved", error: error,
                            context: ["source": candidates.sourceURL, "category": candidates.categoryURL])
        }
    }

    func read(sourceURL: String, categoryURL: String, sourceID: UUID, contextID: String? = nil) -> ForYouCandidates? {
        let file = fileURL(sourceURL: sourceURL, categoryURL: categoryURL, contextID: contextID)
        let started = SourcePerfTrace.now
        if var saved = memory[file], FileManager.default.fileExists(atPath: file.path) {
            for index in saved.books.indices { saved.books[index].sourceId = sourceID }
            SourcePerfTrace.record("home.cache.memory", "books=\(saved.books.count) main=\(Thread.isMainThread)", since: started)
            return saved
        }
        memory[file] = nil
        do {
            let data = try Data(contentsOf: file)
            var saved = try JSONDecoder().decode(ForYouCandidates.self, from: data)
            guard saved.sourceURL == sourceURL, saved.categoryURL == categoryURL, saved.contextID == contextID else { return nil }
            for index in saved.books.indices { saved.books[index].sourceId = sourceID }
            remember(saved, file: file)
            SourcePerfTrace.record("home.cache.disk", "books=\(saved.books.count) bytes=\(data.count) main=\(Thread.isMainThread)", since: started)
            return saved
        } catch CocoaError.fileReadNoSuchFile { return nil }
        catch {
            AppLogger.cache("⟐ for-you candidates unreadable", error: error,
                            context: ["source": sourceURL, "category": categoryURL])
            return nil
        }
    }

    /// All cached editions for existing sources, also used by the detail page's version list.
    func savedBooks(sources: [String: UUID]) -> [OnlineBook] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
        } catch CocoaError.fileReadNoSuchFile { return [] }
        catch {
            AppLogger.cache("⟐ for-you candidates folder unreadable", error: error, context: [:])
            return []
        }
        var pages: [ForYouCandidates] = []
        for file in files {
            do { pages.append(try JSONDecoder().decode(ForYouCandidates.self, from: Data(contentsOf: file))) }
            catch { AppLogger.cache("⟐ for-you candidates unreadable", error: error, context: ["file": file.lastPathComponent]) }
        }
        var seen = Set<String>()
        return pages.sorted { ($0.sourceURL, $0.categoryURL) < ($1.sourceURL, $1.categoryURL) }.flatMap { page in
            guard let id = sources[page.sourceURL] else { return [OnlineBook]() }
            return page.books.compactMap { book -> OnlineBook? in
                let key = page.sourceURL + "\u{1F}" + OnlineBookURLKey.normalize(book.bookUrl)
                guard seen.insert(key).inserted else { return nil }
                var rebound = book; rebound.sourceId = id
                return rebound
            }
        }
    }
}
