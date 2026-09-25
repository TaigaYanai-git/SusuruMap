# 🍜 すするマップ

YouTuber **SUSURU TV.** が訪れたラーメン店を地図で探せる iOS アプリ（非公式・ファンメイド）。

- 地図上の店をタップ → その店が紹介された **すするTVの動画** へ
- **「行った！」チェック**（訪問日つき・iCloud 同期・カレンダー登録）と制覇率
- **美味しさ★・コメント・ラーメン写真** を投稿して他のユーザーと共有

仕様は [`docs/SPEC.md`](docs/SPEC.md)、変更履歴は [`CHANGELOG.md`](CHANGELOG.md)、共同開発のルールは [`CONTRIBUTING.md`](CONTRIBUTING.md)。

---

## はじめかた（各自の Mac で）

必要なもの：Xcode 16 以上、Homebrew、Apple ID（無料でも実機ビルド可）

```bash
git clone https://github.com/<owner>/SusuruMap.git
cd SusuruMap
make setup      # XcodeGen を入れて Config/Local.xcconfig を作成
# → Config/Local.xcconfig の DEVELOPMENT_TEAM と BUNDLE_ID_PREFIX を自分用に書き換える
make open       # Xcode プロジェクトを生成して開く → ▶︎ で実行
```

この状態で **マップ・動画リンク・訪問記録・レビュー（端末内保存）** まで動きます。
同梱の `shops.json` は動作確認用の架空データ3件なので、下の「店舗データ」で実データを作ってください。

## レビュー共有を有効にする（Firebase・無料枠で可）

リポジトリのオーナーが1回だけ行い、友達には `GoogleService-Info.plist` を個別に渡します。

1. [Firebase コンソール](https://console.firebase.google.com/) でプロジェクトを作成し、iOS アプリを追加
   （Bundle ID は各自のものを全員分追加しておくと楽）
2. **Authentication** → ログイン方法で「匿名」を有効化
3. **Firestore Database** と **Storage** を作成
4. ルールをデプロイ（このリポジトリのルールがそのまま使える）
   ```bash
   npm i -g firebase-tools && firebase login
   firebase use --add          # 作ったプロジェクトを選ぶ
   firebase deploy --only firestore:rules,storage
   ```
5. ダウンロードした `GoogleService-Info.plist` を `SusuruMap/Resources/` に置き、`make project`
   （Git には上がりません。`.gitignore` 済み）

plist がないビルドは自動的に「端末内保存モード」になるので、Firebase なしでも開発できます。

## 店舗データ（すするTVの動画 → 地図）

```bash
export YOUTUBE_API_KEY=...   # Google Cloud で YouTube Data API v3 を有効にして発行
make data                    # 全動画を取得 → 店名・住所を抽出 → 座標化 → shops.json
```

- 抽出に自信がない動画は `data/unresolved.csv` に出ます。`data/overrides.json` で手直し → `make data-cache`
- GitHub の Secrets に `YOUTUBE_API_KEY` を登録すると、**毎週自動で新着動画を取り込んで PR** が来ます
- `Config/Local.xcconfig` の `SHOPS_DATA_URL` に raw URL を入れると、アプリ更新なしで最新データが配信されます（公開リポジトリの場合）

## iCloud 同期（任意・有料 Developer Program が必要）

`project.yml` の `entitlements:` のコメントを外し、`Local.xcconfig` に `ICLOUD_CONTAINER = iCloud.com.yourname.susurumap` を書いて `make project`。
訪問記録が自分の iPhone / iPad 間で同期されます。

## GitHub でやっていること

| 仕組み | 内容 |
|---|---|
| `project.yml`（XcodeGen） | `.xcodeproj` を Git に入れずに済むので、友達とファイルを追加しても衝突しない |
| `docs/SPEC.md` + PR テンプレート | 仕様変更は PR で議論して、仕様書も同時に更新 |
| `CHANGELOG.md` + タグ | `v0.2.0` のタグを push すると Release が自動作成。アプリの設定画面にもバージョン表示 |
| Actions: iOS Build | PR ごとにビルドが通るか確認 |
| Actions: Shop Data Check | `shops.json` の形式を検証 |
| Actions: Update Shop Data | 週1で新着動画を取り込み PR 作成 |
| Issue テンプレート | 不具合・機能提案・店舗データ修正 |

## ディレクトリ

```
SusuruMap/
├─ project.yml               XcodeGen の定義（バージョンもここ）
├─ Config/                   xcconfig（Local.xcconfig は各自）
├─ SusuruMap/
│  ├─ App/                   エントリポイント・設定・サービス切替
│  ├─ Models/                Shop, Visit(SwiftData), Review
│  ├─ Services/              店舗データ, レビュー(Firebase/ローカル), カレンダー
│  ├─ Views/                 マップ, 店舗詳細, 訪問記録, レビュー投稿, 設定
│  └─ Resources/             shops.json, Assets
├─ firebase/                 Firestore / Storage セキュリティルール
├─ tools/                    店舗データ生成・検証スクリプト
├─ data/                     手動修正・ジオコードキャッシュ・要確認リスト
├─ scripts/bump_version.py   バージョン更新
└─ docs/SPEC.md              仕様書
```

## 注意

- 非公式アプリです。SUSURU TV. の名称・ロゴ・動画の権利は各権利者に帰属します。公開（App Store 配布など）する場合は、事前に権利者の確認を取ってください。
- ユーザー投稿を扱うため、App Store に出す場合は利用規約・通報への対応体制・プライバシーポリシーが必要です。
