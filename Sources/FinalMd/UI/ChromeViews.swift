//
//  ChromeViews.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  标题栏 / 查找栏 / 状态栏 / Toast。
//  对应 Electron 版 index.html 里的 header.titlebar、div.findbar、footer.statusbar、div.toast。
//

import SwiftUI
import AppKit

// MARK: - 标题栏

struct TitleBarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var l10n: Localizer

    var body: some View {
        HStack(spacing: 8) {
            Text(model.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            if let path = model.currentPath {
                Text(path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Text(model.isDirty ? l10n.t("save.unsaved") : l10n.t("save.saved"))
                .font(.system(size: 11.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(model.isDirty ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.10))
                )
                .foregroundStyle(model.isDirty ? Color.accentColor : Color.secondary)
        }
        .padding(.leading, 84)   // 给 macOS 红绿灯留位
        .padding(.trailing, 12)
        .frame(height: 34)
        .background(Color(nsColor: DocTheme.chromeBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - 查找栏

struct FindBarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var l10n: Localizer

    var body: some View {
        HStack(spacing: 6) {
            TextField(l10n.t("find.placeholder"), text: $model.findText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit { model.findNext() }
                .onChange(of: model.findText) { _, _ in model.refreshFindStatus() }

            tinyButton(l10n.t("find.prev")) { model.findNext(backward: true) }
            tinyButton(l10n.t("find.next")) { model.findNext() }

            Text(model.findStatus)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(minWidth: 74, alignment: .leading)

            TextField(l10n.t("find.replacePh"), text: $model.replaceText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)

            tinyButton(l10n.t("find.replace")) { model.replaceOne() }
            tinyButton(l10n.t("find.replaceAll")) { model.replaceAll() }

            Spacer(minLength: 0)

            Button {
                model.findVisible = false
            } label: {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help(l10n.t("common.close"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: DocTheme.chromeBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tinyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 12))
            .buttonStyle(.borderless)
    }
}

// MARK: - 状态栏

struct StatusBarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var l10n: Localizer

    var body: some View {
        HStack(spacing: 14) {
            Text(l10n.t("stat.words", ["n": String(model.stats.words)]))
            Text(l10n.t("stat.chars", ["n": String(model.stats.chars)]))
            Text(l10n.t("stat.lines", ["n": String(model.stats.lines)]))
            Spacer(minLength: 0)
            Text(model.currentPath ?? l10n.t("stat.notSaved"))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(l10n.t("stat.zoom")) \(Int(round(model.zoom * 100)))%")
            Text("Markdown")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Color(nsColor: DocTheme.chromeBackground))
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
