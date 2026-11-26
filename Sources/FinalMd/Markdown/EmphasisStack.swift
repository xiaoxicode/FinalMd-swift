//
//  EmphasisStack.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  CommonMark 0.31.2 §6.4「Emphasis and strong emphasis」定界符栈。
//
//  替换原先「首个匹配即闭合」的递归下降：那个算法在 `***a ***b***`
//  这类重叠定界符上每轮换一种切分，前 4 轮持续搬家、嵌套语义被压平。
//
//  算法与 cmark / commonmark.js 一致：
//   1. 扫描 `*` / `_` 的连续 run，按 left/right-flanking 标记 canOpen / canClose；
//   2. 从左到右处理 closer，在栈里找最近的合法 opener，遵守 rule of 9/10
//      （长度和为 3 的倍数、且并非都是 3 的倍数时不许配对）；
//   3. 命中后按可用长度取 1（em）或 2（strong）个字符，扣减后继续找更远的 opener；
//   4. 把命中区间映射成字符级 bold/italic，未命中的定界符保留为字面文本。
//
//  代码 span / 反斜杠转义 / 链接与双链 / 行内 HTML 内部的字符不参与定界符扫描，
//  与 InlineParser 的原子边界保持一致。
//

import Foundation

enum EmphasisStack {

    /// 一段行内文本的强调解析结果
    struct Plan: Equatable {
        /// 被定界符占用的字符位置：渲染时跳过（不显示）
        var skipped: Set<Int> = []
        /// 内容字符应有的粗体 / 斜体位置
        var bold: Set<Int> = []
        var italic: Set<Int> = []
        /// 命中区间（内容端点，不含定界符），供快照与 HTML 使用
        var spans: [Span] = []
    }

    struct Span: Equatable {
        let start: Int
        let end: Int
        let strong: Bool
    }

    private struct Delimiter {
        let char: Character
        /// run 起始位置
        let start: Int
        /// run 长度（原始，commonmark.js 的 origdelims）
        let originalLength: Int
        /// 剩余可用长度（commonmark.js 的 numdelims）
        var length: Int
        let canOpen: Bool
        let canClose: Bool
        /// 是否仍在定界符栈中。配对成功后中间的 delimiter 会被摘除
        /// （commonmark.js 的 removeDelimitersBetween），摘除后不再参与后续配对。
        var alive = true
    }

    // MARK: - 入口

