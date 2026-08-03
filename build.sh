#!/bin/sh
# 一键构建：编译 → 打 App → 生成 pkg 与 dmg（产物在 dist/）
set -e
cd "$(dirname "$0")"
VER="${1:-1.0.0}"
B=build; rm -rf $B dist; mkdir -p $B dist
touch $B/.metadata_never_index   # 防止中间产物被 Spotlight 收录

echo "[1/4] 编译 Swift 与 usbreset（通用二进制 arm64+x86_64，最低 macOS 10.15）..."
MACOS_MIN="10.15"
# 三个编译互相独立，并行跑；lipo 只等两个 swiftc（wait $pid 保留失败退出码）
SWIFT_FLAGS="-O -parse-as-library"
swiftc $SWIFT_FLAGS -target arm64-apple-macos$MACOS_MIN \
  -o $B/LTEGuard.arm64 src/LTEGuard.swift -framework Cocoa -framework IOKit & P_ARM=$!
swiftc $SWIFT_FLAGS -target x86_64-apple-macos$MACOS_MIN \
  -o $B/LTEGuard.x86_64 src/LTEGuard.swift -framework Cocoa -framework IOKit & P_X86=$!
clang -arch arm64 -arch x86_64 -mmacosx-version-min=$MACOS_MIN \
  -o $B/usbreset src/usbreset.c -framework IOKit -framework CoreFoundation & P_CLANG=$!
wait $P_ARM; wait $P_X86
lipo -create -output $B/LTEGuard $B/LTEGuard.arm64 $B/LTEGuard.x86_64
rm $B/LTEGuard.arm64 $B/LTEGuard.x86_64
wait $P_CLANG

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
         --version "$VER" --install-location / "$B/component.pkg" >/dev/null
# productbuild 包装：安装器显示免责声明（继续安装即同意）
sed "s/__VERSION__/$VER/g" packaging/distribution.xml > $B/distribution.xml
cp packaging/install-license.txt $B/
productbuild --distribution $B/distribution.xml --package-path $B --resources $B \
             "dist/LTEGuard-$VER.pkg" >/dev/null
rm -rf $B/dmgroot && mkdir $B/dmgroot && cp -R "$APP" $B/dmgroot/ && ln -s /Applications $B/dmgroot/Applications
hdiutil create -volname "LTE Guard" -srcfolder $B/dmgroot -ov -format UDZO "dist/LTEGuard-$VER.dmg" >/dev/null

# 清理中间产物（避免 Spotlight 里出现多个同名 App）
rm -rf $B

echo "完成 → dist/LTEGuard-$VER.pkg  dist/LTEGuard-$VER.dmg"
