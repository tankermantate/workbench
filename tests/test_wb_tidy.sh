#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # macOS /var is /private/var; git reports the real path
W="$REPO/bin/wb-tidy"
unset CLAUDE_CONFIG_DIR WB_SPACE_ROOT WB_BEAD WB_WORKTREE WORKBENCH_DRY_RUN

export HOME="$T/home" WORKBENCH_CONFIG="$T/spaces.toml" WB_WORKTREES_DIR="$T/wts"
export FAKE_PS_OUT="$T/ps.out" FAKE_PS_ARGS="$T/ps.args"
# never the real end-session: log each worktree it's asked to end; FAIL_FOR names one it refuses
cat > "$T/fake-end" <<'EOF'
#!/bin/sh
echo "$1" >> "$END_LOG"
case "$1" in *"${FAIL_FOR:-/none/}"*) echo "end-session: the worktree has uncommitted changes" >&2; exit 1 ;; esac
echo "✓ session ended."
EOF
chmod +x "$T/fake-end"
export WB_END_SESSION="$T/fake-end" END_LOG="$T/end.log"
CFG="$HOME/.claude"; mkdir -p "$CFG/sessions" "$T/wts"

setup_repo "$T/acme" >/dev/null 2>&1
mkstore "$T/acme"
cat > "$T/spaces.toml" <<EOF
[[space]]
name      = "Acme"
root      = "$T/acme"
worktrees = true
space_key = "acme"
EOF
wt() { git -C "$T/acme" worktree add -q -b "$2" "$T/wts/$1" 2>/dev/null; }
wt acme-done feat/done          # bead closed, merged, clean: offered
wt acme-nobead explore/x        # no bead, merged, clean: kept unless --no-bead
wt acme-open feat/open          # its bead is still open
wt acme-unmerged feat/unmerged  # a commit main doesn't have
git -C "$T/wts/acme-unmerged" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m wip
wt acme-dirty feat/dirty        # an uncommitted file
: > "$T/wts/acme-dirty/notes.txt"
wt acme-live explore/live       # a Claude session is open inside it
wt acme-rewritten feat/rewritten  # its bead's notes were replaced; the link is in its metadata
mkdir -p "$T/wts/acme-live/sub" "$T/wts/stray"   # stray: no space's repo has it as a worktree
note() { printf 'Claimed by new-session (worktree at %s)' "$T/wts/$1"; }
python3 - "$T/acme/.beads/fake.json" "$(note acme-done)" "$(note acme-open)" "$(note acme-unmerged)" "$T/wts/acme-rewritten" <<'PY'
import json, sys
p, done, opn, unm, rew = sys.argv[1:]
json.dump([
  {"id": "ac-4", "title": "Rewritten one", "status": "closed", "notes": "Branch: feat/rewritten. Notes since replaced.",
   "metadata": {"wb_worktree": rew}, "updated_at": "2026-11-10T00:00:00Z"},
  {"id": "ac-1", "title": "Done one", "status": "closed", "notes": done, "updated_at": "2026-11-10T00:00:00Z"},
  {"id": "ac-2", "title": "Open one", "status": "in_progress", "notes": opn, "updated_at": "2026-11-10T00:00:00Z"},
  {"id": "ac-3", "title": "Unmerged one", "status": "closed", "notes": unm, "updated_at": "2026-11-10T00:00:00Z"},
], open(p, "w"))
PY

# the session open in acme-live: login > -zsh > claude on ttys001, its pid file naming the folder
printf '101 1 ttys001 login\n102 101 ttys001 -zsh\n103 102 ttys001 claude\n' > "$T/ps.out"
printf '{"pid": 103, "sessionId": "sid-live", "cwd": "%s/sub", "kind": "interactive", "startedAt": 1}' \
  "$T/wts/acme-live" > "$CFG/sessions/103.json"

line() { printf '%s\n' "$1" | grep -F -- "$2" | head -1; }

