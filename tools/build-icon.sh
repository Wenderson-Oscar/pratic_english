#!/bin/bash
#
# Gera App/Icon.icns (macOS app icon) e assets/icon.png (256px para o README)
# a partir do renderizador Swift em tools/make-icon.swift.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ICONSET="$(mktemp -d)/Icon.iconset"
mkdir -p "$ICONSET"
mkdir -p App assets

echo "▸ Renderizando 1024×1024..."
swift tools/make-icon.swift "$ICONSET/icon_512x512@2x.png"

echo "▸ Gerando demais resoluções..."
declare -a SIZES=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
)
for entry in "${SIZES[@]}"; do
    size="${entry%%:*}"
    name="${entry##*:}"
    sips -z "$size" "$size" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/$name" >/dev/null
done

echo "▸ Empacotando .icns..."
iconutil -c icns "$ICONSET" -o "App/Icon.icns"

echo "▸ Copiando 256×256 para assets/icon.png..."
cp "$ICONSET/icon_256x256.png" "assets/icon.png"

rm -rf "$(dirname "$ICONSET")"

echo "✓ App/Icon.icns ($(stat -f%z App/Icon.icns) bytes)"
echo "✓ assets/icon.png ($(stat -f%z assets/icon.png) bytes)"
