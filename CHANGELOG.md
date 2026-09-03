# Changelog

All notable changes to `@softspark/gitspace` are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## v1.2.0 -- the gh account follows the directory everywhere (2026-09-03)

### Added
- **A `gh` wrapper, so the account is right in shells the hook cannot reach.**
  Binding the account on `chpwd` only ever worked in an interactive zsh. A
  script, an editor or a coding agent got whatever account was last made active
  — and because that is global state shared by every terminal, switching
  accounts to open a pull request in one window silently repointed the others.

  `~/.config/git/bin/gh` decides at the point of use and switches nothing: gh is
  handed the bound account's token through `GH_TOKEN` for one process. Two
  terminals in two workspaces stop fighting, and a shell that never sourced the
  plugin still gets the right identity.

  `gitspace install` puts the directory on `$PATH` through **both** `~/.zshenv`
  and `~/.zprofile`. Both are needed: `.zshenv` is the only file a
  non-interactive zsh reads, and macOS rebuilds `$PATH` in `/etc/zprofile`
  afterwards, which would otherwise leave the wrapper behind the gh it shadows.
  `doctor` checks the thing that actually matters — whether `gh` resolves to the
  wrapper in this shell.

  Every uncertainty passes the call through untouched: no config, no workspace,
  no account bound, no token, a `gh auth` subcommand, or a `GH_TOKEN` the caller
  set. `gh auth` is excluded deliberately — `switch` refuses to run while
  `GH_TOKEN` is set, and `status` would report the token's account as the active
  one, turning the command people use to check their identity into a lie.

### Fixed
- **`--sign` no longer bricks a workspace on git older than 2.34.** ssh signing
  arrived in 2.34; before it, `gpg.format = ssh` is rejected outright. The
  setting lands in the workspace's include file, so it did not fail at signing
  time but at *every* commit, with `fatal: bad config variable` pointing at a
  file the user never wrote. `add --sign` now refuses and names the version it
  found, and `doctor` reports a workspace whose signing this git cannot honour —
  the case where it was registered on another machine.
- `skip` was called in three places and defined in none. Nothing reached it
  until the signing tests learned to take the other path.

### Changed
- Workspace resolution moved to `lib/resolve.sh`, which has no side effects.
  Sourcing `guard.sh` runs git and exits on a mismatch, which is right for a
  hook and useless to anything else needing the same answer.

---

## v1.1.1 -- doctor notices stale hooks (2026-08-28)

### Fixed
- **`doctor` compares the installed hooks against the plugin source.** The plugin
  directory is often a symlink to a checkout and therefore always current, while
  the hooks in `~/.config/git/hooks` are copies made by `gitspace install`. That
  asymmetry hid staleness: every check passed while the guards ran code from an
  earlier release. Found on a real installation where the installed `guard.sh`
  predated the symlink-resolution fix by two releases — a workspace behind a
  symlink would not have matched, and nothing said so.

---

## v1.1.0 -- Proven identity, not just declared (2026-08-28)

### Added
- **SSH commit signing per workspace** -- `gitspace add --sign` signs commits and
  tags with that workspace's own SSH key, registers the public key in
  `~/.config/git/allowed_signers`, and leaves `git log --show-signature` able to
  verify locally rather than only on the forge. Off unless asked for: enabling it
  by default would change behaviour for every existing workspace.
- **`gitspace audit`** -- walks the repositories on disk and reports remotes that
  bypass the workspace's aliases and commits authored under another workspace's
  address. `--deep` walks full history; `--limit N` bounds the cheap pass.
- **Key-existence checks in `doctor`** -- an alias whose `IdentityFile` is absent
  used to pass every check and fail only at push time. `doctor` now reports a
  missing private key, a missing `.pub` (which signing needs), and an alias with
  no `IdentityFile` at all.
- **Signing consistency checks in `doctor`** -- the workspace flag, `gpgsign` in
  the generated config, and the `allowed_signers` entry must agree; any two out
  of three is a signature that will not verify.

### Changed
- `workspaces.conf` gains an optional sixth field carrying the signing flag.
  Rows written by 1.0.0 keep working: an absent field means signing is off.
- `gitspace audit` compares against the operator's *own* workspace addresses.
  Flagging every third-party author produced sixty lines of noise on a real tree
  and one line of signal; the narrow question is the useful one.

---

## v1.0.0 -- Initial public release (2026-08-28)

Published to the public npm registry with SLSA provenance. An identical build
was first published privately to GitHub Packages for internal validation, per
the two-phase release standard; that phase could not carry provenance, since npm
only attests packages published with public access.

### Added
- **Per-directory git identity** -- `gitspace add <path> --email <address>` binds a
  commit e-mail, `gh` account and SSH aliases to a workspace directory, writes
  `~/.gitconfig-<name>` and wires the `includeIf` into `~/.gitconfig`.
- **Three enforcement layers** -- `user.useConfigOnly` with no global e-mail,
  `pre-commit`/`pre-push` hooks, and `url.<alias>.insteadOf` rewriting that the
  remote enforces server-side.
- **Path-prefix workspace resolution** -- workspaces may live anywhere, and a
  nested workspace wins over its parent by longest matching prefix.
- **`wclone`** -- clones from any URL form, derives the host, picks the workspace
  alias whose `HostName` matches, switches the `gh` account and verifies access
  with `git ls-remote` before cloning. Nested GitLab groups supported.
- **`gitspace doctor`** -- verifies hooks, global settings, per-workspace configs,
  `includeIf` wiring, SSH aliases and `gh` login state.
- **Directory announcement** -- a `chpwd` hook reports the identity in force and
  switches the `gh` account, reading the account back afterwards so a failed
  switch is visible rather than assumed.
- **Completion** -- for `gitspace` subcommands, workspace names, SSH aliases and
  `gh` accounts, and for `wclone`.
- **npm installer** -- `npx @softspark/gitspace install` links the plugin into
  Oh My Zsh and offers to add it to `plugins=(...)`. Not a postinstall hook by
  design.
