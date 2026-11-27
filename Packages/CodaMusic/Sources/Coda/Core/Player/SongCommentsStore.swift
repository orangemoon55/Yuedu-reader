import Combine
import Foundation

@MainActor
final class SongCommentsStore: ObservableObject {
    typealias Loader = @MainActor (Int, SongCommentSort, Int, Double) async throws -> SongCommentsPage

    let trackID: Int
    @Published private(set) var sort: SongCommentSort = .hot
    @Published private(set) var comments: [SongComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var refreshError: String?
    @Published private(set) var loadMoreError: String?
    @Published private(set) var busyCommentIDs: Set<Int> = []
    @Published private(set) var isSubmitting = false
    @Published var actionError: String?
    @Published var draft = ""
    @Published var replyingTo: SongComment?

    private let loader: Loader
    private var generation = UUID()
    private var offset = 0
    private var before: Double = 0
    private var hasAccountContext = false
    private var accountContext: Int?

    init(trackID: Int, loader: @escaping Loader = {
        try await NeteaseAPI.songComments(id: $0, sort: $1, offset: $2, before: $3)
    }) {
        self.trackID = trackID
        self.loader = loader
    }

    func select(_ sort: SongCommentSort) async {
        guard self.sort != sort else { return }
        self.sort = sort
        resetList()
        await reload()
    }

    func resetComposer() {
        draft = ""
        replyingTo = nil
        actionError = nil
    }

    func open(accountID: Int?) async {
        if !hasAccountContext || accountContext != accountID {
            resetComposer()
            resetList()
            accountContext = accountID
            hasAccountContext = true
        }
        await reload()
    }

    func reload() async {
        let request = UUID()
        generation = request
        errorMessage = nil
        refreshError = nil
        loadMoreError = nil
        isLoadingMore = false
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let page = try await loader(trackID, sort, 0, 0)
            guard !Task.isCancelled, generation == request else { return }
            // Replace only after success. Clearing the mounted ScrollView's
            // data first can destroy its refresh task and leave an empty list.
            resetList()
            append(page)
        } catch {
            guard !Task.isCancelled, generation == request else { return }
            if comments.isEmpty { errorMessage = error.localizedDescription }
            else { refreshError = error.localizedDescription }
        }
    }

    private func resetList() {
        comments = []
        offset = 0
        before = 0
        hasMore = false
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        let request = generation
        isLoadingMore = true
        loadMoreError = nil
        defer { if generation == request { isLoadingMore = false } }
        do {
            let page = try await loader(trackID, sort, offset, before)
            guard !Task.isCancelled, generation == request else { return }
            append(page)
        } catch {
            guard !Task.isCancelled, generation == request else { return }
            loadMoreError = error.localizedDescription
        }
    }

    private func append(_ page: SongCommentsPage) {
        let incoming = page.items(for: sort)
        var seen = Set(comments.map(\.id))
        let unique = incoming.filter { seen.insert($0.id).inserted }
        comments.append(contentsOf: unique)
        offset += incoming.count
        // Deep pagination uses the last comment's server timestamp.
        before = offset >= 5000 ? (incoming.last?.time ?? before) : 0
        hasMore = !unique.isEmpty && (page.more ?? page.hasMore ?? (incoming.count >= 20))
    }

    func toggleLike(_ comment: SongComment) async {
        guard !busyCommentIDs.contains(comment.id) else { return }
        let authentication = NeteaseClient.shared.authenticationFingerprint
        busyCommentIDs.insert(comment.id)
        defer { busyCommentIDs.remove(comment.id) }
        do {
            try await NeteaseAPI.likeSongComment(trackID: trackID, commentID: comment.id, like: !comment.liked)
            guard authentication == NeteaseClient.shared.authenticationFingerprint else { return }
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].liked = !comment.liked
                comments[index].likedCount = max(0, comment.likedCount + (comment.liked ? -1 : 1))
            }
        } catch {
            if authentication == NeteaseClient.shared.authenticationFingerprint {
                actionError = error.localizedDescription
            }
        }
    }

    @discardableResult
    func send() async -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmitting else { return false }
        let authentication = NeteaseClient.shared.authenticationFingerprint
        let replyID = replyingTo?.id
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await NeteaseAPI.sendSongComment(trackID: trackID, content: text, replyingTo: replyID)
            guard authentication == NeteaseClient.shared.authenticationFingerprint else { return false }
            draft = ""
            replyingTo = nil
            if sort != .latest {
                sort = .latest
                resetList()
            }
            await reload()
            return true
        } catch {
            if authentication == NeteaseClient.shared.authenticationFingerprint {
                actionError = error.localizedDescription
            }
            return false
        }
    }

    func delete(_ comment: SongComment) async {
        guard !busyCommentIDs.contains(comment.id) else { return }
        let authentication = NeteaseClient.shared.authenticationFingerprint
        busyCommentIDs.insert(comment.id)
        defer { busyCommentIDs.remove(comment.id) }
        do {
            try await NeteaseAPI.deleteSongComment(trackID: trackID, commentID: comment.id)
            guard authentication == NeteaseClient.shared.authenticationFingerprint else { return }
            comments.removeAll { $0.id == comment.id }
            offset = max(0, offset - 1)
            // Removing a visible row changes the next server offset.
            await reload()
        } catch {
            if authentication == NeteaseClient.shared.authenticationFingerprint {
                actionError = error.localizedDescription
            }
        }
    }
}
