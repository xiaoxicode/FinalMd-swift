//
//  Typography.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  文档排版常量，逐项对应 Electron 版 renderer/styles.css 里的 --doc-font / .mw-editor 系列规则，
//  保证迁移后「纸面」观感一致。
//

import AppKit

enum DocTheme {

    // MARK: 画布 / 界面

    static let workspaceBackground = NSColor(calibratedWhite: 0.94, alpha: 1)   // --bg #f0f0f0
    static let chromeBackground = NSColor(calibratedWhite: 0.98, alpha: 1)       // --chrome #fafafa
    static let chromeForeground = NSColor.white                                  // --chrome-2
    static let border = NSColor(calibratedRed: 0.863, green: 0.863, blue: 0.863, alpha: 1) // #dcdcdc
    static let borderSoft = NSColor(calibratedRed: 0.91, green: 0.91, blue: 0.91, alpha: 1)
    static let hover = NSColor(calibratedWhite: 0.925, alpha: 1)

    // MARK: 文字 / 强调

    static let text = NSColor(calibratedRed: 0.122, green: 0.137, blue: 0.157, alpha: 1)  // #1f2328
    static let textDim = NSColor(calibratedRed: 0.42, green: 0.447, blue: 0.502, alpha: 1) // #6b7280
    static let accent = NSColor(calibratedRed: 0.184, green: 0.435, blue: 0.922, alpha: 1) // #2f6feb
    static let accentSoft = NSColor(calibratedRed: 0.91, green: 0.941, blue: 0.996, alpha: 1)
    static let danger = NSColor(calibratedRed: 0.839, green: 0.271, blue: 0.271, alpha: 1)
    static let defaultHighlight = NSColor(calibratedRed: 1, green: 0.953, blue: 0.639, alpha: 1) // #fff3a3
    static let codeBackground = NSColor(calibratedRed: 0.969, green: 0.973, blue: 0.98, alpha: 1)

    // MARK: 纸张

    /// 页面最大宽度（对应 .page{max-width:820px}）
    static let pageMaxWidth: CGFloat = 820
    /// 页边距（对应 .page{padding:62px 72px 90px}）
    static let pagePadding = NSEdgeInsets(top: 62, left: 72, bottom: 90, right: 72)

    // MARK: 字号

    /// 正文字号（对应 .mw-editor{font-size:16px}）
    static let bodyFontSize: CGFloat = 16
    /// 正文行高倍数（line-height:1.8）
    static let bodyLineHeight: CGFloat = 1.8

    /// 标题字号（对应 h1:1.9em … h6:.95em）
    static func headingFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return bodyFontSize * 1.9
        case 2: return bodyFontSize * 1.5
        case 3: return bodyFontSize * 1.25
        case 4: return bodyFontSize * 1.08
        case 5: return bodyFontSize * 1.0
        default: return bodyFontSize * 0.95
        }
    }

    static let codeFontSize: CGFloat = bodyFontSize * 0.88

    // MARK: 字体

    /// 文档字体（对应 --doc-font）
    static func documentFont(size: CGFloat, weight: NSFont.Weight = .regular, traits: NSFontDescriptor.SymbolicTraits = []) -> NSFont {
        var descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if !traits.isEmpty {
            descriptor = descriptor.withSymbolicTraits(traits.union(descriptor.symbolicTraits))
        }
        let font = NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
        return font
    }

    static func monospacedFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// 段落默认字体（正文）
    static var bodyFont: NSFont { documentFont(size: bodyFontSize) }
}

// MARK: - 段落样式构造

extension DocTheme {

    /// 生成某个块级类型对应的段落样式
    static func paragraphStyle(for block: MDBlockType, alignment: NSTextAlignment = .natural) -> NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.alignment = alignment
        ps.lineBreakMode = .byWordWrapping

        switch block {
        case .code:
            ps.lineHeightMultiple = 1.6
            ps.paragraphSpacing = 10
            ps.paragraphSpacingBefore = 8
            ps.headIndent = 14
            ps.firstLineHeadIndent = 14

        case .quote:
            ps.lineHeightMultiple = bodyLineHeight
            ps.paragraphSpacing = 10
            ps.paragraphSpacingBefore = 6
            // 引用块左侧竖线用缩进 + 文本块背景模拟，见 blockQuoteTextBlock
            ps.headIndent = 20
            ps.firstLineHeadIndent = 20
            ps.tailIndent = -8

        case .paragraph:
            ps.lineHeightMultiple = bodyLineHeight
            ps.paragraphSpacing = 10

        default:
            // 标题
            ps.lineHeightMultiple = 1.35
            ps.paragraphSpacingBefore = 14
            ps.paragraphSpacing = 6
        }
        return ps
    }

    /// 引用块左侧竖线（border-left:3px solid accent）
    static var quoteTextBlock: NSTextBlock {
        let block = NSTextBlock()
        block.setBorderColor(DocTheme.accent, for: .minX)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        block.backgroundColor = NSColor(calibratedRed: 0.973, green: 0.976, blue: 0.984, alpha: 1)
        return block
    }

    /// 代码块外壳
    static var codeTextBlock: NSTextBlock {
        let block = NSTextBlock()
        block.backgroundColor = codeBackground
        block.setBorderColor(borderSoft)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        return block
    }
}

// MARK: - NSColor 十六进制互转（Markdown 里的 <span style="color:#xxx">）

extension NSColor {

    /// #rgb / #rrggbb -> NSColor
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        // 用 sRGB 而不是 calibrated：后者在转到设备色彩空间时会有 gamma 漂移，
        // 导致 #d64545 存进去、读出来变成 #e05c56
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// -> "#rrggbb"
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) ?? usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
