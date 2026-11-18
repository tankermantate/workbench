#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/z"
# install.sh also installs a launch agent: never the real one, never a real launchctl.
export WORKBENCH_DRY_RUN=1 WB_LAUNCH_AGENTS_DIR="$T/agents" WB_GROOM_DIR="$T/groom" WB_RESTORE_DIR="$T/restore"
echo "not ours" > "$T/bin/wb-ui"
# python leaves bin/__pycache__ (gitignored) behind; an earlier install linked it, and a command
# since removed from bin/ left a dangling link
mkdir -p "$REPO/bin/__pycache__"
ln -s "$REPO/bin/__pycache__" "$T/bin/__pycache__"; ln -s "$REPO/bin/wb-gone" "$T/bin/wb-gone"
ln -s "$REPO/README.md" "$T/bin/readme"   # into the repo but not bin/: not install's to judge
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" WORKBENCH_CONFIG="$T/none.toml" bash "$REPO/install.sh" 2>&1)"
assert_contains "no config yet: points at wb-setup" "$out" "Next: run $REPO/bin/wb-setup"
if [ ! -e "$T/bin/__pycache__" ] && [ ! -L "$T/bin/__pycache__" ]; then ok "a directory in bin/ is not linked, and an old link to it goes"; else bad "bin/__pycache__ still linked"; fi
assert_not_contains "says nothing about linking it" "$out" "linked $T/bin/__pycache__"
if [ ! -L "$T/bin/wb-gone" ]; then ok "a link to a command no longer in bin/ goes"; else bad "dangling wb-gone link kept"; fi
assert_contains "says it removed them" "$out" "removed $T/bin/wb-gone"
assert_eq "a link elsewhere into the repo is left alone" "$(readlink "$T/bin/readme")" "$REPO/README.md"
assert_eq "links wb-spaces" "$(readlink "$T/bin/wb-spaces")" "$REPO/bin/wb-spaces"
assert_eq "existing non-symlink left alone" "$(cat "$T/bin/wb-ui")" "not ours"
assert_contains "says it skipped it" "$out" "skip: $T/bin/wb-ui"
assert_contains "prints the zshrc line" "$out" "source \"$REPO/shell/workbench.zsh\""
if [ ! -e "$T/z/.zshrc" ]; then ok "never writes .zshrc"; else bad "install wrote .zshrc"; fi
echo "source \"$REPO/shell/workbench.zsh\"" > "$T/z/.zshrc"
: > "$T/spaces.toml"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" WORKBENCH_CONFIG="$T/spaces.toml" bash "$REPO/install.sh" 2>&1)"; rc=$?
assert_eq "second run succeeds" "$rc" "0"
assert_not_contains "a config already: no wb-setup hint" "$out" "Next: run"
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
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" WB_PLANS_DIR="$T/plans & <more>" WORKBENCH_CONFIG="$T/c.toml" bash "$REPO/install.sh" 2>&1)"; pl="$(cat "$PL")"
assert_contains "schedule: WB_PLANS_DIR is passed on, xml-escaped" "$pl" $'<key>WB_PLANS_DIR</key>\n\t\t<string>'"$T/plans &amp; &lt;more&gt;</string>"
assert_contains "schedule: WORKBENCH_CONFIG is passed on" "$pl" $'<key>WORKBENCH_CONFIG</key>\n\t\t<string>'"$T/c.toml</string>"
# bash >= 5.2 (patsub_replacement, on by default) reads an & in ${v//pat/rep}'s replacement as
# the match, so &lt; would come out <lt;. The suite runs on 3.2, so pin the construct instead.
assert_eq "install.sh has no \${v//pat/rep}: bash 5.2 rewrites & in the replacement" \
  "$(grep -cE '\$\{[A-Za-z_][A-Za-z0-9_]*//' "$REPO/install.sh")" "0"
if command -v plutil >/dev/null; then assert_eq "schedule: plist with env is valid" "$(plutil -lint "$PL" >/dev/null 2>&1; echo $?)" "0"; fi
rm -f "$PL"

