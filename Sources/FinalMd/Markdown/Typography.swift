//
//  Typography.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  文档排版常量，逐项对应 Electron 版 renderer/styles.css 里的 --doc-font / .mw-editor 系列规则，
//  保证迁移后「纸面」观感一致。
//

import AppKit

enum DocTheme {

    // MARK: 明暗两套色值

    /// 声明一个「浅色 / 深色」双值动态色。
    /// 返回的是 NSColor 的 dynamicProvider 形式：同一份值在绘制时按当前外观解析，
    /// 因此已经排好的属性字符串不必重建，切换外观只要重绘一次。
    static func pair(_ name: String, _ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("finalmd.\(name)")) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    // MARK: 画布 / 界面

    static let workspaceBackground = pair("workspace",
                                          NSColor(srgbRed: 0.941, green: 0.941, blue: 0.941, alpha: 1),   // #f0f0f0
                                          NSColor(srgbRed: 0.078, green: 0.082, blue: 0.094, alpha: 1))  // #141518
    static let chromeBackground = pair("chrome",
                                       NSColor(srgbRed: 0.98, green: 0.98, blue: 0.98, alpha: 1),         // #fafafa
                                       NSColor(srgbRed: 0.106, green: 0.11, blue: 0.125, alpha: 1))   // #1b1c20
    /// 功能区底色（原 --chrome-2，浅色下是纯白）
    static let chromeForeground = pair("chrome2",
                                       NSColor.white,
                                       NSColor(srgbRed: 0.133, green: 0.137, blue: 0.153, alpha: 1))   // #222327
    static let border = pair("border",
                             NSColor(srgbRed: 0.863, green: 0.863, blue: 0.863, alpha: 1),               // #dcdcdc
                             NSColor(srgbRed: 0.204, green: 0.212, blue: 0.235, alpha: 1))            // #34363c
    static let borderSoft = pair("borderSoft",
                                 NSColor(srgbRed: 0.91, green: 0.91, blue: 0.91, alpha: 1),              // #e8e8e8
                                 NSColor(srgbRed: 0.169, green: 0.176, blue: 0.196, alpha: 1))          // #2b2d32
    static let hover = pair("hover",
                            NSColor(srgbRed: 0.925, green: 0.925, blue: 0.925, alpha: 1),               // #ececec
                            NSColor(srgbRed: 0.165, green: 0.173, blue: 0.192, alpha: 1))            // #2a2c31

    // MARK: 文字 / 强调

    static let text = pair("text",
                           NSColor(srgbRed: 0.122, green: 0.137, blue: 0.157, alpha: 1),                   // #1f2328
                           NSColor(srgbRed: 0.89, green: 0.902, blue: 0.918, alpha: 1))                    // #e3e6ea
    static let textDim = pair("textDim",
                              NSColor(srgbRed: 0.42, green: 0.447, blue: 0.502, alpha: 1),                // #6b7280
                              NSColor(srgbRed: 0.6, green: 0.627, blue: 0.671, alpha: 1))                 // #99a0ab
    static let accent = pair("accent",
                             NSColor(srgbRed: 0.184, green: 0.435, blue: 0.922, alpha: 1),                // #2f6feb
                             NSColor(srgbRed: 0.357, green: 0.576, blue: 1, alpha: 1))                    // #5b93ff
    static let accentSoft = pair("accentSoft",
                                 NSColor(srgbRed: 0.91, green: 0.941, blue: 0.996, alpha: 1),             // #e8f0fe
                                 NSColor(srgbRed: 0.118, green: 0.165, blue: 0.267, alpha: 1))            // #1e2a44
    static let danger = pair("danger",
                             NSColor(srgbRed: 0.839, green: 0.271, blue: 0.271, alpha: 1),                // #d64545
                             NSColor(srgbRed: 1, green: 0.42, blue: 0.42, alpha: 1))                      // #ff6b6b
    /// `==高亮==` 的默认底色。这是**文档内容**（会序列化成 rgb()），所以固定不随外观变；
    /// 真正画在屏幕上的是 displayHighlight(_:) 返回的动态色。
    static let defaultHighlight = NSColor(srgbRed: 1, green: 0.953, blue: 0.639, alpha: 1)            // #fff3a3
    /// 代码块 / 行内代码底色。深色下必须明显亮于纸面，否则盒子会「糊」进纸里。
    static let codeBackground = pair("codeBg",
                                     NSColor(srgbRed: 0.969, green: 0.973, blue: 0.98, alpha: 1),         // #f7f8fa
                                     NSColor(srgbRed: 0.169, green: 0.184, blue: 0.216, alpha: 1))         // #2b2f37
    /// 行内代码的砖红字色
    static let inlineCodeText = pair("inlineCode",
                                     NSColor(srgbRed: 0.753, green: 0.204, blue: 0.114, alpha: 1),        // #c0341d
                                     NSColor(srgbRed: 0.91, green: 0.459, blue: 0.416, alpha: 1))          // #e8756a
    /// 引用块底纹。浅色下几乎看不见（只靠左侧竖线），深色下要比纸面亮一档才认得出是引用。
    static let quoteBackground = pair("quoteBg",
                                      NSColor(srgbRed: 0.973, green: 0.976, blue: 0.984, alpha: 1),       // #f8f9fb
                                      NSColor(srgbRed: 0.165, green: 0.18, blue: 0.212, alpha: 1))        // #2a2e36
    /// 表格标题行底纹
    static let tableHeaderBackground = pair("tableHead",
                                            NSColor(srgbRed: 0.961, green: 0.965, blue: 0.976, alpha: 1), // #f5f6f8
                                            NSColor(srgbRed: 0.149, green: 0.157, blue: 0.18, alpha: 1))  // #26282e

