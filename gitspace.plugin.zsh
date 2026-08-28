# gitspace - tozsamosc gita per przestrzen robocza.
#
# Utrzymuje rozdzial kont: kazdy katalog ma wlasny e-mail, konto gh i klucz SSH.
# Niezgodnosc konczy sie twardym bledem, nie cichym uzyciem domyslnych ustawien.
#
#   gitspace add <sciezka> --email <adres> [--gh <konto>] [--alias a,b]
#   gitspace list | doctor | remove <nazwa> | install
#   wclone <url> [katalog]
#
# Stan trzymany jest POZA drzewem pluginu (~/.config/git/), bo rola Ansible
# usuwa katalog pluginu, gdy nie jest checkoutem gita.

typeset -g GITSPACE_CONF="${GITSPACE_CONF:-$HOME/.config/git/workspaces.conf}"
typeset -g GITSPACE_LIB="${GITSPACE_LIB:-$HOME/.config/git/hooks}"
typeset -g GITSPACE_SRC="${0:A:h}"

autoload -Uz add-zsh-hook

# --- pomocnicze --------------------------------------------------------------

_gs_expand() {
  case "$1" in
    "~/"*) print -r -- "$HOME/${1#\~/}" ;;
    "~")   print -r -- "$HOME" ;;
    *)     print -r -- "$1" ;;
  esac
}

# Wiersze konfiguracji, bez komentarzy i pustych.
_gs_rows() {
  [[ -f "$GITSPACE_CONF" ]] || return 0
  grep -v '^[[:space:]]*#' "$GITSPACE_CONF" 2>/dev/null | grep -v '^[[:space:]]*$'
}

