import Foundation
import Observation

/// 店舗データの読み込み。
/// 優先順: GitHub 上の最新 shops.json → 端末キャッシュ / アプリ同梱のうち新しい方
@MainActor
@Observable
final class ShopStore {
    private(set) var shops: [Shop] = []
    private(set) var dataVersion = "-"
    private(set) var source = "-"
    private(set) var isLoading = false
    private(set) var lastError: String?
    private var index: [String: Shop] = [:]

    func shop(id: String) -> Shop? { index[id] }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        if shops.isEmpty {
            // 数千件の JSON を読むと一瞬固まるので、画面を動かす処理（メインスレッド）とは別の場所で読む
            let (cached, bundled) = await Task.detached(priority: .userInitiated) {
                (Self.readCatalog(at: Self.cacheURL),
                 Bundle.main.url(forResource: "shops", withExtension: "json").flatMap(Self.readCatalog(at:)))
            }.value
            if let cached, (cached.generatedAt ?? "") > (bundled?.generatedAt ?? "") {
                apply(cached, source: "前回ダウンロード分")
            } else if let bundled {
                apply(bundled, source: "アプリ同梱")
            }
        }

        guard let remote = AppConfig.shopsDataURL else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: remote)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let catalog = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(ShopCatalog.self, from: data)
            }.value
            try? data.write(to: Self.cacheURL, options: .atomic)
            apply(catalog, source: "GitHub（最新）")
            lastError = nil
        } catch {
            lastError = "店舗データを更新できませんでした（\(error.localizedDescription)）"
        }
    }

    private func apply(_ catalog: ShopCatalog, source: String) {
        shops = catalog.shops
        index = Dictionary(catalog.shops.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        dataVersion = catalog.version
        self.source = source
    }

    nonisolated private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shops.json")
    }

    nonisolated private static func readCatalog(at url: URL) -> ShopCatalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ShopCatalog.self, from: data)
    }
}
