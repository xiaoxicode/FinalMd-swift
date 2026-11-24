//
//  EditorFocus.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  即刻 / 传统两个 NSTextView 常驻同一窗口，切换模式时由这里统一移交键盘焦点。
//  刻意不 import SwiftUI，scripts/smoke.swift 可以直接编译验证其中的判定逻辑。
//
//  ⚠️ 不要直接调用 NSTextView.resignFirstResponder()。
//  NSViewRepresentable 的 updateNSView 运行在 SwiftUI 的 layout / display cycle 里，
//  此刻两个 scroll view 的 hidden 状态正在被改写、视图树尚未稳定。直接 resign
//  会让 AppKit 走 -[NSWindow _newFirstResponderAfterResigning] 去「猜」下一个
//  响应者；找不到合法候选时抛 NSException，进程以 SIGABRT 退出（启动首帧尤其容易踩中）。
//  正确做法是把明确的目标交给 NSWindow.makeFirstResponder(_:)，
//  由窗口一次性完成「旧响应者让位 + 新响应者接任」，不走候选查找路径。
//

import AppKit

enum EditorFocus {

    /// 视图本身或任一祖先被隐藏 / 全透明时，不能接收键盘焦点。
    /// 自己遍历而不依赖 hiddenOrHasHiddenAncestor：该属性在不同 SDK 上导入名不一致。
    static func isEffectivelyHidden(_ view: NSView) -> Bool {
        var node: NSView? = view
        while let current = node {
            if current.isHidden || current.alphaValue < 0.01 { return true }
            node = current.superview
        }
        return false
    }

    /// 当前焦点是否允许被编辑器接管。
    ///
    /// AppKit 给查找栏 / 表单 / AI 输入框用的是 field editor，它同样是
    /// NSTextView，不能只按类型放行。这里只允许：
    ///  · 窗口尚未指定响应者（或已被 AppKit 自动收回到窗口本身）
    ///  · 另一个编辑器视图（模式切换前的那一侧）
    ///  · 按钮 / 分段控件等非文本控件 —— 用户点工具栏切模式后应能直接打字
    /// 其余文本输入视图（查找栏、对话框、输入框）的焦点一律不抢。
    static func mayTakeFocus(from responder: NSResponder?, otherEditor: NSView? = nil) -> Bool {
        guard let responder else { return true }
        if responder is NSWindow { return true }
        if let textView = responder as? NSTextView {
            return textView === otherEditor
        }
        return true
    }

    /// 同步执行一次焦点移交；任一前置条件不满足时安静返回 false。
    /// 供测试直接调用，产品代码请用 scheduleHandoff(to:from:)。
    /// `otherEditor` 是切换前的那一侧编辑器，只有它的焦点允许被接管。
    @discardableResult
    static func handoff(to target: NSView?, from otherEditor: NSView? = nil) -> Bool {
        guard let target,
              let window = target.window,
              (window.firstResponder as AnyObject?) !== (target as AnyObject?),
              target.acceptsFirstResponder,
              !isEffectivelyHidden(target),
              mayTakeFocus(from: window.firstResponder, otherEditor: otherEditor) else { return false }
        return window.makeFirstResponder(target)
    }

    /// SwiftUI 的 updateNSView 处在布局周期中，不能同步改第一响应者。
    /// 推到下一个主队列回合：那时显隐已经落地、AppKit 也已完成隐藏视图的
    /// 自动让位，窗口能明确知道新的第一响应者是谁。
    static func scheduleHandoff(to target: NSView?, from otherEditor: NSView? = nil) {
        guard let target else { return }
        DispatchQueue.main.async { [weak target, weak otherEditor] in
            guard let target else { return }
            _ = handoff(to: target, from: otherEditor)
        }
    }
}
