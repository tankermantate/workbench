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
# a stale claim on something due must still reach start-here: attention is the one thing
# grooming may change on a claimed bead
out="$(ops '{"attention":{"add":[{"id":"acme-3","why":"stale claim · due Nov 2"}]},"changes":[{"id":"acme-3","kind":"icebox","why":"x","protected":false}]}')"
assert_contains "attention add on a claimed bead is an op" "$out" $'acme-3\tattention\tattention\tstale claim · due Nov 2'
assert_contains "... but any other change to it is still dropped" "$out" $'dropped\tacme-3: claimed'
out="$(ops '{"attention":{"add":[{"id":"acme-3","why":"due"}]}}' "$T/none")"
assert_contains "attention on a claimed bead, plan missing: a proposal" "$out" $'proposal\tacme-3\tattention\tattention\tdue\tplan missing'

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
elif sys.argv[1] == "close":
    c = [c for c in map(json.loads, open(sys.argv[2])) if "close" in c][0]
    r = [a for a in c if "$(touch" in a]
    print(len(r), r[0].startswith("--reason="), "\n" in r[0])
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

# --- fix round 1 ---
# edit ID KEY VALUE(JSON): a human editing a bead behind the run's back
edit() { python3 - "$T/s/.beads/fake.json" "$1" "$2" "$3" <<'PY'
import json, sys
p, id, k, v = sys.argv[1:]
b = json.load(open(p))
for x in b:
    if x["id"] == id:
        x[k] = json.loads(v); x["updated_at"] = "2026-10-23T13:30:00Z"
json.dump(b, open(p, "w"))
PY
}
addbead() { python3 - "$T/s/.beads/fake.json" "$1" <<'PY'
import json, sys
p = sys.argv[1]; b = json.load(open(p)); b.append(json.loads(sys.argv[2])); json.dump(b, open(p, "w"))
PY
}
pnum() { python3 -c "import json; print([i+1 for i,p in enumerate(json.load(open('$T/r/proposals.json'))) if p['kind']=='$1'][0])"; }
nwrites() { grep -cE '(^| )(update|close|undefer) ' "$T/bd.log"; }

# I1: a write that can't be recorded is reported as written, not as "nothing applied"
fresh; cp "$T/D.json" "$T/r/decisions.json"; : > "$T/r/applied.jsonl"; chmod 444 "$T/r/applied.jsonl"
if [ "$(id -u)" != 0 ]; then
  apply >"$T/out" 2>"$T/err"; rc=$?
  assert_eq "unrecordable write: exit 5, not 6" "$rc" "5"
  assert_contains "... says the bead was written but not recorded" "$(cat "$T/err")" "acme-4"
  assert_contains "... " "$(cat "$T/err")" "written but not recorded"
  assert_not_contains "... and does not claim nothing was applied" "$(cat "$T/err")" "nothing applied"
  assert_contains "... and prints the manual restore argv" "$(cat "$T/err")" "--sandbox update acme-4"
  assert_contains "... restoring the wave label" "$(cat "$T/err")" "--add-label wave:1"
  assert_eq "... and stops after that bead" "$(grep -cE '(^| )update ' "$T/bd.log")" "1"
fi
chmod 644 "$T/r/applied.jsonl"

# I2: undo checks the chain of applies
fresh; cp "$T/D.json" "$T/r/decisions.json"; apply >/dev/null 2>&1
PRI=$(pnum priority)
edit acme-9 labels '["human"]'
apply --proposal "$PRI" >/dev/null 2>&1
out="$(undo 2>&1)"; rc=$?
assert_eq "undo: a human edit between two applies is refused, exit 8" "$rc" "8"
assert_contains "... naming the bead" "$out" "acme-9 changed since the run; not undone"
assert_eq "... leaving it alone" "$(field acme-9 labels)" "['human']"
assert_eq "... while the other beads are restored" "$(field acme-4 labels)" "['wave:1']"
fresh; cp "$T/D.json" "$T/r/decisions.json"; apply >/dev/null 2>&1
PRI=$(pnum priority); undo >/dev/null 2>&1
apply --proposal "$PRI" >/dev/null 2>&1
assert_eq "a proposal applied after an undo: the bead has it" "$(field acme-9 priority)" "1"
out="$(undo 2>&1)"; rc=$?
assert_eq "... and is undoable, exit 0" "$rc" "0"
assert_contains "... the bead is restored, not 'already undone'" "$out" "acme-9: restored"
assert_eq "... to its priority" "$(field acme-9 priority)" "2"
assert_contains "... earlier beads are still 'already undone'" "$out" "acme-4: already undone"

