# Session Knows Its Bead Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every workbench-launched Claude session knows which bead it serves. The status line
shows it, Claude is handed it back after compaction, a session with no bead picks one up when
Claude claims it, a second claim makes Claude ask "continue here or start fresh", and closing the
bead tells the session it's done.

**Architecture:**
- **`lib/wb_session.py`** is shared python. It holds:
  - the per-session binding file under `$WB_STATE_DIR/sessions/`
  - reading a bead with `bd show`
  - parsing a Bash command for bd claims and closes
  - the status line segment
- **`bin/wb-session-hook`** is one python script with a subcommand per hook event, plus a
  `settings` subcommand that prints the `--settings` JSON.
- **`bin/wb-focus`** and **`bin/wb-statusline-bead`** are thin python front ends on the lib.
- **The launcher and `new-session`** add `--settings` and the `WB_*` environment to the `claude`
  command.
- **`wb-backlog claimed`** breaks ties by `updated_at`.

**Tech Stack:**
- python 3.11+, standard library only (`json`, `shlex`, `subprocess`, `re`)
- zsh for the launcher, bash 3.2 for `new-session`
- plain bash tests with `tests/fake/bd`

**Spec:** `docs/specs/2026-10-21-session-bead-design.md`. Read it first; this plan argues from it.

## Global Constraints

- **Only sessions workbench starts.** Nothing is written into a repo or `~/.claude`, and
  `--settings` never sets `statusLine`.
- **Awareness code fails silent.** On any error, every hook exits 0 with no output, and
  `wb-statusline-bead` prints nothing. `wb-focus` is the exception: a person or Claude runs it, so
  it reports errors on stderr and exits 1.
- **No reminder on every prompt.** UserPromptSubmit returns only a `sessionTitle`, and only when
  the bead changed.
- **The status line reads one file and never calls `bd`.**
- **`bd` calls use a timeout:** `WB_BD_TIMEOUT` for reads (default 3s, as in `wb-backlog`) and
  `WB_BD_WRITE_TIMEOUT` for writes (default 30s, as in `lib/session.sh`). Use `WB_BD` for the
  binary.
- **Binding path:** `${WB_STATE_DIR:-~/.cache/workbench}/sessions/<session_id>.json`. Write it to
  a `.part` file, then rename. A session id that doesn't match `^[A-Za-z0-9-]{1,64}$` is never
  used in a path.
- **Binding fields:** `bead`, `title`, `root`, `since` (UTC ISO-8601 `Z`), `done` (bool) and
  `named` (the title last sent as `sessionTitle`, or null).
- **Display forms:**
  - The short id is `id.rsplit("-", 1)[-1]`, as in `wb-backlog`.
  - Titles in the status line are cut to 40 characters, with `…` replacing the last one when cut.
  - Segments: `◆ <short> <title>`, `✓ <short> done · close this session`, `◇ no bead`.
- **Claim note form:** `Branch: <branch> (worktree at <path>)`, as written by `bin/new-session`.
- **Prune:** binding files with an mtime over 30 days old are deleted on SessionStart.
- **Repo rules:**
  - Tests come first.
  - Comments say why.
  - Examples use Acme.
  - Run `scripts/check-leaks.sh` before committing.
  - Commit only when the user says so. "Commit" steps below are checkpoints, so ask first.

## Review Focus

1. **bd text quoted inside another command** (`bd create --description "… bd close acme-x1y …"`,
   `echo "bd update x --claim"`) must not count as a claim or a close. Tokenize with
   `shlex.shlex(cmd, posix=True, punctuation_chars=True)` and only read `bd` at the start of a
   command segment. Tests in Task 2.
2. **A bd command that ran but did nothing** must not move the binding: a close refused for open
   children, or a claim of a bead someone else holds. Confirm with `bd show` (status
   `in_progress` for a claim, `closed` for a close) before acting. Tests in Task 3.
3. **A hanging or missing `bd`** must not stall the session. Hooks give up at the timeout and exit
   0 silently. Tests in Tasks 2 and 3.
