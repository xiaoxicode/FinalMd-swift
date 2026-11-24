//
//  EmbedInline.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  Obsidian 嵌入 ![[...]] 的「内联展示」：在即刻模式里把嵌入语法替换成一张
//  自绘卡片附件，直接显示在文档流中，而不是弹只读预览面板。
//
//  设计约束：
//   1. 附件只占一个 U+FFFC 字符，序列化时按 link.raw 逐字还原，Markdown 源码
//      与传统模式完全不受影响（兼容性测试走 parse → serialize，不经过这里）。
//   2. 解析 / 替换是纯逻辑，不依赖 SwiftUI，冒烟测试可直接验证。
//   3. 卡片是不可编辑的原子附件，不写额外段落，不影响折叠、横线与 undo 历史。
//

import Foundation
import AppKit

// MARK: - 内联嵌入附件

/// 自绘卡片附件：保存原始 ![[...]] 语法与目标内容快照。
final class MDEmbedAttachment: NSTextAttachment {
    let link: MDWikiLink
    let preview: EmbedPreview

    init(link: MDWikiLink, preview: EmbedPreview) {
        self.link = link
        self.preview = preview
        super.init(data: nil, ofType: nil)
        self.attachmentCell = MDEmbedAttachmentCell(owning: self)
    }

    required init?(coder: NSCoder) {
        let raw = coder.decodeObject(forKey: "finalmd.embed.raw") as? String ?? ""
        let title = coder.decodeObject(forKey: "finalmd.embed.title") as? String ?? ""
        let text = coder.decodeObject(forKey: "finalmd.embed.text") as? String ?? ""
        let imagePath = coder.decodeObject(forKey: "finalmd.embed.image") as? String
        self.link = EmbedInline.wikiLink(from: raw)
            ?? MDWikiLink(raw: raw, target: "", suffix: "", alias: "", embedded: true)
        self.preview = EmbedPreview(title: title, text: text, imagePath: imagePath)
        super.init(coder: coder)
        self.attachmentCell = MDEmbedAttachmentCell(owning: self)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(link.raw, forKey: "finalmd.embed.raw")
        coder.encode(preview.title, forKey: "finalmd.embed.title")
        coder.encode(preview.text, forKey: "finalmd.embed.text")
        coder.encode(preview.imagePath, forKey: "finalmd.embed.image")
    }
}

// MARK: - 卡片绘制

final class MDEmbedAttachmentCell: NSTextAttachmentCell {

    private weak var owner: MDEmbedAttachment?

    private static let maxWidth: CGFloat = 460
    private static let titleHeight: CGFloat = 22
    private static let padding: CGFloat = 10
    private static let maxBodyHeight: CGFloat = 190
    private static let maxTextLength = 1500

