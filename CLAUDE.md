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

## Layout
```
gitspace.plugin.zsh   chpwd hook, wclone, gitspace command
_gitspace             completion
lib/                  guard.sh + pre-commit + pre-push, installed to ~/.config/git/hooks
templates/            workspaces.conf seed
bin/                  npm installer
tests/run.sh          test suite
```