# ---- the list, and what's offered
out=$(WORKBENCH_DRY_RUN=1 "$W" </dev/null 2>&1); rc=$?
assert_eq "dry run exits 0" "$rc" "0"
assert_contains "a closed bead's merged, clean worktree is offered" "$(line "$out" acme-done)" "offer"
assert_contains "with its bead" "$(line "$out" acme-done)" "ac-1 closed"
assert_contains "a bead whose notes were replaced still names its worktree" "$(line "$out" acme-rewritten)" "  offer  acme-rewritten"
assert_contains "through its metadata" "$(line "$out" acme-rewritten)" "ac-4 closed"
assert_contains "no bead names it: kept, since done can't be told" "$(line "$out" acme-nobead)" "keep"
assert_contains "and says how to include it" "$(line "$out" acme-nobead)" "no bead names it; wb-tidy --no-bead"
assert_contains "an open bead keeps it" "$(line "$out" acme-open)" "keep"
assert_contains "and says so" "$(line "$out" acme-open)" "ac-2 is in_progress"
assert_contains "an unmerged branch keeps it" "$(line "$out" acme-unmerged)" "not merged into main"
assert_contains "uncommitted changes keep it" "$(line "$out" acme-dirty)" "uncommitted changes"
assert_contains "a live session keeps it" "$(line "$out" acme-live)" "a Claude session is open in it"
assert_contains "a folder no space claims is listed" "$(line "$out" stray)" "keep"
assert_contains "and never offered" "$(line "$out" stray)" "not a worktree of any space"
assert_contains "dry run says what it would end" "$out" "DRY-RUN: would end 2"
# --count (wb-kvx.22): the launcher's first screen, how many it would offer and nothing else
assert_eq "--count: the number offered, alone" "$("$W" --count </dev/null 2>&1)" "2"
: > "$T/end.log"; "$W" --count </dev/null >/dev/null 2>&1
assert_eq "--count: ends nothing" "$(cat "$T/end.log")" ""
out=$(WORKBENCH_DRY_RUN=1 "$W" --no-bead </dev/null 2>&1)
assert_contains "--no-bead: a merged, clean worktree with no bead is offered" "$(line "$out" acme-nobead)" "offer"
assert_contains "--no-bead: said as such" "$(line "$out" acme-nobead)" "no bead · merged · clean"
assert_contains "--no-bead: an open bead still keeps one" "$(line "$out" acme-open)" "keep"
assert_contains "--no-bead: would end 3" "$out" "DRY-RUN: would end 3"
[ -s "$T/end.log" ] && bad "dry run ends nothing" || ok "dry run ends nothing"

# ---- asking
out=$("$W" </dev/null 2>&1); rc=$?
assert_eq "no terminal to answer on: exits 1" "$rc" "1"
assert_contains "and says it couldn't ask" "$out" "couldn't ask"
[ -s "$T/end.log" ] && bad "can't ask: nothing ended" || ok "can't ask: nothing ended"

out=$(echo n | "$W" 2>&1); rc=$?
assert_contains "no: nothing ended" "$out" "nothing ended"
[ -s "$T/end.log" ] && bad "no: end-session never ran" || ok "no: end-session never ran"

out=$(echo y | "$W" --no-bead 2>&1); rc=$?
assert_eq "yes exits 0" "$rc" "0"
assert_eq "end-session ran on each offered worktree, one at a time" "$(cat "$T/end.log")" "$T/wts/acme-done
$T/wts/acme-nobead
$T/wts/acme-rewritten"
assert_contains "and its output is shown" "$out" "session ended"
rm -f "$T/end.log"

out=$(echo y | FAIL_FOR=acme-done "$W" --no-bead 2>&1); rc=$?
assert_eq "a refusal: exits 1" "$rc" "1"
assert_eq "and stops there" "$(cat "$T/end.log")" "$T/wts/acme-done"
assert_contains "saying which refused" "$out" "end-session refused acme-done"
assert_contains "and what's left untouched" "$out" "2 left as it was"
assert_contains "end-session's own reason shows" "$out" "uncommitted changes"
rm -f "$T/end.log"

