# FinalMd Markdown 兼容性测试报告

> 生成时间：2026-11-24 21:40　|　语料：207 份真实文件 + 1327 条官方规范用例　|　测试程序：`scripts/run-compat.sh`

## 1. 结论摘要

从 14 个主流 Markdown 软件 / 解析器生态与 2 份官方规范中下载了 **207 份真实 `.md` 文件**和 **1327 条规范用例**，全部用 FinalMd 自己的 `MarkdownParser.parse` / `MarkdownSerializer.markdown` 逐份跑通。

| 指标 | ① 首次运行 | ② 修复两个 P0 后 | ③ 原样透传块 + CI | ④ 本次：Obsidian 语法 |
|---|---|---|---|---|
| 解析崩溃 | 1 处（索引越界） | **0** | **0** | **0** |
| 平均可读字符保留率 | 69.0% | 80.6% | 83.0% | **83.0%** |
| Obsidian 帮助库保留率 | 21.1% | 86.1% | 86.1% | **86.1%** |
| cmark-gfm 样本保留率 | 77.4% | 87.5% | 89.3% | **89.3%** |
| 文件一次稳定 | — | 163/207 | 166/207 | **183/207** |
| 文件两轮内收敛 | — | — | 171/207 | **195/207** |
| 规范用例一次稳定 | — | 1283/1327 | 1285/1327 | **1301/1327** |
| 规范用例两轮内收敛 | — | — | 1307/1327 | **1323/1327** |
| 引用式链接定义（正则口径） | 3/24 | 3/24 | 24/24 | **24/24** |
| 原始 HTML 块（正则口径） | 9/23 | 9/23 | 23/23 | **23/23** |
| Obsidian 双链 / 嵌入 / Callout / 任务框 | 4/30 / 2/7 / 1/12 / 2/9 | 4/30 / 2/7 / 1/12 / 2/9 | 4/30 / 2/7 / 1/12 / 2/9 | **30/30 / 7/7 / 12/12 / 9/9** |
| 透传块逐字保留（整行字节比对） | — | — | 227/262 | **227/262 (86.6%)** |
| 冒烟测试 | 313 项 | 325 项 | 382 项 | **452 项** |

文件往返：一次稳定 183/207，两轮内收敛 195/207；规范用例：一次稳定 1301/1327，收敛 1323/1327。逐文件、逐用例对比本次与上一版结果：**保留率下降 0 份、失去稳定 0 份、新增不收敛 0 份**；文件一次稳定 166 → 183，规范用例一次稳定 1285 → 1301。

**结论**：FinalMd 对常见 Markdown 语法（标题、列表、引用、代码、表格、行内样式、链接）兼容性良好。四个阶段依次修复了 2 个会造成崩溃 / 数据丢失的真实缺陷、落地 P1 「原样透传块」（YAML/TOML frontmatter、原始 HTML 块、引用式链接定义逐字保存）、把兼容性测试接入 CI，本次再补齐 Obsidian 双链 / 嵌入 / Callout 与任务列表复选框的识别与逐字序列化。语法特征矩阵中 **C 类（<60%）已清零**。剩余边界见第 7 节。

## 2. 语料来源

| 来源 | 官方仓库 | 文件数 | 代表性内容 | 许可证 |
|---|---|---:|---|---|
| Obsidian | `obsidianmd/obsidian-help` | 13 | 官方帮助库中的真实笔记文件，含 wikilink / callout / properties / embed | CC BY-NC-SA 4.0 (Obsidian Help) |
| Typora | `typora/typora-issues` | 1 | 闭源软件，官方仅有 issue 仓库；语法覆盖由 GFM / Pandoc 语料补齐 | Repo content (Typora) |
| Mark Text | `marktext/marktext` | 18 | 官方 e2e / unit 测试用的真实 Markdown 文件 | MIT |
| Zettlr | `Zettlr/Zettlr` | 10 | GUI 测试文档：YAML frontmatter、脚注、链接解析、排序等学术写作场景 | GPL-3.0 |
| Joplin | `laurent22/joplin` | 11 | Evernote 导入转换测试用的 Markdown 文件 + 大体积 README | MIT |
| StackEdit | `benweet/stackedit` | 3 | 应用内置的示例文档（新建文件默认内容） | MIT |
| MacDown | `MacDownApp/macdown` | 2 | 官方 demo.md 与 README | MIT |
| Logseq | `logseq/logseq` | 26 | 图谱解析器导出测试用的真实日记笔记（大纲式 Markdown） | MIT |
| VS Code | `microsoft/vscode` | 6 | markdown-language-features 扩展的测试工作区与仓库文档 | MIT |
| Quarto | `quarto-dev/quarto-web` | 8 | 技术写作 .qmd：YAML、代码单元格、callout、交叉引用 | MIT |
| Pandoc | `jgm/pandoc` | 30 | 官方 reader 测试语料（最全的 Markdown 扩展语法覆盖）+ 基准长文 | GPL-2.0-or-later |
| MultiMarkdown 6 | `fletcher/MultiMarkdown-6` | 29 | MMD6 官方语法测试集（.text） | MIT |
| kramdown | `gettalong/kramdown` | 25 | Ruby 解析器官方 testcases | MIT |
| GitHub / cmark-gfm | `github/cmark-gfm` | 25 | GFM 参考实现的基准样本文件 | BSD-2-Clause |

