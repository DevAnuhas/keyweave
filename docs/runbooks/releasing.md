# Releasing KeyWeaver

KeyWeaver is distributed from [DevAnuhas/keyweave](https://github.com/DevAnuhas/keyweave/releases) as an Apple Silicon macOS app. Version `2.2.0` continues the inherited TabType `2.1.0` version line. Internal Swift module names and persistent `dev.anuhas.keyweave` namespaces remain stable. Release acceptance requires working setup/reopening and permission-aware local completion, not just a successful signature or build. Optional screen/clipboard context, writing history and sync must remain off until their explicit consent controls and behavior are verified. Signing and notarization do not establish Cotypist parity.

## Prerequisites

Use full Xcode, the already-provisioned pinned llama dependency and Python 3.10 or newer for DMG tooling. A distribution build requires an installed **Developer ID Application** certificate/private key and its expected ten-character Apple team ID. `SIGN_IDENTITY` accepts its SHA-1 fingerprint or exact certificate name. Apple Development, self-signed and ad-hoc identities cannot be used for a release.

An authorized account holder must have already stored notarization credentials in a `notarytool` Keychain profile. Pass only the profile's name through `KEYCHAIN_PROFILE`; never put Apple IDs, passwords, API keys or signing keys into source, command history or chat. Receipts default to `~/Library/Application Support/KeyWeaverReleaseReceipts`, outside public git. `NOTARY_RECEIPTS_DIR` can select another private directory outside the repository. No helper installs a certificate, changes trust or launches/installs the app.

## DMG creation method

The DMG uses the same **dmgbuild** creation method as Yeelight Station, with a headless Finder layout, HFS+ filesystem and UDZO compression. [Requirements](../../packaging/dmg/requirements.txt) pin the same wheel hashes for `dmgbuild==1.6.7`, `ds-store==1.3.3` and `mac-alias==2.2.3`. Provision the owned, ignored `.build-keyweave/tools/dmgbuild` environment once:

```sh
Scripts/setup-dmg.sh
```

`DMG_WHEELHOUSE=/path/to/pinned/wheels Scripts/setup-dmg.sh` uses `--no-index` with local wheels for an offline setup. Both paths enforce `--require-hashes --only-binary=:all:`. Packaging never installs dependencies automatically. An existing environment can instead be selected through `DMGBUILD_VENV`; packaging reads it without writing Python bytecode and checks all three versions. No other-project path is hardcoded.

[The layout](../../packaging/dmg/settings.py) uses KeyWeaver's signed `AppIcon.icns` as the custom volume icon, the committed 600×400 background and 1200×800 Retina companion, a 600×500 Finder window, app at `(150, 180)`, Applications at `(450, 180)`, and `License.txt` at `(520, 320)`, with 80-point icons and 13-point labels. The background contains the app name, drag-to-Applications instruction and arrow; it has no updating or preview footer. Regenerate both PNGs with `swift Scripts/make-dmg-background.swift packaging/dmg` after changing the background source. No FinderInfo extension flags are applied to the signed app. `dmgbuild` temporary backing images stay inside a private stage; cleanup only detaches images whose backing paths are inside that stage. A per-output lock prevents overlapping package operations. Failed cleanup preserves the stage and lock for inspection.

## Build and notarize

Set the following non-secret configuration to the appropriate existing certificate/profile before running:

```sh
export SIGN_IDENTITY=<Developer-ID-certificate-fingerprint>
export DEVELOPMENT_TEAM=<expected-team-id>
export KEYCHAIN_PROFILE=<existing-notarytool-profile-name>
Scripts/test.sh
python3 Scripts/tests/test_release_packaging.py -v
# Once only, unless DMGBUILD_VENV already selects the pinned tooling:
Scripts/setup-dmg.sh
RELEASE=1 CONFIG=Release Scripts/build.sh app
Scripts/notarize.sh app dist/KeyWeaver.app
Scripts/package.sh
Scripts/notarize.sh dmg dist/KeyWeaver-2.2.0-arm64.dmg
Scripts/package.sh --verify
```

Use the version in `Resources/Info.plist` in the asset paths. `2.2.0` uses build `13`, after inherited `2.1.0`/build `11` and the withdrawn isolation build `12`. `Scripts/release.sh` runs those local build/notary/package steps in order when all three configuration variables exist. It never tags, pushes or creates a GitHub release. The app build signs `llama.framework` and then the app explicitly, inside-out, with Hardened Runtime and secure timestamps. Release identity/configuration failures stop before building. Every release signature must satisfy Apple's Developer ID certificate OID, expected team and isolated bundle identity; no ad-hoc fallback exists in release mode.

The app must have an **Accepted** notary status and matching authoritative log before stapling. The helper verifies the ticket/signature and Gatekeeper, then recreates `KeyWeaver-<version>-arm64.zip` from the stapled app, with MIT `LICENSE` alongside it. ZIP files cannot themselves be stapled. The dmgbuild DMG contains that app, an Applications link and the same MIT notice named `License.txt`; the container is signed and notarized separately. Final verification mounts the DMG read-only, checks the mounted app and compares its executable/resource seal to the accepted source app. It also extracts and verifies the ZIP. `SHA256SUMS.txt` is written only after both final artifacts pass those checks.

## Timeouts and uncertain uploads

Notary submissions run once. Each private receipt binds the artifact's code-directory hash and the exact uploaded archive's SHA-256. `NOTARY_TIMEOUT` defaults to `55s`; a timeout does not cancel Apple's submission. Resume the same submission using the printed private receipt path:

```sh
Scripts/notarize.sh app dist/KeyWeaver.app --resume <private-app-receipt>
Scripts/notarize.sh dmg dist/KeyWeaver-2.2.0-arm64.dmg --resume <private-dmg-receipt>
```

Do not rerun the complete release build after a timeout. If upload returned no ID, inspect that receipt and the account's submission history before taking another action. Existing same-signature receipts block automatic reupload, and resumed receipts never submit again. Rejected/Invalid status preserves Apple's log and stops. Changed source artifacts or corrupted preserved submissions fail closed. A failed DMG staple operates on a private copy and leaves the distribution image unchanged.

`Scripts/package.sh` refuses to overwrite an existing DMG, including a previously accepted image. Preserve that artifact and its receipts privately before deliberately building a different container. A DMG-only layout change must not rebuild or modify the accepted signed app or its ZIP; rebuild, sign and notarize only the new DMG, then run final verification/checksums again.

## Publish and verify

After reviewing the exact source tree, license, native test results, setup/reopen and synthetic completion journeys, signed bundle, Accepted app/DMG receipts, mounted/extracted app checks and final hashes, create an annotated `v2.2.0` release tag on that source commit. Publish a normal GitHub release titled **KeyWeaver 2.2.0**, marked **Latest**, attaching only:

- `KeyWeaver-2.2.0-arm64.dmg`
- `KeyWeaver-2.2.0-arm64.zip`
- `SHA256SUMS.txt`

```sh
gh release create v2.2.0 \
    dist/KeyWeaver-2.2.0-arm64.dmg \
    dist/KeyWeaver-2.2.0-arm64.zip dist/SHA256SUMS.txt \
    --repo DevAnuhas/keyweave --verify-tag \
    --title 'KeyWeaver 2.2.0' --prerelease=false --latest=true \
    --notes-file /private/path/to/release-notes.md
```

Use release notes describing actual enabled behavior, optional capabilities still disabled, tested macOS/architecture and unresolved quality/compatibility checks. A tag alone is not a GitHub release; a prerelease does not become Latest. Confirm that the published release has `isDraft=false`, `isPrerelease=false` and is returned by `repos/DevAnuhas/keyweave/releases/latest`. Do not fabricate releases for inherited historical tags or claim parity. Download the public assets anonymously after publication, compare their SHA-256 values to the final local files and checksums, and verify a fresh extracted app's ticket/signature. Keep raw notary receipts and credentials outside git. Preserve the upstream MIT notice and third-party acknowledgments.