# I2 again: a before line with no applied line (a run that stopped) must not pair with a later apply
fresh; cp "$T/D.json" "$T/r/decisions.json"; FAKE_BD_UPDATE_FAIL_ID=acme-4 apply >/dev/null 2>&1
PRI=$(pnum priority)
edit acme-9 labels '["human"]'
apply --proposal "$PRI" >/dev/null 2>&1
assert_eq "stopped run, human edit, proposal: the proposal applied" "$(field acme-9 priority)" "1"
out="$(undo 2>&1)"; rc=$?
assert_eq "... undo refuses the edited bead, exit 8" "$rc" "8"
assert_contains "... naming it" "$out" "acme-9 changed since the run; not undone"
assert_eq "... and keeps the human edit" "$(field acme-9 labels)" "['human']"
assert_eq "... and the priority it was left with" "$(field acme-9 priority)" "1"
# a bead never applied in a stopped run is restorable to the state before its first real apply
fresh; cp "$T/D.json" "$T/r/decisions.json"; FAKE_BD_UPDATE_FAIL_ID=acme-4 apply >/dev/null 2>&1
apply --proposal "$(pnum priority)" >/dev/null 2>&1
assert_contains "stopped run then a proposal, no edit: undo restores it" "$(undo 2>&1)" "acme-9: restored"
assert_eq "... to its priority" "$(field acme-9 priority)" "2"

# I3 and M4: undefer and close come back exactly, and note the op
fresh; addbead '{"id":"acme-14","title":"Later","status":"deferred","priority":2,"labels":[],"defer_until":"2027-01-05T00:00:00Z","updated_at":"2026-10-01T00:00:00Z"}'
printf '%s' '{"changes":[{"id":"acme-14","kind":"undefer","why":"back","protected":false},{"id":"acme-1","kind":"close","why":"done","protected":false}]}' > "$T/r/decisions.json"
apply >/dev/null 2>&1; UND=$(pnum undefer); CLO=$(pnum close)
apply --proposal "$UND" >/dev/null 2>&1; apply --proposal "$CLO" >/dev/null 2>&1
assert_eq "undefer: opens it and drops the date" "$(field acme-14 status) $(field acme-14 defer_until)" "open "
assert_contains "undefer: gets a groomed note (M4)" "$(field acme-14 notes)" "groomed 2026-10-23: undefer — back"
assert_contains "close: gets a groomed note (M4)" "$(field acme-1 notes)" "groomed 2026-10-23: close — done"
assert_eq "close: closed with a reason" "$(field acme-1 status) $(field acme-1 close_reason)" "closed done"
out="$(undo 2>&1)"; rc=$?
assert_eq "undo of undefer and close: exit 0" "$rc" "0"
assert_eq "undo: undefer comes back deferred with the same date" "$(field acme-14 status) $(field acme-14 defer_until)" "deferred 2027-01-05T00:00:00Z"
assert_eq "undo: close comes back open, closed_at and close_reason gone" "$(field acme-1 status)|$(field acme-1 closed_at)|$(field acme-1 close_reason)|$(field acme-1 notes)" "open|||"
assert_not_contains "undo: nothing to do by hand" "$out" "by hand"

# M5: a named bead that was never applied exits 8
fresh; cp "$T/D.json" "$T/r/decisions.json"; FAKE_BD_UPDATE_FAIL_ID=acme-4 apply >/dev/null 2>&1
undo acme-10 >"$T/out" 2>&1; rc=$?
assert_eq "undo ID for a bead in before.jsonl but not applied: exit 8" "$rc" "8"
assert_contains "... and says so" "$(cat "$T/out")" "acme-10: not applied"

# M8: before.jsonl unwritable (proposals.json writable): exit 6, nothing written
if [ "$(id -u)" != 0 ]; then
  fresh; cp "$T/D.json" "$T/r/decisions.json"; : > "$T/r/before.jsonl"; chmod 444 "$T/r/before.jsonl"
  apply >/dev/null 2>"$T/err"; rc=$?
  assert_eq "unwritable before.jsonl: exit 6" "$rc" "6"
  assert_eq "... nothing applied" "$(nwrites)" "0"
  assert_contains "... proposals.json was still written" "$(ls "$T/r")" "proposals.json"
  chmod 644 "$T/r/before.jsonl"
  fresh; cp "$T/D.json" "$T/r/decisions.json"; apply >/dev/null 2>&1; PRI=$(pnum priority); n=$(nwrites)
  chmod 444 "$T/r/before.jsonl"
  apply --proposal "$PRI" >/dev/null 2>"$T/err"; rc=$?
  assert_eq "unwritable before.jsonl, --proposal: exit 6" "$rc" "6"
  assert_eq "... nothing applied" "$(nwrites)" "$n"
  assert_eq "... the bead is untouched" "$(field acme-9 priority)" "2"
  chmod 644 "$T/r/before.jsonl"
fi

# M9: a hostile close reason is one argv element
fresh
python3 - "$T/r/decisions.json" "$HOSTILE" <<'PY'
import json, sys
json.dump({"changes": [{"id": "acme-1", "kind": "close", "why": sys.argv[2], "protected": False}]}, open(sys.argv[1], "w"))
PY
apply >/dev/null 2>&1; apply --proposal "$(pnum close)" >/dev/null 2>&1
assert_eq "hostile close reason: the bead is closed" "$(field acme-1 status)" "closed"
assert_eq "hostile close reason: nothing executed" "$(ls "$T" | grep -c '^pwned')" "0"
assert_eq "hostile close reason: one --reason= element, no newline" "$(chk close "$T/argv.log")" "1 True False"

unset FAKE_BD_STATEFUL FAKE_BD_LOG FAKE_BD_ARGV_LOG

