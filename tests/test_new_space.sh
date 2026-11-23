#!/usr/bin/env bash
# + new space (wb-kvx.24.1): lib/wb_newspace.py and bin/wb-new-space.
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # paths come back real; macOS's /var is /private/var
NS() { python3 -c "import sys; sys.path.insert(0, '$REPO/lib'); import wb_newspace as n; $1"; }

# --- the pieces moved from wb-setup ---
assert_eq "unique_key: slug, then -2" "$(NS 'print(n.unique_key("My App", {"my-app"}))')" "my-app-2"
out="$(NS "print(n.space_toml({'name': 'Acme', 'root': '$T/a', 'beads': 'true', 'worktrees': True, 'space_key': 'acme', 'claude_config': '$T/cfg'}))")"
assert_contains "space_toml: the key" "$out" 'space_key = "acme"'
assert_contains "space_toml: the account" "$out" "claude_config = \"$T/cfg\""
out="$(NS "print(n.space_toml({'name': 'B', 'root': '$T/b', 'beads': 'true', 'worktrees': False}))")"
assert_not_contains "space_toml: no account line when unset" "$out" "claude_config"

mkdir -p "$T/a"
export WORKBENCH_CONFIG="$T/new/spaces.toml"
out="$(NS "print(n.append_spaces('$WORKBENCH_CONFIG', [{'name': 'Acme', 'root': '$T/a', 'beads': 'true', 'worktrees': True, 'space_key': 'acme'}], '$REPO/spaces.example.toml'))")"
assert_eq "append_spaces: ok on a missing file" "$out" "(True, '')"
assert_eq "append_spaces: made it with the header" "$(head -1 "$WORKBENCH_CONFIG")" "# workbench's spaces: one [[space]] per project folder the launcher offers. wb-setup wrote this;"
assert_eq "append_spaces: wb-spaces lists it" "$("$REPO/bin/wb-spaces" | cut -f1,7)" "Acme	acme"
cp "$WORKBENCH_CONFIG" "$T/before.toml"
out="$(NS "print(n.append_spaces('$WORKBENCH_CONFIG', [{'name': 'Dup', 'root': '$T/a', 'beads': 'true', 'worktrees': True, 'space_key': 'acme'}], '$REPO/spaces.example.toml'))")"
assert_contains "append_spaces: a config that won't read back fails" "$out" "(False, "
assert_contains "append_spaces: ... saying why" "$out" "space key 'acme' is used by more than one worktree space"
cmp -s "$WORKBENCH_CONFIG" "$T/before.toml" && ok "append_spaces: ... and the file is as it was" || bad "append_spaces: file changed"

# --- create(), through wb-new-space --json ---
# bd: init writes bd's own CLAUDE.md block and commits, as the real one does; FAKE_INIT_RC fails it
cat > "$T/bd-stub" <<'EOF'
#!/bin/sh
[ "$1" = init ] || exit 0
echo "$*" >> "${FAKE_BD_ARGS:-/dev/null}"
[ -n "${FAKE_INIT_RC:-}" ] && { echo "init broke"; exit "$FAKE_INIT_RC"; }
mkdir -p .beads && : > .beads/config.yaml
printf '# Project Instructions\n\n<!-- BEGIN BEADS -->\nbd block\n<!-- END BEADS -->\n' > CLAUDE.md
git add -A && git commit -qm "bd init"
EOF
chmod +x "$T/bd-stub"
export WB_BD="$T/bd-stub" WB_NEW_SPACE_PARENT="$T/dev"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
mkdir -p "$T/dev" "$T/side/existing" "$T/acme" "$T/cfg"
export WORKBENCH_CONFIG="$T/spaces.toml"
cat > "$WORKBENCH_CONFIG" <<EOF
[[space]]
name = "Acme"
root = "$T/acme"
beads = true
worktrees = true
space_key = "acme"

[[space]]
name = "Side"
glob = "$T/side/*"
EOF
NEW="$REPO/bin/wb-new-space"
J() { python3 -c "import json, sys; d = json.load(sys.stdin); print($1)" <<<"$out"; }
row() { "$REPO/bin/wb-spaces" 2>/dev/null | awk -F'\t' -v l="$1" '$1==l'; }

