# Session Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `new-session` and `end-session` move into workbench and work for any space with `worktrees = true`. Everything specific to one space (setup, GitHub account, the check before removal) lives in that machine's `spaces.toml`.

**Architecture:**
- **`bin/wb-spaces`** gains three columns: `gh_account`, `on_create` and `before_end`. Its validation changes too:
  - Space keys must be unique.
  - In a glob space, each folder's key is its folder name.
  - `session_cmd` defaults to workbench's own `bin/new-session`.
  - A hook must be one line.
- **`lib/session.sh`** holds the bash helpers both scripts share:
  - reading rows;
  - finding a space by key or by bead;
  - the default branch;
  - the nearest bead store;
  - running a hook;
  - switching the gh account.
- **`bin/new-session` and `bin/end-session`** are bash scripts built on those helpers.
- **The launcher** passes `--space <key>` with a bead id.

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), git ≥ 2.31 (`--path-format`), perl (only for `File::Spec->abs2rel` and `alarm`), python3 ≥ 3.11 (`wb-spaces`, and JSON parsing in the lib). Tests are plain bash with fake `bd`, `gh` and `claude` on `PATH`.

**Spec:** `docs/specs/2026-10-18-session-scripts-design.md`. Read it first; this plan argues from it.

## Global Constraints

- **bash 3.2:** no `declare -A`, `mapfile`, `${x,,}`, or `readarray`. `"${arr[@]}"` on an empty array fails under `set -u`, so check `${#arr[@]}` first.
- **`set -euo pipefail`** in both scripts:
  - Never pipe into `grep -q`, since with pipefail an early exit kills the writer and the `if` reads false. Capture the output first, then grep a here-string.
  - Guard every expected failure with `if`, `||` or `&&`.
- **Paths:** resolve with `pwd -P` before comparing, because `/tmp` is really `/private/tmp`. Quote every expansion, since paths may contain spaces (glob keys are folder names).
- **TSV:** `wb-spaces` writes `-` for an empty value, and `ws_split` turns `-` back into empty.
- **Hooks** run as `(cd <project> && sh -c "<hook>")`, with `WB_SPACE`, `WB_WORKTREE`, `WB_PROJECT`, `WB_SOURCE`, `WB_BRANCH` and `WB_BEAD` exported. `WB_SHA` is also set, for `before_end` only.
- **bd** is `${WB_BD:-bd}` and **gh** is `${WB_GH:-gh}`. A bd call is bounded by `${WB_BD_TIMEOUT:-5}` seconds through `perl -e 'alarm shift; exec @ARGV'`, and its stdin is `/dev/null`, so it can never swallow a `while read` loop's input.
- **Tests must never touch real systems:**
  - Worktrees go in `WB_WORKTREES_DIR`, under the test's temp folder.
  - Config is `WORKBENCH_CONFIG`.
  - Fakes come first on `PATH` (set up by `tests/lib.sh`).
  - Anything that would start Claude runs with `WORKBENCH_DRY_RUN=1`.
  - The test files `unset CLAUDECODE` because they run inside Claude.
- **No real names** in code, tests or examples. Use `Acme`, `Beta`, `Loc` and `acme-bot`.
- **Commits:** one per task, on `feat/session-scripts`. Every message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01L3Jq9hZ4cjAjWXwvozc1r7
  ```
  Nothing is pushed.

## Review Focus

1. **Paths with spaces, or behind a symlink (`/tmp`):** worktree registration, matching a repo to a space, the redirect's relative path, and the hook variables must all work when `WB_WORKTREES_DIR` or a root is under `/tmp`, or contains a space.
2. **The main checkout on a branch other than the default, or dirty, when `new-session` runs:** it must never be moved. Only a checked-out default branch is fast-forwarded.
3. **bd output with `Warning:` lines before the JSON, a bd that is slow or missing, and a bead id found in two stores:** the first space in config order wins, a slow bd counts as "not found", and nothing hangs.
4. **`end-session` run from inside the worktree it removes, and from a project subfolder:** the target is the worktree's top folder, and the removal still works.
5. **A repo that doesn't ignore `.beads/redirect`:** the worktree must still be clean for `end-session`'s dirty check.

---

### Task 0: Workspace

- [ ] **Step 1:** From `~/dev/workbench` on a clean `main`, create the worktree and enter it.
  ```bash
  git worktree add .claude/worktrees/session-scripts -b feat/session-scripts main
  ```
  Then `EnterWorktree` with `path: .claude/worktrees/session-scripts`.
- [ ] **Step 2:** Run the baseline.
  ```bash
  tests/run.sh
  ```
  Expected: every file passes (142 tests).

---

### Task 1: `wb-spaces`: new columns, keys, default session command

**Files:**
- Modify: `bin/wb-spaces`
- Test: `tests/test_wb_spaces.sh`

**Interfaces:**
- Produces: each row has 13 tab-separated fields:
  - fields 1–10 as before (label, group, root, beads, worktrees, session_cmd, space_key, claude_config, protocol, safe);
  - then 11 `gh_account`, 12 `on_create`, 13 `before_end`.

  Two of the old fields change:
  - `session_cmd` is `<realpath of bin>/new-session` when `worktrees` is on and the field is unset.
  - In a glob space, `space_key` is the folder name, unless the space sets one.
- Exit 4 for any of:
  - a root worktree space without `space_key`;
  - a glob worktree space that sets `space_key`;
  - a duplicate key among worktree spaces;
  - a hook (`gh_account`, `on_create` or `before_end`) that contains a newline or isn't a string.

- [ ] **Step 1: Write the failing tests.** In `tests/test_wb_spaces.sh`, replace the `expected=` block and the `nokey` assertion, and add the new cases before `finish`:

```bash
expected="Acme	-	$T/acme	true	1	new-session	acme	$T/home/cfg	docs/PROTOCOL.md	0	-	-	-
alpha	Side	$T/side/alpha	if-present	0	-	alpha	-	-	1	-	-	-
my proj	Side	$T/side/my proj	if-present	0	-	my proj	-	-	1	-	-	-"
```

```bash
out="$(WORKBENCH_CONFIG="$T/nokey.toml" "$WS" 2>&1)"; rc=$?
assert_eq "worktrees without space_key is invalid" "$rc" "4"
assert_contains "it says which field" "$out" "no space_key"
```

```bash
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

printf '[[space]]\nname = "S"\nglob = "%s/side/*"\nworktrees = true\nspace_key = "s"\n' "$T" > "$T/globkey.toml"
out="$(WORKBENCH_CONFIG="$T/globkey.toml" "$WS" 2>&1)"; rc=$?
assert_eq "glob worktree space with space_key is invalid" "$rc" "4"
```

- [ ] **Step 2: Run the test and check it fails.**
  ```bash
  bash tests/test_wb_spaces.sh
  ```
  Expected: FAIL on the 13-column rows, the default `session_cmd`, the hook columns, the glob keys, duplicate keys, the newline hook, and the glob key. The `nokey` test fails too, on its message.

- [ ] **Step 3: Implement.** In `bin/wb-spaces`:

Docstring line 6 becomes `space_key, claude_config, protocol, safe, gh_account, on_create, before_end   ('-' = unset)`.

After `def expand(p): …` add:

```python
DEFAULT_SESSION_CMD = os.path.join(os.path.dirname(os.path.realpath(__file__)), "new-session")
HOOKS = ("gh_account", "on_create", "before_end")
```

In `spaces(cfg)`, replace the block from `worktrees = bool(...)` through the `yield` of glob rows with:

```python
        worktrees = bool(s.get("worktrees", False))
        if worktrees and "root" in s and not s.get("space_key"):
            raise ValueError(f"space '{name}' has worktrees = true but no space_key")
        if worktrees and "glob" in s and s.get("space_key"):
            raise ValueError(f"space '{name}': a glob space with worktrees = true uses each folder's "
                             "name as its key; remove space_key")
        hooks = {k: s.get(k, "") for k in HOOKS}
        for k, v in hooks.items():
            if not isinstance(v, str) or "\n" in v:
                raise ValueError(f"space '{name}': {k} must be one line")
        beads = s.get("beads", "if-present")
        beads = {True: "true", False: "false"}.get(beads, beads)
        if beads not in ("true", "false", "if-present"):
            raise ValueError(f"space '{name}': beads must be true, false or \"if-present\"")
        common = {
            "beads": beads,
            "worktrees": "1" if worktrees else "0",
            "session_cmd": s.get("session_cmd", "") or (DEFAULT_SESSION_CMD if worktrees else ""),
            "space_key": s.get("space_key", ""),
            "claude_config": expand(s.get("claude_config", "")),
            "protocol": s.get("protocol", ""),
            "safe": "1" if s.get("safe") else "0",
            **hooks,
        }
        if "root" in s:
            root = expand(s["root"])
            if not os.path.isdir(root):
                print(f"workbench: skipping '{name}': {root} is not a folder", file=sys.stderr)
                continue
            yield {"label": name, "group": "", "root": root, **common}
        else:
            for d in sorted(glob.glob(expand(s["glob"]))):
                if os.path.isdir(d):
                    yield {"label": os.path.basename(d), "group": name, "root": d,
                           **common, "space_key": common["space_key"] or os.path.basename(d)}
