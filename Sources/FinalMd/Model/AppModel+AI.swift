//
//  AppModel+AI.swift
//  FinalMd（墨写）— AI 结果的取用与写回
//
//  取原文时用 MarkdownSerializer 保留结构，写回时用 MarkdownParser 还原样式；
//  替换合并成一次 shouldChangeText / didChangeText，保证一次 ⌘Z 就能撤回。
//

import AppKit

extension AppModel {

    /// 取一次原文快照。有选区时只取选区，并记录范围供替换使用。
    func aiSource(scope: AIScope) -> (text: String, range: NSRange?) {
        guard let storage = textView?.textStorage, storage.length > 0 else { return ("", nil) }
        if scope == .selection {
            let sel = textView?.selectedRange() ?? NSRange(location: 0, length: 0)
            if sel.length > 0, NSMaxRange(sel) <= storage.length {
                let slice = storage.attributedSubstring(from: sel)
                return (MarkdownSerializer.markdown(from: slice), sel)
            }
        }
        return (MarkdownSerializer.markdown(from: storage), nil)
    }

    func applyAIResult(_ text: String, mode: AIApplyMode, sourceRange: NSRange?) {
        guard !text.isEmpty, let tv = textView, let storage = tv.textStorage else { return }

        if mode == .replaceDocument {
            setMarkdown(text)
            markDirty()
            return
        }

        let range: NSRange
        switch mode {
        case .replaceSelection:
            guard let r = sourceRange, r.length > 0, NSMaxRange(r) <= storage.length else { return }
            range = r
        case .insertAtCaret:
            range = NSRange(location: min(tv.selectedRange().location, storage.length), length: 0)
        case .replaceDocument:
            return
        }

        let attributed = MarkdownParser.parse(text)
        guard tv.shouldChangeText(in: range, replacementString: text) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: attributed)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + attributed.length, length: 0))
        markDirty()
        refreshAll()
    }
}
