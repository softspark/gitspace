---
title: "SOP: Pre-Commit Quality Gate"
category: procedures
section: procedures
service: gitspace
tags: [sop, quality-gate, pre-commit, shellcheck, tests]
version: "1.0.0"
created: "2026-08-28"
last_updated: "2026-08-28"
description: "Checks that must pass before every commit to gitspace."
---

# SOP: Pre-Commit Quality Gate

Run before every commit. CI runs the same checks, but finding a failure locally
costs seconds instead of a round trip.

## Checklist

- [ ] `shellcheck lib/guard.sh lib/pre-commit lib/pre-push tests/run.sh` — 0 findings
- [ ] `node --check bin/gitspace-install.mjs` — parses
- [ ] `zsh -n gitspace.plugin.zsh && zsh -n _gitspace` — parse
- [ ] `./tests/run.sh` — all pass
- [ ] No secrets in staged files (tokens, keys, real addresses in fixtures)
- [ ] Conventional commit message (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`)
- [ ] Branch named `feat/`, `fix/`, `refactor/`, `docs/` or `test/`
- [ ] Behaviour change reflected in README and CHANGELOG (doc-drift rule)

## Quick run

```bash
shellcheck lib/guard.sh lib/pre-commit lib/pre-push tests/run.sh \
  && node --check bin/gitspace-install.mjs \
  && zsh -n gitspace.plugin.zsh && zsh -n _gitspace \
  && ./tests/run.sh
```

## Notes

Never pass `--no-verify`. gitspace exists to stop commits that bypass identity
checks; bypassing its own gates while developing it is not a defensible
exception.

The test suite builds a throwaway `HOME`. If a test starts touching the real
`~/.gitconfig`, that is a bug in the test, not a reason to skip it.

The suite is the only place several past defects would have been caught: the
symlinked-path mismatch, the missing `user.name` under `useConfigOnly`, and the
literal `\t` written into generated git config. Add a failing test before the
fix, not after.
