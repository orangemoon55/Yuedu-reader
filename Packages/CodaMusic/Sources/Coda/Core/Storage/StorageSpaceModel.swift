import Foundation

@MainActor
final class StorageSpaceModel: ObservableObject {
    @Published private(set) var snapshot: StorageUsageSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isClearing = false
    @Published private(set) var clearingCategory: StorageCategory?
    @Published private(set) var message: String?
    private let reader: StorageUsageReader
    private let audio: OfflineStore
    private let images: ImageCache
    private let accountScope: @MainActor () -> String?

    init(reader: StorageUsageReader? = nil, audio: OfflineStore = .shared, images: ImageCache = .shared,
         accountScope: @escaping @MainActor () -> String? = { AccountStore.shared.offlineScope }) {
        self.audio = audio
        self.images = images
        let musicCaches = Self.musicCacheDirectories
        self.reader = reader ?? StorageUsageReader(
            roots: CodaPaths.storageRoots + [images.directory] + CodaPaths.applicationBundleRoots + musicCaches,
            imageDirectory: images.directory, musicCacheDirectories: musicCaches,
            downloadDirectory: audio.directory.appendingPathComponent("downloads"),
            volumeURL: CodaPaths.applicationSupport, appDataLocations: Self.appDataLocations)
        self.accountScope = accountScope
    }

    /// The song cache the player on this platform actually writes to.
    static var musicCacheDirectories: [URL] {
        // Decrypted Qishui songs are played from the temporary folder.
        #if os(macOS)
        [CodaDirectories.caches("Audio"), QishuiAudio.directory]
        #else
        [AudioCache.shared.directory, QishuiAudio.directory]
        #endif
    }

    /// Where each kind of app data lives. Paths not listed count as `.other`.
    static var appDataLocations: [AppDataLocation] {
        let support = CodaPaths.applicationSupport
        let network = CodaPaths.networkCache
        func at(_ kind: AppDataKind, _ base: URL, _ names: String...) -> [AppDataLocation] {
            names.map { AppDataLocation(kind: kind, url: base.appendingPathComponent($0)) }
        }
        #if os(iOS)
        let temporary = [AppDataLocation(kind: .temporary, url: CodaIdentity.isEmbeddedHost
            ? CodaPaths.temporaryDirectory : FileManager.default.temporaryDirectory)]
        #else
        let temporary: [AppDataLocation] = []
        #endif
        return temporary
            + at(.library, support, "playlists", "platform-catalog.json")
            + at(.networkCache, network, "Cache.db", "Cache.db-shm", "Cache.db-wal", "fsCachedData")
            + at(.analysis, support, "Analysis")
            + at(.models, support, "Models")
            + at(.diagnostics, support, "Diagnostics", "seamtraces", "taps", "automix-feedback.jsonl")
            + at(.offlineIndex, support, "Offline")
            + at(.account, support, "cookies.json", "account-snapshot.json", "device-id")
            + CodaPaths.applicationBundleRoots.map { AppDataLocation(kind: .application, url: $0) }
    }

    @Published private(set) var clearingAppData: AppDataKind?

    /// Files written this recently may belong to a song that is playing or a
    /// download in flight, so clearing leaves them for the next time.
    static let inUseWindow: TimeInterval = 10 * 60

    private static var protectionNotice: String? {
        CodaIdentity.isEmbeddedHost
            ? String(localized: "受保护：宿主临时文件和共享网络缓存不纳入音乐统计或清理。") : nil
    }

    func clear(_ item: StorageItem) async {
        switch item {
        case .cache(let category): await clear(category)
        case .appData(let kind): await clear(kind)
        }
    }

