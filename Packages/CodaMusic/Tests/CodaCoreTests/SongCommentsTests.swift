import Foundation
import Testing
@testable import CodaCore

private func commentsPage(ids: [Int], hot: Bool = false, more: Bool = false) throws -> SongCommentsPage {
    let items: [[String: Any]] = ids.map {
        ["commentId": $0, "content": "Comment \($0)", "time": 1_700_000_000_000,
         "user": ["userId": 7, "nickname": "Listener"], "likedCount": 3]
    }
    let object: [String: Any] = ["code": 200, hot ? "hotComments" : "comments": items, "more": more]
    return try JSONDecoder().decode(SongCommentsPage.self, from: JSONSerialization.data(withJSONObject: object))
}

private final class SongCommentsProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []
        private var code = 200
        func reset(code: Int = 200) { lock.lock(); defer { lock.unlock() }; paths = []; self.code = code }
        func record(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; paths.append(path); return code }
        func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return paths }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let code = Self.state.record(request.url!.path)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                                                             httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"code\":\(code)}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Song comments", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SongCommentsTests {
    @Test func handlesMissingOptionalFieldsAndDeletedQuotedComments() throws {
        let data = Data("""
        {"comments":[{"commentId":99,"content":"A song","user":null,
         "beReplied":[{"user":null,"content":null}]}],"hasMore":false}
        """.utf8)
        let page = try JSONDecoder().decode(SongCommentsPage.self, from: data)
        let comment = try #require(page.comments.first)
        #expect(comment.id == 99 && !comment.liked && comment.likedCount == 0)
        #expect(comment.user.userId == 0)
        #expect(comment.beReplied.first?.content == nil)
        #expect(page.items(for: .hot).isEmpty)
    }

    @Test func paginatesWithoutDuplicatingOverlappingRows() async throws {
        var offsets: [Int] = []
        let first = try commentsPage(ids: [1, 2], more: true)
        let second = try commentsPage(ids: [2, 3])
        let store = SongCommentsStore(trackID: 42) { id, sort, offset, _ in
            #expect(id == 42 && sort == .latest)
            offsets.append(offset)
            return offset == 0 ? first : second
        }
        await store.select(.latest)
        await store.loadMore()
        #expect(offsets == [0, 2])
        #expect(store.comments.map(\.id) == [1, 2, 3])
        #expect(!store.hasMore && !store.isLoadingMore)
    }

    @Test func lateHotResponseCannotReplaceTheLatestTab() async throws {
        var pending: CheckedContinuation<SongCommentsPage, Error>?
        let hot = try commentsPage(ids: [1], hot: true)
        let latest = try commentsPage(ids: [2])
        let store = SongCommentsStore(trackID: 42) { _, sort, _, _ in
            if sort == .hot {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return latest
        }
        let loading = Task { await store.reload() }
        while pending == nil { await Task.yield() }
        await store.select(.latest)
        pending?.resume(returning: hot)
        await loading.value
        #expect(store.sort == .latest)
        #expect(store.comments.map(\.id) == [2])
        #expect(!store.isLoading)
    }

    @Test func failedNextPageKeepsVisibleCommentsAndAllowsRetry() async throws {
        let page = try commentsPage(ids: [1], hot: true, more: true)
        let store = SongCommentsStore(trackID: 42) { _, _, offset, _ in
            if offset > 0 { throw URLError(.notConnectedToInternet) }
            return page
        }
        await store.reload()
        await store.loadMore()
        #expect(store.comments.map(\.id) == [1])
        #expect(store.hasMore && store.loadMoreError != nil)
        #expect(store.errorMessage == nil && !store.isLoadingMore)
    }

    @Test func draftSurvivesPanelSwitchButNotAccountSwitch() async throws {
        let page = try commentsPage(ids: [1], hot: true)
        let store = SongCommentsStore(trackID: 42) { _, _, _, _ in page }
        await store.open(accountID: 7)
        store.draft = "Unsent draft"
        await store.open(accountID: 7)
        #expect(store.draft == "Unsent draft")
        await store.open(accountID: 8)
        #expect(store.draft.isEmpty && store.replyingTo == nil)
    }

    @Test func cancelledRefreshKeepsCommentsAndTheNextPageOffset() async throws {
        let first = try commentsPage(ids: [1, 2], hot: true, more: true)
        let next = try commentsPage(ids: [3], hot: true)
        var calls = 0
        var pending: CheckedContinuation<SongCommentsPage, Error>?
        var offsets: [Int] = []
        let store = SongCommentsStore(trackID: 42) { _, _, offset, _ in
            calls += 1
            offsets.append(offset)
            if calls == 2 {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return offset == 0 ? first : next
        }
        await store.reload()
        let refresh = Task { await store.reload() }
        while pending == nil { await Task.yield() }
        #expect(store.isLoading && store.comments.map(\.id) == [1, 2])
        refresh.cancel()
        pending?.resume(returning: next)
        await refresh.value
        #expect(store.comments.map(\.id) == [1, 2])
        #expect(!store.isLoading && store.hasMore)
        await store.loadMore()
        #expect(offsets == [0, 0, 2])
        #expect(store.comments.map(\.id) == [1, 2, 3])
    }

    @Test func failedRefreshPreservesRowsUntilSuccessfulReplacement() async throws {
        let first = try commentsPage(ids: [1, 2], hot: true)
        let replacement = try commentsPage(ids: [3], hot: true)
        var calls = 0
        let store = SongCommentsStore(trackID: 42) { _, _, _, _ in
            calls += 1
            if calls == 2 { throw URLError(.notConnectedToInternet) }
            return calls == 1 ? first : replacement
        }
        await store.reload()
        await store.reload()
        #expect(store.comments.map(\.id) == [1, 2])
        #expect(store.refreshError != nil && store.errorMessage == nil)
        await store.reload()
        #expect(store.comments.map(\.id) == [3])
        #expect(store.refreshError == nil && !store.isLoading)
    }

    @Test func switchingSortDoesNotKeepRowsFromThePreviousSortOnFailure() async throws {
        let first = try commentsPage(ids: [1], hot: true)
        let store = SongCommentsStore(trackID: 42) { _, sort, _, _ in
            if sort == .latest { throw URLError(.notConnectedToInternet) }
            return first
        }
        await store.reload()
        await store.select(.latest)
        #expect(store.sort == .latest && store.comments.isEmpty)
        #expect(store.errorMessage != nil && store.refreshError == nil)
    }

    @Test func dockedKeyboardAvoidanceIsLimitedToTheCommentColumn() {
        let window = CGRect(x: 0, y: 0, width: 1194, height: 834)
        let column = CGRect(x: 560, y: 90, width: 560, height: 650)
        let docked = CGRect(x: 0, y: 405, width: 1194, height: 429)
        #expect(SongCommentsKeyboardLayout.bottomInset(column: column, keyboard: docked, window: window) == 347)
        let hidden = CGRect(x: 0, y: 834, width: 1194, height: 429)
        #expect(SongCommentsKeyboardLayout.bottomInset(column: column, keyboard: hidden, window: window) == 0)
        #expect(SongCommentsKeyboardLayout.bottomInset(column: column, keyboard: .null, window: window) == 0)
    }

    @Test func floatingKeyboardAndNonOverlappingColumnsDoNotGetCompressed() {
        let window = CGRect(x: 0, y: 0, width: 1194, height: 834)
        let column = CGRect(x: 560, y: 90, width: 560, height: 650)
        let floating = CGRect(x: 600, y: 420, width: 320, height: 280)
        #expect(SongCommentsKeyboardLayout.bottomInset(column: column, keyboard: floating, window: window) == 0)
        let shortColumn = CGRect(x: 560, y: 90, width: 560, height: 250)
        let docked = CGRect(x: 0, y: 405, width: 1194, height: 429)
        #expect(SongCommentsKeyboardLayout.bottomInset(column: shortColumn, keyboard: docked, window: window) == 0)
    }

    private func client(loggedIn: Bool = true) -> NeteaseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SongCommentsProtocol.self]
        let client = NeteaseClient(configuration: config, persistsCookies: false)
        if loggedIn { client.setCookies(["MUSIC_U": "synthetic-comments-session"]) }
        return client
    }

    @Test func allOperationsUseSongSpecificEndpointsWithoutLiveRequests() async throws {
        SongCommentsProtocol.state.reset()
        let client = client()
        _ = try await NeteaseAPI.songComments(id: 42, sort: .hot, using: client)
        _ = try await NeteaseAPI.songComments(id: 42, sort: .latest, offset: 20, using: client)
        try await NeteaseAPI.likeSongComment(trackID: 42, commentID: 99, like: true, using: client)
        try await NeteaseAPI.likeSongComment(trackID: 42, commentID: 99, like: false, using: client)
        try await NeteaseAPI.sendSongComment(trackID: 42, content: "Fixture", using: client)
        try await NeteaseAPI.sendSongComment(trackID: 42, content: "Reply fixture", replyingTo: 99, using: client)
        try await NeteaseAPI.deleteSongComment(trackID: 42, commentID: 99, using: client)
        #expect(SongCommentsProtocol.state.snapshot() == [
            "/weapi/v1/resource/hotcomments/R_SO_4_42", "/weapi/v1/resource/comments/R_SO_4_42",
            "/weapi/v1/comment/like", "/weapi/v1/comment/unlike",
            "/eapi/resource/comments/add", "/eapi/resource/comments/reply", "/eapi/resource/comments/delete"
        ])
    }

    @Test func guestAndEmptyDraftCannotProduceMutationRequests() async throws {
        SongCommentsProtocol.state.reset()
        let guest = client(loggedIn: false)
        await #expect(throws: NeteaseAPIError.self) {
            try await NeteaseAPI.sendSongComment(trackID: 42, content: "Fixture", using: guest)
        }
        await #expect(throws: NeteaseAPIError.self) {
            try await NeteaseAPI.likeSongComment(trackID: 42, commentID: 99, like: true, using: guest)
        }
        await #expect(throws: NeteaseAPIError.self) {
            try await NeteaseAPI.sendSongComment(trackID: 42, content: " \n ", using: client())
        }
        #expect(SongCommentsProtocol.state.snapshot().isEmpty)
    }

    @Test func serverRejectionIsReportedAsFailure() async throws {
        SongCommentsProtocol.state.reset(code: 500)
        await #expect(throws: NeteaseAPIError.self) {
            try await NeteaseAPI.sendSongComment(trackID: 42, content: "Fixture", using: client())
        }
    }
}
