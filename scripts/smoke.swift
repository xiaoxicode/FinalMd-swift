//
//  smoke.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  Markdown 双向转换冒烟测试。对应 Electron 版的 scripts/smoke.js（64 项）。
//  这里聚焦最容易出错的部分：Markdown → NSAttributedString → Markdown 的往返一致性。
//
//  运行：./scripts/run-smoke.sh
//  （不需要 Xcode：只编译 Markdown / i18n / 图表模型这几层，不涉及 SwiftUI 宏）
//

import Foundation
import AppKit

// MARK: - 测试框架

var passed = 0
var failed = 0
var failureDetails: [String] = []

func check(_ name: String, _ condition: Bool) {
    if condition {
        passed += 1
    } else {
        failed += 1
        failureDetails.append("  ✗ \(name)")
    }
}

func equal(_ name: String, _ actual: String, _ expected: String) {
    if actual == expected {
        passed += 1
    } else {
        failed += 1
        failureDetails.append("  ✗ \(name)\n      期望: \(debug(expected))\n      实际: \(debug(actual))")
    }
}

func debug(_ s: String) -> String {
    s.replacingOccurrences(of: "\n", with: "\\n")
}

/// Markdown → 属性串 → Markdown
func roundTrip(_ md: String) -> String {
    let attributed = MarkdownParser.parse(md)
    return MarkdownSerializer.markdown(from: attributed)
}

/// 往返后再走一遍，验证稳定性（第二次结果应与第一次完全相同）
func stable(_ md: String) -> Bool {
    let first = roundTrip(md)
    let second = roundTrip(first)
    return first == second
}

// MARK: - 用例

func testHeadings() {
    equal("H1 往返", roundTrip("# 标题\n"), "# 标题\n")
    equal("H2 往返", roundTrip("## 二级\n"), "## 二级\n")
    equal("H6 往返", roundTrip("###### 六级\n"), "###### 六级\n")
    check("标题不带多余加粗", !roundTrip("# 标题\n").contains("**"))
    check("标题往返稳定", stable("# 标题\n"))
}

func testInline() {
    equal("加粗", roundTrip("**粗体**\n"), "**粗体**\n")
    equal("斜体", roundTrip("*斜体*\n"), "*斜体*\n")
    equal("删除线", roundTrip("~~删除~~\n"), "~~删除~~\n")
    equal("行内代码", roundTrip("`code`\n"), "`code`\n")
    equal("下划线", roundTrip("<u>下划</u>\n"), "<u>下划</u>\n")
    equal("链接", roundTrip("[文字](https://a.com)\n"), "[文字](https://a.com)\n")
    equal("嵌套强调", roundTrip("**粗 _斜_**\n"), "**粗 _斜_**\n")
    check("行内往返稳定", stable("**粗体** 与 *斜体* 与 `code`\n"))
}

func testBlocks() {
    equal("段落", roundTrip("普通段落\n"), "普通段落\n")
    equal("引用", roundTrip("> 引用\n"), "> 引用\n")
    equal("分割线", roundTrip("---\n"), "---\n")

    let list = roundTrip("- 一\n- 二\n")
    equal("无序列表紧排", list, "- 一\n- 二\n")
    check("有序列表编号", roundTrip("1. 甲\n2. 乙\n").hasPrefix("1. 甲\n2. 乙"))
    check("列表往返稳定", stable("- 一\n- 二\n"))

    equal("代码块", roundTrip("```\nlet x = 1\n```\n"), "```\nlet x = 1\n```\n")
    equal("带语言的代码块", roundTrip("```swift\nlet x = 1\n```\n"), "```swift\nlet x = 1\n```\n")
    check("代码块往返稳定", stable("```swift\nlet x = 1\nlet y = 2\n```\n"))

    let md = "段一\n\n段二\n"
    equal("多段落空一行分隔", roundTrip(md), "段一\n\n段二\n")
}

func testTable() {
    let input = "| 名称 | 数量 |\n| --- | --- |\n| 苹果 | 3 |\n"
    equal("表格往返", roundTrip(input), input)
    check("表格往返稳定", stable(input))
    check("表头不输出加粗", !roundTrip(input).contains("**"))
}

