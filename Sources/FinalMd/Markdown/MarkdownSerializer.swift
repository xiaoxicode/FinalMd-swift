//
//  MarkdownSerializer.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  NSAttributedString → Markdown / HTML。
//  先把文档切成块（DocBlock），再分别用 Markdown、HTML 两种发射器输出，
//  保证「保存 .md」与「导出 HTML」共用同一套块级语义。
//

import AppKit

// MARK: - 块模型

enum DocBlock {
    case heading(level: Int, content: NSAttributedString)
    case paragraph(NSAttributedString)
    case quote(NSAttributedString)
    case code(String, language: String)
    case rule
    case listItem(ordered: Bool, level: Int, content: NSAttributedString, indent: Int? = nil)
    case image(MDImageAttachment)
    case table(rows: [[NSAttributedString]], hasHeader: Bool)
    /// 原样透传块：不解析、不转义、不规范化，逐字写回 Markdown。
    case raw(String, kind: MDRawKind)
    /// Obsidian Callout：lines 是去掉 "> " 前缀后的原始行，写回时逐行加回前缀。
    case callout(lines: [String], kind: String, fold: String)
}

enum MarkdownSerializer {

    // MARK: 入口

    static func markdown(from attr: NSAttributedString) -> String {
        let blocks = blocks(from: attr)
        var pieces: [String] = []
        var orderedCounters: [Int: Int] = [:]   // level -> 已输出的有序项数量
        var lastLevel = -1
        var previousWasListItem = false
        var previousListOrdered = false
        var previousListLevel = 0
        // 列表项附属的缩进容器块：与所属列表项之间不插空行，也不重置有序编号
        var previousWasListContinuation = false

        for block in blocks {
            var text = ""
            var isListItem = false
            var isListContinuation = false
            var listOrdered = false
            var listLevel = 0

            switch block {
            case .heading(let level, let content):
                text = String(repeating: "#", count: level) + " " + InlineSerializer.markdown(content)
                orderedCounters.removeAll()
                lastLevel = -1

            case .paragraph(let content):
                text = InlineSerializer.markdown(content)
                orderedCounters.removeAll()
                lastLevel = -1

            case .quote(let content):
                let md = InlineSerializer.markdown(content)
                text = md.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "> " + $0 }.joined(separator: "\n")
                orderedCounters.removeAll()
                lastLevel = -1

            case .code(let code, let language):
                text = "```\(language)\n\(code)\n```"
                orderedCounters.removeAll()
                lastLevel = -1

            case .rule:
                text = "---"
                orderedCounters.removeAll()
                lastLevel = -1

            case .listItem(let ordered, let level, let content, let originalIndent):
                isListItem = true
                listOrdered = ordered
                listLevel = level
                // 列表项文本里带着成文用的符号（"- " / "1. "），输出前剥掉
                var body = content
                let s = body.string
                if let sp = s.firstIndex(of: " ") {
                    let drop = s.distance(from: s.startIndex, to: sp) + 1
                    if drop < body.length {
                        body = body.attributedSubstring(from: NSRange(location: drop, length: body.length - drop))
                    }
                }
                // 解析时记下的原始缩进优先：4 空格嵌套列表不能被压成 2 空格/级，
                // 否则下一轮会丢失 zettlr / Logseq 语料里的容器块缩进。
                let indent = originalIndent.map { String(repeating: " ", count: $0) }
                    ?? String(repeating: "  ", count: level)
                if ordered {
                    if level != lastLevel { orderedCounters[level] = 0 }
                    let n = (orderedCounters[level] ?? 0) + 1
                    orderedCounters[level] = n
                    text = "\(indent)\(n). " + InlineSerializer.markdown(body)
                } else {
                    text = "\(indent)- " + InlineSerializer.markdown(body)
                }
                lastLevel = level

            case .image(let att):
                if att.mdTitle.isEmpty {
                    text = "![\(att.alt)](\(att.src))"
                } else {
                    text = "![\(att.alt)](\(att.src) \"\(att.mdTitle)\")"
                }
                orderedCounters.removeAll()
                lastLevel = -1

            case .table(let rows, let hasHeader):
                var lines: [String] = []
                for (r, row) in rows.enumerated() {
                    let cells = row.map { InlineSerializer.markdown($0).replacingOccurrences(of: "|", with: "\\|") }
                    lines.append("| " + cells.joined(separator: " | ") + " |")
                    if r == 0 {
                        lines.append("| " + row.map { _ in "---" }.joined(separator: " | ") + " |")
                    }
                }
                _ = hasHeader
                text = lines.joined(separator: "\n")
                orderedCounters.removeAll()
                lastLevel = -1

            case .raw(let source, let kind):
                // 整块逐字输出：frontmatter 的换行、HTML 的尖括号、链接定义的方括号
                // 都不经过 InlineSerializer，也就不会被 escapeMarkdown 改写。
                text = source
                // 列表项内的缩进容器块仍属于同一个列表：既不插空行，也不重置
                // orderedCounters（否则 "1. foo / 缩进代码 / 2. bar" 会变回 "1. bar"）。
                isListContinuation = kind == .listIndented || kind == .listCode
                if !isListContinuation {
                    orderedCounters.removeAll()
                    lastLevel = -1
                }

            case .callout(let lines, _, _):
                // Callout 多行属于同一个块，必须一次输出，不能像 quote 那样按段落拆成
                // 多个块再插入空行（那会把 > [!NOTE] 和后续 > 内容拆散）。
                text = lines.map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
                orderedCounters.removeAll()
                lastLevel = -1
            }

            // 连续的列表项之间不留空行（紧列表）；列表项附属的缩进容器块
            // 与所属列表项同样不留空行，其余块之间空一行
            if !pieces.isEmpty {
                let sameList = previousWasListItem && isListItem
                    && previousListOrdered == listOrdered
                    && previousListLevel == listLevel
                // 只在「列表项 ↔ 它的附属容器行」之间紧连；附属行后面若接
                // 普通段落，仍要空一行，否则第二轮解析会把普通段落重新拆开
                // 并补上空行，导致 out1 != out2（失去一次稳定）。
                let attached =
                    (isListContinuation && (previousWasListItem || previousWasListContinuation))
                    || (previousWasListContinuation && isListItem)
                pieces.append(sameList || attached ? "\n" : "\n\n")
            }
            pieces.append(text)
            previousWasListItem = isListItem
            previousListOrdered = listOrdered
            previousListLevel = listLevel
            previousWasListContinuation = isListContinuation
        }

