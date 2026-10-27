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
        textView.delegate = context.coordinator

        let page = EditorPageView(textView: textView)
        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        scroll.backgroundColor = DocTheme.workspaceBackground
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.6
        scroll.maxMagnification = 2.0
        scroll.autohidesScrollers = true
        scroll.documentView = page
        scroll.contentView.autoresizesSubviews = true

        context.coordinator.textView = textView
        context.coordinator.pageView = page

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

        model.textView = textView
        model.loadInitialContentIfNeeded()
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let target = model.zoom
        if abs(scrollView.magnification - target) > 0.001 {
            scrollView.magnification = target
        }
        context.coordinator.pageView?.needsLayout = true
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        weak var textView: NSTextView?
        weak var pageView: EditorPageView?

        init(model: AppModel) {
            self.model = model
            super.init()
        }

        func textDidChange(_ notification: Notification) {
            model.markDirty()
            model.refreshAll()
            pageView?.needsLayout = true
            pageView?.layout()
            // Markdown 快捷输入规则：输入 "# " 立刻变标题
            (textView as? MDEditorTextView)?.applyInputRules()
            model.refreshToolbar()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            model.refreshToolbar()
        }
    }
}

// MARK: - 文本视图

final class MDEditorTextView: NSTextView {

    var onImageDoubleClick: ((MDImageAttachment) -> Void)?
    var onDropImageFiles: (([URL]) -> Void)?
    var onDropImages: (([NSImage]) -> Void)?

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
        typingAttributes = [
            .font: DocTheme.bodyFont,
            .foregroundColor: DocTheme.text,
            .paragraphStyle: DocTheme.paragraphStyle(for: .paragraph),
            .mdBlockType: MDBlockType.paragraph.rawValue,
        ]

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = []
        textContainerInset = NSSize(width: 0, height: 0)
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.lineFragmentPadding = 0
    }

    // MARK: Markdown 快捷输入规则

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

    // MARK: 双击图片 → 回到图表编辑

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2, let storage = textStorage, storage.length > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        var index = characterIndexForInsertion(at: point)
        index = min(max(index, 0), storage.length - 1)
        if let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? MDImageAttachment {
            onImageDoubleClick?(attachment)
        }
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

// MARK: - 页面容器（白纸）

final class EditorPageView: NSView {

    let textView: NSTextView
    private var pageX: CGFloat = 24
    private var pageWidth: CGFloat = DocTheme.pageMaxWidth

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        autoresizingMask = [.width]
        autoresizesSubviews = true
        textView.drawsBackground = false
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()

        let inset = DocTheme.pagePadding
        let outerPadding: CGFloat = 24
        let available = max(bounds.width - outerPadding * 2, 360)
        pageWidth = min(available, DocTheme.pageMaxWidth)
        pageX = max((bounds.width - pageWidth) / 2, 0)

        let textW = max(pageWidth - inset.left - inset.right, 200)
        let textX = pageX + inset.left
        textView.frame = NSRect(x: textX, y: inset.top, width: textW, height: 40)

        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            textView.frame.size.height = max(used + 24, 40)
        }

        let needed = inset.top + textView.frame.height + inset.bottom
        let visible = (superview as? NSClipView)?.bounds.height ?? 0
        var f = frame
        f.size.height = max(needed, visible)
        f.size.width = max(bounds.width, pageWidth + outerPadding)
        if f != frame { frame = f }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        DocTheme.workspaceBackground.setFill()
        bounds.fill()

        let pageRect = NSRect(x: pageX, y: 0, width: pageWidth, height: bounds.height)
        NSColor.white.setFill()
        pageRect.fill()

        DocTheme.borderSoft.setStroke()
        let path = NSBezierPath(rect: pageRect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }
}

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
