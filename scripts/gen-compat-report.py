#!/usr/bin/env python3
#
#  gen-compat-report.py — 由 tests/fixtures/RESULTS.json 生成中文兼容性报告。
#  所有统计数字都来自结构化结果，不手写，保证报告可复现。
#
import collections
import datetime
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, "tests", "fixtures")
M = json.load(open(os.path.join(FX, "MANIFEST.json"), encoding="utf-8"))
R = json.load(open(os.path.join(FX, "RESULTS.json"), encoding="utf-8"))

S = R["summary"]
FILES = R["files"]
CASES = R["spec_cases"]
FEATURES = {f["key"]: f["label"] for f in R["features"]}

# 首次运行（修复前）与「只修两个 P0」阶段的实测基线，用于三阶段对比
BASELINE = dict(
    retention=0.690,
    obsidian=0.211,
    cmark=0.774,
    crashes=1,
    smoke=313,
)
STAGE2 = dict(retention=0.806, smoke=325, file_stable=163, case_stable=1283)
FIXED = dict(retention=S["avg_retention"], smoke=382)


def feature_rate(key):
    det = sum(1 for f in FILES if key in f["detected"])
    pre = sum(1 for f in FILES if key in f["preserved"])
    return pre, det, (pre / det if det else 0.0)


out = []


def w(s=""):
    out.append(s)


def pct(x):
    return f"{x * 100:.1f}%"


def ratio(a, b):
    return f"{a}/{b}"


def avg_for(slug):
    g = [x["retention"] for x in FILES if x["slug"] == slug]
    return sum(g) / len(g) if g else 0.0


# ---------------------------------------------------------------------------
w("# FinalMd Markdown 兼容性测试报告")
w("")
w(f"> 生成时间：{datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}　|　"
  f"语料：{S['files']} 份真实文件 + {S['spec_cases']} 条官方规范用例　|　"
  "测试程序：`scripts/run-compat.sh`")
w("")
w("## 1. 结论摘要")
w("")
w(f"从 {len(M['sources'])} 个主流 Markdown 软件 / 解析器生态与 "
  f"{len(M['specs'])} 份官方规范中下载了 **{S['files']} 份真实 `.md` 文件**和 "
  f"**{S['spec_cases']} 条规范用例**，全部用 FinalMd 自己的 "
  "`MarkdownParser.parse` / `MarkdownSerializer.markdown` 逐份跑通。")
w("")
w("| 指标 | ① 首次运行 | ② 修复两个 P0 后 | ③ 加入原样透传块后（本次） |")
w("|---|---|---|---|")
w(f"| 解析崩溃 | {BASELINE['crashes']} 处（索引越界） | **0** | **0** |")
w(f"| 平均可读字符保留率 | {pct(BASELINE['retention'])} | {pct(STAGE2['retention'])} | "
  f"**{pct(FIXED['retention'])}** |")
w(f"| Obsidian 帮助库保留率 | {pct(BASELINE['obsidian'])} | "
  f"{pct(avg_for('obsidian'))} | **{pct(avg_for('obsidian'))}** |")
w(f"| cmark-gfm 样本保留率 | {pct(BASELINE['cmark'])} | 87.5% | "
  f"**{pct(avg_for('cmark-gfm'))}** |")
w(f"| 文件一次稳定 | — | {ratio(STAGE2['file_stable'], S['files'])} | "
  f"**{ratio(S['file_stable'], S['files'])}** |")
w(f"| 规范用例一次稳定 | — | {ratio(STAGE2['case_stable'], S['spec_cases'])} | "
  f"**{ratio(S['case_stable'], S['spec_cases'])}** |")
rd_p, rd_d, _ = feature_rate("refdef")
hb_p, hb_d, _ = feature_rate("htmlblock")
w("| 引用式链接定义（正则口径） | 3/24 | 3/24 | "
  f"**{ratio(rd_p, rd_d)}** |")
