#!/bin/zsh
# Verify that a packaged Headroom.app is complete and correctly signed.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="${1:-build/Headroom.app}"

[[ -x "$APP/Contents/MacOS/Headroom" ]] || {
  echo "missing executable: $APP/Contents/MacOS/Headroom" >&2
  exit 1
}

for bundle in Headroom_HeadroomCore.bundle KeyboardShortcuts_KeyboardShortcuts.bundle; do
  [[ -d "$APP/Contents/Resources/$bundle" ]] || {
    echo "missing SwiftPM resource bundle: $APP/Contents/Resources/$bundle" >&2
    exit 1
  }
done

[[ -f "$APP/Contents/Resources/Headroom_HeadroomCore.bundle/Contents/Resources/pricing.json" ]] || {
  echo "missing bundled pricing data" >&2
  exit 1
}

# Native SwiftPM builds bake the developer's absolute .build path into the
# resource accessor. Such an app appears healthy only on the build machine.
if strings "$APP/Contents/MacOS/Headroom" | grep -Fq "$PWD/.build"; then
  echo "executable contains a local SwiftPM build-path fallback" >&2
  exit 1
fi

[[ -x "$APP/Contents/Frameworks/Sparkle.framework/Sparkle" ]] || {
  echo "missing Sparkle update framework" >&2
  exit 1
}
otool -L "$APP/Contents/MacOS/Headroom" | grep -Fq '@rpath/Sparkle.framework/' || {
  echo "executable does not link the bundled Sparkle framework" >&2
  exit 1
}
otool -l "$APP/Contents/MacOS/Headroom" | grep -Fq '@executable_path/../Frameworks' || {
  echo "missing bundled-framework runtime search path" >&2
  exit 1
}
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP"
echo "Verified $APP"
