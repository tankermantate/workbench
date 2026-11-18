#!/usr/bin/env bash
# wb-update: the launcher's once-a-day new-version notice, and the one-step update.
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
U="$REPO/bin/wb-update"
unset WB_UPDATE_CHECK                 # lib.sh turns the check off for every other suite
export WB_UPDATE_FOREGROUND=1         # refresh inline, so a test can see its result
export WORKBENCH_CONFIG="$T/none.toml"   # no config: the check is on by default

# The release history, as the owner would make it: a bare origin, and a published checkout
# that cuts 0.1 then 0.2. A user's clone is made at 0.1.
setup_repo "$T/pub"
P="$T/pub"
cat > "$P/install.sh" <<'EOF'
#!/usr/bin/env bash
echo "install.sh ran with: $*" >> "$(dirname "$0")/../install.log"
echo "linked things"
EOF
chmod +x "$P/install.sh"
printf '0.1\n' > "$P/VERSION"
printf '# Changelog\n\n## 0.1 — 2026-11-01\n\n- First release.\n' > "$P/CHANGELOG.md"
git -C "$P" add -A && git -C "$P" commit -q -m "release 0.1" && git -C "$P" tag v0.1
git -C "$P" push -q origin main v0.1
git clone -q "$T/pub.origin.git" "$T/user"
H="$T/user"
cache="$T/cache/update.json"
export WB_UPDATE_HOME="$H" WB_UPDATE_CACHE="$cache"

out=$("$U" --version)
assert_eq "--version: the installed version" "$out" "0.1"

out=$("$U" --notice); rc=$?
assert_eq "current: no notice" "$rc:$out" "0:"
if [ -f "$cache" ]; then ok "the check wrote its cache"; else bad "no cache at $cache"; fi

# the owner cuts 0.2
printf '0.2\n' > "$P/VERSION"
printf '# Changelog\n\n## 0.2 — 2026-11-20\n\n- The launcher says when a new version is out.\n\n## 0.1 — 2026-11-01\n\n- First release.\n' > "$P/CHANGELOG.md"
git -C "$P" commit -q -am "release 0.2" && git -C "$P" tag v0.2 && git -C "$P" push -q origin main v0.2

out=$("$U" --notice)
assert_eq "checked today: the cached answer stands, no new look" "$out" ""

python3 - "$cache" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["checked"] -= 86400 + 60; json.dump(d, open(sys.argv[1], "w"))
EOF
"$U" --notice >/dev/null       # stale: this one refreshes (inline here; the launcher's runs in the background)
out=$("$U" --notice)
assert_eq "an older version sees the notice" "$out" "workbench 0.2 available: wb-update"
out=$("$U" --notice --color)
assert_contains "--color: yellow" "$out" $'\033[33m'

out=$(WB_UPDATE_CHECK=off "$U" --notice)
assert_eq "WB_UPDATE_CHECK=off: nothing" "$out" ""
printf '[launcher]\nupdate_check = false\n' > "$T/off.toml"
out=$(WORKBENCH_CONFIG="$T/off.toml" "$U" --notice)
assert_eq "update_check = false in the config: nothing" "$out" ""
printf '[launcher\n' > "$T/bad.toml"
out=$(WORKBENCH_CONFIG="$T/bad.toml" "$U" --notice)
assert_eq "an invalid config: nothing (can't tell it's allowed)" "$out" ""

# off means no contact at all: a stale cache stays stale
rm -f "$cache"
WORKBENCH_CONFIG="$T/off.toml" "$U" --notice >/dev/null
if [ ! -f "$cache" ]; then ok "turned off: never looks"; else bad "turned off but it checked"; fi

# fail silent: an unreachable origin, no git checkout, no VERSION
git -C "$H" remote set-url origin "$T/nowhere.git"
out=$("$U" --notice 2>&1); rc=$?
assert_eq "unreachable origin: exit 0, nothing" "$rc:$out" "0:"
git -C "$H" remote set-url origin "$T/pub.origin.git"
mkdir -p "$T/zip"
out=$(WB_UPDATE_HOME="$T/zip" "$U" --notice 2>&1); rc=$?
assert_eq "not a checkout, no VERSION: exit 0, nothing" "$rc:$out" "0:"