export FAKE_BD_ARGS="$T/bd-args"
out="$("$NEW" --json --kind tool --name "My App")"; rc=$?
# bd names its database after the folder and refuses one with a space (seen with the real bd)
assert_eq "tool: bd init gets a prefix it accepts" "$(tail -1 "$T/bd-args")" "init --non-interactive --prefix my-app"
assert_eq "tool: exit 0" "$rc" "0"
assert_eq "tool: every step ran" "$(J 'd["ok"], d["done"], d["root"], d["worktrees"]')" "True ['folder', 'git', 'backlog', 'process', 'config'] $T/dev/My App True"
assert_eq "tool: git on main" "$(git -C "$T/dev/My App" symbolic-ref --short HEAD)" "main"
assert_eq "tool: bd init's commit, then the process section's" "$(git -C "$T/dev/My App" rev-list --count HEAD)" "2"
assert_eq "tool: nothing left uncommitted" "$(git -C "$T/dev/My App" status --porcelain)" ""
cm="$(cat "$T/dev/My App/CLAUDE.md")"
assert_contains "tool: bd's block kept" "$cm" "<!-- BEGIN BEADS -->"
assert_contains "tool: the section opts in to committing" "${cm#*END BEADS}" "Team-maintainer"
assert_contains "tool: the local merge" "${cm#*END BEADS}" "merge --ff-only"
assert_contains "tool: the PR path once there is an origin" "${cm#*END BEADS}" "pull request"
assert_eq "tool: a worktree space keyed my-app" "$(row "My App" | cut -f5,7,8)" "1	my-app	-"
assert_not_contains "tool: no account line for the default account" "$(cat "$WORKBENCH_CONFIG")" "claude_config"

out="$("$NEW" --json --kind tool --name "2026 plans" --account "$T/cfg")"
assert_eq "a name starting with a digit: the prefix still starts with a letter" "$(tail -1 "$T/bd-args")" "init --non-interactive --prefix p-2026-plans"
out="$("$NEW" --json --kind tool --name gadget --account "$T/cfg")"
assert_eq "tool + account: on that account" "$(row gadget | cut -f8)" "$T/cfg"

cp "$WORKBENCH_CONFIG" "$T/before.toml"
out="$("$NEW" --json --kind idea --name notes --area Side)"; rc=$?
assert_eq "idea in an area: exit 0" "$rc" "0"
assert_eq "idea in an area: its folder, a backlog" "$(J 'd["root"], d["done"]')" "$T/side/notes ['folder', 'git', 'backlog']"
[ -d "$T/side/notes/.beads" ] && ok "idea in an area: .beads made" || bad "idea in an area: no .beads"
assert_not_contains "idea in an area: no process section" "$(cat "$T/side/notes/CLAUDE.md")" "Team-maintainer"
cmp -s "$WORKBENCH_CONFIG" "$T/before.toml" && ok "idea in an area: spaces.toml untouched" || bad "idea in an area: spaces.toml changed"
assert_eq "idea in an area: listed in its area" "$(row notes | cut -f2)" "Side"

out="$("$NEW" --json --kind idea --name loose)"
assert_eq "idea, no area: its own space" "$(J 'd["root"], d["done"]')" "$T/dev/loose ['folder', 'git', 'backlog', 'config']"
assert_eq "idea, no area: no worktrees" "$(row loose | cut -f5,7)" "0	-"

refuse() {  # what, name, expected reason
  cp "$WORKBENCH_CONFIG" "$T/before.toml"; ls "$T/dev" "$T/side" > "$T/ls.before"
  out="$("$NEW" --json --kind tool --name "$2")"; rc=$?
  assert_eq "refuses $1: exit 1" "$rc" "1"
  assert_contains "refuses $1: says why" "$(J 'd["error"]')" "$3"
  cmp -s "$WORKBENCH_CONFIG" "$T/before.toml" && cmp -s <(ls "$T/dev" "$T/side") "$T/ls.before" \
    && ok "refuses $1: nothing made" || bad "refuses $1: something changed"
}
refuse "a taken name" "Acme" "already a space called Acme"
refuse "a taken name, any case" "my app" "already a space called My App"
refuse "a slash" "a/b" "/"
refuse "a leading dot" ".x" "."
refuse "an empty name" "" "a name"
mkdir -p "$T/dev/taken"
refuse "a folder that exists" "taken" "$T/dev/taken exists; to make it a space, run wb-setup"
out="$("$NEW" --json --kind idea --name existing --area Side)"
assert_contains "refuses an area's own folder: it's a space already" "$(J 'd["error"]')" "already a space called existing"
: > "$T/side/afile"   # not a folder, so not a row: only the path is taken
out="$("$NEW" --json --kind idea --name afile --area Side)"
assert_contains "refuses a path in the area that exists" "$(J 'd["error"]')" "$T/side/afile exists"
out="$("$NEW" --json --kind idea --name x --area Nope)"
assert_contains "refuses an unknown area" "$(J 'd["error"]')" "no area called Nope"

