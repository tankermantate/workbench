# Session knows its bead

**Status:** built (2026-10-22), checked with `claude -p`; not yet used interactively · **Date:** 2026-10-21 · bead wb-7vd.1 (epic wb-7vd: workbench through the whole
life of the work, not just the start)

## Why

Workbench starts a session on a bead and then steps away. From there the bead lives only in the
opening prompt, and the prompt scrolls away. Partway through a session you can't say what it's
for, how far along it is, or what's left. Compaction makes it worse: the summary keeps what was
done and loses what it was for. Sessions also drift. One session started as "something new" and
went on to cover about eight beads (search, short ids, a leak check, a scrub, launch planning,
research, this design), with a compaction in the middle. Nothing ever showed which bead it was on.

What the user said:
- The pain is **losing my place mid-flight**: what the work is for, whether the goal has moved,
  where it stands against the target.
- Awareness, not a gate. When a session moves on to another bead, **ask: continue in this session
  or start a fresh one**. It's the user's call.
- Workbench is a private tool for now. This isn't launch work.

## What you get

1. **The status line names the bead.** A session started from workbench shows its bead in the
   status line: `◆ x1y Fix fabric PO search`. A session with no bead yet shows `◇ no bead`. Context
   use stays where it is in your own status line (see "Your status line" below).
2. **Claude gets the goal back after compaction.** After `/compact`, auto-compaction or a resume,
   Claude is handed the bead's id, title and goal again, plus its acceptance criteria when the bead
   has them. Claude can then say what the session is for without being told.
3. **A session without a bead picks one up.** A "something new" session starts with `◇ no bead`.
   The first time Claude claims a bead in it, the session is on that bead: the status line changes
   and you see a one-line notice, `→ this session is now on x1y`.
4. **Claiming a second bead asks.** When Claude claims a different bead from the one the session is
   on, it stops and asks you before working on it:
   - **Continue here:** the session moves to the new bead.
   - **Start fresh:** the new bead goes back to open (`bd update <id> --status open`), so the
     launcher starts it normally, in its own worktree where the space uses worktrees. Claude tells
     you to open it from the launcher in a new tab, and this session carries on with its own bead.
5. **Closing the bead closes out the session.** When the session's own bead is closed, the
   session's job is done. Instead of quietly carrying on with whatever comes next, it winds down:
   - The status line shows `✓ x1y done · close this session`.
   - Claude does the close-out: in a worktree space it runs `end-session` once the work is merged
     or pushed, as today.
   - Claude then tells you to type `/exit` and start the next bead from the launcher, in a fresh
     session with a fresh context.

   - **When the bead belongs to an epic** (its direct parent), the close-out shows what is left in
     that epic, so you can carry on in the same train of thought while this session's context is
     fresh, instead of stopping at a fraction of what matters:

     ```
     ✓ e1 closed · this session is done
       invoice sync: 2 of 10 done
       next here:  e4  NOW P3  Match invoices to POs by supplier ref
                   e3  P1  Flag invoices with no matching PO
       in another session:  e5  Import supplier refs
     ```

     `N of M` counts every child, shelved ones too, so the total doesn't shrink as work is put
     aside. "Next here" is the epic's open beads in the work screen's order (NOW, NEXT, the rest;
     priority within), at most five, leaving out epics, icebox beads and blocked ones (a blocker
     outside the epic counts as still blocking). Beads in progress are listed under "in another
     session", never offered. Nothing from outside the epic is shown. Claude gets the same list,
     reads the closed bead's notes and the epic's description, and says so if they name a different
     next step. If you pick one, Claude claims it and moves the session onto it with `wb-focus`;
     otherwise it finishes the close-out as above. A worktree session can't carry on (its worktree
     goes at close-out, and the next bead needs its own), so there the list is for information:
     Claude finishes the close-out and names the bead to start from the launcher in a fresh session. When every bead in the epic is closed, it says
     the epic looks finished and offers to close it. A bead with no epic gets none of this: that work
     is over, and the next session starts fresh.

   Workbench can't shut the session itself: as far as the Claude Code docs show, no hook can end an
   interactive session or clear its context. So the session says it's done, and you close it.
   If Claude claims another bead in a session whose bead is done, it still asks "continue here or
   start fresh", and recommends starting fresh, unless the bead is in the same epic as the closed
   one in a plain space: then it recommends continuing here, since the context carries over.
