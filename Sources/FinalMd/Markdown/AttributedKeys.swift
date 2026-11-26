//
//  AttributedKeys.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  文档内部表示：NSAttributedString + 一组自定义属性，用来记住 Markdown 的「块级语义」。
//  （对应 Electron 版的 ProseMirror 节点类型：heading / blockquote / codeBlock / listItem …）
//
//  行内样式一律使用 AppKit 标准属性，这样 ⌘B / ⌘I / ⌘U 等系统快捷键天然可用：
//    · 加粗      → 字体 trait .bold
//    · 斜体      → 字体 trait .italic
//    · 下划线    → .underlineStyle
//    · 删除线    → .strikethroughStyle
//    · 字体颜色  → .foregroundColor
//    · 突出显示  → .backgroundColor
//    · 链接      → .link
//    · 行内代码  → 自定义 .mdInlineCode + 等宽字体
//

import AppKit

// MARK: - 自定义属性键

extension NSAttributedString.Key {
    /// 块级类型："p" / "h1"…"h6" / "quote" / "code"
    static let mdBlockType = NSAttributedString.Key("finalmd.blockType")
    /// 列表项信息 MDListItem
    static let mdListItem = NSAttributedString.Key("finalmd.listItem")
    /// 行内代码
    static let mdInlineCode = NSAttributedString.Key("finalmd.inlineCode")
    /// 表格标题行
    static let mdTableHeader = NSAttributedString.Key("finalmd.tableHeader")
    /// 代码块语言（```swift 里的 swift）
    static let mdCodeLanguage = NSAttributedString.Key("finalmd.codeLanguage")
    /// 代码块终结换行：内容里每个 \n 都是普通字符，仅块尾这个 \n 带此标记。
    /// blocks() 靠它区分「相邻两个代码块」与「一个代码块的多个段落」，
    /// 否则 "~~~\n~~~\n~~~" 这类相邻空代码块会被并成一块。
    static let mdCodeEnd = NSAttributedString.Key("finalmd.codeEnd")
    /// 空代码块占位标记：显示需要非空段落，空内容存 " " 并打此标记，
    /// 提取时还原为 ""（否则 HTML 导出多印一个空格）。
    static let mdCodeEmpty = NSAttributedString.Key("finalmd.codeEmpty")
    /// 引用块原始源码（去掉 "> " 前缀的正文）。HTML 导出按块递归重解析它，
    /// 才能还原 **粗体** / 围栏 / 嵌套列表等内层语法——引用在存储里只是单段富文本。
    static let mdQuoteSource = NSAttributedString.Key("finalmd.quoteSource")
    /// 引用块原始行（含 `>` 标记与懒续行原文）：未编辑时序列化逐字写回，
    /// 保住懒续行缩进与 `>>` 紧写形式（mdQuoteSource 是剥掉标记的递归解析源）。
    static let mdQuoteRaw = NSAttributedString.Key("finalmd.quoteRaw")
    /// 用户显式设置的字体颜色（NSColor）。与 .foregroundColor 成对写入，
    /// 序列化时只读这个键，避免把「默认正文色」误判成用户设的颜色而输出多余的 span
    static let mdTextColor = NSAttributedString.Key("finalmd.textColor")
    /// 用户显式设置的突出显示色（NSColor），同上
    static let mdHighlight = NSAttributedString.Key("finalmd.highlight")
    /// 结构性加粗：标题/表头靠字号+字重呈现，但这层加粗不是用户敲的 **，
    /// 打上标记后才能在「标题改回正文」时准确剥掉，避免把 # 标题 变成 **正文**
    static let mdStructuralBold = NSAttributedString.Key("finalmd.structuralBold")
    /// 用户手写强调（`**x**` / `<strong>`）产生的粗体。表头 / 标题的排版加粗
    /// 会打 mdStructuralBold 抑制 `**` 回写，但用户粗体必须保住记号，
    /// 否则 `**bold**` 进表头一轮就被吞掉。
    static let mdUserBold = NSAttributedString.Key("finalmd.userBold")
    /// 原样透传块的类型（MDRawKind.rawValue）。frontmatter / 原始 HTML / 引用式链接定义
    /// 这类外部语法 FinalMd 不渲染，但必须逐字保住，不能在保存时被拆行或转义。
    static let mdRawKind = NSAttributedString.Key("finalmd.rawKind")
    /// 原样透传块的编号。同一个块的每一行（含空行）共享一个 ID，
    /// 序列化时按「连续且同 ID」把段落重新拼回一整块，避免相邻透传块粘连。
    static let mdRawID = NSAttributedString.Key("finalmd.rawID")
    /// Obsidian 双链 / 嵌入（MDWikiLink）。属性里记住原始语法与解析时的显示文字，
    /// 序列化时若显示文字未被改动就逐字输出原语法。
    static let mdWikiLink = NSAttributedString.Key("finalmd.wikiLink")
    /// Obsidian Callout 块编号：同一个 Callout 的每一行共享一个 ID
    static let mdCalloutID = NSAttributedString.Key("finalmd.calloutID")
    /// Callout 类型（NOTE / TIP / WARNING …，统一大写）
    static let mdCalloutKind = NSAttributedString.Key("finalmd.calloutKind")
    /// Callout 折叠标记："+"（默认展开）/ "-"（默认折叠）/ ""（不折叠）
    static let mdCalloutFold = NSAttributedString.Key("finalmd.calloutFold")
    /// 任务列表复选框 `[ ]` / `[x]`。显示文字就是源码本身，标记它只是为了
    /// 序列化时跳过方括号转义，避免写成 `\[ \]` 后在 Obsidian / GFM 里失效。
    static let mdTaskBox = NSAttributedString.Key("finalmd.taskBox")
    /// 「长得像引用式链接定义、但语法不合法」的整行。它仍是普通段落（结构识别
    /// 算 p），但显示与序列化都逐字保留：按普通段落走 InlineSerializer 会把
    /// `[` `]` 转义成 `\[` `\]`，反而改写原文。
    static let mdVerbatimLine = NSAttributedString.Key("finalmd.verbatimLine")
    /// Callout 行的原始源码。行内强调现在会真解析成富文本，另存原行 +
    /// 解析后显示文字快照：只要显示文字没被改过，序列化仍逐字输出原行。
    static let mdCalloutSource = NSAttributedString.Key("finalmd.calloutSource")
    /// Callout 行解析后的显示文字快照，用来判断用户是否编辑过这一行。
    static let mdCalloutDisplay = NSAttributedString.Key("finalmd.calloutDisplay")
    /// Callout 行解析后的格式指纹（与 mdEmphasisTraits 同口径）。
    /// 只改格式不改文字时也要让快照失效：否则 ⌘B / ⌘I 的改动会被旧源码盖掉。
    /// 是否按指纹重建由 MarkdownSerializer.calloutFormatEdits 开关决定。
    static let mdCalloutTraits = NSAttributedString.Key("finalmd.calloutTraits")
    /// 含强调的行内源码快照。CommonMark 的 `***a ***b***` 是树形嵌套，
    /// 而富文本只有粗/斜两个 trait，无法表达嵌套层级。存下原行 + 解析后的
    /// 显示文字：未编辑时逐字输出原行（语义与写法全保住），编辑后才按 trait 重建。
    static let mdEmphasisSource = NSAttributedString.Key("finalmd.emphasisSource")
    /// 强调行解析后的显示文字快照，用来判断用户是否编辑过这一行。
    static let mdEmphasisDisplay = NSAttributedString.Key("finalmd.emphasisDisplay")
    /// 强调行解析后的格式指纹（粗/斜/下划线/删除线/行内代码/字体色/高亮/链接）：
    /// 只改格式不改文字时也要让快照失效，否则用户按 ⌘B / 改色后的改动会被旧源码盖掉
    /// （与 Callout 的同类边界）。
    static let mdEmphasisTraits = NSAttributedString.Key("finalmd.emphasisTraits")
    /// 逐行源码快照（三个平行 [String]）：整块被编辑时按**行粒度**重建——
    /// 文本与指纹都未变的行逐字写回，只有被改过的行才按富文本重建。
    /// 仅当每行「独立解析的显示 == 块内显示行」（自包含，无跨行强调/链接）时才打。
    static let mdLineSources = NSAttributedString.Key("finalmd.lineSources")
    static let mdLineDisplays = NSAttributedString.Key("finalmd.lineDisplays")
    static let mdLineTraits = NSAttributedString.Key("finalmd.lineTraits")
    /// 引用逐行快照：source 是含 `>` 前缀与懒续行缩进的原始行，
    /// 编辑某一行不再改写兄弟行的写法（围栏 / `>>` / 缩进逐字保留）。
    static let mdQuoteLineSources = NSAttributedString.Key("finalmd.quoteLineSources")
    static let mdQuoteLineDisplays = NSAttributedString.Key("finalmd.quoteLineDisplays")
    static let mdQuoteLineTraits = NSAttributedString.Key("finalmd.quoteLineTraits")
    /// 显示行 ↔ 源行组映射（[[dispIdx, rawStart, rawEnd, contentIdx]]）：
    /// 跨行构造吞掉换行时（内层围栏被行内解析成代码 span）按组对齐，
    /// 编辑只替换内容行，围栏等结构行逐字保留。
    static let mdQuoteLineMap = NSAttributedString.Key("finalmd.quoteLineMap")
    /// 行内 HTML 原样透传片段（`<img …>`、`<code>…</code>`、`<a href><img></a>` 等
    /// 不渲染成富文本的部分）。显示文字就是源码本身，序列化逐字写回，
    /// 不经 escapeMarkdown，避免 `<` `>` `[` `]` 被防御性转义改写。
    static let mdInlineHTML = NSAttributedString.Key("finalmd.inlineHTML")
    /// 链接 / 图片的 title（`[t](u "title")` 里引号包住的部分）。
    /// 不存进 .link，否则 NSLink 点击会带着 title 拼进 URL；序列化时单独写回。
    static let mdLinkTitle = NSAttributedString.Key("finalmd.linkTitle")
}

