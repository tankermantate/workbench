#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
unset FAKE_BD_DIR   # fake bd reads each store's .beads/fake.json
export WORKBENCH_DRY_RUN=1 FAKE_NS_LOG="$T/ns.log" FAKE_NS_DIR="$T/wt/proj" XDG_STATE_HOME="$T/state"
export WORKBENCH_CONFIG="$T/spaces.toml" WB_STATE_DIR="$T/wbstate"
export WB_GROOM_DIR="$T/groom" WB_PLANS_DIR="$T/plans"   # never the real ones
mkstore "$T/acme" "$T/side/beta"; mkdir -p "$T/side/gamma" "$T/start"
cp "$REPO/tests/fixtures/waves.json" "$T/acme/.beads/fake.json"
cp "$REPO/tests/fixtures/plain.json" "$T/side/beta/.beads/fake.json"
cat > "$WORKBENCH_CONFIG" <<EOF
[[space]]
name = "Acme"
root = "$T/acme"
beads = true
worktrees = true
session_cmd = "$REPO/tests/fake/new-session"
space_key = "acme"
claude_config = "$T/cfg"

[[space]]
name = "Side"
glob = "$T/side/*"
EOF
L() { (cd "$T/start" && zsh -f -c "source '$REPO/shell/workbench.zsh'; launch; print \"AFTER rc=\$? PWD=\$PWD\"" 2>&1); }

# wb-ui render-work: sections and kinds
printf 'Acme\t-\t%s\ttrue\t1\tx\tacme\t-\t-\t0\n' "$T/acme" > "$T/start/spaces.tsv"
out="$("$REPO/bin/wb-ui" render-work "$T/start" 1)"
assert_eq "render-work kinds and order" "$(printf '%s\n' "$out" | cut -f1,2 | tr '\n' ' ')" \
  "new	- sep	 open	acme-a2 open	acme-a1 open	acme-b1 sep	 open	acme-a2 open	acme-a1 sep	 open	acme-b1 sep	 open	acme-c1 open	acme-e1 claimed	acme-c2 "
assert_contains "render-work: start here first" "$(printf '%s\n' "$out" | sed -n 2p)" "── start here ──"
assert_contains "render-work: a pick says why, dim" "$(printf '%s\n' "$out" | sed -n 3p)" $'High wave-1  \e[2mNOW · P1 · shape first\e[0m'
assert_not_contains "render-work: no flow line when nothing was created or closed" "$out" "last 30 days"
assert_contains "render-work NOW header" "$out" "── NOW ──"
assert_contains "render-work everything-else header" "$out" "── everything else ──"
assert_contains "render-work claimed row keeps its worktree" "$out" "claimed	acme-c2	/tmp/wb-fixture-wt/acme-x"
# the epic column: the direct parent's title, "Epic:" dropped, dim, fixed width
# (a start-here pick is listed twice; row is the one in its own section)
row() { printf '%s\n' "$1" | awk -F'\t' -v id="$2" '$2==id {r=$5} END {print r}'; }
assert_eq "epic column: a child shows its parent" "$(row "$out" acme-a1)" \
  $'○ a1     P2  \e[2mtidy the shop       \e[0m  Low wave-1'
assert_eq "epic column: no parent, blank but aligned" "$(row "$out" acme-b1)" \
  "○ b1     P0                        Wave-2 urgent"
# a past-due deferral ends its row with the date, dim
mkstore "$T/dfr"; mkdir -p "$T/dfrs"
cat > "$T/dfr/.beads/fake.json" <<'EOF'
[{"id":"dfr-1","title":"Back again","status":"deferred","priority":2,"defer_until":"2020-01-01T00:00:00Z"},
 {"id":"dfr-2","title":"Still later","status":"deferred","priority":2,"defer_until":"2099-01-01T00:00:00Z"}]
EOF
printf 'Dfr\t-\t%s\ttrue\t1\tx\tdfr\t-\t-\t0\n' "$T/dfr" > "$T/dfrs/spaces.tsv"
dout="$("$REPO/bin/wb-ui" render-work "$T/dfrs" 1)"
assert_eq "render-work: a past-due deferral is an open row tagged with its date, dim" "$(row "$dout" dfr-1)" \
  $'○ 1      P2  Back again  \e[2mdeferred until 2020-01-01\e[0m'
assert_not_contains "render-work: a future deferral is not listed" "$dout" "dfr-2"
# a blocked bead: its own mark, and the row ends with what blocks it, dim
mkstore "$T/blk"; mkdir -p "$T/blks"
cat > "$T/blk/.beads/fake.json" <<'EOF'
[{"id":"blk-1","title":"Setup","status":"open","priority":1},
 {"id":"blk-2","title":"Guide","status":"open","priority":2,"dependencies":[{"issue_id":"blk-2","depends_on_id":"blk-1","type":"blocks"}]},
 {"id":"blk-3","title":"Claimed guide","status":"in_progress","priority":2,"dependencies":[{"issue_id":"blk-3","depends_on_id":"blk-1","type":"blocks"}]}]
EOF
printf 'Blk\t-\t%s\ttrue\t1\tx\tblk\t-\t-\t0\n' "$T/blk" > "$T/blks/spaces.tsv"
bout="$("$REPO/bin/wb-ui" render-work "$T/blks" 1)"
assert_eq "render-work: a blocked bead is ⊘, ending with its blockers, dim" "$(row "$bout" blk-2)" \
  $'⊘ 2      P2  Guide  \e[2mblocked by 1\e[0m'
assert_eq "render-work: a blocked claim stays a claimed ◐ row" \
  "$(printf '%s\n' "$bout" | awk -F'\t' '$2=="blk-3" {print $1}') $(row "$bout" blk-3)" \
  $'claimed ◐ 3      P2  Claimed guide  \e[2mblocked by 1\e[0m'
