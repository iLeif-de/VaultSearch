#!/bin/zsh
# Renders Design/AppIcon.svg into all formats and updates the Xcode asset catalog.
# Requires: rsvg-convert (brew install librsvg), magick (brew install imagemagick), iconutil (macOS).
set -euo pipefail

cd "${0:A:h}"
SVG=AppIcon.svg
OUT=Export
ASSET=../VaultSearch/Assets.xcassets/AppIcon.appiconset

rm -rf "$OUT"
mkdir -p "$OUT/png" "$OUT/VaultSearch.iconset"

# Vector
cp "$SVG" "$OUT/VaultSearch.svg"
rsvg-convert -f pdf "$SVG" -o "$OUT/VaultSearch.pdf"

# PNG in all common sizes
for size in 16 32 48 64 128 256 512 1024; do
  rsvg-convert -w $size -h $size "$SVG" -o "$OUT/png/VaultSearch-$size.png"
done

# macOS .icns
for size in 16 32 128 256 512; do
  cp "$OUT/png/VaultSearch-$size.png" "$OUT/VaultSearch.iconset/icon_${size}x${size}.png"
  double=$((size * 2))
  [[ -f "$OUT/png/VaultSearch-$double.png" ]] || rsvg-convert -w $double -h $double "$SVG" -o "$OUT/png/VaultSearch-$double.png"
  cp "$OUT/png/VaultSearch-$double.png" "$OUT/VaultSearch.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$OUT/VaultSearch.iconset" -o "$OUT/VaultSearch.icns"
rm -rf "$OUT/VaultSearch.iconset"

# Windows / web
magick "$OUT/png/VaultSearch-16.png" "$OUT/png/VaultSearch-32.png" "$OUT/png/VaultSearch-48.png" \
       "$OUT/png/VaultSearch-64.png" "$OUT/png/VaultSearch-256.png" "$OUT/VaultSearch.ico"

# Xcode asset catalog (file names as referenced by Contents.json)
for size in 16 32 64 128 256 512 1024; do
  cp "$OUT/png/VaultSearch-$size.png" "$ASSET/icon_$size.png"
done

echo "Exported to Design/$OUT and updated the AppIcon asset catalog."