// MARK: - 格式指纹

/// 逐字符编码格式状态：粗 / 斜体（B / I / X / -）+ 下划线 / 删除线 / 行内代码 /
/// 字体色 / 高亮 / 链接增量，用 U+1 分隔。解析器存入 `mdEmphasisTraits`，
/// 序列化器重算后比对，确保「只改格式不改文字」也能让源码快照失效——
/// 否则用户按 ⌘B / 改色后的改动会被旧源码盖掉。
func mdFormattingFingerprint(_ attr: NSAttributedString, length: Int) -> String {
    var out = ""
    out.reserveCapacity(length * 2)
    for i in 0..<length {
        let font = attr.attribute(.font, at: i, effectiveRange: nil) as? NSFont
        let traits = font?.fontDescriptor.symbolicTraits ?? []
        let bold = traits.contains(.bold)
        let italic = traits.contains(.italic)
        out.append(bold ? (italic ? "X" : "B") : (italic ? "I" : "-"))
        var extra = ""
        if let u = attr.attribute(.underlineStyle, at: i, effectiveRange: nil) as? Int, u != 0 {
            extra += "u"
        }
        if let s = attr.attribute(.strikethroughStyle, at: i, effectiveRange: nil) as? Int, s != 0 {
            extra += "s"
        }
        if (attr.attribute(.mdInlineCode, at: i, effectiveRange: nil) as? Bool) == true {
            extra += "c"
        }
        if let color = attr.attribute(.mdTextColor, at: i, effectiveRange: nil) as? NSColor {
            extra += "t" + color.hexString
        }
        if let hl = attr.attribute(.mdHighlight, at: i, effectiveRange: nil) as? NSColor {
            extra += "h" + hl.hexString
        }
        if let link = attr.attribute(.link, at: i, effectiveRange: nil) {
            extra += "l\(link)"
            if let t = attr.attribute(.mdLinkTitle, at: i, effectiveRange: nil) as? String, !t.isEmpty {
                extra += "|\(t)"
            }
        }
        out.append(extra)
        out.append("\u{1}")
    }
    return out
}

