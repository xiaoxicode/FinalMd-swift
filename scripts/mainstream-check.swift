//
//  mainstream-check.swift — 主流语法测试矩阵（第二轮）检查器
//
//  读 JSON 用例 [{id, section, markdown, ref, check}]，对每个用例：
//   1. parse → serialize 往返两次，取 out1 / out2，判定一次稳定（out1 == out2）
//   2. 生成「忠实 HTML 片段」：walk MarkdownSerializer.blocks(from:)，
//      按 CommonMark HTML 模型输出（区分 ol/ul、表头 thead、标题层级），
//      行内沿用 InlineSerializer.html。
//   3. 输出 JSON 结果供 run-mainstream.py 与权威期望 HTML 归一化对比。
//
//  用法：/tmp/finalmd-mainstream <cases.json> <results.json>
//
import Foundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("usage: mainstream-check <cases.json> <results.json>\n", stderr)
    exit(1)
}

func readJSON(_ path: String) -> [String: Any]? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    return (try? JSONSerialization.jsonObject(with: d, options: [])) as? [String: Any]
}

guard let doc = readJSON(args[1]),
      let cases = doc["cases"] as? [[String: Any]] else {
    fputs("cannot read cases from \(args[1])\n", stderr)
    exit(1)
}

// MARK: - 忠实 HTML 片段渲染（测试专用：比 HTMLExporter 更贴近 CommonMark 模型）

func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func inlineHTML(_ content: NSAttributedString) -> String {
    InlineSerializer.html(content)
}

/// 把扁平 listItem(ordered, level) 序列重建成嵌套 <ul>/<ol>：
/// 子层列表必须开在父项 <li> 内部（CommonMark 嵌套结构），
/// raws 是列表项附属的缩进容器块 HTML（代码块等），归属进 <li>。
func renderListItems(_ items: [(ordered: Bool, level: Int, html: String, raws: [String])]) -> String {
    var out = ""
    // 栈元素：(ordered, level, liOpen)
    var stack: [(ordered: Bool, level: Int, liOpen: Bool)] = []

    func closeLi() {
        if !stack.isEmpty, stack[stack.count - 1].liOpen {
            out += "</li>\n"
            stack[stack.count - 1].liOpen = false
        }
    }
    func closeList() {
        closeLi()
        if let top = stack.popLast() {
            out += top.ordered ? "</ol>\n" : "</ul>\n"
        }
    }

    for item in items {
        // 关掉更深的层
        while let top = stack.last, top.level > item.level { closeList() }
        // 同层但列表类型变化（ol ↔ ul）：关旧开新
        if let top = stack.last, top.level == item.level, top.ordered != item.ordered {
            closeList()
        }
        // 开新层（子层列表开在父项 <li> 内部）
        if stack.isEmpty || stack.last!.level < item.level {
            out += item.ordered ? "<ol>\n" : "<ul>\n"
            stack.append((item.ordered, item.level, false))
        }
        closeLi()
        out += "<li>" + item.html + item.raws.joined()
        stack[stack.count - 1].liOpen = true
    }
    while !stack.isEmpty { closeList() }
    return out
}

