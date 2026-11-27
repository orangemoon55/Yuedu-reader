// SPDX-License-Identifier: AGPL-3.0-or-later
// Protocol and playback reference: libresoda 5edd2ff. See ThirdPartyNotices/Qishui-API.md.
import Foundation
import CryptoKit

final class QishuiNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

extension QishuiMusicAPI {
    private static let browserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
    // SodaM f43a22b’s public default signer (crates/sodam-core/src/config.rs).
    private static let signerURL = URL(string: "http://103.236.75.83:8899/sign")!
    private static let signerToken = "b356ad402bc31ee9e5a99cfdbf41eaa39961a562251c3359"
    private static let trackPath = "/luna/pc/track_v2"

    struct PlaybackResource: Sendable {
        let url: String
        let durationMS: Int
        let bitrate: Int?
        let size: Int
        let format: String
        let quality: String
        let playAuth: String

        var sampleRate: Double = 0
        var bitDepth: Int = 0
        var verifiedLevel: AudioQuality? = nil

        var level: AudioQuality {
            if let verifiedLevel { return verifiedLevel }
            if AudioQualityCheck.isLossless(format) {
                return AudioQualityCheck.losslessTier(sampleRate: sampleRate, bitDepth: bitDepth)
            }
            let name = quality.lowercased()
            if name.contains("highest") { return .exhigh }
            if name.contains("higher") { return .higher }
            if let bitrate, bitrate >= 256_000 { return .exhigh }
            if let bitrate, bitrate >= 160_000 { return .higher }
            return .standard
        }

        var rank: Int { AudioQuality.allCases.firstIndex(of: level) ?? 0 }

        var potentialRank: Int {
            // A level read from the file itself is not a guess any more.
            if verifiedLevel != nil { return rank }
            let name = quality.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
            guard !AudioQualityCheck.isLossy(format) else { return rank }
            if name.contains("hires") { return AudioQuality.allCases.firstIndex(of: .hires) ?? rank }
            if name.contains("lossless") { return max(rank, AudioQuality.allCases.firstIndex(of: .lossless) ?? rank) }
            return rank
        }
    }

    struct PlaybackRequest: Hashable {
        let trackID: String
        let quality: AudioQuality?
    }

    final class PlaybackJob {
        let id = UUID()
        var waiters: Set<UUID> = []
        var task: Task<PlaybackResource, Error>?
    }

    struct PreparedPlayback {
        let resource: PlaybackResource
        let expiry: Date
    }

    func resetPlaybackPreparation() {
        for job in playbackJobs.values { job.task?.cancel() }
        playbackJobs.removeAll()
        preparedPlayback.removeAll()
    }

    func lyric(trackID: String) async throws -> LyricResponse {
        let pc = try? await pcWebTrack(trackID)
        let original = pc.flatMap { Self.lyrics(in: $0) }
        if let original, original.tlyric != nil { return original }
        try Task.checkCancellation()
        do {
            let body = try await seoTrack(trackID, timeout: original == nil ? nil : 3)
            if let response = Self.lyrics(in: body, preferredOriginal: original) { return response }
            // Qishui serves no lyric for an instrumental and marks the track
            // itself: vocal 1 is sung, 2 is instrumental.
            if (Self.track(in: body)["vocal"] as? NSNumber)?.intValue == 2 {
                return AlternativeLyricsAPI.instrumentalResponse()
            }
            throw AlternativeLyricsAPI.Failure.noMatch
        } catch {
            try Task.checkCancellation()
            if let original { return original }
            throw error
        }
    }

    private static func lyrics(in body: [String: Any], preferredOriginal: LyricResponse? = nil) -> LyricResponse? {
        let seo = body["seo_track"] as? [String: Any]
        let payloads = [body["lyric"], seo?["lyric"], track(in: body)["lyric"]]
            .compactMap { $0 as? [String: Any] }
        let translation = payloads.lazy.compactMap { payload -> String? in
            let translations = payload["translations"] as? [String: String]
            let languages = payload["lang_translations"] as? [String: [String: Any]]
            return [translations?["cn"], languages?["CHINESE"]?["content"] as? String]
                .compactMap { $0 }.first { !LyricsParser.parseLRC($0).isEmpty }
        }.first
        var response = preferredOriginal ?? payloads.lazy.compactMap { payload -> LyricResponse? in
            guard let content = payload["content"] as? String else { return nil }
            // Qishui's word offsets are relative to the line start, like KRC.
            return (try? AlternativeLyricsAPI.parseKRC(content)) ?? (try? AlternativeLyricsAPI.response(lrc: content))
        }.first
        if let translation {
            response?.tlyric = .init(lyric: translation)
        }
        return response
    }

