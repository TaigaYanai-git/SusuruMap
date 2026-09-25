import Foundation
import Observation

/// アプリ全体で使うサービスの入れ物。
/// レビューは iCloud（CloudKit）の公開データベースに保存し、全ユーザーで共有する。
@Observable
final class AppServices {
    let reviews: any ReviewService
    let backendDescription: String
    let isSharedBackend: Bool

    init(reviews: any ReviewService, backendDescription: String, isSharedBackend: Bool) {
        self.reviews = reviews
        self.backendDescription = backendDescription
        self.isSharedBackend = isSharedBackend
    }

    static func make() -> AppServices {
        AppServices(
            reviews: CloudKitReviewService(),
            backendDescription: "iCloud（全ユーザーで共有）",
            isSharedBackend: true
        )
    }
}
