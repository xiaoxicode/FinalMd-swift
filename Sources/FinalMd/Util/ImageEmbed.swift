//
//  ImageEmbed.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  图片以 Base64 Data URL 内嵌进 Markdown（对应 Electron 版 app.js 的 compressIfNeeded）。
//  超过 380KB 自动压缩：最长边缩到 1600px，并转为 JPEG 质量 0.86。
//

import AppKit

enum ImageEmbed {

    static let sizeThreshold = 380 * 1024
    static let maxEdge: CGFloat = 1600

    /// NSImage → PNG 数据
    static func pngData(image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// PNG 数据 → Data URL
    static func dataURL(pngData data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        return "data:image/png;base64," + data.base64EncodedString()
    }

    /// 按需压缩后返回 Data URL
    static func compressedDataURL(image: NSImage, maxEdge: CGFloat = ImageEmbed.maxEdge) -> String? {
        let target = scaleDown(image: image, maxEdge: maxEdge)

        if let png = pngData(image: target), png.count <= sizeThreshold {
            return dataURL(pngData: png)
        }
        // 体积仍然偏大 → 转 JPEG
        if let jpeg = jpegData(image: target, quality: 0.86) {
            return "data:image/jpeg;base64," + jpeg.base64EncodedString()
        }
        if let png = pngData(image: target) { return dataURL(pngData: png) }
        return nil
    }

    /// 最长边超过 maxEdge 时等比缩小
    static func scaleDown(image: NSImage, maxEdge: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return image }

        let scale = maxEdge / longest
        let newSize = NSSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let result = NSImage(size: newSize)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1)
        result.unlockFocus()
        return result
    }

    static func jpegData(image: NSImage, quality: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
