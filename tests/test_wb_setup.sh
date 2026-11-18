#!/usr/bin/env bash
# wb-setup: the guided first run. Answers come on stdin, one per line ('' takes the default).
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # wb-setup writes real paths; macOS's /var is /private/var
PY="$(command -v python3)"
S="$REPO/bin/wb-setup"
# a bare PATH: only what each case links into $T/fb, plus the system's own folders
mkdir -p "$T/fb"
ln -s "$PY" "$T/fb/python3"
ln -s "$(command -v git)" "$T/fb/git"
ln -s "$REPO/tests/fake/claude" "$T/fb/claude"
printf '#!/bin/sh\nexit 0\n' > "$T/fb/fzf"; chmod +x "$T/fb/fzf"
# bd: logs each call with its folder; init makes a store there, version answers
cat > "$T/bd-stub" <<EOF
#!/bin/sh
echo "\$PWD :: \$*" >> "$T/bd.log"
case "\$1" in
  init) mkdir -p .beads && : > .beads/config.yaml; echo "lots of init chatter"; echo "Prefer to opt out?  bd metrics off" ;;
  version) echo "bd version 9.9" ;;
esac
EOF
chmod +x "$T/bd-stub"; cp "$T/bd-stub" "$T/fb/bd"
# brew: logs its args and HOMEBREW_NO_AUTOREMOVE; installing beads puts bd on the PATH
cat > "$T/brew" <<EOF
#!/bin/sh
echo "\$* autoremove-off=\${HOMEBREW_NO_AUTOREMOVE:-}" >> "$T/brew.log"
[ "\$*" = "install beads" ] && cp "$T/bd-stub" "$T/fb/bd"
exit 0
EOF
chmod +x "$T/brew"
export WORKBENCH_DRY_RUN=1 WB_GROOM_DIR="$T/groom" WB_RESTORE_DIR="$T/restore" WB_LAUNCH_AGENTS_DIR="$T/agents"
export WB_DESKTOP_DIR="$T/desk" WB_MCP="$T/no-wb-mcp" WB_BREW="$T/no-brew"
export PATH="$T/fb:/usr/bin:/bin"
# fresh HOME NAME: a machine where nothing of workbench is set up yet
fresh() {
  H="$T/$1"; mkdir -p "$H"
  export HOME="$H" ZDOTDIR="$H" WB_BIN_DIR="$H/.local/bin" WORKBENCH_CONFIG="$H/.config/workbench/spaces.toml"
  export WB_DEMO_DIR="$H/.local/share/workbench/demo"
}
setup() { printf '%s\n' "$@" | "$PY" "$S" 2>&1; }
rows() { "$REPO/bin/wb-spaces" 2>/dev/null | cut -f1,3,4,5,7; }

# --- a first run, start to finish ---
fresh a
setup_repo "$T/proj"; rm -rf "$T/proj.origin.git"
out=$(setup n "$T/nope" "$T/proj" 'My "app"' y '' '' '' '' ''); rc=$?
assert_eq "first run: exit 0" "$rc" "0"
assert_contains "checks the tools first" "$out" "ok   claude"
assert_eq "linked the commands (install.sh)" "$(readlink "$WB_BIN_DIR/wb-spaces")" "$REPO/bin/wb-spaces"
if [ ! -e "$T/agents" ]; then ok "schedule declined: install.sh --no-schedule"; else bad "schedule installed though declined"; fi
assert_contains "a folder that isn't one: says so and asks again" "$out" "not a folder: $T/nope"
assert_eq "bd init in the project, and in the demo with its own prefix" "$(grep -c ':: init --non-interactive' "$T/bd.log")" "2"
assert_not_contains "bd init's chatter is kept off the screen" "$out" "lots of init chatter"
assert_eq "bd's metrics notice, said once and plainly" "$(grep -c 'anonymous usage metrics' <<<"$out")" "1"
assert_not_contains "install.sh's own next steps aren't shown inside setup" "$out" "Next: run"
assert_contains "the project's init ran there" "$(cat "$T/bd.log")" "$T/proj :: init --non-interactive"
assert_contains "the demo's init ran there, prefix demo" "$(cat "$T/bd.log")" "$WB_DEMO_DIR :: init --non-interactive -q -p demo"
assert_eq "the demo gets sample tasks" "$(grep -c "$WB_DEMO_DIR :: create" "$T/bd.log")" "3"
assert_contains "the first sample is under NOW" "$(cat "$T/bd.log")" "-l wave:1"
assert_eq "the config: the project (quoted name, worktrees, a key) and the demo" "$(rows)" \
  "$(printf 'My "app"\t%s\ttrue\t1\tmy-app\nDemo\t%s\ttrue\t0\t-' "$T/proj" "$WB_DEMO_DIR")"
