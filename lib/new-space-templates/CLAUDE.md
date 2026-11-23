
## How work is done here (workbench)

This repository opts in to the **Team-maintainer** profile: agents commit finished, tested work
when they close a bead, and bring it into `main` as described below. This is the "repository
profile" bd's conservative default defers to, so it overrides `bd prime`'s "Git authority: no git
operations" line. A current "do not commit" from the user still wins.

Every session works on its own branch in its own worktree (workbench's launcher and `new-session`
make one). Nothing is committed on `main` directly.

Every behaviour change starts with a failing test. A bead closes only with the project's tests
passing, once it has any.

Closing a bead, in order. Stop at the first failure and report it; don't work around it.

1. Run the project's tests: all pass.
2. `bd close <id> --reason="<what shipped; what did not>"`.
3. `git status`, then stage by name the files the work touched. Never `git add -A` or `git add .`.
4. One commit per bead on the session's branch, message `<type>: <summary> (<bead-id>)`
   (e.g. `feat: export to CSV (acme-a1b)`), with a body saying why.
5. Bring it into `main`:
   - **If the repository has an `origin` remote:** `git push -u origin HEAD`, then open a pull
     request (`gh pr create --fill`). `main` changes only through a merged pull request, and
     merging is the owner's call.
   - **If it has none:** merge on this Mac. Refuse if the main checkout has uncommitted changes or
     isn't on `main`. Then `git -C <main checkout> merge --ff-only <branch>` (a worktree can't check
     out `main` while the main checkout has it). If that isn't a fast-forward because another
     session merged first, rebase the branch onto `main` (it was never pushed), run the tests
     again, and retry. This is the only way `main` changes.
6. Hand off: the commit, the test result, the pull request link or the merge, what's left open.

Never: force-push, `--no-verify`, amend or rebase anything already pushed, or merge your own pull
request unless the owner asks.

The project's why, decisions and open questions live in its epic bead: the description says why,
the design field holds what's decided, and dated notes hold what's still open. A Claude chat and a
Claude Code session can both pick the project up from there, so keep it current when either
changes.
