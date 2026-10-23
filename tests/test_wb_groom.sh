#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
WG="$REPO/bin/wb-groom"; FX="$REPO/tests/fixtures/groom"
mkstore "$T/store"; cp "$FX/beads.json" "$T/store/.beads/fake.json"
export WB_TODAY=2026-10-23
RUN="$T/run"; mkdir -p "$RUN"
# ops JSON: print the CLI's stdout for a decisions.json given as $1 (default: the plan fixture)
ops() { printf '%s' "$1" > "$RUN/decisions.json"; "$WG" ops "$RUN" "$T/store" --plan "${2:-$FX/plan}" 2>"$T/err"; }

# --- the plan ---
PL="$REPO/lib"
py() { PYTHONPATH="$PL" python3 -c "import datetime, wb_groom as g; $1"; }
assert_eq "plan: date, sizes and protected labels" \
  "$(py "p = g.read_plan('$FX/plan'); print(p.goals_date, p.now_size, p.next_size, sorted(p.protected_labels))")" \
  "2026-10-10 2 2 ['customer', 'ws:money']"
mkdir -p "$T/p2"; printf 'no date here\n' > "$T/p2/goals.md"
assert_eq "plan: defaults for sizes; no date is missing" \
  "$(py "p = g.read_plan('$T/p2'); d = datetime.date(2026,10,23); print(p.now_size, p.next_size, g.plan_state(p, d))")" "5 8 missing"
assert_eq "plan: no directory is None, state missing" \
  "$(py "d = datetime.date(2026,10,23); print(g.read_plan('$T/none'), g.plan_state(None, d))")" "None missing"
assert_eq "plan_state: ok, due (30), stale (46)" \
  "$(py "p = g.read_plan('$FX/plan'); print(*(g.plan_state(p, datetime.date(2026,10,10) + datetime.timedelta(days=n)) for n in (29, 30, 45, 46)))")" \
  "ok due due stale"
assert_eq "load_plan reads WB_PLANS_DIR/<space>" \
  "$(WB_PLANS_DIR="$T/plans" py "import os; os.makedirs('$T/plans', exist_ok=True); print(g.load_plan('acme'))"; mkdir -p "$T/plans"; cp -R "$FX/plan" "$T/plans/acme"; WB_PLANS_DIR="$T/plans" py "print(g.load_plan('acme').now_size)")" "None
2"

# --- is_protected ---
assert_eq "protected: by label even when the judge says no" \
  "$(py "p = g.read_plan('$FX/plan'); print(g.is_protected({'labels': ['ws:money']}, False, p))")" "True"
assert_eq "protected: judge unsure" \
  "$(py "p = g.read_plan('$FX/plan'); print(g.is_protected({'labels': []}, None, p))")" "True"
assert_eq "protected: judge says true" \
  "$(py "print(g.is_protected({'labels': []}, True, None))")" "True"
assert_eq "unprotected only when the judge says false and no label" \
  "$(py "p = g.read_plan('$FX/plan'); print(g.is_protected({'labels': ['x']}, False, p))")" "False"

# --- sprint ---
out="$(ops '{"sprint":{"now":[{"id":"acme-1","why":"g1"},{"id":"acme-7","why":"money"},{"id":"acme-9","why":"x"},{"id":"acme-3","why":"x"},{"id":"acme-99","why":"x"}],
 "next":[{"id":"acme-8","why":"later"},{"id":"acme-6","why":"same"}],
 "leaving":[{"id":"acme-4","why":"no goal","protected":false}]}}')"; rc=$?
