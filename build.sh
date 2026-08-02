#!/bin/sh
# 一键构建：编译 → 打 App → 生成 pkg 与 dmg（产物在 dist/）
set -e
cd "$(dirname "$0")"
VER="${1:-1.0.0}"
B=build; rm -rf $B dist; mkdir -p $B dist

echo "[1/4] 编译 Swift 与 usbreset..."
swiftc -O -parse-as-library -o $B/LTEGuard src/LTEGuard.swift -framework Cocoa -framework IOKit
clang -o $B/usbreset src/usbreset.c -framework IOKit -framework CoreFoundation

echo "[2/4] 生成图标..."
rm -rf $B/icon.iconset; mkdir -p $B/icon.iconset
if command -v rsvg-convert >/dev/null; then
  for s in 16 32 128 256 512; do
    rsvg-convert -w $s -h $s src/icon.svg -o $B/icon.iconset/icon_${s}x${s}.png
    rsvg-convert -w $((s*2)) -h $((s*2)) src/icon.svg -o $B/icon.iconset/icon_${s}x${s}@2x.png
  done
  iconutil -c icns $B/icon.iconset -o $B/AppIcon.icns
else
  echo "  (未装 librsvg，跳过图标：brew install librsvg)"
fi

echo "[3/4] 组装 App..."
APP=$B/LTEGuard.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp $B/LTEGuard "$APP/Contents/MacOS/"
cp $B/usbreset "$APP/Contents/Resources/"
cp -R lang "$APP/Contents/Resources/lang"
[ -f $B/AppIcon.icns ] && cp $B/AppIcon.icns "$APP/Contents/Resources/"
sed "s/__VERSION__/$VER/g" packaging/Info.plist > "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"

echo "[4/4] 打包 pkg / dmg..."
rm -rf $B/pkgroot && mkdir -p $B/pkgroot/Applications && cp -R "$APP" $B/pkgroot/Applications/
pkgbuild --root $B/pkgroot --scripts packaging/scripts --identifier com.oceantang.lteguard \
         --version "$VER" --install-location / "dist/LTEGuard-$VER.pkg" >/dev/null
rm -rf $B/dmgroot && mkdir $B/dmgroot && cp -R "$APP" $B/dmgroot/ && ln -s /Applications $B/dmgroot/Applications
hdiutil create -volname "LTE Guard" -srcfolder $B/dmgroot -ov -format UDZO "dist/LTEGuard-$VER.dmg" >/dev/null

echo "完成 → dist/LTEGuard-$VER.pkg  dist/LTEGuard-$VER.dmg"
