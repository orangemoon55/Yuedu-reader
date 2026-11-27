import AVFoundation
import CryptoKit
import Foundation

// Protocol flow referenced from MeloX/Core/Cloud and Core/Networking at
// 9c2f87b57b54ddbab76a4a53736f4840719a0947 (GPL-3.0-only).
extension NeteaseAPI {
    /// Keep every stage bound to the login that selected the file.
    static func cloudUpload(fileAt url: URL, using client: NeteaseClient = .shared) async throws {
        if MusicProviderContext.shared.current == .kugou { return try await PlatformMusicAPI.shared.cloudUpload(fileAt: url) }
        try MusicProviderContext.shared.requireNetease()
        guard let authentication = client.authenticationFingerprint else { throw NeteaseAPIError.needLogin }
        func checkSession() throws {
            try Task.checkCancellation()
            guard client.authenticationFingerprint == authentication else { throw CancellationError() }
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try await CloudUploadFile.prepare(url)
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }

        func request<T: Decodable>(_ type: T.Type, _ path: String, _ payload: [String: Any], web: Bool = false) async throws -> T {
            try checkSession()
            var data = try await (web ? client.weapi(path, payload) : client.eapi(path, payload))
            // Some accounts receive an empty WEAPI token response; only that
            // transport failure falls back to EAPI, never a business rejection.
            if web && data.isEmpty {
                try checkSession()
                data = try await client.eapi(path, payload)
            }
            try checkSession()
            do {
                return try client.decoded(type, from: data)
            } catch NeteaseAPIError.decoding {
                let stage: String
                switch path {
                case "/cloud/upload/check": stage = String(localized: "上传预检查")
                case "/nos/token/alloc": stage = String(localized: "获取上传凭证")
                case "/upload/cloud/info/v2": stage = String(localized: "提交歌曲信息")
                default: stage = String(localized: "发布云盘歌曲")
                }
                throw NeteaseAPIError.business(code: -1, message: String(localized: "\(stage)：服务器响应格式不兼容"))
            }
        }
        let check = try await request(CloudUploadCheck.self, "/cloud/upload/check", [
            "bitrate": "999000", "ext": "", "length": file.size, "md5": file.md5, "songId": "0", "version": 1
        ])
        let tokenPayload: [String: Any] = [
            "bucket": "", "ext": file.ext, "filename": file.stem,
            "local": false, "nos_product": 3, "type": "audio", "md5": file.md5
        ]
        let metadata = try await request(CloudUploadToken.self, "/nos/token/alloc", tokenPayload)
        if check.needUpload {
            let bucket = "jd-musicrep-privatecloud-audio-public"
            var payload = tokenPayload
            payload["bucket"] = bucket
            // NOS needs its own token; the metadata resourceId is retained for registration.
            let token = try await request(CloudUploadToken.self, "/nos/token/alloc", payload, web: true)
            try checkSession()
            try await client.uploadCloudFile(file.url, bucket: bucket, objectKey: token.result.objectKey,
                                             token: token.result.token, md5: file.md5, size: file.size)
        }
        let info = try await request(CloudUploadSong.self, "/upload/cloud/info/v2", [
            "md5": file.md5, "songid": check.songID, "filename": file.filename,
            "song": file.title, "artist": file.artist, "album": file.album,
            "bitrate": "999000", "resourceId": metadata.result.resourceID
        ])
        guard !info.songID.isEmpty, info.songID != "0" else { throw NeteaseAPIError.decoding("Missing cloud song ID") }
        _ = try await request(CodeOnly.self, "/cloud/pub/v2", ["songid": info.songID])
    }
}

private struct CloudUploadCheck: Decodable {
    let needUpload: Bool
    let songID: String
    enum CodingKeys: String, CodingKey { case needUpload, songId }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let flag = try? c.decode(Bool.self, forKey: .needUpload) { needUpload = flag }
        else if let flag = try? c.decode(Int.self, forKey: .needUpload) { needUpload = flag != 0 }
        else {
            let flag = try c.decode(String.self, forKey: .needUpload).lowercased()
            guard ["true", "false", "1", "0"].contains(flag) else {
                throw NeteaseAPIError.decoding("Invalid upload check flag")
            }
            needUpload = flag == "true" || flag == "1"
        }
        songID = try c.cloudSongID()
    }
}

