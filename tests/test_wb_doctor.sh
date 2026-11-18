#!/usr/bin/env bash
# wb-doctor: is this machine ready for the launcher? One line per check, exit 1 on any failure.
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
PY="$(command -v python3)"
D="$REPO/bin/wb-doctor"
# a bare PATH: only what each case links into $T/fb, plus the system's own folders
mkdir -p "$T/fb" "$T/home/.local/bin" "$T/cfg" "$T/desk"; mkstore "$T/p"
ln -s "$PY" "$T/fb/python3"
ln -s "$(command -v git)" "$T/fb/git"
ln -s "$REPO/tests/fake/claude" "$T/fb/claude"
ln -s "$REPO/tests/fake/bd" "$T/fb/bd"
printf '#!/bin/sh\nexit 0\n' > "$T/fb/fzf"; chmod +x "$T/fb/fzf"
export HOME="$T/home" ZDOTDIR="$T/home" WB_BIN_DIR="$T/home/.local/bin"
export WORKBENCH_CONFIG="$T/cfg/spaces.toml" WB_LAUNCH_AGENTS_DIR="$T/agents" WB_DESKTOP_DIR="$T/desk"
export WB_MCP="$T/no-wb-mcp"
export PATH="$T/fb:$WB_BIN_DIR:/usr/bin:/bin"
WORKBENCH_DRY_RUN=1 WB_GROOM_DIR="$T/groom" WB_RESTORE_DIR="$T/restore" bash "$REPO/install.sh" > /dev/null 2>&1
echo "source \"$REPO/shell/workbench.zsh\"" > "$T/home/.zshrc"
cat > "$WORKBENCH_CONFIG" <<EOF
[[space]]
name  = "Alpha"
root  = "$T/p"
beads = true
EOF
doc() { "$PY" "$D" "$@" 2>&1; }

out=$(doc); rc=$?
assert_eq "healthy: exit 0" "$rc" "0"
assert_contains "python checked" "$out" "ok   python3"
assert_contains "bd checked" "$out" "ok   bd"
assert_contains "claude checked" "$out" "ok   claude"
assert_contains "config checked, with its space count" "$out" "ok   spaces.toml: 1 space"
assert_contains "each space with a backlog" "$out" "ok   Alpha"
assert_contains "the zshrc line" "$out" "ok   ~/.zshrc"
assert_contains "the schedule" "$out" "ok   schedule"
assert_contains "says it's ready" "$out" "workbench is ready"
assert_not_contains "no failures" "$out" "!!"

# a space that wants a backlog and has none: names the fix
rm -rf "$T/p/.beads"; mkdir "$T/p/.beads"   # a .beads without bd's config isn't a store
out=$(doc); rc=$?
assert_eq "missing .beads: exit 1" "$rc" "1"
assert_contains "names the space and the fix" "$out" "!!   Alpha: no backlog yet: cd $T/p && bd init"
assert_contains "counts what to fix" "$out" "1 thing to fix"
rm -rf "$T/p/.beads"; git init -q "$T/repo"; mkstore "$T/repo"; mkdir -p "$T/repo/sub"
printf '[[space]]\nname  = "Alpha"\nroot  = "%s"\nbeads = true\n' "$T/repo/sub" > "$WORKBENCH_CONFIG"
out=$(doc); rc=$?
assert_eq "a store higher up the repo counts, as bd finds it there" "$rc:$(grep -c 'Alpha' <<<"$out")" "0:1"
assert_contains "and the space is ok" "$out" "ok   Alpha"
printf 'worktrees = true\nspace_key = "a"\n' >> "$WORKBENCH_CONFIG"
out=$(doc); rc=$?
assert_eq "worktrees in a subfolder of a repo: fine" "$rc" "0"
printf '[[space]]\nname = "Beta"\nroot = "%s"\nbeads = false\nworktrees = true\nspace_key = "b"\n' "$T/cfg" >> "$WORKBENCH_CONFIG"
out=$(doc); rc=$?
assert_eq "worktrees outside a repo: exit 1" "$rc" "1"
assert_contains "worktrees outside a repo: says so" "$out" "!!   Beta: worktrees = true, but $T/cfg is not a git repository"
printf '[[space]]\nname  = "Alpha"\nroot  = "%s"\nbeads = true\n' "$T/p" > "$WORKBENCH_CONFIG"
mkstore "$T/p"

# a root that isn't a folder
mv "$T/p" "$T/p2"
out=$(doc); rc=$?
assert_eq "missing root: exit 1" "$rc" "1"
assert_contains "says the folder is gone" "$out" "!!   Alpha: $T/p is not a folder"
mv "$T/p2" "$T/p"

# no config: points at wb-setup
mv "$WORKBENCH_CONFIG" "$T/cfg/away.toml"
out=$(doc); rc=$?
assert_eq "no config: exit 1" "$rc" "1"
assert_contains "no config: run wb-setup" "$out" "!!   spaces.toml: none at $WORKBENCH_CONFIG; run wb-setup"
mv "$T/cfg/away.toml" "$WORKBENCH_CONFIG"