// MARK: - Obsidian 双链

/// `[[Note|别名]]` / `[[Note#标题]]` / `![[image.png|100]]` 的原始语法。
/// 显示文字不是源码本身，所以额外记住解析时的 display：序列化时若当前文字
/// 与 display 一致就输出 raw；用户改过显示文字就按新文字重建，绝不用旧源码覆盖编辑。
final class MDWikiLink: NSObject {
    let raw: String
    let target: String
    let suffix: String
    let alias: String
    let embedded: Bool
    let display: String

    init(raw: String, target: String, suffix: String, alias: String, embedded: Bool) {
        self.raw = raw
        self.target = target
        self.suffix = suffix
        self.alias = alias
        self.embedded = embedded
        self.display = alias.isEmpty ? (target + suffix) : alias
        super.init()
    }

    /// 显示文字被编辑后，用新文字重建一条等价的双链
    func rebuilt(display newText: String) -> String {
        let open = embedded ? "![[" : "[["
        let base = target + suffix
        if newText == base, alias.isEmpty { return open + base + "]]" }
        return open + base + "|" + newText + "]]"
    }
}

// MARK: - 原样透传块类型

/// 透传块在 HTML 导出时的处理方式不同：
/// frontmatter 与链接定义是元数据（不进正文），原始 HTML 要原样放进 <body>，
/// 缩进代码块去缩进后包成 <pre><code>。
enum MDRawKind: String {
    case frontmatter
    case html
    case definition
    /// CommonMark 4 空格 / tab 缩进代码块。按原始行逐字保存，
    /// 序列化时不能丢掉前导空格，否则下一轮会被当成普通段落。
    case indentedCode
    /// 列表项内的缩进行（CommonMark 容器块内容）：引用续行、属性行、嵌套源码等。
    /// 仍是上一个列表项的附属内容，按原始行逐字保存；序列化时不能当成独立
    /// 段落插空行，也不能让它重置有序列表编号。
    case listIndented
    /// 列表项内的缩进代码块：缩进达到「列表内容缩进 + 4」，结构上等价于 code。
    case listCode
}