# --- run: the judge, then apply ---
# Three spaces: acme and beta have plans, gamma has none. The fake judge copies decisions.json and
# summary.md from $T/judge into the run dir; wb-groom applies them with the stateful fake bd.
TR="$(cd "$T" && pwd -P)"   # the judge is given resolved paths (macOS: /var is /private/var)
G="$TR/groom"; P="$TR/plans"; rm -rf "$G" "$P"; mkdir -p "$P" "$T/cfg-acme"
cp -R "$FX/plan" "$P/acme"; cp -R "$FX/plan" "$P/beta"; printf 'date: 2026-10-10\nAcme only.\n' > "$P/acme/calendar.md"
setup_repo "$T/ra" >/dev/null 2>&1
git -C "$T/ra" push -q origin HEAD:refs/dolt/data 2>/dev/null   # a store that syncs to a shared remote
for d in ra rb rc; do mkstore "$T/$d"; done
reset_stores() { for d in ra rb rc; do cp "$FX/beads.json" "$T/$d/.beads/fake.json"; rm -f "$T/$d/.beads/fake-clock"; done; }
cat > "$T/spaces.toml" <<EOF
[[space]]
name = "acme"
root = "$T/ra"
claude_config = "$T/cfg-acme"
protocol = "docs/PROTOCOL.md"
[[space]]
name = "beta"
root = "$T/rb"
[[space]]
name = "gamma"
root = "$T/rc"
EOF
mkdir -p "$T/judge"
printf '%s' '{"goals":[{"text":"Invoices match the books.","inferred":false}],"changes":[{"id":"acme-10","kind":"icebox","why":"no goal","protected":false},{"id":"acme-9","kind":"priority","to":"1","why":"due soon"}],"attention":{"add":[{"id":"acme-9","why":"due Nov 2"}]}}' > "$T/judge/decisions.json"
printf '# Grooming\nThe judge wrote this.\n' > "$T/judge/summary.md"
# files a hostile bead could talk the judge into writing: wb-groom must not take them
printf 'x\n' > "$T/judge/reviewed"; printf '{"id":"acme-10"}\n' > "$T/judge/before.jsonl"
export WORKBENCH_CONFIG="$T/spaces.toml" WB_GROOM_DIR="$G" WB_PLANS_DIR="$P" FAKE_CLAUDE_GROOM="$T/judge" FAKE_CLAUDE_LOG="$T/claude.log"
export FAKE_BD_STATEFUL=1 FAKE_BD_LOG="$T/bd.log"
groom() { "$WG" run "$@"; }
newest() { ls -d "$G/$1"/2* 2>/dev/null | tail -1; }
writes() { grep -cE '(^| )(update|close|undefer) ' "$T/bd.log"; }
sfield() { python3 -c "import json; print([b for b in json.load(open('$T/$1/.beads/fake.json')) if b['id']=='$2'][0].get('$3', ''))"; }
# jl EXPR: EXPR over the last fake-claude call (a = argv, c = the whole record)
jl() { python3 -c "import json; c = json.loads(open('$T/claude.log').read().splitlines()[-1]); a = c['argv']; print($1)"; }

reset_stores; : > "$T/bd.log"; : > "$T/claude.log"
CLAUDE_CONFIG_DIR="$T/elsewhere" GITHUB_TOKEN=secret AWS_SECRET_ACCESS_KEY=secret groom acme >"$T/out" 2>"$T/err"; rc=$?
R="$(newest acme)"
assert_eq "run: exit 0" "$rc" "0"
assert_eq "run: the run dir is <space>/YYYYMMDD-HHMM" "$(basename "$R" | grep -cE '^[0-9]{8}-[0-9]{4}$')" "1"
assert_contains "run: the judge's decisions are applied (bd log)" "$(cat "$T/bd.log")" "--sandbox update acme-10 --add-label icebox"
assert_eq "run: ... and in the store" "$(sfield ra acme-10 labels)" "['icebox']"
assert_eq "run: a priority change is only proposed" "$(sfield ra acme-9 priority)" "2"
assert_eq "run: attention is applied" "$(sfield ra acme-9 labels)" "['attention']"
assert_eq "run: proposals.json is in the run dir (no sprint named, so no wave moves)" "$(python3 -c "import json; print([p['kind'] for p in json.load(open('$R/proposals.json'))])")" "['priority']"
assert_eq "run: inputs.json hashes the plan files" \
  "$(python3 -c "import json, hashlib; i = json.load(open('$R/inputs.json')); f = i['plan_files']; print(f['goals.md'] == hashlib.sha256(open('$P/acme/goals.md','rb').read()).hexdigest(), f['calendar.md'] is not None, f['sources.md'], i['plan_state'])")" \
  "True True None ok"
assert_eq "judge: runs in the space root" "$(jl "c['cwd']")" "$(cd "$T/ra" && pwd -P)"
assert_eq "judge: with the space's claude_config" "$(jl "c['config']")" "$T/cfg-acme"
assert_eq "judge: print mode, settings sources off" "$(jl "a[0], a[a.index('--setting-sources') + 1] == ''")" "-p True"
assert_eq "judge: dontAsk, strict MCP, only Bash, Read and Write" \
  "$(jl "a[a.index('--permission-mode') + 1], '--strict-mcp-config' in a, a[a.index('--tools') + 1]")" "dontAsk True Bash,Read,Write"
