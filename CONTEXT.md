# KeyWeave

A free, local-first macOS writing assistant forked from [TabType](https://github.com/nilava/TabType). The goal is useful Cotypist capabilities, including Pro/Labs, implemented independently and verified rather than inferred from source or marketing.

## Current state

- Current version: `2.2.2` / build `15`, with the product name **KeyWeave** throughout the app and installer. Native tests and ordinary installed launch/Settings reopening pass; distribution uses Developer ID signing and notarization.
- The installed `2.2.1` launch and core suggestions were confirmed working by the user. Startup opens Setup, requires its own Accessibility grant, and loads only an installed local model; downloads remain explicit.
- Screen/clipboard context, screenshot appearance capture, writing memory, sync, login registration and automatic updates remain disabled. Instructions, mid-line completion, alternatives and synonyms are retained; full Pro/Labs parity is unfinished.
- Bundle/preferences ID `dev.anuhas.keyweave` and isolated storage, Keychain and iCloud namespaces stay unchanged. Never automatically access or migrate TabType/Cotypist data.
- Before enabling optional services, fix capture app/window identity, clipboard ownership, stale picker selections and sync deletion behavior. Live AX/OCR and cross-Mac sync remain unverified.

## References

- [Milestone](docs/MILESTONE.md), [fork isolation](docs/FORK-IDENTITY.md), [research](docs/research/README.md), [release instructions](docs/runbooks/releasing.md).
- [Gate 0 verification](docs/implementation/gate0-isolation.md) and [AX fallback](docs/implementation/ax-context-fallback.md).

Preserve upstream MIT attribution. Keep personal writing, proprietary app material, credentials and raw platform receipts outside git. No paid services, purchases or Cotypist decompilation are authorized.
