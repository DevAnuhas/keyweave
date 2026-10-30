# KeyWeaver 2.2.0 verification

Version/build: `2.2.0` / `13`, Apple Silicon, macOS 14 or later. Target tag/title: `v2.2.0` / **KeyWeaver 2.2.0**, published as a normal GitHub release marked Latest. This continues inherited TabType `2.1.0`/build `11`; the `0.1.0`/build `12` isolation release and its remote preview tag were withdrawn. Signed build, model-enabled tests, controlled typing and local distribution checks passed as recorded below. GitHub publication and anonymous download checks are recorded in the release notes.

## Why the previous installation looked broken

The withdrawn app passed signature, notarization-ticket and Gatekeeper checks and matched its published executable. Those checks established distribution integrity, not a working autocomplete journey. Its menu-bar-only startup opened no setup window, had no reopen handler, hard-disabled input monitoring and left model startup empty. Merging the isolation PRs preserved those restrictions; it did not activate the inherited completion engine. Two controlled launches of the old installed executable stayed alive for five seconds with zero visible app windows. This reproduced hidden startup; neither controlled run crashed.

## Restored behavior

- Launch visibly opens Settings on Setup. Opening an already running app brings back the same Settings window, including after it was closed or its menu icon was hidden.
- Basic input monitoring is available. Startup checks Accessibility trust without requesting it automatically; the user grants permission explicitly. Monitoring starts after trust is granted and stops when trust is revoked. Setup/readiness must also reflect whether the input monitor actually starts, rather than treating trust alone as success.
- Model constructors and Settings getters remain passive. Explicit startup loads the selected, fully installed KeyWeaver model once. Missing, partial, truncated or deleted-custom selections do not start downloads or resume transfers. Invalid/unknown selections surface recoverable setup errors. Manual model selection/download remains available.
- Core completion reads the focused editable field after Accessibility permission. Screen Recording is not required for that basic path. Secure-field exclusion and inherited app/domain controls remain in place.
- Optional screen context, screenshot appearance capture, clipboard context, writing memory, sync and login registration remain disabled. Automatic app updates, remote model-catalog refresh, automatic model-download resume, writing-import consumption, OCR diagnostics and global macOS preference changes remain disabled.
- `dev.anuhas.keyweave` preferences, support/cache/log/model paths, Keychain service and cloud namespace remain isolated. No automatic TabType/Cotypist data or model migration occurs. Upstream MIT and bundled third-party notices are retained.

## Installer and release presentation

The DMG still uses Yeelight Station's pinned **dmgbuild 1.6.7** method, HFS+/UDZO and app/Applications layout. All three former footer lines were removed, including the updating/quit instructions and preview-disabled message. The app name, drag-to-Applications instruction and arrow remain. Both 600×400 and 1200×800 backgrounds are regenerated from the native source; the entire former footer region is verified blank at both scales.

A tag alone is not a GitHub release. The replacement must be a published release with `isDraft=false`, `isPrerelease=false` and explicit Latest selection, verified through GitHub's latest-release endpoint. See the [release runbook](../runbooks/releasing.md) for the exact recipe. Historical upstream tags are preserved without manufacturing release entries for them.

## Verification status — 2026-10-30