assert_eq "render-work: a ready bead has no tag" "$(row "$bout" blk-1)" "○ 1      P1  Setup"
out="$("$REPO/bin/wb-ui" filter-work "$T/start" 1 'tidy')"
assert_eq "search: the parent's title is searched" "$(printf '%s\n' "$out" | cut -f1,2 | tr '\t\n' ': ')" \
  "new:- msg: open:acme-e1 open:acme-a2 open:acme-a1 "
assert_contains "search: a match in the column is highlighted" "$(row "$out" acme-a1)" $'\e[1;33mtidy\e[0m'
assert_eq "render-spaces: the q row has no stray dash" "$("$REPO/bin/wb-ui" render-spaces "$T/start" | tail -1)" "q	[q] just give me a shell	"

# wb-ui filter-work: words across title and description; every word first, then some
mkstore "$T/fab"; mkdir -p "$T/srch"
cat > "$T/fab/.beads/fake.json" <<'EOF'
[
  {"id":"fab-1","title":"Fabric swatches","status":"open","priority":1,"description":"Pick three."},
  {"id":"fab-e","title":"EPIC: Fabric sourcing for the spring line","status":"closed","priority":2},
  {"id":"fab-2","title":"Fabric order","status":"open","priority":2,"description":"Raise PO 4471 with the mill.","parent":"fab-e"},
  {"id":"fab-3","title":"Fix a bug in the router","status":"open","priority":0,"description":"Comes up in the profile page."},
  {"id":"fab-4","title":"Deposit the report","status":"open","priority":3},
  {"id":"fab-5","title":"Fabric samples","status":"open","priority":0,"description":"Possibly next week."},
  {"id":"fab-6","title":"Chase the mill","status":"open","priority":2,"description":"Two POs are late."},
  {"id":"fab-7","title":"Update the policy page","status":"open","priority":2,"description":"Portal posts."}
]
EOF
printf 'Fab\t-\t%s\ttrue\t1\tx\tfab\t-\t-\t0\n' "$T/fab" > "$T/srch/spaces.tsv"
printf '[{"id":"fab-c","title":"Done","status":"closed","created_at":"%s","closed_at":"%s"}]' \
  "$(date -u -v-2d +%Y-%m-%dT%H:%M:%SZ)" "$(date -u -v-1d +%Y-%m-%dT%H:%M:%SZ)" > "$T/fab/.beads/fake-closed.json"
full="$("$REPO/bin/wb-ui" render-work "$T/srch" 1)"
assert_eq "render-work: the flow line closes the start-here section" \
  "$(printf '%s\n' "$full" | sed -n 6p | cut -f1,4)" "msg	last 30 days: 0 · 1 created, 1 closed"
assert_eq "render-work: picks P0 first, then P1" "$(printf '%s\n' "$full" | sed -n 3,5p | cut -f2 | tr '\n' ' ')" "fab-3 fab-5 fab-1 "
assert_contains "epic column: a long parent is cut to 20 with …" "$(row "$full" fab-2)" $'\e[2mFabric sourcing for…\e[0m'
rows() { printf '%s\n' "$1" | cut -f1,2 | tr '\t\n' ': '; }
out="$("$REPO/bin/wb-ui" filter-work "$T/srch" 1 'fabric PO')"
assert_eq "filter-work: all words, then some words, scattered letters never" "$(rows "$out")" \
  "new:- msg: sep: open:fab-2 sep: open:fab-5 open:fab-1 open:fab-6 "
assert_contains "filter-work: a count line" "$out" "1 match all words · 3 match some"
assert_contains "filter-work: all-words divider" "$out" "── all words ──"
assert_contains "filter-work: some-words divider" "$out" "── some words ──"
out="$("$REPO/bin/wb-ui" filter-work "$T/srch" 1 'po')"
assert_eq "filter-work: a 1-2 letter word matches whole or plural, any case" "$(rows "$out")" "new:- msg: open:fab-2 open:fab-6 "
assert_contains "filter-work: one word, a plain count" "$out" "2 match"
assert_not_contains "filter-work: one word, no dividers" "$out" "──"
out="$("$REPO/bin/wb-ui" filter-work "$T/srch" 1 "PO's")"
assert_eq "filter-work: an apostrophe doesn't split a word" "$(rows "$out")" "new:- msg: open:fab-2 open:fab-6 "
out="$("$REPO/bin/wb-ui" filter-work "$T/srch" 1 'fab')"
assert_eq "filter-work: a longer word matches from a word's start" "$(rows "$out")" "new:- msg: open:fab-5 open:fab-1 open:fab-2 "
out="$("$REPO/bin/wb-ui" filter-work "$T/srch" 1 'mill')"
assert_eq "filter-work: descriptions are searched; title matches come first" "$(rows "$out")" "new:- msg: open:fab-6 open:fab-2 "
out="$("$REPO/bin/wb-ui" filter-work "$T/srch" 1 '7')"
assert_eq "filter-work: a bead's short id is searched" "$(rows "$out")" "new:- msg: open:fab-7 "
assert_contains "filter-work: a matched id is highlighted, padding kept" "$out" $'○ \e[1;33m7\e[0m      P2'
assert_contains "filter-work: nothing found says so" "$("$REPO/bin/wb-ui" filter-work "$T/srch" 1 'zebra')" "no beads match"
out="$("$REPO/bin/wb-ui" filter-work "$T/srch" 1 'fabric')"
assert_contains "filter-work: matched words are highlighted" "$out" $'\e[1;33mFabric\e[0m order'
assert_not_contains "filter-work: no colour outside the shown text" "$(printf '%s\n' "$out" | cut -f1-4)" $'\e'
assert_eq "filter-work: empty query is the full list, uncoloured" "$("$REPO/bin/wb-ui" filter-work "$T/srch" 1 '')" "$full"
assert_not_contains "render-work: no highlights" "$full" $'\e[1;33m'

