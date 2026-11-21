#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
S="$REPO/bin/wb-ship"
unset WB_SHIP_TTY FAKE_GH_PRS FAKE_GH_REPO FAKE_GH_CHECKS_FILE FAKE_GH_MERGE_RC
export WORKBENCH_CONFIG="$T/spaces.toml" WB_SHIP_INTERVAL=0 WB_SHIP_GRACE=0 FAKE_GH_LOG="$T/gh.log"
conf() { printf '[[space]]\nname = "Acme"\nroot = "%s"\nworktrees = true\nspace_key = "acme"\n%s\n' "$1" "${2:-}" > "$WORKBENCH_CONFIG"; }
wt() { local p="$1-wt-$(printf '%s' "$2" | tr / -)"; git -C "$1" worktree add -q -b "$2" "$p" main; printf '%s\n' "$p"; }
commit() { echo "$2" > "$1/$2.txt"; git -C "$1" add "$2.txt"; git -C "$1" commit -q -m "add $2"; }
checks() { printf '%s\n' "$@" > "$T/checks"; export FAKE_GH_CHECKS_FILE="$T/checks"; }
GREEN_JSON='[{"name":"tests","bucket":"pass","link":"https://ci/1"}]'
log() { cat "$T/gh.log" 2>/dev/null; }
fresh() { rm -f "$T/gh.log"; }

h="$T/r"; setup_repo "$h"; mkstore "$h"; conf "$h"

# ---- refusals
w=$(wt "$h" feat/dirty); echo x > "$w/x.txt"
out=$("$S" "$w" 2>&1); rc=$?
assert_eq "dirty: refused" "$rc" "1"; assert_contains "dirty: says so" "$out" "uncommitted changes"
out=$("$S" "$h" 2>&1); rc=$?
assert_eq "on the default branch: refused" "$rc" "1"; assert_contains "and says so" "$out" "on main"

fresh; w=$(wt "$h" feat/empty)
out=$("$S" "$w" 2>&1); rc=$?
assert_eq "nothing beyond main: exits 0" "$rc" "0"; assert_contains "says nothing to ship" "$out" "nothing to ship"
assert_not_contains "and opens no pull request" "$(log)" "pr create"

# ---- green, no terminal, no yes: stops for the owner, saying the exact command
fresh; checks "$GREEN_JSON"
w=$(wt "$h" feat/green); commit "$w" g; sha=$(git -C "$w" rev-parse HEAD)
out=$("$S" "$w" 2>&1); rc=$?
assert_eq "green without a yes: exits 10" "$rc" "10"
assert_eq "pushed the branch" "$(git -C "$h" ls-remote origin refs/heads/feat/green | cut -f1)" "$sha"
assert_contains "opened the pull request against main from the branch" "$(log)" "pr create --base main --head feat/green --fill"
assert_contains "names it" "$out" "PR #7"
assert_contains "says merging is the owner's call, with the command bound to this commit" "$out" "wb-ship --yes=${sha:0:12}"
assert_not_contains "merged nothing" "$(log)" "pr merge"

# ---- the yes, bound to the commit CI checked
fresh; checks "$GREEN_JSON"
out=$("$S" --yes="${sha:0:12}" "$w" 2>&1); rc=$?
assert_eq "yes on green: exits 0" "$rc" "0"
assert_contains "merges exactly the checked head, by the repo's default method" "$(log)" "pr merge 7 --squash --match-head-commit $sha"
for f in --delete-branch --admin --auto; do assert_not_contains "never $f" "$(log)" "$f"; done
assert_contains "reuses the open pull request" "$out" "PR #7"
assert_contains "says how to end the session" "$out" "end-session"
assert_contains "... which is /exit: the launcher ends it" "$out" "When you /exit, the launcher removes this worktree"

fresh; checks "$GREEN_JSON"
out=$("$S" --yes=0000000deadbeef "$w" 2>&1); rc=$?
assert_eq "a yes for another commit: refused" "$rc" "1"
assert_contains "and says HEAD isn't what was approved" "$out" "not the commit"
assert_not_contains "merged nothing" "$(log)" "pr merge"

# ---- red never merges
fresh; checks '[{"name":"tests","bucket":"fail","link":"https://ci/2"},{"name":"lint","bucket":"pass","link":""}]'
out=$("$S" --yes="$sha" "$w" 2>&1); rc=$?
assert_eq "red: exits 1" "$rc" "1"; assert_contains "names the failing check" "$out" "tests"
assert_not_contains "red: merged nothing, even with a yes" "$(log)" "pr merge"
fresh; checks '[{"name":"tests","bucket":"cancel","link":""}]'
"$S" --yes="$sha" "$w" >/dev/null 2>&1; assert_eq "cancelled counts as red" "$?" "1"

