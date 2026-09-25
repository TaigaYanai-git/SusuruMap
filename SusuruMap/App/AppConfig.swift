import Foundation

/// Info.plist（= Config/*.xcconfig）から読む設定値。
enum AppConfig {
    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        // 未設定の xcconfig 変数は空文字か "$(KEY)" のまま残る
        if trimmed.isEmpty || trimmed.hasPrefix("$(") { return nil }
        return trimmed
    }

    /// GitHub 上の shops.json（raw URL）。設定するとアプリ更新なしで店舗データが最新になる。
    static var shopsDataURL: URL? { string("SHOPS_DATA_URL").flatMap(URL.init(string:)) }

    /// 設定画面に表示する GitHub リポジトリの URL。
    static var repositoryURL: URL? { string("REPO_URL").flatMap(URL.init(string:)) }

    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}
