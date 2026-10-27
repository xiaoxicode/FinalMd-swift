//
//  InsertDialogs.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  插入图片 / 链接 / 表格对话框，以及通用确认框。
//  对应 Electron 版 index.html 里的 #maskImage / #maskLink / #maskTable / #maskConfirm。
//

import SwiftUI
import AppKit

// MARK: - 插入图片

struct ImageInsertDialog: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var l10n: Localizer
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var alt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("image.title")).font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("image.pickLabel"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button(l10n.t("image.pickBtn")) {
                    Task {
                        await model.pickAndInsertImages()
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
                .controlSize(.large)
            }

            LabeledField(l10n.t("image.urlLabel")) {
                TextField("https://example.com/pic.png", text: $url)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledField(l10n.t("image.altLabel")) {
                TextField(l10n.t("image.altPh"), text: $alt)
                    .textFieldStyle(.roundedBorder)
            }

            Text(l10n.t("image.hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(l10n.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(l10n.t("common.insert")) {
                    model.insertImageURL(url, alt: alt)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 430)
    }
}

// MARK: - 插入链接

struct LinkInsertDialog: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var l10n: Localizer
    @Environment(\.dismiss) private var dismiss

    @State private var url = "https://"
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("link.title")).font(.headline)

            LabeledField(l10n.t("link.urlLabel")) {
                TextField("https://", text: $url).textFieldStyle(.roundedBorder)
            }
            LabeledField(l10n.t("link.textLabel")) {
                TextField("", text: $text).textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button(l10n.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(l10n.t("common.ok")) {
                    model.insertLink(url: url, text: text.isEmpty ? nil : text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 400)
    }
}

// MARK: - 插入表格

struct TableInsertDialog: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var l10n: Localizer
    @Environment(\.dismiss) private var dismiss

    @State private var rows = 3
    @State private var cols = 3
    @State private var hasHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("table.title")).font(.headline)

            HStack(alignment: .top, spacing: 16) {
                LabeledField(l10n.t("table.rows")) {
                    Stepper(value: $rows, in: 1...50) {
                        Text("\(rows)").frame(minWidth: 26)
                    }
                }
                LabeledField(l10n.t("table.cols")) {
                    Stepper(value: $cols, in: 1...20) {
                        Text("\(cols)").frame(minWidth: 26)
                    }
                }
            }

            Toggle(l10n.t("table.headerRow"), isOn: $hasHeader)

            HStack {
                Spacer()
                Button(l10n.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(l10n.t("common.insert")) {
                    model.insertTable(rows: rows, cols: cols, header: hasHeader)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}

// MARK: - 通用确认框

struct ConfirmDialogView: View {
    let spec: ConfirmSpec
    let onChoose: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(spec.title).font(.headline)
            Text(spec.message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                ForEach(spec.buttons) { button in
                    Button(button.label) {
                        onChoose(button.id)
                        dismiss()
                    }
                    .keyboardShortcut(button.style == .primary ? .defaultAction : nil)
                    .tint(button.style == .danger ? .red : nil)
                }
            }
        }
        .padding(18)
        .frame(width: 400)
    }
}

// MARK: - 小组件

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            content
        }
    }
}
