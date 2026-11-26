#!/bin/bash
# build-mainstream.sh — 编译 mainstream-check.swift → /tmp/finalmd-mainstream
set -e
cd /Users/daijh/WorkBuddy/2026-11-25-12-05-46/FinalMd-swift
WORK=/tmp/finalmd-mainstream-build
rm -rf $WORK && mkdir -p $WORK
cp scripts/mainstream-check.swift $WORK/main.swift
if [ "$(uname -m)" = "x86_64" ]; then TARGET=x86_64-apple-macosx14.0; else TARGET=arm64-apple-macosx14.0; fi
rm -f /tmp/finalmd-mainstream
swiftc -sdk "$(xcrun --show-sdk-path)" -target "$TARGET" -O -o /tmp/finalmd-mainstream \
  Sources/FinalMd/I18n/Dictionaries.swift Sources/FinalMd/I18n/I18nExtras.swift Sources/FinalMd/I18n/Localizer.swift \
  Sources/FinalMd/AI/AIProtocol.swift Sources/FinalMd/AI/AIPresets.swift \
  Sources/FinalMd/Markdown/HTMLEntities.swift Sources/FinalMd/Markdown/AttributedKeys.swift Sources/FinalMd/Markdown/Typography.swift Sources/FinalMd/Markdown/EmphasisStack.swift \
  Sources/FinalMd/Markdown/InlineParser.swift Sources/FinalMd/Markdown/MarkdownParser.swift Sources/FinalMd/Markdown/MarkdownSerializer.swift \
  Sources/FinalMd/Markdown/MarkdownCompatibility.swift Sources/FinalMd/Markdown/ObsidianLinks.swift Sources/FinalMd/Markdown/EmbedInline.swift \
  Sources/FinalMd/Markdown/TaskBoxToggle.swift Sources/FinalMd/Markdown/EditorMode.swift \
  Sources/FinalMd/Model/ChartConfig.swift Sources/FinalMd/Editor/InlineSelection.swift Sources/FinalMd/Editor/CalloutFolding.swift \
  Sources/FinalMd/Editor/TextFormatting.swift Sources/FinalMd/Editor/ScrollView.swift Sources/FinalMd/Editor/SourceTextView.swift \
  Sources/FinalMd/Editor/EditorFocus.swift Sources/FinalMd/Util/ImageEmbed.swift Sources/FinalMd/Util/HTMLExporter.swift \
  $WORK/main.swift 2>&1 | grep -E "error:" || true
if [ ! -x /tmp/finalmd-mainstream ]; then echo "BUILD FAILED"; exit 1; fi
echo "built /tmp/finalmd-mainstream"
