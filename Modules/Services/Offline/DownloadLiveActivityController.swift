// Covers `Activity` (sent to its own async `update`/`end`), not Sendable in the iOS 26 SDK.
// Remove `@preconcurrency` when ActivityKit marks `Activity` Sendable.
@preconcurrency import ActivityKit
import Foundation

/// Download progress stays in the app: offline caching must not occupy the Dynamic Island.
/// Keeps the existing download-write hooks solely to dismiss activities left by older builds.
/// This controller never changes download jobs, their progress, or cached chapter files.
@MainActor
final class DownloadLiveActivityController {
    static let shared = DownloadLiveActivityController()

    private var activity: Activity<DownloadActivityAttributes>?
    private var lastPushedAt: Date = .distantPast
    private var lastPushedState: DownloadActivityAttributes.ContentState?
    private var pendingState: DownloadActivityAttributes.ContentState?
    private var flushTask: Task<Void, Never>?
    private var flushGeneration = 0
    private var isFlushWaiting = false

    /// Chapters land fast enough that pushing each one would be pure overhead; progress that
    /// catches up every 1.5 seconds still reads as continuous.
    private static let minimumUpdateInterval: TimeInterval = 1.5

    /// Narrow injectable handle: cleanup can be tested without requesting a real activity.
    struct ExistingDownloadActivity {
        let endImmediately: @MainActor () async -> Void
    }

    private let existingActivities: @MainActor () -> [ExistingDownloadActivity]

