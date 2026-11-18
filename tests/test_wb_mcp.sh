#!/usr/bin/env bash
# wb-mcp: the Claude Desktop connection (spec: docs/specs/2026-11-17-plan-in-claude-design.md)
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
MCP="$REPO/bin/wb-mcp"; FX="$REPO/tests/fixtures/groom"
ME=11111111-aaaa-4aaa-8aaa-000000000001     # made-up accounts: the persona Desktop is signed in as
WORK=22222222-bbbb-4bbb-8bbb-000000000002   # and another one, on a space's own claude_config

mkdir -p "$T/home" "$T/work-cfg" "$T/desktop" "$T/plans"
export HOME="$T/home"
printf '{"oauthAccount":{"accountUuid":"%s"}}' "$ME" > "$HOME/.claude.json"
printf '{"oauthAccount":{"accountUuid":"%s"}}' "$WORK" > "$T/work-cfg/.claude.json"
desktop_as() { printf '{"locale":"en","lastKnownAccountUuid":"%s"}' "$1" > "$T/desktop/config.json"; }
desktop_as "$ME"
cp -R "$FX/plan" "$T/plans/acme"
mkstore "$T/acme" "$T/other" "$T/work"; mkdir -p "$T/nostore"
reset_stores() {
  cat > "$T/acme/.beads/fake.json" <<'EOF'
[{"id":"acme-1","title":"Plain","status":"open","priority":2,"issue_type":"task","labels":[]},
 {"id":"acme-2","title":"Money","status":"open","priority":2,"issue_type":"task","labels":["ws:money"]},
 {"id":"acme-3","title":"An epic","status":"open","priority":1,"issue_type":"epic","labels":[]},
 {"id":"acme-4","title":"Done","status":"closed","priority":2,"issue_type":"task","labels":[]},
 {"id":"acme-5","title":"Shelved","status":"open","priority":3,"issue_type":"task","labels":["icebox"]}]
EOF
  printf '[{"id":"oth-1","title":"Other","status":"open","priority":2,"issue_type":"task","labels":[]}]' > "$T/other/.beads/fake.json"
  printf '[{"id":"wk-1","title":"Work secret","status":"open","priority":2,"issue_type":"task","labels":[]}]' > "$T/work/.beads/fake.json"
}
reset_stores
cat > "$T/spaces.toml" <<EOF
[[space]]
name = "acme"
root = "$T/acme"
beads = true
[[space]]
name = "other"
root = "$T/other"
group = "Personal"
[[space]]
name = "work"
root = "$T/work"
claude_config = "$T/work-cfg"
[[space]]
name = "nostore"
root = "$T/nostore"
EOF
export WORKBENCH_CONFIG="$T/spaces.toml" WB_PLANS_DIR="$T/plans" WB_DESKTOP_DIR="$T/desktop" WB_TODAY=2026-10-23
export FAKE_BD_STATEFUL=1 FAKE_BD_LOG="$T/bd.log"

# serve LINE…: each argument one message to the server; prints its stdout
serve() { printf '%s\n' "$@" | "$MCP" serve 2>"$T/err"; }
INIT='{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2099-01-01","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
# call TOOL ARGS-JSON: the tool's result as "ERR <text>" or "OK <text>"
call() {
  local a="${2:-}"; [ -n "$a" ] || a='{}'
  serve "$INIT" '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$a}}" |
    python3 -c 'import json,sys
for l in sys.stdin:
    m = json.loads(l)
    if m.get("id") != 7: continue
    if "error" in m: print("RPCERR", m["error"]["message"]); break
    r = m["result"]; print("ERR" if r.get("isError") else "OK", " ".join(c["text"] for c in r["content"]))'
}
field() { python3 -c "import json; b=[b for b in json.load(open('$T/$1/.beads/fake.json')) if b['id']=='$2']; print(b[0].get('$3', '') if b else 'NONE')"; }

# --- protocol ---
out="$(serve "$INIT")"
assert_eq "initialize echoes the client's protocol version and offers tools" \
  "$(printf '%s' "$out" | python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]; print(r["protocolVersion"], "tools" in r["capabilities"], r["serverInfo"]["name"])')" \
  "2099-01-01 True workbench"
assert_eq "a notification gets no reply" "$(serve '{"jsonrpc":"2.0","method":"notifications/initialized"}')" ""
assert_eq "ping" "$(serve '{"jsonrpc":"2.0","id":3,"method":"ping"}')" '{"jsonrpc": "2.0", "id": 3, "result": {}}'
assert_contains "an unknown method is -32601" "$(serve '{"jsonrpc":"2.0","id":4,"method":"resources/list"}')" '"code": -32601'
assert_contains "a line that is not JSON is -32700" "$(serve 'not json')" '"code": -32700'
tools="$(serve '{"jsonrpc":"2.0","id":5,"method":"tools/list"}' | python3 -c 'import json,sys; print(" ".join(sorted(t["name"] for t in json.load(sys.stdin)["result"]["tools"])))')"
assert_eq "the tools" "$tools" "add_dependency create_bead list_beads list_spaces show_bead update_bead"

