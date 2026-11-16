#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
HOOK="$REPO/bin/wb-session-hook"
export WB_STATE_DIR="$T/state" FAKE_BD_LOG="$T/bd.log"
unset WB_SPACE_ROOT WB_WORKTREE WB_BEAD CLAUDE_CODE_SESSION_ID
# never the real wb-restore: a session start or end saves the snapshot in the background
printf '#!/bin/sh\necho "$*" >> "%s/saves.log"\n' "$T" > "$T/fake-restore"; chmod +x "$T/fake-restore"
export WB_RESTORE_CMD="$T/fake-restore" WB_SAVE_DELAY=0
# saves_after N: wait (up to 5s) for the background saves to log more than N lines, then print the log
saves_after() { local i=0; while [ "$(cat "$T/saves.log" 2>/dev/null | wc -l)" -le "$1" ] && [ $i -lt 50 ]; do
  sleep 0.1; i=$((i + 1)); done; cat "$T/saves.log" 2>/dev/null; }
S="$T/store"; mkstore "$S"
python3 - "$S/.beads/fake.json" <<'EOF'
import json, sys
json.dump([
  {"id": "acme-x1y", "title": "Fix fabric PO search", "status": "in_progress",
   "description": "Typing fabric PO matches scattered letters.", "notes": ""},
  {"id": "acme-ac1", "title": "With acceptance", "status": "open", "description": "d",
   "acceptance_criteria": "Search ranks both words first."},
  {"id": "acme-big", "title": "Big", "status": "open", "description": "x" * 5000},
], open(sys.argv[1], "w"))
EOF
# j EXPR: evaluate a python expression over the JSON on stdin (d), print it
j() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }
ss() { printf '{"session_id":"%s","source":"%s"}' "$1" "$2" | "$HOOK" session-start; }
ups() { printf '{"session_id":"%s","prompt":"hi"}' "$1" | "$HOOK" user-prompt-submit; }
binding() { cat "$WB_STATE_DIR/sessions/$1.json" 2>/dev/null; }
setstatus() { python3 - "$S/.beads/fake.json" "$1" "$2" <<'EOF'
import json, sys
p, i, st = sys.argv[1:]
d = json.load(open(p))
found = [b for b in d if b["id"] == i]
if found: found[0]["status"] = st
else: d.append({"id": i, "title": "Picked up", "status": st, "notes": ""})
json.dump(d, open(p, "w"))
EOF
}

# --- the command parser
parse() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import wb_session; print(wb_session.parse(sys.argv[2]))' "$REPO/lib" "$1"; }
assert_eq "parse: claim" "$(parse 'bd update acme-x1y --claim')" "[('claim', ['acme-x1y'])]"
assert_eq "parse: cd && two ids, --status=" "$(parse 'cd /r && bd update acme-x1y acme-q9z --status=in_progress')" "[('claim', ['acme-x1y', 'acme-q9z'])]"
assert_eq "parse: -s in_progress" "$(parse 'bd update acme-x1y -s in_progress')" "[('claim', ['acme-x1y'])]"
assert_eq "parse: --status in_progress" "$(parse 'bd update acme-x1y --status in_progress --notes x')" "[('claim', ['acme-x1y'])]"
assert_eq "parse: close" "$(parse 'bd close acme-x1y --reason "done"')" "[('close', ['acme-x1y'])]"
assert_eq "parse: create --claim" "$(parse 'bd create --title t --claim')" "[('create-claim', [])]"
assert_eq "parse: a path to bd" "$(parse '/opt/bin/bd close acme-x1y')" "[('close', ['acme-x1y'])]"
assert_eq "parse: update without a claim" "$(parse 'bd update acme-x1y --notes x')" "[]"
assert_eq "parse: bd text inside a description" "$(parse 'bd create --description "then bd close acme-x1y; bd update acme-x1y --claim"')" "[]"
assert_eq "parse: bd text in an echo" "$(parse 'echo "bd update acme-x1y --claim"')" "[]"
assert_eq "parse: junk quoting" "$(parse 'bd close "unterminated')" "[]"