    init(existingActivities: @escaping @MainActor () -> [ExistingDownloadActivity] = {
        // Deliberately typed: TTS, reading and timer activities are not enumerated or ended.
        Activity<DownloadActivityAttributes>.activities.map { activity in
            ExistingDownloadActivity {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }) {
        self.existingActivities = existingActivities
    }

    /// Pure publication policy, independent of authorization, progress, and pause state.
    nonisolated static func shouldPublish(
        _ state: DownloadActivityAttributes.ContentState?
    ) -> Bool {
        false
    }

    /// Enumerate every time, not only a remembered first activity from this process.
    func cleanupExistingActivities() async {
        for activity in existingActivities() {
            await activity.endImmediately()
        }
    }

    /// Recomputes the activity from the shelf. Safe to call on every download write.
    ///
    /// `BookStore` is not actor-isolated, so the snapshot is built where the call happens and
    /// only the small `Sendable` result crosses to the main actor — `[ReadingBook]` never does.
    nonisolated static func refresh(books: [ReadingBook]) {
        // No payload/cover work on the progress path when publication is disabled.
        guard shouldPublish(nil) else {
            // Startup/foreground hooks end all legacy activities. Progress writes do
            // no ActivityKit enumeration, cover work, or main-queue task allocation.
            return
        }
        let active = books.filter(isActiveDownload)
        // Only checks which thumbnails already exist — cheap enough for the progress path.
        let covers = DownloadActivityCoverStore.publishedFilenames(for: active.map(\.id))
        let state = contentState(for: books, coverFilenames: covers)
        Task { @MainActor in shared.apply(state) }

        // Encoding a thumbnail is a decode plus a JPEG write, which must never run on a
        // download's progress path. Whatever this produces is picked up by the next refresh —
        // progress refreshes at least once per chapter, so the cover appears almost at once.
        let pending = active
            .filter { covers[$0.id.uuidString] == nil }
            .map { (id: $0.id, coverImagePath: $0.coverImagePath) }
        let keep = Set(active.map { "\($0.id.uuidString).jpg" })
        Task.detached(priority: .utility) {
            for book in pending {
                DownloadActivityCoverStore.publish(
                    bookId: book.id,
                    coverImagePath: book.coverImagePath
                )
            }
            DownloadActivityCoverStore.prune(keeping: keep)
        }
    }

    /// A book the activity should represent: downloading or paused, with something requested.
    nonisolated static func isActiveDownload(_ book: ReadingBook) -> Bool {
        guard book.offlineDownloadState == .downloading || book.offlineDownloadState == .paused
        else { return false }
        return (book.offlineDownloadTask?.totalChapterCount ?? 0) > 0
    }

    /// Pure: the activity payload for a shelf, or nil when nothing is downloading.
    nonisolated static func contentState(
        for books: [ReadingBook],
        coverFilenames: [String: String] = [:]
    ) -> DownloadActivityAttributes.ContentState? {
        let downloading = books
            .filter(isActiveDownload)
            .compactMap { book -> DownloadActivityAttributes.ContentState.Book? in
                guard let task = book.offlineDownloadTask else { return nil }
                return .init(
                    id: book.id.uuidString,
                    title: book.title,
                    completedChapters: task.clampedCompletedChapterCount,
                    totalChapters: task.totalChapterCount,
                    isPaused: task.isPaused,
                    coverFilename: coverFilenames[book.id.uuidString]
                )
            }
        guard !downloading.isEmpty else { return nil }

        // The presentation features one book — cover, title, progress — and folds the rest, so
        // the featured slot has to hold a book that is actually moving. Shelf order breaks the
        // tie, which keeps the choice from jumping around while progress ticks.
        let featuredFirst = downloading.enumerated()
            .sorted { lhs, rhs in
                lhs.element.isPaused == rhs.element.isPaused
                    ? lhs.offset < rhs.offset
                    : !lhs.element.isPaused
            }
            .map(\.element)
        return .init(books: featuredFirst)
    }

    /// Whether an update changes what the activity's control represents.
    ///
    /// Chapter counts can be coalesced without changing the meaning of the UI. A pause / resume
    /// transition cannot: it changes the title, progress tint, and trailing button. Likewise,
    /// adding, removing, or reordering books can replace the featured book and the `bookId` the
    /// button targets. Those updates are the final write in several flows, so they must not sit
    /// behind the progress throttle waiting for another chapter to wake the app.
    nonisolated static func requiresImmediateUpdate(
        from previous: DownloadActivityAttributes.ContentState?,
        to next: DownloadActivityAttributes.ContentState
    ) -> Bool {
        guard let previous else { return true }
        guard previous.books.map(\.id) == next.books.map(\.id) else { return true }
        return zip(previous.books, next.books).contains { pair in
            pair.0.isPaused != pair.1.isPaused
        }
    }

    func apply(_ state: DownloadActivityAttributes.ContentState?) {
        guard Self.shouldPublish(state) else {
            end()
            return
        }
        guard let state else {
            end()
            return
        }
        guard activity != nil else {
            start(with: state)
            return
        }
        schedule(state)
    }

    /// Ends the activity immediately — used when the queue drains and when the app is torn
    /// down. Leaving a stale activity on the Lock Screen is worse than none.
    func end() {
        flushGeneration &+= 1
        flushTask?.cancel()
        flushTask = nil
        isFlushWaiting = false
        pendingState = nil
        lastPushedState = nil
        lastPushedAt = .distantPast
        self.activity = nil
        Task { await cleanupExistingActivities() }
    }

    // MARK: - Private

    private func start(with state: DownloadActivityAttributes.ContentState) {
        guard Self.shouldPublish(state) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: DownloadActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil)
            )
            lastPushedAt = Date()
            lastPushedState = state
            AppLogger.cache("⟐ download Live Activity started", context: ["books": state.books.count])
        } catch {
            // Denied authorization, or too many activities. Not worth surfacing: the download
            // itself is unaffected.
            AppLogger.cache("⟐ download Live Activity could not start", error: error)
        }
    }

    /// Coalesces to at most one push per `minimumUpdateInterval`, always delivering the most
    /// recent progress state rather than the first one seen in the window. Control changes
    /// bypass the delay, and one flush remains the owner while `Activity.update` is suspended
    /// so a later state cannot race the earlier cross-process update.
    private func schedule(_ state: DownloadActivityAttributes.ContentState) {
        pendingState = state
        if Self.requiresImmediateUpdate(from: lastPushedState, to: state), isFlushWaiting {
            // The existing task is only sleeping to coalesce progress. Replace it with a
            // zero-delay flush while the app still has execution time from the user action.
            flushGeneration &+= 1
            flushTask?.cancel()
            flushTask = nil
            isFlushWaiting = false
        }
        startFlushIfNeeded()
    }

    private func startFlushIfNeeded() {
        guard flushTask == nil, pendingState != nil, activity != nil else { return }
        flushGeneration &+= 1
        let generation = flushGeneration
        flushTask = Task { [weak self] in
            await self?.flushPendingStates(generation: generation)
        }
    }

    private func flushPendingStates(generation: Int) async {
        while !Task.isCancelled, generation == flushGeneration {
            guard let next = pendingState, let activity else { break }
            let isControlUpdate = Self.requiresImmediateUpdate(
                from: lastPushedState,
                to: next
            )
            let delay: TimeInterval
            if isControlUpdate {
                delay = 0
            } else {
                let elapsed = Date().timeIntervalSince(lastPushedAt)
                delay = max(0, Self.minimumUpdateInterval - elapsed)
            }

            if delay > 0 {
                isFlushWaiting = true
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    finishFlush(generation: generation)
                    return
                }
                guard !Task.isCancelled, generation == flushGeneration else { return }
                isFlushWaiting = false
                // Re-read `pendingState`: progress or a control action may have replaced it
                // while this task was sleeping.
                continue
            }

            pendingState = nil
            lastPushedAt = Date()
            lastPushedState = next
            await activity.update(ActivityContent(state: next, staleDate: nil))
            if isControlUpdate {
                AppLogger.cache("⟐ download Live Activity control state updated", context: [
                    "books": next.books.count,
                    "paused": next.isPaused,
                ])
            }
            // Keep this task installed across the await. Calls to `schedule` only replace
            // `pendingState`, then this loop serially delivers the newest value.
        }
        finishFlush(generation: generation)
    }

    private func finishFlush(generation: Int) {
        guard generation == flushGeneration else { return }
        isFlushWaiting = false
        flushTask = nil
    }
}