func testImageAndChart() {
    let src = "data:image/png;base64,iVBORw0KGgoAA"
    equal("图片往返", roundTrip("![图](\(src))\n"), "![图](\(src))\n")
    check("图片 alt 保留", roundTrip("![图](\(src))\n").contains("![图]"))
    check("图片 src 保留", roundTrip("![图](\(src))\n").contains(src))

    // 图表配置：编码进图片 title，再解回来
    let config = ChartConfig(type: "bar",
                             title: "季度营收",
                             xLabel: "季度",
                             yLabel: "万元",
                             categories: ["Q1", "Q2"],
                             series: [ChartSeries(name: "2026", values: [120, 158])],
                             theme: 0,
                             showValue: true)
    let encoded = config.encodedTitle()
    check("图表 title 带标记", encoded.hasPrefix(ChartConfig.tag))
    let decoded = ChartConfig.decode(encoded)
    check("图表配置可解回", decoded != nil)
    check("图表标题一致", decoded?.title == "季度营收")
    check("图表数据一致", decoded?.series.first?.values == [120, 158])
    check("非图表 title 返回 nil", ChartConfig.decode("普通标题") == nil)
    check("空 title 返回 nil", ChartConfig.decode(nil) == nil)
}

func testColors() {
    let colorMD = "<span style=\"color:#d64545\">红字</span>\n"
    equal("字体颜色往返", roundTrip(colorMD), colorMD)

    let markMD = "<mark>高亮</mark>\n"
    let once = roundTrip(markMD)
    check("高亮会带上背景色", once.contains("background-color:"))
    check("高亮二次往返稳定", roundTrip(once) == once)
}

func testEscaping() {
    // 字面量里的 Markdown 记号要被转义，不能再次被解析成样式
    let md = "a \\* b\n"
    let result = roundTrip(md)
    check("转义星号保留", result.contains("\\*"))
    check("转义不会炸", !result.isEmpty)
}

func testHeroDocument() {
    // 构造一份包含所有块类型的文档，验证整体往返稳定
    let doc = """
    # 标题一

    这是**正文**，带 *斜体*、`代码` 与 [链接](https://example.com)。

    ## 标题二

    - 列表项一
    - 列表项二

    1. 有序一
    2. 有序二

    > 引用一句话

    ```swift
    let x = 1
    ```

    | 列一 | 列二 |
    | --- | --- |
    | a | b |

    ---

    结尾段落。
    """
    let first = roundTrip(doc)
    let second = roundTrip(first)
    equal("综合文档往返稳定", second, first)
    check("综合文档保留 H1", first.contains("# 标题一"))
    check("综合文档保留列表", first.contains("- 列表项一"))
    check("综合文档保留表格", first.contains("| 列一 | 列二 |"))
    check("综合文档保留代码块", first.contains("```swift"))
    check("综合文档保留引用", first.contains("> 引用一句话"))
    check("综合文档保留分割线", first.contains("---"))
}

// 欢迎文档在 7 种语言下各有一份，逐份验证往返稳定与结构完整。
// 注意：不能用 Localizer() 的默认语言来测——那取决于 CI/本机的系统语言，结果不稳定。
func testWelcomeDocument() {
    for code in ["zh", "en", "ja", "ko", "fr", "de", "es"] {
        let welcome = Localizer.translate(code, "welcome")
        check("欢迎文档[\(code)]非空", !welcome.isEmpty)
        let first = roundTrip(welcome)
        let second = roundTrip(first)
        equal("欢迎文档[\(code)]往返稳定", second, first)
        check("欢迎文档[\(code)]有 H1", first.hasPrefix("# "))
        check("欢迎文档[\(code)]有列表", first.contains("\n- "))
        check("欢迎文档[\(code)]有引用", first.contains("\n> "))
    }
}

func testLocalization() {
    let l10n = Localizer()
    check("中文取到中文", l10n.t("tb.bold") == "粗体" || l10n.setLanguage("zh") == false || l10n.t("tb.bold") == "加粗")
    l10n.setLanguage("en")
    check("英文取到英文", l10n.t("tb.bold") == "Bold")
    l10n.setLanguage("ja")
    check("日文取到日文", !l10n.t("tb.bold").isEmpty && l10n.t("tb.bold") != "Bold")
    check("占位符替换", l10n.t("style.heading", ["n": "3"]).contains("3"))
    check("缺失 key 回落 key 本身", Localizer.translate("en", "no.such.key") == "no.such.key")
    check("语言数量 7", I18nDictionary.supportedLanguages.count == 7)
    check("每种语言都有 213 个 key",
          I18nDictionary.supportedLanguages.allSatisfy { I18nDictionary.table[$0.code]?.count == 213 })
    l10n.setLanguage("zh")
}

