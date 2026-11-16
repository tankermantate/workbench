# wb-tidy: end the worktrees whose work is finished

Bead: wb-9ug.3 (epic wb-9ug). Finished worktrees pile up: a 2026-11-15 check found 32, 19 GB,
24 with no session open. `end-session` removes one safely, but only when you name it.

## Goal

One command lists every worktree, offers the finished ones, and ends the ones you keep ticked.
Non-goals: deciding anything `end-session` decides (it still checks pushes and runs `before_end`),
and ever touching a folder it can't place.

## What's offered

A worktree is offered when all of these hold:

- its repo is a `worktrees = true` space's (the space is picked as `end-session` picks it: the
  one whose key names the folder, else the first on that repo);
- its branch is merged into the repo's default branch (local or `origin/`), checked by ancestry,
  so a squash-merged branch reads as unmerged and is kept;
- `git status --porcelain` is empty;
- no live Claude session's folder is inside it (`lib/wb_live.py`, as `wb-tabs` and `wb-restore`
  find them; no `lsof`);
- the bead whose current claim note names it is closed. A worktree no bead names is offered on the
  rest alone, since every commit in it is already on the default branch. (A judgement call: most
  bead-less worktrees are `explore/` ones.)

Everything else is listed as `keep` with the first reason that holds. Folders in
`WB_WORKTREES_DIR` that no space's repo has as a worktree are listed and never offered.

## Failing closed

- `ps` fails, or a live claude has no pid file in any known config dir (its folder can't be
  told): nothing is offered, exit 1.
- A space's beads can't be read (`bd list --all`): nothing in that space is offered.
- No terminal to answer on: nothing ends, exit 1.

## Ending

The offered ones go to fzf, all ticked (Tab unticks); without fzf, one yes/no. Each ticked one
gets `end-session <path>` in turn, its output shown. The first refusal stops the run and says how
many were left as they were. `WORKBENCH_DRY_RUN` lists and stops.
