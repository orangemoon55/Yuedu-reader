import Foundation

/// 短时记住 QQ 播放链路的中间结果，让播放、音质菜单和预取共用同一次请求。
///
/// 参照 qq-music-api（folia-major 内嵌的后端）：CDN 节点测出来以后缓存一段时间，
/// 同一首歌同一档音质的 vkey 只要一次；正在进行的请求被并发调用方共享，不重复发起。
actor QQMusicPlaybackCache<Value: Sendable> {
    private struct Entry {
        let value: Value
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Value, Error>] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// 命中未过期缓存直接返回；同 key 的请求进行中则等它；否则发起并按 `ttl(value)` 缓存。
    /// `ttl` 返回 nil 表示这个结果不缓存。请求抛错时不缓存。
    func value(
        for key: String,
        ttl: @escaping @Sendable (Value) -> TimeInterval?,
        load: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let entry = entries[key] {
            if entry.expiresAt > now() { return entry.value }
            entries[key] = nil
        }
        if let task = inFlight[key] { return try await task.value }
        // 不随调用方取消：用户切歌后，这次结果仍可能被音质菜单或下一次播放用到。
        let task = Task { try await load() }
        inFlight[key] = task
        do {
            let value = try await task.value
            inFlight[key] = nil
            if let seconds = ttl(value), seconds > 0 {
                entries[key] = Entry(value: value, expiresAt: now().addingTimeInterval(seconds))
            }
            return value
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func removeAll() {
        entries.removeAll()
    }
}

/// 最近一次验证可用的 QQ 音频 CDN 节点。命中时只探测这一个节点，失效再并发探测全部候选。
final class QQStreamHostMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var base: String?
    private var expiresAt = Date.distantPast
    private let lifetime: TimeInterval
    private let now: () -> Date

    init(lifetime: TimeInterval = 30 * 60, now: @escaping () -> Date = Date.init) {
        self.lifetime = lifetime
        self.now = now
    }

    var current: String? {
        lock.lock()
        defer { lock.unlock() }
        return expiresAt > now() ? base : nil
    }

    func remember(_ value: String) {
        lock.lock()
        base = value
        expiresAt = now().addingTimeInterval(lifetime)
        lock.unlock()
    }

    func forget(_ value: String) {
        lock.lock()
        if base == value { base = nil; expiresAt = .distantPast }
        lock.unlock()
    }
}

/// QQ 单曲详情中与播放有关的字段（get_song_detail_yqq 的 track_info）。
struct QQSongPlaybackDetail: Sendable, Equatable {
    var mediaMid: String?
    var duration: Double?
    /// file.size_* 字段；缺失的键表示详情没有给出，不代表文件不存在。
    var fileSizes: [String: Double] = [:]

    static let sizeFieldByBR: [String: String] = [
        "RS01": "size_hires",
        "F000": "size_flac",
        "M800": "size_320mp3",
        "M500": "size_128mp3",
        "C400": "size_96aac",
    ]

    init(mediaMid: String? = nil, duration: Double? = nil, fileSizes: [String: Double] = [:]) {
        self.mediaMid = mediaMid
        self.duration = duration
        self.fileSizes = fileSizes
    }

    init?(trackInfo track: [String: Any]) {
        guard let file = track["file"] as? [String: Any] else { return nil }
        let mid = (file["media_mid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        mediaMid = mid?.isEmpty == false ? mid : nil
        duration = (track["interval"] as? NSNumber)?.doubleValue
        for field in Self.sizeFieldByBR.values {
            if let number = file[field] as? NSNumber {
                fileSizes[field] = number.doubleValue
            } else if let text = file[field] as? String, let number = Double(text) {
                fileSizes[field] = number
            }
        }
    }

    /// 详情明确给出某档文件大小为 0 时跳过该档，省掉一次必然为空的 vkey 请求。
    /// 只跳过高档：128k 与 m4a 始终保留，详情缺字段或读不到时也照常请求（与 qq-music-api 的 best 档位一致）。
    func definitelyLacks(br: String) -> Bool {
        guard ["RS01", "F000", "M800"].contains(br),
              let field = Self.sizeFieldByBR[br], let size = fileSizes[field] else { return false }
        return size <= 0
    }
}

/// 探测时被截断（别的节点已明确回答、它还没回）的 CDN 节点。一段时间内不再探测它们，
/// 避免每首歌、每个文件名都在同一个挂起的节点上等待。
final class QQSlowHostMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var until: [String: Date] = [:]
    private let lifetime: TimeInterval
    private let now: () -> Date

    init(lifetime: TimeInterval = 10 * 60, now: @escaping () -> Date = Date.init) {
        self.lifetime = lifetime
        self.now = now
    }

    func mark(_ hosts: [String]) {
        guard !hosts.isEmpty else { return }
        lock.lock()
        let expiry = now().addingTimeInterval(lifetime)
        for host in hosts { until[host] = expiry }
        lock.unlock()
    }

    /// 去掉仍在冷却中的节点；如果全部都在冷却，原样返回，宁可慢也不能没有候选。
    func excluding(_ bases: [String]) -> [String] {
        lock.lock()
        let current = now()
        until = until.filter { $0.value > current }
        let slow = Set(until.keys)
        lock.unlock()
        let kept = bases.filter { !slow.contains($0) }
        return kept.isEmpty ? bases : kept
    }
}
