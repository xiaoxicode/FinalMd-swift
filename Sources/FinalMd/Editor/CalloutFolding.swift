//
//  CalloutFolding.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  Obsidian Callout 折叠范围计算。
//
//  刻意只依赖 AppKit：折叠用 NSLayoutManager 的临时属性实现，不写 NSTextStorage，
//  所以「折叠了什么」必须能被冒烟测试直接验证 —— 首行永远可见、只折叠指定块、
//  段落终结符不进隐藏范围，序列化读到的仍是完整原文。
//

import AppKit

enum CalloutFolding {

    /// 需要隐藏的字符范围。返回的范围不含段落末尾的 `\n`，避免布局粘连。
    /// - foldedIDs: 用户折叠的 Callout 块 ID
    static func hiddenRanges(in storage: NSAttributedString, foldedIDs: Set<Int>) -> [NSRange] {
        guard !foldedIDs.isEmpty, storage.length > 0 else { return [] }
        let ns = storage.string as NSString
        var seenFirst: Set<Int> = []
        var result: [NSRange] = []
        var loc = 0

        while loc < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            if paragraph.length == 0 { break }
            loc = NSMaxRange(paragraph)
            guard let id = storage.attribute(.mdCalloutID, at: paragraph.location,
                                             effectiveRange: nil) as? Int else { continue }
            // 首行是 Callout 标题，永远可见
            if !seenFirst.contains(id) {
                seenFirst.insert(id)
                continue
            }
            guard foldedIDs.contains(id) else { continue }

            var r = paragraph
            if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 0x0A { r.length -= 1 }
            if r.length > 0 { result.append(r) }
        }
        return result
    }
}
