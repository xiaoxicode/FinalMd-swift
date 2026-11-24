//
//  SourceTextView.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  传统模式：像用文本编辑器打开 .md 一样，直接看到并修改 Markdown 原文。
//  这里刻意只用 AppKit，不 import SwiftUI —— 冒烟测试可以直接编译真实类。
//
//  三个「像文本编辑器」的关键点：
//   1. 纯文本（isRichText = false），关掉所有智能替换 / 自动链接 / 拼写检查；
//   2. 等宽字体、按字符折行、段落间不留排版空白；
//   3. 语法着色只写在 NSLayoutManager 的**临时属性**上 —— 不碰 NSTextStorage，
//      因此不会污染存盘内容、不会进 undo 栈、也不会变成真的富文本。
//

import AppKit

// MARK: - 源码文本视图

final class MDSourceTextView: NSTextView {

    func configure() {
        isRichText = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
        importsGraphics = false
        allowsImageEditing = false

        // 文本编辑器不会偷偷改写你敲进去的字符
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        usesFindBar = false

        drawsBackground = false        // 背景由 SourceContainerView 铺，颜色随外观走
        font = DocTheme.monospacedFont(size: 13.5)
        textColor = DocTheme.text
        insertionPointColor = DocTheme.text
        selectedTextAttributes = [
            .backgroundColor: DocTheme.accentSoft,
            .foregroundColor: DocTheme.text,
        ]
        typingAttributes = EditorModeBridge.plainAttributes

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = []
        textContainerInset = NSSize(width: 20, height: 20)
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.lineFragmentPadding = 0
    }

    /// 文本被替换（新建 / 打开 / 模式切换）后，输入属性必须回到纯文本基线，
    /// 否则 NSTextView 会把上一段的字体颜色继承下来。
    func resetTypingAttributes() {
        typingAttributes = EditorModeBridge.plainAttributes
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        insertionPointColor = DocTheme.text
        // 临时属性里存的是动态色，重绘即可换色；顺手重算一次更保险
        applySyntaxHighlight()
        needsDisplay = true
    }

    // MARK: 语法着色（临时属性）

    /// 重新给全文上色。只改 layout manager 的临时属性，
    /// NSTextStorage 里的字符与属性一个字节都不动。
    func applySyntaxHighlight() {
        guard let layoutManager, let storage = textStorage else { return }
        let length = storage.length
        // 空文档（新建、清空）时不要拿零长度范围去动 layout manager，
        // AppKit 会在没有 glyph 的情况下触发越界断言。
        guard length > 0 else { return }
        let full = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)

        let s = storage.string as NSString
        let inlineTokens = length <= 300_000      // 超大文档只做行首着色，保证输入不卡
        var inFence = false
        var loc = 0

