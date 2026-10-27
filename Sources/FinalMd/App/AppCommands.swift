//
//  AppCommands.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  原生菜单栏。对应 Electron 版 main.js 的 buildMenu()，
//  7 个菜单：文件 / 编辑 / 插入 / 格式 / 视图 / 语言 / 帮助。
//

import SwiftUI
import AppKit

struct AppCommands: Commands {

    @ObservedObject var model: AppModel
    @ObservedObject var l10n: Localizer

    var body: some Commands {
        // MARK: 文件
        CommandGroup(replacing: .newItem) {
            Button(l10n.t("menu.file.new")) { model.perform(.new) }
                .keyboardShortcut("n", modifiers: .command)
            Button(l10n.t("menu.file.open")) { model.perform(.open) }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button(l10n.t("menu.file.save")) { model.perform(.save) }
                .keyboardShortcut("s", modifiers: .command)
            Button(l10n.t("menu.file.saveAs")) { model.perform(.saveAs) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button(l10n.t("menu.file.exportHtml")) { model.perform(.exportHTML) }
            Button(l10n.t("menu.file.exportPdf")) { model.perform(.exportPDF) }
        }

        // MARK: 编辑
        CommandGroup(replacing: .undoRedo) {
            Button(l10n.t("menu.edit.undo")) { model.perform(.undo) }
                .keyboardShortcut("z", modifiers: .command)
            Button(l10n.t("menu.edit.redo")) { model.perform(.redo) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .pasteboard) {
            Button(l10n.t("menu.edit.cut")) { send("cut:") }
                .keyboardShortcut("x", modifiers: .command)
            Button(l10n.t("menu.edit.copy")) { send("copy:") }
                .keyboardShortcut("c", modifiers: .command)
            Button(l10n.t("menu.edit.paste")) { send("paste:") }
                .keyboardShortcut("v", modifiers: .command)
            Button(l10n.t("menu.edit.selectAll")) { send("selectAll:") }
                .keyboardShortcut("a", modifiers: .command)
        }

        CommandGroup(before: .textEditing) {
            Button(l10n.t("menu.edit.find")) { model.perform(.find) }
                .keyboardShortcut("f", modifiers: .command)
        }

        // MARK: 插入
        CommandMenu(l10n.t("menu.insert")) {
            Button(l10n.t("menu.insert.image")) { model.perform(.image) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button(l10n.t("menu.insert.chart")) { model.perform(.chart) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button(l10n.t("menu.insert.table")) { model.perform(.table) }
            Button(l10n.t("menu.insert.link")) { model.perform(.link) }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button(l10n.t("menu.insert.hr")) { model.perform(.hr) }
            Button(l10n.t("menu.insert.codeblock")) { model.perform(.codeBlock) }
            Button(l10n.t("menu.insert.toc")) { model.perform(.toc) }
        }

        // MARK: 格式
        CommandMenu(l10n.t("menu.format")) {
            Button(l10n.t("menu.format.bold")) { model.perform(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button(l10n.t("menu.format.italic")) { model.perform(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button(l10n.t("menu.format.underline")) { model.perform(.underline) }
                .keyboardShortcut("u", modifiers: .command)
            Button(l10n.t("menu.format.strike")) { model.perform(.strike) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Divider()
            Button(l10n.t("menu.format.body")) { model.perform(.style(.paragraph)) }
                .keyboardShortcut("0", modifiers: .command)
            ForEach(1...6, id: \.self) { level in
                Button(l10n.t("menu.format.heading", ["n": String(level)])) {
                    model.perform(.style(.heading(level)))
                }
                .keyboardShortcut(KeyEquivalent(Character(String(level))), modifiers: .command)
            }
            Divider()
            Button(l10n.t("tb.bulletList")) { model.perform(.bulletList) }
            Button(l10n.t("tb.orderedList")) { model.perform(.orderedList) }
            Button(l10n.t("tb.quote")) { model.perform(.quote) }
        }

        // MARK: 视图
        CommandMenu(l10n.t("menu.view")) {
            Button(l10n.t("menu.view.zoomIn")) { model.perform(.zoomIn) }
                .keyboardShortcut("+", modifiers: .command)
            Button(l10n.t("menu.view.zoomOut")) { model.perform(.zoomOut) }
                .keyboardShortcut("-", modifiers: .command)
            Button(l10n.t("menu.view.zoomReset")) { model.perform(.zoomReset) }
                .keyboardShortcut("0", modifiers: [.command, .shift])
        }

        // MARK: 语言
        CommandMenu(l10n.t("menu.language")) {
            ForEach(I18nDictionary.supportedLanguages) { language in
                Button {
                    l10n.setLanguage(language.code)
                } label: {
                    Text((l10n.code == language.code ? "✓ " : "    ") + language.label)
                }
            }
        }

        // MARK: 帮助
        CommandGroup(replacing: .help) {
            Button(l10n.t("menu.help.checkUpdate")) {
                Task { await model.checkForUpdates() }
            }
        }
    }

    private func send(_ selector: String) {
        NSApp.sendAction(NSSelectorFromString(selector), to: nil, from: nil)
    }
}
