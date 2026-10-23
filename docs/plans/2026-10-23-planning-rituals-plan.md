# Planning Rituals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Weekly unattended grooming that sets each planned space's NOW/NEXT, ices what no longer
earns its place and flags what demands attention, with a review and a monthly strategy session
offered by the launcher, and critical work never hidden behind the three start-here picks.

**Architecture:**
- **Milestone A (launcher, stands alone):** `wb-backlog` learns the `attention` label and caps
  fresh claims at one pick; `wb-ui` shows attention beads first under start-here, uncapped to 5
  plus a `+N more` line; screen 1 says `! N need attention`.
- **Milestone B (`wb-groom` core):** `lib/wb_groom.py` holds the plan reader and the policy (pure
  functions: decisions in, operations and proposals out). `bin/wb-groom` runs the judge
  (`claude -p`, read-only, narrow settings) and the applier (bd writes with a before-record and undo).
- **Milestone C (rituals in the launcher):** `wb-groom status` feeds screen 1 and two new rows on
  the work screen that start a review or strategy session; `install.sh` installs a launchd agent.

**Tech Stack:** python 3.11+ standard library; zsh launcher; bash 3.2 tests with fakes; launchd.

**Spec:** `docs/specs/2026-10-23-planning-rituals-design.md`

## Global Constraints

- Nothing private in the repo: examples use Acme; run `scripts/check-leaks.sh` before every commit.
  Never stage `.beads/interactions.jsonl` until its private names are cleaned (open item).
- Shell targets macOS bash 3.2 / zsh; python 3.11+ (`tomllib`), stdlib only.
- Every behaviour change starts with a failing test (`tests/test_*.sh`, asserts in `tests/lib.sh`).
- Fail closed: a step that can't tell whether a change is safe doesn't make it and says why.
- Plan directory: `$WB_PLANS_DIR/<space label>/` (default `~/.config/workbench/plans`).
- Run records: `$WB_GROOM_DIR/<space label>/<run-id>/` (default `~/.local/state/workbench/groom`);
  run-id is `YYYYMMDD-HHMM` local time.
- Sprint sizes default NOW 5, NEXT 8; attention list shows 5 before `+N more need attention`.
- `attention` flags: due within 14 days, neglected protected bead, or a blocker in front of either.
- Plan is stale when `goals.md`'s date is over 45 days old; strategy is due at 30+ days.
- Judge timeout 20 minutes; a timed-out run applies nothing.
- Schedule: Saturday 06:00 local, weekly.
- bd writes from `wb-groom` always pass `--sandbox` (no Dolt auto-push).

## Review Focus

1. A judge that writes malformed or partial `decisions.json` (truncated, wrong types, unknown ids):
   apply must drop what it can't validate, apply nothing if the file doesn't parse, and say so.
2. A bead edited by the user between the run and `undo`: undo refuses that bead and names it.
3. Text from beads reaching the judge prompt or notes (tabs, newlines, `$(...)`): notes are
   passed as one argv element, never through a shell.
4. Two runs overlapping (launchd at wake plus a manual `run`): a lock per space; the second exits
   saying a run is in progress.
5. A space whose bd store is missing or unreadable at run time: the run records the failure in
   `summary.md`, applies nothing, and `--all` carries on with the next space.

Each has its test in the task that owns the code (Tasks 3, 4, 5).

---

### Task 1: `wb-backlog` — attention beads and one fresh claim in the picks

**Files:**
- Modify: `bin/wb-backlog` (`picks()`, `cmd_list`, `cmd_summary`, docstring)
- Modify: `tests/test_wb_backlog.sh`

**Interfaces:**
- Produces: `list` field 12 = `"<n> <reason>"` for attention beads (n from 1, ordered by priority
  then id), `-` otherwise. Reason = text after the last notes line matching
  `^attention: (.+)$`, else `attention`. Attention beads are listed whatever their section
  (icebox included) and are never also picks. Summary starts with `! N need attention · ` when N > 0.
