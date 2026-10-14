---
title: "Gitspace configuration and audit"
category: reference
service: gitspace
tags: [reference, configuration, audit]
version: "1.4.0"
created: "2026-09-06"
last_updated: "2026-10-14"
description: "Gitspace configuration and audit."
---

# Configuration and audit

Load `gitspace.plugin.zsh` in Zsh. State stays outside the plugin checkout:
`~/.config/git/workspaces.conf` contains
`name|path|email|gh-account|ssh-alias[,ssh-alias...]|[sign]`.
An empty gh account is valid. The longest physical directory prefix owns a
repository, including nested workspaces and linked worktrees.
Hidden directories such as `.worktrees/` are included in traversal.

`GITSPACE_CONF` overrides the workspace file; `GITSPACE_LIB` and
`GITSPACE_BIN` select installed hook and wrapper directories. Register with
`gitspace add <path> --email <address>`; optional `--name`, `--gh`,
`--alias`, `--as` and `--sign` configure identity, routing and signing.
SSH aliases must already exist.

`gitspace install`, `add` and `remove` regenerate
`~/.config/git/routes.gitconfig` (next to `GITSPACE_CONF`, override with
`GITSPACE_ROUTES`) and include it unconditionally from `~/.gitconfig`. For
each gh account, the first workspace naming it and having a `github.com`
alias contributes `url.<alias>:<account>/.insteadOf` for
`git@github.com:<account>/` and `https://github.com/<account>/`. These rules
apply to every git on the machine, including one run with `--git-dir` outside
any workspace (a package manager's git cache). Inside a workspace they only
narrow its own rewrite, and identity stays bound to the directory. `doctor`
fails when the include is missing or the file differs from what
`workspaces.conf` produces.

The gh wrapper resolves the account at command time, passes its token only
to the invoked gh process and preserves caller-supplied tokens. It never
switches the shared active account.

## Audit contract

`gitspace audit [--deep] [--limit N] [--json|--sarif]` scans locally.
The default history window is 50 commits; `N` must be a positive integer.
`--deep` scans the complete history. It makes no network calls and changes
no Git configuration. Text remains the default.

JSON has `schemaVersion: 1`, `tool`, `scanned` and `findings`.
Each finding has `ruleId`, `level` and `repository`. SARIF uses version
2.1.0, the same rules and severities, and percent-encoded file artifact URIs.

| Rule | Severity | Meaning |
|---|---|---|
| remote-alias | error | Origin bypasses the owning workspace's aliases |
| identity-leak | error | History contains another configured identity belonging to this operator |
| dirty-worktree | warning | The working tree contains uncommitted changes |

Exit codes: 0 means no wrong remotes or identity leaks (dirty warnings alone
do not fail); 1 means either error was found; 2 means invalid arguments.
Remote URLs are omitted in all formats, preventing URL credentials from
reaching output. JSON and SARIF also omit email addresses. Repository paths
remain visible. Colleagues' addresses are never identity-leak findings.

`gitspace audit --sarif > audit.sarif` produces input for GitHub's
`github/codeql-action/upload-sarif` action (`sarif_file: audit.sarif`).
Upload even when the audit returns 1, then fail the job using that recorded
status. The report describes the machine's configured workspaces, so only
upload it to a repository where exposing those paths is intended.
