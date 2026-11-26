#!/usr/bin/env python3
#
#  fetch-fixtures.py — 下载主流 Markdown 软件 / 解析器官方仓库里的真实 .md 文件，
#  以及 CommonMark / GFM 规范的官方测试用例，作为 FinalMd 兼容性测试语料。
#
#  用法：python3 scripts/fetch-fixtures.py
#  产物：tests/fixtures/{sources,specs}/ 与 tests/fixtures/MANIFEST.json
#
#  说明：
#   · 只下载各项目公开仓库中已存在的 Markdown 文件，不改动原内容；
#     版权与许可证归原作者，仅用于本地兼容性测试（见 README.md）。
#   · 网络不稳定时自动重试；raw.githubusercontent.com 失败会回退到 GitHub
#     Contents API（base64）。
#   · 规范文件（spec.txt）会额外解析成结构化 JSON 用例，便于逐例跑解析器。
#

import concurrent.futures
import hashlib
import json
import os
import re
import subprocess
import time
import urllib.parse

def log(*a):
    print(*a, flush=True)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "fixtures")
SPECS = os.path.join(OUT, "specs")
SOURCES_DIR = os.path.join(OUT, "sources")

UA = "finalmd-compat-fixtures/1.0"
DOC_EXT = (".md", ".markdown", ".text", ".qmd")

