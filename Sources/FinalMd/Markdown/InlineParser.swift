//
//  InlineParser.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  行内 Markdown → NSAttributedString。
//  递归下降扫描，支持：**粗体** / *斜体* / `代码` / ~~删除线~~ / [链接](url) /
//  ![图片](src "title") / <span style="color:#d64545"> / <mark> / <u> / <br> 与 \ 转义。
//

import AppKit

enum InlineParser {

    /// 当前文档的引用式链接定义表（由 `MarkdownParser.parse` 入口按全文填入）。
    /// 键是规范化后的 label（空白折叠 + 小写），值是 (url, title)。
    /// 单线程 UI 使用，不考虑并发；直接调用 `InlineParser.parse` 的场景表为空，
    /// 引用式语法回退为字面文本，行为与旧版一致。
    static var references: [String: (url: String, title: String)] = [:]

    /// 把一段行内 Markdown 渲染成带属性的字符串。
    ///
    /// 强调走 CommonMark §6.4 定界符栈：先由 `EmphasisStack` 一次性算出每个
    /// 定界符的配对与每个字符的粗/斜体，再交给扫描器渲染。旧的「首个匹配即
    /// 闭合」在 `***a ***b***` 这类重叠 run 上每轮换一种切分，嵌套语义被压平。
    static func parse(_ text: String, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        // 软换行 / 硬换行统一编码成 U+2028（段内换行）：
        // NSAttributedString 的段落以 \n 为界，裸 \n 会被 blocks(from:) 按段落切分，
        // 把「同一段落里的软换行」拆成多个段落、序列化时多出空行。
        // U+2028 是段内换行，不影响段落切分。硬换行（行尾 ≥2 空格或行尾反斜杠）
        // 保留两空格前缀，序列化时 U+2028 还原成 "\n"，两空格天然构成 "  \n"。
        // 行尾反斜杠的识别必须跳过 `\\` 转义对：`\\`+换行是「字面反斜杠 + 软换行」
        //（CommonMark §2.5/§6.7），全局替换会把转义对里的第二个反斜杠当硬换行
        // 吃掉、还少一个反斜杠（cmark-gfm 019 实测）。
        var hardFixed = ""
        var hi = text.startIndex
        while hi < text.endIndex {
            let ch = text[hi]
            if ch == "\\" {
                let nxt = text.index(after: hi)
                if nxt < text.endIndex {
                    let next = text[nxt]
                    if next == "\n" {
                        hardFixed += "  \u{2028}"
                        hi = text.index(after: nxt)
                        continue
                    }
                    if next == "\\" {
                        hardFixed += "\\\\"
                        hi = text.index(after: nxt)
                        continue
                    }
                }
            }
            hardFixed.append(ch)
            hi = text.index(after: hi)
        }
        let normalized = hardFixed
            .replacingOccurrences(of: "  \n", with: "  \u{2028}")
            .replacingOccurrences(of: "\n", with: "\u{2028}")
        let chars = Array(normalized)
        let plan = EmphasisStack.plan(chars)
        var scanner = Scanner(chars: chars, base: base, plan: plan)
        return scanner.render()
    }