# ---- waiting
fresh; checks '[{"name":"tests","bucket":"pending","link":""}]' "$GREEN_JSON"
"$S" --yes="$sha" "$w" >/dev/null 2>&1; assert_eq "pending, then green: merged" "$?" "0"
fresh; checks '[{"name":"tests","bucket":"pending","link":""}]'
out=$("$S" --wait=0 "$w" 2>&1); rc=$?
assert_eq "still pending at the deadline: exits 11" "$rc" "11"; assert_contains "and says to run it again" "$out" "run wb-ship again"
fresh; checks none "$GREEN_JSON"
WB_SHIP_GRACE=60 "$S" --yes="$sha" "$w" >/dev/null 2>&1
assert_eq "no checks yet, inside the grace period: waits for them" "$?" "0"
assert_contains "and merged once they passed" "$(log)" "pr merge"
fresh; checks none
out=$("$S" "$w" 2>&1); rc=$?
assert_eq "no checks after the grace period: green, waiting for a yes" "$rc" "10"
assert_contains "says no CI ran" "$out" "no CI checks"
fresh; checks '[{"name":"docs","bucket":"skipping","link":""}]'
"$S" "$w" >/dev/null 2>&1; assert_eq "skipped checks count as passing" "$?" "10"

# ---- existing pull requests
fresh; checks "$GREEN_JSON"
export FAKE_GH_PRS='[{"number":9,"state":"OPEN","headRefOid":"x","url":"https://github.com/acme/app/pull/9"}]'
out=$("$S" "$w" 2>&1)
assert_not_contains "an open pull request is reused" "$(log)" "pr create"; assert_contains "and named" "$out" "PR #9"
fresh; export FAKE_GH_PRS="[{\"number\":5,\"state\":\"MERGED\",\"headRefOid\":\"$sha\",\"url\":\"u\"}]"
out=$("$S" "$w" 2>&1); rc=$?
assert_eq "already merged at this HEAD: exits 0" "$rc" "0"; assert_contains "says so" "$out" "already merged by PR #5"
assert_not_contains "and opens nothing" "$(log)" "pr create"
fresh; export FAKE_GH_PRS='[{"number":4,"state":"MERGED","headRefOid":"old","url":"u"},{"number":3,"state":"CLOSED","headRefOid":"x","url":"u"}]'
checks "$GREEN_JSON"; "$S" "$w" >/dev/null 2>&1
assert_contains "a merged PR behind HEAD or a closed one: a new pull request" "$(log)" "pr create"
unset FAKE_GH_PRS

# ---- merge method
fresh; checks "$GREEN_JSON"; "$S" --yes="$sha" --method=merge "$w" >/dev/null 2>&1
assert_contains "--method=merge" "$(log)" "pr merge 7 --merge --match-head-commit"
fresh; checks "$GREEN_JSON"; FAKE_GH_REPO='{"viewerDefaultMergeMethod":"REBASE","mergeCommitAllowed":false,"squashMergeAllowed":false,"rebaseMergeAllowed":true}' \
  "$S" --yes="$sha" "$w" >/dev/null 2>&1
assert_contains "the repo's default: rebase" "$(log)" "pr merge 7 --rebase"
fresh; checks "$GREEN_JSON"; out=$(FAKE_GH_REPO='oops' "$S" --yes="$sha" "$w" 2>&1); rc=$?
assert_eq "repo settings unreadable and no --method: refused" "$rc" "1"; assert_contains "says to pass one" "$out" "--method"
assert_not_contains "and merges nothing" "$(log)" "pr merge"
out=$("$S" --method=fast "$w" 2>&1); assert_eq "a bad --method: usage" "$?" "2"

fresh; checks "$GREEN_JSON"; out=$(FAKE_GH_MERGE_RC=1 FAKE_GH_MERGE_ERR="Pull request is not mergeable: the base branch policy" "$S" --yes="$sha" "$w" 2>&1); rc=$?
assert_eq "GitHub refuses the merge: exits 1" "$rc" "1"; assert_contains "with gh's reason" "$out" "base branch policy"

