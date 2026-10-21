# Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every new Terminal window opens on a start screen. You pick a space, then a bead or "something new", and Claude starts in the right folder, on the right account, already briefed.

**Architecture:** One zsh file (`shell/workbench.zsh`) defines `launch` and a run-once `precmd` hook. Being a function, `launch` can `cd` the user's shell. It draws two fzf screens, with a numbered-menu fallback when fzf is missing. Three small stdlib-Python helpers do the work behind it:
- `wb-spaces` reads the private TOML config.
- `wb-backlog` reads one space's beads through `bd`, with a timeout.
- `wb-ui` holds the screen helpers that fzf calls as child processes.

Worktree spaces go through `new-session --no-launch`, which now prints `WORKTREE_DIR=<path>` last; the launcher then starts Claude itself.

**Tech Stack:** zsh 5.9, Python ≥ 3.11 (stdlib only), fzf (brew, 0.74.5 at time of writing), bd 1.1.0. Tests are plain bash 3.2 scripts with fake `bd`, `new-session` and `claude` on `PATH`.

**Spec:** `docs/specs/2026-10-16-launcher-design.md`. Read it first; this plan argues from it.

## Global Constraints

- **macOS only:** `/bin/bash` is 3.2, so test scripts must not use bash 4+ features (no `${x,,}`, no `declare -A`, no `mapfile`).
- **Python:** `python3` ≥ 3.11, stdlib only. `wb-spaces` exits with a clear message on an older Python.
- **Config:** `~/.config/workbench/spaces.toml`, overridable with `WORKBENCH_CONFIG=<path>` (tests use the override). The repo ships only `spaces.example.toml`.
- **No real names in the repo:** no space name, path, account, employer or email in code, fixtures or the example config. Fixtures use `Acme`, `Beta`, `Gamma` and bead ids `acme-*`, `bee-*`.
- **bd read timeout:** 3 seconds per read, overridable with `WB_BD_TIMEOUT` (tests use `1`).
- **bd location:** `bd` is looked up as `WB_BD` (default `bd`). Tests set `WB_BD=/nonexistent/bd` to simulate "bd not installed".
- **`launch` never calls `exit`:** it would close the Terminal window. Always `return`, and `launch` itself always returns 0.
- **`CLAUDE_CONFIG_DIR` is never exported:**
  - It is set per command (`env CLAUDE_CONFIG_DIR=<dir> claude …`).
  - It is removed for spaces with no `claude_config` (`env -u CLAUDE_CONFIG_DIR claude …`).
  - Using `env claude` also bypasses the user's `claude()` shell function.
- **Prompts default off:** every launch passes `--dangerously-skip-permissions` unless the space sets `safe = true`.
- **Tests must never touch real systems:**
  - Never run the real `claude`, `new-session` or `bd`.
  - Fakes go first on `PATH`, and `WORKBENCH_DRY_RUN=1` is set for anything that would start Claude.
  - Any test of the auto-start guards runs with `env -u CLAUDECODE`, because the tests themselves usually run inside Claude.
- **TSV fields are never empty:** zsh collapses consecutive tabs when splitting, so an empty value is written as `-`. The exception is fzf display columns 4 and 5 in screen-2 lines, which zsh never splits.
- **Commits:**
  - Only if Tommy authorises them in Task 0, with the identity he picks there.
  - Every message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  - Nothing is pushed in this plan.

## Spec Deviations (decided in this plan; Tommy confirms at plan review)

1. **Re-read is `ctrl-r`, not `r`,** and **`q` on screen 1 is a list row plus Esc,** not a bare key. In a type-to-filter list, a bare `r` or `q` is filter text.
2. **"unrouted" is dropped from the summary.** The spec never defines it, and it is Acme-specific (`ws:` labels).
   - Screen 1 shows `NOW n · NEXT n · claimed n` for wave spaces and `open n · claimed n` otherwise, one line per space.
   - There is no separate group summary line.
3. **`wave:0` beads sort into "everything else",** by priority, exactly as the spec orders. Acme has 4 of them today.
4. **Section headers on screen 2 are rows that can't be picked.** Choosing one re-shows the screen, and typing a filter hides them.
5. **`◐` in a plain (non-worktree) space** asks "start anyway? [y/N]". The spec only defines `◐` for worktree spaces.
6. **The test seam is `grep -F`, not `fzf --filter`.** `WB_TEST_PICK_SPACE` and `WB_TEST_PICK_WORK` pick the first line containing the text. That makes the tests deterministic and independent of fzf.
7. **A third helper, `bin/wb-ui`, exists.** fzf's `reload`, `preview` and `start` actions run in a child process, so they can't call zsh functions.
8. **`wb-backlog` takes the space's root path, not its name.** That avoids a second config read.

## Review Focus

