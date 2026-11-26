//
//  MarkdownParser.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  Markdown 文本 → NSAttributedString（块级）：
//  # 标题 / > 引用 / ``` 代码块 / --- 分割线 / - 与 1. 列表 / | 表格 | / 段落。
//

import AppKit

enum MarkdownParser {

    /// CommonMark 空白 = 空格 + 制表符。块级判定不能用 .whitespaces：
    /// 那会把 NBSP 等 Unicode 空白也剥掉（`&nbsp;` 整行会被误判成空行丢段）。
    private static let mdWS = CharacterSet(charactersIn: " \t")

    /// 解析整篇 Markdown
    static func parse(_ markdown: String) -> NSMutableAttributedString {
        var text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // UTF-8 BOM 会让首行 frontmatter 的 "---" 判断失效，先剥掉
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // 引用式链接定义 [label]: url "title" 先全量收集，
        // 供行内解析解析 [text][ref] / ![alt][ref] / 快捷式 [ref]。
        InlineParser.references = linkDefinitions(in: text)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let out = NSMutableAttributedString()
        var i = 0
        var nextRawID = 1

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: mdWS)

            // 空行：跳过（Markdown 里只作分隔用）
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // ── 原样透传块：这些写法 FinalMd 不渲染，但必须逐字保住 ──
            // 判定必须排在分割线 / 标题 / 段落之前：frontmatter 的 "---" 本身就是
            // 一条合法分割线，引用式链接定义又长得像普通段落。
            if out.length == 0, let end = frontmatterEnd(in: lines, from: i) {
                out.append(rawBlock(Array(lines[i..<end]), kind: .frontmatter, id: nextRawID))
                nextRawID += 1
                i = end
                continue
            }
            if let end = htmlBlockEnd(in: lines, from: i) {
                out.append(rawBlock(Array(lines[i..<end]), kind: .html, id: nextRawID))
                nextRawID += 1
                i = end
                continue
            }
            if isReferenceDefinition(line) {
                var end = i
                while end < lines.count,
                      isReferenceDefinition(lines[end]) || isDefinitionContinuation(lines[end]) {
                    end += 1
                }
                out.append(rawBlock(Array(lines[i..<end]), kind: .definition, id: nextRawID))
                nextRawID += 1
                i = end
                continue
            }
            // 语法非法但形似定义的行：规范里属于普通段落，不能吞进透传块，
            // 但也不能让 InlineSerializer 把方括号防御性转义掉。
            if isMalformedDefinitionLine(line) {
                out.append(verbatimLineBlock(line))
                i += 1
                continue
            }
            // [TOC] / [TOCM] 目录指令（editor.md / Obsidian / Typora）：整行原样
            // 显示与写回。走普通段落会被防御性转义成 `\[TOC\]`，下游编辑器就
            // 不再识别目录指令了。
            if isTOCDirective(line) {
                out.append(verbatimLineBlock(line))
                i += 1
                continue
            }

            // 缩进代码块（CommonMark 4 空格 / tab）。只在块首识别：段落里出现
            // 缩进行属于 lazy continuation，CommonMark 规定不能打断段落。
            // 也不能抢走「4 空格 + 列表标记」这种嵌套列表项，交给列表分支处理。
            // 判定要在 HTML 块 / 链接定义之后：那两者已自己排除了 4 空格开头。
            if listItemInfo(line) == nil, let end = indentedCodeEnd(in: lines, from: i) {
                out.append(rawBlock(Array(lines[i..<end]), kind: .indentedCode, id: nextRawID))
                nextRawID += 1
                i = end
                continue
            }