| Check | Actual result |
| --- | --- |
| Full native suite with model | **209 cases — 203 passed, six skipped, zero failures** on the final source. App: 96 cases/two skips; Kit: 113 cases/four skips. Includes the final input-monitor failure-status regression and an application-level local-completion integration test. |
| Real model-backed inference | Eight of nine `LlamaIntegrationTests` passed with the approved 396,705,184-byte Qwen3-0.6B-Base i1 Q4_K_M GGUF outside git. Includes tokenization, prefix reuse/splice, deterministic partial-word healing, selected-word alternatives, invalid-adapter recovery, superseded-request cancellation and parked-model reload. Adapter-change fixture remains unavailable. |
| Startup/model regressions | Permission denial, successful input startup, actual Settings reopening, passive constructors/getters, missing/partial/truncated/deleted-custom model states, unknown selection and load failure are covered through public seams. Failed keyboard-monitor creation returns an explicit failed state; Setup requires actual active monitoring before declaring readiness. |
| Packaging command-boundary suite | **14 passed**, zero failures. Synthetic platform tools; no actual signing, mounting or Apple connection from this suite. |
| Rendered DMG backgrounds | Old image failed the independent blank-footer check with 3,830 non-background pixels; regenerated 1×/2× images both have **zero** non-background footer pixels and correct dimensions. |
| Final Release build and signature | Xcode Release build succeeded for `2.2.0`/`13`; Developer ID Application **Arno & Co. LLC**, team `FMS4W53T57`, Hardened Runtime, secure timestamp and strict publisher/bundle requirements passed. |
| App and DMG notarization/stapling | Both **Accepted**, stapled and validated; Gatekeeper accepted. App job `5d7fc90e-fd87-41ab-9dd3-d5b42db6f8a6`; DMG job `e3bcc7fd-c732-4519-99be-1a158fc3cae3`. |
| Packaged-app setup/reopen and synthetic accept journey | Signed app opened a normal **760×648** Settings window. Native tests exercised repeated close/reopen. With a verified local model and existing Accessibility trust, global synthetic typing produced a painted ghost and Tab acceptance in an owned NSTextView. All 16 sentinel files remained unchanged; both owned processes stopped. |
| Final DMG/ZIP extraction and hashes | Read-only mounted DMG and fresh ZIP extraction passed strict signature, publisher, ticket and Gatekeeper checks and matched the accepted app executable/resource seal. Final hashes are below. Public download results are recorded in GitHub release notes after publication. |

The six skips are two manual screen/transcript probes, two opt-in model-downloader network cases, one adapter-change fixture and one strip replay. Model weights stay outside git and are not bundled with the app. The test-model SHA-256 is `279e7f2d04f7e225eef1ff469897340e18a53ed500247b8c7a1acf13e9a04446`. No personal writing, clipboard text or vendor assets are used as public test evidence.

## Final artifact fingerprints

| Artifact | SHA-256 |
| --- | --- |
| App executable | `54ecdd5256542c3b2e99f686f46b36a5a35baa1b6822bfb137fa7a4dec01ef84` |
| `KeyWeaver-2.2.0-arm64.dmg` | `d554189bbc39ee7433c1318acd4b3e1593a1d80926cc19c720466efe99919902` |
| `KeyWeaver-2.2.0-arm64.zip` | `feac6d70101ad7660f1af98a6a16955d1d4581bf08b3c8b3d484d9add64c5461` |

The synthetic host journey typed `The capital of France is` and accepted ` the`. This verifies the live typing/ghost/Tab insertion mechanism, not factual correctness or broad writing quality. The separate application-level completion integration test continued the bare synthetic sentence with `Paris`. The smaller test model and different metadata/context are disclosed; no general model-quality claim follows.

Native command: `KEYWEAVE_TEST_MODEL=<approved-external-model.gguf> Scripts/test.sh`. Packaging regression command: `python3 Scripts/tests/test_release_packaging.py -v`. Actual signed build, notarization and DMG commands follow the [release runbook](../runbooks/releasing.md). Raw platform receipts and temporary synthetic harnesses remain outside git. The documentation validator retained exactly the same 16 working-tree diagnostics before/after this maintenance (15 established tracked baseline diagnostics plus an ignored Finder metadata diagnostic); documentation validation is not green, and unrelated documentation was not reorganized.

## Limits and remaining evidence

This work restores core behavior instead of merely removing preview labels. It does not certify Cotypist Pro/Labs parity, optional acquisition services, broad app compatibility, model quality or cross-Mac sync. Synthetic inference and unit tests establish narrower behavior than daily writing. Release notes name the packaged-app journeys actually run, test skips, final fingerprints and accepted notarization IDs. Finder-launched KeyWeaver needs its own Accessibility grant and local model setup; TabType permissions and models are not automatically migrated.

The [withdrawn build report](keyweaver-preview.md) remains historical. The [AX fallback report](ax-context-fallback.md), [Gate 0 report](gate0-isolation.md) and [milestone](../MILESTONE.md) retain their respective research/isolation and future-acceptance boundaries. Raw signing/notary receipts, local paths and synthetic host captures remain outside public git.
