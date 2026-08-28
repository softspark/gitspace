# Changelog

All notable changes to `@softspark/gitspace` are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

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
