#!/bin/zsh
# Renders Pip's app icon and packs it into Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
swift run -q Pip --snapshot $TMP/render >/dev/null
SET=$TMP/AppIcon.iconset
mkdir -p $SET
for size in 16 32 128 256 512; do
    sips -z $size $size $TMP/render/AppIcon.png --out $SET/icon_${size}x${size}.png >/dev/null
    sips -z $((size * 2)) $((size * 2)) $TMP/render/AppIcon.png --out $SET/icon_${size}x${size}@2x.png >/dev/null
done
iconutil -c icns $SET -o Resources/AppIcon.icns
rm -rf $TMP
echo "Wrote Resources/AppIcon.icns"
