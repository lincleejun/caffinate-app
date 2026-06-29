#!/bin/bash
# 生成并签名 Sparkle appcast.xml。
#
# 用法：scripts/make-appcast.sh <staging-dir> <download-url-prefix>
#   <staging-dir>          含待发布 .zip 的目录；appcast.xml 写到同目录
#   <download-url-prefix>  enclosure 下载地址前缀（结尾带 /）
#
# 私钥从环境变量 SPARKLE_ED_PRIVATE_KEY 读取（GitHub Secret 注入）；
# 本地调试时若未设该变量，则回退用 keychain 里的 caffinate 账号密钥。
set -euo pipefail
cd "$(dirname "$0")/.."

DIR="${1:?用法: make-appcast.sh <staging-dir> <download-url-prefix>}"
PREFIX="${2:?缺少 download-url-prefix}"

GA="$(find .build/artifacts -path '*Sparkle/bin/generate_appcast' -type f 2>/dev/null | head -1)"
if [ -z "$GA" ]; then
    echo "❌ 找不到 generate_appcast（先跑一次 swift build 让 SPM 下载 Sparkle 工件）" >&2
    exit 1
fi

if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    # CI：私钥来自 Secret，写到受限临时文件，用完即删
    KEYFILE="$(mktemp)"
    chmod 600 "$KEYFILE"
    trap 'rm -f "$KEYFILE"' EXIT
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$KEYFILE"
    "$GA" --ed-key-file "$KEYFILE" --download-url-prefix "$PREFIX" "$DIR"
else
    # 本地：用 keychain 中 caffinate 账号的私钥
    echo "ℹ️ 未设 SPARKLE_ED_PRIVATE_KEY，改用 keychain(caffinate 账号)签名"
    "$GA" --account caffinate --download-url-prefix "$PREFIX" "$DIR"
fi

echo "✅ 已生成 $DIR/appcast.xml"
