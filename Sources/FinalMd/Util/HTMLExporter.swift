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
    """
}
