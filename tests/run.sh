#!/usr/bin/env bash
# gitspace test suite.
#
# Runs against a throwaway HOME so it never touches the developer's real
# ~/.gitconfig, ~/.ssh/config or workspaces.conf. No network access required.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
head_() { printf '\n\033[36m%s\033[0m\n' "$1"; }

# Physical path on purpose: git's own `includeIf gitdir:` does not resolve
# symlinks either, and on macOS mktemp hands back /var/... while git reports
# /private/var/... A fixture built on the symlinked form tests nothing.
SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
export GITSPACE_CONF="$HOME/.config/git/workspaces.conf"
export GITSPACE_LIB="$HOME/.config/git/hooks"
mkdir -p "$HOME/.config/git/hooks" "$HOME/.ssh"

# Minimal ssh config so alias resolution has something to find.
cat > "$HOME/.ssh/config" <<'SSHCFG'
Host github-acme
    HostName github.com
    User git

Host gitlab-acme
    HostName gitlab.example.com
    User git
SSHCFG

install -m 0755 "$REPO/lib/guard.sh" "$REPO/lib/pre-commit" "$REPO/lib/pre-push" "$GITSPACE_LIB/"

WS="$HOME/ws/Acme"
NESTED="$WS/nested"
mkdir -p "$NESTED"
cat > "$GITSPACE_CONF" <<CONF
# test fixture
Acme|$WS|dev@acme.test|acme-bot|github-acme,gitlab-acme
Nested|$NESTED|nested@acme.test||github-acme
CONF

git config --global user.useConfigOnly true
git config --global init.defaultBranch main
cat >> "$HOME/.gitconfig" <<GITCFG
[includeIf "gitdir:$WS/"]
	path = $HOME/.gitconfig-Acme
[includeIf "gitdir:$NESTED/"]
	path = $HOME/.gitconfig-Nested
GITCFG
# user.name is not optional: useConfigOnly refuses a commit without one.
printf '[user]\n\tname = Acme Bot\n\temail = dev@acme.test\n[core]\n\thooksPath = %s\n' "$GITSPACE_LIB" > "$HOME/.gitconfig-Acme"
printf '[user]\n\tname = Nested Bot\n\temail = nested@acme.test\n[core]\n\thooksPath = %s\n' "$GITSPACE_LIB" > "$HOME/.gitconfig-Nested"

new_repo() { rm -rf "$1"; mkdir -p "$1"; git -C "$1" init -q; echo x > "$1/f.txt"; git -C "$1" add f.txt; }

# --------------------------------------------------------------------------
head_ "guard: workspace resolution"

new_repo "$WS/repo"
if git -C "$WS/repo" commit -q -m t 2>/dev/null; then
  got=$(git -C "$WS/repo" log -1 --format=%ae)
  if [ "$got" = "dev@acme.test" ]; then
    ok "commit in a workspace is signed with its e-mail"
  else
    bad "wrong signing address" "got $got"
  fi
else
  bad "commit in a valid workspace was refused"
fi

# The nested workspace must win over its parent (longest prefix).
new_repo "$NESTED/repo"
if git -C "$NESTED/repo" commit -q -m t 2>/dev/null; then
  got=$(git -C "$NESTED/repo" log -1 --format=%ae)
  if [ "$got" = "nested@acme.test" ]; then
    ok "nested workspace wins over its parent"
  else
    bad "nested workspace lost to parent" "got $got"
  fi
else
  bad "commit in the nested workspace was refused"
fi

# --------------------------------------------------------------------------
head_ "guard: refusals"

new_repo "$WS/wrong"
git -C "$WS/wrong" config user.email intruder@example.com
if git -C "$WS/wrong" commit -q -m t 2>/dev/null; then
  bad "a commit with the wrong e-mail was allowed"
else
  ok "commit with the wrong e-mail is refused"
fi

OUT="$SANDBOX/outside"
new_repo "$OUT"
if git -C "$OUT" commit -q -m t 2>/dev/null; then
  bad "a commit outside every workspace was allowed"
else
  ok "commit outside every workspace is refused"
fi

# --------------------------------------------------------------------------
head_ "pre-push"

new_repo "$WS/push"
git -C "$WS/push" commit -q -m t
git -C "$WS/push" remote add origin "github-acme:acme/thing.git"
printf 'github.com:\n  user: acme-bot\n' > "$HOME/.config/gh/hosts.yml" 2>/dev/null || {
  mkdir -p "$HOME/.config/gh"; printf 'github.com:\n  user: acme-bot\n' > "$HOME/.config/gh/hosts.yml"; }