cp "$WORKBENCH_CONFIG" "$T/before.toml"
out="$(FAKE_INIT_RC=1 "$NEW" --json --kind tool --name broken)"; rc=$?
assert_eq "bd init fails: exit 1" "$rc" "1"
assert_eq "bd init fails: stopped after git" "$(J 'd["done"]')" "['folder', 'git']"
assert_contains "bd init fails: says how to finish" "$(J 'd["left"]')" "cd $T/dev/broken && bd init"
assert_contains "bd init fails: ... or remove it" "$(J 'd["left"]')" "rm -rf"
assert_contains "bd init fails: bd's own words" "$(J 'd["error"]')" "init broke"
cmp -s "$WORKBENCH_CONFIG" "$T/before.toml" && ok "bd init fails: spaces.toml untouched" || bad "bd init fails: spaces.toml changed"
[ -d "$T/dev/broken" ] && ok "bd init fails: the folder is left for the user" || bad "bd init fails: folder removed"

# --- asking (answers on stdin, one per line; '' takes the default) ---
ASK() { printf '%s\n' "$@" | "$NEW" 2>"$T/err"; }
out="$(ASK '' "My Tool" '' '')"; rc=$?
err="$(cat "$T/err")"
assert_eq "asks: a tool by default, made" "$rc" "0"
assert_eq "asks: the folder is the last stdout line" "$(printf '%s\n' "$out" | tail -1)" "$T/dev/My Tool"
assert_contains "asks: what it is" "$err" "an idea or notes"
assert_contains "asks: ... the tool choice" "$err" "a tool for me"
assert_contains "asks: the account, since spaces use two" "$err" "the default account"
assert_contains "asks: ... listing the other one" "$err" "$T/cfg"
assert_contains "asks: a summary before making it" "$err" "Make it?"
assert_eq "asks: default account is the most used (no claude_config)" "$(row "My Tool" | cut -f8)" "-"

out="$(ASK 1 idea1 '')"; rc=$?
err="$(cat "$T/err")"
assert_eq "an idea with one area: made" "$rc" "0"
assert_eq "an idea with one area: in it" "$(printf '%s\n' "$out" | tail -1)" "$T/side/idea1"
assert_not_contains "an idea with one area: no area question" "$err" "Which area"
assert_not_contains "an idea in an area: no account question" "$err" "the default account"

mkdir -p "$T/more"
printf '\n[[space]]\nname = "More"\nglob = "%s/more/*"\n' "$T" >> "$WORKBENCH_CONFIG"
out="$(ASK 1 2 idea2 '')"; rc=$?
err="$(cat "$T/err")"
assert_contains "an idea with two areas: asks which" "$err" "Which area"
assert_eq "an idea with two areas: the one picked" "$(printf '%s\n' "$out" | tail -1)" "$T/more/idea2"

out="$(ASK 2 Acme "Fresh" '' '')"; rc=$?
err="$(cat "$T/err")"
assert_contains "a taken name: says why" "$err" "already a space called Acme"
assert_eq "a taken name: asked again, then made" "$(printf '%s\n' "$out" | tail -1)" "$T/dev/Fresh"

cp "$WORKBENCH_CONFIG" "$T/before.toml"
out="$(ASK 2 Declined '' n)"; rc=$?
assert_eq "declined: exit 1" "$rc" "1"
[ ! -e "$T/dev/Declined" ] && ok "declined: nothing made" || bad "declined: folder made"
cmp -s "$WORKBENCH_CONFIG" "$T/before.toml" && ok "declined: spaces.toml untouched" || bad "declined: spaces.toml changed"
out="$(ASK 2)"; rc=$?
assert_eq "stdin runs out: exit 1" "$rc" "1"
assert_contains "stdin runs out: says nothing was made" "$(cat "$T/err")" "nothing made"