assert_contains "the config names folders under home with ~" "$(cat "$WORKBENCH_CONFIG")" 'root = "~/.local/share/workbench/demo"'
assert_contains "the config points at the example for the rest" "$(cat "$WORKBENCH_CONFIG")" "spaces.example.toml"
assert_contains "~/.zshrc: the launcher line" "$(cat "$H/.zshrc")" "source \"$REPO/shell/workbench.zsh\""
assert_contains "~/.zshrc: the bin dir on PATH, since it wasn't" "$(cat "$H/.zshrc")" 'export PATH="$HOME/.local/bin:$PATH"'
assert_contains "no wb-mcp: says planning in Claude isn't in this version" "$out" "isn't in this version"
assert_contains "ends with the doctor: ready" "$out" "workbench is ready"
assert_not_contains "the doctor counts the new PATH line, though this shell hasn't read it" "$out" "is not on your PATH"
assert_contains "and says what to do next" "$out" "Open a new Terminal window"
assert_contains "and suggests the demo" "$out" "Demo"

# --- run again: nothing asked twice, nothing written twice ---
cp "$WORKBENCH_CONFIG" "$T/before.toml"; : > "$T/bd.log"
out=$(setup ''); rc=$?
assert_eq "second run: exit 0" "$rc" "0"
assert_contains "second run: offers to add to the config it found" "$out" "2 spaces in"
assert_eq "second run: the config is untouched" "$(cmp -s "$WORKBENCH_CONFIG" "$T/before.toml" && echo same)" "same"
assert_eq "second run: no bd calls but the doctor's" "$(grep -v ':: version' "$T/bd.log")" ""
assert_eq "second run: the zshrc line once" "$(grep -c workbench.zsh "$H/.zshrc")" "1"
assert_eq "second run: the PATH line once" "$(grep -c '.local/bin' "$H/.zshrc")" "1"
assert_not_contains "second run: no demo offer (it's there)" "$out" "Add a Demo space"

# --- adding to that config: a taken name is asked again; no bd init leaves beads if-present ---
mkdir -p "$T/proj2"
out=$(setup y "$T/proj" "$T/proj2" Demo '' n ''); rc=$?
assert_eq "add: exit 0" "$rc" "0"
assert_contains "add: a folder that's already a space" "$out" "already a space: $T/proj"
assert_contains "add: a taken name" "$out" "already a space called Demo"
assert_eq "add: appended, the rest kept" "$(rows | tail -1)" "$(printf 'proj2\t%s\tif-present\t0\t-' "$T/proj2")"
assert_eq "add: three spaces" "$(rows | wc -l | tr -d ' ')" "3"
assert_not_contains "add: no worktree question outside a git repo" "$out" "its own worktree"