assert_eq "ops exits 0" "$rc" "0"
assert_contains "sprint: add an unprotected bead to NOW" "$out" $'acme-1\twave\twave:1\tNOW: g1'
assert_contains "sprint: a protected bead moving NEXT to NOW is applied" "$out" $'acme-7\twave\twave:1\t'
ops_only() { printf '%s\n' "$1" | grep -v '^proposal\|^dropped'; }
assert_contains "sprint: leaving with protected:false is an unwave op, with the leaving why" "$(ops_only "$out")" $'acme-4\tunwave\twave:1\tno goal'
assert_contains "sprint: unwave of a protected bead is a proposal" "$out" $'proposal\tacme-5\tunwave\twave:1\t'
assert_not_contains "sprint: ... and not an op" "$(ops_only "$out")" $'acme-5\tunwave'
assert_contains "sprint: protected NOW to NEXT is a proposal" "$out" $'proposal\tacme-8\twave\twave:2\tlater\tprotected'
assert_not_contains "sprint: already in the named wave: no op" "$out" "acme-6"$'\twave'
assert_contains "sprint: past size is dropped" "$out" $'dropped\tacme-9: over size'
assert_contains "sprint: claimed is dropped" "$out" $'dropped\tacme-3: claimed'
assert_contains "sprint: unknown id is dropped" "$out" $'dropped\tacme-99: unknown id'
out2="$(ops '{"sprint":{"now":[]},"changes":[{"id":"acme-4","kind":"priority","to":"3","why":"p","protected":null}]}')"
assert_contains "sprint: a leaving bead the judge called unsure is a proposal" "$out2" $'proposal\tacme-4\tunwave'
out2="$(ops '{"sprint":{"now":[]}}')"
assert_contains "sprint: leaving with no verdict at all is a proposal" "$out2" $'proposal\tacme-4\tunwave\twave:1\tleft the sprint\tprotected'
assert_not_contains "sprint: ... not an op" "$(ops_only "$out2")" "acme-4"
out2="$(ops '{"sprint":{"now":[],"leaving":[{"id":"acme-4","why":"w","protected":false}]},"changes":[{"id":"acme-4","kind":"bogus","protected":false},{"id":"acme-4","kind":"priority","to":"3","why":"p","protected":true}]}')"
assert_contains "sprint: a protected:true change vetoes the leaving verdict" "$out2" $'proposal\tacme-4\tunwave'
out2="$(ops '{"sprint":{"now":[]},"changes":[{"id":"acme-4","kind":"bogus","protected":false}]}')"
assert_contains "sprint: a verdict from an invalid change does not count" "$out2" $'proposal\tacme-4\tunwave'
out2="$(ops '{"sprint":{"next":[{"id":"acme-4","why":"slip","protected":false}]}}')"
assert_contains "sprint: NOW to NEXT with protected:false is applied" "$(ops_only "$out2")" $'acme-4\twave\twave:2\tNEXT: slip'
out2="$(ops '{"sprint":{"next":[{"id":"acme-4","why":"slip"}]}}')"
assert_contains "sprint: NOW to NEXT with no verdict is a proposal" "$out2" $'proposal\tacme-4\twave\twave:2\tslip\tprotected'
out2="$(ops '{"sprint":{"now":[{"id":"acme-3","why":"x"},{"id":"acme-1","why":"a"},{"id":"acme-9","why":"b"}]}}')"
assert_contains "sprint: a claimed bead doesn't use up a NOW slot (1)" "$(ops_only "$out2")" $'acme-1\twave'
assert_contains "sprint: a claimed bead doesn't use up a NOW slot (2)" "$(ops_only "$out2")" $'acme-9\twave'
assert_not_contains "sprint: ... so nothing is over size" "$out2" "over size"
out2="$(ops '{"sprint":{"now":[{"id":"acme-1","why":"a","protected":"yes"}],"next":[{"id":"acme-6","why":"n"}]}}')"
assert_contains "sprint: wrong-typed protected drops that section" "$out2" $'dropped\tsprint.now: bad field now'
out2="$(ops '{"sprint":{"leaving":"acme-4"}}')"
assert_contains "sprint: wrong-typed leaving is dropped" "$out2" $'dropped\tsprint.leaving: bad field leaving'
out2="$(ops '{"changes":[{"id":"acme-1","kind":["icebox"],"why":"c"},{"id":"acme-10","kind":{"a":1}},{"id":"acme-9","kind":"priority","to":"1","why":"p"}]}')"; rc=$?
assert_eq "unhashable kind: exit 0" "$rc" "0"
assert_contains "unhashable kind: dropped" "$out2" $'dropped\tacme-1: bad field kind'
assert_contains "unhashable kind: the rest is kept" "$out2" $'proposal\tacme-9\tpriority'
assert_not_contains "sprint: a claimed bead's wave is never unwaved" "$out" $'acme-3\tunwave'