// MARK: - 块级类型

enum MDBlockType: String {
    case paragraph = "p"
    case heading1 = "h1"
    case heading2 = "h2"
    case heading3 = "h3"
    case heading4 = "h4"
    case heading5 = "h5"
    case heading6 = "h6"
    case quote = "quote"
    case code = "code"
    /// 原样透传块：YAML/TOML frontmatter、原始 HTML 块、引用式链接定义。
    /// 解析时按原始行存进 storage，序列化时跳过行内解析与转义，逐字输出。
    case raw = "raw"
    /// Obsidian Callout：`> [!NOTE] 标题` + 后续 `> 内容`。
    /// 与 raw 一样按原始行保存并逐字输出，但带类型色与独立段落排版。
    case callout = "callout"

    var headingLevel: Int? {
        guard rawValue.hasPrefix("h"), let n = Int(rawValue.dropFirst()) else { return nil }
        return n
    }

    init(headingLevel: Int) {
        self = MDBlockType(rawValue: "h\(min(max(headingLevel, 1), 6))") ?? .heading1
    }
}

// MARK: - 列表项

/// 列表项标记：有序/无序 + 缩进层级 + 序号
final class MDListItem: NSObject {
    let ordered: Bool
    let level: Int
    let number: Int
    /// 解析时记下的原始前导空格数。序列化时优先用它，避免 4 空格缩进的
    /// 嵌套列表项被压成 2 空格/级；编辑器里新建的列表项为 nil，按 level 推算。
    /// 必须参与 isEqual / hash，否则 AppKit 合并相邻属性 run 时会串用旧缩进。
    let indent: Int?

