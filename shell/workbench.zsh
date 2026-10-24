# workbench.zsh — the start screen for every Terminal window.
# Source it at the END of ~/.zshrc. Spec: docs/specs/2026-10-16-launcher-design.md
#
# Helpers below read two locals of the caller (_wb_main) through zsh's dynamic
# scoping: `s` (the chosen space's 13 fields, as printed by wb-spaces) and
# `tmp` (this launch's scratch dir).

typeset -g WORKBENCH_HOME=${${(%):-%x}:A:h:h}

# ---- handoff ----

# $1 prompt file name, $2 bead id (or -), $3 run dir and $4 plan dir for the
# planning rituals. Prints the opening prompt.
_wb_prompt() {
  local text proto=""
  text=$(<$WORKBENCH_HOME/prompts/$1.txt) || return 1
  [[ $s[9] != - ]] && proto="Before anything else, read $s[9]: it is how this space works."
  [[ -z $proto ]] && text=${text//$'\n{protocol}'/}   # no blank line where it would be
  text=${text//'{id}'/$2}
  text=${text//'{space}'/$s[1]}
  text=${text//'{root}'/$s[3]}
  text=${text//'{run}'/${3-}}
  text=${text//'{plan}'/${4-}}
  text=${text//'{groom}'/$WORKBENCH_HOME/bin/wb-groom}   # not on PATH unless install.sh ran
  text=${text//'{protocol}'/$proto}
  print -r -- $text
}

# $1 prompt|continue, $2 prompt text, $3 bead id (or -). Starts Claude in $PWD
# on the space's account. CLAUDE_CONFIG_DIR and the WB_* variables the session
# hooks read (bin/wb-session-hook) are set for this one command, or removed,
# never exported. `env claude` also skips the user's claude() shell function.
_wb_claude() {
  local -a cmd
  local top js
  if [[ $s[8] != - ]]; then cmd=(env CLAUDE_CONFIG_DIR=$s[8]); else cmd=(env -u CLAUDE_CONFIG_DIR); fi
  cmd+=(WB_SPACE_ROOT=$s[3])
  [[ ${3:--} != - ]] && cmd+=(WB_BEAD=$3)
  [[ $s[5] == 1 ]] && top=$(git rev-parse --show-toplevel 2>/dev/null) && cmd+=(WB_WORKTREE=$top)
  cmd+=(claude)
  # Without the hooks the session still starts; it just won't know its bead.
  js=$($WORKBENCH_HOME/bin/wb-session-hook settings-file 2>/dev/null) && cmd+=(--settings $js)
  [[ $s[10] == 1 ]] || cmd+=(--dangerously-skip-permissions)
  if [[ $1 == continue ]]; then cmd+=(--continue); else cmd+=($2); fi
  # Terminal learns the folder from a precmd hook, which won't run again until
  # Claude exits. Tell it now, so Cmd-T opens a tab here and not in ~.
  (( $+functions[update_terminal_cwd] )) && update_terminal_cwd
  if [[ -n ${WORKBENCH_DRY_RUN-} ]]; then
    print -r -- "DRY-RUN: cd $PWD && ${(j: :)${(@q-)cmd}}"
    return 0
  fi
  "${cmd[@]}"
}

# Runs the space's session command with --no-launch, showing its output as it
# goes, then cds into the WORKTREE_DIR it prints last. The launcher starts
# Claude itself so this shell is in the worktree when Claude exits.
_wb_session_cd() {
  setopt local_options local_traps
  local log=$tmp/session.log dir rc int=0
  # Ctrl-C stops the command (it gets SIGINT from the terminal) but not this
  # function, so it can say what may be left behind.
  trap 'int=1' INT
  "$s[6]" "$@" --no-launch 2>&1 | tee $log
  rc=${pipestatus[1]}
  if (( int )); then
    print -u2 "workbench: $s[6] was interrupted; it may have left a half-made worktree."
    print -u2 "           See: git -C $s[3] worktree list. You're at a shell in \$HOME."
    cd ~
    return 1
  fi
  dir=$(sed -n 's/^WORKTREE_DIR=//p' $log | tail -n 1)
  if (( rc != 0 )) || [[ -z $dir || ! -d $dir ]]; then
    print -u2 "workbench: $s[6] did not finish (exit $rc); you're at a shell in \$HOME."
    cd ~
    return 1
  fi
  cd -- $dir
}

_wb_start_bead() {
  if [[ $s[5] == 1 ]]; then _wb_session_cd $1 --space $s[7] || return 0
  else cd -- $s[3] || return 0; fi
  _wb_claude prompt "$(_wb_prompt work-on-bead $1)" $1
}

_wb_start_new() {
  if [[ $s[5] == 1 ]]; then _wb_session_cd $s[7] || return 0
  else cd -- $s[3] || return 0; fi
  _wb_claude prompt "$(_wb_prompt something-new -)" -
}

# The planning rituals (wb-groom): Claude starts in the space root, not on a bead.
# $1 the run dir from the work screen's review row.
_wb_start_review() {
  cd -- $s[3] || return 0
  _wb_claude prompt "$(_wb_prompt review - $1 ${WB_PLANS_DIR:-$HOME/.config/workbench/plans}/$s[1])" -
}

# $1 is the plan dir the row names; wb-groom makes it from the templates when a
# space has none yet, and says where it is.
_wb_start_strategy() {
  local plan ans
  if ! plan=$($WORKBENCH_HOME/bin/wb-groom strategy $s[1]); then
    print -nu2 "Press Enter to go back "   # fzf's redraw would hide the message otherwise
    read -r ans
    return 1
  fi
  cd -- $s[3] || return 0
  _wb_claude prompt "$(_wb_prompt strategy - - $plan)" -
}

# ◐ beads are probably another session's. $1 id, $2 worktree from the claim
# notes (or -). Returns 1 to go back to screen 2.
_wb_start_claimed() {
  local id=$1 wt=$2 ans dir
  if [[ $s[5] != 1 ]]; then
    read -r "ans?$id is already claimed (◐). Start a session on it anyway? [y/N] " || return 1
    [[ $ans == [yY]* ]] || return 1
    _wb_start_bead $id
    return 0
  fi
  if [[ $wt != - && -d $wt ]]; then
    dir=$wt/$(git -C $s[3] rev-parse --show-prefix 2>/dev/null)
    [[ -d $dir ]] || dir=$wt
    read -r "ans?$id is claimed; its worktree is ${dir%/}. Resume there? [Y/n] " || return 1
    [[ $ans == [nN]* ]] && return 1
    cd -- $dir || return 1
    _wb_claude continue "" $id
    return 0
  fi
  [[ $wt == - ]] && wt="(no worktree recorded)"
  print -u2 "workbench: $id is a stale claim: it is in progress, but its worktree $wt is gone."
  print -u2 "           Release it with: bd update $id --status open"
  print -nu2 "Press Enter to go back "   # fzf's redraw would hide the message otherwise
  read -r ans
  return 1
}

# ---- screens ----

_wb_use_fzf() { [[ -z ${WB_NO_FZF-} ]] && (( $+commands[fzf] )) }

# fzf, or, when a test passes a query in $1, the first line containing it.
_wb_fzf() {
  local q=$1; shift
  if [[ -n $q ]]; then grep -F -- "$q" | head -n 1 | grep .; return; fi
  fzf "$@"
}

# One-time hint when fzf is missing.
_wb_fzf_hint() {
  _wb_use_fzf && return 0
  local mark=${XDG_STATE_HOME:-$HOME/.local/state}/workbench/fzf-hint-shown
  [[ -e $mark ]] && return 0
  print -u2 "workbench: tip: brew install fzf for type-to-filter."
  mkdir -p ${mark:h} && : > $mark
}

# Numbered menu for when fzf is missing. $1 file of tab-separated lines,
# $2 prompt, $3 first display column. sep/msg lines are shown, not numbered.
# The menu goes to stderr because stdout carries the chosen line.
# Returns 1 on q, empty input or EOF, and 2 on r (re-read); asks again on
# anything else that isn't a listed number.
_wb_menu() {
  local file=$1 prompt=$2 col=$3 line ans n=0
  local -a pickable f
  for line in "${(@f)$(<$file)}"; do
    f=("${(@ps:\t:)line}")
    if [[ $f[1] == (sep|msg) ]]; then
      print -r -- "      ${(j: :)f[col,-1]}"
    elif [[ $f[1] != q ]]; then
      pickable+=($line)
      printf '  %2d) %s\n' $(( ++n )) "${(j: :)f[col,-1]}"
    fi
  done >&2
  while true; do
    read -r "ans?$prompt number, r = re-read, q = shell: " || return 1
    case $ans in
      (''|q) return 1 ;;
      (r)    return 2 ;;
      (<1->) (( ans <= n )) && break ;;
    esac
    print -u2 "  type a number from the list (1-$n), r or q"
  done
  print -r -- $pickable[ans]
}

# Screen 1. Prints the chosen space's index; returns 1 to leave.
_wb_screen_spaces() {
  local ui=$WORKBENCH_HOME/bin/wb-ui line rc
  if [[ -n ${WB_TEST_PICK_SPACE-} ]] || _wb_use_fzf; then
    line=$("$ui" render-spaces $tmp | _wb_fzf "${WB_TEST_PICK_SPACE-}" \
      --listen=0 --delimiter=$'\t' --with-nth=2,3 --nth=1 --exact --ignore-case --no-sort --track \
      --layout=reverse --ansi --prompt='Space? › ' --header='enter: choose · esc: plain shell' \
      --bind "start:execute-silent(${(q)ui} fill-counts ${(q)tmp} >/dev/null 2>&1 &)") || return 1
  else
    while true; do
      "$ui" fill-counts $tmp          # no fzf: wait for the counts (bounded by the bd timeout)
      "$ui" render-spaces $tmp > $tmp/spaces.menu
      line=$(_wb_menu $tmp/spaces.menu "Space?" 2); rc=$?
      (( rc == 2 )) && continue
      (( rc == 0 )) || return 1
      break
    done
  fi
  print -r -- ${line%%$'\t'*}
}

# Screen 2. Prints the chosen line (kind, id, worktree, …); returns 1 to leave.
# fzf can only search the text it shows, so wb-ui does the search (titles and
# descriptions, every word then some, highlighted) and fzf reloads on each
# keystroke. --ansi strips the highlights from the chosen line.
_wb_screen_work() {
  local i=$1 ui=$WORKBENCH_HOME/bin/wb-ui line rc
  if [[ -n ${WB_TEST_PICK_WORK-} ]] || _wb_use_fzf; then
    line=$("$ui" render-work $tmp $i | _wb_fzf "${WB_TEST_PICK_WORK-}" \
      --delimiter=$'\t' --with-nth=4,5 --disabled --ansi --no-sort --layout=reverse \
      --prompt="$s[1] › " --header='type to search titles and descriptions · ctrl-r: re-read · esc: plain shell' \
      --preview="${(q)WORKBENCH_HOME}/bin/wb-backlog preview ${(q)tmp}/snapshot.json {2} {q}" \
      --preview-window=right,50%,wrap \
      --bind "change:reload(${(q)ui} filter-work ${(q)tmp} $i {q})" \
      --bind "ctrl-r:reload(${(q)ui} render-work ${(q)tmp} $i {q})") || return 1
  else
    while true; do
      "$ui" render-work $tmp $i > $tmp/work.menu
      line=$(_wb_menu $tmp/work.menu "Work?" 4); rc=$?
      (( rc == 2 )) && continue
      (( rc == 0 )) || return 1
      break
    done
  fi
  print -r -- $line
}

# ---- launch ----

_wb_main() {
  local tmp=$1 i pick
  local -a rows s p
  "$WORKBENCH_HOME/bin/wb-spaces" > $tmp/spaces.tsv || return 0   # it said why on stderr
  rows=("${(@f)$(<$tmp/spaces.tsv)}")
  [[ -n $rows[1] ]] || { print -u2 "workbench: no spaces found; check ${WORKBENCH_CONFIG:-~/.config/workbench/spaces.toml}"; return 0 }
  _wb_fzf_hint
  i=$(_wb_screen_spaces) || return 0
  [[ $i == <1-> ]] || return 0
  s=("${(@ps:\t:)rows[i]}")
  while true; do
    pick=$(_wb_screen_work $i) || return 0
    p=("${(@ps:\t:)pick}")
    case $p[1] in
      new)     _wb_start_new; return 0 ;;
      open)    _wb_start_bead $p[2]; return 0 ;;
      claimed) _wb_start_claimed $p[2] $p[3] && return 0 ;;
      review)  _wb_start_review $p[3]; return 0 ;;
      strategy) _wb_start_strategy && return 0 ;;
    esac                          # sep/msg rows, or a declined ◐: show screen 2 again
  done
}

# The start screen. Type `launch` any time. Never exits the shell: q, Esc,
# Ctrl-C and errors all end at a normal prompt.
launch() {
  emulate -L zsh
  setopt local_traps
  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/workbench.XXXXXX") || return 0
  {
    _wb_main $tmp
  } always {
    if (( TRY_BLOCK_ERROR )); then
      print -u2 "workbench: the launcher hit an error; you're at a normal shell."
      TRY_BLOCK_ERROR=0
    fi
    rm -rf -- $tmp
  }
  return 0
}

# ---- auto-start ----

_wb_terminal_allowed() {
  emulate -L zsh
  [[ ${TERM_PROGRAM-} == Apple_Terminal ]] && return 0
  [[ -n ${TERM_PROGRAM-} ]] || return 1
  local t
  for t in ${(f)"$($WORKBENCH_HOME/bin/wb-spaces --terminals 2>/dev/null)"}; do
    [[ $t == $TERM_PROGRAM ]] && return 0
  done
  return 1
}

# Sets $reply to every guard that blocks auto-start; returns 0 only when none
# do. Each guard is checked on its own so tests can see each one. It sets
# $reply rather than printing, because redirecting or capturing its stdout
# would make the tty guard fail.
_wb_autolaunch_blockers() {
  emulate -L zsh
  reply=()
  [[ -o interactive ]]             || reply+=(interactive)
  [[ -t 0 && -t 1 ]]               || reply+=(tty)
  [[ -z ${CLAUDECODE-} ]]          || reply+=(claudecode)
  [[ -z ${WORKBENCH_NO_LAUNCH-} ]] || reply+=(no_launch)
  [[ ${SHLVL-} == 1 ]]             || reply+=(shlvl)
  _wb_terminal_allowed             || reply+=(terminal)
  (( ! $#reply ))
}

# Runs at the first prompt, after all of .zshrc (claude(), aliases, PATH) is
# defined. Removes itself first, so it never runs twice, and is armed only on
# the first source, so re-sourcing ~/.zshrc later doesn't launch again.
_wb_first_prompt() {
  emulate -L zsh
  add-zsh-hook -d precmd _wb_first_prompt
  _wb_autolaunch_blockers && launch
}
if (( ! ${+_WB_HOOK_ARMED} )); then
  typeset -g _WB_HOOK_ARMED=1
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _wb_first_prompt
fi
