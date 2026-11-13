墨写 —— macOS 原生 SwiftUI 版 Markdown 写作器（Electron 版移植）

## 下载

| 文件 | 说明 |
|---|---|
| `FinalMd-macOS-*.zip` | macOS 14+ / Apple Silicon (arm64)，解压后把 `FinalMd.app` 拖进「应用程序」 |
| `FinalMd-macOS-*.zip.sha256` | 校验和（下载后可用 `shasum -a 256 -c *.sha256` 验证） |

> **首次打开**：未配置 Developer ID 证书时是 ad-hoc 签名，下载后带 `com.apple.quarantine`
> 隔离属性，Gatekeeper 会拦截并可能提示「已损坏，无法打开」。这不是安装包损坏，
> 在终端执行一次即可（把路径换成实际位置）：
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/FinalMd.app
> ```
>
> 也可以右键「打开」一次，或到「系统设置 → 隐私与安全性」点「仍要打开」。
> 配置证书后流水线会自动完成签名与公证，之后下载即可直接打开。

## 应用名称

- 应用显示名跟随**系统语言**：简体/繁体中文显示「墨写」，英文及其他语言显示 `FinalMd`
- 不支持的系统语言默认回退英文；磁盘上的文件名统一为 `FinalMd.app`（旧版叫 `墨写.app`，升级时请注意替换）
- 切换系统语言后若 Finder / Dock 仍显示旧名，重新登录一次即可刷新
- 应用内「语言」菜单只切换界面文案，不改变 Finder / Dock 里的应用名

## 修复

- 插入点（光标）高度/粗细现在按光标所在位置的字体度量计算，标题、正文、代码块字号不同时光标同步变化
- 修复 1.8 倍行高下光标浮在文字上方的问题：改为按该行基线定位，光标上下边缘与文字齐平

## 编辑器

- 内核是原生 `NSTextView` + `NSAttributedString`，不是 WebView 套壳
- `.md` 文件格式与 Electron 版兼容；图表配置以 `mwchart:` 前缀存在图片 title 里，双击可回来改数据
- Markdown 快捷输入：`# ` `> ` ` ``` ` `- ` `1. ` 回车即成对应块
- 界面 7 种语言（中英日韩法德西），运行期可切换

## 缩放

| 操作 | 说明 |
|---|---|
| ⌘ 或 ⌃ + 滚轮 | 以指针位置为锚点，一格约 10% |
| 触控板双指捏合 | 系统原生 |
| ⌘+ / ⌘- / ⌘0、菜单「视图」 | 命令方式 |

范围 60%–200%，只改显示比例不改字号，因此不会影响 Markdown 输出。

## 构建

- 零第三方依赖：仅 SwiftUI / AppKit / Swift Charts / PDFKit
- 由 GitHub Actions（`macos-15` runner）编译打包
- 冒烟测试覆盖 Markdown 双向转换与滚动/缩放行为

开源许可：Apache 2.0（沿用原项目）
