#!/usr/bin/env bash
# build-icon.sh — Resources/AppIcon.svg → build/AppIcon.icns
# 의존: rsvg-convert (brew install librsvg), iconutil, sips

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SVG="$ROOT/Resources/AppIcon.svg"
OUT_DIR="$ROOT/build"
ICONSET="$OUT_DIR/AppIcon.iconset"
ICNS="$OUT_DIR/AppIcon.icns"

if [ ! -f "$SRC_SVG" ]; then
  echo "ERR: $SRC_SVG not found" >&2
  exit 1
fi

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "ERR: rsvg-convert 필요. 'brew install librsvg'" >&2
  exit 1
fi

mkdir -p "$ICONSET"
echo ">> Render PNGs from $SRC_SVG"

# macOS .icns 표준 슬롯: 16, 32, 64, 128, 256, 512, 1024
declare -a sizes=(16 32 64 128 256 512 1024)
for s in "${sizes[@]}"; do
  rsvg-convert -w "$s" -h "$s" "$SRC_SVG" -o "$ICONSET/icon_${s}x${s}.png"
done

# iconutil 명명 규약 (@2x 매핑)
mv "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_16x16@2x.png"  "$ICONSET/icon_16x16.png" 2>/dev/null || \
  rsvg-convert -w 16  -h 16  "$SRC_SVG" -o "$ICONSET/icon_16x16.png"

mv "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
rsvg-convert -w 32  -h 32  "$SRC_SVG" -o "$ICONSET/icon_32x32.png"

# 128
cp "$ICONSET/icon_128x128.png" "$ICONSET/icon_128x128@1x.tmp" 2>/dev/null || true
rsvg-convert -w 256 -h 256 "$SRC_SVG" -o "$ICONSET/icon_128x128@2x.png"
rsvg-convert -w 128 -h 128 "$SRC_SVG" -o "$ICONSET/icon_128x128.png"

# 256
rsvg-convert -w 512 -h 512 "$SRC_SVG" -o "$ICONSET/icon_256x256@2x.png"
rsvg-convert -w 256 -h 256 "$SRC_SVG" -o "$ICONSET/icon_256x256.png"

# 512
rsvg-convert -w 1024 -h 1024 "$SRC_SVG" -o "$ICONSET/icon_512x512@2x.png"
rsvg-convert -w 512  -h 512  "$SRC_SVG" -o "$ICONSET/icon_512x512.png"

# 정리 — 표준 슬롯만 남기기
rm -f "$ICONSET/icon_1024x1024.png" "$ICONSET"/*.tmp 2>/dev/null || true

echo ">> iconutil → $ICNS"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo ">> Done: $ICNS"
ls -la "$ICNS"
