#!/usr/bin/env python3
#
#  probe-new-sources.py — 为新增的 Markdown 编辑器 / 解析器来源探测 .md 文件路径，
#  生成 PATHS.json 增量条目（用 jsDelivr data API，不受 GitHub API 限流）。
#
#  用法：python3 scripts/probe-new-sources.py > /tmp/new_paths.json
#

import json
import re
import subprocess
import sys
import urllib.parse

UA = "finalmd-compat-fixtures/1.0"

NEW_SOURCES = [
    # GUI 编辑器 / 笔记应用
    dict(slug="dillinger", name="Dillinger", repo="joemccann/dillinger", branch="master"),
    dict(slug="notable", name="Notable", repo="fabiospampinato/notable", branch="master"),
    dict(slug="simplenote", name="Simplenote", repo="Automattic/simplenote", branch="trunk"),
    dict(slug="trilium", name="Trilium Notes", repo="zadam/trilium", branch="master"),
    dict(slug="boostnote", name="Boostnote", repo="BoostIO/Boostnote", branch="master"),
    dict(slug="qownnotes", name="QOwnNotes", repo="pbek/QOwnNotes", branch="main"),
    dict(slug="appflowy", name="AppFlowy", repo="AppFlowy-IO/AppFlowy", branch="main"),
    dict(slug="codimd", name="CodiMD / HackMD", repo="hackmdio/codiMD", branch="develop"),
    dict(slug="editormd", name="editor.md", repo="pandao/editor.md", branch="master"),
    # 文档站 / 静态站点生成器（真实文档即语料）
    dict(slug="docsify", name="Docsify", repo="docsifyjs/docsify", branch="develop"),
    dict(slug="vitepress", name="VitePress", repo="vuejs/vitepress", branch="main"),
    dict(slug="docusaurus", name="Docusaurus", repo="facebook/docusaurus", branch="main"),
    dict(slug="mkdocs", name="MkDocs", repo="mkdocs/mkdocs", branch="master"),
    dict(slug="mdbook", name="mdBook", repo="rust-lang/mdBook", branch="master"),
    dict(slug="hugo", name="Hugo", repo="gohugoio/hugo", branch="master"),
    dict(slug="jekyll", name="Jekyll", repo="jekyll/jekyll", branch="master"),
    dict(slug="eleventy", name="Eleventy", repo="11ty/eleventy", branch="main"),
    dict(slug="hexo", name="Hexo", repo="hexojs/hexo", branch="master"),
    # 幻灯片
    dict(slug="slidev", name="Slidev", repo="slidevjs/slidev", branch="main"),
    dict(slug="revealjs", name="reveal.js", repo="hakimel/reveal.js", branch="master"),
    dict(slug="marp", name="Marp Core", repo="marp-team/marp-core", branch="main"),
    # 主流解析器 / 工具（测试语料即语法覆盖）
    dict(slug="markdown-it", name="markdown-it", repo="markdown-it/markdown-it", branch="master"),
    dict(slug="marked", name="marked", repo="markedjs/marked", branch="master"),
    dict(slug="remark", name="remark", repo="remarkjs/remark", branch="main"),
    dict(slug="commonmarkjs", name="commonmark.js", repo="commonmark/commonmark.js", branch="master"),
    dict(slug="python-markdown", name="Python-Markdown", repo="Python-Markdown/Markdown", branch="master"),
    dict(slug="mistune", name="mistune", repo="lepture/mistune", branch="master"),
    dict(slug="pulldown-cmark", name="pulldown-cmark", repo="raphlinus/pulldown-cmark", branch="master"),
    dict(slug="goldmark", name="goldmark", repo="yuin/goldmark", branch="master"),
    dict(slug="comrak", name="comrak", repo="kivikakk/comrak", branch="main"),
    dict(slug="markdownlint", name="markdownlint", repo="DavidAnson/markdownlint", branch="main"),
    dict(slug="prettier", name="Prettier", repo="prettier/prettier", branch="main"),
    dict(slug="md4c", name="md4c", repo="mity/md4c", branch="master"),
    dict(slug="discount", name="Discount", repo="Orc/discount", branch="master"),
    dict(slug="parsedown", name="Parsedown", repo="erusev/parsedown", branch="master"),
    dict(slug="league-commonmark", name="league/commonmark", repo="thephpleague/commonmark", branch="master"),
]

