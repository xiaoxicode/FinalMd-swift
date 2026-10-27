//
//  ChartRenderer.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  图表引擎。Electron 版是自研 SVG 引擎（renderer/src/charts.js），
//  原生版直接用 Swift Charts 绘制，再用 ImageRenderer 以 2 倍分辨率光栅化成 PNG 内嵌。
//  画布尺寸沿用原版：760 × 420。
//

import SwiftUI
import Charts
import AppKit

/// 图表画布（复用于对话框预览与 PNG 导出）
struct ChartCanvas: View {

    let config: ChartConfig

    private var palette: ChartPalette {
        let index = max(min(config.theme, ChartPalette.all.count - 1), 0)
        return ChartPalette.all[index]
    }

    var body: some View {
        VStack(spacing: 0) {
            if !config.title.isEmpty {
                Text(config.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1F2328))
                    .padding(.top, 14)
                    .padding(.bottom, 4)
            }
            chartBody
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
        .background(Color.white)
    }

    @ViewBuilder
    private var chartBody: some View {
        if config.isEmptyData {
            placeholder
        } else {
            switch config.type {
            case "pie": pieChart
            case "line": lineChart
            case "area": areaChart
            case "hbar": horizontalBarChart
            default: barChart
            }
        }
    }

    private var placeholder: some View {
        VStack {
            Spacer()
            Text("—")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: 柱状图

    private var barChart: some View {
        Chart(config.data) { item in
            BarMark(
                x: .value("category", item.category),
                y: .value("value", item.value)
            )
            .foregroundStyle(by: .value("series", item.series))
            .position(by: .value("series", item.series))
            .cornerRadius(2)
            .annotation(position: .top) {
                if config.showValue { Text(format(item.value)).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
        .chartForegroundStyleScale(range: palette.colors)
        .chartXAxisLabel(config.xLabel, position: .bottom, alignment: .center, spacing: 6)
        .chartYAxisLabel(config.yLabel, position: .leading, alignment: .center, spacing: 6)
        .chartLegend(config.series.count > 1 ? .visible : .hidden)
    }

    // MARK: 折线图

    private var lineChart: some View {
        Chart(config.data) { item in
            LineMark(
                x: .value("category", item.category),
                y: .value("value", item.value),
                series: .value("series", item.series)
            )
            .foregroundStyle(by: .value("series", item.series))
            .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .symbol(by: .value("series", item.series))
            .interpolationMethod(.catmullRom)
            .annotation(position: .top) {
                if config.showValue { Text(format(item.value)).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
        .chartForegroundStyleScale(range: palette.colors)
        .chartXAxisLabel(config.xLabel, position: .bottom, alignment: .center, spacing: 6)
        .chartYAxisLabel(config.yLabel, position: .leading, alignment: .center, spacing: 6)
        .chartLegend(config.series.count > 1 ? .visible : .hidden)
    }

    // MARK: 面积图

    private var areaChart: some View {
        Chart(config.data) { item in
            AreaMark(
                x: .value("category", item.category),
                y: .value("value", item.value),
                series: .value("series", item.series)
            )
            .foregroundStyle(by: .value("series", item.series))
            .interpolationMethod(.catmullRom)
            .opacity(0.18)
            LineMark(
                x: .value("category", item.category),
                y: .value("value", item.value),
                series: .value("series", item.series)
            )
            .foregroundStyle(by: .value("series", item.series))
            .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.catmullRom)
        }
        .chartForegroundStyleScale(range: palette.colors)
        .chartXAxisLabel(config.xLabel, position: .bottom, alignment: .center, spacing: 6)
        .chartYAxisLabel(config.yLabel, position: .leading, alignment: .center, spacing: 6)
        .chartLegend(config.series.count > 1 ? .visible : .hidden)
    }

    // MARK: 条形图（横向）

    private var horizontalBarChart: some View {
        Chart(config.data) { item in
            BarMark(
                x: .value("value", item.value),
                y: .value("category", item.category)
            )
            .foregroundStyle(by: .value("series", item.series))
            .position(by: .value("series", item.series))
            .cornerRadius(2)
            .annotation(position: .trailing) {
                if config.showValue { Text(format(item.value)).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
        .chartForegroundStyleScale(range: palette.colors)
        .chartXAxisLabel(config.xLabel, position: .bottom, alignment: .center, spacing: 6)
        .chartYAxisLabel(config.yLabel, position: .leading, alignment: .center, spacing: 6)
        .chartLegend(config.series.count > 1 ? .visible : .hidden)
    }

    // MARK: 饼图

    private var pieChart: some View {
        Chart(config.pieData) { item in
            SectorMark(
                angle: .value("value", max(item.value, 0)),
                innerRadius: .ratio(0),
                angularInset: 1.5
            )
            .foregroundStyle(by: .value("category", item.category))
            .cornerRadius(2)
            .annotation(position: .overlay) {
                if config.showValue {
                    let total = max(config.pieData.reduce(0) { $0 + max($1.value, 0) }, 1)
                    Text(String(format: "%.1f%%", item.value / total * 100))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .chartForegroundStyleScale(range: palette.colors)
        .chartLegend(position: .bottom, spacing: 8)
    }

    // MARK: 数值格式（与原版 fmt() 一致：≥10000 加千分位）

    private func format(_ v: Double) -> String {
        if abs(v) >= 10000 {
            return String(format: "%.0f", v)
        }
        let rounded = round(v * 100) / 100
        if rounded == rounded.rounded() { return String(format: "%.0f", rounded) }
        return String(format: "%.2f", rounded)
    }
}

// MARK: - 光栅化

@MainActor
enum ChartRenderer {

    static let canvasSize = NSSize(width: 760, height: 420)

    /// 配置 → PNG 图像（2 倍分辨率，保证内嵌进 Markdown 后清晰）
    static func renderPNG(_ config: ChartConfig, scale: CGFloat = 2) -> NSImage? {
        let view = ChartCanvas(config: config)
            .frame(width: canvasSize.width, height: canvasSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.nsImage
    }
}
