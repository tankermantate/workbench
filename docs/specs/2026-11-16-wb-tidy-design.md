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
- its branch is merged into the repo's default branch: an ancestor of it (local or `origin/`),
  or squash-merged, which ancestry can't see. Squash-merged means `gh` reports a merged pull
  request from the branch into the default branch whose head is exactly the branch's tip
  (`lib/wb_merged.py`, shared with `end-session`). That's one `gh pr list` per repo, made only
  when some branch isn't an ancestor, as the first space on the repo with a `gh_account` (a
  token for the call, so gh's active account is left alone). The note says `squash-merged by
  PR #N`. When `gh` can't answer (missing, logged out, slow), the branch stays unmerged and the
  reason says gh couldn't check;
- `git status --porcelain` is empty;
- no live Claude session's folder is inside it (`lib/wb_live.py`, as `wb-tabs` and `wb-restore`
  find them; no `lsof`);
- the bead linked to it is closed (`wb_worktree` metadata, else the last claim note; as `end-session`).

A worktree no bead names is kept, saying `wb-tidy --no-bead` offers it on the rest alone. A closed
bead is the only sign the work is done: merged and clean only say no code would be lost, and for
an `explore/` worktree the value is often the conversation, which can't be resumed once its folder
is gone. "No bead" is also not always true: a bead whose claim note doesn't name its worktree
reads as none (two of the first real run's ten were such, both closed, their notes replaced by a
later `bd update --notes`). Decided 2026-11-16, after a first cut that offered them by default.
Since then new-session also links the bead in its metadata, which a notes rewrite can't drop; beads
claimed before that and since rewritten still read as none.

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

`wb-tidy --count` prints only how many would be offered (exit 1 when it can't tell). The launcher's
first screen reads it to show `✦ N finished worktrees, tidy?` (wb-kvx.22): sessions the launcher
started are closed out at exit, so what's left here is mostly work merged after its session left.
