#!/bin/sh
# gitspace - workspace resolution, with no side effects.
#
# Split out of guard.sh so that something other than a git hook can ask which
# workspace a path belongs to. guard.sh runs git and exits on a mismatch the
# moment it is sourced, which is right for a hook and useless for anything else;
# the `gh` wrapper needs the answer without the verdict.
#
# Format of ~/.config/git/workspaces.conf (fields separated by |):
#   name|path|email|gh-account|ssh-alias[,ssh-alias...]|[sign]
#
# The workspace is resolved BY PATH, not by directory name, so a workspace may
# live anywhere. Nested paths are settled by the longest matching prefix.

GITSPACE_CONF="${GITSPACE_CONF:-$HOME/.config/git/workspaces.conf}"

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