    init(ordered: Bool, level: Int, number: Int = 1, indent: Int? = nil) {
        self.ordered = ordered
        self.level = max(level, 0)
        self.number = number
        self.indent = indent
        super.init()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MDListItem else { return false }
        // indent 必须参与相等性判断：NSAttributedString 会按 isEqual 合并相邻
        // 属性相同的 run，若忽略 indent，4 空格缩进的列表项会复用别的缩进值，
        // 写回时静默丢掉原始空格。
        return ordered == other.ordered && level == other.level
            && number == other.number && indent == other.indent
    }

    override var hash: Int {
        var h = Hasher()
        h.combine(ordered)
        h.combine(level)
        h.combine(number)
        h.combine(indent)
        return h.finalize()
    }
}

// MARK: - 图片附件

/// 图片附件：保留原始 src（data URL 或 http URL）、alt 与 title（图表配置写在 title 里）。
final class MDImageAttachment: NSTextAttachment {

    /// 图片源：Base64 Data URL 或 http(s) 链接
    var src: String
    /// 替代文字
    var alt: String
    /// title 属性——图表把配置编码后存在这里，随 .md 一起走
    var mdTitle: String

    /// HTML 导出用的替代文字：按 CommonMark 以标签内容的纯文本渲染
    /// （`![alt with *em*](x)` 的 alt 是 "alt with em"）。
    /// .alt 本身保留原始写法，供 Markdown 逐字往返。
    var altPlainText: String {
        InlineParser.parse(alt, base: [:]).string
    }

    /// 最大显示宽度（点）
    var maxWidth: CGFloat = 640

    init(src: String, alt: String = "", title: String = "", image: NSImage? = nil) {
        self.src = src
        self.alt = alt
        self.mdTitle = title
        super.init(data: nil, ofType: nil)
        if let image {
            self.image = image
        } else if let url = URL(string: src), url.scheme == "http" || url.scheme == "https" {
            // 远程图片异步加载：解析期绝不做同步网络 IO——连接黑洞会把整篇
            // 文档解析挂死（codimd 语料的远程截图 URL 即触发）。先空占位，
            // 取到图再刷新附件并广播通知。
            loadRemoteImage(from: url)
        } else {
            self.image = Self.image(from: src)
        }
        self.attachmentCell = MDImageAttachmentCell(owning: self)
    }

    /// 远程图片加载完成后广播（编辑器可据此触发重排）
    static let imageLoadedNotification = Notification.Name("finalmd.mdImageAttachmentLoaded")

    private func loadRemoteImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.image = img
                NotificationCenter.default.post(name: Self.imageLoadedNotification, object: self)
            }
        }.resume()
    }

    required init?(coder: NSCoder) {
        self.src = coder.decodeObject(forKey: "src") as? String ?? ""
        self.alt = coder.decodeObject(forKey: "alt") as? String ?? ""
        self.mdTitle = coder.decodeObject(forKey: "mdTitle") as? String ?? ""
        super.init(coder: coder)
        if self.image == nil { self.image = Self.image(from: src) }
        self.attachmentCell = MDImageAttachmentCell(owning: self)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(src, forKey: "src")
        coder.encode(alt, forKey: "alt")
        coder.encode(mdTitle, forKey: "mdTitle")
    }

    /// 从 data URL / 文件路径解析出 NSImage。
    /// http(s) 远程图不在此同步加载（连接黑洞会挂死解析）——init 里异步取。
    static func image(from src: String) -> NSImage? {
        if src.hasPrefix("data:"), let comma = src.firstIndex(of: ",") {
            let meta = String(src[src.startIndex..<comma])
            let payload = String(src[src.index(after: comma)...])
            guard meta.contains("base64"), let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
                return nil
            }
            return NSImage(data: data)
        }
        return NSImage(contentsOfFile: src)
    }

    /// 按容器宽度等比缩放，超宽图片自动收窄
    override func attachmentBounds(for textContainer: NSTextContainer?,
                                   proposedLineFragment lineFrag: NSRect,
                                   glyphPosition position: NSPoint,
                                   characterIndex charIndex: Int) -> NSRect {
        guard let image else {
            return NSRect(x: 0, y: -4, width: 16, height: 16)
        }
        let avail = max(min(lineFrag.width, maxWidth), 80)
        let scale = min(avail / image.size.width, 1)
        let w = image.size.width * scale
        let h = image.size.height * scale
        return NSRect(x: 0, y: -3, width: w, height: h)
    }
}