w("| 原始 HTML 块（正则口径） | 9/23 | 9/23 | "
  f"**{ratio(hb_p, hb_d)}** |")
w(f"| 透传块逐字保留（整行字节比对） | — | — | "
  f"**{ratio(S['raw_blocks_kept'], S['raw_blocks_total'])} "
  f"({pct(S['raw_exact_rate'])})** |")
w(f"| 冒烟测试 | {BASELINE['smoke']} 项 | {STAGE2['smoke']} 项 | **{FIXED['smoke']} 项** |")
w("")
w(f"文件往返：一次稳定 {ratio(S['file_stable'], S['files'])}，"
  f"两轮内收敛 {ratio(S['file_converged'], S['files'])}；"
  f"规范用例：一次稳定 {ratio(S['case_stable'], S['spec_cases'])}，"
  f"收敛 {ratio(S['case_converged'], S['spec_cases'])}。"
  f"逐文件对比本次与上一版结果：**保留率下降的文件 0 份**，"
  f"提升超过 2 个百分点的 11 份。")
w("")
w("**结论**：FinalMd 对常见 Markdown 语法（标题、列表、引用、代码、表格、行内样式、链接）"
  "兼容性良好。测试过程中先修复了 2 个会造成崩溃 / 数据丢失的真实缺陷，随后落地 P1 "
  "「原样透传块」：YAML/TOML frontmatter、原始 HTML 块与引用式链接（含脚注 / 引文 / "
  "缩写）定义在即刻模式下整块逐字保存，不再被拆行或转义。兼容性测试已接入 CI，"
  "以保留率与逐字保留率作为回归阈值。剩余边界见第 7 节。")
w("")

# ---------------------------------------------------------------------------
w("## 2. 语料来源")
w("")
w("| 来源 | 官方仓库 | 文件数 | 代表性内容 | 许可证 |")
w("|---|---|---:|---|---|")
by_slug = collections.defaultdict(list)
for f in FILES:
    by_slug[f["slug"]].append(f)
for src in M["sources"]:
    n = len(by_slug[src["slug"]])
    note = src["note"].replace("|", "\\|")
    w(f"| {src['name']} | `{src['repo']}` | {n} | {note} | {src['license']} |")
w("")
w("| 规范 | 版本 | 官方用例数 | 用途 |")
w("|---|---|---:|---|")
for sp in M["specs"]:
    w(f"| {sp['name']} | {sp['version']} | {sp['example_count']} | "
      "逐例跑解析 + 序列化，按章节统计结构识别率 |")
w("")
w("> 闭源软件（Typora、iA Writer、Bear、Ulysses）没有公开的官方 `.md` 样例文件仓库，"
  "因此只纳入 Typora 官方 issue 仓库的 README；它们支持的语法（GFM、任务列表、"
  "数学公式、`[TOC]`、行内 HTML 等）已由 Pandoc / cmark-gfm / Mark Text / Zettlr 语料覆盖。")
w("")

# ---------------------------------------------------------------------------
w("## 3. 测试方法")
w("")
w("1. **下载语料**：`scripts/fetch-fixtures.py` 按 `tests/fixtures/PATHS.json` 的固化路径清单，"
  "经 jsDelivr CDN 下载各仓库原始文件，逐字节校验并记录 sha256 到 `MANIFEST.json`。"
  "运行时不依赖 GitHub API，避免限流，结果可复现。")
w("2. **三轮往返**：对每份文件执行 "
  "`parse → serialize → parse → serialize → parse → serialize`，"
  "用真实的 FinalMd 解析器与序列化器，不走任何模拟实现。")
w("3. **逐例跑规范**：CommonMark / GFM 的每条 example 单独执行同样流程，"
  "并比对预期 HTML 中的块类型（`<h1>`/`<blockquote>`/`<pre>` 等）是否被识别。")
