#!/usr/bin/env swift
// 生成 FinalMd 应用图标：红色渐变圆角底 + 白色粗体大写 M。
// 用法：swift scripts/generate-icon.swift [输出 .icns 路径]
// 默认写入 Resources/AppIcon.icns；只依赖 macOS 自带的 AppKit / CoreText / sips / iconutil。

import AppKit
import CoreGraphics
import CoreText

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"
let S = 1024

// MARK: - 绘制 1024×1024 主图

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("无法创建绘图上下文")
}

let rect = CGRect(x: 0, y: 0, width: CGFloat(S), height: CGFloat(S))
let radius: CGFloat = 218
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()

// 红色渐变（上 #FF6B6B → 下 #C92A2A）
let top = CGColor(colorSpace: cs, components: [255/255, 107/255, 107/255, 1])!
let bottom = CGColor(colorSpace: cs, components: [201/255, 42/255, 42/255, 1])!
let gradient = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(S)),
                       end: CGPoint(x: 0, y: 0), options: [])

let font: CTFont = {
    if let f = NSFont(name: "SF Pro Display Bold", size: 690) { return f as CTFont }
    return NSFont.boldSystemFont(ofSize: 690) as CTFont
}()
let attrs: [CFString: Any] = [
    kCTFontAttributeName: font,
    kCTForegroundColorAttributeName: NSColor.white.cgColor,
]
let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, "M" as CFString, attrs as CFDictionary)!
let line = CTLineCreateWithAttributedString(attrStr)
var bounds = CTLineGetImageBounds(line, ctx)
if bounds.isNull { bounds = CGRect(x: 0, y: 0, width: 500, height: 500) }
ctx.textPosition = CGPoint(
    x: (CGFloat(S) - bounds.width) / 2 - bounds.minX,
    y: (CGFloat(S) - bounds.height) / 2 - bounds.minY
)
CTLineDraw(line, ctx)

guard let image = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("PNG 编码失败")
}

// MARK: - 生成 iconset 并打包 .icns

let fm = FileManager.default
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("finalmd-icon-\(UUID().uuidString)")
try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
let iconset = tmp.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let master = tmp.appendingPathComponent("master.png")
try png.write(to: master)

func run(_ path: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { fatalError("\(path) 启动失败: \(error)") }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { fatalError("\(path) 退出码 \(p.terminationStatus)") }
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (px, name) in sizes {
    run("/usr/bin/sips", ["-Z", "\(px)", master.path, "--out", iconset.appendingPathComponent(name).path])
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", output])
try? fm.removeItem(at: tmp)
print("已生成 \(output)")
