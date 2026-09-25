# 共同開発のルール

## ブランチと PR

- `main` は常にビルドが通る状態。**直接 push しない**（GitHub の Branch protection で「PR 必須」「iOS Build が成功」を設定推奨）
- 作業ブランチ名：`feat/〇〇`, `fix/〇〇`, `data/〇〇`, `docs/〇〇`
- PR を出すと GitHub Actions がビルドと店舗データの検証を自動で行う
- 仕様が変わる PR は `docs/SPEC.md` と `CHANGELOG.md` の `[Unreleased]` も更新する

```bash
git switch -c feat/shop-clustering
# … 作業 …
git commit -m "feat: ピンをクラスタリング表示"
git push -u origin feat/shop-clustering   # → GitHub で PR を作成
```

## コミットメッセージ

[Conventional Commits](https://www.conventionalcommits.org/ja/) の接頭辞を使う：
`feat:` 新機能 / `fix:` 修正 / `data:` 店舗データ / `docs:` 仕様・README / `chore:` 雑務 / `refactor:` 整理

## バージョンとリリース

- `MAJOR.MINOR.PATCH`（SemVer）。機能追加で MINOR、修正のみで PATCH を上げる
- バージョンの正は `project.yml` の `MARKETING_VERSION`（アプリの設定画面にも表示される）

```bash
python3 scripts/bump_version.py 0.2.0          # project.yml と CHANGELOG を更新
git commit -am "chore: release v0.2.0"
git tag v0.2.0 && git push origin main --tags   # → GitHub Release が自動作成
```

友達に「今どのバージョン使ってる？」と聞けば、Release ページの変更点と照らし合わせられる。

## 店舗データの直し方

1. Issue テンプレート「🍜 店舗データの修正」で報告、または自分で直す
2. `data/overrides.json` に動画IDをキーにして修正を書く
3. `make data-cache`（手元に `data/videos_cache.json` がある場合）または PR を出して Actions に任せる
4. PR をマージ → `SHOPS_DATA_URL` を設定したアプリは次回起動時に反映

## Xcode プロジェクトについて

`SusuruMap.xcodeproj` は **Git に入れない**。`project.yml` から `make project` で生成する。
（`.pbxproj` のマージ衝突が起きなくなる。ファイルを追加したら `make project` し直す）
