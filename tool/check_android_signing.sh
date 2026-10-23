#!/usr/bin/env bash
# 既存のアップロード鍵を読み、ビルド前に秘密鍵とパスワードを検証する。
# 鍵を作成・変更せず、秘密値をログやkey.propertiesに書かない。
set -euo pipefail
for name in CM_KEYSTORE_PATH CM_KEYSTORE_PASSWORD CM_KEY_ALIAS CM_KEY_PASSWORD; do
  [ -n "${!name:-}" ] || { echo "Missing Android signing variable: $name" >&2; exit 1; }
done
test -f "$CM_KEYSTORE_PATH" || { echo "Android keystore file not found" >&2; exit 1; }

# keytoolはPKCS12のkeyPasswordを無視する場合があるため、Gradleと同様に
# KeyStore.getKeyで秘密鍵を読み出し、実際の鍵パスワードを検証する。
java "$(dirname "$0")/CheckAndroidSigning.java"
