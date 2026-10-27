//
//  TextFormatting.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  NSTextView 上的排版命令，对应 Electron 版 app.js 的 dispatch() 各分支：
//  块级（标题 / 引用 / 代码块 / 列表 / 对齐 / 缩进）与行级（加粗 / 斜体 / 颜色 / 高亮 …）。
//

import AppKit

/// 块级样式
enum BlockStyle: Hashable {
    case paragraph
    case heading(Int)
    case quote
    case code
}

extension NSTextView {

    // MARK: - 基础编辑封装（带撤销）

    /// 在 shouldChangeText / didChangeText 之间改 textStorage，保证撤销栈正确
    func performEdit(_ block: (NSTextStorage, [NSRange]) -> Void) {
        guard let storage = textStorage else { return }
        let ranges = targetRanges()
        guard !ranges.isEmpty else { return }
        let union = ranges.reduce(ranges[0]) { NSUnionRange($0, $1) }
        guard shouldChangeText(in: union, replacementString: nil) else { return }
        storage.beginEditing()
        block(storage, ranges)
        storage.endEditing()
        didChangeText()
        needsDisplay = true
    }

    /// 需要作用的段落范围（光标时取整个段落）
    func targetRanges() -> [NSRange] {
        let sel = selectedRange()
        let s = string as NSString
        guard s.length > 0 else { return [NSRange(location: 0, length: 0)] }

        if sel.length == 0 {
            var r = s.paragraphRange(for: sel)
            if r.length > 0, s.character(at: NSMaxRange(r) - 1) == 0x0A { r.length -= 1 }
            return [r]
        }
        var out: [NSRange] = []
        s.enumerateSubstrings(in: sel, options: [.byParagraphs]) { _, subRange, _, _ in
            out.append(subRange)
        }
        return out.isEmpty ? [sel] : out
    }

    // MARK: - 状态查询

