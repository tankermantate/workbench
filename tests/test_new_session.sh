#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
unset CLAUDECODE FAKE_BD_DIR WORKBENCH_DRY_RUN
NS="$REPO/bin/new-session"
export WB_WORKTREES_DIR="$T/wts" WORKBENCH_CONFIG="$T/spaces.toml"
export FAKE_BD_LOG="$T/bd.log" FAKE_GH_LOG="$T/gh.log" HOOK_OUT="$T/hook.env" WB_STATE_DIR="$T/state"

# Acme: origin; project in app/; tracked bead store at the repo top.
A="$T/acme"; setup_repo "$A"
mkdir -p "$A/app"; mkstore "$A"; : > "$A/app/keep"
# a leftover .beads (no database) nearer the project than the real store
mkdir -p "$A/app/.beads"; : > "$A/app/.beads/issues.jsonl"
cat > "$A/.beads/fake.json" <<'EOF'
[{"id":"acme-a1","title":"Fix the Login Page!","issue_type":"bug","status":"open"},
 {"id":"acme-a2","title":"Add CSV export","issue_type":"feature","status":"open"},
 {"id":"acme-a3","title":"Hook fails here","issue_type":"task","status":"open"}]
EOF
git -C "$A" add app .beads; git -C "$A" commit -q -m app; git -C "$A" push -q
# Beta: its own store, untracked; a safe space.
B="$T/beta"; setup_repo "$B"; mkstore "$B"
echo '[{"id":"bee-1","title":"Tidy","issue_type":"task"},{"id":"bee-2","title":"Slow claim","issue_type":"task"}]' > "$B/.beads/fake.json"
# Loc: no origin, no beads.
L="$T/loc"; git init -q -b main "$L"; git -C "$L" config user.email t@example.com
git -C "$L" config user.name t; : > "$L/a"; git -C "$L" add a; git -C "$L" commit -q -m init

cat > "$WORKBENCH_CONFIG" <<EOF
[[space]]
name = "Acme"
root = "$A/app"
worktrees = true
space_key = "acme"
claude_config = "$T/cfg"
gh_account = "acme-bot"
on_create = '[ -z "\$HOOK_FAIL" ] || { echo hook-boom; exit 3; }; env | grep ^WB_ | sort > "\$HOOK_OUT"'

[[space]]
name = "Beta"
root = "$B"
worktrees = true
space_key = "beta"
safe = true

[[space]]
name = "Loc"
root = "$L"
worktrees = true
space_key = "loc"
beads = false
EOF
W="$T/wts"   # where worktrees go

# --- a bead, with --space (the launcher's form)
out="$("$NS" acme-a1 --space acme --no-launch 2>&1)"; rc=$?
WT="$W/acme-fix-the-login-page"
assert_eq "bead: exits 0" "$rc" "0"
assert_eq "bead: last line is the project folder" "$(printf '%s\n' "$out" | tail -1)" "WORKTREE_DIR=$WT/app"
assert_eq "bead: bug → fix/ branch from the title" "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" "fix/fix-the-login-page"
assert_contains "bead: claimed, appending to notes" "$(cat "$FAKE_BD_LOG")" \
  "update acme-a1 --claim --append-notes Branch: fix/fix-the-login-page (worktree at $WT)"
assert_eq "beads: redirect points at the real store" "$(cat "$WT/.beads/redirect")" \
  "$(perl -MFile::Spec -e 'print File::Spec->abs2rel($ARGV[0],$ARGV[1])' "$A/.beads" "$WT")"
assert_eq "beads: the redirect doesn't dirty the worktree" "$(git -C "$WT" status --porcelain)" ""
if [ ! -e "$WT/app/.beads/redirect" ]; then ok "beads: a leftover .beads with no database is skipped"; else bad "beads: redirect went into the leftover app/.beads"; fi
hook="$(cat "$HOOK_OUT")"
assert_contains "hook: WB_SPACE" "$hook" "WB_SPACE=acme"
assert_contains "hook: WB_WORKTREE" "$hook" "WB_WORKTREE=$WT"
assert_contains "hook: WB_PROJECT" "$hook" "WB_PROJECT=$WT/app"
assert_contains "hook: WB_SOURCE" "$hook" "WB_SOURCE=$A/app"
assert_contains "hook: WB_BRANCH" "$hook" "WB_BRANCH=fix/fix-the-login-page"
assert_contains "hook: WB_BEAD" "$hook" "WB_BEAD=acme-a1"
assert_contains "gh: switched to the space's account" "$(cat "$FAKE_GH_LOG")" "auth switch --user acme-bot"

# --- a bead without --space: found by asking each store
out="$("$NS" bee-1 --no-launch 2>&1)"
assert_eq "lookup: found in the second space" "$(printf '%s\n' "$out" | tail -1)" "WORKTREE_DIR=$W/beta-tidy"
assert_eq "lookup: task → feat/" "$(git -C "$W/beta-tidy" rev-parse --abbrev-ref HEAD)" "feat/tidy"
assert_eq "beads: untracked store still gets a clean redirect" "$(git -C "$W/beta-tidy" status --porcelain)" ""
out="$("$NS" acme-a2 --no-launch 2>&1)"
assert_contains "lookup: first space in config order" "$out" "WORKTREE_DIR=$W/acme-add-csv-export/app"
out="$("$NS" zz-9 --no-launch 2>&1)"; rc=$?
assert_eq "unknown id: exit 2" "$rc" "2"
assert_contains "unknown id: lists the keys" "$out" "acme, beta, loc"

