#!/bin/zsh
# Cut a release: build arm64 release, ad-hoc sign, package a DMG, tag, and publish a GitHub Release.
# Usage: script/release.sh vX.Y.Z
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:-}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: script/release.sh vX.Y.Z" >&2; exit 2; }
VERSION="${TAG#v}"

[ -z "$(git status --porcelain)" ] || { echo "working tree is dirty; commit first" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "tag $TAG already exists" >&2; exit 1; }
grep -q "^## \[$VERSION\]" CHANGELOG.md || { echo "CHANGELOG.md has no ## [$VERSION] section" >&2; exit 1; }

swift test
VERSION="$VERSION" script/build.sh release

DMG="build/Headroom-$VERSION.dmg"
STAGE="build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Headroom.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Headroom" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
shasum -a 256 "$DMG" | tee "$DMG.sha256"

# Release notes are this version's CHANGELOG section.
NOTES="$(awk -v v="$VERSION" '
  /^## \[/ { if (found) exit; found = ($0 ~ "^## \\[" v "\\]"); next }
  found { print }
' CHANGELOG.md)"

git tag -a "$TAG" -m "Headroom $TAG"
git push origin "$TAG"
gh release create "$TAG" "$DMG" "$DMG.sha256" --title "Headroom $TAG" --notes "$NOTES"
echo "Released $TAG"
