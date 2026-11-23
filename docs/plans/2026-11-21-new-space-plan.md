# New space + commands submenu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `+ new space` in a new `✦ more…` launcher submenu makes a right-sized project (an idea, or a tool with a branch per task) and starts Claude shaping it.

**Architecture:** A non-prompting core (`lib/wb_newspace.py`, python 3.9-safe) does the steps; `bin/wb-new-space` asks the questions or, with `--json`, takes them as flags. `wb-setup` imports the core's config-writing pieces. The launcher gets a submenu screen (`wb-ui render-more`) and hands off to the new space's something-new session with a new prompt.

**Tech Stack:** python 3.9+ stdlib (core, wb-new-space, wb-setup), python 3.11 (wb-spaces, wb-ui), zsh (launcher), plain-bash tests.

**Spec:** `docs/specs/2026-11-21-new-space-design.md`

## Global Constraints

- `lib/wb_newspace.py` and `bin/wb-new-space` are 3.9-safe: no `tomllib`, no `match`, no `X | Y` types; config is read back only through `bin/wb-spaces`.
- No private names anywhere in the repo, tests, template or prompt: examples are Acme-style.
- Tests first: every task's tests are written and seen failing before its code.
- One commit for the whole bead (repo rule), at the end, `feat: + new space and a commands submenu in the launcher (wb-kvx.24.1)`; tasks end with `tests/run.sh` green, not a commit.
- Own-space parent folder: `~/dev`, overridable by env `WB_NEW_SPACE_PARENT` (the test seam).
- Kinds are exactly `idea` and `tool`; labels `an idea or notes` / `a tool for me`; default `tool`.
- `git init -b main`; `bd init --non-interactive` via `wb_doctor.bd_cmd()`.
- A failed run never leaves `spaces.toml` changed and never deletes the folder.

## Review Focus

- **The name has spaces or capitals** ("My App"): folder is `My App`, label `My App`, `space_key` is `my-app`. Test in Task 3.
- **`WORKBENCH_CONFIG` file doesn't exist yet** (first space ever made from the launcher is impossible, but `--json` from Desktop could be): create with wb-setup's `HEADER`, as `write_config` does. Test in Task 2.
- **Two areas share a parent folder or an area's parent doesn't exist**: an area whose parent isn't a folder is not offered. Test in Task 1.
- **`bd init` fails** (bd missing, or exits non-zero): stops after git init, result says the folder and `cd <folder> && bd init`; `spaces.toml` untouched. Test in Task 3.
- **Esc / EOF at any question in `wb-new-space`**: exits 1 having made nothing, and the launcher returns to the submenu. Test in Task 4.

---

### Task 1: `wb-spaces --areas`

**Files:**
- Modify: `bin/wb-spaces` (docstring, `main`)
- Test: `tests/test_wb_spaces.sh`

**Interfaces:**
- Produces: `wb-spaces --areas` prints a JSON list, one object per glob space whose glob's last component is exactly `*`, whose `beads` isn't `"false"`, and whose parent folder exists: `{"name": str, "parent": abs path, "worktrees": bool, "beads": "true"|"if-present", "claude_config": abs path or ""}`, in config order.

- [ ] **Step 1: Write the failing tests** in `tests/test_wb_spaces.sh`, with a config holding: `Side` (`glob = "$T/side/*"`), `Odd` (`glob = "$T/odd/x-*"`), `Off` (`glob = "$T/off/*"`, `beads = false`), `Gone` (`glob = "$T/gone/*"`, no folder), `Acme` (root). Assert:
  - `--areas` output parses as JSON (`python3 -c 'import json,sys; json.load(sys.stdin)'`), exit 0;
  - names are exactly `["Side"]`;
  - Side's `parent` is `$T/side`, `worktrees` false, `beads` `"if-present"`;
  - a `Side2` with `worktrees = true` and `claude_config` set reports both.
- [ ] **Step 2: Run** `bash tests/test_wb_spaces.sh` — new asserts FAIL.
- [ ] **Step 3: Implement** in `main`, after the config validates: iterate `cfg["space"]`, keep entries with `"glob"` where `os.path.basename(glob) == "*"`; parent = `expand(os.path.dirname(glob))`; skip when not `os.path.isdir(parent)` or beads (as `spaces()` normalises it) is `"false"`. Add the line to the docstring.
- [ ] **Step 4: Run** `bash tests/test_wb_spaces.sh` — all PASS.

### Task 2: Move wb-setup's config writing into `lib/wb_newspace.py`

