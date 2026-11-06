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
 {"id":"ac-web","title":"Web bead","status":"open","description":"Too short."},
 {"id":"ac-4","title":"Approve the refund","status":"in_progress",
  "description":"Refunds over the limit need a person to approve them.","notes":"one refund left to approve"}
]
EOF
cat > "$T/globex/.beads/fake.json" <<'EOF'
[{"id":"gl-1","title":"Globex bead","status":"blocked","description":""}]
EOF

# ps_row PID PPID TTY COMM
: > "$T/ps.out"; : > "$T/ps.env"
ps_row() { echo "$1 $2 $3 $4" >> "$T/ps.out"; }
# session DIR PID SID CWD STATUS AGE_SECONDS [STARTED_AGO_SECONDS] [WAITING_FOR]
session() {
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" "${7:-86400}" "$NOW" "${8:-}" <<'PY'
import json, sys
d, pid, sid, cwd, st, age, started, now, waiting = sys.argv[1:]
now = int(now)
j = {"pid": int(pid), "sessionId": sid, "cwd": cwd, "status": st,
     "statusUpdatedAt": (now - int(age)) * 1000, "startedAt": (now - int(started)) * 1000}
if waiting:
    j["waitingFor"] = waiting
json.dump(j, open(f"{d}/sessions/{pid}.json", "w"))
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
# a tab's row, found by its text, with the goal and next lines under it
tab() { awk -v t="$1" 'p && /^      /{print; next} p{exit} index($0, t){p=1; print}' <<<"$OUT"; }
# everything under a heading, up to the next one
section() { awk -v h="$1" 'index($0, h)==1{p=1; next} p && /^[A-Z]/{exit} p' <<<"$OUT"; }
# the line number of a row: order is what this view is for
line_of() { grep -nF -- "$1" <<<"$OUT" | head -1 | cut -d: -f1; }

# ttys001: bound, in a worktree, under an epic, idle 5h
ps_row 101 1 ttys001 login; ps_row 102 101 ttys001 -zsh; ps_row 103 102 ttys001 claude
session "$CFG" 103 sid-a "$T/wts/acme-x1y" idle 18000
record sid-a ac-1 "Resend the order email" "$T/acme"
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
# ttys008: another config dir, another root on the same store as ttys001
ps_row 801 1 ttys008 login; ps_row 802 801 ttys008 -zsh; ps_row 803 802 ttys008 claude
session "$ALT" 803 sid-f "$T/acme/apps/web" idle 30 3600
record sid-f ac-web "Web bead" "$T/acme/apps/web"
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
# ttys013: stuck on a prompt, on a bead
ps_row 1301 1 ttys013 login; ps_row 1302 1301 ttys013 -zsh; ps_row 1303 1302 ttys013 claude
session "$CFG" 1303 sid-k "$T/acme" waiting 120 86400 "input needed"
record sid-k ac-4 "Approve the refund" "$T/acme"
# ttys014: stuck on a prompt with no bead at all
ps_row 1401 1 ttys014 login; ps_row 1402 1401 ttys014 -zsh; ps_row 1403 1402 ttys014 claude
session "$CFG" 1403 sid-l "$T/globex" waiting 60 86400 "dialog open"
# ttys015: stuck on a prompt, its bead already closed
ps_row 1501 1 ttys015 login; ps_row 1502 1501 ttys015 -zsh; ps_row 1503 1502 ttys015 claude
session "$CFG" 1503 sid-m "$T/acme" waiting 60 86400 "sandbox request"
record sid-m ac-2 "Trim the footer" "$T/acme"
# ttys016: stuck on a prompt in a folder that's no space
ps_row 1601 1 ttys016 login; ps_row 1602 1601 ttys016 -zsh; ps_row 1603 1602 ttys016 claude
session "$CFG" 1603 sid-n "$T/plainfolder" waiting 60 86400 "input needed"
# no process: daemons, and a tty whose tab has closed
ps_row 1 0 '??' launchd; ps_row 2000 1 '??' claude
printf 'DEAD TAB TITLE|w' > "$TITLES/last-ttys099"

OUT=$("$TABS" 2>&1); RC=$?
assert_eq "exits 0" "$RC" 0

# the three groups, what needs you first
WAITING=$(section "WAITING ON YOU"); WORKING=$(section "WORKING"); NOTHING=$(section "NOTHING PENDING")
assert_contains "heading counts waiting tabs"    "$OUT" "WAITING ON YOU (8)"
assert_contains "heading counts working tabs"    "$OUT" "WORKING (1)"
assert_contains "heading counts the rest"        "$OUT" "NOTHING PENDING (7)"
assert_eq "waiting comes before working" "$(( $(line_of "WAITING ON YOU") < $(line_of "WORKING (") ))" 1
assert_eq "working comes before the rest" "$(( $(line_of "WORKING (") < $(line_of "NOTHING PENDING") ))" 1

# waiting tabs run to three lines each, so they need telling apart; one-line rows don't
assert_eq "a blank line between waiting tabs" "$(grep -c '^$' <<<"$WAITING")" 7
assert_eq "no blank lines between the one-line rows" "$(grep -c '^$' <<<"$NOTHING")" 0

# blocked: a real prompt, whatever the bead says
B=$(tab "Approve the refund")
assert_contains "blocked: is waiting"            "$WAITING" "Approve the refund"
assert_contains "blocked: says so, why, how long" "$B" "blocked · input needed · 2m"
assert_contains "blocked: the goal"              "$B" "goal  Refunds over the limit need a person to approve them."
assert_contains "blocked: the next step"         "$B" "next  one refund left to approve"
assert_contains "blocked: no bead still counts"  "$WAITING" "blocked · dialog open · 1m"
assert_contains "blocked: a closed bead still counts" "$WAITING" "blocked · sandbox request · 1m"
assert_eq "blocked tabs come before your-turn tabs" \
  "$(( $(line_of "blocked · sandbox request") < $(line_of "your turn") ))" 1

# your turn: finished, with the bead still open
A=$(tab "Resend the order email")
assert_contains "your turn: is waiting"          "$WAITING" "Resend the order email"
assert_contains "your turn: says so and how long" "$A" "your turn · 5h"
assert_contains "the bead's short id"            "$A" "1     Resend the order email"
assert_contains "the space, marked as a worktree" "$A" "Acme ⑂"
assert_not_contains "the worktree's long name stays out" "$A" "acme-x1y"
assert_contains "goal: first sentence, no WHY"   "$A" "goal  customers lose the email when the provider times out."
assert_not_contains "goal: one sentence"         "$A" "happened twice"
assert_not_contains "goal: no epic in front"     "$A" "Checkout reliability"
assert_contains "next: the latest real note"     "$A" "next  retry added, deploy pending"
assert_not_contains "next: a claim line isn't a next step" "$A" "worktree at"
assert_eq "the bead title is said once" "$(grep -c "Resend the order email" <<<"$A")" 1
assert_contains "no notes: says so"              "$(tab "Web bead")" "next  no next step recorded"
assert_contains "a short description is still the goal" "$(tab "Web bead")" "goal  Too short."
assert_contains "the deepest space wins"         "$(tab "Web bead")" "Web"
assert_contains "a space's claude_config is searched" "$WAITING" "Web bead"
G1=$(tab "Globex bead")
assert_contains "second store read; a blocked bead says so" "$G1" "your turn · bead blocked · 1m"
assert_contains "no description: says so"        "$G1" "goal  no description"
assert_contains "worktree gone: the record names the space" "$(tab "Reopened after a close")" "Acme"

# working
assert_contains "busy reads as working, with its age" "$WORKING" "working · 2m"
assert_contains "the outermost claude is the session" "$WORKING" "Reopened after a close"
assert_not_contains "working tabs get no goal line" "$WORKING" "goal"
assert_not_contains "a spawned claude is not the session" "$WORKING" "Trim the footer"

# nothing pending
assert_contains "closed bead: nothing pending"   "$NOTHING" "Trim the footer"
assert_contains "closed: says so and how long"   "$NOTHING" "closed · 2h"
assert_contains "plain shell labelled"           "$NOTHING" "plain shell"
assert_not_contains "plain shell: no stale title" "$OUT" "STALE PLAIN TITLE"
assert_eq "plain shells come last" "$(tail -1 <<<"$OUT" | tr -d ' ')" "plainshell"
assert_not_contains "nothing pending: no goal line" "$NOTHING" "goal"
U=$(grep "Globex" <<<"$NOTHING")
assert_contains "no binding, not launched: unbound" "$U" "unbound"
assert_contains "launched on no bead: no bead"   "$U" "no bead"
assert_not_contains "the environment is never echoed" "$OUT" "hunter2"
assert_contains "no pid file: unbound, not dropped" "$NOTHING" "status unknown"
assert_contains "missing bead: the record's title" "$NOTHING" "Deleted bead"
assert_contains "missing bead: says so"          "$NOTHING" "bead not found"
assert_contains "worktree gone, no record: the folder, no guess" "$NOTHING" "(removed-long-ago)"

assert_not_contains "a closed tab's title isn't listed" "$OUT" "DEAD TAB TITLE"
assert_not_contains "a process with no tty isn't a tab" "$OUT" "??"
assert_not_contains "piped: no colour" "$OUT" $'\e['

# bd: one list per store, whatever the number of tabs and roots, and nothing that writes
assert_eq "one bd call per store" "$(wc -l < "$T/bd.log" | tr -d ' ')" 2
assert_not_contains "never bd show: it rewrites last-touched" "$(cat "$T/bd.log")" "show"
assert_eq "every bd call is a list" "$(grep -vc '^list ' "$T/bd.log")" 0

# what the launcher reads: waiting tabs per space, and a total that includes folders in no space
J=$("$TABS" --waiting 2>&1)
assert_eq "--waiting: per space and in total" \
  "$(python3 -c 'import json,sys; j=json.loads(sys.argv[1]); print(j["total"], sorted(j["spaces"].items()))' "$J")" \
  "8 [('Acme', 4), ('Globex', 2), ('Web', 1)]"

# what the launcher's list reads: a tab's lines all carry its tty, the others carry -
ROWS=$(COLUMNS=200 "$TABS" --rows 2>&1)   # wide enough that no title is cut
row_tty() { awk -F'\t' -v t="$1" 'index($2, t){print $1; exit}' <<<"$ROWS"; }
assert_eq "rows: a tab's row carries its tty"    "$(row_tty "Resend the order email")" "ttys001"
assert_eq "rows: its goal line goes there too"   "$(row_tty "goal  customers lose")" "ttys001"
assert_eq "rows: its next line goes there too"   "$(row_tty "next  retry added")" "ttys001"
assert_eq "rows: a plain shell can be picked"    "$(row_tty "plain shell")" "ttys002"
assert_eq "rows: a heading can't"                "$(row_tty "WORKING (")" "-"
assert_eq "rows: nor can a blank line"           "$(grep -c $'^-\t$' <<<"$ROWS")" 9
assert_contains "rows: the waiting heading is yellow, for fzf --ansi" "$ROWS" $'\e[33mWAITING ON YOU (8)\e[0m'
assert_eq "rows: always two fields" "$(awk -F'\t' 'NF!=2' <<<"$ROWS" | wc -l | tr -d ' ')" 0
assert_eq "rows: fit inside fzf's gutter at the given width" \
  "$(COLUMNS=60 "$TABS" --rows | cut -f2 | sed $'s/\e\\[[0-9;]*m//g' | python3 -c 'import sys; print(int(max(len(l.rstrip("\n")) for l in sys.stdin) <= 56))')" 1

# jumping: the tty reaches osascript as an argument, and only if it looks like one
export FAKE_OSA_LOG="$T/osa.log" TERM_PROGRAM=Apple_Terminal
: > "$FAKE_OSA_LOG"
"$TABS" --jump ttys013; RC=$?
assert_eq "jump: exits 0"                        "$RC" 0
assert_eq "jump: asks for that tab"              "$(cat "$FAKE_OSA_LOG")" "ttys013"
: > "$FAKE_OSA_LOG"
J=$("$TABS" --jump 'ttys013"; do shell script "x' 2>&1); RC=$?
assert_eq "jump: a strange tty fails"            "$RC" 1
assert_contains "jump: and says so"              "$J" "not a terminal tab"
assert_eq "jump: without reaching a script"      "$(cat "$FAKE_OSA_LOG")" ""
J=$(FAKE_OSA_OUT=gone "$TABS" --jump ttys013 2>&1); RC=$?
assert_eq "jump: a closed tab fails"             "$RC" 1
assert_contains "jump: and says so"              "$J" "has closed"
J=$(FAKE_OSA_RC=1 FAKE_OSA_ERR="execution error: Not authorized to send Apple events to Terminal. (-1743)" "$TABS" --jump ttys013 2>&1); RC=$?
assert_eq "jump: declined permission fails"      "$RC" 1
assert_contains "jump: and says where to allow it" "$J" "Privacy & Security"
J=$(FAKE_OSA_RC=1 FAKE_OSA_ERR="something else" "$TABS" --jump ttys013 2>&1); RC=$?
assert_eq "jump: another failure fails"          "$RC" 1
assert_contains "jump: and passes on the reason" "$J" "something else"
: > "$FAKE_OSA_LOG"
J=$(TERM_PROGRAM=iTerm.app "$TABS" --jump ttys013 2>&1); RC=$?
assert_eq "jump: another terminal fails"         "$RC" 1
assert_contains "jump: and says so"              "$J" "Apple Terminal"
assert_eq "jump: without trying"                 "$(cat "$FAKE_OSA_LOG")" ""
J=$(WB_OSASCRIPT=/nonexistent/osascript "$TABS" --jump ttys013 2>&1); RC=$?
assert_eq "jump: no osascript fails"             "$RC" 1
assert_not_contains "jump: no traceback"         "$J" "Traceback"

# on a terminal, lines stop at its width; a pipe gets them whole
assert_contains "piped: lines stay whole" "$(tab "Resend the order")" "Resend the order email"
LONGEST=$(COLUMNS=40 script -q /dev/null "$TABS" 2>/dev/null </dev/null | tr -d '\r' | python3 -c 'import sys; print(max(len(l.rstrip("\n")) for l in sys.stdin))')
assert_eq "on a terminal: cut to its width" "$((LONGEST <= 38))" 1
TERM_OUT=$(COLUMNS=120 script -q /dev/null "$TABS" 2>/dev/null </dev/null)
assert_contains "on a terminal: the waiting heading is yellow" "$TERM_OUT" $'\e[33mWAITING ON YOU (8)\e[0m'
assert_not_contains "on a terminal: the rest isn't" "$TERM_OUT" $'\e[33mWORKING'

# the session record names the bead, even when the launch environment says otherwise
echo "103 claude WB_BEAD=ac-3 WB_SPACE_ROOT=$T/acme" >> "$T/ps.env"
OUT=$("$TABS" 2>&1)
assert_contains "the record beats the launch env" "$(tab "Resend the order")" "Resend the order email"

# a pid file in two config dirs: the newest start wins (a recycled pid leaves the old one)
session "$ALT" 103 sid-old "$T/globex" idle 60 999999
OUT=$("$TABS" 2>&1)
assert_contains "recycled pid: the newest pid file wins" "$(tab "Resend the order")" "your turn · 5h"
rm -f "$ALT/sessions/103.json"

# a pid file in an unexpected shape reads as unbound, and doesn't break the view
echo 'not json' > "$CFG/sessions/403.json"
OUT=$("$TABS" 2>&1); RC=$?
assert_eq "odd pid file: still exits 0" "$RC" 0
assert_eq "odd pid file: unbound, status unknown, not waiting" \
  "$(grep -c "unbound .*status unknown" <<<"$(section "NOTHING PENDING")")" 2
assert_not_contains "odd pid file: no traceback" "$OUT" "Traceback"
session "$CFG" 403 sid-c "$T/acme" idle 7200

# bd failing: the other store's rows are unaffected in the failing store's view
FAKE_DIR="$T/fakebd"; mkdir -p "$FAKE_DIR"; echo 1 > "$FAKE_DIR/rc"
OUT=$(FAKE_BD_DIR="$FAKE_DIR" "$TABS" 2>&1); RC=$?
assert_eq "bd failing: still exits 0" "$RC" 0
A=$(tab "Resend the order")
assert_contains "bd failing: the record's title stays" "$A" "Resend the order email"
assert_contains "bd failing: an idle bound tab stays waiting" "$(section "WAITING ON YOU")" "Resend the order email"
assert_contains "bd failing: says so, with the age" "$A" "your turn · bead status unknown (bd didn't answer) · 5h"
assert_not_contains "bd failing: no empty goal line" "$A" "goal"
assert_contains "bd failing: a done record is still closed" "$(section "NOTHING PENDING")" "closed · 2h"

# bd slow: the deadline holds the view to it
FAKE_DIR="$T/slowbd"; mkdir -p "$FAKE_DIR"; echo 5 > "$FAKE_DIR/sleep"; echo '[]' > "$FAKE_DIR/stdout"
S=$(python3 -c 'import time; print(time.time())')
OUT=$(FAKE_BD_DIR="$FAKE_DIR" WB_TABS_BD_TIMEOUT=0.2 "$TABS" 2>&1)
E=$(python3 -c "import time; print(int(time.time() - $S < 3))")
assert_eq "bd slow: the deadline holds" "$E" 1
assert_contains "bd slow: says so" "$(tab "Resend the order")" "bead status unknown (bd didn't answer)"

# a status this view has never heard of is shown, and doesn't claim anyone's time
session "$CFG" 103 sid-a "$T/wts/acme-x1y" compacting 60
OUT=$("$TABS" 2>&1)
assert_contains "unknown status: shown as it is" "$(section "NOTHING PENDING")" "compacting · 1m"
session "$CFG" 103 sid-a "$T/wts/acme-x1y" idle 18000

# ps failing: nothing to say what's live, so say that
OUT=$(FAKE_PS_RC=1 "$TABS" 2>&1); RC=$?
assert_eq "ps failing: exits 1" "$RC" 1
assert_contains "ps failing: says so" "$OUT" "can't read the process table"

# nothing open
: > "$T/ps.out"
OUT=$("$TABS" 2>&1); RC=$?
assert_eq "no tabs: exits 0" "$RC" 0
assert_contains "no tabs: says so" "$OUT" "no open terminal tabs"
assert_eq "no tabs: --waiting is zero" "$("$TABS" --waiting)" '{"total": 0, "spaces": {}}'
assert_eq "no tabs: --rows says so, unpickable" "$("$TABS" --rows)" $'-\tno open terminal tabs'

finish
