//
//  AIPanels.swift
//  FinalMd（墨写）— 模型设置 / AI 指令面板
//
//  两个面板都挂在 ContentView 的 sheet 上。设置用本地草稿，点「保存」才落盘；
//  指令面板先预览结果，再由用户决定替换、插入还是复制，不会悄悄改动正文。
//

import SwiftUI
import AppKit

// MARK: - 模型设置

struct AISettingsView: View {

    @EnvironmentObject var ai: AIController
    @EnvironmentObject var l10n: Localizer
    @Environment(\.dismiss) private var dismiss

    @State private var draft = AISettings()
    @State private var draftKey = ""
    @State private var revealKey = false
    @State private var quickPreset: AIServicePreset = .custom
    @State private var isTesting = false
    @State private var testMessage: String?

    private let presets: [AIServicePreset] = [.openAI, .deepSeek, .ollama, .custom]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ai.t("ai.settings.title")).font(.headline)

            Group {
                field(ai.t("ai.settings.preset")) {
                    Picker("", selection: $quickPreset) {
                        ForEach(presets) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: quickPreset) { _, p in
                        guard p != .custom else { return }
                        draft.baseURL = p.baseURL
                        draft.model = p.model
                    }
                }

                field(ai.t("ai.settings.baseURL")) {
                    TextField(ai.t("ai.settings.baseURL.ph"), text: $draft.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                field(ai.t("ai.settings.apiKey")) {
                    HStack(spacing: 6) {
                        if revealKey {
                            TextField(ai.t("ai.settings.apiKey.ph"), text: $draftKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField(ai.t("ai.settings.apiKey.ph"), text: $draftKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(revealKey ? "隐藏" : "显示")
                    }
                }

                field(ai.t("ai.settings.model")) {
                    TextField(ai.t("ai.settings.model.ph"), text: $draft.model)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 16) {
                    field(ai.t("ai.settings.temperature")) {
                        HStack {
                            Slider(value: $draft.temperature, in: 0...1, step: 0.1)
                                .frame(width: 130)
                            Text(String(format: "%.1f", draft.temperature))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 26)
                        }
                    }
                    field(ai.t("ai.settings.timeout")) {
                        TextField("60", value: $draft.timeout, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                }

                field(ai.t("ai.settings.systemPrompt")) {
                    TextField(ai.t("ai.settings.systemPrompt.ph"), text: $draft.systemPrompt)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text(ai.t("ai.settings.hint"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let msg = testMessage {
                Text(msg)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            if let err = ai.errorMessage {
                Text(err)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(ai.t("ai.settings.test")) {
                    isTesting = true
                    ai.settings = draft
                    ai.apiKey = draftKey
                    Task {
                        let ok = await ai.testConnection()
                        testMessage = ok ? ai.t("ai.settings.testOK") : nil
                        isTesting = false
                    }
                }
                .disabled(isTesting || ai.isLoading)

                Button(ai.t("ai.settings.clearKey")) {
                    draftKey = ""
                    ai.apiKey = ""
                    AIKeychain.delete()
                }
                .buttonStyle(.borderless)

                Spacer()
                Button(ai.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(ai.t("ai.settings.save")) {
                    ai.settings = draft
                    ai.apiKey = draftKey
                    ai.persistSettings()
                    ai.errorMessage = nil
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 540)
        .onAppear {
            draft = ai.settings
            draftKey = ai.apiKey
        }
    }

    private func field<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - AI 指令

struct AICommandView: View {

    @EnvironmentObject var ai: AIController
    @EnvironmentObject var l10n: Localizer
    @Environment(\.dismiss) private var dismiss

    @State private var showSource = false

    private var presets: [AIPreset] { AIPresets.all { l10n.t($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ai.t("ai.command.title")).font(.headline)
                Spacer()
                if ai.needsKey {
                    Button(ai.t("ai.command.openSettings")) { ai.openSettings() }
                        .font(.system(size: 11.5))
                }
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ai.t("ai.command.preset")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { ai.presetID },
                        set: { ai.selectPreset($0) }
                    )) {
                        ForEach(presets) { p in
                            Text(p.title).tag(p.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(ai.t("ai.command.scope")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Picker("", selection: $ai.scope) {
                        Text(ai.t("ai.command.scope.selection")).tag(AIScope.selection)
                        Text(ai.t("ai.command.scope.document")).tag(AIScope.document)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(ai.t("ai.command.instruction")).font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $ai.instruction)
                    .font(.system(size: 12))
                    .frame(height: 58)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }

            HStack {
                Button {
                    showSource.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showSource ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                        Text("\(ai.t("ai.command.source")) · \(ai.sourceText.count)")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(ai.t("ai.command.run")) { Task { await ai.run() } }
                    .disabled(ai.isLoading)
                if ai.isLoading {
                    ProgressView().controlSize(.small)
                    Text(ai.t("ai.command.running")).font(.system(size: 11))
                }
            }

            if showSource {
                ScrollView {
                    Text(ai.sourceText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 88)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }

            if let err = ai.errorMessage {
                Text(err)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let status = ai.statusMessage {
                Text(status).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }

            TextEditor(text: $ai.result)
                .font(.system(size: 12))
                .frame(minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))

            Text(ai.t("ai.command.hint"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(ai.t("ai.command.replaceSelection")) { apply(.replaceSelection) }
                    .disabled(ai.result.isEmpty || ai.sourceRange == nil)
                Button(ai.t("ai.command.insert")) { apply(.insertAtCaret) }
                    .disabled(ai.result.isEmpty)
                Button(ai.t("ai.command.replaceDocument")) { apply(.replaceDocument) }
                    .disabled(ai.result.isEmpty)
                Button(ai.t("ai.command.copy")) { ai.copyResult() }
                    .disabled(ai.result.isEmpty)
                Spacer()
                Button(ai.t("ai.command.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 640, height: 540)
        .onChange(of: ai.scope) { _, _ in ai.prepareSource() }
    }

    private func apply(_ mode: AIApplyMode) {
        ai.apply(mode)
        AppModel.shared?.showToast(ai.t("ai.command.applied"))
        dismiss()
    }
}
