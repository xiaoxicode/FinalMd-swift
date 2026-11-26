#!/usr/bin/env python3
# gen-mainstream-cases.py — 主流 Markdown 语法（CommonMark 0.31.2 + GFM）系统测试矩阵
# 产出 tests/fixtures/specs/mainstream-round2.json：[{id, section, markdown, ref}]
# ref: "cm"  = 以 commonmark.js 0.31.2 为权威期望
#      "gfm" = 以 marked（GFM）为权威期望
# 另有 "check": "stable" 的用例只查往返稳定（无 HTML 权威对照，如 frontmatter）。
import json, os

CASES = []
def add(section, markdown, ref="cm", check="full", known=False):
    case = {
        "id": len(CASES) + 1,
        "section": section,
        "markdown": markdown,
        "ref": ref,
        "check": check,
    }
    if known:
        case["known"] = True   # 已知语义取舍：失败不计入缺陷，见 COMPATIBILITY.md
    CASES.append(case)

# ---------------------------------------------------------------- 1. 段落与换行
add("paragraph-breaks", "single line paragraph")
add("paragraph-breaks", "line one\nline two")
add("paragraph-breaks", "line one  \nline two")                      # 两空格硬换行
add("paragraph-breaks", "line one\\\nline two")                      # 反斜杠硬换行
add("paragraph-breaks", "a  \nb  \nc")                               # 连续硬换行
add("paragraph-breaks", "a\\\nb\\\nc")
add("paragraph-breaks", "a  \n\nb")                                  # 硬换行后空行
add("paragraph-breaks", "trailing spaces here   ")                   # 行尾空格不接换行
add("paragraph-breaks", "para ends with hard break  ")               # 段尾硬换行(B25)
add("paragraph-breaks", "para ends with backslash break\\")
add("paragraph-breaks", "  leading two spaces")
add("paragraph-breaks", "a\n   \nb")                                 # 空白行分段
add("paragraph-breaks", "loose  \n\n\ntight")

# ---------------------------------------------------------------- 2. ATX 标题
for lvl in range(1, 7):
    add("atx-headings", "#" * lvl + " heading " + str(lvl))
add("atx-headings", "#no space")
add("atx-headings", "# closed heading #")
add("atx-headings", "### closed ###")
add("atx-headings", "## trailing hashes ##extra")
add("atx-headings", "# empty #")
add("atx-headings", "# `code` and **bold** in heading")
add("atx-headings", "   # indented up to 3")
add("atx-headings", "    # four spaces is code")
add("atx-headings", "# heading with [link](http://x)")
add("atx-headings", "# escaped \\# not heading")
add("atx-headings", "#1 no space after hash")

# ---------------------------------------------------------------- 3. Setext 标题
add("setext-headings", "title\n=")
add("setext-headings", "title\n-")
add("setext-headings", "multi word title\n====")
add("setext-headings", "title\n---")                                 # 也是 hr 上下文
add("setext-headings", "with **bold**\n=")
add("setext-headings", "a\n=\nb\n=")                                 # 连续两个
add("setext-headings", "  indented title\n=")

# ---------------------------------------------------------------- 4. 分割线
add("thematic-breaks", "***")
add("thematic-breaks", "---")
add("thematic-breaks", "___")
add("thematic-breaks", " * * * ")
add("thematic-breaks", "- - -")
add("thematic-breaks", "_____")
add("thematic-breaks", "**")                                         # 不足 3 个
add("thematic-breaks", "--")
add("thematic-breaks", " ***\n ---\n ___")                           # 连续三种
add("thematic-breaks", "a\n\n---\n\nb")

# ---------------------------------------------------------------- 5. 围栏代码块
add("fenced-code", "```\ncode\n```")
add("fenced-code", "```swift\nlet x = 1\n```")
add("fenced-code", "~~~python\nprint(1)\n~~~")
add("fenced-code", "````\n```\nnested\n```\n````")
add("fenced-code", "``` info with spaces\ncode\n```")
add("fenced-code", "```info`tick\ncode\n```")                        # info 含反引号非法
add("fenced-code", "```\n```")                                       # 空
add("fenced-code", "```\nunclosed fence")
add("fenced-code", "  ```\n  indented fence\n  ```")
add("fenced-code", "```\n*not emphasis*\n[not link](x)\n```")
add("fenced-code", "```bash\necho `date`\n```")
add("fenced-code", "~~~\n~~~\n~~~")                                  # 空 ~~~ 三次
add("fenced-code", "```\n\n\n```")                                   # 空行在代码内