| 规范 | 版本 | 官方用例数 | 用途 |
|---|---|---:|---|
| CommonMark 0.31.2 | 0.31.2 | 655 | 逐例跑解析 + 序列化，按章节统计结构识别率 |
| GFM 0.29 | 0.29 | 672 | 逐例跑解析 + 序列化，按章节统计结构识别率 |

> 闭源软件（Typora、iA Writer、Bear、Ulysses）没有公开的官方 `.md` 样例文件仓库，因此只纳入 Typora 官方 issue 仓库的 README；它们支持的语法（GFM、任务列表、数学公式、`[TOC]`、行内 HTML 等）已由 Pandoc / cmark-gfm / Mark Text / Zettlr 语料覆盖。

## 3. 测试方法

1. **下载语料**：`scripts/fetch-fixtures.py` 按 `tests/fixtures/PATHS.json` 的固化路径清单，经 jsDelivr CDN 下载各仓库原始文件，逐字节校验并记录 sha256 到 `MANIFEST.json`。运行时不依赖 GitHub API，避免限流，结果可复现。
2. **三轮往返**：对每份文件执行 `parse → serialize → parse → serialize → parse → serialize`，用真实的 FinalMd 解析器与序列化器，不走任何模拟实现。
3. **逐例跑规范**：CommonMark / GFM 的每条 example 单独执行同样流程，并比对预期 HTML 中的块类型（`<h1>`/`<blockquote>`/`<pre>` 等）是否被识别。
4. **语法特征扫描**：对原文与首轮序列化输出各跑 33 条正则，判断每类扩展语法是「原样保留」「等价改写」还是「丢失」。
5. **逐字保留比对**：正则只判断「长得像」，会把 `\[1\]:` 也误算成保留。因此额外抽取原文里 frontmatter 整块、HTML 块起始行、链接定义行，逐行检查其原始字节是否出现在序列化输出中，作为 CI 的硬阈值。
6. **扩展语法硬约束**：Obsidian 双链 / 嵌入 / Callout / 任务框按语法特征分别计数，要求命中样本 100% 在输出里保留等价写法；这些语法字符占比很小，单看整体保留率发现不了倒退。

指标定义：

| 指标 | 含义 |
|---|---|
| 一次稳定 | 首轮输出再解析后完全一致（所见即所得编辑器的理想状态） |
| 收敛 | 允许第一轮做规范化（空行、列表符号），第二轮起不再变化 |
| 可读字符保留率 | 原文中的字母 / 数字 / CJK 字符按顺序出现在输出中的比例（启发式，用于发现内容被吞掉，不比较排版标记） |
| 结构识别率 | 规范用例预期 HTML 的块类型，有多少出现在解析结果的 `.mdBlockType` 中 |
| 透传块逐字保留 | frontmatter 整块 + HTML 块起始行 + 链接定义行，按原始字节原样出现在输出中的比例 |

## 4. 总体结果（按来源）

| 来源 | 文件 | 一次稳定 | 收敛 | 平均保留率 |
|---|---:|---:|---:|---:|
| Obsidian | 13 | 10/13 | 13/13 | 86.1% |
| Typora | 1 | 1/1 | 1/1 | 100.0% |
| Mark Text | 18 | 16/18 | 17/18 | 84.1% |
| Zettlr | 10 | 10/10 | 10/10 | 91.0% |
| Joplin | 11 | 10/11 | 10/11 | 89.3% |
| StackEdit | 3 | 3/3 | 3/3 | 81.6% |
| MacDown | 2 | 2/2 | 2/2 | 100.0% |
| Logseq | 26 | 26/26 | 26/26 | 56.1% |
| VS Code | 6 | 6/6 | 6/6 | 90.1% |
| Quarto | 8 | 4/8 | 7/8 | 52.5% |
| Pandoc | 30 | 29/30 | 29/30 | 93.8% |
| MultiMarkdown 6 | 29 | 24/29 | 26/29 | 86.4% |
| kramdown | 25 | 22/25 | 23/25 | 85.5% |
| GitHub / cmark-gfm | 25 | 20/25 | 22/25 | 89.3% |

