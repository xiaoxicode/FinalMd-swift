//
//  probe-html.swift — 取一段 Markdown 的 FinalMd HTML 导出与往返序列化
//  用法: /tmp/finalmd-probe '<markdown>'   或   /tmp/finalmd-probe -f file.md
//
import Foundation
import AppKit

let args = CommandLine.arguments
var md = ""
if args.count >= 3, args[1] == "-f" {
    md = String(decoding: FileManager.default.contents(atPath: args[2]) ?? Data(), as: UTF8.self)
} else if args.count >= 2 {
    md = args[1]
} else {
    md = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
}

let a1 = MarkdownParser.parse(md)
let out1 = MarkdownSerializer.markdown(from: a1)
let a2 = MarkdownParser.parse(out1)
let out2 = MarkdownSerializer.markdown(from: a2)
let html = MarkdownSerializer.html(a1)
print("== HTML ==")
print(html)
print("== OUT1 ==")
print(out1)
print("== STABLE: \(out1 == out2) ==")