# --- settings
mkdir -p "$T/wb home"; cp -R "$REPO/bin" "$REPO/lib" "$T/wb home/"
out="$("$T/wb home/bin/wb-session-hook" settings)"
assert_eq "settings: valid JSON with four events" "$(printf '%s' "$out" | j 'sorted(d["hooks"])')" "['PostToolUse', 'SessionEnd', 'SessionStart', 'UserPromptSubmit']"
assert_eq "settings: no statusLine" "$(printf '%s' "$out" | j '"statusLine" in d')" "False"
assert_eq "settings: PostToolUse is for Bash" "$(printf '%s' "$out" | j 'd["hooks"]["PostToolUse"][0]["matcher"]')" "Bash"
assert_eq "settings: commands survive a space in the path" \
  "$(printf '%s' "$out" | j '__import__("shlex").split(d["hooks"]["SessionStart"][0]["hooks"][0]["command"])')" \
  "['$(cd "$T" && pwd -P)/wb home/bin/wb-session-hook', 'session-start']"

# a file, not inline JSON: the command line shows in the terminal's window title
out="$("$HOOK" settings-file)"
assert_eq "settings-file: prints the file's path" "$out" "$WB_STATE_DIR/claude-settings.json"
assert_eq "settings-file: holds the settings" "$(cat "$out" 2>/dev/null)" "$("$HOOK" settings)"

# --- session-start
out="$(WB_BEAD=acme-x1y WB_SPACE_ROOT="$S" ss s1 startup)"
ctx="$(printf '%s' "$out" | j 'd["hookSpecificOutput"]["additionalContext"]')"
assert_contains "start: binds from WB_BEAD" "$(binding s1)" '"bead": "acme-x1y"'
assert_contains "start: context names the bead" "$ctx" "This session serves bead acme-x1y: Fix fabric PO search."
assert_contains "start: context has the description" "$ctx" "Typing fabric PO matches scattered letters."
assert_contains "start: context says to ask before switching" "$ctx" "Before you start work on a different bead"
assert_not_contains "start: no acceptance line without criteria" "$ctx" "Acceptance:"
assert_eq "start: names the session" "$(printf '%s' "$out" | j 'd["hookSpecificOutput"]["sessionTitle"]')" "x1y Fix fabric PO search"
assert_contains "start: remembers the name" "$(binding s1)" '"named": "x1y Fix fabric PO search"'

out="$(ss s1 compact)"
assert_contains "compact: re-injects from the binding (no WB_BEAD)" "$(printf '%s' "$out" | j 'd["hookSpecificOutput"]["additionalContext"]')" "acme-x1y"
assert_eq "compact: no sessionTitle when already named" "$(printf '%s' "$out" | j '"sessionTitle" in d["hookSpecificOutput"]')" "False"

out="$(WB_BEAD=acme-ac1 WB_SPACE_ROOT="$S" ss s2 startup)"
assert_contains "start: acceptance criteria included" "$(printf '%s' "$out" | j 'd["hookSpecificOutput"]["additionalContext"]')" $'Acceptance: Search ranks both words first.'
out="$(WB_BEAD=acme-big WB_SPACE_ROOT="$S" ss s3 startup)"
assert_eq "start: description cut to 1,500" "$(printf '%s' "$out" | j 'max(len(l) for l in d["hookSpecificOutput"]["additionalContext"].splitlines())')" "1500"

setstatus acme-ac1 closed
out="$(WB_BEAD=acme-ac1 WB_SPACE_ROOT="$S" ss c1 clear)"
assert_contains "start: a closed launch bead binds as done" "$(binding c1)" '"done": true'
assert_contains "start: and says so" "$(printf '%s' "$out" | j 'd["hookSpecificOutput"]["additionalContext"]')" "It is closed"
setstatus acme-ac1 open

out="$(WB_SPACE_ROOT="$S" ss s4 startup)"
assert_eq "start: no bead, no output" "$out" ""
[ -z "$(binding s4)" ] && ok "start: no bead, no file" || bad "start: no bead wrote a file"

