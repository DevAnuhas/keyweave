# Keyweave

## Direction

A free, local-first macOS writing-autocomplete application, developed from [nilava/TabType](https://github.com/nilava/TabType). Keyweave is the working name, not a trademark-cleared brand. Preserve TabType attribution and its MIT license.

The target is the useful behavior of the complete current Cotypist feature set, including Pro and Labs, with independently written changes and explicit verification. Public changelogs define research questions and regression scenarios, not proof of the installed binary's behavior.

## Current state

- Public fork: https://github.com/DevAnuhas/keyweave
- Upstream source baseline: `b75ea0e22bc565e57b133b2625a49d7e8a24c789` on `main`.
- Latest upstream downloadable baseline inspected: v2.1.0, commit `6ffca7c56f231aed1ed3eacd635561f0b9813d4b`.
- The inherited source already contains OCR/clipboard context, writing personalization, instructions, mid-line completion, alternatives, selected-text replacements and encrypted cross-Mac sync. Validate those paths rather than treating them as new work.
- This bootstrap adds guidance, a partial official release-history index and a research/build handoff. It does not rename the executable, change its behavior, establish runtime parity, or produce a Keyweave release.
- The recovered official notes expose four version identities across two note bodies, not the full lifetime archive. Preserve the [coverage gaps](docs/research/COTYPIST-HISTORY.md).
- Cotypist's published terms prohibit modification/decompilation. That research phase requires written permission or qualified legal clearance for the intended scope; public-document and normal UI-behavior research can proceed meanwhile.
- Native implementation, target-app investigation and Mac acceptance must run on macOS. No Mac build or Cotypist binary analysis has been performed by this bootstrap.

## First executable outcome

Isolate the fork's identity, updater and stored data before running it. Then reproduce the inherited app on synthetic fixtures, study Cotypist feature-by-feature, and implement the verified gaps in small reviewable slices. See [the milestone](docs/MILESTONE.md) and [identity requirements](docs/FORK-IDENTITY.md).

## Open prerequisites

- Actual installed Cotypist version/build and authorized plan capabilities.
- Local native-analysis engine availability and REA readiness.
- Target-app/macOS/language acceptance matrix and measured baseline.
- Developer ID/notarization capability for a distributable build. A self-signed development certificate is not Apple notarization.

Do not turn an unknown into a silent scope cut or a parity claim. The [research map](docs/research/README.md) owns evidence and coverage limits.
