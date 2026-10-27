#!/usr/bin/env bash
#
# 把 SwiftPM 构建出的可执行文件包装成 macOS 应用 bundle。
# 不需要 Xcode：SwiftPM + Command Line Tools 即可（签名用 ad-hoc 身份，本地可直接双击运行）。
#
#   ./scripts/make_app.sh          # 打包到 build/墨写.app
#   ./scripts/make_app.sh --run    # 打包后直接打开
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$SRC/build"
APP="$APP_DIR/墨写.app"
EXE_NAME="墨写"

cd "$SRC"

echo "→ 编译 Release…"
swift build -c release

BIN="$SRC/.build/release/FinalMd"
if [[ ! -x "$BIN" ]]; then
  echo "❌ 没找到可执行文件：$BIN"
  exit 1
fi

echo "→ 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXE_NAME"
cp "$SRC/Resources/Info.plist" "$APP/Contents/Info.plist"
[[ -f "$SRC/Resources/AppIcon.icns" ]] && cp "$SRC/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# ad-hoc 签名：本机可直接运行；正式分发请换成 Developer ID 并做公证
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "（跳过签名）"

echo "✅ 完成：$APP"

if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
