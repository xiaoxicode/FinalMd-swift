#!/usr/bin/env bash
#
# 编译并运行 Markdown 双向转换冒烟测试。
# 只编译不涉及 SwiftUI 宏的那几层（i18n / Markdown / 图表模型 / 图片内嵌），
# 因此在只装了 Command Line Tools、没有 Xcode 的机器上也能跑。
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/finalmd-smoke"
WORK="${TMPDIR:-/tmp}/finalmd-smoke-build"

rm -rf "$OUT" "$WORK"
mkdir -p "$WORK"
# 顶层可执行语句必须放在名为 main.swift 的文件里
cp "$SRC/scripts/smoke.swift" "$WORK/main.swift"

# CI 上可能是 Intel 也可能是 Apple Silicon，按宿主架构选择 target
if [[ "$(uname -m)" == "x86_64" ]]; then
  TARGET="x86_64-apple-macosx14.0"
else
  TARGET="arm64-apple-macosx14.0"
fi

FILES=(
  "$SRC/Sources/FinalMd/I18n/Dictionaries.swift"
  "$SRC/Sources/FinalMd/I18n/I18nExtras.swift"
  "$SRC/Sources/FinalMd/I18n/Localizer.swift"
  "$SRC/Sources/FinalMd/AI/AIProtocol.swift"
  "$SRC/Sources/FinalMd/AI/AIPresets.swift"
  "$SRC/Sources/FinalMd/Markdown/HTMLEntities.swift"
  "$SRC/Sources/FinalMd/Markdown/AttributedKeys.swift"
  "$SRC/Sources/FinalMd/Markdown/Typography.swift"
  "$SRC/Sources/FinalMd/Markdown/EmphasisStack.swift"
  "$SRC/Sources/FinalMd/Markdown/InlineParser.swift"
  "$SRC/Sources/FinalMd/Markdown/MarkdownParser.swift"
  "$SRC/Sources/FinalMd/Markdown/MarkdownSerializer.swift"
  "$SRC/Sources/FinalMd/Markdown/MarkdownCompatibility.swift"
  "$SRC/Sources/FinalMd/Markdown/ObsidianLinks.swift"
  "$SRC/Sources/FinalMd/Markdown/EmbedInline.swift"
  "$SRC/Sources/FinalMd/Markdown/TaskBoxToggle.swift"
  "$SRC/Sources/FinalMd/Markdown/EditorMode.swift"
  "$SRC/Sources/FinalMd/Model/ChartConfig.swift"
  "$SRC/Sources/FinalMd/Editor/InlineSelection.swift"
  "$SRC/Sources/FinalMd/Editor/CalloutFolding.swift"
  "$SRC/Sources/FinalMd/Editor/TextFormatting.swift"
  "$SRC/Sources/FinalMd/Editor/ScrollView.swift"
  "$SRC/Sources/FinalMd/Editor/SourceTextView.swift"
  "$SRC/Sources/FinalMd/Editor/EditorFocus.swift"
  "$SRC/Sources/FinalMd/Util/ImageEmbed.swift"
  "$SRC/Sources/FinalMd/Util/HTMLExporter.swift"
  "$WORK/main.swift"
)

echo "→ 编辑模式焦点回归检查…"
# 防回归：在 SwiftUI 的 layout / display cycle 里直接 resignFirstResponder()
# 会让 AppKit 走 -[NSWindow _newFirstResponderAfterResigning] 猜下一个响应者，
# 找不到候选时抛 NSException → SIGABRT（启动首帧必现）。
# 焦点必须统一由 EditorFocus → NSWindow.makeFirstResponder(_:) 移交。
# 只检查代码行；注释里提到这个方法名是说明文档，不算调用。
DIRECT_RESIGN="$(grep -R --include='*.swift' -n 'resignFirstResponder()' "$SRC/Sources" \
  | grep -vE ':[0-9]+:[[:space:]]*(//|\*)' || true)"
if [[ -n "$DIRECT_RESIGN" ]]; then
  echo "❌ 发现直接调用 resignFirstResponder()：请用 EditorFocus.scheduleHandoff(to:)"
  printf '%s\n' "$DIRECT_RESIGN"
  exit 1
fi
echo "  ✓ 未发现直接 resignFirstResponder()"

echo "→ 编译冒烟测试…"
swiftc \
  -sdk "$(xcrun --show-sdk-path)" \
  -target "$TARGET" \
  -O \
  -o "$OUT" \
  "${FILES[@]}" 2>&1 | grep -E "error:" || true

if [[ ! -x "$OUT" ]]; then
  echo "❌ 编译失败"
  exit 1
fi

echo "→ 运行冒烟测试…"
"$OUT"