**规范用例中未达到一次稳定的章节**（共 2 个）：

| 章节 | 一次稳定 | 平均结构识别率 |
|---|---:|---:|
| Inlines | 675/693 | 99.4% |
| Leaf blocks | 372/380 | 81.8% |

## 5. 语法特性兼容矩阵

### A. 完整保留（≥95%）

这些写法在 FinalMd 打开并保存后仍保持等价的 Markdown 表示。

| 语法特性 | 保留 / 命中样本 | 保留率 |
|---|---:|---:|
| 表格 | 21/22 | 95.5% |
| 粗体 | 47/49 | 95.9% |
| 无序列表 | 90/93 | 96.8% |
| Setext 标题 | 35/36 | 97.2% |
| ATX 标题 | 86/86 | 100.0% |
| 围栏代码块 | 70/70 | 100.0% |
| 行内链接 | 58/58 | 100.0% |
| 行内代码 | 55/55 | 100.0% |
| 分割线 | 47/47 | 100.0% |
| 引用块 | 34/34 | 100.0% |
| Obsidian 双链 [[]] | 30/30 | 100.0% |
| 引用式链接定义 | 24/24 | 100.0% |
| YAML frontmatter | 24/24 | 100.0% |
| 原始 HTML 块 | 23/23 | 100.0% |
| 有序列表 | 22/22 | 100.0% |
| 脚注 | 13/13 | 100.0% |
| Obsidian Callout | 12/12 | 100.0% |
| HTML 注释 | 11/11 | 100.0% |
| 任务列表复选框 | 9/9 | 100.0% |
| 删除线 | 9/9 | 100.0% |
| 高亮 == == | 7/7 | 100.0% |
| Obsidian 嵌入 ![[]] | 7/7 | 100.0% |
| Quarto 代码单元格 | 3/3 | 100.0% |
| 中日韩文字 | 1/1 | 100.0% |

### B. 部分降级（60%–95%）

多数场景保留，但在复杂组合（嵌套列表、HTML 混排、特殊标题）下会被规范化改写。

| 语法特性 | 保留 / 命中样本 | 保留率 |
|---|---:|---:|
| CriticMarkup | 21/33 | 63.6% |
| Mermaid / 图表围栏 | 2/3 | 66.7% |
| 井号标签 | 16/20 | 80.0% |
| 尖括号自动链接 | 10/12 | 83.3% |
| 图片 | 27/31 | 87.1% |
| 行内 HTML | 18/20 | 90.0% |
| 数学公式块 $$ | 9/10 | 90.0% |
| 缩进代码块 | 52/57 | 91.2% |

### C. 不兼容 / 会被改写（<60%）

前两个阶段分别由 P0 缺陷修复（方括号吞噬）与 P1 原样透传块（引用式链接定义、原始 HTML 块）清零一部分；本次补齐 Obsidian 双链 / 嵌入 / Callout / 任务框后，**该档已无残留语法**。

（本次测试没有落入该档的语法特性。）


## 6. 发现并修复的缺陷

### 缺陷 A：`1.` 这类空序号行导致解析崩溃（P0）

- **触发样例**：`cmark-gfm/bench/samples/block-list-flat.md`，其中包含 `1.` / `2.` / `3.` 这些只有序号、没有后续空格的行。
- **现象**：`MarkdownParser.parse` 抛 `String index is out of bounds`，进程退出。用户只要写出 `1.` 再打开 / 保存该文件就会崩。
- **根因**：`listItemInfo` 用 `dot < rest.endIndex` 判断后直接取 `rest[rest.index(after: dot)]`；当 `.` 是最后一个字符时，`index(after:)` 等于 `endIndex`，下标越界。`.` 与 `)` 两个分支都有此问题。
- **修复**：先保存 `after = index(after: dot)`，再判断 `after < endIndex` 才取值。同时加 `1.` / `2)` 的冒烟回归断言。

