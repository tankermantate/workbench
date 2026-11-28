# workbench.zsh — the start screen for every Terminal window.
# Source it at the END of ~/.zshrc. Spec: docs/specs/2026-10-16-launcher-design.md
#
# Helpers below read two locals of the caller (_wb_main) through zsh's dynamic
# scoping: `s` (the chosen space's 14 fields, as printed by wb-spaces) and
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
  # a worktree session has a branch to ship; merging stays the owner's call
  if [[ $s[5] == 1 ]]; then
    text=${text//'{ship}'/"4. When it's committed, ship it with \`wb-ship\`: it pushes the branch, opens the pull request and waits for CI (run it with a 10-minute timeout; exit 11 means run it again). Merging is my call: tell me how CI went, and run the \`wb-ship --yes=<sha>\` it prints only after I say yes."}
  else
    text=${text//$'\n{ship}'/}
  fi
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
    [[ -n $top ]] && _wb_close_out $top
    return 0
  fi
  local rc
  "${cmd[@]}"; rc=$?
  [[ -n $top ]] && _wb_close_out $top
  return $rc
}

# Claude has exited in a worktree space; $1 is the folder's git top. end-session can't run inside
# a session (it removes the folder Claude runs in), but here it can. With --if-merged it removes
# the worktree only when its branch is merged and its bead closed, and otherwise keeps it and says
# why in one line: a pull request waiting on the owner's yes keeps its folder and conversation.
_wb_close_out() {
  local top=$1 es=${WB_END_SESSION:-$WORKBENCH_HOME/bin/end-session}
  # a linked worktree only: review and strategy sessions run in the main checkout
  [[ $(git -C $top rev-parse --path-format=absolute --git-dir 2>/dev/null) != \
     $(git -C $top rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ]] || return 0
  if [[ -n ${WORKBENCH_DRY_RUN-} ]]; then
    print -r -- "DRY-RUN: $es --if-merged $top"
    return 0
  fi
  $es --if-merged $top
  # end-session's cd moved only itself; this shell would be left in a deleted folder
  if [[ ! -d $top ]]; then
    cd -- $s[3] 2>/dev/null || cd ~
    (( $+functions[update_terminal_cwd] )) && update_terminal_cwd
  fi
  return 0
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

# $1 the opening prompt (default something-new; + new space passes new-project).
_wb_start_new() {
  if [[ $s[5] == 1 ]]; then _wb_session_cd $s[7] || return 0
  else cd -- $s[3] || return 0; fi
  _wb_claude prompt "$(_wb_prompt ${1:-something-new} -)" -
}

# After + new space: the rows were read before it existed, so read them again and start the new
# project's first session in it. $1 the new space's folder. Returns 1 when it isn't listed.
_wb_start_new_space() {
  local i
  "$WORKBENCH_HOME/bin/wb-spaces" > $tmp/spaces.tsv 2>/dev/null
  rows=("${(@f)$(<$tmp/spaces.tsv)}")
  for (( i = 1; i <= $#rows; i++ )); do
    s=("${(@ps:\t:)rows[i]}")
    if [[ $s[3] == $1 ]]; then
      _wb_start_new new-project
      return 0
    fi
  done
  print -u2 "workbench: made $1, but the launcher can't find it among the spaces (wb-doctor says why)."
  return 1
}

# The planning rituals (wb-groom): Claude starts in the space root, not on a bead.
# $1 the run dir from the work screen's review row.
_wb_start_review() {
  cd -- $s[3] || return 0
  _wb_claude prompt "$(_wb_prompt review - $1 ${WB_PLANS_DIR:-$HOME/.config/workbench/plans}/$s[1])" -
}

# wb-groom makes the plan dir from the templates when a space has none yet, and
# says where it is. Returns 1 to go back to screen 2 when it can't: nothing has
# started, so leaving the launcher would only lose the user's place.
_wb_start_strategy() {
  local plan ans
  if ! plan=$($WORKBENCH_HOME/bin/wb-groom strategy $s[1]); then
    print -u2 "workbench: the strategy session did not start (wb-groom said why, above)."
    print -nu2 "Press Enter to go back "   # fzf's redraw would hide the message otherwise
    read -r ans
    return 1
  fi
  cd -- $s[3] || return 0
  _wb_claude prompt "$(_wb_prompt strategy - - $plan)" -
  return 0   # Claude ran: whatever it exited with, the launcher is done
}

# The printed tabs view, or what went wrong: fzf's redraw would hide either, so wait for Enter.
# Returns 1 on EOF, when no Enter is coming.
_wb_tabs_pause() {
  local ans
  print -nu2 "Press Enter to go back "
  read -r ans
}

_wb_print_tabs() {
  # not inside $(...): it cuts lines to the terminal's width only on a terminal
  $WORKBENCH_HOME/bin/wb-tabs
  _wb_tabs_pause
}

# Screen 1's tabs row. wb-tabs takes about a second, so it runs only when chosen. With fzf
# it's a list: picking a tab's line goes to that tab and back to screen 1, which re-reads
# its counts. Returns 1 on EOF at a pause.
_wb_show_tabs() {
  local wb=$WORKBENCH_HOME/bin/wb-tabs rows line rc
  _wb_use_fzf || { _wb_print_tabs; return }
  while true; do
    rows=$(COLUMNS=$COLUMNS $wb --rows) || { _wb_tabs_pause; return }
    line=$(print -r -- $rows | _wb_fzf "" --delimiter=$'\t' --with-nth=2 --no-sort --exact --ignore-case \
      --layout=reverse --ansi --prompt='Tabs? › ' --header="$(_wb_header 'enter or double-click: go to tab · ctrl-r: re-read · esc: back')" \
      --bind 'load:pos(2)' --bind "ctrl-r:reload(COLUMNS=$COLUMNS ${(q)wb} --rows)"); rc=$?
    (( rc == 1 || rc == 130 )) && return 0
    (( rc == 0 )) || { _wb_print_tabs; return }
    [[ ${line%%$'\t'*} == - ]] && continue    # a heading or a blank line
    $wb --jump ${line%%$'\t'*} && return 0
    _wb_tabs_pause || return 1
  done
}

# Screen 1's tidy row: worktrees whose pull request merged after their session left. wb-tidy
# lists them and asks again (all ticked) before ending any. Returns 1 on EOF at the pause.
_wb_tidy() {
  ${WB_TIDY:-$WORKBENCH_HOME/bin/wb-tidy}
  _wb_tabs_pause
}

# The ✦ more… submenu: workbench-wide commands. Prints the chosen key; esc, q and an empty
# answer all mean back.
_wb_screen_more() {
  local ui=$WORKBENCH_HOME/bin/wb-ui line rc
  if [[ -n ${WB_TEST_PICK_MORE-} ]] || _wb_use_fzf; then
    line=$("$ui" render-more $tmp | _wb_fzf "${WB_TEST_PICK_MORE-}" \
      --delimiter=$'\t' --with-nth=2,3 --nth=1 --exact --ignore-case --no-sort \
      --layout=reverse --ansi --prompt='More? › ' --header="$(_wb_header 'enter: choose · esc: back')") || { print back; return 0 }
  else
    while true; do
      "$ui" render-more $tmp > $tmp/more.menu
      line=$(_wb_menu $tmp/more.menu "More?" 2 back); rc=$?
      (( rc == 2 )) && continue
      (( rc == 0 )) || { print back; return 0 }
      break
    done
  fi
  print -r -- ${line%%$'\t'*}
}

# Runs ✦ more… until something starts a session (returns 0) or the user goes back (2).
# Returns 1 on EOF at a pause, when no answer is coming.
_wb_more() {
  local key root
  while true; do
    key=$(_wb_screen_more)
    unset WB_TEST_PICK_MORE      # a test's pick is used once, as on screen 1
    case $key in
      tabs)   _wb_show_tabs || return 1 ;;
      tidy)   _wb_tidy || return 1 ;;
      doctor) $WORKBENCH_HOME/bin/wb-doctor; _wb_tabs_pause || return 1 ;;
      update) $WORKBENCH_HOME/bin/wb-update; _wb_tabs_pause || return 1 ;;
      # a Claude Code session does the sync: nothing else can reach the page's data
      roadmap) $WORKBENCH_HOME/bin/wb-roadmap sync && return 0
              _wb_tabs_pause || return 1 ;;
      new)
        # its questions and messages go to the terminal; the folder is its last stdout line
        if root=$($WORKBENCH_HOME/bin/wb-new-space); then
          _wb_start_new_space "${root##*$'\n'}" && return 0
        fi
        _wb_tabs_pause || return 1 ;;
      *)      return 2 ;;
    esac
  done
}

