#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # macOS /var is /private/var; git reports the real path
R="$REPO/bin/wb-restore"
unset CLAUDE_CONFIG_DIR WB_SPACE_ROOT WB_BEAD WB_WORKTREE WORKBENCH_DRY_RUN

export HOME="$T/home" WB_STATE_DIR="$T/state" WORKBENCH_CONFIG="$T/spaces.toml" WB_RESTORE_DIR="$T/restore"
export FAKE_PS_OUT="$T/ps.out" FAKE_PS_ARGS="$T/ps.args" FAKE_OSA_LOG="$T/osa.log"
CFG="$HOME/.claude"; ALT="$HOME/.claude-alt"
mkdir -p "$CFG/sessions" "$ALT/sessions" "$WB_STATE_DIR/sessions" "$T/wts" "$T/plain"
NOW=$(date +%s)

setup_repo "$T/acme" >/dev/null 2>&1
git -C "$T/acme" worktree add -q -b feat/x "$T/wts/acme-x1y" 2>/dev/null
cat > "$T/spaces.toml" <<EOF
[[space]]
name          = "Acme"
root          = "$T/acme"
worktrees     = true
space_key     = "acme"
claude_config = "$ALT"
EOF

: > "$T/ps.out"; : > "$T/ps.args"
# live PID TTY ARGV: a claude on its own tab, as login > -zsh > claude
live() { echo "$(( $1 - 2 )) 1 $2 login" >> "$T/ps.out"; echo "$(( $1 - 1 )) $(( $1 - 2 )) $2 -zsh" >> "$T/ps.out"
         echo "$1 $(( $1 - 1 )) $2 claude" >> "$T/ps.out"; echo "$1 $3" >> "$T/ps.args"; }
# pidfile DIR PID SID CWD [KIND]
pidfile() {
  python3 - "$@" <<'PY'
import json, sys
d, pid, sid, cwd = sys.argv[1:5]
kind = sys.argv[5] if len(sys.argv) > 5 else "interactive"
json.dump({"pid": int(pid), "sessionId": sid, "cwd": cwd, "kind": kind, "name": f"name of {sid}",
           "startedAt": 1}, open(f"{d}/sessions/{pid}.json", "w"))
PY
}
record() { printf '{"bead":"%s","title":"t","root":"%s","since":"x","done":false,"named":false}' "$2" "$3" \
  > "$WB_STATE_DIR/sessions/$1.json"; }
snaps() { ls "$WB_RESTORE_DIR/snapshots" 2>/dev/null | wc -l | tr -d ' '; }
field() { python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); e=[x for x in s["sessions"] if x["session"]==sys.argv[2]]; print(e[0].get(sys.argv[3]) if e else "ABSENT")' "$@"; }

# ---- save
# ttys001: a bound worktree session on the space's account, skipping permissions
live 103 ttys001 "claude --settings /x.json --dangerously-skip-permissions SECRET OPENING PROMPT"
pidfile "$ALT" 103 sid-a "$T/wts/acme-x1y"
record sid-a ac-1 "$T/acme"
# ttys002: an unbound session on the default account, asking for permissions
live 203 ttys002 "claude --continue"
pidfile "$CFG" 203 sid-b "$T/plain"
# ttys003: a claude -p run is not a session to bring back
live 303 ttys003 "claude -p hello"
pidfile "$CFG" 303 sid-p "$T/plain" sdk-cli
# ttys005: its bead is done, so a resume must not hand the finished goal back
live 503 ttys005 "claude"
pidfile "$CFG" 503 sid-done "$T/plain"
printf '{"bead":"ac-9","title":"t","root":"%s","since":"x","done":true,"named":false}' "$T/acme" \
  > "$WB_STATE_DIR/sessions/sid-done.json"

