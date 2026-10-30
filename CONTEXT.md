# KeyWeaver

## Direction

A free, local-first macOS writing-autocomplete application developed from [nilava/TabType](https://github.com/nilava/TabType). Preserve the upstream MIT license and history. Current branding is KeyWeaver; bundle/preferences identifiers and storage folders deliberately retain the isolated Keyweave namespace.

The target remains useful Cotypist capabilities, including Pro/Labs writing features, implemented independently and verified with synthetic acceptance scenarios. Vendor claims, source implementation, observed behavior and measured quality are separate evidence.

## Current state — 2026-10-30

- Public repository: https://github.com/DevAnuhas/keyweave.
- Gate 0 PRs #3–#6, bootstrap PR #2 and AX-fallback PR #7 are merged. Native isolation tests, synthetic launch and Settings reopening evidence are in [implementation reports](docs/README.md).
- Current release target: `2.2.0`/build `13`, normal `v2.2.0` GitHub release marked Latest, continuing inherited `2.1.0`. The `v0.1.0-preview.1` release/tag were withdrawn. See [2.2.0 verification status](docs/implementation/keyweaver-2.2.0.md) and the [release runbook](docs/runbooks/releasing.md); signed/notarized distribution and controlled writing evidence are recorded there.
- Core input monitoring is enabled. Launch opens Setup, reopening shows the cached Settings window, Accessibility permission gates monitoring, and the selected installed KeyWeaver model loads once at startup. Readiness requires an active input monitor and loaded model. No automatic model download/resume or remote catalog refresh is restored.
- Optional screen/clipboard context, writing memory, sync, login registration and automatic updates remain off. Existing manual model actions remain available. The full native run with an approved external GGUF model completed 209 cases (203 passed, six skipped, zero failures). Final Release signing/notarization, visible setup and synthetic typing/Tab acceptance passed.
- Isolated bundle ID is `dev.anuhas.keyweave`. No automatic upstream data access/migration, global macOS preference write, model resume or OCR diagnostic is permitted. [Gate 0 boundary](docs/implementation/gate0-isolation.md).
- The shared context-source reader now allows eligible AX text without Screen Recording and skips OCR entirely when denied. Its production wiring is tested with synthetic readers; enabled live AX/OCR acquisition remains unverified. [AX fallback evidence](docs/implementation/ax-context-fallback.md).
- Existing model, personalization, instructions, mid-line, alternatives, synonyms and sync implementations are retained. Verify concrete gaps instead of rebuilding them.
- Cotypist history is incomplete. Preserve [coverage gaps](docs/research/COTYPIST-HISTORY.md); no feature-parity certification exists. Current target Pro/Labs behavior and REA attachment to the running Codex thread remain unresolved.

## Next correctness boundaries

Core startup and the controlled local-completion journey are verified for 2.2.0. Next, fail closed on capture app/window identity before enabling capture; fix clipboard ownership/restoration, stale picker/selection identity, alternatives spacing and key lifecycle. Activation of optional retained services needs effective-consent and controlled-host evidence.

Keep Cotypist binaries/assets, personal writing, credentials, private notary receipts and analysis outside public git. Cotypist decompilation remains outside the authorized scope. No paid service or purchase is authorized by the release task.