# Wiersz przestrzeni zawierajacej podana sciezke (najdluzszy pasujacy prefiks).
_gs_row_for() {
  local target="$1" best="" bestlen=0 n p rest full
  local -a f
  while IFS= read -r line; do
    f=("${(@s:|:)line}")
    n=$f[1]; p=$(_gs_expand "$f[2]")
    if [[ "$target/" == "$p"/* ]]; then
      (( ${#p} > bestlen )) && { best="$line"; bestlen=${#p} }
    fi
  done < <(_gs_rows)
  print -r -- "$best"
}

# Aktywne konto gh - czytane lokalnie, bez zapytania do sieci.
_gs_gh_active() {
  sed -n 's/^[[:space:]]*user:[[:space:]]*\(.*\)$/\1/p' "$HOME/.config/gh/hosts.yml" 2>/dev/null | tail -1
}

# HostName przypisany aliasowi w ~/.ssh/config.
_gs_alias_host() {
  awk -v a="$1" '
    $1=="Host" { inblk=0; for(i=2;i<=NF;i++) if($i==a) inblk=1; next }
    inblk && tolower($1)=="hostname" { print $2; exit }
  ' "$HOME/.ssh/config" 2>/dev/null
}

# Czy ~/.gitconfig ma includeIf dla tej sciezki? git akceptuje forme bezwzgledna
# i skrocona z ~, wiec sprawdzamy obie - inaczej doctor daje falszywy alarm.
_gs_has_include() {
  local abs="$1" tilde="${1/#$HOME/~}"
  grep -qF "gitdir:$abs/" "$HOME/.gitconfig" 2>/dev/null && return 0
  grep -qF "gitdir:$tilde/" "$HOME/.gitconfig" 2>/dev/null && return 0
  return 1
}

# --- sygnalizacja przy zmianie katalogu --------------------------------------

_gs_announce() {
  local row ws mail acct cur
  local -a f
  row=$(_gs_row_for "$PWD")
  if [[ -z "$row" ]]; then _GS_LAST=""; return; fi
  f=("${(@s:|:)row}")
  ws=$f[1]; mail=$f[3]; acct=$f[4]
  [[ "$ws" == "$_GS_LAST" ]] && return
  _GS_LAST="$ws"

  if [[ -n "$acct" ]]; then
    cur=$(_gs_gh_active)
    if [[ -n "$cur" && "$cur" != "$acct" ]]; then
      print -P "%F{yellow}~ przelaczam gh: $cur -> $acct%f"
      gh auth switch --user "$acct" 2>&1 | sed 's/^/   /'
      cur=$(_gs_gh_active)      # odczyt PO probie - raportujemy stan faktyczny
    fi
  fi

  print -P "%F{cyan}> $ws%f - commity jako %F{green}$mail%f"
  if [[ -z "$acct" ]]; then
    print -P "   %F{8}bez konta gh%f"
  elif [[ "$cur" == "$acct" ]]; then
    print -P "   konto gh: %F{green}$cur%f"
  else
    print -P "   %F{red}konto gh: ${cur:-brak} - NIE $acct. Push bedzie zablokowany.%f"
    print -P "   %F{red}napraw: gh auth login  (na konto $acct)%f"
  fi
}
add-zsh-hook chpwd _gs_announce

# --- klonowanie --------------------------------------------------------------

wclone() {
  emulate -L zsh
  local url="$1" dest="$2"
  local rest host rpath repo row ws wsroot mail acct aliases a chosen cur got ah
  local -a f

  if [[ -z "$url" ]]; then
    print -u2 "uzycie: wclone <url|owner/repo> [katalog]"
    return 2
  fi

  chosen=""
  case "$url" in
    *://*)   rest=${url#*://}; rest=${rest#*@}; host=${rest%%/*}; rpath=${rest#*/} ;;
    *@*:*)   rest=${url#*@};   host=${rest%%:*}; rpath=${rest#*:} ;;
    *:*)     chosen=${url%%:*}; rpath=${url#*:}; host="" ;;   # juz alias
    */*)     host="github.com"; rpath=$url
             print -P "%F{yellow}i brak hosta w URL - zakladam github.com%f" ;;
    *) print -u2 "wclone: nie rozpoznaje URL-a: $url"; return 2 ;;
  esac
  rpath=${rpath%.git}; rpath=${rpath%/}; rpath=${rpath#/}
  repo=${rpath##*/}
  if [[ -z "$rpath" || -z "$repo" || "$rpath" != */* ]]; then
    print -u2 "wclone: sciezka '$rpath' nie wyglada na <grupa>/<repo>"; return 2
  fi

  [[ -z "$dest" ]] && dest="$PWD/$repo"
  [[ "$dest" != /* ]] && dest="$PWD/$dest"
  dest=${dest:a}

  row=$(_gs_row_for "$dest")
  if [[ -z "$row" ]]; then
    print -P "%F{red}x wclone: $dest nie nalezy do zadnej przestrzeni%f"
    print -P "   dodaj ja:  gitspace add <sciezka> --email <adres>"
    return 1
  fi
  f=("${(@s:|:)row}")
  ws=$f[1]; wsroot=$(_gs_expand "$f[2]"); mail=$f[3]; acct=$f[4]; aliases=$f[5]

  if [[ -n "$chosen" ]]; then
    if [[ ",$aliases," != *",$chosen,"* ]]; then
      print -P "%F{red}x wclone: alias '$chosen' nie nalezy do '$ws' (dozwolone: ${aliases:-<brak>})%f"
      return 1
    fi
  else
    for a in ${(s:,:)aliases}; do
      [[ "$(_gs_alias_host $a)" == "$host" ]] && { chosen=$a; break }
    done
    if [[ -z "$chosen" ]]; then
      print -P "%F{red}x wclone: przestrzen '$ws' nie obsluguje hosta '$host'%f"
      for a in ${(s:,:)aliases}; do print -P "   $a -> $(_gs_alias_host $a)"; done
      return 1
    fi
  fi

  if [[ "$chosen" == github-* && -n "$acct" ]]; then
    cur=$(_gs_gh_active)
    if [[ -n "$cur" && "$cur" != "$acct" ]]; then
      print -P "%F{yellow}~ przelaczam gh: $cur -> $acct%f"
      gh auth switch --user "$acct" 2>&1 | sed 's/^/   /'
      cur=$(_gs_gh_active)
    fi
    if [[ "$cur" != "$acct" ]]; then
      print -P "%F{red}x wclone: konto gh to '${cur:-brak}', a '$ws' wymaga '$acct'%f"
      return 1
    fi
  fi

  # Realny test dostepu kluczem - dziala tak samo dla GitHuba i GitLaba.
  if ! git ls-remote "$chosen:$rpath.git" >/dev/null 2>&1; then
    print -P "%F{red}x wclone: brak dostepu do $rpath przez alias $chosen%f"
    print -P "   repo nie istnieje, albo klucz tej przestrzeni go nie siega"
    return 1
  fi

  print -P "%F{cyan}> klonuje%f $rpath %F{cyan}->%f $dest"
  print -P "   jako %F{green}$mail%f, alias $chosen ($(_gs_alias_host $chosen))"
  command git clone "$chosen:$rpath.git" "$dest" || return $?

  got=$(command git -C "$dest" config user.email)
  if [[ "$got" == "$mail" ]]; then
    print -P "%F{green}v gotowe%f - commity beda podpisane $got"
  else
    print -P "%F{red}! UWAGA: repo podpisuje sie '$got', a przestrzen wymaga '$mail'%f"
    print -P "   sprawdz:  gitspace doctor"
  fi
}

# --- komenda gitspace --------------------------------------------------------

_gs_install() {
  local force=$1
  mkdir -p "${GITSPACE_CONF:h}" "$GITSPACE_LIB"

  local f
  for f in guard.sh pre-commit pre-push; do
    install -m 0755 "$GITSPACE_SRC/lib/$f" "$GITSPACE_LIB/$f"
  done
  print -P "%F{green}v%f hooki -> $GITSPACE_LIB"

  if [[ ! -f "$GITSPACE_CONF" ]]; then
    cp "$GITSPACE_SRC/templates/workspaces.conf" "$GITSPACE_CONF"
    print -P "%F{green}v%f utworzono $GITSPACE_CONF"
  else
    print -P "%F{8}=%f $GITSPACE_CONF juz istnieje - nie ruszam"
  fi

  # Zakaz zgadywania tozsamosci z username@hostname.
  if [[ "$(command git config --global user.useConfigOnly)" != "true" ]]; then
    command git config --global user.useConfigOnly true
    print -P "%F{green}v%f user.useConfigOnly = true"
  else
    print -P "%F{8}=%f user.useConfigOnly juz ustawione"
  fi

  local gmail=$(command git config --global user.email)
  if [[ -n "$gmail" ]]; then
    print -P "%F{yellow}!%f globalny user.email = $gmail"
    print -P "   To fallback, ktory podpisze commit poza kazda przestrzenia."
    print -P "   Usun:  git config --global --unset user.email"
  fi
  print -P "\nDalej:  gitspace add <sciezka> --email <adres>"
}

_gs_add() {
  emulate -L zsh
  local wspath="" mail="" acct="" aliases="" uname="" as=""
  local -a rest
  while (( $# )); do
    case "$1" in
      --email) mail="$2"; shift 2 ;;
      --gh)    acct="$2"; shift 2 ;;
      --alias) aliases="$2"; shift 2 ;;
      --name)  uname="$2"; shift 2 ;;
      --as)    as="$2"; shift 2 ;;
      -*) print -u2 "gitspace add: nieznana opcja $1"; return 2 ;;
      *)  rest+=("$1"); shift ;;
    esac
  done
  wspath=$rest[1]

  if [[ -z "$wspath" || -z "$mail" ]]; then
    print -u2 "uzycie: gitspace add <sciezka> --email <adres> [--gh <konto>] [--alias a,b] [--name \"Imie\"] [--as <nazwa>]"
    return 2
  fi

  [[ "$wspath" != /* ]] && wspath="$PWD/$wspath"
  wspath=${wspath:a}
  local ws=${as:-${wspath:t}}

  if [[ ! -d "$wspath" ]]; then
    mkdir -p "$wspath" || return 1
    print -P "%F{green}v%f utworzono katalog $wspath"
  fi

  [[ -f "$GITSPACE_CONF" ]] || _gs_install >/dev/null

  if _gs_rows | grep -q "^$ws|"; then
    print -P "%F{red}x przestrzen '$ws' juz istnieje w $GITSPACE_CONF%f"
    print -P "   usun ja najpierw:  gitspace remove $ws"
    return 1
  fi

  # Aliasy musza istniec w ~/.ssh/config - inaczej push poszedlby domyslnym kluczem.
  local a missing=()
  for a in ${(s:,:)aliases}; do
    [[ -z "$(_gs_alias_host $a)" ]] && missing+=($a)
  done
  if (( ${#missing} )); then
    print -P "%F{red}x brak w ~/.ssh/config: ${(j:, :)missing}%f"
    print -P "   dodaj wpis Host zanim zarejestrujesz przestrzen"
    return 1
  fi

  print -r -- "$ws|$wspath|$mail|$acct|$aliases" >> "$GITSPACE_CONF"

  # Konfiguracja gita dla tej przestrzeni.
  local inc="$HOME/.gitconfig-$ws"
  {
    print -r -- "# gitspace: tozsamosc przestrzeni '$ws' ($wspath)"
    print -r -- "[user]"
    [[ -n "$uname" ]] && print -r -- $'\tname = '"$uname"
    print -r -- $'\temail = '"$mail"
    print -r -- ""
    print -r -- "[core]"
    print -r -- $'\thooksPath = '"$GITSPACE_LIB"
    for a in ${(s:,:)aliases}; do
      local h=$(_gs_alias_host $a)
      print -r -- ""
      print -r -- "# remote'y $h w tej przestrzeni ida kluczem $a"
      print -r -- "[url \"$a:\"]"
      print -r -- $'\tinsteadOf = git@'"$h:"
      print -r -- $'\tinsteadOf = https://'"$h/"
    done
  } > "$inc"

  local gc="$HOME/.gitconfig"
  if ! _gs_has_include "$wspath"; then
    {
      print -r -- ""
      print -r -- "[includeIf \"gitdir:$wspath/\"]"
      print -r -- $'\tpath = '"$inc"
    } >> "$gc"
  fi

  print -P "%F{green}v%f przestrzen %F{cyan}$ws%f -> $wspath"
  print -P "   commity: %F{green}$mail%f${uname:+ ($uname)}"
  local _a_disp=${acct:-brak} _s_disp=${aliases:-brak}
  print -P "   konto gh: %F{green}$_a_disp%f   aliasy: %F{green}$_s_disp%f"
  print -P "   config:  $inc"
  print -P "\nsprawdz:  gitspace doctor"
}

_gs_remove() {
  local ws="$1"
  [[ -n "$ws" ]] || { print -u2 "uzycie: gitspace remove <nazwa>"; return 2 }
  _gs_rows | grep -q "^$ws|" || { print -P "%F{red}x nie ma przestrzeni '$ws'%f"; return 1 }

  local tmp=$(mktemp)
  grep -v "^$ws|" "$GITSPACE_CONF" > "$tmp" && mv "$tmp" "$GITSPACE_CONF"
  print -P "%F{green}v%f usunieto wpis z $GITSPACE_CONF"
  print -P "%F{yellow}!%f zostawiam nietkniete (usun recznie, jesli chcesz):"
  print -P "   ~/.gitconfig-$ws  oraz  sekcje includeIf w ~/.gitconfig"
  print -P "   katalog przestrzeni i jego repozytoria"
}

_gs_list() {
  local n p m a s
  local -a f
  if [[ -z "$(_gs_rows)" ]]; then
    print -P "%F{8}brak przestrzeni. Dodaj:  gitspace add <sciezka> --email <adres>%f"
    return 0
  fi
  printf "%-12s %-34s %-26s %-14s %s\n" PRZESTRZEN SCIEZKA EMAIL KONTO-GH ALIASY
  while IFS= read -r line; do
    f=("${(@s:|:)line}")
    printf "%-12s %-34s %-26s %-14s %s\n" \
      "$f[1]" "${$(_gs_expand $f[2])/#$HOME/~}" "$f[3]" "${f[4]:--}" "${f[5]:--}"
  done < <(_gs_rows)
}

_gs_doctor() {
  emulate -L zsh
  local problems=0 line n p m a s al h probe
  local -a f

  print -P "%F{cyan}hooki%f"
  local x
  for x in guard.sh pre-commit pre-push; do
    if [[ -f "$GITSPACE_LIB/$x" ]]; then
      print -P "  %F{green}v%f $x"
    else
      print -P "  %F{red}x%f brak $x - uruchom: gitspace install"; (( problems++ ))
    fi
  done

  print -P "\n%F{cyan}ustawienia globalne%f"
  if [[ "$(command git config --global user.useConfigOnly)" == "true" ]]; then
    print -P "  %F{green}v%f user.useConfigOnly = true"
  else
    print -P "  %F{red}x%f user.useConfigOnly nie jest true - git zgadnie tozsamosc"; (( problems++ ))
  fi
  local gmail=$(command git config --global user.email)
  if [[ -n "$gmail" ]]; then
    print -P "  %F{yellow}!%f globalny user.email = $gmail (cichy fallback)"; (( problems++ ))
  else
    print -P "  %F{green}v%f brak globalnego user.email"
  fi

  print -P "\n%F{cyan}przestrzenie%f"
  while IFS= read -r line; do
    f=("${(@s:|:)line}")
    n=$f[1]; p=$(_gs_expand "$f[2]"); m=$f[3]; a=$f[4]; s=$f[5]
    print -P "  %F{cyan}$n%f -> ${p/#$HOME/~}"

    [[ -d "$p" ]] || { print -P "    %F{red}x%f katalog nie istnieje"; (( problems++ )) }

    if [[ -f "$HOME/.gitconfig-$n" ]]; then
      print -P "    %F{green}v%f ~/.gitconfig-$n"
    else
      print -P "    %F{red}x%f brak ~/.gitconfig-$n"; (( problems++ ))
    fi

    # git zapisuje gitdir: raz jako sciezke bezwzgledna, raz z ~ - obie sa poprawne
    if _gs_has_include "$p"; then
      print -P "    %F{green}v%f includeIf w ~/.gitconfig"
    else
      print -P "    %F{red}x%f brak includeIf dla $p"; (( problems++ ))
    fi

    for al in ${(s:,:)s}; do
      h=$(_gs_alias_host $al)
      if [[ -z "$h" ]]; then
        print -P "    %F{red}x%f alias $al nie istnieje w ~/.ssh/config"; (( problems++ ))
      else
        print -P "    %F{green}v%f $al -> $h"
      fi
    done

    if [[ -n "$a" ]]; then
      if command gh auth status 2>/dev/null | grep -q "account $a "; then
        print -P "    %F{green}v%f konto gh '$a' zalogowane"
      else
        print -P "    %F{red}x%f konto gh '$a' NIE zalogowane - gh auth login"; (( problems++ ))
      fi
    fi
  done < <(_gs_rows)

  print ""
  if (( problems )); then
    print -P "%F{red}$problems problemow%f"
    return 1
  fi
  print -P "%F{green}wszystko na miejscu%f"
}

gitspace() {
  local cmd="$1"; shift 2>/dev/null
  case "$cmd" in
    install) _gs_install "$@" ;;
    add)     _gs_add "$@" ;;
    remove|rm) _gs_remove "$@" ;;
    list|ls) _gs_list "$@" ;;
    doctor)  _gs_doctor "$@" ;;
    ""|help|-h|--help)
      print -- "gitspace - tozsamosc gita per przestrzen robocza

  gitspace install                       hooki, szablon configu, ustawienia globalne
  gitspace add <sciezka> --email <adres> [--gh <konto>] [--alias a,b]
                                 [--name \"Imie\"] [--as <nazwa>]
  gitspace list                          zarejestrowane przestrzenie
  gitspace doctor                        sprawdza spojnosc calej konfiguracji
  gitspace remove <nazwa>                wyrejestrowuje przestrzen

  wclone <url> [katalog]                 klonuje wlasciwym kluczem dla katalogu"
      ;;
    *) print -u2 "gitspace: nieznana komenda '$cmd' (zobacz: gitspace help)"; return 2 ;;
  esac
}
