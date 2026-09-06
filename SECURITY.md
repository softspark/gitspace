# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |

## Reporting a Vulnerability

**Do NOT open a public GitHub issue for security vulnerabilities.**

Email: biuro@softspark.eu

Response SLA: 48 hours.

Process:
1. Report via email with description and reproduction steps
2. We confirm receipt within 48 hours
3. We investigate and develop a fix
4. We coordinate disclosure and credit the reporter

## Security Design

### Credentials are scoped to the invoked gh process

The `gh` wrapper asks `gh auth token --user` for the account bound to the
current workspace and passes it through `GH_TOKEN` only to that command.
It does not switch the globally active account or save the token. Tokens
already supplied by the caller take precedence. SSH keys remain referenced
through SSH aliases. Audit JSON and SARIF omit remote URLs and email addresses.

### No network access

The plugin makes no network requests of its own. `wclone` shells out to
`git ls-remote` and `git clone`; the wrapped `gh` command makes the requests
the caller selected. The local audit does not contact remotes. There is no telemetry.

### Explicit installation

The npm package ships `ignore-scripts=true` and is published with
`--ignore-scripts`. Linking the plugin and editing `~/.zshrc` happen only when
you run `npx @softspark/gitspace install`, and the `.zshrc` edit is confirmed
interactively unless you pass `--yes`. A backup is written first.

### Config parsing

`workspaces.conf` is parsed with plain field splitting — never `eval`, and
tilde expansion is done by string substitution rather than by the shell. A
malicious entry cannot execute code through the parser.

### What the guards can and cannot do

The hooks are advisory in the sense that `git commit --no-verify` bypasses
them, and a repository setting its own `core.hooksPath` (husky does this)
overrides them. The `url.<alias>.insteadOf` layer is the one that holds
regardless, because the remote enforces it. Treat the hooks as the fast
feedback loop and the key separation as the actual boundary.

## Scope

**In scope:**
- Code execution through `workspaces.conf`, `~/.ssh/config` or URL parsing
- Identity guards that pass when they should refuse
- Leaking a token or key path into logs or command lines
- The installer writing outside `$ZSH_CUSTOM/plugins` or `~/.zshrc`

**Out of scope:**
- `--no-verify` and other documented bypasses
- Security of git, gh, ssh, GitHub or GitLab themselves
- Social engineering
