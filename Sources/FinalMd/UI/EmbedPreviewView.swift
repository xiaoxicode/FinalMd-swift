//
//  EmbedPreviewView.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  ⌘+点击 ![[嵌入]] 时展开的预览面板。只读，不改文档内容。
//

import SwiftUI
import AppKit

struct EmbedPreviewView: View {

    let preview: EmbedPreview
    @EnvironmentObject var l10n: Localizer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: preview.isImage ? "photo" : "doc.text")
                    .foregroundColor(.accentColor)
                Text(preview.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(l10n.t("common.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            Group {
                if let path = preview.imagePath,
                   let image = NSImage(contentsOfFile: path) {
                    ScrollView {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                    }
                } else {
                    ScrollView {
                        Text(preview.text.isEmpty ? l10n.t("embed.empty") : preview.text)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(16)
                    }
                }
            }
            .background(Color(nsColor: DocTheme.workspaceBackground))
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 360, idealHeight: 480)
    }
}
