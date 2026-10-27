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
    case listItem(ordered: Bool, level: Int, content: NSAttributedString)
    case image(MDImageAttachment)
    case table(rows: [[NSAttributedString]], hasHeader: Bool)
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

        for block in blocks {
            var text = ""
            var isListItem = false
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

            case .listItem(let ordered, let level, let content):
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
                let indent = String(repeating: "  ", count: level)
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
            }

            // 连续的列表项之间不留空行（紧列表），其余块之间空一行
            if !pieces.isEmpty {
                let sameList = previousWasListItem && isListItem
                    && previousListOrdered == listOrdered
                    && previousListLevel == listLevel
                pieces.append(sameList ? "\n" : "\n\n")
            }
            pieces.append(text)
            previousWasListItem = isListItem
            previousListOrdered = listOrdered
            previousListLevel = listLevel
        }

        return pieces.joined() + "\n"
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
            if para.length == 0 { continue }

            let attrs = para.attributes(at: 0, effectiveRange: nil)

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
                continue
            }

            // 表格单元格
            if let style = attrs[.paragraphStyle] as? NSParagraphStyle,
               let tableBlock = style.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first {
                let row = tableBlock.startingRow
                let col = tableBlock.startingColumn
                while tableRows.count <= row { tableRows.append([]) }
                while tableRows[row].count <= col { tableRows[row].append(NSAttributedString(string: "")) }
                tableRows[row][col] = para
                if row == 0, (attrs[.mdTableHeader] as? Bool) == true { tableHeader = true }
                continue
            }
            flushTable()

            // 列表项
            if let item = attrs[.mdListItem] as? MDListItem {
                result.append(.listItem(ordered: item.ordered, level: item.level, content: para))
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

            let raw = (attr.string as NSString).substring(with: range)
            let text = escapeMarkdown(raw.replacingOccurrences(of: "\u{2028}", with: "  \n"))
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

            // 关闭已失效的标记（由内到外）
            for mark in active.reversed() where !marks.contains(mark) {
                out += closingMarkdown(mark)
            }
            // 打开新增的标记（由外到内）
            for mark in marks.sorted(by: { $0.order < $1.order }) where !active.contains(mark) {
                out += openingMarkdown(mark)
            }
            active = marks

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
            for mark in marks.sorted(by: { $0.order < $1.order }) where !active.contains(mark) { out += openingHTML(mark) }
            active = marks

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
        var out = ""
        for ch in s {
            switch ch {
            case "\\", "`", "*", "_", "[", "]", "~", "<":
                out.append("\\")
                out.append(ch)
            default:
                out.append(ch)
            }
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
