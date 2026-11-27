import SwiftUI

/// A successful response alone makes a resource fresh. Tickets prevent superseded
/// or cancelled work from committing, including changes within the same account.
@MainActor
final class PanelRefreshGate {
    struct Ticket: Equatable { let id = UUID(); let key: String }
    private var current: Ticket?
    private var successfulKey: String?
    private var fetchedAt: Date?

    func begin(key: String, lifetime: TimeInterval, force: Bool = false, now: Date = Date()) -> Ticket? {
        if !force {
            if current?.key == key { return nil }
            if successfulKey == key, let fetchedAt, now.timeIntervalSince(fetchedAt) < lifetime { return nil }
        }
        let ticket = Ticket(key: key)
        current = ticket
        return ticket
    }

    func isCurrent(_ ticket: Ticket) -> Bool { current == ticket }
    func accepts(_ ticket: Ticket) -> Bool { isCurrent(ticket) && !Task.isCancelled }
    func finish(_ ticket: Ticket, success: Bool) {
        guard current == ticket else { return }
        if success && !Task.isCancelled { successfulKey = ticket.key; fetchedAt = Date() }
        current = nil
    }
    func invalidate() { successfulKey = nil; fetchedAt = nil; current = nil }
}

extension Notification.Name {
    static let panelDataChanged = Notification.Name("Coda.panelDataChanged")
}

#if DEBUG
/// UI tests hold real initial loading states until their screenshot has been
/// captured. This gate is dormant without the explicit test launch flag and
/// releases automatically if a test disconnects; it never changes account data.
@MainActor
private enum SkeletonLayoutUITestGate {
    private static var pending: Set<String> = []
    private static var released: Set<String> = []
    private static let enabled: Bool = {
        guard ProcessInfo.processInfo.environment["CODA_UI_TEST_SKELETONS"] == "1" else { return false }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            Task { @MainActor in releasePending() }
        }, "wow.caicai.coda.ui-tests.release-skeletons" as CFString, nil, .deliverImmediately)
        return true
    }()

    private static func releasePending() { released.formUnion(pending) }

    static func waitIfRequested(key: String) async -> Bool {
        let kind = String(key.prefix { $0 != ":" })
        guard enabled, ["home", "collections", "album", "artist"].contains(kind),
              !released.contains(kind) else { return !Task.isCancelled }
        pending.insert(kind)
        let deadline = Date().addingTimeInterval(60)
        while !released.contains(kind), Date() < deadline {
            do { try await Task.sleep(nanoseconds: 50_000_000) }
            catch { return false }
        }
        return !Task.isCancelled
    }
}
#endif

/// Runs only while the page is mounted and active. Every resource decides its
/// own expiry; foreground/network transitions merely ask it to check freshness.
private struct PanelRefreshModifier: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @EnvironmentObject private var account: AccountStore
    @ObservedObject private var downloads = DownloadManager.shared
    @State private var revision = 0
    @State private var inflight = Inflight()
    let key: String

    /// Models skip a request while an identical one is in flight. A context change
    /// cancels that request, so the next pass must wait for it to unwind; otherwise
    /// the new pass is skipped and the cancelled one discards its results.
    @MainActor private final class Inflight {
        var task: Task<Void, Never>?
    }

    private func run() async {
        if let previous = inflight.task { await previous.value }
        guard !Task.isCancelled else { return }
        let work = Task { await action(false) }
        inflight.task = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }
    let action: (Bool) async -> Void

    private var context: String {
        "\(key):\(account.offlineScope ?? "pending"):\(phase):\(downloads.network.connected):\(revision)"
    }

    func body(content: Content) -> some View {
        content
            .refreshable { await action(true) }
            .onReceive(NotificationCenter.default.publisher(for: .panelDataChanged)) { _ in revision += 1 }
            .task(id: context) {
                guard phase == .active else { return }
                repeat {
                    #if DEBUG
                    guard await SkeletonLayoutUITestGate.waitIfRequested(key: key) else { return }
                    #endif
                    await run()
                    guard !Task.isCancelled else { return }
                    guard !downloads.network.isKnown || downloads.network.connected else { return }
                    do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                    catch { return }
                } while !Task.isCancelled
            }
    }
}

extension View {
    func panelRefresh(key: String, action: @escaping (Bool) async -> Void) -> some View {
        modifier(PanelRefreshModifier(key: key, action: action))
    }
}

@MainActor
final class PanelResource<Value>: ObservableObject {
    @Published private(set) var value: Value
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let empty: Value
    private var scope: String?
    private let gate = PanelRefreshGate()

    init(_ empty: Value) { self.empty = empty; value = empty }

    func invalidate() { gate.invalidate() }
    func reset() {
        gate.invalidate(); value = empty; error = nil; isLoading = false; scope = nil
    }

    func load(lifetime: TimeInterval, key: String = "", force: Bool = false,
              fetch: () async throws -> Value) async {
        let authentication = MusicProviderContext.shared.authenticationKey
        let accountScope = AccountStore.shared.offlineScope
        let identity = "\(accountScope ?? "pending"):\(authentication ?? "guest")"
        if scope != identity {
            gate.invalidate(); value = empty; error = nil; scope = identity
        }
        guard let ticket = gate.begin(key: identity + key, lifetime: lifetime, force: force) else { return }
        isLoading = true
        var succeeded = false
        defer {
            if gate.isCurrent(ticket) { isLoading = false }
            gate.finish(ticket, success: succeeded)
        }
        do {
            let fresh = try await fetch()
            guard gate.accepts(ticket), authentication == MusicProviderContext.shared.authenticationKey,
                  accountScope == AccountStore.shared.offlineScope else { return }
            value = fresh; error = nil; succeeded = true
        } catch {
            guard gate.accepts(ticket), authentication == MusicProviderContext.shared.authenticationKey else { return }
            self.error = error.localizedDescription
        }
    }
}

@MainActor
enum SidebarResources {
    // Survives unmounting the account page, unlike its local notification state.
    static private(set) var playbackRevision = UUID()
    static let recents = PanelResource<[RecentSongPlayRecord]>([])
    static let cloud = PanelResource<NeteaseAPI.CloudResponse?>(nil)
    static let daily = PanelResource<[Track]>([])

    static func resetAccount() { recents.reset(); cloud.reset(); daily.reset() }

    static func libraryChanged() {
        AccountStore.shared.invalidateLibrary()
        NotificationCenter.default.post(name: .panelDataChanged, object: nil)
    }

    static func playbackChanged() {
        playbackRevision = UUID()
        recents.invalidate()
        NotificationCenter.default.post(name: .panelDataChanged, object: nil)
    }

    static func dailyPeriod(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let shifted = now.addingTimeInterval(-6 * 3600)
        return String(calendar.startOfDay(for: shifted).timeIntervalSince1970)
    }
}

/// Keep stale content usable while making a failed background refresh visible.
struct PanelRefreshFailure: View {
    let message: String?
    let retry: () -> Void
    var body: some View {
        if let message {
            HStack(spacing: 12) {
                Label(message, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.caption)
                    .lineLimit(2)
                Spacer()
                Button("重试", action: retry)
            }
            .padding(12)
            .background(.regularMaterial)
        }
    }
}