# --- changes ---
out="$(ops '{"changes":[
 {"id":"acme-10","kind":"icebox","why":"no goal","protected":false},
 {"id":"acme-11","kind":"icebox","why":"unsure","protected":null},
 {"id":"acme-2","kind":"icebox","why":"label wins","protected":false},
 {"id":"acme-9","kind":"priority","to":"1","why":"p","protected":false},
 {"id":"acme-1","kind":"close","why":"c","protected":false},
 {"id":"acme-12","kind":"icebox","why":"again","protected":false},
 {"id":"acme-3","kind":"icebox","why":"c","protected":false},
 {"id":"acme-1","kind":"frobnicate","why":"c"},
 {"id":"acme-1","kind":"icebox","why":"c","protected":"no"}]}')"
assert_contains "icebox: unprotected is applied" "$out" $'acme-10\ticebox\ticebox\tno goal'
assert_contains "icebox: judge unsure is a proposal" "$out" $'proposal\tacme-11\ticebox\t\tunsure\tprotected'
assert_contains "icebox: protected label is a proposal" "$out" $'proposal\tacme-2\ticebox\t\tlabel wins\tprotected'
assert_not_contains "icebox: protected is not an op" "$out" $'acme-2\ticebox\ticebox'
assert_contains "priority is always a proposal" "$out" $'proposal\tacme-9\tpriority\t1\tp\talways proposed'
assert_contains "close is always a proposal, even unprotected" "$out" $'proposal\tacme-1\tclose\t'
assert_not_contains "icebox of an iceboxed bead: nothing" "$out" "acme-12"
assert_contains "claimed: any change is dropped" "$out" $'dropped\tacme-3: claimed'
assert_contains "bad kind is dropped" "$out" $'dropped\tacme-1: bad field kind'
assert_contains "wrong-typed protected is dropped" "$out" $'dropped\tacme-1: bad field protected'

# --- attention ---
out="$(ops '{"attention":{"add":[{"id":"acme-9","why":"due in 5 days"},{"id":"acme-13","why":"already"}],"remove":[{"id":"acme-13","why":"done"},{"id":"acme-1","why":"never had it"}]}}')"
assert_contains "attention add is an op" "$out" $'acme-9\tattention\tattention\tdue in 5 days'
assert_contains "attention remove is an op" "$out" $'acme-13\tunattention\tattention\tdone'
assert_not_contains "attention add on a flagged bead: no op" "$out" $'acme-13\tattention'
assert_not_contains "attention remove on an unflagged bead: no op" "$out" "acme-1"$'\t'

# --- plan state ---
D='{"sprint":{"now":[{"id":"acme-1","why":"g"}]},"changes":[{"id":"acme-10","kind":"icebox","why":"i","protected":false}],"attention":{"add":[{"id":"acme-9","why":"d"}]}}'
mkdir -p "$T/stale"; printf 'date: 2026-08-01\n' > "$T/stale/goals.md"; cp "$FX/plan/protected.md" "$T/stale/"
out="$(ops "$D" "$T/stale")"
assert_eq "stale plan: every line is a proposal or dropped" "$(printf '%s\n' "$out" | grep -vc '^proposal')" "0"
assert_contains "stale plan: the reason" "$out" $'proposal\tacme-1\twave\twave:1\tNOW: g\tplan stale'
assert_eq "stale plan: sprint, changes, attention proposals in that order" \
  "$(printf '%s\n' "$out" | grep '^proposal' | cut -f2 | tr '\n' ' ')" "acme-1 acme-4 acme-5 acme-8 acme-10 acme-9 "
out="$(ops "$D" "$T/none")"
assert_contains "missing plan: proposals too" "$out" $'proposal\tacme-10\ticebox\ticebox\ti\tplan missing'
out="$("$WG" ops "$RUN" "$T/store")"
assert_contains "no --plan means a missing plan" "$out" $'plan missing'

mkdir -p "$T/noprot"; cp "$FX/plan/goals.md" "$T/noprot/"
assert_eq "plan without protected.md is missing, though goals.md is fresh" \
  "$(py "p = g.read_plan('$T/noprot'); print(g.plan_state(p, datetime.date(2026,10,23)))")" "missing"
