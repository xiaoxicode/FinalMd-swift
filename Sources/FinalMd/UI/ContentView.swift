//
//  ContentView.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  主窗口：标题栏 + 功能区 + 查找栏 + 编辑区 + 状态栏。
//  对应 Electron 版 renderer/index.html 的 .app 容器。
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var l10n: Localizer

    var body: some View {
        VStack(spacing: 0) {
            TitleBarView()
            RibbonView()
            if model.findVisible {
                FindBarView()
            }
            // 两个编辑器常驻同一容器：切换模式只是显隐互换，
            // 即刻模式里的富文本 / 图片附件 / 光标不会被销毁重建。
            ZStack {
                EditorView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                SourceEditorView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusBarView()
        }
        .background(Color(nsColor: DocTheme.workspaceBackground))
        .overlay(alignment: .bottom) {
            if let message = model.toastMessage {
                ToastView(message: message)
                    .padding(.bottom, 44)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.toastMessage)
        .animation(.easeOut(duration: 0.15), value: model.findVisible)
        .sheet(item: $model.activeDialog) { kind in
            dialog(for: kind)
                .environmentObject(model)
                .environmentObject(l10n)
        }
    }

    @ViewBuilder
    private func dialog(for kind: DialogKind) -> some View {
        switch kind {
        case .image:
            ImageInsertDialog()
        case .link:
            LinkInsertDialog()
        case .table:
            TableInsertDialog()
        case .chart:
            ChartDialogView(initial: model.chartDraft ?? ChartConfig.sample(l10n))
        case .confirm(let spec):
            ConfirmDialogView(spec: spec) { answer in
                model.activeDialog = nil
                model.confirmHandler?(answer)
            }
        }
    }
}
