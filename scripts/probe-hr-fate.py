#!/usr/bin/env python3
"""核对每处 hr 命中的去向：源码前导行文本 → out1 中是否出现对应 ATX 标题 / 文本是否保留。"""
import json, re, subprocess, os

BASE = "/Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift"
FILES = [
    "tests/fixtures/sources/cmark/006-README.md",
    "tests/fixtures/sources/cmark/007-why-cmark-and-not-x.md",
    "tests/fixtures/sources/cmark-gfm/008-block-lheading.md",
    "tests/fixtures/sources/commonmarkjs/001-README.md",
    "tests/fixtures/sources/commonmarkjs/004-README.md",
    "tests/fixtures/sources/stackedit/002-markdownSample.md",
]
HR_DETECT = re.compile(r"^\s{0,3}([-*_])\s*(\1\s*){2,}$", re.M)

for rel in FILES:
    path = os.path.join(BASE, rel)
    src = open(path, encoding="utf-8").read()
    lines = src.split("\n")
    probe = {"source": "p", "version": "t", "count": 1,
             "cases": [{"id": 1, "section": "t", "markdown": src, "ref": "cm", "check": "stable"}]}
    with open("/tmp/hr-probe.json", "w") as f:
        json.dump(probe, f)
    subprocess.run(["/tmp/finalmd-mainstream", "/tmp/hr-probe.json", "/tmp/hr-probe.out.json"],
                   timeout=30, capture_output=True, check=True)
    out = json.load(open("/tmp/hr-probe.out.json"))
    o = out["results"][0] if isinstance(out, dict) and "results" in out else out[0]
    out1 = o["out1"]
    print(f"\n== {rel} ==")
    for i, ln in enumerate(lines):
        if not HR_DETECT.match(ln):
            continue
        prev = lines[i-1] if i > 0 else ""
        ptext = prev.strip()
        # 去向1：转成 ATX 标题
        atx = f"# {ptext}" if ptext else None
        # 去向2：文本仍在（可能成段落）
        as_para = ptext and ptext in out1
        atx_ok = atx and atx in out1
        verdict = ("→ATX标题✓" if atx_ok else
                   ("→文本保留(未成标题)✗" if as_para else "→内容丢失✗✗"))
        print(f"  L{i+1} {ln.strip()[:20]!r:24} prev={ptext[:40]!r:44} {verdict}")