# review fixes: Esc (a literal \e on a plain read) and q stop; only '', y or yes make it
cp "$WORKBENCH_CONFIG" "$T/before.toml"; ls "$T/dev" > "$T/ls.before"
ESC=$(printf '\033')
stops() {  # what, answers…: each must stop with nothing made, having reached that question
  local what=$1; shift
  out="$(ASK "$@" '' '' '' '')"; rc=$?   # spare defaults: a stop that doesn't happen would make it
  assert_eq "$what: exit 1" "$rc" "1"
  assert_contains "$what: says nothing was made" "$(cat "$T/err")" "nothing made"
}
stops "esc at the kind" "$ESC"
stops "esc at the name" 2 "$ESC"
stops "esc at the account" 2 EscA "$ESC"
stops "esc at the confirm" 2 EscC '' "$ESC"
stops "q at the confirm" 2 QuitC '' q
cmp -s <(ls "$T/dev") "$T/ls.before" && cmp -s "$WORKBENCH_CONFIG" "$T/before.toml" \
  && ok "esc and q: nothing made at all" || bad "esc and q: something was made"
out="$(ASK 2 Again '' maybe y)"; rc=$?
assert_contains "the confirm: anything else is asked again" "$(cat "$T/err")" "y or n, please"
assert_eq "the confirm: ... then y makes it" "$(printf '%s\n' "$out" | tail -1)" "$T/dev/Again"
out="$("$NEW" --json --kind tool --name "$(printf 'a\033b')")"
assert_contains "a control character in a name is refused" "$(J 'd["error"]')" "can't have a control character"
out="$("$NEW" --json --kind tool --name " Pad ")"
assert_contains "spaces around a name are refused" "$(J 'd["error"]')" "can't start or end with a space"

# review fix: a folder in a worktrees = true area takes its name as its key; a clash would make
# wb-spaces refuse the whole config, so it's refused first
mkdir -p "$T/lab"
printf '\n[[space]]\nname = "Lab"\nglob = "%s/lab/*"\nworktrees = true\nbeads = true\n' "$T" >> "$WORKBENCH_CONFIG"
cp "$WORKBENCH_CONFIG" "$T/before.toml"
out="$("$NEW" --json --kind idea --name acme2 --area Lab)"
assert_eq "worktree area: a free name is made" "$(J 'd["ok"], d["done"]')" "True ['folder', 'git', 'backlog', 'process']"
out="$("$NEW" --json --kind idea --name my-app --area Lab)"; rc=$?
assert_eq "worktree area: a name that is another space's key is refused" "$rc" "1"
assert_contains "worktree area: ... saying why" "$(J 'd["error"]')" "my-app is already a space's key"
[ ! -e "$T/lab/my-app" ] && ok "worktree area: ... and nothing made" || bad "worktree area: folder made"
"$REPO/bin/wb-spaces" >/dev/null 2>&1 && ok "worktree area: the config still reads" || bad "worktree area: config broken"

# review fix: --json with no config yet makes one (the Desktop tool can get here; the launcher can't)
out="$(WORKBENCH_CONFIG="$T/fresh/spaces.toml" "$NEW" --json --kind tool --name firstone)"; rc=$?
assert_eq "no config yet: made" "$rc" "0"
assert_eq "no config yet: the file starts with the header" "$(head -1 "$T/fresh/spaces.toml")" "# workbench's spaces: one [[space]] per project folder the launcher offers. wb-setup wrote this;"
printf 'not = = toml\n' > "$T/badcfg.toml"
out="$(WORKBENCH_CONFIG="$T/badcfg.toml" "$NEW" --json --kind tool --name nope)"; rc=$?
assert_eq "a config that doesn't parse: refused" "$rc" "1"
assert_eq "a config that doesn't parse: left as it was" "$(cat "$T/badcfg.toml")" "not = = toml"

out="$(FAKE_INIT_RC=1 ASK 2 Broke2 '' '')"; rc=$?
err="$(cat "$T/err")"
assert_eq "a failed make: exit 1" "$rc" "1"
assert_contains "a failed make: why" "$err" "bd init failed"
assert_contains "a failed make: what's left" "$err" "rm -rf"

finish