# ---------------------------------------------------------------------------
# 语料来源。每个条目代表一个主流 Markdown 软件 / 解析器生态。
#   paths 模式：明确的官方示例 / 测试文件路径
#   tree  模式：从仓库文件树里按目录前缀均匀取样，覆盖更多语法分支
# ---------------------------------------------------------------------------
SOURCES = [
    dict(slug="obsidian", name="Obsidian", repo="obsidianmd/obsidian-help",
         branch="master", license="CC BY-NC-SA 4.0 (Obsidian Help)",
         note="官方帮助库中的真实笔记文件，含 wikilink / callout / properties / embed",
         paths=[
             "README.md", "en/Home.md",
             "en/Editing and formatting/Basic formatting syntax.md",
             "en/Editing and formatting/Advanced formatting syntax.md",
             "en/Editing and formatting/Callouts.md",
             "en/Editing and formatting/Obsidian Flavored Markdown.md",
             "en/Editing and formatting/Properties.md",
             "en/Editing and formatting/HTML content.md",
             "en/Editing and formatting/Tags.md",
             "en/Editing and formatting/Attachments.md",
             "en/Linking notes and files/Internal links.md",
             "en/Linking notes and files/Embed files.md",
             "en/Linking notes and files/Aliases.md",
         ]),
    dict(slug="typora", name="Typora", repo="typora/typora-issues",
         branch="master", license="Repo content (Typora)",
         note="闭源软件，官方仅有 issue 仓库；语法覆盖由 GFM / Pandoc 语料补齐",
         paths=["README.md"]),
    dict(slug="marktext", name="Mark Text", repo="marktext/marktext",
         branch="master", license="MIT",
         note="官方 e2e / unit 测试用的真实 Markdown 文件",
         tree=[("test/e2e/data/", 12), ("test/unit/data/common/", 12)]),
    dict(slug="zettlr", name="Zettlr", repo="Zettlr/Zettlr",
         branch="develop", license="GPL-3.0",
         note="GUI 测试文档：YAML frontmatter、脚注、链接解析、排序等学术写作场景",
         tree=[("scripts/test-gui/test-files/", 16)], paths=["README.md"]),
    dict(slug="joplin", name="Joplin", repo="laurent22/joplin",
         branch="dev", license="MIT",
         note="Evernote 导入转换测试用的 Markdown 文件 + 大体积 README",
         tree=[("packages/app-cli/tests/enex_to_md/", 24)], paths=["README.md"]),
    dict(slug="stackedit", name="StackEdit", repo="benweet/stackedit",
         branch="master", license="MIT",
         note="应用内置的示例文档（新建文件默认内容）",
         paths=["README.md", "src/data/markdownSample.md", "src/data/welcomeFile.md"]),
    dict(slug="macdown", name="MacDown", repo="MacDownApp/macdown",
         branch="master", license="MIT",
         note="官方 demo.md 与 README",
         paths=["README.md", "assets/demo.md"]),
    dict(slug="logseq", name="Logseq", repo="logseq/logseq",
         branch="master", license="MIT",
         note="图谱解析器导出测试用的真实日记笔记（大纲式 Markdown）",
         tree=[("deps/graph-parser/test/resources/exporter-test-graph/journals/", 24)]),
    dict(slug="vscode", name="VS Code", repo="microsoft/vscode",
         branch="main", license="MIT",
         note="markdown-language-features 扩展的测试工作区与仓库文档",
         tree=[("extensions/markdown-language-features/test-workspace/", 6)],
         paths=["extensions/markdown-language-features/README.md",
                ".github/instructions/writing-tests.instructions.md"]),
    dict(slug="quarto", name="Quarto", repo="quarto-dev/quarto-web",
         branch="main", license="MIT",
         note="技术写作 .qmd：YAML、代码单元格、callout、交叉引用",
         tree=[("docs/authoring/", 24)]),
    dict(slug="pandoc", name="Pandoc", repo="jgm/pandoc",
         branch="main", license="GPL-2.0-or-later",
         note="官方 reader 测试语料（最全的 Markdown 扩展语法覆盖）+ 基准长文",
         tree=[("test/command/", 28)],
         paths=["benchmark/sample.md", "README.md"]),
    dict(slug="multimarkdown", name="MultiMarkdown 6", repo="fletcher/MultiMarkdown-6",
         branch="develop", license="MIT",
         note="MMD6 官方语法测试集（.text）",
         tree=[("tests/MMD6Tests/", 24), ("tests/Complex/", 6)],
         paths=["README.md"]),
    dict(slug="kramdown", name="kramdown", repo="gettalong/kramdown",
         branch="master", license="MIT",
         note="Ruby 解析器官方 testcases",
         tree=[("test/testcases/", 24)], paths=["README.md"]),
    dict(slug="cmark-gfm", name="GitHub / cmark-gfm", repo="github/cmark-gfm",
         branch="master", license="BSD-2-Clause",
         note="GFM 参考实现的基准样本文件",
         tree=[("bench/samples/", 30)]),
    # ---- Top 50 扩充：更多主流编辑器 / 笔记应用 ----
    dict(slug="dillinger", name="Dillinger", repo="joemccann/dillinger",
         branch="master", license="MIT",
         note="云端所见即所得编辑器的官方示例与文档"),
    dict(slug="notable", name="Notable", repo="fabiospampinato/notable",
         branch="master", license="MIT",
         note="笔记应用官方文档（Markdown 语法与数据格式）"),
    dict(slug="trilium", name="Trilium Notes", repo="zadam/trilium",
         branch="master", license="AGPL-3.0",
         note="知识库笔记应用的官方文档与迁移说明"),
    dict(slug="boostnote", name="Boostnote", repo="BoostIO/Boostnote",
         branch="master", license="GPL-2.0",
         note="程序员笔记应用的文档与示例笔记"),
    dict(slug="appflowy", name="AppFlowy", repo="AppFlowy-IO/AppFlowy",
         branch="main", license="AGPL-3.0",
         note="开源 Notion 替代品的文档与设计文档"),
    dict(slug="codimd", name="CodiMD / HackMD", repo="hackmdio/codiMD",
         branch="develop", license="AGPL-3.0",
         note="实时协作 Markdown 编辑器的文档"),
    dict(slug="editormd", name="editor.md", repo="pandao/editor.md",
         branch="master", license="MIT",
         note="jQuery Markdown 编辑器组件的官方文档"),
    dict(slug="laverna", name="Laverna", repo="Laverna/laverna",
         branch="master", license="MPL-2.0",
         note="加密笔记应用的文档"),
    # ---- 文档站 / 静态站点生成器（真实文档即语料）----
    dict(slug="docsify", name="Docsify", repo="docsifyjs/docsify",
         branch="develop", license="MIT",
         note="文档站点生成器官方文档（含插件语法）"),
    dict(slug="vitepress", name="VitePress", repo="vuejs/vitepress",
         branch="main", license="MIT",
         note="Vue 文档站生成器官方文档（容器语法、代码组）"),
    dict(slug="mkdocs", name="MkDocs", repo="mkdocs/mkdocs",
         branch="master", license="BSD-2-Clause",
         note="Python 文档站生成器的用户指南"),
    dict(slug="mdbook", name="mdBook", repo="rust-lang/mdBook",
         branch="master", license="MPL-2.0",
         note="Rust 官方文档书籍源文件（含隐藏行 / 注释语法）"),
    dict(slug="hugo", name="Hugo", repo="gohugoio/hugo",
         branch="master", license="Apache-2.0",
         note="静态站点生成器官方文档（frontmatter、短代码）"),
    dict(slug="jekyll", name="Jekyll", repo="jekyll/jekyll",
         branch="master", license="MIT",
         note="Ruby 静态站点生成器官方文档（Liquid + Markdown）"),
    dict(slug="eleventy", name="Eleventy", repo="11ty/eleventy",
         branch="main", license="MIT",
         note="静态站点生成器官方文档（多种模板语言共存）"),
    dict(slug="hexo", name="Hexo", repo="hexojs/hexo",
         branch="master", license="MIT",
         note="博客框架官方文档"),
    # ---- 幻灯片 ----
    dict(slug="slidev", name="Slidev", repo="slidevjs/slidev",
         branch="main", license="MIT",
         note="Markdown 幻灯片（代码高亮、动画、演讲者备注）"),
    dict(slug="revealjs", name="reveal.js", repo="hakimel/reveal.js",
         branch="master", license="MIT",
         note="HTML 幻灯片框架的 Markdown 幻灯片示例"),
    dict(slug="marp", name="Marp Core", repo="marp-team/marp-core",
         branch="main", license="MIT",
         note="Markdown 幻灯片引擎核心的语法测试文档"),
    # ---- 主流解析器 / 工具（测试语料即语法覆盖）----
    dict(slug="markdown-it", name="markdown-it", repo="markdown-it/markdown-it",
         branch="master", license="MIT",
         note="CommonMark 参考级 JS 解析器的 fixture 语料"),
    dict(slug="marked", name="marked", repo="markedjs/marked",
         branch="master", license="MIT",
         note="最流行的 JS 解析器官方 spec fixture"),
    dict(slug="remark", name="remark", repo="remarkjs/remark",
         branch="main", license="MIT",
         note="unified 生态解析器的测试与文档"),
    dict(slug="commonmarkjs", name="commonmark.js", repo="commonmark/commonmark.js",
         branch="master", license="BSD-2-Clause",
         note="CommonMark 官方参考实现的测试与基准样本"),
    dict(slug="python-markdown", name="Python-Markdown", repo="Python-Markdown/Markdown",
         branch="master", license="BSD-3-Clause",
         note="Python 解析器官方文档与扩展语法测试"),
    dict(slug="mistune", name="mistune", repo="lepture/mistune",
         branch="master", license="BSD-3-Clause",
         note="快速 Python 解析器的文档"),
    dict(slug="pulldown-cmark", name="pulldown-cmark", repo="raphlinus/pulldown-cmark",
         branch="master", license="MIT",
         note="Rust CommonMark 解析器的测试语料"),
    dict(slug="goldmark", name="goldmark", repo="yuin/goldmark",
         branch="master", license="MIT",
         note="Go CommonMark 解析器（GitHub 官方采用）"),
    dict(slug="comrak", name="comrak", repo="kivikakk/comrak",
         branch="main", license="BSD-2-Clause",
         note="Rust cmark-gfm 移植的测试与文档"),
    dict(slug="markdownlint", name="markdownlint", repo="DavidAnson/markdownlint",
         branch="main", license="MIT",
         note="Markdown 规范检查器的示例文档（规则即语法规范）"),
    dict(slug="prettier", name="Prettier", repo="prettier/prettier",
         branch="main", license="MIT",
         note="代码格式化器的 Markdown 格式化测试样例"),
    dict(slug="md4c", name="md4c", repo="mity/md4c",
         branch="master", license="MIT",
         note="C 语言 CommonMark 解析器的测试输入"),
    dict(slug="discount", name="Discount", repo="Orc/discount",
         branch="master", license="BSD-2-Clause",
         note="C 语言 Markdown 解析器（markdown 命令）的测试语料"),
    dict(slug="parsedown", name="Parsedown", repo="erusev/parsedown",
         branch="master", license="MIT",
         note="PHP 最流行 Markdown 解析器的文档"),
    dict(slug="league-commonmark", name="league/commonmark", repo="thephpleague/commonmark",
         branch="master", license="BSD-3-Clause",
         note="PHP CommonMark 参考实现的文档"),
    dict(slug="remarkable", name="remarkable", repo="jonschlinkert/remarkable",
         branch="master", license="MIT",
         note="高性能 JS 解析器的官方文档与基准样例"),
    dict(slug="showdown", name="showdown", repo="showdownjs/showdown",
         branch="master", license="MIT",
         note="双向 Markdown 转换器的官方文档"),
    dict(slug="cmark", name="cmark", repo="commonmark/cmark",
         branch="master", license="BSD-2-Clause",
         note="CommonMark 官方 C 参考实现的测试输入"),
]

