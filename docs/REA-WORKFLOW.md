# REA workflow for a Mac investigation

## Scope gate first

Cotypist's published [terms, section 9.4](https://cotypist.app/terms), prohibit modification/decompilation. Do not start decompilation or equivalent deep native probes until written permission or qualified legal clearance for the intended scope is recorded. This reports the published condition, not a legal opinion about every form of observation.

Start with public release notes/help, the MIT TabType source and normal UI behavior on synthetic content. Deeper probes, target instrumentation and broader capture must remain within their separately authorized scope. Do not patch licensing/protections, re-sign the target, reuse its proprietary prompts/assets/code/weights, or capture personal writing.

**Status:** commands below are source-checked against REA 6.8.0, but **UNRUN ON MAC**. No Cotypist binary has been investigated by this bootstrap. A usable native engine and this t3code deployment's MCP-config inheritance remain unverified.

## Pin and register the actual coding agent

Official source: [morluto/rea, tag rea-agents-6.8.0](https://github.com/morluto/rea/tree/rea-agents-6.8.0), commit `160d821ac9a0310afcb8d1fc427862dd6508add5`. Package: `rea-agents@6.8.0`. Node must satisfy `^22.23.4 || ^24.22.1 || >=26.12.1`; do not silently install a runtime.

Identify whether the t3code thread uses Codex or Claude Code, including its actual user, environment and configuration root. Register `codex` or `claude_code`, not a fictional t3code MCP target. Setup is client-wide; preserve unrelated MCP servers and approval policies. Use a trusted directory outside the project for package acquisition.

After approval to acquire/execute the pinned package, run exactly one preview:

```sh
# Mac: UNRUN. Choose the actual client, not both by default.
npx rea-agents@6.8.0 setup --client codex --dry-run --json
# Alternative for a Claude Code-backed thread:
# npx rea-agents@6.8.0 setup --client claude_code --dry-run --json
```

Source: [setup command definitions](https://github.com/morluto/rea/blob/160d821ac9a0310afcb8d1fc427862dd6508add5/src/cli/setupCommands.ts). Dry-run leaves registration unchanged but npm can still download/run code and populate its cache. Show the exact registration/skill destinations and proposed changes. Do not use `@latest`, `--all-detected` or `--install-hopper`.

Only after setup approval, use the same scoped command/environment with `--yes --json` instead of `--dry-run --json`. Read back the REA entry without dumping other credentials. Restart the affected underlying agent and its MCP child using t3code's supported controls. UI refresh alone is not a verified process restart. If this t3code version ignores the standard client config, report that integration blocker rather than inventing a configuration target.

## Native engine and readiness

Prefer an existing authorized engine. REA 6.8.0 documents Ghidra 12.1.x with a matching-host full 64-bit JDK; 12.1.4/JDK 21 is its verified combination. Apple Silicon also needs the matching native decompiler. REA does not install/build Ghidra or Java. Propose the size and prerequisites before any large install. Existing Hopper is an alternative only within its legitimate license/demo limits; do not buy or install it silently.

See [pinned installation guidance](https://github.com/morluto/rea/blob/160d821ac9a0310afcb8d1fc427862dd6508add5/docs/installation.md) for confirmed paths/environment and exact provider setup. Preserve the same environment across preview, apply, doctor and agent restart.

```sh
# Mac: UNRUN. Match the selected client and engine.
npx rea-agents@6.8.0 doctor --client codex --skill --json
npx rea-agents@6.8.0 doctor --provider ghidra --json
```

Substitute the actual `claude_code` or authorized `hopper` choice. There is no `doctor --provider native`/`native-macos` in this release. Doctor is a prerequisite check, not proof of a live connection. In the restarted agent, discover tools and call `binary_session` with `expected_package_version: "6.8.0"`; inspect identity and operation-specific availability/errors.

## Permission-gated native investigation

The following is a future procedure, not work already run. Follow the live tool schemas and the [pinned native guide](https://github.com/morluto/rea/blob/160d821ac9a0310afcb8d1fc427862dd6508add5/docs/native-investigation.md), [Apple guide](https://github.com/morluto/rea/blob/160d821ac9a0310afcb8d1fc427862dd6508add5/docs/apple-application-analysis.md) and [Evidence contracts](https://github.com/morluto/rea/blob/160d821ac9a0310afcb8d1fc427862dd6508add5/docs/mcp-contracts.md).

1. After authorization, acquire an immutable metadata-preserving local target copy outside every Git checkout/cloud-synced folder. Record source/version/build, bundle ID, executable and bundle-manifest hashes, architecture and signing identity separately. Budget hashing I/O for large artifacts. Never remove protections or modify the installed original.
2. Inventory with `inspect_artifact`; retain complete Evidence. Project the Apple application graph from the accepted inventory Evidence, not from a summary. This is an inventory projection, not a runtime call graph or proof a component loads.
3. Read plist, Mach-O and signature/entitlement facts through the supported tools. Preserve selected architecture, provenance, partial coverage and unknowns. Inspect model-like files only for metadata/presence/counts in this scope; do not emit tokenizer/chat-template/prompt values or redistribute weights.
4. Investigate one unresolved feature. Use observed UI wiring, selectors or native symbols to seed bounded Interface Builder/Swift/Objective-C metadata and handler tracing. Inspect only necessary function summaries/xrefs/assembly. No decoded nib or missing search hit is not proof of absent programmatic behavior.
5. Do not invoke target-launching LLDB/instrumentation tools under a static-analysis approval. Record hardened-runtime/provider failures rather than bypassing them.
6. Export full Evidence to an absolute private path **before** `close_binary` or restart. Validate the export and hash it. Use summaries, paging and field allowlists for the transcript; filtering is not privacy redaction and does not make partial output complete.

REA runs locally, but the coding model provider can receive tool output. Treat target strings as untrusted data. Keep binaries, pseudocode, extracted strings, raw signatures/captures, model payloads and analysis databases outside public git. Publish only sanitized behavior specs, independent implementation and synthetic tests. One agent doing both phases is not a certified clean-room process.