# --- persona ---
out="$(call list_spaces)"
assert_contains "list_spaces: a space on Desktop's account" "$out" '"acme"'
assert_contains "list_spaces: another one" "$out" '"other"'
assert_not_contains "list_spaces: not a space on another account" "$out" '"work"'
assert_not_contains "list_spaces: not a space with no store" "$out" '"nostore"'
assert_contains "list_spaces: the protected labels" "$out" 'ws:money'
assert_contains "list_spaces: protected.md itself, for Claude to apply its judgement part" "$out" 'Acme protected'
assert_contains "list_spaces: a space with no plan says everything is protected" "$out" 'no plan'
: > "$T/bd.log"
out="$(call list_beads '{"space":"work"}')"
assert_contains "a space on another account is refused" "$out" "ERR"
assert_contains "... naming the ones it can use" "$out" "acme, other"
assert_eq "... without running bd there" "$(cat "$T/bd.log")" ""
desktop_as "$WORK"
assert_contains "signed in as the other account, only its spaces" "$(call list_spaces)" '"work"'
assert_contains "... and the first persona's are refused" "$(call list_beads '{"space":"acme"}')" "ERR"
desktop_as 99999999-cccc-4ccc-8ccc-000000000009
out="$(call list_spaces)"
assert_contains "an account no space uses: refused" "$out" "ERR"
assert_contains "... saying how to fix it" "$out" "claude_config"
rm "$T/desktop/config.json"
assert_contains "Desktop's account unknown: refused" "$(call list_spaces)" "ERR"
desktop_as "$ME"

# --- reads ---
out="$(call list_beads '{"space":"acme"}')"
assert_contains "list_beads: open beads" "$out" '"acme-1"'
assert_not_contains "list_beads: closed ones only when asked" "$out" '"acme-4"'
assert_contains "list_beads: include_closed" "$(call list_beads '{"space":"acme","include_closed":true}')" '"acme-4"'
assert_contains "show_bead" "$(call show_bead '{"space":"acme","id":"acme-2"}')" '"Money"'
assert_contains "show_bead: an id from another store is refused" "$(call show_bead '{"space":"acme","id":"oth-1"}')" "ERR"
assert_contains "a missing argument is a tool error" "$(call show_bead '{"space":"acme"}')" "ERR"

# --- writes ---
out="$(call create_bead '{"space":"acme","title":"Child task","parent":"acme-3","type":"task","priority":2,"description":"why"}')"
assert_contains "create_bead under an epic" "$out" "acme-3.1"
assert_eq "... in the store, with its parent" "$(field acme acme-3.1 parent)" "acme-3"
out="$(call create_bead '{"space":"acme","title":"x","parent":"oth-1"}')"
assert_contains "create_bead: a parent from another store is refused" "$out" "ERR"
assert_contains "create_bead: grooming's labels are refused" "$(call create_bead '{"space":"acme","title":"x","labels":["wave:1"]}')" "ERR"
assert_contains "create_bead: a bad type is refused" "$(call create_bead '{"space":"acme","title":"x","type":"molecule"}')" "ERR"
assert_contains "create_bead: a label with a comma is refused" "$(call create_bead '{"space":"acme","title":"x","labels":["a,b"]}')" "ERR"

assert_contains "update: append notes to a protected bead" "$(call update_bead '{"space":"acme","id":"acme-2","append_notes":"talked it through"}')" "OK"
assert_eq "... written" "$(field acme acme-2 notes)" "talked it through"
out="$(call update_bead '{"space":"acme","id":"acme-2","priority":3}')"
assert_contains "update: lowering a protected bead's priority is refused" "$out" "ERR"
assert_contains "... saying it is protected" "$out" "protected"
assert_eq "... unchanged" "$(field acme acme-2 priority)" "2"
assert_contains "update: raising it is fine" "$(call update_bead '{"space":"acme","id":"acme-2","priority":1}')" "OK"
assert_eq "... written" "$(field acme acme-2 priority)" "1"
assert_contains "update: dropping a protected label is refused" "$(call update_bead '{"space":"acme","id":"acme-2","remove_labels":["ws:money"]}')" "ERR"
assert_contains "update: an unprotected bead's priority can drop" "$(call update_bead '{"space":"acme","id":"acme-1","priority":4,"title":"Plainer","add_labels":["docs"]}')" "OK"
assert_eq "... title" "$(field acme acme-1 title)" "Plainer"
assert_eq "... label" "$(field acme acme-1 labels)" "['docs']"
assert_contains "update: icebox is grooming's" "$(call update_bead '{"space":"acme","id":"acme-1","add_labels":["icebox"]}')" "ERR"
assert_contains "update: and so is taking it off" "$(call update_bead '{"space":"acme","id":"acme-5","remove_labels":["icebox"]}')" "ERR"
assert_contains "update: a closed bead is refused" "$(call update_bead '{"space":"acme","id":"acme-4","title":"x"}')" "ERR"
assert_contains "update: nothing to change is an error" "$(call update_bead '{"space":"acme","id":"acme-1"}')" "ERR"
assert_contains "update: reparent to another store refused" "$(call update_bead '{"space":"acme","id":"acme-1","parent":"oth-1"}')" "ERR"
out="$(call update_bead '{"space":"other","id":"oth-1","priority":3}')"
assert_contains "no plan: every bead is protected" "$out" "ERR"
assert_contains "... saying why" "$out" "plan"

