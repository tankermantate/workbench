# Changelog

What changed for you in each workbench release. Update with `wb-update`.

## Unreleased

- A new space's first plan starts from the launcher: a space with beads but no plan and no
  grooming runs has `✦ start a plan` on its work screen. It opens the strategy session, which
  drafts the plan from the backlog. You no longer need a first `wb-groom run` to get there.
- A roadmap page you can open anywhere you use Claude, on the web and the phone: your open beads,
  space by space, in a page in your own Claude account. Change a title or priority, add a note or
  a new task there, and it waits on the page until the next sync. `wb-roadmap sync` (or
  `✦ sync roadmap page` under `✦ more…`) starts a Claude Code session that publishes the page the
  first time, applies the waiting changes under the same rules as planning in Desktop, and
  refreshes the page's copy. Sync happens when you ask for it, because only a Claude Code session
  on your Mac can reach the page. If a bead changed on the Mac first, the Mac's version wins and
  the page says so.
- Starting a session in the workbench's own space no longer leaves new commands unlinked: when
  `new-session` fast-forwards the workbench checkout, it re-links its commands
  (`install.sh --no-schedule`), so a command like `wb-ship` is on your PATH right away.
- `+ new space`: start a project from the launcher. The first screen's last row is now
  `✦ more…`, holding `+ new space`, `✦ open tabs` (moved there; the waiting count moved with it),
  `✦ tidy worktrees`, `✦ health check` and `✦ update`. `+ new space` asks what the project is: an
  idea or notes (git and a backlog, no branches) or a tool for you (its own space, a branch per
  task, and a CLAUDE.md saying how work is done there: fast-forward `main` on this Mac, or pull
  requests once there's an `origin`). Then Claude starts in it to shape the project into its
  first epic. `wb-new-space` does the same from any shell.
- Leaving a worktree session cleans up after itself. When Claude exits, the launcher runs
  `end-session --if-merged`: merged work whose bead is closed loses its worktree and branch, with
  no command to type; anything else (a pull request waiting on your yes, uncommitted work, an open
  bead) is kept, with one line saying why. Worktrees whose pull request merges later show on the
  first screen as `✦ N finished worktrees, tidy?`, which runs `wb-tidy`.
- `✦ something new` offers a light spec before filing the bead: two to five done-when checks,
  saved as its acceptance criteria, and a few lines of approach as its design. It's a suggestion:
  say skip, or keep the idea small, and the bead is filed without them. A bead with done-when
  checks no longer shows `shape first` in the picks, and a bead session checks them before closing.
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