assert_not_contains "judge: never skips permissions" "$(cat "$T/claude.log")" "dangerously"
assert_not_contains "judge: never bypassPermissions" "$(cat "$T/claude.log")" "bypassPermissions"
assert_eq "judge: the rules admit the run's bd script and scoped Read/Edit, nothing else" \
  "$(jl "sorted(json.loads(a[a.index('--settings') + 1])['permissions']['allow']) == sorted(['Bash($R/bd-readonly:*)', 'Read(/$(cd "$T/ra" && pwd -P)/**)', 'Read(/$P/acme/**)', 'Read(/$R/judge/**)', 'Edit(/$R/judge/**)'])")" "True"
assert_eq "judge: --allowedTools is the same list" \
  "$(jl "a[a.index('--allowedTools') + 1:a.index('--add-dir')] == json.loads(a[a.index('--settings') + 1])['permissions']['allow']")" "True"
assert_eq "judge: no rule names bd itself" "$(jl "[x for x in a if x.startswith('Bash(bd')]")" "[]"
assert_eq "judge: the bd script is not writable" "$(ls -l "$R/bd-readonly" | cut -c1-10)" "-r-xr-xr-x"
assert_eq "judge: its environment is the allowlist only (PWD, SHLVL, _ are the fake shell's own)" "$(jl "[k for k in c['env'] if k not in ('PATH','HOME','USER','LOGNAME','SHELL','LANG','TMPDIR','CLAUDE_CONFIG_DIR','PWD','SHLVL','_') and not k.startswith(('LC_','FAKE_CLAUDE_','__CF'))]")" "[]"
assert_eq "judge: writes only to its own dir in the run dir" "$(jl "[x for x in a if x.startswith('Edit(')] == ['Edit(/' + '$R' + '/judge/**)']")" "True"
assert_eq "judge: reads no run record" "$(jl "[x for x in a if x.startswith('Read(/$R')] == ['Read(/$R/judge/**)']")" "True"
assert_eq "judge: no unscoped Read or Write" "$(jl "'Read' in a or 'Write' in a")" "False"
assert_eq "judge: settings deny the network commands" \
  "$(jl "(lambda d: all('Bash(%s:*)' % c in d for c in ('gh','ssh','curl','wget','nc','printenv','env')))(json.loads(a[a.index('--settings') + 1])['permissions']['deny'])")" "True"
assert_eq "judge: settings deny git and the web, and not Edit (that would block Write too)" \
  "$(jl "(lambda d: ('Bash(git:*)' in d, 'WebFetch' in d, 'Edit' in d))(json.loads(a[a.index('--settings') + 1])['permissions']['deny'])")" "(True, True, False)"
assert_eq "judge: add-dir is its own dir, then the plan dir" "$(jl "a[a.index('--add-dir') + 1:a.index('--add-dir') + 3] == ['$R/judge', '$P/acme']")" "True"
assert_eq "judge: the prompt is one argv element, after --" "$(jl "a[-2] == '--' and '$R/judge/decisions.json' in a[-1] and 'acme' in a[-1]")" "True"
assert_eq "run: decisions.json and summary.md are taken from the judge's dir" "$(ls "$R/decisions.json" "$R/summary.md" | wc -l | tr -d ' ')" "2"
assert_eq "run: nothing else the judge wrote reaches the run dir" "$(ls "$R/reviewed" "$R/judge/../reviewed" 2>/dev/null; python3 -c "import json; print([r['step'] is not None for r in map(json.loads, open('$R/before.jsonl'))])")" "[True, True]"
assert_eq "judge: no placeholder left in the prompt" "$(jl "__import__('re').findall(r'\{[a-z_]+\}', a[-1])")" "[]"
assert_contains "summary: keeps the judge's text" "$(cat "$R/summary.md")" "The judge wrote this."
assert_contains "summary: says what workbench applied" "$(cat "$R/summary.md")" "applied 2 bead(s)"
assert_contains "summary: a store on a shared remote says so" "$(cat "$R/summary.md")" "This store syncs to a shared remote: changes go out with your next sync"
assert_not_contains "summary: a fresh plan does not ask for strategy" "$(cat "$R/summary.md")" "strategy session needed"
assert_not_contains "summary: no earlier runs, no count" "$(cat "$R/summary.md")" "earlier run"

# beta: no claude_config, so the judge gets none, even with one in the environment
: > "$T/claude.log"
CLAUDE_CONFIG_DIR="$T/elsewhere" groom beta >/dev/null 2>&1
assert_eq "judge: no claude_config, CLAUDE_CONFIG_DIR unset" "$(jl "c['config']")" "None"
assert_not_contains "summary: no remote, no remote line" "$(cat "$(newest beta)/summary.md")" "shared remote"

