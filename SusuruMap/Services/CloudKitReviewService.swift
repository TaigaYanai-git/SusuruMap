import CloudKit
import Foundation

/// レビューを iCloud（CloudKit）の「公開データベース」に保存し、全ユーザーで共有する。
/// Apple Developer Program に含まれるので追加料金はかからない。
///
/// レコードの種類
///   Review : shopId, authorID, displayName, rating, comment, visitedAt?, photo(画像)?
///   Report : shopId, reviewId, reviewAuthorID, reporterID, reason
///
/// 権限（CloudKit の標準設定）
///   だれでも読める / iCloud にサインインしている人が作れる / 作った本人だけが消せる
final class CloudKitReviewService: ReviewService {
    private let container = CKContainer.default()
    private var database: CKDatabase { container.publicCloudDatabase }

    enum ServiceError: LocalizedError {
        case notSignedIn
        var errorDescription: String? {
            "投稿するには、iPhone の設定アプリで iCloud にサインインしてください。"
        }
    }

    func currentUserID() async throws -> String {
        try await container.userRecordID().recordName
    }

    func reviews(for shopIDs: [String]) async throws -> [Review] {
        let query = CKQuery(recordType: "Review", predicate: NSPredicate(format: "shopId IN %@", shopIDs))
        let (results, _) = try await database.records(matching: query, resultsLimit: 100)
        return results
            .compactMap { try? $0.1.get() }
            .compactMap(Review.init(record:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    func post(_ draft: ReviewDraft) async throws {
        guard try await container.accountStatus() == .available else { throw ServiceError.notSignedIn }
        let authorID = try await currentUserID()

        let record = CKRecord(recordType: "Review")
        record["shopId"] = draft.shopId
        record["authorID"] = authorID
        record["displayName"] = draft.displayName
        record["rating"] = draft.rating
        record["comment"] = draft.comment
        record["visitedAt"] = draft.visitedAt

        var tempFile: URL?
        if let data = draft.imageData {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            try data.write(to: url)
            record["photo"] = CKAsset(fileURL: url)
            tempFile = url
        }
        defer { if let tempFile { try? FileManager.default.removeItem(at: tempFile) } }

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw ServiceError.notSignedIn
        }
    }

    func delete(_ review: Review) async throws {
        try await database.deleteRecord(withID: CKRecord.ID(recordName: review.id))
    }

    func report(_ review: Review, reason: String) async throws {
        let record = CKRecord(recordType: "Report")
        record["shopId"] = review.shopId
        record["reviewId"] = review.id
        record["reviewAuthorID"] = review.userId
        record["reporterID"] = (try? await currentUserID()) ?? ""
        record["reason"] = reason
        _ = try await database.save(record)
    }
}

private extension Review {
    init?(record: CKRecord) {
        guard let shopId = record["shopId"] as? String,
              let rating = record["rating"] as? Int else { return nil }
        self.init(
            id: record.recordID.recordName,
            shopId: shopId,
            userId: record["authorID"] as? String ?? "",
            displayName: record["displayName"] as? String ?? "名無し",
            rating: rating,
            comment: record["comment"] as? String ?? "",
            photoURL: (record["photo"] as? CKAsset)?.fileURL,
            visitedAt: record["visitedAt"] as? Date,
            createdAt: record.creationDate ?? Date()
        )
    }
}