        return pieces.joined() + "\n"
    }

    /// 与 MarkdownParser 的 emphasisFingerprint 同口径：B=粗、I=斜、X=粗斜、-=无。
    /// 用来判断强调行是否「只改了格式没改文字」——这种情况快照必须失效，
    /// 否则用户按 ⌘B / ⌘I 的改动会被旧源码盖掉。
    static func emphasisFingerprint(_ attr: NSAttributedString) -> String {
        var out = ""
        out.reserveCapacity(attr.length)
        for i in 0..<attr.length {
            let font = attr.attribute(.font, at: i, effectiveRange: nil) as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let bold = traits.contains(.bold)
            let italic = traits.contains(.italic)
            out.append(bold ? (italic ? "X" : "B") : (italic ? "I" : "-"))
        }
        return out
    }

    /// 空段落若是表格单元格，不能按「空行」跳过：
    /// Parser 会为空格子生成带 NSTextTableBlock 的空段落并占住 row/col，
    /// 序列化时跳过它就会让后续单元格行号错位，每往返一次多出一个 `|  |` 空行。
    private static func isTableCellParagraph(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
        guard let style = attrs[.paragraphStyle] as? NSParagraphStyle else { return false }
        return style.textBlocks.contains { $0 is NSTextTableBlock }
    }

    // MARK: 块切分

    static func blocks(from attr: NSAttributedString) -> [DocBlock] {
        let ns = attr.string as NSString
        var result: [DocBlock] = []

        // 表格累积器
        var tableRows: [[NSAttributedString]] = []
        var tableHeader = false

        func flushTable() {
            guard !tableRows.isEmpty else { return }
            result.append(.table(rows: tableRows, hasHeader: tableHeader))
            tableRows = []
            tableHeader = false
        }

        var loc = 0
        while loc < ns.length {
            let range = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            if range.length == 0 { break }
            loc = NSMaxRange(range)

            let para = trimTrailing(attr.attributedSubstring(from: range))
            // 属性要直接从原文档读：空行只有一个 \n，trimTrailing 之后就没字符可取了，
            // 而空行同样可能是透传块的一部分。
            let attrs = attr.attributes(at: range.location, effectiveRange: nil)

            // 原样透传块：把「连续且同一 ID」的段落按原始行拼回一整块。
            // 显示的文字本身就是源码——用户若在块内编辑过，编辑结果会原样写出，
            // 不存在「藏着一份旧源码把用户改动盖掉」的风险。
            if (attrs[.mdBlockType] as? String) == MDBlockType.raw.rawValue,
               let rawID = attrs[.mdRawID] as? Int {
                flushTable()
                var rawLines: [String] = [para.string]
                while loc < ns.length {
                    let next = ns.paragraphRange(for: NSRange(location: loc, length: 0))
                    if next.length == 0 { break }
                    let nextAttrs = attr.attributes(at: next.location, effectiveRange: nil)
                    guard (nextAttrs[.mdBlockType] as? String) == MDBlockType.raw.rawValue,
                          (nextAttrs[.mdRawID] as? Int) == rawID else { break }
                    rawLines.append(trimTrailing(attr.attributedSubstring(from: next)).string)
                    loc = NSMaxRange(next)
                }
                let kind = MDRawKind(rawValue: attrs[.mdRawKind] as? String ?? "") ?? .html
                result.append(.raw(rawLines.joined(separator: "\n"), kind: kind))
                continue
            }

            if para.length == 0, !isTableCellParagraph(attrs),
               (attrs[.mdBlockType] as? String) != MDBlockType.callout.rawValue { continue }

            // Obsidian Callout：连续且同 ID 的行聚合成一个块，逐行写回。
            // 行内强调已真解析成富文本，未编辑时靠快照逐字输出原行。
            if (attrs[.mdBlockType] as? String) == MDBlockType.callout.rawValue,
               let calloutID = attrs[.mdCalloutID] as? Int {
                flushTable()
                var lines: [String] = [calloutLine(from: para, attrs: attrs)]
                while loc < ns.length {
                    let next = ns.paragraphRange(for: NSRange(location: loc, length: 0))
                    if next.length == 0 { break }
                    let nextAttrs = attr.attributes(at: next.location, effectiveRange: nil)
                    guard (nextAttrs[.mdBlockType] as? String) == MDBlockType.callout.rawValue,
                          (nextAttrs[.mdCalloutID] as? Int) == calloutID else { break }
                    lines.append(calloutLine(from: trimTrailing(attr.attributedSubstring(from: next)),
                                             attrs: nextAttrs))
                    loc = NSMaxRange(next)
                }
                let kind = attrs[.mdCalloutKind] as? String ?? "NOTE"
                let fold = attrs[.mdCalloutFold] as? String ?? ""
                result.append(.callout(lines: lines, kind: kind, fold: fold))
                continue
            }

            if para.length == 0, !isTableCellParagraph(attrs) { continue }

            // 附件（图片 / 分割线）
            if let attachment = attrs[.attachment] {
                if let image = attachment as? MDImageAttachment {
                    flushTable()
                    result.append(.image(image))
                    continue
                }
                if attachment is MDRuleAttachment {
                    flushTable()
                    result.append(.rule)
                    continue
                }
                // 内联嵌入卡片不是独占段落的附件：整段照常序列化，
                // 由 InlineSerializer 把 U+FFFC 还原成原始 ![[...]] 语法。
                if attachment is MDEmbedAttachment { /* fall through */ }
                else { continue }
            }

            // 表格单元格
            if let style = attrs[.paragraphStyle] as? NSParagraphStyle,
               let tableBlock = style.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first {
                let row = tableBlock.startingRow
                let col = tableBlock.startingColumn
                while tableRows.count <= row { tableRows.append([]) }
                // Parser 为每个 cell 追加一个末尾 \n，于是「内容段落 + 空段落」会先后出现；
                // 只保留第一次收集到的内容，后续空段落不能覆盖（否则整表被清空）。
                // 行首缺列时用空 cell 补齐，保持列号与 NSTextTableBlock 一致。
                while tableRows[row].count < col { tableRows[row].append(NSAttributedString(string: "")) }
                if tableRows[row].count == col { tableRows[row].append(para) }
                if row == 0, (attrs[.mdTableHeader] as? Bool) == true { tableHeader = true }
                continue
            }
            flushTable()

            // 列表项
            if let item = attrs[.mdListItem] as? MDListItem {
                result.append(.listItem(ordered: item.ordered, level: item.level,
                                        content: para, indent: item.indent))
                continue
            }

            let rawType = attrs[.mdBlockType] as? String ?? MDBlockType.paragraph.rawValue
            let type = MDBlockType(rawValue: rawType) ?? .paragraph

            switch type {
            case .code:
                // 代码块可能跨多个「段」，一直吃到块类型变化为止
                var text = para.string
                while loc < ns.length {
                    let next = ns.paragraphRange(for: NSRange(location: loc, length: 0))
                    if next.length == 0 { break }
                    let nextAttrs = attr.attributes(at: next.location, effectiveRange: nil)
                    guard (nextAttrs[.mdBlockType] as? String) == MDBlockType.code.rawValue else { break }
                    text += "\n" + trimTrailing(attr.attributedSubstring(from: next)).string
                    loc = NSMaxRange(next)
                }
                let language = attrs[.mdCodeLanguage] as? String ?? ""
                result.append(.code(text, language: language))

            case .quote:
                result.append(.quote(para))

            case .paragraph:
                result.append(.paragraph(para))

            default:
                if let level = type.headingLevel {
                    result.append(.heading(level: level, content: para))
                } else {
                    result.append(.paragraph(para))
                }
            }
        }

        flushTable()
        return result
    }

    /// Callout 单行：行内强调已解析成富文本，但原行写法（`*斜*` 还是 `_斜_`、
    /// 折叠标记、双链原语法）必须逐字保住。
    /// 显示文字与解析快照一致 → 说明用户没编辑过，直接输出原行；
    /// 不一致 → 用户改过内容，按当前富文本重建，不让旧源码盖掉编辑。
    private static func calloutLine(from para: NSAttributedString,
                                    attrs: [NSAttributedString.Key: Any]) -> String {
        let shown = para.string
        if let source = attrs[.mdCalloutSource] as? String,
           let display = attrs[.mdCalloutDisplay] as? String,
           shown == display {
            return source
        }
        return InlineSerializer.markdown(para)
    }

    private static func trimTrailing(_ s: NSAttributedString) -> NSAttributedString {
        let str = s.string as NSString
        var len = str.length
        while len > 0 {
            let c = str.character(at: len - 1)
            if c == 0x0A || c == 0x0D { len -= 1 } else { break }
        }
        guard len != str.length else { return s }
        return s.attributedSubstring(from: NSRange(location: 0, length: len))
    }
}

