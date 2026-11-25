#!/bin/bash
# One-command release: signs with your Developer ID, notarizes, staples, and publishes the DMG on GitHub.
#
#   ./release.sh              build, sign, notarize and staple build/Nabiz-<version>.dmg
#   ./release.sh publish      … and create the GitHub release v<version> with notes from CHANGELOG.md
#
# Once per Mac, store the notary credentials for the same team (Apple ID + app-specific password, or an API key):
#   xcrun notarytool store-credentials nabiz --team-id 3Q2LK426HF
set -euo pipefail
cd "$(dirname "$0")"

# Releases are signed by Finqt Veri Hizmetleri (team 3Q2LK426HF, the team Sincerus ships with). Override with SIGN_TEAM.
TEAM="${SIGN_TEAM:-3Q2LK426HF}"   # FINQT VERI HIZMETLERI SANAYI VE TICARET LTD. STI.
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep -m1 -i "$TEAM" | sed -E 's/.*"(.*)"/\1/' || true)
if [[ -z "$IDENTITY" ]]; then
    echo "No 'Developer ID Application' certificate for \"$TEAM\" in this keychain. Found:" >&2
    security find-identity -v -p codesigning | grep "Developer ID Application" | sed -E 's/.*"(.*)"/  \1/' >&2 || true
    echo "Create it as the team's Account Holder or Admin: Xcode → Settings → Accounts → (team) → Manage Certificates → + → Developer ID Application." >&2
    exit 1
fi
echo "Signing as: $IDENTITY"
if ! xcrun notarytool history --keychain-profile nabiz >/dev/null 2>&1; then
    echo "No notary profile yet. Run once:  xcrun notarytool store-credentials nabiz" >&2
    exit 1
fi

SIGN_IDENTITY="$IDENTITY" NOTARY_PROFILE=nabiz ./build.sh dmg
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
DMG="build/Nabiz-$VERSION.dmg"
spctl --assess --type open --context context:primary-signature -v "$DMG"

if [[ "${1:-}" == "publish" ]]; then
    NOTES=$(mktemp)
    awk -v v="## $VERSION" '$0==v{f=1;next} /^## /{f=0} f' CHANGELOG.md > "$NOTES"
    gh release create "v$VERSION" "$DMG" --title "Nabız $VERSION" --notes-file "$NOTES" --target main
    rm -f "$NOTES"
fi
