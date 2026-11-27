import Foundation
import os.log

/// Finds a full-length stream for a track its own platform will not play:
/// the mirror and parsing services first, then the other platforms
/// (signed-in ones first), with
/// Qishui last. Lookups run in parallel, but the earliest source in that
/// order that succeeds always wins, so the result does not depend on timing.
enum UnblockResolver {
    enum Purpose {
        case playback
        /// Prefetch skips Qishui, which downloads the whole file up front.
        case prefetch
    }

    struct Resolution {
        let source: ResolvedAudioSource?
        /// Sources that were tried and failed, plus the one returned.
        let attemptedSources: Set<AudioSourceID>
    }

    static let sourceTimeout: TimeInterval = 8
    static let totalTimeout: TimeInterval = 15
    /// Qishui runs after the others and needs time to fetch and decrypt.
    static let qishuiTimeout: TimeInterval = 20

    private static let log = Logger(subsystem: "wow.caicai.coda", category: "audio-source")
    private static let parallelSources: [any UnblockSource] = [
        MirrorUnblockSource(), ParserUnblockSource(), NeteaseUnblockSource(), QQUnblockSource(), KugouUnblockSource(),
    ]
    private static let lastSource: any UnblockSource = QishuiUnblockSource()

    static func resolve(
        _ track: Track,
        quality: AudioQuality,
        excluding excluded: Set<AudioSourceID> = [],
        purpose: Purpose = .playback
    ) async -> Resolution {
        let query = UnblockQuery(track: track)
        let origin = AudioSourceID(platform: query.origin)
        let usable = parallelSources.filter { $0.id != origin && !excluded.contains($0.id) }
        let ordered = await order(usable)

        var attempted = Set<AudioSourceID>()
        if !ordered.isEmpty {
            let (winner, failed) = await race(ordered, query: query, quality: quality)
            attempted.formUnion(failed)
            if let winner {
                attempted.insert(winner.id)
                return Resolution(source: winner, attemptedSources: attempted)
            }
        }

        guard purpose == .playback, lastSource.id != origin, !excluded.contains(lastSource.id),
              !Task.isCancelled, await lastSource.isAvailable()
        else { return Resolution(source: nil, attemptedSources: attempted) }
        attempted.insert(lastSource.id)
        let stream = await attempt(lastSource, query: query, quality: quality, timeout: qishuiTimeout)
        return Resolution(source: stream.map { ResolvedAudioSource(id: lastSource.id, url: $0.url, quality: $0.quality, bitrate: $0.bitrate, title: $0.title) },
                          attemptedSources: attempted)
    }

    /// The tiers the source serving a gray track offers, for the quality menu.
    static func qualityOptions(for track: Track, source id: AudioSourceID) async -> [AudioQualityOption] {
        guard let source = (parallelSources + [lastSource]).first(where: { $0.id == id }) else { return [] }
        let options = (try? await source.qualityOptions(UnblockQuery(track: track))) ?? []
        return AudioQualityOption.unified(options)
    }

    /// Mirrors first, in listed order; then platforms with a saved account
    /// before anonymous ones.
    private static func order(_ sources: [any UnblockSource]) async -> [any UnblockSource] {
        var signedIn: [any UnblockSource] = []
        var anonymous: [any UnblockSource] = []
        for source in sources {
            if source.id.isMirror { continue }
            if await source.isSignedIn() { signedIn.append(source) } else { anonymous.append(source) }
        }
        return sources.filter { $0.id.isMirror } + signedIn + anonymous
    }

    private enum State { case pending, failed, found(UnblockStream) }
    private enum Event { case finished(Int, UnblockStream?), deadline }

    private static func race(
        _ sources: [any UnblockSource],
        query: UnblockQuery,
        quality: AudioQuality
    ) async -> (ResolvedAudioSource?, Set<AudioSourceID>) {
        await withTaskGroup(of: Event.self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    .finished(index, await attempt(source, query: query, quality: quality, timeout: sourceTimeout))
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(totalTimeout * 1_000_000_000))
                return .deadline
            }
            defer { group.cancelAll() }

            var states = Array(repeating: State.pending, count: sources.count)
            var failed = Set<AudioSourceID>()
            for await event in group {
                guard case .finished(let index, let stream) = event else { break }
                if let stream { states[index] = .found(stream) } else {
                    states[index] = .failed
                    failed.insert(sources[index].id)
                }
                // The first source in order decides once everything before it failed.
                for (position, state) in states.enumerated() {
                    if case .found(let stream) = state {
                        return (ResolvedAudioSource(id: sources[position].id, url: stream.url,
                                                    quality: stream.quality, bitrate: stream.bitrate,
                                                    title: stream.title), failed)
                    }
                    if case .pending = state { break }
                }
                if !states.contains(where: { if case .pending = $0 { return true }; return false }) { break }
            }
            return (nil, failed)
        }
    }

    /// One source's answer; failures are logged and read as "no stream".
    private static func attempt(
        _ source: any UnblockSource,
        query: UnblockQuery,
        quality: AudioQuality,
        timeout: TimeInterval
    ) async -> UnblockStream? {
        if await UnblockFailureMemory.shared.remembersMiss(source.id, query) { return nil }
        do {
            let stream = try await withTimeout(timeout) { try await source.resolve(query, quality: quality) }
            if stream == nil, !Task.isCancelled {
                await UnblockFailureMemory.shared.rememberMiss(source.id, query)
            }
            return stream
        } catch {
            if !Task.isCancelled {
                log.error("source=\(source.id.rawValue, privacy: .public) operation=resolve error=\(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    private struct TimeoutError: LocalizedError {
        var errorDescription: String? { "Audio-source lookup timed out" }
    }

    private static func withTimeout<T>(
        _ seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T?
    ) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { return nil }
            return result
        }
    }
}

/// Remembers, for a while, that a source has no copy of a song, so skipping
/// back and forth does not search every platform again.
actor UnblockFailureMemory {
    static let shared = UnblockFailureMemory()
    static let lifetime: TimeInterval = 10 * 60

    private struct Key: Hashable {
        let source: AudioSourceID
        let query: UnblockQuery
    }

    private var misses: [Key: Date] = [:]

    func remembersMiss(_ source: AudioSourceID, _ query: UnblockQuery) -> Bool {
        let key = Key(source: source, query: query)
        guard let expiry = misses[key] else { return false }
        if expiry > Date() { return true }
        misses[key] = nil
        return false
    }

    func rememberMiss(_ source: AudioSourceID, _ query: UnblockQuery) {
        let now = Date()
        if misses.count > 500 { misses = misses.filter { $0.value > now } }
        misses[Key(source: source, query: query)] = now.addingTimeInterval(Self.lifetime)
    }

    func removeAll() {
        misses.removeAll()
    }
}
