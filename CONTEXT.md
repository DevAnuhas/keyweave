# KeyWeave

A free, local-first macOS writing assistant forked from [TabType](https://github.com/nilava/TabType). The goal is useful Cotypist capabilities, including Pro/Labs, implemented independently and verified rather than inferred from source or marketing.

## Current state

- Current version: `2.3.0` / build `16`, restoring opt-in login, context, learning and encrypted iCloud Drive sync. Persistent identity and storage namespaces stay unchanged.
- The installed `2.2.1` launch and core suggestions were confirmed working by the user. Startup opens Setup, requires its own Accessibility grant, and loads only an installed local model; downloads remain explicit.
- Optional services require their local controls; defaults remain off. App/domain exclusions and secure fields constrain acquisition, and consent changes invalidate in-flight/cached results. Sync cannot grant privacy consent from another Mac. Automatic app updates, remote catalog refresh and model-download resume remain disabled. Full Pro/Labs parity is unfinished.
- Bundle/preferences ID `dev.anuhas.keyweave` and isolated storage, Keychain and iCloud namespaces stay unchanged. Never automatically access or migrate TabType/Cotypist data.
- Captures bind to a specific window/field, clipboard restoration preserves newer copies, and erasure generations prevent stale sync payloads restoring deleted writing. Synthetic two-peer sync tests do not establish live cross-Mac iCloud delivery; broad host compatibility and remaining picker behavior still need verification.

## References

- [Milestone](docs/MILESTONE.md), [fork isolation](docs/FORK-IDENTITY.md), [research](docs/research/README.md), [release instructions](docs/runbooks/releasing.md).
- [Gate 0 verification](docs/implementation/gate0-isolation.md) and [AX fallback](docs/implementation/ax-context-fallback.md).

Preserve upstream MIT attribution. Keep personal writing, proprietary app material, credentials and raw platform receipts outside git. No paid services, purchases or Cotypist decompilation are authorized.
