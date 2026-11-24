//
//  EditorView.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  把 NSTextView 包进 SwiftUI：NSScrollView → 页面容器（白纸）→ NSTextView。
//  对应 Electron 版 renderer/index.html 的 .workspace / .page / #editor 结构。
//

import SwiftUI
import AppKit

// MARK: - SwiftUI 包装

struct EditorView: NSViewRepresentable {

    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MDEditorTextView()
        textView.configure()
        textView.showsLineRuling = model.showLineRuling
        textView.delegate = context.coordinator

        let (scroll, page) = EditorScrollFactory.make(textView: textView)
        // 首帧就把显隐设对：ZStack 里后添加的源码视图默认会盖在上面，
        // 若等 updateNSView 才隐藏，AppKit 启动时可能先把焦点交给它。
        scroll.isHidden = model.editorMode != .instant
        context.coordinator.appliedHidden = model.editorMode == .instant
        context.coordinator.textView = textView
        context.coordinator.pageView = page
        context.coordinator.observe(scrollView: scroll)

        // ⌘/⌃ + 滚轮缩放：把结果同步回模型（状态栏百分比），
        // 同时更新 appliedZoom，避免下一次 SwiftUI 刷新把缩放拽回去
        scroll.onWheelZoom = { [weak coordinator = context.coordinator] value in
            guard let coordinator else { return }
            coordinator.appliedZoom = value
            coordinator.model.setZoom(value)
        }

        // 图片交互回调
        textView.onImageDoubleClick = { [weak model] attachment in
            guard let model else { return }
            guard let storage = textView.textStorage,
                  let range = storage.rangeOfAttachment(attachment) else {
                model.openChartDialog(editing: attachment)
                return
            }
            model.openChartDialog(editing: attachment, at: range)
        }
        textView.onDropImageFiles = { [weak model] urls in
            model?.insertImageFiles(urls)
        }
        textView.onDropImages = { [weak model] images in
            guard let model else { return }
            for image in images {
                let src = ImageEmbed.compressedDataURL(image: image) ?? ""
                textView.insertImage(MDImageAttachment(src: src, alt: "", image: image))
            }
            model.markDirty()
        }

        // Obsidian 交互：⌘+点击双链跳转 / 嵌入预览 / Callout 折叠
        textView.onWikiLinkActivated = { [weak model] link in
            model?.followWikiLink(link)
        }
        textView.onEmbedActivated = { [weak model] link in
            model?.previewEmbed(link)
        }
        textView.onCalloutToggle = { [weak textView] id in
            textView?.toggleCallout(id: id)
        }

        model.richTextView = textView
        model.textView = textView
        model.loadInitialContentIfNeeded()
        model.editorViewDidBecomeReady(.rich)
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        let visible = model.editorMode == .instant

        // 只在显隐真的变化时写 isHidden：每次 SwiftUI 刷新都写会额外触发
        // AppKit 布局，而布局周期里改视图树正是首响应者异常的温床。
        if coord.appliedHidden != visible {
            coord.appliedHidden = visible
            scrollView.isHidden = !visible
        }

        if coord.appliedMode != model.editorMode {
            coord.appliedMode = model.editorMode
            // 绝不在这里直接 resignFirstResponder()：那会让 AppKit 在布局周期里
            // 猜测下一个响应者并抛异常。改由窗口把焦点一次性交给可见侧，
            // 旧响应者由 NSWindow 负责让位（见 EditorFocus）。
            if visible {
                EditorFocus.scheduleHandoff(to: coord.textView, from: model.sourceTextView)
            }
        }

        // 只有当 model.zoom 真的变了才往 scroll view 里写。
        // 否则用户手势缩放会在下一次 SwiftUI 刷新时被硬拉回 model.zoom。
        if abs(model.zoom - coord.appliedZoom) > 0.001 {
            scrollView.magnification = model.zoom
            coord.appliedZoom = model.zoom
        }
        coord.pageView?.needsLayout = true
        coord.pageView?.layout()