    init(owning: MDEmbedAttachment) {
        self.owner = owning
        super.init(imageCell: nil)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static var background: NSColor {
        dynamic(NSColor(calibratedWhite: 0.965, alpha: 1),
                NSColor(calibratedWhite: 0.19, alpha: 1))
    }

    private static var foreground: NSColor {
        dynamic(NSColor(calibratedWhite: 0.16, alpha: 1),
                NSColor(calibratedWhite: 0.90, alpha: 1))
    }

    private static var dim: NSColor {
        dynamic(NSColor(calibratedWhite: 0.42, alpha: 1),
                NSColor(calibratedWhite: 0.66, alpha: 1))
    }

    private static var accent: NSColor {
        dynamic(NSColor.systemBlue, NSColor.systemTeal)
    }

    private static var bodyFont: NSFont { NSFont.systemFont(ofSize: 11.5) }
    private static var titleFont: NSFont { NSFont.systemFont(ofSize: 11, weight: .semibold) }

    private func bodyHeight(for width: CGFloat) -> CGFloat {
        guard let preview = owner?.preview else { return 20 }
        let innerWidth = max(width - Self.padding * 2 - 8, 40)
        if let path = preview.imagePath, let image = NSImage(contentsOfFile: path) {
            let scale = min(innerWidth / max(image.size.width, 1), 1)
            return min(max(image.size.height * scale, 16), Self.maxBodyHeight)
        }
        let text = String(preview.text.prefix(Self.maxTextLength))
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: innerWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.bodyFont])
        return min(max(rect.height, 16), Self.maxBodyHeight)
    }

    private func cardHeight(for width: CGFloat) -> CGFloat {
        min(Self.titleHeight + bodyHeight(for: width) + Self.padding * 2, 260)
    }

    override func cellFrame(for textContainer: NSTextContainer,
                            proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint,
                            characterIndex charIndex: Int) -> NSRect {
        let width = min(Self.maxWidth, max(lineFrag.width - 8, 160))
        let height = cardHeight(for: width)
        return NSRect(x: position.x, y: position.y - height, width: width, height: height)
    }

    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: 2) }

    override func draw(withFrame cellFrame: NSRect,
                       in controlView: NSView?,
                       characterIndex charIndex: Int,
                       layoutManager: NSLayoutManager) {
        guard let preview = owner?.preview else { return }

        Self.background.setFill()
        let border = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 1, dy: 1),
                                  xRadius: 6, yRadius: 6)
        border.fill()
        Self.accent.setStroke()
        border.lineWidth = 1
        border.stroke()

        Self.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: cellFrame.minX + 3,
                                         y: cellFrame.minY + 7,
                                         width: 3,
                                         height: max(cellFrame.height - 14, 4)),
                     xRadius: 1.5, yRadius: 1.5).fill()

        let insetX = cellFrame.minX + Self.padding + 4
        let innerWidth = max(cellFrame.width - Self.padding * 2 - 8, 40)
        let titleRect = NSRect(x: insetX,
                               y: cellFrame.maxY - Self.titleHeight - 2,
                               width: innerWidth,
                               height: Self.titleHeight)
        (preview.title as NSString).draw(in: titleRect, withAttributes: [
            .font: Self.titleFont,
            .foregroundColor: Self.dim,
        ])

        let bodyH = bodyHeight(for: cellFrame.width)
        let bodyRect = NSRect(x: insetX,
                              y: cellFrame.maxY - Self.titleHeight - bodyH - 2,
                              width: innerWidth,
                              height: bodyH)
        if let path = preview.imagePath, let image = NSImage(contentsOfFile: path) {
            let scale = min(innerWidth / max(image.size.width, 1), 1)
            let height = min(image.size.height * scale, bodyH)
            image.draw(in: NSRect(x: bodyRect.minX,
                                  y: bodyRect.maxY - height,
                                  width: image.size.width * scale,
                                  height: height))
        } else {
            let text = String(preview.text.prefix(Self.maxTextLength))
            (text as NSString).draw(in: bodyRect, withAttributes: [
                .font: Self.bodyFont,
                .foregroundColor: Self.foreground,
            ])
        }
    }
}

// MARK: - 展开逻辑（纯逻辑，可单测）

enum EmbedInline {

    /// 从用户直接敲进去的 `![[Note]]` 文本构造双链（与 InlineParser 同一套拆分规则）。
    static func wikiLink(from raw: String) -> MDWikiLink? {
        guard raw.hasPrefix("![["), raw.hasSuffix("]]"), raw.count >= 7 else { return nil }
        let inner = String(raw.dropFirst(3).dropLast(2))
        guard !inner.isEmpty,
              !inner.contains("["), !inner.contains("]"), !inner.contains("\n") else { return nil }
        let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let targetPart = String(parts[0])
        let alias = parts.count > 1 ? String(parts[1]) : ""
        guard !targetPart.isEmpty else { return nil }
        let target: String
        let suffix: String
        if let hash = targetPart.firstIndex(of: "#") {
            target = String(targetPart[targetPart.startIndex..<hash])
            suffix = String(targetPart[hash...])
        } else {
            target = targetPart
            suffix = ""
        }
        guard !target.isEmpty else { return nil }
        return MDWikiLink(raw: raw, target: target, suffix: suffix,
                          alias: alias, embedded: true)
    }

