#!/usr/bin/env bash
#
# 用 Developer ID 给 墨写.app 签名并送 Apple 公证。
# 只在 CI 里配置了证书类 secrets 时才会被调用（见 .github/workflows/build-macos.yml）。
#
# 需要的环境变量：
#   MACOS_CERTIFICATE            base64 编码的 .p12 证书（导出时含私钥）
#   MACOS_CERTIFICATE_PASSWORD   .p12 的导出密码
#   MACOS_KEYCHAIN_PASSWORD      临时 keychain 的密码（任意字符串）
#   NOTARIZE_APPLE_ID            Apple ID
#   NOTARIZE_TEAM_ID             Team ID
#   NOTARIZE_PASSWORD            App 专用密码（appleid.apple.com 生成）
#
# 缺少任一变量则跳过，保持 make_app.sh 已有的 ad-hoc 签名。
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP="$SRC/build/墨写.app"
TMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

need() { [[ -n "${!1:-}" ]] || { echo "⚠️ 缺少 $1，跳过签名与公证"; exit 0; }; }
need MACOS_CERTIFICATE
need MACOS_CERTIFICATE_PASSWORD
need MACOS_KEYCHAIN_PASSWORD
need NOTARIZE_APPLE_ID
need NOTARIZE_TEAM_ID
need NOTARIZE_PASSWORD

[[ -d "$APP" ]] || { echo "❌ 没找到 $APP，请先跑 scripts/make_app.sh"; exit 1; }

echo "→ 导入签名证书…"
CERT_PATH="$TMP/finalmd-cert.p12"
KEYCHAIN_PATH="$TMP/finalmd-signing.keychain-db"
rm -f "$CERT_PATH" "$KEYCHAIN_PATH"

echo -n "$MACOS_CERTIFICATE" | base64 --decode -o "$CERT_PATH"

security create-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" \
  -P "$MACOS_CERTIFICATE_PASSWORD" \
  -A -t cert -f pkcs12 \
  -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -k "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychain -d user -s "$KEYCHAIN_PATH"

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
  | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [[ -z "$IDENTITY" ]]; then
  echo "❌ 没有可用的 Developer ID Application 签名身份"
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true
  exit 1
fi
echo "  签名身份：$IDENTITY"

echo "→ 签名（hardened runtime）…"
codesign --force --deep --timestamp --options runtime \
  --sign "$IDENTITY" --keychain "$KEYCHAIN_PATH" "$APP"
codesign --verify --verbose=2 "$APP"

echo "→ 送 Apple 公证…"
ZIP="$TMP/FinalMd-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
  --apple-id "$NOTARIZE_APPLE_ID" \
  --team-id "$NOTARIZE_TEAM_ID" \
  --password "$NOTARIZE_PASSWORD" \
  --wait

echo "→ 装订公证票据…"
xcrun stapler staple "$APP"
spctl -a -vvv -t exec "$APP" || true

# 清理临时 keychain
security delete-keychain "$KEYCHAIN_PATH" || true

echo "✅ 签名并公证完成：$APP"
