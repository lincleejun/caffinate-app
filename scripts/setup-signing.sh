#!/bin/bash
# 一次性配置：创建本机自签名代码签名证书并信任之。
# 之后 build-app.sh 用固定身份签名，重建不再丢失辅助功能等 TCC 授权。
set -euo pipefail

IDENTITY="Caffinate Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✅ 证书已存在：$IDENTITY（无需重复配置）"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE" 2>/dev/null

# -legacy：macOS security import 不支持 OpenSSL 3 默认的新式 p12 加密
openssl pkcs12 -export -legacy -out "$TMP/identity.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:caffinate

# 导入 login keychain，并预授权 codesign 使用该私钥
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P caffinate -T /usr/bin/codesign

# 信任该证书用于代码签名（系统会弹密码框，输入登录密码确认，仅此一次）
echo "→ 即将弹出系统对话框：请输入登录密码以信任该证书"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "✅ 已创建并信任：$IDENTITY"
security find-identity -v -p codesigning | grep "$IDENTITY"
