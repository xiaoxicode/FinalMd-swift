//
//  InlineParser.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  行内 Markdown → NSAttributedString。
//  递归下降扫描，支持：**粗体** / *斜体* / `代码` / ~~删除线~~ / [链接](url) /
//  ![图片](src "title") / <span style="color:#d64545"> / <mark> / <u> / <br> 与 \ 转义。
//

import AppKit

enum InlineParser {

    /// 把一段行内 Markdown 渲染成带属性的字符串
    static func parse(_ text: String, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var scanner = Scanner(chars: Array(text), base: base)
        return scanner.render(stop: nil)
    }

    // MARK: - 扫描器

    private struct Scanner {
        let chars: [Character]
        let base: [NSAttributedString.Key: Any]
        var pos = 0

        var isAtEnd: Bool { pos >= chars.count }

        mutating func render(stop: String?) -> NSAttributedString {
            let out = NSMutableAttributedString()
            var plain = [Character]()

            func flushPlain() {
                guard !plain.isEmpty else { return }
                out.append(NSAttributedString(string: String(plain), attributes: base))
                plain.removeAll()
            }

            while !isAtEnd {
                // 遇到停止分隔符（** / __ / * / _ / ~~ ）就结束本层
                if let stop, matches(stop) { return out.appendingFlush(plain, base) }
                guard !isAtEnd else { break }

                let c = chars[pos]

                // 转义
                if c == "\\" {
                    if pos + 1 < chars.count {
                        plain.append(chars[pos + 1])
                        pos += 2
                    } else {
                        plain.append("\\")
                        pos += 1
                    }
                    continue
                }

                // 行内代码
                if c == "`" {
                    flushPlain()
                    if let end = find("`", from: pos + 1) {
                        let code = String(chars[(pos + 1)..<end])
                        out.append(NSAttributedString(string: code, attributes: codeAttributes(base)))
                        pos = end + 1
                    } else {
                        plain.append("`")
                        pos += 1
                    }
                    continue
                }

                // 图片 ![alt](src "title")
                if c == "!", peek(1) == "[" {
                    flushPlain()
                    if let raw = readDelimited(open: "![", close: "]"),
                       let link = readLinkTarget(after: pos) {
                        out.append(imageAttachment(alt: raw, src: link.url, title: link.title))
                        continue
                    }
                    plain.append(c)
                    pos += 1
                    continue
                }

                // 链接 [text](url)
                if c == "[" {
                    flushPlain()
                    if let raw = readDelimited(open: "[", close: "]"),
                       let link = readLinkTarget(after: pos) {
                        var inner = base
                        inner[.link] = link.url
                        inner[.foregroundColor] = DocTheme.accent
                        inner[.underlineStyle] = NSUnderlineStyle.single.rawValue
                        let label = link.text.isEmpty ? raw : link.text
                        let content = InlineParser.parse(label, base: inner)
                        out.append(content)
                        continue
                    }
                    plain.append(c)
                    pos += 1
                    continue
                }

                // 强调 ** __ * _ ~~
                if let (mark, len) = emphasis(at: pos) {
                    flushPlain()
                    pos += len
                    var inner = base
                    switch mark {
                    case .bold: inner[.font] = FontTraits.adding(.bold, to: base[.font])
                    case .italic: inner[.font] = FontTraits.adding(.italic, to: base[.font])
                    case .strike: inner[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    }
                    var sub = Scanner(chars: chars, base: inner)
                    sub.pos = pos
                    let rendered = sub.render(stop: mark.delimiter)
                    pos = sub.pos + len
                    out.append(rendered)
                    continue
                }

                // HTML 标签
                if c == "<" {
                    flushPlain()
                    if let handled = handleTag(into: out) {
                        if handled { continue }
                    }
                    plain.append(c)
                    pos += 1
                    continue
                }

                plain.append(c)
                pos += 1
            }

            flushPlain()
            return out
        }

        // MARK: 工具

        private func peek(_ offset: Int) -> Character? {
            let i = pos + offset
            return i < chars.count ? chars[i] : nil
        }

        private func matches(_ s: String) -> Bool {
            let arr = Array(s)
            guard pos + arr.count <= chars.count else { return false }
            for (i, ch) in arr.enumerated() where chars[pos + i] != ch { return false }
            return true
        }

        private func find(_ s: String, from: Int) -> Int? {
            let arr = Array(s)
            var i = from
            while i + arr.count <= chars.count {
                var ok = true
                for (k, ch) in arr.enumerated() where chars[i + k] != ch { ok = false; break }
                if ok { return i }
                i += 1
            }
            return nil
        }

        /// 读取 `open ... close` 之间的原文（不解析内部强调）
        private mutating func readDelimited(open: String, close: String) -> String? {
            guard matches(open) else { return nil }
            let start = pos + open.count
            guard let end = find(close, from: start) else { return nil }
            let raw = String(chars[start..<end])
            pos = end + close.count
            return raw
        }

        /// 读取紧随其后的 (url "title")，并把 pos 移到右括号之后
        private mutating func readLinkTarget(after: Int) -> (url: String, title: String, text: String)? {
            guard pos < chars.count, chars[pos] == "(" else { return nil }
            var i = pos + 1
            var depth = 1
            var buf = [Character]()
            while i < chars.count {
                let ch = chars[i]
                if ch == "(" { depth += 1 }
                if ch == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
                buf.append(ch)
                i += 1
            }
            guard i < chars.count else { return nil }
            pos = i + 1

            var raw = String(buf).trimmingCharacters(in: .whitespaces)
            var title = ""
            // 形如：url "title"
            if let qStart = raw.firstIndex(of: "\""),
               let qEnd = raw.lastIndex(of: "\""), qStart < qEnd {
                title = String(raw[raw.index(after: qStart)..<qEnd])
                raw = String(raw[raw.startIndex..<qStart]).trimmingCharacters(in: .whitespaces)
            }
            return (raw, title, "")
        }

        private func emphasis(at index: Int) -> (Emphasis, Int)? {
            let s = String(chars[index...].prefix(2))
            if s.hasPrefix("**") { return (.bold, 2) }
            if s.hasPrefix("__") { return (.bold, 2) }
            if s.hasPrefix("~~") { return (.strike, 2) }
            if s.hasPrefix("*") { return (.italic, 1) }
            if s.hasPrefix("_") { return (.italic, 1) }
            return nil
        }

        enum Emphasis {
            case bold, italic, strike
            var delimiter: String {
                switch self {
                case .bold: return "**"
                case .italic: return "*"
                case .strike: return "~~"
                }
            }
        }

        // MARK: HTML 标签

        private mutating func handleTag(into out: NSMutableAttributedString) -> Bool? {
            guard let gt = find(">", from: pos) else { return nil }
            let tagText = String(chars[pos...gt])
            let name = String(tagText.dropFirst().prefix(while: { $0.isLetter })).lowercased()
            guard !name.isEmpty else { return false }

            // 自闭合
            if tagText.hasSuffix("/>") || name == "br" || name == "hr" {
                pos = gt + 1
                if name == "br" {
                    out.append(NSAttributedString(string: "\u{2028}", attributes: base))
                } else if name == "hr" {
                    out.append(NSAttributedString(attachment: MDRuleAttachment()))
                }
                return true
            }

            // 需要闭合标签
            let closeTag = "</\(name)>"
            guard let closeStart = findMatchingClose(tag: name, from: gt + 1) else { return false }
            let innerStart = gt + 1
            let inner = String(chars[innerStart..<closeStart])

            var innerAttrs = base
            switch name {
            case "span":
                let style = Self.styleValue(of: "style", in: tagText)
                if let c = Self.cssColor(style, key: "color"), let color = NSColor(hex: c) {
                    innerAttrs[.foregroundColor] = color
                    innerAttrs[.mdTextColor] = color
                }
                if let c = Self.cssColor(style, key: "background-color"), let color = NSColor(hex: c) {
                    innerAttrs[.backgroundColor] = color
                    innerAttrs[.mdHighlight] = color
                }
            case "mark":
                let style = Self.styleValue(of: "style", in: tagText)
                if let c = Self.cssColor(style, key: "background-color"), let color = NSColor(hex: c) {
                    innerAttrs[.backgroundColor] = color
                    innerAttrs[.mdHighlight] = color
                } else {
                    innerAttrs[.backgroundColor] = DocTheme.defaultHighlight
                    innerAttrs[.mdHighlight] = DocTheme.defaultHighlight
                }
            case "u":
                innerAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case "strong", "b":
                innerAttrs[.font] = FontTraits.adding(.bold, to: base[.font])
            case "em", "i":
                innerAttrs[.font] = FontTraits.adding(.italic, to: base[.font])
            case "code":
                innerAttrs = codeAttributes(base)
            case "del", "s":
                innerAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case "a":
                if let href = Self.attributeValue(of: "href", in: tagText) {
                    innerAttrs[.link] = href as NSString
                    innerAttrs[.foregroundColor] = DocTheme.accent
                    innerAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
            default:
                break
            }

            out.append(InlineParser.parse(inner, base: innerAttrs))
            pos = closeStart + closeTag.count
            return true
        }

        private func findMatchingClose(tag: String, from: Int) -> Int? {
            let open = "<\(tag)"
            let close = "</\(tag)>"
            var depth = 1
            var i = from
            while i < chars.count {
                if substring(at: i, matches: open) && !substring(at: i, matches: close) {
                    // 只统计真正的开标签（后面跟空格或 >）
                    let after = i + open.count
                    if after < chars.count, chars[after] == ">" || chars[after] == " " {
                        depth += 1
                    }
                } else if substring(at: i, matches: close) {
                    depth -= 1
                    if depth == 0 { return i }
                }
                i += 1
            }
            return nil
        }

        private func substring(at index: Int, matches s: String) -> Bool {
            let arr = Array(s)
            guard index + arr.count <= chars.count else { return false }
            for (i, ch) in arr.enumerated() where chars[index + i] != ch { return false }
            return true
        }

        static func styleValue(of attr: String, in tag: String) -> String {
            guard let r = tag.range(of: "\(attr)=\"") else { return "" }
            let rest = tag[r.upperBound...]
            guard let end = rest.range(of: "\"") else { return "" }
            return String(rest[rest.startIndex..<end.lowerBound])
        }

        static func attributeValue(of attr: String, in tag: String) -> String? {
            let pattern = "\(attr)=\""
            guard let r = tag.range(of: pattern) else { return nil }
            let rest = tag[r.upperBound...]
            guard let end = rest.range(of: "\"") else { return nil }
            return String(rest[rest.startIndex..<end.lowerBound])
        }

        /// 从 "color:#d64545;background-color:#fff3a3" 里取某个 css 属性
        static func cssColor(_ style: String, key: String) -> String? {
            for part in style.split(separator: ";") {
                let kv = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == key {
                    var v = kv[1].trimmingCharacters(in: .whitespaces)
                    if v.hasPrefix("#") == false, v.count == 6 { v = "#" + v }
                    return v
                }
            }
            return nil
        }

        // MARK: 附件

        private func imageAttachment(alt: String, src: String, title: String) -> NSAttributedString {
            let att = MDImageAttachment(src: src, alt: alt, title: title)
            let obj = NSAttributedString(attachment: att)
            let out = NSMutableAttributedString(attributedString: obj)
            // alt 作为无障碍描述保留在附件上，不在正文里显示
            return out
        }
    }
}

// MARK: - 辅助

enum FontTraits {
    static func adding(_ trait: NSFontDescriptor.SymbolicTraits,
                       to value: Any?) -> NSFont {
        let font = value as? NSFont ?? DocTheme.bodyFont
        let d = font.fontDescriptor
        let merged = d.withSymbolicTraits(d.symbolicTraits.union(trait))
        return NSFont(descriptor: merged, size: font.pointSize) ?? font
    }

