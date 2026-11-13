//
//  AIProtocol.swift
//  FinalMd（墨写）— 自定义大模型接入
//
//  OpenAI 兼容 /chat/completions 的协议层。这里只放纯函数（不碰网络、不碰 UI），
//  因此能被 scripts/run-smoke.sh 直接编译验证。
//

import Foundation

// MARK: - 端点归一化

enum AIEndpoint {
    /// 用户可能填 https://api.openai.com/v1、完整 /chat/completions、裸域名、
    /// 或本机 Ollama 的 http://127.0.0.1:11434/v1 —— 统一补成可 POST 的 URL。
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard var comps = URLComponents(string: s),
              let host = comps.host, !host.isEmpty,
              let scheme = comps.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }

        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/chat/completions") {
            // 已经是完整路径，原样保留
        } else if path.isEmpty {
            path = "/v1/chat/completions"
        } else if path.hasSuffix("/v1") {
            path += "/chat/completions"
        } else {
            // 自建网关常带自定义前缀，例如 /api/v1、/openai/deployments/xxx
            path += "/v1/chat/completions"
        }
        comps.path = path
        return comps.url
    }
}

// MARK: - 请求

struct AIRequestConfig: Equatable {
    var model: String
    var temperature: Double
    var timeout: TimeInterval
    var systemPrompt: String
    var apiKey: String
    var endpoint: URL
}

enum AIProtocolError: Error, Equatable {
    case missingModel
    case invalidJSON
    case missingContent
    case api(String)
}

enum AIProtocol {

    /// 把「一句话指令」和待处理文本拼成 user message。
    /// 用分隔线隔开，降低模型把正文当指令执行的概率。
    static func composeUserMessage(instruction: String, content: String) -> String {
        let i = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(i)\n\n---\n\n\(content)"
    }

    static func makeRequest(_ config: AIRequestConfig,
                            instruction: String,
                            content: String) throws -> URLRequest {
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProtocolError.missingModel
        }
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": config.systemPrompt],
                ["role": "user", "content": composeUserMessage(instruction: instruction, content: content)],
            ],
            "temperature": config.temperature,
            "stream": false,
        ]
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = config.timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    // MARK: - 响应

    /// 兼容常见返回形态：choices[0].message.content 为字符串 / 分段数组，
    /// 以及部分网关直接返回顶层 content 或 choices[0].text。
    static func parseContent(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let root = json as? [String: Any] else {
            throw AIProtocolError.invalidJSON
        }
        if let apiMessage = parseErrorMessage(from: data), !apiMessage.isEmpty {
            throw AIProtocolError.api(apiMessage)
        }
        if let choices = root["choices"] as? [[String: Any]], let first = choices.first {
            if let message = first["message"] as? [String: Any],
               let text = contentString(message["content"]) {
                return text
            }
            if let text = first["text"] as? String, !text.isEmpty { return text }
        }
        if let text = contentString(root["content"]) { return text }
        throw AIProtocolError.missingContent
    }

    static func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let root = json as? [String: Any] else { return nil }
        if let err = root["error"] as? [String: Any] {
            if let msg = err["message"] as? String { return msg }
        }
        if let msg = root["error"] as? String { return msg }
        return nil
    }

    private static func contentString(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let parts = value as? [[String: Any]] {
            let joined = parts.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    /// 模型常把 Markdown 整段包进 ```markdown ... ```，写回文档前剥掉。
    static func sanitize(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        if let newline = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: newline)...])
        } else {
            return s
        }
        if let range = s.range(of: "\n```", options: .backwards) {
            s = String(s[..<range.lowerBound])
        } else if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - HTTP 状态分类

enum AIStatusKind: Equatable {
    case ok
    case unauthorized
    case notFound
    case rateLimited
    case serverError
    case other(Int)

    static func classify(_ code: Int) -> AIStatusKind {
        switch code {
        case 200...299: return .ok
        case 401, 403: return .unauthorized
        case 404: return .notFound
        case 429: return .rateLimited
        case 500...599: return .serverError
        default: return .other(code)
        }
    }
}
