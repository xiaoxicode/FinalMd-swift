// 探针：打印块的 display / 逐行快照数组，定位逐行机制为何未生效
import Foundation
import AppKit

func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{2028}", with: "<SP>")
     .replacingOccurrences(of: "\n", with: "<NL>")
     .replacingOccurrences(of: "\u{200B}", with: "<ZW>")
}

let inputs = [
    "> ```\n> code\n> ```\n",
    "*a\nb*\n",
    "- a\n  lazy\n- b\n",
    "x **y**\nz *w*\n",
]
for md in inputs {
    print("=== input:", esc(md))
    let attr = MarkdownParser.parse(md)
    print("    doc display:", esc(attr.string))
    attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
        let sub = (attr.string as NSString).substring(with: range)
        let src = attrs[.mdEmphasisSource] as? String
        let disp = attrs[.mdEmphasisDisplay] as? String
        let ls = attrs[.mdLineSources] as? [String]
        let qsrc = attrs[.mdQuoteRaw] as? String
        let qls = attrs[.mdQuoteLineSources] as? [String]
        let qld = attrs[.mdQuoteLineDisplays] as? [String]
        if src != nil || ls != nil || qsrc != nil {
            print("    run[\(range.location)+\(range.length)] text:", esc(sub))
            if let s = src { print("      emphasisSource:", esc(s)) }
            if let d = disp { print("      emphasisDisplay:", esc(d)) }
            if let l = ls { print("      lineSources:", l.map(esc)) }
            if let q = qsrc { print("      quoteRaw:", esc(q)) }
            if let l = qls { print("      quoteLineSources:", l.map(esc)) }
            if let l = qld { print("      quoteLineDisplays:", l.map(esc)) }
        }
    }
    let out = MarkdownSerializer.markdown(from: attr)
    print("    out1:", esc(out))
}

func dumpRuns(_ attr: NSAttributedString, _ tag: String) {
    print("  -- runs(\(tag)):")
    attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
        let sub = (attr.string as NSString).substring(with: range)
        let font = attrs[.font] as? NSFont
        let bold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        let italic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
        print("    [\(range.location)+\(range.length)]", esc(sub), "bold:", bold, "italic:", italic)
    }
}

// ——— 编辑场景：围栏组对齐 / 跨行强调重建 ———
let fenceMd = "> ```\n> code\n> ```\n"
let qEdit = NSMutableAttributedString(attributedString: MarkdownParser.parse(fenceMd))
dumpRuns(qEdit, "fence parsed")
print("  fence map:", qEdit.attribute(.mdQuoteLineMap, at: 0, effectiveRange: nil) ?? "nil")
qEdit.replaceCharacters(in: (qEdit.string as NSString).range(of: "code"), with: "codes")
let qOut = MarkdownSerializer.markdown(from: qEdit)
print("=== fence edit out:", esc(qOut))
let qRe = MarkdownParser.parse(qOut)
print("    reparse display:", esc(qRe.string))
print("    out2:", esc(MarkdownSerializer.markdown(from: qRe)))

let xEdit = NSMutableAttributedString(attributedString: MarkdownParser.parse("*a\nb*\n"))
dumpRuns(xEdit, "crossline parsed")
xEdit.replaceCharacters(in: (xEdit.string as NSString).range(of: "a"), with: "aa")
dumpRuns(xEdit, "crossline edited")
let xOut = MarkdownSerializer.markdown(from: xEdit)
print("=== crossline edit out:", esc(xOut))
let xRe = MarkdownParser.parse(xOut)
print("    reparse display:", esc(xRe.string))
print("    out2:", esc(MarkdownSerializer.markdown(from: xRe)))
