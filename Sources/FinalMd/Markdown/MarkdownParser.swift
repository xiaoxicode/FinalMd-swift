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
        let text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let out = NSMutableAttributedString()
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行：跳过（Markdown 里只作分隔用）
            if trimmed.isEmpty {
                i += 1
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

            // 引用
            if trimmed.hasPrefix(">") {
                var body: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[i].trimmingCharacters(in: .whitespaces)
                    l = String(l.dropFirst())
                    if l.hasPrefix(" ") { l = String(l.dropFirst()) }
                    body.append(l)
                    i += 1
                }
                out.append(quoteBlock(body.joined(separator: "\n")))
                continue
            }

            // 列表
            if listItemInfo(line) != nil {
                var items: [(String, String, Int)] = []  // (marker, content, level)
                var counter = 0
                while i < lines.count {
                    let l = lines[i]
                    if let info = listItemInfo(l) {
                        counter = info.ordered ? counter + 1 : 0
                        let n = info.ordered ? counter : 0
                        items.append((info.ordered ? "\(n)." : "-", info.content, info.level))
                        i += 1
                    } else if !l.trimmingCharacters(in: .whitespaces).isEmpty,
                              l.hasPrefix(" ") || l.hasPrefix("\t"),
                              !items.isEmpty {
                        // 续行：接到上一个列表项后面
                        let cont = l.trimmingCharacters(in: .whitespaces)
                        items[items.count - 1].1 += "\n" + cont
                        i += 1
                    } else {
                        break
                    }
                }
                out.append(listBlock(items))
                continue
            }

            // 普通段落：一直吃到空行或下一个块级开始
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if t.hasPrefix("```") || t.hasPrefix("~~~") || t.hasPrefix("|") || t.hasPrefix(">")
                    || isHorizontalRule(t) || heading(from: t) != nil || listItemInfo(l) != nil {
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
            if !numPart.isEmpty, numPart.allSatisfy(\.isNumber),
               dot < rest.endIndex, rest[rest.index(after: dot)] == " " {
                ordered = true
                markerLength = numPart.count + 2
            }
        } else if let paren = rest.firstIndex(of: ")"), rest.startIndex < paren {
            let numPart = String(rest[rest.startIndex..<paren])
            if !numPart.isEmpty, numPart.allSatisfy(\.isNumber),
               paren < rest.endIndex, rest[rest.index(after: paren)] == " " {
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
        return ListInfo(ordered: ordered, level: level, content: content)
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

    private static func listBlock(_ items: [(String, String, Int)]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (marker, content, level) in items {
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

            let item = NSMutableAttributedString()
            item.append(bullet)
            item.append(attributed)

            let range = NSRange(location: 0, length: item.length)
            item.addAttribute(.mdListItem, value: MDListItem(ordered: ordered, level: level), range: range)
            item.addAttribute(.mdBlockType, value: MDBlockType.paragraph.rawValue, range: range)
            item.append(NSAttributedString(string: "\n", attributes: attrs))
            out.append(item)
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
                    block.backgroundColor = NSColor(calibratedRed: 0.961, green: 0.965, blue: 0.976, alpha: 1)
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
                    block.backgroundColor = NSColor(calibratedRed: 0.961, green: 0.965, blue: 0.976, alpha: 1)
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