# the restore snapshot, every 10 minutes, so a crash or forced restart can be restored too
RL="$T/agents/workbench.restore-save.plist"; rm -f "$RL"
out="$(WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" WB_RESTORE_DIR="$T/restore" WB_STATE_DIR="$T/state" bash "$REPO/install.sh" 2>&1)"
if [ -f "$RL" ]; then ok "save agent: plist written"; else bad "save agent: no plist at $RL"; fi
rl="$(cat "$RL" 2>/dev/null)"
assert_contains "save agent: says it wrote it" "$out" "workbench.restore-save.plist"
assert_contains "save agent: label" "$rl" "<string>workbench.restore-save</string>"
assert_contains "save agent: every 600s" "$rl" $'<key>StartInterval</key>\n\t<integer>600</integer>'
assert_contains "save agent: runs wb-restore save --quiet from the bin dir" "$rl" $'<string>'"$T/bin/wb-restore"$'</string>\n\t\t<string>save</string>\n\t\t<string>--quiet</string>'
assert_contains "save agent: logs in the restore dir" "$rl" "<string>$T/restore/launchd.log</string>"
assert_contains "save agent: WB_RESTORE_DIR passed on" "$rl" $'<key>WB_RESTORE_DIR</key>\n\t\t<string>'"$T/restore</string>"
assert_contains "save agent: WB_STATE_DIR passed on" "$rl" $'<key>WB_STATE_DIR</key>\n\t\t<string>'"$T/state</string>"
assert_not_contains "save agent: no placeholder left" "$rl" "@"
if command -v plutil >/dev/null; then assert_eq "save agent: plist is valid" "$(plutil -lint "$RL" >/dev/null 2>&1; echo $?)" "0"; fi
assert_contains "save agent: dry run prints its bootstrap" "$out" "launchctl bootstrap gui/$(id -u) $RL"
assert_contains "save agent: ... after replacing any earlier one" "$out" "launchctl bootout gui/$(id -u)/workbench.restore-save"
assert_eq "save agent: the restore dir exists for the log" "$([ -d "$T/restore" ] && echo yes)" "yes"
rm -f "$RL"
WB_BIN_DIR="$T/bin" ZDOTDIR="$T/z" bash "$REPO/install.sh" --no-schedule >/dev/null 2>&1
if [ ! -e "$RL" ]; then ok "save agent: --no-schedule skips it too"; else bad "save agent: --no-schedule wrote it"; fi

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
# A sibling worktree's folder is not the repo's name; the repo is still acmebench.
git -C "$T/acmebench" worktree add -q --detach "$T/acmebench-groom"
WORKBENCH_CONFIG="$T/self.toml" WB_LEAK_REPO="$T/acmebench-groom" bash "$REPO/scripts/check-leaks.sh" >/dev/null 2>&1; rc=$?
assert_eq "the repo's own name is not a leak from a sibling worktree" "$rc" "0"