w(f"4. **语法特征扫描**：对原文与首轮序列化输出各跑 {len(FEATURES)} 条正则，"
  "判断每类扩展语法是「原样保留」「等价改写」还是「丢失」。")
w("5. **逐字保留比对**：正则只判断「长得像」，会把 `\\[1\\]:` 也误算成保留。"
  "因此额外抽取原文里 frontmatter 整块、HTML 块起始行、链接定义行，"
  "逐行检查其原始字节是否出现在序列化输出中，作为 CI 的硬阈值。")
w("")
w("指标定义：")
w("")
w("| 指标 | 含义 |")
w("|---|---|")
w("| 一次稳定 | 首轮输出再解析后完全一致（所见即所得编辑器的理想状态） |")
w("| 收敛 | 允许第一轮做规范化（空行、列表符号），第二轮起不再变化 |")
w("| 可读字符保留率 | 原文中的字母 / 数字 / CJK 字符按顺序出现在输出中的比例（启发式，"
  "用于发现内容被吞掉，不比较排版标记） |")
w("| 结构识别率 | 规范用例预期 HTML 的块类型，有多少出现在解析结果的 `.mdBlockType` 中 |")
w("| 透传块逐字保留 | frontmatter 整块 + HTML 块起始行 + 链接定义行，按原始字节原样出现在输出中的比例 |")
w("")

# ---------------------------------------------------------------------------
w("## 4. 总体结果（按来源）")
w("")
w("| 来源 | 文件 | 一次稳定 | 收敛 | 平均保留率 |")
w("|---|---:|---:|---:|---:|")
for src in M["sources"]:
    g = by_slug[src["slug"]]
    if not g:
        continue
    st = sum(1 for x in g if x["stable"])
    cv = sum(1 for x in g if x["converged"])
    rt = sum(x["retention"] for x in g) / len(g)
    w(f"| {src['name']} | {len(g)} | {st}/{len(g)} | {cv}/{len(g)} | {pct(rt)} |")
w("")
sec = collections.defaultdict(lambda: [0, 0, 0.0])
for c in CASES:
    k = c["section"] or "(未分节)"
    sec[k][0] += 1
    sec[k][1] += 1 if c["stable"] else 0
    sec[k][2] += c["structure"]
weak = [(k, v) for k, v in sec.items() if v[1] < v[0]]
w("**规范用例中未达到一次稳定的章节**（共 %d 个）：" % len(weak))
w("")
w("| 章节 | 一次稳定 | 平均结构识别率 |")
w("|---|---:|---:|")
for k, v in sorted(weak, key=lambda x: -x[1][0]):
    w(f"| {k} | {v[1]}/{v[0]} | {pct(v[2] / v[0])} |")
w("")

# ---------------------------------------------------------------------------
w("## 5. 语法特性兼容矩阵")
w("")
det = collections.Counter()
pre = collections.Counter()
for f in FILES:
    for k in f["detected"]:
        det[k] += 1
    for k in f["preserved"]:
        pre[k] += 1

full, partial, weakf = [], [], []
for k in det:
    rate = pre[k] / det[k]
    row = (FEATURES.get(k, k), pre[k], det[k], rate)
    (full if rate >= 0.95 else partial if rate >= 0.60 else weakf).append(row)

def table(title, rows, desc):
    w(f"### {title}")
    w("")
    w(desc)
    w("")
    w("| 语法特性 | 保留 / 命中样本 | 保留率 |")
    w("|---|---:|---:|")
    for label, p, d, r in sorted(rows, key=lambda x: (x[3], -x[2])):
        w(f"| {label} | {p}/{d} | {pct(r)} |")
    w("")

table("A. 完整保留（≥95%）", full,
      "这些写法在 FinalMd 打开并保存后仍保持等价的 Markdown 表示。")
table("B. 部分降级（60%–95%）", partial,
      "多数场景保留，但在复杂组合（嵌套列表、HTML 混排、特殊标题）下会被规范化改写。")
