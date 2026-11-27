import Combine
import CryptoKit
import Foundation
import Security

enum MusicProvider: String, Codable, CaseIterable, Identifiable {
    case netease, qq, kugou, qishui
    var id: String { rawValue }
    var supportsFavoriteChanges: Bool { supports(.favoriteChanges) }
    var supportsDownloads: Bool { supports(.downloads) }
    /// NetEase's playlistChanges covers track edits only; renaming is wired per platform.
    var supportsPlaylistRename: Bool { self != .netease && supports(.playlistChanges) }
    var name: String {
        switch self { case .netease: return "网易云音乐"; case .qq: return "QQ 音乐"; case .kugou: return "酷狗音乐"; case .qishui: return "汽水音乐" }
    }
}

/// Readable by networking code without depending on the UI's executor.
final class MusicProviderContext: @unchecked Sendable {
    static let shared = MusicProviderContext()
    private let lock = NSLock()
    private let defaults: UserDefaults
    private var provider: MusicProvider
    init(provider: MusicProvider? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.provider = provider ?? MusicProvider(rawValue: defaults.string(forKey: "music.provider") ?? "") ?? .netease
    }
    private var revision = UUID()
    var current: MusicProvider { lock.withLock { provider } }
    var authenticationKey: String? {
        "\(current.rawValue):\(ticket):\(current == .netease ? NeteaseClient.shared.authenticationFingerprint ?? "guest" : "platform")"
    }
    var ticket: UUID { lock.withLock { revision } }
    func activate(_ value: MusicProvider) {
        lock.withLock { provider = value; revision = UUID() }
        defaults.set(value.rawValue, forKey: "music.provider")
    }
    func requireNetease() throws {
        guard current == .netease else { throw MusicProviderError.unsupported }
    }
    func check(_ ticket: UUID) throws {
        try Task.checkCancellation()
        guard self.ticket == ticket else { throw CancellationError() }
    }
}

enum MusicProviderError: LocalizedError {
    case unsupported, missingTrack, storage(OSStatus)
    var errorDescription: String? {
        switch self {
        case .unsupported: return "当前音乐平台暂不支持此功能"
        case .missingTrack: return "歌曲来源信息已失效，请重新加载歌单或搜索"
        case .storage(let code): return "账号凭证保存失败（\(code)）"
        }
    }
}

/// Adapter persistence and saved account sessions live in this app's keychain.
/// No cookies or tokens are written to UserDefaults or logs.
final class ProviderCredentialDefaults {
    static let shared = ProviderCredentialDefaults()
    private let service = CodaIdentity.keychainService("music-accounts")
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] }
    private(set) var lastError: OSStatus?
    #if os(macOS)
    // Providers repeatedly read their defaults during request signing. Ask for
    // each credential once per process, including after cancelled authorization.
    // Successful writes replace this cache so a new login takes effect at once.
    private let credentialLock = NSRecursiveLock()
    private var cachedCredentials: [String: Data] = [:]
    private var attemptedReads: Set<String> = []
    #endif
    func data(forKey key: String) -> Data? {
        #if os(macOS)
        credentialLock.lock()
        defer { credentialLock.unlock() }
        if attemptedReads.contains(key) { return cachedCredentials[key] }
        #endif
        var q = query
        q[kSecAttrAccount as String] = key
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        lastError = status == errSecSuccess ? nil : status
        let data = status == errSecSuccess ? result as? Data : nil
        #if os(macOS)
        attemptedReads.insert(key)
        cachedCredentials[key] = data
        #endif
        return data
    }
    func dictionary(forKey key: String) -> [String: Any]? {
        guard let data = data(forKey: key) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    func string(forKey key: String) -> String? { data(forKey: key).flatMap { String(data: $0, encoding: .utf8) } }
    @discardableResult func set(_ value: Any, forKey key: String) -> Bool {
        #if os(macOS)
        credentialLock.lock()
        defer { credentialLock.unlock() }
        #endif
        let data: Data?
        if let bytes = value as? Data { data = bytes }
        else if let text = value as? String { data = Data(text.utf8) }
        else { data = try? JSONSerialization.data(withJSONObject: value) }
        guard let data else { return false }
        var q = query
        q[kSecAttrAccount as String] = key
        let attributes = [kSecValueData as String: data]
        var status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        lastError = status == errSecSuccess ? nil : status
        #if os(macOS)
        if status == errSecSuccess {
            attemptedReads.insert(key)
            cachedCredentials[key] = data
        }
        #endif
        return status == errSecSuccess
    }
    func removeObject(forKey key: String) {
        #if os(macOS)
        credentialLock.lock()
        defer { credentialLock.unlock() }
        #endif
        var q = query; q[kSecAttrAccount as String] = key
        let status = SecItemDelete(q as CFDictionary)
        lastError = status == errSecSuccess || status == errSecItemNotFound ? nil : status
        #if os(macOS)
        if status == errSecSuccess || status == errSecItemNotFound {
            attemptedReads.insert(key)
            cachedCredentials[key] = nil
        }
        #endif
    }
}

extension Notification.Name {
    static let qqLoginDidUpdate = Notification.Name("coda.qqLoginDidUpdate")
    static let kugouLoginDidUpdate = Notification.Name("coda.kugouLoginDidUpdate")
}

extension Data {
    func md5Hex() -> String { Insecure.MD5.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}
func providerLocalized(_ chinese: String, _ english: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
}