out=$("$R" save 2>&1); rc=$?
assert_eq "save exits 0" "$rc" "0"
assert_contains "save says how many" "$out" "3 sessions"
assert_eq "one snapshot written" "$(snaps)" "1"
S="$WB_RESTORE_DIR/snapshots/$(ls "$WB_RESTORE_DIR/snapshots")"
assert_eq "account is the pid file's folder" "$(field "$S" sid-a config)" "$ALT"
assert_eq "default account recorded too" "$(field "$S" sid-b config)" "$CFG"
assert_eq "folder kept exactly" "$(field "$S" sid-a cwd)" "$T/wts/acme-x1y"
assert_eq "skip-permissions read from argv" "$(field "$S" sid-a skip_permissions)" "True"
assert_eq "no skip-permissions when absent" "$(field "$S" sid-b skip_permissions)" "False"
assert_eq "bead from the session record" "$(field "$S" sid-a bead)" "ac-1"
assert_eq "space root from the session record" "$(field "$S" sid-a space_root)" "$T/acme"
assert_eq "worktree is the cwd's linked worktree" "$(field "$S" sid-a worktree)" "$T/wts/acme-x1y"
assert_eq "no worktree outside one" "$(field "$S" sid-b worktree)" "None"
assert_eq "a done bead isn't resumed into" "$(field "$S" sid-done bead)" "None"
assert_eq "but its space still is" "$(field "$S" sid-done space_root)" "$T/acme"
assert_eq "claude -p is left out" "$(field "$S" sid-p session)" "ABSENT"
assert_not_contains "argv itself is never kept" "$(cat "$S")" "SECRET OPENING PROMPT"

"$R" save >/dev/null 2>&1
assert_eq "same sessions again: no new snapshot" "$(snaps)" "1"

old="$WB_RESTORE_DIR/snapshots/20200101T000000Z.json"
echo '{"taken": 1577836800, "sessions": []}' > "$old"
live 403 ttys004 "claude"; pidfile "$CFG" 403 sid-c "$T/plain"
"$R" save >/dev/null 2>&1
assert_eq "a changed set is saved, and one older than 7 days pruned" "$(snaps)" "2"
[ -e "$old" ] && bad "old snapshot pruned" || ok "old snapshot pruned"

# ---- restore: picks the newest snapshot from before this boot
rm -rf "$WB_RESTORE_DIR"; mkdir -p "$WB_RESTORE_DIR/snapshots"
snap() {  # snap STAMP EPOCH JSON-SESSIONS
  printf '{"taken": %s, "sessions": [%s]}' "$2" "$3" > "$WB_RESTORE_DIR/snapshots/$1.json"; }
