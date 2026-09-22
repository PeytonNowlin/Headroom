# Signed updates

Headroom uses Sparkle 2.9.6. Both the update archive and appcast require Ed25519 signatures; archive verification happens before extraction. Automatic checking is opt-in, installation uses Sparkle’s standard UI, and system-profile reporting is disabled.

The public key is in `script/Info.plist`. The matching private key is held in the release maintainer’s login Keychain under Sparkle account `io.github.peytonnowlin.Headroom`. `script/make-appcast.sh X.Y.Z` calls Sparkle’s generator with that account. When `SPARKLE_ED_KEY` is set, the script reads the key from that variable instead of Keychain. Do not generate a replacement key for an existing update channel: installed clients trust the existing public key.

`script/release.sh vX.Y.Z` builds, checks, packages, generates signed metadata, then publishes the DMG, SHA-256 checksum, and appcast as assets on the latest GitHub release. The stable feed is `https://github.com/PeytonNowlin/Headroom/releases/latest/download/appcast.xml`. Increment the build number as well as the display version: Sparkle compares `CFBundleVersion`, normally the commit count.

## Releasing from GitHub Actions

The **Release** workflow (`.github/workflows/release.yml`) runs `script/release.sh` on a GitHub-hosted macOS runner, so a release does not need a local Xcode. Start it from the Actions tab or with `gh workflow run release.yml -f version=X.Y.Z`. The version needs a matching `CHANGELOG.md` section on `main`.

The workflow reads the private key from the `SPARKLE_ED_KEY` repository secret. To set it, export the key yourself into a private temporary directory, upload it, and delete the export:

```sh
d=$(mktemp -d) \
  && .build/artifacts/sparkle/Sparkle/bin/generate_keys --account io.github.peytonnowlin.Headroom -x "$d/key" \
  && gh secret set SPARKLE_ED_KEY --repo PeytonNowlin/Headroom < "$d/key"; rm -rf "$d"
```

Ad-hoc macOS code signing and Sparkle update signing serve different purposes. This integration does not notarize the app or remove first-install Gatekeeper requirements. The app includes Sparkle’s upstream license in Resources/Sparkle-LICENSE and preserves its framework helper signatures.