4. **Paths with spaces** in `WORKBENCH_HOME`, the space root or the worktree must still work. The
   `settings` JSON quotes the command with `shlex.quote`, and the env vars pass through unsplit.
   Tests in Tasks 2 and 5.
5. **Two sessions side by side** keep separate files and never read each other's binding. A test
   in Task 1 uses two session ids.

---

### Task 1: Binding store, status line segment and `wb-focus`

**Files:**
- Create: `lib/wb_session.py`, `bin/wb-statusline-bead`, `bin/wb-focus`
- Test: `tests/test_wb_session.sh`

**Interfaces:**
- Produces, in `lib/wb_session.py`:
  - `state_dir() -> str`
  - `binding_path(sid: str) -> str | None`, which returns None for an unsafe id
  - `load(sid: str) -> dict | None`, which returns None when the file is missing or corrupt
  - `save(sid: str, binding: dict) -> None`, an atomic write
  - `prune(days: int = 30) -> None`
  - `short(bead_id: str) -> str`
  - `show(root: str, bead_id: str) -> dict | None`, which runs `bd show <id> --json` in `root`
    with the read timeout, skips leading `Warning` lines as `wb-backlog` does, and returns the bead
    dict or None
  - `bind(sid: str, bead: dict, root: str) -> dict`, which writes a fresh binding (`done` false,
    `named` null) and returns it
  - `note_claim(root: str, bead: dict, worktree: str) -> str | None`. When `worktree` is non-empty
    and no claim note in `bead["notes"]` names its realpath, it appends the claim note with
    `bd update <id> --append-notes …` and the write timeout. It returns an error string on
    failure, otherwise None.
  - `segment(stdin_json: dict, env: Mapping) -> str`
- Produces CLIs:
  - **`wb-statusline-bead`** reads the status line JSON on stdin and prints `segment(...)`, or
    nothing.
  - **`wb-focus [<id> | --clear]`:**
    - It uses `CLAUDE_CODE_SESSION_ID`.
    - The root comes from the existing binding, else `WB_SPACE_ROOT`.
    - It calls `note_claim` with `WB_WORKTREE`.
    - It prints `→ this session is now on <short> <title>`, the binding as `<id> <title>`
      (or `no bead`), or `→ unbound`.

