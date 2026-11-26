#!/usr/bin/env python3
"""甄别 6 份 hr 特征丢失文件：源码里每个 hr 命中行的上下文分类 + 往返后去向。"""
import json, re, subprocess, sys, os

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
HR_PRESERVE = re.compile(r"^\s{0,3}([-*_])\s*(\1\s*){2,}$|^\s*---+\s*$", re.M)

def classify(lines, idx):
    """给 hr 行打上下文标签。"""
    line = lines[idx]
    stripped = line.strip()
    # frontmatter 区间
    if lines and lines[0].strip() == "---":
        end = None
        for j in range(1, len(lines)):
            if lines[j].strip() == "---":
                end = j
                break
        if end is not None and idx <= end:
            return "frontmatter-delimiter" if idx in (0, end) else "frontmatter-inner"
    # 围栏内（线性扫描围栏开闭）
    fence = None
    for j in range(idx):
        t = lines[j].strip()
        if fence is None:
            m = re.match(r"^(`{3,}|~{3,})", t)
            if m:
                fence = m.group(1)
        else:
            if re.match(r"^" + re.escape(fence[0]) + "{" + str(len(fence)) + r",}\s*$", t):
                fence = None
    if fence:
        return "inside-fence"
    # 缩进代码内（连续 4+ 空格行）
    if re.match(r"^(?: {4}|\t)", line) and (idx == 0 or lines[idx-1].strip() == "" or re.match(r"^(?: {4}|\t)", lines[idx-1])):
        return "indented-code?"
    # Setext 下划线：前一行非空且不是块开始
    if idx > 0:
        prev = lines[idx-1]
        pt = prev.strip()
        if pt and not re.match(r"^(#{1,6}\s|>|[-*+]\s|\d+[.)]\s|```|~~~)", pt) \
           and not HR_DETECT.match(prev):
            return "setext-underline"
    return "REAL-hr"

def main():
    report = []
    for rel in FILES:
        path = os.path.join(BASE, rel)
        src = open(path, encoding="utf-8").read()
        lines = src.split("\n")
        hits = []
        for i, ln in enumerate(lines):
            if HR_DETECT.match(ln):
                hits.append((i + 1, ln, classify(lines, i)))
        # 往返
        probe = {"source": "p", "version": "t", "count": 1,
                 "cases": [{"id": 1, "section": "t", "markdown": src, "ref": "cm", "check": "stable"}]}
        with open("/tmp/hr-probe.json", "w") as f:
            json.dump(probe, f)
        subprocess.run(["/tmp/finalmd-mainstream", "/tmp/hr-probe.json", "/tmp/hr-probe.out.json"],
                       timeout=30, capture_output=True, check=True)
        out = json.load(open("/tmp/hr-probe.out.json"))
        o = out["results"][0] if isinstance(out, dict) and "results" in out else out[0]
        out1 = o["out1"]
        out_hits = [(m.start(), m.group(0)) for m in HR_PRESERVE.finditer(out1)]
        report.append({"file": rel, "src_hits": hits, "out_hr_lines": len(out_hits),
                       "out_sample": [h[1] for h in out_hits[:5]], "stable": o.get("stable")})
        print(f"\n== {rel} == stable={o.get('stable')} out_hr_lines={len(out_hits)}")
        for ln_no, text, kind in hits:
            print(f"  L{ln_no} [{kind}] {text!r}")
    json.dump(report, open("/tmp/hr-report.json", "w"), ensure_ascii=False, indent=1)
    print("\nsummary written /tmp/hr-report.json")

if __name__ == "__main__":
    main()
