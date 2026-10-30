# KeyWeaver 0.1.0 preview

> **Withdrawn:** the `v0.1.0-preview.1` GitHub release and remote tag were removed on 2026-10-30. This report preserves the original build's evidence; it does not describe current behavior. Continue with [KeyWeaver 2.2.0](keyweaver-2.2.0.md), which restores core startup and continues the inherited version line. The hashes and notarization IDs below apply only to the withdrawn artifacts.

Release tag: `v0.1.0-preview.1`. App version/build: `0.1.0` / `12`. This is an Apple Silicon interface/isolation preview: suggestions and input monitoring are disabled. Context, clipboard context, writing memory, sync, login registration and automatic updates remain off. Signing/notarization does not establish feature parity or daily-use readiness.

## Artwork and packaging

The app has original generated robot/weave artwork, a matching transparent logo and an 18/36-pixel macOS template menu image. The [masters and generation prompts](../../Resources/Branding/README.md) are included; the Cotypist reference asset is not. Visible branding is KeyWeaver, while `dev.anuhas.keyweave` and existing isolated storage/Keychain/cloud paths stay stable.

The DMG uses Yeelight Station's **dmgbuild 1.6.7** method, with the same pinned `ds-store 1.3.3` / `mac-alias 2.2.3` dependencies, HFS+/UDZO, custom volume icon, 1×/2× background, Finder window and app/Applications layout. The [release runbook](../runbooks/releasing.md) and [settings](../../packaging/dmg/settings.py) own the recipe. No FinderInfo flags modify the signed app. The app and container are notarized separately; the ZIP is recreated from the stapled app.

## Verification performed — 2026-10-30

| Check | Result |
| --- | --- |
| Native `Scripts/test.sh` | 203 XCTest cases: **189 passed, 14 skipped, zero failures**. App: 90 cases/2 skips; Kit: 113 cases/12 skips. |
| Packaging command-boundary tests | **14 passed**, zero failures. Includes exact dmgbuild pins/layout, no app modification, fail-closed signing, resume safety and owned-mount cleanup. |
| Release build | Xcode 27.1 / Swift 6.4 on macOS 27.0.1, arm64. Developer ID Application: Arno & Co. LLC, team `FMS4W53T57`; Hardened Runtime and secure timestamps. |
| App notarization | **Accepted**, submission `af7ea004-f280-4914-9ce0-163e5dd42b07`; ticket stapled/validated, strict signature and Gatekeeper accepted. |
| dmgbuild DMG notarization | **Accepted**, submission `35496f2c-9254-405f-967f-09d9dc07fdd5`; ticket stapled/validated, signature and Gatekeeper accepted. |
| Final packaging | Fresh extracted ZIP and read-only mounted DMG apps pass ticket/signature/Gatekeeper checks and executable/resource-seal comparisons. License and Applications link verified. |
| Controlled app launch | Alive for 12 seconds, then deliberately stopped. All 25 synthetic sentinels unchanged; only its own log created; partial model and global prediction preference unchanged. Network/upstream paths denied for the test process. |
| Settings | Actual cached window opens/closes six panes twice within the native suite. New app/menu artwork loads from the packaged resource layout; template alpha and both pixel scales are checked. |
| Static reviews | No production blocker. A test's `hide_extensions` option assertion was corrected and the full packaging group rerun. |

The app executable SHA-256 is `4024a04bd84060fcdc1da3b2a06725943769280e6fdaa1bac673dcbe07f69e26`. Final stapled assets:

| Asset | SHA-256 |
| --- | --- |
| `KeyWeaver-0.1.0-arm64.dmg` | `9827b74f8c27d77d32599db193f5efeefe04cf4c971a4acb4434a1870127db15` |
| `KeyWeaver-0.1.0-arm64.zip` | `bef97cec5b2540ad8ba67efc433bf91cc5499eb4762dc0614948977ac8e58452` |

`SHA256SUMS.txt` is generated only after stapling and final package verification. Publication includes anonymous download/hash verification. Raw Apple receipts, private paths, credentials and reference assets stay outside git.

## Notices and limits

The original MIT notice is unchanged. Full ggml/xxHash, gemoji, SymSpell, Google Books/SCOWL and FrequencyWords notices/attributions are bundled with [exact data provenance](../../Sources/TabType/Resources/ThirdPartyNotices/README.md); eight font OFL notices remain alongside their fonts. The twelve dictionary payloads are unchanged upstream blobs, and the inherited emoji transform is reproduced exactly. No model weights are bundled or downloaded for verification.

The fourteen skips are nine model/adapter cases, two opt-in network cases, two manual screen/transcript probes and one strip replay. Enabled live acquisition, completion usefulness, host compatibility beyond this check and Cotypist Pro/Labs parity remain unverified. The historical SCOWL sub-version used by SymSpell is undocumented; the complete official v1 notice is included without claiming to pin that older sub-version. Repo-wide documentation validation retains the same fifteen tracked diagnostics as the merged baseline; no unrelated documentation was reorganized. These are separate from the passing native and release checks.
