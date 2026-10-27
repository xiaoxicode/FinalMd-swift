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
  "$SRC/Sources/FinalMd/I18n/Localizer.swift"
  "$SRC/Sources/FinalMd/Markdown/AttributedKeys.swift"
  "$SRC/Sources/FinalMd/Markdown/Typography.swift"
  "$SRC/Sources/FinalMd/Markdown/InlineParser.swift"
  "$SRC/Sources/FinalMd/Markdown/MarkdownParser.swift"
  "$SRC/Sources/FinalMd/Markdown/MarkdownSerializer.swift"
  "$SRC/Sources/FinalMd/Model/ChartConfig.swift"
  "$SRC/Sources/FinalMd/Editor/ScrollView.swift"
  "$SRC/Sources/FinalMd/Util/ImageEmbed.swift"
  "$WORK/main.swift"
)

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