SPECS_SRC = [
    dict(slug="commonmark", name="CommonMark 0.31.2", repo="commonmark/commonmark-spec",
         branch="master", path="spec.txt", version="0.31.2",
         license="CC-BY-SA 4.0"),
    dict(slug="gfm", name="GFM 0.29", repo="github/cmark-gfm",
         branch="master", path="test/spec.txt", version="0.29",
         license="CC-BY-SA 4.0"),
]


def curl(url, dest=None, headers=(), timeout=40, retries=2):
    """带重试的 curl；dest 为空时返回 stdout 文本。"""
    cmd = ["curl", "-sSL", "--compressed", "--max-time", str(timeout),
           "-H", f"User-Agent: {UA}"]
    for h in headers:
        cmd += ["-H", h]
    if dest:
        cmd += ["-o", dest, "-w", "%{http_code}"]
    cmd.append(url)
    for attempt in range(retries):
        try:
            p = subprocess.run(cmd, capture_output=True, text=False, timeout=timeout + 20)
            out = p.stdout.decode("utf-8", "replace") if isinstance(p.stdout, bytes) else p.stdout
            if p.returncode == 0 and (not dest or out.strip() == "200"):
                return out
            if dest and out.strip() != "200":
                # 有些请求返回 200 但被网关截断，重试
                pass
        except subprocess.TimeoutExpired:
            pass
        time.sleep(0.6 * (attempt + 1))
    return None