### 缺陷 B：方括号内容被整段吞噬（P0）

- **触发样例**：`cmark-gfm/bench/samples/block-ref-flat.md`（`[1] [2] [3]`）、Obsidian 帮助库、`logseq` 日记、Zettlr README 等。
- **现象**：`[1]` 变成 `\[`，数字与括号内文字消失；`[[双链]]`、`[ ]` 任务框、`![[嵌入]]` 同样被吃掉。首次运行时 Obsidian 语料平均保留率仅 21.1%。
- **根因**：`InlineParser` 的 `readDelimited` 是 `mutating`，会先把游标推过 `]`；若随后 `readLinkTarget` 发现没有 `(url)` 而返回 nil，代码只补了 `[` 却没回滚游标，于是方括号里的内容被跳过。图片分支同理。
- **修复**：解析前保存 `pos`，目标解析失败时回滚，再按字面文本逐字符处理。修复后平均保留率 69.0% → 80.6%，Obsidian 语料提升到 86.1%。新增 5 组方括号写法的冒烟回归断言。

### 改进 C：原样透传块（P1，第三阶段落地）

前面两个修复解决的是「别把内容弄丢」，但即刻模式保存仍会把外部文件重写一遍：YAML frontmatter 被按段落拆行、`<div>` 被行内解析转义成 `\<div`、`[1]: https://…` 变成 `\[1\]:`。第 5 节里 frontmatter 一度显示 100% 保留，其实是正则只检查「输出里还有 `---…---`」，属于假阳性——内容已经被改得不能用。

| 做法 | 说明 |
|---|---|
| 新块类型 `MDBlockType.raw` | 与 `heading / quote / code` 并列；属性键 `.mdRawKind` 记录 frontmatter / html / definition，`.mdRawID` 给同块每一行编号 |
| 解析时整块存原文 | 三类块按原始行写进 `NSTextStorage`，**不经过 `InlineParser`**；内部空行、缩进、尖括号、方括号全部保留 |
| 序列化时按 ID 聚合 | `MarkdownSerializer.blocks(from:)` 把连续且同 ID 的段落拼回一整块，**跳过 `InlineSerializer` 与 `escapeMarkdown`**，逐字写出 |
| 编辑安全 | 显示文本本身就是源码：用户在块内改动后，写出的就是改动后的文字，不存在「缓存的旧源码把编辑盖掉」 |
| HTML 导出分流 | 原始 HTML 原样进 `<body>`；frontmatter 与链接定义是元数据，不印成正文 |

判定过程中修掉了 4 个「过宽 / 过严」问题，都用官方规范用例做了回归：

1. `<script>` / `<style>` / `<pre>` / `<textarea>` 属于 CommonMark type 1，必须结束在对应闭标签行，不能吃到空行，否则 `</style>` 后面的正文会被吞掉。
2. type 7 的「整行一个标签」必须做**语法完整**校验（标签名、属性名、引号、属性间空白）；只看尖括号会把 `<m:abc>`、`<a href='bar'title=title>` 这类本该是普通段落的非法写法误判成 HTML 块。
3. 链接定义必须校验 destination 与可选 title，尾部杂字要拒绝（`[foo]: /url "title" ok` 是段落）；但脚注 / 引文 / 缩写这类扩展定义的冒号后是自由文本，不能套标准 URL 规则。MultiMarkdown 的 `width="3in"` 属性也要放行。
4. 未闭合 HTML 块吃到文件末尾时，`split` 会多出一个空串；不剥掉它，每往返一次就多一个空行（CommonMark #175 / GFM #142 由此不收敛）。

效果：引用式链接定义 3/24 → **24/24**，原始 HTML 块 9/23 → **23/23**，平均保留率 80.6% → **83.0%**，逐字保留 **227/262**，冒烟测试 325 → **382 项**。

### 改进 D：Obsidian 双链 / 嵌入 / Callout / 任务框（P2，本次落地）

透传块解决的是「整块外部语法」，但行内的 Obsidian 写法仍会被 `escapeMarkdown`改写成 `\[\[Note\]\]`、`\[ \]`——字符还在，语义却没了：Obsidian / GFM 不再把它们识别成双链或任务复选框。Callout 则更严重：普通引用块按段落切分后会在每行之间插入空行，`> [!NOTE]` 与后续 `> 内容` 被拆散。