    /// 精确对齐 commonmark.js 0.31.2 的 processEmphasis 定界符栈算法。
    /// 用数组 + alive 标记模拟它的双向链表摘除语义（removeDelimitersBetween /
    /// removeDelimiter），并保留 openers_bottom 剪枝——这三者缺一都会在
    /// `__foo_ bar_`、`*foo *bar**`、`*foo _bar* baz_` 这类用例上配错。
    static func plan(_ chars: [Character]) -> Plan {
        var stack = collectDelimiters(chars)
        var result = Plan()
        guard !stack.isEmpty else { return result }

        // opener 从右端消耗、closer 从左端消耗；合并后得到应跳过的语法标记位置。
        var usedRight = Array(repeating: 0, count: stack.count)
        var usedLeft = Array(repeating: 0, count: stack.count)

        // openers_bottom[14]：与 commonmark.js 同构的搜索下界剪枝。
        // 存 delimiter 索引；nil 表示尚未设置（下界为栈底）。
        var openersBottom: [Int?] = Array(repeating: nil, count: 14)
        let stackBottom = -1

        func bottomIndex(_ d: Delimiter) -> Int {
            // 0/1 是单引号/双引号槽位，本解析器不处理智能引号，只用 2..13。
            if d.char == "_" {
                return 2 + (d.canOpen ? 3 : 0) + (d.originalLength % 3)
            }
            return 8 + (d.canOpen ? 3 : 0) + (d.originalLength % 3)
        }

        // 前一个 / 后一个仍 alive 的 delimiter 索引；找不到分别返回 stackBottom / count。
        func prevAlive(_ i: Int) -> Int {
            var j = i - 1
            while j >= 0 {
                if stack[j].alive { return j }
                j -= 1
            }
            return stackBottom
        }
        func nextAlive(_ i: Int) -> Int {
            var j = i + 1
            while j < stack.count {
                if stack[j].alive { return j }
                j += 1
            }
            return stack.count
        }

        // 从左到右处理 closer；配对成功但 closer 仍有余量时原地重试同一个 closer。
        var ci = 0
        while ci < stack.count {
            guard stack[ci].alive, stack[ci].canClose, stack[ci].length > 0 else {
                ci = nextAlive(ci)
                continue
            }

            let bi = bottomIndex(stack[ci])
            let lower = openersBottom[bi] ?? stackBottom

            // 回看找最近的合法 opener，遇到下界即停（下界本身不参与，与权威 `!==` 一致）。
            var oi = prevAlive(ci)
            var openerFound = false
            while oi != stackBottom, oi != lower {
                let opener = stack[oi], closer = stack[ci]
                // CommonMark rule of 9/10（权威 odd_match）：
                // 仅当 closer 也能 open 或 opener 也能 close、且 closer 原始长度不是 3 的倍数、
                // 且两侧原始长度之和是 3 的倍数时，禁止这次配对。
                let oddMatch = (closer.canOpen || opener.canClose)
                    && closer.originalLength % 3 != 0
                    && (opener.originalLength + closer.originalLength) % 3 == 0
                if opener.canOpen, opener.char == closer.char, !oddMatch {
                    openerFound = true
                    break
                }
                oi = prevAlive(oi)
            }

            if !openerFound {
                // 没找到：把当前 closer 的前一个节点设为该槽位新下界；
                // 若它不能 open，则从栈中摘除（权威 removeDelimiter）。
                openersBottom[bi] = prevAlive(ci)
                if !stack[ci].canOpen { stack[ci].alive = false }
                ci = nextAlive(ci)
                continue
            }

            // 配对成功：取 1（em）或 2（strong）个字符。
            let use = (stack[ci].length >= 2 && stack[oi].length >= 2) ? 2 : 1
            let strong = use == 2
            let contentStart = stack[oi].start + stack[oi].originalLength
            let contentEnd = stack[ci].start
            result.spans.append(Span(start: contentStart, end: contentEnd, strong: strong))
            if contentEnd > contentStart {
                for p in contentStart..<contentEnd {
                    if strong { result.bold.insert(p) } else { result.italic.insert(p) }
                }
            }

            // 消耗内侧字符：opener 从右端、closer 从左端。
            stack[oi].length -= use
            stack[ci].length -= use
            usedRight[oi] += use
            usedLeft[ci] += use

            // removeDelimitersBetween：摘除 opener 与 closer 之间的所有 delimiter，
            // 它们不再参与后续配对（*foo _bar* baz_ 里的 `_` 因此保持字面）。
            var k = nextAlive(oi)
            while k != ci, k < stack.count {
                let nxt = nextAlive(k)
                stack[k].alive = false
                k = nxt
            }

            // 用尽则摘除端点；closer 用尽才前进，否则原地重试同一个 closer。
            if stack[oi].length == 0 { stack[oi].alive = false }
            if stack[ci].length == 0 {
                let nxt = nextAlive(ci)
                stack[ci].alive = false
                ci = nxt
            }
        }

        // 只有被配对消耗的字符才是语法标记；未配对的按字面显示（`* foo` 不被吞）。
        for (i, d) in stack.enumerated() {
            let right = usedRight[i]
            let left = usedLeft[i]
            if right > 0 {
                for p in (d.start + d.originalLength - right)..<(d.start + d.originalLength) {
                    result.skipped.insert(p)
                }
            }
            if left > 0 {
                for p in d.start..<(d.start + left) { result.skipped.insert(p) }
            }
        }

        return result
    }

    // MARK: - 定界符扫描

