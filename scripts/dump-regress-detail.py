#!/usr/bin/env python3
"""dump 倒退用例全文 + features 缩进代码条目 + 标题语料片段"""
import json

base = "/Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift"
r = json.load(open(base + "/tests/fixtures/RESULTS.json"))

print("== 不稳定用例全文 ==")
for c in r["spec_cases"]:
    if not c.get("stable", True):
        print(json.dumps(c, ensure_ascii=False)[:600])
        print("---")

print("\n== features 里 retention < 1.0 的条目 ==")
feats = r.get("features", {})
if isinstance(feats, dict):
    for k, v in feats.items():
        s = json.dumps(v, ensure_ascii=False)
        if "1.0" not in s or "122" in s or "121" in s:
            print(k, "=>", s[:300])
elif isinstance(feats, list):
    for f in feats:
        kept = f.get("kept", f.get("exact", 0))
        total = f.get("total", f.get("count", 0))
        if total and kept != total:
            print(json.dumps(f, ensure_ascii=False)[:400])

print("\n== 标题语料行（含 # 或 ===）==")
for p in ["tests/fixtures/sources/cmark-gfm/005-block-heading.md",
          "tests/fixtures/sources/commonmarkjs/008-block-heading.md",
          "tests/fixtures/sources/kramdown/003-atx_header.text"]:
    print(f"\n--- {p} ---")
    txt = open(base + "/" + p, encoding="utf-8").read()
    for i, line in enumerate(txt.splitlines()[:40]):
        print(f"{i:>3}| {line}")