private struct CloudUploadSong: Decodable {
    let songID: String
    init(from decoder: Decoder) throws {
        songID = try decoder.container(keyedBy: CloudUploadCheck.CodingKeys.self).cloudSongID()
    }
}

private extension KeyedDecodingContainer where Key == CloudUploadCheck.CodingKeys {
    /// Upload IDs are server handles, not catalogue track IDs. In particular,
    /// upload/check can return a long hexadecimal string when needUpload=false.
    /// Preserve it verbatim when passing it to upload/cloud/info/v2.
    func cloudSongID() throws -> String {
        if let id = try? decode(String.self, forKey: .songId), !id.isEmpty { return id }
        return String(try decode(Int64.self, forKey: .songId))
    }
}

private struct CloudUploadToken: Decodable {
    struct Token: Decodable {
        let objectKey: String
        let resourceID: String
        let token: String
        enum CodingKeys: String, CodingKey { case objectKey, resourceId, token }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            objectKey = try c.decode(String.self, forKey: .objectKey)
            token = try c.decode(String.self, forKey: .token)
            if let value = try? c.decode(String.self, forKey: .resourceId) { resourceID = value }
            else { resourceID = String(try c.decode(Int64.self, forKey: .resourceId)) }
        }
    }
    let result: Token
}

/// 云盘上传前的本地快照：复制到临时目录、计算 MD5 并读取标签与时长。
struct CloudUploadFile {
    let url: URL
    let filename: String
    let ext: String
    let stem: String
    let size: Int64
    let md5: String
    let title: String
    let artist: String
    let album: String
    let durationMS: Int
    /// 文件自带的歌手标签；`artist` 在缺失时为占位文字。
    let taggedArtist: String?

    static func prepare(_ source: URL) async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coda-cloud-\(UUID().uuidString)")
        do {
            // Read a stable snapshot and hash in chunks, away from the UI thread.
            let snapshot = try await Task.detached(priority: .userInitiated) { () throws -> (URL, Int64, String) in
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
                    throw NeteaseAPIError.business(code: -1, message: String(localized: "请选择有效的音频文件"))
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let copy = directory.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: copy)
                let handle = try FileHandle(forReadingFrom: copy)
                defer { try? handle.close() }
                var hash = Insecure.MD5()
                var length: Int64 = 0
                while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                    try Task.checkCancellation()
                    hash.update(data: chunk)
                    length += Int64(chunk.count)
                }
                return (copy, length, hash.finalize().map { String(format: "%02x", $0) }.joined())
            }.value
            try Task.checkCancellation()
            let asset = AVURLAsset(url: snapshot.0)
            guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
                throw NeteaseAPIError.business(code: -1, message: String(localized: "请选择有效的音频文件"))
            }
            var values: [AVMetadataKey: String] = [:]
            for item in (try? await asset.load(.commonMetadata)) ?? [] {
                if let key = item.commonKey, let value = try? await item.load(.stringValue), !value.isEmpty {
                    values[key] = value
                }
            }
            let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
            let fallback = source.deletingPathExtension().lastPathComponent
            let normalized = fallback.components(separatedBy: .whitespacesAndNewlines).joined().replacingOccurrences(of: ".", with: "_")
            return Self(url: snapshot.0, filename: source.lastPathComponent,
                        ext: source.pathExtension.lowercased(), stem: normalized.isEmpty ? "music" : normalized,
                        size: snapshot.1, md5: snapshot.2, title: values[.commonKeyTitle] ?? fallback,
                        artist: values[.commonKeyArtist] ?? String(localized: "未知歌手"),
                        album: values[.commonKeyAlbumName] ?? String(localized: "未知专辑"),
                        durationMS: duration.isFinite && duration > 0 ? Int(duration * 1000) : 0,
                        taggedArtist: values[.commonKeyArtist])
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
