#!/usr/bin/env python3
"""
バージョンを上げる。project.yml と CHANGELOG.md をまとめて更新する。

  python3 scripts/bump_version.py 0.2.0     # MARKETING_VERSION=0.2.0, ビルド番号+1
  python3 scripts/bump_version.py --build   # ビルド番号だけ +1（TestFlight 再提出など）

その後:
  git commit -am "chore: release v0.2.0"
  git tag v0.2.0 && git push origin main --tags   # → GitHub Release が自動作成される
"""
from __future__ import annotations

import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "project.yml"
CHANGELOG = ROOT / "CHANGELOG.md"
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    arg = sys.argv[1]
    text = PROJECT.read_text(encoding="utf-8")

    build = int(re.search(r'CURRENT_PROJECT_VERSION: "(\d+)"', text).group(1)) + 1
    text = re.sub(r'CURRENT_PROJECT_VERSION: "\d+"', f'CURRENT_PROJECT_VERSION: "{build}"', text)

    if arg != "--build":
        if not SEMVER.match(arg):
            print(f"バージョンは X.Y.Z 形式で指定してください: {arg}")
            return 1
        old = re.search(r'MARKETING_VERSION: "([^"]+)"', text).group(1)
        text = re.sub(r'MARKETING_VERSION: "[^"]+"', f'MARKETING_VERSION: "{arg}"', text)

        log = CHANGELOG.read_text(encoding="utf-8")
        if f"## [{arg}]" in log:
            print(f"CHANGELOG に {arg} は既にあります")
            return 1
        log = log.replace("## [Unreleased]", f"## [Unreleased]\n\n## [{arg}] - {date.today().isoformat()}", 1)
        CHANGELOG.write_text(log, encoding="utf-8")
        print(f"MARKETING_VERSION: {old} → {arg}")

    PROJECT.write_text(text, encoding="utf-8")
    print(f"CURRENT_PROJECT_VERSION → {build}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
