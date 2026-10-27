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

    init() {
        let localizer = Localizer()
        _l10n = StateObject(wrappedValue: localizer)
        _model = StateObject(wrappedValue: AppModel(l10n: localizer))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(l10n)
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            AppCommands(model: model, l10n: l10n)
        }
    }
}
