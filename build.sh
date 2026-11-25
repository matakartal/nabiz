#!/bin/bash
# Builds Nabız.
#
#   ./build.sh              build/Nabiz.app (universal: Apple silicon + Intel)
#   ./build.sh install      … and copy it to ~/Applications, then open it
#   ./build.sh dmg          … and package build/Nabiz-<version>.dmg
#
# Signing: ad-hoc by default (runs on this Mac). For a release others can open without warnings, set
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="nabiz"   # created once with: xcrun notarytool store-credentials nabiz
# and run ./build.sh dmg — the app and the DMG are signed with the hardened runtime and notarized.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
APP="build/Nabiz.app"
IDENTITY="${SIGN_IDENTITY:--}"

# Universal when both slices build; on a toolchain without the Intel SDK, the native slice alone.
if swift build -c release --product Nabiz --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Nabiz"
else
    swift build -c release --product Nabiz
    BIN="$(swift build -c release --show-bin-path)/Nabiz"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Nabiz"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP" >/dev/null
else
    codesign --force --options runtime --timestamp --entitlements Nabiz.entitlements --sign "$IDENTITY" "$APP"
fi
echo "Built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/Nabiz"))"

case "${1:-}" in
install)
    mkdir -p "$HOME/Applications"
    pkill -x Nabiz 2>/dev/null || true
    sleep 0.5
    rm -rf "$HOME/Applications/Nabiz.app"
    cp -R "$APP" "$HOME/Applications/Nabiz.app"
    open "$HOME/Applications/Nabiz.app"
    echo "Installed to ~/Applications/Nabiz.app"
    ;;
dmg)
    DMG="build/Nabiz-$VERSION.dmg"
    STAGE="build/dmg"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "Nabız $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    if [[ "$IDENTITY" != "-" ]]; then
        codesign --force --timestamp --sign "$IDENTITY" "$DMG"
        if [[ -n "${NOTARY_PROFILE:-}" ]]; then
            xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
            xcrun stapler staple "$DMG"
        fi
    fi
    echo "Packaged $DMG"
    ;;
esac
