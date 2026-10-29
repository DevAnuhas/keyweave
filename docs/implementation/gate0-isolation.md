# Gate 0 isolation

Status: implemented for review; unmerged. Scope is Gate 0.1–0.4 only. Gate 1+, feature parity work, merges, releases, paid services and Cotypist decompilation remain unauthorized. Upstream MIT attribution and internal Swift module/target names remain intact.

## Implemented boundary

The packaged app is `Keyweave.app`, executable `Keyweave`, bundle/signing identifier `dev.anuhas.keyweave`. The build helper uses `.build-keyweave/`, defaults to the distinct `Keyweave Dev` signer, and falls back to ad-hoc signing without creating or trusting a certificate. The release helper refuses before mutation or distribution actions. Internal `TabType`, `TabTypeKit` and eval target names are retained.

`ProductIdentity` and `AppPaths` own pure namespace/path resolution. Preferences read only `dev.anuhas.keyweave`, without standard/argument/global-domain fallback. App data, models, caches and logs use Keyweave roots; sync uses `dev.anuhas.keyweave.sync`, `Keyweave Sync` and `.keyweavesync`. Construction and path getters do not create directories, import writing or create/replace encryption keys. No default path consults TabType/Cotypist data.

Log construction remains passive, including when an existing log exceeds 5 MiB. The first actual queued write checks rotation before appending, then checks again every 500 additional writes. Rotation retains the newest complete lines within the existing 1 MiB tail policy in `keyweave.1.log`. A fresh logger performs its own first-write check, so repeated short sessions cannot indefinitely skip rotation. `flush()` waits for queued operations without writing or rotating by itself.

Sync, writing collection/use, screen/conversation/clipboard context, screenshot appearance, login registration and input monitoring are gated off in this build. Persisted flags, direct setters, remote settings and per-app context/learning overrides cannot activate those effects. Input monitoring is blocked at startup and the direct Engine API even when macOS reports Accessibility trusted. Settings shows the disabled controls; it does not alter macOS predictive-text preferences or request Screen Recording access.

The updater has no feed, network request, installer or relaunch path. Catalog access always returns the bundled catalog, ignoring remote and cached replacements. Model construction/getters and `start()` are passive: no automatic refresh, loading, resume or power subscription. Existing explicit manual model-management code is preserved; it was not invoked during verification. Automatic OCR/model diagnostics, pending/legacy writing import and global macOS preference application are removed from startup.

These changes prevent automatic upstream access; they do not implement data migration, owned application updates, new model catalogue entries or broader writing features.

## Repeatable native tests

```sh
Scripts/test.sh
bash Scripts/build.sh app
codesign --verify --deep --strict --verbose=2 dist/Keyweave.app
```

The test helper requires the cached pinned llama XCFramework, creates a private temporary home with an ownership token, clears manual/network test opt-ins, and removes only its own test preferences/root afterward. It does not repurpose `HOME`. Settings fixtures reject unowned roots, existing destination stores and symlink ancestors, and create files without overwriting. An ordinary test environment variable pointing at a personal home is insufficient to authorize fixture writes.

The build dependency remains llama.cpp `b11490`, pinned SHA-256 `bc19f561ae2504cb2b3e7b189f44c8a81f8aa0fd84f70b9e81c2ff92a98a086c`. Its already-cached 62,967,543-byte archive was checksum-verified and copied into the isolated package cache. No new dependency/model download was needed. Fresh machines must provision that dependency separately before using the helper.

## Negative coverage

Tests exercise bundle/plist/package identity; pure paths and sibling sentinels; exact preference-domain reads; passive writing/key/import construction and disabled lifecycle; zero injected Keychain/cloud/login/capture calls; persisted/direct/synced sensitive flags and per-app overrides; bundled catalog with zero injected requests; absent/partial/installed model fixtures; disabled direct updater/input-start APIs; and real Settings window opening, closing and cached-window reuse across six panes twice.