// MARK: - 行内序列化

enum InlineSerializer {

    private enum Mark: Equatable {
        case link(String)
        case bold
        /// 关联值是斜体分隔符：粗体里嵌套斜体时用 `_`，避免出现 `***` 被误解析
        case italic(String)
        case underline
        case strike
        case code
        case color(String)
        case highlight(String)

        /// 嵌套顺序：外层 → 内层
        var order: Int {
            switch self {
            case .link: return 0
            case .bold: return 1
            case .italic: return 2
            case .underline: return 3
            case .strike: return 4
            case .code: return 5
            case .color: return 6
            case .highlight: return 7
            }
        }
    }

    // MARK: Markdown

    static func markdown(_ attr: NSAttributedString) -> String {
        // 逐字段落：语法非法但形似引用式链接定义的整行，原样写出，
        // 不做方括号防御性转义（否则 cmark-gfm / pandoc 语料里的行会被改写）。
        if attr.length > 0,
           attr.attribute(.mdVerbatimLine, at: 0, effectiveRange: nil) as? Bool == true {
            return attr.string
        }
        // 强调行：CommonMark 的定界符栈是树形嵌套，粗/斜两个 trait 无法还原。
        // 显示文字与解析快照一致 = 用户没编辑过，逐字输出原行；一致才走这里，
        // 一旦编辑就交给下面的 trait 重建，绝不拿旧源码盖掉输入（P1 的教训）。
        // 只在块级入口生效：链接 label / 删除线 body 是递归 parse 的子串，若也
        // 短路会把 `[**x**](url)` 截成 `**x**`。块级属性由 finalized 打上。
        if attr.length > 0,
           attr.attribute(.mdBlockType, at: 0, effectiveRange: nil) != nil,
           let source = attr.attribute(.mdEmphasisSource, at: 0, effectiveRange: nil) as? String,
           let display = attr.attribute(.mdEmphasisDisplay, at: 0, effectiveRange: nil) as? String,
           let traits = attr.attribute(.mdEmphasisTraits, at: 0, effectiveRange: nil) as? String,
           attr.string == display,
           MarkdownSerializer.emphasisFingerprint(attr) == traits {
            return source
        }
        var out = ""
        var active: [Mark] = []

        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            // 图片附件
            if let image = attrs[.attachment] as? MDImageAttachment {
                out += image.mdTitle.isEmpty
                    ? "![\(image.alt)](\(image.src))"
                    : "![\(image.alt)](\(image.src) \"\(image.mdTitle)\")"
                return
            }
            // 即刻模式里的内联嵌入卡片：一个 U+FFFC 就是整条 ![[...]]，
            // 按原语法逐字还原，绝不把卡片内容写进 Markdown 源码。
            if let embed = attrs[.attachment] as? MDEmbedAttachment {
                for mark in active.reversed() { out += closingMarkdown(mark) }
                active = []
                out += embed.link.raw
                return
            }

            // 任务复选框：显示文字就是源码，逐字输出即可；用户勾选成 [x] 时
            // 以当前文字为准，不能用解析时缓存的 [ ] 覆盖。
            if let box = attrs[.mdTaskBox] as? String {
                for mark in active.reversed() { out += closingMarkdown(mark) }
                active = []
                let shown = (attr.string as NSString).substring(with: range)
                out += ["[ ]", "[x]", "[X]"].contains(shown) ? shown : box
                return
            }

            // Obsidian 双链 / 嵌入：逐字输出原语法，绝不走 escapeMarkdown。
            // 用户若改过显示文字，就按新文字重建，避免旧源码盖掉编辑（P1 的教训）。
            if let wiki = attrs[.mdWikiLink] as? MDWikiLink {
                for mark in active.reversed() { out += closingMarkdown(mark) }
                active = []
                let shown = (attr.string as NSString).substring(with: range)
                out += shown == wiki.display ? wiki.raw : wiki.rebuilt(display: shown)
                return
            }

            let raw = (attr.string as NSString).substring(with: range)
            let isCode = (attrs[.mdInlineCode] as? Bool) ?? false
            // 代码 span 里反斜杠是字面量，不能按正文规则转义，否则 `[[code]]`
            // 会变成 `\[\[code\]\]`，每往返一次内容都不一致。
            let text = isCode
                ? raw.replacingOccurrences(of: "\u{2028}", with: "  \n")
                : escapeMarkdown(raw.replacingOccurrences(of: "\u{2028}", with: "  \n"))
            guard !text.isEmpty else { return }

            var marks: [Mark] = []
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []

            if isCode {
                marks.append(.code)
            } else {
                // 标题 / 表头的字重是排版自带的（.mdStructuralBold），不是用户敲的 **，不输出
                let hasBold = traits.contains(.bold) && (attrs[.mdStructuralBold] as? Bool) != true
                // 标题 / 表头的字重是排版自带的（.mdStructuralBold），不是用户敲的 **，不输出
                if hasBold { marks.append(.bold) }
                if traits.contains(.italic) { marks.append(.italic(hasBold ? "_" : "*")) }
                // 链接本身就带下划线，不再额外包一层 <u>
                if let u = attrs[.underlineStyle] as? Int, u != 0, linkString(from: attrs) == nil {
                    marks.append(.underline)
                }
                if let s = attrs[.strikethroughStyle] as? Int, s != 0 { marks.append(.strike) }
                if let color = attrs[.mdTextColor] as? NSColor { marks.append(.color(color.hexString)) }
                if let hl = attrs[.mdHighlight] as? NSColor { marks.append(.highlight(hl.hexString)) }
                if let url = linkString(from: attrs) { marks.append(.link(url)) }
            }

            // 关闭已失效的标记（由内到外）
            for mark in active.reversed() where !marks.contains(mark) {
                out += closingMarkdown(mark)
            }
            // 打开新增的标记（由外到内）
            let sortedMarks = marks.sorted(by: { $0.order < $1.order })
            for mark in sortedMarks where !active.contains(mark) {
                out += openingMarkdown(mark)
            }
            // active 必须与打开顺序一致：关闭时按 reversed() 由内到外输出。
            // 若存未排序的 marks，链接与强调并存时会先关链接再关强调，
            // 把 `**` 写到 `](url)` 后面，每次往返都搬一次家。
            active = sortedMarks

            out += text
        }