- `picks()` now admits at most one fresh-claim bead (the best-ranked one); the rest rank as before.

- [ ] **Step 1: Write failing tests** in `tests/test_wb_backlog.sh`:
  - `attention: field 12 ranks flagged beads by priority, reason from the last attention note`
    — fixture with `att-1` (P2, labels `["attention"]`, notes `"x\nattention: due Nov 2 · money"`),
    `att-2` (P1, `attention`, no notes), `att-3` (iced + `attention`); assert `cut -f1,12` gives
    `att-2:1 attention`, `att-1:2 due Nov 2 · money`, `att-3:3 attention`, others `-`.
  - `attention: never also a pick` — no id has both field 11 and field 12 set.
  - `picks: at most one fresh claim` — 4 fresh claims P1 + 2 open P2 beads → field 11 shows one
    `resume` and two non-claims.
  - `summary: attention first` → `! 2 need attention · open …`.
  - Update the hostile-title row count to `1:12`.
- [ ] **Step 2: Run** `bash tests/test_wb_backlog.sh` — the new asserts FAIL.
- [ ] **Step 3: Implement** `attention(beads) -> dict[str, str]` beside `picks()`; drop the
  `ICEBOX` exclusion for attention only; in `picks()`, after sorting, keep the first resume and
  skip later ones.
- [ ] **Step 4: Run** `bash tests/test_wb_backlog.sh` — `0 failed`.
- [ ] **Step 5: Commit** `feat: attention beads and one fresh claim in the picks (wb-7vd.6)`

### Task 2: `wb-ui` — attention first under start-here

**Files:**
- Modify: `bin/wb-ui` (`print_work`, `print_row` unpack of 12 fields)
- Modify: `tests/test_launch.sh`, `docs/specs/2026-10-16-launcher-design.md`, `README.md`

**Interfaces:**
- Consumes: Task 1's field 12.
- Produces: under `── start here ──`, attention rows first (reason dim, prefixed `! `), at most
  5, then `msg … +N more need attention` when more; then picks; then the flow line. Start-here
  shows whenever there is any attention bead, even in a backlog of 3 or fewer.

- [ ] **Step 1: Write failing tests** in `tests/test_launch.sh` with a 7-attention-bead store:
  `render-work: attention first, five then a count` (rows 3-7 are attention ids in rank order,
  row 8 is `msg` with `+2 more need attention`), `render-work: attention reason dim with !`
  (`$'\e[2m! due Nov 2 · money\e[0m'`), `render-work: attention shown in a tiny backlog`.
- [ ] **Step 2: Run** `bash tests/test_launch.sh` — FAIL.
- [ ] **Step 3: Implement** in `print_work`; `print_row(r, pats, layout, why=None)` keeps its
  signature (why text passed in, `! ` prefix added by the caller).
- [ ] **Step 4: Run** `tests/run.sh` — all pass. Update the launcher spec's Start-here bullet and
  README to match (one bullet each).
- [ ] **Step 5: Commit** `feat: the work screen shows critical work first, uncapped (wb-7vd.6)`

### Task 3: `lib/wb_groom.py` — the plan and the policy

**Files:**
- Create: `lib/wb_groom.py`, `bin/wb-groom` (subcommand `ops` only in this task)
- Create: `tests/test_wb_groom.sh`, `tests/fixtures/groom/` (plan dir, `decisions.json`, bead JSON)

