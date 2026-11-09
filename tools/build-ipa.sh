#!/usr/bin/env bash
# Unsigned .ipa of the app, attached to the GitHub releases for side-loading (AltStore, SideStore or any tool that
# signs it with the tester's own Apple ID). iOS never installs an unsigned app as is: the App Store and TestFlight
# builds are archived and signed in Xcode (see docs/RELEASING.md).
#
#   tools/build-ipa.sh        # -> build/ipa/humbleplanning-<version>-unsigned.ipa and its .sha256
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/ipa
rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild -project HumblePlanning.xcodeproj -scheme HumblePlanning -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$OUT/derived" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -quiet build

APP=$(find "$OUT/derived/Build/Products/Release-iphoneos" -maxdepth 1 -name '*.app' | head -n 1)
[ -n "$APP" ] || { echo "no .app built" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
NAME="humbleplanning-$VERSION-unsigned.ipa"

mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
(cd "$OUT" && zip -qry "$NAME" Payload && shasum -a 256 "$NAME" >"$NAME.sha256")
rm -rf "$OUT/Payload" "$OUT/derived"
echo "$OUT/$NAME"
