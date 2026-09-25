import Foundation

/// 他のユーザーと共有されるレビュー
struct Review: Identifiable, Codable, Hashable {
    let id: String
    let shopId: String
    let userId: String
    let displayName: String
    /// 1〜5
    let rating: Int
    let comment: String
    let photoURL: URL?
    let visitedAt: Date?
    let createdAt: Date

    func with(photoURL: URL?) -> Review {
        Review(id: id, shopId: shopId, userId: userId, displayName: displayName, rating: rating,
               comment: comment, photoURL: photoURL, visitedAt: visitedAt, createdAt: createdAt)
    }
}

/// 投稿前の下書き
struct ReviewDraft {
    var shopId: String
    var displayName: String
    var rating: Int
    var comment: String
    /// 圧縮済み JPEG
    var imageData: Data?
    var visitedAt: Date?

    static let maxCommentLength = 1000
    static let maxNameLength = 30
}

extension Array where Element == Review {
    var averageRating: Double? {
        guard !isEmpty else { return nil }
        return Double(map(\.rating).reduce(0, +)) / Double(count)
    }
}

/// 非表示にしたユーザーの ID（@AppStorage に "," 区切りで保存）
enum BlockList {
    static let storageKey = "blockedUserIDs"
    static func decode(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init))
    }
    static func encode(_ ids: Set<String>) -> String {
        ids.sorted().joined(separator: ",")
    }
}
