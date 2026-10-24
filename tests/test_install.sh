#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/z"
# install.sh also installs a launch agent: never the real one, never a real launchctl.
export WORKBENCH_DRY_RUN=1 WB_LAUNCH_AGENTS_DIR="$T/agents" WB_GROOM_DIR="$T/groom"
echo "not ours" > "$T/bin/wb-ui"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" bash "$REPO/install.sh" 2>&1)"
assert_eq "links wb-spaces" "$(readlink "$T/bin/wb-spaces")" "$REPO/bin/wb-spaces"
assert_eq "existing non-symlink left alone" "$(cat "$T/bin/wb-ui")" "not ours"
assert_contains "says it skipped it" "$out" "skip: $T/bin/wb-ui"
assert_contains "prints the zshrc line" "$out" "source \"$REPO/shell/workbench.zsh\""
if [ ! -e "$T/z/.zshrc" ]; then ok "never writes .zshrc"; else bad "install wrote .zshrc"; fi
echo "source \"$REPO/shell/workbench.zsh\"" > "$T/z/.zshrc"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" bash "$REPO/install.sh" 2>&1)"; rc=$?
assert_eq "second run succeeds" "$rc" "0"
assert_contains "second run sees the zshrc line" "$out" "already sources workbench"

# the weekly grooming schedule
PL="$T/agents/workbench.groom.plist"
assert_contains "schedule: says it wrote the agent" "$out" "workbench.groom.plist"
if [ -f "$PL" ]; then ok "schedule: plist written"; else bad "schedule: no plist at $PL"; fi
pl="$(cat "$PL" 2>/dev/null)"
assert_contains "schedule: label" "$pl" "<string>workbench.groom</string>"
assert_contains "schedule: Saturday" "$pl" $'<key>Weekday</key>\n\t\t<integer>6</integer>'
assert_contains "schedule: 06:00 (hour)" "$pl" $'<key>Hour</key>\n\t\t<integer>6</integer>'
assert_contains "schedule: 06:00 (minute)" "$pl" $'<key>Minute</key>\n\t\t<integer>0</integer>'
assert_contains "schedule: runs wb-groom run --all from the bin dir" "$pl" $'<string>'"$T/bin/wb-groom"$'</string>\n\t\t<string>run</string>\n\t\t<string>--all</string>'
assert_contains "schedule: stdout to launchd.log in the groom dir" "$pl" "<string>$T/groom/launchd.log</string>"
assert_not_contains "schedule: no placeholder left" "$pl" "@"
if command -v plutil >/dev/null; then assert_eq "schedule: plist is valid" "$(plutil -lint "$PL" >/dev/null 2>&1; echo $?)" "0"; fi
assert_contains "schedule: dry run prints bootstrap instead of running it" "$out" "launchctl bootstrap gui/$(id -u) $PL"
assert_contains "schedule: ... after replacing any earlier one" "$out" "launchctl bootout gui/$(id -u)/workbench.groom"
assert_eq "schedule: the groom dir exists for the log" "$([ -d "$T/groom" ] && echo yes)" "yes"
rm -f "$PL"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" bash "$REPO/install.sh" 2>&1)"
if [ -f "$PL" ]; then ok "schedule: re-running writes it again"; else bad "schedule: re-run wrote no plist"; fi
echo "stale" > "$PL"
WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" bash "$REPO/install.sh" >/dev/null 2>&1
assert_contains "schedule: re-running replaces it" "$(cat "$PL")" "<string>workbench.groom</string>"
rm -f "$PL"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" bash "$REPO/install.sh" --no-schedule 2>&1)"; rc=$?
assert_eq "schedule: --no-schedule succeeds" "$rc" "0"
if [ ! -e "$PL" ]; then ok "schedule: --no-schedule writes no plist"; else bad "schedule: --no-schedule wrote a plist"; fi
assert_not_contains "schedule: --no-schedule runs no launchctl" "$out" "launchctl"
assert_contains "schedule: --no-schedule still links" "$out" "linked $T/bin/wb-spaces"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" bash "$REPO/install.sh" --bogus 2>&1)"; rc=$?
assert_eq "install: an unknown option is usage (exit 2)" "$rc" "2"

# the agent runs with launchd's bare environment: what install saw of ours must reach it
rm -f "$PL"; mkdir -p "$T/py"; ln -s "$(command -v python3)" "$T/py/python3"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" PATH="$T/py:$PATH" bash "$REPO/install.sh" 2>&1)"; pl="$(cat "$PL")"
assert_contains "schedule: the python3, bd and claude install found lead the agent's PATH" "$pl" \
  "<string>$T/py:$REPO/tests/fake:$T/bin:"
