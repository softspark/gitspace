# gitspace

## Overview
Oh My Zsh plugin that binds git identity to a workspace directory: per-directory
commit e-mail, `gh` account and SSH key, enforced so a wrong-account commit
fails instead of happening quietly.

## Tech Stack
- **Plugin**: zsh (Oh My Zsh custom plugin)
- **Hooks**: POSIX sh, sourced by git
- **Installer**: Node.js >= 18, ESM, no dependencies
- **Test**: bash harness against a throwaway `HOME`
- **Lint**: ShellCheck for `lib/`, `zsh -n` for zsh sources

## Commands
```bash
npm run lint        # ShellCheck over lib/
npm run typecheck   # node --check on the installer
npm test            # full suite in an isolated HOME
```

## Key Conventions
- Conventional Commits (feat:, fix:, refactor:, test:, docs:, chore:)
- Branch names: feat/, fix/, refactor/, docs/, test/
- Everything user-facing is in English
- State lives in `~/.config/git/`, never inside the plugin tree — deployment
  tooling deletes and re-clones the plugin directory
- Never `eval` config input; expand tildes by substitution
- Resolve symlinks before comparing paths: git reports physical paths
- `${${(s:,:)x}[1]}` indexes the first CHARACTER, not the first element. Assign
  to a real array first, or an alias like `github-acme` silently becomes `g`
- A check that flags everything flags nothing: `audit` compares against the
  operator's own addresses, never against every author in history
- The `chpwd` hook reaches an interactive zsh and nothing else. Anything that
  must also hold for scripts, editors and agents belongs in `lib/gh` or in git
  config, not in the plugin
- A wrapper must not shell out to find itself. `lib/gh` takes its directory from
  `${0%/*}`, never `dirname`: a stripped `$PATH` has neither, and self-detection
  that fails turns `exec` into an infinite loop. Bound any test that can hit it —
  a hanging test reports nothing and has to be killed by hand
- macOS rebuilds `$PATH` in `/etc/zprofile` via `path_helper`, which runs AFTER
  `.zshenv`. An entry that must win goes in `.zprofile` too, and re-prepends
  rather than skipping when already present: after path_helper it is present,
  just too late to matter
- Never write a git config a git might reject. `gpg.format = ssh` on git < 2.34
  fails every commit in the workspace, not just the signing

## Layout
```
gitspace.plugin.zsh   chpwd hook, wclone, gitspace command
_gitspace             completion
lib/                  guard.sh + pre-commit + pre-push, installed to ~/.config/git/hooks
templates/            workspaces.conf seed
bin/                  npm installer
tests/run.sh          test suite
```
