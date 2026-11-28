import Combine
import Foundation

struct MusicAccount: Codable, Identifiable {
    let id: String
    let provider: MusicProvider
    let userID: String
    var nickname: String
    var credentials: [String: String]
    var membership: MusicMembershipSnapshot? = nil
    var avatarURL: String? = nil
}

enum MusicAccountValidity: String {
    case checking = "验证中…"
    case valid = "有效"
    case invalid = "失效"
    case unknown = "暂无法验证"
}

@MainActor
final class MusicAccountManager: ObservableObject {
    static let shared = MusicAccountManager()
    @Published private(set) var accounts: [MusicAccount] = []
    @Published private(set) var isSwitching = false
    // NetEase (including guest) logout does not rotate the provider ticket.
    // Invalidate outstanding search activations even when no saved ID exists.
    @Published private(set) var searchActivationGeneration = UUID()
    let searchSessionLifecycle = CodaSearchSessionLifecycle()
    var searchSessionIdentity: CodaSearchSessionIdentity {
        CodaSearchSessionIdentity(revision: AccountStore.shared.sessionRevision,
            provider: AccountStore.shared.provider, ticket: MusicProviderContext.shared.ticket,
            authenticationKey: MusicProviderContext.shared.authenticationKey)
    }
    @Published private(set) var refreshingMembershipIDs: Set<String> = []
    @Published private(set) var failedMembershipIDs: Set<String> = []
    @Published private var validityResults: [String: (credentials: [String: String], status: MusicAccountValidity)] = [:]
    /// Checks in flight, keyed by account. `.checking` is reported only while
    /// one runs: a stored `.checking` marker left by a cancelled check kept the
    /// sidebar badge's 30 Hz pulse (and a window layout per frame) running forever.
    @Published private var validityChecks: [String: UUID] = [:]

    func validity(for item: MusicAccount) -> MusicAccountValidity {
        if let result = validityResults[item.id], result.credentials == item.credentials { return result.status }
        return validityChecks[item.id] == nil ? .unknown : .checking
    }

    private func checkValidity(_ item: MusicAccount) async {
        let check = UUID()
        validityChecks[item.id] = check
        defer { if validityChecks[item.id] == check { validityChecks[item.id] = nil } }
        let status: MusicAccountValidity
        do {
            switch item.provider {
            case .netease:
                let client = NeteaseClient(configuration: .ephemeral, persistsCookies: false)
                client.setCookies(item.credentials)
                let data = try await client.eapi("/nuser/account/get")
                let response = try client.decoded(NeteaseAPI.AccountResponse.self, from: data)
                if response.code == 200 {
                    status = response.profile.map { String($0.userId) == item.userID ? .valid : .invalid } ?? .invalid
                } else { status = .unknown }
            case .qq:
                let auth = QQMusicAuth(persistsSession: false)
                auth.importCookies(item.credentials, nickname: item.nickname)
                status = await QQMusicAPI.shared.sessionValidity(credential: auth.collectionCredential)
            case .qishui:
                let profile = try await QishuiMusicAPI.shared.profile(credentials: item.credentials)
                status = QishuiMusicAPI.string(profile["id"]) == item.userID ? .valid : .invalid
            case .kugou:
                status = try await KugouMusicAPI.shared.loginValidity(credentials: item.credentials)
            }
        } catch QishuiError.expiredLogin { status = .invalid }
        catch NeteaseAPIError.needLogin { status = .invalid }
        catch is CancellationError { return }
        catch let error as URLError where error.code == .cancelled { return }
        catch { status = .unknown }
        // A finished answer stays valid for these credentials even if the
        // caller was cancelled meanwhile; only a changed account discards it.
        guard accounts.contains(where: { $0.id == item.id && $0.credentials == item.credentials }) else { return }
        validityResults[item.id] = (item.credentials, status)
    }

