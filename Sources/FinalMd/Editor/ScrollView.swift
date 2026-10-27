//
//  ScrollView.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  编辑器滚动容器：NSScrollView 装配 + 白纸页面视图 + 居中裁剪视图。
//  故意不 import SwiftUI —— 这样冒烟测试可以直接编译这些真实类，
//  用可执行断言验证缩放 / 居中 / 横向滚动行为，而不是靠肉眼。
//

import AppKit

// MARK: - 装配工厂

@MainActor
enum EditorScrollFactory {

    /// 最小页边距（页面两侧留白）
    static let outerPadding: CGFloat = 24

    /// 装配 编辑器滚动视图，返回 (scroll, page)。
    /// EditorView(NSViewRepresentable) 与冒烟测试共用同一份装配逻辑。
    static func make(textView: NSTextView) -> (scroll: NSScrollView, page: EditorPageView) {
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
        return (scroll, page)
    }
}

// MARK: - 页面容器（白纸）

final class EditorPageView: NSView {

    let textView: NSTextView
    private var pageX: CGFloat = EditorScrollFactory.outerPadding
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

    /// 文档宽度 = 页面宽 + 两侧对称留白；页面永远从 outerPadding 处开始画。
    /// （此前 pageX 会根据可视宽度额外居中，而文档宽度却只包到页面边缘，
    ///  两者不一致导致页面被画到文档视图边界之外、整体偏右且缩放后错位。）
    override func layout() {
        super.layout()

        let inset = DocTheme.pagePadding
        let outer = EditorScrollFactory.outerPadding
        // 关键：用 clip view 的 frame（屏幕可视宽度）而不是 bounds。
        // bounds 会随缩放变化（bounds = frame / magnification），用它算页宽会导致
        // 缩放时页面跟着变窄、文字重排，看起来就像完全没缩放。
        let visible = (superview as? NSClipView)?.frame.width ?? bounds.width
        let available = max(visible - outer * 2, 360)
        pageWidth = min(available, DocTheme.pageMaxWidth)
        pageX = outer

        let textW = max(pageWidth - inset.left - inset.right, 200)
        let textX = pageX + inset.left
        textView.frame = NSRect(x: textX, y: inset.top, width: textW, height: 40)

        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            textView.frame.size.height = max(used + 24, 40)
        }

        let needed = inset.top + textView.frame.height + inset.bottom
        // bounds.height 已是文档坐标系里的可视高度（随缩放变大/变小），
        // 缩小时把文档撑到可视高，保证工作区背景铺满。
        let visibleH = (superview as? NSClipView)?.bounds.height ?? 0
        var f = frame
        f.size.height = max(needed, visibleH)
        f.size.width = pageWidth + outer * 2
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
