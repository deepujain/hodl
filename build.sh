#!/bin/bash
# Builds HODL.app into ./build, signed ad hoc for local use.
# Release builds are universal (Apple silicon and Intel); debug builds are for this Mac only.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/HODL.app"
CONFIG="${1:-release}"

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" build/bin

# Both architectures build into the same folder, so keep each binary as it is built.
swift build -c "$CONFIG" --product HODL
BIN=build/bin/HODL-native
cp "$(swift build -c "$CONFIG" --show-bin-path)/HODL" "$BIN"
if [ "$CONFIG" = release ]; then
  INTEL=x86_64-apple-macosx14.0
  swift build -c release --product HODL --triple "$INTEL"
  cp "$(swift build -c release --triple "$INTEL" --show-bin-path)/HODL" build/bin/HODL-x86_64
  lipo -create "$BIN" build/bin/HODL-x86_64 -output "$APP/Contents/MacOS/HODL"
else
  cp "$BIN" "$APP/Contents/MacOS/HODL"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp Resources/IconPhoto.jpg "$APP/Contents/Resources/IconPhoto.jpg"
for tool in hodl hodl-run hodl-hook; do
  install -m 0755 "Scripts/$tool" "$APP/Contents/Resources/bin/$tool"
done

"$BIN" --render-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# No App Sandbox: HODL needs to read process names, run pmset, and pause chat apps.
codesign --force --sign - --options runtime --timestamp=none "$APP"
echo "Built $APP"
