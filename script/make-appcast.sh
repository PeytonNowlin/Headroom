#!/bin/zsh
# Generate signed update metadata without publishing. The private key is read from
# Keychain, or from SPARKLE_ED_KEY when set (the CI release workflow).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: script/make-appcast.sh X.Y.Z}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid release version" >&2; exit 2; }
ARCHIVES="$(mktemp -d "$PWD/build/appcast.XXXXXX")"
trap 'rm -rf "$ARCHIVES"' EXIT
cp "build/Headroom-$VERSION.dmg" "$ARCHIVES/"
if [[ -f "build/Headroom-$VERSION-notes.md" ]]; then
  cp "build/Headroom-$VERSION-notes.md" "$ARCHIVES/Headroom-$VERSION.md"
fi

sparkle() {
  local tool=".build/artifacts/sparkle/Sparkle/bin/$1"; shift
  if [[ -n "${SPARKLE_ED_KEY:-}" ]]; then
    print -r -- "$SPARKLE_ED_KEY" | "$tool" --ed-key-file - "$@"
  else
    "$tool" --account io.github.peytonnowlin.Headroom "$@"
  fi
}

sparkle generate_appcast \
  --download-url-prefix "https://github.com/PeytonNowlin/Headroom/releases/download/v$VERSION/" \
  --link "https://github.com/PeytonNowlin/Headroom/releases/tag/v$VERSION" \
  --maximum-deltas 0 --embed-release-notes \
  -o "$ARCHIVES/appcast.xml" "$ARCHIVES"
sparkle sign_update --verify "$ARCHIVES/appcast.xml"
cp "$ARCHIVES/appcast.xml" build/appcast.xml