    // MARK: 纸张

    /// 页面最大宽度（对应 .page{max-width:820px}）
    static let pageMaxWidth: CGFloat = 820
    /// 页边距（对应 .page{padding:62px 72px 90px}）
    static let pagePadding = NSEdgeInsets(top: 62, left: 72, bottom: 90, right: 72)

    /// 纸张底色：浅色是白纸，深色是「夜色纸」，比工作区亮一档以保留纸张的层次感
    static let pageBackground = pair("page",
                                     NSColor.white,
                                     NSColor(srgbRed: 0.122, green: 0.129, blue: 0.149, alpha: 1))   // #1f2126

    // MARK: 字号

    /// 正文字号（对应 .mw-editor{font-size:16px}）
    static let bodyFontSize: CGFloat = 16
    /// 正文行高倍数（line-height:1.8）
    static let bodyLineHeight: CGFloat = 1.8

    // MARK: 文档横线（作业本行线）

    /// 横线颜色：淡蓝灰，接近作业本的印刷行线，不抢正文。
    /// 深色下换成低亮度蓝灰，否则一条亮线会把整页切成碎条。
    static let ruledLine = pair("ruled",
                                NSColor(srgbRed: 0.796, green: 0.855, blue: 0.918, alpha: 1),            // #cbdaea
                                NSColor(srgbRed: 0.2, green: 0.231, blue: 0.278, alpha: 1))              // #333b47
    /// 横线粗细
    static let ruledLineWidth: CGFloat = 1
    /// 横线相对行底的上移量：留一点缝，避免正好压住下伸部（g、p 的尾巴）
    static let ruledLineInset: CGFloat = 1.5

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

// MARK: - 内容色在深色下的显示映射

extension DocTheme {

    /// 用户设置的字体色：`<span style="color:#1f2328">` 这类深色文字落到深色纸面上等于隐形。
    /// 深色下按 HSB 提亮，浅色下原样返回。
    ///
    /// 关键点：文档里存的仍是**原始色**（序列化只读 .mdTextColor），
    /// 返回的动态色只负责屏幕显示 —— 所以同一份文件在明暗外观下都能读，
    /// 存回 .md 的内容也不会因为当时用的是什么主题而改变。
    static func displayTextColor(_ stored: NSColor) -> NSColor {
        guard let rgb = stored.usingColorSpace(.sRGB) else { return stored }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard b < 0.55 else { return stored }                       // 本来就够亮，不必动
        let lifted = NSColor(hue: h, saturation: min(s, 0.55),
                             brightness: max(b, 0.82), alpha: a)
        return pair("text.\(rgb.hexString)", stored, lifted)
    }

    /// 高亮底色：浅黄（#fff3a3 之类）配浅色文字等于看不见。
    /// 深色下保留色相、压低明度，变成一块深色荧光笔；浅色下原样返回。
    static func displayHighlight(_ stored: NSColor) -> NSColor {
        guard let rgb = stored.usingColorSpace(.sRGB) else { return stored }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard b > 0.5 else { return stored }
        let dimmed = NSColor(hue: h, saturation: max(s, 0.5),
                             brightness: min(b, 0.32), alpha: a)
        return pair("hl.\(rgb.hexString)", stored, dimmed)
    }
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
        block.backgroundColor = quoteBackground
        return block
    }

    /// 代码块外壳
    static var codeTextBlock: NSTextBlock {
        let block = NSTextBlock()
        block.backgroundColor = codeBackground
        block.setBorderColor(border)
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