    /// CommonMark label 规范化：内部空白折叠成单个空格、去掉首尾空白、小写。
    static func normalizeLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// 反斜杠转义：`\` + ASCII 标点 → 标点本身；其余保留反斜杠原样。
    static func unescapeMarkdown(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\\" {
                let nxt = s.index(after: i)
                if nxt < s.endIndex {
                    let next = s[nxt]
                    if next.isASCII, "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".contains(next) {
                        out.append(next)
                        i = s.index(after: nxt)
                        continue
                    }
                }
            }
            out.append(ch)
            i = s.index(after: i)
        }
        return out
    }

    /// 严格解析链接目标 + 可选 title（CommonMark §6.3 / §4.7 共用口径）：
    /// destination 是 `<...>`（内部 `<` `>` 须转义）或非空白串（括号须配平），
    /// 其后可选空白 + 可选 title（`"..."` / `'...'` / `(...)`），
    /// 尾部只允许空白——任何杂字令整段失效，返回 nil。
    /// 目标与 title 里的反斜杠转义会被还原。
    /// allowEmpty：行内链接 `[x]()` 的空目标合法（§6.3）；引用定义（§4.7）不合法。
    static func parseLinkDestination(_ raw: String, allowEmpty: Bool = false)
        -> (url: String, title: String)? {
        let c = Array(raw)
        var p = 0
        func ws() { while p < c.count, c[p] == " " || c[p] == "\t" { p += 1 } }
        ws()
        var dest = ""
        if p < c.count, c[p] == "<" {
            p += 1
            while p < c.count {
                let ch = c[p]
                if ch == "\\" && p + 1 < c.count {
                    dest.append(ch); dest.append(c[p + 1]); p += 2
                    continue
                }
                if ch == ">" { break }
                // 尖括号目标内不允许裸 `<` / `>`
                if ch == "<" { return nil }
                dest.append(ch); p += 1
            }
            guard p < c.count, c[p] == ">" else { return nil }
            p += 1
        } else {
            while p < c.count {
                let ch = c[p]
                if ch == "\\" && p + 1 < c.count {
                    dest.append(ch); dest.append(c[p + 1]); p += 2
                    continue
                }
                if ch == " " || ch == "\t" { break }
                dest.append(ch); p += 1
            }
            guard !dest.isEmpty || allowEmpty else { return nil }
        }
        dest = unescapeMarkdown(dest)
        // title 必须以空白与 destination 分隔（CommonMark §6.3 / §4.7）：
        // `[foo]: <bar>(baz)` 的 `(baz)` 没有前置空白，整条定义失效；
        // `[link]("title")` 的引号串则整体是 destination，不是 title。
        var sawSpace = false
        while p < c.count, c[p] == " " || c[p] == "\t" { sawSpace = true; p += 1 }
        var title = ""
        if p < c.count {
            guard sawSpace else { return nil }
            let open = c[p]
            guard open == "\"" || open == "'" || open == "(" else { return nil }
            let close: Character = open == "(" ? ")" : open
            p += 1
            while p < c.count {
                let ch = c[p]
                if ch == "\\" && p + 1 < c.count {
                    title.append(ch); title.append(c[p + 1]); p += 2
                    continue
                }
                if ch == close { break }
                title.append(ch); p += 1
            }
            guard p < c.count, c[p] == close else { return nil }
            p += 1
            ws()
        }
        guard p == c.count else { return nil }
        return (dest, unescapeMarkdown(title))
    }

    // MARK: - HTML 实体

    /// 解析 `&name;` / `&#dd;` / `&#xhh;`（CommonMark §2.5）。返回 (解码结果, 源长)。
    /// 不合法（无分号、未知名称、数字超范围未定义）返回 nil，按字面量处理；
    /// 数字引用指向非法标量（0 / 代理区）时按 HTML5 规则替换为 U+FFFD。
    private static func parseEntity(_ c: [Character], at pos: Int) -> (String, Int)? {
        guard c[pos] == "&" else { return nil }
        var j = pos + 1
        guard j < c.count else { return nil }
        if c[j] == "#" {
            j += 1
            var hex = false
            if j < c.count, c[j] == "x" || c[j] == "X" { hex = true; j += 1 }
            var digits = ""
            while j < c.count, hex ? c[j].isHexDigit : c[j].isNumber {
                digits.append(c[j]); j += 1
            }
            guard !digits.isEmpty, j < c.count, c[j] == ";" else { return nil }
            let v = UInt64(digits, radix: hex ? 16 : 10)
            let scalar: Unicode.Scalar
            if let v, v > 0, v <= 0x10FFFF, let s = Unicode.Scalar(UInt32(v)),
               !(0xD800...0xDFFF).contains(v) {
                scalar = s
            } else {
                scalar = Unicode.Scalar(0xFFFD)!
            }
            return (String(Character(scalar)), j - pos + 1)
        }
        var name = ""
        while j < c.count, c[j].isLetter || c[j].isNumber {
            name.append(c[j]); j += 1
        }
        guard !name.isEmpty, j < c.count, c[j] == ";" else { return nil }
        if let decoded = HTMLEntities.table[name] {
            return (decoded, j - pos + 1)
        }
        return nil
    }

    // MARK: - 扫描器

    private struct Scanner {
        let chars: [Character]
        let base: [NSAttributedString.Key: Any]
        let plan: EmphasisStack.Plan
        var pos = 0

        var isAtEnd: Bool { pos >= chars.count }

        mutating func render() -> NSAttributedString {
            let out = NSMutableAttributedString()
            var plain = [Character]()
            // 普通文字的强调 trait 由 EmphasisStack 按字符给出；连续相同 trait
            // 的字符合并成一段，减少属性 run 数量。
            var plainBold = false
            var plainItalic = false

            func flushPlain() {
                guard !plain.isEmpty else { return }
                var attrs = base
                if plainBold {
                    attrs[.font] = FontTraits.adding(.bold, to: base[.font])
                    attrs[.mdUserBold] = true
                }
                if plainItalic { attrs[.font] = FontTraits.adding(.italic, to: attrs[.font]) }
                out.append(NSAttributedString(string: String(plain), attributes: attrs))
                plain.removeAll()
            }

            /// 追加一个普通字符，并按定界符栈算出的 trait 分组
            func appendPlain(_ c: Character, at index: Int) {
                let bold = plan.bold.contains(index)
                let italic = plan.italic.contains(index)
                if !plain.isEmpty, bold != plainBold || italic != plainItalic { flushPlain() }
                plainBold = bold
                plainItalic = italic
                plain.append(c)
            }

            /// 定界符栈算出的外层强调（* / **）按源码下标覆盖到递归构造的属性上。
            /// 链接 label、代码 span、删除线 body 只带 base 会丢外层 trait，
            /// `*em [link](u)*` 的链接内容缺斜体，HTML 会把强调撕成兄弟节点。
            func outerAttrs(at index: Int, from attrs: [NSAttributedString.Key: Any])
                -> [NSAttributedString.Key: Any] {
                var a = attrs
                if plan.bold.contains(index) {
                    a[.font] = FontTraits.adding(.bold, to: a[.font])
                    a[.mdUserBold] = true
                }
                if plan.italic.contains(index) {
                    a[.font] = FontTraits.adding(.italic, to: a[.font])
                }
                return a
            }

            while !isAtEnd {
                let c = chars[pos]

                // 转义（CommonMark §2.5）：只有 ASCII 标点可被反斜杠转义；
                // `\t` 这类字母 / 数字前的反斜杠是字面量，必须原样保留，
                // 否则 cmark-gfm 的转义用例会把 `\t\e\s\t\i\n\g` 读成 `testing`。
                if c == "\\" {
                    if pos + 1 < chars.count,
                       "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".contains(chars[pos + 1]) {
                        appendPlain(chars[pos + 1], at: pos + 1)
                        pos += 2
                    } else {
                        appendPlain("\\", at: pos)
                        pos += 1
                    }
                    continue
                }

                // HTML 实体（CommonMark §2.5 / §6.9）：`&name;` / `&#dd;` / `&#xhh;`。
                // 解析成对应字符；非法或无分号终结的按字面量保留。
                if c == "&" {
                    if let (decoded, len) = parseEntity(chars, at: pos) {
                        for ch in decoded { appendPlain(ch, at: pos) }
                        pos += len
                    } else {
                        appendPlain("&", at: pos)
                        pos += 1
                    }
                    continue
                }

                // 行内代码（CommonMark §6.1）：反引号串按长度配对——开栏 N 个反引号
                // 只能被恰好 N 个反引号的串闭合（更长的串不算）；内容跨行时换行
                // 视为空格，两端同为空格且非全空格时各剥一格。
                if c == "`" {
                    flushPlain()
                    var openLen = 0
                    while pos + openLen < chars.count, chars[pos + openLen] == "`" { openLen += 1 }
                    var j = pos + openLen
                    var closeStart: Int? = nil
                    while j < chars.count {
                        if chars[j] == "`" {
                            var run = 0
                            while j + run < chars.count, chars[j + run] == "`" { run += 1 }
                            if run == openLen { closeStart = j; break }
                            j += run
                        } else {
                            j += 1
                        }
                    }
                    if let end = closeStart {
                        var code = String(chars[(pos + openLen)..<end])
                        code = code
                            .replacingOccurrences(of: "\u{2028}", with: " ")
                            .replacingOccurrences(of: "\u{2029}", with: " ")
                            .replacingOccurrences(of: "\n", with: " ")
                        if code.count >= 2, code.first == " ", code.last == " ",
                           !code.allSatisfy({ $0 == " " }) {
                            code = String(code.dropFirst().dropLast())
                        }
                        out.append(NSAttributedString(string: code,
                                                      attributes: codeAttributes(outerAttrs(at: pos + openLen, from: base))))
                        pos = end + openLen
                    } else {
                        for _ in 0..<openLen { appendPlain("`", at: pos) }
                        pos += openLen
                    }
                    continue
                }

                // Obsidian 嵌入 ![[note]] / ![[image.png|100]]
                // 必须排在标准图片之前：![[ 里的 "![" 也会被 readDelimited 命中，
                // 但后面没有 (url)，回滚后会把 ! 当普通字符、[[ 又被当成两个裸方括号。
                if c == "!", peek(1) == "[", peek(2) == "[" {
                    flushPlain()
                    if let wiki = readWikiLink(embedded: true) {
                        out.append(wiki)
                        continue
                    }
                }

                // 图片 ![alt](src "title") 与引用式图片 ![alt][ref] / ![alt][]
                if c == "!", peek(1) == "[" {
                    flushPlain()
                    let saved = pos
                    if let raw = readDelimited(open: "![", close: "]") {
                        if let link = readLinkTarget(after: pos) {
                            out.append(imageAttachment(alt: raw, src: link.url, title: link.title))
                            continue
                        }
                        if let ref = readReferenceTarget(label: raw) {
                            out.append(imageAttachment(alt: raw, src: ref.url, title: ref.title))
                            continue
                        }
                    }
                    // 不是完整图片语法（如 ![[]] 嵌入、裸 ![）：readDelimited 已经
                    // 把 pos 推过右括号，必须回滚，否则方括号里的文字会被整段吞掉。
                    pos = saved
                    appendPlain(c, at: pos)
                    pos += 1
                    continue
                }

                // GFM / Obsidian 任务列表复选框 [ ] / [x] / [X]
                // 同属方括号语法：走链接分支回滚后是字面文本，但序列化会被转义成
                // \[ \]，在其它软件里就不再是复选框了。这里显式标记成原样输出。
                if c == "[", pos + 2 < chars.count, chars[pos + 2] == "]",
                   chars[pos + 1] == " " || chars[pos + 1] == "x" || chars[pos + 1] == "X" {
                    flushPlain()
                    let token = String(chars[pos...pos + 2])
                    var attrs = base
                    attrs[.mdTaskBox] = token
                    out.append(NSAttributedString(string: token, attributes: attrs))
                    pos += 3
                    continue
                }

                // Obsidian 双链 [[Note]] / [[Note|别名]] / [[Note#标题]]
                if c == "[", peek(1) == "[" {
                    flushPlain()
                    if let wiki = readWikiLink(embedded: false) {
                        out.append(wiki)
                        continue
                    }
                }

                // 链接 [text](url "title") 与引用式链接 [text][ref] / [text][] / [text]
                if c == "[" {
                    flushPlain()
                    let saved = pos
                    if let raw = readDelimited(open: "[", close: "]") {
                        var labelText = raw
                        var url: String?
                        var linkTitle = ""
                        if let link = readLinkTarget(after: pos) {
                            url = link.url
                            linkTitle = link.title
                            if !link.text.isEmpty { labelText = link.text }
                        } else if let ref = readReferenceTarget(label: raw) {
                            url = ref.url
                            linkTitle = ref.title
                        }
                        if let url {
                            var inner = outerAttrs(at: saved + 1, from: base)
                            inner[.link] = url
                            if !linkTitle.isEmpty { inner[.mdLinkTitle] = linkTitle }
                            inner[.foregroundColor] = DocTheme.accent
                            inner[.underlineStyle] = NSUnderlineStyle.single.rawValue
                            let content = InlineParser.parse(labelText, base: inner)
                            // 空标签链接 `[](url)`：storage 的属性 run 至少要 1 个字符
                            // 才立得住，用零宽空格（ZWSP）占位并挂链接属性；序列化与
                            // HTML 导出剥掉哨兵还原 `[](url)` / `<a href></a>`（CommonMark
                            // §6.3 空标签合法）。
                            if content.length == 0 {
                                out.append(NSAttributedString(string: "\u{200B}", attributes: inner))
                            } else {
                                out.append(content)
                            }
                            continue
                        }
                    }
                    // 引用式链接 [1]、Obsidian 双链 [[...]]、任务框 [ ] 等
                    // 都要按字面文本保留，不能因为后面没有 (url) 就吃掉内容。
                    pos = saved
                    appendPlain(c, at: pos)
                    pos += 1
                    continue
                }

                // 强调定界符：CommonMark 定界符栈已算好哪些字符被配对消耗。
                // 被消耗的不显示（trait 已打在内容上）；未配对的按字面文本保留，
                // 例如 `* foo` 或行尾孤立的 `**`，不能再走递归配对。
                if c == "*" || c == "_" {
                    if plan.skipped.contains(pos) {
                        flushPlain()
                        pos += 1
                    } else {
                        appendPlain(c, at: pos)
                        pos += 1
                    }
                    continue
                }

                // 删除线 ~~ 不属于 CommonMark 强调，仍按成对扫描处理（GFM 扩展）；
                // GFM 也接受单波浪线 ~x~（cmark-gfm / marked 同语义），~~ 优先。
                if c == "~" {
                    let doubled = pos + 1 < chars.count && chars[pos + 1] == "~"
                    if doubled, let end = find("~~", from: pos + 2) {
                        flushPlain()
                        var inner = outerAttrs(at: pos + 2, from: base)
                        inner[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                        let body = String(chars[(pos + 2)..<end])
                        out.append(InlineParser.parse(body, base: inner))
                        pos = end + 2
                        continue
                    }
                    if !doubled, let end = find("~", from: pos + 1) {
                        let body = String(chars[(pos + 1)..<end])
                        if !body.isEmpty,
                           body.first != " ", body.last != " ",
                           body.first != "\t", body.last != "\t" {
                            flushPlain()
                            var inner = outerAttrs(at: pos + 1, from: base)
                            inner[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                            out.append(InlineParser.parse(body, base: inner))
                            pos = end + 1
                            continue
                        }
                    }
                }

                // HTML 标签
                if c == "<" {
                    flushPlain()
                    if let handled = handleTag(into: out) {
                        if handled { continue }
                    }
                    appendPlain(c, at: pos)
                    pos += 1
                    continue
                }

                // GFM 扩展自动链接：裸 http(s):// / www. / 邮箱。
                // 只在词边界识别，链接内部（label 递归解析）不再套娃。
                // 属性走 outerAttrs：`**me@example.com**` 这类强调包着的裸邮箱
                // 必须带上定界符栈算出的粗/斜 trait，否则重建时强调被吞。
                if base[.link] == nil, Self.extAutolinkBoundary(chars, at: pos) {
                    if let auto = Self.extendedAutolink(chars, at: pos) {
                        flushPlain()
                        var attrs = outerAttrs(at: pos, from: base)
                        attrs[.link] = auto.url
                        attrs[.foregroundColor] = DocTheme.accent
                        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                        out.append(NSAttributedString(string: auto.text, attributes: attrs))
                        pos += auto.length
                        continue
                    }
                }

                appendPlain(c, at: pos)
                pos += 1
            }

            flushPlain()
            return out
        }

        // MARK: 工具

        private func peek(_ offset: Int) -> Character? {
            let i = pos + offset
            return i < chars.count ? chars[i] : nil
        }

        /// 从 pos 起的标签形态是否合法（开 / 闭标签，属性区严格校验）。
        /// 用正则整体把关：标签名 ASCII 字母开头，属性名 / 值 / 引号 / 间隔
        /// 都要符合 CommonMark §6.6 的 tag 语法。
        private func tagWellFormed() -> Bool {
            let s = String(chars[pos...].prefix(while: { $0 != ">" }) ) + ">"
            return s.range(
                of: #"^</?[A-Za-z][A-Za-z0-9-]*((\s+[A-Za-z_:][A-Za-z0-9_.:-]*(\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s\"'`=<>]+))?)|(\s*/))*>$"#,
                options: .regularExpression) != nil
        }

        private func matches(_ s: String) -> Bool {
            let arr = Array(s)
            guard pos + arr.count <= chars.count else { return false }
            for (i, ch) in arr.enumerated() where chars[pos + i] != ch { return false }
            return true
        }

        /// GFM 扩展自动链接的词边界：行首 / 空白 / 常见引括号之后才算起词。
        static func extAutolinkBoundary(_ c: [Character], at pos: Int) -> Bool {
            guard pos > 0 else { return true }
            let prev = c[pos - 1]
            return prev.isWhitespace || "\"'([{<*_,;:!?".contains(prev)
        }

        /// GFM 扩展自动链接（https?:// / www. / 邮箱）。返回 url、显示文字与源长。
        static func extendedAutolink(_ c: [Character], at pos: Int) ->
            (url: String, text: String, length: Int)? {
            let rest = String(c[pos...])
            // 裸 URL：http(s):// 或 www.
            let urlPat = "^(https?://[^\\s<>\"'`]+|www\\.[^\\s<>\"'`]+)"
            if let m = rest.range(of: urlPat, options: [.regularExpression]) {
                var text = String(rest[m])
                // 去掉尾部标点与不平衡的右括号
                while let last = text.last, ".,;:!?".contains(last) { text = String(text.dropLast()) }
                while text.hasSuffix(")"), text.filter({ $0 == "(" }).count < text.filter({ $0 == ")" }).count {
                    text = String(text.dropLast())
                }
                guard !text.isEmpty else { return nil }
                let url = text.hasPrefix("www.") ? "http://" + text : text
                return (url, text, text.count)
            }
            // 裸邮箱（GFM：域名末两段不得含 _，末段须字母开头）
            let mailPat = "^[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\\.)+[A-Za-z]{2,}"
            if let m = rest.range(of: mailPat, options: [.regularExpression]) {
                let text = String(rest[m])
                // GFM 约束：@ 后域名的最后两段不能带下划线
                let parts = text.split(separator: "@")
                guard parts.count == 2 else { return nil }
                let domain = parts[1].split(separator: ".")
                guard domain.count >= 2 else { return nil }
                let last2 = domain.suffix(2).joined(separator: ".")
                if last2.contains("_") { return nil }
                return ("mailto:" + text, text, text.count)
            }
            return nil
        }

        private func find(_ s: String, from: Int) -> Int? {
            let arr = Array(s)
            var i = from
            while i + arr.count <= chars.count {
                var ok = true
                for (k, ch) in arr.enumerated() where chars[i + k] != ch { ok = false; break }
                if ok { return i }
                i += 1
            }
            return nil
        }

        /// 读取 `open ... close` 之间的原文（不解析内部强调）。
        /// 方括号按深度配对：`[![badge](img)](url)` 这类嵌套 label 若在第一个 `]`
        /// 就收尾，内层图片的括号会被拆散，序列化时还要加防御性转义。
        /// `\]` 之类转义对深度计数透明（CommonMark：label 内括号须成对）。
        private mutating func readDelimited(open: String, close: String) -> String? {
            guard matches(open) else { return nil }
            let start = pos + open.count
            var depth = 1
            var i = start
            while i < chars.count {
                let ch = chars[i]
                if ch == "\\" {
                    i += 2
                    continue
                }
                if ch == "[" { depth += 1 }
                else if ch == "]" {
                    depth -= 1
                    if depth == 0 {
                        let raw = String(chars[start..<i])
                        pos = i + close.count
                        return raw
                    }
                }
                i += 1
            }
            return nil
        }

        /// 引用式链接目标：`[text][ref]`（全引用）/ `[text][]`（折叠）/ `[text]`（快捷）。
        /// 只有在定义表里查得到才消费语法；否则**不推进 pos**，让调用方按字面文本回退。
        private mutating func readReferenceTarget(label: String) -> (url: String, title: String)? {
            if pos < chars.count, chars[pos] == "[" {
                var j = pos + 1
                while j < chars.count, chars[j] != "]" {
                    if chars[j] == "\\" { j += 1 }
                    j += 1
                }
                guard j < chars.count else { return nil }
                let ref = String(chars[(pos + 1)..<j])
                let key = ref.isEmpty ? label : ref
                if let target = Self.lookupRef(key) {
                    pos = j + 1
                    return target
                }
                return nil
            }
            // 快捷式：label 本身就是引用名（如 [foo] 配 [foo]: url）
            return Self.lookupRef(label)
        }

        private static func lookupRef(_ label: String) -> (url: String, title: String)? {
            InlineParser.references[InlineParser.normalizeLabel(label)]
        }

        /// 读取 Obsidian 双链 / 嵌入。失败时**不推进 pos**，让调用方按字面文本继续处理。
        private mutating func readWikiLink(embedded: Bool) -> NSAttributedString? {
            let open = embedded ? "![[" : "[["
            guard matches(open) else { return nil }
            let start = pos + open.count
            guard let end = find("]]", from: start) else { return nil }
            let inner = String(chars[start..<end])
            guard !inner.isEmpty,
                  !inner.contains("["), !inner.contains("]"), !inner.contains("\n") else { return nil }

            // target[#heading / #^block] [| alias 或尺寸]
            let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let targetPart = String(parts[0])
            let alias = parts.count > 1 ? String(parts[1]) : ""
            guard !targetPart.isEmpty else { return nil }

            let suffix: String
            let target: String
            if let hash = targetPart.firstIndex(of: "#") {
                target = String(targetPart[targetPart.startIndex..<hash])
                suffix = String(targetPart[hash...])
            } else {
                target = targetPart
                suffix = ""
            }
            guard !target.isEmpty else { return nil }

            let raw = open + inner + "]]"
            let link = MDWikiLink(raw: raw, target: target, suffix: suffix,
                                  alias: alias, embedded: embedded)
            pos = end + 2

            var attrs = base
            attrs[.mdWikiLink] = link
            attrs[.foregroundColor] = DocTheme.accent
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            // 双链不是标准链接，别让 .link 把它序列化成 [text](url)
            attrs.removeValue(forKey: .link)
            return NSAttributedString(string: link.display, attributes: attrs)
        }

        /// 读取紧随其后的 `(url "title")` / `(url 'title')` / `(url (title))` / `(<url>)`，
        /// 并把 pos 移到右括号之后。目标区解析不出来时返回 nil、不推进 pos，
        /// 整段按字面文本处理（CommonMark：`[a](<b)c` 这类畸形目标不是链接）。
        /// 尖括号目标里的括号是内容、对深度计数透明（`[link](<foo(and(bar)>)` 合法）；
        /// 裸目标的括号深度计数对 `\(` `\)` 转义透明。
        private mutating func readLinkTarget(after: Int) -> (url: String, title: String, text: String)? {
            guard pos < chars.count, chars[pos] == "(" else { return nil }
            var i = pos + 1
            while i < chars.count,
                  chars[i] == " " || chars[i] == "\t" || chars[i] == "\u{2028}" || chars[i] == "\n" {
                i += 1
            }
            var buf = [Character]()
            if i < chars.count, chars[i] == "<" {
                buf.append("<")
                i += 1
                var closed = false
                while i < chars.count {
                    let ch = chars[i]
                    if ch == "\\" && i + 1 < chars.count {
                        buf.append(ch); buf.append(chars[i + 1]); i += 2
                        continue
                    }
                    // 尖括号目标不含换行、不含裸 <
                    if ch == "\u{2028}" || ch == "\n" || ch == "<" { return nil }
                    buf.append(ch)
                    if ch == ">" { closed = true; i += 1; break }
                    i += 1
                }
                guard closed else { return nil }
            }
            var depth = 1
            while i < chars.count {
                let ch = chars[i]
                if ch == "\\" && i + 1 < chars.count {
                    buf.append(ch); buf.append(chars[i + 1]); i += 2
                    continue
                }
                if ch == "(" { depth += 1 }
                if ch == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
                buf.append(ch)
                i += 1
            }
            guard i < chars.count else { return nil }
            let raw = String(buf)
            guard let parsed = Self.parseLinkDestination(raw) else { return nil }
            pos = i + 1
            return (parsed.url, parsed.title, "")
        }

        /// CommonMark 链接目标：`<...>` 或非空白串做 destination，其后是可选空白
        /// 加可选 title（`"..."` / `'...'` / `(...)`），尾部不允许再有杂字。
        /// 任何一处不符合就返回 nil（畸形目标不是链接），由调用方按字面文本处理。
        /// 行内链接的空目标 `[x]()` 合法（§6.3）。
        private static func parseLinkDestination(_ raw: String)
            -> (url: String, title: String)? {
            InlineParser.parseLinkDestination(raw, allowEmpty: true)
        }

        private func emphasis(at index: Int) -> (Emphasis, Int)? {
            let s = String(chars[index...].prefix(2))
            if s.hasPrefix("**") { return (.bold, 2) }
            if s.hasPrefix("__") { return (.bold, 2) }
            if s.hasPrefix("~~") { return (.strike, 2) }
            if s.hasPrefix("*") { return (.italic, 1) }
            if s.hasPrefix("_") { return (.italic, 1) }
            return nil
        }

        enum Emphasis {
            case bold, italic, strike
            var delimiter: String {
                switch self {
                case .bold: return "**"
                case .italic: return "*"
                case .strike: return "~~"
                }
            }
        }

        // MARK: HTML 标签

        /// 未识别 / 无渲染语义的 HTML（img、iframe、details…）按原样整段保留：
        /// 显示层就是源码文本，序列化逐字写回，不做转义、不拆解内部结构。
        private func opaqueHTML(_ raw: String, into out: NSMutableAttributedString) {
            var attrs = base
            attrs[.mdInlineHTML] = raw
            out.append(NSAttributedString(string: raw, attributes: attrs))
        }

        private mutating func handleTag(into out: NSMutableAttributedString) -> Bool? {
            // 注释 / 处理指令 / CDATA / 声明有自己的终结符，不能用第一个 ">"
            // 截断（`<!-- a > b -->` 里的 `>` 不是注释终点）。
            if matches("<!--") {
                guard let end = find("-->", from: pos) else { return false }
                let text = String(chars[pos..<(end + 3)])
                opaqueHTML(text, into: out)
                pos = end + 3
                return true
            }
            if matches("<?") {
                guard let end = find("?>", from: pos) else { return false }
                let text = String(chars[pos..<(end + 2)])
                opaqueHTML(text, into: out)
                pos = end + 2
                return true
            }
            if matches("<![CDATA[") {
                guard let end = find("]]>", from: pos) else { return false }
                let text = String(chars[pos..<(end + 3)])
                opaqueHTML(text, into: out)
                pos = end + 3
                return true
            }
            if matches("<!"), pos + 2 < chars.count,
               chars[pos + 2].isUppercase {
                guard let gt0 = find(">", from: pos) else { return false }
                let text = String(chars[pos...gt0])
                opaqueHTML(text, into: out)
                pos = gt0 + 1
                return true
            }
            // 闭合标签（</x>）：合法形态时按行内 HTML 原样保留（CommonMark §6.6）
            if matches("</") {
                guard let gtC = find(">", from: pos), tagWellFormed() else { return false }
                opaqueHTML(String(chars[pos...gtC]), into: out)
                pos = gtC + 1
                return true
            }

            guard let gt = find(">", from: pos) else { return nil }
            let tagText = String(chars[pos...gt])

            // 自动链接 <https://example.com> / <user@example.com>：不是标签，
            // 按 CommonMark §6.9 解析成「显示文字 = 地址」的链接。
            if let auto = Self.autolink(tagText) {
                var attrs = base
                attrs[.link] = auto.url
                attrs[.foregroundColor] = DocTheme.accent
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                out.append(NSAttributedString(string: auto.text, attributes: attrs))
                pos = gt + 1
                return true
            }

            let name = String(tagText.dropFirst().prefix(while: { $0.isLetter })).lowercased()
            guard !name.isEmpty else { return false }

            // 空元素 / 自闭合：<br> 变硬换行，<hr> 变分割线附件，其余原样保留
            let voidElements: Set<String> = ["img", "input", "wbr", "source", "track",
                                             "col", "area", "base", "embed", "param",
                                             "meta", "link", "picture", "svg", "path"]
            if tagText.hasSuffix("/>") || name == "br" || name == "hr"
                || voidElements.contains(name) {
                pos = gt + 1
                if name == "br" {
                    // <br> 是硬换行：两空格 + 段内换行，序列化还原 "  \n"。
                    // 后面紧跟的源码换行**不再吞并**：`x<br>\ny` 在 GFM（breaks:true）
                    // 下是两个换行标记（<br> 标签 + 软换行），折叠成语义分歧（B4x）。
                    // 双标记写回由序列化器的换行段规则处理（`<br>\n` / `<br><br>`），
                    // 不会退化成 "  \n\n" 把段落误拆（B24 的原始问题）。
                    out.append(NSAttributedString(string: "  \u{2028}", attributes: base))
                } else if name == "hr" {
                    out.append(NSAttributedString(attachment: MDRuleAttachment()))
                } else {
                    opaqueHTML(tagText, into: out)
                }
                return true
            }

            // 需要闭合标签
            let closeTag = "</\(name)>"
            guard let closeStart = findMatchingClose(tag: name, from: gt + 1) else {
                // 独立开标签（`<same>` 这类无闭合）也是合法行内 HTML（CommonMark
                // §6.6）：形态合法就整段原样保留；非法形态按字面文本。
                if tagWellFormed() {
                    opaqueHTML(tagText, into: out)
                    pos = gt + 1
                    return true
                }
                return false
            }
            let innerStart = gt + 1
            let inner = String(chars[innerStart..<closeStart])

            // <code> 内容按 HTML 语义是字面文本，不能再解析 Markdown
            // （否则 `[link](url)` 里的地址会在重建时被吃掉）。
            if name == "code" {
                pos = closeStart + closeTag.count
                opaqueHTML(tagText + inner + closeTag, into: out)
                return true
            }

            // 未识别的成对标签整段原样保留：拆解重建会丢属性、丢内层标签。
            // <a> 里包着空元素 / 未识别 HTML 时（如 <a href><img></a>）同样整段保留，
            // 否则内层 <img> 会被拆成转义文本、外层 href 在重建时丢失。
            // 已知标签带不可重建属性（class / id / 非颜色 style）时也整段保留，
            // 否则 <span class="msrv"> 这类属性会在拆解时永久丢失（CommonMark §6.6）。
            let known: Set<String> = ["span", "mark", "u", "strong", "b", "em", "i",
                                      "del", "s", "a"]
            let innerHasOpaque = inner.range(
                of: #"<(img|input|wbr|source|track|col|area|base|embed|param|meta|link|picture|svg|path|iframe|details|div|table|pre|button|video|audio|object|canvas|form|script|style|code)\b"#,
                options: [.regularExpression, .caseInsensitive]) != nil
            if !known.contains(name) || !Self.canDecompose(name: name, tagText: tagText)
                || (name == "a" && innerHasOpaque) {
                pos = closeStart + closeTag.count
                opaqueHTML(tagText + inner + closeTag, into: out)
                return true
            }

            var innerAttrs = base
            switch name {
            case "span":
                let style = Self.styleValue(of: "style", in: tagText)
                if let c = Self.cssColor(style, key: "color"), let color = NSColor(hex: c) {
                    innerAttrs[.foregroundColor] = DocTheme.displayTextColor(color)
                    innerAttrs[.mdTextColor] = color
                }
                if let c = Self.cssColor(style, key: "background-color"), let color = NSColor(hex: c) {
                    innerAttrs[.backgroundColor] = DocTheme.displayHighlight(color)
                    innerAttrs[.mdHighlight] = color
                }
            case "mark":
                let style = Self.styleValue(of: "style", in: tagText)
                if let c = Self.cssColor(style, key: "background-color"), let color = NSColor(hex: c) {
                    innerAttrs[.backgroundColor] = DocTheme.displayHighlight(color)
                    innerAttrs[.mdHighlight] = color
                } else {
                    innerAttrs[.backgroundColor] = DocTheme.displayHighlight(DocTheme.defaultHighlight)
                    innerAttrs[.mdHighlight] = DocTheme.defaultHighlight
                }
            case "u":
                innerAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case "strong", "b":
                innerAttrs[.font] = FontTraits.adding(.bold, to: base[.font])
                innerAttrs[.mdUserBold] = true
            case "em", "i":
                innerAttrs[.font] = FontTraits.adding(.italic, to: base[.font])
            case "del", "s":
                innerAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case "a":
                if let href = Self.attributeValue(of: "href", in: tagText) {
                    innerAttrs[.link] = href as NSString
                    if let t = Self.attributeValue(of: "title", in: tagText), !t.isEmpty {
                        innerAttrs[.mdLinkTitle] = t
                    }
                    innerAttrs[.foregroundColor] = DocTheme.accent
                    innerAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
            default:
                break
            }

            out.append(InlineParser.parse(inner, base: innerAttrs))
            pos = closeStart + closeTag.count
            return true
        }

        /// `<scheme:rest>` / `<mailbox>` 形式的自动链接
        private static func autolink(_ tagText: String) -> (text: String, url: String)? {
            guard tagText.hasPrefix("<"), tagText.hasSuffix(">"), tagText.count > 2 else { return nil }
            let body = String(tagText.dropFirst().dropLast())
            guard !body.isEmpty, !body.contains(" "), !body.contains("<"), !body.contains(">") else {
                return nil
            }
            if let colon = body.firstIndex(of: ":"),
               colon > body.startIndex {
                let scheme = body[body.startIndex..<colon]
                guard scheme.count >= 2,
                      scheme.first!.isLetter,
                      scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" })
                else { return nil }
                return (body, body)
            }
            // 邮箱：<user@example.com>
            if body.contains("@"),
               body.range(of: #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#,
                          options: .regularExpression) != nil {
                return (body, "mailto:" + body)
            }
            return nil
        }

        private func findMatchingClose(tag: String, from: Int) -> Int? {
            let open = "<\(tag)"
            let close = "</\(tag)>"
            var depth = 1
            var i = from
            while i < chars.count {
                if substring(at: i, matches: open) && !substring(at: i, matches: close) {
                    // 只统计真正的开标签（后面跟空格或 >）
                    let after = i + open.count
                    if after < chars.count, chars[after] == ">" || chars[after] == " " {
                        depth += 1
                    }
                } else if substring(at: i, matches: close) {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i += 1
            }
            return nil
        }

        private func substring(at index: Int, matches s: String) -> Bool {
            let arr = Array(s)
            guard index + arr.count <= chars.count else { return false }
            for (i, ch) in arr.enumerated() where chars[index + i] != ch { return false }
            return true
        }

        static func styleValue(of attr: String, in tag: String) -> String {
            guard let r = tag.range(of: "\(attr)=\"") else { return "" }
            let rest = tag[r.upperBound...]
            guard let end = rest.range(of: "\"") else { return "" }
            return String(rest[rest.startIndex..<end.lowerBound])
        }

        /// 解析开标签里「标签名之后到 > 之前」的属性区。
        /// 返回 (属性名, 值, 是否双引号) 列表；任何畸形写法返回 nil，
        /// 调用方一律按「不可拆解」处理（宁可原样保留也不丢信息）。
        private static func parseAttrsRegion(_ tagText: String)
            -> [(name: String, value: String, doubleQuoted: Bool)]? {
            var rest = tagText.dropFirst()                    // 去掉 <
            rest = rest.drop(while: { $0.isLetter })          // 去掉标签名
            guard let gt = rest.firstIndex(of: ">") else { return nil }
            var region = String(rest[rest.startIndex..<gt])
            region = region.trimmingCharacters(in: .whitespaces)
            if region.hasSuffix("/") {
                region = String(region.dropLast()).trimmingCharacters(in: .whitespaces)
            }
            var result: [(name: String, value: String, doubleQuoted: Bool)] = []
            var i = region.startIndex
            func skipSpace() {
                while i < region.endIndex, region[i].isWhitespace { i = region.index(after: i) }
            }
            skipSpace()
            while i < region.endIndex {
                let ns = i
                while i < region.endIndex,
                      region[i].isLetter || region[i].isNumber
                        || region[i] == "-" || region[i] == "_" || region[i] == ":" {
                    i = region.index(after: i)
                }
                guard i > ns else { return nil }
                let name = String(region[ns..<i])
                skipSpace()
                guard i < region.endIndex, region[i] == "=" else {
                    result.append((name, "", false))          // 裸属性
                    continue
                }
                i = region.index(after: i)
                skipSpace()
                guard i < region.endIndex else { return nil }
                if region[i] == "\"" || region[i] == "'" {
                    let q = region[i]
                    let vs = region.index(after: i)
                    var j = vs
                    while j < region.endIndex, region[j] != q { j = region.index(after: j) }
                    guard j < region.endIndex else { return nil }
                    result.append((name, String(region[vs..<j]), q == "\""))
                    i = region.index(after: j)
                } else {
                    let vs = i
                    while i < region.endIndex, !region[i].isWhitespace { i = region.index(after: i) }
                    result.append((name, String(region[vs..<i]), false))
                }
                skipSpace()
            }
            return result
        }

        /// style 值能否被属性模型完整重建：只允许颜色 / 背景色声明，
        /// 且每条声明都取得到有效颜色。`class`、`font-size` 这类重建不出来的
        /// 信息一旦拆解就永久丢失，必须整段不透明保留（CommonMark §6.6）。
        private static func styleIsDecomposable(_ style: String, allowed: Set<String>) -> Bool {
            var seen = false
            for part in style.split(separator: ";") {
                let p = part.trimmingCharacters(in: .whitespaces)
                if p.isEmpty { continue }
                let kv = p.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard kv.count == 2 else { return false }
                let key = kv[0].trimmingCharacters(in: .whitespaces)
                guard allowed.contains(key) else { return false }
                guard let v = cssColor(style, key: key), NSColor(hex: v) != nil else { return false }
                seen = true
            }
            return seen
        }

        /// 成对「已知」标签能否安全拆解重建：属性必须全部能被属性模型重建。
        /// `<span class="msrv">` 这类带 class / id / 非颜色 style 的标签，
        /// 拆解会让属性永久丢失（comrak 语料实测），只能整段按不透明 HTML 保留。
        private static func canDecompose(name: String, tagText: String) -> Bool {
            guard let attrs = parseAttrsRegion(tagText) else { return false }
            switch name {
            case "u", "strong", "b", "em", "i", "del", "s":
                return attrs.isEmpty
            case "span":
                guard attrs.count == 1, attrs[0].name == "style", attrs[0].doubleQuoted else {
                    return false
                }
                return styleIsDecomposable(attrs[0].value, allowed: ["color", "background-color"])
            case "mark":
                if attrs.isEmpty { return true }   // 无样式 <mark> 默认高亮（既定行为）
                guard attrs.count == 1, attrs[0].name == "style", attrs[0].doubleQuoted else {
                    return false
                }
                return styleIsDecomposable(attrs[0].value, allowed: ["background-color"])
            case "a":
                guard !attrs.isEmpty else { return false }
                guard attrs.allSatisfy({ ($0.name == "href" || $0.name == "title") && $0.doubleQuoted })
                else { return false }
                return attrs.contains { $0.name == "href" }
            default:
                return false
            }
        }

        static func attributeValue(of attr: String, in tag: String) -> String? {
            let pattern = "\(attr)=\""
            guard let r = tag.range(of: pattern) else { return nil }
            let rest = tag[r.upperBound...]
            guard let end = rest.range(of: "\"") else { return nil }
            return String(rest[rest.startIndex..<end.lowerBound])
        }

        /// 从 "color:#d64545;background-color:#fff3a3" 里取某个 css 属性
        static func cssColor(_ style: String, key: String) -> String? {
            for part in style.split(separator: ";") {
                let kv = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == key {
                    var v = kv[1].trimmingCharacters(in: .whitespaces)
                    if v.hasPrefix("#") == false, v.count == 6 { v = "#" + v }
                    return v
                }
            }
            return nil
        }

        // MARK: 附件

        private func imageAttachment(alt: String, src: String, title: String) -> NSAttributedString {
            let att = MDImageAttachment(src: src, alt: alt, title: title)
            let obj = NSMutableAttributedString(attachment: att)
            // 继承 base 里的链接等属性：`[![alt](img)](url)` 的递归 label 解析
            // 带着 .link 进来，丢了它序列化时就只剩裸图片、外层链接消失。
            var attrs = base
            attrs[.attachment] = att
            obj.setAttributes(attrs, range: NSRange(location: 0, length: obj.length))
            // alt 作为无障碍描述保留在附件上，不在正文里显示
            return obj
        }
    }
}

// MARK: - 辅助

enum FontTraits {
    static func adding(_ trait: NSFontDescriptor.SymbolicTraits,
                       to value: Any?) -> NSFont {
        let font = value as? NSFont ?? DocTheme.bodyFont
        let d = font.fontDescriptor
        let merged = d.withSymbolicTraits(d.symbolicTraits.union(trait))
        return NSFont(descriptor: merged, size: font.pointSize) ?? font
    }

    static func removing(_ trait: NSFontDescriptor.SymbolicTraits,
                         from value: Any?) -> NSFont {
        let font = value as? NSFont ?? DocTheme.bodyFont
        let d = font.fontDescriptor
        let rest = d.symbolicTraits.subtracting(trait)
        let merged = d.withSymbolicTraits(rest)
        return NSFont(descriptor: merged, size: font.pointSize) ?? font
    }

    static func has(_ trait: NSFontDescriptor.SymbolicTraits, in value: Any?) -> Bool {
        guard let font = value as? NSFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(trait)
    }
}

/// 行内代码的属性组合
func codeAttributes(_ base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
    var a = base
    let baseFont = base[.font] as? NSFont
    let size = baseFont?.pointSize ?? DocTheme.bodyFontSize
    let traits = baseFont?.fontDescriptor.symbolicTraits ?? []
    var font = DocTheme.monospacedFont(size: size * 0.88)
    // 强调里的代码 span：粗 / 斜 trait 必须带上，否则 `**`code`**`
    // 的代码 run 丢了粗体，序列化重建时强调范围被撕开。
    if traits.contains(.bold) { font = FontTraits.adding(.bold, to: font) }
    if traits.contains(.italic) { font = FontTraits.adding(.italic, to: font) }
    a[.font] = font
    a[.mdInlineCode] = true
    a[.backgroundColor] = DocTheme.codeBackground
    a[.foregroundColor] = DocTheme.inlineCodeText
    return a
}

private extension NSMutableAttributedString {
    func appendingFlush(_ chars: [Character], _ attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        if !chars.isEmpty {
            append(NSAttributedString(string: String(chars), attributes: attrs))
        }
        return self
    }
}
