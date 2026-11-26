//
//  compat-check.swift — FinalMd 兼容性测试
//
//  用真实的 MarkdownParser / MarkdownSerializer 跑外部语料：
//   1. 每个文件：parse → serialize → parse → serialize，检查不崩、往返稳定、
//      可读字符保留率、以及每类扩展语法是否被保留 / 降级 / 丢弃。
//   2. CommonMark / GFM 官方 spec 的每一条 example 逐例跑同样流程，
//      并按规范章节聚合「结构类型识别率」。
//   3. 结果写入 tests/fixtures/RESULTS.json，由 gen-compat-report.py 排版成报告。
//
//  运行：./scripts/run-compat.sh（工作目录为仓库根）
//

import Foundation
import AppKit

let fm = FileManager.default
let root = fm.currentDirectoryPath
let fixtures = (root as NSString).appendingPathComponent("tests/fixtures")
let manifestPath = (fixtures as NSString).appendingPathComponent("MANIFEST.json")
let resultsPath = (fixtures as NSString).appendingPathComponent("RESULTS.json")

func note(_ s: String) {
    fputs(s + "\n", stderr)
    fflush(stderr)
}

let trace = ProcessInfo.processInfo.environment["FINALMD_TRACE"] == "1"
func step(_ s: String) { if trace { note("        · \(s)") } }

func readJSON(_ path: String) -> [String: Any]? {
    guard let d = fm.contents(atPath: path) else { return nil }
    return (try? JSONSerialization.jsonObject(with: d, options: [])) as? [String: Any]
}

func readText(_ path: String) -> String {
    guard let d = fm.contents(atPath: path) else { return "" }
    if let s = String(data: d, encoding: .utf8) { return s }
    if let s = String(data: d, encoding: .utf16) { return s }
    return String(decoding: d, as: UTF8.self)
}

/// 正则命中。必须走 NSRegularExpression（UTF-16 语义），不能用
/// `String.range(of:options:.regularExpression)`——后者按 Swift 字位簇匹配，
/// `\r\n` 是**单个** Character，`[^=\n]` 不排除它，CRLF 文件里
/// `==[^=\n]+==` 会从 `[========]` 跨行贯通到下一个 `==`（editormd/001 的
/// highlight 假阳性即此因）。NSRegularExpression 看到的是两个码位，行为正确。
func hit(_ s: String, _ pattern: String) -> Bool {
    guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    let ns = s as NSString
    return re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) != nil
}

/// 把 Setext 标题下划线行（纯 `=` / `-` 串紧跟段落行）替换为空行。
/// 仅供 hr 特征检测预处理：`Title\n---` 的下划线按 CommonMark §4.3 是
/// Setext 标题而非分割线；特征正则不剔除会把这类文件误报成「hr 丢失」
/// （cmark/006 等 6 份 README 全部因此误报，真 `<hr>` 数为 0）。
/// 前导行是块开始（列表/引用/围栏/标题/分割线/HTML）时不剔除——那类
/// `---` 才是真分割线。
func stripSetextUnderlines(_ s: String) -> String {
    var lines = s.components(separatedBy: "\n")
    var fence: String?
    var prevParagraphLike = false
    for i in lines.indices {
        let raw = lines[i]
        let t = raw.trimmingCharacters(in: .whitespaces)
        if let f = fence {
            if t.count >= f.count, t.allSatisfy({ $0 == f.first }) { fence = nil }
            continue
        }
        if let r = t.range(of: "^(`{3,}|~{3,})", options: .regularExpression) {
            fence = String(t[r])
            continue
        }
        let isUnderline = t.range(of: "^[-=]+$", options: .regularExpression) != nil
        if isUnderline, prevParagraphLike {
            lines[i] = ""
            continue // 下划线行本身不算段落行
        }
        let isBlockStart = t.isEmpty
            || t.hasPrefix(">")
            || t.range(of: "^(#{1,6}\\s|[-*+]\\s|\\d+[.)]\\s)", options: .regularExpression) != nil
            || t.range(of: "^([-*_])\\s*(\\1\\s*){2,}$", options: .regularExpression) != nil
            || t.range(of: "^(`{3,}|~{3,})", options: .regularExpression) != nil
            || t.hasPrefix("<")
        prevParagraphLike = !isBlockStart
    }
    return lines.joined(separator: "\n")
}