        while loc < length {
            let lineRange = s.lineRange(for: NSRange(location: loc, length: 0))
            guard lineRange.length > 0 else { break }
            loc = NSMaxRange(lineRange)

            var bodyLength = lineRange.length
            if bodyLength > 0, s.character(at: NSMaxRange(lineRange) - 1) == 0x0A {
                bodyLength -= 1
            }
            guard bodyLength > 0 else { continue }
            let bodyRange = NSRange(location: lineRange.location, length: bodyLength)
            let line = s.substring(with: bodyRange)

            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            let leading = line.count - trimmed.count
            let start = bodyRange.location + leading
            let content = String(trimmed)

            // 围栏代码块：整行用代码色，块内文字不上色， fencing 切换状态
            if content.hasPrefix("```") || content.hasPrefix("~~~") {
                color(NSRange(location: start, length: bodyLength - leading), with: DocTheme.inlineCodeText)
                inFence.toggle()
                continue
            }
            if inFence { continue }

            if content.hasPrefix("#") {
                let hashes = content.prefix(while: { $0 == "#" }).count
                if (1...6).contains(hashes) {
                    color(NSRange(location: start, length: hashes), with: DocTheme.accent)
                    // 标题正文也用强调色，一眼能看出层级
                    let rest = bodyLength - leading - hashes
                    if rest > 0 {
                        color(NSRange(location: start + hashes, length: rest), with: DocTheme.accent)
                    }
                }
            } else if content.hasPrefix(">") {
                color(NSRange(location: start, length: 1), with: DocTheme.textDim)
            } else if Self.isListMarker(content) {
                color(NSRange(location: start, length: Self.markerLength(content)), with: DocTheme.accent)
            } else if Self.isRule(content) || content.hasPrefix("|") {
                color(bodyRange, with: DocTheme.textDim)
            }

            guard inlineTokens else { continue }
            highlightInline(in: bodyRange, storage: s)
        }
    }

    private func color(_ range: NSRange, with value: NSColor) {
        guard range.length > 0, range.location >= 0,
              NSMaxRange(range) <= (textStorage?.length ?? 0) else { return }
        layoutManager?.addTemporaryAttributes([.foregroundColor: value], forCharacterRange: range)
    }

    private static func isListMarker(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { return true }
        guard let dot = line.firstIndex(of: "."), dot != line.startIndex else { return false }
        let number = line[..<dot]
        return !number.isEmpty && number.allSatisfy(\.isNumber)
    }

    private static func markerLength(_ line: String) -> Int {
        if let sp = line.firstIndex(of: " ") { return line.distance(from: line.startIndex, to: sp) + 1 }
        return line.count
    }

    private static func isRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3 else { return false }
        return (t.allSatisfy { $0 == "-" } || t.allSatisfy { $0 == "*" } || t.allSatisfy { $0 == "_" })
    }

    /// 行内标记：`**粗体**` / `` `代码` `` / 链接里的 URL。
    private func highlightInline(in range: NSRange, storage s: NSString) {
        colorPaired("**", in: range, storage: s, with: DocTheme.accent,
                    contentOnly: true)
        colorPaired("`", in: range, storage: s, with: DocTheme.inlineCodeText,
                    contentOnly: false)

        // [文字](https://…) —— 只给括号里的地址换个弱色
        var search = range
        while search.length > 0 {
            let close = s.range(of: "](", options: [], range: search)
            if close.location == NSNotFound { break }
            let urlStart = NSMaxRange(close)
            guard urlStart < NSMaxRange(range) else { break }
            let rest = NSRange(location: urlStart, length: NSMaxRange(range) - urlStart)
            let end = s.range(of: ")", options: [], range: rest)
            if end.location != NSNotFound, end.location > urlStart {
                color(NSRange(location: urlStart, length: end.location - urlStart), with: DocTheme.textDim)
                search = NSRange(location: NSMaxRange(end), length: NSMaxRange(range) - NSMaxRange(end))
            } else {
                break
            }
        }
    }

    private func colorPaired(_ token: String, in range: NSRange, storage s: NSString,
                             with value: NSColor, contentOnly: Bool) {
        var search = range
        var open: NSRange?
        while search.length > 0 {
            let hit = s.range(of: token, options: [], range: search)
            if hit.location == NSNotFound { break }
            if let first = open {
                let from = contentOnly ? NSMaxRange(first) : first.location
                let to = contentOnly ? hit.location : NSMaxRange(hit)
                color(NSRange(location: from, length: max(to - from, 0)), with: value)
                open = nil
            } else {
                open = hit
            }
            let next = NSMaxRange(hit)
            guard next < NSMaxRange(range) else { break }
            search = NSRange(location: next, length: NSMaxRange(range) - next)
        }
    }
}

// MARK: - 源码滚动容器（无纸张、全宽）

/// 传统模式不像即刻模式那样画「一张白纸」：整片工作区就是文档底色，
/// 文字从左边缘按等宽字体铺开，跟系统文本编辑器一致。
final class SourceContainerView: NSView {

    let textView: NSTextView

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        autoresizingMask = []
        autoresizesSubviews = false
        textView.drawsBackground = false
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let visibleW = (superview as? NSClipView)?.frame.width ?? bounds.width
        let width = max(visibleW, 320)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 40)

        if let lm = textView.layoutManager, let tc = textView.textContainer {
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc).height
            textView.frame.size.height = max(used + 40, 40)
        }
        let visibleH = (superview as? NSClipView)?.bounds.height ?? 0
        let height = max(textView.frame.height, visibleH)
        let f = NSRect(x: 0, y: 0, width: width, height: height)
        if f != frame { frame = f }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        DocTheme.pageBackground.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        textView.needsDisplay = true
    }
}

/// 传统模式的滚动视图装配（与即刻模式共用 ⌘/⌃ + 滚轮缩放逻辑）
@MainActor
enum SourceScrollFactory {
    static func make(textView: NSTextView) -> (scroll: MDEditorScrollView, container: SourceContainerView) {
        let container = SourceContainerView(textView: textView)
        let scroll = MDEditorScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        scroll.backgroundColor = DocTheme.pageBackground
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.6
        scroll.maxMagnification = 2.0
        scroll.autohidesScrollers = true

        let clip = NSClipView(frame: .zero)
        clip.drawsBackground = true
        clip.backgroundColor = DocTheme.pageBackground
        clip.autoresizesSubviews = false
        scroll.contentView = clip
        scroll.documentView = container
        return (scroll, container)
    }
}
