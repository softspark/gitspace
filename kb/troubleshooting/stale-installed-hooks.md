---
title: "Installed hooks silently lag the plugin"
category: troubleshooting
section: troubleshooting
service: gitspace
tags: [hooks, install, drift, symlink, doctor, staleness]
version: "1.0.0"
created: "2026-08-28"
last_updated: "2026-08-28"
description: "The plugin directory is often a symlink and always current, while the git hooks are copies made by gitspace install — so the guards can run code from an earlier release while every check reports success."
---

# Installed hooks silently lag the plugin

## Symptom

`gitspace doctor` reports `everything checks out`, `gitspace list` shows the
right workspaces, the shell announces the right identity on `cd` — and yet a
guard behaves like an older release. In the case that surfaced this, workspaces
reached through a symlink were not matched at all, because the installed
`guard.sh` predated the symlink-resolution fix by two releases.

Before 1.1.1 nothing reported it. `doctor` checked only that the hook files
*existed*.

## Cause

gitspace installs itself in two different ways at once, and only one of them
stays current:

| Component | How it gets there | Updates itself? |
|---|---|---|
| `gitspace.plugin.zsh`, `_gitspace` | plugin directory, frequently a **symlink** to a git checkout | yes — the symlink always points at the working tree |
| `lib/guard.sh`, `lib/pre-commit`, `lib/pre-push` | **copied** into `~/.config/git/hooks` by `gitspace install` | no |

Pulling the repository, switching branches, or checking out a new tag updates
the plugin instantly and leaves the hooks untouched. The asymmetry is what makes
it invisible: everything a person would think to check is genuinely up to date.

npm installs have the same shape. `npm update -g` replaces the package, and the
hooks copied out of the previous version stay where they are.

## Fix

```bash
gitspace install
```

It rewrites the hooks and leaves `workspaces.conf` and the global git settings
alone, so it is safe to run at any time.

## Detection

From 1.1.1, `doctor` compares each installed hook against the plugin source and
reports a mismatch:

```
hooks
  x guard.sh differs from the plugin source
  v pre-commit
  v pre-push
  run 'gitspace install' to refresh the installed hooks
```

Comparison is skipped, not failed, when the plugin source is unavailable — an
npm install whose package directory has been removed should not read as drift.

## Prevention

Run `gitspace install` after anything that changes `lib/`:

- `git pull` or a branch switch in a checkout you have symlinked
- `npm update -g @softspark/gitspace`
- editing a hook while developing the plugin

`gitspace doctor` exits non-zero on drift, so a provisioning script can gate on
it rather than relying on anyone remembering.

## Why the hooks are copies at all

Because `core.hooksPath` must point somewhere stable. Pointing it into the
plugin directory would break the moment the plugin is removed, moved, or — in
the Ansible deployment path — deleted and re-cloned, which the `ohmyzsh` role
does whenever the directory is not a git checkout. Copying is the right
trade-off; not noticing the copies had gone stale was the defect.
