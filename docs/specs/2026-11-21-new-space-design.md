# New space from the launcher, and a commands submenu

Bead: wb-kvx.24.1 (epic wb-kvx.24, "Bridge planning in Claude and building in Claude Code").

## Why

Most new projects start in a new, empty folder. Today turning one into a space means leaving the
launcher, running `wb-setup` (built for the first run), answering its questions, and remembering
`bd init`. Claude then starts in a folder that knows nothing about the process the established
spaces follow. A new project should get a process sized to what it is from its first minute: a
folder, git, a backlog, the right Claude account, a CLAUDE.md that says how work is done there,
and a first conversation that shapes the project into its epic.

Not every project is an app, and not every project goes on GitHub. So the first question is what
the project is, and the setup follows from the answer.

This is also the setup code a Claude Desktop chat will call to start a project (wb-kvx.24.2), so
the steps live in code that never prompts.

## Goals

- `+ new space` in the launcher makes a new project, right-sized to what it is, and starts Claude
  shaping it.
- A **commands submenu** keeps the first screen about projects: one `✦ more…` row opens every
  special command, today's and future ones.
- The setup steps are a non-interactive core, callable from a chat tool later.

Non-goals:
- Taking over an existing folder (stays `wb-setup`'s job; see "Existing folders").
- Anything on GitHub. Publishing a space (a private repo, push, PRs) is its own bead,
  wb-kvx.24.4, which adds "something to ship" to the question below once it works.
- The Desktop chat tool (wb-kvx.24.2) and carrying ideas between Code and a chat (wb-kvx.24.3).

Anti-goals: a half-made space that the launcher can't read or `wb-doctor` flags; any private name
(real space, account, path) in the repo; a busier first screen; asking more than a new project
needs.

## The commands submenu

The first screen keeps its space rows and `[q]`, and its `✦ open tabs` row becomes `✦ more…`,
still showing the waiting count (`N waiting on you`) so nothing is lost at a glance.

```
Space? ›
  Acme app         4 ready
  Side › gadget    1 ready
  ✦ more…          2 waiting on you
  [q] just give me a shell
```

Choosing it opens screen "More?", drawn by `wb-ui render-more`, in fzf or the numbered menu like
the other screens:

```
More? ›
  + new space          start a project: folder, git, backlog, first epic
  ✦ open tabs          every tab's space, task and status        2 waiting on you
  ✦ tidy worktrees     end the finished ones (wb-tidy)
  ✦ health check       wb-doctor
  ✦ update             wb-update
  ← back
```

- `← back` and esc return to the space list (not to a plain shell, unlike esc on the first screen).
- `✦ open tabs` does what the old first-screen row did, then returns to the submenu.
- `✦ tidy worktrees`, `✦ health check` and `✦ update` run the command in the launcher's shell,
  then wait for Enter (their output would be lost to fzf's redraw) and return to the submenu.
  `✦ update` is listed always; `wb-update` itself says when there's nothing new.
- The one exception is a nudge: `✦ N finished worktrees, tidy?` (wb-kvx.22) stays on the first
  screen, after `✦ more…`, because it only shows when there is something to tidy.
- Commands that act across workbench go here, never on the first screen. Commands about one space
  (review, strategy, something new, and later publish) stay on that space's work screen.

## `+ new space`

### What it asks (`bin/wb-new-space`)

1. **What is it?**

   ```
   What is it? ›
     an idea or notes     backlog only, no branches
     a tool for me        a branch per task, merged into main on this Mac      (default)
   ```

   "Something to ship" (a private GitHub repo and pull requests) joins this list when
   wb-kvx.24.4 lands; until then it isn't shown, so nothing offered is half-built.

2. **Where** (an idea or notes only). An idea goes in an *area*: a glob space whose glob is a
   plain `<folder>/*` and whose `beads` isn't `false`, read from `wb-spaces`, never named in code.
   One area: used without asking. Several: asked which. None (a new user, or only other globs):
   it becomes its own `[[space]]` under `~/dev` with `worktrees = false`. A tool for me is always
   its own space, `~/dev/<name>`.
3. **Name.** Also the folder name. Refused when it's empty, starts or ends with a space, has `/`
   or a control character, starts with `.`, the folder exists, or a space already has that label
   (case-insensitive), as `wb-setup` refuses. In an area with `worktrees = true` the folder's name
   is its key, so a name that is already a worktree space's key is refused too: `wb-spaces` would
   refuse the whole config otherwise.
4. **Account** (own space only; an area's folder has its area's). The distinct `claude_config`
   values the spaces already use, plus "the default account" (no `claude_config`); the default is
   the account of the most spaces. Shown as the folder path, as `spaces.toml` holds it.
5. **Confirm.** One summary of what will be made, then `Make it? [Y/n]`: Enter, `y` or `yes`
   makes it; `n`, `no` or `q` stops; anything else is asked again. Esc (a plain read sees it as a
   character) or end of input at any question stops, with nothing made.

| | an idea or notes | a tool for me |
|---|---|---|
| folder | in an area, or `~/dev/<name>` | `~/dev/<name>` |
| `spaces.toml` | nothing (area) or a `[[space]]`, `worktrees = false` | a `[[space]]`, `worktrees = true`, `space_key` |
| git, `bd init` | yes | yes |
| CLAUDE.md process section | no | yes |
| sessions | in the folder | a worktree and branch per task |

An area's folder inherits everything from its area (account, `worktrees`, hooks). If that area
has `worktrees = true` its folder also gets the process section and branch-per-task sessions; the
folder name is its key. (Builder's call.)

### What it does (`lib/wb_newspace.py`, never prompts)

`create(kind, name, area=None, account=None) -> result` runs these in order, stopping at the
first failure. `wb-new-space --json --kind idea|tool ...` exposes it without prompts and prints
the result as JSON, so the Desktop tool (a separate python 3.11 process) can call it without
importing workbench internals. (Builder's call.)

1. Make the folder (`os.mkdir`, never over an existing one).
2. `git init -b main`, so the branch name doesn't depend on the user's git config.
3. `bd init --non-interactive`, which writes `.beads`, AGENTS.md and CLAUDE.md and commits them.
   That commit is `main`'s first, which `new-session` needs to branch from (checked 2026-11-21 in
   a fresh `git init -b main`: bd init commits on `main`).
4. When the space has worktrees: append workbench's process section to CLAUDE.md and commit it.
5. When it's its own space: append a `[[space]]` (`name`, `root`, `beads = true`, `worktrees`,
   a unique `space_key` made as `wb-setup` makes one when `worktrees = true`, `claude_config` when
   not the default) to `spaces.toml` atomically, then read the config back through `wb-spaces`. If
   it doesn't read back, or the new space isn't in it (with its key), the file goes back to what
   it was.

With no `spaces.toml` yet (possible from `--json`, not from the launcher) the first own space
creates it with `wb-setup`'s header; one that exists but doesn't parse is refused, untouched. An
area's folder writes nothing to the config, but the config is still read back after it.

On failure the result names each step that ran, what it left (the folder, the commit), and the
command to finish or remove it. `spaces.toml` is never left changed by a failed run. The folder is
not deleted automatically: removing files is the user's call.

The pieces `wb-setup` already has that never prompt (`slug`, `space_toml`, the backlog init, the
append and read-back) move to this module and `wb-setup` imports them, so the two can't drift.
`wb-setup` runs on macOS's python 3.9, so the module stays 3.9-safe (no `tomllib`, no 3.10+
syntax); reading `spaces.toml` back goes through `wb-spaces`, which already has the right python.

### The CLAUDE.md process section

A template, `lib/new-space-templates/CLAUDE.md`, appended below bd's own managed block (bd keeps
ownership of that block). One section serves with or without GitHub: what happens at the end
depends on whether the repo has an `origin`, so adding a remote later (by hand, or by
wb-kvx.24.4) switches the process with nothing to rewrite.

