#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
ES="$REPO/bin/end-session"
export WORKBENCH_CONFIG="$T/spaces.toml" MARKERS="$T/markers"; mkdir -p "$MARKERS"
GATE="before_end = 'test -f \"\$MARKERS/\$WB_SHA\" || { echo \"predeploy has not passed\"; exit 1; }'"
# conf ROOT [EXTRA-LINE]: one worktree space "acme" at ROOT
conf() { printf '[[space]]\nname = "Acme"\nroot = "%s"\nworktrees = true\nspace_key = "acme"\n%s\n' "$1" "${2:-}" > "$WORKBENCH_CONFIG"; }
# wt REPO BRANCH [BASE]: a worktree beside REPO; prints its path
wt() { local p="$1-wt-$(printf '%s' "$2" | tr / -)"; git -C "$1" worktree add -q -b "$2" "$p" "${3:-main}"; printf '%s\n' "$p"; }
commit() { echo "$2" > "$1/$2.txt"; git -C "$1" add "$2.txt"; git -C "$1" commit -q -m "add $2"; }
gone()  { if [ ! -e "$2" ]; then ok "$1"; else bad "$1" "still there: $2"; fi; }
there() { if [ -e "$2" ]; then ok "$1"; else bad "$1" "missing: $2"; fi; }
branch_gone() { if git -C "$2" show-ref --verify --quiet "refs/heads/$3"; then bad "$1"; else ok "$1"; fi; }
branch_kept() { if git -C "$2" show-ref --verify --quiet "refs/heads/$3"; then ok "$1"; else bad "$1"; fi; }

# 1 merged branch is deleted
h="$T/r1"; setup_repo "$h"; conf "$h"
w=$(wt "$h" feat/one); commit "$w" x; git -C "$w" push -q -u origin feat/one
git -C "$h" merge -q --ff-only feat/one; git -C "$h" push -q origin main
"$ES" "$w" >/dev/null 2>&1; assert_eq "merged: exits 0" "$?" "0"
gone "merged: worktree removed" "$w"; branch_gone "merged: branch deleted" "$h" feat/one

# 2 unmerged but pushed: removed, branch kept
w=$(wt "$h" feat/two); commit "$w" y; git -C "$w" push -q -u origin feat/two
"$ES" "$w" >/dev/null 2>&1
gone "unmerged: worktree removed" "$w"; branch_kept "unmerged: branch kept" "$h" feat/two

# 3 --force keeps even a merged branch
w=$(wt "$h" feat/three); commit "$w" z; git -C "$w" push -q -u origin feat/three
git -C "$h" merge -q --ff-only feat/three; git -C "$h" push -q origin main
"$ES" --force "$w" >/dev/null 2>&1
gone "force: worktree removed" "$w"; branch_kept "force: branch kept" "$h" feat/three

# 4 --base=develop
git -C "$h" checkout -q -b develop; git -C "$h" push -q -u origin develop; git -C "$h" checkout -q main
w=$(wt "$h" feat/four develop); commit "$w" w; git -C "$w" push -q -u origin feat/four
git -C "$h" checkout -q develop; git -C "$h" merge -q --ff-only feat/four; git -C "$h" push -q origin develop; git -C "$h" checkout -q main
"$ES" --base=develop "$w" >/dev/null 2>&1
gone "base: worktree removed" "$w"; branch_gone "base: merged into develop, deleted" "$h" feat/four

# 5 never-pushed, no commits: nothing at risk
w=$(wt "$h" fix/five)
"$ES" "$w" >/dev/null 2>&1; assert_eq "empty branch: exits 0" "$?" "0"
gone "empty branch: removed" "$w"; branch_gone "empty branch: deleted" "$h" fix/five

# 6 merged, then rebased past its own stale upstream
w=$(wt "$h" feat/six); commit "$w" v; git -C "$w" push -q -u origin feat/six
git -C "$h" merge -q --no-ff -m "merge six" feat/six; git -C "$h" push -q origin main
git -C "$w" fetch -q origin; git -C "$w" rebase -q origin/main
"$ES" "$w" >/dev/null 2>&1; assert_eq "ahead of stale upstream: exits 0" "$?" "0"
branch_gone "ahead of stale upstream: deleted" "$h" feat/six

# 7 before_end skipped when nothing is at risk
conf "$h" "$GATE"
w=$(wt "$h" fix/seven)
"$ES" "$w" >/dev/null 2>&1; assert_eq "gate: skipped with nothing at risk" "$?" "0"

