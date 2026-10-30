# AX-context fallback without Screen Recording

Status: implemented for review, unmerged. This is the first bounded correctness slice (P1.1) after the approved Gate 0 merge at `9ef5dd2c02c57435f5653e69c6b658cc6a5b832d`. The [Gate 0 isolation gates](gate0-isolation.md) remain off, including context and input monitoring. This change repairs the source-selection path without enabling live context acquisition or changing permissions.

## Contract and implementation

Previously, `ScreenContextProvider.refreshIfStale()` returned immediately when Screen Recording was denied, so its later accessibility-transcript fallback could never run. The existing transcript extractor, capture/OCR code, budgets, normalization, sanitization, deduplication and history identity are retained.

[ContextSourceReader](../../Sources/TabType/Core/ContextSourceReader.swift) now owns the shared selection rule used by [ScreenContextProvider](../../Sources/TabType/Core/ScreenContextProvider.swift):

1. Production checks immutable context capability and user consent before any platform work.
2. When Screen Recording is allowed, OCR text of at least 12 characters retains priority.
3. When OCR is unavailable or too thin, an eligible accessibility transcript of at least 80 characters can supply context. Denied Screen Recording skips the OCR reader entirely.
4. Ineligible or unusable sources produce no context. Selected source, app, bundle ID and text remain explicit; existing append-time processing stores the result.

The reader has required injected closures and no live platform defaults. Tests can supply synthetic text without a permission request, screenshot, AX tree walk or capability-gate bypass. Production AX eligibility still requires the existing app policy and a focused window. The per-app explanation and permission diagnostic now describe OCR priority and AX fallback accurately. Unsupported inherited claims about a proprietary implementation were removed from comments; no target internals informed this fix.

## Acceptance evidence

[Five deterministic source-selection tests](../../Tests/TabTypeTests/ContextSourceReaderTests.swift) cover denied permission with available AX text and zero OCR calls; ineligible AX; absent/79-character AX text; permitted 12-character OCR priority; and missing/11-character OCR falling back to 80-character AX text. They use synthetic asynchronous readers and an actor recorder, with no sleeps or personal data. The denied-permission regression was observed failing before the fix (nil result, no AX read), then passing. The existing direct-provider isolation regression still records zero injected platform operations while the immutable gate is off.

The full native suite passes **201 XCTest cases: 187 passed, 14 skipped, zero failures**. App target: 88 cases/2 skips; Kit target: 113 cases/12 skips. The actual Settings controller opens and closes six panes twice with cached-window and synthetic sentinel checks. Commands:

```sh
Scripts/test.sh
bash Scripts/build.sh app
codesign --verify --deep --strict --verbose=2 dist/Keyweave.app
```

Validation ran on 2026-10-29, macOS 27.0.1 / Swift 6.4 / Xcode 27.1, using the already-cached pinned llama dependency. The build reports `BUILD SUCCEEDED`; strict/deep signature verification exits zero for the ad-hoc signed `dev.anuhas.keyweave` bundle. No Developer ID or notarization claim is made.

A fresh controlled packaged launch stayed alive for 12 seconds under network and real upstream-path restrictions, then was deliberately stopped. All 25 seeded synthetic sentinel files, including the partial model, remained unchanged. Only `Library/Logs/Keyweave/keyweave.log` was created; the relevant macOS prediction preference was unchanged. This checks the disabled startup boundary, not enabled AX acquisition. Independent static review found no actionable issues. Raw red/green logs, sandbox profile and receipts remain outside public git.

| Artifact | SHA-256 |
| --- | --- |
| Packaged `Keyweave` executable | `e5508c284d68e49a71820a075c5abfef60ef0f5f78a02e927af6e1f58051e856` |
| `ContextSourceReader.swift` | `40ea7003cfd07f2a7c535de18b8f86d55b34bd37527b4cd059a0a24503fecbb1` |
| `ScreenContextProvider.swift` | `88d17e0ba3b37ac44185064bfc2c068cd553a806788fb68098557fd98fe89ce8` |
| `ContextSourceReaderTests.swift` | `43f37f1d53fbde3c934a510eaf4ca5a2a477740f0dfc2574ca78bf18de384315` |

The documentation validator still reports the same ten tracked diagnostics as merged main; the live checkout adds one ignored `docs/.DS_Store` diagnostic. The [Gate 0 report](gate0-isolation.md#documentation-validator-evidence) records the validator command and full diagnostic set. Unrelated docs, research and PR #2 remain untouched.

## Limits and next boundary

The source-selection component is exercised by deterministic tests and wired into production. Enabled end-to-end `refreshIfStale()` acquisition and live AX/OCR usefulness remain unverified because the build's context and input gates remain off. No automatic permission change or new context activation is included. The 14 skips remain nine model/adapter cases, two opt-in network cases, two manual screen/transcript probes and one strip replay. No claim of Cotypist behavioral parity follows from these tests.

Capture identity (P1.2), stale async-result ownership and later context activation are separate work. In particular, the inherited capture fallback must fail closed for the requested app/window before live capture is enabled. No release, paid service, proprietary probing, model download or unrelated project change is included.
