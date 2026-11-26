#!/usr/bin/env python3
# run-mainstream.py — 主流 Markdown 语法测试编排器（第二轮）
#
# 流程：
#   1. 读 tests/fixtures/specs/mainstream-round2.json
#   2. gen-expected-html.js（commonmark.js / marked）批量生成权威期望 HTML
#   3. /tmp/finalmd-mainstream 跑 FinalMd parse→serialize 与忠实 HTML 片段
#   4. 双方 HTML 归一为「语义 token 流」后对比：
#        correct   = tokens(期望) == tokens(frag)    —— 解析/导出语义正确性
#        preserved = tokens(frag) == tokens(frag2)   —— 往返语义保持
#        stable    = out1 == out2                    —— 编辑器不动点
#   5. 输出 tests/fixtures/MAINSTREAM.json 与 /tmp/mainstream-report.md
#
# 归一化规则（消除渲染层噪声，只留语义差异）：
#   - 强调嵌套扁平为「字符段标记集」（em/strong/u/del 不分内外层顺序）
#   - b/i/s/strike 别名归一；空白折叠；<br> 周围空白不计
#   - 代码块内容只去尾换行；缩进代码块剥掉 4 空格/tab 语法前缀
#   - 列表剥掉成文标记（"- " / "8. "），按 (层级, 有序) 扁平比较
#   - 表格只比 th/td 序列与单元格内容，不比 thead/tbody 包裹与对齐
#   - 引用块内容扁平为单段行内流（多段落结构差异单列标记）
import json, os, subprocess, sys
from html.parser import HTMLParser

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
CASES_PATH = os.path.join(ROOT, "tests/fixtures/specs/mainstream-round2.json")
RESULTS_PATH = os.path.join(ROOT, "tests/fixtures/MAINSTREAM.json")
TOOL = "/tmp/finalmd-mainstream"

VOID = {"br", "hr", "img", "input", "meta", "link", "area", "base", "col",
        "embed", "source", "track", "wbr"}
TAG_ALIAS = {"s": "del", "strike": "del", "b": "strong", "i": "em"}
DROP_CLASSES = {"task-list-item", "contains-task-list"}
MARKS = {"em", "strong", "u", "del"}

class Node:
    __slots__ = ("tag", "attrs", "children")
    def __init__(self, tag, attrs=None):
        self.tag = tag
        self.attrs = attrs or {}
        self.children = []