# 8 never-pushed work is refused
w=$(wt "$h" feat/eight); commit "$w" u
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "unpushed: refused" "$rc" "1"; assert_contains "unpushed: says so" "$out" "not pushed"
there "unpushed: worktree kept" "$w"

# 9 before_end refuses real work until it passes
w=$(wt "$h" feat/nine); commit "$w" t; git -C "$w" push -q -u origin feat/nine
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "gate: refuses without a marker" "$rc" "1"
assert_contains "gate: shows the hook's output" "$out" "predeploy has not passed"
there "gate: worktree kept" "$w"
touch "$MARKERS/$(git -C "$w" rev-parse HEAD)"
"$ES" "$w" >/dev/null 2>&1; assert_eq "gate: passes with a marker" "$?" "0"

# 10 dirty is refused, even with nothing beyond main
w=$(wt "$h" fix/ten); echo s > "$w/s.txt"
"$ES" "$w" >/dev/null 2>&1; assert_eq "dirty: refused" "$?" "1"; there "dirty: kept" "$w"
rm "$w/s.txt"

# 11 hook variables, project below the repo top, run from inside the worktree
mkdir -p "$h/app"; : > "$h/app/keep"; git -C "$h" add app; git -C "$h" commit -q -m app; git -C "$h" push -q origin main
conf "$h/app" "before_end = 'env | grep ^WB_ | sort > \"\$MARKERS/env\"'"
w=$(wt "$h" feat/eleven); commit "$w" e; git -C "$w" push -q -u origin feat/eleven
sha=$(git -C "$w" rev-parse HEAD)
mkstore "$h/app"   # new-session's claim note is how end-session finds the bead
printf '[{"id":"acme-7","title":"Eleven","status":"in_progress","notes":"Branch: feat/eleven (worktree at %s)"}]\n' "$w" > "$h/app/.beads/fake.json"
(cd "$w/app" && FAKE_BD_LOG="$T/bd.log" "$ES" >/dev/null 2>&1); assert_eq "from inside: exits 0" "$?" "0"
gone "from inside: removed" "$w"
env_out="$(cat "$MARKERS/env" 2>/dev/null)"
assert_contains "hook: WB_SPACE" "$env_out" "WB_SPACE=acme"
assert_contains "hook: WB_WORKTREE" "$env_out" "WB_WORKTREE=$w"
assert_contains "hook: WB_PROJECT" "$env_out" "WB_PROJECT=$w/app"
assert_contains "hook: WB_SOURCE" "$env_out" "WB_SOURCE=$h/app"
assert_contains "hook: WB_SHA" "$env_out" "WB_SHA=$sha"
assert_contains "hook: WB_BEAD from the claim note" "$env_out" "WB_BEAD=acme-7"
assert_contains "bead: close-out noted, not closed" "$(cat "$T/bd.log")" \
  "update acme-7 --append-notes Session ended: worktree removed; branch feat/eleven kept, not merged into main."
assert_not_contains "bead: never closed" "$(cat "$T/bd.log")" "close"
rm -rf "$h/app/.beads"

# 12 no origin
n="$T/noorigin"; git init -q -b main "$n"; git -C "$n" config user.email t@example.com; git -C "$n" config user.name t
commit "$n" base; conf "$n"
w=$(wt "$n" feat/local); commit "$w" l
out="$("$ES" "$w" 2>&1)"; assert_eq "no origin: unmerged work ends" "$?" "0"
assert_contains "no origin: says the push check was skipped" "$out" "no origin remote, so there is nothing to push to"
branch_kept "no origin: unmerged branch kept" "$n" feat/local
w=$(wt "$n" feat/merged); commit "$w" m; git -C "$n" merge -q --ff-only feat/merged
"$ES" "$w" >/dev/null 2>&1; branch_gone "no origin: merged branch deleted" "$n" feat/merged

# 13 no space claims the repo
conf "$T/markers"
w=$(wt "$h" fix/thirteen)
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "unclaimed: refused (a missed lookup must not skip a gate)" "$rc" "1"
there "unclaimed: kept" "$w"; assert_contains "unclaimed: names the override" "$out" "--no-space"
out="$("$ES" --no-space "$w" 2>&1)"; rc=$?
assert_eq "unclaimed + --no-space: goes ahead" "$rc" "0"; gone "unclaimed + --no-space: removed" "$w"
assert_contains "unclaimed + --no-space: says no before_end ran" "$out" "no before_end check ran"