| 做法 | 说明 |
|---|---|
| 行内属性 `MDWikiLink` | 解析 `[[Note]]` / `[[Note|别名]]` / `[[Note#标题]]` / `![[pic.png|100]]`，记住 raw、target、suffix、alias 与解析时的显示文字；正文显示别名 / 目标名，用强调色下划线区分 |
| 编辑安全 | 序列化时比对当前显示文字：未改动就逐字输出原语法，用户改过就按新文字重建 `[[target|新别名]]`，绝不让缓存的旧源码盖掉编辑 |
| Callout 块 `MDBlockType.callout` | `> [!NOTE] 标题` 及其后续 `> ` 行按原始行存入 storage，每行共享 `.mdCalloutID`，序列化时聚合成一个块一次输出，避免行间插空行 |
| 渲染与导出 | 按类型（NOTE / TIP / WARNING / DANGER …）给左侧色条与标题色；HTML 导出为 `<div class="callout" data-callout=…>`、双链为 `<a class="internal-link">`、嵌入为 `<span class="internal-embed">`、任务框为 `<input type="checkbox">` |
| 判定收紧 | `[!NOTE` 缺右括号、`[!]` 空类型仍是普通引用；`[[` 未闭合、`[[]]` 空链接不生成链接对象；任务框勾选成 `[x]` 后按当前文字写出 |
| 顺带修复 | 行内代码 span 内的反斜杠是字面量，原先也被 `escapeMarkdown` 转义，导致 `` `[[code]]` `` 往返不稳定；代码 span 现在跳过正文转义规则 |

效果：双链 4/30 → **30/30**，嵌入 2/7 → **7/7**，Callout 1/12 → **12/12**，任务框 2/9 → **9/9**；文件一次稳定 166 → **183**，收敛 171 → **195**；冒烟测试 382 → **452 项**。CI 闸门新增「这四类特征必须 100% 逐字保留」的硬约束。

## 7. 已知限制与风险边界

**不收敛文件**：12/207 份在第二轮往返后仍会继续变化，主要是含多层嵌套列表、缩进代码块、CriticMarkup / 数学公式混排的文档。frontmatter / 原始 HTML / 链接定义已被透传块覆盖，Obsidian 双链与 Callout 本次也已逐字保留，不再是主因。

| 文件 | 保留率 | 丢失的语法特征 |
|---|---:|---|
| `pandoc/sample.md` | 1.5% | 数学公式块 $$ |
| `kramdown/markdown_attr.text` | 5.6% | 行内 HTML |
| `kramdown/README.md` | 6.7% | — |
| `joplin/README.md` | 6.8% | 无序列表, 图片 |
| `multimarkdown/EdgeCases.text` | 12.3% | — |
| `marktext/BasicTextFormatting.md` | 19.5% | — |
| `cmark-gfm/block-list-nested.md` | 35.5% | — |
| `cmark-gfm/inline-em-nested.md` | 100.0% | — |
| `cmark-gfm/inline-em-worst.md` | 100.0% | — |
| `multimarkdown/README.md` | 100.0% | 粗体, 图片 |
| `multimarkdown/EmphandStrongStar.text` | 100.0% | — |
| `quarto/callouts.qmd` | 100.0% | — |

**风险边界（重要）**：

1. **传统模式是安全的**：它把 `.md` 当纯文本逐字节保存，不做任何解析或规范化。打开外部来源的复杂 Markdown 文件、且需要保持原写法时，请切到传统模式编辑后保存。
2. **即刻模式仍会规范化**，但范围已收窄：列表符号、段落空行、标题写法会被统一；YAML/TOML frontmatter、原始 HTML 块、引用式链接 / 脚注 / 引文定义整块逐字保留，Obsidian 双链 / 嵌入 / Callout / 任务框也逐字往返。透传块与 Callout 在编辑器里以源码形态显示，不渲染成对应交互效果。
3. **未编辑就切换模式不损坏文件**：`AppModel.authority` 机制保证刚打开、两侧都未编辑时切换模式不会重新序列化，保留原文件字节。改写风险出现在「即刻侧被编辑过再保存 / 切到传统侧」时。
4. **缩进代码块（4 空格）仍是空白**：FinalMd 目前没有把它识别成代码块，夹在其中的 HTML 行与链接定义行会按普通段落被转义。这是逐字保留率停在 86.6% 的主因——剩余 35 行里绝大多数是这类缩进行。涉及大量缩进代码的外部文件仍建议用传统模式。
5. **「逐字保留」不等于「完整渲染」**：Obsidian 双链不做跨文件跳转、`![[]]` 不展开被嵌入笔记的内容、Callout 不做 +/- 折叠交互、任务框不会点击勾选；Callout 内部行按源码形态显示，其中的行内强调不解析。这些是能力边界，不影响文件在 Obsidian 里重新打开时的正确性。
6. **规范用例结构识别率 90.39% → 90.34%**（−0.05pp，第三阶段的口径差异，本次保持不变 0.9034）：两条用例里的链接引用定义被正确识别为 `raw` 块，而旧版把它当成 `p` 段落凑巧命中了指标。内容无损、稳定性无损。

