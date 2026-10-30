# KeyWeaver

## Direction

A free, local-first macOS writing-autocomplete application developed from [nilava/TabType](https://github.com/nilava/TabType). Preserve the upstream MIT license and history. Current branding is KeyWeaver; bundle/preferences identifiers and storage folders deliberately retain the isolated Keyweave namespace.

The target remains useful Cotypist capabilities, including Pro/Labs writing features, implemented independently and verified with synthetic acceptance scenarios. Vendor claims, source implementation, observed behavior and measured quality are separate evidence.

## Current state — 2026-10-30

- Public repository: https://github.com/DevAnuhas/keyweave.
- Gate 0 PRs #3–#6, bootstrap PR #2 and AX-fallback PR #7 are merged. Native isolation tests, synthetic launch and Settings reopening evidence are in [implementation reports](docs/README.md).
- Preview line: `0.1.0`/build `12`, tag `v0.1.0-preview.1`, Apple Silicon/macOS 14+. It introduces original app/logo/menu artwork and a Developer ID/notarization pipeline. Actual signed/stapled artifacts and receipts establish release acceptance; see the [verification report](docs/implementation/keyweaver-preview.md), [runbook](docs/runbooks/releasing.md) and GitHub release notes.
- Input monitoring/suggestions, context capture, clipboard context, writing memory, sync, login registration and automatic updates remain off. The preview is not a usable daily autocomplete build. Existing explicit manual model actions remain available; a model download does not enable suggestions.
- Isolated bundle ID is `dev.anuhas.keyweave`. No automatic upstream data access/migration, global macOS preference write, model resume or OCR diagnostic is permitted. [Gate 0 boundary](docs/implementation/gate0-isolation.md).
- The shared context-source reader now allows eligible AX text without Screen Recording and skips OCR entirely when denied. Its production wiring is tested with synthetic readers; enabled live AX/OCR acquisition remains unverified. [AX fallback evidence](docs/implementation/ax-context-fallback.md).
- Existing model, personalization, instructions, mid-line, alternatives, synonyms and sync implementations are retained. Verify concrete gaps instead of rebuilding them.
- Cotypist history is incomplete. Preserve [coverage gaps](docs/research/COTYPIST-HISTORY.md); no feature-parity certification exists. Current target Pro/Labs behavior and REA attachment to the running Codex thread remain unresolved.

## Next correctness boundaries

Fail closed on capture app/window identity before enabling capture; then fix clipboard ownership/restoration, stale picker/selection identity, alternatives spacing and key lifecycle. Activation of retained services needs effective-consent and controlled-host evidence. Do not enable a service merely to make a preview look functional.

Keep Cotypist binaries/assets, personal writing, credentials, private notary receipts and analysis outside public git. Cotypist decompilation remains outside the authorized scope. No paid service or purchase is authorized by the release task.