# ◐ beads are probably another session's. $1 id, $2 worktree from the claim
# notes (or -). Returns 1 to go back to screen 2.
# Whether Claude has a conversation for $PWD on the space's account: it keeps them in
# <config>/projects/<the folder's real path, each non-alphanumeric as ->/*.jsonl.
_wb_has_conversation() {
  local cfg=$HOME/.claude
  [[ $s[8] != - ]] && cfg=$s[8]
  local -a found=($cfg/projects/${${PWD:A}//[^A-Za-z0-9]/-}/*.jsonl(N[1]))
  (( $#found ))
}

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
    if _wb_has_conversation; then
      _wb_claude continue "" $id
    else
      # --continue would only say "No conversation found to continue": the worktree was made
      # here but its session ran elsewhere, or never started
      print "workbench: no earlier conversation in this folder; starting a fresh session on $id."
      _wb_claude prompt "$(_wb_prompt work-on-bead $id)" $id
    fi
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
#
# Inside $(...) it execs fzf, so no zsh is left waiting on it (wb-k3v). When
# the subshell around it died while fzf was up (seen after closing a tab on
# screen 2), the waiting zsh 5.9 livelocked in its job-wait loop: 100% CPU,
# deaf to SIGHUP, adopted by launchd, for days, starving everything else on
# the Mac. With exec there is no waiter left to spin. Outside a subshell it
# must not exec, or it would replace the login shell.
_wb_fzf() {
  local q=$1; shift
  if [[ -n $q ]]; then grep -F -- "$q" | head -n 1 | grep .; return; fi
  (( ZSH_SUBSHELL )) && exec fzf "$@"
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
# $2 prompt, $3 first display column, $4 what q does (default: shell). sep/msg
# lines are shown, not numbered.
# The menu goes to stderr because stdout carries the chosen line.
# Returns 1 on q, empty input or EOF, and 2 on r (re-read); asks again on
# anything else that isn't a listed number.
_wb_menu() {
  local file=$1 prompt=$2 col=$3 qdo=${4:-shell} line ans n=0
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
    read -r "ans?$prompt number, r = re-read, q = $qdo: " || return 1
    case $ans in
      (''|q) return 1 ;;
      (r)    return 2 ;;
      (<1->) (( ans <= n )) && break ;;
    esac
    print -u2 "  type a number from the list (1-$n), r, or q = $qdo"
  done
  print -r -- $pickable[ans]
}

# $1 the keys line. Prints an fzf header: the keys, then wb-health's line when it has one,
# so a Mac that's due a restart says so on every screen.
_wb_header() {
  local health
  health=$($WORKBENCH_HOME/bin/wb-health --color 2>/dev/null)
  print -r -- $1${health:+$'\n'$health}
}

# The first screen's header: _wb_header, then the new-version notice when there is one
# (wb-update --notice answers from its cache; the once-a-day look runs in the background).
_wb_first_header() {
  local note
  note=$($WORKBENCH_HOME/bin/wb-update --notice --color 2>/dev/null)
  print -r -- "$(_wb_header $1)"${note:+$'\n'$note}
}

# Screen 1. Prints the chosen space's index; returns 1 to leave.
_wb_screen_spaces() {
  local ui=$WORKBENCH_HOME/bin/wb-ui line rc
  if [[ -n ${WB_TEST_PICK_SPACE-} ]] || _wb_use_fzf; then
    line=$("$ui" render-spaces $tmp | _wb_fzf "${WB_TEST_PICK_SPACE-}" \
      --listen=0 --delimiter=$'\t' --with-nth=2,3 --nth=1 --exact --ignore-case --no-sort --track \
      --layout=reverse --ansi --prompt='Space? › ' --header="$(_wb_first_header 'enter: choose · esc: plain shell')" \
      --bind "start:execute-silent(${(q)ui} fill-counts ${(q)tmp} >/dev/null 2>&1 &)") || return 1
  else
    while true; do
      "$ui" fill-counts $tmp          # no fzf: wait for the counts (bounded by the bd timeout)
      "$ui" render-spaces $tmp > $tmp/spaces.menu
      $WORKBENCH_HOME/bin/wb-health >&2
      $WORKBENCH_HOME/bin/wb-update --notice >&2 2>/dev/null
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
  while true; do
    i=$(_wb_screen_spaces) || return 0
    case $i in
      (more) unset WB_TEST_PICK_SPACE   # a test's pick is used once, so screen 1 can be left after
             _wb_more; case $? in 0|1) return 0 ;; esac ;;   # 2: screen 1 again
      (tidy) _wb_tidy || return 0 ;;
      (*)    break ;;
    esac
  done
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
    esac                          # sep/msg rows, a declined ◐, a failed strategy start: screen 2 again
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
  _wb_autolaunch_blockers && { _wb_restore_claimed || { _wb_restore_offer; launch } }
}

# After a restart, offers to bring back the sessions that were open before it.
# Enter means yes; a no lasts until the next restart, so new tabs stop asking.
_wb_restore_offer() {
  emulate -L zsh
  local n answer
  n=$($WORKBENCH_HOME/bin/wb-restore count 2>/dev/null) || return 0
  [[ $n == <-> ]] && (( n > 0 )) || return 0
  print -n "$n session$( (( n == 1 )) && print -n ' was' || print -n 's were') open before the restart. Bring them back? [Y/n] "
  read -r answer
  if [[ $answer == [nN]* ]]; then
    $WORKBENCH_HOME/bin/wb-restore decline
  else
    $WORKBENCH_HOME/bin/wb-restore
  fi
}

# A tab wb-restore opened takes one queued session and resumes it, here rather
# than by typing a command in, which the launcher's screen would swallow.
# Returns 1, so the launcher starts, when nothing is queued for it.
_wb_restore_claimed() {
  emulate -L zsh
  local line
  # glob first: no python at every new tab while the queue is empty
  local -a queued=(${WB_RESTORE_DIR:-$HOME/.local/state/workbench/restore}/queue/*.json(N[1]))
  (( $#queued )) || return 1
  line=$($WORKBENCH_HOME/bin/wb-restore claim 2>/dev/null) || return 1
  cd -- ${line%%$'\t'*} || return 1
  (( $+functions[update_terminal_cwd] )) && update_terminal_cwd
  $WORKBENCH_HOME/bin/wb-restore exec ${line#*$'\t'}
  return 0
}
if (( ! ${+_WB_HOOK_ARMED} )); then
  typeset -g _WB_HOOK_ARMED=1
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _wb_first_prompt
fi