start=$SECONDS; out="$(FAKE_BD_SLEEP=5 WB_BEAD=acme-x1y WB_SPACE_ROOT="$S" ss s5 startup)"; rc=$?; took=$((SECONDS - start))
assert_eq "start: bd hangs → silent, exit 0" "$out:$rc" ":0"
if [ "$took" -lt 3 ]; then ok "start: hang cut off (${took}s)"; else bad "start: hang took ${took}s"; fi

# a big store's bd show takes ~2s idle, more while claude is starting: the
# default limit must leave room for it, or the session silently never binds
out="$(unset WB_BD_TIMEOUT; FAKE_BD_SLEEP=3.5 WB_BEAD=acme-x1y WB_SPACE_ROOT="$S" ss s6 startup)"
assert_contains "start: a slow bd within the default limit still binds" "$(binding s6)" "acme-x1y"

touch -t "$(date -v-31d +%Y%m%d%H%M)" "$WB_STATE_DIR/sessions/s2.json"
touch -t "$(date -v-29d +%Y%m%d%H%M)" "$WB_STATE_DIR/sessions/s3.json"
ss s9 startup >/dev/null
[ ! -e "$WB_STATE_DIR/sessions/s2.json" ] && ok "prune: 31 days old is gone" || bad "prune: 31-day file kept"
[ -e "$WB_STATE_DIR/sessions/s3.json" ] && ok "prune: 29 days old stays" || bad "prune: 29-day file removed"

# --- user-prompt-submit
printf '%s' '{"bead":"acme-x1y","title":"Fix fabric PO search","root":"'"$S"'","since":"x","done":false,"named":null}' > "$WB_STATE_DIR/sessions/u1.json"
assert_eq "prompt: names a session not yet named" "$(ups u1 | j 'd["hookSpecificOutput"]["sessionTitle"]')" "x1y Fix fabric PO search"
assert_eq "prompt: then nothing" "$(ups u1)" ""
assert_eq "prompt: no binding, nothing" "$(ups u9)" ""

# --- post-tool-use
# ptu SID COMMAND [STDOUT] [IS_ERROR]
ptu() { python3 -c 'import json,sys; print(json.dumps({"session_id":sys.argv[1],"tool_name":"Bash","tool_input":{"command":sys.argv[2]},"tool_response":{"stdout":sys.argv[3],"stderr":"","is_error":sys.argv[4]=="1"}}))' "$1" "$2" "${3:-}" "${4:-0}" | "$HOOK" post-tool-use; }
msg() { j 'd.get("systemMessage","")'; }
pctx() { j 'd.get("hookSpecificOutput",{}).get("additionalContext","")'; }
export WB_SPACE_ROOT="$S"
setstatus acme-q9z in_progress

out="$(ptu p1 'bd update acme-x1y --claim')"
assert_eq "pick up: notice" "$(printf '%s' "$out" | msg)" "→ this session is now on x1y Fix fabric PO search"
assert_contains "pick up: binds" "$(binding p1)" '"bead": "acme-x1y"'
mkdir -p "$T/wt"; git -C "$T/wt" init -q -b feat/x; : > "$FAKE_BD_LOG"
WB_WORKTREE="$T/wt" ptu p2 'bd update acme-x1y --claim' >/dev/null
assert_contains "pick up: claim note in a worktree" "$(cat "$FAKE_BD_LOG")" "update acme-x1y --append-notes Branch: feat/x (worktree at $T/wt)"
ptu p3 'bd create --silent --claim --title "Picked up"' 'acme-q9z' >/dev/null
assert_contains "pick up: from create --claim (--silent)" "$(binding p3)" '"bead": "acme-q9z"'
ptu p4 'bd create --claim --title "Picked up"' '✓ Created issue: acme-q9z' >/dev/null
assert_contains "pick up: from create --claim (Created issue:)" "$(binding p4)" '"bead": "acme-q9z"'
assert_eq "same bead: silent" "$(ptu p1 'bd update acme-x1y --claim')" ""