- [ ] **Step 1: Write failing tests** in `tests/test_wb_session.sh`, with `WB_STATE_DIR=$T/state`,
  a store made with `mkstore` holding `.beads/fake.json` with beads `acme-x1y` (title "Fix fabric
  PO search", in_progress) and `acme-q9z` (a 45-character title), and `FAKE_BD_LOG`:
  - `statusline: bound` → stdin `{"session_id":"s1"}` with an `s1` binding prints exactly
    `◆ x1y Fix fabric PO search`
  - `statusline: done` → `✓ x1y done · close this session`
  - `statusline: long title cut` → output is 40 title characters ending in `…`
  - `statusline: workbench session, no bead` → no file, `WB_SPACE_ROOT` set prints `◇ no bead`
  - `statusline: not a workbench session` → no file, no `WB_SPACE_ROOT` prints ``
  - `statusline: corrupt file / bad stdin / unsafe id ../x` → prints ``, exit 0
  - `two sessions` → bindings for `s1` and `s2` each show their own bead
  - `focus: binds` → `CLAUDE_CODE_SESSION_ID=s1 WB_SPACE_ROOT=$store wb-focus acme-x1y` prints
    `→ this session is now on x1y Fix fabric PO search`, and the file has `"bead": "acme-x1y"`,
    `"done": false`, `"named": null`
  - `focus: prints` → `wb-focus` prints `acme-x1y Fix fabric PO search`
  - `focus: clear` → `wb-focus --clear` prints `→ unbound`, and the file is gone
  - `focus: unknown bead` → exit 1, stderr contains `acme-nope`, binding unchanged
  - `focus: outside a session` → unset `CLAUDE_CODE_SESSION_ID`: exit 1, stderr says to run it
    inside Claude
  - `focus: claim note in a worktree` → with `WB_WORKTREE=$T/wt` (a git repo on branch `feat/x`),
    `FAKE_BD_LOG` holds `update acme-q9z --append-notes Branch: feat/x (worktree at $T/wt)`
  - `focus: no duplicate note` → a bead whose notes already name `$T/wt` gets no `update`
- [ ] **Step 2:** Run `bash tests/test_wb_session.sh`. Expected: FAIL (the scripts don't exist).
- [ ] **Step 3: Implement** the lib and the two CLIs. Both import the lib through
  `os.path.realpath(__file__)/../lib`, as `wb-backlog` does. Add the file to `tests/run.sh`'s glob
  (automatic) and make the scripts executable.
- [ ] **Step 4:** Run `bash tests/test_wb_session.sh`. Expected: all pass.
- [ ] **Step 5: Commit** (ask first): `feat: session binding, status line segment, wb-focus (wb-7vd.1)`

### Task 2: `wb-session-hook`: settings, SessionStart, UserPromptSubmit, and the command parser

**Files:**
- Create: `bin/wb-session-hook`
- Modify: `lib/wb_session.py` (add the parser)
- Test: `tests/test_session_hook.sh`

**Interfaces:**
- Consumes: Task 1's lib.
- Produces:
  - `parse(cmd: str) -> list[tuple[str, list[str]]]` in the lib. It returns `("claim", ids)`,
    `("close", ids)` or `("create-claim", [])` for each command segment whose first word is `bd`
    (or ends in `/bd`):
    - **claim:** `update` with `--claim`, `--status in_progress`, `--status=in_progress` or
      `-s in_progress`
    - **close:** `close`
    - **create-claim:** `create` with `--claim`

    For `claim` and `close`, the ids are the positional words after the verb, up to the first flag.
    Segments split on `;`, `&&`, `||`, `|` and newlines.
  - `wb-session-hook settings` prints `{"hooks": {...}}` with three events:
    - `SessionStart` (no matcher) runs `<quoted abs path> session-start`
    - `PostToolUse` (matcher `Bash`) runs `… post-tool-use`
    - `UserPromptSubmit` runs `… user-prompt-submit`
  - `wb-session-hook session-start` and `wb-session-hook user-prompt-submit` read hook JSON on
    stdin and print hook JSON or nothing.

- [ ] **Step 1: Write failing tests** (state dir, store and fixtures as in Task 1):
  - **parse:**
    - `bd update acme-x1y --claim` gives `claim [acme-x1y]`
    - `cd /r && bd update acme-x1y acme-q9z --status=in_progress` gives `claim [acme-x1y, acme-q9z]`
    - `bd update acme-x1y -s in_progress`
    - `bd close acme-x1y --reason "done"` gives `close [acme-x1y]`
    - `bd create --title t --claim` gives `create-claim`
    - `bd update acme-x1y --notes x` gives `[]`
    - `bd create --description "then bd close acme-x1y"` gives `[]`
    - `echo "bd update acme-x1y --claim"` gives `[]`

    Test these through a small `python3 -c` call on the lib.
  - **settings:**
    - with `WORKBENCH_HOME` under a path containing a space, the output is valid JSON
    - each command, split with `shlex.split`, starts with the real path to `bin/wb-session-hook`
    - there is no `statusLine` key
  - **session-start:**
    - `bind from WB_BEAD`: stdin `{"session_id":"s1","source":"startup"}` with
      `WB_BEAD=acme-x1y WB_SPACE_ROOT=$store` writes the binding. The output's
      `hookSpecificOutput.additionalContext` contains `acme-x1y`, `Fix fabric PO search`, the
      description, and the sentence starting `Before you start work on a different bead`.
      `sessionTitle` is `x1y Fix fabric PO search`.
    - `re-inject on compact`: an existing binding with `source: compact` gives the same context,
      plus `Acceptance:` and the criteria when the bead has `acceptance_criteria`. There's no
      `sessionTitle` when `named` already equals the title.
    - `description cut`: a 5,000-character description is cut to 1,500 characters in the context.
    - `no bead`: no `WB_BEAD` and no binding prints nothing and writes nothing.
    - `bd hangs`: `FAKE_BD_SLEEP=5` with `WB_BD_TIMEOUT=1` prints nothing, exits 0, and takes
      under 3s.
    - `prune`: a binding file touched 31 days ago is gone after any session-start, and a 29-day
      one stays.
  - **user-prompt-submit:**
    - With `named` null, the output's `sessionTitle` is `x1y Fix fabric PO search`, and `named` is
      saved.
    - Run again, it prints nothing.
    - With no binding, it prints nothing.
  - **junk:** `not json` on stdin for each subcommand exits 0 with no output.
- [ ] **Step 2:** Run `bash tests/test_session_hook.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `parse` and the three subcommands.
  - Output shapes:
    - `{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": …,
      "sessionTitle": …}}`
    - `{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "sessionTitle": …}}`
  - Wrap each subcommand's body in one `try/except Exception: return 0`.
  - Context block wording, kept short:
    ```
    This session serves bead <id>: <title>.
    <description, cut to 1,500>
    Acceptance: <criteria>            (only when present)
    Before you start work on a different bead (claiming it or setting it in progress), ask the user whether to continue in this session or start a fresh one.
    ```
- [ ] **Step 4:** Run `bash tests/test_session_hook.sh`. Expected: all pass.
- [ ] **Step 5: Commit** (ask first): `feat: wb-session-hook settings, session start, prompt title (wb-7vd.1)`

### Task 3: `wb-session-hook post-tool-use`: pick up, switch, close

**Files:**
- Modify: `bin/wb-session-hook`
- Test: `tests/test_session_hook.sh`

**Interfaces:**
- Consumes: `parse`, `show`, `bind`, `note_claim`, `load` and `save` from the lib.
- Produces: `wb-session-hook post-tool-use`, which reads
  `{"session_id", "tool_name", "tool_input": {"command"}, "tool_response": {...}}`.

**Rules:**
- **Which commands count:** only `tool_name == "Bash"` with a non-empty parse, and the response
  must not be an error (`is_error` or `interrupted` true).
- **The root** is the binding's `root`, else `WB_SPACE_ROOT`. With neither, do nothing.
- **Claimed ids:**
  - for `claim`, the parsed ids
  - for `create-claim`, the id from `tool_response.stdout`: either `Created issue: <id>`, or the
    whole stripped stdout when it's a single word (`--silent`)
- **A candidate counts** only if `show()` reports it `in_progress`.
- **No binding:** bind the first candidate, run `note_claim` with `WB_WORKTREE`, and return
  `systemMessage: "→ this session is now on <short> <title>"`. Append
  ` (claim note not written: <err>)` on a note failure.
- **Bound, the candidate is the bound bead, and not `done`:** nothing.
- **Bound to another bead, or `done`:** for the first candidate that differs (or any candidate when
  done), return
  `systemMessage: "→ claimed <short Y> while this session is on <short X>"` plus `additionalContext`:
  ```
  You just claimed <Y>: <title Y>, but this session is on <X>: <title X>[, which is closed].
  Before working on <Y>, ask the user: continue in this session (then run `wb-focus <Y>`), or start fresh (run `bd update <Y> --status open` and tell them to start <Y> from the workbench launcher in a new tab)[; starting fresh is recommended, since this session's bead is done].
  ```
  Nothing is written to the binding.
- **Close:** if the bound bead's id is among the ids and `show()` reports it `closed`, set
  `done: true` and save. Return `systemMessage: "✓ <short> closed · this session is done"` plus
  `additionalContext`:
  ```
  This session's bead <X> is closed, so the session's work is done. Finish the close-out (in a worktree space, run end-session once the work is merged or pushed), then tell the user to type /exit and start the next bead from the workbench launcher.
  ```
- **Output shape:** `{"systemMessage": …, "hookSpecificOutput": {"hookEventName": "PostToolUse",
  "additionalContext": …}}`.

- [ ] **Step 1: Write failing tests:**
  - `pick up`: no binding, `WB_SPACE_ROOT=$store`, and the command `bd update acme-x1y --claim`
    with the bead in_progress. The output's systemMessage is
    `→ this session is now on x1y Fix fabric PO search`, and the binding is written.
  - `pick up writes the claim note`: as above with `WB_WORKTREE=$T/wt` on `feat/x` puts the note in
    `FAKE_BD_LOG`.
  - `pick up from create --claim`: stdout `acme-q9z` from `bd create --silent --claim …` binds
    `acme-q9z`.
  - `same bead`: bound to `acme-x1y`, a claim of `acme-x1y` prints nothing.
  - `switch asks`: bound to `acme-x1y`, a claim of `acme-q9z` (in_progress). The systemMessage is
    `→ claimed q9z while this session is on x1y`, the context contains `wb-focus acme-q9z` and
    `bd update acme-q9z --status open`, and the binding is unchanged.
  - `claim that didn't take`: `acme-q9z` still open in fake.json prints nothing.
  - `close marks done`: bound `acme-x1y`, the command `bd close acme-x1y`, with fake.json showing
    it closed. The systemMessage is `✓ x1y closed · this session is done`, the context contains
    `/exit`, and the binding has `done: true`.
  - `close refused`: the fake still shows it in_progress. Nothing is printed, and `done` stays
    false.
  - `close of another bead`: `bd close acme-q9z` prints nothing.
  - `claim after done`: the context contains `starting fresh is recommended`.
  - `failed tool`: `tool_response.is_error: true` prints nothing.
  - `bd create without --claim`: prints nothing.
  - `bd hangs`: as in Task 2.
- [ ] **Step 2:** Run the tests. Expected: the new cases FAIL.
- [ ] **Step 3: Implement** `post-tool-use` to the rules above.
- [ ] **Step 4:** Run `bash tests/test_session_hook.sh`. Expected: all pass.
- [ ] **Step 5: Commit** (ask first): `feat: session hook picks up, asks on switch, closes out (wb-7vd.1)`

### Task 4: `wb-backlog claimed` prefers the most recently updated bead

**Files:**
- Modify: `bin/wb-backlog` (`cmd_claimed`, near line 163)
- Test: `tests/test_wb_backlog.sh`

**Interfaces:**
- Produces: `wb-backlog claimed ROOT PATH`, which still prints one id or exits 1. Among beads whose
  current claim note names PATH, it prints the one with the greatest `updated_at`. A missing
  `updated_at` sorts as oldest, and a tie keeps list order.

- [ ] **Step 1: Write the failing test** `claimed: two beads name the worktree, the newest update
  wins`. The fake bd stdout has `bee-old` (`updated_at` `2026-10-01T…Z`) and `bee-new`
  (`2026-10-20T…Z`), both with notes naming `/x/wt`, listed old first. Assert the output is
  `bee-new`.
- [ ] **Step 2:** Run `bash tests/test_wb_backlog.sh`. Expected: that case FAILS (it prints
  `bee-old`).
- [ ] **Step 3: Implement** the choice with `max(…, key=…)` over the matches. Update the usage
  docstring line for `claimed`.
- [ ] **Step 4:** Run `bash tests/test_wb_backlog.sh` and `bash tests/test_end_session.sh`.
  Expected: all pass.
- [ ] **Step 5: Commit** (ask first): `fix: wb-backlog claimed prefers the bead noted last (wb-7vd.1)`

### Task 5: Launch with the hooks: launcher and `new-session`

**Files:**
- Modify: `shell/workbench.zsh` (`_wb_claude` and its three callers), `bin/new-session` (the
  launch block near line 172)
- Test: `tests/test_handoff.sh`, `tests/test_new_session.sh`

**Interfaces:**
- Consumes: `wb-session-hook settings` from Task 2.
- Produces:
  - **`_wb_claude MODE TEXT BEAD`**, where MODE is `prompt` or `continue` and BEAD is an id or
    `-`. The `env` part becomes
    `env [CLAUDE_CONFIG_DIR=…|-u CLAUDE_CONFIG_DIR] WB_SPACE_ROOT=$s[3] [WB_BEAD=<id>] [WB_WORKTREE=<top>]`.
    - `WB_WORKTREE` is `git rev-parse --show-toplevel` of `$PWD`, and only when `$s[5] == 1`.
    - `--settings <json>` goes right after `claude`.
  - **Callers:**
    - `_wb_start_bead` passes its id
    - `_wb_start_new` passes `-`
    - `_wb_start_claimed`'s resume passes its id
  - **`new-session`, launching itself,** adds `WB_SPACE_ROOT=$S_ROOT`, `WB_WORKTREE=$WORKTREE`,
    `WB_BEAD=$BEAD` (only when set) and `--settings`.
  - **If `wb-session-hook settings` fails,** launch without `--settings`. Losing awareness must
    not stop a session.

- [ ] **Step 1: Write failing tests:**
  - **`test_handoff.sh`:**
    - `plain bead: env and hooks` → the DRY-RUN line contains `WB_SPACE_ROOT=`, `WB_BEAD=bee-1`
      and `--settings`, but not `WB_WORKTREE=`
    - `something new: no WB_BEAD` → contains `WB_SPACE_ROOT=` and not `WB_BEAD=`
    - `worktree bead: WB_WORKTREE` → contains `WB_WORKTREE=$T/wt`, where the fake new-session's
      dir is a git repo top. Make `FAKE_NS_DIR` a `git init` repo, or assert on the toplevel the
      test computes.
    - `◐ resume: WB_BEAD` → contains `WB_BEAD=acme-c2` and `--continue`
  - **`test_new_session.sh` dry run:** contains `WB_BEAD=acme-…`, `WB_WORKTREE=<worktree>` and
    `--settings`.
  - **Existing exact-match DRY-RUN assertions** (for example lines 86, 128 and 190) are updated to
    the new prefix. They keep checking the account and permission parts.
- [ ] **Step 2:** Run `bash tests/test_handoff.sh; bash tests/test_new_session.sh; bash tests/test_launch.sh`.
  Expected: the new cases FAIL.
- [ ] **Step 3: Implement.** `_wb_claude` gets the JSON with
  `$WORKBENCH_HOME/bin/wb-session-hook settings`, and new-session with
  `$WB_HOME/bin/wb-session-hook settings`. Keep CLAUDE_CONFIG_DIR's "this command only, never
  exported" behaviour for the new variables, and say so in the existing comment.
- [ ] **Step 4:** Run `tests/run.sh`. Expected: every file passes.
- [ ] **Step 5: Commit** (ask first): `feat: launcher and new-session start Claude with the session hooks (wb-7vd.1)`

### Task 6: Docs, and the checks that need a real session

**Files:**
- Modify: `README.md`, `docs/specs/2026-10-21-session-bead-design.md` (status line), `CLAUDE.md`
  (architecture list: the three new bin files)

- [ ] **Step 1: README.** Add a short section, "While you work". Say what the status line shows
  and how to wire `wb-statusline-bead` into your own status line, with a two-line example:
  ```bash
  bead=$(printf '%s' "$input" | wb-statusline-bead)
  printf '%s %s\n' "$bead" "$rest_of_your_line"
  ```
  Add the "continue here or start fresh" ask, the close-out, `wb-focus`, and that a plain `claude`
  is unchanged.
- [ ] **Step 2: Spec.** Set the status to `shipped` once Step 3 passes, and keep the text in step
  with anything that changed in the build.
- [ ] **Step 3: Interactive checks, by hand, reported to the user with what was seen:**
  1. Start a bead from the launcher. The status line shows `◆ …` once it's wired in, and
     `wb-focus` prints the bead.
  2. Run `/compact`, then ask "what is this session for?". Claude names the bead without looking.
  3. Claim a second bead. Claude asks "continue or start fresh" before working on it in the same
     turn. If the ask only comes a turn later, PostToolUse context isn't read in the same turn:
     move the ask into the next `user-prompt-submit` (the spec's fallback) and add a test.
  4. Close the bead. You see `✓ … closed · this session is done`, and Claude says to `/exit`.
  5. A plain `claude` started by hand shows nothing new.
- [ ] **Step 4:** Run `tests/run.sh` and `scripts/check-leaks.sh`. Expected: all pass, and
  `check-leaks: clean`.
- [ ] **Step 5: Commit** (ask first): `docs: while you work: the session's bead (wb-7vd.1)`. Then
  close wb-7vd.1 with what shipped and what didn't.