# an invalid config: wb-spaces' own reason
printf '[[space]]\nname = "Broken"\n' >> "$WORKBENCH_CONFIG"
out=$(doc); rc=$?
assert_eq "invalid config: exit 1" "$rc" "1"
assert_contains "invalid config: says why" "$out" "needs exactly one of root or glob"
printf '[[space]]\nname  = "Alpha"\nroot  = "%s"\nbeads = true\n' "$T/p" > "$WORKBENCH_CONFIG"

# missing tools
rm "$T/fb/bd"
out=$(doc); rc=$?
assert_eq "no bd: exit 1" "$rc" "1"
assert_contains "no bd: how to get it" "$out" "!!   bd: not found; install beads: brew install beads"
ln -s "$REPO/tests/fake/bd" "$T/fb/bd"
rm "$T/fb/claude"
out=$(doc); rc=$?
assert_eq "no claude: exit 1" "$rc" "1"
assert_contains "no claude: where to get it" "$out" "!!   claude: not found"
ln -s "$REPO/tests/fake/claude" "$T/fb/claude"
printf '#!/bin/sh\necho 3.9\n' > "$T/oldpy"; chmod +x "$T/oldpy"
out=$(WB_PYTHON="$T/oldpy" doc); rc=$?
assert_eq "old python: exit 1" "$rc" "1"
assert_contains "old python: says which and what" "$out" "!!   python3 3.9: workbench needs 3.11 or later: brew install python"

# optional things only warn
rm "$T/fb/fzf"
out=$(doc); rc=$?
assert_eq "no fzf: still exit 0" "$rc" "0"
assert_contains "no fzf: a note" "$out" "--   fzf: not found (optional: searchable menus): brew install fzf"
rm -rf "$T/agents"
out=$(doc); rc=$?
assert_eq "no schedule: still exit 0" "$rc" "0"
assert_contains "no schedule: a note" "$out" "--   schedule: not installed"
out=$(PATH="$T/fb:/usr/bin:/bin" doc); rc=$?
assert_eq "bin dir off PATH: still exit 0" "$rc" "0"
assert_contains "bin dir off PATH: a note" "$out" "--   $WB_BIN_DIR is not on your PATH"

# the launcher line in ~/.zshrc
: > "$T/home/.zshrc"
out=$(doc); rc=$?
assert_eq "no zshrc line: exit 1" "$rc" "1"
assert_contains "no zshrc line: run wb-setup" "$out" "!!   ~/.zshrc doesn't start the launcher; run wb-setup"
echo "source \"$REPO/shell/workbench.zsh\"" > "$T/home/.zshrc"

# commands not linked
rm -f "$WB_BIN_DIR"/*
out=$(doc); rc=$?
assert_eq "not installed: exit 1" "$rc" "1"
assert_contains "not installed: run install.sh" "$out" "!!   commands: not linked into $WB_BIN_DIR; run $REPO/install.sh"
WORKBENCH_DRY_RUN=1 WB_GROOM_DIR="$T/groom" WB_RESTORE_DIR="$T/restore" bash "$REPO/install.sh" > /dev/null 2>&1

# another checkout's links and zshrc line count (this one may be a worktree of it)
mkdir -p "$T/other/bin" "$T/other/shell"; : > "$T/other/shell/workbench.zsh"
cp "$REPO/bin/wb-spaces" "$T/other/bin/wb-spaces"
ln -sfn "$T/other/bin/wb-spaces" "$WB_BIN_DIR/wb-spaces"
echo "source \"$T/other/shell/workbench.zsh\"" > "$T/home/.zshrc"
out=$(doc); rc=$?
assert_eq "another checkout: exit 0" "$rc" "0"
assert_contains "another checkout: says which" "$out" "ok   commands linked into $WB_BIN_DIR (from $(cd "$T/other" && pwd -P))"
ln -sfn "$REPO/bin/wb-spaces" "$WB_BIN_DIR/wb-spaces"
echo "source \"$REPO/shell/workbench.zsh\"" > "$T/home/.zshrc"

# Claude Desktop, only when wb-mcp is installed
out=$(doc)
assert_contains "no wb-mcp: says it's not in this version" "$out" "--   Claude Desktop: planning in Claude (wb-mcp) isn't in this version"
printf '#!/bin/sh\nexit 0\n' > "$T/wb-mcp"; chmod +x "$T/wb-mcp"
out=$(WB_MCP="$T/wb-mcp" doc); rc=$?
assert_eq "wb-mcp not connected: still exit 0" "$rc" "0"
assert_contains "wb-mcp not connected: how" "$out" "--   Claude Desktop: not connected; wb-mcp connect"
echo '{"mcpServers": {"workbench": {"command": "x"}}}' > "$T/desk/claude_desktop_config.json"
out=$(WB_MCP="$T/wb-mcp" doc)
assert_contains "wb-mcp connected" "$out" "ok   Claude Desktop: connected"
finish