    private func webTrack(_ trackID: String) async throws -> [String: Any] {
        do {
            return try await pcWebTrack(trackID)
        } catch {
            try Task.checkCancellation()
            return try await seoTrack(trackID)
        }
    }

    private func pcWebTrack(_ trackID: String) async throws -> [String: Any] {
        try await send(host: .pc, path: Self.trackPath, query: [
            "track_id": trackID, "media_type": "track", "aid": "386088",
            "device_platform": "web", "channel": "pc_web"
        ], cookie: nil, userAgent: Self.browserAgent).0
    }

    private func seoTrack(_ trackID: String, timeout: TimeInterval? = nil) async throws -> [String: Any] {
        try await send(host: .app, path: "/luna/h5/seo_track",
            query: ["track_id": trackID, "device_platform": "web"], cookie: nil,
            userAgent: Self.browserAgent, timeout: timeout).0
    }

    func playback(trackID: String, quality: AudioQuality? = nil) async throws -> PlaybackResource {
        try Task.checkCancellation()
        let account = credentials
        let request = PlaybackRequest(trackID: trackID, quality: quality)
        let time = now()
        preparedPlayback = preparedPlayback.filter { $0.value.expiry > time }
        if let prepared = preparedPlayback[request], let url = URL(string: prepared.resource.url),
           FileManager.default.fileExists(atPath: url.path) {
            return prepared.resource
        }
        let job: PlaybackJob
        if let active = playbackJobs[request] {
            job = active
        } else {
            job = PlaybackJob()
            let jobID = job.id
            playbackJobs[request] = job
            job.task = Task {
                defer {
                    if playbackJobs[request]?.id == jobID { playbackJobs[request] = nil }
                }
                let resource = try await resolvePlayback(trackID: trackID, quality: quality)
                try Task.checkCancellation()
                if URL(string: resource.url)?.isFileURL == true {
                    if preparedPlayback.count >= 4,
                       let oldest = preparedPlayback.min(by: { $0.value.expiry < $1.value.expiry })?.key {
                        preparedPlayback[oldest] = nil
                    }
                    preparedPlayback[request] = .init(resource: resource, expiry: now().addingTimeInterval(600))
                }
                return resource
            }
        }
        guard let task = job.task else { throw CancellationError() }
        let jobID = job.id
        let waiter = UUID()
        job.waiters.insert(waiter)
        return try await withTaskCancellationHandler {
            let resource = try await task.value
            try Task.checkCancellation()
            guard isCurrentSession(account) else { throw CancellationError() }
            return resource
        } onCancel: {
            Task { @MainActor in
                guard let job = self.playbackJobs[request], job.id == jobID else { return }
                job.waiters.remove(waiter)
                // Give a foreground switch time to take over the next track's prefetch.
                try? await Task.sleep(for: .milliseconds(250))
                guard job.waiters.isEmpty, self.playbackJobs[request]?.id == jobID else { return }
                self.playbackJobs[request] = nil
                task.cancel()
            }
        }
    }