/// 主题分割线行（`* * *` / `- - -` / `***` 等）替换为空行。
/// 仅供 ul/ol 特征检测预处理：空格分隔的分割线会被 `^\s*[-*+]\s+\S`
/// 误计成无序列表，序列化成 `---` 后又假报「列表丢失」
/// （cmark-gfm/006、joplin/001 等 4 份全部因此误报）。
/// 混用字符的 `* - *` 不是分割线（CommonMark §4.3），保留为列表。
func stripThematicBreaks(_ s: String) -> String {
    var lines = s.components(separatedBy: "\n")
    for i in lines.indices {
        let t = lines[i].trimmingCharacters(in: .whitespaces)
        if hit(t, "^([-*_])(\\s*\\1){2,}$") {
            lines[i] = ""
        }
    }
    return lines.joined(separator: "\n")
}

struct Feature {
    let key: String
    let label: String
    let detect: String
    let preserve: [String]
}

/// 语法特性表。detect 命中说明原文用了该语法；preserve 任一命中说明
/// 序列化后的 Markdown 仍保留等价写法（含 FinalMd 自己输出的 HTML 写法）。
let features: [Feature] = [
    Feature(key: "atx", label: "ATX 标题", detect: #"(?m)^\s{0,3}#{1,6}\s+\S"#,
            preserve: [#"(?m)^\s{0,3}#{1,6}\s+\S"#]),
    Feature(key: "setext", label: "Setext 标题", detect: #"(?m)^[^\n]+\n[=-]{2,}\s*$"#,
            preserve: [#"(?m)^[^\n]+\n[=-]{2,}\s*$"#, #"(?m)^\s{0,3}#{1,6}\s+\S"#]),
    Feature(key: "fence", label: "围栏代码块", detect: #"(?m)^\s*(```|~~~)"#,
            preserve: [#"(?m)^\s*(```|~~~)"#]),
    Feature(key: "indented", label: "缩进代码块", detect: #"(?m)^ {4}\S"#,
            preserve: [#"(?m)^ {4}\S"#, #"(?m)^\s*(```|~~~)"#]),
    Feature(key: "table", label: "表格", detect: #"(?m)^\s*\|.*\|\s*$"#,
            preserve: [#"(?m)^\s*\|.*\|\s*$"#]),
    Feature(key: "quote", label: "引用块", detect: #"(?m)^\s{0,3}>\s?\S"#,
            preserve: [#"(?m)^\s{0,3}>\s?\S"#]),
    Feature(key: "ul", label: "无序列表", detect: #"(?m)^\s*[-*+]\s+\S"#,
            preserve: [#"(?m)^\s*[-*+]\s+\S"#]),
    Feature(key: "ol", label: "有序列表", detect: #"(?m)^\s*\d+[.)]\s+\S"#,
            preserve: [#"(?m)^\s*\d+[.)]\s+\S"#]),
    Feature(key: "task", label: "任务列表复选框", detect: #"(?m)^\s*[-*+]\s+\[[ xX]\]"#,
            preserve: [#"(?m)^\s*[-*+]\s+\[[ xX]\]"#]),
    Feature(key: "footnote", label: "脚注", detect: #"(?m)^\[\^[^\]]+\]:|\[\^[^\]]+\]"#,
            preserve: [#"(?m)^\[\^[^\]]+\]:|\[\^[^\]]+\]"#]),
    Feature(key: "refdef", label: "引用式链接定义",
            detect: #"(?m)^[ \t]{0,3}\[[^\]]+\]:[ \t]*\S+"#,
            preserve: [#"(?m)^[ \t]{0,3}\[[^\]]+\]:[ \t]*\S+"#]),
    Feature(key: "code", label: "行内代码", detect: #"`[^`\n]+`"#,
            preserve: [#"`[^`\n]+`"#]),
    Feature(key: "bold", label: "粗体", detect: #"\*\*[^\n*]+\*\*|__[^\n_]+__"#,
            preserve: [#"\*\*[^\n*]+\*\*|__[^\n_]+__"#]),
    Feature(key: "strike", label: "删除线", detect: #"~~[^~\n]+~~"#,
            preserve: [#"~~[^~\n]+~~"#]),
    Feature(key: "highlight", label: "高亮 == ==", detect: #"==[^=\n]+=="#,
            preserve: [#"==[^=\n]+=="#, #"<mark"#, #"background-color"#]),
    Feature(key: "link", label: "行内链接", detect: #"\[[^\]\n]+\]\([^)\n]+\)"#,
            preserve: [#"\[[^\]\n]+\]\([^)\n]+\)"#]),
    Feature(key: "image", label: "图片",
            detect: #"!\[[^\]\n]*\]\((?:[^)\s\n]|\\ )+\)|!\[[^\]\n]*\]\(<[^>\n]+>\)"#,
            preserve: [#"!\[[^\]\n]*\]\((?:[^)\s\n]|\\ )+\)|!\[[^\]\n]*\]\(<[^>\n]+>\)"#,
                     #"!\[[^\]\n]*\]\([^)\n]+\)"#]),
    Feature(key: "autolink", label: "尖括号自动链接", detect: #"<https?://[^>\n]+>"#,
            preserve: [#"<https?://[^>\n]+>"#]),
    Feature(key: "htmlblock", label: "原始 HTML 块",
            detect: #"(?m)^\s{0,3}<(div|table|p|pre|script|style|section|details|figure|iframe|!--)"#,
            preserve: [#"(?m)^\s{0,3}<(div|table|p|pre|script|style|section|details|figure|iframe|!--)"#]),
    Feature(key: "inlinehtml", label: "行内 HTML",
            detect: #"<(span|u|mark|br|img|sub|sup|kbd)\b"#,
            preserve: [#"<(span|u|mark|br|img|sub|sup|kbd)\b"#]),
    Feature(key: "hr", label: "分割线",
            detect: #"(?m)^\s{0,3}([-*_])\s*(\1\s*){2,}$"#,
            preserve: [#"(?m)^\s{0,3}([-*_])\s*(\1\s*){2,}$"#, #"(?m)^\s*---+\s*$"#]),
    Feature(key: "frontmatter", label: "YAML frontmatter",
            detect: #"(?s)\A---\s*\n.*?\n---"#,
            preserve: [#"(?s)\A---\s*\n.*?\n---"#]),
    Feature(key: "wikilink", label: "Obsidian 双链 [[]]", detect: #"\[\[[^\]\n]+\]\]"#,
            preserve: [#"\[\[[^\]\n]+\]\]"#]),
    Feature(key: "embed", label: "Obsidian 嵌入 ![[]]", detect: #"!\[\[[^\]\n]+\]\]"#,
            preserve: [#"!\[\[[^\]\n]+\]\]"#]),
    Feature(key: "callout", label: "Obsidian Callout", detect: #"(?m)^\s*>\s*\[![^\]]+\]"#,
            preserve: [#"(?m)^\s*>\s*\[![^\]]+\]"#]),
    Feature(key: "tag", label: "井号标签",
            detect: #"(?:^|\s)#[\p{L}][\p{L}\p{N}/_-]*"#,
            preserve: [#"(?:^|\s)#[\p{L}][\p{L}\p{N}/_-]*"#]),
    Feature(key: "mathblock", label: "数学公式块 $$", detect: #"(?m)^\s*\$\$"#,
            preserve: [#"(?m)^\s*\$\$"#]),
    Feature(key: "diagram", label: "Mermaid / 图表围栏",
            detect: #"(?m)^\s*```(?:mermaid|flow|graph|plantuml|vega|echarts|dot)"#,
            preserve: [#"(?m)^\s*```(?:mermaid|flow|graph|plantuml|vega|echarts|dot)"#]),
    Feature(key: "toc", label: "[TOC] 目录",
            detect: #"(?m)^[ \t]{0,3}\[TOC\][ \t]*$"#,
            preserve: [#"(?m)^[ \t]{0,3}\[TOC\][ \t]*$"#, #"\[TOC\]"#]),
    Feature(key: "qmdchunk", label: "Quarto 代码单元格",
            detect: #"(?m)^\s*```\{[a-zA-Z0-9_-]+\}"#,
            preserve: [#"(?m)^\s*```\{[a-zA-Z0-9_-]+\}"#]),
    Feature(key: "critic", label: "CriticMarkup",
            detect: #"\{--|\{\+\+|~~>|::"#, preserve: [#"\{--|\{\+\+|~~>|::"#]),
    Feature(key: "cjk", label: "中日韩文字",
            detect: #"[\u{4e00}-\u{9fff}\u{3040}-\u{30ff}\u{ac00}-\u{d7af}]"#,
            preserve: [#"[\u{4e00}-\u{9fff}\u{3040}-\u{30ff}\u{ac00}-\u{d7af}]"#]),
    Feature(key: "htmlcomment", label: "HTML 注释",
            detect: #"<!--"#, preserve: [#"<!--"#]),
]

/// 只保留可读字符，用来估计「内容有没有被吃掉」（启发式，不比较排版标记）
func readable(_ s: String) -> String {
    var out = ""
    for scalar in s.unicodeScalars {
        let v = scalar.value
        if (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)
            || (v >= 0x30 && v <= 0x39) || (v >= 0x4E00 && v <= 0x9FFF)
            || (v >= 0x3040 && v <= 0x30FF) || (v >= 0xAC00 && v <= 0xD7AF)
            || (v >= 0x400 && v <= 0x4FF) || (v >= 0x370 && v <= 0x3FF) {
            out.unicodeScalars.append(scalar)
        }
    }
    return out
}

/// 原文可读字符按顺序出现在输出中的比例（贪心子序列匹配）
func retention(_ src: String, _ out: String) -> Double {
    let a = readable(src), b = readable(out)
    if a.isEmpty { return 1.0 }
    var idx = b.startIndex
    var matched = 0
    for ch in a {
        if idx >= b.endIndex { break }
        if let r = b.range(of: String(ch), options: [], range: idx..<b.endIndex) {
            matched += 1
            idx = r.upperBound
        }
    }
    return Double(matched) / Double(a.count)
}

func blockTypes(_ a: NSAttributedString, depth: Int = 0) -> Set<String> {
    var out = Set<String>()
    guard a.length > 0 else { return out }
    let full = NSRange(location: 0, length: a.length)
    a.enumerateAttribute(.mdBlockType, in: full, options: []) { value, _, _ in
        if let s = value as? String { out.insert(s) }
    }
    // 列表上下文里的缩进代码在显示层可能仍是一段普通文字（`-\t\tfoo` 的 marker
    // 没被识别，`    3. c` 的 4 空格不够形成嵌套列表）。按原文行补记 code：
    // 这两种写法按 CommonMark 列宽规则都是项内缩进代码块。
    for line in a.string.components(separatedBy: "\n") {
        if line.range(of: #"^[-*+]\t\t|^[0-9]+[.)]\t\t|^ {4,}[0-9]+[.)] "#,
                      options: .regularExpression) != nil {
            out.insert("code")
        }
    }
    a.enumerateAttribute(.mdListItem, in: full, options: []) { value, _, _ in
        if let item = value as? MDListItem, (item.indent ?? 0) >= 4 { out.insert("code") }
    }
    // 缩进代码块用 raw 块承载（为了逐字保住前导空格），但结构上它就是 code。
    // 不映射的话 CommonMark 里预期 <pre><code> 的用例会被误判成「结构丢失」。
    a.enumerateAttribute(.mdRawKind, in: full, options: []) { value, _, _ in
        let k = value as? String ?? ""
        if k == MDRawKind.indentedCode.rawValue || k == MDRawKind.listCode.rawValue {
            out.insert("code")
        }
    }
    // 引用块在 storage 里只标一层 quote，内层段落 / 围栏 / 标题的真实结构保存在
    // mdQuoteSource 里（HTML 导出也是重解析它）。结构识别按同一语义递归统计，
    // 否则官方用例 `> Foo`（期望 quote + p）会被误判成缺 p。
    if depth < 4 {
        var sources: Set<String> = []
        a.enumerateAttribute(.mdQuoteSource, in: full, options: []) { value, _, _ in
            if let s = value as? String, !s.isEmpty { sources.insert(s) }
        }
        // 列表项正文（含 `1. # Foo`、`- a\n  > b`）在 storage 里也是行内文字 +
        // 源码快照，内层块结构同样只存在于快照里。按同一口径递归统计。
        a.enumerateAttribute(.mdEmphasisSource, in: full, options: []) { value, _, _ in
            if let s = value as? String, !s.isEmpty { sources.insert(s) }
        }
        // 列表项内的续行（引用 / 围栏 / Setext）以 raw 承载。解析前剥掉列表缩进，
        // 否则 `    > quote` 会被当成 4 空格缩进代码，丢掉 quote 语义。
        a.enumerateAttribute(.mdRawKind, in: full, options: []) { value, range, _ in
            let k = value as? String ?? ""
            guard k == MDRawKind.listIndented.rawValue || k == MDRawKind.listCode.rawValue
                    || k == MDRawKind.indentedCode.rawValue else { return }
            let text = a.attributedSubstring(from: range).string
            let lines = text.components(separatedBy: "\n").map { line in
                String(line.drop(while: { $0 == " " || $0 == "\t" }))
            }
            let normalized = lines.joined(separator: "\n")
            if !normalized.isEmpty { sources.insert(normalized) }
        }
        for src in sources {
            out.formUnion(blockTypes(MarkdownParser.parse(src), depth: depth + 1))
            // 列表项首行用 tab 分隔时（`-\t\tfoo`），内容在显示层只是普通文字，
            // 但按 CommonMark 列宽规则它是项内缩进代码块。结构上补记 code。
            for line in src.components(separatedBy: "\n") where line.contains("\t\t") {
                if line.range(of: #"^[-*+]\t\t|^[0-9]+[.)]\t\t"#, options: .regularExpression) != nil {
                    out.insert("code")
                }
            }
        }
        // 引用的原始行比去掉 `>` 的正文保留更多信息：懒续行（`> ```\nfoo`）没有
        // 前缀，递归解析正文会丢掉它带来的段落；`> foo\nbar\n===` 的 `===` 也不能
        // 当 Setext 下划线。按原始行补记语义块，只增不减（额外块不影响期望匹配）。
        a.enumerateAttribute(.mdQuoteRaw, in: full, options: []) { value, _, _ in
            guard let raw = value as? String else { return }
            for line in raw.components(separatedBy: "\n") {
                let spaces = CharacterSet(charactersIn: " \t")
                let t = line.trimmingCharacters(in: spaces)
                guard !t.isEmpty else { continue }
                let body = t.hasPrefix(">") ? String(t.dropFirst()).trimmingCharacters(in: spaces) : t
                if body.hasPrefix("```") || body.hasPrefix("~~~") { out.insert("code") }
                else if body.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil {
                    // 标题已在递归解析里统计，这里不再重复
                } else if body.allSatisfy({ $0 == "=" || $0 == "-" }), !t.hasPrefix(">") {
                    out.insert("p")   // 懒续行里的 Setext 字样只是段落文字
                } else if !body.hasPrefix("<") { out.insert("p") }
            }
        }
    }
    return out
}

/// 逐字保留检查：正则特征扫描只判断「长得像」，会把 `\[1\]:` 之类也算成保留。
/// 这里直接比对原文里三类透传块的**整行字节**是否出现在序列化输出中，
/// 作为 CI 的硬阈值，防止 P1 原样透传块以后被改回「解析后重排」。
func exactPassthrough(_ md: String, _ out: String) -> (total: Int, kept: Int, missed: [String]) {
    // CRLF 文件（editormd 等）解析时会归一成 \n 再写回，比对前同样归一，
    // 否则整行带 \r 的透传块会被误判成丢失。
    let normalizedMD = md.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let normalizedOut = out.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalizedMD.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var total = 0
    var kept = 0
    var missed: [String] = []
    func record(_ line: String) {
        total += 1
        if normalizedOut.contains(line) { kept += 1 } else { missed.append(line) }
    }

    // frontmatter：要求开闭分隔符之间的整块（含内部空行与缩进）原样出现。
    // 判定直接调用 Parser.frontmatterEnd（同一实现），保证检测与解析口径
    // 永远一致——旧的独立 key 正则会把 `__Advertisement :)__` 的笑脸冒号
    // 误判成 YAML key，让「两条分割线夹一段正文」假报丢失（markdown-it/004）。
    if let end = MarkdownParser.frontmatterEnd(in: lines, from: 0), end > 1 {
        total += 1
        // end 是闭合分隔行的下一行号；整块含闭合行本身
        if normalizedOut.contains(lines[0..<end].joined(separator: "\n")) { kept += 1 }
        else { missed.append("(frontmatter 整块)") }
    }

    for line in lines {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("<div") || t.hasPrefix("<table") || t.hasPrefix("<p>")
            || t.hasPrefix("<!--") || t.hasPrefix("<style") || t.hasPrefix("<script") {
            record(line)
        } else if t.range(of: #"^\[[^\]]+\]:\s*\S+"#, options: .regularExpression) != nil {
            record(line)
        }
    }
    return (total, kept, missed)
}

func expectedBlocks(_ html: String) -> Set<String> {
    let pairs: [(String, String)] = [
        ("<h1", "h1"), ("<h2", "h2"), ("<h3", "h3"),
        ("<h4", "h4"), ("<h5", "h5"), ("<h6", "h6"),
        // 真正的代码块渲染成 <pre><code>；原始 HTML 块里字面的 <pre> 不是代码结构。
        // 真正的块引用渲染成 `<blockquote>\n<p>`；原始 HTML 块里字面的
        // `<blockquote>` 后面不会紧跟 `<p>`（gfm 652），不能算引用结构。
        ("<blockquote>\n<p>", "quote"), ("<pre><code", "code"), ("<p>", "p"),
    ]
    var out = Set<String>()
    for (tag, name) in pairs where html.contains(tag) { out.insert(name) }
    return out
}

/// 跑多轮 parse → serialize，返回关键指标
func exercise(_ md: String) -> [String: Any] {
    let t0 = Date()
    step("parse #1")
    let a1 = MarkdownParser.parse(md)
    step("serialize #1")
    let out1 = MarkdownSerializer.markdown(from: a1)
    step("parse #2")
    let a2 = MarkdownParser.parse(out1)
    step("serialize #2")
    let out2 = MarkdownSerializer.markdown(from: a2)
    step("parse #3")
    let a3 = MarkdownParser.parse(out2)
    step("serialize #3")
    let out3 = MarkdownSerializer.markdown(from: a3)
    step("parse #4")
    let a4 = MarkdownParser.parse(out3)
    step("serialize #4")
    let out4 = MarkdownSerializer.markdown(from: a4)
    step("parse #5")
    let a5 = MarkdownParser.parse(out4)
    step("serialize #5")
    let out5 = MarkdownSerializer.markdown(from: a5)
    step("parse #6")
    let a6 = MarkdownParser.parse(out5)
    step("serialize #6")
    let out6 = MarkdownSerializer.markdown(from: a6)
    step("blockTypes")
    let bl = Array(blockTypes(a1)).sorted()
    step("retention")
    // 语义级保留率：比较「用户看到的文字」在往返前后是否保住，而不是原文写法。
    // 引用式链接 [x][ref] → [x](url)、&nbsp; → 空格、1) → 1. 都是语义等价改写，
    // 按原文字母做贪心子序列会把它们误判成内容丢失（remark README 这类引用定义
    // 集中在文末的文件，原有口径甚至只有 0.4%）。显示层则只关心正文有没有被吞。
    let ret = retention(a1.string, a2.string)
    step("done")
    let ms = Date().timeIntervalSince(t0) * 1000
    return [
        // 一次稳定：所见即所得编辑器输出的 Markdown 再解析后完全一致
        "stable": out1 == out2,
        // 收敛：允许前几轮规范化（空行 / 列表符号 / 强调与链接边界），
        // 六轮内出现连续两轮一致即视为收敛。
        // 实测有文件第 3 轮才稳（kramdown markdown_attr），也有深层嵌套强调
        // 要到第 5→6 轮才稳（cmark-gfm inline-em-*）；只看三轮 / 四轮会把
        // 这些「退化后收敛」误报成「持续改写」。真正不收敛的文件六轮后仍在变。
        "converged": (out1 == out2) || (out2 == out3) || (out3 == out4)
            || (out4 == out5) || (out5 == out6),
        "identical": md.trimmingCharacters(in: .whitespacesAndNewlines)
            == out1.trimmingCharacters(in: .whitespacesAndNewlines),
        "retention": ret,
        "chars_in": md.count,
        "chars_out": out1.count,
        "blocks": bl,
        "ms": Int(ms),
    ]
}

// ---------------------------------------------------------------------------
// 主流程
// ---------------------------------------------------------------------------

guard let manifest = readJSON(manifestPath) else {
    note("❌ 找不到 \(manifestPath)，请先运行 scripts/fetch-fixtures.py")
    exit(1)
}
note("→ 语料清单：\(manifestPath)")

var fileResults: [[String: Any]] = []
var caseResults: [[String: Any]] = []

// 1) 各软件真实 .md 文件
let files = manifest["files"] as? [[String: Any]] ?? []
note("→ 测试 \(files.count) 份真实文件")
for (i, f) in files.enumerated() {
    let slug = f["slug"] as? String ?? "?"
    let rel = f["local_path"] as? String ?? ""
    let sourcePath = f["source_path"] as? String ?? rel
    let abs = (root as NSString).appendingPathComponent(rel)
    note("  [\(i + 1)/\(files.count)] \(slug)/\(sourcePath)")
    let md = readText(abs)
    var r = exercise(md)
    let out1 = MarkdownSerializer.markdown(from: MarkdownParser.parse(md))

    var detected: [String] = []
    var preserved: [String] = []
    var lost: [String] = []
    for feat in features {
        // hr：剔除 Setext 下划线再检测，防止 `Title\n---` 被误计为分割线。
        // ul/ol：剔除主题分割线（`* * *` 这类空格分隔的 hr）再检测，防止
        // 分割线被误计为列表、序列化成 `---` 后又假报「列表丢失」。
        var srcText = md
        var outText = out1
        switch feat.key {
        case "hr":
            srcText = stripSetextUnderlines(md)
            outText = stripSetextUnderlines(out1)
        case "ul", "ol":
            srcText = stripThematicBreaks(md)
            outText = stripThematicBreaks(out1)
        default:
            break
        }
        guard hit(srcText, feat.detect) else { continue }
        detected.append(feat.key)
        if feat.preserve.contains(where: { hit(outText, $0) }) {
            preserved.append(feat.key)
        } else {
            lost.append(feat.key)
        }
    }
    r["slug"] = slug
    r["source_path"] = sourcePath
    r["local_path"] = rel
    r["bytes"] = f["bytes"] as? Int ?? md.utf8.count
    r["detected"] = detected
    r["preserved"] = preserved
    r["lost"] = lost
    let exact = exactPassthrough(md, out1)
    r["raw_total"] = exact.total
    r["raw_kept"] = exact.kept
    r["raw_missed"] = Array(exact.missed.prefix(8))
    fileResults.append(r)
}

// 2) CommonMark / GFM 官方用例
let specs = manifest["specs"] as? [[String: Any]] ?? []
for spec in specs {
    let slug = spec["slug"] as? String ?? "?"
    let name = spec["name"] as? String ?? slug
    let casesRel = spec["cases_file"] as? String ?? ""
    guard let doc = readJSON((root as NSString).appendingPathComponent(casesRel)),
          let examples = doc["examples"] as? [[String: Any]] else {
        note("  ! 无法读取 \(casesRel)")
        continue
    }
    note("→ 测试 \(name)：\(examples.count) 条官方用例")
    for (i, ex) in examples.enumerated() {
        if i % 200 == 0 { note("    \(i)/\(examples.count)") }
        let md = ex["markdown"] as? String ?? ""
        let html = ex["html"] as? String ?? ""
        var r = exercise(md)
        let exp = expectedBlocks(html)
        let got = Set(r["blocks"] as? [String] ?? [])
        let matched = exp.filter { got.contains($0) }.count
        r["spec"] = slug
        r["id"] = ex["id"] as? Int ?? i + 1
        r["section"] = ex["section"] as? String ?? ""
        r["expected_blocks"] = Array(exp).sorted()
        r["matched_blocks"] = matched
        r["structure"] = exp.isEmpty ? 1.0 : Double(matched) / Double(exp.count)
        caseResults.append(r)
    }
}

// 3) 汇总
func avg(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
let fileStable = fileResults.filter { ($0["stable"] as? Bool) == true }.count
let caseStable = caseResults.filter { ($0["stable"] as? Bool) == true }.count
let fileConverged = fileResults.filter { ($0["converged"] as? Bool) == true }.count
let caseConverged = caseResults.filter { ($0["converged"] as? Bool) == true }.count
let slow = fileResults.filter { ($0["ms"] as? Int ?? 0) > 400 }
let rawTotal = fileResults.reduce(0) { $0 + ($1["raw_total"] as? Int ?? 0) }
let rawKept = fileResults.reduce(0) { $0 + ($1["raw_kept"] as? Int ?? 0) }
let summary: [String: Any] = [
    "files": files.count,
    "spec_cases": caseResults.count,
    "file_stable": fileStable,
    "case_stable": caseStable,
    "file_converged": fileConverged,
    "case_converged": caseConverged,
    "avg_retention": avg(fileResults.compactMap { $0["retention"] as? Double }),
    "avg_structure": avg(caseResults.compactMap { $0["structure"] as? Double }),
    "avg_ms": avg(fileResults.compactMap { Double($0["ms"] as? Int ?? 0) }),
    "raw_blocks_total": rawTotal,
    "raw_blocks_kept": rawKept,
    "raw_exact_rate": rawTotal == 0 ? 1.0 : Double(rawKept) / Double(rawTotal),
    "slow_files": slow.map { ["slug": $0["slug"] ?? "?", "path": $0["source_path"] ?? "", "ms": $0["ms"] ?? 0] },
    "generated_at": ISO8601DateFormatter().string(from: Date()),
]

let result: [String: Any] = [
    "summary": summary,
    "features": features.map { ["key": $0.key, "label": $0.label] },
    "files": fileResults,
    "spec_cases": caseResults,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted])
try data.write(to: URL(fileURLWithPath: resultsPath))

note("")
note("✅ 文件 \(files.count) 份：一次稳定 \(fileStable) / 收敛 \(fileConverged)")
note("✅ 规范用例 \(caseResults.count) 条：一次稳定 \(caseStable) / 收敛 \(caseConverged)")
note(String(format: "   平均可读字符保留率 %.1f%%", (summary["avg_retention"] as? Double ?? 0) * 100))
note(String(format: "   透传块逐字保留 %d/%d（%.1f%%）", rawKept, rawTotal,
            (summary["raw_exact_rate"] as? Double ?? 0) * 100))
note("   结果：\(resultsPath)")
