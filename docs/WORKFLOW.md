# Workflow

Use one long-lived branch, `main`, and focused `docs/*`, `feat/*` or `fix/*` branches. Keep upstream changes separate from fork-specific behavior where practical.

1. Fetch the fork and `https://github.com/nilava/TabType` before starting. Read `AGENTS.md`, `CONTEXT.md` and the current issue/PR. Preserve unrelated work and inspect existing worktrees.
2. Use a focused issue with the problem, outcome, evidence and a few observable acceptance criteria. A source claim is not a reproduced bug.
3. Work in a separate worktree/branch. Add regression tests before behavior changes and keep upstream MIT/third-party notices.
4. Open a draft pull request **against `DevAnuhas/keyweave`**, not the upstream project. List actual tests, Mac journeys not run, raw-evidence locations kept outside git, and the affected capability-matrix rows.
5. Record test counts/logs/SHAs in the PR or a local evidence record, not as growing appendices in canonical agent guidance.
6. Stop before merge or publication unless explicitly authorized. A request to build is not permission to publish a release or spend on signing/tools/API calls.

These are repository conventions, not a claim that GitHub branch protection or required status checks are configured. Inspect actual workflows and protection before relying on them. An inherited workflow is not proof of a successful fork run.

## Upstream synchronization

Keep `origin` pointed at this fork and `upstream` at TabType. Review upstream diffs before integrating. Do not overwrite fork changes with a reset, rewrite upstream history, or send raw reverse-engineering evidence upstream. Preserve a source attribution when adapting an MIT implementation.
