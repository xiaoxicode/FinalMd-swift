//
//  AIController.swift
//  FinalMd（墨写）— AI 面板状态机
//
//  文档内容始终以 AppModel.textView 为准；这里只保存一次生成所用的原文快照、
//  指令、结果和错误，避免生成过程中用户继续打字导致替换错位。
//

import Foundation
import AppKit
import SwiftUI

enum AIScope: String, CaseIterable, Identifiable {
    case selection
    case document
    var id: String { rawValue }
}

enum AIApplyMode {
    case replaceSelection
    case replaceDocument
    case insertAtCaret
}

@MainActor
final class AIController: ObservableObject {

    @Published var settings: AISettings
    @Published var apiKey: String
    @Published var presetID: String
    @Published var instruction: String
    @Published var scope: AIScope = .selection
    @Published var sourceText = ""
    @Published var sourceRange: NSRange?
    @Published var result = ""
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var isLoading = false

    let l10n: Localizer

    init(l10n: Localizer) {
        let saved = AISettingsStore.load()
        self.l10n = l10n
        self.settings = saved
        self.apiKey = AIKeychain.read()
        self.presetID = saved.lastPreset
        self.instruction = AIPresets.instruction(for: saved.lastPreset) { l10n.t($0) }
    }

    func t(_ key: String, _ vars: [String: String] = [:]) -> String {
        l10n.t(key, vars)
    }

    var systemPrompt: String {
        settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? t(AIPresets.systemPromptKey)
            : settings.systemPrompt
    }

    var needsKey: Bool {
        guard let host = AIEndpoint.normalize(settings.baseURL)?.host else { return true }
        let local = ["127.0.0.1", "localhost", "::1"].contains(host)
        return !local && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 面板入口

    func openCommand(preset: String? = nil, autoRun: Bool = false) {
        if let preset { selectPreset(preset) }
        result = ""
        errorMessage = nil
        statusMessage = nil
        prepareSource()
        AppModel.shared?.activeDialog = .aiCommand
        if autoRun { Task { await run() } }
    }

    func openSettings() {
        AppModel.shared?.activeDialog = .aiSettings
    }

    func selectPreset(_ id: String) {
        guard AIPresets.ids.contains(id) else { return }
        presetID = id
        instruction = AIPresets.instruction(for: id) { l10n.t($0) }
        settings.lastPreset = id
    }

    /// 抓一次原文快照；没有选区时自动按整篇处理
    func prepareSource() {
        let source: (text: String, range: NSRange?) =
            AppModel.shared?.aiSource(scope: scope) ?? ("", nil)
        sourceText = source.text
        sourceRange = source.range
        if source.range == nil { scope = .document }
    }

    // MARK: - 生成

    func run() async {
        guard !isLoading else { return }
        errorMessage = nil
        statusMessage = nil
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = t("ai.command.emptySource"); return
        }
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = t("ai.command.emptyInstruction"); return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            result = try await AIClient.send(settings: settings,
                                             apiKey: apiKey,
                                             instruction: instruction,
                                             content: sourceText,
                                             systemPrompt: systemPrompt)
        } catch let error as AIClientError {
            let base = t(error.messageKey)
            errorMessage = error.detail.isEmpty ? base : "\(base)（\(error.detail)）"
        } catch {
            errorMessage = t("ai.err.network")
        }
    }

    @discardableResult
    func testConnection() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await AIClient.send(settings: settings,
                                        apiKey: apiKey,
                                        instruction: "Reply with the single word OK.",
                                        content: "ping",
                                        systemPrompt: "Reply with exactly one word.")
            statusMessage = t("ai.settings.testOK")
            errorMessage = nil
            return true
        } catch let error as AIClientError {
            let base = t(error.messageKey)
            errorMessage = error.detail.isEmpty ? base : "\(base)（\(error.detail)）"
            statusMessage = nil
            return false
        } catch {
            errorMessage = t("ai.err.network")
            return false
        }
    }

    // MARK: - 结果落回文档

    func apply(_ mode: AIApplyMode) {
        guard !result.isEmpty else { return }
        AppModel.shared?.applyAIResult(result, mode: mode, sourceRange: sourceRange)
        statusMessage = t("ai.command.applied")
    }

    func copyResult() {
        guard !result.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        statusMessage = t("ai.command.copied")
    }

    func persistSettings() {
        AISettingsStore.save(settings)
        AIKeychain.save(apiKey)
    }
}
