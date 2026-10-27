//
//  ChartDialogView.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  插入 / 编辑图表对话框。对应 Electron 版 renderer/src/chart-dialog.js：
//  选类型 → 填数据 → 挑配色 → 实时预览 → 插入（双击已插入的图表可回来改数据）。
//

import SwiftUI
import AppKit

struct ChartDialogView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var l10n: Localizer
    @Environment(\.dismiss) private var dismiss

    @State private var config: ChartConfig

    init(initial: ChartConfig) {
        var cfg = initial
        cfg.resizeValues()
        _config = State(initialValue: cfg)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("chart.title")).font(.headline)

            // 图表类型
            HStack(spacing: 8) {
                ForEach(ChartConfig.types, id: \.self) { type in
                    Button {
                        config.type = type
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: icon(for: type))
                                .font(.system(size: 15))
                            Text(label(for: type))
                                .font(.system(size: 11))
                        }
                        .frame(width: 66, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(config.type == type ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(config.type == type ? Color.accentColor : Color.gray.opacity(0.25),
                                        lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                LabeledField(l10n.t("chart.titleLabel")) {
                    TextField(l10n.t("chart.titlePh"), text: $config.title)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField(l10n.t("chart.xLabel")) {
                    TextField(l10n.t("chart.xPh"), text: $config.xLabel)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField(l10n.t("chart.yLabel")) {
                    TextField(l10n.t("chart.yPh"), text: $config.yLabel)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // 数据网格
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("chart.data"))
                    .font(.system(size: 12, weight: .medium))
                dataGrid
                HStack(spacing: 10) {
                    Button(l10n.t("chart.addSeries")) { addSeries() }
                    Button(l10n.t("chart.addCategory")) { addCategory() }
                    Button(l10n.t("chart.reset")) { config = ChartConfig.sample(l10n) }
                    Spacer()
                }
                .font(.system(size: 11.5))
                .buttonStyle(.borderless)
            }

            // 配色 / 显示数值
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.t("chart.palette")).font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(Array(ChartPalette.all.enumerated()), id: \.offset) { index, palette in
                            Button {
                                config.theme = index
                            } label: {
                                HStack(spacing: 1) {
                                    ForEach(0..<4, id: \.self) { i in
                                        Rectangle().fill(palette.color(i)).frame(width: 9, height: 16)
                                    }
                                }
                                .cornerRadius(3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(config.theme == index ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                            .help(l10n.t("theme." + palette.key))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.t("chart.showValue")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Picker("", selection: $config.showValue) {
                        Text(l10n.t("chart.show")).tag(true)
                        Text(l10n.t("chart.hide")).tag(false)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // 实时预览
            ChartCanvas(config: config)
                .frame(width: 460, height: 254)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(6)

            HStack {
                Spacer()
                Button(l10n.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(l10n.t("chart.insert")) {
                    model.insertChart(config)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 500)
    }

    // MARK: 数据网格

    private var dataGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text(l10n.t("chart.category"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                ForEach(Array(config.series.enumerated()), id: \.element.id) { index, series in
                    HStack(spacing: 2) {
                        TextField("", text: Binding(
                            get: { config.series[index].name },
                            set: { config.series[index].name = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 84)
                        if config.series.count > 1 {
                            Button {
                                config.series.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(l10n.t("chart.deleteSeries"))
                        }
                    }
                    .frame(width: 104)
                    .id(series.id)
                }
                Color.clear.frame(width: 22)
            }

            ForEach(0..<config.categories.count, id: \.self) { row in
                GridRow {
                    TextField("", text: Binding(
                        get: { config.categories[row] },
                        set: { config.categories[row] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 92)

                    ForEach(Array(config.series.enumerated()), id: \.element.id) { col, _ in
                        TextField("", value: Binding(
                            get: { config.value(category: row, seriesIndex: col) },
                            set: { newValue in
                                guard col < config.series.count else { return }
                                var values = config.series[col].values
                                while values.count <= row { values.append(0) }
                                values[row] = newValue
                                config.series[col].values = values
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 104)
                        .multilineTextAlignment(.trailing)
                    }

                    Button {
                        deleteCategory(row)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.t("chart.deleteRow"))
                }
            }
        }
    }

    // MARK: 操作

    private func addSeries() {
        let n = config.series.count + 1
        config.series.append(
            ChartSeries(name: l10n.t("chart.series", ["n": String(n)]),
                        values: Array(repeating: 0, count: config.categories.count))
        )
    }

    private func addCategory() {
        let n = config.categories.count + 1
        config.categories.append("\(l10n.t("chart.category")) \(n)")
        config.resizeValues()
    }

    private func deleteCategory(_ row: Int) {
        guard row < config.categories.count, config.categories.count > 1 else { return }
        config.categories.remove(at: row)
        for i in config.series.indices where row < config.series[i].values.count {
            config.series[i].values.remove(at: row)
        }
    }

    private func icon(for type: String) -> String {
        switch type {
        case "bar": return "chart.bar"
        case "line": return "chart.line.uptrend.xyaxis"
        case "area": return "chart.bar.fill"
        case "hbar": return "chart.bar.xaxis"
        case "pie": return "chart.pie"
        default: return "chart.bar"
        }
    }

    private func label(for type: String) -> String {
        l10n.t("chart.type." + type)
    }
}