before="$(binding p1)"; out="$(ptu p1 'bd update acme-q9z --claim')"
assert_eq "switch: notice" "$(printf '%s' "$out" | msg)" "→ claimed q9z while this session is on x1y"
assert_contains "switch: continue-here command" "$(printf '%s' "$out" | pctx)" "wb-focus acme-q9z"
assert_contains "switch: start-fresh command" "$(printf '%s' "$out" | pctx)" "bd update acme-q9z --status open"
assert_eq "switch: binding unchanged" "$(binding p1)" "$before"
setstatus acme-big open
assert_eq "claim that didn't take: silent" "$(ptu p1 'bd update acme-big --claim')" ""
assert_eq "claim that didn't take: no pick up" "$(ptu p5 'bd update acme-big --claim'; binding p5)" ""

assert_eq "close refused: silent" "$(ptu p1 'bd close acme-x1y')" ""
assert_contains "close refused: not done" "$(binding p1)" '"done": false'
setstatus acme-x1y closed
out="$(ptu p1 'bd close acme-x1y --reason "shipped"')"
assert_eq "close: notice" "$(printf '%s' "$out" | msg)" "✓ x1y closed · this session is done"
assert_contains "close: tells Claude to say /exit" "$(printf '%s' "$out" | pctx)" "/exit"
assert_contains "close: marks done" "$(binding p1)" '"done": true'
setstatus acme-x1y in_progress
assert_eq "close of another bead: silent" "$(ptu p3 'bd close acme-x1y')" ""
out="$(ptu p1 'bd update acme-q9z --claim')"
assert_contains "claim after done: recommends fresh" "$(printf '%s' "$out" | pctx)" "starting fresh is recommended"
assert_contains "claim after done: says it's closed" "$(printf '%s' "$out" | pctx)" "which is closed"

printf '%s' '{"bead":"acme-x1y","title":"Fix fabric PO search","root":"'"$S"'","since":"x","done":false,"named":null}' > "$WB_STATE_DIR/sessions/p9.json"
setstatus acme-x1y closed
out="$(ptu p9 'bd close acme-x1y && bd update acme-q9z --claim')"
assert_contains "close and claim in one command: both notices" "$(printf '%s' "$out" | msg)" $'✓ x1y closed · this session is done\n→ claimed q9z while this session is on x1y'
assert_contains "close and claim in one command: still asks" "$(printf '%s' "$out" | pctx)" "starting fresh is recommended"
setstatus acme-x1y in_progress

# a bead someone else holds is in_progress too; claiming it changed nothing
setstatus acme-oth in_progress
python3 - "$S/.beads/fake.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for b in d:
    if b["id"] == "acme-oth": b["assignee"] = "Other Person"
    if b["id"] == "acme-q9z": b["assignee"] = "Me"
json.dump(d, open(sys.argv[1], "w"))
EOF
export BEADS_ACTOR="Me"
out="$(ptu o1 'bd update acme-oth --claim 2>&1 | tail -3')"
assert_eq "someone else's bead: no pick up" "$out|$(binding o1)" "|"
printf '%s' '{"bead":"acme-x1y","title":"Fix fabric PO search","root":"'"$S"'","since":"x","done":false,"named":null}' > "$WB_STATE_DIR/sessions/o2.json"
assert_eq "someone else's bead: no ask" "$(ptu o2 'bd update acme-oth --claim')" ""
assert_contains "my own claim still counts" "$(ptu o3 'bd update acme-q9z --claim' | msg)" "now on q9z"
out="$(ptu o2 'bd update acme-q9z --claim')"
assert_contains "the ask names wb-focus by its full path" "$(printf '%s' "$out" | pctx)" "$REPO/bin/wb-focus acme-q9z"
unset BEADS_ACTOR

