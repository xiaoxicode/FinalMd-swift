//
//  AIPresets.swift
//  FinalMd（墨写）— 内置 AI 指令
//
//  预设只是「一句话指令」的模板，用户随时可以改写或选 custom 自己写。
//  文案全部走 Localizer，这里不硬编码语言。
//

import Foundation

struct AIPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let instruction: String
}

enum AIPresets {

    /// 顺序即面板里的顺序；custom 固定排第一（自己写一句话）
    static let ids = ["custom", "polish", "agent", "concise", "outline", "grammar", "translate"]

    static let systemPromptKey = "ai.systemPrompt"

    static func all(_ t: (String) -> String) -> [AIPreset] {
        ids.map { id in
            AIPreset(id: id,
                     title: t("ai.preset.\(id)"),
                     instruction: instruction(for: id, t))
        }
    }

    static func instruction(for id: String, _ t: (String) -> String) -> String {
        id == "custom" ? "" : t("ai.instruction.\(id)")
    }

    static func title(for id: String, _ t: (String) -> String) -> String {
        t("ai.preset.\(id)")
    }
}
