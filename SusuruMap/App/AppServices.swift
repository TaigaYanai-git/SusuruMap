import Foundation
import Observation
import FirebaseCore

/// アプリ全体で使うサービスの入れ物。
/// GoogleService-Info.plist があれば Firebase（全ユーザー共有）、なければローカル保存で動く。
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
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            return AppServices(
                reviews: FirebaseReviewService(),
                backendDescription: "Firebase（全ユーザーで共有）",
                isSharedBackend: true
            )
        }
        return AppServices(
            reviews: LocalReviewService(),
            backendDescription: "この端末のみ（Firebase未設定）",
            isSharedBackend: false
        )
    }
}
