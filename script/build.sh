#!/bin/zsh
# Build Headroom.app into ./build. Usage: script/build.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

case "$CONFIG" in
  debug) XCODE_CONFIG="Debug" ;;
  release) XCODE_CONFIG="Release" ;;
  *) echo "usage: script/build.sh [debug|release]" >&2; exit 2 ;;
esac

# Xcode's SwiftPM integration generates app-aware Bundle.module accessors that
# search Contents/Resources. The native SwiftPM build generates command-line
# accessors with an absolute local-build fallback, which breaks distributed apps.
swift build -c "$CONFIG" --arch arm64 --build-system xcode
BIN=".build/apple/Products/$XCODE_CONFIG"
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
script/verify-app.sh "$APP"
echo "Built $APP ($CONFIG, v$VERSION build $BUILD_NUMBER)"