out="$(ops "$D" "$T/noprot")"
assert_contains "... so everything is proposed" "$out" $'proposal\tacme-10\ticebox\ticebox\ti\tplan missing'
mkdir -p "$T/two"; cp "$FX/plan/goals.md" "$T/two/"; printf 'labels: a\n\nmore:\nlabels: b, c\n' > "$T/two/protected.md"
assert_eq "protected.md: every labels: line counts" \
  "$(py "print(sorted(g.read_plan('$T/two').protected_labels))")" "['a', 'b', 'c']"

# --- malformed input ---
printf '{"sprint": ' > "$RUN/decisions.json"
out="$("$WG" ops "$RUN" "$T/store" --plan "$FX/plan" 2>"$T/err")"; rc=$?
assert_eq "malformed decisions.json: exit 3" "$rc" "3"
assert_contains "... says so on stderr" "$(cat "$T/err")" "decisions.json unreadable"
assert_eq "... and prints nothing" "$out" ""
printf '[1]' > "$RUN/decisions.json"; "$WG" ops "$RUN" "$T/store" --plan "$FX/plan" >/dev/null 2>&1
assert_eq "decisions.json not an object: exit 3" "$?" "3"
rm "$RUN/decisions.json"; "$WG" ops "$RUN" "$T/store" >/dev/null 2>&1
assert_eq "missing decisions.json: exit 3" "$?" "3"

out="$(ops '{"sprint":{"now":"acme-1","next":[{"id":"acme-1","why":"n"}]},"changes":[{"id":"acme-10","kind":"icebox","why":"i","protected":false}]}')"
assert_contains "wrong-typed section is dropped" "$out" $'dropped\tsprint.now: bad field now'
assert_contains "... and the rest is kept (next)" "$out" $'acme-1\twave\twave:2\t'
assert_contains "... and the rest is kept (changes)" "$out" $'acme-10\ticebox'
assert_not_contains "... and an unreadable NOW list unwaves nothing" "$out" $'acme-4\tunwave'

# --- bd failures fail closed ---
printf '{}' > "$RUN/decisions.json"
FAKE_BD_DIR="$T/bd" ; mkdir -p "$T/bd"; echo 1 > "$T/bd/rc"; echo "boom" > "$T/bd/stderr"
out="$(FAKE_BD_DIR="$T/bd" "$WG" ops "$RUN" "$T/store" --plan "$FX/plan" 2>"$T/err")"; rc=$?
assert_eq "bd failure: exit 4" "$rc" "4"
assert_contains "bd failure: message" "$(cat "$T/err")" "bd list exited 1"
assert_eq "bd failure: no stdout" "$out" ""
echo "not json" > "$T/bd/stdout"; echo 0 > "$T/bd/rc"; rm "$T/bd/stderr"
FAKE_BD_DIR="$T/bd" "$WG" ops "$RUN" "$T/store" >/dev/null 2>&1
assert_eq "bd output that is not a bead list: exit 4" "$?" "4"

# --- apply and undo ---
# A fresh store and run dir per case; fakes write for real (FAKE_BD_STATEFUL) and log every call.
fresh() {
  chmod -R u+w "$T/r" 2>/dev/null; rm -rf "$T/s" "$T/r"; mkstore "$T/s"; mkdir -p "$T/r"
  python3 - "$FX/beads.json" "$T/s/.beads/fake.json" <<'PY'
import json, sys
b = json.load(open(sys.argv[1]))
for x in b: x["updated_at"] = "2026-10-01T00:00:00Z"
b[3]["notes"] = "kept from before"
json.dump(b, open(sys.argv[2], "w"))
PY
  : > "$T/bd.log"; : > "$T/argv.log"
}
bead() { python3 -c "import json,sys; print(json.dumps([b for b in json.load(open('$T/s/.beads/fake.json')) if b['id']=='$1'][0], sort_keys=True))"; }
field() { bead "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$2', ''))"; }
# chk: checks too long for $(…) with a heredoc, which bash 3.2 misparses
cat > "$T/chk.py" <<'PY'
import json, sys
if sys.argv[1] == "applied":
    t = sys.argv[2]
    live = {b["id"]: b for b in json.load(open(t + "/s/.beads/fake.json"))}
    rec = [json.loads(l) for l in open(t + "/r/applied.jsonl")]
    print(len(rec) == 3 and all(r["updated_at"] == live[r["id"]]["updated_at"] != "2026-10-01T00:00:00Z" for r in rec))
