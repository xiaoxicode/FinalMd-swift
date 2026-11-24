//
//  ObsidianLinks.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  Obsidian 双链 / 嵌入的「库内解析」：把 [[Note#标题]] 解析成文件 + 定位，
//  在笔记库里找目标文件，读取嵌入预览内容。
//
//  刻意只依赖 Foundation / AppKit，不 import SwiftUI：这样冒烟测试能直接编译
//  验证路径解析、标题定位、块引用定位这些最容易写错的纯逻辑。
//

import Foundation
import AppKit

struct ObsidianTarget: Equatable {
    /// 双链里的目标（可能是 "Note"、"folder/Note"、"pic.png"）
    var file: String
    /// `#标题` 里的标题文字，nil 表示没有
    var heading: String?
    /// `#^blockid` 里的块 ID，nil 表示没有
    var block: String?
    var embedded: Bool
}

/// 嵌入预览的数据。用路径而不是 NSImage，便于 Equatable 与 DialogKind 复用。
struct EmbedPreview: Equatable, Identifiable {
    var id: String { title + "#" + String(text.prefix(48)) }
    let title: String
    let text: String
    /// 图片类嵌入：这里放本地文件路径，展示时再构造 NSImage
    let imagePath: String?

    var isImage: Bool { imagePath != nil }
}

enum ObsidianResolver {

    /// `[[Note#标题]]` / `[[Note#^block]]` / `![[pic.png|100]]` → 结构化目标
    static func target(from link: MDWikiLink) -> ObsidianTarget {
        var heading: String?
        var block: String?
        let suffix = link.suffix
        if suffix.hasPrefix("#^") {
            let id = String(suffix.dropFirst(2))
            if !id.isEmpty { block = id }
        } else if suffix.hasPrefix("#") {
            let name = String(suffix.dropFirst(1))
            if !name.isEmpty { heading = name }
        }
        return ObsidianTarget(file: link.target,
                              heading: heading,
                              block: block,
                              embedded: link.embedded)
    }

    /// 在笔记库里找目标文件。先按当前文档所在目录直接命中，再浅层递归查找。
    /// - documentPath: 当前打开的 .md 路径
    /// - vaultRoot: 用户最近打开过的目录（未命名文档时用它）
    static func resolve(file: String, near documentPath: String?, vaultRoot: String?) -> URL? {
        let name = file.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("..") else { return nil }
        let fm = FileManager.default

        var dirs: [String] = []
        if let path = documentPath, !path.isEmpty {
            dirs.append((path as NSString).deletingLastPathComponent)
        }
        if let root = vaultRoot, !root.isEmpty, !dirs.contains(root) {
            dirs.append(root)
        }
        guard !dirs.isEmpty else { return nil }

        let ext = (name as NSString).pathExtension.lowercased()
        let candidates: [String]
        if ext.isEmpty {
            candidates = [name + ".md", name + ".markdown", name + ".txt"]
        } else {
            candidates = [name]
        }

        for dir in dirs {
            for candidate in candidates {
                let path = (dir as NSString).appendingPathComponent(candidate)
                if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
            }
        }

        // 库内同名笔记（Obsidian 允许不写目录）：限制深度与遍历量，避免大库卡顿
        let wanted = ((name as NSString).lastPathComponent as NSString).deletingPathExtension
        guard !wanted.isEmpty else { return nil }
        for dir in dirs {
            let root = URL(fileURLWithPath: dir)
            guard let walker = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            let baseDepth = root.pathComponents.count
            var visited = 0
            for case let url as URL in walker {
                visited += 1
                if visited > 20_000 { break }
                if url.pathComponents.count - baseDepth > 4 {
                    walker.skipDescendants()
                    continue
                }
                let stem = (url.lastPathComponent as NSString).deletingPathExtension
                if stem.compare(wanted, options: .caseInsensitive) == .orderedSame {
                    return url
                }
            }
        }
        return nil
    }

    /// 在解析后的排版文本里定位某个标题段落
    static func headingRange(_ heading: String, in storage: NSAttributedString) -> NSRange? {
        let wanted = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        var loc = 0
        while loc < ns.length {
            let range = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            if range.length == 0 { break }
            loc = NSMaxRange(range)
            let type = storage.attribute(.mdBlockType, at: range.location, effectiveRange: nil) as? String ?? ""
            guard type.hasPrefix("h"), type.count == 2 else { continue }
            let text = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.compare(wanted, options: .caseInsensitive) == .orderedSame
                || text.localizedCaseInsensitiveContains(wanted) {
                return range
            }
        }
        return nil
    }

    /// 定位 `^blockid` 所在段落
    static func blockRange(_ id: String, in storage: NSAttributedString) -> NSRange? {
        let marker = "^" + id.trimmingCharacters(in: .whitespaces)
        guard marker.count > 1, storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        var loc = 0
        while loc < ns.length {
            let range = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            if range.length == 0 { break }
            loc = NSMaxRange(range)
            if ns.substring(with: range).contains(marker) { return range }
        }
        return nil
    }

    /// 读取嵌入目标的内容用于预览面板
    static func preview(at url: URL) -> EmbedPreview? {
        let title = url.lastPathComponent
        if isImage(url) {
            return EmbedPreview(title: title, text: "", imagePath: url.path)
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return EmbedPreview(title: title, text: text, imagePath: nil)
    }

    static func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "svg", "pdf"]
            .contains(url.pathExtension.lowercased())
    }
}
