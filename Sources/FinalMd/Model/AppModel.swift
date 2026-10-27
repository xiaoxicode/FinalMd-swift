//
//  AppModel.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  全局状态中心，对应 Electron 版 renderer/src/app.js 的状态与命令分发。
//  文本真正存在 NSTextView 的 NSTextStorage 里，这里只保存派生状态与文件信息。
//

import AppKit
import SwiftUI

/// 字数 / 字符 / 行数统计
struct DocStats: Equatable {
    var words = 0
    var chars = 0
    var lines = 1
}

/// 工具栏回显状态
struct ToolbarState: Equatable {
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrike = false
    var isInlineCode = false
    var isCodeBlock = false
    var isQuote = false
    var isBulletList = false
    var isOrderedList = false
    var alignment: NSTextAlignment = .natural
    var blockType: MDBlockType = .paragraph
    var canUndo = false
    var canRedo = false
}

/// 当前打开的对话框
enum DialogKind: Identifiable, Equatable {
    case image
    case link
    case table
    case chart
    case confirm(ConfirmSpec)

    var id: String {
        switch self {
        case .image: return "image"
        case .link: return "link"
        case .table: return "table"
        case .chart: return "chart"
        case .confirm(let spec): return "confirm-\(spec.title)"
        }
    }
}

/// 三选一确认框
struct ConfirmSpec: Equatable {
    let title: String
    let message: String
    let buttons: [ConfirmButton]

    static func unsaved(_ l10n: Localizer, title: String) -> ConfirmSpec {
        ConfirmSpec(
            title: title,
            message: l10n.t("dlg.unsaved.text"),
            buttons: [
                ConfirmButton(id: "save", label: l10n.t("common.save"), style: .primary),
                ConfirmButton(id: "discard", label: l10n.t("common.dontSave"), style: .danger),
                ConfirmButton(id: "cancel", label: l10n.t("common.cancel"), style: .plain),
            ]
        )
    }
}

struct ConfirmButton: Equatable, Identifiable {
    enum Style { case plain, primary, danger }
    let id: String
    let label: String
    let style: Style
}

@MainActor
final class AppModel: ObservableObject {

    // MARK: 文档

    weak var textView: NSTextView? {
        didSet { refreshAll() }
    }

    @Published private(set) var currentPath: String?
    @Published private(set) var isDirty = false
    @Published private(set) var stats = DocStats()
    @Published private(set) var toolbar = ToolbarState()

    @Published var zoom: Double = 1
    @Published var toastMessage: String?
    @Published var activeDialog: DialogKind?
    @Published var findVisible = false
    @Published var findText = ""
    @Published var replaceText = ""
    @Published var findStatus = ""

    /// 确认框回调
    var confirmHandler: ((String) -> Void)?

    /// 正在编辑的图表（对话框用）
    @Published var chartDraft: ChartConfig?
    /// 双击进来的图表：记录它在文档里的位置，保存时替换而不是新增
    var chartEditRange: NSRange?

    let l10n: Localizer

    init(l10n: Localizer) {
        self.l10n = l10n
        AppModel.shared = self
    }

    /// 供 AppDelegate 在退出确认时取用（单窗口应用）
    static var shared: AppModel?

    // MARK: 派生信息

    var docName: String {
        guard let currentPath else { return l10n.t("doc.untitledFile") }
        return (currentPath as NSString).lastPathComponent
    }

    var displayTitle: String {
        (docName as NSString).deletingPathExtension
    }

    // MARK: 状态刷新

    func refreshAll() {
        refreshStats()
        refreshToolbar()
    }

