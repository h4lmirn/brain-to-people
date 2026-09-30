#!/bin/bash
# Brain-to-People.app を組み立てる。
# 使い方: scripts/build-app.sh [--install] [--dmg]
#   --install  ~/Applications に置く
#   --dmg      他の Mac に配るためのディスクイメージを dist/ に作る
# Xcode があれば Intel と Apple シリコンの両方で動く形（ユニバーサル）でビルドする。
# Command Line Tools だけのときは、この Mac の種類向けだけになる。
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0; DMG=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --dmg) DMG=1 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

VERSION=1.1
BUILD_NUMBER=2
XCODE_DEV=/Applications/Xcode.app/Contents/Developer
if DEVELOPER_DIR=$XCODE_DEV xcrun actool --version >/dev/null 2>&1; then
    HAS_XCODE=1
    export DEVELOPER_DIR=$XCODE_DEV
    ARCHS=(--arch arm64 --arch x86_64)
else
    HAS_XCODE=0
    ARCHS=()
    echo "note: Xcode が使えないため、この Mac の種類向けだけにビルドします"
fi

# SwiftPM が起動できない環境では、対応する SDK を明示して直接コンパイルする。
if [[ -n ${B2P_DIRECT_SDK:-} ]]; then
    DIRECT_OUT="$PWD/build/direct"
    mkdir -p "$DIRECT_OUT/module-cache"
    FLAGS=(-sdk "$B2P_DIRECT_SDK" -target "$(uname -m)-apple-macosx14.0"
           -module-cache-path "$DIRECT_OUT/module-cache" -O)
    swiftc "${FLAGS[@]}" -emit-library -static -emit-module -module-name B2PCore \
        Sources/B2PCore/*.swift -o "$DIRECT_OUT/libB2PCore.a" \
        -emit-module-path "$DIRECT_OUT/B2PCore.swiftmodule"
    swiftc "${FLAGS[@]}" -parse-as-library -module-name B2P \
        -I "$DIRECT_OUT" -L "$DIRECT_OUT" -lB2PCore Sources/B2P/*.swift -o "$DIRECT_OUT/B2P"
    BIN="$DIRECT_OUT/B2P"
else
    swift build -c release --product B2P ${ARCHS[@]+"${ARCHS[@]}"}
    BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/B2P"
fi

APP="build/Brain-to-People.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/B2P"

# ビルド環境によらず、共通の黒いマークを使う。
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

sed -e 's/$(EXECUTABLE_NAME)/B2P/' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.changsama.B2P/' \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/" \
    -e 's/$(MACOSX_DEPLOYMENT_TARGET)/14.0/' \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# アドホック署名（Apple Developer Program の署名がないため）
codesign --force --deep --sign - "$APP"
BINARY_ARCHS="$(lipo -archs "$APP/Contents/MacOS/B2P")"
if [[ "$BINARY_ARCHS" == *arm64* && "$BINARY_ARCHS" == *x86_64* ]]; then
    ARCH_LABEL=universal
else
    ARCH_LABEL="$BINARY_ARCHS"
fi
echo "built: $APP ($BINARY_ARCHS)"

if [[ $INSTALL == 1 ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Brain-to-People.app
    cp -R "$APP" ~/Applications/
    echo "installed: ~/Applications/Brain-to-People.app"
fi

if [[ $DMG == 1 ]]; then
    STAGE="build/dmg"
    rm -rf "$STAGE"
    mkdir -p "$STAGE" dist
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    cp Resources/はじめにお読みください.txt "$STAGE/"
    OUT="dist/Brain-to-People-$VERSION-$ARCH_LABEL.dmg"
    rm -f "$OUT"
    hdiutil create -volname "Brain-to-People" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
    echo "dmg: $OUT ($(du -h "$OUT" | cut -f1))"
fi