# ---------------------------------------------------------------- 6. 缩进代码块
add("indented-code", "    indented code")
add("indented-code", "    line 1\n    line 2")
add("indented-code", "    code\n\n    more code")
add("indented-code", "\ttab indented code")
add("indented-code", "text\n\n    code after para")
add("indented-code", "    *not a list*")
add("indented-code", "     5 spaces, one kept")

# ---------------------------------------------------------------- 7. 引用块
add("blockquote", "> simple quote")
add("blockquote", "> line 1\n> line 2")
add("blockquote", "> line 1\nline 2 lazy")
add("blockquote", "> nested\n>> deeper")
add("blockquote", ">")
add("blockquote", "> # heading in quote")
add("blockquote", "> ```\n> code in quote\n> ```")
add("blockquote", "> - list in quote\n> - second")
add("blockquote", "> quote\n\n> second quote")
add("blockquote", "> **bold** in quote")
add("blockquote", "> multi\n>\n> paragraph quote")

# ---------------------------------------------------------------- 8. 无序列表
add("lists-ul", "- a\n- b")
add("lists-ul", "* a\n* b")
add("lists-ul", "+ a\n+ b")
add("lists-ul", "- a\n* b\n+ c")                                     # 标记变化断列表
add("lists-ul", "- one\n\n- two")                                    # loose
add("lists-ul", "- one\n  - nested\n  - nested2\n- two")
add("lists-ul", "- a\n  continued lazy")
add("lists-ul", "- a\n\n  para in item")
add("lists-ul", "- **bold** item\n- `code` item")
add("lists-ul", "-\n  empty item")
add("lists-ul", "- a\n\n\n- b")                                      # 多空行 loose
add("lists-ul", "  - two space indent item")

# ---------------------------------------------------------------- 9. 有序列表
add("lists-ol", "1. a\n2. b")
add("lists-ol", "1. a\n1. b")                                        # 序号全 1
add("lists-ol", "3. start at three\n4. next")
add("lists-ol", "1) paren delimiter\n2) next")
add("lists-ol", "1. a\n\n2. b")                                      # loose
add("lists-ol", "1. one\n   1. nested\n   2. nested2\n2. two")
add("lists-ol", "10. two digit\n11. eleven")
add("lists-ol", "1. **bold**\n2. [link](http://x)")
add("lists-ol", "1. a\n  continued")

# ---------------------------------------------------------------- 10. 行内链接
add("links-inline", "[text](http://example.com)")
add("links-inline", "[text](http://example.com \"title\")")
add("links-inline", "[text](http://example.com 'title')")
add("links-inline", "[text](http://example.com (title))")
add("links-inline", "[text](/relative/path)")
add("links-inline", "[text](<http://example.com/a b>)")              # 尖括号含空格
add("links-inline", "[text](<>")                                     # 空目标
add("links-inline", "[nested [brackets] here](http://x)")
add("links-inline", "[empty]()")
add("links-inline", "[with *em* and `code`](http://x)")
add("links-inline", "[spaces in text](http://x)")
add("links-inline", "[escaped \\] bracket](http://x)")
add("links-inline", "[](http://x)")   # B4x：空标签链接按 ZWSP 哨兵渲染成空锚点（CM §6.3）
add("links-inline", "[text](http://x \"ti(t)le\")")
add("links-inline", "[a](b(c)d)")                                    # 深度配对括号
add("links-inline", "[CONTRIBUTING.md](CONTRIBUTING.md)")            # B18 text==dest
add("links-inline", "[same](same) and <same>")                       # autolink 邻接
add("links-inline", "[*em text*](http://x)")

# ---------------------------------------------------------------- 11. 引用式链接
add("links-reference", "[text][ref]\n\n[ref]: http://example.com")
add("links-reference", "[text][]\n\n[text]: http://example.com")
add("links-reference", "[text]\n\n[text]: http://example.com")
add("links-reference", "[text][REF]\n\n[ref]: http://example.com")   # 大小写
add("links-reference", "[text][undefined]")
add("links-reference", "[text][ref]\n\n[ref]: http://example.com \"title\"")
add("links-reference", "[text][ref]\n\n   [ref]: /url\n")
add("links-reference", "[text][ref]\n\n[ref]: <http://example.com>")
add("links-reference", "[a][b]\n\n[b]: /u1\n[a]: /u2")