else:
    calls = [json.loads(l) for l in open(sys.argv[2])]
    u = [c for c in calls if "update" in c and "acme-9" in c][0]
    note = u[u.index("--append-notes") + 1]
    print(sum("$(touch" in a for a in u), "\nsecond line" in note, "second line; touch" in note)
PY
chk() { python3 "$T/chk.py" "$1" "$2"; }
export FAKE_BD_STATEFUL=1 FAKE_BD_LOG="$T/bd.log" FAKE_BD_ARGV_LOG="$T/argv.log"
apply() { "$WG" apply "$T/r" "$T/s" --plan "$FX/plan" "$@"; }
undo() { "$WG" undo "$T/r" "$@"; }
HOSTILE=$'due soon $(touch '"$T"$'/pwned) `touch '"$T"$'/pwned2`\nsecond line; touch '"$T"$'/pwned3'
python3 - "$T/D.json" "$HOSTILE" <<'PY'
import json, sys
json.dump({"sprint": {"next": [{"id": "acme-4", "why": "slip", "protected": False}]},
 "changes": [{"id": "acme-10", "kind": "icebox", "why": "no goal", "protected": False},
             {"id": "acme-9", "kind": "priority", "to": "1", "why": "p"},
             {"id": "acme-11", "kind": "icebox", "why": "unsure"},
             {"id": "acme-1", "kind": "close", "why": "done", "protected": False},
             {"id": "acme-10", "kind": "merge", "to": "acme-9", "why": "dup"}],
 "attention": {"add": [{"id": "acme-9", "why": sys.argv[2]}]}}, open(sys.argv[1], "w"))
PY
fresh; cp "$T/D.json" "$T/r/decisions.json"
FAKE_BD_REQUIRE_FILE="$T/r/before.jsonl" apply >"$T/out" 2>"$T/err"; rc=$?
assert_eq "apply: exit 0 (before.jsonl existed, non-empty, at the first write)" "$rc" "0"
assert_eq "apply: every write has --sandbox" "$(grep -E '(^| )(update|close|undefer) ' "$T/bd.log" | grep -vc '^--sandbox ')" "0"
assert_eq "apply: wave move adds wave:2, removes wave:1" "$(field acme-4 labels)" "['wave:2']"
assert_eq "apply: icebox adds the label" "$(field acme-10 labels)" "['icebox']"
assert_contains "apply: the groomed note names the date, kind and why" "$(field acme-4 notes)" "groomed 2026-10-23: wave — NEXT: slip"
assert_contains "apply: ... after the notes it already had" "$(field acme-4 notes)" "kept from before"
assert_contains "apply: an attention op also notes attention:" "$(field acme-9 notes)" "attention: due soon"
assert_eq "apply: only the op beads were written" "$(grep -E '(^| )update ' "$T/bd.log" | awk '{print $3}' | sort | tr '\n' ' ')" "acme-10 acme-4 acme-9 "
assert_eq "apply: one update call per bead" "$(grep -cE '(^| )update ' "$T/bd.log")" "3"
assert_eq "apply: before.jsonl has one line per touched bead" "$(wc -l < "$T/r/before.jsonl" | tr -d ' ')" "3"
assert_eq "apply: before.jsonl keeps the notes and updated_at from before" \
  "$(python3 -c "import json; r=[json.loads(l) for l in open('$T/r/before.jsonl')]; b=[x for x in r if x['id']=='acme-4'][0]; print(b['labels'], b['priority'], b['status'], b['notes'], b['updated_at'])")" \
  "['wave:1'] 2 open kept from before 2026-10-01T00:00:00Z"
assert_eq "apply: applied.jsonl stores each bead's updated_at read back after the writes" "$(chk applied "$T")" "True"
assert_eq "apply: proposals.json holds the proposals, in order" \
  "$(python3 -c "import json; print([(p['id'], p['kind']) for p in json.load(open('$T/r/proposals.json'))])")" \
  "[('acme-6', 'unwave'), ('acme-7', 'unwave'), ('acme-9', 'priority'), ('acme-11', 'icebox'), ('acme-1', 'close'), ('acme-10', 'merge')]"
