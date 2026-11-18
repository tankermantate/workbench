# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## This Repository's Profile: Team-maintainer, Branches and Pull Requests

This repository opts in to the Team-maintainer profile: agents commit finished, tested work when they close a bead, push the session's branch and open a pull request. `main` changes only through a merged pull request with green CI (GitHub enforces it); merging is the owner's call. This is the "repository profile" bd's conservative default defers to, so it overrides `bd prime`'s "Git authority: no git operations" line. A current "do not commit" from the user still wins.

Every session works on its own branch in its own worktree: the workbench space has `worktrees = true`, so the launcher and `new-session` make one. If you find yourself on `main` in the main checkout, don't commit there: make a worktree with `new-session <bead-id>` and carry the work over.

Closing a bead, in order. Stop at the first failure and report it; don't commit around it.

1. `tests/run.sh`: every suite reports 0 failed.
2. `bd close <id> --reason="<what shipped; what did not>"`, with no private names (bead text stays local, but keep it shareable).
3. `git status`, then stage by name the files the work touched. Never `git add -A` or `git add .`; leave out anything dirty you didn't change, and say so.
4. One commit per bead on the session's branch (never `main`), message `<type>: <summary> (<bead-id>)` like `git log`, a body saying why, and the co-author trailer.
5. `scripts/check-leaks.sh`: clean, the bead db included (with a remote set, a bead-db finding fails too). If the new commit leaks, `git reset --soft HEAD~1`, fix it, commit again.
6. `git push -u origin HEAD`, then `gh pr create --fill` (or add commits to the branch's open pull request). Never push when step 5 found anything. If a push is rejected, stop and report it; don't pull, rebase or force.
7. Hand off: the commit hash, test and leak results, the pull request link, what's left open. Once the owner merges it, `end-session` removes the worktree.

Never: commit or push to `main`, `bd dolt push` (the bead db stays local; `no-push` is on), a force push, amend, rebase or force anything already pushed, `--no-verify`, merge your own pull request unless the owner asks, or a commit with failing tests.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Build & Test

```bash
tests/run.sh               # all tests (plain bash; fakes for bd/new-session/claude)
./install.sh               # link bin/* into ~/.local/bin, schedule weekly grooming and the 10-minute session snapshot (--no-schedule skips), print the ~/.zshrc line
scripts/check-leaks.sh     # before any push: no private names in tracked files, history or the bead db
new-session <bead-id>|<space-key> [topic]   # worktree session for a worktrees = true space
end-session [<worktree>]                    # remove it once the work is merged/pushed/verified
```

## Architecture Overview

User guide: `README.md`. Designs: `docs/specs/` (launcher, session scripts, session's bead, planning rituals, tabs view, restore); plans: `docs/plans/`.

- `shell/workbench.zsh` — the launcher (zsh, sourced at the end of `~/.zshrc`). Auto-starts once, at the first prompt, via a self-removing precmd hook; `launch` runs it by hand. Two fzf screens (space, then work), a numbered menu without fzf, then the handoff to Claude.
- `bin/wb-spaces` (python) — reads `~/.config/workbench/spaces.toml` and prints one 13-field TSV row per space; every other piece reads spaces through it.
- `bin/wb-backlog`, `bin/wb-ui` (python) — a space's beads through `bd`, and the fzf screen helpers. `lib/wb_touched.py` gives a claim's idle age with grooming's own writes walked back (wb-backlog and the grooming judge both use it).
- `bin/wb-session-hook`, `bin/wb-focus`, `bin/wb-statusline-bead` (python) with `lib/wb_session.py` — keep a launched Claude session on its bead: hooks passed with `claude --settings`, the session→bead record in `~/.cache/workbench/sessions/`, and the status line segment. `bin/wb-statusline-space` is the one naming the session's space (and whether it's a worktree), from `wb-spaces`.
- `bin/wb-tabs` (python) lists every open terminal tab with its space, bead, goal and status, joining `ps`, Claude's `sessions/<pid>.json` and the session records, with one `bd list` per store and never `bd show`; `lib/wb_space.py` is the folder-to-space logic it shares with the status line.
- `bin/wb-health` (python) prints uptime and swap, saying when a restart is due; the launcher shows it in its screen headers.
- `bin/wb-restore` (python) saves every live session and, after a restart, queues them; each new tab's launcher claims one and resumes it with `claude --resume`. `lib/launchd/workbench.restore-save.plist.in` saves every 10 minutes. `lib/wb_live.py` is the live-session lookup (ps and Claude's pid files) it shares with `wb-tabs` and `wb-tidy`.
- `bin/wb-tidy` (python) lists every worktree, offers the finished ones (merged, clean, no live session, bead closed; `--no-bead` adds those with none) and runs `end-session` on the ticked ones, stopping at the first refusal. Spec: `docs/specs/2026-11-16-wb-tidy-design.md`.
- `bin/wb-mcp` (python) puts a persona's beads in the Claude Desktop app: an MCP server on stdio (`serve`) limited to the spaces whose `claude_config` account is the one Desktop is signed in as, editing through `bd` under grooming's protected-work rules; `connect` / `check` / `disconnect` manage Desktop's config. Spec: `docs/specs/2026-11-17-plan-in-claude-design.md`.
- `bin/wb-update` (python) is releases: `VERSION` and `CHANGELOG.md` say what's installed and what changed, a `vX.Y` tag on `main` is a release. `wb-update --notice` puts `workbench X.Y available: wb-update` on the launcher's first screen (cached, one background `git ls-remote` a day, fail-silent, off with `update_check = false`); `wb-update` pulls, re-runs `install.sh` and shows the changelog since your version. Spec: `docs/specs/2026-11-17-updates-design.md`.
- `bin/new-session`, `bin/end-session` (bash) with `lib/session.sh` — worktree sessions for `worktrees = true` spaces; the space's private setup runs as `on_create` / `before_end` hooks from `spaces.toml`.
- `bin/wb-groom` (python) with `lib/wb_groom.py` and `lib/wb_judge_bd.py` — planning rituals: weekly grooming (a read-only `claude -p` judge, then policy-checked apply through `bd` with an exact undo record), and the review and strategy sessions the launcher offers. Each space's plan is private, in `~/.config/workbench/plans/<space>/` (templates in `lib/plan-templates/`); runs are kept in `~/.local/state/workbench/groom/`. `lib/launchd/workbench.groom.plist.in` is the Saturday 06:00 agent `install.sh` writes.
- `prompts/*.txt` — the opening prompts handed to Claude (`groom.txt`, `review.txt` and `strategy.txt` for the rituals).

## Conventions & Patterns

- Nothing private in the repo: real spaces, paths, accounts and hook scripts live in `~/.config/workbench/`. Examples use made-up names (Acme). Run `scripts/check-leaks.sh` before any push.
- Shell scripts target macOS's bash 3.2; python needs 3.11+ (`tomllib`).
- Every behaviour change starts with a failing test. Tests are plain bash (`tests/test_*.sh`, asserts in `tests/lib.sh`), with fakes for `bd`, `gh`, `claude` and `new-session` in `tests/fake/`, steered by env seams (`WORKBENCH_CONFIG`, `WB_BD`, `WB_GH`, `WB_WORKTREES_DIR`, `WB_PLANS_DIR`, `WB_GROOM_DIR`, `WB_TODAY`, `WORKBENCH_DRY_RUN`, `FAKE_*`).
- Fail closed: a step that can't tell whether work is safe refuses and says how to override.
- Comments say why, not what. Keep a spec's text in step when its behaviour changes.
