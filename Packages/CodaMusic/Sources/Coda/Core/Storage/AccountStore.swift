import Combine
import Foundation

/// Login state and the user's library: profile, liked track IDs, playlists.
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published private(set) var provider = MusicProviderContext.shared.current
    @Published private(set) var sessionRevision = UUID()
    @Published var profile: UserProfile?
    @Published var likedTrackIDs: Set<Int> = []
    @Published var userPlaylists: [PlaylistSummary] = []
    @Published var likedAlbums: [AlbumSummary] = []
    @Published var likedArtists: [ArtistSummary] = []
    @Published var isBootstrapped = false

    var isLoggedIn: Bool { hasAuthCookie && profile != nil }
    private var currentAuthenticationFingerprint: String? {
        if provider == .netease { return NeteaseClient.shared.authenticationFingerprint }
        guard hasAuthCookie else { return nil }
        return "\(provider.rawValue):\(MusicProviderContext.shared.ticket)"
    }
    var hasAuthCookie: Bool {
        switch provider {
        case .netease: return NeteaseClient.shared.isLoggedIn
        case .qq: return QQMusicAuth.shared.isLoggedIn
        case .qishui: return QishuiMusicAPI.shared.isLoggedIn
        case .kugou: return KugouMusicAuth.shared.isLoggedIn
        }
    }
    var authenticatedAccountID: Int? {
        guard provider == .netease, isLoggedIn, profileBinding == currentAuthenticationFingerprint else { return nil }
        return profile?.userId
    }
    var vipType: Int { profile?.vipType ?? 0 }
    var displayUserID: String {
        switch provider {
        case .netease: return profile.map { String($0.userId) } ?? ""
        case .qq: return QQMusicAuth.shared.uin
        case .qishui: return QishuiMusicAPI.shared.userID
        case .kugou: return KugouMusicAuth.shared.userId
        }
    }
    var offlineScope: String? {
        guard hasAuthCookie else { return provider == .netease ? "guest" : "\(provider.rawValue):guest" }
        guard profileBinding == currentAuthenticationFingerprint else { return nil }
        return profile.map { "\(provider.rawValue):\($0.userId)" }
    }
    private let libraryRefresh = PanelRefreshGate()
    private let sublistsRefresh = PanelRefreshGate()
    @Published private(set) var sublistsError: String?
    @Published private(set) var libraryRevision = 0
    private var mutationRevision = 0
    private var pendingLikes = 0
    private var pendingPlatformLikes: [Int: UUID] = [:]
    private var profileBinding: String?
    private var bootstrapGeneration = 0
    private var playlistSyncTask: Task<Void, Never>?
    private var playlistSyncID = UUID()
    private var networkObserver: AnyCancellable?
    private var qqRenewalTask: Task<Void, Never>?

    var likedSongsPlaylist: PlaylistSummary? {
        if provider != .netease { return userPlaylists.first(where: \.isLikedSongsList) }
        return userPlaylists.first(where: \.isLikedSongsList) ?? userPlaylists.first
    }

    var createdPlaylists: [PlaylistSummary] {
        if provider == .qishui { return userPlaylists.filter { !$0.isLikedSongsList && !$0.subscribed } }
        guard let uid = profile?.userId else { return [] }
        return userPlaylists.filter { $0.creator?.userId == uid && !$0.isLikedSongsList }
    }

    var subscribedPlaylists: [PlaylistSummary] {
        if provider == .qishui { return userPlaylists.filter(\.subscribed) }
        guard let uid = profile?.userId else { return [] }
        return userPlaylists.filter { $0.creator?.userId != uid }
    }

    private init() {
        if provider == .netease, let snapshot = AccountSnapshotStorage.shared.load(fingerprint: NeteaseClient.shared.authenticationFingerprint) {
            profile = snapshot.profile
            likedTrackIDs = snapshot.likedTrackIDs
            userPlaylists = snapshot.playlists
            profileBinding = snapshot.authenticationFingerprint
        }
    }

    func changeProvider(_ value: MusicProvider) async {
        bootstrapGeneration += 1
        cancelPlaylistSync()
        qqRenewalTask?.cancel()
        qqRenewalTask = nil
        provider = value
        sessionRevision = UUID()
        pendingPlatformLikes = [:]
        profileBinding = nil
        profile = nil
        likedTrackIDs = []; userPlaylists = []; likedAlbums = []; likedArtists = []
        libraryRefresh.invalidate(); sublistsRefresh.invalidate()
        SidebarResources.resetAccount()
        PlayerService.shared.activateAccount(scope: offlineScope)
        DownloadManager.shared.activate(accountScope: offlineScope)
        await bootstrap()
    }

    /// Called at launch and after login succeeds.
    func bootstrap() async {
        observeLibraryNetwork()
        if provider != .netease { await bootstrapPlatform(); return }
        bootstrapGeneration += 1
        let generation = bootstrapGeneration
        defer { if generation == bootstrapGeneration { isBootstrapped = true } }
        guard hasAuthCookie else { applyProfile(nil, binding: nil); return }
        if profileBinding != NeteaseClient.shared.authenticationFingerprint { applyProfile(nil, binding: nil) }
        await refreshCookieIfNeeded()
        guard generation == bootstrapGeneration, let binding = NeteaseClient.shared.authenticationFingerprint else { return }
        if profileBinding != binding { applyProfile(nil, binding: nil) }
        do {
            let fetched = try await NeteaseAPI.userAccount()
            guard generation == bootstrapGeneration, binding == NeteaseClient.shared.authenticationFingerprint else { return }
            applyProfile(fetched, binding: binding)
            saveSnapshot()
        } catch {
            return
        }
        try? MusicAccountManager.shared.rememberCurrent()
        await refreshLibrary()
    }

    func refreshLibrary(force: Bool = true) async {
        if provider != .netease { await refreshPlatformLibrary(force: force); return }
        guard let uid = authenticatedAccountID else { return }
        let authentication = NeteaseClient.shared.authenticationFingerprint
        let mutation = mutationRevision
        guard let ticket = libraryRefresh.begin(key: "\(uid):\(authentication ?? "")", lifetime: 300, force: force) else { return }
        var success = false
        defer { libraryRefresh.finish(ticket, success: success) }
        async let playlists = try? NeteaseAPI.userPlaylists(uid: uid)
        async let liked = try? NeteaseAPI.likedTrackIDs(uid: uid)
        let (fetchedPlaylists, fetchedLiked) = await (playlists, liked)
        guard libraryRefresh.accepts(ticket), mutation == mutationRevision, authenticatedAccountID == uid,
              authentication == NeteaseClient.shared.authenticationFingerprint else { return }
        userPlaylists = fetchedPlaylists ?? userPlaylists
        if let ids = fetchedLiked, pendingLikes == 0 { likedTrackIDs = Set(ids) }
        success = fetchedPlaylists != nil && fetchedLiked != nil && pendingLikes == 0
        saveSnapshot()
        syncPlaylistContents()
    }

    private func observeLibraryNetwork() {
        guard networkObserver == nil else { return }
        networkObserver = DownloadManager.shared.$network.map(\.connected).removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                if connected { Task { await self.refreshLibrary() } }
                else { self.cancelPlaylistSync() }
            }
    }

    private func cancelPlaylistSync() {
        playlistSyncID = UUID()
        playlistSyncTask?.cancel()
        playlistSyncTask = nil
    }

    private func syncPlaylistContents() {
        guard playlistSyncTask == nil, let scope = offlineScope, profile != nil else { return }
        let ticket = UUID()
        playlistSyncID = ticket
        let playlists = userPlaylists.sorted { $0.isLikedSongsList && !$1.isLikedSongsList }
        playlistSyncTask = Task(priority: .utility) { [weak self] in
            defer { if self?.playlistSyncID == ticket { self?.playlistSyncTask = nil } }
            for playlist in playlists {
                guard !Task.isCancelled, self?.offlineScope == scope else { return }
                let network = DownloadManager.shared.network
                guard !network.isKnown || network.connected else { return }
                let model = PlaylistContent(playlistID: playlist.id)
                await model.load(summary: playlist, background: true)
            }
        }
    }

    func refreshSublists(force: Bool = true) async {
        guard provider.supports(.collectionAlbums) || provider.supports(.collectionArtists), isLoggedIn else {
            likedAlbums = []; likedArtists = []
            return
        }
        if provider == .netease, authenticatedAccountID == nil { return }
        let scope = offlineScope
        guard isLoggedIn, let scope,
              let ticket = sublistsRefresh.begin(key: scope, lifetime: 300, force: force) else { return }
        var success = false
        defer { sublistsRefresh.finish(ticket, success: success) }
        async let albums = Self.attempt { try await NeteaseAPI.likedAlbums() }
        async let artists = Self.attempt { try await NeteaseAPI.likedArtists() }
        let (albumResult, artistResult) = await (albums, artists)
        guard sublistsRefresh.accepts(ticket), scope == offlineScope else { return }
        let fetchedAlbums = try? albumResult.get(), fetchedArtists = try? artistResult.get()
        success = fetchedAlbums != nil && fetchedArtists != nil
        // An expired login says so; other failures keep the generic retry hint.
        let errors: [Error?] = [albumResult.failure, artistResult.failure]
        let expired = errors.contains { $0 is QQMusicSessionError }
        sublistsError = success ? nil : expired ? QQMusicSessionError.expired.localizedDescription : String(localized: "收藏加载失败，请重试")
        likedAlbums = fetchedAlbums ?? likedAlbums
        likedArtists = fetchedArtists ?? likedArtists
    }

    private static func attempt<T>(_ body: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    func invalidateLibrary() {
        mutationRevision += 1
        libraryRefresh.invalidate()
        sublistsRefresh.invalidate()
        libraryRevision += 1
    }

    func insertCreatedPlaylist(_ playlist: PlaylistSummary) {
        // A library fetch started before creation must not overwrite this result.
        libraryRefresh.invalidate()
        userPlaylists = [playlist] + userPlaylists.filter { $0.id != playlist.id }
    }

    func renameCreatedPlaylist(id: Int, name: String) {
        invalidateLibrary()
        if let index = userPlaylists.firstIndex(where: { $0.id == id }) { userPlaylists[index].name = name }
    }

    func removeCreatedPlaylist(id: Int) {
        invalidateLibrary()
        userPlaylists.removeAll { $0.id == id }
    }

    func isLiked(_ trackID: Int) -> Bool {
        likedTrackIDs.contains(trackID)
    }

    func toggleLike(trackID: Int) async {
        guard provider.supportsFavoriteChanges else { return }
        guard isLoggedIn else {
            ToastCenter.shared.show(String(localized: "登录后即可收藏歌曲"))
            return
        }
        let serialize = provider == .qishui || provider == .qq
        let session = sessionRevision
        if serialize {
            guard pendingPlatformLikes[trackID] == nil else { return }
            pendingPlatformLikes[trackID] = session
        }
        mutationRevision += 1
        pendingLikes += 1
        defer {
            if serialize, pendingPlatformLikes[trackID] == session { pendingPlatformLikes[trackID] = nil }
            pendingLikes -= 1
            mutationRevision += 1
            libraryRefresh.invalidate()
        }
        libraryRefresh.invalidate()
        let like = !likedTrackIDs.contains(trackID)
        let scope = offlineScope
        // Optimistic update
        if like { likedTrackIDs.insert(trackID) } else { likedTrackIDs.remove(trackID) }
        do {
            try await NeteaseAPI.likeTrack(id: trackID, like: like)
        } catch {
            guard session == sessionRevision, scope == offlineScope else { return }
            if like { likedTrackIDs.remove(trackID) } else { likedTrackIDs.insert(trackID) }
            ToastCenter.shared.show(error.localizedDescription)
        }
        guard session == sessionRevision, scope == offlineScope else { return }
        saveSnapshot()
        libraryRevision += 1
        NowPlayingManager.shared.refreshLikeState()
    }

    /// Revoke by default. A login another device still offers is kept alive
    /// for it; sync still withdraws this device's record after sign-out.
    func logout() async throws {
        try MusicAccountManager.shared.forgetCurrent()
        PlayerService.shared.resetForMusicAccountChange()
        if provider != .netease {
            if provider == .qishui { try QishuiMusicAPI.shared.logout() }
            else if provider == .qq { QQMusicAuth.shared.logout() } else { KugouMusicAuth.shared.logout() }
            MusicProviderContext.shared.activate(provider)
            await changeProvider(provider)
            return
        }
        let cookies = NeteaseClient.shared.authenticationCookies()
        let revokeSession = SyncService.shared.shouldRevokeLoginSession(accountID: authenticatedAccountID)
        try NeteaseClient.shared.clearAuthCookies()
        bootstrapGeneration += 1
        AccountSnapshotStorage.shared.clear()
        applyProfile(nil, binding: nil)
        if revokeSession { try await NeteaseAPI.logout(detachedCookies: cookies) }
    }

    /// Verify a received session in isolation. A failed or superseded import must
    /// leave the current device's cookies, profile and library intact.
    func importLogin(accountID: Int, cookies: [String: String], authorization: () -> Bool) async throws {
        guard accountID > 0, cookies["MUSIC_U"]?.isEmpty == false else { throw SyncError.invalidRecord }
        guard authorization() else { throw CancellationError() }
        let generation = bootstrapGeneration
        let binding = NeteaseClient.shared.authenticationFingerprint
        let candidate = NeteaseClient(configuration: .ephemeral, persistsCookies: false)
        candidate.setCookies(cookies)
        guard let verified = try await NeteaseAPI.userAccount(using: candidate),
              verified.userId == accountID else { throw NeteaseAPIError.needLogin }
        guard authorization(), generation == bootstrapGeneration,
              binding == NeteaseClient.shared.authenticationFingerprint else { throw CancellationError() }
        try NeteaseClient.shared.replaceAuthentication(with: candidate.authenticationCookies())
        bootstrapGeneration += 1
        PlayerService.shared.suspendForAccountChange()
        UserDefaults.standard.removeObject(forKey: "auth.lastCookieRefresh")
        applyProfile(verified, binding: NeteaseClient.shared.authenticationFingerprint)
        saveSnapshot()
    }

    private func bootstrapPlatform() async {
        bootstrapGeneration += 1
        let generation = bootstrapGeneration
        defer { if generation == bootstrapGeneration { isBootstrapped = true } }
        guard hasAuthCookie else { applyProfile(nil, binding: nil); return }
        if provider == .qq {
            await QQMusicAuth.shared.refreshCredentialIfNeeded()
            guard generation == bootstrapGeneration, provider == .qq, hasAuthCookie else { return }
            scheduleQQCredentialRenewal()
        }
        guard let cached = platformProfile(), generation == bootstrapGeneration else { return }
        applyProfile(cached, binding: currentAuthenticationFingerprint)
        try? MusicAccountManager.shared.rememberCurrent()
        if provider == .qq || provider == .qishui {
            // 先用缓存资料显示，再向平台拉取真实昵称和头像
            let active = provider
            if active == .qq { await QQMusicAuth.shared.fetchProfile() } else { await QishuiMusicAPI.shared.refreshProfile() }
            guard generation == bootstrapGeneration, provider == active, hasAuthCookie else { return }
            if let refreshed = platformProfile(), refreshed != cached {
                applyProfile(refreshed, binding: currentAuthenticationFingerprint)
                try? MusicAccountManager.shared.rememberCurrent()
            }
        }
        await refreshPlatformLibrary(force: true)
        if generation == bootstrapGeneration, provider.supports(.collectionArtists) { await refreshSublists(force: true) }
    }

    /// Keeps the active QQ login alive: renews musickey ahead of expiry while the app runs.
    /// The sleep uses the continuous clock, so a check overdue after system sleep or app
    /// suspension fires as soon as the app runs again.
    private func scheduleQQCredentialRenewal() {
        qqRenewalTask?.cancel()
        qqRenewalTask = Task { [weak self] in
            let auth = QQMusicAuth.shared
            while !Task.isCancelled, let delay = auth.nextRenewalCheckDelay() {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, self.provider == .qq, auth.isLoggedIn else { return }
                if await auth.refreshCredentialIfNeeded(), self.provider == .qq {
                    try? MusicAccountManager.shared.rememberCurrent()
                }
            }
        }
    }

    private func platformProfile() -> UserProfile? {
        let userID = provider == .qishui ? QishuiMusicAPI.shared.userID : provider == .qq ? QQMusicAuth.shared.uin : KugouMusicAuth.shared.userId
        let nickname = provider == .qishui ? QishuiMusicAPI.shared.nickname : provider == .qq ? QQMusicAuth.shared.nickname : KugouMusicAuth.shared.nickname
        let vip = provider == .kugou ? KugouMusicAuth.shared.vipType : 0
        let avatar = provider == .qishui ? QishuiMusicAPI.shared.credentials["avatar"] : provider == .kugou ? KugouMusicAuth.shared.avatarURL?.absoluteString : QQMusicAuth.shared.exportedCredentials["logo"]
        let id = PlatformMusicAPI.identifier(provider: provider, kind: "account", value: userID)
        var object: [String: Any] = ["userId": id, "nickname": nickname.isEmpty ? "\(provider.name)用户 \(userID)" : nickname, "vipType": vip]
        object["avatarUrl"] = avatar
        return try? PlatformMusicAPI.decode(UserProfile.self, object)
    }

    private func refreshPlatformLibrary(force: Bool) async {
        guard isLoggedIn else { return }
        let mutation = mutationRevision
        let ticket = MusicProviderContext.shared.ticket
        guard let refresh = libraryRefresh.begin(key: "\(ticket)", lifetime: 300, force: force) else { return }
        var success = false
        defer { libraryRefresh.finish(refresh, success: success) }
        do {
            let playlists = try await PlatformMusicAPI.shared.userPlaylists()
            try MusicProviderContext.shared.check(ticket)
            guard libraryRefresh.accepts(refresh) else { return }
            userPlaylists = playlists
            if provider == .qq {
                let favorites = try await PlatformMusicAPI.shared.favorites()
                try MusicProviderContext.shared.check(ticket)
                guard libraryRefresh.accepts(refresh), mutation == mutationRevision, pendingPlatformLikes.isEmpty else { return }
                likedTrackIDs = Set(favorites.map(\.id))
            } else if let liked = playlists.first(where: \.isLikedSongsList) {
                let favorites = try await PlatformMusicAPI.shared.playlistDetail(id: liked.id).playlist.tracks
                try MusicProviderContext.shared.check(ticket)
                guard libraryRefresh.accepts(refresh), mutation == mutationRevision,
                      provider != .qishui || pendingPlatformLikes.isEmpty else { return }
                likedTrackIDs = Set(favorites.map(\.id))
            } else if provider == .qishui {
                guard mutation == mutationRevision, pendingPlatformLikes.isEmpty else { return }
                likedTrackIDs = []
            }
            if provider == .qishui || provider == .qq { NowPlayingManager.shared.refreshLikeState() }
            success = true
            sublistsError = nil
            libraryRevision += 1
        } catch is CancellationError { return }
        catch { sublistsError = error.localizedDescription }
    }

    private func applyProfile(_ value: UserProfile?, binding: String?) {
        let oldID = profile?.userId
        profile = value
        profileBinding = binding
        if oldID != value?.userId {
            libraryRefresh.invalidate(); sublistsRefresh.invalidate()
            SidebarResources.resetAccount()
            sublistsError = nil
            libraryRevision += 1
            cancelPlaylistSync()
            likedTrackIDs = []
            userPlaylists = []
            likedAlbums = []
            likedArtists = []
            PlayerService.shared.activateAccount(scope: offlineScope)
        }
        DownloadManager.shared.activate(accountScope: offlineScope)
    }

    private func saveSnapshot() {
        guard provider == .netease else { return }
        guard let profile, let binding = profileBinding, binding == NeteaseClient.shared.authenticationFingerprint else { return }
        try? AccountSnapshotStorage.shared.save(.init(authenticationFingerprint: binding, profile: profile,
                                                      likedTrackIDs: likedTrackIDs, playlists: userPlaylists, savedAt: Date()))
    }

    /// Refresh the login cookie at most once per calendar day.
    private func refreshCookieIfNeeded() async {
        let key = "auth.lastCookieRefresh"
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: key) < today else { return }
        UserDefaults.standard.set(today, forKey: key)
        await NeteaseAPI.refreshLogin()
    }
}

// MARK: - Toasts

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published var current: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String) {
        current = Toast(message: message)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            current = nil
        }
    }
}

private extension Result {
    var failure: Failure? { if case .failure(let error) = self { return error } else { return nil } }
}
