.PHONY: setup project open data data-cache validate

setup:          ## 初回セットアップ（XcodeGen の導入と個人設定ファイルの作成）
	@command -v xcodegen >/dev/null || brew install xcodegen
	@test -f Config/Local.xcconfig || cp Config/Local.xcconfig.example Config/Local.xcconfig
	@echo "→ Config/Local.xcconfig に DEVELOPMENT_TEAM などを書いてから 'make project'"

project:        ## project.yml から Xcode プロジェクトを生成
	xcodegen generate

open: project   ## 生成して Xcode で開く
	open SusuruMap.xcodeproj

data:           ## YouTube API から店舗データを再生成（要 YOUTUBE_API_KEY）
	python3 tools/fetch_susuru_shops.py && python3 tools/validate_shops.py

data-cache:     ## 前回取得した動画一覧から再生成（overrides.json の修正を反映するとき）
	python3 tools/fetch_susuru_shops.py --from-cache && python3 tools/validate_shops.py

validate:       ## shops.json の形式チェック
	python3 tools/validate_shops.py