# 14 unreadable config fails closed
w=$(wt "$h" fix/fourteen)
out="$(WORKBENCH_CONFIG="$T/missing.toml" "$ES" "$w" 2>&1)"; rc=$?
assert_eq "no config: refused" "$rc" "1"; there "no config: kept" "$w"
assert_contains "no config: says why" "$out" "could not read spaces.toml"
WORKBENCH_CONFIG="$T/missing.toml" "$ES" --force "$w" >/dev/null 2>&1
gone "no config + --force: removed" "$w"

# 15 a master repo
m="$T/master"; setup_repo "$m" master; conf "$m"
w=$(wt "$m" feat/mm master); commit "$w" q; git -C "$w" push -q -u origin feat/mm
git -C "$m" merge -q --ff-only feat/mm; git -C "$m" push -q origin master
"$ES" "$w" >/dev/null 2>&1; branch_gone "master repo: merged branch deleted" "$m" feat/mm

# 15b a non-worktree space on the same repo, listed first, must not hide before_end
printf '[[space]]\nname = "Top"\nroot = "%s"\n[[space]]\nname = "Acme"\nroot = "%s"\nworktrees = true\nspace_key = "acme"\n%s\n' "$h" "$h" "$GATE" > "$WORKBENCH_CONFIG"
w=$(wt "$h" feat/shadow); commit "$w" sh; git -C "$w" push -q -u origin feat/shadow
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "shadowed: before_end still runs and refuses" "$rc" "1"
assert_contains "shadowed: hook output shown" "$out" "predeploy has not passed"
there "shadowed: worktree kept" "$w"

# 15c two worktree spaces on one repo: the worktree's <key>- prefix picks the space
printf '[[space]]\nname = "AA"\nroot = "%s"\nworktrees = true\nspace_key = "aa"\nbefore_end = "true"\n[[space]]\nname = "BB"\nroot = "%s/app"\nworktrees = true\nspace_key = "bb"\nbefore_end = "echo bb-gate; exit 1"\n' "$h" "$h" > "$WORKBENCH_CONFIG"
w="$T/bb-thing"; git -C "$h" worktree add -q -b feat/bb "$w" main; commit "$w" bb; git -C "$w" push -q -u origin feat/bb
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "two spaces: the bb- worktree gets bb's before_end" "$rc" "1"
assert_contains "two spaces: bb's hook ran" "$out" "bb-gate"

# 15d a repo whose path has a space: works, and the printed command is quoted
sp="$T/my repo"; setup_repo "$sp"; conf "$sp"
w=$(wt "$sp" feat/sp); commit "$w" s; git -C "$w" push -q -u origin feat/sp
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "space in path: ends" "$rc" "0"; gone "space in path: removed" "$w"
assert_contains "space in path: delete command is quoted" "$out" "git -C $(printf '%q' "$sp") branch -d feat/sp"

# 17 merged: the note says where; no bead found is a warning, not a refusal
b="$T/beadrepo"; setup_repo "$b"; conf "$b"; mkstore "$b"
w=$(wt "$b" feat/noted); commit "$w" n; git -C "$w" push -q -u origin feat/noted
git -C "$b" merge -q --ff-only feat/noted; git -C "$b" push -q origin main; sha=$(git -C "$b" rev-parse HEAD)
printf '[{"id":"acme-8","title":"Noted","status":"in_progress","notes":"Branch: feat/noted (worktree at %s)"}]\n' "$w" > "$b/.beads/fake.json"
FAKE_BD_LOG="$T/bd8.log" "$ES" "$w" >/dev/null 2>&1
assert_contains "bead: merged close-out names the commit" "$(cat "$T/bd8.log")" \
  "update acme-8 --append-notes Session ended: worktree removed; branch feat/noted merged into main at ${sha:0:10} and deleted."
w=$(wt "$b" feat/orphan)
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "no bead: still ends" "$rc" "0"; assert_contains "no bead: says so" "$out" "no bead names this worktree"

