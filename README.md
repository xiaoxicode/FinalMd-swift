# 墨写 FinalMd — SwiftUI 原生版

Electron 版（[xiaoxicode/FinalMd](https://github.com/xiaoxicode/FinalMd)）的 **macOS 原生 SwiftUI 移植**。
所见即所得地写 Markdown，存出来是干净的 `.md` 文件。

- 目标平台：**macOS 14+**（仅桌面端）
- 编辑器内核：**NSTextView + NSAttributedString**（原生富文本，无内嵌浏览器）
- 语言：Swift 6 / SwiftUI / AppKit / Swift Charts，零第三方依赖
- 最新版本：**[Release v1.1.0](https://github.com/xiaoxicode/FinalMd-swift/releases/tag/v1.1.0)**
  （`FinalMd-macOS-1.1.0-*.zip`，macOS 14+ / arm64）
- Markdown 兼容性报告：[COMPATIBILITY.md](COMPATIBILITY.md)（51 个来源 / 416 份真实语料 + 1327 条规范用例 + 317 条主流语法矩阵）

---

## 快速开始

```bash
cd FinalMdSwift
./scripts/make_app.sh --run     # 编译并打包成 build/FinalMd.app 后打开
```

> ⚠️ **完整编译需要安装 Xcode（15+）**。
> SwiftUI 的 `@State` / `@Environment` 等是**外部宏**，其插件 `SwiftUIMacros` 只随 Xcode 提供；
> 只装 Command Line Tools 时 `swift build` 会报 `plugin for module 'SwiftUIMacros' not found`。
> `make_app.sh` 会自动切换到已安装的完整 Xcode 工具链；没有 Xcode 的机器可用下面两个脚本做**替代验证**（详见「验证情况」）。

在没有 Xcode 的机器上仍可运行的两项检查：

```bash
./scripts/run-smoke.sh   # Markdown 双向转换 + 编辑器行为 + AI 协议冒烟测试（699 项）—— 直接跑，不需要 Xcode
./scripts/verify.sh      # 整套视图代码的类型校验（用宏桩顶替 @State 等）
```

在 Xcode 里开发：直接用 Xcode 打开本目录（`open Package.swift`），或新建 macOS App target 后把
`Sources/FinalMd` 与 `Resources` 挂进去即可。

---

## 自定义大模型（AI 助手）

在「AI 助手」菜单或功能区 ✨ 按钮里，用**一句话**对选中的文字或整篇文档做处理。兼容任何提供 OpenAI `/chat/completions` 协议的云端或本地模型。

### 配置

1. 打开「AI 助手 → 模型设置…」，可用「快速填充」一键带入 OpenAI / DeepSeek / Ollama 的地址与模型名。
2. 填接口地址（`/v1`、`/chat/completions` 完整路径或裸域名都行）、API Key、模型名；可调温度、超时与系统提示词。
3. 点「测试连接」确认可用，再「保存设置」。本机 Ollama / LM Studio 用 `http://127.0.0.1:11434/v1`，**不需要密钥**。

| 数据 | 存放位置 | 说明 |
|---|---|---|
| 接口地址 / 模型 / 温度 / 超时 | `UserDefaults` | 非敏感的本机偏好 |
| API Key | **系统钥匙串** | 只进 Keychain，不写进 plist、文档或日志 |
| 原文与指令 | 内存 + 你配置的端点 | 只在点「生成」时发送一次，不做后台采集 |

`Resources/FinalMd.entitlements` 的 `com.apple.security.network.client` 已在 `make_app.sh` / `sign_and_notarize.sh` 签名时写入（公证版启用 hardened runtime 后没它会静默断网）；`Info.plist` 的 `NSAllowsLocalNetworking` 仅为本机 `http://` 模型放行，远端服务仍必须 https。

### 一句话指令

内置预设：**润色**、**整理为 Agent 易读格式**、精简、提炼要点、纠错、翻译成英文，也可选「自定义指令」自己写。Agent 预设会把内容重写为「目标 / 背景与约束 / 输入 / 步骤 / 输出格式 / 验收标准」的结构化 Markdown，把「尽量、适当」等模糊表述改成可判定条件，并给不确定处标 `[待确认]`。

生成后先预览，再决定「替换选中文字 / 插入到光标 / 替换整篇 / 复制结果」，**不会自动改动正文**；每次写入合并成一次 `⌘Z`。原文经 `MarkdownSerializer` 取出、结果经 `MarkdownParser` 还原样式，标题与列表格式不丢。

### 验证步骤

1. 设置面板点「测试连接」，应提示「连接成功，模型可用」；401 查 Key，404 查地址与模型名，超时查本机服务是否已启动。
2. 选中一段文字 → ⌘⇧A → 选「润色」→ 生成 →「替换选中文字」，确认只有选中部分被替换，且一次 ⌘Z 能整段撤回。
3. 不选文字直接打开，范围自动切到「整篇文档」；用 Agent 预设生成后保存 `.md`，检查标题、有序列表与代码块结构。
4. 用本机模型时断网重复 1–2，验证不走外网。

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
git tag v1.1.0 && git push --tags          # 或打 tag：构建完自动发 Release
```

流水线做的事：

| 步骤 | 说明 |
|---|---|
| 冒烟测试 | 先跑 699 项断言（Markdown 往返 + 真实 `NSTextView` 行内样式范围 + AI 协议），不过就不往下走 |
| 编译 + 组装 | `swift build -c release` → `build/FinalMd.app`，ad-hoc 签名 |
| bundle 校验 | 检查可执行文件、Info.plist、图标、版本、最低系统版本、中英文 `InfoPlist.strings` 与英文回退，并做 `codesign --verify` 签名自检 |
| Developer ID 签名 + 公证（可选） | 配了证书 secrets 才执行，`scripts/sign_and_notarize.sh` |
| 打包上传 | 生成 `FinalMd-macOS-<版本>-<commit>.zip` + `.sha256`，作为 artifact 保留 30 天 |
| 发布 Release | 仅 `v*` tag 触发，自动挂 zip 到 Release |

### 首次打开提示「已损坏 / 无法验证开发者」

`make_app.sh` 和未配置证书的 CI 产物都是 **ad-hoc 签名**（`Signature=adhoc`，无 Team ID）。
本机编译出来的 `build/FinalMd.app` 可以直接双击；但只要经过**下载 / 网盘 / 压缩包**传递，
macOS 会给它加上 `com.apple.quarantine` 隔离属性，Gatekeeper 于是拦截，提示「已损坏，无法打开」
或「无法验证开发者」。**这不是编译失败**，代码签名本身是有效的。

先确认签名没坏（若确实无效，请重新解压或重新下载）：

```bash
codesign --verify --deep --strict /path/to/FinalMd.app
xattr -l /path/to/FinalMd.app | grep quarantine
```

解除隔离属性后即可打开：

```bash
xattr -dr com.apple.quarantine /path/to/FinalMd.app
open /path/to/FinalMd.app
```

也可以右键 →「打开」，或到「系统设置 → 隐私与安全性」点「仍要打开」。
要让别人下载后**直接**能打开，只能走下面的 Developer ID 签名 + 公证。

### 分发前配置签名（根治）

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
│   │   ├── AppCommands.swift         文件/编辑/插入/格式/AI/视图/语言/帮助 八个菜单
│   │   └── AppDelegate.swift         窗口生命周期 + 应用级未保存退出确认
│   ├── Model/
│   │   ├── AppModel.swift            全局状态：文档、统计、读写、查找替换
│   │   ├── AppModel+AI.swift         AI 原文快照 / 结果写回（一次撤销）
│   │   └── ChartConfig.swift         图表配置 + Base64 编码（存进图片 title）
│   ├── AI/                           ★ 自定义大模型接入（OpenAI 兼容协议）
│   │   ├── AIProtocol.swift          端点归一化 / 请求构造 / 响应解析（纯函数，可单测）
│   │   ├── AIClient.swift            非流式 /chat/completions 调用与错误分类
│   │   ├── AISettings.swift          配置持久化 + API Key 钥匙串 + 服务预设
│   │   ├── AIPresets.swift           内置润色 / Agent 结构化等指令
│   │   └── AIController.swift        面板状态机、生成与结果落回文档
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
│   │   ├── AIPanels.swift            模型设置 / AI 指令面板
│   │   └── ChartDialogView.swift     图表对话框（数据网格 + 实时预览）
│   ├── I18n/
│   │   ├── Dictionaries.swift        ⚙️ 自动生成：7 语言 × 213 key
│   │   ├── I18nExtras.swift          手写补充：AI 功能词条（zh / en，其余回退 en）
│   │   └── Localizer.swift           运行期切换语言、占位符替换、持久化
│   └── Util/
│       ├── OpenSavePanel.swift       NSOpenPanel / NSSavePanel 的 async 封装
│       ├── HTMLExporter.swift        导出独立 HTML（沿用原版 CSS）
│       ├── PDFExporter.swift         分页导出 PDF
│       ├── ImageEmbed.swift          Base64 内嵌 + 超 380KB 自动压缩
│       └── UpdateChecker.swift       查 GitHub Release（替代 electron-updater）
├── Resources/                        Info.plist + 应用图标 + 本地化显示名 + 权限声明
│   ├── Info.plist                    默认（英文）名为 FinalMd，开发语言 en
│   ├── FinalMd.entitlements           network.client / 用户选中文件读写（签名时写入）
│   ├── en.lproj/InfoPlist.strings    英文 / 其他语言：FinalMd
│   ├── zh.lproj/InfoPlist.strings    中文（通用）：墨写
│   ├── zh-Hans.lproj/InfoPlist.strings  简体中文：墨写
│   ├── zh-Hant.lproj/InfoPlist.strings  繁体中文：墨写
│   └── AppIcon.icns
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
| `scripts/smoke.js`（64 项） | `scripts/smoke.swift`（699 项） | 聚焦 Markdown 往返一致性、编辑器行为与 AI 协议 |

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

### 5. 应用名称跟随系统语言

磁盘上的 bundle 固定叫 `FinalMd.app`（ASCII，任何语言下都一样）；**显示名**交给系统按语言选：

| 系统语言 | Finder / Dock / 菜单栏 / 窗口标题 |
|---|---|
| 简体中文、繁体中文、`zh-*` | 墨写 |
| 英文及其他语言（含不支持的语言） | FinalMd |

1. `Resources/Info.plist` 里 `CFBundleName` / `CFBundleDisplayName` 写默认英文 `FinalMd`，
   `CFBundleDevelopmentRegion` 设为 `en` —— 系统语言没有匹配的 `.lproj` 时一定回退到英文，而不是中文。
2. 中文名只放在 `zh` / `zh-Hans` / `zh-Hant` 三个 `.lproj/InfoPlist.strings` 里，同时覆盖
   `CFBundleName`（菜单栏的「关于/隐藏/退出 XXX」）与 `CFBundleDisplayName`（Finder / Dock / 窗口标题）。
3. `scripts/make_app.sh` 把 `.lproj` 复制进 `Contents/Resources/`，并把仓库里的 UTF-8 源码转成
   `InfoPlist.strings` 所需的 UTF-16（带 BOM），否则中文名会乱码。
4. 应用内界面文案仍由 `Localizer` 独立管理（7 语言，可在「语言」菜单手动切换）；**显示名只看系统语言**，
   与界面语言设置无关 —— 这也是 macOS 对 bundle 名称的标准行为。

> 切换系统语言后 Finder / Dock 可能缓存旧名字，重新登录，或执行一次
> `lsregister -f /Applications/FinalMd.app && killall Finder` 刷新；已运行的进程要重启才会更新菜单栏名称。

### 6. 插入点随字号缩放，并与文字齐平

AppKit 默认按视图的 `font`（固定 16pt 正文）计算插入点高度，切到 H1（30.4pt）或代码块（14pt）时光标仍一样高。
`DocTheme.caretSize(for:)` 按字体的 `ascender - descender + leading` 算出高度与宽度。

纵向位置不能按「行片段中线」算：正文用了 `lineHeightMultiple = 1.8`，TextKit 把多出来的行距
加在**行片段顶部**，字形其实沉在底部（16pt 正文实测行片段 `0..32.4`、基线却在 `29.4`），
按中线居中会把光标画到文字上方约 7pt，看起来就是「偏上、没和文字齐平」。
因此 `MDEditorTextView` 通过 `layoutManager` 找到光标所在行的**基线**，
再由 `DocTheme.caretRect(baselineY:x:font:)` 以基线为锚反推矩形：
顶部 ≈ `baseline - ascender`，底部 ≈ `baseline - descender`，与字身上下边缘对齐。
`typingAttributes` 变化后调用 `updateInsertionPointStateAndRestartTimer(true)` 立即重绘；
缩放（magnification）由 `NSScrollView` 的坐标系变换负责，光标会随之等比变化。

### 7. 行内样式只作用于选中的字符

凸显 / 字体色 / 加粗 / 斜体 / 下划线 / 删除线 / 行内代码 / 清除格式这些**行内**样式，
与标题 / 列表 / 对齐这些**块级**样式对范围的要求正好相反：

- 块级样式要把属性写到整段（含段落终结符 `\n`），回车才能继承模式，走 `performEdit` + `targetRanges()`；
- 行内样式必须严格限定在用户选中的字符里，走 `performInlineStyle` + `InlineSelection.slices()`。

旧实现让两者共用 `performEdit`，于是出现两种误伤：选区一直拖到行尾时，`targetRanges()`
会补上 `\n`，AppKit 把段落终结符上的 `backgroundColor` 渲染成**行尾一整块色块**，
序列化时 `<span>` 还会跨到下一行；没有选区（纯光标）时更是直接把**整段**涂色。
`InlineSelection.slices()` 按段落终结符、软换行与图片附件占位符切分选区，只返回有可见字身的字符段。
无选区时不改动任何已有文字，只把样式写进 `typingAttributes`，让「先点荧光笔再打字」仍然生效；
`InlineTypingMemory` 协议记住开启时的插入点，避免弹面板切焦点触发的 `didChangeSelection` 把样式冲掉，
光标一移动即作废。

### 8. AI 结果先预览、再一次撤销地写回

协议层（`AIProtocol.swift`）全是纯函数：端点归一化、请求构造、响应解析、结果清理，所以能脱离 UI 和网络直接进冒烟测试。
调用层刻意用**非流式**一次请求——流式对整段润色收益不大，却会把一次编辑拆成几十次撤销。
`AppModel+AI.swift` 把原文快照用 `MarkdownSerializer` 取出、结果用 `MarkdownParser` 还原成属性串，
包在**一次** `shouldChangeText` / `didChangeText` 里替换，保证 `⌘Z` 一次回到生成前。
面板只负责预览，用户显式点「替换 / 插入 / 复制」才动正文。

### 9. 关窗不退出、Dock 图标能叫回窗口

原先未保存确认是挂在 `ContentView` 上的 SwiftUI `.sheet`，而 `applicationShouldTerminate` 已返回
`.terminateLater` 等待它的回复。窗口一关，sheet 永远无法呈现，`reply(toApplicationShouldTerminate:)` 再也不会被调用，
于是 Dock 右键「退出」卡死、点图标也回不到前台。现在：

- 确认改用**应用级 `NSAlert`**（`runModal()` 同步返回），不依赖任何窗口；只有「保存」这一支因要弹 `NSSavePanel` 才用 `.terminateLater`，并在 Task 里明确 `reply`；
- `applicationShouldTerminateAfterLastWindowClosed` 返回 `false`，窗口关掉后进程留在 Dock；Info.plist 同步关掉 `NSSupportsAutomaticTermination`，避免系统悄悄终止进程丢掉未保存内容；
- `WindowGroup(id: "main")` + `ContentView` 把 `openWindow` 注册给 `WindowBridge`，`applicationShouldHandleReopen` 在点 Dock 图标时重建 / 唤醒主窗口。

### 10. 原样透传与 Callout 格式开关

frontmatter、原始 HTML、链接 / 脚注定义、独立与列表项内的缩进代码块、双链 / 嵌入 / Callout / 任务框都用原始行快照承载，未编辑时逐字写回；语法特征由 `.mdCalloutTraits` 等属性记录，编辑后才按当前富文本重建。Callout 行额外保存一份**格式指纹**：文字没变而只改了粗 / 斜 / 颜色等格式时，默认让改动生效；若你更看重「原行逐字保真」，可在「视图 → Callout 格式改动生效」关掉该开关（偏好持久化在 `UserDefaults`）。

---

## 验证情况

| 项目 | 结果 |
|---|---|
| Markdown / 编辑器 / AI 协议冒烟测试 | ✅ **699 项全部通过**（`./scripts/run-smoke.sh`） |
| 主流语法矩阵 | ✅ **317/317 一次稳定，语义 314/314，已知取舍 0**（`scripts/run-mainstream.py`，对照 commonmark.js / marked） |
| 真实语料 + 官方规范用例 | ✅ **416/416 语料、1327/1327 规范用例**一次稳定且收敛，平均可读字符保留率 **100.0%**、结构识别率 **100.0%** |
| 逐字透传 / 扩展语法硬约束 | ✅ 透传块 **872/872（100%）**；双链 / 嵌入 / Callout / 任务框 / 缩进代码块均 100% 逐字保留 |
| 回归阈值闸门 | ✅ `python3 scripts/check-compat-thresholds.py` 全绿（不收敛 0、倒退 0） |
| 全套视图代码类型校验 | ✅ **Build complete，0 error**（`./scripts/verify.sh`） |
| 完整 `swift build` + 打包 | ✅ 本机完整 Xcode 工具链 release 编译 + bundle 自检通过（`./scripts/make_app.sh`） |
| 签名 / 启动 | ✅ `codesign --verify --deep --strict` 通过；entitlements 已签入；`open -a` 实测可启动 |
| 窗口生命周期 | ✅ 关闭窗口后进程保留、点 Dock 图标窗口恢复；未保存时应用级确认框弹出，退出完成 |
| GitHub Actions | ✅ `Build macOS App` + `Markdown 兼容性回归` 两条流水线 |

一键复现：`bash scripts/regress-all.sh`（主流矩阵 + 冒烟）、`bash scripts/compat-and-gate.sh`（全量语料 + 阈值闸门）、`bash scripts/update-report-baseline.sh`（重生成 `COMPATIBILITY.md`）。完整缺陷清单、逐来源数据与已知边界见 [COMPATIBILITY.md](COMPATIBILITY.md)。

冒烟测试覆盖：六级标题、粗斜体/删除线/行内代码/下划线/链接/嵌套强调、段落、引用、分割线、
有序与无序列表、围栏代码块（含语言）、表格（含表头）、图片（Base64）、
字体色与高亮（`<span>` / `<mark>`）、转义，以及一份包含全部块类型的综合文档与欢迎文档的**二次往返稳定性**；
另外还覆盖**滚动容器行为**：各缩放值下页面水平居中、放大后横滑能拖动（含事件穿过文字视图）、
连续捏合文档宽度稳定，以及 ⌘+滚轮的缩放方向、回调同步、60%–200% 上下限；
还有插入点尺寸与位置：H1 / 正文 / 代码块字号的单调性、与字号的比例关系、六级标题逐级递减，
以及按基线纵向对齐（顶边 / 底边贴合字身、修复行高造成的偏上、整行下移时等量跟随）；
最后覆盖**行内样式作用范围**：部分选区 / 跨行 / 到行尾 / 全篇 / 空选区 / 越界 / 附件的精确切片，
凸显与 `<span>` 只包住选中字符、换行符不携带背景色，以及在真实 `NSTextView` 上设置选区后
直接调用 `setHighlight` / `setTextColor` / `toggleUnderline` / `applyBlockStyle` 的属性落点；
**AI 协议层**另覆盖端点归一化（`/v1` / 完整路径 / 裸域名 / 本机 http / 非法值）、请求体与 Bearer 头、
四种响应形态与服务端 `error.message`、Markdown 围栏剥离、HTTP 状态分类，以及内置预设与中英文案的一一对应。

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
- `***a ***b***` 这类嵌套强调在未编辑时逐字保真；编辑该行后只能按富文本的粗 / 斜 trait 重建，不还原原嵌套写法
- 即刻模式会统一列表符号、段落空行与标题写法；需要逐字节保留外部文件时请用传统模式，或调整「视图 → 打开外部 Markdown 时」策略
- 未配置 Developer ID 时产物为 ad-hoc 签名，经下载传递后会被 Gatekeeper 拦截，需先解除隔离属性（见「首次打开提示已损坏」）
- AI 功能为非流式请求，长文档生成期间面板会等待；模型不支持的语言会直接返回服务端错误
- AI 界面文案只有中 / 英完整，其余 5 种语言沿 `Localizer` 既有链路回退英文
- 每次 `make_app.sh` 重新 ad-hoc 签名后，钥匙串里的 API Key 有可能因签名标识变化读不到，重新填一次即可；正式分发请用 Developer ID 签名

## 许可

沿用原项目 [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)，Copyright © 2026 Cliff。