6. **The session is named after the bead,** so `claude --resume` lists it by bead rather than by a
   generated label.

Filing beads isn't switching. `bd create` mid-session, for an idea or a bug spotted on the way, is
capture. The session stays on its bead and nothing asks.

## Scope

**Only sessions workbench starts** (launcher, `new-session`, a resume from the launcher). Workbench
passes its hooks with `claude --settings` at launch, so nothing is written into any repo or into
`~/.claude`. A `claude` you start by hand behaves exactly as today.

**Non-goals:**
- checking work against a definition of done, or a Stop hook of any kind
- blocking, refusing or warning on anything, including token or context thresholds
- backlog hygiene (stalled in-progress beads, icebox, inflow): that's wb-7vd.2
- replacing or editing anyone's own status line

**Anti-goals:**
- a hook failure that breaks, slows or clutters a session. Awareness hooks fail *silent*: on any
  error they exit 0 with no output. This is the opposite of the fail-closed rule for the
  session scripts, and that's deliberate: these hooks guard nothing.
- a status line that calls `bd`. It runs after every reply, so it reads one small file and nothing
  else.
- a reminder injected into every prompt. The goal comes back at session start and after compaction,
  not on each turn.

## How it works

### The binding

One small file per session records which bead it's on:

```
~/.cache/workbench/sessions/<session_id>.json
{"bead": "acme-x1y", "title": "Fix fabric PO search", "root": "/path/to/space/root",
 "since": "2026-10-21T14:02:00Z", "done": false}
```

`WB_STATE_DIR` overrides `~/.cache/workbench` (the test seam). The session id comes from the hook's
stdin, or from `CLAUDE_CODE_SESSION_ID` in commands Claude runs. Both were checked on this machine.
The title is cached in the file when the binding is written, so the status line never needs `bd`.
`root` is the space root, so hooks know where to run `bd show`.

Files older than 30 days are pruned by the SessionStart hook, on the way past.

### At launch

`_wb_claude` (launcher) and `new-session` add the following to the `claude` command:
- `--settings <file>`: workbench's hooks, with absolute paths under `WORKBENCH_HOME`, written by
  `wb-session-hook settings-file` to `~/.cache/workbench/claude-settings.json`. A file, not inline
  JSON, because the terminal shows the command line in its window title (2026-10-22).
- `WB_BEAD=<id>`, `WB_SPACE_ROOT=<root>` and, in a worktree session, `WB_WORKTREE=<worktree top>`
  in the environment, set for this one command the way `CLAUDE_CONFIG_DIR` is, never exported to
  the shell. "Something new" doesn't set `WB_BEAD`. `WB_WORKTREE` is how the hooks know to keep
  claim notes in step.

The session is named by the hooks (`sessionTitle`) rather than by `claude -n`. That way one code
path names it at launch and again when the bead changes mid-session.

A spike on 2026-10-21 confirmed that an environment variable set on the `claude` command reaches
SessionStart and UserPromptSubmit hooks.

For a resume of a claimed bead (`_wb_claude continue`), `WB_BEAD` is that bead.

### Hooks

All hooks are python, in one script with a subcommand per event (`bin/wb-session-hook <event>`),
reading the hook JSON on stdin.

- **SessionStart and SessionEnd: the restore snapshot.** Both start `wb-restore save` in the
  background (see `2026-11-15-restore-sessions-design.md`); SessionEnd leaves its own session out.
  This is the only thing SessionEnd does.