    private let key = "music.savedAccounts.v1"
    private init() {
        if let data = ProviderCredentialDefaults.shared.data(forKey: key), let saved = try? JSONDecoder().decode([MusicAccount].self, from: data) { accounts = saved }
    }
    var currentID: String? {
        let account = AccountStore.shared
        guard account.isLoggedIn else { return nil }
        let uid: String
        switch account.provider {
        case .netease: uid = String(account.profile?.userId ?? 0)
        case .qq: uid = QQMusicAuth.shared.uin
        case .qishui: uid = QishuiMusicAPI.shared.userID
        case .kugou: uid = KugouMusicAuth.shared.userId
        }
        return "\(account.provider.rawValue):\(uid)"
    }
    func rememberCurrent() throws {
        let account = AccountStore.shared
        guard let id = currentID, let profile = account.profile else { return }
        let credentials: [String: String]
        switch account.provider {
        case .netease: credentials = NeteaseClient.shared.authenticationCookies()
        case .qq: credentials = QQMusicAuth.shared.exportedCredentials
        case .qishui: credentials = QishuiMusicAPI.shared.credentials
        case .kugou: credentials = KugouMusicAuth.shared.exportedCredentials
        }
        var item = MusicAccount(id: id, provider: account.provider, userID: String(id.dropFirst(account.provider.rawValue.count + 1)), nickname: profile.nickname, credentials: credentials)
        let existing = accounts.first { $0.id == id }
        item.membership = existing?.membership
        item.avatarURL = profile.avatarUrl.flatMap { $0.isEmpty ? nil : $0 } ?? existing?.avatarURL
        var next = accounts.filter { $0.id != id }; next.append(item)
        try persist(next)
    }
    struct LoginTransfer: Codable {
        let format: String
        let version: Int
        let accounts: [MusicAccount]
    }

    private enum TransferError: LocalizedError {
        case empty, invalid
        var errorDescription: String? {
            switch self {
            case .empty: return "没有可导出的登录数据，请先登录账号。"
            case .invalid: return "剪贴板中没有有效的 Coda 登录数据，或数据版本不受支持。"
            }
        }
    }

