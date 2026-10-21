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
(cd "$w/app" && "$ES" >/dev/null 2>&1); assert_eq "from inside: exits 0" "$?" "0"
gone "from inside: removed" "$w"
env_out="$(cat "$MARKERS/env" 2>/dev/null)"
assert_contains "hook: WB_SPACE" "$env_out" "WB_SPACE=acme"
assert_contains "hook: WB_WORKTREE" "$env_out" "WB_WORKTREE=$w"
assert_contains "hook: WB_PROJECT" "$env_out" "WB_PROJECT=$w/app"
assert_contains "hook: WB_SOURCE" "$env_out" "WB_SOURCE=$h/app"
assert_contains "hook: WB_SHA" "$env_out" "WB_SHA=$sha"

# 12 no origin
n="$T/noorigin"; git init -q -b main "$n"; git -C "$n" config user.email t@example.com; git -C "$n" config user.name t
commit "$n" base; conf "$n"
w=$(wt "$n" feat/local); commit "$w" l
"$ES" "$w" >/dev/null 2>&1; assert_eq "no origin: unmerged work ends" "$?" "0"
branch_kept "no origin: unmerged branch kept" "$n" feat/local
w=$(wt "$n" feat/merged); commit "$w" m; git -C "$n" merge -q --ff-only feat/merged
"$ES" "$w" >/dev/null 2>&1; branch_gone "no origin: merged branch deleted" "$n" feat/merged

# 13 no space claims the repo
conf "$T/markers"
w=$(wt "$h" fix/thirteen)
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "unclaimed: goes ahead" "$rc" "0"
assert_contains "unclaimed: says no before_end ran" "$out" "no before_end check ran"

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

# 16 refusals
conf "$h"
out="$("$ES" "$h" 2>&1)"; rc=$?
assert_eq "main checkout: refused" "$rc" "1"; assert_contains "main checkout: says so" "$out" "main checkout"
out="$("$ES" "$T/markers" 2>&1)"; rc=$?
assert_contains "not a repo: refused" "$out" "not in a git repo"
finish
