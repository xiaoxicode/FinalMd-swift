#!/usr/bin/env python3
"""定位 compat 一次稳定倒退与缩进代码保留倒退的具体文件/用例。"""
import json

base = "/Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift/tests/fixtures"
r = json.load(open(base + "/RESULTS.json"))

print("== RESULTS.json 顶层键 ==")
print(list(r.keys()))

# 文件级
files = r.get("files", [])
unstable_files = [f for f in files if not f.get("stable_once", f.get("stable", True))]
print(f"\n== 文件一次不稳定 {len(unstable_files)} ==")
for f in unstable_files:
    print(f"  {f.get('path', f.get('local_path'))} keys={list(f.keys())[:12]}")

# 用例级
cases = r.get("spec_cases", r.get("cases", []))
unstable_cases = [c for c in cases if not c.get("stable_once", c.get("stable", True))]
print(f"\n== 用例一次不稳定 {len(unstable_cases)} ==")
for c in unstable_cases:
    print(f"  [{c.get('id')}] {c.get('name', c.get('section'))} md={repr(c.get('markdown',''))[:80]}")

# 缩进代码
def scan_indented(obj, path="root"):
    hits = []
    if isinstance(obj, dict):
        s = json.dumps(obj, ensure_ascii=False)
        if "indented" in s.lower() and ("121" in s or "122" in s or "retain" in s.lower()):
            hits.append((path, {k: v for k, v in obj.items() if not isinstance(v, (dict, list))}))
        for k, v in obj.items():
            hits += scan_indented(v, path + "." + str(k))
    elif isinstance(obj, list):
        for i, v in enumerate(obj[:50]):
            hits += scan_indented(v, path + f"[{i}]")
    return hits

print("\n== 缩进代码相关字段 ==")
for p, kv in scan_indented(r)[:10]:
    print(p, kv)
