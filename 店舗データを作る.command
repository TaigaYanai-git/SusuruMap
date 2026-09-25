#!/bin/bash
# ダブルクリックすると、SUSURU TV. の全動画から店舗データ（shops.json）を作ります。
cd "$(dirname "$0")" || exit 1
SERVICE="susurumap-youtube-api-key"
echo "🍜 すするTVの店舗データを作ります"
echo ""

KEY=$(security find-generic-password -s "$SERVICE" -w 2>/dev/null)
if [ -z "$KEY" ]; then
  echo "YouTube の APIキーを貼り付けて Enter を押してください。"
  echo "（貼り付けても画面には何も表示されませんが、入力されています）"
  read -r -s KEY
  echo ""
  if [ -z "$KEY" ]; then
    echo "❌ キーが空でした。もう一度ダブルクリックしてやり直してください。"
    read -r -p "Enter で閉じます"; exit 1
  fi
  security add-generic-password -a "$USER" -s "$SERVICE" -w "$KEY" -U \
    && echo "→ キーを Mac のキーチェーンに保存しました（次回からは入力不要です）"
fi

echo ""
echo "→ 動画の一覧を取り、お店の場所を調べます。"
echo "  初回は 30分〜1時間ほどかかります。この画面は閉じずに、そのまま待ってください。"
echo "  （実行中は Mac がスリープしないようにしています）"
echo ""

if ! YOUTUBE_API_KEY="$KEY" caffeinate -i python3 tools/fetch_susuru_shops.py; then
  echo ""
  echo "❌ 途中で止まりました。上に出ているメッセージを Claude に貼ってください。"
  echo ""
  read -r -p "APIキーが間違っていた場合は y を押して Enter（保存したキーを消します）: " ANS
  [ "$ANS" = "y" ] && security delete-generic-password -s "$SERVICE" >/dev/null 2>&1 && echo "→ 保存したキーを消しました"
  read -r -p "Enter で閉じます"; exit 1
fi

python3 tools/validate_shops.py
echo ""
echo "✅ 完了しました。"
echo "  ・Xcode に戻って ▶︎ を押すと、地図に本物のお店が表示されます"
echo "  ・場所が怪しいお店の一覧は data/unresolved.csv にあります（あとで確認でOK）"
echo ""
read -r -p "Enter で閉じます"