if (cd "$WS/push" && sh "$GITSPACE_LIB/pre-push" origin "github-acme:acme/thing.git" </dev/null >/dev/null 2>&1); then
  ok "push with a matching alias and gh account passes"
else
  bad "push with a matching alias and gh account was refused"
fi

printf 'github.com:\n  user: someone-else\n' > "$HOME/.config/gh/hosts.yml"
if (cd "$WS/push" && sh "$GITSPACE_LIB/pre-push" origin "github-acme:acme/thing.git" </dev/null >/dev/null 2>&1); then
  bad "push with the wrong gh account was allowed"
else
  ok "push with the wrong gh account is refused"
fi
printf 'github.com:\n  user: acme-bot\n' > "$HOME/.config/gh/hosts.yml"

git -C "$WS/push" remote set-url origin "git@github.com:acme/thing.git"
if (cd "$WS/push" && sh "$GITSPACE_LIB/pre-push" origin "git@github.com:acme/thing.git" </dev/null >/dev/null 2>&1); then
  bad "push over a non-aliased GitHub remote was allowed"
else
  ok "push over a non-aliased remote is refused"
fi

# A GitLab remote must not be judged by the gh account.
git -C "$WS/push" remote set-url origin "gitlab-acme:group/sub/thing.git"
printf 'github.com:\n  user: someone-else\n' > "$HOME/.config/gh/hosts.yml"
if (cd "$WS/push" && sh "$GITSPACE_LIB/pre-push" origin "gitlab-acme:group/sub/thing.git" </dev/null >/dev/null 2>&1); then
  ok "GitLab remote ignores the active gh account"
else
  bad "GitLab remote was blocked by the gh account check"
fi

# --------------------------------------------------------------------------
head_ "hook chaining"

new_repo "$WS/chain"
git -C "$WS/chain" commit -q -m t
mkdir -p "$WS/chain/.git/hooks"
printf '#!/bin/sh\necho CHAINED\nexit 0\n' > "$WS/chain/.git/hooks/pre-push"
chmod +x "$WS/chain/.git/hooks/pre-push"
git -C "$WS/chain" remote add origin "github-acme:acme/thing.git"
printf 'github.com:\n  user: acme-bot\n' > "$HOME/.config/gh/hosts.yml"
out=$(cd "$WS/chain" && sh "$GITSPACE_LIB/pre-push" origin "github-acme:acme/thing.git" </dev/null 2>&1)
case "$out" in
  *CHAINED*) ok "the repository's own pre-push still runs" ;;
  *)         bad "repository hook was not chained" "output: $out" ;;
esac

# --------------------------------------------------------------------------
head_ "signing (--sign)"

# A real key pair, so the signing path is exercised rather than mocked.
ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519_acme" -N "" -q -C "acme"
cat >> "$HOME/.ssh/config" <<SSHCFG

Host github-signed
    HostName github.com
    User git
    IdentityFile $HOME/.ssh/id_ed25519_acme
SSHCFG

if command -v zsh >/dev/null 2>&1; then
  SIGNED="$HOME/ws/Signed"
  zsh -c "GITSPACE_CONF='$GITSPACE_CONF' GITSPACE_LIB='$GITSPACE_LIB'
          source '$REPO/gitspace.plugin.zsh'
          gitspace add '$SIGNED' --email signer@acme.test --name Signer \
                       --alias github-signed --sign" >/dev/null 2>&1

  cfg="$HOME/.gitconfig-Signed"
  if grep -qE '^[[:space:]]*gpgsign[[:space:]]*=[[:space:]]*true' "$cfg" 2>/dev/null; then
    ok "--sign writes commit.gpgsign"
  else
    bad "--sign did not enable gpgsign"
  fi
  if grep -q 'format = ssh' "$cfg" 2>/dev/null; then
    ok "--sign sets gpg.format = ssh"
  else
    bad "gpg.format not set to ssh"
  fi
  if grep -q "signer@acme.test " "$HOME/.config/git/allowed_signers" 2>/dev/null; then
    ok "--sign registers the key in allowed_signers"
  else
    bad "allowed_signers not updated"
  fi

  # A real signed commit must verify against that allowed-signers file.
  mkdir -p "$SIGNED/r" && git -C "$SIGNED/r" init -q
  echo x > "$SIGNED/r/f" && git -C "$SIGNED/r" add f
  if git -C "$SIGNED/r" commit -q -m signed 2>/dev/null; then
    if git -C "$SIGNED/r" log -1 --show-signature 2>&1 | grep -q 'Good .*signature'; then
      ok "a signed commit verifies locally"
    else
      bad "signed commit does not verify" "$(git -C "$SIGNED/r" log -1 --show-signature 2>&1 | head -2 | tr '\n' ' ')"
    fi
  else
    bad "signed commit was refused"
  fi

  # --sign without an alias has no key to sign with and must refuse.
  out=$(zsh -c "GITSPACE_CONF='$GITSPACE_CONF' GITSPACE_LIB='$GITSPACE_LIB'
                source '$REPO/gitspace.plugin.zsh'
                gitspace add '$HOME/ws/NoKey' --email x@acme.test --sign" 2>&1)
  case "$out" in
    *"needs at least one --alias"*) ok "--sign without --alias is refused" ;;
    *) bad "--sign without --alias was accepted" ;;
  esac
