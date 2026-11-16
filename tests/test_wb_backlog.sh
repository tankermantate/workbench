#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
WB="$REPO/bin/wb-backlog"; FX="$REPO/tests/fixtures"
mkstore "$T/store"; mkdir -p "$T/nostore"
export FAKE_BD_DIR="$T/bd" WB_GROOM_DIR="$T/groom"  # never the real run records
reset_bd() { rm -rf "$FAKE_BD_DIR"; mkdir -p "$FAKE_BD_DIR"; }

reset_bd; cp "$FX/waves.json" "$FAKE_BD_DIR/stdout"
out="$("$WB" list "$T/store" --snapshot "$T/snap.json")"; rc=$?
assert_eq "list ok exits 0" "$rc" "0"
assert_eq "order: NOW by priority, NEXT, then the rest by priority; deferred+closed hidden" \
  "$(printf '%s\n' "$out" | cut -f1 | tr '\n' ' ')" "acme-a2 acme-a1 acme-b1 acme-c1 acme-e1 acme-c2 "
assert_eq "row fields" "$(printf '%s\n' "$out" | head -1)" \
  "acme-a2	a2	○	P1	NOW	High wave-1	acme-e1	-	Epic: tidy the shop	-	1 NOW · P1 · shape first	-	-"
assert_eq "in-progress is ◐ with its worktree from notes" "$(printf '%s\n' "$out" | tail -1)" \
  "acme-c2	c2	◐	P3	-	Claimed elsewhere	-	/tmp/wb-fixture-wt/acme-x	-	-	-	-	-"
assert_eq "claimed: the bead whose current claim names the worktree" \
  "$("$WB" claimed "$T/store" /tmp/wb-fixture-wt/acme-x)" "acme-c2"
"$WB" claimed "$T/store" /tmp/wb-fixture-wt/other >/dev/null; assert_eq "claimed: none exits 1" "$?" "1"
assert_eq "summary with waves" "$("$WB" summary "$T/store")" "NOW 2 · NEXT 1 · claimed 1"

prev="$("$WB" preview "$T/snap.json" acme-a1)"
assert_contains "preview: title" "$prev" "Low wave-1"
assert_contains "preview: parent with title" "$prev" "parent: acme-e1  Epic: tidy the shop"
assert_contains "preview: labels" "$prev" "labels: wave:1"
assert_contains "preview: description keeps newlines" "$prev" $'First line\nSecond line'
assert_contains "preview: new-idea row" "$("$WB" preview "$T/snap.json" -)" "new idea"
prev="$("$WB" preview "$T/snap.json" acme-a1 'second LOW')"
assert_contains "preview: query words highlighted in the title" "$prev" $'\e[1;33mLow\e[0m wave-1'
assert_contains "preview: and in the description" "$prev" $'\e[1;33mSecond\e[0m line'
assert_not_contains "preview: not in the labels" "$prev" $'labels: \e'
assert_not_contains "preview: no query, no colour" "$("$WB" preview "$T/snap.json" acme-a1 '')" $'\e'
assert_eq "preview: section and message rows (no id) show nothing" "$("$WB" preview "$T/snap.json" "")" ""

reset_bd; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout"
assert_eq "no waves: priority alone" "$("$WB" list "$T/store" | cut -f1,5 | tr '\n' ' ')" "bee-2	- bee-1	- "
assert_eq "summary without waves" "$("$WB" summary "$T/store")" "open 2 · claimed 0"

reset_bd; { echo "Warning: $T/store/.beads has permissions 0755 [recommended: 0700]"; cat "$FX/plain.json"; } > "$FAKE_BD_DIR/stdout"
assert_eq "warning line before JSON is skipped" "$("$WB" summary "$T/store")" "open 2 · claimed 0"

reset_bd; echo '[]' > "$FAKE_BD_DIR/stdout"
"$WB" list "$T/store" >/dev/null; rc=$?
assert_eq "empty twice exits 24" "$rc" "24"
assert_eq "empty is retried once" "$(cat "$FAKE_BD_DIR/calls")" "2"
assert_eq "empty summary is a plain count (ctrl-r only works on screen 2)" "$("$WB" summary "$T/store")" "0 open"