def cdn_url(repo, branch, path):
    """jsDelivr GitHub CDN：不受 GitHub API 60 次/小时限流影响。"""
    return f"https://cdn.jsdelivr.net/gh/{repo}@{branch}/{urllib.parse.quote(path, safe='/')}"


def raw_url(repo, branch, path):
    return f"https://raw.githubusercontent.com/{repo}/{branch}/{urllib.parse.quote(path, safe='/')}"


def api_raw_url(repo, branch, path):
    return (f"https://api.github.com/repos/{repo}/contents/"
            f"{urllib.parse.quote(path, safe='/')}?ref={branch}")


def download_file(repo, branch, path, dest):
    """jsDelivr CDN → raw.githubusercontent.com → Contents API，逐级回退。"""
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return cdn_url(repo, branch, path)
    for url, timeout, retries in (
        (cdn_url(repo, branch, path), 25, 3),
        (raw_url(repo, branch, path), 20, 2),
    ):
        if curl(url, dest=dest, timeout=timeout, retries=retries):
            if os.path.exists(dest) and os.path.getsize(dest) > 0:
                return url
    # 最后回退：GitHub Contents API（返回 JSON，content 为 base64）
    txt = curl(api_raw_url(repo, branch, path),
               headers=("Accept: application/vnd.github+json",), timeout=40, retries=1)
    if txt:
        try:
            import base64
            data = json.loads(txt)
            if data.get("encoding") == "base64" and data.get("content"):
                with open(dest, "wb") as f:
                    f.write(base64.b64decode(data["content"]))
                return api_raw_url(repo, branch, path)
        except Exception:
            pass
    # 全部失败时清掉可能残留的错误页，避免被误当成有效语料
    if os.path.exists(dest):
        os.remove(dest)
    return None


