#!/usr/bin/env bash
#
# 编译并运行 FinalMd 兼容性测试。
# 只编译不依赖 SwiftUI 宏的 Markdown / AppKit 层，与 run-smoke.sh 同一套源文件。
# 结果写入 tests/fixtures/RESULTS.json，再由 gen-compat-report.py 生成报告。
#
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/finalmd-compat"
WORK="${TMPDIR:-/tmp}/finalmd-compat-build"

rm -rf "$OUT" "$WORK"
mkdir -p "$WORK"
cp "$SRC/scripts/compat-check.swift" "$WORK/main.swift"

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
  "$SRC/Sources/FinalMd/Markdown/AttributedKeys.swift"
  "$SRC/Sources/FinalMd/Markdown/Typography.swift"
  "$SRC/Sources/FinalMd/Markdown/InlineParser.swift"
  "$SRC/Sources/FinalMd/Markdown/MarkdownParser.swift"
  "$SRC/Sources/FinalMd/Markdown/MarkdownSerializer.swift"
  "$SRC/Sources/FinalMd/Markdown/EditorMode.swift"
  "$SRC/Sources/FinalMd/Model/ChartConfig.swift"
  "$SRC/Sources/FinalMd/Editor/InlineSelection.swift"
  "$SRC/Sources/FinalMd/Editor/TextFormatting.swift"
  "$SRC/Sources/FinalMd/Editor/ScrollView.swift"
  "$SRC/Sources/FinalMd/Editor/SourceTextView.swift"
  "$SRC/Sources/FinalMd/Editor/EditorFocus.swift"
  "$SRC/Sources/FinalMd/Util/ImageEmbed.swift"
  "$WORK/main.swift"
)

echo "→ 编译兼容性测试程序…"
swiftc \
  -sdk "$(xcrun --show-sdk-path)" \
  -target "$TARGET" \
  -O \
  -o "$OUT" \
  "${FILES[@]}" 2>&1 | grep -E "error:|warning:" || true

if [[ ! -x "$OUT" ]]; then
  echo "❌ 编译失败"
  exit 1
fi

echo "→ 运行兼容性测试…"
cd "$SRC"
"$OUT"
