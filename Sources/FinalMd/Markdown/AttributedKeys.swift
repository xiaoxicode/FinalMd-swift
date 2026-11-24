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
    /// 用户显式设置的字体颜色（NSColor）。与 .foregroundColor 成对写入，
    /// 序列化时只读这个键，避免把「默认正文色」误判成用户设的颜色而输出多余的 span
    static let mdTextColor = NSAttributedString.Key("finalmd.textColor")
    /// 用户显式设置的突出显示色（NSColor），同上
    static let mdHighlight = NSAttributedString.Key("finalmd.highlight")
    /// 结构性加粗：标题/表头靠字号+字重呈现，但这层加粗不是用户敲的 **，
    /// 打上标记后才能在「标题改回正文」时准确剥掉，避免把 # 标题 变成 **正文**
    static let mdStructuralBold = NSAttributedString.Key("finalmd.structuralBold")
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
/// frontmatter 与链接定义是元数据（不进正文），原始 HTML 要原样放进 <body>。
enum MDRawKind: String {
    case frontmatter
    case html
    case definition
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

    init(ordered: Bool, level: Int, number: Int = 1) {
        self.ordered = ordered
        self.level = max(level, 0)
        self.number = number
        super.init()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MDListItem else { return false }
        return ordered == other.ordered && level == other.level && number == other.number
    }

    override var hash: Int {
        var h = Hasher()
        h.combine(ordered)
        h.combine(level)
        h.combine(number)
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

    /// 最大显示宽度（点）
    var maxWidth: CGFloat = 640

    init(src: String, alt: String = "", title: String = "", image: NSImage? = nil) {
        self.src = src
        self.alt = alt
        self.mdTitle = title
        super.init(data: nil, ofType: nil)
        if let image {
            self.image = image
        } else {
            self.image = Self.image(from: src)
        }
        self.attachmentCell = MDImageAttachmentCell(owning: self)
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

    /// 从 data URL / 普通 URL / 文件路径解析出 NSImage
    static func image(from src: String) -> NSImage? {
        if src.hasPrefix("data:"), let comma = src.firstIndex(of: ",") {
            let meta = String(src[src.startIndex..<comma])
            let payload = String(src[src.index(after: comma)...])
            guard meta.contains("base64"), let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
                return nil
            }
            return NSImage(data: data)
        }
        if let url = URL(string: src), url.scheme == "http" || url.scheme == "https" {
            return NSImage(contentsOf: url)
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
