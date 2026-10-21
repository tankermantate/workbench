#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
unset FAKE_BD_DIR   # fake bd reads each store's .beads/fake.json
export WORKBENCH_DRY_RUN=1 FAKE_NS_LOG="$T/ns.log" FAKE_NS_DIR="$T/wt/proj" XDG_STATE_HOME="$T/state"
export WORKBENCH_CONFIG="$T/spaces.toml"
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
  "new	- sep	 open	acme-a2 open	acme-a1 sep	 open	acme-b1 sep	 open	acme-c1 open	acme-e1 claimed	acme-c2 "
assert_contains "render-work NOW header" "$out" "── NOW ──"
assert_contains "render-work everything-else header" "$out" "── everything else ──"
assert_contains "render-work claimed row keeps its worktree" "$out" "claimed	acme-c2	/tmp/wb-fixture-wt/acme-x"
assert_eq "render-spaces: the q row has no stray dash" "$("$REPO/bin/wb-ui" render-spaces "$T/start" | tail -1)" "q	[q] just give me a shell	"

# wb-ui filter-work: words across title and description; every word first, then some
mkstore "$T/fab"; mkdir -p "$T/srch"
cat > "$T/fab/.beads/fake.json" <<'EOF'
[
  {"id":"fab-1","title":"Fabric swatches","status":"open","priority":1,"description":"Pick three."},
  {"id":"fab-2","title":"Fabric order","status":"open","priority":2,"description":"Raise PO 4471 with the mill."},
  {"id":"fab-3","title":"Fix a bug in the router","status":"open","priority":0,"description":"Comes up in the profile page."},
  {"id":"fab-4","title":"Deposit the report","status":"open","priority":3},
  {"id":"fab-5","title":"Fabric samples","status":"open","priority":0,"description":"Possibly next week."},
  {"id":"fab-6","title":"Chase the mill","status":"open","priority":2,"description":"Two POs are late."},
  {"id":"fab-7","title":"Update the policy page","status":"open","priority":2,"description":"Portal posts."}
]
EOF
printf 'Fab\t-\t%s\ttrue\t1\tx\tfab\t-\t-\t0\n' "$T/fab" > "$T/srch/spaces.tsv"
full="$("$REPO/bin/wb-ui" render-work "$T/srch" 1)"
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
assert_not_contains "render-work: no colour" "$full" $'\e'
out="$("$REPO/bin/wb-ui" filter-work "$T/start" 1 'wave')"
assert_eq "filter-work: section headers give way to the count while searching" "$(rows "$out")" \
  "new:- msg: open:acme-a2 open:acme-a1 open:acme-b1 "

# fallback menu: Acme, then the first bead (item 2; item 1 is ✦ something new)
out="$(printf '1\n2\n' | WB_NO_FZF=1 L)"
assert_contains "menu screen 1 shows counts" "$out" "NOW 2 · NEXT 1 · claimed 1"
assert_contains "menu: fzf hint shown" "$out" "brew install fzf"
assert_eq "menu: bead goes through new-session" "$(tail -1 "$T/ns.log")" "acme-a2 --space acme --no-launch"
assert_contains "menu: launches in the worktree" "$out" "DRY-RUN: cd $T/wt/proj && env CLAUDE_CONFIG_DIR=$T/cfg claude"
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

# test-pick path (stands in for fzf)
out="$(WB_TEST_PICK_SPACE='Side › beta' WB_TEST_PICK_WORK='First by priority' L)"
assert_contains "pick: plain space bead" "$out" "Work on bead bee-2 in beta."
assert_contains "pick: plain space has no config dir" "$out" "env -u CLAUDE_CONFIG_DIR claude"
assert_contains "pick: lands in the project" "$out" "AFTER rc=0 PWD=$T/side/beta"
out="$(WB_TEST_PICK_SPACE='Side › gamma' WB_TEST_PICK_WORK='something new' L)"
assert_contains "pick: no-store space still offers something new" "$out" "start something new in gamma"

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
finish