```

`ORDER` gains `"gh_account", "on_create", "before_end"` at the end. In `main`, right after `rows = list(spaces(cfg))` (inside the `try`), add:

```python
        keys = [r["space_key"] for r in rows if r["worktrees"] == "1"]
        dup = next((k for k in keys if keys.count(k) > 1), None)
        if dup:
            raise ValueError(f"space key '{dup}' is used by more than one worktree space")
```

- [ ] **Step 4: Run all the tests.**
  ```bash
  tests/run.sh
  ```
  Expected: all pass. `wb-ui` zips 10 field names over 13 columns, and `zip` stops at the shorter list.
- [ ] **Step 5: Commit.**
  ```bash
  git add bin/wb-spaces tests/test_wb_spaces.sh
  git commit -m "feat: wb-spaces hook columns, unique keys, default session command"
  ```
  The message ends with the trailer from Global Constraints.

---

### Task 2: `lib/session.sh`: shared helpers

**Files:**
- Create: `lib/session.sh`
- Modify: `tests/lib.sh` (add `setup_repo`)
- Modify: `tests/fake/bd` (`show` and `update`)
- Create: `tests/fake/gh`
- Test: `tests/test_session_lib.sh`

**Interfaces:**
- Consumes: the 13-column rows from Task 1.
- Produces (sourced by Tasks 3 and 4, which first set `WB_HOME`):
  - `ws_rows`: prints `wb-spaces` output, and returns its exit code.
  - `ws_split ROW`: sets `S_LABEL S_GROUP S_ROOT S_BEADS S_WORKTREES S_SESSION_CMD S_KEY S_CLAUDE_CONFIG S_PROTOCOL S_SAFE S_GH_ACCOUNT S_ON_CREATE S_BEFORE_END`, with `-` turned into empty.
  - `ws_find_key ROWS KEY`: 0 and `S_*` set when a worktree space has that key.
  - `ws_keys ROWS`: prints the worktree keys, as `a, b`, or `none`.
  - `ws_bead_info ROOT ID`: 0 and sets `BEAD_TYPE` and `BEAD_TITLE` when `bd show ID --json` in ROOT returns the bead.
  - `ws_find_bead ROWS ID`: 0 with `S_*` and `BEAD_*` set, for the first worktree space (beads not `false`) whose store has the bead.
  - `ws_default_branch REPO`: the target of `origin/HEAD`, else `main`, else `master`, else the current branch, else `main`.
  - `ws_store_dir DIR TOP`: prints the nearest `DIR/../.beads` up to `TOP`, or nothing. Both paths must be resolved.
  - `ws_relpath PATH BASE`: prints PATH relative to BASE.
  - `ws_slugify WORDS…`: prints the slug; returns 1 with a message when it would be empty.
  - `ws_gh_switch ACCOUNT`: switches gh when another account is active. It only ever warns, and always returns 0.
  - `ws_run_hook CMD DIR`: runs `sh -c CMD` in DIR, and returns its exit code.
- Test helpers:
  - `setup_repo DIR [BRANCH]` in `tests/lib.sh`: a repo with a bare `DIR.origin.git` as `origin` and one pushed commit.
  - Fake `bd`, when `FAKE_BD_DIR` is unset:
    - `show ID …` walks up from `$PWD` to `.beads/fake.json` and prints `[<bead>]`, or exits 1;
    - `update …` exits `${FAKE_BD_UPDATE_RC:-0}`;
    - every call is logged to `$FAKE_BD_LOG` when that is set.
  - Fake `gh`: logs to `$FAKE_GH_LOG`; `auth status --active` reports `${FAKE_GH_ACTIVE:-someone}`; `auth switch` exits `${FAKE_GH_SWITCH_RC:-0}`.

- [ ] **Step 1: Test helpers.** Append to `tests/lib.sh`:

```bash
# setup_repo DIR [BRANCH]: a repo on BRANCH (default main) with one commit,
# pushed to a bare DIR.origin.git that is its origin.
setup_repo() {
  local h=$1 b=${2:-main}
  git init -q --bare -b "$b" "$h.origin.git"
  git init -q -b "$b" "$h"
  git -C "$h" config user.email t@example.com
  git -C "$h" config user.name t
  git -C "$h" remote add origin "$h.origin.git"
  : > "$h/README.md"; git -C "$h" add README.md; git -C "$h" commit -q -m init
  git -C "$h" push -q -u origin "$b"
}
```

In `tests/fake/bd`, replace the `FAKE_BD_DIR`-unset block (`if [ -z "${FAKE_BD_DIR:-}" ]; then … fi`) with the following, and add the two new lines to the header comment (`#   show/update without FAKE_BD_DIR: see below` and `# FAKE_BD_LOG: every call's args are appended to it`):

```bash
[ -n "${FAKE_BD_LOG:-}" ] && echo "$*" >> "$FAKE_BD_LOG"
if [ -z "${FAKE_BD_DIR:-}" ]; then
  case "${1:-}" in
    show)    # walk up to .beads/fake.json; print that one bead as a list, like bd
      d=$PWD
      while [ ! -f "$d/.beads/fake.json" ] && [ "$d" != / ]; do d=$(dirname "$d"); done
      [ -f "$d/.beads/fake.json" ] || { echo "Error: no beads database found" >&2; exit 1; }
      python3 - "$d/.beads/fake.json" "$2" <<'PY'
import json, sys
beads = [b for b in json.load(open(sys.argv[1])) if b.get("id") == sys.argv[2]]
if not beads:
    print(f"Error: no issue found matching {sys.argv[2]!r}", file=sys.stderr)
    sys.exit(1)
print(json.dumps(beads))
PY
      exit $? ;;
    update) exit "${FAKE_BD_UPDATE_RC:-0}" ;;
  esac
  [ -f .beads/fake.json ] && cat .beads/fake.json
  exit 0
fi
```

Create `tests/fake/gh` (make it executable):

```bash
#!/usr/bin/env bash
# Fake gh: logs argv to $FAKE_GH_LOG; reports $FAKE_GH_ACTIVE as the active
# account; 'auth switch' exits $FAKE_GH_SWITCH_RC (default 0).
[ -n "${FAKE_GH_LOG:-}" ] && echo "$*" >> "$FAKE_GH_LOG"
case "${1:-} ${2:-}" in
  "auth status") echo "github.com"; echo "  ✓ Logged in to github.com account ${FAKE_GH_ACTIVE:-someone} (keyring)" ;;
  "auth switch") exit "${FAKE_GH_SWITCH_RC:-0}" ;;
esac
```