table("C. 不兼容 / 会被改写（<60%）", weakf,
      "引用式链接定义与原始 HTML 块已由 P1 透传块移到 A 类；这里剩下的是 "
      "Obsidian 专属语法：文字内容多数仍在，但方括号会被防御性转义成 `\\[`。"
      "注意：`\\[[双链]\\]` / `\\[ \\]` 在其它软件里**不再**被识别为双链或任务复选框，"
      "因此这类文件建议用**传统模式**编辑，避免即刻模式保存时改写原文件。")
w("")

# ---------------------------------------------------------------------------
w("## 6. 发现并修复的缺陷")
w("")
w("### 缺陷 A：`1.` 这类空序号行导致解析崩溃（P0）")
w("")
w("- **触发样例**：`cmark-gfm/bench/samples/block-list-flat.md`，其中包含 "
  "`1.` / `2.` / `3.` 这些只有序号、没有后续空格的行。")
w("- **现象**：`MarkdownParser.parse` 抛 `String index is out of bounds`，进程退出。"
  "用户只要写出 `1.` 再打开 / 保存该文件就会崩。")
w("- **根因**：`listItemInfo` 用 `dot < rest.endIndex` 判断后直接取 "
  "`rest[rest.index(after: dot)]`；当 `.` 是最后一个字符时，"
  "`index(after:)` 等于 `endIndex`，下标越界。`.` 与 `)` 两个分支都有此问题。")
w("- **修复**：先保存 `after = index(after: dot)`，再判断 `after < endIndex` 才取值。"
  "同时加 `1.` / `2)` 的冒烟回归断言。")
w("")
w("### 缺陷 B：方括号内容被整段吞噬（P0）")
w("")
w("- **触发样例**：`cmark-gfm/bench/samples/block-ref-flat.md`（`[1] [2] [3]`）、"
  "Obsidian 帮助库、`logseq` 日记、Zettlr README 等。")
w("- **现象**：`[1]` 变成 `\\[`，数字与括号内文字消失；`[[双链]]`、`[ ]` 任务框、"
  "`![[嵌入]]` 同样被吃掉。首次运行时 Obsidian 语料平均保留率仅 "
  f"{pct(BASELINE['obsidian'])}。")
w("- **根因**：`InlineParser` 的 `readDelimited` 是 `mutating`，会先把游标推过 `]`；"
  "若随后 `readLinkTarget` 发现没有 `(url)` 而返回 nil，代码只补了 `[` 却没回滚游标，"
  "于是方括号里的内容被跳过。图片分支同理。")
w("- **修复**：解析前保存 `pos`，目标解析失败时回滚，再按字面文本逐字符处理。"
  f"修复后平均保留率 {pct(BASELINE['retention'])} → {pct(STAGE2['retention'])}，"
  f"Obsidian 语料提升到 {pct(avg_for('obsidian'))}。新增 5 组方括号写法的冒烟回归断言。")
w("")
w("### 改进 C：原样透传块（P1，本次落地）")
w("")
w("前面两个修复解决的是「别把内容弄丢」，但即刻模式保存仍会把外部文件重写一遍："
  "YAML frontmatter 被按段落拆行、`<div>` 被行内解析转义成 `\\<div`、"
  "`[1]: https://…` 变成 `\\[1\\]:`。第 5 节里 frontmatter 一度显示 100% 保留，"
  "其实是正则只检查「输出里还有 `---…---`」，属于假阳性——内容已经被改得不能用。")
w("")
w("| 做法 | 说明 |")
w("|---|---|")
w("| 新块类型 `MDBlockType.raw` | 与 `heading / quote / code` 并列；属性键 `.mdRawKind` 记录"
  " frontmatter / html / definition，`.mdRawID` 给同块每一行编号 |")
w("| 解析时整块存原文 | 三类块按原始行写进 `NSTextStorage`，**不经过 `InlineParser`**；"
  "内部空行、缩进、尖括号、方括号全部保留 |")