reset_bd; echo '[]' > "$FAKE_BD_DIR/stdout.1"; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout.2"
assert_eq "empty then data: the retry wins" "$("$WB" summary "$T/store")" "open 2 · claimed 0"

reset_bd; echo 1 > "$FAKE_BD_DIR/rc"; echo "Error: no beads database found" > "$FAKE_BD_DIR/stderr"
"$WB" list "$T/store" >/dev/null 2>&1; rc=$?
assert_eq "unreadable store exits 22" "$rc" "22"
assert_eq "unreadable summary" "$("$WB" summary "$T/store")" "(no readable beads)"

reset_bd; echo 1 > "$FAKE_BD_DIR/rc"; echo "Error: dolt exploded" > "$FAKE_BD_DIR/stderr"
"$WB" list "$T/store" >/dev/null 2>&1; rc=$?
assert_eq "other failure exits 23" "$rc" "23"

reset_bd; echo 'not json at all' > "$FAKE_BD_DIR/stdout"
assert_eq "junk output is unavailable" "$("$WB" summary "$T/store")" "(bd unavailable)"

# A big store read alongside every other space can take a few seconds: the
# default limit must leave room for it (a store of ~1,200 beads: about 3s under load).
reset_bd; echo 3.5 > "$FAKE_BD_DIR/sleep"; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout"
assert_not_contains "a slow read within the default limit counts" "$(env -u WB_BD_TIMEOUT "$WB" summary "$T/store")" "unavailable"

reset_bd; echo 5 > "$FAKE_BD_DIR/sleep"; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout"
start=$SECONDS; out="$(WB_BD_TIMEOUT=2 "$WB" summary "$T/store")"; took=$((SECONDS - start))
assert_eq "hang is unavailable" "$out" "(bd unavailable)"
if [ "$took" -lt 4 ]; then ok "hang is cut off at the timeout (${took}s)"; else bad "hang took ${took}s"; fi

# A bd that leaves a detached child (its own session, so killpg misses it)
# holding the output pipe must not make the read wait for that child.
cat > "$T/bd-daemon" <<'EOF'
#!/usr/bin/env perl
use POSIX qw(setsid);
if (fork() == 0) { setsid(); sleep 6; exit 0 }
sleep 6;
EOF
chmod +x "$T/bd-daemon"
start=$SECONDS; out="$(WB_BD="$T/bd-daemon" "$WB" summary "$T/store")"; took=$((SECONDS - start))
assert_eq "hang with a detached child is unavailable" "$out" "(bd unavailable)"
if [ "$took" -lt 5 ]; then ok "a detached child does not hold the read open (${took}s)"; else bad "detached child held the read for ${took}s"; fi

