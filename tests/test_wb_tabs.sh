#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # macOS /var is /private/var; git reports the real path
TABS="$REPO/bin/wb-tabs"
unset CLAUDE_CONFIG_DIR WB_SPACE_ROOT WB_BEAD WB_WORKTREE

export HOME="$T/home" WB_STATE_DIR="$T/state" WORKBENCH_CONFIG="$T/spaces.toml"
export WB_PS="$REPO/tests/fake/fake-ps" FAKE_PS_OUT="$T/ps.out" FAKE_PS_ENV="$T/ps.env"
export FAKE_BD_LOG="$T/bd.log"
unset FAKE_BD_DIR
CFG="$HOME/.claude"; ALT="$HOME/.claude-alt"; TITLES="$HOME/.cache/claude-titles"
mkdir -p "$CFG/sessions" "$ALT/sessions" "$TITLES" "$WB_STATE_DIR/sessions" "$T/wts" "$T/plainfolder"
NOW=$(date +%s)

setup_repo "$T/acme" >/dev/null 2>&1
git -C "$T/acme" worktree add -q -b feat/x "$T/wts/acme-x1y" 2>/dev/null
mkstore "$T/acme"
# a second space in the same repo, rooted in a subfolder: same store, so one read between them
mkdir -p "$T/acme/apps/web"
setup_repo "$T/globex" >/dev/null 2>&1
mkstore "$T/globex"
cat > "$T/spaces.toml" <<EOF
[[space]]
name      = "Acme"
root      = "$T/acme"
worktrees = true
space_key = "acme"

[[space]]
name          = "Web"
root          = "$T/acme/apps/web"
claude_config = "$ALT"

[[space]]
name = "Globex"
root = "$T/globex"
EOF

cat > "$T/acme/.beads/fake.json" <<'EOF'
[
 {"id":"ac-epic","title":"EPIC: Checkout reliability","status":"open","description":"Keep checkout up."},
 {"id":"ac-1","title":"Resend the order email","status":"in_progress","parent":"ac-epic",
  "description":"WHY: customers lose the email when the provider times out. It has happened twice.\n\nWHAT: retry.",
  "notes":"started (worktree at /somewhere/acme-x1y)\nretry added, deploy pending\n(worktree at /somewhere/acme-x1y)"},
 {"id":"ac-2","title":"Trim the footer","status":"closed","close_reason":"footer trimmed; logo did not change",
  "description":"The footer is too tall."},
 {"id":"ac-3","title":"Reopened after a close","status":"open","description":"Split from ac-1. The retry must survive a restart."},
 {"id":"ac-web","title":"Web bead","status":"open","description":"Too short."}
]
EOF
cat > "$T/globex/.beads/fake.json" <<'EOF'
[{"id":"gl-1","title":"Globex bead","status":"blocked","description":""}]
EOF

# ps_row PID PPID TTY COMM
: > "$T/ps.out"; : > "$T/ps.env"
ps_row() { echo "$1 $2 $3 $4" >> "$T/ps.out"; }
# session DIR PID SID CWD STATUS AGE_SECONDS [STARTED_AGO_SECONDS]
session() {
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" "${7:-86400}" "$NOW" <<'PY'
import json, sys
d, pid, sid, cwd, st, age, started, now = sys.argv[1:]
now = int(now)
json.dump({"pid": int(pid), "sessionId": sid, "cwd": cwd, "status": st,
           "statusUpdatedAt": (now - int(age)) * 1000, "startedAt": (now - int(started)) * 1000},
          open(f"{d}/sessions/{pid}.json", "w"))
PY
}
# record SID BEAD TITLE ROOT [DONE]
record() {
  python3 - "$WB_STATE_DIR/sessions/$1.json" "$2" "$3" "$4" "${5:-}" <<'PY'
import json, sys
p, bead, title, root, done = sys.argv[1:]
json.dump({"bead": bead, "title": title, "root": root, "since": "2026-11-05T00:00:00Z",
           "done": bool(done), "named": False}, open(p, "w"))
PY
}
# the block of lines for one tab
block() { awk -v t="$1" '$1==t && !/^ /{p=1; print; next} !/^ /{p=0} p' <<<"$OUT"; }

