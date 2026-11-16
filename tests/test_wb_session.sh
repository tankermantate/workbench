#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
SL="$REPO/bin/wb-statusline-bead"; FOCUS="$REPO/bin/wb-focus"
export WB_STATE_DIR="$T/state" FAKE_BD_LOG="$T/bd.log"
unset WB_SPACE_ROOT WB_WORKTREE WB_BEAD CLAUDE_CODE_SESSION_ID
S="$T/store"; mkstore "$S"
cat > "$S/.beads/fake.json" <<EOF
[{"id":"acme-x1y","title":"Fix fabric PO search","status":"in_progress","notes":""},
 {"id":"acme-q9z","title":"A title that is well over forty characters long","status":"in_progress",
  "notes":"Branch: feat/old (worktree at $T/elsewhere)"},
 {"id":"acme-n0t","title":"Noted already","status":"in_progress","notes":"Branch: feat/x (worktree at $T/wt)"},
 {"id":"acme-m3t","title":"Linked already","status":"in_progress","notes":"rewritten","metadata":{"wb_worktree":"$T/wt"}}]
EOF
mkdir -p "$T/wt"; git -C "$T/wt" init -q -b feat/x
bindfile() { printf '%s' "$2" > "$WB_STATE_DIR/sessions/$1.json"; }
mkdir -p "$WB_STATE_DIR/sessions"
bindfile s1 '{"bead":"acme-x1y","title":"Fix fabric PO search","root":"/r","since":"2026-10-21T00:00:00Z","done":false,"named":null}'
bindfile s2 '{"bead":"acme-q9z","title":"A title that is well over forty characters long","root":"/r","since":"2026-10-21T00:00:00Z","done":false,"named":null}'
bindfile s3 '{"bead":"acme-x1y","title":"Fix fabric PO search","root":"/r","since":"2026-10-21T00:00:00Z","done":true,"named":null}'
bindfile bad 'not json'

sl() { printf '%s' "$1" | "$SL"; }
assert_eq "statusline: bound" "$(sl '{"session_id":"s1"}')" "◆ x1y Fix fabric PO search"
assert_eq "statusline: done" "$(sl '{"session_id":"s3"}')" "✓ x1y done · close this session"
assert_eq "statusline: long title cut to 40 with …" "$(sl '{"session_id":"s2"}')" "◆ q9z A title that is well over forty charact…"
assert_eq "statusline: workbench session, no bead" "$(WB_SPACE_ROOT="$S" sl '{"session_id":"s9"}')" "◇ no bead"
assert_eq "statusline: not a workbench session" "$(sl '{"session_id":"s9"}')" ""
assert_eq "statusline: corrupt file" "$(sl '{"session_id":"bad"}')" ""
out="$(sl 'garbage')"; rc=$?
assert_eq "statusline: bad stdin prints nothing, exits 0" "$out:$rc" ":0"
assert_eq "statusline: unsafe id" "$(WB_SPACE_ROOT="$S" sl '{"session_id":"../s1"}')" ""
assert_eq "two sessions: each its own bead" "$(sl '{"session_id":"s1"}' | awk '{print $1, $2}')|$(sl '{"session_id":"s2"}' | awk '{print $1, $2}')" "◆ x1y|◆ q9z"

export CLAUDE_CODE_SESSION_ID=f1 WB_SPACE_ROOT="$S"
assert_eq "focus: binds" "$("$FOCUS" acme-x1y)" "→ this session is now on x1y Fix fabric PO search"
b="$(cat "$WB_STATE_DIR/sessions/f1.json")"
assert_contains "focus: file has the bead" "$b" '"bead": "acme-x1y"'
assert_contains "focus: not done" "$b" '"done": false'
assert_contains "focus: not yet named" "$b" '"named": null'
assert_eq "focus: prints" "$("$FOCUS")" "acme-x1y Fix fabric PO search"
err="$("$FOCUS" acme-nope 2>&1 >/dev/null)"; rc=$?
assert_eq "focus: unknown bead exits 1" "$rc" "1"
assert_contains "focus: unknown bead says which" "$err" "acme-nope"
assert_contains "focus: unknown bead leaves the binding" "$(cat "$WB_STATE_DIR/sessions/f1.json")" "acme-x1y"
assert_eq "focus: clear" "$("$FOCUS" --clear)" "→ unbound"
[ ! -e "$WB_STATE_DIR/sessions/f1.json" ] && ok "focus: clear removes the file" || bad "focus: clear left the file"
assert_eq "focus: prints no bead" "$("$FOCUS")" "no bead"
err="$(env -u CLAUDE_CODE_SESSION_ID "$FOCUS" acme-x1y 2>&1)"; rc=$?
assert_eq "focus: outside a session exits 1" "$rc" "1"
assert_contains "focus: outside a session says where to run it" "$err" "inside Claude"
assert_not_contains "focus: no worktree, no claim note" "$(cat "$FAKE_BD_LOG" 2>/dev/null)" "append-notes"

: > "$FAKE_BD_LOG"
WB_WORKTREE="$T/wt" "$FOCUS" acme-q9z >/dev/null
assert_contains "focus: claim note in a worktree" "$(cat "$FAKE_BD_LOG")" "update acme-q9z --append-notes Branch: feat/x (worktree at $T/wt) --set-metadata wb_worktree=$T/wt"
: > "$FAKE_BD_LOG"
WB_WORKTREE="$T/wt" "$FOCUS" acme-n0t >/dev/null
assert_not_contains "focus: no duplicate claim note" "$(cat "$FAKE_BD_LOG")" "append-notes"
assert_contains "focus: an old claim note gains the metadata link" "$(cat "$FAKE_BD_LOG")" "update acme-n0t --set-metadata wb_worktree=$T/wt"
: > "$FAKE_BD_LOG"
WB_WORKTREE="$T/wt" "$FOCUS" acme-m3t >/dev/null
assert_not_contains "focus: linked by metadata, notes rewritten: nothing to add" "$(cat "$FAKE_BD_LOG")" "update"
finish
