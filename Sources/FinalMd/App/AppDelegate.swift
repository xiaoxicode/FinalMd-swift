//
//  AppDelegate.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  未保存改动时的退出确认。对应 Electron 版 main.js 的 win.on('close') +
//  app:confirm-before-close：先弹自定义对话框，用户选「保存 / 不保存 / 取消」再决定。
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = AppModel.shared, model.isDirty else {
            return .terminateNow
        }

        let l10n = model.l10n
        let spec = ConfirmSpec(
            title: l10n.t("dlg.close.title"),
            message: l10n.t("dlg.close.text", ["name": model.docName]),
            buttons: [
                ConfirmButton(id: "save", label: l10n.t("common.save"), style: .primary),
                ConfirmButton(id: "discard", label: l10n.t("common.dontSave"), style: .danger),
                ConfirmButton(id: "cancel", label: l10n.t("common.cancel"), style: .plain),
            ]
        )

        Task { @MainActor in
            let answer = await model.confirm(spec)
            switch answer {
            case "save":
                let ok = await model.save(asNew: false)
                NSApp.reply(toApplicationShouldTerminate: ok)
            case "discard":
                NSApp.reply(toApplicationShouldTerminate: true)
            default:
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }

        return .terminateLater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