DOC_EXT = (".md", ".markdown", ".text", ".qmd")
SKIP_PAT = re.compile(
    r"(node_modules|vendor/|\.github/|changelog|code_of_conduct|contributing|"
    r"issue_template|pull_request_template|security\.md|funding\.yml|"
    r"authors\.md|maintainers|governance|release[-_]?notes?|"
    r"translations?/|locale|i18n/)", re.I)
PREFER_PAT = re.compile(
    r"(test|fixture|sample|example|spec|docs?/|guide|demo|benchmark)", re.I)


def curl_json(url, timeout=30, retries=3):
    for attempt in range(retries):
        try:
            p = subprocess.run(
                ["curl", "-sSL", "--compressed", "--max-time", str(timeout),
                 "-H", f"User-Agent: {UA}", url],
                capture_output=True, text=True, timeout=timeout + 15)
            if p.returncode == 0 and p.stdout.strip():
                return json.loads(p.stdout)
        except Exception:
            pass
    return None


def list_files(repo, branch):
    """jsDelivr data API：列出仓库扁平文件树。"""
    url = f"https://data.jsdelivr.com/v1/packages/gh/{repo}@{urllib.parse.quote(branch)}?structure=flat"
    data = curl_json(url)
    if not data:
        # 常见默认分支回退
        for alt in ("main", "master", "develop", "dev", "trunk"):
            if alt == branch:
                continue
            url = f"https://data.jsdelivr.com/v1/packages/gh/{repo}@{alt}?structure=flat"
            data = curl_json(url, retries=2)
            if data:
                return alt, data.get("files", [])
        return None, []
    return branch, data.get("files", [])


def pick(files, limit=8):
    """筛选并取样 .md 文件：优先 test/fixture/sample 目录，避开杂项文档。"""
    cands = []
    for f in files:
        name = f.get("name", "")
        size = f.get("size", 0)
        if not name.endswith(DOC_EXT):
            continue
        if SKIP_PAT.search(name):
            continue
        if not (40 <= size <= 60000):
            continue
        cands.append(name)
    # 优先测试/示例目录，其次文档目录，最后其他
    def rank(p):
        if PREFER_PAT.search(p) and re.search(r"(test|fixture|sample|spec)", p, re.I):
            return 0
        if PREFER_PAT.search(p):
            return 1
        return 2
    cands.sort(key=lambda p: (rank(p), p))
    picked = []
    seen_dirs = {}
    for p in cands:
        d = "/".join(p.split("/")[:-1]) or "/"
        # 每个目录最多取 3 个，保证覆盖面
        if seen_dirs.get(d, 0) >= 3:
            continue
        seen_dirs[d] = seen_dirs.get(d, 0) + 1
        picked.append(p.lstrip("/"))
        if len(picked) >= limit:
            break
    # 不足 limit 时按目录配额放宽
    if len(picked) < limit:
        for p in cands:
            pp = p.lstrip("/")
            if pp not in picked:
                picked.append(pp)
            if len(picked) >= limit:
                break
    return picked


def main():
    out = {}
    for src in NEW_SOURCES:
        branch, files = list_files(src["repo"], src["branch"])
        if not files:
            print(f"  ! {src['slug']}: 无法列出文件（{src['repo']}）", file=sys.stderr)
            out[src["slug"]] = []
            continue
        picked = pick(files, limit=8)
        out[src["slug"]] = picked
        print(f"  ✓ {src['slug']:18} @{branch or '?'}  {len(picked)} 个文件 "
              f"（候选 {len([f for f in files if f.get('name','').endswith(DOC_EXT)])}）",
              file=sys.stderr)
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
