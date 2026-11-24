//
//  MarkdownParser.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  Markdown 文本 → NSAttributedString（块级）：
//  # 标题 / > 引用 / ``` 代码块 / --- 分割线 / - 与 1. 列表 / | 表格 | / 段落。
//

import AppKit

enum MarkdownParser {

    /// 解析整篇 Markdown
    static func parse(_ markdown: String) -> NSMutableAttributedString {
        var text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // UTF-8 BOM 会让首行 frontmatter 的 "---" 判断失效，先剥掉
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let out = NSMutableAttributedString()
        var i = 0
        var nextRawID = 1

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

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

            // 围栏代码块
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    body.append(lines[i])
                    i += 1
                }
                i += 1 // 跳过收尾围栏
                out.append(codeBlock(body.joined(separator: "\n"), language: language))
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

            // 表格
            if trimmed.hasPrefix("|") {
                var block: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    block.append(lines[i].trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                out.append(tableBlock(block))
                continue
            }

            // 引用 / Obsidian Callout
            if trimmed.hasPrefix(">") {
                var body: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[i].trimmingCharacters(in: .whitespaces)
                    l = String(l.dropFirst())
                    if l.hasPrefix(" ") { l = String(l.dropFirst()) }
                    body.append(l)
                    i += 1
                }
                if let info = calloutInfo(body.first) {
                    out.append(calloutBlock(body, kind: info.kind, fold: info.fold, id: nextRawID))
                    nextRawID += 1
                } else {
                    out.append(quoteBlock(body.joined(separator: "\n")))
                }
                continue
            }

