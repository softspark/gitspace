#!/bin/sh
# gitspace - shared identity guard, sourced by the git hooks.
#
# Resolution lives in resolve.sh, which has no side effects; this file is the
# part that judges what it finds and stops the operation. Sourcing it IS the
# check, which is why the `gh` wrapper reads resolve.sh instead.
set -e

# shellcheck source=lib/resolve.sh
. "${GITSPACE_LIB:-$HOME/.config/git/hooks}/resolve.sh"

die() {
  printf '\n\033[31m✗ IDENTITY BLOCKED (%s)\033[0m\n  %s\n\n' "$1" "$2" >&2
  exit 1
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