# a second run in the same minute gets its own dir, and counts the first as unreviewed
groom acme >/dev/null 2>&1
R2="$(newest acme)"
assert_eq "run: a second run in the same minute has its own dir" "$(ls -d "$G/acme"/2* | wc -l | tr -d ' ')" "2"
assert_contains "summary: earlier runs not yet reviewed" "$(cat "$R2/summary.md")" "1 earlier runs not yet reviewed"
touch "$R/reviewed"; groom acme >/dev/null 2>&1
assert_contains "summary: a reviewed run is not counted" "$(cat "$(newest acme)/summary.md")" "1 earlier runs not yet reviewed"

# missing plan: the judge runs, nothing is written, and the summary leads with strategy
reset_stores; : > "$T/bd.log"
groom gamma >/dev/null 2>"$T/err"; rc=$?
R="$(newest gamma)"
assert_eq "missing plan: exit 0" "$rc" "0"
assert_eq "missing plan: no bd writes" "$(writes)" "0"
assert_eq "missing plan: summary leads 'strategy session needed'" "$(head -1 "$R/summary.md" | cut -c1-25)" "strategy session needed ("
assert_eq "missing plan: the ops are left as proposals" "$(python3 -c "import json; print(len(json.load(open('$R/proposals.json'))) > 0)")" "True"
assert_eq "missing plan: inputs.json says so" "$(python3 -c "import json; print(json.load(open('$R/inputs.json'))['plan_state'])")" "missing"
# a stale plan: the same, and the summary says which
cp "$P/acme/goals.md" "$T/goals.keep"; printf 'date: 2026-08-01\n' > "$P/acme/goals.md"; : > "$T/bd.log"
groom acme >/dev/null 2>&1; rc=$?
assert_eq "stale plan: exit 0, no bd writes" "$rc $(writes)" "0 0"
assert_eq "stale plan: summary leads with it" "$(head -1 "$(newest acme)/summary.md" | cut -c1-36)" "strategy session needed (plan stale)"
cp "$T/goals.keep" "$P/acme/goals.md"

# the judge times out: nothing applied, even though it wrote decisions.json first
reset_stores; : > "$T/bd.log"; s=$SECONDS
WB_GROOM_TIMEOUT=1 FAKE_CLAUDE_SLEEP=30 groom acme >/dev/null 2>"$T/err"; rc=$?
R="$(newest acme)"
assert_eq "timeout: exit 10" "$rc" "10"
assert_eq "timeout: no bd writes" "$(writes)" "0"
assert_eq "timeout: the judge is stopped, not waited for" "$(( SECONDS - s < 20 ))" "1"
assert_contains "timeout: summary says why" "$(cat "$R/summary.md")" "timed out after 1 s; nothing applied"
assert_eq "timeout: no before.jsonl" "$(ls "$R/before.jsonl" 2>/dev/null)" ""
# the judge fails
FAKE_CLAUDE_RC=3 groom acme >/dev/null 2>"$T/err"; rc=$?
assert_eq "judge failed: exit 10" "$rc" "10"
assert_contains "judge failed: summary says why" "$(cat "$(newest acme)/summary.md")" "the judge failed (exit 3); nothing applied"
assert_contains "judge failed: summary names the files with the detail" "$(cat "$(newest acme)/summary.md")" "see judge.json and judge.err in the run dir"
assert_eq "judge failed: no bd writes" "$(writes)" "0"
# the judge leaves no decisions.json
mkdir -p "$T/judge2"; printf 'I could not finish.\n' > "$T/judge2/summary.md"
FAKE_CLAUDE_GROOM="$T/judge2" groom acme >/dev/null 2>"$T/err"; rc=$?
assert_eq "no decisions.json: exit 10" "$rc" "10"
assert_contains "no decisions.json: summary names the judge's output" "$(cat "$(newest acme)/summary.md")" "see judge.json and judge.err in the run dir"
assert_contains "no decisions.json: summary says why" "$(cat "$(newest acme)/summary.md")" "the judge left no decisions.json; nothing applied"
assert_contains "no decisions.json: ... and keeps the judge's words" "$(cat "$(newest acme)/summary.md")" "I could not finish."
assert_eq "no decisions.json: no bd writes" "$(writes)" "0"

