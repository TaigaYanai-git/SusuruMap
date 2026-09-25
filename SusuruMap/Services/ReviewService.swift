import Foundation

/// レビューの保存先。iCloud（CloudKit）版と端末内版を差し替えられるようにプロトコル化。
protocol ReviewService {
    func currentUserID() async throws -> String
    /// その店のレビュー（古い ID に付いたものも含めて）
    func reviews(for shopIDs: [String]) async throws -> [Review]
    func post(_ draft: ReviewDraft) async throws
    func delete(_ review: Review) async throws
    func report(_ review: Review, reason: String) async throws
}

/// 端末内だけのレビュー保存（通信なしで画面を試すとき用）
actor LocalReviewService: ReviewService {
    private let fileURL: URL
    private let photoDir: URL
    private let userID: String
    /// 写真は「ファイル名だけ」を photoURL に入れて保存し、読み出し時に絶対パスへ戻す
    /// （アプリ更新でコンテナのパスが変わっても壊れないように）
    private var stored: [Review]?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("local_reviews.json")
        photoDir = docs.appendingPathComponent("review_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)

        let key = "localUserID"
        if let id = UserDefaults.standard.string(forKey: key) {
            userID = id
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: key)
            userID = id
        }
    }

    func currentUserID() async throws -> String { userID }

    func reviews(for shopIDs: [String]) async throws -> [Review] {
        try all()
            .filter { shopIDs.contains($0.shopId) }
            .sorted { $0.createdAt > $1.createdAt }
            .map { review in
                review.with(photoURL: review.photoURL.map { photoDir.appendingPathComponent($0.lastPathComponent) })
            }
    }

    func post(_ draft: ReviewDraft) async throws {
        let id = UUID().uuidString
        var photoName: URL?
        if let data = draft.imageData {
            let name = "\(id).jpg"
            try data.write(to: photoDir.appendingPathComponent(name), options: .atomic)
            photoName = URL(string: name)
        }
        let review = Review(id: id, shopId: draft.shopId, userId: userID, displayName: draft.displayName,
                            rating: draft.rating, comment: draft.comment, photoURL: photoName,
                            visitedAt: draft.visitedAt, createdAt: Date())
        var list = try all()
        list.append(review)
        try save(list)
    }

    func delete(_ review: Review) async throws {
        var list = try all()
        list.removeAll { $0.id == review.id }
        try save(list)
        if let url = review.photoURL { try? FileManager.default.removeItem(at: url) }
    }

    func report(_ review: Review, reason: String) async throws {
        // ローカル版では通報先がないので何もしない
    }

    private func all() throws -> [Review] {
        if let stored { return stored }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { stored = []; return [] }
        let list = try JSONDecoder().decode([Review].self, from: Data(contentsOf: fileURL))
        stored = list
        return list
    }

    private func save(_ list: [Review]) throws {
        stored = list
        try JSONEncoder().encode(list).write(to: fileURL, options: .atomic)
    }
}
