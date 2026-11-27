import Foundation

extension NeteaseAPI {
    static func songComments(id: Int, sort: SongCommentSort, offset: Int = 0,
                             before: Double = 0, limit: Int = 20,
                             using client: NeteaseClient = .shared) async throws -> SongCommentsPage {
        if MusicProviderContext.shared.current != .netease {
            return try await PlatformMusicAPI.shared.comments(id: id, sort: sort, offset: offset, limit: limit)
        }
        try MusicProviderContext.shared.requireNetease()
        let resource = "R_SO_4_\(id)"
        let path = sort == .hot ? "/v1/resource/hotcomments/\(resource)" : "/v1/resource/comments/\(resource)"
        let data = try await client.weapi(path, ["rid": id, "offset": offset,
                                                "limit": limit, "beforeTime": before])
        return try client.decoded(SongCommentsPage.self, from: data)
    }

    static func likeSongComment(trackID: Int, commentID: Int, like: Bool,
                                using client: NeteaseClient = .shared) async throws {
        try MusicProviderContext.shared.requireNetease()
        guard client.isLoggedIn else { throw NeteaseAPIError.needLogin }
        let data = try await client.weapi("/v1/comment/\(like ? "like" : "unlike")",
                                         ["threadId": "R_SO_4_\(trackID)", "commentId": commentID])
        _ = try client.decoded(CodeOnly.self, from: data)
    }

    static func sendSongComment(trackID: Int, content: String, replyingTo commentID: Int? = nil,
                                using client: NeteaseClient = .shared) async throws {
        try MusicProviderContext.shared.requireNetease()
        guard client.isLoggedIn else { throw NeteaseAPIError.needLogin }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw NeteaseAPIError.business(code: -1, message: String(localized: "请输入评论内容"))
        }
        var payload: [String: Any] = ["threadId": "R_SO_4_\(trackID)", "content": text]
        if let commentID { payload["commentId"] = commentID }
        let data = try await client.eapi("/resource/comments/\(commentID == nil ? "add" : "reply")", payload)
        _ = try client.decoded(CodeOnly.self, from: data)
    }

    static func deleteSongComment(trackID: Int, commentID: Int,
                                  using client: NeteaseClient = .shared) async throws {
        try MusicProviderContext.shared.requireNetease()
        guard client.isLoggedIn else { throw NeteaseAPIError.needLogin }
        let data = try await client.eapi("/resource/comments/delete",
                                        ["threadId": "R_SO_4_\(trackID)", "commentId": commentID])
        _ = try client.decoded(CodeOnly.self, from: data)
    }
}
