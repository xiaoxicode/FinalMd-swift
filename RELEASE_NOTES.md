墨写 —— macOS 原生 SwiftUI 版 Markdown 写作器（Electron 版移植）

## 下载

| 文件 | 说明 |
|---|---|
| `FinalMd-macOS-*.zip` | macOS 14+ / Apple Silicon (arm64)，解压后把 `墨写.app` 拖进「应用程序」 |
| `FinalMd-macOS-*.zip.sha256` | 校验和（下载后可用 `shasum -a 256 -c *.sha256` 验证） |

> **首次打开**：未配置 Developer ID 证书时是 ad-hoc 签名，macOS Gatekeeper 会拦截。
> 请右键「打开」一次，或到「系统设置 → 隐私与安全性」点「仍要打开」。
> 配置证书后流水线会自动完成签名与公证。

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
