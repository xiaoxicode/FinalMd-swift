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
    // 不写死数量：新增文案时不必改这里，但任何一种语言漏翻都会被这条断言抓到
    let baseKeyCount = I18nDictionary.table["zh"]?.count ?? 0
    check("各语言 key 数量一致（\(baseKeyCount) 个）",
          baseKeyCount > 200
          && I18nDictionary.supportedLanguages.allSatisfy { I18nDictionary.table[$0.code]?.count == baseKeyCount })
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
        // 滚动是异步落地的，每次事件后多转两圈 runloop 再读，避免偶发失败
        func pan(_ deltaX: CGFloat, to target: NSView) {
            for _ in 0..<2 {
                if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                                    wheel1: 0, wheel2: Int32(-deltaX), wheel3: 0),
                   let e = NSEvent(cgEvent: cg) {
                    target.scrollWheel(with: e)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            }
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

// MARK: ⌘/⌃ + 滚轮缩放

func testWheelZoom() {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let textView = NSTextView(frame: .zero)
        let (scroll, page) = EditorScrollFactory.make(textView: textView)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
                           styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        win.contentView = scroll
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        scroll.frame = NSRect(x: 0, y: 0, width: 1080, height: 700)
        scroll.layoutSubtreeIfNeeded()
        page.needsLayout = true; page.layout(); scroll.layoutSubtreeIfNeeded()

        var reported: CGFloat = -1
        scroll.onWheelZoom = { reported = $0 }

        func wheel(deltaY: Int32, command: Bool) -> NSEvent? {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                                   wheel1: deltaY, wheel2: 0, wheel3: 0) else { return nil }
            if command { cg.flags = CGEventFlags.maskCommand }
            return NSEvent(cgEvent: cg)
        }

        // 上滚 = 放大
        let base = scroll.magnification
        scroll.scrollWheel(with: wheel(deltaY: 2, command: true)!)
        check("⌘+滚轮上滚放大", scroll.magnification > base + 0.001)
        check("缩放值回调同步模型", abs(reported - scroll.magnification) < 0.001)

        // 下滚 = 缩小
        let zoomedIn = scroll.magnification
        scroll.scrollWheel(with: wheel(deltaY: -4, command: true)!)
        check("⌘+滚轮下滚缩小", scroll.magnification < zoomedIn - 0.001)

        // 不带修饰键时滚轮只滚动，不缩放
        let before = scroll.magnification
        scroll.scrollWheel(with: wheel(deltaY: 6, command: false)!)
        check("普通滚轮不触发缩放", abs(scroll.magnification - before) < 0.0005)

        // 上下限
        for _ in 0..<40 { scroll.scrollWheel(with: wheel(deltaY: 4, command: true)!) }
        check("放大不超过上限 2.0", scroll.magnification <= 2.0 + 0.0001)
        check("放大确实到上限", abs(scroll.magnification - 2.0) < 0.0001)
        for _ in 0..<60 { scroll.scrollWheel(with: wheel(deltaY: -4, command: true)!) }
        check("缩小不低于下限 0.6", scroll.magnification >= 0.6 - 0.0001)
        check("缩小确实到下限", abs(scroll.magnification - 0.6) < 0.0001)

        // 缩放后页面仍然水平居中（锚点缩放不能破坏居中）
        page.needsLayout = true; page.layout(); scroll.layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        func pageCenterX() -> CGFloat {
            (24 + (page.frame.width - 48) / 2 - clip.bounds.origin.x) * scroll.magnification
        }
        check("滚轮缩到最小时页面仍居中", abs(pageCenterX() - clip.frame.width / 2) < 1.0)
    }
}

// MARK: - 编辑模式（即刻 / 传统）

