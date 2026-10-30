# KeyWeaver 2.2.1 installed-launch fix

Version/build: `2.2.1` / `14`. This patch fixes the startup crash in the ordinary installed `2.2.0` app; it does not activate optional services or claim Cotypist parity.

## Cause and correction

The installed `2.2.0` executable passed strict signature and Gatekeeper checks but exited with `SIGTRAP` before showing a window. Its diagnostic said that using its own bundle identifier as an `NSUserDefaults` suite name would not work. Symbolication located the trap at `AppPreferences.current`, then `AppSettings.shared` and `AppDelegate.init()`.

`DomainPreferences` force-unwrapped `UserDefaults.init(suiteName: domain)`. When `domain` equals `Bundle.main.bundleIdentifier`, Foundation rejects that initializer. Earlier synthetic homes selected different test domains and therefore concealed the production collision. The fix uses Foundation's default backing store for a matching bundle ID and retains a named backing store for a different explicit domain. Every existing read override still reads only the named persistent domain, so argument/global/added-suite fallbacks remain excluded. No preferences migration or namespace change is involved.

The unconditional Settings message saying input monitoring was disabled is now shown only when that capability actually is disabled.

## Regression and verification

- `python3 Scripts/tests/test_app_preferences.py -v`: two matching-bundle-ID tests failed before the fix with the same initializer warning and `SIGTRAP`; both pass afterward. The harness compiles the actual production Swift sources into a disposable app whose bundle ID equals its unique synthetic preferences domain. Constructor/getter access preserves existing bytes; writes/removal affect only that domain; added-suite/argument values remain hidden and sibling sentinel bytes remain unchanged. No real KeyWeaver preferences are seeded or deleted.
- `KEYWEAVE_TEST_MODEL=<approved-external-model.gguf> Scripts/test.sh`: full native suite, **209 cases: 203 passed, six skipped, zero failures**. The model remains outside git. The skips and narrower model/typing evidence are described in the [2.2.0 report](keyweaver-2.2.0.md).
- `python3 Scripts/tests/test_release_packaging.py -v`: **14 passed**, zero failures, using synthetic platform boundaries.
- Xcode Release arm64 build and strict Developer ID signature passed for `2.2.1`/`14`, team `FMS4W53T57`, with Hardened Runtime and a secure timestamp. App notarization was **Accepted** (`1783f752-3c26-4a22-a7c4-e3cb9d8146bd`), stapled and accepted by Gatekeeper.
- The accepted app replaced only `/Applications/KeyWeaver.app`, with the exact previous executable checked and its bundle preserved outside git. Ordinary LaunchServices opening with **no test-home override** stayed running and showed a **760×648** Setup window. Closing its own Settings window removed that window; opening the app again returned the same window in the same process. It was left running with Settings visible. No preferences/models were migrated and no other app was changed.
- The dmgbuild DMG was separately **Accepted** (`c0b6cb21-d0d8-4633-a076-a7181f7d1990`), stapled and accepted by Gatekeeper. Final mounted DMG/fresh ZIP extraction checks verify publisher, signature, ticket, executable/resource seal and MIT notice against the accepted app. Public download results are recorded in the published release notes.

Raw crash reports, signing receipts and private diagnostic output stay outside git. The documentation validator's 16 preexisting working-tree diagnostics remain separate from native app verification; unrelated documentation is not reorganized.

## Final fingerprints

| Artifact | SHA-256 |
| --- | --- |
| Installed/released app executable | `e829fc81aeadab7abfc9edd5e5868af8c96e780200a357d3c9f1a08533335b28` |
| `KeyWeaver-2.2.1-arm64.dmg` | `57a3e432a9d3e2d8b35960fd91924dba35bf552260f21388e05f20463e7159da` |
| `KeyWeaver-2.2.1-arm64.zip` | `78e2f49082fc3fc871b173fdd33a659a83c225a535bb792a52604d71aeccf61e` |

App CDHash: `d76fb78368b4b661ab55b670e3a52716847182e2`. DMG CDHash: `200ceea9fc97fad5eb5593d931df444debe97dd6`.

## Optional features

The six optional-service flags introduced for Gate 0 remain false. This is a fork policy restriction, not a missing upstream implementation or a paid tier. Screen/clipboard context, screenshot appearance fitting, writing memory, sync and login registration all retain inherited implementations. Login activation was deferred. Other concrete follow-up gaps include capture falling back to another app's window, clipboard ownership/restoration, prompt assembly omitting clipboard text on the transcript branch, and sync resurrecting locally erased writing.

Alternatives and synonyms remain under **Settings → Text Tools → Alternatives & synonyms (Labs)**. Custom instructions/style/name remain in Personalization, and mid-line completion has its per-app control. Retaining these paths does not establish Cotypist Pro/Labs behavior or quality; that remains the [milestone](../MILESTONE.md). No optional service is silently enabled by this patch.