        for mark in active.reversed() { out += closingMarkdown(mark) }
        return out
    }

    // MARK: HTML

    static func html(_ attr: NSAttributedString) -> String {
        var out = ""
        var active: [Mark] = []

        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            if let image = attrs[.attachment] as? MDImageAttachment {
                var tag = "<img src=\"\(escapeHTML(image.src))\" alt=\"\(escapeHTML(image.alt))\""
                if !image.mdTitle.isEmpty {
                    tag += " title=\"\(escapeHTML(image.mdTitle))\""
                }
                out += tag + " />"
                return
            }
            // 内联嵌入卡片：HTML 导出按源码语法输出一个可点击的链接文字，
            // 不把卡片里的目标内容复制进当前文档。
            if let embed = attrs[.attachment] as? MDEmbedAttachment {
                out += escapeHTML(embed.link.raw)
                return
            }

            if attrs[.mdTaskBox] is String {
                for mark in active.reversed() { out += closingHTML(mark) }
                active = []
                let shown = (attr.string as NSString).substring(with: range)
                let checked = shown == "[x]" || shown == "[X]"
                out += "<input type=\"checkbox\" disabled\(checked ? " checked" : "") />"
                return
            }

            if let wiki = attrs[.mdWikiLink] as? MDWikiLink {
                for mark in active.reversed() { out += closingHTML(mark) }
                active = []
                let shown = (attr.string as NSString).substring(with: range)
                if wiki.embedded {
                    out += "<span class=\"internal-embed\" data-src=\"\(escapeHTML(wiki.target + wiki.suffix))\">"
                        + escapeHTML(shown) + "</span>"
                } else {
                    out += "<a class=\"internal-link\" href=\"\(escapeHTML(wiki.target + wiki.suffix))\">"
                        + escapeHTML(shown) + "</a>"
                }
                return
            }

            let raw = (attr.string as NSString).substring(with: range)
            let text = escapeHTML(raw).replacingOccurrences(of: "\u{2028}", with: "<br />")
            guard !text.isEmpty else { return }

            var marks: [Mark] = []
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isCode = (attrs[.mdInlineCode] as? Bool) ?? false

            if isCode {
                marks.append(.code)
            } else {
                // 标题 / 表头的字重是排版自带的（.mdStructuralBold），不是用户敲的 **，不输出
                let hasBold = traits.contains(.bold) && (attrs[.mdStructuralBold] as? Bool) != true
                // 标题 / 表头的字重是排版自带的（.mdStructuralBold），不是用户敲的 **，不输出
                if hasBold { marks.append(.bold) }
                if traits.contains(.italic) { marks.append(.italic(hasBold ? "_" : "*")) }
                // 链接本身就带下划线，不再额外包一层 <u>
                if let u = attrs[.underlineStyle] as? Int, u != 0, linkString(from: attrs) == nil {
                    marks.append(.underline)
                }
                if let s = attrs[.strikethroughStyle] as? Int, s != 0 { marks.append(.strike) }
                if let color = attrs[.mdTextColor] as? NSColor { marks.append(.color(color.hexString)) }
                if let hl = attrs[.mdHighlight] as? NSColor { marks.append(.highlight(hl.hexString)) }
                if let url = linkString(from: attrs) { marks.append(.link(url)) }
            }

            for mark in active.reversed() where !marks.contains(mark) { out += closingHTML(mark) }
            let sortedMarks = marks.sorted(by: { $0.order < $1.order })
            for mark in sortedMarks where !active.contains(mark) { out += openingHTML(mark) }
            active = sortedMarks

            out += text
        }

        for mark in active.reversed() { out += closingHTML(mark) }
        return out
    }

    // MARK: 工具

    private static func linkString(from attrs: [NSAttributedString.Key: Any]) -> String? {
        if let url = attrs[.link] as? URL { return url.absoluteString }
        if let url = attrs[.link] as? NSURL { return url.absoluteString }
        if let s = attrs[.link] as? String { return s }
        return nil
    }

    private static func openingMarkdown(_ mark: Mark) -> String {
        switch mark {
        case .link: return "["
        case .bold: return "**"
        case .italic(let delimiter): return delimiter
        case .underline: return "<u>"
        case .strike: return "~~"
        case .code: return "`"
        case .color(let hex): return "<span style=\"color:\(hex)\">"
        case .highlight(let hex): return "<span style=\"background-color:\(hex)\">"
        }
    }

    private static func closingMarkdown(_ mark: Mark) -> String {
        switch mark {
        case .link(let url): return "](\(url))"
        case .bold: return "**"
        case .italic(let delimiter): return delimiter
        case .underline: return "</u>"
        case .strike: return "~~"
        case .code: return "`"
        case .color: return "</span>"
        case .highlight: return "</span>"
        }
    }

    private static func openingHTML(_ mark: Mark) -> String {
        switch mark {
        case .link(let url): return "<a href=\"\(escapeHTML(url))\">"
        case .bold: return "<strong>"
        case .italic: return "<em>"
        case .underline: return "<u>"
        case .strike: return "<del>"
        case .code: return "<code>"
        case .color(let hex): return "<span style=\"color:\(hex)\">"
        case .highlight(let hex): return "<mark style=\"background-color:\(hex)\">"
        }
    }

    private static func closingHTML(_ mark: Mark) -> String {
        switch mark {
        case .link: return "</a>"
        case .bold: return "</strong>"
        case .italic: return "</em>"
        case .underline: return "</u>"
        case .strike: return "</del>"
        case .code: return "</code>"
        case .color: return "</span>"
        case .highlight: return "</mark>"
        }
    }

    /// Markdown 特殊字符转义
    private static func escapeMarkdown(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var p = 0
        while p < chars.count {
            // Obsidian Callout 标记 `[!NOTE]` 不是链接语法。Callout 内部行现在会真解析，
            // 用户编辑标题后按富文本重建时，若把 `[` `]` 转义成 `\[!NOTE\]`，
            // 下次打开就不认得这是 Callout 了，所以整段原样输出。
            if chars[p] == "[", p + 1 < chars.count, chars[p + 1] == "!",
               let close = (p + 2..<chars.count).first(where: { chars[$0] == "]" }) {
                out.append(contentsOf: chars[p...close])
                p = close + 1
                continue
            }
            let ch = chars[p]
            switch ch {
            case "\\", "`", "*", "_", "[", "]", "~", "<":
                out.append("\\")
                out.append(ch)
            default:
                out.append(ch)
            }
            p += 1
        }
        return out
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
