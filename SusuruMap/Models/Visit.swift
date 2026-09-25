import Foundation
import SwiftData

/// 自分の訪問記録（1店舗に複数回OK）。
/// CloudKit 同期の制約に合わせ、全プロパティにデフォルト値を持たせ unique 制約は使わない。
@Model
final class Visit {
    var shopId: String = ""
    var shopName: String = ""
    var visitedAt: Date = Date()
    var memo: String = ""
    var createdAt: Date = Date()

    init(shopId: String, shopName: String, visitedAt: Date, memo: String = "") {
        self.shopId = shopId
        self.shopName = shopName
        self.visitedAt = visitedAt
        self.memo = memo
        self.createdAt = Date()
    }
}