    private static func collectDelimiters(_ chars: [Character]) -> [Delimiter] {
        let n = chars.count
        var runs: [Delimiter] = []
        var i = 0
        while i < n {
            let c = chars[i]

            // 反斜杠转义：被转义的字符（含 * / _）不是定界符
            if c == "\\", i + 1 < n { i += 2; continue }

            // 行内代码：整段跳过
            if c == "`" {
                if let end = findRunEnd("`", chars, from: i + 1) { i = end + 1; continue }
                i += 1
                continue
            }

            // 删除线 ~~不属于 CommonMark 强调，内部的 * 由递归 parse 处理
            if c == "~", i + 1 < n, chars[i + 1] == "~" {
                var j = i + 2
                while j + 1 < n, !(chars[j] == "~" && chars[j + 1] == "~") { j += 1 }
                if j + 1 < n { i = j + 2; continue }
                i += 2
                continue
            }

            // 行内 HTML 标签：整段跳过（尖括号内的 * 不是强调）
            if c == "<", let end = chars[i...].firstIndex(of: ">") {
                i = chars.index(after: end)
                continue
            }

            // Obsidian 双链 / 图片 / 标准链接：整段跳过，内部由递归 parse 处理
            if c == "[" || (c == "!" && i + 1 < n && chars[i + 1] == "[") {
                if let end = atomEnd(chars, at: i) { i = end + 1; continue }
            }

            if c == "*" || c == "_" {
                var j = i + 1
                while j < n, chars[j] == c { j += 1 }
                let before = i > 0 ? chars[i - 1] : nil
                let after = j < n ? chars[j] : nil
                let (open, close) = flanking(c, before: before, after: after)
                runs.append(Delimiter(char: c, start: i, originalLength: j - i,
                                      length: j - i, canOpen: open, canClose: close))
                i = j
                continue
            }

            i += 1
        }
        return runs
    }

    /// 找到原子语法（链接 / 双链 / 图片）的结束位置，失败返回 nil
    private static func atomEnd(_ chars: [Character], at start: Int) -> Int? {
        let n = chars.count
        var i = start
        if chars[i] == "!" { i += 1 }
        guard i < n, chars[i] == "[" else { return nil }

        // [[...]] / ![[...]]
        if i + 1 < n, chars[i + 1] == "[" {
            var j = i + 2
            while j + 1 < n {
                if chars[j] == "]" && chars[j + 1] == "]" { return j + 1 }
                j += 1
            }
            return nil
        }

        // [text](target) / ![alt](src)
        var j = i + 1
        var depth = 1
        while j < n {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "[" { depth += 1 }
            if chars[j] == "]" {
                depth -= 1
                if depth == 0 { break }
            }
            j += 1
        }
        guard j < n, j + 1 < n, chars[j + 1] == "(" else { return nil }
        var k = j + 2
        var paren = 1
        while k < n {
            if chars[k] == "\\" { k += 2; continue }
            if chars[k] == "(" { paren += 1 }
            if chars[k] == ")" {
                paren -= 1
                if paren == 0 { return k }
            }
            k += 1
        }
        return nil
    }

    private static func findRunEnd(_ mark: Character, _ chars: [Character], from: Int) -> Int? {
        var i = from
        while i < chars.count {
            if chars[i] == mark { return i }
            i += 1
        }
        return nil
    }

    // MARK: - Flanking（CommonMark §6.4）

    private static func isWhitespace(_ c: Character) -> Bool {
        // U+2028（段内软/硬换行）对 flanking 判定等同空白/行界（CommonMark §6.4）
        c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{2028}" || c == "\u{2029}"
            || c == "\u{0B}" || c == "\u{0C}"
    }

    private static func isPunctuation(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation,
             .closePunctuation, .initialPunctuation, .finalPunctuation,
             .otherPunctuation, .mathSymbol, .currencySymbol,
             .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }

    /// 返回 (canOpen, canClose)
    private static func flanking(_ char: Character,
                                 before: Character?, after: Character?) -> (Bool, Bool) {
        let beforeSpace = before.map(isWhitespace) ?? true   // 行首等同空白
        let afterSpace = after.map(isWhitespace) ?? true     // 行尾等同空白
        let beforePunct = before.map(isPunctuation) ?? false
        let afterPunct = after.map(isPunctuation) ?? false

        // left-flanking：后继非空白，且（后继非标点 或 前驱是空白/标点）
        let left = !afterSpace && (!afterPunct || beforeSpace || beforePunct)
        // right-flanking：前驱非空白，且（前驱非标点 或 后继是空白/标点）
        let right = !beforeSpace && (!beforePunct || afterSpace || afterPunct)

        if char == "*" {
            return (left, right)
        }
        // `_`：只能单侧打开/关闭，除非另一侧紧邻标点
        return (left && (!right || beforePunct), right && (!left || afterPunct))
    }
}
