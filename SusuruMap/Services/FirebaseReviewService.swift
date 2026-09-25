import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// Firestore + Cloud Storage でレビューを全ユーザーと共有する。
///
/// Firestore:  shops/{shopId}/reviews/{reviewId}
///             reports/{reportId}
/// Storage:    reviews/{uid}/{reviewId}.jpg
///
/// 認証は匿名ログイン（アプリを入れた端末ごとに1ユーザー）。
/// セキュリティルールは firebase/ 以下を参照。
final class FirebaseReviewService: ReviewService {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    func currentUserID() async throws -> String {
        if let user = Auth.auth().currentUser { return user.uid }
        return try await Auth.auth().signInAnonymously().user.uid
    }

    private func reviewsRef(_ shopId: String) -> CollectionReference {
        db.collection("shops").document(shopId).collection("reviews")
    }

    func reviews(for shopId: String) async throws -> [Review] {
        let snapshot = try await reviewsRef(shopId)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            let d = doc.data()
            guard let userId = d["userId"] as? String,
                  let rating = d["rating"] as? Int else { return nil }
            return Review(
                id: doc.documentID,
                shopId: shopId,
                userId: userId,
                displayName: d["displayName"] as? String ?? "名無し",
                rating: rating,
                comment: d["comment"] as? String ?? "",
                photoURL: (d["photoURL"] as? String).flatMap(URL.init(string:)),
                visitedAt: (d["visitedAt"] as? Timestamp)?.dateValue(),
                createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            )
        }
    }

    func post(_ draft: ReviewDraft) async throws {
        let uid = try await currentUserID()
        let doc = reviewsRef(draft.shopId).document()

        var fields: [String: Any] = [
            "userId": uid,
            "displayName": draft.displayName,
            "rating": draft.rating,
            "comment": draft.comment,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if let visitedAt = draft.visitedAt {
            fields["visitedAt"] = Timestamp(date: visitedAt)
        }
        if let data = draft.imageData {
            let path = "reviews/\(uid)/\(doc.documentID).jpg"
            let ref = storage.reference().child(path)
            let meta = StorageMetadata()
            meta.contentType = "image/jpeg"
            _ = try await ref.putDataAsync(data, metadata: meta)
            fields["photoURL"] = try await ref.downloadURL().absoluteString
            fields["photoPath"] = path
        }
        try await doc.setData(fields)
    }

    func delete(_ review: Review) async throws {
        let doc = reviewsRef(review.shopId).document(review.id)
        let snapshot = try await doc.getDocument()
        if let path = snapshot.data()?["photoPath"] as? String {
            try? await storage.reference().child(path).delete()
        }
        try await doc.delete()
    }

    func report(_ review: Review, reason: String) async throws {
        let uid = try await currentUserID()
        try await db.collection("reports").document().setData([
            "shopId": review.shopId,
            "reviewId": review.id,
            "reviewUserId": review.userId,
            "reporterId": uid,
            "reason": reason,
            "createdAt": FieldValue.serverTimestamp(),
        ])
    }
}