# ids longer than 6 (a sub-epic's children: "abcd.12") still line up the columns
mkstore "$T/dot"; mkdir -p "$T/dotui"
cat > "$T/dot/.beads/fake.json" <<'EOF2'
[
  {"id":"dot-1","title":"Short id","status":"open","priority":1,"parent":"dot-e"},
  {"id":"dot-abcd.123","title":"Long id","status":"open","priority":2,"parent":"dot-e"},
  {"id":"dot-e","title":"The epic","status":"closed","priority":2}
]
EOF2
printf 'Dot\t-\t%s\ttrue\t1\tx\tdot\t-\t-\t0\n' "$T/dot" > "$T/dotui/spaces.tsv"
cols="$("$REPO/bin/wb-ui" render-work "$T/dotui" 1 | grep -E '^open' | cut -f5 | sed $'s/\e\\[[0-9;]*m//g' | awk '{print index($0, "The epic")}' | sort -u | wc -l | tr -d ' ')"
assert_eq "epic column: lines up when an id is longer than 6" "$cols" "1"
assert_eq "render-work: no colour but the dim epic column" "$(printf '%s\n' "$full" | sed $'s/\e\\[2m//g; s/\e\\[0m//g' | grep -c $'\e')" "0"
out="$("$REPO/bin/wb-ui" filter-work "$T/start" 1 'wave')"
assert_eq "filter-work: section headers give way to the count while searching" "$(rows "$out")" \
  "new:- msg: open:acme-a2 open:acme-a1 open:acme-b1 "

