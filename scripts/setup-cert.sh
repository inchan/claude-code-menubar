#!/usr/bin/env bash
# Self-signed Code Signing 인증서 1회 생성.
# stable codesign identity → Keychain ACL 영구 trust → 빌드마다 prompt 회피.
set -euo pipefail

SIGN_NAME="${SIGN_NAME:-Claude Code Menubar Dev}"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_NAME\""; then
    echo ">> 이미 '$SIGN_NAME' 인증서가 존재합니다 — 추가 작업 불필요"
    exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

echo ">> openssl 로 self-signed 인증서 생성 …"
openssl req -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" \
    -x509 -days 3650 -out "$TMP/cert.pem" \
    -subj "/CN=$SIGN_NAME"

echo ">> pkcs12 패키징 …"
openssl pkcs12 -export -legacy \
    -in "$TMP/cert.pem" -inkey "$TMP/key.pem" \
    -out "$TMP/cert.p12" -name "$SIGN_NAME" -password pass:

echo ">> Keychain import …"
security import "$TMP/cert.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -T /usr/bin/codesign -P ""

echo ""
echo ">> 1차 검증:"
if security find-identity -v -p codesigning | grep -q "\"$SIGN_NAME\""; then
    echo "   ✓ codesigning identity 등록 확인"
else
    echo "   ✗ identity 미등록 — Keychain Access 에서 'Code Signing' Trust 를 'Always Trust' 로 변경 필요"
fi

echo ""
echo ">> 추가 작업 (1회):"
echo "   1. Keychain Access 앱 실행"
echo "   2. '내 인증서' 또는 '로그인' 키체인에서 '$SIGN_NAME' 더블클릭"
echo "   3. '신뢰' 항목 펼침 → '코드 서명' 을 '항상 신뢰' 로 변경 + 창 닫기 (KC pwd 입력)"
echo "   4. 'make app' — 첫 빌드 후 Keychain prompt 1회만 (Always Allow 클릭)"