1. **Parent shell already has `CLAUDE_CONFIG_DIR` exported** (for example, a tab opened from an Acme session), and you pick a personal project. Expected: Claude starts on the default account. *Test: Task 4, "exported CLAUDE_CONFIG_DIR is removed for a plain space".*
2. **You hit Esc, give EOF or answer `q` on either screen, or `new-session` fails partway.** Expected: a normal prompt, the window stays open, and the folder is unchanged (or `$HOME` after a failed `new-session`). *Tests: Task 4, "new-session failure lands in HOME"; Task 5, "q on screen 1 leaves a working shell" and "an internal error is trapped".*
3. **bd prints a `Warning:` line on stdout before the JSON** (lens's permissions warning), or a locked store returns `[]` with exit 0. Expected: counts are still right, and a double-empty read shows `0 open (ctrl-r to re-check)` rather than a confident 0. *Tests: Task 2, "warning line before JSON" and "empty twice".*
4. **A bead title or description contains a tab, a newline, quotes or `$(…)`.** Expected: rows stay aligned, nothing is executed, and the preview shows it literally. *Test: Task 2, "hostile title is cleaned and not executed".*
5. **A space root with a space in its path, a glob matching plain files, or a root that no longer exists.** Expected: the directory is listed and `cd` works, files are skipped, and the missing root is skipped with a warning. *Tests: Task 1, "glob" and "missing root"; Task 4, "plain bead" (its root has a space).*

---

## File Map

| File | Responsibility |
|---|---|
| `bin/wb-spaces` | Parse `spaces.toml`, expand globs, print one 10-field TSV line per space. Also `--terminals` and `--leak-terms`. |
| `bin/wb-backlog` | `list` / `summary` / `preview` for one space root, via `bd list -n 0 --json`, with a timeout, classification, retry, ordering and a snapshot. |
| `bin/wb-ui` | Screen helpers fzf runs: `render-spaces`, `fill-counts`, `render-work`. |
| `shell/workbench.zsh` | `launch`, the screens, the handoff, the auto-start guards and the run-once `precmd` hook. |
| `prompts/work-on-bead.txt`, `prompts/something-new.txt` | Opening prompts with `{id}`, `{space}` and `{protocol}` placeholders. |
| `spaces.example.toml` | Generic example config. |
| `install.sh` | Links `bin/*` into `~/.local/bin` and prints the `~/.zshrc` line. Never edits `~/.zshrc`. |
| `scripts/check-leaks.sh` | Pre-push check: fails if tracked files name anything from the private config. |
| `tests/lib.sh`, `tests/run.sh`, `tests/test_*.sh` | Assert helpers, the runner and one test file per unit. |
| `tests/fake/bd`, `tests/fake/new-session`, `tests/fake/claude` | Fakes. |
| `tests/fixtures/*.json` | Bead JSON fixtures. |
| `~/scripts/new-session` (outside the repo) | Prints `WORKTREE_DIR=<project dir>` as its last line under `--no-launch`. |

**Space TSV fields** (`wb-spaces` output, and the `s` array in zsh): `1 label · 2 group · 3 root · 4 beads(true|false|if-present) · 5 worktrees(1|0) · 6 session_cmd · 7 space_key · 8 claude_config · 9 protocol · 10 safe(1|0)`. Missing values are `-`.

**`wb-backlog list` TSV fields:** `1 id · 2 short id · 3 mark(○|◐) · 4 P<n> · 5 section(NOW|NEXT|-) · 6 title · 7 parent · 8 worktree`.

**`wb-backlog list` exit codes:** 0 ok · 20 bd not installed · 21 no bead store · 22 store unreadable · 23 bd unavailable (timeout, crash or junk) · 24 empty twice.

**Screen-2 line fields** (`wb-ui render-work`): `1 kind(new|sep|msg|open|claimed) · 2 id · 3 worktree · 4 header text · 5 row text`.

---

### Task 0: Prerequisites and decisions (Tommy, before any code)

**Files:** none.

- [ ] **Step 1: Install fzf**

Run: `brew install fzf && fzf --version`
Expected: `0.74.x` or newer.

- [ ] **Step 2: Check the fzf features the launcher relies on, in the installed version**

Run: `fzf --man | grep -nE -- '--listen|FZF_PORT|change-header|reload\(|start\b|--track|--with-nth|--nth'`
Expected: each of these appears:
- `--listen` (with port 0 meaning a random port, exported to child processes as `FZF_PORT`)
- the `start` event
- the `reload` action
- `--track`
- `--with-nth`
- `--nth`

If `--nth` applies to the original fields rather than the `--with-nth` ones in this version, note it. Task 5 then uses `--nth=5` instead of `--nth=2` (screen 2) and `--nth=2` instead of `--nth=1` (screen 1).

- [ ] **Step 3: Ask Tommy for the three decisions, and record them in the bead**

1. **Commit authority:** may the executor commit after each task? This repo's profile is conservative, so the default is no.
2. **Commit identity:** keep the global Gmail identity, or set `git config user.email <github-noreply>` in this repo first? If he chooses noreply, the 4 existing commits should be rewritten before any push. That is a separate decision; this plan pushes nothing.
3. **Leak check vs. tracked docs:** the spec and this plan name real spaces and accounts. Should they be scrubbed before publishing, excluded from `check-leaks.sh`, or kept out of the public repo? Task 7 builds the check either way.
4. **The Acme protocol's paste-this block** (`docs/PROGRAM_PROTOCOL.md`, lines 25–30): should it now say "the launcher sends this"? That edits a tracked file in the Acme repo, so the executor leaves it alone unless Tommy says yes.
5. **The live `new-session` check (Task 3 Step 4).** This step fetches, may run `gh auth switch` (which changes the global gh account), creates a worktree and runs `npm install` in the Acme repo. Run it during Task 3, or fold it into acceptance item 3?

Run: `bd update wb-1fy --append-notes="Task 0 decisions: commits=<yes/no>, identity=<…>, docs-leak=<…>, protocol-block=<…>, live-ns-check=<task3|acceptance>"`

**STOP: Tommy answers these. The executor does not guess them.**

---

### Task 1: Test harness and `wb-spaces`

**Files:**
- Create: `tests/lib.sh`, `tests/run.sh`, `tests/fake/bd`, `tests/fake/new-session`, `tests/fake/claude`
- Create: `bin/wb-spaces`
- Test: `tests/test_wb_spaces.sh`

**Interfaces:**
- Produces: `wb-spaces` (no args) prints space TSV lines (see the field list above) and exits 0.
  - Exit 3: no config; stderr has `workbench: no config at <path> …`.
  - Exit 4: invalid config; stderr has `workbench: invalid config <path>: <reason>`.
- Produces: `wb-spaces --terminals` prints `[launcher].terminals`, one per line.
- Produces: `wb-spaces --leak-terms` prints labels, groups and `claude_config` basenames, minus `[launcher].leak_allow`.
- Produces: fakes that later tasks rely on.
  - `tests/fake/bd` is driven by `FAKE_BD_DIR`, or, when that is unset, by `$PWD/.beads/fake.json`.
  - `tests/fake/new-session` is driven by `FAKE_NS_LOG`, `FAKE_NS_DIR` and `FAKE_NS_RC`.
  - `tests/fake/claude` prints `FAKE-CLAUDE <args>`.

- [ ] **Step 1: Write the test helpers and the runner**

`tests/lib.sh`:
```bash
# Tiny assert helpers for plain-bash tests. Source it; call `finish` last.
PASS=0; FAIL=0
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$REPO/tests/fake:$PATH"
export WB_BD_TIMEOUT=1
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
assert_eq()           { if [ "$2" == "$3" ]; then ok "$1"; else bad "$1" "expected: $3"$'\n'"got:      $2"; fi; }
assert_contains()     { if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "missing: $3"$'\n'"in: $2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1" "unexpected: $3"$'\n'"in: $2"; fi; }
finish() { echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }
newtmp() { mktemp -d "${TMPDIR:-/tmp}/wbtest.XXXXXX"; }
```

`tests/run.sh`:
```bash
#!/usr/bin/env bash
# Run every tests/test_*.sh; exit non-zero if any failed.
cd "$(dirname "$0")" || exit 1
status=0
for t in test_*.sh; do
  echo "== $t"
  bash "$t" || status=1
done
exit $status
```

- [ ] **Step 2: Write the fakes**

`tests/fake/bd`:
```bash
#!/usr/bin/env bash
# Fake bd for tests.
# With FAKE_BD_DIR set, behaviour comes from files in it:
#   calls             incremented on every invocation (retry tests count it)
#   stdout.N, stdout  what call N (or any call) prints
#   stderr            printed to stderr
#   rc                exit code (default 0)
#   sleep             seconds to sleep first, in a child process (timeout tests)
# Without FAKE_BD_DIR, it prints $PWD/.beads/fake.json (screen tests: one store per space).
set -u
if [ -z "${FAKE_BD_DIR:-}" ]; then
  [ -f .beads/fake.json ] && cat .beads/fake.json
  exit 0
fi
d="$FAKE_BD_DIR"
n=$(( $(cat "$d/calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$d/calls"
[ -f "$d/sleep" ] && sleep "$(cat "$d/sleep")"
[ -f "$d/stderr" ] && cat "$d/stderr" >&2
if [ -f "$d/stdout.$n" ]; then cat "$d/stdout.$n"; elif [ -f "$d/stdout" ]; then cat "$d/stdout"; fi
exit "$(cat "$d/rc" 2>/dev/null || echo 0)"
```

`tests/fake/new-session`:
```bash
#!/usr/bin/env bash
# Fake new-session: logs argv, prints progress like the real one, ends with WORKTREE_DIR=.
echo "$*" >> "${FAKE_NS_LOG:?}"
echo "→ creating worktree (fake)"
if [ -n "${FAKE_NS_RC:-}" ]; then echo "error: worktree path already exists: /x" >&2; exit "$FAKE_NS_RC"; fi
mkdir -p "${FAKE_NS_DIR:?}"
echo "WORKTREE_DIR=$FAKE_NS_DIR"
```

`tests/fake/claude`:
```bash
#!/usr/bin/env bash
# Safety net: if a test ever reaches a real launch, it prints instead of starting Claude.
echo "FAKE-CLAUDE $*"
```

Run: `chmod +x tests/run.sh tests/fake/*`

- [ ] **Step 3: Write the failing `wb-spaces` tests**

`tests/test_wb_spaces.sh`:
```bash
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
expected="Acme	-	$T/acme	true	1	new-session	acme	$T/home/cfg	docs/PROTOCOL.md	0
alpha	Side	$T/side/alpha	if-present	0	-	-	-	-	1
my proj	Side	$T/side/my proj	if-present	0	-	-	-	-	1"
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
assert_eq "worktrees without session_cmd is invalid" "$rc" "4"

out="$(WORKBENCH_CONFIG="$T/ok.toml" "$WS" --terminals)"
assert_eq "--terminals" "$out" "WezTerm"
out="$(WORKBENCH_CONFIG="$T/ok.toml" "$WS" --leak-terms 2>/dev/null)"
assert_contains "--leak-terms has labels" "$out" "Acme"
assert_contains "--leak-terms has config basename" "$out" "cfg"
assert_not_contains "--leak-terms drops leak_allow" "$out" "Side"
finish
```

- [ ] **Step 4: Run it to verify it fails**

Run: `bash tests/test_wb_spaces.sh`
Expected: FAIL lines, with `bin/wb-spaces: No such file or directory`.

- [ ] **Step 5: Implement `bin/wb-spaces`**

```python
#!/usr/bin/env python3
"""wb-spaces — this machine's spaces, from ~/.config/workbench/spaces.toml.

  wb-spaces                one TSV line per space (glob spaces: one per folder):
                           label, group, root, beads, worktrees, session_cmd,
                           space_key, claude_config, protocol, safe   ('-' = unset)
  wb-spaces --terminals    [launcher].terminals, one per line
  wb-spaces --leak-terms   private words check-leaks.sh greps for

Exit 3: no config file. Exit 4: the config is invalid. Both explain on stderr.
"""
import glob
import os
import sys

if sys.version_info < (3, 11):
    sys.exit("workbench: wb-spaces needs python3 >= 3.11 (for tomllib)")
import tomllib


def config_path():
    return os.environ.get("WORKBENCH_CONFIG") or os.path.expanduser("~/.config/workbench/spaces.toml")


def expand(p):
    return os.path.abspath(os.path.expanduser(p)) if p else ""


def field(v):
    v = str(v).replace("\t", " ").replace("\n", " ")
    return v if v else "-"


def spaces(cfg):
    entries = cfg.get("space")
    if not isinstance(entries, list) or not entries:
        raise ValueError("no [[space]] entries")
    for n, s in enumerate(entries, 1):
        name = s.get("name")
        if not name:
            raise ValueError(f"space #{n} has no name")
        if ("root" in s) == ("glob" in s):
            raise ValueError(f"space '{name}' needs exactly one of root or glob")
        worktrees = bool(s.get("worktrees", False))
        if worktrees and not (s.get("session_cmd") and s.get("space_key")):
            raise ValueError(f"space '{name}' has worktrees = true but no session_cmd and space_key")
        beads = s.get("beads", "if-present")
        beads = {True: "true", False: "false"}.get(beads, beads)
        if beads not in ("true", "false", "if-present"):
            raise ValueError(f"space '{name}': beads must be true, false or \"if-present\"")
        common = {
            "beads": beads,
            "worktrees": "1" if worktrees else "0",
            "session_cmd": s.get("session_cmd", ""),
            "space_key": s.get("space_key", ""),
            "claude_config": expand(s.get("claude_config", "")),
            "protocol": s.get("protocol", ""),
            "safe": "1" if s.get("safe") else "0",
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
                    yield {"label": os.path.basename(d), "group": name, "root": d, **common}


ORDER = ("label", "group", "root", "beads", "worktrees", "session_cmd",
         "space_key", "claude_config", "protocol", "safe")


def main(argv):
    path = config_path()
    if not os.path.exists(path):
        print(f"workbench: no config at {path} — copy spaces.example.toml there to start", file=sys.stderr)
        return 3
    try:
        with open(path, "rb") as f:
            cfg = tomllib.load(f)
        launcher = cfg.get("launcher", {})
        if argv[1:] == ["--terminals"]:
            print("\n".join(launcher.get("terminals", [])))
            return 0
        rows = list(spaces(cfg))
    except (tomllib.TOMLDecodeError, ValueError, TypeError, AttributeError) as e:
        print(f"workbench: invalid config {path}: {e}", file=sys.stderr)
        return 4
    if argv[1:] == ["--leak-terms"]:
        allow = set(launcher.get("leak_allow", []))
        terms = {r["label"] for r in rows} | {r["group"] for r in rows if r["group"]}
        terms |= {os.path.basename(r["claude_config"]) for r in rows if r["claude_config"]}
        print("\n".join(sorted(terms - allow)))
        return 0
    for r in rows:
        print("\t".join(field(r[k]) for k in ORDER))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

Run: `chmod +x bin/wb-spaces`

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/test_wb_spaces.sh`
Expected: all `ok`, then `N passed, 0 failed`.

- [ ] **Step 7: Commit (only if authorised in Task 0)**

```bash
git add tests/lib.sh tests/run.sh tests/fake bin/wb-spaces tests/test_wb_spaces.sh
git commit -m "feat: wb-spaces reads the private space config" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `wb-backlog`

**Files:**
- Create: `bin/wb-backlog`
- Create: `tests/fixtures/waves.json`, `tests/fixtures/plain.json`
- Test: `tests/test_wb_backlog.sh`

**Interfaces:**
- Consumes: `tests/fake/bd` and `tests/lib.sh` (Task 1).
- Produces:
  - `wb-backlog list ROOT [--snapshot FILE]`: list TSV and exit codes as in the File Map. The snapshot is written whenever bd returned data: a JSON object of every bead, live or not, keyed by id.
  - `wb-backlog summary ROOT`: one line, always exit 0.
  - `wb-backlog preview FILE ID`: the preview text.

- [ ] **Step 1: Write the fixtures**

`tests/fixtures/waves.json`:
```json
[
  {"id":"acme-e1","title":"Epic: tidy the shop","status":"open","priority":2,"issue_type":"epic","labels":[],"parent":null,"description":"The parent epic."},
  {"id":"acme-a1","title":"Low wave-1","status":"open","priority":2,"labels":["wave:1"],"parent":"acme-e1","description":"First line\nSecond line"},
  {"id":"acme-a2","title":"High wave-1","status":"open","priority":1,"labels":["wave:1","ws:shop"],"parent":"acme-e1","description":"Do the thing."},
  {"id":"acme-b1","title":"Wave-2 urgent","status":"open","priority":0,"labels":["wave:2"],"parent":null,"description":""},
  {"id":"acme-c1","title":"Unwaved P1","status":"blocked","priority":1,"labels":[],"parent":null},
  {"id":"acme-c2","title":"Claimed elsewhere","status":"in_progress","priority":3,"labels":["wave:0"],"parent":null,"notes":"Branch: feat/x (worktree at /tmp/wb-fixture-wt/acme-x)"},
  {"id":"acme-d1","title":"Deferred one","status":"deferred","priority":0,"labels":["wave:1"]},
  {"id":"acme-z1","title":"Closed one","status":"closed","priority":0,"labels":["wave:1"]}
]
```

`tests/fixtures/plain.json`:
```json
[
  {"id":"bee-1","title":"Second by priority","status":"open","priority":2,"labels":null},
  {"id":"bee-2","title":"First by priority","status":"open","priority":1}
]
```

- [ ] **Step 2: Write the failing tests**

`tests/test_wb_backlog.sh`:
```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
WB="$REPO/bin/wb-backlog"; FX="$REPO/tests/fixtures"
mkdir -p "$T/store/.beads" "$T/nostore"
export FAKE_BD_DIR="$T/bd"
reset_bd() { rm -rf "$FAKE_BD_DIR"; mkdir -p "$FAKE_BD_DIR"; }

reset_bd; cp "$FX/waves.json" "$FAKE_BD_DIR/stdout"
out="$("$WB" list "$T/store" --snapshot "$T/snap.json")"; rc=$?
assert_eq "list ok exits 0" "$rc" "0"
assert_eq "order: NOW by priority, NEXT, then the rest by priority; deferred+closed hidden" \
  "$(printf '%s\n' "$out" | cut -f1 | tr '\n' ' ')" "acme-a2 acme-a1 acme-b1 acme-c1 acme-e1 acme-c2 "
assert_eq "row fields" "$(printf '%s\n' "$out" | head -1)" \
  "acme-a2	a2	○	P1	NOW	High wave-1	acme-e1	-"
assert_eq "in-progress is ◐ with its worktree from notes" "$(printf '%s\n' "$out" | tail -1)" \
  "acme-c2	c2	◐	P3	-	Claimed elsewhere	-	/tmp/wb-fixture-wt/acme-x"
assert_eq "summary with waves" "$("$WB" summary "$T/store")" "NOW 2 · NEXT 1 · claimed 1"

prev="$("$WB" preview "$T/snap.json" acme-a1)"
assert_contains "preview: title" "$prev" "Low wave-1"
assert_contains "preview: parent with title" "$prev" "parent: acme-e1  Epic: tidy the shop"
assert_contains "preview: labels" "$prev" "labels: wave:1"
assert_contains "preview: description keeps newlines" "$prev" $'First line\nSecond line'
assert_contains "preview: new-idea row" "$("$WB" preview "$T/snap.json" -)" "new idea"

reset_bd; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout"
assert_eq "no waves: priority alone" "$("$WB" list "$T/store" | cut -f1,5 | tr '\n' ' ')" "bee-2	- bee-1	- "
assert_eq "summary without waves" "$("$WB" summary "$T/store")" "open 2 · claimed 0"

reset_bd; { echo "Warning: $T/store/.beads has permissions 0755 [recommended: 0700]"; cat "$FX/plain.json"; } > "$FAKE_BD_DIR/stdout"
assert_eq "warning line before JSON is skipped" "$("$WB" summary "$T/store")" "open 2 · claimed 0"

reset_bd; echo '[]' > "$FAKE_BD_DIR/stdout"
"$WB" list "$T/store" >/dev/null; rc=$?
assert_eq "empty twice exits 24" "$rc" "24"
assert_eq "empty is retried once" "$(cat "$FAKE_BD_DIR/calls")" "2"
assert_eq "empty summary says re-check" "$("$WB" summary "$T/store")" "0 open (ctrl-r to re-check)"

reset_bd; echo '[]' > "$FAKE_BD_DIR/stdout.1"; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout.2"
assert_eq "empty then data: the retry wins" "$("$WB" summary "$T/store")" "open 2 · claimed 0"

reset_bd; echo 1 > "$FAKE_BD_DIR/rc"; echo "Error: no beads database found" > "$FAKE_BD_DIR/stderr"
"$WB" list "$T/store" >/dev/null 2>&1; rc=$?
assert_eq "unreadable store exits 22" "$rc" "22"
assert_eq "unreadable summary" "$("$WB" summary "$T/store")" "(no readable beads)"

reset_bd; echo 1 > "$FAKE_BD_DIR/rc"; echo "Error: dolt exploded" > "$FAKE_BD_DIR/stderr"
"$WB" list "$T/store" >/dev/null 2>&1; rc=$?
assert_eq "other failure exits 23" "$rc" "23"

reset_bd; echo 'not json at all' > "$FAKE_BD_DIR/stdout"
assert_eq "junk output is unavailable" "$("$WB" summary "$T/store")" "(bd unavailable)"

reset_bd; echo 5 > "$FAKE_BD_DIR/sleep"; cp "$FX/plain.json" "$FAKE_BD_DIR/stdout"
start=$SECONDS; out="$("$WB" summary "$T/store")"; took=$((SECONDS - start))
assert_eq "hang is unavailable" "$out" "(bd unavailable)"
if [ "$took" -lt 3 ]; then ok "hang is cut off at the timeout (${took}s)"; else bad "hang took ${took}s"; fi

reset_bd
"$WB" list "$T/nostore" >/dev/null; rc=$?
assert_eq "no .beads exits 21" "$rc" "21"
if [ ! -f "$FAKE_BD_DIR/calls" ]; then ok "no .beads: bd not called"; else bad "bd was called without .beads"; fi
assert_eq "no-store summary" "$("$WB" summary "$T/nostore")" "(no bead store)"

WB_BD=/nonexistent/bd "$WB" list "$T/store" >/dev/null; rc=$?
assert_eq "bd missing exits 20" "$rc" "20"
assert_eq "bd missing summary" "$(WB_BD=/nonexistent/bd "$WB" summary "$T/store")" "(bd not installed)"

reset_bd
cat > "$FAKE_BD_DIR/stdout" <<EOF
[{"id":"bee-9","title":"tab\there \$(touch $T/pwned) \"q\"\nnext","status":"open","priority":1,"description":"\$(touch $T/pwned)"}]
EOF
out="$("$WB" list "$T/store" --snapshot "$T/snap2.json")"
assert_eq "hostile title is cleaned into one row of 8 fields" "$(printf '%s\n' "$out" | awk -F'\t' '{print NR":"NF}')" "1:8"
prev="$("$WB" preview "$T/snap2.json" bee-9)"
assert_contains "hostile description shown literally" "$prev" "\$(touch $T/pwned)"
if [ ! -e "$T/pwned" ]; then ok "hostile title is cleaned and not executed"; else bad "something executed the title"; fi
finish
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash tests/test_wb_backlog.sh`
Expected: FAIL lines (`bin/wb-backlog: No such file or directory`).

- [ ] **Step 4: Implement `bin/wb-backlog`**

```python
#!/usr/bin/env python3
"""wb-backlog — one space's live beads, read through bd.

  wb-backlog list ROOT [--snapshot FILE]
      TSV, best first: id, short id, mark (○ open / ◐ in progress), P<n>,
      section (NOW / NEXT / -), title, parent, worktree from the claim notes.
      Exits non-zero when there is nothing to list; the code says why (STATES).
  wb-backlog summary ROOT      one line of counts for screen 1; always exits 0
  wb-backlog preview FILE ID   the preview pane for one bead, from a snapshot

Order: wave:1, then wave:2, then everything else; priority within each.
Closed and deferred beads are hidden.
"""
import json
import os
import re
import shutil
import signal
import subprocess
import sys

TIMEOUT = float(os.environ.get("WB_BD_TIMEOUT", "3"))
BD = os.environ.get("WB_BD", "bd")
HIDDEN = {"closed", "deferred"}
WORKTREE_RE = re.compile(r"worktree at (/[^)\s]+)")
# state -> (list exit code, summary text)
STATES = {
    "no-bd": (20, "(bd not installed)"),
    "no-store": (21, "(no bead store)"),
    "unreadable": (22, "(no readable beads)"),
    "unavailable": (23, "(bd unavailable)"),
    "empty": (24, "0 open (ctrl-r to re-check)"),
}


class BdError(Exception):
    def __init__(self, state):
        super().__init__(state)
        self.state = state


def run_bd(root):
    try:
        p = subprocess.Popen([BD, "list", "-n", "0", "--json"], cwd=root, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             start_new_session=True)
    except OSError:
        raise BdError("unavailable")
    try:
        out, err = p.communicate(timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        # Kill the whole group: a child still holding the pipe would make
        # communicate() wait for it.
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass  # it finished just as the timeout hit
        p.communicate()
        raise BdError("unavailable")
    if p.returncode != 0:
        raise BdError("unreadable" if "no beads database found" in out + err else "unavailable")
    start = re.search(r"^\[", out, re.M)  # bd can print 'Warning: …' lines first
    if not start:
        raise BdError("unavailable")
    try:
        data = json.loads(out[start.start():])
    except json.JSONDecodeError:
        raise BdError("unavailable")
    if not isinstance(data, list) or not all(isinstance(b, dict) for b in data):
        raise BdError("unavailable")
    return data


def read(root):
    """(state, every bead bd returned). state is 'ok' or a key of STATES."""
    if shutil.which(BD) is None:
        return "no-bd", []
    # No .beads here: don't let bd walk up to some parent's store.
    if not os.path.isdir(os.path.join(root, ".beads")):
        return "no-store", []
    try:
        data = run_bd(root)
        if not data:  # a locked store has answered [] with exit 0; look once more
            data = run_bd(root)
    except BdError as e:
        return e.state, []
    return ("ok" if data else "empty"), data


def live(data):
    return [b for b in data if b.get("status") not in HIDDEN]


def section(b):
    waves = [int(l[5:]) for l in (b.get("labels") or []) if re.fullmatch(r"wave:\d+", str(l))]
    return {1: "NOW", 2: "NEXT"}.get(min(waves) if waves else None, "-")


def priority(b):
    p = b.get("priority")
    return p if isinstance(p, int) else 9


def ordered(beads):
    rank = {"NOW": 0, "NEXT": 1}
    return sorted(beads, key=lambda b: (rank.get(section(b), 2), priority(b), str(b.get("id", ""))))


def clean(v):
    v = re.sub(r"[\t\r\n]+", " ", str(v or "")).strip()
    return v or "-"


def worktree(b):
    m = WORKTREE_RE.search(b.get("notes") or "")
    return m.group(1) if m else "-"


def cmd_list(root, snapshot=None):
    state, data = read(root)
    if snapshot and data:  # write-then-rename: the preview may be reading it during a ctrl-r reload
        with open(snapshot + ".part", "w") as f:
            json.dump({b.get("id"): b for b in data}, f, ensure_ascii=False)
        os.replace(snapshot + ".part", snapshot)
    if state != "ok":
        return STATES[state][0]
    for b in ordered(live(data)):
        bid = str(b.get("id", ""))
        mark = "◐" if b.get("status") == "in_progress" else "○"
        prio = f"P{b['priority']}" if isinstance(b.get("priority"), int) else "P-"
        print("\t".join(clean(x) for x in (bid, bid.rsplit("-", 1)[-1], mark, prio,
                                            section(b), b.get("title"), b.get("parent"),
                                            worktree(b))))
    return 0


def cmd_summary(root):
    state, data = read(root)
    if state != "ok":
        print(STATES[state][1])
        return 0
    beads = live(data)
    claimed = sum(b.get("status") == "in_progress" for b in beads)
    now = sum(section(b) == "NOW" for b in beads)
    nxt = sum(section(b) == "NEXT" for b in beads)
    if now or nxt:
        print(f"NOW {now} · NEXT {nxt} · claimed {claimed}")
    else:
        print(f"open {len(beads)} · claimed {claimed}")
    return 0


def cmd_preview(snapshot, bead_id):
    if bead_id in ("", "-"):
        print("✦ Start Claude here and shape a new idea into a bead.")
        return 0
    try:
        with open(snapshot) as f:
            beads = json.load(f)
    except (OSError, ValueError):
        print("(no details yet — ctrl-r to re-read)")
        return 0
    b = beads.get(bead_id)
    if not b:
        print(f"{bead_id}: not in the last read")
        return 0
    parent = b.get("parent")
    ptitle = (beads.get(parent) or {}).get("title") if parent else None
    print(f"{bead_id}  P{b.get('priority', '?')}  {b.get('status', '?')}")
    print(b.get("title") or "")
    print()
    print("parent: " + (f"{parent}  {ptitle}" if ptitle else (parent or "—")))
    print("labels: " + (", ".join(map(str, b.get("labels") or [])) or "—"))
    print()
    print(b.get("description") or "(no description)")
    return 0


def main(argv):
    args = argv[1:]
    if len(args) >= 2 and args[0] == "list":
        snap = args[3] if len(args) == 4 and args[2] == "--snapshot" else None
        return cmd_list(args[1], snap)
    if len(args) == 2 and args[0] == "summary":
        return cmd_summary(args[1])
    if len(args) == 3 and args[0] == "preview":
        return cmd_preview(args[1], args[2])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

Run: `chmod +x bin/wb-backlog`

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/test_wb_backlog.sh`
Expected: all `ok`, then `N passed, 0 failed`. The hang test takes about 1 second.

- [ ] **Step 6: Smoke-test against real stores (read-only)**

Run: `bin/wb-backlog summary ~/dev/acme/acme-app; for d in ~/dev/personal/*/; do printf '%s: ' "$(basename "$d")"; bin/wb-backlog summary "$d"; done`
Expected:
- Acme shows `NOW 9 · NEXT 15 · claimed 7` (give or take today's changes).
- notes, atlas and done show `(no readable beads)`.
- lens shows `0 open (ctrl-r to re-check)`.
- The others show `(no bead store)`.

- [ ] **Step 7: Commit (only if authorised)**

```bash
git add bin/wb-backlog tests/fixtures tests/test_wb_backlog.sh
git commit -m "feat: wb-backlog reads a space's beads with timeout, retry and ordering" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `new-session` prints `WORKTREE_DIR=` under `--no-launch`

**Files:**
- Modify: `~/scripts/new-session` (outside the repo, and not in git), in the `if [[ $LAUNCH -eq 0 ]]` block just after the "Session ready" banner.

**Interfaces:**
- Produces: with `--no-launch`, the last stdout line is `WORKTREE_DIR=$WORKTREE/$PROJECT_DIR`, the same path as the banner's `project:` line. All other output is unchanged.

- [ ] **Step 1: Back it up (it has no version control)**

Run: `cp -p ~/scripts/new-session ~/scripts/new-session.bak-2026-10-16`

- [ ] **Step 2: Make the edit**

Replace:
```bash
if [[ $LAUNCH -eq 0 ]]; then
  exit 0
fi
```
with:
```bash
if [[ $LAUNCH -eq 0 ]]; then
  # Parseable last line for callers that start claude themselves (workbench launch).
  echo "WORKTREE_DIR=$WORKTREE/$PROJECT_DIR"
  exit 0
fi
```

- [ ] **Step 3: Verify syntax and the diff**

Run: `bash -n ~/scripts/new-session && diff ~/scripts/new-session.bak-2026-10-16 ~/scripts/new-session`
Expected: no syntax error, and a diff of exactly the 2 added lines.

- [ ] **Step 4: Verify for real with an exploratory worktree, then clean it up**

**STOP: run this only if Tommy chose "task3" in Task 0 decision 5; otherwise skip it, because acceptance item 3 covers it.** This is the same operation as acceptance item 3. It fetches origin and runs `npm install` (about 20 s).

Run: `new-session acme --no-launch | tee /tmp/ns.log; tail -1 /tmp/ns.log`
Expected: the last line is `WORKTREE_DIR=~/.worktrees/acme-<timestamp>/acme-app`, and that directory exists.

Clean up (substitute the printed timestamp):
```bash
git -C ~/dev/acme/acme-app worktree remove --force ~/.worktrees/acme-<timestamp>
git -C ~/dev/acme/acme-app branch -D explore/<timestamp>
```

- [ ] **Step 5: No commit:** the file isn't in a repo. Record the change in the bead:

Run: `bd update wb-1fy --append-notes="new-session: --no-launch now prints WORKTREE_DIR=<project dir> last; backup at ~/scripts/new-session.bak-2026-10-16"`

---

### Task 4: Prompts and handoff

**Files:**
- Create: `prompts/work-on-bead.txt`, `prompts/something-new.txt`
- Create: `shell/workbench.zsh` (handoff section only; Tasks 5 and 6 add to it)
- Test: `tests/test_handoff.sh`

**Interfaces:**
- Consumes: the space TSV fields (Task 1), the fake `new-session` (Task 1), and the `WORKTREE_DIR=` contract (Task 3).
- Produces (zsh functions; they read the caller's `local -a s` (space fields) and `local tmp` (scratch dir) through zsh's dynamic scoping):
  - `_wb_prompt <work-on-bead|something-new> <id|->` prints the rendered prompt.
  - `_wb_claude <prompt|continue> [text]` builds and runs `env … claude …`, or with `WORKBENCH_DRY_RUN=1` prints `DRY-RUN: cd <pwd> && <cmd>`.
  - `_wb_session_cd <args…>` runs `$s[6] <args> --no-launch`, showing its output live. It then `cd`s to `WORKTREE_DIR`. On failure it `cd`s to `$HOME`, prints `workbench: … did not finish` and returns 1.
  - `_wb_start_bead <id>`, `_wb_start_new`, and `_wb_start_claimed <id> <worktree|->`. The last returns 1 to mean "go back to screen 2".

- [ ] **Step 1: Write the prompts**

`prompts/work-on-bead.txt`:
```
Work on bead {id} in {space}.

{protocol}
1. Run `bd show {id}` and read all of it, including the notes.
2. Before writing any code, re-verify the bead's load-bearing figure or fact against the live system, and tell me if it moved. If it moved, re-scope before building.
3. Then build it. When it ships, close the bead, recording what actually shipped and what did not.
```

This carries over every instruction in Acme's paste-this block (`PROGRAM_PROTOCOL.md` lines 27–30) except the Acme-specific ones: "against production" and "PR". Those stay in the protocol doc, which `{protocol}` tells the session to read first.

`prompts/something-new.txt`:
```
I want to start something new in {space}. Help me shape the idea before writing any code: ask what it's for and what done looks like.

{protocol}
Once it has a shape, file it as a bead with `bd create`, under a parent epic if this space uses epics, and only then start building. If this folder has no .beads directory, run `bd init` first.
```

- [ ] **Step 2: Write the failing tests**

`tests/test_handoff.sh`:
```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
export WORKBENCH_DRY_RUN=1 FAKE_NS_LOG="$T/ns.log" FAKE_NS_DIR="$T/wt/proj"
NS="$REPO/tests/fake/new-session"
mkdir -p "$T/proj dir" "$T/repo/sub" "$T/scratch" "$T/wt-x/sub"
git -C "$T/repo" init -q

# z <space fields as one TSV string> <zsh code>: run code with s and tmp set
z() { zsh -f -c "source '$REPO/shell/workbench.zsh'; tmp='$T/scratch'; local -a s; s=(\"\${(@ps:\t:)1}\"); $2" _ "$1"; }
PLAIN="Beta	Side	$T/proj dir	if-present	0	-	-	-	-	0"
WT="Acme	-	$T/repo/sub	true	1	$NS	acme	$T/cfg	docs/PROTOCOL.md	0"

out="$(z "$PLAIN" '_wb_start_bead bee-1; print "PWD=$PWD"' 2>&1)"
assert_contains "plain bead: unsets config, prompts off" "$out" "env -u CLAUDE_CONFIG_DIR claude --dangerously-skip-permissions"
assert_contains "plain bead: work-on-bead prompt" "$out" "Work on bead bee-1 in Beta."
assert_contains "plain bead: shell lands in the project (path with a space)" "$out" "PWD=$T/proj dir"
assert_not_contains "no protocol: no protocol line" "$out" "Before anything else"

out="$(CLAUDE_CONFIG_DIR=/elsewhere z "$PLAIN" '_wb_start_new' 2>&1)"
assert_contains "exported CLAUDE_CONFIG_DIR is removed for a plain space" "$out" "env -u CLAUDE_CONFIG_DIR claude"
assert_contains "something-new prompt" "$out" "start something new in Beta"

out="$(z "${PLAIN%0}1" '_wb_start_new' 2>&1)"
assert_not_contains "safe space keeps prompts on" "$out" "--dangerously-skip-permissions"

out="$(z "$WT" '_wb_start_bead acme-a2; print "PWD=$PWD"' 2>&1)"
assert_eq "worktree bead: new-session got the bead + --no-launch" "$(tail -1 "$T/ns.log")" "acme-a2 --no-launch"
assert_contains "worktree bead: new-session output shown live" "$out" "creating worktree (fake)"
assert_contains "worktree bead: config dir set for the command" "$out" "DRY-RUN: cd $T/wt/proj && env CLAUDE_CONFIG_DIR=$T/cfg claude --dangerously-skip-permissions"
assert_contains "worktree bead: protocol line" "$out" "Before anything else, read docs/PROTOCOL.md"
assert_contains "worktree bead: shell lands in the worktree" "$out" "PWD=$T/wt/proj"

z "$WT" '_wb_start_new' >/dev/null 2>&1
assert_eq "worktree new: new-session got the space key" "$(tail -1 "$T/ns.log")" "acme --no-launch"

out="$(cd "$T/proj dir" && FAKE_NS_RC=1 z "$WT" '_wb_start_bead acme-a2; print "PWD=$PWD"' 2>&1)"
assert_contains "new-session failure is reported" "$out" "did not finish"
assert_contains "new-session failure lands in HOME" "$out" "PWD=$HOME"
assert_not_contains "new-session failure starts nothing" "$out" "DRY-RUN"

out="$(printf 'y\n' | z "$WT" "_wb_start_claimed acme-c2 '$T/wt-x'; print \"rc=\$? PWD=\$PWD\"" 2>&1)"
assert_contains "◐ with worktree: resumes with --continue" "$out" "claude --dangerously-skip-permissions --continue"
assert_contains "◐ with worktree: cd into the same subfolder" "$out" "PWD=$T/wt-x/sub"

out="$(printf 'n\n' | z "$WT" "_wb_start_claimed acme-c2 '$T/wt-x'; print \"rc=\$?\"" 2>&1)"
assert_contains "◐ resume declined goes back" "$out" "rc=1"

out="$(z "$WT" "_wb_start_claimed acme-c2 '$T/gone'; print \"rc=\$?\"" 2>&1)"
assert_contains "◐ without worktree: stale claim shown" "$out" "stale claim"
assert_contains "◐ without worktree: back to screen 2" "$out" "rc=1"
assert_not_contains "◐ without worktree: no launch" "$out" "DRY-RUN"

out="$(printf 'n\n' | z "$PLAIN" "_wb_start_claimed bee-1 -; print \"rc=\$?\"" 2>&1)"
assert_contains "◐ in a plain space: declining goes back" "$out" "rc=1"
out="$(printf 'y\n' | z "$PLAIN" "_wb_start_claimed bee-1 -" 2>&1)"
assert_contains "◐ in a plain space: accepting starts it" "$out" "Work on bead bee-1"
finish
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash tests/test_handoff.sh`
Expected: FAIL lines (`shell/workbench.zsh` does not exist).

- [ ] **Step 4: Create `shell/workbench.zsh` with the handoff section**

```zsh
# workbench.zsh — the start screen for every Terminal window.
# Source it at the END of ~/.zshrc. Spec: docs/specs/2026-10-16-launcher-design.md
#
# Helpers below read two locals of the caller (_wb_main) through zsh's dynamic
# scoping: `s` (the chosen space's 10 fields, as printed by wb-spaces) and
# `tmp` (this launch's scratch dir).

typeset -g WORKBENCH_HOME=${${(%):-%x}:A:h:h}

# ---- handoff ----

# $1 prompt file name, $2 bead id (or -). Prints the opening prompt.
_wb_prompt() {
  local text proto=""
  text=$(<$WORKBENCH_HOME/prompts/$1.txt) || return 1
  [[ $s[9] != - ]] && proto="Before anything else, read $s[9]: it is how this space works."
  text=${text//'{id}'/$2}
  text=${text//'{space}'/$s[1]}
  text=${text//'{protocol}'/$proto}
  print -r -- $text
}

# $1 prompt|continue, $2 prompt text. Starts Claude in $PWD on the space's
# account. CLAUDE_CONFIG_DIR is set for this one command, or removed, never
# exported. `env claude` also skips the user's claude() shell function.
_wb_claude() {
  local -a cmd
  if [[ $s[8] != - ]]; then cmd=(env CLAUDE_CONFIG_DIR=$s[8]); else cmd=(env -u CLAUDE_CONFIG_DIR); fi
  cmd+=(claude)
  [[ $s[10] == 1 ]] || cmd+=(--dangerously-skip-permissions)
  if [[ $1 == continue ]]; then cmd+=(--continue); else cmd+=($2); fi
  if [[ -n ${WORKBENCH_DRY_RUN-} ]]; then
    print -r -- "DRY-RUN: cd $PWD && ${(j: :)${(@q-)cmd}}"
    return 0
  fi
  "${cmd[@]}"
}

# Runs the space's session command with --no-launch, showing its output as it
# goes, then cds into the WORKTREE_DIR it prints last. The launcher starts
# Claude itself so this shell is in the worktree when Claude exits.
_wb_session_cd() {
  local log=$tmp/session.log dir rc
  "$s[6]" "$@" --no-launch 2>&1 | tee $log
  rc=${pipestatus[1]}
  dir=$(sed -n 's/^WORKTREE_DIR=//p' $log | tail -n 1)
  if (( rc != 0 )) || [[ -z $dir || ! -d $dir ]]; then
    print -u2 "workbench: $s[6] did not finish (exit $rc); you're at a shell in \$HOME."
    cd ~
    return 1
  fi
  cd -- $dir
}

_wb_start_bead() {
  if [[ $s[5] == 1 ]]; then _wb_session_cd $1 || return 0
  else cd -- $s[3] || return 0; fi
  _wb_claude prompt "$(_wb_prompt work-on-bead $1)"
}

_wb_start_new() {
  if [[ $s[5] == 1 ]]; then _wb_session_cd $s[7] || return 0
  else cd -- $s[3] || return 0; fi
  _wb_claude prompt "$(_wb_prompt something-new -)"
}

# ◐ beads are probably another session's. $1 id, $2 worktree from the claim
# notes (or -). Returns 1 to go back to screen 2.
_wb_start_claimed() {
  local id=$1 wt=$2 ans dir
  if [[ $s[5] != 1 ]]; then
    read -r "ans?$id is already claimed (◐). Start a session on it anyway? [y/N] " || return 1
    [[ $ans == [yY]* ]] || return 1
    _wb_start_bead $id
    return 0
  fi
  if [[ $wt != - && -d $wt ]]; then
    dir=$wt/$(git -C $s[3] rev-parse --show-prefix 2>/dev/null)
    [[ -d $dir ]] || dir=$wt
    read -r "ans?$id is claimed; its worktree is ${dir%/}. Resume there? [Y/n] " || return 1
    [[ $ans == [nN]* ]] && return 1
    cd -- $dir || return 1
    _wb_claude continue
    return 0
  fi
  [[ $wt == - ]] && wt="(no worktree recorded)"
  print -u2 "workbench: $id is a stale claim: it is in progress, but its worktree $wt is gone."
  print -u2 "           Release it with: bd update $id --status open"
  return 1
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/test_handoff.sh`
Expected: all `ok`. If the ◐-resume `PWD` assertion fails only because of a trailing slash, the `cd` is still correct: `cd` normalises the path and `$PWD` has no trailing slash. Fix the assertion only if `$PWD` really differs.

- [ ] **Step 6: Commit (only if authorised)**

```bash
git add prompts shell/workbench.zsh tests/test_handoff.sh
git commit -m "feat: launcher handoff — prompts, account scoping, new-session cd, resume" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Screens and `launch`

**Files:**
- Create: `bin/wb-ui`
- Modify: `shell/workbench.zsh` (add the screens section, `_wb_main` and `launch`)
- Test: `tests/test_launch.sh`

**Interfaces:**
- Consumes:
  - `wb-spaces` (Task 1)
  - `wb-backlog list|summary|preview` and its exit codes (Task 2)
  - `_wb_start_bead`, `_wb_start_new` and `_wb_start_claimed` (Task 4)
- Produces:
  - `launch` (zsh function, always returns 0).
  - `wb-ui render-spaces TMP`, `wb-ui fill-counts TMP` and `wb-ui render-work TMP INDEX`.
  - Test seams:
    - `WB_NO_FZF=1` forces the numbered menu.
    - `WB_TEST_PICK_SPACE` / `WB_TEST_PICK_WORK` pick the first line containing that text.
    - `XDG_STATE_HOME` locates the one-time fzf hint marker.

- [ ] **Step 1: Write the failing tests**

`tests/test_launch.sh`:
```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
unset FAKE_BD_DIR   # fake bd reads each store's .beads/fake.json
export WORKBENCH_DRY_RUN=1 FAKE_NS_LOG="$T/ns.log" FAKE_NS_DIR="$T/wt/proj" XDG_STATE_HOME="$T/state"
export WORKBENCH_CONFIG="$T/spaces.toml"
mkdir -p "$T/acme/.beads" "$T/side/beta/.beads" "$T/side/gamma" "$T/start"
cp "$REPO/tests/fixtures/waves.json" "$T/acme/.beads/fake.json"
cp "$REPO/tests/fixtures/plain.json" "$T/side/beta/.beads/fake.json"
cat > "$WORKBENCH_CONFIG" <<EOF
[[space]]
name = "Acme"
root = "$T/acme"
beads = true
worktrees = true
session_cmd = "$REPO/tests/fake/new-session"
space_key = "acme"
claude_config = "$T/cfg"

[[space]]
name = "Side"
glob = "$T/side/*"
EOF
L() { (cd "$T/start" && zsh -f -c "source '$REPO/shell/workbench.zsh'; launch; print \"AFTER rc=\$? PWD=\$PWD\"" 2>&1); }

# wb-ui render-work: sections and kinds
printf 'Acme\t-\t%s\ttrue\t1\tx\tacme\t-\t-\t0\n' "$T/acme" > "$T/start/spaces.tsv"
out="$("$REPO/bin/wb-ui" render-work "$T/start" 1)"
assert_eq "render-work kinds and order" "$(printf '%s\n' "$out" | cut -f1,2 | tr '\n' ' ')" \
  "new	- sep	- open	acme-a2 open	acme-a1 sep	- open	acme-b1 sep	- open	acme-c1 open	acme-e1 claimed	acme-c2 "
assert_contains "render-work NOW header" "$out" "── NOW ──"
assert_contains "render-work everything-else header" "$out" "── everything else ──"
assert_contains "render-work claimed row keeps its worktree" "$out" "claimed	acme-c2	/tmp/wb-fixture-wt/acme-x"

# fallback menu: Acme, then the first bead (item 2; item 1 is ✦ something new)
out="$(printf '1\n2\n' | WB_NO_FZF=1 L)"
assert_contains "menu screen 1 shows counts" "$out" "NOW 2 · NEXT 1 · claimed 1"
assert_contains "menu: fzf hint shown" "$out" "brew install fzf"
assert_eq "menu: bead goes through new-session" "$(tail -1 "$T/ns.log")" "acme-a2 --no-launch"
assert_contains "menu: launches in the worktree" "$out" "DRY-RUN: cd $T/wt/proj && env CLAUDE_CONFIG_DIR=$T/cfg claude"
assert_contains "menu: shell ends in the worktree" "$out" "AFTER rc=0 PWD=$T/wt/proj"
out="$(printf '1\n1\n' | WB_NO_FZF=1 L)"
assert_not_contains "fzf hint only once" "$out" "brew install fzf"
assert_eq "menu: something new uses the space key" "$(tail -1 "$T/ns.log")" "acme --no-launch"
out="$(printf '1\nr\n1\n' | WB_NO_FZF=1 L)"
assert_contains "menu: r re-reads then still picks" "$out" "DRY-RUN"

# test-pick path (stands in for fzf)
out="$(WB_TEST_PICK_SPACE='Side › beta' WB_TEST_PICK_WORK='First by priority' L)"
assert_contains "pick: plain space bead" "$out" "Work on bead bee-2 in beta."
assert_contains "pick: plain space has no config dir" "$out" "env -u CLAUDE_CONFIG_DIR claude"
assert_contains "pick: lands in the project" "$out" "AFTER rc=0 PWD=$T/side/beta"
out="$(WB_TEST_PICK_SPACE='Side › gamma' WB_TEST_PICK_WORK='something new' L)"
assert_contains "pick: no-store space still offers something new" "$out" "start something new in gamma"

# leaving
out="$(printf 'q\n' | WB_NO_FZF=1 L)"
assert_contains "q on screen 1 leaves a working shell" "$out" "AFTER rc=0 PWD=$T/start"
assert_not_contains "q starts nothing" "$out" "DRY-RUN"
out="$(WB_NO_FZF=1 L < /dev/null)"
assert_contains "EOF leaves a working shell" "$out" "AFTER rc=0 PWD=$T/start"
out="$(WB_TEST_PICK_SPACE='no such space' L)"
assert_contains "esc (no pick) leaves a working shell" "$out" "AFTER rc=0 PWD=$T/start"

out="$(WORKBENCH_CONFIG="$T/missing.toml" L)"
assert_contains "missing config: one line naming the file" "$out" "no config at $T/missing.toml"
assert_contains "missing config: still a shell" "$out" "AFTER rc=0"

# A division by zero raises a zsh error that the always block catches. (${x:?} would
# not do here: it exits a non-interactive shell outright.)
out="$( (cd "$T/start" && zsh -f -c "source '$REPO/shell/workbench.zsh'; _wb_main() { integer i=1/0 }; launch; print AFTER rc=\$?") 2>&1)"
assert_contains "an internal error is trapped" "$out" "launcher hit an error"
assert_contains "an internal error still leaves a shell" "$out" "AFTER rc=0"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_launch.sh`
Expected: FAIL lines (`wb-ui` is missing, and `launch` is not defined).

- [ ] **Step 3: Implement `bin/wb-ui`**

```python
#!/usr/bin/env python3
"""wb-ui — the launcher's screen helpers. fzf runs these as child processes,
so they can't be zsh functions. TMP is the launch's scratch dir, holding
spaces.tsv (wb-spaces output).

  wb-ui render-spaces TMP      screen 1 lines: index, label, summary
  wb-ui fill-counts TMP        every space's summary, read in parallel, into
                               TMP/counts/<index>; with $FZF_PORT set, tells
                               fzf to reload as each one lands
  wb-ui render-work TMP INDEX  screen 2 lines: kind, id, worktree, header, text
"""
import os
import shlex
import subprocess
import sys
import threading
import urllib.request

ME = os.path.realpath(__file__)
BACKLOG = os.path.join(os.path.dirname(ME), "wb-backlog")
FIELDS = ("label", "group", "root", "beads", "worktrees", "session_cmd",
          "space_key", "claude_config", "protocol", "safe")
MESSAGES = {  # wb-backlog list exit code -> screen 2 message
    20: "(bd not installed — something new still works)",
    21: "(no bead store — something new still works)",
    22: "(no readable beads — something new still works)",
    23: "(bd unavailable — ctrl-r to retry)",
    24: "0 open (ctrl-r to re-check)",
}


def spaces(tmp):
    with open(os.path.join(tmp, "spaces.tsv")) as f:
        return [dict(zip(FIELDS, l.rstrip("\n").split("\t"))) for l in f if l.strip()]


def render_spaces(tmp):
    rows = spaces(tmp)
    names = [s["label"] if s["group"] == "-" else f"{s['group']} › {s['label']}" for s in rows]
    width = max(map(len, names), default=0)
    for i, (s, name) in enumerate(zip(rows, names), 1):
        summary = ""
        if s["beads"] != "false":
            try:
                with open(os.path.join(tmp, "counts", str(i))) as f:
                    summary = f.read().strip()
            except FileNotFoundError:
                summary = "…"
        print(f"{i}\t{name.ljust(width)}  \t{summary}")
    print("q\t[q] just give me a shell\t-")


def fill_counts(tmp):
    counts = os.path.join(tmp, "counts")
    os.makedirs(counts, exist_ok=True)
    port = os.environ.get("FZF_PORT")
    reload = f"reload({shlex.quote(sys.executable)} {shlex.quote(ME)} render-spaces {shlex.quote(tmp)})"

    def one(i, s):
        p = subprocess.run([BACKLOG, "summary", s["root"]], capture_output=True, text=True)
        path = os.path.join(counts, str(i))
        with open(path + ".part", "w") as f:
            f.write(p.stdout.strip() or "(bd unavailable)")
        os.replace(path + ".part", path)
        if port:
            try:
                urllib.request.urlopen(urllib.request.Request(
                    f"http://127.0.0.1:{port}", data=reload.encode(), method="POST"), timeout=1).close()
            except OSError:
                pass  # fzf has already closed

    threads = [threading.Thread(target=one, args=(i, s))
               for i, s in enumerate(spaces(tmp), 1) if s["beads"] != "false"]
    for t in threads:
        t.start()
    for t in threads:
        t.join()


def render_work(tmp, index):
    s = spaces(tmp)[int(index) - 1]
    print("new\t-\t-\t\t✦ something new", flush=True)
    if s["beads"] == "false":
        return
    p = subprocess.run([BACKLOG, "list", s["root"], "--snapshot", os.path.join(tmp, "snapshot.json")],
                       capture_output=True, text=True)
    if p.returncode != 0:
        print(f"msg\t-\t-\t{MESSAGES.get(p.returncode, MESSAGES[23])}\t")
        return
    rows = [l.split("\t") for l in p.stdout.splitlines() if l]
    waves = any(r[4] != "-" for r in rows)
    current = None
    for bid, short, mark, prio, sect, title, _parent, wt in rows:
        if waves and sect != current:
            current = sect
            print(f"sep\t-\t-\t── {sect if sect != '-' else 'everything else'} ──\t")
        kind = "claimed" if mark == "◐" else "open"
        print(f"{kind}\t{bid}\t{wt}\t\t{mark} {short:<6} {prio}  {title}")


def main(argv):
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    if cmd == "render-spaces" and len(args) == 1:
        render_spaces(*args)
    elif cmd == "fill-counts" and len(args) == 1:
        fill_counts(*args)
    elif cmd == "render-work" and len(args) == 2:
        render_work(*args)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

Run: `chmod +x bin/wb-ui`

- [ ] **Step 4: Append the screens section and `launch` to `shell/workbench.zsh`**

```zsh
# ---- screens ----

_wb_use_fzf() { [[ -z ${WB_NO_FZF-} ]] && (( $+commands[fzf] )) }

# fzf, or, when a test passes a query in $1, the first line containing it.
_wb_fzf() {
  local q=$1; shift
  if [[ -n $q ]]; then grep -F -- "$q" | head -n 1 | grep .; return; fi
  fzf "$@"
}

# One-time hint when fzf is missing.
_wb_fzf_hint() {
  _wb_use_fzf && return 0
  local mark=${XDG_STATE_HOME:-$HOME/.local/state}/workbench/fzf-hint-shown
  [[ -e $mark ]] && return 0
  print -u2 "workbench: tip: brew install fzf for type-to-filter."
  mkdir -p ${mark:h} && : > $mark
}

# Numbered menu for when fzf is missing. $1 file of tab-separated lines,
# $2 prompt, $3 first display column. sep/msg lines are shown, not numbered.
# The menu goes to stderr because stdout carries the chosen line.
# Returns 1 on q, empty input or EOF, and 2 on r (re-read).
_wb_menu() {
  local file=$1 prompt=$2 col=$3 line ans n=0
  local -a pickable f
  for line in "${(@f)$(<$file)}"; do
    f=("${(@ps:\t:)line}")
    if [[ $f[1] == (sep|msg) ]]; then
      print -r -- "      ${(j: :)f[col,-1]}"
    elif [[ $f[1] != q ]]; then
      pickable+=($line)
      printf '  %2d) %s\n' $(( ++n )) "${(j: :)f[col,-1]}"
    fi
  done >&2
  read -r "ans?$prompt number, r = re-read, q = shell: " || return 1
  [[ $ans == r ]] && return 2
  [[ $ans == <1-> && $ans -le $n ]] || return 1
  print -r -- $pickable[ans]
}

# Screen 1. Prints the chosen space's index; returns 1 to leave.
_wb_screen_spaces() {
  local ui=$WORKBENCH_HOME/bin/wb-ui line
  if [[ -n ${WB_TEST_PICK_SPACE-} ]] || _wb_use_fzf; then
    line=$("$ui" render-spaces $tmp | _wb_fzf "${WB_TEST_PICK_SPACE-}" \
      --listen=0 --delimiter=$'\t' --with-nth=2,3 --nth=1 --no-sort --track \
      --layout=reverse --prompt='Space? › ' --header='enter: choose · esc: plain shell' \
      --bind "start:execute-silent(${(q)ui} fill-counts ${(q)tmp} >/dev/null 2>&1 &)") || return 1
  else
    "$ui" fill-counts $tmp            # no fzf: wait for the counts (bounded by the bd timeout)
    "$ui" render-spaces $tmp > $tmp/spaces.menu
    line=$(_wb_menu $tmp/spaces.menu "Space?" 2) || return 1
  fi
  print -r -- ${line%%$'\t'*}
}

# Screen 2. Prints the chosen line (kind, id, worktree, …); returns 1 to leave.
_wb_screen_work() {
  local i=$1 ui=$WORKBENCH_HOME/bin/wb-ui line rc
  if [[ -n ${WB_TEST_PICK_WORK-} ]] || _wb_use_fzf; then
    line=$("$ui" render-work $tmp $i | _wb_fzf "${WB_TEST_PICK_WORK-}" \
      --delimiter=$'\t' --with-nth=4,5 --nth=2 --no-sort --layout=reverse \
      --prompt="$s[1] › " --header='type to filter · ctrl-r: re-read · esc: plain shell' \
      --preview="${(q)WORKBENCH_HOME}/bin/wb-backlog preview ${(q)tmp}/snapshot.json {2}" \
      --preview-window=right,50%,wrap \
      --bind "ctrl-r:reload(${(q)ui} render-work ${(q)tmp} $i)") || return 1
  else
    while true; do
      "$ui" render-work $tmp $i > $tmp/work.menu
      line=$(_wb_menu $tmp/work.menu "Work?" 4); rc=$?
      (( rc == 2 )) && continue
      (( rc == 0 )) || return 1
      break
    done
  fi
  print -r -- $line
}

# ---- launch ----

_wb_main() {
  local tmp=$1 i pick
  local -a rows s p
  "$WORKBENCH_HOME/bin/wb-spaces" > $tmp/spaces.tsv || return 0   # it said why on stderr
  rows=("${(@f)$(<$tmp/spaces.tsv)}")
  [[ -n $rows[1] ]] || { print -u2 "workbench: no spaces found; check ${WORKBENCH_CONFIG:-~/.config/workbench/spaces.toml}"; return 0 }
  _wb_fzf_hint
  i=$(_wb_screen_spaces) || return 0
  [[ $i == <1-> ]] || return 0
  s=("${(@ps:\t:)rows[i]}")
  while true; do
    pick=$(_wb_screen_work $i) || return 0
    p=("${(@ps:\t:)pick}")
    case $p[1] in
      new)     _wb_start_new; return 0 ;;
      open)    _wb_start_bead $p[2]; return 0 ;;
      claimed) _wb_start_claimed $p[2] $p[3] && return 0 ;;
    esac                          # sep/msg rows, or a declined ◐: show screen 2 again
  done
}

# The start screen. Type `launch` any time. Never exits the shell: q, Esc,
# Ctrl-C and errors all end at a normal prompt.
launch() {
  emulate -L zsh
  setopt local_traps
  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/workbench.XXXXXX") || return 0
  {
    _wb_main $tmp
  } always {
    if (( TRY_BLOCK_ERROR )); then
      print -u2 "workbench: the launcher hit an error; you're at a normal shell."
      TRY_BLOCK_ERROR=0
    fi
    rm -rf -- $tmp
  }
  return 0
}
```

`_wb_screen_spaces` and `_wb_screen_work` read `tmp` (and `s`) from `_wb_main` through dynamic scoping, like the handoff helpers. `_wb_main` calls `_wb_screen_spaces` without arguments.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/test_launch.sh && bash tests/run.sh`
Expected: `test_launch.sh` passes on its own, and the runner reports 0 failed in every file.

- [ ] **Step 6: Check the real fzf screens by hand**

**STOP: Tommy runs this in a real Terminal.** fzf needs a TTY, which the executor's shell doesn't have. The executor hands over the command below and waits for the result.

Run (from `~`): `WORKBENCH_DRY_RUN=1 zsh -c 'source ~/dev/workbench/shell/workbench.zsh; launch'`
Expected:
- The space list appears at once with `…`, and the counts fill in within about 1 s without the cursor jumping. If `--track` doesn't hold the cursor, note it in the bead; it is not a blocker.
- Typing filters the list, and Esc ends at a prompt.
- On Acme the preview shows the description, parent and labels, and ctrl-r re-reads.
- Picking a bead prints a `DRY-RUN:` line. This step still runs the real `new-session` for worktree spaces, so pick "something new" in a plain space, or use a personal project.

If the `--nth` semantics noted in Task 0 differ, adjust `--nth` here and re-check.

- [ ] **Step 7: Commit (only if authorised)**

```bash
git add bin/wb-ui shell/workbench.zsh tests/test_launch.sh
git commit -m "feat: launch — space and work screens, fzf with numbered fallback" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Auto-start guards and the run-once hook

**Files:**
- Modify: `shell/workbench.zsh` (append the guards section)
- Test: `tests/test_autostart.sh`

**Interfaces:**
- Consumes: `launch` (Task 5) and `wb-spaces --terminals` (Task 1).
- Produces:
  - `_wb_autolaunch_blockers`: prints the name of every failing guard, one per line, and returns 0 only if none fail. The names are `interactive`, `tty`, `claudecode`, `no_launch`, `shlvl`, `terminal` and `git_repo`.
  - A `precmd` hook that runs once.

- [ ] **Step 1: Write the failing tests**

`tests/test_autostart.sh`:
```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/plain" "$T/repo" "$T/zdot"; git -C "$T/repo" init -q
printf '[launcher]\nterminals = ["WezTerm"]\n[[space]]\nname = "X"\nroot = "%s"\n' "$T/plain" > "$T/spaces.toml"
export WORKBENCH_CONFIG="$T/spaces.toml"
# blockers [env assignments…]: guard names from a non-interactive zsh in $T/plain
blockers() { (cd "$T/plain" && env -u CLAUDECODE -u WORKBENCH_NO_LAUNCH TERM_PROGRAM=Apple_Terminal SHLVL=0 "$@" \
  zsh -f -c "source '$REPO/shell/workbench.zsh'; _wb_autolaunch_blockers"); }

out="$(blockers)"
assert_contains "non-interactive is blocked" "$out" "interactive"
assert_not_contains "default env: no claudecode" "$out" "claudecode"
assert_not_contains "default env: SHLVL 1 passes" "$out" "shlvl"
assert_not_contains "Apple_Terminal passes" "$out" "terminal"
assert_not_contains "non-repo folder passes" "$out" "git_repo"
assert_contains "inside Claude is blocked" "$(blockers CLAUDECODE=1)" "claudecode"
assert_contains "escape hatch" "$(blockers WORKBENCH_NO_LAUNCH=1)" "no_launch"
assert_contains "nested shell is blocked" "$(blockers SHLVL=3)" "shlvl"
assert_contains "VS Code terminal is blocked" "$(blockers TERM_PROGRAM=vscode)" "terminal"
assert_not_contains "terminal listed in config passes" "$(blockers TERM_PROGRAM=WezTerm)" "terminal"
out="$(cd "$T/repo" && env -u CLAUDECODE TERM_PROGRAM=Apple_Terminal SHLVL=0 zsh -f -c "source '$REPO/shell/workbench.zsh'; _wb_autolaunch_blockers")"
assert_contains "inside a git repo is blocked" "$out" "git_repo"

# True positive in a real pty: first prompt runs launch once (stubbed).
cat > "$T/zdot/.zshrc" <<EOF
source '$REPO/shell/workbench.zsh'
launch() { print LAUNCHED-STUB }
EOF
pty() { (cd "$1" && printf 'true\nexit\n' | env -u CLAUDECODE -u WORKBENCH_NO_LAUNCH ZDOTDIR="$T/zdot" \
  TERM_PROGRAM=Apple_Terminal SHLVL=0 perl -e 'alarm 10; exec @ARGV' script -q /dev/null zsh -i 2>&1); }
out="$(pty "$T/plain")"
assert_contains "new window in a plain folder launches" "$out" "LAUNCHED-STUB"
assert_eq "it launches once, not at every prompt" "$(printf '%s' "$out" | grep -c LAUNCHED-STUB)" "1"
assert_not_contains "new tab inside a repo does not launch" "$(pty "$T/repo")" "LAUNCHED-STUB"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_autostart.sh`
Expected: FAIL (`_wb_autolaunch_blockers: command not found`, and no `LAUNCHED-STUB`).

- [ ] **Step 3: Append the guards section to `shell/workbench.zsh`**

```zsh
# ---- auto-start ----

_wb_terminal_allowed() {
  emulate -L zsh
  [[ ${TERM_PROGRAM-} == Apple_Terminal ]] && return 0
  [[ -n ${TERM_PROGRAM-} ]] || return 1
  local t
  for t in ${(f)"$($WORKBENCH_HOME/bin/wb-spaces --terminals 2>/dev/null)"}; do
    [[ $t == $TERM_PROGRAM ]] && return 0
  done
  return 1
}

# Prints every guard that blocks auto-start, one name per line; returns 0 only
# when none do. Each guard is checked on its own so tests can see each one.
_wb_autolaunch_blockers() {
  emulate -L zsh
  local -a blocked
  [[ -o interactive ]]             || blocked+=(interactive)
  [[ -t 0 && -t 1 ]]               || blocked+=(tty)
  [[ -z ${CLAUDECODE-} ]]          || blocked+=(claudecode)
  [[ -z ${WORKBENCH_NO_LAUNCH-} ]] || blocked+=(no_launch)
  [[ ${SHLVL-} == 1 ]]             || blocked+=(shlvl)
  _wb_terminal_allowed             || blocked+=(terminal)
  git rev-parse --is-inside-work-tree &>/dev/null && blocked+=(git_repo)
  (( $#blocked )) || return 0
  print -l -- $blocked
  return 1
}

# Runs at the first prompt, after all of .zshrc (claude(), aliases, PATH) is
# defined. Removes itself first, so it never runs twice.
_wb_first_prompt() {
  emulate -L zsh
  add-zsh-hook -d precmd _wb_first_prompt
  _wb_autolaunch_blockers >/dev/null && launch
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _wb_first_prompt
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/test_autostart.sh && bash tests/run.sh`
Expected: all pass. If the pty test hangs or `script` misbehaves with piped stdin, `perl alarm` ends it after 10 s.
- **If it fails for that reason**, record the failure output in the bead, and keep the guard-name tests.
- **Do not weaken the guard to make it pass.** Acceptance items 1 and 6 cover the same behaviour by hand.

- [ ] **Step 5: Commit (only if authorised)**

```bash
git add shell/workbench.zsh tests/test_autostart.sh
git commit -m "feat: auto-start the launcher at the first prompt of a new Terminal window" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Install, example config, leak check, private config

**Files:**
- Create: `install.sh`, `spaces.example.toml`, `scripts/check-leaks.sh`
- Modify: `CLAUDE.md` and `AGENTS.md` (`## Build & Test` section)
- Create, outside the repo: `~/.config/workbench/spaces.toml`
- Test: `tests/test_install.sh`

**Interfaces:**
- Consumes: `bin/*`, `wb-spaces --leak-terms` (Task 1).
- Produces:
  - `install.sh`: honours `WB_BIN_DIR` (default `~/.local/bin`) and `ZDOTDIR`.
  - `scripts/check-leaks.sh`: honours `WB_LEAK_REPO` (default: this repo). Exits 1 if a leak is found.

- [ ] **Step 1: Write the failing tests**

`tests/test_install.sh`:
```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/z"
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

assert_eq "example config parses" "$(WORKBENCH_CONFIG="$REPO/spaces.example.toml" "$REPO/bin/wb-spaces" >/dev/null 2>&1; echo $?)" "0"

mkdir -p "$T/leak" && git -C "$T/leak" init -q
printf '[[space]]\nname = "Zanzibar"\nroot = "%s"\n' "$T" > "$T/leak.toml"
echo "nothing private here" > "$T/leak/a.txt"; git -C "$T/leak" add a.txt
out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/leak" bash "$REPO/scripts/check-leaks.sh" 2>&1)"; rc=$?
assert_eq "clean repo passes" "$rc" "0"
echo "deploys to zanzibar today" > "$T/leak/b.txt"; git -C "$T/leak" add b.txt
out="$(WORKBENCH_CONFIG="$T/leak.toml" WB_LEAK_REPO="$T/leak" bash "$REPO/scripts/check-leaks.sh" 2>&1)"; rc=$?
assert_eq "leak fails" "$rc" "1"
assert_contains "leak names the file" "$out" "b.txt"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_install.sh`
Expected: FAIL (`install.sh` is missing).

- [ ] **Step 3: Implement `install.sh`**

```bash
#!/usr/bin/env bash
# Link bin/* into ~/.local/bin and print the line to add to ~/.zshrc.
# Idempotent. Never edits ~/.zshrc and never replaces a file it didn't create.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dest="${WB_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$dest"
for src in "$here"/bin/*; do
  link="$dest/$(basename "$src")"
  if [ -L "$link" ] && [ "$(readlink "$link")" != "$src" ] && [[ "$(readlink "$link")" != "$here"/* ]]; then
    echo "skip: $link points somewhere else ($(readlink "$link")); left alone" >&2; continue
  elif [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "skip: $link exists and is not a symlink; left alone" >&2; continue
  fi
  ln -sfn "$src" "$link"
  echo "linked $link -> $src"
done
command -v fzf >/dev/null || echo "note: fzf not found; the launcher will use a numbered menu (brew install fzf)."
command -v bd  >/dev/null || echo "note: bd not found; spaces will show (bd not installed)."
python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' || echo "note: python3 >= 3.11 is required."
line="source \"$here/shell/workbench.zsh\""
if grep -qF "$line" "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null; then
  echo "~/.zshrc already sources workbench."
else
  echo
  echo "Add this line to the END of ~/.zshrc:"
  echo "  $line"
fi
```

Run: `chmod +x install.sh`

- [ ] **Step 4: Write `spaces.example.toml`**

```toml
# Copy to ~/.config/workbench/spaces.toml and edit it there. This file stays
# generic: real names, paths and accounts live only in your copy.

[launcher]
# $TERM_PROGRAM values, besides Apple_Terminal, that should auto-start the launcher.
terminals = []
# Space names that are ordinary words, which check-leaks.sh should not flag.
leak_allow = []

# A space whose sessions each get their own git worktree, via a session command.
[[space]]
name          = "Acme"
root          = "~/dev/acme/app"
beads         = true
worktrees     = true
session_cmd   = "new-session"       # takes <bead-id> or <space_key>, plus --no-launch,
                                    # and then prints WORKTREE_DIR=<path> as its last line
space_key     = "acme"
claude_config = "~/.claude-acme"    # optional: a non-default Claude profile
protocol      = "docs/PROTOCOL.md"  # optional: read first in every session
# safe        = true                # keep Claude's permission prompts on

# One entry per folder; sessions start in the folder itself.
[[space]]
name      = "Side projects"
glob      = "~/dev/side/*"
beads     = "if-present"
worktrees = false
```

- [ ] **Step 5: Implement `scripts/check-leaks.sh`**

```bash
#!/usr/bin/env bash
# Run before any push. Fails if a tracked file names a space, profile, user
# or email from this machine's private config. Whole words, any case.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="${WB_LEAK_REPO:-$here}"
terms="$(mktemp)"; trap 'rm -f "$terms"' EXIT
{ "$here/bin/wb-spaces" --leak-terms; id -un; git -C "$repo" config user.email || true; } \
  | awk 'length($0) >= 3' | sort -u > "$terms"
if git -C "$repo" grep -n -I -w -i -F -f "$terms" -- . ; then
  echo "check-leaks: the lines above name something from your private config. Fix them before pushing." >&2
  exit 1
fi
echo "check-leaks: clean ($(wc -l < "$terms" | tr -d ' ') terms checked)"
```

Run: `chmod +x scripts/check-leaks.sh`

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/test_install.sh && bash tests/run.sh`
Expected: all pass.

- [ ] **Step 7: Fill in `## Build & Test` in `CLAUDE.md` and mirror it in `AGENTS.md`**

Replace the placeholder block under `## Build & Test` in both files with:
````markdown
```bash
tests/run.sh               # all tests (plain bash; fakes for bd/new-session/claude)
./install.sh               # link bin/* into ~/.local/bin, print the ~/.zshrc line
scripts/check-leaks.sh     # before any push: no private names in tracked files
```
````

- [ ] **Step 8: Write Tommy's private config (outside the repo) and install**

Create `~/.config/workbench/spaces.toml`:
```toml
[launcher]
terminals = []
leak_allow = ["done", "people"]   # personal project names that are ordinary words

[[space]]
name          = "Acme"
root          = "~/dev/acme/acme-app"
beads         = true
worktrees     = true
session_cmd   = "new-session"
space_key     = "acme"
claude_config = "~/.claude-acme"
protocol      = "docs/PROGRAM_PROTOCOL.md"

[[space]]
name      = "Personal"
glob      = "~/dev/personal/*"
beads     = "if-present"
worktrees = false
```

Run: `bin/wb-spaces && ./install.sh && scripts/check-leaks.sh`
Expected:
- `wb-spaces` prints 1 Acme line plus 11 personal lines.
- `install.sh` links `wb-spaces`, `wb-backlog` and `wb-ui`, and prints the `source` line.
- `check-leaks.sh` **fails** on the spec and plan docs. That is expected until Tommy's Task 0 decision 3 is carried out. Report its output; don't change the docs in this task.

- [ ] **Step 9: Commit (only if authorised)**

```bash
git add install.sh spaces.example.toml scripts/check-leaks.sh tests/test_install.sh CLAUDE.md AGENTS.md
git commit -m "feat: install script, example config and pre-push leak check" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Hand acceptance (Tommy, in a real Terminal window)

**STOP: this whole task is Tommy's.** The executor reports that Tasks 1–7 are done and waits.

**Files:** none (`~/.zshrc` gets the one line Tommy adds himself).

- [ ] **Step 1: Tommy adds the `source "…/shell/workbench.zsh"` line printed by `install.sh` to the end of `~/.zshrc`.**

- [ ] **Step 2: Run the spec's acceptance list, tick each item, and note failures in the bead**
  1. A new window shows the summary.
  2. Acme → a NOW bead → an Acme worktree session starts on the Acme account, already briefed. Check with `/status` inside Claude.
  3. Acme → something new → an exploratory worktree.
  4. A personal project → something new → Claude starts in that folder on the personal account.
  5. `q` (or Esc) gives a plain shell.
  6. VS Code's terminal, and a new tab opened inside a worktree, do not launch it.
  7. After Claude exits, the shell is in the session's folder.
  8. Additionally, Acme → a `◐` bead offers "resume there", or reports a stale claim.

- [ ] **Step 3: Close out**

Run: `bash tests/run.sh && bd close wb-1fy --reason="Launcher accepted by hand; all tests pass"`. Then file the beads for anything the acceptance run turned up.