# icebox: its own section, last; an idle claim says how long
mkstore "$T/ice"; mkdir -p "$T/iceui"
python3 - "$T/ice/.beads/fake.json" <<'EOF3'
import json, sys, datetime
ago = lambda d: (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=d, hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump([
  {"id": "ice-1", "title": "Someday", "status": "open", "priority": 0, "labels": ["icebox"]},
  {"id": "ice-2", "title": "Live open", "status": "open", "priority": 1},
  {"id": "ice-3", "title": "Forgotten tab", "status": "in_progress", "priority": 2, "updated_at": ago(23)},
], open(sys.argv[1], "w"))
EOF3
printf 'Ice\t-\t%s\ttrue\t1\tx\tice\t-\t-\t0\n' "$T/ice" > "$T/iceui/spaces.tsv"
out="$("$REPO/bin/wb-ui" render-work "$T/iceui" 1)"
assert_eq "render-work: icebox under its own divider, last" "$(rows "$out")" "new:- sep: open:ice-2 claimed:ice-3 sep: open:ice-1 "
assert_contains "render-work: the icebox divider" "$out" "── icebox ──"
assert_contains "render-work: an idle claim says how long, dim" "$(row "$out" ice-3)" $'Forgotten tab  \e[2midle 23d\e[0m'
assert_not_contains "render-work: a fresh row has no idle tag" "$(row "$out" ice-2)" "idle"

# attention: flagged beads lead start-here, five then a count, even in a tiny backlog
mkstore "$T/att"; mkdir -p "$T/attui"
python3 - "$T/att/.beads/fake.json" <<'EOF4'
import json, sys
beads = [{"id": f"att-{i}", "title": f"Flagged {i}", "status": "open", "priority": i % 3 + 1,
          "labels": ["attention"], "notes": "attention: due Nov 2 · money" if i == 1 else ""} for i in range(1, 8)]
json.dump(beads, open(sys.argv[1], "w"))
EOF4
printf 'Att\t-\t%s\ttrue\t1\tx\tatt\t-\t-\t0\n' "$T/att" > "$T/attui/spaces.tsv"
out="$("$REPO/bin/wb-ui" render-work "$T/attui" 1)"
assert_eq "render-work: attention first, five then a count" \
  "$(printf '%s\n' "$out" | sed -n 2,8p | cut -f1,2 | tr '\t\n' ': ')" "sep: open:att-3 open:att-6 open:att-1 open:att-4 open:att-7 msg: "
assert_contains "render-work: the count line" "$(printf '%s\n' "$out" | sed -n 8p)" "+2 more need attention"
assert_contains "render-work: attention reason dim with !" "$(printf '%s\n' "$out" | awk -F'\t' '$2=="att-1" {print $5; exit}')" $'\e[2m! due Nov 2 · money\e[0m'
assert_eq "search: the word attention finds every flagged bead, even past the fifth" \
  "$("$REPO/bin/wb-ui" filter-work "$T/attui" 1 'attention' | grep -c $'^open')" "7"
assert_eq "search: the reason is searched too" "$("$REPO/bin/wb-ui" filter-work "$T/attui" 1 'money' | grep -c $'^open')" "1"
assert_contains "render-work: attention shown in a tiny backlog" "$out" "── start here ──"
assert_contains "render-work: every attention bead still sits in its section" "$(printf '%s\n' "$out" | sed -n '9,$p')" "att-2"

# fallback menu: Acme, then the first bead (item 2; item 1 is ✦ something new)
out="$(printf '1\n2\n' | WB_NO_FZF=1 L)"
assert_contains "menu screen 1 shows counts" "$out" "NOW 2 · NEXT 1 · claimed 1"
assert_contains "menu: fzf hint shown" "$out" "brew install fzf"
assert_eq "menu: bead goes through new-session" "$(tail -1 "$T/ns.log")" "acme-a2 --space acme --no-launch"
assert_contains "menu: launches in the worktree" "$out" "DRY-RUN: cd $T/wt/proj && env CLAUDE_CONFIG_DIR=$T/cfg WB_SPACE_ROOT="
assert_contains "menu: shell ends in the worktree" "$out" "AFTER rc=0 PWD=$T/wt/proj"
out="$(printf '1\n1\n' | WB_NO_FZF=1 L)"
assert_not_contains "fzf hint only once" "$out" "brew install fzf"
assert_eq "menu: something new uses the space key" "$(tail -1 "$T/ns.log")" "acme --no-launch"
out="$(printf '1\nr\n1\n' | WB_NO_FZF=1 L)"
assert_contains "menu: r re-reads then still picks" "$out" "DRY-RUN"
out="$(printf 'r\n1\n1\n' | WB_NO_FZF=1 L)"
assert_contains "menu: r on screen 1 re-reads then still picks" "$out" "DRY-RUN"
out="$(printf '7\n1\nx\n1\n' | WB_NO_FZF=1 L)"
assert_contains "menu: a mistyped answer asks again" "$out" "DRY-RUN"
assert_contains "menu: says what it wants" "$out" "type a number from the list"

# planning rituals: an unreviewed run and a due plan add to both screens
printf 'Acme\t-\t%s\ttrue\t1\tx\tacme\t-\t-\t0\n' "$T/acme" > "$T/start/spaces.tsv"
out="$("$REPO/bin/wb-ui" render-work "$T/start" 1)"
assert_not_contains "render-work: no review row without a run" "$out" "✦ review"
assert_not_contains "render-work: no strategy row without a plan" "$out" "✦ strategy"
"$REPO/bin/wb-ui" fill-counts "$T/start"; "$REPO/bin/wb-ui" render-spaces "$T/start" > "$T/screen1"
assert_not_contains "screen 1: nothing about grooming without a run" "$(cat "$T/screen1")" "groomed"
mkdir -p "$T/groom/Acme/20261017-0600" "$T/plans/Acme"
printf 'date: %s\n' "$(date +%Y-%m-%d)" > "$T/plans/Acme/goals.md"; printf 'labels: ws:money\n' > "$T/plans/Acme/protected.md"
out="$("$REPO/bin/wb-ui" render-work "$T/start" 1)"
assert_eq "render-work: the review row follows something new" "$(printf '%s\n' "$out" | sed -n 2p)" \
  "review	-	$T/groom/Acme/20261017-0600		✦ review Saturday's grooming"
assert_not_contains "render-work: a fresh plan has no strategy row" "$out" "✦ strategy"
assert_eq "filter-work keeps the ritual rows with no query" "$("$REPO/bin/wb-ui" filter-work "$T/start" 1 '' | sed -n 2p | cut -f1)" "review"
assert_not_contains "filter-work: a search shows only matches" "$("$REPO/bin/wb-ui" filter-work "$T/start" 1 'wave')" "✦ review"
"$REPO/bin/wb-ui" fill-counts "$T/start"; "$REPO/bin/wb-ui" render-spaces "$T/start" > "$T/screen1"
assert_contains "screen 1: groomed Sat · review, dim, after the counts" "$(cat "$T/screen1")" $'NOW 2 · NEXT 1 · claimed 1\e[2m · groomed Sat · review\e[0m'
# a partial run (the judge did not show it read the whole backlog) says so on both screens
printf 'the judge did not confirm it read the whole backlog\n' > "$T/groom/Acme/20261017-0600/partial"
"$REPO/bin/wb-ui" fill-counts "$T/start"; "$REPO/bin/wb-ui" render-spaces "$T/start" > "$T/screen1"
assert_contains "screen 1: a partial run says so" "$(cat "$T/screen1")" $'\e[2m · groomed Sat · partial · review\e[0m'
assert_eq "render-work: ... and so does its review row" "$("$REPO/bin/wb-ui" render-work "$T/start" 1 | sed -n 2p | cut -f5)" \
  "✦ review Saturday's grooming (partial: not the whole backlog)"
rm "$T/groom/Acme/20261017-0600/partial"
printf 'date: 2020-01-01\n' > "$T/plans/Acme/goals.md"
out="$("$REPO/bin/wb-ui" render-work "$T/start" 1)"
assert_eq "render-work: a due plan adds the strategy row after review" "$(printf '%s\n' "$out" | sed -n 3p | cut -f1,2,5)" "strategy	-	✦ strategy session"
"$REPO/bin/wb-ui" fill-counts "$T/start"; "$REPO/bin/wb-ui" render-spaces "$T/start" > "$T/screen1"
assert_contains "screen 1: both, in order" "$(cat "$T/screen1")" $'\e[2m · groomed Sat · review · strategy due\e[0m'
# a Saturday run that left no run dir (it failed early, or never started) shows on screen 1
mkdir -p "$T/agents"; : > "$T/agents/workbench.groom.plist"
WB_TODAY=2026-10-25 WB_LAUNCH_AGENTS_DIR="$T/agents" "$REPO/bin/wb-ui" fill-counts "$T/start"
"$REPO/bin/wb-ui" render-spaces "$T/start" > "$T/screen1"
assert_contains "screen 1: a missed run comes first and points at the log" "$(cat "$T/screen1")" \
  $'\e[2m · grooming missed Oct 24, see launchd.log · groomed Sat · review · strategy due\e[0m'
# a newest run that failed (nothing applied) says so instead of review, and names an expired login
mkdir -p "$T/groom/Acme/20261024-0600"; printf 'the judge failed (exit 1)\n' > "$T/groom/Acme/20261024-0600/summary.md"
: > "$T/groom/Acme/20261017-0600/reviewed"
WB_TODAY=2026-10-25 WB_LAUNCH_AGENTS_DIR="$T/agents" "$REPO/bin/wb-ui" fill-counts "$T/start"
"$REPO/bin/wb-ui" render-spaces "$T/start" > "$T/screen1"
assert_contains "screen 1: a failed run says so and points at its summary" "$(cat "$T/screen1")" \
  $'\e[2m · grooming failed Sat, see summary · strategy due\e[0m'
assert_not_contains "render-work: no review row for a failed run" "$("$REPO/bin/wb-ui" render-work "$T/start" 1)" "✦ review"
printf '{"is_error":true,"result":"Failed to authenticate: OAuth session expired"}' > "$T/groom/Acme/20261024-0600/judge.json"
"$REPO/bin/wb-ui" fill-counts "$T/start"; "$REPO/bin/wb-ui" render-spaces "$T/start" > "$T/screen1"
assert_contains "screen 1: an expired login says what to do" "$(cat "$T/screen1")" \
  $'\e[2m · grooming failed Sat: Claude login expired, log in again · strategy due\e[0m'
rm -rf "$T/groom/Acme/20261024-0600" "$T/groom/Acme/20261017-0600/reviewed"
# a status that fails or hangs never fails the screen
mkdir -p "$T/ui2/bin" "$T/ui2/lib"; cp "$REPO/bin/wb-ui" "$REPO/bin/wb-backlog" "$T/ui2/bin/"; cp "$REPO/lib/"*.py "$T/ui2/lib/"
printf '#!/bin/sh\nsleep 30\n' > "$T/ui2/bin/wb-groom"; chmod +x "$T/ui2/bin/wb-groom"
rm -rf "$T/start/counts"; s0=$SECONDS; "$T/ui2/bin/wb-ui" fill-counts "$T/start"
assert_contains "a hung wb-groom status adds nothing and the counts still land" "$(cat "$T/start/counts/1")" "NOW 2 · NEXT 1 · claimed 1"
assert_not_contains "... and says nothing about grooming" "$(cat "$T/start/counts/1")" "groomed"
if (( SECONDS - s0 < 20 )); then ok "... within a short timeout"; else bad "hung status was waited for"; fi
printf '#!/bin/sh\nexit 3\n' > "$T/ui2/bin/wb-groom"
rm -rf "$T/start/counts"; "$T/ui2/bin/wb-ui" fill-counts "$T/start"
assert_not_contains "a failing wb-groom status adds nothing" "$(cat "$T/start/counts/1")" "groomed"

# choosing them in the menu: Claude starts in the space with the prompt, run and plan filled in
FIRST_REVIEW="$(head -1 "$REPO/prompts/review.txt" | sed 's/{space}/Acme/; s/{run}.*//')"
out="$(printf '1\n2\n' | WB_NO_FZF=1 L)"
assert_contains "menu: review starts Claude in the space root" "$out" "DRY-RUN: cd $T/acme && env CLAUDE_CONFIG_DIR=$T/cfg WB_SPACE_ROOT="
assert_contains "menu: the review prompt opens as review.txt does" "$out" "$FIRST_REVIEW"
assert_contains "menu: ... with the run dir" "$out" "$T/groom/Acme/20261017-0600"
assert_contains "menu: ... and wb-groom apply with the plan dir" "$out" "$REPO/bin/wb-groom apply $T/groom/Acme/20261017-0600 $T/acme --plan $T/plans/Acme --proposal"
assert_not_contains "menu: no placeholder left in the prompt" "$out" "{run}"
assert_not_contains "menu: review is not a bead: WB_BEAD unset" "$out" "WB_BEAD="
assert_not_contains "menu: review makes no worktree" "$out" "--no-launch"
out="$(printf '1\n3\n' | WB_NO_FZF=1 L)"
FIRST_STRAT="$(head -1 "$REPO/prompts/strategy.txt" | sed 's/{space}/Acme/; s/{plan}.*//')"
assert_contains "menu: strategy opens as strategy.txt does" "$out" "$FIRST_STRAT"
assert_contains "menu: ... with the plan dir" "$out" "$T/plans/Acme"
assert_contains "menu: ... in the space root" "$out" "DRY-RUN: cd $T/acme && "
rm -rf "$T/plans/Acme"; mkdir -p "$T/groom/Acme/20261018-0600"
out="$(printf '1\n3\n' | WB_NO_FZF=1 L)"
assert_contains "menu: a strategy session on a space with no plan makes it from the templates" "$out" "$T/plans/Acme"
assert_eq "... the four files" "$(ls "$T/plans/Acme" | tr '\n' ' ')" "calendar.md goals.md protected.md sources.md "
# wb-groom strategy fails (the plans dir can't be made): back to the work screen, not out
: > "$T/blocker"
out="$(printf '1\n3\n\nq\n' | WB_NO_FZF=1 WB_PLANS_DIR="$T/blocker/plans" L)"
assert_contains "strategy fails: wb-groom's reason is shown" "$out" "wb-groom: cannot make $T/blocker/plans/Acme"
assert_contains "strategy fails: says so and waits" "$out" "workbench: the strategy session did not start"
assert_eq "strategy fails: the work screen comes back" "$(printf '%s\n' "$out" | grep -c '✦ strategy session')" "2"
assert_not_contains "strategy fails: Claude is not started" "$out" "DRY-RUN"
assert_contains "strategy fails: q then leaves a shell where it was" "$out" "AFTER rc=0 PWD=$T/start"
rm -rf "$T/groom" "$T/plans" "$T/blocker"

# test-pick path (stands in for fzf)
out="$(WB_TEST_PICK_SPACE='Side › beta' WB_TEST_PICK_WORK='First by priority' L)"
assert_contains "pick: plain space bead" "$out" "Work on bead bee-2 in beta."
assert_contains "pick: plain space has no config dir" "$out" "env -u CLAUDE_CONFIG_DIR WB_SPACE_ROOT="
assert_contains "pick: lands in the project" "$out" "AFTER rc=0 PWD=$T/side/beta"
out="$(WB_TEST_PICK_SPACE='Side › gamma' WB_TEST_PICK_WORK='something new' L)"
assert_contains "pick: no-store space still offers something new" "$out" "start something new in gamma"

# the tabs row (wb-xw0): on screen 1, after the spaces; its view is only shown when chosen, then back
export WB_PS="$REPO/tests/fake/fake-ps" FAKE_PS_OUT="$T/ps.out" FAKE_PS_LOG="$T/ps.log"
printf '  901     1 ttys901  -zsh\n' > "$FAKE_PS_OUT"; : > "$FAKE_PS_LOG"
out="$(printf 'q\n' | WB_NO_FZF=1 L)"
assert_contains "tabs row: in the numbered menu, after the three spaces" "$out" "4) ✦ open tabs"
assert_not_contains "tabs row: drawing the screen does not show the view" "$out" "plain shell"
out="$(printf '4\n\n1\n1\n' | WB_NO_FZF=1 L)"
assert_contains "tabs row: choosing it shows the tabs view" "$out" "plain shell"
assert_contains "tabs row: it waits before going back" "$out" "Press Enter to go back"
assert_eq "tabs row: back on screen 1" "$(printf '%s\n' "$out" | grep -c '✦ open tabs')" "2"
assert_contains "tabs row: a session still starts afterwards" "$out" "DRY-RUN"
out="$(printf '4\n\nq\n' | WB_NO_FZF=1 FAKE_PS_RC=1 L)"
assert_contains "tabs row: a failed view says why" "$out" "wb-tabs: can't read the process table"
assert_eq "tabs row: ... and still comes back" "$(printf '%s\n' "$out" | grep -c '✦ open tabs')" "2"
assert_contains "tabs row: ... and q leaves a shell" "$out" "AFTER rc=0 PWD=$T/start"
# no fzf: a picked tab has nowhere to go, so the numbered menu keeps the printed view
assert_contains "tabs row: the printed view has no field for fzf" "$(printf '4\n\nq\n' | WB_NO_FZF=1 L)" $'  plain shell\n'
# with fzf (wb-1nk): the view is a list. A fake fzf, as the real one is driven: screen 1 chooses the
# row, then each list answers with $T/answers' next line (a pattern to pick, or an exit code)
mkdir -p "$T/pickbin"
cat > "$T/pickbin/fzf" <<EOF
#!/bin/bash
if [ ! -e "$T/picked" ]; then : > "$T/picked"; grep '✦ open tabs'; exit; fi
case " \$* " in *"--prompt=Tabs"*) ;; *) exit 130 ;; esac
cat > "$T/list.in"; printf '%s\n' "\$*" > "$T/list.args"; echo call >> "$T/list.calls"
a=\$(sed -n "\$(wc -l < "$T/list.calls")p" "$T/answers")
case "\$a" in ''|[0-9]*) exit "\${a:-130}" ;; esac
grep -F -- "\$a" "$T/list.in" | head -1
EOF
chmod +x "$T/pickbin/fzf"
# two tabs: a plain shell, and a session stuck on a prompt
printf '  901     1 ttys901  -zsh\n  911     1 ttys911  -zsh\n  912   911 ttys911  claude\n' > "$FAKE_PS_OUT"
mkdir -p "$T/fakehome/.claude/sessions"
printf '{"pid":912,"sessionId":"s9","cwd":"%s","status":"waiting","waitingFor":"input needed"}' "$T/acme" > "$T/fakehome/.claude/sessions/912.json"
export FAKE_OSA_LOG="$T/osa.log" TERM_PROGRAM=Apple_Terminal
pick() { rm -f "$T/picked" "$T/list.calls"; : > "$T/list.calls"; : > "$FAKE_OSA_LOG"; printf '%s\n' "${@:2}" > "$T/answers"; out="$(printf "$1" | HOME="$T/fakehome" PATH="$T/pickbin:$PATH" L)"; }