**Interfaces:**
- Produces:
  - `load_plan(space: str) -> Plan` — dataclass `Plan(dir, goals_date: date|None, now_size=5,
    next_size=8, protected_labels: set[str])`. `goals.md` line `date: YYYY-MM-DD` and optional
    `sprint: now=N next=M`; `protected.md` line `labels: a, b`. Missing dir → `None`.
  - `plan_state(plan, today) -> "missing"|"stale"|"ok"|"due"` (`due` = 30-45 days, still applies).
  - `is_protected(bead: dict, decision_protected: bool|None, plan) -> bool` — label ∨ judge says
    true ∨ judge says None/unsure.
  - `plan_ops(decisions: dict, beads: dict[str, dict], plan) -> (ops: list[Op], proposals:
    list[dict], dropped: list[str])`. `Op(id, kind: "wave"|"unwave"|"icebox"|"attention"|
    "unattention", value: str, why: str)`.
- CLI: `wb-groom ops RUN_DIR SPACE_ROOT` prints ops as TSV `id kind value why`, then
  `proposal\t…` and `dropped\t…` lines; reads beads with `bd list -n 0 --json` in SPACE_ROOT.

Policy (from the spec, exactly):
- Sprint → `wave:1`/`wave:2` add for beads named, `unwave` for current wave beads not named;
  claimed beads are skipped both ways and don't count toward size; an `unwave` on a protected bead
  becomes a proposal; extra names past size are dropped (`over size`).
- `icebox` applied only for unprotected; otherwise proposal. `priority`, `merge`, `close`,
  `undefer`, `dep`, `date` → always proposals. `attention` add/remove → always applied.
- Ids not in `beads` → `dropped` with reason. Claimed beads: any change → dropped (`claimed`).
- `plan_state` `missing` or `stale` → every op becomes a proposal.

- [ ] **Step 1: Write failing tests**, one assert each: protected by label; protected when judge
  unsure; unprotected only when judge says false and no label; icebox protected → proposal;
  priority → proposal; claimed → dropped; unknown id → dropped; unwave protected → proposal;
  sprint over size → dropped; stale plan → no ops, all proposals; malformed decisions.json →
  exit 3, `decisions.json unreadable` on stderr, no output (Review Focus 1); wrong-typed field
  (e.g. `"now": "acme-1"`) → that section dropped, rest kept.
- [ ] **Step 2: Run** `bash tests/test_wb_groom.sh` — FAIL.
- [ ] **Step 3: Implement** the functions above; `bin/wb-groom` follows `wb-backlog`'s
  `sys.path` + `realpath` pattern to import the lib.
- [ ] **Step 4: Run** — pass.
- [ ] **Step 5: Commit** `feat: wb-groom's plan reader and policy (wb-7vd.6)`

### Task 4: `wb-groom apply` and `undo`

**Files:**
- Modify: `bin/wb-groom`, `lib/wb_groom.py`, `tests/fake/bd` (record writes under `FAKE_BD_LOG`;
  `show` already supported), `tests/test_wb_groom.sh`

**Interfaces:**
- Consumes: `plan_ops`.
- Produces:
  - `wb-groom apply RUN_DIR SPACE_ROOT` — writes `before.jsonl` (one line per touched bead:
    id, labels, priority, status, notes, updated_at) with `fsync`, then per op one
    `bd --sandbox update ID --add-label/--remove-label … --append-notes "groomed YYYY-MM-DD: <kind> — <why>"`
    (attention ops also append `attention: <why>`), argv list, no shell. Writes `applied.jsonl`,
    `proposals.json`. Exit 0; non-zero with nothing applied if `before.jsonl` can't be written.
  - `wb-groom apply RUN_DIR SPACE_ROOT --proposal N` — applies proposal N (review only; user's yes
    is the confirmation), recording its before-state the same way.
  - `wb-groom undo RUN_DIR [ID]` — restores labels/priority/status from `before.jsonl` and appends
    `groomed undo: <run-id>`; refuses a bead whose current `updated_at` is later than the run's
    own write (Review Focus 2), printing `ID changed since the run; not undone`.