else
  skip "signing tests (zsh not installed)"
fi

# --------------------------------------------------------------------------
head_ "doctor: key existence"

if command -v zsh >/dev/null 2>&1; then
  cat >> "$HOME/.ssh/config" <<SSHCFG

Host github-ghostkey
    HostName github.com
    User git
    IdentityFile $HOME/.ssh/does_not_exist
SSHCFG
  printf 'Ghost|%s/ws/Ghost|ghost@acme.test||github-ghostkey\n' "$HOME" >> "$GITSPACE_CONF"
  mkdir -p "$HOME/ws/Ghost"
  out=$(zsh -c "GITSPACE_CONF='$GITSPACE_CONF' GITSPACE_LIB='$GITSPACE_LIB'
                source '$REPO/gitspace.plugin.zsh'; gitspace doctor" 2>&1)
  case "$out" in
    *"key missing"*) ok "doctor reports a missing IdentityFile" ;;
    *) bad "doctor accepted an alias whose key does not exist" ;;
  esac
  # Keep the rest of the suite deterministic.
  grep -v '^Ghost|' "$GITSPACE_CONF" > "$SANDBOX/c" && mv "$SANDBOX/c" "$GITSPACE_CONF"
else
  skip "doctor key tests (zsh not installed)"
fi

# --------------------------------------------------------------------------
head_ "audit"

if command -v zsh >/dev/null 2>&1; then
  # Plant a commit authored as the OTHER workspace's identity.
  new_repo "$WS/leaky"
  git -C "$WS/leaky" -c user.email=nested@acme.test -c user.name=N \
      commit -q -m leak --no-verify
  out=$(zsh -c "GITSPACE_CONF='$GITSPACE_CONF' GITSPACE_LIB='$GITSPACE_LIB'
                source '$REPO/gitspace.plugin.zsh'; gitspace audit" 2>&1)
  case "$out" in
    *"leaky"*"wrong workspace identity"*) ok "audit detects identity leakage" ;;
    *) bad "audit missed a commit authored as another workspace" ;;
  esac
  # A third party's address must NOT be a finding.
  new_repo "$WS/thirdparty"
  git -C "$WS/thirdparty" -c user.email=colleague@example.com -c user.name=C \
      commit -q -m ext --no-verify
  case "$out" in
    *"thirdparty"*) bad "audit flagged a third-party author as a finding" ;;
    *) ok "audit ignores third-party authors" ;;
  esac
else
  skip "audit tests (zsh not installed)"
fi

# --------------------------------------------------------------------------
head_ "installer"

if node --check "$REPO/bin/gitspace-install.mjs" 2>/dev/null; then
  ok "installer parses"
else
  bad "installer has a syntax error"
fi

out=$(node "$REPO/bin/gitspace-install.mjs" path 2>&1)
if [ "$out" = "$REPO" ]; then
  ok "installer reports its package directory"
else
  bad "wrong package directory" "got $out"
fi

# --------------------------------------------------------------------------
head_ "zsh syntax"

if command -v zsh >/dev/null 2>&1; then
  for f in gitspace.plugin.zsh _gitspace; do
    if zsh -n "$REPO/$f" 2>/dev/null; then ok "$f parses"; else bad "$f has a syntax error"; fi
  done
else
  printf '  \033[33mskip\033[0m zsh not installed\n'
fi

# --------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
