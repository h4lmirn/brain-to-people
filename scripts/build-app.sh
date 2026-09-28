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

VERSION=1.0
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

swift build -c release --product B2P ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/B2P"

APP="build/Brain-to-People.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/B2P"

# アイコン: Xcode があれば Icon Composer 形式（.icon）から Liquid Glass のアイコンを作る。
# なければ、前回作った AppIcon.icns をそのまま使う。
if [[ $HAS_XCODE == 1 ]]; then
    xcrun actool Resources/AppIcon.icon \
        --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 \
        --app-icon AppIcon --output-partial-info-plist build/icon-partial.plist >/dev/null
    cp "$APP/Contents/Resources/AppIcon.icns" Resources/AppIcon.icns
else
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

sed -e 's/$(EXECUTABLE_NAME)/B2P/' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.changsama.B2P/' \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e 's/$(CURRENT_PROJECT_VERSION)/1/' \
    -e 's/$(MACOSX_DEPLOYMENT_TARGET)/14.0/' \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# アドホック署名（Apple Developer Program の署名がないため）
codesign --force --deep --sign - "$APP"
echo "built: $APP ($(lipo -archs "$APP/Contents/MacOS/B2P"))"

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
    OUT="dist/Brain-to-People-$VERSION.dmg"
    rm -f "$OUT"
    hdiutil create -volname "Brain-to-People" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
    echo "dmg: $OUT ($(du -h "$OUT" | cut -f1))"
fi
