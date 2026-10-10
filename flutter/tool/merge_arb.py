#!/usr/bin/env python3
"""Merge lib/l10n/parts/<feature>_<lang>.arb into lib/l10n/app_<lang>.arb.

Each feature keeps its own string file, so several features built at the same time never collide editing one ARB.
Fails on duplicate keys. Run: python3 tool/merge_arb.py && flutter gen-l10n
"""
import json, pathlib, sys

root = pathlib.Path(__file__).resolve().parent.parent / "lib" / "l10n"
langs = {}
for part in sorted((root / "parts").glob("*_*.arb")):
    lang = part.stem.rsplit("_", 1)[1]
    data = json.loads(part.read_text(encoding="utf-8"))
    merged = langs.setdefault(lang, {"@@locale": lang})
    for k, v in data.items():
        if k == "@@locale":
            continue
        if k in merged:
            sys.exit(f"duplicate key {k} in {part.name}")
        merged[k] = v
keysets = {lang: {k for k in m if not k.startswith("@")} for lang, m in langs.items()}
base = keysets.get("ko", set())
for lang, ks in keysets.items():
    if ks != base:
        sys.exit(f"{lang} keys differ from ko: missing {sorted(base - ks)[:5]} extra {sorted(ks - base)[:5]}")
for lang, m in langs.items():
    (root / f"app_{lang}.arb").write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("merged", {lang: len(ks) for lang, ks in keysets.items()})
