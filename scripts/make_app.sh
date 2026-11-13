#!/usr/bin/env bash
#
# 把 SwiftPM 构建出的可执行文件包装成 macOS 应用 bundle。
# 不需要 Xcode：SwiftPM + Command Line Tools 即可（签名用 ad-hoc 身份，本地可直接双击运行）。
#
#   ./scripts/make_app.sh          # 打包到 build/FinalMd.app
#   ./scripts/make_app.sh --run    # 打包后直接打开
#
# 磁盘上的 bundle 名固定为 FinalMd.app（ASCII，各语言一致）；
# Finder / Dock / 菜单栏显示的名字由 Contents/Resources/*.lproj/InfoPlist.strings
# 按系统语言决定：中文「墨写」，其余语言（含不支持的语言）FinalMd。
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$SRC/build"
APP="$APP_DIR/FinalMd.app"
EXE_NAME="FinalMd"

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
# 旧版本产物叫「墨写.app」，留着会和新包并存、容易误开旧包
rm -rf "$APP_DIR/墨写.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXE_NAME"
cp "$SRC/Resources/Info.plist" "$APP/Contents/Info.plist"
[[ -f "$SRC/Resources/AppIcon.icns" ]] && cp "$SRC/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# 本地化显示名：把各语言的 InfoPlist.strings 放进 Contents/Resources/*.lproj。
# 仓库里存 UTF-8（方便 diff / 编辑），但 CFBundle 读 InfoPlist.strings 用 UTF-16，
# 所以打包时转成带 BOM 的 UTF-16，避免中文名在 Finder 里变乱码。
for LPROJ in "$SRC"/Resources/*.lproj; do
  [[ -d "$LPROJ" ]] || continue
  DEST="$APP/Contents/Resources/$(basename "$LPROJ")"
  mkdir -p "$DEST"
  for STRINGS in "$LPROJ"/*.strings; do
    [[ -f "$STRINGS" ]] || continue
    iconv -f UTF-8 -t UTF-16 "$STRINGS" > "$DEST/$(basename "$STRINGS")"
  done
done

# 自检：plist 合法，且中英文的显示名确实写进去了
plutil -lint "$APP/Contents/Info.plist" >/dev/null
iconv -f UTF-16 -t UTF-8 "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" | grep -q '"CFBundleDisplayName" = "墨写"'
iconv -f UTF-16 -t UTF-8 "$APP/Contents/Resources/en.lproj/InfoPlist.strings" | grep -q '"CFBundleDisplayName" = "FinalMd"'

# 清掉从源文件继承来的扩展属性（com.apple.quarantine / provenance 等）。
# 带隔离属性的 bundle 即使签名有效，Gatekeeper 也会拦截首次打开，提示「已损坏」。
xattr -cr "$APP" 2>/dev/null || true

# ad-hoc 签名：本机可直接运行；正式分发请换成 Developer ID 并做公证。
# 签名失败必须让构建失败——静默产出的未签名 bundle 在 macOS 上一定打不开。
if ! codesign --force --deep --sign - "$APP"; then
  echo "❌ ad-hoc 签名失败，产物无法在 macOS 上打开" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP" >/dev/null || { echo "❌ 签名自检失败" >&2; exit 1; }

echo "✅ 完成：${APP}（中文系统显示「墨写」／其他语言显示 FinalMd）"
echo "ℹ️  ad-hoc 签名仅供本机使用；经下载 / 压缩分发后被 Gatekeeper 拦截时，执行："
echo "   xattr -dr com.apple.quarantine \"$APP\""

if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
