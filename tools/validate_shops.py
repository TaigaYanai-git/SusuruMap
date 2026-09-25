#!/usr/bin/env python3
"""shops.json の形式チェック（CI と pre-commit 用）。問題があれば終了コード 1。"""
import json
import re
import sys
from pathlib import Path

DEFAULT = Path(__file__).resolve().parent.parent / "SusuruMap" / "Resources" / "shops.json"
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")


def validate(path):
    errors = []
    try:
        catalog = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        return [f"JSON として読めません: {e}"]

    for key in ("version", "shops"):
        if key not in catalog:
            errors.append(f"トップレベルに '{key}' がありません")
    seen = set()
    for i, s in enumerate(catalog.get("shops", [])):
        where = f"shops[{i}] ({s.get('name', '?')})"
        for key, typ in (("id", str), ("name", str), ("latitude", (int, float)),
                         ("longitude", (int, float)), ("videos", list)):
            if not isinstance(s.get(key), typ):
                errors.append(f"{where}: '{key}' が不正")
        if s.get("id") in seen:
            errors.append(f"{where}: id '{s['id']}' が重複")
        seen.add(s.get("id"))
        lat, lng = s.get("latitude"), s.get("longitude")
        if isinstance(lat, (int, float)) and isinstance(lng, (int, float)):
            if not (20 <= lat <= 46 and 122 <= lng <= 154):
                errors.append(f"{where}: 座標 ({lat}, {lng}) が日本の範囲外（海外店なら無視してOK）")
        if not s.get("videos"):
            errors.append(f"{where}: videos が空")
        for v in s.get("videos", []):
            vid = v.get("videoId")
            if vid is not None and not VIDEO_ID.match(vid):
                errors.append(f"{where}: videoId '{vid}' の形式が不正")
            if not v.get("title"):
                errors.append(f"{where}: 動画タイトルが空")
    return errors


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    errors = validate(path)
    catalog_size = len(json.loads(path.read_text(encoding="utf-8")).get("shops", [])) if not errors else "?"
    if errors:
        print(f"❌ {path}: {len(errors)} 件の問題")
        for e in errors[:200]:
            print("  -", e)
        return 1
    print(f"✅ {path}: {catalog_size} 店舗 OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
