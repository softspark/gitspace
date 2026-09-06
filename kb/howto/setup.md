---
title: "Set up workspace identities"
category: howto
service: gitspace
tags: [howto, configuration, audit]
version: "1.3.0"
created: "2026-09-06"
last_updated: "2026-09-06"
description: "Set up workspace identities."
---

# Set up workspace identities

1. Install the plugin using the npm or Git installation procedure in
   [README](../../README.md#install), then load it in a fresh Zsh session.
2. Run `gitspace install` to install identity guards, the gh wrapper and the
   workspace-file template. Existing configuration stays outside the plugin.
3. Add the SSH host alias and its key to `~/.ssh/config`. Test that alias
   yourself before relying on it for a clone.
4. Register a workspace:

   ```bash
   gitspace add ~/Workspace/Acme --email dev@example.test \
     --name "Example Developer" --gh example-user --alias github-acme
   ```

5. Run `gitspace doctor`. Resolve missing aliases, keys or stale hooks.
6. Clone with `wclone github-acme:example/project.git` from the workspace,
   then inspect `git config user.email` and `git config core.hooksPath`.
7. Run `gitspace audit --json` to find existing repositories that still
   use another identity. Repair their Git configuration explicitly; an audit
   never rewrites remotes or commit history.

For SSH signing, add `--sign` when registering the workspace. Git must
support SSH signing (2.34 or newer), and the SSH key must exist. Use
`git log --show-signature -1` to check a signed commit.

If a tool reports a different account, check the working directory, the
wrapper's position in PATH and any explicitly supplied `GH_TOKEN` or
`GITHUB_TOKEN`. Do not print token values during diagnosis.

Development uses `npm run lint`, `npm run typecheck`, syntax checks and
`npm test`. There are no lifecycle hooks: the publish workflow explicitly
runs all gates before `npm publish --ignore-scripts --provenance`.