assert_not_contains "schedule: no WB_PLANS_DIR key when none was set" "$pl" "WB_PLANS_DIR"
assert_not_contains "schedule: no WORKBENCH_CONFIG key when none was set" "$pl" "WORKBENCH_CONFIG"
assert_contains "schedule: WB_GROOM_DIR (set) is passed on" "$pl" $'<key>WB_GROOM_DIR</key>\n\t\t<string>'"$T/groom</string>"
rm -f "$PL"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" WB_PLANS_DIR="$T/plans & more" WORKBENCH_CONFIG="$T/c.toml" bash "$REPO/install.sh" 2>&1)"; pl="$(cat "$PL")"
assert_contains "schedule: WB_PLANS_DIR is passed on, xml-escaped" "$pl" $'<key>WB_PLANS_DIR</key>\n\t\t<string>'"$T/plans &amp; more</string>"
assert_contains "schedule: WORKBENCH_CONFIG is passed on" "$pl" $'<key>WORKBENCH_CONFIG</key>\n\t\t<string>'"$T/c.toml</string>"
if command -v plutil >/dev/null; then assert_eq "schedule: plist with env is valid" "$(plutil -lint "$PL" >/dev/null 2>&1; echo $?)" "0"; fi
rm -f "$PL"

assert_eq "example config parses" "$(WORKBENCH_CONFIG="$REPO/spaces.example.toml" "$REPO/bin/wb-spaces" >/dev/null 2>&1; echo $?)" "0"

mkdir -p "$T/clean" && git -C "$T/clean" init -q && echo "plain" > "$T/clean/a.txt" && git -C "$T/clean" add a.txt
git -C "$T/clean" -c user.email=t@example.com -c user.name=t commit -qm "first"
printf '[[space]]\nname = "Zanzibar"\nroot = "%s"\n' "$T" > "$T/leak.toml"
WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/clean" bash "$REPO/scripts/check-leaks.sh" >/dev/null 2>&1; rc=$?
assert_eq "clean repo with history passes" "$rc" "0"

mkdir -p "$T/leak" && git -C "$T/leak" init -q
printf '[[space]]\nname = "Zanzibar"\nroot = "%s"\n' "$T" > "$T/leak.toml"
echo "nothing private here" > "$T/leak/a.txt"; git -C "$T/leak" add a.txt
out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/leak" bash "$REPO/scripts/check-leaks.sh" 2>&1)"; rc=$?
assert_eq "clean repo passes" "$rc" "0"
echo "deploys to zanzibar today" > "$T/leak/b.txt"; git -C "$T/leak" add b.txt
out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/leak" bash "$REPO/scripts/check-leaks.sh" 2>&1)"; rc=$?
assert_eq "leak fails" "$rc" "1"
assert_contains "leak names the file" "$out" "b.txt"

# A name removed from the files is still in history, and a push would publish it.
git -C "$T/leak" -c user.email=t@example.com -c user.name=t commit -qm "add b"
echo "fine now" > "$T/leak/b.txt"; git -C "$T/leak" add b.txt
git -C "$T/leak" -c user.email=t@example.com -c user.name=t commit -qm "scrub b"
out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/leak" bash "$REPO/scripts/check-leaks.sh" 2>&1)"; rc=$?
assert_eq "leak still in history fails" "$rc" "1"
git -C "$T/leak" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m "trip to Zanzibar"
out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/leak" bash "$REPO/scripts/check-leaks.sh" 2>&1)"
assert_contains "leak in a commit message is reported" "$out" "commit message"
# The repo's own name is public (it is the repo), even when a space is named after it.
mkdir -p "$T/acmebench" && git -C "$T/acmebench" init -q
echo "acmebench reads acmebench's config" > "$T/acmebench/a.txt"; git -C "$T/acmebench" add a.txt
git -C "$T/acmebench" -c user.email=t@example.com -c user.name=t commit -qm "acmebench: first"
printf '[[space]]\nname = "acmebench"\nroot = "%s"\n' "$T/acmebench" > "$T/self.toml"
WORKBENCH_CONFIG="$T/self.toml" WB_LEAK_REPO="$T/acmebench" bash "$REPO/scripts/check-leaks.sh" >/dev/null 2>&1; rc=$?
assert_eq "the repo's own name is not a leak" "$rc" "0"
finish