bd's block defaults agents to its Conservative profile (no commits or pushes unless asked), so the
section opens by opting the repository in to the Team-maintainer profile, as workbench's own
CLAUDE.md does: it names that it overrides bd prime's "no git operations" line, and keeps the
carve-out that a current "do not commit" from the user wins. Without it agents follow bd's block
and none of the process runs.

It says, with made-up example names only:

- Every session works on its own branch in its own worktree; nothing is committed on `main`
  directly.
- Every behaviour change starts with a failing test; a bead closes only with the project's tests
  passing, once it has any.
- Closing a bead: tests; `bd close` with a reason; stage the touched files by name; one commit per
  bead (`<type>: <summary> (<bead-id>)`) with a body saying why; then
  - **with an `origin`:** push the branch and open a pull request; `main` changes only through a
    merged pull request, which is the owner's call;
  - **without one:** bring the branch into `main` on this Mac: refuse if the main checkout is
    dirty or not on `main`; `git -C <main checkout> merge --ff-only <branch>` (a worktree can't
    check out `main` while the main checkout has it); if it isn't a fast-forward because another
    session merged first, rebase the branch onto `main` (it was never pushed), run the tests
    again, and retry. That is the only way `main` changes.
- Never: force-push, `--no-verify`, rewrite anything pushed, merge your own pull request unless
  asked.