pick '' 'input needed'
assert_contains "list: the tabs are offered" "$(cat "$T/list.in")" "plain shell"
assert_contains "list: the tty is hidden from view" "$(cat "$T/list.args")" "--with-nth=2"
assert_contains "list: starts on a tab, not the heading" "$(cat "$T/list.args")" "load:pos(2)"
assert_eq "list: picking a row jumps to its tab" "$(cat "$FAKE_OSA_LOG")" "ttys911"
assert_eq "list: a jump goes back to screen 1, not the list" "$(wc -l < "$T/list.calls" | tr -d ' ')" 1
assert_contains "list: screen 1 then leaves a shell" "$out" "AFTER rc=0 PWD=$T/start"

pick '' 130
assert_eq "list: esc jumps nowhere" "$(cat "$FAKE_OSA_LOG")" ""
assert_contains "list: esc is back at screen 1, then a shell" "$out" "AFTER rc=0 PWD=$T/start"

pick '' 'WAITING ON YOU' 130
assert_eq "list: a heading jumps nowhere" "$(cat "$FAKE_OSA_LOG")" ""
assert_eq "list: a heading stays on the list" "$(wc -l < "$T/list.calls" | tr -d ' ')" 2

export FAKE_OSA_OUT=gone
pick '\n' 'input needed' 130
assert_contains "list: a failed jump says why" "$out" "has closed"
assert_contains "list: ... and waits to be read" "$out" "Press Enter to go back"
assert_eq "list: ... and returns to the list" "$(wc -l < "$T/list.calls" | tr -d ' ')" 2
pick '' 'input needed' 130
assert_contains "list: EOF at that pause leaves a shell rather than looping" "$out" "AFTER rc=0 PWD=$T/start"
assert_eq "list: ... after one try" "$(wc -l < "$FAKE_OSA_LOG" | tr -d ' ')" 1
unset FAKE_OSA_OUT

