#!/bin/sh
# gitspace - wspolna logika blokad tozsamosci, zrodlowana przez hooki gita.
#
# Format ~/.config/git/workspaces.conf (pola rozdzielone |):
#   nazwa|sciezka|email|konto-gh|alias-ssh[,alias-ssh...]
#
# Przestrzen jest ustalana przez DOPASOWANIE SCIEZKI, nie po nazwie katalogu -
# dzieki temu przestrzen moze lezec gdziekolwiek, a zagniezdzone sciezki
# rozstrzyga najdluzszy pasujacy prefiks.
set -e

GITSPACE_CONF="${GITSPACE_CONF:-$HOME/.config/git/workspaces.conf}"

die() {
  printf '\n\033[31m✗ BLOKADA TOZSAMOSCI (%s)\033[0m\n  %s\n\n' "$1" "$2" >&2
  exit 1
}

# ~/cos -> /home/user/cos, bez eval
_gs_expand() {
  case "$1" in
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    "~")   printf '%s' "$HOME" ;;
    *)     printf '%s' "$1" ;;
  esac
}

# Wiersz przestrzeni zawierajacej podana sciezke; pusty, gdy zadna nie pasuje.
_gs_row_for() {
  _target="$1" _best="" _bestlen=0
  [ -f "$GITSPACE_CONF" ] || return 0
  while IFS='|' read -r _n _p _m _a _s; do
    case "$_n" in ''|\#*) continue ;; esac
    _p=$(_gs_expand "$_p")
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

TOP=$(git rev-parse --show-toplevel)
ROW=$(_gs_row_for "$TOP")

[ -n "$ROW" ] || die "poza przestrzenia" \
  "Repo $TOP nie nalezy do zadnej przestrzeni z $GITSPACE_CONF.
  Dodaj ja:  gitspace add <sciezka> --email <adres>"

WS=$(printf '%s' "$ROW"       | cut -d'|' -f1)
WS_PATH=$(printf '%s' "$ROW"  | cut -d'|' -f2)
EXP_MAIL=$(printf '%s' "$ROW" | cut -d'|' -f3)
EXP_GH=$(printf '%s' "$ROW"   | cut -d'|' -f4)
EXP_SSH=$(printf '%s' "$ROW"  | cut -d'|' -f5)

GOT_MAIL=$(git config user.email || true)
[ -n "$GOT_MAIL" ] || die "brak e-maila" \
  "user.email nie jest ustawiony. Przestrzen '$WS' oczekuje <$EXP_MAIL>.
  Sprawdz includeIf w ~/.gitconfig:  gitspace doctor"
[ "$GOT_MAIL" = "$EXP_MAIL" ] || die "zly e-mail" \
  "Przestrzen '$WS' wymaga <$EXP_MAIL>, a masz <$GOT_MAIL>."