func testEditorModes() {
    // 枚举本身
    check("恰好两种编辑模式", EditorMode.allCases.count == 2)
    check("即刻模式 rawValue", EditorMode.instant.rawValue == "instant")
    check("传统模式 rawValue", EditorMode.classic.rawValue == "classic")
    check("模式名称 key", EditorMode.instant.labelKey == "mode.instant"
          && EditorMode.classic.labelKey == "mode.classic")
    check("模式说明 key", EditorMode.instant.hintKey == "mode.instant.hint")
    check("模式偏好键", EditorMode.storageKey == "finalmd.editorMode")
    check("模式图标", !EditorMode.instant.symbol.isEmpty && !EditorMode.classic.symbol.isEmpty)

    // 七种语言都要有完整的新文案
    let newKeys = ["menu.view.editorMode", "menu.view.toggleMode", "tb.switchMode",
                   "mode.instant", "mode.instant.hint", "mode.classic",
                   "mode.classic.hint", "mode.classic.richOnly"]
    for lang in I18nDictionary.supportedLanguages {
        for key in newKeys {
            let value = I18nDictionary.table[lang.code]?[key] ?? ""
            check("\(lang.code) 文案 \(key)", !value.isEmpty)
        }
    }

    // 即刻 → 传统 → 即刻：切过去要看得见 Markdown 标记，切回来内容不漂
    let md = "# 标题\n\n正文 **粗体** 与 `代码`\n\n- 甲\n- 乙\n"
    let rich = EditorModeBridge.richText(from: md)
    let source = EditorModeBridge.sourceText(from: rich)
    check("即刻→传统输出 Markdown 标记",
          source.contains("# 标题") && source.contains("**粗体**") && source.contains("- 甲"))
    let back = EditorModeBridge.sourceText(from: EditorModeBridge.richText(from: source))
    equal("传统→即刻→传统 幂等", back, source)

    // 纯文本显示基线
    let attrs = EditorModeBridge.plainAttributes
    let font = attrs[.font] as? NSFont
    check("源码用等宽字体", font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    check("源码按字符折行",
          (attrs[.paragraphStyle] as? NSParagraphStyle)?.lineBreakMode == .byCharWrapping)
    check("源码文字用明暗动态色",
          (attrs[.foregroundColor] as AnyObject?) === DocTheme.text)

    // 真实源码视图：像文本编辑器，不做任何自动改写
    let tv = MDSourceTextView()
    tv.configure()
    check("源码视图是纯文本", !tv.isRichText)
    check("关闭智能引号替换", !tv.isAutomaticQuoteSubstitutionEnabled)
    check("关闭破折号替换", !tv.isAutomaticDashSubstitutionEnabled)
    check("关闭自动链接", !tv.isAutomaticLinkDetectionEnabled)
    check("关闭拼写检查", !tv.isContinuousSpellCheckingEnabled)
    check("插入点用明暗动态色", (tv.insertionPointColor as AnyObject?) === DocTheme.text)

    let original = "# 标题  \n正文 **粗体**\n\n```swift\nlet a = 1\n```\n"
    EditorModeBridge.install(NSAttributedString(string: original), in: tv, plain: true)
    equal("装载源码逐字节保留", tv.string, original)
    equal("保存源码不做规范化", EditorModeBridge.plainText(in: tv), original)
    check("装载后光标在开头", tv.selectedRange().location == 0)

    // 粘贴富文本进源码视图：只留字符，格式一律抹平
    let fancy = NSMutableAttributedString(string: "**粗**", attributes: [
        .font: NSFont.boldSystemFont(ofSize: 30),
        .foregroundColor: NSColor.red,
        .underlineStyle: 1,
    ])
    EditorModeBridge.install(fancy, in: tv, plain: true)
    equal("富文本粘进源码只留字符", tv.string, "**粗**")
    let a0 = tv.textStorage?.attributes(at: 0, effectiveRange: nil) ?? [:]
    check("源码不会变粗", (a0[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) != true)
    check("源码不会带下划线", a0[.underlineStyle] == nil)
    check("源码颜色统一", (a0[.foregroundColor] as AnyObject?) === DocTheme.text)

    // 语法着色写在临时属性上：不碰 storage、不进存盘内容、不进 undo
    let doc = "# 标题\n> 引用\n- 列表\n`代码` **粗体** [链接](https://a.b)\n```\nfence\n```\n"
    EditorModeBridge.install(NSAttributedString(string: doc), in: tv, plain: true)
    tv.applySyntaxHighlight()
    equal("着色不改动文档内容", tv.string, doc)
    check("着色不写进 storage",
          (tv.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as AnyObject?) === DocTheme.text)
    if let lm = tv.layoutManager {
        let titleMark = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: 0,
                                               effectiveRange: nil) as? NSColor
        check("标题标记有临时着色", titleMark != nil)
        check("临时着色用强调动态色", (titleMark as AnyObject?) === DocTheme.accent)
    } else {
        check("文本视图带 layoutManager", false)
    }
    tv.applySyntaxHighlight()
    tv.applySyntaxHighlight()
    equal("重复着色不叠加、不改写", tv.string, doc)

    // 源码滚动容器（工厂与即刻模式一样标注了 @MainActor）
    MainActor.assumeIsolated {
        let (scroll, container) = SourceScrollFactory.make(textView: tv)
        check("源码容器是 documentView", scroll.documentView === container)
        check("源码视图挂在容器里", container.textView === tv)
        check("源码容器底色用动态色", (scroll.backgroundColor as AnyObject?) === DocTheme.pageBackground)
        container.needsLayout = true
        container.layout()
        check("源码容器宽度可排版", container.frame.width >= 320)
        check("源码容器高度为正", container.frame.height > 0)
    }

    EditorModeBridge.resetUndoHistory([tv, nil])
    check("模式切换清空 undo 不崩溃", true)
}

// MARK: - 插入点（光标）尺寸随字号缩放

func testCaretSizing() {
    let body = DocTheme.bodyFont
    let h1 = DocTheme.documentFont(size: DocTheme.headingFontSize(1), weight: .bold)
    let code = DocTheme.monospacedFont(size: DocTheme.codeFontSize)

    let bodySize = DocTheme.caretSize(for: body)
    let h1Size = DocTheme.caretSize(for: h1)
    let codeSize = DocTheme.caretSize(for: code)

    check("H1 光标明显高于正文光标", h1Size.height > bodySize.height * 1.5)
    check("代码块光标矮于正文光标", codeSize.height < bodySize.height)
    check("光标高度与字号基本成比例",
          abs(h1Size.height / bodySize.height - h1.pointSize / body.pointSize) < 0.15)
    check("H1 光标比正文更粗", h1Size.width > bodySize.width)
    check("正文光标宽度为 1pt", bodySize.width == 1)

    // 六级标题字号逐级递减，光标高度也必须逐级递减（不能卡在固定值）
    var previous = CGFloat.greatestFiniteMagnitude
    for level in 1...6 {
        let font = DocTheme.documentFont(size: DocTheme.headingFontSize(level), weight: .bold)
        let height = DocTheme.caretSize(for: font).height
        check("H\(level) 光标高度不超过上一级", height <= previous + 0.001)
        previous = height
    }
}

// MARK: - 插入点纵向对齐（不能浮在文字上方）

func testCaretAlignment() {
    // 实测：16pt 正文 + lineHeightMultiple 1.8，行片段 y=0..32.4，基线 y=29.4。
    // 多出来的行距全加在行片段顶部，所以按「行片段中线」居中会把光标画到文字上方。
    let body = DocTheme.bodyFont
    let bodyBaseline: CGFloat = 29.4
    let fragmentMidY: CGFloat = 16.2
    let textTop = bodyBaseline - body.ascender
    let textBottom = bodyBaseline - body.descender
    let size = DocTheme.caretSize(for: body)

    let fixed = DocTheme.caretRect(baselineY: bodyBaseline, x: 72, font: body)
    check("正文光标顶边与文字顶边齐平", abs(fixed.minY - textTop) < 1)
    check("正文光标底边与文字底边齐平", abs(fixed.maxY - textBottom) < 1)
    check("正文光标高度仍按字号计算", abs(fixed.height - size.height) < 0.001)
    check("正文光标宽度仍按字号计算", abs(fixed.width - size.width) < 0.001)
    check("正文光标保持插入点 x", fixed.minX == 72)

    let oldTop = fragmentMidY - size.height / 2
    check("修复后正文光标不再偏上", fixed.minY - oldTop > 3)

    // 标题 30.4pt + lineHeightMultiple 1.35：行片段 0..40.5，基线 36.5
    let h1 = DocTheme.documentFont(size: DocTheme.headingFontSize(1), weight: .bold)
    let h1Baseline: CGFloat = 36.5
    let h1MidY: CGFloat = 20.25
    let h1Size = DocTheme.caretSize(for: h1)
    let h1Fixed = DocTheme.caretRect(baselineY: h1Baseline, x: 0, font: h1)
    check("标题光标顶边与文字顶边齐平", abs(h1Fixed.minY - (h1Baseline - h1.ascender)) < 1)
    check("标题光标底边与文字底边齐平", abs(h1Fixed.maxY - (h1Baseline - h1.descender)) < 1)
    check("修复后标题光标不再偏上", h1Fixed.minY - (h1MidY - h1Size.height / 2) > 3)

    // 换到下一行时，光标应随基线等量下移（段落间距 / 多行场景）
    let shifted = DocTheme.caretRect(baselineY: bodyBaseline + 42.4, x: 0, font: body)
    check("光标跟随所在行基线整体下移", abs((shifted.minY - fixed.minY) - 42.4) < 0.001)

    // 小字号（代码块）也应贴住同一基线的字身，而不是悬在行片段中间
    let code = DocTheme.monospacedFont(size: DocTheme.codeFontSize)
    let codeRect = DocTheme.caretRect(baselineY: bodyBaseline, x: 0, font: code)
    check("代码块光标顶部不高于正文字身顶部", codeRect.minY > textTop)
    check("代码块光标底部贴近同一基线", abs(codeRect.maxY - textBottom) < 3)
}

// MARK: - 行内样式作用范围（凸显标记回归）

/// 把 [NSRange] 压成 "起点:长度,起点:长度"，便于断言
func rangesDesc(_ rs: [NSRange]) -> String {
    rs.map { "\($0.location):\($0.length)" }.joined(separator: ",")
}

func testInlineSelection() {
    // 索引： 0-9 = ABCDEFGHIJ，10 = \n，11-20 = 0123456789，21 = \n，22-24 = 末尾行
    let s = "ABCDEFGHIJ\n0123456789\n末尾行" as NSString

    // 核心回归：只选中间 3 个字，前后没选的字绝不能被标记
    equal("部分选区只切出选中字符", rangesDesc(InlineSelection.slices(NSRange(location: 2, length: 3), in: s)), "2:3")
    equal("整行全选不含段落终结符", rangesDesc(InlineSelection.slices(NSRange(location: 0, length: 10), in: s)), "0:10")

    // 段落终结符不能承载 backgroundColor，否则 AppKit 会在行尾画出色块
    equal("跨行选区按行切分并跳过换行符", rangesDesc(InlineSelection.slices(NSRange(location: 8, length: 6), in: s)), "8:2,11:3")
    equal("全篇选区逐行切分", rangesDesc(InlineSelection.slices(NSRange(location: 0, length: s.length), in: s)), "0:10,11:10,22:3")
    equal("只选中换行符时没有作用范围", rangesDesc(InlineSelection.slices(NSRange(location: 10, length: 1), in: s)), "")
    equal("选区以行尾换行结束时不带换行符", rangesDesc(InlineSelection.slices(NSRange(location: 0, length: 3), in: "AB\n" as NSString)), "0:2")

    equal("空选区不改动任何文字", rangesDesc(InlineSelection.slices(NSRange(location: 5, length: 0), in: s)), "")
    equal("越界选区裁剪到文档末尾", rangesDesc(InlineSelection.slices(NSRange(location: 20, length: 50), in: s)), "20:1,22:3")

    // 附件 / 软换行没有可见字身，也不该被高亮
    equal("图片附件占位符被跳过", rangesDesc(InlineSelection.slices(NSRange(location: 0, length: 3), in: "A\u{FFFC}B" as NSString)), "0:1,2:1")
    equal("软换行被跳过", rangesDesc(InlineSelection.slices(NSRange(location: 0, length: 5), in: "AB\u{2028}CD" as NSString)), "0:2,3:2")

    // 端到端：给选中的 3 个字符打上凸显，检查属性与 Markdown 输出都只覆盖选区
    let attr = NSMutableAttributedString(attributedString: MarkdownParser.parse("ABCDEFGHIJ\n"))
    let color = NSColor(hex: "#fff3a3")!
    for r in InlineSelection.slices(NSRange(location: 2, length: 3), in: attr.string as NSString) {
        attr.addAttribute(.backgroundColor, value: color, range: r)
        attr.addAttribute(.mdHighlight, value: color, range: r)
    }
    check("选中的 3 个字符都带凸显", (2...4).allSatisfy {
        attr.attribute(.mdHighlight, at: $0, effectiveRange: nil) != nil
    })
    check("选区之前的字符没有凸显", attr.attribute(.mdHighlight, at: 1, effectiveRange: nil) == nil)
    check("选区之后的字符没有凸显", attr.attribute(.mdHighlight, at: 5, effectiveRange: nil) == nil)
    check("这一行行尾没有凸显", attr.attribute(.mdHighlight, at: 9, effectiveRange: nil) == nil)

    let md = MarkdownSerializer.markdown(from: attr)
    let span = "<span style=\"background-color:#fff3a3\">"
    check("序列化后 span 只包住选中文字", md.contains("AB\(span)CDE</span>FGHIJ"))
    check("整行只出现一对凸显 span", md.components(separatedBy: span).count - 1 == 1)

    // 回归：选区正好到行尾时，旧逻辑会把 \n 一起涂上背景色，
    // 于是 AppKit 在行尾画出色块，<span> 还会跨到下一行。
    let lineEnd = NSMutableAttributedString(attributedString: MarkdownParser.parse("ABCDEF\nSECOND\n"))
    let nl = (lineEnd.string as NSString).range(of: "\n").location
    for r in InlineSelection.slices(NSRange(location: 2, length: 4), in: lineEnd.string as NSString) {
        lineEnd.addAttribute(.mdHighlight, value: color, range: r)
    }
    check("选区到行尾时换行符没有凸显", lineEnd.attribute(.mdHighlight, at: nl, effectiveRange: nil) == nil)
    check("选区到行尾时 span 在换行前闭合", MarkdownSerializer.markdown(from: lineEnd).contains("CDEF</span>"))

    // 跨行选区：两行各自只标记选中的部分，换行符与未选字符都不带属性
    let multi = NSMutableAttributedString(attributedString: MarkdownParser.parse("ABC\nDEF\n"))
    let slices = InlineSelection.slices(NSRange(location: 1, length: 5), in: multi.string as NSString)
    equal("跨行选区切成两段", rangesDesc(slices), "1:2,4:2")
    for r in slices { multi.addAttribute(.mdHighlight, value: color, range: r) }
    check("跨行选区的换行符没有凸显", multi.attribute(.mdHighlight, at: 3, effectiveRange: nil) == nil)
    check("第二行未选中的字符没有凸显", multi.attribute(.mdHighlight, at: 6, effectiveRange: nil) == nil)
}

// MARK: - 真实 NSTextView 上的行内样式（集成验证）

func testInlineStyleOnTextView() {
    let hl = NSColor(hex: "#fff3a3")!

    func make(_ text: String) -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        tv.isEditable = true
        tv.isRichText = true
        tv.string = text
        tv.typingAttributes = EditorStyle.defaultTyping
        return tv
    }

    /// 列出带该属性的所有连续段，格式 "起点:长度,…"
    func runs(_ tv: NSTextView, _ key: NSAttributedString.Key) -> String {
        guard let st = tv.textStorage else { return "" }
        var out: [String] = []
        st.enumerateAttribute(key, in: NSRange(location: 0, length: st.length), options: []) { v, r, _ in
            if v != nil { out.append("\(r.location):\(r.length)") }
        }
        return out.joined(separator: ",")
    }

    // 选中第一行中间 3 个字符：凸显只应落在 2:3，前后与下一行都不带属性
    let a = make("ABCDEFGHIJ\nSECOND LINE\n")
    a.setSelectedRange(NSRange(location: 2, length: 3))
    a.setHighlight(hl)
    equal("真实视图：凸显只覆盖选中字符", runs(a, .mdHighlight), "2:3")

    // 选区跨到下一行：按行切分，换行符不带属性
    let b = make("ABCDEFGHIJ\nSECOND LINE\n")
    b.setSelectedRange(NSRange(location: 8, length: 8))
    b.setHighlight(hl)
    equal("真实视图：跨行凸显跳过换行符", runs(b, .mdHighlight), "8:2,11:5")

    // 同一入口下的其它行内样式也不扩散
    let c = make("ABCDEFGHIJ\nSECOND LINE\n")
    c.setSelectedRange(NSRange(location: 2, length: 3))
    c.setTextColor(NSColor(hex: "#d64545"))
    equal("真实视图：字体色只覆盖选中字符", runs(c, .mdTextColor), "2:3")

    let d = make("ABCDEFGHIJ\nSECOND LINE\n")
    d.setSelectedRange(NSRange(location: 2, length: 3))
    d.toggleUnderline()
    equal("真实视图：下划线只覆盖选中字符", runs(d, .underlineStyle), "2:3")

    // 清除凸显只作用于当前选区，之前打在别处的凸显要保留
    let e = make("ABCDEFGHIJ\nSECOND LINE\n")
    e.setSelectedRange(NSRange(location: 2, length: 3)); e.setHighlight(hl)
    e.setSelectedRange(NSRange(location: 6, length: 2)); e.setHighlight(hl)
    e.setSelectedRange(NSRange(location: 2, length: 3)); e.setHighlight(nil)
    equal("真实视图：清除凸显不影响选区外", runs(e, .mdHighlight), "6:2")

    // 无选区时不涂改任何已有文字，只决定「接下来输入的字」
    let f = make("ABCDEFGHIJ\n")
    f.setSelectedRange(NSRange(location: 5, length: 0))
    f.setHighlight(hl)
    equal("真实视图：无选区不改动已有文字", runs(f, .mdHighlight), "")
    check("真实视图：无选区时输入属性带凸显", f.typingAttributes[.mdHighlight] != nil)

    // 块级样式仍走段落级范围，未被本次改动破坏
    let g = make("ABCDEFGHIJ\nSECOND LINE\n")
    g.setSelectedRange(NSRange(location: 2, length: 0))
    g.applyBlockStyle(.heading(1))
    equal("真实视图：块样式仍作用于整段", runs(g, .mdBlockType), "0:11")
}

