# Changelog

All notable changes to `@softspark/gitspace` are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## v1.0.0 -- Initial release (2026-08-28)

Published to GitHub Packages as a private package. Provenance attestation is
not available for private packages and is therefore not claimed; the move to the
public npm registry will add it.

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
