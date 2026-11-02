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

# 本机 xcode-select 指向 Command Line Tools 时，SwiftUI 宏插件（Observation / StateMacro）缺失，
# 直接 swift build 会报「external macro implementation type could not be found」。
# 这里自动切到已安装的完整 Xcode 工具链，免得每次手动export。
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
  for x in /Applications/Xcode*.app; do
    [[ -d "$x/Contents/Developer" ]] || continue
    export DEVELOPER_DIR="$x/Contents/Developer"
    echo "→ 使用工具链：$DEVELOPER_DIR"
    break
  done
fi

echo "→ 编译 Release…"
# 个别受限环境（CI / 沙箱）里 SwiftPM 自己的 sandbox-exec 会申请失败，退回 --disable-sandbox 重试一次。
if ! swift build -c release; then
  echo "→ 首次编译失败，关闭 SwiftPM 沙箱重试…"
  swift build -c release --disable-sandbox
fi

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
