# Working in Keyweave

Keyweave is a working-name fork of TabType. Preserve the upstream MIT notice and history. Product direction and current status live in [CONTEXT.md](CONTEXT.md); the active outcome is [docs/MILESTONE.md](docs/MILESTONE.md).

## Invariants

- Keep inference on the Mac. Do not add telemetry or cloud inference as a shortcut to quality. Screen, clipboard, writing-history and cross-Mac context require explicit, reversible controls.
- Preserve secure-field exclusion and app/domain controls. Test focus changes, stale selections, cancellation and insertion readback before expanding app support. A setting without working behavior is not a feature.
- Do not claim Cotypist parity from a README, changelog, source search or a successful build. Distinguish published claims, static implementation, reproduced behavior and measured results.
- Before running a fork build, complete the identity/update/storage isolation in [docs/FORK-IDENTITY.md](docs/FORK-IDENTITY.md). The inherited app still identifies itself as TabType.
- Proprietary app bundles, decompiler output, extracted prompts/assets, writing histories, credentials, signing keys and raw screen/clipboard captures stay outside this public repository. Use synthetic content for tests and public evidence.
- Study lawful, authorized behavior and implement independently. Do not modify Cotypist, remove licensing/tier restrictions, use its signing identity, or distribute its code, prompts, assets or model artifacts. Pause any probe whose authorization or terms are unclear; continue public-document and ordinary behavior research where appropriate.
- Keep changes focused and upstream-friendly. Do not rename all Swift modules or replace working subsystems merely to rebrand the app.

## Task map

- [Milestone and acceptance](docs/MILESTONE.md)
- [Fork identity and updater boundary](docs/FORK-IDENTITY.md)
- [Research sources and inherited capabilities](docs/research/README.md)
- [REA investigation workflow](docs/REA-WORKFLOW.md)
- [Branch and review workflow](docs/WORKFLOW.md)
- [Inherited build/test guidance](CONTRIBUTING.md)

## Verification

Use existing tests and add focused regressions before behavior changes. Read `Package.swift`, `Scripts/build.sh` and the relevant implementation before selecting commands. Record Mac builds, tests and app journeys as unrun when the host cannot execute them. Documentation checks do not prove the app works. Review raw research for private/vendor content before committing a sanitized specification.