def fetch_tree(repo, branch):
    url = f"https://api.github.com/repos/{repo}/git/trees/{branch}?recursive=1"
    txt = curl(url, headers=("Accept: application/vnd.github+json",), timeout=90, retries=2)
    if not txt:
        return None
    try:
        return json.loads(txt).get("tree", [])
    except Exception:
        return None


def select_from_tree(tree, prefix, limit):
    """按目录前缀筛文件并等间隔取样，尽量覆盖不同子目录 / 大小。"""
    cands = [e for e in tree
             if e.get("type") == "blob" and e["path"].startswith(prefix)
             and e["path"].endswith(DOC_EXT)
             and 40 <= e.get("size", 0) <= 60000
             and "node_modules" not in e["path"]
             and not os.path.basename(e["path"]).startswith("_")]
    cands.sort(key=lambda e: e["path"])
    if len(cands) <= limit:
        return [e["path"] for e in cands]
    step = len(cands) / float(limit)
    picked = []
    for i in range(limit):
        p = cands[min(int(i * step), len(cands) - 1)]["path"]
        if p not in picked:
            picked.append(p)
    return picked


def safe_name(path, index):
    base = os.path.basename(path)
    base = re.sub(r"[^A-Za-z0-9._\-\u4e00-\u9fff]", "_", base)
    return f"{index:03d}-{base}"


def parse_spec(text, version, source):
    """把官方 spec.txt 里的 example 块解析成结构化用例。
    规范用 → 表示一个真实 tab，需要还原；'.' 单独一行分隔 markdown / html。"""
    lines = text.split("\n")
    examples, section, i = [], "", 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("# "):
            section = line.lstrip("# ").strip()
        if re.match(r"^`{3,}\s+example", line):
            j, md = i + 1, []
            while j < len(lines) and lines[j] != ".":
                md.append(lines[j])
                j += 1
            j += 1
            html = []
            while j < len(lines) and not re.match(r"^`{3,}\s*$", lines[j]):
                html.append(lines[j])
                j += 1
            examples.append(dict(
                id=len(examples) + 1,
                section=section,
                markdown="\n".join(md).replace("→", "\t"),
                html="\n".join(html),
            ))
            i = j + 1
        else:
            i += 1
    return dict(source=source, version=version, count=len(examples), examples=examples)