- [ ] **Step 2: Write the failing tests.** Create `tests/test_session_lib.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
WB_HOME="$REPO"; . "$REPO/lib/session.sh"

assert_eq "slugify" "$(ws_slugify 'Fix the Login Page!')" "fix-the-login-page"
assert_eq "slugify joins words" "$(ws_slugify big idea)" "big-idea"
assert_eq "slugify cuts at 40, no trailing dash" \
  "$(ws_slugify 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbb')" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
ws_slugify '!!!' >/dev/null 2>&1; assert_eq "slugify of nothing fails" "$?" "1"

ws_split $'Acme\t-\t/r x\ttrue\t1\tcmd\tacme\t-\t-\t0\tbot\thook one\t-'
assert_eq "split: a field with spaces" "$S_ON_CREATE" "hook one"
assert_eq "split: a path with a space" "$S_ROOT" "/r x"
assert_eq "split: '-' becomes empty" "$S_GROUP|$S_BEFORE_END" "|"

setup_repo "$T/r1"
assert_eq "default branch: main" "$(ws_default_branch "$T/r1")" "main"
setup_repo "$T/r2" master
assert_eq "default branch: master when there is no main" "$(ws_default_branch "$T/r2")" "master"
git -C "$T/r1" checkout -q -b trunk; git -C "$T/r1" push -q origin trunk
git -C "$T/r1" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
assert_eq "default branch: origin/HEAD wins" "$(ws_default_branch "$T/r1")" "trunk"
git init -q -b dev "$T/r3"
assert_eq "default branch: else the current branch" "$(ws_default_branch "$T/r3")" "dev"

mkdir -p "$T/s/.beads" "$T/s/a/b"
assert_eq "store: nearest .beads up to the top" "$(ws_store_dir "$T/s/a/b" "$T/s")" "$T/s/.beads"
assert_eq "store: not above the top" "$(ws_store_dir "$T/s/a/b" "$T/s/a")" ""
assert_eq "relpath" "$(ws_relpath "$T/s/.beads" "$T/w/x")" "../../s/.beads"

mkdir -p "$T/hk"
out="$(WB_SPACE=acme ws_run_hook 'echo "$WB_SPACE in $(basename "$PWD")"; exit 3' "$T/hk")"; rc=$?
assert_eq "hook: runs in its folder with the variables" "$out" "acme in hk"
assert_eq "hook: its exit code comes back" "$rc" "3"

export FAKE_GH_LOG="$T/gh.log"
FAKE_GH_ACTIVE=acme-bot ws_gh_switch acme-bot
assert_eq "gh: no switch when already active" "$(cat "$T/gh.log" 2>/dev/null | grep -c switch)" "0"
out="$(FAKE_GH_ACTIVE=other ws_gh_switch acme-bot 2>&1)"
assert_contains "gh: switches when another account is active" "$(cat "$T/gh.log")" "auth switch --user acme-bot"
out="$(FAKE_GH_ACTIVE=other FAKE_GH_SWITCH_RC=1 ws_gh_switch acme-bot 2>&1)"; rc=$?
assert_contains "gh: a failed switch warns" "$out" "warning"
assert_eq "gh: and doesn't fail" "$rc" "0"
out="$(WB_GH=/nonexistent/gh ws_gh_switch acme-bot 2>&1)"; rc=$?
assert_contains "gh: missing gh warns" "$out" "gh not found"

unset FAKE_BD_DIR
mkdir -p "$T/b1/.beads" "$T/b2/.beads"
echo '[{"id":"x-1","title":"One","issue_type":"bug"}]' > "$T/b1/.beads/fake.json"
printf '[{"id":"y-1","title":"Two\\tthree\\nfour","issue_type":"task"}]\n' > "$T/b2/.beads/fake.json"
ROWS=$(printf 'B1\t-\t%s\ttrue\t1\tc\tb1\t-\t-\t0\t-\t-\t-\nB2\t-\t%s\ttrue\t1\tc\tb2\t-\t-\t0\t-\t-\t-\nP\t-\t/x\ttrue\t0\t-\tp\t-\t-\t0\t-\t-\t-' "$T/b1" "$T/b2")
ws_find_key "$ROWS" b2; rc=$?
assert_eq "find key: the worktree space" "$rc $S_ROOT" "0 $T/b2"
ws_find_key "$ROWS" p; assert_eq "find key: not a non-worktree space" "$?" "1"
assert_eq "keys: worktree spaces only" "$(ws_keys "$ROWS")" "b1, b2"
ws_find_bead "$ROWS" y-1; rc=$?
assert_eq "find bead: its space, type and a one-line title" "$rc $S_KEY $BEAD_TYPE $BEAD_TITLE" "0 b2 task Two three four"
FAKE_BD_WARN=1 ws_bead_info "$T/b1" x-1; rc=$?
assert_eq "bead info: a Warning line before the JSON is skipped" "$rc $BEAD_TITLE" "0 One"
ws_find_bead "$ROWS" zz-9; assert_eq "find bead: unknown id" "$?" "1"
WB_BD_TIMEOUT=1 FAKE_BD_SLEEP=5 ws_bead_info "$T/b1" x-1; assert_eq "bead info: a slow bd counts as not found" "$?" "1"
finish
```

The fake `bd show` prints `Warning: noisy` before its JSON when `FAKE_BD_WARN` is set, and sleeps `FAKE_BD_SLEEP` seconds first when that is set. Add both to the `show)` branch in Step 1: `[ -z "${FAKE_BD_SLEEP:-}" ] || sleep "$FAKE_BD_SLEEP"` as its first line, and `[ -z "${FAKE_BD_WARN:-}" ] || echo "Warning: noisy"` just before the `python3` call.

- [ ] **Step 3: Run the test and check it fails.**
  ```bash
  bash tests/test_session_lib.sh
  ```
  Expected: the source of `lib/session.sh` fails (no such file), and the assertions after it fail.

- [ ] **Step 4: Implement.** Create `lib/session.sh`:

```bash
# lib/session.sh — helpers shared by bin/new-session and bin/end-session.
# Source it after setting WB_HOME (this repo's top). bash 3.2.
# Spec: docs/specs/2026-10-18-session-scripts-design.md

# wb-spaces rows, one per line, in config order; returns wb-spaces' exit code.
ws_rows() { "$WB_HOME/bin/wb-spaces"; }

# ws_split ROW: one row into S_*; '-' becomes empty.
ws_split() {
  local f
  IFS=$'\t' read -r S_LABEL S_GROUP S_ROOT S_BEADS S_WORKTREES S_SESSION_CMD S_KEY \
    S_CLAUDE_CONFIG S_PROTOCOL S_SAFE S_GH_ACCOUNT S_ON_CREATE S_BEFORE_END <<< "$1"
  for f in S_LABEL S_GROUP S_ROOT S_BEADS S_WORKTREES S_SESSION_CMD S_KEY S_CLAUDE_CONFIG \
           S_PROTOCOL S_SAFE S_GH_ACCOUNT S_ON_CREATE S_BEFORE_END; do
    if [ "${!f}" = "-" ]; then printf -v "$f" '%s' ""; fi
  done
}

# ws_find_key ROWS KEY: S_* = the worktree space with that key.
ws_find_key() {
  local r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ws_split "$r"
    if [ "$S_WORKTREES" = 1 ] && [ "$S_KEY" = "$2" ]; then return 0; fi
  done <<< "$1"
  return 1
}

# ws_keys ROWS: the worktree space keys, for error messages.
ws_keys() {
  local r out=""
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ws_split "$r"
    if [ "$S_WORKTREES" = 1 ]; then out="$out${out:+, }$S_KEY"; fi
  done <<< "$1"
  printf '%s' "${out:-none}"
}

# ws_bead_info ROOT ID: BEAD_TYPE and BEAD_TITLE from 'bd show ID --json' in ROOT.
# bd can print 'Warning: …' lines before the JSON; a slow bd counts as not found.
ws_bead_info() {
  local out
  out=$(cd "$1" && perl -e 'alarm shift; exec @ARGV' "${WB_BD_TIMEOUT:-5}" \
        "${WB_BD:-bd}" show "$2" --json 2>/dev/null </dev/null) || return 1
  out=$(printf '%s' "$out" | python3 -c '
import json, re, sys
t = sys.stdin.read()
m = re.search(r"^[\[{]", t, re.M)
if not m:
    sys.exit(1)
b = json.JSONDecoder().raw_decode(t[m.start():])[0]
if isinstance(b, list):
    if not b:
        sys.exit(1)
    b = b[0]
clean = lambda v: " ".join(str(v or "").split())
print(clean(b.get("issue_type")), clean(b.get("title")), sep="\t")
') || return 1
  BEAD_TYPE=${out%%$'\t'*}
  BEAD_TITLE=${out#*$'\t'}
  [ -n "$BEAD_TITLE" ]
}

# ws_find_bead ROWS ID: S_* and BEAD_* for the first worktree space whose store has ID.
ws_find_bead() {
  local r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ws_split "$r"
    if [ "$S_WORKTREES" = 1 ] && [ "$S_BEADS" != false ] && ws_bead_info "$S_ROOT" "$2"; then
      return 0
    fi
  done <<< "$1"
  return 1
}

# ws_default_branch REPO: origin/HEAD's target, else main, else master, else the
# current branch. Both scripts use it, so they agree on what "merged" means.
ws_default_branch() {
  local b
  if b=$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s\n' "${b#origin/}"; return 0
  fi
  for b in main master; do
    if git -C "$1" show-ref --verify --quiet "refs/heads/$b"; then printf '%s\n' "$b"; return 0; fi
  done
  git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'main\n'
}

# ws_store_dir DIR TOP: the nearest .beads from DIR up to TOP (both resolved), or nothing.
ws_store_dir() {
  local d=$1
  while :; do
    if [ -d "$d/.beads" ]; then printf '%s\n' "$d/.beads"; return 0; fi
    if [ "$d" = "$2" ] || [ "$d" = / ]; then return 0; fi
    d=$(dirname "$d")
  done
}

# ws_relpath PATH BASE: PATH relative to BASE.
ws_relpath() { perl -MFile::Spec -e 'print File::Spec->abs2rel($ARGV[0], $ARGV[1]), "\n"' "$1" "$2"; }

# ws_slugify WORDS…: lowercase, non-alphanumerics to '-', dashes collapsed, 40 chars.
ws_slugify() {
  local s
  s=$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]' \
      | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' | cut -c1-40 | sed 's/-$//')
  if [ -z "$s" ]; then echo "'$*' has no letters or digits to name a branch with" >&2; return 1; fi
  printf '%s\n' "$s"
}

# ws_gh_switch ACCOUNT: make ACCOUNT gh's active account. Only ever warns: the
# fetch is tried either way, and it may already work.
ws_gh_switch() {
  local gh=${WB_GH:-gh} active
  if ! command -v "$gh" >/dev/null 2>&1; then
    echo "  warning: gh not found; can't switch GitHub to $1, so the fetch may fail." >&2
    return 0
  fi
  active=$("$gh" auth status --active 2>/dev/null | sed -n 's/.*account \([^ ]*\) .*/\1/p' | head -n 1) || true
  [ "$active" != "$1" ] || return 0
  if "$gh" auth switch --user "$1" >/dev/null 2>&1; then
    echo "→ gh: switched to $1"
  else
    echo "  warning: couldn't switch gh to $1, so the fetch may fail (try: gh auth login --user $1)." >&2
  fi
  return 0
}

# ws_run_hook CMD DIR: a space's hook, in DIR, with the WB_* variables the caller exported.
ws_run_hook() { (cd "$2" && sh -c "$1"); }
```

- [ ] **Step 5: Run the tests.**
  ```bash
  bash tests/test_session_lib.sh && tests/run.sh
  ```
  Expected: all pass. The launcher tests still pass, because the fake bd's `list` path is unchanged.
- [ ] **Step 6: Commit.**
  ```bash
  git add lib tests
  git commit -m "feat: shared session helpers, fake gh, bd show/update in the fake"
  ```
  The message ends with the trailer.

---

### Task 3: `bin/new-session`

**Files:**
- Create: `bin/new-session` (executable)
- Test: `tests/test_new_session.sh`

**Interfaces:**
- Consumes: Task 2's helpers.
- Produces:
  - **Usage:** `new-session <bead-id> [--space K] [--no-launch] [--safe]`, or `new-session <space-key> [topic…] [--no-launch] [--safe]`.
  - **`--no-launch`:** the last stdout line is `WORKTREE_DIR=<worktree>/<project prefix>`.
  - **With `WORKBENCH_DRY_RUN=1` and no `--no-launch`:** the last line is `DRY-RUN: cd <project> && env … claude …`.
  - **Exits:**
    - 2 for usage errors, an unknown key or bead, or a root that isn't in git;
    - 1 when the worktree already exists, the branch is checked out elsewhere, the fetch fails, the add fails, or `on_create` fails;
    - 0 on success.

- [ ] **Step 1: Write the failing tests.** Create `tests/test_new_session.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
unset CLAUDECODE FAKE_BD_DIR WORKBENCH_DRY_RUN
NS="$REPO/bin/new-session"
export WB_WORKTREES_DIR="$T/wts" WORKBENCH_CONFIG="$T/spaces.toml"
export FAKE_BD_LOG="$T/bd.log" FAKE_GH_LOG="$T/gh.log" HOOK_OUT="$T/hook.env"

# Acme: origin; project in app/; tracked bead store at the repo top.
A="$T/acme"; setup_repo "$A"
mkdir -p "$A/app" "$A/.beads"; : > "$A/app/keep"
cat > "$A/.beads/fake.json" <<'EOF'
[{"id":"acme-a1","title":"Fix the Login Page!","issue_type":"bug","status":"open"},
 {"id":"acme-a2","title":"Add CSV export","issue_type":"feature","status":"open"},
 {"id":"acme-a3","title":"Hook fails here","issue_type":"task","status":"open"}]
EOF
git -C "$A" add app .beads; git -C "$A" commit -q -m app; git -C "$A" push -q
# Beta: its own store, untracked; a safe space.
B="$T/beta"; setup_repo "$B"; mkdir -p "$B/.beads"
echo '[{"id":"bee-1","title":"Tidy","issue_type":"task"}]' > "$B/.beads/fake.json"
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
assert_eq "beads: redirect points at the real store" "$(cat "$WT/.beads/redirect")" "$(ws_rel() { perl -MFile::Spec -e 'print File::Spec->abs2rel($ARGV[0],$ARGV[1])' "$@"; }; ws_rel "$A/.beads" "$WT")"
assert_eq "beads: the redirect doesn't dirty the worktree" "$(git -C "$WT" status --porcelain)" ""
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
assert_eq "launch: config dir for the one command, prompts off" "$(printf '%s\n' "$out" | tail -1)" \
  "DRY-RUN: cd $W/acme-dry-run/app && env CLAUDE_CONFIG_DIR=$T/cfg claude --dangerously-skip-permissions"
out="$(WORKBENCH_DRY_RUN=1 "$NS" beta safe one 2>&1)"
assert_contains "safe space: no config dir, prompts on" "$(printf '%s\n' "$out" | tail -1)" "env -u CLAUDE_CONFIG_DIR claude"
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
finish
```

- [ ] **Step 2: Run the test and check it fails.**
  ```bash
  bash tests/test_new_session.sh
  ```
  Expected: every case fails, because `bin/new-session` doesn't exist yet.

- [ ] **Step 3: Implement.** Create `bin/new-session`, then `chmod +x bin/new-session`:

```bash
#!/usr/bin/env bash
# new-session — start a Claude Code session in its own git worktree, for any
# space with worktrees = true in spaces.toml.
# Spec: docs/specs/2026-10-18-session-scripts-design.md
set -euo pipefail
WB_HOME="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
# shellcheck source=../lib/session.sh
. "$WB_HOME/lib/session.sh"

usage() {
  cat <<'EOF'
Usage: new-session <bead-id> [--space <key>] [--no-launch] [--safe]
       new-session <space-key> [topic words...] [--no-launch] [--safe]

  <bead-id>     work on that bead: branch feat/<title> (fix/<title> for a bug); the bead is claimed
  <space-key>   explore: branch explore/<topic>, or explore/<timestamp> with no topic
  --space KEY   the bead's space (the launcher passes it); otherwise each
                worktree space's bead store is asked
  --no-launch   set up only; the last line is WORKTREE_DIR=<project folder>
  --safe        keep Claude's permission prompts on

Spaces: ~/.config/workbench/spaces.toml (WORKBENCH_CONFIG overrides).
Worktrees: ~/.worktrees/<key>-<slug> (WB_WORKTREES_DIR overrides).
EOF
}
die() { echo "new-session: $1" >&2; exit "${2:-2}"; }

LAUNCH=1; SAFE=0; SPACE=""; POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-launch) LAUNCH=0; shift ;;
    --safe) SAFE=1; shift ;;
    --space=*) SPACE=${1#--space=}; shift ;;
    --space)
      if [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then die "--space needs a space key"; fi
      SPACE=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "new-session: unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *) POS+=("$1"); shift ;;
  esac
done
if [ ${#POS[@]} -eq 0 ]; then usage >&2; exit 2; fi

ROWS="$(ws_rows)" || die "could not read spaces.toml (see above)"
FIRST=${POS[0]}; BEAD=""; TOPIC=""; BEAD_TYPE=""; BEAD_TITLE=""

# ---- which space, which shape
if [ -z "$SPACE" ] && ws_find_key "$ROWS" "$FIRST"; then
  TOPIC="${POS[*]:1}"
else
  BEAD=$FIRST
  [ ${#POS[@]} -eq 1 ] || die "a bead id takes no topic words (got: ${POS[*]})"
  if [ -n "$SPACE" ]; then
    ws_find_key "$ROWS" "$SPACE" || die "no worktree space has the key '$SPACE' (keys: $(ws_keys "$ROWS"))"
    ws_bead_info "$S_ROOT" "$BEAD" || die "bd show $BEAD failed in $S_ROOT; check the id"
  else
    ws_find_bead "$ROWS" "$BEAD" \
      || die "'$BEAD' is not a space key, and no worktree space's bead store has it (keys: $(ws_keys "$ROWS"))"
  fi
fi

# ---- repo, project folder, branch, worktree path
REPO=$(git -C "$S_ROOT" rev-parse --show-toplevel 2>/dev/null) || die "$S_ROOT is not in a git repo"
REPO=$(cd "$REPO" && pwd -P)
PREFIX=$(git -C "$S_ROOT" rev-parse --show-prefix); PREFIX=${PREFIX%/}
SOURCE="$REPO${PREFIX:+/$PREFIX}"

if [ -n "$BEAD" ]; then
  if [ "$BEAD_TYPE" = bug ]; then BRANCH="fix/$(ws_slugify "$BEAD_TITLE")"
  else BRANCH="feat/$(ws_slugify "$BEAD_TITLE")"; fi
elif [ -n "$TOPIC" ]; then
  BRANCH="explore/$(ws_slugify "$TOPIC")"
else
  BRANCH="explore/$(date +%Y-%m-%d-%H%M%S)"
fi
WT_DIR=${WB_WORKTREES_DIR:-$HOME/.worktrees}
WORKTREE="$WT_DIR/$S_KEY-${BRANCH#*/}"

# ---- pre-checks: nothing is created if these fail
[ ! -e "$WORKTREE" ] || die "worktree path already exists: $WORKTREE" 1
LIST=$(git -C "$REPO" worktree list --porcelain)
if grep -qxF "branch refs/heads/$BRANCH" <<< "$LIST"; then
  die "branch '$BRANCH' is already checked out in another worktree" 1
fi

# ---- base
DEFAULT=$(ws_default_branch "$REPO")
if git -C "$REPO" remote get-url origin >/dev/null 2>&1; then
  [ -z "$S_GH_ACCOUNT" ] || ws_gh_switch "$S_GH_ACCOUNT"
  echo "→ fetching origin"
  git -C "$REPO" fetch origin --quiet || die "git fetch origin failed in $REPO" 1
  # Refresh the main checkout only when it is on the default branch: 'git pull'
  # always merges into whatever branch is checked out.
  if [ "$(git -C "$REPO" symbolic-ref --quiet --short HEAD || true)" = "$DEFAULT" ]; then
    git -C "$REPO" pull --ff-only --quiet origin "$DEFAULT" 2>/dev/null \
      || echo "  note: couldn't fast-forward $DEFAULT in $REPO; the worktree still starts from origin/$DEFAULT."
  fi
  BASE="origin/$DEFAULT"
else
  BASE=$DEFAULT
fi

# ---- create
echo "→ creating worktree at $WORKTREE on branch $BRANCH (from $BASE)"
mkdir -p "$WT_DIR"
git -C "$REPO" worktree add --quiet -b "$BRANCH" "$WORKTREE" "$BASE" || die "git worktree add failed" 1
WORKTREE=$(cd "$WORKTREE" && pwd -P)
PROJECT="$WORKTREE${PREFIX:+/$PREFIX}"
[ -d "$PROJECT" ] || die "the worktree has no $PREFIX folder (is it committed on $BASE?); it is at $WORKTREE" 1

# ---- beads: point the worktree's .beads at the real store. git checks out only
# tracked files, and the database itself is never tracked.
STORE=$(ws_store_dir "$(cd "$S_ROOT" && pwd -P)" "$REPO")
if [ -n "$STORE" ]; then
  WT_BEADS="$WORKTREE${STORE#"$REPO"}"
  mkdir -p "$WT_BEADS"; chmod 700 "$WT_BEADS"
  ws_relpath "$STORE" "$(dirname "$WT_BEADS")" > "$WT_BEADS/redirect"
  # Keep the redirect out of git status, or end-session would call the tree dirty.
  rel="${WT_BEADS#"$WORKTREE"/}/redirect"
  if ! git -C "$WORKTREE" check-ignore -q -- "$rel"; then
    excl="$(git -C "$WORKTREE" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
    mkdir -p "$(dirname "$excl")"; echo "/$rel" >> "$excl"
  fi
  echo "→ beads: redirect → $STORE"
fi

# ---- the space's own setup
export WB_SPACE="$S_KEY" WB_WORKTREE="$WORKTREE" WB_PROJECT="$PROJECT" WB_SOURCE="$SOURCE" \
       WB_BRANCH="$BRANCH" WB_BEAD="$BEAD"
if [ -n "$S_ON_CREATE" ]; then
  echo "→ on_create: $S_ON_CREATE"
  if ! ws_run_hook "$S_ON_CREATE" "$PROJECT"; then
    echo "new-session: on_create failed; the worktree is still at $WORKTREE." >&2
    echo "             Remove it with: end-session --force $WORKTREE" >&2
    exit 1
  fi
fi

# ---- claim (append: --notes would replace the bead's notes)
if [ -n "$BEAD" ]; then
  echo "→ claiming $BEAD"
  (cd "$SOURCE" && "${WB_BD:-bd}" update "$BEAD" --claim \
     --append-notes "Branch: $BRANCH (worktree at $WORKTREE)" </dev/null >/dev/null) \
    || echo "  warning: couldn't claim $BEAD; the session starts anyway." >&2
fi

cat <<EOF

────────────────────────────────────────
  Session ready
    space:    $S_KEY
    worktree: $WORKTREE
    branch:   $BRANCH
    project:  $PROJECT
    bead:     ${BEAD:-<none>}
────────────────────────────────────────
EOF

if [ "$LAUNCH" -eq 0 ]; then
  echo "WORKTREE_DIR=$PROJECT"   # the launcher reads this last line
  exit 0
fi

# ---- launch Claude on the space's account
if [ -n "$S_CLAUDE_CONFIG" ]; then ENVS=(env "CLAUDE_CONFIG_DIR=$S_CLAUDE_CONFIG"); else ENVS=(env -u CLAUDE_CONFIG_DIR); fi
CMD=(claude)
if [ "$SAFE" -eq 0 ] && [ "$S_SAFE" != 1 ]; then CMD+=(--dangerously-skip-permissions); fi
cd "$PROJECT"
if [ -n "${WORKBENCH_DRY_RUN:-}" ]; then
  echo "DRY-RUN: cd $PROJECT && ${ENVS[*]} ${CMD[*]}"
  exit 0
fi
# Inside a Claude session (or with no terminal) an interactive claude can't start.
if [ -n "${CLAUDECODE:-}" ] || ! [ -t 0 ]; then
  cat <<EOF

  Running inside a Claude session (or with no terminal), so a new interactive
  Claude can't start here. Open a new terminal and run:
    cd $PROJECT
    ${ENVS[*]} ${CMD[*]}
EOF
  exit 0
fi
exec "${ENVS[@]}" "${CMD[@]}"
```

