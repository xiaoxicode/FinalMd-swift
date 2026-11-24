//
//  HTMLExporter.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  对应 Electron 版 app.js 的 exportHtml()：用导出的 CSS 把文档包成一份独立 HTML。
//

import AppKit

enum HTMLExporter {

    static func document(from attr: NSAttributedString, title: String, language: String) -> String {
        let blocks = MarkdownSerializer.blocks(from: attr)
        var body = ""

        for block in blocks {
            switch block {
            case .heading(let level, let content):
                body += "<h\(level)>\(InlineSerializer.html(content))</h\(level)>\n"
            case .paragraph(let content):
                body += "<p>\(InlineSerializer.html(content))</p>\n"
            case .quote(let content):
                body += "<blockquote>\(InlineSerializer.html(content))</blockquote>\n"
            case .code(let text, let language):
                let cls = language.isEmpty ? "" : " class=\"language-\(escape(language))\""
                body += "<pre><code\(cls)>\(escape(text))</code></pre>\n"
            case .rule:
                body += "<hr />\n"
            case .listItem(let ordered, let level, let content):
                _ = level
                body += "<li>\(InlineSerializer.html(content))</li>\n"
                _ = ordered
            case .image(let att):
                var tag = "<img src=\"\(escape(att.src))\" alt=\"\(escape(att.alt))\""
                if !att.mdTitle.isEmpty { tag += " title=\"\(escape(att.mdTitle))\"" }
                body += tag + " />\n"
            case .table(let rows, let hasHeader):
                body += "<table>\n"
                for (r, row) in rows.enumerated() {
                    let tag = (hasHeader && r == 0) ? "th" : "td"
                    let cells = row.map { "<\(tag)>\(InlineSerializer.html($0))</\(tag)>" }.joined(separator: "")
                    body += "<tr>\(cells)</tr>\n"
                }
                body += "</table>\n"
            case .raw(let source, let kind):
                // 原始 HTML 原样进正文；frontmatter 与引用式链接定义是元数据，
                // 不渲染成可见内容（否则 YAML 会被当成正文印出来）。
                if kind == .html {
                    body += source + "\n"
                } else if kind == .indentedCode {
                    // 4 空格 / tab 是 Markdown 的语法前缀，导出 HTML 时要去掉一层
                    let code = source.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { line -> String in
                            if line.hasPrefix("\t") { return String(line.dropFirst()) }
                            let n = min(line.prefix(while: { $0 == " " }).count, 4)
                            return String(line.dropFirst(n))
                        }.joined(separator: "\n")
                    body += "<pre><code>\(escape(code))</code></pre>\n"
                }
            case .callout(let lines, let kind, let fold):
                let lower = kind.lowercased()
                var title = lines.first ?? ""
                if let close = title.firstIndex(of: "]") {
                    var rest = String(title[title.index(after: close)...])
                    if rest.hasPrefix("+") || rest.hasPrefix("-") { rest = String(rest.dropFirst()) }
                    title = rest.trimmingCharacters(in: .whitespaces)
                }
                if title.isEmpty { title = kind.capitalized }
                body += "<div class=\"callout\" data-callout=\"\(escape(lower))\""
                    + " data-fold=\"\(escape(fold))\">\n"
                body += "<div class=\"callout-title\">\(escape(title))</div>\n"
                for line in lines.dropFirst() {
                    body += "<p>\(InlineSerializer.html(NSAttributedString(string: line)))</p>\n"
                }
                body += "</div>\n"
            }
        }

        // 列表项包一层 <ul>/<ol>
        body = wrapLists(body)

        return """
        <!DOCTYPE html>
        <html lang="\(language)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(escape(title))</title>
        <style>\(css)</style>
        </head>
        <body>
        \(body)</body>
        </html>
        """
    }

    /// 把连续的 <li> 包进 <ul>（本版本统一用无序列表承载，与原版 TOC/列表输出一致）
    private static func wrapLists(_ html: String) -> String {
        var out = ""
        var inList = false
        for line in html.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("<li>") {
                if !inList { out += "<ul>\n"; inList = true }
                out += line + "\n"
            } else {
                if inList { out += "</ul>\n"; inList = false }
                out += line + "\n"
            }
        }
        if inList { out += "</ul>\n" }
        return out
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// 与原版 exportHtml() 内联的 CSS 保持一致
    private static let css = """
        body{font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif;
          max-width:820px;margin:40px auto;padding:0 24px;line-height:1.8;color:#24292f;}
        h1,h2,h3,h4{line-height:1.35;color:#101418;}
        h1{font-size:1.9em;border-bottom:1px solid #eee;padding-bottom:.25em;}
        h2{font-size:1.5em;}h3{font-size:1.25em;}
        code{background:#f2f3f5;border:1px solid #e6e8ea;border-radius:4px;padding:.08em .35em;font-size:.88em;color:#c0341d;}
        pre{background:#f7f8fa;border:1px solid #e6e8ea;border-radius:6px;padding:14px 16px;overflow:auto;}
        pre code{background:none;border:none;color:inherit;}
        blockquote{border-left:3px solid #2f6feb;margin:.8em 0;padding:.1em 0 .1em 1em;color:#4b5563;background:#f8f9fb;}
        table{border-collapse:collapse;width:100%;margin:.9em 0;}
        th,td{border:1px solid #ddd;padding:7px 10px;} th{background:#f5f6f8;}
        img{max-width:100%;height:auto;display:block;margin:.8em auto;}
        hr{border:none;border-top:1px solid #ddd;margin:1.6em 0;}
        a{color:#2f6feb;}
        mark{background:#fff3a3;}
        a.internal-link{color:#2f6feb;text-decoration:none;border-bottom:1px dashed #2f6feb;}
        .internal-embed{display:inline-block;padding:0 .4em;border:1px dashed #c8ced6;border-radius:4px;color:#4b5563;}
        .callout{border-left:4px solid #2f6feb;background:#f8f9fb;border-radius:0 6px 6px 0;
          padding:10px 14px;margin:1em 0;color:#24292f;}
        .callout-title{font-weight:600;margin-bottom:.35em;}
        .callout p{margin:.25em 0;}
        .callout[data-callout~="tip"],.callout[data-callout~="success"],.callout[data-callout~="check"],
        .callout[data-callout~="done"]{border-left-color:#188368;}
        .callout[data-callout~="important"],.callout[data-callout~="example"],
        .callout[data-callout~="abstract"],.callout[data-callout~="summary"]{border-left-color:#7a53c1;}
        .callout[data-callout~="warning"],.callout[data-callout~="caution"],
        .callout[data-callout~="question"],.callout[data-callout~="help"]{border-left-color:#c87114;}
        .callout[data-callout~="danger"],.callout[data-callout~="error"],
        .callout[data-callout~="bug"],.callout[data-callout~="fail"]{border-left-color:#c83737;}
        .callout[data-callout~="quote"],.callout[data-callout~="cite"]{border-left-color:#6b7280;}
    """
}
