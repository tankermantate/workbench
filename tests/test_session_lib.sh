#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
WB_HOME="$REPO"; . "$REPO/lib/session.sh"

assert_eq "slugify" "$(ws_slugify 'Fix the Login Page!')" "fix-the-login-page"
assert_eq "slugify joins words" "$(ws_slugify big idea)" "big-idea"
assert_eq "slugify cuts at 40, no trailing dash" \
  "$(ws_slugify 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbb')" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
ws_slugify '!!!' >/dev/null 2>&1; assert_eq "slugify of nothing fails" "$?" "1"

ws_split $'Acme\t-\t/r x\ttrue\t1\tcmd\tacme\t-\t-\t0\tbot\thook one\t-'
assert_eq "split: a field with spaces" "$S_ON_CREATE" "hook one"
assert_eq "split: a path with a space" "$S_ROOT" "/r x"
assert_eq "split: '-' becomes empty" "$S_GROUP|$S_BEFORE_END" "|"

setup_repo "$T/r1"
assert_eq "default branch: main" "$(ws_default_branch "$T/r1")" "main"
setup_repo "$T/r2" master
assert_eq "default branch: master when there is no main" "$(ws_default_branch "$T/r2")" "master"
git -C "$T/r1" checkout -q -b trunk; git -C "$T/r1" push -q origin trunk
git -C "$T/r1" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
assert_eq "default branch: origin/HEAD wins" "$(ws_default_branch "$T/r1")" "trunk"
git init -q -b dev "$T/r3"
assert_eq "default branch: else the current branch" "$(ws_default_branch "$T/r3")" "dev"

mkstore "$T/s"; mkdir -p "$T/s/a/b" "$T/s/a/.beads"   # s/a/.beads: a leftover, no database
assert_eq "store: nearest .beads up to the top" "$(ws_store_dir "$T/s/a/b" "$T/s")" "$T/s/.beads"
assert_eq "store: not above the top" "$(ws_store_dir "$T/s/a/b" "$T/s/a")" ""
assert_eq "relpath" "$(ws_relpath "$T/s/.beads" "$T/w/x")" "../../s/.beads"

mkdir -p "$T/hk"
out="$(WB_SPACE=acme ws_run_hook 'echo "$WB_SPACE in $(basename "$PWD")"; exit 3' "$T/hk")"; rc=$?
assert_eq "hook: runs in its folder with the variables" "$out" "acme in hk"
assert_eq "hook: its exit code comes back" "$rc" "3"

export FAKE_GH_LOG="$T/gh.log"
FAKE_GH_ACTIVE=acme-bot ws_gh_switch acme-bot
assert_eq "gh: no switch when already active" "$(cat "$T/gh.log" 2>/dev/null | grep -c switch)" "0"
out="$(FAKE_GH_ACTIVE=other ws_gh_switch acme-bot 2>&1)"
assert_contains "gh: switches when another account is active" "$(cat "$T/gh.log")" "auth switch --user acme-bot"
out="$(FAKE_GH_ACTIVE=other FAKE_GH_SWITCH_RC=1 ws_gh_switch acme-bot 2>&1)"; rc=$?
assert_contains "gh: a failed switch warns" "$out" "warning"
assert_eq "gh: and doesn't fail" "$rc" "0"
out="$(WB_GH=/nonexistent/gh ws_gh_switch acme-bot 2>&1)"; rc=$?
assert_contains "gh: missing gh warns" "$out" "gh not found"

unset FAKE_BD_DIR
mkstore "$T/b1" "$T/b2"
git init -q "$T/b1"; git init -q "$T/b2"   # a space's store is found within its repo
echo '[{"id":"x-1","title":"One","issue_type":"bug"}]' > "$T/b1/.beads/fake.json"
printf '[{"id":"y-1","title":"Two\\tthree\\nfour","issue_type":"task"}]\n' > "$T/b2/.beads/fake.json"
ROWS=$(printf 'B1\t-\t%s\ttrue\t1\tc\tb1\t-\t-\t0\t-\t-\t-\nB2\t-\t%s\ttrue\t1\tc\tb2\t-\t-\t0\t-\t-\t-\nP\t-\t/x\ttrue\t0\t-\tp\t-\t-\t0\t-\t-\t-' "$T/b1" "$T/b2")
ws_find_key "$ROWS" b2; rc=$?
assert_eq "find key: the worktree space" "$rc $S_ROOT" "0 $T/b2"
ws_find_key "$ROWS" p; assert_eq "find key: not a non-worktree space" "$?" "1"
assert_eq "keys: worktree spaces only" "$(ws_keys "$ROWS")" "b1, b2"
ws_find_bead "$ROWS" y-1; rc=$?
assert_eq "find bead: its space, type and a one-line title" "$rc $S_KEY $BEAD_TYPE $BEAD_TITLE" "0 b2 task Two three four"
FAKE_BD_WARN=1 ws_bead_info "$T/b1" x-1; rc=$?
assert_eq "bead info: a Warning line before the JSON is skipped" "$rc $BEAD_TITLE" "0 One"
ws_find_bead "$ROWS" zz-9; assert_eq "find bead: unknown id" "$?" "1"
start=$SECONDS
WB_BD_TIMEOUT=1 FAKE_BD_SLEEP=5 ws_bead_info "$T/b1" x-1; assert_eq "bead info: a slow bd counts as not found" "$?" "1"
took=$((SECONDS - start))
if [ "$took" -lt 3 ]; then ok "bead info: cut off at the timeout, children too (${took}s)"; else bad "bead info: waited ${took}s for bd's children"; fi
out="$(FAKE_BD_WARN=bracket ws_bead_info "$T/b1" x-1 2>&1)"; rc=$?
assert_eq "bead info: a '[warn]' line before the JSON is skipped" "$rc" "0"
assert_not_contains "bead info: no Python traceback" "$out" "Traceback"

ws_timeout 5 sh -c 'kill -9 $$'; rc=$?
assert_eq "timeout: a command killed by a signal is a failure" "$rc" "137"
# Ctrl-C reaches the timeout wrapper (the terminal's process group), not bd's
# own group; the wrapper must take bd's group down with it.
ws_timeout 10 sleep 31.5 & bgp=$!
sleep 1
pp=$(pgrep -P "$bgp" perl || echo "$bgp")   # bash may run perl as the job itself
start=$SECONDS
kill -INT "$pp" 2>/dev/null; wait "$bgp" 2>/dev/null
took=$((SECONDS - start))
if pgrep -f 'sleep 31.5' >/dev/null; then bad "timeout: Ctrl-C stops bd too"; pkill -f 'sleep 31.5'
elif [ "$took" -ge 3 ]; then bad "timeout: Ctrl-C was ignored; the timeout stopped it after ${took}s"
else ok "timeout: Ctrl-C stops bd too (${took}s)"; fi
finish