    func exportLoginData() throws -> String {
        try rememberCurrent()
        guard !accounts.isEmpty else { throw TransferError.empty }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LoginTransfer(format: "coda-login", version: 1, accounts: accounts))
        return String(decoding: data, as: UTF8.self)
    }

    /// Product/version validation happens before accessing or writing credentials.
    static func decodeLoginTransfer(_ text: String) throws -> LoginTransfer {
        guard text.utf8.count <= 5_000_000,
              let transfer = try? JSONDecoder().decode(LoginTransfer.self, from: Data(text.utf8)),
              transfer.format == "coda-login", transfer.version == 1,
              !transfer.accounts.isEmpty, transfer.accounts.count <= 100 else { throw TransferError.invalid }
        return transfer
    }

    /// Validate the entire payload before writing; importing never replaces the active session.
    func importLoginData(_ text: String) throws -> Int {
        guard !isSwitching else { throw MusicProviderError.unsupported }
        let transfer = try Self.decodeLoginTransfer(text)
        var seen = Set<String>()
        for item in transfer.accounts {
            guard !item.userID.isEmpty, item.userID != "0",
                  item.id == "\(item.provider.rawValue):\(item.userID)",
                  seen.insert(item.id).inserted else { throw TransferError.invalid }
            switch item.provider {
            case .netease:
                guard Int(item.userID).map({ $0 > 0 }) == true,
                      item.credentials["MUSIC_U"]?.isEmpty == false else { throw TransferError.invalid }
            case .qq:
                let candidate = QQMusicAuth(persistsSession: false)
                candidate.importCookies(item.credentials, nickname: item.nickname)
                guard candidate.uin == item.userID, !item.credentials.isEmpty else { throw TransferError.invalid }
            case .qishui:
                guard item.credentials["userid"] == item.userID, QishuiMusicAPI.validSessionID(item.credentials["sessionid"] ?? "") else { throw TransferError.invalid }
            case .kugou:
                let uid = (item.credentials["userid"] ?? item.credentials["user_id"] ?? "").filter(\.isNumber)
                guard uid == item.userID, item.credentials["token"]?.isEmpty == false else { throw TransferError.invalid }
            }
        }
        // Capture current credentials in the same write so a storage failure is atomic.
        let activeID = currentID
        let imported = transfer.accounts.filter { $0.id != activeID }
        let importedIDs = Set(imported.map(\.id))
        try persist(accounts.filter { !importedIDs.contains($0.id) } + imported)
        return imported.count
    }

    private func persist(_ next: [MusicAccount]) throws {
        let data = try JSONEncoder().encode(next)
        guard ProviderCredentialDefaults.shared.set(data, forKey: key) else { throw MusicProviderError.storage(ProviderCredentialDefaults.shared.lastError ?? -1) }
        accounts = next
    }

    func refreshMemberships() async {
        for item in accounts {
            guard !Task.isCancelled else { return }
            await refreshStatus(of: item)
        }
    }

    /// Refreshes one saved account's login validity and membership.
    func refreshStatus(of item: MusicAccount) async {
        guard refreshingMembershipIDs.insert(item.id).inserted else { return }
        defer { refreshingMembershipIDs.remove(item.id) }
        await checkValidity(item)
        guard !Task.isCancelled else { return }
        do {
            let membership: MusicMembership
            switch item.provider {
            case .netease:
                let client = NeteaseClient(configuration: .ephemeral, persistsCookies: false)
                client.setCookies(item.credentials)
                let data = try await client.eapi("/music-vip-membership/client/vip/info", ["userId": item.userID])
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                membership = MusicMembership.netease(json)
            case .qq:
                let auth = QQMusicAuth(persistsSession: false)
                auth.importCookies(item.credentials, nickname: item.nickname)
                membership = try await auth.membershipStatus()
            case .qishui:
                membership = try await QishuiMusicAPI.shared.membership(credentials: item.credentials)
            case .kugou:
                membership = try await KugouMusicAPI.shared.membershipStatus(credentials: item.credentials)
            }
            guard !Task.isCancelled,
                  let index = accounts.firstIndex(where: { $0.id == item.id && $0.credentials == item.credentials }) else { return }
            guard membership != .unknown else { failedMembershipIDs.insert(item.id); return }
            var next = accounts
            next[index].membership = .init(membership: membership, checkedAt: Date())
            try persist(next)
            failedMembershipIDs.remove(item.id)
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            if accounts.contains(where: { $0.id == item.id && $0.credentials == item.credentials }) {
                failedMembershipIDs.insert(item.id)
            }
        }
    }

    /// Membership line shown under an account in settings and the sidebar.
    func membershipTitle(for item: MusicAccount) -> String {
        if refreshingMembershipIDs.contains(item.id), item.membership == nil { return "查询中…" }
        let title = item.membership?.membership.rawValue ?? MusicMembership.unknown.rawValue
        return failedMembershipIDs.contains(item.id) && item.membership != nil ? title + "（待更新）" : title
    }
    /// Search uses the normal lifecycle, but keeps the receipt from its commit,
    /// not a newly sampled ticket after asynchronous account bootstrap finishes.
    func selectProviderForSearch(_ provider: MusicProvider, request: UUID) async throws -> UUID {
        guard !isSwitching else { throw MusicProviderError.unsupported }
        try Task.checkCancellation()
        let generation = searchActivationGeneration
        let origin = searchSessionIdentity
        var revisionObservation: AnyCancellable?
        defer { revisionObservation?.cancel() }
        var committedTicket: UUID?
        var committedAuthenticationKey: String?
        try await selectProvider(provider, activationCommitted: {
            let ticket = MusicProviderContext.shared.ticket
            let authenticationKey = MusicProviderContext.shared.authenticationKey
            committedTicket = ticket
            committedAuthenticationKey = authenticationKey
            revisionObservation = self.searchSessionLifecycle.observeNextCommit(
                request: request, origin: origin, provider: provider,
                ticket: ticket, authenticationKey: authenticationKey,
                revisions: AccountStore.shared.$sessionRevision,
                snapshot: { revision in
                    CodaSearchSessionIdentity(revision: revision,
                        provider: AccountStore.shared.provider,
                        ticket: MusicProviderContext.shared.ticket,
                        authenticationKey: MusicProviderContext.shared.authenticationKey)
                })
        })
        try Task.checkCancellation()
        guard let committedTicket, !isSwitching, searchActivationGeneration == generation,
              searchSessionLifecycle.owns(request, session: searchSessionIdentity),
              AccountStore.shared.provider == provider,
              MusicProviderContext.shared.current == provider,
              CodaSearchInteractionPolicy.activationReceiptIsCurrent(
                ticket: committedTicket, authenticationKey: committedAuthenticationKey,
                currentTicket: MusicProviderContext.shared.ticket,
                currentAuthenticationKey: MusicProviderContext.shared.authenticationKey) else {
            throw CancellationError()
        }
        return committedTicket
    }

    func selectProvider(_ provider: MusicProvider, activationCommitted: (() -> Void)? = nil) async throws {
        guard !isSwitching, provider != AccountStore.shared.provider else { return }
        if let saved = accounts.last(where: { $0.provider == provider }) {
            try await select(saved, activationCommitted: activationCommitted)
            return
        }
        try rememberCurrent()
        isSwitching = true
        defer { isSwitching = false }
        await activate(provider, activationCommitted: activationCommitted)
    }
    /// Whether the active platform is already being browsed without an account.
    func isBrowsingAsGuest(_ provider: MusicProvider) -> Bool {
        AccountStore.shared.provider == provider && !AccountStore.shared.isLoggedIn
    }

    /// Browses a platform signed out. Accounts stay in the saved list and can be
    /// switched back to; only this device's local session for the platform is
    /// cleared, and nothing is revoked on the server.
    func browseAsGuest(_ provider: MusicProvider) async throws {
        guard !isSwitching, !isBrowsingAsGuest(provider) else { return }
        try rememberCurrent()
        try preserveInactiveSession(of: provider)
        isSwitching = true
        defer { isSwitching = false }
        switch provider {
        case .netease:
            try NeteaseClient.shared.clearAuthCookies()
            AccountSnapshotStorage.shared.clear()
        case .qq: QQMusicAuth.shared.logout()
        case .qishui: try QishuiMusicAPI.shared.logout()
        case .kugou: KugouMusicAuth.shared.logout()
        }
        await activate(provider)
    }

    /// A platform that is not active may still hold a session; keep it switchable
    /// before clearing it. NetEase sessions are always saved when leaving the platform.
    private func preserveInactiveSession(of provider: MusicProvider) throws {
        guard provider != AccountStore.shared.provider else { return }
        let session: (userID: String, nickname: String, credentials: [String: String])?
        switch provider {
        case .netease: session = nil
        case .qq:
            let auth = QQMusicAuth.shared
            session = auth.isLoggedIn ? (auth.uin, auth.nickname, auth.exportedCredentials) : nil
        case .qishui:
            let api = QishuiMusicAPI.shared
            session = api.isLoggedIn ? (api.userID, api.nickname, api.credentials) : nil
        case .kugou:
            let auth = KugouMusicAuth.shared
            session = auth.isLoggedIn ? (auth.userId, auth.nickname, auth.exportedCredentials) : nil
        }
        guard let session, !session.userID.isEmpty else { return }
        let id = "\(provider.rawValue):\(session.userID)"
        guard !accounts.contains(where: { $0.id == id }) else { return }
        let item = MusicAccount(id: id, provider: provider, userID: session.userID,
                                nickname: session.nickname.isEmpty ? provider.name : session.nickname,
                                credentials: session.credentials)
        try persist(accounts + [item])
    }

    func select(_ item: MusicAccount, activationCommitted: (() -> Void)? = nil) async throws {
        guard !isSwitching, item.id != currentID else { return }
        try rememberCurrent()
        isSwitching = true
        defer { isSwitching = false }
        // Persist before replacing a session; keychain failure leaves the current login intact.
        switch item.provider {
        case .netease: try NeteaseClient.shared.replaceAuthentication(with: item.credentials)
        case .qq: QQMusicAuth.shared.importCookies(item.credentials, nickname: item.nickname)
        case .qishui: try QishuiMusicAPI.shared.restore(item.credentials)
        case .kugou: KugouMusicAuth.shared.restore(item.credentials)
        }
        await activate(item.provider, activationCommitted: activationCommitted)
    }
    func saveAndActivate(provider: MusicProvider, credentials: [String: String], nickname: String) async throws {
        guard provider != .netease, !isSwitching else { throw MusicProviderError.unsupported }
        isSwitching = true
        defer { isSwitching = false }
        if provider == .qishui {
            let verified = try await QishuiMusicAPI.shared.profile(credentials: credentials)
            guard QishuiMusicAPI.string(verified["id"]) == credentials["userid"] else { throw QishuiError.expiredLogin }
        }
        try Task.checkCancellation()
        try rememberCurrent()
        let userID: String
        if provider == .qq {
            let candidate = QQMusicAuth(persistsSession: false)
            candidate.importCookies(credentials, nickname: nickname)
            userID = candidate.uin
        } else { userID = credentials["userid"] ?? "" }
        guard !userID.isEmpty else { throw MusicProviderError.missingTrack }
        let id = "\(provider.rawValue):\(userID)"
        let item = MusicAccount(id: id, provider: provider, userID: userID, nickname: nickname, credentials: credentials)
        var next = accounts.filter { $0.id != id }; next.append(item)
        try persist(next)
        if provider == .qq { QQMusicAuth.shared.importCookies(credentials, nickname: nickname) }
        else if provider == .qishui { try QishuiMusicAPI.shared.restore(credentials) }
        else { KugouMusicAuth.shared.restore(credentials) }
        await activate(provider)
    }

    /// Saves a QR-scanned account to the list without switching platform or replacing the active session.
    /// When nobody is signed in, the new account becomes active and its platform is selected.
    @discardableResult
    func addAccount(provider: MusicProvider, credentials: [String: String], nickname: String) async throws -> MusicAccount {
        guard !isSwitching else { throw MusicProviderError.unsupported }
        var name = nickname
        var avatar: String?
        let userID: String
        switch provider {
        case .netease:
            let client = NeteaseClient(configuration: .ephemeral, persistsCookies: false)
            client.setCookies(credentials)
            let data = try await client.eapi("/nuser/account/get")
            guard let profile = try client.decoded(NeteaseAPI.AccountResponse.self, from: data).profile else { throw NeteaseAPIError.needLogin }
            userID = String(profile.userId)
            if !profile.nickname.isEmpty { name = profile.nickname }
            avatar = profile.avatarUrl
        case .qq:
            let candidate = QQMusicAuth(persistsSession: false)
            candidate.importCookies(credentials, nickname: nickname)
            userID = candidate.uin
        case .qishui:
            let verified = try await QishuiMusicAPI.shared.profile(credentials: credentials)
            guard QishuiMusicAPI.string(verified["id"]) == credentials["userid"] else { throw QishuiError.expiredLogin }
            userID = credentials["userid"] ?? ""
        case .kugou:
            userID = credentials["userid"] ?? ""
        }
        try Task.checkCancellation()
        guard !userID.isEmpty, userID != "0" else { throw MusicProviderError.missingTrack }
        try rememberCurrent()
        let id = "\(provider.rawValue):\(userID)"
        var item = MusicAccount(id: id, provider: provider, userID: userID, nickname: name, credentials: credentials)
        let existing = accounts.first { $0.id == id }
        item.membership = existing?.membership
        item.avatarURL = avatar.flatMap { $0.isEmpty ? nil : $0 } ?? existing?.avatarURL
        var next = accounts.filter { $0.id != id }; next.append(item)
        try persist(next)
        let account = AccountStore.shared
        // With no active session (e.g. first launch), the new account becomes active on its own platform.
        if !account.isLoggedIn { try await select(item) }
        return item
    }

    func addedMessage(for item: MusicAccount) -> String {
        currentID == item.id ? "已登录\(item.nickname)" : "已添加\(item.nickname)，可在账号列表中切换"
    }

    private func activate(_ provider: MusicProvider, activationCommitted: (() -> Void)? = nil) async {
        PlayerService.shared.resetForMusicAccountChange()
        MusicProviderContext.shared.activate(provider)
        activationCommitted?()
        await AccountStore.shared.changeProvider(provider)
    }
    func forgetCurrent() throws {
        searchSessionLifecycle.invalidate()
        searchActivationGeneration = UUID()
        guard let id = currentID else { return }
        try persist(accounts.filter { $0.id != id })
    }
    func remove(_ item: MusicAccount) async throws {
        guard !isSwitching else { return }
        if currentID == item.id { try await AccountStore.shared.logout() }
        else { try persist(accounts.filter { $0.id != item.id }) }
    }
}