- **SessionStart, any source.**
  - If the binding is new or its bead changed, also return `sessionTitle: "<short id> <title>"`.
  - If there's no binding for this session and `WB_BEAD` is set, bind it, reading the title with
    `bd show --json` from `WB_SPACE_ROOT` and the same timeout as `wb-backlog`.
  - A launch bead that is already closed binds as `done`.
  - `/clear` starts a new session id, so it binds the launch bead again (`WB_BEAD`), even after
    "continue here" moved the session to another bead. Run `wb-focus <id>` again after a `/clear`.
  - If the session is bound, return `additionalContext`: the bead id, title, the first ~1,500
    characters of the description, and the acceptance criteria if there are any. Then one sentence:
    "Before you start work on a different bead (claiming it or setting it in progress), ask the
    user whether to continue in this session or start a fresh one."
  - On `startup` with a bead, the opening prompt already says `bd show`, so this repeats it. That's
    accepted: it's one short block, and it keeps a single code path.
- **PostToolUse, matcher `Bash`.** It reads `tool_input.command` for a bead being claimed: `bd
  update <id…>` with `--claim` or `--status in_progress` (`=` or space), or `bd create … --claim`
  with the new id read from the tool output. It ignores the command when the tool failed.
  - No binding yet: bind the claimed bead and return `systemMessage: "→ this session is now on
    <short id> <title>"`.
  - Bound to the same bead: nothing.
  - Bound to a different bead: return `additionalContext` telling Claude that the session is on X,
    it just claimed Y, and it must ask the user before working on Y: continue here (run `wb-focus
    Y`) or start fresh (put Y back to open; tell the user to start it from the launcher). Also return
    `systemMessage: "→ claimed <Y> while this session is on <X>"`, so the user sees it even if
    Claude doesn't.
  - `bd close` of the bound bead (any form that names it): mark the binding `done` and return
    `additionalContext` telling Claude the session's bead is closed. It should finish the close-out
    (`end-session` in a worktree space, once the work is merged or pushed), then tell the user to
    `/exit` and start the next bead from the launcher. Also return `systemMessage: "✓ <short id>
    closed · this session is done"`. A bead with a parent also records `epic` in the binding, and
    both messages carry the epic's close-out (item 5): `bd list --parent <epic> --all` and `bd show
    <epic>`, about 2s on a big store. If bd can't list the children, the plain close-out stands.
  - A claim in a session whose binding is `done`: the same ask as a different bead, saying the
    session's bead is closed and recommending start fresh (continuing here when the bead is in
    the binding's `epic`).
  - A claim counts only when `bd show` reports the bead in progress **and** assigned to you
    (`$BEADS_ACTOR`, else `git user.name`, else `$USER`, as bd resolves it). A bead someone else
    holds is in progress too, and `bd update … --claim 2>&1 | tail` hides bd's refusal.
  - The ask names `wb-focus` by its full path, because it's on PATH only once `install.sh` has
    linked it.
  - Several ids in one command: the first id that differs from the binding counts. A bind takes
    the first id.
- **UserPromptSubmit.** If the binding changed since the session was last named, return
  `hookSpecificOutput.sessionTitle` with the new bead. It returns nothing otherwise, so there's no
  per-prompt reminder.

### `wb-focus`

`bin/wb-focus` (python, sharing the binding code with the hooks):
- `wb-focus <id>` binds the current session (`CLAUDE_CODE_SESSION_ID`) to that bead. Claude runs it
  when the user chooses "continue here".
- `wb-focus` with no argument prints the current binding.
- `wb-focus --clear` unbinds the session.

It errors out of a Claude session, like `tabname`.

**Claim notes stay in step.** In a worktree session, `end-session` finds the bead from the claim
note naming the worktree (`wb-backlog claimed`). So whenever a session is bound to a bead that has
no claim note naming this worktree (the hook's pickup in a "something new" session, or `wb-focus`),
it appends one in the `new-session` form: `Branch: <branch> (worktree at <path>)`. `wb-backlog
claimed` then has to prefer, among the beads whose current note names the worktree, the one
updated most recently (`updated_at`), not the first one listed. After "continue here" both the old
and the new bead name the worktree, and the new one has just been noted. The old bead is
left as it is (still in progress), and you decide about it. A failed note write is reported in the
notice (`→ … (claim note not written: <reason>)`) but doesn't fail the hook.

### Your status line

Workbench ships `bin/wb-statusline-bead`. It reads the status line's stdin JSON and prints the
segment: `◆ x1y Fix fabric PO search` (title cut to 40 characters), `✓ x1y done · close this
session`, `◇ no bead`, or nothing when the
session isn't a workbench one. It reads only the binding file.

Your status line is private config, so wiring it in is a private step, not part of this repo: call
`wb-statusline-bead` from your own script with the same stdin, and put its output where you want.
The README shows a two-line example. A user without a status line can point `statusLine` at
`wb-statusline-bead` directly.

Workbench's `--settings` must not set `statusLine`, because that would replace yours.

## Testing

Plain bash tests in the usual style:
- Hooks are fed recorded hook JSON on stdin, with `WB_STATE_DIR` in a temp dir and `tests/fake/bd`
  for `bd show`. Cases:
  - bind at start from `WB_BEAD`
  - no binding without `WB_BEAD`
  - re-inject on `compact`, including the acceptance criteria
  - each claim form binds a session that has no bead yet
  - a claim of the same bead is silent
  - a claim of a different bead produces the ask and the notice
  - `bd create` without `--claim` is ignored
  - a failed tool call is ignored
  - `bd close` of the bound bead marks it done; closing a different bead doesn't
  - a claim after done asks, recommending fresh
  - malformed stdin or an unreadable `bd` exits 0 silently
  - prune
- `wb-focus`: binds, prints, clears, and refuses outside a session.
- `wb-statusline-bead`: each of the three outputs, the cut title, and a missing or corrupt file.
- Launcher and `new-session` dry runs show `--settings` and the env vars, and show no
  `WB_BEAD` for "something new".
- By hand, once:
  - start a bead from the launcher, see the status line, run `/compact`, and ask Claude what the
    session is for
  - claim a second bead and see the ask
  - start a plain `claude` and see nothing new

## Builder: verify before building on it

Checked 2026-10-21 with throwaway `claude -p` sessions:
- **Hooks from `--settings` run alongside other settings' hooks.** A SessionStart hook from
  `--settings` and one from the project's `.claude/settings.json` both ran.
- **`--continue` keeps the same `session_id`.** SessionStart fired again with `source: resume` and
  the same id. The SessionStart bind from `WB_BEAD` covers a resume anyway.

Checked 2026-10-22 against the built hooks, in a scratch repo with real `bd` and `claude -p` sessions:
- **Bound at launch.** Asked "what is this session for?", Claude named the bead. Asked to claim
  another, it asked first, which comes from the start-of-session context.
- **Same-turn ask.** PostToolUse `additionalContext` reaches Claude in the same turn. Made to claim
  a second bead, it quoted the message and asked "continue or start fresh" before doing anything.
- **After compaction.** After `/compact` (the transcript shows the compact boundary), the bead's
  context was there again, and Claude gave the bead and its acceptance criterion without running a
  command.
- **Close-out.** After `bd close` of the session's bead, the binding was `done`, the status line
  segment read `✓ … done · close this session`, and Claude said to `/exit` and start the next bead
  from the launcher.

`bd create --claim`: bd 1.1.0 has no such flag, so that path stays unused until bd adds one.

Not yet seen: the status line in an interactive session, which needs your status line script to
call `wb-statusline-bead` (a private step).

## Left to the builder

- The exact hook JSON in `--settings`.
- The regex for spotting claims. It must cover the forms above and not much more.
- The wording of the injected blocks, kept short.

Calls made in design (by the assistant, open to change):
- python for the hooks; `~/.cache` for the binding
- no reminder on every prompt
- the status line shows the bead but no warning colour
- 30-day prune
- "start fresh" puts the new bead back to open, because a bead claimed without a worktree note
  reads as a stale claim in the launcher, which would refuse to start it
- binding appends a claim note so `end-session` finds the right bead; the old bead is left alone
