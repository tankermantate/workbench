#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
export WORKBENCH_DRY_RUN=1 FAKE_NS_LOG="$T/ns.log" FAKE_NS_DIR="$T/wt/proj" WB_STATE_DIR="$T/state"
NS="$REPO/tests/fake/new-session"
mkdir -p "$T/proj dir" "$T/repo/sub" "$T/scratch" "$T/wt-x/sub" "$T/wt"
git -C "$T/repo" init -q; git -C "$T/wt" init -q; git -C "$T/wt-x" init -q
WTTOP="$(cd "$T/wt" && pwd -P)"; WTXTOP="$(cd "$T/wt-x" && pwd -P)"

# z <space fields as one TSV string> <zsh code>: run code with s and tmp set
z() { zsh -f -c "source '$REPO/shell/workbench.zsh'; tmp='$T/scratch'; local -a s; s=(\"\${(@ps:\t:)1}\"); $2" _ "$1"; }
PLAIN="Beta	Side	$T/proj dir	if-present	0	-	-	-	-	0"
WT="Acme	-	$T/repo/sub	true	1	$NS	acme	$T/cfg	docs/PROTOCOL.md	0"

out="$(z "$PLAIN" '_wb_start_bead bee-1; print "PWD=$PWD"' 2>&1)"
assert_contains "plain bead: unsets config" "$out" "env -u CLAUDE_CONFIG_DIR 'WB_SPACE_ROOT=$T/proj dir' WB_BEAD=bee-1 claude"
assert_contains "plain bead: hooks passed as a file" "$out" "claude --settings $T/state/claude-settings.json "
assert_contains "plain bead: prompts off" "$out" " --dangerously-skip-permissions "
assert_not_contains "plain bead: no worktree" "$out" "WB_WORKTREE="
assert_contains "plain bead: work-on-bead prompt" "$out" "Work on bead bee-1 in Beta."
assert_contains "plain bead: shell lands in the project (path with a space)" "$out" "PWD=$T/proj dir"
assert_not_contains "no protocol: no protocol line" "$out" "Before anything else"
for f in work-on-bead something-new; do
  out="$(z "$PLAIN" "_wb_prompt $f bee-1")"
  assert_eq "no protocol: no double blank line ($f)" "$(printf '%s\n' "$out" | awk 'NR>1 && p=="" && $0=="" {n++} {p=$0} END {print n+0}')" "0"
done

out="$(CLAUDE_CONFIG_DIR=/elsewhere z "$PLAIN" '_wb_start_new' 2>&1)"
assert_contains "exported CLAUDE_CONFIG_DIR is removed for a plain space" "$out" "env -u CLAUDE_CONFIG_DIR 'WB_SPACE_ROOT="
assert_not_contains "something new: no WB_BEAD" "$out" "WB_BEAD="
assert_contains "something-new prompt" "$out" "start something new in Beta"

out="$(z "${PLAIN%0}1" '_wb_start_new' 2>&1)"
assert_not_contains "safe space keeps prompts on" "$out" "--dangerously-skip-permissions"

out="$(z "$WT" '_wb_start_bead acme-a2; print "PWD=$PWD"' 2>&1)"
assert_eq "worktree bead: new-session got the bead + --no-launch" "$(tail -1 "$T/ns.log")" "acme-a2 --space acme --no-launch"
assert_contains "worktree bead: new-session output shown live" "$out" "creating worktree (fake)"
assert_contains "worktree bead: config dir and env for the command" "$out" "DRY-RUN: cd $T/wt/proj && env CLAUDE_CONFIG_DIR=$T/cfg WB_SPACE_ROOT=$T/repo/sub WB_BEAD=acme-a2 WB_WORKTREE=$WTTOP claude --settings "
assert_contains "worktree bead: protocol line" "$out" "Before anything else, read docs/PROTOCOL.md"
assert_contains "worktree bead: told to ship with wb-ship" "$out" "ship it with \`wb-ship\`: it pushes the branch"
assert_contains "worktree bead: merging is the owner's call" "$out" "only after I say yes"
po="$(z "$PLAIN" '_wb_prompt work-on-bead bee-1')"
assert_not_contains "plain bead: no wb-ship step (no worktree, no branch to ship)" "$po" "wb-ship"
assert_eq "plain bead: no blank line where the ship step would be" "$(printf '%s\n' "$po" | tail -1 | cut -c1-3)" "3. "
assert_contains "worktree bead: shell lands in the worktree" "$out" "PWD=$T/wt/proj"