**Files:**
- Create: `lib/wb_newspace.py`
- Modify: `bin/wb-setup` (delete the moved functions; import and call them)
- Test: `tests/test_wb_setup.sh` (existing, unchanged, must stay green), `tests/test_new_space.sh` (new)

**Interfaces:**
- Produces (all in `lib/wb_newspace.py`):
  - `slug(name: str) -> str` (as today)
  - `tilde(p: str) -> str`, `toml_str(s: str) -> str` (as today)
  - `space_toml(s: dict) -> str` — as today, plus a `claude_config = "<tilde path>"` line when `s.get("claude_config")`
  - `unique_key(name: str, taken: set) -> str` — `slug(name)`, then `-2`, `-3`… (wb-setup's loop)
  - `HEADER: str` (moved)
  - `append_spaces(path: str, new: list, header_ref: str) -> (bool, str)` — `write_config`'s write + `wb_doctor.spaces()` read-back + restore, with no printing; returns `(True, "")` or `(False, reason)`. `header_ref` is the `spaces.example.toml` path for the header.
  - `init_backlog(folder: str) -> (bool, str)` — runs `[wb_doctor.bd_cmd(), "init", "--non-interactive"]` in folder (timeout 300); `(False, "bd not found")` when `bd_cmd()` is None.
- wb-setup keeps `say`, its metrics note (wrapping `init_backlog`'s output) and the `ok`/`!!` lines it prints today.

- [ ] **Step 1: Write the failing test** `tests/test_new_space.sh` (source `lib.sh`, `T=$(cd "$(newtmp)" && pwd -P)`): call via `python3 -c "import sys; sys.path.insert(0,'$REPO/lib'); import wb_newspace as n; …"`:
  - `n.unique_key("My App", {"my-app"})` == `my-app-2`;
  - `n.space_toml({"name":"Acme","root":"$T/a","beads":"true","worktrees":True,"space_key":"acme","claude_config":"$T/cfg"})` contains `claude_config = "$T/cfg"` and `space_key = "acme"`;
  - `append_spaces` to a missing `$T/new/spaces.toml` creates it starting with `# workbench's spaces`, and `wb-spaces` then lists the space;
  - `append_spaces` with a space whose root doesn't exist and `worktrees=True` with a key already used → `(False, …)` and the file is byte-identical to before.
- [ ] **Step 2: Run** `bash tests/test_new_space.sh` — FAIL (no module).
- [ ] **Step 3: Implement** `lib/wb_newspace.py` (3.9-safe, imports `wb_doctor` from its own folder) and switch `bin/wb-setup` to it: `spaces()` uses `unique_key`, `write_config` becomes a call to `append_spaces` plus wb-setup's own messages.
- [ ] **Step 4: Run** `bash tests/test_new_space.sh && bash tests/test_wb_setup.sh` — all PASS, wb-setup's output unchanged.

### Task 3: `create()`, the CLAUDE.md template, and `wb-new-space --json`

**Files:**
- Modify: `lib/wb_newspace.py`
- Create: `lib/new-space-templates/CLAUDE.md`, `bin/wb-new-space`
- Test: `tests/test_new_space.sh`

**Interfaces:**
- Consumes: Task 1's `--areas`, Task 2's functions.
- Produces:
  - `areas() -> list` — `wb-spaces --areas` parsed; `[]` on any failure.
  - `create(kind: str, name: str, area: str = None, account: str = None) -> dict` — `kind` `"idea"`|`"tool"`; `area` an area name (idea only; `None` → own space); `account` a `claude_config` path or `None`. Returns `{"ok": bool, "root": str, "space": label, "kind": kind, "worktrees": bool, "done": [step names], "left": str, "error": str}`. Step names: `folder`, `git`, `backlog`, `process`, `config`. On failure `left` says what exists and the command to finish (`cd <root> && bd init`) or remove it (`rm -rf <root>`).
  - `check_name(name: str, rows: list, parent: str) -> str` — `""` if fine, else the reason (empty, `/`, leading `.`, `<path> exists; to make it a space, run wb-setup`, `already a space called <name>`).
  - `wb-new-space --json --kind idea|tool --name N [--area A] [--account PATH]` → prints `create()`'s dict as JSON; exit 0 when ok, 1 otherwise; nothing prompted.

- [ ] **Step 1: Write the failing tests** (a bd stub on `PATH` as in `test_wb_setup.sh`, but its `init` also does `git add -A && git commit -qm "bd init"` and writes a `CLAUDE.md` holding `<!-- BEGIN BEADS -->`; `git config` user via `GIT_AUTHOR_*`/`GIT_COMMITTER_*` env; `WB_NEW_SPACE_PARENT=$T/dev`; config with `Side` glob `$T/side/*` and `Acme` root). Assert:
  - `--kind tool --name "My App"`: exit 0; `$T/dev/My App` exists; `git -C … symbolic-ref --short HEAD` is `main`; 2 commits; CLAUDE.md contains `<!-- BEGIN BEADS -->` and, after it, `Team-maintainer` and `merge --ff-only`; `wb-spaces` row for `My App` has worktrees `1`, key `my-app`; JSON `done` is `["folder","git","backlog","process","config"]`;
  - `--account $T/cfg`: the row's claude_config is `$T/cfg`; without it the toml has no `claude_config` line for that space;
  - `--kind idea --name notes --area Side`: `$T/side/notes` exists with `.beads`; CLAUDE.md has no `Team-maintainer`; `spaces.toml` unchanged (cmp); `wb-spaces` lists `notes` in group `Side`;
  - `--kind idea --name loose` (no area): own `[[space]]` with `worktrees = false`, no `space_key` line;
  - refusals, each exit 1 with nothing made: existing folder (`exists; to make it a space, run wb-setup`), name `Acme` (`already a space called Acme`), `a/b`, `.x`, empty;
  - bd stub exiting 1 on init: exit 1, `done` is `["folder","git"]`, `left` contains `bd init`, `spaces.toml` unchanged.
  (Private names in the template are `scripts/check-leaks.sh`'s job, run at close; a test can't name them without leaking them.)
- [ ] **Step 2: Run** `bash tests/test_new_space.sh` — new asserts FAIL.
- [ ] **Step 3: Implement** `create` (steps in the spec's order; `process` appends the template then `git add CLAUDE.md && git commit -qm "workbench: how work is done here"`, only when the space will have worktrees; `config` only for own spaces, via `append_spaces` with `unique_key` over existing worktree keys), `check_name`, `areas`, and `bin/wb-new-space` (`#!/usr/bin/env python3`, argparse). An idea in an area with `worktrees` true runs `process` too. Write the template per the spec's "CLAUDE.md process section", headed `## How work is done here (workbench)`.
- [ ] **Step 4: Run** `bash tests/test_new_space.sh` — all PASS.

### Task 4: `wb-new-space` asks the questions

**Files:**
- Modify: `bin/wb-new-space`
- Test: `tests/test_new_space.sh`

**Interfaces:**
- Consumes: `create`, `check_name`, `areas`, `wb_doctor.spaces()` (extend its row dicts with `"claude_config": f[7]` when not `-`, else `""`).
- Produces: `wb-new-space` (no flags) reads answers from stdin, one per line (`''` takes the default), prints the questions on stderr; on success prints the new space's root as its **last stdout line** and exits 0; exit 1 when declined, on EOF, or on a failed `create` (its `error` and `left` on stderr).

Question order (spec "What it asks"): kind (numbered 1/2, default 2) → area (only for idea; skipped with one area; numbered when several; none → own space) → name (re-asked on a `check_name` reason) → account (tool, or idea without area: numbered list of distinct `claude_config` values plus `the default account`, default = most used) → summary + `Make it? [Y/n]`.

- [ ] **Step 1: Write the failing tests**: `printf '2\nMy Tool\n\n\n' | wb-new-space` → exit 0, last stdout line `$T/dev/My Tool`; `printf '1\nidea1\n\n'` with one area → made in `$T/side/idea1`, no area question shown; two areas → the area question lists both; a taken name then a good one → the reason, then made; `n` at confirm → exit 1, nothing made; EOF after kind → exit 1, nothing made.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** the interactive path in `bin/wb-new-space`.
- [ ] **Step 4: Run** `bash tests/test_new_space.sh` — PASS.

### Task 5: The `✦ more…` submenu

**Files:**
- Modify: `bin/wb-ui` (`render_spaces`, new `render_more`, `main`), `shell/workbench.zsh` (`_wb_main`, new `_wb_screen_more`, `_wb_more`)
- Test: `tests/test_launch.sh` (rewrite the tabs-row cases at lines ~295-317 and the waiting-count case ~369-390)

**Interfaces:**
- Produces:
  - `render-spaces` prints `more\t✦ more…\t<waiting text>` where it printed the `tabs` row.
  - `wb-ui render-more TMP` prints, tab-separated `key\tlabel\tnote`: `new\t+ new space\tstart a project: folder, git, backlog, first epic`, `tabs\t✦ open tabs\t<waiting text>`, `tidy\t✦ tidy worktrees\tend the finished ones`, `doctor\t✦ health check\twb-doctor`, `update\t✦ update\twb-update`, `back\t← back\t`.
  - `_wb_screen_more` prints the chosen key (fzf with `WB_TEST_PICK_MORE`, else `_wb_menu`); esc → `back`.
  - `_wb_more` loops: `tabs` → `_wb_show_tabs`; `tidy|doctor|update` → run `$WORKBENCH_HOME/bin/wb-tidy|wb-doctor|wb-update`, then `_wb_tabs_pause`; `back` → return 2 (to screen 1); `new` → Task 6 (until then, return 2). Returns 0 when a session started, 1 on EOF.

- [ ] **Step 1: Write the failing tests**: numbered menu shows `✦ more…` and no `✦ open tabs` on screen 1; choosing it shows `More?` with the six rows in order; `tabs` from there shows the tabs view, pauses, returns to `More?`; `back` returns to screen 1 and a session still starts after; the waiting count is on the `more` row and on `✦ open tabs` inside; `WB_TEST_PICK_SPACE='✦ more…' WB_TEST_PICK_MORE='health check'` runs a fake `wb-doctor` (copy `bin/` to a temp `WORKBENCH_HOME` as the waiting-count test does) and pauses.
- [ ] **Step 2: Run** `bash tests/test_launch.sh` — FAIL.
- [ ] **Step 3: Implement**; `_wb_main`'s `[[ $i == tabs ]]` branch becomes `more` → `_wb_more` (rc 2: screen 1 again; 0: done; 1: leave).
- [ ] **Step 4: Run** `bash tests/test_launch.sh` — PASS.

### Task 6: `+ new space` hands off to the new project's first session

**Files:**
- Modify: `shell/workbench.zsh` (`_wb_more`'s `new`), Create: `prompts/new-project.txt`
- Modify docs: `README.md` (launcher section: the submenu and `+ new space`), `CLAUDE.md` (Architecture: `bin/wb-new-space`, `lib/wb_newspace.py`), `docs/vision.md` (what works today, if it lists launcher commands)
- Test: `tests/test_launch.sh`

**Interfaces:**
- Consumes: `wb-new-space`'s last stdout line (the root), `_wb_main`'s row re-read.
- Produces: after `+ new space`, the launcher re-runs `wb-spaces` into `$tmp/spaces.tsv`, sets `rows`/`s` to the row whose root (field 3) equals the printed root, and runs `_wb_start_new` with prompt `new-project` (pass the prompt name as `$1` to `_wb_start_new`, default `something-new`). A failed or declined `wb-new-space` pauses and returns to `More?`.

`prompts/new-project.txt` (modelled on `something-new.txt`, same `{space}`/`{protocol}` placeholders): this is a brand-new project in {space}; ask what it's for and what done looks like; file one epic with the why in `--description`, decisions in `--design`, open questions in `--notes`, then its first beads under it with `--parent`; only then start building.

- [ ] **Step 1: Write the failing tests** (`WB_NEW_SPACE_PARENT=$T/dev`, the bd stub from Task 3 on PATH for this case, and a temp `WORKBENCH_HOME` copied from the repo, as the waiting-count case does, with its `bin/new-session` replaced by `tests/fake/new-session`, since a new space's `session_cmd` is the default one next to `wb-spaces`): `WB_TEST_PICK_SPACE='✦ more…' WB_TEST_PICK_MORE='new space'` with stdin `2\nGadget\n\n\n` → `$FAKE_NS_LOG` names key `gadget`, output has `DRY-RUN: cd $FAKE_NS_DIR` and the prompt text `brand-new project`; with `n` at confirm → back on `More?`, no DRY-RUN.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** the handoff, the prompt, the doc lines.
- [ ] **Step 4: Run** `tests/run.sh` — every suite 0 failed.

### Task 7: Close

- [ ] `tests/run.sh`: all 0 failed.
- [ ] Try it for real once: `WB_NEW_SPACE_PARENT=$(mktemp -d) WORKBENCH_CONFIG=<copy of spaces.toml> bin/wb-new-space`, make a tool space, check `wb-doctor` is clean against that config; remove the temp folder.
- [ ] `bd close wb-kvx.24.1 --reason=…`, stage by name, one commit, `scripts/check-leaks.sh`, push, `gh pr create --fill` (repo's closing order in CLAUDE.md).