# ttys001: bound, in a worktree, under an epic, idle 5h
ps_row 101 1 ttys001 login; ps_row 102 101 ttys001 -zsh; ps_row 103 102 ttys001 claude
session "$CFG" 103 sid-a "$T/wts/acme-x1y" idle 18000
record sid-a ac-1 "Resend the order email" "$T/acme"
printf '🟣 Acme · x1y Resend|window title' > "$TITLES/last-ttys001"
# ttys002: plain shell, with a title left by a session that ended
ps_row 201 1 ttys002 login; ps_row 202 201 ttys002 -zsh
printf 'STALE PLAIN TITLE|w' > "$TITLES/last-ttys002"
# ttys003: working now, and its claude has spawned another claude
ps_row 301 1 ttys003 login; ps_row 302 301 ttys003 -zsh; ps_row 303 302 ttys003 claude; ps_row 304 303 ttys003 claude
session "$CFG" 303 sid-b "$T/acme" busy 120
session "$CFG" 304 sid-sub "$T/acme" busy 1
record sid-b ac-3 "Reopened after a close" "$T/acme"
record sid-sub ac-2 "Trim the footer" "$T/acme"
# ttys004: the session closed its bead
ps_row 401 1 ttys004 login; ps_row 402 401 ttys004 -zsh; ps_row 403 402 ttys004 claude
session "$CFG" 403 sid-c "$T/acme" idle 7200
record sid-c ac-2 "Trim the footer" "$T/acme" done
# ttys005: started outside the launcher, no record
ps_row 501 1 ttys005 login; ps_row 502 501 ttys005 -zsh; ps_row 503 502 ttys005 claude
session "$CFG" 503 sid-d "$T/globex" idle 60
echo "503 claude --continue TERM=xterm SECRET_TOKEN=hunter2" >> "$T/ps.env"
# ttys006: launched by workbench, on no bead
ps_row 601 1 ttys006 login; ps_row 602 601 ttys006 -zsh; ps_row 603 602 ttys006 claude
session "$CFG" 603 sid-e "$T/globex" idle 60
echo "603 claude WB_SPACE_ROOT=$T/globex SECRET_TOKEN=hunter2" >> "$T/ps.env"
# ttys007: claude with no pid file at all
ps_row 701 1 ttys007 login; ps_row 702 701 ttys007 -zsh; ps_row 703 702 ttys007 claude
# ttys008: another config dir, another root on the same store as ttys001; a title older than its session
ps_row 801 1 ttys008 login; ps_row 802 801 ttys008 -zsh; ps_row 803 802 ttys008 claude
session "$ALT" 803 sid-f "$T/acme/apps/web" idle 30 3600
record sid-f ac-web "Web bead" "$T/acme/apps/web"
printf 'OLD SESSION TITLE|w' > "$TITLES/last-ttys008"; touch -t 202001010000 "$TITLES/last-ttys008"
# ttys009: bound to a bead its store doesn't have
ps_row 901 1 ttys009 login; ps_row 902 901 ttys009 -zsh; ps_row 903 902 ttys009 claude
session "$CFG" 903 sid-g "$T/acme" idle 60
record sid-g ac-gone "Deleted bead" "$T/acme"
# ttys010: bound in a second store, with an empty description
ps_row 1001 1 ttys010 login; ps_row 1002 1001 ttys010 -zsh; ps_row 1003 1002 ttys010 claude
session "$CFG" 1003 sid-h "$T/globex" idle 60
record sid-h gl-1 "Globex bead" "$T/globex"
# ttys011: bound, its worktree removed since (end-session), and the session left open
ps_row 1101 1 ttys011 login; ps_row 1102 1101 ttys011 -zsh; ps_row 1103 1102 ttys011 claude
session "$CFG" 1103 sid-i "$T/wts/removed-long-ago" idle 60
record sid-i ac-3 "Reopened after a close" "$T/acme"
# ttys012: the same gone folder with no record: nothing says which space, so no guess
ps_row 1201 1 ttys012 login; ps_row 1202 1201 ttys012 -zsh; ps_row 1203 1202 ttys012 claude
session "$CFG" 1203 sid-j "$T/wts/removed-long-ago" idle 60
# no process: daemons, and a tty whose tab has closed
ps_row 1 0 '??' launchd; ps_row 2000 1 '??' claude
printf 'DEAD TAB TITLE|w' > "$TITLES/last-ttys099"