        // 横线开关发生变化时同步给文本视图（值相同不会触发重绘）
        (coord.textView as? MDEditorTextView)?.showsLineRuling = model.showLineRuling
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        weak var textView: NSTextView?
        weak var pageView: EditorPageView?
        /// 最近一次由代码写进 scroll view 的缩放值，用来区分「模型变了」和「用户捏合了」
        var appliedZoom: Double = 1
        /// 最近一次应用到视图上的编辑模式，用来判断是否需要移交键盘焦点
        var appliedMode: EditorMode?
        /// 最近一次写入 scroll view 的显隐状态，避免每次刷新都触发 AppKit 布局
        var appliedHidden: Bool?

        init(model: AppModel) {
            self.model = model
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func observe(scrollView: NSScrollView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(magnifyDidEnd(_:)),
                name: NSScrollView.didEndLiveMagnifyNotification,
                object: scrollView)
        }

        /// 捏合/智能缩放结束后把结果回写给模型，状态栏的百分比才会跟着动
        @objc @MainActor private func magnifyDidEnd(_ note: Notification) {
            guard let scrollView = note.object as? NSScrollView else { return }
            appliedZoom = scrollView.magnification
            model.setZoom(scrollView.magnification)
        }

        func textDidChange(_ notification: Notification) {
            if let tv = textView { model.noteEdited(in: tv) }
            model.markDirty()
            model.refreshAll()
            pageView?.needsLayout = true
            pageView?.layout()
            // Markdown 快捷输入规则：输入 "# " 立刻变标题
            (textView as? MDEditorTextView)?.applyInputRules()
            // storage 变了，旧的临时属性范围可能已失效，按块 ID 重新套折叠状态
            (textView as? MDEditorTextView)?.reapplyFoldVisuals()
            model.refreshToolbar()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // 光标挪动后让输入属性跟上光标所在的段落（Word 行为）
            (textView as? MDEditorTextView)?.syncTypingAttributesFromCaret()
            model.refreshToolbar()
        }
    }
}

// MARK: - 文本视图

final class MDEditorTextView: NSTextView, InlineTypingMemory {

    var onImageDoubleClick: ((MDImageAttachment) -> Void)?
    var onDropImageFiles: (([URL]) -> Void)?
    var onDropImages: (([NSImage]) -> Void)?

    /// ⌘+点击 Obsidian 双链 / 嵌入 / Callout 折叠箭头
    var onWikiLinkActivated: ((MDWikiLink) -> Void)?
    var onEmbedActivated: ((MDWikiLink) -> Void)?
    var onCalloutToggle: ((Int) -> Void)?

    /// 折叠的 Callout 块 ID。只影响渲染，不写进 NSTextStorage，
    /// 因此序列化、存盘、undo 历史都不会看到「折叠」这件事。
    private var foldedCalloutIDs: Set<Int> = []
    private var appliedFoldRanges: [NSRange] = []
    private static let foldedAttribute = NSAttributedString.Key("finalmd.folded")

    /// 正在执行回车换行。期间 didChangeSelection 会因插入点移动而触发，
    /// 若不拦住，syncTypingAttributesFromCaret 会用插入点前一个字符的属性
    /// 覆盖 insertNewline 里刚合并好的块级属性，导致新行丢模式。
    private var isInsertingNewline = false

    /// 无选区时通过工具栏设置的行内样式（荧光笔 / 加粗 …）。
    /// 记下设置时的插入点：光标未移动期间，防止 didChangeSelection 把
    /// typingAttributes 重算掉；光标一移动即作废，样式不会被带到别处。
    private var pendingInlineTyping: (location: Int, attrs: [NSAttributedString.Key: Any])?

    func rememberInlineTyping(_ attrs: [NSAttributedString.Key: Any]) {
        pendingInlineTyping = (selectedRange().location, attrs)
    }

    func clearPendingInlineTyping() {
        pendingInlineTyping = nil
    }

    private func validPendingInlineTyping() -> [NSAttributedString.Key: Any]? {
        let sel = selectedRange()
        guard let p = pendingInlineTyping, p.location == sel.location, sel.length == 0 else {
            pendingInlineTyping = nil
            return nil
        }
        return p.attrs
    }