# 17b the usual end: the bead is closed and its notes were rewritten since new-session; the
# metadata still links it (bd list leaves closed beads out without --all; the fake too, so told)
w=$(wt "$b" feat/rewritten); commit "$w" r; git -C "$w" push -q -u origin feat/rewritten
git -C "$b" merge -q --ff-only feat/rewritten; git -C "$b" push -q origin main
printf '[{"id":"acme-9","title":"Rewritten","status":"closed","notes":"Branch: feat/rewritten. Replaced.","metadata":{"wb_worktree":"%s"}}]\n' "$w" > "$b/.beads/fake.json"
out="$(FAKE_BD_HIDE_CLOSED=1 FAKE_BD_LOG="$T/bd9.log" "$ES" "$w" 2>&1)"
assert_contains "closed bead, notes rewritten: found" "$out" "→ bead: acme-9"
assert_contains "closed bead, notes rewritten: close-out noted" "$(cat "$T/bd9.log")" "update acme-9 --append-notes Session ended"

# 18 stashes made on the branch are mentioned (they outlive the worktree)
w=$(wt "$b" feat/stashy); echo wip > "$w/wip.txt"; git -C "$w" add wip.txt; git -C "$w" stash -q
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "stash: still ends" "$rc" "0"
assert_contains "stash: mentioned" "$out" "1 stash made on feat/stashy is kept in the repo"

# 19 after_end: runs after removal, in the main checkout's project folder, on every path
mkdir -p "$b/app"; : > "$b/app/keep"; git -C "$b" add app; git -C "$b" commit -q -m app; git -C "$b" push -q origin main
AFTER="after_end = 'echo \"\$PWD|\$WB_WORKTREE|\$WB_PROJECT|\$(test -e \"\$WB_WORKTREE\" && echo there || echo gone)\" >> \"\$MARKERS/after\"'"
conf "$b/app" "$AFTER"
w=$(wt "$b" fix/after-empty)                      # nothing at risk
"$ES" "$w" >/dev/null 2>&1; assert_eq "after_end, nothing at risk: exits 0" "$?" "0"
assert_eq "after_end: ran once, in the main project folder, after removal, with physical paths" \
  "$(cat "$MARKERS/after")" "$b/app|$w|$w/app|gone"
w=$(wt "$b" feat/after-force); echo d > "$w/dirty.txt"
"$ES" --force "$w" >/dev/null 2>&1; assert_eq "after_end, --force: exits 0" "$?" "0"
assert_eq "after_end: ran on --force too" "$(wc -l < "$MARKERS/after" | tr -d ' ')" "2"
w=$(wt "$b" feat/after-work); commit "$w" aw; git -C "$w" push -q -u origin feat/after-work
"$ES" "$w" >/dev/null 2>&1; assert_eq "after_end, real work: exits 0" "$?" "0"
assert_eq "after_end: ran after a checked removal" "$(wc -l < "$MARKERS/after" | tr -d ' ')" "3"
# a failing hook only warns: the worktree is gone either way
conf "$b/app" "after_end = 'echo cleanup-broke; exit 3'"
w=$(wt "$b" fix/after-fail)
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "after_end fails: still exits 0" "$rc" "0"; gone "after_end fails: removed" "$w"
assert_contains "after_end fails: shows its output" "$out" "cleanup-broke"
assert_contains "after_end fails: warns" "$out" "after_end failed"
# a hung hook is cut off
conf "$b/app" "after_end = 'sleep 30'"
w=$(wt "$b" fix/after-hang)
start=$(date +%s); out="$(WB_AFTER_END_TIMEOUT=1 "$ES" "$w" 2>&1)"; rc=$?; took=$(( $(date +%s) - start ))
assert_eq "after_end hangs: still exits 0" "$rc" "0"
assert_contains "after_end hangs: warns" "$out" "after_end failed"
if [ "$took" -lt 10 ]; then ok "after_end hangs: cut off by the timeout"; else bad "after_end hangs: took ${took}s"; fi