# ---------------------------------------------------------------- 12. autolink
add("autolinks", "<http://example.com>")
add("autolinks", "<https://example.com/path?q=1>")
add("autolinks", "<mailto:foo@bar.com>")
add("autolinks", "<foo@bar.com>")
add("autolinks", "<foo:bar>")
add("autolinks", "<foo bar>")                                        # 含空格非法
add("autolinks", "<http://example.com> and [text](http://example.com)")
add("autolinks", "text <http://x.y> more")

# ---------------------------------------------------------------- 13. 图片
add("images", "![alt](http://example.com/img.png)")
add("images", "![alt](img.png \"title\")")
add("images", "![](img.png)")
add("images", "![alt with *em*](img.png)")
add("images", "[![img in link](i.png)](http://x)")
add("images", "![alt][ref]\n\n[ref]: img.png")
add("images", "![](<img with space.png>)")

# ---------------------------------------------------------------- 14. 强调
add("emphasis", "*em*")
add("emphasis", "_em_")
add("emphasis", "**strong**")
add("emphasis", "__strong__")
add("emphasis", "***both***")
add("emphasis", "___both___")
add("emphasis", "*foo **bar** baz*")                                 # 嵌套
add("emphasis", "**foo *bar* baz**")
add("emphasis", "*foo*bar*baz*")                                     # intraword *
add("emphasis", "a*b*c")
add("emphasis", "a_b_c")
add("emphasis", "snake_case_word")
add("emphasis", "a * b")                                             # 不配对
add("emphasis", "a*b c")
add("emphasis", "*a b*")
add("emphasis", "**foo*")                                            # rule of 3
add("emphasis", "*foo**")
add("emphasis", "**foo** bar **baz**")
add("emphasis", "*foo *bar* baz*")                                   # opener 内嵌
add("emphasis", "***foo** bar*")                                     # commonmark.js 权威
add("emphasis", "*foo **bar***")
add("emphasis", "*foo _bar* baz_")                                   # removeDelimitersBetween
add("emphasis", "__foo__ bar __baz__")
add("emphasis", "**a *b* c**")
add("emphasis", "*a*b*")
add("emphasis", "*(text)*")
add("emphasis", "**text with spaces**")
add("emphasis", "*")

# ---------------------------------------------------------------- 15. 行内代码
add("code-spans", "`code`")
add("code-spans", "`` code with ` tick ``")
add("code-spans", "`` ` ``")
add("code-spans", "``  ``")
add("code-spans", "`  padded  `")                                    # 两侧空格剥掉
add("code-spans", "`a\nb`")                                          # 代码内换行
add("code-spans", "`*not em*`")
add("code-spans", "`[not link](x)`")
add("code-spans", "`` `a` ``")
add("code-spans", "unmatched ` tick")
add("code-spans", "`\\` backslash in code")

# ---------------------------------------------------------------- 16. 反斜杠转义
add("backslash-escapes", "\\*not em\\*")
add("backslash-escapes", "\\[not link\\](x)")
add("backslash-escapes", "\\`not code\\`")
add("backslash-escapes", "\\\\ literal backslash")
add("backslash-escapes", "\\# not heading")                          # 行首转义
add("backslash-escapes", "\\- not list")
add("backslash-escapes", "\\t not tab escape")                       # B21
add("backslash-escapes", "\\e \\s \\d")
add("backslash-escapes", "\\\\")                                     # 转义对 B23
add("backslash-escapes", "\\\\\nnext")                               # \\+NL 软换行
add("backslash-escapes", "a\\\nb")                                   # 硬换行
add("backslash-escapes", "\\!\\\"\\#\\$\\%\\&\\'\\(\\)\\*\\+\\,\\-\\.\\/\\:\\;\\<\\=\\>\\?\\@\\[\\\\\\]\\^\\_\\`\\{\\|\\}\\~")  # 全 ASCII 标点
add("backslash-escapes", "50\\*50\\*2")

# ---------------------------------------------------------------- 17. 实体
add("entities", "&amp;")
add("entities", "&#65;")
add("entities", "&#x41;")
add("entities", "&nbsp;")
add("entities", "&copy;")
add("entities", "&unknown;")
add("entities", "a &amp; b &lt; c")