// MARK: 滚动容器缩放 / 居中 / 横向拖动（真实 EditorScrollFactory 类，可执行回归）

func testScrollViewZoom() {
    MainActor.assumeIsolated {
        _ = NSApplication.shared          // 滚轮事件处理依赖 App 对象
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let textView = NSTextView(frame: .zero)
        let (scroll, page) = EditorScrollFactory.make(textView: textView)
        // 滚轮事件链路要求视图挂在窗口里（NSScrollView 会检查 event.window 归属）
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
                           styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        win.contentView = scroll
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        scroll.frame = NSRect(x: 0, y: 0, width: 1080, height: 700)
        scroll.layoutSubtreeIfNeeded()
        page.needsLayout = true; page.layout(); scroll.layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        let docWidth: CGFloat = DocTheme.pageMaxWidth + EditorScrollFactory.outerPadding * 2

        // 文档宽度：页宽 + 对称留白，与缩放无关
        check("初始文档宽度 = 页宽 + 两侧留白", abs(page.frame.width - docWidth) < 0.5)

        // 缩小 → 页面水平居中（白色区 = 文档内 24..width-24）
        // 注意：居中目标用 clip 实际宽度而不是写死的窗口宽，CI 虚拟屏幕可能约束窗口尺寸
        func pageScreenCenterX() -> CGFloat {
            (24 + (page.frame.width - 24 - 24) / 2 - clip.bounds.origin.x) * scroll.magnification
        }
        for mag in [CGFloat(0.6), 1.0] {
            scroll.magnification = mag
            scroll.layoutSubtreeIfNeeded()
            page.needsLayout = true; page.layout(); scroll.layoutSubtreeIfNeeded()
            check("mag \(mag) 页面居中（偏差 < 1pt）",
                  abs(pageScreenCenterX() - clip.frame.width / 2) < 1.0)
        }

        // 放大 → 出现水平滚动范围
        scroll.magnification = 2.0
        scroll.layoutSubtreeIfNeeded()
        page.needsLayout = true; page.layout(); scroll.layoutSubtreeIfNeeded()
        let range = (docWidth - clip.bounds.width)
        check("mag 2.0 有水平滚动范围", range > 300)

        // NSEvent 双指横滑（发给 scroll view 与发给文字视图都要能拖动）
        func pan(_ deltaX: CGFloat, to target: NSView) {
            if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                                wheel1: 0, wheel2: Int32(-deltaX), wheel3: 0),
               let e = NSEvent(cgEvent: cg) {
                target.scrollWheel(with: e)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let before = clip.bounds.origin.x
        pan(-10, to: scroll)
        let afterScroll = clip.bounds.origin.x
        check("放大后横滑 scroll view 能拖动", afterScroll < before)
        pan(-10, to: textView)
        check("横滑事件穿过文字视图也能拖动", clip.bounds.origin.x < afterScroll)
        // 往回拖
        let beforeReverse = clip.bounds.origin.x
        pan(10, to: scroll)
        check("反方向拖回", clip.bounds.origin.x > beforeReverse)

        // 连续捏合：文档宽度必须稳定（否则文字会随缩放重排）
        var widths: Set<Int> = []
        for step in 0...10 {
            scroll.magnification = 1.0 + CGFloat(step) * 0.1
            scroll.layoutSubtreeIfNeeded()
            page.needsLayout = true; page.layout(); scroll.layoutSubtreeIfNeeded()
            widths.insert(Int(page.frame.width.rounded()))
        }
        check("捏合全程文档宽度稳定", widths.count == 1)
    }
}

// MARK: - 入口

testHeadings()
testInline()
testBlocks()
testTable()
testImageAndChart()
testColors()
testEscaping()
testHeroDocument()
testWelcomeDocument()
testScrollViewZoom()
testLocalization()

print("")
if failureDetails.isEmpty {
    print("✅ 冒烟测试全部通过：\(passed) 项")
} else {
    print("❌ 冒烟测试：\(passed) 项通过，\(failed) 项失败")
    failureDetails.forEach { print($0) }
}
if failed > 0 { exit(1) }
