//
//  MarkdownCompatibility.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  打开外部 Markdown 前的「兼容性体检」。
//
//  不维护一张「哪些语法不支持」的清单 —— 那张清单会随着解析器补齐功能而过时。
//  这里直接用产品里真实的 MarkdownParser / MarkdownSerializer 跑一轮往返，
//  用「有多少行会被改写」和「可读字符保留率」判断这份文件是否适合即刻模式。
//  FinalMd 自己保存的文档往返稳定，changedLines = 0，因此不会被打扰。
//

import Foundation

struct MarkdownAssessment: Equatable {
    /// 原文里在往返输出中找不到对应行的行数（忽略首尾空白与空行）
    var changedLines: Int = 0
    /// 字母 / 数字 / CJK 字符按顺序保留的比例
    var retention: Double = 1
    /// 命中的扩展写法标识（用于报告与诊断，不逐条本地化）
    var syntaxHits: [String] = []

    /// 是否需要在打开前提醒用户。
    /// 三选一：改写两行以上、可读字符有丢失、或同时命中多类扩展语法且已有改写。
    /// 单纯「`*` 列表统一成 `-`」这类只有一行、且不含扩展语法的规范化不打扰用户。
    var needsCare: Bool {
        changedLines >= 2
            || retention < 0.995
            || (changedLines >= 1 && syntaxHits.count >= 2)
    }
}

enum MarkdownCompatibility {

    /// 体检一份外部 Markdown。纯计算，不触碰任何编辑器状态。
    static func assess(_ source: String) -> MarkdownAssessment {
        let src = normalize(source)
        guard !src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return MarkdownAssessment()
        }
        let out = MarkdownSerializer.markdown(from: MarkdownParser.parse(src))
        return MarkdownAssessment(
            changedLines: changedLineCount(src, out),
            retention: retainedCharacters(src, out),
            syntaxHits: detectSyntax(src)
        )
    }

    static func normalize(_ s: String) -> String {
        var text = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    /// 按「行的多重集合」比较，重排不会被误判成改写，但列表符号统一、
    /// Setext 标题改 ATX、段落合并这类真实变化都会被算进来。
    static func changedLineCount(_ src: String, _ out: String) -> Int {
        var pool: [String: Int] = [:]
        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            let key = line.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { pool[key, default: 0] += 1 }
        }
        var changed = 0
        for line in src.split(separator: "\n", omittingEmptySubsequences: false) {
            let key = line.trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }
            if let n = pool[key], n > 0 {
                pool[key] = n - 1
            } else {
                changed += 1
            }
        }
        return changed
    }

    /// 字符级顺序保留率：只统计字母 / 数字，用于发现内容被吞掉。
    static func retainedCharacters(_ src: String, _ out: String) -> Double {
        func readable(_ s: String) -> [Character] {
            s.filter { $0.isLetter || $0.isNumber }
        }
        let a = readable(src)
        let b = readable(out)
        guard !a.isEmpty else { return 1 }
        var j = 0
        var hit = 0
        for ch in a {
            while j < b.count, b[j] != ch { j += 1 }
            if j < b.count { hit += 1; j += 1 }
        }
        return Double(hit) / Double(a.count)
    }

    /// 当前仍会让即刻模式做规范化、或尚未结构化支持的扩展写法。
    /// 已逐字保真的 frontmatter / HTML 块 / 链接定义 / 双链 / Callout /
    /// 任务框 / 缩进代码块刻意不列入，避免提示已经解决的问题。
    static func detectSyntax(_ src: String) -> [String] {
        let patterns: [(String, String)] = [
            ("setext",      #"(?m)^[^\n]+\n[=-]{2,}\s*$"#),
            ("math",        #"(?m)^\s*\$\$"#),
            ("footnote",    #"\[\^[^\]]+\]"#),
            ("hardbreak",   #"(?m)\S {2,}$"#),
            ("diagram",     #"(?m)^\s*(```|~~~)\s*(mermaid|plantuml|dot|graphviz)"#),
            ("critic",      #"\{\+[^\n]+\+\}|\{--[^\n]+--\}| \{==[^\n]+==\}"#),
            ("qmd",         #"(?m)^\s*```\{[^\n]+\}"#),
            ("toc",         #"\[TOC\]"#),
            ("nested",      #"(?m)^ {4,}[-*+]\s+\S"#),
        ]
        return patterns.compactMap { key, pattern in
            src.range(of: pattern, options: .regularExpression) != nil ? key : nil
        }
    }
}
