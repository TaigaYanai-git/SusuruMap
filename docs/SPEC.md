# すするマップ 仕様書

| 項目 | 内容 |
|---|---|
| 対象バージョン | 0.1.0 |
| 対応 OS | iOS 17.0 以上（iPhone） |
| 技術 | SwiftUI / MapKit / SwiftData / EventKit / Firebase (Auth, Firestore, Storage) |

> 仕様を変えるときは、このファイルと `CHANGELOG.md` を同じ PR で更新する。

## 1. 目的

YouTuber「SUSURU TV.」が動画で訪れたラーメン店を地図で探し、動画を見返し、自分の訪問を記録し、
友達や他のユーザーと感想を共有できるようにする。非公式のファンメイドアプリ。

## 2. 機能一覧

| ID | 機能 | 概要 |
|---|---|---|
| F-01 | 店舗マップ | すするTVが訪れた店をピン表示。未訪問はオレンジ（🍴）、行った店は緑（✓） |
| F-02 | 動画リンク | 店をタップ → 詳細シート → 動画をタップで YouTube を開く（アプリがあればアプリで）。動画IDが不明な店は「SUSURU TV. 店名」の検索結果を開く |
| F-03 | 絞り込み・検索 | すべて / 未訪問 / 行った の切替。店名・住所・都道府県で検索し、確定で最初の結果へ移動 |
| F-04 | 訪問チェック | 「行った！」で訪問日（今日以前）とメモを記録。複数回記録可、スワイプで削除 |
| F-05 | 訪問の同期 | SwiftData + CloudKit で自分の端末間を同期（iCloud 設定済みビルドのみ）。任意で iPhone のカレンダーに終日予定「🍜 店名」を追加 |
| F-06 | 制覇率 | 行った店の数 / 全店舗数、通算訪問回数、訪問履歴 |
| F-07 | レビュー投稿 | ★1〜5、コメント（1000字以内）、写真1枚、ニックネーム（30字以内）。訪問記録があれば訪問日を添付 |
| F-08 | レビュー共有 | 店ごとに新しい順で最大100件表示。平均評価を表示。自分の投稿は削除可（編集は不可） |
| F-09 | 安全対策 | 他人のレビューを通報（理由選択）・投稿者を非表示。写真は縮小時に EXIF（位置情報）を除去 |
| F-10 | 店舗データ更新 | GitHub 上の `shops.json` を起動時に取得してキャッシュ。取得できなければ前回分かアプリ同梱分 |

## 3. 画面構成

```
TabView
├─ マップ (MapScreen)
│   └─ 店舗詳細シート (ShopDetailView)
│       ├─ 動画一覧 → YouTube
│       ├─ 訪問記録 → 「行った！」シート (VisitEditor) → 「レビューも書きますか？」
│       └─ みんなのレビュー → レビュー投稿シート (ReviewComposer)
├─ 行った店 (VisitLogView) → 店舗詳細
└─ 設定 (SettingsView)
```

## 4. データ

### 4.1 店舗データ `SusuruMap/Resources/shops.json`

```jsonc
{
  "version": "2026.09.25",            // 生成日
  "generatedAt": "2026-09-25T00:00:00Z",
  "shops": [{
    "id": "s_1a2b3c4d5e",             // 店名+座標のハッシュ。overrides で固定可
    "name": "店名",
    "address": "東京都…",
    "prefecture": "東京都",
    "latitude": 35.0, "longitude": 139.0,
    "videos": [{ "videoId": "xxxxxxxxxxx", "title": "…", "publishedAt": "ISO8601" }]
  }]
}
```

生成手順（`tools/fetch_susuru_shops.py`）:
1. YouTube Data API v3 で `@SUSURUTV` のアップロード動画を全件取得
2. 概要欄の「店名：」「住所：」、郵便番号行、都道府県から始まる文字列を抽出。店名がなければタイトルから推定
3. 国土地理院ジオコーダで緯度経度を取得（結果は `data/geocode_cache.json` にキャッシュ）
4. `data/overrides.json` の手動修正を適用し、同じ店の動画をまとめる
5. 推定に自信がないものは `data/unresolved.csv` に出力 → 人が確認して overrides を直す

### 4.2 訪問記録（端末 / iCloud）

SwiftData `Visit`：`shopId`, `shopName`, `visitedAt`, `memo`, `createdAt`

### 4.3 レビュー（Firebase）

| 場所 | フィールド |
|---|---|
| Firestore `shops/{shopId}/reviews/{reviewId}` | `userId`, `displayName`, `rating`(int 1-5), `comment`, `visitedAt?`, `photoURL?`, `photoPath?`, `createdAt`(server) |
| Firestore `reports/{reportId}` | `shopId`, `reviewId`, `reviewUserId`, `reporterId`, `reason`, `createdAt` |
| Storage `reviews/{uid}/{reviewId}.jpg` | 長辺1600px, JPEG 品質0.7, 5MB 未満 |

- 認証：Firebase 匿名ログイン（端末ごとに1ユーザー）
- 権限：`firebase/firestore.rules`, `firebase/storage.rules`（読み取りは誰でも、作成・削除は本人のみ、更新不可）
- `GoogleService-Info.plist` がないビルドでは、レビューは端末内（`Documents/local_reviews.json`）に保存

## 5. 設定値（`Config/*.xcconfig`）

| キー | 用途 |
|---|---|
| `DEVELOPMENT_TEAM` / `BUNDLE_ID_PREFIX` | 各自の署名設定（`Local.xcconfig`、Git 管理外） |
| `SHOPS_DATA_URL` | GitHub の raw `shops.json` URL。空なら同梱データのみ |
| `REPO_URL` | 設定画面に出すリポジトリ URL |
| `ICLOUD_CONTAINER` | iCloud 同期用コンテナ ID |

## 6. 既知の制約 / 今後の候補

- 店舗数が数千になるとピンが多すぎる → クラスタリング（MKMapView ラップ）を検討
- 匿名ログインのため、アプリを消すと自分のレビューを削除できなくなる → Sign in with Apple
- 通報は Firestore に記録されるだけ → 一定数で自動非表示にする Cloud Functions
- 店舗データの抽出精度は概要欄の書式次第 → `unresolved.csv` を定期的に確認
- 閉店・移転情報の表示
- 友達同士のグループ（友達のレビューだけ表示、行った店の比較）
