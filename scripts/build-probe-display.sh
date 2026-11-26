#!/bin/bash
# 编译 probe-display 探针（与 mainstream-check 同一源列表）
set -e
SRC=/Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift
OUT=/tmp/finalmd-probe-display
WORK=/tmp/finalmd-probe-display-build
rm -f "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
cp "$SRC/scripts/probe-display.swift" "$WORK/main.swift"
TARGET=arm64-apple-macosx14.0
[ "$(uname -m)" = "x86_64" ] && TARGET=x86_64-apple-macosx14.0
swiftc -sdk "$(xcrun --show-sdk-path)" -target "$TARGET" -O -o "$OUT" \
  "$SRC/Sources/FinalMd/I18n/Dictionaries.swift" \
  "$SRC/Sources/FinalMd/I18n/I18nExtras.swift" \
  "$SRC/Sources/FinalMd/I18n/Localizer.swift" \
  "$SRC/Sources/FinalMd/AI/AIProtocol.swift" \
  "$SRC/Sources/FinalMd/AI/AIPresets.swift" \
  "$SRC/Sources/FinalMd/Markdown/HTMLEntities.swift" \
  "$SRC/Sources/FinalMd/Markdown/AttributedKeys.swift" \
  "$SRC/Sources/FinalMd/Markdown/Typography.swift" \
  "$SRC/Sources/FinalMd/Markdown/EmphasisStack.swift" \
  "$SRC/Sources/FinalMd/Markdown/InlineParser.swift" \
  "$SRC/Sources/FinalMd/Markdown/MarkdownParser.swift" \
  "$SRC/Sources/FinalMd/Markdown/MarkdownSerializer.swift" \
  "$SRC/Sources/FinalMd/Markdown/MarkdownCompatibility.swift" \
  "$SRC/Sources/FinalMd/Markdown/ObsidianLinks.swift" \
  "$SRC/Sources/FinalMd/Markdown/EmbedInline.swift" \
  "$SRC/Sources/FinalMd/Markdown/TaskBoxToggle.swift" \
  "$SRC/Sources/FinalMd/Markdown/EditorMode.swift" \
  "$SRC/Sources/FinalMd/Model/ChartConfig.swift" \
  "$SRC/Sources/FinalMd/Editor/InlineSelection.swift" \
  "$SRC/Sources/FinalMd/Editor/CalloutFolding.swift" \
  "$SRC/Sources/FinalMd/Editor/TextFormatting.swift" \
  "$SRC/Sources/FinalMd/Editor/ScrollView.swift" \
  "$SRC/Sources/FinalMd/Editor/SourceTextView.swift" \
  "$SRC/Sources/FinalMd/Editor/EditorFocus.swift" \
  "$SRC/Sources/FinalMd/Util/ImageEmbed.swift" \
  "$SRC/Sources/FinalMd/Util/HTMLExporter.swift" \
  "$WORK/main.swift" 2>&1 | grep -E "error:" || true
if [ ! -x "$OUT" ]; then echo "BUILD FAILED"; exit 1; fi
echo "built $OUT"
