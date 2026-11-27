import Foundation

/// Private clients for looking songs up on platforms other than the active
/// one. Each is built from that platform's saved account (or anonymously) and
/// never touches the shared clients, so the active login, catalog and
/// platform switching stay exactly as they are.
@MainActor
final class UnblockSessionPool {
    static let shared = UnblockSessionPool()

    private var netease: (credentials: [String: String]?, client: NeteaseClient)?
    private var qq: (credentials: [String: String]?, api: QQMusicAPI)?
    private var kugou: (credentials: [String: String]?, api: KugouMusicAPI)?
    private var qishui: (credentials: [String: String], api: QishuiMusicAPI)?

    /// The most recently saved account of a platform; credentials stay in memory only.
    func credentials(for provider: MusicProvider) -> [String: String]? {
        MusicAccountManager.shared.accounts
            .last { $0.provider == provider && !$0.credentials.isEmpty }?
            .credentials
    }

    func hasAccount(_ provider: MusicProvider) -> Bool {
        credentials(for: provider) != nil
    }

    func neteaseClient() -> NeteaseClient {
        let credentials = credentials(for: .netease)
        if let netease, netease.credentials == credentials { return netease.client }
        let client = NeteaseClient(configuration: .ephemeral, persistsCookies: false)
        if let credentials { _ = client.setCookies(credentials) }
        netease = (credentials, client)
        return client
    }

    func qqAPI() -> QQMusicAPI {
        let credentials = credentials(for: .qq)
        if let qq, qq.credentials == credentials { return qq.api }
        // Never nil: a nil authentication would fall back to the shared login.
        let auth = QQMusicAuth(persistsSession: false)
        if let credentials { auth.importCookies(credentials, nickname: nil) }
        let api = QQMusicAPI(authentication: auth)
        qq = (credentials, api)
        return api
    }

    func kugouAPI() -> KugouMusicAPI {
        let credentials = credentials(for: .kugou)
        if let kugou, kugou.credentials == credentials { return kugou.api }
        let api = KugouMusicAPI(playbackCredentials: credentials)
        kugou = (credentials, api)
        return api
    }

    /// Qishui serves full tracks only to a signed-in account.
    func qishuiAPI() -> QishuiMusicAPI? {
        guard let credentials = credentials(for: .qishui) else { qishui = nil; return nil }
        if let qishui, qishui.credentials == credentials { return qishui.api }
        let api = QishuiMusicAPI()
        guard (try? api.restore(credentials)) != nil else { qishui = nil; return nil }
        qishui = (credentials, api)
        return api
    }
}
