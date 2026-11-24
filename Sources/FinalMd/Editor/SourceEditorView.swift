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

        scrollView.isHidden = !visible
        if scrollView.isHidden { _ = context.coordinator.textView?.resignFirstResponder() }

        if coord.appliedMode != model.editorMode {
            coord.appliedMode = model.editorMode
            if visible {
                // 显隐生效之后再把键盘焦点交给源码视图，否则 ⌘B / 打字
                // 仍会落到已经藏起来的即刻视图上。
                DispatchQueue.main.async { [weak coord] in
                    guard let tv = coord?.textView, let window = tv.window else { return }
                    window.makeFirstResponder(tv)
                }
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