# --- exploratory
out="$("$NS" loc Big idea --no-launch 2>&1)"; rc=$?
assert_eq "explore + topic: exits 0 with no origin" "$rc" "0"
assert_eq "explore + topic: branch" "$(git -C "$W/loc-big-idea" rev-parse --abbrev-ref HEAD)" "explore/big-idea"
assert_eq "no origin: starts from local main" "$(git -C "$W/loc-big-idea" log -1 --format=%s)" "init"
out="$("$NS" beta --no-launch 2>&1)"
assert_contains "explore, no topic: timestamp branch" "$out" "on branch explore/20"
out="$("$NS" loc Big idea --no-launch 2>&1)"; rc=$?
assert_eq "existing worktree path: exit 1" "$rc" "1"
assert_contains "existing worktree path: says so" "$out" "already exists"

# --- on_create fails: worktree kept, bead not claimed
: > "$FAKE_BD_LOG"
out="$(HOOK_FAIL=1 "$NS" acme-a3 --space acme --no-launch 2>&1)"; rc=$?
assert_eq "on_create fails: exit 1" "$rc" "1"
assert_contains "on_create fails: hook output shown" "$out" "hook-boom"
assert_contains "on_create fails: says how to remove it" "$out" "end-session --force $W/acme-hook-fails-here"
if [ -d "$W/acme-hook-fails-here" ]; then ok "on_create fails: worktree kept"; else bad "on_create fails: worktree kept"; fi
assert_not_contains "on_create fails: bead not claimed" "$(cat "$FAKE_BD_LOG")" "update"

# --- the main checkout on another branch is never moved
git -C "$A" checkout -q -b side
c="$T/clone"; git clone -q "$A.origin.git" "$c"
git -C "$c" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m ahead
git -C "$c" push -q origin main
before="$(git -C "$A" rev-parse side)"
"$NS" acme pull check --no-launch >/dev/null 2>&1
assert_eq "pull: a checkout on another branch is left alone" "$(git -C "$A" rev-parse side)" "$before"
assert_eq "base: the worktree starts from fetched origin/main" "$(git -C "$W/acme-pull-check" log -1 --format=%s)" "ahead"
git -C "$A" checkout -q main

# --- gh: already active, or missing
: > "$FAKE_GH_LOG"
FAKE_GH_ACTIVE=acme-bot "$NS" acme gh same --no-launch >/dev/null 2>&1
assert_not_contains "gh: no switch when already active" "$(cat "$FAKE_GH_LOG")" "switch"
out="$(WB_GH=/nonexistent/gh "$NS" acme gh missing --no-launch 2>&1)"; rc=$?
assert_contains "gh missing: warns" "$out" "gh not found"
assert_eq "gh missing: still starts" "$rc" "0"

# --- launching (dry run), safe, nested guard
out="$(WORKBENCH_DRY_RUN=1 "$NS" acme dry run 2>&1)"
assert_contains "launch: config dir and env for the one command" "$(printf '%s\n' "$out" | tail -1)" \
  "DRY-RUN: cd $W/acme-dry-run/app && env CLAUDE_CONFIG_DIR=$T/cfg WB_SPACE_ROOT=$A/app WB_WORKTREE=$W/acme-dry-run claude --settings $T/state/claude-settings.json "
assert_contains "launch: prompts off" "$(printf '%s\n' "$out" | tail -1)" " --dangerously-skip-permissions"
assert_not_contains "launch: no bead, no WB_BEAD" "$(printf '%s\n' "$out" | tail -1)" "WB_BEAD="
out="$(WORKBENCH_DRY_RUN=1 "$NS" beta safe one 2>&1)"
assert_contains "safe space: no config dir, prompts on" "$(printf '%s\n' "$out" | tail -1)" "env -u CLAUDE_CONFIG_DIR WB_SPACE_ROOT="
assert_not_contains "safe space: no skip flag" "$(printf '%s\n' "$out" | tail -1)" "dangerously"
out="$(WORKBENCH_DRY_RUN=1 "$NS" acme with flag --safe 2>&1)"
assert_not_contains "--safe: no skip flag" "$(printf '%s\n' "$out" | tail -1)" "dangerously"
out="$(CLAUDECODE=1 "$NS" loc nested 2>&1)"; rc=$?
assert_contains "nested: says what to run instead" "$out" "Open a new terminal and run"
assert_not_contains "nested: doesn't start Claude" "$out" "FAKE-CLAUDE"
assert_eq "nested: exits 0" "$rc" "0"

