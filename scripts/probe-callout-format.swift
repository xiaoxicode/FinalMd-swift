import AppKit

// Callout「只改格式不改文字」探针：验证开关 ON/OFF 下的写回行为。
let md = """
> [!NOTE] 标题
> 这里有 **加粗** 与 *斜体*

"""

func dump(_ label: String, _ s: String) {
    print("== \(label) ==")
    print(repr(s))
}

func repr(_ s: String) -> String {
    s.debugDescription
}

let doc = MarkdownParser.parse(md)
let ns = doc.string as NSString
print("display:", repr(doc.string))
let boldRange = ns.range(of: "加粗")
print("boldRange:", boldRange.location, boldRange.length)

// 只改格式：把「加粗」去掉粗体（换成正文字体）
let edited = NSMutableAttributedString(attributedString: doc)
if boldRange.location != NSNotFound {
    edited.addAttribute(.font, value: DocTheme.bodyFont, range: boldRange)
}

// 开关 ON（默认）：格式改动生效 → 应重建该行
MarkdownSerializer.calloutFormatEdits = true
let onOut = MarkdownSerializer.markdown(from: edited)
dump("ON out1", onOut)
let on2 = MarkdownParser.parse(onOut)
let onOut2 = MarkdownSerializer.markdown(from: on2)
print("ON stable:", onOut == onOut2)
print("ON 长字面星号:", on2.string.contains("*"))
print("ON 仍有加粗标记:", onOut.contains("**加粗**"))
print("ON 内容仍在:", onOut.contains("加粗"))

// 开关 OFF：逐字保真优先 → 应写回原行（格式改动被丢弃）
MarkdownSerializer.calloutFormatEdits = false
let offOut = MarkdownSerializer.markdown(from: edited)
dump("OFF out1", offOut)
print("OFF == 原文:", offOut == md)
MarkdownSerializer.calloutFormatEdits = true

// 未编辑行：两种模式都逐字
let clean = MarkdownParser.parse(md)
print("未编辑 ON 逐字:", MarkdownSerializer.markdown(from: clean) == md)
MarkdownSerializer.calloutFormatEdits = false
print("未编辑 OFF 逐字:", MarkdownSerializer.markdown(from: clean) == md)
MarkdownSerializer.calloutFormatEdits = true

// 改文字仍要生效（开关 OFF 也不能盖掉）
let textEdit = NSMutableAttributedString(attributedString: doc)
if boldRange.location != NSNotFound {
    textEdit.replaceCharacters(in: boldRange, with: "重点")
}
MarkdownSerializer.calloutFormatEdits = false
let textOut = MarkdownSerializer.markdown(from: textEdit)
print("OFF 改文字仍生效:", textOut.contains("重点") && !textOut.contains("加粗"))
MarkdownSerializer.calloutFormatEdits = true

// 给普通文字加粗（反向格式改动）也应生效
let embolden = NSMutableAttributedString(attributedString: doc)
let plain = ns.range(of: "斜体")
if plain.location != NSNotFound {
    let boldFont = NSFont.boldSystemFont(ofSize: DocTheme.bodyFontSize)
    embolden.addAttribute(.font, value: boldFont, range: plain)
}
let embOut = MarkdownSerializer.markdown(from: embolden)
dump("加粗斜体 out", embOut)
print("反向格式生效:", embOut.contains("**斜体**"))