# --- close-out names what is left in the bead's epic, to keep the flow going
python3 - "$S/.beads/fake.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
kid = lambda i, title, **kw: {**dict(id=i, title=title, parent="acme-ep", priority=2, status="open"), **kw}
d += [
  {"id": "acme-ep", "title": "Epic: invoice sync", "status": "open", "issue_type": "epic",
   "description": "Match supplier invoices to purchase orders."},
  kid("acme-e1", "Invoices without a PO number", status="in_progress"),
  kid("acme-e2", "Already shipped", status="closed"),
  kid("acme-e3", "Flag invoices with no matching PO", priority=1),
  kid("acme-e4", "Match invoices to POs by supplier ref", priority=3, labels=["wave:1"]),
  kid("acme-e5", "Import supplier refs", status="in_progress", assignee="Other Person"),
  kid("acme-e6", "Someday: OCR the paper ones", labels=["icebox"]),
  kid("acme-e7", "After the audit", status="deferred"),
  kid("acme-e8", "Waits on the bank", status="blocked"),
  kid("acme-e9", "Waits on e3", dependencies=[{"issue_id": "acme-e9", "depends_on_id": "acme-e3", "type": "blocks"}]),
  kid("acme-ea", "Sub-epic: credit notes", issue_type="epic"),
  kid("acme-eb", "Credit note numbering", status="in_progress"),
  {"id": "acme-zz", "title": "Not in the epic", "status": "open", "priority": 0},
  {"id": "acme-s1", "title": "Last one standing", "parent": "acme-ep2", "status": "in_progress"},
  {"id": "acme-s2", "title": "Done before", "parent": "acme-ep2", "status": "closed"},
  {"id": "acme-ep2", "title": "Small epic", "status": "open", "issue_type": "epic"},
]
json.dump(d, open(sys.argv[1], "w"))
EOF
printf '%s' '{"bead":"acme-e1","title":"Invoices without a PO number","root":"'"$S"'","since":"x","done":false,"named":null}' > "$WB_STATE_DIR/sessions/e1.json"
setstatus acme-e1 closed
out="$(ptu e1 'bd close acme-e1')"; m="$(printf '%s' "$out" | msg)"; c="$(printf '%s' "$out" | pctx)"
assert_eq "epic close-out: the epic's next work, in list order, under the done line" "$m" \
"✓ e1 closed · this session is done
  invoice sync: 2 of 11 done
  next here:  e4  NOW P3  Match invoices to POs by supplier ref
              e3  P1  Flag invoices with no matching PO
  in another session:  e5  Import supplier refs
                       eb  Credit note numbering"
assert_not_contains "epic close-out: nothing from outside the epic" "$m" "zz"
printf '%s' '{"bead":"acme-e1","title":"x","root":"'"$S"'","since":"x","done":false,"named":null}' > "$WB_STATE_DIR/sessions/e3.json"
python3 - "$S/.beads/fake.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for b in d:
    if b["id"] == "acme-ep": b["title"] = "Epic: make the supplier ledger and the bank agree on what is owed"
json.dump(d, open(sys.argv[1], "w"))
PY
assert_contains "epic close-out: a long epic name is cut" "$(ptu e3 'bd close acme-e1' | msg)" "  make the supplier ledger and the bank a…: 2 of 11 done"
assert_contains "epic close-out: Claude gets the picks by full id" "$c" "acme-e4: Match invoices to POs by supplier ref"
assert_contains "epic close-out: Claude checks the notes for a different next step" "$c" "notes"
assert_contains "epic close-out: Claude gets the epic's description" "$c" "Match supplier invoices to purchase orders."
assert_contains "epic close-out: /exit only once they are done for now" "$c" "If they are done for now: Finish the close-out"
assert_contains "epic close-out: the binding remembers the epic" "$(binding e1)" '"epic": "acme-ep"'
setstatus acme-e3 in_progress
out="$(BEADS_ACTOR=Me ptu e1 'bd update acme-e3 --claim')"
assert_contains "claiming the epic's next bead: continuing here is recommended" "$(printf '%s' "$out" | pctx)" "continuing here is recommended"
assert_not_contains "claiming the epic's next bead: not told to start fresh" "$(printf '%s' "$out" | pctx)" "starting fresh is recommended"

# a worktree session can't carry on: its worktree goes at close-out, and the
# next bead needs its own. The list still shows; the next one starts fresh.
setstatus acme-e3 open
printf '%s' '{"bead":"acme-e1","title":"x","root":"'"$S"'","since":"x","done":false,"named":null}' > "$WB_STATE_DIR/sessions/w1.json"
out="$(WB_WORKTREE="$T/wt" ptu w1 'bd close acme-e1')"; c="$(printf '%s' "$out" | pctx)"
assert_contains "worktree close-out: still lists the epic's next work" "$(printf '%s' "$out" | msg)" "next here:  e4"
assert_contains "worktree close-out: the next bead starts fresh from the launcher" "$c" "start acme-e4 from the workbench launcher in a fresh session"
assert_not_contains "worktree close-out: no carrying on in this session" "$c" "wb-focus"
out="$(setstatus acme-e3 in_progress; BEADS_ACTOR=Me WB_WORKTREE="$T/wt" ptu w1 'bd update acme-e3 --claim')"
assert_contains "worktree: claiming the epic's next bead still recommends fresh" "$(printf '%s' "$out" | pctx)" "starting fresh is recommended"

