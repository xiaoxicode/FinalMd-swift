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

// MARK: - 输入属性（typingAttributes）

/// 根据块样式构造一份完整的 typingAttributes。
/// 空文档 / 空段落上没有字符可取属性时用它，保证「接下来敲的字」就是该样式（Word 行为）。
enum EditorStyle {

    /// 默认输入属性：正文。新建文档 / 清空文档后从这里开始写，而不是残留上一个文档的样式。
    static var defaultTyping: [NSAttributedString.Key: Any] {
        typing(for: .paragraph)
    }

    static func typing(for style: BlockStyle) -> [NSAttributedString.Key: Any] {
        let type: MDBlockType
        switch style {
        case .paragraph: type = .paragraph
        case .heading(let n): type = MDBlockType(headingLevel: n)
        case .quote: type = .quote
        case .code: type = .code
        }

        var attrs: [NSAttributedString.Key: Any] = [:]
        let ps = DocTheme.paragraphStyle(for: type)
        switch type {
        case .code:
            attrs[.font] = DocTheme.monospacedFont(size: DocTheme.codeFontSize)
            ps.textBlocks = [DocTheme.codeTextBlock]
            attrs[.foregroundColor] = DocTheme.text
        case .quote:
            attrs[.font] = DocTheme.bodyFont
            ps.textBlocks = [DocTheme.quoteTextBlock]
            attrs[.foregroundColor] = DocTheme.textDim
        case .paragraph:
            attrs[.font] = DocTheme.bodyFont
            attrs[.foregroundColor] = DocTheme.text
        default:
            let size = DocTheme.headingFontSize(type.headingLevel ?? 1)
            attrs[.font] = DocTheme.documentFont(size: size, weight: .bold)
            attrs[.mdStructuralBold] = true   // 排版加粗不是用户敲的 **，序列化时不输出
            attrs[.foregroundColor] = type.headingLevel == 6 ? DocTheme.textDim : DocTheme.text
        }
        attrs[.paragraphStyle] = ps
        attrs[.mdBlockType] = type.rawValue
        return attrs
    }
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