# 20 squash-merged through a pull request: the branch's commits never reach main,
# only the squash does, so ancestry can't tell. gh can: a merged PR into main whose
# head is exactly this worktree's HEAD.
s="$T/r20"; setup_repo "$s"; conf "$s" "$GATE"
squash() {   # squash REPO BRANCH: squash-merge BRANCH into main and push, as GitHub would
  git -C "$1" merge -q --squash "$2" >/dev/null; git -C "$1" commit -q -m "squash $2"; git -C "$1" push -q origin main
}
pr() { printf '[{"number":%s,"headRefName":"%s","headRefOid":"%s","baseRefName":"%s"}]' "$1" "$2" "$3" "${4:-main}"; }
w=$(wt "$s" feat/sq); commit "$w" s1; commit "$w" s2; git -C "$w" push -q -u origin feat/sq
squash "$s" feat/sq; git -C "$s" push -q origin --delete feat/sq   # GitHub deletes the head branch
out="$(FAKE_GH_PRS="$(pr 12 feat/sq "$(git -C "$w" rev-parse HEAD)")" "$ES" "$w" 2>&1)"; rc=$?
assert_eq "squash-merged: exits 0" "$rc" "0"
gone "squash-merged: worktree removed" "$w"; branch_gone "squash-merged: branch deleted" "$s" feat/sq
assert_contains "squash-merged: says how it knows" "$out" "squash-merged into main by PR #12"
assert_not_contains "squash-merged: before_end not run (the code is on main)" "$out" "predeploy has not passed"
assert_not_contains "squash-merged: no 'not pushed' though the remote branch is gone" "$out" "not pushed"

# a commit beyond the merged PR's head is real work: checked as before
w=$(wt "$s" feat/sq2); commit "$w" t1; git -C "$w" push -q -u origin feat/sq2
head=$(git -C "$w" rev-parse HEAD); squash "$s" feat/sq2
commit "$w" t2; git -C "$w" push -q origin feat/sq2
out="$(FAKE_GH_PRS="$(pr 13 feat/sq2 "$head")" "$ES" "$w" 2>&1)"; rc=$?
assert_eq "work beyond the merged PR: refused by before_end" "$rc" "1"
assert_contains "work beyond the merged PR: the gate ran" "$out" "predeploy has not passed"
there "work beyond the merged PR: kept" "$w"

# a PR merged into another branch isn't merged into main
conf "$s"
w=$(wt "$s" feat/sq3); commit "$w" u1; git -C "$w" push -q -u origin feat/sq3
out="$(FAKE_GH_PRS="$(pr 14 feat/sq3 "$(git -C "$w" rev-parse HEAD)" develop)" "$ES" "$w" 2>&1)"
gone "PR into develop: removed (pushed)" "$w"; branch_kept "PR into develop: branch kept" "$s" feat/sq3
assert_contains "PR into develop: not merged" "$out" "not merged into main"

# gh failing or hanging reads as not merged, as before
w=$(wt "$s" feat/sq4); commit "$w" v1; git -C "$w" push -q -u origin feat/sq4; squash "$s" feat/sq4
FAKE_GH_PR_RC=1 FAKE_GH_PRS="$(pr 15 feat/sq4 "$(git -C "$w" rev-parse HEAD)")" "$ES" "$w" >/dev/null 2>&1
branch_kept "gh fails: branch kept" "$s" feat/sq4
w=$(wt "$s" feat/sq5); commit "$w" v2; git -C "$w" push -q -u origin feat/sq5; squash "$s" feat/sq5
start=$(date +%s)
WB_GH_TIMEOUT=1 FAKE_GH_SLEEP=20 FAKE_GH_PRS="$(pr 16 feat/sq5 "$(git -C "$w" rev-parse HEAD)")" "$ES" "$w" >/dev/null 2>&1
took=$(( $(date +%s) - start ))
branch_kept "gh hangs: branch kept" "$s" feat/sq5
if [ "$took" -lt 10 ]; then ok "gh hangs: cut off by the timeout"; else bad "gh hangs: took ${took}s"; fi

# the space's GitHub account asks, without switching gh's active account
conf "$s" "gh_account = \"acme-bot\""
w=$(wt "$s" feat/sq6); commit "$w" v3; git -C "$w" push -q -u origin feat/sq6; squash "$s" feat/sq6
FAKE_GH_LOG="$T/gh20.log" FAKE_GH_PRS="$(pr 17 feat/sq6 "$(git -C "$w" rev-parse HEAD)")" "$ES" "$w" >/dev/null 2>&1
branch_gone "gh account: squash-merged, deleted" "$s" feat/sq6
assert_contains "gh account: asked as the space's account" "$(cat "$T/gh20.log")" "token=tok-acme-bot"
assert_not_contains "gh account: active account left alone" "$(cat "$T/gh20.log")" "auth switch"

