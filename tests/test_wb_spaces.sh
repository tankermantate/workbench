#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
WS="$REPO/bin/wb-spaces"

out="$(WORKBENCH_CONFIG="$T/none.toml" "$WS" 2>&1)"; rc=$?
assert_eq "missing config exits 3" "$rc" "3"
assert_contains "missing config names the file" "$out" "no config at $T/none.toml"

printf 'this is = = not toml\n' > "$T/bad.toml"
out="$(WORKBENCH_CONFIG="$T/bad.toml" "$WS" 2>&1)"; rc=$?
assert_eq "invalid config exits 4" "$rc" "4"
assert_contains "invalid config names the file" "$out" "invalid config $T/bad.toml"

mkdir -p "$T/acme" "$T/side/alpha" "$T/side/my proj" "$T/home/cfg"
touch "$T/side/notes.txt"
cat > "$T/ok.toml" <<EOF
[launcher]
terminals = ["WezTerm"]
leak_allow = ["Side"]

[[space]]
name          = "Acme"
root          = "$T/acme"
beads         = true
worktrees     = true
session_cmd   = "new-session"
space_key     = "acme"
claude_config = "$T/home/cfg"
protocol      = "docs/PROTOCOL.md"

[[space]]
name      = "Side"
glob      = "$T/side/*"
beads     = "if-present"
worktrees = false
safe      = true

[[space]]
name = "Gone"
root = "$T/does-not-exist"
EOF
out="$(WORKBENCH_CONFIG="$T/ok.toml" "$WS" 2>"$T/err")"; rc=$?
assert_eq "valid config exits 0" "$rc" "0"
expected="Acme	-	$T/acme	true	1	new-session	acme	$T/home/cfg	docs/PROTOCOL.md	0	-	-	-
alpha	Side	$T/side/alpha	if-present	0	-	alpha	-	-	1	-	-	-
my proj	Side	$T/side/my proj	if-present	0	-	my proj	-	-	1	-	-	-"
assert_eq "root + glob rows, sorted, files skipped, missing root skipped" "$out" "$expected"
assert_contains "missing root warns" "$(cat "$T/err")" "skipping 'Gone'"

cat > "$T/tilde.toml" <<EOF
[[space]]
name = "Home"
root = "~"
EOF
out="$(WORKBENCH_CONFIG="$T/tilde.toml" "$WS")"
assert_eq "~ is expanded" "$(printf '%s' "$out" | cut -f3)" "$HOME"

cat > "$T/nokey.toml" <<EOF
[[space]]
name = "Acme"
root = "$T/acme"
worktrees = true
EOF
out="$(WORKBENCH_CONFIG="$T/nokey.toml" "$WS" 2>&1)"; rc=$?
assert_eq "worktrees without space_key is invalid" "$rc" "4"
assert_contains "it says which field" "$out" "no space_key"

out="$(WORKBENCH_CONFIG="$T/ok.toml" "$WS" --terminals)"
assert_eq "--terminals" "$out" "WezTerm"
out="$(WORKBENCH_CONFIG="$T/ok.toml" "$WS" --leak-terms 2>/dev/null)"
assert_contains "--leak-terms has labels" "$out" "Acme"
assert_contains "--leak-terms has config basename" "$out" "cfg"
assert_not_contains "--leak-terms drops leak_allow" "$out" "Side"
assert_eq "--leak-terms has root folder names" "$(printf '%s\n' "$out" | grep -x acme)" "acme"
assert_eq "--leak-terms: leak_allow ignores case (glob folder side)" "$(printf '%s\n' "$out" | grep -xi side)" ""

cat > "$T/wt.toml" <<EOF
[[space]]
name = "Acme"
root = "$T/acme"
worktrees = true
space_key = "acme"
gh_account = "acme-bot"
on_create = '~/hooks/setup "\$WB_PROJECT"'
before_end = 'test -f "/m/\$WB_SHA"'

[[space]]
name = "Side"
glob = "$T/side/*"
worktrees = true
EOF
out="$(WORKBENCH_CONFIG="$T/wt.toml" "$WS")"
row1="$(printf '%s\n' "$out" | head -1)"
assert_eq "default session_cmd is workbench's own, by absolute path" \
  "$(printf '%s' "$row1" | cut -f6)" "$(cd "$REPO/bin" && pwd -P)/new-session"
assert_eq "hook columns 11-13" "$(printf '%s' "$row1" | cut -f11-13)" \
  "acme-bot	~/hooks/setup \"\$WB_PROJECT\"	test -f \"/m/\$WB_SHA\""
