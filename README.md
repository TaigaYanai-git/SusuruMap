# 🍜 すするマップ

YouTuber **SUSURU TV.** が訪れたラーメン店を地図で探せる iOS アプリ（非公式・ファンメイド）。

- 地図上の店をタップ → その店が紹介された **すするTVの動画** へ
- **現在地・近くの店・目的地までの経路**（Apple マップ／Google マップでナビ）
- **「行った！」チェック**（訪問日つき・iCloud 同期・カレンダー登録）と制覇率
- **美味しさ★・コメント・ラーメン写真** を投稿して全ユーザーと共有（iCloud）

仕様は [`docs/SPEC.md`](docs/SPEC.md)、変更履歴は [`CHANGELOG.md`](CHANGELOG.md)、共同開発のルールは [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## しくみ（追加のサーバー代 0円）

```
【GitHub（このリポジトリ・公開）】
   ├ アプリのプログラム … 誰でも見られるが、編集できるのは招待された人だけ
   ├ 店舗データ shops.json … 毎週 GitHub Actions が新着動画から自動更新
   │                          アプリは起動時にここから最新版を読む
   └ タグを打つと TestFlight へ自動配信

【iCloud（CloudKit）】… Apple Developer Program に含まれる
   ├ 公開データベース：みんなのレビュー・写真
   └ 非公開データベース：自分の訪問記録（自分の端末どうしで同期）
```

---

## はじめかた（開発する人・Mac）

必要なもの：Xcode 26 以上、Homebrew、Apple Developer Program のチーム
（**使うだけの友達は TestFlight で入れるだけ**でOK）

```bash
git clone https://github.com/TaigaYanai-git/SusuruMap.git
```

1. Finder で `SusuruMap` フォルダの **`Xcodeで開く.command`** をダブルクリック
   （XcodeGen の導入 → プロジェクト生成 → Xcode 起動まで自動）
2. `Config/Local.xcconfig` に自分の `DEVELOPMENT_TEAM` と `BUNDLE_ID_PREFIX` を書く
3. もう一度 `Xcodeで開く.command` → Xcode で ▶︎

ファイルを追加・削除したら、`Xcodeで開く.command` をもう一度実行します（`.xcodeproj` は `project.yml` から作るので Git に入れていません）。

## iCloud（CloudKit）の準備（オーナーが1回だけ）

1. 実機で一度アプリを動かし、レビューを1件投稿する（開発用のデータベースに型が作られる）
2. [CloudKit Console](https://icloud.developer.apple.com/) → コンテナ `iCloud.<BUNDLE_ID_PREFIX>.susurumap` を開く
3. **Schema › Indexes** で、レコード型 `Review` に次の索引を追加
   - `shopId` … **Queryable**
   - `recordName` … **Queryable**
4. （任意）**Schema › Security Roles** で `Report` の `_world` の Read を外す（通報内容を他人に見せない）
5. TestFlight に出す前に **Deploy Schema Changes…** で Production に反映

## 店舗データ（すするTVの動画 → 地図）

- **手元で作る**：Finder で `店舗データを作る.command` をダブルクリック（初回だけ YouTube の APIキーを聞かれ、Mac のキーチェーンに保存）
- **自動更新**：リポジトリの *Settings › Secrets and variables › Actions* に `YOUTUBE_API_KEY` を登録すると、毎週月曜 3:00 に新着動画を取り込んで `main` に反映します
- 抽出に自信がない動画は `data/unresolved.csv` に出ます。`data/overrides.json` で手直しできます

## TestFlight で友達に配る

`v*` タグを push すると GitHub Actions がビルドして TestFlight に上げます。

**最初に1回だけ**
1. [App Store Connect](https://appstoreconnect.apple.com/) で新規アプリを作成（Bundle ID は `<BUNDLE_ID_PREFIX>.susurumap`）
2. *ユーザとアクセス › 統合 › App Store Connect API* でキーを発行（ロール **Admin**）
3. GitHub の Secrets / Variables に登録

   | 種類 | 名前 | 値 |
   |---|---|---|
   | Secret | `APPLE_TEAM_ID` | Team ID |
   | Secret | `ASC_KEY_ID` / `ASC_ISSUER_ID` | API キーの ID / Issuer ID |
   | Secret | `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8` の結果 |
   | Variable | `BUNDLE_ID_PREFIX` | 例 `com.taigayanai` |

4. TestFlight の「外部テスト」でグループを作り、**公開リンク**を友達に送る

**リリースのたびに**
```bash
python3 scripts/bump_version.py 0.2.0
git commit -am "chore: release v0.2.0" && git tag v0.2.0 && git push origin main --tags
```

## 公開リポジトリで守っていること

| 公開されないもの | どこにあるか |
|---|---|
| Team ID・Bundle ID の個人設定 | `Config/Local.xcconfig`（Git に入れない） |
| YouTube / App Store Connect のキー | GitHub Secrets（本人も中身を見られない金庫） |
| コミットのメールアドレス | GitHub の非公開用アドレス（`…@users.noreply.github.com`） |

## ディレクトリ

```
SusuruMap/
├─ project.yml               XcodeGen の定義（バージョンもここ）
├─ Config/                   xcconfig（Local.xcconfig は各自・Git 管理外）
├─ SusuruMap/
│  ├─ App/                   起動・設定・サービスの用意
│  ├─ Models/                Shop, Visit(SwiftData), Review
│  ├─ Services/              店舗データ, レビュー(CloudKit), 現在地, 経路, ピンのまとめ表示
│  ├─ Views/                 地図, 店舗詳細, 近くの店, 訪問記録, レビュー投稿, 設定
│  └─ Resources/             shops.json, アイコン, ラーメンのピン
├─ tools/                    店舗データ生成・検証スクリプト
├─ data/                     手動修正・位置のキャッシュ・要確認リスト
├─ scripts/bump_version.py   バージョン更新
├─ Xcodeで開く.command        プロジェクト生成して Xcode を開く
├─ 店舗データを作る.command    店舗データを作る
└─ docs/SPEC.md              仕様書
```

## 注意

- 非公式アプリです。SUSURU TV. の名称・動画の権利は各権利者に帰属します。App Store で一般公開する場合は、事前に権利者の確認を取ってください。
- ユーザー投稿を扱うため、App Store に出す場合は利用規約・通報への対応体制・プライバシーポリシーが必要です。