# ---- fail closed
out=$(WORKBENCH_DRY_RUN=1 FAKE_PS_RC=1 "$W" </dev/null 2>&1); rc=$?
assert_eq "ps failing: refuses" "$rc" "1"
assert_contains "and says why" "$out" "can't tell which worktrees have a Claude session open"
assert_not_contains "offers nothing" "$out" "would end"
FAKE_PS_RC=1 "$W" --count >"$T/count.out" 2>/dev/null; rc=$?
assert_eq "--count: can't tell, exits 1" "$rc" "1"; assert_eq "--count: ... and prints no number" "$(cat "$T/count.out")" ""

printf '201 1 ttys002 login\n202 201 ttys002 -zsh\n203 202 ttys002 claude\n' >> "$T/ps.out"   # no pid file
out=$(WORKBENCH_DRY_RUN=1 "$W" </dev/null 2>&1); rc=$?
assert_eq "a claude whose folder can't be told: refuses" "$rc" "1"
assert_contains "and says why" "$out" "1 open Claude session"
printf '101 1 ttys001 login\n102 101 ttys001 -zsh\n103 102 ttys001 claude\n' > "$T/ps.out"

out=$(WORKBENCH_DRY_RUN=1 WB_BD=false "$W" --no-bead </dev/null 2>&1); rc=$?
assert_contains "beads unreadable: nothing in that space is offered" "$(line "$out" acme-nobead)" "keep"
assert_contains "and says why" "$(line "$out" acme-nobead)" "couldn't read Acme's beads"
assert_not_contains "nothing would be ended" "$out" "would end"

# ---- squash-merged through a pull request: not an ancestor of main, but gh knows
wt acme-squashed feat/squashed
echo s > "$T/wts/acme-squashed/s.txt"
git -C "$T/wts/acme-squashed" add s.txt
git -C "$T/wts/acme-squashed" -c user.email=t@example.com -c user.name=t commit -q -m s
git -C "$T/acme" merge -q --squash feat/squashed >/dev/null
git -C "$T/acme" -c user.email=t@example.com -c user.name=t commit -q -m "squash"
python3 - "$T/acme/.beads/fake.json" "$(note acme-squashed)" <<'PY'
import json, sys
p, n = sys.argv[1:]
d = json.load(open(p))
d.append({"id": "ac-5", "title": "Squashed one", "status": "closed", "notes": n, "updated_at": "2026-11-10T00:00:00Z"})
json.dump(d, open(p, "w"))
PY
tip=$(git -C "$T/wts/acme-squashed" rev-parse HEAD)
PRS="[{\"number\":21,\"headRefName\":\"feat/squashed\",\"headRefOid\":\"$tip\",\"baseRefName\":\"main\"},
      {\"number\":22,\"headRefName\":\"feat/unmerged\",\"headRefOid\":\"0000000\",\"baseRefName\":\"main\"}]"
out=$(WORKBENCH_DRY_RUN=1 FAKE_GH_LOG="$T/gh.log" FAKE_GH_PRS="$PRS" "$W" </dev/null 2>&1)
assert_contains "squash-merged by a PR: offered" "$(line "$out" acme-squashed)" "  offer  acme-squashed"
assert_contains "and says how it knows" "$(line "$out" acme-squashed)" "squash-merged by PR #21"
assert_contains "a merged PR whose head isn't the worktree's HEAD doesn't count" "$(line "$out" acme-unmerged)" "not merged into main"
assert_eq "one gh call for the repo, not one per worktree" "$(grep -c '^pr list' "$T/gh.log")" "1"
out=$(WORKBENCH_DRY_RUN=1 FAKE_GH_PR_RC=1 FAKE_GH_PRS="$PRS" "$W" </dev/null 2>&1)
assert_contains "gh failing: kept" "$(line "$out" acme-squashed)" "keep"
assert_contains "and says gh couldn't tell" "$(line "$out" acme-squashed)" "not merged into main (gh couldn't check for a merged pull request)"

finish
