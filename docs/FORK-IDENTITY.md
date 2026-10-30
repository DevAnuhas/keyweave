# Fork identity and first-run safety

The app is KeyWeave (`dev.anuhas.keyweave`); internal Swift modules retain TabType names. Keep the isolated identity and storage boundaries below when changing startup or distribution.

## Existing coupling to inspect

- `Resources/Info.plist`: display/executable/bundle identifiers.
- `Scripts/build.sh`, `Scripts/setup-signing.sh`, `Scripts/release.sh`: output names, signing certificate label, identifier and release packaging.
- `Sources/TabType/App/Updater.swift`: only the pinned KeyWeave feed and public key may activate Sparkle. Test processes remain inert.
- `Sources/TabTypeKit/Catalog/ModelCatalog.swift`: the moving upstream catalog endpoint.
- `Sources/TabTypeKit/Catalog/ModelStore.swift`, `Sources/TabType/Core/WritingStore.swift`, settings/statistics/logging: Application Support and preference namespaces.
- `Sources/TabType/App/SyncManager.swift`: `app.tabtype.sync` Keychain service and `TabType Sync` iCloud Drive folder.
- `Sources/TabType/Core/ScreenContextProvider.swift`: own-app exclusion list.
- User-facing views, URLs, icons and menu text. Preserve upstream attribution and third-party licenses even after rebranding.

## Intended boundary

Use `KeyWeave` as the working display/bundle output name and a distinct application identifier, provisionally `dev.anuhas.keyweave`. Keep internal Swift module names if renaming them creates unnecessary risk. The signer may require a different final identifier; verify it before distribution.

Give the fork its own Application Support, preferences, Keychain service and cloud-sync namespace. Do not silently read, migrate, overwrite, delete or synchronize TabType/Cotypist data. Import, if added later, is explicit and reversible. Models may be large; do not duplicate or move another app's installed weights without permission and license checks.

Disable inherited automatic updates until a KeyWeave-owned distribution source and publisher verification exist. Repointing a URL alone is not enough: asset naming, bundle identity, checksum, signing trust and recovery must agree. A new fork with no releases must show a benign no-update state, not install an upstream TabType build.

Choose whether to pin or own the remote model catalog; do not inherit unreviewed future catalog changes silently. Preserve model-license notices and download verification.

For local development, use a distinct stable development signing identity rather than borrowing `TabType Dev`. Do not import or share private signing keys. Self-signing can support stable local identity, but does not establish Developer ID signing or notarization.

## Evidence required

- Static test/check of all product identity, update and storage endpoints; intentional attribution strings may still mention TabType.
- Real Mac build with bundle metadata and signature readback.
- Coexistence test using synthetic stores: the other apps' files/settings remain unchanged.
- Fork updater tests for no release, wrong application/publisher, bad checksum and failed replacement.
- Relaunch/rebuild permissions behavior recorded; no promise that the old app's grants transfer to a new bundle identity.

The production app uses these isolated namespaces. In-app updates require a signed KeyWeave feed, EdDSA archive verification before extraction, and Developer ID verification; the [release runbook](runbooks/releasing.md) owns publishing instructions.