# ---------------------------------------------------------------- 18. 行内 HTML
add("inline-html", "<b>bold html</b>")
add("inline-html", "<em>em</em> and *md em*")
add("inline-html", "<span class=\"x\">class span</span>")            # B20
add("inline-html", "<span style=\"color:red\">color span</span>")
add("inline-html", "<span style=\"background:red\">non-color style</span>")
add("inline-html", "<u>underline</u>")
add("inline-html", "text<br>more")
add("inline-html", "text<br/>more")
add("inline-html", "text<br />more")
add("inline-html", "a <sup>1</sup> b")
add("inline-html", "<img src=\"i.png\" alt=\"x\">")
add("inline-html", "html <b>with **md bold**</b> mix")
add("inline-html", "<a href=\"http://x\" title=\"t\">link html</a>")
add("inline-html", "inline <!-- comment --> text")
add("inline-html", "<?php echo 1; ?>")
add("inline-html", "<notatag")
add("inline-html", "<3 not a tag")

# ---------------------------------------------------------------- 19. HTML 块
add("html-blocks", "<div>\nblock html\n</div>")
add("html-blocks", "<script>\nvar x = 1;\n</script>")
add("html-blocks", "<style>\np { color: red }\n</style>")
add("html-blocks", "<!-- comment -->")
add("html-blocks", "<!--\nmulti line\ncomment\n-->")
add("html-blocks", "<pre>\n  preserved\n</pre>")
add("html-blocks", "<textarea>\nx\n</textarea>")
add("html-blocks", "<div class=\"x\">attr div</div>")
add("html-blocks", "<p>para html</p>")
add("html-blocks", "<div>\n\npara after blank\n\n</div>")
add("html-blocks", "<div>")
add("html-blocks", "<table>\n<tr><td>cell</td></tr>\n</table>")
add("html-blocks", "<span>not block</span>")

# ---------------------------------------------------------------- 20. GFM 表格
add("tables-gfm", "| a | b |\n| --- | --- |\n| 1 | 2 |", ref="gfm")
add("tables-gfm", "| left | center | right |\n| :--- | :---: | ---: |\n| 1 | 2 | 3 |", ref="gfm")
add("tables-gfm", "| a | b |\n|---|---|\n| 1 |", ref="gfm")          # 缺格
add("tables-gfm", "| a | b |\n|---|---|\n| 1 | 2 | 3 |", ref="gfm")  # 多格
add("tables-gfm", "| `a|b` | c |\n|---|---|\n| 1 | 2 |", ref="gfm")  # 代码内竖线
add("tables-gfm", "| a \\| b | c |\n|---|---|\n| 1 | 2 |", ref="gfm")# 转义竖线
add("tables-gfm", "| **b** | *i* |\n|---|---|\n| `c` | [l](x) |", ref="gfm")
add("tables-gfm", "| a | b |\n|---|---|\n| x<br>y | 2 |", ref="gfm") # <br> 单元格 B22
add("tables-gfm", "| a | b |\n|---|---|\n| x  \ny | 2 |", ref="gfm") # 真换行 B22
add("tables-gfm", "| only | header |\n|---|---|", ref="gfm")
add("tables-gfm", "a | b\n--- | ---\n1 | 2", ref="gfm")              # 无外框竖线
add("tables-gfm", "| a |\n|---|\n| `|` |", ref="gfm")

# ---------------------------------------------------------------- 21. GFM 删除线
add("strikethrough-gfm", "~~struck~~", ref="gfm")
add("strikethrough-gfm", "~single~", ref="gfm")
add("strikethrough-gfm", "~~with *em* inside~~", ref="gfm")
add("strikethrough-gfm", "~~unclosed")
add("strikethrough-gfm", "a ~~b~~ c", ref="gfm")
add("strikethrough-gfm", "~~~~both~~~~", ref="gfm")

# ---------------------------------------------------------------- 22. GFM 任务框
add("tasklists-gfm", "- [ ] todo\n- [x] done", ref="gfm")
add("tasklists-gfm", "- [X] uppercase done", ref="gfm")
add("tasklists-gfm", "- [ ] **bold** todo", ref="gfm")
add("tasklists-gfm", "1. [ ] ordered task", ref="gfm")
add("tasklists-gfm", "- [ ] parent\n  - [x] child", ref="gfm")
add("tasklists-gfm", "- [ ] task with [link](http://x)", ref="gfm")

# ---------------------------------------------------------------- 23. GFM 扩展 autolink
add("autolink-ext-gfm", "visit www.example.com now", ref="gfm")
add("autolink-ext-gfm", "http://example.com plain", ref="gfm")
add("autolink-ext-gfm", "https://example.com/path", ref="gfm")
add("autolink-ext-gfm", "mail me at foo@bar.com ok", ref="gfm")
add("autolink-ext-gfm", "<https://example.com> explicit", ref="gfm")

