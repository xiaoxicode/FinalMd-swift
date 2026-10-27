//
//  ChartConfig.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  图表配置。对应 Electron 版 renderer/src/charts.js + chart-dialog.js：
//  配置以 Base64 JSON 编码进图片的 title 属性，随 .md 文件一起走，双击图表即可回来改数据。
//

import Foundation
import AppKit
import SwiftUI

struct ChartSeries: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var values: [Double]

    private enum CodingKeys: String, CodingKey { case name, values }

    init(name: String, values: [Double]) {
        self.name = name
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        // 兼容旧数据：允许值为字符串或缺失
        if let doubles = try? c.decode([Double].self, forKey: .values) {
            values = doubles
        } else if let strings = try? c.decode([String].self, forKey: .values) {
            values = strings.map { Double($0) ?? 0 }
        } else {
            values = []
        }
    }
}

struct ChartConfig: Codable, Hashable {

    /// bar / line / area / hbar / pie
    var type: String
    var title: String
    var xLabel: String
    var yLabel: String
    var categories: [String]
    var series: [ChartSeries]
    /// 配色方案下标
    var theme: Int
    var showValue: Bool

    static let tag = "mwchart:"

    static let types = ["bar", "line", "area", "hbar", "pie"]

    // MARK: 默认示例

    static func sample(_ l10n: Localizer) -> ChartConfig {
        ChartConfig(
            type: "bar",
            title: l10n.t("sample.title"),
            xLabel: l10n.t("sample.xLabel"),
            yLabel: l10n.t("sample.yLabel"),
            categories: [
                l10n.t("sample.cat1"),
                l10n.t("sample.cat2"),
                l10n.t("sample.cat3"),
                l10n.t("sample.cat4"),
            ],
            series: [
                ChartSeries(name: l10n.t("sample.series1"), values: [120, 158, 176, 210]),
                ChartSeries(name: l10n.t("sample.series2"), values: [148, 182, 205, 246]),
            ],
            theme: 0,
            showValue: true
        )
    }

    // MARK: 编码进图片 title

    /// 配置 → "mwchart:<base64>"
    func encodedTitle() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return Self.tag }
        return Self.tag + data.base64EncodedString()
    }

    /// 图片 title → 配置
    static func decode(_ title: String?) -> ChartConfig? {
        guard let title, title.hasPrefix(tag) else { return nil }
        let payload = String(title.dropFirst(tag.count))
        guard let data = Data(base64Encoded: payload),
              let cfg = try? JSONDecoder().decode(ChartConfig.self, from: data),
              !cfg.categories.isEmpty else { return nil }
        return cfg
    }

    static func isChartTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        return title.hasPrefix(tag)
    }

    // MARK: 数据访问

    /// 取第 i 个分类下第 s 个系列的值
    func value(category: Int, seriesIndex: Int) -> Double {
        guard seriesIndex < series.count, category < series[seriesIndex].values.count else { return 0 }
        return series[seriesIndex].values[category]
    }

    var isEmptyData: Bool {
        categories.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    mutating func resizeValues() {
        for i in series.indices {
            var v = series[i].values
            if v.count < categories.count {
                v.append(contentsOf: Array(repeating: 0, count: categories.count - v.count))
            } else if v.count > categories.count {
                v = Array(v.prefix(categories.count))
            }
            series[i].values = v
        }
    }
}

// MARK: - 配色方案

struct ChartPalette {
    let key: String
    let colors: [Color]

    /// 取第 i 个系列的颜色
    func color(_ index: Int) -> Color {
        guard !colors.isEmpty else { return .accentColor }
        return colors[index % colors.count]
    }

    var swiftUIColors: [Color] { colors }

    static let all: [ChartPalette] = [
        ChartPalette(key: "business", colors: [
            Color(hex: 0x2F6FEB), Color(hex: 0x5AA0FF), Color(hex: 0x8FC0FF),
            Color(hex: 0x1F4FA8), Color(hex: 0x7D5FFF), Color(hex: 0xC2DCFF),
        ]),
        ChartPalette(key: "sunrise", colors: [
            Color(hex: 0xE8543F), Color(hex: 0xFF8A6B), Color(hex: 0xF2A03D),
            Color(hex: 0xB8331F), Color(hex: 0xFFC46B), Color(hex: 0xFFD9CC),
        ]),
        ChartPalette(key: "fresh", colors: [
            Color(hex: 0x2BA36B), Color(hex: 0x5EC98F), Color(hex: 0x96E0B7),
            Color(hex: 0x177A4C), Color(hex: 0x8FD14F), Color(hex: 0xCCF2DF),
        ]),
        ChartPalette(key: "elegant", colors: [
            Color(hex: 0x7C5CFF), Color(hex: 0xA78BFA), Color(hex: 0xC4B5FD),
            Color(hex: 0x5B3FD6), Color(hex: 0xEC4899), Color(hex: 0xE5DDFF),
        ]),
        ChartPalette(key: "gray", colors: [
            Color(hex: 0x4B5563), Color(hex: 0x6B7280), Color(hex: 0x9CA3AF),
            Color(hex: 0x1F2937), Color(hex: 0x374151), Color(hex: 0xD1D5DB),
        ]),
    ]
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - 图表数据点（喂给 Swift Charts）

/// Swift Charts 需要扁平化的数据
struct ChartDatum: Identifiable, Hashable {
    var id: String { "\(category)-\(series)" }
    let category: String
    let series: String
    let value: Double
}

extension ChartConfig {
    /// 扁平化成 Swift Charts 可用的数据点
    var data: [ChartDatum] {
        var out: [ChartDatum] = []
        for s in series {
            for (i, category) in categories.enumerated() {
                let v = i < s.values.count ? s.values[i] : 0
                out.append(ChartDatum(category: category, series: s.name, value: v))
            }
        }
        return out
    }

    /// 饼图只看第一个系列
    var pieData: [ChartDatum] {
        let s = series.first ?? ChartSeries(name: "", values: [])
        return categories.enumerated().map { i, c in
            ChartDatum(category: c, series: s.name, value: i < s.values.count ? s.values[i] : 0)
        }
    }
}
