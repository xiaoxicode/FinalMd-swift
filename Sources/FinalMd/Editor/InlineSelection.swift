//
//  InlineSelection.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  行内样式（高亮 / 字体色 / 加粗 …）的作用范围计算。
//  抽成不依赖 NSTextView 的纯函数，冒烟测试可以直接验证。
//

import Foundation

enum InlineSelection {

    /// 选区里「真正能承载行内样式」的连续字符段。
    ///
    /// 块级样式（标题 / 列表 / 对齐）需要整段范围，且必须把属性写到段落
    /// 终结符 `\n` 上，回车才能继承模式 —— 这是 `targetRanges()` 的职责。
    /// 行内样式恰好相反：
    ///   · 只能覆盖用户选中的字符，绝不能扩到整段；
    ///   · 不能把 `backgroundColor` 写到 `\n` 或图片附件上：AppKit 会把段落
    ///     终结符上的背景色渲染成行尾一整块色块，看起来就像「行尾没选中的
    ///     部分也被标记了」，跨行选区还会把样式串到下一行。
    ///
    /// 因为要跳过分隔符，返回的是若干段（跨行选区会被切成多段）。
    static func slices(_ selection: NSRange, in string: NSString) -> [NSRange] {
        guard selection.length > 0 else { return [] }
        let end = min(NSMaxRange(selection), string.length)
        let start = min(max(selection.location, 0), end)
        guard start < end else { return [] }

        var out: [NSRange] = []
        var runStart: Int?
        for i in start..<end {
            if isSeparator(string.character(at: i)) {
                if let b = runStart {
                    out.append(NSRange(location: b, length: i - b))
                    runStart = nil
                }
            } else if runStart == nil {
                runStart = i
            }
        }
        if let b = runStart {
            out.append(NSRange(location: b, length: end - b))
        }
        return out
    }

    /// 段落 / 软换行终结符与附件占位符：没有可见字身，不该被高亮。
    private static func isSeparator(_ ch: unichar) -> Bool {
        switch ch {
        case 0x0A, 0x0D, 0x2028, 0x2029,  // LF / CR / line & paragraph separator
             0xFFFC:                        // NSAttachmentCharacter（内嵌图片 / 图表）
            return true
        default:
            return false
        }
    }
}