    func configure() {
        isRichText = true
        isEditable = true
        isSelectable = true
        allowsUndo = true
        importsGraphics = true
        allowsImageEditing = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = true
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        usesFindBar = false
        drawsBackground = false
        font = DocTheme.bodyFont
        textColor = DocTheme.text
        // 插入点跟随正文色：深色纸面上默认的黑色光标几乎看不见
        insertionPointColor = DocTheme.text
        typingAttributes = EditorStyle.defaultTyping

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = []
        textContainerInset = NSSize(width: 0, height: 0)
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.lineFragmentPadding = 0
    }

    // MARK: 插入点（光标）随字号缩放

    /// 光标处的有效字体。优先取 typingAttributes —— 空段落、刚切换块样式时，
    /// 只有它带着新字号；再退回插入点前一字符的字体，最后是视图默认字体。
    private func caretFont() -> NSFont {
        if let f = typingAttributes[.font] as? NSFont { return f }
        if let storage = textStorage, storage.length > 0 {
            let loc = min(max(selectedRange().location - 1, 0), storage.length - 1)
            if let f = storage.attribute(.font, at: loc, effectiveRange: nil) as? NSFont { return f }
        }
        return font ?? DocTheme.bodyFont
    }

    /// 光标所在行的基线 y（视图坐标系）。
    ///
    /// `lineHeightMultiple` 会把额外行距堆在行片段顶部，所以「行片段中线」并不是文字中线，
    /// 只有基线能准确定位字身。这里用系统传入矩形的纵向位置找到所属行片段，
    /// 再取该行首个字形的基线；落在段间距等空白处时，退而取纵向最近的一行。
    private func caretBaselineY(containing rect: NSRect) -> CGFloat? {
        guard let lm = layoutManager, lm.numberOfGlyphs > 0 else { return nil }
        let origin = textContainerOrigin
        let probeY = rect.midY - origin.y
        var nearestBaseline: CGFloat?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        var index = 0
        while index < lm.numberOfGlyphs {
            var glyphRange = NSRange()
            let fragment = lm.lineFragmentRect(forGlyphAt: index, effectiveRange: &glyphRange)
            let baseline = fragment.minY + lm.location(forGlyphAt: index).y + origin.y
            let distance = abs(probeY - fragment.midY)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestBaseline = baseline
            }
            if probeY >= fragment.minY && probeY < fragment.maxY { return baseline }
            let next = NSMaxRange(glyphRange)
            index = next > index ? next : index + 1
        }
        return nearestBaseline
    }

    /// AppKit 算出的插入点矩形用的是视图固定字体（configure 里设的 16pt 正文），
    /// 标题 / 代码块换字号后光标不会跟着变；而正文 1.8 倍行高又把文字压到行片段底部。
    /// 因此这里按「光标处字体 + 该行基线」重算矩形：高度随字号变化，上下边缘与文字齐平。
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let font = caretFont()
        let size = DocTheme.caretSize(for: font)
        var r: NSRect
        if let baseline = caretBaselineY(containing: rect) {
            r = DocTheme.caretRect(baselineY: baseline, x: rect.minX, font: font)
        } else {
            // 页面尚未完成排版（空文档 / 首帧）时退回系统矩形，保持 minY 不动，
            // 只按字号调整高度，避免光标浮到文字上方。
            r = rect
            r.size.height = size.height
        }
        r.size.width = max(rect.width, size.width)
        // 仍交给 AppKit 绘制：闪烁与 turnedOn=false 时的擦除逻辑都保持系统行为，
        // 且每次亮/灭用的都是同一个重算后的矩形，不会留下残影。
        super.drawInsertionPoint(in: r, color: color, turnedOn: flag)
    }

    // MARK: 文档横线（作业本行线）

    /// 是否显示文档横线。由 AppModel 推送，切换后立即重绘。
    var showsLineRuling = false {
        didSet {
            guard oldValue != showsLineRuling else { return }
            needsDisplay = true
        }
    }

    /// PDF 导出期间临时关掉横线：横线是编辑时的辅助线，不该印进成品文档
    var suppressesLineRuling = false

    /// 在每一行文字的下方画一条横线（就像作业本）。
    /// 用 layout manager 的行片段定位，横线才会随字号、行高、折行准确跟随文字，
    /// 而不是按固定像素间距硬画。
    private func drawLineRuling(in dirtyRect: NSRect) {
        guard let layoutManager, let container = textContainer, let storage = textStorage else { return }
        guard storage.length > 0 else { return }

        let glyphRange = layoutManager.glyphRange(for: container)
        guard glyphRange.length > 0 else { return }

        let origin = textContainerOrigin
        let right = origin.x + container.size.width

        let path = NSBezierPath()
        path.lineWidth = DocTheme.ruledLineWidth
        DocTheme.ruledLine.setStroke()

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, lineGlyphs, _ in
            guard lineGlyphs.length > 0 else { return }
            // 只画落在重绘区域里的行：长文档滚动时不必为整篇重建路径
            let y = origin.y + rect.maxY - DocTheme.ruledLineInset
            guard dirtyRect.minY - 2 <= y, y <= dirtyRect.maxY + 2 else { return }

            let charRange = layoutManager.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
            let loc = min(charRange.location, max(storage.length - 1, 0))
            let attrs = storage.attributes(at: loc, effectiveRange: nil)

            // 代码块自带宽底色和外框，透传块 / Callout 是源码视图或色块视图，
            // 再叠横线只会显脏
            if let raw = attrs[.mdBlockType] as? String,
               raw == MDBlockType.code.rawValue
                || raw == MDBlockType.raw.rawValue
                || raw == MDBlockType.callout.rawValue { return }
            // 图片 / 图表 / 分割线所在的整行不画
            if attrs[.attachment] != nil { return }

            path.move(to: NSPoint(x: origin.x, y: y))
            path.line(to: NSPoint(x: right, y: y))
        }

        path.stroke()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsLineRuling, !suppressesLineRuling else { return }
        drawLineRuling(in: dirtyRect)
    }

    /// 浅色 ↔ 深色切换后重绘正文与横线。
    /// TextKit 的排版结果与外观无关，属性里存的又是动态色，
    /// 所以不需要重新解析文档，重绘一遍就会按新外观取色。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        insertionPointColor = DocTheme.text
        needsDisplay = true
        updateInsertionPointStateAndRestartTimer(true)
    }

    // MARK: 回车换行（Word 行为）

    /// 回车换行：
    /// 1. 新行保持和回车之前一样的模式（标题 / 正文 / 引用 / 列表）。
    ///    段落级属性（paragraphStyle / mdBlockType 等）写在段落终结符 \n 上，
    ///    系统换行会让新 \n 继承插入点前的属性；这里再把 typingAttributes 对齐一次，
    ///    保证后续输入继续带块语义与结构性加粗标记。
    /// 2. 列表项：非空条目回车 → 新行自动补下一个符号 / 序号；
    ///    空条目回车 → 去掉符号退出列表、不新增行（与 Word 一致）。
    override func insertNewline(_ sender: Any?) {
        isInsertingNewline = true
        defer { isInsertingNewline = false }

        let before = currentParagraphAttributes()
        let beforeItem = before?[.mdListItem] as? MDListItem
        let beforeMarker = currentListItemMarkerText()

        // 空列表条目（只有符号、没有正文）：就地退出列表，不新增行（Word 行为）
        if beforeItem != nil, currentParagraphIsMarkerOnly() {
            convertCurrentParagraphToPlain()
            return
        }

        super.insertNewline(sender)
        guard let before else { return }

        // 段落级属性写在段落终结符 \n 上，系统换行时新 \n 已继承这些属性；
        // 这里再把 typingAttributes 对齐到回车前那段，保证后续输入继续带块语义
        // 与结构性加粗标记（Word 行为：Enter 后保持原模式）。
        var merged = typingAttributes
        for key in [NSAttributedString.Key.mdBlockType, .paragraphStyle, .mdListItem,
                    .mdStructuralBold, .mdRawID, .mdRawKind,
                    .mdCalloutID, .mdCalloutKind, .mdCalloutFold] {
            if let v = before[key] { merged[key] = v } else { merged.removeValue(forKey: key) }
        }
        // 整行快照属于原行，不能跟着回车继承到新段（否则新行会被旧源码盖掉）
        for key in MDEditorTextView.lineSnapshotKeys { merged.removeValue(forKey: key) }
        typingAttributes = merged

        // 非空列表条目 → 新行自动补下一个符号 / 序号
        if beforeItem != nil, let storage = textStorage {
            let s = storage.string as NSString
            let sel = selectedRange()
            let para = s.paragraphRange(for: NSRange(location: min(sel.location, s.length), length: 0))
            let bodyLen = max(para.length - 1, 0)
            let body = bodyLen > 0 ? s.substring(with: NSRange(location: para.location, length: bodyLen)) : ""
            if body.trimmingCharacters(in: .whitespaces).isEmpty {
                let marker = Self.nextListMarker(after: beforeMarker ?? "-")
                var attrs = merged
                // 序号由序列化器按出现顺序重算，这里沿用上一项的列表语义即可
                attrs[.mdListItem] = beforeItem
                if shouldChangeText(in: NSRange(location: para.location, length: 0),
                                    replacementString: marker) {
                    storage.insert(NSAttributedString(string: marker, attributes: attrs), at: para.location)
                    didChangeText()
                }
                let caret = para.location + (marker as NSString).length
                setSelectedRange(NSRange(location: caret, length: 0))
                typingAttributes = attrs
            }
        }
    }

    /// 当前段落开头到第一个空格之间的符号文本（"- " / "2. " …），取不到返回 nil
    private func currentListItemMarkerText() -> String? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let s = storage.string as NSString
        let para = s.paragraphRange(for: selectedRange())
        let bodyLen = max(para.length - 1, 0)
        guard bodyLen > 0 else { return nil }
        let body = s.substring(with: NSRange(location: para.location, length: bodyLen))
        return body.components(separatedBy: " ").first
    }

    /// 当前段落是否是「只剩符号」的空列表项
    private func currentParagraphIsMarkerOnly() -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let s = storage.string as NSString
        let para = s.paragraphRange(for: selectedRange())
        let bodyLen = max(para.length - 1, 0)
        let body = bodyLen > 0 ? s.substring(with: NSRange(location: para.location, length: bodyLen)) : ""
        let stripped: String
        if let sp = body.firstIndex(of: " ") {
            stripped = String(body[body.index(after: sp)...])
        } else {
            stripped = body
        }
        return stripped.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 把光标所在的空列表项还原成普通段落：删掉符号文本并清除列表属性
    private func convertCurrentParagraphToPlain() {
        guard let storage = textStorage else { return }
        let s = storage.string as NSString
        let para = s.paragraphRange(for: selectedRange())
        let bodyLen = max(para.length - 1, 0)
        let body = bodyLen > 0 ? s.substring(with: NSRange(location: para.location, length: bodyLen)) : ""
        var cut = 0
        if let sp = body.firstIndex(of: " ") {
            cut = body.distance(from: body.startIndex, to: sp) + 1
        }
        if cut > 0, shouldChangeText(in: NSRange(location: para.location, length: cut), replacementString: "") {
            storage.deleteCharacters(in: NSRange(location: para.location, length: cut))
            didChangeText()
        }
        let rest = NSRange(location: para.location, length: max(para.length - cut, 0))
        if rest.length > 0, shouldChangeText(in: rest, replacementString: nil) {
            storage.beginEditing()
            storage.removeAttribute(.mdListItem, range: rest)
            let keepAlign = (storage.attribute(.paragraphStyle, at: para.location, effectiveRange: nil)
                as? NSParagraphStyle)?.alignment ?? .natural
            storage.addAttribute(.paragraphStyle,
                                 value: DocTheme.paragraphStyle(for: .paragraph, alignment: keepAlign),
                                 range: rest)
            storage.addAttribute(.mdBlockType, value: MDBlockType.paragraph.rawValue, range: rest)
            storage.addAttribute(.foregroundColor, value: DocTheme.text, range: rest)
            storage.endEditing()
            didChangeText()
        }
        setSelectedRange(NSRange(location: para.location, length: 0))
        typingAttributes = EditorStyle.defaultTyping
    }

    /// 由上一个符号推出下一个符号："-" → "-"；"3." → "4."
    private static func nextListMarker(after marker: String) -> String {
        let token = marker.trimmingCharacters(in: .whitespaces)
        if token == "-" || token == "*" || token == "+" { return "- " }
        let numeric = token.hasSuffix(".") ? String(token.dropLast()) : token
        if !numeric.isEmpty, numeric.allSatisfy(\.isNumber), let n = Int(numeric) {
            return "\(n + 1). "
        }
        return "- "
    }

    /// 光标所在段落第一个字符的属性（空文档返回 nil）
    private func currentParagraphAttributes() -> [NSAttributedString.Key: Any]? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let s = storage.string as NSString
        let sel = selectedRange()
        let para = s.paragraphRange(for: NSRange(location: min(sel.location, s.length), length: 0))
        guard para.length > 0 else { return nil }
        return storage.attributes(at: para.location, effectiveRange: nil)
    }

    /// 光标移动后同步 typingAttributes：从标题行挪到正文行接着打字，不该继续带标题样式。
    /// （NSTextView 默认用插入点前一字符的属性；段落开头会取到上一段，这里显式纠正。）
    /// 由 Coordinator 的 textViewDidChangeSelection 调起 —— AppKit 没有可覆写的
    /// didChangeSelection，选区的变化只能从代理回调里拿到。
    func syncTypingAttributesFromCaret() {
        // 光标所在段落的字号可能变了，立刻按新字体重画插入点，
        // 否则要等下一次闪烁周期才更新（defer 覆盖下面所有提前返回的路径）。
        defer { updateInsertionPointStateAndRestartTimer(true) }
        // 光标没动时，保留用户刚通过工具栏打开的行内样式（见 performInlineStyle）。
        defer { if let p = validPendingInlineTyping() { typingAttributes = p } }
        guard !isInsertingNewline else { return }
        guard let storage = textStorage else { return }
        if storage.length == 0 {
            typingAttributes = EditorStyle.defaultTyping
            return
        }
        let sel = selectedRange()
        guard sel.length == 0 else { return }
        let s = storage.string as NSString
        let para = s.paragraphRange(for: NSRange(location: min(sel.location, s.length), length: 0))
        guard para.length > 0 else {
            typingAttributes = EditorStyle.defaultTyping
            return
        }
        let loc = min(max(sel.location, 0), NSMaxRange(para) - 1)
        // 光标在段落最前：段落级属性取自本段，行内属性（字体/颜色）也取本段第一个字符，
        // 而不是上一段结尾——这是「换行后继续写保持同样模式」与「挪动光标模式正确」的平衡点。
        var attrs = storage.attributes(at: para.location, effectiveRange: nil)
        if loc > para.location {
            let before = storage.attributes(at: loc - 1, effectiveRange: nil)
            for key in [NSAttributedString.Key.font, .foregroundColor, .backgroundColor,
                        .underlineStyle, .strikethroughStyle, .link,
                        .mdInlineCode, .mdTextColor, .mdHighlight] {
                if let v = before[key] { attrs[key] = v } else { attrs.removeValue(forKey: key) }
            }
        }
        // 双链 / 任务框是「一整段语法」的属性，绝不能继承到接下来敲的字上，
        // 否则在链接后面打字会静默生成新的 [[...]]；整行快照同理。
        attrs.removeValue(forKey: .mdWikiLink)
        attrs.removeValue(forKey: .mdTaskBox)
        for key in Self.lineSnapshotKeys { attrs.removeValue(forKey: key) }
        typingAttributes = attrs
    }

    /// 输入 "# " / "- " / "> " / "1. " / "``` " 后立刻转成对应块级样式
    func applyInputRules() {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        guard sel.length == 0, sel.location >= 1 else { return }
        let s = storage.string as NSString
        guard sel.location <= s.length else { return }
        let paraStart = s.paragraphRange(for: NSRange(location: sel.location, length: 0)).location
        guard sel.location > paraStart else { return }

        let prefix = s.substring(with: NSRange(location: paraStart, length: sel.location - paraStart))
        guard prefix.hasSuffix(" ") else { return }
        let marker = String(prefix.dropLast())
        guard !marker.isEmpty else { return }

        var style: BlockStyle?
        var list = false
        var ordered = false

        if marker.allSatisfy({ $0 == "#" }), (1...6).contains(marker.count) {
            style = .heading(marker.count)
        } else if marker == ">" {
            style = .quote
        } else if marker == "```" || marker == "~~~" {
            style = .code
        } else if marker == "-" || marker == "*" || marker == "+" {
            list = true
        } else {
            let numeric = marker.hasSuffix(".") ? String(marker.dropLast()) : marker
            if !numeric.isEmpty, numeric.allSatisfy(\.isNumber), marker.hasSuffix(".") || !marker.contains(".") {
                list = true
                ordered = marker.hasSuffix(".")
            }
        }

        guard style != nil || list else { return }

        let markerRange = NSRange(location: paraStart, length: (marker as NSString).length + 1)
        if shouldChangeText(in: markerRange, replacementString: "") {
            storage.deleteCharacters(in: markerRange)
            didChangeText()
        }
        setSelectedRange(NSRange(location: paraStart, length: 0))

        if let style {
            applyBlockStyle(style)
        } else {
            makeList(ordered: ordered)
        }
        setSelectedRange(NSRange(location: paraStart, length: 0))
    }

    // MARK: ⌘+点击 Obsidian 交互 / 单击任务框 / 双击图片 → 回到图表编辑

    /// 把鼠标事件换算成 storage 里的字符下标（已夹在合法范围内）
    private func hitCharacterIndex(for event: NSEvent) -> Int? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        return min(max(index, 0), storage.length - 1)
    }

    override func mouseDown(with event: NSEvent) {
        // 即刻模式是编辑器，直接单击跳转会和选中文本冲突，所以用 ⌘+点击。
        if event.modifierFlags.contains(.command),
           let storage = textStorage, let index = hitCharacterIndex(for: event) {
            let attrs = storage.attributes(at: index, effectiveRange: nil)
            if let wiki = attrs[.mdWikiLink] as? MDWikiLink {
                if wiki.embedded { onEmbedActivated?(wiki) } else { onWikiLinkActivated?(wiki) }
                return
            }
            if let id = attrs[.mdCalloutID] as? Int,
               let fold = attrs[.mdCalloutFold] as? String, !fold.isEmpty {
                onCalloutToggle?(id)
                return
            }
        }

        // 单击任务框直接勾选 / 取消。只有点在 `[ ]` / `[x]` 这 3 个字符上才触发，
        // 点在任务文字上仍是正常的光标定位；不要求 ⌘，与 Typora / Obsidian 一致。
        if !event.modifierFlags.contains(.command), event.clickCount == 1,
           let storage = textStorage, let index = hitCharacterIndex(for: event),
           let range = TaskBoxToggle.boxRange(in: storage, at: index) {
            let current = (storage.string as NSString).substring(with: range)
            // 先让 AppKit 完成窗口激活 / first responder / 选区定位，
            // 再替换字符；直接 return 跳过 super 会让首次点击拿不到焦点。
            super.mouseDown(with: event)
            if let next = TaskBoxToggle.toggled(current) {
                toggleTaskBox(in: range, to: next)
            }
            return
        }

        super.mouseDown(with: event)
        guard event.clickCount == 2, let storage = textStorage,
              let index = hitCharacterIndex(for: event) else { return }
        if let attachment = storage.attribute(.attachment, at: index,
                                              effectiveRange: nil) as? MDImageAttachment {
            onImageDoubleClick?(attachment)
        }
    }

    /// 勾选状态写回 storage：文字变了，序列化器以当前文字为准输出 `[ ]` / `[x]`，
    /// 不会被解析时缓存的旧标记盖掉。走 shouldChangeTextIn / didChangeText 以支持 ⌘Z。
    func toggleTaskBox(in range: NSRange, to text: String) {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length,
              shouldChangeText(in: range, replacementString: text) else { return }
        let attrs = storage.attributes(at: range.location, effectiveRange: nil)
        storage.replaceCharacters(in: range, with: text)
        let newRange = NSRange(location: range.location, length: (text as NSString).length)
        storage.addAttributes(attrs, range: newRange)
        storage.addAttribute(.mdTaskBox, value: text, range: newRange)
        didChangeText()
        reapplyFoldVisuals()
    }

    // MARK: Callout 折叠（纯视觉，storage 不变）

    func toggleCallout(id: Int) {
        if foldedCalloutIDs.contains(id) { foldedCalloutIDs.remove(id) }
        else { foldedCalloutIDs.insert(id) }
        reapplyFoldVisuals()
    }

    /// 换文档 / 导出前调用：折叠状态全部清空
    func expandAllCallouts() {
        foldedCalloutIDs.removeAll()
        reapplyFoldVisuals()
    }

    /// 用 NSLayoutManager 的临时属性隐藏折叠行：
    /// 不替换字符、不写 storage，所以 Markdown 序列化永远是完整原文，
    /// 也不会在 undo 栈里留下「折叠」这一步。
    func reapplyFoldVisuals() {
        guard let layout = layoutManager, let storage = textStorage else { return }
        for r in appliedFoldRanges where NSMaxRange(r) <= storage.length {
            let glyphs = layout.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            for g in glyphs.location..<NSMaxRange(glyphs) where g < layout.numberOfGlyphs {
                layout.setNotShownAttribute(false, forGlyphAt: g)
            }
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: r)
            layout.removeTemporaryAttribute(.font, forCharacterRange: r)
            layout.removeTemporaryAttribute(Self.foldedAttribute, forCharacterRange: r)
        }
        appliedFoldRanges.removeAll()
        guard !foldedCalloutIDs.isEmpty, storage.length > 0 else {
            needsDisplay = true
            return
        }

        for r in CalloutFolding.hiddenRanges(in: storage, foldedIDs: foldedCalloutIDs) {
            layout.addTemporaryAttributes([
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 1),
                Self.foldedAttribute: true,
            ], forCharacterRange: r)
            appliedFoldRanges.append(r)
            let glyphs = layout.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            for g in glyphs.location..<NSMaxRange(glyphs) where g < layout.numberOfGlyphs {
                layout.setNotShownAttribute(true, forGlyphAt: g)
            }
        }
        needsDisplay = true
    }

    // MARK: 拖入图片

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let images = urls.filter { Self.isImageFile($0) }
            if !images.isEmpty {
                onDropImageFiles?(images)
                return true
            }
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !images.isEmpty {
            onDropImages?(images)
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: 粘贴图片

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let images = urls.filter { Self.isImageFile($0) }
            if !images.isEmpty {
                onDropImageFiles?(images)
                return
            }
        }
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !images.isEmpty {
            onDropImages?(images)
            return
        }
        super.paste(sender)
    }

    private static func isImageFile(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff"].contains(url.pathExtension.lowercased())
    }
}

// MARK: - 页面容器（白纸）、居中裁剪视图、装配工厂
//
// 已移至 Editor/ScrollView.swift（不依赖 SwiftUI，冒烟测试可直接编译验证）。

// MARK: - 附件查找

extension NSAttributedString {
    /// 找到某个附件对象在文档里的字符范围
    func rangeOfAttachment(_ attachment: NSTextAttachment) -> NSRange? {
        var found: NSRange?
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length), options: []) { value, range, stop in
            if let value = value as? NSTextAttachment, value === attachment {
                found = range
                stop.pointee = true
            }
        }
        return found
    }
}