printf '%s' '{"bead":"acme-s1","title":"Last one standing","root":"'"$S"'","since":"x","done":false,"named":null}' > "$WB_STATE_DIR/sessions/e2.json"
setstatus acme-s1 closed
out="$(ptu e2 'bd close acme-s1')"
assert_eq "epic close-out: the last bead says the epic looks done" "$(printf '%s' "$out" | msg)" \
"✓ s1 closed · this session is done
  Small epic: 2 of 2 done · the epic looks finished"
assert_contains "epic close-out: Claude offers to close the epic" "$(printf '%s' "$out" | pctx)" "bd close acme-ep2"

python3 - "$S/.beads/fake.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d += [{"id": "acme-ep3", "title": "Third epic", "status": "open", "issue_type": "epic"},
      {"id": "acme-t1", "title": "Mine", "parent": "acme-ep3", "status": "closed"},
      {"id": "acme-t2", "title": "Theirs", "parent": "acme-ep3", "status": "in_progress"}]
json.dump(d, open(sys.argv[1], "w"))
PY
printf '%s' '{"bead":"acme-t1","title":"Mine","root":"'"$S"'","since":"x","done":false,"named":null}' > "$WB_STATE_DIR/sessions/e4.json"
assert_eq "epic close-out: the rest in another session, so nothing called shelved" "$(ptu e4 'bd close acme-t1' | msg)" \
"✓ t1 closed · this session is done
  Third epic: 1 of 2 done
  in another session:  t2  Theirs"

assert_eq "failed tool: silent" "$(ptu p6 'bd update acme-x1y --claim' '' 1)" ""
assert_eq "create without --claim: silent" "$(ptu p6 'bd create --silent --title t' 'acme-q9z')" ""
assert_eq "no space root: silent" "$(env -u WB_SPACE_ROOT bash -c "$(declare -f ptu j); HOOK='$HOOK'; ptu p7 'bd update acme-x1y --claim'")" ""
start=$SECONDS; out="$(FAKE_BD_SLEEP=5 ptu p8 'bd update acme-x1y --claim')"; rc=$?; took=$((SECONDS - start))
assert_eq "post: bd hangs → silent, exit 0" "$out:$rc" ":0"
if [ "$took" -lt 3 ]; then ok "post: hang cut off (${took}s)"; else bad "post: hang took ${took}s"; fi

# --- the restore snapshot follows sessions opening and closing, not only the 10-minute save
rm -f "$T/saves.log"
out="$(printf '{"session_id":"sid-new","source":"startup"}' | "$HOOK" session-start)"; rc=$?
assert_eq "session start, unbound: still exit 0" "$rc" "0"
assert_eq "session start saves the snapshot" "$(saves_after 0)" "save --quiet"
out="$(printf '{"session_id":"sid-new","reason":"prompt_input_exit"}' | "$HOOK" session-end)"; rc=$?
assert_eq "session end: silent, exit 0" "$out:$rc" ":0"
assert_eq "session end saves, leaving the ending session out (it is still running)" \
  "$(saves_after 1 | tail -1)" "save --quiet --without sid-new"
out="$(printf '{"session_id":"sid-new"}' | WB_RESTORE_CMD="$T/missing" "$HOOK" session-end 2>&1)"; rc=$?
assert_eq "a save that can't run never troubles the session" "$out:$rc" ":0"

for sub in session-start user-prompt-submit post-tool-use session-end; do
  out="$(printf 'not json' | "$HOOK" $sub 2>&1)"; rc=$?
  assert_eq "junk stdin: $sub is silent, exit 0" "$out:$rc" ":0"
done
finish