- [ ] **Step 4: Run the tests.**
  ```bash
  bash tests/test_new_session.sh && tests/run.sh
  ```
  Expected: all pass.
- [ ] **Step 5: Commit.**
  ```bash
  git add bin/new-session tests/test_new_session.sh
  git commit -m "feat: new-session for any worktree space"
  ```
  The message ends with the trailer.

---

### Task 4: `bin/end-session`

**Files:**
- Create: `bin/end-session` (executable)
- Test: `tests/test_end_session.sh`

**Interfaces:**
- Consumes: Task 2's helpers.
- Produces: `end-session [<path>] [--force] [--base=<branch>]`.
  - **Exits:**
    - 2 for usage errors;
    - 1 for a refusal: the main checkout, not a worktree, detached, dirty, unpushed, `before_end` failed, or the config can't be read without `--force`;
    - 0 when the worktree was removed.
  - **Stderr** says when no space claims the repo, or the config couldn't be read (with `--force`).

- [ ] **Step 1: Write the failing tests.** Create `tests/test_end_session.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
ES="$REPO/bin/end-session"
export WORKBENCH_CONFIG="$T/spaces.toml" MARKERS="$T/markers"; mkdir -p "$MARKERS"
GATE="before_end = 'test -f \"\$MARKERS/\$WB_SHA\" || { echo \"predeploy has not passed\"; exit 1; }'"
# conf ROOT [EXTRA-LINE]: one worktree space "acme" at ROOT
conf() { printf '[[space]]\nname = "Acme"\nroot = "%s"\nworktrees = true\nspace_key = "acme"\n%s\n' "$1" "${2:-}" > "$WORKBENCH_CONFIG"; }
# wt REPO BRANCH [BASE]: a worktree beside REPO; prints its path
wt() { local p="$1-wt-$(printf '%s' "$2" | tr / -)"; git -C "$1" worktree add -q -b "$2" "$p" "${3:-main}"; printf '%s\n' "$p"; }
commit() { echo "$2" > "$1/$2.txt"; git -C "$1" add "$2.txt"; git -C "$1" commit -q -m "add $2"; }
gone()  { if [ ! -e "$2" ]; then ok "$1"; else bad "$1" "still there: $2"; fi; }
there() { if [ -e "$2" ]; then ok "$1"; else bad "$1" "missing: $2"; fi; }
branch_gone() { if git -C "$2" show-ref --verify --quiet "refs/heads/$3"; then bad "$1"; else ok "$1"; fi; }
branch_kept() { if git -C "$2" show-ref --verify --quiet "refs/heads/$3"; then ok "$1"; else bad "$1"; fi; }

# 1 merged branch is deleted
h="$T/r1"; setup_repo "$h"; conf "$h"
w=$(wt "$h" feat/one); commit "$w" x; git -C "$w" push -q -u origin feat/one
git -C "$h" merge -q --ff-only feat/one; git -C "$h" push -q origin main
"$ES" "$w" >/dev/null 2>&1; assert_eq "merged: exits 0" "$?" "0"
gone "merged: worktree removed" "$w"; branch_gone "merged: branch deleted" "$h" feat/one

# 2 unmerged but pushed: removed, branch kept
w=$(wt "$h" feat/two); commit "$w" y; git -C "$w" push -q -u origin feat/two
"$ES" "$w" >/dev/null 2>&1
gone "unmerged: worktree removed" "$w"; branch_kept "unmerged: branch kept" "$h" feat/two

# 3 --force keeps even a merged branch
w=$(wt "$h" feat/three); commit "$w" z; git -C "$w" push -q -u origin feat/three
git -C "$h" merge -q --ff-only feat/three; git -C "$h" push -q origin main
"$ES" --force "$w" >/dev/null 2>&1
gone "force: worktree removed" "$w"; branch_kept "force: branch kept" "$h" feat/three

# 4 --base=develop
git -C "$h" checkout -q -b develop; git -C "$h" push -q -u origin develop; git -C "$h" checkout -q main
w=$(wt "$h" feat/four develop); commit "$w" w; git -C "$w" push -q -u origin feat/four
git -C "$h" checkout -q develop; git -C "$h" merge -q --ff-only feat/four; git -C "$h" push -q origin develop; git -C "$h" checkout -q main
"$ES" --base=develop "$w" >/dev/null 2>&1
gone "base: worktree removed" "$w"; branch_gone "base: merged into develop, deleted" "$h" feat/four

# 5 never-pushed, no commits: nothing at risk
w=$(wt "$h" fix/five)
"$ES" "$w" >/dev/null 2>&1; assert_eq "empty branch: exits 0" "$?" "0"
gone "empty branch: removed" "$w"; branch_gone "empty branch: deleted" "$h" fix/five

# 6 merged, then rebased past its own stale upstream
w=$(wt "$h" feat/six); commit "$w" v; git -C "$w" push -q -u origin feat/six
git -C "$h" merge -q --no-ff -m "merge six" feat/six; git -C "$h" push -q origin main
git -C "$w" fetch -q origin; git -C "$w" rebase -q origin/main
"$ES" "$w" >/dev/null 2>&1; assert_eq "ahead of stale upstream: exits 0" "$?" "0"
branch_gone "ahead of stale upstream: deleted" "$h" feat/six

# 7 before_end skipped when nothing is at risk
conf "$h" "$GATE"
w=$(wt "$h" fix/seven)
"$ES" "$w" >/dev/null 2>&1; assert_eq "gate: skipped with nothing at risk" "$?" "0"

# 8 never-pushed work is refused
w=$(wt "$h" feat/eight); commit "$w" u
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "unpushed: refused" "$rc" "1"; assert_contains "unpushed: says so" "$out" "not pushed"
there "unpushed: worktree kept" "$w"

# 9 before_end refuses real work until it passes
w=$(wt "$h" feat/nine); commit "$w" t; git -C "$w" push -q -u origin feat/nine
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "gate: refuses without a marker" "$rc" "1"
assert_contains "gate: shows the hook's output" "$out" "predeploy has not passed"
there "gate: worktree kept" "$w"
touch "$MARKERS/$(git -C "$w" rev-parse HEAD)"
"$ES" "$w" >/dev/null 2>&1; assert_eq "gate: passes with a marker" "$?" "0"

# 10 dirty is refused, even with nothing beyond main
w=$(wt "$h" fix/ten); echo s > "$w/s.txt"
"$ES" "$w" >/dev/null 2>&1; assert_eq "dirty: refused" "$?" "1"; there "dirty: kept" "$w"
rm "$w/s.txt"

# 11 hook variables, project below the repo top, run from inside the worktree
mkdir -p "$h/app"; : > "$h/app/keep"; git -C "$h" add app; git -C "$h" commit -q -m app; git -C "$h" push -q origin main
conf "$h/app" "before_end = 'env | grep ^WB_ | sort > \"\$MARKERS/env\"'"
w=$(wt "$h" feat/eleven); commit "$w" e; git -C "$w" push -q -u origin feat/eleven
sha=$(git -C "$w" rev-parse HEAD)
(cd "$w/app" && "$ES" >/dev/null 2>&1); assert_eq "from inside: exits 0" "$?" "0"
gone "from inside: removed" "$w"
env_out="$(cat "$MARKERS/env")"
assert_contains "hook: WB_SPACE" "$env_out" "WB_SPACE=acme"
assert_contains "hook: WB_WORKTREE" "$env_out" "WB_WORKTREE=$w"
assert_contains "hook: WB_PROJECT" "$env_out" "WB_PROJECT=$w/app"
assert_contains "hook: WB_SOURCE" "$env_out" "WB_SOURCE=$h/app"
assert_contains "hook: WB_SHA" "$env_out" "WB_SHA=$sha"

# 12 no origin
n="$T/noorigin"; git init -q -b main "$n"; git -C "$n" config user.email t@example.com; git -C "$n" config user.name t
commit "$n" base; conf "$n"
w=$(wt "$n" feat/local); commit "$w" l
"$ES" "$w" >/dev/null 2>&1; assert_eq "no origin: unmerged work ends" "$?" "0"
branch_kept "no origin: unmerged branch kept" "$n" feat/local
w=$(wt "$n" feat/merged); commit "$w" m; git -C "$n" merge -q --ff-only feat/merged
"$ES" "$w" >/dev/null 2>&1; branch_gone "no origin: merged branch deleted" "$n" feat/merged

# 13 no space claims the repo
conf "$T/markers"
w=$(wt "$h" fix/thirteen)
out="$("$ES" "$w" 2>&1)"; rc=$?
assert_eq "unclaimed: goes ahead" "$rc" "0"
assert_contains "unclaimed: says no before_end ran" "$out" "no before_end check ran"

# 14 unreadable config fails closed
w=$(wt "$h" fix/fourteen)
out="$(WORKBENCH_CONFIG="$T/missing.toml" "$ES" "$w" 2>&1)"; rc=$?
assert_eq "no config: refused" "$rc" "1"; there "no config: kept" "$w"
assert_contains "no config: says why" "$out" "could not read spaces.toml"
WORKBENCH_CONFIG="$T/missing.toml" "$ES" --force "$w" >/dev/null 2>&1
gone "no config + --force: removed" "$w"

# 15 a master repo
m="$T/master"; setup_repo "$m" master; conf "$m"
w=$(wt "$m" feat/mm master); commit "$w" q; git -C "$w" push -q -u origin feat/mm
git -C "$m" merge -q --ff-only feat/mm; git -C "$m" push -q origin master
"$ES" "$w" >/dev/null 2>&1; branch_gone "master repo: merged branch deleted" "$m" feat/mm

# 16 refusals
conf "$h"
out="$("$ES" "$h" 2>&1)"; rc=$?
assert_eq "main checkout: refused" "$rc" "1"; assert_contains "main checkout: says so" "$out" "main checkout"
out="$("$ES" "$T/markers" 2>&1)"; rc=$?
assert_contains "not a repo: refused" "$out" "not in a git repo"
finish
```

