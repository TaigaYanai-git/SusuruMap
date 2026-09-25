# 🍜 すするマップ

YouTuber **SUSURU TV.** が訪れたラーメン店を地図で探せる iOS アプリ（非公式・ファンメイド）。

- 地図上の店をタップ → その店が紹介された **すするTVの動画** へ
- **「行った！」チェック**（訪問日つき・iCloud 同期・カレンダー登録）と制覇率
- **美味しさ★・コメント・ラーメン写真** を投稿して他のユーザーと共有

仕様は [`docs/SPEC.md`](docs/SPEC.md)、変更履歴は [`CHANGELOG.md`](CHANGELOG.md)、共同開発のルールは [`CONTRIBUTING.md`](CONTRIBUTING.md)。

---

## はじめかた（各自の Mac で）

必要なもの：Xcode 16 以上、Homebrew。開発者は Developer Program のチーム（無料アカウントでも iCloud を外せばビルド可）。**使うだけの友達は TestFlight で入れるだけ**でOK

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

## iCloud 同期（訪問記録）

Developer Program のチームでビルドする前提で **最初から ON** です（`Config/Base.xcconfig` の `CODE_SIGN_ENTITLEMENTS`）。
コンテナ ID は `iCloud.<BUNDLE_ID_PREFIX>.susurumap` が自動で使われます。

1. 初回ビルド前に Xcode の *Signing & Capabilities* で iCloud の欄を開き、コンテナにチェックが入っていることを確認
   （自動署名なら Developer サイトへの登録も Xcode がやります）
2. 実機を2台用意して同じ Apple ID でサインイン → 片方で「行った！」を記録すると、もう片方に数十秒で反映
3. **TestFlight / App Store に出す前に** [CloudKit Console](https://icloud.developer.apple.com/) で
   Schema を **Deploy to Production** する（これを忘れると TestFlight 版で同期されません）

友達が無料アカウントで自分用にビルドする場合は、`Local.xcconfig` に `CODE_SIGN_ENTITLEMENTS =` を書けば iCloud なし（端末内保存）でビルドできます。

## TestFlight で友達に配る

`v*` タグを push すると GitHub Actions がビルドして TestFlight に上げます（`.github/workflows/testflight.yml`）。

**最初に1回だけ**
1. [App Store Connect](https://appstoreconnect.apple.com/) で新規アプリを作成（Bundle ID は `<BUNDLE_ID_PREFIX>.susurumap`）
2. *ユーザとアクセス > 統合 > App Store Connect API* でキーを発行（ロール **Admin**。CI で証明書を自動作成するため）
3. GitHub の *Settings > Secrets and variables > Actions* に登録
   | 種類 | 名前 | 値 |
   |---|---|---|
   | Secret | `APPLE_TEAM_ID` | Team ID |
   | Secret | `ASC_KEY_ID` / `ASC_ISSUER_ID` | API キーの ID / Issuer ID |
   | Secret | `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` の結果 |
   | Secret | `GOOGLE_SERVICE_INFO_PLIST_BASE64` | `base64 -i GoogleService-Info.plist \| pbcopy` の結果 |
   | Variable | `BUNDLE_ID_PREFIX` | 例 `com.toraapple` |
4. 友達の招待：TestFlight の「外部テスト」でグループを作り **公開リンク** を発行（初回ビルドだけ Apple の簡易審査あり）

**リリースのたびに**
```bash
python3 scripts/bump_version.py 0.2.0
git commit -am "chore: release v0.2.0" && git tag v0.2.0 && git push origin main --tags
```
→ GitHub Release（変更点）と TestFlight ビルドが同時にできます。友達の TestFlight アプリに更新通知が届きます。

## GitHub でやっていること

| 仕組み | 内容 |
|---|---|
| `project.yml`（XcodeGen） | `.xcodeproj` を Git に入れずに済むので、友達とファイルを追加しても衝突しない |
| `docs/SPEC.md` + PR テンプレート | 仕様変更は PR で議論して、仕様書も同時に更新 |
| `CHANGELOG.md` + タグ | `v0.2.0` のタグを push すると Release が自動作成。アプリの設定画面にもバージョン表示 |
| Actions: iOS Build | PR ごとにビルドが通るか確認 |
| Actions: Shop Data Check | `shops.json` の形式を検証 |
| Actions: Update Shop Data | 週1で新着動画を取り込み PR 作成 |
| Actions: TestFlight | タグを push するとビルドして TestFlight に配信 |
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
├─ ci/                      TestFlight 用の ExportOptions.plist
├─ firebase/                 Firestore / Storage セキュリティルール
├─ tools/                    店舗データ生成・検証スクリプト
├─ data/                     手動修正・ジオコードキャッシュ・要確認リスト
├─ scripts/bump_version.py   バージョン更新
└─ docs/SPEC.md              仕様書
```

## 注意

- 非公式アプリです。SUSURU TV. の名称・ロゴ・動画の権利は各権利者に帰属します。公開（App Store 配布など）する場合は、事前に権利者の確認を取ってください。
- ユーザー投稿を扱うため、App Store に出す場合は利用規約・通報への対応体制・プライバシーポリシーが必要です。
