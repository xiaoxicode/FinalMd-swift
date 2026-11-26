# Markdown 兼容性测试语料

本目录由 `scripts/fetch-fixtures.py` 生成，内容来自各主流 Markdown 软件 / 解析器
官方仓库中的真实文件与官方规范用例，**仅供 FinalMd 本地兼容性测试使用**。
所有文件保持原始字节，版权与许可证归原作者。

| 文件 | 说明 |
|---|---|
| `MANIFEST.json` | 每个文件的来源路径、URL、字节数、sha256 与许可证 |
| `PATHS.json` | 固化的下载路径清单（让脚本不依赖 GitHub API，可复现） |
| `RESULTS.json` | `run-compat.sh` 生成的结构化测试结果 |
| `BASELINE.json` | CI 回归阈值（保留率 / 结构识别率 / 稳定率、`required_features_100` 五类语法特征 100% 硬约束、`raw_exact_rate = 1.0` 即全部透传行〔frontmatter 整块 / 原始 HTML / 链接定义〕逐字保留，倒退一行即拦下；`min_feature_rates` 当前为空，预留给未来低频语法）；指标提升后用 `check-compat-thresholds.py --update-baseline` 更新 |
| `sources/<slug>/` | 按来源分组的原始 `.md` 文件 |
| `specs/` | CommonMark / GFM 规范原文与解析后的结构化用例 |

重新下载：`python3 scripts/fetch-fixtures.py`（已有文件自动复用）。
运行测试：`./scripts/run-compat.sh`；回归闸门：`python3 scripts/check-compat-thresholds.py`；
生成报告：`python3 scripts/gen-compat-report.py`。
CI：`.github/workflows/compat-macos.yml`（push / PR / 手动触发，语料直接取自 git）。

来源许可证：

- **Obsidian** — `obsidianmd/obsidian-help`（CC BY-NC-SA 4.0 (Obsidian Help)）
- **Typora** — `typora/typora-issues`（Repo content (Typora)）
- **Mark Text** — `marktext/marktext`（MIT）
- **Zettlr** — `Zettlr/Zettlr`（GPL-3.0）
- **Joplin** — `laurent22/joplin`（MIT）
- **StackEdit** — `benweet/stackedit`（MIT）
- **MacDown** — `MacDownApp/macdown`（MIT）
- **Logseq** — `logseq/logseq`（MIT）
- **VS Code** — `microsoft/vscode`（MIT）
- **Quarto** — `quarto-dev/quarto-web`（MIT）
- **Pandoc** — `jgm/pandoc`（GPL-2.0-or-later）
- **MultiMarkdown 6** — `fletcher/MultiMarkdown-6`（MIT）
- **kramdown** — `gettalong/kramdown`（MIT）
- **GitHub / cmark-gfm** — `github/cmark-gfm`（BSD-2-Clause）
- **Dillinger** — `joemccann/dillinger`（MIT）
- **Notable** — `fabiospampinato/notable`（MIT）
- **Trilium Notes** — `zadam/trilium`（AGPL-3.0）
- **Boostnote** — `BoostIO/Boostnote`（GPL-2.0）
- **AppFlowy** — `AppFlowy-IO/AppFlowy`（AGPL-3.0）
- **CodiMD / HackMD** — `hackmdio/codiMD`（AGPL-3.0）
- **editor.md** — `pandao/editor.md`（MIT）
- **Laverna** — `Laverna/laverna`（MPL-2.0）
- **Docsify** — `docsifyjs/docsify`（MIT）
- **VitePress** — `vuejs/vitepress`（MIT）
- **MkDocs** — `mkdocs/mkdocs`（BSD-2-Clause）
- **mdBook** — `rust-lang/mdBook`（MPL-2.0）
- **Hugo** — `gohugoio/hugo`（Apache-2.0）
- **Jekyll** — `jekyll/jekyll`（MIT）
- **Eleventy** — `11ty/eleventy`（MIT）
- **Hexo** — `hexojs/hexo`（MIT）
- **Slidev** — `slidevjs/slidev`（MIT）
- **reveal.js** — `hakimel/reveal.js`（MIT）
- **Marp Core** — `marp-team/marp-core`（MIT）
- **markdown-it** — `markdown-it/markdown-it`（MIT）
- **marked** — `markedjs/marked`（MIT）
- **remark** — `remarkjs/remark`（MIT）
- **commonmark.js** — `commonmark/commonmark.js`（BSD-2-Clause）
- **Python-Markdown** — `Python-Markdown/Markdown`（BSD-3-Clause）
- **mistune** — `lepture/mistune`（BSD-3-Clause）
- **pulldown-cmark** — `raphlinus/pulldown-cmark`（MIT）
- **goldmark** — `yuin/goldmark`（MIT）
- **comrak** — `kivikakk/comrak`（BSD-2-Clause）
- **markdownlint** — `DavidAnson/markdownlint`（MIT）
- **Prettier** — `prettier/prettier`（MIT）
- **md4c** — `mity/md4c`（MIT）
- **Discount** — `Orc/discount`（BSD-2-Clause）
- **Parsedown** — `erusev/parsedown`（MIT）
- **league/commonmark** — `thephpleague/commonmark`（BSD-3-Clause）
- **remarkable** — `jonschlinkert/remarkable`（MIT）
- **showdown** — `showdownjs/showdown`（MIT）
- **cmark** — `commonmark/cmark`（BSD-2-Clause）
- **CommonMark 0.31.2** — `commonmark/commonmark-spec`（CC-BY-SA 4.0）
- **GFM 0.29** — `github/cmark-gfm`（CC-BY-SA 4.0）
