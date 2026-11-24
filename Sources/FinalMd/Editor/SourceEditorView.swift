//
//  SourceEditorView.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  把传统模式的源码文本视图包进 SwiftUI。它与 EditorView 同时常驻窗口，
//  切换模式时只是 isHidden 互换 —— 两边的内容、光标、undo 状态都不会被重建。
//

import SwiftUI
import AppKit

struct SourceEditorView: NSViewRepresentable {

    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> MDEditorScrollView {
        let textView = MDSourceTextView()
        textView.configure()
        textView.delegate = context.coordinator

        let (scroll, container) = SourceScrollFactory.make(textView: textView)
        // 首帧就把显隐设对：ZStack 里源码视图是后添加的上层视图，
        // 若等 updateNSView 才隐藏，AppKit 启动时可能先把焦点交给它。
        scroll.isHidden = model.editorMode != .classic
        context.coordinator.appliedHidden = model.editorMode == .classic
        context.coordinator.textView = textView
        context.coordinator.container = container
        context.coordinator.observe(scrollView: scroll)
        scroll.onWheelZoom = { [weak coordinator = context.coordinator] value in
            guard let coordinator else { return }
            coordinator.appliedZoom = value
            coordinator.model.setZoom(value)
        }

        model.sourceTextView = textView
        model.editorViewDidBecomeReady(.source)
        return scroll
    }

    func updateNSView(_ scrollView: MDEditorScrollView, context: Context) {
        let coord = context.coordinator
        let visible = model.editorMode == .classic

        // 只在显隐真的变化时写 isHidden。
        // 这里曾对隐藏侧调用 resignFirstResponder()：它运行在 SwiftUI 的
        // layout / display cycle 中，AppKit 会去猜下一个响应者并抛 NSException
        // （崩溃栈：-[NSWindow _newFirstResponderAfterResigning] → SIGABRT）。
        // 现在焦点只由可见侧通过 NSWindow.makeFirstResponder 一次性接管。
        if coord.appliedHidden != visible {
            coord.appliedHidden = visible
            scrollView.isHidden = !visible
        }

        if coord.appliedMode != model.editorMode {
            coord.appliedMode = model.editorMode
            if visible {
                EditorFocus.scheduleHandoff(to: coord.textView, from: model.richTextView)
            }
        }

        if abs(model.zoom - coord.appliedZoom) > 0.001 {
            scrollView.magnification = model.zoom
            coord.appliedZoom = model.zoom
        }
        coord.container?.needsLayout = true
        coord.container?.layout()
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        weak var textView: MDSourceTextView?
        weak var container: SourceContainerView?
        var appliedZoom: Double = 1
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

        @objc @MainActor private func magnifyDidEnd(_ note: Notification) {
            guard let scrollView = note.object as? NSScrollView else { return }
            appliedZoom = scrollView.magnification
            model.setZoom(scrollView.magnification)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            model.noteEdited(in: tv)
            model.markDirty()
            model.refreshAll()
            container?.needsLayout = true
            container?.layout()
            tv.applySyntaxHighlight()
            // 源码视图永远保持同一套等宽纯文本属性，不继承任何排版样式
            tv.resetTypingAttributes()
        }
    }
}