Test-first checks exposed the former writing-import/key mutation, sync system access, settings restoration, capture/login calls, remote/cache selection and startup input-monitor behavior. Fixes were limited to the isolation contract. Review also caught and corrected an unsafe test-root assumption and missing per-app adversarial coverage.

The log follow-up adds four deterministic filesystem regressions: constructor-only access preserves active/archive bytes and absent directories; the first queued write rotates an oversized log; three fresh two-write sessions each rotate their inherited oversized log; and a long session rechecks after 500 additional writes. Tests drain the serial queue through `flush()` without sleeps or timestamp comparisons. Before the fix, the first-write regression failed with two assertions: the old archive survived and the active log remained 5,242,947 bytes. All four regressions now pass.

## Native results and controlled launch

Validation date: 2026-10-29, macOS 27.0.1 on Apple Silicon, Swift 6.4 / Xcode selected at `/Applications/Xcode.app`.

| Check | Result | Boundary |
| --- | --- | --- |
| `Scripts/test.sh` | Exit 0; **196 XCTest cases: 182 passed, 14 skipped, 0 failed** | Native package and all test targets, not a source-only subset. App target: 83 cases/2 skips; Kit target: 113 cases/12 skips. Includes the four log regressions. |
| Actual Settings controller | Passed within native suite | Opens/closes six panes twice, reuses the cached window, seeds per-app overrides, and preserves synthetic store bytes. Refusal tests reject unsafe fixture paths. |
| `bash Scripts/build.sh app` | Xcode `BUILD SUCCEEDED` | Packaged arm64 `dist/Keyweave.app`; internal targets retained; cached dependency reused. |
| Bundle/signature | `dev.anuhas.keyweave`, executable `Keyweave`; strict/deep verification exit 0 | Ad-hoc; no Team ID or Developer ID/notarization claim. |
| Controlled packaged launch | Alive for 12 seconds; deliberately stopped with SIGTERM | Disposable synthetic home; sensitive persisted flags and per-app overrides set true, malformed key/history/import fixtures and a partial model pre-seeded. Network and real upstream file paths denied by a test sandbox profile. |
| Launch sentinel checks | **25 files unchanged; zero deleted/modified; only Keyweave log created** | Partial model unchanged; no Keyweave key/import/catalog creation. Current-host macOS prediction preference unchanged. |
| Independent review | Two initial findings corrected; second review clear; log follow-up review clear | Reviewed log code/test fingerprints match the updated native test and build inputs. |

Verified updated executable SHA-256: `d04712f078714a0c856f29e91cd8fdc65c17977330150315891e0285494cb378`. Native tests, build/signature and the controlled launch were rerun after the log fix. An earlier smoke process reported existing Accessibility trust; it was stopped and the additional startup/direct input-monitor guard was added and tested before the final launch. The updated process still reported trust while screen context remained off; no permission was changed.

The 14 skipped cases are nine model-backed/adapter integration tests (no GGUF fixtures), two opt-in network-download tests, two manual capture/transcript probes and one strip replay. They remain unverified. Explicit model actions, completion usefulness and live screen/clipboard behavior were not exercised. An optional native automation attempt to inspect the menu-bar-only smoke process timed out; actual cached-window Settings behavior was verified through native XCTest, with no claim of a full manual GUI/completion walkthrough.

Raw outputs, failed red-phase logs, sandbox profile and synthetic launch receipts remain outside public git. Syntax/plist/new-file whitespace checks pass. Passing selected worker checks was never counted as the full native result above.

## Updated fingerprints

These SHA-256 values identify the source/test bytes exercised above; documentation-only evidence updates do not change the build inputs.

| Artifact | SHA-256 |
| --- | --- |
| `Sources/TabType/Core/Log.swift` | `9e3a4250143258c913ca8ccc465a11cf8a4c6169299c2a59ac5cf7ce693e22d5` |
| `Tests/TabTypeTests/LogTests.swift` | `9a9ae607f9867b14be1bb793dfc863f0bcb8c998a18685dc599a9432e5c484db` |
| `Tests/TabTypeTests/SettingsIsolationTests.swift` | `55d24a9e0826df3c76738113d6a7b0b6debe74631bf5c0d2ea350f8be307575e` |
| `Tests/TabTypeTests/StartupIsolationTests.swift` | `1df8094da04e1fe343c3eced60cc8cfe8f34a1dca60b8936555a35d0b8e7748f` |
| `Scripts/test.sh` | `f3ae3e3e250114f4c6e683d5a987b647b95a9b5fb6e392f331bdfeaa530148d9` |

