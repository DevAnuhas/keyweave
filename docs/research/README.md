# Research map

## Primary references

- [TabType upstream at the fork baseline](https://github.com/nilava/TabType/tree/b75ea0e22bc565e57b133b2625a49d7e8a24c789)
- [Upstream v2.1.0 comparison and explicit gaps](https://github.com/nilava/TabType/blob/6ffca7c56f231aed1ed3eacd635561f0b9813d4b/docs/COMPARISON.md)
- [Cotypist current Pro/Labs capability list](https://cotypist.app/pricing)
- [Cotypist compatibility](https://cotypist.app/compatibility)
- [Cotypist privacy and context controls](https://cotypist.app/help/privacy)
- [Official REA repository](https://github.com/morluto/rea) and [pinned 6.8.0 release](https://github.com/morluto/rea/releases/tag/rea-agents-6.8.0)

Read [Cotypist history coverage](COTYPIST-HISTORY.md) and the [release/version index](cotypist-releases.json) before forming the current parity matrix. The recovered archive is incomplete; do not describe it as all lifetime releases. Raw downloaded pages and target-app analysis stay in a local research directory outside public git. Source URLs and hashes are provenance; they do not prove behavior.

## Inherited capabilities to validate, not rebuild by default

- `Sources/TabType/Core/Engine.swift`: writer instructions, clipboard request context, per-app mid-line gating, alternatives and selection-replacement paths.
- `Sources/TabType/Core/ScreenContextProvider.swift` and `ContextReader.swift`: screen/accessibility context.
- `Sources/TabType/Core/Engines/LlamaEngine.swift` and `Sources/TabTypeKit/Decoding/CompletionDecoder.swift`: contextual replacement candidates and decoding.
- `Sources/TabType/Core/WritingStore.swift` and `Sources/TabTypeKit/Personalization/SuffixIndex.swift`: writing memory and personalization.
- `Sources/TabType/App/SyncManager.swift`: encrypted cross-Mac sync.
- `Sources/TabType/Core/AppPolicy.swift`, `TextInserter.swift`, `SuggestionOverlay.swift` and `AccessibilityBridge.swift`: compatibility, insertion and rendering.
- `Tests/TabTypeTests`, `Tests/TabTypeKitTests`, and `eval/README.md`: existing regression/evaluation seams.

The most concrete documented upstream omissions are notarization and a dedicated rich-text compatibility switch. Neither a toggle nor a paid signing account automatically resolves the underlying app behavior. Quality, compatibility, model/catalog coverage and current Cotypist changes remain research/acceptance questions.

## Evidence discipline

For each claim keep the target version/build/hash, source URL or local Evidence ID, reproduction steps, observation versus inference, relevant fork source path, confidence/unknowns and synthetic test. Keep vendor pseudocode/prompts and personal text out of public reports. The user-facing matrix and independent behavior specification are the bridge into implementation.
