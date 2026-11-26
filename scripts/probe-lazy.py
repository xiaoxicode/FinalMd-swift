#!/usr/bin/env python3
"""diff kramdown/004-lazy.text source vs out1"""
import json, subprocess, difflib

base = "/Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift"
md = open(base + "/tests/fixtures/sources/kramdown/004-lazy.text", encoding="utf-8").read()
probe = {"source": "p", "version": "t", "count": 1,
         "cases": [{"id": 1, "section": "t", "markdown": md, "ref": "cm", "check": "stable"}]}
with open("/tmp/plazy.json", "w") as f:
    json.dump(probe, f)
subprocess.run(["/tmp/finalmd-mainstream", "/tmp/plazy.json", "/tmp/plazy.out.json"], timeout=60)
r = json.load(open("/tmp/plazy.out.json"))
row = (r["results"] if isinstance(r, dict) and "results" in r else r)[0]
print("stable:", row.get("stable"))
diff = list(difflib.unified_diff(md.splitlines(), row["out1"].splitlines(), "source", "out1", lineterm="", n=3))
print("\n".join(diff[:60]))