## 8. 改进建议（按优先级）

| 优先级 | 建议 | 状态 | 预期收益 |
|---|---|---|---|
| P0 | 修复 `1.` 索引越界与方括号吞噬，并加入冒烟回归 | ✅ 已完成 | 消除崩溃与内容丢失 |
| P1 | 增加「原样透传块」：frontmatter / 原始 HTML / 链接定义整块保存、逐字输出 | ✅ 已完成 | frontmatter 不再拆行、HTML 不再转义 |
| P1 | 把 `run-compat.sh` 接入 CI，用保留率 / 逐字保留率 / 语料 sha256 做回归阈值 | ✅ 已完成 | 防止兼容性倒退 |
| P2 | 支持 Obsidian 双链 / 嵌入 / Callout / 任务列表复选框的识别与逐字序列化，并在 CI 闸门里设为 100% 硬约束 | ✅ 本次完成 | C 类特征清零；文件一次稳定 166 → 183 |
| P1 | 打开外部 `.md` 时，若检测到不兼容扩展语法，提示「建议用传统模式编辑」或默认以传统模式打开 | ⬜ 待做 | 避免用户无意识改写原文件 |
| P2 | 支持缩进代码块（4 空格） | ⬜ 待做 | 补齐逐字保留率剩下的 35 行 |
| P3 | Obsidian 双链跳转、Callout 折叠交互、嵌入内容展开 | ⬜ 待做 | 从「保真」走向「完整可用」 |

## 9. 复现与验证步骤

```bash
cd FinalMd-swift

# 1) 下载 / 更新语料（已有文件会复用，不重复请求网络）
python3 scripts/fetch-fixtures.py

# 2) 现有冒烟测试（含透传块 / Obsidian 语法的回归断言）
./scripts/run-smoke.sh

# 3) 编译并运行全部语料的兼容性测试
./scripts/run-compat.sh

# 4) 校验语料完整性 + 回归阈值（CI 上跑的就是这条）
python3 scripts/check-compat-thresholds.py

# 5) 由结构化结果重新生成这份报告
python3 scripts/gen-compat-report.py
```

CI：`.github/workflows/compat-macos.yml` 在 push / PR / 手动触发时跑 `run-smoke.sh` → `run-compat.sh` → `check-compat-thresholds.py` → `gen-compat-report.py`，并把 `RESULTS.json` 与 `COMPATIBILITY.md` 上传为构建产物。阈值基线写在 `tests/fixtures/BASELINE.json`，提升后需显式更新。

本次实测：

| 验证项 | 结果 |
|---|---|
| `run-smoke.sh` | 452 项全通过 |
| `run-compat.sh` | 207 份文件 + 1327 条规范用例，零崩溃 |
| 平均可读字符保留率 | 83.0% |
| 透传块逐字保留 | 227/262 (86.6%) |
| Obsidian 双链 / 嵌入 / Callout / 任务框 | 30/30 / 7/7 / 12/12 / 9/9，全部 100% |
| `check-compat-thresholds.py` | 语料 sha256、绝对阈值、逐文件回归、四类扩展语法 100% 硬约束全部通过 |
| `swift build` / `swift build -c release` | 零警告 |
| `scripts/make_app.sh` | 重新打包 `build/FinalMd.app` |

## 10. 语料许可与来源

- 所有 `.md` 文件均为各项目公开仓库中的原始内容，未经修改，版权与许可证归各自作者。此处仅用于 FinalMd 本地兼容性测试。
- 每个文件的原始路径、来源 URL、字节数与 sha256 记录在 `tests/fixtures/MANIFEST.json`；路径清单在 `PATHS.json`；每份文件的详细测试结果在 `RESULTS.json`；CI 回归阈值在 `BASELINE.json`。
- CommonMark / GFM 规范文本与用例采用 CC-BY-SA 4.0；各软件仓库许可证见第 2 节表格。

