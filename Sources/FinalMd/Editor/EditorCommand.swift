//
//  EditorCommand.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  命令分发。对应 Electron 版 app.js 的 dispatch() + menu: 频道处理。
//  功能区按钮、菜单项、快捷键都收敛到同一个入口。
//

import AppKit

enum EditorCommand: Equatable {
    // 文件
    case new, open, save, saveAs, exportHTML, exportPDF
    // 编辑
    case undo, redo, find
    // 行内
    case bold, italic, underline, strike, inlineCode, clearFormat, color, highlight
    // 块级
    case style(BlockStyle)
    case bulletList, orderedList, quote, codeBlock, hr
    case align(NSTextAlignment)
    case indent, outdent
    // 插入
    case link, table, image, chart, toc
    // 视图
    case zoomIn, zoomOut, zoomReset
}

extension AppModel {

    /// 工具栏 / 菜单 / 快捷键统一入口
    func perform(_ command: EditorCommand) {
        guard let tv = textView else { return }

        switch command {
        case .new: Task { _ = await newDocument() }
        case .open: Task { await openDocument() }
        case .save: Task { _ = await save(asNew: false) }
        case .saveAs: Task { _ = await save(asNew: true) }
        case .exportHTML: Task { await exportHTML() }
        case .exportPDF: Task { await exportPDF() }

        case .undo: tv.undoManager?.undo(); markDirty(); refreshToolbar()
        case .redo: tv.undoManager?.redo(); markDirty(); refreshToolbar()
        case .find:
            findVisible.toggle()
            if findVisible { refreshFindStatus() }

        case .bold: tv.toggleBold()
        case .italic: tv.toggleItalic()
        case .underline: tv.toggleUnderline()
        case .strike: tv.toggleStrike()
        case .inlineCode: toggleInlineCode()
        case .clearFormat: tv.clearFormatting()
        case .color: break      // 由功能区弹出取色面板处理
        case .highlight: break

        case .style(let style): tv.applyBlockStyle(style)

        case .bulletList: tv.toggleList(ordered: false)
        case .orderedList: tv.toggleList(ordered: true)
        case .quote:
            if tv.currentBlockType() == .quote { tv.applyBlockStyle(.paragraph) }
            else { tv.applyBlockStyle(.quote) }
        case .codeBlock:
            if tv.currentBlockType() == .code { tv.applyBlockStyle(.paragraph) }
            else { tv.applyBlockStyle(.code) }
        case .hr: tv.insertRule()

        case .align(let alignment): tv.setAlignment(alignment)
        case .indent: tv.indentParagraphs()
        case .outdent: tv.outdentParagraphs()

        case .link: activeDialog = .link
        case .table: activeDialog = .table
        case .image: activeDialog = .image
        case .chart: openChartDialog()
        case .toc: insertTOC()

        case .zoomIn: setZoom(zoom + 0.1)
        case .zoomOut: setZoom(zoom - 0.1)
        case .zoomReset: setZoom(1)
        }

        if command != .find {
            markDirty()
            refreshToolbar()
        }
    }

    /// 行内代码：切换等宽字体 + 灰底
    private func toggleInlineCode() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ranges = tv.targetRanges()
        let shouldAdd = !tv.hasAttribute(.mdInlineCode)
        guard tv.shouldChangeText(in: ranges[0], replacementString: nil) else { return }
        storage.beginEditing()
        for r in ranges {
            if shouldAdd {
                let attrs = codeAttributes(storage.attributes(at: r.location, effectiveRange: nil))
                storage.addAttributes(attrs, range: r)
            } else {
                storage.removeAttribute(.mdInlineCode, range: r)
                storage.removeAttribute(.backgroundColor, range: r)
                let size = (storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont)?.pointSize
                    ?? DocTheme.bodyFontSize
                storage.addAttribute(.font, value: DocTheme.documentFont(size: size), range: r)
                storage.addAttribute(.foregroundColor, value: DocTheme.text, range: r)
            }
        }
        storage.endEditing()
        tv.didChangeText()
    }
}
