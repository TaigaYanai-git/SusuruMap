#!/usr/bin/env python3
"""
SUSURU TV. の全動画から「ラーメン店データ（shops.json）」を生成する。

  1. YouTube Data API v3 で公式チャンネルのアップロード動画を全件取得
  2. 概要欄・タイトルから店名と住所を推定
  3. 住所があれば国土地理院のジオコーダ、なければ店名で OpenStreetMap を検索して緯度経度に
     （どちらも APIキー不要・無料。相手サーバーに配慮して1件ずつ間隔をあける）
  4. 同じ店の動画をまとめて SusuruMap/Resources/shops.json に書き出す

推定できなかった動画は data/unresolved.csv に出る。
data/overrides.json で手動修正できる（修正は PR で共有 → GitHub Actions で再生成）。

使い方:
  export YOUTUBE_API_KEY=xxxx
  python3 tools/fetch_susuru_shops.py              # API から取得して生成
  python3 tools/fetch_susuru_shops.py --from-cache # 前回取得した動画一覧から再生成（API不要）

依存: Python 3.9+ 標準ライブラリのみ
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "SusuruMap" / "Resources" / "shops.json"
DATA = ROOT / "data"
VIDEOS_CACHE = DATA / "videos_cache.json"      # Git 管理外（大きいので）
GEOCODE_CACHE = DATA / "geocode_cache.json"    # Git 管理（再取得を避ける）
OVERRIDES = DATA / "overrides.json"            # Git 管理（手動修正）
UNRESOLVED = DATA / "unresolved.csv"           # Git 管理（修正待ちリスト）

YT_API = "https://www.googleapis.com/youtube/v3/"
# SUSURU TV. 公式チャンネル（@SUSURUTV）のアップロード動画プレイリスト
DEFAULT_UPLOADS_PLAYLIST = "UUXcjvt8cOfwtcqaMeE7-hqA"
GSI_GEOCODER = "https://msearch.gsi.go.jp/address-search/AddressSearch?q="
NOMINATIM = "https://nominatim.openstreetmap.org/search?"

PREFECTURES = [
    "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県", "茨城県", "栃木県",
    "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県", "新潟県", "富山県", "石川県", "福井県",
    "山梨県", "長野県", "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府",
    "兵庫県", "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県",
    "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県",
    "鹿児島県", "沖縄県",
]
PREF_ALT = "|".join(PREFECTURES)
ADDRESS_IN_TEXT = re.compile(rf"((?:{PREF_ALT})[^\s、，,。【】()（）「」]{{3,50}})")
LABELED = re.compile(r"^\s*[■◆●▼☆★・\-]*\s*(店名|店舗名|お店|住所|所在地|場所)\s*[:：]\s*(.+)$")
ZIP_LINE = re.compile(r"〒?\s*\d{3}-\d{4}\s*(.+)")
# SUSURU TV. のタイトル形式: 「（見出し）。をすする 店名【飯テロ】SUSURU TV.第3900回」
# → 最後の「すする」から【飯テロ】（なければ SUSURU TV.）までが店名
TITLE_SHOP = re.compile(r".*すする\s*(.+?)\s*【飯テロ】")
TITLE_SHOP_ALT = re.compile(r".*すする\s*(.+?)\s*SUSURU\s*TV", re.IGNORECASE)
# 店ではない回（カップ麺・袋麺・通販など）を見分ける語
NOT_SHOP_WORDS = ("カップ", "袋麺", "日清", "マルちゃん", "明星", "サッポロ一番", "エースコック",
                  "セブン", "ローソン", "ファミマ", "ファミリーマート", "宅麺", "冷凍", "コンビニ", "自作")


def norm(s: str) -> str:
    return unicodedata.normalize("NFKC", s).strip()


def load_json(path: Path, default):
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return default


def http_json(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "SusuruMap-data-builder/0.2 (fan-made app; github.com)", "Accept-Language": "ja"})
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.load(res)


# ---------------------------------------------------------------- YouTube

def fetch_videos(api_key: str, playlist: str) -> list[dict]:
    videos, token = [], None
    while True:
        params = {"part": "snippet", "playlistId": playlist, "maxResults": 50, "key": api_key}
        if token:
            params["pageToken"] = token
        page = http_json(YT_API + "playlistItems?" + urllib.parse.urlencode(params))
        for item in page.get("items", []):
            sn = item["snippet"]
            vid = sn.get("resourceId", {}).get("videoId")
            if not vid:
                continue
            videos.append({
                "videoId": vid,
                "title": sn.get("title", ""),
                "description": sn.get("description", ""),
                "publishedAt": sn.get("publishedAt"),
            })
        token = page.get("nextPageToken")
        print(f"  取得 {len(videos)} 件…", file=sys.stderr)
        if not token:
            return videos


# ---------------------------------------------------------------- 抽出

def extract(video: dict) -> dict:
    """概要欄とタイトルから {name, address, nameSource} を推定する"""
    name = address = None
    for raw in video["description"].splitlines():
        line = norm(raw)
        m = LABELED.match(line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            if key in ("住所", "所在地", "場所") and not address:
                address = val
            elif key in ("店名", "店舗名", "お店") and not name:
                name = val
            continue
        if not address:
            z = ZIP_LINE.match(line)
            if z and ADDRESS_IN_TEXT.search(z.group(1)):
                address = z.group(1).strip()
    if not address:
        m = ADDRESS_IN_TEXT.search(norm(video["description"]))
        if m:
            address = m.group(1)

    name_source = "description"
    if not name:
        name, name_source = shop_from_title(video["title"]), "title"

    if address:
        address = re.split(r"\s{2,}|　|TEL|電話|営業|定休", address)[0].strip()
    return {"name": name, "address": address, "nameSource": name_source}


def shop_from_title(title: str) -> str | None:
    t = norm(title)
    for rx in (TITLE_SHOP, TITLE_SHOP_ALT):
        m = rx.match(t)
        if m:
            name = re.sub(r"【[^】]*】|#\S+", "", m.group(1)).strip(" -!！。、")
            if name:
                return name
    return None


def looks_like_non_shop(name: str | None) -> bool:
    return bool(name) and any(w in name for w in NOT_SHOP_WORDS)


def prefecture_of(text: str | None) -> str | None:
    if not text:
        return None
    return next((p for p in PREFECTURES if p in text), None)


# ---------------------------------------------------------------- ジオコーディング

def geocode(address: str, cache: dict, retry_failed: bool) -> dict | None:
    if address in cache and (cache[address] is not None or not retry_failed):
        return cache[address]
    try:
        res = http_json(GSI_GEOCODER + urllib.parse.quote(address))
    except Exception as e:  # noqa: BLE001
        print(f"  ジオコード失敗 {address}: {e}", file=sys.stderr)
        return None
    time.sleep(0.3)  # 相手サーバーへの配慮
    if res:
        lng, lat = res[0]["geometry"]["coordinates"]
        cache[address] = {"lat": round(lat, 6), "lng": round(lng, 6), "matched": res[0]["properties"].get("title")}
    else:
        cache[address] = None
    return cache[address]


def search_by_name(name: str, cache: dict, retry_failed: bool) -> dict | None:
    """住所がないとき、店名で OpenStreetMap を検索（飲食店・お店だけを採用）"""
    key = "name:" + name
    if key in cache and (cache[key] is not None or not retry_failed):
        return cache[key]
    params = {"q": name, "format": "jsonv2", "countrycodes": "jp", "limit": 5, "accept-language": "ja"}
    try:
        res = http_json(NOMINATIM + urllib.parse.urlencode(params))
    except Exception as e:  # noqa: BLE001
        print(f"  店名検索失敗 {name}: {e}", file=sys.stderr)
        return None
    time.sleep(1.1)  # OpenStreetMap の利用規約（1秒に1回まで）
    hit = next((r for r in res if r.get("category", r.get("class")) in ("amenity", "shop")), None)
    if hit:
        cache[key] = {"lat": round(float(hit["lat"]), 6), "lng": round(float(hit["lon"]), 6),
                      "matched": hit.get("display_name"), "source": "osm"}
    else:
        cache[key] = None
    return cache[key]


# ---------------------------------------------------------------- メイン

def build(videos: list[dict], overrides: dict, geo_cache: dict, retry_failed: bool):
    shops: dict[str, dict] = {}
    unresolved: list[dict] = []
    stats: dict[str, int] = {}
    ov_videos = overrides.get("videos", {})

    for i, v in enumerate(videos, 1):
        if i % 50 == 0 or i == len(videos):
            print(f"  場所を調べています… {i} / {len(videos)} 本目（店舗 {len(shops)} 件）", file=sys.stderr)
        ov = ov_videos.get(v["videoId"], {})
        if ov.get("skip"):
            continue
        info = extract(v)
        name = ov.get("name") or info["name"]
        address = ov.get("address") or info["address"]

        def note(reason: str):
            unresolved.append({
                "videoId": v["videoId"], "title": v["title"], "publishedAt": v["publishedAt"],
                "guessedName": name or "", "guessedAddress": address or "", "reason": reason,
            })

        if not name and not address:
            note("店の回ではなさそう")
            continue
        if looks_like_non_shop(name) and not address and "lat" not in ov:
            note("店の回ではなさそう（カップ麺など）")
            continue

        geo = None
        located_by = ""
        if "lat" in ov and "lng" in ov:
            geo, located_by = {"lat": ov["lat"], "lng": ov["lng"]}, "override"
        if geo is None and address:
            geo, located_by = geocode(address, geo_cache, retry_failed), "address"
        if geo is None and name:
            geo, located_by = search_by_name(name, geo_cache, retry_failed), "name"

        if not name or not geo:
            note("場所が見つからない" if name else "店名が分からない")
            continue
        stats[located_by] = stats.get(located_by, 0) + 1
        if located_by == "name":
            note("店名検索で配置（支店違いの可能性・要確認）")

        shop_id = ov.get("shopId") or "s_" + hashlib.sha1(
            f"{norm(name)}|{geo['lat']:.3f},{geo['lng']:.3f}".encode()).hexdigest()[:10]
        shop = shops.setdefault(shop_id, {
            "id": shop_id, "name": name, "address": address,
            "prefecture": prefecture_of(address) or prefecture_of(geo.get("matched")),
            "latitude": geo["lat"], "longitude": geo["lng"], "videos": [],
        })
        shop["videos"].append({"videoId": v["videoId"], "title": v["title"], "publishedAt": v["publishedAt"]})

    for s in shops.values():
        s["videos"].sort(key=lambda x: x["publishedAt"] or "", reverse=True)
    ordered = sorted(shops.values(), key=lambda s: s["videos"][0]["publishedAt"] or "", reverse=True)
    print("配置方法: " + ", ".join(f"{k}={v}" for k, v in sorted(stats.items())), file=sys.stderr)
    return ordered, unresolved


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from-cache", action="store_true", help="data/videos_cache.json を使い API を呼ばない")
    ap.add_argument("--playlist", default=DEFAULT_UPLOADS_PLAYLIST, help="アップロード動画のプレイリストID")
    ap.add_argument("--retry-failed", action="store_true", help="前回ジオコードに失敗した住所も再試行")
    args = ap.parse_args()

    DATA.mkdir(exist_ok=True)
    if args.from_cache:
        videos = load_json(VIDEOS_CACHE, None)
        if videos is None:
            print("data/videos_cache.json がありません。まず API キー付きで実行してください。", file=sys.stderr)
            return 1
    else:
        key = os.environ.get("YOUTUBE_API_KEY")
        if not key:
            print("環境変数 YOUTUBE_API_KEY を設定してください。", file=sys.stderr)
            return 1
        print("YouTube から動画一覧を取得中…", file=sys.stderr)
        videos = fetch_videos(key, args.playlist)
        VIDEOS_CACHE.write_text(json.dumps(videos, ensure_ascii=False), encoding="utf-8")

    overrides = load_json(OVERRIDES, {"videos": {}})
    geo_cache = load_json(GEOCODE_CACHE, {})
    shops, unresolved = build(videos, overrides, geo_cache, args.retry_failed)

    GEOCODE_CACHE.write_text(json.dumps(geo_cache, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
    now = datetime.now(timezone.utc)
    catalog = {
        "version": now.strftime("%Y.%m.%d"),
        "generatedAt": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "note": "tools/fetch_susuru_shops.py により自動生成。修正は data/overrides.json へ。",
        "shops": shops,
    }
    OUTPUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    with UNRESOLVED.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["videoId", "reason", "guessedName", "guessedAddress", "title", "publishedAt"])
        w.writeheader()
        w.writerows(sorted(unresolved, key=lambda r: r["publishedAt"] or "", reverse=True))

    print(f"動画 {len(videos)} 本 → 店舗 {len(shops)} 件 / 要確認 {len(unresolved)} 件", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