    func hasTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let sel = selectedRange()
        if sel.length == 0 {
            let font = storage.attribute(.font, at: max(sel.location - 1, 0), effectiveRange: nil) as? NSFont
            return font?.fontDescriptor.symbolicTraits.contains(trait) ?? false
        }
        var all = true
        storage.enumerateAttribute(.font, in: sel, options: []) { value, _, stop in
            let font = value as? NSFont ?? DocTheme.bodyFont
            if !font.fontDescriptor.symbolicTraits.contains(trait) { all = false; stop.pointee = true }
        }
        return all
    }

    func hasAttribute(_ key: NSAttributedString.Key) -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let loc = max(selectedRange().location - 1, 0)
        return storage.attribute(key, at: loc, effectiveRange: nil) != nil
    }

    func currentBlockType() -> MDBlockType {
        guard let storage = textStorage, storage.length > 0 else { return .paragraph }
        let loc = min(selectedRange().location, storage.length - 1)
        let raw = storage.attribute(.mdBlockType, at: max(loc, 0), effectiveRange: nil) as? String
        return MDBlockType(rawValue: raw ?? "p") ?? .paragraph
    }

    func currentAlignment() -> NSTextAlignment {
        guard let storage = textStorage, storage.length > 0 else { return .natural }
        let loc = min(selectedRange().location, storage.length - 1)
        let ps = storage.attribute(.paragraphStyle, at: max(loc, 0), effectiveRange: nil) as? NSParagraphStyle
        return ps?.alignment ?? .natural
    }

    func isListItem() -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let loc = min(selectedRange().location, storage.length - 1)
        return storage.attribute(.mdListItem, at: max(loc, 0), effectiveRange: nil) != nil
    }

    // MARK: - 行内样式

    func toggleTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        let shouldAdd = !hasTrait(trait)
        performEdit { storage, ranges in
            for r in ranges {
                storage.enumerateAttribute(.font, in: r, options: []) { value, range, _ in
                    let font = value as? NSFont ?? DocTheme.bodyFont
                    let d = font.fontDescriptor
                    var traits = d.symbolicTraits
                    if shouldAdd { traits.insert(trait) } else { traits.remove(trait) }
                    let nd = d.withSymbolicTraits(traits)
                    storage.addAttribute(.font,
                                         value: NSFont(descriptor: nd, size: font.pointSize) ?? font,
                                         range: range)
                }
                // 结构性加粗已被用户接管，去掉标记
                storage.removeAttribute(.mdStructuralBold, range: r)
            }
        }
    }

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }

    func toggleUnderline() {
        let shouldAdd = !hasAttribute(.underlineStyle)
        performEdit { storage, ranges in
            for r in ranges {
                if shouldAdd {
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
                } else {
                    storage.removeAttribute(.underlineStyle, range: r)
                }
            }
        }
    }

    func toggleStrike() {
        let shouldAdd = !hasAttribute(.strikethroughStyle)
        performEdit { storage, ranges in
            for r in ranges {
                if shouldAdd {
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
                } else {
                    storage.removeAttribute(.strikethroughStyle, range: r)
                }
            }
        }
    }

    func setTextColor(_ color: NSColor?) {
        performEdit { storage, ranges in
            for r in ranges {
                if let color {
                    storage.addAttribute(.foregroundColor, value: color, range: r)
                    storage.addAttribute(.mdTextColor, value: color, range: r)
                } else {
                    storage.addAttribute(.foregroundColor, value: DocTheme.text, range: r)
                    storage.removeAttribute(.mdTextColor, range: r)
                }
            }
        }
    }

    func setHighlight(_ color: NSColor?) {
        performEdit { storage, ranges in
            for r in ranges {
                if let color {
                    storage.addAttribute(.backgroundColor, value: color, range: r)
                    storage.addAttribute(.mdHighlight, value: color, range: r)
                } else {
                    storage.removeAttribute(.backgroundColor, range: r)
                    storage.removeAttribute(.mdHighlight, range: r)
                }
            }
        }
    }

    func clearFormatting() {
        performEdit { storage, ranges in
            for r in ranges {
                storage.enumerateAttribute(.font, in: r, options: []) { value, range, _ in
                    let font = value as? NSFont ?? DocTheme.bodyFont
                    var traits = font.fontDescriptor.symbolicTraits
                    traits.remove(.bold)
                    traits.remove(.italic)
                    let nd = font.fontDescriptor.withSymbolicTraits(traits)
                    storage.addAttribute(.font,
                                         value: NSFont(descriptor: nd, size: DocTheme.bodyFontSize) ?? DocTheme.bodyFont,
                                         range: range)
                }
                [NSAttributedString.Key.underlineStyle,
                 .strikethroughStyle,
                 .link,
                 .backgroundColor,
                 .mdTextColor,
                 .mdHighlight,
                 .mdInlineCode,
                 .mdStructuralBold].forEach { storage.removeAttribute($0, range: r) }
                storage.addAttribute(.foregroundColor, value: DocTheme.text, range: r)
            }
        }
    }

    // MARK: - 块级样式

    func applyBlockStyle(_ style: BlockStyle) {
        performEdit { storage, ranges in
            for r in ranges {
                let oldRaw = storage.attribute(.mdBlockType, at: r.location, effectiveRange: nil) as? String
                let oldType = MDBlockType(rawValue: oldRaw ?? "p") ?? .paragraph

                let newType: MDBlockType
                switch style {
                case .paragraph: newType = .paragraph
                case .heading(let n): newType = MDBlockType(headingLevel: n)
                case .quote: newType = .quote
                case .code: newType = .code
                }

                let size: CGFloat
                switch newType {
                case .code: size = DocTheme.codeFontSize
                case .paragraph, .quote: size = DocTheme.bodyFontSize
                default: size = DocTheme.headingFontSize(newType.headingLevel ?? 1)
                }

                let keepAlignment = (storage.attribute(.paragraphStyle, at: r.location, effectiveRange: nil)
                    as? NSParagraphStyle)?.alignment ?? .natural

                let rangesSnapshot: [NSRange] = {
                    var list: [NSRange] = []
                    storage.enumerateAttribute(.font, in: r, options: []) { _, range, _ in list.append(range) }
                    return list.isEmpty ? [r] : list
                }()

                for fr in rangesSnapshot {
                    if newType == .code {
                        storage.addAttribute(.font, value: DocTheme.monospacedFont(size: DocTheme.codeFontSize), range: fr)
                        continue
                    }
                    let font = storage.attribute(.font, at: fr.location, effectiveRange: nil) as? NSFont ?? DocTheme.bodyFont
                    var d = font.fontDescriptor
                    var traits = d.symbolicTraits

                    if newType.headingLevel != nil {
                        if !traits.contains(.bold) {
                            traits.insert(.bold)
                            storage.addAttribute(.mdStructuralBold, value: true, range: fr)
                        }
                    } else if oldType.headingLevel != nil,
                              (storage.attribute(.mdStructuralBold, at: fr.location, effectiveRange: nil) as? Bool) == true {
                        traits.remove(.bold)
                        storage.removeAttribute(.mdStructuralBold, range: fr)
                    }

                    d = d.withSymbolicTraits(traits)
                    let newFont = NSFont(descriptor: d.withSize(size), size: size) ?? font
                    storage.addAttribute(.font, value: newFont, range: fr)
                }

                // 段落样式
                let ps = DocTheme.paragraphStyle(for: newType, alignment: keepAlignment)
                switch newType {
                case .quote: ps.textBlocks = [DocTheme.quoteTextBlock]
                case .code: ps.textBlocks = [DocTheme.codeTextBlock]
                default: ps.textBlocks = []
                }
                storage.addAttribute(.paragraphStyle, value: ps, range: r)
                storage.addAttribute(.mdBlockType, value: newType.rawValue, range: r)

                if newType == .code {
                    storage.removeAttribute(.mdListItem, range: r)
                }
                if newType == .quote {
                    storage.addAttribute(.foregroundColor, value: DocTheme.textDim, range: r)
                } else if oldType == .quote {
                    storage.addAttribute(.foregroundColor, value: DocTheme.text, range: r)
                }
            }
        }
    }

    func setAlignment(_ alignment: NSTextAlignment) {
        performEdit { storage, ranges in
            for r in ranges {
                let base = storage.attribute(.paragraphStyle, at: r.location, effectiveRange: nil) as? NSParagraphStyle
                let ps = (base?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                ps.alignment = alignment
                storage.addAttribute(.paragraphStyle, value: ps, range: r)
            }
        }
    }

    // MARK: - 列表

    func makeList(ordered: Bool) {
        performEdit { storage, ranges in
            for r in ranges.reversed() {
                let loc = r.location
                var len = r.length
                // 剥掉旧的项目符号
                if storage.attribute(.mdListItem, at: loc, effectiveRange: nil) != nil {
                    let s = storage.string as NSString
                    let head = s.substring(with: NSRange(location: loc, length: min(8, len)))
                    if let sp = head.firstIndex(of: " ") {
                        let drop = head.distance(from: head.startIndex, to: sp) + 1
                        storage.deleteCharacters(in: NSRange(location: loc, length: drop))
                        len -= drop
                    }
                    storage.removeAttribute(.mdListItem, range: NSRange(location: loc, length: len))
                }
                let marker = ordered ? "1. " : "- "
                let attrs = storage.attributes(at: max(loc - 1, 0), effectiveRange: nil)
                storage.insert(NSAttributedString(string: marker, attributes: attrs), at: loc)
                len += (marker as NSString).length
                let full = NSRange(location: loc, length: len)
                storage.addAttribute(.mdListItem, value: MDListItem(ordered: ordered, level: 0), range: full)
                storage.addAttribute(.mdBlockType, value: MDBlockType.paragraph.rawValue, range: full)
            }
        }
    }

    func removeList() {
        performEdit { storage, ranges in
            for r in ranges.reversed() {
                guard storage.attribute(.mdListItem, at: r.location, effectiveRange: nil) != nil else { continue }
                let s = storage.string as NSString
                let head = s.substring(with: NSRange(location: r.location, length: min(8, r.length)))
                var len = r.length
                if let sp = head.firstIndex(of: " ") {
                    let drop = head.distance(from: head.startIndex, to: sp) + 1
                    storage.deleteCharacters(in: NSRange(location: r.location, length: drop))
                    len -= drop
                }
                storage.removeAttribute(.mdListItem, range: NSRange(location: r.location, length: len))
            }
        }
    }

    func toggleList(ordered: Bool) {
        if isListItem() { removeList() } else { makeList(ordered: ordered) }
    }

    // MARK: - 缩进

    private static let indentUnit = "　　"   // 两个全角空格 ≈ 首行缩进两字符

    func indentParagraphs() {
        performEdit { storage, ranges in
            for r in ranges.reversed() {
                let attrs = storage.attributes(at: r.location, effectiveRange: nil)
                storage.insert(NSAttributedString(string: Self.indentUnit, attributes: attrs), at: r.location)
            }
        }
    }

    func outdentParagraphs() {
        performEdit { storage, ranges in
            for r in ranges.reversed() {
                let s = storage.string as NSString
                guard r.length >= 2 else { continue }
                let head = s.substring(with: NSRange(location: r.location, length: 2))
                if head == Self.indentUnit || head.allSatisfy({ $0 == " " }) {
                    storage.deleteCharacters(in: NSRange(location: r.location, length: 2))
                }
            }
        }
    }

    // MARK: - 插入

    func insertRule() {
        guard textStorage != nil else { return }
        let loc = selectedRange().location
        let attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.bodyFont,
            .paragraphStyle: DocTheme.paragraphStyle(for: .paragraph),
        ]
        performEdit { st, _ in
            st.insert(NSAttributedString(string: "\n", attributes: attrs), at: loc)
            st.insert(NSAttributedString(attachment: MDRuleAttachment()), at: loc + 1)
            st.insert(NSAttributedString(string: "\n", attributes: attrs), at: loc + 2)
        }
        setSelectedRange(NSRange(location: loc + 3, length: 0))
    }

    func insertCodeBlock() {
        applyBlockStyle(.code)
        applyBlockStyle(.code)   // 幂等：已经是代码块时不再切换
    }

    func insertTable(rows: Int, cols: Int, hasHeader: Bool) {
        guard textStorage != nil else { return }
        let loc = selectedRange().location
        let attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.bodyFont,
            .paragraphStyle: DocTheme.paragraphStyle(for: .paragraph),
            .mdBlockType: MDBlockType.paragraph.rawValue,
        ]
        performEdit { st, _ in
            st.insert(NSAttributedString(string: "\n", attributes: attrs), at: loc)
            st.insert(MarkdownParser.makeTable(rows: rows, cols: cols, hasHeader: hasHeader), at: loc + 1)
        }
    }

    func insertImage(_ attachment: MDImageAttachment) {
        guard textStorage != nil else { return }
        let loc = selectedRange().location
        let attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.bodyFont,
            .paragraphStyle: DocTheme.paragraphStyle(for: .paragraph),
            .mdBlockType: MDBlockType.paragraph.rawValue,
        ]
        performEdit { st, _ in
            st.insert(NSAttributedString(string: "\n", attributes: attrs), at: loc)
            st.insert(NSAttributedString(attachment: attachment), at: loc + 1)
            st.insert(NSAttributedString(string: "\n", attributes: attrs), at: loc + 2)
        }
        setSelectedRange(NSRange(location: loc + 3, length: 0))
    }

    func insertLink(url: String, text: String?) {
        guard !url.isEmpty, textStorage != nil else { return }
        var attrs = typingAttributes
        attrs[.link] = url
        attrs[.foregroundColor] = DocTheme.accent
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        let label = (text?.isEmpty ?? true) ? url : text!
        performEdit { st, _ in
            let sel = selectedRange()
            st.insert(NSAttributedString(string: label, attributes: attrs), at: NSMaxRange(sel))
        }
        setSelectedRange(NSRange(location: selectedRange().location + (label as NSString).length, length: 0))
    }

    /// 用当前文档的标题生成目录
    func insertTOC() {
        guard let storage = textStorage else { return }
        var headings: [(Int, String)] = []
        let s = storage.string as NSString
        var loc = 0
        while loc < storage.length {
            let r = s.paragraphRange(for: NSRange(location: loc, length: 0))
            if r.length == 0 { break }
            loc = NSMaxRange(r)
            let attrs = storage.attributes(at: r.location, effectiveRange: nil)
            guard let raw = attrs[.mdBlockType] as? String,
                  let type = MDBlockType(rawValue: raw),
                  let level = type.headingLevel else { continue }
            let text = s.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            headings.append((level, text))
        }
        guard !headings.isEmpty else { return }

        // 插到文档开头
        let attrs: [NSAttributedString.Key: Any] = [
            .font: DocTheme.bodyFont,
            .paragraphStyle: DocTheme.paragraphStyle(for: .paragraph),
            .foregroundColor: DocTheme.text,
            .mdBlockType: MDBlockType.paragraph.rawValue,
        ]
        performEdit { st, _ in
            var at = 0
            for (level, text) in headings {
                let itemStyle = DocTheme.paragraphStyle(for: .paragraph)
                itemStyle.headIndent = CGFloat(16 + (level - 1) * 20)
                itemStyle.firstLineHeadIndent = CGFloat(16 + (level - 1) * 20)
                var a = attrs
                a[.paragraphStyle] = itemStyle
                let line = "• " + (text.isEmpty ? "（无标题文本）" : text)
                st.insert(NSAttributedString(string: line + "\n", attributes: a), at: at)
                at += (line as NSString).length + 1
            }
            st.insert(NSAttributedString(string: "\n", attributes: attrs), at: at)
        }
    }
}