    func refreshStats() {
        guard let tv = textView else { return }
        let text = tv.string
        var words = 0
        var chars = 0
        var sawLetter = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if sawLetter { words += 1; sawLetter = false }
                continue
            }
            // CJK 每个字算一个词
            if (0x4E00...0x9FFF).contains(scalar.value) {
                if sawLetter { words += 1; sawLetter = false }
                words += 1
            } else {
                sawLetter = true
            }
            chars += 1
        }
        if sawLetter { words += 1 }
        var lines = text.isEmpty ? 1 : text.split(separator: "\n", omittingEmptySubsequences: false).count
        if lines < 1 { lines = 1 }
        stats = DocStats(words: words, chars: chars, lines: lines)
    }

    func refreshToolbar() {
        guard let tv = textView else { return }
        var s = ToolbarState()
        s.isBold = tv.hasTrait(.bold)
        s.isItalic = tv.hasTrait(.italic)
        s.isUnderline = tv.hasAttribute(.underlineStyle)
        s.isStrike = tv.hasAttribute(.strikethroughStyle)
        s.isInlineCode = tv.hasAttribute(.mdInlineCode)
        s.blockType = tv.currentBlockType()
        s.isCodeBlock = s.blockType == .code
        s.isQuote = s.blockType == .quote
        s.alignment = tv.currentAlignment()
        s.canUndo = tv.undoManager?.canUndo ?? false
        s.canRedo = tv.undoManager?.canRedo ?? false
        if let storage = tv.textStorage, storage.length > 0 {
            let loc = min(tv.selectedRange().location, storage.length - 1)
            if let item = storage.attribute(.mdListItem, at: max(loc, 0), effectiveRange: nil) as? MDListItem {
                s.isBulletList = !item.ordered
                s.isOrderedList = item.ordered
            }
        }
        toolbar = s

        NSApp.mainWindow?.isDocumentEdited = isDirty
    }

    func markDirty(_ dirty: Bool = true) {
        isDirty = dirty
        NSApp.mainWindow?.isDocumentEdited = dirty
        NSApp.mainWindow?.title = displayTitle
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            if self.toastMessage == message { self.toastMessage = nil }
        }
    }

    // MARK: - 文档读写

    var markdown: String {
        guard let storage = textView?.textStorage else { return "" }
        return MarkdownSerializer.markdown(from: storage)
    }

    func setMarkdown(_ md: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let attr = MarkdownParser.parse(md)
        storage.beginEditing()
        storage.setAttributedString(attr)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        markDirty(false)
        refreshAll()
    }

    func loadWelcome() {
        setMarkdown(l10n.t("welcome"))
    }

    private var didLoadInitialContent = false

    /// 编辑器视图就绪后载入欢迎文档（只做一次）
    func loadInitialContentIfNeeded() {
        guard !didLoadInitialContent else { return }
        didLoadInitialContent = true
        loadWelcome()
    }

    // MARK: 版本检查

    func checkForUpdates() async {
        showToast(l10n.t("upd.checking"))
        guard let latest = await UpdateChecker.latestRelease() else {
            showToast(l10n.t("upd.checkFailed"))
            return
        }
        let current = "v" + UpdateChecker.currentVersion
        if latest == current {
            showToast(l10n.t("upd.latest"))
            return
        }
        let answer = await confirm(ConfirmSpec(
            title: l10n.t("upd.available.title"),
            message: l10n.t("upd.available.text", ["current": current, "version": latest]),
            buttons: [
                ConfirmButton(id: "yes", label: l10n.t("upd.download"), style: .primary),
                ConfirmButton(id: "no", label: l10n.t("upd.later"), style: .plain),
            ]
        ))
        if answer == "yes" {
            NSWorkspace.shared.open(UpdateChecker.releasesURL)
        }
    }

    func newDocument() async -> Bool {
        if isDirty {
            let answer = await confirm(ConfirmSpec.unsaved(l10n, title: l10n.t("dlg.new.title")))
            if answer == "cancel" { return false }
            if answer == "save", !(await save(asNew: false)) { return false }
        }
        currentPath = nil
        setMarkdown("")
        return true
    }

    func openDocument() async {
        guard let result = await OpenSavePanel.openMarkdown(l10n: l10n) else { return }
        if isDirty {
            let answer = await confirm(ConfirmSpec.unsaved(l10n, title: l10n.t("dlg.open.title")))
            if answer == "cancel" { return }
            if answer == "save", !(await save(asNew: false)) { return }
        }
        currentPath = result.path
        setMarkdown(result.content)
        showToast(l10n.t("toast.opened", ["name": docName]))
    }

    @discardableResult
    func save(asNew: Bool) async -> Bool {
        guard let result = await OpenSavePanel.saveMarkdown(
            l10n: l10n,
            path: asNew ? nil : currentPath,
            content: markdown,
            suggestedName: docName
        ) else { return false }
        currentPath = result
        markDirty(false)
        showToast(l10n.t("toast.saved"))
        return true
    }

    func exportHTML() async {
        guard let storage = textView?.textStorage else { return }
        let html = HTMLExporter.document(from: storage, title: displayTitle, language: l10n.htmlLang)
        if await OpenSavePanel.exportFile(l10n: l10n,
                                          defaultName: displayTitle + ".html",
                                          extension: "html",
                                          content: html) {
            showToast(l10n.t("toast.exportedHtml"))
        }
    }

    func exportPDF() async {
        guard let tv = textView else { return }
        if await PDFExporter.export(l10n: l10n, view: tv, defaultName: displayTitle + ".pdf") {
            showToast(l10n.t("toast.exportedPdf"))
        }
    }

    // MARK: - 插入

    func insertImageFiles(_ urls: [URL]) {
        guard let tv = textView else { return }
        var count = 0
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let image = NSImage(data: data) else { continue }
            let scaled = ImageEmbed.compressedDataURL(image: image, maxEdge: 1600) ?? ""
            let src = scaled.isEmpty ? url.absoluteString : scaled
            let alt = (url.lastPathComponent as NSString).deletingPathExtension
            tv.insertImage(MDImageAttachment(src: src, alt: alt, image: image))
            count += 1
        }
        if count > 0 {
            markDirty()
            showToast(l10n.t("image.embeddedMany", ["n": String(count)]))
        }
    }

    func insertImageURL(_ url: String, alt: String) {
        guard let tv = textView, !url.isEmpty else { return }
        tv.insertImage(MDImageAttachment(src: url, alt: alt))
        markDirty()
        showToast(l10n.t("image.inserted"))
    }

    func pickAndInsertImages() async {
        let urls = await OpenSavePanel.openImages(l10n: l10n)
        guard !urls.isEmpty else { return }
        insertImageFiles(urls)
    }

    func insertTable(rows: Int, cols: Int, header: Bool) {
        textView?.insertTable(rows: rows, cols: cols, hasHeader: header)
        markDirty()
    }

    func insertLink(url: String, text: String?) {
        textView?.insertLink(url: url, text: text)
        markDirty()
    }

    func insertTOC() {
        guard let tv = textView else { return }
        let before = tv.string
        tv.insertTOC()
        if tv.string == before {
            showToast(l10n.t("toc.noHeadings"))
        } else {
            markDirty()
            showToast(l10n.t("toc.inserted"))
        }
    }

    // MARK: 图表

    func openChartDialog(editing attachment: MDImageAttachment? = nil, at range: NSRange? = nil) {
        chartEditRange = range
        if let attachment, let cfg = ChartConfig.decode(attachment.mdTitle) {
            chartDraft = cfg
        } else {
            chartDraft = ChartConfig.sample(l10n)
        }
        activeDialog = .chart
    }

    /// 把图表渲染成 PNG 后插入文档
    func insertChart(_ config: ChartConfig) {
        guard let tv = textView else { return }
        guard let image = ChartRenderer.renderPNG(config, scale: 2) else {
            showToast(l10n.t("chart.failed", ["msg": "render"]))
            return
        }
        let src = ImageEmbed.dataURL(pngData: ImageEmbed.pngData(image: image) ?? Data()) ?? ""
        let attachment = MDImageAttachment(src: src,
                                           alt: config.title.isEmpty ? l10n.t("chart.alt") : config.title,
                                           title: config.encodedTitle(),
                                           image: image)
        if let range = chartEditRange {
            replaceAttachment(at: range, with: attachment)
        } else {
            tv.insertImage(attachment)
        }
        let wasEditing = chartEditRange != nil
        chartEditRange = nil
        markDirty()
        showToast(wasEditing ? l10n.t("chart.updated") : l10n.t("chart.inserted"))
    }

    private func replaceAttachment(at range: NSRange, with attachment: MDImageAttachment) {
        guard let tv = textView, let storage = tv.textStorage,
              NSMaxRange(range) <= storage.length else { return }
        if tv.shouldChangeText(in: range, replacementString: "") {
            storage.beginEditing()
            storage.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
            storage.endEditing()
            tv.didChangeText()
        }
    }

    // MARK: - 查找替换

    func findMatches() -> [NSRange] {
        guard let storage = textView?.textStorage, !findText.isEmpty else { return [] }
        let s = storage.string as NSString
        var out: [NSRange] = []
        var searchRange = NSRange(location: 0, length: s.length)
        while true {
            let r = s.range(of: findText, options: [], range: searchRange)
            if r.location == NSNotFound { break }
            out.append(r)
            let next = NSMaxRange(r)
            if next >= s.length { break }
            searchRange = NSRange(location: next, length: s.length - next)
        }
        return out
    }

    func refreshFindStatus() {
        let n = findMatches().count
        findStatus = n == 0 ? l10n.t("find.noMatch") : l10n.t("find.count", ["n": String(n)])
    }

    func findNext(backward: Bool = false) {
        guard let tv = textView else { return }
        let matches = findMatches()
        guard !matches.isEmpty else { refreshFindStatus(); return }
        let current = tv.selectedRange().location
        let target: NSRange
        if backward {
            target = matches.reversed().first(where: { NSMaxRange($0) <= current || $0.location < current }) ?? matches.last!
        } else {
            target = matches.first(where: { $0.location >= current }) ?? matches.first!
        }
        tv.setSelectedRange(target)
        tv.scrollRangeToVisible(target)
        tv.showFindIndicator(for: target)
        refreshFindStatus()
    }

    func replaceOne() {
        guard let tv = textView, let storage = tv.textStorage, !findText.isEmpty else { return }
        let sel = tv.selectedRange()
        let s = storage.string as NSString
        if sel.length > 0, sel.location + sel.length <= s.length,
           s.substring(with: sel) == findText {
            if tv.shouldChangeText(in: sel, replacementString: replaceText) {
                storage.replaceCharacters(in: sel, with: replaceText)
                tv.didChangeText()
            }
        }
        findNext()
        refreshFindStatus()
    }

    func replaceAll() {
        guard let tv = textView, let storage = tv.textStorage, !findText.isEmpty else { return }
        let matches = findMatches()
        guard !matches.isEmpty else { return }
        if tv.shouldChangeText(in: NSRange(location: 0, length: storage.length),
                               replacementString: storage.string) {
            storage.beginEditing()
            for r in matches.reversed() {
                storage.replaceCharacters(in: r, with: replaceText)
            }
            storage.endEditing()
            tv.didChangeText()
        }
        showToast(l10n.t("find.replacedAll"))
        refreshFindStatus()
    }

    // MARK: - 确认框

    func confirm(_ spec: ConfirmSpec) async -> String {
        await withCheckedContinuation { continuation in
            confirmHandler = { [weak self] answer in
                self?.confirmHandler = nil
                continuation.resume(returning: answer)
            }
            activeDialog = .confirm(spec)
        }
    }

    // MARK: - 缩放

    func setZoom(_ value: Double) {
        zoom = min(max(value, 0.6), 2.0)
    }
}
