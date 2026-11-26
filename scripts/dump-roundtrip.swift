//
//  dump-roundtrip.swift — 调试工具：把单个文件的 parse→serialize 结果打印出来
//  用法（编译方式同 run-compat.sh，产物放 /tmp/finalmd-dump）：
//    /tmp/finalmd-dump <file.md> [rounds]
//
import Foundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: dump <file.md> [rounds]\n", stderr)
    exit(1)
}
let path = args[1]
let rounds = args.count > 2 ? Int(args[2]) ?? 2 : 2
guard let data = FileManager.default.contents(atPath: path) else {
    fputs("cannot read \(path)\n", stderr)
    exit(1)
}
var md = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
print("== INPUT (\(md.count) chars) ==")
print(md)
if ProcessInfo.processInfo.environment["FINALMD_DUMP_ATTRS"] == "1" {
    let parsed = MarkdownParser.parse(md)
    print("\n== PARSED ATTRS ==")
    print(parsed)
    let full = NSRange(location: 0, length: parsed.length)
    parsed.enumerateAttributes(in: full, options: []) { attrs, range, _ in
        let keys = attrs.keys.map { "\($0.rawValue)" }.sorted().joined(separator: ",")
        print("  run \(range.location):\(range.length) keys=[\(keys)]")
    }
}
var current = md
for i in 1...rounds {
    let attr = MarkdownParser.parse(current)
    let out = MarkdownSerializer.markdown(from: attr)
    print("\n== ROUND \(i) OUT (\(out.count) chars) ==")
    print(out)
    if out == current {
        print("\n== STABLE at round \(i) ==")
        break
    }
    current = out
}
