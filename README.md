# 墨写 FinalMd — SwiftUI 原生版

Electron 版（[xiaoxicode/FinalMd](https://github.com/xiaoxicode/FinalMd)）的 **macOS 原生 SwiftUI 移植**。
所见即所得地写 Markdown，存出来是干净的 `.md` 文件。

- 目标平台：**macOS 14+**（仅桌面端）
- 编辑器内核：**NSTextView + NSAttributedString**（原生富文本，无内嵌浏览器）
- 语言：Swift 6 / SwiftUI / AppKit / Swift Charts，零第三方依赖
- 已发布版本：**[Release v1.0.1](https://github.com/xiaoxicode/FinalMd-swift/releases/tag/v1.0.1)**
  （`FinalMd-macOS-1.0.1-*.zip`，macOS 14+ / arm64）

---

## 快速开始

```bash
cd FinalMdSwift
./scripts/make_app.sh --run     # 编译并打包成 build/墨写.app 后打开
```

> ⚠️ **完整编译需要安装 Xcode（15+）**。
> SwiftUI 的 `@State` / `@Environment` 等是**外部宏**，其插件 `SwiftUIMacros` 只随 Xcode 提供；
> 只装 Command Line Tools 时 `swift build` 会报 `plugin for module 'SwiftUIMacros' not found`。
> 本机没有 Xcode，因此本仓库用下面两个脚本做了**替代验证**（详见「验证情况」）。

在没有 Xcode 的机器上仍可运行的两项检查：

```bash
./scripts/run-smoke.sh   # Markdown 双向转换冒烟测试（89 项）—— 直接跑，不需要 Xcode
./scripts/verify.sh      # 整套视图代码的类型校验（用宏桩顶替 @State 等）
```

在 Xcode 里开发：直接用 Xcode 打开本目录（`open Package.swift`），或新建 macOS App target 后把
`Sources/FinalMd` 与 `Resources` 挂进去即可。

---

## 云端打包（本机没装 Xcode 时用这个）

`.app` 只能在带 Xcode 的 macOS 环境里编译，所以本机装不了 Xcode 时走 **GitHub Actions 的 macOS runner**
（预装 Xcode，Apple Silicon，公开仓库免费）。

流水线已经写好：`.github/workflows/build-macos.yml`

```bash
# 1. 把项目推到 GitHub
git init && git add . && git commit -m "FinalMd SwiftUI 原生版"
git remote add origin https://github.com/<你的账号>/FinalMdSwift.git
git push -u origin main

# 2. 触发构建
gh workflow run build-macos.yml            # 手动触发
git tag v1.0.1 && git push --tags          # 或打 tag：构建完自动发 Release
```

流水线做的事：

| 步骤 | 说明 |
|---|---|
| 冒烟测试 | 先跑 89 项 Markdown 往返断言，不过就不往下走 |
| 编译 + 组装 | `swift build -c release` → `build/墨写.app`，ad-hoc 签名 |
| bundle 校验 | 检查可执行文件、Info.plist、图标、版本与最低系统版本 |
| Developer ID 签名 + 公证（可选） | 配了证书 secrets 才执行，`scripts/sign_and_notarize.sh` |
| 打包上传 | 生成 `FinalMd-macOS-<版本>-<commit>.zip` + `.sha256`，作为 artifact 保留 30 天 |
| 发布 Release | 仅 `v*` tag 触发，自动挂 zip 到 Release |

### 分发前建议配置签名

ad-hoc 签名的 `.app` 下载到别的 Mac 上会被 Gatekeeper 拦（右键「打开」可绕过）。
正式分发请在仓库 Settings → Secrets 里加：

| Secret | 内容 |
|---|---|
| `MACOS_CERTIFICATE` | Developer ID Application 证书导出成 `.p12` 后 `base64 -i cert.p12` 的内容 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `MACOS_KEYCHAIN_PASSWORD` | 临时 keychain 密码，任意字符串 |
| `NOTARIZE_APPLE_ID` / `NOTARIZE_TEAM_ID` / `NOTARIZE_PASSWORD` | Apple ID、Team ID、App 专用密码 |

配好之后流水线会自动做 hardened runtime 签名 → `notarytool` 公证 → `stapler` 装订票据，出来的 zip 别人下载即可直接打开。

macOS runner 按 10 倍计费（私有仓库免费额度约合 200 分钟/月），单次构建约 3–5 分钟，日常使用够。

---

## 目录结构

```
FinalMdSwift/
├── Package.swift                     SwiftPM 清单（macOS 14+）
├── Sources/FinalMd/
│   ├── App/                          应用入口与原生菜单
│   │   ├── FinalMdApp.swift          @main + WindowGroup
│   │   ├── AppCommands.swift         文件/编辑/插入/格式/视图/语言/帮助 七个菜单
│   │   └── AppDelegate.swift         未保存改动时的退出确认
│   ├── Model/
│   │   ├── AppModel.swift            全局状态：文档、统计、读写、查找替换
│   │   └── ChartConfig.swift         图表配置 + Base64 编码（存进图片 title）
│   ├── Markdown/                     ★ 迁移的核心
│   │   ├── AttributedKeys.swift      自定义属性键 + 图片/分割线附件
│   │   ├── Typography.swift          排版常量（逐项对齐原版 styles.css）
│   │   ├── InlineParser.swift        行内 Markdown → NSAttributedString
│   │   ├── MarkdownParser.swift      块级 Markdown → NSAttributedString
│   │   └── MarkdownSerializer.swift  NSAttributedString → Markdown / HTML
│   ├── Editor/
│   │   ├── EditorView.swift          NSViewRepresentable + 白纸页面容器 + 输入规则
│   │   ├── TextFormatting.swift      标题/加粗/颜色/对齐/列表/缩进等命令
│   │   └── EditorCommand.swift       工具栏、菜单、快捷键的统一分发入口
│   ├── Charts/
│   │   └── ChartRenderer.swift       Swift Charts 绘制 + PNG 光栅化
│   ├── UI/
│   │   ├── ContentView.swift         主窗口
│   │   ├── RibbonView.swift          两行功能区
│   │   ├── ChromeViews.swift         标题栏 / 查找栏 / 状态栏 / Toast
│   │   ├── InsertDialogs.swift       插入图片 / 链接 / 表格 / 确认框
│   │   └── ChartDialogView.swift     图表对话框（数据网格 + 实时预览）
│   ├── I18n/
│   │   ├── Dictionaries.swift        ⚙️ 自动生成：7 语言 × 213 key
│   │   └── Localizer.swift           运行期切换语言、占位符替换、持久化
│   └── Util/
│       ├── OpenSavePanel.swift       NSOpenPanel / NSSavePanel 的 async 封装
│       ├── HTMLExporter.swift        导出独立 HTML（沿用原版 CSS）
│       ├── PDFExporter.swift         分页导出 PDF
│       ├── ImageEmbed.swift          Base64 内嵌 + 超 380KB 自动压缩
│       └── UpdateChecker.swift       查 GitHub Release（替代 electron-updater）
├── Resources/                        Info.plist + 应用图标
└── scripts/                          make_app.sh / run-smoke.sh / verify.sh / gen-i18n.js
```

---

## 迁移映射（Electron → SwiftUI）

| Electron 原版 | SwiftUI 原生版 | 说明 |
|---|---|---|
| `main.js`（窗口 / IPC / 菜单） | `App/FinalMdApp.swift` + `AppCommands.swift` + `AppDelegate.swift` | 改用 SwiftUI `Commands` 原生菜单 |
| `preload.js`（contextBridge） | — | 不再需要，原生直接调 AppKit |
| `main.js` 的 `dialog:*` IPC | `Util/OpenSavePanel.swift` | `async/await` 封装 |
| `renderer/src/editor.js`（TipTap 3） | `Editor/EditorView.swift` + `TextFormatting.swift` | 内核换成 NSTextView |
| `tiptap-markdown`（Markdown 双向） | `Markdown/MarkdownParser.swift` + `MarkdownSerializer.swift` | 自研，见下文 |
| `renderer/src/ui.js`（功能区/查找/弹窗） | `UI/RibbonView.swift` / `ChromeViews.swift` / `InsertDialogs.swift` | 图标改用 SF Symbols |
| `renderer/src/charts.js`（自研 SVG 引擎） | `Charts/ChartRenderer.swift` | 改用 Swift Charts，画布仍是 760×420 |
| `renderer/src/chart-dialog.js` | `UI/ChartDialogView.swift` | 数据网格 + 实时预览，交互一致 |
| `renderer/styles.css` | `Markdown/Typography.swift` + SwiftUI 修饰符 | 字号/行高/配色逐项对齐 |
| `shared/i18n/*.js`（7 语言） | `I18n/Dictionaries.swift` + `Localizer.swift` | 词典由脚本从 JS 原文件生成 |
| `updater.js`（electron-updater） | `Util/UpdateChecker.swift` | 查 GitHub Release tag，引导浏览器下载 |
| `scripts/smoke.js`（64 项） | `scripts/smoke.swift`（89 项） | 聚焦 Markdown 往返一致性，含 7 语言欢迎文档 |

### 重新生成本地化词典

7 份词典是从 Electron 版原文件机械转换来的，上游改文案后重跑即可：

```bash
node scripts/gen-i18n.js ../FinalMd Sources/FinalMd/I18n/Dictionaries.swift
```

---

## 关键设计

### 1. 块级语义存在自定义属性里

`NSAttributedString` 本身不分「标题 / 引用 / 列表项」，所以加了一组自定义属性键来记住 Markdown 的块级语义：

| 键 | 作用 |
|---|---|
| `.mdBlockType` | `p` / `h1`…`h6` / `quote` / `code` |
| `.mdListItem` | 有序/无序 + 缩进层级 |
| `.mdTableHeader` | 表格标题行 |
| `.mdInlineCode` | 行内代码 |
| `.mdTextColor` / `.mdHighlight` | 用户**显式**设置的颜色与高亮 |
| `.mdStructuralBold` | 标题/表头自带的字重，**不是**用户敲的 `**` |
| `.mdCodeLanguage` | 代码块语言 |

行内样式则一律用 AppKit **标准**属性（字体 trait、`.underlineStyle`、`.strikethroughStyle`、`.link`），
这样 ⌘B / ⌘I / ⌘U 等系统快捷键天然可用，无需自己接管。

`.mdStructuralBold` 解决了一个真实陷阱：标题为了好看必须用粗体字重，
若不区分，序列化时会把 `# 标题` 写成 `# **标题**`。

### 2. 表格用 NSTextTable

表格单元格 = 带 `NSTextTableBlock` 的段落，由 AppKit 负责排版与边框渲染，可直接在编辑器里编辑。
序列化时按 `startingRow / startingColumn` 还原成 `| a | b |`。

### 3. 图片与图表

图片以 `MDImageAttachment`（`NSTextAttachment` 子类）承载，保留原始 `src`（Base64 Data URL）、`alt` 与 `title`。
图表把配置 JSON 做 Base64 后写进 `title`（前缀 `mwchart:`），**双击图表即可回来改数据**——与原版 `.md` 文件完全兼容。

### 4. 缩放不污染文档

缩放走 `NSScrollView.magnification`，不改字号。
因为序列化完全依赖块类型与字体 trait（而非绝对字号），缩放、换字号都不会影响 Markdown 输出。

缩放方式（三种，等价，范围 60%–200%）：

| 操作 | 说明 |
|---|---|
| **⌘ 或 ⌃ + 滚轮** | 鼠标也能缩放；以指针位置为锚点（`setMagnification(_:centeredAt:)`），一格约 10% |
| 触控板双指捏合 | `NSScrollView` 自带，结束后回写状态栏百分比 |
| 菜单「视图 → 放大/缩小/重置」、⌘+ / ⌘- / ⌘0 | 命令走 `AppModel.setZoom` |

实现要点：`MDEditorScrollView.scrollWheel(with:)` 里识别 ⌘/⌃ 拦截滚轮，
触控板用 `scrollingDeltaY`、传统滚轮用 `deltaY` 归一到「一格 10%」并夹住单帧增量；
缩放后同步 `Coordinator.appliedZoom` 再写模型，避免下一次 SwiftUI 刷新把缩放拽回去。

---

## 验证情况

| 项目 | 结果 |
|---|---|
| Markdown 双向转换冒烟测试 | ✅ **106 项全部通过**（`./scripts/run-smoke.sh`） |
| 全套视图代码类型校验 | ✅ **Build complete，0 error / 0 warning**（`./scripts/verify.sh`） |
| 完整 `swift build` + 打包 | ⚠️ 本机未装 Xcode，SwiftUI 宏插件缺失，**未能执行** |

冒烟测试覆盖：六级标题、粗斜体/删除线/行内代码/下划线/链接/嵌套强调、段落、引用、分割线、
有序与无序列表、围栏代码块（含语言）、表格（含表头）、图片（Base64）、
字体色与高亮（`<span>` / `<mark>`）、转义，以及一份包含全部块类型的综合文档与欢迎文档的**二次往返稳定性**；
另外还覆盖**滚动容器行为**：各缩放值下页面水平居中、放大后横滑能拖动（含事件穿过文字视图）、
连续捏合文档宽度稳定，以及 ⌘+滚轮的缩放方向、回调同步、60%–200% 上下限。

> 关于 `verify.sh`：它把源码复制到临时目录，用**重命名**的 property wrapper 顶替
> `@State` / `@Environment` 等宏（Swift 会优先解析 SwiftUI 的宏，所以同名无效），
> 从而在没有 Xcode 的机器上也能对视图层做完整类型检查。**它只用于校验，不参与交付构建。**

---

## 已适配 / 有差异的地方

| 项 | 说明 |
|---|---|
| 平台 | 仅 macOS。原版三平台（Win/Linux）不在本次范围内 |
| 标题栏 | 用 `.hiddenTitleBar` + 自定义标题栏（保留红绿灯），与原版 `hiddenInset` 观感一致 |
| 图标 | 改用 SF Symbols（原生观感），分组与两行布局不变 |
| 图表 | Swift Charts 绘制，视觉风格现代化；数据与配置格式与原版 `.md` 兼容 |
| 自动更新 | 不内置二进制热更新，改为查 GitHub Release 后引导浏览器下载 |
| PDF 导出 | 按 A4 内容区逐段渲染后由 PDFKit 拼成多页 |

## 已知限制

- 文字对齐、字体颜色、高亮依赖 HTML 标签，在纯 Markdown 阅读器中可能失效（与原版一致）
- 图片全部内嵌 Base64，`.md` 体积偏大（换取单文件带走）
- 标题内部的 `**加粗**` 无法在 Markdown 中区分（结构上标题已自带字重），与多数所见即所得编辑器一致

## 许可

沿用原项目 [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)，Copyright © 2026 Cliff。
