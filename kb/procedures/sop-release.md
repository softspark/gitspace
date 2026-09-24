---
title: "SOP: Release Creation"
category: procedures
section: procedures
service: gitspace
tags: [sop, release, npm, provenance, supply-chain, versioning, local-gates]
version: "1.3.0"
created: "2026-08-28"
last_updated: "2026-09-24"
description: "Version bump, changelog, and the single release command that gates, tags and publishes @softspark/gitspace."
---

# SOP: Release Creation

```bash
npm run release -- X.Y.Z             # gates, Linux run, pack smoke, tag, push, watch publish
npm run release -- X.Y.Z --dry-run   # everything up to the tag, then prints the rest
```

`scripts/release.sh` is the only supported way to create a release tag. GitHub
Actions no longer tests anything: there is no CI on pushes or pull requests,
and `publish.yml` only turns a tag into an npm package and a GitHub Release. A
tag made by hand ships whatever the commit holds, gated or not. The shared model
is the SoftSpark SOP "Local Release Gates, Publish-Only CI"; this page keeps
what is specific to gitspace.

## 1. Decide the version

Semantic Versioning. The first public release is `1.0.0`; SoftSpark modules do
not ship `0.x`.

| Change | Bump |
|---|---|
| Guard becomes stricter, config format changes, command removed | major |
| New command, new check, new flag | minor |
| Bug fix, message wording, docs | patch |

A guard that starts refusing something it used to allow is a **major** bump even
though nothing in the API changed — existing setups stop working, which is the
definition of breaking.

## 2. Prepare the release commit

The script checks these; it does not write them.

```bash
npm version --no-git-tag-version X.Y.Z
```

`package.json` is the only file carrying a version; there is no companion
manifest to keep in sync.

- **CHANGELOG:** `## vX.Y.Z -- Title (YYYY-MM-DD)` with Added / Changed / Fixed /
  Removed. Latest version at the top, `---` between versions, bold feature
  names, verb-first descriptions.
- **README:** collapse any older `## What's New` block. Exactly one may exist at
  a time; history belongs in the CHANGELOG.

```bash
git commit -am "chore: release vX.Y.Z"
git push origin main
```

## 3. Release

```bash
npm run release -- X.Y.Z
```

It stops at the first failure. Logs go to `${TMPDIR:-/tmp}/gitspace-release-X.Y.Z/`.

| Step | What it checks or does |
|---|---|
| 1. Preconditions | on `main`, clean tree, `main` equals `origin/main` after a fetch, `X.Y.Z` is semver, `vX.Y.Z` exists neither locally nor on origin |
| 2. Version and notes | `package.json` is `X.Y.Z`, CHANGELOG has `## vX.Y.Z `, `HEAD` is `chore: release vX.Y.Z` |
| 3. Gates | `npm run lint` (ShellCheck over `lib/`, `tests/run.sh`, `scripts/release.sh`), `npm run typecheck`, `zsh -n` on both zsh sources, `npm test`, required files, supply-chain gates |
| 4. Linux run | the same gate in a throwaway `node:24` container, repository copied in, run as the non-root `node` user |
| 5. Build and smoke | `npm pack`; the tarball must carry `lib/`, `templates/`, `bin/`, both zsh sources, `LICENSE` and `NOTICE`; installed into a scratch prefix, `gitspace-install path` must print a directory holding the plugin |
| 6. Tag and push | lightweight tag `vX.Y.Z` on `HEAD`, push `main`, then `git push origin refs/tags/vX.Y.Z` |
| 7. Watch publish | `gh run watch` on the tag's `publish.yml` run, then `npm view @softspark/gitspace@X.Y.Z` and the GitHub Release |

**Why the Linux run applies here.** The hooks are POSIX sh, the plugin is zsh,
and the suite is bash with path handling that differs between macOS and Linux
(`/var` against `/private/var`, `path_helper`). The old CI ran the suite on both
systems for this reason. It needs Docker running.

**npm keeps NOTICE out on its own.** npm includes `LICENSE` automatically but
**not** `NOTICE`, which is why it is listed explicitly in `files` and why step 5
refuses a tarball without it. Apache-2.0 §4(d) makes carrying it an obligation.

## Supply-chain gates

npm only attests packages published with public access. Step 3 reads
`publish.yml` with comments stripped (the workflow's own prose mentions both
flags) and requires `registry-url` on `registry.npmjs.org`, `--provenance`,
`id-token: write`, and `ignore-scripts=true` in `.npmrc`. An unsigned public
release is a regression and has to be re-published.

### Record: moving from GitHub Packages to public npm

Done on 2026-08-28, ahead of the public 1.0.0. Kept because getting only some of
it right leaves the gates disagreeing with the workflow. The move touched, in
one commit:

1. `publish.yml`: `registry-url` to `https://registry.npmjs.org`, add
   `id-token: write`, publish with `--access public --provenance --ignore-scripts`,
   swap `secrets.GITHUB_TOKEN` for `secrets.NPM_TOKEN`
2. `package.json`: drop `publishConfig`
3. `README.md`: drop the GitHub Packages `~/.npmrc` block from Install
4. `sop-post-release-testing.md`: re-enable the provenance phase

Provenance is unavailable for a private package: claiming it in the workflow
fails the publish, and a reader would believe the release is attested when it
cannot be.

## What publish.yml still does

On a `v*` tag: checkout, Node setup, a check that the tag equals
`package.json`, `npm publish --access public --provenance --ignore-scripts`, and
the GitHub Release. Nothing else. The tag check stays because tagging the wrong
commit is easy and invisible until someone installs the result.

## 4. Verify

The script already confirmed the registry version and the GitHub Release. Run
`sop-post-release-testing.md` against the published package.

## Rollback

```bash
npm deprecate @softspark/gitspace@X.Y.Z "reason"
```

Deprecate rather than unpublish: npm restricts unpublishing, and consumers may
already have the version pinned. Deleting the tag does not delete what was
published; fix forward with a new patch version through the same script.