FAKE_PS_RC=1 pick '\n' 130
assert_contains "list: an unreadable process table says why" "$out" "can't read the process table"
assert_contains "list: ... without offering an empty list" "$out" "Press Enter to go back"
assert_eq "list: ... or calling fzf" "$(wc -l < "$T/list.calls" | tr -d ' ')" 0

pick '\n' 2
assert_contains "list: fzf itself failing falls back to the printed view" "$out" "plain shell"
assert_contains "list: ... which waits" "$out" "Press Enter to go back"
unset FAKE_OSA_LOG TERM_PROGRAM
rm -f "$T/picked"; unset FAKE_PS_OUT FAKE_PS_LOG

# the yellow count (wb-pmr): from wb-tabs --waiting, on the space's row and the tabs row
mkdir -p "$T/ui3/bin" "$T/ui3/lib"; cp "$REPO"/bin/wb-ui "$REPO"/bin/wb-backlog "$T/ui3/bin/"; cp -R "$REPO"/lib/. "$T/ui3/lib/"
cat > "$T/ui3/bin/wb-tabs" <<'EOF'
#!/usr/bin/env bash
[ "$1" = --waiting ] || exit 9
[ -n "${FAKE_TABS_SLEEP:-}" ] && sleep "$FAKE_TABS_SLEEP"
[ -n "${FAKE_TABS_RC:-}" ] && exit "$FAKE_TABS_RC"
echo '{"total": 3, "spaces": {"Acme": 2}}'
EOF
chmod +x "$T/ui3/bin/wb-tabs"
rm -rf "$T/start3"; mkdir -p "$T/start3"; "$REPO/bin/wb-spaces" > "$T/start3/spaces.tsv"
"$T/ui3/bin/wb-ui" fill-counts "$T/start3"; S1=$("$T/ui3/bin/wb-ui" render-spaces "$T/start3")
assert_contains "waiting count: yellow, first on its space's row" "$(grep Acme <<<"$S1")" $'\t\e[33m2 waiting on you\e[0m · '
assert_not_contains "waiting count: not on another space's row" "$(grep -v 'Acme\|open tabs' <<<"$S1")" "waiting on you"
assert_contains "waiting count: the total on the tabs row" "$(grep 'open tabs' <<<"$S1")" $'\e[33m3 waiting on you\e[0m'
rm -rf "$T/start3/counts" "$T/start3/waiting.json"
"$T/ui3/bin/wb-ui" render-spaces "$T/start3" > "$T/screen3"; RC=$?
assert_eq "waiting count: not read yet, the screen still draws" "$RC" 0
assert_not_contains "waiting count: not read yet, none shown" "$(cat "$T/screen3")" "waiting on you"
"$T/ui3/bin/wb-ui" fill-counts "$T/start3"   # a good read first: a failed one must not leave it showing
FAKE_TABS_RC=1 "$T/ui3/bin/wb-ui" fill-counts "$T/start3"
assert_not_contains "waiting count: a failing wb-tabs adds nothing" "$("$T/ui3/bin/wb-ui" render-spaces "$T/start3")" "waiting on you"
assert_contains "waiting count: a failing wb-tabs leaves the other counts" "$("$T/ui3/bin/wb-ui" render-spaces "$T/start3")" "NOW"
rm -rf "$T/start3/counts"; s0=$SECONDS; FAKE_TABS_SLEEP=30 "$T/ui3/bin/wb-ui" fill-counts "$T/start3"
assert_eq "waiting count: a hung wb-tabs can't hold the screen" "$(( SECONDS - s0 < 10 ))" 1
assert_not_contains "waiting count: a hung wb-tabs adds nothing" "$("$T/ui3/bin/wb-ui" render-spaces "$T/start3")" "waiting on you"

