import Foundation
import CoreLocation

/// shops.json のトップレベル
struct ShopCatalog: Codable {
    var version: String
    var generatedAt: String?
    var note: String?
    var shops: [Shop]
}

/// すするTVが訪れたラーメン店
struct Shop: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let address: String?
    let prefecture: String?
    let latitude: Double
    let longitude: Double
    /// この店が登場する動画（新しい順）
    let videos: [ShopVideo]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var latestVideo: ShopVideo? {
        videos.max { ($0.publishedAt ?? "") < ($1.publishedAt ?? "") }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return [name, address ?? "", prefecture ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

struct ShopVideo: Identifiable, Codable, Hashable {
    /// YouTube の動画ID。未特定のときは nil（検索結果に飛ぶ）
    let videoId: String?
    let title: String
    /// ISO8601 文字列
    let publishedAt: String?

    var id: String { videoId ?? "search:\(title)" }

    /// 動画を開く URL。YouTube アプリが入っていればアプリで開く（ユニバーサルリンク）。
    func watchURL(shopName: String) -> URL {
        if let videoId, let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") {
            return url
        }
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: "SUSURU TV. \(shopName)")]
        return c.url!
    }

    var thumbnailURL: URL? {
        guard let videoId else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
    }

    var publishedDate: Date? {
        guard let publishedAt else { return nil }
        return ISO8601DateFormatter().date(from: publishedAt)
    }
}