# a held lock: a second run refuses and starts nothing
n=$(ls -d "$G/acme"/2* 2>/dev/null | wc -l); mkdir -p "$G/acme"; rm -f "$T/locked"
python3 -c "import fcntl, os, sys, time; f = open('$G/acme/.lock', 'a'); fcntl.flock(f, fcntl.LOCK_EX); open('$T/locked', 'w').close(); time.sleep(10)" &
lp=$!
i=0; while [ ! -f "$T/locked" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
: > "$T/claude.log"
groom acme >/dev/null 2>"$T/err"; rc=$?
kill $lp 2>/dev/null; wait $lp 2>/dev/null
assert_eq "lock: a second run exits 9" "$rc" "9"
assert_contains "lock: and says why" "$(cat "$T/err")" "a grooming run is in progress"
assert_eq "lock: no judge, no new run dir" "$(wc -c < "$T/claude.log" | tr -d ' ') $(ls -d "$G/acme"/2* | wc -l)" "0 $n"
groom acme >/dev/null 2>&1; assert_eq "lock: released when its holder ends" "$?" "0"

# --all: spaces with a plan; one broken store does not stop the others
reset_stores; : > "$T/bd.log"; rm -rf "$G"; rm "$T/rb/.beads/fake.json"
groom --all >"$T/out" 2>"$T/err"; rc=$?
assert_eq "--all: exit 1 when a space failed" "$rc" "1"
assert_eq "--all: the good space is applied" "$(sfield ra acme-10 labels)" "['icebox']"
assert_contains "--all: names the failed space" "$(cat "$T/err")" "failed: beta (exit 4)"
assert_eq "--all: a space with no plan dir is not run" "$(ls "$G" | tr '\n' ' ')" "acme beta "
assert_contains "--all: the broken space's summary says why" "$(cat "$(newest beta)/summary.md")" "bd could not be read"
cp "$FX/beads.json" "$T/rb/.beads/fake.json"
groom --all >/dev/null 2>&1; assert_eq "--all: exit 0 when all ran" "$?" "0"

groom nope >/dev/null 2>"$T/err"; assert_eq "run: an unknown space exits 2" "$?" "2"
assert_contains "... and says so" "$(cat "$T/err")" "no space named nope"
groom >/dev/null 2>&1; assert_eq "run: no space is usage" "$?" "2"
WB_GROOM_TIMEOUT=soon groom acme >/dev/null 2>"$T/err"; assert_eq "run: a bad WB_GROOM_TIMEOUT exits 2" "$?" "2"
assert_contains "... and says so" "$(cat "$T/err")" "WB_GROOM_TIMEOUT is not a number"

# attention applied to claimed beads: the label and note change, the claim does not
fresh
addbead '{"id":"acme-15","title":"Claimed, flagged","status":"in_progress","priority":1,"labels":["attention"],"notes":"attention: old reason","updated_at":"2026-10-01T00:00:00Z"}'
addbead '{"id":"acme-16","title":"Done","status":"closed","priority":2,"labels":[],"updated_at":"2026-10-01T00:00:00Z"}'
printf '%s' '{"attention":{"add":[{"id":"acme-3","why":"stale claim · due Nov 2"},{"id":"acme-16","why":"x"}],"remove":[{"id":"acme-15","why":"paid"}]}}' > "$T/r/decisions.json"
apply >"$T/out" 2>"$T/err"; rc=$?
assert_eq "claimed attention: apply exits 0" "$rc" "0"
assert_eq "claimed attention: flagged, still claimed" "$(field acme-3 labels) $(field acme-3 status)" "['wave:1', 'attention'] in_progress"
assert_contains "claimed attention: the reason is in the notes" "$(field acme-3 notes)" "attention: stale claim · due Nov 2"
assert_eq "claimed attention: unflagged, still claimed" "$(field acme-15 labels) $(field acme-15 status)" "[] in_progress"
assert_eq "claimed attention: a closed bead is never flagged" "$(field acme-16 labels)" "[]"

# the prompt teaches the decisions.json shape and the plan inputs
GP="$(cat "$REPO/prompts/groom.txt" 2>/dev/null)"
for w in '"leaving"' '"attention"' '"protected"' goals.md protected.md calendar.md sources.md \
         '{bd} list -n 0 --json' '{bd} show <id> --json' 'when unsure' 'within 14 days'; do
  assert_contains "prompt: mentions $w" "$GP" "$w"
done
assert_not_contains "prompt: no unqualified bd call" "$GP" '`bd list'
assert_not_contains "prompt: no bd --readonly call (bd itself is refused)" "$GP" '`bd --readonly'

# --- the judge's bd script ---
# cx ARGS…: check() on ARGS, "ok <argv>" or "refused"
cx() { PYTHONPATH="$PL" python3 -c 'import sys, wb_judge_bd as w
try: print("ok", " ".join(w.check(sys.argv[1:])))
except w.Refused: print("refused")' "$@"; }
assert_eq "bd script: list -n 0 --json" "$(cx list -n 0 --json)" "ok list -n 0 --json"
assert_eq "bd script: list --all" "$(cx list --all -n 0 --json)" "ok list --all -n 0 --json"
assert_eq "bd script: show several ids" "$(cx show acme-1 acme-2.3 --json)" "ok show acme-1 acme-2.3 --json"
assert_eq "bd script: ready" "$(cx ready -n 5 --json)" "ok ready -n 5 --json"
assert_eq "bd script: dep tree" "$(cx dep tree acme-1)" "ok dep tree acme-1"
assert_eq "bd script: children" "$(cx children acme-1 --json)" "ok children acme-1 --json"
assert_eq "bd script: an id with a trailing newline is refused" "$(cx show $'acme-1\n')" "refused"
assert_eq "bd script: a number with a trailing newline is refused" "$(cx list -n $'5\n')" "refused"
for bad in "list --profile" "list --db /x" "list -C /x" "list --directory=/x" "list --global" "list --readonly=false" \
           "list --dolt-auto-commit=on" "list --sandbox=false" "--profile list" "update acme-1 -p 1" "close acme-1" \
           "show" "show --all" "show -x" "show ../x" "show /etc/passwd" "list acme-1" "list -n" "list -n x" \
           "dep add acme-1 acme-2" "dep tree" "children" "children a b" "sql select" "list --json=x"; do
  assert_eq "bd script refuses: $bad" "$(cx $bad)" "refused"
done
# the script itself: a recording bd, called from elsewhere with hostile env; it runs in the root
cat > "$T/recbd" <<EOF
#!/bin/sh
printf '%s|%s|%s\n' "\$PWD" "\$*" "\$(env | cut -d= -f1 | sort | tr '\n' ' ')" >> "$T/recbd.log"
EOF
chmod +x "$T/recbd"; mkdir -p "$T/wrun"; : > "$T/recbd.log"
WS="$(PYTHONPATH="$PL" python3 -c "import wb_groom; print(wb_groom.write_judge_bd('$T/wrun', '$T/ra', '$T/recbd'))")"
(cd / && GITHUB_TOKEN=x BEADS_DIR=/tmp PYTHONPATH=/tmp "$WS" list -n 0 --json)
assert_eq "bd script: execs bd --readonly --sandbox in the space root" "$(cut -d'|' -f1-2 "$T/recbd.log")" "$(cd "$T/ra" && pwd -P)|--readonly --sandbox list -n 0 --json"
assert_not_contains "bd script: none of the caller's env reaches bd" "$(cut -d'|' -f3 "$T/recbd.log")" "GITHUB_TOKEN"
assert_not_contains "bd script: ... not BEADS_DIR" "$(cut -d'|' -f3 "$T/recbd.log")" "BEADS_DIR"
"$WS" list --profile 2>"$T/err"; rc=$?
assert_eq "bd script: a refused call exits 2 and runs no bd" "$rc $(wc -l < "$T/recbd.log" | tr -d ' ')" "2 1"
assert_contains "... and says what is allowed" "$(cat "$T/err")" "refused: '--profile' is not allowed"

# --- --all goes on past a space that crashes ---
cat > "$T/crash.py" <<'PYX'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("wg", importlib.machinery.SourceFileLoader("wg", sys.argv[1]))
wg = importlib.util.module_from_spec(spec); spec.loader.exec_module(wg)
real = wg.groom_space
def groom_space(space):
    if space["label"] == "acme":
        raise RuntimeError("boom")
    return real(space)
wg.groom_space = groom_space
sys.exit(wg.cmd_run("--all"))
PYX
export FAKE_BD_STATEFUL=1 FAKE_BD_LOG="$T/bd.log" FAKE_CLAUDE_GROOM="$T/judge" WORKBENCH_CONFIG="$T/spaces.toml" WB_GROOM_DIR="$G" WB_PLANS_DIR="$P"
reset_stores; rm -rf "$G"
python3 "$T/crash.py" "$WG" >/dev/null 2>"$T/err"; rc=$?
assert_eq "--all: a crashing space exits 1" "$rc" "1"
assert_contains "--all: names the crash" "$(cat "$T/err")" "acme: crashed: RuntimeError: boom"
assert_contains "--all: counts it failed" "$(cat "$T/err")" "failed: acme (crashed)"
assert_eq "--all: the next space still ran" "$(ls "$G" | tr '\n' ' ')" "beta "

# --- shared remote: a remote that can't be reached is said, not skipped ---
git -C "$T/rb" init -q 2>/dev/null; git -C "$T/rb" remote add origin "$T/no-such-remote.git"
groom beta >/dev/null 2>&1
assert_contains "remote: an unreachable remote says it couldn't check" "$(cat "$(newest beta)/summary.md")" "Could not check whether this store syncs to a shared remote"
assert_eq "remote: a repo's core.sshCommand is left to git" \
  "$(git -C "$T/rb" config core.sshCommand 'ssh -i k'; python3 - "$WG" "$T/rb" <<'PYX'
import importlib.machinery, importlib.util, os, subprocess, sys
spec = importlib.util.spec_from_loader("wg", importlib.machinery.SourceFileLoader("wg", sys.argv[1]))
wg = importlib.util.module_from_spec(spec); spec.loader.exec_module(wg)
seen = []
real = subprocess.run
def run(*a, **k):
    seen.append(k.get("env", {}).get("GIT_SSH_COMMAND"))
    return real(*a, **k)
wg.subprocess.run = run
os.environ.pop("GIT_SSH_COMMAND", None)
wg.shared_remote(sys.argv[2])
print(seen[-1])
PYX
)" "None"

# --- status, reviewed, strategy (what the launcher shows and starts) ---
SG="$T/sg"; SP="$T/sp"; export WB_GROOM_DIR="$SG" WB_PLANS_DIR="$SP"
st() { "$WG" status "$@" 2>"$T/err"; }
assert_eq "status: no plan and no runs shows nothing, exit 0" "$(st acme; echo "rc=$?")" "rc=0"
mkdir -p "$SG/acme/20261010-0600" "$SG/acme/20261017-0600"; : > "$SG/acme/.lock"; mkdir -p "$SG/acme/notes"; : > "$SG/acme/20261024-0600"
assert_eq "status: no plan, runs: strategy is due (missing plan); the newest unreviewed run, one more waiting" "$(st acme)" \
  "review	$SG/acme/20261017-0600	Sat	1 waiting
strategy	due"
mkdir -p "$SP/acme"; cp "$FX/plan/"* "$SP/acme/"
assert_eq "status: an ok plan adds no strategy line; .lock, files and non-run dirs are ignored" "$(st acme)" \
  "review	$SG/acme/20261017-0600	Sat	1 waiting"
: > "$SG/acme/20261017-0600/reviewed"
assert_eq "status: reviewed runs are skipped, no waiting count for one" "$(st acme)" "review	$SG/acme/20261010-0600	Sat"
: > "$SG/acme/20261010-0600/reviewed"
assert_eq "status: all reviewed shows nothing" "$(st acme)" ""
mkdir -p "$SG/acme/20261020-0600-02" "$SG/acme/20261020-0600"
assert_eq "status: -02 sorts after its minute; weekday from the run id" "$(st acme)" "review	$SG/acme/20261020-0600-02	Tue	1 waiting"
rm -rf "$SG/acme/20261020-0600-02" "$SG/acme/20261020-0600"
assert_eq "status: plan 31 days old is due" "$(WB_TODAY=2026-11-10 st acme)" "strategy	due"
assert_eq "status: plan 60 days old is stale: due" "$(WB_TODAY=2026-12-09 st acme)" "strategy	due"
rm -rf "$SG/acme"; mkdir -p "$SG/acme"
assert_eq "status: a due plan with no runs is still due (the date is the clock)" "$(WB_TODAY=2026-11-10 st acme)" "strategy	due"
rm -rf "$SP/acme"; mkdir -p "$SP/acme"; printf '# Goals\ndate: YYYY-MM-DD\n' > "$SP/acme/goals.md"
assert_eq "status: an unedited template plan with no runs shows nothing" "$(st acme)" ""
mkdir -p "$SG/acme/20261017-0600"
assert_contains "status: an unedited template plan with runs is due" "$(st acme)" "strategy	due"
assert_eq "status: always exit 0, even for an unknown label" "$(st nope/../x; echo $?)" "0"

"$WG" reviewed "$SG/acme/20261017-0600" >"$T/out" 2>"$T/err"; assert_eq "reviewed: exit 0" "$?" "0"
assert_eq "reviewed: writes the date" "$(cat "$SG/acme/20261017-0600/reviewed")" "$(date +%Y-%m-%d)"
assert_eq "reviewed: the run is no longer offered" "$(st acme | grep -c '^review')" "0"
"$WG" reviewed "$SG/acme/20261017-0600" >/dev/null 2>&1; assert_eq "reviewed: twice is fine" "$?" "0"
"$WG" reviewed "$SG/acme/nope" >/dev/null 2>"$T/err"; assert_eq "reviewed: a missing run dir exits 2" "$?" "2"
assert_contains "reviewed: ... and says so" "$(cat "$T/err")" "no run directory"
"$WG" reviewed >/dev/null 2>&1; assert_eq "reviewed: no argument is usage" "$?" "2"

rm -rf "$SP"
out="$("$WG" strategy acme 2>"$T/err")"; rc=$?
assert_eq "strategy: exit 0 and prints the plan dir" "$rc $out" "0 $SP/acme"
assert_eq "strategy: makes the four plan files from the templates" "$(ls "$SP/acme" | tr '\n' ' ')" "calendar.md goals.md protected.md sources.md "
assert_eq "strategy: a fresh plan reads as missing (its date is a placeholder)" \
  "$(py "import datetime; p = g.read_plan('$SP/acme'); print(p.goals_date, g.plan_state(p, datetime.date(2026,10,23)))")" "None missing"
assert_eq "strategy: the template's calendar dates are far in the future (never due soon)" \
  "$(grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$SP/acme/calendar.md" | cut -c1-2 | sort -u | tr -d '\n')" "20"
