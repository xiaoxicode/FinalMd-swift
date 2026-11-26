#!/bin/bash
# 重建 compat 检查器 + 全量语料 + 阈值闸门
cd /Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift || exit 2
SRC=/Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift
OUT=/tmp/finalmd-compat
WORK=/tmp/finalmd-compat-build
rm -rf "$OUT" "$WORK"
mkdir -p "$WORK"
cp "$SRC/scripts/compat-check.swift" "$WORK/main.swift"
swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx14.0 -O -o "$OUT" \
  "$SRC/Sources/FinalMd/I18n/Dictionaries.swift" "$SRC/Sources/FinalMd/I18n/I18nExtras.swift" \
  "$SRC/Sources/FinalMd/I18n/Localizer.swift" "$SRC/Sources/FinalMd/AI/AIProtocol.swift" \
  "$SRC/Sources/FinalMd/AI/AIPresets.swift" "$SRC/Sources/FinalMd/Markdown/HTMLEntities.swift" \
  "$SRC/Sources/FinalMd/Markdown/AttributedKeys.swift" "$SRC/Sources/FinalMd/Markdown/Typography.swift" \
  "$SRC/Sources/FinalMd/Markdown/EmphasisStack.swift" "$SRC/Sources/FinalMd/Markdown/InlineParser.swift" \
  "$SRC/Sources/FinalMd/Markdown/MarkdownParser.swift" "$SRC/Sources/FinalMd/Markdown/MarkdownSerializer.swift" \
  "$SRC/Sources/FinalMd/Markdown/MarkdownCompatibility.swift" "$SRC/Sources/FinalMd/Markdown/ObsidianLinks.swift" \
  "$SRC/Sources/FinalMd/Markdown/EmbedInline.swift" "$SRC/Sources/FinalMd/Markdown/TaskBoxToggle.swift" \
  "$SRC/Sources/FinalMd/Markdown/EditorMode.swift" "$SRC/Sources/FinalMd/Model/ChartConfig.swift" \
  "$SRC/Sources/FinalMd/Editor/InlineSelection.swift" "$SRC/Sources/FinalMd/Editor/CalloutFolding.swift" \
  "$SRC/Sources/FinalMd/Editor/TextFormatting.swift" "$SRC/Sources/FinalMd/Editor/ScrollView.swift" \
  "$SRC/Sources/FinalMd/Editor/SourceTextView.swift" "$SRC/Sources/FinalMd/Editor/EditorFocus.swift" \
  "$SRC/Sources/FinalMd/Util/ImageEmbed.swift" "$SRC/Sources/FinalMd/Util/HTMLExporter.swift" \
  "$WORK/main.swift" 2>&1 | grep -E "error:" && { echo BUILD_FAILED; exit 3; }
if [ ! -x "$OUT" ]; then echo BUILD_FAILED; exit 3; fi
echo "== compat run =="
timeout 480 "$OUT" > /tmp/compat-run.log 2>&1
echo "exit=$?"
tail -10 /tmp/compat-run.log
echo
echo "== threshold gate =="
python3 scripts/check-compat-thresholds.py
echo "gate_exit=$?"
