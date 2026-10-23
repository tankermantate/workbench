# Planning rituals: monthly strategy, weekly grooming, review in the launcher

**Status:** approved 2026-10-23, not yet planned · **Date:** 2026-10-23 · bead wb-7vd.6 (epic wb-7vd: workbench
through the whole life of the work, not just the start)

## Why

A busy space's backlog stops telling you what matters. In the largest space on this Mac, 2026-10-23:
362 live beads, 244 created and 170 closed in 30 days, 164 of 282 non-icebox beads at P2, a NOW
list (`wave:1`) whose 8 beads were last touched a month ago, and 32 deferred beads past their
date and visible nowhere. The start-here picks (wb-7vd.5) rank what the backlog says; nothing
keeps what the backlog says true.

What the user said:
- **High judgement, not rules.** Work on the most important problems, eradicate what impedes the
  work, make the product more useful to the business; and **surface good ideas** buried in the
  backlog as candidates for new work.
- It is **automating the standard planning rituals** (PDLC/SDLC: strategic planning,
  prioritization, grooming). **Strategy monthly, with the user; grooming weekly**, by itself.
- It acts, then leaves **a summary to review, in the launcher, when a terminal opens**.
- **What would destroy trust:** shelving or demoting anything touching **money, legal,
  compliance, customer satisfaction or production**, or a call that makes the user miss a
  compliance or legal matter.
- It must **work in the abstract**, for any space and domain: a production business app today, a
  household finance plan next, others as they grow.

A read-only dry run of the grooming prompt (2026-10-23, two very different spaces) found: hard
dates (a payment window, a promised delivery, a login expiry, tax deadlines) were the strongest
signal in both and had no home in the backlog; a stale NOW list; ~10 merge/close candidates;
effort drifting from the plan's stated order (routed to strategy, correctly). It also found the
prompt alone did not keep a run read-only (one run ran `git log`), which shapes the safety design
below.

## The three rituals

| Ritual | Cadence | Who | Produces |
|---|---|---|---|
| **Strategy** | monthly | user + Claude, in a session | the space's plan: goals, protected areas, calendar, sources |
| **Grooming** | weekly | Claude, unattended | a run: applied changes, proposals, candidates, a summary |
| **Review** | after each grooming run | user + Claude, in a session | accepted / reversed changes, approved proposals, new beads |

The start-here picks and the NOW/NEXT sections on the work screen are where the result shows up
day to day.

## The plan (one per space, private)

Everything domain-specific lives in a private **plan directory** per space, under
`~/.config/workbench/plans/<space>/`, never in this repo. A space takes part when its plan
directory exists (no new `spaces.toml` field needed; the builder may add one if cleaner). Four
inputs, all plain markdown so the user can edit them by hand:

1. **`goals.md`** — 3-5 current goals in the user's words, the date set, and what's explicitly
   not a goal this month. Example (made up): *"Acme: 1. Invoices match the books. 2. Every order
   ships by its promised date. …"*
2. **`protected.md`** — the protected areas and how to recognise them: labels that mark them for
   certain (e.g. `ws:money`), plus words for judgement ("anything a customer would notice").
3. **`calendar.md`** — dated obligations: payments, filings, renewals, promised dates, with what
   they touch. Grooming reads it and also adds dates it finds in beads (as proposals).
4. **`sources.md`** — what else to read: docs in the repo (the space's `protocol` file is read by
   default), and anything outside it. A source grooming can't read is reported, not skipped silently.

A **missing or stale plan fails closed**: with no `goals.md`, or one older than 45 days, grooming
still runs but applies nothing, infers goals (marked INFERRED), and its summary leads with
"strategy session needed".

## Grooming (weekly, unattended)

### Two halves: Claude judges, workbench applies

Claude never writes to the bead store. Each run has two halves:

1. **Judge** — `claude -p` with the space's Claude account, the grooming prompt
   (`prompts/groom.txt`), the plan, and a **tool allowlist enforced by Claude Code settings**, not
   by the prompt: read-only bd (`list`, `show`, `ready`, `dep tree`, `children`), Read inside the
   space root and the plan directory, Write only to the run directory. No git, no network, no edits.
   The run uses the space's config only for its account and auth; it **ignores that config's own
   settings and permission rules** (they could widen the allowlist). If the run can't be started
   that narrowly, it doesn't start (*my call*).
   It writes `decisions.json` (structured, below) and `summary.md` (for the human).
2. **Apply** — `wb-groom apply` (python, in this repo) validates `decisions.json` and applies only
   what policy allows, through bd. **A bead is protected if any of these hold**: it carries a
   protected label from `protected.md` (checked by `apply` itself); the judge says it is protected;
   the judge says it is unsure. Only a bead with no protected label that the judge positively calls
   unprotected is treated as unprotected (*my call*, from "when unsure, treat it as protected").
   A decision naming a bead `apply` can't find or read is dropped and reported.

### What it may change by itself

- **NOW and NEXT**: sets the `wave:1` / `wave:2` labels to a fixed-size sprint (default 5 and 8, per
  space in the plan). Beads leaving the sprint lose the wave label. This is "re-ranking".
  A **protected** bead leaving NOW/NEXT is a proposal: it keeps its label until review, so the
  sprint can run over size by those beads. **Claimed** beads keep whatever wave they have and don't
  count toward the size (they're work in hand). (*My calls.*)
- **Icebox** a non-protected bead that no longer earns its place.
- **A note on every bead it changes**: `groomed <date>: <change> — <why, tied to a goal>`.

### What it only proposes (applied in review)

- Any change to a **protected** bead other than *adding* it to NOW/NEXT.
- **Priority changes**, all of them (*my call*: unattended raises would inflate priority, and the
  sprint labels already carry "do this now").
- Merges, closes, un-deferring, new dependencies, dates for the calendar.
- **Candidates**: new beads it thinks should exist, or buried ones worth reviving.

### What it never touches

Claimed (in-progress) beads — it lists claims untouched 14+ days under **Release?**. Closed beads.
Anything outside the space's bead store. Code and git.

### The run record and undo

`apply` runs bd with auto-push off (bd's `--sandbox` flag disables Dolt auto-push; builder to
confirm it has no other effect), so applied changes stay local until the user syncs.

Each run lives in `~/.local/state/workbench/groom/<space>/<run-id>/`: inputs' hashes, `decisions.json`,
`summary.md`, and `before.jsonl` — each touched bead's labels, priority, status and notes **before**
the change, written and synced to disk before the first bd write. If `before.jsonl` can't be
written, the run applies nothing. `wb-groom undo <run> [<bead>]` restores from it, and refuses
(saying why) when a bead has changed since the run.

### Shared stores

A space's bead store may sync to a shared remote, so applied changes reach anyone else who reads
it. Grooming doesn't sync or push; the change goes out with the user's next sync. The summary says
so when the space has a remote. (*Builder:* confirm bd doesn't auto-push on write.)

### Schedule

A launchd agent (`~/Library/LaunchAgents/…workbench.groom.plist`, installed by `install.sh`) runs
`wb-groom run --all` weekly, Saturday 06:00 (*my call*). A Mac asleep then runs it at wake. One run
per space per week; a run that times out (default 20 min) applies nothing. Cost seen in the dry
run: ~6 min / ~160k tokens for a 400-bead space, ~2 min for a 50-bead one.

### `decisions.json` (shape; builder may refine)

```json
{"goals": [{"text": "...", "inferred": true}],
 "sprint": {"now": [{"id": "acme-12", "why": "..."}], "next": [...]},
 "changes": [{"id": "acme-40", "kind": "icebox|priority|merge|close|undefer|dep|date",
              "to": "...", "why": "...", "protected": false}],
 "release": [{"id": "...", "idle_days": 30}],
 "candidates": [{"title": "...", "why": "...", "from": ["acme-7"]}],
 "questions": ["..."], "process_notes": ["..."]}
```

## Review (in the launcher)

- Screen 1 adds to the space's line: `groomed Sat · review` while a run is unreviewed, and
  `strategy due` once goals are 30+ days old. (Both dim, after the counts.)
- The work screen gets a row at the top: `✦ review Saturday's grooming` (and `✦ strategy session`
  when due). Choosing it starts Claude in the space with `prompts/review.txt` and the run directory.
- The user's yes in the review conversation is enough for Claude to apply any item, protected ones
  included (user's call, 2026-10-23); `wb-groom` doesn't ask again on the terminal.
- Claude walks the summary in this order: what's due soon (calendar), the new sprint, proposals on
  protected beads, other proposals, release?, candidates, questions. The user accepts, reverses or
  edits each; Claude applies through `wb-groom` (`undo`, `apply --proposal <n>`) so every change
  still goes through the policy and the run record. Candidates the user accepts become beads.
- Finishing the review marks the run reviewed. An unreviewed run doesn't block the next one; the
  next summary says how many runs are waiting.

## Nothing critical out of sight

The user: *"My goal is to not have blinders on to critical work. If there is work that demands
attention that is falling outside of the 3 slots, then we need to adjust the design."* So the
work screen gets a place for critical work that isn't bounded by the three picks:

- **Grooming flags what demands attention** with a `attention` label and a note saying why:
  something due within 14 days on the calendar or in a bead, a protected bead that has been
  neglected, a blocker in front of either. Adding the label is applied unattended (it only ever
  raises), and removing it is too, once the reason is gone (closed, date passed, done). The user
  can add or remove it by hand.
- **Start-here shows those first, uncapped**: under `── start here ──`, every `attention` bead,
  most urgent first, each with its reason dim (`due Nov 2 · money`). Past five, the fifth row is
  followed by `+N more need attention` and the rest are in the search (`attention`). Then the three
  picks as now.
- **The picks hold at most one fresh claim**, so the other two come from NOW and the ranking: in a
  space with many claims, the sprint grooming set still reaches start-here (*my call*; this changes
  wb-7vd.5's resume-first rule).
- Screen 1 adds `! 3 need attention` to the space's line when any are flagged, so it shows before
  the space is opened.

## Strategy (monthly, with the user)

Offered by the launcher when due (above), or any time with `wb-groom strategy <space>`, which
also **starts a space**: it creates the plan directory the first time (*my call*; spaces without one
show nothing new on screen 1). Claude
starts prepared: the last month's closes by area, the 30-day flow, the reviewed runs' questions and
process notes, what's been reversed in review (where grooming's judgement was off), and the
calendar ahead. With the user it rewrites `goals.md`, `protected.md` and `calendar.md` (drafting
them from the inferred goals the first time). The date in `goals.md` resets the "strategy due" clock.

## Goals, non-goals, anti-goals

- **Goals:** a backlog whose NOW is right every Monday; nothing dated is missed; good buried ideas
  get a hearing; the same process in every space, with only the plan differing.
- **Non-goals:** writing code or opening PRs; closing or creating beads unattended; cloud runs
  (the stores are local, and the plan is private); spaces without a plan.
- **Anti-goals (a failure even if it works):** a protected bead demoted or shelved without the user;
  a change that can't be undone exactly; a change the user only learns of from someone else; a
  summary too long to review in ten minutes.

## Left to the builder

File layout inside the plan and run directories; the exact allowlist syntax; whether participation
is a `spaces.toml` field; how `wb-groom` reports progress; test seams (follow the existing ones:
fake `bd`, fake `claude`, `WORKBENCH_CONFIG`, a state-dir variable). Keep private names out of the
repo and of workbench's own beads (`scripts/check-leaks.sh`).

## Related

- The launcher hides every deferred bead, including those past their defer date, so they show
  nowhere; grooming lists them, and the launcher fix is its own bead.
- wb-7vd.5's start-here: changed by "Nothing critical out of sight" above.