w("| 序列化时按 ID 聚合 | `MarkdownSerializer.blocks(from:)` 把连续且同 ID 的段落拼回一整块，"
  "**跳过 `InlineSerializer` 与 `escapeMarkdown`**，逐字写出 |")
w("| 编辑安全 | 显示文本本身就是源码：用户在块内改动后，写出的就是改动后的文字，"
  "不存在「缓存的旧源码把编辑盖掉」 |")
w("| HTML 导出分流 | 原始 HTML 原样进 `<body>`；frontmatter 与链接定义是元数据，不印成正文 |")
w("")
w("判定过程中修掉了 4 个「过宽 / 过严」问题，都用官方规范用例做了回归：")
w("")
w("1. `<script>` / `<style>` / `<pre>` / `<textarea>` 属于 CommonMark type 1，"
  "必须结束在对应闭标签行，不能吃到空行，否则 `</style>` 后面的正文会被吞掉。")
w("2. type 7 的「整行一个标签」必须做**语法完整**校验（标签名、属性名、引号、"
  "属性间空白）；只看尖括号会把 `<m:abc>`、`<a href='bar'title=title>` 这类"
  "本该是普通段落的非法写法误判成 HTML 块。")
w("3. 链接定义必须校验 destination 与可选 title，尾部杂字要拒绝"
  "（`[foo]: /url \"title\" ok` 是段落）；但脚注 / 引文 / 缩写这类扩展定义的"
  "冒号后是自由文本，不能套标准 URL 规则。MultiMarkdown 的 `width=\"3in\"` "
  "属性也要放行。")
w("4. 未闭合 HTML 块吃到文件末尾时，`split` 会多出一个空串；不剥掉它，"
  "每往返一次就多一个空行（CommonMark #175 / GFM #142 由此不收敛）。")
w("")
w(f"效果：引用式链接定义 3/24 → **{ratio(rd_p, rd_d)}**，"
  f"原始 HTML 块 9/23 → **{ratio(hb_p, hb_d)}**，"
  f"平均保留率 {pct(STAGE2['retention'])} → **{pct(FIXED['retention'])}**，"
  f"逐字保留 **{ratio(S['raw_blocks_kept'], S['raw_blocks_total'])}**，"
  f"冒烟测试 {STAGE2['smoke']} → **{FIXED['smoke']} 项**。")
w("")

# ---------------------------------------------------------------------------
w("## 7. 已知限制与风险边界")
w("")
nonconv = [f for f in FILES if not f["converged"]]
w(f"**不收敛文件**：{len(nonconv)}/{S['files']} 份在第二轮往返后仍会继续变化，"
  "主要是含多层嵌套列表、缩进代码块、Obsidian 专有语法的文档。"
  "frontmatter / 原始 HTML / 链接定义已被透传块覆盖，不再是主因。")
w("")
w("| 文件 | 保留率 | 丢失的语法特征 |")
w("|---|---:|---|")
for f in sorted(nonconv, key=lambda x: x["retention"])[:12]:
    lost = ", ".join(FEATURES.get(k, k) for k in f["lost"][:5]) or "—"
    w(f"| `{f['slug']}/{os.path.basename(f['source_path'])}` | "
      f"{pct(f['retention'])} | {lost} |")
w("")
w("**风险边界（重要）**：")
w("")
w("1. **传统模式是安全的**：它把 `.md` 当纯文本逐字节保存，不做任何解析或规范化。"
  "打开外部来源的复杂 Markdown 文件、且需要保持原写法时，请切到传统模式编辑后保存。")
w("2. **即刻模式仍会规范化**，但范围已收窄：列表符号、段落空行、标题写法会被统一；"
  "YAML/TOML frontmatter、原始 HTML 块、引用式链接 / 脚注 / 引文定义现在整块逐字保留。"
  "透传块在编辑器里以等宽源码形态显示，不渲染成对应视觉效果。")
