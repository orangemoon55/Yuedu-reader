import Foundation

enum CodaPaths {
    static var applicationSupport: URL {
        #if DEBUG
        if let path = Bundle.main.object(forInfoDictionaryKey: "CodaTestingDirectory") as? String {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(CodaIdentity.namespace, isDirectory: true)
    }

    static var imageCache: URL {
        #if DEBUG
        if isOfflineUITest { return applicationSupport.appendingPathComponent("images", isDirectory: true) }
        #endif
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(CodaIdentity.namespace + "/images", isDirectory: true)
    }

    static var isOfflineUITest: Bool {
        #if DEBUG
        return Bundle.main.object(forInfoDictionaryKey: "CodaTestingDirectory") is String
            && Bundle.main.object(forInfoDictionaryKey: "CodaOfflineUITest") as? Bool == true
        #else
        return false
        #endif
    }

    static var networkCache: URL {
        if isOfflineUITest { return applicationSupport.appendingPathComponent("network-cache") }
        let identifier = CodaIdentity.namespace
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(identifier, isDirectory: true)
    }

    /// Reserved for music-owned scratch files. Existing unscoped upload and
    /// URLSession temporary files cannot safely be attributed to this module.
    static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(CodaIdentity.namespace, isDirectory: true)
    }

    /// Never replace URLCache.shared: it belongs to the host and its clients.
    /// The embedded cache is reserved for explicitly opted-in music clients;
    /// existing default-session responses remain protected host-owned data.
    private static let embeddedResponseCache = URLCache(
        memoryCapacity: 4 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024,
        directory: networkCache.appendingPathComponent("responses", isDirectory: true))
    static var responseCache: URLCache {
        CodaIdentity.isEmbeddedHost ? embeddedResponseCache : .shared
    }

    /// The host app bundle and its global Library/Documents/tmp are not music.
    static var applicationBundleRoots: [URL] {
        CodaIdentity.isEmbeddedHost ? [] : [Bundle.main.bundleURL]
    }

    static var storageRoots: [URL] {
        if isOfflineUITest { return [applicationSupport] }
        if CodaIdentity.isEmbeddedHost {
            return [applicationSupport, networkCache, temporaryDirectory]
        }
        #if os(iOS)
        // These are inside this app's sandbox, including preferences,
        // URLSession data and any update IPA saved to Files.
        return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            + FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            + [FileManager.default.temporaryDirectory]
        #else
        return [applicationSupport, networkCache]
        #endif
    }
}
