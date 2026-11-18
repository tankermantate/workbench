# Changelog

What changed for you in each workbench release. Update with `wb-update`.

## Unreleased

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