assert_eq "hostile why: nothing executed" "$(ls "$T" | grep -c '^pwned')" "0"
assert_eq "hostile why: one argv element, newline-free, behind --append-notes" "$(chk argv "$T/argv.log")" "1 False True"
assert_eq "apply: argv starts bd --sandbox update ID" "$(python3 -c "import json; print([json.loads(l) for l in open('$T/argv.log') if 'acme-9' in l and 'update' in l][0][:3])")" "['--sandbox', 'update', 'acme-9']"
assert_contains "apply: summary line on stdout" "$(cat "$T/out")" "applied 3"
apply >/dev/null 2>"$T/err"; assert_eq "apply: a second full apply of a run is refused" "$?" "7"
assert_contains "... and says why" "$(cat "$T/err")" "already applied"

# undo
undo >"$T/out" 2>"$T/err"; rc=$?
assert_eq "undo: exit 0" "$rc" "0"
assert_eq "undo: labels restored" "$(field acme-4 labels)" "['wave:1']"
assert_eq "undo: labels restored to empty" "$(field acme-10 labels)" "[]"
assert_eq "undo: notes restored exactly, no note appended" "$(field acme-4 notes)" "kept from before"
assert_eq "undo: notes restored to none" "$(field acme-9 notes)" ""
assert_eq "undo: appends no note anywhere" "$(grep -c 'groomed undo' "$T/s/.beads/fake.json")" "0"
assert_eq "undo: writes pass --sandbox" "$(grep -E '(^| )update ' "$T/bd.log" | grep -vc '^--sandbox ')" "0"
assert_eq "undo: undone.jsonl records the three beads" "$(wc -l < "$T/r/undone.jsonl" | tr -d ' ')" "3"
out="$(undo 2>&1)"; rc=$?
assert_eq "undo: idempotent, exit 0" "$rc" "0"
assert_contains "undo: names an already-undone bead" "$out" "acme-4: already undone"
assert_eq "undo: ... and writes nothing more" "$(grep -cE '(^| )update ' "$T/bd.log")" "6"

# undo refuses what changed
fresh; printf '%s' '{"changes":[{"id":"acme-10","kind":"icebox","why":"w","protected":false}]}' > "$T/r/decisions.json"
apply >/dev/null 2>&1
python3 - "$T/s/.beads/fake.json" <<'PY'
import json, sys
p = sys.argv[1]; b = json.load(open(p))
for x in b:
    if x["id"] == "acme-10": x["priority"], x["updated_at"] = 0, "2026-10-23T13:00:00Z"
json.dump(b, open(p, "w"))
PY
out="$(undo acme-10 2>&1)"; rc=$?
assert_eq "undo: a bead changed after the run is refused" "$rc" "8"
assert_contains "undo: ... naming it" "$out" "acme-10 changed since the run; not undone"
assert_eq "undo: ... and left alone" "$(field acme-10 labels)" "['icebox']"
fresh; printf '%s' '{"changes":[{"id":"acme-10","kind":"icebox","why":"w","protected":false}]}' > "$T/r/decisions.json"
apply >/dev/null 2>&1
python3 - "$T/s/.beads/fake.json" <<'PY'
import json, sys
p = sys.argv[1]; b = json.load(open(p))
for x in b:
    if x["id"] == "acme-10": x["labels"].append("sneaky")   # same updated_at: the state check still sees it
json.dump(b, open(p, "w"))
PY
undo acme-10 >/dev/null 2>&1; assert_eq "undo: a changed label set is refused even when updated_at matches" "$?" "8"
undo acme-1 >"$T/out" 2>&1; rc=$?
assert_eq "undo: a bead not in the run: skipped, non-zero" "$rc" "8"
assert_contains "undo: ... says so" "$(cat "$T/out")" "acme-1: not in this run"

