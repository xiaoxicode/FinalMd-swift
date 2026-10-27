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
        scroll.hasHorizontalScroller = true      // 放大后要能左右拖动
        scroll.drawsBackground = true
        scroll.backgroundColor = DocTheme.workspaceBackground
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.6
        scroll.maxMagnification = 2.0
        scroll.autohidesScrollers = true

        // 自定义 clip view：文档比可视区窄时居中，比可视区宽时正常横向滚动。
        // autoresizesSubviews 必须关掉，否则缩放时文档视图被一起改尺寸、文字重排，
        // 结果就是「拉了缩放但页面纹丝不动」。
        let clip = CenteringClipView(frame: .zero)
        clip.drawsBackground = true
        clip.backgroundColor = DocTheme.workspaceBackground
        clip.autoresizesSubviews = false
        scroll.contentView = clip
        scroll.documentView = page

        context.coordinator.textView = textView
        context.coordinator.pageView = page
        context.coordinator.observe(scrollView: scroll)

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
        let coord = context.coordinator
        // 只有当 model.zoom 真的变了才往 scroll view 里写。
        // 否则用户手势缩放会在下一次 SwiftUI 刷新时被硬拉回 model.zoom。
        if abs(model.zoom - coord.appliedZoom) > 0.001 {
            scrollView.magnification = model.zoom
            coord.appliedZoom = model.zoom
        }
        coord.pageView?.needsLayout = true
        coord.pageView?.layout()
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        weak var textView: NSTextView?
        weak var pageView: EditorPageView?
        /// 最近一次由代码写进 scroll view 的缩放值，用来区分「模型变了」和「用户捏合了」
        var appliedZoom: Double = 1

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
        // 尺寸完全交给 layout() 计算，不让 AppKit 的 autoresizing 插手
        autoresizingMask = []
        autoresizesSubviews = false
        textView.drawsBackground = false
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()

        let inset = DocTheme.pagePadding
        let outerPadding: CGFloat = 24
        // 关键：用 clip view 的 frame（屏幕可视宽度）而不是 bounds。
        // bounds 会随缩放变化，用它算页宽会导致缩放时页面跟着变窄、文字重排，
        // 看起来就像完全没缩放；而且文档宽度永远不超过可视宽度，横向也就滚不动。
        let visible = (superview as? NSClipView)?.frame.width ?? bounds.width
        let available = max(visible - outerPadding * 2, 360)
        pageWidth = min(available, DocTheme.pageMaxWidth)
        pageX = outerPadding + max((available - pageWidth) / 2, 0)

        let textW = max(pageWidth - inset.left - inset.right, 200)
        let textX = pageX + inset.left
        textView.frame = NSRect(x: textX, y: inset.top, width: textW, height: 40)

        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            textView.frame.size.height = max(used + 24, 40)
        }

        let needed = inset.top + textView.frame.height + inset.bottom
        let visibleH = (superview as? NSClipView)?.bounds.height ?? 0
        var f = frame
        f.size.height = max(needed, visibleH)
        // 文档宽度固定为「页面 + 两侧留白」，缩放时不随之变化：
        // 放大后文档比可视区宽 → 出现横向滚动；缩小时由 CenteringClipView 居中。
        f.size.width = pageWidth + outerPadding * 2
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

// MARK: - 居中的裁剪视图

/// 文档视图比可视区窄时把它水平居中（此时 NSScrollView 默认只能贴在左边），
/// 比可视区宽时交给父类正常滚动 —— 放大后因此能左右拖动。
final class CenteringClipView: NSClipView {

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        let docWidth = doc.frame.width
        if docWidth < rect.width {
            rect.origin.x = (docWidth - rect.width) / 2
        }
        return rect
    }

    /// 窗口尺寸变化时要让页面重新排版（页宽依赖屏幕可视宽度）
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let doc = documentView else { return }
        doc.needsLayout = true
        doc.layout()
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
