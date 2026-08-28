# Contributing to gitspace

Thanks for wanting to help. gitspace is small on purpose — it guards git
identity and does nothing else — so the bar for new surface area is high, and
the bar for correctness is higher.

## Workflow

1. Fork, then branch from `main`
2. Make the change, with a test that fails without it
3. Run the gates below
4. Open a PR against `main`

## Branch Naming

| Prefix | Use |
|--------|-----|
| `feat/` | New feature |
| `fix/` | Bug fix |
| `refactor/` | No behavior change |
| `docs/` | Documentation only |
| `test/` | Tests only |

## Commit Conventions

[Conventional Commits](https://www.conventionalcommits.org/). Subject under 72
characters, one logical change per commit. Never pass `--no-verify`; if a hook
fails, fix the cause. Never add AI co-authorship trailers.

## CI Requirements

Everything below must pass locally before you open a PR:

```bash
shellcheck lib/guard.sh lib/pre-commit lib/pre-push tests/run.sh
node --check bin/gitspace-install.mjs
zsh -n gitspace.plugin.zsh && zsh -n _gitspace
./tests/run.sh
```

The suite builds a throwaway `HOME` and never touches your real git config.

## Coding Standards

**Never `eval` anything read from configuration.** Tilde expansion is done by
string substitution for this reason.

**Resolve symlinks before comparing paths.** `git rev-parse --show-toplevel`
returns a physical path; a configured path that traverses a symlink will not
match otherwise. This has already been a bug once.

**`print -r --` does not interpret `\t`.** Use `$'\t'` when generating git
config, or you will write a literal backslash-t and break the user's
`~/.gitconfig`. This has also already been a bug once.

**Do not name a zsh variable `path`.** It is tied to `$PATH`; a `local path`
silently destroys the command search path inside the function.

**`user.useConfigOnly` needs a name as well as an address.** Writing only
`user.email` produces "Author identity unknown" at commit time — an error that
never mentions gitspace. Anything generating a workspace config must fill in a
name.

**Report the state you observed, not the state you intended.** After a
`gh auth switch`, read the account back before printing it. A message that
claims success while the switch failed is worse than no message.

**Guards fail loudly or not at all.** No silent fallbacks, no "best effort"
defaults. If gitspace cannot determine the right identity, it must refuse.

## What to Contribute

Good first contributions:
- Additional `gitspace doctor` checks
- Completion improvements
- Support for a forge beyond GitHub and GitLab

Open an issue first for:
- New commands or flags
- Changes to the `workspaces.conf` format
- Anything that relaxes a guard

## Security

No secrets in code, tests or fixtures. Never log a token or a key path. See
[SECURITY.md](../SECURITY.md); report vulnerabilities to biuro@softspark.eu
rather than in a public issue.