    /// 需要作用的段落范围（光标时取整个段落）。
    /// 段落范围保留结尾的 \n：段落级属性（段落样式 / 块类型）必须写到段落终结符上，
    /// 回车换行才能继承上一行的模式，修改显示模式后接着输入才会跟随新模式（Word 行为）。
    func targetRanges() -> [NSRange] {
        let sel = selectedRange()
        let s = string as NSString
        guard s.length > 0 else { return [NSRange(location: 0, length: 0)] }

        if sel.length == 0 {
            return [s.paragraphRange(for: sel)]
        }
        var out: [NSRange] = []
        s.enumerateSubstrings(in: sel, options: [.byParagraphs]) { _, subRange, _, _ in
            var r = subRange
            // 段落枚举不包含段末的换行符（选区正好停在行尾时尤其如此）。
            // 段落级属性必须落到 \n 上，否则回车换行没东西可继承，新行就会掉回正文。
            if NSMaxRange(r) < s.length, s.character(at: NSMaxRange(r)) == 0x0A {
                r.length += 1
            }
            out.append(r)
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
                // 结构性加粗已被用户接管，去掉标记。
                // 注意只有「加粗」开关才清标记：切换斜体不该把结构性加粗标记抹掉，
                // 否则「标题改回正文」时无法准确剥掉排版加粗，正文会莫名残留粗体。
                if trait == .bold {
                    storage.removeAttribute(.mdStructuralBold, range: r)
                }
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
                    // 文档里存原色，屏幕上显示按当前外观调整过的动态色
                    storage.addAttribute(.foregroundColor, value: DocTheme.displayTextColor(color), range: r)
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
                    storage.addAttribute(.backgroundColor, value: DocTheme.displayHighlight(color), range: r)
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
        // 空文档、或插入点落在文末空行时，没有任何字符能承载段落属性：
        // 这时只调整「接下来输入的样式」，直接去改 storage 会越界崩溃。
        if targetRanges().contains(where: { $0.length > 0 }) {
            performEdit { storage, ranges in
                for r in ranges where r.length > 0 {
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
                            // 结构性加粗标记随块样式一起清除
                            if (storage.attribute(.mdStructuralBold, at: fr.location, effectiveRange: nil) as? Bool) == true {
                                storage.removeAttribute(.mdStructuralBold, range: fr)
                            }
                            continue
                        }
                        let font = storage.attribute(.font, at: fr.location, effectiveRange: nil) as? NSFont ?? DocTheme.bodyFont
                        var d = font.fontDescriptor
                        var traits = d.symbolicTraits

                        if newType.headingLevel != nil {
                            if !traits.contains(.bold) {
                                traits.insert(.bold)
                                // 原本不是粗体、现在为排版加粗 → 打结构性标记；
                                // 用户自己加粗的文字不打标记，标题改回正文时保留用户粗体
                                storage.addAttribute(.mdStructuralBold, value: true, range: fr)
                            }
                        } else if (storage.attribute(.mdStructuralBold, at: fr.location, effectiveRange: nil) as? Bool) == true {
                            // 从标题等带结构性加粗的样式切走：精确剥掉排版加粗，
                            // 用户显式设置的粗体（无标记）不受影响
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
        // 模式改完后同步输入属性：接着这行继续敲字，新字要和这行保持同一模式（Word 行为）。
        refreshTypingAttributes(fallbackStyle: style)
    }

    /// 块样式 / 对齐等修改后，把 typingAttributes 同步为光标处的当前样式，
    /// 保证改完模式紧接着输入的文字跟随新模式（Word 行为）。
    /// 空文档或空段落没有字符可取时，用 fallbackStyle（或默认正文）构造。
    func refreshTypingAttributes(fallbackStyle: BlockStyle? = nil) {
        guard let storage = textStorage, storage.length > 0 else {
            typingAttributes = fallbackStyle.map { EditorStyle.typing(for: $0) } ?? EditorStyle.defaultTyping
            return
        }
        let s = storage.string as NSString
        let sel = selectedRange()
        let para = s.paragraphRange(for: NSRange(location: min(sel.location, s.length), length: 0))
        guard para.length > 0 else {
            typingAttributes = fallbackStyle.map { EditorStyle.typing(for: $0) } ?? EditorStyle.defaultTyping
            return
        }
        // 段落级属性取自本段开头；行内属性（字体/颜色等）取自光标前一个字符，
        // 与 Word「接着当前输入点的格式继续写」一致。
        var attrs = storage.attributes(at: para.location, effectiveRange: nil)
        let loc = min(max(sel.location, para.location), NSMaxRange(para) - 1)
        if loc > para.location {
            let before = storage.attributes(at: loc - 1, effectiveRange: nil)
            for key in Self.inlineTypingKeys {
                if let v = before[key] { attrs[key] = v } else { attrs.removeValue(forKey: key) }
            }
        }
        typingAttributes = attrs
    }

    /// 行内属性键：typingAttributes 同步时跟随光标前字符，不取段落头
    static let inlineTypingKeys: [NSAttributedString.Key] = [
        .font, .foregroundColor, .backgroundColor, .underlineStyle, .strikethroughStyle,
        .link, .mdInlineCode, .mdTextColor, .mdHighlight,
    ]

    func setAlignment(_ alignment: NSTextAlignment) {
        performEdit { storage, ranges in
            for r in ranges where r.length > 0 {
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
                // 剥掉旧的项目符号（文末空行长度为 0，没有字符可读，直接跳到插入）
                if len > 0, storage.attribute(.mdListItem, at: loc, effectiveRange: nil) != nil {
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
                let attrs = storage.attributes(at: max(min(loc - 1, storage.length - 1), 0), effectiveRange: nil)
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
            for r in ranges.reversed() where r.length > 0 {
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
                // 文末空行（长度 0、位置等于文档长度）取不到属性，退回末字符的属性
                let probe = min(max(r.length > 0 ? r.location : r.location - 1, 0), max(storage.length - 1, 0))
                let attrs = storage.attributes(at: probe, effectiveRange: nil)
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