            // 围栏代码块：开栏 3+ 个同类反引号 / 波浪号，收尾栏长度不少于开栏。
            // 内容里的短围栏行（如 ``` 里嵌 ```）不能提前收块，
            // 否则一轮就把内容截断、下一轮再换一种拆法，永远不收敛。
            // CommonMark：反引号围栏的 info 串不允许再含反引号——
            // "``` ```" 这样的行不是围栏，要落到段落里当行内代码解析。
            if let (fenceChar, fenceLen, language) = fenceStart(trimmed) {
                // 开栏行前导空格（0...3）：内容行各剥掉至多这么多前导空格（CommonMark）
                let fenceIndent = line.prefix(while: { $0 == " " }).count
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: mdWS)
                    if t.count >= fenceLen, t.allSatisfy({ $0 == fenceChar }) { break }
                    var content = lines[i]
                    let n = min(content.prefix(while: { $0 == " " }).count, fenceIndent)
                    content = String(content.dropFirst(n))
                    body.append(content)
                    i += 1
                }
                i += 1 // 跳过收尾围栏
                // 内容按「每行 + 换行」拼（CommonMark 代码内容含行尾换行），空块保持空
                out.append(codeBlock(body.map { $0 + "\n" }.joined(), language: language))
                continue
            }

            // 分割线
            if isHorizontalRule(trimmed) {
                out.append(horizontalRule())
                i += 1
                continue
            }

            // 标题
            if let (level, content) = heading(from: trimmed) {
                out.append(headingBlock(content, level: level))
                i += 1
                continue
            }

            // 表格（GFM）：第 2 行必须是分隔行，且与首行格数一致；行可以没有
            // 外框竖线（`a | b` 形式）。`|` 单独一行没有分隔行，是普通段落。
            if isTableStart(lines, at: i) {
                var block: [String] = [lines[i], lines[i + 1]]
                i += 2
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: mdWS)
                    if t.isEmpty { break }
                    if fenceStart(t) != nil || isHorizontalRule(t) || heading(from: t) != nil
                        || t.hasPrefix(">") || listInterrupts(lines[i])
                        || isReferenceDefinition(lines[i]) || isMalformedDefinitionLine(lines[i])
                        || htmlBlockEnd(in: lines, from: i, interruptParagraph: false) != nil {
                        break
                    }
                    block.append(lines[i])
                    i += 1
                }
                out.append(tableBlock(block))
                continue
            }

            // 引用 / Obsidian Callout
            if trimmed.hasPrefix(">") {
                var body: [String] = []
                var rawLines: [String] = []   // 原始行（含 `>` 标记），逐字写回用
                while i < lines.count, lines[i].trimmingCharacters(in: mdWS).hasPrefix(">") {
                    rawLines.append(lines[i])
                    var l = lines[i].trimmingCharacters(in: mdWS)
                    l = String(l.dropFirst())
                    if l.hasPrefix(" ") { l = String(l.dropFirst()) }
                    body.append(l)
                    i += 1
                }
                // 懒续行（CommonMark）：引用段落的延续行不带 `>` 也并入引用，
                // 空行或任何块级开始行终止。
                lazy: while i < lines.count {
                    let raw = lines[i]
                    let t = raw.trimmingCharacters(in: mdWS)
                    if t.isEmpty || t.hasPrefix(">") { break lazy }
                    if fenceStart(t) != nil || isHorizontalRule(t) || heading(from: t) != nil
                        || listInterrupts(raw) || isTableStart(lines, at: i)
                        || isReferenceDefinition(raw) || isMalformedDefinitionLine(raw)
                        || htmlBlockEnd(in: lines, from: i, interruptParagraph: false) != nil {
                        break lazy
                    }
                    rawLines.append(raw)
                    body.append(t)
                    i += 1
                }
                if let info = calloutInfo(body.first) {
                    out.append(calloutBlock(body, kind: info.kind, fold: info.fold, id: nextRawID))
                    nextRawID += 1
                } else {
                    out.append(quoteBlock(body.joined(separator: "\n"),
                                          raw: rawLines.joined(separator: "\n")))
                }
                continue
            }

            // 列表（含 CommonMark 容器块：项内缩进代码块 / 引用 / 嵌套源码）。
            // 缩进续行不能 trim 后拼进列表文本：storage 里一个段落就是一个列表项，
            // 拼接会让它被序列化成多个 "- " 行，既丢内容又丢原始缩进。
            // 正确做法是把原始行挂在所属列表项下面，按 raw 机制逐字写回。
            if listItemInfo(line) != nil {
                var items: [ListEntry] = []
                var contentIndent = 2
                // 项内围栏块透传状态：围栏开栏后所有行（含空行）原样进 raw，
                // 不能让围栏内容被当成懒续行并进项文本。
                var openFence: (char: Character, len: Int)?
                while i < lines.count {
                    let l = lines[i]
                    if let info = listItemInfo(l) {
                        // 标记逐字保留（"8." 不重排成 "1."、"*" 不统一成 "-"）：
                        // 重排会改写内容，且有序列表的起始序号在 CommonMark 里有意义。
                        items.append(ListEntry(marker: info.marker,
                                               content: info.content,
                                               level: info.level,
                                               indent: info.indent))
                        contentIndent = info.contentIndent
                        i += 1
                        continue
                    }
                    // 空行后紧跟「项内缩进代码块」时，空行属于同一个列表项：
                    // 不能在这里 break，否则列表被拆成两段，有序编号会重新从 1 开始。
                    if l.trimmingCharacters(in: mdWS).isEmpty {
                        var k = i
                        while k < lines.count,
                              lines[k].trimmingCharacters(in: mdWS).isEmpty { k += 1 }
                        if k < lines.count, !items.isEmpty {
                            let nextTrim = lines[k].trimmingCharacters(in: mdWS)
                            let nextIndented = lines[k].hasPrefix(" ") || lines[k].hasPrefix("\t")
                            let nextCode = isListItemIndentedCode(lines[k], contentIndent: contentIndent)
                            let nextFence = openFence != nil || (nextIndented && fenceStart(nextTrim) != nil)
                            let nextQuote = nextIndented && nextTrim.hasPrefix(">")
                            // 空行后是项内嵌块（围栏 / 引用 / 缩进代码）：
                            // 空行随 raw 块走，保住「块内空行」的逐字写回。
                            if nextFence || nextCode || nextQuote {
                                let kind: MDRawKind = nextCode
                                    ? listIndentedKind(lines[k], contentIndent: contentIndent)
                                    : .listIndented
                                for _ in i..<k { items[items.count - 1].lines.append(("", kind)) }
                                i = k
                                continue
                            }
                            // 松散列表：空行 + 缩进纯文字段落并入当前项内容（CommonMark
                            // 的 lazy continuation），空行按内容空行原样并入，未编辑时
                            // 快照逐字写回。嵌套列表仍交给上面的 listItemInfo 分支。
                            if nextIndented, listItemInfo(lines[k]) == nil {
                                for _ in i..<k { items[items.count - 1].content += "\n" }
                                i = k
                                continue
                            }
                        }
                        break
                    }
                    if (l.hasPrefix(" ") || l.hasPrefix("\t")), !items.isEmpty {
                        // 续行分类（CommonMark）：纯文本续行并入项内容（懒续行），
                        // 语义上是同一段落的延续；引用 / 围栏 / 深层缩进代码保持
                        // raw 透传，交由 HTML 渲染归属到所属列表项。
                        let trimmedCont = l.trimmingCharacters(in: mdWS)
                        let kind = listIndentedKind(l, contentIndent: contentIndent)
                        if openFence != nil {
                            // 围栏块内：逐行透传，收尾栏清状态
                            items[items.count - 1].lines.append((l, kind == .listCode ? .listCode : .listIndented))
                            if let fence = openFence, trimmedCont.count >= fence.len,
                               trimmedCont.allSatisfy({ $0 == fence.char }) {
                                openFence = nil
                            }
                        } else if kind != .listCode, !trimmedCont.hasPrefix(">"),
                                  let fence = fenceStart(trimmedCont) {
                            items[items.count - 1].lines.append((l, .listIndented))
                            openFence = (fence.char, fence.len)
                        } else if kind != .listCode, !trimmedCont.hasPrefix(">") {
                            // 空内容项的首个续行直接成内容，不带换行（`-\n  x` → "x"）
                            if items[items.count - 1].content.isEmpty {
                                items[items.count - 1].content = l
                            } else {
                                items[items.count - 1].content += "\n" + l
                            }
                        } else {
                            items[items.count - 1].lines.append((l, kind))
                        }
                        i += 1
                        continue
                    }
                    break
                }
                out.append(listBlock(items, rawID: &nextRawID))
                continue
            }

            // 普通段落：一直吃到空行或下一个块级开始
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: mdWS)
                if t.isEmpty { break }
                // Setext 标题下划线（CommonMark §4.3）：段落行 + 纯 `=`/`-` 行。
                // 优先于分割线 / 列表判定——`Foo\n---` 是 h2，不是段落+hr。
                // 多行内容用空格连接（标题序列化是单行 ATX 形式）。
                // CommonMark §4.3：Setext 下划线最多缩进 3 列；4 列及以上是缩进代码，
                // 而缩进代码不能打断段落，所以 `Foo\n    ---` 是段落内的字面 `---`。
                if !para.isEmpty, expandedIndent(l) <= 3, let lvl = setextLevel(t) {
                    let title = para.joined(separator: " ")
                        .trimmingCharacters(in: mdWS)
                    out.append(headingBlock(title, level: lvl))
                    para = []
                    i += 1
                    break
                }
                if fenceStart(t) != nil || isTableStart(lines, at: i) || t.hasPrefix(">")
                    || isHorizontalRule(t) || heading(from: t) != nil || listInterrupts(l)
                    || isReferenceDefinition(l) || isMalformedDefinitionLine(l)
                    || htmlBlockEnd(in: lines, from: i, interruptParagraph: false) != nil {
                    break
                }
                para.append(l)
                i += 1
            }
            if !para.isEmpty {
                out.append(paragraphBlock(para.joined(separator: "\n")))
            }
        }

        return out
    }

    /// 全文提取引用式链接定义：`[label]: url "title"`（title 可用 ' 或 () 包裹）。
    /// 键按 CommonMark 规范化（空白折叠 + 小写）；同名定义取第一个。
    /// destination + title 用与行内链接同一套严格解析：尾部杂字、无空白分隔的
    /// title、尖括号目标里的裸 `<`/`>`，任一不符即整条定义失效（CommonMark §4.7），
    /// 落回普通段落文本。`^`/`#`/`>` 开头的标签是脚注 / 引文 / 缩写扩展定义，
    /// 冒号后是自由文本，绝不能进链接表。
    private static func linkDefinitions(in text: String)
        -> [String: (url: String, title: String)] {
        var out: [String: (url: String, title: String)] = [:]
        for line in text.components(separatedBy: "\n") {
            var idx = line.startIndex
            var spaces = 0
            while idx < line.endIndex, line[idx] == " ", spaces < 3 {
                spaces += 1; idx = line.index(after: idx)
            }
            guard spaces <= 3, idx < line.endIndex, line[idx] == "[" else { continue }
            guard let br = line[idx...].firstIndex(of: "]") else { continue }
            let label = String(line[line.index(after: idx)..<br])
            guard !label.isEmpty else { continue }
            if label.hasPrefix("^") || label.hasPrefix("#") || label.hasPrefix(">") { continue }
            var q = line.index(after: br)
            guard q < line.endIndex, line[q] == ":" else { continue }
            q = line.index(after: q)
            guard let parsed = InlineParser.parseLinkDestination(String(line[q...])) else { continue }
            let key = InlineParser.normalizeLabel(label)
            if out[key] == nil { out[key] = (parsed.url, parsed.title) }
        }
        return out
    }

    // MARK: - 行判定

    /// 围栏开栏行：3+ 个同类反引号 / 波浪号。CommonMark 规定反引号围栏的
    /// info 串不允许再含反引号（"``` ```" 不是围栏，是行内代码）——
    /// 外层围栏分支与段落打断判定必须同口径，否则该行两边都不收、死循环。
    private static func fenceStart(_ t: String) -> (char: Character, len: Int, info: String)? {
        guard t.hasPrefix("```") || t.hasPrefix("~~~") else { return nil }
        let fenceChar = t.first!
        let fenceLen = t.prefix(while: { $0 == fenceChar }).count
        let info = String(t.dropFirst(fenceLen)).trimmingCharacters(in: mdWS)
        if fenceChar == "`", info.contains("`") { return nil }
        return (fenceChar, fenceLen, info)
    }

    private static func isHorizontalRule(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: " ", with: "")
        guard t.count >= 3 else { return false }
        let set = Set(t)
        guard set.count == 1 else { return false }
        return set == ["-"] || set == ["*"] || set == ["_"]
    }

    // MARK: - Obsidian Callout 判定

    private struct CalloutInfo {
        let kind: String
        let fold: String
    }

    /// 首行形如 `[!NOTE] 标题` / `[!TIP]- 可折叠` / `[!WARNING]+ 展开`。
    /// 只认「引用块第一行」，且类型名必须是字母数字；`[!]`、`[!NOTE` 这类
    /// 不完整的写法仍按普通引用处理，避免误伤 CommonMark 规范用例。
    private static func calloutInfo(_ line: String?) -> CalloutInfo? {
        guard let line else { return nil }
        let t = line.trimmingCharacters(in: mdWS)
        guard t.hasPrefix("[!"), let close = t.firstIndex(of: "]") else { return nil }
        let name = String(t[t.index(t.startIndex, offsetBy: 2)..<close])
        guard !name.isEmpty,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        let after = t.index(after: close)
        var fold = ""
        if after < t.endIndex, t[after] == "+" || t[after] == "-" {
            fold = String(t[after])
        }
        return CalloutInfo(kind: name.uppercased(), fold: fold)
    }

    // MARK: - 原样透传块判定

    private static func isATXHeading(_ t: String) -> Bool {
        t.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil
    }

    /// YAML / TOML frontmatter：只在文档开头识别，返回「块结束后的行号」（exclusive）。
    /// 必须有闭合分隔符且块内至少有一行 `key: value` / `key = value`，
    /// 否则会把「两条分割线夹着一段正文」误判成 frontmatter。
    /// 非 private：兼容性测试的逐字透传比对（exactPassthrough）直接调用本判定，
    /// 保证检测口径与解析口径永远一致。
    static func frontmatterEnd(in lines: [String], from start: Int) -> Int? {
        guard start < lines.count else { return nil }
        let open = lines[start].trimmingCharacters(in: mdWS)
        guard open == "---" || open == "+++" else { return nil }
        let close = open

        var j = start + 1
        var sawKey = false
        while j < lines.count, j - start <= 300 {
            let rawLine = lines[j]
            let t = rawLine.trimmingCharacters(in: mdWS)
            if t == close || (open == "---" && t == "...") {
                return sawKey ? j + 1 : nil
            }
            if t.isEmpty { j += 1; continue }

            if isATXHeading(t) {
                // 块里已经出现 key，多半是 YAML 注释；否则就是 Markdown 标题，不是元数据
                if !sawKey { return nil }
            } else if t.hasPrefix("```") || t.hasPrefix("~~~")
                        || t.hasPrefix("|") || t.hasPrefix(">")
                        || rawLine.range(of: #"^[-*+]\s+\S"#, options: .regularExpression) != nil {
                return nil
            }
            // key 判定：YAML 映射的冒号后必须有空白或行尾（`a:b` 是纯量不是 key），
            // TOML 的 `=` 则不强制空格。旧写法 `[:=]\s*\S?` 会把 `__Advertisement :)__`
            // 里的笑脸冒号、`https://` 里的协议冒号误认成 key，把正文吞成元数据。
            if t.range(of: #"^[A-Za-z_][A-Za-z0-9_.\- ]*(?::(\s|$)|=)"#,
                       options: .regularExpression) != nil {
                sawKey = true
            }
            j += 1
        }
        return nil
    }

    /// CommonMark 里可开启 HTML 块的块级标签
    private static let htmlBlockTags: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body",
        "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir",
        "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
        "frame", "frameset", "head", "header", "hr", "html", "iframe", "legend",
        "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol",
        "optgroup", "option", "p", "param", "pre", "script", "search", "section",
        "style", "summary", "table", "tbody", "td", "textarea", "tfoot", "th",
        "thead", "title", "tr", "track", "ul", "h1", "h2", "h3", "h4", "h5", "h6",
    ]

    private static func htmlTagName(_ t: String) -> String? {
        var s = t.dropFirst()                 // 去掉 "<"
        if s.hasPrefix("/") { s = s.dropFirst() }
        var name = ""
        for ch in s {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" { name.append(ch) } else { break }
        }
        return name.isEmpty ? nil : name.lowercased()
    }

    private static func isASCIILetter(_ c: Character) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z")
    }

    private static func isASCIIDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }

    /// CommonMark type 1：`<script>` / `<pre>` / `<style>` / `<textarea>` 这类块
    /// 结束在对应闭标签所在行，而不是空行——否则 `</style>` 后面的正文会被一起吞掉。
    private static func type1ClosingTag(for t: String) -> String? {
        let lower = t.lowercased()
        for tag in ["script", "pre", "style", "textarea"] {
            if lower.hasPrefix("<\(tag)") {
                let after = lower.dropFirst(tag.count + 1).first
                if after == ">" || after == " " || after == "\t" || after == nil {
                    return "</\(tag)>"
                }
            }
        }
        return nil
    }

    /// CommonMark type 7：整行必须恰好是一个**语法完整**的开标签 / 闭标签。
    /// 只看尖括号会误伤 `<m:abc>`、`<a href='bar'title=title>`、`</a href="foo">`
    /// 这类非法写法——规范里它们是普通段落里的转义文本，不是 HTML 块。
    private static func isValidStandaloneTag(_ t: String) -> Bool {
        let c = Array(t)
        var p = 0
        func ws() { while p < c.count, c[p] == " " || c[p] == "\t" { p += 1 } }
        func take(_ s: String) -> Bool {
            let a = Array(s)
            guard p + a.count <= c.count else { return false }
            for (k, ch) in a.enumerated() where c[p + k] != ch { return false }
            p += a.count
            return true
        }
        guard take("<") else { return false }
        let closing = take("/")
        guard p < c.count, isASCIILetter(c[p]) else { return false }
        p += 1
        while p < c.count, isASCIILetter(c[p]) || isASCIIDigit(c[p]) || c[p] == "-" { p += 1 }

        if closing {
            ws()
            guard take(">") else { return false }
            ws()
            return p == c.count
        }

        while true {
            let before = p
            ws()
            guard p < c.count else { return false }
            if c[p] == ">" {
                p += 1
                ws()
                return p == c.count
            }
            if c[p] == "/" {
                p += 1
                guard p < c.count, c[p] == ">" else { return false }
                p += 1
                ws()
                return p == c.count
            }
            guard p > before else { return false }   // 属性之间必须有空白
            guard p < c.count, isASCIILetter(c[p]) || c[p] == "_" || c[p] == ":" else { return false }
            p += 1
            while p < c.count, isASCIILetter(c[p]) || isASCIIDigit(c[p])
                    || c[p] == "_" || c[p] == "." || c[p] == ":" || c[p] == "-" { p += 1 }
            let nameEnd = p
            ws()
            if p < c.count, c[p] == "=" {
                p += 1
                ws()
                guard p < c.count else { return false }
                if c[p] == "\"" || c[p] == "'" {
                    let quote = c[p]
                    p += 1
                    var closed = false
                    while p < c.count {
                        if c[p] == quote { closed = true; p += 1; break }
                        if c[p] == "<" { return false }
                        p += 1
                    }
                    guard closed else { return false }
                } else {
                    let valueStart = p
                    while p < c.count, c[p] != " " && c[p] != "\t" && c[p] != "\""
                            && c[p] != "'" && c[p] != "=" && c[p] != "<" && c[p] != ">"
                            && c[p] != "`" { p += 1 }
                    guard p > valueStart else { return false }
                }
            } else {
                p = nameEnd   // 布尔属性：没有 = value
            }
        }
    }

    /// 原始 HTML 块：返回块结束后的行号（exclusive），nil 表示这一行不是 HTML 块起点。
    /// 注释 / 处理指令 / CDATA / 声明吃到结束标记；块级标签吃到空行为止
    /// （CommonMark type 1–6）。type 7（整行恰好是一个完整标签，如 `<img ... />`）
    /// 只能在块首出现，不能打断已经开始的普通段落。
    private static func htmlBlockEnd(in lines: [String], from start: Int,
                                     interruptParagraph: Bool = true) -> Int? {
        guard start < lines.count else { return nil }
        let line = lines[start]
        let leading = line.prefix(while: { $0 == " " }).count
        guard leading <= 3 else { return nil }   // 4 空格开头是缩进代码块
        let t = String(line.dropFirst(leading)).trimmingCharacters(in: mdWS)
        guard t.hasPrefix("<") else { return nil }

        // type 1 优先：以闭标签所在行收尾，别把后面的 Markdown 正文吞进来
        if let closingTag = type1ClosingTag(for: t) {
            var j = start
            while j < lines.count {
                if lines[j].lowercased().contains(closingTag) { return j + 1 }
                j += 1
                if j - start > 200 { return j }
            }
            return lines.count
        }

        let terminator: String?
        if t.hasPrefix("<!--") { terminator = "-->" }
        else if t.hasPrefix("<?") { terminator = "?>" }
        else if t.hasPrefix("<![CDATA[") { terminator = "]]>" }
        else if t.hasPrefix("<!") { terminator = ">" }
        else { terminator = nil }

        if let terminator {
            var j = start
            while j < lines.count {
                if lines[j].contains(terminator) { return j + 1 }
                j += 1
                if j - start > 200 { return j }   // 没闭合时也别无限吞
            }
            return lines.count
        }

        guard let name = htmlTagName(t) else { return nil }
        if !htmlBlockTags.contains(name) {
            // 行内 / 自定义标签：只在「整行恰好一个合法标签」且处于块首时开启
            guard interruptParagraph, isValidStandaloneTag(t) else { return nil }
        }

        var j = start
        while j < lines.count, !lines[j].trimmingCharacters(in: mdWS).isEmpty {
            j += 1
            if j - start > 400 { break }
        }
        return j
    }

    /// 「长得像引用式链接定义、但语法不合法」的整行。
    ///
    /// 例：cmark-gfm 语料里 30 个 `[` 的 `[[[[…[[]: this is not a valid reference`，
    /// 以及 pandoc 里 title 含未转义双引号的 `  [bar]: /url/ "Title with "quotes" inside"`。
    /// 按 CommonMark 它们都是普通段落，不能塞进 `.definition` 透传块，否则官方规范
    /// 用例的结构识别会掉；但按普通段落走 InlineSerializer 又会把 `[` `]` 转义成
    /// `\[` `\]`，改写原文。这里单独标记为「逐字段落」：块类型仍是 paragraph，
    /// 显示文字就是原行，序列化时整行原样写出。
    private static func isMalformedDefinitionLine(_ line: String) -> Bool {
        guard !isReferenceDefinition(line) else { return false }
        let leading = line.prefix(while: { $0 == " " }).count
        guard leading <= 3 else { return false }
        let t = String(line.dropFirst(leading))
        guard t.hasPrefix("["), let close = t.firstIndex(of: "]") else { return false }
        let afterClose = t.index(after: close)
        guard afterClose < t.endIndex, t[afterClose] == ":" else { return false }
        let rest = String(t[t.index(after: afterClose)...])
        return !rest.trimmingCharacters(in: mdWS).isEmpty
    }

    /// 引用式链接定义 / 脚注定义：`[label]: destination "title"`
    /// 必须完整校验 destination 与可选的 title：像 `[foo]: /url "title" ok`
    /// 这种尾部带杂字的写法在规范里是普通段落，不能当成定义吞进透传块。
    private static func isReferenceDefinition(_ line: String) -> Bool {
        let leading = line.prefix(while: { $0 == " " }).count
        guard leading <= 3 else { return false }
        let t = String(line.dropFirst(leading))
        guard t.hasPrefix("["), let close = t.firstIndex(of: "]") else { return false }
        let label = String(t[t.index(after: t.startIndex)..<close])
        guard !label.isEmpty, !label.contains("["), !label.contains("]") else { return false }
        let afterClose = t.index(after: close)
        guard afterClose < t.endIndex, t[afterClose] == ":" else { return false }
        let rest = String(t[t.index(after: afterClose)...]).trimmingCharacters(in: mdWS)
        guard !rest.isEmpty else { return false }
        // 脚注 / 引文 / 缩写是 Pandoc、MultiMarkdown、Obsidian 的扩展定义，
        // 冒号后面是自由文本而不是 URL，不能用标准链接定义的规则去卡。
        let extendedLabel = label.hasPrefix("^") || label.hasPrefix("#") || label.hasPrefix(">")
        return extendedLabel || isValidDefinitionBody(rest)
    }

    /// destination（`<...>` 或不含空白的一串）+ 可选 title + 可选扩展属性，之后不允许再有内容
    private static func isValidDefinitionBody(_ body: String) -> Bool {
        let c = Array(body)
        var p = 0
        func ws() { while p < c.count, c[p] == " " || c[p] == "\t" { p += 1 } }
        func readValue() -> Bool {
            guard p < c.count else { return false }
            if c[p] == "\"" || c[p] == "'" {
                let quote = c[p]
                p += 1
                while p < c.count {
                    if c[p] == quote { p += 1; return true }
                    if c[p] == "\n" { return false }
                    p += 1
                }
                return false
            }
            let start = p
            while p < c.count, c[p] != " " && c[p] != "\t" && c[p] != "\""
                    && c[p] != "'" && c[p] != "=" && c[p] != "<" && c[p] != ">"
                    && c[p] != "`" { p += 1 }
            return p > start
        }

        if c[p] == "<" {
            p += 1
            while p < c.count, c[p] != ">" {
                if c[p] == "<" || c[p] == "\n" { return false }
                p += 1
            }
            guard p < c.count else { return false }
            p += 1
        } else {
            let start = p
            var depth = 0
            while p < c.count, c[p] != " " && c[p] != "\t" {
                if c[p] == "\\", p + 1 < c.count { p += 2; continue }
                if c[p] == "(" { depth += 1 }
                else if c[p] == ")" { depth -= 1; if depth < 0 { return false } }
                p += 1
            }
            guard p > start, depth == 0 else { return false }
        }

        ws()
        if p == c.count { return true }

        // 可选 title："..." / '...' / (...)
        if c[p] == "\"" || c[p] == "'" || c[p] == "(" {
            let closing: Character = c[p] == "(" ? ")" : c[p]
            p += 1
            var closed = false
            while p < c.count {
                if c[p] == closing { closed = true; p += 1; break }
                if c[p] == "\n" { return false }
                p += 1
            }
            guard closed else { return false }
        }

        // MultiMarkdown 扩展：title 之后还能跟 width="3in" height="2.4in" 这类属性。
        // 但 `[foo]: /url "title" ok` 这种无等号的杂字仍会被拒绝（规范里是普通段落）。
        while true {
            ws()
            if p == c.count { return true }
            guard isASCIILetter(c[p]) || c[p] == "_" || c[p] == ":" else { return false }
            p += 1
            while p < c.count, isASCIILetter(c[p]) || isASCIIDigit(c[p])
                    || c[p] == "_" || c[p] == "." || c[p] == ":" || c[p] == "-" { p += 1 }
            ws()
            guard p < c.count, c[p] == "=" else { return false }
            p += 1
            ws()
            guard readValue() else { return false }
        }
    }

    /// 定义行的下一行可以是缩进的 title，也要一起保住
    private static func isDefinitionContinuation(_ line: String) -> Bool {
        guard line.first == " " || line.first == "\t" else { return false }
        let t = line.trimmingCharacters(in: mdWS)
        guard !t.isEmpty else { return false }
        return (t.hasPrefix("\"") && t.hasSuffix("\""))
            || (t.hasPrefix("'") && t.hasSuffix("'"))
            || (t.hasPrefix("(") && t.hasSuffix(")"))
    }

    /// CommonMark 缩进代码块：一行以 4 个空格 / tab 开头即可开启，
    /// 后续缩进行与块内空行都属于同一块；遇到第一个非缩进非空行结束。
    /// 返回块结束后的行号（exclusive），尾部空行不并入（否则每往返一次多一空行）。
    private static func indentedCodeEnd(in lines: [String], from start: Int) -> Int? {
        guard start < lines.count, isIndentedCodeLine(lines[start]) else { return nil }
        var j = start
        var lastContent = start
        var sawContent = false
        while j < lines.count {
            let line = lines[j]
            if line.trimmingCharacters(in: mdWS).isEmpty {
                j += 1
                continue
            }
            guard isIndentedCodeLine(line) else { break }
            sawContent = true
            lastContent = j
            j += 1
        }
        return sawContent ? lastContent + 1 : nil
    }

    private static func isIndentedCodeLine(_ line: String) -> Bool {
        // CommonMark §4.4：前导空白按 4 列 tab 展开，达到 4 列即缩进代码块。
        // `  \tfoo` 这类「空格 + tab」也必须按列数判定，不能只看行首字符。
        // 块首的 `> ...` 即使内容以 > 开头也是代码（4 空格缩进优先于容器记号）；
        // 列表项内的嵌套引用走 listIndentedKind 的 containerStart 单独排除，不受影响。
        guard !line.trimmingCharacters(in: mdWS).isEmpty else { return false }
        return expandedIndent(line) >= 4
    }

    /// 把整块原始行原封不动放进 storage：不走 InlineParser，也不做任何转义。
    /// 每一行（含空行）都带同一个 blockID，序列化时据此拼回一整块。
    private static func rawBlock(_ lines: [String], kind: MDRawKind, id: Int) -> NSAttributedString {
        // split(omittingEmptySubsequences:false) 会在文件末尾多出一个空串；
        // 未闭合的 HTML 块吃到 EOF 时会把它一起带进来，导致每往返一次就多一个空行。
        // 块内部的空行要保留，只剥掉尾部空行。
        var content = lines
        while let last = content.last, last.trimmingCharacters(in: mdWS).isEmpty {
            content.removeLast()
        }
        guard !content.isEmpty else { return NSAttributedString() }
        let style = DocTheme.paragraphStyle(for: .raw)
        if kind == .indentedCode || kind == .listCode { style.textBlocks = [DocTheme.codeTextBlock] }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.monospacedFont(size: DocTheme.codeFontSize),
            .paragraphStyle: style,
            .foregroundColor: DocTheme.textDim,
            .mdBlockType: MDBlockType.raw.rawValue,
            .mdRawKind: kind.rawValue,
            .mdRawID: id,
        ]
        let out = NSMutableAttributedString()
        for line in content {
            out.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }
        return out
    }

    private static func heading(from line: String) -> (Int, String)? {
        var hashes = 0
        for ch in line {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard (1...6).contains(hashes) else { return nil }
        let rest = String(line.dropFirst(hashes))
        // CommonMark §4.2：# 序列后必须是空格 / tab 或行尾。
        // `#no`、`#1 x` 是普通段落，不是标题。
        if !rest.isEmpty, !rest.hasPrefix(" "), !rest.hasPrefix("\t") { return nil }
        var content = rest
        while content.hasPrefix(" ") || content.hasPrefix("\t") {
            content = String(content.dropFirst())
        }
        // 可选的闭合 # 串：必须以空格 / tab 分隔（或整段都是 #），其后只允许空白。
        content = stripClosingHashes(content)
        return (hashes, content)
    }

    /// 剥掉 ATX 标题的闭合 # 串（CommonMark §4.2）。
    /// `# closed heading #` → `closed heading`；`## a ##extra` 不受影响。
    private static func stripClosingHashes(_ s: String) -> String {
        var t = s
        while t.hasSuffix(" ") || t.hasSuffix("\t") { t = String(t.dropLast()) }
        guard t.hasSuffix("#") else { return t }
        var idx = t.endIndex
        while idx > t.startIndex, t[t.index(before: idx)] == "#" {
            idx = t.index(before: idx)
        }
        if idx == t.startIndex { return "" }          // `# #` / `###` 整段都是 #
        let before = t[t.index(before: idx)]
        // 闭合串前面必须是空白；`a#b#` 里的 # 是内容
        if before == " " || before == "\t" {
            var head = String(t[..<idx])
            while head.hasSuffix(" ") || head.hasSuffix("\t") { head = String(head.dropLast()) }
            return head
        }
        return t
    }

    /// Setext 标题下划线（CommonMark §4.3）：纯 `=`+ 或纯 `-`+ 行。
    /// 返回标题层级（= → 1，- → 2）。`- item` 这类带内容的行不是下划线。
    private static func setextLevel(_ t: String) -> Int? {
        if t.isEmpty { return nil }
        if t.allSatisfy({ $0 == "=" }) { return 1 }
        if t.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    /// 列表项能否打断段落：空项（`-` 独占一行）不打断（CommonMark §5.3）。
    private static func listInterrupts(_ line: String) -> Bool {
        guard let inf = listItemInfo(line) else { return false }
        return !inf.content.isEmpty
    }

    private struct ListInfo {
        let ordered: Bool
        let level: Int
        let content: String
        /// 列表标记前的原始前导空格数（写回时保住 4 空格缩进的嵌套列表项）
        let indent: Int
        /// 列表项内容起始列。缩进 >= contentIndent + 4 的行才是
        /// CommonMark 意义上的「列表项内缩进代码块」。
        let contentIndent: Int
        /// 原始列表标记（"8." / "8)" / "-" / "*" / "+"）。往返必须逐字保留：
        /// 重排编号会把 `8. 第八项` 改写成 `1. 第八项`，既是内容损坏，
        /// 也让有序列表的起始序号在 CommonMark 渲染里变掉。
        let marker: String
    }

    /// 一个列表项：正文 + 属于它的缩进容器块原始行。
    private struct ListEntry {
        var marker: String
        var content: String
        var level: Int
        var indent: Int
        var lines: [(String, MDRawKind)] = []
    }

    private static func listItemInfo(_ line: String) -> ListInfo? {
        let leading = line.prefix(while: { $0 == " " }).count
        let rest = String(line.dropFirst(leading))
        guard !rest.isEmpty else { return nil }

        var ordered = false
        var markerText = ""

        // 空列表项：`-` / `*` / `+` 独占一行也是合法项（CommonMark §5.3）
        if rest == "-" || rest == "*" || rest == "+" {
            markerText = rest
        } else if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            markerText = String(rest.prefix(1))
        } else if let delim = rest.firstIndex(where: { $0 == "." || $0 == ")" }),
                  delim > rest.startIndex {
            // CommonMark §5.3：有序标记 = 数字 + `.` 或 `)`。必须用「全行第一个
            // `.`/`)`」做定界符再校验数字——旧写法先找 `.`、内层校验失败后因
            // else-if 跳过 `)` 分支，像 `1)  The ...(https://mermaid.live/)` 这种
            // URL 带点的 `)` 列表项会被误判成普通段落（quarto 006 的 4 个有序项
            // 全部被转义成 `1\)`）。
            let numPart = String(rest[rest.startIndex..<delim])
            // "1." 这种只有序号、没有后续空格的行：index(after:) 会等于 endIndex，
            // 直接用 rest[endIndex] 取值会触发 String 索引越界崩溃。
            let after = rest.index(after: delim)
            if !numPart.isEmpty, numPart.allSatisfy(\.isNumber),
               after == rest.endIndex || rest[after] == " " {
                ordered = true
                markerText = String(rest[rest.startIndex...delim])
            }
        }

        guard !markerText.isEmpty else { return nil }
        let markerLength = markerText.count + 1
        let content = String(rest.dropFirst(markerLength))
        let level: Int
        if leading >= 4, leading % 4 == 0 {
            level = leading / 4
        } else {
            level = leading / 2
        }
        return ListInfo(ordered: ordered, level: level, content: content,
                        indent: leading, contentIndent: leading + markerLength,
                        marker: markerText)
    }

    /// 前导空白按 CommonMark 的列数展开：tab 补齐到下一个 4 列边界。
    private static func expandedIndent(_ line: String) -> Int {
        var col = 0
        for ch in line {
            if ch == " " { col += 1 }
            else if ch == "\t" { col += 4 - (col % 4) }
            else { break }
        }
        return col
    }

    /// 列表项内的缩进行分类：
    /// - 缩进 >= 内容缩进 + 4，且不是引用 / 嵌套列表 / 围栏等容器块起始 → 缩进代码块
    /// - 其余（引用续行、Logseq 属性行、嵌套源码）→ 普通缩进容器内容
    /// 两者都按原始行逐字保留，区别只在结构识别与 HTML 导出。
    private static func listIndentedKind(_ line: String, contentIndent: Int) -> MDRawKind {
        let t = line.trimmingCharacters(in: mdWS)
        let containerStart = t.hasPrefix(">") || t.hasPrefix("#") || t.hasPrefix("|")
            || t.hasPrefix("```") || t.hasPrefix("~~~") || isHorizontalRule(t)
            || listItemInfo(line) != nil
        if expandedIndent(line) >= contentIndent + 4, !containerStart { return .listCode }
        return .listIndented
    }

    private static func isListItemIndentedCode(_ line: String, contentIndent: Int) -> Bool {
        listIndentedKind(line, contentIndent: contentIndent) == .listCode
    }

    // MARK: - 块构造

    private static func paragraphBlock(_ text: String) -> NSAttributedString {
        let style = DocTheme.paragraphStyle(for: .paragraph)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.bodyFont,
            .paragraphStyle: style,
            .foregroundColor: DocTheme.text,
        ]
        let attributed = InlineParser.parse(text, base: attrs)
        attrs[.mdBlockType] = MDBlockType.paragraph.rawValue
        return withEmphasisSnapshot(finalized(attributed, with: attrs),
                                    source: text, display: attributed.string)
    }

    /// 逐行快照三元组（sources / displays / traits）：行粒度源码保真。
    /// **自包含校验**——每行独立解析的显示必须与块内显示行一致，否则说明
    /// 有跨行构造（强调定界符配对、链接 label、行尾反斜杠硬换行……），返回 nil
    /// 放弃逐行（退回块级快照 / 整块重建），避免重建时把跨行定界符撕断。
    /// `bodyLines` 是参与自包含校验的行（quote 传剥掉 `>` 的正文行），
    /// `sources` 是逐行写回的原文（quote 传含 `>` 前缀与懒续行缩进的原始行）。
    private static func lineSnapshots(_ block: NSAttributedString,
                                      bodyLength: Int,
                                      bodyLines: [String],
                                      sources: [String],
                                      display: String) -> (sources: [String], displays: [String], traits: [String])? {
        let dispLines = display.components(separatedBy: "\u{2028}")
        guard bodyLines.count == sources.count, sources.count == dispLines.count,
              !sources.isEmpty else { return nil }
        for (idx, body) in bodyLines.enumerated() {
            guard InlineParser.parse(body, base: [:]).string == dispLines[idx] else { return nil }
        }
        let ns = block.string as NSString
        let limit = min(bodyLength, ns.length)
        var ranges: [NSRange] = []
        var start = 0
        for i in 0..<limit {
            if ns.character(at: i) == 0x2028 {
                ranges.append(NSRange(location: start, length: i - start))
                start = i + 1
            }
        }
        ranges.append(NSRange(location: start, length: limit - start))
        guard ranges.count == sources.count else { return nil }
        let traits = ranges.map {
            mdFormattingFingerprint(block.attributedSubstring(from: $0), length: $0.length)
        }
        return (sources, dispLines, traits)
    }

    /// 引用逐行对齐：显示行 ↔ 连续原始行**组**。跨行构造（典型是被行内解析
    /// 成代码 span 的内层围栏：`> ``` / > code / > ``` ` 三个源行对一个显示行）
    /// 用贪心组匹配吸收；对不齐（如跨行强调 `*a` / `b*`）返回 nil 走整块重建。
    /// map 元素 [dispIdx, rawStart, rawEnd, contentIdx]：contentIdx 是组内
    /// 「独立解析 == 该显示行」的唯一内容行（编辑时只替换它，结构行逐字保留），
    /// 不唯一时为 -1。
    private static func quoteLineAlignment(bodyLines: [String],
                                           dispLines: [String]) -> [[Int]]? {
        var map: [[Int]] = []
        var i = 0
        for (j, d) in dispLines.enumerated() {
            var matched = false
            var k = i
            while k < bodyLines.count {
                let group = bodyLines[i...k].joined(separator: "\n")
                if InlineParser.parse(group, base: [:]).string == d {
                    var contentIdx = -1
                    for c in i...k {
                        if InlineParser.parse(bodyLines[c], base: [:]).string == d {
                            if contentIdx == -1 { contentIdx = c } else { contentIdx = -2; break }
                        }
                    }
                    if contentIdx == -2 { contentIdx = -1 }
                    map.append([j, i, k, contentIdx])
                    i = k + 1
                    matched = true
                    break
                }
                k += 1
            }
            if !matched { return nil }
        }
        guard i == bodyLines.count else { return nil }
        return map
    }

    /// 给块级行打源码快照：CommonMark 的 `***a ***b***` 是树形嵌套，
    /// 富文本的粗/斜两个 trait 无法还原层级；引用式链接、软换行、行内 HTML
    /// 等写法重建同样会变形。未编辑时序列化器逐字输出原文，编辑后才按富文本重建。
    /// 所有块都打快照（不限含强调的行），让即刻模式对外部文件逐字保真。
    /// 只在顶层块构造调用，链接 label 等递归子串不经过这里。
    private static func withEmphasisSnapshot(_ block: NSAttributedString,
                                             source: String,
                                             display: String,
                                             force: Bool = false) -> NSAttributedString {
        // 没有强调定界符就不打，避免给纯文本行多带属性。
        // 快照只为「强调定界符栈无法用粗/斜 trait 还原」兜底；纯文本块不打快照，
        // 让它们走重建路径做设计内规范化（<mark> → background-color span、
        // 文本方括号防御性转义等），体检工具也据此检出改写行。
        // `~` 是删除线定界符（~~x~~ / ~x~ 两个 trait 同形），同样无法用 trait
        // 还原写法——纯删除线行不打快照会被重建吞掉 `~~`（marked 003）。
        // force：引用块必须逐字写回原始正文（`>`/`#`/`-` 被重建转义会毁掉
        // 内层块结构），不受定界符限制。
        guard force || source.contains("*") || source.contains("_")
                || source.contains("~") else { return block }
        let out = NSMutableAttributedString(attributedString: block)
        // 只覆盖正文部分：末尾的 \n 是 finalized 追加的，不参与显示比对
        let bodyLength = min(display.utf16.count, out.length)
        guard bodyLength > 0 else { return block }
        let range = NSRange(location: 0, length: bodyLength)
        out.addAttribute(.mdEmphasisSource, value: source, range: range)
        out.addAttribute(.mdEmphasisDisplay, value: display, range: range)
        out.addAttribute(.mdEmphasisTraits, value: mdFormattingFingerprint(out, length: bodyLength),
                         range: range)
        // 逐行快照（quote 的行形态特殊，由 quoteBlock 自行打 mdQuoteLine*）：
        // 整块被编辑时按行粒度重建，未动的行逐字保留写法。
        if !force {
            let lines = source.components(separatedBy: "\n")
            if let snap = lineSnapshots(out, bodyLength: bodyLength,
                                        bodyLines: lines, sources: lines, display: display) {
                out.addAttribute(.mdLineSources, value: snap.sources, range: range)
                out.addAttribute(.mdLineDisplays, value: snap.displays, range: range)
                out.addAttribute(.mdLineTraits, value: snap.traits, range: range)
            }
        }
        return out
    }

    /// 格式指纹：见 `mdFormattingFingerprint`（与序列化器共用同一算法）。
    private static func formattingFingerprint(_ attr: NSAttributedString, length: Int) -> String {
        mdFormattingFingerprint(attr, length: length)
    }

    /// editor.md / Obsidian 的目录指令行：`[TOC]` / `[TOCM]` 独占一行（大小写不敏感）。
    /// 标题、段落里的 `[TOC]` 字样不算指令，仍按普通文字走防御性转义。
    private static func isTOCDirective(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: mdWS).lowercased()
        return t == "[toc]" || t == "[tocm]"
    }

    /// 逐字段落：块类型与外观都跟普通段落一致，但不走 InlineParser /
    /// InlineSerializer，整行（含前导空格与方括号）原样显示、原样写回。
    private static func verbatimLineBlock(_ line: String) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.bodyFont,
            .paragraphStyle: DocTheme.paragraphStyle(for: .paragraph),
            .foregroundColor: DocTheme.text,
            .mdBlockType: MDBlockType.paragraph.rawValue,
            .mdVerbatimLine: true,
        ]
        return NSAttributedString(string: line + "\n", attributes: attrs)
    }

    private static func headingBlock(_ text: String, level: Int) -> NSAttributedString {
        let type = MDBlockType(headingLevel: level)
        let size = DocTheme.headingFontSize(level)
        let style = DocTheme.paragraphStyle(for: type)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.documentFont(size: size, weight: .bold),
            .paragraphStyle: style,
            .foregroundColor: level >= 6 ? DocTheme.textDim : DocTheme.text,
        ]
        let attributed = InlineParser.parse(text, base: attrs)
        attrs[.mdBlockType] = type.rawValue
        attrs[.mdStructuralBold] = true   // 标题的字重是排版自带的，序列化时不输出 **
        return withEmphasisSnapshot(finalized(attributed, with: attrs),
                                    source: text, display: attributed.string)
    }

    private static func quoteBlock(_ text: String, raw: String) -> NSAttributedString {
        let style = DocTheme.paragraphStyle(for: .quote)
        style.textBlocks = [DocTheme.quoteTextBlock]
        var attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.bodyFont,
            .paragraphStyle: style,
            .foregroundColor: DocTheme.textDim,
        ]
        let attributed = InlineParser.parse(text, base: attrs)
        attrs[.mdBlockType] = MDBlockType.quote.rawValue
        // 引用在存储里只是单段富文本，内层块语法（围栏/嵌套列表/标题）只存在于
        // 原始源码里；HTML 导出按块递归重解析这份源码，才能还原完整语义。
        let merged = NSMutableAttributedString(attributedString: attributed)
        if merged.length > 0 {
            merged.addAttribute(.mdQuoteSource, value: text,
                                range: NSRange(location: 0, length: merged.length))
            // 原始行（含 `>` 与懒续行缩进）：未编辑时序列化逐字写回
            merged.addAttribute(.mdQuoteRaw, value: raw,
                                range: NSRange(location: 0, length: merged.length))
            // 逐行快照：编辑某一行只重建该行，兄弟行（围栏 / `>>` / 懒续行缩进）
            // 逐字保留。自包含校验在 lineSnapshots 里做；跨行构造（内层围栏被
            // 行内解析吞成代码 span）改用组对齐 quoteLineAlignment。
            let bodyLines = text.components(separatedBy: "\n")
            let rawLines = raw.components(separatedBy: "\n")
            let dispLines = attributed.string.components(separatedBy: "\u{2028}")
            var lineRanges: [NSRange] = []
            do {
                let ns = merged.string as NSString
                var start = 0
                for i in 0..<merged.length {
                    if ns.character(at: i) == 0x2028 {
                        lineRanges.append(NSRange(location: start, length: i - start))
                        start = i + 1
                    }
                }
                lineRanges.append(NSRange(location: start, length: merged.length - start))
            }
            if let snap = lineSnapshots(merged, bodyLength: merged.length,
                                        bodyLines: bodyLines, sources: rawLines,
                                        display: attributed.string) {
                merged.addAttribute(.mdQuoteLineSources, value: snap.sources,
                                    range: NSRange(location: 0, length: merged.length))
                merged.addAttribute(.mdQuoteLineDisplays, value: snap.displays,
                                    range: NSRange(location: 0, length: merged.length))
                merged.addAttribute(.mdQuoteLineTraits, value: snap.traits,
                                    range: NSRange(location: 0, length: merged.length))
            } else if bodyLines.count == rawLines.count,
                      dispLines.count == lineRanges.count,
                      let map = quoteLineAlignment(bodyLines: bodyLines, dispLines: dispLines) {
                // 组对齐：displays / traits 按显示行，sources 按原始行
                let traits = lineRanges.map {
                    mdFormattingFingerprint(merged.attributedSubstring(from: $0), length: $0.length)
                }
                merged.addAttribute(.mdQuoteLineSources, value: rawLines,
                                    range: NSRange(location: 0, length: merged.length))
                merged.addAttribute(.mdQuoteLineDisplays, value: dispLines,
                                    range: NSRange(location: 0, length: merged.length))
                merged.addAttribute(.mdQuoteLineTraits, value: traits,
                                    range: NSRange(location: 0, length: merged.length))
                merged.addAttribute(.mdQuoteLineMap, value: map,
                                    range: NSRange(location: 0, length: merged.length))
            }
        }
        return withEmphasisSnapshot(finalized(merged, with: attrs),
                                    source: text, display: attributed.string, force: true)
    }

    /// Obsidian Callout：每行走 InlineParser 做真正的行内解析。
    /// 与旧实现的区别：旧实现把去掉 "> " 后的原始行整个塞进 storage，
    /// 所以 `**粗体**`、`*斜体*`、`` `代码` `` 只会当普通字符显示。
    /// 现在显示的是解析后的富文本，同时记住「原行 + 解析后显示文字」两个快照：
    /// 只要显示文字没被改过，序列化仍逐字输出原行（保住 12/12 逐字往返）；
    /// 用户改过文字就按新文字重建，绝不让旧源码盖掉编辑（P1 的教训）。
    private static func calloutBlock(_ lines: [String], kind: String,
                                     fold: String, id: Int) -> NSAttributedString {
        let style = DocTheme.paragraphStyle(for: .callout)
        style.textBlocks = [DocTheme.calloutTextBlock(kind: kind)]
        let titleColor = DocTheme.calloutColor(kind: kind)
        let out = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let font = index == 0
                ? DocTheme.documentFont(size: DocTheme.bodyFontSize, weight: .semibold)
                : DocTheme.bodyFont
            let color = index == 0 ? titleColor : DocTheme.text
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: style,
                .foregroundColor: color,
                .mdBlockType: MDBlockType.callout.rawValue,
                .mdCalloutID: id,
                .mdCalloutKind: kind,
                .mdCalloutFold: fold,
            ]
            let parsed = NSMutableAttributedString(
                attributedString: InlineParser.parse(line, base: attrs))
            let display = parsed.string
            // 只补语义标签，不能覆盖 InlineParser 为强调片段单独设的 font /
            // foregroundColor，否则刚解析出来的粗体、斜体、链接色会被抹平。
            var tags: [NSAttributedString.Key: Any] = [
                .mdBlockType: MDBlockType.callout.rawValue,
                .mdCalloutID: id,
                .mdCalloutKind: kind,
                .mdCalloutFold: fold,
                .mdCalloutSource: line,
                .mdCalloutDisplay: display,
                // 格式指纹：只改格式不改文字时也要让快照失效（否则 ⌘B 被旧源码盖掉）
                .mdCalloutTraits: mdFormattingFingerprint(parsed, length: parsed.length),
            ]
            if parsed.length > 0 {
                parsed.addAttributes(tags, range: NSRange(location: 0, length: parsed.length))
            }
            out.append(parsed)
            // 段末 \n 也带全套属性：Callout 的空行只有一个 \n，
            // blocks(from:) / folding 都是从它身上读属性。
            tags[.font] = font
            tags[.paragraphStyle] = style
            tags[.foregroundColor] = color
            out.append(NSAttributedString(string: "\n", attributes: tags))
        }
        return out
    }

    private static func codeBlock(_ text: String, language: String) -> NSAttributedString {
        let style = DocTheme.paragraphStyle(for: .code)
        style.textBlocks = [DocTheme.codeTextBlock]
        let attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.monospacedFont(size: DocTheme.codeFontSize),
            .paragraphStyle: style,
            .foregroundColor: DocTheme.text,
            .mdBlockType: MDBlockType.code.rawValue,
            .mdCodeLanguage: language,
        ]
        // 代码块内容原样保留，不做行内解析。
        // 空内容存 " "（NSAttributedString 需要非空段落）并打 mdCodeEmpty 还原标记；
        // 末尾块终结换行打 mdCodeEnd，blocks() 据此断开相邻代码块的合并。
        var bodyAttrs = attrs
        if text.isEmpty { bodyAttrs[.mdCodeEmpty] = true }
        let body = NSAttributedString(string: text.isEmpty ? " " : text, attributes: bodyAttrs)
        let out = NSMutableAttributedString(attributedString: body)
        var termAttrs = attrs
        termAttrs[.mdCodeEnd] = true
        out.append(NSAttributedString(string: "\n", attributes: termAttrs))
        return out
    }

    private static func horizontalRule() -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.bodyFont,
            .paragraphStyle: DocTheme.paragraphStyle(for: .paragraph),
        ]
        // 附件字符串本身就是一个 object replacement 字符，不要再手动拼一个
        let out = NSMutableAttributedString(attachment: MDRuleAttachment())
        out.append(NSAttributedString(string: "\n", attributes: attrs))
        return out
    }

    private static func listBlock(_ items: [ListEntry], rawID: inout Int) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for item in items {
            let (marker, content, level) = (item.marker, item.content, item.level)
            let ordered = marker.last == "." || marker.last == ")"
            let number = Int(marker.dropLast().filter(\.isNumber)) ?? 1
            let style = DocTheme.paragraphStyle(for: .paragraph)
            style.lineHeightMultiple = DocTheme.bodyLineHeight
            style.headIndent = CGFloat(20 + level * 24)
            style.firstLineHeadIndent = CGFloat(20 + level * 24)
            style.paragraphSpacing = 2

            let attrs: [NSAttributedString.Key: Any] = [
                .font: DocTheme.bodyFont,
                .paragraphStyle: style,
                .foregroundColor: DocTheme.text,
            ]
            // 列表符号直接写进文本（所见即所得，和 Typora 一致）
            let bullet = NSAttributedString(string: marker + " ", attributes: attrs)
            let attributed = InlineParser.parse(content, base: attrs)

            let entry = NSMutableAttributedString()
            entry.append(bullet)
            entry.append(attributed)

            let range = NSRange(location: 0, length: entry.length)
            entry.addAttribute(.mdListItem,
                               value: MDListItem(ordered: ordered, level: level,
                                                 number: number, indent: item.indent),
                               range: range)
            entry.addAttribute(.mdBlockType, value: MDBlockType.paragraph.rawValue, range: range)
            // 列表项正文打源码快照：未编辑时逐字输出原内容（保住强调写法、
            // 软换行、引用式链接等写法），编辑后才按富文本重建。
            if attributed.length > 0 {
                let bodyRange = NSRange(location: bullet.length, length: attributed.length)
                entry.addAttribute(.mdEmphasisSource, value: content, range: bodyRange)
                entry.addAttribute(.mdEmphasisDisplay, value: attributed.string, range: bodyRange)
                entry.addAttribute(.mdEmphasisTraits,
                                   value: formattingFingerprint(attributed,
                                                                length: attributed.length),
                                   range: bodyRange)
                // 逐行快照：懒续行并入内容后是多行文本，编辑其中一行
                // 不应改写其余续行的写法。
                let lines = content.components(separatedBy: "\n")
                if let snap = lineSnapshots(attributed, bodyLength: attributed.length,
                                            bodyLines: lines, sources: lines,
                                            display: attributed.string) {
                    entry.addAttribute(.mdLineSources, value: snap.sources, range: bodyRange)
                    entry.addAttribute(.mdLineDisplays, value: snap.displays, range: bodyRange)
                    entry.addAttribute(.mdLineTraits, value: snap.traits, range: bodyRange)
                }
            }
            entry.append(NSAttributedString(string: "\n", attributes: attrs))
            out.append(entry)

            // 缩进容器块：按 kind 分段，连续同类的原始行共用一个 rawID，
            // 序列化时聚合成一块，逐行（含块内空行）原样写回。
            var group: [String] = []
            var groupKind: MDRawKind?
            func flushGroup() {
                defer { group = []; groupKind = nil }
                guard let kind = groupKind, !group.isEmpty else { return }
                out.append(rawBlock(group, kind: kind, id: rawID))
                rawID += 1
            }
            for (line, kind) in item.lines {
                if let current = groupKind, current != kind { flushGroup() }
                groupKind = kind
                group.append(line)
            }
            flushGroup()
        }
        return out
    }

    private static func tableBlock(_ lines: [String]) -> NSAttributedString {
        // GFM 规则：只在未转义的 `|` 处切分（`\|` 是内容里的竖线，交给
        // InlineParser 解转义）；外框竖线可有可无；行内代码里的裸 `|`
        // 按规范照切（要保竖线得写 `\|`）。
        var parsed: [[String]] = lines.map(splitTableCells)

        // 第二行是分隔行则第一行视为表头，列宽以分隔行为准
        var hasHeader = false
        var width = parsed.first?.count ?? 1
        if parsed.count >= 2, parsed[1].allSatisfy({ isSeparatorCell($0) }) {
            hasHeader = true
            width = parsed[1].count
            parsed.remove(at: 1)
        }

        // GFM：行格数不齐——少的补空、多的丢弃
        parsed = parsed.map { row in
            var r = row
            if r.count > width { r = Array(r.prefix(width)) }
            while r.count < width { r.append("") }
            return r
        }

        let columns = max(width, 1)
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        let out = NSMutableAttributedString()
        for (r, row) in parsed.enumerated() {
            for c in 0..<columns {
                let raw = c < row.count ? row[c] : ""
                let block = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                block.setBorderColor(DocTheme.border)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(7, type: .absoluteValueType, for: .padding)
                block.setWidth(1, type: .absoluteValueType, for: .margin)

                let isHeader = hasHeader && r == 0
                if isHeader {
                    block.backgroundColor = DocTheme.tableHeaderBackground
                }

                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                style.alignment = .natural
                style.lineHeightMultiple = 1.35

                var attrs: [NSAttributedString.Key: Any] = [
                    .font: isHeader ? DocTheme.documentFont(size: DocTheme.bodyFontSize, weight: .semibold)
                                    : DocTheme.bodyFont,
                    .paragraphStyle: style,
                    .foregroundColor: DocTheme.text,
                ]
                let cell = InlineParser.parse(raw, base: attrs)
                attrs[.mdTableHeader] = isHeader
                attrs[.mdBlockType] = MDBlockType.paragraph.rawValue
                if isHeader { attrs[.mdStructuralBold] = true }
                // 单元格也打源码快照：`***bold italics***` 这类嵌套强调的树形
                // 写法无法用粗 / 斜 trait 还原，未编辑时逐字写回才不会走样。
                let finalizedCell = withEmphasisSnapshot(finalized(cell, with: attrs),
                                                         source: raw, display: cell.string)
                out.append(finalizedCell)
                out.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }
        return out
    }

    /// 从 i 起两行是否构成 GFM 表格（首行 + 分隔行且格数一致）。
    /// 外层表格分支与段落打断判定必须共用此谓词：格数不齐的 `|` 行
    /// （如 `| \`a|b\` | c |` 代码内竖线切出的假表格）两边都不收会死循环。
    private static func isTableStart(_ lines: [String], at i: Int) -> Bool {
        guard i + 1 < lines.count, lines[i].contains("|") else { return false }
        guard isTableDelimiterLine(lines[i + 1]) else { return false }
        return splitTableCells(lines[i]).count == splitTableCells(lines[i + 1]).count
    }

    private static func isSeparatorCell(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: ":", with: "")
        return !t.isEmpty && t.allSatisfy { $0 == "-" }
    }

    /// 分隔行（GFM）：每个单元格都是 `---` / `:---:` 形态。
    private static func isTableDelimiterLine(_ line: String) -> Bool {
        let cells = splitTableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { isSeparatorCell($0) }
    }

    /// GFM 单元格切分：只在未转义的 `|` 处切；`\|` 是内容里的竖线。
    /// 切完把 `\|` 解成 `|`（内容里不再需要转义，输出时序列化器会重新转义）。
    private static func splitTableCells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: mdWS)
        if s.hasPrefix("|") { s = String(s.dropFirst()) }
        if s.hasSuffix("|"), !isEscapedPipe(s, at: s.index(before: s.endIndex)) {
            s = String(s.dropLast())
        }
        var cells: [String] = []
        var cur = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "|", !isEscapedPipe(s, at: i) {
                cells.append(cur)
                cur = ""
                i = s.index(after: i)
                continue
            }
            cur.append(s[i])
            i = s.index(after: i)
        }
        cells.append(cur)
        return cells.map {
            $0.trimmingCharacters(in: mdWS)
                .replacingOccurrences(of: "\\|", with: "|")
        }
    }

    /// 该处的 `|` 是否被反斜杠转义（前面连续反斜杠数为奇数）。
    private static func isEscapedPipe(_ s: String, at idx: String.Index) -> Bool {
        var n = 0
        var j = idx
        while j > s.startIndex {
            j = s.index(before: j)
            if s[j] == "\\" { n += 1 } else { break }
        }
        return n % 2 == 1
    }

    // MARK: - 建表（插入表格对话框复用）

    /// 生成 rows × cols 的空表格，首行可选作为表头
    static func makeTable(rows: Int, cols: Int, hasHeader: Bool) -> NSAttributedString {
        let columnCount = max(cols, 1)
        let rowCount = max(rows, 1)
        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        let out = NSMutableAttributedString()
        for r in 0..<rowCount {
            for c in 0..<columnCount {
                let block = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1,
                                             startingColumn: c, columnSpan: 1)
                block.setBorderColor(DocTheme.border)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(7, type: .absoluteValueType, for: .padding)
                block.setWidth(1, type: .absoluteValueType, for: .margin)

                let isHeader = hasHeader && r == 0
                if isHeader {
                    block.backgroundColor = DocTheme.tableHeaderBackground
                }

                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                style.alignment = .natural
                style.lineHeightMultiple = 1.35

                var attrs: [NSAttributedString.Key: Any] = [
                    .font: isHeader ? DocTheme.documentFont(size: DocTheme.bodyFontSize, weight: .semibold)
                                    : DocTheme.bodyFont,
                    .paragraphStyle: style,
                    .foregroundColor: DocTheme.text,
                    .mdTableHeader: isHeader,
                    .mdBlockType: MDBlockType.paragraph.rawValue,
                ]
                if isHeader { attrs[.mdStructuralBold] = true }
                out.append(NSAttributedString(string: "", attributes: attrs))
                out.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }
        // 表格后面补一个普通段落，方便继续输入
        let tailAttrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.bodyFont,
            .paragraphStyle: DocTheme.paragraphStyle(for: .paragraph),
            .foregroundColor: DocTheme.text,
            .mdBlockType: MDBlockType.paragraph.rawValue,
        ]
        out.append(NSAttributedString(string: "\n", attributes: tailAttrs))
        return out
    }

    // MARK: - 工具

    /// 把 base 里除 font/paragraphStyle 之外的属性补齐到整个块（保证后续序列化能读到块类型）
    private static func finalized(_ attr: NSAttributedString,
                                  with attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: attr)
        let full = NSRange(location: 0, length: out.length)
        if let type = attrs[.mdBlockType] { out.addAttribute(.mdBlockType, value: type, range: full) }
        if let header = attrs[.mdTableHeader] { out.addAttribute(.mdTableHeader, value: header, range: full) }
        if let lang = attrs[.mdCodeLanguage] { out.addAttribute(.mdCodeLanguage, value: lang, range: full) }
        if let structural = attrs[.mdStructuralBold] {
            // 用户手写 `**x**` 的粗体不是排版自带的，不能打抑制标记，
            // 否则表头 / 标题里的用户粗体记号会被序列化吞掉。
            out.beginEditing()
            out.enumerateAttribute(.mdUserBold, in: full) { userBold, range, _ in
                if (userBold as? Bool) != true {
                    out.addAttribute(.mdStructuralBold, value: structural, range: range)
                }
            }
            out.endEditing()
        }
        out.append(NSAttributedString(string: "\n", attributes: attrs))
        return out
    }
}
