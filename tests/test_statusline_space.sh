#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # macOS /var is /private/var; git reports the real path
SP="$REPO/bin/wb-statusline-space"
unset WB_SPACE_ROOT WB_WORKTREE

setup_repo "$T/acme"
mkdir -p "$T/side/alpha/sub" "$T/elsewhere" "$T/wts"
git -C "$T/acme" worktree add -q -b feat/x "$T/wts/acme-x1y"
# a monorepo: two worktree spaces rooted in subfolders, worktrees made from the repo's top
setup_repo "$T/mono"; mkdir -p "$T/mono/apps/web" "$T/mono/apps/api"
git -C "$T/mono" worktree add -q -b w "$T/wts/web-2026" && git -C "$T/mono" worktree add -q -b a "$T/wts/api-9"
git -C "$T/mono" worktree add -q -b o "$T/wts/other"
cat > "$T/spaces.toml" <<EOF
[[space]]
name      = "Acme"
root      = "$T/acme"
worktrees = true
space_key = "acme"

[[space]]
name      = "Web"
root      = "$T/mono/apps/web"
worktrees = true
space_key = "web"

[[space]]
name      = "Api"
root      = "$T/mono/apps/api"
worktrees = true
space_key = "api"

[[space]]
name = "Side"
glob = "$T/side/*"
EOF
export WORKBENCH_CONFIG="$T/spaces.toml"

sp() { printf '{"workspace":{"project_dir":"%s","current_dir":"%s"}}' "$1" "${2:-$1}" | "$SP"; }

assert_eq "main checkout: the space's name" "$(sp "$T/acme")" "Acme"
assert_eq "worktree: its space, marked" "$(sp "$T/wts/acme-x1y")" "Acme ⑂ worktree"
assert_eq "monorepo worktree: the space its key names" "$(sp "$T/wts/api-9")" "Api ⑂ worktree"
assert_eq "monorepo worktree, no key match: the repo's first space" "$(sp "$T/wts/other")" "Web ⑂ worktree"
assert_eq "monorepo worktree, other key" "$(sp "$T/wts/web-2026")" "Web ⑂ worktree"
assert_eq "glob space: the folder's label" "$(sp "$T/side/alpha")" "alpha"
assert_eq "a folder inside a space" "$(sp "$T/side/alpha/sub")" "alpha"
assert_eq "launched folder wins over a tool's cd" "$(sp "$T/acme" "$T/elsewhere")" "Acme"
assert_eq "no space: the folder, in parens" "$(sp "$T/elsewhere")" "(elsewhere)"
assert_eq "falls back to current_dir" \
  "$(printf '{"workspace":{"current_dir":"%s"}}' "$T/acme" | "$SP")" "Acme"
assert_eq "WB_SPACE_ROOT never claims a folder outside the space" \
  "$(WB_SPACE_ROOT="$T/acme" sp "$T/elsewhere")" "(elsewhere)"
out="$(WORKBENCH_CONFIG="$T/none.toml" sp "$T/acme" 2>&1)"; rc=$?
assert_eq "no config: the folder, quietly" "$out:$rc" "(acme):0"
out="$(printf 'not json' | "$SP" 2>&1)"; rc=$?
assert_eq "bad stdin prints nothing, exits 0" "$out:$rc" ":0"
finish