assert_eq "glob worktree space: each folder's key is its name" \
  "$(printf '%s\n' "$out" | tail -n +2 | cut -f7 | tr '\n' '|')" "alpha|my proj|"

printf '[[space]]\nname = "A"\nroot = "%s"\nworktrees = true\nspace_key = "k"\n[[space]]\nname = "B"\nroot = "%s"\nworktrees = true\nspace_key = "k"\n' "$T/acme" "$T/acme" > "$T/dup.toml"
out="$(WORKBENCH_CONFIG="$T/dup.toml" "$WS" 2>&1)"; rc=$?
assert_eq "duplicate worktree keys are invalid" "$rc" "4"
assert_contains "it names the key" "$out" "'k'"

printf '[[space]]\nname = "A"\nroot = "%s"\nworktrees = true\nspace_key = "a"\non_create = """one\ntwo"""\n' "$T/acme" > "$T/nl.toml"
out="$(WORKBENCH_CONFIG="$T/nl.toml" "$WS" 2>&1)"; rc=$?
assert_eq "a hook with a newline is invalid" "$rc" "4"
assert_contains "it says one line" "$out" "on_create must be one line"
printf '[[space]]\nname = "A"\nroot = "%s"\nworktrees = true\nspace_key = "a"\nbefore_end = "one\\ttwo"\n' "$T/acme" > "$T/tab.toml"
out="$(WORKBENCH_CONFIG="$T/tab.toml" "$WS" 2>&1)"; rc=$?
assert_eq "a hook with a tab is invalid" "$rc" "4"
assert_contains "it says no tabs" "$out" "before_end must be one line without tabs"

printf '[[space]]\nname = "S"\nglob = "%s/side/*"\nworktrees = true\nspace_key = "s"\n' "$T" > "$T/globkey.toml"
out="$(WORKBENCH_CONFIG="$T/globkey.toml" "$WS" 2>&1)"; rc=$?
assert_eq "glob worktree space with space_key is invalid" "$rc" "4"
# judge_env: extra variables for the grooming judge's environment, per space (a proxy, Bedrock)
cat > "$T/je.toml" <<EOF
[[space]]
name = "A"
root = "$T/acme"
judge_env = { HTTPS_PROXY = "http://proxy.acme.test:3128", CLAUDE_CODE_USE_BEDROCK = "1" }
[[space]]
name = "S"
glob = "$T/side/*"
judge_env = { AWS_REGION = "us-east-1" }
[[space]]
name = "B"
root = "$T/acme"
EOF
out="$(WORKBENCH_CONFIG="$T/je.toml" "$WS" --judge-env 2>&1)"; rc=$?
assert_eq "--judge-env exits 0" "$rc" "0"
assert_eq "--judge-env: JSON by label; a glob space's folders share it; none is {}" \
  "$(printf '%s' "$out" | python3 -c 'import json, sys; d = json.load(sys.stdin); print(d["A"]["HTTPS_PROXY"], d["A"]["CLAUDE_CODE_USE_BEDROCK"], d["alpha"], d["my proj"], d["B"])')" \
  "http://proxy.acme.test:3128 1 {'AWS_REGION': 'us-east-1'} {'AWS_REGION': 'us-east-1'} {}"
assert_eq "judge_env leaves the 13 TSV fields alone" "$(WORKBENCH_CONFIG="$T/je.toml" "$WS" | awk -F'\t' '{print NF}' | sort -u)" "13"
je_bad() {  # je_bad NAME TOML-VALUE MESSAGE
  printf '[[space]]\nname = "A"\nroot = "%s"\njudge_env = %s\n' "$T/acme" "$2" > "$T/jebad.toml"
  out="$(WORKBENCH_CONFIG="$T/jebad.toml" "$WS" --judge-env 2>&1)"; rc=$?
  assert_eq "judge_env $1 is invalid" "$rc" "4"
  assert_contains "judge_env $1: says why" "$out" "$3"
}
je_bad "as a string" '"HTTPS_PROXY=x"' "judge_env must be a table"
je_bad "with a number value" '{ AWS_MAX_ATTEMPTS = 3 }' "judge_env.AWS_MAX_ATTEMPTS must be a string"
je_bad "with a bad name" '{ "my-var" = "x" }' "judge_env: 'my-var' is not a variable name"
je_bad "with a newline" '{ HTTPS_PROXY = "a\nb" }' "judge_env.HTTPS_PROXY must be one line"
je_bad "setting PATH" '{ PATH = "/tmp" }' "judge_env can't set PATH"
je_bad "setting CLAUDE_CONFIG_DIR" '{ CLAUDE_CONFIG_DIR = "/tmp" }' "use claude_config"
finish