- [ ] **Step 1: Write failing tests:** apply writes `before.jsonl` before the first bd write
  (order in `FAKE_BD_LOG`); every write has `--sandbox`; unwritable run dir → nothing applied,
  exit 4; a hostile `why` with `$(touch …)` and a newline lands as one argv element and executes
  nothing (Review Focus 3); undo restores labels; undo refuses a bead changed after the run;
  `--proposal 2` applies only proposal 2.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `tests/run.sh` — pass.
- [ ] **Step 5: Commit** `feat: wb-groom applies with a before-record and undoes exactly (wb-7vd.6)`

### Task 5: `wb-groom run` — the judge

**Files:**
- Modify: `bin/wb-groom`, `tests/fake/claude` (with `FAKE_CLAUDE_GROOM=<dir>`, copy that dir's
  `decisions.json` and `summary.md` into the `--add-dir` run dir named in its args; log args to
  `FAKE_CLAUDE_LOG`; `FAKE_CLAUDE_SLEEP` to test the timeout), `tests/test_wb_groom.sh`
- Create: `prompts/groom.txt` (from the dry-run prototype, with the raise/propose contradiction
  removed, the `decisions.json` schema from the spec, the attention rules, and the four plan inputs)

**Interfaces:**
- Produces: `wb-groom run SPACE` and `wb-groom run --all` (spaces from `wb-spaces` whose plan dir
  exists). Per space: lock `$WB_GROOM_DIR/<space>/.lock` (Review Focus 4); make the run dir; write
  `inputs.json` (plan file hashes, plan state); run the judge; then `apply` unless the judge
  failed, timed out, or left no `decisions.json` — in which case `summary.md` says why and nothing
  is applied (Review Focus 5). `--all` continues past a failed space and exits non-zero at the end
  if any failed.
  `wb-groom` appends two lines to the judge's `summary.md` itself: `N earlier runs not yet reviewed`
  when any are, and `This store syncs to a shared remote: changes go out with your next sync` when
  the space's git remote has `refs/dolt/data` (checked with `git ls-remote`, 5 s timeout; skipped
  on failure).
- Judge command (verify flags against `claude --help` on this Mac before coding; if the narrow
  form can't authenticate, fail closed — don't widen):
  `env CLAUDE_CONFIG_DIR=<space claude_config or unset> claude -p --setting-sources "" --strict-mcp-config --permission-mode dontAsk --settings <generated groom-settings.json> --allowedTools "Bash(bd --readonly list:*)" "Bash(bd --readonly show:*)" "Bash(bd --readonly ready:*)" "Bash(bd --readonly dep tree:*)" "Bash(bd --readonly children:*)" Read Write --add-dir <run dir> <plan dir> "<prompt>"`
  run in the space root; `groom-settings.json` denies Write outside the run dir, Edit, WebFetch,
  WebSearch, and all other Bash.

- [ ] **Step 1: Verify the judge flags by hand** on a throwaway space: a run with the command
  above can read beads, can write only to the run dir, and a prompted `git log` is refused. Record
  the working flag set in the code comment. If `--setting-sources ""` is rejected, find the
  narrowest accepted form and note it in the spec.
- [ ] **Step 2: Write failing tests:** fake judge output → applied ops in `FAKE_BD_LOG`; judge
  args contain `--setting-sources` and no `--dangerously-skip-permissions`; missing plan → no
  bd writes, summary leads `strategy session needed`; timeout (`WB_GROOM_TIMEOUT=1`,
  `FAKE_CLAUDE_SLEEP=3`) → nothing applied; a held lock → second run exits 5 with
  `a grooming run is in progress`; `--all` with one broken store → other space still applied, exit 1.
- [ ] **Step 3: Run** — FAIL. **Step 4: Implement.** **Step 5: Run** `tests/run.sh` — pass.
- [ ] **Step 6: Live dry check:** `WB_GROOM_DIR=<scratch> wb-groom run <small space>` with a plan
  dir in scratch, then `wb-groom undo` the run; confirm with `bd show` that every touched bead is
  back. Report the outcome.