# wb-update: refuses what it can't do safely
out=$(WB_UPDATE_HOME="$T/zip" "$U" 2>&1); rc=$?
assert_eq "not a checkout: refuses" "$rc" "1"
assert_contains "and says so" "$out" "not a git checkout"
echo "my edit" >> "$H/CHANGELOG.md"
out=$("$U" 2>&1); rc=$?
assert_eq "local changes: refuses" "$rc" "1"
assert_contains "and says how to go on" "$out" "local changes"
assert_eq "and pulls nothing" "$(cat "$H/VERSION")" "0.1"
git -C "$H" checkout -q -- CHANGELOG.md
git -C "$H" checkout -q --detach
out=$("$U" 2>&1); rc=$?
assert_eq "detached HEAD: refuses" "$rc" "1"
assert_contains "and says so" "$out" "not on a branch"
git -C "$H" checkout -q main

# one command brings them current
out=$("$U" 2>&1); rc=$?
assert_eq "wb-update: exit 0" "$rc" "0"
assert_eq "pulled: the new version is installed" "$(cat "$H/VERSION")" "0.2"
assert_contains "re-ran install.sh" "$(cat "$T/install.log")" "install.sh ran with"
assert_contains "without the schedule when there was none" "$(cat "$T/install.log")" "--no-schedule"
assert_contains "install.sh's output shows" "$out" "linked things"
assert_contains "says what moved" "$out" "workbench 0.1 → 0.2"
assert_contains "shows what's new" "$out" "The launcher says when a new version is out."
assert_not_contains "only what's new" "$out" "First release."
out=$("$U" --notice)
assert_eq "current again: the notice is gone" "$out" ""

out=$("$U" 2>&1); rc=$?
assert_eq "already current: exit 0" "$rc" "0"
assert_contains "and says so" "$out" "up to date"

# a schedule that was installed stays installed
: > "$T/install.log"
mkdir -p "$T/agents"; : > "$T/agents/workbench.groom.plist"
echo "- more" >> "$P/CHANGELOG.md"; git -C "$P" commit -q -am "unreleased fix"; git -C "$P" push -q origin main
out=$(WB_LAUNCH_AGENTS_DIR="$T/agents" "$U" 2>&1)
assert_not_contains "a schedule there: re-installed with it" "$(cat "$T/install.log")" "--no-schedule"
assert_contains "commits past the release: still says it pulled" "$out" "0.2"

# the launcher's first screen carries the notice; no other screen does
rm -f "$cache"
git -C "$H" reset -q --hard HEAD~2
first() { (cd "$T" && WB_BOOTTIME=garbage WB_SWAPUSAGE=garbage zsh -f -c "source '$REPO/shell/workbench.zsh'; WORKBENCH_HOME='$REPO'; $1"); }
out=$(first "_wb_first_header 'enter: choose'")
assert_contains "first screen: the keys" "$out" "enter: choose"
assert_contains "first screen: then the notice" "$out" "workbench 0.2 available: wb-update"
out=$(first "_wb_header 'enter: choose'")
assert_eq "other screens: no notice" "$out" "enter: choose"
src=$(cat "$REPO/shell/workbench.zsh")
assert_contains "the space screen (fzf) uses the first header" "$src" "--header=\"\$(_wb_first_header 'enter: choose"
assert_contains "the numbered menu prints the notice too" "$src" 'bin/wb-update --notice >&2'

# the repo's own release files stay in step
v=$(cat "$REPO/VERSION")
assert_contains "VERSION is X.Y" "$(printf '%s' "$v" | grep -E '^[0-9]+\.[0-9]+$')" "$v"
assert_contains "CHANGELOG.md has a section for VERSION" "$(cat "$REPO/CHANGELOG.md")" "## $v "
finish