# Every email git knows here is a term, not just the one that wins: a repo set to a public
# address still has the personal one in its global config, and bd copied that into old beads.
mkdir -p "$T/mail" && git -C "$T/mail" init -q && git -C "$T/mail" config user.email t@example.com
echo "plain" > "$T/mail/a.txt"; git -C "$T/mail" add a.txt
git -C "$T/mail" -c user.name=t commit -qm "first"
printf '[user]\n\temail = jo.private@mail.test\n' > "$T/gitglobal"
mailleaks() { GIT_CONFIG_GLOBAL="$T/gitglobal" WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/mail" bash "$REPO/scripts/check-leaks.sh" 2>&1; }
echo "ping jo.private@mail.test" > "$T/mail/b.txt"; git -C "$T/mail" add b.txt
out="$(mailleaks)"; rc=$?
assert_eq "the global email is a term when the repo sets its own" "$rc" "1"
# A GitHub noreply address is public by design: it is the author of every pushed commit.
git -C "$T/mail" rm -q --cached b.txt; rm "$T/mail/b.txt"
git -C "$T/mail" config user.email 1234+jo@users.noreply.github.com
echo "owner 1234+jo@users.noreply.github.com" > "$T/mail/c.txt"; git -C "$T/mail" add c.txt
out="$(mailleaks)"; rc=$?
assert_eq "a GitHub noreply email is not a leak" "$rc" "0"

# The bead store is a Dolt database that bd syncs to the git remote (refs/dolt/data), so its
# rows and its history are published too, outside anything git grep sees.
leaks() { WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/beady" bash "$REPO/scripts/check-leaks.sh" 2>&1; }
if command -v dolt >/dev/null; then
  export DOLT_ROOT_PATH="$T/doltroot"   # dolt's global config: never the real one
  mkdir -p "$T/beady/.beads/embeddeddolt/wb" && git -C "$T/beady" init -q
  echo "plain" > "$T/beady/a.txt"; git -C "$T/beady" add a.txt
  git -C "$T/beady" -c user.email=t@example.com -c user.name=t commit -qm "first"
  db="$T/beady/.beads/embeddeddolt/wb"
  dq() { (cd "$db" && dolt sql -q "$1" >/dev/null && dolt add -A && dolt commit -m "$2" >/dev/null); }
  (cd "$db" && dolt init --name t --email t@example.com >/dev/null)
  dq "create table issues (id varchar(20) primary key, title text)" "schema"
  dq "insert into issues values ('wb-1', 'tidy the launcher')" "clean bead"
  out="$(leaks)"; rc=$?
  assert_eq "bead db: clean store passes" "$rc" "0"
  assert_not_contains "bead db: clean store has no warning" "$out" "bead db"

  dq "insert into issues values ('wb-2', 'invoice Zanzibar')" "leaky bead"
  out="$(leaks)"; rc=$?
  assert_eq "bead db: leak with no remote only warns" "$rc" "0"
  assert_contains "bead db: the warning names the table" "$out" "bead db: issues"
  assert_contains "bead db: the warning names the bead" "$out" "wb-2"
  assert_not_contains "bead db: the warning does not repeat the private name" "$out" "Zanzibar"
  # The store is untracked, so it lives only in the main checkout; a worktree must still scan it.
  git -C "$T/beady" worktree add -q --detach "$T/beady-groom"
  out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/beady-groom" bash "$REPO/scripts/check-leaks.sh" 2>&1)"
  assert_contains "bead db: a sibling worktree scans the main checkout's store" "$out" "bead db: issues"
  git -C "$T/beady" worktree remove "$T/beady-groom"

  git -C "$T/beady" remote add origin "$T/nowhere.git"
  # bd's no-push keeps the store off the git remote, so a finding only warns, as with no remote.
  printf 'sync-branch: main\nno-push: true\n' > "$T/beady/.beads/config.yaml"
  out="$(leaks)"; rc=$?
  assert_eq "bead db: a git remote with bd no-push on only warns" "$rc" "0"
  assert_contains "bead db: and says why it's only a warning" "$out" "no-push"
  assert_contains "bead db: still names the bead" "$out" "wb-2"
  rm "$T/beady/.beads/config.yaml"
  out="$(leaks)"; rc=$?
  assert_eq "bead db: leak with a git remote fails" "$rc" "1"
  dq "update issues set title = 'invoice the client' where id = 'wb-2'" "scrub"
  out="$(leaks)"; rc=$?
  assert_eq "bead db: leak left in dolt history fails" "$rc" "1"
  assert_contains "bead db: history is reported" "$out" "bead db: issues history"

  git -C "$T/beady" remote remove origin
  (cd "$db" && dolt remote add backup "file://$T/doltremote")
  out="$(leaks)"; rc=$?
  assert_eq "bead db: a dolt remote counts as a remote" "$rc" "1"
  printf 'no-push: true\n' > "$T/beady/.beads/config.yaml"
  out="$(leaks)"; rc=$?
  assert_eq "bead db: no-push doesn't excuse a dolt remote (bd dolt push publishes to it)" "$rc" "1"
  rm "$T/beady/.beads/config.yaml"

  out="$(WB_DOLT="$T/no-dolt" leaks)"; rc=$?
  assert_eq "bead db: can't scan with a remote fails closed" "$rc" "1"
  assert_contains "bead db: says how to override" "$out" "WB_LEAK_SKIP_BEADS=1"
  printf '#!/bin/sh\necho "[1]"\n' > "$T/odd-dolt"; chmod +x "$T/odd-dolt"
  out="$(WB_DOLT="$T/odd-dolt" leaks)"; rc=$?
  assert_eq "bead db: output it can't read fails closed" "$rc" "1"
  assert_contains "bead db: and says so" "$out" "can't scan"
  out="$(WB_DOLT="$T/no-dolt" WB_LEAK_SKIP_BEADS=1 leaks)"; rc=$?
  assert_eq "bead db: the override skips the store" "$rc" "0"
else
  echo "  skip bead db leak tests: no dolt"
fi
finish