# --- errors
out="$("$NS" --bogus 2>&1)"; rc=$?
assert_eq "unknown flag: exit 2" "$rc" "2"
mkdir -p "$T/plain"; F="$T/nofetch"; git init -q -b main "$F"
git -C "$F" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$F" remote add origin "$T/nowhere.git"
printf '[[space]]\nname = "X"\nroot = "%s"\nworktrees = true\nspace_key = "x"\n[[space]]\nname = "F"\nroot = "%s"\nworktrees = true\nspace_key = "f"\n' "$T/plain" "$F" > "$T/bad.toml"
out="$(WORKBENCH_CONFIG="$T/bad.toml" "$NS" x --no-launch 2>&1)"; rc=$?
assert_eq "root not in git: exit 2" "$rc" "2"
assert_contains "root not in git: says so" "$out" "not in a git repo"
out="$(WORKBENCH_CONFIG="$T/bad.toml" "$NS" f --no-launch 2>&1)"; rc=$?
assert_eq "fetch fails: exit 1" "$rc" "1"
assert_contains "fetch fails: says so" "$out" "git fetch origin failed"
if [ -z "$(ls "$W" | grep '^f-')" ]; then ok "fetch fails: nothing created"; else bad "fetch fails: nothing created"; fi
out="$(WORKBENCH_CONFIG="$T/missing.toml" "$NS" acme --no-launch 2>&1)"; rc=$?
assert_eq "no config: exit 2" "$rc" "2"

# --- a space with no store of its own never answers for a store above its repo
P="$T/parent"; mkstore "$P"
echo '[{"id":"p-1","title":"Parent bead","issue_type":"task"}]' > "$P/.beads/fake.json"
O="$P/own"; git init -q -b main "$O"; git -C "$O" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
R="$T/real"; git init -q -b main "$R"; mkstore "$R"; cp "$P/.beads/fake.json" "$R/.beads/"
git -C "$R" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
printf '[[space]]\nname = "Own"\nroot = "%s"\nworktrees = true\nspace_key = "own"\n[[space]]\nname = "Real"\nroot = "%s"\nworktrees = true\nspace_key = "real"\n' "$O" "$R" > "$T/stores.toml"
out="$(WORKBENCH_CONFIG="$T/stores.toml" "$NS" p-1 --no-launch 2>&1)"
assert_eq "store-less space: skipped in the lookup" "$(printf '%s\n' "$out" | tail -1)" "WORKTREE_DIR=$W/real-parent-bead"
out="$(WORKBENCH_CONFIG="$T/stores.toml" "$NS" p-1 --space own --no-launch 2>&1)"; rc=$?
assert_eq "store-less space with --space: refused" "$rc" "2"
assert_contains "store-less space with --space: says why" "$out" "has no bead store"

# --- a claim stuck behind bd's lock doesn't hang the session
start=$SECONDS
out="$(WB_BD_WRITE_TIMEOUT=1 FAKE_BD_UPDATE_SLEEP=5 "$NS" bee-2 --space beta --no-launch 2>&1)"; rc=$?
took=$((SECONDS - start))
assert_eq "slow claim: the session still starts" "$rc" "0"
assert_contains "slow claim: says the claim failed" "$out" "couldn't claim bee-2"
if [ "$took" -lt 4 ]; then ok "slow claim: cut off (${took}s)"; else bad "slow claim: waited ${took}s"; fi

# --- a branch an earlier end-session kept is picked up again, not an error
git -C "$L" branch explore/kept
out="$("$NS" loc kept --no-launch 2>&1)"; rc=$?
assert_eq "kept branch: starts" "$rc" "0"
assert_contains "kept branch: says it reuses it" "$out" "reusing branch explore/kept"
assert_eq "kept branch: the worktree is on it" "$(git -C "$W/loc-kept" rev-parse --abbrev-ref HEAD)" "explore/kept"

# --- spaces in paths: everything works, and printed commands are quoted
SW="$T/wt dir"
out="$(WB_WORKTREES_DIR="$SW" WORKBENCH_DRY_RUN=1 "$NS" acme spaced 2>&1)"; rc=$?
assert_eq "space in path: starts" "$rc" "0"
assert_eq "space in path: hook saw the project" "$(grep '^WB_PROJECT=' "$HOOK_OUT")" "WB_PROJECT=$SW/acme-spaced/app"
assert_eq "space in path: redirect resolves" "$(cd "$SW/acme-spaced" && cd "$(cat .beads/redirect)" && pwd -P)" "$A/.beads"
assert_contains "space in path: DRY-RUN line is quoted" "$(printf '%s\n' "$out" | tail -1)" \
  "DRY-RUN: cd $(printf '%q' "$SW/acme-spaced/app") && env $(printf '%q' "CLAUDE_CONFIG_DIR=$T/cfg") WB_SPACE_ROOT=$A/app $(printf '%q' "WB_WORKTREE=$SW/acme-spaced") claude --settings "
out="$(WB_WORKTREES_DIR="$SW" CLAUDECODE=1 "$NS" loc spaced too 2>&1)"
assert_contains "space in path: nested guard's cd line is quoted" "$out" "cd $(printf '%q' "$SW/loc-spaced-too")"
finish
