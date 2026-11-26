import Foundation
import AppKit

// 删除线 + 裸邮箱 vs 粗体 + 裸邮箱：解析属性与序列化对照探针
let cases = [
    "~~hello@email.com~~",
    "**me@example.com**",
    "__test@test.com__",
    "hello@email.com",
    "~~plain text~~",
    "~~**bold** email~~",
]

for md in cases {
    let a = InlineParser.parse(md, base: [:])
    print("== \(md) ==")
    print("   out:", MarkdownSerializer.markdown(from: a).debugDescription)
    let s = a.string as NSString
    a.enumerateAttributes(in: NSRange(location: 0, length: s.length), options: []) { attrs, r, _ in
        let txt = s.substring(with: r)
        var keys: [String] = []
        if let v = attrs[.strikethroughStyle] as? Int, v != 0 { keys.append("strike") }
        if let f = attrs[.font] as? NSFont {
            let t = f.fontDescriptor.symbolicTraits
            if t.contains(.bold) { keys.append("bold") }
            if t.contains(.italic) { keys.append("italic") }
        }
        if let l = attrs[.link] { keys.append("link=\(l)") }
        if attrs[.underlineStyle] != nil { keys.append("underline") }
        print("   run \(txt.debugDescription): \(keys.joined(separator: ","))")
    }
}

// 块级路径对照（MarkdownParser + MarkdownSerializer 全链）
print("\n==== block-level (MarkdownParser) ====")
for md in cases {
    let doc = MarkdownParser.parse(md)
    print("== \(md) ==")
    print("   out:", MarkdownSerializer.markdown(from: doc).debugDescription)
    let s = doc.string as NSString
    doc.enumerateAttributes(in: NSRange(location: 0, length: s.length), options: []) { attrs, r, _ in
        let txt = s.substring(with: r)
        var keys: [String] = []
        if let v = attrs[.strikethroughStyle] as? Int, v != 0 { keys.append("strike") }
        if let f = attrs[.font] as? NSFont {
            let t = f.fontDescriptor.symbolicTraits
            if t.contains(.bold) { keys.append("bold") }
            if t.contains(.italic) { keys.append("italic") }
        }
        if let l = attrs[.link] { keys.append("link=\(l)") }
        if attrs[.mdVerbatimLine] != nil { keys.append("verbatim") }
        print("   run \(txt.debugDescription): \(keys.joined(separator: ","))")
    }
}
