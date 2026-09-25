#!/bin/bash
# Finder でダブルクリックすると、Xcode プロジェクトを作って開きます。
cd "$(dirname "$0")" || exit 1
echo "🍜 すするマップを準備しています…"

if ! command -v brew >/dev/null 2>&1; then
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$p" ] && eval "$("$p" shellenv)"
  done
fi
if ! command -v brew >/dev/null 2>&1; then
  echo ""
  echo "❌ Homebrew が見つかりません。https://brew.sh の手順で入れてから、もう一度ダブルクリックしてください。"
  read -r -p "Enter で閉じます"
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "→ XcodeGen をインストールしています（初回のみ・1〜2分）"
  brew install xcodegen || { read -r -p "インストールに失敗しました。Enter で閉じます"; exit 1; }
fi

if [ ! -f Config/Local.xcconfig ]; then
  cp Config/Local.xcconfig.example Config/Local.xcconfig
  echo "→ Config/Local.xcconfig を作りました（Team ID などはあとで書き換えてください）"
fi

echo "→ Xcode プロジェクトを生成しています"
xcodegen generate || { read -r -p "生成に失敗しました。Enter で閉じます"; exit 1; }

open SusuruMap.xcodeproj
echo "✅ Xcode を開きました。このウィンドウは閉じて大丈夫です。"
