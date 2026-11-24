//
//  TaskBoxToggle.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  任务列表复选框 `[ ]` / `[x]` / `[X]` 的点击切换逻辑。
//  纯 AppKit 逻辑、不依赖 SwiftUI 宏，便于冒烟测试直接验证；
//  编辑器只负责把命中范围交给 storage 走一次可撤销的替换。
//

import AppKit

enum TaskBoxToggle {

    /// 命中复选框时返回切换后的文字；`[X]` 也按已勾选处理，取消统一写成 `[ ]`。
    /// 其它文字（用户已把 `[ ]` 改写成别的）返回 nil，不擅自改动。
    static func toggled(_ current: String) -> String? {
        switch current {
        case "[ ]", "[x]", "[X]": return current == "[ ]" ? "[x]" : "[ ]"
        default: return nil
        }
    }

    /// 点击位置是否落在某个完整的任务框上。
    /// 用 `.mdTaskBox` 的 effectiveRange 定位，避免只看一个字符就误判。
    static func boxRange(in storage: NSAttributedString, at index: Int) -> NSRange? {
        guard storage.length > 0 else { return nil }
        let i = min(max(index, 0), storage.length - 1)
        var range = NSRange()
        guard storage.attribute(.mdTaskBox, at: i, effectiveRange: &range) != nil,
              NSMaxRange(range) <= storage.length else { return nil }
        let text = (storage.string as NSString).substring(with: range)
        guard toggled(text) != nil else { return nil }
        return range
    }
}
