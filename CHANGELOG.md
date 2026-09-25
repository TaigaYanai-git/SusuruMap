# Changelog

このプロジェクトの変更履歴。形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/)、
バージョンは [Semantic Versioning](https://semver.org/lang/ja/) に従います。

PR を出すときは `[Unreleased]` に1行追記してください。リリース時に `scripts/bump_version.py` がバージョン見出しを付けます。

## [Unreleased]

### Changed
- iCloud 同期（訪問記録）を既定で有効化（無料アカウントは `CODE_SIGN_ENTITLEMENTS =` で無効化）

### Added
- `店舗データを作る.command`：ダブルクリックで店舗データを生成（APIキーはキーチェーンに保存）
- 住所がない回は店名で OpenStreetMap を検索して配置

### Fixed
- 動画タイトルからの店名抽出（「をすする 店名【飯テロ】」形式に対応）

### Added (CI)
- タグ push で TestFlight に自動配信する GitHub Actions ワークフロー

## [0.1.0] - 2026-09-25

### Added
- すするTVが訪れたラーメン店を地図上にピン表示（未訪問=オレンジ / 行った=緑）
- 店をタップすると詳細シート。動画サムネイルから YouTube の該当動画を開く
- 「行った！」の記録（訪問日・メモ、1店舗に複数回可）。iCloud 同期対応、iPhone カレンダーへの登録（任意）
- 行った店一覧と制覇率
- 美味しさ（★1〜5）・コメント・写真のレビュー投稿。Firebase で全ユーザーと共有
- 他ユーザーのレビューの通報・非表示
- 店名・地域での検索、未訪問/行ったの絞り込み
- 店舗データ生成スクリプト（YouTube Data API + 国土地理院ジオコーダ）と週次自動更新ワークフロー
- GitHub Actions：iOS ビルド、店舗データ検証、タグからのリリース作成
