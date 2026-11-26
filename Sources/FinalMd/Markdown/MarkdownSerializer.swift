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

    // MARK: 写回策略（用户偏好）

    /// Callout「只改格式不改文字」时是否按富文本重建该行。
    /// true（默认）：⌘B / ⌘I / 改色等格式改动生效，按当前富文本重建；
    /// false：逐字保真优先，文字没变就写回原行（旧取舍，格式改动被丢弃）。
    /// 只影响 Callout 行；文字或指纹都没被改过时，两种模式都逐字写回原行。
    /// 由 AppModel 的 UserDefaults 偏好同步；测试可直接改写。
    static var calloutFormatEdits = true

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
                // 尾部裸 `#` 串必须转义：`### foo ###` 写出去下一轮会把尾部 ###
                // 当闭合串剥掉，out1 != out2 失去一次稳定（CommonMark §4.2）。
                text = String(repeating: "#", count: level) + " "
                    + Self.escapeTrailingHeadingHashes(InlineSerializer.markdown(content))
                orderedCounters.removeAll()
                lastLevel = -1

            case .paragraph(let content):
                text = InlineSerializer.markdown(content)
                orderedCounters.removeAll()
                lastLevel = -1

            case .quote(let content):
                // 未编辑的引用逐字写回原始行（含 `>` 标记与懒续行缩进）：
                // 重建路径会把 `>>` 变 `> >`、把懒续行 `    no code` 变 `> no code`，
                // 破坏一次稳定与透传特征（kramdown 004 实测）。
                if content.length > 0,
                   let raw = content.attribute(.mdQuoteRaw, at: 0, effectiveRange: nil) as? String,
                   let display = content.attribute(.mdEmphasisDisplay, at: 0, effectiveRange: nil) as? String,
                   content.string == display {
                    text = raw
                } else if content.length > 0,
                          let sources = content.attribute(.mdQuoteLineSources, at: 0, effectiveRange: nil) as? [String],
                          let displays = content.attribute(.mdQuoteLineDisplays, at: 0, effectiveRange: nil) as? [String],
                          let traits = content.attribute(.mdQuoteLineTraits, at: 0, effectiveRange: nil) as? [String],
                          let map = content.attribute(.mdQuoteLineMap, at: 0, effectiveRange: nil) as? [[Int]],
                          !map.isEmpty, map.count == displays.count, displays.count == traits.count {
                    // 组对齐：显示行 ↔ 连续原始行**组**（内层围栏被行内 code span
                    // 吞并成单显示行时逐行 1:1 对不齐）。未编辑的组整组源行逐字保留；
                    // 编辑的组只重建内容行，围栏 / `>>` / 懒续行等结构行仍逐字保留。
                    let ns = content.string as NSString
                    var ranges: [NSRange] = []
                    var start = 0
                    for i in 0..<ns.length {
                        if ns.character(at: i) == 0x2028 {
                            ranges.append(NSRange(location: start, length: i - start))
                            start = i + 1
                        }
                    }
                    ranges.append(NSRange(location: start, length: ns.length - start))
                    var parts: [String] = []
                    var aligned = ranges.count == displays.count
                    if aligned {
                        for entry in map {
                            guard entry.count == 4 else { aligned = false; break }
                            let d = entry[0], rs = entry[1], re = entry[2], ci = entry[3]
                            guard d >= 0, d < ranges.count,
                                  rs >= 0, rs <= re, re < sources.count else { aligned = false; break }
                            let lineAttr = content.attributedSubstring(from: ranges[d])
                            if lineAttr.string == displays[d],
                               Self.emphasisFingerprint(lineAttr) == traits[d] {
                                // 整组未编辑：源行组逐字保留（含围栏 / `>>` / 懒续行缩进）
                                parts.append(sources[rs...re].joined(separator: "\n"))
                            } else if ci >= rs, ci <= re {
                                // 只重建唯一内容行，组内结构行逐字保留。
                                // 合并组的内容行处于字面上下文（内层围栏内容），必须按
                                // 显示文字直写——走行内重建会补出 ` 反被 code span 吞掉。
                                var group: [String] = []
                                for i in rs...re {
                                    if i == ci {
                                        let body = (rs == re)
                                            ? InlineSerializer.rebuildEditedLine(lineAttr)
                                            : lineAttr.string
                                        group.append(Self.quoteLinePrefix(sources[i]) + body)
                                    } else {
                                        group.append(sources[i])
                                    }
                                }
                                parts.append(group.joined(separator: "\n"))
                            } else {
                                // 找不到唯一内容行（多行合并成单显示行）：整组塌缩成
                                // 一行重建，显示语义不变（源码结构降级但不丢内容）。
                                parts.append(Self.quoteLinePrefix(sources[rs])
                                    + InlineSerializer.rebuildEditedLine(lineAttr))
                            }
                        }
                    }
                    if aligned {
                        text = parts.joined(separator: "\n")
                    } else {
                        let md = InlineSerializer.markdown(content)
                        text = md.split(separator: "\n", omittingEmptySubsequences: false)
                            .map { "> " + $0 }.joined(separator: "\n")
                    }
                } else if content.length > 0,
                          let sources = content.attribute(.mdQuoteLineSources, at: 0, effectiveRange: nil) as? [String],
                          let displays = content.attribute(.mdQuoteLineDisplays, at: 0, effectiveRange: nil) as? [String],
                          let traits = content.attribute(.mdQuoteLineTraits, at: 0, effectiveRange: nil) as? [String],
                          sources.count == displays.count, displays.count == traits.count {
                    // 逐行快照：只重建被编辑的行，围栏 / `>>` / 懒续行缩进等
                    // 兄弟行逐字保留（编辑引用的一行不再毁掉内层块结构）。
                    let ns = content.string as NSString
                    var ranges: [NSRange] = []
                    var start = 0
                    for i in 0..<ns.length {
                        if ns.character(at: i) == 0x2028 {
                            ranges.append(NSRange(location: start, length: i - start))
                            start = i + 1
                        }
                    }
                    ranges.append(NSRange(location: start, length: ns.length - start))
                    guard ranges.count == displays.count else {
                        let md = InlineSerializer.markdown(content)
                        text = md.split(separator: "\n", omittingEmptySubsequences: false)
                            .map { "> " + $0 }.joined(separator: "\n")
                        break
                    }
                    var parts: [String] = []
                    for (idx, r) in ranges.enumerated() {
                        let lineAttr = content.attributedSubstring(from: r)
                        if lineAttr.string == displays[idx],
                           Self.emphasisFingerprint(lineAttr) == traits[idx] {
                            parts.append(sources[idx])
                        } else {
                            // 保留原行的 `>` 标记 / 懒续行缩进，只重建正文
                            parts.append(Self.quoteLinePrefix(sources[idx])
                                + InlineSerializer.rebuildEditedLine(lineAttr))
                        }
                    }
                    text = parts.joined(separator: "\n")
                } else {
                    let md = InlineSerializer.markdown(content)
                    text = md.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "> " + $0 }.joined(separator: "\n")
                }
                orderedCounters.removeAll()
                lastLevel = -1

            case .code(let code, let language):
                // info 含反引号时必须改用波浪号围栏：反引号围栏的 info 串不允许
                // 含反引号（CommonMark），用反引号写出去下一轮就不认这个围栏了。
                // 围栏长度必须大于内容里最长的同类围栏字符连续段：
                // 内容含 ``` 时用三反引号封口会把块提前截断，下一轮就换一种拆法。
                let fenceChar: Character = language.contains("`") ? "~" : "`"
                var fence = String(repeating: fenceChar, count: 3)
                let maxRun = code.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { line -> Int in
                        var best = 0, cur = 0
                        for ch in line {
                            if ch == fenceChar { cur += 1; best = max(best, cur) } else { cur = 0 }
                        }
                        return best
                    }
                    .max() ?? 0
                if maxRun >= 3 { fence = String(repeating: fenceChar, count: maxRun + 1) }
                // 内容自带行尾换行（CommonMark 语义）时不再补换行，否则多空一行
                let codeBody = code.isEmpty ? "" : (code.hasSuffix("\n") ? code : code + "\n")
                text = "\(fence)\(language)\n\(codeBody)\(fence)"
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
                // 列表项文本里带着成文用的符号（"- " / "8. " / "* "），输出前剥掉
                var body = content
                var markerToken = ""
                let s = body.string
                if let sp = s.firstIndex(of: " ") {
                    let drop = s.distance(from: s.startIndex, to: sp) + 1
                    markerToken = String(s[s.startIndex..<sp])
                    if drop < body.length {
                        body = body.attributedSubstring(from: NSRange(location: drop, length: body.length - drop))
                    } else {
                        body = NSAttributedString()
                    }
                }
                // 解析时记下的原始缩进优先：4 空格嵌套列表不能被压成 2 空格/级，
                // 否则下一轮会丢失 zettlr / Logseq 语料里的容器块缩进。
                let indent = originalIndent.map { String(repeating: " ", count: $0) }
                    ?? String(repeating: "  ", count: level)
                // 标记逐字写回（"8." 不重排成 "1."、"*" 不统一成 "-"）。
                // 编辑器回车续行（nextListMarker）已按序递增写进文本，
                // 这里再重排只会把外部文件的起始序号改坏。
                let marker: String
                if !markerToken.isEmpty {
                    marker = markerToken
                } else if ordered {
                    if level != lastLevel { orderedCounters[level] = 0 }
                    let n = (orderedCounters[level] ?? 0) + 1
                    orderedCounters[level] = n
                    marker = "\(n)."
                } else {
                    marker = "-"
                }
                text = "\(indent)\(marker) " + InlineSerializer.markdown(body)
                lastLevel = level

            case .image(let att):
                text = "![\(att.alt)](\(InlineSerializer.linkTarget(att.src, title: att.mdTitle)))"
                orderedCounters.removeAll()
                lastLevel = -1

            case .table(let rows, let hasHeader):
                var lines: [String] = []
                for (r, row) in rows.enumerated() {
                    // 单元格是单行：段内换行（<br> 进来的硬换行）必须写成 <br>，
                    // 直接写换行会把表格行撕成多行、下一轮重解析成不同结构
                    // （marp 002 / obsidian 007 实测）。"  \n" 是硬换行原文，
                    // "\\\n" 是空内容硬换行经 fixEmptyHardBreaks 的输出。
                    let cells = row.map {
                        InlineSerializer.markdown($0)
                            .replacingOccurrences(of: "  \n", with: "<br>")
                            .replacingOccurrences(of: "\\\n", with: "<br>")
                            .replacingOccurrences(of: "|", with: "\\|")
                    }
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

    /// 标题内容尾部的裸 `#` 串下一轮会被当 ATX 闭合串剥掉（CommonMark §4.2），
    /// 给串首 `#` 加转义打断；前缀反斜杠奇数个说明已转义，不动。
    /// 例：显示 `foo ###` → 写出 `foo \###`，重解析回 `foo ###`，一次稳定。
    private static func escapeTrailingHeadingHashes(_ s: String) -> String {
        guard s.last == "#" else { return s }
        var runStart = s.endIndex
        while runStart > s.startIndex, s[s.index(before: runStart)] == "#" {
            runStart = s.index(before: runStart)
        }
        // 反斜杠奇偶：序列化已把字面反斜杠翻倍，奇数个只剩「# 已被转义」一种来源
        var bs = 0
        var k = runStart
        while k > s.startIndex, s[s.index(before: k)] == "\\" {
            bs += 1
            k = s.index(before: k)
        }
        if bs % 2 == 1 { return s }
        if runStart != s.startIndex {
            let prev = s[s.index(before: runStart)]
            guard prev == " " || prev == "\t" else { return s }
        }
        return s[..<runStart] + "\\" + s[runStart...]
    }

    /// 与 MarkdownParser 的 emphasisFingerprint 同口径：B=粗、I=斜、X=粗斜、-=无。
    /// 用来判断强调行是否「只改了格式没改文字」——这种情况快照必须失效，
    /// 否则用户按 ⌘B / ⌘I 的改动会被旧源码盖掉。
    static func emphasisFingerprint(_ attr: NSAttributedString) -> String {
        mdFormattingFingerprint(attr, length: attr.length)
    }

    /// 引用原始行的标记前缀。与解析侧 body 剥离**同口径**：行首空白 +
    /// 一个 `>` + 紧随的一个空格（`>> code` 的 body 是 `> code`，第二个 `>`
    /// 留在正文里）。编辑行重建时保留前缀只换正文，避免 `>>` 被压成 `> `、
    /// 懒续行缩进被顶掉（kramdown 004 的透传特征）。
    static func quoteLinePrefix(_ raw: String) -> String {
        var idx = raw.startIndex
        while idx < raw.endIndex, raw[idx] == " " || raw[idx] == "\t" {
            idx = raw.index(after: idx)
        }
        if idx < raw.endIndex, raw[idx] == ">" {
            idx = raw.index(after: idx)
            if idx < raw.endIndex, raw[idx] == " " {
                idx = raw.index(after: idx)
            }
        }
        return String(raw[raw.startIndex..<idx])
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
        var currentTable: NSTextTable?

        func flushTable() {
            guard !tableRows.isEmpty else { return }
            result.append(.table(rows: tableRows, hasHeader: tableHeader))
            tableRows = []
            tableHeader = false
            currentTable = nil
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

            // 空内容块不一概丢弃：空行（无块类型或普通段落）跳过，
            // 但 CommonMark 的空标题（`#`）、空引用（`>`）、空列表项（`-`）
            // 都是合法块，必须照常输出。
            if para.length == 0, !isTableCellParagraph(attrs), attrs[.mdListItem] == nil {
                let bt = attrs[.mdBlockType] as? String
                if bt == nil || bt == MDBlockType.paragraph.rawValue { continue }
            }

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

            if para.length == 0, !isTableCellParagraph(attrs), attrs[.mdListItem] == nil {
                let bt = attrs[.mdBlockType] as? String
                if bt == nil || bt == MDBlockType.paragraph.rawValue {
                    flushTable()
                    continue
                }
            }

            // 附件（图片 / 分割线）
            // 带链接的图片（[![alt](img)](url)）走段落通道交给 InlineSerializer：
            // .image 通道只输出裸图片，外层链接会丢。
            // 表格单元格里的附件也是行内内容（`| ![a](i) |`），不能抽成独立块
            // 把表格拦腰截断。
            // 只有「整段恰好就是这一个附件」才能抽成独立块。段落以图片开头但后面
            // 还有同行文字 / 续行行内 HTML（Joplin 的 `![](url)` + `<img …/>`）时，
            // 旧写法在这里 continue 把整段剩余内容吞掉，保存后图片属性整行消失。
            let paragraphIsOnlyAttachment = para.string.count == 1
            if let attachment = attrs[.attachment], attrs[.link] == nil,
               paragraphIsOnlyAttachment, !isTableCellParagraph(attrs) {
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
                // 相邻两张表会各自建一个 NSTextTable，但行号都从 0 开始。
                // 不按表实例切换就 flush，旧行还在累积器里，新 cell 会被
                // `count == col` 的判重逻辑整张丢掉（stackedit 002 实测）。
                let table = tableBlock.table
                if table !== currentTable {
                    flushTable()
                    currentTable = table
                }
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
                // 代码块可能跨多个「段」（内容里的 \n 会切段），吃到块尾的
                // mdCodeEnd 终结换行为止。没有这个标记，"~~~\n~~~\n~~~"
                // 两个相邻空代码块会被并成一块。
                var text = para.string
                var ended = attr.attribute(.mdCodeEnd, at: NSMaxRange(range) - 1,
                                           effectiveRange: nil) != nil
                while !ended, loc < ns.length {
                    let next = ns.paragraphRange(for: NSRange(location: loc, length: 0))
                    if next.length == 0 { break }
                    let nextAttrs = attr.attributes(at: next.location, effectiveRange: nil)
                    guard (nextAttrs[.mdBlockType] as? String) == MDBlockType.code.rawValue else { break }
                    ended = attr.attribute(.mdCodeEnd, at: NSMaxRange(next) - 1,
                                           effectiveRange: nil) != nil
                    text += "\n" + trimTrailing(attr.attributedSubstring(from: next)).string
                    loc = NSMaxRange(next)
                }
                if (attrs[.mdCodeEmpty] as? Bool) == true { text = "" }
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
    /// 显示文字与解析快照一致 → 说明用户没改文字，此时看格式指纹：
    /// 指纹也没动 → 直接输出原行；只改了格式（⌘B / ⌘I / 改色）→ 按开关决定
    /// 是否按当前富文本重建（默认生效，关闭则回到「逐字保真优先」的旧取舍）。
    /// 显示文字不一致 → 用户改过内容，按当前富文本重建，不让旧源码盖掉编辑。
    private static func calloutLine(from para: NSAttributedString,
                                    attrs: [NSAttributedString.Key: Any]) -> String {
        let shown = para.string
        if let source = attrs[.mdCalloutSource] as? String,
           let display = attrs[.mdCalloutDisplay] as? String,
           shown == display {
            guard calloutFormatEdits else { return source }
            guard let traits = attrs[.mdCalloutTraits] as? String else { return source }
            return mdFormattingFingerprint(para, length: para.length) == traits
                ? source
                : InlineSerializer.markdown(para)
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
        /// 关联值是 (url, title)；title 为空时输出 `[text](url)`，否则带引号写回
        case link(String, String)
        case bold
        /// 关联值是斜体分隔符：粗体里嵌套斜体时用 `_`，避免出现 `***` 被误解析
        case italic(String)
        case underline
        case strike
        /// 关联值是代码围栏（内容含反引号时用更长围栏，必要时带定界空格）
        case code(fence: String, pad: Bool)
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
        // 逐行快照：整块被编辑过时按**行粒度**判定——文本与指纹都未变的行
        // 逐字写回，只有被改的行才按富文本重建。编辑一行不再改写兄弟行的写法
        // （如多行段落里只改一行，另一行的强调 / 转义 / 引用式链接原样保留）。
        if attr.length > 0,
           attr.attribute(.mdBlockType, at: 0, effectiveRange: nil) != nil,
           let sources = attr.attribute(.mdLineSources, at: 0, effectiveRange: nil) as? [String],
           let displays = attr.attribute(.mdLineDisplays, at: 0, effectiveRange: nil) as? [String],
           let traits = attr.attribute(.mdLineTraits, at: 0, effectiveRange: nil) as? [String],
           sources.count == displays.count, displays.count == traits.count {
            let ns = attr.string as NSString
            var ranges: [NSRange] = []
            var start = 0
            for i in 0..<ns.length {
                if ns.character(at: i) == 0x2028 {
                    ranges.append(NSRange(location: start, length: i - start))
                    start = i + 1
                }
            }
            ranges.append(NSRange(location: start, length: ns.length - start))
            if ranges.count == displays.count {
                var parts: [String] = []
                for (idx, r) in ranges.enumerated() {
                    let lineAttr = attr.attributedSubstring(from: r)
                    if lineAttr.string == displays[idx],
                       MarkdownSerializer.emphasisFingerprint(lineAttr) == traits[idx] {
                        parts.append(sources[idx])
                    } else {
                        parts.append(Self.rebuildEditedLine(lineAttr))
                    }
                }
                return parts.joined(separator: "\n")
            }
        }
        var out = ""
        var active: [Mark] = []

        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            // 行内 HTML 原样片段（<img>、<code>…</code>、<a><img></a>…）：
            // 显示文字就是源码，逐字写回，不经 escapeMarkdown。
            if let raw = attrs[.mdInlineHTML] as? String {
                for mark in active.reversed() { out += closingMarkdown(mark) }
                active = []
                out += raw
                return
            }
            // 图片附件
            if let image = attrs[.attachment] as? MDImageAttachment {
                // 目标含空格等情形要写 <...> 包裹（linkTarget 统一处理），
                // 否则 `![](<img with space.png>)` 往返一次目标就散架。
                let img = "![\(image.alt)](\(InlineSerializer.linkTarget(image.src, title: image.mdTitle)))"
                // [![alt](img)](url)：链接包着图片时输出完整的嵌套写法
                if let url = linkString(from: attrs) {
                    let t = attrs[.mdLinkTitle] as? String ?? ""
                    out += "[" + img + "](" + InlineSerializer.linkTarget(url, title: t) + ")"
                } else {
                    out += img
                }
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
            // 空标签链接 `[](url)`：ZWSP 哨兵占位，写回剥掉还原成 `[](...)`。
            let isSentinelLink = raw == "\u{200B}" && linkString(from: attrs) != nil
            // 段尾硬换行（raw 尾部 "  \u{2028}" 且本 run 一直到内容末尾）按 <br>
            // 写回：段尾 "  \n" 会和块间换行并成三连换行、下一轮再合并成两连
            // （codimd 004 / prettier 002 实测），"\\\n" 又会和段落分隔互相振荡；
            // <br> 形式重解析回同一个段尾硬换行，逐字稳定。
            var rawSub = raw
            var trailingBreak = false
            if !isCode, !isSentinelLink, range.location + range.length == attr.length,
               rawSub.hasSuffix("  \u{2028}") {
                // 只有换行段恰好是**单个**硬换行时才按段尾 <br> 写回；
                // [s,h] / [h,h] 这类连续换行段必须整体交给 breakAwareMarkdown，
                // 否则两种规则各写一种形态，往返振荡。
                let before = String(rawSub.dropLast(3))
                if before.isEmpty || !before.hasSuffix("\u{2028}") {
                    rawSub = before
                    trailingBreak = true
                }
            }
            // U+2028 是段内换行：软换行还原成 "\n"；硬换行的两空格前缀
            // 已经在文字里，拼上 "\n" 天然构成 "  \n"。
            // 连续换行段按段写回（`x<br>\ny` 的硬+软写 "<br>\n"），不能写
            // "  \n\n"——空行会把段落误拆成两段（B24 的原始问题）。
            // 代码 span 里反斜杠是字面量，不能按正文规则转义，否则 `[[code]]`
            // 会变成 `\[\[code\]\]`，每往返一次内容都不一致。
            var text = isSentinelLink
                ? ""
                : isCode
                ? raw.replacingOccurrences(of: "\u{2028}", with: "\n")
                : Self.breakAwareMarkdown(rawSub,
                                          atLineStart: out.isEmpty || out.hasSuffix("\n"),
                                          atEnd: range.location + range.length == attr.length)
            // 空内容硬换行（"  " 独占一行）写成 "  \n" 会被下一轮解析成空行、
            // 整行丢失（cmark-gfm 019 / prettier 004 实测），必须写反斜杠硬换行。
            if !isCode, !isSentinelLink, text.contains("\n") {
                text = Self.fixEmptyHardBreaks(text)
            }
            if trailingBreak { text += "<br>" }
            guard !text.isEmpty || isSentinelLink else { return }

            // 自动链接 <https://x> / <a@b.c>：显示文字就是地址，按 <url> 原样写回，
            // 不走 [text](url) 重建，保住 GFM / CommonMark 的 autolink 写法。
            // 只有合法 autolink（CommonMark §6.9：带 URI 方案 / 邮箱）才能写 <...>；
            // `[CONTRIBUTING.md](CONTRIBUTING.md)` 这类无方案目标写成 <...> 会被
            // 下一轮当字面文本，链接直接丢失、`<` 转义还会来回振荡。
            if !isCode, let url = linkString(from: attrs) {
                let display = url.hasPrefix("mailto:") ? String(url.dropFirst(7)) : url
                if raw == display, isAutolinkDisplay(display) {
                    // run 上还有其他标记（删除线 / 粗斜 / 颜色 / 高亮）时必须把
                    // 它们包在 <...> 外面——直接短路会把 `~~hello@email.com~~`
                    // 的删除线吞成裸 <hello@email.com>（marked 003）。链接与
                    // 下划线不在此列：autolink 本身就是链接形态。
                    // 标记开闭与 active 记账跟正常路径同构，相邻 run 共享的
                    // 删除线不会被拆成 `~~<a>~~~~ b~~` 两段。
                    var extra: [Mark] = []
                    if let f = attrs[.font] as? NSFont {
                        let t = f.fontDescriptor.symbolicTraits
                        let bold = t.contains(.bold) && (attrs[.mdStructuralBold] as? Bool) != true
                        if bold { extra.append(.bold) }
                        if t.contains(.italic) { extra.append(.italic(bold ? "_" : "*")) }
                    }
                    if let s = attrs[.strikethroughStyle] as? Int, s != 0 { extra.append(.strike) }
                    if let color = attrs[.mdTextColor] as? NSColor { extra.append(.color(color.hexString)) }
                    if let hl = attrs[.mdHighlight] as? NSColor { extra.append(.highlight(hl.hexString)) }
                    let sorted = extra.sorted(by: { $0.order < $1.order })
                    for mark in active.reversed() where !sorted.contains(mark) {
                        out += closingMarkdown(mark)
                    }
                    for mark in sorted where !active.contains(mark) {
                        out += openingMarkdown(mark)
                    }
                    active = sorted
                    out += "<" + display + ">"
                    return
                }
            }

            var marks: [Mark] = []
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []

            // 标题 / 表头的字重是排版自带的（.mdStructuralBold），不是用户敲的 **，不输出
            let hasBold = traits.contains(.bold) && (attrs[.mdStructuralBold] as? Bool) != true
            if hasBold { marks.append(.bold) }
            if traits.contains(.italic) { marks.append(.italic(hasBold ? "_" : "*")) }
            // 链接本身就带下划线，不再额外包一层 <u>
            if let u = attrs[.underlineStyle] as? Int, u != 0, linkString(from: attrs) == nil {
                marks.append(.underline)
            }
            if let s = attrs[.strikethroughStyle] as? Int, s != 0 { marks.append(.strike) }
            if let color = attrs[.mdTextColor] as? NSColor { marks.append(.color(color.hexString)) }
            if let hl = attrs[.mdHighlight] as? NSColor { marks.append(.highlight(hl.hexString)) }
            if let url = linkString(from: attrs) {
                marks.append(.link(url, attrs[.mdLinkTitle] as? String ?? ""))
            }
            if isCode {
                // 代码 span 不排斥外层标记：`[**x**](url)` 里的代码 / 强调 / 链接
                // 要嵌套输出，拆开写会把链接或强调范围撕断。
                // 内容以反引号开头 / 结尾时在围栏**内侧**补定界空格（CommonMark 会剥掉
                // 一层）；内容两端都有空格时同样补一层（解析剥一对、写回补一对才收敛）。
                // 只有单边空格不补——CommonMark 只在两端同时有空格时才剥。
                marks.append(.code(fence: Self.codeFence(for: text),
                                   pad: text.hasPrefix("`") || text.hasSuffix("`")
                                        || (text.hasPrefix(" ") && text.hasSuffix(" ")
                                            && !text.allSatisfy { $0 == " " })))
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
            // 行内 HTML 原样片段本身就是 HTML，直接进导出结果
            if let raw = attrs[.mdInlineHTML] as? String {
                for mark in active.reversed() { out += closingHTML(mark) }
                active = []
                out += raw
                return
            }
            if let image = attrs[.attachment] as? MDImageAttachment {
                var tag = "<img src=\"\(escapeHTML(image.src))\" alt=\"\(escapeHTML(image.altPlainText))\""
                if !image.mdTitle.isEmpty {
                    tag += " title=\"\(escapeHTML(image.mdTitle))\""
                }
                tag += " />"
                // [![alt](img)](url)：链接包着图片时输出 <a><img></a>
                if let url = linkString(from: attrs) {
                    let t = attrs[.mdLinkTitle] as? String ?? ""
                    let titleAttr = t.isEmpty ? "" : " title=\"\(escapeHTML(t))\""
                    out += "<a href=\"\(escapeHTML(url))\"\(titleAttr)>" + tag + "</a>"
                } else {
                    out += tag
                }
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
            // 空标签链接 `[](url)`：ZWSP 哨兵剥掉，输出空锚点 `<a href></a>`。
            let isSentinelLink = raw == "\u{200B}" && linkString(from: attrs) != nil
            let text = isSentinelLink
                ? ""
                : escapeHTML(raw).replacingOccurrences(of: "\u{2028}", with: "<br />")
            guard !text.isEmpty || isSentinelLink else { return }

            var marks: [Mark] = []
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isCode = (attrs[.mdInlineCode] as? Bool) ?? false

            // 标题 / 表头的字重是排版自带的（.mdStructuralBold），不是用户敲的 **，不输出
            let hasBold = traits.contains(.bold) && (attrs[.mdStructuralBold] as? Bool) != true
            if hasBold { marks.append(.bold) }
            if traits.contains(.italic) { marks.append(.italic(hasBold ? "_" : "*")) }
            // 链接本身就带下划线，不再额外包一层 <u>
            if let u = attrs[.underlineStyle] as? Int, u != 0, linkString(from: attrs) == nil {
                marks.append(.underline)
            }
            if let s = attrs[.strikethroughStyle] as? Int, s != 0 { marks.append(.strike) }
            if let color = attrs[.mdTextColor] as? NSColor { marks.append(.color(color.hexString)) }
            if let hl = attrs[.mdHighlight] as? NSColor { marks.append(.highlight(hl.hexString)) }
            if let url = linkString(from: attrs) {
                marks.append(.link(url, attrs[.mdLinkTitle] as? String ?? ""))
            }
            // 代码 span 不排斥外层标记：链接 / 强调里的代码要嵌套输出
            if isCode {
                marks.append(.code(fence: "`", pad: false))   // HTML 走 <code>，fence 不参与
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
        case .code(let fence, let pad): return fence + (pad ? " " : "")
        case .color(let hex): return "<span style=\"color:\(hex)\">"
        case .highlight(let hex): return "<span style=\"background-color:\(hex)\">"
        }
    }

    private static func closingMarkdown(_ mark: Mark) -> String {
        switch mark {
        case .link(let url, let title): return "](" + linkTarget(url, title: title) + ")"
        case .bold: return "**"
        case .italic(let delimiter): return delimiter
        case .underline: return "</u>"
        case .strike: return "~~"
        case .code(let fence, let pad): return (pad ? " " : "") + fence
        case .color: return "</span>"
        case .highlight: return "</span>"
        }
    }

    /// 链接 / 图片目标：destination 含空白、以 `<` 开头、含裸 `<`/`>` 或括号
    /// 不配平时用 `<...>` 包住，包内 `<` `>` `\` 用反斜杠转义（CommonMark 允许），
    /// 否则每往返一轮就多包一层尖括号、永不收敛。
    /// title 非空时带引号写回（含双引号则改用单引号）。
    static func linkTarget(_ url: String, title: String) -> String {
        let needsAngle = url.isEmpty
            || url.contains(" ") || url.contains("\t") || url.contains("\n")
            || url.hasPrefix("<")
            || url.contains("<") || url.contains(">")
            || url.contains("\\")
            || !parensBalanced(url)
        let dest: String
        if needsAngle {
            let inner = url
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "<", with: "\\<")
                .replacingOccurrences(of: ">", with: "\\>")
            dest = "<\(inner)>"
        } else {
            // 裸目标里配平括号本就合法（深度计数按嵌套读回），只需转义反斜杠，
            // 否则 url 里的 `\*` 会被下一轮当成转义对还原成 `*`。
            dest = url.replacingOccurrences(of: "\\", with: "\\\\")
        }
        guard !title.isEmpty else { return dest }
        if title.contains("\"") && !title.contains("'") {
            return dest + " '\(title)'"
        }
        if title.contains("\"") { return dest }   // 两种引号都有：title 写不回去，宁可丢 title 不写坏语法
        return dest + " \"\(title)\""
    }

    /// 括号是否配平（转义括号不计）：不配平的裸目标会让下一轮按嵌套解析走样。
    private static func parensBalanced(_ s: String) -> Bool {
        var depth = 0
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\\" {
                let nxt = s.index(after: i)
                if nxt < s.endIndex {
                    i = s.index(after: nxt)
                    continue
                }
            }
            if ch == "(" { depth += 1 }
            if ch == ")" {
                depth -= 1
                if depth < 0 { return false }
            }
            i = s.index(after: i)
        }
        return depth == 0
    }

    /// `<...>` 是否是合法 autolink（CommonMark §6.9）：`<scheme:...>` 带
    /// 2–32 字符 URI 方案，或 `<mailbox>` 邮箱形式。无方案的路径 / 文件名
    /// （如 `CONTRIBUTING.md`、`/scripts`）写成 `<...>` 只是字面文本，
    /// 重解析时链接会丢失，所以只有合法形式才允许按 autolink 写回。
    static func isAutolinkDisplay(_ s: String) -> Bool {
        guard !s.isEmpty, !s.contains(" "), !s.contains("<"), !s.contains(">") else {
            return false
        }
        if s.contains("@") {
            return s.range(
                of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"#,
                options: .regularExpression) != nil
        }
        guard let colon = s.firstIndex(of: ":"), colon != s.startIndex else { return false }
        let scheme = s[s.startIndex..<colon]
        guard (2...32).contains(scheme.count),
              let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-")
        }
    }

    /// 段内换行段感知的正文输出：`"  \u{2028}"`（硬换行）与 `"\u{2028}"`（软换行）
    /// 按**连续段**写回——单个照旧 `"  \n"` / `"\n"`；连续段写 `<br>` 形态
    /// （如硬+软写 `<br>\n`，逐字保住 `x<br>\ny`），绝不写 `"  \n\n"`：
    /// 空行会把段落误拆成两段（B24 的原始问题）。
    /// 段首 / 段尾的换行段若会写出孤立的行首 / 行尾 "\n"，退化为 `<br>` 串。
    private static func breakAwareMarkdown(_ raw: String, atLineStart: Bool, atEnd: Bool) -> String {
        let chars = Array(raw)
        var out = ""
        var textStart = 0
        var run: [Bool] = []   // true = 硬换行，false = 软换行

        // 输出 [textStart, end) 的正文；有 pending 换行段时先刷段（段在正文前）。
        // 相邻定界符（end == textStart）只吸收进 run、不刷段，保持连续段完整。
        func flushRun() {
            guard !run.isEmpty else { return }
            if run.count == 1 {
                // 段尾孤立软换行写 "\n" 会和块间换行并成空行，改写 <br>
                if !run[0], atEnd, textStart == chars.count {
                    out += "<br>"
                } else {
                    out += run[0] ? "  \n" : "\n"
                }
            } else {
                let f1 = run.map { $0 ? "<br>" : "\n" }.joined()
                let endsRaw = textStart == chars.count
                let unsafe = f1.contains("\n\n")
                    || (f1.hasPrefix("\n") && out.isEmpty && atLineStart)
                    || (f1.hasSuffix("\n") && endsRaw && atEnd)
                out += unsafe ? String(repeating: "<br>", count: run.count) : f1
            }
            run = []
        }
        func flushText(_ end: Int) {
            if end > textStart {
                if !run.isEmpty { flushRun() }
                // 每个正文段独立判行首：换行段之后的段（如 `x<br>\n---` 的 `---`）
                // 必须做块级记号转义，否则下一轮被误拆成 hr / 列表。
                out += escapeMarkdown(String(chars[textStart..<end]),
                                      atLineStart: out.isEmpty ? atLineStart : out.hasSuffix("\n"))
            }
            textStart = end
        }

        var i = 0
        while i < chars.count {
            if i + 2 < chars.count, chars[i] == " ", chars[i + 1] == " ", chars[i + 2] == "\u{2028}" {
                flushText(i)
                run.append(true)
                i += 3
                textStart = i
            } else if chars[i] == "\u{2028}" {
                flushText(i)
                run.append(false)
                i += 1
                textStart = i
            } else {
                i += 1
            }
        }
        flushText(chars.count)
        flushRun()
        return out
    }

    /// 重建被编辑过的单行：剥掉全部快照属性再走正常重建。
    /// 不剥会命中逐行 / 块级快照短路，递归回自己。
    static func rebuildEditedLine(_ line: NSAttributedString) -> String {
        guard line.length > 0 else { return "" }
        let clean = NSMutableAttributedString(attributedString: line)
        let r = NSRange(location: 0, length: clean.length)
        for key in [NSAttributedString.Key.mdLineSources, .mdLineDisplays, .mdLineTraits,
                    .mdEmphasisSource, .mdEmphasisDisplay, .mdEmphasisTraits,
                    .mdQuoteRaw, .mdQuoteSource,
                    .mdQuoteLineSources, .mdQuoteLineDisplays, .mdQuoteLineTraits,
                    .mdQuoteLineMap] {
            clean.removeAttribute(key, range: r)
        }
        return markdown(clean)
    }

    /// 段落文本里独占一行的 "  " 是空内容硬换行：按 "  \n" 写出去会被下一轮
    /// 解析成空行（空白行 = 段落分隔）整行丢失，必须写成反斜杠硬换行 "\\\n"
    /// （CommonMark §6.6：行尾反斜杠恒为硬换行）。
    /// 只处理**后随换行的完整行**：串尾的 "  " 是未完成行——列表项续段落的
    /// 行缩进会存进文本 run（`  aaa\u{2028}  ` + 代码 run），那是下一行内容的
    /// 缩进前缀，误转成 `\` 会顶掉缩进还给相邻标记加错转义（md4c 005 实测）。
    private static func fixEmptyHardBreaks(_ s: String) -> String {
        guard s.contains("\n") else { return s }
        var lines = s.components(separatedBy: "\n")
        var changed = false
        for k in lines.indices where k < lines.count - 1 && lines[k] == "  " {
            lines[k] = "\\"
            changed = true
        }
        return changed ? lines.joined(separator: "\n") : s
    }

    /// 代码 span 围栏：内容含反引号时用比最长连续反引号更长的围栏，
    /// 否则 `` `a`b` `` 这类内容会把 span 提前闭合、尾巴漏成字面文本。
    /// 只返回纯反引号串；内容以反引号开头 / 结尾时的定界空格由 Mark.code 的
    /// pad 决定，加在围栏内侧。
    private static func codeFence(for text: String) -> String {
        var maxRun = 0, cur = 0
        for ch in text {
            if ch == "`" { cur += 1; maxRun = max(maxRun, cur) } else { cur = 0 }
        }
        return String(repeating: "`", count: maxRun + 1)
    }

    private static func openingHTML(_ mark: Mark) -> String {
        switch mark {
        case .link(let url, let title):
            let t = title.isEmpty ? "" : " title=\"\(escapeHTML(title))\""
            return "<a href=\"\(escapeHTML(url))\"\(t)>"
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

    /// Markdown 特殊字符转义。atLineStart 表示本串第一个字符落在输出行首：
    /// 行首若是块级记号（分割线 / setext 下划线 / ATX 标题 / 引用 / 列表项），
    /// 还要转义记号本身，否则下一轮解析会把同一段落误拆成多个块。
    /// 只对文本 run 调用——序列化器生成的标记（代码围栏等）不得经过这里。
    private static func escapeMarkdown(_ s: String, atLineStart: Bool) -> String {
        let lines = s.components(separatedBy: "\n")
        var parts: [String] = []
        for (i, line) in lines.enumerated() {
            var escaped = escapeInlineChars(line)
            if i > 0 || atLineStart {
                escaped = escapeBlockStartLine(escaped)
            }
            parts.append(escaped)
        }
        return parts.joined(separator: "\n")
    }

    /// 行首是块级记号时转义记号字符：分割线 / setext 下划线转义首字符，
    /// 有序列表转义 `.` / `)`（转义数字无效，`\1` 会留下可见反斜杠）。
    private static func escapeBlockStartLine(_ line: String) -> String {
        let spaces = line.prefix(while: { $0 == " " }).count
        guard spaces <= 3 else { return line }   // 4+ 空格是缩进代码，不能打断段落
        let rest = line.dropFirst(spaces)
        guard let first = rest.first else { return line }
        let tail = String(rest.dropFirst())

        func isThematic() -> Bool {
            guard first == "-" || first == "*" || first == "_" else { return false }
            var count = 0
            for ch in tail where ch != " " {
                guard ch == first else { return false }
                count += 1
            }
            return count + 1 >= 3
        }
        func isSetext() -> Bool {
            (first == "-" || first == "=") && tail.allSatisfy { $0 == first }
        }
        func isFence() -> Bool {
            rest.hasPrefix("```") || rest.hasPrefix("~~~")
        }
        func isATX() -> Bool {
            guard first == "#" else { return false }
            let hashes = rest.prefix(while: { $0 == "#" }).count
            guard hashes <= 6 else { return false }
            let after = rest.dropFirst(hashes)
            return after.isEmpty || after.hasPrefix(" ") || after.hasPrefix("\t")
        }
        func orderedMarkerDot() -> String.Index? {
            guard first.isNumber else { return nil }
            let digits = rest.prefix(while: { $0.isNumber }).count
            guard digits >= 1, digits <= 9 else { return nil }
            let idx = line.index(line.startIndex, offsetBy: spaces + digits)
            guard idx < line.endIndex, line[idx] == "." || line[idx] == ")" else { return nil }
            let after = line.index(after: idx)
            guard after == line.endIndex || line[after] == " " || line[after] == "\t" else { return nil }
            return idx
        }
        func isBulletItem() -> Bool {
            (first == "-" || first == "+" || first == "*")
                && (tail.isEmpty || tail.hasPrefix(" ") || tail.hasPrefix("\t"))
        }

        if let dot = orderedMarkerDot() {
            return line.prefix(upTo: dot) + "\\" + line[dot...]
        }
        let dangerous = first == ">" || isThematic() || isSetext() || isFence()
            || isATX() || isBulletItem()
        guard dangerous else { return line }
        return line.prefix(spaces) + "\\" + line.dropFirst(spaces)
    }

    private static func escapeInlineChars(_ s: String) -> String {
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
        return breakExtendedAutolinks(out)
    }

    /// 写回防御：纯文本里裸 URL / 裸邮箱形态下一轮会被 GFM 扩展 autolink 重新
    /// 识别成链接，二轮结构漂移失去一次稳定（`\<foo+@bar.com>` 实测）。在关键
    /// 字符前插一个反斜杠转义（`\@` / `\:` / `\.`）打断识别；转义对重解析后
    /// 显示不变，且与 marked/cmark-gfm 语义一致（实测 `foo\+@bar.com` 不成链）。
    private static func breakExtendedAutolinks(_ s: String) -> String {
        let chars = Array(s)
        var inserts: [Int] = []   // 在该下标前插 "\"
        var i = 0
        while i < chars.count {
            if chars[i] == "\\" { i += 2; continue }   // 跳过已有转义对
            let boundary = i == 0 || chars[i - 1].isWhitespace
                || "\"'([{<*_,;:!?".contains(chars[i - 1])
            if boundary {
                let rest = String(chars[i...])
                // 裸邮箱：@ 前插转义
                let mailPat = "^[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\\.)+[A-Za-z]{2,}"
                if let m = rest.range(of: mailPat, options: [.regularExpression]) {
                    let text = String(rest[m])
                    if let at = text.firstIndex(of: "@") {
                        inserts.append(i + text.distance(from: text.startIndex, to: at))
                    }
                    i += text.count
                    continue
                }
                // http(s):// ：冒号前插转义
                if rest.hasPrefix("https://") {
                    inserts.append(i + 5)
                    i += 8
                    continue
                }
                if rest.hasPrefix("http://") {
                    inserts.append(i + 4)
                    i += 7
                    continue
                }
                // www. ：第一个点前插转义
                if rest.hasPrefix("www.") {
                    inserts.append(i + 3)
                    i += 4
                    continue
                }
            }
            i += 1
        }
        guard !inserts.isEmpty else { return s }
        var out = ""
        var last = 0
        for pos in inserts {
            out += String(chars[last..<pos]) + "\\"
            last = pos
        }
        out += String(chars[last...])
        return out
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