/// 图片附件单元格：用附件自身的 image 绘制，并画一个选中态描边
final class MDImageAttachmentCell: NSTextAttachmentCell {

    private weak var owner: MDImageAttachment?

    init(owning: MDImageAttachment) {
        self.owner = owning
        super.init(imageCell: nil)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var image: NSImage? {
        get { owner?.image ?? super.image }
        set { super.image = newValue }
    }

    override func cellFrame(for textContainer: NSTextContainer,
                            proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint,
                            characterIndex charIndex: Int) -> NSRect {
        guard let image else { return NSRect(x: position.x, y: position.y, width: 16, height: 16) }
        let avail = max(min(lineFrag.width, owner?.maxWidth ?? 640), 80)
        let scale = min(avail / image.size.width, 1)
        let w = image.size.width * scale
        let h = image.size.height * scale
        return NSRect(x: position.x, y: position.y - h, width: w, height: h)
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: 3)
    }

    override func draw(withFrame cellFrame: NSRect,
                       in controlView: NSView?,
                       characterIndex charIndex: Int,
                       layoutManager: NSLayoutManager) {
        guard let image else { return }
        image.draw(in: cellFrame)
        if owner?.isChart == true {
            NSColor(calibratedRed: 0.18, green: 0.43, blue: 0.92, alpha: 0.5).setStroke()
            let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            path.lineWidth = 1
            path.stroke()
        }
    }
}

extension MDImageAttachment {
    /// 该附件是否是图表（title 里带图表配置标记）
    var isChart: Bool { ChartConfig.isChartTitle(mdTitle) }
}

// MARK: - 分割线附件

final class MDRuleAttachment: NSTextAttachment {
    init() {
        super.init(data: nil, ofType: nil)
        self.attachmentCell = MDRuleAttachmentCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.attachmentCell = MDRuleAttachmentCell()
    }

    override func attachmentBounds(for textContainer: NSTextContainer?,
                                   proposedLineFragment lineFrag: NSRect,
                                   glyphPosition position: NSPoint,
                                   characterIndex charIndex: Int) -> NSRect {
        NSRect(x: 0, y: -6, width: max(lineFrag.width, 40), height: 20)
    }
}

final class MDRuleAttachmentCell: NSTextAttachmentCell {

    override func cellFrame(for textContainer: NSTextContainer,
                            proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint,
                            characterIndex charIndex: Int) -> NSRect {
        NSRect(x: position.x, y: position.y - 16, width: max(lineFrag.width, 40), height: 20)
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: 6)
    }

    override func draw(withFrame cellFrame: NSRect,
                       in controlView: NSView?,
                       characterIndex charIndex: Int,
                       layoutManager: NSLayoutManager) {
        let y = cellFrame.midY.rounded()
        NSColor.separatorColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cellFrame.minX, y: y))
        path.line(to: NSPoint(x: cellFrame.maxX, y: y))
        path.lineWidth = 1
        path.stroke()
    }
}
