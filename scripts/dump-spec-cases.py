#!/usr/bin/env python3
import json

base = "/Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift"

for fname, ids in [("commonmark-0.31.2.json", {76, 608}), ("gfm-0.29.json", {46, 614})]:
    d = json.load(open(base + "/tests/fixtures/specs/" + fname))
    cases = d["cases"] if isinstance(d, dict) and "cases" in d else d
    for c in cases:
        if c.get("id") in ids:
            print(f"[{fname} #{c['id']}]")
            print(json.dumps(c, ensure_ascii=False)[:600])
            print("---")

r = json.load(open(base + "/tests/fixtures/RESULTS.json"))
print("\n== raw_missed > 0 ==")
for f in r["files"]:
    if f.get("raw_missed"):
        print(f["local_path"], "raw_missed=", f["raw_missed"], "raw_kept=", f.get("raw_kept"))
