//
//  FinalMdApp.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  应用入口。对应 Electron 版的 main.js：创建窗口、构建菜单、接入生命周期。
//

import SwiftUI

@main
struct FinalMdApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var l10n: Localizer
    @StateObject private var model: AppModel
    @StateObject private var ai: AIController

    init() {
        let localizer = Localizer()
        _l10n = StateObject(wrappedValue: localizer)
        _model = StateObject(wrappedValue: AppModel(l10n: localizer))
        _ai = StateObject(wrappedValue: AIController(l10n: localizer))
    }

    var body: some Scene {
        // 显式 id：关掉窗口后点 Dock 图标，AppDelegate 用 openWindow(id: "main")
        // 把同一个窗口重新唤回（见 WindowBridge）。
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(l10n)
                .environmentObject(ai)
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            AppCommands(model: model, l10n: l10n, ai: ai)
        }
    }
}