    /// 把 attr 里所有能解析到文件的嵌入替换成内联卡片，返回新的富文本。
    /// 目标文件不存在时保留原有写法，绝不把用户的 `![[...]]` 吞掉。
    static func expand(_ attr: NSAttributedString,
                       documentPath: String?,
                       vaultRoot: String?) -> NSMutableAttributedString {
        let out = NSMutableAttributedString(attributedString: attr)
        let items = replacements(in: attr, documentPath: documentPath, vaultRoot: vaultRoot)
        for (range, attachment) in items.reversed() {
            let base = attr.attributes(at: range.location, effectiveRange: nil)
            out.replaceCharacters(in: range, with: attachmentString(attachment, base: base))
        }
        return out
    }

    /// 在已有的 textStorage 上原地增量展开（编辑器里新敲的嵌入）。
    /// 返回是否真的改动了 storage；调用方需关闭 undo 注册并恢复光标。
    @discardableResult
    static func refresh(in storage: NSMutableAttributedString,
                        documentPath: String?,
                        vaultRoot: String?) -> Bool {
        let items = replacements(in: storage, documentPath: documentPath, vaultRoot: vaultRoot)
        guard !items.isEmpty else { return false }
        for (range, attachment) in items.reversed() {
            let base = storage.attributes(at: range.location, effectiveRange: nil)
            storage.replaceCharacters(in: range, with: attachmentString(attachment, base: base))
        }
        return true
    }

    /// 是否还有「用户新敲进去、尚未展开」的嵌入语法，供上层跳过无谓的扫描。
    /// 已经在装载时展开过的嵌入变成了 U+FFFC 附件字符，不再含 `![[` 字面量。
    static func needsRefresh(_ attr: NSAttributedString) -> Bool {
        let s = attr.string
        return s.contains("![[") && s.contains("]]")
    }

    // MARK: 内部

    private static func makeAttachment(_ link: MDWikiLink,
                                      documentPath: String?,
                                      vaultRoot: String?) -> MDEmbedAttachment? {
        let target = ObsidianResolver.target(from: link)
        guard let url = ObsidianResolver.resolve(file: target.file,
                                                 near: documentPath,
                                                 vaultRoot: vaultRoot),
              let preview = ObsidianResolver.preview(at: url) else { return nil }
        return MDEmbedAttachment(link: link, preview: preview)
    }

    private static func attachmentString(_ attachment: MDEmbedAttachment,
                                         base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        var attrs = base
        // 双链属性必须摘掉：否则序列化器会按旧的 display 重建，覆盖附件里的原文
        attrs.removeValue(forKey: .mdWikiLink)
        attrs.removeValue(forKey: .attachment)
        result.addAttributes(attrs, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// 同时覆盖两种来源：
    ///  - parse 后带 .mdWikiLink 属性的嵌入（显示文字是 target/alias）
    ///  - 用户在即刻模式里直接敲出来的 `![[...]]` 纯文本
    private static func replacements(in attr: NSAttributedString,
                                     documentPath: String?,
                                     vaultRoot: String?) -> [(NSRange, MDEmbedAttachment)] {
        let ns = attr.string as NSString
        let full = NSRange(location: 0, length: attr.length)
        guard full.length > 0 else { return [] }

        var result: [(NSRange, MDEmbedAttachment)] = []
        var occupied: [NSRange] = []

        attr.enumerateAttribute(.mdWikiLink, in: full, options: []) { value, range, _ in
            guard let link = value as? MDWikiLink, link.embedded,
                  let attachment = makeAttachment(link, documentPath: documentPath,
                                                 vaultRoot: vaultRoot) else { return }
            result.append((range, attachment))
            occupied.append(range)
        }

        // 文本扫描只在确实出现嵌入语法时才做，避免每次按键都跑正则
        guard ns.contains("![[") else { return result.sorted { $0.0.location < $1.0.location } }
        guard let regex = try? NSRegularExpression(pattern: "!\\[\\[[^\\[\\]\\n]+\\]\\]") else {
            return result.sorted { $0.0.location < $1.0.location }
        }
        for match in regex.matches(in: ns as String, range: full) {
            let range = match.range
            if occupied.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }
            let raw = ns.substring(with: range)
            guard let link = wikiLink(from: raw),
                  let attachment = makeAttachment(link, documentPath: documentPath,
                                                 vaultRoot: vaultRoot) else { continue }
            result.append((range, attachment))
        }
        return result.sorted { $0.0.location < $1.0.location }
    }
}
