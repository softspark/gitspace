---
title: "SOP: Post-Release Testing"
category: procedures
section: procedures
service: gitspace
tags: [sop, testing, smoke-test, provenance, npm, post-release]
version: "1.0.0"
created: "2026-08-28"
last_updated: "2026-08-28"
description: "Smoke-test a published @softspark/gitspace release from npm in an isolated HOME, without disturbing the maintainer's own setup."
---

# SOP: Post-Release Testing

Run once `publish.yml` goes green. Everything happens under a throwaway `HOME`,
so a failing test cannot damage a real configuration. Open a fresh shell when
you are done — `HOME` is overridden for the duration.

## Phase 1 — isolated install

The package is public, so no token and no `~/.npmrc` are needed.

```bash
export SMOKE=$(mktemp -d)
export HOME="$SMOKE/home"
mkdir -p "$HOME"
npm install -g --prefix "$SMOKE/npm" @softspark/gitspace@X.Y.Z
```

Until 1.0.0 the package lived on GitHub Packages, where this phase needed a
token with `read:packages` **read before `HOME` was redirected** — `gh` resolves
its config from `$HOME`, so reading it afterwards yielded an empty string and a
`401` identical to a missing scope. Kept here because the same trap applies to
any private-registry smoke test.

## Phase 2 — installer

```bash
"$SMOKE/npm/bin/gitspace-install" path
ZSH_CUSTOM="$HOME/omz" "$SMOKE/npm/bin/gitspace-install" install --yes
test -L "$HOME/omz/plugins/gitspace" || echo "FAIL: plugin not linked"
```

The installer must **refuse** rather than overwrite when the target already
exists as a real directory. Replace the symlink with a directory and confirm the
second run exits non-zero.

With no `~/.zshrc` present it must say so and carry on, not fail.

## Phase 3 — plugin surface

```bash
zsh -c 'source "$HOME/omz/plugins/gitspace/gitspace.plugin.zsh"; gitspace help'
zsh -c 'source "$HOME/omz/plugins/gitspace/gitspace.plugin.zsh"; gitspace install'
zsh -c 'source "$HOME/omz/plugins/gitspace/gitspace.plugin.zsh"; gitspace list'
```

Register a workspace and confirm the identity actually reaches a repository:

```bash
zsh -c 'source "$HOME/omz/plugins/gitspace/gitspace.plugin.zsh"
        gitspace add "$HOME/ws/Demo" --email demo@example.test'
mkdir -p "$HOME/ws/Demo/r" && git -C "$HOME/ws/Demo/r" init -q
git -C "$HOME/ws/Demo/r" config user.email       # demo@example.test
git -C "$HOME/ws/Demo/r" config user.name        # must NOT be empty
git -C "$HOME/ws/Demo/r" config core.hooksPath   # ~/.config/git/hooks
```

Note the deliberate omission of `--name`. `user.useConfigOnly` refuses an
identity without a name, so `gitspace add` fills one in; an empty `user.name`
here means every commit in that workspace would die on "Author identity
unknown".

Then confirm the guard actually bites:

```bash
cd "$HOME/ws/Demo/r" && echo x > f && git add f && git commit -m t   # succeeds
git config user.email intruder@example.test && git commit -m t --allow-empty  # refused
```

## Phase 4 — supply-chain verification (mandatory)

```bash
npm view "@softspark/gitspace@X.Y.Z" --json | python3 -c \
  "import json,sys; d=json.load(sys.stdin); \
   assert d['dist']['attestations']['provenance']['predicateType']=='https://slsa.dev/provenance/v1'; \
   print('PROVENANCE OK')"
npm audit signatures --registry https://registry.npmjs.org
```

## Phase 5 — tarball contents

```bash
npm pack @softspark/gitspace@X.Y.Z --dry-run 2>&1 \
  | grep -E 'NOTICE|LICENSE|gitspace.plugin.zsh|lib/guard.sh'
```

All four must appear. A missing `NOTICE` breaks the Apache-2.0 §4(d) obligation
and is a release blocker, not a nitpick.

Also assert what must **not** ship — `.npmignore` regressions are invisible
otherwise:

```bash
for f in tests/run.sh kb CLAUDE.md SECURITY.md .github; do
  test -e "$SMOKE/npm/lib/node_modules/@softspark/gitspace/$f" \
    && echo "FAIL: should not ship: $f"
done
```

## Phase 6 — cleanup

Delete `$SMOKE` and open a new shell.

## Run log

| Version | Registry | Date | Result |
|---|---|---|---|
| 1.0.0 | GitHub Packages (private) | 2026-08-28 | 20 passed, 0 failed, 1 skipped — provenance N/A |
| 1.0.0 | public npm | 2026-08-28 | 20 passed, 0 failed, 0 skipped |

Three things this SOP learned by being run rather than written:

**The token had to move.** The private-registry run first failed on an empty
token, read after `HOME` had already been redirected. Same symptom as a missing
`read:packages` scope, different cause.

**Provenance needs a public source repository.** The first public publish failed
with `422 — Unsupported GitHub Actions source repository visibility: "private"`,
after npm had already signed the statement into the sigstore transparency log.
Every quality gate passed; only the last step failed. Flip repository visibility
*before* pushing the tag.

**A fresh package 404s for a while.** `npm publish` printed
`+ @softspark/gitspace@1.0.0` and the registry answered `404` for roughly 100
seconds. Poll rather than diagnose.
