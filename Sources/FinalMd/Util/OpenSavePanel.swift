//
//  OpenSavePanel.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  NSOpenPanel / NSSavePanel 的 async 封装，对应 Electron 版 main.js 里的 ipcMain.handle('dialog:*')。
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum OpenSavePanel {

    // MARK: 打开 Markdown

    static func openMarkdown(l10n: Localizer) async -> (path: String, content: String)? {
        let panel = NSOpenPanel()
        panel.title = l10n.t("dialog.openFile")
        panel.allowedContentTypes = markdownTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard await run(panel) == .OK, let url = panel.url else { return nil }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            showError(l10n.t("err.openFailed"), "\(url.path)")
            return nil
        }
        return (url.path, content)
    }

    // MARK: 保存 Markdown

    @discardableResult
    static func saveMarkdown(l10n: Localizer,
                             path: String?,
                             content: String,
                             suggestedName: String) async -> String? {
        var target = path
        if target == nil {
            let panel = NSSavePanel()
            panel.title = l10n.t("dialog.saveFile")
            panel.nameFieldStringValue = suggestedName
            panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
            guard await run(panel) == .OK, let url = panel.url else { return nil }
            target = url.path
        }
        guard var finalPath = target else { return nil }
        if !["md", "markdown", "mdown", "txt"].contains((finalPath as NSString).pathExtension.lowercased()) {
            finalPath += ".md"
        }
        do {
            try content.write(toFile: finalPath, atomically: true, encoding: .utf8)
            return finalPath
        } catch {
            showError(l10n.t("err.saveFailed"), error.localizedDescription)
            return nil
        }
    }

    // MARK: 选择图片

    static func openImages(l10n: Localizer) async -> [URL] {
        let panel = NSOpenPanel()
        panel.title = l10n.t("dialog.insertImage")
        panel.allowedContentTypes = imageTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard await run(panel) == .OK else { return [] }
        return panel.urls
    }

    // MARK: 通用导出

    static func exportFile(l10n: Localizer,
                           defaultName: String,
                           extension ext: String,
                           content: String) async -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        if let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        guard await run(panel) == .OK, let url = panel.url else { return false }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            showError(l10n.t("err.exportFailed"), error.localizedDescription)
            return false
        }
    }

    /// PDF 导出用的保存面板
    static func savePDF(l10n: Localizer, defaultName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.title = l10n.t("dialog.exportPdf")
        panel.nameFieldStringValue = defaultName
        if let type = UTType(filenameExtension: "pdf") {
            panel.allowedContentTypes = [type]
        }
        guard await run(panel) == .OK else { return nil }
        return panel.url
    }

    // MARK: 内部

    private static func run(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
    }

    private static func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private static var markdownTypes: [UTType] {
        ["md", "markdown", "mdown", "txt"].compactMap { UTType(filenameExtension: $0) }
    }

    private static var imageTypes: [UTType] {
        ["png", "jpg", "jpeg", "gif", "webp", "bmp"].compactMap { UTType(filenameExtension: $0) }
    }
}