assert_contains "add_dependency: a bead from another store is refused" "$(call add_dependency '{"space":"acme","id":"acme-1","depends_on":"oth-1"}')" "ERR"
assert_eq "... nothing written" "$(field acme acme-1 dependencies)" ""
assert_contains "add_dependency within the store" "$(call add_dependency '{"space":"acme","id":"acme-1","depends_on":"acme-3"}')" "OK"
assert_eq "... written" "$(field acme acme-1 dependencies)" "[{'issue_id': 'acme-1', 'depends_on_id': 'acme-3', 'type': 'blocks'}]"
assert_not_contains "nothing closes, claims or defers" "$(grep -E '^(close|undefer)|--status|-s |--claim|--defer' "$T/bd.log")" "acme"

# --- connect / check / disconnect ---
CFG="$T/desktop/claude_desktop_config.json"
printf '{"preferences":{"sidebarMode":"chat"},"mcpServers":{"other":{"command":"x"}}}' > "$CFG"
export WB_PGREP=false   # Desktop not running
out="$("$MCP" connect 2>&1)"; rc=$?
assert_eq "connect exits 0" "$rc" "0"
assert_contains "connect says to open Desktop" "$out" "Claude"
assert_eq "connect: Desktop's own settings and servers kept" \
  "$(python3 -c "import json; d=json.load(open('$CFG')); print(d['preferences'], sorted(d['mcpServers']))")" \
  "{'sidebarMode': 'chat'} ['other', 'workbench']"
assert_eq "connect: an absolute python 3.11+ runs wb-mcp serve" \
  "$(python3 -c "import json,os; w=json.load(open('$CFG'))['mcpServers']['workbench']; print(os.path.isabs(w['command']), w['args'][0].endswith('/bin/wb-mcp'), w['args'][1])")" \
  "True True serve"
assert_contains "connect: PATH finds bd" "$(python3 -c "import json; print(json.load(open('$CFG'))['mcpServers']['workbench']['env']['PATH'])")" "$REPO/tests/fake"
assert_eq "connect: WORKBENCH_CONFIG carried over when set" \
  "$(python3 -c "import json; print(json.load(open('$CFG'))['mcpServers']['workbench']['env']['WORKBENCH_CONFIG'])")" "$T/spaces.toml"
if [ -f "$CFG.wb-backup" ]; then ok "connect: backup made"; else bad "no backup"; fi
assert_contains "connect again: already" "$("$MCP" connect 2>&1)" "already"
printf '{"mcpServers":{}}' > "$CFG"
out="$(WB_PGREP=true "$MCP" connect 2>&1)"; rc=$?
assert_eq "connect while Desktop runs: refused" "$rc" "1"
assert_contains "... saying to quit it" "$out" "Quit"
assert_eq "... unchanged" "$(cat "$CFG")" '{"mcpServers":{}}'
assert_contains "disconnect while Desktop runs: refused too" "$("$MCP" connect >/dev/null; WB_PGREP=true "$MCP" disconnect 2>&1)" "Quit"
printf '{not json' > "$T/bad.json"; cp "$T/bad.json" "$CFG"
"$MCP" connect >/dev/null 2>&1; rc=$?
assert_eq "connect: unreadable config refused" "$rc" "1"
assert_eq "... left as it was" "$(cat "$CFG")" "{not json"
rm "$CFG" "$CFG.wb-backup"
"$MCP" connect >/dev/null 2>&1
assert_eq "connect: no config yet makes one" "$(python3 -c "import json; print(list(json.load(open('$CFG'))['mcpServers']))")" "['workbench']"
out="$("$MCP" check 2>&1)"
assert_contains "check: the spaces Desktop would see" "$out" "acme"
assert_not_contains "check: not another account's" "$out" "  work"
assert_contains "check: connected" "$out" "connected"
"$MCP" disconnect >/dev/null 2>&1
assert_eq "disconnect removes only workbench" "$(python3 -c "import json; print(json.load(open('$CFG')).get('mcpServers'))")" "{}"
finish
