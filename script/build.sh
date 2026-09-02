#!/bin/zsh
# Build Headroom.app into ./build. Usage: script/build.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

swift build -c "$CONFIG" --arch arm64
BIN=".build/arm64-apple-macosx/$CONFIG"
APP="build/Headroom.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Headroom" "$APP/Contents/MacOS/Headroom"
for bundle in "$BIN"/*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" script/Info.plist > "$APP/Contents/Info.plist"
[ -f script/Headroom.icns ] && cp script/Headroom.icns "$APP/Contents/Resources/Headroom.icns"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($CONFIG, v$VERSION build $BUILD_NUMBER)"
