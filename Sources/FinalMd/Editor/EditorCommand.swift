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
    case zoomIn, zoomOut, zoomReset, lineRuling
    // 编辑模式
    case toggleMode
}

extension EditorCommand {

    /// 传统模式是纯文本编辑器：所有富文本排版 / 插入命令都不适用，
    /// 文件、撤销、查找、缩放、切换模式这些仍然有效。
    /// 这里守住命令总线，工具栏按钮与菜单项即使被点到也不会破坏纯文本。
    var isAvailableInClassicMode: Bool {
        switch self {
        case .new, .open, .save, .saveAs, .exportHTML, .exportPDF,
             .undo, .redo, .find,
             .zoomIn, .zoomOut, .zoomReset, .toggleMode:
            return true
        default:
            return false
        }
    }

    /// 只有真正改到文档内容的命令才标脏。
    /// 以前「新建 / 打开 / 保存 / 缩放 / 开对话框」一律标脏，会导致刚保存完
    /// 再点一次新建就误弹「有未保存改动」。
    var mutatesDocument: Bool {
        switch self {
        case .bold, .italic, .underline, .strike, .inlineCode, .clearFormat,
             .style, .bulletList, .orderedList, .quote, .codeBlock, .hr,
             .align, .indent, .outdent, .undo, .redo:
            return true
        default:
            // 插入类命令只负责打开对话框，真正写入时由各自的回调标脏
            return false
        }
    }
}

extension AppModel {

    /// 工具栏 / 菜单 / 快捷键统一入口
    func perform(_ command: EditorCommand) {
        // 切换模式不依赖任何编辑器视图就绪，也不该把文档标脏
        if command == .toggleMode {
            toggleEditorMode()
            return
        }

        guard let tv = textView else { return }

        guard editorMode == .instant || command.isAvailableInClassicMode else {
            showToast(l10n.t("mode.classic.richOnly"))
            return
        }

        switch command {
        case .new: Task { _ = await newDocument() }
        case .open: Task { await openDocument() }
        case .save: Task { _ = await save(asNew: false) }
        case .saveAs: Task { _ = await save(asNew: true) }
        case .exportHTML: Task { await exportHTML() }
        case .exportPDF: Task { await exportPDF() }

        case .undo:
            tv.undoManager?.undo()
            noteEdited(in: tv)
        case .redo:
            tv.undoManager?.redo()
            noteEdited(in: tv)
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
        case .lineRuling: toggleLineRuling()
        case .toggleMode: break      // 已在入口提前处理
        }

        if command.mutatesDocument {
            markDirty()
            refreshToolbar()
        }
    }

    /// 行内代码：切换等宽字体 + 灰底（与其它行内样式一样只作用于选中的字符）
    private func toggleInlineCode() {
        guard let tv = textView else { return }
        let shouldAdd = !tv.hasAttribute(.mdInlineCode)
        tv.performInlineStyle { storage, ranges in
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
        }
    }
}
