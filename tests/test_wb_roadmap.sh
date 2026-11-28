#!/usr/bin/env bash
# wb-roadmap: the roadmap page's sync (spec: docs/specs/2026-11-27-roadmap-view-design.md)
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
RM="$REPO/bin/wb-roadmap"; FX="$REPO/tests/fixtures/groom"
ME=11111111-aaaa-4aaa-8aaa-000000000001     # made-up accounts: the session's persona
WORK=22222222-bbbb-4bbb-8bbb-000000000002   # and another one, on a space's own claude_config

mkdir -p "$T/home" "$T/work-cfg" "$T/plans" "$T/cfg"
export HOME="$T/home"
printf '{"oauthAccount":{"accountUuid":"%s"}}' "$ME" > "$HOME/.claude.json"
printf '{"oauthAccount":{"accountUuid":"%s"}}' "$WORK" > "$T/work-cfg/.claude.json"
cp -R "$FX/plan" "$T/plans/acme"
mkstore "$T/acme" "$T/other" "$T/work" "$T/broken"   # broken: a store bd lists nothing from
reset_stores() {
  cat > "$T/acme/.beads/fake.json" <<'EOF'
[{"id":"acme-1","title":"Plain","status":"open","priority":2,"issue_type":"task","labels":[],"updated_at":"2026-10-20T10:00:00Z","description":"why it matters"},
 {"id":"acme-2","title":"Money","status":"in_progress","priority":2,"issue_type":"task","labels":["ws:money"],"updated_at":"2026-10-20T10:00:00Z","assignee":"Someone Private"},
 {"id":"acme-3","title":"An epic","status":"open","priority":1,"issue_type":"epic","labels":[],"updated_at":"2026-10-20T10:00:00Z"},
 {"id":"acme-4","title":"Done","status":"closed","priority":2,"issue_type":"task","labels":[],"updated_at":"2026-10-20T10:00:00Z"},
 {"id":"acme-5","title":"Waits","status":"open","priority":2,"issue_type":"task","labels":[],"parent":"acme-3","updated_at":"2026-10-20T10:00:00Z",
  "dependencies":[{"issue_id":"acme-5","depends_on_id":"acme-1","type":"blocks"},{"issue_id":"acme-5","depends_on_id":"acme-3","type":"parent-child"},{"issue_id":"acme-5","depends_on_id":"acme-4","type":"blocks"}]}]
EOF
  printf '[{"id":"oth-1","title":"Other","status":"open","priority":2,"issue_type":"task","labels":[],"updated_at":"2026-10-20T10:00:00Z"}]' > "$T/other/.beads/fake.json"
  printf '[{"id":"wk-1","title":"Work secret","status":"open","priority":2,"issue_type":"task","labels":[]}]' > "$T/work/.beads/fake.json"
  rm -f "$T"/*/.beads/fake-clock
}
reset_stores
cat > "$T/cfg/spaces.toml" <<EOF
[[space]]
name = "acme"
root = "$T/acme"
[[space]]
name = "Other Things"
root = "$T/other"
[[space]]
name = "broken"
root = "$T/broken"
[[space]]
name = "work"
root = "$T/work"
claude_config = "$T/work-cfg"
EOF
export WORKBENCH_CONFIG="$T/cfg/spaces.toml" WB_PLANS_DIR="$T/plans" WB_TODAY=2026-10-23
export WB_ROADMAP_STATE="$T/state" FAKE_BD_STATEFUL=1
unset CLAUDE_CONFIG_DIR
field() { python3 -c "import json; b=[b for b in json.load(open('$T/$1/.beads/fake.json')) if b['id']=='$2']; print(b[0].get('$3', '') if b else 'NONE')"; }
doc() { python3 -c "import json,sys; d=json.load(open('$1')); print(eval(sys.argv[1]))" "$2"; }

# --- export ---
out="$("$RM" export "$T/out")"; rc=$?
assert_eq "export: exits 0" "$rc" "0"
assert_eq "export: one document per space of this account" "$(cd "$T/out/spaces" && ls | LC_ALL=C sort | tr '\n' ' ')" "Other-Things.json acme.json "
assert_contains "export: says which documents to write" "$out" '"acme"'
assert_contains "export: ... and the account they belong to" "$out" "$ME"
A="$T/out/spaces/acme.json"
assert_eq "export: the space's own name" "$(doc "$A" 'd["space"]')" "acme"
assert_eq "export: open beads only" "$(doc "$A" '" ".join(t["id"] for t in d["tasks"])')" "acme-1 acme-2 acme-3 acme-5"
assert_eq "export: the fields the page shows" "$(doc "$A" 'sorted(d["tasks"][0])')" \
  "['blocked_by', 'claimed', 'description', 'id', 'labels', 'parent', 'priority', 'protected', 'status', 'title', 'type', 'updated_at']"
assert_eq "export: a claim is a yes, never the claimant's name" "$(doc "$A" '[t["claimed"] for t in d["tasks"]]')" "[False, True, False, False]"
assert_not_contains "export: ... nowhere in the document" "$(cat "$A")" "Someone Private"
assert_eq "export: blocked by open blockers only, not the parent" "$(doc "$A" 'd["tasks"][3]["blocked_by"]')" "['acme-1']"
assert_eq "export: the protected beads marked" "$(doc "$A" '[t["id"] for t in d["tasks"] if t.get("protected")]')" "['acme-2']"
assert_contains "export: the plan state" "$(doc "$A" 'd["plan"]')" "ok"
assert_eq "export: a space without a plan says everything is protected" "$(doc "$T/out/spaces/Other-Things.json" 'd["protection"]')" \
  "no plan: every bead counts as protected"
assert_contains "export: a space bd can't read is skipped, saying why" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["skipped"])')" "'doc_id': 'broken'"
mv "$T/acme" "$T/acme.off"; mv "$T/other" "$T/other.off"
out="$("$RM" export "$T/out3" 2>&1)"; rc=$?
assert_eq "export: no space readable at all: refused" "$rc" "1"
mv "$T/acme.off" "$T/acme"; mv "$T/other.off" "$T/other"
"$RM" export "$T/out" >/dev/null
assert_eq "export: run again, the folder holds only this run's documents" "$(ls "$T/out/spaces" | wc -l | tr -d ' ')" "2"

python3 - "$T/acme/.beads/fake.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d[0]["description"] = "x" * 5000
json.dump(d, open(p, "w"))
PY
"$RM" export "$T/out" >/dev/null
assert_eq "export: a long description is cut short" "$(doc "$A" 'len(d["tasks"][0]["description"]) <= 1001')" "True"
reset_stores

CLAUDE_CONFIG_DIR="$T/work-cfg" "$RM" export "$T/out" >/dev/null
assert_eq "export: as the other account, only its spaces" "$(ls "$T/out/spaces" | tr '\n' ' ')" "work.json "
out="$(CLAUDE_CONFIG_DIR="$T/nobody" "$RM" export "$T/out2" 2>&1)"; rc=$?
assert_eq "export: the session's account unknown: refused" "$rc" "1"
assert_contains "... saying why" "$out" "account"
assert_eq "... writing nothing" "$(ls "$T/out2/spaces" 2>/dev/null | wc -l | tr -d ' ')" "0"

# --- apply ---
# edit ID JSON: one document as ArtifactData's out_dir saves it, <dir>/edits/<id>.json
E="$T/edits"
edit() { mkdir -p "$E/edits"; printf '%s' "$2" > "$E/edits/$1.json"; }
apply() { rm -rf "$E"; mkdir -p "$E"; while [ $# -gt 1 ]; do edit "$1" "$2"; shift 2; done; "$RM" apply "$E"; }
result() { python3 -c "import json,sys; r={x['edit']:x for x in json.load(sys.stdin)['results']}; x=r.get('$1'); print(x['status'] + ': ' + x['message'] if x else 'NONE')"; }

out="$(apply e1 '{"space":"acme","bead":"acme-1","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"title":"Plainer","priority":3},"at":"2026-10-23T09:00:00Z"}')"
assert_contains "apply: an edit on an unchanged bead is applied" "$(printf '%s' "$out" | result e1)" "applied: "
assert_eq "... title" "$(field acme acme-1 title)" "Plainer"
assert_eq "... priority" "$(field acme acme-1 priority)" "3"
out="$(apply e1 '{"space":"acme","bead":"acme-1","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"title":"Plainer","priority":3},"at":"2026-10-23T09:00:00Z"}')"
assert_contains "apply: the same edit again is not applied twice" "$(printf '%s' "$out" | result e1)" "applied: already applied"

out="$(apply e2 '{"space":"acme","bead":"acme-1","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"title":"Stale"},"at":"2026-10-23T09:05:00Z"}')"
assert_contains "apply: a bead changed on the Mac since: a conflict" "$(printf '%s' "$out" | result e2)" "conflict: "
assert_contains "... saying the Mac's version stays" "$(printf '%s' "$out" | result e2)" "changed"
assert_eq "... nothing written" "$(field acme acme-1 title)" "Plainer"

out="$(apply e3 '{"space":"acme","bead":"acme-1","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"append_notes":"from my phone"},"at":"2026-10-23T09:06:00Z"}')"
assert_contains "apply: a note is added even when the bead changed since" "$(printf '%s' "$out" | result e3)" "applied: "
assert_eq "... written" "$(field acme acme-1 notes)" "from my phone"

out="$(apply e4 '{"space":"acme","bead":"acme-2","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"priority":4},"at":"2026-10-23T09:07:00Z"}')"
assert_contains "apply: wb-mcp's rules hold: a protected bead isn't demoted" "$(printf '%s' "$out" | result e4)" "refused: "
assert_contains "... saying it is protected" "$(printf '%s' "$out" | result e4)" "protected"
assert_eq "... unchanged" "$(field acme acme-2 priority)" "2"

out="$(apply e5 '{"space":"acme","bead":"acme-4","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"append_notes":"x"},"at":"2026-10-23T09:08:00Z"}')"
assert_contains "apply: a closed bead is refused" "$(printf '%s' "$out" | result e5)" "refused: "
out="$(apply e6 '{"space":"acme","bead":"oth-1","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"title":"x"},"at":"2026-10-23T09:09:00Z"}')"
assert_contains "apply: a bead from another space is refused" "$(printf '%s' "$out" | result e6)" "refused: "
out="$(apply e7 '{"space":"work","bead":"wk-1","kind":"update","base":null,"changes":{"title":"x"},"at":"2026-10-23T09:10:00Z"}')"
assert_contains "apply: another account's space is refused" "$(printf '%s' "$out" | result e7)" "refused: "
assert_eq "... unchanged" "$(field work wk-1 title)" "Work secret"
out="$(apply e8 '{"space":"acme","bead":"acme-1","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"status":"closed"},"at":"2026-10-23T09:11:00Z"}')"
assert_contains "apply: a status change is refused (the terminal closes work)" "$(printf '%s' "$out" | result e8)" "refused: "
out="$(apply e9 '{"space":"acme","bead":"acme-1","kind":"update","changes":{"labels":["wave:1"]},"at":"2026-10-23T09:12:00Z"}')"
assert_contains "apply: labels can't be edited from the page" "$(printf '%s' "$out" | result e9)" "refused: "
out="$(apply e10 'not json')"
assert_contains "apply: a document that isn't JSON is refused" "$(printf '%s' "$out" | result e10)" "refused: "
out="$(apply e11 '{"space":"acme","bead":"acme-1","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"priority":"high"},"at":"2026-10-23T09:13:00Z"}')"
assert_contains "apply: a bad priority is refused" "$(printf '%s' "$out" | result e11)" "refused: "

out="$(apply e12 '{"space":"acme","kind":"create","changes":{"title":"New from the page","description":"seen on the train","priority":1,"parent":"acme-3"},"at":"2026-10-23T09:14:00Z"}')"
assert_contains "apply: a new task is created" "$(printf '%s' "$out" | result e12)" "applied: Created acme-3.2"
assert_eq "... under its epic" "$(field acme acme-3.2 parent)" "acme-3"
out="$(apply e13 '{"space":"acme","kind":"create","changes":{"title":""},"at":"2026-10-23T09:15:00Z"}')"
assert_contains "apply: a new task needs a title" "$(printf '%s' "$out" | result e13)" "refused: "

# ArtifactData can save a document with its body under "data", beside its version
out="$(apply e14 '{"version":3,"data":{"space":"acme","bead":"acme-3","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"append_notes":"wrapped"},"at":"2026-10-23T09:16:00Z"}}')"
assert_contains "apply: a document saved with its version around it" "$(printf '%s' "$out" | result e14)" "applied: "

out="$(apply b '{"space":"acme","bead":"acme-3","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"append_notes":"second"},"at":"2026-10-23T10:00:00Z"}' \
             a '{"space":"acme","bead":"acme-3","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"append_notes":"first"},"at":"2026-10-23T09:59:00Z"}')"
assert_eq "apply: edits go in the order they were made" "$(field acme acme-3 notes | tr '\n' '|')" "wrapped|first|second|"
reset_stores; rm -rf "$T/state"
out="$(apply s1 '{"space":"acme","bead":"acme-1","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"append_notes":"note first"},"at":"2026-10-23T11:00:00Z"}' \
             s2 '{"space":"acme","bead":"acme-1","kind":"update","base":"2026-10-20T10:00:00+00:00","changes":{"priority":1},"at":"2026-10-23T11:01:00Z"}')"
assert_contains "apply: two changes queued on one bead both apply (the first doesn't make the second a conflict)" "$(printf '%s' "$out" | result s2)" "applied: "
assert_eq "... the priority" "$(field acme acme-1 priority)" "1"
out="$(apply s3 '{"space":"acme","bead":"acme-1","kind":"update","base":"2026-10-20T10:00:00Z","changes":{"priority":4},"at":"2026-10-23T11:02:00Z"}')"
assert_contains "apply: ... but in a later sync that base is out of date: a conflict" "$(printf '%s' "$out" | result s3)" "conflict: "
out="$(apply r1 '{"space":"acme","bead":"acme-1","kind":"update","base":"old","changes":{"title":"x"},"status":"conflict","reason":"r","at":"2026-10-23T10:01:00Z"}')"
assert_eq "apply: an edit already reported back is left alone until it's dismissed" "$out" '{"results": []}'
assert_eq "apply: no edits folder is no edits" "$(rm -rf "$E"; mkdir -p "$E"; "$RM" apply "$E")" '{"results": []}'

out="$(CLAUDE_CONFIG_DIR="$T/nobody" "$RM" apply "$E" 2>&1)"; rc=$?
assert_eq "apply: the session's account unknown: refused" "$rc" "1"

# --- url ---
assert_eq "url: none yet" "$("$RM" url; echo "rc=$?")" "rc=1"
"$RM" url https://claude.ai/artifact/abc123 >/dev/null
assert_eq "url: remembered for this account" "$("$RM" url)" "https://claude.ai/artifact/abc123"
assert_eq "url: not for another account" "$(CLAUDE_CONFIG_DIR="$T/work-cfg" "$RM" url; echo "rc=$?")" "rc=1"
assert_contains "url: only a claude.ai artifact link" "$("$RM" url https://example.com/x 2>&1; echo "rc=$?")" "rc=2"

# --- sync: starts a Claude session with the sync prompt, on the chosen space's account ---
export FAKE_CLAUDE_LOG="$T/claude.log"
out="$("$RM" sync)"
assert_contains "sync: starts Claude" "$out" "FAKE-CLAUDE"
assert_contains "sync: with the sync prompt" "$out" "wb-roadmap export"
assert_contains "sync: naming the saved page" "$out" "https://claude.ai/artifact/abc123"
"$RM" sync work >/dev/null
assert_eq "sync SPACE: on that space's account" "$(tail -1 "$T/claude.log" | python3 -c 'import json,sys; print(json.load(sys.stdin)["config"])')" "$T/work-cfg"
assert_contains "sync SPACE: ... with no page yet, the prompt says to publish one" "$(tail -1 "$T/claude.log")" "no roadmap page yet"
assert_contains "sync: an unknown space is refused" "$("$RM" sync nope 2>&1; echo "rc=$?")" "rc=2"

finish
