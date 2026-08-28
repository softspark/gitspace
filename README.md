# gitspace

Oh My Zsh plugin that binds git identity to a directory — each workspace gets its
own commit e-mail, `gh` account and SSH key. A mismatch is a hard error, never a
silent fallback to whatever git would have guessed.

## Why

Working across several GitHub accounts and a private GitLab, the failure mode is
not dramatic: a commit gets signed with the wrong address and nobody notices until
it is pushed to someone else's repository. `gitspace` makes that impossible to do
by accident, on three independent layers:

1. **No global identity.** `user.useConfigOnly=true` and no global `user.email`,
   so git refuses to guess from `username@hostname`.
2. **Hooks.** `pre-commit` and `pre-push` verify e-mail, SSH alias and the active
   `gh` account against the workspace the repository sits in.
3. **URL rewriting.** `url.<alias>.insteadOf` forces every remote in a workspace
   onto that workspace's key. This layer is enforced server-side, so it holds even
   when the hooks are bypassed with `--no-verify` or overridden by husky.

## Install

```zsh
git clone git@github.com:softspark/gitspace.git \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/gitspace
```

Add `gitspace` to `plugins=(...)` in `~/.zshrc`, open a new shell, then:

```zsh
gitspace install
```

That writes the hooks to `~/.config/git/hooks`, creates
`~/.config/git/workspaces.conf` and sets `user.useConfigOnly`. It never
overwrites an existing config.

## Use

Register a workspace and bind an e-mail to it:

```zsh
gitspace add ~/Workspace/Acme \
  --email dev@acme.com \
  --gh acme-dev \
  --alias github-acme,gitlab-acme \
  --name "Jane Doe"
```

`--email` is the only required flag. The path may be anywhere; workspaces are
matched by longest path prefix, so nested workspaces resolve correctly.

The SSH aliases must already exist in `~/.ssh/config`:

```
Host github-acme
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_acme
    IdentitiesOnly yes
```

`gitspace add` refuses to register a workspace naming an alias that does not
exist — a missing alias would silently fall back to the default key.

### Commands

| Command | Effect |
|---|---|
| `gitspace install` | hooks, config template, global settings |
| `gitspace add <path> --email <addr>` | register a workspace |
| `gitspace list` | show registered workspaces |
| `gitspace doctor` | verify the whole setup, exit 1 on problems |
| `gitspace remove <name>` | unregister (leaves files on disk) |
| `wclone <url> [dir]` | clone with the key the target directory implies |

### wclone

Paste a URL in any form — `git@host:group/repo.git`, `https://host/group/repo`,
or `alias:group/repo`. `wclone` derives the host, picks the workspace alias whose
`HostName` matches, switches the `gh` account, verifies access with `git ls-remote`
and only then clones. Nested GitLab groups are supported.

It refuses, rather than guessing, when the target lies outside every workspace,
when the workspace has no alias for that host, or when the key cannot reach the
repository.

## Entering a directory

The `chpwd` hook prints the identity in force and switches the `gh` account when
needed. It reads the account back after switching and reports the actual state, so
a failed switch is visible rather than assumed:

```
> Acme - commity jako dev@acme.com
   konto gh: acme-dev
```

## Configuration format

`~/.config/git/workspaces.conf`, one workspace per line:

```
name|path|email|gh-account|ssh-alias[,ssh-alias...]
```

The `gh-account` field may be empty for workspaces that do not use GitHub. State
lives outside the plugin directory on purpose: deployment tooling may delete and
re-clone the plugin, and configuration must survive that.

## Known limits

- `git commit --no-verify` bypasses the hooks. Layer 3 still applies on push.
- A repository setting its own `core.hooksPath` (husky does this on
  `npm install`) overrides the hooks for that repository. Layer 3 still applies.
- Matching is by path prefix, so a workspace nested inside another must be
  registered separately to win over its parent.

## License

Apache-2.0
