#!/bin/sh
# gitspace - shared identity guard, sourced by the git hooks.
#
# Format of ~/.config/git/workspaces.conf (fields separated by |):
#   name|path|email|gh-account|ssh-alias[,ssh-alias...]
#
# The workspace is resolved BY PATH, not by directory name, so a workspace may
# live anywhere. Nested paths are settled by the longest matching prefix.
set -e

GITSPACE_CONF="${GITSPACE_CONF:-$HOME/.config/git/workspaces.conf}"

die() {
  printf '\n\033[31m✗ IDENTITY BLOCKED (%s)\033[0m\n  %s\n\n' "$1" "$2" >&2
  exit 1
}

# Resolve symlinks. `git rev-parse --show-toplevel` always returns a physical
# path, so a configured path that traverses a symlink (/var -> /private/var on
# macOS) would never match without this.
_gs_real() {
  if [ -d "$1" ]; then (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"
  else printf '%s' "$1"; fi
}

# Expand a leading tilde against $HOME, without eval.
# shellcheck disable=SC2088  # "~/" here is a case PATTERN matching a literal
# tilde in the config file, not a path we want the shell to expand. Expansion is
# exactly what this function performs by hand, deliberately avoiding eval.
_gs_expand() {
  case "$1" in
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    "~")   printf '%s' "$HOME" ;;
    *)     printf '%s' "$1" ;;
  esac
}

# Row of the workspace containing the given path; empty when none matches.
_gs_row_for() {
  _target="$1" _best="" _bestlen=0
  [ -f "$GITSPACE_CONF" ] || return 0
  while IFS='|' read -r _n _p _m _a _s; do
    case "$_n" in ''|\#*) continue ;; esac
    _p=$(_gs_real "$(_gs_expand "$_p")")
    case "$_target/" in
      "$_p"/*)
        _len=${#_p}
        if [ "$_len" -gt "$_bestlen" ]; then
          _best="$_n|$_p|$_m|$_a|$_s"; _bestlen=$_len
        fi
        ;;
    esac
  done < "$GITSPACE_CONF"
  printf '%s' "$_best"
}

TOP=$(_gs_real "$(git rev-parse --show-toplevel)")
ROW=$(_gs_row_for "$TOP")

[ -n "$ROW" ] || die "outside every workspace" \
  "$TOP belongs to no workspace in $GITSPACE_CONF.
  Register one:  gitspace add <path> --email <address>"

# Field 2 (the workspace path) is deliberately not extracted: nothing downstream
# needs it, and an unused assignment invites the reader to look for a use.
# EXP_GH and EXP_SSH are consumed by pre-push, which sources this file.
# shellcheck disable=SC2034
WS=$(printf '%s' "$ROW"       | cut -d'|' -f1)
EXP_MAIL=$(printf '%s' "$ROW" | cut -d'|' -f3)
# shellcheck disable=SC2034
EXP_GH=$(printf '%s' "$ROW"   | cut -d'|' -f4)
# shellcheck disable=SC2034
EXP_SSH=$(printf '%s' "$ROW"  | cut -d'|' -f5)

GOT_MAIL=$(git config user.email || true)
[ -n "$GOT_MAIL" ] || die "no e-mail set" \
  "user.email is unset. Workspace '$WS' expects <$EXP_MAIL>.
  Check the includeIf in ~/.gitconfig:  gitspace doctor"
[ "$GOT_MAIL" = "$EXP_MAIL" ] || die "wrong e-mail" \
  "Workspace '$WS' requires <$EXP_MAIL>, but this repository uses <$GOT_MAIL>."