    /// Deletes one rebuildable kind of app data. Folders are emptied rather
    /// than removed, so stores that created them at launch keep writing.
    func clear(_ kind: AppDataKind) async {
        guard !isClearing, !isLoading else { return }
        guard kind.isDeletable else {
            message = Self.protectionNotice ?? String(localized: "此数据受保护，未执行清理。")
            return
        }
        isClearing = true
        clearingAppData = kind
        message = nil
        defer { isClearing = false; clearingAppData = nil }
        if kind == .networkCache { CodaPaths.responseCache.removeAllCachedResponses() }
        let urls = Self.appDataLocations.filter { $0.kind == kind }.map(\.url)
        let keepAfter: Date? = kind == .temporary ? Date().addingTimeInterval(-Self.inUseWindow) : nil
        let failed = await Task.detached(priority: .userInitiated) {
            Self.remove(urls, keepingModifiedAfter: keepAfter, sparing: kind == .temporary ? [QishuiAudio.directory] : [])
        }.value
        message = failed ? String(localized: "部分数据未能删除") : String(localized: "已删除\(kind.title)")
        await reload(clearMessage: false)
    }

    /// Empties folders and removes files. With a cutoff, recently written
    /// files are kept, and folders are entered rather than removed whole.
    nonisolated static func remove(_ urls: [URL], keepingModifiedAfter cutoff: Date? = nil, sparing: [URL] = []) -> Bool {
        let manager = FileManager.default
        let spared = Set(sparing.map(\.standardizedFileURL.path))
        var failed = false
        func delete(_ target: URL) {
            do { try manager.removeItem(at: target) } catch {
                if (error as NSError).code != NSFileNoSuchFileError { failed = true }
            }
        }
        func empty(_ directory: URL) {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
            for child in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? [] {
                guard !spared.contains(child.standardizedFileURL.path) else { continue }
                let info = try? child.resourceValues(forKeys: Set(keys))
                guard let cutoff else { delete(child); continue }
                if info?.isDirectory == true, info?.isSymbolicLink != true {
                    empty(child)
                    if (try? manager.contentsOfDirectory(atPath: child.path))?.isEmpty == true { try? manager.removeItem(at: child) }
                } else if (info?.contentModificationDate ?? .distantFuture) < cutoff {
                    delete(child)
                }
            }
        }
        for url in urls {
            if CodaIdentity.isEmbeddedHost {
                let path = url.standardizedFileURL.path
                let allowed = (CodaPaths.storageRoots + [QishuiAudio.directory]).contains {
                    let root = $0.standardizedFileURL.path
                    return path == root || path.hasPrefix(root + "/")
                }
                guard allowed, (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                    failed = true
                    continue
                }
            }
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue { empty(url) } else { delete(url) }
        }
        return failed
    }

    func reload(clearMessage: Bool = true) async {
        guard !isLoading else { return }
        if clearMessage { message = Self.protectionNotice }
        else if let notice = Self.protectionNotice, message?.contains(notice) != true {
            message = message.map { $0 + "\n" + notice } ?? notice
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let files = try await audio.storageFiles()
            snapshot = await reader.read(audioFiles: files, accountScope: accountScope())
        } catch {
            // Image usage remains useful when the audio index cannot be read.
            var result = await reader.read(audioFiles: [], accountScope: accountScope())
            result.partial = true
            result.unavailableCategories = [.musicCache, .downloads, .appData]
            snapshot = result
            message = String(localized: "部分存储信息不可用")
        }
    }

    func clear(_ category: StorageCategory) async {
        guard !isClearing, !isLoading else { return }
        isClearing = true
        clearingCategory = category
        message = nil
        defer { isClearing = false; clearingCategory = nil }
        do {
            switch category {
            case .imageCache:
                try await images.clear()
                message = String(localized: "图片缓存已清除")
            case .musicCache:
                #if os(macOS)
                await EngineAudioCache.shared.removeAll()
                #else
                try await AudioCache.shared.clear()
                #endif
                let cutoff = Date().addingTimeInterval(-Self.inUseWindow)
                _ = await Task.detached(priority: .userInitiated) {
                    Self.remove([QishuiAudio.directory], keepingModifiedAfter: cutoff)
                }.value
                await DownloadManager.shared.refreshCachedTracks()
                message = String(localized: "歌曲缓存已清除")
            default: return
            }
        } catch { message = String(localized: "缓存清除失败") }
        await reload(clearMessage: false)
    }
}
