#!/usr/bin/env python3
"""探 004-sample.md 的 out1 与源码差异（定位缩进代码丢块）"""
import json, subprocess, difflib

base = "/Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift"
md = open(base + "/tests/fixtures/sources/markdown-it/004-sample.md", encoding="utf-8").read()
probe = {"source": "p", "version": "t", "count": 1,
         "cases": [{"id": 1, "section": "t", "markdown": md, "ref": "cm", "check": "stable"}]}
with open("/tmp/p004.json", "w") as f:
    json.dump(probe, f)
subprocess.run(["/tmp/finalmd-mainstream", "/tmp/p004.json", "/tmp/p004.out.json"], timeout=60)
r = json.load(open("/tmp/p004.out.json"))
row = (r["results"] if isinstance(r, dict) and "results" in r else r)[0]
out1 = row["out1"]
print("stable:", row.get("stable"))
a = md.splitlines()
b = out1.splitlines()
diff = list(difflib.unified_diff(a, b, "source", "out1", lineterm="", n=2))
print("diff lines:", len(diff))
print("\n".join(diff[:80]))