- [ ] **Step 2: Run the test and check it fails.**
  ```bash
  bash tests/test_end_session.sh
  ```
  Expected: every case fails, because `bin/end-session` doesn't exist yet.

- [ ] **Step 3: Implement.** Create `bin/end-session`, then `chmod +x bin/end-session`:

```bash
#!/usr/bin/env bash
# end-session — remove a session's worktree once its work is safe, for any
# space in spaces.toml. Spec: docs/specs/2026-10-18-session-scripts-design.md
set -euo pipefail
WB_HOME="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
# shellcheck source=../lib/session.sh
. "$WB_HOME/lib/session.sh"

usage() {
  cat <<'EOF'
Usage: end-session [<worktree-path>] [--force] [--base=<branch>]

  <worktree-path>   default: the worktree you are in
  --force           skip the dirty, unpushed and before_end checks; keep the branch
  --base=<branch>   the branch "merged" is checked against
                    (default: the repo's default branch)
EOF
}
die() { echo "end-session: $1" >&2; exit "${2:-2}"; }

FORCE=0; TARGET=""; BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --base=*) BASE=${1#*=}; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "end-session: unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "$TARGET" ] || die "only one worktree path, got another: $1"
       TARGET=$1; shift ;;
  esac
done

# ---- the worktree, and the main checkout it belongs to
[ -n "$TARGET" ] || TARGET=$PWD
[ -d "$TARGET" ] || die "no such folder: $TARGET"
TARGET=$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null) || die "$TARGET is not in a git repo" 1
TARGET=$(cd "$TARGET" && pwd -P)
COMMON=$(git -C "$TARGET" rev-parse --path-format=absolute --git-common-dir)
MAIN=$(cd "$COMMON/.." && pwd -P)
[ "$TARGET" != "$MAIN" ] || die "refusing to remove the main checkout ($MAIN)" 1
REGISTERED=0
LIST=$(git -C "$MAIN" worktree list --porcelain)
while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      if [ "$(cd "${line#worktree }" 2>/dev/null && pwd -P)" = "$TARGET" ]; then REGISTERED=1; fi ;;
  esac
done <<< "$LIST"
[ "$REGISTERED" = 1 ] || die "$TARGET is not a registered git worktree" 1
BRANCH=$(git -C "$TARGET" rev-parse --abbrev-ref HEAD)
[ "$BRANCH" != HEAD ] || die "the worktree is on a detached HEAD, so its branch is unknown" 1
echo "→ worktree: $TARGET (branch: $BRANCH)"

# ---- its space. Fail closed: before_end may be the only thing between
# unverified work and its removal.
FOUND=0
if ROWS="$(ws_rows)"; then
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    ws_split "$r"
    top=$(git -C "$S_ROOT" rev-parse --show-toplevel 2>/dev/null) || continue
    if [ "$(cd "$top" && pwd -P)" = "$MAIN" ]; then FOUND=1; break; fi
  done <<< "$ROWS"
  [ "$FOUND" = 1 ] || echo "end-session: no space in spaces.toml claims $MAIN; no before_end check ran." >&2
elif [ "$FORCE" = 1 ]; then
  echo "end-session: could not read spaces.toml; going ahead because of --force." >&2
else
  die "could not read spaces.toml (see above), so this space's before_end check can't run. Fix the config, or use --force." 1
fi

[ -n "$BASE" ] || BASE=$(ws_default_branch "$MAIN")
HAS_ORIGIN=0
if git -C "$MAIN" remote get-url origin >/dev/null 2>&1; then HAS_ORIGIN=1; fi
REF=$BASE; if [ "$HAS_ORIGIN" = 1 ]; then REF="origin/$BASE"; fi

# ---- checks
if [ "$FORCE" = 0 ] && [ -n "$(git -C "$TARGET" status --porcelain)" ]; then
  echo "end-session: the worktree has uncommitted changes. Commit them, or use --force:" >&2
  git -C "$TARGET" status --short >&2
  exit 1
fi

NOTHING=0   # every commit already on the base: nothing to push or verify
if [ "$FORCE" = 0 ]; then
  if [ "$HAS_ORIGIN" = 1 ]; then git -C "$TARGET" fetch --quiet origin "$BASE" 2>/dev/null || true; fi
  if git -C "$TARGET" merge-base --is-ancestor HEAD "$REF" 2>/dev/null; then
    NOTHING=1; echo "→ no commits beyond $REF — nothing to push or verify"
  fi
fi

if [ "$FORCE" = 0 ] && [ "$NOTHING" = 0 ] && [ "$HAS_ORIGIN" = 1 ]; then
  git -C "$TARGET" fetch --quiet origin "$BRANCH" 2>/dev/null || true
  LOCAL=$(git -C "$TARGET" rev-parse HEAD)
  REMOTE=$(git -C "$TARGET" rev-parse --verify --quiet "origin/$BRANCH" || true)
  [ -n "$REMOTE" ] || die "'$BRANCH' is not pushed to origin (use --force to override)" 1
  [ "$LOCAL" = "$REMOTE" ] || die "'$BRANCH' has unpushed commits (origin at ${REMOTE:0:10}, local at ${LOCAL:0:10})" 1
fi

if [ "$FOUND" = 1 ] && [ -n "$S_BEFORE_END" ] && [ "$FORCE" = 0 ] && [ "$NOTHING" = 0 ]; then
  PREFIX=$(git -C "$S_ROOT" rev-parse --show-prefix); PREFIX=${PREFIX%/}
  PROJECT="$TARGET${PREFIX:+/$PREFIX}"; [ -d "$PROJECT" ] || PROJECT=$TARGET
  export WB_SPACE="$S_KEY" WB_WORKTREE="$TARGET" WB_PROJECT="$PROJECT" \
         WB_SOURCE="$MAIN${PREFIX:+/$PREFIX}" WB_BRANCH="$BRANCH" WB_BEAD=""
  WB_SHA=$(git -C "$TARGET" rev-parse HEAD); export WB_SHA
  echo "→ before_end: $S_BEFORE_END"
  ws_run_hook "$S_BEFORE_END" "$PROJECT" \
    || die "before_end failed, so the worktree stays. Fix what it says, or use --force." 1
fi

# ---- remove, then tidy the branch
echo "→ removing worktree $TARGET"
cd "$MAIN"   # the worktree may be our own folder
if [ "$FORCE" = 1 ]; then git -C "$MAIN" worktree remove --force "$TARGET"
else git -C "$MAIN" worktree remove "$TARGET"; fi
if [ "$FORCE" = 1 ]; then
  echo "✓ session ended (forced). Branch '$BRANCH' kept — check it by hand."
  exit 0
fi
if [ "$HAS_ORIGIN" = 1 ]; then git -C "$MAIN" fetch --quiet origin "$BASE" 2>/dev/null || true; fi
MERGED=0
if git -C "$MAIN" merge-base --is-ancestor "$BRANCH" "$BASE" 2>/dev/null; then MERGED=1; fi
if [ "$HAS_ORIGIN" = 1 ] && git -C "$MAIN" merge-base --is-ancestor "$BRANCH" "origin/$BASE" 2>/dev/null; then MERGED=1; fi
if [ "$MERGED" = 1 ]; then
  # -D, not -d: ancestry is proven above, and -d re-checks against the branch's
  # own (possibly stale) upstream.
  git -C "$MAIN" branch -D "$BRANCH" >/dev/null
  echo "✓ session ended. Branch '$BRANCH' is merged into $BASE and was deleted."
else
  echo "✓ session ended. Branch '$BRANCH' is not merged into $BASE, so it was kept."
  echo "  Delete it later with: git -C $MAIN branch -d $BRANCH"
fi
```