    static func removing(_ trait: NSFontDescriptor.SymbolicTraits,
                         from value: Any?) -> NSFont {
        let font = value as? NSFont ?? DocTheme.bodyFont
        let d = font.fontDescriptor
        let rest = d.symbolicTraits.subtracting(trait)
        let merged = d.withSymbolicTraits(rest)
        return NSFont(descriptor: merged, size: font.pointSize) ?? font
    }

    static func has(_ trait: NSFontDescriptor.SymbolicTraits, in value: Any?) -> Bool {
        guard let font = value as? NSFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(trait)
    }
}

/// 行内代码的属性组合
func codeAttributes(_ base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
    var a = base
    let size = (base[.font] as? NSFont)?.pointSize ?? DocTheme.bodyFontSize
    a[.font] = DocTheme.monospacedFont(size: size * 0.88)
    a[.mdInlineCode] = true
    a[.backgroundColor] = DocTheme.codeBackground
    a[.foregroundColor] = NSColor(calibratedRed: 0.753, green: 0.204, blue: 0.114, alpha: 1)
    return a
}

private extension NSMutableAttributedString {
    func appendingFlush(_ chars: [Character], _ attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        if !chars.isEmpty {
            append(NSAttributedString(string: String(chars), attributes: attrs))
        }
        return self
    }
}
