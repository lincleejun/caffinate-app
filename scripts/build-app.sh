#!/bin/bash
# 构建 Caffinate.app（无需 Xcode，仅需 Command Line Tools）。
#
# 内嵌 Sparkle.framework 以支持自动更新。更新包用自生成的 EdDSA 密钥签名，
# 不依赖 Apple Developer 证书——分发仍是 ad-hoc/未签名，首次打开需右键。
#
# 版本号（Sparkle 据此判断「有没有新版」）：
#   CFBundleVersion        = git commit 数（单调递增，作为 Sparkle 比较键）
#   CFBundleShortVersionString = git describe（展示用，带 tag 与领先提交数）
#
# 可用环境变量覆盖默认值（CI 与 fork 用）：
#   SU_FEED_URL       appcast.xml 地址（默认指向 release-latest 滚动预发布）
#   SU_PUBLIC_ED_KEY  Sparkle EdDSA 公钥（与 CI 私钥配对）
set -euo pipefail
cd "$(dirname "$0")/.."

# ---- 自动更新配置（公钥可安全入库；私钥只在 GitHub Secret 里）----
SU_FEED_URL="${SU_FEED_URL:-https://github.com/lincleejun/caffinate-app/releases/download/release-latest/appcast.xml}"
SU_PUBLIC_ED_KEY="${SU_PUBLIC_ED_KEY:-bzbmCcjtB+lV0qzEfUoB/+Zvly26N+vrpYcuM6t9+b0=}"

# ---- 版本派生 ----
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
# --match 'v*'：只认 vX.Y.Z 版本 tag，忽略 workflow 自己打的滚动 tag
# release-latest（否则 describe 自我引用，版本号变成 release-latest-N-g…）。
SHORT_VERSION="$(git describe --tags --always --dirty --match 'v*' 2>/dev/null | sed 's/^v//')"
[ -n "$SHORT_VERSION" ] || SHORT_VERSION="0.0.0"
echo "→ 版本：short=$SHORT_VERSION  build=$BUILD_NUMBER"

swift build -c release

APP=dist/Caffinate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/Caffinate "$APP/Contents/MacOS/Caffinate"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 语言包（随系统切换，开发语言 en 兜底）
for lproj in Resources/*.lproj; do
    cp -R "$lproj" "$APP/Contents/Resources/"
done

# ---- 内嵌 Sparkle.framework ----
# swift build 把 Sparkle.framework 拷到 .build/release/；放进 Contents/Frameworks/，
# 并给主程序加 @executable_path/../Frameworks 的 rpath（它链接的是
# @rpath/Sparkle.framework/Versions/B/Sparkle）。cp -R 保留 framework 的符号链接结构。
cp -R .build/release/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Caffinate"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.lijun.caffinate</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
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
    <string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>SUFeedURL</key>
    <string>${SU_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SU_PUBLIC_ED_KEY}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
</dict>
</plist>
EOF

cp .build/release/caf dist/caf

# ---- 签名 ----
# 必须用 --deep（inside-out）：Sparkle.framework 内含已签名的 XPCServices 与
# Updater.app，外层重签时要把嵌套代码一并重签，否则签名团队不一致会被系统拒。
# 优先用本机固定证书（scripts/setup-signing.sh 配置），重建不丢 TCC 授权；否则回退 ad-hoc。
IDENTITY="Caffinate Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "⚠️ 未配置本机签名证书（可运行 scripts/setup-signing.sh），使用 ad-hoc 签名"
    codesign --force --deep --sign - "$APP"
fi

# 校验签名完整（含嵌套 Sparkle 代码）
codesign --verify --deep --strict "$APP"

echo "✅ 已生成 $APP 与 dist/caf"
echo "   安装 App：cp -R $APP /Applications/"
echo "   安装 CLI：sudo cp dist/caf /usr/local/bin/"
