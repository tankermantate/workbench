#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/plain" "$T/repo" "$T/zdot"; git -C "$T/repo" init -q
printf '[launcher]\nterminals = ["WezTerm"]\n[[space]]\nname = "X"\nroot = "%s"\n' "$T/plain" > "$T/spaces.toml"
export WORKBENCH_CONFIG="$T/spaces.toml"
# never the real snapshots: an offer to restore from them would answer every pty test
export WB_RESTORE_DIR="$T/restore"
# blockers [env assignments…]: guard names from a non-interactive zsh in $T/plain
blockers() { (cd "$T/plain" && env -u CLAUDECODE -u WORKBENCH_NO_LAUNCH TERM_PROGRAM=Apple_Terminal SHLVL=0 "$@" \
  zsh -f -c "source '$REPO/shell/workbench.zsh'; _wb_autolaunch_blockers; print -l -- \$reply"); }

out="$(blockers)"
assert_contains "non-interactive is blocked" "$out" "interactive"
assert_not_contains "default env: no claudecode" "$out" "claudecode"
assert_not_contains "default env: SHLVL 1 passes" "$out" "shlvl"
assert_not_contains "Apple_Terminal passes" "$out" "terminal"
assert_not_contains "non-repo folder passes" "$out" "git_repo"
assert_contains "inside Claude is blocked" "$(blockers CLAUDECODE=1)" "claudecode"
assert_contains "escape hatch" "$(blockers WORKBENCH_NO_LAUNCH=1)" "no_launch"
assert_contains "nested shell is blocked" "$(blockers SHLVL=3)" "shlvl"
assert_contains "VS Code terminal is blocked" "$(blockers TERM_PROGRAM=vscode)" "terminal"
assert_not_contains "terminal listed in config passes" "$(blockers TERM_PROGRAM=WezTerm)" "terminal"
out="$(cd "$T/repo" && env -u CLAUDECODE TERM_PROGRAM=Apple_Terminal SHLVL=0 zsh -f -c "source '$REPO/shell/workbench.zsh'; _wb_autolaunch_blockers; print -l -- \$reply")"
assert_not_contains "inside a git repo passes: Cmd-T tabs open in the worktree" "$out" "git_repo"

# True positive in a real pty: first prompt runs launch once (stubbed).
cat > "$T/zdot/.zshrc" <<EOF
source '$REPO/shell/workbench.zsh'
launch() { print LAUNCHED-STUB }
EOF
# pty DIR LINE…: a new interactive zsh in DIR, typing each LINE then exit. zsh
# throws away anything typed before its first prompt, so each line waits a second.
pty() { local d=$1; shift
  (cd "$d" && { for l in "$@" exit; do sleep 1; printf '%s\n' "$l"; done; } \
    | env -u CLAUDECODE -u WORKBENCH_NO_LAUNCH ZDOTDIR="$T/zdot" TERM_PROGRAM=Apple_Terminal SHLVL=0 \
      perl -e 'alarm 15; exec @ARGV' script -q /dev/null zsh -i 2>&1); }
out="$(pty "$T/plain" 'print REACHED-$((2+2))')"
assert_contains "new window in a plain folder launches" "$out" "LAUNCHED-STUB"
assert_contains "the typed line ran, so there was a second prompt" "$out" "REACHED-4"
assert_eq "it launches once, not at every prompt" "$(printf '%s' "$out" | tr -d '\r' | grep -c 'LAUNCHED-STUB$')" "1"
assert_contains "new tab inside a repo launches too" "$(pty "$T/repo")" "LAUNCHED-STUB"
# Re-sourcing mid-session must not arm the hook again. The stub prints LAUNCHED-2,
# which the terminal's echo of the typed line (LAUNCHED-$((1+1))) does not match.
out="$(pty "$T/plain" "source '$REPO/shell/workbench.zsh'; launch() { print LAUNCHED-\$((1+1)) }" true)"
assert_eq "re-sourcing .zshrc does not launch again" "$(printf '%s' "$out" | tr -d '\r' | grep -c -E 'LAUNCHED-(STUB|2)$')" "1"

# A tab wb-restore opened: its first prompt resumes the queued session instead of launching.
mkdir -p "$T/restore/queue" "$T/resumed"
printf '{"session":"sid-q","cwd":"%s","config":"%s","skip_permissions":false,"name":"q"}' \
  "$T/resumed" "$T/zdot/.claude-alt" > "$T/restore/queue/1-000.json"
out="$(export WORKBENCH_DRY_RUN=1; pty "$T/plain" 'print PWD-IS-$PWD')"
assert_contains "a queued session is resumed in the new tab" "$out" "--resume sid-q"
assert_not_contains "and the launcher doesn't start" "$out" "LAUNCHED-STUB"
assert_contains "the tab is left in the session's folder" "$out" "PWD-IS-$T/resumed"
[ -e "$T/restore/queue/1-000.json" ] && bad "the entry was claimed" || ok "the entry was claimed"
out="$(pty "$T/plain")"
assert_contains "with the queue empty, the next tab launches as usual" "$out" "LAUNCHED-STUB"

# After a restart, the first tab's launcher offers to bring the sessions back, once.
rm -rf "$T/restore"; mkdir -p "$T/restore/snapshots"
NOW=$(date +%s)
printf '{"taken": %s, "sessions": [{"session":"sid-old","cwd":"%s","config":"%s","skip_permissions":false,"name":"Old one"}]}' \
  $((NOW - 7200)) "$T/resumed" "$T/zdot/.claude" > "$T/restore/snapshots/20261115T090000Z.json"
export WB_BOOTTIME=$((NOW - 3600))
out="$(export WORKBENCH_DRY_RUN=1; pty "$T/plain" '')"
assert_contains "the offer names how many" "$out" "1 session was open before the restart"
assert_contains "enter (yes) runs the restore" "$out" "DRY-RUN: would open"
assert_contains "then the launcher starts" "$out" "LAUNCHED-STUB"
out="$(pty "$T/plain" n)"
assert_contains "asked again while not answered no" "$out" "before the restart"
assert_contains "no: the launcher starts" "$out" "LAUNCHED-STUB"
out="$(pty "$T/plain")"
assert_not_contains "no is remembered: not asked again this boot" "$out" "before the restart"
assert_contains "and the launcher starts" "$out" "LAUNCHED-STUB"
unset WB_BOOTTIME
finish
