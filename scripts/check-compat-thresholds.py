#!/usr/bin/env python3
#
#  check-compat-thresholds.py — 兼容性回归闸门（本地 / CI 通用）
#
#  三道检查：
#   1. 语料完整性：MANIFEST.json 里每个文件的存在性、字节数、sha256；规范用例文件与条数。
#      CI 上语料直接来自仓库，不联网；这一步防止语料被误改后「用坏样本测出好结果」。
#   2. 绝对阈值：tests/fixtures/BASELINE.json 里的保留率 / 稳定率 / 收敛数下限。
#   3. 逐文件回归：与上一版 RESULTS.json（CI 里由 git show HEAD 取）对比，
#      任何一份文件保留率下降、或失去「一次稳定 / 收敛」状态，都判失败。
#
#  环境变量：
#    FINALMD_BASELINE_RESULTS  上一版 RESULTS.json 路径；不设置则跳过第 3 步。
#  用法：
#    python3 scripts/check-compat-thresholds.py
#    python3 scripts/check-compat-thresholds.py --update-baseline   # 指标提升后抬高基线
#
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, "tests", "fixtures")
BASELINE_PATH = os.path.join(FX, "BASELINE.json")
RESULTS_PATH = os.path.join(FX, "RESULTS.json")

errors = []
lines = []


def w(s=""):
    print(s)
    lines.append(s)


def fail(msg):
    errors.append(msg)
    w(f"❌ {msg}")


def ok(msg):
    w(f"✓ {msg}")


def load(path, label):
    if not os.path.isfile(path):
        fail(f"缺少{label}：{path}")
        return None
    try:
        return json.load(open(path, encoding="utf-8"))
    except (ValueError, OSError) as e:
        fail(f"{label}无法解析：{e}")
        return None


M = load(os.path.join(FX, "MANIFEST.json"), "语料清单 MANIFEST.json")
R = load(RESULTS_PATH, "测试结果 RESULTS.json")
B = load(BASELINE_PATH, "阈值基线 BASELINE.json")
if not M or not R or not B:
    sys.exit(1)

if "--update-baseline" in sys.argv:
    s = R["summary"]
    B["thresholds"] = {
        "files": s["files"],
        "spec_cases": s["spec_cases"],
        "avg_retention": round(s["avg_retention"], 3),
        "raw_exact_rate": round(s["raw_exact_rate"], 3),
        "file_stable": s["file_stable"],
        "file_converged": s["file_converged"],
        "case_stable": s["case_stable"],
        "case_converged": s["case_converged"],
    }
    with open(BASELINE_PATH, "w", encoding="utf-8") as f:
        json.dump(B, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"✅ 已更新基线：{os.path.relpath(BASELINE_PATH, ROOT)}")
    print(json.dumps(B["thresholds"], ensure_ascii=False, indent=2))
    sys.exit(0)

w("## 1. 语料完整性")
missing = 0
for f in M["files"]:
    p = os.path.join(ROOT, f["local_path"])
    if not os.path.isfile(p):
        missing += 1
        if missing <= 3:
            fail(f"语料缺失：{f['local_path']}")
        continue
    with open(p, "rb") as fh:
        data = fh.read()
    if len(data) != f["bytes"]:
        fail(f"语料字节数不符：{f['local_path']}（{len(data)} ≠ {f['bytes']}）")
    if hashlib.sha256(data).hexdigest() != f["sha256"]:
        fail(f"语料 sha256 不符：{f['local_path']}")
if missing > 3:
    fail(f"另有 {missing - 3} 份语料缺失")
if missing == 0:
    ok(f"{len(M['files'])} 份语料：字节数与 sha256 全部一致")

for sp in M["specs"]:
    for key in ("spec_file", "cases_file"):
        if not os.path.isfile(os.path.join(ROOT, sp[key])):
            fail(f"规范文件缺失：{sp[key]}")
    cases = os.path.join(ROOT, sp["cases_file"])
    if os.path.isfile(cases):
        try:
            n = len(json.load(open(cases, encoding="utf-8"))["examples"])
            if n != sp["example_count"]:
                fail(f"{sp['slug']} 用例条数不符：{n} ≠ {sp['example_count']}")
            else:
                ok(f"{sp['slug']}：{n} 条官方用例")
        except (ValueError, KeyError, OSError) as e:
            fail(f"{sp['slug']} 用例文件无法解析：{e}")
w("")

w("## 2. 绝对阈值")
S = R["summary"]
T = B["thresholds"]
exact = {"files", "spec_cases"}
for key, minimum in T.items():
    if key not in S:
        fail(f"RESULTS.json 缺少指标 {key}（测试程序版本过旧？）")
        continue
    actual = S[key]
    if key in exact:
        if actual == minimum:
            ok(f"{key} = {actual}")
        else:
            fail(f"{key} 应为 {minimum}，实际 {actual}（语料集被改动？）")
    elif actual >= minimum:
        shown = f"{actual:.4f}" if isinstance(actual, float) else str(actual)
        ok(f"{key} = {shown}（下限 {minimum}）")
    else:
        fail(f"{key} 低于阈值：{actual} < {minimum}")
w("")

w("## 3. 与上一版逐文件对比")
prev_path = os.environ.get("FINALMD_BASELINE_RESULTS", "")
if not prev_path:
    w("⚠️ 未提供 FINALMD_BASELINE_RESULTS，跳过（CI 会由 git show HEAD 提供）")
else:
    prev = load(prev_path, "上一版结果")
    if prev:
        old = {f["local_path"]: f for f in prev.get("files", [])}
        drops, lost_stable, lost_conv, new_files = [], [], [], []
        for f in R["files"]:
            b = old.get(f["local_path"])
            if not b:
                new_files.append(f["local_path"])
                continue
            delta = f["retention"] - b["retention"]
            if delta < -B["max_retention_drop_per_file"]:
                drops.append((f["local_path"], delta))
            if b.get("stable") and not f["stable"]:
                lost_stable.append(f["local_path"])
            if b.get("converged") and not f["converged"]:
                lost_conv.append(f["local_path"])
        for p, d in drops[:8]:
            fail(f"保留率倒退 {d:+.3f}：{p}")
        if len(drops) > 8:
            fail(f"另有 {len(drops) - 8} 份文件保留率倒退")
        for p in lost_stable[:8]:
            fail(f"失去「一次稳定」：{p}")
        for p in lost_conv[:8]:
            fail(f"失去「收敛」：{p}")
        if not (drops or lost_stable or lost_conv):
            ok(f"对比 {len(old)} 份基线文件：0 份保留率倒退、0 份稳定性倒退")
        if new_files:
            w(f"  · 新增语料 {len(new_files)} 份（无基线可比）")
w("")

w("## 结果")
w(f"- 文件 {S['files']} 份：一次稳定 {S['file_stable']} / 收敛 {S['file_converged']}")
w(f"- 规范用例 {S['spec_cases']} 条：一次稳定 {S['case_stable']} / 收敛 {S['case_converged']}")
w(f"- 平均可读字符保留率 {S['avg_retention'] * 100:.1f}%")
w(f"- 透传块逐字保留 {S['raw_blocks_kept']}/{S['raw_blocks_total']} "
  f"（{S['raw_exact_rate'] * 100:.1f}%）")

summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if summary_path:
    with open(summary_path, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

if errors:
    print(f"\n❌ 兼容性回归检查失败：{len(errors)} 项")
    sys.exit(1)
print("\n✅ 兼容性回归检查全部通过")
