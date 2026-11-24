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

/// 界面外观：跟随系统 / 强制浅色 / 强制深色
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// 菜单文案的 i18n key
    var labelKey: String { "appearance.\(rawValue)" }

    /// 对应的 AppKit 外观；nil 表示交还给系统
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
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
    case aiCommand
    case aiSettings

    var id: String {
        switch self {
        case .image: return "image"
        case .link: return "link"
        case .table: return "table"
        case .chart: return "chart"
        case .confirm(let spec): return "confirm-\(spec.title)"
        case .aiCommand: return "aiCommand"
        case .aiSettings: return "aiSettings"
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

    /// 当前活跃的文本视图。传统模式下指向源码视图，即刻模式下指向排版视图。
    /// 命令、查找、统计、undo 都通过它走，因此切换模式后它们自动作用于正确的视图。
    weak var textView: NSTextView? {
        didSet { refreshAll() }
    }

    /// 两个编辑器常驻窗口，切换模式只显隐、不销毁：
    /// 即刻视图里的富文本、图片附件、光标状态才不会在来回切换时丢失。
    weak var richTextView: MDEditorTextView?
    weak var sourceTextView: MDSourceTextView?

    /// 两侧内容谁更新。nil = 刚装载 / 刚同步，两边等价，切换时无需搬运。
    private var authority: EditorSide?

    /// 编辑模式：即刻（所见即所得）/ 传统（Markdown 源码）。
    /// 属于本机偏好，不写进文档；下次启动沿用上次的选择。
    @Published var editorMode: EditorMode = {
        let saved = UserDefaults.standard.string(forKey: EditorMode.storageKey) ?? ""
        return EditorMode(rawValue: saved) ?? .instant
    }() {
        didSet {
            guard oldValue != editorMode else { return }
            UserDefaults.standard.set(editorMode.rawValue, forKey: EditorMode.storageKey)
            applyEditorMode()
            showToast(l10n.t(editorMode.labelKey))
        }
    }

    @Published private(set) var currentPath: String?
    @Published private(set) var isDirty = false
    @Published private(set) var stats = DocStats()
    @Published private(set) var toolbar = ToolbarState()

    @Published var zoom: Double = 1

    /// 文档横线（作业本行线）开关。只是编辑区的显示辅助，不写进文档内容，
    /// 所以用 UserDefaults 记住偏好，而不是当成文档状态。
    @Published var showLineRuling: Bool =
        (UserDefaults.standard.object(forKey: AppModel.lineRulingKey) as? Bool) ?? false

    static let lineRulingKey = "finalmd.lineRuling"

    /// 界面外观。默认跟随系统；想固定成深色写字的人可以在这里盖一层。
    /// 和横线一样属于「本机偏好」，不进文档，所以存 UserDefaults。
    @Published var appearanceMode: AppearanceMode = .system {
        didSet {
            guard oldValue != appearanceMode else { return }
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceKey)
            applyAppearance()
        }
    }

    static let appearanceKey = "finalmd.appearance"
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
        // 恢复上次选择的外观（跟随系统时没有这个键）
        if let saved = UserDefaults.standard.string(forKey: Self.appearanceKey),
           let mode = AppearanceMode(rawValue: saved) {
            appearanceMode = mode
        }
        AppModel.shared = self
        applyAppearance()
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

        // 传统模式是纯文本编辑：没有字重 / 块样式 / 对齐状态可回显，
        // 功能区整片本来也会淡显，这里只保留 undo / redo 两个仍然有效的按钮。
        guard editorMode == .instant else {
            var plain = ToolbarState()
            plain.canUndo = tv.undoManager?.canUndo ?? false
            plain.canRedo = tv.undoManager?.canRedo ?? false
            toolbar = plain
            NSApp.mainWindow?.isDocumentEdited = isDirty
            return
        }

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

    /// 存盘用的 Markdown 文本。
    /// 传统模式直接取源码视图的字符串（逐字节保留用户输入，不做任何规范化），
    /// 即刻模式才把富文本序列化回 Markdown。
    var markdown: String {
        if editorMode == .classic, let source = sourceTextView {
            return EditorModeBridge.plainText(in: source)
        }
        if let storage = richTextView?.textStorage {
            return EditorModeBridge.sourceText(from: storage)
        }
        return ""
    }

    /// 最近一次装载的文档原文。两个编辑器视图不是同一帧创建的，
    /// 后就绪的那个用它补上同一份内容（传统模式因此能看到文件的原始字节）。
    private var pendingDocument: String?
    /// 两个视图是否已经装载过当前文档（后创建的那个才需要补写）
    private var richContentLoaded = false
    private var sourceContentLoaded = false

    func setMarkdown(_ md: String) {
        pendingDocument = md

        // 两侧同时装载：即刻侧拿解析后的排版，传统侧拿原样 Markdown。
        // 此刻两边内容等价，来回切换不需要重新转换，也不会把原文件的
        // 空行 / 列表风格悄悄规范化掉。
        if let rich = richTextView {
            loadRich(EditorModeBridge.richText(from: md), into: rich)
        } else {
            richContentLoaded = false
        }
        if let source = sourceTextView {
            loadSource(md, into: source)
        } else {
            sourceContentLoaded = false
        }
        authority = nil

        if editorMode == .instant {
            // 换文档后必须重算输入属性：否则新建/打开后敲的第一个字会沿用上一篇的样式
            richTextView?.refreshTypingAttributes()
        }
        markDirty(false)
        refreshAll()
    }

    private func loadRich(_ attr: NSAttributedString, into view: MDEditorTextView) {
        EditorModeBridge.install(attr, in: view, plain: false)
        view.refreshTypingAttributes()
        view.showsLineRuling = showLineRuling
        view.needsDisplay = true
        richContentLoaded = true
    }

    private func loadSource(_ md: String, into view: MDSourceTextView) {
        EditorModeBridge.install(NSAttributedString(string: md), in: view, plain: true)
        view.applySyntaxHighlight()
        view.needsDisplay = true
        sourceContentLoaded = true
    }

    /// 某个编辑器视图刚创建完成。把文档补给它，再按当前模式显隐。
    func editorViewDidBecomeReady(_ side: EditorSide) {
        switch side {
        case .rich:
            if let rich = richTextView, !richContentLoaded {
                let md: String
                if authority == .source, let source = sourceTextView {
                    md = source.string
                } else {
                    md = pendingDocument ?? ""
                }
                loadRich(EditorModeBridge.richText(from: md), into: rich)
            }
        case .source:
            if let source = sourceTextView, !sourceContentLoaded {
                let md: String
                if authority == .rich, let storage = richTextView?.textStorage {
                    md = EditorModeBridge.sourceText(from: storage)
                } else {
                    md = pendingDocument ?? (richTextView?.textStorage.map { EditorModeBridge.sourceText(from: $0) } ?? "")
                }
                loadSource(md, into: source)
            }
        }

        EditorModeBridge.resetUndoHistory([richTextView, sourceTextView])
        applyLineRuling()
        applyEditorMode()
    }

    /// 某个视图发生了真实编辑。记下哪一侧是最新内容，切换模式时只搬运这一侧。
    func noteEdited(in view: NSTextView) {
        if view === richTextView { authority = .rich }
        else if view === sourceTextView { authority = .source }
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
        // 传统模式下 rich 视图可能还是旧内容，用当前源码现场解析一份，
        // 既不改动隐藏视图，也不影响用户正在编辑的源码与 undo 历史。
        let attr: NSAttributedString
        if editorMode == .classic, let source = sourceTextView {
            attr = MarkdownParser.parse(source.string)
        } else if let storage = richTextView?.textStorage {
            attr = storage
        } else { return }
        let html = HTMLExporter.document(from: attr, title: displayTitle, language: l10n.htmlLang)
        if await OpenSavePanel.exportFile(l10n: l10n,
                                          defaultName: displayTitle + ".html",
                                          extension: "html",
                                          content: html) {
            showToast(l10n.t("toast.exportedHtml"))
        }
    }

    func exportPDF() async {
        guard let rich = richTextView else { return }
        if editorMode == .classic, let source = sourceTextView {
            // PDF 印的是排版结果，不是源码。把当前源码刷新进隐藏的 rich 视图，
            // 导出完仍留在传统模式，源码视图与存盘内容都不受影响。
            loadRich(EditorModeBridge.richText(from: source.string), into: rich)
        }
        if await PDFExporter.export(l10n: l10n, view: rich, defaultName: displayTitle + ".pdf") {
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

    // MARK: - 编辑模式（即刻 / 传统）

    /// 切换按钮 / 菜单 / 快捷键共用的入口
    func toggleEditorMode() {
        editorMode = (editorMode == .instant) ? .classic : .instant
    }

    /// 把模式落到两个视图上：先让目标侧拿到最新内容，再把「活跃视图」指过去。
    /// 显隐与键盘焦点由两个 NSViewRepresentable 在 updateNSView 里完成（时机更准）。
    func applyEditorMode() {
        syncHiddenSideIfNeeded(for: editorMode == .classic ? .source : .rich)

        let active: NSTextView? = editorMode == .classic ? sourceTextView : richTextView
        if textView !== active {
            textView = active            // didSet 会刷新统计 / 工具栏
        } else {
            refreshAll()
        }
    }

    /// 只有「另一侧被编辑过」才需要搬运内容。
    /// 刚打开文件、或刚同步过（authority == nil）时直接换显隐，
    /// 原文件的换行与标记写法因此能原封不动地保留。
    private func syncHiddenSideIfNeeded(for target: EditorSide) {
        guard let authority, authority != target else { return }
        switch target {
        case .source:
            guard let storage = richTextView?.textStorage,
                  let source = sourceTextView else { return }
            loadSource(EditorModeBridge.sourceText(from: storage), into: source)
        case .rich:
            guard let rich = richTextView, let source = sourceTextView else { return }
            loadRich(EditorModeBridge.richText(from: source.string), into: rich)
        }
        self.authority = nil
        // 整篇被替换后，两个视图里按旧字符范围记录的 undo 都已失效
        EditorModeBridge.resetUndoHistory([richTextView, sourceTextView])
    }

    /// 编辑器视图刚创建 / 偏好刚恢复时调用一次，保证模式与视图状态一致。
    /// 启动阶段视图还没建好，这里能安全地什么都不做。
    func reapplyEditorMode() {
        applyEditorMode()
    }

    // MARK: - 文档横线

    /// 开 / 关文档横线（作业本行线），并记住这次选择
    func toggleLineRuling() {
        showLineRuling.toggle()
        UserDefaults.standard.set(showLineRuling, forKey: Self.lineRulingKey)
        applyLineRuling()
    }

    /// 把开关状态推给即刻视图。横线是排版页面的辅助线，传统模式（纯文本）不画。
    func applyLineRuling() {
        richTextView?.showsLineRuling = showLineRuling
    }

    // MARK: - 外观（浅色 / 深色）

    /// 把外观模式落到 NSApplication 上。
    /// .system 交给系统（nil），另外两个强制覆盖 —— 覆盖只影响本应用，不碰系统设置。
    func applyAppearance() {
        guard let app = NSApp else { return }
        app.appearance = appearanceMode.appearance
    }
}
