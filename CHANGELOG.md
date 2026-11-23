# Changelog

What changed for you in each workbench release. Update with `wb-update`.

## Unreleased

- `+ new space`: start a project from the launcher. The first screen's last row is now
  `✦ more…`, holding `+ new space`, `✦ open tabs` (moved there; the waiting count moved with it),
  `✦ tidy worktrees`, `✦ health check` and `✦ update`. `+ new space` asks what the project is: an
  idea or notes (git and a backlog, no branches) or a tool for you (its own space, a branch per
  task, and a CLAUDE.md saying how work is done there: fast-forward `main` on this Mac, or pull
  requests once there's an `origin`). Then Claude starts in it to shape the project into its
  first epic. `wb-new-space` does the same from any shell.
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