# icebox beads go last, under their own section, and don't count as open work;
# a claim untouched for over 7 days is idle (likely a forgotten tab)
reset_bd; python3 - "$FAKE_BD_DIR/stdout" <<'EOF'
import json, sys, datetime
ago = lambda d: (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=d, hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump([
  {"id": "ice-1", "title": "Someday", "status": "open", "priority": 0, "labels": ["icebox", "wave:1"], "updated_at": ago(1)},
  {"id": "ice-2", "title": "Live open", "status": "open", "priority": 1, "updated_at": ago(1)},
  {"id": "ice-3", "title": "Forgotten tab", "status": "in_progress", "priority": 2, "updated_at": ago(23)},
  {"id": "ice-4", "title": "Live claim", "status": "in_progress", "priority": 3, "updated_at": ago(2)},
  {"id": "ice-5", "title": "Old but not claimed", "status": "open", "priority": 4, "updated_at": ago(40)},
  {"id": "ice-6", "title": "A week to the day", "status": "in_progress", "priority": 4, "updated_at": ago(7)},
], open(sys.argv[1], "w"))
EOF
out="$("$WB" list "$T/store")"
assert_eq "icebox: last, in its own section, even with a wave label" "$(printf '%s\n' "$out" | cut -f1,5 | tr '\t\n' ': ')" \
  "ice-2:- ice-3:- ice-4:- ice-5:- ice-6:- ice-1:ICEBOX "
assert_eq "idle: days since a claim was touched, past 7" "$(printf '%s\n' "$out" | cut -f1,10 | tr '\t\n' ': ')" \
  "ice-2:- ice-3:23 ice-4:- ice-5:- ice-6:- ice-1:- "
assert_eq "summary: icebox apart from open, idle claims counted" "$("$WB" summary "$T/store")" "open 5 · icebox 1 · claimed 3 (1 idle)"
reset_bd; python3 - "$FX/waves.json" "$FAKE_BD_DIR/stdout" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
d.append({"id": "acme-i1", "title": "Iced", "status": "open", "priority": 2, "labels": ["icebox"]})
json.dump(d, open(sys.argv[2], "w"))
EOF
assert_eq "summary with waves: icebox at the end" "$("$WB" summary "$T/store")" "NOW 2 · NEXT 1 · claimed 1 · icebox 1"

reset_bd
"$WB" list "$T/nostore" >/dev/null; rc=$?
assert_eq "no .beads exits 21" "$rc" "21"
if [ ! -f "$FAKE_BD_DIR/calls" ]; then ok "no .beads: bd not called"; else bad "bd was called without .beads"; fi
assert_eq "no-store summary" "$("$WB" summary "$T/nostore")" "(no bead store)"

# .beads higher up in the same git repo counts (a root can be a subfolder); above the repo it doesn't.
mkdir -p "$T/repo/.git" "$T/repo/projects/app" "$T/outer/proj/.git"; mkstore "$T/repo" "$T/outer"
reset_bd; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout"
assert_eq ".beads at the repo top counts for a subfolder root" "$("$WB" summary "$T/repo/projects/app")" "open 2 · claimed 0"
assert_eq ".beads above the repo does not count" "$("$WB" summary "$T/outer/proj")" "(no bead store)"
mkstore "$T/home"; mkdir -p "$T/home/dev/loose"
assert_eq "outside any repo, ~/.beads does not count" "$(HOME="$T/home" "$WB" summary "$T/home/dev/loose")" "(no bead store)"
# A .beads without bd's config (old exports left behind) is not a store, as bd skips it too.
mkdir -p "$T/left/.git" "$T/left/.beads"; : > "$T/left/.beads/issues.jsonl"
assert_eq "a leftover .beads is not a store" "$("$WB" summary "$T/left")" "(no bead store)"
mkdir -p "$T/repo/projects/.beads"; : > "$T/repo/projects/.beads/issues.jsonl"
assert_eq "a leftover nearer the root doesn't hide the real store" "$("$WB" summary "$T/repo/projects/app")" "open 2 · claimed 0"

WB_BD=/nonexistent/bd "$WB" list "$T/store" >/dev/null; rc=$?
assert_eq "bd missing exits 20" "$rc" "20"
assert_eq "bd missing summary" "$(WB_BD=/nonexistent/bd "$WB" summary "$T/store")" "(bd not installed)"

reset_bd
cat > "$FAKE_BD_DIR/stdout" <<'EOF'
[{"id":"bee-7","title":"Claimed twice","status":"in_progress","priority":1,
  "notes":"Branch: feat/a (worktree at /x/old)\nBranch: feat/a (worktree at /x/wt dir/new)"}]
EOF
assert_eq "claim notes: the newest worktree, spaces kept" \
  "$("$WB" list "$T/store" | cut -f8)" "/x/wt dir/new"

reset_bd
cat > "$FAKE_BD_DIR/stdout" <<'EOF'
[{"id":"bee-old","title":"Old","status":"in_progress","updated_at":"2026-10-01T10:00:00Z",
  "notes":"Branch: feat/a (worktree at /x/wt)"},
 {"id":"bee-new","title":"New","status":"in_progress","updated_at":"2026-10-20T10:00:00Z",
  "notes":"Branch: feat/a (worktree at /x/wt)"}]
EOF
assert_eq "claimed: two beads name the worktree, the newest update wins" "$("$WB" claimed "$T/store" /x/wt)" "bee-new"

# new-session's link also rides in the bead's metadata, which a notes rewrite (bd update --notes) can't drop
reset_bd
cat > "$FAKE_BD_DIR/stdout" <<'EOF'
[{"id":"bee-m","title":"Rewritten","status":"in_progress","priority":1,
  "notes":"Branch: feat/m. All rewritten since.","metadata":{"wb_worktree":"/x/meta wt"}},
 {"id":"bee-both","title":"Moved on","status":"in_progress","priority":2,
  "notes":"Branch: feat/a (worktree at /x/stale)","metadata":{"wb_worktree":"/x/current"}}]
EOF
assert_eq "claimed: from the metadata when the notes were rewritten" "$("$WB" claimed "$T/store" "/x/meta wt")" "bee-m"
assert_eq "list: the worktree from the metadata" "$("$WB" list "$T/store" | cut -f8 | head -1)" "/x/meta wt"
assert_eq "claimed: the metadata wins over an older notes line" "$("$WB" claimed "$T/store" /x/current)" "bee-both"
"$WB" claimed "$T/store" /x/stale >/dev/null; assert_eq "claimed: the superseded notes line no longer resolves" "$?" "1"
FAKE_BD_LOG="$T/claimed.log" "$WB" claimed "$T/store" /x/current >/dev/null
assert_contains "claimed: reads closed beads too (a finished worktree's bead is closed)" "$(cat "$T/claimed.log")" "list -n 0 --json --all"

# grooming's own writes (an attention flag on a claim) don't count as touching it: the
# stamp a grooming apply or undo left walks back to the one before, through the run records
reset_bd; python3 - "$FAKE_BD_DIR/stdout" "$WB_GROOM_DIR" "$T/store" <<'EOF'
import json, os, sys, datetime
ago = lambda d: (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=d, hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
stamp = lambda d, s: ago(d)[:-3] + s + "Z"  # a second no other bead has
out, base, root = sys.argv[1:]
json.dump([
  {"id": "gt-1", "title": "Flagged then unflagged", "status": "in_progress", "priority": 1, "updated_at": stamp(0, "01"),
   "notes": "Branch: a (worktree at /x/gt)"},
  {"id": "gt-2", "title": "Touched since grooming", "status": "in_progress", "priority": 2, "updated_at": ago(1)},
  {"id": "gt-3", "title": "Flag undone", "status": "in_progress", "priority": 3, "updated_at": stamp(0, "02")},
  {"id": "gt-4", "title": "Newer claim on the same worktree", "status": "in_progress", "priority": 4, "updated_at": ago(3),
   "notes": "Branch: a (worktree at /x/gt)"},
  {"id": "gt-5", "title": "Another space's record", "status": "in_progress", "priority": 4, "updated_at": ago(2)},
], open(out, "w"))
def run(space, name, root, rows, undone=()):
    d = os.path.join(base, space, name); os.makedirs(d)
    w = lambda f, rs: open(os.path.join(d, f), "w").write("".join(json.dumps(r) + "\n" for r in rs))
    w("before.jsonl", [{"id": i, "step": s, "updated_at": b} for i, s, b, _ in rows])
    w("applied.jsonl", [{"id": i, "step": s, "root": root, "updated_at": a} for i, s, _, a in rows])
    w("undone.jsonl", list(undone))
run("acme", "20261001-0600", root, [("gt-1", "s1", ago(30), stamp(10, "30")), ("gt-2", "s1", ago(30), stamp(9, "30")),
                                     ("gt-3", "s1", ago(20), stamp(8, "30"))],
    [{"id": "gt-3", "through": 1, "updated_at": stamp(0, "02")}])
run("acme", "20261008-0600", root, [("gt-1", "s2", stamp(10, "30"), stamp(0, "01"))])
run("acme", "20261015-0600", root, [("gt-1", "s3", stamp(0, "01"), stamp(0, "01"))])  # a write that failed: no change
run("other", "20261001-0600", "/elsewhere", [("gt-5", "x", ago(40), ago(2))])
EOF
out="$("$WB" list "$T/store")"
assert_eq "touched: grooming's writes are walked back; a later touch and another space's record are not" \
  "$(printf '%s\n' "$out" | cut -f1,10 | tr '\t\n' ': ')" "gt-1:30 gt-2:- gt-3:20 gt-4:- gt-5:- "
assert_eq "touched: an idle claim grooming flagged is counted idle" "$("$WB" summary "$T/store")" "open 5 · claimed 5 (2 idle)"
assert_eq "touched: claimed breaks the tie on the last real touch, not grooming's" "$("$WB" claimed "$T/store" /x/gt)" "gt-4"

reset_bd
cat > "$FAKE_BD_DIR/stdout" <<EOF
[{"id":"bee-9","title":"tab\there \$(touch $T/pwned) \"q\"\nnext","status":"open","priority":1,"description":"\$(touch $T/pwned)"}]
EOF
out="$("$WB" list "$T/store" --snapshot "$T/snap2.json")"
assert_eq "hostile title is cleaned into one row of 13 fields" "$(printf '%s\n' "$out" | awk -F'\t' '{print NR":"NF}')" "1:13"
prev="$("$WB" preview "$T/snap2.json" bee-9)"
assert_contains "hostile description shown literally" "$prev" "\$(touch $T/pwned)"
if [ ! -e "$T/pwned" ]; then ok "hostile title is cleaned and not executed"; else bad "something executed the title"; fi
# start here: the top three ready beads, each with why (field 11: rank, then reasons)
reset_bd; python3 - "$FAKE_BD_DIR/stdout" <<'EOF'
import json, sys, datetime
ago = lambda d: (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=d, hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
blocks = lambda i: [{"issue_id": "x", "depends_on_id": i, "type": "blocks"}]
json.dump([
  {"id": "st-01", "title": "Plain", "status": "open", "priority": 2},
  {"id": "st-02", "title": "Fresh claim", "status": "in_progress", "priority": 3, "updated_at": ago(1)},
  {"id": "st-03", "title": "Idle claim", "status": "in_progress", "priority": 1, "updated_at": ago(20)},
  {"id": "st-04", "title": "Iced", "status": "open", "priority": 0, "labels": ["icebox"]},
  {"id": "st-05", "title": "An epic", "status": "open", "priority": 0, "issue_type": "epic"},
  {"id": "st-06", "title": "Marked blocked", "status": "blocked", "priority": 0},
  {"id": "st-07", "title": "Waits on st-01", "status": "open", "priority": 0, "dependencies": blocks("st-01")},
  {"id": "st-08", "title": "Blocker closed", "status": "open", "priority": 0, "dependencies": blocks("st-gone"),
   "description": "Why.\n\nDone when: the thing ships."},
  {"id": "st-09", "title": "Child", "status": "open", "priority": 0,
   "dependencies": [{"issue_id": "st-09", "depends_on_id": "st-05", "type": "parent-child"}],
   "acceptance_criteria": "It works."},
  {"id": "st-10", "title": "Now", "status": "open", "priority": 2, "labels": ["wave:1"]},
  {"id": "st-11", "title": "No timestamp claim", "status": "in_progress", "priority": 4},
], open(sys.argv[1], "w"))
EOF
out="$("$WB" list "$T/store")"
assert_eq "start here: a fresh claim, then NOW, then priority; icebox, epics and blocked beads are never picked" \
  "$(printf '%s\n' "$out" | awk -F'\t' '$11 != "-" {print $1 "=" $11}' | sort -t= -k2 | tr '\n' '|')" \
  "st-02=1 resume · P3 · shape first|st-10=2 NOW · P2 · shape first|st-08=3 P0|"
reset_bd; cat > "$FAKE_BD_DIR/stdout" <<'EOF'
[{"id":"tb-1","title":"a","status":"open","priority":2},
 {"id":"tb-2","title":"b","status":"open","priority":2,"description":"- **Done when** the tests pass"},
 {"id":"tb-3","title":"c","status":"open","priority":2},
 {"id":"tb-4","title":"d","status":"open","priority":2},
 {"id":"tb-5","title":"e","status":"open","priority":3,"dependencies":[{"issue_id":"tb-5","depends_on_id":"tb-3","type":"blocks"}]}]
EOF
assert_eq "start here ties: a done line first, then what unblocks the most" \
  "$("$WB" list "$T/store" | awk -F'\t' '$11 != "-" {print $1 "=" $11}' | sort -t= -k2 | tr '\n' '|')" \
  "tb-2=1 P2|tb-3=2 P2 · unblocks 1 · shape first|tb-1=3 P2 · shape first|"
reset_bd; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout"
assert_eq "start here: none in a backlog of three or fewer, it's all on screen" \
  "$("$WB" list "$T/store" | cut -f11 | sort -u)" "-"

# one fresh claim at most: the rest of the picks are fresh work, not a pile of tabs
reset_bd; python3 - "$FAKE_BD_DIR/stdout" <<'EOF2'
import json, sys, datetime
ago = lambda d: (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=d, hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump([{"id": f"fc-{i}", "title": "claim", "status": "in_progress", "priority": 1, "updated_at": ago(1)} for i in range(1, 5)]
          + [{"id": f"fo-{i}", "title": "open", "status": "open", "priority": 2} for i in range(1, 3)],
          open(sys.argv[1], "w"))
EOF2
out="$("$WB" list "$T/store")"
assert_eq "picks: at most one fresh claim" \
  "$(printf '%s\n' "$out" | awk -F'\t' '$11 != "-" {print $1 "=" $11}' | sort -t= -k2 | tr '\n' '|')" \
  "fc-1=1 resume · P1 · shape first|fo-1=2 P2 · shape first|fo-2=3 P2 · shape first|"

# attention: beads flagged for the planning rituals, ranked apart from the picks
reset_bd; cat > "$FAKE_BD_DIR/stdout" <<'EOF2'
[{"id":"at-1","title":"due","status":"open","priority":2,"labels":["attention"],"notes":"x\nattention: old\nattention: due Nov 2 · money"},
 {"id":"at-2","title":"urgent","status":"open","priority":1,"labels":["attention"]},
 {"id":"at-3","title":"iced","status":"open","priority":3,"labels":["icebox","attention"]},
 {"id":"at-4","title":"a","status":"open","priority":1},
 {"id":"at-5","title":"b","status":"open","priority":2},
 {"id":"at-6","title":"c","status":"open","priority":3}]
EOF2
out="$("$WB" list "$T/store")"
assert_eq "attention: field 12 ranks flagged beads by priority, reason from the last attention note" \
  "$(printf '%s\n' "$out" | cut -f1,12 | sort | tr '\t\n' ':|')" \
  "at-1:2 due Nov 2 · money|at-2:1 attention|at-3:3 attention|at-4:-|at-5:-|at-6:-|"
assert_eq "attention: never also a pick" \
  "$(printf '%s\n' "$out" | awk -F'\t' '$11 != "-" && $12 != "-"' | wc -l | tr -d ' ')" "0"
assert_eq "attention: the others are still picked" \
  "$(printf '%s\n' "$out" | awk -F'\t' '$11 != "-" {print $1}' | sort | tr '\n' ' ')" "at-4 at-5 at-6 "
assert_eq "summary: attention first" "$("$WB" summary "$T/store")" "! 3 need attention · open 5 · icebox 1 · claimed 0"

# attention on a deferred bead still shows (the launcher hides deferred beads otherwise); closed never
reset_bd; cat > "$FAKE_BD_DIR/stdout" <<'EOF2'
[{"id":"dd-1","title":"later","status":"deferred","priority":1,"labels":["attention"],"notes":"attention: due Nov 2 · money"},
 {"id":"dd-2","title":"done","status":"closed","priority":1,"labels":["attention"]},
 {"id":"dd-3","title":"quiet deferral","status":"deferred","priority":1},
 {"id":"dd-4","title":"open","status":"open","priority":2,"labels":["attention"]}]
EOF2
out="$("$WB" list "$T/store")"
assert_eq "attention: a deferred bead is listed with its reason and ' · deferred'; closed and quiet deferrals are not" \
  "$(printf '%s\n' "$out" | cut -f1,12 | sort | tr '\t\n' ':|')" "dd-1:1 due Nov 2 · money · deferred|dd-4:2 attention|"
assert_eq "attention: a deferred bead is never a pick" "$(printf '%s\n' "$out" | awk -F'\t' '$1=="dd-1" {print $11}')" "-"
assert_eq "summary: a deferred attention bead counts" "$("$WB" summary "$T/store")" "! 2 need attention · open 1 · claimed 0"

# a deferral whose date has passed is back: listed in its section, tagged, counted, pickable;
# one dated in the future, or with no date (dd-3 above), stays hidden
reset_bd; cat > "$FAKE_BD_DIR/stdout" <<'EOF2'
[{"id":"df-1","title":"past due","status":"deferred","priority":1,"labels":["wave:1"],"defer_until":"2020-01-01T00:00:00Z"},
 {"id":"df-2","title":"not yet","status":"deferred","priority":0,"labels":["wave:1"],"defer_until":"2099-01-01T00:00:00Z"},
 {"id":"df-3","title":"date only","status":"deferred","priority":2,"defer_until":"2020-03-04"},
 {"id":"df-4","title":"bad date","status":"deferred","priority":2,"defer_until":"soon"},
 {"id":"df-5","title":"open","status":"open","priority":2}]
EOF2
out="$("$WB" list "$T/store")"; rc=$?
assert_eq "deferred past due: list ok" "$rc" "0"
assert_eq "deferred past due: in its section with the date in field 13; future and bad dates hidden" \
  "$(printf '%s\n' "$out" | cut -f1,3,5,13 | tr '\t\n' ':|')" "df-1:○:NOW:2020-01-01|df-3:○:-:2020-03-04|df-5:○:-:-|"
assert_eq "summary: past-due deferrals are counted, future ones are not" "$("$WB" summary "$T/store")" \
  "NOW 1 · NEXT 0 · claimed 0"
reset_bd; cat > "$FAKE_BD_DIR/stdout" <<'EOF2'
[{"id":"df-6","title":"past due","status":"deferred","priority":1,"defer_until":"2020-01-01T00:00:00Z"},
 {"id":"df-7","title":"not yet","status":"deferred","priority":1,"defer_until":"2099-01-01T00:00:00Z"},
 {"id":"df-8","title":"a","status":"open","priority":3},{"id":"df-9","title":"b","status":"open","priority":3},
 {"id":"df-10","title":"c","status":"open","priority":3}]
EOF2
assert_eq "summary without waves: only the past-due deferral counts" "$("$WB" summary "$T/store")" "open 4 · claimed 0"
assert_eq "deferred past due: a pick like any open bead" \
  "$("$WB" list "$T/store" | awk -F'\t' '$1=="df-6" {print $11}')" "1 P1 · shape first"

# the 30-day flow: beads created vs closed, closed ones read apart (bd hides them)
reset_bd; python3 - "$FAKE_BD_DIR" <<'EOF'
import json, sys, datetime
ago = lambda d: (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=d)).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump([{"id": f"fl-{i}", "title": "t", "status": "open", "priority": 2, "created_at": ago(d)}
           for i, d in enumerate([1, 5, 29, 31, 90])], open(sys.argv[1] + "/stdout", "w"))
json.dump([{"id": f"fc-{i}", "title": "t", "status": "closed", "created_at": ago(d), "closed_at": ago(1)}
           for i, d in enumerate([2, 40])], open(sys.argv[1] + "/closed", "w"))
EOF
"$WB" list "$T/store" --flow "$T/flow" >/dev/null
assert_eq "flow: created in 30 days (open or since closed) vs closed" "$(cat "$T/flow")" "last 30 days: +2 · 4 created, 2 closed"
reset_bd; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout"; rm -f "$T/flow"
"$WB" list "$T/store" --flow "$T/flow" >/dev/null
if [ ! -e "$T/flow" ]; then ok "flow: nothing created or closed, nothing to say"; else bad "flow: wrote $(cat "$T/flow")"; fi
"$WB" list "$T/store" >/dev/null
if [ ! -e "$T/flow" ]; then ok "flow: only read when asked for"; else bad "flow written unasked"; fi
reset_bd; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout"; echo 'junk' > "$FAKE_BD_DIR/closed"; rm -f "$T/flow"
"$WB" list "$T/store" --flow "$T/flow" >/dev/null; rc=$?
assert_eq "flow: an unreadable closed read leaves the list alone" "$rc" "0"
assert_eq "flow: and writes nothing rather than a wrong count" "$(cat "$T/flow" 2>/dev/null)" ""
finish