    private func resolvePlayback(trackID: String, quality: AudioQuality?) async throws -> PlaybackResource {
        let streams = try await playbackStreams(trackID: trackID)
        let limit = quality.flatMap { AudioQuality.allCases.firstIndex(of: $0) }
        let ordered = streams.sorted { ($0.rank, $0.bitrate ?? 0, $0.size) > ($1.rank, $1.bitrate ?? 0, $1.size) }
        let matching = ordered.filter { stream in limit.map { $0 >= stream.rank } ?? true }
        let account = credentials
        var lastError: Error = QishuiError.unavailable
        let verifiesPremium = limit.map { $0 >= (AudioQuality.allCases.firstIndex(of: .lossless) ?? 0) } ?? true
        let candidates: [PlaybackResource]
        if matching.isEmpty {
            candidates = Array(ordered.reversed())
        } else if verifiesPremium {
            // Read each uncertain encrypted stream's real tier from its header
            // first, so only the stream that is actually best is downloaded in full.
            let checked = await Self.headerVerified(matching, session: session, agent: Self.browserAgent)
            try Task.checkCancellation()
            candidates = checked.sorted { ($0.potentialRank, $0.bitrate ?? 0, $0.size) > ($1.potentialRank, $1.bitrate ?? 0, $1.size) }
        } else {
            candidates = matching
        }
        var best: PlaybackResource?
        var aboveLimit: PlaybackResource?
        for stream in candidates {
            if let best, stream.potentialRank < best.rank { break }
            do {
                let prepared = try await prepare(stream, trackID: trackID)
                try Task.checkCancellation()
                guard isCurrentSession(account) else { throw CancellationError() }
                if !verifiesPremium || matching.isEmpty { return prepared }
                if let limit, prepared.rank > limit {
                    if aboveLimit.map({ prepared.rank < $0.rank }) ?? true { aboveLimit = prepared }
                    continue
                }
                if best.map({ ($0.rank, $0.bitrate ?? 0, $0.size) < (prepared.rank, prepared.bitrate ?? 0, prepared.size) }) ?? true {
                    best = prepared
                }
                if prepared.rank >= stream.potentialRank { break }
            } catch {
                try Task.checkCancellation()
                guard isCurrentSession(account) else { throw CancellationError() }
                lastError = error
            }
        }
        if let result = best ?? aboveLimit { return result }
        throw lastError
    }

    /// `unifiedNames` titles the tiers like the other platforms (used when
    /// Qishui serves another platform's gray track).
    func playbackQualityOptions(trackID: String, unifiedNames: Bool = false) async throws -> [AudioQualityOption] {
        let streams = try await playbackStreams(trackID: trackID)
        return Dictionary(grouping: streams, by: \.level).compactMap { level, streams in
            guard let stream = streams.max(by: { ($0.bitrate ?? 0, $0.size) < ($1.bitrate ?? 0, $1.size) }) else { return nil }
            guard unifiedNames else {
                return .qishui(quality: level, bitrate: stream.bitrate, byteCount: stream.size, durationMS: stream.durationMS)
            }
            return .init(quality: level, title: AudioQualityOption.unifiedTitle(
                quality: level, reportedBitrate: stream.bitrate.map(Double.init),
                byteCount: Double(stream.size), durationSeconds: Double(stream.durationMS) / 1000))
        }
    }

    private func playbackStreams(trackID: String) async throws -> [PlaybackResource] {
        let account = credentials
        let signed = isLoggedIn ? Task {
            try await signedPCPost(path: Self.trackPath, payload: [
                "track_id": trackID, "media_type": "track", "queue_type": "favorite_track_playlist", "scene_name": "library"
            ])
        } : nil
        defer { signed?.cancel() }
        let web: Result<[PlaybackResource], Error>
        var fullDuration = 0
        do {
            let body = try await webTrack(trackID)
            fullDuration = Self.integer(Self.number(Self.track(in: body)["duration"]))
            web = .success(try await resolveStreams(body, fallbackDuration: fullDuration))
        } catch { web = .failure(error) }
        try Task.checkCancellation()
        guard isCurrentSession(account) else { throw CancellationError() }
        if let signed {
            do {
                let body = try await withTaskCancellationHandler {
                    try await signed.value
                } onCancel: {
                    signed.cancel()
                }
                try Task.checkCancellation()
                let streams = try await resolveStreams(body, fallbackDuration: fullDuration)
                guard isCurrentSession(account) else { throw CancellationError() }
                return streams + ((try? web.get()) ?? [])
            } catch {
                try Task.checkCancellation()
                guard isCurrentSession(account) else { throw CancellationError() }
                if case .failure = web { throw error }
            }
        }
        return try web.get()
    }

    func signedPCPost(path: String, payload: [String: Any]) async throws -> [String: Any] {
        guard isLoggedIn else { throw QishuiError.expiredLogin }
        return try await signedPCRequest(path: path, payload: payload)
    }