## Documentation-validator evidence

The validator is `/Users/mac/.agents/skills/maintain-project-docs/scripts/validate_docs.py`, SHA-256 `d032871f8c808fdea8386eac0b616b0880c1006ada732de84eebcb5e335e2131`, run with Python 3.15.0. The exact validator command is:

```sh
python3 /Users/mac/.agents/skills/maintain-project-docs/scripts/validate_docs.py --root .
```

Run separately from disposable tracked trees extracted with `git archive --format=tar b75ea0e22bc565e57b133b2625a49d7e8a24c789` (baseline) and `git archive --format=tar HEAD` (updated Gate 0), it exits **1 in both cases**, with empty stdout and the stderr below. The only normalization is the disposable absolute root, shown as `<root>`. `--require-core` is omitted for this incomplete documentation-migration audit; this scoped change does not create the unrelated root context/agent documents. These newly captured comparisons substantiate the claim; the earlier turn's missing raw validator transcript is not reconstructed.

Baseline stderr:

```text
ERROR: flat docs file `docs/COMPARISON.md`; route it into a canonical category
ERROR: flat docs file `docs/social-preview.png`; route it into a canonical category
ERROR: flat docs file `docs/REWRITE_PLAN.md`; route it into a canonical category
ERROR: flat docs file `docs/demo.gif`; route it into a canonical category
ERROR: <root>/README.md: broken local link `../../issues`
ERROR: <root>/README.md: missing anchor `#-full-ai-disclosure--who-and-what-built-this`
ERROR: <root>/README.md: broken local link `../../issues/new/choose`
ERROR: <root>/README.md: broken local link `../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22`
ERROR: <root>/README.md: broken local link `../../discussions`
ERROR: <root>/README.md: broken local link `../../releases`
Documentation validation failed with 10 error(s).
```

Updated tracked-tree stderr:

```text
ERROR: flat docs file `docs/COMPARISON.md`; route it into a canonical category
ERROR: flat docs file `docs/social-preview.png`; route it into a canonical category
ERROR: flat docs file `docs/REWRITE_PLAN.md`; route it into a canonical category
ERROR: flat docs file `docs/demo.gif`; route it into a canonical category
ERROR: <root>/README.md: broken local link `../../issues`
ERROR: <root>/README.md: missing anchor `#-full-ai-disclosure--who-and-what-built-this`
ERROR: <root>/README.md: broken local link `../../issues/new/choose`
ERROR: <root>/README.md: broken local link `../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22`
ERROR: <root>/README.md: broken local link `../../discussions`
ERROR: <root>/README.md: broken local link `../../releases`
Documentation validation failed with 10 error(s).
```

The tracked diagnostic sets are identical: zero introduced, zero resolved. Five GitHub-relative README URLs are interpreted as local filesystem links by this validator; this output does not prove those URLs fail on GitHub. Running the same command in the live checkout exits **1 with 11 errors**: these ten plus a flat-file diagnostic for `docs/.DS_Store`. That extra file is ignored local state, absent from both tracked snapshots; calling it a tracked baseline failure would be inaccurate. It, the unrelated research and all inherited docs remain untouched. The validator is not passing.

## Limits

Ad-hoc signing supports this local check; it does not establish Developer ID signing, notarization, stable permission grants or release readiness. No signing certificate/trust or macOS permission was changed.

Model-backed inference, live network-download tests, manual screen/transcript probes and strip replay require additional fixtures or explicit opt-ins. No Cotypist behavior comparison or Gate 1 bug fix is part of this stack. A controlled launch and synthetic fixtures are bounded evidence, not a universal audit of macOS filesystem or preference-daemon access.
