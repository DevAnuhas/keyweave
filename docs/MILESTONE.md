# Milestone: a safe fork and evidence-backed Cotypist parity

## Outcome

Use KeyWeave for normal writing on a Mac without losing a required Cotypist capability or damaging existing installations/data. Full parity remains a target until every required journey has evidence. A docs bootstrap, compilation or benchmark on synthetic data alone does not complete this milestone.

## 1. Establish both baselines

- Record the fork commit, installed Cotypist version/build, macOS, chip/RAM, input languages, app versions, model/quantization and enabled settings. Hash the immutable local target snapshot; do not upload it.
- Read every entry exposed by the official changelog corpus, including changes retained only in the appcast. Record archive boundaries, unavailable older releases, ambiguous dates/builds and any feed disagreement.
- Deduplicate history into current capabilities and relevant regression scenarios. Every changelog item gets a disposition: current feature, historical fix, superseded behavior, distribution prerequisite, irrelevant to the current target, or unresolved. Historical fixes are not automatically independent new features.
- Build a feature matrix with columns: capability, official source/version, Cotypist observation, inherited source path, KeyWeave observation, status, acceptance test and evidence location. Use present/unverified/partial/missing/external-prerequisite explicitly.
- Validate already-present alternatives, synonyms, clipboard, OCR and sync instead of rebuilding them from marketing comparisons.

## 2. Isolate identity before running the fork

Complete [FORK-IDENTITY.md](FORK-IDENTITY.md), including own update provenance and separate user data. This is the first code slice. Keep internal module paths stable where a display/bundle change suffices.

Pass bar: an installed KeyWeave build can coexist with TabType and Cotypist; it does not alter their data, permissions, cloud records or update channels. Report the new permission prompts honestly.

## 3. Investigate, specify, implement

Use [REA-WORKFLOW.md](REA-WORKFLOW.md) for tool readiness and the explicitly permission-gated native workflow. Cotypist's published [terms, section 9.4](https://cotypist.app/terms), prohibit modification/decompilation; record written permission or qualified legal clearance before those probes. Public-document and normal UI-behavior research can proceed meanwhile. Start there and use static native investigation only for a focused unresolved mechanism within the cleared scope, not to dump the whole application.

Prioritize after the matrix, with these starting research questions:

- What does Cotypist's rich-text compatibility control change, and where do current KeyWeave insertion/rendering workarounds fail?
- Which caret/font/wrapping, delayed accessibility, fast typing, selection and focus cases behave differently in native, browser and Electron fields?
- Where do context freshness, personalization, word alternatives or selected-word/phrase replacement differ in user-visible results?
- Which model choices, languages, low-memory/battery paths and update/relaunch cases matter for the user's workflows?

For each verified gap: save a behavior specification with provenance and unknowns, add a failing regression, implement independently in the existing architecture, run focused tests and re-run the affected Mac journey. Keep proprietary pseudocode and extracted text out of committed specifications, code comments and public artifacts; use independently written behavior specs when starting an implementation thread. A single agent's research/implementation pass is not a legally certified clean-room process.

## 4. Required acceptance journeys

- Type, type through, reject and accept next word/all; repeated Tab; switch app/field/browser tab while a completion is in flight.
- Native rich text, browser input/contenteditable and Electron text; wrapping, scaling, selection and existing suffix text. No misplaced ghost or replacement of the wrong range.
- OCR/clipboard/history opt-in, opt-out, stale context, deletion, excluded apps/domains and secure fields. Synthetic secret-like text must not become persisted writing memory.
- Contextual word alternatives and selected-word/short-phrase replacements, including a selection that changes before the result returns.
- Personalization on/off/strength; custom instructions at global and app/domain scope; multilingual and input-method cases the user needs.
- Offline local inference, model download interruption, missing/unloaded model, memory pressure, sleep/wake and battery changes.
- Sync enabled/disabled and deletion across two authorized Macs, or mark the multi-Mac check unrun. One-machine unit tests do not establish cross-Mac behavior.
- Fork-only update source, invalid checksum/signature/publisher, failed install and recovery. Never update from TabType or Cotypist releases.

## 5. Quality and distribution gates

Compare acceptance/correction rate, wrong suggestions, latency and memory on the same tasks with settings/model differences disclosed. Do not copy unsupported performance claims or present a larger model as proof of better suggestions.

Use the inherited test/eval tooling after inspecting its real commands. Mac builds and actual app tests must return real output. Notarization requires a verified Developer ID capability; do not purchase accounts, use paid APIs or publish a release without explicit authorization. Small implementation PRs remain draft until reviewed.

## Not building

No cloud inference, telemetry backend, subscription bypass, copied branding or wholesale rewrite of working upstream code. No claim that an arbitrary custom prompt substitutes for a missing user-facing feature. No public redistribution of Cotypist binaries, proprietary code/prompts/assets or raw personal evidence.
