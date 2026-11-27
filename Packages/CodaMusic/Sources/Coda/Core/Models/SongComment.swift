import Foundation

enum SongCommentSort: String, CaseIterable {
    case hot, latest
}

struct SongComment: Decodable, Identifiable, Equatable {
    struct Author: Decodable, Equatable {
        let userId: Int
        let nickname: String
        let avatarUrl: String?
    }

    struct Reply: Decodable, Equatable {
        let user: Author?
        let content: String?
    }

    let commentId: Int
    let user: Author
    let content: String
    let time: Double
    var likedCount: Int
    var liked: Bool
    let beReplied: [Reply]
    var id: Int { commentId }
    var date: Date { Date(timeIntervalSince1970: time / 1000) }

    private enum CodingKeys: String, CodingKey {
        case commentId, user, content, time, likedCount, liked, beReplied
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commentId = try c.decode(Int.self, forKey: .commentId)
        user = (try? c.decode(Author.self, forKey: .user))
            ?? Author(userId: 0, nickname: String(localized: "网易云用户"), avatarUrl: nil)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        time = try c.decodeIfPresent(Double.self, forKey: .time) ?? 0
        likedCount = try c.decodeIfPresent(Int.self, forKey: .likedCount) ?? 0
        liked = try c.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        beReplied = try c.decodeIfPresent([Reply].self, forKey: .beReplied) ?? []
    }
}

struct SongCommentsPage: Decodable {
    let comments: [SongComment]
    let hotComments: [SongComment]
    let total: Int?
    let more: Bool?
    let hasMore: Bool?

    private enum CodingKeys: String, CodingKey { case comments, hotComments, total, more, hasMore }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        comments = try c.decodeIfPresent([SongComment].self, forKey: .comments) ?? []
        hotComments = try c.decodeIfPresent([SongComment].self, forKey: .hotComments) ?? []
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        more = try c.decodeIfPresent(Bool.self, forKey: .more)
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore)
    }

    func items(for sort: SongCommentSort) -> [SongComment] {
        sort == .hot ? hotComments : comments
    }
}