- [ ] **Step 7: Commit** `feat: wb-groom run judges read-only and applies by policy (wb-7vd.6)`

### Task 6: Review and strategy in the launcher

**Files:**
- Modify: `bin/wb-groom` (`status`, `reviewed`, `strategy`), `bin/wb-ui` (`fill-counts`,
  `render-work`), `shell/workbench.zsh` (`_wb_main` cases, `_wb_prompt` `{run}` / `{plan}`),
  `tests/test_wb_groom.sh`, `tests/test_launch.sh`
- Create: `prompts/review.txt`, `prompts/strategy.txt`, `lib/plan-templates/{goals,protected,calendar,sources}.md`

**Interfaces:**
- `wb-groom status SPACE` prints zero or more lines: `review\t<run dir>\t<Sat>` for the newest
  unreviewed run (plus `\t<k> waiting` when more), `strategy\tdue` when plan state is `due`,
  `stale` or `missing`-with-runs. Exit 0 always.
- `wb-groom reviewed RUN_DIR` marks it reviewed (`reviewed` file with the date).
- `wb-groom strategy SPACE` creates the plan dir from `lib/plan-templates/` if absent and prints its path.
- Screen 1: the summary line gets ` · groomed Sat · review` and/or ` · strategy due`, dim.
- Work screen: rows `review\t-\t<run dir>\t\t✦ review Saturday's grooming` and
  `strategy\t-\t<plan dir>\t\t✦ strategy session` after `✦ something new`; `_wb_main` handles
  kinds `review` and `strategy`: `cd` to the space root and `_wb_claude prompt` with the
  matching prompt (`{run}`, `{plan}` substituted), bead `-`.
- `review.txt` walks the spec's order (calendar due soon, sprint, protected proposals, other
  proposals, release?, candidates, questions), applies with `wb-groom apply --proposal` / `undo`,
  creates accepted candidates with `bd create`, ends with `wb-groom reviewed`.
  `strategy.txt` prepares from the last month's closes by area, the flow, reviewed runs'
  questions/process notes and reversals, and the calendar; rewrites the plan files with the user.

- [ ] **Step 1: Write failing tests:** `status` lines for unreviewed / reviewed / due / missing;
  `strategy` creates the dir once and is idempotent; render-work shows the review row only with an
  unreviewed run; choosing it in the menu fallback prints a DRY-RUN with `review.txt`'s first line
  and the run dir.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `tests/run.sh` — pass.
- [ ] **Step 5: Commit** `feat: review and strategy sessions from the launcher (wb-7vd.6)`

### Task 7: The weekly schedule

**Files:**
- Modify: `install.sh`, `tests/test_install.sh`, `README.md`,
  `docs/specs/2026-10-23-planning-rituals-design.md` (status → built)
- Create: `lib/launchd/workbench.groom.plist.in`

**Interfaces:**
- `install.sh` writes `~/Library/LaunchAgents/<label>.workbench.groom.plist` (label from the
  existing install naming; `StartCalendarInterval` Weekday 6, Hour 6, Minute 0; runs
  `~/.local/bin/wb-groom run --all`; stdout/stderr to `$WB_GROOM_DIR/launchd.log`) and
  `launchctl bootstrap`s it; re-running replaces it; `install.sh --no-schedule` skips it. Under
  tests (`WORKBENCH_DRY_RUN=1`) it prints the launchctl command instead of running it.

- [ ] **Step 1: Write failing tests** in `tests/test_install.sh`: plist written with Weekday 6 /
  Hour 6; `--no-schedule` writes none; dry run prints `launchctl bootstrap gui/…`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `tests/run.sh` — pass.
- [ ] **Step 5:** README section "Planning rituals" (what runs when, where plans live, how to
  review, undo, and start a space with `wb-groom strategy <space>`); spec status → built.
- [ ] **Step 6: Commit** `feat: weekly grooming runs from launchd (wb-7vd.6)`
