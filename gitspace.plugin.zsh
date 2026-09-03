# gitspace - git identity per workspace directory.
#
# Keeps accounts apart: every directory carries its own commit e-mail, gh
# account and SSH key. A mismatch is a hard error, never a silent fallback.
#
#   gitspace add <path> --email <address> [--gh <account>] [--alias a,b]
#   gitspace list | doctor | remove <name> | install
#   wclone <url> [directory]
#
# State lives OUTSIDE the plugin tree (~/.config/git/), because deployment
# tooling deletes and re-clones the plugin directory.

typeset -g GITSPACE_CONF="${GITSPACE_CONF:-$HOME/.config/git/workspaces.conf}"
typeset -g GITSPACE_LIB="${GITSPACE_LIB:-$HOME/.config/git/hooks}"
typeset -g GITSPACE_BIN="${GITSPACE_BIN:-$HOME/.config/git/bin}"
typeset -g GITSPACE_SRC="${0:A:h}"

autoload -Uz add-zsh-hook

# --- helpers -----------------------------------------------------------------

_gs_expand() {
  case "$1" in
    "~/"*) print -r -- "$HOME/${1#\~/}" ;;
    "~")   print -r -- "$HOME" ;;
    *)     print -r -- "$1" ;;
  esac
}

# Resolve symlinks, so a path that traverses one still matches. git reports
# physical paths, and /var -> /private/var on macOS would otherwise never match.
_gs_real() {
  if [[ -d "$1" ]]; then print -r -- "${1:A}"; else print -r -- "$1"; fi
}

# Configuration rows, comments and blank lines dropped.
_gs_rows() {
  [[ -f "$GITSPACE_CONF" ]] || return 0
  grep -v '^[[:space:]]*#' "$GITSPACE_CONF" 2>/dev/null | grep -v '^[[:space:]]*$'
}

