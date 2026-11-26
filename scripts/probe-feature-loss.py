#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""甄别特征丢失：逐命中分类 + 追踪往返输出去向。

对 RESULTS.json 里每个 (feature, file) 丢失对：
1. 用特征 detect 正则在源文件里列出全部命中行（行号+内容）
2. 分类每处命中：thematic-break / setext-underline / inside-fence / real
3. 走 /tmp/finalmd-mainstream 拿到往返输出 out1，追踪每处命中的去向
"""
import json
import re
import subprocess
import sys
import os

BASE = "/Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift"
RESULTS = f"{BASE}/tests/fixtures/RESULTS.json"

FEATURES = {
    "ul":        (re.compile(r"(?m)^\s*[-*+]\s+\S"), r"(?m)^\s*[-*+]\s+\S"),
    "ol":        (re.compile(r"(?m)^\s*\d+[.)]\s+\S"), r"(?m)^\s*\d+[.)]\s+\S"),
    "toc":       (re.compile(r"\[TOC\]"), r"\[TOC\]"),
    "refdef":    (re.compile(r"(?m)^\s{0,3}\[[^\]]+\]:\s*\S+"), r"(?m)^\s{0,3}\[[^\]]+\]:\s*\S+"),
    "highlight": (re.compile(r"==[^=\n]+=="), r"==[^=\n]+=="),
    "strike":    (re.compile(r"~~[^~\n]+~~"), r"~~[^~\n]+~~"),
    "image":     (re.compile(r"!\[[^\]\n]*\]\([^)\n]+\)"), r"!\[[^\]\n]*\]\([^)\n]+\)"),
}

PRESERVE_ALT = {
    # 允许的替代形态（语义保留但写法变化）——人工核对用提示
    "highlight": ["<mark", "background-color"],
    "strike": ["<del", "<s>", "~~"],
    "toc": ["[TOC]", "toc", "目录"],
}


def fence_state(lines):
    """返回每行是否在围栏内的布尔列表。"""
    inside = [False] * len(lines)
    state = None
    for i, ln in enumerate(lines):
        t = ln.strip()
        m = re.match(r"^(`{3,}|~{3,})", t)
        if m:
            tick = m.group(1)
            if state is None:
                state = tick
                inside[i] = True
            elif t.startswith(state[0]) and len(t) >= len(state) and set(t) <= {state[0]}:
                inside[i] = True
                state = None
            else:
                inside[i] = True
            continue
        if state is not None:
            inside[i] = True
    return inside


def classify(idx, lines, inside):
    ln = lines[idx]
    # 围栏内
    if inside[idx]:
        return "inside-fence"
    # 主题分割线（hr）：纯 - *_ 重复 ≥3
    if re.match(r"^\s{0,3}([-*_])(\s*\1){2,}\s*$", ln):
        return "thematic-break"
    # Setext 下划线：纯 =+ 或 -+ 且上一非空行是文本
    if re.match(r"^\s{0,3}(=+|-+)\s*$", ln):
        j = idx - 1
        while j >= 0 and not lines[j].strip():
            j -= 1
        if j >= 0 and not re.match(r"^\s{0,3}([-*_])(\s*\1){2,}\s*$", lines[j]) \
           and not re.match(r"^\s*(`{3,}|~{3,})", lines[j].strip()) \
           and not re.match(r"^\s{0,3}#{1,6}\s", lines[j]):
            return "setext-underline"
    return "real"


def run_mainstream(md_text):
    probe = {"source": "p", "version": "t", "count": 1,
             "cases": [{"id": 1, "section": "t", "markdown": md_text,
                        "ref": "cm", "check": "stable"}]}
    with open("/tmp/fl-probe.json", "w") as f:
        json.dump(probe, f)
    subprocess.run(["/tmp/finalmd-mainstream", "/tmp/fl-probe.json", "/tmp/fl-probe.out.json"],
                   timeout=60, check=True, capture_output=True)
    out = json.load(open("/tmp/fl-probe.out.json"))
    o = out["results"][0] if "results" in out else out[0]
    return o.get("out1", "")


def trace_fate(feature, hit_line, out1, out_lines):
    """追踪命中行在输出中的去向，返回描述。"""
    src = hit_line.strip()
    # 1) 逐字保留
    for j, ol in enumerate(out_lines):
        if ol.strip() == src:
            return f"verbatim@out{j+1}"
    # 2) 内容核心保留（剥掉列表记号/标记）
    core = re.sub(r"^\s*[-*+]\s+", "", src)
    core = re.sub(r"^\s*\d+[.)]\s+", "", core)
    core = core.strip()
    if core:
        for j, ol in enumerate(out_lines):
            if core and core in ol:
                # 避免极短核心误配
                if len(core) >= 3:
                    return f"core-in-out{j+1}:{ol.strip()[:70]}"
    # 3) 特征形态转化
    if feature == "ul":
        # 列表符号归一化？
        m = re.match(r"^\s*([-*+])\s+(.*)$", src)
        if m:
            alt = re.compile(r"^\s*[-*+]\s+" + re.escape(m.group(2)[:20]))
            for j, ol in enumerate(out_lines):
                if alt.match(ol):
                    return f"marker-normalized@out{j+1}:{ol.strip()[:70]}"
    if feature == "ol":
        m = re.match(r"^\s*(\d+)([.)])\s+(.*)$", src)
        if m:
            alt = re.compile(r"^\s*\d+[.)]\s+" + re.escape(m.group(3)[:20]))
            for j, ol in enumerate(out_lines):
                if alt.match(ol):
                    return f"ol-renumbered@out{j+1}:{ol.strip()[:70]}"
    if feature == "strike":
        m = re.match(r"~~([^~]+)~~", src)
        if m:
            core2 = m.group(1)
            for j, ol in enumerate(out_lines):
                if core2 in ol and ("del" in ol or "<s>" in ol or "~~" in ol):
                    return f"strike-transformed@out{j+1}:{ol.strip()[:70]}"
            for j, ol in enumerate(out_lines):
                if core2 in ol:
                    return f"strike-text-only@out{j+1}:{ol.strip()[:70]}"
    if feature == "highlight":
        m = re.match(r"==([^=]+)==", src)
        if m:
            core2 = m.group(1)
            for j, ol in enumerate(out_lines):
                if core2 in ol and ("mark" in ol or "background" in ol or "==" in ol):
                    return f"hl-transformed@out{j+1}:{ol.strip()[:70]}"
            for j, ol in enumerate(out_lines):
                if core2 in ol:
                    return f"hl-text-only@out{j+1}:{ol.strip()[:70]}"
    if feature == "toc":
        for j, ol in enumerate(out_lines):
            if "[TOC]" in ol or "[toc]" in ol.lower():
                return f"toc-literal@out{j+1}:{ol.strip()[:70]}"
        return "toc-vanished (展开或被吞)"
    if feature == "refdef":
        m = re.match(r"^\s{0,3}\[([^\]]+)\]:\s*(\S+)", src)
        if m:
            label, dest = m.group(1), m.group(2)
            for j, ol in enumerate(out_lines):
                if dest in ol:
                    return f"refdef-dest-in-out{j+1}:{ol.strip()[:70]}"
            for j, ol in enumerate(out_lines):
                if f"[{label}]" in ol:
                    return f"refdef-label-in-out{j+1}:{ol.strip()[:70]}"
        return "refdef-vanished"
    if feature == "image":
        m = re.match(r"!\[([^\]\n]*)\]\(([^)\n]+)\)", src)
        if m:
            alt, url = m.group(1), m.group(2)
            for j, ol in enumerate(out_lines):
                if url in ol or (alt and alt in ol and "!" in ol):
                    return f"image-in-out{j+1}:{ol.strip()[:70]}"
        return "image-vanished"
    return "not-found"


def main():
    r = json.load(open(RESULTS))
    targets = []
    for f in r["files"]:
        det = f.get("detected", [])
        pre = f.get("preserved", [])
        for k in det:
            if k not in pre:
                targets.append((k, f["local_path"]))

    report = []
    for feat, relpath in sorted(targets):
        path = os.path.join(BASE, relpath)
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        lines = text.split("\n")
        inside = fence_state(lines)
        rx = FEATURES[feat][0]
        print(f"\n===== {feat} | {relpath} =====")
        md_out = run_mainstream(text)
        out_lines = md_out.split("\n")
        hits = []
        for i, ln in enumerate(lines):
            if rx.search(ln):
                hits.append(i)
        if not hits:
            # 多行正则（(?m) 已覆盖逐行）；若无命中说明 detect 在整文匹配（如 toc 用 finditer 跨行）
            for m in rx.finditer(text):
                line_no = text[:m.start()].count("\n")
                hits.append(line_no)
            hits = sorted(set(hits))
        for i in hits:
            cls = classify(i, lines, inside)
            fate = trace_fate(feat, lines[i], md_out, out_lines) if cls == "real" else "-"
            print(f"  L{i+1:4d} [{cls:16s}] {lines[i][:80]!r}")
            if cls == "real":
                print(f"         -> {fate}")
            report.append({"feature": feat, "file": relpath, "line": i + 1,
                           "class": cls, "src": lines[i], "fate": fate})

    with open("/tmp/feature-loss-report.json", "w") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    print("\n\n==== 汇总 ====")
    from collections import Counter
    c = Counter((x["feature"], x["class"]) for x in report)
    for (feat, cls), n in sorted(c.items()):
        print(f"  {feat:10s} {cls:18s} x{n}")
    reals = [x for x in report if x["class"] == "real"]
    print(f"\nreal 命中共 {len(reals)} 处：")
    for x in reals:
        print(f"  {x['feature']:10s} {x['file']}:{x['line']}  {x['src'][:60]!r}")
        print(f"             fate: {x['fate']}")


if __name__ == "__main__":
    main()
