//
//  RibbonView.swift
//  FinalMd（墨写）— SwiftUI 原生版
//
//  Word 风格功能区。对应 Electron 版 renderer/src/ui.js 的 GROUPS 定义，
//  图标改用 SF Symbols（原生观感），分组与两行布局保持不变。
//

import SwiftUI
import AppKit

// MARK: - 分组容器

struct RibbonGroup<Content: View>: View {
    let showsDivider: Bool
    @ViewBuilder var content: Content

    init(showsDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 1) { content }
            .padding(.horizontal, 6)
            .background(alignment: .trailing) {
                if showsDivider {
                    Divider().frame(height: 18)
                }
            }
    }
}

// MARK: - 功能区

struct RibbonView: View {

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var l10n: Localizer

    @State private var colorPopover = false
    @State private var highlightPopover = false

    var body: some View {
        VStack(spacing: 3) {
            row1
            Divider().padding(.horizontal, 8)
            row2
        }
        .padding(.vertical, 5)
        .background(Color(nsColor: DocTheme.chromeForeground))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: 第一行

    private var row1: some View {
        HStack(spacing: 0) {
            RibbonGroup {
                icon("doc.badge.plus", "tb.new", .new)
                icon("folder", "tb.open", .open)
                icon("square.and.arrow.down", "tb.save", .save)
            }
            RibbonGroup {
                icon("arrow.uturn.backward", "tb.undo", .undo, disabled: !model.toolbar.canUndo)
                icon("arrow.uturn.forward", "tb.redo", .redo, disabled: !model.toolbar.canRedo)
            }
            RibbonGroup {
                stylePicker
            }
            RibbonGroup {
                paragraphButton
                ForEach(1...6, id: \.self) { level in
                    headingButton(level)
                }
            }
            RibbonGroup(showsDivider: false) {
                icon("bold", "tb.bold", .bold, active: model.toolbar.isBold)
                icon("italic", "tb.italic", .italic, active: model.toolbar.isItalic)
                icon("underline", "tb.underline", .underline, active: model.toolbar.isUnderline)
                icon("strikethrough", "tb.strike", .strike, active: model.toolbar.isStrike)
                colorButton
                highlightButton
                icon("eraser", "tb.clearFormat", .clearFormat)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
    }

    // MARK: 第二行

    private var row2: some View {
        HStack(spacing: 0) {
            RibbonGroup {
                icon("list.bullet", "tb.bulletList", .bulletList, active: model.toolbar.isBulletList)
                icon("list.number", "tb.orderedList", .orderedList, active: model.toolbar.isOrderedList)
            }
            RibbonGroup {
                icon("decrease.indent", "tb.outdent", .outdent)
                icon("increase.indent", "tb.indent", .indent)
            }
            RibbonGroup {
                icon("text.alignleft", "tb.alignLeft", .align(.left),
                     active: model.toolbar.alignment == .left)
                icon("text.aligncenter", "tb.alignCenter", .align(.center),
                     active: model.toolbar.alignment == .center)
                icon("text.alignright", "tb.alignRight", .align(.right),
                     active: model.toolbar.alignment == .right)
                icon("text.justify", "tb.alignJustify", .align(.justified),
                     active: model.toolbar.alignment == .justified)
            }
            RibbonGroup {
                icon("text.quote", "tb.quote", .quote, active: model.toolbar.isQuote)
                icon("chevron.left.forwardslash.chevron.right", "tb.inlineCode", .inlineCode,
                     active: model.toolbar.isInlineCode)
                icon("terminal", "tb.codeBlock", .codeBlock, active: model.toolbar.isCodeBlock)
                icon("minus", "tb.hr", .hr)
            }
            RibbonGroup(showsDivider: false) {
                icon("link", "tb.link", .link)
                icon("tablecells", "tb.table", .table)
                icon("photo", "tb.image", .image)
                icon("chart.bar", "tb.chart", .chart)
                icon("list.bullet.indent", "tb.toc", .toc)
                icon("magnifyingglass", "tb.find", .find)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
    }

    // MARK: 组件

    private func icon(_ systemName: String,
                      _ titleKey: String,
                      _ command: EditorCommand,
                      active: Bool = false,
                      disabled: Bool = false) -> some View {
        Button {
            model.perform(command)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .frame(width: 27, height: 22)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.accentColor.opacity(0.16) : Color.clear)
                )
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(l10n.t(titleKey))
    }

    private var paragraphButton: some View {
        Button { model.perform(.style(.paragraph)) } label: {
            Text("¶")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 27, height: 22)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isParagraphActive ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(isParagraphActive ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(l10n.t("style.body") + " (⌘0)")
    }

    private func headingButton(_ level: Int) -> some View {
        let size: CGFloat = [13, 12.5, 12, 11.5, 11, 11][level - 1]
        let active = currentStyle == .heading(level)
        return Button { model.perform(.style(.heading(level))) } label: {
            Text("H\(level)")
                .font(.system(size: size, weight: .semibold))
                .frame(width: 27, height: 22)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(l10n.t("style.heading", ["n": String(level)]) + " (⌘\(level))")
    }

    private var stylePicker: some View {
        Picker("", selection: Binding(
            get: { currentStyle },
            set: { model.perform(.style($0)) }
        )) {
            Text(l10n.t("style.body")).tag(BlockStyle.paragraph)
            ForEach(1...6, id: \.self) { n in
                Text(l10n.t("style.heading", ["n": String(n)])).tag(BlockStyle.heading(n))
            }
            Text(l10n.t("style.quote")).tag(BlockStyle.quote)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 118)
        .help(l10n.t("style.body"))
    }

    private var isParagraphActive: Bool {
        currentStyle == .paragraph
    }

    private var currentStyle: BlockStyle {
        let type = model.toolbar.blockType
        if let level = type.headingLevel { return .heading(level) }
        if type == .quote { return .quote }
        return .paragraph
    }

    // MARK: 颜色 / 高亮

    private var colorButton: some View {
        Button { colorPopover.toggle() } label: {
            Image(systemName: "paintbrush")
                .font(.system(size: 13))
                .frame(width: 27, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(l10n.t("tb.color"))
        .popover(isPresented: $colorPopover, arrowEdge: .bottom) {
            ColorPopover(title: l10n.t("tb.color"),
                         swatches: Self.textColors,
                         showsCustomPicker: true) { color in
                model.textView?.setTextColor(color)
                model.refreshToolbar()
                colorPopover = false
            }
        }
    }

    private var highlightButton: some View {
        Button { highlightPopover.toggle() } label: {
            Image(systemName: "highlighter")
                .font(.system(size: 13))
                .frame(width: 27, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(l10n.t("tb.highlight"))
        .popover(isPresented: $highlightPopover, arrowEdge: .bottom) {
            ColorPopover(title: l10n.t("tb.highlight"),
                         swatches: Self.highlightColors,
                         showsCustomPicker: false) { color in
                model.textView?.setHighlight(color)
                model.refreshToolbar()
                highlightPopover = false
            }
        }
    }

    /// 字体色板（与 Electron 版 TEXT_COLORS 一致）
    static let textColors: [NSColor] = [
        NSColor(hex: "#1f2328")!, NSColor(hex: "#d64545")!, NSColor(hex: "#e07b39")!,
        NSColor(hex: "#c9a227")!, NSColor(hex: "#2ba36b")!, NSColor(hex: "#2f6feb")!,
        NSColor(hex: "#7c5cff")!, NSColor(hex: "#c2478f")!, NSColor(hex: "#6b7280")!,
        NSColor(hex: "#0f766e")!, NSColor(hex: "#a16207")!, NSColor(hex: "#0369a1")!,
    ]

    /// 高亮色板（与 Electron 版 HL_COLORS 一致）
    static let highlightColors: [NSColor] = [
        NSColor(hex: "#fff3a3")!, NSColor(hex: "#ffd8a8")!, NSColor(hex: "#ffc9c9")!,
        NSColor(hex: "#c8f0d2")!, NSColor(hex: "#cfe3ff")!, NSColor(hex: "#e6d8ff")!,
        NSColor(hex: "#e8eaed")!, NSColor(hex: "#ffd6f0")!,
    ]
}

// MARK: - 颜色面板

struct ColorPopover: View {
    let title: String
    let swatches: [NSColor]
    let showsCustomPicker: Bool
    let onPick: (NSColor?) -> Void

    @State private var custom = Color.accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(20), spacing: 5), count: 6), spacing: 5) {
                ForEach(swatches, id: \.hexString) { color in
                    Button {
                        onPick(color)
                    } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: color))
                            .frame(width: 20, height: 20)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if showsCustomPicker {
                HStack {
                    Text("自定义").font(.system(size: 11)).foregroundStyle(.secondary)
                    ColorPicker("", selection: Binding(
                        get: { custom },
                        set: { newValue in
                            custom = newValue
                            onPick(NSColor(newValue))
                        }
                    ))
                    .labelsHidden()
                    .frame(width: 42, height: 20)
                }
            }

            Button("恢复默认") { onPick(nil) }
                .font(.system(size: 11))
        }
        .padding(10)
        .frame(width: 168)
    }
}
