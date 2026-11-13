//
//  AISettings.swift
//  FinalMd（墨写）— 自定义模型配置
//
//  非敏感配置存 UserDefaults；API Key 只进系统钥匙串，绝不写进 plist / 文档 / 日志。
//

import Foundation
import Security

struct AISettings: Equatable {
    var baseURL = "https://api.openai.com/v1"
    var model = "gpt-4o-mini"
    var temperature: Double = 0.3
    var timeout: TimeInterval = 60
    /// 留空则使用内置的系统提示词（随界面语言）
    var systemPrompt = ""
    var lastPreset = "polish"
}

enum AISettingsStore {
    private static let prefix = "finalmd.ai."

    static func load() -> AISettings {
        let d = UserDefaults.standard
        var s = AISettings()
        if let v = d.string(forKey: prefix + "baseURL"), !v.isEmpty { s.baseURL = v }
        if let v = d.string(forKey: prefix + "model"), !v.isEmpty { s.model = v }
        if d.object(forKey: prefix + "temperature") != nil { s.temperature = d.double(forKey: prefix + "temperature") }
        if d.object(forKey: prefix + "timeout") != nil { s.timeout = d.double(forKey: prefix + "timeout") }
        if let v = d.string(forKey: prefix + "systemPrompt") { s.systemPrompt = v }
        if let v = d.string(forKey: prefix + "lastPreset"), AIPresets.ids.contains(v) { s.lastPreset = v }
        return s
    }

    static func save(_ s: AISettings) {
        let d = UserDefaults.standard
        d.set(s.baseURL, forKey: prefix + "baseURL")
        d.set(s.model, forKey: prefix + "model")
        d.set(s.temperature, forKey: prefix + "temperature")
        d.set(s.timeout, forKey: prefix + "timeout")
        d.set(s.systemPrompt, forKey: prefix + "systemPrompt")
        d.set(s.lastPreset, forKey: prefix + "lastPreset")
    }
}

/// 常见服务的一键填充（只是改输入框，不会自动发请求）
enum AIServicePreset: Identifiable, Equatable {
    case openAI, deepSeek, ollama, custom

    var id: String { "\(self)" }

    var title: String {
        switch self {
        case .openAI: return "OpenAI"
        case .deepSeek: return "DeepSeek"
        case .ollama: return "Ollama (本机)"
        case .custom: return "自定义"
        }
    }

    var baseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .ollama: return "http://127.0.0.1:11434/v1"
        case .custom: return ""
        }
    }

    var model: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .deepSeek: return "deepseek-chat"
        case .ollama: return "qwen2.5:7b"
        case .custom: return ""
        }
    }
}

enum AIKeychain {
    private static let service = "cn.moxie.markdown.ai"
    private static let account = "chatCompletionsAPIKey"

    static func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        guard !key.isEmpty, let data = key.data(using: .utf8) else { return true }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