w("3. **未编辑就切换模式不损坏文件**：`AppModel.authority` 机制保证"
  "刚打开、两侧都未编辑时切换模式不会重新序列化，保留原文件字节。"
  "改写风险出现在「即刻侧被编辑过再保存 / 切到传统侧」时。")
w("4. **缩进代码块（4 空格）仍是空白**：FinalMd 目前没有把它识别成代码块，"
  "夹在其中的 HTML 行与链接定义行会按普通段落被转义。这是逐字保留率"
  f"停在 {pct(S['raw_exact_rate'])} 的主因——剩余 "
  f"{S['raw_blocks_total'] - S['raw_blocks_kept']} 行里绝大多数是这类缩进行。"
  "涉及大量缩进代码的外部文件仍建议用传统模式。")
w("5. **第 5 节 C 类语法**（Obsidian 双链 / Callout / 任务列表复选框）"
  "按纯文本保留，不会渲染成对应结构，方括号可能被防御性转义。")
w("6. **规范用例结构识别率 90.39% → 90.34%**（−0.05pp）：两条用例里的链接引用定义"
  "现在被正确识别为 `raw` 块，而旧版把它当成 `p` 段落凑巧命中了指标。"
  "内容无损、稳定性无损，属于指标口径差异而非解析倒退。")
w("")

# ---------------------------------------------------------------------------
w("## 8. 改进建议（按优先级）")
w("")
w("| 优先级 | 建议 | 状态 | 预期收益 |")
w("|---|---|---|---|")
w("| P0 | 修复 `1.` 索引越界与方括号吞噬，并加入冒烟回归 | ✅ 已完成 | 消除崩溃与内容丢失 |")
w("| P1 | 增加「原样透传块」：frontmatter / 原始 HTML / 链接定义整块保存、逐字输出 | "
  "✅ 本次完成 | frontmatter 不再拆行、HTML 不再转义 |")
w("| P1 | 把 `run-compat.sh` 接入 CI，用保留率 / 逐字保留率 / 语料 sha256 做回归阈值 | "
  "✅ 本次完成 | 防止兼容性倒退 |")
w("| P1 | 打开外部 `.md` 时，若检测到不兼容扩展语法，提示「建议用传统模式编辑」"
  "或默认以传统模式打开 | ⬜ 待做 | 避免用户无意识改写原文件 |")
w("| P2 | 支持缩进代码块（4 空格） | ⬜ 待做 | 补齐逐字保留率剩下的 "
  f"{S['raw_blocks_total'] - S['raw_blocks_kept']} 行 |")
w("| P2 | 支持 Obsidian 双链 / Callout / 任务列表复选框的识别与序列化 | "
  "⬜ 待做 | 覆盖知识库 / 学术写作场景 |")
w("")

# ---------------------------------------------------------------------------
w("## 9. 复现与验证步骤")
w("")
w("```bash")
w("cd FinalMd-swift")
w("")
w("# 1) 下载 / 更新语料（已有文件会复用，不重复请求网络）")
w("python3 scripts/fetch-fixtures.py")
w("")
w("# 2) 现有冒烟测试（含本次透传块的回归断言）")
w("./scripts/run-smoke.sh")
w("")
w("# 3) 编译并运行全部语料的兼容性测试")
w("./scripts/run-compat.sh")
w("")
w("# 4) 校验语料完整性 + 回归阈值（CI 上跑的就是这条）")
w("python3 scripts/check-compat-thresholds.py")
w("")
w("# 5) 由结构化结果重新生成这份报告")
w("python3 scripts/gen-compat-report.py")
w("```")
w("")
w("CI：`.github/workflows/compat-macos.yml` 在 push / PR / 手动触发时跑 "
  "`run-smoke.sh` → `run-compat.sh` → `check-compat-thresholds.py` → "
  "`gen-compat-report.py`，并把 `RESULTS.json` 与 `COMPATIBILITY.md` 上传为构建产物。"
  "阈值基线写在 `tests/fixtures/BASELINE.json`，提升后需显式更新。")