def main():
    os.makedirs(SPECS, exist_ok=True)
    os.makedirs(SOURCES_DIR, exist_ok=True)
    manifest = dict(
        generated_at=time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        purpose="FinalMd Markdown 兼容性测试语料（原文件内容未经修改）",
        sources=[], specs=[], files=[],
    )

    # 1) 规范测试套件
    for s in SPECS_SRC:
        dest = os.path.join(SPECS, f"{s['slug']}-{s['version']}.spec.txt")
        url = download_file(s["repo"], s["branch"], s["path"], dest)
        if not url or not os.path.exists(dest):
            log(f"  ! 规范下载失败：{s['name']}")
            continue
        text = open(dest, encoding="utf-8", errors="replace").read()
        parsed = parse_spec(text, s["version"], s["name"])
        jdest = os.path.join(SPECS, f"{s['slug']}-{s['version']}.json")
        with open(jdest, "w", encoding="utf-8") as f:
            json.dump(parsed, f, ensure_ascii=False, indent=1)
        manifest["specs"].append(dict(
            slug=s["slug"], name=s["name"], version=s["version"],
            license=s["license"], url=url,
            spec_file=os.path.relpath(dest, ROOT),
            cases_file=os.path.relpath(jdest, ROOT),
            example_count=parsed["count"],
        ))
        log(f"  ✓ {s['name']}: {parsed['count']} 个官方用例")

    # 2) 各软件真实 .md 文件。
    #    路径清单固化在 PATHS.json（由 GitHub 文件树 / jsDelivr 列表一次性探测得到），
    #    运行时不再请求任何 API，因此不受限流影响，也保证结果可复现。
    paths_file = os.path.join(OUT, "PATHS.json")
    fixed_paths = {}
    if os.path.exists(paths_file):
        with open(paths_file, encoding="utf-8") as f:
            fixed_paths = json.load(f)
    else:
        log("  ! 缺少 PATHS.json，回退到脚本内的显式路径")

    jobs = []
    for src in SOURCES:
        paths = list(fixed_paths.get(src["slug"]) or src.get("paths", []))
        # 去重且保序
        seen, unique = set(), []
        for p in paths:
            if p not in seen:
                seen.add(p)
                unique.append(p)
        manifest["sources"].append(dict(
            slug=src["slug"], name=src["name"], repo=src["repo"],
            branch=src["branch"], license=src["license"], note=src["note"],
            file_count=len(unique),
        ))
        for idx, path in enumerate(unique, 1):
            dest = os.path.join(SOURCES_DIR, src["slug"], safe_name(path, idx))
            jobs.append((src, path, dest, idx))

    def run(job):
        src, path, dest, idx = job
        url = download_file(src["repo"], src["branch"], path, dest)
        if not url or not os.path.exists(dest) or os.path.getsize(dest) == 0:
            return None
        data = open(dest, "rb").read()
        return dict(
            slug=src["slug"], source_path=path,
            local_path=os.path.relpath(dest, ROOT),
            url=url, bytes=len(data),
            sha256=hashlib.sha256(data).hexdigest(),
        )

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(run, jobs))
    ok = [r for r in results if r]
    manifest["files"] = sorted(ok, key=lambda r: (r["slug"], r["local_path"]))
    failed = len(jobs) - len(ok)
    log(f"  ✓ 下载文件 {len(ok)}/{len(jobs)}" + (f"（失败 {failed}）" if failed else ""))

    with open(os.path.join(OUT, "MANIFEST.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    by_slug = {}
    for r in ok:
        by_slug[r["slug"]] = by_slug.get(r["slug"], 0) + 1
    log("\n  来源汇总：")
    for src in SOURCES:
        log(f"    {src['name']:22} {by_slug.get(src['slug'], 0):>3} 个文件")
    total_bytes = sum(r["bytes"] for r in ok)
    log(f"\n  合计 {len(ok)} 个文件 / {total_bytes / 1024:.1f} KiB")
    log(f"  规范用例 {sum(s['example_count'] for s in manifest['specs'])} 条")
    log(f"  清单：{os.path.relpath(os.path.join(OUT, 'MANIFEST.json'), ROOT)}")


if __name__ == "__main__":
    main()