# Row of the workspace containing the given path (longest matching prefix).
_gs_row_for() {
  local target="$1" best="" bestlen=0 line n p
  local -a f
  while IFS= read -r line; do
    f=("${(@s:|:)line}")
    n=$f[1]; p=$(_gs_real "$(_gs_expand "$f[2]")")
    if [[ "$target/" == "$p"/* ]]; then
      (( ${#p} > bestlen )) && { best="$line"; bestlen=${#p} }
    fi
  done < <(_gs_rows)
  print -r -- "$best"
}

# Active gh account, read locally so no network round-trip is needed.
_gs_gh_active() {
  sed -n 's/^[[:space:]]*user:[[:space:]]*\(.*\)$/\1/p' "$HOME/.config/gh/hosts.yml" 2>/dev/null | tail -1
}

# HostName bound to an alias in ~/.ssh/config.
_gs_alias_host() {
  awk -v a="$1" '
    $1=="Host" { inblk=0; for(i=2;i<=NF;i++) if($i==a) inblk=1; next }
    inblk && tolower($1)=="hostname" { print $2; exit }
  ' "$HOME/.ssh/config" 2>/dev/null
}

# IdentityFile bound to an alias in ~/.ssh/config, tilde expanded.
_gs_alias_key() {
  local k
  k=$(awk -v a="$1" '
    $1=="Host" { inblk=0; for(i=2;i<=NF;i++) if($i==a) inblk=1; next }
    inblk && tolower($1)=="identityfile" { print $2; exit }
  ' "$HOME/.ssh/config" 2>/dev/null)
  [[ -n "$k" ]] && _gs_expand "$k"
}

# Does ~/.gitconfig carry an includeIf for this path? git writes the directory
# either absolute or tilde-shortened, so both forms count - checking only one
# makes doctor report a false alarm.
_gs_has_include() {
  local abs="$1" tilde="${1/#$HOME/~}"
  grep -qF "gitdir:$abs/" "$HOME/.gitconfig" 2>/dev/null && return 0
  grep -qF "gitdir:$tilde/" "$HOME/.gitconfig" 2>/dev/null && return 0
  return 1
}

# The allowed-signers file lets `git log --show-signature` verify locally, not
# just on the forge. One line per identity; rewritten in place so a workspace
# never ends up with two entries after --sign is re-run.
_gs_allowed_signers() { print -r -- "${GITSPACE_CONF:h}/allowed_signers"; }

_gs_git_version() { command git --version 2>/dev/null | awk '{print $3}'; }

# ssh signing arrived in git 2.34. Compared numerically rather than as a string,
# because "2.9" sorts above "2.34" the moment anyone does it lexically.
_gs_git_can_sign_ssh() {
  local v=$(_gs_git_version) maj min
  [[ -n "$v" ]] || return 1
  maj=${v%%.*}; min=${${v#*.}%%.*}
  (( maj > 2 || (maj == 2 && min >= 34) ))
}

_gs_register_signer() {
  local mail="$1" pub="$2" f=$(_gs_allowed_signers) tmp
  [[ -r "$pub" ]] || return 1
  mkdir -p "${f:h}"
  touch "$f"
  tmp=$(mktemp)
  grep -v "^${mail} " "$f" > "$tmp" 2>/dev/null
  print -r -- "$mail namespaces=\"git\" $(< "$pub")" >> "$tmp"
  mv "$tmp" "$f"
}

# --- directory change announcement -------------------------------------------

_gs_announce() {
  local row ws mail acct cur
  local -a f
  row=$(_gs_row_for "${PWD:A}")
  if [[ -z "$row" ]]; then _GS_LAST=""; return; fi
  f=("${(@s:|:)row}")
  ws=$f[1]; mail=$f[3]; acct=$f[4]
  [[ "$ws" == "$_GS_LAST" ]] && return
  _GS_LAST="$ws"

  if [[ -n "$acct" ]]; then
    cur=$(_gs_gh_active)
    if [[ -n "$cur" && "$cur" != "$acct" ]]; then
      print -P "%F{yellow}~ switching gh: $cur -> $acct%f"
      gh auth switch --user "$acct" 2>&1 | sed 's/^/   /'
      cur=$(_gs_gh_active)      # read back AFTER the attempt - report reality
    fi
  fi

  print -P "%F{cyan}> $ws%f - committing as %F{green}$mail%f"
  if [[ -z "$acct" ]]; then
    print -P "   %F{8}no gh account bound%f"
  elif [[ "$cur" == "$acct" ]]; then
    print -P "   gh account: %F{green}$cur%f"
  else
    print -P "   %F{red}gh account: ${cur:-none} - NOT $acct. Pushes will be blocked.%f"
    print -P "   %F{red}fix: gh auth login  (as $acct)%f"
  fi
}
add-zsh-hook chpwd _gs_announce

# --- cloning -----------------------------------------------------------------

wclone() {
  emulate -L zsh
  local url="$1" dest="$2"
  local rest host rpath repo row ws mail acct aliases a chosen cur got
  local -a f

  if [[ -z "$url" ]]; then
    print -u2 "usage: wclone <url|owner/repo> [directory]"
    return 2
  fi

  chosen=""
  case "$url" in
    *://*)   rest=${url#*://}; rest=${rest#*@}; host=${rest%%/*}; rpath=${rest#*/} ;;
    *@*:*)   rest=${url#*@};   host=${rest%%:*}; rpath=${rest#*:} ;;
    *:*)     chosen=${url%%:*}; rpath=${url#*:}; host="" ;;   # already an alias
    */*)     host="github.com"; rpath=$url
             print -P "%F{yellow}i no host in URL - assuming github.com%f" ;;
    *) print -u2 "wclone: unrecognised URL: $url"; return 2 ;;
  esac
  rpath=${rpath%.git}; rpath=${rpath%/}; rpath=${rpath#/}
  repo=${rpath##*/}
  if [[ -z "$rpath" || -z "$repo" || "$rpath" != */* ]]; then
    print -u2 "wclone: '$rpath' does not look like <group>/<repo>"; return 2
  fi

  [[ -z "$dest" ]] && dest="$PWD/$repo"
  [[ "$dest" != /* ]] && dest="$PWD/$dest"
  dest=${dest:a}

  row=$(_gs_row_for "${dest:A}")
  if [[ -z "$row" ]]; then
    print -P "%F{red}x wclone: $dest belongs to no workspace%f"
    print -P "   register one:  gitspace add <path> --email <address>"
    return 1
  fi
  f=("${(@s:|:)row}")
  ws=$f[1]; mail=$f[3]; acct=$f[4]; aliases=$f[5]

  if [[ -n "$chosen" ]]; then
    if [[ ",$aliases," != *",$chosen,"* ]]; then
      print -P "%F{red}x wclone: alias '$chosen' does not belong to '$ws' (allowed: ${aliases:-<none>})%f"
      return 1
    fi
  else
    for a in ${(s:,:)aliases}; do
      [[ "$(_gs_alias_host $a)" == "$host" ]] && { chosen=$a; break }
    done
    if [[ -z "$chosen" ]]; then
      print -P "%F{red}x wclone: workspace '$ws' has no alias for host '$host'%f"
      for a in ${(s:,:)aliases}; do print -P "   $a -> $(_gs_alias_host $a)"; done
      return 1
    fi
  fi

  if [[ "$chosen" == github-* && -n "$acct" ]]; then
    cur=$(_gs_gh_active)
    if [[ -n "$cur" && "$cur" != "$acct" ]]; then
      print -P "%F{yellow}~ switching gh: $cur -> $acct%f"
      gh auth switch --user "$acct" 2>&1 | sed 's/^/   /'
      cur=$(_gs_gh_active)
    fi
    if [[ "$cur" != "$acct" ]]; then
      print -P "%F{red}x wclone: gh account is '${cur:-none}', '$ws' requires '$acct'%f"
      return 1
    fi
  fi

  # Real access check with the workspace key - same for GitHub and GitLab.
  if ! git ls-remote "$chosen:$rpath.git" >/dev/null 2>&1; then
    print -P "%F{red}x wclone: no access to $rpath through alias $chosen%f"
    print -P "   the repository does not exist, or this workspace's key cannot reach it"
    return 1
  fi

  print -P "%F{cyan}> cloning%f $rpath %F{cyan}->%f $dest"
  print -P "   as %F{green}$mail%f, alias $chosen ($(_gs_alias_host $chosen))"
  command git clone "$chosen:$rpath.git" "$dest" || return $?

  got=$(command git -C "$dest" config user.email)
  if [[ "$got" == "$mail" ]]; then
    print -P "%F{green}v done%f - commits will be signed $got"
  else
    print -P "%F{red}! WARNING: repository signs as '$got', workspace requires '$mail'%f"
    print -P "   check:  gitspace doctor"
  fi
}

# --- gh wrapper on PATH ------------------------------------------------------

typeset -g _GS_PATH_MARKER='# gitspace: the gh wrapper must resolve before the real gh'

# Put $GITSPACE_BIN in front of the real gh, for every zsh rather than only the
# interactive one.
#
# Two files, and both are needed. ~/.zshenv is the only startup file a
# non-interactive zsh reads, which is what a script or a coding agent gets.
# ~/.zprofile is needed because macOS rebuilds PATH from scratch in
# /etc/zprofile — `eval $(/usr/libexec/path_helper -s)` puts /usr/local/bin
# first and appends whatever .zshenv had set, so in a login shell the wrapper
# ends up BEHIND the gh it is meant to shadow. Restoring the order afterwards is
# the only way the entry survives.
#
# The line removes existing occurrences before prepending, rather than skipping
# when the directory is already somewhere in PATH: after path_helper it IS in
# PATH, just too late to matter.
_gs_wire_path() {
  local f
  for f in "$HOME/.zshenv" "$HOME/.zprofile"; do
    if [[ -f "$f" ]] && grep -qF -- "$_GS_PATH_MARKER" "$f"; then
      print -P "%F{8}=%f ${f/#$HOME/~} already wires it"
      continue
    fi
    [[ -f "$f" ]] && cp "$f" "$f.bak-gitspace"
    {
      print -r --
      print -r -- "$_GS_PATH_MARKER"
      print -r -- "path=( ${(q)GITSPACE_BIN} \${path:#${(q)GITSPACE_BIN}} )"
    } >> "$f"
    print -P "%F{green}v%f ${f/#$HOME/~} puts it first"
  done
  # And in the shell running the install, so it does not need a new terminal.
  path=( "$GITSPACE_BIN" ${path:#$GITSPACE_BIN} )
}

# --- gitspace command --------------------------------------------------------

_gs_install() {
  mkdir -p "${GITSPACE_CONF:h}" "$GITSPACE_LIB" "$GITSPACE_BIN"

  local f
  for f in resolve.sh guard.sh pre-commit pre-push; do
    install -m 0755 "$GITSPACE_SRC/lib/$f" "$GITSPACE_LIB/$f"
  done
  print -P "%F{green}v%f hooks -> $GITSPACE_LIB"

  install -m 0755 "$GITSPACE_SRC/lib/gh" "$GITSPACE_BIN/gh"
  print -P "%F{green}v%f gh wrapper -> $GITSPACE_BIN"
  _gs_wire_path

  if [[ ! -f "$GITSPACE_CONF" ]]; then
    cp "$GITSPACE_SRC/templates/workspaces.conf" "$GITSPACE_CONF"
    print -P "%F{green}v%f created $GITSPACE_CONF"
  else
    print -P "%F{8}=%f $GITSPACE_CONF already exists - left alone"
  fi

  # Forbid guessing an identity from username@hostname.
  if [[ "$(command git config --global user.useConfigOnly)" != "true" ]]; then
    command git config --global user.useConfigOnly true
    print -P "%F{green}v%f user.useConfigOnly = true"
  else
    print -P "%F{8}=%f user.useConfigOnly already set"
  fi

  local gmail=$(command git config --global user.email)
  if [[ -n "$gmail" ]]; then
    print -P "%F{yellow}!%f global user.email = $gmail"
    print -P "   That is a fallback which would sign commits outside every workspace."
    print -P "   Remove it:  git config --global --unset user.email"
  fi
  print -P "\nNext:  gitspace add <path> --email <address>"
}

_gs_add() {
  emulate -L zsh
  local wspath="" mail="" acct="" aliases="" uname="" as="" sign=""
  local -a rest
  while (( $# )); do
    case "$1" in
      --email) mail="$2"; shift 2 ;;
      --gh)    acct="$2"; shift 2 ;;
      --alias) aliases="$2"; shift 2 ;;
      --name)  uname="$2"; shift 2 ;;
      --as)    as="$2"; shift 2 ;;
      --sign)  sign="sign"; shift ;;
      -*) print -u2 "gitspace add: unknown option $1"; return 2 ;;
      *)  rest+=("$1"); shift ;;
    esac
  done
  wspath=$rest[1]

  if [[ -z "$wspath" || -z "$mail" ]]; then
    print -u2 "usage: gitspace add <path> --email <address> [--gh <account>] [--alias a,b] [--name \"Full Name\"] [--as <name>] [--sign]"
    return 2
  fi

  [[ "$wspath" != /* ]] && wspath="$PWD/$wspath"
  wspath=${wspath:a}
  local ws=${as:-${wspath:t}}

  if [[ ! -d "$wspath" ]]; then
    mkdir -p "$wspath" || return 1
    print -P "%F{green}v%f created $wspath"
  fi

  [[ -f "$GITSPACE_CONF" ]] || _gs_install >/dev/null

  if _gs_rows | grep -q "^$ws|"; then
    print -P "%F{red}x workspace '$ws' already exists in $GITSPACE_CONF%f"
    print -P "   remove it first:  gitspace remove $ws"
    return 1
  fi

  # Aliases must exist in ~/.ssh/config, otherwise a push falls back to the
  # default key - which is exactly the silent failure this tool exists to stop.
  local a
  local -a missing
  for a in ${(s:,:)aliases}; do
    [[ -z "$(_gs_alias_host $a)" ]] && missing+=($a)
  done
  if (( ${#missing} )); then
    print -P "%F{red}x not found in ~/.ssh/config: ${(j:, :)missing}%f"
    print -P "   add the Host entries before registering the workspace"
    return 1
  fi

  # --sign signs with the workspace's own SSH key, so it needs exactly one.
  local signkey=""
  if [[ -n "$sign" ]]; then
    # git learned ssh signing in 2.34. An older one rejects `gpg.format = ssh`
    # outright — and because the setting lands in the workspace's include file,
    # it does not fail at signing time but at EVERY commit, with
    # "fatal: bad config variable" pointing at a file the user never wrote.
    # Refusing here costs one check; the alternative bricks the workspace.
    if ! _gs_git_can_sign_ssh; then
      print -P "%F{red}x this git cannot sign with ssh: $(_gs_git_version) (needs 2.34)%f"
      print -P "   Enabling it would write gpg.format = ssh, and every commit in"
      print -P "   this workspace would then fail with 'bad config variable'."
      print -P "   Upgrade git, or register the workspace without --sign."
      return 1
    fi
    # Split into a real array first. ${${(s:,:)x}[1]} indexes the first
    # CHARACTER of the joined result, not the first element, so an alias
    # like "github-acme" silently becomes "g".
    local -a _als
    _als=(${(s:,:)aliases})
    local first=$_als[1]
    if [[ -z "$first" ]]; then
      print -P "%F{red}x --sign needs at least one --alias to take the key from%f"
      return 1
    fi
    signkey=$(_gs_alias_key "$first")
    if [[ -z "$signkey" ]]; then
      print -P "%F{red}x alias '$first' has no IdentityFile in ~/.ssh/config%f"
      return 1
    fi
    if [[ ! -r "$signkey.pub" ]]; then
      print -P "%F{red}x public key not found: $signkey.pub%f"
      print -P "   ssh signing needs the .pub beside the private key"
      return 1
    fi
  fi

  print -r -- "$ws|$wspath|$mail|$acct|$aliases|$sign" >> "$GITSPACE_CONF"

  # user.useConfigOnly requires BOTH name and email. Writing only the address
  # produces "Author identity unknown" at commit time - an error that never
  # mentions gitspace and sends people hunting through git docs. Fall back to
  # the gh account, then the workspace name; --name overrides either.
  local commit_name=${uname:-${acct:-$ws}}

  local inc="$HOME/.gitconfig-$ws"
  {
    print -r -- "# gitspace: identity for workspace '$ws' ($wspath)"
    print -r -- "[user]"
    print -r -- $'\tname = '"$commit_name"
    print -r -- $'\temail = '"$mail"
    print -r -- ""
    print -r -- "[core]"
    print -r -- $'\thooksPath = '"$GITSPACE_LIB"
    for a in ${(s:,:)aliases}; do
      local h=$(_gs_alias_host $a)
      print -r -- ""
      print -r -- "# $h remotes in this workspace go over key $a"
      print -r -- "[url \"$a:\"]"
      print -r -- $'\tinsteadOf = git@'"$h:"
      print -r -- $'\tinsteadOf = https://'"$h/"
    done
    if [[ -n "$signkey" ]]; then
      print -r -- ""
      print -r -- "# Commits and tags are signed with this workspace's own SSH key,"
      print -r -- "# so the identity is proven rather than merely declared."
      print -r -- "[user]"
      print -r -- $'\tsigningkey = '"$signkey.pub"
      print -r -- "[gpg]"
      print -r -- $'\tformat = ssh'
      print -r -- "[gpg \"ssh\"]"
      print -r -- $'\tallowedSignersFile = '"$(_gs_allowed_signers)"
      print -r -- "[commit]"
      print -r -- $'\tgpgsign = true'
      print -r -- "[tag]"
      print -r -- $'\tgpgsign = true'
    fi
  } > "$inc"

  [[ -n "$signkey" ]] && _gs_register_signer "$mail" "$signkey.pub"

  local gc="$HOME/.gitconfig"
  if ! _gs_has_include "$wspath"; then
    {
      print -r -- ""
      print -r -- "[includeIf \"gitdir:$wspath/\"]"
      print -r -- $'\tpath = '"$inc"
    } >> "$gc"
  fi

  local a_disp=${acct:-none} s_disp=${aliases:-none}
  print -P "%F{green}v%f workspace %F{cyan}$ws%f -> $wspath"
  print -P "   commits: %F{green}$commit_name <$mail>%f"
  print -P "   gh account: %F{green}$a_disp%f   aliases: %F{green}$s_disp%f"
  if [[ -n "$signkey" ]]; then
    print -P "   signing: %F{green}on%f ($signkey.pub)"
    print -P "   %F{8}add the same key to the forge as a SIGNING key, not just an auth key%f"
  fi
  print -P "   config:  $inc"
  print -P "\nverify:  gitspace doctor"
}

_gs_remove() {
  local ws="$1"
  [[ -n "$ws" ]] || { print -u2 "usage: gitspace remove <name>"; return 2 }
  _gs_rows | grep -q "^$ws|" || { print -P "%F{red}x no workspace named '$ws'%f"; return 1 }

  local tmp=$(mktemp)
  grep -v "^$ws|" "$GITSPACE_CONF" > "$tmp" && mv "$tmp" "$GITSPACE_CONF"
  print -P "%F{green}v%f removed the entry from $GITSPACE_CONF"
  print -P "%F{yellow}!%f left in place (delete by hand if you want them gone):"
  print -P "   ~/.gitconfig-$ws  and the includeIf section in ~/.gitconfig"
  print -P "   the workspace directory and its repositories"
}

_gs_list() {
  local line
  local -a f
  if [[ -z "$(_gs_rows)" ]]; then
    print -P "%F{8}no workspaces yet. Add one:  gitspace add <path> --email <address>%f"
    return 0
  fi
  printf "%-12s %-34s %-26s %-14s %s\n" WORKSPACE PATH EMAIL GH-ACCOUNT ALIASES
  while IFS= read -r line; do
    f=("${(@s:|:)line}")
    printf "%-12s %-34s %-26s %-14s %s\n" \
      "$f[1]" "${$(_gs_expand $f[2])/#$HOME/~}" "$f[3]" "${f[4]:--}" "${f[5]:--}"
  done < <(_gs_rows)
}

_gs_doctor() {
  emulate -L zsh
  local problems=0 line n p m a s al h x
  local -a f

  # The plugin itself may be a symlink to a checkout and therefore always
  # current, while the hooks are COPIES made by `gitspace install`. That
  # asymmetry hides staleness: everything reads as up to date while the guards
  # are running code from an earlier release. Compare them.
  print -P "%F{cyan}hooks%f"
  local stale=0
  for x in resolve.sh guard.sh pre-commit pre-push; do
    if [[ ! -f "$GITSPACE_LIB/$x" ]]; then
      print -P "  %F{red}x%f $x missing - run: gitspace install"; (( problems++ ))
    elif [[ ! -f "$GITSPACE_SRC/lib/$x" ]]; then
      print -P "  %F{green}v%f $x %F{8}(source unavailable, not compared)%f"
    elif cmp -s "$GITSPACE_SRC/lib/$x" "$GITSPACE_LIB/$x"; then
      print -P "  %F{green}v%f $x"
    else
      print -P "  %F{red}x%f $x differs from the plugin source"; (( problems++ )); stale=1
    fi
  done
  (( stale )) && print -P "  %F{yellow}run 'gitspace install' to refresh the installed hooks%f"

  # The wrapper is the only part of this tool that reaches a shell which never
  # sourced the plugin, and it reaches it through $PATH alone. Every check below
  # exists because the wrapper can be perfectly installed and still never run.
  print -P "\n%F{cyan}gh wrapper%f"
  if [[ ! -x "$GITSPACE_BIN/gh" ]]; then
    print -P "  %F{red}x%f $GITSPACE_BIN/gh missing - run: gitspace install"; (( problems++ ))
  elif [[ -f "$GITSPACE_SRC/lib/gh" ]] && ! cmp -s "$GITSPACE_SRC/lib/gh" "$GITSPACE_BIN/gh"; then
    print -P "  %F{red}x%f gh wrapper differs from the plugin source - run: gitspace install"; (( problems++ ))
  else
    print -P "  %F{green}v%f ${GITSPACE_BIN/#$HOME/~}/gh"
  fi

  for x in "$HOME/.zshenv" "$HOME/.zprofile"; do
    if [[ -f "$x" ]] && grep -qF -- "$_GS_PATH_MARKER" "$x"; then
      print -P "  %F{green}v%f ${x/#$HOME/~} wires it onto PATH"
    else
      print -P "  %F{red}x%f ${x/#$HOME/~} does not - run: gitspace install"; (( problems++ ))
    fi
  done

  # The one that matters. Everything above can be right while macOS path_helper,
  # or another tool prepending to PATH, still leaves the real gh in front.
  local resolved=$(command -v gh 2>/dev/null)
  if [[ -z "$resolved" ]]; then
    print -P "  %F{8}=%f gh is not installed - the wrapper has nothing to wrap"
  elif [[ "${resolved:A}" == "${GITSPACE_BIN:A}/gh" ]]; then
    print -P "  %F{green}v%f gh resolves to the wrapper in this shell"
  else
    print -P "  %F{red}x%f gh resolves to $resolved, not the wrapper"; (( problems++ ))
    print -P "    %F{8}PATH puts it first; open a new shell, or check what prepends after ~/.zprofile%f"
  fi

  print -P "\n%F{cyan}global settings%f"
  if [[ "$(command git config --global user.useConfigOnly)" == "true" ]]; then
    print -P "  %F{green}v%f user.useConfigOnly = true"
  else
    print -P "  %F{red}x%f user.useConfigOnly is not true - git will guess an identity"; (( problems++ ))
  fi
  local gmail=$(command git config --global user.email)
  if [[ -n "$gmail" ]]; then
    print -P "  %F{yellow}!%f global user.email = $gmail (silent fallback)"; (( problems++ ))
  else
    print -P "  %F{green}v%f no global user.email"
  fi

  print -P "\n%F{cyan}workspaces%f"
  while IFS= read -r line; do
    f=("${(@s:|:)line}")
    n=$f[1]; p=$(_gs_real "$(_gs_expand "$f[2]")"); m=$f[3]; a=$f[4]; s=$f[5]
    print -P "  %F{cyan}$n%f -> ${p/#$HOME/~}"

    [[ -d "$p" ]] || { print -P "    %F{red}x%f directory does not exist"; (( problems++ )) }

    if [[ -f "$HOME/.gitconfig-$n" ]]; then
      # useConfigOnly needs a name as well; without one every commit here dies
      # on "Author identity unknown", which never points back at gitspace.
      if grep -qE '^[[:space:]]*name[[:space:]]*=' "$HOME/.gitconfig-$n"; then
        print -P "    %F{green}v%f ~/.gitconfig-$n"
      else
        print -P "    %F{red}x%f ~/.gitconfig-$n has no user.name - commits will be refused"
        (( problems++ ))
      fi
    else
      print -P "    %F{red}x%f ~/.gitconfig-$n missing"; (( problems++ ))
    fi

    if _gs_has_include "$p"; then
      print -P "    %F{green}v%f includeIf in ~/.gitconfig"
    else
      print -P "    %F{red}x%f no includeIf for $p"; (( problems++ ))
    fi

    for al in ${(s:,:)s}; do
      h=$(_gs_alias_host $al)
      if [[ -z "$h" ]]; then
        print -P "    %F{red}x%f alias $al is not in ~/.ssh/config"; (( problems++ ))
        continue
      fi
      # An alias pointing at a key that is not on disk passes every other check
      # and fails only at push time - exactly the silent gap this tool exists
      # to close, so it is verified here rather than assumed.
      local key=$(_gs_alias_key "$al")
      if [[ -z "$key" ]]; then
        print -P "    %F{yellow}!%f $al -> $h (no IdentityFile; ssh will try default keys)"
        (( problems++ ))
      elif [[ ! -r "$key" ]]; then
        print -P "    %F{red}x%f $al -> $h  key missing: ${key/#$HOME/~}"; (( problems++ ))
      elif [[ ! -r "$key.pub" ]]; then
        print -P "    %F{yellow}!%f $al -> $h  private key present, ${key:t}.pub missing (signing needs it)"
        (( problems++ ))
      else
        print -P "    %F{green}v%f $al -> $h  (${key:t})"
      fi
    done

    if [[ -n "$a" ]]; then
      if command gh auth status 2>/dev/null | grep -q "account $a "; then
        print -P "    %F{green}v%f gh account '$a' is logged in"
      else
        print -P "    %F{red}x%f gh account '$a' is NOT logged in - gh auth login"; (( problems++ ))
      fi
    fi

    # Signing: declared in workspaces.conf, realised in ~/.gitconfig-<ws>, and
    # verifiable only if the public key is registered in allowed_signers. All
    # three must agree, or `git log --show-signature` reports an unknown signer.
    local want_sign=$f[6] cfg="$HOME/.gitconfig-$n" signers=$(_gs_allowed_signers)
    if [[ -n "$want_sign" ]]; then
      # A workspace registered on a machine with a newer git, then used on this
      # one, signs nothing and breaks every commit here. The config is right;
      # the binary cannot read it.
      if ! _gs_git_can_sign_ssh; then
        print -P "    %F{red}x%f signing requested but git $(_gs_git_version) cannot sign with ssh (needs 2.34)"
        print -P "      %F{8}every commit in this workspace fails with 'bad config variable'%f"
        (( problems++ ))
      fi
      if grep -qE '^[[:space:]]*gpgsign[[:space:]]*=[[:space:]]*true' "$cfg" 2>/dev/null; then
        print -P "    %F{green}v%f signing enabled"
      else
        print -P "    %F{red}x%f signing requested but gpgsign is not true in $cfg"; (( problems++ ))
      fi
      if grep -q "^${m} " "$signers" 2>/dev/null; then
        print -P "    %F{green}v%f $m is in allowed_signers"
      else
        print -P "    %F{red}x%f $m missing from ${signers/#$HOME/~} - signatures will not verify"
        (( problems++ ))
      fi
    elif grep -qE '^[[:space:]]*gpgsign[[:space:]]*=[[:space:]]*true' "$cfg" 2>/dev/null; then
      print -P "    %F{yellow}!%f gpgsign is on in $cfg but the workspace is not marked --sign"
      (( problems++ ))
    fi
  done < <(_gs_rows)

  print ""
  if (( problems )); then
    print -P "%F{red}$problems problem(s)%f"
    return 1
  fi
  print -P "%F{green}everything checks out%f"
}

# doctor checks the CONFIGURATION; audit checks what the repositories on disk
# actually contain. A setup can be perfect and still hold a repo cloned before
# it existed, or commits authored under a since-corrected address.
_gs_audit() {
  emulate -L zsh
  local deep="" limit=50
  while (( $# )); do
    case "$1" in
      --deep)  deep=1; shift ;;
      --limit) limit="$2"; shift 2 ;;
      -*) print -u2 "gitspace audit: unknown option $1"; return 2 ;;
      *) shift ;;
    esac
  done

  # "Some other person committed here" is normal in a shared repository and
  # says nothing. The question worth asking is narrower: did MY OTHER identity
  # leak into this workspace? So the comparison set is the operator's own
  # addresses from workspaces.conf, not every author in history.
  local -a mine
  mine=(${(f)"$(_gs_rows | cut -d'|' -f3)"})

  local line n p m a s repo rel url ok_url bad=0 scanned=0 leaks=0
  local -a f al
  while IFS= read -r line; do
    f=("${(@s:|:)line}")
    n=$f[1]; p=$(_gs_real "$(_gs_expand "$f[2]")"); m=$f[3]; s=$f[5]
    [[ -d "$p" ]] || continue
    al=(${(s:,:)s})
    print -P "%F{cyan}$n%f ${p/#$HOME/~}"

    for repo in "$p"/**/.git(N/); do
      repo=${repo:h}
      rel=${repo#$p/}
      (( scanned++ ))

      # 1. Remote must go through one of this workspace's aliases.
      url=$(command git -C "$repo" remote get-url origin 2>/dev/null)
      if [[ -n "$url" ]]; then
        ok_url=0
        for a in $al; do [[ "$url" == "$a:"* ]] && ok_url=1; done
        if (( ! ok_url )); then
          print -P "  %F{red}x%f $rel  remote not on a workspace alias: $url"; (( bad++ ))
        fi
      fi

      # 2. Working state that would block or mislead a commit.
      if [[ -n "$(command git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        print -P "  %F{yellow}*%f $rel  uncommitted changes"
      fi

      # 3. Identity leakage: commits here authored with one of the operator's
      #    OTHER workspace addresses. Third-party colleagues are not a finding.
      local -a authors wrong
      if [[ -n "$deep" ]]; then
        authors=(${(f)"$(command git -C "$repo" log --format=%ae 2>/dev/null | sort -u)"})
      else
        authors=(${(f)"$(command git -C "$repo" log -n "$limit" --format=%ae 2>/dev/null | sort -u)"})
      fi
      wrong=()
      for x in $authors; do
        [[ "$x" == "$m" ]] && continue
        (( ${mine[(I)$x]} )) && wrong+=($x)     # one of ours, but the wrong one
      done
      if (( ${#wrong} )); then
        print -P "  %F{red}x%f $rel  commits authored as ${(j:, :)wrong} - wrong workspace identity"
        (( leaks++ ))
      fi
    done
  done < <(_gs_rows)

  print ""
  print "scanned $scanned repositories"
  if (( bad == 0 && leaks == 0 )); then
    print -P "%F{green}no wrong remotes, no identity leakage%f"
  else
    (( bad ))   && print -P "%F{red}$bad with a remote outside the workspace's aliases%f"
    (( leaks )) && print -P "%F{red}$leaks holding commits authored as another workspace%f"
  fi
  (( bad == 0 && leaks == 0 ))
}

gitspace() {
  local cmd="$1"; shift 2>/dev/null
  case "$cmd" in
    install) _gs_install "$@" ;;
    add)     _gs_add "$@" ;;
    remove|rm) _gs_remove "$@" ;;
    list|ls) _gs_list "$@" ;;
    doctor)  _gs_doctor "$@" ;;
    audit)   _gs_audit "$@" ;;
    ""|help|-h|--help)
      print -- "gitspace - git identity per workspace directory

  gitspace install                     hooks, config template, global settings
  gitspace add <path> --email <addr> [--gh <account>] [--alias a,b]
                             [--name \"Full Name\"] [--as <name>]
  gitspace list                        registered workspaces
  gitspace doctor                      verify the whole setup
  gitspace audit [--deep] [--limit N]  scan the repositories on disk
  gitspace remove <name>               unregister a workspace

  wclone <url> [directory]             clone with the key the target implies"
      ;;
    *) print -u2 "gitspace: unknown command '$cmd' (see: gitspace help)"; return 2 ;;
  esac
}