assert_not_contains "strategy: ... 2099, not a near year" "$(grep -Eo '[0-9]{4}-' "$SP/acme/calendar.md")" "2026"
assert_contains "strategy: the template carries a labels line" "$(cat "$SP/acme/protected.md")" "labels:"
assert_contains "strategy: the template carries the sprint line" "$(cat "$SP/acme/goals.md")" "sprint:"
printf 'my goals\ndate: 2026-10-20\n' > "$SP/acme/goals.md"
out="$("$WG" strategy acme)"
assert_eq "strategy: idempotent; prints the same path and keeps edits" "$out $(head -1 "$SP/acme/goals.md")" "$SP/acme my goals"
rm "$SP/acme/calendar.md"; "$WG" strategy acme >/dev/null
assert_eq "strategy: a deleted file is not brought back over the user's plan" "$(ls "$SP/acme" | tr '\n' ' ')" "goals.md protected.md sources.md "
"$WG" strategy nope >/dev/null 2>"$T/err"; assert_eq "strategy: an unknown space exits 2" "$?" "2"
assert_contains "strategy: ... and says so" "$(cat "$T/err")" "no space named nope"
assert_eq "strategy: nothing made for an unknown space" "$(ls "$SP" | tr '\n' ' ')" "acme "
export WB_GROOM_DIR="$G" WB_PLANS_DIR="$P"

unset FAKE_BD_STATEFUL FAKE_BD_LOG FAKE_CLAUDE_GROOM FAKE_CLAUDE_LOG WORKBENCH_CONFIG WB_GROOM_DIR WB_PLANS_DIR

finish
