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

func hit(_ s: String, _ pattern: String) -> Bool {
    s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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
    Feature(key: "refdef", label: "引用式链接定义", detect: #"(?m)^\s{0,3}\[[^\]]+\]:\s*\S+"#,
            preserve: [#"(?m)^\s{0,3}\[[^\]]+\]:\s*\S+"#]),
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
    Feature(key: "image", label: "图片", detect: #"!\[[^\]\n]*\]\([^)\n]+\)"#,
            preserve: [#"!\[[^\]\n]*\]\([^)\n]+\)"#]),
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
    Feature(key: "toc", label: "[TOC] 目录", detect: #"\[TOC\]"#, preserve: [#"\[TOC\]"#]),
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

func blockTypes(_ a: NSAttributedString) -> Set<String> {
    var out = Set<String>()
    guard a.length > 0 else { return out }
    a.enumerateAttribute(.mdBlockType,
                         in: NSRange(location: 0, length: a.length),
                         options: []) { value, _, _ in
        if let s = value as? String { out.insert(s) }
    }
    return out
}

func expectedBlocks(_ html: String) -> Set<String> {
    let pairs: [(String, String)] = [
        ("<h1", "h1"), ("<h2", "h2"), ("<h3", "h3"),
        ("<h4", "h4"), ("<h5", "h5"), ("<h6", "h6"),
        ("<blockquote", "quote"), ("<pre", "code"), ("<p>", "p"),
    ]
    var out = Set<String>()
    for (tag, name) in pairs where html.contains(tag) { out.insert(name) }
    return out
}

/// 跑一轮 parse → serialize → parse → serialize，返回关键指标
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
    step("blockTypes")
    let bl = Array(blockTypes(a1)).sorted()
    step("retention")
    let ret = retention(md, out1)
    step("done")
    let ms = Date().timeIntervalSince(t0) * 1000
    return [
        // 一次稳定：所见即所得编辑器输出的 Markdown 再解析后完全一致
        "stable": out1 == out2,
        // 收敛：允许第一轮规范化（空行 / 列表符号 / frontmatter 重排），
        // 但第二轮起必须稳定；不收敛才意味着真正会持续改写文件。
        "converged": (out1 == out2) || (out2 == out3),
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
    for feat in features where hit(md, feat.detect) {
        detected.append(feat.key)
        if feat.preserve.contains(where: { hit(out1, $0) }) {
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
let summary: [String: Any] = [
    "files": files.count,
    "spec_cases": caseResults.count,
    "file_stable": fileStable,
    "case_stable": caseStable,
    "file_converged": fileConverged,
    "case_converged": caseConverged,
    "avg_retention": avg(fileResults.compactMap { $0["retention"] as? Double }),
    "avg_ms": avg(fileResults.compactMap { Double($0["ms"] as? Int ?? 0) }),
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
note("   结果：\(resultsPath)")
