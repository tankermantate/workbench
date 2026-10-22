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
./install.sh               # link bin/* into ~/.local/bin, print the ~/.zshrc line
scripts/check-leaks.sh     # before any push: no private names in tracked files
new-session <bead-id>|<space-key> [topic]   # worktree session for a worktrees = true space
end-session [<worktree>]                    # remove it once the work is merged/pushed/verified
```

## Architecture Overview

User guide: `README.md`. Designs: `docs/specs/` (launcher, session scripts, session's bead); plans: `docs/plans/`.

- `shell/workbench.zsh` — the launcher (zsh, sourced at the end of `~/.zshrc`). Auto-starts once, at the first prompt, via a self-removing precmd hook; `launch` runs it by hand. Two fzf screens (space, then work), a numbered menu without fzf, then the handoff to Claude.
- `bin/wb-spaces` (python) — reads `~/.config/workbench/spaces.toml` and prints one 13-field TSV row per space; every other piece reads spaces through it.
- `bin/wb-backlog`, `bin/wb-ui` (python) — a space's beads through `bd`, and the fzf screen helpers.
- `bin/wb-session-hook`, `bin/wb-focus`, `bin/wb-statusline-bead` (python) with `lib/wb_session.py` — keep a launched Claude session on its bead: hooks passed with `claude --settings`, the session→bead record in `~/.cache/workbench/sessions/`, and the status line segment.
- `bin/new-session`, `bin/end-session` (bash) with `lib/session.sh` — worktree sessions for `worktrees = true` spaces; the space's private setup runs as `on_create` / `before_end` hooks from `spaces.toml`.
- `prompts/*.txt` — the opening prompts handed to Claude.

## Conventions & Patterns

- Nothing private in the repo: real spaces, paths, accounts and hook scripts live in `~/.config/workbench/`. Examples use made-up names (Acme). Run `scripts/check-leaks.sh` before any push.
- Shell scripts target macOS's bash 3.2; python needs 3.11+ (`tomllib`).
- Every behaviour change starts with a failing test. Tests are plain bash (`tests/test_*.sh`, asserts in `tests/lib.sh`), with fakes for `bd`, `gh`, `claude` and `new-session` in `tests/fake/`, steered by env seams (`WORKBENCH_CONFIG`, `WB_BD`, `WB_GH`, `WB_WORKTREES_DIR`, `WORKBENCH_DRY_RUN`, `FAKE_*`).
- Fail closed: a step that can't tell whether work is safe refuses and says how to override.
- Comments say why, not what. Keep a spec's text in step when its behaviour changes.