            // 列表（含 CommonMark 容器块：项内缩进代码块 / 引用 / 嵌套源码）。
            // 缩进续行不能 trim 后拼进列表文本：storage 里一个段落就是一个列表项，
            // 拼接会让它被序列化成多个 "- " 行，既丢内容又丢原始缩进。
            // 正确做法是把原始行挂在所属列表项下面，按 raw 机制逐字写回。
            if listItemInfo(line) != nil {
                var items: [ListEntry] = []
                var counter = 0
                var contentIndent = 2
                while i < lines.count {
                    let l = lines[i]
                    if let info = listItemInfo(l) {
                        counter = info.ordered ? counter + 1 : 0
                        let n = info.ordered ? counter : 0
                        items.append(ListEntry(marker: info.ordered ? "\(n)." : "-",
                                               content: info.content,
                                               level: info.level,
                                               indent: info.indent))
                        contentIndent = info.contentIndent
                        i += 1
                        continue
                    }
                    // 空行后紧跟「项内缩进代码块」时，空行属于同一个列表项：
                    // 不能在这里 break，否则列表被拆成两段，有序编号会重新从 1 开始。
                    if l.trimmingCharacters(in: .whitespaces).isEmpty {
                        var k = i
                        while k < lines.count,
                              lines[k].trimmingCharacters(in: .whitespaces).isEmpty { k += 1 }
                        if k < lines.count, !items.isEmpty,
                           isListItemIndentedCode(lines[k], contentIndent: contentIndent) {
                            let kind = listIndentedKind(lines[k], contentIndent: contentIndent)
                            for _ in i..<k { items[items.count - 1].lines.append(("", kind)) }
                            i = k
                            continue
                        }
                        break
                    }
                    if (l.hasPrefix(" ") || l.hasPrefix("\t")), !items.isEmpty {
                        items[items.count - 1].lines.append(
                            (l, listIndentedKind(l, contentIndent: contentIndent)))
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
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if t.hasPrefix("```") || t.hasPrefix("~~~") || t.hasPrefix("|") || t.hasPrefix(">")
                    || isHorizontalRule(t) || heading(from: t) != nil || listItemInfo(l) != nil
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

    // MARK: - 行判定

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
        let t = line.trimmingCharacters(in: .whitespaces)
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
    private static func frontmatterEnd(in lines: [String], from start: Int) -> Int? {
        guard start < lines.count else { return nil }
        let open = lines[start].trimmingCharacters(in: .whitespaces)
        guard open == "---" || open == "+++" else { return nil }
        let close = open

        var j = start + 1
        var sawKey = false
        while j < lines.count, j - start <= 300 {
            let rawLine = lines[j]
            let t = rawLine.trimmingCharacters(in: .whitespaces)
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
            if t.range(of: #"^[A-Za-z_][A-Za-z0-9_.\- ]*[:=]\s*\S?"#,
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
        let t = String(line.dropFirst(leading)).trimmingCharacters(in: .whitespaces)
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
        while j < lines.count, !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
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
        return !rest.trimmingCharacters(in: .whitespaces).isEmpty
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
        let rest = String(t[t.index(after: afterClose)...]).trimmingCharacters(in: .whitespaces)
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
        let t = line.trimmingCharacters(in: .whitespaces)
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
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
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
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // 缩进的 "> ..." 在 FinalMd 里一直是引用块（常见于列表项内的嵌套引用），
        // 不能因为前面有 4 个空格就把它降级成代码源码、丢掉引用排版。
        guard !trimmed.isEmpty, !trimmed.hasPrefix(">") else { return false }
        if line.hasPrefix("\t") { return true }
        return line.prefix(while: { $0 == " " }).count >= 4
    }

    /// 把整块原始行原封不动放进 storage：不走 InlineParser，也不做任何转义。
    /// 每一行（含空行）都带同一个 blockID，序列化时据此拼回一整块。
    private static func rawBlock(_ lines: [String], kind: MDRawKind, id: Int) -> NSAttributedString {
        // split(omittingEmptySubsequences:false) 会在文件末尾多出一个空串；
        // 未闭合的 HTML 块吃到 EOF 时会把它一起带进来，导致每往返一次就多一个空行。
        // 块内部的空行要保留，只剥掉尾部空行。
        var content = lines
        while let last = content.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
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
        var rest = String(line.dropFirst(hashes))
        if rest.hasPrefix(" ") { rest = String(rest.dropFirst()) }
        return (hashes, rest.trimmingCharacters(in: .whitespaces))
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
        var markerLength = 0

        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            markerLength = 2
        } else if let dot = rest.firstIndex(of: "."), rest.startIndex < dot {
            let numPart = String(rest[rest.startIndex..<dot])
            // "1." 这种只有序号、没有后续空格的行：index(after:) 会等于 endIndex，
            // 直接用 rest[endIndex] 取值会触发 String 索引越界崩溃。
            let after = rest.index(after: dot)
            if !numPart.isEmpty, numPart.allSatisfy(\.isNumber),
               after < rest.endIndex, rest[after] == " " {
                ordered = true
                markerLength = numPart.count + 2
            }
        } else if let paren = rest.firstIndex(of: ")"), rest.startIndex < paren {
            let numPart = String(rest[rest.startIndex..<paren])
            let after = rest.index(after: paren)
            if !numPart.isEmpty, numPart.allSatisfy(\.isNumber),
               after < rest.endIndex, rest[after] == " " {
                ordered = true
                markerLength = numPart.count + 2
            }
        }

        guard markerLength > 0 else { return nil }
        let content = String(rest.dropFirst(markerLength))
        let level: Int
        if leading >= 4, leading % 4 == 0 {
            level = leading / 4
        } else {
            level = leading / 2
        }
        return ListInfo(ordered: ordered, level: level, content: content,
                        indent: leading, contentIndent: leading + markerLength)
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
        let t = line.trimmingCharacters(in: .whitespaces)
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
        return finalized(attributed, with: attrs)
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
        return finalized(attributed, with: attrs)
    }

    private static func quoteBlock(_ text: String) -> NSAttributedString {
        let style = DocTheme.paragraphStyle(for: .quote)
        style.textBlocks = [DocTheme.quoteTextBlock]
        var attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.bodyFont,
            .paragraphStyle: style,
            .foregroundColor: DocTheme.textDim,
        ]
        let attributed = InlineParser.parse(text, base: attrs)
        attrs[.mdBlockType] = MDBlockType.quote.rawValue
        return finalized(attributed, with: attrs)
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
        // 代码块内容原样保留，不做行内解析
        let body = NSAttributedString(string: text.isEmpty ? " " : text, attributes: attrs)
        let out = NSMutableAttributedString(attributedString: body)
        out.append(NSAttributedString(string: "\n", attributes: attrs))
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
            let ordered = marker != "-"
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
                                                 indent: item.indent),
                               range: range)
            entry.addAttribute(.mdBlockType, value: MDBlockType.paragraph.rawValue, range: range)
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
        // 解析每一行
        var rows: [[String]] = []
        for line in lines {
            var l = line
            if l.hasPrefix("|") { l = String(l.dropFirst()) }
            if l.hasSuffix("|") { l = String(l.dropLast()) }
            let cells = l.split(separator: "|", omittingEmptySubsequences: false).map { cell in
                cell.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\\|", with: "|")
            }
            rows.append(cells)
        }

        // 第二行是分隔行则第一行视为表头
        var hasHeader = false
        if rows.count >= 2, rows[1].allSatisfy({ isSeparatorCell($0) }) {
            hasHeader = true
            rows.remove(at: 1)
        }

        let columns = rows.map(\.count).max() ?? 1
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        let out = NSMutableAttributedString()
        for (r, row) in rows.enumerated() {
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
                let finalizedCell = finalized(cell, with: attrs)
                out.append(finalizedCell)
                out.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }
        return out
    }

    private static func isSeparatorCell(_ s: String) -> Bool {
        let t = s.replacingOccurrences(of: ":", with: "")
        return !t.isEmpty && t.allSatisfy { $0 == "-" }
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
            out.addAttribute(.mdStructuralBold, value: structural, range: full)
        }
        out.append(NSAttributedString(string: "\n", attributes: attrs))
        return out
    }
}