# proposals, then undo of priority, status and labels
fresh; cp "$T/D.json" "$T/r/decisions.json"; apply >/dev/null 2>&1
ix() { python3 -c "import json; print([i+1 for i,p in enumerate(json.load(open('$T/r/proposals.json'))) if p['kind']=='$1'][0])"; }
PRI=$(ix priority); CLO=$(ix close); MER=$(ix merge); ICE=$(ix icebox)
apply --proposal "$PRI" >"$T/out" 2>&1; rc=$?
assert_eq "proposal: priority applies, exit 0" "$rc" "0"
assert_eq "proposal: the bead has the priority" "$(field acme-9 priority)" "1"
assert_eq "proposal: only that bead was written" "$(field acme-1 status)" "open"
apply --proposal "$PRI" >/dev/null 2>"$T/err"; assert_eq "proposal: the same one twice is refused" "$?" "7"
assert_contains "proposal: ... says so" "$(cat "$T/err")" "already applied"
apply --proposal "$MER" >/dev/null 2>"$T/err"; assert_eq "proposal: merge is not applied, non-zero" "$?" "7"
assert_contains "proposal: merge is by hand" "$(cat "$T/err")" "proposal $MER (merge) is applied by hand in review"
apply --proposal 99 >/dev/null 2>&1; assert_eq "proposal: no such number is refused" "$?" "7"
apply --proposal "$CLO" >/dev/null 2>&1
assert_eq "proposal: close sets the status" "$(field acme-1 status)" "closed"
assert_contains "proposal: close passes --reason" "$(grep -E '(^| )close ' "$T/bd.log")" "--reason=done"
apply --proposal "$ICE" >/dev/null 2>&1
assert_eq "proposal: icebox applies" "$(field acme-11 labels)" "['icebox']"
undo >"$T/out" 2>&1; rc=$?
assert_eq "undo after proposals: exit 0" "$rc" "0"
assert_eq "undo: priority back" "$(field acme-9 priority)" "2"
assert_eq "undo: status back" "$(field acme-1 status)" "open"
assert_eq "undo: proposal icebox back" "$(field acme-11 labels)" "[]"
assert_eq "undo: a bead touched twice goes back to its first before-state" "$(field acme-9 labels)" "[]"

# failures
fresh; cp "$T/D.json" "$T/r/decisions.json"
FAKE_BD_UPDATE_FAIL_ID=acme-9 apply >"$T/out" 2>"$T/err"; rc=$?
assert_eq "apply: a failing write stops the run, exit 5" "$rc" "5"
assert_contains "apply: ... naming the bead" "$(cat "$T/err")" "acme-9"
assert_eq "apply: ... earlier beads stay applied and recorded, and so does the failed one, with its error" \
  "$(python3 -c "import json; print([(r['id'], 'error' in r) for r in map(json.loads, open('$T/r/applied.jsonl'))])")" \
  "[('acme-4', False), ('acme-10', False), ('acme-9', True)]"
assert_eq "apply: ... before.jsonl covers every bead the run might touch" "$(wc -l < "$T/r/before.jsonl" | tr -d ' ')" "3"
n=$(grep -cE '(^| )update ' "$T/bd.log")
out="$(undo 2>&1)"; rc=$?
assert_eq "undo after a failed run: exit 0" "$rc" "0"
assert_eq "undo after a failed run: the applied beads are restored" "$(field acme-4 labels)" "['wave:1']"
assert_eq "undo: the bead whose write failed needed no write" "$(grep -cE '(^| )update ' "$T/bd.log")" "$((n + 2))"
fresh; cp "$T/D.json" "$T/r/decisions.json"
FAKE_BD_UPDATE_FAIL_ID=acme-4 apply >/dev/null 2>&1
assert_contains "undo: a bead the run never reached is skipped" "$(undo 2>&1)" "acme-10: not applied"
fresh; cp "$T/D.json" "$T/r/decisions.json"; chmod 555 "$T/r"
if [ "$(id -u)" != 0 ]; then
  apply >/dev/null 2>"$T/err"; rc=$?
  assert_eq "apply: unwritable run dir: exit 6" "$rc" "6"
  assert_eq "apply: ... nothing applied" "$(grep -cE '(^| )(update|close) ' "$T/bd.log")" "0"
fi
chmod 755 "$T/r"
fresh; printf '{}' > "$T/r/decisions.json"; apply --proposal 1 >/dev/null 2>&1
assert_eq "apply --proposal with no such proposal: refused" "$?" "7"
fresh; printf '{' > "$T/r/decisions.json"; apply >/dev/null 2>&1
assert_eq "apply: unreadable decisions: exit 3" "$?" "3"
assert_eq "... nothing applied" "$(grep -cE '(^| )update ' "$T/bd.log")" "0"
unset FAKE_BD_STATEFUL FAKE_BD_LOG FAKE_BD_ARGV_LOG

finish