- [ ] **Step 4: Run the tests.**
  ```bash
  bash tests/test_end_session.sh && tests/run.sh
  ```
  Expected: all pass.
- [ ] **Step 5: Commit.**
  ```bash
  git add bin/end-session tests/test_end_session.sh
  git commit -m "feat: end-session for any space; fails closed when the config can't be read"
  ```
  The message ends with the trailer.

---

### Task 5: The launcher passes `--space`; example config and docs

**Files:**
- Modify: `shell/workbench.zsh` (`_wb_start_bead`)
- Modify: `tests/test_handoff.sh`
- Modify: `tests/test_launch.sh`
- Modify: `spaces.example.toml`
- Modify: `CLAUDE.md` (Build & Test)

**Interfaces:**
- Consumes: Task 3's `--space`.
- Produces: in a worktree space, the launcher runs `<session_cmd> <id> --space <key> --no-launch`.

- [ ] **Step 1: Write the failing tests.**
  - In `tests/test_handoff.sh`, change the expected log line `"acme-a2 --no-launch"` (both places) to `"acme-a2 --space acme --no-launch"`.
  - In `tests/test_launch.sh`, change `assert_eq "menu: bead goes through new-session" … "acme-a2 --no-launch"` to `"acme-a2 --space acme --no-launch"`.
- [ ] **Step 2: Run the tests and check they fail.**
  ```bash
  bash tests/test_handoff.sh; bash tests/test_launch.sh
  ```
  Expected: those assertions fail.
- [ ] **Step 3: Implement.**
  - In `shell/workbench.zsh`, `_wb_start_bead`: `if [[ $s[5] == 1 ]]; then _wb_session_cd $1 --space $s[7] || return 0`.
  - `spaces.example.toml`: replace the Acme block's `session_cmd` lines with:

```toml
space_key     = "acme"              # new-session/end-session call this space by it
claude_config = "~/.claude-acme"    # optional: a non-default Claude profile
protocol      = "docs/PROTOCOL.md"  # optional: read first in every session
# safe        = true                # keep Claude's permission prompts on
# Optional, worktree spaces only. Hooks are one line, run with sh -c, with
# WB_SPACE WB_WORKTREE WB_PROJECT WB_SOURCE WB_BRANCH WB_BEAD set (WB_SHA too for before_end).
# gh_account  = "acme-bot"                                  # gh account to switch to before fetching
# on_create   = "~/.config/workbench/hooks/acme-setup"      # after the worktree is made
# before_end  = 'test -f ~/.local/state/acme-ok/$WB_SHA'    # end-session refuses if this fails
# session_cmd = "my-session"        # default: workbench's own bin/new-session
```

  - `CLAUDE.md` Build & Test gains two lines:

```bash
new-session <bead-id>|<space-key> [topic]   # worktree session for a worktrees = true space
end-session [<worktree>]                    # remove it once the work is merged/pushed/verified
```

- [ ] **Step 4: Run all the tests and the leak check.**
  ```bash
  tests/run.sh
  bash scripts/check-leaks.sh
  ```
  Expected: all tests pass. The leak check flags only the docs it flagged before (the specs and plans), with no hits under `bin/`, `lib/` or `tests/`.
- [ ] **Step 5: Commit.**
  ```bash
  git add shell tests spaces.example.toml CLAUDE.md
  git commit -m "feat: launcher passes --space; example config shows the hooks"
  ```
  The message ends with the trailer.

---

### Task 6: Final review, merge, cutover, acceptance

- [ ] **Step 1: Final review.** Run a fresh whole-branch review against this plan's Review Focus. Fix Critical and Important findings test-first, and record minor ones in the hand-off.
- [ ] **Step 2: Merge.** `superpowers:finishing-a-development-branch` (merge to `main` locally, tests green on `main`).
- [ ] **Step 3: Cutover,** in the same sitting, with Tommy's OK. This is the spec's Cutover section.
  1. Write `~/.config/workbench/hooks/acme-setup` and make it executable:

     ```bash
     #!/usr/bin/env bash
     # Acme on_create hook for workbench's new-session. Private: lives only on this machine.
     set -euo pipefail
     ln -s "$WB_SOURCE/.env.local" "$WB_PROJECT/.env.local"
     echo "→ linked .env.local"
     echo "→ npm install (Turbopack rejects a symlinked node_modules; ~20s)"
     (cd "$WB_PROJECT" && npm install --no-audit --no-fund --silent)
     ```
  2. In the Acme space of `~/.config/workbench/spaces.toml`:
     - delete `session_cmd`;
     - add `gh_account`, plus `on_create = "~/.config/workbench/hooks/acme-setup"`;
     - add `before_end = 'test -f ~/.local/state/acme-predeploy/$WB_SHA || { echo "predeploy has not passed for $WB_SHA; run: acme-predeploy"; exit 1; }'`.
  3. Remove the `~/.local/bin/new-session` and `~/.local/bin/end-session` links (they point at `~/scripts`), then run `./install.sh`.
  4. Check:
     - `readlink ~/.local/bin/new-session` points into `~/dev/workbench/bin`;
     - `wb-spaces | cut -f6,11-13` shows the Acme row with the workbench path and the three hooks;
     - `end-session --help` shows the new usage.
- [ ] **Step 4: Acceptance.** Tommy runs these in a new Terminal window:
  1. An Acme bead from the launcher gets a worktree, the `.env.local` link, `npm install`, the claim note, and Claude on the Acme account.
  2. `end-session` on an Acme worktree with unmerged, pushed work refuses until predeploy has passed.
  3. A personal repo given `worktrees = true` gets a worktree session from the launcher, and `end-session` removes it.
  4. `scripts/check-leaks.sh` shows no new private names.
- [ ] **Step 5:** `bd close wb-5jy` once acceptance passes.