class TreeBuilder(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root")
        self.stack = [self.root]
    def handle_starttag(self, tag, attrs):
        tag = TAG_ALIAS.get(tag, tag)
        node = Node(tag, self._clean(dict(attrs)))
        self.stack[-1].children.append(node)
        if tag not in VOID:
            self.stack.append(node)
    def handle_startendtag(self, tag, attrs):
        tag = TAG_ALIAS.get(tag, tag)
        self.stack[-1].children.append(Node(tag, self._clean(dict(attrs))))
    def handle_endtag(self, tag):
        tag = TAG_ALIAS.get(tag, tag)
        if tag in VOID:
            return
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                break
    def handle_data(self, data):
        self.stack[-1].children.append(data)
    def handle_comment(self, data):
        # 注释按行内 HTML 原样语义对待：用特殊节点保留（比较时双方一致即可）
        self.stack[-1].children.append(Node("#comment", {"text": data}))
    @staticmethod
    def _clean(attrs):
        out = {}
        for k, v in attrs.items():
            if k == "align":
                continue
            if k == "class":
                toks = [t for t in (v or "").split() if t not in DROP_CLASSES]
                if not toks:
                    continue
                v = " ".join(sorted(toks))
            if v is None:
                out[k] = None
            elif k in ("checked", "disabled") and v.lower() in ("", k):
                out[k] = None
            else:
                out[k] = v
        return out

def collapse_ws(s):
    return " ".join(s.split())

def strip4(text):
    """剥掉缩进代码块的一层语法前缀（4 空格 / tab）"""
    lines = text.split("\n")
    out = []
    for ln in lines:
        if ln.startswith("\t"):
            out.append(ln[1:])
        else:
            n = 0
            while n < 4 and n < len(ln) and ln[n] == " ":
                n += 1
            out.append(ln[n:])
    return "\n".join(out)

# ---------------- token 流生成 ----------------

def tokens_of(html):
    tb = TreeBuilder()
    tb.feed(html)
    tb.close()
    out = []
    walk(tb.root, out, marks=frozenset(), cont=(), block_ctx=True)
    return out

def walk(node, out, marks, cont, block_ctx):
    """扁平遍历生成 token。
    marks: 当前 em/strong/u/del 标记集
    cont: 行内容器上下文 (('code',), ('a', href), ...)
    block_ctx: 是否处于块级容器（用于空白端点裁剪）
    """
    buf = []  # 收集 (marks, cont, text) 段，邻接同键合并

    def flush():
        if not buf:
            return
        # 合并邻接同 (marks, cont) 段
        merged = []
        for m, c, t in buf:
            if merged and merged[-1][0] == m and merged[-1][1] == c:
                merged[-1] = (m, c, merged[-1][2] + t)
            else:
                merged.append((m, c, t))
        # 空白规则：块级端点与 <br> 两侧的纯空白段丢弃；段内空白折叠
        for m, c, t in merged:
            t2 = collapse_ws(t)
            if t2 == "":
                continue
            out.append(("seg", c, tuple(sorted(m)), t2))
        buf.clear()

    def emit_text(s, m, c, in_pre):
        buf.append((m, c, s))

    def walk_children(n, m, c, in_pre, block):
        for ch in n.children:
            if isinstance(ch, str):
                emit_text(ch, m, c, in_pre)
                continue
            t = ch.tag
            if t == "#comment":
                flush()
                out.append(("comment", ch.attrs.get("text", "")))
                continue
            if t in MARKS:
                walk_children(ch, m | {t}, c, in_pre, block)
                continue
            if t == "br":
                flush()
                out.append(("void", "br"))
                continue
            if t == "img":
                flush()
                src = (ch.attrs.get("src") or "").replace("%20", " ")
                alt = (ch.attrs.get("alt") or "").strip()
                title = ch.attrs.get("title") or ""
                out.append(("void", "img", src, alt, title))
                continue
            if t == "input":
                flush()
                out.append(("void", "input", ch.attrs.get("type") or "",
                            ch.attrs.get("checked") is not None))
                continue
            if t == "hr":
                flush()
                out.append(("void", "hr"))
                continue
            if t == "code":
                # 行内代码：内容精确保留（空白折叠前不做），作为一个 code 容器段
                txt = raw_text(ch)
                if txt.endswith("\n"):
                    txt = txt[:-1]
                flush()
                out.append(("code", c, txt))
                continue
            if t == "a":
                href = (ch.attrs.get("href") or "").replace("%20", " ")
                walk_children(ch, m, (("a", href),) + c, in_pre, block)
                continue
            if t == "pre":
                flush()
                txt = raw_text(ch)
                if txt.endswith("\n"):
                    txt = txt[:-1]
                if txt.strip() == "":
                    txt = ""
                cls = ""
                for cc in ch.children:
                    if isinstance(cc, Node) and cc.tag == "code":
                        cls = cc.attrs.get("class") or ""
                        break
                # 语言类只取首词（commonmark.js 只回填第一个词）
                if cls.startswith("language-"):
                    cls = "language-" + cls[len("language-"):].split()[0] if cls != "language-" else ""
                out.append(("pre", cls, txt))
                continue
            if t in ("p", "li", "h1", "h2", "h3", "h4", "h5", "h6",
                     "blockquote", "table", "thead", "tbody", "tr", "div",
                     "ul", "ol", "span", "u", "mark", "sup", "sub", "kbd"):
                walk_children(ch, m, c, in_pre, block)
                continue
            # 未知标签：整棵子树按原始 HTML 不透明比较
            flush()
            out.append(("html", dump_raw(ch)))

    walk_children(node, marks, cont, False, block_ctx)
    flush()

def raw_text(node):
    parts = []
    def w(n):
        for ch in n.children:
            if isinstance(ch, str):
                parts.append(ch)
            elif ch.tag == "br":
                parts.append("\n")
            else:
                w(ch)
    w(node)
    return "".join(parts)

def dump_raw(node):
    """未知标签子树还原为原始 HTML 片段（不透明比较）"""
    parts = []
    attrs = ""
    if node.attrs:
        items = []
        for k in sorted(node.attrs):
            v = node.attrs[k]
            if v is None:
                items.append(k)
            else:
                items.append(f'{k}="{v}"')
        attrs = " " + " ".join(items)
    if node.tag in VOID:
        return f"<{node.tag}{attrs}>"
    parts.append(f"<{node.tag}{attrs}>")
    for ch in node.children:
        if isinstance(ch, str):
            parts.append(ch)
        else:
            parts.append(dump_raw(ch))
    parts.append(f"</{node.tag}>")
    return "".join(parts)

def tokens_of_doc(html):
    """文档级 token：块结构（标题/列表/表格/引用）+ 行内段流"""
    tb = TreeBuilder()
    tb.feed(html)
    tb.close()
    out = []
    doc_blocks(tb.root, out)
    return out

def doc_blocks(node, out):
    for ch in node.children:
        if isinstance(ch, str):
            continue
        t = ch.tag
        if t == "p":
            inner = tokens_of_inner(ch)
            out.append(("p",))
            out.extend(trim_edge_segs(inner))
            out.append(("/p",))
        elif t in ("h1", "h2", "h3", "h4", "h5", "h6"):
            inner = tokens_of_inner(ch)
            out.append(("h", int(t[1])))
            out.extend(trim_edge_segs(inner))
            out.append(("/h",))
        elif t == "blockquote":
            inner = tokens_of_inner(ch)  # 内容扁平（块标签透明）
            out.append(("bq",))
            out.extend(inner)
            out.append(("/bq",))
        elif t in ("ul", "ol"):
            list_items(ch, 0, out)
        elif t == "table":
            out.append(("table",))
            table_cells(ch, out)
            out.append(("/table",))
        elif t == "pre":
            txt = raw_text(ch)
            if txt.endswith("\n"):
                txt = txt[:-1]
            if txt.startswith("    "):
                txt = strip4(txt)
            cls = ""
            for cc in ch.children:
                if isinstance(cc, Node) and cc.tag == "code":
                    cls = cc.attrs.get("class") or ""
                    break
            out.append(("pre", cls, txt))
        elif t in VOID:
            if t == "hr":
                out.append(("void", "hr"))
            elif t == "img":
                src = (ch.attrs.get("src") or "").replace("%20", " ")
                out.append(("void", "img", src, (ch.attrs.get("alt") or "").strip(),
                            ch.attrs.get("title") or ""))
            elif t == "br":
                out.append(("void", "br"))
        elif t in ("div", "figure", "section", "blockquote"):
            doc_blocks(ch, out)
        else:
            # 罕见顶层元素：按段落处理
            inner = tokens_of_inner(ch)
            if inner:
                out.append(("p",))
                out.extend(trim_edge_segs(inner))
                out.append(("/p",))

def tokens_of_inner(node):
    """行内 token 流（块标签透明，用于 li/quote/heading 内容）"""
    out = []
    walk(node, out, marks=frozenset(), cont=(), block_ctx=False)
    return out

def trim_edge_segs(toks):
    """去掉 token 流首尾的纯空白 seg"""
    def is_ws_seg(x):
        return x[0] == "seg" and x[3].strip() == ""
    while toks and is_ws_seg(toks[0]):
        toks = toks[1:]
    while toks and is_ws_seg(toks[-1]):
        toks = toks[:-1]
    return toks

def list_items(node, depth, out):
    ordered = node.tag == "ol"
    for ch in node.children:
        if not isinstance(ch, Node) or ch.tag != "li":
            continue
        out.append(("li", depth, 1 if ordered else 0))
        # li 内容：块标签透明（p 拆掉），嵌套列表的 li 单独在后面发
        inner = []
        for c2 in ch.children:
            if isinstance(c2, Node) and c2.tag in ("ul", "ol"):
                continue
            if isinstance(c2, str):
                inner.append(c2)
            else:
                walk_li_child(c2, inner)
        inner_toks = tokens_of_inner(Node("#frag", {}, ) ) # placeholder
        # 直接用 walk 收集
        frag = Node("#frag")
        frag.children = [c2 for c2 in ch.children
                         if not (isinstance(c2, Node) and c2.tag in ("ul", "ol"))]
        toks = tokens_of_inner(frag)
        out.extend(trim_edge_segs(toks))
        out.append(("/li",))
        for c2 in ch.children:
            if isinstance(c2, Node) and c2.tag in ("ul", "ol"):
                list_items(c2, depth + 1, out)

def walk_li_child(node, inner):
    inner.append(node)

def table_cells(node, out):
    def row(r):
        for c in r.children:
            if isinstance(c, Node) and c.tag in ("th", "td"):
                out.append(("cell", c.tag))
                frag = Node("#frag")
                frag.children = c.children
                out.extend(trim_edge_segs(tokens_of_inner(frag)))
                out.append(("/cell",))
    for ch in node.children:
        if not isinstance(ch, Node):
            continue
        if ch.tag == "tr":
            row(ch)
        elif ch.tag in ("thead", "tbody"):
            for c2 in ch.children:
                if isinstance(c2, Node) and c2.tag == "tr":
                    row(c2)

# ---------------- 主流程 ----------------

def main():
    with open(CASES_PATH, encoding="utf-8") as f:
        doc = json.load(f)
    cases = doc["cases"]

    gen_in = json.dumps([{"id": c["id"], "markdown": c["markdown"], "ref": c["ref"]}
                         for c in cases if c.get("check") == "full"])
    proc = subprocess.run(["node", os.path.join(ROOT, "scripts/gen-expected-html.js")],
                          input=gen_in, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        sys.exit(1)
    expected = {e["id"]: e["html"] for e in json.loads(proc.stdout)}

    tmp_cases = "/tmp/mainstream-cases.json"
    tmp_results = "/tmp/mainstream-results.json"
    with open(tmp_cases, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False)
    proc = subprocess.run([TOOL, tmp_cases, tmp_results], capture_output=True, text=True)
    sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        print("mainstream-check failed", file=sys.stderr)
        sys.exit(1)
    with open(tmp_results, encoding="utf-8") as f:
        results = json.load(f)["results"]
    by_id = {r["id"]: r for r in results}

    fails = []
    knowns = []
    ok = {"stable": 0, "correct": 0, "preserved": 0}
    total_full = 0
    for c in cases:
        r = by_id[c["id"]]
        checks = c.get("check", "full")
        stable = r["stable"]
        row = {"id": c["id"], "section": c["section"], "markdown": c["markdown"],
               "stable": stable}
        if stable:
            ok["stable"] += 1
        if checks == "full":
            total_full += 1
            exp_t = tokens_of_doc(expected[c["id"]])
            got_t = tokens_of_doc(r["frag"])
            got2_t = tokens_of_doc(r["frag2"])
            correct = exp_t == got_t
            preserved = got_t == got2_t
            row["correct"] = correct
            row["preserved"] = preserved
            if correct:
                ok["correct"] += 1
            if preserved:
                ok["preserved"] += 1
            if not correct:
                row["exp_t"] = exp_t
                row["got_t"] = got_t
            if not preserved:
                row["got2_t"] = got2_t
        if not stable or (checks == "full" and not row.get("correct")) or \
           (checks == "full" and not row.get("preserved")):
            row["out1"] = r["out1"]
            row["out2"] = r["out2"]
            row["frag"] = r["frag"]
            row["exp"] = expected.get(c["id"], "")
            if c.get("known"):
                row["known"] = True
                knowns.append(row)
            else:
                fails.append(row)

    report = {
        "generated_at": __import__("datetime").datetime.now().isoformat(timespec="seconds"),
        "summary": {
            "cases": len(cases),
            "full_checks": total_full,
            "stable": ok["stable"],
            "correct": ok["correct"],
            "preserved": ok["preserved"],
            "known": len(knowns),
            "failed": len(fails),
        },
        "failures": fails,
        "known_divergences": knowns,
    }
    with open(RESULTS_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)

    s = report["summary"]
    print(f"用例 {s['cases']} 条（语义对比 {s['full_checks']}）")
    print(f"  一次稳定 : {s['stable']}/{s['cases']}")
    print(f"  语义正确 : {s['correct']}/{s['full_checks']}")
    print(f"  往返保持 : {s['preserved']}/{s['full_checks']}")
    print(f"  已知取舍 : {s['known']}")
    print(f"  失败合计 : {s['failed']}")
    print(f"结果 → {RESULTS_PATH}")

    with open("/tmp/mainstream-report.md", "w", encoding="utf-8") as f:
        f.write("# 主流语法测试失败明细\n\n")
        f.write(f"用例 {s['cases']}：稳定 {s['stable']}、语义正确 {s['correct']}/{s['full_checks']}、"
                f"往返保持 {s['preserved']}/{s['full_checks']}、失败 {s['failed']}\n\n")
        by_sec = {}
        for row in fails:
            by_sec.setdefault(row["section"], []).append(row)
        for sec, rows in sorted(by_sec.items()):
            f.write(f"## {sec}（{len(rows)}）\n\n")
            for row in rows:
                tags = []
                if not row["stable"]:
                    tags.append("不稳定")
                if row.get("correct") is False:
                    tags.append("语义不符")
                if row.get("preserved") is False:
                    tags.append("往返丢失")
                f.write(f"### #{row['id']} [{'/'.join(tags)}]\n\n")
                f.write(f"输入: `{row['markdown']!r}`\n\n")
                if row.get("exp_t") is not None and row.get("correct") is False:
                    f.write(f"期望: `{row['exp_t']}`\n\n实际: `{row['got_t']}`\n\n")
                if row.get("preserved") is False:
                    f.write(f"往返后: `{row.get('got2_t','')}`\n\n")
                if not row["stable"]:
                    f.write(f"out1: `{row['out1']!r}`\n\nout2: `{row['out2']!r}`\n\n")
    print("明细 → /tmp/mainstream-report.md")

if __name__ == "__main__":
    main()
