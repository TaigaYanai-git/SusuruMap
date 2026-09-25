import SwiftUI

struct SettingsView: View {
    @Environment(ShopStore.self) private var store
    @Environment(AppServices.self) private var services
    @AppStorage("displayName") private var displayName = ""
    @AppStorage("addVisitsToCalendar") private var addToCalendar = false
    @AppStorage(BlockList.storageKey) private var blockedRaw = ""
    @AppStorage(MapApp.storageKey) private var mapApp: MapApp = .inApp

    var body: some View {
        let blockedCount = BlockList.decode(blockedRaw).count

        NavigationStack {
            Form {
                Section("プロフィール") {
                    TextField("ニックネーム（レビューに表示）", text: $displayName)
                }
                Section {
                    Picker("ナビに使う地図アプリ", selection: $mapApp) {
                        ForEach(MapApp.allCases) { Text($0.rawValue).tag($0) }
                    }
                } header: {
                    Text("地図")
                } footer: {
                    Text("「すするマップ」はアプリの中で道案内します（徒歩・車）。電車の乗り換えは Apple マップで開きます。Google マップは、アプリが入っていなければブラウザで開きます。")
                }
                Section {
                    Toggle("記録時にカレンダーにも登録", isOn: $addToCalendar)
                } header: {
                    Text("訪問記録")
                } footer: {
                    Text("訪問記録は iCloud を有効にしたビルドでは、自分の iPhone / iPad 間で自動同期されます。")
                }
                Section("レビュー共有") {
                    LabeledContent("保存先", value: services.backendDescription)
                    Button("非表示にしたユーザーを元に戻す（\(blockedCount)人）") { blockedRaw = "" }
                        .disabled(blockedCount == 0)
                }
                Section("店舗データ") {
                    LabeledContent("店舗数", value: "\(store.shops.count) 店")
                    LabeledContent("データ版", value: store.dataVersion)
                    LabeledContent("取得元", value: store.source)
                    Button("最新データを取得") { Task { await store.load() } }
                        .disabled(store.isLoading)
                }
                Section {
                    LabeledContent("バージョン", value: AppConfig.appVersion)
                    if let url = AppConfig.repositoryURL {
                        Link("GitHub リポジトリ（仕様・変更履歴）", destination: url)
                    }
                } header: {
                    Text("このアプリについて")
                } footer: {
                    Text("非公式のファンメイドアプリです。SUSURU TV. および関係者とは無関係です。")
                }
            }
            .navigationTitle("設定")
        }
    }
}
