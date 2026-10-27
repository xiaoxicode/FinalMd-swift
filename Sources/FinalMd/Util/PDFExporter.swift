//
//  PDFExporter.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  对应 Electron 版的 app:print-to-pdf：只打印正文（编辑器的文本视图），
//  功能区、标题栏、状态栏不会出现在 PDF 里。
//
//  实现上先把文本视图按 A4 内容区高度逐段渲染成单页 PDF，再用 PDFKit 拼成一份多页文档，
//  这样不依赖 NSPrintOperation 的私有保存路径键，行为更可控。
//

import AppKit
import PDFKit

enum PDFExporter {

    /// A4 内容区（72dpi：595×842，四边留 54pt 页边距）
    private static let pageSize = NSSize(width: 595, height: 842)
    private static let margin: CGFloat = 54

    @MainActor
    static func export(l10n: Localizer, view: NSView, defaultName: String) async -> Bool {
        guard let url = await OpenSavePanel.savePDF(l10n: l10n, defaultName: defaultName) else { return false }
        let data = makePDF(view: view)
        guard !data.isEmpty else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// 把视图内容分页渲染成 PDF 数据
    static func makePDF(view: NSView) -> Data {
        view.layoutSubtreeIfNeeded()
        let contentWidth = pageSize.width - margin * 2
        let contentHeight = pageSize.height - margin * 2
        let total = max(view.frame.height, contentHeight)

        let document = PDFDocument()
        var y: CGFloat = 0
        var guardCounter = 0

        while y < total - 1, guardCounter < 400 {
            let height = min(contentHeight, total - y)
            let rect = NSRect(x: 0, y: y, width: contentWidth, height: height)
            let pageData = view.dataWithPDF(inside: rect)
            if let pageDoc = PDFDocument(data: pageData), let page = pageDoc.page(at: 0) {
                document.insert(page, at: document.pageCount)
            }
            y += height
            guardCounter += 1
        }
        if document.pageCount == 0 {
            let pageData = view.dataWithPDF(inside: view.bounds)
            if let pageDoc = PDFDocument(data: pageData), let page = pageDoc.page(at: 0) {
                document.insert(page, at: 0)
            }
        }
        return document.dataRepresentation() ?? Data()
    }
}
