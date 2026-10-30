# Releasing KeyWeave

Requires full Xcode, the cached pinned llama XCFramework, an existing Developer ID Application identity and an existing notarization Keychain profile. Keep signing credentials and notary receipts outside git. Preserve the MIT license and bundled third-party notices.

## Build and verify

```sh
export SIGN_IDENTITY='<Developer-ID-certificate-fingerprint>'
export DEVELOPMENT_TEAM='<expected-team-id>'
export KEYCHAIN_PROFILE='<existing-notarytool-profile-name>'
Scripts/test.sh
python3 Scripts/tests/test_app_preferences.py -v
python3 Scripts/tests/test_release_packaging.py -v
Scripts/setup-dmg.sh # Once, to provision the pinned dmgbuild tools.
RELEASE=1 CONFIG=Release Scripts/build.sh app
Scripts/notarize.sh app dist/KeyWeave.app
Scripts/package.sh
version="$(plutil -extract CFBundleShortVersionString raw -o - dist/KeyWeave.app/Contents/Info.plist)"
Scripts/notarize.sh dmg "dist/KeyWeave-$version-arm64.dmg"
Scripts/package.sh --verify
```

The app and DMG must each receive **Accepted**, be stapled and pass Gatekeeper. Packaging checks the mounted DMG and extracted ZIP against the accepted app, then writes `SHA256SUMS.txt`. The [dmgbuild layout](../../packaging/dmg/settings.py) and [hash-pinned dependencies](../../packaging/dmg/requirements.txt) own the installer recipe. Regenerate its background with `swift Scripts/make-dmg-background.swift packaging/dmg` after changing the source.

A notary timeout does not cancel the submission. Resume with the printed receipt using `Scripts/notarize.sh <app|dmg> <artifact> --resume <receipt>`; do not rebuild or resubmit it. If no submission ID was returned, inspect the receipt and account history before retrying. Packaging refuses to overwrite an existing DMG.

## Publish

Verify normal installed launch and Settings reopening without test-home overrides, plus the affected synthetic writing journey. Signatures and tests alone do not establish app compatibility or Cotypist parity.

Tag the exact verified source commit as `v<version>`, then publish a normal release marked Latest:

```sh
gh release create "v$version" \
    "dist/KeyWeave-$version-arm64.dmg" \
    "dist/KeyWeave-$version-arm64.zip" dist/SHA256SUMS.txt \
    --repo DevAnuhas/keyweave --verify-tag \
    --title "KeyWeave $version" --prerelease=false --latest=true \
    --notes-file /private/path/to/release-notes.md
```

Confirm GitHub's latest-release endpoint, anonymously download the assets, compare checksums and verify the fresh app's signature/ticket. Release notes should state actual changes and remaining feature limits; raw receipts stay private.
