---
title: "Release verification on 2026-09-06"
category: procedures
service: gitspace
tags: [release, verification, provenance]
version: "1.3.0"
created: "2026-09-06"
last_updated: "2026-09-06"
description: "Published 1.3.0 verification, pre-release gates and earlier smoke evidence."
---

# Executed verification

## Published 1.3.0

Published on 2026-09-06 from commit `1112d2137a2618f8fbf1c258232dbf4afbdb81e0`.

- [Release](https://github.com/softspark/gitspace/releases/tag/v1.3.0)
- [Exact release-head CI](https://github.com/softspark/gitspace/actions/runs/34051724336): success
- [Publish workflow](https://github.com/softspark/gitspace/actions/runs/34051900056): success

Registry metadata returned the exact version and SLSA v1 provenance. A fresh
consumer lockfile installed gitspace 1.3.0, mage2x 1.4.0 and jira-mcp 1.11.0 with
scripts disabled. Cryptographic verification completed successfully:
**4 verified registry signatures and 3 verified attestations**. This is a new
verification of the released artifacts, separate from the older smoke below.

All three packages contained their expected runtime files, LICENSE and NOTICE;
tests, KB and .github were absent. Syntax checks preceded CLI execution.

The installed plugin passed help/list and JSON/SARIF audit parsing. The npm
installer created a symlink in a temporary ZSH_CUSTOM, refused an existing
real directory, and preserved the real .zshrc modification time.

## Earlier published-version smoke


The published package `@softspark/gitspace@1.2.0` was installed as an
exact dependency in a temporary npm project, with `--ignore-scripts` and a
consumer lockfile. The isolated project also contained the other two audited
CLI packages. `npm audit signatures --registry https://registry.npmjs.org`
exited 0: **4 verified registry signatures and 3 verified attestations**
(the fourth dependency is commander).

Published artifact checks passed: expected version, LICENSE, NOTICE and runtime
entry points present; tests, KB and .github absent. JavaScript/Zsh syntax
checks ran before executing CLI smoke commands.

The installer `path` command resolved the installed package. Published plugin
`help` and `list` commands succeeded with an empty temporary workspace file.
No global plugin installation, real home rewrite or live-account switch ran.
The full isolated identity/signing/gh-wrapper tests validate the candidate;
this limited published smoke does not replace a new release's installation test.

## Pre-release validation

Version 1.3.0 was validated locally before publication. Its new
audit commands are tested against real temporary filesystem/configuration
fixtures, including secret redaction and SARIF output. Existing text behavior
is retained except for documented repairs.

After publication, repeat this record against the new registry version and run
its post-release SOP. Do not carry the 1.2.0 cryptographic result forward
as evidence for a future 1.3.0 artifact.

Candidate gates on 2026-09-06: ShellCheck, installer syntax, Zsh syntax and the
full isolated suite passed (38 tests). JSON/SARIF fixtures include quoted,
backslash, tab, newline and Unicode repository paths, linked worktrees,
nested ownership, remote-token redaction and disabled fsmonitor execution.
The linked-worktree fixtures include hidden `.worktrees/` directories under
both the parent and nested workspace; each retains its owning identity.