# ---- asking on a terminal
fresh; checks "$GREEN_JSON"; out=$(echo n | WB_SHIP_TTY=1 "$S" "$w" 2>&1); rc=$?
assert_eq "terminal, no: exits 10" "$rc" "10"; assert_contains "asked" "$out" "Merge PR #7 into main"
assert_not_contains "no: merged nothing" "$(log)" "pr merge"
fresh; checks "$GREEN_JSON"; echo y | WB_SHIP_TTY=1 "$S" "$w" >/dev/null 2>&1
assert_eq "terminal, yes: exits 0" "$?" "0"; assert_contains "yes: merged" "$(log)" "pr merge 7 --squash"

# ---- its bead hears about it
fresh; checks "$GREEN_JSON"
w=$(wt "$h" feat/noted); commit "$w" n; nsha=$(git -C "$w" rev-parse HEAD)
printf '[{"id":"acme-1","title":"Noted","status":"in_progress","notes":"Branch: feat/noted (worktree at %s)"}]\n' "$w" > "$h/.beads/fake.json"
FAKE_BD_LOG="$T/bd.log" "$S" --yes="$nsha" "$w" >/dev/null 2>&1
assert_contains "bead: the pull request is noted" "$(cat "$T/bd.log")" "update acme-1 --append-notes PR #7 opened: https://github.com/acme/app/pull/7"
assert_contains "bead: the merge is noted" "$(cat "$T/bd.log")" "update acme-1 --append-notes PR #7 merged into main by squash at ${nsha:0:10}"

# ---- the space's GitHub account, as new-session uses it
conf "$h" 'gh_account = "acme-bot"'
fresh; checks "$GREEN_JSON"; FAKE_GH_ACTIVE=someone "$S" "$w" >/dev/null 2>&1
assert_contains "switches gh to the space's account first" "$(head -3 "$T/gh.log")" "auth switch --user acme-bot"
conf "$h"

# ---- the space's before_end gate runs before any merge, as end-session would have run it
export MARKERS="$T/markers"; mkdir -p "$MARKERS"
conf "$h" "before_end = 'test -f \"\$MARKERS/\$WB_SHA\" || { echo \"predeploy has not passed\"; exit 1; }; echo \"\$WB_SPACE|\$WB_BRANCH|\$PWD\" > \"\$MARKERS/env\"'"
fresh; checks "$GREEN_JSON"
w=$(wt "$h" feat/gated); commit "$w" gt; gsha=$(git -C "$w" rev-parse HEAD)
out=$("$S" --yes="$gsha" "$w" 2>&1); rc=$?
assert_eq "before_end fails: refused" "$rc" "1"
assert_contains "before_end fails: its output shown" "$out" "predeploy has not passed"
assert_not_contains "before_end fails: merged nothing, even with a yes" "$(log)" "pr merge"
touch "$MARKERS/$gsha"; fresh; checks "$GREEN_JSON"
"$S" --yes="$gsha" "$w" >/dev/null 2>&1; assert_eq "before_end passes: merged" "$?" "0"
assert_eq "before_end: run with the hook variables, in the project folder" "$(cat "$MARKERS/env")" "acme|feat/gated|$w"
fresh; checks '[{"name":"tests","bucket":"fail","link":""}]'; rm -f "$MARKERS/env"
"$S" "$w" >/dev/null 2>&1
[ -e "$MARKERS/env" ] && bad "red: before_end not run" || ok "red: before_end not run"
conf "$h"

# ---- nothing to ship says how to end the session
out=$("$S" "$(wt "$h" feat/nothing)" 2>&1)
assert_contains "nothing to ship: the end-session line" "$out" "end-session"

# ---- a rejected push stops everything
fresh; w=$(wt "$h" feat/rejected); commit "$w" a; git -C "$w" push -q -u origin feat/rejected
git -C "$w" commit -q --amend -m "rewritten"
out=$("$S" "$w" 2>&1); rc=$?
assert_eq "push rejected: exits 1" "$rc" "1"; assert_contains "says the push failed" "$out" "push"
assert_not_contains "no pull request" "$(log)" "pr create"

# ---- no origin
n="$T/noorigin"; git init -q -b main "$n"; git -C "$n" config user.email t@example.com; git -C "$n" config user.name t
git -C "$n" commit -q --allow-empty -m init; git -C "$n" checkout -q -b feat/x; git -C "$n" commit -q --allow-empty -m x
out=$("$S" "$n" 2>&1); rc=$?
assert_eq "no origin: refused" "$rc" "1"; assert_contains "and says so" "$out" "no origin"
finish
