import EventKit
import Foundation

/// 訪問日を iOS のカレンダーに終日予定として書き込む（書き込み専用アクセス）。
enum CalendarSync {
    enum CalendarError: LocalizedError {
        case denied, noCalendar
        var errorDescription: String? {
            switch self {
            case .denied: "カレンダーへのアクセスが許可されていません（設定アプリ > プライバシー > カレンダー）"
            case .noCalendar: "書き込み先のカレンダーが見つかりません"
            }
        }
    }

    static func addVisit(shop: Shop, date: Date, memo: String) async throws {
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else { throw CalendarError.denied }
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarError.noCalendar }

        let event = EKEvent(eventStore: store)
        event.title = "🍜 \(shop.name)"
        event.isAllDay = true
        event.startDate = date
        event.endDate = date
        event.location = shop.address
        event.notes = memo.isEmpty ? "すするマップで記録" : memo
        event.url = shop.latestVideo?.watchURL(shopName: shop.name)
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
    }
}