out="$(z "$WT" 'update_terminal_cwd() { print "OSC7=$PWD" }; _wb_start_bead acme-a2' 2>&1)"
assert_contains "Terminal is told the new folder before Claude starts" "$(printf '%s\n' "$out" | grep -E '^(OSC7|DRY-RUN)' | tr '\n' '|')" "OSC7=$T/wt/proj|DRY-RUN"

z "$WT" '_wb_start_new' >/dev/null 2>&1
assert_eq "worktree new: new-session got the space key" "$(tail -1 "$T/ns.log")" "acme --no-launch"

out="$(cd "$T/proj dir" && FAKE_NS_RC=1 z "$WT" '_wb_start_bead acme-a2; print "PWD=$PWD"' 2>&1)"
assert_contains "new-session failure is reported" "$out" "did not finish"
assert_contains "new-session failure lands in HOME" "$out" "PWD=$HOME"
assert_not_contains "new-session failure starts nothing" "$out" "DRY-RUN"

out="$(FAKE_NS_INT=1 z "$WT" '_wb_start_bead acme-a2; print "PWD=$PWD"' 2>&1)"
assert_contains "Ctrl-C in new-session: says so" "$out" "interrupted"
assert_contains "Ctrl-C in new-session: says how to find a half-made worktree" "$out" "git -C $T/repo/sub worktree list"
assert_contains "Ctrl-C in new-session: lands in HOME" "$out" "PWD=$HOME"
assert_not_contains "Ctrl-C in new-session: starts nothing" "$out" "DRY-RUN"

# no conversation ever ran in the worktree (for the space's account): claude --continue would
# only say "No conversation found to continue", so a fresh session starts on the bead instead
out="$(printf 'y\n' | z "$WT" "_wb_start_claimed acme-c2 '$T/wt-x'; print \"rc=\$? PWD=\$PWD\"" 2>&1)"
assert_contains "◐ no conversation in the worktree: says so" "$out" "no earlier conversation"
assert_contains "◐ no conversation: a fresh session on the bead" "$out" "Work on bead acme-c2 in Acme."
assert_not_contains "◐ no conversation: not --continue" "$out" "--continue"
assert_contains "◐ no conversation: still in the worktree's subfolder" "$out" "PWD=$T/wt-x/sub"
# Claude keeps a folder's conversations under <config>/projects/<its real path, non-alphanumerics as ->
mkdir -p "$T/cfg/projects/$(cd "$T/wt-x/sub" && pwd -P | sed 's/[^A-Za-z0-9]/-/g')"
: > "$T/cfg/projects/$(cd "$T/wt-x/sub" && pwd -P | sed 's/[^A-Za-z0-9]/-/g')/s1.jsonl"
out="$(printf 'y\n' | z "$WT" "_wb_start_claimed acme-c2 '$T/wt-x'; print \"rc=\$? PWD=\$PWD\"" 2>&1)"
assert_contains "◐ with worktree: resumes with --continue" "$out" " --dangerously-skip-permissions --continue"
assert_contains "◐ resume: WB_BEAD and WB_WORKTREE" "$out" "WB_BEAD=acme-c2 WB_WORKTREE=$WTXTOP claude --settings "
assert_contains "◐ with worktree: cd into the same subfolder" "$out" "PWD=$T/wt-x/sub"

out="$(printf 'n\n' | z "$WT" "_wb_start_claimed acme-c2 '$T/wt-x'; print \"rc=\$?\"" 2>&1)"
assert_contains "◐ resume declined goes back" "$out" "rc=1"

out="$(printf '\n' | z "$WT" "_wb_start_claimed acme-c2 '$T/gone'; print \"rc=\$?\"" 2>&1)"
assert_contains "◐ without worktree: stale claim shown" "$out" "stale claim"
assert_contains "◐ without worktree: waits so the message is read before fzf redraws" "$out" "Press Enter to go back"
assert_contains "◐ without worktree: back to screen 2" "$out" "rc=1"
assert_not_contains "◐ without worktree: no launch" "$out" "DRY-RUN"

out="$(printf 'n\n' | z "$PLAIN" "_wb_start_claimed bee-1 -; print \"rc=\$?\"" 2>&1)"
assert_contains "◐ in a plain space: declining goes back" "$out" "rc=1"
out="$(printf 'y\n' | z "$PLAIN" "_wb_start_claimed bee-1 -" 2>&1)"
assert_contains "◐ in a plain space: accepting starts it" "$out" "Work on bead bee-1"
out="$(z "$PLAIN" 'WORKBENCH_HOME=/nonexistent; _wb_start_bead bee-1' 2>&1)"
assert_contains "no hooks script: still launches" "$out" "WB_BEAD=bee-1 claude --dangerously-skip-permissions"
finish
