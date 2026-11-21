# Changelog

What changed for you in each workbench release. Update with `wb-update`.

## Unreleased

- Leaving a worktree session cleans up after itself. When Claude exits, the launcher runs
  `end-session --if-merged`: merged work whose bead is closed loses its worktree and branch, with
  no command to type; anything else (a pull request waiting on your yes, uncommitted work, an open
  bead) is kept, with one line saying why. Worktrees whose pull request merges later show on the
  first screen as `✦ N finished worktrees, tidy?`, which runs `wb-tidy`.
- `wb-ship`: the steps after the commit. In a worktree it pushes the branch, opens the pull
  request (or reuses the open one), waits for CI, and on green merges on a yes, by the repo's
  default method, pinned to the commit CI checked. Claude, running it, stops at green and asks
  you; a worktree session's opening prompt says so.
- `end-session` and `wb-tidy` recognise a branch squash-merged through a pull request. `gh` is
  asked (as the space's `gh_account`) for a merged pull request from the branch into the default
  branch whose head is the worktree's HEAD. When there is one, `wb-tidy` offers the worktree
  (`squash-merged by PR #N`), and `end-session` deletes the branch without `--force`, skipping
  the push check (GitHub may have deleted the remote branch) and `before_end` (the code is already
  on the default branch). Without `gh`, or with a commit beyond the pull request, nothing changes.
- Tell us how it's going: GitHub issue forms for a bug, an idea, and an opt-in "tell us your
  setup" (every question optional, nothing collected otherwise). Links are in the README.
- `wb-setup`: a guided first run. From a fresh clone it checks your tools (offering Homebrew for
  beads, fzf and python), runs `install.sh`, asks about your project folders and writes
  `spaces.toml`, runs `bd init` where you say so, offers a Demo space with sample tasks, adds the
  launcher line to `~/.zshrc`, and ends with `wb-doctor`. Run it again to add projects.
- `wb-doctor`: checks the setup, one line per check, saying how to fix what's wrong.
- The work screen shows what blocks a bead: a blocked bead is marked `⊘` (a claimed one keeps `◐`)
  and ends with `blocked by 4, 1`; its detail pane lists `blocked by:` and `blocks:`. Start here
  no longer picks a bead whose blocker is deferred.

## 0.1 — 2026-11-17

- The first numbered release. From here on, the launcher's first screen says when a newer
  release is out (`workbench X.Y available: wb-update`), and `wb-update` pulls it, re-runs
  `install.sh` and shows what changed. It looks once a day; `update_check = false` under
  `[launcher]` in `spaces.toml` turns that off.
