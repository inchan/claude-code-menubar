#!/usr/bin/env bash
# 첫 매칭 codesigning identity 이름 출력. 없으면 빈 문자열.
NAME="${1:-}"
if [ -n "$NAME" ]; then
    security find-identity -v -p codesigning 2>/dev/null \
        | grep -m1 "\"$NAME\"" | awk -F'"' '{print $2}'
else
    security find-identity -v -p codesigning 2>/dev/null \
        | grep -m1 -E '^[[:space:]]*[0-9]+\)' | awk -F'"' '{print $2}'
fi
