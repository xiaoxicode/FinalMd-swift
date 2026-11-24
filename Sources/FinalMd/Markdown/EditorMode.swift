//
//  EditorMode.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  两种编辑模式：
//   · 即刻模式（instant）：所见即所得，像 WPS / Word 那样排版后写作；
//   · 传统模式（classic）：直接显示并编辑 Markdown 原文，像用文本编辑器打开 .md。
//
//  这里同时放「两种视图之间搬运内容」的纯 AppKit 逻辑，刻意不 import SwiftUI，
//  这样 scripts/smoke.swift 可以直接编译、断言往返转换的正确性。
//

import AppKit

// MARK: - 模式

enum EditorMode: String, CaseIterable, Identifiable {
    case instant
    case classic

    var id: String { rawValue }

    /// 名称文案 key
    var labelKey: String { "mode.\(rawValue)" }
    /// 说明文案 key（功能区提示 / 状态栏气泡）
    var hintKey: String { "mode.\(rawValue).hint" }

    /// 功能区分段控件上的图标
    var symbol: String {
        switch self {
        case .instant: return "doc.richtext"
        case .classic: return "chevron.left.forwardslash.chevron.right"
        }
    }

    static let storageKey = "finalmd.editorMode"
}

/// 哪一侧的内容是「最新」的。nil 表示两侧刚刚同步过、内容等价。
enum EditorSide {
    case rich
    case source
}

// MARK: - 内容桥接

enum EditorModeBridge {

    /// 即刻 → 传统：把排版后的富文本序列化成 Markdown 原文。
    static func sourceText(from storage: NSAttributedString) -> String {
        MarkdownSerializer.markdown(from: storage)
    }

    /// 传统 → 即刻：把 Markdown 原文解析成排版后的富文本。
    static func richText(from source: String) -> NSAttributedString {
        MarkdownParser.parse(source)
    }

    /// 传统模式下所有文字共用的显示属性。
    /// 颜色用 DocTheme 的动态色，浅色 / 深色切换时无需重建文档。
    static var plainAttributes: [NSAttributedString.Key: Any] {
        [
            .font: DocTheme.monospacedFont(size: 13.5),
            .foregroundColor: DocTheme.text,
            .paragraphStyle: plainParagraphStyle,
        ]
    }

    /// 源码编辑器的段落样式：等距行、按字符折行、段落间不留额外空白。
    static var plainParagraphStyle: NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.alignment = .natural
        ps.lineBreakMode = .byCharWrapping
        ps.lineHeightMultiple = 1.45
        ps.paragraphSpacing = 0
        ps.paragraphSpacingBefore = 0
        return ps
    }

    /// 把一整份内容装进视图。
    ///
    /// 模式切换不是「用户编辑」：不能进 undo 栈，也不能触发 didChangeText
    /// （否则切换一下就把文档标脏，并让另一侧的代理回调把 authority 改回去）。
    /// 所以这里直接写 NSTextStorage，并临时关掉 undo 注册。
    static func install(_ content: NSAttributedString,
                        in textView: NSTextView,
                        plain: Bool) {
        guard let storage = textView.textStorage else { return }

        let undo = textView.undoManager
        undo?.disableUndoRegistration()
        defer { undo?.enableUndoRegistration() }

        let mutable = NSMutableAttributedString(attributedString: content)
        if plain, mutable.length > 0 {
            // 纯文本视图里不允许出现富文本属性：粘贴/解析带进来的字体、
            // 颜色、附件统统抹平，只保留字符本身。
            mutable.setAttributes(plainAttributes,
                                  range: NSRange(location: 0, length: mutable.length))
        }

        storage.beginEditing()
        storage.setAttributedString(mutable)
        storage.endEditing()

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.typingAttributes = plain ? plainAttributes : defaultRichTyping(from: storage)
    }

    /// 即刻视图载入新文档后的输入属性：取第一段的属性，空文档回落到正文。
    /// 不依赖 TextFormatting.swift，让冒烟测试可以单独编译本文件。
    private static func defaultRichTyping(from storage: NSTextStorage) -> [NSAttributedString.Key: Any] {
        guard storage.length > 0 else { return [:] }
        return storage.attributes(at: 0, effectiveRange: nil)
    }

    /// 传统视图的纯文本内容（保存时逐字节写回磁盘，不做任何规范化）。
    static func plainText(in textView: NSTextView) -> String {
        textView.string
    }

    /// 切换后清掉两侧 undo 栈。
    ///
    /// 两个视图各自维护一份 undo 历史，记录的都是「字符范围」；一旦整篇被
    /// 另一侧的内容替换，旧历史里的范围就不再对应当前文本，撤销会把文档
    /// 撕成两半。宁可让切换成为一次干净的断点，也不要留下错乱的撤销。
    static func resetUndoHistory(_ views: [NSTextView?]) {
        for view in views.compactMap({ $0 }) {
            view.undoManager?.removeAllActions()
        }
    }
}
