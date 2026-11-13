//
//  AIClient.swift
//  FinalMd（墨写）— 网络调用
//
//  只做一次非流式 /chat/completions 请求。流式输出对「整段润色」收益不大，
//  却会让撤销合并变得复杂，所以这里保持一次请求、一次替换、一次 ⌘Z。
//

import Foundation

enum AIClientError: Error {
    case badEndpoint
    case missingKey
    case request(AIProtocolError)
    case transport(String)
    case http(status: Int, detail: String)
    case parse(AIProtocolError)
    case emptyResult

    /// 给界面用的本地化 key
    var messageKey: String {
        switch self {
        case .badEndpoint: return "ai.err.endpoint"
        case .missingKey: return "ai.err.noKey"
        case .request: return "ai.err.missingModel"
        case .transport: return "ai.err.network"
        case .http(let status, _):
            switch AIStatusKind.classify(status) {
            case .unauthorized: return "ai.err.unauthorized"
            case .notFound: return "ai.err.notFound"
            case .rateLimited: return "ai.err.rateLimited"
            case .serverError: return "ai.err.server"
            default: return "ai.err.http"
            }
        case .parse: return "ai.err.parse"
        case .emptyResult: return "ai.err.empty"
        }
    }

    /// HTTP 状态码 / 服务端原文，拼在本地化说明后面方便排查
    var detail: String {
        switch self {
        case .transport(let message): return message
        case .http(let status, let detail): return "HTTP \(status)\(detail.isEmpty ? "" : " · \(detail)")"
        case .parse(let error):
            if case .api(let message) = error { return message }
            return ""
        case .request(let error):
            if case .api(let message) = error { return message }
            return ""
        default: return ""
        }
    }
}

enum AIClient {

    static func send(settings: AISettings,
                     apiKey: String,
                     instruction: String,
                     content: String,
                     systemPrompt: String) async throws -> String {
        guard let endpoint = AIEndpoint.normalize(settings.baseURL) else {
            throw AIClientError.badEndpoint
        }
        // 本机 Ollama / LM Studio 不需要密钥；云端服务没有密钥必然 401，提前拦掉
        let isLocal = endpoint.host == "127.0.0.1" || endpoint.host == "localhost" || endpoint.host == "::1"
        if !isLocal && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIClientError.missingKey
        }

        let config = AIRequestConfig(
            model: settings.model,
            temperature: settings.temperature,
            timeout: settings.timeout,
            systemPrompt: systemPrompt,
            apiKey: apiKey,
            endpoint: endpoint
        )
        let request: URLRequest
        do {
            request = try AIProtocol.makeRequest(config, instruction: instruction, content: content)
        } catch let error as AIProtocolError {
            throw AIClientError.request(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIClientError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.transport("invalid response")
        }
        guard AIStatusKind.classify(http.statusCode) == .ok else {
            let detail = AIProtocol.parseErrorMessage(from: data) ?? ""
            throw AIClientError.http(status: http.statusCode, detail: String(detail.prefix(300)))
        }

        let raw: String
        do {
            raw = try AIProtocol.parseContent(from: data)
        } catch let error as AIProtocolError {
            throw AIClientError.parse(error)
        }
        let text = AIProtocol.sanitize(raw)
        guard !text.isEmpty else { throw AIClientError.emptyResult }
        return text
    }
}
