//
//  AppDelegate.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  窗口生命周期与未保存改动时的退出确认。
//
//  历史 bug：确认框原先用挂在 ContentView 上的 SwiftUI sheet。用户关掉窗口后
//  sheet 再也无法呈现，applicationShouldTerminate 却已经返回 .terminateLater，
//  于是永远等不到 reply —— Dock 右键「退出」没反应、点图标也回不到前台。
//  现在改成不依赖任何窗口的应用级 NSAlert，并显式处理关窗与重新打开。
//

import AppKit

/// SwiftUI 的 `openWindow` 只能在 View 里通过 @Environment 取到，
/// AppDelegate 需要在「点 Dock 图标」时用它，所以由 ContentView 注册进来。
final class WindowBridge {
    static let shared = WindowBridge()
    var reopen: (() -> Void)?
    private init() {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // 启动时再应用一次外观：AppModel 初始化时 NSApp 可能还没就绪
        AppModel.shared?.applyAppearance()
    }

    /// 关掉最后一个窗口**不退出**：文档仍在 AppModel（全局单例）里，
    /// 让 app 留在 Dock，点图标才能把窗口叫回来。
    /// 配套地，Info.plist 关掉了 NSSupportsAutomaticTermination ——
    /// 否则系统会在无窗口时把进程悄悄终止，未保存内容会丢。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 没有可见窗口时点 Dock 图标：重建（或唤醒）主窗口并激活 app。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let reopen = WindowBridge.shared.reopen {
                reopen()
            } else if let window = sender.windows.first(where: { $0.canBecomeKey }) {
                // 兜底：SwiftUI 有时只是把窗口藏起来，并没有销毁
                window.makeKeyAndOrderFront(nil)
            }
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = AppModel.shared, model.isDirty else {
            return .terminateNow
        }

        // NSAlert 是应用级模态窗口，即使主窗口已关闭也能显示。
        // 保存动作要走异步的 NSSavePanel，只有这一支用 .terminateLater。
        let alert = NSAlert()
        alert.messageText = model.l10n.t("dlg.close.title")
        alert.informativeText = model.l10n.t("dlg.close.text", ["name": model.docName])
        alert.addButton(withTitle: model.l10n.t("common.save"))
        alert.addButton(withTitle: model.l10n.t("common.dontSave"))
        alert.addButton(withTitle: model.l10n.t("common.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                let ok = await model.save(asNew: false)
                NSApp.reply(toApplicationShouldTerminate: ok)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