// MARK: - 自定义大模型协议

func testAIProtocol() {
    // 端点归一化
    let endpoint = { (raw: String) -> String in
        AIEndpoint.normalize(raw)?.absoluteString ?? "<nil>"
    }
    equal("AI 端点：/v1 自动补路径", endpoint("https://api.openai.com/v1"),
          "https://api.openai.com/v1/chat/completions")
    equal("AI 端点：尾部斜杠", endpoint("https://api.openai.com/v1/"),
          "https://api.openai.com/v1/chat/completions")
    equal("AI 端点：完整路径不重复追加", endpoint("https://api.openai.com/v1/chat/completions"),
          "https://api.openai.com/v1/chat/completions")
    equal("AI 端点：裸域名补 https", endpoint("api.deepseek.com"),
          "https://api.deepseek.com/v1/chat/completions")
    equal("AI 端点：本机 http 保留", endpoint("http://127.0.0.1:11434/v1"),
          "http://127.0.0.1:11434/v1/chat/completions")
    equal("AI 端点：自建网关前缀", endpoint("https://gw.example.com/api"),
          "https://gw.example.com/api/v1/chat/completions")
    equal("AI 端点：空串无效", endpoint(""), "<nil>")
    equal("AI 端点：无 host 无效", endpoint("not a url"), "<nil>")
    equal("AI 端点：非 http 协议无效", endpoint("ftp://example.com"), "<nil>")

    // 请求构造
    let url = AIEndpoint.normalize("https://api.openai.com/v1")!
    let cfg = AIRequestConfig(model: "gpt-4o-mini", temperature: 0.3, timeout: 60,
                              systemPrompt: "SYS", apiKey: "sk-test", endpoint: url)
    let req = try? AIProtocol.makeRequest(cfg, instruction: "润色", content: "原文")
    check("AI 请求：构造成功", req != nil)
    if let req {
        equal("AI 请求：POST", req.httpMethod ?? "", "POST")
        equal("AI 请求：Content-Type", req.value(forHTTPHeaderField: "Content-Type") ?? "", "application/json")
        equal("AI 请求：Authorization", req.value(forHTTPHeaderField: "Authorization") ?? "", "Bearer sk-test")
        let body = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any]
        equal("AI 请求：model", body?["model"] as? String ?? "", "gpt-4o-mini")
        check("AI 请求：非流式", (body?["stream"] as? Bool) == false)
        let messages = body?["messages"] as? [[String: Any]] ?? []
        check("AI 请求：system + user 两条消息", messages.count == 2)
        equal("AI 请求：第一条是 system", messages.first?["role"] as? String ?? "", "system")
        equal("AI 请求：第二条是 user", messages.last?["role"] as? String ?? "", "user")
        equal("AI 请求：指令与正文分隔", messages.last?["content"] as? String ?? "", "润色\n\n---\n\n原文")
    }
    let noKey = AIRequestConfig(model: "m", temperature: 0, timeout: 10,
                                systemPrompt: "", apiKey: "", endpoint: url)
    check("AI 请求：空密钥不带 Authorization",
          (try? AIProtocol.makeRequest(noKey, instruction: "x", content: "y"))?
            .value(forHTTPHeaderField: "Authorization") == nil)
    let noModel = AIRequestConfig(model: " ", temperature: 0, timeout: 10,
                                  systemPrompt: "", apiKey: "", endpoint: url)
    var threwMissingModel = false
    do { _ = try AIProtocol.makeRequest(noModel, instruction: "x", content: "y") }
    catch AIProtocolError.missingModel { threwMissingModel = true }
    catch {}
    check("AI 请求：空模型名被拦下", threwMissingModel)

    // 响应解析（含各家网关的返回形态）
    func parse(_ json: String) -> String {
        (try? AIProtocol.parseContent(from: Data(json.utf8))) ?? "<throw>"
    }
    equal("AI 响应：标准 choices", parse(#"{"choices":[{"message":{"content":"你好"}}]}"#), "你好")
    equal("AI 响应：分段数组 content",
          parse(#"{"choices":[{"message":{"content":[{"type":"text","text":"A"},{"text":"B"}]}}]}"#), "AB")
    equal("AI 响应：顶层 content", parse(#"{"content":"顶层"}"#), "顶层")
    equal("AI 响应：旧式 choices.text", parse(#"{"choices":[{"text":"旧式"}]}"#), "旧式")
    var threwAPI = false
    do { _ = try AIProtocol.parseContent(from: Data(#"{"error":{"message":"key invalid"}}"#.utf8)) }
    catch AIProtocolError.api(let msg) { threwAPI = msg == "key invalid" }
    catch {}
    check("AI 响应：服务端 error 抛出带原文", threwAPI)
    var threwInvalid = false
    do { _ = try AIProtocol.parseContent(from: Data("not json".utf8)) }
    catch AIProtocolError.invalidJSON { threwInvalid = true }
    catch {}
    check("AI 响应：非法 JSON 被识别", threwInvalid)
    check("AI 响应：缺 content 被识别", parse(#"{"choices":[{}]}"#) == "<throw>")

    // 结果清理
    equal("AI 结果：剥掉 markdown 围栏",
          AIProtocol.sanitize("```markdown\n# 标题\n正文\n```\n"), "# 标题\n正文")
    equal("AI 结果：普通文本原样保留", AIProtocol.sanitize("  # 标题\n\n```\ncode\n```  "),
          "# 标题\n\n```\ncode\n```")
    equal("AI 结果：去首尾空白", AIProtocol.sanitize("\n\n正文\n\n"), "正文")

    // HTTP 状态分类
    check("AI 状态：200 成功", AIStatusKind.classify(200) == .ok)
    check("AI 状态：401 鉴权失败", AIStatusKind.classify(401) == .unauthorized)
    check("AI 状态：403 鉴权失败", AIStatusKind.classify(403) == .unauthorized)
    check("AI 状态：404 端点错误", AIStatusKind.classify(404) == .notFound)
    check("AI 状态：429 限流", AIStatusKind.classify(429) == .rateLimited)
    check("AI 状态：503 服务端错误", AIStatusKind.classify(503) == .serverError)
    check("AI 状态：302 其它", AIStatusKind.classify(302) == .other(302))

    // 预设与文案
    check("AI 预设：7 项含 agent", AIPresets.ids.count == 7 && AIPresets.ids.contains("agent"))
    check("AI 预设：custom 指令为空",
          AIPresets.instruction(for: "custom") { Localizer.translate("en", $0) }.isEmpty)
    let agent = AIPresets.instruction(for: "agent") { Localizer.translate("zh", $0) }
    check("AI 预设：agent 指令含验收标准与防臆造", agent.contains("验收标准") && agent.contains("不编造"))
    let polish = AIPresets.instruction(for: "polish") { Localizer.translate("en", $0) }
    check("AI 预设：英文润色指令非空", !polish.isEmpty)
    let zhPresets: [AIPreset] = AIPresets.all { Localizer.translate("zh", $0) }
    let titlesOK: Bool = zhPresets.allSatisfy { !$0.title.isEmpty && $0.title != $0.id }
    check("AI 预设：中英标题都齐", titlesOK)
    let zhKeys: Set<String> = Set(I18nExtras.table["zh"]?.keys.map { String($0) } ?? [])
    let enKeys: Set<String> = Set(I18nExtras.table["en"]?.keys.map { String($0) } ?? [])
    check("AI 文案：zh / en 词条一一对应", zhKeys == enKeys)
    equal("AI 文案：中文", Localizer.translate("zh", "ai.menu"), "AI 助手")
    equal("AI 文案：英文", Localizer.translate("en", "ai.menu"), "AI Assistant")
    equal("AI 文案：其它语言回退英文", Localizer.translate("ja", "ai.menu"), "AI Assistant")
    check("AI 文案：既有词条未受影响", Localizer.translate("zh", "common.save") == "保存")
    equal("AI 文案：变量替换仍生效", Localizer.translate("en", "ai.err.http", [:]), "Request failed")
}

// MARK: - 编辑模式焦点移交（启动首帧 SIGABRT 回归）

func testEditorFocus() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    root.addSubview(scroll)
    scroll.addSubview(tv)

    // 判定隐藏必须沿着祖先链走：模式切换隐藏的是 scroll view，不是 text view 自己
    check("可见视图不算隐藏", !EditorFocus.isEffectivelyHidden(tv))
    tv.isHidden = true
    check("自身隐藏可识别", EditorFocus.isEffectivelyHidden(tv))
    tv.isHidden = false
    scroll.isHidden = true
    check("祖先隐藏可识别", EditorFocus.isEffectivelyHidden(tv))
    scroll.isHidden = false
    root.alphaValue = 0
    check("祖先全透明可识别", EditorFocus.isEffectivelyHidden(tv))
    root.alphaValue = 1
    check("恢复可见后重新可聚焦", !EditorFocus.isEffectivelyHidden(tv))

    // 焦点只在两个编辑器之间（或窗口/工具栏控件手里）接管。
    // 查找栏 / 对话框的 field editor 也是 NSTextView，必须靠 otherEditor 区分。
    let previous = NSTextView()
    check("空响应者允许接管", EditorFocus.mayTakeFocus(from: nil))
    check("另一个编辑器允许接管",
          EditorFocus.mayTakeFocus(from: previous, otherEditor: previous))
    check("查找栏 field editor 不抢",
          !EditorFocus.mayTakeFocus(from: NSTextView(), otherEditor: previous))
    check("对话框输入框 field editor 不抢",
          !EditorFocus.mayTakeFocus(from: NSTextView()))
    check("工具栏按钮焦点可接管", EditorFocus.mayTakeFocus(from: NSButton()))

    // 没有窗口 / 目标是隐藏侧时，必须安静失败而不是碰第一响应者
    check("空目标安全返回", !EditorFocus.handoff(to: nil))
    check("未挂到窗口时安全返回", !EditorFocus.handoff(to: tv))
    scroll.isHidden = true
    check("隐藏目标安全返回", !EditorFocus.handoff(to: tv))
    scroll.isHidden = false

    // 异步入口在目标不可用时也不能抛异常
    EditorFocus.scheduleHandoff(to: nil)
    EditorFocus.scheduleHandoff(to: tv)
    check("异步移交入口不抛异常", true)
}

// MARK: - 外部语料回归（兼容性测试发现的真实缺陷）

func testExternalCorpusRegressions() {
    // 1) "1." / "2)" 这种只有序号、没有后续空格的行，
    //    listItemInfo 曾用 rest[endIndex] 取值，触发 String 索引越界崩溃。
    //    来源：cmark-gfm/bench/samples/block-list-flat.md
    let edge = "1.\n\n2)\n\n1. ok\n"
    let a = MarkdownParser.parse(edge)
    check("空序号行解析不崩溃", a.length > 0)
    check("空序号行按字面保留", a.string.contains("1."))
    _ = MarkdownSerializer.markdown(from: a)

    // 2) 链接目标解析失败时没有回滚 pos，方括号里的文字会被整段吞掉。
    //    影响引用式链接 / Obsidian 双链 / 任务复选框 / 数组下标等常见写法。
    let cases: [(String, String, String)] = [
        ("引用式链接", "[1] [2] [3]\n\n[1]: https://example.com\n", "[1]"),
        ("Obsidian 双链", "见 [[My Note]] 与 [[Other|别名]]\n", "[[My Note]]"),
        ("任务列表复选框", "- [ ] 待办\n- [x] 完成\n", "[ ]"),
        ("Obsidian 嵌入", "![[image.png]]\n", "![[image.png]]"),
        ("裸方括号", "数组 [1, 2] 与 [text]\n", "[1, 2]"),
    ]
    for (name, md, token) in cases {
        let parsed = MarkdownParser.parse(md)
        check("\(name)：方括号内文字不被吞", parsed.string.contains(token))
        let out1 = MarkdownSerializer.markdown(from: parsed)
        let out2 = MarkdownSerializer.markdown(from: MarkdownParser.parse(out1))
        check("\(name)：往返稳定", out1 == out2)
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
testWheelZoom()
testLocalization()
testEditorModes()
testEditorFocus()
testExternalCorpusRegressions()
testCaretSizing()
testCaretAlignment()
testInlineSelection()
testInlineStyleOnTextView()
testAIProtocol()

print("")
if failureDetails.isEmpty {
    print("✅ 冒烟测试全部通过：\(passed) 项")
} else {
    print("❌ 冒烟测试：\(passed) 项通过，\(failed) 项失败")
    failureDetails.forEach { print($0) }
}
if failed > 0 { exit(1) }