- The project's why, decisions and open questions live in its epic bead (description, design,
  notes), so a Claude chat and a Claude Code session can both pick it up.

Checked 2026-11-21: with no `origin`, `end-session` and `wb-tidy` test "merged" against local
`main` (`bin/end-session` line 200, `bin/wb-tidy` line 150), so a fast-forwarded branch counts as
merged and its worktree can be ended. No tooling change is needed.

### What happens next

The launcher re-reads `wb-spaces` (its row list is from before the new space existed), finds the
new row by its root, and starts the "something new" session there with a new opening prompt,
`prompts/new-project.txt`: shape the project (what it's for, what done looks like) and file its
epic with the why in the description and decisions in the design, then its first beads. A space
with worktrees goes through `new-session` like any worktree space's something-new; with no remote
it skips the fetch and branches from local `main` (`bin/new-session` lines 88-99).

## Existing folders

Not offered. A folder that exists is refused with: `<path> exists; to make it a space, run
wb-setup`. Decided 2026-11-21: existing folders only came up when moving projects from plain
beads to workbench, which `wb-setup` already handles.

## Approaches considered

1. **A non-prompting core with a terminal front end (chosen).** The core is what the Desktop chat
   tool will call; the launcher and `wb-new-space` stay thin.
2. **A `--new` mode in `wb-setup`.** Less new code, but its questions are woven into one first-run
   flow and it must stay 3.9-safe end to end; the chat tool would have to pull the logic out later.
3. **All in the launcher's zsh.** Fast, but a chat tool can't call it and the config writing would
   exist twice, in two languages.

And for sizing: one setup for every project (a GitHub repo always, or never) was rejected on
2026-11-21. Not every project is an app or gets published, and the owner wants to decide on GitHub
when it's worth it. Publishing moved to wb-kvx.24.4, one code path used both at creation and
later, from the space's work screen.

## Testing

Tests first, as always (`tests/test_new_space.sh`, launcher cases in the existing launcher tests):

- the core against a temp `WORKBENCH_CONFIG`, a temp parent folder and the `bd` fake: each kind's
  steps and order (the table above), refusals (existing folder, taken name, bad name),
  `spaces.toml` unchanged after a failed read-back, the generated `space_key`, `claude_config` only
  when not default, the CLAUDE.md section present exactly when the space has worktrees, `git init
  -b main`, the area choice (one, several, none, `beads = false` skipped), `--json` output;
- `wb-setup`'s existing tests still pass after the move;
- the launcher: a `WB_TEST_PICK_MORE` seam on the pattern of `WB_TEST_PICK_SPACE` and
  `WB_TEST_PICK_WORK`; `✦ more…` carries the waiting count; the tests that picked `tabs` from the
  first screen pick `more` then `tabs`; `+ new space` ends in a `WORKBENCH_DRY_RUN` Claude start
  in the new folder with the new-project prompt; `← back` returns to the space list.

## Left to the builder

- Exact wording of the questions and the summary, in the launcher's existing voice.
- The new-project prompt's text, modelled on `prompts/something-new.txt`.
- Where the own-space parent (`~/dev`) is set: a constant now; a `[launcher]` key later if anyone
  asks.