# 17 --if-merged (wb-kvx.22): what the launcher runs when Claude exits. Only merged work whose bead
# is closed goes; everything else is kept, with one line saying why
i="$T/r17"; setup_repo "$i"; conf "$i"; mkstore "$i"
# beadfor WT STATUS: the store names WT's bead, with STATUS
beadfor() { printf '[{"id":"acme-9","title":"Nine","status":"%s","notes":"Branch: x (worktree at %s)"}]\n' "$2" "$1" > "$i/.beads/fake.json"; }
w=$(wt "$i" feat/m1); commit "$w" a; git -C "$w" push -q -u origin feat/m1
git -C "$i" merge -q --no-ff -m "Merge pull request #1" feat/m1; git -C "$i" push -q origin main
beadfor "$w" closed
out="$("$ES" --if-merged "$w" 2>&1)"; rc=$?
assert_eq "if-merged: merged and closed exits 0" "$rc" "0"
gone "if-merged: merged and closed, removed" "$w"; branch_gone "if-merged: ... branch deleted" "$i" feat/m1
assert_not_contains "if-merged: no progress lines" "$out" "→"
assert_eq "if-merged: one line on success" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"

w=$(wt "$i" feat/m2); commit "$w" b; git -C "$w" push -q -u origin feat/m2; beadfor "$w" closed
out="$("$ES" --if-merged "$w" 2>&1)"; rc=$?
assert_eq "if-merged: pushed, unmerged refused" "$rc" "1"
there "if-merged: pushed, unmerged kept" "$w"; branch_kept "if-merged: ... branch kept" "$i" feat/m2
assert_contains "if-merged: says it's not merged" "$out" "not merged into main"
assert_eq "if-merged: one line when kept" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"

w=$(wt "$i" feat/m3); beadfor "$w" in_progress
out="$("$ES" --if-merged "$w" 2>&1)"; rc=$?
assert_eq "if-merged: a fresh worktree (no commits) refused" "$rc" "1"
there "if-merged: a fresh worktree is kept" "$w"
assert_contains "if-merged: says its bead is open" "$out" "acme-9 is in_progress"
assert_eq "if-merged: ... in one line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"

w=$(wt "$i" feat/m4); commit "$w" c; git -C "$w" push -q -u origin feat/m4
git -C "$i" merge -q --no-ff -m "Merge pull request #4" feat/m4; git -C "$i" push -q origin main
beadfor "$w" in_progress
"$ES" --if-merged "$w" >/dev/null 2>&1; assert_eq "if-merged: merged but bead open refused" "$?" "1"
there "if-merged: merged but bead open kept" "$w"
echo '[]' > "$i/.beads/fake.json"
out="$("$ES" --if-merged "$w" 2>&1)"; rc=$?
assert_eq "if-merged: no bead names it, refused" "$rc" "1"; there "if-merged: no bead, kept" "$w"
assert_contains "if-merged: says no bead names it" "$out" "no bead names"

beadfor "$w" closed; echo dirt > "$w/dirt.txt"
out="$("$ES" --if-merged "$w" 2>&1)"; rc=$?
assert_eq "if-merged: uncommitted refused" "$rc" "1"; there "if-merged: uncommitted kept" "$w"
assert_contains "if-merged: says uncommitted" "$out" "uncommitted changes"
assert_eq "if-merged: ... in one line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"
rm "$w/dirt.txt"

w=$(wt "$i" feat/m6); commit "$w" f; git -C "$w" push -q -u origin feat/m6; beadfor "$w" in_progress
out="$(FAKE_GH_LOG="$T/gh-m6.log" "$ES" --if-merged "$w" 2>&1)"
assert_contains "if-merged: mid-work (bead open) refused" "$out" "acme-9 is in_progress"
assert_eq "if-merged: ... without asking gh (most exits are mid-work)" "$(cat "$T/gh-m6.log" 2>/dev/null)" ""

w=$(wt "$i" feat/m5); commit "$w" d; beadfor "$w" closed
"$ES" --if-merged "$w" >/dev/null 2>&1; assert_eq "if-merged: never pushed refused" "$?" "1"
there "if-merged: never pushed kept" "$w"
rm -rf "$i/.beads"

# 16 refusals
conf "$h"
out="$("$ES" "$h" 2>&1)"; rc=$?
assert_eq "main checkout: refused" "$rc" "1"; assert_contains "main checkout: says so" "$out" "main checkout"
out="$("$ES" "$T/markers" 2>&1)"; rc=$?
assert_contains "not a repo: refused" "$out" "not in a git repo"
finish