# --- bd init commits its files, and would sweep in whatever is staged: refused then ---
setup_repo "$T/proj3"; rm -rf "$T/proj3.origin.git"
echo wip > "$T/proj3/wip.txt"; git -C "$T/proj3" add wip.txt
: > "$T/bd.log"
out=$(setup y "$T/proj3" '' n ''); rc=$?
assert_eq "staged changes: setup carries on" "$rc" "0"
assert_contains "staged changes: says why it won't run bd init" "$out" "proj3 has staged changes (git add), which bd init would commit with its own files"
assert_contains "staged changes: and how to do it later" "$out" "cd $T/proj3 && bd init"
assert_not_contains "staged changes: no bd init question" "$out" "Make one with bd init"
assert_eq "staged changes: bd init not run" "$(grep -c ':: init' "$T/bd.log")" "0"
assert_eq "staged changes: the space waits for its backlog" "$(rows | tail -1)" "$(printf 'proj3\t%s\tif-present\t0\t-' "$T/proj3")"

# --- an invalid config is left alone ---
fresh inv; mkdir -p "${WORKBENCH_CONFIG%/*}"; printf '[[space]]\nname = "Broken"\n' > "$WORKBENCH_CONFIG"
out=$(setup n ''); rc=$?
assert_eq "invalid config: exit 1" "$rc" "1"
assert_contains "invalid config: says why and to fix it" "$out" "needs exactly one of root or glob"
assert_eq "invalid config: untouched" "$(cat "$WORKBENCH_CONFIG")" $'[[space]]\nname = "Broken"'

# --- missing tools ---
fresh noclaude; rm "$T/fb/claude"
out=$(setup); rc=$?
assert_eq "no claude: exit 1" "$rc" "1"
assert_contains "no claude: where to get it" "$out" "Install Claude Code"
if [ ! -e "$WORKBENCH_CONFIG" ] && [ ! -e "$WB_BIN_DIR" ]; then ok "no claude: nothing written"; else bad "no claude: wrote something"; fi
ln -s "$REPO/tests/fake/claude" "$T/fb/claude"

fresh nobd; rm "$T/fb/bd"
out=$(setup); rc=$?
assert_eq "no bd, no brew: exit 1" "$rc" "1"
assert_contains "no bd, no brew: how to get beads" "$out" "https://github.com/gastownhall/beads"
out=$(WB_BREW="$T/brew" setup y); rc=$?
assert_contains "no bd, brew: installs beads, autoremove off" "$(cat "$T/brew.log")" "install beads autoremove-off=1"
assert_contains "then finds bd" "$out" "ok   bd"
assert_contains "stdin ran out: stops, saying how to carry on" "$out" "stopped; run wb-setup again"
assert_eq "stopped: exit 1" "$rc" "1"

printf '#!/bin/sh\necho 3.9\n' > "$T/oldpy"; chmod +x "$T/oldpy"
out=$(WB_PYTHON="$T/oldpy" setup); rc=$?
assert_eq "old python: exit 1" "$rc" "1"
assert_contains "old python: what's needed" "$out" "3.11 or later"

# --- Claude Desktop, when this version has wb-mcp ---
fresh mcp
printf '#!/bin/sh\necho "$*" >> "%s/mcp.log"\necho "workbench connected"\nexit ${FAKE_MCP_RC:-0}\n' "$T" > "$T/wb-mcp"; chmod +x "$T/wb-mcp"
out=$(WB_MCP="$T/wb-mcp" setup n '' n '' '' y); rc=$?
assert_eq "wb-mcp: asked and connected" "$(cat "$T/mcp.log")" "connect"
assert_contains "wb-mcp: its output shown" "$out" "workbench connected"
assert_eq "no projects, no demo: the doctor fails on the missing config" "$rc" "1"
fresh mcp2; : > "$T/mcp.log"
out=$(FAKE_MCP_RC=1 WB_MCP="$T/wb-mcp" setup n '' '' '' '' y); rc=$?
assert_contains "wb-mcp fails: says how to try later" "$out" "wb-mcp connect"
assert_eq "wb-mcp fails: setup carries on to the doctor" "$rc" "0"
finish