# ---------------------------------------------------------------- 24. 硬换行 HTML 形式（主流编辑器通用）
add("breaks-html", "line one<br>line two", ref="gfm")
add("breaks-html", "line one<br>\nline two", ref="gfm")  # B4x：br+换行 = 双换行标记，不再折叠
add("breaks-html", "line one<br>\n\nline two", ref="gfm")            # br + 空行
add("breaks-html", "a<br><br>b", ref="gfm")                          # 双 <br>
add("breaks-html", "para end<br>", ref="gfm")                        # B25
add("breaks-html", "<br> para start", ref="gfm")

# ---------------------------------------------------------------- 25. 组合场景
add("combos", "# heading with **bold** and `code` and [link](http://x)")
add("combos", "> quote with **bold**\n> and `code`")
add("combos", "- list **bold** item\n- [link](http://x) item")
add("combos", "1. numbered **strong**\n2. with *em*")
add("combos", "[**bold link**](http://x)")
add("combos", "[*em link*](http://x)")
add("combos", "[`code link`](http://x)")
add("combos", "![**bold alt**](i.png)")
add("combos", "> - quote list **bold**\n> - second")
add("combos", "- item\n\n  ```\n  code in list\n  ```")
add("combos", "- item\n\n      indented code in list")
add("combos", "1. a\n\n   ```\n   fence in ol\n   ```")
add("combos", "| h1 | h2 |\n|---|---|\n| **b** | `c` |", ref="gfm")
add("combos", "| link | img |\n|---|---|\n| [t](u) | ![a](i) |", ref="gfm")
add("combos", "para\n> lazy quote start\n> continue")
add("combos", "text before\n\n- list\n- after\n\ntext after")
add("combos", "*em with [link](http://x) inside*")
add("combos", "**strong with `code` and ~~strike~~**", ref="gfm")
add("combos", "[link with *em* and **strong**](http://x \"title\")")
add("combos", "> ## heading in quote with *em*")
add("combos", "- [ ] task with ~~strike~~", ref="gfm")
add("combos", "1. first\n2. second\n\n   para in item two")
add("combos", "\\*literal\\* and *real em*")
add("combos", "`code with **stars**` and **real**")

# ---------------------------------------------------------------- 26. 边界与畸形输入
add("edge-cases", "")                                                # 空文档
add("edge-cases", "\n\n\n")                                          # 纯空行
add("edge-cases", " ")                                               # 纯空格
add("edge-cases", "|")                                               # 孤竖线
add("edge-cases", "[")                                               # 孤方括号
add("edge-cases", "](")                                              # 半个链接
add("edge-cases", "![")                                              # 半个图片
add("edge-cases", "<")                                               # 孤尖括号
add("edge-cases", "`")                                               # 孤反引号
add("edge-cases", "*")                                               # 孤星号
add("edge-cases", "_")                                               # 孤下划线
add("edge-cases", "~")                                               # 孤波浪
add("edge-cases", "#")                                               # 孤井号
add("edge-cases", ">")                                               # 孤引用
add("edge-cases", "-")                                               # 孤横线
add("edge-cases", "1.")                                              # 空序号 B0
add("edge-cases", "1)")                                              # 空序号括号
add("edge-cases", "text with  double  spaces")
add("edge-cases", "unicode 你好 **世界** `代码`")
add("edge-cases", "emoji 🎉 in **bold** 🚀")
add("edge-cases", "tab\tinside\ttext")
add("edge-cases", "a\\")
add("edge-cases", "line  \\")

# frontmatter：主流编辑器通用，但不在 CM/GFM 范围 → 只查稳定与逐字
add("frontmatter", "---\ntitle: x\ntags: [a, b]\n---\n\nbody text", check="stable")
add("frontmatter", "---\nkey: value\n---", check="stable")
add("frontmatter", "---\na: 1\n\nb: 2\n---\nbody", check="stable")

# 引用式定义独立成块（主流）
add("definitions", "[ref]: http://example.com\n\nuse [ref]", ref="cm")
add("definitions", "[ref]: /url \"title\"\n\n[ref]", ref="cm")

out = {
    "source": "systematic mainstream Markdown matrix (CommonMark 0.31.2 core + GFM)",
    "version": "round2",
    "count": len(CASES),
    "cases": CASES,
}
path = os.path.join(os.path.dirname(__file__), "..", "tests", "fixtures", "specs", "mainstream-round2.json")
path = os.path.normpath(path)
with open(path, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print(f"wrote {len(CASES)} cases -> {path}")
