//
//  Localizer.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  对应 Electron 版 renderer/src/i18n.js + shared/i18n/index.js。
//  界面文案集中在 Dictionaries.swift，运行期可切换语言并即时刷新界面。
//

import SwiftUI

/// 运行期本地化器。作为 EnvironmentObject 注入，语言切换时所有视图自动重绘。
final class Localizer: ObservableObject {

    /// 当前语言代码（zh/en/ja/ko/fr/de/es）
    @Published private(set) var code: String

    private static let storageKey = "finalmd.lang"
    private static let fallback = "en"

    static let supportedCodes: [String] = I18nDictionary.supportedLanguages.map(\.code)

    init() {
        // 优先级：用户上次的选择 → 系统语言 → en（与原版 detectLang 一致）
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        if let saved, Self.supportedCodes.contains(saved) {
            self.code = saved
        } else {
            self.code = Self.matchSystemLanguage() ?? Self.fallback
        }
    }

    // MARK: - 语言匹配

    /// 把系统语言标签（zh-Hans-CN / ja-JP / es-419 …）归一到受支持的语言代码
    static func matchSystemLanguage() -> String? {
        guard let tag = Locale.preferredLanguages.first else { return nil }
        return match(tag)
    }

    static func match(_ tag: String) -> String? {
        let low = tag.lowercased()
        if let hit = supportedCodes.first(where: { low == $0 || low.hasPrefix($0 + "-") }) {
            return hit
        }
        return nil
    }

    /// 校验语言代码，非法则回落到 en
    static func normalize(_ code: String) -> String {
        supportedCodes.contains(code) ? code : fallback
    }

    // MARK: - 取文案

    /// 取当前语言的文案。缺失时依次回落到 en、zh，最后回落 key 本身。
    func t(_ key: String, _ vars: [String: String] = [:]) -> String {
        Self.translate(code, key, vars)
    }

    /// 带快捷键提示：「加粗 (⌘B)」
    func withAccel(_ key: String, _ accel: String? = nil) -> String {
        guard let accel, !accel.isEmpty else { return t(key) }
        return "\(t(key)) (\(accel))"
    }

    static func translate(_ lang: String, _ key: String, _ vars: [String: String] = [:]) -> String {
        let l = normalize(lang)
        var s = I18nDictionary.table[l]?[key]
        if s == nil { s = I18nDictionary.table[fallback]?[key] }
        if s == nil { s = I18nDictionary.table["zh"]?[key] }
        guard var text = s else { return key }
        if !vars.isEmpty {
            for (name, value) in vars {
                text = text.replacingOccurrences(of: "{\(name)}", with: value)
            }
        }
        return text
    }

    /// 导出 HTML 时写进 <html lang> 的语言标签
    var htmlLang: String {
        I18nDictionary.supportedLanguages.first(where: { $0.code == code })?.locale ?? "en"
    }

    // MARK: - 切换

    /// 切换语言并持久化。返回是否真的发生了变化。
    @discardableResult
    func setLanguage(_ newCode: String) -> Bool {
        let next = Self.normalize(newCode)
        let changed = next != code
        code = next
        UserDefaults.standard.set(next, forKey: Self.storageKey)
        return changed
    }
}

// MARK: - SwiftUI 便捷写法

extension Localizer {
    /// LocalizableText("tb.bold") —— 在 View 内部使用，语言变化时自动刷新
    func text(_ key: String, _ vars: [String: String] = [:]) -> Text {
        Text(t(key, vars))
    }
}

/// 让任意 View 能写 `.i18n("tb.bold", ["n": "1"])` 直接拿到本地化 String
struct LocalizedKey: EnvironmentKey {
    static let defaultValue: Localizer = Localizer()
}

extension EnvironmentValues {
    var l10n: Localizer {
        get { self[LocalizedKey.self] }
        set { self[LocalizedKey.self] = newValue }
    }
}