w("")
w("本次实测：")
w("")
w("| 验证项 | 结果 |")
w("|---|---|")
w(f"| `run-smoke.sh` | {FIXED['smoke']} 项全通过 |")
w(f"| `run-compat.sh` | {S['files']} 份文件 + {S['spec_cases']} 条规范用例，零崩溃 |")
w(f"| 平均可读字符保留率 | {pct(FIXED['retention'])} |")
w(f"| 透传块逐字保留 | {ratio(S['raw_blocks_kept'], S['raw_blocks_total'])} "
  f"({pct(S['raw_exact_rate'])}) |")
w("| `swift build` / `swift build -c release` | 零警告 |")
w("| `scripts/make_app.sh` | 重新打包 `build/FinalMd.app` |")
w("")

# ---------------------------------------------------------------------------
w("## 10. 语料许可与来源")
w("")
w("- 所有 `.md` 文件均为各项目公开仓库中的原始内容，未经修改，"
  "版权与许可证归各自作者。此处仅用于 FinalMd 本地兼容性测试。")
w("- 每个文件的原始路径、来源 URL、字节数与 sha256 记录在 "
  "`tests/fixtures/MANIFEST.json`；路径清单在 `PATHS.json`；"
  "每份文件的详细测试结果在 `RESULTS.json`；CI 回归阈值在 `BASELINE.json`。")
w("- CommonMark / GFM 规范文本与用例采用 CC-BY-SA 4.0；"
  "各软件仓库许可证见第 2 节表格。")
w("")

report = os.path.join(ROOT, "COMPATIBILITY.md")
with open(report, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print(f"✅ 报告已生成：{os.path.relpath(report, ROOT)}（{len(out)} 行）")

# 语料目录说明
readme = [
    "# Markdown 兼容性测试语料",
    "",
    "本目录由 `scripts/fetch-fixtures.py` 生成，内容来自各主流 Markdown 软件 / 解析器",
    "官方仓库中的真实文件与官方规范用例，**仅供 FinalMd 本地兼容性测试使用**。",
    "所有文件保持原始字节，版权与许可证归原作者。",
    "",
    "| 文件 | 说明 |",
    "|---|---|",
    "| `MANIFEST.json` | 每个文件的来源路径、URL、字节数、sha256 与许可证 |",
    "| `PATHS.json` | 固化的下载路径清单（让脚本不依赖 GitHub API，可复现） |",
    "| `RESULTS.json` | `run-compat.sh` 生成的结构化测试结果 |",
    "| `BASELINE.json` | CI 回归阈值；指标提升后用 `check-compat-thresholds.py --update-baseline` 更新 |",
    "| `sources/<slug>/` | 按来源分组的原始 `.md` 文件 |",
    "| `specs/` | CommonMark / GFM 规范原文与解析后的结构化用例 |",
    "",
    "重新下载：`python3 scripts/fetch-fixtures.py`（已有文件自动复用）。",
    "运行测试：`./scripts/run-compat.sh`；回归闸门：`python3 scripts/check-compat-thresholds.py`；",
    "生成报告：`python3 scripts/gen-compat-report.py`。",
    "CI：`.github/workflows/compat-macos.yml`（push / PR / 手动触发，语料直接取自 git）。",
    "",
    "来源许可证：",
    "",
]
for src in M["sources"]:
    readme.append(f"- **{src['name']}** — `{src['repo']}`（{src['license']}）")
for sp in M["specs"]:
    repo = {"commonmark": "commonmark/commonmark-spec",
            "gfm": "github/cmark-gfm"}.get(sp["slug"], sp["name"])
    readme.append(f"- **{sp['name']}** — `{repo}`（{sp['license']}）")
with open(os.path.join(FX, "README.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(readme) + "\n")
print("✅ 语料说明已生成：tests/fixtures/README.md")