OUT=$("$TABS" 2>&1); RC=$?
assert_eq "exits 0" "$RC" 0

A=$(block ttys001)
assert_contains "tab: tty and title"           "$A" "ttys001  🟣 Acme · x1y Resend"
assert_not_contains "tab: only the tab's half of the title" "$A" "window title"
assert_contains "space and worktree"           "$A" "Acme ⑂ acme-x1y"
assert_contains "bead id and title"            "$A" "ac-1 Resend the order email"
assert_contains "goal: first sentence, no WHY" "$A" "customers lose the email when the provider times out."
assert_not_contains "goal: one sentence"       "$A" "happened twice"
assert_contains "goal: the parent epic"        "$A" "Checkout reliability ›"
assert_not_contains "goal: the epic's own label goes" "$A" "EPIC:"
assert_contains "status: bead state"           "$A" "in_progress"
assert_contains "status: idle time"            "$A" "idle 5h"
assert_contains "status: latest real note"     "$A" "retry added, deploy pending"
assert_not_contains "status: a claim line isn't news" "$A" "worktree at"

P=$(block ttys002)
assert_contains "plain shell labelled"         "$P" "plain shell"
assert_not_contains "plain shell: no stale title" "$P" "STALE PLAIN TITLE"

W=$(block ttys003)
assert_contains "a busy session reads as working" "$W" "working 2m"
assert_contains "the outermost claude is the session" "$W" "ac-3"
assert_not_contains "a spawned claude is not the session" "$OUT" "sid-sub"
assert_eq "a tty is one tab, however many claudes" "$(grep -c '^ttys003' <<<"$OUT")" 1

assert_contains "goal: past a sentence saying where it came from" "$W" "The retry must survive a restart."
assert_not_contains "goal: not that sentence" "$W" "Split from"

C=$(block ttys004)
assert_contains "closed by this session"       "$C" "closed by this session"
assert_contains "closed: says what shipped"    "$C" "footer trimmed"
assert_contains "closed: still says idle"      "$C" "idle 2h"

U=$(block ttys005)
assert_contains "no binding, not launched: unbound" "$U" "unbound"
assert_contains "unbound: the folder's space"  "$U" "Globex"
assert_not_contains "unbound: not called no bead" "$U" "no bead"
assert_not_contains "the environment is never echoed" "$OUT" "hunter2"

N=$(block ttys006)
assert_contains "launched on no bead: no bead" "$N" "no bead"
assert_not_contains "no bead: not called unbound" "$N" "unbound"

M=$(block ttys007)
assert_contains "no pid file: unbound, not dropped" "$M" "unbound"

F=$(block ttys008)
assert_contains "a space's claude_config is searched" "$F" "ac-web Web bead"
assert_contains "the deepest space wins"       "$F" "Web"
assert_not_contains "a title older than the session isn't shown" "$F" "OLD SESSION TITLE"

G=$(block ttys009)
assert_contains "missing bead: the record's title" "$G" "ac-gone Deleted bead"
assert_contains "missing bead: says so"        "$G" "bead not found"

assert_contains "goal: a short description is still the goal" "$F" "Too short."

R=$(block ttys011)
assert_contains "worktree gone: the record names the space" "$R" "Acme · ac-3"
assert_not_contains "worktree gone: not a stray folder" "$R" "removed-long-ago"
Q=$(block ttys012)
assert_contains "worktree gone, no record: the folder, no guess" "$Q" "(removed-long-ago) · unbound"

H=$(block ttys010)
assert_contains "second store read"            "$H" "blocked"
assert_contains "no description: says so"      "$H" "no description"

assert_not_contains "a closed tab isn't listed"     "$OUT" "ttys099"
assert_not_contains "a closed tab's title isn't listed" "$OUT" "DEAD TAB TITLE"
assert_not_contains "a process with no tty isn't a tab" "$OUT" "??"

