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
python3 Scripts/tests/test_appcast.py -v
Scripts/setup-dmg.sh # Once, to provision the pinned dmgbuild tools.
RELEASE=1 CONFIG=Release Scripts/build.sh app
Scripts/notarize.sh app dist/KeyWeave.app
Scripts/package.sh
version="$(plutil -extract CFBundleShortVersionString raw -o - dist/KeyWeave.app/Contents/Info.plist)"
Scripts/notarize.sh dmg "dist/KeyWeave-$version-arm64.dmg"
Scripts/package.sh --verify
python3 Scripts/appcast.py --app dist/KeyWeave.app \
    --archive "dist/KeyWeave-$version-arm64.dmg" --notes /private/path/to/release-notes.md
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

## In-app update feed

Sparkle 2.10.1 is pinned in `Package.swift`. The release build signs its helpers inside-out with the app's Developer ID. Checks run daily by default, can be disabled in About, and always require the user to install. System profiling and silent installation are disabled. Test-home runs do not start Sparkle.

The app pins `Updates/appcast.xml` on this repository's `main` branch and the KeyWeave public EdDSA key. Both the feed and archive signatures are required; verification happens before archive extraction. The private signing key stays in the login Keychain under account `dev.anuhas.keyweave.sparkle`. On initial setup only, run the pinned distribution's `bin/generate_keys --account dev.anuhas.keyweave.sparkle`; commit only its public key. Do not replace an existing key casually or put private keys in the repository.

`Scripts/release.sh` also generates the feed after notarization. `Scripts/appcast.py` verifies the app/DMG signatures and tickets, signs with the dedicated Keychain account, checks the enclosure signature and signed feed with Sparkle's tools, and atomically replaces the feed. A new release must increment both the version and integer build number. Feed changes must be re-signed; `.gitattributes` preserves their bytes. `--validate-feed` checks metadata only and does not replace cryptographic verification.

Publish and verify the matching GitHub release assets **before** committing/pushing the generated feed, so existing clients never receive an unavailable archive. Keep the generated feed change out of a code PR until those assets exist. Test a background update prompt and actual installation/replacement on an owned copy. Versions through 2.3.0 have no active updater and require one manual bootstrap upgrade. Replacing a DMG under an existing version breaks its recorded signature; publish a new build instead.