func fragmentHTML(_ attr: NSAttributedString) -> String {
    let blocks = MarkdownSerializer.blocks(from: attr)
    var out = ""
    var listBuf: [(ordered: Bool, level: Int, html: String, raws: [String])] = []

    func flushList() {
        guard !listBuf.isEmpty else { return }
        out += renderListItems(listBuf)
        listBuf = []
    }

    /// 剥掉非空行的共同前导缩进（列表项内嵌块的语法缩进）
    func stripCommonIndent(_ source: String) -> String {
        let rawLines = source.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let minIndent = rawLines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix(while: { $0 == " " }).count }
            .min() ?? 0
        return rawLines.map { line -> String in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let n = min(line.prefix(while: { $0 == " " }).count, minIndent)
            return String(line.dropFirst(n))
        }.joined(separator: "\n")
    }

    for block in blocks {
        switch block {
        case .heading(let level, let content):
            flushList()
            out += "<h\(level)>" + inlineHTML(content) + "</h\(level)>\n"
        case .paragraph(let content):
            flushList()
            out += "<p>" + inlineHTML(content) + "</p>\n"
        case .quote(let content):
            flushList()
            // 引用内容按块结构递归渲染（与 HTMLExporter 一致），
            // 优先重解析原始源码：显示文本里的 ** 等标记已被行内解析吃掉。
            var inner = content.string.replacingOccurrences(of: "\u{2028}", with: "\n")
            if content.length > 0,
               let raw = content.attribute(.mdQuoteSource, at: 0, effectiveRange: nil) as? String {
                inner = raw
            }
            let innerAttr = MarkdownParser.parse(inner)
            out += "<blockquote>" + fragmentHTML(innerAttr) + "</blockquote>\n"
        case .code(let text, let language):
            flushList()
            // info 串第一个词才是语言类名（CommonMark）
            let lang = language.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .first.map(String.init) ?? ""
            let cls = lang.isEmpty ? "" : " class=\"language-\(esc(lang))\""
            out += "<pre><code\(cls)>" + esc(text) + "</code></pre>\n"
        case .rule:
            flushList()
            out += "<hr />\n"
        case .listItem(let ordered, let level, let content, _):
            // 成文标记（"- " / "8. "）是文本的一部分，HTML 语义里要剥掉
            // （与 MarkdownSerializer 的 markdown 输出路径同规则）。
            var body = content
            let s = body.string
            if let sp = s.firstIndex(of: " ") {
                let drop = s.distance(from: s.startIndex, to: sp) + 1
                if drop < body.length {
                    body = body.attributedSubstring(from: NSRange(location: drop, length: body.length - drop))
                } else {
                    body = NSAttributedString()
                }
            }
            // 松散列表项（内容含空行）按段落拆 <p>（CommonMark loose list）；
            // 紧凑项保持裸文本（<li>a</li>），与权威一致。
            var itemHTML = inlineHTML(body)
            if itemHTML.contains("<br /><br />") {
                itemHTML = "<p>" + itemHTML
                    .replacingOccurrences(of: "<br /><br />", with: "</p><p>")
                    + "</p>"
                itemHTML = itemHTML.replacingOccurrences(of: "<p></p>", with: "")
            }
            listBuf.append((ordered, level, itemHTML, []))
        case .image(let att):
            flushList()
            var tag = "<p><img src=\"\(esc(att.src))\" alt=\"\(esc(att.altPlainText))\""
            if !att.mdTitle.isEmpty { tag += " title=\"\(esc(att.mdTitle))\"" }
            out += tag + " /></p>\n"
        case .table(let rows, let hasHeader):
            flushList()
            out += "<table>\n"
            for (r, row) in rows.enumerated() {
                if hasHeader && r == 0 {
                    out += "<thead><tr>"
                    out += row.map { "<th>" + inlineHTML($0) + "</th>" }.joined()
                    out += "</tr></thead>\n"
                } else {
                    if hasHeader && r == 1 { out += "<tbody>\n" }
                    out += "<tr>"
                    out += row.map { "<td>" + inlineHTML($0) + "</td>" }.joined()
                    out += "</tr>\n"
                }
            }
            if hasHeader && rows.count > 1 { out += "</tbody>\n" }
            out += "</table>\n"
        case .raw(let source, let kind):
            // 列表项附属的缩进容器块归属进最近的 <li>（CommonMark 嵌套结构）：
            // .listCode 是项内代码块，.listIndented 是项内引用 / 围栏等嵌套块，
            // 剥掉共同缩进后按块递归渲染，不能当字面 <pre> 印。
            if (kind == .listCode || kind == .listIndented), !listBuf.isEmpty {
                if kind == .listCode {
                    // 吸收进来的块前空行不属于代码内容（空行不能开代码块）
                    var code = stripCommonIndent(source)
                    while code.hasPrefix("\n") { code = String(code.dropFirst()) }
                    listBuf[listBuf.count - 1].raws
                        .append("<pre><code>" + esc(code) + "</code></pre>\n")
                } else {
                    let nested = MarkdownParser.parse(stripCommonIndent(source))
                    let html = fragmentHTML(nested)
                    if !html.isEmpty {
                        listBuf[listBuf.count - 1].raws.append(html)
                    }
                }
            } else {
                flushList()
                switch kind {
                case .html:
                    out += source + "\n"
                case .frontmatter, .definition:
                    break // 元数据，不进 HTML 正文
                case .indentedCode:
                    // 4 空格 / tab 是语法前缀，导出时去掉一层（同 HTMLExporter）
                    let code = source.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { line -> String in
                            if line.hasPrefix("\t") { return String(line.dropFirst()) }
                            let n = min(line.prefix(while: { $0 == " " }).count, 4)
                            return String(line.dropFirst(n))
                        }.joined(separator: "\n")
                    out += "<pre><code>" + esc(code) + "</code></pre>\n"
                case .listCode, .listIndented:
                    out += "<pre>" + esc(source) + "</pre>\n"
                }
            }
        case .callout:
            flushList()
            // 扩展语法，不在主流矩阵内
            break
        }
    }
    flushList()
    return out
}

// MARK: - 主循环

var results: [[String: Any]] = []
let t0 = Date()
for (i, c) in cases.enumerated() {
    let md = c["markdown"] as? String ?? ""
    let a1 = MarkdownParser.parse(md)
    let out1 = MarkdownSerializer.markdown(from: a1)
    let a2 = MarkdownParser.parse(out1)
    let out2 = MarkdownSerializer.markdown(from: a2)
    let frag = fragmentHTML(a1)
    let frag2 = fragmentHTML(a2)
    var r: [String: Any] = [
        "id": c["id"] as? Int ?? (i + 1),
        "section": c["section"] as? String ?? "",
        "check": c["check"] as? String ?? "full",
        "out1": out1,
        "out2": out2,
        "stable": out1 == out2,
        "frag": frag,
        "frag2": frag2,
    ]
    if let ref = c["ref"] as? String { r["ref"] = ref }
    results.append(r)
    if (i + 1) % 50 == 0 {
        FileHandle.standardError.write("  \(i + 1)/\(cases.count)\n".data(using: .utf8)!)
    }
}

let summary: [String: Any] = [
    "cases": cases.count,
    "stable": results.filter { ($0["stable"] as? Bool) == true }.count,
    "ms": Int(Date().timeIntervalSince(t0) * 1000),
]
let payload: [String: Any] = ["summary": summary, "results": results]
let data = try JSONSerialization.data(withJSONObject: payload, options: [])
try data.write(to: URL(fileURLWithPath: args[2]))
FileHandle.standardError.write("done: \(cases.count) cases\n".data(using: .utf8)!)