ent() { printf '{"session":"%s","cwd":"%s","config":"%s","skip_permissions":%s,"name":"%s","space_root":%s,"bead":%s,"worktree":%s}' "$@"; }
BEFORE=$((NOW - 7200)); BOOT=$((NOW - 3600))
snap 20261115T080000Z $((BEFORE - 600)) "$(ent sid-old "$T/plain" "$CFG" false "Oldest snap" null null null)"
snap 20261115T090000Z $BEFORE "$(ent sid-a "$T/wts/acme-x1y" "$ALT" true "Resend the email" "\"$T/acme\"" '"ac-1"' "\"$T/wts/acme-x1y\""),$(ent sid-b "$T/plain" "$CFG" false "Plain one" null null null),$(ent sid-gone "$T/wts/removed" "$CFG" false "Gone one" null null null),$(ent sid-c "$T/plain" "$CFG" false "Still open" null null null)"
snap 20261115T110000Z $((NOW - 60)) "$(ent sid-c "$T/plain" "$CFG" false "Still open" null null null)"
# after the boot, only sid-c (pid 403) is running
: > "$T/ps.out"; : > "$T/ps.args"; rm -f "$CFG"/sessions/* "$ALT"/sessions/*
live 403 ttys004 "claude"; pidfile "$CFG" 403 sid-c "$T/plain"
export WB_BOOTTIME=$BOOT

out=$(WORKBENCH_DRY_RUN=1 "$R" </dev/null 2>&1); rc=$?
assert_eq "dry run exits 0" "$rc" "0"
assert_contains "uses the snapshot from before the boot" "$out" "Resend the email"
assert_not_contains "not the older one" "$out" "Oldest snap"
assert_contains "a live session is not resumed twice" "$out" "Still open"
assert_contains "it says why" "$out" "still open"
assert_contains "a gone folder is skipped, with why" "$out" "Gone one"
assert_contains "and the reason" "$out" "folder is gone"
assert_contains "dry run says what it would open" "$out" "each of the 2 ready"
[ -d "$WB_RESTORE_DIR/queue" ] && [ -n "$(ls "$WB_RESTORE_DIR/queue")" ] && bad "dry run queues nothing" || ok "dry run queues nothing"
[ -s "$T/osa.log" ] && bad "dry run opens no window" || ok "dry run opens no window"

out=$(echo n | "$R" 2>&1)
assert_contains "no: nothing is queued" "$out" "nothing resumed"
[ -s "$T/osa.log" ] && bad "no: no window opened" || ok "no: no window opened"

out=$(echo y | "$R" 2>&1); rc=$?
assert_eq "yes exits 0" "$rc" "0"
assert_eq "two sessions queued" "$(ls "$WB_RESTORE_DIR/queue" | wc -l | tr -d ' ')" "2"
assert_eq "one osascript call asks for 2 new tabs" "$(cat "$T/osa.log")" "2"

out=$(echo y | "$R" 2>&1); rc=$?
assert_contains "a second run before the tabs start: already queued, so skipped" "$out" "already queued"
assert_eq "and nothing is queued twice" "$(ls "$WB_RESTORE_DIR/queue" | wc -l | tr -d ' ')" "2"
rm -rf "$WB_RESTORE_DIR/queue"

out=$(echo y | FAKE_PS_RC=1 "$R" 2>&1); rc=$?
assert_eq "ps failing: refuse, since live sessions can't be told apart" "$rc" "1"
[ -d "$WB_RESTORE_DIR/queue" ] && [ -n "$(ls "$WB_RESTORE_DIR/queue")" ] && bad "ps failing queues nothing" || ok "ps failing queues nothing"

out=$(echo y | FAKE_OSA_RC=1 FAKE_OSA_ERR="Not authorized to send Apple events to Terminal. (-1743)" \
  FAKE_OSA_LOG=/dev/null "$R" 2>&1); rc=$?
assert_eq "Terminal refusing is a failure" "$rc" "1"
assert_contains "and says where to allow it" "$out" "Automation"
rm -rf "$WB_RESTORE_DIR/queue"

# ---- claim: one queued entry per tab, oldest first, never twice, never stale
echo y | "$R" >/dev/null 2>&1
first=$("$R" claim); rc=$?
assert_eq "claim exits 0" "$rc" "0"
assert_eq "claim prints the folder first" "$(cut -f1 <<<"$first")" "$T/wts/acme-x1y"
ticket=$(cut -f2 <<<"$first")
assert_contains "the ticket moved to claimed" "$ticket" "/claimed/"
[ -f "$ticket" ] && ok "the claimed ticket exists" || bad "the claimed ticket exists"
second=$("$R" claim)
assert_eq "the next tab gets the next one" "$(cut -f1 <<<"$second")" "$T/plain"
"$R" claim >/dev/null 2>&1; rc=$?
assert_eq "an empty queue: exit 1, so the launcher starts" "$rc" "1"

rm -rf "$WB_RESTORE_DIR/queue" "$WB_RESTORE_DIR/claimed"
echo y | "$R" >/dev/null 2>&1
touch -t 202001010000 "$WB_RESTORE_DIR"/queue/*
"$R" claim >/dev/null 2>&1; rc=$?
assert_eq "an entry older than 5 minutes isn't claimed" "$rc" "1"
assert_eq "and is deleted" "$(ls "$WB_RESTORE_DIR/queue" | wc -l | tr -d ' ')" "0"

# ---- exec: the command each tab runs
rm -rf "$WB_RESTORE_DIR/queue" "$WB_RESTORE_DIR/claimed"
echo y | "$R" >/dev/null 2>&1
a=$("$R" claim | cut -f2); b=$("$R" claim | cut -f2)
out=$(WORKBENCH_DRY_RUN=1 "$R" exec "$a")
assert_contains "the space's account" "$out" "CLAUDE_CONFIG_DIR=$ALT"
assert_contains "resumes by id" "$out" "--resume sid-a"
assert_contains "skip-permissions kept" "$out" "--dangerously-skip-permissions"
assert_contains "the bead for the hooks" "$out" "WB_BEAD=ac-1"
assert_contains "the space root" "$out" "WB_SPACE_ROOT=$T/acme"
assert_contains "the worktree" "$out" "WB_WORKTREE=$T/wts/acme-x1y"
assert_contains "the workbench hooks" "$out" "--settings $WB_STATE_DIR/claude-settings.json"
out=$(WORKBENCH_DRY_RUN=1 "$R" exec "$b")
assert_contains "the default account unsets CLAUDE_CONFIG_DIR" "$out" "-u CLAUDE_CONFIG_DIR"
assert_not_contains "no skip-permissions when it wasn't there" "$out" "dangerously"
assert_not_contains "no bead when unbound" "$out" "WB_BEAD"
printf '{"session":"sid-c","cwd":"%s","config":"%s","skip_permissions":false}' "$T/plain" "$CFG" > "$T/live.json"
out=$("$R" exec "$T/live.json" 2>&1); rc=$?
assert_eq "exec of a session that is live refuses" "$rc" "1"
assert_contains "and says so" "$out" "already open"
"$R" exec "$T/nope.json" >/dev/null 2>&1; rc=$?
assert_eq "exec of a missing ticket fails" "$rc" "1"

finish
