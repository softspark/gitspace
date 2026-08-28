# gitspace

> Git identity bound to a directory. The wrong account fails loudly instead of
> signing a commit quietly.

[![CI](https://github.com/softspark/gitspace/actions/workflows/ci.yml/badge.svg)](https://github.com/softspark/gitspace/actions/workflows/ci.yml)
[![npm](https://img.shields.io/npm/v/@softspark/gitspace)](https://www.npmjs.com/package/@softspark/gitspace)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

## What's New in v1.0.0

- **Per-directory identity** — bind a commit e-mail, `gh` account and SSH keys to
  a workspace with one command
- **Three enforcement layers**, one of them enforced by the remote and therefore
  impossible to bypass locally
- **`wclone`** — paste any URL and it picks the right key, or refuses
- **`gitspace doctor`** — verifies the whole setup and exits non-zero on problems
- **npm installer** — `npx @softspark/gitspace install`, no postinstall hooks

See [CHANGELOG.md](CHANGELOG.md).

## Table of Contents

- [Why](#why)
- [Install](#install)
- [Update](#update)
- [Configuration](#configuration)
- [Usage](#usage)
- [Commands](#commands)
- [Architecture](#architecture)
- [Key Features](#key-features)
- [Known Limits](#known-limits)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)
- [Changelog](#changelog)

## Why

Working across several GitHub accounts and a private GitLab, the failure mode is
not dramatic. A commit gets signed with the wrong address, nobody notices, and it
surfaces weeks later in someone else's repository — or in a compliance review.

`gitspace` makes that hard to do by accident, on three independent layers:

1. **No global identity.** `user.useConfigOnly=true` and no global `user.email`,
   so git refuses to guess an identity from `username@hostname`.
2. **Hooks.** `pre-commit` and `pre-push` check the e-mail, the SSH alias and the
   active `gh` account against the workspace the repository sits in.
3. **URL rewriting.** `url.<alias>.insteadOf` forces every remote in a workspace
   onto that workspace's key.

The third layer is the one that matters. Hooks can be skipped with `--no-verify`
and overridden by tools that set their own `core.hooksPath`; the key separation
is enforced by the remote, so a push to a repository your workspace key cannot
reach fails no matter what happens locally.

## Install

### From git

```bash
git clone https://github.com/softspark/gitspace.git \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/gitspace"
```

### From the package registry

`@softspark/gitspace` currently publishes to **GitHub Packages**, which requires
authentication even for reading. Add to `~/.npmrc`:

```
@softspark:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=<a GitHub token with read:packages>
```

Then:

```bash
npx @softspark/gitspace install
```

That links the plugin into `$ZSH_CUSTOM/plugins/gitspace` and offers to add
`gitspace` to `plugins=(...)` in `~/.zshrc` (a backup is written first; pass
`--yes` to skip the prompt). Nothing runs behind your back — the package ships
`ignore-scripts=true` and has no postinstall hook, so installation is always an
explicit command.

For a permanent install:

```bash
npm install -g @softspark/gitspace && gitspace-install
```

### Then, either way

```bash
exec zsh
gitspace install
```

`gitspace install` writes the hooks to `~/.config/git/hooks`, seeds
`~/.config/git/workspaces.conf` and sets `user.useConfigOnly`. It never
overwrites an existing config.

**Requirements:** zsh with Oh My Zsh, git 2.13+ (for `includeIf`), Node.js 18+
for the npm installer only. [`gh`](https://cli.github.com/) is optional and used
only when a workspace binds a GitHub account.

## Update

```bash
npm update -g @softspark/gitspace && gitspace install
```

Re-running `gitspace install` refreshes the hooks; your workspaces are untouched.

## Configuration

Register a workspace and bind an e-mail to it:

```bash
gitspace add ~/Workspace/Acme \
  --email dev@acme.com \
  --gh acme-dev \
  --alias github-acme,gitlab-acme \
  --name "Jane Doe"
```

Only `--email` is required. The path may be anywhere — workspaces are matched by
longest path prefix, so a workspace nested inside another wins over its parent.

The SSH aliases must already exist in `~/.ssh/config`:

```
Host github-acme
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_acme
    IdentitiesOnly yes
```

`gitspace add` refuses to register a workspace that names an alias which does not
exist — a missing alias would silently fall back to the default key, which is the
whole failure this tool exists to prevent.

State lives in `~/.config/git/`, deliberately outside the plugin directory:
deployment tooling deletes and re-clones plugin checkouts, and configuration must
survive that.

### `workspaces.conf`

One workspace per line:

```
name|path|email|gh-account|ssh-alias[,ssh-alias...]
```

`gh-account` may be empty for workspaces that do not use GitHub.

## Usage

### Entering a directory

The `chpwd` hook reports the identity in force and switches the `gh` account when
needed. It reads the account back after switching and reports what actually
happened, so a failed switch is visible rather than assumed:

```
> Acme - committing as dev@acme.com
   gh account: acme-dev
```

### Cloning

```bash
wclone git@github.com:acme/thing.git
wclone https://gitlab.example.com/group/sub/thing.git ~/Workspace/Acme/thing
```

Paste a URL in any form — `git@host:group/repo.git`, `https://host/group/repo`,
or `alias:group/repo`. `wclone` derives the host, picks the workspace alias whose
`HostName` matches, switches the `gh` account, verifies access with
`git ls-remote` and only then clones. Nested GitLab groups work.

It refuses rather than guesses when the target lies outside every workspace, when
the workspace has no alias for that host, or when the key cannot reach the
repository.

Cloning through `wclone` rather than `git clone` matters: `includeIf` does not
apply while the repository is still being created, so a plain
`git clone git@github.com:...` would record a remote pointing at the default key.

### Checking the setup

```bash
gitspace doctor
```

Verifies hooks, global settings, per-workspace configs, `includeIf` wiring, SSH
aliases and `gh` login state. Exits non-zero when anything is wrong, so it can
gate a provisioning script.

## Commands

| Command | Description |
|---|---|
| `gitspace install` | hooks, config template, global git settings |
| `gitspace add <path> --email <addr>` | register a workspace; `--gh`, `--alias`, `--name`, `--as` optional |
| `gitspace list` | show registered workspaces |
| `gitspace doctor` | verify the whole setup, exit 1 on problems |
| `gitspace remove <name>` | unregister a workspace (files left on disk) |
| `wclone <url> [dir]` | clone with the key the target directory implies |
| `gitspace-install` | npm-side installer: link the plugin, patch `~/.zshrc` |

Completion is provided for subcommands, workspace names, SSH aliases and `gh`
accounts.

## Architecture

```
gitspace.plugin.zsh   chpwd hook, wclone, the gitspace command
_gitspace             zsh completion
lib/
  guard.sh            workspace resolution and identity check, sourced by hooks
  pre-commit          refuses a commit whose identity does not match
  pre-push            refuses a push over the wrong key or gh account
templates/
  workspaces.conf     seed copied on first install
bin/
  gitspace-install.mjs  npm installer (Node, no dependencies)
tests/run.sh          suite, runs against a throwaway HOME
```

Installed state, outside the plugin tree:

```
~/.config/git/workspaces.conf     workspace table
~/.config/git/hooks/              guard.sh, pre-commit, pre-push
~/.gitconfig-<workspace>          identity, hooksPath, URL rewriting
~/.gitconfig                      includeIf per workspace
```

## Key Features

**Path-prefix resolution.** Workspaces are matched by repository path, not by
directory name, so they can live anywhere and nest freely. Symlinks are resolved
first — git reports physical paths, and a workspace behind a symlink would
otherwise never match.

**Hook chaining.** The hooks run the repository's own `pre-commit` / `pre-push`
afterwards, so husky and friends keep working. Chaining goes through `--git-dir`
rather than `--git-path`, because the latter honours `core.hooksPath` and the
hook would exec itself forever.

**No credentials touched.** gitspace reads the *name* of the active `gh` account
and nothing else from that file. SSH keys are referenced by alias; no key file is
ever opened.

**Truthful reporting.** Every state that can fail to change is read back before
being printed.

## Known Limits

- `git commit --no-verify` bypasses the hooks. Layer 3 still applies on push.
- A repository that sets its own `core.hooksPath` (husky does this on
  `npm install`) overrides the hooks for that repository. Layer 3 still applies.
- `includeIf` does not apply during `git clone`, which is why `wclone` exists.
- Workspace matching is by path prefix; a workspace nested inside another must be
  registered separately to win over its parent.

## Contributing

See [CONTRIBUTING.md](.github/CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md). Report vulnerabilities to biuro@softspark.eu
rather than in a public issue.

## License

[Apache-2.0](LICENSE). See [NOTICE](NOTICE) for attribution requirements.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

Built by [SoftSpark](https://softspark.eu).