# the tidy row (wb-kvx.22): worktrees whose PR merged after their session left. wb-tidy --count
# runs with the other counts; the row shows only when some are finished, and runs wb-tidy when chosen
cat > "$T/fake-tidy" <<'EOF'
#!/bin/sh
if [ "$1" = --count ]; then [ -n "${FAKE_TIDY_RC:-}" ] && exit "$FAKE_TIDY_RC"; echo "${FAKE_TIDY_COUNT:-2}"; exit 0; fi
echo "TIDY RAN $*"
EOF
chmod +x "$T/fake-tidy"; OLD_TIDY=$WB_TIDY; export WB_TIDY="$T/fake-tidy"
rm -rf "$T/start4"; mkdir -p "$T/start4"; "$REPO/bin/wb-spaces" > "$T/start4/spaces.tsv"
"$REPO/bin/wb-ui" fill-counts "$T/start4"; S4=$("$REPO/bin/wb-ui" render-spaces "$T/start4")
assert_eq "tidy row: after the tabs row, before q" "$(printf '%s\n' "$S4" | tail -2 | head -1)" "tidy	✦ 2 finished worktrees, tidy?	"
FAKE_TIDY_COUNT=1 "$REPO/bin/wb-ui" fill-counts "$T/start4"
assert_contains "tidy row: one is singular" "$("$REPO/bin/wb-ui" render-spaces "$T/start4")" "✦ 1 finished worktree, tidy?"
FAKE_TIDY_COUNT=0 "$REPO/bin/wb-ui" fill-counts "$T/start4"
assert_not_contains "tidy row: none finished, no row" "$("$REPO/bin/wb-ui" render-spaces "$T/start4")" "tidy?"
"$REPO/bin/wb-ui" fill-counts "$T/start4"; FAKE_TIDY_RC=1 "$REPO/bin/wb-ui" fill-counts "$T/start4"
assert_not_contains "tidy row: wb-tidy can't tell, no row (not an old count)" "$("$REPO/bin/wb-ui" render-spaces "$T/start4")" "tidy?"
out="$(printf 'q\n' | WB_NO_FZF=1 L)"
assert_contains "tidy row: in the numbered menu" "$out" "5) ✦ 2 finished worktrees, tidy?"
assert_not_contains "tidy row: drawing it runs nothing" "$out" "TIDY RAN"
out="$(printf '5\n\nq\n' | WB_NO_FZF=1 L)"
assert_contains "tidy row: choosing it runs wb-tidy" "$out" "TIDY RAN"
assert_contains "tidy row: it waits before going back" "$out" "Press Enter to go back"
assert_eq "tidy row: back on screen 1" "$(printf '%s\n' "$out" | grep -c 'finished worktrees, tidy?')" "2"
assert_contains "tidy row: q then leaves a shell" "$out" "AFTER rc=0 PWD=$T/start"
out="$(printf 'q\n' | FAKE_TIDY_COUNT=0 WB_NO_FZF=1 L)"
assert_not_contains "tidy row: none finished, not in the menu" "$out" "tidy?"
export WB_TIDY=$OLD_TIDY

