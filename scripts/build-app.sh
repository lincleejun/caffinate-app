#!/bin/bash
# 构建 Caffinate.app（无需 Xcode，仅需 Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/Caffinate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Caffinate "$APP/Contents/MacOS/Caffinate"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.lijun.caffinate</string>
    <key>CFBundleName</key>
    <string>Caffinate</string>
    <key>CFBundleDisplayName</key>
    <string>Caffinate</string>
    <key>CFBundleExecutable</key>
    <string>Caffinate</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

cp .build/release/caf dist/caf

# 优先用本机固定证书（scripts/setup-signing.sh 配置），重建不丢 TCC 授权；否则回退 ad-hoc
IDENTITY="Caffinate Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "⚠️ 未配置本机签名证书（可运行 scripts/setup-signing.sh），使用 ad-hoc 签名"
    codesign --force --sign - "$APP"
fi
echo "✅ 已生成 $APP 与 dist/caf"
echo "   安装 App：cp -R $APP /Applications/"
echo "   安装 CLI：sudo cp dist/caf /usr/local/bin/"