# bd: one list per store, whatever the number of tabs and roots, and nothing that writes
assert_eq "one bd call per store" "$(wc -l < "$T/bd.log" | tr -d ' ')" 2
assert_not_contains "never bd show: it rewrites last-touched" "$(cat "$T/bd.log")" "show"
assert_eq "every bd call is a list" "$(grep -vc '^list ' "$T/bd.log")" 0

# on a terminal, lines stop at its width; a pipe gets them whole
assert_contains "piped: lines stay whole" "$(block ttys001)" "ac-1 Resend the order email"
LONGEST=$(COLUMNS=40 script -q /dev/null "$TABS" 2>/dev/null </dev/null | tr -d '\r' | python3 -c 'import sys; print(max(len(l.rstrip("\n")) for l in sys.stdin))')
assert_eq "on a terminal: cut to its width" "$((LONGEST <= 38))" 1

# the session record names the bead, even when the launch environment says otherwise
echo "103 claude WB_BEAD=ac-3 WB_SPACE_ROOT=$T/acme" >> "$T/ps.env"
OUT=$("$TABS" 2>&1)
assert_contains "the record beats the launch env" "$(block ttys001)" "ac-1 Resend"

# a pid file in two config dirs: the newest start wins (a recycled pid leaves the old one)
session "$ALT" 103 sid-old "$T/globex" idle 60 999999
OUT=$("$TABS" 2>&1)
assert_contains "recycled pid: the newest pid file wins" "$(block ttys001)" "ac-1 Resend"
rm -f "$ALT/sessions/103.json"

# a pid file in an unexpected shape reads as unbound, and doesn't break the view
echo 'not json' > "$CFG/sessions/403.json"
OUT=$("$TABS" 2>&1); RC=$?
assert_eq "odd pid file: still exits 0" "$RC" 0
assert_contains "odd pid file: unbound" "$(block ttys004)" "unbound"
assert_not_contains "odd pid file: no traceback" "$OUT" "Traceback"
session "$CFG" 403 sid-c "$T/acme" idle 7200

# bd failing: the other store's rows are unaffected in the failing store's view
FAKE_DIR="$T/fakebd"; mkdir -p "$FAKE_DIR"; echo 1 > "$FAKE_DIR/rc"
OUT=$(FAKE_BD_DIR="$FAKE_DIR" "$TABS" 2>&1); RC=$?
assert_eq "bd failing: still exits 0" "$RC" 0
A=$(block ttys001)
assert_contains "bd failing: the record's title stays" "$A" "ac-1 Resend the order email"
assert_contains "bd failing: says so"          "$A" "bead status unknown (bd didn't answer)"
assert_contains "bd failing: session state stays" "$A" "idle 5h"
assert_contains "bd failing: a done record still says closed" "$(block ttys004)" "closed by this session"

# bd slow: the deadline holds the view to it
FAKE_DIR="$T/slowbd"; mkdir -p "$FAKE_DIR"; echo 5 > "$FAKE_DIR/sleep"; echo '[]' > "$FAKE_DIR/stdout"
S=$(python3 -c 'import time; print(time.time())')
OUT=$(FAKE_BD_DIR="$FAKE_DIR" WB_TABS_BD_TIMEOUT=0.2 "$TABS" 2>&1)
E=$(python3 -c "import time; print(int(time.time() - $S < 3))")
assert_eq "bd slow: the deadline holds" "$E" 1
assert_contains "bd slow: says so" "$(block ttys001)" "bead status unknown (bd didn't answer)"

# ps failing: nothing to say what's live, so say that
OUT=$(FAKE_PS_RC=1 "$TABS" 2>&1); RC=$?
assert_eq "ps failing: exits 1" "$RC" 1
assert_contains "ps failing: says so" "$OUT" "can't read the process table"

# nothing open
: > "$T/ps.out"
OUT=$("$TABS" 2>&1); RC=$?
assert_eq "no tabs: exits 0" "$RC" 0
assert_contains "no tabs: says so" "$OUT" "no open terminal tabs"

finish