# the close-out (wb-kvx.22): when Claude exits in a worktree, the launcher runs end-session --if-merged
# on it. Merged work with a closed bead goes, and the shell moves to the space root; anything else stays
setup_repo "$T/co" >/dev/null 2>&1; CO=$(cd "$T/co" && pwd -P)
git -C "$CO" worktree add -q -b feat/co "$CO-wt" 2>/dev/null; COW="$CO-wt"
out="$(WB_TEST_PICK_SPACE=Acme WB_TEST_PICK_WORK='High wave-1' FAKE_NS_DIR="$COW" L)"
assert_contains "close-out: runs after Claude, on the worktree" "$out" "DRY-RUN: $REPO/bin/end-session --if-merged $COW"
assert_eq "close-out: ... after Claude, not before" "$(printf '%s\n' "$out" | grep DRY-RUN | tail -1)" "DRY-RUN: $REPO/bin/end-session --if-merged $COW"
out="$(WB_TEST_PICK_SPACE=Acme WB_TEST_PICK_WORK='High wave-1' L)"
assert_not_contains "close-out: not in a folder that isn't a git worktree" "$out" "--if-merged"
# CO(ES-SCRIPT): the function itself, with a stand-in end-session, from inside the worktree
CO() { (cd "$COW" && WORKBENCH_DRY_RUN= WB_END_SESSION="$1" zsh -f -c "source '$REPO/shell/workbench.zsh'; s=(Co - $CO - 1); _wb_close_out $COW; print \"AFTER PWD=\$PWD\"" 2>&1); }
cat > "$T/es-keep" <<'EOF'
#!/bin/sh
echo "end-session: kept $(basename "$2"): 'feat/co' is not merged into main yet." >&2; exit 1
EOF
cat > "$T/es-end" <<'EOF'
#!/bin/sh
cd / && git -C "$(git -C "$2" rev-parse --path-format=absolute --git-common-dir)/.." worktree remove "$2" && echo "✓ session ended. Branch 'feat/co' is merged into main and was deleted."
EOF
chmod +x "$T/es-keep" "$T/es-end"
out="$(CO "$T/es-keep")"
assert_contains "close-out: unmerged says why" "$out" "kept co-wt: 'feat/co' is not merged into main yet."
assert_contains "close-out: unmerged stays in the worktree" "$out" "AFTER PWD=$COW"
out="$(CO "$T/es-end")"
assert_contains "close-out: merged says so" "$out" "✓ session ended."
assert_contains "close-out: merged moves the shell to the space root" "$out" "AFTER PWD=$CO"
assert_not_contains "close-out: ... not the removed folder" "$out" "AFTER PWD=$COW"
# the main checkout (review and strategy run there) is never ended
out="$(cd "$CO" && WORKBENCH_DRY_RUN=1 zsh -f -c "source '$REPO/shell/workbench.zsh'; s=(Co - $CO - 1); _wb_close_out $CO" 2>&1)"
assert_eq "close-out: never the main checkout" "$out" ""

# leaving
out="$(printf 'q\n' | WB_NO_FZF=1 L)"
assert_contains "q on screen 1 leaves a working shell" "$out" "AFTER rc=0 PWD=$T/start"
assert_not_contains "q starts nothing" "$out" "DRY-RUN"
out="$(WB_NO_FZF=1 L < /dev/null)"
assert_contains "EOF leaves a working shell" "$out" "AFTER rc=0 PWD=$T/start"
out="$(WB_TEST_PICK_SPACE='no such space' L)"
assert_contains "esc (no pick) leaves a working shell" "$out" "AFTER rc=0 PWD=$T/start"

out="$(WORKBENCH_CONFIG="$T/missing.toml" L)"
assert_contains "missing config: one line naming the file" "$out" "no config at $T/missing.toml"
assert_contains "missing config: still a shell" "$out" "AFTER rc=0"

# A division by zero raises a zsh error that the always block catches. (${x:?} would
# not do here: it exits a non-interactive shell outright.)
out="$( (cd "$T/start" && zsh -f -c "source '$REPO/shell/workbench.zsh'; _wb_main() { integer i=1/0 }; launch; print AFTER rc=\$?") 2>&1)"
assert_contains "an internal error is trapped" "$out" "launcher hit an error"
assert_contains "an internal error still leaves a shell" "$out" "AFTER rc=0"

# wb-k3v: inside $(...), _wb_fzf execs fzf, so no zsh waits on it. A waiting
# zsh livelocked at 100% CPU for days when the subshell around it died. The
# fake fzf prints its own pid; exec means it is the subshell's pid.
mkdir -p "$T/execbin"
printf '#!/bin/sh\necho "$$"\n' > "$T/execbin/fzf"; chmod +x "$T/execbin/fzf"
out="$(PATH="$T/execbin:$PATH" zsh -f -c "zmodload zsh/system; source '$REPO/shell/workbench.zsh'
  r=\$(print -n \"\$sysparams[pid] \"; _wb_fzf ''); print -r -- \$r
  _wb_fzf '' >/dev/null; print AFTER")"
read -r sub fzfpid _ <<< "$(printf '%s\n' "$out" | head -1)"
assert_eq "in a subshell, fzf replaces it (no zsh left waiting)" "$fzfpid" "$sub"
assert_contains "outside a subshell, the shell survives fzf" "$out" "AFTER"
finish