    /// Signed PC request. A nil payload sends a GET with `parameters` in the query;
    /// anonymous callers (search) use it too, since upstream now drops unsigned search
    /// requests with an empty 200 body.
    func signedPCRequest(path: String, parameters: [String: String] = [:], payload: [String: Any]? = nil) async throws -> [String: Any] {
        let account = credentials
        let timestamp = Int64(now().timeIntervalSince1970 * 1000)
        let device = String(timestamp)
        let query = [
            "aid": "386088", "app_name": "luna_pc", "region": "cn", "geo_region": "cn", "os_region": "cn",
            "sim_region": "", "device_id": device, "cdid": "", "iid": String(timestamp + 1),
            "version_name": "3.3.0", "version_code": "30030000", "channel": "official", "build_mode": "master",
            "network_carrier": "", "ac": "wifi", "tz_name": "Asia/Shanghai", "resolution": "",
            "device_platform": "windows", "device_type": "Windows", "os_version": "Windows 11",
            "fp": device
        ].merging(parameters) { _, new in new }
        var components = URLComponents(string: Host.pc.rawValue + path)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let bytes = try payload.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) }
        let method = bytes == nil ? "GET" : "POST"
        var headers = [
            "User-Agent": "LunaPC/3.3.0(359450208)", "x-luna-background-type": "foreground",
            "x-luna-is-background-req": "0", "x-luna-is-local-user": "1"
        ]
        // The signer rejects an empty Cookie header, so anonymous requests omit it.
        let cookie = Self.accountCookie(account)
        if !cookie.isEmpty { headers["Cookie"] = cookie }
        if let bytes {
            headers["Content-Type"] = "application/json; charset=utf-8"
            headers["X-SS-STUB"] = bytes.md5Hex().uppercased()
        }
        var sign = URLRequest(url: Self.signerURL, timeoutInterval: 10)
        sign.httpMethod = "POST"
        sign.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sign.setValue("Bearer " + Self.signerToken, forHTTPHeaderField: "Authorization")
        sign.httpBody = try JSONSerialization.data(withJSONObject: [
            "url": components.url!.absoluteString, "method": method, "body": bytes.map { String(decoding: $0, as: UTF8.self) } ?? "",
            "headers": headers, "ts_ms": timestamp
        ])
        let signed: Data, signerResponse: URLResponse
        do {
            (signed, signerResponse) = try await session.data(for: sign, delegate: QishuiNoRedirect())
        } catch {
            try Task.checkCancellation()
            throw QishuiError.signerFailed
        }
        guard let status = (signerResponse as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
              let signature = try? JSONSerialization.jsonObject(with: signed) as? [String: Any],
              signature["ok"] as? Bool != false else { throw QishuiError.signerFailed }
        let returned = (signature["headers"] as? [String: Any] ?? [:]).merging(signature) { first, _ in first }
        for key in ["x-helios", "x-medusa"] {
            guard let value = returned.first(where: { $0.key.lowercased() == key })?.value as? String,
                  !value.isEmpty, !value.contains(where: \.isNewline) else { throw QishuiError.signerFailed }
            headers[key] = value
        }
        for (field, name) in [("ms_token", "msToken"), ("a_bogus", "a_bogus")] {
            if let value = signature[field] as? String, !value.isEmpty {
                components.queryItems?.append(URLQueryItem(name: name, value: value))
            }
        }
        try Task.checkCancellation()
        guard isCurrentSession(account) else { throw CancellationError() }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = bytes
        request.allHTTPHeaderFields = headers
        let (data, response) = try await session.data(for: request, delegate: QishuiNoRedirect())
        try Task.checkCancellation()
        guard isCurrentSession(account) else { throw CancellationError() }
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
              !data.isEmpty else { throw QishuiError.signerFailed }
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QishuiError.invalidResponse }
        try Self.validate(body)
        return body
    }

    private static func track(in body: [String: Any]) -> [String: Any] {
        let seo = body["seo_track"] as? [String: Any]
        return [body["track"], body["track_info"], seo?["track"]]
            .compactMap { $0 as? [String: Any] }.first { !$0.isEmpty } ?? [:]
    }

    private func resolveStreams(_ body: [String: Any], fallbackDuration: Int) async throws -> [PlaybackResource] {
        let seo = body["seo_track"] as? [String: Any]
        let track = Self.track(in: body)
        let player = body["track_player"] as? [String: Any] ?? seo?["track_player"] as? [String: Any] ?? [:]
        let duration = Self.number(track["duration"])
        let fullMS = duration > 0 ? Self.integer(duration) : fallbackDuration
        do {
            return try Self.playbackResources(track: track, player: player, fullMS: fullMS)
        } catch {
            guard let url = Self.mediaURL(Self.string(player["url_player_info"])) else { throw error }
            var request = URLRequest(url: url)
            request.setValue(Self.browserAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request, delegate: QishuiNoRedirect())
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = body["Result"] as? [String: Any] ?? body["result"] as? [String: Any],
                  let info = result["Data"] as? [String: Any] ?? result["data"] as? [String: Any] else { throw error }
            return try Self.playbackResources(track: track, player: [
                "video_model": info["PlayInfoList"] ?? info["play_info_list"] ?? []
            ], fullMS: fullMS)
        }
    }

    static func playbackResource(track: [String: Any], player: [String: Any]) throws -> PlaybackResource {
        let streams = try playbackResources(track: track, player: player)
        guard let best = streams.max(by: { ($0.rank, $0.bitrate ?? 0, $0.size) < ($1.rank, $1.bitrate ?? 0, $1.size) }) else {
            throw QishuiError.unavailable
        }
        return best
    }

    private static func playbackResources(track: [String: Any], player: [String: Any], fullMS: Int? = nil) throws -> [PlaybackResource] {
        let full = fullMS ?? integer(number(track["duration"]))
        guard full > 0 else { throw QishuiError.unavailable }
        let expiry = number(player["expire_at"])
        guard expiry <= 0 || expiry > Date().timeIntervalSince1970 else { throw QishuiError.unavailable }
        var model = player["video_model"]
        for _ in 0..<3 {
            guard let text = model as? String else { break }
            model = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
        }
        var candidates: [PlaybackResource] = []
        var preview = false
        let range = track["playable_range"] as? [String: Any] ?? [:]
        let playableMS = number(range["duration"])
        let restricted = number(range["start"]) != 0 || (playableMS > 0 && playableMS < Double(full) - 1000)

        func collect(_ node: Any?, durationMS: Double, auth: String, depth: Int) {
            guard depth < 12 else { return }
            if let list = node as? [Any] {
                for entry in list { collect(entry, durationMS: durationMS, auth: auth, depth: depth + 1) }
                return
            }
            guard let entry = node as? [String: Any] else { return }
            let meta = entry["video_meta"] as? [String: Any] ?? [:]
            let encryption = entry["encrypt_info"] as? [String: Any] ?? entry["EncryptInfo"] as? [String: Any] ?? entry["encryptInfo"] as? [String: Any] ?? [:]
            let ownAuth = [entry["play_auth"], entry["PlayAuth"], entry["spade_a"], encryption["spade_a"], encryption["SpadeA"], encryption["spadeA"], encryption["PlayAuth"], encryption["play_auth"]]
                .map(string).first { !$0.isEmpty } ?? auth
            let duration = number(entry["video_duration"] ?? entry["duration"] ?? entry["Duration"] ?? meta["duration"])
            let ms = duration > 0 ? (duration > 1000 ? duration : duration * 1000) : durationMS
            let addresses = ["main_url", "main_play_url", "MainPlayUrl", "MainUrl", "url", "backup_url", "backup_play_url", "BackupPlayUrl", "BackupUrl", "backup_url_1"]
            if let url = addresses.lazy.compactMap({ mediaURL(string(entry[$0])) }).first {
                if restricted || (ms > 0 && ms < Double(full) - 1000) {
                    preview = true
                } else if ms > 0 {
                    let rawRate = [entry["bitrate"], entry["Bitrate"], entry["BitRate"], meta["bitrate"], meta["real_bitrate"]]
                        .lazy.map(number).first { $0 > 0 } ?? 0
                    let bitrate = integer(AudioQualityCheck.bitrateBPS(rawRate) ?? 0)
                    let size = integer(number(entry["size"] ?? entry["Size"] ?? entry["file_size"] ?? meta["size"]))
                    let quality = string(entry["quality"] ?? entry["Quality"] ?? entry["definition"] ?? meta["quality"] ?? entry["gear_des_key"])
                    let formats = [entry["codec_type"], meta["codec_type"], entry["format"], entry["Format"], entry["vtype"], meta["format"]]
                        .map(string).map { $0.lowercased() }
                    let format = formats.first { AudioQualityCheck.isLossless($0) || AudioQualityCheck.isLossy($0) }
                        ?? formats.first { !$0.isEmpty } ?? ""
                    let sampleRate = number(entry["sample_rate"] ?? meta["sample_rate"] ?? entry["SampleRate"])
                    let bitDepth = integer(number(entry["bit_depth"] ?? meta["bit_depth"] ?? entry["BitDepth"]))
                    candidates.append(.init(url: url.absoluteString, durationMS: full, bitrate: bitrate > 0 ? bitrate : nil,
                                            size: size, format: format, quality: quality, playAuth: ownAuth,
                                            sampleRate: sampleRate, bitDepth: bitDepth))
                }
            }
            for child in entry.values { collect(child, durationMS: ms, auth: ownAuth, depth: depth + 1) }
        }
        collect(model, durationMS: 0, auth: "", depth: 0)
        guard !candidates.isEmpty else { throw preview ? QishuiError.previewOnly : QishuiError.unavailable }
        return candidates
    }

    private static func integer(_ value: Double) -> Int {
        guard value > 0, value < Double(Int.max) else { return 0 }
        return Int(value)
    }

    nonisolated private static func mediaURL(_ address: String) -> URL? {
        guard let url = URL(string: address), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(),
              ["douyin.com", "qishui.com", "douyinvod.com", "bytedance.com", "bytedance.net", "bytecdn.cn",
               "bytecdntp.com", "snssdk.com", "byted.org", "bytevcloud.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { return nil }
        return url
    }

    private func prepare(_ stream: PlaybackResource, trackID: String) async throws -> PlaybackResource {
        guard !stream.playAuth.isEmpty else {
            var checked = stream
            if stream.potentialRank > stream.rank || [.lossless, .hires].contains(stream.level) {
                checked.verifiedLevel = await AudioQualityCheck.remoteTier(url: stream.url, session: session, bitrate: stream.bitrate.map(Double.init))
            }
            return checked
        }
        guard let url = Self.mediaURL(stream.url) else { throw QishuiError.unavailable }
        let account = credentials
        let key = try QishuiAudio.key(from: stream.playAuth)
        // CDN signatures change per request. The media path and encryption key identify the asset.
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        let version = path.isEmpty || path == "/" ? stream.url : path
        let identity = [userID, trackID, version, stream.quality, stream.format, String(stream.size), key.base64EncodedString()]
        let identifier = SHA256.hash(data: try JSONEncoder().encode(identity))
            .map { String(format: "%02x", $0) }.joined()
        let destination = QishuiAudio.directory.appendingPathComponent(identifier).appendingPathExtension("m4a")
        if !FileManager.default.fileExists(atPath: destination.path) {
            let download = try await Self.downloadMedia(url, expectedSize: stream.size, session: session, agent: Self.browserAgent)
            defer { try? FileManager.default.removeItem(at: download) }
            try Task.checkCancellation()
            let decrypt = Task.detached(priority: .utility) {
                try QishuiAudio.decryptFile(download, to: destination, key: key)
            }
            try await withTaskCancellationHandler {
                try await decrypt.value
            } onCancel: {
                decrypt.cancel()
            }
        }
        try Task.checkCancellation()
        guard isCurrentSession(account) else { throw CancellationError() }
        let verified = AudioQualityCheck.localTier(url: destination, bitrate: stream.bitrate.map(Double.init), fallback: stream.level)
        return .init(url: destination.absoluteString, durationMS: stream.durationMS, bitrate: stream.bitrate,
                     size: stream.size, format: stream.format, quality: stream.quality, playAuth: "",
                     sampleRate: stream.sampleRate, bitDepth: stream.bitDepth, verifiedLevel: verified)
    }

    // MARK: - Faster media transfer

    /// Encrypted streams whose name promises more than their metadata proves
    /// get their real tier from the file header (a few KB, unencrypted).
    nonisolated static func headerVerified(_ streams: [PlaybackResource], session: URLSession,
                                           agent: String) async -> [PlaybackResource] {
        await withTaskGroup(of: (Int, AudioQuality?).self) { group in
            for (index, stream) in streams.enumerated()
            where !stream.playAuth.isEmpty && stream.verifiedLevel == nil && stream.potentialRank > stream.rank {
                guard let url = mediaURL(stream.url) else { continue }
                group.addTask {
                    guard let header = await fetchHeader(url, session: session, agent: agent) else { return (index, nil) }
                    return (index, QishuiAudio.headerTier(header))
                }
            }
            var result = streams
            for await (index, tier) in group {
                if let tier { result[index].verifiedLevel = tier }
            }
            return result
        }
    }

    /// The file's `ftyp` + `moov`, fetched with Range requests.
    nonisolated static func fetchHeader(_ url: URL, session: URLSession, agent: String) async -> Data? {
        func range(_ upper: Int) async -> Data? {
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue(agent, forHTTPHeaderField: "User-Agent")
            request.setValue("bytes=0-\(upper - 1)", forHTTPHeaderField: "Range")
            guard let (data, response) = try? await session.data(for: request, delegate: QishuiNoRedirect()),
                  let status = (response as? HTTPURLResponse)?.statusCode, status == 206 || status == 200 else { return nil }
            return data
        }
        guard var data = await range(64 * 1024) else { return nil }
        if QishuiAudio.headerLength(data) == nil, data.count >= 64 * 1024,
           let needed = moovEnd(in: data), needed <= 4 * 1024 * 1024 {
            guard let more = await range(needed) else { return nil }
            data = more
        }
        return QishuiAudio.headerLength(data) == nil ? nil : data
    }

    /// Where `moov` ends, from the box sizes at the start of `data`.
    nonisolated private static func moovEnd(in data: Data) -> Int? {
        var cursor = 0
        while cursor + 8 <= data.count {
            let size = data[cursor..<cursor + 4].reduce(0) { ($0 << 8) | Int($1) }
            let type = String(decoding: data[cursor + 4..<cursor + 8], as: UTF8.self)
            guard size >= 8 else { return nil }
            if type == "moov" { return cursor + size }
            cursor += size
        }
        return nil
    }

    nonisolated static let parallelDownloadThreshold = 4 * 1024 * 1024
    nonisolated static let parallelDownloadParts = 4

    /// Downloads the whole media file. Large files come down as four Range
    /// parts at once; a CDN that refuses ranges gets one plain request.
    nonisolated static func downloadMedia(_ url: URL, expectedSize: Int, session: URLSession, agent: String) async throws -> URL {
        if expectedSize >= parallelDownloadThreshold,
           let file = try await parallelDownload(url, size: expectedSize, session: session, agent: agent) {
            return file
        }
        var request = URLRequest(url: url)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (download, response) = try await session.download(for: request, delegate: QishuiNoRedirect())
        let count = (try? download.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard (response as? HTTPURLResponse)?.statusCode == 200, count > 0, count >= expectedSize,
              count <= 256 * 1024 * 1024 else {
            try? FileManager.default.removeItem(at: download)
            throw QishuiError.unavailable
        }
        return download
    }

    /// Nil when the CDN does not honour the ranges (or the size disagrees), so
    /// the caller falls back to one request; cancellation is passed through.
    nonisolated private static func parallelDownload(_ url: URL, size: Int, session: URLSession, agent: String) async throws -> URL? {
        let parts = parallelDownloadParts
        let step = (size + parts - 1) / parts
        let ranges = (0..<parts).map { index in (index * step)..<min(size, (index + 1) * step) }.filter { !$0.isEmpty }
        let pieces: [Int: URL]
        do {
            pieces = try await withThrowingTaskGroup(of: (Int, URL).self) { group in
                for (index, range) in ranges.enumerated() {
                    group.addTask {
                        var request = URLRequest(url: url)
                        request.setValue(agent, forHTTPHeaderField: "User-Agent")
                        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
                        let (file, response) = try await session.download(for: request, delegate: QishuiNoRedirect())
                        let http = response as? HTTPURLResponse
                        let count = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                        let total = http?.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int($0) }
                        guard http?.statusCode == 206, count == range.count, total == nil || total == size else {
                            try? FileManager.default.removeItem(at: file)
                            throw QishuiError.unavailable
                        }
                        return (index, file)
                    }
                }
                var collected: [Int: URL] = [:]
                do {
                    for try await (index, file) in group { collected[index] = file }
                } catch {
                    collected.values.forEach { try? FileManager.default.removeItem(at: $0) }
                    throw error
                }
                return collected
            }
        } catch {
            try Task.checkCancellation()
            return nil
        }
        defer { pieces.values.forEach { try? FileManager.default.removeItem(at: $0) } }
        let joined = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: joined.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return nil }
        do {
            let output = try FileHandle(forWritingTo: joined)
            defer { try? output.close() }
            for index in ranges.indices {
                guard let piece = pieces[index] else { throw QishuiError.unavailable }
                try output.write(contentsOf: Data(contentsOf: piece, options: .mappedIfSafe))
            }
        } catch {
            try? FileManager.default.removeItem(at: joined)
            return nil
        }
        return joined
    }
}
